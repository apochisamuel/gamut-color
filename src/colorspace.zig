// colorspace.zig - color space conversion math
//
// Analytical transforms between device-independent color spaces:
// CIE XYZ ↔ CIE L*a*b*, XYZ ↔ sRGB linear, sRGB transfer function.
// All use polynomial approximations to avoid std math dependencies.

const types = @import("types.zig");

// Approximate cube root via Newton iteration (for Lab conversion)
fn cbrt(x: f32) f32 {
    if (x <= 0.0) return 0.0;
    var y: f32 = x;
    var k: u32 = 0;
    while (k < 12) : (k += 1) {
        y = (2.0 * y + x / (y * y)) / 3.0;
    }
    return y;
}

// Approximate natural log
fn ln(x: f32) f32 {
    if (x <= 0.0) return -30.0;
    var v = x;
    var r: f32 = 0.0;
    while (v >= 2.0) {
        v *= 0.5;
        r += 0.6931;
    }
    const u = v - 1.0;
    r += u - u * u * 0.5 + u * u * u / 3.0 - u * u * u * u * 0.25;
    return r;
}

// Approximate exp
fn exp_approx(x: f32) f32 {
    var sum: f32 = 1.0;
    var term: f32 = 1.0;
    var k: u32 = 1;
    while (k <= 14) : (k += 1) {
        term *= x / @as(f32, @floatFromInt(k));
        sum += term;
    }
    return sum;
}

// Approximate power function
fn pow_approx(base: f32, exponent: f32) f32 {
    if (base <= 0.0) return 0.0;
    if (base >= 1.0) return 1.0;
    return exp_approx(exponent * ln(base));
}

// Approximate sqrt
fn sqrt(x: f32) f32 {
    if (x <= 0.0) return 0.0;
    var y = x;
    var k: u32 = 0;
    while (k < 10) : (k += 1) {
        y = (y + x / y) * 0.5;
    }
    return y;
}

// D50 white point
pub const d50 = types.Xyz{ .x = 0.9642, .y = 1.0000, .z = 0.8249 };
pub const d65 = types.Xyz{ .x = 0.9505, .y = 1.0000, .z = 1.0890 };

// CIE XYZ to CIE L*a*b* (D50 illuminant)
pub fn xyzToLab(xyz: [3]f32) [3]f32 {
    const xn = xyz[0] / d50.x;
    const yn = xyz[1] / d50.y;
    const zn = xyz[2] / d50.z;

    const fx = labF(xn);
    const fy = labF(yn);
    const fz = labF(zn);

    return .{
        116.0 * fy - 16.0,
        500.0 * (fx - fy),
        200.0 * (fy - fz),
    };
}

fn labF(t: f32) f32 {
    if (t > 0.008856) {
        return cbrt(t);
    }
    return 7.787 * t + 16.0 / 116.0;
}

// CIE L*a*b* to CIE XYZ (D50 illuminant)
pub fn labToXyz(lab: [3]f32) [3]f32 {
    const fy = (lab[0] + 16.0) / 116.0;
    const fx = lab[1] / 500.0 + fy;
    const fz = fy - lab[2] / 200.0;

    return .{
        d50.x * labFInv(fx),
        d50.y * labFInv(fy),
        d50.z * labFInv(fz),
    };
}

fn labFInv(t: f32) f32 {
    if (t > 0.20689) {
        return t * t * t;
    }
    return (t - 16.0 / 116.0) / 7.787;
}

// XYZ to linear sRGB
pub fn xyzToLinearRgb(xyz: [3]f32) [3]f32 {
    return .{
        3.2406 * xyz[0] - 1.5372 * xyz[1] - 0.4986 * xyz[2],
        -0.9689 * xyz[0] + 1.8758 * xyz[1] + 0.0415 * xyz[2],
        0.0557 * xyz[0] - 0.2040 * xyz[1] + 1.0570 * xyz[2],
    };
}

// Linear sRGB to XYZ
pub fn linearRgbToXyz(rgb: [3]f32) [3]f32 {
    return .{
        0.4124 * rgb[0] + 0.3576 * rgb[1] + 0.1805 * rgb[2],
        0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2],
        0.0193 * rgb[0] + 0.1192 * rgb[1] + 0.9505 * rgb[2],
    };
}

// sRGB gamma encode (linear → sRGB)
pub fn srgbGamma(x: f32) f32 {
    if (x <= 0.0031308) return 12.92 * x;
    return 1.055 * pow_approx(x, 1.0 / 2.4) - 0.055;
}

// sRGB gamma decode (sRGB → linear)
pub fn srgbDegamma(x: f32) f32 {
    if (x <= 0.04045) return x / 12.92;
    return pow_approx((x + 0.055) / 1.055, 2.4);
}

// Full pipeline: XYZ → sRGB (with gamma)
pub fn xyzToSrgb(xyz: [3]f32) [3]f32 {
    const lin = xyzToLinearRgb(xyz);
    return .{
        clamp01(srgbGamma(lin[0])),
        clamp01(srgbGamma(lin[1])),
        clamp01(srgbGamma(lin[2])),
    };
}

