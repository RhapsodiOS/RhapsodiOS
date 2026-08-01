#ifndef RBUILD_APK_H
#define RBUILD_APK_H
#include "toolchain.h"
int apk_validate(const char *path, const Toolchain *tc);
int apk_extract(const char *path, const char *root, const Toolchain *tc);
int apk_quarantine(const char *path);
#endif
