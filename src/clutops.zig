// clutops.zig - CLUT extraction and manipulation
//
// Operations on parsed CLUTs: extract sub-tables by fixing input
// dimensions, compute gradients, blend tables, measure total variation.

const types = @import("types.zig");

fn flatIdx(cl: *const types.Clut, nodes: []const u32) u32 {
    var idx: u32 = 0;
    var stride: u32 = 1;
    var d: u8 = 0;
    while (d < cl.in_ch) : (d += 1) {
        idx += nodes[d] * stride;
        stride *= cl.grid[d];
    }
    return idx;
}

fn flatToNodes(cl: *const types.Clut, flat: u32, nodes: []u32) void {
    var rem = flat;
    var d: u8 = 0;
    while (d < cl.in_ch) : (d += 1) {
        nodes[d] = rem % cl.grid[d];
        rem /= cl.grid[d];
    }
}

// Extract a 1D slice by fixing two dimensions of a 3D CLUT
pub fn extract1D(cl: *const types.Clut, vary_dim: u8, fixed_vals: [2]u32, output: []f32) bool {
    if (cl.in_ch != 3 or vary_dim >= 3) return false;
    if (cl.table == null) return false;

    var nodes: [3]u32 = undefined;
    var fix_idx: u8 = 0;
    for (0..3) |d| {
        if (@as(u8, @intCast(d)) == vary_dim) continue;
        nodes[d] = if (fixed_vals[fix_idx] >= cl.grid[d]) cl.grid[d] - 1 else fixed_vals[fix_idx];
        fix_idx += 1;
    }

    var gi: u32 = 0;
    while (gi < cl.grid[vary_dim]) : (gi += 1) {
        nodes[vary_dim] = gi;
        const fi = flatIdx(cl, &nodes);
        var d: u8 = 0;
        while (d < cl.out_ch) : (d += 1) {
            output[@as(usize, gi) * cl.out_ch + d] = cl.table.?[@as(usize, fi) * cl.out_ch + d];
        }
    }
    return true;
}

// Project a CLUT's output to a single channel
pub fn project(cl: *const types.Clut, channel: u8, output: []f32) bool {
    if (channel >= cl.out_ch or cl.table == null) return false;
    var i: u32 = 0;
    while (i < cl.point_count) : (i += 1) {
        output[i] = cl.table.?[@as(usize, i) * cl.out_ch + channel];
    }
    return true;
}

// Compute element-wise difference between two CLUTs
pub fn diff(a: *const types.Clut, b: *const types.Clut, output: []f32) bool {
    if (a.in_ch != b.in_ch or a.out_ch != b.out_ch) return false;
    if (a.point_count != b.point_count) return false;
    if (a.table == null or b.table == null) return false;
    const total = @as(usize, a.point_count) * a.out_ch;
    var i: usize = 0;
    while (i < total) : (i += 1) {
        output[i] = a.table.?[i] - b.table.?[i];
    }
    return true;
}

// Maximum absolute difference between two CLUTs
pub fn maxDiff(a: *const types.Clut, b: *const types.Clut) f32 {
    if (a.in_ch != b.in_ch or a.out_ch != b.out_ch or a.point_count != b.point_count) return 999;
    if (a.table == null or b.table == null) return 999;
    var mx: f32 = 0;
    const total = @as(usize, a.point_count) * a.out_ch;
    var i: usize = 0;
    while (i < total) : (i += 1) {
        var d = a.table.?[i] - b.table.?[i];
        if (d < 0) d = -d;
        if (d > mx) mx = d;
    }
    return mx;
}

// Blend two CLUTs: out = a * (1-t) + b * t
pub fn blend(a: *const types.Clut, b: *const types.Clut, t: f32, output: []f32) bool {
    if (a.in_ch != b.in_ch or a.out_ch != b.out_ch or a.point_count != b.point_count) return false;
    if (a.table == null or b.table == null) return false;
    const total = @as(usize, a.point_count) * a.out_ch;
    var i: usize = 0;
    while (i < total) : (i += 1) {
        output[i] = a.table.?[i] * (1.0 - t) + b.table.?[i] * t;
    }
    return true;
}

// Compute per-channel range
pub fn channelRange(cl: *const types.Clut, mins: []f32, maxs: []f32) void {
    if (cl.table == null) return;
    var d: u8 = 0;
    while (d < cl.out_ch) : (d += 1) {
        mins[d] = 1;
        maxs[d] = 0;
    }
    var i: u32 = 0;
    while (i < cl.point_count) : (i += 1) {
        d = 0;
        while (d < cl.out_ch) : (d += 1) {
            const v = cl.table.?[@as(usize, i) * cl.out_ch + d];
            if (v < mins[d]) mins[d] = v;
            if (v > maxs[d]) maxs[d] = v;
        }
    }
}

