// iccio.zig - ICC profile header and tag directory I/O
//
// Low-level read/write operations for ICC profile binary format.
// Handles byte order, fixed-point encoding, date/time fields,
// and profile connection space negotiation.

const types = @import("types.zig");
const Reader = @import("reader.zig").Reader;

// Read a u32 from arbitrary offset in a buffer
pub fn readU32At(buf: []const u8, off: usize) u32 {
    if (off + 4 > buf.len) return 0;
    return (@as(u32, buf[off]) << 24) |
        (@as(u32, buf[off + 1]) << 16) |
        (@as(u32, buf[off + 2]) << 8) |
        @as(u32, buf[off + 3]);
}

pub fn readU16At(buf: []const u8, off: usize) u16 {
    if (off + 2 > buf.len) return 0;
    return (@as(u16, buf[off]) << 8) | @as(u16, buf[off + 1]);
}

pub fn readFixed(buf: []const u8, off: usize) f32 {
    const whole = readU16At(buf, off);
    const frac = readU16At(buf, off + 2);
    return @as(f32, @floatFromInt(whole)) + @as(f32, @floatFromInt(frac)) / 65536.0;
}

pub fn readS15Fixed16(buf: []const u8, off: usize) f32 {
    const raw: i32 = @bitCast(readU32At(buf, off));
    return @as(f32, @floatFromInt(raw)) / 65536.0;
}

// Write helpers
pub fn writeU32At(buf: []u8, off: usize, v: u32) void {
    if (off + 4 > buf.len) return;
    buf[off] = @intCast((v >> 24) & 0xFF);
    buf[off + 1] = @intCast((v >> 16) & 0xFF);
    buf[off + 2] = @intCast((v >> 8) & 0xFF);
    buf[off + 3] = @intCast(v & 0xFF);
}

pub fn writeU16At(buf: []u8, off: usize, v: u16) void {
    if (off + 2 > buf.len) return;
    buf[off] = @intCast((v >> 8) & 0xFF);
    buf[off + 1] = @intCast(v & 0xFF);
}

pub fn writeFixed(buf: []u8, off: usize, v: f32) void {
    const fixed: u32 = @bitCast(@as(i32, @intFromFloat(v * 65536.0)));
    writeU32At(buf, off, fixed);
}

// Validate ICC profile magic number at various positions
pub fn validateMagic(buf: []const u8) bool {
    if (buf.len < 128) return false;
    // Check for 'acsp' at offset 36
    const sig = readU32At(buf, 36);
    return sig == types.sig('a', 'c', 's', 'p');
}

// Validate our custom gmt format magic
pub fn validateGmtMagic(buf: []const u8) bool {
    if (buf.len < 8) return false;
    return readU32At(buf, 4) == types.sig('g', 'm', 't', 0x01);
}

// Extract tag directory from raw ICC data
pub fn readTagDirectory(buf: []const u8) struct { count: u32, valid: bool } {
    if (buf.len < 132) return .{ .count = 0, .valid = false };
    const count = readU32At(buf, 128);
    if (count > types.MAX_TAGS) return .{ .count = count, .valid = false };
    if (buf.len < 132 + count * 12) return .{ .count = count, .valid = false };
    return .{ .count = count, .valid = true };
}

// Read a single tag entry
pub fn readTagEntry(buf: []const u8, index: u32) types.Tag {
    const off = 132 + @as(usize, index) * 12;
    return .{
        .signature = readU32At(buf, off),
        .offset = readU32At(buf, off + 4),
        .size = readU32At(buf, off + 8),
        .pool_idx = -1,
    };
}

// Count tags of a given type signature pattern
pub fn countTagsMatching(buf: []const u8, mask: u32, value: u32) u32 {
    const dir = readTagDirectory(buf);
    if (!dir.valid) return 0;
    var count: u32 = 0;
    var i: u32 = 0;
    while (i < dir.count) : (i += 1) {
        const tag = readTagEntry(buf, i);
        if (tag.signature & mask == value) count += 1;
    }
    return count;
}

// Read the profile connection space from header
pub fn readPcs(buf: []const u8) types.Colorspace {
    if (buf.len < 24) return .unknown;
    const pcs_sig = readU32At(buf, 20);
    return switch (pcs_sig) {
        types.sig('X', 'Y', 'Z', ' ') => .xyz,
        types.sig('L', 'a', 'b', ' ') => .lab,
        else => .unknown,
    };
}

// Read profile size from header
pub fn readProfileSize(buf: []const u8) u32 {
    return readU32At(buf, 0);
}

// Check that declared size matches buffer
pub fn sizeConsistent(buf: []const u8) bool {
    if (buf.len < 4) return false;
    const declared = readProfileSize(buf);
    return declared <= buf.len;
}

// Compute a simple tag coverage metric
pub fn tagCoverage(buf: []const u8) f32 {
    const dir = readTagDirectory(buf);
    if (!dir.valid or dir.count == 0) return 0;
    const profile_size = readProfileSize(buf);
    if (profile_size <= 132) return 0;

    var covered: u32 = 0;
    var i: u32 = 0;
    while (i < dir.count) : (i += 1) {
        const tag = readTagEntry(buf, i);
        covered += tag.size;
    }
    return @as(f32, @floatFromInt(covered)) / @as(f32, @floatFromInt(profile_size - 132));
}
