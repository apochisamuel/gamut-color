// observer.zig - CIE standard observer data and spectral calculations
//
// 2-degree and 10-degree standard observer color matching functions,
// tristimulus integration, dominant wavelength, and excitation purity
// computation from spectral data.

const types = @import("types.zig");

fn approxSqrt(x: f32) f32 {
    if (x <= 0) return 0;
    var y = x;
    var k: u32 = 0;
    while (k < 8) : (k += 1) y = (y + x / y) * 0.5;
    return y;
}

pub const ObserverType = enum(u8) {
    deg2 = 0,
    deg10 = 1,
};

// CIE 1931 2° observer x̄ (10nm intervals, 380-780nm, 41 values)
const xbar_2deg = [41]f32{
    0.0014, 0.0042, 0.0143, 0.0435, 0.1344, 0.2839, 0.3483, 0.3362,
    0.2908, 0.1954, 0.0956, 0.0320, 0.0049, 0.0093, 0.0633, 0.1655,
    0.2904, 0.4334, 0.5945, 0.7621, 0.9163, 1.0263, 1.0622, 1.0026,
    0.8544, 0.6424, 0.4479, 0.2835, 0.1649, 0.0874, 0.0468, 0.0227,
    0.0114, 0.0058, 0.0029, 0.0014, 0.0007, 0.0004, 0.0002, 0.0001,
    0.0000,
};

const ybar_2deg = [41]f32{
    0.0000, 0.0001, 0.0004, 0.0012, 0.0040, 0.0116, 0.0230, 0.0380,
    0.0600, 0.0910, 0.1390, 0.2080, 0.3230, 0.5030, 0.7100, 0.8620,
    0.9540, 0.9950, 0.9950, 0.9520, 0.8700, 0.7570, 0.6310, 0.5030,
    0.3810, 0.2650, 0.1750, 0.1070, 0.0610, 0.0320, 0.0170, 0.0082,
    0.0041, 0.0021, 0.0010, 0.0005, 0.0003, 0.0001, 0.0001, 0.0000,
    0.0000,
};

const zbar_2deg = [41]f32{
    0.0065, 0.0201, 0.0679, 0.2074, 0.6456, 1.3856, 1.7471, 1.7721,
    1.6692, 1.2876, 0.8130, 0.4652, 0.2720, 0.1582, 0.0782, 0.0422,
    0.0203, 0.0087, 0.0039, 0.0021, 0.0017, 0.0011, 0.0008, 0.0003,
    0.0002, 0.0000, 0.0000, 0.0000, 0.0000, 0.0000, 0.0000, 0.0000,
    0.0000, 0.0000, 0.0000, 0.0000, 0.0000, 0.0000, 0.0000, 0.0000,
    0.0000,
};

// CIE 1964 10° observer x̄ (10nm intervals)
const xbar_10deg = [41]f32{
    0.0002, 0.0089, 0.0304, 0.0846, 0.2045, 0.3147, 0.3837, 0.3707,
    0.3023, 0.1956, 0.0805, 0.0162, 0.0038, 0.0375, 0.1177, 0.2365,
    0.3768, 0.5298, 0.7052, 0.8787, 1.0142, 1.0743, 1.0544, 0.9922,
    0.8434, 0.6327, 0.4317, 0.2683, 0.1526, 0.0813, 0.0409, 0.0199,
    0.0096, 0.0046, 0.0022, 0.0010, 0.0005, 0.0002, 0.0001, 0.0001,
    0.0000,
};

const ybar_10deg = [41]f32{
    0.0000, 0.0001, 0.0003, 0.0008, 0.0021, 0.0073, 0.0159, 0.0282,
    0.0528, 0.0868, 0.1327, 0.1934, 0.2904, 0.4608, 0.6568, 0.8091,
    0.9073, 0.9620, 0.9822, 0.9559, 0.8689, 0.7774, 0.6583, 0.5280,
    0.3981, 0.2835, 0.1798, 0.1076, 0.0603, 0.0318, 0.0159, 0.0077,
    0.0037, 0.0018, 0.0008, 0.0004, 0.0002, 0.0001, 0.0000, 0.0000,
    0.0000,
};

