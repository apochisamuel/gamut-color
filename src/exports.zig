// exports.zig - C ABI exports for library utility functions
//
// Additional exported functions beyond the core parse/apply/close API.
// These make the color science and analysis modules reachable from
// external callers and fuzz harnesses.

const types = @import("types.zig");
const colorspace = @import("colorspace.zig");
const encoding = @import("encoding.zig");
const deltae = @import("deltae.zig");
const curvegen = @import("curvegen.zig");
const adapt = @import("adapt.zig");
const intent = @import("intent.zig");
const interp = @import("interp.zig");
const digest = @import("digest.zig");
const serialize = @import("serialize.zig");
const stats = @import("stats.zig");
const taginspect = @import("taginspect.zig");
const gammap = @import("gammap.zig");
const tonemap = @import("tonemap.zig");
const transfer = @import("transfer.zig");
const illuminant = @import("illuminant.zig");
const matutil = @import("matutil.zig");
const profquality = @import("profquality.zig");
const clutops = @import("clutops.zig");
const halftone = @import("halftone.zig");
const pixelbuf = @import("pixelbuf.zig");
const proofing = @import("proofing.zig");
const whitebal = @import("whitebal.zig");
const iccio = @import("iccio.zig");
const iccv4 = @import("iccv4.zig");
const spectral = @import("spectral.zig");
const profbuild = @import("profbuild.zig");
const chromadapt = @import("chromadapt.zig");
const linsys = @import("linsys.zig");
const colorname = @import("colorname.zig");
const uniformity = @import("uniformity.zig");
const gradient = @import("gradient.zig");
const colortemp = @import("colortemp.zig");
const colorcheck = @import("colorcheck.zig");
const munsell = @import("munsell.zig");
const perceptual = @import("perceptual.zig");
const printer = @import("printer.zig");
const gamutbd = @import("gamutbd.zig");
const gamutvolume = @import("gamutvolume.zig");
const observer = @import("observer.zig");
const primaries = @import("primaries.zig");
const profile_cmp = @import("profile_cmp.zig");
const elements = @import("elements.zig");
const linkcache = @import("linkcache.zig");

// Compute profile statistics after parsing
export fn gmt_profile_stats(p: *const types.Profile) u32 {
    const s = stats.compute(p);
    return s.pool_elements;
}

// Compute profile quality score
export fn gmt_quality_score(p: *const types.Profile) f32 {
    const report = profquality.analyze(p);
    return report.overall_score;
}

// Inspect tags
export fn gmt_tag_inspect(p: *const types.Profile) u32 {
    const result = taginspect.inspect(p);
    return result.anomalies;
}

// Compute transform complexity
export fn gmt_transform_complexity(p: *const types.Profile) f32 {
    return stats.transformComplexity(p);
}

// Estimate serialized size
export fn gmt_serialized_size(p: *const types.Profile) u32 {
    return @intCast(serialize.estimateSize(p));
}

// XYZ to Lab conversion
export fn gmt_xyz_to_lab(xyz: [*]const f32, lab: [*]f32) void {
    const result = colorspace.xyzToLab(.{ xyz[0], xyz[1], xyz[2] });
    lab[0] = result[0];
    lab[1] = result[1];
    lab[2] = result[2];
}

// Lab to sRGB conversion
export fn gmt_lab_to_srgb(lab_in: [*]const f32, rgb: [*]f32) void {
    const result = colorspace.labToSrgb(.{ lab_in[0], lab_in[1], lab_in[2] });
    rgb[0] = result[0];
    rgb[1] = result[1];
    rgb[2] = result[2];
}

// Delta E 2000
export fn gmt_delta_e2000(lab1: [*]const f32, lab2: [*]const f32) f32 {
    return deltae.deltaE2000(.{ lab1[0], lab1[1], lab1[2] }, .{ lab2[0], lab2[1], lab2[2] });
}

