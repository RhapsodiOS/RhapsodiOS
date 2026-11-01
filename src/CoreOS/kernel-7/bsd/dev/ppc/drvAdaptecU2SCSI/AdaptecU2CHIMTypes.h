#ifndef _ADAPTECU2_CHIM_TYPES_H_
#define _ADAPTECU2_CHIM_TYPES_H_

/* The reference's configuration encoding supplies every member and its type. */
typedef struct {
    unsigned int versionNumber;
    unsigned int maxInternalIOBlocks;
    unsigned int maxTargets;
    unsigned int maxSGDescriptors;
    unsigned int maxTransferSize;
    unsigned int memoryMapped;
    unsigned int targetNumNexusTaskSetHandles;
    unsigned int targetNumNodeTaskSetHandles;
    int initiatorMode;
    int targetMode;
    unsigned int iobReserveSize;
    unsigned int stateSize;
    unsigned int maxIOHandles;
    int virtualDataAccess;
    int needPhysicalAddr;
    int busMaster;
    unsigned int allocBusAddressSize;
} AdaptecU2Configuration;

/* Six descriptors occupy each 0x48-byte memory table. Byte 2's meaning
 * is not established; its storage is preserved without a semantic name. */
typedef struct {
    unsigned char category;
    unsigned char alignmentMask;
    unsigned char byte02;
    unsigned char granularity;
    unsigned short size;
    unsigned short minimumSize;
    unsigned char *address;
} AdaptecU2MemoryDescriptor;

typedef struct {
    unsigned int type;
    AdaptecU2MemoryDescriptor memoryTables[5][6];
    AdaptecU2Configuration configuration;
} AdaptecU2InitializationTSCB;

typedef struct AdaptecU2AdapterTSCB AdaptecU2AdapterTSCB;
typedef struct AdaptecU2TargetTSCB AdaptecU2TargetTSCB;
typedef struct AdaptecU2IOB AdaptecU2IOB;
typedef struct AdaptecU2HIOB AdaptecU2HIOB;
typedef struct AdaptecU2HHCB AdaptecU2HHCB;
typedef struct AdaptecU2SCBDescriptor AdaptecU2SCBDescriptor;
typedef struct AdaptecU2ResourceControl AdaptecU2ResourceControl;
typedef struct AdaptecU2UnitControl AdaptecU2UnitControl;
typedef struct AdaptecU2HWInformation AdaptecU2HWInformation;
typedef struct AdaptecU2DeviceTable AdaptecU2DeviceTable;

struct AdaptecU2SCBDescriptor {
    unsigned char number;
    unsigned char reserved01[3];
    unsigned int busAddress;
    unsigned int size;
    unsigned char *virtualAddress;
    AdaptecU2SCBDescriptor *next;
};

struct AdaptecU2ResourceControl {
    AdaptecU2HIOB *head;
    AdaptecU2HIOB *tail;
    unsigned int nonTaggedLimit;
    unsigned int taggedLimit;
    unsigned int activeCount;
    unsigned int savedNonTaggedLimit;
    unsigned int savedTaggedLimit;
    unsigned int savedActiveCount;
    unsigned int resetCount;
    unsigned int abortSetCount;
    unsigned int freezeMask;
    unsigned int word2c;
    AdaptecU2HIOB *savedTail;
    AdaptecU2HIOB *frozenHead;
    AdaptecU2HIOB *frozenTail;
    unsigned int recoveryCount;
    unsigned int queuedCount;
};

/* The accessed unit prefix occupies16 bytes inside target storage. */
struct AdaptecU2UnitControl {
    AdaptecU2HHCB *hhcb;
    unsigned char target;
    unsigned char lun;
    unsigned char reserved06[2];
    AdaptecU2DeviceTable *device;
    AdaptecU2ResourceControl *resource;
};

/* FreeUnitHandle's callers pass either HHCB or UnitControl pointers. */
typedef void *AdaptecU2UnitHandleArgument;

