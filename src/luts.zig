// luts.zig - AtoB/BtoA lookup element decode
//
// A LUT element references sub-elements (curves, CLUT, matrix) by their
// file offset. The pool interns them so multiple LUTs can share elements.

const types = @import("types.zig");
const Reader = @import("reader.zig").Reader;
const mem = @import("alloc.zig");
const elements = @import("elements.zig");

pub fn decode(p: *types.Profile, r: *Reader, src_offset: u32, size: u32) ?*types.Element {
    const in_ch = r.u8read();
    const out_ch = r.u8read();
    r.skip(2);

    if (in_ch == 0 or in_ch > types.MAX_CHANNELS or
        out_ch == 0 or out_ch > types.MAX_CHANNELS)
        return null;

    const el = mem.create(types.Element) orelse return null;
    const lt = mem.create(types.Lut) orelse {
        mem.freeFn(types.Element, el);
        return null;
    };
    lt.in_ch = in_ch;
    lt.out_ch = out_ch;
    lt.pre_curve = -1;
    lt.clut = -1;
    lt.post_curve = -1;
    lt.matrix = -1;

    // Read sub-element offsets
    const pre_off = r.u32read();
    const clut_off = r.u32read();
    const post_off = r.u32read();
    const mat_off = r.u32read();
    _ = size;

    if (pre_off > 0 and pre_off < p.buf_size) {
        lt.pre_curve = elements.parseElementAt(p, pre_off, 0);
    }
    if (clut_off > 0 and clut_off < p.buf_size) {
        lt.clut = elements.parseElementAt(p, clut_off, 0);
    }
    if (post_off > 0 and post_off < p.buf_size) {
        lt.post_curve = elements.parseElementAt(p, post_off, 0);
    }
    if (mat_off > 0 and mat_off < p.buf_size) {
        lt.matrix = elements.parseElementAt(p, mat_off, 0);
    }

    el.kind = .lut;
    el.src_offset = src_offset;
    el.hold = 0;
    el.data = .{ .lut = lt };
    return el;
}
