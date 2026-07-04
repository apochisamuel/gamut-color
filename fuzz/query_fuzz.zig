const std = @import("std");
const gamut = @import("gamut");

export fn LLVMFuzzerTestOneInput(data: [*]const u8, size: usize) c_int {
    if (size == 0) return 0;

    const p = gamut.profile.openMemory(data, size) orelse return 0;
    defer gamut.profile.close(p);

    // Query colorant names
    _ = gamut.profile.colorantIndex(p, "red");
    _ = gamut.profile.colorantIndex(p, "green");
    _ = gamut.profile.colorantIndex(p, "blue");
    _ = gamut.profile.colorantIndex(p, "cyan");

    // Apply transform
    var input = [_]f32{ 0.5, 0.5, 0.5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
    var output: [16]f32 = undefined;
    _ = gamut.profile.gmtApply(p, &input, &output);

    // Analysis
    _ = gamut.stats.compute(p);
    _ = gamut.profquality.analyze(p);
    _ = gamut.taginspect.inspect(p);

    // Color science
    const lab = gamut.colorspace.xyzToLab(.{ output[0], output[1], output[2] });
    var map_lab = [3]f32{ lab[0], lab[1], lab[2] };
    const params = gamut.gammap.MapParams{};
    gamut.gammap.map(&map_lab, &params);

    var proof_lab = [3]f32{ lab[0], lab[1], lab[2] };
    const proof_params = gamut.proofing.ProofingParams{};
    gamut.proofing.proofRender(&proof_lab, &proof_params);

    _ = gamut.colorname.findClosest(lab);
    _ = gamut.perceptual.computeAttributes(lab, 64.0);

    _ = gamut.digest.fnv1a32(data[0..size]);

    return 0;
}
