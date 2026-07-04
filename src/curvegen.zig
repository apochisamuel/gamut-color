// curvegen.zig - curve generation and analysis
//
// Generate standard tone-reproduction curves and compute curve quality
// metrics. Used for testing and profile construction.

const types = @import("types.zig");

fn approxPow(x: f32, g: f32) f32 {
    if (x <= 0) return 0;
    if (x >= 1) return 1;
    const u = 1.0 - x;
    const ln_x = -(u + u * u * 0.5 + u * u * u / 3.0 + u * u * u * u * 0.25);
    const t = g * ln_x;
    var sum: f32 = 1.0;
    var term: f32 = 1.0;
    var k: u32 = 1;
    while (k <= 12) : (k += 1) {
        term *= t / @as(f32, @floatFromInt(k));
        sum += term;
    }
    if (sum < 0) return 0;
    if (sum > 1) return 1;
    return sum;
}

fn approxSqrt(x: f32) f32 {
    if (x <= 0) return 0;
    var y = x;
    var k: u32 = 0;
    while (k < 10) : (k += 1) {
        y = (y + x / y) * 0.5;
    }
    return y;
}

// Generate a linear identity curve
pub fn identity(samples: []f32) void {
    const n = samples.len;
    if (n < 2) return;
    for (samples, 0..) |*s, i| {
        s.* = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(n - 1));
    }
}

// Generate a power-law gamma curve
pub fn gamma(samples: []f32, g: f32) void {
    const n = samples.len;
    if (n < 2) return;
    for (samples, 0..) |*s, i| {
        const x = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(n - 1));
        s.* = approxPow(x, g);
    }
}

// Generate the sRGB forward transfer function
pub fn srgb(samples: []f32) void {
    const n = samples.len;
    if (n < 2) return;
    for (samples, 0..) |*s, i| {
        const x = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(n - 1));
        if (x <= 0.0031308) {
            s.* = 12.92 * x;
        } else {
            s.* = 1.055 * approxPow(x, 1.0 / 2.4) - 0.055;
        }
        if (s.* < 0) s.* = 0;
        if (s.* > 1) s.* = 1;
    }
}

// Generate the inverse sRGB transfer function
pub fn srgbInverse(samples: []f32) void {
    const n = samples.len;
    if (n < 2) return;
    for (samples, 0..) |*s, i| {
        const x = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(n - 1));
        if (x <= 0.04045) {
            s.* = x / 12.92;
        } else {
            s.* = approxPow((x + 0.055) / 1.055, 2.4);
        }
        if (s.* < 0) s.* = 0;
        if (s.* > 1) s.* = 1;
    }
}

// Generate the L* curve (CIE lightness)
pub fn lstar(samples: []f32) void {
    const n = samples.len;
    if (n < 2) return;
    for (samples, 0..) |*s, i| {
        const y = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(n - 1));
        const fy = if (y > 0.008856) approxPow(y, 1.0 / 3.0) else 7.787 * y + 16.0 / 116.0;
        s.* = (116.0 * fy - 16.0) / 100.0;
        if (s.* < 0) s.* = 0;
        if (s.* > 1) s.* = 1;
    }
}

// Invert a monotonically increasing curve using binary search
pub fn invertTable(fwd: []const f32, inv: []f32) void {
    const fwd_n = fwd.len;
    const inv_n = inv.len;
    if (fwd_n < 2 or inv_n < 2) return;
    for (inv, 0..) |*s, oi| {
        const y = @as(f32, @floatFromInt(oi)) / @as(f32, @floatFromInt(inv_n - 1));
        var lo: usize = 0;
        var hi: usize = fwd_n - 1;
        while (hi - lo > 1) {
            const mid = (lo + hi) / 2;
            if (fwd[mid] < y) lo = mid else hi = mid;
        }
        if (fwd[hi] != fwd[lo]) {
            const t = (y - fwd[lo]) / (fwd[hi] - fwd[lo]);
            s.* = (@as(f32, @floatFromInt(lo)) + t) / @as(f32, @floatFromInt(fwd_n - 1));
        } else {
            s.* = @as(f32, @floatFromInt(lo)) / @as(f32, @floatFromInt(fwd_n - 1));
        }
    }
}

