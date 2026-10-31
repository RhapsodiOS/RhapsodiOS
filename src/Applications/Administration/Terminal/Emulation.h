#ifndef TERMINAL_EMULATION_H
#define TERMINAL_EMULATION_H

#import <Foundation/NSObject.h>

#include "Chunk.h"

@class Terminal;

typedef struct {
    signed char var0;
    signed char var1;
    signed char var2;
    signed char var3;
    signed char var4;
    signed char var5;
    signed char var6;
    unsigned char _padding0;
    unsigned short var7;
    unsigned short var8;
    signed char var9;
    unsigned char _padding1[3];
    char *var10;
    id var11;
    float var12;
    unsigned int var13;
    unsigned int var14;
    unsigned char var15;
    unsigned char _padding2[3];
    id var16;
    int var17;
    int var18;
    id var19[8];
    int var20;
} TerminalEmulationDefaults;

typedef struct {
    unsigned char superclass[12];
    unsigned int flags;
    unsigned char destinationLine;
    unsigned char _padding0[3];
    SEL writer;
    unsigned char vt52Flags;
    unsigned char _padding1[3];
    void *vt100Emulator;
} TerminalVT52Layout;

#if defined(__cplusplus)
static_assert(sizeof(TerminalVT52Layout) == 32, "Terminal vt52 ABI");
#elif defined(__STDC_VERSION__) && __STDC_VERSION__ >= 201112L
_Static_assert(sizeof(TerminalVT52Layout) == 32, "Terminal vt52 ABI");
#endif

@interface Emulation : NSObject
{
    Terminal *term;
    unsigned short meta;
    unsigned short _padding0;
    unsigned int eflags;
}

- (void)output:(char *)bytes len:(unsigned int)length;
- (void)ctrloutput:(unsigned char)value;
- (int)key:(id)event;
- (void)deAlternatize:(id)event;

- (void)setTerminal:(Terminal *)value;
- (Terminal *)terminal;
- (void)translateChars:(char *)bytes len:(unsigned int)length;
- (short)metaCharacter;
- (char)autowrapIsOn;
- (id)initDefaults:(const TerminalEmulationDefaults *)defaults;
- (void)setDefaults:(const TerminalEmulationDefaults *)defaults;
- (void)termDidResize:(id)sender;
- (void)wrapoutput;

@end

@interface vt52 : Emulation
{
    unsigned char destinationLine;
    unsigned char _padding1[3];
    SEL writer;
    unsigned char vt52flags;
    unsigned char _padding2[3];
    id vt100Emulator;
}

- (id)initDefaults:(const TerminalEmulationDefaults *)defaults;
- (void)setDefaults:(const TerminalEmulationDefaults *)defaults;
- (void)translateChars:(char *)bytes len:(unsigned int)length;
- (void)wrapoutput;
- (void)ctrloutput:(unsigned char)value;
- (int)key:(id)event;
- (id)vt52getcol:(char)value;
- (id)vt52getline:(char)value;
- (id)vt52Escape:(unsigned char)value;
- (void)vt100Emulator:(id)value;
- (void)reset;

@end

typedef struct {
    unsigned char superclass[16];
    id vt52Emulator;
    unsigned int vflags;
    unsigned char sx;
    unsigned char sy;
    unsigned char _padding0[2];
    TerminalChunk *args;
    unsigned int narg;
    TerminalChunk *tabs;
    TerminalChunk *text;
    SEL writer;
} TerminalVT100Layout;

#if defined(__cplusplus)
static_assert(sizeof(TerminalVT100Layout) == 48, "Terminal vt100 ABI");
#elif defined(__STDC_VERSION__) && __STDC_VERSION__ >= 201112L
_Static_assert(sizeof(TerminalVT100Layout) == 48, "Terminal vt100 ABI");
#endif

@interface vt100 : Emulation
{
    id vt52Emulator;
    unsigned int vflags;
    unsigned char sx;
    unsigned char sy;
    unsigned char _padding2[2];
    TerminalChunk *args;
    unsigned int narg;
    TerminalChunk *tabs;
    TerminalChunk *text;
    SEL writer;
}

- (int)key:(id)event;
- (void)setTerminal:(Terminal *)value;
- (void)setDefaults:(const TerminalEmulationDefaults *)defaults;
- (void)linefeed;
- (void)revlinefeed;
- (void)reset;
- (void)ctrloutput:(unsigned char)value;
- (void)vt100Escape:(unsigned char)value;
- (void)vt100Hash:(unsigned char)value;
- (void)vt100CharsetG0:(unsigned char)value;
- (void)vt100CharsetG1:(unsigned char)value;
- (void)vt100CollectString:(unsigned char)value;
- (id)vt100string:(unsigned char)value;
- (void)vt100CSI:(unsigned char)value;
- (void)vt100CollectArgs:(unsigned char)value;
- (void)vt100DoCSI:(unsigned char)value;
- (void)_insertline:(unsigned int)count;
- (void)_deleteline:(unsigned int)count;
- (void)_deletechar:(unsigned int)count;
- (void)vt100Private:(unsigned char)value;
- (void)translateChars:(char *)bytes len:(unsigned int)length;

@end

#endif
