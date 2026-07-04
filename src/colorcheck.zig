// colorcheck.zig - color checker target analysis
//
// Reference data and analysis routines for standard color checker targets.
// Compute color accuracy metrics against reference patches, build
// correction matrices, and evaluate profile quality with test targets.

fn approxSqrt(x: f32) f32 {
    if (x <= 0) return 0;
    var y = x;
    var k: u32 = 0;
    while (k < 8) : (k += 1) y = (y + x / y) * 0.5;
    return y;
}

pub const Patch = struct {
    name: [16]u8 = [_]u8{0} ** 16,
    lab: [3]f32 = .{ 0, 0, 0 },
};

// Classic 24-patch color checker (Lab D50 reference)
pub const classic_24 = [24]Patch{
    .{ .name = "dark skin\x00\x00\x00\x00\x00\x00\x00".*, .lab = .{ 37.99, 13.56, 14.06 } },
    .{ .name = "light skin\x00\x00\x00\x00\x00\x00".*, .lab = .{ 65.71, 18.13, 17.81 } },
    .{ .name = "blue sky\x00\x00\x00\x00\x00\x00\x00\x00".*, .lab = .{ 49.93, -4.88, -21.93 } },
    .{ .name = "foliage\x00\x00\x00\x00\x00\x00\x00\x00\x00".*, .lab = .{ 43.14, -13.10, 21.91 } },
    .{ .name = "blue flower\x00\x00\x00\x00\x00".*, .lab = .{ 55.11, 8.84, -25.40 } },
    .{ .name = "bluish green\x00\x00\x00\x00".*, .lab = .{ 70.72, -33.40, -0.20 } },
    .{ .name = "orange\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00".*, .lab = .{ 62.66, 36.07, 57.10 } },
    .{ .name = "purplish blue\x00\x00\x00".*, .lab = .{ 40.02, 10.41, -45.96 } },
    .{ .name = "moderate red\x00\x00\x00\x00".*, .lab = .{ 51.12, 48.24, 16.25 } },
    .{ .name = "purple\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00".*, .lab = .{ 30.33, 22.98, -21.59 } },
    .{ .name = "yellow green\x00\x00\x00\x00".*, .lab = .{ 72.53, -23.71, 57.26 } },
    .{ .name = "orange yellow\x00\x00\x00".*, .lab = .{ 71.94, 19.36, 67.86 } },
    .{ .name = "bl_ue\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00".*, .lab = .{ 28.78, 14.18, -50.30 } },
    .{ .name = "gr_een\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00".*, .lab = .{ 55.26, -38.34, 31.37 } },
    .{ .name = "re_d\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00".*, .lab = .{ 42.10, 53.38, 28.19 } },
    .{ .name = "ye_llow\x00\x00\x00\x00\x00\x00\x00\x00\x00".*, .lab = .{ 81.73, 4.04, 79.82 } },
    .{ .name = "magen_ta\x00\x00\x00\x00\x00\x00\x00\x00".*, .lab = .{ 51.94, 49.99, -14.57 } },
    .{ .name = "cy_an\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00".*, .lab = .{ 51.04, -28.63, -28.64 } },
    .{ .name = "wh_ite\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00".*, .lab = .{ 96.54, -0.43, 1.19 } },
    .{ .name = "neutral 8\x00\x00\x00\x00\x00\x00\x00".*, .lab = .{ 81.26, -0.64, -0.34 } },
    .{ .name = "neutral 6.5\x00\x00\x00\x00\x00".*, .lab = .{ 66.77, -0.73, -0.50 } },
    .{ .name = "neutral 5\x00\x00\x00\x00\x00\x00\x00".*, .lab = .{ 50.87, -0.15, -0.27 } },
    .{ .name = "neutral 3.5\x00\x00\x00\x00\x00".*, .lab = .{ 35.66, -0.42, -1.23 } },
    .{ .name = "bl_ack\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00".*, .lab = .{ 20.46, -0.08, -0.97 } },
};

pub const AccuracyResult = struct {
    mean_de: f32 = 0,
    max_de: f32 = 0,
    median_de: f32 = 0,
    percentile_90: f32 = 0,
    pass_count: u32 = 0,
    fail_count: u32 = 0,
    worst_patch: u32 = 0,
    grade: u8 = 0,
};

