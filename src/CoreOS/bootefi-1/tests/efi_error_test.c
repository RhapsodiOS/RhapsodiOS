/* Host test for EFI_ERROR().  Pure C: no firmware, no boot-2 headers.
 * Guards against the historical bug where EFI_ERROR was a macro that
 * evaluated its argument twice, so EFI_ERROR(gBS->Call(...)) ran the
 * firmware call twice whenever the first call returned a non-negative
 * status. */
#include <stdio.h>

#include "efi.h"

static int failures;
static int calls;

static void check(const char *name, int got, int want)
{
    if (got != want) {
        printf("FAIL %s: got %d want %d\n", name, got, want);
        failures++;
    } else {
        printf("ok   %s\n", name);
    }
}

static EFI_STATUS counted(EFI_STATUS s)
{
    calls++;
    return s;
}

int main(void)
{
    int result;

    calls = 0;
    result = EFI_ERROR(counted(EFI_SUCCESS));
    check("success: not an error", result, 0);
    check("success: evaluated once", calls, 1);

    calls = 0;
    result = EFI_ERROR(counted(EFI_BUFFER_TOO_SMALL));
    check("buffer_too_small: is an error", result != 0, 1);
    check("buffer_too_small: evaluated once", calls, 1);

    /* A positive warning code: not negative, but also not EFI_SUCCESS --
     * same truth table as the old macro. */
    calls = 0;
    result = EFI_ERROR(counted((EFI_STATUS)1));
    check("positive warning: is an error", result != 0, 1);
    check("positive warning: evaluated once", calls, 1);

    if (failures) {
        printf("%d failure(s)\n", failures);
        return 1;
    }
    printf("all passed\n");
    return 0;
}
