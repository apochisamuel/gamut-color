// mpet.zig - multi-process element decode and evaluation
//
// An MPET is an ordered sequence of processing stages, each naming an
// operation type and referencing an element by its file offset. The
// collapse optimization for single-stage CLUTs adopts ownership of the

const types = @import("types.zig");
const Reader = @import("reader.zig").Reader;
const mem = @import("alloc.zig");
const elements = @import("elements.zig");

pub fn decode(p: *types.Profile, r: *Reader, src_offset: u32, size: u32) ?*types.Element {
    const in_ch = r.u8read();
    const out_ch = r.u8read();
    r.skip(2);
    const nstages = r.u32read();
    _ = size;

    if (in_ch == 0 or in_ch > types.MAX_CHANNELS or
        out_ch == 0 or out_ch > types.MAX_CHANNELS or
        nstages == 0 or nstages > types.MPET_MAX_STAGES or
        !r.ok(nstages * 8))
        return null;

    const el = mem.create(types.Element) orelse return null;
    const mp = mem.create(types.Mpet) orelse {
        mem.freeFn(types.Element, el);
        return null;
    };

    mp.in_ch = in_ch;
    mp.out_ch = out_ch;
    mp.nstages = nstages;
    mp.collapsed = false;
    mp.fold_elem = -1;
    mp.fold_owned = null;

    var si: u32 = 0;
    while (si < nstages) : (si += 1) {
        const op = r.u32read();
        const elem_off = r.u32read();

        mp.stages[si].op = switch (op) {
            1 => .curve,
            2 => .matrix,
            3 => .clut,
            else => .unknown,
        };

        if (elem_off > 0 and elem_off < p.buf_size) {
            mp.stages[si].elem = elements.parseElementAt(p, elem_off, 0);
        } else {
            mp.stages[si].elem = -1;
        }
    }

    // Collapse optimization: single-stage CLUT sequences adopt ownership
    // of the referenced element for faster evaluation.
    if (nstages == 1 and mp.stages[0].op == .clut and mp.stages[0].elem >= 0) {
        mp.collapsed = true;
        mp.fold_elem = mp.stages[0].elem;
        mp.fold_owned = elements.poolAt(&p.pool, mp.stages[0].elem);
    }

    el.kind = .mpet;
    el.src_offset = src_offset;
    el.hold = 0;
    el.data = .{ .mpet = mp };
    return el;
}

// Apply a CLUT stage from the link cache. Used by resolve.
// causing reads past the end of the CLUT table.
pub fn applyClut(s: *const types.LinkStage, work: []f32) void {
    if (s.clut_table == null) return;
    const in_ch = s.in_ch;
    const oc = s.out_ch;
    if (in_ch == 0 or oc == 0) return;

    var flat: u32 = 0;
    var stride: u32 = 1;
    var d: u8 = 0;
    while (d < in_ch and d < types.MAX_CHANNELS) : (d += 1) {
        const g = s.grid[d];
        if (g == 0) return;
        var v = work[d];
        if (v < 0.0) v = 0.0;
        if (v > 1.0) v = 1.0;
        var node: u32 = @intFromFloat(v * @as(f32, @floatFromInt(g - 1)));
        if (node >= g) node = g - 1;
        flat += node * stride;
        stride *= g;
    }

    d = 0;
    while (d < oc and d < types.MAX_CHANNELS) : (d += 1) {
        work[d] = s.clut_table.?[@as(usize, flat) * oc + d];
    }
}
