const std = @import("std");
const gamut = @import("gamut");

pub fn main() !void {
    const args = try std.process.argsAlloc(std.heap.c_allocator);
    defer std.process.argsFree(std.heap.c_allocator, args);
    if (args.len < 2) return;
    const file = std.fs.cwd().openFile(args[1], .{}) catch return;
    defer file.close();
    const data = file.readToEndAlloc(std.heap.c_allocator, 1 << 20) catch return;
    defer std.heap.c_allocator.free(data);
    if (data.len == 0) return;
    
    const p = gamut.openMemory(data.ptr, data.len) orelse return;
    defer gamut.closeProfile(p);
    
    var k: u8 = 0;
    while (k < 5) : (k += 1) {
        const v: f32 = @as(f32, @floatFromInt(k)) / 4.0;
        var input = [_]f32{ v, v, v, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
        var output: [16]f32 = undefined;
        _ = gamut.applyProfile(p, &input, &output);
    }
}
