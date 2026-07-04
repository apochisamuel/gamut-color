// colortemp.zig - color temperature and tint computation
//
// Convert between correlated color temperature (CCT), tint offset,
// and CIE xy chromaticity. Used for white balance and illuminant
// characterization.

const types = @import("types.zig");

fn approxSqrt(x: f32) f32 {
    if (x <= 0) return 0;
    var y = x;
    var k: u32 = 0;
    while (k < 8) : (k += 1) y = (y + x / y) * 0.5;
    return y;
}

fn approxLn(x: f32) f32 {
    if (x <= 0) return -30;
    var v = x;
    var r: f32 = 0;
    while (v >= 2) { v *= 0.5; r += 0.6931; }
    const u = v - 1.0;
    r += u - u * u * 0.5 + u * u * u / 3.0;
    return r;
}

// Planckian locus: CIE xy from CCT (Kang et al. 2002)
pub fn cctToXy(cct: f32) [2]f32 {
    if (cct < 1667 or cct > 25000) return .{ 0.3127, 0.3290 };
    const t = 1e3 / cct;
    const t2 = t * t;
    const t3 = t2 * t;
    var x: f32 = 0;
    if (cct <= 4000) {
        x = -0.2661239 * t3 - 0.2343589 * t2 + 0.8776956 * t + 0.179910;
    } else {
        x = -3.0258469 * t3 + 2.1070379 * t2 + 0.2226347 * t + 0.24039;
    }
    var y: f32 = 0;
    if (cct <= 2222) {
        y = -1.1063814 * x * x * x - 1.34811020 * x * x + 2.18555832 * x - 0.20219683;
    } else if (cct <= 4000) {
        y = -0.9549476 * x * x * x - 1.37418593 * x * x + 2.09137015 * x - 0.16748867;
    } else {
        y = 3.0817580 * x * x * x - 5.87338670 * x * x + 3.75112997 * x - 0.37001483;
    }
    return .{ x, y };
}

// CIE xy to CCT (Robertson's method approximation)
pub fn xyToCct(x: f32, y: f32) f32 {
    if (y <= 0) return 6500;
    const n = (x - 0.3320) / (y - 0.1858);
    return -449.0 * n * n * n + 3525.0 * n * n - 6823.3 * n + 5520.33;
}

// Compute tint from xy chromaticity (perpendicular to Planckian locus)
pub fn xyToTint(x: f32, y: f32) f32 {
    const cct = xyToCct(x, y);
    const planckian = cctToXy(cct);
    // Tint = signed distance perpendicular to the locus
    // Positive = green shift, negative = magenta shift
    const dx = x - planckian[0];
    const dy = y - planckian[1];
    // Normal direction to locus at this CCT
    const cct2 = cct + 10;
    const p2 = cctToXy(cct2);
    const tx = p2[0] - planckian[0];
    const ty = p2[1] - planckian[1];
    const len = approxSqrt(tx * tx + ty * ty);
    if (len == 0) return 0;
    // Perpendicular = rotate tangent 90°
    const nx = -ty / len;
    const ny = tx / len;
    return dx * nx + dy * ny;
}

// Convert CCT + tint to xy chromaticity
pub fn cctTintToXy(cct: f32, tint: f32) [2]f32 {
    const base = cctToXy(cct);
    if (tint == 0) return base;
    // Compute perpendicular direction
    const cct2 = cct + 10;
    const p2 = cctToXy(cct2);
    const tx = p2[0] - base[0];
    const ty = p2[1] - base[1];
    const len = approxSqrt(tx * tx + ty * ty);
    if (len == 0) return base;
    const nx = -ty / len;
    const ny = tx / len;
    return .{ base[0] + tint * nx, base[1] + tint * ny };
}

// XYZ from CCT
pub fn cctToXyz(cct: f32) types.Xyz {
    const xy = cctToXy(cct);
    if (xy[1] <= 0) return .{};
    return .{
        .x = xy[0] / xy[1],
        .y = 1.0,
        .z = (1.0 - xy[0] - xy[1]) / xy[1],
    };
}

// Mired (micro reciprocal degrees)
pub fn cctToMired(cct: f32) f32 {
    if (cct <= 0) return 0;
    return 1e6 / cct;
}

pub fn miredToCct(mired: f32) f32 {
    if (mired <= 0) return 0;
    return 1e6 / mired;
}

// Color temperature shift in mireds
pub fn miredShift(from_cct: f32, to_cct: f32) f32 {
    return cctToMired(to_cct) - cctToMired(from_cct);
}

// Interpolate between two color temperatures
pub fn interpCct(cct_a: f32, cct_b: f32, t: f32) f32 {
    // Interpolate in mired space for perceptual uniformity
    const ma = cctToMired(cct_a);
    const mb = cctToMired(cct_b);
    return miredToCct(ma * (1.0 - t) + mb * t);
}

// Generate a CCT ramp
pub fn cctRamp(output: []f32, count: usize, cct_start: f32, cct_end: f32) void {
    if (count < 2) return;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(count - 1));
        output[i] = interpCct(cct_start, cct_end, t);
    }
}

// Daylight locus (CIE D-series) chromaticity from CCT
pub fn daylightXy(cct: f32) [2]f32 {
    if (cct < 4000 or cct > 25000) return cctToXy(cct);
    const t = 1e3 / cct;
    var xd: f32 = 0;
    if (cct <= 7000) {
        xd = -4.6070e9 * t * t * t + 2.9678e6 * t * t + 0.09911e3 * t + 0.244063;
    } else {
        xd = -2.0064e9 * t * t * t + 1.9018e6 * t * t + 0.24748e3 * t + 0.237040;
    }
    const yd = -3.0 * xd * xd + 2.87 * xd - 0.275;
    return .{ xd, yd };
}
