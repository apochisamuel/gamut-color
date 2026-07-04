// colorname.zig - named color matching
//
// Match Lab values to a built-in database of named colors. Uses
// Delta E to find the perceptually closest name. Includes basic
// CSS/HTML color names and Munsell-inspired descriptors.

fn approxSqrt(x: f32) f32 {
    if (x <= 0) return 0;
    var y = x;
    var k: u32 = 0;
    while (k < 8) : (k += 1) y = (y + x / y) * 0.5;
    return y;
}

pub const NamedColor = struct {
    name: [16]u8 = [_]u8{0} ** 16,
    lab: [3]f32 = .{ 0, 0, 0 },
};

// Built-in color database (Lab values approximate)
pub const color_db = [_]NamedColor{
    .{ .name = "white\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00".*, .lab = .{ 100, 0, 0 } },
    .{ .name = "black\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00".*, .lab = .{ 0, 0, 0 } },
    .{ .name = "red\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00".*, .lab = .{ 53.2, 80.1, 67.2 } },
    .{ .name = "green\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00".*, .lab = .{ 87.7, -86.2, 83.2 } },
    .{ .name = "blue\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00".*, .lab = .{ 32.3, 79.2, -107.9 } },
    .{ .name = "yellow\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00".*, .lab = .{ 97.1, -21.6, 94.5 } },
    .{ .name = "cyan\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00".*, .lab = .{ 91.1, -48.1, -14.1 } },
    .{ .name = "magenta\x00\x00\x00\x00\x00\x00\x00\x00\x00".*, .lab = .{ 60.3, 98.3, -60.8 } },
    .{ .name = "orange\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00".*, .lab = .{ 74.9, 23.9, 78.9 } },
    .{ .name = "purple\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00".*, .lab = .{ 29.8, 58.9, -36.5 } },
    .{ .name = "pink\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00".*, .lab = .{ 83.6, 24.1, 3.3 } },
    .{ .name = "brown\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00".*, .lab = .{ 37.5, 23.4, 27.1 } },
    .{ .name = "gray\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00".*, .lab = .{ 53.6, 0, 0 } },
    .{ .name = "navy\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00".*, .lab = .{ 12.9, 47.2, -64.4 } },
    .{ .name = "teal\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00".*, .lab = .{ 48.3, -28.8, -8.5 } },
    .{ .name = "olive\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00".*, .lab = .{ 51.9, -12.9, 56.7 } },
    .{ .name = "maroon\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00".*, .lab = .{ 25.5, 48.1, 38.1 } },
    .{ .name = "lime\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00".*, .lab = .{ 87.7, -86.2, 83.2 } },
    .{ .name = "aqua\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00".*, .lab = .{ 91.1, -48.1, -14.1 } },
    .{ .name = "coral\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00".*, .lab = .{ 67.3, 45.4, 47.5 } },
    .{ .name = "gold\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00".*, .lab = .{ 86.9, -1.9, 87.1 } },
    .{ .name = "silver\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00".*, .lab = .{ 77.7, 0, 0 } },
    .{ .name = "ivory\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00".*, .lab = .{ 99.6, -1.6, 5.3 } },
    .{ .name = "tan\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00".*, .lab = .{ 74.9, 5.0, 24.4 } },
};

// Find closest named color by Delta E
pub fn findClosest(lab: [3]f32) usize {
    var best: usize = 0;
    var best_de: f32 = 1e30;
    for (color_db, 0..) |c, i| {
        const dl = lab[0] - c.lab[0];
        const da = lab[1] - c.lab[1];
        const db = lab[2] - c.lab[2];
        const de = approxSqrt(dl * dl + da * da + db * db);
        if (de < best_de) {
            best_de = de;
            best = i;
        }
    }
    return best;
}

// Get the Delta E to closest match
pub fn closestDistance(lab: [3]f32) f32 {
    var best_de: f32 = 1e30;
    for (color_db) |c| {
        const dl = lab[0] - c.lab[0];
        const da = lab[1] - c.lab[1];
        const db = lab[2] - c.lab[2];
        const de = approxSqrt(dl * dl + da * da + db * db);
        if (de < best_de) best_de = de;
    }
    return best_de;
}

// Generate a hue descriptor (warm, cool, neutral)
pub fn hueDescriptor(lab: [3]f32) u8 {
    const c = approxSqrt(lab[1] * lab[1] + lab[2] * lab[2]);
    if (c < 5) return 0; // neutral
    if (lab[1] > 0 and lab[2] > 0) return 1; // warm red-yellow
    if (lab[1] < 0 and lab[2] > 0) return 2; // warm green-yellow
    if (lab[1] < 0 and lab[2] < 0) return 3; // cool green-blue
    return 4; // cool blue-red
}

// Lightness category
pub fn lightnessCategory(l: f32) u8 {
    if (l < 20) return 0; // very dark
    if (l < 40) return 1; // dark
    if (l < 60) return 2; // medium
    if (l < 80) return 3; // light
    return 4; // very light
}

// Saturation category
pub fn saturationCategory(lab: [3]f32) u8 {
    const c = approxSqrt(lab[1] * lab[1] + lab[2] * lab[2]);
    if (c < 10) return 0; // neutral
    if (c < 30) return 1; // muted
    if (c < 60) return 2; // moderate
    if (c < 90) return 3; // vivid
    return 4; // highly saturated
}

// Batch find closest colors
pub fn batchFindClosest(labs: []const f32, indices: []usize, count: usize) void {
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const lab = [3]f32{ labs[i * 3], labs[i * 3 + 1], labs[i * 3 + 2] };
        indices[i] = findClosest(lab);
    }
}
