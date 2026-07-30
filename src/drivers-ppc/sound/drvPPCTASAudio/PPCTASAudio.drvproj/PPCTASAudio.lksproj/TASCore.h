#ifndef TAS_CORE_H
#define TAS_CORE_H

#define TAS_MAX_RATES 8
#define TAS_MODEL_LENGTH 32
#define TAS_CODEC_COMPATIBLE_LENGTH 8

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
    kTASRouteLineOut = 1,
    kTASRouteCount = 2
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
    unsigned long number;
    unsigned long sense;
} TASInterrupt;

typedef struct {
    unsigned long offset;
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
    char codecCompatible[TAS_CODEC_COMPATIBLE_LENGTH];
    unsigned long i2sCell;
    TASRange i2s;
    TASRange outputDBDMA;
    TASRange inputDBDMA;
    TASInterrupt codecInterrupt;
    TASInterrupt outputInterrupt;
    TASInterrupt inputInterrupt;
    unsigned long i2cAddress;
    unsigned long i2cPort;
    TASGPIODescriptor hardwareReset;
    TASGPIODescriptor amplifierMute;
    TASGPIODescriptor inputMux;
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
    unsigned long (*findNodes)(void *, const char *, TASNode *,
        unsigned long);
    unsigned long (*findPropertyNodes)(void *, const char *, const char *,
        TASNode *, unsigned long);
    unsigned long (*resolvePhandle)(void *, unsigned long, TASNode *);
    int (*getParent)(void *, TASNode, TASNode *);
} TASPropertyReader;

TASStatus TASParseMachineConfig(const TASPropertyReader *reader,
    TASMachineConfig *configuration);

#endif