const zbar_10deg = [41]f32{
    0.0007, 0.0427, 0.1547, 0.4264, 1.0509, 1.6026, 1.9485, 1.9116,
    1.6630, 1.2877, 0.8129, 0.4652, 0.2720, 0.1582, 0.0782, 0.0389,
    0.0158, 0.0066, 0.0029, 0.0014, 0.0010, 0.0005, 0.0003, 0.0001,
    0.0001, 0.0000, 0.0000, 0.0000, 0.0000, 0.0000, 0.0000, 0.0000,
    0.0000, 0.0000, 0.0000, 0.0000, 0.0000, 0.0000, 0.0000, 0.0000,
    0.0000,
};

// Get observer function pointer for a given observer type
pub fn getXbar(obs: ObserverType) *const [41]f32 {
    return if (obs == .deg2) &xbar_2deg else &xbar_10deg;
}

pub fn getYbar(obs: ObserverType) *const [41]f32 {
    return if (obs == .deg2) &ybar_2deg else &ybar_10deg;
}

pub fn getZbar(obs: ObserverType) *const [41]f32 {
    return if (obs == .deg2) &zbar_2deg else &zbar_10deg;
}

// Integrate SPD × observer to get XYZ
pub fn integrate(spd: []const f32, obs: ObserverType) types.Xyz {
    const xb = getXbar(obs);
    const yb = getYbar(obs);
    const zb = getZbar(obs);
    const n = if (spd.len < 41) spd.len else 41;
    var x: f32 = 0;
    var y: f32 = 0;
    var z: f32 = 0;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        x += spd[i] * xb[i];
        y += spd[i] * yb[i];
        z += spd[i] * zb[i];
    }
    const step: f32 = 10.0;
    x *= step;
    y *= step;
    z *= step;
    if (y > 0) {
        return .{ .x = x / y, .y = 1.0, .z = z / y };
    }
    return .{ .x = x, .y = y, .z = z };
}

// Dominant wavelength from chromaticity
pub fn dominantWavelength(xyz: types.Xyz) f32 {
    const sum = xyz.x + xyz.y + xyz.z;
    if (sum <= 0) return 0;
    const x = xyz.x / sum;
    const y = xyz.y / sum;
    // White point (equal energy)
    const xw: f32 = 0.3333;
    const yw: f32 = 0.3333;
    // Direction from white to sample
    const dx = x - xw;
    const dy = y - yw;
    // Find intersection with spectral locus (simplified)
    const angle = approxAtan2(dy, dx) * 180.0 / 3.14159;
    // Map angle to wavelength (rough approximation)
    if (angle >= 0 and angle < 90) {
        return 575.0 + angle * 0.5; // yellow-red region
    } else if (angle >= 90 and angle < 180) {
        return 475.0 + (angle - 90) * 1.1; // green-cyan
    } else if (angle >= -180 and angle < -90) {
        return 380.0 + (angle + 180) * 1.0; // violet
    } else {
        return 620.0 + (angle + 90) * 0.5; // red
    }
}

fn approxAtan2(y: f32, x: f32) f32 {
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

// Excitation purity
pub fn excitationPurity(xyz: types.Xyz) f32 {
    const sum = xyz.x + xyz.y + xyz.z;
    if (sum <= 0) return 0;
    const x = xyz.x / sum;
    const y = xyz.y / sum;
    const xw: f32 = 0.3333;
    const yw: f32 = 0.3333;
    const dx = x - xw;
    const dy = y - yw;
    return approxSqrt(dx * dx + dy * dy) * 5.0; // normalized
}

// Colorimetric purity
pub fn colorimetricPurity(xyz: types.Xyz) f32 {
    const sum = xyz.x + xyz.y + xyz.z;
    if (sum <= 0) return 0;
    const y_norm = xyz.y / sum;
    const yw: f32 = 0.3333;
    if (y_norm <= yw) return 0;
    return (y_norm - yw) / (1.0 - yw);
}

// Observer metamerism: compare XYZ under 2° and 10° observers
pub fn observerMetamerism(spd: []const f32) f32 {
    const xyz2 = integrate(spd, .deg2);
    const xyz10 = integrate(spd, .deg10);
    const dx = xyz2.x - xyz10.x;
    const dy = xyz2.y - xyz10.y;
    const dz = xyz2.z - xyz10.z;
    return approxSqrt(dx * dx + dy * dy + dz * dz);
}
