/* Host test for the UEFI loader's Boot Graphics rule.  Pure strings: no
 * firmware, no EFI types, no boot-2 headers. */
#include <stdio.h>

#include "efi_splash_rule.h"

static int failures;

static void check(const char *name, int got, int want)
{
    if (got != want) {
        printf("FAIL %s: got %d want %d\n", name, got, want);
        failures++;
    } else {
        printf("ok   %s\n", name);
    }
}

int main(void)
{
    check("default_verbose", efi_want_splash("rootdev=hd0a -v", 1, 0), 0);
    check("no_flags", efi_want_splash("rootdev=hd0a", 1, 0), 1);
    check("empty_string", efi_want_splash("", 1, 0), 1);
    check("graphics_off", efi_want_splash("rootdev=hd0a", 0, 0), 0);
    check("errors", efi_want_splash("rootdev=hd0a", 1, 1), 0);
    check("single_user", efi_want_splash("rootdev=hd0a -s", 1, 0), 1);
    check("combined_sv", efi_want_splash("rootdev=hd0a -sv", 1, 0), 0);
    check("separate_s_v", efi_want_splash("-s -v rootdev=hd0a", 1, 0), 0);
    check("tab_separated", efi_want_splash("rootdev=hd0a\t-v", 1, 0), 0);
    check("v_inside_word", efi_want_splash("rootdev=dev-v", 1, 0), 1);

    if (failures) {
        printf("%d failed\n", failures);
        return 1;
    }
    printf("all passed\n");
    return 0;
}
