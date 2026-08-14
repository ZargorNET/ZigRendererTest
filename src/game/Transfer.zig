const std = @import("std");

const sdl = @import("sdl");

const Self = @This();

// FIXME: Auto resize when this is not enough!!
const MAX_SIZE = (1 << 29); // 512 MiB

buffer: sdl.gpu.TransferBuffer,

allocator: std.mem.Allocator,
started: bool = false,
ptr: ?[*]u8 = null,
current_offset: u32 = 0,
copies: std.ArrayList(struct { CopyInfo, u32 }) = .empty,

const CopyInfo = union(enum) { Buffer: CopyBufferInfo, Texture: CopyTextureInfo };
const CopyBufferInfo = struct { buffer: sdl.gpu.Buffer, offset: u32, size: u32 };
const CopyTextureInfo = struct { texture: sdl.gpu.Texture, width: u32, height: u32 };

pub fn init(allocator: std.mem.Allocator, device: *const sdl.gpu.Device) !Self {
    const buffer = try device.createTransferBuffer(.{
        .usage = .upload,
        .size = MAX_SIZE,
    });

    return .{
        .allocator = allocator,
        .buffer = buffer,
    };
}

pub fn start(self: *Self, device: *const sdl.gpu.Device) !void {
    if (self.started)
        return error.AlreadyStarted;

    self.ptr = try device.mapTransferBuffer(self.buffer, false);
    self.started = true;
    self.current_offset = 0;
    self.copies.clearRetainingCapacity();
}

pub fn copy_buffer(self: *Self, bytes: []const u8, to: sdl.gpu.Buffer) !void {
    if (bytes.len > std.math.maxInt(u32)) {
        return error.TooLarge;
    }

    try self.copy(bytes, .{ .Buffer = .{ .buffer = to, .size = @intCast(bytes.len), .offset = 0 } });
}

pub fn copy_texture(self: *Self, bytes: []const u8, width: u32, height: u32, to: sdl.gpu.Texture) !void {
    try self.copy(bytes, .{ .Texture = .{ .texture = to, .width = width, .height = height } });
}

fn copy(self: *Self, bytes: []const u8, info: CopyInfo) !void {
    if (self.current_offset + bytes.len > MAX_SIZE) {
        return error.BufferWouldBeTooLarge;
    }

    try self.copies.append(self.allocator, .{ info, self.current_offset });
    @memcpy(self.ptr.?[self.current_offset..], bytes);
    self.current_offset += @intCast(bytes.len);
}

pub fn finish(self: *Self, device: *const sdl.gpu.Device, copy_pass: *const sdl.gpu.CopyPass) void {
    if (!self.started) return;

    device.unmapTransferBuffer(self.buffer);

    for (self.copies.items) |copy_item| {
        const info = copy_item.@"0";
        const offset = copy_item.@"1";

        switch (info) {
            .Texture => |text| {
                copy_pass.uploadToTexture(.{ .transfer_buffer = self.buffer, .offset = offset }, .{
                    .texture = text.texture,
                    .width = text.width,
                    .height = text.height,
                    .layer = 0,
                    .depth = 1,
                }, false);
            },
            .Buffer => |buf| {
                copy_pass.uploadToBuffer(.{ .transfer_buffer = self.buffer, .offset = offset }, .{
                    .buffer = buf.buffer,
                    .offset = buf.offset,
                    .size = buf.size,
                }, false);
            },
        }
    }
    self.current_offset = 0;
    self.copies.clearRetainingCapacity();

    self.started = false;
}

pub fn deinit(self: *Self, device: *const sdl.gpu.Device) void {
    // If finish has not been called, release nonetheless
    if (self.started) {
        device.unmapTransferBuffer(self.buffer);
    }

    device.releaseTransferBuffer(self.buffer);
    self.buffer = undefined;
    self.copies.deinit(self.allocator);
}
