// chromadapt.zig - advanced chromatic adaptation
//
// CIECAM02-based chromatic adaptation with degree of adaptation
// computation, surround factors, and luminance-level adaptation.

const types = @import("types.zig");

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
    const ln = -(u + u * u * 0.5 + u * u * u / 3.0);
    const t = g * ln;
    var sum: f32 = 1.0;
    var term: f32 = 1.0;
    var i: u32 = 1;
    while (i <= 10) : (i += 1) { term *= t / @as(f32, @floatFromInt(i)); sum += term; }
    return sum;
}

fn approxExp(x: f32) f32 {
    var sum: f32 = 1.0;
    var term: f32 = 1.0;
    var k: u32 = 1;
    while (k <= 12) : (k += 1) { term *= x / @as(f32, @floatFromInt(k)); sum += term; }
    return sum;
}

pub const ViewingConditions = struct {
    la: f32 = 64.0,
    yb: f32 = 20.0,
    surround: f32 = 1.0,
    adapting_luminance: f32 = 200.0,
    white: types.Xyz = .{ .x = 0.9505, .y = 1.0, .z = 1.089 },
    degree_of_adaptation: f32 = 1.0,
};

const cat02_m = [9]f32{
    0.7328, 0.4296, -0.1624,
    -0.7036, 1.6975, 0.0061,
    0.0030, 0.0136, 0.9834,
};

const cat02_inv = [9]f32{
    1.0961, -0.2789, 0.1827,
    0.4544, 0.4735, 0.0721,
    -0.0096, -0.0057, 1.0153,
};

fn matApply(m: [9]f32, v: [3]f32) [3]f32 {
    return .{
        m[0] * v[0] + m[1] * v[1] + m[2] * v[2],
        m[3] * v[0] + m[4] * v[1] + m[5] * v[2],
        m[6] * v[0] + m[7] * v[1] + m[8] * v[2],
    };
}

// Compute degree of adaptation from luminance level
pub fn degreeOfAdaptation(la: f32, surround: f32) f32 {
    if (la <= 0) return 0;
    const f = surround;
    const d = f * (1.0 - (1.0 / 3.6) * approxExp((-la - 42.0) / 92.0));
    if (d < 0) return 0;
    if (d > 1) return 1;
    return d;
}

// Forward CAT02 adaptation
pub fn forwardAdapt(xyz: [3]f32, vc: *const ViewingConditions) [3]f32 {
    const rgb = matApply(cat02_m, xyz);
    const w_rgb = matApply(cat02_m, .{ vc.white.x, vc.white.y, vc.white.z });
    const d = vc.degree_of_adaptation;

    var adapted: [3]f32 = undefined;
    for (0..3) |i| {
        const factor = if (w_rgb[i] != 0) (d * vc.adapting_luminance / w_rgb[i] + 1.0 - d) else 1.0;
        adapted[i] = rgb[i] * factor;
    }

    return matApply(cat02_inv, adapted);
}

// Inverse CAT02 adaptation
pub fn inverseAdapt(xyz: [3]f32, vc: *const ViewingConditions) [3]f32 {
    const rgb = matApply(cat02_m, xyz);
    const w_rgb = matApply(cat02_m, .{ vc.white.x, vc.white.y, vc.white.z });
    const d = vc.degree_of_adaptation;

    var unadapted: [3]f32 = undefined;
    for (0..3) |i| {
        const factor = if (w_rgb[i] != 0) (d * vc.adapting_luminance / w_rgb[i] + 1.0 - d) else 1.0;
        unadapted[i] = if (factor != 0) rgb[i] / factor else rgb[i];
    }

    return matApply(cat02_inv, unadapted);
}

// Corresponding colors: transform from viewing condition A to B
pub fn correspondingColors(xyz: [3]f32, from: *const ViewingConditions, to: *const ViewingConditions) [3]f32 {
    const adapted = forwardAdapt(xyz, from);
    return inverseAdapt(adapted, to);
}

// Hunt effect: increase colorfulness with adaptation luminance
pub fn huntEffect(chroma: f32, la: f32) f32 {
    if (la <= 0) return chroma;
    const factor = 1.0 + 0.2 * approxSqrt(la / 200.0);
    return chroma * factor;
}

// Stevens effect: change in perceived brightness with adaptation
pub fn stevensEffect(lightness: f32, la: f32) f32 {
    if (la <= 0) return lightness;
    const factor = 1.0 + 0.1 * approxSqrt(la / 200.0);
    return 50.0 + (lightness - 50.0) * factor;
}

// Helson-Judd effect: hue shift near achromatic colors
pub fn helsonJuddShift(lab: *[3]f32) void {
    const c = approxSqrt(lab[1] * lab[1] + lab[2] * lab[2]);
    if (c < 5.0 and c > 0) {
        // Small desaturation near neutral
        const factor = c / 5.0;
        lab[1] *= factor;
        lab[2] *= factor;
    }
}

// Compute the adaptation white from a mixed illuminant
pub fn mixedIlluminant(a: types.Xyz, b: types.Xyz, ratio: f32) types.Xyz {
    return .{
        .x = a.x * (1.0 - ratio) + b.x * ratio,
        .y = a.y * (1.0 - ratio) + b.y * ratio,
        .z = a.z * (1.0 - ratio) + b.z * ratio,
    };
}

// Batch corresponding colors
pub fn batchCorresponding(xyz: []f32, count: usize, from: *const ViewingConditions, to: *const ViewingConditions) void {
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const triplet = [3]f32{ xyz[i * 3], xyz[i * 3 + 1], xyz[i * 3 + 2] };
        const result = correspondingColors(triplet, from, to);
        xyz[i * 3] = result[0];
        xyz[i * 3 + 1] = result[1];
        xyz[i * 3 + 2] = result[2];
    }
}

// Estimate ambient luminance from display luminance and surround
pub fn estimateAmbient(display_lum: f32, surround: f32) f32 {
    return display_lum * surround * 0.2;
}
