/* Host test for appending System.config "Kernel Flags" to the boot string.
 * Pure C: no firmware, no boot-2 headers. */
#include <stdio.h>
#include <string.h>

#include "efi_bootargs.h"

static int failures;

static void check(const char *name, const char *got, const char *want)
{
    if (strcmp(got, want) != 0) {
        printf("FAIL %s: got '%s' want '%s'\n", name, got, want);
        failures++;
    } else {
        printf("ok   %s\n", name);
    }
}

int main(void)
{
    char boot[160], small[20];

    strcpy(boot, "rootdev=hd0a -v");
    efi_append_boot_flags(boot, sizeof boot, "", 0);
    check("an empty value changes nothing", boot, "rootdev=hd0a -v");

    strcpy(boot, "rootdev=hd0a -v");
    efi_append_boot_flags(boot, sizeof boot, "rootdev=hd1aXXXX", 12);
    check("the value follows a space, and only len bytes are taken",
          boot, "rootdev=hd0a -v rootdev=hd1a");

    boot[0] = '\0';
    efi_append_boot_flags(boot, sizeof boot, "-s", 2);
    check("an empty boot string gets no leading space", boot, "-s");

    strcpy(small, "rootdev=hd0a -v");
    efi_append_boot_flags(small, sizeof small, "rootdev=hd1a", 12);
    check("truncated to fit, still terminated", small, "rootdev=hd0a -v roo");

    strcpy(small, "0123456789012345678");
    efi_append_boot_flags(small, sizeof small, "-s", 2);
    check("a full string is left alone", small, "0123456789012345678");

    if (failures) {
        printf("%d failure(s)\n", failures);
        return 1;
    }
    printf("all passed\n");
    return 0;
}
