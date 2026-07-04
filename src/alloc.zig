// alloc.zig - raw C malloc/free wrappers for ASan compatibility

extern fn malloc(size: usize) ?*anyopaque;
extern fn calloc(nmemb: usize, size: usize) ?*anyopaque;
extern fn @"realloc"(ptr: ?*anyopaque, size: usize) ?*anyopaque;
extern fn free(ptr: ?*anyopaque) void;

pub fn create(comptime T: type) ?*T {
    const p = calloc(1, @sizeOf(T)) orelse return null;
    return @ptrCast(@alignCast(p));
}

pub fn alloc(comptime T: type, n: usize) ?[]T {
    if (n == 0) return null;
    const p = calloc(n, @sizeOf(T)) orelse return null;
    const ptr: [*]T = @ptrCast(@alignCast(p));
    return ptr[0..n];
}

pub fn freeFn(comptime T: type, ptr: *T) void {
    free(@ptrCast(ptr));
}

pub fn freeSlice(comptime T: type, slice: []T) void {
    free(@ptrCast(slice.ptr));
}

pub fn reallocFn(comptime T: type, old: []T, new_len: usize) ?[]T {
    if (new_len == 0) return null;
    const new_slice = alloc(T, new_len) orelse return null;
    const copy_len = if (old.len < new_len) old.len else new_len;
    @memcpy(new_slice[0..copy_len], old[0..copy_len]);
    freeSlice(T, old);
    return new_slice;
}

pub fn dupeZ(s: []const u8) ?[*:0]u8 {
    const p = alloc(u8, s.len + 1) orelse return null;
    @memcpy(p[0..s.len], s);
    p[s.len] = 0;
    return @ptrCast(p.ptr);
}

pub fn freeZ(s: [*:0]u8) void {
    free(@ptrCast(s));
}
