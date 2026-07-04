#!/bin/bash
set -e

SRC=${SRC:-$(dirname "$0")}
OUT=${OUT:-/out}
CC=${CC:-clang}
CXX=${CXX:-clang++}
CFLAGS=${CFLAGS:--g -O1}
CXXFLAGS=${CXXFLAGS:-$CFLAGS}
LIB_FUZZING_ENGINE=${LIB_FUZZING_ENGINE:--fsanitize=fuzzer}

cd "$SRC"

# Ensure zig is available
if ! command -v zig &>/dev/null; then
    pip install ziglang --break-system-packages 2>/dev/null || pip install ziglang
fi

# Build the Zig library
zig build-lib -Mroot=src/root.zig -lc -OReleaseFast -femit-bin=libgamut.o
mv libgamut.o libgamut.a 2>/dev/null || true

# Compile __zig_probe_stack stub
$CC $CFLAGS -c zig_rt_stub.c -o zig_rt_stub.o

# Build each fuzzer harness
for fuzzer in parse_fuzzer query_fuzzer resolve_fuzzer; do
    $CXX $CXXFLAGS -Isrc \
        $LIB_FUZZING_ENGINE \
        -o "$OUT/$fuzzer" \
        "fuzz/${fuzzer}.cc" \
        libgamut.a zig_rt_stub.o -lm
done

# Copy seed corpus
for fuzzer in parse_fuzzer query_fuzzer resolve_fuzzer; do
    if [ -d "fuzz/corpus/${fuzzer}" ]; then
        mkdir -p "$OUT/${fuzzer}_corpus"
        cp fuzz/corpus/${fuzzer}/* "$OUT/${fuzzer}_corpus/" 2>/dev/null || true
    fi
done

rm -f libgamut.a zig_rt_stub.o