// Delta E 76
export fn gmt_delta_e76(lab1: [*]const f32, lab2: [*]const f32) f32 {
    return colorspace.deltaE76(.{ lab1[0], lab1[1], lab1[2] }, .{ lab2[0], lab2[1], lab2[2] });
}

// Encode Lab to 16-bit ICC PCS
export fn gmt_encode_lab16(lab_in: [*]const f32, out: [*]u16) void {
    const enc = encoding.encodeLab16(.{ lab_in[0], lab_in[1], lab_in[2] });
    out[0] = enc[0];
    out[1] = enc[1];
    out[2] = enc[2];
}

// Decode 16-bit ICC PCS to Lab
export fn gmt_decode_lab16(enc: [*]const u16, lab_out: [*]f32) void {
    const dec = encoding.decodeLab16(.{ enc[0], enc[1], enc[2] });
    lab_out[0] = dec[0];
    lab_out[1] = dec[1];
    lab_out[2] = dec[2];
}

// Generate gamma curve
export fn gmt_gen_gamma_curve(samples: [*]f32, count: u32, gamma_val: f32) void {
    curvegen.gamma(samples[0..count], gamma_val);
}

// Generate sRGB TRC
export fn gmt_gen_srgb_curve(samples: [*]f32, count: u32) void {
    curvegen.srgb(samples[0..count]);
}

// Compute curve RMS error
export fn gmt_curve_rms(a: [*]const f32, b: [*]const f32, count: u32) f32 {
    return curvegen.rmsError(a[0..count], b[0..count]);
}

// Fit gamma exponent
export fn gmt_fit_gamma(samples: [*]const f32, count: u32) f32 {
    return curvegen.fitGamma(samples[0..count]);
}

// Bradford D50 to D65
export fn gmt_bradford_d50_d65(xyz_in: [*]const f32, xyz_out: [*]f32) void {
    const m = adapt.d50ToD65();
    const result = adapt.apply(m, .{ xyz_in[0], xyz_in[1], xyz_in[2] });
    xyz_out[0] = result[0];
    xyz_out[1] = result[1];
    xyz_out[2] = result[2];
}

// Tone map (Reinhard)
export fn gmt_tonemap_reinhard(l: f32) f32 {
    return tonemap.reinhard(l);
}

// Tone map (ACES)
export fn gmt_tonemap_aces(l: f32) f32 {
    return tonemap.acesApprox(l);
}

// Transfer function forward
export fn gmt_transfer_srgb(x: f32) f32 {
    return transfer.srgbForward(x);
}

// FNV-1a hash
export fn gmt_fnv1a(data: [*]const u8, size: usize) u32 {
    return digest.fnv1a32(data[0..size]);
}

// CRC32
export fn gmt_crc32(data: [*]const u8, size: usize) u32 {
    return digest.crc32(data[0..size]);
}

// Profile fingerprint
export fn gmt_fingerprint(data: [*]const u8, size: usize) u64 {
    return digest.profileFingerprint(data[0..size]);
}

// CCT from XYZ
export fn gmt_cct(x: f32, y: f32, z: f32) f32 {
    return illuminant.cctFromXyz(.{ .x = x, .y = y, .z = z });
}

// Matrix determinant
export fn gmt_mat3_det(m: [*]const f32) f32 {
    return matutil.determinant(m[0..9].*);
}

// Matrix inverse
export fn gmt_mat3_inv(m_in: [*]const f32, m_out: [*]f32) c_int {
    const inv = matutil.inverse(m_in[0..9].*) orelse return -1;
    for (0..9) |i| m_out[i] = inv[i];
    return 0;
}

// Gamut map (chroma compress)
export fn gmt_gamut_map(lab: [*]f32, max_chroma: f32) void {
    var triplet = [3]f32{ lab[0], lab[1], lab[2] };
    var params = gammap.MapParams{ .dst_max_chroma = max_chroma };
    gammap.map(&triplet, &params);
    lab[0] = triplet[0];
    lab[1] = triplet[1];
    lab[2] = triplet[2];
}

