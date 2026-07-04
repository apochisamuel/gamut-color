// iccv4.zig - ICC v4 profile operations
//
// Version 4 specific processing: perceptual rendering intent tag
// selection, profile description extraction, date/time parsing,
// measurement condition handling, and v4 header field interpretation.

const types = @import("types.zig");
const Reader = @import("reader.zig").Reader;

pub const ProfileClass = enum(u8) {
    input = 1,
    display = 2,
    output = 3,
    device_link = 4,
    color_space = 5,
    abstract_profile = 6,
    named_color = 7,
    unknown = 0,
};

pub const PlatformSig = enum(u32) {
    apple = 0x4150504C,
    microsoft = 0x4D534654,
    sgi = 0x53474920,
    sun = 0x53554E57,
    unknown = 0,
};

pub const DateTime = struct {
    year: u16 = 0,
    month: u16 = 0,
    day: u16 = 0,
    hour: u16 = 0,
    minute: u16 = 0,
    second: u16 = 0,
};

pub const RenderingIntent = enum(u8) {
    perceptual = 0,
    relative_colorimetric = 1,
    saturation_rint = 2,
    absolute_colorimetric = 3,
};

pub const HeaderV4 = struct {
    size: u32 = 0,
    preferred_cmm: u32 = 0,
    version: u32 = 0,
    profile_class: ProfileClass = .unknown,
    data_colorspace: types.Colorspace = .unknown,
    pcs: types.Colorspace = .unknown,
    creation_date: DateTime = .{},
    primary_platform: PlatformSig = .unknown,
    flags: u32 = 0,
    manufacturer: u32 = 0,
    model: u32 = 0,
    attributes: u64 = 0,
    rendering_intent: RenderingIntent = .perceptual,
    illuminant: types.Xyz = .{},
    creator: u32 = 0,
    profile_id: [16]u8 = [_]u8{0} ** 16,
};

pub fn parseV4Header(data: []const u8) ?HeaderV4 {
    if (data.len < 128) return null;
    var r = Reader.init(data.ptr, data.len);
    var h = HeaderV4{};

    h.size = r.u32read();
    h.preferred_cmm = r.u32read();
    const ver = r.u32read();
    h.version = ver;

    const cls = r.u32read();
    h.profile_class = switch (cls) {
        0x73636E72 => .input,
        0x6D6E7472 => .display,
        0x70727472 => .output,
        0x6C696E6B => .device_link,
        0x73706163 => .color_space,
        0x61627374 => .abstract_profile,
        0x6E6D636C => .named_color,
        else => .unknown,
    };

    const dcs = r.u32read();
    h.data_colorspace = switch (dcs & 0xFF) {
        1 => .gray,
        2 => .rgb,
        3 => .cmyk,
        else => .unknown,
    };

    const pcs = r.u32read();
    h.pcs = switch (pcs & 0xFF) {
        4 => .lab,
        5 => .xyz,
        else => .xyz,
    };

    h.creation_date.year = r.u16read();
    h.creation_date.month = r.u16read();
    h.creation_date.day = r.u16read();
    h.creation_date.hour = r.u16read();
    h.creation_date.minute = r.u16read();
    h.creation_date.second = r.u16read();

    _ = r.u32read(); // 'acsp' signature
    h.primary_platform = @enumFromInt(r.u32read());
    h.flags = r.u32read();
    h.manufacturer = r.u32read();
    h.model = r.u32read();

    // Attributes (8 bytes)
    const hi_attr = r.u32read();
    const lo_attr = r.u32read();
    h.attributes = (@as(u64, hi_attr) << 32) | lo_attr;

    const ri = r.u32read();
    h.rendering_intent = switch (ri & 3) {
        0 => .perceptual,
        1 => .relative_colorimetric,
        2 => .saturation_rint,
        3 => .absolute_colorimetric,
        else => .perceptual,
    };

    h.illuminant.x = r.fixed();
    h.illuminant.y = r.fixed();
    h.illuminant.z = r.fixed();

    h.creator = r.u32read();

    // Profile ID (16 bytes)
    if (r.ok(16)) {
        var k: usize = 0;
        while (k < 16) : (k += 1) {
            h.profile_id[k] = r.u8read();
        }
    }

    return h;
}

// Select appropriate AtoB/BtoA tag for a rendering intent
pub fn selectLutTag(intent: RenderingIntent, forward: bool) u32 {
    const base: u8 = if (forward) '0' else '0';
    const idx: u8 = @intFromEnum(intent);
    if (forward) {
        return types.sig('A', '2', 'B', base + idx);
    } else {
        return types.sig('B', '2', 'A', base + idx);
    }
}

// Check if profile is a device-link
pub fn isDeviceLink(class: ProfileClass) bool {
    return class == .device_link;
}

// Check if profile is abstract
pub fn isAbstract(class: ProfileClass) bool {
    return class == .abstract_profile;
}

// Check transparency flag
pub fn isTransparent(flags: u32) bool {
    return (flags & 1) != 0;
}

// Check matte flag
pub fn isMatte(flags: u32) bool {
    return (flags & 2) != 0;
}

// Compute version as a readable triple
pub fn versionTriple(version: u32) [3]u8 {
    return .{
        @intCast((version >> 24) & 0xFF),
        @intCast((version >> 20) & 0x0F),
        @intCast((version >> 16) & 0x0F),
    };
}

// Check version compatibility
pub fn isV4(version: u32) bool {
    return (version >> 24) >= 4;
}

pub fn isV2(version: u32) bool {
    return (version >> 24) == 2;
}
