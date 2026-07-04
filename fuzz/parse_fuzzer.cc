#include "../src/gamut.h"
#include <cstdint>
#include <cstddef>
extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    gmt_profile *p = gmt_open_memory(data, size);
    if (!p) return 0;
    float in[16] = {0.5f,0.5f,0.5f};
    float out[16];
    gmt_apply(p, in, out);
    gmt_close(p);
    return 0;
}
