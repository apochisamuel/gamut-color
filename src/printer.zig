// printer.zig - printer color model simulation
//
// Simulate CMYK ink mixing using Neugebauer and Yule-Nielsen models.
// Handles dot gain, total area coverage limits, ink interaction,
// and paper-ink optical density computation.

fn approxSqrt(x: f32) f32 {
    if (x <= 0) return 0;
    var y = x;
    var k: u32 = 0;
    while (k < 8) : (k += 1) y = (y + x / y) * 0.5;
    return y;
}

fn approxPow(x: f32, g: f32) f32 {
    if (x <= 0) return 0;
    const u = 1.0 - x;
    const ln = -(u + u * u * 0.5 + u * u * u / 3.0);
    const t = g * ln;
    var sum: f32 = 1.0;
    var term: f32 = 1.0;
    var i: u32 = 1;
    while (i <= 10) : (i += 1) { term *= t / @as(f32, @floatFromInt(i)); sum += term; }
    return sum;
}

fn approxLn(x: f32) f32 {
    if (x <= 0) return -30;
    var v = x;
    var r: f32 = 0;
    while (v >= 2) { v *= 0.5; r += 0.6931; }
    const u = v - 1.0;
    r += u - u * u * 0.5 + u * u * u / 3.0;
    return r;
}

pub const InkSet = struct {
    paper: [3]f32 = .{ 0.95, 0.95, 0.95 },
    cyan: [3]f32 = .{ 0.15, 0.55, 0.65 },
    magenta: [3]f32 = .{ 0.75, 0.20, 0.40 },
    yellow: [3]f32 = .{ 0.90, 0.85, 0.15 },
    black: [3]f32 = .{ 0.05, 0.05, 0.05 },
    dot_gain_c: f32 = 0.20,
    dot_gain_m: f32 = 0.22,
    dot_gain_y: f32 = 0.18,
    dot_gain_k: f32 = 0.25,
    tac_limit: f32 = 300.0,
    n_factor: f32 = 1.8,
};

// Neugebauer primary reflectances (8 primaries for CMYK)
fn neugebauerPrimary(inks: *const InkSet, primary: u4, channel: usize) f32 {
    const p = inks.paper[channel];
    const c_r = inks.cyan[channel];
    const m_r = inks.magenta[channel];
    const y_r = inks.yellow[channel];
    const k_r = inks.black[channel];
    return switch (primary) {
        0 => p,                           // paper
        1 => c_r,                         // C
        2 => m_r,                         // M
        3 => c_r * m_r / (p + 0.001),    // CM
        4 => y_r,                         // Y
        5 => c_r * y_r / (p + 0.001),    // CY
        6 => m_r * y_r / (p + 0.001),    // MY
        7 => k_r,                         // CMY ≈ K
        else => p,
    };
}

// Demichel area coverage for 16 Neugebauer primaries
fn demichelArea(c: f32, m: f32, y: f32, k: f32, primary: u4) f32 {
    const cp = 1.0 - c;
    const mp = 1.0 - m;
    const yp = 1.0 - y;
    const kp = 1.0 - k;
    return switch (primary) {
        0 => cp * mp * yp * kp,  // paper
        1 => c * mp * yp * kp,   // C
        2 => cp * m * yp * kp,   // M
        3 => c * m * yp * kp,    // CM
        4 => cp * mp * y * kp,   // Y
        5 => c * mp * y * kp,    // CY
        6 => cp * m * y * kp,    // MY
        7 => c * m * y * kp,     // CMY
        8 => cp * mp * yp * k,   // K
        9 => c * mp * yp * k,    // CK
        10 => cp * m * yp * k,   // MK
        11 => c * m * yp * k,    // CMK
        12 => cp * mp * y * k,   // YK
        13 => c * mp * y * k,    // CYK
        14 => cp * m * y * k,    // MYK
        15 => c * m * y * k,     // CMYK
    };
}

// Simple Neugebauer model: CMYK → RGB reflectance
pub fn neugebauer(cmyk: [4]f32, inks: *const InkSet) [3]f32 {
    var rgb: [3]f32 = .{ 0, 0, 0 };
    // Apply dot gain
    const c = murrayDavies(cmyk[0], inks.dot_gain_c);
    const m = murrayDavies(cmyk[1], inks.dot_gain_m);
    const y = murrayDavies(cmyk[2], inks.dot_gain_y);
    const k = murrayDavies(cmyk[3], inks.dot_gain_k);

    for (0..3) |ch| {
        var sum: f32 = 0;
        var p: u4 = 0;
        while (p < 8) : (p += 1) {
            const area = demichelArea(c, m, y, k, p);
            const refl = neugebauerPrimary(inks, p, ch);
            sum += area * refl;
        }
        rgb[ch] = sum;
    }
    return rgb;
}

