#ifndef GAMUT_H
#define GAMUT_H
#include <stdint.h>
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif

typedef struct gmt_profile gmt_profile;

/* Core API */
gmt_profile *gmt_open_memory(const uint8_t *data, size_t size);
int          gmt_apply(const gmt_profile *p, const float *input, float *output);
int          gmt_colorant_index(const gmt_profile *p, const char *name);
void         gmt_close(gmt_profile *p);

/* Analysis */
uint32_t gmt_profile_stats(const gmt_profile *p);
float    gmt_quality_score(const gmt_profile *p);
uint32_t gmt_tag_inspect(const gmt_profile *p);
float    gmt_transform_complexity(const gmt_profile *p);
uint32_t gmt_serialized_size(const gmt_profile *p);

/* Color science */
void  gmt_xyz_to_lab(const float *xyz, float *lab);
void  gmt_lab_to_srgb(const float *lab, float *rgb);
float gmt_delta_e2000(const float *lab1, const float *lab2);
float gmt_delta_e76(const float *lab1, const float *lab2);
void  gmt_bradford_d50_d65(const float *xyz_in, float *xyz_out);
float gmt_tonemap_reinhard(float l);
float gmt_tonemap_aces(float l);
float gmt_transfer_srgb(float x);
float gmt_srgb_gamma(float x);

/* Encoding */
void gmt_encode_lab16(const float *lab, uint16_t *out);
void gmt_decode_lab16(const uint16_t *enc, float *lab);

/* Hashing */
uint32_t gmt_fnv1a(const uint8_t *data, size_t size);
uint32_t gmt_crc32(const uint8_t *data, size_t size);
uint64_t gmt_fingerprint(const uint8_t *data, size_t size);

/* Curves */
void  gmt_gen_gamma_curve(float *samples, uint32_t count, float gamma);
void  gmt_gen_srgb_curve(float *samples, uint32_t count);
float gmt_curve_rms(const float *a, const float *b, uint32_t count);
float gmt_fit_gamma(const float *samples, uint32_t count);

/* Gamut mapping */
void gmt_gamut_map(float *lab, float max_chroma);

/* Print */
float gmt_dot_area(float coverage, float dot_gain);
void  gmt_neugebauer(const float *cmyk, float *rgb);
void  gmt_bpc_adjust(float *lab, float src_bk, float dst_bk);
void  gmt_proof_render(float *lab);

/* Illuminant */
float gmt_cct(float x, float y, float z);
void  gmt_cct_to_xy(float cct, float *x, float *y);

#ifdef __cplusplus
}
#endif
#endif
