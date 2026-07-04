// profbuild.zig - profile construction from parameters
//
// Build complete profile binary data from high-level specifications:
// primaries, white point, tone curves, and optional lookup tables.

const types = @import("types.zig");

pub const PrimSet = struct {
    rx: f32 = 0.64, ry: f32 = 0.33,
    gx: f32 = 0.30, gy: f32 = 0.60,
    bx: f32 = 0.15, by: f32 = 0.06,
};

pub const ProfileSpec = struct {
    name: [32]u8 = [_]u8{0} ** 32,
    primaries: PrimSet = .{},
    white_x: f32 = 0.3127,
    white_y: f32 = 0.3290,
    gamma: f32 = 2.2,
    use_srgb_trc: bool = false,
    version: u32 = 0x0400,
    channels: u8 = 3,
};

fn w32(buf: []u8, off: usize, v: u32) void {
    if (off + 4 > buf.len) return;
    buf[off] = @intCast((v >> 24) & 0xFF);
    buf[off + 1] = @intCast((v >> 16) & 0xFF);
    buf[off + 2] = @intCast((v >> 8) & 0xFF);
    buf[off + 3] = @intCast(v & 0xFF);
}

fn w16(buf: []u8, off: usize, v: u16) void {
    if (off + 2 > buf.len) return;
    buf[off] = @intCast((v >> 8) & 0xFF);
    buf[off + 1] = @intCast(v & 0xFF);
}

// Compute XYZ from chromaticity (x,y) at Y=1
fn xyToXyz(x: f32, y: f32) types.Xyz {
    if (y <= 0) return .{};
    return .{ .x = x / y, .y = 1.0, .z = (1.0 - x - y) / y };
}

// Compute the 3x3 NPM from primaries and white point
fn computeNpm(spec: *const ProfileSpec) [9]f32 {
    const rx = spec.primaries.rx;
    const ry = spec.primaries.ry;
    const gx = spec.primaries.gx;
    const gy = spec.primaries.gy;
    const bx = spec.primaries.bx;
    const by = spec.primaries.by;

    const xr = rx / ry;
    const yr: f32 = 1.0;
    const zr = (1.0 - rx - ry) / ry;
    const xg = gx / gy;
    const yg: f32 = 1.0;
    const zg = (1.0 - gx - gy) / gy;
    const xb = bx / by;
    const yb: f32 = 1.0;
    const zb = (1.0 - bx - by) / by;

    // White point
    const xw = spec.white_x / spec.white_y;
    const yw: f32 = 1.0;
    const zw = (1.0 - spec.white_x - spec.white_y) / spec.white_y;

    // Solve for S = [sr, sg, sb] such that [Xr Xg Xb; Yr Yg Yb; Zr Zg Zb] × S = W
    const det = xr * (yg * zb - yb * zg) - xg * (yr * zb - yb * zr) + xb * (yr * zg - yg * zr);
    if (det == 0) return .{ 1, 0, 0, 0, 1, 0, 0, 0, 1 };

    const id = 1.0 / det;
    const sr = ((yg * zb - yb * zg) * xw + (xb * zg - xg * zb) * yw + (xg * yb - xb * yg) * zw) * id;
    const sg = ((yb * zr - yr * zb) * xw + (xr * zb - xb * zr) * yw + (xb * yr - xr * yb) * zw) * id;
    const sb = ((yr * zg - yg * zr) * xw + (xg * zr - xr * zg) * yw + (xr * yg - xg * yr) * zw) * id;

    return .{
        sr * xr, sg * xg, sb * xb,
        sr * yr, sg * yg, sb * yb,
        sr * zr, sg * zg, sb * zb,
    };
}