typedef struct {
    void (*loadScsiRate)(AdaptecU2HHCB *, unsigned short);
    void (*resetDFifo)(AdaptecU2HHCB *);
    void (*enableIOErr)(AdaptecU2HHCB *);
    unsigned char (*getWideScsiOffset)(AdaptecU2HIOB *);
    unsigned char (*getNarrowScsiOffset)(AdaptecU2HIOB *);
    unsigned char (*getXferPeriod)(AdaptecU2HHCB *, AdaptecU2HIOB *);
    unsigned short (*calcScsiRate)(AdaptecU2HHCB *, unsigned char, unsigned char);
    void (*clearScsiOffset)(AdaptecU2HIOB *);
    unsigned int (*wasSyncXfer)(unsigned char);
    void (*processAutoTerm)(AdaptecU2HHCB *);
    void (*updateExtTerm)(AdaptecU2HHCB *);
    unsigned int (*getScbRamCtrls)(AdaptecU2HHCB *);
    void (*putScbRamCtrls)(AdaptecU2HHCB *, unsigned int);
    unsigned char (*setDataFifoThrshDefault)(AdaptecU2HHCB *);
    unsigned char (*readDataFifoThrsh)(AdaptecU2HHCB *);
    void (*updateDataFifoThrsh)(AdaptecU2HHCB *);
    unsigned char (*getCacheThEn)(AdaptecU2HHCB *);
    void (*updateCacheThEn)(AdaptecU2HHCB *);
    void (*getProfileParameters)(AdaptecU2HWInformation *, AdaptecU2HHCB *);
    void (*putProfileParameters)(const AdaptecU2HWInformation *, AdaptecU2HHCB *);
    void (*checkExtArbAckEnBit)(AdaptecU2HHCB *);
    unsigned char (*getQNewTail)(AdaptecU2HHCB *);
    void (*waitForBusStable)(AdaptecU2HHCB *);
    void (*seqStretchWorkaround)(AdaptecU2HHCB *);
    void (*ignoreWideResCalc)(AdaptecU2HHCB *, AdaptecU2HIOB *, unsigned char);
    unsigned int ramAvailableMask;
    unsigned int ramDisableMask;
    unsigned int word6c;
    unsigned char byte70;
    unsigned char byte71;
    unsigned char defaultCacheThresholdEnable;
    unsigned char configurationRegister;
    unsigned short periodLimit;
    unsigned short delayCount;
} AdaptecU2HardwareDescriptor;

typedef struct {
    unsigned int busAddress;
    unsigned int size;
    unsigned char *virtualAddress;
} AdaptecU2BufferDescriptor;
typedef struct AdaptecU2HIMFunctions AdaptecU2HIMFunctions;
typedef struct AdaptecU2OSMFunctions AdaptecU2OSMFunctions;
typedef struct AdaptecU2OSMContext_ *AdaptecU2OSMContext;

typedef struct AdaptecU2IOHandle {
    volatile unsigned char *base;
    unsigned int accessMode;
    unsigned int length;
    unsigned int offset;
    unsigned int mapped;
    unsigned char *mappingBase;
    struct AdaptecU2IOHandle *next;
    struct AdaptecU2IOHandle *prev;
} AdaptecU2IOHandle;

/* The union's four words are passed in r6..r9 by CreateAdapterTSCB's
 * reference caller. The metadata does not preserve its member names. */
typedef union {
    unsigned int words[4];
} AdaptecU2PciLocation;

/* Named fields and signedness come from the reference Objective-C encoding.
 * The final union has no encoded members; its full storage is preserved. */
