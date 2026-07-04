// types.zig - core type definitions for the gamut color profile library
//
// All public and internal types used across the parsing pipeline, element
// pool, transform assembly, and evaluation.

const std = @import("std");

pub const HEADER_SIZE: usize = 128;
pub const MAX_CHANNELS: usize = 16;
pub const MAX_TAGS: usize = 128;
pub const NAMEDCOLOR_MAX: usize = 256;
pub const MPET_MAX_STAGES: usize = 16;
pub const STAGE_START: usize = 8;

pub const Colorspace = enum(u8) {
    rgb = 2,
    cmyk = 3,
    gray = 1,
    lab = 4,
    xyz = 5,
    unknown = 0,
};

pub const ElementKind = enum(u8) {
    none = 0,
    curve = 1,
    clut = 2,
    matrix = 3,
    xyz = 4,
    text = 5,
    lut = 6,
    mpet = 7,
};

pub const StageKind = enum(u8) {
    curve = 1,
    matrix = 2,
    clut = 3,
    chad = 4,
};

pub const MpetOp = enum(u8) {
    curve = 1,
    matrix = 2,
    clut = 3,
    unknown = 0,
};

pub const GmtError = error{
    BadMagic,
    BadHeader,
    BadTagTable,
    BadElement,
    BadCurve,
    BadClut,
    BadMatrix,
    BadLut,
    BadMpet,
    Unsupported,
    Range,
    OutOfMemory,
};

pub fn sig(a: u8, b: u8, c: u8, d: u8) u32 {
    return (@as(u32, a) << 24) | (@as(u32, b) << 16) | (@as(u32, c) << 8) | @as(u32, d);
}

pub const Curve = struct {
    fn_type: u8 = 0,
    count: u32 = 0,
    samples: ?[*]f32 = null,
    params: [7]f32 = [_]f32{0} ** 7,
};

pub const Clut = struct {
    in_ch: u8 = 0,
    out_ch: u8 = 0,
    grid: [MAX_CHANNELS]u8 = [_]u8{0} ** MAX_CHANNELS,
    point_count: u32 = 0,
    table: ?[*]f32 = null,
};

pub const Matrix = struct {
    e: [9]f32 = [_]f32{0} ** 9,
    off: [3]f32 = [_]f32{0} ** 3,
    rows: u8 = 3,
    cols: u8 = 3,
};

pub const Xyz = struct {
    x: f32 = 0,
    y: f32 = 0,
    z: f32 = 0,
};

pub const MpetStage = struct {
    op: MpetOp = .unknown,
    elem: i32 = -1,
};

pub const Mpet = struct {
    in_ch: u8 = 0,
    out_ch: u8 = 0,
    nstages: u32 = 0,
    stages: [MPET_MAX_STAGES]MpetStage = [_]MpetStage{.{}} ** MPET_MAX_STAGES,
    collapsed: bool = false,
    fold_elem: i32 = -1,
    fold_owned: ?*Element = null,
};

pub const Lut = struct {
    in_ch: u8 = 0,
    out_ch: u8 = 0,
    pre_curve: i32 = -1,
    clut: i32 = -1,
    post_curve: i32 = -1,
    matrix: i32 = -1,
};

pub const ElementData = union {
    curve: *Curve,
    clut: *Clut,
    matrix: *Matrix,
    xyz: *Xyz,
    text: [*:0]u8,
    lut: *Lut,
    mpet: *Mpet,
};

pub const Element = struct {
    kind: ElementKind = .none,
    src_offset: u32 = 0,
    hold: u32 = 0,
    data: ElementData = undefined,
};

pub const Tag = struct {
    signature: u32 = 0,
    offset: u32 = 0,
    size: u32 = 0,
    pool_idx: i32 = -1,
};

pub const ElemPool = struct {
    items: ?[*]?*Element = null,
    count: usize = 0,
    cap: usize = 0,
};

pub const LinkStage = struct {
    kind: StageKind = .curve,
    in_ch: u8 = 0,
    out_ch: u8 = 0,
    // curve
    curve_samples: ?[*]f32 = null,
    curve_count: u32 = 0,
    // clut
    clut_table: ?[*]f32 = null,
    grid: [MAX_CHANNELS]u8 = [_]u8{0} ** MAX_CHANNELS,
    // matrix
    matrix: ?*Matrix = null,
    // chad
    white: ?*Xyz = null,
};

pub const LinkCache = struct {
    stages: ?[*]LinkStage = null,
    count: usize = 0,
    cap: usize = 0,
    order: ?[*]?*LinkStage = null,
    order_count: usize = 0,
    order_cap: usize = 0,
    in_ch: u8 = 0,
    out_ch: u8 = 0,
    built: bool = false,
};

pub const Colorants = struct {
    count: usize = 0,
    names: [MAX_CHANNELS]?[*:0]u8 = [_]?[*:0]u8{null} ** MAX_CHANNELS,
    pool: ?*anyopaque = null,
};

pub const NamedColors = struct {
    count: usize = 0,
    names: ?[*]?[*:0]u8 = null,
};

pub const Profile = struct {
    buf: ?[*]const u8 = null,
    buf_size: usize = 0,
    version: u32 = 0,
    device_space: Colorspace = .unknown,
    pcs: Colorspace = .unknown,
    channels: u8 = 0,
    pcs_channels: u8 = 0,
    tags: ?[*]Tag = null,
    tag_count: usize = 0,
    pool: ElemPool = .{},
    link: LinkCache = .{},
    link_inv: LinkCache = .{},
    white: ?*Xyz = null,
    colorants: Colorants = .{},
    named: NamedColors = .{},
    has_named: bool = false,
    stored_id: u32 = 0,
    fatal: bool = false,
    alloc_bytes: usize = 0,
    parse_depth: u8 = 0,
};
