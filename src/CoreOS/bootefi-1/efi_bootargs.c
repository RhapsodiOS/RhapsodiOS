#include "efi_bootargs.h"

void efi_append_boot_flags(char *boot, unsigned int cap, const char *flags,
                           int len)
{
    unsigned int n = 0;
    int i;

    if (len <= 0 || cap == 0)
        return;
    while (n < cap - 1 && boot[n] != '\0')
        n++;
    if (n > 0 && n < cap - 1)
        boot[n++] = ' ';
    for (i = 0; i < len && n < cap - 1; i++)
        boot[n++] = flags[i];
    boot[n] = '\0';
}
