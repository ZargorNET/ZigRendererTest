const std = @import("std");

const zmath = @import("zmath");

const Self = @This();

speed: f32 = 5.0,
position: zmath.Vec = .{ 0, 0, 0, 0 },
yaw: f32 = 0.0,
pitch: f32 = 0.0,

up: zmath.Vec = zmath.f32x4(0, 1, 0, 0),
right: zmath.Vec = RIGHT,
forward: zmath.Vec = FORWARD,

rotation_mat: zmath.Mat = zmath.identity(),

const RIGHT: zmath.Vec = zmath.f32x4(1, 0, 0, 0);
const FORWARD: zmath.Vec = zmath.f32x4(0, 0, -1, 0);

inline fn movement(self: Self, dt: f32) zmath.Vec {
    return @splat(self.speed * dt);
}

pub fn view_matrix(self: Self) zmath.Mat {
    const cam_transl = zmath.translation(self.position[0], self.position[1], self.position[2]);
    const cam_transf = zmath.mul(zmath.matFromRollPitchYaw(self.pitch, self.yaw, 0.0), cam_transl);
    return zmath.inverse(cam_transf);
}

pub fn with_forwards(s: Self, dt: f32) Self {
    var self = s;
    self.position += self.forward * movement(self, dt);
    return self;
}

pub fn with_backwards(s: Self, dt: f32) Self {
    var self = s;
    self.position -= self.forward * movement(self, dt);
    return self;
}

pub fn with_left(s: Self, dt: f32) Self {
    var self = s;
    self.position -= self.right * movement(self, dt);
    return self;
}

pub fn with_right(s: Self, dt: f32) Self {
    var self = s;
    self.position += self.right * movement(self, dt);
    return self;
}

pub fn with_up(s: Self, dt: f32) Self {
    var self = s;
    self.position += self.up * movement(self, dt);
    return self;
}

pub fn with_down(s: Self, dt: f32) Self {
    var self = s;
    self.position -= self.up * movement(self, dt);
    return self;
}

pub fn with_yaw(s: Self, yaw: f32) Self {
    var self = s;
    self.yaw = yaw;
    self.rotation_mat = zmath.matFromRollPitchYaw(self.pitch, self.yaw, 0);
    self.forward = zmath.mul(FORWARD, self.rotation_mat);
    self.right = zmath.mul(RIGHT, self.rotation_mat);

    return self;
}

pub fn with_pitch(s: Self, pitch: f32) Self {
    var self = s;
    self.pitch = std.math.clamp(pitch, -std.math.pi / 2.0 + 0.01, std.math.pi / 2.0 - 0.01);
    self.rotation_mat = zmath.matFromRollPitchYaw(self.pitch, self.yaw, 0);
    self.forward = zmath.mul(FORWARD, self.rotation_mat);
    self.right = zmath.mul(RIGHT, self.rotation_mat);

    return self;
}
