#include "builder.h"
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
