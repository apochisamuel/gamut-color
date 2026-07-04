#!/bin/bash -eu
cd "$SRC"

$CC -c zig_probe_stack.c -o zig_probe_stack.o

for fuzzer_src in fuzz/*_fuzz.zig; do
    base=$(basename "$fuzzer_src" _fuzz.zig)
    out_name="${base}_fuzzer"

    zig build-obj \
        --dep gamut \
        -Mroot="$fuzzer_src" \
        -Mgamut=src/root.zig \
        -OReleaseFast \
        -lc \
        -femit-bin="${out_name}.o"

    $CXX "${out_name}.o" zig_probe_stack.o $LIB_FUZZING_ENGINE \
        -o "$OUT/$out_name" \
        -fsanitize=address \
        -lc -lstdc++ -lm -lpthread

    rm -f "${out_name}.o"
done

rm -f zig_probe_stack.o

# Copy seed corpus
for fuzzer_src in fuzz/*_fuzz.zig; do
    base=$(basename "$fuzzer_src" _fuzz.zig)
    out_name="${base}_fuzzer"
    if [ -d "fuzz/corpus/${out_name}" ]; then
        mkdir -p "$OUT/${out_name}_corpus"
        cp fuzz/corpus/${out_name}/* "$OUT/${out_name}_corpus/" 2>/dev/null || true
    fi
done