typedef struct {
    unsigned int AP_Version;
    unsigned int AP_Transport;
    unsigned char AP_WorldWideID[32];
    unsigned int AP_WWIDLength;
    unsigned int AP_NumBuses;
    int AP_VirtualDataAccess;
    int AP_NeedPhysicalAddr;
    int AP_BusMaster;
    unsigned int AP_AlignmentMask;
    unsigned int AP_AddressableRange;
    unsigned int AP_GroupNum;
    unsigned int AP_AutoConfigTimeout;
    unsigned int AP_MaxIOHandles;
    int AP_TargetMode;
    int AP_InitiatorMode;
    int AP_CleanSG;
    int AP_Graphing;
    int AP_CannotCross4G;
    int AP_BiosActive;
    int AP_CacheLineStreaming;
    unsigned int AP_ExtendedTrans;
    unsigned int AP_MemoryMapped;
    unsigned int AP_MaxTargets;
    unsigned int AP_MaxInternalIOBlocks;
    unsigned int AP_MaxSGDescriptors;
    unsigned int AP_MaxTransferSize;
    unsigned int AP_StateSize;
    unsigned int AP_IOBReserveSize;
    int AP_FIFOSeparateRWThreshold;
    int AP_FIFOSeparateRWThresholdEnable;
    unsigned int AP_FIFOWriteThreshold;
    unsigned int AP_FIFOReadThreshold;
    unsigned int AP_FIFOThreshold;
    unsigned int AP_ResetDelay;
    unsigned int AP_HIMVersion;
    unsigned int AP_HardwareVersion;
    unsigned int AP_HardwareVariant;
    unsigned int AP_LowestScanTarget;
    unsigned int AP_AllocBusAddressSize;
    unsigned int AP_indexWithinGroup;
    unsigned int AP_TargetNumNexusTaskSetHandles;
    unsigned int AP_TargetNumNodeTaskSetHandles;
    int AP_TargetDisconnectAllowed;
    int AP_TargetTagEnable;
    int AP_OutOfOrderTransfers;
    unsigned int AP_NexusHandleThreshold;
    unsigned int AP_EC_IOBThreshold;
    unsigned int AP_TargetAvailableEC_IOBCount;
    unsigned int AP_TargetAvailableNexusCount;
    struct AP_SCSI_TARGET_OPT_TASKMANAGEMENT_ {
        int AP_SCSITargetAbortTask;
        int AP_SCSITargetClearTaskSet;
        int AP_SCSITargetTerminateTask;
        int AP_SCSI3TargetClearACA;
        int AP_SCSI3TargetLogicalUnitReset;
    } AP_SCSITargetOptTmFunctions;
    union {
        unsigned int words[55];
        unsigned char bytes[220];
    } himu;
} AdaptecU2AdapterProfile;

/* The target-profile copy is 124 bytes. Its original member names are not
 * encoded; the profile operations access these 31 four-byte positions. */
typedef struct {
    unsigned int words[31];
} AdaptecU2TargetProfile;

/* Four 296-byte mode descriptors; fields before the callback region are
 * sequencer constants/register selectors, not callback addresses. */
typedef struct {
    unsigned int word00;
    unsigned int word04;
    unsigned int word08;
    unsigned int word0c;
    unsigned int word10;
    unsigned int word14;
    unsigned int word18;
    unsigned int word1c;
    unsigned int word20;
    unsigned int word24;
    unsigned int word28;
    unsigned int word2c;
    unsigned int word30;
    unsigned int word34;
    unsigned char registers[28];
    int (*setupSequencer)(AdaptecU2HHCB *hhcb);
    void (*resetSoftware)(AdaptecU2HHCB *hhcb);
    void (*deliverScb)(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);
    void (*patchXferOpt)(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);
    void (*qHeadBDR)(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);
    unsigned char (*retrieveScb)(AdaptecU2HHCB *hhcb);
    unsigned char (*qoutcnt)(const AdaptecU2HHCB *hhcb);
    void (*targetClearBusy)(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);
    void (*requestSense)(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);
    void (*resetBTA)(AdaptecU2HHCB *hhcb);
    void (*getConfig)(AdaptecU2HHCB *hhcb);
    unsigned int (*configureScbRam)(AdaptecU2HHCB *hhcb);
    void (*setupAssignScbBuffer)(AdaptecU2HHCB *hhcb);
    unsigned int reserved88;
    void (*chkCondXferAssign)(AdaptecU2HHCB *hhcb, unsigned char target, unsigned short option);
    void (*xferOptAssign)(AdaptecU2HHCB *hhcb, unsigned char target, unsigned short option);
    void (*commonXferAssign)(AdaptecU2HHCB *hhcb, unsigned char target, unsigned short option);
    void (*updateXferOptionHostMem)(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, unsigned short option);
    unsigned short (*getOption)(AdaptecU2HHCB *hhcb, unsigned char target);
    unsigned char (*getFast20Reg)(AdaptecU2HHCB *hhcb, unsigned char target);
    void (*clearFast20Reg)(AdaptecU2HHCB *hhcb, unsigned char target);
    void (*logFast20Map)(AdaptecU2HHCB *hhcb, unsigned char target, unsigned char period);
    void (*updateFast20HostMem)(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, unsigned char enabled);
    void (*updateFast20HW)(AdaptecU2HHCB *hhcb, unsigned char enabled);
    void (*clearAllFast20Reg)(AdaptecU2HHCB *hhcb);
    void (*modifyDataPtr)(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);
    void (*activeAbort)(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);
    void (*abortHIOB)(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, unsigned char status);
    unsigned char (*searchSeqDoneQ)(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, unsigned char terminate);
    unsigned char (*searchDoneQ)(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);
    unsigned char (*searchNewQ)(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, unsigned char status);
    unsigned char (*searchExeQ)(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, unsigned char status, unsigned char terminate);
    void (*updateAbortBitHostMem)(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);
    unsigned char (*obtainNextScbNum)(AdaptecU2HHCB *hhcb, const AdaptecU2HIOB *hiob);
    void (*updateNextScbNum)(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, unsigned char number);
    unsigned int (*obtainNextScbAddress)(AdaptecU2HHCB *hhcb, const AdaptecU2HIOB *hiob);
    void (*updateNextScbAddress)(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob, unsigned int busAddress);
    void (*resetCCCtl)(AdaptecU2HHCB *hhcb);
    void (*initCCHHAddr)(AdaptecU2HHCB *hhcb);
    void (*removeActiveAbort)(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);
    void (*stackBugFix)(AdaptecU2HHCB *hhcb);
    void (*setupBDR)(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);
    unsigned int (*residueCalc)(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);
    void (*setBreakPoint)(AdaptecU2HHCB *hhcb, unsigned char mask);
    void (*clearBreakPoint)(AdaptecU2HHCB *hhcb, unsigned char mask);
    void (*updateSGLength)(AdaptecU2HHCB *hhcb, unsigned int length);
    void (*updateSGAddress)(AdaptecU2HHCB *hhcb, unsigned int busAddress);
    void (*freezeHWQueue)(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);
    unsigned int reserved114;
    unsigned char (*getScb)(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);
    void (*returnScb)(AdaptecU2HHCB *hhcb, AdaptecU2HIOB *hiob);
    AdaptecU2HIOB * (*hostQueueRemove)(AdaptecU2HHCB *hhcb,                                     unsigned char unusedScbNumber);
    void (*removeScbs)(AdaptecU2HHCB *hhcb);
} AdaptecU2FirmwareDescriptor;

