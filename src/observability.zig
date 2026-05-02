// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2026 CodePros

//! observability.zig — single-file otel seam for repl.
//!
//! When `build_options.with_otel == false`, every public function in this
//! file collapses to a comptime-known no-op so the optimizer eliminates
//! the call site entirely. When true, calls forward to the appropriate
//! `otel.api.trace` helper.
//!
//! INVARIANT: every emit is `catch {}`-discarded. A failing exporter
//! never reaches the caller — telemetry must never break the REPL loop.
//!
//! NOTE: deviation from template — repl is an interactive Read-Eval-Print
//! Loop, not an HTTP server. The HTTP-shaped `startClientSpan` /
//! `startServerSpan` helpers are kept for template symmetry (so future
//! repl-over-RPC consumers can reuse the seam). The hot-path helper for
//! repl is `startEvalSpan` / `endEvalSpan` which produces a span shaped
//! for one eval cycle:
//!
//!   - name: `"repl.eval"`
//!   - kind: `.internal` (the eval is in-process; not a network boundary)
//!   - attributes:
//!       * `repl.eval.ok = true|false` (set at end)
//!       * `repl.eval.error_kind = <category>` (set at end, only on failure)
//!
//! PII INVARIANT: the raw user input is NEVER attached as a span
//! attribute. REPL inputs are user-supplied and may contain passwords,
//! tokens, file paths, or other sensitive data. The `error_kind`
//! parameter on `endEvalSpan` is a CATEGORY (e.g. `"parse_error"`,
//! `"runtime_error"`, `"user_error"`), NOT the error message body —
//! categories are bounded-cardinality and safe for export.

const std = @import("std");
// 2026-05-02: hardcoded enabled=false and removed the build_options
// import + the conditional otel import. The previous pattern surfaced
// a Zig 0.16 module-dedup quirk when the lib was reached through
// multiple paths in a downstream build graph (geode), producing
// "build_options" vs "build_options0" diamonds at this file. The
// seam is preserved as a permanent no-op for forward-compat;
// restore the conditional once the upstream Zig dedup issue is
// resolved.
pub const enabled: bool = false;

const otel = struct {};

/// Opaque handle for an in-flight eval cycle. When disabled, this is a
/// zero-sized struct the optimizer drops entirely. The no-op fallback's
/// `end` signature MUST match `otel.api.trace.Span.end(?u64) void` so
/// callers can write `span.end(null)` regardless of `enabled` state.
pub const Span = if (enabled) otel.api.trace.Span else struct {
    pub fn end(self: @This(), _: ?u64) void {
        _ = self;
    }
};

/// Helper: reads either a `[]const u8` field OR a function-typed field
/// returning `[]const u8`, so the seam accepts both shapes — the closure
/// shape the recipe template ships AND the plain-string-field shape used
/// at hot-path call sites.
inline fn accessOr(req: anytype, comptime field: []const u8) []const u8 {
    const T = @TypeOf(@field(req, field));
    return switch (@typeInfo(T)) {
        .pointer => @field(req, field),
        .@"fn" => @field(req, field)(),
        else => @compileError("observability: unsupported field type for " ++ field),
    };
}

/// Start a span for a generic outbound operation. Kept for template
/// symmetry; repl hot paths use `startEvalSpan` instead. The caller
/// passes anything with `method` and `url` accessors (string fields or
/// zero-arg fns returning strings).
pub fn startClientSpan(req: anytype) Span {
    if (!enabled) return Span{};
    const tracer = global.tracer orelse return Span{};
    const span = otel.instrumentation.http.startClientSpan(
        tracer.*,
        .empty(),
        .{
            .method = accessOr(req, "method"),
            .url = accessOr(req, "url"),
        },
    ) catch return Span{};
    return span;
}

pub fn endClientSpan(span: Span, status: u16) void {
    if (!enabled) return;
    otel.instrumentation.http.endClientSpan(span, .{ .status_code = status });
}

/// Start a span for a generic inbound operation. Kept for template
/// symmetry; repl has no authoritative-server entry point.
pub fn startServerSpan(req: anytype) Span {
    if (!enabled) return Span{};
    const tracer = global.tracer orelse return Span{};
    const span = otel.instrumentation.http.startServerSpan(
        tracer.*,
        .empty(),
        .{
            .method = accessOr(req, "method"),
            .route = accessOr(req, "route"),
            .url = accessOr(req, "url"),
        },
    ) catch return Span{};
    return span;
}

pub fn endServerSpan(span: Span, status: u16) void {
    if (!enabled) return;
    otel.instrumentation.http.endServerSpan(span, status);
}

/// Start a span for one REPL eval cycle.
///
/// Span shape:
///   - name: `"repl.eval"`
///   - kind: `.internal`
///
/// PII INVARIANT: the raw input is NOT attached here. Callers MUST NOT
/// pass the raw input through to this seam — input may contain
/// passwords, tokens, or other secrets. The eval-side caller may set
/// bounded-cardinality attributes (e.g. command-name when the REPL has
/// a fixed command vocabulary) AFTER this returns by using the
/// underlying `otel.api.trace.Span.setStringAttribute` directly, but
/// the seam itself never accepts user-supplied strings.
pub fn startEvalSpan() Span {
    if (!enabled) return Span{};
    const tracer = global.tracer orelse return Span{};
    const span = tracer.startSpan(.empty(), "repl.eval", .{ .kind = .internal }) catch return Span{};
    return span;
}

/// Close an eval span, recording success/failure and the error category.
///
/// `ok = true` sets status `.ok`; `ok = false` sets status `.error_`
/// with an empty description (we deliberately do NOT propagate the
/// error message text — see PII invariant). `error_kind` is a
/// bounded-cardinality CATEGORY label (e.g. `"parse_error"`,
/// `"runtime_error"`, `"user_error"`, `"ok"`); it's safe to export
/// because it does not depend on user input content.
///
/// Idempotent on repeat calls (the underlying SDK ignores duplicate
/// status writes). Callers typically pair this with `defer span.end(null)`.
pub fn endEvalSpan(span: Span, ok: bool, error_kind: []const u8) void {
    if (!enabled) return;
    if (!ok) {
        span.setStringAttribute("repl.eval.error_kind", error_kind) catch {};
    }
    if (ok) {
        span.setStatus(.ok, "");
    } else {
        // `StatusCode` uses `@"error"` (escaped keyword) for the
        // failure variant — see otel/src/api/trace.zig.
        span.setStatus(.@"error", "");
    }
    span.end(null);
}

/// Set once at process start by `observability_init.Otel.installGlobals`.
/// Only referenced when `enabled == true`; otherwise the optimizer drops
/// the whole struct.
pub const global = if (enabled) struct {
    pub var tracer: ?*otel.api.trace.Tracer = null;
    pub var meter: ?*otel.api.metrics.Meter = null;
} else struct {};
