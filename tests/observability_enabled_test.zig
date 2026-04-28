// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2026 CodePros

//! Verifies one REPL eval span lands in an in-memory recorder when
//! `-Dwith_otel=true`. Skips under the disabled build.
//!
//! NOTE: deviation from template — we exercise the seam directly via
//! the in-memory recorder rather than driving a real REPL session
//! (which would require a TTY). The seam's behaviour is identical:
//! `startEvalSpan` -> `endEvalSpan` enters and leaves one tracer span
//! representing one eval cycle.
//!
//! The `otel` module is only added to this test root when
//! `-Dwith_otel=true`. To compile cleanly under both flag values we
//! gate the otel-namespace identifiers behind `comptime if (enabled)`
//! and stub the alias to an empty struct when the flag is off — that
//! branch is dead code in the disabled build but the import resolves.

const std = @import("std");
const build_options = @import("build_options");
const repl = @import("repl");

const otel = if (build_options.with_otel) @import("otel") else struct {};

test "one REPL eval span recorded when otel enabled" {
    if (!repl.observability.enabled) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var resource = try otel.sdk.resource.defaultResource(allocator);
    defer resource.deinit();
    try resource.attributes.putString(otel.semconv.service_name, "repl-test");

    var recorder = otel.exporters.in_memory.Recorder.init(allocator);
    defer recorder.deinit();
    var tp = try otel.sdk.trace.TracerProvider.init(allocator, .{
        .resource = &resource,
        .default_exporter = recorder.spanExporter(),
    });
    defer tp.deinit();

    var tracer = tp.tracer(.{ .name = "repl-test" });
    repl.observability.global.tracer = &tracer;
    defer repl.observability.global.tracer = null;

    const span = repl.observability.startEvalSpan();
    repl.observability.endEvalSpan(span, true, "ok");

    try tp.forceFlush(1_000);
    try std.testing.expectEqual(@as(usize, 1), recorder.spans.items.len);

    // Verify span name shape: "repl.eval".
    const recorded = recorder.spans.items[0];
    try std.testing.expectEqualStrings("repl.eval", recorded.name);

    // Sanity: input content must NEVER appear as an attribute. This test
    // does not drive raw input through the seam, but we still verify
    // no `repl.input` / `code.input` attribute leaks via the helper.
    for (recorded.attribute_kv) |kv| {
        try std.testing.expect(!std.mem.eql(u8, kv.key, "repl.input"));
        try std.testing.expect(!std.mem.eql(u8, kv.key, "code.input"));
    }
}
