/* zig_rt_stub.c - compiler-rt stubs for linking Zig objects with clang++
 *
 * When Zig object files are linked by clang++ instead of the Zig linker,
 * certain compiler-rt symbols from Zig's runtime are missing. This file
 * provides no-op stubs for them.
 */
void __zig_probe_stack(void) {}