/* Native control records. Unknown storage has offset names; bit masks are
 * used explicitly, so C implementation-defined bitfield allocation is avoided. */
struct AdaptecU2DeviceTable {
    unsigned short flags;
    unsigned short option;
    unsigned char rate;
    unsigned char period;
    unsigned char offset;
    unsigned char byte07;
    unsigned char byte08;
    unsigned char byte09;
};

struct AdaptecU2HHCB {
    unsigned short deviceID;
    unsigned char bytes02[5];
    unsigned char numberScbs;
    AdaptecU2IOHandle *ioHandle;
    unsigned int flags;
    unsigned char configurationRegister;
    unsigned char fifoThreshold;
    unsigned char firmwareMode;
    unsigned char hardwareMode;
    unsigned char bytes14[4];
    unsigned char nonTaggedLimit;
    unsigned char taggedLimit;
    unsigned char bytes1a[2];
    unsigned char maxDevices;
    unsigned char byte1d;
    unsigned char hostID;
    unsigned char byte1f;
    AdaptecU2DeviceTable devices[16];
    unsigned int wordc0;
    unsigned char *qout;
    unsigned int scbBusAddress;
    unsigned int scbBufferSize;
    unsigned char *scbBuffers;
    unsigned int hardwareFlags;
    unsigned char qnewHead;
    unsigned char qdoneElement;
    unsigned char qdonePass;
    unsigned char bytedb;
    unsigned int worddc;
    unsigned int worde0;
    unsigned int worde4;
    unsigned int worde8;
    unsigned int wordec;
    const AdaptecU2FirmwareDescriptor *firmware;
    const AdaptecU2HardwareDescriptor *hardware;
    AdaptecU2ResourceControl resources[16];
    AdaptecU2HIOB **activeHiobs;
    AdaptecU2SCBDescriptor *scbDescriptors;
    AdaptecU2HIOB **doneHiobs;
    unsigned char doneHead;
    unsigned char doneTail;
    unsigned char bytes546[2];
    unsigned char freeScbs;
    unsigned char bytes549[3];
    AdaptecU2SCBDescriptor *freeHead;
    AdaptecU2SCBDescriptor *freeTail;
    AdaptecU2HIOB *hostHead;
    AdaptecU2HIOB *hostTail;
    AdaptecU2OSMContext osmContext;
    unsigned int idConfiguration;
};

