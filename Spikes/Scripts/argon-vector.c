#include "argon2.h"
#include <stdint.h>
#include <stdio.h>
#include <string.h>

int main(void) {
    uint8_t password[32], salt[16], secret[8], ad[12], output[32];
    const uint8_t expected[32] = {
        0x0d,0x64,0x0d,0xf5,0x8d,0x78,0x76,0x6c,0x08,0xc0,0x37,0xa3,0x4a,0x8b,0x53,0xc9,
        0xd0,0x1e,0xf0,0x45,0x2d,0x75,0xb6,0x5e,0xb5,0x25,0x20,0xe9,0x6b,0x01,0xe6,0x59
    };
    argon2_context context;
    memset(password, 1, sizeof(password)); memset(salt, 2, sizeof(salt));
    memset(secret, 3, sizeof(secret)); memset(ad, 4, sizeof(ad)); memset(&context, 0, sizeof(context));
    context.out = output; context.outlen = sizeof(output); context.pwd = password; context.pwdlen = sizeof(password);
    context.salt = salt; context.saltlen = sizeof(salt); context.secret = secret; context.secretlen = sizeof(secret);
    context.ad = ad; context.adlen = sizeof(ad); context.t_cost = 3; context.m_cost = 32;
    context.lanes = 4; context.threads = 4; context.version = ARGON2_VERSION_13;
    context.flags = ARGON2_FLAG_CLEAR_PASSWORD | ARGON2_FLAG_CLEAR_SECRET;
    if (argon2id_ctx(&context) != ARGON2_OK || memcmp(output, expected, sizeof(output)) != 0) return 1;
    puts("PHC_RFC9106_VECTOR=PASS tag=0d640df58d78766c08c037a34a8b53c9d01ef0452d75b65eb52520e96b01e659");
    return 0;
}
