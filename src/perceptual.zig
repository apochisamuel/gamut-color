// perceptual.zig - perceptual color attributes
//
// Compute perceptual attributes: brightness, colorfulness, hue
// composition, and whiteness/blackness indices. Implements portions
// of CIECAM02 appearance model and CIE whiteness index.

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

pub const PerceptualAttrs = struct {
    lightness: f32 = 0,
    brightness: f32 = 0,
    chroma: f32 = 0,
    colorfulness: f32 = 0,
    saturation_attr: f32 = 0,
    hue_angle: f32 = 0,
    hue_quad: [4]f32 = .{ 0, 0, 0, 0 },
};

// Compute perceptual attributes from Lab
pub fn computeAttributes(lab: [3]f32, la: f32) PerceptualAttrs {
    var attrs = PerceptualAttrs{};

    attrs.lightness = lab[0];
    attrs.chroma = approxSqrt(lab[1] * lab[1] + lab[2] * lab[2]);
    attrs.hue_angle = atan2(lab[2], lab[1]) * 180.0 / 3.14159;
    if (attrs.hue_angle < 0) attrs.hue_angle += 360.0;

    // Brightness: Stevens power law
    const n = 0.5 + 0.1 * approxSqrt(la / 200.0);
    attrs.brightness = lab[0] * (1.0 + n * 0.1);

    // Colorfulness: Hunt effect
    const m_factor = 1.0 + 0.2 * approxSqrt(la / 200.0);
    attrs.colorfulness = attrs.chroma * m_factor;

    // Saturation: ratio of colorfulness to brightness
    if (attrs.brightness > 0) {
        attrs.saturation_attr = attrs.colorfulness / attrs.brightness * 100.0;
    }

    // Hue composition (quadrature)
    hueComposition(attrs.hue_angle, &attrs.hue_quad);

    return attrs;
}

// Hue quadrature: percentage of Red, Yellow, Green, Blue
fn hueComposition(h: f32, quad: *[4]f32) void {
    // Unique hue angles: R=20.14, Y=90.00, G=164.25, B=237.53
    const uh = [4]f32{ 20.14, 90.00, 164.25, 237.53 };
    const ue = [4]f32{ 0.8, 0.7, 1.0, 1.2 };

    quad.* = .{ 0, 0, 0, 0 };

    // Find which sector we're in
    var hp = h;
    if (hp < uh[0]) hp += 360;

    for (0..4) |i| {
        const j = (i + 1) % 4;
        const hi = uh[i];
        var hj = uh[j];
        if (j == 0) hj += 360;
        if (hi > hj) continue;

        if (hp >= hi and hp < hj) {
            const t = (hp - hi) / (hj - hi);
            quad[i] = (1.0 - t) * ue[i];
            quad[j] = t * ue[j];
            const total = quad[i] + quad[j];
            if (total > 0) {
                quad[i] /= total;
                quad[j] /= total;
            }
            break;
        }
    }
}

// CIE Whiteness Index
pub fn whitenessIndex(lab: [3]f32) f32 {
    // W = Y + 800(xn - x) + 1700(yn - y)
    // Simplified from Lab: W ≈ L* - 3*sqrt(a² + b²)
    const c = approxSqrt(lab[1] * lab[1] + lab[2] * lab[2]);
    var w = lab[0] - 3.0 * c;
    if (w < 0) w = 0;
    return w;
}

// CIE Blackness Index
pub fn blacknessIndex(lab: [3]f32) f32 {
    return 100.0 - lab[0];
}

// Grayness index (low chroma = more gray)
pub fn graynessIndex(lab: [3]f32) f32 {
    const c = approxSqrt(lab[1] * lab[1] + lab[2] * lab[2]);
    if (c >= 20) return 0;
    return (20.0 - c) / 20.0;
}

// Warmth index (positive = warm, negative = cool)
pub fn warmthIndex(lab: [3]f32) f32 {
    // b* > 0 = warm (yellow), b* < 0 = cool (blue)
    // a* > 0 adds warmth (red), a* < 0 adds coolness (green)
    return lab[2] * 0.7 + lab[1] * 0.3;
}

// Vividness (combination of chroma and lightness contrast)
pub fn vividness(lab: [3]f32) f32 {
    const c = approxSqrt(lab[1] * lab[1] + lab[2] * lab[2]);
    const l_factor = 1.0 - (lab[0] - 50.0) * (lab[0] - 50.0) / 2500.0;
    return c * (if (l_factor > 0) l_factor else 0);
}

// Batch compute perceptual attributes
pub fn batchAttributes(lab: []const f32, attrs: []PerceptualAttrs, count: usize, la: f32) void {
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const triplet = [3]f32{ lab[i * 3], lab[i * 3 + 1], lab[i * 3 + 2] };
        attrs[i] = computeAttributes(triplet, la);
    }
}

// Color harmony: complementary angle distance
pub fn harmonicDistance(h1: f32, h2: f32) f32 {
    var d = h1 - h2;
    if (d < 0) d = -d;
    if (d > 180) d = 360 - d;
    // Ideal complementary = 180°
    var dist = d - 180.0;
    if (dist < 0) dist = -dist;
    return dist;
}

// Triadic harmony score (three colors)
pub fn triadicScore(h1: f32, h2: f32, h3: f32) f32 {
    // Ideal triadic = 120° apart
    const d12 = normalizeAngle(h2 - h1);
    const d23 = normalizeAngle(h3 - h2);
    const d31 = normalizeAngle(h1 - h3);
    var err: f32 = 0;
    var e = d12 - 120;
    if (e < 0) e = -e;
    err += e;
    e = d23 - 120;
    if (e < 0) e = -e;
    err += e;
    e = d31 - 120;
    if (e < 0) e = -e;
    err += e;
    return 1.0 - err / 360.0;
}

fn normalizeAngle(a: f32) f32 {
    var h = a;
    while (h < 0) h += 360;
    while (h >= 360) h -= 360;
    return h;
}
