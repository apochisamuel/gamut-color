const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Static library
    const lib = b.addStaticLibrary(.{
        .name = "gamut",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    b.installArtifact(lib);

    // Fuzzer executables
    const fuzzer_names = [_][]const u8{ "parse_fuzzer", "query_fuzzer", "resolve_fuzzer" };
    for (fuzzer_names) |name| {
        const fuzz = b.addExecutable(.{
            .name = name,
            .root_module = b.createModule(.{
                .root_source_file = b.path(b.fmt("fuzz/{s}.zig", .{name})),
                .target = target,
                .optimize = optimize,
                .link_libc = true,
                .imports = &.{
                    .{ .name = "gamut", .module = &lib.root_module },
                },
            }),
        });
        b.installArtifact(fuzz);
    }
}
