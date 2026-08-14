const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Engine
    const sdl3_mod = b.dependency("sdl3", .{
        .target = target,
        .optimize = optimize,
        .ext_image = true,
        .c_sdl_preferred_linkage = .dynamic,
    }).module("sdl3");

    const zmath_mod = b.dependency("zmath", .{
        .target = target,
        .optimize = optimize,
    }).module("root");

    const zgui = b.dependency("zgui", .{
        .optimize = optimize,
        .target = target,

        .backend = .sdl3_gpu,
        .shared = true,
        .with_implot = true,
    });

    const obj_mod = b.dependency("obj", .{ .target = target, .optimize = optimize }).module("obj");

    const options = b.addOptions();
    const debug_gpu = b.option(bool, "debug_gpu", "Enable GPU debugging functionality") orelse false;
    options.addOption(bool, "debug_gpu", debug_gpu);

    const game_mod = b.createModule(.{
        .root_source_file = b.path("src/game/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    game_mod.addImport("sdl", sdl3_mod);
    game_mod.addImport("zmath", zmath_mod);
    game_mod.addImport("obj", obj_mod);
    game_mod.addImport("zgui", zgui.module("root"));
    game_mod.addOptions("options", options);
    game_mod.linkLibrary(zgui.artifact("imgui"));

    const game_exe = b.addExecutable(.{
        .name = "game",
        .root_module = game_mod,
    });
    b.installArtifact(game_exe);

    const shader_step = compileShaders(b, target, game_mod) catch |e| std.debug.panic("Error compiling shaders {}", .{e});

    // Steps
    const game_artifact = b.addRunArtifact(game_exe);

    const run_step = b.step("run", "Run");
    run_step.dependOn(b.getInstallStep());
    run_step.dependOn(shader_step);
    run_step.dependOn(&game_artifact.step);

    const check = b.step("check", "Check if binary compiles");
    check.dependOn(&game_exe.step);

    const test_step = b.step("test", "Run unit tests");
    const unit_tests = b.addTest(.{
        .root_module = game_mod,
    });
    const test_artifcat = b.addRunArtifact(unit_tests);
    test_step.dependOn(&test_artifcat.step);
}

fn compileShaders(b: *std.Build, target: std.Build.ResolvedTarget, game_mod: *std.Build.Module) !*std.Build.Step {
    const io = b.graph.io;

    const step = b.step(
        "shaders",
        "Compile Slang shaders",
    );

    const shaders = b.addWriteFiles();

    var shader_source: std.ArrayList(u8) = .empty;
    defer shader_source.deinit(b.allocator);

    var dir = try std.Io.Dir.cwd().openDir(
        io,
        "shaders",
        .{ .iterate = true },
    );
    defer dir.close(io);

    var walker = try dir.walk(b.allocator);
    defer walker.deinit();

    while (try walker.next(io)) |entry| {
        if (entry.kind != .file)
            continue;

        if (!std.mem.endsWith(u8, entry.path, ".slang"))
            continue;

        const input = b.path(
            b.fmt("shaders/{s}", .{entry.path}),
        );

        const path = b.dupe(entry.path[0 .. entry.path.len - ".slang".len]);
        std.mem.replaceScalar(u8, path, '.', '_');

        const cmd = b.addSystemCommand(&.{
            "slangc",
        });

        cmd.addFileArg(input);

        const is_vertex = std.mem.containsAtLeast(u8, entry.path, 1, ".vert");

        if (is_vertex) {
            cmd.addArgs(&.{ "-entry", "vertexMain", "-stage", "vertex" });
        } else {
            cmd.addArgs(&.{
                "-entry", "fragmentMain",
                "-stage", "fragment",
            });
        }

        switch (target.result.os.tag) {
            .linux => {
                cmd.addArgs(&.{
                    "-target", "spirv",
                });

                cmd.addArg("-o");
                const spirv = cmd.addOutputFileArg(
                    b.fmt("{s}.spv", .{path}),
                );

                step.dependOn(&cmd.step);

                _ = shaders.addCopyFile(
                    spirv,
                    b.fmt("{s}.spv", .{path}),
                );

                try shader_source.appendSlice(
                    b.allocator,
                    b.fmt(
                        "pub const {s} = @embedFile(\"{s}.spv\");\n",
                        .{ path, path },
                    ),
                );
            },

            .macos => {
                cmd.addArgs(&.{
                    "-target", "metal",
                });

                cmd.addArg("-o");
                const metal = cmd.addOutputFileArg(
                    b.fmt("{s}.metal", .{path}),
                );

                step.dependOn(&cmd.step);

                _ = shaders.addCopyFile(
                    metal,
                    b.fmt("{s}.metal", .{path}),
                );

                try shader_source.appendSlice(
                    b.allocator,
                    b.fmt(
                        "pub const {s} = @embedFile(\"{s}.metal\");\n",
                        .{ path, path },
                    ),
                );
            },

            .windows => {
                cmd.addArgs(&.{
                    "-target", "dxil",
                });

                cmd.addArg("-o");
                const dxil = cmd.addOutputFileArg(
                    b.fmt("{s}.dxil", .{path}),
                );

                step.dependOn(&cmd.step);

                _ = shaders.addCopyFile(
                    dxil,
                    b.fmt("{s}.dxil", .{path}),
                );

                try shader_source.appendSlice(
                    b.allocator,
                    b.fmt(
                        "pub const {s} = @embedFile(\"{s}.dxil\");\n",
                        .{ path, path },
                    ),
                );
            },

            else => {
                return error.UnsupportedTarget;
            },
        }
    }

    const shader_zig = shaders.add(
        "shaders.zig",
        shader_source.items,
    );

    game_mod.addAnonymousImport("shaders", .{
        .root_source_file = shader_zig,
    });

    step.dependOn(&shaders.step);

    return step;
}
