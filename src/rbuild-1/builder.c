#include "builder.h"
#include "exec.h"
#include <string.h>
#include <ctype.h>
#include <stdlib.h>
#include <stdio.h>
#include <dirent.h>
#include <sys/stat.h>

void params_init(Params *p) { memset(p, 0, sizeof(*p)); }

void params_free(Params *p) {
    free(p->BUILDROOT); free(p->SRCROOT); free(p->OBJROOT); free(p->SYMROOT);
    free(p->DSTROOT); free(p->HDRROOT); free(p->LIBCOBJROOT); free(p->LOGFILE);
    free(p->SUBLIBROOTS); free(p->PACKAGEROOT); free(p->SRCDIR); free(p->PACKAGEDIR);
    memset(p, 0, sizeof(*p));
}

char *builder_pkgname(const char *pbase, const char *revision) {
    char *name = xstrdup(pbase);
    char *out;
    char *q;
    for (q = name; *q; q++) if (*q == '_') *q = '-';
    if (strcmp(name, "appkit") == 0) {
        out = xstrdup("appkit-old");
        free(name);
        name = out;
    } else if (strcmp(name, "ssh") == 0) {
        if (revision && revision[0] == '1') out = xstrdup("ssh1");
        else out = xstrdup("ssh2");
        free(name);
        name = out;
    }
    str_lowercase(name);
    return name;
}

void builder_dir2name(const char *srcname, char **pbase, char **pname, char **rev) {
    /* strip trailing slashes */
    char *tmp = xstrdup(srcname);
    size_t n = strlen(tmp);
    char *base, *slash, *dash;
    char *revision = 0;

    while (n > 0 && tmp[n - 1] == '/') tmp[--n] = '\0';
    slash = strrchr(tmp, '/');
    base = xstrdup(slash ? slash + 1 : tmp);
    free(tmp);

    /* find trailing "-<[0-9.]+>" */
    dash = strrchr(base, '-');
    if (dash) {
        const char *r = dash + 1;
        int ok = (*r != '\0');
        const char *s;
        for (s = r; *s; s++) {
            if (!isdigit((unsigned char) *s) && *s != '.') { ok = 0; break; }
        }
        if (ok) {
            revision = xstrdup(r);
            *dash = '\0';   /* strip suffix from base */
        }
    }

    *pbase = base;
    *rev = revision;
    *pname = builder_pkgname(base, revision);
}

int builder_match_pkgfile(const char *filename, const char *name) {
    size_t nl = strlen(name);
    if (strncmp(filename, name, nl) != 0) return 0;
    if (filename[nl] != '-') return 0;
    if (!isdigit((unsigned char) filename[nl + 1])) return 0;
    return str_has_suffix(filename, ".apk");
}

static char *scan_dir_for(const char *dir, const char *name) {
    DIR *d = opendir(dir);
    struct dirent *de;
    char *found = 0;
    if (!d) return 0;
    while ((de = readdir(d)) != 0) {
        if (strcmp(de->d_name, ".") == 0 || strcmp(de->d_name, "..") == 0)
            continue;
        if (builder_match_pkgfile(de->d_name, name)) {
            found = path_join(dir, de->d_name);
            break;
        }
    }
    closedir(d);
    return found;
}

char *builder_resolve_dependency(const char *name, const strlist *repository) {
    size_t i;
    for (i = 0; i < repository->count; i++) {
        char *hit = scan_dir_for(repository->items[i], name);
        if (hit) return hit;
    }
    return 0;
}

char *builder_exists(const Package *pkg, const char *type, const char *dir) {
    if (strcmp(type, "any") == 0) {
        return scan_dir_for(dir, pkg->package);
    } else if (strcmp(type, "exact") == 0) {
        char *canon = package_canon_name(pkg);
        char *base = str_cats(canon, ".apk", (char *)0);
        char *full = path_join(dir, base);
        struct stat st;
        free(canon); free(base);
        if (stat(full, &st) == 0) return full;
        free(full);
        return 0;
    }
    fprintf(stderr, "rbuild: invalid match type \"%s\"\n", type);
    return 0;
}

/* Return env value if set and non-empty, else NULL (mirrors Perl
   defined($ENV{X} && $ENV{X})). */
static const char *env_or_null(const char *name) {
    const char *v = getenv(name);
    if (v && v[0]) return v;
    return 0;
}

