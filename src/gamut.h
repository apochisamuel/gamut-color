#ifndef GAMUT_H
#define GAMUT_H
#include <stdint.h>
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct gmt_profile gmt_profile;
gmt_profile *gmt_open_memory(const uint8_t *data, size_t size);
int gmt_apply(const gmt_profile *p, const float *input, float *output);
int gmt_colorant_index(const gmt_profile *p, const char *name);
void gmt_close(gmt_profile *p);
#ifdef __cplusplus
}
#endif
#endif
