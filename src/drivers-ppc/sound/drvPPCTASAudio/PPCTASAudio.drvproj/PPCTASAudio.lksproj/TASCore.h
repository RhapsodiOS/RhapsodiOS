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
    kTASStatusUnsupported,
    kTASStatusTimeout
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
    /* A non-path query uses *node as a cursor; zero starts iteration. */
    int (*findNode)(void *, const char *, TASNode *);
    /* Optional accelerators; the parser works when both are null. */
    unsigned long (*findNodes)(void *, const char *, TASNode *,
        unsigned long);
    unsigned long (*findPropertyNodes)(void *, const char *, const char *,
        TASNode *, unsigned long);
    unsigned long (*resolvePhandle)(void *, unsigned long, TASNode *);
    int (*getParent)(void *, TASNode, TASNode *);
} TASPropertyReader;

typedef struct {
    unsigned long rate;
    unsigned long sourceHz;
    unsigned long mclkDivisor;
    unsigned long sclkDivisor;
    unsigned long frameRatio;
    unsigned long dataWord;
    unsigned long codecSlotBits;
    unsigned long pcmBits;
    unsigned long channels;
} TASI2SClock;

typedef enum {
    kTASStreamOutput = 0,
    kTASStreamInput = 1
} TASStreamDirection;

enum {
    kTASStreamMaskOutput = 1,
    kTASStreamMaskInput = 2
};

typedef struct {
    unsigned long activeRate;
    unsigned long referenceCount;
    unsigned long activeMask;
    unsigned long quiescedMask;
    unsigned long generation;
    int outputsMuted;
} TASSharedClock;

typedef struct {
    TASI2SClock clock;
    unsigned long generation;
    unsigned long activeRate;
    unsigned long activeMask;
    int noOp;
} TASI2STransition;

typedef struct {
    TASI2STransition transition;
    int observedStopped;
} TASI2SStoppedToken;

typedef enum {
    kTASI2SRequestClockStop = 0,
    kTASI2SAwaitClockStopped,
    kTASI2SSetCellClockHeld,
    kTASI2SConfigureFormat,
    kTASI2SWriteDataWord,
    kTASI2SBarrier,
    kTASI2SSetCellRunning
} TASI2SPlanOperation;

typedef struct {
    TASI2SPlanOperation operation;
    unsigned long value;
    unsigned long sourceHz;
    unsigned long mclkDivisor;
    unsigned long sclkDivisor;
    unsigned long frameRatio;
    unsigned long codecSlotBits;
    unsigned long pcmBits;
    unsigned long channels;
} TASI2SPlanStep;

#define TAS_I2S_PLAN_MAX_STEPS 7

typedef struct {
    TASI2SPlanStep steps[TAS_I2S_PLAN_MAX_STEPS];
    unsigned long count;
} TASI2SRegisterPlan;

enum {
    kTASAudioRouteSpeaker = 1,
    kTASAudioRouteHeadphone = 2,
    kTASAudioRouteLineOut = 4
};

typedef enum {
    kTASPowerReady = 0,
    kTASPowerStandby,
    kTASPowerSuspended,
    kTASPowerOff,
    kTASPowerWaking,
    kTASPowerFault
} TASPowerState;

typedef struct {
    unsigned long rate;
    unsigned long leftVolume;
    unsigned long rightVolume;
    unsigned long inputGain;
    unsigned long inputSource;
    int userMuted;
} TASAudioDesiredControls;

typedef enum {
    kTASAudioBlockStarts = 0,
    kTASAudioMuteSpeaker,
    kTASAudioMuteHeadphone,
    kTASAudioMuteLineOut,
    kTASAudioCodecDigitalMute,
    kTASAudioAssertAndedReset,
    kTASAudioReleaseAndedReset,
    kTASAudioSetOutputMux,
    kTASAudioSetCodecRoute,
    kTASAudioUnmuteSpeaker,
    kTASAudioUnmuteHeadphone,
    kTASAudioUnmuteLineOut,
    kTASAudioScheduleDebounce,
    kTASAudioSampleDetects,
    kTASAudioStopOutputDMA,
    kTASAudioResetOutputDMA,
    kTASAudioStopInputDMA,
    kTASAudioResetInputDMA,
    kTASAudioCodecAnalogLowPower,
    kTASAudioCodecMuteLowPower,
    kTASAudioDisableDetectIRQs,
    kTASAudioAssertReset,
    kTASAudioSetResetAmpConstituent,
    kTASAudioSetResetHeadphoneConstituent,
    kTASAudioGateI2SCell,
    kTASAudioEnableI2SCellClock,
    kTASAudioReleaseReset,
    kTASAudioApplyI2SRate,
    kTASAudioCodecReset,
    kTASAudioCodecRestore,
    kTASAudioRebuildOutputDMA,
    kTASAudioRebuildInputDMA,
    kTASAudioEnableDetectIRQs,
    kTASAudioRestoreVolume,
    kTASAudioRestoreInputSource,
    kTASAudioRestoreInputGain
} TASAudioActionOperation;

typedef struct {
    TASAudioActionOperation operation;
    unsigned long value;
    unsigned long value2;
    unsigned long deadline;
} TASAudioAction;

#define TAS_AUDIO_ACTION_MAX 32
#define TAS_AUDIO_DEBOUNCE_CONFIRM_MS 5UL

typedef struct {
    TASAudioAction actions[TAS_AUDIO_ACTION_MAX];
    unsigned long count;
} TASAudioActionPlan;

