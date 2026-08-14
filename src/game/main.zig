const std = @import("std");

const sdl = @import("sdl");
const zmath = @import("zmath");

const Renderer = @import("Renderer.zig");
const Camera = @import("Camera.zig");
const gui = @import("gui.zig");

pub fn main(init: std.process.Init) !void {
    // SDL3 currently does not free everything
    // https://codeberg.org/7Games/zig-sdl3/issues/225
    // _ = try sdl.setMemoryFunctionsByAllocator(init.gpa);

    // defer std.process.cleanExit(init.io);

    sdl.log.setAllPriorities(.verbose);
    sdl.log.setLogOutputFunction(
        void,
        sdl.extras.loggers.zigLog,
        null,
    );

    const flags: sdl.InitFlags = .everything;

    try sdl.setAppMetadata(
        "game",
        "0.0.1",
        "net.zargor.game",
    );

    try sdl.init(flags);
    defer sdl.quit(flags);

    var renderer = try Renderer.init(init.gpa, init.io);
    defer renderer.deinit(init.gpa);

    var last_ticks = sdl.c.SDL_GetTicks();
    var camera: Camera = .{
        .position = .{ 0, 2, -5, 1 },
        .yaw = std.math.degreesToRadians(200),
    };
    var captured = false;

    run: while (true) {
        const now_ticks = sdl.c.SDL_GetTicks();

        const dt: f32 =
            @as(f32, @floatFromInt(now_ticks - last_ticks)) /
            1000.0;

        last_ticks = now_ticks;

        while (sdl.events.poll()) |event| {
            _ = gui.processEvent(&event.toSdl());

            switch (event) {
                .quit => {
                    break :run;
                },

                .key_down => |key| {
                    if (gui.zgui.io.getWantCaptureKeyboard())
                        continue;
                    switch (key.key.?) {
                        .escape => {
                            break :run;
                        },

                        .v => {
                            captured = !captured;
                            try renderer.capture_mouse(captured);

                            gui.zgui.io.setConfigFlags(.{ .no_mouse = captured });
                        },

                        else => {},
                    }
                },

                .mouse_motion => |motion| {
                    // Ignore mouse movement when the mouse isn't captured.
                    if (!captured or gui.zgui.io.getWantCaptureMouse()) {
                        continue;
                    }

                    const dx: f32 = @floatCast(motion.x_rel);
                    const dy: f32 = @floatCast(motion.y_rel);

                    const sensitivity: f32 = 0.0025;

                    const yaw = camera.yaw - dx * sensitivity;
                    const pitch = camera.pitch - dy * sensitivity;

                    camera = camera.with_yaw(yaw).with_pitch(pitch);
                },

                else => {},
            }
        }

        // -----------------------------------------------------------------
        // Camera movement
        // -----------------------------------------------------------------

        if (captured and !gui.zgui.io.getWantCaptureKeyboard()) {
            const keyboard = sdl.keyboard.getState();

            if (keyboard[@intFromEnum(sdl.Scancode.w)]) {
                camera = camera.with_forwards(dt);
            }

            if (keyboard[@intFromEnum(sdl.Scancode.s)]) {
                camera = camera.with_backwards(dt);
            }

            if (keyboard[@intFromEnum(sdl.Scancode.a)]) {
                camera = camera.with_left(dt);
            }

            if (keyboard[@intFromEnum(sdl.Scancode.d)]) {
                camera = camera.with_right(dt);
            }

            if (keyboard[@intFromEnum(sdl.Scancode.space)]) {
                camera = camera.with_up(dt);
            }

            if (keyboard[@intFromEnum(sdl.Scancode.left_shift)]) {
                camera = camera.with_down(dt);
            }
        }

        // -----------------------------------------------------------------
        // Render
        // -----------------------------------------------------------------

        renderer.draw(dt, camera) catch |e| {
            std.log.err(
                "Error while drawing {}\n",
                .{e},
            );
        };
    }
}

// -----------------------------------------------------------------------------
// Logging
// -----------------------------------------------------------------------------

pub const std_options = std.Options{
    .logFn = logFn,
};

fn logFn(
    comptime message_level: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    const time = sdl.time.Time.getCurrent() catch |e|
        std.debug.panic(
            "No current time: {s}",
            .{@errorName(e)},
        );

    const date = sdl.time.DateTime.fromTime(
        time,
        true,
    ) catch |e|
        std.debug.panic(
            "Could not convert time: {s}",
            .{@errorName(e)},
        );

    std.debug.print(
        "\x1b[90m[{0d:0>4}-{1d:0>2}-{2d:0>2} {3d:0>2}:{4d:0>2}:{5d:0>2}] \x1b[0m",
        .{
            date.year,
            @as(
                c_uint,
                @intCast(@intFromEnum(date.month)),
            ),
            date.day,
            date.hour,
            date.minute,
            date.second,
        },
    );

    std.log.defaultLog(
        message_level,
        scope,
        format,
        args,
    );
}

comptime {
    std.testing.refAllDecls(@This());
}