// Compose two curves: out[i] = b(a(i/(n-1)))
pub fn compose(a: []const f32, b: []const f32, output: []f32) void {
    const n = output.len;
    if (a.len < 2 or b.len < 2 or n < 2) return;
    for (output, 0..) |*s, i| {
        const x = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(n - 1));
        const ya = evalTable(a, x);
        s.* = evalTable(b, ya);
    }
}

fn evalTable(tbl: []const f32, x: f32) f32 {
    var xc = x;
    if (xc < 0) xc = 0;
    if (xc > 1) xc = 1;
    const pos = xc * @as(f32, @floatFromInt(tbl.len - 1));
    const lo: usize = @intFromFloat(pos);
    const hi = if (lo + 1 < tbl.len) lo + 1 else tbl.len - 1;
    const frac = pos - @as(f32, @floatFromInt(lo));
    return tbl[lo] * (1.0 - frac) + tbl[hi] * frac;
}

// Compute RMS error between two curves
pub fn rmsError(a: []const f32, b: []const f32) f32 {
    if (a.len != b.len or a.len == 0) return 0;
    var sum: f32 = 0;
    for (a, b) |va, vb| {
        const d = va - vb;
        sum += d * d;
    }
    return approxSqrt(sum / @as(f32, @floatFromInt(a.len)));
}

// Compute maximum absolute error
pub fn maxError(a: []const f32, b: []const f32) f32 {
    if (a.len != b.len) return 0;
    var mx: f32 = 0;
    for (a, b) |va, vb| {
        var d = va - vb;
        if (d < 0) d = -d;
        if (d > mx) mx = d;
    }
    return mx;
}

// Measure smoothness as mean absolute second derivative
pub fn smoothness(samples: []const f32) f32 {
    if (samples.len < 3) return 0;
    var sum: f32 = 0;
    var i: usize = 1;
    while (i + 1 < samples.len) : (i += 1) {
        var d2 = samples[i - 1] - 2.0 * samples[i] + samples[i + 1];
        if (d2 < 0) d2 = -d2;
        sum += d2;
    }
    return sum / @as(f32, @floatFromInt(samples.len - 2));
}

// Check if a curve is monotonically increasing
pub fn isMonotonic(samples: []const f32) bool {
    if (samples.len < 2) return true;
    var i: usize = 1;
    while (i < samples.len) : (i += 1) {
        if (samples[i] < samples[i - 1] - 1e-6) return false;
    }
    return true;
}

// Compute the nonlinearity: integral of |curve - identity|
pub fn nonlinearity(samples: []const f32) f32 {
    if (samples.len < 2) return 0;
    var sum: f32 = 0;
    for (samples, 0..) |s, i| {
        const x = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(samples.len - 1));
        var d = s - x;
        if (d < 0) d = -d;
        sum += d;
    }
    return sum / @as(f32, @floatFromInt(samples.len));
}

// Fit a gamma exponent by grid search
pub fn fitGamma(samples: []const f32) f32 {
    if (samples.len < 4) return 1;
    var best_g: f32 = 1;
    var best_err: f32 = 1e30;
    var gi: u32 = 10;
    while (gi <= 500) : (gi += 1) {
        const g = @as(f32, @floatFromInt(gi)) * 0.01;
        var err: f32 = 0;
        for (samples, 0..) |s, i| {
            const x = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(samples.len - 1));
            const expected = approxPow(x, g);
            const d = s - expected;
            err += d * d;
        }
        if (err < best_err) {
            best_err = err;
            best_g = g;
        }
    }
    return best_g;
}

// Resample a curve to a different number of points
pub fn resample(src: []const f32, dst: []f32) void {
    if (src.len < 2 or dst.len < 2) return;
    for (dst, 0..) |*d, i| {
        const x = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(dst.len - 1));
        d.* = evalTable(src, x);
    }
}

// Generate a posterization curve with N levels
pub fn posterize(samples: []f32, levels: u32) void {
    if (samples.len < 2 or levels < 2) {
        identity(samples);
        return;
    }
    const step = 1.0 / @as(f32, @floatFromInt(levels - 1));
    for (samples, 0..) |*s, i| {
        const x = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(samples.len - 1));
        const bin: u32 = @intFromFloat(x * @as(f32, @floatFromInt(levels - 1)) + 0.5);
        s.* = @as(f32, @floatFromInt(bin)) * step;
    }
}
