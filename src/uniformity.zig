// uniformity.zig - display and print uniformity metrics
//
// Analyze spatial uniformity of color measurements across a display
// or print surface. Computes JNCD (Just Noticeable Color Difference)
// metrics, zone-based analysis, and corner-to-center ratios.

fn approxSqrt(x: f32) f32 {
    if (x <= 0) return 0;
    var y = x;
    var k: u32 = 0;
    while (k < 8) : (k += 1) y = (y + x / y) * 0.5;
    return y;
}

pub const UniformityResult = struct {
    mean_de: f32 = 0,
    max_de: f32 = 0,
    std_dev: f32 = 0,
    corner_to_center: f32 = 0,
    edge_to_center: f32 = 0,
    jncd_count: u32 = 0,
    total_measurements: u32 = 0,
    uniformity_percent: f32 = 100,
};

// Compute Delta E between two Lab values
fn deltaE(a: [3]f32, b: [3]f32) f32 {
    const dl = a[0] - b[0];
    const da = a[1] - b[1];
    const db = a[2] - b[2];
    return approxSqrt(dl * dl + da * da + db * db);
}

// Analyze uniformity of a grid of Lab measurements
pub fn analyzeGrid(measurements: []const f32, cols: u32, rows: u32) UniformityResult {
    var result = UniformityResult{};
    const total = cols * rows;
    if (total < 2) return result;
    result.total_measurements = total;

    // Compute center value
    const cx = cols / 2;
    const cy = rows / 2;
    const center_idx = cy * cols + cx;
    const center = [3]f32{
        measurements[center_idx * 3],
        measurements[center_idx * 3 + 1],
        measurements[center_idx * 3 + 2],
    };

    // Compute all Delta E values relative to center
    var sum_de: f32 = 0;
    var sum_de2: f32 = 0;
    var max_de: f32 = 0;

    var r: u32 = 0;
    while (r < rows) : (r += 1) {
        var c: u32 = 0;
        while (c < cols) : (c += 1) {
            const idx = r * cols + c;
            const lab = [3]f32{
                measurements[idx * 3],
                measurements[idx * 3 + 1],
                measurements[idx * 3 + 2],
            };
            const de = deltaE(lab, center);
            sum_de += de;
            sum_de2 += de * de;
            if (de > max_de) max_de = de;
            if (de > 3.0) result.jncd_count += 1; // visible difference
        }
    }

    result.mean_de = sum_de / @as(f32, @floatFromInt(total));
    result.max_de = max_de;

    // Standard deviation
    const mean2 = result.mean_de * result.mean_de;
    const var_de = sum_de2 / @as(f32, @floatFromInt(total)) - mean2;
    result.std_dev = if (var_de > 0) approxSqrt(var_de) else 0;

    // Corner-to-center ratio
    const corners = [4][2]u32{
        .{ 0, 0 },
        .{ cols - 1, 0 },
        .{ 0, rows - 1 },
        .{ cols - 1, rows - 1 },
    };
    var corner_de: f32 = 0;
    for (corners) |corner| {
        const idx = corner[1] * cols + corner[0];
        const lab = [3]f32{
            measurements[idx * 3],
            measurements[idx * 3 + 1],
            measurements[idx * 3 + 2],
        };
        corner_de += deltaE(lab, center);
    }
    result.corner_to_center = corner_de / 4.0;

    // Edge midpoints
    var edge_de: f32 = 0;
    const edge_pts = [4][2]u32{
        .{ cx, 0 },
        .{ cx, rows - 1 },
        .{ 0, cy },
        .{ cols - 1, cy },
    };
    for (edge_pts) |ep| {
        const idx = ep[1] * cols + ep[0];
        const lab = [3]f32{
            measurements[idx * 3],
            measurements[idx * 3 + 1],
            measurements[idx * 3 + 2],
        };
        edge_de += deltaE(lab, center);
    }
    result.edge_to_center = edge_de / 4.0;

    // Uniformity percentage
    result.uniformity_percent = 100.0 * (1.0 - @as(f32, @floatFromInt(result.jncd_count)) / @as(f32, @floatFromInt(total)));

    return result;
}

// Compute per-zone uniformity (divide into 5 zones)
pub fn zoneAnalysis(measurements: []const f32, cols: u32, rows: u32) [5]f32 {
    var zone_sums: [5]f32 = .{ 0, 0, 0, 0, 0 };
    var zone_counts: [5]u32 = .{ 0, 0, 0, 0, 0 };

    const cx = cols / 2;
    const cy = rows / 2;

    var r: u32 = 0;
    while (r < rows) : (r += 1) {
        var c: u32 = 0;
        while (c < cols) : (c += 1) {
            const idx = (r * cols + c) * 3;
            const lum = measurements[idx]; // Use L* as luminance proxy

            // Determine zone (0=center, 1-4=corners)
            const zone: usize = if (r < cy and c < cx) 1 else if (r < cy and c >= cx) 2 else if (r >= cy and c < cx) 3 else if (r >= cy and c >= cx) 4 else 0;

            // Override: center region
            const dr = if (r > cy) r - cy else cy - r;
            const dc = if (c > cx) c - cx else cx - c;
            const in_center = dr < rows / 4 and dc < cols / 4;

            const z = if (in_center) @as(usize, 0) else zone;
            zone_sums[z] += lum;
            zone_counts[z] += 1;
        }
    }

    var means: [5]f32 = .{ 0, 0, 0, 0, 0 };
    for (0..5) |i| {
        if (zone_counts[i] > 0) {
            means[i] = zone_sums[i] / @as(f32, @floatFromInt(zone_counts[i]));
        }
    }
    return means;
}