// Yule-Nielsen modified Neugebauer
pub fn yuleNielsenNeugebauer(cmyk: [4]f32, inks: *const InkSet) [3]f32 {
    var rgb: [3]f32 = .{ 0, 0, 0 };
    const c = murrayDavies(cmyk[0], inks.dot_gain_c);
    const m = murrayDavies(cmyk[1], inks.dot_gain_m);
    const y = murrayDavies(cmyk[2], inks.dot_gain_y);
    const k = murrayDavies(cmyk[3], inks.dot_gain_k);
    const n = inks.n_factor;
    const inv_n = 1.0 / n;

    for (0..3) |ch| {
        var sum: f32 = 0;
        var p: u4 = 0;
        while (p < 8) : (p += 1) {
            const area = demichelArea(c, m, y, k, p);
            var refl = neugebauerPrimary(inks, p, ch);
            if (refl > 0) refl = approxPow(refl, inv_n);
            sum += area * refl;
        }
        rgb[ch] = if (sum > 0) approxPow(sum, n) else 0;
    }
    return rgb;
}

fn murrayDavies(area: f32, gain: f32) f32 {
    if (area <= 0 or area >= 1) return area;
    return area + gain * area * (1.0 - area) * 4.0;
}

// Enforce TAC limit
pub fn enforceTac(cmyk: *[4]f32, limit: f32) void {
    const tac = (cmyk[0] + cmyk[1] + cmyk[2] + cmyk[3]) * 100.0;
    if (tac > limit) {
        const scale = limit / tac;
        cmyk[0] *= scale;
        cmyk[1] *= scale;
        cmyk[2] *= scale;
        cmyk[3] *= scale;
    }
}

// Optical density from reflectance
pub fn opticalDensity(reflectance: f32) f32 {
    if (reflectance <= 0.001) return 3.0;
    return -approxLn(reflectance) / 2.3026; // -log10(R)
}

// Batch CMYK to RGB
pub fn batchCmykToRgb(cmyk: []const f32, rgb: []f32, count: usize, inks: *const InkSet) void {
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const input = [4]f32{ cmyk[i * 4], cmyk[i * 4 + 1], cmyk[i * 4 + 2], cmyk[i * 4 + 3] };
        const output = yuleNielsenNeugebauer(input, inks);
        rgb[i * 3] = output[0];
        rgb[i * 3 + 1] = output[1];
        rgb[i * 3 + 2] = output[2];
    }
}

// Compute ink cost (weighted sum of coverages)
pub fn inkCost(cmyk: [4]f32, weights: [4]f32) f32 {
    return cmyk[0] * weights[0] + cmyk[1] * weights[1] + cmyk[2] * weights[2] + cmyk[3] * weights[3];
}

// Gray balance: find CMY that produces neutral gray at a given K
pub fn grayBalance(target_l: f32, k: f32, inks: *const InkSet) [3]f32 {
    var best = [3]f32{ 0, 0, 0 };
    var best_err: f32 = 1e30;
    var ci: u32 = 0;
    while (ci <= 20) : (ci += 1) {
        const c = @as(f32, @floatFromInt(ci)) * 0.05;
        var mi: u32 = 0;
        while (mi <= 20) : (mi += 1) {
            const m = @as(f32, @floatFromInt(mi)) * 0.05;
            var yi: u32 = 0;
            while (yi <= 20) : (yi += 1) {
                const y = @as(f32, @floatFromInt(yi)) * 0.05;
                const rgb = neugebauer(.{ c, m, y, k }, inks);
                // Check if neutral (R≈G≈B) and correct lightness
                const avg = (rgb[0] + rgb[1] + rgb[2]) / 3.0;
                const chroma = approxSqrt((rgb[0] - avg) * (rgb[0] - avg) + (rgb[1] - avg) * (rgb[1] - avg) + (rgb[2] - avg) * (rgb[2] - avg));
                const l_approx = avg * 100.0;
                const l_err = l_approx - target_l;
                const err = chroma * 100.0 + l_err * l_err;
                if (err < best_err) {
                    best_err = err;
                    best = .{ c, m, y };
                }
            }
        }
    }
    return best;
}
