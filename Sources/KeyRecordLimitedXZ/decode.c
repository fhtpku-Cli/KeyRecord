#include "KeyRecordLimitedXZ.h"

/* The macOS SDK ships liblzma.5's link stub, but not its headers. This is the
 * public stream_buffer_decode ABI: https://tukaani.org/xz/liblzma-api/container_8h.html
 * Passing no allocator uses liblzma's own allocator; flags 0 rejects concatenation.
 */
struct lzma_allocator;
extern int lzma_stream_buffer_decode(uint64_t *, uint32_t, const struct lzma_allocator *,
                                    const uint8_t *, size_t *, size_t,
                                    uint8_t *, size_t *, size_t);

int keyrecord_decode_xz(const uint8_t *input, size_t input_size, uint8_t *output,
                        size_t output_size, size_t *written) {
    uint64_t memory_limit = 64 * 1024 * 1024;
    size_t consumed = 0;
    *written = 0;
    int result = lzma_stream_buffer_decode(&memory_limit, 0, NULL, input,
                                           &consumed, input_size, output, written, output_size);
    return result == 0 && consumed != input_size ? -1 : result;
}