static char *default_root(const char *buildroot, const char *project,
                          const char *suffix) {
    /* "<buildroot>/<project>.roots/<project><suffix>" */
    return str_cats(buildroot, "/", project, ".roots/", project, suffix, (char *)0);
}

void builder_getparams(const char *project, Params *out) {
    const char *buildroot = env_or_null("BUILDIT_DIR");
    const char *ov;
    if (!buildroot) buildroot = "/private/tmp/roots";

    out->BUILDROOT = default_root(buildroot, project, ".root");
    if ((ov = env_or_null("BUILDROOT")) != 0) { free(out->BUILDROOT); out->BUILDROOT = xstrdup(ov); }

    out->SRCROOT = default_root(buildroot, project, "");
    if ((ov = env_or_null("SRCROOT")) != 0) { free(out->SRCROOT); out->SRCROOT = xstrdup(ov); }

    out->OBJROOT = default_root(buildroot, project, ".obj");
    if ((ov = env_or_null("OBJROOT")) != 0) { free(out->OBJROOT); out->OBJROOT = xstrdup(ov); }

    out->SYMROOT = default_root(buildroot, project, ".sym");
    if ((ov = env_or_null("SYMROOT")) != 0) { free(out->SYMROOT); out->SYMROOT = xstrdup(ov); }

    out->DSTROOT = default_root(buildroot, project, ".dst");
    if ((ov = env_or_null("DSTROOT")) != 0) { free(out->DSTROOT); out->DSTROOT = xstrdup(ov); }

    out->HDRROOT = default_root(buildroot, project, ".hdr");
    if ((ov = env_or_null("HDRROOT")) != 0) { free(out->HDRROOT); out->HDRROOT = xstrdup(ov); }

    out->LIBCOBJROOT = default_root(buildroot, project, ".cobj");
    if ((ov = env_or_null("LIBCOBJROOT")) != 0) { free(out->LIBCOBJROOT); out->LIBCOBJROOT = xstrdup(ov); }

    out->LOGFILE = default_root(buildroot, project, ".log");
    if ((ov = env_or_null("LOGFILE")) != 0) { free(out->LOGFILE); out->LOGFILE = xstrdup(ov); }

    out->SUBLIBROOTS = xstrdup("/usr/local/lib/objs");
    if ((ov = env_or_null("SUBLIBROOTS")) != 0) { free(out->SUBLIBROOTS); out->SUBLIBROOTS = xstrdup(ov); }

    out->PACKAGEROOT = default_root(buildroot, project, ".pkg");
    if ((ov = env_or_null("PACKAGEROOT")) != 0) { free(out->PACKAGEROOT); out->PACKAGEROOT = xstrdup(ov); }
}

static void canon_one(char **field, const char *cwd) {
    if (*field && (*field)[0] != '/') {
        char *joined = path_join(cwd, *field);
        free(*field);
        *field = joined;
    }
}

void builder_canonparams(Params *p, const char *cwd) {
    canon_one(&p->BUILDROOT, cwd);
    canon_one(&p->SRCROOT, cwd);
    canon_one(&p->OBJROOT, cwd);
    canon_one(&p->SYMROOT, cwd);
    canon_one(&p->DSTROOT, cwd);
    canon_one(&p->HDRROOT, cwd);
    canon_one(&p->LIBCOBJROOT, cwd);
    canon_one(&p->PACKAGEROOT, cwd);
    canon_one(&p->LOGFILE, cwd);
    canon_one(&p->SUBLIBROOTS, cwd);
    canon_one(&p->SRCDIR, cwd);
    canon_one(&p->PACKAGEDIR, cwd);
}

static char *prefixed(const char *buildroot, const char *path) {
    if (!path) return 0;
    return str_cats(buildroot, path, (char *)0);
}

void builder_chrootparams(const Params *in, const char *buildroot, Params *out) {
    char *br = xstrdup(buildroot);
    size_t n = strlen(br);
    while (n > 0 && br[n - 1] == '/') br[--n] = '\0';

    out->SRCROOT = prefixed(br, in->SRCROOT);
    out->OBJROOT = prefixed(br, in->OBJROOT);
    out->SYMROOT = prefixed(br, in->SYMROOT);
    out->DSTROOT = prefixed(br, in->DSTROOT);
    out->HDRROOT = prefixed(br, in->HDRROOT);
    out->LIBCOBJROOT = prefixed(br, in->LIBCOBJROOT);
    out->LOGFILE = prefixed(br, in->LOGFILE);
    out->SUBLIBROOTS = prefixed(br, in->SUBLIBROOTS);
    out->PACKAGEROOT = prefixed(br, in->PACKAGEROOT);
    out->BUILDROOT = xstrdup(br);
    free(br);
}

