const std = @import("std");
const gamut = @import("gamut");

export fn LLVMFuzzerTestOneInput(data: [*]const u8, size: usize) c_int {
    if (size == 0) return 0;

    const p = gamut.profile.openMemory(data, size) orelse return 0;
    defer gamut.profile.close(p);

    // Exercise core transform
    var input = [_]f32{ 0.5, 0.5, 0.5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
    var output: [16]f32 = undefined;
    _ = gamut.profile.gmtApply(p, &input, &output);

    // Exercise analysis modules
    const st = gamut.stats.compute(p);
    _ = st.pool_elements;

    const quality = gamut.profquality.analyze(p);
    _ = quality.overall_score;

    const insp = gamut.taginspect.inspect(p);
    _ = insp.anomalies;

    _ = gamut.stats.transformComplexity(p);
    _ = gamut.serialize.estimateSize(p);

    // Exercise color science on output
    const lab = gamut.colorspace.xyzToLab(.{ output[0], output[1], output[2] });
    const srgb = gamut.colorspace.labToSrgb(lab);
    _ = srgb;

    _ = gamut.deltae.deltaE2000(lab, .{ 50, 0, 0 });
    _ = gamut.colorspace.deltaE76(lab, .{ 50, 0, 0 });
    _ = gamut.colorspace.deltaE94(lab, .{ 50, 0, 0 });

    const adapted = gamut.colorspace.bradfordD50ToD65(.{ output[0], output[1], output[2] });
    _ = adapted;

    // Exercise encoding
    const enc16 = gamut.encoding.encodeLab16(lab);
    const dec16 = gamut.encoding.decodeLab16(enc16);
    _ = dec16;

    const enc8 = gamut.encoding.encodeLab8(lab);
    const dec8 = gamut.encoding.decodeLab8(enc8);
    _ = dec8;

    // Exercise hashing on input
    _ = gamut.digest.fnv1a32(data[0..size]);
    _ = gamut.digest.crc32(data[0..size]);
    _ = gamut.digest.profileFingerprint(data[0..size]);

    // Exercise adaptation
    const d50 = gamut.types.Xyz{ .x = 0.9642, .y = 1.0, .z = 0.8249 };
    const d65 = gamut.types.Xyz{ .x = 0.9505, .y = 1.0, .z = 1.089 };
    const brad = gamut.adapt.bradford(d50, d65);
    _ = gamut.adapt.apply(brad, .{ output[0], output[1], output[2] });

    // Exercise curve generation
    var curve_buf: [64]f32 = undefined;
    gamut.curvegen.gamma(&curve_buf, 2.2);
    gamut.curvegen.srgb(&curve_buf);
    gamut.curvegen.lstar(&curve_buf);
    _ = gamut.curvegen.isMonotonic(&curve_buf);
    _ = gamut.curvegen.fitGamma(&curve_buf);

    // Exercise intent
    var intent_lab = [3]f32{ lab[0], lab[1], lab[2] };
    gamut.intent.bpcAdjust(&intent_lab, 3.0, 5.0);

    // Exercise gamut mapping
    var map_lab = [3]f32{ lab[0], lab[1], lab[2] };
    const map_params = gamut.gammap.MapParams{};
    gamut.gammap.map(&map_lab, &map_params);

    // Exercise tone mapping
    _ = gamut.tonemap.reinhard(output[0]);
    _ = gamut.tonemap.acesApprox(output[0]);

    // Exercise transfer functions
    _ = gamut.transfer.srgbForward(output[0]);
    _ = gamut.transfer.bt709Forward(output[0]);

    // Exercise illuminant
    _ = gamut.illuminant.cctFromXyz(d50);
    _ = gamut.illuminant.closestIlluminant(d50);

    // Exercise color temperature
    const xy = gamut.colortemp.cctToXy(6500);
    _ = gamut.colortemp.xyToCct(xy[0], xy[1]);

    // Exercise matutil
    _ = gamut.matutil.determinant(brad);
    _ = gamut.matutil.frobeniusNorm(brad);

    // Exercise proofing
    var proof_lab = [3]f32{ lab[0], lab[1], lab[2] };
    const proof_params = gamut.proofing.ProofingParams{};
    gamut.proofing.proofRender(&proof_lab, &proof_params);

    // Exercise printer
    const cmyk = [4]f32{ 0.5, 0.3, 0.1, 0.2 };
    const inks = gamut.printer.InkSet{};
    _ = gamut.printer.neugebauer(cmyk, &inks);

    // Exercise halftone
    const screen = gamut.halftone.ScreenParams{};
    _ = gamut.halftone.dotArea(0.5, &screen);

    // Exercise iccio
    _ = gamut.iccio.validateGmtMagic(data[0..size]);

    // Exercise spectral
    const spd = gamut.spectral.d65Spd();
    _ = gamut.spectral.spdToXyz(&spd);

    // Exercise observer
    _ = gamut.observer.integrate(&gamut.observer.xbar_2deg, .deg2);

    // Exercise primaries
    const srgb_p = gamut.primaries.get(.srgb);
    _ = gamut.primaries.gamutArea(&srgb_p);

    // Exercise colorname
    _ = gamut.colorname.findClosest(lab);

    // Exercise munsell
    _ = gamut.munsell.valueToL(5.0);

    // Exercise perceptual
    _ = gamut.perceptual.computeAttributes(lab, 64.0);
    _ = gamut.perceptual.whitenessIndex(lab);

    // Exercise linsys
    _ = gamut.linsys.solve3x3(.{ 1, 0, 0, 0, 1, 0, 0, 0, 1 }, .{ 1, 2, 3 });

    // Exercise chromadapt
    const vc = gamut.chromadapt.ViewingConditions{};
    _ = gamut.chromadapt.forwardAdapt(.{ output[0], output[1], output[2] }, &vc);

    // Exercise whitebal
    _ = gamut.whitebal.estimateCct(.{ output[0], output[1], output[2] });

    // Exercise pixelbuf
    _ = gamut.pixelbuf.channelsForFormat(.rgb8);

    // Exercise iccv4
    _ = gamut.iccv4.parseV4Header(data[0..size]);

    // Exercise colorcheck
    _ = gamut.colorcheck.classic_24[0].lab;

    // Exercise profbuild
    const spec = gamut.profbuild.srgbSpec();
    _ = spec.gamma;

    // Exercise gradient
    _ = gamut.gradient.totalVariation1D(&curve_buf, 64);

    // Exercise uniformity (needs grid data)
    var uni_data: [27]f32 = [_]f32{50} ** 27;
    _ = gamut.uniformity.analyzeGrid(&uni_data, 3, 3);

    // Exercise gamutbd
    _ = gamut.gamutbd.contains(&gamut.gamutbd.GamutDesc{}, lab);

    // Exercise gamutvolume
    _ = gamut.gamutvolume.coveragePercent(gamut.gamutvolume.VolumeResult{}, gamut.gamutvolume.VolumeResult{ .volume = 1.0 });

    // Exercise profile_cmp
    _ = gamut.profile_cmp.isEquivalent(p, p);

    // Exercise clutops (safe even if no CLUT)
    _ = gamut.clutops.outOfRange(&gamut.types.Clut{});

    return 0;
}
