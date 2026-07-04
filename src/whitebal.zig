// whitebal.zig - white balance correction
//
// Auto and manual white balance adjustment. Uses gray-world assumption,
// white patch detection, and correlated color temperature estimation.

const types = @import("types.zig");

fn approxSqrt(x: f32) f32 {
    if (x <= 0) return 0;
    var y = x;
    var k: u32 = 0;
    while (k < 8) : (k += 1) y = (y + x / y) * 0.5;
    return y;
}

// Gray world white balance: compute average color as white estimate
pub fn grayWorld(pixels: []const f32, count: u32) [3]f32 {
    var sum = [3]f32{ 0, 0, 0 };
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        sum[0] += pixels[@as(usize, i) * 3];
        sum[1] += pixels[@as(usize, i) * 3 + 1];
        sum[2] += pixels[@as(usize, i) * 3 + 2];
    }
    if (count > 0) {
        const n = @as(f32, @floatFromInt(count));
        return .{ sum[0] / n, sum[1] / n, sum[2] / n };
    }
    return .{ 0.5, 0.5, 0.5 };
}

// White patch: find the brightest pixel
pub fn whitePatch(pixels: []const f32, count: u32) [3]f32 {
    var max_lum: f32 = 0;
    var best = [3]f32{ 1, 1, 1 };
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        const r = pixels[@as(usize, i) * 3];
        const g = pixels[@as(usize, i) * 3 + 1];
        const b = pixels[@as(usize, i) * 3 + 2];
        const lum = 0.2126 * r + 0.7152 * g + 0.0722 * b;
        if (lum > max_lum) {
            max_lum = lum;
            best = .{ r, g, b };
        }
    }
    return best;
}

// Compute white balance correction matrix
pub fn correctionMatrix(measured_white: [3]f32, target_white: [3]f32) [9]f32 {
    var m = [9]f32{ 1, 0, 0, 0, 1, 0, 0, 0, 1 };
    if (measured_white[0] > 0) m[0] = target_white[0] / measured_white[0];
    if (measured_white[1] > 0) m[4] = target_white[1] / measured_white[1];
    if (measured_white[2] > 0) m[8] = target_white[2] / measured_white[2];
    return m;
}

// Apply diagonal correction matrix
pub fn applyCorrection(pixels: []f32, count: u32, matrix: [9]f32) void {
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        const base = @as(usize, i) * 3;
        const r = pixels[base];
        const g = pixels[base + 1];
        const b = pixels[base + 2];
        pixels[base] = matrix[0] * r + matrix[1] * g + matrix[2] * b;
        pixels[base + 1] = matrix[3] * r + matrix[4] * g + matrix[5] * b;
        pixels[base + 2] = matrix[6] * r + matrix[7] * g + matrix[8] * b;
    }
}

// CCT-based white balance: shift to a target temperature
pub fn cctCorrect(pixels: []f32, count: u32, src_cct: f32, dst_cct: f32) void {
    if (src_cct <= 0 or dst_cct <= 0) return;
    // Simple model: warm/cool shift proportional to CCT ratio
    const ratio = dst_cct / src_cct;
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        const base = @as(usize, i) * 3;
        // Warm → more red, less blue
        pixels[base] *= if (ratio < 1) ratio else 1.0 + (ratio - 1.0) * 0.3;
        pixels[base + 2] *= if (ratio > 1) 1.0 / ratio else 1.0 - (1.0 - ratio) * 0.3;
        // Clamp
        if (pixels[base] > 1) pixels[base] = 1;
        if (pixels[base + 2] > 1) pixels[base + 2] = 1;
    }
}

// Estimate CCT from image white point
pub fn estimateCct(white: [3]f32) f32 {
    if (white[1] <= 0) return 6500;
    // Map R/B ratio to approximate CCT
    const rb = white[0] / (white[2] + 0.001);
    if (rb > 2.0) return 2500; // very warm
    if (rb > 1.5) return 3500; // warm
    if (rb > 1.0) return 5000; // neutral warm
    if (rb > 0.8) return 6500; // daylight
    return 8000; // cool
}

// Tint correction (green-magenta axis)
pub fn tintCorrect(pixels: []f32, count: u32, tint: f32) void {
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        const base = @as(usize, i) * 3;
        pixels[base + 1] *= 1.0 + tint;
        if (pixels[base + 1] > 1) pixels[base + 1] = 1;
        if (pixels[base + 1] < 0) pixels[base + 1] = 0;
    }
}

// Combined auto white balance
pub fn autoBalance(pixels: []f32, count: u32) void {
    const gw = grayWorld(pixels, count);
    const target = [3]f32{ 0.5, 0.5, 0.5 };
    const mat = correctionMatrix(gw, target);
    applyCorrection(pixels, count, mat);
}
