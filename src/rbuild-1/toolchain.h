#ifndef RBUILD_TOOLCHAIN_H
#define RBUILD_TOOLCHAIN_H

#include "strutil.h"

typedef struct {
    char *profile;
    char *build_cc;
    char *target_cc;
    char *target_arch;
    char *target_ar;
    char *target_ranlib;
    char *make;
    char *make_flags;
    char *make_flags_ready;
    char *shell;
    char *tar;
    char *archive_create;
    char *archive_create_flags;
    char *gzip;
    char *rsync;
    char *path;
    char *arch_flags;
    char *cpp_flags;
    char *ld_flags;
    char *ln;
} Toolchain;

void toolchain_init(Toolchain *tc);
void toolchain_free(Toolchain *tc);
int toolchain_load(Toolchain *tc, const char *path);
int toolchain_validate(const Toolchain *tc);
void toolchain_expand_words(const char *value, const char *sysroot, strlist *out);

#endif
