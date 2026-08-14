const std = @import("std");
const builtin = @import("builtin");

const obj = @import("obj");
const options = @import("options");
const sdl = @import("sdl");
const shaders = @import("shaders");
const zmath = @import("zmath");

const Camera = @import("Camera.zig");
const GraphicsPipeline = @import("GraphicsPipeline.zig");
const gui = @import("gui.zig");
const Mesh = @import("Mesh.zig");
const Texture = @import("Texture.zig");
const Transfer = @import("Transfer.zig");
const Entity = @import("Entity.zig");

const Self = @This();

device: sdl.gpu.Device,
window: sdl.video.Window,
triangle_pipeline: GraphicsPipeline,
rotate: bool = true,
sampler: sdl.gpu.Sampler,
depth_texutre: sdl.gpu.Texture,

texture: Texture,
entities: std.ArrayList(Entity) = .empty,

light_position: [3]f32 = .{ 3, 0, 3 },
light_color: [3]f32 = @splat(1),
light_intensity: f32 = 10,

pub fn init(gpa: std.mem.Allocator, io: std.Io) !Self {
    gui.init(gpa);
    errdefer gui.deinit();

    const device = try sdl.gpu.Device.init(
        .{ .dxil = true, .msl = true, .spirv = true },
        options.debug_gpu,
        switch (builtin.os.tag) {
            .windows => "direct3d12",
            .macos => "metal",
            else => "vulkan",
        },
    );
    errdefer device.deinit();

    const window = try sdl.video.Window.init("Engine", 1920, 960, .{
        .high_pixel_density = true,
        .resizable = true,
    });
    errdefer window.deinit();

    try device.claimWindow(window);
    errdefer device.releaseWindow(window);

    try window.raise();
    try device.setSwapchainParameters(window, .sdr_linear, .vsync);

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const allocator = arena.allocator();

    const triangle_pipeline = try GraphicsPipeline.init(
        device,
        try device.getSwapchainTextureFormat(window),
        shaders.triangle_vert,
        shaders.triangle_frag,
        .{ .num_uniform_buffers = 2 },
        .{ .num_uniform_buffers = 1, .num_samplers = 1 },
    );
    errdefer triangle_pipeline.deinit(device);

    // TEX
    var transfer = try Transfer.init(allocator, &device);
    defer transfer.deinit(&device);
    try transfer.start(&device);

    const color_map = try Texture.load_from_file(&transfer, .{
        .device = &device,
        .path = "assets/textures/colormap.png",
        .usage = .{ .sampler = true },
        .flip = .{ .vertical = true },
    });

    const window_width, const window_height = try window.getSizeInPixels();
    const depth_texture = try device.createTexture(.{
        .usage = .{ .depth_stencil_target = true },
        .format = .depth32_float,
        .width = @intCast(window_width),
        .height = @intCast(window_height),
        .layer_count_or_depth = 1,
        .num_levels = 1,
    });

    var entities: std.ArrayList(Entity) = .empty;
    const car = try Mesh.init(allocator, io, "sedan-sports.obj");
    defer car.deinit(allocator);
    for (0..2) |x| {
        for (0..2) |z| {
            const entity = try Entity.spawn(
                car,
                zmath.f32x4(@floatFromInt(5 * x), 0, @floatFromInt(5 * z), 0),
                zmath.qidentity(),
                device,
                &transfer,
            );
            try entities.append(gpa, entity);
        }
    }

    const cmd_buf = try device.acquireCommandBuffer();
    const copy_pass = cmd_buf.beginCopyPass();

    transfer.finish(&device, &copy_pass);

    copy_pass.end();
    try cmd_buf.submit();

    const sampler = try device.createSampler(.{
        .mag_filter = .linear,
        .min_filter = .linear,
    });

    gui.init_gpu(
        &window,
        &device,
        try device.getSwapchainTextureFormat(window),
    );
    // gui.zgui.getStyle().scaleAllSizes(2.0);
    // gui.zgui.getStyle().font_size_base *= 5.5;

    return .{
        .device = device,
        .window = window,
        .triangle_pipeline = triangle_pipeline,
        .entities = entities,
        .texture = color_map,
        .sampler = sampler,
        .depth_texutre = depth_texture,
    };
}

pub fn capture_mouse(self: *Self, capture: bool) !void {
    if (!sdl.c.SDL_SetWindowRelativeMouseMode(self.window.value, capture)) {
        return error.SDLError;
    }
}

pub const VertexGlobalUniforms = extern struct {
    viewProjectionMat: zmath.Mat,
};
pub const VertexLocalUnforms = extern struct {
    modelMat: zmath.Mat,
    normalMat: zmath.Mat,
};

pub const FragmentUniforms = extern struct {
    light_position: [3]f32,
    _pad: f32 = 0,
    light_color: [3]f32,
    _pad1: f32 = 0,
    light_intensity: f32,
    _pad2: f32 = 0,
    view_position: [3]f32,
    _pad3: f32 = 0,
};

