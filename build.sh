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

# Install Zig 0.16 via pip (required — code uses 0.16 syntax)
pip install ziglang --break-system-packages 2>/dev/null || pip3 install ziglang --break-system-packages 2>/dev/null || pip install ziglang 2>/dev/null || true

# Find the pip-installed zig (prefer it over system zig which may be older)
ZIG=$(python3 -c "import ziglang,os;print(os.path.join(os.path.dirname(ziglang.__file__),'zig'))" 2>/dev/null || echo "zig")

# Verify zig version
echo "Using zig: $ZIG"
$ZIG version

# Build the Zig library as a static archive
$ZIG build-lib -Mroot=src/root.zig -lc -OReleaseFast -femit-bin=libgamut.o
# Rename to .a if needed (zig may output as .o or as archive)
if [ -f libgamut.o ]; then
    mv libgamut.o libgamut.a
fi

# Compile __zig_probe_stack stub (Zig compiler-rt not available when linking with clang++)
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
