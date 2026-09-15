#include "products.h"
#include "macho.h"
#include "architecture.h"
#include "strutil.h"
#include <sys/types.h>
#include <sys/stat.h>
#include <dirent.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct coverage {
    char *key;
    unsigned mask;
    struct coverage *next;
} coverage;

typedef struct validation {
    const char *root;
    unsigned required;
    int objects, superset;
    coverage *groups;
} validation;

static int failure(validation *v, const char *rel, const char *reason,
                   unsigned actual, unsigned wanted) {
    fprintf(stderr, "rbuild: product root %s, path %s: %s (CPU %s; required %s)\n",
            v->root ? v->root : "(null)", rel, reason,
            architecture_label(actual) ? architecture_label(actual) : "none/invalid",
            architecture_label(wanted) ? architecture_label(wanted) : "none/invalid");
    return 1;
}

static int covers(unsigned actual, unsigned required, int superset) {
    return superset ? (actual & required) == required : actual == required;
}

static void record(validation *v, const char *key, unsigned mask) {
    coverage *g;
    for (g = v->groups; g; g = g->next) {
        if (strcmp(g->key, key) == 0) {
            g->mask |= mask;
            return;
        }
    }
    g = (coverage *)xmalloc(sizeof(*g));
    g->key = xstrdup(key);
    g->mask = mask;
    g->next = v->groups;
    v->groups = g;
}

/* i386/ppc and Project Builder i386.subproj/ppc.subproj after the source
 * name are the same CPU buckets. Repeated same-CPU names are one bucket. */
static int object_arch_component(const char *p, size_t n, unsigned *bucket) {
    if ((n == 4 && strncmp(p, "i386", 4) == 0) ||
        (n == 12 && strncmp(p, "i386.subproj", 12) == 0)) {
        if (bucket) *bucket = RB_ARCH_I386;
        return 1;
    }
    if ((n == 3 && strncmp(p, "ppc", 3) == 0) ||
        (n == 11 && strncmp(p, "ppc.subproj", 11) == 0)) {
        if (bucket) *bucket = RB_ARCH_PPC;
        return 1;
    }
    return 0;
}

static void strip_object_arch_components(char *dir, char *source_end) {
    char *read = source_end + 1;
    char *write = source_end + 1;
    int wrote = 0;
    while (*read) {
        char *slash = strchr(read, '/');
        size_t n;
        unsigned unused = 0;
        if (!slash) slash = read + strlen(read);
        n = (size_t)(slash - read);
        if (!object_arch_component(read, n, &unused)) {
            if (wrote) *write++ = '/';
            memmove(write, read, n);
            write += n;
            wrote = 1;
        }
        if (*slash == '\0') break;
        read = slash + 1;
    }
    if (!wrote) *source_end = '\0';
    else *write = '\0';
}

/* Only architecture directory components after the source name count.
 * Directory buckets take precedence over per-object .i386.o/.ppc.o pairs. */