typedef enum {
    kTASAudioTokenNone = 0,
    kTASAudioTokenRoute,
    kTASAudioTokenPower,
    kTASAudioTokenDebounce,
    kTASAudioTokenWakeRoute,
    kTASAudioTokenRollback
} TASAudioTokenKind;

typedef struct {
    TASAudioTokenKind kind;
    unsigned long generation;
    unsigned long detectGeneration;
    unsigned long sourceDesiredDetects;
    unsigned long actionCount;
    unsigned long deadline;
    unsigned long nextAction;
    unsigned long completedCount;
    unsigned long targetRoutes;
    TASPowerState targetPower;
    TASPowerState sourcePower;
    int actionInFlight;
    int sourceStartsBlocked;
} TASAudioToken;

typedef enum {
    kTASAndedResetUnknown = 0,
    kTASAndedResetAsserted,
    kTASAndedResetReleased
} TASAndedResetState;

typedef struct {
    TASAudioDesiredControls desired;
    unsigned long availableRoutes;
    unsigned long desiredDetects;
    unsigned long currentRoutes;
    unsigned long generation;
    unsigned long detectGeneration;
    unsigned long debounceDeadline;
    unsigned long candidateDetects;
    unsigned long transitionDeadline;
    TASCodecKind codecKind;
    unsigned long quirks;
    TASPowerState powerState;
    TASAndedResetState andedResetState;
    int hardwareValid;
    int routeValid;
    int outputsMuted;
    int streamsRunning;
    int startsBlocked;
    int transitionPending;
    int debouncePending;
    int candidateValid;
    int detectBlocked;
    int transitionBlocked;
    int outputsMuteKnown;
    int dmaStoppedKnown;
    int rollbackPending;
} TASAudioState;

TASStatus TASParseMachineConfig(const TASPropertyReader *reader,
    TASMachineConfig *configuration);
TASStatus TASSelectI2SClock(const TASMachineConfig *configuration,
    unsigned long rate, TASI2SClock *clock);
void TASSharedClockInit(TASSharedClock *state);
TASStatus TASAcquireI2SStream(const TASMachineConfig *configuration,
    TASSharedClock *state, TASStreamDirection direction, unsigned long rate,
    TASI2SClock *clock);
TASStatus TASReleaseI2SStream(TASSharedClock *state,
    TASStreamDirection direction);
TASStatus TASSetI2SStreamQuiesced(TASSharedClock *state,
    TASStreamDirection direction, int quiesced);
TASStatus TASSetI2SOutputsMuted(TASSharedClock *state, int muted);
TASStatus TASPrepareI2STransition(const TASMachineConfig *configuration,
    const TASSharedClock *state, unsigned long rate,
    TASI2STransition *transition);
TASStatus TASBuildI2SStopPlan(const TASSharedClock *state,
    const TASI2STransition *transition, unsigned long stopDeadline,
    TASI2SRegisterPlan *plan);
TASStatus TASObserveI2SClockStopped(const TASSharedClock *state,
    const TASI2STransition *transition, int clocksStopped,
    TASI2SStoppedToken *stopped);
TASStatus TASBuildI2SFormatPlan(const TASSharedClock *state,
    const TASI2SStoppedToken *stopped, TASI2SRegisterPlan *plan);
TASStatus TASCommitI2STransition(TASSharedClock *state,
    TASI2SStoppedToken *stopped);
TASStatus TASAudioStateInit(TASAudioState *, unsigned long, TASCodecKind,
    unsigned long, const TASAudioDesiredControls *);
TASStatus TASAudioSetDesiredControls(TASAudioState *,
    const TASAudioDesiredControls *);
TASStatus TASAudioPrepareRoute(TASAudioState *, unsigned long,
    TASAudioActionPlan *, TASAudioToken *);
TASStatus TASAudioRecordDetectISR(TASAudioState *, unsigned long,
    unsigned long *);
TASStatus TASAudioBuildDebounceSchedule(TASAudioState *, unsigned long,
    unsigned long, TASAudioActionPlan *);
TASStatus TASAudioPrepareDebounceSample(TASAudioState *, unsigned long,
    unsigned long, TASAudioActionPlan *, TASAudioToken *);
TASStatus TASAudioApplyDetectSample(TASAudioState *, const TASAudioToken *,
    unsigned long, unsigned long, TASAudioActionPlan *, TASAudioToken *);
TASStatus TASAudioPreparePower(TASAudioState *, TASPowerState,
    unsigned long, TASAudioActionPlan *, TASAudioToken *);
TASStatus TASAudioAuthorizeAction(const TASAudioState *, TASAudioToken *,
    unsigned long);
TASStatus TASAudioCompleteAction(const TASAudioState *, TASAudioToken *,
    unsigned long);
TASStatus TASAudioCommitTransition(TASAudioState *, TASAudioToken *);
TASStatus TASAudioCancelTransition(TASAudioState *, TASAudioToken *);
TASStatus TASAudioFailTransition(TASAudioState *, TASAudioToken *,
    unsigned long, TASAudioActionPlan *, TASAudioToken *);
TASStatus TASAudioPrepareRollback(TASAudioState *, unsigned long,
    TASAudioActionPlan *, TASAudioToken *);
TASStatus TASAudioCommitRollback(TASAudioState *, TASAudioToken *);
TASStatus TASAudioAbortRollback(TASAudioState *, TASAudioToken *);

#endif
