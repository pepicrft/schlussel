const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Main library module
    const lib_mod = b.addModule("schlussel", .{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Static library for C FFI
    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "schlussel",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/lib.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Link libc for FFI
    lib.linkLibC();

    // Install artifacts
    b.installArtifact(lib);

    // Generate C header
    lib.installHeader(b.path("include/schlussel.h"), "schlussel.h");

    // Unit tests
    const lib_unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/lib.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);

    // Example: GitHub Device Flow
    const github_device_example = b.addExecutable(.{
        .name = "github_device_flow",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/github_device_flow.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "schlussel", .module = lib_mod },
            },
        }),
    });
    b.installArtifact(github_device_example);

    const run_github_device = b.addRunArtifact(github_device_example);
    const run_github_device_step = b.step("example-github-device", "Run the GitHub device flow example");
    run_github_device_step.dependOn(&run_github_device.step);

    // Example: Automatic Refresh
    const auto_refresh_example = b.addExecutable(.{
        .name = "automatic_refresh",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/automatic_refresh.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "schlussel", .module = lib_mod },
            },
        }),
    });
    b.installArtifact(auto_refresh_example);

    const run_auto_refresh = b.addRunArtifact(auto_refresh_example);
    const run_auto_refresh_step = b.step("example-auto-refresh", "Run the automatic refresh example");
    run_auto_refresh_step.dependOn(&run_auto_refresh.step);

    // CLI executable
    const cli_exe = b.addExecutable(.{
        .name = "schlussel",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/cli.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "schlussel", .module = lib_mod },
            },
        }),
    });
    b.installArtifact(cli_exe);

    // Docs generation
    const docs_mod = b.createModule(.{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = .Debug,
    });

    const docs = b.addLibrary(.{
        .linkage = .static,
        .name = "schlussel_docs",
        .root_module = docs_mod,
    });

    const install_docs = b.addInstallDirectory(.{
        .source_dir = docs.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    const docs_step = b.step("docs", "Generate documentation");
    docs_step.dependOn(&install_docs.step);
}
