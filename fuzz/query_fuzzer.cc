#include "../src/gamut.h"
#include <cstdint>
#include <cstddef>
extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    gmt_profile *p = gmt_open_memory(data, size);
    if (!p) return 0;

    gmt_colorant_index(p, "red");
    gmt_colorant_index(p, "green");
    gmt_colorant_index(p, "blue");

    float in[16] = {0.5f, 0.5f, 0.5f};
    float out[16];
    gmt_apply(p, in, out);

    gmt_profile_stats(p);
    gmt_quality_score(p);

    float lab[3];
    gmt_xyz_to_lab(out, lab);
    gmt_gamut_map(lab, 100.0f);
    gmt_proof_render(lab);

    gmt_close(p);
    return 0;
}
