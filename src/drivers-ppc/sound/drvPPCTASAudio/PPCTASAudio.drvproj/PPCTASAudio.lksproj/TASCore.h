#ifndef TAS_CORE_H
#define TAS_CORE_H

#define TAS_MAX_RATES 8
#define TAS_MODEL_LENGTH 32

typedef unsigned long TASNode;

typedef enum {
    kTASStatusOK = 0,
    kTASStatusNotMatched,
    kTASStatusMissing,
    kTASStatusMalformed,
    kTASStatusUnresolved,
    kTASStatusAmbiguous,
    kTASStatusConflict,
    kTASStatusOverflow,
    kTASStatusUnsupported
} TASStatus;

typedef enum {
    kTASCodecTAS3001C = 1,
    kTASCodecTAS3004 = 2
} TASCodecKind;

typedef enum {
    kTASRouteHeadphone = 0,
    kTASRouteSpeaker = 1,
    kTASRouteLineOut = 2,
    kTASRouteCount = 3
} TASRouteKind;

enum {
    kTASQuirkNone = 0,
    kTASQuirkANDedReset = 1
};

typedef struct {
    unsigned long address;
    unsigned long length;
} TASRange;

typedef struct {
    unsigned long address;
    unsigned long mask;
    int activeHigh;
    int hasIRQ;
    unsigned long irq;
} TASGPIODescriptor;

typedef struct {
    int present;
    TASGPIODescriptor mute;
    TASGPIODescriptor detect;
} TASRouteDescriptor;

typedef struct {
    TASCodecKind codecKind;
    TASRange i2s;
    TASRange outputDBDMA;
    TASRange inputDBDMA;
    unsigned long outputIRQ;
    unsigned long inputIRQ;
    unsigned long i2cAddress;
    unsigned long i2cPort;
    TASRouteDescriptor routes[kTASRouteCount];
    unsigned long rates[TAS_MAX_RATES];
    unsigned long rateCount;
    char model[TAS_MODEL_LENGTH];
    unsigned long layoutID;
    unsigned long quirks;
} TASMachineConfig;

typedef struct {
    void *context;
    int (*getProperty)(void *, TASNode, const char *,
        const unsigned char **, unsigned long *);
    int (*findNode)(void *, const char *, TASNode *);
    unsigned long (*resolvePhandle)(void *, unsigned long, TASNode *);
    int (*getParent)(void *, TASNode, TASNode *);
} TASPropertyReader;

TASStatus TASParseMachineConfig(const TASPropertyReader *reader,
    TASMachineConfig *configuration);

#endif
