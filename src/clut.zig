// clut.zig - multi-dimensional color lookup table decode

const types = @import("types.zig");
const Reader = @import("reader.zig").Reader;
const mem = @import("alloc.zig");

pub fn decode(r: *Reader, src_offset: u32) ?*types.Element {
    const in_ch = r.u8read();
    const out_ch = r.u8read();
    r.skip(2);

    if (in_ch == 0 or in_ch > types.MAX_CHANNELS or
        out_ch == 0 or out_ch > types.MAX_CHANNELS)
        return null;

    const el = mem.create(types.Element) orelse return null;
    const cl = mem.create(types.Clut) orelse {
        mem.freeFn(types.Element, el);
        return null;
    };

    cl.in_ch = in_ch;
    cl.out_ch = out_ch;

    var points: u32 = 1;
    var d: u8 = 0;
    while (d < in_ch) : (d += 1) {
        const g = r.u8read();
        cl.grid[d] = if (g < 2) 2 else g;
        points *= cl.grid[d];
        if (points > 262144) {
            mem.freeFn(types.Clut, cl);
            mem.freeFn(types.Element, el);
            return null;
        }
    }
    cl.point_count = points;

    const total = @as(usize, points) * out_ch;
    if (total == 0 or !r.ok(total * 2)) {
        mem.freeFn(types.Clut, cl);
        mem.freeFn(types.Element, el);
        return null;
    }

    const table = mem.alloc(f32, total) orelse {
        mem.freeFn(types.Clut, cl);
        mem.freeFn(types.Element, el);
        return null;
    };

    var i: usize = 0;
    while (i < total) : (i += 1) {
        table[i] = r.u16norm();
    }
    cl.table = table.ptr;

    el.kind = .clut;
    el.src_offset = src_offset;
    el.hold = 0;
    el.data = .{ .clut = cl };
    return el;
}
