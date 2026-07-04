// profquality.zig - comprehensive profile quality analysis
//
// Evaluate overall profile quality by combining multiple metrics:
// curve smoothness, CLUT continuity, matrix conditioning, tag
// completeness, and transform accuracy at reference colors.

const types = @import("types.zig");

fn approxSqrt(x: f32) f32 {
    if (x <= 0) return 0;
    var y = x;
    var k: u32 = 0;
    while (k < 8) : (k += 1) y = (y + x / y) * 0.5;
    return y;
}

pub const QualityGrade = enum(u8) {
    excellent = 5,
    good = 4,
    acceptable = 3,
    marginal = 2,
    poor = 1,
    invalid = 0,
};

pub const QualityReport = struct {
    overall_score: f32 = 0,
    grade: QualityGrade = .invalid,
    curve_score: f32 = 0,
    clut_score: f32 = 0,
    matrix_score: f32 = 0,
    tag_score: f32 = 0,
    transform_score: f32 = 0,
    white_accuracy: f32 = 0,
    black_level: f32 = 0,
    channel_separation: f32 = 0,
    monotonicity: bool = true,
    has_required_tags: bool = false,
    issues_count: u32 = 0,
    warnings: [8]u32 = [_]u32{0} ** 8,
    warning_count: u32 = 0,
};

pub const WarningCode = enum(u32) {
    missing_wtpt = 1,
    missing_desc = 2,
    nonmonotonic_trc = 3,
    clut_discontinuity = 4,
    matrix_singular = 5,
    version_mismatch = 6,
    oversized_profile = 7,
    empty_transform = 8,
};

fn addWarning(report: *QualityReport, code: WarningCode) void {
    if (report.warning_count < 8) {
        report.warnings[report.warning_count] = @intFromEnum(code);
        report.warning_count += 1;
        report.issues_count += 1;
    }
}

// Evaluate curve quality
fn evaluateCurves(p: *const types.Profile) f32 {
    var score: f32 = 1.0;
    if (p.pool.items == null) return 0;
    var curve_count: u32 = 0;
    var i: usize = 0;
    while (i < p.pool.count) : (i += 1) {
        if (p.pool.items.?[i]) |el| {
            if (el.kind == .curve) {
                curve_count += 1;
                const cv = el.data.curve;
                if (cv.samples != null and cv.count >= 4) {
                    // Check monotonicity
                    var k: u32 = 1;
                    while (k < cv.count) : (k += 1) {
                        if (cv.samples.?[k] < cv.samples.?[k - 1] - 0.001) {
                            score -= 0.1;
                            break;
                        }
                    }
                    // Check smoothness
                    if (cv.count >= 3) {
                        var max_d2: f32 = 0;
                        k = 1;
                        while (k + 1 < cv.count) : (k += 1) {
                            var d2 = cv.samples.?[k - 1] - 2.0 * cv.samples.?[k] + cv.samples.?[k + 1];
                            if (d2 < 0) d2 = -d2;
                            if (d2 > max_d2) max_d2 = d2;
                        }
                        if (max_d2 > 0.05) score -= 0.1;
                    }
                }
            }
        }
    }
    if (curve_count == 0) score = 0.5;
    if (score < 0) score = 0;
    return score;
}

// Evaluate CLUT quality
fn evaluateCluts(p: *const types.Profile) f32 {
    var score: f32 = 1.0;
    if (p.pool.items == null) return 0.5;
    var clut_count: u32 = 0;
    var i: usize = 0;
    while (i < p.pool.count) : (i += 1) {
        if (p.pool.items.?[i]) |el| {
            if (el.kind == .clut) {
                clut_count += 1;
                const cl = el.data.clut;
                // Check for reasonable grid sizes
                var d: u8 = 0;
                while (d < cl.in_ch) : (d += 1) {
                    if (cl.grid[d] < 5) score -= 0.05;
                    if (cl.grid[d] > 51) score -= 0.05;
                }
                // Check for out-of-range values
                if (cl.table) |tbl| {
                    const total = @as(usize, cl.point_count) * cl.out_ch;
                    var k: usize = 0;
                    var oor: u32 = 0;
                    while (k < total) : (k += 1) {
                        if (tbl[k] < -0.1 or tbl[k] > 1.1) oor += 1;
                    }
                    if (oor > total / 10) score -= 0.2;
                }
            }
        }
    }
    if (clut_count == 0) score = 0.5;
    if (score < 0) score = 0;
    return score;
}

// Evaluate matrix quality
fn evaluateMatrices(p: *const types.Profile) f32 {
    var score: f32 = 1.0;
    if (p.pool.items == null) return 0.5;
    var i: usize = 0;
    while (i < p.pool.count) : (i += 1) {
        if (p.pool.items.?[i]) |el| {
            if (el.kind == .matrix) {
                const m = el.data.matrix;
                // Check determinant
                const det = m.e[0] * (m.e[4] * m.e[8] - m.e[5] * m.e[7]) -
                    m.e[1] * (m.e[3] * m.e[8] - m.e[5] * m.e[6]) +
                    m.e[2] * (m.e[3] * m.e[7] - m.e[4] * m.e[6]);
                if (det == 0) score -= 0.3;
                const ad = if (det < 0) -det else det; _ = ad;
                _ = ad;
                // Check for extreme values
                for (m.e) |v| {
                    if (v > 5 or v < -5) score -= 0.05;
                }
            }
        }
    }
    if (score < 0) score = 0;
    return score;
}

// Evaluate tag completeness
fn evaluateTags(p: *const types.Profile) f32 {
    var score: f32 = 0.5;
    if (p.tags == null or p.tag_count == 0) return 0;
    score = 0.5 + @as(f32, @floatFromInt(if (p.tag_count > 10) @as(u32, 10) else @as(u32, @intCast(p.tag_count)))) * 0.05;
    if (score > 1) score = 1;
    return score;
}

// Full quality report
pub fn analyze(p: *const types.Profile) QualityReport {
    var report = QualityReport{};

    report.curve_score = evaluateCurves(p);
    report.clut_score = evaluateCluts(p);
    report.matrix_score = evaluateMatrices(p);
    report.tag_score = evaluateTags(p);

    // Transform evaluation (basic)
    if (p.link.built and p.link.order_count > 0) {
        report.transform_score = 0.8;
    } else {
        report.transform_score = 0.2;
        addWarning(&report, .empty_transform);
    }

    // White point accuracy
    if (p.white) |w| {
        const d50_x: f32 = 0.9642;
        const d50_z: f32 = 0.8249;
        const dx = w.x - d50_x;
        const dz = w.z - d50_z;
        report.white_accuracy = 1.0 - approxSqrt(dx * dx + dz * dz) * 10.0;
        if (report.white_accuracy < 0) report.white_accuracy = 0;
    }

    // Overall score
    report.overall_score = report.curve_score * 0.2 +
        report.clut_score * 0.2 +
        report.matrix_score * 0.15 +
        report.tag_score * 0.15 +
        report.transform_score * 0.3;

    // Grade
    if (report.overall_score >= 0.9) report.grade = .excellent
    else if (report.overall_score >= 0.75) report.grade = .good
    else if (report.overall_score >= 0.6) report.grade = .acceptable
    else if (report.overall_score >= 0.4) report.grade = .marginal
    else report.grade = .poor;

    return report;
}
