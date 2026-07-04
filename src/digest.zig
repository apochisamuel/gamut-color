// digest.zig - hash and digest utilities
//
// FNV-1a and CRC32 implementations for profile identification and
// data integrity checking. Used by checksum verification and tag
// deduplication.

// FNV-1a 32-bit hash
pub fn fnv1a32(data: []const u8) u32 {
    var h: u32 = 2166136261;
    for (data) |b| {
        h ^= b;
        h *%= 16777619;
    }
    return h;
}

// FNV-1a with an excluded range (for profile ID computation)
pub fn fnv1aExclude(data: []const u8, exc_off: usize, exc_len: usize) u32 {
    var h: u32 = 2166136261;
    for (data, 0..) |b, i| {
        const byte = if (i >= exc_off and i < exc_off + exc_len) @as(u8, 0) else b;
        h ^= byte;
        h *%= 16777619;
    }
    return h;
}

// CRC32 table
const crc32_table = blk: {
    @setEvalBranchQuota(5000);
    var table: [256]u32 = undefined;
    for (0..256) |i| {
        var c: u32 = @intCast(i);
        for (0..8) |_| {
            if (c & 1 != 0) {
                c = 0xEDB88320 ^ (c >> 1);
            } else {
                c >>= 1;
            }
        }
        table[i] = c;
    }
    break :blk table;
};

// CRC32 (ISO 3309)
pub fn crc32(data: []const u8) u32 {
    var crc: u32 = 0xFFFFFFFF;
    for (data) |b| {
        crc = crc32_table[(crc ^ b) & 0xFF] ^ (crc >> 8);
    }
    return crc ^ 0xFFFFFFFF;
}

// Update a running CRC32
pub fn crc32Update(crc: u32, data: []const u8) u32 {
    var c = crc ^ 0xFFFFFFFF;
    for (data) |b| {
        c = crc32_table[(c ^ b) & 0xFF] ^ (c >> 8);
    }
    return c ^ 0xFFFFFFFF;
}

// Combined 64-bit fingerprint: FNV-1a of header || CRC32 of body
pub fn profileFingerprint(data: []const u8) u64 {
    if (data.len < 128) return 0;
    const head_hash = fnv1aExclude(data[0..128], 24, 4);
    const body_crc = crc32(data[128..]);
    return (@as(u64, head_hash) << 32) | @as(u64, body_crc);
}

// Compute profile ID as defined by the format spec
pub fn computeProfileId(data: []const u8) u32 {
    return fnv1aExclude(data, 24, 4);
}

// Verify stored profile ID against computed
pub fn verifyProfileId(data: []const u8) i32 {
    if (data.len < 28) return -1;
    const stored = (@as(u32, data[24]) << 24) |
        (@as(u32, data[25]) << 16) |
        (@as(u32, data[26]) << 8) |
        @as(u32, data[27]);
    if (stored == 0) return -1;
    const computed = computeProfileId(data);
    return if (stored == computed) 1 else 0;
}

// Hash a single tag body for deduplication
pub fn hashTagBody(data: []const u8, offset: u32, size: u32) u32 {
    const off: usize = offset;
    const sz: usize = size;
    if (off + sz > data.len) return 0;
    return fnv1a32(data[off .. off + sz]);
}

// Simple string hash for colorant name lookup
pub fn hashString(s: [*:0]const u8) u32 {
    var h: u32 = 2166136261;
    var i: usize = 0;
    while (s[i] != 0) : (i += 1) {
        h ^= s[i];
        h *%= 16777619;
    }
    return h;
}
