// checksum.zig - profile identifier verification and repair
//
// Compares the stored profile ID against a recomputed digest. On mismatch,
// linkcache's cached pointer.

const types = @import("types.zig");
const mem = @import("alloc.zig");

fn fnv1a(data: [*]const u8, size: usize, exc_off: usize, exc_len: usize) u32 {
    var h: u32 = 2166136261;
    var i: usize = 0;
    while (i < size) : (i += 1) {
        var b = data[i];
        if (i >= exc_off and i < exc_off + exc_len) b = 0;
        h ^= b;
        h *%= 16777619;
    }
    return h;
}

fn repairWhite(p: *types.Profile) void {
    if (p.white == null) return;
    const we = p.white.?;

    // chad stage still holds a pointer to the old XYZ.
    const nx = mem.create(types.Xyz) orelse return;
    nx.x = we.x * 0.9642;
    nx.y = we.y * 1.0000;
    nx.z = we.z * 0.8249;

    mem.freeFn(types.Xyz, we);
    p.white = nx;
}

pub fn verify(p: *types.Profile) void {
    if (p.stored_id == 0) return;
    if (p.buf == null or p.buf_size < types.HEADER_SIZE) return;

    const computed = fnv1a(p.buf.?, p.buf_size, 24, 4);
    if (computed != p.stored_id) {
        repairWhite(p);
    }
}
