const std = @import("std");

const sdl = @import("sdl");
pub const zgui = @import("zgui");

var backend_init = false;

pub fn init(gpa: std.mem.Allocator) void {
    zgui.init(gpa);
}

pub fn init_gpu(window: *const sdl.video.Window, device: *const sdl.gpu.Device, swapchain_format: sdl.gpu.TextureFormat) void {
    zgui.backend.init(window.value, .{
        .device = device.value,
        .color_target_format = @intFromEnum(swapchain_format),
        .msaa_samples = @intFromEnum(sdl.gpu.SampleCount.no_multisampling),
    });

    // Something to do with Linear -> sRGB
    // The pipeline uses sRGB so we have to convert
    const style = zgui.getStyle();
    for (style.colors, 0..) |col, idx| {
        var converted = col;
        for (0..converted.len) |cidx| {
            converted[cidx] = std.math.pow(f32, converted[cidx], 2.2);
        }

        style.setColor(@enumFromInt(idx), converted);
    }
    backend_init = true;
}

pub fn processEvent(event: *const sdl.c.SDL_Event) bool {
    return zgui.backend.processEvent(event);
}

pub fn render() void {
    zgui.backend.render();
}

pub fn prepareDrawData(command_buffer: *const sdl.gpu.CommandBuffer) void {
    zgui.backend.prepareDrawData(command_buffer.value);
}

pub fn renderDrawData(command_buffer: *const sdl.gpu.CommandBuffer, render_pass: *const sdl.gpu.RenderPass) void {
    zgui.backend.renderDrawData(command_buffer.value, render_pass.value, null);
}

pub fn deinit() void {
    if (backend_init)
        zgui.backend.deinit();

    zgui.deinit();
}
