#ifndef RBUILD_MANIFEST_H
#define RBUILD_MANIFEST_H

#include "strutil.h"

typedef struct {
    char *type;
    char *source;
    char *targets;   /* may be NULL */
} ManifestEntry;

typedef struct {
    ManifestEntry *items;
    size_t count;
    size_t cap;
} Manifest;

void manifest_init(Manifest *m);
void manifest_free(Manifest *m);
int manifest_read(Manifest *m, const char *path);

#endif
