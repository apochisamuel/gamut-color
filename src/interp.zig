// interp.zig - multi-dimensional interpolation for CLUTs
//
// Advanced interpolation methods beyond the nearest-node sampling in
// mpet.zig. Tetrahedral interpolation (for 3D CLUTs) is the method
// used by high-quality color management modules.

const types = @import("types.zig");

// Compute flat index into CLUT table
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

// Read one output sample from the table
fn tbl(cl: *const types.Clut, nodes: []const u32, och: u8) f32 {
    const fi = flatIdx(cl, nodes);
    if (cl.table) |t| {
        return t[@as(usize, fi) * cl.out_ch + och];
    }
    return 0;
}

// Tetrahedral interpolation for 3D CLUTs
pub fn tetrahedral(cl: *const types.Clut, input: [3]f32, output: []f32) void {
    if (cl.in_ch != 3) {
        for (output[0..cl.out_ch]) |*o| o.* = 0;
        return;
    }

    var fx: [3]f32 = undefined;
    var lo: [3]u32 = undefined;
    var hi: [3]u32 = undefined;

    for (0..3) |d| {
        var x = input[d];
        if (x < 0) x = 0;
        if (x > 1) x = 1;
        const g = cl.grid[d];
        const pos = x * @as(f32, @floatFromInt(g - 1));
        lo[d] = @intFromFloat(pos);
        if (lo[d] >= g - 1) lo[d] = g - 2;
        hi[d] = lo[d] + 1;
        if (hi[d] >= g) hi[d] = g - 1;
        fx[d] = pos - @as(f32, @floatFromInt(lo[d]));
    }

    var oc: u8 = 0;
    while (oc < cl.out_ch) : (oc += 1) {
        const n0 = [3]u32{ lo[0], lo[1], lo[2] };
        const n3 = [3]u32{ hi[0], hi[1], hi[2] };
        const c0 = tbl(cl, &n0, oc);
        const c3 = tbl(cl, &n3, oc);

        var c1: f32 = undefined;
        var c2: f32 = undefined;
        var w0: f32 = undefined;
        var w1: f32 = undefined;
        var w2: f32 = undefined;
        var w3: f32 = undefined;

        if (fx[0] >= fx[1]) {
            if (fx[1] >= fx[2]) {
                // Tetrahedron 1: r >= g >= b
                const n1 = [3]u32{ hi[0], lo[1], lo[2] };
                const n2 = [3]u32{ hi[0], hi[1], lo[2] };
                c1 = tbl(cl, &n1, oc);
                c2 = tbl(cl, &n2, oc);
                w0 = 1.0 - fx[0];
                w1 = fx[0] - fx[1];
                w2 = fx[1] - fx[2];
                w3 = fx[2];
            } else if (fx[0] >= fx[2]) {
                // Tetrahedron 2: r >= b >= g
                const n1 = [3]u32{ hi[0], lo[1], lo[2] };
                const n2 = [3]u32{ hi[0], lo[1], hi[2] };
                c1 = tbl(cl, &n1, oc);
                c2 = tbl(cl, &n2, oc);
                w0 = 1.0 - fx[0];
                w1 = fx[0] - fx[2];
                w2 = fx[2] - fx[1];
                w3 = fx[1];
            } else {
                // Tetrahedron 3: b >= r >= g
                const n1 = [3]u32{ lo[0], lo[1], hi[2] };
                const n2 = [3]u32{ hi[0], lo[1], hi[2] };
                c1 = tbl(cl, &n1, oc);
                c2 = tbl(cl, &n2, oc);
                w0 = 1.0 - fx[2];
                w1 = fx[2] - fx[0];
                w2 = fx[0] - fx[1];
                w3 = fx[1];
            }
        } else {
            if (fx[0] >= fx[2]) {
                // Tetrahedron 4: g >= r >= b
                const n1 = [3]u32{ lo[0], hi[1], lo[2] };
                const n2 = [3]u32{ hi[0], hi[1], lo[2] };
                c1 = tbl(cl, &n1, oc);
                c2 = tbl(cl, &n2, oc);
                w0 = 1.0 - fx[1];
                w1 = fx[1] - fx[0];
                w2 = fx[0] - fx[2];
                w3 = fx[2];
            } else if (fx[1] >= fx[2]) {
                // Tetrahedron 5: g >= b >= r
                const n1 = [3]u32{ lo[0], hi[1], lo[2] };
                const n2 = [3]u32{ lo[0], hi[1], hi[2] };
                c1 = tbl(cl, &n1, oc);
                c2 = tbl(cl, &n2, oc);
                w0 = 1.0 - fx[1];
                w1 = fx[1] - fx[2];
                w2 = fx[2] - fx[0];
                w3 = fx[0];
            } else {
                // Tetrahedron 6: b >= g >= r
                const n1 = [3]u32{ lo[0], lo[1], hi[2] };
                const n2 = [3]u32{ lo[0], hi[1], hi[2] };
                c1 = tbl(cl, &n1, oc);
                c2 = tbl(cl, &n2, oc);
                w0 = 1.0 - fx[2];
                w1 = fx[2] - fx[1];
                w2 = fx[1] - fx[0];
                w3 = fx[0];
            }
        }
        output[oc] = w0 * c0 + w1 * c1 + w2 * c2 + w3 * c3;
    }
}

