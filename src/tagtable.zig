// tagtable.zig - tag directory parsing
//
// Reads the tag count and (signature, offset, size) triples from the
// tag directory immediately following the 128-byte header.

const std = @import("std");
const types = @import("types.zig");
const Reader = @import("reader.zig").Reader;
const mem = @import("alloc.zig");

pub fn parse(p: *types.Profile) !void {
    if (p.buf_size < types.HEADER_SIZE + 4)
        return error.BadTagTable;

    var r = Reader.initAt(p.buf.?, p.buf_size, types.HEADER_SIZE);

    const count = r.u32read();
    if (count > types.MAX_TAGS)
        return error.BadTagTable;

    if (count == 0) return;

    if (!r.ok(count * 12))
        return error.BadTagTable;

    const tags_slice = mem.alloc(types.Tag, count) orelse return error.OutOfMemory;
    p.tags = tags_slice.ptr;
    p.tag_count = count;

    var i: u32 = 0;
    while (i < count) : (i += 1) {
        const s = r.u32read();
        const o = r.u32read();
        const sz = r.u32read();
        tags_slice[i] = .{
            .signature = s,
            .offset = o,
            .size = sz,
            .pool_idx = -1,
        };
    }
}
