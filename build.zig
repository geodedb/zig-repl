// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2026 CodePros

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // -Dwith_otel: compile in otel instrumentation. OFF by default; when
    // off the otel dependency is never resolved and the seam collapses
    // to a comptime-known no-op (verified by
    // otel/scripts/verify-consumer-noop.sh).
    const with_otel = b.option(
        bool,
        "with_otel",
        "Compile in otel instrumentation (off by default; zero overhead when off)",
    ) orelse false;

    // Forward otel build options so the upstream package is configured
    // identically across all consumers in the build graph. Without this,
    // each consumer's `b.lazyDependency("otel", ...)` materialises a
    // DISTINCT otel Module instance (different `build_options` ⇒ different
    // package keys), and zig 0.16 errors with `file exists in modules
    // 'otel' and 'otel0'` when transitive imports overlap.
    const otel_use_devnw_tls = b.option(
        bool,
        "otel_use_devnw_tls",
        "Forward to upstream otel: HTTPS via DevNW tls",
    ) orelse false;
    const otel_disabled = b.option(
        bool,
        "otel_disabled",
        "Forward to upstream otel: comptime-disable",
    ) orelse false;
    const otel_profiles = b.option(
        bool,
        "otel_profiles",
        "Forward to upstream otel: experimental profiles",
    ) orelse false;
    const otel_use_devnw_grpc = b.option(
        bool,
        "otel_use_devnw_grpc",
        "Forward to upstream otel: DevNW gRPC",
    ) orelse false;

    // Build options module — materialise ONE shared `build_options`
    // module so every consumer (lib, observability seam, tests) imports
    // the SAME instance. Without the shared instance Zig 0.16 may emit
    // "file exists in modules X and X0" when two independent
    // `addOptions` modules end up sharing a transitive file path.
    const build_options = b.addOptions();
    build_options.addOption([]const u8, "package_name", "repl");
    build_options.addOption(bool, "with_otel", with_otel);
    // Single source of truth for the version: parse `.version` out of
    // build.zig.zon at configure time and expose it as `repl.version`.
    // This keeps src/repl.zig from drifting away from build.zig.zon (the
    // packaging manifest); a test in src/repl.zig re-parses the zon and
    // asserts the match so future drift fails CI.
    const version = parseZonVersion(b);
    build_options.addOption([]const u8, "version", version);
    const build_options_mod = build_options.createModule();

    // Observability seam (otel). Declared as a SHARED NAMED MODULE so
    // every consumer (`repl`, plus the disabled/enabled seam tests)
    // resolves to the same source file via `@import("observability")`.
    // Using a relative `@import("observability.zig")` from each module
    // would trip Zig's "file exists in modules X and Y" error because
    // the file would be pulled into multiple module trees. The seam's
    // `enabled` flag tracks `build_options.with_otel`; when off, every
    // helper compiles to a comptime-known no-op and the otel dependency
    // is never resolved. The optional `otel` import is wired below
    // inside the `if (with_otel)` block.
    const observability_mod = b.addModule("observability", .{
        .root_source_file = b.path("src/observability.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "build_options", .module = build_options_mod },
        },
    });

    // Library module - the main REPL library
    const repl_mod = b.addModule("repl", .{
        .root_source_file = b.path("src/repl.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    repl_mod.addImport("build_options", build_options_mod);
    repl_mod.addImport("observability", observability_mod);

    // Example executable demonstrating library usage
    const example_exe = b.addExecutable(.{
        .name = "repl-example",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/example.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    example_exe.root_module.addImport("repl", repl_mod);
    b.installArtifact(example_exe);

    // Run example step
    const run_step = b.step("run", "Run the example REPL application");
    const run_cmd = b.addRunArtifact(example_exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // Unit tests for the library
    const lib_test_mod = b.createModule(.{
        .root_source_file = b.path("src/repl.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    lib_test_mod.addImport("build_options", build_options_mod);
    lib_test_mod.addImport("observability", observability_mod);
    const lib_tests = b.addTest(.{
        .root_module = lib_test_mod,
    });
    const run_lib_tests = b.addRunArtifact(lib_tests);

    // Integration tests
    const integration_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    integration_tests.root_module.addImport("repl", repl_mod);
    const run_integration_tests = b.addRunArtifact(integration_tests);

    // Test step
    const test_step = b.step("test", "Run all unit tests");
    test_step.dependOn(&run_lib_tests.step);
    test_step.dependOn(&run_integration_tests.step);

    // ========================================================================
    // Observability seam (otel) — gated dependency + seam tests
    // ========================================================================

    // Disabled-mode no-op tests. Verifies `build_options.with_otel == false`
    // is the default and that the seam's public surface returns a
    // comptime-known no-op when otel is off. The test is skip-guarded for
    // the enabled build so it passes under both flag values.
    const observability_disabled_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/observability_disabled_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "repl", .module = repl_mod },
                .{ .name = "build_options", .module = build_options_mod },
            },
        }),
    });
    const run_observability_disabled_tests = b.addRunArtifact(observability_disabled_tests);
    test_step.dependOn(&run_observability_disabled_tests.step);

    // Enabled-mode smoke test. Skips under -Dwith_otel=false; under
    // -Dwith_otel=true it installs an in-memory recorder, drives one
    // eval span through the seam, and asserts the recorder captured it.
    // Compiles cleanly under both flag values because the otel-namespace
    // identifiers sit behind `comptime if (enabled)` short-circuits.
    const observability_enabled_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/observability_enabled_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "repl", .module = repl_mod },
                .{ .name = "build_options", .module = build_options_mod },
            },
        }),
    });

    // Gated otel dependency. The `lazy = true` entry in build.zig.zon
    // means Zig only fetches the package when this branch executes; with
    // the flag off the dependency is never resolved and the produced
    // artifacts contain zero otel symbols (verified by
    // otel/scripts/verify-consumer-noop.sh).
    if (with_otel) {
        const otel_dep = b.lazyDependency("otel", .{
            .target = target,
            .optimize = optimize,
            .otel_use_devnw_tls = otel_use_devnw_tls,
            .otel_disabled = otel_disabled,
            .otel_profiles = otel_profiles,
            .otel_use_devnw_grpc = otel_use_devnw_grpc,
        }) orelse return;
        const otel_module = otel_dep.module("otel");
        // The seam itself imports `otel` when enabled. Wire it onto the
        // shared observability module so every consumer sees the same
        // otel namespace.
        observability_mod.addImport("otel", otel_module);
        repl_mod.addImport("otel", otel_module);

        // Bootstrap helper. Only registered when `-Dwith_otel=true` so
        // the disabled build never compiles otel-touching code. Gated
        // from src/repl.zig via
        // `if (observability.enabled) @import("observability_init")`.
        const observability_init_mod = b.addModule("observability_init", .{
            .root_source_file = b.path("src/observability_init.zig"),
            .target = target,
            .imports = &.{
                .{ .name = "otel", .module = otel_module },
                .{ .name = "observability", .module = observability_mod },
            },
        });
        repl_mod.addImport("observability_init", observability_init_mod);
        // Unit-test root compiles from `src/repl.zig`, which transitively
        // `@import`s `observability_init` under the
        // `if (observability.enabled)` branch. Wire the same import here
        // so that test graph resolves under `-Dwith_otel=true`.
        lib_test_mod.addImport("observability_init", observability_init_mod);

        // Re-resolve otel for the smoke test so its `@import("otel")`
        // resolves; the disabled build skips this branch entirely.
        observability_enabled_tests.root_module.addImport("otel", otel_module);
    }
    const run_observability_enabled_tests = b.addRunArtifact(observability_enabled_tests);
    test_step.dependOn(&run_observability_enabled_tests.step);

    // Format check step
    const fmt_step = b.step("fmt", "Check code formatting");
    const fmt = b.addFmt(.{
        .paths = &.{ "src", "tests", "examples", "build.zig" },
        .check = true,
    });
    fmt_step.dependOn(&fmt.step);

    // ==========================================================================
    // Example executables from examples/ directory
    // ==========================================================================

    // Helper function to add an example executable
    const ExampleInfo = struct {
        name: []const u8,
        file: []const u8,
        description: []const u8,
    };

    const examples = [_]ExampleInfo{
        .{ .name = "basic", .file = "examples/basic.zig", .description = "Basic REPL setup" },
        .{ .name = "completions", .file = "examples/completions.zig", .description = "Tab completion example" },
        .{ .name = "history", .file = "examples/history.zig", .description = "Command history handling" },
        .{ .name = "multiline", .file = "examples/multiline.zig", .description = "Multi-line input example" },
        .{ .name = "colors", .file = "examples/colors.zig", .description = "Terminal colors and styling" },
        .{ .name = "calculator", .file = "examples/calculator.zig", .description = "Calculator REPL" },
        .{ .name = "vi", .file = "examples/vi_mode.zig", .description = "Vi keybindings example" },
        .{ .name = "shell", .file = "examples/shell.zig", .description = "Simple shell example" },
    };

    // Create a step to build all examples
    const examples_step = b.step("examples", "Build all example executables");

    for (examples) |example| {
        // Create executable
        const exe = b.addExecutable(.{
            .name = b.fmt("repl-{s}", .{example.name}),
            .root_module = b.createModule(.{
                .root_source_file = b.path(example.file),
                .target = target,
                .optimize = optimize,
                .link_libc = true,
            }),
        });
        exe.root_module.addImport("repl", repl_mod);
        b.installArtifact(exe);
        examples_step.dependOn(&exe.step);

        // Create run step for this example
        const run_example = b.addRunArtifact(exe);
        run_example.step.dependOn(b.getInstallStep());

        if (b.args) |args| {
            run_example.addArgs(args);
        }

        const step_name = b.fmt("run-{s}", .{example.name});
        const run_example_step = b.step(step_name, example.description);
        run_example_step.dependOn(&run_example.step);
    }
}

