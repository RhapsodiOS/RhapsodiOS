#include "architecture.h"
#include <string.h>

int architecture_parse(const char *label, unsigned *mask) {
    unsigned value;
    if (!label || strcmp(label, "universal-apple-rhapsody") == 0)
        value = RB_ARCH_UNIVERSAL;
    else if (strcmp(label, "i386") == 0 ||
             strcmp(label, "i386-apple-rhapsody") == 0)
        value = RB_ARCH_I386;
    else if (strcmp(label, "ppc") == 0 ||
             strcmp(label, "ppc-apple-rhapsody") == 0)
        value = RB_ARCH_PPC;
    else
        return 1;
    *mask = value;
    return 0;
}

int architecture_resolve(unsigned source, unsigned operation, unsigned *effective) {
    if (source < RB_ARCH_I386 || source > RB_ARCH_UNIVERSAL)
        return 1;
    if (operation != 0 && operation != RB_ARCH_I386 &&
        operation != RB_ARCH_PPC && operation != RB_ARCH_UNIVERSAL)
        return 1;
    if (operation != 0 && (source & operation) != operation)
        return 1;
    *effective = operation ? operation : source;
    return 0;
}

const char *architecture_label(unsigned mask) {
    switch (mask) {
    case RB_ARCH_I386: return "i386-apple-rhapsody";
    case RB_ARCH_PPC: return "ppc-apple-rhapsody";
    case RB_ARCH_UNIVERSAL: return "universal-apple-rhapsody";
    }
    return 0;
}

const char *architecture_archs(unsigned mask) {
    switch (mask) {
    case RB_ARCH_I386: return "i386";
    case RB_ARCH_PPC: return "ppc";
    case RB_ARCH_UNIVERSAL: return "i386 ppc";
    }
    return 0;
}

const char *architecture_cflags(unsigned mask) {
    switch (mask) {
    case RB_ARCH_I386: return "-arch i386";
    case RB_ARCH_PPC: return "-arch ppc";
    case RB_ARCH_UNIVERSAL: return "-arch i386 -arch ppc";
    }
    return 0;
}

const char *architecture_filename_token(unsigned mask) {
    switch (mask) {
    case RB_ARCH_I386: return "i386";
    case RB_ARCH_PPC: return "ppc";
    case RB_ARCH_UNIVERSAL: return "universal";
    }
    return 0;
}

int architecture_path_has_token(const char *path, unsigned mask) {
    const char *token = architecture_filename_token(mask);
    const char *slash;
    const char *base;
    size_t base_len;
    size_t token_len;
    size_t need;
    if (path == 0 || token == 0) return 0;
    slash = strrchr(path, '/');
    base = slash ? slash + 1 : path;
    base_len = strlen(base);
    token_len = strlen(token);
    need = token_len + 5; /* - + token + .apk */
    if (base_len < need) return 0;
    if (base[base_len - need] != '-') return 0;
    if (strncmp(base + base_len - need + 1, token, token_len) != 0) return 0;
    return strcmp(base + base_len - 4, ".apk") == 0;
}
