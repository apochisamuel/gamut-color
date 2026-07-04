// gradient.zig - gradient computation for CLUT quality analysis
//
// Compute spatial gradients of CLUT data to detect discontinuities,
// banding artifacts, and non-smooth transitions. Used for evaluating
// profile quality and detecting interpolation artifacts.

const types = @import("types.zig");

fn approxSqrt(x: f32) f32 {
    if (x <= 0) return 0;
    var y = x;
    var k: u32 = 0;
    while (k < 8) : (k += 1) y = (y + x / y) * 0.5;
    return y;
}

pub const GradientStats = struct {
    mean_magnitude: f32 = 0,
    max_magnitude: f32 = 0,
    min_magnitude: f32 = 1e30,
    std_dev: f32 = 0,
    discontinuity_count: u32 = 0,
    smoothness_score: f32 = 1.0,
};

// Compute forward difference gradient along one dimension
pub fn gradient1D(data: []const f32, out: []f32, count: usize, stride: usize) void {
    if (count < 2) return;
    var i: usize = 0;
    while (i + 1 < count) : (i += 1) {
        out[i] = data[(i + 1) * stride] - data[i * stride];
    }
    out[count - 1] = out[count - 2]; // extend last value
}

// Compute central difference gradient
pub fn centralDiff(data: []const f32, out: []f32, count: usize, stride: usize) void {
    if (count < 3) {
        gradient1D(data, out, count, stride);
        return;
    }
    out[0] = data[stride] - data[0];
    var i: usize = 1;
    while (i + 1 < count) : (i += 1) {
        out[i] = (data[(i + 1) * stride] - data[(i - 1) * stride]) * 0.5;
    }
    out[count - 1] = data[(count - 1) * stride] - data[(count - 2) * stride];
}

// Second derivative (Laplacian along one dimension)
pub fn secondDerivative(data: []const f32, out: []f32, count: usize, stride: usize) void {
    if (count < 3) {
        @memset(out[0..count], 0);
        return;
    }
    out[0] = 0;
    var i: usize = 1;
    while (i + 1 < count) : (i += 1) {
        out[i] = data[(i + 1) * stride] - 2.0 * data[i * stride] + data[(i - 1) * stride];
    }
    out[count - 1] = 0;
}

// Gradient magnitude for 3D data (partial derivatives in each dimension)
pub fn gradientMagnitude3D(data: []const f32, grid: [3]u32, channel: u8, out_ch: u8) GradientStats {
    var stats = GradientStats{};
    var sum: f32 = 0;
    var sum2: f32 = 0;
    var count: u32 = 0;

    const stride_x: u32 = out_ch;
    const stride_y: u32 = grid[0] * out_ch;
    const stride_z: u32 = grid[0] * grid[1] * out_ch;

    var z: u32 = 0;
    while (z < grid[2]) : (z += 1) {
        var y: u32 = 0;
        while (y < grid[1]) : (y += 1) {
            var x: u32 = 0;
            while (x < grid[0]) : (x += 1) {
                const idx = (z * grid[1] * grid[0] + y * grid[0] + x) * out_ch + channel;
                var gx: f32 = 0;
                var gy: f32 = 0;
                var gz: f32 = 0;

                if (x + 1 < grid[0]) gx = data[idx + stride_x] - data[idx];
                if (y + 1 < grid[1]) gy = data[idx + stride_y] - data[idx];
                if (z + 1 < grid[2]) gz = data[idx + stride_z] - data[idx];

                const mag = approxSqrt(gx * gx + gy * gy + gz * gz);
                sum += mag;
                sum2 += mag * mag;
                if (mag > stats.max_magnitude) stats.max_magnitude = mag;
                if (mag < stats.min_magnitude) stats.min_magnitude = mag;

                // Detect discontinuities (gradient jumps)
                if (x > 0 and x + 1 < grid[0]) {
                    const prev_gx = data[idx] - data[idx - stride_x];
                    var jump = gx - prev_gx;
                    if (jump < 0) jump = -jump;
                    if (jump > 0.1) stats.discontinuity_count += 1;
                }

                count += 1;
            }
        }
    }

    if (count > 0) {
        stats.mean_magnitude = sum / @as(f32, @floatFromInt(count));
        const mean2 = stats.mean_magnitude * stats.mean_magnitude;
        const variance = sum2 / @as(f32, @floatFromInt(count)) - mean2;
        stats.std_dev = if (variance > 0) approxSqrt(variance) else 0;
    }

    if (stats.discontinuity_count == 0) {
        stats.smoothness_score = 1.0;
    } else {
        stats.smoothness_score = 1.0 - @as(f32, @floatFromInt(stats.discontinuity_count)) / @as(f32, @floatFromInt(count));
        if (stats.smoothness_score < 0) stats.smoothness_score = 0;
    }

    return stats;
}

