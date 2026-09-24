/*
 * efi_splash_rule.c -- boot-2's Boot Graphics rule, adapted to a loader
 * with no boot prompt.  boot-2 (src/boot-2/i386/boot2/boot.c) shows the
 * panel when "Boot Graphics" is Yes, nothing was typed at the prompt and
 * no errors were reported; typing -v is how a user asks for text.  Here
 * the compile-time boot string stands in for the typed line.  Pure: no
 * EFI or boot-2 dependencies, host-tested by tests/efi_splash_rule_test.c.
 */
#include "efi_splash_rule.h"

static int is_space(char c)
{
    return c == ' ' || c == '\t';
}

static int has_verbose_flag(const char *s)
{
    while (*s) {
        while (is_space(*s))
            s++;
        if (*s == '-') {
            for (s++; *s && !is_space(*s); s++)
                if (*s == 'v')
                    return 1;
        } else {
            while (*s && !is_space(*s))
                s++;
        }
    }
    return 0;
}

int efi_want_splash(const char *bootString, int bootGraphics, int errors)
{
    return bootGraphics && errors == 0 && !has_verbose_flag(bootString);
}
