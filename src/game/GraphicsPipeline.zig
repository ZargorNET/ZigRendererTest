const builtin = @import("builtin");
const sdl = @import("sdl");

const Self = @This();

pipeline: sdl.gpu.GraphicsPipeline,

const ShaderSettings = struct {
    num_uniform_buffers: u32 = 0,
    num_samplers: u32 = 0,
};

pub const VertexData = struct {
    pos: [3]f32,
    color: [4]f32,
    uv: [2]f32,
    normal: [3]f32,
};

pub fn init(
    device: sdl.gpu.Device,
    color_format: sdl.gpu.TextureFormat,
    code: []const u8,
    code_frag: []const u8,
    vertex_props: ShaderSettings,
    fragment_props: ShaderSettings,
) !Self {
    const vertex_shader = try device.createShader(.{
        .code = code,
        .entry_point = "vertexMain",
        .format = comptime shaderFormat(),
        .stage = .vertex,
        .num_uniform_buffers = vertex_props.num_uniform_buffers,
        .num_samplers = vertex_props.num_samplers,
    });
    defer device.releaseShader(vertex_shader);

    const fragment_shader = try device.createShader(.{
        .code = code_frag,
        .entry_point = "fragmentMain",
        .format = comptime shaderFormat(),
        .stage = .fragment,
        .num_uniform_buffers = fragment_props.num_uniform_buffers,
        .num_samplers = fragment_props.num_samplers,
    });
    defer device.releaseShader(fragment_shader);

    const vertex_attrs = [_]sdl.gpu.VertexAttribute{
        .{
            .location = 0,
            .buffer_slot = 0,
            .format = .f32x3,
            .offset = @offsetOf(VertexData, "pos"),
        },
        .{
            .location = 1,
            .buffer_slot = 0,
            .format = .f32x4,
            .offset = @offsetOf(VertexData, "color"),
        },
        .{
            .location = 2,
            .buffer_slot = 0,
            .format = .f32x2,
            .offset = @offsetOf(VertexData, "uv"),
        },
        .{
            .location = 3,
            .buffer_slot = 0,
            .format = .f32x3,
            .offset = @offsetOf(VertexData, "normal"),
        },
    };

    return .{
        .pipeline = try device.createGraphicsPipeline(.{
            .vertex_shader = vertex_shader,
            .fragment_shader = fragment_shader,
            .vertex_input_state = .{
                .vertex_buffer_descriptions = &.{
                    sdl.gpu.VertexBufferDescription{
                        .slot = 0,
                        // Number of bytes between each vertex
                        .pitch = @sizeOf(VertexData),
                        .input_rate = .vertex,
                    },
                },
                .vertex_attributes = &vertex_attrs,
            },
            .target_info = .{
                .color_target_descriptions = &.{.{ .format = color_format }},
                .depth_stencil_format = .depth32_float,
            },
            .depth_stencil_state = .{
                .enable_depth_test = true,
                .enable_depth_write = true,
                .compare = .less, // less because towards negative infinity is near the camera
            },
            .rasterizer_state = .{
                .cull_mode = .back,
            },
        }),
    };
}

pub fn bind(self: Self, render_pass: sdl.gpu.RenderPass) void {
    render_pass.bindGraphicsPipeline(self.pipeline);
}

pub fn deinit(self: Self, device: sdl.gpu.Device) void {
    device.releaseGraphicsPipeline(self.pipeline);
}

fn shaderFormat() sdl.gpu.ShaderFormatFlags {
    return comptime switch (builtin.os.tag) {
        .macos => .{ .msl = true },
        .linux => .{ .spirv = true },
        .windows => .{ .dxil = true },
        else => @compileError("Unsupported shader target"),
    };
}
