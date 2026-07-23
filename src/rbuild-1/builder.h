#ifndef RBUILD_BUILDER_H
#define RBUILD_BUILDER_H

#include "strutil.h"
#include "package.h"

typedef struct {
    char *BUILDROOT;
    char *SRCROOT;
    char *OBJROOT;
    char *SYMROOT;
    char *DSTROOT;
    char *HDRROOT;
    char *LIBCOBJROOT;
    char *LOGFILE;
    char *SUBLIBROOTS;
    char *PACKAGEROOT;
    char *SRCDIR;
    char *PACKAGEDIR;
} Params;

void params_init(Params *p);
void params_free(Params *p);

void builder_dir2name(const char *srcname, char **pbase, char **pname, char **rev);
char *builder_pkgname(const char *pbase, const char *revision);

#endif
