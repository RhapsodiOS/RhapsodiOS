/* Reconstructed i386 BusLogic FlashPoint manager ABI. */
#ifndef _FLASHPOINT_H
#define _FLASHPOINT_H

#include <sys/types.h>

#ifndef BLFP_FIXED_WIDTH_TYPES
#define BLFP_FIXED_WIDTH_TYPES 1
typedef unsigned char u8;
typedef unsigned short u16;
typedef unsigned int u32;
#endif

struct sccb;
typedef int (*CALL_BK_FN)(struct sccb *);
struct sccb_mgr_info;

#define BLFP_CARD_COUNT 4
#define MAX_SCSI_TAR 16
#define MAX_LUN 32
#define SG_ELEMENT_COUNT 17
#define SG_ELEMENT_SIZE 8
#define SCCB_SIZE 260
#define SCCB_MGR_INFO_SIZE 64
#define SCCB_CARD_SIZE 20
#define SCCB_TARGET_SIZE 212

struct sccb_sg_entry {
    u32 length;
    u32 address;
};

struct sccb_queue_links {
    struct sccb *next;
    struct sccb *prev;
};

/* Exactly 260 bytes in the 32-bit reference ABI. */
struct sccb {
    u8 OperationCode;                 /* 0 */
    u8 ControlByte;                   /* 1 */
    u8 CdbLength;                     /* 2 */
    u8 RequestSenseLength;            /* 3 */
    u32 DataLength;                   /* 4 */
    void *DataPointer;                /* 8 */
    u8 CcbRes[2];                     /* 12 */
    u8 HostStatus;                    /* 14 */
    u8 TargetStatus;                  /* 15 */
    u8 TargID;                        /* 16 */
    u8 Lun;                           /* 17 */
    u8 Cdb[12];                       /* 18 */
    u8 CcbRes1;                       /* 30 */
    u8 Reserved1;                     /* 31 */
    u32 Reserved2;                    /* 32 */
    u32 SensePointer;                 /* 36 */
    CALL_BK_FN SccbCallback;          /* 40 */
    u32 SccbIOPort;                   /* 44 */
    u8 SccbStatus;                    /* 48 */
    u8 SCCBRes2;                      /* 49 */
    u16 SccbOSFlags;                  /* 50 */
    u32 Sccb_XferCnt;                 /* 52 */
    u32 Sccb_ATC;                     /* 56 */
    u32 SccbVirtDataPtr;              /* 60 */
    u32 Sccb_res1;                    /* 64 */
    u16 Sccb_MGRFlags;                /* 68 */
    u16 Sccb_sgseg;                   /* 70 */
    u8 Sccb_scsimsg;                  /* 72 */
    u8 Sccb_tag;                      /* 73 */
    u8 Sccb_scsistat;                 /* 74: protocol state */
    u8 Sccb_idmsg;                    /* 75 */
    struct sccb *Sccb_forwardlink;    /* 76 */
    struct sccb *Sccb_backlink;       /* 80 */
    u32 Sccb_savedATC;                /* 84 */
    u8 Save_Cdb[6];                   /* 88 */
    u8 Save_CdbLen;                   /* 94 */
    u8 Sccb_XferState;                /* 95 */
    u32 Sccb_SGoffset;                /* 96 */
    struct sccb_sg_entry SGEntries[SG_ELEMENT_COUNT]; /* 100..235 */
    void *CommandRecord;              /* 236 */
    u32 DriverReserved240;            /* 240 */
    u8 TimeoutScheduled;              /* 244 */
    u8 DriverTail[3];                  /* 245..247 */
    void *Controller;                 /* 248 */
    struct sccb_queue_links QueueLinks; /* 252..259 */
};

/* Manager-info access beyond the verified prefix remains an opaque byte area. */
struct sccb_mgr_info {
    u32 ioBase;                       /* 0 */
    u8 present;                       /* 4 */
    u8 interruptVector;               /* 5 */
    u8 adapterId;                     /* 6 */
    u8 lun;                            /* 7 */
    u16 firmwareRevision;              /* 8 */
    u16 config10;                      /* 10 */
    u16 config12;                      /* 12 */
    u16 config14;                      /* 14 */
    u8 flags;                          /* 16 */
    u8 family;                         /* 17 */
    u8 busType;                        /* 18 */
    u8 cardModel[3];                   /* 19 */
    u8 relativeCard;                   /* 22 */
    u8 reserved23[5];                  /* 23..27 */
    void *owner;                       /* 28 */
    u8 opaque32[32];                   /* 32..63 */
};

