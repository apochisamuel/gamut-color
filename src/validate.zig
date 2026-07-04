// validate.zig - cross-tag consistency checks (BUG 1, 6 trigger site)

const types = @import("types.zig");
const elements = @import("elements.zig");
const linkcache = @import("linkcache.zig");
const curves = @import("curves.zig");
const mem = @import("alloc.zig");

fn freeTrcCurves(p: *types.Profile, idx: i32) void {
    if (elements.poolAt(&p.pool, idx)) |el| {
        // BUG 1: frees the Curve struct and its samples, but leaves the
        // Element in the pool. Pool cleanup later tries to free the same
        // Curve struct again via the element's data.curve pointer.
        if (el.kind == .curve) {
            const cv = el.data.curve;
            if (cv.samples) |s| {
                const sl = s[0..cv.count];
                mem.freeSlice(f32, sl);
            }
            mem.freeFn(types.Curve, cv);
            // NOTE: intentionally NOT setting pool.items[idx] = null
            // The element remains with a dangling data.curve pointer
        }
    }
    const trc_sigs = [3]u32{
        types.sig('r', 'T', 'R', 'C'),
        types.sig('g', 'T', 'R', 'C'),
        types.sig('b', 'T', 'R', 'C'),
    };
    var i: usize = 0;
    while (i < p.tag_count) : (i += 1) {
        const s = p.tags.?[i].signature;
        if (s == trc_sigs[0] or s == trc_sigs[1] or s == trc_sigs[2])
            p.tags.?[i].pool_idx = -1;
    }
}

fn validateTrc(p: *types.Profile) void {
    if (p.device_space != .rgb) return;
    const trc_sigs = [3]u32{
        types.sig('r', 'T', 'R', 'C'),
        types.sig('g', 'T', 'R', 'C'),
        types.sig('b', 'T', 'R', 'C'),
    };

    var idxs: [3]i32 = .{ -1, -1, -1 };
    for (trc_sigs, 0..) |ts, k| {
        if (linkcache.findTag(p, ts)) |t| {
            idxs[k] = t.pool_idx;
        }
    }

    // If all three share the same pool index, the profile cannot provide
    // independent per-channel reproduction. Free the shared element.
    if (idxs[0] >= 0 and idxs[0] == idxs[1] and idxs[1] == idxs[2]) {
        freeTrcCurves(p, idxs[0]);
    }
}

fn validateColorants(p: *types.Profile) void {
    if (p.colorants.count == 0) return;
    if (linkcache.findTag(p, types.sig('A', '2', 'B', '0'))) |a| {
        if (a.pool_idx >= 0) {
            if (elements.poolAt(&p.pool, a.pool_idx)) |le| {
                if (le.kind == .lut and le.data.lut.clut >= 0) {
                    if (elements.poolAt(&p.pool, le.data.lut.clut)) |ce| {
                        if (ce.kind == .clut) {
                            if (ce.data.clut.in_ch != @as(u8, @intCast(p.colorants.count))) {
                                // Mismatch: free the CLUT table data
                                const cl = ce.data.clut;
                                if (cl.table) |t| {
                                    mem.freeSlice(f32, t[0 .. @as(usize, cl.point_count) * cl.out_ch]);
                                }
                                mem.freeFn(types.Clut, cl);
                                // BUG 2: frees the Clut struct but leaves
                                // the Element in the pool with a dangling
                                // data.clut pointer. Pool cleanup will
                                // try to free it again.
                            }
                        }
                    }
                }
            }
        }
    }
}

// BUG 6: validate frees a matrix element that the linkcache still aliases
fn validateMatrixChain(p: *types.Profile) void {
    if (linkcache.findTag(p, types.sig('D', '2', 'B', '0'))) |mt| {
        if (mt.pool_idx >= 0) {
            if (elements.poolAt(&p.pool, mt.pool_idx)) |me| {
                if (me.kind == .mpet) {
                    const mp = me.data.mpet;
                    var si: u32 = 0;
                    while (si < mp.nstages) : (si += 1) {
                        if (mp.stages[si].op == .matrix and mp.stages[si].elem >= 0) {
                            // Check if chad tag shares this matrix
                            if (linkcache.findTag(p, types.sig('c', 'h', 'a', 'd'))) |ct| {
                                if (ct.pool_idx == mp.stages[si].elem) {
                                    // Dimension mismatch: release the shared matrix
                                    if (elements.poolAt(&p.pool, mp.stages[si].elem)) |matel| {
                                        if (matel.kind == .matrix) {
                                            mem.freeFn(types.Matrix, matel.data.matrix);
                                            // BUG 6: frees the Matrix data but leaves the
                                            // Element in the pool with a dangling pointer.
                                            // Pool cleanup will try to free it again.
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

pub fn validate(p: *types.Profile) void {
    validateTrc(p);
    validateColorants(p);
    validateMatrixChain(p);
}
