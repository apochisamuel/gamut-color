const profile = @import("profile.zig");
const types = @import("types.zig");

// Zig module exports (for Zig callers)
pub const openMemory = profile.openMemory;
pub const closeProfile = profile.close;
pub const applyProfile = profile.gmtApply;
pub const colorantIndex = profile.colorantIndex;
pub const Profile = types.Profile;

// C ABI exports (for C/C++ fuzzer harnesses)
export fn gmt_open_memory(data: [*]const u8, size: usize) ?*types.Profile {
    return profile.openMemory(data, size);
}

export fn gmt_apply(p: *const types.Profile, input: [*]const f32, output: [*]f32) c_int {
    const in_sl = input[0..p.channels];
    const out_sl = output[0..p.pcs_channels];
    return if (profile.gmtApply(p, in_sl, out_sl)) 0 else -1;
}

export fn gmt_colorant_index(p: *const types.Profile, name: [*:0]const u8) c_int {
    return profile.colorantIndex(p, name);
}

export fn gmt_close(p: *types.Profile) void {
    profile.close(p);
}

// Debug: report link cache state
export fn gmt_debug_link(p: *const types.Profile) void {
    const c = struct {
        extern fn printf([*:0]const u8, ...) c_int;
    };
    _ = c.printf("link.built=%d order_count=%zu count=%zu\n", 
        @as(c_int, if (p.link.built) 1 else 0),
        p.link.order_count,
        p.link.count);
    _ = c.printf("device_space=%d channels=%d tag_count=%zu\n",
        @as(c_int, @intFromEnum(p.device_space)),
        @as(c_int, p.channels),
        p.tag_count);
}

export fn gmt_debug_pool_count(p: *const types.Profile) c_int {
    const c = struct { extern fn printf([*:0]const u8, ...) c_int; };
    _ = c.printf("pool.count=%zu pool.cap=%zu\n", p.pool.count, p.pool.cap);
    // Print each tag's pool_idx
    if (p.tags) |tags| {
        var i: usize = 0;
        while (i < p.tag_count) : (i += 1) {
            _ = c.printf("  tag[%zu] sig=%08x pool_idx=%d\n", i, tags[i].signature, tags[i].pool_idx);
        }
    }
    // Print pool elements
    if (p.pool.items) |items| {
        var i: usize = 0;
        while (i < p.pool.count) : (i += 1) {
            if (items[i]) |el| {
                _ = c.printf("  pool[%zu] kind=%d src_offset=%u\n", i, @as(c_int, @intFromEnum(el.kind)), el.src_offset);
            }
        }
    }
    return 0;
}
