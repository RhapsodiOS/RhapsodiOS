#ifndef RBUILD_PACKAGE_H
#define RBUILD_PACKAGE_H

#include "strutil.h"

typedef struct {
    char *package;
    char *version;
    char *architecture;
    char *source;
    char *description;
    char *maintainer;
    char *provides;
    char *conflicts;
    char *replaces;
    char *revision;
    char *package_revision;
    strlist build_depends;
    int has_build_depends;
} Package;

void package_init(Package *p);
void package_free(Package *p);
void package_set(char **field, const char *value);
void package_parse(Package *p, const char *data);
char *package_unparse(const Package *p);
char *package_canon_version(const Package *p);
char *package_canon_name(const Package *p);

#endif
