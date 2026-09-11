#include "kernel.h"

#include <sys/types.h>
#include <sys/stat.h>
#include <dirent.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int is_dir(const char *path) {
    struct stat st;
    if (path == 0 || stat(path, &st) != 0) return 0;
    return S_ISDIR(st.st_mode);
}

static int has_control(const char *srcdir, const char *rel) {
    char *full;
    char *control;
    struct stat st;
    int ok = 0;

    full = path_join(srcdir, rel);
    control = path_join(full, "dpkg/control");
    if (stat(control, &st) == 0 && S_ISREG(st.st_mode)) ok = 1;
    free(full);
    free(control);
    return ok;
}

static int driver_name_ok(const char *name) {
    if (name == 0) return 0;
    if (str_has_prefix(name, "drv")) return 1;
    if (str_has_prefix(name, "Intel")) return 1;
    return 0;
}

static int cmp_cstr(const void *va, const void *vb) {
    const char *a = *(char *const *)va;
    const char *b = *(char *const *)vb;
    return strcmp(a, b);
}

static void strlist_sort_unique(strlist *l) {
    size_t i;
    size_t out;

    if (l == 0 || l->count < 2) return;
    qsort(l->items, l->count, sizeof(char *), cmp_cstr);
    out = 1;
    for (i = 1; i < l->count; i++) {
        if (strcmp(l->items[out - 1], l->items[i]) == 0) {
            free(l->items[i]);
        } else {
            l->items[out++] = l->items[i];
        }
    }
    l->count = out;
}

int kernel_arch_safe(const char *arch) {
    const unsigned char *p;

    if (arch == 0 || arch[0] == '\0') return 0;
    if (!((arch[0] >= 'A' && arch[0] <= 'Z') ||
          (arch[0] >= 'a' && arch[0] <= 'z') ||
          arch[0] == '_')) return 0;
    for (p = (const unsigned char *)arch + 1; *p != '\0'; p++) {
        if (!((*p >= 'A' && *p <= 'Z') || (*p >= 'a' && *p <= 'z') ||
              (*p >= '0' && *p <= '9') || *p == '_')) return 0;
    }
    return 1;
}

int kernel_core_packages(const char *arch, strlist *out) {
    char *pexpert;

    if (!kernel_arch_safe(arch) || out == 0) return -1;
    strlist_push(out, "driverkit-3");
    strlist_push(out, "driverTools-1");
    strlist_push(out, "kernload-1");
    pexpert = str_cats("drivers-", arch, "/bus/drvPExpert", (char *)0);
    strlist_push_owned(out, pexpert);
    strlist_push(out, "kernel-7");
    return 0;
}

int kernel_scan_drivers(const char *srcdir, const char *arch, strlist *out) {
    char *arch_dir_name;
    char *arch_root;
    DIR *categories;
    struct dirent *cat;

    if (!kernel_arch_safe(arch) || srcdir == 0 || out == 0) return -1;
    if (!is_dir(srcdir)) return -1;

    arch_dir_name = str_cats("drivers-", arch, (char *)0);
    arch_root = path_join(srcdir, arch_dir_name);
    free(arch_dir_name);

    categories = opendir(arch_root);
    if (categories != 0) {
        while ((cat = readdir(categories)) != 0) {
            char *cat_rel;
            char *cat_full;
            DIR *projects;
            struct dirent *proj;

            if (strcmp(cat->d_name, ".") == 0 || strcmp(cat->d_name, "..") == 0)
                continue;
            cat_rel = str_cats("drivers-", arch, "/", cat->d_name, (char *)0);
            cat_full = path_join(srcdir, cat_rel);
            if (!is_dir(cat_full)) {
                free(cat_rel);
                free(cat_full);
                continue;
            }
            projects = opendir(cat_full);
            if (projects == 0) {
                free(cat_rel);
                free(cat_full);
                continue;
            }
            while ((proj = readdir(projects)) != 0) {
                char *rel;

                if (strcmp(proj->d_name, ".") == 0 ||
                    strcmp(proj->d_name, "..") == 0) continue;
                if (!driver_name_ok(proj->d_name)) continue;
                if (strcmp(proj->d_name, "drvPExpert") == 0) continue;
                rel = path_join(cat_rel, proj->d_name);
                if (has_control(srcdir, rel)) strlist_push(out, rel);
                free(rel);
            }
            closedir(projects);
            free(cat_rel);
            free(cat_full);
        }
        closedir(categories);
    }
    free(arch_root);

    if (has_control(srcdir, "drvBPF")) strlist_push(out, "drvBPF");
    if (has_control(srcdir, "drvPortServer")) strlist_push(out, "drvPortServer");
    if (has_control(srcdir, "drvSCSIServer")) strlist_push(out, "drvSCSIServer");
    if (has_control(srcdir, "drvSCSITape")) strlist_push(out, "drvSCSITape");
    strlist_sort_unique(out);
    return 0;
}

