#ifndef _BOOTEFI_EFI_BOOTARGS_H_
#define _BOOTEFI_EFI_BOOTARGS_H_

/* Append a System.config "Kernel Flags" value to the boot string, after a
 * space.  The kernel's getargs() keeps the last rootdev= it sees, so this
 * lets the config override the loader's compiled-in default -- where
 * boot2's prepend (boot.c) exists so a typed boot: line overrides the
 * config.  `flags` is getValueForKey()'s value: `len` bytes, not
 * NUL-terminated.  Truncates to fit `cap` bytes including the NUL; a
 * value of length 0 changes nothing. */
void efi_append_boot_flags(char *boot, unsigned int cap, const char *flags,
                           int len);

#endif /* _BOOTEFI_EFI_BOOTARGS_H_ */
