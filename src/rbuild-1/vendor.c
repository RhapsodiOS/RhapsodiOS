#include "vendor.h"
#include "apk.h"
#include "exec.h"
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <dirent.h>
#include <sys/stat.h>

void vendor_init(Vendor *v) {
    memset(v, 0, sizeof(*v));
    v->patchlevel = 1;
}

void vendor_free(Vendor *v) {
    free(v->tarball); free(v->directory); free(v->patches);
    memset(v, 0, sizeof(*v));
}

static int is_dir(const char *path) {
    struct stat st;
    return stat(path, &st) == 0 && S_ISDIR(st.st_mode);
}

static int is_file(const char *path) {
    struct stat st;
    return stat(path, &st) == 0 && S_ISREG(st.st_mode);
}

char *vendor_path(const char *source) {
    char *p = str_cats(source, "/apk/vendor", (char *)0);
    if (is_file(p)) return p;
    free(p);
    return 0;
}

int vendor_read(Vendor *v, const char *path) {
    FILE *f = fopen(path, "r");
    char line[4096];
    char *key, *val;

    if (!f) {
        fprintf(stderr, "rbuild: unable to open %s\n", path);
        return 1;
    }
    while (fgets(line, sizeof(line), f) != 0) {
        if (!str_parse_kv(line, &key, &val)) continue;
        if (strcmp(key, "tarball") == 0) {
            free(v->tarball); v->tarball = xstrdup(val);
        } else if (strcmp(key, "directory") == 0) {
            free(v->directory); v->directory = xstrdup(val);
        } else if (strcmp(key, "patches") == 0) {
            free(v->patches); v->patches = xstrdup(val);
            v->patches_explicit = 1;
        } else if (strcmp(key, "patchlevel") == 0) {
            v->patchlevel = atoi(val);
        }
        /* unknown keys ignored, as in pkginfo_read */
    }
    fclose(f);

    if (!v->tarball) {
        fprintf(stderr, "rbuild: %s: missing tarball\n", path);
        return 1;
    }
    if (!v->directory) {
        fprintf(stderr, "rbuild: %s: missing directory\n", path);
        return 1;
    }
    if (!v->patches) v->patches = xstrdup("patches");
    return 0;
}

static int cmp_str(const void *a, const void *b) {
    return strcmp(*(const char **) a, *(const char **) b);
}

int vendor_list_patches(const Vendor *v, const char *srcdir, strlist *out) {
    char *dir = str_cats(srcdir, "/", v->patches, (char *)0);
    DIR *d;
    struct dirent *de;

    if (!is_dir(dir)) {
        int rc = 0;
        if (v->patches_explicit) {
            fprintf(stderr, "rbuild: %s: patch directory does not exist\n", dir);
            rc = 1;
        }
        free(dir);
        return rc;
    }
    d = opendir(dir);
    if (!d) {
        fprintf(stderr, "rbuild: unable to open %s\n", dir);
        free(dir);
        return 1;
    }
    while ((de = readdir(d)) != 0) {
        if (!str_has_suffix(de->d_name, ".patch")) continue;
        strlist_push_owned(out, path_join(dir, de->d_name));
    }
    closedir(d);
    free(dir);
    /* Same directory prefix on every path, so this orders by filename. */
    if (out->count > 1)
        qsort(out->items, out->count, sizeof(char *), cmp_str);
    return 0;
}

/* Number of entries other than "." and ".."; the first is returned in *name
   (malloc'd). -1 if the directory cannot be opened. */
static int sole_entry(const char *dir, char **name) {
    DIR *d = opendir(dir);
    struct dirent *de;
    int n = 0;

    *name = 0;
    if (!d) return -1;
    while ((de = readdir(d)) != 0) {
        if (strcmp(de->d_name, ".") == 0 || strcmp(de->d_name, "..") == 0)
            continue;
        if (n == 0) *name = xstrdup(de->d_name);
        n++;
    }
    closedir(d);
    return n;
}

int vendor_apply(const Vendor *v, const char *srcdir, const char *srcroot,
                 const Toolchain *tc) {
    char *dest = str_cats(srcroot, "/", v->directory, (char *)0);
    char *tmp = str_cats(srcroot, "/.vendor-tmp", (char *)0);
    char *tarball = str_cats(srcdir, "/", v->tarball, (char *)0);
    char *entry = 0;
    char *moved;
    strlist patches;
    char plevel[16];
    struct stat st;
    size_t i;
    int n;
    int rc = 1;

    strlist_init(&patches);
    if (!is_file(tarball)) {
        fprintf(stderr, "rbuild: %s: tarball not found\n", tarball);
        goto done;
    }
    if (vendor_list_patches(v, srcdir, &patches) != 0) goto done;
    /* SRCROOT was just wiped and rsynced, so dest can only exist if the
       project still carries its expanded tree next to apk/vendor. */
    if (!exec_dry_run && lstat(dest, &st) == 0) {
        fprintf(stderr, "rbuild: %s already exists; a project with "
                "apk/vendor must not also carry the expanded tree\n", dest);
        goto done;
    }

    printf("vendoring %s into %s\n", v->tarball, dest);
    fflush(stdout);
    if (exec_check(exec_runv("mkdir", tmp, (char *)0))) goto done;
    if (apk_untar(tarball, tmp, tc) != 0) goto done;
    if (exec_dry_run) {
        printf("rename sole entry of %s to %s\n", tmp, dest);
        fflush(stdout);
    } else {
        n = sole_entry(tmp, &entry);
        if (n != 1) {
            fprintf(stderr, "rbuild: %s: tarball must contain exactly one "
                    "top-level entry (found %d)\n", tarball, n);
            goto done;
        }
        moved = str_cats(tmp, "/", entry, (char *)0);
        n = exec_runv("mv", moved, dest, (char *)0);
        free(moved);
        if (exec_check(n)) goto done;
    }
    if (exec_check(exec_runv("rmdir", tmp, (char *)0))) goto done;

    sprintf(plevel, "-p%d", v->patchlevel);
    for (i = 0; i < patches.count; i++) {
        printf("applying %s\n", patches.items[i]);
        fflush(stdout);
        n = exec_runv("patch", "-f", "-E", "--no-backup-if-mismatch", plevel,
                      "-d", dest, "-i", patches.items[i], (char *)0);
        if (exec_check(n)) {
            fprintf(stderr, "rbuild: %s: patch failed\n", patches.items[i]);
            goto done;
        }
    }
    rc = 0;

done:
    strlist_free(&patches);
    free(entry); free(dest); free(tmp); free(tarball);
    return rc;
}
