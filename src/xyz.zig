// xyz.zig - XYZ tristimulus value element decode

const types = @import("types.zig");
const Reader = @import("reader.zig").Reader;
const mem = @import("alloc.zig");

pub fn decode(r: *Reader, src_offset: u32) ?*types.Element {
    const el = mem.create(types.Element) orelse return null;
    const v = mem.create(types.Xyz) orelse {
        mem.freeFn(types.Element, el);
        return null;
    };

    v.x = r.fixed();
    v.y = r.fixed();
    v.z = r.fixed();

    el.kind = .xyz;
    el.src_offset = src_offset;
    el.hold = 0;
    el.data = .{ .xyz = v };
    return el;
}
