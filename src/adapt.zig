// adapt.zig - chromatic adaptation transforms
//
// Compute adaptation matrices for transforming between illuminants.
// Three methods: von Kries, Bradford (ICC standard), and CAT02.

const types = @import("types.zig");

const Mat3 = [9]f32;

fn matMul(a: Mat3, b: Mat3) Mat3 {
    var out: Mat3 = undefined;
    for (0..3) |r| {
        for (0..3) |c| {
            out[r * 3 + c] = a[r * 3 + 0] * b[0 * 3 + c] +
                a[r * 3 + 1] * b[1 * 3 + c] +
                a[r * 3 + 2] * b[2 * 3 + c];
        }
    }
    return out;
}

fn matApply(m: Mat3, v: [3]f32) [3]f32 {
    return .{
        m[0] * v[0] + m[1] * v[1] + m[2] * v[2],
        m[3] * v[0] + m[4] * v[1] + m[5] * v[2],
        m[6] * v[0] + m[7] * v[1] + m[8] * v[2],
    };
}

fn matIdent() Mat3 {
    return .{ 1, 0, 0, 0, 1, 0, 0, 0, 1 };
}

fn matInv(m: Mat3) ?Mat3 {
    const det = m[0] * (m[4] * m[8] - m[5] * m[7]) -
        m[1] * (m[3] * m[8] - m[5] * m[6]) +
        m[2] * (m[3] * m[7] - m[4] * m[6]);
    if (det == 0) return null;
    const id = 1.0 / det;
    return .{
        (m[4] * m[8] - m[5] * m[7]) * id,
        -(m[1] * m[8] - m[2] * m[7]) * id,
        (m[1] * m[5] - m[2] * m[4]) * id,
        -(m[3] * m[8] - m[5] * m[6]) * id,
        (m[0] * m[8] - m[2] * m[6]) * id,
        -(m[0] * m[5] - m[2] * m[3]) * id,
        (m[3] * m[7] - m[4] * m[6]) * id,
        -(m[0] * m[7] - m[1] * m[6]) * id,
        (m[0] * m[4] - m[1] * m[3]) * id,
    };
}

fn buildAdapt(cone: Mat3, cone_inv: Mat3, src: types.Xyz, dst: types.Xyz) Mat3 {
    const sv = [3]f32{ src.x, src.y, src.z };
    const dv = [3]f32{ dst.x, dst.y, dst.z };
    const src_c = matApply(cone, sv);
    const dst_c = matApply(cone, dv);

    var scale = matIdent();
    for (0..3) |i| {
        scale[i * 4] = if (src_c[i] != 0) dst_c[i] / src_c[i] else 1.0;
    }

    const tmp = matMul(scale, cone);
    return matMul(cone_inv, tmp);
}

// XYZ scaling adaptation
pub fn xyzScaling(src: types.Xyz, dst: types.Xyz) Mat3 {
    var m = matIdent();
    m[0] = if (src.x != 0) dst.x / src.x else 1;
    m[4] = if (src.y != 0) dst.y / src.y else 1;
    m[8] = if (src.z != 0) dst.z / src.z else 1;
    return m;
}

// Von Kries adaptation (Hunt-Pointer-Estevez cone fundamentals)
pub fn vonKries(src: types.Xyz, dst: types.Xyz) Mat3 {
    const hpe = Mat3{
        0.38971, 0.68898, -0.07868,
        -0.22981, 1.18340, 0.04641,
        0.00000, 0.00000, 1.00000,
    };
    const hpe_inv = Mat3{
        1.91020, -1.11212, 0.20191,
        0.37095, 0.62905, 0.00000,
        0.00000, 0.00000, 1.00000,
    };
    return buildAdapt(hpe, hpe_inv, src, dst);
}

// Bradford adaptation (ICC standard)
pub fn bradford(src: types.Xyz, dst: types.Xyz) Mat3 {
    const brad = Mat3{
        0.8951, 0.2664, -0.1614,
        -0.7502, 1.7135, 0.0367,
        0.0389, -0.0685, 1.0296,
    };
    const brad_inv = Mat3{
        0.9870, -0.1471, 0.1600,
        0.4323, 0.5184, 0.0493,
        -0.0085, 0.0400, 0.9685,
    };
    return buildAdapt(brad, brad_inv, src, dst);
}

// CAT02 adaptation (CIECAM02)
pub fn cat02(src: types.Xyz, dst: types.Xyz) Mat3 {
    const c = Mat3{
        0.7328, 0.4296, -0.1624,
        -0.7036, 1.6975, 0.0061,
        0.0030, 0.0136, 0.9834,
    };
    const c_inv = matInv(c) orelse return matIdent();
    return buildAdapt(c, c_inv, src, dst);
}

// Apply adaptation
pub fn apply(m: Mat3, xyz: [3]f32) [3]f32 {
    return matApply(m, xyz);
}

// D50 → D65 Bradford
pub fn d50ToD65() Mat3 {
    const d50 = types.Xyz{ .x = 0.9642, .y = 1.0, .z = 0.8249 };
    const d65 = types.Xyz{ .x = 0.9505, .y = 1.0, .z = 1.0890 };
    return bradford(d50, d65);
}

// D65 → D50 Bradford
pub fn d65ToD50() Mat3 {
    const d50 = types.Xyz{ .x = 0.9642, .y = 1.0, .z = 0.8249 };
    const d65 = types.Xyz{ .x = 0.9505, .y = 1.0, .z = 1.0890 };
    return bradford(d65, d50);
}

// Compare two matrices within tolerance
pub fn matricesEqual(a: Mat3, b: Mat3, eps: f32) bool {
    for (a, b) |va, vb| {
        var d = va - vb;
        if (d < 0) d = -d;
        if (d > eps) return false;
    }
    return true;
}
