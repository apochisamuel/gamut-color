// intent.zig - rendering intent simulation
//
// Simulate the four ICC rendering intents by manipulating Lab values.
// Includes black point compensation (BPC) for shadow detail preservation.

const types = @import("types.zig");

fn approxSqrt(x: f32) f32 {
    if (x <= 0) return 0;
    var y = x;
    var k: u32 = 0;
    while (k < 8) : (k += 1) {
        y = (y + x / y) * 0.5;
    }
    return y;
}

// Black point compensation: linearly map [src_black, 100] → [dst_black, 100]
pub fn bpcAdjust(lab: *[3]f32, src_black: f32, dst_black: f32) void {
    const src_range = 100.0 - src_black;
    const dst_range = 100.0 - dst_black;
    if (src_range <= 0) {
        lab[0] = dst_black;
        return;
    }
    var l = ((lab[0] - src_black) / src_range) * dst_range + dst_black;
    if (l < dst_black) l = dst_black;
    if (l > 100.0) l = 100.0;
    lab[0] = l;
}

// Apply BPC to an array of Lab values
pub fn bpcBatch(lab: []f32, count: usize, src_black: f32, dst_black: f32) void {
    var i: usize = 0;
    while (i < count) : (i += 1) {
        var triplet = [3]f32{ lab[i * 3], lab[i * 3 + 1], lab[i * 3 + 2] };
        bpcAdjust(&triplet, src_black, dst_black);
        lab[i * 3] = triplet[0];
        lab[i * 3 + 1] = triplet[1];
        lab[i * 3 + 2] = triplet[2];
    }
}

// Perceptual intent: compress lightness and reduce chroma
pub fn perceptual(lab: []f32, count: usize) void {
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const off = i * 3;
        const t = lab[off] / 100.0;
        lab[off] = (0.1 + 0.8 * t) * 100.0;
        lab[off + 1] *= 0.95;
        lab[off + 2] *= 0.95;
    }
}

// Relative colorimetric: shift lightness
pub fn relativeColorimetric(lab: []f32, count: usize, src_l: f32, dst_l: f32) void {
    const shift = dst_l - src_l;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        lab[i * 3] += shift;
    }
}

// Saturation intent: scale chroma
pub fn saturation(lab: []f32, count: usize, scale: f32) void {
    var i: usize = 0;
    while (i < count) : (i += 1) {
        lab[i * 3 + 1] *= scale;
        lab[i * 3 + 2] *= scale;
    }
}

// Absolute colorimetric: no-op
pub fn absolute(lab: []f32, count: usize) void {
    _ = lab;
    _ = count;
}

// Dispatch by intent index
pub fn applyIntent(lab: []f32, count: usize, intent: u8, src_bk: f32, dst_bk: f32) void {
    switch (intent) {
        0 => {
            perceptual(lab, count);
            bpcBatch(lab, count, src_bk, dst_bk);
        },
        1 => relativeColorimetric(lab, count, 100.0, 100.0),
        2 => saturation(lab, count, 1.1),
        3 => absolute(lab, count),
        else => {},
    }
}

// Compute chroma from Lab
pub fn chroma(lab: [3]f32) f32 {
    return approxSqrt(lab[1] * lab[1] + lab[2] * lab[2]);
}

// Compute hue angle from Lab
pub fn hueAngle(lab: [3]f32) f32 {
    const ax = if (lab[1] < 0) -lab[1] else lab[1];
    const ay = if (lab[2] < 0) -lab[2] else lab[2];
    if (ax < 1e-10 and ay < 1e-10) return 0;
    const a = if (ax >= ay) ay / ax else ax / ay;
    const t = a * a;
    var r = ((-0.0465 * t + 0.1593) * t - 0.3276) * t * a + a;
    if (ax < ay) r = 1.5708 - r;
    if (lab[1] < 0) r = 3.14159 - r;
    if (lab[2] < 0) r = -r;
    return r;
}

// Gamut clip: clamp chroma to a maximum
pub fn chromaClip(lab: *[3]f32, max_chroma: f32) void {
    const c = chroma(lab.*);
    if (c > max_chroma and c > 0) {
        const scale = max_chroma / c;
        lab[1] *= scale;
        lab[2] *= scale;
    }
}

// Dynamic range: ratio of white to black lightness
pub fn dynamicRange(white_l: f32, black_l: f32) f32 {
    const bk = if (black_l <= 0) @as(f32, 0.001) else black_l;
    return white_l / bk;
}

// Compute chromaticity distance between two whites
pub fn whiteDistance(a: types.Xyz, b: types.Xyz) f32 {
    const a_sum = a.x + a.y + a.z;
    const b_sum = b.x + b.y + b.z;
    if (a_sum <= 0 or b_sum <= 0) return 999.0;
    const ax = a.x / a_sum;
    const ay = a.y / a_sum;
    const bx = b.x / b_sum;
    const by = b.y / b_sum;
    const dx = ax - bx;
    const dy = ay - by;
    return approxSqrt(dx * dx + dy * dy);
}