/// Extract the `.version = "X.Y.Z"` string from build.zig.zon so the
/// version exposed as `repl.version` has a single source of truth. Reads
/// the manifest at configure time; panics loudly if the field is missing
/// (a malformed manifest is a build-author error, not a runtime concern).
fn parseZonVersion(b: *std.Build) []const u8 {
    const zon = b.build_root.handle.readFileAlloc(
        b.graph.io,
        "build.zig.zon",
        b.allocator,
        @enumFromInt(64 * 1024),
    ) catch @panic("build: cannot read build.zig.zon to resolve version");
    const marker = ".version";
    const marker_idx = std.mem.indexOf(u8, zon, marker) orelse
        @panic("build: no .version field in build.zig.zon");
    const after = zon[marker_idx + marker.len ..];
    const open = std.mem.indexOfScalar(u8, after, '"') orelse
        @panic("build: malformed .version in build.zig.zon (no opening quote)");
    const rest = after[open + 1 ..];
    const close = std.mem.indexOfScalar(u8, rest, '"') orelse
        @panic("build: malformed .version in build.zig.zon (no closing quote)");
    // Dupe so the slice outlives the file buffer's lifetime expectations.
    return b.allocator.dupe(u8, rest[0..close]) catch @panic("build: OOM dupe version");
}
