// curves.zig - tone curve element decode and evaluation

const types = @import("types.zig");
const Reader = @import("reader.zig").Reader;
const mem = @import("alloc.zig");

pub fn decode(r: *Reader, src_offset: u32) ?*types.Element {
    const count = r.u16read();
    r.skip(2); // padding

    const el = mem.create(types.Element) orelse return null;
    const cv = mem.create(types.Curve) orelse {
        mem.freeFn(types.Element, el);
        return null;
    };

    if (count >= 2 and count <= 65536 and r.ok(count * 2)) {
        const samples = mem.alloc(f32, count) orelse {
            mem.freeFn(types.Curve, cv);
            mem.freeFn(types.Element, el);
            return null;
        };
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            samples[i] = r.u16norm();
        }
        cv.fn_type = 0;
        cv.count = count;
        cv.samples = samples.ptr;
    } else if (count == 1) {
        cv.fn_type = 1;
        cv.count = 0;
        cv.samples = null;
        cv.params[0] = r.u16norm() * 10.0;
    } else {
        cv.fn_type = 0;
        cv.count = 0;
        cv.samples = null;
    }

    el.kind = .curve;
    el.src_offset = src_offset;
    el.hold = 0;
    el.data = .{ .curve = cv };
    return el;
}

pub fn eval(cv: *const types.Curve, x: f32) f32 {
    if (cv.fn_type == 0) {
        if (cv.samples == null or cv.count == 0) return x;
        return sampleAt(cv.samples.?, cv.count, x);
    }
    // Parametric: simple gamma
    const g = cv.params[0];
    if (x <= 0.0) return 0.0;
    if (x >= 1.0) return 1.0;
    return approxPow(x, g);
}

fn sampleAt(samples: [*]f32, count: u32, x: f32) f32 {
    var xc = x;
    if (xc < 0.0) xc = 0.0;
    if (xc > 1.0) xc = 1.0;
    const pos = xc * @as(f32, @floatFromInt(count - 1));
    const lo: u32 = @intFromFloat(pos);
    const hi = if (lo + 1 < count) lo + 1 else count - 1;
    const frac = pos - @as(f32, @floatFromInt(lo));
    return samples[lo] * (1.0 - frac) + samples[hi] * frac;
}

fn approxPow(x: f32, g: f32) f32 {
    const u = 1.0 - x;
    const ln_x = -(u + u * u * 0.5 + u * u * u / 3.0);
    const t = g * ln_x;
    var sum: f32 = 1.0;
    var term: f32 = 1.0;
    var k: u32 = 1;
    while (k <= 12) : (k += 1) {
        term *= t / @as(f32, @floatFromInt(k));
        sum += term;
    }
    if (sum < 0.0) return 0.0;
    if (sum > 1.0) return 1.0;
    return sum;
}

pub fn freeCurve(cv: *types.Curve) void {
    if (cv.samples) |s| {
        const sl = s[0..cv.count];
        mem.freeSlice(f32, sl);
        cv.samples = null;
    }
    mem.freeFn(types.Curve, cv);
}
