#ifndef RBUILD_APK_H
#define RBUILD_APK_H
#include "toolchain.h"
int apk_validate(const char *path, const Toolchain *tc);
int apk_validate_readonly(const char *path, const Toolchain *tc);
int apk_validate_identity(const char *path, const Toolchain *tc,
                          const char *pkgname, const char *pkgver,
                          const char *architecture, int readonly);
int apk_extract(const char *path, const char *root, const Toolchain *tc);
int apk_extract_identity(const char *path, const char *root,
                         const Toolchain *tc, const char *pkgname,
                         const char *pkgver, const char *architecture);
/* root == NULL inspects and discards a private immutable stage. Exact cache
 * use requires canonical metadata; dependencies validate declared code first. */
int apk_use_arch(const char *path, const char *root, const Toolchain *tc,
                  const char *pkgname, const char *pkgver, unsigned required,
                  int object_collection, int allow_superset);
int apk_quarantine(const char *path);
#endif
