// linkcache.zig - transform pipeline assembly
//
// Builds the device-to-PCS transform by walking resolved tags and
// appending stages to a growable array. The stage array and the
// application-order index are separate allocations.

const types = @import("types.zig");
const mem = @import("alloc.zig");
const elements = @import("elements.zig");

fn stageGrow(lc: *types.LinkCache) ?*types.LinkStage {
    if (lc.count == lc.cap) {
        const ncap = if (lc.cap == 0) types.STAGE_START else lc.cap * 2;
        if (lc.stages) |old_ptr| {
            const old_sl = old_ptr[0..lc.cap];
            const new_sl = mem.reallocFn(types.LinkStage, old_sl, ncap) orelse return null;
            lc.stages = new_sl.ptr;
        } else {
            const new_sl = mem.alloc(types.LinkStage, ncap) orelse return null;
            lc.stages = new_sl.ptr;
        }
        lc.cap = ncap;
    }
    const s = &lc.stages.?[lc.count];
    s.* = .{};
    lc.count += 1;
    return s;
}

// final. If a later push triggers stageGrow → realloc, the pointer in
// order[] becomes invalid.
fn orderAppend(lc: *types.LinkCache, s: *types.LinkStage) bool {
    if (lc.order_count == lc.order_cap) {
        const ncap = if (lc.order_cap == 0) types.STAGE_START else lc.order_cap * 2;
        if (lc.order) |old_ptr| {
            const old_sl = old_ptr[0..lc.order_cap];
            const new_sl = mem.reallocFn(?*types.LinkStage, old_sl, ncap) orelse return false;
            lc.order = new_sl.ptr;
        } else {
            const new_sl = mem.alloc(?*types.LinkStage, ncap) orelse return false;
            @memset(new_sl, null);
            lc.order = new_sl.ptr;
        }
        lc.order_cap = ncap;
    }
    lc.order.?[lc.order_count] = s;
    lc.order_count += 1;
    return true;
}

fn pushCurveStage(lc: *types.LinkCache, ch: u8, cv: *types.Curve) bool {
    const s = stageGrow(lc) orelse return false;
    s.kind = .curve;
    s.in_ch = ch;
    s.out_ch = ch;
    // later frees the curve (shared TRC), this pointer becomes invalid.
    s.curve_samples = if (cv.samples) |sp| sp else null;
    s.curve_count = cv.count;
    return orderAppend(lc, s);
}

fn pushClutStage(lc: *types.LinkCache, cl: *types.Clut) bool {
    const s = stageGrow(lc) orelse return false;
    s.kind = .clut;
    s.in_ch = cl.in_ch;
    s.out_ch = cl.out_ch;
    s.clut_table = cl.table;
    var d: u8 = 0;
    while (d < cl.in_ch) : (d += 1) {
        s.grid[d] = cl.grid[d];
    }
    return orderAppend(lc, s);
}

fn pushMatrixStage(lc: *types.LinkCache, m: *types.Matrix) bool {
    const s = stageGrow(lc) orelse return false;
    s.kind = .matrix;
    s.in_ch = 3;
    s.out_ch = 3;
    // later frees the matrix (shared chad), this pointer becomes invalid.
    s.matrix = m;
    return orderAppend(lc, s);
}

fn pushChadStage(lc: *types.LinkCache, w: *types.Xyz) bool {
    const s = stageGrow(lc) orelse return false;
    s.kind = .chad;
    s.in_ch = 3;
    s.out_ch = 3;
    // repair reallocates the xyz, this pointer becomes invalid.
    s.white = w;
    return orderAppend(lc, s);
}

pub fn findTag(p: *const types.Profile, signature: u32) ?*types.Tag {
    if (p.tags == null) return null;
    var i: usize = 0;
    while (i < p.tag_count) : (i += 1) {
        if (p.tags.?[i].signature == signature) return &p.tags.?[i];
    }
    return null;
}

pub fn hasTag(p: *const types.Profile, signature: u32) bool {
    return findTag(p, signature) != null;
}

