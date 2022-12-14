const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    // b.setPreferredReleaseMode(.Debug);
    const mode = b.standardReleaseOptions();

    const pipewire = std.build.Pkg{ .name = "pipewire", .source = .{ .path = "src/pipewire.zig" } };

    // const exe = b.addExecutable("zig-pw", "examples/roundtrip.zig");
    // exe.setTarget(target);
    // exe.setBuildMode(mode);
    // exe.linkLibC();
    // exe.linkSystemLibrary("libpipewire-0.3");
    // exe.addPackage(pipewire);

    // exe.install();

    inline for ([_][]const u8{ "roundtrip", "volume" }) |example| {
        const exe = b.addExecutable(example, "examples/" ++ example ++ ".zig");
        // const exe = b.addExecutable("zig-pw", "examples/roundtrip.zig");
        exe.setTarget(target);
        exe.setBuildMode(mode);
        exe.linkLibC();
        exe.linkSystemLibrary("libpipewire-0.3");
        exe.addPackage(pipewire);

        exe.install();

        const run_cmd = exe.run();
        run_cmd.step.dependOn(b.getInstallStep());

        if (b.args) |args| {
            run_cmd.addArgs(args);
        }

        const run_step = b.step("run-" ++ example, "Run " ++ example);
        run_step.dependOn(&run_cmd.step);
    }

    const exe_tests = b.addTest("src/pipewire.zig");
    exe_tests.setTarget(target);
    exe_tests.setBuildMode(mode);
    exe_tests.addCSourceFile("src/spa/test_pod.c", &[_][]const u8{});
    exe_tests.linkLibC();
    exe_tests.linkSystemLibrary("libpipewire-0.3");

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&exe_tests.step);
}
