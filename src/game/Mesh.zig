const std = @import("std");

const obj = @import("obj");
const GraphicsPipeline = @import("GraphicsPipeline.zig");

const Self = @This();

vertices: []const GraphicsPipeline.VertexData,
indices: []const u16,

pub fn init(gpa: std.mem.Allocator, io: std.Io, obj_path: []const u8) !Self {
    var vertices: std.ArrayList(GraphicsPipeline.VertexData) = .empty;
    var indices: std.ArrayList(u16) = .empty;
    errdefer vertices.deinit(gpa);
    errdefer indices.deinit(gpa);

    const cwd = std.Io.Dir.cwd();

    const path = try std.fmt.allocPrint(gpa, "assets/meshes/{s}", .{obj_path});
    defer gpa.free(path);

    const file = try std.Io.Dir.readFileAlloc(cwd, io, path, gpa, .unlimited);
    var object = try obj.parseObj(gpa, file);
    defer object.deinit(gpa);

    // An OBJ face index addresses a position, UV, and normal independently.
    // Expand those tuples into GPU vertices so positions that use different UVs
    // at a seam remain distinct vertices.
    for (object.meshes) |mesh| {
        for (mesh.indices) |index| {
            // Position
            const position_index = index.vertex orelse return error.ObjMissingPosition;
            const position_offset: usize = @as(usize, position_index) * 3;
            if (position_offset + 3 > object.vertices.len) {
                return error.ObjPositionOutOfBounds;
            }
            // UV
            const uv: [2]f32 = if (index.tex_coord) |tex_coord_index| blk: {
                const tex_coord_offset: usize = @as(usize, tex_coord_index) * 2;
                if (tex_coord_offset + 2 > object.tex_coords.len) {
                    return error.ObjTexCoordOutOfBounds;
                }
                break :blk .{
                    object.tex_coords[tex_coord_offset],
                    object.tex_coords[tex_coord_offset + 1],
                };
            } else .{ 0, 0 };
            // Normal
            const normal: [3]f32 = if (index.normal) |normal_index| blk: {
                const normal_offset: usize = @as(usize, normal_index) * 3;
                if (normal_offset + 3 > object.normals.len) {
                    return error.ObjNormalOutOfBounds;
                }
                break :blk .{
                    object.normals[normal_offset],
                    object.normals[normal_offset + 1],
                    object.normals[normal_offset + 2],
                };
            } else .{ 0, 0, 0 };
            if (vertices.items.len > std.math.maxInt(u16)) {
                return error.MeshTooLarge;
            }
            try indices.append(gpa, @intCast(vertices.items.len));
            try vertices.append(gpa, .{
                .pos = .{
                    object.vertices[position_offset],
                    object.vertices[position_offset + 1],
                    object.vertices[position_offset + 2],
                },
                .color = .{ 1, 1, 1, 1 },
                .uv = uv,
                .normal = normal,
            });
        }
    }
    if (indices.items.len == 0) return error.EmptyMesh;

    const verticesSlice = try vertices.toOwnedSlice(gpa);
    errdefer gpa.free(verticesSlice);
    const indicesSlice = try indices.toOwnedSlice(gpa);

    return .{
        .vertices = verticesSlice,
        .indices = indicesSlice,
    };
}

pub fn deinit(self: *const Self, gpa: std.mem.Allocator) void {
    gpa.free(self.vertices);
    gpa.free(self.indices);
}
