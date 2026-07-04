// root.zig - library root module
//
// Re-exports the parsing pipeline and all color science modules.
// Fuzz harnesses import this as their library dependency.

// Core parsing pipeline
pub const types = @import("types.zig");
pub const profile = @import("profile.zig");
pub const header = @import("header.zig");
pub const tagtable = @import("tagtable.zig");
pub const elements = @import("elements.zig");
pub const curves = @import("curves.zig");
pub const clut_mod = @import("clut.zig");
pub const matrix_mod = @import("matrix.zig");
pub const xyz_mod = @import("xyz.zig");
pub const luts = @import("luts.zig");
pub const mpet = @import("mpet.zig");
pub const linkcache = @import("linkcache.zig");
pub const validate = @import("validate.zig");
pub const checksum = @import("checksum.zig");
pub const colorants = @import("colorants.zig");
pub const resolve = @import("resolve.zig");
pub const alloc = @import("alloc.zig");
pub const reader = @import("reader.zig");

// Color science and analysis modules
pub const colorspace = @import("colorspace.zig");
pub const interp = @import("interp.zig");
pub const digest = @import("digest.zig");
pub const curvegen = @import("curvegen.zig");
pub const adapt = @import("adapt.zig");
pub const intent = @import("intent.zig");
pub const encoding = @import("encoding.zig");
pub const clutops = @import("clutops.zig");
pub const serialize = @import("serialize.zig");
pub const stats = @import("stats.zig");
pub const taginspect = @import("taginspect.zig");
pub const matutil = @import("matutil.zig");
pub const deltae = @import("deltae.zig");
pub const illuminant = @import("illuminant.zig");
pub const spectral = @import("spectral.zig");
pub const profbuild = @import("profbuild.zig");
pub const halftone = @import("halftone.zig");
pub const iccv4 = @import("iccv4.zig");
pub const iccio = @import("iccio.zig");
pub const gammap = @import("gammap.zig");
pub const profile_cmp = @import("profile_cmp.zig");
pub const pixelbuf = @import("pixelbuf.zig");
pub const proofing = @import("proofing.zig");
pub const whitebal = @import("whitebal.zig");
pub const tonemap = @import("tonemap.zig");
pub const chromadapt = @import("chromadapt.zig");
pub const linsys = @import("linsys.zig");
pub const colorname = @import("colorname.zig");
pub const uniformity = @import("uniformity.zig");
pub const gradient = @import("gradient.zig");
pub const colortemp = @import("colortemp.zig");
pub const transfer = @import("transfer.zig");
pub const colorcheck = @import("colorcheck.zig");
pub const munsell = @import("munsell.zig");
pub const perceptual = @import("perceptual.zig");
pub const printer = @import("printer.zig");
pub const gamutbd = @import("gamutbd.zig");
pub const gamutvolume = @import("gamutvolume.zig");
pub const observer = @import("observer.zig");
pub const primaries = @import("primaries.zig");
pub const profquality = @import("profquality.zig");
