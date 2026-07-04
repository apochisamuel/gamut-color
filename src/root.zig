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

// Debug exports
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
    if (p.tags) |tags| {
        var i: usize = 0;
        while (i < p.tag_count) : (i += 1) {
            _ = c.printf("  tag[%zu] sig=%08x pool_idx=%d\n", i, tags[i].signature, tags[i].pool_idx);
        }
    }
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

// Re-export all library modules to ensure compilation
pub const adapt_mod = @import("adapt.zig");
pub const chromadapt_mod = @import("chromadapt.zig");
pub const clutops_mod = @import("clutops.zig");
pub const colorcheck_mod = @import("colorcheck.zig");
pub const colorname_mod = @import("colorname.zig");
pub const colorspace_mod = @import("colorspace.zig");
pub const colortemp_mod = @import("colortemp.zig");
pub const curvegen_mod = @import("curvegen.zig");
pub const deltae_mod = @import("deltae.zig");
pub const digest_mod = @import("digest.zig");
pub const encoding_mod = @import("encoding.zig");
pub const gammap_mod = @import("gammap.zig");
pub const gamutbd_mod = @import("gamutbd.zig");
pub const gamutvolume_mod = @import("gamutvolume.zig");
pub const gradient_mod = @import("gradient.zig");
pub const halftone_mod = @import("halftone.zig");
pub const iccio_mod = @import("iccio.zig");
pub const iccv4_mod = @import("iccv4.zig");
pub const illuminant_mod = @import("illuminant.zig");
pub const intent_mod = @import("intent.zig");
pub const interp_mod = @import("interp.zig");
pub const linsys_mod = @import("linsys.zig");
pub const matutil_mod = @import("matutil.zig");
pub const munsell_mod = @import("munsell.zig");
pub const observer_mod = @import("observer.zig");
pub const perceptual_mod = @import("perceptual.zig");
pub const pixelbuf_mod = @import("pixelbuf.zig");
pub const primaries_mod = @import("primaries.zig");
pub const printer_mod = @import("printer.zig");
pub const profbuild_mod = @import("profbuild.zig");
pub const profile_cmp_mod = @import("profile_cmp.zig");
pub const profquality_mod = @import("profquality.zig");
pub const proofing_mod = @import("proofing.zig");
pub const serialize_mod = @import("serialize.zig");
pub const spectral_mod = @import("spectral.zig");
pub const stats_mod = @import("stats.zig");
pub const taginspect_mod = @import("taginspect.zig");
pub const tonemap_mod = @import("tonemap.zig");
pub const transfer_mod = @import("transfer.zig");
pub const uniformity_mod = @import("uniformity.zig");
pub const whitebal_mod = @import("whitebal.zig");
