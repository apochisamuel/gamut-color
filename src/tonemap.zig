// tonemap.zig - HDR tone mapping operators
//
// Map high dynamic range luminance values to displayable range.
// Implements Reinhard, filmic, ACES, and PQ (Perceptual Quantizer)
// transfer functions for HDR color management.

fn approxSqrt(x: f32) f32 {
    if (x <= 0) return 0;
    var y = x;
    var k: u32 = 0;
    while (k < 8) : (k += 1) y = (y + x / y) * 0.5;
    return y;
}

fn approxPow(x: f32, g: f32) f32 {
    if (x <= 0) return 0;
    const u = 1.0 - x;
    const ln_x = -(u + u * u * 0.5 + u * u * u / 3.0);
    const t = g * ln_x;
    var sum: f32 = 1.0;
    var term: f32 = 1.0;
    var i: u32 = 1;
    while (i <= 12) : (i += 1) {
        term *= t / @as(f32, @floatFromInt(i));
        sum += term;
    }
    return sum;
}

pub const ToneMapOp = enum(u8) {
    reinhard = 0,
    reinhard_extended = 1,
    filmic_hable = 2,
    aces_approx = 3,
    exposure = 4,
    linear_clamp = 5,
};

pub const ToneMapParams = struct {
    op: ToneMapOp = .reinhard,
    max_luminance: f32 = 1000.0,
    display_max: f32 = 100.0,
    exposure: f32 = 1.0,
    white_point: f32 = 4.0,
    shoulder: f32 = 0.22,
    linear_strength: f32 = 0.30,
    linear_angle: f32 = 0.10,
    toe_strength: f32 = 0.20,
    toe_numerator: f32 = 0.01,
    toe_denominator: f32 = 0.30,
};

// Reinhard simple: L_out = L / (1 + L)
pub fn reinhard(l: f32) f32 {
    if (l <= 0) return 0;
    return l / (1.0 + l);
}

// Reinhard extended: L_out = L(1 + L/Lw²) / (1 + L)
pub fn reinhardExtended(l: f32, l_white: f32) f32 {
    if (l <= 0) return 0;
    const lw2 = l_white * l_white;
    return l * (1.0 + l / lw2) / (1.0 + l);
}

// Hable/Uncharted 2 filmic curve
fn hablePartial(x: f32, p: *const ToneMapParams) f32 {
    const a = p.shoulder;
    const b = p.linear_strength;
    const c = p.linear_angle;
    const d = p.toe_strength;
    const e = p.toe_numerator;
    const f = p.toe_denominator;
    return ((x * (a * x + c * b) + d * e) / (x * (a * x + b) + d * f)) - e / f;
}

pub fn filmicHable(l: f32, params: *const ToneMapParams) f32 {
    if (l <= 0) return 0;
    const curr = hablePartial(l * params.exposure, params);
    const white = hablePartial(params.white_point, params);
    if (white <= 0) return 0;
    return curr / white;
}

// ACES approximation (Krzysztof Narkowicz)
pub fn acesApprox(x: f32) f32 {
    if (x <= 0) return 0;
    const a: f32 = 2.51;
    const b: f32 = 0.03;
    const c: f32 = 2.43;
    const d: f32 = 0.59;
    const e: f32 = 0.14;
    var v = (x * (a * x + b)) / (x * (c * x + d) + e);
    if (v < 0) v = 0;
    if (v > 1) v = 1;
    return v;
}

// Simple exposure adjustment
pub fn exposureAdjust(l: f32, ev: f32) f32 {
    if (l <= 0) return 0;
    var scale: f32 = 1.0;
    if (ev > 0) {
        var k: u32 = 0;
        while (k < @as(u32, @intFromFloat(ev))) : (k += 1) scale *= 2.0;
    } else if (ev < 0) {
        var k: u32 = 0;
        while (k < @as(u32, @intFromFloat(-ev))) : (k += 1) scale *= 0.5;
    }
    return l * scale;
}

// PQ EOTF (Perceptual Quantizer, SMPTE ST 2084)
pub fn pqEotf(n: f32) f32 {
    if (n <= 0) return 0;
    const m1: f32 = 0.1593017578125;
    const m2: f32 = 78.84375;
    const c1: f32 = 0.8359375;
    const c2: f32 = 18.8515625;
    const c3: f32 = 18.6875;

    // n^(1/m2)
    var np = approxPow(n, 1.0 / m2);
    if (np < 0) np = 0;
    var num = np - c1;
    if (num < 0) num = 0;
    var den = c2 - c3 * np;
    if (den <= 0) return 0;
    return 10000.0 * approxPow(num / den, 1.0 / m1);
}

// PQ inverse EOTF
pub fn pqInvEotf(l: f32) f32 {
    if (l <= 0) return 0;
    const y = l / 10000.0;
    const m1: f32 = 0.1593017578125;
    const m2: f32 = 78.84375;
    const c1: f32 = 0.8359375;
    const c2: f32 = 18.8515625;
    const c3: f32 = 18.6875;

    const ym1 = approxPow(y, m1);
    const num = c1 + c2 * ym1;
    const den = 1.0 + c3 * ym1;
    if (den <= 0) return 0;
    return approxPow(num / den, m2);
}

// HLG OETF (Hybrid Log-Gamma, ARIB STD-B67)
pub fn hlgOetf(l: f32) f32 {
    if (l <= 0) return 0;
    const a: f32 = 0.17883277;
    const b: f32 = 0.28466892;
    const c: f32 = 0.55991073;
    if (l <= 1.0 / 12.0) {
        return approxSqrt(3.0 * l);
    }
    // ln approximation
    var v = l;
    var r: f32 = 0;
    while (v >= 2.0) { v *= 0.5; r += 0.6931; }
    const u = v - 1.0;
    r += u - u * u * 0.5;
    return a * r + b + c;
}

// Dispatch tone map operator
pub fn toneMap(l: f32, params: *const ToneMapParams) f32 {
    return switch (params.op) {
        .reinhard => reinhard(l * params.exposure),
        .reinhard_extended => reinhardExtended(l * params.exposure, params.white_point),
        .filmic_hable => filmicHable(l, params),
        .aces_approx => acesApprox(l * params.exposure),
        .exposure => blk: {
            var v = exposureAdjust(l, params.exposure);
            if (v > 1) v = 1;
            break :blk v;
        },
        .linear_clamp => if (l * params.exposure > 1) @as(f32, 1) else l * params.exposure,
    };
}

// Batch tone map RGB
pub fn toneMapBatch(rgb: []f32, count: u32, params: *const ToneMapParams) void {
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        const base = @as(usize, i) * 3;
        rgb[base] = toneMap(rgb[base], params);
        rgb[base + 1] = toneMap(rgb[base + 1], params);
        rgb[base + 2] = toneMap(rgb[base + 2], params);
    }
}

// Luminance-based tone mapping (preserve chroma ratios)
pub fn toneMapLuminance(rgb: *[3]f32, params: *const ToneMapParams) void {
    const lum = 0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2];
    if (lum <= 0) return;
    const mapped = toneMap(lum, params);
    const scale = mapped / lum;
    rgb[0] *= scale;
    rgb[1] *= scale;
    rgb[2] *= scale;
}