// sRGB TRC forward
export fn gmt_srgb_gamma(x: f32) f32 {
    return colorspace.srgbGamma(x);
}

// Perceptual whiteness index
export fn gmt_whiteness(lab: [*]const f32) f32 {
    return perceptual.whitenessIndex(.{ lab[0], lab[1], lab[2] });
}

// Closest named color
export fn gmt_color_name(lab: [*]const f32) u32 {
    return @intCast(colorname.findClosest(.{ lab[0], lab[1], lab[2] }));
}

// Munsell value to L*
export fn gmt_munsell_v_to_l(v: f32) f32 {
    return munsell.valueToL(v);
}

// Halftone dot area
export fn gmt_dot_area(coverage: f32, dot_gain: f32) f32 {
    var params = halftone.ScreenParams{ .dot_gain = dot_gain };
    return halftone.dotArea(coverage, &params);
}

// Neugebauer CMYK to RGB
export fn gmt_neugebauer(cmyk: [*]const f32, rgb: [*]f32) void {
    var inks = printer.InkSet{};
    const result = printer.neugebauer(.{ cmyk[0], cmyk[1], cmyk[2], cmyk[3] }, &inks);
    rgb[0] = result[0];
    rgb[1] = result[1];
    rgb[2] = result[2];
}

// BPC adjust
export fn gmt_bpc_adjust(lab: [*]f32, src_bk: f32, dst_bk: f32) void {
    var triplet = [3]f32{ lab[0], lab[1], lab[2] };
    intent.bpcAdjust(&triplet, src_bk, dst_bk);
    lab[0] = triplet[0];
    lab[1] = triplet[1];
    lab[2] = triplet[2];
}

// Proof render
export fn gmt_proof_render(lab: [*]f32) void {
    var triplet = [3]f32{ lab[0], lab[1], lab[2] };
    var params = proofing.ProofingParams{};
    proofing.proofRender(&triplet, &params);
    lab[0] = triplet[0];
    lab[1] = triplet[1];
    lab[2] = triplet[2];
}

// Validate ICC magic
export fn gmt_validate_icc(data: [*]const u8, size: usize) c_int {
    if (size < 128) return 0;
    return if (iccio.validateGmtMagic(data[0..size])) 1 else 0;
}

// Solve 3x3 linear system
export fn gmt_solve3x3(a: [*]const f32, b: [*]const f32, x: [*]f32) c_int {
    const result = linsys.solve3x3(a[0..9].*, b[0..3].*) orelse return -1;
    x[0] = result[0]; x[1] = result[1]; x[2] = result[2];
    return 0;
}

// CCT to xy chromaticity
export fn gmt_cct_to_xy(cct: f32, x_out: *f32, y_out: *f32) void {
    const xy = colortemp.cctToXy(cct);
    x_out.* = xy[0];
    y_out.* = xy[1];
}

// SPD to XYZ
export fn gmt_spd_to_xyz(spd: [*]const f32, count: u32, xyz: [*]f32) void {
    var sd = spectral.SpectralData{};
    const n = if (count > spectral.N_BANDS) spectral.N_BANDS else @as(usize, count);
    for (0..n) |i| sd.values[i] = spd[i];
    sd.count = n;
    const result = spectral.spdToXyz(&sd);
    xyz[0] = result.x; xyz[1] = result.y; xyz[2] = result.z;
}

// Observer integration (2° or 10°)
export fn gmt_observer_integrate(spd: [*]const f32, count: u32, deg10: c_int, xyz: [*]f32) void {
    const obs = if (deg10 != 0) observer.ObserverType.deg10 else observer.ObserverType.deg2;
    const n = if (count > 41) @as(usize, 41) else @as(usize, count);
    const result = observer.integrate(spd[0..n], obs);
    xyz[0] = result.x; xyz[1] = result.y; xyz[2] = result.z;
}

// Gamut area for standard primaries
export fn gmt_gamut_area(space_id: u8) f32 {
    if (space_id > 10) return 0;
    const p = primaries.get(@enumFromInt(space_id));
    return primaries.gamutArea(&p);
}

