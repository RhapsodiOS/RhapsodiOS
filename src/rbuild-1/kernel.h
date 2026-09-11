#ifndef RBUILD_KERNEL_H
#define RBUILD_KERNEL_H

#include "strutil.h"

#define KERNEL_DRIVERS_BLACKLIST_REL "rbuild-1/kernel-drivers-blacklist.json"

int kernel_arch_safe(const char *arch);
int kernel_core_packages(const char *arch, strlist *out);
int kernel_scan_drivers(const char *srcdir, const char *arch, strlist *out);
int kernel_load_blacklist(const char *path, strlist *out);
int kernel_driver_blacklisted(const strlist *skip, const char *rel);

#endif
