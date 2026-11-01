/* efi_splash_rule.h -- when the UEFI loader shows the Boot Graphics panel. */
#ifndef EFI_SPLASH_RULE_H
#define EFI_SPLASH_RULE_H

/* Non-zero when the panel should be shown: the "Boot Graphics" config key
 * is set, no errors have been reported, and bootString carries no -v
 * flag (a '-' word containing 'v', as in "-v" or "-sv"). */
int efi_want_splash(const char *bootString, int bootGraphics, int errors);

#endif
