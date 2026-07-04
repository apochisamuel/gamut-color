// stats.zig - profile statistics and quality metrics
//
// Compute summary statistics: element counts, memory usage, sharing
// ratios, and transform quality metrics.

const types = @import("types.zig");
const linkcache = @import("linkcache.zig");
const elements = @import("elements.zig");

pub const ProfileStats = struct {
    total_tags: u32 = 0,
    resolved_tags: u32 = 0,
    shared_tags: u32 = 0,
    curve_tags: u32 = 0,
    clut_tags: u32 = 0,
    matrix_tags: u32 = 0,
    xyz_tags: u32 = 0,
    text_tags: u32 = 0,
    lut_tags: u32 = 0,
    mpet_tags: u32 = 0,

    pool_elements: u32 = 0,
    pool_curves: u32 = 0,
    pool_cluts: u32 = 0,
    pool_matrices: u32 = 0,
    pool_xyzs: u32 = 0,
    pool_texts: u32 = 0,

    link_stages: u32 = 0,
    link_curve_stages: u32 = 0,
    link_clut_stages: u32 = 0,
    link_matrix_stages: u32 = 0,
    link_chad_stages: u32 = 0,

    curve_samples_mem: usize = 0,
    clut_table_mem: usize = 0,

    is_sorted: bool = true,
    has_duplicates: bool = false,
    quality_score: f32 = 1.0,
};

pub fn compute(p: *const types.Profile) ProfileStats {
    var s = ProfileStats{};

    s.total_tags = @intCast(p.tag_count);

    // Per-tag analysis
    if (p.tags) |tags| {
        var i: usize = 0;
        while (i < p.tag_count) : (i += 1) {
            if (tags[i].pool_idx < 0) continue;
            s.resolved_tags += 1;
            if (elements.poolAt(@constCast(&p.pool), tags[i].pool_idx)) |el| {
                switch (el.kind) {
                    .curve => s.curve_tags += 1,
                    .clut => s.clut_tags += 1,
                    .matrix => s.matrix_tags += 1,
                    .xyz => s.xyz_tags += 1,
                    .text => s.text_tags += 1,
                    .lut => s.lut_tags += 1,
                    .mpet => s.mpet_tags += 1,
                    .none => {},
                }
            }
            // Check sharing
            var j: usize = i + 1;
            while (j < p.tag_count) : (j += 1) {
                if (tags[j].offset == tags[i].offset and tags[i].size > 0) {
                    s.shared_tags += 1;
                    break;
                }
            }
        }
    }

    // Pool analysis
    if (p.pool.items) |items| {
        s.pool_elements = @intCast(p.pool.count);
        var i: usize = 0;
        while (i < p.pool.count) : (i += 1) {
            if (items[i]) |el| {
                switch (el.kind) {
                    .curve => {
                        s.pool_curves += 1;
                        if (el.data.curve.samples != null) {
                            s.curve_samples_mem += @as(usize, el.data.curve.count) * 4;
                        }
                    },
                    .clut => {
                        s.pool_cluts += 1;
                        if (el.data.clut.table != null) {
                            s.clut_table_mem += @as(usize, el.data.clut.point_count) * el.data.clut.out_ch * 4;
                        }
                    },
                    .matrix => s.pool_matrices += 1,
                    .xyz => s.pool_xyzs += 1,
                    .text => s.pool_texts += 1,
                    else => {},
                }
            }
        }
    }

    // Link cache analysis
    s.link_stages = @intCast(p.link.count);
    if (p.link.stages) |stages| {
        var i: usize = 0;
        while (i < p.link.count) : (i += 1) {
            switch (stages[i].kind) {
                .curve => s.link_curve_stages += 1,
                .clut => s.link_clut_stages += 1,
                .matrix => s.link_matrix_stages += 1,
                .chad => s.link_chad_stages += 1,
            }
        }
    }

    // Tag directory quality
    if (p.tags) |tags| {
        if (p.tag_count > 1) {
            var i: usize = 1;
            while (i < p.tag_count) : (i += 1) {
                if (tags[i].signature < tags[i - 1].signature) {
                    s.is_sorted = false;
                    break;
                }
            }
        }
        var i: usize = 0;
        while (i < p.tag_count and !s.has_duplicates) : (i += 1) {
            var j: usize = i + 1;
            while (j < p.tag_count) : (j += 1) {
                if (tags[j].signature == tags[i].signature) {
                    s.has_duplicates = true;
                    break;
                }
            }
        }
    }

    // Quality score
    s.quality_score = 1.0;
    if (s.has_duplicates) s.quality_score -= 0.2;
    if (!s.is_sorted) s.quality_score -= 0.1;
    if (s.resolved_tags == 0) s.quality_score -= 0.3;
    if (s.quality_score < 0) s.quality_score = 0;

    return s;
}

// Compute the estimated complexity cost of a transform
pub fn transformComplexity(p: *const types.Profile) f32 {
    var cost: f32 = 0;
    if (p.link.stages) |stages| {
        var i: usize = 0;
        while (i < p.link.count) : (i += 1) {
            cost += switch (stages[i].kind) {
                .curve => 2.0 + @as(f32, @floatFromInt(stages[i].curve_count)) * 0.002,
                .clut => blk: {
                    var pts: u32 = 1;
                    var d: u8 = 0;
                    while (d < stages[i].in_ch) : (d += 1) {
                        pts *= if (stages[i].grid[d] > 0) stages[i].grid[d] else 1;
                    }
                    break :blk 10.0 + @as(f32, @floatFromInt(pts)) * 0.01;
                },
                .matrix => 5.0,
                .chad => 3.0,
            };
        }
    }
    return cost;
}

// Estimated throughput in samples per second
pub fn estimatedThroughput(p: *const types.Profile) f32 {
    const cost = transformComplexity(p);
    if (cost <= 0) return 0;
    return 1e9 / cost;
}

// Count identity stages
pub fn identityStageCount(p: *const types.Profile, eps: f32) u32 {
    var count: u32 = 0;
    if (p.link.stages) |stages| {
        var i: usize = 0;
        while (i < p.link.count) : (i += 1) {
            const s = &stages[i];
            if (s.kind == .curve) {
                if (s.curve_samples == null or s.curve_count == 0) {
                    count += 1;
                    continue;
                }
                var is_ident = true;
                var k: u32 = 0;
                while (k < s.curve_count) : (k += 1) {
                    const expected = @as(f32, @floatFromInt(k)) / @as(f32, @floatFromInt(s.curve_count - 1));
                    var d = s.curve_samples.?[k] - expected;
                    if (d < 0) d = -d;
                    if (d > eps) {
                        is_ident = false;
                        break;
                    }
                }
                if (is_ident) count += 1;
            }
        }
    }
    return count;
}
