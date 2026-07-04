const std = @import("std");
const gamut = @import("gamut");
const c = @cImport({});

pub fn main() void {
    // Use C's argc/argv via start
    const argv: [*][*:0]u8 = @ptrCast(std.os.argv.ptr);
    const argc = std.os.argv.len;
    
    if (argc < 2) return;
    runFuzz(std.mem.span(argv[1]));
}

fn runFuzz(path: []const u8) void {
    const file = std.fs.cwd().openFile(path, .{}) catch return;
    defer file.close();
    const data = file.reader().readAllAlloc(std.heap.c_allocator, 1 << 20) catch return;
    defer std.heap.c_allocator.free(data);
    if (data.len == 0) return;

    const p = gamut.openMemory(data.ptr, data.len) orelse return;
    defer gamut.closeProfile(p);

    var input = [_]f32{ 0.5, 0.5, 0.5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
    var output: [16]f32 = undefined;
    _ = gamut.applyProfile(p, &input, &output);
}
