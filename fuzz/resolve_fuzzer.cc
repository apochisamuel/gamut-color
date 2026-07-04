#include "../src/gamut.h"
#include <cstdint>
#include <cstddef>
extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    gmt_profile *p = gmt_open_memory(data, size);
    if (!p) return 0;

    for (int k = 0; k < 5; k++) {
        float v = (float)k / 4.0f;
        float in[16] = {v, v, v};
        float out[16];
        gmt_apply(p, in, out);

        float lab[3];
        gmt_xyz_to_lab(out, lab);
        gmt_delta_e76(lab, in);
    }

    gmt_tag_inspect(p);
    gmt_transform_complexity(p);
    gmt_fnv1a(data, size);

    gmt_close(p);
    return 0;
}
