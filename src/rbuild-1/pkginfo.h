#ifndef RBUILD_PKGINFO_H
#define RBUILD_PKGINFO_H

#include "package.h"
#include "toolchain.h"

/* 0 success, 1 missing file, 2 invalid (missing pkgname/pkgver or bad arch). */
int pkginfo_read(Package *p, const char *path);
int pkginfo_write(const Package *p, const char *path);
int pkginfo_build_apk(const char *root_dir, const char *out_apk,
                      const Toolchain *tc);

#endif