struct sccb_card {
    struct sccb *currentSCCB;          /* 0 */
    struct sccb_mgr_info *cardInfo;    /* 4 */
    u32 ioPort;                        /* 8 */
    u16 cmdCounter;                    /* 12 */
    u8 discQCount;                     /* 14: manager card index */
    u8 tagQ_Lst;                       /* 15 */
    u8 globalFlags;                    /* 16 */
    u8 ourId;                          /* 17 */
    u8 reserved18[2];                  /* 18..19 */
};

struct sccb_mgr_target {
    u8 opaque0[64];                    /* 0..63 */
    struct sccb *disconnected[33];     /* 64..195 */
    struct sccb *selectHead;           /* 196 */
    struct sccb *selectTail;           /* 200 */
    u8 selectEligible;                 /* 204 */
    u8 selectCount;                    /* 205 */
    u8 status;                         /* 206 */
    u8 eepromValue;                    /* 207 */
    u8 syncValue;                      /* 208 */
    u8 reserved209[3];                 /* 209..211 */
};

struct sccb_scam_info {
    u8 idString[32];
    u32 state;
};

#define SCATTER_GATHER_COMMAND 0x02
#define RESIDUAL_COMMAND       0x03
#define RESIDUAL_SG_COMMAND    0x04
#define RESET_COMMAND          0x81
#define F_USE_CMD_Q            0x20
#define SCCB_DATA_XFER_OUT     0x10
#define SCCB_DATA_XFER_IN      0x08
#define SCCB_COMPLETE          0x00
#define SCCB_DATA_UNDER_RUN    0x0c
#define SCCB_SELECTION_TIMEOUT 0x11
#define SCCB_DATA_OVER_RUN     0x12
#define SCCB_PHASE_SEQUENCE_FAIL 0x14
#define SCCB_PARITY_ERR         0x34

extern struct sccb_card BL_Card[BLFP_CARD_COUNT];
extern struct sccb_mgr_target sccbMgrTbl[BLFP_CARD_COUNT][MAX_SCSI_TAR];
extern struct sccb_scam_info scamInfo[BLFP_CARD_COUNT][MAX_SCSI_TAR];
extern u8 BL_CardFlags[BLFP_CARD_COUNT * 20];

int OS_InPortByte(u16 port);
int OS_InPortWord(u16 port);
u32 OS_InPortLong(u16 port);
int OS_OutPortByte(u16 port, u8 value);
int OS_OutPortWord(u16 port, u16 value);
int OS_OutPortLong(u16 port, u32 value);
void OS_start_timer(void);
void OS_stop_timer(void);
int OS_Lock(void *lock);
int OS_UnLock(void *lock);

int queueSearchSelect(struct sccb_card *card, u8 cardIndex);
u8 queueSelectFail(struct sccb **current, u8 cardIndex);
int queueCmdComplete(struct sccb_card *card, struct sccb *sccb);
int queueDisconnect(struct sccb *sccb, u8 cardIndex);
int queueFlushSccb(u8 cardIndex, char hostStatus);
int queueAddSccb(struct sccb *sccb, u8 cardIndex);
int queueFindSccb(struct sccb *sccb, u8 cardIndex);
int utilUpdateResidual(struct sccb *sccb);
int Wait1Second(u16 basePort);
int Wait(u16 basePort, u8 ticks);
int doesCrossPage(u32 address, u32 length);
int SccbMgrTableInitAll(void);
int SccbMgrTableInitCard(struct sccb_card *card, u8 cardIndex);
int SccbMgrTableInitTarget(u8 cardIndex, u8 target);
int SccbMgr_my_int(struct sccb_card *card);
int SccbMgr_start_sccb(struct sccb_card *card, struct sccb *sccb);
int SccbMgr_abort_sccb(struct sccb_card *card, struct sccb *sccb);
int SccbMgr_isr(struct sccb_card *card);
int SccbMgr_bad_isr(u16 basePort, u8 cardIndex, struct sccb_card *card,
                    signed char interruptStatus);
