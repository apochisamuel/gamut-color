// resolve.zig - transform evaluation
//
// Walks the link cache in application order and runs each stage against
// a working sample vector. The stage evaluation functions read resolved
// pointers cached during assembly.

const types = @import("types.zig");
const curves_mod = @import("curves.zig");
const mpet_mod = @import("mpet.zig");

fn sampleAt(samples: [*]f32, count: u32, x: f32) f32 {
    var xc = x;
    if (xc < 0.0) xc = 0.0;
    if (xc > 1.0) xc = 1.0;
    const pos = xc * @as(f32, @floatFromInt(count - 1));
    const lo: u32 = @intFromFloat(pos);
    const hi = if (lo + 1 < count) lo + 1 else count - 1;
    const frac = pos - @as(f32, @floatFromInt(lo));
    return samples[lo] * (1.0 - frac) + samples[hi] * frac;
}

fn applyCurveStage(s: *const types.LinkStage, v: []f32) void {
    const ch = s.in_ch;
    v[ch] = sampleAt(s.curve_samples.?, s.curve_count, v[ch]);
}

fn applyChadStage(s: *const types.LinkStage, v: []f32) void {
    const wx = s.white.?.x;
    const wy = s.white.?.y;
    const wz = s.white.?.z;
    if (wy == 0.0) return;
    v[0] *= wx / wy;
    v[2] *= wz / wy;
}

fn applyMatrixStage(s: *const types.LinkStage, v: []f32) void {
    const m = s.matrix.?;
    const r = m.e[0] * v[0] + m.e[1] * v[1] + m.e[2] * v[2] + m.off[0];
    const g = m.e[3] * v[0] + m.e[4] * v[1] + m.e[5] * v[2] + m.off[1];
    const b = m.e[6] * v[0] + m.e[7] * v[1] + m.e[8] * v[2] + m.off[2];
    v[0] = r;
    v[1] = g;
    v[2] = b;
}

pub fn apply(p: *const types.Profile, lc: *const types.LinkCache, input: []const f32, output: []f32) bool {
    if (!lc.built or lc.order == null or lc.order_count == 0) return false;

    var work: [types.MAX_CHANNELS]f32 = [_]f32{0} ** types.MAX_CHANNELS;
    var d: usize = 0;
    while (d < p.channels and d < input.len) : (d += 1) {
        work[d] = input[d];
    }

    var i: usize = 0;
    while (i < lc.order_count) : (i += 1) {
        const s = lc.order.?[i] orelse continue;
        switch (s.kind) {
            .curve => applyCurveStage(s, &work),
            .chad => applyChadStage(s, &work),
            .matrix => applyMatrixStage(s, &work),
            .clut => mpet_mod.applyClut(s, &work),
        }
    }

    d = 0;
    while (d < p.pcs_channels and d < output.len) : (d += 1) {
        output[d] = work[d];
    }
    return true;
}
