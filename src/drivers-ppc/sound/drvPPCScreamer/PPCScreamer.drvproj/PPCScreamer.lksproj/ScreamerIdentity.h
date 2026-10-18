/* Copyright (c) 2026 RhapsodiOS Project. */
#ifndef PPC_SCREAMER_IDENTITY_H
#define PPC_SCREAMER_IDENTITY_H
#include <string.h>

typedef struct {
    const unsigned char *bytes;
    unsigned int length;
} ScreamerBytes;

typedef enum {
    kScreamerIdentityUnknown, kScreamerIdentityScreamer,
    kScreamerIdentityOther, kScreamerIdentityConflict
} ScreamerIdentity;

static unsigned int screamer_identity_token(const unsigned char *s,
    unsigned int length)
{
    static const char *other[] = { "awacs", "burgundy", "daca", "tumbler",
        "snapper", "onyx", "DVD-Video and Audio/Video" };
    unsigned int i;
    if (length == 8 && memcmp(s, "screamer", 8) == 0)
        return 1;
    if (length == 5 && memcmp(s, "awacs", 5) == 0)
        return 4;
    for (i = 0; i < sizeof(other) / sizeof(other[0]); ++i)
        if (length == strlen(other[i]) && memcmp(s, other[i], length) == 0)
            return 2;
    return 0;
}

static __inline__ ScreamerIdentity ScreamerClassify(ScreamerBytes model,
    ScreamerBytes compatible)
{
    unsigned int flags, modelFlags, i, start, n,j;
    flags = 0;
    if ((model.length && !model.bytes) ||
        (compatible.length && !compatible.bytes))
        return kScreamerIdentityConflict;
    n = model.length;
    if (n) {
        if (model.bytes[n - 1] == 0)
            --n;
        for (i = 0; i < n; ++i)
            if (model.bytes[i] == 0)
                return kScreamerIdentityConflict;
        flags |= screamer_identity_token(model.bytes, n);
    }
    modelFlags=flags;start = 0;
    for (i = 0; i < compatible.length; ++i) {
        if (compatible.bytes[i] != 0)
            continue;
        if (i == start) {
            for(j=i;j<compatible.length;++j) if(compatible.bytes[j]) return kScreamerIdentityConflict;
            start=compatible.length;break;
        }
        flags |= screamer_identity_token(compatible.bytes + start, i - start);
        start = i + 1;
    }
    if (start != compatible.length || ((flags&1) && ((flags&2) || modelFlags==4)))
        return kScreamerIdentityConflict;
    return flags&1 ? kScreamerIdentityScreamer :
        (flags&6 ? kScreamerIdentityOther : kScreamerIdentityUnknown);
}
#endif
