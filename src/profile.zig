// profile.zig - public API entry points

const types = @import("types.zig");
const header = @import("header.zig");
const tagtable = @import("tagtable.zig");
const elems = @import("elements.zig");
const linkcache = @import("linkcache.zig");
const colorants = @import("colorants.zig");
const checksum = @import("checksum.zig");
const validate = @import("validate.zig");
const resolve = @import("resolve.zig");
const mem = @import("alloc.zig");

pub fn openMemory(data: [*]const u8, size: usize) ?*types.Profile {
    if (size < types.HEADER_SIZE) return null;

    const p = mem.create(types.Profile) orelse return null;
    p.* = .{};
    p.buf = data;
    p.buf_size = size;

    // Read stored profile ID from header bytes [24..28)
    if (size >= 28) {
        p.stored_id = (@as(u32, data[24]) << 24) |
            (@as(u32, data[25]) << 16) |
            (@as(u32, data[26]) << 8) |
            @as(u32, data[27]);
    }

    // Phase 1-2: header and tag directory
    header.parse(p) catch {
        mem.freeFn(types.Profile, p);
        return null;
    };
    tagtable.parse(p) catch {
        close(p);
        return null;
    };

    // Phase 3-7: element decode
    elems.parseAll(p) catch {
        close(p);
        return null;
    };

    // Phase 7b: colorants and named colors
    colorants.parseColorants(p);
    colorants.parseNamedColors(p);

    // Phase 8: assemble the transform
    if (!linkcache.build(p)) {
        close(p);
        return null;
    }

    checksum.verify(p);

    validate.validate(p);

    return p;
}

pub fn gmtApply(p: *const types.Profile, input: []const f32, output: []f32) bool {
    return resolve.apply(p, &p.link, input, output);
}

pub fn colorantIndex(p: *const types.Profile, name: [*:0]const u8) i32 {
    var i: usize = 0;
    while (i < p.colorants.count) : (i += 1) {
        if (p.colorants.names[i]) |cname| {
            const std = @import("std");
            if (std.mem.orderZ(u8, cname, name) == .eq) return @intCast(i);
        }
    }
    return -1;
}

pub fn close(p: *types.Profile) void {
    linkcache.linkFree(&p.link);
    linkcache.linkFree(&p.link_inv);
    elems.poolFree(&p.pool);
    // Free tags
    if (p.tags) |tags| {
        const sl = tags[0..p.tag_count];
        mem.freeSlice(types.Tag, sl);
    }
    // Free colorant names
    var i: usize = 0;
    while (i < p.colorants.count) : (i += 1) {
        if (p.colorants.names[i]) |name| {
            mem.freeZ(name);
        }
    }
    // Free named color names
    if (p.named.names) |names| {
        var j: usize = 0;
        while (j < p.named.count) : (j += 1) {
            if (names[j]) |name| {
                mem.freeZ(name);
            }
        }
        mem.freeSlice(?[*:0]u8, names[0..p.named.count]);
    }
    mem.freeFn(types.Profile, p);
}
