// matrix.zig - 3x3 affine matrix element decode

const types = @import("types.zig");
const Reader = @import("reader.zig").Reader;
const mem = @import("alloc.zig");

pub fn decode(r: *Reader, src_offset: u32) ?*types.Element {
    const el = mem.create(types.Element) orelse return null;
    const m = mem.create(types.Matrix) orelse {
        mem.freeFn(types.Element, el);
        return null;
    };

    var i: usize = 0;
    while (i < 9) : (i += 1) {
        m.e[i] = r.fixed();
    }
    i = 0;
    while (i < 3) : (i += 1) {
        m.off[i] = r.fixed();
    }
    m.rows = 3;
    m.cols = 3;

    el.kind = .matrix;
    el.src_offset = src_offset;
    el.hold = 0;
    el.data = .{ .matrix = m };
    return el;
}
