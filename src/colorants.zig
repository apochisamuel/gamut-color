// colorants.zig - colorant table and named color parsing

const types = @import("types.zig");
const Reader = @import("reader.zig").Reader;
const mem = @import("alloc.zig");
const linkcache = @import("linkcache.zig");

pub fn parseColorants(p: *types.Profile) void {
    const t = linkcache.findTag(p, types.sig('c', 'l', 'r', 't')) orelse return;
    if (t.size == 0 or t.size > 8192) return;
    if (@as(usize, t.offset) + t.size > p.buf_size) return;

    var r = Reader.initAt(p.buf.?, p.buf_size, t.offset);
    r.skip(4); // type sig
    const count = r.u32read();
    if (count == 0 or count > types.MAX_CHANNELS) return;

    p.colorants.count = count;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        if (!r.ok(32)) break;
        var name: [32]u8 = undefined;
        var j: usize = 0;
        while (j < 32) : (j += 1) {
            name[j] = r.u8read();
        }
        // Find null terminator
        var len: usize = 0;
        while (len < 32 and name[len] != 0) : (len += 1) {}
        if (len > 0) {
            p.colorants.names[i] = mem.dupeZ(name[0..len]);
        }
    }
}

// BUG 4: namedcolor error path releases the colorant backing pool
pub fn parseNamedColors(p: *types.Profile) void {
    const t = linkcache.findTag(p, types.sig('n', 'c', 'l', '2')) orelse return;
    if (t.size == 0) return;
    if (@as(usize, t.offset) + t.size > p.buf_size) return;

    var r = Reader.initAt(p.buf.?, p.buf_size, t.offset);
    r.skip(4); // type sig
    const count = r.u32read();
    const dev_ch = r.u8read();
    r.skip(3);

    if (count == 0 or count > types.NAMEDCOLOR_MAX or dev_ch > types.MAX_CHANNELS) return;

    const names = mem.alloc(?[*:0]u8, count) orelse return;
    @memset(names, null);
    p.named.names = names.ptr;
    p.named.count = count;
    p.has_named = true;

    var i: usize = 0;
    while (i < count) : (i += 1) {
        if (!r.ok(dev_ch + 6)) {
            // Error: not enough data. Unwind.
            namedcolorUnwind(p);
            return;
        }
        var name: [64]u8 = undefined;
        var j: usize = 0;
        while (j < 6) : (j += 1) {
            if (r.ok(1)) name[j] = r.u8read() else name[j] = 0;
        }
        var len: usize = 0;
        while (len < 6 and name[len] != 0) : (len += 1) {}
        if (len > 0) {
            names[i] = mem.dupeZ(name[0..len]);
        }
        r.skip(dev_ch);
    }
}

fn namedcolorUnwind(p: *types.Profile) void {
    // BUG 4: releases the colorant name strings but does not clear the
    // pointers in p.colorants.names[]. When close() later iterates and
    // frees them again, it causes a double-free.
    var i: usize = 0;
    while (i < p.colorants.count) : (i += 1) {
        if (p.colorants.names[i]) |name| {
            mem.freeZ(name);
            // NOTE: intentionally NOT setting names[i] = null
        }
    }
    if (p.named.names) |names| {
        const sl = names[0..p.named.count];
        mem.freeSlice(?[*:0]u8, sl);
        p.named.names = null;
    }
    p.named.count = 0;
    p.has_named = false;
}
