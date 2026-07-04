#include "../src/gamut.h"
#include <cstdint>
#include <cstddef>
extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    gmt_profile *p = gmt_open_memory(data, size);
    if (!p) return 0;

    /* Exercise core transform */
    float in[16] = {0.5f, 0.5f, 0.5f};
    float out[16];
    gmt_apply(p, in, out);

    /* Exercise analysis modules */
    gmt_profile_stats(p);
    gmt_quality_score(p);
    gmt_tag_inspect(p);
    gmt_transform_complexity(p);
    gmt_serialized_size(p);

    /* Exercise color science on output */
    float lab[3], srgb[3];
    gmt_xyz_to_lab(out, lab);
    gmt_lab_to_srgb(lab, srgb);
    gmt_delta_e2000(lab, in);
    gmt_bradford_d50_d65(out, srgb);

    /* Exercise hash on input */
    gmt_fnv1a(data, size);
    gmt_crc32(data, size);
    gmt_fingerprint(data, size);

    gmt_close(p);
    return 0;
}
