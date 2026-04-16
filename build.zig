// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2026 CodePros

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Library module - the main REPL library
    const repl_mod = b.addModule("repl", .{
        .root_source_file = b.path("src/repl.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

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
    const lib_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/repl.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
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
