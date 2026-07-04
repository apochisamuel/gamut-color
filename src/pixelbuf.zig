// pixelbuf.zig - pixel buffer processing pipeline
//
// Batch transform processing for pixel arrays. Handles interleaved and
// planar layouts, bit depth conversion, premultiplied alpha handling,
// and out-of-gamut flagging.

const types = @import("types.zig");

pub const PixelFormat = enum(u8) {
    rgb8 = 0,
    rgba8 = 1,
    rgb16 = 2,
    rgba16 = 3,
    rgb_f32 = 4,
    rgba_f32 = 5,
    cmyk8 = 6,
    cmyk16 = 7,
    gray8 = 8,
    gray16 = 9,
};

pub const BufferLayout = enum(u8) {
    interleaved = 0,
    planar = 1,
};

pub const PixelBuf = struct {
    format: PixelFormat = .rgb8,
    layout: BufferLayout = .interleaved,
    width: u32 = 0,
    height: u32 = 0,
    channels: u8 = 3,
    has_alpha: bool = false,
    premultiplied: bool = false,
    stride: u32 = 0,
};

pub fn channelsForFormat(fmt: PixelFormat) u8 {
    return switch (fmt) {
        .rgb8, .rgb16, .rgb_f32 => 3,
        .rgba8, .rgba16, .rgba_f32 => 4,
        .cmyk8, .cmyk16 => 4,
        .gray8, .gray16 => 1,
    };
}

pub fn bitsPerChannel(fmt: PixelFormat) u8 {
    return switch (fmt) {
        .rgb8, .rgba8, .cmyk8, .gray8 => 8,
        .rgb16, .rgba16, .cmyk16, .gray16 => 16,
        .rgb_f32, .rgba_f32 => 32,
    };
}

pub fn bytesPerPixel(fmt: PixelFormat) u32 {
    return @as(u32, channelsForFormat(fmt)) * bitsPerChannel(fmt) / 8;
}

// Convert a row of 8-bit interleaved to float [0,1]
pub fn unpack8(src: []const u8, dst: []f32, channels: u8, count: u32) void {
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        var c: u8 = 0;
        while (c < channels) : (c += 1) {
            const idx = @as(usize, i) * channels + c;
            dst[idx] = @as(f32, @floatFromInt(src[idx])) / 255.0;
        }
    }
}

// Convert a row of float to 8-bit interleaved
pub fn pack8(src: []const f32, dst: []u8, channels: u8, count: u32) void {
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        var c: u8 = 0;
        while (c < channels) : (c += 1) {
            const idx = @as(usize, i) * channels + c;
            var v = src[idx] * 255.0 + 0.5;
            if (v < 0) v = 0;
            if (v > 255) v = 255;
            dst[idx] = @intFromFloat(v);
        }
    }
}

// Convert 16-bit to float
pub fn unpack16(src: []const u8, dst: []f32, channels: u8, count: u32) void {
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        var c: u8 = 0;
        while (c < channels) : (c += 1) {
            const idx = @as(usize, i) * channels + c;
            const byte_idx = idx * 2;
            if (byte_idx + 1 >= src.len) break;
            const val = (@as(u16, src[byte_idx]) << 8) | src[byte_idx + 1];
            dst[idx] = @as(f32, @floatFromInt(val)) / 65535.0;
        }
    }
}

// Convert float to 16-bit
pub fn pack16(src: []const f32, dst: []u8, channels: u8, count: u32) void {
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        var c: u8 = 0;
        while (c < channels) : (c += 1) {
            const idx = @as(usize, i) * channels + c;
            var v = src[idx] * 65535.0 + 0.5;
            if (v < 0) v = 0;
            if (v > 65535) v = 65535;
            const val: u16 = @intFromFloat(v);
            const byte_idx = idx * 2;
            if (byte_idx + 1 >= dst.len) break;
            dst[byte_idx] = @intCast((val >> 8) & 0xFF);
            dst[byte_idx + 1] = @intCast(val & 0xFF);
        }
    }
}

