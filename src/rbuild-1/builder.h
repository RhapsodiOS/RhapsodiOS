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

int builder_match_pkgfile(const char *filename, const char *name);
char *builder_exists(const Package *pkg, const char *type, const char *dir);
char *builder_resolve_dependency(const char *name, const strlist *repository);

#endif
