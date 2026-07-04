const profile = @import("profile.zig");
const types = @import("types.zig");
const exports = @import("exports.zig");

// Zig module re-exports
pub const openMemory = profile.openMemory;
pub const closeProfile = profile.close;
pub const applyProfile = profile.gmtApply;
pub const colorantIndex = profile.colorantIndex;
pub const Profile = types.Profile;

// Core C ABI exports
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

// Force exports module to compile (all utility modules are transitively imported)
comptime {
    _ = exports;
}
