#include "builder.h"
#include "architecture.h"
#include "products.h"
#include "macho.h"
#include "apk.h"
#include <errno.h>
#include "pkginfo.h"
#include "exec.h"
#include <string.h>
#include <ctype.h>
#include <stdlib.h>
#include <stdio.h>
#include <dirent.h>
#include <sys/stat.h>
#include <unistd.h>

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

static char *apk_name_for_mask(const char *name, const char *version,
                               unsigned mask) {
    const char *token = architecture_filename_token(mask);
    if (!token) return 0;
    return str_cats(name, "-", version, "-", token, ".apk", (char *)0);
}

static char *open_arch_package(const char *dir, const char *filename,
                               const char *name, const char *version,
                               unsigned required, int dependency,
                               const Toolchain *tc) {
    char *path = path_join(dir, filename);
    if (!exec_dry_run && apk_use_arch(path, 0, tc, name, version,
            required, str_has_suffix(name, "-obj"), dependency) == 0)
        return path;
    if (exec_dry_run) printf("validate APK %s for %s\n", path,
                            architecture_label(required));
    free(path);
    return 0;
}

/* Inspect every candidate in repository order; incompatible files do not hide
 * compatible versions later in the same directory or a later repository. */
static char *find_arch_package(const char *dir, const char *name,
                               const char *version, unsigned required,
                               int dependency, const Toolchain *tc) {
    unsigned try_mask[2];
    unsigned tries = 0;
    unsigned i;
    if (version) {
        if (required == RB_ARCH_I386 || required == RB_ARCH_PPC) {
            try_mask[tries++] = required;
            try_mask[tries++] = RB_ARCH_UNIVERSAL;
        } else {
            try_mask[tries++] = RB_ARCH_UNIVERSAL;
        }
        for (i = 0; i < tries; i++) {
            char *exact = apk_name_for_mask(name, version, try_mask[i]);
            char *found;
            struct stat st;
            char *path;
            if (!exact) continue;
            path = path_join(dir, exact);
            if (stat(path, &st) != 0) {
                free(path);
                free(exact);
                continue;
            }
            free(path);
            found = open_arch_package(dir, exact, name, version, required,
                                      dependency, tc);
            free(exact);
            if (found) return found;
        }
        return 0;
    }
    /* version == 0: scan, new names only via apk_use_arch token check */
    {
        DIR *d = opendir(dir);
        struct dirent *de;
        char *found = 0;
        if (!d) return 0;
        while ((de = readdir(d)) != 0) {
            if (!builder_match_pkgfile(de->d_name, name)) continue;
            found = open_arch_package(dir, de->d_name, name, version,
                                      required, dependency, tc);
            if (found) break;
        }
        closedir(d);
        return found;
    }
}

