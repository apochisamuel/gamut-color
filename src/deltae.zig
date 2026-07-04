// deltae.zig - advanced color difference formulas
//
// CIE Delta E 2000 and CMC(l:c) implementations. These are the
// industry standard perceptual color difference metrics.

fn approxSqrt(x: f32) f32 {
    if (x <= 0) return 0;
    var y = x;
    var k: u32 = 0;
    while (k < 10) : (k += 1) y = (y + x / y) * 0.5;
    return y;
}

fn approxPow(x: f32, g: f32) f32 {
    if (x <= 0) return 0;
    if (x >= 1) return 1;
    const u = 1.0 - x;
    const ln_x = -(u + u * u * 0.5 + u * u * u / 3.0);
    const t = g * ln_x;
    var sum: f32 = 1.0;
    var term: f32 = 1.0;
    var i: u32 = 1;
    while (i <= 12) : (i += 1) {
        term *= t / @as(f32, @floatFromInt(i));
        sum += term;
    }
    return sum;
}

fn atan2(y: f32, x: f32) f32 {
    const ax = if (x < 0) -x else x;
    const ay = if (y < 0) -y else y;
    if (ax < 1e-10 and ay < 1e-10) return 0;
    const a = if (ax >= ay) ay / ax else ax / ay;
    const t = a * a;
    var r = ((-0.0465 * t + 0.1593) * t - 0.3276) * t * a + a;
    if (ax < ay) r = 1.5708 - r;
    if (x < 0) r = 3.14159 - r;
    if (y < 0) r = -r;
    return r;
}

fn cos_approx(x: f32) f32 {
    const x2 = x * x;
    return 1.0 - x2 * 0.5 + x2 * x2 / 24.0 - x2 * x2 * x2 / 720.0;
}

fn sin_approx(x: f32) f32 {
    const x2 = x * x;
    return x - x * x2 / 6.0 + x * x2 * x2 / 120.0;
}

fn exp_approx(x: f32) f32 {
    var sum: f32 = 1.0;
    var term: f32 = 1.0;
    var k: u32 = 1;
    while (k <= 12) : (k += 1) {
        term *= x / @as(f32, @floatFromInt(k));
        sum += term;
    }
    return sum;
}

const PI: f32 = 3.14159265;
const DEG: f32 = PI / 180.0;

// CIE Delta E 2000 (CIEDE2000)
pub fn deltaE2000(lab1: [3]f32, lab2: [3]f32) f32 {
    const kL: f32 = 1;
    const kC: f32 = 1;
    const kH: f32 = 1;

    const l1 = lab1[0];
    const a1 = lab1[1];
    const b1 = lab1[2];
    const l2 = lab2[0];
    const a2 = lab2[1];
    const b2 = lab2[2];

    // Step 1: compute Cab and hab
    const c1s = approxSqrt(a1 * a1 + b1 * b1);
    const c2s = approxSqrt(a2 * a2 + b2 * b2);
    const c_bar = (c1s + c2s) / 2.0;

    const c7 = c_bar * c_bar * c_bar * c_bar * c_bar * c_bar * c_bar;
    const g = 0.5 * (1.0 - approxSqrt(c7 / (c7 + 6103515625.0)));

    const a1p = a1 * (1.0 + g);
    const a2p = a2 * (1.0 + g);

    const c1p = approxSqrt(a1p * a1p + b1 * b1);
    const c2p = approxSqrt(a2p * a2p + b2 * b2);

    var h1p = atan2(b1, a1p);
    if (h1p < 0) h1p += 2.0 * PI;
    var h2p = atan2(b2, a2p);
    if (h2p < 0) h2p += 2.0 * PI;

    // Step 2: compute delta values
    const dLp = l2 - l1;
    const dCp = c2p - c1p;

    var dhp: f32 = 0;
    if (c1p * c2p != 0) {
        dhp = h2p - h1p;
        if (dhp > PI) dhp -= 2.0 * PI;
        if (dhp < -PI) dhp += 2.0 * PI;
    }

    const dHp = 2.0 * approxSqrt(c1p * c2p) * sin_approx(dhp / 2.0);

    // Step 3: compute CIEDE2000
    const l_bar = (l1 + l2) / 2.0;
    const c_bar_p = (c1p + c2p) / 2.0;

    var h_bar_p: f32 = 0;
    if (c1p * c2p != 0) {
        var dh_abs = h1p - h2p;
        if (dh_abs < 0) dh_abs = -dh_abs;
        if (dh_abs <= PI) {
            h_bar_p = (h1p + h2p) / 2.0;
        } else {
            h_bar_p = (h1p + h2p + 2.0 * PI) / 2.0;
            if (h_bar_p > 2.0 * PI) h_bar_p -= 2.0 * PI;
        }
    }

    const t = 1.0 -
        0.17 * cos_approx(h_bar_p - 30.0 * DEG) +
        0.24 * cos_approx(2.0 * h_bar_p) +
        0.32 * cos_approx(3.0 * h_bar_p + 6.0 * DEG) -
        0.20 * cos_approx(4.0 * h_bar_p - 63.0 * DEG);

    const l50_2 = (l_bar - 50.0) * (l_bar - 50.0);
    const sl = 1.0 + 0.015 * l50_2 / approxSqrt(20.0 + l50_2);
    const sc = 1.0 + 0.045 * c_bar_p;
    const sh = 1.0 + 0.015 * c_bar_p * t;

    const c7p = c_bar_p * c_bar_p * c_bar_p * c_bar_p * c_bar_p * c_bar_p * c_bar_p;
    const rc = 2.0 * approxSqrt(c7p / (c7p + 6103515625.0));

    const h_minus_275 = (h_bar_p / DEG - 275.0) / 25.0;
    const rt = -sin_approx(2.0 * (30.0 * DEG * exp_approx(-h_minus_275 * h_minus_275))) * rc;

    const lp = dLp / (kL * sl);
    const cp = dCp / (kC * sc);
    const hp = dHp / (kH * sh);

    return approxSqrt(lp * lp + cp * cp + hp * hp + rt * cp * hp);
}

