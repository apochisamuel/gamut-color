// proofing.zig - soft proofing simulation
//
// Simulate the visual appearance of print output on a display by
// composing device → PCS → proof transforms. Handles paper simulation,
// black point scaling, and proofing condition adjustments.

const types = @import("types.zig");

fn approxSqrt(x: f32) f32 {
    if (x <= 0) return 0;
    var y = x;
    var k: u32 = 0;
    while (k < 8) : (k += 1) y = (y + x / y) * 0.5;
    return y;
}

pub const ProofingParams = struct {
    simulate_paper: bool = true,
    simulate_ink_limit: bool = true,
    paper_white: [3]f32 = .{ 95.0, 100.0, 108.88 },
    paper_lab: [3]f32 = .{ 100.0, 0.0, 0.0 },
    ink_limit_tac: f32 = 300.0,
    black_point_scale: f32 = 1.0,
    ambient_lux: f32 = 500.0,
    surround: Surround = .average,
};

pub const Surround = enum(u8) {
    dark = 0,
    dim = 1,
    average = 2,
};

// Paper simulation: tint toward paper color
pub fn paperSimulate(lab: *[3]f32, params: *const ProofingParams) void {
    if (!params.simulate_paper) return;
    // Blend white point toward paper white
    const t = lab[0] / 100.0;
    lab[1] = lab[1] * (1.0 - t * 0.1) + params.paper_lab[1] * t * 0.1;
    lab[2] = lab[2] * (1.0 - t * 0.1) + params.paper_lab[2] * t * 0.1;
    // Reduce dynamic range
    lab[0] *= 0.95;
}

// Ink limit enforcement
pub fn inkLimitEnforce(cmyk: *[4]f32, tac_limit: f32) bool {
    const tac = (cmyk[0] + cmyk[1] + cmyk[2] + cmyk[3]) * 100.0;
    if (tac <= tac_limit) return false;
    const scale = tac_limit / tac;
    cmyk[0] *= scale;
    cmyk[1] *= scale;
    cmyk[2] *= scale;
    cmyk[3] *= scale;
    return true;
}

// Black point scaling for proofing
pub fn blackPointScale(lab: *[3]f32, src_bp: f32, dst_bp: f32, factor: f32) void {
    if (lab[0] >= 50) return;
    const range = 50.0 - src_bp;
    if (range <= 0) return;
    const t = (lab[0] - src_bp) / range;
    const new_bp = src_bp + (dst_bp - src_bp) * factor;
    lab[0] = new_bp + t * (50.0 - new_bp);
}

// Viewing condition adaptation: convert from one viewing condition to another
pub fn viewingAdapt(lab: *[3]f32, from: Surround, to: Surround) void {
    const from_factor = switch (from) {
        .dark => @as(f32, 0.525),
        .dim => @as(f32, 0.59),
        .average => @as(f32, 0.69),
    };
    const to_factor = switch (to) {
        .dark => @as(f32, 0.525),
        .dim => @as(f32, 0.59),
        .average => @as(f32, 0.69),
    };
    if (from_factor == to_factor) return;
    const ratio = to_factor / from_factor;
    lab[0] *= ratio;
    if (lab[0] > 100) lab[0] = 100;
}

// Compute proof rendering: composite proofing simulation
pub fn proofRender(lab: *[3]f32, params: *const ProofingParams) void {
    paperSimulate(lab, params);
    blackPointScale(lab, 3.0, 5.0, params.black_point_scale);
    viewingAdapt(lab, .average, params.surround);
}

// Batch proof rendering
pub fn proofRenderBatch(lab: []f32, count: usize, params: *const ProofingParams) void {
    var i: usize = 0;
    while (i < count) : (i += 1) {
        var triplet = [3]f32{ lab[i * 3], lab[i * 3 + 1], lab[i * 3 + 2] };
        proofRender(&triplet, params);
        lab[i * 3] = triplet[0];
        lab[i * 3 + 1] = triplet[1];
        lab[i * 3 + 2] = triplet[2];
    }
}

// Compute proof-to-display Delta E
pub fn proofError(original: [3]f32, proofed: [3]f32) f32 {
    const dl = original[0] - proofed[0];
    const da = original[1] - proofed[1];
    const db = original[2] - proofed[2];
    return approxSqrt(dl * dl + da * da + db * db);
}

// Ambient lighting compensation
pub fn ambientCompensate(lab: *[3]f32, lux: f32) void {
    // Higher ambient = more washed out appearance
    const factor = if (lux > 0) 500.0 / lux else 1.0;
    const contrast = if (factor > 1) 1.0 + (factor - 1.0) * 0.1 else 1.0 - (1.0 - factor) * 0.1;
    lab[0] = 50.0 + (lab[0] - 50.0) * contrast;
    if (lab[0] < 0) lab[0] = 0;
    if (lab[0] > 100) lab[0] = 100;
}

// Fluorescent whitening agent (OBA) simulation
pub fn obaSimulate(lab: *[3]f32, oba_strength: f32) void {
    // OBAs increase perceived b* (blue shift) under UV
    if (lab[0] > 90) {
        lab[2] -= oba_strength * (lab[0] - 90.0) / 10.0;
    }
}
