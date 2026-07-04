const std = @import("std");
const gamut = @import("gamut");

export fn LLVMFuzzerTestOneInput(data: [*]const u8, size: usize) c_int {
    if (size == 0) return 0;

    const p = gamut.profile.openMemory(data, size) orelse return 0;
    defer gamut.profile.close(p);

    // Multi-point evaluation
    var k: u8 = 0;
    while (k < 5) : (k += 1) {
        const v: f32 = @as(f32, @floatFromInt(k)) / 4.0;
        var input = [_]f32{ v, v, v, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
        var output: [16]f32 = undefined;
        _ = gamut.profile.gmtApply(p, &input, &output);

        const lab = gamut.colorspace.xyzToLab(.{ output[0], output[1], output[2] });
        _ = gamut.deltae.deltaE2000(lab, .{ 50, 0, 0 });
        _ = gamut.colorspace.deltaE76(lab, .{ 50, 0, 0 });
    }

    _ = gamut.taginspect.inspect(p);
    _ = gamut.stats.transformComplexity(p);
    _ = gamut.digest.fnv1a32(data[0..size]);
    _ = gamut.digest.crc32(data[0..size]);

    return 0;
}
