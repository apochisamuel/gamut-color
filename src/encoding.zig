// encoding.zig - color value encoding and normalization
//
// Handle encoding conventions for color values in different contexts:
// ICC PCS encoding (16-bit Lab, 16-bit XYZ), device value normalization,
// and conversion between encoded integer values and float.

const types = @import("types.zig");

// Encode float Lab to 16-bit ICC PCS
pub fn encodeLab16(lab: [3]f32) [3]u16 {
    var l = lab[0];
    var a = lab[1];
    var b = lab[2];
    if (l < 0) l = 0;
    if (l > 100) l = 100;
    if (a < -128) a = -128;
    if (a > 127) a = 127;
    if (b < -128) b = -128;
    if (b > 127) b = 127;
    return .{
        @intFromFloat(l / 100.0 * 65280.0 + 0.5),
        @intFromFloat((a + 128.0) / 255.0 * 65535.0 + 0.5),
        @intFromFloat((b + 128.0) / 255.0 * 65535.0 + 0.5),
    };
}

// Decode 16-bit ICC PCS Lab to float
pub fn decodeLab16(enc: [3]u16) [3]f32 {
    return .{
        @as(f32, @floatFromInt(enc[0])) / 65280.0 * 100.0,
        @as(f32, @floatFromInt(enc[1])) / 65535.0 * 255.0 - 128.0,
        @as(f32, @floatFromInt(enc[2])) / 65535.0 * 255.0 - 128.0,
    };
}

// Encode float XYZ to 16-bit ICC PCS
pub fn encodeXyz16(xyz: [3]f32) [3]u16 {
    var out: [3]u16 = undefined;
    for (0..3) |i| {
        var v = xyz[i];
        if (v < 0) v = 0;
        if (v > 1.99997) v = 1.99997;
        out[i] = @intFromFloat(v / 1.99997 * 65535.0 + 0.5);
    }
    return out;
}

// Decode 16-bit ICC PCS XYZ
pub fn decodeXyz16(enc: [3]u16) [3]f32 {
    var out: [3]f32 = undefined;
    for (0..3) |i| {
        out[i] = @as(f32, @floatFromInt(enc[i])) / 65535.0 * 1.99997;
    }
    return out;
}

// Encode float Lab to 8-bit (v2 profiles)
pub fn encodeLab8(lab: [3]f32) [3]u8 {
    var l = lab[0];
    var a = lab[1];
    var b = lab[2];
    if (l < 0) l = 0;
    if (l > 100) l = 100;
    if (a < -128) a = -128;
    if (a > 127) a = 127;
    if (b < -128) b = -128;
    if (b > 127) b = 127;
    return .{
        @intFromFloat(l / 100.0 * 255.0 + 0.5),
        @intFromFloat(a + 128.0 + 0.5),
        @intFromFloat(b + 128.0 + 0.5),
    };
}

// Decode 8-bit Lab
pub fn decodeLab8(enc: [3]u8) [3]f32 {
    return .{
        @as(f32, @floatFromInt(enc[0])) / 255.0 * 100.0,
        @as(f32, @floatFromInt(enc[1])) - 128.0,
        @as(f32, @floatFromInt(enc[2])) - 128.0,
    };
}

// Normalize device values from integer bit depth to [0,1]
pub fn normalizeDevice(raw: []const u16, bits: u8, output: []f32) void {
    if (bits == 0 or bits > 16) return;
    const scale = 1.0 / @as(f32, @floatFromInt((@as(u32, 1) << @intCast(bits)) - 1));
    for (raw, 0..) |r, i| {
        if (i >= output.len) break;
        output[i] = @as(f32, @floatFromInt(r)) * scale;
    }
}

// Denormalize float [0,1] to integer bit depth
pub fn denormalizeDevice(flt: []const f32, bits: u8, output: []u16) void {
    if (bits == 0 or bits > 16) return;
    const scale = @as(f32, @floatFromInt((@as(u32, 1) << @intCast(bits)) - 1));
    for (flt, 0..) |f, i| {
        if (i >= output.len) break;
        var v = f;
        if (v < 0) v = 0;
        if (v > 1) v = 1;
        output[i] = @intFromFloat(v * scale + 0.5);
    }
}

// Lab v2 to v4 encoding conversion
pub fn labV2ToV4(v2: [3]f32) [3]f32 {
    return .{
        v2[0],
        v2[1] * (65535.0 / 65280.0),
        v2[2] * (65535.0 / 65280.0),
    };
}

pub fn labV4ToV2(v4: [3]f32) [3]f32 {
    return .{
        v4[0],
        v4[1] * (65280.0 / 65535.0),
        v4[2] * (65280.0 / 65535.0),
    };
}

// Round-trip error for Lab 16-bit encoding
pub fn lab16RoundtripError(lab: [3]f32) f32 {
    const enc = encodeLab16(lab);
    const dec = decodeLab16(enc);
    var max_err: f32 = 0;
    for (0..3) |i| {
        var d = lab[i] - dec[i];
        if (d < 0) d = -d;
        if (d > max_err) max_err = d;
    }
    return max_err;
}

// Round-trip error for XYZ 16-bit encoding
pub fn xyz16RoundtripError(xyz: [3]f32) f32 {
    const enc = encodeXyz16(xyz);
    const dec = decodeXyz16(enc);
    var max_err: f32 = 0;
    for (0..3) |i| {
        var d = xyz[i] - dec[i];
        if (d < 0) d = -d;
        if (d > max_err) max_err = d;
    }
    return max_err;
}

// Batch encode Lab to 16-bit
pub fn batchEncodeLab16(lab: []const f32, output: []u16, count: usize) void {
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const triplet = [3]f32{ lab[i * 3], lab[i * 3 + 1], lab[i * 3 + 2] };
        const enc = encodeLab16(triplet);
        output[i * 3] = enc[0];
        output[i * 3 + 1] = enc[1];
        output[i * 3 + 2] = enc[2];
    }
}

// Batch decode 16-bit to Lab
pub fn batchDecodeLab16(enc: []const u16, output: []f32, count: usize) void {
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const triplet = [3]u16{ enc[i * 3], enc[i * 3 + 1], enc[i * 3 + 2] };
        const dec = decodeLab16(triplet);
        output[i * 3] = dec[0];
        output[i * 3 + 1] = dec[1];
        output[i * 3 + 2] = dec[2];
    }
}