pub fn draw(self: *Self, dt: f32, camera: Camera) !void {
    const cmd_buf = try self.device.acquireCommandBuffer();
    const swapchain_texture, const width, const height = try cmd_buf.waitAndAcquireSwapchainTexture(self.window);
    const ROTATION_SPEED: f32 = std.math.degreesToRadians(90);
    if (self.rotate) {
        for (self.entities.items) |*entity| {
            entity.rotation = zmath.qmul(entity.rotation, zmath.quatFromMat(zmath.rotationY(dt * ROTATION_SPEED)));
        }
    }

    // cmd_buf.pushDebugGroup("testdebug");
    if (swapchain_texture) |texture| {
        const window_width, const window_height = try self.window.getSize();
        const pixel_width, _ = try self.window.getSizeInPixels();
        const scale_x =
            @as(f32, @floatFromInt(pixel_width)) /
            @as(f32, @floatFromInt(window_width));
        // std.log.info("W: {d} H: {d}; SW: {d} SH: {d}; PW: {d} S: {d}", .{ window_width, window_height, width, height, pixel_width, scale_x });
        gui.zgui.backend.newFrame(@intCast(window_width), @intCast(window_height), scale_x);

        {
            cmd_buf.pushDebugGroup("WORLD");
            defer cmd_buf.popDebugGroup();
            // -----------------------------------------------------------------
            // MESH RENDER PASS
            // -----------------------------------------------------------------

            // SDL3 uses this apparently, Right Hand Side
            const projection = zmath.perspectiveFovRh(
                std.math.degreesToRadians(70),
                @as(f32, @floatFromInt(width)) / @as(f32, @floatFromInt(height)),
                0.1,
                1000,
            );

            const render_pass = cmd_buf.beginRenderPass(
                &.{
                    sdl.gpu.ColorTargetInfo{
                        .texture = texture,
                        .clear_color = .{ .r = 0, .g = 0, .b = 0 },
                        .load = .clear,
                    },
                },
                .{
                    .texture = self.depth_texutre,
                    .load = .clear,
                    .store = .do_not_care,
                    .stencil_load = .clear,
                    .stencil_store = .do_not_care,
                    .cycle = false,
                    .clear_stencil = 1,
                    .clear_depth = 1,
                },
            );
            defer render_pass.end();

            self.triangle_pipeline.bind(render_pass);
            render_pass.bindFragmentSamplers(0, &.{.{ .texture = self.texture.texture, .sampler = self.sampler }});
            cmd_buf.pushFragmentUniformData(0, std.mem.asBytes(&FragmentUniforms{
                .light_color = self.light_color,
                .light_position = self.light_position,
                .light_intensity = self.light_intensity,
                .view_position = zmath.vecToArr3(camera.position),
            }));
            cmd_buf.pushVertexUniformData(0, std.mem.asBytes(&VertexGlobalUniforms{
                .viewProjectionMat = zmath.mul(camera.view_matrix(), projection),
            }));

            for (self.entities.items) |entity| {
                entity.draw(cmd_buf, render_pass);
            }
        }

        {
            cmd_buf.pushDebugGroup("GUI");
            defer cmd_buf.popDebugGroup();
            // -----------------------------------------------------------------
            // IMGUI
            // -----------------------------------------------------------------
            var show = true;
            gui.zgui.showDemoWindow(&show);

            if (gui.zgui.begin("Model", .{})) {
                _ = gui.zgui.checkbox("Rotate", .{ .v = &self.rotate });
                gui.zgui.end();
            }

            if (gui.zgui.begin("Light", .{})) {
                _ = gui.zgui.sliderFloat("Light Intensity", .{ .min = 0, .max = 10, .v = &self.light_intensity });
                _ = gui.zgui.sliderFloat3("Light Position", .{ .min = 0, .max = 10, .v = &self.light_position });
                _ = gui.zgui.colorEdit3("Light Color", .{ .col = &self.light_color });
                gui.zgui.end();
            }

            if (gui.zgui.begin("Cam", .{})) {
                gui.zgui.text("Position {}", .{camera.position});
                gui.zgui.text("Rotation pitch {}", .{std.math.radiansToDegrees(camera.pitch)});
                gui.zgui.text("Rotation yaw {}", .{std.math.radiansToDegrees(camera.yaw)});
                gui.zgui.end();
            }

            gui.render();

            gui.prepareDrawData(&cmd_buf);
            const render_pass = cmd_buf.beginRenderPass(
                &.{
                    sdl.gpu.ColorTargetInfo{
                        .texture = texture,
                        .clear_color = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
                        .load = .load,
                    },
                },
                null,
            );
            defer render_pass.end();

            gui.renderDrawData(&cmd_buf, &render_pass);
        }
    }

    try cmd_buf.submit();
}

pub fn deinit(self: *Self, gpa: std.mem.Allocator) void {
    self.device.waitForIdle() catch @panic("could not wait for idle");

    gui.deinit();

    self.texture.deinit(&self.device);

    for (self.entities.items) |*entity| {
        entity.deinit(self.device);
    }
    self.entities.deinit(gpa);

    self.device.releaseTexture(self.depth_texutre);
    self.device.releaseSampler(self.sampler);

    self.triangle_pipeline.deinit(self.device);

    self.device.releaseWindow(self.window);
    self.device.deinit();
    self.window.deinit();
}
