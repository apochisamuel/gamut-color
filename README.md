# libgamut

A Zig library for parsing and evaluating custom ICC-style color profiles
in the `.gmt` binary format. Designed for embedded color management
pipelines where full ICC support is unnecessary.

## Format

The `.gmt` format is a simplified color profile container with a 128-byte
fixed header, a tag directory, and typed element bodies (tone curves,
multi-dimensional lookup tables, matrices, XYZ tristimulus values, and
multi-process elements). Tags may share element bodies via offset interning.

## Architecture

The processing pipeline has ten phases:

1. **Header** (`header.zig`): Parse magic, version, device space, PCS.
2. **Tag directory** (`tagtable.zig`): Read tag signatures, offsets, sizes.
3. **Element pool** (`elements.zig`): Decode and intern elements by offset.
4. **Curves** (`curves.zig`): Tone reproduction curve decode and evaluation.
5. **CLUTs** (`clut.zig`): Multi-dimensional color lookup table decode.
6. **Matrices** (`matrix.zig`): 3×3 affine matrix decode.
7. **LUTs/MPETs** (`luts.zig`, `mpet.zig`): Composite element decode.
8. **Link cache** (`linkcache.zig`): Assemble the transform pipeline.
9. **Checksum** (`checksum.zig`): Profile ID verification and repair.
10. **Validate** (`validate.zig`): Cross-tag consistency checks.

Additional library modules provide color science utilities:

- **Color spaces** (`colorspace.zig`): XYZ ↔ Lab ↔ sRGB transforms, Delta E.
- **Interpolation** (`interp.zig`): Tetrahedral, bilinear, nearest CLUT interpolation.
- **Chromatic adaptation** (`adapt.zig`, `chromadapt.zig`): Bradford, CAT02, von Kries.
- **Rendering intents** (`intent.zig`): Perceptual, relative, saturation, absolute.
- **Tone mapping** (`tonemap.zig`): Reinhard, ACES, filmic, PQ, HLG.
- **Transfer functions** (`transfer.zig`): sRGB, BT.709, BT.2020, ProPhoto, log.
- **Encoding** (`encoding.zig`): ICC PCS 16-bit Lab/XYZ encode/decode.
- **Serialization** (`serialize.zig`): Write parsed profiles back to binary.
- **Statistics** (`stats.zig`): Profile summary and quality metrics.
- **Gamut mapping** (`gammap.zig`): Chroma compression, SGCK, lightness-preserving.
- **Delta E** (`deltae.zig`): CIE DE2000 and CMC color difference.
- **Spectral** (`spectral.zig`): SPD handling and standard observer integration.
- **Print simulation** (`printer.zig`, `halftone.zig`, `proofing.zig`): Neugebauer, dot gain.
- **Analysis** (`taginspect.zig`, `profquality.zig`, `gradient.zig`, `uniformity.zig`).

## Public API

```c
gmt_profile *gmt_open_memory(const uint8_t *data, size_t size);
int          gmt_apply(const gmt_profile *p, const float *in, float *out);
int          gmt_colorant_index(const gmt_profile *p, const char *name);
void         gmt_close(gmt_profile *p);
```

## Building

Requires Zig (0.13+) and a C/C++ compiler with libFuzzer support.

```bash
# Build the library
zig build-lib -Mroot=src/root.zig -lc -OReleaseFast -femit-bin=libgamut.o

# Build fuzzer
clang++ -fsanitize=address,fuzzer -o parse_fuzzer fuzz/parse_fuzzer.cc libgamut.a
```

## Fuzz targets

Three fuzzer harnesses exercise different API surfaces:

- `parse_fuzzer`: Opens a profile from fuzzed input, applies a transform, closes.
- `query_fuzzer`: Opens, queries colorant names, applies, closes.
- `resolve_fuzzer`: Opens, evaluates the transform at multiple sample points, closes.

## License

MIT
