// primaries.zig - standard RGB primaries database
//
// Reference data for common RGB color spaces including sRGB, Adobe RGB,
// Display P3, BT.2020, and ProPhoto RGB. Provides primary chromaticities,
// white points, and derived normalized primary matrices (NPMs).

const types = @import("types.zig");

pub const ColorSpaceId = enum(u8) {
    srgb = 0,
    adobe_rgb = 1,
    display_p3 = 2,
    bt2020 = 3,
    prophoto = 4,
    bt709 = 5,
    aces_ap0 = 6,
    aces_ap1 = 7,
    dci_p3 = 8,
    rec601_525 = 9,
    rec601_625 = 10,
};

pub const Primaries = struct {
    rx: f32, ry: f32,
    gx: f32, gy: f32,
    bx: f32, by: f32,
    wx: f32, wy: f32,
};

pub const db = [_]Primaries{
    // sRGB / BT.709
    .{ .rx = 0.64, .ry = 0.33, .gx = 0.30, .gy = 0.60, .bx = 0.15, .by = 0.06, .wx = 0.3127, .wy = 0.3290 },
    // Adobe RGB (1998)
    .{ .rx = 0.64, .ry = 0.33, .gx = 0.21, .gy = 0.71, .bx = 0.15, .by = 0.06, .wx = 0.3127, .wy = 0.3290 },
    // Display P3
    .{ .rx = 0.68, .ry = 0.32, .gx = 0.265, .gy = 0.69, .bx = 0.15, .by = 0.06, .wx = 0.3127, .wy = 0.3290 },
    // BT.2020
    .{ .rx = 0.708, .ry = 0.292, .gx = 0.170, .gy = 0.797, .bx = 0.131, .by = 0.046, .wx = 0.3127, .wy = 0.3290 },
    // ProPhoto RGB (ROMM)
    .{ .rx = 0.7347, .ry = 0.2653, .gx = 0.1596, .gy = 0.8404, .bx = 0.0366, .by = 0.0001, .wx = 0.3457, .wy = 0.3585 },
    // BT.709 (same as sRGB primaries)
    .{ .rx = 0.64, .ry = 0.33, .gx = 0.30, .gy = 0.60, .bx = 0.15, .by = 0.06, .wx = 0.3127, .wy = 0.3290 },
    // ACES AP0
    .{ .rx = 0.7347, .ry = 0.2653, .gx = 0.0000, .gy = 1.0000, .bx = 0.0001, .by = -0.0770, .wx = 0.32168, .wy = 0.33767 },
    // ACES AP1 (ACEScg)
    .{ .rx = 0.713, .ry = 0.293, .gx = 0.165, .gy = 0.830, .bx = 0.128, .by = 0.044, .wx = 0.32168, .wy = 0.33767 },
    // DCI-P3 (theater)
    .{ .rx = 0.68, .ry = 0.32, .gx = 0.265, .gy = 0.69, .bx = 0.15, .by = 0.06, .wx = 0.314, .wy = 0.351 },
    // Rec.601 (NTSC 525-line)
    .{ .rx = 0.63, .ry = 0.34, .gx = 0.31, .gy = 0.595, .bx = 0.155, .by = 0.07, .wx = 0.3127, .wy = 0.3290 },
    // Rec.601 (PAL 625-line)
    .{ .rx = 0.64, .ry = 0.33, .gx = 0.29, .gy = 0.60, .bx = 0.15, .by = 0.06, .wx = 0.3127, .wy = 0.3290 },
};

pub fn get(id: ColorSpaceId) Primaries {
    return db[@intFromEnum(id)];
}

// Compute normalized primary matrix from chromaticities
pub fn computeNpm(p: *const Primaries) [9]f32 {
    const xr = p.rx / p.ry;
    const yr: f32 = 1;
    const zr = (1 - p.rx - p.ry) / p.ry;
    const xg = p.gx / p.gy;
    const yg: f32 = 1;
    const zg = (1 - p.gx - p.gy) / p.gy;
    const xb = p.bx / p.by;
    const yb: f32 = 1;
    const zb = (1 - p.bx - p.by) / p.by;
    const xw = p.wx / p.wy;
    const yw: f32 = 1;
    const zw = (1 - p.wx - p.wy) / p.wy;
    const det = xr * (yg * zb - yb * zg) - xg * (yr * zb - yb * zr) + xb * (yr * zg - yg * zr);
    if (det == 0) return .{ 1, 0, 0, 0, 1, 0, 0, 0, 1 };
    const id = 1.0 / det;
    const sr = ((yg * zb - yb * zg) * xw + (xb * zg - xg * zb) * yw + (xg * yb - xb * yg) * zw) * id;
    const sg = ((yb * zr - yr * zb) * xw + (xr * zb - xb * zr) * yw + (xb * yr - xr * yb) * zw) * id;
    const sb = ((yr * zg - yg * zr) * xw + (xg * zr - xr * zg) * yw + (xr * yg - xg * yr) * zw) * id;
    return .{ sr * xr, sg * xg, sb * xb, sr * yr, sg * yg, sb * yb, sr * zr, sg * zg, sb * zb };
}

// Gamut area in xy chromaticity (triangle area)
pub fn gamutArea(p: *const Primaries) f32 {
    return 0.5 * ((p.gx - p.rx) * (p.by - p.ry) - (p.bx - p.rx) * (p.gy - p.ry));
}

// Relative gamut area compared to sRGB
pub fn relativeArea(p: *const Primaries) f32 {
    const srgb = get(.srgb);
    const ref_area = gamutArea(&srgb);
    if (ref_area <= 0) return 0;
    return gamutArea(p) / ref_area;
}

// Check if a chromaticity is inside the triangle
pub fn containsXy(p: *const Primaries, x: f32, y: f32) bool {
    const d1 = sign(x, y, p.rx, p.ry, p.gx, p.gy);
    const d2 = sign(x, y, p.gx, p.gy, p.bx, p.by);
    const d3 = sign(x, y, p.bx, p.by, p.rx, p.ry);
    const has_neg = (d1 < 0) or (d2 < 0) or (d3 < 0);
    const has_pos = (d1 > 0) or (d2 > 0) or (d3 > 0);
    return !(has_neg and has_pos);
}

fn sign(px: f32, py: f32, x1: f32, y1: f32, x2: f32, y2: f32) f32 {
    return (px - x2) * (y1 - y2) - (x1 - x2) * (py - y2);
}
