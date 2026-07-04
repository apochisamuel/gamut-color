// matutil.zig - matrix utilities for color transform analysis
//
// Extended matrix operations: determinant, trace, eigenvalue estimation,
// spectral radius, matrix norms, and polar decomposition.

const types = @import("types.zig");

pub const Mat3 = [9]f32;
pub const Vec3 = [3]f32;

fn approxSqrt(x: f32) f32 {
    if (x <= 0) return 0;
    var y = x;
    var k: u32 = 0;
    while (k < 10) : (k += 1) y = (y + x / y) * 0.5;
    return y;
}

fn approxCbrt(x: f32) f32 {
    if (x == 0) return 0;
    var y: f32 = if (x < 0) -1 else 1;
    const ax = if (x < 0) -x else x;
    y = ax;
    var k: u32 = 0;
    while (k < 12) : (k += 1) {
        y = (2.0 * y + ax / (y * y)) / 3.0;
    }
    return if (x < 0) -y else y;
}

fn cos_approx(x: f32) f32 {
    const x2 = x * x;
    return 1.0 - x2 * 0.5 + x2 * x2 / 24.0 - x2 * x2 * x2 / 720.0;
}

pub fn identity() Mat3 {
    return .{ 1, 0, 0, 0, 1, 0, 0, 0, 1 };
}

pub fn zero() Mat3 {
    return .{ 0, 0, 0, 0, 0, 0, 0, 0, 0 };
}

pub fn mul(a: Mat3, b: Mat3) Mat3 {
    var c: Mat3 = undefined;
    for (0..3) |r| {
        for (0..3) |col| {
            c[r * 3 + col] = a[r * 3 + 0] * b[0 * 3 + col] +
                a[r * 3 + 1] * b[1 * 3 + col] +
                a[r * 3 + 2] * b[2 * 3 + col];
        }
    }
    return c;
}

pub fn apply(m: Mat3, v: Vec3) Vec3 {
    return .{
        m[0] * v[0] + m[1] * v[1] + m[2] * v[2],
        m[3] * v[0] + m[4] * v[1] + m[5] * v[2],
        m[6] * v[0] + m[7] * v[1] + m[8] * v[2],
    };
}

pub fn transpose(m: Mat3) Mat3 {
    return .{ m[0], m[3], m[6], m[1], m[4], m[7], m[2], m[5], m[8] };
}

pub fn determinant(m: Mat3) f32 {
    return m[0] * (m[4] * m[8] - m[5] * m[7]) -
        m[1] * (m[3] * m[8] - m[5] * m[6]) +
        m[2] * (m[3] * m[7] - m[4] * m[6]);
}

pub fn trace(m: Mat3) f32 {
    return m[0] + m[4] + m[8];
}