// Smooth data with a 1D box filter
pub fn boxFilter1D(data: []f32, count: usize, radius: u32) void {
    if (count < 3 or radius == 0) return;
    var tmp: [1024]f32 = undefined;
    if (count > 1024) return;

    @memcpy(tmp[0..count], data[0..count]);

    var i: usize = 0;
    while (i < count) : (i += 1) {
        var sum: f32 = 0;
        var n: u32 = 0;
        const lo = if (i >= radius) i - radius else 0;
        const hi = if (i + radius < count) i + radius else count - 1;
        var j: usize = lo;
        while (j <= hi) : (j += 1) {
            sum += tmp[j];
            n += 1;
        }
        if (n > 0) data[i] = sum / @as(f32, @floatFromInt(n));
    }
}

// Gaussian-weighted smooth (1D, sigma=radius/3)
pub fn gaussianSmooth1D(data: []f32, count: usize, radius: u32) void {
    if (count < 3 or radius == 0) return;
    var tmp: [1024]f32 = undefined;
    if (count > 1024) return;

    @memcpy(tmp[0..count], data[0..count]);
    const sigma = @as(f32, @floatFromInt(radius)) / 3.0;
    const s2 = 2.0 * sigma * sigma;

    var i: usize = 0;
    while (i < count) : (i += 1) {
        var sum: f32 = 0;
        var wsum: f32 = 0;
        const lo = if (i >= radius) i - radius else 0;
        const hi = if (i + radius < count) i + radius else count - 1;
        var j: usize = lo;
        while (j <= hi) : (j += 1) {
            const d = @as(f32, @floatFromInt(j)) - @as(f32, @floatFromInt(i));
            var w: f32 = 1.0;
            // Approximate exp(-d²/2σ²)
            const exponent = -(d * d) / s2;
            var term: f32 = 1.0;
            var exp_sum: f32 = 1.0;
            var k: u32 = 1;
            while (k <= 8) : (k += 1) {
                term *= exponent / @as(f32, @floatFromInt(k));
                exp_sum += term;
            }
            w = exp_sum;
            sum += tmp[j] * w;
            wsum += w;
        }
        if (wsum > 0) data[i] = sum / wsum;
    }
}

// Compute total variation of a 1D signal
pub fn totalVariation1D(data: []const f32, count: usize) f32 {
    if (count < 2) return 0;
    var tv: f32 = 0;
    var i: usize = 1;
    while (i < count) : (i += 1) {
        var d = data[i] - data[i - 1];
        if (d < 0) d = -d;
        tv += d;
    }
    return tv;
}

// Detect monotonicity violations
pub fn monotonicityViolations(data: []const f32, count: usize) u32 {
    if (count < 2) return 0;
    var violations: u32 = 0;
    var i: usize = 1;
    while (i < count) : (i += 1) {
        if (data[i] < data[i - 1] - 1e-6) violations += 1;
    }
    return violations;
}

// Compute peak-to-valley ratio (dynamic range indicator)
pub fn peakToValley(data: []const f32, count: usize) f32 {
    if (count == 0) return 0;
    var mn = data[0];
    var mx = data[0];
    for (data[0..count]) |v| {
        if (v < mn) mn = v;
        if (v > mx) mx = v;
    }
    if (mn <= 0) return 0;
    return mx / mn;
}