// CMC(l:c) color difference
pub fn deltaCMC(lab1: [3]f32, lab2: [3]f32, l_weight: f32, c_weight: f32) f32 {
    const dL = lab1[0] - lab2[0];
    const c1 = approxSqrt(lab1[1] * lab1[1] + lab1[2] * lab1[2]);
    const c2 = approxSqrt(lab2[1] * lab2[1] + lab2[2] * lab2[2]);
    const dC = c1 - c2;
    const da = lab1[1] - lab2[1];
    const db = lab1[2] - lab2[2];
    const dH2 = da * da + db * db - dC * dC;
    const dH = if (dH2 > 0) approxSqrt(dH2) else 0;

    const sl: f32 = if (lab1[0] < 16.0) 0.511 else 0.040975 * lab1[0] / (1.0 + 0.01765 * lab1[0]);

    const sc = 0.0638 * c1 / (1.0 + 0.0131 * c1) + 0.638;

    var h1 = atan2(lab1[2], lab1[1]);
    if (h1 < 0) h1 += 2.0 * PI;
    const h1_deg = h1 / DEG;

    const t_val = if (h1_deg >= 164 and h1_deg <= 345)
        0.56 + if (0.2 * cos_approx((h1 + 168.0 * DEG)) > 0) 0.2 * cos_approx((h1 + 168.0 * DEG)) else -0.2 * cos_approx((h1 + 168.0 * DEG))
    else
        0.36 + if (0.4 * cos_approx((h1 + 35.0 * DEG)) > 0) 0.4 * cos_approx((h1 + 35.0 * DEG)) else -0.4 * cos_approx((h1 + 35.0 * DEG));

    const c14 = c1 * c1 * c1 * c1;
    const f = approxSqrt(c14 / (c14 + 1900.0));

    const sh = sc * (f * t_val + 1.0 - f);

    const term_l = dL / (l_weight * sl);
    const term_c = dC / (c_weight * sc);
    const term_h = dH / sh;

    return approxSqrt(term_l * term_l + term_c * term_c + term_h * term_h);
}

// Batch Delta E 2000
pub fn batchDeltaE2000(lab_a: []const f32, lab_b: []const f32, output: []f32, count: usize) void {
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const a = [3]f32{ lab_a[i * 3], lab_a[i * 3 + 1], lab_a[i * 3 + 2] };
        const b = [3]f32{ lab_b[i * 3], lab_b[i * 3 + 1], lab_b[i * 3 + 2] };
        output[i] = deltaE2000(a, b);
    }
}

// Mean Delta E 2000
pub fn meanDeltaE2000(lab_a: []const f32, lab_b: []const f32, count: usize) f32 {
    if (count == 0) return 0;
    var sum: f32 = 0;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const a = [3]f32{ lab_a[i * 3], lab_a[i * 3 + 1], lab_a[i * 3 + 2] };
        const b = [3]f32{ lab_b[i * 3], lab_b[i * 3 + 1], lab_b[i * 3 + 2] };
        sum += deltaE2000(a, b);
    }
    return sum / @as(f32, @floatFromInt(count));
}

// Max Delta E 2000
pub fn maxDeltaE2000(lab_a: []const f32, lab_b: []const f32, count: usize) f32 {
    var mx: f32 = 0;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const a = [3]f32{ lab_a[i * 3], lab_a[i * 3 + 1], lab_a[i * 3 + 2] };
        const b = [3]f32{ lab_b[i * 3], lab_b[i * 3 + 1], lab_b[i * 3 + 2] };
        const de = deltaE2000(a, b);
        if (de > mx) mx = de;
    }
    return mx;
}