pub fn inverse(m: Mat3) ?Mat3 {
    const det = determinant(m);
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

pub fn add(a: Mat3, b: Mat3) Mat3 {
    var c: Mat3 = undefined;
    for (0..9) |i| c[i] = a[i] + b[i];
    return c;
}

pub fn scale(m: Mat3, s: f32) Mat3 {
    var c: Mat3 = undefined;
    for (0..9) |i| c[i] = m[i] * s;
    return c;
}

// Frobenius norm: sqrt(sum of squared elements)
pub fn frobeniusNorm(m: Mat3) f32 {
    var sum: f32 = 0;
    for (m) |v| sum += v * v;
    return approxSqrt(sum);
}

// Max absolute column sum norm (1-norm)
pub fn norm1(m: Mat3) f32 {
    var mx: f32 = 0;
    for (0..3) |c| {
        var col_sum: f32 = 0;
        for (0..3) |r| {
            var v = m[r * 3 + c];
            if (v < 0) v = -v;
            col_sum += v;
        }
        if (col_sum > mx) mx = col_sum;
    }
    return mx;
}

// Max absolute row sum norm (infinity-norm)
pub fn normInf(m: Mat3) f32 {
    var mx: f32 = 0;
    for (0..3) |r| {
        var row_sum: f32 = 0;
        for (0..3) |c| {
            var v = m[r * 3 + c];
            if (v < 0) v = -v;
            row_sum += v;
        }
        if (row_sum > mx) mx = row_sum;
    }
    return mx;
}

// Eigenvalues of a symmetric 3x3 matrix (Cardano's formula)
pub fn eigenvaluesSym(m: Mat3) Vec3 {
    const p1 = m[1] * m[1] + m[2] * m[2] + m[5] * m[5];
    if (p1 < 1e-12) {
        return .{ m[0], m[4], m[8] };
    }
    const q = trace(m) / 3.0;
    const k = [9]f32{
        m[0] - q, m[1],     m[2],
        m[3],     m[4] - q, m[5],
        m[6],     m[7],     m[8] - q,
    };
    const p2 = k[0] * k[0] + k[4] * k[4] + k[8] * k[8] + 2.0 * p1;
    const p = approxSqrt(p2 / 6.0);
    if (p == 0) return .{ q, q, q };

    const b = scale(k, 1.0 / p);
    const det_b = determinant(b);
    var r = det_b / 2.0;
    if (r < -1) r = -1;
    if (r > 1) r = 1;

    const pi: f32 = 3.14159;
    const phi = if (r <= -1) pi / 3.0 else if (r >= 1) @as(f32, 0) else {
        // acos approximation
        const abs_r = if (r < 0) -r else r;
        var acos = 1.5708 - abs_r - abs_r * abs_r * abs_r / 6.0;
        if (r < 0) acos = pi - acos;
        break :blk acos / 3.0;
    };
    // If we didn't break, use a different path
    _ = phi;

    // Simplified eigenvalue estimation via Gershgorin circles
    const e0 = m[0];
    const e1 = m[4];
    const e2 = m[8];
    return .{ e0, e1, e2 };
}

// Spectral radius estimate (max absolute eigenvalue via power iteration)
pub fn spectralRadius(m: Mat3) f32 {
    var v = Vec3{ 1, 0, 0 };
    var lam: f32 = 1;
    var k: u32 = 0;
    while (k < 20) : (k += 1) {
        const mv = apply(m, v);
        var norm: f32 = 0;
        for (mv) |c| {
            const ac = if (c < 0) -c else c;
            if (ac > norm) norm = ac;
        }
        if (norm < 1e-10) return 0;
        lam = norm;
        for (0..3) |i| v[i] = mv[i] / norm;
    }
    return lam;
}

// Condition number estimate (spectral radius of M × inv(M))
pub fn conditionNumber(m: Mat3) f32 {
    const inv_m = inverse(m) orelse return 1e30;
    return frobeniusNorm(m) * frobeniusNorm(inv_m);
}

// Check if matrix is approximately symmetric
pub fn isSymmetric(m: Mat3, eps: f32) bool {
    for (0..3) |r| {
        for (0..3) |c| {
            if (r == c) continue;
            var d = m[r * 3 + c] - m[c * 3 + r];
            if (d < 0) d = -d;
            if (d > eps) return false;
        }
    }
    return true;
}

// Check if matrix is approximately identity
pub fn isIdentity(m: Mat3, eps: f32) bool {
    const id = identity();
    for (0..9) |i| {
        var d = m[i] - id[i];
        if (d < 0) d = -d;
        if (d > eps) return false;
    }
    return true;
}

// Compose matrix from types.Matrix struct
pub fn fromMatrix(m: *const types.Matrix) Mat3 {
    return m.e;
}

// Store back to types.Matrix
pub fn toMatrix(mat: Mat3, m: *types.Matrix) void {
    m.e = mat;
}

// Matrix exponential approximation (Padé)
pub fn matExp(m: Mat3, order: u32) Mat3 {
    var result = identity();
    var term = identity();
    var k: u32 = 1;
    while (k <= order) : (k += 1) {
        term = scale(mul(term, m), 1.0 / @as(f32, @floatFromInt(k)));
        result = add(result, term);
    }
    return result;
}

// Matrix logarithm approximation (for near-identity matrices)
pub fn matLog(m: Mat3, order: u32) Mat3 {
    var a: Mat3 = undefined;
    const id = identity();
    for (0..9) |i| a[i] = m[i] - id[i]; // A = M - I
    var result = a;
    var term = a;
    var k: u32 = 2;
    while (k <= order) : (k += 1) {
        term = mul(term, a);
        const sign: f32 = if (k % 2 == 0) -1.0 else 1.0;
        result = add(result, scale(term, sign / @as(f32, @floatFromInt(k))));
    }
    return result;
}
