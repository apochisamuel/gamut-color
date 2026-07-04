// halftone.zig - halftone screen simulation
//
// Simulate classical and stochastic halftone screens for print
// color management. Includes AM screening (clustered dot), FM
// screening (error diffusion), and screen angle calculations.

fn approxSqrt(x: f32) f32 {
    if (x <= 0) return 0;
    var y = x;
    var k: u32 = 0;
    while (k < 8) : (k += 1) y = (y + x / y) * 0.5;
    return y;
}

fn sin_a(x: f32) f32 {
    const x2 = x * x;
    return x - x * x2 / 6.0 + x * x2 * x2 / 120.0;
}

fn cos_a(x: f32) f32 {
    const x2 = x * x;
    return 1.0 - x2 * 0.5 + x2 * x2 / 24.0 - x2 * x2 * x2 / 720.0;
}

pub const ScreenType = enum(u8) {
    round_dot = 0,
    elliptical_dot = 1,
    diamond_dot = 2,
    line_screen = 3,
    stochastic = 4,
};

pub const ScreenParams = struct {
    screen_type: ScreenType = .round_dot,
    lpi: f32 = 150.0,
    angle_deg: f32 = 45.0,
    dot_gain: f32 = 0.2,
    min_dot: f32 = 0.02,
    max_dot: f32 = 0.98,
};

// Standard screen angles for CMYK process
pub const cmyk_angles = [4]f32{ 105.0, 75.0, 90.0, 45.0 };

// Compute dot area for a given input coverage
pub fn dotArea(coverage: f32, params: *const ScreenParams) f32 {
    var c = coverage;
    if (c < 0) c = 0;
    if (c > 1) c = 1;

    // Apply Murray-Davies dot gain
    c = murrayDavies(c, params.dot_gain);

    // Enforce minimum/maximum dot
    if (c < params.min_dot and c > 0.001) c = params.min_dot;
    if (c > params.max_dot) c = params.max_dot;

    return c;
}

// Murray-Davies equation for optical dot gain
fn murrayDavies(area: f32, gain: f32) f32 {
    if (area <= 0 or area >= 1) return area;
    return area + gain * area * (1.0 - area) * 4.0;
}

// Yule-Nielsen equation for physical dot gain
pub fn yuleNielsen(area: f32, n: f32) f32 {
    if (area <= 0) return 0;
    if (area >= 1) return 1;
    if (n == 0) return area;
    const t = 1.0 - area;
    var t_n: f32 = 1;
    var k: u32 = 0;
    while (k < 10) : (k += 1) {
        const factor = 1.0 / n;
        _ = factor;
    }
    // Simplified: for n close to 1, use linear approximation
    return area + 0.1 * (n - 1.0) * area * t;
}

// Compute spot function value for a position in the cell
fn spotFunction(x: f32, y: f32, screen_type: ScreenType) f32 {
    return switch (screen_type) {
        .round_dot => 1.0 - approxSqrt(x * x + y * y),
        .elliptical_dot => blk: {
            const sx = x * 0.7;
            const sy = y * 1.3;
            break :blk 1.0 - approxSqrt(sx * sx + sy * sy);
        },
        .diamond_dot => blk: {
            var ax = x;
            if (ax < 0) ax = -ax;
            var ay = y;
            if (ay < 0) ay = -ay;
            break :blk 1.0 - (ax + ay);
        },
        .line_screen => 1.0 - (if (y < 0) -y else y),
        .stochastic => blk: {
            // Simple hash-based dither threshold
            const ix: u32 = @intFromFloat((x + 1.0) * 127.5);
            const iy: u32 = @intFromFloat((y + 1.0) * 127.5);
            const h = (ix *% 2654435761 ^ iy *% 2246822519) & 0xFFFF;
            break :blk @as(f32, @floatFromInt(h)) / 65535.0;
        },
    };
}

// Generate a halftone cell threshold matrix
pub fn generateCell(cell: []f32, size: u32, screen_type: ScreenType) void {
    if (size < 2 or size > 256) return;
    var iy: u32 = 0;
    while (iy < size) : (iy += 1) {
        var ix: u32 = 0;
        while (ix < size) : (ix += 1) {
            const x = 2.0 * @as(f32, @floatFromInt(ix)) / @as(f32, @floatFromInt(size - 1)) - 1.0;
            const y = 2.0 * @as(f32, @floatFromInt(iy)) / @as(f32, @floatFromInt(size - 1)) - 1.0;
            cell[iy * size + ix] = spotFunction(x, y, screen_type);
        }
    }
}

// Apply screen rotation
pub fn rotateCoords(x: f32, y: f32, angle_deg: f32) [2]f32 {
    const rad = angle_deg * 3.14159 / 180.0;
    const cs = cos_a(rad);
    const sn = sin_a(rad);
    return .{
        x * cs - y * sn,
        x * sn + y * cs,
    };
}

// Compute optimal screen angles to minimize moiré
pub fn moireRisk(angles: []const f32, count: usize) f32 {
    var risk: f32 = 0;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        var j: usize = i + 1;
        while (j < count) : (j += 1) {
            var diff = angles[i] - angles[j];
            if (diff < 0) diff = -diff;
            while (diff > 90) diff -= 90;
            if (diff < 15 or diff > 75) {
                risk += 1.0 / (diff + 1.0);
            }
        }
    }
    return risk;
}

// Simulate ink-on-paper dot overlap for two colors
pub fn twoColorOverprint(c1: f32, c2: f32, trapping: f32) f32 {
    return c1 + c2 * (1.0 - c1) * trapping;
}

// Total area coverage for CMYK
pub fn totalAreaCoverage(cmyk: [4]f32) f32 {
    return cmyk[0] + cmyk[1] + cmyk[2] + cmyk[3];
}

// GCR: replace CMY gray component with K
pub fn gcrReplace(cmyk: *[4]f32, amount: f32) void {
    const mn = blk: {
        var m = cmyk[0];
        if (cmyk[1] < m) m = cmyk[1];
        if (cmyk[2] < m) m = cmyk[2];
        break :blk m;
    };
    const k_add = mn * amount;
    cmyk[0] -= k_add;
    cmyk[1] -= k_add;
    cmyk[2] -= k_add;
    cmyk[3] += k_add;
    if (cmyk[3] > 1) cmyk[3] = 1;
}

// UCR: under color removal
pub fn ucrReplace(cmyk: *[4]f32, amount: f32, start: f32) void {
    const mn = blk: {
        var m = cmyk[0];
        if (cmyk[1] < m) m = cmyk[1];
        if (cmyk[2] < m) m = cmyk[2];
        break :blk m;
    };
    if (mn <= start) return;
    const excess = mn - start;
    const k_add = excess * amount;
    cmyk[0] -= k_add;
    cmyk[1] -= k_add;
    cmyk[2] -= k_add;
    cmyk[3] += k_add;
}

// Linearize a press curve
pub fn linearize(input: f32, tvi: []const f32, tvi_count: usize) f32 {
    if (tvi_count < 2) return input;
    var x = input;
    if (x < 0) x = 0;
    if (x > 1) x = 1;
    const pos = x * @as(f32, @floatFromInt(tvi_count - 1));
    const lo: usize = @intFromFloat(pos);
    const hi = if (lo + 1 < tvi_count) lo + 1 else tvi_count - 1;
    const frac = pos - @as(f32, @floatFromInt(lo));
    return tvi[lo] * (1.0 - frac) + tvi[hi] * frac;
}