static int code_file(validation *v, const char *rel, unsigned mask) {
    static const char prefix[] = "usr/local/lib/objs/";
    char *dir, *source_end, *p, *end, *dynamic = 0, *key;
    const char *name;
    unsigned bucket = 0, suffix = 0, seen = 0, component = 0;
    size_t n;
    int count = 0, rc = 0;
    if (!v->objects || strncmp(rel, prefix, sizeof(prefix)-1) != 0)
        return covers(mask, v->required, v->superset) ? 0 :
            failure(v, rel, "code architecture mismatch", mask, v->required);
    dir = xstrdup(rel);
    p = strrchr(dir, '/');
    if (!p) { free(dir); return 1; }
    *p = 0;
    name = rel + (p-dir) + 1;
    source_end = strchr(dir + sizeof(prefix)-1, '/');
    if (source_end) {
        for (p = source_end+1; *p; p = *end ? end+1 : end) {
            end = strchr(p, '/');
            if (!end) end = p + strlen(p);
            n = (size_t)(end-p);
            if (n == 11 && strncmp(p, "dynamic_obj", 11) == 0) dynamic = p;
            if (object_arch_component(p, n, &component)) {
                if (seen && component != seen) count = 2;
                else count = 1;
                seen = component;
                bucket = component;
            }
        }
    }
    if (!dynamic) {
        free(dir);
        return covers(mask, v->required, v->superset) ? 0 :
            failure(v, rel, "code outside object collection has wrong architecture",
                    mask, v->required);
    }
    n = strlen(name);
    if (n > 7 && strcmp(name+n-7, ".i386.o") == 0) suffix = RB_ARCH_I386;
    if (n > 6 && strcmp(name+n-6, ".ppc.o") == 0) suffix = RB_ARCH_PPC;
    if (count > 1) {
        rc = failure(v, rel, "ambiguous architecture path", mask, v->required);
    } else if (bucket) {
        if ((mask & bucket) != bucket || (suffix && suffix != bucket)) {
            rc = failure(v, rel, "object CPU/suffix disagrees with directory bucket",
                         mask, bucket);
        } else {
            /* Drop every CPU directory; keep source and remaining variant. */
            strip_object_arch_components(dir, source_end);
            key = str_cats("directory:", dir, (char *)0);
            record(v, key, bucket);
            free(key);
        }
    } else if (suffix) {
        if (mask != suffix) {
            rc = failure(v, rel, "object CPU disagrees with filename suffix",
                         mask, suffix);
        } else {
            key = str_cats("object:", rel, (char *)0);
            key[strlen(key) - (suffix == RB_ARCH_I386 ? 7 : 6)] = 0;
            record(v, key, suffix);
            free(key);
        }
    } else if (!covers(mask, v->required, v->superset)) {
        rc = failure(v, rel, "code architecture mismatch", mask, v->required);
    }
    free(dir);
    return rc;
}

static int walk(validation *v, const char *rel) {
    char *path = rel[0] ? path_join(v->root, rel) : xstrdup(v->root);
    struct stat st;
    DIR *d;
    struct dirent *de;
    int rc = 0;
    unsigned mask;
    int code;
    if (lstat(path, &st) != 0) {
        rc = failure(v, rel, "cannot inspect path", 0, v->required);
    } else if (S_ISREG(st.st_mode)) {
        if (macho_file_arches(path, &mask, &code) != 0)
            rc = failure(v, rel, "cannot inspect code (malformed or unsupported CPU)",
                         0, v->required);
        else if (code)
            rc = code_file(v, rel, mask);
    } else if (S_ISDIR(st.st_mode)) {
        d = opendir(path);
        if (!d) {
            rc = failure(v, rel, "cannot open directory", 0, v->required);
        } else {
            for (;;) {
                char *child;
                errno = 0;
                de = readdir(d);
                if (!de) {
                    if (errno)
                        rc = failure(v, rel, "cannot read directory", 0, v->required);
                    break;
                }
                if (!strcmp(de->d_name, ".") || !strcmp(de->d_name, "..")) continue;
                child = rel[0] ? path_join(rel, de->d_name) : xstrdup(de->d_name);
                rc = walk(v, child);
                free(child);
                if (rc) break;
            }
            if (closedir(d) != 0 && !rc)
                rc = failure(v, rel, "cannot close directory", 0, v->required);
        }
    }
    /* Symlinks, including directory links, are never followed. */
    free(path);
    return rc;
}

int products_validate(const char *root, unsigned required,
                      int object_collection, int allow_superset) {
    validation v;
    coverage *g, *next;
    struct stat st;
    int rc;
    v.root = root;
    v.required = required;
    v.objects = object_collection;
    v.superset = allow_superset;
    v.groups = 0;
    if (!architecture_label(required) || !root || !*root ||
        lstat(root, &st) != 0 || !S_ISDIR(st.st_mode))
        return failure(&v, ".", "invalid validation root or requested architecture",
                       0, required);
    rc = walk(&v, "");
    for (g = v.groups; g; g = next) {
        next = g->next;
        if (!rc && !covers(g->mask, required, allow_superset || v.objects))
            rc = failure(&v, g->key, "incomplete object architecture coverage",
                         g->mask, required);
        free(g->key);
        free(g);
    }
    return rc;
}
