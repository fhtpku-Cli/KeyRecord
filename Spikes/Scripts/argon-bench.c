#include "argon2.h"
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static double milliseconds(struct timespec start, struct timespec end) {
    return (double)(end.tv_sec - start.tv_sec) * 1000.0 + (double)(end.tv_nsec - start.tv_nsec) / 1000000.0;
}

int main(int argc, char **argv) {
    uint32_t memory, iterations, parallelism;
    uint8_t output[32];
    const uint8_t password[] = "phase0-bounded-password";
    const uint8_t salt[16] = {0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15};
    struct timespec start, end;
    if (argc != 4) return 64;
    memory = (uint32_t)strtoul(argv[1], NULL, 10);
    iterations = (uint32_t)strtoul(argv[2], NULL, 10);
    parallelism = (uint32_t)strtoul(argv[3], NULL, 10);
    clock_gettime(CLOCK_MONOTONIC_RAW, &start);
    if (argon2id_hash_raw(iterations, memory, parallelism, password, sizeof(password) - 1, salt, sizeof(salt), output, sizeof(output)) != ARGON2_OK) return 1;
    clock_gettime(CLOCK_MONOTONIC_RAW, &end);
    printf("%.3f\n", milliseconds(start, end));
    memset(output, 0, sizeof(output));
    return 0;
}
