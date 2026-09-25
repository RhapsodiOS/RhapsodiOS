#ifndef RBUILD_VENDOR_H
#define RBUILD_VENDOR_H

#include "strutil.h"
#include "toolchain.h"

/* A vendored source: a pristine upstream tarball plus an ordered patch
   series, described by "<project>/apk/vendor". */
typedef struct {
    char *tarball;        /* required; relative to the project dir */
    char *directory;      /* required; name the extracted tree gets in SRCROOT */
    char *patches;        /* default "patches"; relative to the project dir */
    int patchlevel;       /* default 1; -p level passed to patch */
    int patches_explicit; /* 1 if "patches" was named in the file */
} Vendor;

void vendor_init(Vendor *v);
void vendor_free(Vendor *v);

/* Malloc'd "<source>/apk/vendor" if that file exists, else NULL. */
char *vendor_path(const char *source);

/* 0 on success; 1 if unreadable, tarball/directory is missing, or a value
   is invalid. */
int vendor_read(Vendor *v, const char *path);

/* Pushes every "*.patch" under "<srcdir>/<patches>" in ascending strcmp
   order. An absent default directory means no patches; an absent explicit
   one is an error. */
int vendor_list_patches(const Vendor *v, const char *srcdir, strlist *out);

/* Extracts <srcdir>/<tarball> into <srcroot>/<directory> (renaming the
   tarball's sole top-level entry), then applies the patch series.
   <srcroot>/<directory> must not already exist. */
int vendor_apply(const Vendor *v, const char *srcdir, const char *srcroot,
                 const Toolchain *tc);

#endif
