/*
 * whpx_nested_patch.c -- QEMU 11.0.0 for Windows (mingw-w64, GCC 15.2.0):
 * make WHPX nested-virt setup non-fatal, so kernel-irqchip=on works on hosts
 * that won't sub-delegate nesting (typical WSL2 / Hyper-V machine).
 *
 *   usage: whpx_nested_patch <qemu-system-x86_64[w].exe>   -> <name>_patched.exe
 *   build: gcc -std=c99 -O2 -o whpx_nested_patch whpx_nested_patch.c
 *   The input file is never modified.
 *
 * whpx_accel_init() in target/i386/whpx/whpx-all.c aborts when the host
 * refuses WHvPartitionPropertyCodeNestedVirtualization (hr = 0x80370302):
 *
 *     hr = whp_dispatch.WHvSetPartitionProperty(...);
 *     if (FAILED(hr)) {                                     <-- defused below
 *         error_report("WHPX: Failed to enable nested virtualization, ...");
 *         ret = -EINVAL; goto error;
 *     }
 *
 * Found via that string (file 0x1605488 -> VA 0x141606E88) and the cold block
 * referencing it inside whpx_accel_init (.text+0x36EA00 -> VA 0x14036FA00):
 *
 *   14036ffa0: ba 04 00 00 00       mov   $0x4,%edx    ; ...NestedVirtualization
 *   14036ffb5: ff 57 28             callq *0x28(%rdi)  ; WHvSetPartitionProperty
 *   14036ffb8: 85 c0                test  %eax,%eax    ; hr
 *   14036ffba: 0f 89 4c fc ff ff    jns   14036fc0c    ; <-- PATCH: !FAILED(hr)
 *   14036ffc2: 48 8d 0d bf 6e 29 01 lea   ...          # 141606e88 (the string)
 *
 * The mov $0x4 pins this to the nested-virt call, not the 0x100a/0x1009 ones.
 * Making the jump unconditional leaves the call intact and defuses only the
 * abort; hr is not faked. Same length, so nothing else shifts:
 *
 *   jns 14036fc0c  ->  jmp 14036fc0c ; nop
 *   rel32 = 0x14036FC0C - (0x14036FFBA + 5) = -0x3B3 = 0xFFFFFC4D
 *   file offset = 0x14036FFBA - 0x140001000 (.text VMA) + 0x600 (raw) = 0x36F5BA
 *
 * qemu-system-x86_64.exe and ...w.exe are the same code -- they differ only in
 * PE entry point, checksum and subsystem -- so one size/offset covers both.
 */

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define SIZE 83407949L
#define OFF  0x36F5BAL
#define LEN  6

static const unsigned char ORIG[LEN] = { 0x0f, 0x89, 0x4c, 0xfc, 0xff, 0xff };
static const unsigned char DONE[LEN] = { 0xe9, 0x4d, 0xfc, 0xff, 0xff, 0x90 };

int main(int argc, char **argv)
{
    unsigned char *b;
    char *out;
    FILE *f;
    size_t n;
    long sz;

    if (argc != 2) {
        fprintf(stderr, "usage: %s <qemu-system-x86_64[w].exe>\n", argv[0]);
        return 2;
    }

    if (!(f = fopen(argv[1], "rb"))) {
        fprintf(stderr, "error: cannot open '%s'\n", argv[1]);
        return 1;
    }
    fseek(f, 0, SEEK_END);
    sz = ftell(f);
    rewind(f);
    if (sz != SIZE) {
        fprintf(stderr, "error: '%s' is %ld bytes, expected %ld -- not a known "
                "build, refusing to patch\n", argv[1], sz, SIZE);
        fclose(f);
        return 1;
    }
    if (!(b = malloc(SIZE)) || fread(b, 1, SIZE, f) != SIZE) {
        fprintf(stderr, "error: cannot read '%s'\n", argv[1]);
        fclose(f);
        return 1;
    }
    fclose(f);

    if (!memcmp(b + OFF, DONE, LEN)) {
        printf("already patched\n");
    } else if (memcmp(b + OFF, ORIG, LEN)) {
        fprintf(stderr, "error: unexpected bytes at 0x%lX: "
                "%02x %02x %02x %02x %02x %02x -- refusing to patch\n", OFF,
                b[OFF], b[OFF+1], b[OFF+2], b[OFF+3], b[OFF+4], b[OFF+5]);
        return 1;
    } else {
        memcpy(b + OFF, DONE, LEN);
        printf("patched 0x%lX: 0f 89 4c fc ff ff -> e9 4d fc ff ff 90"
               "  (jns -> jmp 0x14036FC0C ; nop)\n", OFF);
    }

    /* <name>.exe -> <name>_patched.exe */
    n = strlen(argv[1]);
    if (n > 4 && argv[1][n-4] == '.' && tolower((unsigned char)argv[1][n-3]) == 'e'
              && tolower((unsigned char)argv[1][n-2]) == 'x'
              && tolower((unsigned char)argv[1][n-1]) == 'e') {
        n -= 4;
    }
    if (!(out = malloc(n + sizeof("_patched.exe")))) {
        fprintf(stderr, "error: out of memory\n");
        return 1;
    }
    sprintf(out, "%.*s_patched.exe", (int)n, argv[1]);

    if (!(f = fopen(out, "wb")) || fwrite(b, 1, SIZE, f) != SIZE || fclose(f)) {
        fprintf(stderr, "error: cannot write '%s'\n", out);
        return 1;
    }
    printf("wrote %s (input untouched)\n", out);
    return 0;
}
