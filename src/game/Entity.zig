const std = @import("std");

const sdl = @import("sdl");
const zmath = @import("zmath");

const Mesh = @import("Mesh.zig");
const Transfer = @import("Transfer.zig");
const Renderer = @import("Renderer.zig");
const Camera = @import("Camera.zig");

const Self = @This();

position: zmath.Vec,
rotation: zmath.Quat,

indices: u32,
vertex_buf: sdl.gpu.Buffer,
index_buf: sdl.gpu.Buffer,

pub fn spawn(mesh: Mesh, position: zmath.Vec, rotation: zmath.Quat, device: sdl.gpu.Device, transfer: *Transfer) !Self {
    const vertex_bytes: []const u8 = std.mem.sliceAsBytes(mesh.vertices);
    const index_bytes: []const u8 = std.mem.sliceAsBytes(mesh.indices);

    const vertex_buf = try device.createBuffer(.{ .size = @intCast(vertex_bytes.len), .usage = .{ .vertex = true } });
    errdefer device.releaseBuffer(vertex_buf);

    const index_buf = try device.createBuffer(.{
        .size = @intCast(index_bytes.len),
        .usage = .{ .index = true },
    });
    errdefer device.releaseBuffer(index_buf);

    try transfer.copy_buffer(vertex_bytes, vertex_buf);
    try transfer.copy_buffer(index_bytes, index_buf);

    return .{
        .index_buf = index_buf,
        .vertex_buf = vertex_buf,
        .indices = @intCast(mesh.indices.len),
        .position = position,
        .rotation = rotation,
    };
}

pub fn draw(self: Self, cmd_buf: sdl.gpu.CommandBuffer, render_pass: sdl.gpu.RenderPass) void {
    const model: zmath.Mat = zmath.mul(zmath.matFromQuat(self.rotation), zmath.translationV(self.position));
    const normal: zmath.Mat = zmath.transpose(zmath.inverse(model));

    cmd_buf.pushVertexUniformData(1, std.mem.asBytes(&Renderer.VertexLocalUnforms{
        .modelMat = model,
        .normalMat = normal,
    }));
    render_pass.bindVertexBuffers(0, &.{.{
        .buffer = self.vertex_buf,
        .offset = 0,
    }});
    render_pass.bindIndexBuffer(.{ .buffer = self.index_buf, .offset = 0 }, .indices_16bit);
    render_pass.drawIndexedPrimitives(self.indices, 1, 0, 0, 0);
}

pub fn deinit(self: *Self, device: sdl.gpu.Device) void {
    device.releaseBuffer(self.index_buf);
    device.releaseBuffer(self.vertex_buf);

    self.index_buf = undefined;
    self.vertex_buf = undefined;
}