struct AdaptecU2TargetTSCB {
    unsigned int type;
    AdaptecU2AdapterTSCB *adapter;
    unsigned int target;
    unsigned int lun;
    unsigned int flags;
    AdaptecU2UnitControl unit;
    unsigned char reserved24[4];
};

/* Function selects the pointer interpretation; no pointer is widened to a
 * host integer. 0xffffffff is the reference's empty/sentinel pointer. */
struct AdaptecU2HIOB {
    union {
        AdaptecU2UnitControl *unit;
        AdaptecU2HHCB *hhcb;
        AdaptecU2HIOB *related;
    } context;
    unsigned char function;
    unsigned char status;
    unsigned char hostStatus;
    unsigned char targetStatus;
    union {
        unsigned int flags;
        struct {
            unsigned char byte08;
            unsigned char scbNumber;
            unsigned char byte0a;
            unsigned char byte0b;
        } bytes;
    } control;
    union {
        unsigned char *sense;
        AdaptecU2HIOB *related;
    } auxiliary;
    unsigned char senseLength;
    unsigned char residualSense;
    unsigned char bytes12[2];
    unsigned int residualLength;
    AdaptecU2SCBDescriptor *scb;
    AdaptecU2HIOB *next;
    unsigned char managerStatus;
    unsigned char negotiationState;
    unsigned char acknowledgeLastMessage;
    unsigned char message[5];
    unsigned char bytes28[8];
    unsigned int priority;
    AdaptecU2IOB *iob;
};

typedef struct {
    unsigned char scsiOption[4];
    unsigned int word04;
    unsigned int word08;
    unsigned int word0c;
    unsigned char target;
    unsigned char bus;
    unsigned char lun;
    unsigned char byte13;
} AdaptecU2TransportSpecific;

struct AdaptecU2IOB {
    AdaptecU2BufferDescriptor reserve;
    unsigned int function;
    unsigned int priority;
    unsigned int flags;
    unsigned int word18;
    AdaptecU2TransportSpecific *transportSpecific;
    struct AdaptecU2Command *command;
    AdaptecU2IOB *related;
    union {
        AdaptecU2TargetTSCB *target;
        AdaptecU2AdapterTSCB *adapter;
    } taskSet;
    unsigned int status;
    unsigned int word30;
    unsigned int (*post)(AdaptecU2IOB *);
    unsigned char *cdb;
    unsigned int cdbLength;
    unsigned int word40;
    AdaptecU2BufferDescriptor data;
    unsigned int transferLength;
    unsigned int word54;
    unsigned char *sense;
    unsigned int senseLength;
    unsigned int residualLength;
    unsigned int residualSense;
    unsigned int taskAttribute;
};

typedef struct {
    unsigned char cdb[32];
    AdaptecU2HIOB hiob;
} AdaptecU2IOBReserve;

/* DMA records are byte arrays: every multibyte field is explicitly little
 * endian. Native unsigned fields would silently reverse them on PPC. */
typedef struct { unsigned char address[4]; unsigned char lengthAndLast[4]; }
    AdaptecU2SGElement;
typedef struct { unsigned char bytes[64]; } AdaptecU2Standard64SCB;
typedef struct { unsigned char bytes[32]; } AdaptecU2Swapping32SCB;
typedef struct { unsigned char bytes[64]; } AdaptecU2StandardAdvSCB;
typedef struct { unsigned char bytes[64]; } AdaptecU2SwappingAdvSCB;

struct AdaptecU2HWInformation {
    unsigned char identification[32];
    unsigned char hostID;
    unsigned char fifoThreshold;
    unsigned char readThreshold;
    unsigned char writeThreshold;
    unsigned int flags;
    struct {
        unsigned int queueDepth;
        unsigned short option;
        unsigned short flags;
        unsigned short maximumSpeed;
        unsigned short currentSpeed;
        unsigned short requestedSpeed;
        unsigned char maximumOffset;
        unsigned char currentOffset;
        unsigned char requestedOffset;
        unsigned char maximumWidth;
        unsigned char currentWidth;
        unsigned char requestedWidth;
        unsigned char changed;
        unsigned char reserved15[3];
    } targets[16];
    unsigned short minimumSpeed;
    unsigned char reserved1aa[2];
};

#endif