static const char *cflags[] = {
    "-Dunix", "-D__unix", "-D__unix__",
    "-DNX_COMPILER_RELEASE_3_0=300", "-DNX_COMPILER_RELEASE_3_1=310",
    "-DNX_COMPILER_RELEASE_3_2=320", "-DNX_COMPILER_RELEASE_3_3=330",
    "-DNX_CURRENT_COMPILER_RELEASE=520",
    "-DNS_TARGET=52", "-DNS_TARGET_MAJOR=5", "-DNS_TARGET_MINOR=2",
    "-DNeXT", "-D__NeXT", "-D__NeXT__", "-D_NEXT_SOURCE", 0
};

/* baseflags as {key, value} pairs (value may be ""). */
static const char *baseflags[][2] = {
    { "RC_JASPER", "YES" },
    { "RC_ARCHS", "i386 ppc" },
    { "RC_CFLAGS", "" },
    { "RC_hppa", "" }, { "RC_i386", "" }, { "RC_m68k", "" },
    { "RC_ppc", "" }, { "RC_sparc", "" },
    { "RC_KANJI", "" }, { "JAPANESE", "" },
    { "RC_OS", "teflon" },
    { "CURRENT_PROJECT_VERSION", "1" },
    { "RC_RELEASE", "Rhapsody" },
    { "NEXT_ROOT", "" },
    { "GnuNoInstallSource", "YES" },
    { "Install_Source", "" },
    { 0, 0 }
};

static void push_kv(strlist *out, const char *k, const char *v) {
    char *s = str_cats(k, "=", v ? v : "", (char *)0);
    strlist_push_owned(out, s);
}

void builder_buildflags(const Params *params, const char *target, strlist *out) {
    int i;
    char *rc_cflags;
    sbuf s;

    /* Fixed base flags, but skip the ones we override below. */
    for (i = 0; baseflags[i][0]; i++) {
        const char *k = baseflags[i][0];
        if (strcmp(k, "RC_CFLAGS") == 0 || strcmp(k, "RC_ARCHS") == 0 ||
            strcmp(k, "RC_i386") == 0 || strcmp(k, "RC_ppc") == 0)
            continue;
        push_kv(out, k, baseflags[i][1]);
    }

    /* Path roots. */
    push_kv(out, "SRCROOT", params->SRCROOT);
    push_kv(out, "OBJROOT", params->OBJROOT);
    push_kv(out, "SYMROOT", params->SYMROOT);
    push_kv(out, "SUBLIBROOTS", params->SUBLIBROOTS);
    if (strcmp(target, "installhdrs") == 0)
        push_kv(out, "DSTROOT", params->HDRROOT);
    else
        push_kv(out, "DSTROOT", params->DSTROOT);

    /* RC_CFLAGS = "-arch i386 -arch ppc" + " -D..." for each cflag. */
    sbuf_init(&s);
    sbuf_puts(&s, "-arch i386 -arch ppc");
    for (i = 0; cflags[i]; i++) { sbuf_putc(&s, ' '); sbuf_puts(&s, cflags[i]); }
    rc_cflags = sbuf_steal(&s);
    sbuf_free(&s);
    push_kv(out, "RC_CFLAGS", rc_cflags);
    free(rc_cflags);

    push_kv(out, "RC_ARCHS", "i386 ppc");
    push_kv(out, "RC_i386", "YES");
    push_kv(out, "RC_ppc", "YES");
}

void builder_buildcmd(const Params *params, const char *srcroot,
                      const char *target, strlist *out) {
    size_t i;
    strlist flags;
    strlist_push(out, "chroot");
    strlist_push(out, params->BUILDROOT);
    strlist_push(out, "make");
    strlist_push(out, "-w");
    strlist_push(out, "-C");
    strlist_push(out, srcroot);
    strlist_init(&flags);
    builder_buildflags(params, target, &flags);
    for (i = 0; i < flags.count; i++) strlist_push(out, flags.items[i]);
    strlist_free(&flags);
    strlist_push(out, target);
}

static const char *DEFAULT_DESC = "No description available.";
static const char *DEFAULT_MAINT =
    "Anonymous <darwin-development@public.lists.apple.com>";
