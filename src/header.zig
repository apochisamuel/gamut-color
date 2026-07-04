// header.zig - profile header parsing
//
// Reads the 128-byte fixed header to extract format signature, version,
// device color space, profile connection space, and channel count.

const types = @import("types.zig");
const Reader = @import("reader.zig").Reader;

pub fn parse(p: *types.Profile) !void {
    if (p.buf_size < types.HEADER_SIZE)
        return error.BadHeader;

    var r = Reader.init(p.buf.?, p.buf_size);

    // Skip to magic at offset 4
    r.skip(4);
    const magic = r.u32read();
    if (magic != types.sig('g', 'm', 't', 0x01))
        return error.BadMagic;

    // Version at offset 8
    const ver_hi = r.u8read();
    const ver_lo = r.u8read();
    p.version = (@as(u32, ver_hi) << 8) | @as(u32, ver_lo);
    r.skip(2); // skip minor (offset 10-11)

    // Device space at offset 15
    r.skip(3); // skip 12-14
    const ds = r.u8read();
    p.device_space = switch (ds) {
        1 => .gray,
        2 => .rgb,
        3 => .cmyk,
        else => .unknown,
    };

    // PCS at offset 19
    r.skip(3); // skip 16-18
    const pc = r.u8read();
    p.pcs = switch (pc) {
        4 => .lab,
        5 => .xyz,
        else => .xyz,
    };

    // Channels at offset 23
    r.skip(3); // skip 20-22
    const nch = r.u8read();
    if (nch == 0 or nch > types.MAX_CHANNELS)
        return error.BadHeader;
    p.channels = nch;
    p.pcs_channels = 3;
}