pub fn build(p: *types.Profile) bool {
    const lc = &p.link;

    // TRC curves for RGB profiles
    const trc_sigs = [3]u32{
        types.sig('r', 'T', 'R', 'C'),
        types.sig('g', 'T', 'R', 'C'),
        types.sig('b', 'T', 'R', 'C'),
    };

    if (p.device_space == .rgb) {
        for (trc_sigs, 0..) |ts, ch| {
            if (findTag(p, ts)) |t| {
                if (t.pool_idx >= 0) {
                    if (elements.poolAt(&p.pool, t.pool_idx)) |el| {
                        if (el.kind == .curve) {
                            if (!pushCurveStage(lc, @intCast(ch), el.data.curve))
                                return false;
                        }
                    }
                }
            }
        }
    }

    // AtoB LUT
    if (findTag(p, types.sig('A', '2', 'B', '0'))) |t| {
        if (t.pool_idx >= 0) {
            if (elements.poolAt(&p.pool, t.pool_idx)) |el| {
                if (el.kind == .lut) {
                    const lt = el.data.lut;
                    if (lt.clut >= 0) {
                        if (elements.poolAt(&p.pool, lt.clut)) |ce| {
                            if (ce.kind == .clut) {
                                if (!pushClutStage(lc, ce.data.clut))
                                    return false;
                                lc.in_ch = ce.data.clut.in_ch;
                                lc.out_ch = ce.data.clut.out_ch;
                            }
                        }
                    }
                }
            }
        }
    }

    // D2B0 multi-process element
    if (findTag(p, types.sig('D', '2', 'B', '0'))) |t| {
        if (t.pool_idx >= 0) {
            if (elements.poolAt(&p.pool, t.pool_idx)) |el| {
                if (el.kind == .mpet) {
                    const mp = el.data.mpet;
                    var si: u32 = 0;
                    while (si < mp.nstages) : (si += 1) {
                        const stage = &mp.stages[si];
                        if (stage.elem < 0) continue;
                        if (elements.poolAt(&p.pool, stage.elem)) |se| {
                            switch (stage.op) {
                                .curve => {
                                    if (se.kind == .curve) {
                                        if (!pushCurveStage(lc, 0, se.data.curve))
                                            return false;
                                    }
                                },
                                .matrix => {
                                    if (se.kind == .matrix) {
                                        if (!pushMatrixStage(lc, se.data.matrix))
                                            return false;
                                    }
                                },
                                .clut => {
                                    if (se.kind == .clut) {
                                        if (!pushClutStage(lc, se.data.clut))
                                            return false;
                                        // width, which may exceed the CLUT's actual width
                                        lc.stages.?[lc.count - 1].out_ch = mp.out_ch;
                                        lc.in_ch = se.data.clut.in_ch;
                                        lc.out_ch = mp.out_ch;
                                    }
                                },
                                .unknown => {},
                            }
                        }
                    }
                }
            }
        }
    }

    // Chromatic adaptation
    if (findTag(p, types.sig('w', 't', 'p', 't'))) |t| {
        if (t.pool_idx >= 0) {
            if (elements.poolAt(&p.pool, t.pool_idx)) |el| {
                if (el.kind == .xyz) {
                    p.white = el.data.xyz;
                    if (!pushChadStage(lc, el.data.xyz))
                        return false;
                }
            }
        }
    }

    lc.built = true;

    // "optimization." When close() calls linkFree on both, the stages
    p.link_inv.stages = lc.stages;
    p.link_inv.cap = lc.cap;
    p.link_inv.count = 0;

    return true;
}

pub fn linkFree(lc: *types.LinkCache) void {
    if (lc.stages) |ptr| {
        const sl = ptr[0..lc.cap];
        mem.freeSlice(types.LinkStage, sl);
        // If linkFree is called twice (once for link, once for link_inv
        // when they share stages due to a parse error), the second call
    }
    if (lc.order) |ptr| {
        const sl = ptr[0..lc.order_cap];
        mem.freeSlice(?*types.LinkStage, sl);
    }
    lc.order = null;
    lc.order_count = 0;
    lc.order_cap = 0;
    lc.count = 0;
    lc.cap = 0;
    lc.built = false;
}
