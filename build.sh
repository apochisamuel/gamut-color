#!/bin/bash
# build.sh - Build fuzzer targets for ClusterFuzzLite
# Uses zig to compile the library, then links with the fuzzing engine.

set -e

SRC=${SRC:-$(dirname "$0")}
OUT=${OUT:-/out}
CC=${CC:-clang}
CXX=${CXX:-clang++}
CFLAGS=${CFLAGS:--g -O1}
CXXFLAGS=${CXXFLAGS:-$CFLAGS}
LIB_FUZZING_ENGINE=${LIB_FUZZING_ENGINE:--fsanitize=fuzzer}

cd "$SRC"

# Build the Zig library as a static archive
zig build-lib -Mroot=src/root.zig -lc -OReleaseFast -femit-bin=libgamut
mv libgamut libgamut.a

# Build each fuzzer harness
for fuzzer in parse_fuzzer query_fuzzer resolve_fuzzer; do
    $CXX $CXXFLAGS -Isrc \
        $LIB_FUZZING_ENGINE \
        -o "$OUT/$fuzzer" \
        "fuzz/${fuzzer}.cc" \
        libgamut.a -lm
done

# Copy seed corpus
for fuzzer in parse_fuzzer query_fuzzer resolve_fuzzer; do
    if [ -d "fuzz/corpus/${fuzzer}" ]; then
        cp -r "fuzz/corpus/${fuzzer}" "$OUT/${fuzzer}_corpus" 2>/dev/null || true
    fi
done

rm -f libgamut.a
