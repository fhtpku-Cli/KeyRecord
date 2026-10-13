#include <stddef.h>
#include <stdint.h>

int keyrecord_decode_xz(const uint8_t *input, size_t input_size, uint8_t *output,
                        size_t output_size, size_t *written);
