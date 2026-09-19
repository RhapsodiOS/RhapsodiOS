#include "package.h"
#include "architecture.h"
#include <string.h>
#include <stdio.h>

void package_init(Package *p) {
    memset(p, 0, sizeof(*p));
    strlist_init(&p->build_depends);
    p->has_build_depends = 0;
}

void package_free(Package *p) {
    free(p->package); free(p->version); free(p->architecture);
    free(p->source); free(p->description); free(p->maintainer);
    free(p->url); free(p->license);
    free(p->provides); free(p->conflicts); free(p->replaces);
    free(p->revision); free(p->package_revision);
    strlist_free(&p->build_depends);
    memset(p, 0, sizeof(*p));
}

void package_set(char **field, const char *value) {
    free(*field);
    *field = value ? xstrdup(value) : 0;
}

int package_copy(Package *dst, const Package *src) {
    size_t i;
    package_free(dst);
    package_init(dst);
    package_set(&dst->package, src->package);
    package_set(&dst->version, src->version);
    package_set(&dst->architecture, src->architecture);
    package_set(&dst->source, src->source);
    package_set(&dst->description, src->description);
    package_set(&dst->maintainer, src->maintainer);
    package_set(&dst->url, src->url);
    package_set(&dst->license, src->license);
    package_set(&dst->provides, src->provides);
    package_set(&dst->conflicts, src->conflicts);
    package_set(&dst->replaces, src->replaces);
    package_set(&dst->revision, src->revision);
    package_set(&dst->package_revision, src->package_revision);
    for (i = 0; i < src->build_depends.count; i++)
        strlist_push(&dst->build_depends, src->build_depends.items[i]);
    dst->has_build_depends = src->has_build_depends;
    return 0;
}

char *package_canon_version(const Package *p) {
    sbuf s;
    char *out;
    /* Package.pm dies when both are set; fail loudly rather than emit an
       ambiguous version (uses the codebase's fatal-error idiom). */
    if (p->revision && p->package_revision) {
        fprintf(stderr,
            "rbuild: package has both revision and package_revision entries\n");
        exit(2);
    }
    sbuf_init(&s);
    sbuf_puts(&s, p->version ? p->version : "");
    if (p->package_revision) sbuf_puts(&s, p->package_revision);
    if (p->revision) sbuf_puts(&s, p->revision);
    out = sbuf_steal(&s);
    sbuf_free(&s);
    return out;
}

/* apk stem: "<pkgname>-<pkgver>-<shortarch>". */
char *package_canon_name(const Package *p) {
    unsigned mask = 0;
    const char *token;
    char *ver;
    char *out;
    if (p->architecture && p->architecture[0] == '\0') {
        fprintf(stderr,
            "rbuild: missing or unsupported architecture for package \"%s\"\n",
            p->package ? p->package : "");
        return 0;
    }
    if (architecture_parse(p->architecture, &mask) != 0 ||
        (token = architecture_filename_token(mask)) == 0) {
        fprintf(stderr,
            "rbuild: missing or unsupported architecture for package \"%s\"\n",
            p->package ? p->package : "");
        return 0;
    }
    ver = package_canon_version(p);
    out = str_cats(p->package ? p->package : "", "-", ver, "-", token,
                   (char *)0);
    free(ver);
    return out;
}
