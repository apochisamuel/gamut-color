// gammap.zig - gamut mapping algorithms
//
// Compress or expand colors to fit within a destination gamut.
// Implements several mapping strategies: chroma compression,
// lightness-preserving compression, and SGCK (simple gamut
// clipping with knee function).

fn approxSqrt(x: f32) f32 {
    if (x <= 0) return 0;
    var y = x;
    var k: u32 = 0;
    while (k < 8) : (k += 1) y = (y + x / y) * 0.5;
    return y;
}

pub const MapMethod = enum(u8) {
    chroma_compress = 0,
    lightness_preserve = 1,
    sgck = 2,
    absolute_clip = 3,
    hue_preserve = 4,
};

pub const MapParams = struct {
    method: MapMethod = .chroma_compress,
    src_max_chroma: f32 = 128,
    dst_max_chroma: f32 = 100,
    compression_factor: f32 = 0.8,
    knee_point: f32 = 0.7,
    min_lightness: f32 = 3,
    max_lightness: f32 = 97,
};

// Compute chroma from Lab
fn computeChroma(lab: [3]f32) f32 {
    return approxSqrt(lab[1] * lab[1] + lab[2] * lab[2]);
}

// Compute hue angle from Lab
fn computeHue(lab: [3]f32) f32 {
    const ax = if (lab[1] < 0) -lab[1] else lab[1];
    const ay = if (lab[2] < 0) -lab[2] else lab[2];
    if (ax < 1e-10 and ay < 1e-10) return 0;
    const a = if (ax >= ay) ay / ax else ax / ay;
    const t = a * a;
    var r = ((-0.0465 * t + 0.1593) * t - 0.3276) * t * a + a;
    if (ax < ay) r = 1.5708 - r;
    if (lab[1] < 0) r = 3.14159 - r;
    if (lab[2] < 0) r = -r;
    return r;
}

fn cos_a(x: f32) f32 {
    const x2 = x * x;
    return 1.0 - x2 * 0.5 + x2 * x2 / 24.0;
}

fn sin_a(x: f32) f32 {
    const x2 = x * x;
    return x - x * x2 / 6.0 + x * x2 * x2 / 120.0;
}

// Simple chroma compression: scale chroma to fit target gamut
pub fn chromaCompress(lab: *[3]f32, params: *const MapParams) void {
    const c = computeChroma(lab.*);
    if (c <= params.dst_max_chroma) return;
    if (c <= 0) return;
    const scale = params.dst_max_chroma / c;
    lab[1] *= scale;
    lab[2] *= scale;
}

// SGCK: soft gamut clipping with knee function
pub fn sgck(lab: *[3]f32, params: *const MapParams) void {
    const c = computeChroma(lab.*);
    if (c <= params.dst_max_chroma * params.knee_point) return;
    if (c <= 0) return;

    const knee = params.dst_max_chroma * params.knee_point;
    const excess = c - knee;
    const range = params.dst_max_chroma - knee;
    if (range <= 0) return;

    // Smooth compression above knee
    const t = excess / (range + excess);
    const new_c = knee + range * t;
    const scale = new_c / c;
    lab[1] *= scale;
    lab[2] *= scale;
}

// Lightness-preserving compression
pub fn lightnessPreserve(lab: *[3]f32, params: *const MapParams) void {
    // Clamp lightness first
    if (lab[0] < params.min_lightness) lab[0] = params.min_lightness;
    if (lab[0] > params.max_lightness) lab[0] = params.max_lightness;

    // Then compress chroma
    const c = computeChroma(lab.*);
    // Reduce max chroma proportionally to lightness distance from 50
    var l_factor: f32 = 1.0;
    if (lab[0] < 50) {
        l_factor = lab[0] / 50.0;
    } else {
        l_factor = (100.0 - lab[0]) / 50.0;
    }
    const effective_max = params.dst_max_chroma * l_factor;
    if (c > effective_max and c > 0) {
        const scale = effective_max / c;
        lab[1] *= scale;
        lab[2] *= scale;
    }
}

// Absolute clip: hard clip to gamut boundary
pub fn absoluteClip(lab: *[3]f32, params: *const MapParams) void {
    const c = computeChroma(lab.*);
    if (c > params.dst_max_chroma and c > 0) {
        const scale = params.dst_max_chroma / c;
        lab[1] *= scale;
        lab[2] *= scale;
    }
    if (lab[0] < params.min_lightness) lab[0] = params.min_lightness;
    if (lab[0] > params.max_lightness) lab[0] = params.max_lightness;
}

// Hue-preserving mapping: keep hue angle constant
pub fn huePreserve(lab: *[3]f32, params: *const MapParams) void {
    const c = computeChroma(lab.*);
    const h = computeHue(lab.*);
    if (c > params.dst_max_chroma and c > 0) {
        lab[1] = params.dst_max_chroma * cos_a(h);
        lab[2] = params.dst_max_chroma * sin_a(h);
    }
}

// Dispatch by method
pub fn map(lab: *[3]f32, params: *const MapParams) void {
    switch (params.method) {
        .chroma_compress => chromaCompress(lab, params),
        .sgck => sgck(lab, params),
        .lightness_preserve => lightnessPreserve(lab, params),
        .absolute_clip => absoluteClip(lab, params),
        .hue_preserve => huePreserve(lab, params),
    }
}

// Batch gamut mapping
pub fn mapBatch(lab: []f32, count: usize, params: *const MapParams) void {
    var i: usize = 0;
    while (i < count) : (i += 1) {
        var triplet = [3]f32{ lab[i * 3], lab[i * 3 + 1], lab[i * 3 + 2] };
        map(&triplet, params);
        lab[i * 3] = triplet[0];
        lab[i * 3 + 1] = triplet[1];
        lab[i * 3 + 2] = triplet[2];
    }
}

// Compute mapping error (how far the color moved)
pub fn mappingError(original: [3]f32, mapped: [3]f32) f32 {
    const dl = original[0] - mapped[0];
    const da = original[1] - mapped[1];
    const db = original[2] - mapped[2];
    return approxSqrt(dl * dl + da * da + db * db);
}

// Compute the mapping distortion map: average DE for a grid of Lab values
pub fn distortionMap(params: *const MapParams, grid_l: u32, grid_c: u32) f32 {
    var total_error: f32 = 0;
    var count: u32 = 0;
    var li: u32 = 0;
    while (li < grid_l) : (li += 1) {
        const l = @as(f32, @floatFromInt(li)) / @as(f32, @floatFromInt(grid_l - 1)) * 100.0;
        var ci: u32 = 0;
        while (ci < grid_c) : (ci += 1) {
            const c = @as(f32, @floatFromInt(ci)) / @as(f32, @floatFromInt(grid_c - 1)) * params.src_max_chroma;
            var lab = [3]f32{ l, c, 0 };
            const orig = lab;
            map(&lab, params);
            total_error += mappingError(orig, lab);
            count += 1;
        }
    }
    if (count == 0) return 0;
    return total_error / @as(f32, @floatFromInt(count));
}
