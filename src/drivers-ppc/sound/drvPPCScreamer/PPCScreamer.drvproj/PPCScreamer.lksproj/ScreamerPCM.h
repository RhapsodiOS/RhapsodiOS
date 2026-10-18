/* Copyright (c) 2026 RhapsodiOS Project. */
#ifndef PPC_SCREAMER_PCM_H
#define PPC_SCREAMER_PCM_H
#include "ScreamerCore.h"

/* Signed big-endian 16-bit stereo; copy precedes inversion if both are set. */
ScreamerStatus ScreamerPCMCorrect(void *, unsigned long, unsigned int,
    unsigned int);
#endif
