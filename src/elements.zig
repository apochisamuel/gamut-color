// elements.zig - element pool management and parse dispatch
//
// The element pool interns decoded profile elements by file offset.
// Tags that share an offset resolve to a single pooled element. This
// interning is the substrate for the cross-table pointer relationships
// that drive the library's memory lifecycle.

const std = @import("std");
const types = @import("types.zig");
const Reader = @import("reader.zig").Reader;
const mem = @import("alloc.zig");
const curves = @import("curves.zig");
const clut = @import("clut.zig");
const matrix = @import("matrix.zig");
const xyz = @import("xyz.zig");
const luts = @import("luts.zig");
const mpet = @import("mpet.zig");

pub fn poolFind(pool: *types.ElemPool, src_offset: u32) i32 {
    if (pool.items == null or pool.count == 0)
        return -1;
    var i: usize = 0;
    while (i < pool.count) : (i += 1) {
        if (pool.items.?[i]) |el| {
            if (el.src_offset == src_offset)
                return @intCast(i);
        }
    }
    return -1;
}

pub fn poolAt(pool: *types.ElemPool, index: i32) ?*types.Element {
    if (index < 0) return null;
    const idx: usize = @intCast(index);
    if (pool.items == null or idx >= pool.count) return null;
    return pool.items.?[idx];
}

pub fn poolAdd(pool: *types.ElemPool, el: *types.Element) bool {
    if (pool.count == pool.cap) {
        const ncap = if (pool.cap == 0) @as(usize, 16) else pool.cap * 2;
        if (pool.items) |old_ptr| {
            const old_slice = old_ptr[0..pool.cap];
            const new_slice = mem.reallocFn(?*types.Element, old_slice, ncap) orelse return false;
            pool.items = new_slice.ptr;
        } else {
            const new_slice = mem.alloc(?*types.Element, ncap) orelse return false;
            @memset(new_slice, null);
            pool.items = new_slice.ptr;
        }
        pool.cap = ncap;
    }
    pool.items.?[pool.count] = el;
    pool.count += 1;
    return true;
}

pub fn poolGet(pool: *types.ElemPool, src_offset: u32) ?*types.Element {
    const idx = poolFind(pool, src_offset);
    return poolAt(pool, idx);
}

pub fn parseElementAt(p: *types.Profile, offset: u32, size: u32) i32 {
    // Check if already interned
    const existing = poolFind(&p.pool, offset);
    if (existing >= 0) return existing;

    if (@as(usize, offset) + 4 > p.buf_size) return -1;
    if (offset < types.HEADER_SIZE) return -1;
    if (p.parse_depth >= 8) return -1;
    if (p.pool.count >= 512) return -1;

    p.parse_depth += 1;
    defer p.parse_depth -= 1;

    var r = Reader.initAt(p.buf.?, p.buf_size, offset);
    const type_sig = r.u32read();

    const el_opt: ?*types.Element = switch (type_sig) {
        types.sig('c', 'u', 'r', 'v') => curves.decode(&r, offset),
        types.sig('C', 'L', 'U', 'T') => clut.decode(&r, offset),
        types.sig('m', 'a', 't', 'x') => matrix.decode(&r, offset),
        types.sig('X', 'Y', 'Z', ' ') => xyz.decode(&r, offset),
        types.sig('l', 'u', 't', 'A') => luts.decode(p, &r, offset, size),
        types.sig('m', 'p', 'e', 't') => mpet.decode(p, &r, offset, size),
        else => null,
    };

    if (el_opt) |el| {
        if (poolAdd(&p.pool, el)) {
            return @as(i32, @intCast(p.pool.count - 1));
        }
    }
    return -1;
}

pub fn parseAll(p: *types.Profile) !void {
    if (p.tags == null or p.tag_count == 0) return;

    var i: usize = 0;
    while (i < p.tag_count) : (i += 1) {
        const t = &p.tags.?[i];
        if (t.offset == 0 or t.size == 0) continue;
        if (@as(usize, t.offset) + @as(usize, t.size) > p.buf_size) continue;

        const idx = parseElementAt(p, t.offset, t.size);
        t.pool_idx = idx;
    }
}

pub fn poolFree(pool: *types.ElemPool) void {
    if (pool.items == null) return;

    var i: usize = 0;
    while (i < pool.count) : (i += 1) {
        if (pool.items.?[i]) |el| {
            freeElement(el);
            pool.items.?[i] = null;
        }
    }

    const slice = pool.items.?[0..pool.cap];
    mem.freeSlice(?*types.Element, slice);
    pool.items = null;
    pool.count = 0;
    pool.cap = 0;
}

fn freeElement(el: *types.Element) void {
    switch (el.kind) {
        .curve => {
            const cv = el.data.curve;
            if (cv.samples) |s| {
                const sl = s[0..cv.count];
                mem.freeSlice(f32, sl);
            }
            mem.freeFn(types.Curve, cv);
        },
        .clut => {
            const cl = el.data.clut;
            if (cl.table) |t| {
                const total = @as(usize, cl.point_count) * cl.out_ch;
                const sl = t[0..total];
                mem.freeSlice(f32, sl);
            }
            mem.freeFn(types.Clut, cl);
        },
        .matrix => mem.freeFn(types.Matrix, el.data.matrix),
        .xyz => mem.freeFn(types.Xyz, el.data.xyz),
        .lut => mem.freeFn(types.Lut, el.data.lut),
        .mpet => {
            const mp = el.data.mpet;
            // pool element. The mpet_free attempts to release it, causing a
            if (mp.collapsed and mp.fold_owned != null) {
                const fe = mp.fold_owned.?;
                if (fe.kind == .clut) {
                    const cl = fe.data.clut;
                    if (cl.table) |t| {
                        const total = @as(usize, cl.point_count) * cl.out_ch;
                        mem.freeSlice(f32, t[0..total]);
                        cl.table = null;
                    }
                    mem.freeFn(types.Clut, cl);
                }
                mem.freeFn(types.Element, fe);
            }
            mem.freeFn(types.Mpet, mp);
        },
        .text => {
            mem.freeZ(el.data.text);
        },
        .none => {},
    }
    mem.freeFn(types.Element, el);
}