static void skip_ws(const char **p) {
    while (**p == ' ' || **p == '\t' || **p == '\n' || **p == '\r')
        (*p)++;
}

static int kernel_rel_safe(const char *rel) {
    const unsigned char *p;

    if (rel == 0 || rel[0] == '\0' || rel[0] == '/') return 0;
    if (strcmp(rel, "..") == 0 || str_has_prefix(rel, "../") ||
        strstr(rel, "/../") != 0 || str_has_suffix(rel, "/..")) return 0;
    for (p = (const unsigned char *)rel; *p != '\0'; p++) {
        if (!((*p >= 'A' && *p <= 'Z') || (*p >= 'a' && *p <= 'z') ||
              (*p >= '0' && *p <= '9') || *p == '_' || *p == '.' ||
              *p == '/' || *p == '+' || *p == '-')) return 0;
    }
    return 1;
}

static int parse_json_string(const char **p, char **out) {
    sbuf b;

    *out = 0;
    if (**p != '"') return -1;
    (*p)++;
    sbuf_init(&b);
    while (**p != '\0' && **p != '"') {
        if ((unsigned char)**p < 32 || **p == '\\') {
            sbuf_free(&b);
            return -1;
        }
        sbuf_putc(&b, **p);
        (*p)++;
    }
    if (**p != '"') {
        sbuf_free(&b);
        return -1;
    }
    (*p)++;
    *out = sbuf_steal(&b);
    sbuf_free(&b);
    return 0;
}

int kernel_driver_blacklisted(const strlist *skip, const char *rel) {
    size_t i;

    if (skip == 0 || rel == 0) return 0;
    for (i = 0; i < skip->count; i++)
        if (strcmp(skip->items[i], rel) == 0) return 1;
    return 0;
}

int kernel_load_blacklist(const char *path, strlist *out) {
    FILE *f;
    sbuf data;
    char buf[512];
    size_t n;
    const char *p;
    char *key = 0;
    strlist parsed;
    size_t i;
    int rc = -1;

    if (path == 0 || out == 0) return -1;
    f = fopen(path, "r");
    if (f == 0) return -1;
    sbuf_init(&data);
    while ((n = fread(buf, 1, sizeof(buf), f)) > 0) sbuf_putn(&data, buf, n);
    fclose(f);
    strlist_init(&parsed);
    p = data.buf;
    skip_ws(&p);
    if (*p != '{') goto done;
    p++;
    skip_ws(&p);
    if (parse_json_string(&p, &key) != 0) goto done;
    if (strcmp(key, "skip") != 0) goto done;
    skip_ws(&p);
    if (*p != ':') goto done;
    p++;
    skip_ws(&p);
    if (*p != '[') goto done;
    p++;
    skip_ws(&p);
    if (*p == ']') {
        p++;
    } else {
        for (;;) {
            char *item = 0;
            if (parse_json_string(&p, &item) != 0) goto done;
            if (!kernel_rel_safe(item)) {
                free(item);
                goto done;
            }
            strlist_push_owned(&parsed, item);
            skip_ws(&p);
            if (*p == ',') {
                p++;
                skip_ws(&p);
                continue;
            }
            if (*p == ']') {
                p++;
                break;
            }
            goto done;
        }
    }
    skip_ws(&p);
    if (*p != '}') goto done;
    p++;
    skip_ws(&p);
    if (*p != '\0') goto done;
    for (i = 0; i < parsed.count; i++) strlist_push(out, parsed.items[i]);
    strlist_sort_unique(out);
    rc = 0;
done:
    free(key);
    strlist_free(&parsed);
    sbuf_free(&data);
    return rc;
}