// Bilinear interpolation for 2D CLUTs
pub fn bilinear(cl: *const types.Clut, input: [2]f32, output: []f32) void {
    if (cl.in_ch != 2) {
        for (output[0..cl.out_ch]) |*o| o.* = 0;
        return;
    }

    var px: [2]f32 = undefined;
    var lx: [2]u32 = undefined;
    var hx: [2]u32 = undefined;
    var fx: [2]f32 = undefined;

    for (0..2) |d| {
        var v = input[d];
        if (v < 0) v = 0;
        if (v > 1) v = 1;
        px[d] = v * @as(f32, @floatFromInt(cl.grid[d] - 1));
        lx[d] = @intFromFloat(px[d]);
        if (lx[d] >= cl.grid[d] - 1) lx[d] = cl.grid[d] - 2;
        hx[d] = lx[d] + 1;
        fx[d] = px[d] - @as(f32, @floatFromInt(lx[d]));
    }

    var oc: u8 = 0;
    while (oc < cl.out_ch) : (oc += 1) {
        const n00 = [2]u32{ lx[0], lx[1] };
        const n10 = [2]u32{ hx[0], lx[1] };
        const n01 = [2]u32{ lx[0], hx[1] };
        const n11 = [2]u32{ hx[0], hx[1] };
        const c00 = tbl(cl, &n00, oc);
        const c10 = tbl(cl, &n10, oc);
        const c01 = tbl(cl, &n01, oc);
        const c11 = tbl(cl, &n11, oc);
        const c0 = c00 * (1.0 - fx[0]) + c10 * fx[0];
        const c1 = c01 * (1.0 - fx[0]) + c11 * fx[0];
        output[oc] = c0 * (1.0 - fx[1]) + c1 * fx[1];
    }
}

// Nearest-node sampling (general N-dimensional)
pub fn nearest(cl: *const types.Clut, input: []const f32, output: []f32) void {
    var nodes: [types.MAX_CHANNELS]u32 = [_]u32{0} ** types.MAX_CHANNELS;
    var d: u8 = 0;
    while (d < cl.in_ch and d < types.MAX_CHANNELS) : (d += 1) {
        var x = input[d];
        if (x < 0) x = 0;
        if (x > 1) x = 1;
        var n: u32 = @intFromFloat(x * @as(f32, @floatFromInt(cl.grid[d] - 1)) + 0.5);
        if (n >= cl.grid[d]) n = cl.grid[d] - 1;
        nodes[d] = n;
    }
    const fi = flatIdx(cl, &nodes);
    d = 0;
    while (d < cl.out_ch) : (d += 1) {
        if (cl.table) |t| {
            output[d] = t[@as(usize, fi) * cl.out_ch + d];
        }
    }
}

// Dispatch by dimensionality
pub fn interp(cl: *const types.Clut, input: []const f32, output: []f32) void {
    switch (cl.in_ch) {
        2 => bilinear(cl, .{ input[0], input[1] }, output),
        3 => tetrahedral(cl, .{ input[0], input[1], input[2] }, output),
        else => nearest(cl, input, output),
    }
}

// Batch interpolation
pub fn interpBatch(cl: *const types.Clut, inputs: []const f32, outputs: []f32, count: usize) void {
    var i: usize = 0;
    while (i < count) : (i += 1) {
        interp(cl, inputs[i * cl.in_ch ..], outputs[i * cl.out_ch ..]);
    }
}
