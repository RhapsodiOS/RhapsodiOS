#include "toolchain.h"

#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    const char *key;
    size_t offset;
} ToolchainField;

#define FIELD(name) { #name, offsetof(Toolchain, name) }

static const ToolchainField fields[] = {
    FIELD(profile),
    FIELD(build_cc),
    FIELD(target_cc),
    FIELD(target_ar),
    FIELD(target_ranlib),
    FIELD(make),
    FIELD(shell),
    FIELD(tar),
    FIELD(gzip),
    FIELD(rsync),
    FIELD(path),
    FIELD(arch_flags),
    FIELD(cpp_flags),
    FIELD(ld_flags),
    FIELD(ln)
};

#define FIELD_COUNT (sizeof(fields) / sizeof(fields[0]))

static char **field_slot(Toolchain *tc, size_t offset) {
    return (char **)((char *)tc + offset);
}

void toolchain_init(Toolchain *tc) {
    memset(tc, 0, sizeof(*tc));
}

void toolchain_free(Toolchain *tc) {
    size_t i;
    for (i = 0; i < FIELD_COUNT; i++) {
        char **slot = field_slot(tc, fields[i].offset);
        free(*slot);
        *slot = 0;
    }
}

int toolchain_load(Toolchain *tc, const char *path) {
    FILE *fp;
    char line[4096];
    unsigned long line_no = 0;

    fp = fopen(path, "r");
    if (fp == 0) {
        fprintf(stderr, "rbuild: cannot open toolchain profile %s\n", path);
        return 1;
    }
    while (fgets(line, sizeof(line), fp) != 0) {
        char *text;
        char *equals;
        char *key;
        char *value;
        size_t i;

        line_no++;
        if (strchr(line, '\n') == 0 && !feof(fp)) {
            fprintf(stderr, "rbuild: malformed toolchain profile line %lu\n",
                    line_no);
            fclose(fp);
            return 1;
        }
        text = str_trim(str_chomp(line));
        if (*text == '\0' || *text == '#') continue;
        equals = strchr(text, '=');
        if (equals == 0) {
            fprintf(stderr, "rbuild: malformed toolchain profile line %lu\n",
                    line_no);
            fclose(fp);
            return 1;
        }
        *equals = '\0';
        key = str_trim(text);
        value = str_trim(equals + 1);
        if (*key == '\0') {
            fprintf(stderr, "rbuild: malformed toolchain profile line %lu\n",
                    line_no);
            fclose(fp);
            return 1;
        }
        for (i = 0; i < FIELD_COUNT; i++) {
            if (strcmp(key, fields[i].key) == 0) break;
        }
        if (i == FIELD_COUNT) {
            fprintf(stderr, "rbuild: unknown toolchain profile key %s\n", key);
            fclose(fp);
            return 1;
        }
        {
            char **slot = field_slot(tc, fields[i].offset);
            if (*slot != 0) {
                fprintf(stderr, "rbuild: duplicate toolchain profile key %s\n",
                        key);
                fclose(fp);
                return 1;
            }
            *slot = xstrdup(value);
        }
    }
    if (ferror(fp)) {
        fprintf(stderr, "rbuild: error reading toolchain profile %s\n", path);
        fclose(fp);
        return 1;
    }
    fclose(fp);
    return 0;
}

int toolchain_validate(const Toolchain *tc) {
    size_t i;
    for (i = 0; i < FIELD_COUNT; i++) {
        char *const *slot = (char *const *)((const char *)tc + fields[i].offset);
        if (*slot == 0 || **slot == '\0') {
            fprintf(stderr, "rbuild: toolchain profile missing %s\n",
                    fields[i].key);
            return 1;
        }
    }
    return 0;
}

void toolchain_expand_words(const char *value, const char *sysroot,
                            strlist *out) {
    static const char marker[] = "@SYSROOT@";
    const char *p = value ? value : "";
    const char *match;
    sbuf expanded;

    sbuf_init(&expanded);
    while ((match = strstr(p, marker)) != 0) {
        sbuf_putn(&expanded, p, (size_t)(match - p));
        sbuf_puts(&expanded, sysroot);
        p = match + sizeof(marker) - 1;
    }
    sbuf_puts(&expanded, p);
    str_split_ws(expanded.buf, out);
    sbuf_free(&expanded);
}
