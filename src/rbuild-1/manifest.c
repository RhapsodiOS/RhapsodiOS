#include "manifest.h"
#include <string.h>
#include <stdio.h>
#include <sys/stat.h>
#include <dirent.h>

void manifest_init(Manifest *m) {
    m->cap = 8;
    m->count = 0;
    m->items = (ManifestEntry *) xmalloc(m->cap * sizeof(ManifestEntry));
}

void manifest_free(Manifest *m) {
    size_t i;
    for (i = 0; i < m->count; i++) {
        free(m->items[i].type);
        free(m->items[i].source);
        free(m->items[i].targets);
    }
    free(m->items);
    m->items = 0; m->count = 0; m->cap = 0;
}

static ManifestEntry *manifest_new(Manifest *m) {
    ManifestEntry *e;
    if (m->count == m->cap) {
        m->cap *= 2;
        m->items = (ManifestEntry *) xrealloc(m->items, m->cap * sizeof(ManifestEntry));
    }
    e = &m->items[m->count++];
    e->type = 0; e->source = 0; e->targets = 0;
    return e;
}

/* Reads all children of dir and adds one "dir"-typed entry per child.
   NOTE: the reference Perl (Manifest.pm readdir) has a bug: its skip test
   `next if $dir =~ /\.|\.\./` checks $dir (the directory path being read),
   not $i (the current child), so it never actually skips "." or "..".
   That is unintentional; rbuild fixes it here by testing the child name
   itself and skipping "." and "..", which is the correct behavior. */
static int read_directory(Manifest *m, const char *dir) {
    DIR *d = opendir(dir);
    struct dirent *de;
    if (!d) { fprintf(stderr, "rbuild: unable to open \"%s\"\n", dir); return 1; }
    while ((de = readdir(d)) != 0) {
        ManifestEntry *e;
        if (strcmp(de->d_name, ".") == 0 || strcmp(de->d_name, "..") == 0)
            continue;
        e = manifest_new(m);
        e->type = xstrdup("dir");
        e->source = path_join(dir, de->d_name);
    }
    closedir(d);
    return 0;
}

static int read_file(Manifest *m, const char *path) {
    FILE *f = fopen(path, "r");
    char line[4096];
    if (!f) { fprintf(stderr, "rbuild: unable to open \"%s\"\n", path); return 1; }
    while (fgets(line, sizeof(line), f) != 0) {
        char *hash;
        strlist toks;
        str_chomp(line);
        hash = strchr(line, '#');
        if (hash) *hash = '\0';
        strlist_init(&toks);
        str_split_ws(line, &toks);
        if (toks.count == 0) { strlist_free(&toks); continue; }
        {
            ManifestEntry *e = manifest_new(m);
            e->type = xstrdup(toks.items[0]);
            if (toks.count >= 2) e->source = xstrdup(toks.items[1]);
            else e->source = xstrdup("");
            if (toks.count >= 3) e->targets = xstrdup(toks.items[2]);
        }
        strlist_free(&toks);
    }
    fclose(f);
    return 0;
}

int manifest_read(Manifest *m, const char *path) {
    struct stat st;
    if (stat(path, &st) == 0 && S_ISDIR(st.st_mode))
        return read_directory(m, path);
    return read_file(m, path);
}
