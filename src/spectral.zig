// spectral.zig - spectral power distribution math
//
// Representation and conversion of spectral data. Handles reflectance
// spectra, spectral power distributions, and conversion to XYZ via
// CIE standard observer integration.

const types = @import("types.zig");

pub const LAMBDA_MIN: u32 = 380;
pub const LAMBDA_MAX: u32 = 780;
pub const LAMBDA_STEP: u32 = 5;
pub const N_BANDS: usize = (LAMBDA_MAX - LAMBDA_MIN) / LAMBDA_STEP + 1;

pub const SpectralData = struct {
    values: [N_BANDS]f32 = [_]f32{0} ** N_BANDS,
    lambda_min: u32 = LAMBDA_MIN,
    lambda_step: u32 = LAMBDA_STEP,
    count: usize = N_BANDS,
};

// CIE 1931 2-degree standard observer x-bar (5nm, 380-780nm)
const xbar = [_]f32{
    0.0014, 0.0022, 0.0042, 0.0076, 0.0143, 0.0232, 0.0435, 0.0776,
    0.1344, 0.2148, 0.2839, 0.3285, 0.3483, 0.3481, 0.3362, 0.3187,
    0.2908, 0.2511, 0.1954, 0.1421, 0.0956, 0.0580, 0.0320, 0.0147,
    0.0049, 0.0024, 0.0093, 0.0291, 0.0633, 0.1096, 0.1655, 0.2257,
    0.2904, 0.3597, 0.4334, 0.5121, 0.5945, 0.6784, 0.7621, 0.8425,
    0.9163, 0.9786, 1.0263, 1.0567, 1.0622, 1.0456, 1.0026, 0.9384,
    0.8544, 0.7514, 0.6424, 0.5419, 0.4479, 0.3608, 0.2835, 0.2187,
    0.1649, 0.1212, 0.0874, 0.0636, 0.0468, 0.0329, 0.0227, 0.0158,
    0.0114, 0.0081, 0.0058, 0.0041, 0.0029, 0.0020, 0.0014, 0.0010,
    0.0007, 0.0005, 0.0004, 0.0002, 0.0002, 0.0001, 0.0001, 0.0001,
    0.0000,
};

const ybar = [_]f32{
    0.0000, 0.0001, 0.0001, 0.0002, 0.0004, 0.0006, 0.0012, 0.0022,
    0.0040, 0.0073, 0.0116, 0.0168, 0.0230, 0.0298, 0.0380, 0.0480,
    0.0600, 0.0739, 0.0910, 0.1126, 0.1390, 0.1693, 0.2080, 0.2586,
    0.3230, 0.4073, 0.5030, 0.6082, 0.7100, 0.7932, 0.8620, 0.9149,
    0.9540, 0.9803, 0.9950, 1.0000, 0.9950, 0.9786, 0.9520, 0.9154,
    0.8700, 0.8163, 0.7570, 0.6949, 0.6310, 0.5668, 0.5030, 0.4412,
    0.3810, 0.3210, 0.2650, 0.2170, 0.1750, 0.1382, 0.1070, 0.0816,
    0.0610, 0.0446, 0.0320, 0.0232, 0.0170, 0.0119, 0.0082, 0.0057,
    0.0041, 0.0029, 0.0021, 0.0015, 0.0010, 0.0007, 0.0005, 0.0004,
    0.0003, 0.0002, 0.0001, 0.0001, 0.0001, 0.0000, 0.0000, 0.0000,
    0.0000,
};

const zbar = [_]f32{
    0.0065, 0.0105, 0.0201, 0.0362, 0.0679, 0.1102, 0.2074, 0.3713,
    0.6456, 1.0391, 1.3856, 1.6230, 1.7471, 1.7826, 1.7721, 1.7441,
    1.6692, 1.5281, 1.2876, 1.0419, 0.8130, 0.6162, 0.4652, 0.3533,
    0.2720, 0.2123, 0.1582, 0.1117, 0.0782, 0.0573, 0.0422, 0.0298,
    0.0203, 0.0134, 0.0087, 0.0057, 0.0039, 0.0027, 0.0021, 0.0018,
    0.0017, 0.0014, 0.0011, 0.0010, 0.0008, 0.0006, 0.0003, 0.0002,
    0.0002, 0.0001, 0.0000, 0.0000, 0.0000, 0.0000, 0.0000, 0.0000,
    0.0000, 0.0000, 0.0000, 0.0000, 0.0000, 0.0000, 0.0000, 0.0000,
    0.0000, 0.0000, 0.0000, 0.0000, 0.0000, 0.0000, 0.0000, 0.0000,
    0.0000, 0.0000, 0.0000, 0.0000, 0.0000, 0.0000, 0.0000, 0.0000,
    0.0000,
};

