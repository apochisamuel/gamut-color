// munsell.zig - Munsell color system conversion
//
// Convert between Munsell HVC notation and CIE Lab values.
// Includes hue name mapping, chroma scaling, and value-to-lightness
// tables based on the Munsell renotation dataset.

fn approxSqrt(x: f32) f32 {
    if (x <= 0) return 0;
    var y = x;
    var k: u32 = 0;
    while (k < 8) : (k += 1) y = (y + x / y) * 0.5;
    return y;
}

fn cos_a(x: f32) f32 {
    const x2 = x * x;
    return 1.0 - x2 * 0.5 + x2 * x2 / 24.0 - x2 * x2 * x2 / 720.0;
}

fn sin_a(x: f32) f32 {
    const x2 = x * x;
    return x - x * x2 / 6.0 + x * x2 * x2 / 120.0;
}

pub const MunsellHue = enum(u8) {
    R = 0, YR = 1, Y = 2, GY = 3, G = 4,
    BG = 5, B = 6, PB = 7, P = 8, RP = 9,
};

pub const MunsellColor = struct {
    hue: MunsellHue = .R,
    hue_step: f32 = 5.0,
    value: f32 = 5.0,
    chroma: f32 = 6.0,
};

// Hue angles in degrees for each Munsell hue family at step 5
const hue_angles = [10]f32{
    28.0,  // 5R
    55.0,  // 5YR
    82.0,  // 5Y
    112.0, // 5GY
    155.0, // 5G
    190.0, // 5BG
    225.0, // 5B
    265.0, // 5PB
    305.0, // 5P
    340.0, // 5RP
};

// Munsell value to CIE L* (Godlove approximation)
pub fn valueToL(v: f32) f32 {
    if (v <= 0) return 0;
    if (v >= 10) return 100;
    // Munsell value formula: Y = 1.2219V - 0.23111V² + 0.23951V³ - 0.021009V⁴ + 0.0008404V⁵
    const v2 = v * v;
    const v3 = v2 * v;
    const v4 = v3 * v;
    const v5 = v4 * v;
    var y = 1.2219 * v - 0.23111 * v2 + 0.23951 * v3 - 0.021009 * v4 + 0.0008404 * v5;
    if (y < 0) y = 0;
    if (y > 100) y = 100;
    // Y to L*
    const yn = y / 100.0;
    if (yn > 0.008856) {
        var cb = yn;
        var k: u32 = 0;
        while (k < 12) : (k += 1) cb = (2.0 * cb + yn / (cb * cb)) / 3.0;
        return 116.0 * cb - 16.0;
    }
    return 903.3 * yn;
}

// CIE L* to Munsell value (inverse)
pub fn lToValue(l: f32) f32 {
    // Binary search for the value that maps to this L*
    var lo: f32 = 0;
    var hi: f32 = 10;
    var k: u32 = 0;
    while (k < 30) : (k += 1) {
        const mid = (lo + hi) * 0.5;
        if (valueToL(mid) < l) lo = mid else hi = mid;
    }
    return (lo + hi) * 0.5;
}

// Munsell HVC to Lab
pub fn hvcToLab(mc: MunsellColor) [3]f32 {
    const l = valueToL(mc.value);

    // Hue angle interpolation
    const base_angle = hue_angles[@intFromEnum(mc.hue)];
    const step_offset = (mc.hue_step - 5.0) * 3.6; // 36° per hue family / 10 steps
    const h_rad = (base_angle + step_offset) * 3.14159 / 180.0;

    // Chroma to a*b* magnitude
    // Munsell chroma is roughly 5× Lab chroma for mid-value colors
    const lab_chroma = mc.chroma * 5.0;

    return .{
        l,
        lab_chroma * cos_a(h_rad),
        lab_chroma * sin_a(h_rad),
    };
}

// Lab to approximate Munsell HVC
pub fn labToHvc(lab: [3]f32) MunsellColor {
    var mc = MunsellColor{};
    mc.value = lToValue(lab[0]);

    const c = approxSqrt(lab[1] * lab[1] + lab[2] * lab[2]);
    mc.chroma = c / 5.0;

    // Compute hue angle
    var h_deg = computeHueDeg(lab[1], lab[2]);
    if (h_deg < 0) h_deg += 360.0;

    // Find closest hue family
    var best: usize = 0;
    var best_dist: f32 = 360;
    for (hue_angles, 0..) |ha, i| {
        var d = h_deg - ha;
        if (d < 0) d = -d;
        if (d > 180) d = 360 - d;
        if (d < best_dist) {
            best_dist = d;
            best = i;
        }
    }
    mc.hue = @enumFromInt(best);

    // Step within hue family
    var delta = h_deg - hue_angles[best];
    if (delta > 180) delta -= 360;
    if (delta < -180) delta += 360;
    mc.hue_step = 5.0 + delta / 3.6;
    if (mc.hue_step < 0) mc.hue_step = 0;
    if (mc.hue_step > 10) mc.hue_step = 10;

    return mc;
}

fn computeHueDeg(a: f32, b: f32) f32 {
    const ax = if (a < 0) -a else a;
    const ay = if (b < 0) -b else b;
    if (ax < 1e-10 and ay < 1e-10) return 0;
    const at = if (ax >= ay) ay / ax else ax / ay;
    const t = at * at;
    var r = ((-0.0465 * t + 0.1593) * t - 0.3276) * t * at + at;
    if (ax < ay) r = 1.5708 - r;
    if (a < 0) r = 3.14159 - r;
    if (b < 0) r = -r;
    return r * 180.0 / 3.14159;
}

// Generate a Munsell hue circle at a given value and chroma
pub fn hueCircle(value: f32, chroma_val: f32, output: []f32, steps: u32) void {
    if (steps < 2) return;
    var i: u32 = 0;
    while (i < steps) : (i += 1) {
        const hue_deg = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(steps)) * 360.0;
        const hue_idx: usize = @intFromFloat(hue_deg / 36.0);
        const mc = MunsellColor{
            .hue = @enumFromInt(if (hue_idx < 10) hue_idx else 0),
            .hue_step = 5.0,
            .value = value,
            .chroma = chroma_val,
        };
        const lab = hvcToLab(mc);
        output[i * 3] = lab[0];
        output[i * 3 + 1] = lab[1];
        output[i * 3 + 2] = lab[2];
    }
}

// Generate a Munsell value scale (neutral axis)
pub fn valueScale(output: []f32, steps: u32) void {
    var i: u32 = 0;
    while (i < steps) : (i += 1) {
        const v = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(steps - 1)) * 10.0;
        output[i] = valueToL(v);
    }
}

// Compute Munsell chroma at maximum for a given hue and value
pub fn maxChroma(hue: MunsellHue, value: f32) f32 {
    // Simplified model: max chroma depends on value
    const v_factor = if (value < 5) value / 5.0 else (10.0 - value) / 5.0;
    const hue_factor: f32 = switch (hue) {
        .R, .YR => 16.0,
        .Y, .GY => 14.0,
        .G, .BG => 10.0,
        .B, .PB => 12.0,
        .P, .RP => 14.0,
    };
    return hue_factor * v_factor;
}
