// gamutbd.zig - gamut boundary descriptor
//
// Compute the gamut boundary of a color profile by sampling the device
// space and projecting through the transform. Supports gamut containment
// testing and volume estimation.

const types = @import("types.zig");

fn approxSqrt(x: f32) f32 {
    if (x <= 0) return 0;
    var y = x;
    var k: u32 = 0;
    while (k < 8) : (k += 1) y = (y + x / y) * 0.5;
    return y;
}

pub const GamutPoint = struct {
    lab: [3]f32 = .{ 0, 0, 0 },
    device: [types.MAX_CHANNELS]f32 = [_]f32{0} ** types.MAX_CHANNELS,
    chroma: f32 = 0,
    hue: f32 = 0,
    lightness: f32 = 0,
};

pub const GamutSlice = struct {
    hue: f32 = 0,
    points: [64]GamutPoint = undefined,
    count: usize = 0,
    max_chroma: f32 = 0,
    min_lightness: f32 = 100,
    max_lightness: f32 = 0,
};

pub const GamutDesc = struct {
    slices: [36]GamutSlice = undefined,
    num_slices: usize = 0,
    total_points: u32 = 0,
    volume_estimate: f32 = 0,
    white: [3]f32 = .{ 100, 0, 0 },
    black: [3]f32 = .{ 0, 0, 0 },
};

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

// Sample the gamut at a single device value
fn sampleGamut(dev: [3]f32) GamutPoint {
    var pt = GamutPoint{};
    pt.device[0] = dev[0];
    pt.device[1] = dev[1];
    pt.device[2] = dev[2];
    // Placeholder: directly map device to Lab-like values
    pt.lab[0] = dev[0] * 100.0;
    pt.lab[1] = (dev[1] - 0.5) * 200.0;
    pt.lab[2] = (dev[2] - 0.5) * 200.0;
    pt.lightness = pt.lab[0];
    pt.chroma = approxSqrt(pt.lab[1] * pt.lab[1] + pt.lab[2] * pt.lab[2]);
    pt.hue = atan2(pt.lab[2], pt.lab[1]);
    return pt;
}

// Build a gamut descriptor by sampling device space edges
pub fn buildGamut(grid_size: u8) GamutDesc {
    var gd = GamutDesc{};
    if (grid_size < 3 or grid_size > 33) return gd;

    const g = grid_size;
    const step = 1.0 / @as(f32, @floatFromInt(g - 1));

    // Sample face i=0 and i=max
    var j: u8 = 0;
    while (j < g) : (j += 1) {
        var k: u8 = 0;
        while (k < g) : (k += 1) {
            const jf = @as(f32, @floatFromInt(j)) * step;
            const kf = @as(f32, @floatFromInt(k)) * step;
            addToGamut(&gd, sampleGamut(.{ 0, jf, kf }));
            addToGamut(&gd, sampleGamut(.{ 1, jf, kf }));
            addToGamut(&gd, sampleGamut(.{ jf, 0, kf }));
            addToGamut(&gd, sampleGamut(.{ jf, 1, kf }));
            addToGamut(&gd, sampleGamut(.{ jf, kf, 0 }));
            addToGamut(&gd, sampleGamut(.{ jf, kf, 1 }));
        }
    }

    gd.volume_estimate = estimateVolume(&gd);
    return gd;
}

fn addToGamut(gd: *GamutDesc, pt: GamutPoint) void {
    // Assign to hue slice (36 slices × 10 degrees)
    var hue_deg = pt.hue * 180.0 / 3.14159;
    if (hue_deg < 0) hue_deg += 360.0;
    var slice_idx: usize = @intFromFloat(hue_deg / 10.0);
    if (slice_idx >= 36) slice_idx = 35;

    if (gd.num_slices == 0) {
        gd.num_slices = 36;
        for (&gd.slices, 0..) |*s, i| {
            s.hue = @as(f32, @floatFromInt(i)) * 10.0;
            s.count = 0;
        }
    }

    var sl = &gd.slices[slice_idx];
    if (sl.count < 64) {
        sl.points[sl.count] = pt;
        sl.count += 1;
        if (pt.chroma > sl.max_chroma) sl.max_chroma = pt.chroma;
        if (pt.lightness < sl.min_lightness) sl.min_lightness = pt.lightness;
        if (pt.lightness > sl.max_lightness) sl.max_lightness = pt.lightness;
        gd.total_points += 1;
    }
}

fn estimateVolume(gd: *const GamutDesc) f32 {
    var total: f32 = 0;
    for (gd.slices[0..gd.num_slices]) |sl| {
        if (sl.count == 0) continue;
        const l_range = sl.max_lightness - sl.min_lightness;
        total += sl.max_chroma * sl.max_chroma * l_range;
    }
    return total * 3.14159 / @as(f32, @floatFromInt(if (gd.num_slices > 0) gd.num_slices else 1));
}

// Test if a Lab point is inside the gamut (approximate)
pub fn contains(gd: *const GamutDesc, lab: [3]f32) bool {
    if (gd.num_slices == 0) return false;
    const c = approxSqrt(lab[1] * lab[1] + lab[2] * lab[2]);
    var hue_deg = atan2(lab[2], lab[1]) * 180.0 / 3.14159;
    if (hue_deg < 0) hue_deg += 360.0;
    var slice_idx: usize = @intFromFloat(hue_deg / 10.0);
    if (slice_idx >= gd.num_slices) slice_idx = gd.num_slices - 1;
    const sl = &gd.slices[slice_idx];
    return c <= sl.max_chroma and lab[0] >= sl.min_lightness and lab[0] <= sl.max_lightness;
}

// Compute gamut coverage as fraction of a reference gamut
pub fn coverage(gd: *const GamutDesc, ref: *const GamutDesc) f32 {
    if (ref.num_slices == 0) return 0;
    var inside: u32 = 0;
    var total: u32 = 0;
    for (ref.slices[0..ref.num_slices]) |sl| {
        for (sl.points[0..sl.count]) |pt| {
            total += 1;
            if (contains(gd, pt.lab)) inside += 1;
        }
    }
    if (total == 0) return 0;
    return @as(f32, @floatFromInt(inside)) / @as(f32, @floatFromInt(total));
}
