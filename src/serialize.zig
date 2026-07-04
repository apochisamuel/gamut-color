// serialize.zig - profile serialization
//
// Convert a parsed profile back to its binary representation. Writes
// header, tag directory, and element bodies in canonical order.

const types = @import("types.zig");

fn w32(buf: []u8, off: usize, v: u32) void {
    if (off + 4 > buf.len) return;
    buf[off] = @intCast((v >> 24) & 0xFF);
    buf[off + 1] = @intCast((v >> 16) & 0xFF);
    buf[off + 2] = @intCast((v >> 8) & 0xFF);
    buf[off + 3] = @intCast(v & 0xFF);
}

fn w16(buf: []u8, off: usize, v: u16) void {
    if (off + 2 > buf.len) return;
    buf[off] = @intCast((v >> 8) & 0xFF);
    buf[off + 1] = @intCast(v & 0xFF);
}

// Write the header
fn writeHeader(p: *const types.Profile, buf: []u8) usize {
    if (buf.len < types.HEADER_SIZE) return 0;
    @memset(buf[0..types.HEADER_SIZE], 0);
    w32(buf, 4, types.sig('g', 'm', 't', 0x01));
    buf[8] = @intCast((p.version >> 8) & 0xFF);
    buf[9] = @intCast(p.version & 0xFF);
    buf[15] = @intFromEnum(p.device_space);
    buf[19] = @intFromEnum(p.pcs);
    buf[23] = p.channels;
    return types.HEADER_SIZE;
}

// Write the tag directory
fn writeTagDir(p: *const types.Profile, buf: []u8, base: usize) usize {
    if (p.tags == null) return 0;
    var pos = base;
    w32(buf, pos, @intCast(p.tag_count));
    pos += 4;
    var i: usize = 0;
    while (i < p.tag_count) : (i += 1) {
        const t = p.tags.?[i];
        w32(buf, pos, t.signature);
        w32(buf, pos + 4, t.offset);
        w32(buf, pos + 8, t.size);
        pos += 12;
    }
    return pos - base;
}

// Write a curve element
fn writeCurve(cv: *const types.Curve, buf: []u8, off: usize) usize {
    var pos = off;
    w32(buf, pos, types.sig('c', 'u', 'r', 'v'));
    pos += 4;
    w16(buf, pos, @intCast(cv.count));
    pos += 4; // 2 bytes count + 2 padding
    if (cv.samples) |samples| {
        var i: u32 = 0;
        while (i < cv.count) : (i += 1) {
            const v: u16 = @intFromFloat(samples[i] * 65535.0);
            w16(buf, pos, v);
            pos += 2;
        }
    }
    return pos - off;
}

// Write a CLUT element
fn writeClut(cl: *const types.Clut, buf: []u8, off: usize) usize {
    var pos = off;
    w32(buf, pos, types.sig('C', 'L', 'U', 'T'));
    pos += 4;
    buf[pos] = cl.in_ch;
    buf[pos + 1] = cl.out_ch;
    pos += 4;
    var d: u8 = 0;
    while (d < cl.in_ch) : (d += 1) {
        buf[pos] = cl.grid[d];
        pos += 1;
    }
    if (cl.table) |table| {
        const total = @as(usize, cl.point_count) * cl.out_ch;
        var i: usize = 0;
        while (i < total) : (i += 1) {
            const v: u16 = @intFromFloat(table[i] * 65535.0);
            w16(buf, pos, v);
            pos += 2;
        }
    }
    return pos - off;
}

// Write a matrix element
fn writeMatrix(m: *const types.Matrix, buf: []u8, off: usize) usize {
    var pos = off;
    w32(buf, pos, types.sig('m', 'a', 't', 'x'));
    pos += 4;
    for (0..9) |i| {
        const fixed: u32 = @bitCast(@as(i32, @intFromFloat(m.e[i] * 65536.0)));
        w32(buf, pos, fixed);
        pos += 4;
    }
    for (0..3) |i| {
        const fixed: u32 = @bitCast(@as(i32, @intFromFloat(m.off[i] * 65536.0)));
        w32(buf, pos, fixed);
        pos += 4;
    }
    return pos - off;
}

// Write an XYZ element
fn writeXyz(v: *const types.Xyz, buf: []u8, off: usize) usize {
    var pos = off;
    w32(buf, pos, types.sig('X', 'Y', 'Z', ' '));
    pos += 4;
    w32(buf, pos, @bitCast(@as(i32, @intFromFloat(v.x * 65536.0))));
    pos += 4;
    w32(buf, pos, @bitCast(@as(i32, @intFromFloat(v.y * 65536.0))));
    pos += 4;
    w32(buf, pos, @bitCast(@as(i32, @intFromFloat(v.z * 65536.0))));
    pos += 4;
    return pos - off;
}

// Estimate the serialized size of a profile
pub fn estimateSize(p: *const types.Profile) usize {
    var size: usize = types.HEADER_SIZE;
    size += 4 + p.tag_count * 12; // tag directory
    // Each element body (rough estimate)
    if (p.pool.items) |items| {
        var i: usize = 0;
        while (i < p.pool.count) : (i += 1) {
            if (items[i]) |el| {
                size += switch (el.kind) {
                    .curve => 8 + @as(usize, el.data.curve.count) * 2,
                    .clut => 8 + @as(usize, el.data.clut.in_ch) + @as(usize, el.data.clut.point_count) * el.data.clut.out_ch * 2,
                    .matrix => 52,
                    .xyz => 16,
                    .text => 64,
                    .lut => 24,
                    .mpet => 12 + @as(usize, el.data.mpet.nstages) * 8,
                    .none => 0,
                };
            }
        }
    }
    return size;
}

// Serialize the profile to a buffer. Returns bytes written.
pub fn serialize(p: *const types.Profile, buf: []u8) usize {
    if (buf.len < types.HEADER_SIZE) return 0;

    var pos = writeHeader(p, buf);
    pos += writeTagDir(p, buf, pos);

    // Write element bodies
    if (p.pool.items) |items| {
        var i: usize = 0;
        while (i < p.pool.count) : (i += 1) {
            if (items[i]) |el| {
                const written = switch (el.kind) {
                    .curve => writeCurve(el.data.curve, buf, pos),
                    .clut => writeClut(el.data.clut, buf, pos),
                    .matrix => writeMatrix(el.data.matrix, buf, pos),
                    .xyz => writeXyz(el.data.xyz, buf, pos),
                    else => @as(usize, 0),
                };
                pos += written;
            }
        }
    }

    // Write total size at offset 0
    w32(buf, 0, @intCast(pos));
    return pos;
}