char *builder_exists(const Package *pkg, const char *type, const char *dir) {
    unsigned required;
    char *version = 0, *found;
    if (architecture_parse(pkg->architecture, &required) != 0) return 0;
    if (strcmp(type, "exact") == 0) version = package_canon_version(pkg);
    else if (strcmp(type, "any") != 0) return 0;
    found = find_arch_package(dir, pkg->package, version, required, 1, 0);
    free(version);
    return found;
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

void build_options_init(BuildOptions *opt) {
    memset(opt, 0, sizeof(*opt));
}

/* Resolve only the scanned local package, never its source control file. */
int builder_resolve_architecture(Package *pkg, BuildOptions *opt) {
    unsigned source, operation = opt->operation_arch, effective;
    if (opt->bootstrap) {
        unsigned profile_arch;
        if (!opt->toolchain ||
            architecture_parse(opt->toolchain->target_arch, &profile_arch) != 0 ||
            (profile_arch != RB_ARCH_I386 && profile_arch != RB_ARCH_PPC) ||
            (operation && operation != profile_arch &&
             operation != RB_ARCH_UNIVERSAL)) {
            fprintf(stderr, "rbuild: %s: invalid or conflicting bootstrap architecture '%s' for operation '%s'\n",
                    pkg->source ? pkg->source :
                    (pkg->package ? pkg->package : "(unknown)"),
                    opt->toolchain && opt->toolchain->target_arch ?
                    opt->toolchain->target_arch : "(missing)",
                    operation ? (architecture_label(operation) ?
                    architecture_label(operation) : "(invalid)") : "bootstrap");
            return 1;
        }
        if (operation != RB_ARCH_UNIVERSAL)
            operation = profile_arch;
    }
    if (architecture_parse(pkg->architecture, &source) != 0 ||
        architecture_resolve(source, operation, &effective) != 0) {
        fprintf(stderr, "rbuild: %s: unsupported or conflicting package architecture '%s' for operation '%s'\n",
                pkg->source ? pkg->source :
                    (pkg->package ? pkg->package : "(unknown)"),
                pkg->architecture ? pkg->architecture : "(missing)",
                operation ? (architecture_label(operation) ?
                architecture_label(operation) : "(invalid)") : "ordinary");
        return 1;
    }
    opt->operation_arch = operation;
    opt->effective_arch = effective;
    package_set(&pkg->architecture, architecture_label(effective));
    return 0;
}

static char *expand_toolchain_value(const char *value, const char *sysroot) {
    static const char marker[] = "@SYSROOT@";
    const char *p = value ? value : "";
    const char *match;
    sbuf expanded;
    char *out;

    sbuf_init(&expanded);
    while ((match = strstr(p, marker)) != 0) {
        sbuf_putn(&expanded, p, (size_t)(match - p));
        sbuf_puts(&expanded, sysroot ? sysroot : "");
        p = match + sizeof(marker) - 1;
    }
    sbuf_puts(&expanded, p);
    out = sbuf_steal(&expanded);
    sbuf_free(&expanded);
    return out;
}

static void expand_toolchain_words(const char *value, const char *sysroot,
                                   strlist *out) {
    char *expanded = expand_toolchain_value(value, sysroot);
    str_split_ws(expanded, out);
    free(expanded);
}

static int toolchain_ready(const char *marker, const char *sysroot) {
    char *path;
    int ready;
    if (!marker) return 1;
    path = expand_toolchain_value(marker, sysroot);
    ready = access(path, F_OK) == 0;
    free(path);
    return ready;
}

static int file_has_slice(const char *path, unsigned slice) {
    unsigned mask;
    int code;
    if (!path || macho_file_arches(path, &mask, &code) != 0 || !code)
        return 0;
    return (mask & slice) == slice;
}

static int slice_link_ready(const BuildOptions *opt, unsigned slice) {
    char *system_path;
    char *crt_path;
    int ready;
    if (!opt || !opt->bootstrap || !opt->toolchain) return 1;
    if (!opt->toolchain->ld_flags_ready) return 1;
    if (!toolchain_ready(opt->toolchain->ld_flags_ready, opt->sysroot))
        return 0;
    system_path = expand_toolchain_value(opt->toolchain->ld_flags_ready,
                                         opt->sysroot);
    crt_path = str_cats(opt->sysroot ? opt->sysroot : "", "/lib/crt1.o",
                        (char *)0);
    ready = file_has_slice(system_path, slice) && file_has_slice(crt_path, slice);
    free(system_path);
    free(crt_path);
    return ready;
}

void builder_buildflags(const Params *params, const char *target, strlist *out,
                        const BuildOptions *opt) {
    int i;
    char *rc_cflags;
    sbuf s;
    const char *arch_cflags;
    char *expanded_cflags = 0;
    const char *archs;
    int bootstrap = opt && opt->bootstrap;
    const Toolchain *tc = opt ? opt->toolchain : 0;
    unsigned effective = opt && opt->effective_arch ? opt->effective_arch :
                         RB_ARCH_UNIVERSAL;

    if (bootstrap && tc && !(opt && opt->effective_arch)) {
        unsigned profile_arch;
        if (architecture_parse(tc->target_arch, &profile_arch) == 0 &&
            profile_arch != RB_ARCH_UNIVERSAL)
            effective = profile_arch;
    }
    if (opt && opt->target_arch && opt->target_arch[0] != '\0') {
        unsigned requested;
        if (architecture_parse(opt->target_arch, &requested) == 0 &&
            requested != RB_ARCH_UNIVERSAL)
            effective = requested;
    }

    /* Fixed base flags, but skip the ones we override below. */
    for (i = 0; baseflags[i][0]; i++) {
        const char *k = baseflags[i][0];
        if (strcmp(k, "RC_CFLAGS") == 0 || strcmp(k, "RC_ARCHS") == 0 ||
            strcmp(k, "RC_i386") == 0 || strcmp(k, "RC_ppc") == 0 ||
            (bootstrap && strcmp(k, "NEXT_ROOT") == 0))
            continue;
        push_kv(out, k, baseflags[i][1]);
    }

    /* Path roots. */
    push_kv(out, "SRCROOT", params->SRCROOT);
    push_kv(out, "OBJROOT", params->OBJROOT);
    push_kv(out, "SYMROOT", params->SYMROOT);
    if (bootstrap && tc && opt->sysroot) {
        char *sublibroots = str_cats(
            opt->sysroot, "/usr/local/lib/objs", (char *)0);
        push_kv(out, "SUBLIBROOTS", sublibroots);
        free(sublibroots);
    } else {
        push_kv(out, "SUBLIBROOTS", params->SUBLIBROOTS);
    }
    if (strcmp(target, "installhdrs") == 0)
        push_kv(out, "DSTROOT", params->HDRROOT);
    else
        push_kv(out, "DSTROOT", params->DSTROOT);
    if (bootstrap && tc && opt->sysroot) {
        char *coreos_makefiles = str_cats(
            opt->sysroot, "/System/Developer/Makefiles/CoreOS", (char *)0);
        char *coreos_common = str_cats(
            coreos_makefiles, "/ReleaseControl/Common.make", (char *)0);
        /* CoreOSMakefiles-1 ships Common.make and includes it via
         * CoreOSMakefiles=.; overriding that before the sysroot exists
         * makes the first installhdrs fail. */
        if (access(coreos_common, F_OK) == 0)
            push_kv(out, "CoreOSMakefiles", coreos_makefiles);
        push_kv(out, "MKDIRS", "/bin/mkdir -p");
        free(coreos_common);
        free(coreos_makefiles);
        {
            char *sfile_dir = str_cats(
                params->SYMROOT, "/derived_src", (char *)0);
            push_kv(out, "SFILE_DIR", sfile_dir);
            free(sfile_dir);
        }
    }

    if (bootstrap && tc) {
        strlist words;
        strlist include_words;
        int cpp_ready = 1;
        char *other_cflags;
        const char *slice_flags;
        strlist_init(&words);
        strlist_init(&include_words);
        /* Universal install must pass both -arch flags so Csu/etc. produce
         * fat objects. Thin bootstrap still follows the profile arch_flags. */
        if (effective == RB_ARCH_UNIVERSAL)
            slice_flags = architecture_cflags(effective);
        else
            slice_flags = 0;
        if (!slice_flags) slice_flags = tc->arch_flags;
        expand_toolchain_words(slice_flags, opt->sysroot, &words);
        if (tc->cpp_flags_ready) {
            char *path = expand_toolchain_value(
                tc->cpp_flags_ready, opt->sysroot);
            cpp_ready = access(path, F_OK) == 0;
            free(path);
        }
        {
            strlist cpp_words;
            size_t wi;
            strlist_init(&cpp_words);
            expand_toolchain_words(tc->cpp_flags, opt->sysroot, &cpp_words);
            for (wi = 0; wi < cpp_words.count; wi++) {
                const char *word = cpp_words.items[wi];
                if (!cpp_ready && strcmp(word, "-nostdinc") == 0)
                    continue;
                if (strcmp(word, "-nostdinc") == 0)
                    strlist_push(&words, word);
                else
                    strlist_push(&include_words, word);
            }
            strlist_free(&cpp_words);
        }
        other_cflags = strlist_join(&include_words, " ");
        if (other_cflags[0] != '\0')
            push_kv(out, "LOCAL_CFLAGS", other_cflags);
        free(other_cflags);
        strlist_free(&include_words);
        expanded_cflags = strlist_join(&words, " ");
        arch_cflags = expanded_cflags;
        archs = architecture_archs(effective);
        strlist_free(&words);
    } else {
        arch_cflags = architecture_cflags(effective);
        archs = architecture_archs(effective);
    }

    /* RC_CFLAGS = "-arch ..." + " -D..." for each cflag. */
    sbuf_init(&s);
    sbuf_puts(&s, arch_cflags);
    /* Preserve the legacy ordinary flag separator used by the Perl oracle. */
    if (!bootstrap) sbuf_putc(&s, ' ');
    for (i = 0; cflags[i]; i++) { sbuf_putc(&s, ' '); sbuf_puts(&s, cflags[i]); }
    rc_cflags = sbuf_steal(&s);
    sbuf_free(&s);
    push_kv(out, "RC_CFLAGS", rc_cflags);
    free(rc_cflags);

    push_kv(out, "RC_ARCHS", archs);
    push_kv(out, "RC_i386", effective & RB_ARCH_I386 ? "YES" : "");
    push_kv(out, "RC_ppc", effective & RB_ARCH_PPC ? "YES" : "");
    if (bootstrap && tc)
        push_kv(out, "TARGETS", architecture_archs(effective));
    if (bootstrap && tc) {
        strlist ld_words;
        char *ld_flags;
        int ld_ready = toolchain_ready(tc->ld_flags_ready, opt->sysroot);
        /* NEXT_ROOT also redirects Darwin startup-object/library lookup. */
        if (bootstrap && tc && opt->sysroot)
            push_kv(out, "HDRROOT", opt->sysroot);
        if (opt->sysroot && ld_ready)
            push_kv(out, "NEXT_ROOT", opt->sysroot);
        if (opt->sysroot) {
            char *indr = str_cats(opt->sysroot, "/usr/local/bin/indr",
                                  (char *)0);
            if (access(indr, X_OK) == 0)
                push_kv(out, "INDR", indr);
            free(indr);
        }
        if (tc->target_cc) push_kv(out, "CC", tc->target_cc);
        if (tc->target_ar) push_kv(out, "AR", tc->target_ar);
        if (tc->target_ranlib) push_kv(out, "RANLIB", tc->target_ranlib);
        if (tc->ln) {
            if (strstr(tc->ln, "-s") != 0)
                push_kv(out, "LN", tc->ln);
            else {
                char *ln_s = str_cats(tc->ln, " -s", (char *)0);
                push_kv(out, "LN", ln_s);
                free(ln_s);
            }
        }
        strlist_init(&ld_words);
        if (ld_ready)
            expand_toolchain_words(tc->ld_flags, opt->sysroot, &ld_words);
        /* Rhapsody ld rejects -syslibroot; search the sysroot with -F/-L. */
        {
            strlist rewritten;
            size_t wi;
            strlist_init(&rewritten);
            for (wi = 0; wi < ld_words.count; wi++) {
                const char *w = ld_words.items[wi];
                const char *prefix = "-Wl,-syslibroot,";
                if (str_has_prefix(w, prefix)) {
                    const char *root = w + strlen(prefix);
                    char *dash_f = str_cats("-F", root,
                        "/System/Library/Frameworks", (char *)0);
                    char *dash_local = str_cats("-L", root, "/usr/local/lib",
                        (char *)0);
                    char *dash_l = str_cats("-L", root, "/usr/lib",
                        (char *)0);
                    strlist_push(&rewritten, dash_f);
                    strlist_push(&rewritten, dash_local);
                    strlist_push(&rewritten, dash_l);
                    free(dash_f);
                    free(dash_local);
                    free(dash_l);
                } else {
                    strlist_push(&rewritten, w);
                }
            }
            strlist_free(&ld_words);
            ld_words = rewritten;
        }
        ld_flags = strlist_join(&ld_words, " ");
        push_kv(out, "OTHER_LDFLAGS", ld_flags);
        free(ld_flags);
        strlist_free(&ld_words);
        free(expanded_cflags);
    }
}

void builder_buildcmd(const Params *chroot_params, const Params *build_params,
                      const char *target, strlist *out,
                      const BuildOptions *opt) {
    size_t i;
    strlist flags;
    int bootstrap = opt && opt->bootstrap;
    if (!bootstrap) {
        strlist_push(out, "chroot");
        strlist_push(out, chroot_params->BUILDROOT);
    }
    if (bootstrap && opt->toolchain && opt->toolchain->make)
        strlist_push(out, opt->toolchain->make);
    else
        strlist_push(out, "make");
    strlist_push(out, "-w");
    strlist_push(out, "-C");
    strlist_push(out, build_params->SRCROOT);
    if (bootstrap && opt->toolchain && opt->toolchain->make_flags) {
        int ready = 1;
        if (opt->toolchain->make_flags_ready) {
            char *path = expand_toolchain_value(
                opt->toolchain->make_flags_ready, opt->sysroot);
            ready = access(path, F_OK) == 0;
            free(path);
        }
        if (ready) {
            strlist words;
            strlist_init(&words);
            expand_toolchain_words(opt->toolchain->make_flags,
                                   opt->sysroot, &words);
            for (i = 0; i < words.count; i++) {
                /* Let a project select pb_makefiles over this weak default. */
                if (!str_has_prefix(words.items[i], "MAKEFILEDIR="))
                    strlist_push(out, words.items[i]);
            }
            strlist_free(&words);
        }
    }
    strlist_init(&flags);
    builder_buildflags(build_params, target, &flags, opt);
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

/* Returns 0 on success, 1 for fallback, 2 for invalid architecture. */
static int readcontrol(Package *pkg, const char *control_path) {
    unsigned mask;
    char *data = slurp_file(control_path);
    if (!data) return 1;
    package_parse(pkg, data);
    free(data);
    if (architecture_parse(pkg->architecture, &mask) != 0) {
        fprintf(stderr, "rbuild: %s: invalid Architecture: '%s'\n",
                control_path, pkg->architecture);
        return 2;
    }
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
    if (!pkg->architecture) package_set(&pkg->architecture, ARCH);
    package_set(&pkg->source, pkg->package);
    return 0;
}

int builder_scan_dir(const char *source, Package *pkg, Params *params) {
    char *pbase = 0, *pname = 0, *rev = 0;
    char *control_path;
    char *projname;
    int rc;

    builder_dir2name(source, &pbase, &pname, &rev);

    control_path = str_cats(source, "/dpkg/control", (char *)0);
    rc = readcontrol(pkg, control_path);
    if (rc == 2) {
        free(control_path);
        free(pbase); free(pname); free(rev);
        return 1;
    }
    if (rc != 0) {
        /* Synthesize legacy defaults without discarding a validated explicit
         * architecture from a partial control file. */
        char *architecture = pkg->architecture ? xstrdup(pkg->architecture) : 0;
        package_free(pkg);
        package_init(pkg);
        makecontrol(pkg, pname);
        if (architecture) package_set(&pkg->architecture, architecture);
        free(architecture);
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
    "awk", "grep", "gnutar", "patch-cmds",
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

int builder_makeroot(const Package *pkg, const char *buildroot,
                     const strlist *repository, const Toolchain *tc) {
    strlist deps;       /* expanded, deduped dependency names */
    strlist depnames;   /* resolved package basenames (no .apk) */
    strlist depfiles;   /* resolved full paths, parallel to depnames */
    unsigned required;
    size_t i;
    char *listpath;
    char *admdir;
    FILE *f;
    int rc = 0;

    strlist_init(&deps);
    strlist_init(&depnames);
    strlist_init(&depfiles);
    if (architecture_parse(pkg->architecture, &required) != 0) return 1;

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
        char *file = 0;
        char *name;
        size_t ri;
        for (ri = 0; ri < repository->count && !file; ri++)
            file = find_arch_package(repository->items[ri], deps.items[i],
                                     0, required, 1, tc);
        if (exec_dry_run && !file) {
            printf("validate and install dependency %s for %s\n", deps.items[i],
                   architecture_label(required));
            continue;
        }
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

    listpath = str_cats(buildroot, "/var/adm/package-list", (char *)0);
    /* A basename-only package-list cannot attest installed architecture. */
    for (i = 0; i < depnames.count; i++) {
        printf("\tinstalling %s\n", depfiles.items[i]);
        fflush(stdout);
        if (apk_use_arch(depfiles.items[i], buildroot, tc, deps.items[i], 0,
                         required, str_has_suffix(deps.items[i], "-obj"), 1) != 0) {
            rc = 1; free(listpath); goto cleanup;
        }
    }

    /* mkdir -p <buildroot>/var/adm and rewrite package-list. */
    admdir = str_cats(buildroot, "/var/adm", (char *)0);
    if (exec_runv("mkdir", "-p", admdir, (char *)0) != 0) {
        rc = 1; free(admdir); free(listpath); goto cleanup;
    }
    free(admdir);

    if (!exec_dry_run) {
        f = fopen(listpath, "w");
        if (!f) {
            fprintf(stderr, "rbuild: unable to open %s\n", listpath);
            rc = 1; free(listpath); goto cleanup;
        }
        for (i = 0; i < depnames.count; i++)
            fprintf(f, "%s\n", depnames.items[i]);
        fclose(f);
    }
    free(listpath);

    /* coreosmakefiles.apk often ships texi2html as 0644 (Windows sync / tar
       mode loss). flex and others exec it during install-strip docs. */
    {
        char *dst = str_cats(buildroot,
            "/System/Developer/Makefiles/CoreOS/ReleaseControl/texi2html",
            (char *)0);
        struct stat st;
        if (stat(dst, &st) == 0) {
            printf("\tchmod +x texi2html in build root\n");
            fflush(stdout);
            exec_runv("chmod", "a+x", dst, (char *)0);
        }
        free(dst);
    }

cleanup:
    strlist_free(&deps);
    strlist_free(&depnames);
    strlist_free(&depfiles);

    return rc;
}

static int mkdirp(const char *path) {
    return exec_runv("mkdir", "-p", path, (char *)0);
}

static int rmtree_dir(const char *path) {
    if (path == 0 || path[0] == '\0' || strcmp(path, "/") == 0)
        return 0;
    return exec_runv("rm", "-rf", path, (char *)0);
}

static int path_is_inside(const char *root, const char *path) {
    size_t n;
    if (root == 0 || path == 0 || root[0] != '/' || path[0] != '/') return 0;
    n = strlen(root);
    while (n > 1 && root[n - 1] == '/') n--;
    if (strncmp(path, root, n) != 0) return 0;
    return path[n] == '\0' || path[n] == '/';
}

static int split_abs_components(const char *path, strlist *out) {
    const char *p;
    if (path == 0 || path[0] != '/') return 1;
    p = path + 1;
    while (*p != '\0') {
        const char *start = p;
        size_t length;
        while (*p != '\0' && *p != '/') p++;
        length = (size_t)(p - start);
        if (length == 1 && start[0] == '.') {
            /* skip */
        } else if (length == 2 && start[0] == '.' && start[1] == '.') {
            return 1;
        } else if (length > 0) {
            char *comp = (char *)xmalloc(length + 1);
            memcpy(comp, start, length);
            comp[length] = '\0';
            strlist_push_owned(out, comp);
        }
        if (*p == '/') p++;
    }
    return 0;
}

static char *relative_from_dir(const char *from_dir, const char *to) {
    strlist from;
    strlist dest;
    size_t common = 0;
    size_t i;
    sbuf s;
    strlist_init(&from);
    strlist_init(&dest);
    if (split_abs_components(from_dir, &from) != 0 ||
        split_abs_components(to, &dest) != 0) {
        strlist_free(&from);
        strlist_free(&dest);
        return 0;
    }
    while (common < from.count && common < dest.count &&
           strcmp(from.items[common], dest.items[common]) == 0)
        common++;
    sbuf_init(&s);
    for (i = common; i < from.count; i++) {
        if (s.len != 0) sbuf_putc(&s, '/');
        sbuf_puts(&s, "..");
    }
    for (i = common; i < dest.count; i++) {
        if (s.len != 0) sbuf_putc(&s, '/');
        sbuf_puts(&s, dest.items[i]);
    }
    if (s.len == 0) sbuf_putc(&s, '.');
    strlist_free(&from);
    strlist_free(&dest);
    return sbuf_steal(&s);
}

static int relativize_walk(const char *root, const char *dir) {
    DIR *d = opendir(dir);
    struct dirent *de;
    int rc = 0;
    if (d == 0) return 1;
    while ((de = readdir(d)) != 0) {
        char *path;
        struct stat st;
        if (strcmp(de->d_name, ".") == 0 || strcmp(de->d_name, "..") == 0)
            continue;
        path = path_join(dir, de->d_name);
        if (lstat(path, &st) != 0) { free(path); rc = 1; break; }
        if (S_ISLNK(st.st_mode)) {
            char target[1024];
            int n = readlink(path, target, sizeof(target) - 1);
            if (n < 0 || n == (int)sizeof(target) - 1) {
                free(path); rc = 1; break;
            }
            target[n] = '\0';
            if (target[0] == '/') {
                char *abs_dest = 0;
                struct stat mapped_st;
                if (path_is_inside(root, target)) {
                    abs_dest = xstrdup(target);
                } else {
                    char *mapped = str_cats(root, target, (char *)0);
                    if (lstat(mapped, &mapped_st) == 0)
                        abs_dest = mapped;
                    else
                        free(mapped);
                }
                if (abs_dest != 0) {
                    char *from_dir = xstrdup(path);
                    char *slash = strrchr(from_dir, '/');
                    char *rel;
                    if (slash == 0) {
                        free(from_dir); free(abs_dest); free(path);
                        rc = 1; break;
                    }
                    if (slash == from_dir) slash[1] = '\0';
                    else *slash = '\0';
                    rel = relative_from_dir(from_dir, abs_dest);
                    free(from_dir);
                    free(abs_dest);
                    if (rel == 0 || unlink(path) != 0 ||
                        symlink(rel, path) != 0) {
                        free(rel); free(path); rc = 1; break;
                    }
                    free(rel);
                }
            }
        } else if (S_ISDIR(st.st_mode)) {
            if (relativize_walk(root, path) != 0) {
                free(path); rc = 1; break;
            }
        }
        free(path);
    }
    closedir(d);
    return rc;
}

int builder_relativize_symlinks(const char *root) {
    struct stat st;
    if (root == 0 || root[0] == '\0') return 1;
    if (lstat(root, &st) != 0 || !S_ISDIR(st.st_mode)) return 1;
    return relativize_walk(root, root);
}

int builder_setupdirs(const Package *pkg, const Params *params,
                      const char *srcname, const char *srctype,
                      const strlist *repository, const BuildOptions *opt) {
    int bootstrap = opt && opt->bootstrap;
    (void) srcname;   /* only used by the dropped cvs branch */

    if (exec_check(rmtree_dir(params->OBJROOT))) return 1;
    if (exec_check(rmtree_dir(params->SYMROOT))) return 1;
    if (exec_check(rmtree_dir(params->DSTROOT))) return 1;
    if (exec_check(rmtree_dir(params->HDRROOT))) return 1;
    if (exec_check(rmtree_dir(params->LIBCOBJROOT))) return 1;
    if (exec_check(rmtree_dir(params->SRCROOT))) return 1;
    if (exec_check(rmtree_dir(params->PACKAGEROOT))) return 1;

    if (exec_check(mkdirp(params->OBJROOT))) return 1;
    if (exec_check(mkdirp(params->SYMROOT))) return 1;
    if (bootstrap) {
        char *sfile_dir = str_cats(params->SYMROOT, "/derived_src", (char *)0);
        int failed = exec_check(mkdirp(sfile_dir));
        free(sfile_dir);
        if (failed) return 1;
    }
    if (exec_check(mkdirp(params->DSTROOT))) return 1;
    if (exec_check(mkdirp(params->HDRROOT))) return 1;
    if (exec_check(mkdirp(params->PACKAGEROOT))) return 1;

    /* Bootstrap builds run on the host root: no chroot to create or populate. */
    if (!bootstrap) {
        if (exec_check(mkdirp(params->BUILDROOT))) return 1;
        if (builder_makeroot(pkg, params->BUILDROOT, repository,
                             opt ? opt->toolchain : 0) != 0) return 1;
        /* cc -arch <not-host> needs that arch's cc1obj/cpp-precomp. The
         * compiler apk only seeds the host arch; copy the host's
         * /usr/libexec/<arch> when --arch asked for another. */
        if (opt && opt->target_arch && opt->target_arch[0] != '\0') {
            char host_libexec[128];
            char chroot_libexec[512];
            struct stat st;
            sprintf(host_libexec, "/usr/libexec/%s", opt->target_arch);
            if (stat(host_libexec, &st) == 0 && S_ISDIR(st.st_mode)) {
                char *parent = str_cats(params->BUILDROOT,
                                        "/usr/libexec", (char *)0);
                int failed = exec_check(mkdirp(parent));
                free(parent);
                if (failed) return 1;
                sprintf(chroot_libexec, "%s/usr/libexec/%s",
                        params->BUILDROOT, opt->target_arch);
                if (exec_runv("rm", "-rf", chroot_libexec, (char *)0) != 0)
                    return 1;
                if (exec_runv("cp", "-R", host_libexec, chroot_libexec,
                              (char *)0) != 0)
                    return 1;
            }
        }
    }

    if (strcmp(srctype, "dir") == 0) {
        char *source;
        char *argv[8];
        const char *rsync = "rsync";
        int rc;
        if (exec_check(mkdirp(params->SRCROOT))) return 1;
        if (opt && opt->toolchain && opt->toolchain->rsync)
            rsync = opt->toolchain->rsync;
        source = str_cats(params->SRCDIR, "/", (char *)0);
        argv[0] = (char *)rsync; argv[1] = "-avr"; argv[2] = source;
        argv[3] = "--exclude=CVS/"; argv[4] = "--exclude=.svn/";
        argv[5] = "--exclude=.git/"; argv[6] = params->SRCROOT; argv[7] = 0;
        exec_printcmd(argv);
        rc = exec_run_checked(argv);
        free(source);
        if (rc) return 1;
    } else {
        fprintf(stderr, "rbuild: unknown source type %s\n", srctype);
        return 1;
    }
    return 0;
}

/* Count directory entries excluding . and .. ; -1 if cannot open. */
static int dir_nonempty(const char *path) {
    DIR *d = opendir(path);
    struct dirent *de;
    int n = 0;
    if (!d) return -1;
    while ((de = readdir(d)) != 0) {
        if (strcmp(de->d_name, ".") == 0 || strcmp(de->d_name, "..") == 0)
            continue;
        n++;
    }
    closedir(d);
    return n;
}

static int file_exists(const char *path) {
    struct stat st;
    return stat(path, &st) == 0 && S_ISREG(st.st_mode);
}

/* Missing optional trees mean there was nothing to harvest/install. Existing
 * paths, including symlinks and unreadable directories, must validate. */
static int validate_products(const char *root, unsigned required,
                             int objects, int optional) {
    struct stat st;
    if (exec_dry_run) {
        printf("validate products in %s for %s%s\n",
               root ? root : "(null)", architecture_label(required),
               objects ? " (object collection)" : "");
        return 0;
    }
    if (optional && root && lstat(root, &st) != 0 && errno == ENOENT)
        return 0;
    return products_validate(root, required, objects, objects);
}

int builder_cache_status(const char *path, const Toolchain *tc,
                          const char *name, const char *version,
                          unsigned required, int objects, int *exists) {
    struct stat st;
    *exists = 0;
    if (exec_dry_run) {
        printf("validate cached APK %s for %s\n", path, architecture_label(required));
        return 0;
    }
    if (lstat(path, &st) != 0) return errno == ENOENT ? 0 : 1;
    if (S_ISREG(st.st_mode) &&
        apk_use_arch(path, 0, tc, name, version, required, objects, 1) == 0) {
        *exists = 1; return 0;
    }
    fprintf(stderr, "rbuild: invalid APK %s; quarantining\n", path);
    return apk_quarantine(path);
}

/* Ancillary package files are products too: stage before architecture checks. */
static int stage_ancillary_files(const Params *params) {
    static const char *names[] =
        { "conffiles", "preinst", "postinst", "prerm", "postrm", 0 };
    int i;
    struct stat st;
    if (!params->SRCDIR) return 0;
    if (!exec_dry_run && (!params->DSTROOT ||
        lstat(params->DSTROOT, &st) != 0 || !S_ISDIR(st.st_mode))) {
        fprintf(stderr, "rbuild: product root %s: cannot stage ancillary files; "
                "required destination directory is missing or invalid\n",
                params->DSTROOT ? params->DSTROOT : "(null)");
        return 1;
    }
    for (i = 0; names[i]; i++) {
        char *extra = str_cats(params->SRCDIR, "/dpkg/", names[i], (char *)0);
        if (file_exists(extra)) {
            char *dest = str_cats(params->DSTROOT, "/", names[i], (char *)0);
            const char *mode = strcmp(names[i], "conffiles") == 0 ? "644" : "755";
            printf("copying %s\n", names[i]);
            fflush(stdout);
            if (exec_runv("cp", "-p", extra, dest, (char *)0) != 0 ||
                exec_runv("chmod", mode, dest, (char *)0) != 0) {
                free(extra); free(dest); return 1;
            }
            free(dest);
        }
        free(extra);
    }
    return 0;
}

static int buildpackage(const Package *spkg, const Params *params,
                        const char *target, const BuildOptions *opt,
                        int ancillary_staged) {
    Package pkg;
    const char *dstroot;
    char *pname;
    char *unparsed;
    char *canon;
    char *pkginfo_path;
    char *apk_path;
    int nonempty;
    int existing;
    char *version;
    int rc = 0;
    BuildOptions resolved_opt;

    /* Clone spkg by round-tripping through unparse/parse (matches Perl). */
    package_init(&pkg);
    unparsed = package_unparse(spkg);
    package_parse(&pkg, unparsed);
    free(unparsed);
    /* Serialization represents an absent field as empty; keep their distinct
     * architecture semantics for direct callers. */
    if (!spkg->architecture) package_set(&pkg.architecture, 0);
    /* Direct callers share normal build architecture resolution. */
    build_options_init(&resolved_opt);
    if (opt) resolved_opt = *opt;
    if (builder_resolve_architecture(&pkg, &resolved_opt) != 0) {
        package_free(&pkg); return 1;
    }

    pname = xstrdup(pkg.package ? pkg.package : "");

    if (strcmp(target, "local") == 0) {
        dstroot = params->DSTROOT;
    } else if (strcmp(target, "binary") == 0) {
        char *hdrs = str_cats(pname, "-hdrs", (char *)0);
        dstroot = params->DSTROOT;
        package_set(&pkg.package, pname);
        package_set(&pkg.provides, hdrs);
        package_set(&pkg.replaces, hdrs);
        free(hdrs);
    } else if (strcmp(target, "headers") == 0) {
        char *hdrs = str_cats(pname, "-hdrs", (char *)0);
        dstroot = params->HDRROOT;
        package_set(&pkg.package, hdrs);
        free(hdrs);
    } else if (strcmp(target, "objects") == 0) {
        char *obj = str_cats(pname, "-obj", (char *)0);
        dstroot = params->LIBCOBJROOT;
        package_set(&pkg.package, obj);
        free(obj);
    } else {
        fprintf(stderr, "rbuild: bad target: \"%s\"\n", target);
        free(pname); package_free(&pkg);
        return 1;
    }

    if (!ancillary_staged && strcmp(target, "binary") == 0 &&
        stage_ancillary_files(params) != 0) {
        rc = 1; goto done;
    }

    /* Validate before metadata or archive creation, including direct callers. */
    if (validate_products(dstroot, resolved_opt.effective_arch,
                          strcmp(target, "objects") == 0,
                          strcmp(target, "headers") == 0 ||
                          strcmp(target, "objects") == 0) != 0) {
        rc = 1; goto done;
    }
    if (strcmp(target, "local") == 0) goto done;
    /* Ensure the base package dir exists (Perl mkdir -p DEBIAN for binary,
       BEFORE the emptiness check -- this guarantees "binary" always proceeds
       to packaging, matching Builder.pm:398-404). */
    if (strcmp(target, "binary") == 0) {
        if (exec_check(mkdirp(dstroot))) { rc = 1; goto done; }
    }

    /* Perl only creates the sentinel DEBIAN dir for "binary", so only
       "headers" and "objects" are subject to the empty-dstroot skip. */
    if (strcmp(target, "headers") == 0 || strcmp(target, "objects") == 0) {
        nonempty = dir_nonempty(dstroot);
        if (nonempty <= 0) {
            /* cannot open (no files) or empty -> nothing to package */
            goto done;
        }
    }

    if (exec_runv("rm", "-rf",
                  (canon = str_cats(dstroot, "/System/Developer/Source", (char *)0)),
                  (char *)0) != 0) {
        free(canon); rc = 1; goto done;
    }
    free(canon);

    if (exec_check(mkdirp(dstroot))) { rc = 1; goto done; }

    /* Write .PKGINFO into dstroot. */
    if (!exec_dry_run) {
        pkginfo_path = str_cats(dstroot, "/.PKGINFO", (char *)0);
        if (pkginfo_write(&pkg, pkginfo_path) != 0) {
            free(pkginfo_path); rc = 1; goto done;
        }
        free(pkginfo_path);
    }

    if (!exec_dry_run && builder_relativize_symlinks(dstroot) != 0) {
        rc = 1; goto done;
    }

    /* Assemble <PACKAGEDIR>/<canon_name>.apk */
    canon = package_canon_name(&pkg);
    if (canon == 0) { rc = 1; goto done; }
    apk_path = str_cats(params->PACKAGEDIR, "/", canon, ".apk", (char *)0);
    version = package_canon_version(&pkg);
    rc = builder_cache_status(apk_path, resolved_opt.toolchain, pkg.package,
                              version, resolved_opt.effective_arch,
                              strcmp(target, "objects") == 0, &existing);
    free(version);
    if (!rc) rc = pkginfo_build_apk(dstroot, apk_path, resolved_opt.toolchain);
    free(canon);
    free(apk_path);

done:
    free(pname);
    package_free(&pkg);
    return rc;
}

int builder_buildpackage(const Package *spkg, const Params *params,
                         const char *target, const BuildOptions *opt) {
    return buildpackage(spkg, params, target, opt, 0);
}

/* Object harvest: find directories containing a 'dynamic_obj' entry under
   OBJROOT and copy them into LIBCOBJROOT (Builder.pm:778-896).

   Matches are collected first (mirroring Perl's @objs / unshift in
   findobjs()), then copied in a separate pass (mirroring the separate
   "for my $file (@objs)" loop in build()). */

typedef struct obj_match {
    char *file;             /* "./<rel>/dynamic_obj", matches Perl's
                                "$File::Find::dir/$_" */
    struct obj_match *next;
} obj_match;

static void obj_match_free_all(obj_match *head) {
    obj_match *next;
    while (head) {
        next = head->next;
        free(head->file);
        free(head);
        head = next;
    }
}

/* Walks the ENTIRE tree rooted at objroot_abs/rel. Every directory is
   inspected for a 'dynamic_obj' entry; if present, the match is prepended
   to *phead (unshift order). Descent still proceeds into the directory's
   OTHER subdirectories -- only the 'dynamic_obj' entry itself is pruned,
   matching Perl's $File::Find::prune semantics (it stops recursion into
   the pruned entry, not into its siblings). */
static void harvest_walk(const char *objroot_abs, const char *rel,
                         obj_match **phead) {
    char *dirpath = (rel[0] == '\0')
        ? xstrdup(objroot_abs)
        : path_join(objroot_abs, rel);
    DIR *d = opendir(dirpath);
    struct dirent *de;
    int found_obj = 0;

    if (!d) { free(dirpath); return; }

    /* First, does this directory contain 'dynamic_obj'? */
    while ((de = readdir(d)) != 0) {
        if (strcmp(de->d_name, "dynamic_obj") == 0) { found_obj = 1; break; }
    }
    rewinddir(d);

    if (found_obj) {
        /* file = "./<rel>/dynamic_obj" relative form matching Perl
           $File::Find::dir/$_ */
        obj_match *node = (obj_match *) xmalloc(sizeof(obj_match));
        node->file = (rel[0] == '\0')
            ? xstrdup("./dynamic_obj")
            : str_cats("./", rel, "/dynamic_obj", (char *)0);
        node->next = *phead;
        *phead = node;
    }

    /* Descend into subdirectories other than 'dynamic_obj' itself, which
       is pruned (not recursed into) whether or not it was just matched. */
    while ((de = readdir(d)) != 0) {
        char *child;
        struct stat st;
        if (strcmp(de->d_name, ".") == 0 || strcmp(de->d_name, "..") == 0)
            continue;
        if (strcmp(de->d_name, "dynamic_obj") == 0)
            continue;
        child = path_join(dirpath, de->d_name);
        if (stat(child, &st) == 0 && S_ISDIR(st.st_mode)) {
            char *newrel = (rel[0] == '\0')
                ? xstrdup(de->d_name)
                : path_join(rel, de->d_name);
            harvest_walk(objroot_abs, newrel, phead);
            free(newrel);
        }
        free(child);
    }
    closedir(d);
    free(dirpath);
}

int builder_harvest_objects(const Package *pkg, const Params *params,
                            const Params *bparams, const BuildOptions *opt) {
    obj_match *head = 0;
    obj_match *node;
    int rc = 0;

    printf("finding files in %s\n", params->OBJROOT);
    fflush(stdout);

    harvest_walk(params->OBJROOT, "", &head);

    for (node = head; node != 0; node = node->next) {
        char *file = node->file;
        char *objdest = str_cats("/usr/local/lib/objs/",
                                 pkg->source ? pkg->source : "", "/", file, (char *)0);
        char *dstdir = str_cats(params->LIBCOBJROOT, objdest, (char *)0);
        char *srcpath = str_cats(bparams->OBJROOT, "/", file, (char *)0);
        char *cobjpath = str_cats(bparams->LIBCOBJROOT, objdest, (char *)0);

        printf("copying files from %s\n", file);
        fflush(stdout);
        if (exec_runv("rm", "-rf", dstdir, (char *)0) != 0) rc = 1;
        exec_check(mkdirp(dstdir));
        exec_runv("rmdir", dstdir, (char *)0);
        {
            char *argv[9];
            int a = 0;
            if (!(opt && opt->bootstrap)) {
                argv[a++] = "chroot"; argv[a++] = params->BUILDROOT;
            }
            argv[a++] = "cp"; argv[a++] = "-rp";
            argv[a++] = srcpath; argv[a++] = cobjpath; argv[a] = 0;
            exec_printcmd(argv);
            if (exec_run_checked(argv)) rc = 1;
        }
        free(objdest); free(dstdir); free(srcpath); free(cobjpath);
    }

    obj_match_free_all(head);
    return rc;
}

static char *cwd_dup(void) {
    char buf[4096];
    if (getcwd(buf, sizeof(buf)) == 0) return xstrdup(".");
    return xstrdup(buf);
}

static int run_make(strlist *cmd, const BuildOptions *opt) {
    char **argv;
    size_t i;
    int rc;
    argv = (char **) xmalloc((cmd->count + 1) * sizeof(char *));
    for (i = 0; i < cmd->count; i++) argv[i] = cmd->items[i];
    argv[cmd->count] = 0;
    setenv("UNAME_SYSNAME", "Rhapsody", 1);
    if (opt && opt->bootstrap && opt->sysroot) {
        char *makefiledir = str_cats(
            opt->sysroot, "/System/Developer/Makefiles/project", (char *)0);
        setenv("MAKEFILEDIR", makefiledir, 1);
        free(makefiledir);
    }
    {
        const char *path = "/sbin:/usr/sbin:/bin:/usr/bin:/usr/local/bin";
        const char *old_path = getenv("PATH");
        char *saved_path = old_path ? xstrdup(old_path) : 0;
        if (opt && opt->toolchain && opt->toolchain->path)
            path = opt->toolchain->path;
        setenv("PATH", path, 1);
        printf("UNAME_SYSNAME=Rhapsody PATH=%s ", path);
        exec_printcmd(argv);
        rc = exec_run_checked(argv);
        if (saved_path) {
            setenv("PATH", saved_path, 1);
            free(saved_path);
        }
    }
    free(argv);
    return rc;
}

static int probe_write(const char *dir, const char *name, const char *text) {
    char *path = path_join(dir, name);
    FILE *f = fopen(path, "w");
    int rc = 1;
    free(path);
    if (f) {
        rc = fputs(text, f) == EOF;
        if (fclose(f) != 0) rc = 1;
    }
    return rc;
}

int builder_probe_toolchain(const Params *params, const Params *bparams,
                            const BuildOptions *opt) {
    static const char makefile[] =
        "probe.o: probe.c\n"
        "\t$(CC) $(CPPFLAGS) $(CFLAGS) $(RC_CFLAGS) $(LOCAL_CFLAGS) -c probe.c -o probe.o\n"
        "probe: probe.o\n"
        "\t$(CC) $(CFLAGS) $(RC_CFLAGS) $(LOCAL_CFLAGS) $(LDFLAGS) $(OTHER_LDFLAGS) probe.o -o probe\n";
    char name[80];
    char *parent = 0, *dir = 0, *guest_parent = 0;
    const char *stage = "setup";
    unsigned slice = 0;
    int attempt, made = 0, rc = 1;
    if (!opt || !architecture_label(opt->effective_arch) ||
        !params->OBJROOT || !bparams->OBJROOT) return 1;
    for (attempt = 0; attempt < 100; attempt++) {
        sprintf(name, ".rbuild-probe-%ld-%d", (long)getpid(), attempt);
        parent = path_join(params->OBJROOT, name);
        if (exec_dry_run || mkdir(parent, 0700) == 0) {
            made = !exec_dry_run;
            break;
        }
        free(parent); parent = 0;
        if (errno != EEXIST) break;
    }
    if (!parent) goto done;
    guest_parent = path_join(bparams->OBJROOT, name);
    for (slice = RB_ARCH_I386; slice <= RB_ARCH_PPC; slice <<= 1) {
        Params probe_params = *bparams;
        BuildOptions probe_opt = *opt;
        Toolchain probe_tc;
        char *guest_dir;
        int pass;
        if (!(opt->effective_arch & slice)) continue;
        stage = "setup";
        dir = path_join(parent, architecture_archs(slice));
        guest_dir = path_join(guest_parent, architecture_archs(slice));
        probe_params.SRCROOT = guest_dir;
        probe_opt.effective_arch = slice;
        if (opt->bootstrap && opt->effective_arch == RB_ARCH_UNIVERSAL &&
            opt->toolchain) {
            probe_tc = *opt->toolchain;
            probe_tc.arch_flags = architecture_cflags(slice);
            probe_opt.toolchain = &probe_tc;
        }
        rc = 0;
        if (!exec_dry_run && (mkdir(dir, 0700) != 0 ||
            probe_write(dir, "probe.c", "int main(void) { return 0; }\n") ||
            probe_write(dir, "Makefile", makefile))) rc = 1;
        {
        int link_ready = slice_link_ready(opt, slice);
        for (pass = 0; !rc && pass < (link_ready ? 2 : 1); pass++) {
            strlist cmd;
            char *output;
            unsigned mask;
            int code;
            stage = pass ? "link" : "compile";
            printf("probe %s %s\n", architecture_archs(slice), stage);
            strlist_init(&cmd);
            builder_buildcmd(params, &probe_params, pass ? "probe" : "probe.o",
                              &cmd, &probe_opt);
            rc = run_make(&cmd, &probe_opt);
            strlist_free(&cmd);
            if (!rc && !exec_dry_run) {
                stage = pass ? "link inspection" : "compile inspection";
                output = path_join(dir, pass ? "probe" : "probe.o");
                if (macho_file_arches(output, &mask, &code) || !code || mask != slice)
                    rc = 1;
                free(output);
            }
        }
        }
        free(guest_dir);
        free(dir); dir = 0;
        if (rc) break;
    }
done:
    /* Only this exclusively created subtree is owned by the probe. Compiler
     * options can leave extra files (for example -save-temps or -MD). */
    if (made && exec_runv("rm", "-rf", parent, (char *)0) != 0 && !rc) {
        stage = "cleanup"; rc = 1;
    }
    if (rc)
        fprintf(stderr, "rbuild: %s toolchain probe failed during %s\n",
                architecture_archs(architecture_label(slice) ? slice :
                                    opt->effective_arch), stage);
    free(guest_parent); free(parent);
    return rc;
}

int builder_build(const char *srctype, const char *srcname,
                  const strlist *repository, const char *target,
                  const char *dstdir, const BuildOptions *opt) {
    BuildOptions resolved_opt;
    Package pkg, hdrpkg;
    Params bparams, params;
    char *hdrfilename, *filename;
    char *cwd;
    int rc = 0;
    int do_hdr = (strcmp(target, "all") == 0 || strcmp(target, "headers") == 0);
    int do_bin = (strcmp(target, "all") == 0 || strcmp(target, "binary") == 0);

    package_init(&pkg);
    params_init(&bparams);
    if (builder_scan(srctype, srcname, &pkg, &bparams) != 0) {
        package_free(&pkg); params_free(&bparams);
        return 1;
    }

    build_options_init(&resolved_opt);
    if (opt) resolved_opt = *opt;
    if (builder_resolve_architecture(&pkg, &resolved_opt) != 0) {
        fprintf(stderr, "rbuild: architecture resolution failed for %s\n", srcname);
        package_free(&pkg); params_free(&bparams);
        return 1;
    }
    opt = &resolved_opt;

    /* hdrpackage = clone(pkg); name += "-hdrs" */
    {
        char *u = package_unparse(&pkg);
        char *h;
        package_init(&hdrpkg);
        package_parse(&hdrpkg, u);
        free(u);
        h = str_cats(hdrpkg.package, "-hdrs", (char *)0);
        package_set(&hdrpkg.package, h);
        free(h);
    }
    hdrfilename = package_canon_name(&hdrpkg);
    filename = package_canon_name(&pkg);
    if (!hdrfilename || !filename) {
        rc = 1;
        free(hdrfilename);
        free(filename);
        package_free(&hdrpkg);
        package_free(&pkg);
        params_free(&bparams);
        return 1;
    }

    if (do_hdr || do_bin) {
        char *names[3];
        char *version = package_canon_version(&pkg);
        int exists[3], was[3], i, count = 0, invalid = 0;
        struct stat st;
        const char *token = architecture_filename_token(opt->effective_arch);
        names[count++] = xstrdup(strcmp(target, "headers") == 0 ? hdrpkg.package : pkg.package);
        if (strcmp(target, "all") == 0 || strcmp(target, "binary") == 0) {
            names[count++] = xstrdup(hdrpkg.package);
            names[count++] = str_cats(pkg.package, "-obj", (char *)0);
        }
        for (i = 0; i < count; i++) {
            char *path;
            if (token == 0) { rc = 1; break; }
            path = str_cats(dstdir, "/", names[i], "-", version, "-", token, ".apk",
                            (char *)0);
            was[i] = lstat(path, &st) == 0;
            if (builder_cache_status(path, opt->toolchain, names[i], version,
                    opt->effective_arch, str_has_suffix(names[i], "-obj"), &exists[i]) != 0)
                rc = 1;
            if (was[i] && !exists[i]) invalid = 1;
            free(path); free(names[i]);
        }
        free(version);
        if (rc) goto done_ok;
        if (!opt->bootstrap && !opt->force && !invalid && exists[0] &&
            (strcmp(target, "headers") == 0 || strcmp(target, "all") == 0 ||
             strcmp(target, "binary") == 0)) {
            printf("package file for \"%s\" already exists; not building\n", filename);
            goto done_ok;
        }
    }

    /* params = chrootparams(bparams, bparams.BUILDROOT) */
    params_init(&params);
    /* Bootstrap: prefix with "/" so params paths equal the host bparams paths.
       There is no chroot in bootstrap mode, so params.BUILDROOT is unused: every
       site that would touch it (setupdirs mkdir/makeroot, buildcmd chroot,
       harvest_objects chroot, the clean teardown) is gated on !bootstrap. Do not
       rely on its value under bootstrap -- builder_canonparams below rewrites the
       empty string to "<cwd>/". */
    builder_chrootparams(&bparams, opt && opt->bootstrap ? "/" : bparams.BUILDROOT,
                         &params);

    /* SRCDIR */
    if (strcmp(srctype, "dir") == 0) params.SRCDIR = xstrdup(srcname);
    else { fprintf(stderr, "rbuild: invalid source type \"%s\"\n", srctype); rc = 1; goto done; }
    params.PACKAGEDIR = xstrdup(dstdir);

    cwd = cwd_dup();
    builder_canonparams(&params, cwd);
    builder_canonparams(&bparams, cwd);
    free(cwd);

    printf("building %s from %s:\n\n", filename, params.SRCDIR);

    if (builder_setupdirs(&pkg, &params, srcname, srctype, repository, opt) != 0) {
        rc = 1; goto done;
    }

    if (do_bin && builder_probe_toolchain(&params, &bparams, opt) != 0) {
        rc = 1; goto done;
    }

    if (do_hdr) {
        strlist cmd; strlist_init(&cmd);
        builder_buildcmd(&params, &bparams, "installhdrs", &cmd, opt);
        if (run_make(&cmd, opt)) { strlist_free(&cmd); rc = 1; goto done; }
        strlist_free(&cmd);
        printf("\n");
    }

    if (do_bin) {
        strlist cmd; strlist_init(&cmd);
        builder_buildcmd(&params, &bparams, "install", &cmd, opt);
        if (run_make(&cmd, opt)) { strlist_free(&cmd); rc = 1; goto done; }
        strlist_free(&cmd);
        printf("\n");

        if (builder_harvest_objects(&pkg, &params, &bparams, opt) != 0) { rc = 1; goto done; }
        printf("\n");
    }

    if (do_bin && stage_ancillary_files(&params) != 0) {
        rc = 1; goto done;
    }

    /* Complete all validation after harvest, before writing any package. */
    if ((do_hdr && validate_products(params.HDRROOT, opt->effective_arch, 0, 1)) ||
        (do_bin && (validate_products(params.DSTROOT, opt->effective_arch, 0, 0) ||
                    validate_products(params.LIBCOBJROOT, opt->effective_arch, 1, 1))) ||
        (strcmp(target, "local") == 0 &&
         validate_products(params.DSTROOT, opt->effective_arch, 0, 0))) {
        rc = 1; goto done;
    }
    if (do_hdr) {
        if (buildpackage(&pkg, &params, "headers", opt, 1) != 0) {
            rc = 1; goto done;
        }
    }
    if (do_bin) {
        if (buildpackage(&pkg, &params, "binary", opt, 1) != 0) {
            rc = 1; goto done;
        }
        if (buildpackage(&pkg, &params, "objects", opt, 1) != 0) {
            rc = 1; goto done;
        }
        if (buildpackage(&pkg, &params, "local", opt, 1) != 0) {
            rc = 1; goto done;
        }
    }

    /* No chroot BUILDROOT to remove in bootstrap mode (it is empty). */
    if (opt && opt->clean && !opt->bootstrap) {
        if (exec_runv("rm", "-rf", params.BUILDROOT, (char *)0) != 0) { rc = 1; goto done; }
    }

done:
    params_free(&params);
    free(hdrfilename); free(filename);
    package_free(&pkg); package_free(&hdrpkg);
    params_free(&bparams);
    return rc;

done_ok:
    free(hdrfilename); free(filename);
    package_free(&pkg); package_free(&hdrpkg);
    params_free(&bparams);
    return rc;
}