static const char *ARCH = "universal-apple-rhapsody";

static void makecontrol(Package *pkg, const char *pname) {
    package_set(&pkg->package, pname);
    package_set(&pkg->version, "0");
    package_set(&pkg->architecture, ARCH);
    package_set(&pkg->source, pname);
    package_set(&pkg->description, DEFAULT_DESC);
    package_set(&pkg->maintainer, DEFAULT_MAINT);
    strlist_free(&pkg->build_depends);
    strlist_init(&pkg->build_depends);
    strlist_push(&pkg->build_depends, "build-base");
    pkg->has_build_depends = 1;
}

/* Read <path> into a string; returns malloc'd or NULL. */
static char *slurp_file(const char *path) {
    FILE *f = fopen(path, "r");
    sbuf s;
    char buf[1024];
    size_t n;
    char *out;
    if (!f) return 0;
    sbuf_init(&s);
    while ((n = fread(buf, 1, sizeof(buf), f)) > 0) sbuf_putn(&s, buf, n);
    fclose(f);
    out = sbuf_steal(&s);
    sbuf_free(&s);
    return out;
}

/* Returns 0 and fills pkg on success; 1 if control missing/invalid. */
static int readcontrol(Package *pkg, const char *control_path) {
    char *data = slurp_file(control_path);
    if (!data) return 1;
    package_parse(pkg, data);
    free(data);
    if (!pkg->package) {
        fprintf(stderr, "error: package file does not contain 'Package:' entry\n");
        return 1;
    }
    if (!pkg->version) {
        fprintf(stderr, "error: package file does not contain 'Version:' entry\n");
        return 1;
    }
    if (!pkg->description) package_set(&pkg->description, DEFAULT_DESC);
    if (!pkg->maintainer) package_set(&pkg->maintainer, DEFAULT_MAINT);
    package_set(&pkg->architecture, ARCH);
    package_set(&pkg->source, pkg->package);
    return 0;
}

int builder_scan_dir(const char *source, Package *pkg, Params *params) {
    char *pbase = 0, *pname = 0, *rev = 0;
    char *control_path;
    char *projname;

    builder_dir2name(source, &pbase, &pname, &rev);

    control_path = str_cats(source, "/dpkg/control", (char *)0);
    if (readcontrol(pkg, control_path) != 0) {
        /* reset any partial parse and synthesize default */
        package_free(pkg);
        package_init(pkg);
        makecontrol(pkg, pname);
    }
    free(control_path);

    package_set(&pkg->source, pbase);
    if (rev) {
        char *nv = str_cats(pkg->version, "-", rev, (char *)0);
        package_set(&pkg->version, nv);
        free(nv);
    }

    projname = str_cats(pkg->package, "-", pkg->version, (char *)0);
    builder_getparams(projname, params);
    free(projname);

    free(pbase); free(pname); free(rev);
    return 0;
}

int builder_scan(const char *type, const char *source,
                 Package *pkg, Params *params) {
    if (strcmp(type, "dir") == 0)
        return builder_scan_dir(source, pkg, params);
    fprintf(stderr, "rbuild: invalid source type \"%s\"\n", type);
    return 1;
}

/* Fixed base dependency set for the "build-base" meta-dependency
   (Builder.pm:619-644). */
static const char *basedeps[] = {
    "cc", "cctools", "gnumake",
    "pb-makefiles", "coreosmakefiles", "project-makefiles",
    "zsh", "tcsh",
    "file-cmds", "text-cmds", "shell-cmds", "developer-cmds",
    "awk", "grep", "gnutar",
    "libsystem", "libc-hdrs",
    "architecture-hdrs", "kernel-hdrs",
    "csu", "objc4-hdrs",
    "files",
    "basic-cmds", "bootstrap-cmds", "system-cmds",
    0
};

/* strlist "set" helpers (linear; lists are small). */
static int set_has(const strlist *l, const char *s) {
    size_t i;
    for (i = 0; i < l->count; i++) if (strcmp(l->items[i], s) == 0) return 1;
    return 0;
}

static void set_add(strlist *l, const char *s) {
    if (!set_has(l, s)) strlist_push(l, s);
}

