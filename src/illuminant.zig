// illuminant.zig - standard illuminants and color temperature
//
// CIE standard illuminant XYZ values, correlated color temperature (CCT)
// computation via McCamy's approximation, and planckian locus.

const types = @import("types.zig");

fn approxSqrt(x: f32) f32 {
    if (x <= 0) return 0;
    var y = x;
    var k: u32 = 0;
    while (k < 10) : (k += 1) y = (y + x / y) * 0.5;
    return y;
}

fn approxLn(x: f32) f32 {
    if (x <= 0) return -30;
    var v = x;
    var r: f32 = 0;
    while (v >= 2) {
        v *= 0.5;
        r += 0.6931;
    }
    const u = v - 1.0;
    r += u - u * u * 0.5 + u * u * u / 3.0;
    return r;
}

fn approxExp(x: f32) f32 {
    var sum: f32 = 1;
    var term: f32 = 1;
    var k: u32 = 1;
    while (k <= 12) : (k += 1) {
        term *= x / @as(f32, @floatFromInt(k));
        sum += term;
    }
    return sum;
}

// Standard illuminant XYZ values (Y = 1)
pub const Illuminant = struct {
    name: [4]u8 = .{ 0, 0, 0, 0 },
    xyz: types.Xyz = .{},
    cct: f32 = 0,
};

pub const illuminants = [_]Illuminant{
    .{ .name = .{ 'A', ' ', ' ', ' ' }, .xyz = .{ .x = 1.0985, .y = 1.0, .z = 0.3558 }, .cct = 2856 },
    .{ .name = .{ 'B', ' ', ' ', ' ' }, .xyz = .{ .x = 0.9909, .y = 1.0, .z = 0.8531 }, .cct = 4874 },
    .{ .name = .{ 'C', ' ', ' ', ' ' }, .xyz = .{ .x = 0.9807, .y = 1.0, .z = 1.1822 }, .cct = 6774 },
    .{ .name = .{ 'D', '5', '0', ' ' }, .xyz = .{ .x = 0.9642, .y = 1.0, .z = 0.8249 }, .cct = 5003 },
    .{ .name = .{ 'D', '5', '5', ' ' }, .xyz = .{ .x = 0.9568, .y = 1.0, .z = 0.9214 }, .cct = 5503 },
    .{ .name = .{ 'D', '6', '5', ' ' }, .xyz = .{ .x = 0.9505, .y = 1.0, .z = 1.0890 }, .cct = 6504 },
    .{ .name = .{ 'D', '7', '5', ' ' }, .xyz = .{ .x = 0.9497, .y = 1.0, .z = 1.2264 }, .cct = 7504 },
    .{ .name = .{ 'E', ' ', ' ', ' ' }, .xyz = .{ .x = 1.0, .y = 1.0, .z = 1.0 }, .cct = 5454 },
    .{ .name = .{ 'F', '2', ' ', ' ' }, .xyz = .{ .x = 0.9918, .y = 1.0, .z = 0.6740 }, .cct = 4230 },
    .{ .name = .{ 'F', '7', ' ', ' ' }, .xyz = .{ .x = 0.9504, .y = 1.0, .z = 1.0875 }, .cct = 6500 },
    .{ .name = .{ 'F', '1', '1', ' ' }, .xyz = .{ .x = 1.0096, .y = 1.0, .z = 0.6435 }, .cct = 4000 },
};

// McCamy's CCT approximation from chromaticity (x, y)
pub fn cctFromXy(x: f32, y: f32) f32 {
    if (y == 0) return 0;
    const n = (x - 0.3320) / (y - 0.1858);
    return -449.0 * n * n * n + 3525.0 * n * n - 6823.3 * n + 5520.33;
}

// CCT from XYZ tristimulus
pub fn cctFromXyz(xyz: types.Xyz) f32 {
    const sum = xyz.x + xyz.y + xyz.z;
    if (sum <= 0) return 0;
    return cctFromXy(xyz.x / sum, xyz.y / sum);
}

// Planckian locus: XYZ of a blackbody at temperature T (Kelvin)
pub fn planckian(t: f32) types.Xyz {
    if (t < 1000 or t > 25000) return .{};
    // CIE daylight D-series approximation
    const ti = 1e3 / t;
    var xd: f32 = 0;
    if (t <= 7000) {
        xd = 0.244063 + 0.09911 * ti + 2.9678 * ti * ti - 4.6070 * ti * ti * ti;
    } else {
        xd = 0.237040 + 0.24748 * ti + 1.9018 * ti * ti - 2.0064 * ti * ti * ti;
    }
    const yd = -3.0 * xd * xd + 2.87 * xd - 0.275;
    if (yd <= 0) return .{};

    return .{
        .x = xd / yd,
        .y = 1.0,
        .z = (1.0 - xd - yd) / yd,
    };
}

// Find closest standard illuminant
pub fn closestIlluminant(xyz: types.Xyz) usize {
    var best: usize = 0;
    var best_dist: f32 = 1e30;
    for (illuminants, 0..) |ill, i| {
        const dx = xyz.x - ill.xyz.x;
        const dy = xyz.y - ill.xyz.y;
        const dz = xyz.z - ill.xyz.z;
        const dist = approxSqrt(dx * dx + dy * dy + dz * dz);
        if (dist < best_dist) {
            best_dist = dist;
            best = i;
        }
    }
    return best;
}

// Duv: distance from Planckian locus in CIE 1960 UCS
pub fn duv(xyz: types.Xyz) f32 {
    const sum = xyz.x + xyz.y + xyz.z;
    if (sum <= 0) return 0;
    const x = xyz.x / sum;
    const y = xyz.y / sum;
    // Convert to CIE 1960 UCS
    const denom = -2.0 * x + 12.0 * y + 3.0;
    if (denom == 0) return 0;
    const u = 4.0 * x / denom;
    const v = 6.0 * y / denom;

    // Find Duv by checking distance to Planckian locus at nearby CCTs
    const cct = cctFromXy(x, y);
    var min_dist: f32 = 1e30;

    var ti: i32 = -50;
    while (ti <= 50) : (ti += 10) {
        const t = cct + @as(f32, @floatFromInt(ti));
        if (t < 1000) continue;
        const pl = planckian(t);
        const ps = pl.x + pl.y + pl.z;
        if (ps <= 0) continue;
        const px = pl.x / ps;
        const py = pl.y / ps;
        const pd = -2.0 * px + 12.0 * py + 3.0;
        if (pd == 0) continue;
        const pu = 4.0 * px / pd;
        const pv = 6.0 * py / pd;
        const du = u - pu;
        const dv = v - pv;
        const dist = approxSqrt(du * du + dv * dv);
        if (dist < min_dist) min_dist = dist;
    }
    return min_dist;
}

// Color rendering index (CRI) approximation from CCT
pub fn approximateCri(cct: f32) f32 {
    // Rough CRI estimate: daylight sources near 100, others lower
    if (cct < 2000 or cct > 20000) return 60;
    if (cct >= 4000 and cct <= 7000) return 95;
    if (cct >= 2500 and cct <= 4000) return 85;
    return 75;
}

// D-series illuminant from CCT
pub fn dIlluminant(cct: f32) types.Xyz {
    if (cct < 4000 or cct > 25000) return planckian(cct);
    return planckian(cct);
}
