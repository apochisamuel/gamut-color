// reader.zig - binary reader for profile data
//
// Sequential reader over a byte buffer with bounds checking and
// big-endian integer and fixed-point decoding.

const types = @import("types.zig");

pub const Reader = struct {
    data: [*]const u8,
    size: usize,
    pos: usize,

    pub fn init(data: [*]const u8, size: usize) Reader {
        return .{ .data = data, .size = size, .pos = 0 };
    }

    pub fn initAt(data: [*]const u8, size: usize, offset: usize) Reader {
        return .{ .data = data, .size = size, .pos = offset };
    }

    pub fn ok(self: *const Reader, n: usize) bool {
        return self.pos + n <= self.size;
    }

    pub fn remaining(self: *const Reader) usize {
        if (self.pos >= self.size) return 0;
        return self.size - self.pos;
    }

    pub fn skip(self: *Reader, n: usize) void {
        self.pos += n;
    }

    pub fn u8read(self: *Reader) u8 {
        if (self.pos >= self.size) return 0;
        const v = self.data[self.pos];
        self.pos += 1;
        return v;
    }

    pub fn u16read(self: *Reader) u16 {
        if (self.pos + 2 > self.size) return 0;
        const hi: u16 = @intCast(self.data[self.pos]);
        const lo: u16 = @intCast(self.data[self.pos + 1]);
        self.pos += 2;
        return (hi << 8) | lo;
    }

    pub fn u32read(self: *Reader) u32 {
        if (self.pos + 4 > self.size) return 0;
        const b0: u32 = @intCast(self.data[self.pos]);
        const b1: u32 = @intCast(self.data[self.pos + 1]);
        const b2: u32 = @intCast(self.data[self.pos + 2]);
        const b3: u32 = @intCast(self.data[self.pos + 3]);
        self.pos += 4;
        return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3;
    }

    pub fn fixed(self: *Reader) f32 {
        const raw = self.u16read();
        const frac = self.u16read();
        return @as(f32, @floatFromInt(raw)) + @as(f32, @floatFromInt(frac)) / 65536.0;
    }

    pub fn u16norm(self: *Reader) f32 {
        const v = self.u16read();
        return @as(f32, @floatFromInt(v)) / 65535.0;
    }
};
