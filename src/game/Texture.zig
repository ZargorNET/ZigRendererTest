const std = @import("std");

const sdl = @import("sdl");

const Transfer = @import("Transfer.zig");

const Self = @This();

texture: sdl.gpu.Texture,

pub fn init(device: *const sdl.gpu.Device, transfer: *Transfer, rgba: []const u8, info: sdl.gpu.TextureCreateInfo) !Self {
    const texture = try device.createTexture(info);

    try transfer.copy_texture(rgba, info.width, info.height, texture);

    return .{
        .texture = texture,
    };
}

pub const FileLoadArgs = struct {
    device: *const sdl.gpu.Device,
    path: [:0]const u8,
    usage: sdl.gpu.TextureUsageFlags,
    flip: ?sdl.surface.FlipMode = null,
};

pub fn load_from_file(transfer: *Transfer, args: FileLoadArgs) !Self {
    const tex = try sdl.image.loadFile(args.path);
    defer tex.deinit();

    const converted = try tex.convertFormat(.array_rgba_32);
    defer converted.deinit();

    if (args.flip) |flip|
        try converted.flip(flip);

    return Self.init(args.device, transfer, converted.getPixels().?, .{
        .format = .r8g8b8a8_unorm_srgb,
        .usage = args.usage,
        .width = @intCast(converted.getWidth()),
        .height = @intCast(converted.getHeight()),
        .layer_count_or_depth = 1,
        .num_levels = 1, // something with mipmaps
    });
}

pub fn deinit(self: *Self, device: *const sdl.gpu.Device) void {
    device.releaseTexture(self.texture);
    self.texture = undefined;
}