// Convert SPD to XYZ using standard observer integration
pub fn spdToXyz(spd: *const SpectralData) types.Xyz {
    var x: f32 = 0;
    var y: f32 = 0;
    var z: f32 = 0;
    const n = if (spd.count < N_BANDS) spd.count else N_BANDS;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        x += spd.values[i] * xbar[i];
        y += spd.values[i] * ybar[i];
        z += spd.values[i] * zbar[i];
    }
    const step_nm: f32 = @floatFromInt(spd.lambda_step);
    x *= step_nm;
    y *= step_nm;
    z *= step_nm;
    if (y > 0) {
        x /= y;
        z /= y;
        return .{ .x = x, .y = 1.0, .z = z };
    }
    return .{ .x = x, .y = y, .z = z };
}

// Generate D65 illuminant SPD
pub fn d65Spd() SpectralData {
    var spd = SpectralData{};
    var i: usize = 0;
    while (i < N_BANDS) : (i += 1) {
        const lambda: f32 = @floatFromInt(LAMBDA_MIN + i * LAMBDA_STEP);
        spd.values[i] = d65SpectralValue(lambda);
    }
    return spd;
}

fn d65SpectralValue(lambda: f32) f32 {
    // Rough approximation of D65 SPD
    if (lambda < 380 or lambda > 780) return 0;
    const t = (lambda - 380.0) / 400.0;
    return 0.5 + 0.5 * (1.0 - (t - 0.4) * (t - 0.4) * 4.0);
}

// Multiply two SPDs (reflectance × illuminant)
pub fn multiply(a: *const SpectralData, b: *const SpectralData) SpectralData {
    var result = SpectralData{};
    const n = if (a.count < b.count) a.count else b.count;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        result.values[i] = a.values[i] * b.values[i];
    }
    result.count = n;
    return result;
}

// Add two SPDs
pub fn addSpd(a: *const SpectralData, b: *const SpectralData) SpectralData {
    var result = SpectralData{};
    const n = if (a.count < b.count) a.count else b.count;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        result.values[i] = a.values[i] + b.values[i];
    }
    result.count = n;
    return result;
}

// Scale an SPD
pub fn scaleSpd(spd: *const SpectralData, factor: f32) SpectralData {
    var result = SpectralData{};
    var i: usize = 0;
    while (i < spd.count) : (i += 1) {
        result.values[i] = spd.values[i] * factor;
    }
    result.count = spd.count;
    return result;
}

// Compute dominant wavelength
pub fn dominantWavelength(spd: *const SpectralData) f32 {
    var max_val: f32 = 0;
    var max_idx: usize = 0;
    var i: usize = 0;
    while (i < spd.count) : (i += 1) {
        if (spd.values[i] > max_val) {
            max_val = spd.values[i];
            max_idx = i;
        }
    }
    return @floatFromInt(spd.lambda_min + max_idx * spd.lambda_step);
}

// Compute spectral purity
pub fn spectralPurity(spd: *const SpectralData) f32 {
    var sum: f32 = 0;
    var peak: f32 = 0;
    var i: usize = 0;
    while (i < spd.count) : (i += 1) {
        sum += spd.values[i];
        if (spd.values[i] > peak) peak = spd.values[i];
    }
    if (sum <= 0) return 0;
    return peak / sum * @as(f32, @floatFromInt(spd.count));
}

// Compute metamerism index between two SPDs
pub fn metamerismIndex(a: *const SpectralData, b: *const SpectralData) f32 {
    const xyz_a = spdToXyz(a);
    const xyz_b = spdToXyz(b);
    const dx = xyz_a.x - xyz_b.x;
    const dy = xyz_a.y - xyz_b.y;
    const dz = xyz_a.z - xyz_b.z;
    var sum: f32 = 0;
    sum = dx * dx + dy * dy + dz * dz;
    if (sum <= 0) return 0;
    var s = sum;
    var k: u32 = 0;
    while (k < 8) : (k += 1) s = (s + sum / s) * 0.5;
    return s;
}
