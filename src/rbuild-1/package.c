#include "package.h"
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
    free(p->provides); free(p->conflicts); free(p->replaces);
    free(p->revision); free(p->package_revision);
    strlist_free(&p->build_depends);
    memset(p, 0, sizeof(*p));
}

void package_set(char **field, const char *value) {
    free(*field);
    *field = value ? xstrdup(value) : 0;
}

/* Assign a parsed key/value pair into the struct. Unknown keys are
   ignored (mirrors Perl's Package.pm storing them in a hash that is
   never read back for anything but the known fields). */
static void assign_field(Package *p, const char *key, const char *value) {
    if (strcmp(key, "package") == 0) package_set(&p->package, value);
    else if (strcmp(key, "version") == 0) package_set(&p->version, value);
    else if (strcmp(key, "architecture") == 0) package_set(&p->architecture, value);
    else if (strcmp(key, "source") == 0) package_set(&p->source, value);
    else if (strcmp(key, "description") == 0) package_set(&p->description, value);
    else if (strcmp(key, "maintainer") == 0) package_set(&p->maintainer, value);
    else if (strcmp(key, "provides") == 0) package_set(&p->provides, value);
    else if (strcmp(key, "conflicts") == 0) package_set(&p->conflicts, value);
    else if (strcmp(key, "replaces") == 0) package_set(&p->replaces, value);
    else if (strcmp(key, "revision") == 0) package_set(&p->revision, value);
    else if (strcmp(key, "package_revision") == 0)
        package_set(&p->package_revision, value);
    else if (strcmp(key, "build-depends") == 0) {
        strlist_free(&p->build_depends);
        strlist_init(&p->build_depends);
        str_split_chars(value, " ,", &p->build_depends);
        p->has_build_depends = 1;
    }
}

/* Parse Debian-control-style text. Single scan over physical lines:
   a line beginning with whitespace is a continuation and is folded onto
   the current field's value as "\n " + trim(line) (Package.pm:33-39);
   any other line is split at the first ':' to become a new field,
   flushing whatever field was previously accumulating. Lines with
   neither leading whitespace nor a colon are silently ignored, matching
   Perl's /^(\S+):\s*(.*)\s*$/mg which simply skips non-matching lines. */
void package_parse(Package *p, const char *data) {
    char *copy = xstrdup(data);
    char *cursor = copy;
    char *key = 0;
    sbuf value;
    int have = 0;

    sbuf_init(&value);

    while (*cursor != '\0') {
        char *line = cursor;
        char *nl = strchr(cursor, '\n');
        if (nl != 0) { *nl = '\0'; cursor = nl + 1; }
        else { cursor = cursor + strlen(cursor); }

        if (line[0] == ' ' || line[0] == '\t') {
            if (have) {
                sbuf_puts(&value, "\n ");
                sbuf_puts(&value, str_trim(line));
            }
        } else {
            char *colon;
            if (have) {
                assign_field(p, key, value.buf);
                have = 0;
                sbuf_free(&value);
                sbuf_init(&value);
            }
            colon = strchr(line, ':');
            if (colon != 0) {
                char *val;
                *colon = '\0';
                str_lowercase(line);
                key = line;
                val = colon + 1;
                sbuf_puts(&value, str_trim(val));
                have = 1;
            }
        }
    }

    if (have) assign_field(p, key, value.buf);

    sbuf_free(&value);
    free(copy);
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

/* apk stem: "<pkgname>-<pkgver>". Redefined from Perl's canon_name
   (pkg_ver_arch); architecture now lives only in .PKGINFO. */
char *package_canon_name(const Package *p) {
    char *ver = package_canon_version(p);
    char *out = str_cats(p->package ? p->package : "", "-", ver, (char *)0);
    free(ver);
    return out;
}

static void unparse_field(sbuf *s, const char *label, const char *value) {
    sbuf_puts(s, label);
    sbuf_puts(s, ": ");
    sbuf_puts(s, value ? value : "");
    sbuf_putc(s, '\n');
}

char *package_unparse(const Package *p) {
    sbuf s;
    char *out;
    sbuf_init(&s);
    unparse_field(&s, "Package", p->package);
    if (p->provides) unparse_field(&s, "Provides", p->provides);
    if (p->conflicts) unparse_field(&s, "Conflicts", p->conflicts);
    if (p->replaces) unparse_field(&s, "Replaces", p->replaces);
    unparse_field(&s, "Maintainer", p->maintainer);
    unparse_field(&s, "Version", p->version);
    unparse_field(&s, "Source", p->source);
    if (p->has_build_depends) {
        sbuf bd;
        char *joined;
        size_t i;
        sbuf_init(&bd);
        for (i = 0; i < p->build_depends.count; i++) {
            if (i) sbuf_puts(&bd, ", ");
            sbuf_puts(&bd, p->build_depends.items[i]);
        }
        joined = sbuf_steal(&bd);
        unparse_field(&s, "Build-Depends", joined);
        free(joined);
        sbuf_free(&bd);
    }
    unparse_field(&s, "Architecture", p->architecture);
    unparse_field(&s, "Description", p->description);
    out = sbuf_steal(&s);
    sbuf_free(&s);
    return out;
}
