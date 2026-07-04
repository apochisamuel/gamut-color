// linsys.zig - small linear system solver
//
// Solve Ax=b for 2x2, 3x3, and 4x4 systems using Cramer's rule
// and Gaussian elimination. Used for matrix fitting, white point
// computation, and profile construction.

pub fn solve2x2(a: [4]f32, b: [2]f32) ?[2]f32 {
    const det = a[0] * a[3] - a[1] * a[2];
    if (det == 0) return null;
    const id = 1.0 / det;
    return .{
        (a[3] * b[0] - a[1] * b[1]) * id,
        (a[0] * b[1] - a[2] * b[0]) * id,
    };
}

pub fn solve3x3(a: [9]f32, b: [3]f32) ?[3]f32 {
    const det = a[0] * (a[4] * a[8] - a[5] * a[7]) -
        a[1] * (a[3] * a[8] - a[5] * a[6]) +
        a[2] * (a[3] * a[7] - a[4] * a[6]);
    if (det == 0) return null;
    const id = 1.0 / det;

    return .{
        ((a[4] * a[8] - a[5] * a[7]) * b[0] +
            (a[2] * a[7] - a[1] * a[8]) * b[1] +
            (a[1] * a[5] - a[2] * a[4]) * b[2]) * id,
        ((a[5] * a[6] - a[3] * a[8]) * b[0] +
            (a[0] * a[8] - a[2] * a[6]) * b[1] +
            (a[2] * a[3] - a[0] * a[5]) * b[2]) * id,
        ((a[3] * a[7] - a[4] * a[6]) * b[0] +
            (a[1] * a[6] - a[0] * a[7]) * b[1] +
            (a[0] * a[4] - a[1] * a[3]) * b[2]) * id,
    };
}

// Gaussian elimination for 4x4
pub fn solve4x4(a_in: [16]f32, b_in: [4]f32) ?[4]f32 {
    var a: [4][5]f32 = undefined;
    for (0..4) |r| {
        for (0..4) |c| a[r][c] = a_in[r * 4 + c];
        a[r][4] = b_in[r];
    }

    // Forward elimination
    for (0..4) |col| {
        // Find pivot
        var max_row = col;
        var max_val = if (a[col][col] < 0) -a[col][col] else a[col][col];
        for (col + 1..4) |r| {
            const v = if (a[r][col] < 0) -a[r][col] else a[r][col];
            if (v > max_val) {
                max_val = v;
                max_row = r;
            }
        }
        if (max_val < 1e-10) return null;

        // Swap rows
        if (max_row != col) {
            const tmp = a[col];
            a[col] = a[max_row];
            a[max_row] = tmp;
        }

        // Eliminate
        for (col + 1..4) |r| {
            const factor = a[r][col] / a[col][col];
            for (col..5) |c| {
                a[r][c] -= factor * a[col][c];
            }
        }
    }

    // Back substitution
    var x: [4]f32 = undefined;
    var row: i32 = 3;
    while (row >= 0) : (row -= 1) {
        const r: usize = @intCast(row);
        x[r] = a[r][4];
        for (r + 1..4) |c| {
            x[r] -= a[r][c] * x[c];
        }
        if (a[r][r] == 0) return null;
        x[r] /= a[r][r];
    }

    return x;
}

// Least squares fit for overdetermined 3x3 system
pub fn leastSquares3(samples: []const [6]f32, count: usize) ?[9]f32 {
    if (count < 3) return null;

    // Build AᵀA and Aᵀb for each output channel
    var result: [9]f32 = undefined;

    for (0..3) |out_ch| {
        var ata: [9]f32 = [_]f32{0} ** 9;
        var atb: [3]f32 = .{ 0, 0, 0 };

        for (0..count) |i| {
            const inp = [3]f32{ samples[i][0], samples[i][1], samples[i][2] };
            const target = samples[i][3 + out_ch];

            for (0..3) |r| {
                atb[r] += inp[r] * target;
                for (0..3) |c| {
                    ata[r * 3 + c] += inp[r] * inp[c];
                }
            }
        }

        const x = solve3x3(ata, atb) orelse return null;
        result[out_ch * 3] = x[0];
        result[out_ch * 3 + 1] = x[1];
        result[out_ch * 3 + 2] = x[2];
    }

    return result;
}

// Compute matrix condition number (ratio of max/min singular values, approximated)
fn approxSqrt(x: f32) f32 {
    if (x <= 0) return 0;
    var y = x;
    var k: u32 = 0;
    while (k < 8) : (k += 1) y = (y + x / y) * 0.5;
    return y;
}

pub fn condition3x3(a: [9]f32) f32 {
    // Frobenius norm of A
    var norm_a: f32 = 0;
    for (a) |v| norm_a += v * v;
    norm_a = approxSqrt(norm_a);

    // Frobenius norm of inverse
    const det = a[0] * (a[4] * a[8] - a[5] * a[7]) -
        a[1] * (a[3] * a[8] - a[5] * a[6]) +
        a[2] * (a[3] * a[7] - a[4] * a[6]);
    if (det == 0) return 1e10;
    const id = 1.0 / det;

    var inv: [9]f32 = .{
        (a[4] * a[8] - a[5] * a[7]) * id,
        -(a[1] * a[8] - a[2] * a[7]) * id,
        (a[1] * a[5] - a[2] * a[4]) * id,
        -(a[3] * a[8] - a[5] * a[6]) * id,
        (a[0] * a[8] - a[2] * a[6]) * id,
        -(a[0] * a[5] - a[2] * a[3]) * id,
        (a[3] * a[7] - a[4] * a[6]) * id,
        -(a[0] * a[7] - a[1] * a[6]) * id,
        (a[0] * a[4] - a[1] * a[3]) * id,
    };
    _ = &inv;

    var norm_inv: f32 = 0;
    for (inv) |v| norm_inv += v * v;
    norm_inv = approxSqrt(norm_inv);

    return norm_a * norm_inv;
}

// Matrix-vector multiply 3x3
pub fn matvec3(m: [9]f32, v: [3]f32) [3]f32 {
    return .{
        m[0] * v[0] + m[1] * v[1] + m[2] * v[2],
        m[3] * v[0] + m[4] * v[1] + m[5] * v[2],
        m[6] * v[0] + m[7] * v[1] + m[8] * v[2],
    };
}

// Matrix multiply 3x3
pub fn matmul3(a: [9]f32, b: [9]f32) [9]f32 {
    var c: [9]f32 = undefined;
    for (0..3) |r| {
        for (0..3) |col| {
            c[r * 3 + col] = a[r * 3] * b[col] + a[r * 3 + 1] * b[3 + col] + a[r * 3 + 2] * b[6 + col];
        }
    }
    return c;
}
