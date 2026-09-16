#ifndef RBUILD_BUILDER_H
#define RBUILD_BUILDER_H

#include "strutil.h"
#include "package.h"
#include "toolchain.h"

typedef struct {
    int clean;
    int bootstrap;
    const char *sysroot;
    const char *state_dir;
    const Toolchain *toolchain;
    int force;
    unsigned operation_arch; /* zero for ordinary builds */
    unsigned effective_arch; /* zero until the source is resolved */
} BuildOptions;

void build_options_init(BuildOptions *opt);
/* Missing is successful with *exists == 0; invalid cache is quarantined.
 * Dry-run reports inspection and leaves every cache unavailable. */
int builder_cache_status(const char *path, const Toolchain *tc,
                          const char *name, const char *version,
                          unsigned required, int objects, int *exists);
int builder_resolve_architecture(Package *pkg, BuildOptions *opt);

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
                        const BuildOptions *opt);
void builder_buildcmd(const Params *chroot_params, const Params *build_params,
                      const char *target, strlist *out,
                      const BuildOptions *opt);

int builder_scan_dir(const char *source, Package *pkg, Params *params);
int builder_scan(const char *type, const char *source, Package *pkg, Params *params);

int builder_makeroot(const Package *pkg, const char *buildroot,
                     const strlist *repository, const Toolchain *tc);

int builder_setupdirs(const Package *pkg, const Params *params,
                      const char *srcname, const char *srctype,
                      const strlist *repository, const BuildOptions *opt);

/* Probe resolved slices in private OBJROOT directories. Bootstrap links a
 * CPU only when sysroot crt1.o and ld_flags_ready System contain that slice. */
int builder_probe_toolchain(const Params *params, const Params *bparams,
                            const BuildOptions *opt);

int builder_buildpackage(const Package *spkg, const Params *params,
                         const char *target, const BuildOptions *opt);
int builder_relativize_symlinks(const char *root);
int builder_harvest_objects(const Package *pkg, const Params *params,
                            const Params *bparams, const BuildOptions *opt);

int builder_build(const char *srctype, const char *srcname,
                  const strlist *repository, const char *target,
                  const char *dstdir, const BuildOptions *opt);

#endif
