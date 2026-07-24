#ifndef RBUILD_PKGINFO_H
#define RBUILD_PKGINFO_H

#include "package.h"

int pkginfo_write(const Package *p, const char *path);
int pkginfo_build_apk(const char *root_dir, const char *out_apk);

#endif