// Build the binary profile
pub fn buildProfile(spec: *const ProfileSpec, buf: []u8) usize {
    if (buf.len < 512) return 0;
    @memset(buf, 0);

    // Header
    w32(buf, 4, types.sig('g', 'm', 't', 0x01));
    buf[8] = @intCast((spec.version >> 8) & 0xFF);
    buf[9] = @intCast(spec.version & 0xFF);
    buf[15] = 2; // RGB
    buf[19] = 5; // XYZ PCS
    buf[23] = spec.channels;

    var pos: usize = types.HEADER_SIZE;

    // Tag directory: rTRC, gTRC, bTRC, rXYZ, gXYZ, bXYZ, wtpt = 7 tags
    const num_tags: u32 = 7;
    w32(buf, pos, num_tags);
    pos += 4;
    const tag_dir_start = pos;
    pos += num_tags * 12; // reserve space

    // Compute NPM
    const npm = computeNpm(spec);

    // Write curve elements (shared or separate)
    const curve_off: u32 = @intCast(pos);
    const curve_size: u32 = 12; // 4 type + 2 count(1) + 2 pad + 4 gamma
    w32(buf, pos, types.sig('c', 'u', 'r', 'v'));
    w16(buf, pos + 4, 1); // parametric: count=1
    w16(buf, pos + 8, @intFromFloat(spec.gamma / 10.0 * 65535.0));
    pos += curve_size;

    // Write XYZ elements for each primary
    const xyz_r_off: u32 = @intCast(pos);
    w32(buf, pos, types.sig('X', 'Y', 'Z', ' '));
    writeFixed(buf, pos + 4, npm[0]);
    writeFixed(buf, pos + 8, npm[3]);
    writeFixed(buf, pos + 12, npm[6]);
    pos += 16;

    const xyz_g_off: u32 = @intCast(pos);
    w32(buf, pos, types.sig('X', 'Y', 'Z', ' '));
    writeFixed(buf, pos + 4, npm[1]);
    writeFixed(buf, pos + 8, npm[4]);
    writeFixed(buf, pos + 12, npm[7]);
    pos += 16;

    const xyz_b_off: u32 = @intCast(pos);
    w32(buf, pos, types.sig('X', 'Y', 'Z', ' '));
    writeFixed(buf, pos + 4, npm[2]);
    writeFixed(buf, pos + 8, npm[5]);
    writeFixed(buf, pos + 12, npm[8]);
    pos += 16;

    const xyz_w_off: u32 = @intCast(pos);
    w32(buf, pos, types.sig('X', 'Y', 'Z', ' '));
    const w_xyz = xyToXyz(spec.white_x, spec.white_y);
    writeFixed(buf, pos + 4, w_xyz.x);
    writeFixed(buf, pos + 8, w_xyz.y);
    writeFixed(buf, pos + 12, w_xyz.z);
    pos += 16;

    // Fill in tag directory
    var td = tag_dir_start;
    // rTRC
    w32(buf, td, types.sig('r', 'T', 'R', 'C'));
    w32(buf, td + 4, curve_off);
    w32(buf, td + 8, curve_size);
    td += 12;
    // gTRC
    w32(buf, td, types.sig('g', 'T', 'R', 'C'));
    w32(buf, td + 4, curve_off);
    w32(buf, td + 8, curve_size);
    td += 12;
    // bTRC
    w32(buf, td, types.sig('b', 'T', 'R', 'C'));
    w32(buf, td + 4, curve_off);
    w32(buf, td + 8, curve_size);
    td += 12;
    // rXYZ
    w32(buf, td, types.sig('r', 'X', 'Y', 'Z'));
    w32(buf, td + 4, xyz_r_off);
    w32(buf, td + 8, 16);
    td += 12;
    // gXYZ
    w32(buf, td, types.sig('g', 'X', 'Y', 'Z'));
    w32(buf, td + 4, xyz_g_off);
    w32(buf, td + 8, 16);
    td += 12;
    // bXYZ
    w32(buf, td, types.sig('b', 'X', 'Y', 'Z'));
    w32(buf, td + 4, xyz_b_off);
    w32(buf, td + 8, 16);
    td += 12;
    // wtpt
    w32(buf, td, types.sig('w', 't', 'p', 't'));
    w32(buf, td + 4, xyz_w_off);
    w32(buf, td + 8, 16);

    // Write total size
    w32(buf, 0, @intCast(pos));
    return pos;
}

fn writeFixed(buf: []u8, off: usize, v: f32) void {
    const fixed: u32 = @bitCast(@as(i32, @intFromFloat(v * 65536.0)));
    w32(buf, off, fixed);
}

// sRGB profile spec
pub fn srgbSpec() ProfileSpec {
    return .{
        .name = blk: {
            var n = [_]u8{0} ** 32;
            const s = "sRGB";
            @memcpy(n[0..4], s);
            break :blk n;
        },
        .primaries = .{
            .rx = 0.64, .ry = 0.33,
            .gx = 0.30, .gy = 0.60,
            .bx = 0.15, .by = 0.06,
        },
        .white_x = 0.3127,
        .white_y = 0.3290,
        .gamma = 2.2,
        .use_srgb_trc = true,
    };
}

// Adobe RGB profile spec
pub fn adobeRgbSpec() ProfileSpec {
    return .{
        .primaries = .{
            .rx = 0.64, .ry = 0.33,
            .gx = 0.21, .gy = 0.71,
            .bx = 0.15, .by = 0.06,
        },
        .white_x = 0.3127,
        .white_y = 0.3290,
        .gamma = 2.19921875,
    };
}

// Display P3 profile spec
pub fn displayP3Spec() ProfileSpec {
    return .{
        .primaries = .{
            .rx = 0.68, .ry = 0.32,
            .gx = 0.265, .gy = 0.69,
            .bx = 0.15, .by = 0.06,
        },
        .white_x = 0.3127,
        .white_y = 0.3290,
        .gamma = 2.2,
        .use_srgb_trc = true,
    };
}