int SccbMgr_sense_adapter(struct sccb_mgr_info *info);
int scsiInitSCCB(struct sccb *sccb, u8 cardIndex);
int utilEEWriteOnOff(u16 basePort, u8 mode);
int utilEEWrite(u16 basePort, u16 value, short address);
int utilEERead(u16 basePort, short address);
int utilEESendCmdAddr(u16 basePort, u8 command, u16 address);
int scsiSenseSetup(struct sccb **sccb);
int scsiSetSyncValue(u16 basePort, u8 target, u8 value,
                     struct sccb_mgr_target *targetState);
int scsiFetchMsg(u16 basePort, struct sccb *sccb);
int dataXferProcessor(u32 basePort, struct sccb_card *card);
int phaseStatus(u16 basePort);
int phaseDecode(u32 basePort, u8 cardIndex);
int phaseDataOut(u32 basePort, u8 cardIndex);
int phaseDataIn(u32 basePort, u8 cardIndex);
int phaseIllegal(u32 basePort, u8 cardIndex);
int phaseCommand(u32 basePort, u8 cardIndex);
int phaseMsgOut(u32 basePort, u8 cardIndex);
int phaseMsgIn(u32 basePort, u8 cardIndex);
int phaseChkFifo(u32 basePort, u8 cardIndex);
int phaseBusFree(u32 basePort, u8 cardIndex);
int autoCmdCmplt(u32 basePort, u8 cardIndex);
int phaseMsgOut(u32 basePort, u8 cardIndex);
int scsiSelect(u32 basePort, u8 cardIndex);
int scsiReselection(u16 basePort, u8 cardIndex, struct sccb_card *card);
int scsiDecodeMsg(u8 message, u32 basePort, u8 cardIndex);
int scsiHandleExtMsg(u32 basePort, u8 cardIndex, struct sccb *sccb);
int scsiChkDmaDone(u32 basePort, u8 cardIndex);
int scsiInitSyncNego(u32 basePort, u8 cardIndex);
int scsiTargSyncNego(u32 basePort, u8 cardIndex);
int scsiInitSyncRespond(u32 basePort, u8 period, u8 offset);
int scsiInitWideNego(u32 basePort, u8 cardIndex);
int scsiTargWideNego(u32 basePort, u8 cardIndex);
int scsiInitWideRespond(u32 basePort, u8 width);
int scsiXferPad(u32 basePort, u8 cardIndex);
int hostDataXferAbort(u32 basePort, u8 cardIndex, struct sccb *sccb);
int busMstrSGDataXferStart(u32 basePort, struct sccb *sccb);
int busMstrDataXferStart(u32 basePort, struct sccb *sccb);
void hostDataXferRestart(struct sccb *sccb);
int ScamWireOrData(u16 basePort, u8 mask);
int ScamWireOrSig(u16 basePort, u8 mask);
int ScamValidQ(u8 value);
int ScamWaitSelection(u16 basePort);
int ScamArbitration(u16 basePort, u8 start);
int ScamBusFree(u16 basePort);
int ScamSelect(u16 basePort);
int ScamXferCycle(u16 basePort, u8 value);
int ScamSendIsolate(u16 basePort, const u8 idString[32]);
int ScamIsolate(u16 basePort, u8 idString[32]);
int initScamInfo(u8 cardIndex, u16 basePort);
int scamMatchId(u8 cardIndex, const char *idString);
int scamSaveDeviceInfo(u8 cardIndex, u16 basePort);
int ScamAssignID(u8 cardIndex, u16 basePort);
int ScamSelLegacy(u16 basePort, u8 target);
void SccbMgr_timer_expired(void);
int ScamInit(u8 cardIndex, u8 adapterId, int reserved);
int scsiResetBus(u32 basePort, u8 cardIndex);
int BusMasterInit(u32 basePort);
int XbowInit(u32 basePort);
int autoLoadDefaultMap(u32 basePort);
int busMstrTimeOut(u32 basePort);
struct sccb_card *SccbMgr_config_adapter(struct sccb_mgr_info *info);
int SccbMgr_scsi_reset(struct sccb_card *card);

extern volatile u32 xxx_8_0;
extern volatile u32 xxx_11_0;
extern volatile u32 xxx_14_0;
extern u32 page_mask;

#endif /* _FLASHPOINT_H */
