// transfer.zig - transfer function library
//
// Standard OETF/EOTF implementations for display and camera workflows.
// Includes sRGB, BT.709, BT.2020, DCI-P3, ProPhoto, and log encodings.

fn approxPow(x: f32, g: f32) f32 {
    if (x <= 0) return 0;
    if (x >= 1) return 1;
    const u = 1.0 - x;
    const ln_x = -(u + u * u * 0.5 + u * u * u / 3.0 + u * u * u * u * 0.25);
    const t = g * ln_x;
    var sum: f32 = 1.0;
    var term: f32 = 1.0;
    var i: u32 = 1;
    while (i <= 12) : (i += 1) { term *= t / @as(f32, @floatFromInt(i)); sum += term; }
    if (sum < 0) return 0;
    if (sum > 1) return 1;
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

fn approxSqrt(x: f32) f32 {
    if (x <= 0) return 0;
    var y = x;
    var k: u32 = 0;
    while (k < 8) : (k += 1) y = (y + x / y) * 0.5;
    return y;
}

pub const TransferFn = enum(u8) {
    srgb = 0,
    bt709 = 1,
    bt2020 = 2,
    dci_p3 = 3,
    prophoto = 4,
    gamma22 = 5,
    gamma26 = 6,
    gamma28 = 7,
    linear = 8,
    log_c = 9,
    slog3 = 10,
};

// sRGB forward (linear → sRGB)
pub fn srgbForward(x: f32) f32 {
    if (x <= 0.0031308) return 12.92 * x;
    return 1.055 * approxPow(x, 1.0 / 2.4) - 0.055;
}

// sRGB inverse (sRGB → linear)
pub fn srgbInverse(x: f32) f32 {
    if (x <= 0.04045) return x / 12.92;
    return approxPow((x + 0.055) / 1.055, 2.4);
}

// BT.709 OETF
pub fn bt709Forward(x: f32) f32 {
    if (x < 0.018) return 4.5 * x;
    return 1.099 * approxPow(x, 0.45) - 0.099;
}

// BT.709 EOTF
pub fn bt709Inverse(x: f32) f32 {
    if (x < 0.081) return x / 4.5;
    return approxPow((x + 0.099) / 1.099, 1.0 / 0.45);
}

// BT.2020 (10-bit)
pub fn bt2020Forward(x: f32) f32 {
    const alpha: f32 = 1.0993;
    const beta: f32 = 0.0181;
    if (x < beta) return 4.5 * x;
    return alpha * approxPow(x, 0.45) - (alpha - 1.0);
}

pub fn bt2020Inverse(x: f32) f32 {
    const alpha: f32 = 1.0993;
    const beta: f32 = 0.0181;
    if (x < 4.5 * beta) return x / 4.5;
    return approxPow((x + alpha - 1.0) / alpha, 1.0 / 0.45);
}

// DCI-P3 (pure gamma 2.6)
pub fn dciP3Forward(x: f32) f32 {
    return approxPow(x, 1.0 / 2.6);
}

pub fn dciP3Inverse(x: f32) f32 {
    return approxPow(x, 2.6);
}

// ProPhoto RGB (ROMM)
pub fn proPhotoForward(x: f32) f32 {
    if (x < 0.001953) return 16.0 * x;
    return approxPow(x, 1.0 / 1.8);
}

pub fn proPhotoInverse(x: f32) f32 {
    if (x < 0.03125) return x / 16.0;
    return approxPow(x, 1.8);
}

// ARRI LogC (simplified)
pub fn logCForward(x: f32) f32 {
    if (x <= 0) return 0;
    const a: f32 = 5.555556;
    const b: f32 = 0.052272;
    const c: f32 = 0.247190;
    const d: f32 = 0.385537;
    const e: f32 = 5.367655;
    const f: f32 = 0.092809;
    if (x > b) {
        return c * approxLn(a * x + d) / approxLn(10.0) + f;
    }
    return e * x + f;
}

// Sony S-Log3
pub fn slog3Forward(x: f32) f32 {
    if (x <= 0) return 0;
    if (x >= 0.01125) {
        return (420.0 + approxLn(x * 261.5 + 0.01) / approxLn(10.0) * 261.5) / 1023.0;
    }
    return (x * (171.2102946929 - 95.0) / 0.01125000 + 95.0) / 1023.0;
}

// Dispatch forward
pub fn forward(x: f32, tf: TransferFn) f32 {
    return switch (tf) {
        .srgb => srgbForward(x),
        .bt709 => bt709Forward(x),
        .bt2020 => bt2020Forward(x),
        .dci_p3 => dciP3Forward(x),
        .prophoto => proPhotoForward(x),
        .gamma22 => approxPow(x, 1.0 / 2.2),
        .gamma26 => approxPow(x, 1.0 / 2.6),
        .gamma28 => approxPow(x, 1.0 / 2.8),
        .linear => x,
        .log_c => logCForward(x),
        .slog3 => slog3Forward(x),
    };
}

// Dispatch inverse
pub fn inverse(x: f32, tf: TransferFn) f32 {
    return switch (tf) {
        .srgb => srgbInverse(x),
        .bt709 => bt709Inverse(x),
        .bt2020 => bt2020Inverse(x),
        .dci_p3 => dciP3Inverse(x),
        .prophoto => proPhotoInverse(x),
        .gamma22 => approxPow(x, 2.2),
        .gamma26 => approxPow(x, 2.6),
        .gamma28 => approxPow(x, 2.8),
        .linear => x,
        .log_c => x, // simplified
        .slog3 => x, // simplified
    };
}

// Generate a TRC table from a transfer function
pub fn generateTrc(samples: []f32, tf: TransferFn) void {
    const n = samples.len;
    if (n < 2) return;
    for (samples, 0..) |*s, i| {
        const x = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(n - 1));
        s.* = forward(x, tf);
    }
}

// Compute round-trip error for a transfer function
pub fn roundtripError(tf: TransferFn, count: u32) f32 {
    var max_err: f32 = 0;
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        const x = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(count - 1));
        const encoded = forward(x, tf);
        const decoded = inverse(encoded, tf);
        var err = x - decoded;
        if (err < 0) err = -err;
        if (err > max_err) max_err = err;
    }
    return max_err;
}

// Batch apply transfer function
pub fn batchForward(data: []f32, count: usize, tf: TransferFn) void {
    var i: usize = 0;
    while (i < count) : (i += 1) {
        data[i] = forward(data[i], tf);
    }
}

pub fn batchInverse(data: []f32, count: usize, tf: TransferFn) void {
    var i: usize = 0;
    while (i < count) : (i += 1) {
        data[i] = inverse(data[i], tf);
    }
}