// Compute per-channel mean
pub fn channelMean(cl: *const types.Clut, means: []f32) void {
    if (cl.table == null or cl.point_count == 0) return;
    var d: u8 = 0;
    while (d < cl.out_ch) : (d += 1) {
        means[d] = 0;
    }
    var i: u32 = 0;
    while (i < cl.point_count) : (i += 1) {
        d = 0;
        while (d < cl.out_ch) : (d += 1) {
            means[d] += cl.table.?[@as(usize, i) * cl.out_ch + d];
        }
    }
    d = 0;
    while (d < cl.out_ch) : (d += 1) {
        means[d] /= @as(f32, @floatFromInt(cl.point_count));
    }
}

// Scale all values uniformly
pub fn scale(table: []f32, factor: f32) void {
    for (table) |*v| v.* *= factor;
}

// Clamp all values to [0, 1]
pub fn clampTable(table: []f32) void {
    for (table) |*v| {
        if (v.* < 0) v.* = 0;
        if (v.* > 1) v.* = 1;
    }
}

// Apply per-channel gain
pub fn applyGain(table: []f32, point_count: u32, out_ch: u8, gains: []const f32) void {
    var i: u32 = 0;
    while (i < point_count) : (i += 1) {
        var d: u8 = 0;
        while (d < out_ch) : (d += 1) {
            table[@as(usize, i) * out_ch + d] *= gains[d];
        }
    }
}

// Count out-of-range nodes
pub fn outOfRange(cl: *const types.Clut) u32 {
    if (cl.table == null) return 0;
    var count: u32 = 0;
    var i: u32 = 0;
    while (i < cl.point_count) : (i += 1) {
        var d: u8 = 0;
        while (d < cl.out_ch) : (d += 1) {
            const v = cl.table.?[@as(usize, i) * cl.out_ch + d];
            if (v < 0 or v > 1) {
                count += 1;
                break;
            }
        }
    }
    return count;
}

// Total variation along all dimensions
pub fn totalVariation(cl: *const types.Clut, channel: u8) f32 {
    if (cl.table == null or channel >= cl.out_ch) return 0;
    var tv: f32 = 0;
    var strides: [types.MAX_CHANNELS]u32 = [_]u32{0} ** types.MAX_CHANNELS;
    strides[0] = 1;
    var d: u8 = 1;
    while (d < cl.in_ch) : (d += 1) {
        strides[d] = strides[d - 1] * cl.grid[d - 1];
    }

    var i: u32 = 0;
    while (i < cl.point_count) : (i += 1) {
        var nodes: [types.MAX_CHANNELS]u32 = [_]u32{0} ** types.MAX_CHANNELS;
        flatToNodes(cl, i, &nodes);
        d = 0;
        while (d < cl.in_ch) : (d += 1) {
            if (nodes[d] + 1 < cl.grid[d]) {
                const next = i + strides[d];
                var dd = cl.table.?[@as(usize, next) * cl.out_ch + channel] -
                    cl.table.?[@as(usize, i) * cl.out_ch + channel];
                if (dd < 0) dd = -dd;
                tv += dd;
            }
        }
    }
    return tv;
}

// Check if a CLUT is approximately identity
pub fn isIdentity(cl: *const types.Clut, eps: f32) bool {
    if (cl.in_ch != cl.out_ch or cl.table == null) return false;
    var strides: [types.MAX_CHANNELS]u32 = [_]u32{0} ** types.MAX_CHANNELS;
    strides[0] = 1;
    var d: u8 = 1;
    while (d < cl.in_ch) : (d += 1) {
        strides[d] = strides[d - 1] * cl.grid[d - 1];
    }
    var i: u32 = 0;
    while (i < cl.point_count) : (i += 1) {
        var nodes: [types.MAX_CHANNELS]u32 = [_]u32{0} ** types.MAX_CHANNELS;
        flatToNodes(cl, i, &nodes);
        d = 0;
        while (d < cl.in_ch) : (d += 1) {
            const expected = if (cl.grid[d] > 1)
                @as(f32, @floatFromInt(nodes[d])) / @as(f32, @floatFromInt(cl.grid[d] - 1))
            else
                0;
            const actual = cl.table.?[@as(usize, i) * cl.out_ch + d];
            var dd = actual - expected;
            if (dd < 0) dd = -dd;
            if (dd > eps) return false;
        }
    }
    return true;
}