// Compute accuracy against reference patches
pub fn computeAccuracy(measured: []const f32, reference: []const Patch, count: usize) AccuracyResult {
    var result = AccuracyResult{};
    if (count == 0) return result;

    var errors: [128]f32 = undefined;
    var error_count: usize = 0;
    var worst_de: f32 = 0;

    var i: usize = 0;
    while (i < count and i < 128) : (i += 1) {
        const m = [3]f32{ measured[i * 3], measured[i * 3 + 1], measured[i * 3 + 2] };
        const r = reference[i].lab;
        const dl = m[0] - r[0];
        const da = m[1] - r[1];
        const db = m[2] - r[2];
        const de = approxSqrt(dl * dl + da * da + db * db);
        errors[error_count] = de;
        error_count += 1;
        result.mean_de += de;
        if (de > worst_de) {
            worst_de = de;
            result.worst_patch = @intCast(i);
        }
        if (de <= 2.0) result.pass_count += 1 else result.fail_count += 1;
    }

    result.max_de = worst_de;
    if (error_count > 0) {
        result.mean_de /= @as(f32, @floatFromInt(error_count));
    }

    // Sort errors for percentiles
    if (error_count > 1) {
        var j: usize = 1;
        while (j < error_count) : (j += 1) {
            const val = errors[j];
            var k: usize = j;
            while (k > 0 and errors[k - 1] > val) : (k -= 1) {
                errors[k] = errors[k - 1];
            }
            errors[k] = val;
        }
        result.median_de = errors[error_count / 2];
        result.percentile_90 = errors[error_count * 90 / 100];
    }

    // Grade assignment
    if (result.mean_de < 1.0) result.grade = 5 // excellent
    else if (result.mean_de < 2.0) result.grade = 4 // good
    else if (result.mean_de < 3.0) result.grade = 3 // acceptable
    else if (result.mean_de < 5.0) result.grade = 2 // marginal
    else result.grade = 1; // poor

    return result;
}

// Compute neutral axis accuracy (patches 19-24)
pub fn neutralAxisAccuracy(measured: []const f32) f32 {
    var sum_chroma: f32 = 0;
    var count: u32 = 0;
    var i: usize = 18;
    while (i < 24) : (i += 1) {
        const a = measured[i * 3 + 1];
        const b = measured[i * 3 + 2];
        sum_chroma += approxSqrt(a * a + b * b);
        count += 1;
    }
    if (count == 0) return 0;
    return sum_chroma / @as(f32, @floatFromInt(count));
}

// Compute saturation accuracy (ratio of measured to reference chroma)
pub fn saturationAccuracy(measured: []const f32, reference: []const Patch, count: usize) f32 {
    var sum_ratio: f32 = 0;
    var n: u32 = 0;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const mc = approxSqrt(measured[i * 3 + 1] * measured[i * 3 + 1] + measured[i * 3 + 2] * measured[i * 3 + 2]);
        const rc = approxSqrt(reference[i].lab[1] * reference[i].lab[1] + reference[i].lab[2] * reference[i].lab[2]);
        if (rc > 5) {
            sum_ratio += mc / rc;
            n += 1;
        }
    }
    if (n == 0) return 1;
    return sum_ratio / @as(f32, @floatFromInt(n));
}

// Compute lightness linearity (R² of neutral patches)
pub fn lightnessLinearity(measured: []const f32) f32 {
    // Expected L* values for neutral patches (19-24)
    const expected = [6]f32{ 96.54, 81.26, 66.77, 50.87, 35.66, 20.46 };
    var sum_x: f32 = 0;
    var sum_y: f32 = 0;
    var sum_xy: f32 = 0;
    var sum_x2: f32 = 0;
    var sum_y2: f32 = 0;
    const n: f32 = 6;
    for (0..6) |i| {
        const x = expected[i];
        const y = measured[(18 + i) * 3];
        sum_x += x;
        sum_y += y;
        sum_xy += x * y;
        sum_x2 += x * x;
        sum_y2 += y * y;
    }
    const num = n * sum_xy - sum_x * sum_y;
    const den = approxSqrt((n * sum_x2 - sum_x * sum_x) * (n * sum_y2 - sum_y * sum_y));
    if (den <= 0) return 0;
    const r = num / den;
    return r * r;
}