// Unpack 8-bit pixels
export fn gmt_unpack8(src: [*]const u8, dst: [*]f32, channels: u8, count: u32) void {
    pixelbuf.unpack8(src[0 .. @as(usize, count) * channels], dst[0 .. @as(usize, count) * channels], channels, count);
}

// Pack 8-bit pixels
export fn gmt_pack8(src: [*]const f32, dst: [*]u8, channels: u8, count: u32) void {
    pixelbuf.pack8(src[0 .. @as(usize, count) * channels], dst[0 .. @as(usize, count) * channels], channels, count);
}

// White balance (gray world)
export fn gmt_gray_world(pixels: [*]const f32, count: u32, out: [*]f32) void {
    const result = whitebal.grayWorld(pixels[0 .. @as(usize, count) * 3], count);
    out[0] = result[0]; out[1] = result[1]; out[2] = result[2];
}

// Chromatic adaptation (CIECAM02 forward)
export fn gmt_chromadapt(xyz: [*]f32, la: f32) void {
    var vc = chromadapt.ViewingConditions{ .adapting_luminance = la };
    const result = chromadapt.forwardAdapt(.{ xyz[0], xyz[1], xyz[2] }, &vc);
    xyz[0] = result[0]; xyz[1] = result[1]; xyz[2] = result[2];
}

// Compute NPM from primaries
export fn gmt_compute_npm(rx: f32, ry: f32, gx: f32, gy: f32, bx: f32, by: f32, wx: f32, wy: f32, npm: [*]f32) void {
    const p = primaries.Primaries{ .rx = rx, .ry = ry, .gx = gx, .gy = gy, .bx = bx, .by = by, .wx = wx, .wy = wy };
    const result = primaries.computeNpm(&p);
    for (0..9) |i| npm[i] = result[i];
}

// Build a simple profile from spec
export fn gmt_build_profile(buf: [*]u8, buf_size: u32, gamma_val: f32) u32 {
    var spec = profbuild.ProfileSpec{};
    spec.gamma = gamma_val;
    return @intCast(profbuild.buildProfile(&spec, buf[0..buf_size]));
}

// Parse ICC v4 header
export fn gmt_parse_v4_header(data: [*]const u8, size: usize) c_int {
    if (size < 128) return -1;
    const h = iccv4.parseV4Header(data[0..size]) orelse return -1;
    _ = h;
    return 0;
}

// Color checker accuracy (returns mean DE)
export fn gmt_checker_accuracy(measured: [*]const f32, count: u32) f32 {
    const n = if (count > 24) @as(usize, 24) else @as(usize, count);
    const result = colorcheck.computeAccuracy(measured[0 .. n * 3], &colorcheck.classic_24, n);
    return result.mean_de;
}

// Gradient smoothness score
export fn gmt_gradient_smoothness(data: [*]const f32, count: u32) f32 {
    if (count < 3) return 0;
    return gradient.totalVariation1D(data[0..count], count);
}

// Uniformity analysis
export fn gmt_uniformity(measurements: [*]const f32, cols: u32, rows: u32) f32 {
    const total = @as(usize, cols) * rows * 3;
    if (total == 0) return 0;
    const result = uniformity.analyzeGrid(measurements[0..total], cols, rows);
    return result.uniformity_percent;
}

// Gamut volume estimation
export fn gmt_gamut_volume(points: [*]const f32, num_points: u32) f32 {
    const result = gamutvolume.monteCarloVolume(points[0 .. @as(usize, num_points) * 3], num_points, 1000);
    return result.volume;
}

// Profile comparison
export fn gmt_compare_profiles(a: *const types.Profile, b: *const types.Profile) f32 {
    const result = profile_cmp.compareTransforms(a, b, 5);
    return result.mean_de;
}

// Gamut boundary build
export fn gmt_build_gamut(grid: u8) f32 {
    const gd = gamutbd.buildGamut(grid);
    return gd.volume_estimate;
}
