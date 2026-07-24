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

void builder_getparams(const char *projectname, Params *out);
void builder_canonparams(Params *p, const char *cwd);
void builder_chrootparams(const Params *in, const char *buildroot, Params *out);

void builder_buildflags(const Params *params, const char *target, strlist *out,
                        int native);
void builder_buildcmd(const Params *chroot_params, const Params *build_params,
                      const char *target, strlist *out, int native);

int builder_scan_dir(const char *source, Package *pkg, Params *params);
int builder_scan(const char *type, const char *source, Package *pkg, Params *params);

int builder_makeroot(const Package *pkg, const char *buildroot,
                     const strlist *repository);

int builder_setupdirs(const Package *pkg, const Params *params,
                      const char *srcname, const char *srctype,
                      const strlist *repository, int native);

int builder_buildpackage(const Package *spkg, const Params *params,
                         const char *target);
int builder_harvest_objects(const Package *pkg, const Params *params,
                            const Params *bparams, int native);

int builder_build(const char *srctype, const char *srcname,
                  const strlist *repository, const char *target,
                  const char *dstdir, int clean, int native);

#endif
