// gamutvolume.zig - gamut volume computation
//
// Estimate the volume of a color gamut in Lab space using Monte Carlo
// integration and convex hull approximation. Compare gamut volumes
// between profiles to evaluate relative gamut sizes.

const types = @import("types.zig");

fn approxSqrt(x: f32) f32 {
    if (x <= 0) return 0;
    var y = x;
    var k: u32 = 0;
    while (k < 8) : (k += 1) y = (y + x / y) * 0.5;
    return y;
}

pub const VolumeResult = struct {
    volume: f32 = 0,
    surface_area: f32 = 0,
    max_chroma: f32 = 0,
    min_lightness: f32 = 100,
    max_lightness: f32 = 0,
    centroid: [3]f32 = .{ 0, 0, 0 },
    samples_inside: u32 = 0,
    samples_total: u32 = 0,
};

// Monte Carlo volume estimation
pub fn monteCarloVolume(boundary_points: []const f32, num_points: usize, num_samples: u32) VolumeResult {
    var result = VolumeResult{};
    if (num_points < 4) return result;

    // Find bounding box
    var min_l: f32 = 100;
    var max_l: f32 = 0;
    var min_a: f32 = 128;
    var max_a: f32 = -128;
    var min_b: f32 = 128;
    var max_b: f32 = -128;

    var i: usize = 0;
    while (i < num_points) : (i += 1) {
        const l = boundary_points[i * 3];
        const a = boundary_points[i * 3 + 1];
        const b = boundary_points[i * 3 + 2];
        if (l < min_l) min_l = l;
        if (l > max_l) max_l = l;
        if (a < min_a) min_a = a;
        if (a > max_a) max_a = a;
        if (b < min_b) min_b = b;
        if (b > max_b) max_b = b;
        // Update stats
        const c = approxSqrt(a * a + b * b);
        if (c > result.max_chroma) result.max_chroma = c;
        result.centroid[0] += l;
        result.centroid[1] += a;
        result.centroid[2] += b;
    }
    result.min_lightness = min_l;
    result.max_lightness = max_l;
    if (num_points > 0) {
        const np = @as(f32, @floatFromInt(num_points));
        result.centroid[0] /= np;
        result.centroid[1] /= np;
        result.centroid[2] /= np;
    }

    // Monte Carlo sampling
    const bbox_vol = (max_l - min_l) * (max_a - min_a) * (max_b - min_b);
    result.samples_total = num_samples;

    var inside: u32 = 0;
    var si: u32 = 0;
    while (si < num_samples) : (si += 1) {
        // Pseudo-random point in bounding box
        const hash1 = si *% 2654435761;
        const hash2 = si *% 2246822519;
        const hash3 = si *% 3266489917;
        const l = min_l + @as(f32, @floatFromInt(hash1 & 0xFFFF)) / 65535.0 * (max_l - min_l);
        const a = min_a + @as(f32, @floatFromInt(hash2 & 0xFFFF)) / 65535.0 * (max_a - min_a);
        const b = min_b + @as(f32, @floatFromInt(hash3 & 0xFFFF)) / 65535.0 * (max_b - min_b);

        if (isInsideGamut(boundary_points, num_points, l, a, b)) {
            inside += 1;
        }
    }

    result.samples_inside = inside;
    if (num_samples > 0) {
        result.volume = bbox_vol * @as(f32, @floatFromInt(inside)) / @as(f32, @floatFromInt(num_samples));
    }

    // Estimate surface area from boundary points
    result.surface_area = estimateSurface(boundary_points, num_points);

    return result;
}

// Check if a point is inside the gamut (approximate: nearest-neighbor distance)
fn isInsideGamut(boundary: []const f32, num_boundary: usize, l: f32, a: f32, b: f32) bool {
    // Find closest boundary point
    var min_dist: f32 = 1e30;
    var closest_c: f32 = 0;
    var query_c = approxSqrt(a * a + b * b);

    var i: usize = 0;
    while (i < num_boundary) : (i += 1) {
        const bl = boundary[i * 3];
        const ba = boundary[i * 3 + 1];
        const bb = boundary[i * 3 + 2];
        const dl = l - bl;
        const da = a - ba;
        const db = b - bb;
        const d = dl * dl + da * da + db * db;
        if (d < min_dist) {
            min_dist = d;
            closest_c = approxSqrt(ba * ba + bb * bb);
        }
    }

    // Point is inside if its chroma is less than closest boundary chroma
    return query_c <= closest_c * 1.1;
}

// Estimate surface area using average distance between neighboring boundary points
fn estimateSurface(boundary: []const f32, num_points: usize) f32 {
    if (num_points < 3) return 0;
    var total_dist: f32 = 0;
    var pairs: u32 = 0;

    var i: usize = 0;
    while (i < num_points) : (i += 1) {
        // Find two nearest neighbors
        var d1: f32 = 1e30;
        var d2: f32 = 1e30;
        var j: usize = 0;
        while (j < num_points) : (j += 1) {
            if (j == i) continue;
            const dl = boundary[i * 3] - boundary[j * 3];
            const da = boundary[i * 3 + 1] - boundary[j * 3 + 1];
            const db = boundary[i * 3 + 2] - boundary[j * 3 + 2];
            const d = approxSqrt(dl * dl + da * da + db * db);
            if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
        }
        // Triangle area ≈ d1 × d2 / 2
        total_dist += d1 * d2 * 0.5;
        pairs += 1;
    }

    return total_dist;
}

// Compare two gamut volumes
pub fn compareVolumes(a: VolumeResult, b: VolumeResult) f32 {
    if (b.volume <= 0) return 0;
    return a.volume / b.volume;
}

// Compute gamut coverage percentage
pub fn coveragePercent(measured: VolumeResult, reference: VolumeResult) f32 {
    if (reference.volume <= 0) return 0;
    var ratio = measured.volume / reference.volume * 100.0;
    if (ratio > 200) ratio = 200;
    return ratio;
}
