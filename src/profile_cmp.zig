// profile_cmp.zig - profile comparison utilities
//
// Compare two parsed profiles: transform-level comparison by evaluating
// at grid points, structural comparison (tag sets, element types),
// and metadata comparison.

const types = @import("types.zig");
const resolve = @import("resolve.zig");

pub const CmpResult = struct {
    mean_de: f32 = 0,
    max_de: f32 = 0,
    percentile_95: f32 = 0,
    num_samples: u32 = 0,
    channel_match: bool = true,
    pcs_match: bool = true,
    version_match: bool = true,
    tag_count_match: bool = true,
    tags_a_only: u32 = 0,
    tags_b_only: u32 = 0,
    tags_shared: u32 = 0,
};

fn approxSqrt(x: f32) f32 {
    if (x <= 0) return 0;
    var y = x;
    var k: u32 = 0;
    while (k < 8) : (k += 1) y = (y + x / y) * 0.5;
    return y;
}

// Compare transforms at a grid of points
pub fn compareTransforms(a: *const types.Profile, b: *const types.Profile, grid: u8) CmpResult {
    var result = CmpResult{};

    result.channel_match = (a.channels == b.channels);
    result.pcs_match = (a.pcs == b.pcs);
    result.version_match = (a.version == b.version);
    result.tag_count_match = (a.tag_count == b.tag_count);

    if (!result.channel_match or a.channels < 1 or a.channels > 4) return result;

    const g = if (grid < 3) @as(u8, 5) else grid;
    const step = 1.0 / @as(f32, @floatFromInt(g - 1));

    var errors: [4096]f32 = undefined;
    var error_count: u32 = 0;

    if (a.channels == 3) {
        var ri: u8 = 0;
        while (ri < g) : (ri += 1) {
            var gi: u8 = 0;
            while (gi < g) : (gi += 1) {
                var bi: u8 = 0;
                while (bi < g) : (bi += 1) {
                    var input = [_]f32{0} ** types.MAX_CHANNELS;
                    input[0] = @as(f32, @floatFromInt(ri)) * step;
                    input[1] = @as(f32, @floatFromInt(gi)) * step;
                    input[2] = @as(f32, @floatFromInt(bi)) * step;

                    var out_a = [_]f32{0} ** types.MAX_CHANNELS;
                    var out_b = [_]f32{0} ** types.MAX_CHANNELS;

                    _ = resolve.apply(a, &a.link, &input, &out_a);
                    _ = resolve.apply(b, &b.link, &input, &out_b);

                    var de: f32 = 0;
                    var ch: u8 = 0;
                    while (ch < a.pcs_channels) : (ch += 1) {
                        const d = out_a[ch] - out_b[ch];
                        de += d * d;
                    }
                    de = approxSqrt(de);

                    if (error_count < 4096) {
                        errors[error_count] = de;
                        error_count += 1;
                    }
                    result.mean_de += de;
                    if (de > result.max_de) result.max_de = de;
                }
            }
        }
    }

    result.num_samples = error_count;
    if (error_count > 0) {
        result.mean_de /= @as(f32, @floatFromInt(error_count));
    }

    // Sort for percentile (insertion sort for small arrays)
    if (error_count > 1) {
        var i: u32 = 1;
        while (i < error_count) : (i += 1) {
            const val = errors[i];
            var j: u32 = i;
            while (j > 0 and errors[j - 1] > val) : (j -= 1) {
                errors[j] = errors[j - 1];
            }
            errors[j] = val;
        }
        const p95 = error_count * 95 / 100;
        result.percentile_95 = errors[p95];
    }

    return result;
}

// Compare tag sets
pub fn compareTagSets(a: *const types.Profile, b: *const types.Profile) CmpResult {
    var result = CmpResult{};
    if (a.tags == null or b.tags == null) return result;

    var i: usize = 0;
    while (i < a.tag_count) : (i += 1) {
        var found = false;
        var j: usize = 0;
        while (j < b.tag_count) : (j += 1) {
            if (a.tags.?[i].signature == b.tags.?[j].signature) {
                found = true;
                result.tags_shared += 1;
                break;
            }
        }
        if (!found) result.tags_a_only += 1;
    }

    i = 0;
    while (i < b.tag_count) : (i += 1) {
        var found = false;
        var j: usize = 0;
        while (j < a.tag_count) : (j += 1) {
            if (b.tags.?[i].signature == a.tags.?[j].signature) {
                found = true;
                break;
            }
        }
        if (!found) result.tags_b_only += 1;
    }

    result.tag_count_match = (a.tag_count == b.tag_count);
    return result;
}

// Quick equivalence check (structural only)
pub fn isEquivalent(a: *const types.Profile, b: *const types.Profile) bool {
    if (a.channels != b.channels) return false;
    if (a.pcs != b.pcs) return false;
    if (a.tag_count != b.tag_count) return false;
    return true;
}
