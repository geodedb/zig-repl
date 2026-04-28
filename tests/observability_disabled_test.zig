// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2026 CodePros

//! Verifies the no-op invariant when -Dwith_otel=false (the default).
//!
//! repl publishes its public surface as the "repl" module rooted at
//! src/repl.zig. The seam is exposed as `repl.observability` so this test
//! drives the disabled-mode invariants through the public root.
//!
//! NOTE: deviation from template — repl is an interactive Read-Eval-Print
//! Loop. The "operation" boundary is one eval cycle (one accepted line of
//! user input). The seam therefore exposes
//! `startEvalSpan()` / `endEvalSpan(span, ok, error_kind)` which produces
//! span name `"repl.eval"` with kind `.internal`. We deliberately do NOT
//! attach the raw input as a span attribute because REPL inputs are
//! user-supplied and may contain PII / secrets.

const std = @import("std");
const repl = @import("repl");

test "build_options.with_otel exists and defaults to false" {
    const build_options = @import("build_options");
    try std.testing.expect(@hasDecl(build_options, "with_otel"));
    // The "default" assertion only holds for the disabled build. When
    // the operator forces -Dwith_otel=true, this test runs against the
    // enabled module and must skip rather than misreport the default.
    if (build_options.with_otel) return error.SkipZigTest;
    try std.testing.expectEqual(false, build_options.with_otel);
}

test "observability.enabled tracks build_options.with_otel" {
    const build_options = @import("build_options");
    try std.testing.expectEqual(build_options.with_otel, repl.observability.enabled);
}

test "REPL eval span helper is a no-op when otel disabled" {
    if (repl.observability.enabled) return error.SkipZigTest;
    var span = repl.observability.startEvalSpan();
    repl.observability.endEvalSpan(span, true, "ok");
    // Belt-and-suspenders: the seam's `endEvalSpan` already covers the
    // lifecycle; this line just verifies the no-op fallback's signature
    // matches the real API's `Span.end(?u64) void`.
    span.end(null);

    // error_kind is a category, not a message — pass an arbitrary label.
    var span2 = repl.observability.startEvalSpan();
    repl.observability.endEvalSpan(span2, false, "user_error");
    span2.end(null);
}