// Remove premultiplied alpha
pub fn unpremultiply(data: []f32, channels: u8, count: u32) void {
    if (channels < 4) return;
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        const base = @as(usize, i) * channels;
        const alpha = data[base + 3];
        if (alpha > 0.001) {
            var c: u8 = 0;
            while (c < 3) : (c += 1) {
                data[base + c] /= alpha;
                if (data[base + c] > 1.0) data[base + c] = 1.0;
            }
        }
    }
}

// Apply premultiplied alpha
pub fn premultiply(data: []f32, channels: u8, count: u32) void {
    if (channels < 4) return;
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        const base = @as(usize, i) * channels;
        const alpha = data[base + 3];
        var c: u8 = 0;
        while (c < 3) : (c += 1) {
            data[base + c] *= alpha;
        }
    }
}

// Clamp all channels to [0,1]
pub fn clampRow(data: []f32, total: usize) void {
    var i: usize = 0;
    while (i < total) : (i += 1) {
        if (data[i] < 0) data[i] = 0;
        if (data[i] > 1) data[i] = 1;
    }
}

// Compute row statistics
pub fn rowStats(data: []const f32, channels: u8, count: u32, mins: []f32, maxs: []f32, means: []f32) void {
    var c: u8 = 0;
    while (c < channels) : (c += 1) {
        mins[c] = 1;
        maxs[c] = 0;
        means[c] = 0;
    }
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        c = 0;
        while (c < channels) : (c += 1) {
            const v = data[@as(usize, i) * channels + c];
            if (v < mins[c]) mins[c] = v;
            if (v > maxs[c]) maxs[c] = v;
            means[c] += v;
        }
    }
    if (count > 0) {
        c = 0;
        while (c < channels) : (c += 1) {
            means[c] /= @as(f32, @floatFromInt(count));
        }
    }
}

// Flag out-of-gamut pixels (any channel < 0 or > 1)
pub fn flagOutOfGamut(data: []const f32, flags: []u8, channels: u8, count: u32) u32 {
    var oog_count: u32 = 0;
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        var is_oog = false;
        var c: u8 = 0;
        while (c < channels) : (c += 1) {
            const v = data[@as(usize, i) * channels + c];
            if (v < -0.001 or v > 1.001) {
                is_oog = true;
                break;
            }
        }
        flags[i] = if (is_oog) 1 else 0;
        if (is_oog) oog_count += 1;
    }
    return oog_count;
}

// Apply a simple 3x3 matrix to a pixel row
pub fn applyMatrix3(data: []f32, mat: [9]f32, count: u32) void {
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        const base = @as(usize, i) * 3;
        const r = data[base];
        const g = data[base + 1];
        const b = data[base + 2];
        data[base] = mat[0] * r + mat[1] * g + mat[2] * b;
        data[base + 1] = mat[3] * r + mat[4] * g + mat[5] * b;
        data[base + 2] = mat[6] * r + mat[7] * g + mat[8] * b;
    }
}

// Channel swap: RGB ↔ BGR
pub fn swapRB(data: []f32, count: u32) void {
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        const base = @as(usize, i) * 3;
        const tmp = data[base];
        data[base] = data[base + 2];
        data[base + 2] = tmp;
    }
}

// Dither: add controlled noise for banding reduction
pub fn ditheRow(data: []f32, channels: u8, count: u32, row: u32, bits: u8) void {
    const quantum = 1.0 / @as(f32, @floatFromInt((@as(u32, 1) << @intCast(bits)) - 1));
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        const hash = (i *% 2654435761 ^ row *% 2246822519) & 0xFFFF;
        const noise = (@as(f32, @floatFromInt(hash)) / 65535.0 - 0.5) * quantum;
        var c: u8 = 0;
        while (c < channels) : (c += 1) {
            data[@as(usize, i) * channels + c] += noise;
        }
    }
}