/* basename without ".apk" suffix: "/a/b/foo-1.0.apk" -> "foo-1.0" */
static char *deb_to_name(const char *path) {
    const char *slash = strrchr(path, '/');
    const char *base = slash ? slash + 1 : path;
    char *out = xstrdup(base);
    size_t n = strlen(out);
    if (n >= 4 && strcmp(out + n - 4, ".apk") == 0) out[n - 4] = '\0';
    return out;
}

/* Apk analog of "dpkg-deb -x <debfile> <buildroot>": an .apk is a gzipped
   tar, so extract its payload (including the harmless .PKGINFO member)
   directly into buildroot. */
static int apk_extract(const char *apkfile, const char *buildroot) {
    char *cmd = str_cats("gzip -dc '", apkfile, "' | tar -C '",
                         buildroot, "' -xf -", (char *)0);
    char *argv[4];
    int rc;
    argv[0] = "sh"; argv[1] = "-c"; argv[2] = cmd; argv[3] = 0;
    rc = exec_run_checked(argv);
    free(cmd);
    return rc;
}

int builder_makeroot(const Package *pkg, const char *buildroot,
                     const strlist *repository) {
    strlist deps;       /* expanded, deduped dependency names */
    strlist depnames;   /* resolved package basenames (no .apk) */
    strlist depfiles;   /* resolved full paths, parallel to depnames */
    strlist curdeps;    /* already-installed names from package-list */
    size_t i;
    char *listpath;
    char *admdir;
    FILE *f;
    int rc = 0;

    strlist_init(&deps);
    strlist_init(&depnames);
    strlist_init(&depfiles);
    strlist_init(&curdeps);

    printf("Building build root:\n");
    fflush(stdout);

    /* Expand build-depends (or basedeps) into a deduped set. Matches
       Builder.pm's defined() check: an explicitly-declared build-depends
       field (even empty) is honored as-is; only an ABSENT field falls back
       to basedeps. */
    if (pkg->has_build_depends) {
        for (i = 0; i < pkg->build_depends.count; i++) {
            const char *d = pkg->build_depends.items[i];
            if (strcmp(d, "build-base") == 0) {
                int j;
                for (j = 0; basedeps[j]; j++) set_add(&deps, basedeps[j]);
            } else {
                set_add(&deps, d);
            }
        }
    } else {
        int j;
        for (j = 0; basedeps[j]; j++) set_add(&deps, basedeps[j]);
    }

    /* Resolve each dep to a package file. */
    for (i = 0; i < deps.count; i++) {
        char *file = builder_resolve_dependency(deps.items[i], repository);
        char *name;
        if (!file) {
            fprintf(stderr, "rbuild: unable to find dependency for \"%s\"\n",
                    deps.items[i]);
            rc = 1;
            goto cleanup;
        }
        name = deb_to_name(file);
        strlist_push_owned(&depnames, name);
        strlist_push_owned(&depfiles, file);
    }

    /* Read existing package-list. */
    listpath = str_cats(buildroot, "/var/adm/package-list", (char *)0);
    f = fopen(listpath, "r");
    if (f) {
        char line[1024];
        while (fgets(line, sizeof(line), f) != 0) {
            str_chomp(line);
            if (line[0]) set_add(&curdeps, line);
        }
        fclose(f);
    }

    /* Install any dep not already present. */
    for (i = 0; i < depnames.count; i++) {
        if (set_has(&curdeps, depnames.items[i])) {
            printf("\talready have %s\n", depfiles.items[i]);
        } else {
            printf("\tinstalling %s\n", depfiles.items[i]);
            fflush(stdout);
            if (apk_extract(depfiles.items[i], buildroot) != 0) {
                rc = 1;
                free(listpath);
                goto cleanup;
            }
        }
    }

    /* mkdir -p <buildroot>/var/adm and rewrite package-list. */
    admdir = str_cats(buildroot, "/var/adm", (char *)0);
    if (exec_runv("mkdir", "-p", admdir, (char *)0) != 0) {
        rc = 1; free(admdir); free(listpath); goto cleanup;
    }
    free(admdir);

    f = fopen(listpath, "w");
    if (!f) {
        fprintf(stderr, "rbuild: unable to open %s\n", listpath);
        rc = 1; free(listpath); goto cleanup;
    }
    for (i = 0; i < depnames.count; i++)
        fprintf(f, "%s\n", depnames.items[i]);
    fclose(f);
    free(listpath);

cleanup:
    strlist_free(&deps);
    strlist_free(&depnames);
    strlist_free(&depfiles);
    strlist_free(&curdeps);
    return rc;
}