// Full pipeline: sRGB → XYZ
pub fn srgbToXyz(srgb: [3]f32) [3]f32 {
    const lin = [3]f32{
        srgbDegamma(srgb[0]),
        srgbDegamma(srgb[1]),
        srgbDegamma(srgb[2]),
    };
    return linearRgbToXyz(lin);
}

// Lab to sRGB (through XYZ)
pub fn labToSrgb(lab: [3]f32) [3]f32 {
    return xyzToSrgb(labToXyz(lab));
}

// sRGB to Lab (through XYZ)
pub fn srgbToLab(srgb: [3]f32) [3]f32 {
    return xyzToLab(srgbToXyz(srgb));
}

fn clamp01(x: f32) f32 {
    if (x < 0.0) return 0.0;
    if (x > 1.0) return 1.0;
    return x;
}

// L*a*b* to LCh
pub fn labToLch(lab: [3]f32) [3]f32 {
    const c = sqrt(lab[1] * lab[1] + lab[2] * lab[2]);
    const h = atan2(lab[2], lab[1]);
    return .{ lab[0], c, h };
}

// LCh to L*a*b*
pub fn lchToLab(lch: [3]f32) [3]f32 {
    return .{
        lch[0],
        lch[1] * cos_approx(lch[2]),
        lch[1] * sin_approx(lch[2]),
    };
}

fn atan2(y: f32, x: f32) f32 {
    const ax = if (x < 0) -x else x;
    const ay = if (y < 0) -y else y;
    if (ax < 1e-10 and ay < 1e-10) return 0;
    const a = if (ax >= ay) ay / ax else ax / ay;
    const t = a * a;
    var r = ((-0.0465 * t + 0.1593) * t - 0.3276) * t * a + a;
    if (ax < ay) r = 1.5708 - r;
    if (x < 0) r = 3.14159 - r;
    if (y < 0) r = -r;
    return r;
}

fn cos_approx(x: f32) f32 {
    const x2 = x * x;
    return 1.0 - x2 * 0.5 + x2 * x2 / 24.0 - x2 * x2 * x2 / 720.0;
}

fn sin_approx(x: f32) f32 {
    const x2 = x * x;
    return x - x * x2 / 6.0 + x * x2 * x2 / 120.0;
}

// Chromatic adaptation: Bradford matrix (D50 ↔ D65)
pub fn bradfordD50ToD65(xyz: [3]f32) [3]f32 {
    return .{
        0.9555766 * xyz[0] - 0.0230393 * xyz[1] + 0.0631636 * xyz[2],
        -0.0282895 * xyz[0] + 1.0099416 * xyz[1] + 0.0210077 * xyz[2],
        0.0122982 * xyz[0] - 0.0204830 * xyz[1] + 1.3299098 * xyz[2],
    };
}

pub fn bradfordD65ToD50(xyz: [3]f32) [3]f32 {
    return .{
        1.0478112 * xyz[0] + 0.0228866 * xyz[1] - 0.0501270 * xyz[2],
        0.0295424 * xyz[0] + 0.9904844 * xyz[1] - 0.0170491 * xyz[2],
        -0.0092345 * xyz[0] + 0.0150436 * xyz[1] + 0.7521316 * xyz[2],
    };
}

// Delta E 1976
pub fn deltaE76(a: [3]f32, b: [3]f32) f32 {
    const dL = a[0] - b[0];
    const da = a[1] - b[1];
    const db = a[2] - b[2];
    return sqrt(dL * dL + da * da + db * db);
}

// Delta E 1994 (textiles weighting)
pub fn deltaE94(lab1: [3]f32, lab2: [3]f32) f32 {
    const dL = lab1[0] - lab2[0];
    const da = lab1[1] - lab2[1];
    const db = lab1[2] - lab2[2];
    const c1 = sqrt(lab1[1] * lab1[1] + lab1[2] * lab1[2]);
    const c2 = sqrt(lab2[1] * lab2[1] + lab2[2] * lab2[2]);
    const dc = c1 - c2;
    const dh2 = da * da + db * db - dc * dc;
    const dh = if (dh2 > 0) sqrt(dh2) else 0;
    const sl: f32 = 1.0;
    const sc = 1.0 + 0.048 * c1;
    const sh = 1.0 + 0.014 * c1;
    const tl = dL / sl;
    const tc = dc / sc;
    const th = dh / sh;
    return sqrt(tl * tl + tc * tc + th * th);
}

// Batch convert array of XYZ to Lab
pub fn batchXyzToLab(xyz_arr: []const f32, lab_arr: []f32, count: usize) void {
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const xyz = [3]f32{ xyz_arr[i * 3], xyz_arr[i * 3 + 1], xyz_arr[i * 3 + 2] };
        const lab = xyzToLab(xyz);
        lab_arr[i * 3] = lab[0];
        lab_arr[i * 3 + 1] = lab[1];
        lab_arr[i * 3 + 2] = lab[2];
    }
}
