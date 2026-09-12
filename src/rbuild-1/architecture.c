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
    if (operation != 0 && operation != RB_ARCH_I386 && operation != RB_ARCH_PPC)
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
