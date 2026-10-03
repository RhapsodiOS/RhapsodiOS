/*
 * Reconstructed i386 BusLogic FlashPoint manager primitives.
 *
 * Hardware behavior and field offsets in this file follow the supplied
 * BusLogicFPSCSI_reloc disassembly.  The Linux FlashPoint source is retained
 * only as research material; it is not compiled into this reconstruction.
 */
#include "FlashPoint.h"

typedef int (*blfp_phase_handler)(u32 basePort, u8 cardIndex);
static blfp_phase_handler phaseTable[8];
static u8 first_time_2 = 1;

int phaseDataOut(u32 basePort, u8 cardIndex);
int phaseDataIn(u32 basePort, u8 cardIndex);
int phaseIllegal(u32 basePort, u8 cardIndex);
int phaseCommand(u32 basePort, u8 cardIndex);
int phaseStatus(u16 basePort);
int phaseMsgOut(u32 basePort, u8 cardIndex);
int phaseMsgIn(u32 basePort, u8 cardIndex);
int scsiTargSyncNego(u32 basePort, u8 cardIndex);
int scsiTargWideNego(u32 basePort, u8 cardIndex);
int scsiXferPad(u32 basePort, u8 cardIndex);

static int phaseStatusDispatch(u32 basePort, u8 cardIndex)
{
    (void)cardIndex;
    return phaseStatus((u16)basePort);
}

struct sccb_card BL_Card[BLFP_CARD_COUNT];
struct sccb_mgr_target sccbMgrTbl[BLFP_CARD_COUNT][MAX_SCSI_TAR];
u8 BL_CardFlags[BLFP_CARD_COUNT * 20];
struct sccb_scam_info scamInfo[BLFP_CARD_COUNT][MAX_SCSI_TAR];

volatile u32 xxx_8_0;
volatile u32 xxx_11_0;
volatile u32 xxx_14_0;

#ifndef BLFP_TEST_IO
static u8 blfp_in8(u16 port)
{
    u8 value;
    __asm__ volatile ("inb %1, %0" : "=a" (value) : "Nd" (port));
    return value;
}

static u16 blfp_in16(u16 port)
{
    u16 value;
    __asm__ volatile ("inw %1, %0" : "=a" (value) : "Nd" (port));
    return value;
}

static u32 blfp_in32(u16 port)
{
    u32 value;
    __asm__ volatile ("inl %1, %0" : "=a" (value) : "Nd" (port));
    return value;
}

static void blfp_out8(u16 port, u8 value)
{
    __asm__ volatile ("outb %0, %1" : : "a" (value), "Nd" (port));
}

static void blfp_out16(u16 port, u16 value)
{
    __asm__ volatile ("outw %0, %1" : : "a" (value), "Nd" (port));
}

static void blfp_out32(u16 port, u32 value)
{
    __asm__ volatile ("outl %0, %1" : : "a" (value), "Nd" (port));
}
#else
extern u8 blfp_test_in8(u16 port);
extern u16 blfp_test_in16(u16 port);
extern u32 blfp_test_in32(u16 port);
extern void blfp_test_out8(u16 port, u8 value);
extern void blfp_test_out16(u16 port, u16 value);
extern void blfp_test_out32(u16 port, u32 value);
#define blfp_in8 blfp_test_in8
#define blfp_in16 blfp_test_in16
#define blfp_in32 blfp_test_in32
#define blfp_out8 blfp_test_out8
#define blfp_out16 blfp_test_out16
#define blfp_out32 blfp_test_out32
#endif

static void blfp_count(volatile u32 *counter)
{
    __asm__ volatile ("lock; incl %0" : "+m" (*counter) : : "memory");
}

int OS_InPortByte(u16 port) { return (int)blfp_in8(port); }
int OS_InPortWord(u16 port) { return (int)blfp_in16(port); }
u32 OS_InPortLong(u16 port) { return blfp_in32(port); }

int OS_OutPortByte(u16 port, u8 value)
{
    blfp_out8(port, value);
    blfp_count(&xxx_8_0);
    return 0;
}

int OS_OutPortWord(u16 port, u16 value)
{
    blfp_out16(port, value);
    blfp_count(&xxx_11_0);
    return 0;
}

int OS_OutPortLong(u16 port, u32 value)
{
    blfp_out32(port, value);
    blfp_count(&xxx_14_0);
    return 0;
}

void OS_start_timer(void) { }
void OS_stop_timer(void) { }
int OS_Lock(void *lock) { (void)lock; return 0; }
int OS_UnLock(void *lock) { (void)lock; return 0; }

static struct sccb_mgr_target *blfp_target(u8 card, u8 target)
{
    return &sccbMgrTbl[card][target];
}

int queueSearchSelect(struct sccb_card *card, u8 cardIndex)
{
    u8 target = card->tagQ_Lst;
    struct sccb_mgr_target *entry;
    struct sccb *selected;

    for (;;) {
        entry = blfp_target(cardIndex, target);
        if (entry->selectCount != 0 && entry->selectEligible == 0)
            break;
        if (++target == MAX_SCSI_TAR)
            target = 0;
        if (card->tagQ_Lst == target)
            return 53 * target;
    }

    selected = entry->selectHead;
    card->currentSCCB = selected;
    entry->selectHead = selected->Sccb_forwardlink;
    if (entry->selectHead != 0) {
        --entry->selectCount;
        entry->selectHead->Sccb_backlink = 0;
    } else {
        entry->selectTail = 0;
        entry->selectCount = 0;
    }
    card->tagQ_Lst = (target + 1 == MAX_SCSI_TAR) ? 0 : (u8)(target + 1);
    card->globalFlags |= 0x40;
    return (int)(unsigned long long)entry->selectHead;
}

u8 queueSelectFail(struct sccb **current, u8 cardIndex)
{
    struct sccb *sccb = *current;
    struct sccb_mgr_target *entry;
    u8 result = cardIndex;

    if (sccb != 0) {
        entry = blfp_target(cardIndex, sccb->TargID);
        sccb->Sccb_backlink = 0;
        sccb->Sccb_forwardlink = entry->selectHead;
        if (entry->selectCount != 0)
            entry->selectHead->Sccb_backlink = sccb;
        else
            entry->selectTail = sccb;
        entry->selectHead = sccb;
        *current = 0;
        ++entry->selectCount;
        result = (u8)(unsigned long long)sccb;
    }
    return result;
}

int queueCmdComplete(struct sccb_card *card, struct sccb *sccb)
{
    u8 opcode = sccb->OperationCode;
    u8 i;
    u8 value;
    int callbackResult = 0;

    if ((sccb->Sccb_XferState & 2) == 0 && (sccb->ControlByte & 0x18) != 0) {
        if (sccb->HostStatus != 0) {
            sccb->SccbStatus = 4;
            goto complete;
        }
        if (sccb->TargetStatus != 2 &&
            (opcode == 8 || opcode == 10 || opcode == 40 || opcode == 42 ||
             opcode == 46 || opcode == 27 || (card->globalFlags & 8) != 0))
            sccb->HostStatus = 12;
    }
    if (sccb->HostStatus != 0 || sccb->TargetStatus != 0)
        sccb->SccbStatus = 4;
    else
        sccb->SccbStatus = 1;

complete:
    if ((sccb->Sccb_XferState & 8) != 0) {
        sccb->CdbLength = sccb->Save_CdbLen;
        for (i = 0; i <= 5; ++i)
            sccb->Cdb[i] = sccb->Save_Cdb[i];
    }
    if (sccb->OperationCode == RESIDUAL_COMMAND ||
        sccb->OperationCode == RESIDUAL_SG_COMMAND)
        utilUpdateResidual(sccb);

    if (card->cmdCounter-- == 1) {
        if ((card->globalFlags & 0x10) != 0) {
            OS_OutPortByte((u16)(card->ioPort + 109), 0x53);
            OS_OutPortByte((u16)(card->ioPort + 15), 1);
        }
        value = OS_InPortByte((u16)(card->ioPort + 12));
        OS_OutPortByte((u16)(card->ioPort + 12), (u8)(value & 0xfe));
    }
    callbackResult = sccb->SccbCallback(sccb);
    card->globalFlags |= 0x40;
    card->currentSCCB = 0;
    return callbackResult;
}

int queueDisconnect(struct sccb *sccb, u8 cardIndex)
{
    struct sccb_mgr_target *entry = blfp_target(cardIndex, sccb->TargID);
    entry->disconnected[sccb->Sccb_tag] = sccb;
    if (sccb->Sccb_tag != 0)
        ++((u8 *)entry)[32 + sccb->Lun];
    BL_Card[cardIndex].currentSCCB = 0;
    return 5 * cardIndex;
}

int queueFlushSccb(u8 cardIndex, char hostStatus)
{
    struct sccb *current = BL_Card[cardIndex].currentSCCB;
    struct sccb_mgr_target *entry = blfp_target(cardIndex, current->TargID);
    u8 i;
    u8 j;
    int result = 0;

    for (i = 0; i <= 32; ++i) {
        struct sccb *sccb = entry->disconnected[i];
        if (sccb != 0) {
            sccb->HostStatus = (u8)hostStatus;
            queueCmdComplete(&BL_Card[cardIndex], sccb);
            entry->disconnected[i] = 0;
        }
    }
    for (j = 0; j <= 31; ++j) {
        result = j;
        ((u8 *)entry)[32 + j] = 0;
    }
    return result;
}

int queueAddSccb(struct sccb *sccb, u8 cardIndex)
{
    struct sccb_mgr_target *entry = blfp_target(cardIndex, sccb->TargID);
    int result = (int)(unsigned long long)entry;
    if (entry->selectCount != 0)
        result = (int)(unsigned long long)entry->selectTail;
    sccb->Sccb_forwardlink = 0;
    sccb->Sccb_backlink = entry->selectTail;
    if (entry->selectCount != 0)
        entry->selectTail->Sccb_forwardlink = sccb;
    else
        entry->selectHead = sccb;
    entry->selectTail = sccb;
    ++entry->selectCount;
    return result;
}

int queueFindSccb(struct sccb *sccb, u8 cardIndex)
{
    struct sccb_mgr_target *entry = blfp_target(cardIndex, sccb->TargID);
    struct sccb *node = entry->selectHead;

    if (node == 0)
        return 0;
    while (node != sccb) {
        node = node->Sccb_forwardlink;
        if (node == 0)
            return 0;
    }
    if (entry->selectHead == node)
        entry->selectHead = node->Sccb_forwardlink;
    if (entry->selectTail == node)
        entry->selectTail = node->Sccb_backlink;
    if (node->Sccb_forwardlink != 0)
        node->Sccb_forwardlink->Sccb_backlink = node->Sccb_backlink;
    if (node->Sccb_backlink != 0)
        node->Sccb_backlink->Sccb_forwardlink = node->Sccb_forwardlink;
    --entry->selectCount;
    return 1;
}

int SccbMgr_start_sccb(struct sccb_card *card, struct sccb *sccb)
{
    u8 cardIndex = card->discQCount;
    u32 basePort = card->ioPort;
    u8 value;
    struct sccb_mgr_target *target;

    OS_Lock(card->cardInfo);
    scsiInitSCCB(sccb, cardIndex);
    if (card->cmdCounter == 0) {
        value = (u8)OS_InPortByte((u16)(basePort + 12));
        OS_OutPortByte((u16)(basePort + 12), (u8)(value | 1));
        if ((card->globalFlags & 0x10) != 0) {
            OS_OutPortByte((u16)(basePort + 109), 19);
            OS_OutPortByte((u16)(basePort + 15), 0);
        }
    }
    ++card->cmdCounter;
    if ((OS_InPortByte((u16)(basePort + 12)) & 0x10) != 0) {
        value = (u8)OS_InPortByte((u16)(basePort + 12));
        OS_OutPortByte((u16)(basePort + 12), (u8)(value | 2));
        queueAddSccb(sccb, cardIndex);
    } else if ((OS_InPortByte((u16)(basePort + 41)) & 8) != 0) {
        queueAddSccb(sccb, cardIndex);
    } else {
        value = (u8)OS_InPortByte((u16)(basePort + 41));
        OS_OutPortByte((u16)(basePort + 41), (u8)(value | 8));
        target = blfp_target(cardIndex, sccb->TargID);
        if (card->currentSCCB != 0 || target->selectCount != 0 ||
            target->selectEligible != 0) {
            queueAddSccb(sccb, cardIndex);
        } else {
            card->currentSCCB = sccb;
            OS_UnLock(card->cardInfo);
            scsiSelect(sccb->SccbIOPort, cardIndex);
            OS_Lock(card->cardInfo);
        }
        value = (u8)OS_InPortByte((u16)(basePort + 41));
        OS_OutPortByte((u16)(basePort + 41), (u8)(value & 0xf7));
    }
    return OS_UnLock(card->cardInfo);
}

int SccbMgr_abort_sccb(struct sccb_card *card, struct sccb *sccb)
{
    u32 basePort = card->ioPort;
    u8 cardIndex = card->discQCount;
    u8 value;

    OS_Lock(card->cardInfo);
    if ((OS_InPortByte((u16)(basePort + 41)) & 8) != 0) {
        OS_UnLock(card->cardInfo);
        return -1;
    }
    if (queueFindSccb(sccb, cardIndex) != 0) {
        OS_UnLock(card->cardInfo);
        if (--card->cmdCounter == 0) {
            value = (u8)OS_InPortByte((u16)(basePort + 12));
            OS_OutPortByte((u16)(basePort + 12), (u8)(value & 0xfc));
        }
        sccb->SccbStatus = 2;
        sccb->SccbCallback(sccb);
    } else {
        u8 lun;
        struct sccb_mgr_target *target;
        OS_UnLock(card->cardInfo);
        if (card->currentSCCB == sccb)
            return 0;
        target = blfp_target(cardIndex, sccb->TargID);
        for (lun = 0; lun <= 0x20; ++lun) {
            if (target->disconnected[lun] == sccb)
                return 0;
        }
        return -1;
    }
    return 0;
}

int SccbMgr_bad_isr(u16 basePort, u8 cardIndex, struct sccb_card *card,
                    signed char interruptStatus)
{
    struct sccb *sccb = card->currentSCCB;
    struct sccb_mgr_target *target = blfp_target(cardIndex, sccb->TargID);
    u8 status;

    if ((OS_InPortByte((u16)(basePort + 54)) & 0x63) != 0) {
        if ((card->globalFlags & 0x20) != 0)
            hostDataXferAbort(basePort, cardIndex, sccb);
        if ((OS_InPortByte((u16)(basePort + 45)) & 0x20) != 0) {
            status = (u8)OS_InPortByte((u16)(basePort + 45));
            OS_OutPortByte((u16)(basePort + 45), (u8)(status & 0xdf));
            OS_OutPortByte((u16)(basePort + 19), 0);
        }
        if (sccb != 0) {
            if (sccb->HostStatus == 0)
                sccb->HostStatus = 48;
            scsiXferPad(basePort, cardIndex);
            status = (u8)OS_InPortByte((u16)(basePort + 34)) & 0xc0;
            OS_OutPortByte((u16)(basePort + 34), (u8)(status | 0x28));
            OS_OutPortByte((u16)(basePort + 34), status);
            if ((OS_InPortByte((u16)(basePort + 67)) & 0x80) == 0 &&
                (OS_InPortByte((u16)(basePort + 66)) & 0x80) == 0)
                phaseDecode(basePort, cardIndex);
        }
        return 0;
    }
    if (interruptStatus >= 0) {
        if ((interruptStatus & 0x10) != 0) {
            OS_OutPortByte((u16)(basePort + 66), 0x10);
            if (sccb != 0)
                scsiXferPad(basePort, cardIndex);
        } else if ((interruptStatus & 1) != 0) {
            OS_OutPortByte((u16)(basePort + 71), 2);
            OS_OutPortByte((u16)(basePort + 71), 0);
            OS_OutPortByte((u16)(basePort + 66), 0x49);
            OS_OutPortByte((u16)(basePort + 67), 0xb0);
            sccb->HostStatus = 17;
            target->selectEligible = 0;
            if ((target->eepromValue & 3) != 0) {
                target->syncValue = 0;
                target->status &= 0x3f;
            }
            if ((signed char)target->eepromValue < 0)
                target->status &= 0xcf;
            scsiSetSyncValue(basePort, sccb->TargID, 16, target);
            queueCmdComplete(card, sccb);
        }
        return 0;
    }
    if (sccb != 0 && (card->globalFlags & 0x20) != 0)
        hostDataXferAbort(basePort, cardIndex, sccb);
    OS_OutPortByte((u16)(basePort + 71), 2);
    OS_OutPortByte((u16)(basePort + 71), 0);
    scsiResetBus(basePort, cardIndex);
    while ((OS_InPortByte((u16)(basePort + 69)) & 2) != 0)
        ;
    XbowInit(basePort);
    ScamInit(cardIndex, card->cardInfo->adapterId, 0);
    return 255;
}

int SccbMgr_isr(struct sccb_card *card)
{
    u8 cardIndex = card->discQCount;
    u32 basePort = card->ioPort;
    struct sccb *sccb;
    u8 interruptError;
    u8 interruptEnable;
    u8 status;
    signed char event;
    u8 irqStatus;

    OS_Lock(card->cardInfo);
    sccb = card->currentSCCB;
    status = (u8)OS_InPortByte((u16)(basePort + 41));
    OS_OutPortByte((u16)(basePort + 41), (u8)(status | 8));
    if ((OS_InPortByte((u16)(basePort + 55)) & 2) != 0)
        interruptError = (u8)OS_InPortByte((u16)(basePort + 54)) & 0x73;
    else
        interruptError = 0;
    OS_OutPortByte((u16)(basePort + 23), 5);
    OS_UnLock(card->cardInfo);

    status = (u8)OS_InPortByte((u16)(basePort + 66));
    irqStatus = (u8)OS_InPortByte((u16)(basePort + 64)) & status;
    interruptEnable = (u8)OS_InPortByte((u16)(basePort + 67));
    event = (signed char)((u8)OS_InPortByte((u16)(basePort + 65)) & interruptEnable);
    while (event != 0 || irqStatus != 0 || interruptError != 0) {
        if ((irqStatus & 0x95) != 0 || interruptError != 0) {
            u8 handled = (u8)SccbMgr_bad_isr((u16)basePort, cardIndex, card,
                                               (signed char)irqStatus);
            OS_OutPortByte((u16)(basePort + 66), 149);
            interruptError = 0;
            if (handled != 0) {
                OS_Lock(card->cardInfo);
                status = (u8)OS_InPortByte((u16)(basePort + 41));
                OS_OutPortByte((u16)(basePort + 41), (u8)(status & 0xf7));
                OS_UnLock(card->cardInfo);
                return handled;
            }
        } else if ((event & 8) != 0) {
            if ((OS_InPortByte((u16)(basePort + 67)) & 0x80) == 0) {
                while ((OS_InPortByte((u16)(basePort + 67)) & 0x80) == 0 &&
                       (OS_InPortByte((u16)(basePort + 66)) & 2) == 0)
                    ;
            }
            if ((card->globalFlags & 0x20) != 0)
                phaseChkFifo(basePort, cardIndex);
            OS_OutPortByte((u16)(basePort + 67), 0xff);
            autoCmdCmplt(basePort, cardIndex);
        } else if ((event & 1) != 0) {
            if ((card->globalFlags & 0x20) != 0)
                phaseChkFifo(basePort, cardIndex);
            if ((u8)OS_InPortByte((u16)(basePort + 105)) == 2) {
                OS_OutPortByte((u16)(basePort + 105), 0);
                sccb->Sccb_XferState |= 0x80;
                sccb->Sccb_savedATC = sccb->Sccb_ATC;
            }
            sccb->Sccb_scsistat = 9;
            queueDisconnect(sccb, cardIndex);
            if ((OS_InPortByte((u16)(basePort + 67)) & 0x80) == 0) {
                while ((OS_InPortByte((u16)(basePort + 67)) & 0x80) == 0 &&
                       (OS_InPortByte((u16)(basePort + 66)) & 2) == 0)
                    ;
            }
            OS_OutPortByte((u16)(basePort + 67), 129);
            card->globalFlags |= 0x40;
        } else if ((irqStatus & 2) != 0) {
            OS_OutPortByte((u16)(basePort + 66), 66);
            OS_OutPortByte((u16)(basePort + 67), 160);
            if ((OS_InPortByte((u16)(basePort + 67)) & 1) != 0) {
                if ((card->globalFlags & 0x20) != 0)
                    phaseChkFifo(basePort, cardIndex);
                if ((u8)OS_InPortByte((u16)(basePort + 105)) == 2) {
                    OS_OutPortByte((u16)(basePort + 105), 0);
                    sccb->Sccb_XferState |= 0x80;
                    sccb->Sccb_savedATC = sccb->Sccb_ATC;
                }
                OS_OutPortByte((u16)(basePort + 67), 129);
                sccb->Sccb_scsistat = 9;
                queueDisconnect(sccb, cardIndex);
            }
            scsiReselection((u16)basePort, cardIndex, card);
            phaseDecode(basePort, cardIndex);
        } else if ((event & 0x82) == 2) {
            OS_OutPortByte((u16)(basePort + 67), 66);
            phaseDecode(basePort, cardIndex);
        } else if ((event & 0x10) != 0 || (irqStatus & 0x40) != 0) {
            OS_OutPortByte((u16)(basePort + 67), 48);
            OS_OutPortByte((u16)(basePort + 66), 64);
            if ((OS_InPortByte((u16)(basePort + 79)) & 0x3f) > 0x27) {
                u8 transfer = (u8)OS_InPortByte((u16)(basePort + 111));
                u8 target = (u8)OS_InPortByte((u16)(basePort + 107));
                OS_OutPortByte((u16)(basePort + 115), 8);
                OS_OutPortByte((u16)(basePort + 83), (u8)(target | (16 * target)));
                OS_OutPortByte((u16)(basePort + 115), 0);
                OS_OutPortByte((u16)(basePort + 111), transfer);
                OS_OutPortByte((u16)(basePort + 103), 32);
            } else {
                phaseDecode(basePort, cardIndex);
            }
        } else if ((event & 0x40) != 0) {
            OS_OutPortByte((u16)(basePort + 67), 64);
            scsiChkDmaDone(basePort, cardIndex);
        } else if (event >= 0) {
            if ((event & 4) != 0) {
                OS_OutPortByte((u16)(basePort + 67), 4);
                card->globalFlags |= 0x40;
            }
        } else {
            OS_OutPortByte((u16)(basePort + 67), 128);
            if ((card->globalFlags & 0x20) != 0)
                hostDataXferAbort(basePort, cardIndex, sccb);
            phaseBusFree(basePort, cardIndex);
        }

        if ((card->globalFlags & 0x40) != 0) {
            card->globalFlags &= (u8)~0x40;
            if (card->currentSCCB != 0 ||
                (queueSearchSelect(card, cardIndex), card->currentSCCB != 0)) {
                card->globalFlags &= (u8)~0x40;
                scsiSelect(basePort, cardIndex);
            }
            break;
        }
        sccb = card->currentSCCB;
        status = (u8)OS_InPortByte((u16)(basePort + 66));
        irqStatus = (u8)OS_InPortByte((u16)(basePort + 64)) & status;
        interruptEnable = (u8)OS_InPortByte((u16)(basePort + 67));
        event = (signed char)((u8)OS_InPortByte((u16)(basePort + 65)) & interruptEnable);
    }
    OS_Lock(card->cardInfo);
    status = (u8)OS_InPortByte((u16)(basePort + 41));
    OS_OutPortByte((u16)(basePort + 41), (u8)(status & 0xf7));
    OS_UnLock(card->cardInfo);
    return 0;
}

int utilUpdateResidual(struct sccb *sccb)
{
    u32 transferred;
    u16 index;

    if ((sccb->Sccb_XferState & 2) != 0) {
        sccb->DataLength = 0;
    } else if ((sccb->Sccb_XferState & 4) != 0) {
        transferred = 0;
        index = sccb->Sccb_sgseg;
        if (sccb->Sccb_SGoffset != 0)
            transferred = sccb->Sccb_SGoffset;
        for (;;) {
            transferred += sccb->SGEntries[index].length;
            ++index;
            if (sccb->DataLength <= (u32)index * 8)
                break;
        }
        sccb->DataLength = transferred;
    } else {
        sccb->DataLength -= sccb->Sccb_ATC;
    }
    return 0;
}

int Wait(u16 basePort, u8 ticks)
{
    u8 saved = OS_InPortByte((u16)(basePort + 108));
    u8 value;

    OS_OutPortByte((u16)(basePort + 108), ticks);
    OS_OutPortByte((u16)(basePort + 66), 1);
    value = OS_InPortByte((u16)(basePort + 64));
    OS_OutPortByte((u16)(basePort + 64), (u8)(value & 0xfe));
    value = OS_InPortByte((u16)(basePort + 70));
    OS_OutPortByte((u16)(basePort + 70), (u8)(value | 1));
    while ((OS_InPortByte((u16)(basePort + 66)) & 1) == 0 &&
           (OS_InPortByte((u16)(basePort + 69)) & 2) == 0 &&
           (OS_InPortByte((u16)(basePort + 66)) & 4) == 0)
        ;
    value = OS_InPortByte((u16)(basePort + 70));
    OS_OutPortByte((u16)(basePort + 70), (u8)(value & 0xfe));
    OS_OutPortByte((u16)(basePort + 108), saved);
    OS_OutPortByte((u16)(basePort + 66), 1);
    value = OS_InPortByte((u16)(basePort + 64));
    return OS_OutPortByte((u16)(basePort + 64), (u8)(value | 1));
}

int Wait1Second(u16 basePort)
{
    u8 i;
    int result = 0;

    for (i = 0; i <= 3; ++i) {
        Wait(basePort, 0x99);
        result = OS_InPortByte((u16)(basePort + 69));
        if ((result & 2) != 0)
            break;
        result = OS_InPortByte((u16)(basePort + 66));
        if ((result & 4) != 0)
            break;
    }
    return result;
}

int doesCrossPage(u32 address, u32 length)
{
    u32 pageBits = ~page_mask;
    return (address & pageBits) != ((address + length - 1) & pageBits);
}

int SccbMgr_my_int(struct sccb_card *card)
{
    return (OS_InPortByte((u16)(card->ioPort + 55)) & 0x20) != 0;
}

int SccbMgrTableInitTarget(u8 cardIndex, u8 target)
{
    struct sccb_mgr_target *entry = blfp_target(cardIndex, target);
    u8 i;
    u8 j;
    int result = 0;

    entry->selectCount = 0;
    entry->syncValue = 0;
    entry->selectHead = 0;
    entry->selectTail = 0;
    entry->selectEligible = 0;
    for (i = 0; i <= 31; ++i) {
        ((u8 *)entry)[i + 32] = 0;
        ((u8 *)entry)[i] = 0;
        for (j = 0; j <= 32; ++j) {
            result = j;
            entry->disconnected[j] = 0;
        }
    }
    return result;
}

int SccbMgrTableInitCard(struct sccb_card *card, u8 cardIndex)
{
    u8 i;
    int result = 0;

    for (i = 0; i <= 15; ++i) {
        ((u8 *)&sccbMgrTbl[cardIndex][i])[2] = 0;
        ((u8 *)&sccbMgrTbl[cardIndex][i])[3] = 0;
        result = SccbMgrTableInitTarget(cardIndex, i);
    }
    card->tagQ_Lst = 0;
    card->currentSCCB = 0;
    card->globalFlags = 0;
    card->cmdCounter = 0;
    return result;
}

int SccbMgrTableInitAll(void)
{
    u8 i;
    int result = 0;

    for (i = 0; i <= 3; ++i) {
        struct sccb_card *card = &BL_Card[i];
        result = SccbMgrTableInitCard(card, i);
        card->ioPort = 0;
        card->cardInfo = 0;
        card->discQCount = 0xff;
        card->ourId = 0;
    }
    return result;
}

int scsiInitSCCB(struct sccb *sccb, u8 cardIndex)
{
    struct sccb_mgr_target *entry = blfp_target(cardIndex, sccb->TargID);
    u8 identify;

    sccb->Sccb_XferState = 0;
    sccb->Sccb_XferCnt = sccb->DataLength;
    if (sccb->OperationCode == SCATTER_GATHER_COMMAND ||
        sccb->OperationCode == RESIDUAL_SG_COMMAND) {
        sccb->Sccb_SGoffset = 0;
        sccb->Sccb_XferState = 4;
        sccb->Sccb_XferCnt = 0;
    }
    if (sccb->DataLength == 0)
        sccb->Sccb_XferState |= 2;
    if ((sccb->ControlByte & 0x20) != 0) {
        if ((entry->status & 0x0c) == 8)
            sccb->ControlByte &= (u8)~0x20;
        else
            entry->status |= 4;
    }
    if (((BL_CardFlags[20 * cardIndex] & 2) == 0 &&
         (entry->status & 1) != 0) || (entry->status & 4) != 0)
        identify = (u8)(sccb->Lun | 0xc0);
    else
        identify = (u8)(sccb->Lun | 0x80);
    sccb->Sccb_idmsg = identify;
    sccb->HostStatus = 0;
    sccb->TargetStatus = 0;
    sccb->Sccb_tag = 0;
    sccb->Sccb_MGRFlags = 0;
    sccb->Sccb_sgseg = 0;
    sccb->Sccb_ATC = 0;
    sccb->Sccb_savedATC = 0;
    sccb->Sccb_scsistat = 0;
    sccb->SccbStatus = 0;
    sccb->Sccb_scsimsg = 8;
    return 5 * cardIndex;
}

int utilEESendCmdAddr(u16 basePort, u8 command, u16 address)
{
    u8 value;
    u16 bit;
    u16 addressBit;
    u16 port = (u16)(basePort + 34);
    u16 firstAddressBit;
    int result = 0;

    firstAddressBit = (OS_InPortByte((u16)(basePort + 41)) & 0x10) ? 512 : 128;
    OS_OutPortByte(port, 0x20);
    OS_OutPortByte(port, 0x28);
    value = 0x28;
    for (bit = 4; bit != 0; bit >>= 1) {
        value = ((bit & command) != 0) ? (u8)(value | 2) : (u8)(value & 0xfd);
        OS_OutPortByte(port, value);
        value |= 4;
        OS_OutPortByte(port, value);
        value &= 0xfb;
        OS_OutPortByte(port, value);
    }
    for (addressBit = firstAddressBit; addressBit != 0; addressBit >>= 1) {
        value = ((addressBit & address) != 0) ? (u8)(value | 2) : (u8)(value & 0xfd);
        OS_OutPortByte(port, value);
        value |= 4;
        OS_OutPortByte(port, value);
        value &= 0xfb;
        result = OS_OutPortByte(port, value);
    }
    return result;
}

int utilEEWriteOnOff(u16 basePort, u8 mode)
{
    u8 value = (u8)OS_InPortByte((u16)(basePort + 34)) & 0xc0;
    utilEESendCmdAddr(basePort, 4, mode != 0 ? 960 : 0);
    OS_OutPortByte((u16)(basePort + 34), (u8)(value | 0x20));
    return OS_OutPortByte((u16)(basePort + 34), value);
}

int utilEEWrite(u16 basePort, u16 data, short address)
{
    u16 bit = 0x8000;
    u16 port = (u16)(basePort + 34);
    u8 value = ((u8)OS_InPortByte(port) & 0xc0) | 0x28;
    u8 topBits;
    int result;

    utilEESendCmdAddr(basePort, 5, address);
    while (bit != 0) {
        value = ((bit & (u16)data) != 0) ? (u8)(value | 2) : (u8)(value & 0xfd);
        OS_OutPortByte(port, value);
        value |= 4;
        OS_OutPortByte(port, value);
        value &= 0xfb;
        OS_OutPortByte(port, value);
        bit >>= 1;
    }
    topBits = value & 0xc0;
    OS_OutPortByte(port, (u8)(topBits | 0x20));
    Wait(basePort, 7);
    OS_OutPortByte(port, (u8)(topBits | 0x28));
    OS_OutPortByte(port, (u8)(topBits | 0x20));
    result = OS_OutPortByte(port, topBits);
    return result;
}

int utilEERead(u16 basePort, short address)
{
    u16 bitCount = 1;
    u16 data = 0;
    u16 port = (u16)(basePort + 34);
    u8 value = ((u8)OS_InPortByte(port) & 0xc0) | 0x28;

    utilEESendCmdAddr(basePort, 6, (u16)address);
    do {
        value |= 4;
        OS_OutPortByte(port, value);
        value &= 0xfb;
        OS_OutPortByte(port, value);
        data *= 2;
        if ((OS_InPortByte(port) & 1) != 0)
            data |= 1;
        ++bitCount;
    } while (bitCount <= 16);
    value &= 0xd7;
    OS_OutPortByte(port, (u8)(value | 0x20));
    OS_OutPortByte(port, value);
    return data;
}

int scsiSenseSetup(struct sccb **sccbPointer)
{
    struct sccb *sccb = *sccbPointer;
    u8 i;
    int result = 0;

    sccb->Save_CdbLen = sccb->CdbLength;
    for (i = 0; i <= 5; ++i) {
        result = i;
        sccb->Save_Cdb[i] = sccb->Cdb[i];
    }
    sccb->CdbLength = 6;
    sccb->Cdb[0] = 3;
    sccb->Cdb[1] &= 0xe0;
    sccb->Cdb[2] = 0;
    sccb->Cdb[3] = 0;
    sccb->Cdb[4] = sccb->RequestSenseLength;
    sccb->Cdb[5] = 0;
    sccb->Sccb_XferCnt = sccb->RequestSenseLength;
    sccb->Sccb_ATC = 0;
    sccb->Sccb_XferState |= 8;
    sccb->Sccb_XferState &= (u8)~4;
    sccb->Sccb_idmsg &= (u8)~0x40;
    sccb->ControlByte = 0;
    sccb->Sccb_MGRFlags &= 1;
    return result;
}

int scsiSetSyncValue(u16 basePort, u8 target, u8 value,
                     struct sccb_mgr_target *targetState)
{
    static const u8 portOrder[16] = {
        12, 13, 14, 15, 8, 9, 10, 11, 4, 5, 6, 7, 0, 1, 2, 3
    };
    u8 selector = target < 16 ? portOrder[target] : target;
    int result = OS_OutPortByte((u16)(basePort + selector + 84), value);
    targetState->syncValue = value;
    return result;
}

int scsiFetchMsg(u16 basePort, struct sccb *sccb)
{
    u16 count = 0;
    u16 previous;
    u8 message;

    do {
        if ((OS_InPortByte((u16)(basePort + 68)) & 0x20) != 0)
            break;
        previous = count++;
    } while (previous <= 0x4e1f);

    OS_OutPortByte((u16)(basePort + 70), 0x80);
    message = (u8)OS_InPortByte((u16)(basePort + 116));
    OS_OutPortByte((u16)(basePort + 68), 0x12);
    if (count > 0x4e20)
        message = 0;
    if ((OS_InPortByte((u16)(basePort + 66)) & 0x20) != 0 &&
        (OS_InPortByte((u16)(basePort + 78)) & 1) != 0) {
        OS_OutPortByte((u16)(basePort + 66), 0x20);
        if (sccb != 0)
            sccb->Sccb_scsimsg = 9;
        while ((OS_InPortByte((u16)(basePort + 68)) & 0x20) != 0)
            ;
        OS_OutPortByte((u16)(basePort + 68), 0x0a);
        return 0;
    }
    return message;
}

int dataXferProcessor(u32 basePort, struct sccb_card *card)
{
    struct sccb *sccb = card->currentSCCB;
    if ((sccb->Sccb_XferState & 4) != 0) {
        if ((card->globalFlags & 0x20) != 0) {
            sccb->Sccb_sgseg += 16;
            sccb->Sccb_SGoffset = 0;
        }
        card->globalFlags |= 0x20;
        return busMstrSGDataXferStart(basePort, sccb);
    }
    if ((card->globalFlags & 0x20) == 0) {
        card->globalFlags |= 0x20;
        return busMstrDataXferStart(basePort, sccb);
    }
    {
        union { struct sccb *pointer; u32 word; } result;
        result.pointer = sccb;
        return (int)result.word;
    }
}

int phaseDecode(u32 basePort, u8 cardIndex)
{
    int phase;
    OS_OutPortByte((u16)(basePort + 71), 2);
    OS_OutPortByte((u16)(basePort + 71), 0);
    phase = OS_InPortByte((u16)(basePort + 68)) & 7;
    return phaseTable[phase](basePort, cardIndex);
}

int ScamWireOrData(u16 basePort, u8 mask)
{
    u8 count = 0;
    int value;
    do {
        value = OS_InPortByte((u16)(basePort + 116));
        if (((u8)value & mask) != 0)
            count = 0;
        else
            ++count;
    } while (count <= 15);
    return value;
}

int ScamWireOrSig(u16 basePort, u8 mask)
{
    u8 count = 0;
    int value;
    do {
        value = OS_InPortByte((u16)(basePort + 68));
        if (((u8)value & mask) != 0)
            count = 0;
        else
            ++count;
    } while (count <= 15);
    return value;
}

int ScamValidQ(u8 value)
{
    u8 bit;
    for (bit = 1; bit <= 7; bit <<= 1) {
        if ((value & bit) == 0)
            value = (u8)(value + 0x80);
    }
    return (value & 0x18) == 0;
}

int ScamWaitSelection(u16 basePort)
{
    int value;
    do {
        value = OS_InPortByte((u16)(basePort + 66));
    } while ((value & 4) == 0);
    return value;
}

int ScamSendIsolate(u16 basePort, const u8 idString[32])
{
    u8 byteIndex;
    int matched = 0;

    for (byteIndex = 0; byteIndex <= 0x1f; ++byteIndex) {
        u8 bitMask;
        for (bitMask = 0x80; bitMask != 0; bitMask >>= 1) {
            u8 cycle;
            if (matched) {
                cycle = (u8)ScamXferCycle(basePort, 0);
            } else if ((idString[byteIndex] & bitMask) != 0) {
                cycle = (u8)ScamXferCycle(basePort, 2);
            } else {
                cycle = (u8)ScamXferCycle(basePort, 1);
                matched = (cycle & 2) != 0;
            }
            if ((cycle & 0x1c) == 0x10)
                return 0;
            if ((cycle & 0x1c) != 0)
                return 255;
            if (matched && (cycle & 0x1f) == 0)
                return 1;
        }
    }
    return matched;
}

int ScamIsolate(u16 basePort, u8 idString[32])
{
    u8 byteIndex = 0;
    u8 bitIndex;
    u8 value = 0;

    for (;;) {
        for (bitIndex = 0; bitIndex < 8; ++bitIndex) {
            u8 cycle = (u8)ScamXferCycle(basePort, 0);
            if ((cycle & 0xfc) != 0)
                return 255;
            value = (u8)(value << 1);
            if ((cycle & 2) != 0)
                value |= 1;
            if ((cycle & 0x1f) == 0)
                return byteIndex == 0 ? 255 : 0;
        }
        idString[byteIndex++] = value;
        if (byteIndex > 0x1f)
            return 0;
    }
}

int initScamInfo(u8 cardIndex, u16 basePort)
{
    u8 count = 16;
    u8 target;
    int result = 0;

    if ((OS_InPortByte((u16)(basePort + 41)) & 0x10) != 0)
        count = 8;
    for (target = 0; target < count; ++target) {
        u8 offset;
        for (offset = 0; offset <= 0x1e; offset += 2) {
            u16 word = (u16)utilEERead(basePort,
                (short)(16 * target + (offset >> 1) + 128));
            scamInfo[cardIndex][target].idString[offset] = (u8)word;
            scamInfo[cardIndex][target].idString[offset + 1] = (u8)(word >> 8);
        }
        if (scamInfo[cardIndex][target].idString[0] != 0 &&
            scamInfo[cardIndex][target].idString[0] != 0xff)
            scamInfo[cardIndex][target].state = 17;
        else
            scamInfo[cardIndex][target].state = 16;
        result = 144 * cardIndex;
    }
    return result * 4;
}

int scamMatchId(u8 cardIndex, const char *idString)
{
    u8 target;
    u8 slotCount = (idString[0] & 0x20) != 0 ? 8 : 16;
    u8 initial;
    u8 tries;

    for (target = 0; target < 16; ++target) {
        if (scamInfo[cardIndex][target].state == 17) {
            u8 index;
            int equal = 1;
            for (index = 0; index < 32; ++index) {
                if (scamInfo[cardIndex][target].idString[index] !=
                    (u8)idString[index])
                    equal = 0;
            }
            if (equal) {
                scamInfo[cardIndex][target].state = 18;
                return target;
            }
        }
    }

    initial = (idString[0] & 6) == 2 || (idString[0] & 6) == 4
        ? ((u8)idString[1] & 0x1f) : 7;
    target = initial;
    for (tries = 0; tries < slotCount; ++tries) {
        if (scamInfo[cardIndex][target].state == 16) {
            u8 index;
            for (index = 0; index < 32; ++index)
                scamInfo[cardIndex][target].idString[index] = (u8)idString[index];
            scamInfo[cardIndex][target].state = 18;
            BL_Card[cardIndex].globalFlags |= 0x80;
            return target;
        }
        if (target-- == 0)
            target = slotCount - 1;
    }

    if ((u8)idString[0] & 0x80)
        return 20;
    target = initial;
    for (tries = 0; tries < slotCount; ++tries) {
        if (scamInfo[cardIndex][target].state == 17) {
            u8 index;
            for (index = 0; index < 32; ++index)
                scamInfo[cardIndex][target].idString[index] = (u8)idString[index];
            scamInfo[cardIndex][target].idString[0] |= 0x80;
            scamInfo[cardIndex][target].state = 18;
            BL_Card[cardIndex].globalFlags |= 0x80;
            return target;
        }
        if (target-- == 0)
            target = slotCount - 1;
    }
    return 21;
}

int ScamArbitration(u16 basePort, u8 start)
{
    u8 value;

    if (start == 1) {
        while ((OS_InPortByte((u16)(basePort + 68)) & 0xc0) != 0)
            ;
        if ((OS_InPortByte((u16)(basePort + 68)) & 0x80) != 0 ||
            (u8)OS_InPortByte((u16)(basePort + 116)) != 0)
            return 0;
        value = (u8)OS_InPortByte((u16)(basePort + 68));
        OS_OutPortByte((u16)(basePort + 68), (u8)(value | 0x40));
        if ((OS_InPortByte((u16)(basePort + 68)) & 0x80) != 0) {
            value = (u8)OS_InPortByte((u16)(basePort + 68));
            OS_OutPortByte((u16)(basePort + 68), (u8)(value & 0xbf));
            return 0;
        }
        value = (u8)OS_InPortByte((u16)(basePort + 68));
        OS_OutPortByte((u16)(basePort + 68), (u8)(value | 0x80));
        if ((u8)OS_InPortByte((u16)(basePort + 116)) != 0) {
            value = (u8)OS_InPortByte((u16)(basePort + 68));
            OS_OutPortByte((u16)(basePort + 68), (u8)(value & 0x3f));
            return 0;
        }
    }

    value = (u8)OS_InPortByte((u16)(basePort + 109));
    OS_OutPortByte((u16)(basePort + 109), (u8)(value & 0xef));
    OS_OutPortByte((u16)(basePort + 71), 0x20);
    OS_OutPortByte((u16)(basePort + 116), 0);
    OS_OutPortByte((u16)(basePort + 117), 0);
    OS_OutPortByte((u16)(basePort + 70), 2);
    value = (u8)OS_InPortByte((u16)(basePort + 68));
    OS_OutPortByte((u16)(basePort + 68), (u8)(value | 2));
    value = (u8)OS_InPortByte((u16)(basePort + 68));
    OS_OutPortByte((u16)(basePort + 68), (u8)(value & 0xbf));
    Wait(basePort, 153);
    return 1;
}

int ScamBusFree(u16 basePort)
{
    u8 value;

    value = (u8)OS_InPortByte((u16)(basePort + 41));
    OS_OutPortByte((u16)(basePort + 41), (u8)(value | 8));
    OS_OutPortByte((u16)(basePort + 116), 0);
    value = (u8)OS_InPortByte((u16)(basePort + 70));
    OS_OutPortByte((u16)(basePort + 70), (u8)(value & 0xfd));
    OS_OutPortByte((u16)(basePort + 68), 0);
    value = (u8)OS_InPortByte((u16)(basePort + 71));
    OS_OutPortByte((u16)(basePort + 71), (u8)(value & 0xdf));
    value = (u8)OS_InPortByte((u16)(basePort + 109));
    OS_OutPortByte((u16)(basePort + 109), (u8)(value | 0x10));
    OS_OutPortByte((u16)(basePort + 67), 0x9f);
    value = (u8)OS_InPortByte((u16)(basePort + 41));
    return OS_OutPortByte((u16)(basePort + 41), (u8)(value & 0xf7));
}

int ScamSelect(u16 basePort)
{
    u8 value;

    OS_OutPortByte((u16)(basePort + 68), 0x80);
    ScamWireOrSig(basePort, 2);
    OS_OutPortByte((u16)(basePort + 68), 0xc0);
    OS_OutPortByte((u16)(basePort + 68), 0xc5);
    value = (u8)OS_InPortByte((u16)(basePort + 116));
    OS_OutPortByte((u16)(basePort + 116), (u8)(value | 0xc0));
    OS_OutPortByte((u16)(basePort + 68), 0x45);
    ScamWireOrSig(basePort, 0x80);
    value = (u8)OS_InPortByte((u16)(basePort + 116));
    OS_OutPortByte((u16)(basePort + 116), (u8)(value & 0xbf));
    ScamWireOrData(basePort, 0x40);
    return OS_OutPortByte((u16)(basePort + 68), 0xc5);
}

int ScamXferCycle(u16 basePort, u8 value)
{
    u8 sampled;

    OS_OutPortByte((u16)(basePort + 116), (u8)(value | 0xa0));
    OS_OutPortByte((u16)(basePort + 116), (u8)((value & 0x5f) | 0x20));
    ScamWireOrData(basePort, 0x80);
    while ((OS_InPortByte((u16)(basePort + 116)) & 0x20) == 0)
        ;
    sampled = (u8)OS_InPortByte((u16)(basePort + 116)) & 0x1f;
    OS_OutPortByte((u16)(basePort + 116), (u8)((value & 0x1f) | 0x60));
    OS_OutPortByte((u16)(basePort + 116), (u8)((value & 0x1f) | 0x40));
    ScamWireOrData(basePort, 0x20);
    OS_OutPortByte((u16)(basePort + 116), 0xc0);
    OS_OutPortByte((u16)(basePort + 116), 0x80);
    ScamWireOrData(basePort, 0x40);
    return sampled;
}

int ScamAssignID(u8 cardIndex, u16 basePort)
{
    u8 idString[32];
    u8 result;

    do {
        u8 index;
        for (index = 0; index < 32; ++index)
            idString[index] = 0;
        ScamXferCycle(basePort, 31);
        ScamXferCycle(basePort, 0);
        if (ScamIsolate(basePort, idString) != 0) {
            result = 1;
        } else {
            u8 bit;
            result = (u8)scamMatchId(cardIndex, (const char *)idString);
            if (result == 20) {
                ScamXferCycle(basePort, 20);
                ScamXferCycle(basePort, 24);
                result = 0;
            } else if (result != 21) {
                u8 encoded = result & 7;
                if (result > 7)
                    ScamXferCycle(basePort, 17);
                else
                    ScamXferCycle(basePort, 24);
                for (bit = 1; bit <= 7; bit <<= 1) {
                    if ((result & bit) == 0)
                        encoded = (u8)(encoded + 8);
                }
                ScamXferCycle(basePort, encoded);
                result = 0;
            }
        }
    } while (result == 0);

    ScamXferCycle(basePort, 31);
    return ScamXferCycle(basePort, 3);
}

int ScamSelLegacy(u16 basePort, u8 target)
{
    u8 value;
    u16 port;

    value = (u8)OS_InPortByte((u16)(basePort + 41));
    OS_OutPortByte((u16)(basePort + 41), (u8)(value | 8));
    value = (u8)OS_InPortByte((u16)(basePort + 41));
    OS_OutPortByte((u16)(basePort + 41), (u8)(value | 2));
    value = (u8)OS_InPortByte((u16)(basePort + 78));
    OS_OutPortByte((u16)(basePort + 78), (u8)(value | 0x80));
    OS_OutPortByte((u16)(basePort + 108), 0x67);
    for (port = (u16)(basePort + 136); port < basePort + 148; port += 2)
        OS_OutPortWord(port, 0x8400);
    OS_OutPortWord(port, 0x2010);
    OS_OutPortByte((u16)(basePort + 66), 0x89);
    OS_OutPortByte((u16)(basePort + 67), 0x9f);
    OS_OutPortByte((u16)(basePort + 83), target);
    OS_OutPortByte((u16)(basePort + 70), 0x80);
    OS_OutPortByte((u16)(basePort + 103), 0x42);
    OS_OutPortByte((u16)(basePort + 69), 0x44);
    while ((OS_InPortByte((u16)(basePort + 66)) & 0xc1) == 0 &&
           (OS_InPortByte((u16)(basePort + 67)) & 0x1f) == 0)
        ;
    if ((OS_InPortByte((u16)(basePort + 66)) & 0x80) != 0)
        Wait(basePort, 153);
    OS_OutPortByte((u16)(basePort + 71), 2);
    OS_OutPortByte((u16)(basePort + 71), 0);
    value = (u8)OS_InPortByte((u16)(basePort + 78));
    OS_OutPortByte((u16)(basePort + 78), (u8)(value & 0x7f));
    OS_OutPortByte((u16)(basePort + 108), 0xb1);
    value = (u8)OS_InPortByte((u16)(basePort + 41));
    OS_OutPortByte((u16)(basePort + 41), (u8)(value & 0xfd));
    if ((OS_InPortByte((u16)(basePort + 66)) & 0x81) != 0) {
        OS_OutPortByte((u16)(basePort + 66), 0x89);
        OS_OutPortByte((u16)(basePort + 67), 0xa0);
        value = (u8)OS_InPortByte((u16)(basePort + 41));
        OS_OutPortByte((u16)(basePort + 41), (u8)(value & 0xf7));
        return 0;
    }
    while ((OS_InPortByte((u16)(basePort + 67)) & 0x80) == 0) {
        if ((OS_InPortByte((u16)(basePort + 68)) & 0x20) != 0) {
            OS_OutPortByte((u16)(basePort + 68), 0x12);
            while ((OS_InPortByte((u16)(basePort + 68)) & 0x20) != 0)
                ;
            OS_OutPortByte((u16)(basePort + 68), 2);
        }
    }
    OS_OutPortByte((u16)(basePort + 67), 0xff);
    value = (u8)OS_InPortByte((u16)(basePort + 41));
    OS_OutPortByte((u16)(basePort + 41), (u8)(value & 0xf7));
    return 1;
}

int scamSaveDeviceInfo(u8 cardIndex, u16 basePort)
{
    short checksum = 0;
    u8 targetCount = 16;
    u8 target;

    for (target = 1; target <= 0x7f; ++target)
        checksum = (short)(checksum + utilEERead(basePort, target));
    utilEEWriteOnOff(basePort, 1);
    if ((OS_InPortByte((u16)(basePort + 41)) & 0x10) != 0)
        targetCount = 8;
    for (target = 0; target < targetCount; ++target) {
        u8 offset;
        for (offset = 0; offset <= 0x1e; offset += 2) {
            u16 word = (u16)scamInfo[cardIndex][target].idString[offset] |
                       (u16)((u16)scamInfo[cardIndex][target].idString[offset + 1] << 8);
            checksum = (short)(checksum + word);
            utilEEWrite(basePort, word,
                (short)(16 * target + (offset >> 1) + 128));
        }
    }
    utilEEWrite(basePort, (u16)checksum, 0);
    return utilEEWriteOnOff(basePort, 0);
}

#ifndef BLFP_TEST_STUB_SCAM_INIT
int ScamInit(u8 cardIndex, u8 adapterId, int reserved)
{
    struct sccb_card *card = &BL_Card[cardIndex];
    u16 basePort = (u16)card->ioPort;
    u8 eepromConfig;
    u8 target;
    u8 legacyCount = 0;
    int result = 0;

    (void)reserved;
    initScamInfo(cardIndex, basePort);
    Wait1Second(basePort);
    eepromConfig = (u8)utilEERead(basePort, 10);
    scamInfo[cardIndex][adapterId].state = 18;
    for (target = 0; target <= 15; ++target) {
        u32 state = scamInfo[cardIndex][target].state;
        if ((state == 16 || state == 17) && ScamSelLegacy(basePort, target) != 0) {
            scamInfo[cardIndex][target].state = 19;
            if (scamInfo[cardIndex][target].idString[0] != 0xff ||
                scamInfo[cardIndex][target].idString[1] != 0xfa) {
                scamInfo[cardIndex][target].idString[0] = 0xff;
                scamInfo[cardIndex][target].idString[1] = 0xfa;
                card->globalFlags |= 0x80;
            }
        }
    }
    if ((eepromConfig & 4) != 0) {
        scsiResetBus(card->ioPort, cardIndex);
        Wait1Second(basePort);
        while (ScamArbitration(basePort, 1) == 0)
            ;
        ScamSelect(basePort);
        ScamAssignID(cardIndex, basePort);
        if ((eepromConfig & 4) != 0) {
            ScamBusFree(basePort);
            if ((signed char)card->globalFlags < 0) {
                scamSaveDeviceInfo(cardIndex, basePort);
                card->globalFlags &= (u8)~0x80;
            }
        }
    }
    for (target = 0; target <= 15; ++target) {
        if (scamInfo[cardIndex][target].state == 19)
            ScamSelLegacy(basePort, target);
    }
    for (target = 0; target <= 15; ++target) {
        u32 state = scamInfo[cardIndex][target].state;
        result = (int)state - 18;
        if (state == 18 || state == 19)
            ++legacyCount;
    }
    if (legacyCount == 2)
        card->globalFlags |= 2;
    else
        card->globalFlags &= (u8)~2;
    return result;
}
#endif

int phaseStatus(u16 basePort)
{
    return OS_OutPortByte((u16)(basePort + 100), 0x2a);
}

void SccbMgr_timer_expired(void)
{
}

int scsiReselection(u16 basePort, u8 cardIndex, struct sccb_card *card)
{
    struct sccb_mgr_target *target;
    u8 lun = 0;
    u8 identifyLun = 0;
    u8 targetId;
    int result;

    if (card->currentSCCB != 0) {
        target = blfp_target(cardIndex, card->currentSCCB->TargID);
        OS_OutPortByte((u16)(basePort + 71), 2);
        OS_OutPortByte((u16)(basePort + 71), 0);
        OS_OutPortByte((u16)(basePort + 69), 5);
        target->selectEligible = 0;
        queueSelectFail(&card->currentSCCB, cardIndex);
    }
    OS_OutPortWord((u16)(basePort + 110), 0);
    targetId = (u8)OS_InPortByte((u16)(basePort + 83)) >> 4;
    target = blfp_target(cardIndex, targetId);
    while ((OS_InPortByte((u16)(basePort + 68)) & 0x20) == 0) {
        if ((OS_InPortByte((u16)(basePort + 68)) & 0x40) == 0)
            return OS_OutPortByte((u16)(basePort + 67), 0x20);
    }
    OS_OutPortByte((u16)(basePort + 67), 0x20);
    if ((OS_InPortByte((u16)(basePort + 68)) & 7) != 7) {
        while ((OS_InPortByte((u16)(basePort + 68)) & 0x20) != 0)
            ;
        goto reject_reselection;
    }
    result = scsiFetchMsg(basePort, card->currentSCCB);
    if ((u8)result == 0)
        return result;
    if ((u8)result > 0x87) {
        while ((OS_InPortByte((u16)(basePort + 68)) & 0x20) != 0)
            ;
        OS_OutPortByte((u16)(basePort + 68), 0x0a);
        goto lookup_disconnected;
    } else {
        identifyLun = (u8)result & 7;
        if ((target->status & 0x0c) == 4 &&
            target->opaque0[identifyLun + 32] != 0 &&
            target->opaque0[identifyLun] == 0) {
            while ((OS_InPortByte((u16)(basePort + 68)) & 0x20) != 0)
                ;
            OS_OutPortByte((u16)(basePort + 68), 2);
            result = scsiFetchMsg(basePort, card->currentSCCB);
            if ((u8)result == 0)
                return result;
            while ((OS_InPortByte((u16)(basePort + 68)) & 0x20) != 0)
                ;
            OS_OutPortByte((u16)(basePort + 68), 2);
            result = scsiFetchMsg(basePort, card->currentSCCB);
            lun = (u8)result;
            if ((u8)result == 0)
                return result;
            goto lookup_disconnected;
        }
    }

lookup_disconnected:
    if (target->disconnected[lun] != 0) {
        card->currentSCCB = target->disconnected[lun];
        target->disconnected[lun] = 0;
        if (lun != 0)
            --target->opaque0[identifyLun + 32];
        while ((OS_InPortByte((u16)(basePort + 68)) & 0x20) != 0)
            ;
        OS_OutPortByte((u16)(basePort + 68), 2);
        goto finish_reselection;
    }
reject_reselection:
    while ((OS_InPortByte((u16)(basePort + 68)) & 0x20) != 0)
        ;
    OS_OutPortByte((u16)(basePort + 68), 0x0a);
    do {
finish_reselection:
        result = OS_InPortByte((u16)(basePort + 67));
        if ((result & 0x20) != 0)
            break;
        result = OS_InPortByte((u16)(basePort + 66));
        if ((result & 0x80) != 0)
            break;
        result = OS_InPortByte((u16)(basePort + 68));
        if ((result & 0x20) != 0)
            break;
        result = OS_InPortByte((u16)(basePort + 68));
    } while ((result & 0x40) != 0);
    return result;
}

int scsiSelect(u32 basePort, u8 cardIndex)
{
    struct sccb_card *card = &BL_Card[cardIndex];
    struct sccb *sccb = card->currentSCCB;
    struct sccb_mgr_target *target = blfp_target(cardIndex, sccb->TargID);
    u8 targetId = sccb->TargID;
    u8 lun = sccb->Lun;
    u8 value;
    u8 cdbIndex;
    u16 port;
    int negotiation = 0;

    value = (u8)OS_InPortByte((u16)(basePort + 41));
    OS_OutPortByte((u16)(basePort + 41), (u8)(value | 2));
    if ((card->globalFlags & 1) == 0) {
        target->selectEligible = 1;
    } else if ((sccb->ControlByte & 0x20) == 0) {
        if (target->opaque0[lun] == 0 && (target->status & 0x0c) == 4 &&
            target->opaque0[lun + 32] != 0) {
            target->selectEligible = 1;
            return queueSelectFail(&card->currentSCCB, cardIndex);
        }
        target->selectEligible = 1;
    } else if (target->opaque0[lun] == 1) {
        return queueSelectFail(&card->currentSCCB, cardIndex);
    }

    OS_OutPortByte((u16)(basePort + 83), targetId);
    OS_OutPortByte((u16)(basePort + 107), targetId);
    if (sccb->OperationCode == RESET_COMMAND) {
        u16 idMessage = (u16)(((u16)sccb->Sccb_idmsg | 0x8600) & 0x86bf);
        OS_OutPortWord((u16)(basePort + 128), idMessage);
        OS_OutPortWord((u16)(basePort + 130), 0x2010);
        sccb->Sccb_scsimsg = 12;
        OS_OutPortByte((u16)(basePort + 103), 0x40);
        negotiation = 1;
        sccb->Sccb_scsistat = 2;
        if ((target->eepromValue & 3) != 0) {
            target->syncValue = 0;
            target->status &= 0x3f;
        }
        if ((signed char)target->eepromValue < 0)
            target->status &= 0xcf;
        scsiSetSyncValue((u16)basePort, targetId, 16, target);
        SccbMgrTableInitTarget(cardIndex, targetId);
    } else if ((target->status & 0x20) != 0) {
        if ((target->status & 0xc0) != 0xc0) {
            negotiation = scsiInitSyncNego(basePort, cardIndex);
            sccb->Sccb_scsistat = 3;
        }
    } else {
        negotiation = scsiInitWideNego(basePort, cardIndex);
        sccb->Sccb_scsistat = 4;
    }

    if (negotiation == 0) {
        if ((sccb->ControlByte & 0x20) == 0) {
            OS_OutPortWord((u16)(basePort + 128), 0x2002);
            OS_OutPortWord((u16)(basePort + 134),
                (u16)(((u16)sccb->Sccb_idmsg | 0x8600) & 0x86ff));
            sccb->Sccb_scsistat = 1;
            OS_OutPortByte((u16)(basePort + 103), 0x54);
        } else {
            card->globalFlags |= 1;
            if ((target->status & 0x0c) != 8) {
                u8 tag;
                OS_OutPortWord((u16)(basePort + 128),
                    (u16)(((u16)sccb->Sccb_idmsg | 0x8600) & 0x86ff));
                OS_OutPortWord((u16)(basePort + 130),
                    (u16)(((sccb->ControlByte >> 6) | 0x8620)));
                tag = 1;
                while (target->disconnected[tag] != 0) {
                    if (++tag > 0x20)
                        break;
                }
                if (tag != 0x21) {
                    OS_OutPortWord((u16)(basePort + 134), (u16)(tag | 0x8600));
                    sccb->Sccb_tag = tag;
                    sccb->Sccb_scsistat = 5;
                    OS_OutPortByte((u16)(basePort + 103), 0x54);
                } else {
                    target->selectEligible = 1;
                    return queueSelectFail(&card->currentSCCB, cardIndex);
                }
            } else {
                sccb->ControlByte &= (u8)~0x20;
                OS_OutPortWord((u16)(basePort + 128), 0x2002);
                OS_OutPortWord((u16)(basePort + 134),
                    (u16)(((u16)sccb->Sccb_idmsg | 0x8600) & 0x86ff));
                OS_OutPortByte((u16)(basePort + 103), 0x54);
                sccb->Sccb_scsistat = 1;
                target->selectEligible = 1;
            }
        }

        port = (u16)(basePort + 136);
        for (cdbIndex = 0; cdbIndex < sccb->CdbLength; ++cdbIndex) {
            OS_OutPortWord(port,
                (u16)(((u16)sccb->Cdb[cdbIndex] | 0x8400) & 0x84ff));
            port += 2;
        }
        if (sccb->CdbLength != 12)
            OS_OutPortWord(port, 0x2010);
    }

    OS_OutPortWord((u16)(basePort + 110), 0);
    OS_OutPortByte((u16)(basePort + 113), 0);
    OS_OutPortByte((u16)(basePort + 66), 0x49);
    OS_OutPortByte((u16)(basePort + 67), 0x80);
    OS_OutPortByte((u16)(basePort + 70), 0x80);
    if ((sccb->Sccb_MGRFlags & 4) != 0) {
        value = (u8)OS_InPortByte((u16)(basePort + 103)) & 0x1f;
        OS_OutPortByte((u16)(basePort + 71), 2);
        OS_OutPortByte((u16)(basePort + 71), 0);
        OS_OutPortByte((u16)(basePort + 103), (u8)(value | 0x20));
    } else {
        OS_OutPortByte((u16)(basePort + 69), 0x55);
    }
    value = (u8)OS_InPortByte((u16)(basePort + 41));
    return OS_OutPortByte((u16)(basePort + 41), (u8)(value & 0xfd));
}

int SccbMgr_sense_adapter(struct sccb_mgr_info *info)
{
    u16 base = (u16)info->ioBase;
    u16 config10 = 0, config12 = 0, config14 = 0;
    u16 ee;
    u8 flags = 0;

    if ((u8)OS_InPortByte(base) != 75 ||
        (u8)OS_InPortByte((u16)(base + 1)) != 16 ||
        (u8)OS_InPortByte((u16)(base + 2)) != 48 ||
        (u8)OS_InPortByte((u16)(base + 3)) != 0x81 ||
        ((u8)OS_InPortByte((u16)(base + 51)) != 15 &&
         (OS_InPortByte((u16)(base + 6)) & 0x0f) != 0))
        return -1;

    if (first_time_2 != 0) {
        SccbMgrTableInitAll();
        first_time_2 = 0;
    }
    OS_OutPortByte((u16)(base + 109), 19);
    OS_OutPortByte((u16)(base + 15), 0);
    info->adapterId = (u8)utilEERead(base, 12);
    info->lun = 0;
    info->firmwareRevision = 64;
    for (u8 i = 0; i <= 7; ++i) {
        ee = (u16)utilEERead(base, (short)(i + 19));
        for (u8 byteIndex = 0; byteIndex < 2; ++byteIndex) {
            config10 >>= 1;
            if ((ee & 3) != 0)
                config10 |= 0x8000;
            if ((ee & 0x40) != 0)
                config12 = (u16)((config12 >> 1) | 0x8000);
            else
                config12 >>= 1;
            if ((ee & 0x80) != 0)
                config14 = (u16)((config14 >> 1) | 0x8000);
            else
                config14 >>= 1;
            ee >>= 8;
        }
    }
    info->config10 = config10;
    info->config12 = config12;
    info->config14 = config14;
    ee = (u16)utilEERead(base, 8);
    if ((ee & 1) != 0)
        flags = 1;
    {
        u8 value = (u8)OS_InPortByte((u16)(base + 38)) & 0xfe;
        if ((ee & 4) != 0) {
            value |= 1;
            flags |= 0x10;
        }
        OS_OutPortByte((u16)(base + 38), value);
    }
    {
        u8 value = (u8)OS_InPortByte((u16)(base + 34)) & 0xbf;
        if ((ee & 8) != 0) {
            value |= 0x40;
            flags |= 0x20;
        }
        OS_OutPortByte((u16)(base + 34), value);
    }
    if ((OS_InPortByte((u16)(base + 41)) & 0x10) == 0)
        flags |= 2;
    info->flags = flags;
    info->family = 2;
    info->busType = 3;
    info->cardModel[0] = (u8)((u16)utilEERead(base, 2) >> 8);
    *(u16 *)((u8 *)info + 20) = (u16)utilEERead(base, 3);
    {
        u8 value = (u8)OS_InPortByte((u16)(base + 41));
        OS_OutPortByte((u16)(base + 41), value | 2);
    }
    for (u8 i = 0; i <= 3; ++i)
        info->opaque32[i] = (u8)OS_InPortByte((u16)(base + 224 + i));
    info->relativeCard = (u8)(OS_InPortByte((u16)(base + 228)) - 1);
    {
        u8 value = (u8)OS_InPortByte((u16)(base + 41));
        OS_OutPortByte((u16)(base + 41), value & 0xfd);
    }
    phaseTable[0] = phaseDataOut;
    phaseTable[1] = phaseDataIn;
    phaseTable[2] = phaseIllegal;
    phaseTable[3] = phaseIllegal;
    phaseTable[4] = phaseCommand;
    phaseTable[5] = phaseStatusDispatch;
    phaseTable[6] = phaseMsgOut;
    phaseTable[7] = phaseMsgIn;
    info->present = 1;
    return 0;
}

struct sccb_card *SccbMgr_config_adapter(struct sccb_mgr_info *info)
{
    u32 base = info->ioBase;
    struct sccb_card *card = 0;
    u8 cardIndex = 0;

    while (cardIndex < BLFP_CARD_COUNT) {
        struct sccb_card *candidate = &BL_Card[cardIndex];
        if (candidate->ioPort == base) {
            card = candidate;
            break;
        }
        if (candidate->ioPort == 0) {
            candidate->ioPort = base;
            SccbMgrTableInitCard(candidate, cardIndex);
            candidate->discQCount = cardIndex;
            candidate->cardInfo = info;
            card = candidate;
            break;
        }
        ++cardIndex;
    }
    if (card == 0)
        return (struct sccb_card *)-1;

    BusMasterInit(base);
    XbowInit(base);
    autoLoadDefaultMap(base);
    {
        u8 target = 0;
        u8 mask = 1;
        while (info->adapterId != target) {
            ++target;
            mask <<= 1;
        }
        OS_OutPortByte((u16)(base + 80), mask);
    }
    OS_OutPortByte((u16)(base + 81), 0);
    OS_OutPortByte((u16)(base + 82), info->adapterId);
    card->ourId = info->adapterId;
    if ((info->flags & 1) != 0)
        OS_OutPortByte((u16)(base + 114), 9);
    {
        u8 value = (u8)OS_InPortByte((u16)(base + 38)) & 0xfe;
        if ((info->flags & 0x10) != 0)
            value |= 1;
        OS_OutPortByte((u16)(base + 38), value);
    }
    {
        u8 value = (u8)OS_InPortByte((u16)(base + 34)) & 0xbf;
        if ((info->flags & 0x20) != 0)
            value |= 0x40;
        OS_OutPortByte((u16)(base + 34), value);
    }
    if ((info->flags & 4) == 0) {
        scsiResetBus(base, cardIndex);
        ScamInit(cardIndex, info->adapterId, 0);
    }
    if ((info->flags & 0x40) != 0)
        card->globalFlags |= 8;
    if (((u16)utilEERead((u16)base, 8) & 0x1000) != 0)
        card->globalFlags |= 0x10;

    for (u8 target = 0, mask = 1; target <= 15; ++target, mask <<= 1) {
        if ((info->config12 & mask) != 0)
            sccbMgrTbl[cardIndex][target].opaque0[0] |= 1;
    }
    {
        u16 mask = 1;
        for (u8 eepromIndex = 0; eepromIndex <= 7; ++eepromIndex) {
            u16 value = (u16)utilEERead((u16)base, (short)(eepromIndex + 19));
            u8 firstTarget = (u8)(eepromIndex * 2);
            for (u8 half = 0; half <= 1; ++half) {
                struct sccb_mgr_target *target =
                    &sccbMgrTbl[cardIndex][firstTarget + half];
                if ((info->config10 & mask) != 0) {
                    target->opaque0[1] = (u8)value;
                } else {
                    target->opaque0[0] |= 0xc0;
                    target->opaque0[1] = (u8)value & 0xfc;
                }
                if ((info->config14 & mask) != 0)
                    target->opaque0[1] |= 0x80;
                else
                    target->opaque0[0] |= 0x20;
                mask <<= 1;
                value >>= 8;
            }
        }
    }
    {
        u8 value = (u8)OS_InPortByte((u16)(base + 12));
        OS_OutPortByte((u16)(base + 12), value | 8);
    }
    return card;
}

int SccbMgr_scsi_reset(struct sccb_card *card)
{
    u8 index = card->discQCount;
    u32 base = card->ioPort;
    if ((card->cardInfo->flags & 0x10) != 0) {
        OS_OutPortByte((u16)(base + 109), 19);
        OS_OutPortByte((u16)(base + 15), 0);
    }
    scsiResetBus(base, index);
    if ((OS_InPortByte((u16)(base + 54)) & 0x80) != 0) {
        u8 value = (u8)OS_InPortByte((u16)(base + 41));
        OS_OutPortByte((u16)(base + 41), value & 0xfe);
        OS_OutPortByte((u16)(base + 40), 0);
        card->cardInfo->flags &= (u8)~0x20;
        busMstrTimeOut(base);
        OS_OutPortByte((u16)(base + 23), 5);
    }
    return ScamInit(index, card->cardInfo->adapterId, 0);
}

int scsiResetBus(u32 basePort, u8 cardIndex)
{
    u8 value = (u8)OS_InPortByte((u16)(basePort + 41));
    u8 savedTimer;
    OS_OutPortByte((u16)(basePort + 41), value | 8);
    OS_OutPortByte((u16)(basePort + 66), 0xff);
    OS_OutPortByte((u16)(basePort + 67), 0xff);
    OS_OutPortByte((u16)(basePort + 69), 2);
    savedTimer = (u8)OS_InPortByte((u16)(basePort + 108));
    OS_OutPortByte((u16)(basePort + 108), 3);
    OS_OutPortByte((u16)(basePort + 66), 1);
    OS_OutPortByte((u16)(basePort + 70), 0x81);
    while ((OS_InPortByte((u16)(basePort + 66)) & 1) == 0)
        ;
    OS_OutPortByte((u16)(basePort + 108), savedTimer);
    OS_OutPortByte((u16)(basePort + 69), 1);
    Wait((u16)basePort, 3);
    OS_OutPortByte((u16)(basePort + 66), 0xff);
    OS_OutPortByte((u16)(basePort + 67), 0xff);
    value = (u8)OS_InPortByte((u16)(basePort + 23));
    OS_OutPortByte((u16)(basePort + 23), value);
    for (u8 targetId = 0; targetId < MAX_SCSI_TAR; ++targetId) {
        struct sccb_mgr_target *target = &sccbMgrTbl[cardIndex][targetId];
        if ((target->eepromValue & 3) != 0) {
            target->syncValue = 0;
            target->status &= 0x3f;
        }
        if ((signed char)target->eepromValue < 0)
            target->status &= 0xcf;
        scsiSetSyncValue((u16)basePort, targetId, 0x10, target);
        SccbMgrTableInitTarget(cardIndex, targetId);
    }
    BL_Card[cardIndex].tagQ_Lst = 0;
    BL_Card[cardIndex].currentSCCB = 0;
    BL_Card[cardIndex].globalFlags = 0;
    BL_Card[cardIndex].cmdCounter = 0;
    value = (u8)OS_InPortByte((u16)(basePort + 41));
    return OS_OutPortByte((u16)(basePort + 41), value & 0xf7);
}

int busMstrDataXferStart(u32 basePort, struct sccb *sccb)
{
    u32 address;
    u32 length;
    if ((sccb->Sccb_XferState & 8) != 0) {
        address = sccb->SensePointer;
        length = sccb->RequestSenseLength;
    } else {
        union { void *pointer; u32 word; } data;
        data.pointer = sccb->DataPointer;
        address = sccb->SccbVirtDataPtr + data.word;
        length = sccb->Sccb_XferCnt;
    }
    OS_OutPortWord((u16)(basePort + 28), (u16)address);
    OS_OutPortWord((u16)(basePort + 30), (u16)(address >> 16));
    OS_OutPortLong((u16)(basePort + 72), length);
    OS_OutPortWord((u16)(basePort + 24), (u16)length);
    OS_OutPortByte((u16)(basePort + 26), (u8)(length >> 16));
    if ((sccb->Sccb_XferState & 1) != 0) {
        OS_OutPortByte((u16)(basePort + 70), 0xe0);
        OS_OutPortByte((u16)(basePort + 68), 1);
        return OS_OutPortByte((u16)(basePort + 27), 0x21);
    }
    OS_OutPortByte((u16)(basePort + 70), 0xb0);
    OS_OutPortByte((u16)(basePort + 68), 0);
    return OS_OutPortByte((u16)(basePort + 27), 0x20);
}

int busMstrSGDataXferStart(u32 basePort, struct sccb *sccb)
{
    u32 control = (sccb->Sccb_XferState & 1) ? 0xa1000000u : 0xa0000000u;
    u8 count = 0;
    u16 index = sccb->Sccb_sgseg;
    u32 transferred = 0;
    u16 port = 128;
    u8 prior = (u8)OS_InPortByte((u16)(basePort + 41)) & 0xfc;
    OS_OutPortByte((u16)(basePort + 41), prior);
    do {
        u32 length;
        u32 address;
        u32 entryOffset = 8u * index;
        if (sccb->DataLength <= entryOffset)
            break;
        length = sccb->SGEntries[index].length;
        address = sccb->SGEntries[index].address;
        transferred += length;
        control = length | control;
        if (count == 0 && sccb->Sccb_SGoffset != 0) {
            address += (control & 0x00ffffffu) - sccb->Sccb_SGoffset;
            control = sccb->Sccb_SGoffset | (control & 0xff000000u);
            transferred = control & 0x00ffffffu;
        }
        OS_OutPortLong((u16)(basePort + port), address);
        port += 4;
        OS_OutPortLong((u16)(basePort + port), control);
        port += 4;
        control &= 0xff000000u;
        ++index;
        ++count;
    } while (count <= 15);

    sccb->Sccb_XferCnt = transferred;
    OS_OutPortByte((u16)(basePort + 40), (u8)(16 * count));
    if ((sccb->Sccb_XferState & 1) != 0) {
        OS_OutPortLong((u16)(basePort + 72), transferred);
        OS_OutPortByte((u16)(basePort + 70), 0xe0);
        OS_OutPortByte((u16)(basePort + 68), 1);
    } else {
        if ((OS_InPortByte((u16)(basePort + 96)) & 0x10) == 0 &&
            (transferred & 1) != 0) {
            sccb->Sccb_XferState |= 0x10;
            --transferred;
        }
        OS_OutPortLong((u16)(basePort + 72), transferred);
        OS_OutPortByte((u16)(basePort + 70), 0xb0);
        OS_OutPortByte((u16)(basePort + 68), 0);
    }
    return OS_OutPortByte((u16)(basePort + 41), (u8)(prior | 1));
}

int busMstrTimeOut(u32 basePort)
{
    int remaining = 0xffff;
    OS_OutPortByte((u16)(basePort + 15), 8);
    do {
        if ((OS_InPortByte((u16)(basePort + 54)) & 0x10) != 0)
            break;
    } while (remaining-- != 0);
    if ((OS_InPortByte((u16)(basePort + 54)) & 0x80) != 0) {
        remaining = 0xffff;
        OS_OutPortByte((u16)(basePort + 15), 0x10);
        do {
            if ((OS_InPortByte((u16)(basePort + 54)) & 0x80) == 0)
                break;
        } while (remaining-- != 0);
    }
    OS_InPortByte((u16)(basePort + 55));
    return (OS_InPortByte((u16)(basePort + 54)) & 0x80) != 0;
}

void hostDataXferRestart(struct sccb *sccb)
{
    if ((sccb->Sccb_XferState & 4) != 0) {
        int index = -1;
        u32 transferred;
        sccb->Sccb_XferCnt = 0;
        for (transferred = 0; sccb->Sccb_ATC > transferred;
             transferred += sccb->SGEntries[index].length)
            ++index;
        if (sccb->Sccb_ATC == transferred) {
            sccb->Sccb_SGoffset = 0;
            sccb->Sccb_sgseg = (u16)(index + 1);
        } else {
            sccb->Sccb_SGoffset = transferred - sccb->Sccb_ATC;
            sccb->Sccb_sgseg = (u16)index;
        }
    } else {
        sccb->Sccb_XferCnt = sccb->DataLength - sccb->Sccb_ATC;
    }
}

int XbowInit(u32 basePort)
{
    int result;
    OS_OutPortByte((u16)(basePort + 71), 0);
    OS_OutPortByte((u16)(basePort + 114), 1);
    OS_OutPortByte((u16)(basePort + 71), 0x0f);
    OS_OutPortByte((u16)(basePort + 71), 0);
    OS_OutPortByte((u16)(basePort + 109), 0x13);
    OS_OutPortByte((u16)(basePort + 68), 0);
    OS_OutPortByte((u16)(basePort + 69), 1);
    OS_OutPortByte((u16)(basePort + 66), 0xff);
    OS_OutPortByte((u16)(basePort + 67), 0xff);
    OS_OutPortByte((u16)(basePort + 64), 0xc3);
    OS_OutPortByte((u16)(basePort + 65), 0xdf);
    OS_OutPortByte((u16)(basePort + 108), 0xb1);
    result = OS_InPortByte((u16)(basePort + 41));
    if ((result & 0x10) != 0)
        return OS_OutPortByte((u16)(basePort + 78), 8);
    return result;
}

int BusMasterInit(u32 basePort)
{
    int value;
    OS_OutPortByte((u16)(basePort + 15), 2);
    OS_OutPortByte((u16)(basePort + 15), 0);
    OS_OutPortByte((u16)(basePort + 19), 6);
    OS_OutPortByte((u16)(basePort + 38), 0x61);
    OS_OutPortByte((u16)(basePort + 34), 0x40);
    OS_InPortByte((u16)(basePort + 55));
    OS_OutPortByte((u16)(basePort + 23), 5);
    value = OS_InPortByte((u16)(basePort + 41));
    return OS_OutPortByte((u16)(basePort + 41), (u8)(value & 0xfe));
}

int autoLoadDefaultMap(u32 basePort)
{
    static const u16 words[] = {
        0x86c0, 0x8620, 0x6800, 0x8600,
        0x8400, 0x8400, 0x8400, 0x8400,
        0x8400, 0x8400, 0x8400, 0x8400,
        0x8400, 0x8400, 0x8400, 0x8400,
        0x4812, 0x2c13, 0x8802, 0x4912, 0x571d, 0x0c02,
        0x2219, 0x4401, 0x571d, 0x0c04, 0x2224, 0x4407,
        0x8801, 0x5524, 0x4400, 0x5725, 0x0c00, 0x2225,
        0x4407, 0x8808, 0x8810, 0x8810, 0x8804, 0x8810,
        0x1307, 0x2100, 0x8810
    };
    u8 value = (u8)OS_InPortByte((u16)(basePort + 41));
    OS_OutPortByte((u16)(basePort + 41), value | 2);
    for (u16 i = 0; i < sizeof(words) / sizeof(words[0]); ++i)
        OS_OutPortWord((u16)(basePort + 128 + 2 * i), words[i]);
    value = (u8)OS_InPortByte((u16)(basePort + 41));
    return OS_OutPortByte((u16)(basePort + 41), value & 0xfd);
}

int scsiXferPad(u32 basePort, u8 cardIndex)
{
    int result;
    u8 phase;
    u8 current;
    OS_OutPortByte((u16)(basePort + 71), 2);
    OS_OutPortByte((u16)(basePort + 71), 0);
    if ((BL_CardFlags[20 * cardIndex] & 0x20) != 0)
        hostDataXferAbort(basePort, cardIndex, BL_Card[cardIndex].currentSCCB);
    result = OS_InPortByte((u16)(basePort + 67));
    if ((result & 0xdf) != 0)
        return result;

    OS_OutPortByte((u16)(basePort + 72), 0);
    phase = (u8)OS_InPortByte((u16)(basePort + 68)) & 7;
    OS_OutPortByte((u16)(basePort + 67), 0x40);
    OS_OutPortByte((u16)(basePort + 68), phase);
    while ((OS_InPortByte((u16)(basePort + 67)) & 0x80) == 0) {
        if ((OS_InPortByte((u16)(basePort + 66)) & 0x80) != 0)
            break;
        current = (u8)OS_InPortByte((u16)(basePort + 68));
        if (phase != (current & 7))
            break;
        if ((current & 1) != 0) {
            OS_OutPortByte((u16)(basePort + 70), 0xc8);
            if ((OS_InPortByte((u16)(basePort + 113)) & 0x40) == 0)
                OS_InPortByte((u16)(basePort + 76));
        } else {
            OS_OutPortByte((u16)(basePort + 70), 0x8c);
            if ((OS_InPortByte((u16)(basePort + 113)) & 0x40) != 0)
                OS_OutPortByte((u16)(basePort + 76), 0xfa);
        }
    }
    while ((OS_InPortByte((u16)(basePort + 67)) & 0x80) == 0 &&
           (OS_InPortByte((u16)(basePort + 66)) & 0x80) == 0 &&
           (OS_InPortByte((u16)(basePort + 68)) & 0x20) == 0)
        ;
    OS_OutPortByte((u16)(basePort + 70), 0xc8);
    while ((OS_InPortByte((u16)(basePort + 113)) & 0x40) == 0)
        OS_InPortByte((u16)(basePort + 76));
    result = OS_InPortByte((u16)(basePort + 67));
    if ((result & 0x80) == 0) {
        result = OS_InPortByte((u16)(basePort + 66));
        if ((result & 0x80) == 0) {
            OS_OutPortByte((u16)(basePort + 100), 0x28);
            while ((OS_InPortByte((u16)(basePort + 67)) & 0x1f) == 0)
                ;
            if ((OS_InPortByte((u16)(basePort + 67)) & 8) != 0 ||
                ((result = OS_InPortByte((u16)(basePort + 67))) & 1) != 0) {
                do {
                    result = OS_InPortByte((u16)(basePort + 67));
                    if ((result & 0x80) != 0)
                        break;
                    result = OS_InPortByte((u16)(basePort + 66));
                } while ((result & 2) == 0);
            }
        }
    }
    return result;
}

int hostDataXferAbort(u32 basePort, u8 cardIndex, struct sccb *sccb)
{
    int remaining;
    u32 index;
    u32 value;
    BL_CardFlags[20 * cardIndex] &= (u8)~0x20;
    if ((sccb->Sccb_XferState & 8) != 0) {
        if ((OS_InPortByte((u16)(basePort + 55)) & 1) == 0) {
            value = (u8)OS_InPortByte((u16)(basePort + 38));
            OS_OutPortByte((u16)(basePort + 38), (u8)value | 2);
            remaining = 0xffff;
            do {
                if ((OS_InPortByte((u16)(basePort + 54)) & 0x80) == 0)
                    break;
            } while (remaining-- != 0);
            value = (u8)OS_InPortByte((u16)(basePort + 38));
            OS_OutPortByte((u16)(basePort + 38), (u8)value & 0xfd);
            if ((OS_InPortByte((u16)(basePort + 54)) & 0x80) != 0) {
                if (busMstrTimeOut(basePort) && sccb->HostStatus == 0)
                    sccb->HostStatus = 48;
                goto check_interrupt_status;
            }
        }
        return OS_OutPortByte((u16)(basePort + 23), 5);
    }

    if (sccb->Sccb_XferCnt != 0) {
        if ((sccb->Sccb_XferState & 4) != 0) {
            value = (u8)OS_InPortByte((u16)(basePort + 41));
            OS_OutPortByte((u16)(basePort + 41), (u8)value & 0xfe);
            OS_OutPortByte((u16)(basePort + 40), 0);
            index = (u32)sccb->Sccb_sgseg + 16;
            if (index > (sccb->DataLength >> 3))
                index = sccb->DataLength >> 3;
            value = sccb->Sccb_XferCnt;
            if (value > 0xffffff)
                goto invalid_sg_rewind;
            do {
                --index;
                if (sccb->SGEntries[index].length >= value)
                    break;
                value -= sccb->SGEntries[index].length;
            } while (value <= 0xffffff);
            if (value > 0xffffff) {
invalid_sg_rewind:
                if (sccb->HostStatus == 0)
                    sccb->HostStatus = 39;
            } else {
                sccb->Sccb_SGoffset = value;
                sccb->Sccb_sgseg = (u16)index;
                if (sccb->DataLength == 8 * index && value == 0)
                    sccb->Sccb_XferState |= 2;
            }
        }
        if ((sccb->Sccb_XferState & 1) != 0) {
            if ((u8)OS_InPortByte((u16)(basePort + 56)) > 0x3f) {
                remaining = 15;
                do {
                    if ((OS_InPortByte((u16)(basePort + 54)) & 0x80) == 0)
                        break;
                    if ((u8)OS_InPortByte((u16)(basePort + 56)) <= 0x3f)
                        break;
                } while (remaining-- != 0);
            }
            if ((OS_InPortByte((u16)(basePort + 54)) & 0x80) != 0) {
                value = (u8)OS_InPortByte((u16)(basePort + 38));
                OS_OutPortByte((u16)(basePort + 38), (u8)value | 2);
                remaining = 0xffff;
                do {
                    if ((OS_InPortByte((u16)(basePort + 54)) & 0x80) == 0)
                        break;
                } while (remaining-- != 0);
                value = (u8)OS_InPortByte((u16)(basePort + 38));
                OS_OutPortByte((u16)(basePort + 38), (u8)value & 0xfd);
                if ((OS_InPortByte((u16)(basePort + 54)) & 0x80) != 0) {
                    if (sccb->HostStatus == 0)
                        sccb->HostStatus = 48;
                    busMstrTimeOut(basePort);
                }
            }
        } else if ((OS_InPortByte((u16)(basePort + 54)) & 0x80) != 0) {
            busMstrTimeOut(basePort);
            return OS_OutPortByte((u16)(basePort + 23), 5);
        }
        goto check_interrupt_status;
    }

    if ((OS_InPortByte((u16)(basePort + 54)) & 0x80) != 0) {
        remaining = 0xffff;
        do {
            if ((OS_InPortByte((u16)(basePort + 54)) & 0x80) == 0)
                break;
        } while (remaining-- != 0);
        if ((OS_InPortByte((u16)(basePort + 54)) & 0x80) != 0) {
            if (sccb->HostStatus == 0)
                sccb->HostStatus = 48;
            busMstrTimeOut(basePort);
        }
    }
check_interrupt_status:
    if ((OS_InPortByte((u16)(basePort + 55)) & 2) != 0 &&
        (OS_InPortByte((u16)(basePort + 54)) & 0x73) != 0 &&
        sccb->HostStatus == 0)
        sccb->HostStatus = 48;
    if ((sccb->Sccb_XferState & 8) != 0)
        return OS_OutPortByte((u16)(basePort + 23), 5);
    if (sccb->Sccb_XferCnt == 0) {
        if ((sccb->Sccb_XferState & 4) != 0) {
            value = (u8)OS_InPortByte((u16)(basePort + 41));
            OS_OutPortByte((u16)(basePort + 41), (u8)value & 0xfe);
            OS_OutPortByte((u16)(basePort + 40), 0);
            sccb->Sccb_sgseg += 16;
            sccb->Sccb_SGoffset = 0;
            if (sccb->DataLength <= 8u * sccb->Sccb_sgseg) {
                sccb->Sccb_XferState |= 2;
                sccb->Sccb_sgseg = (u16)(sccb->DataLength >> 3);
            }
        } else if ((sccb->Sccb_XferState & 8) == 0) {
            sccb->Sccb_XferState |= 2;
        }
    }
    return OS_OutPortByte((u16)(basePort + 23), 5);
}

int phaseDataOut(u32 basePort, u8 cardIndex)
{
    struct sccb_card *card = &BL_Card[cardIndex];
    struct sccb *sccb = card->currentSCCB;
    int result = 5 * cardIndex;
    if (sccb == 0)
        return result;
    sccb->Sccb_scsistat = 7;
    sccb->Sccb_XferState &= 0x7e;
    OS_OutPortByte((u16)(basePort + 70), 0x80);
    OS_OutPortByte((u16)(basePort + 67), 0x40);
    OS_OutPortByte((u16)(basePort + 100), 0xca);
    result = dataXferProcessor(basePort, card);
    if (sccb->Sccb_XferCnt == 0) {
        if ((sccb->ControlByte & 0x10) != 0 && sccb->HostStatus == 0)
            sccb->HostStatus = SCCB_DATA_OVER_RUN;
        scsiXferPad(basePort, cardIndex);
        result = OS_InPortByte((u16)(basePort + 67));
        if ((result & 0x80) == 0) {
            result = OS_InPortByte((u16)(basePort + 66));
            if ((result & 0x80) == 0)
                return phaseDecode(basePort, cardIndex);
        }
    }
    return result;
}

int phaseDataIn(u32 basePort, u8 cardIndex)
{
    struct sccb_card *card = &BL_Card[cardIndex];
    struct sccb *sccb = card->currentSCCB;
    int result = 5 * cardIndex;
    if (sccb == 0)
        return result;
    sccb->Sccb_scsistat = 8;
    sccb->Sccb_XferState |= 1;
    sccb->Sccb_XferState &= 0x7f;
    OS_OutPortByte((u16)(basePort + 70), 0x80);
    OS_OutPortByte((u16)(basePort + 67), 0x40);
    OS_OutPortByte((u16)(basePort + 100), 0xca);
    result = dataXferProcessor(basePort, card);
    if (sccb->Sccb_XferCnt == 0) {
        if ((sccb->ControlByte & 8) != 0 && sccb->HostStatus == 0)
            sccb->HostStatus = SCCB_DATA_OVER_RUN;
        scsiXferPad(basePort, cardIndex);
        result = OS_InPortByte((u16)(basePort + 67));
        if ((result & 0x80) == 0) {
            result = OS_InPortByte((u16)(basePort + 66));
            if ((result & 0x80) == 0)
                return phaseDecode(basePort, cardIndex);
        }
    }
    return result;
}

int phaseCommand(u32 basePort, u8 cardIndex)
{
    struct sccb *sccb = BL_Card[cardIndex].currentSCCB;
    u16 port = (u16)(basePort + 136);
    u8 value;
    u8 i;
    if (sccb->OperationCode == RESET_COMMAND) {
        sccb->HostStatus = SCCB_PHASE_SEQUENCE_FAIL;
        sccb->CdbLength = 6;
    }
    OS_OutPortByte((u16)(basePort + 68), 0);
    value = (u8)OS_InPortByte((u16)(basePort + 41));
    OS_OutPortByte((u16)(basePort + 41), value | 2);
    for (i = 0; i < sccb->CdbLength; ++i) {
        u16 word = sccb->OperationCode == RESET_COMMAND
            ? 0x8400 : (u16)(0x8400 | sccb->Cdb[i]);
        OS_OutPortWord(port, word);
        port += 2;
    }
    if (sccb->CdbLength != 12)
        OS_OutPortWord(port, 0x2010);
    OS_OutPortByte((u16)(basePort + 70), 0x80);
    sccb->Sccb_scsistat = 6;
    OS_OutPortByte((u16)(basePort + 103), 0x22);
    value = (u8)OS_InPortByte((u16)(basePort + 41));
    return OS_OutPortByte((u16)(basePort + 41), value & 0xfd);
}

int phaseIllegal(u32 basePort, u8 cardIndex)
{
    struct sccb *sccb = BL_Card[cardIndex].currentSCCB;
    u8 value = (u8)OS_InPortByte((u16)(basePort + 68));
    OS_OutPortByte((u16)(basePort + 68), value);
    if (sccb != 0) {
        sccb->HostStatus = SCCB_PHASE_SEQUENCE_FAIL;
        sccb->Sccb_scsistat = 11;
        sccb->Sccb_tag = 6;
    }
    while ((OS_InPortByte((u16)(basePort + 68)) & 0x20) != 0)
        ;
    return OS_OutPortByte((u16)(basePort + 68), 0x0a);
}

int phaseChkFifo(u32 basePort, u8 cardIndex)
{
    struct sccb *sccb = BL_Card[cardIndex].currentSCCB;
    u32 remaining;
    if (sccb->Sccb_scsistat == 8) {
        while ((OS_InPortByte((u16)(basePort + 113)) & 0x40) == 0 &&
               (OS_InPortByte((u16)(basePort + 54)) & 0x80) != 0)
            ;
        if ((OS_InPortByte((u16)(basePort + 113)) & 0x40) == 0) {
            sccb->Sccb_ATC += sccb->Sccb_XferCnt;
            sccb->Sccb_XferCnt = 0;
            if ((OS_InPortByte((u16)(basePort + 66)) & 0x20) != 0 &&
                sccb->HostStatus == 0) {
                sccb->HostStatus = SCCB_PARITY_ERR;
                OS_OutPortByte((u16)(basePort + 66), 0x20);
            }
            hostDataXferAbort(basePort, cardIndex, sccb);
            dataXferProcessor(basePort, &BL_Card[cardIndex]);
            while ((OS_InPortByte((u16)(basePort + 113)) & 0x40) == 0 &&
                   (OS_InPortByte((u16)(basePort + 54)) & 0x80) != 0)
                ;
        }
    }
    remaining = OS_InPortLong((u16)(basePort + 72)) & 0x00ffffff;
    OS_OutPortByte((u16)(basePort + 72), 0);
    OS_OutPortByte((u16)(basePort + 70), 0);
    sccb->Sccb_ATC += sccb->Sccb_XferCnt - remaining;
    sccb->Sccb_XferCnt = remaining;
    if ((OS_InPortByte((u16)(basePort + 66)) & 0x20) != 0 &&
        sccb->HostStatus == 0) {
        sccb->HostStatus = SCCB_PARITY_ERR;
        OS_OutPortByte((u16)(basePort + 66), 0x20);
    }
    hostDataXferAbort(basePort, cardIndex, sccb);
    OS_OutPortByte((u16)(basePort + 111), 0);
    OS_OutPortByte((u16)(basePort + 110), 0);
    OS_OutPortByte((u16)(basePort + 113), 0);
    return OS_OutPortByte((u16)(basePort + 67), 0x40);
}

int phaseBusFree(u32 basePort, u8 cardIndex)
{
    struct sccb_card *card = &BL_Card[cardIndex];
    struct sccb *sccb = card->currentSCCB;
    int result = 20 * cardIndex;
    struct sccb_mgr_target *target;
    if (sccb == 0)
        return result;
    OS_OutPortByte((u16)(basePort + 71), 2);
    OS_OutPortByte((u16)(basePort + 71), 0);
    target = &sccbMgrTbl[cardIndex][sccb->TargID];
    if (sccb->OperationCode == RESET_COMMAND) {
        target->selectEligible = 0;
        queueCmdComplete(card, sccb);
        queueSearchSelect(card, cardIndex);
        card->globalFlags |= 0x40;
        return 5 * cardIndex;
    }
    switch (sccb->Sccb_scsistat) {
    case 3:
        target->status |= 0xc0;
        target->eepromValue &= 0xfc;
        card->globalFlags |= 0x40;
        return 5 * cardIndex;
    case 4:
        target->status = (target->status & 0xcf) | 0x20;
        target->eepromValue &= 0x7f;
        card->globalFlags |= 0x40;
        return 5 * cardIndex;
    case 5:
        if ((OS_InPortByte((u16)(basePort + 68)) & 0x40) != 0 &&
            (OS_InPortByte((u16)(basePort + 66)) & 2) == 0)
            return result;
        target->status = (target->status & 0xf3) | 8;
        card->globalFlags |= 0x40;
        return 5 * cardIndex;
    default:
        sccb->Sccb_scsistat = 0;
        if (sccb->HostStatus == 0)
            sccb->HostStatus = SCCB_PHASE_SEQUENCE_FAIL;
        target->selectEligible = 0;
        return queueCmdComplete(card, sccb);
    }
}

int phaseMsgOut(u32 basePort, u8 cardIndex)
{
    struct sccb *sccb = BL_Card[cardIndex].currentSCCB;
    u8 message;
    if (sccb != 0) {
        message = sccb->Sccb_scsimsg;
        if (message == 12) {
            struct sccb_mgr_target *target =
                &sccbMgrTbl[cardIndex][sccb->TargID];
            target->syncValue = 0;
            SccbMgrTableInitTarget(cardIndex, sccb->TargID);
            if ((target->eepromValue & 3) != 0) {
                target->status &= 0x3f;
                scsiSetSyncValue((u16)basePort, sccb->TargID, 16, target);
            }
            if ((signed char)target->eepromValue < 0)
                target->status &= 0xcf;
            queueFlushSccb(cardIndex, 0);
        } else if (sccb->Sccb_scsistat <= 5) {
            sccb->Sccb_MGRFlags += 4;
            scsiSelect(basePort, cardIndex);
        } else if (message == 6) {
            queueFlushSccb(cardIndex, 0);
        }
    } else {
        message = 6;
    }
    OS_OutPortByte((u16)(basePort + 67), 0xe0);
    OS_OutPortByte((u16)(basePort + 70), 2);
    OS_OutPortByte((u16)(basePort + 116), message);
    OS_OutPortByte((u16)(basePort + 68), 0x12);
    while ((OS_InPortByte((u16)(basePort + 68)) & 0x20) != 0)
        ;
    OS_OutPortByte((u16)(basePort + 68), 2);
    OS_OutPortByte((u16)(basePort + 70), 0);
    if (message != 6 && message != 12)
        return scsiXferPad(basePort, cardIndex);
    while ((OS_InPortByte((u16)(basePort + 67)) & 0xa0) == 0)
        ;
    if ((OS_InPortByte((u16)(basePort + 67)) & 0x80) == 0)
        return scsiXferPad(basePort, cardIndex);
    OS_OutPortByte((u16)(basePort + 67), 0x80);
    if (sccb != 0) {
        sccbMgrTbl[cardIndex][sccb->TargID].selectEligible = 0;
        return queueCmdComplete(&BL_Card[cardIndex], sccb);
    }
    BL_CardFlags[20 * cardIndex] |= 0x40;
    return 5 * cardIndex;
}

int phaseMsgIn(u32 basePort, u8 cardIndex)
{
    struct sccb *sccb = BL_Card[cardIndex].currentSCCB;
    int message;
    if ((BL_CardFlags[20 * cardIndex] & 0x20) != 0)
        phaseChkFifo(basePort, cardIndex);
    message = OS_InPortByte((u16)(basePort + 116));
    if (message == 4 || message == 2)
        return OS_OutPortByte((u16)(basePort + 101), 0x2a);
    message = scsiFetchMsg((u16)basePort, sccb);
    if ((u8)message != 0)
        return scsiDecodeMsg((u8)message, basePort, cardIndex);
    return message;
}

int scsiHandleExtMsg(u32 basePort, u8 cardIndex, struct sccb *sccb)
{
    int first = scsiFetchMsg((u16)basePort, sccb);
    int second;
    if ((u8)first == 0)
        return first;
    while ((OS_InPortByte((u16)(basePort + 68)) & 0x20) != 0)
        ;
    OS_OutPortByte((u16)(basePort + 68), 2);
    second = scsiFetchMsg((u16)basePort, sccb);
    if ((u8)second == 0)
        return second;
    if ((u8)second == 1) {
        if ((u8)first == 3) {
            while ((OS_InPortByte((u16)(basePort + 68)) & 0x20) != 0)
                ;
            OS_OutPortByte((u16)(basePort + 68), 2);
            return scsiTargSyncNego(basePort, cardIndex);
        }
        sccb->Sccb_scsimsg = 7;
        while ((OS_InPortByte((u16)(basePort + 68)) & 0x20) != 0)
            ;
        return OS_OutPortByte((u16)(basePort + 68), 0x0a);
    }
    if ((u8)second == 3 && (u8)first == 2) {
        while ((OS_InPortByte((u16)(basePort + 68)) & 0x20) != 0)
            ;
        OS_OutPortByte((u16)(basePort + 68), 2);
        return scsiTargWideNego(basePort, cardIndex);
    }
    sccb->Sccb_scsimsg = 7;
    while ((OS_InPortByte((u16)(basePort + 68)) & 0x20) != 0)
        ;
    OS_OutPortByte((u16)(basePort + 68), 0x0a);
    return OS_OutPortByte((u16)(basePort + 101), 0x28);
}

int scsiDecodeMsg(u8 message, u32 basePort, u8 cardIndex)
{
    struct sccb_card *card = &BL_Card[cardIndex];
    struct sccb *sccb = card->currentSCCB;
    struct sccb_mgr_target *target = &sccbMgrTbl[cardIndex][sccb->TargID];
    if (message == 3) {
        if ((sccb->Sccb_XferState & 0x80) == 0) {
            sccb->Sccb_ATC = sccb->Sccb_savedATC;
            hostDataXferRestart(sccb);
        }
        while ((OS_InPortByte((u16)(basePort + 68)) & 0x20) != 0)
            ;
        OS_OutPortByte((u16)(basePort + 68), 2);
        return OS_OutPortByte((u16)(basePort + 101), 0x28);
    }
    if (message == 0) {
        if (sccb->Sccb_scsistat == 5) {
            target->status &= 0xf3;
            target->status |= 8;
        }
        while ((OS_InPortByte((u16)(basePort + 68)) & 0x20) != 0)
            ;
        return OS_OutPortByte((u16)(basePort + 68), 2);
    }
    if (message == 8 || message > 0x7f) {
        while ((OS_InPortByte((u16)(basePort + 68)) & 0x20) != 0)
            ;
        OS_OutPortByte((u16)(basePort + 68), 2);
        return OS_OutPortByte((u16)(basePort + 101), 0x28);
    }
    if (message == 7) {
        if ((u8)(sccb->Sccb_scsistat - 3) > 1 &&
            (target->status & 0xc0) != 0x40 &&
            (target->status & 0x0c) != 4) {
            while ((OS_InPortByte((u16)(basePort + 68)) & 0x20) != 0)
                ;
            return OS_OutPortByte((u16)(basePort + 68), 2);
        }
        OS_OutPortByte((u16)(basePort + 67), 0x80);
        while ((OS_InPortByte((u16)(basePort + 68)) & 0x20) != 0)
            ;
        OS_OutPortByte((u16)(basePort + 68), 2);
        while ((OS_InPortByte((u16)(basePort + 68)) & 0x20) == 0 &&
               (OS_InPortByte((u16)(basePort + 67)) & 0x80) == 0)
            ;
        if (sccb->Sccb_scsistat == 3) {
            target->status |= 0xc0;
            target->eepromValue &= 0xfc;
        } else if (sccb->Sccb_scsistat == 4) {
            target->status = (target->status & 0xcf) | 0x20;
            target->eepromValue &= 0x7f;
        } else {
            target->status = (target->status & 0xf3) | 8;
            sccb->ControlByte &= (u8)~0x20;
            sccb->Sccb_tag = 0;
        }
        if ((OS_InPortByte((u16)(basePort + 67)) & 0x80) != 0) {
            int result = OS_OutPortByte((u16)(basePort + 67), 0x80);
            card->globalFlags |= 0x40;
            return result;
        }
        target->selectEligible = 1;
        sccb->ControlByte &= (u8)~0x20;
        return OS_OutPortByte((u16)(basePort + 101), 0x28);
    }
    if (message == 1) {
        while ((OS_InPortByte((u16)(basePort + 68)) & 0x20) != 0)
            ;
        OS_OutPortByte((u16)(basePort + 68), 2);
        return scsiHandleExtMsg(basePort, cardIndex, sccb);
    }
    if (message == 0x23) {
        while ((OS_InPortByte((u16)(basePort + 68)) & 0x20) != 0)
            ;
        OS_OutPortByte((u16)(basePort + 68), 2);
        scsiFetchMsg((u16)basePort, sccb);
        while ((OS_InPortByte((u16)(basePort + 68)) & 0x20) != 0)
            ;
        OS_OutPortByte((u16)(basePort + 68), 2);
        return OS_OutPortByte((u16)(basePort + 101), 0x28);
    }
    sccb->HostStatus = SCCB_PHASE_SEQUENCE_FAIL;
    sccb->Sccb_scsistat = 7;
    while ((OS_InPortByte((u16)(basePort + 68)) & 0x20) != 0)
        ;
    OS_OutPortByte((u16)(basePort + 68), 0x0a);
    return OS_OutPortByte((u16)(basePort + 101), 0x28);
}

int scsiChkDmaDone(u32 basePort, u8 cardIndex)
{
    struct sccb *sccb = BL_Card[cardIndex].currentSCCB;
    int result = (signed char)(sccb->Sccb_scsistat - 7);
    if (sccb->Sccb_scsistat != 7 && sccb->Sccb_scsistat != 8)
        return result;
    if ((sccb->Sccb_XferState & 0x10) != 0) {
        sccb->Sccb_ATC += sccb->Sccb_XferCnt - 1;
        sccb->Sccb_XferCnt = 1;
        sccb->Sccb_XferState &= (u8)~0x10;
        OS_OutPortWord((u16)(basePort + 110), 0);
        OS_OutPortByte((u16)(basePort + 113), 0);
    } else {
        sccb->Sccb_ATC += sccb->Sccb_XferCnt;
        sccb->Sccb_XferCnt = 0;
    }
    if ((OS_InPortByte((u16)(basePort + 66)) & 0x20) != 0 &&
        sccb->HostStatus == 0) {
        sccb->HostStatus = SCCB_PARITY_ERR;
        OS_OutPortByte((u16)(basePort + 66), 0x20);
    }
    hostDataXferAbort(basePort, cardIndex, sccb);
    while ((OS_InPortByte((u16)(basePort + 68)) & 0x10) != 0)
        ;
    {
        u16 count = 0;
        u16 previous;
        do {
            if ((OS_InPortByte((u16)(basePort + 113)) & 0x40) == 0)
                break;
            result = (signed char)OS_InPortByte((u16)(basePort + 67));
            if (result < 0)
                return result;
            if ((OS_InPortByte((u16)(basePort + 112)) & 0x1f) != 0)
                break;
            result = (signed char)OS_InPortByte((u16)(basePort + 66));
            if (result < 0)
                return result;
            if ((OS_InPortByte((u16)(basePort + 68)) & 0x20) != 0)
                break;
            previous = count++;
        } while (previous <= 0x1388);
    }
    if ((OS_InPortByte((u16)(basePort + 113)) & 0x40) == 0 ||
        (OS_InPortByte((u16)(basePort + 112)) & 0x1f) != 0 ||
        (u8)OS_InPortByte((u16)(basePort + 68)) == 64 ||
        (u8)OS_InPortByte((u16)(basePort + 68)) == 65) {
        OS_OutPortByte((u16)(basePort + 70), 0x80);
        if ((sccb->Sccb_XferState & 2) != 0) {
            scsiXferPad(basePort, cardIndex);
            result = OS_InPortByte((u16)(basePort + 67));
            if ((result & 0x89) == 0) {
                result = (signed char)OS_InPortByte((u16)(basePort + 66));
                if (result >= 0) {
                    OS_OutPortByte((u16)(basePort + 67), 0x1f);
                    return phaseDecode(basePort, cardIndex);
                }
            }
        } else if ((sccb->Sccb_XferState & 1) != 0) {
            return phaseDataIn(basePort, cardIndex);
        } else {
            return phaseDataOut(basePort, cardIndex);
        }
    } else {
        return OS_OutPortByte((u16)(basePort + 70), 0);
    }
    return result;
}

int scsiInitSyncNego(u32 basePort, u8 cardIndex)
{
    struct sccb *sccb = BL_Card[cardIndex].currentSCCB;
    struct sccb_mgr_target *target = &sccbMgrTbl[cardIndex][sccb->TargID];
    if ((target->status & 0xc0) == 0x40) {
        target->status |= 0xc0;
        target->eepromValue &= 0xfc;
        return 0;
    }
    OS_OutPortWord((u16)(basePort + 128), (u16)(0x8600 | sccb->Sccb_idmsg));
    OS_OutPortWord((u16)(basePort + 130), 0x2004);
    OS_OutPortWord((u16)(basePort + 136), 0x8601);
    OS_OutPortWord((u16)(basePort + 138), 0x8603);
    OS_OutPortWord((u16)(basePort + 140), 0x8601);
    switch (target->eepromValue & 3) {
    case 3: OS_OutPortWord((u16)(basePort + 142), 0x860c); break;
    case 2: OS_OutPortWord((u16)(basePort + 142), 0x8619); break;
    case 1: OS_OutPortWord((u16)(basePort + 142), 0x8632); break;
    default: OS_OutPortWord((u16)(basePort + 142), 0x8600); break;
    }
    OS_OutPortWord((u16)(basePort + 144), 0x6800);
    OS_OutPortWord((u16)(basePort + 146), 0x860f);
    OS_OutPortWord((u16)(basePort + 148), 0x2010);
    OS_OutPortByte((u16)(basePort + 103), 0x54);
    target->status = (target->status & 0x3f) | 0x40;
    return 1;
}

int scsiTargSyncNego(u32 basePort, u8 cardIndex)
{
    struct sccb *sccb = BL_Card[cardIndex].currentSCCB;
    struct sccb_mgr_target *target = &sccbMgrTbl[cardIndex][sccb->TargID];
    u8 period = (u8)scsiFetchMsg((u16)basePort, sccb);
    u8 offset;
    u8 rate = 0;
    int result;
    while ((OS_InPortByte((u16)(basePort + 68)) & 0x20) != 0)
        ;
    OS_OutPortByte((u16)(basePort + 68), 2);
    offset = (u8)scsiFetchMsg((u16)basePort, sccb);
    switch (target->eepromValue & 3) {
    case 3: if (period < 12) period = 12; break;
    case 2: if (period < 25) period = 25; break;
    case 1: if (period < 50) period = 50; break;
    }
    if (offset == 0)
        period = 0;
    if (offset > 15)
        offset = 15;
    if (period > 12) rate = 32;
    if (period > 25) rate = 64;
    if (period > 38) rate = 96;
    if (period > 50) rate = 128;
    if (period > 62) rate = 160;
    if (period > 75) rate = 192;
    if (period > 87) rate = 224;
    if (period > 100) {
        rate = 0;
        offset = 0;
    }
    if ((target->status & 0x10) == 0)
        rate |= 0x10;
    scsiSetSyncValue((u16)basePort, sccb->TargID, (u8)(offset | rate), target);
    if (sccb->Sccb_scsistat == 3) {
        while ((OS_InPortByte((u16)(basePort + 68)) & 0x20) != 0)
            ;
        OS_OutPortByte((u16)(basePort + 68), 2);
        target->status |= 0xc0;
        return OS_OutPortByte((u16)(basePort + 101), 0x28);
    }
    while ((OS_InPortByte((u16)(basePort + 68)) & 0x20) != 0)
        ;
    OS_OutPortByte((u16)(basePort + 68), 0x0a);
    result = scsiInitSyncRespond(basePort, period, offset);
    target->status |= 0xc0;
    return result;
}

int scsiInitSyncRespond(u32 basePort, u8 period, u8 offset)
{
    u8 value = (u8)OS_InPortByte((u16)(basePort + 41));
    OS_OutPortByte((u16)(basePort + 41), value | 2);
    OS_OutPortWord((u16)(basePort + 136), 0x8601);
    OS_OutPortWord((u16)(basePort + 138), 0x8603);
    OS_OutPortWord((u16)(basePort + 140), 0x8601);
    OS_OutPortWord((u16)(basePort + 142), (u16)(0x8600 | period));
    OS_OutPortWord((u16)(basePort + 144), 0x6800);
    OS_OutPortWord((u16)(basePort + 146), (u16)(0x8600 | offset));
    OS_OutPortWord((u16)(basePort + 148), 0x2010);
    value = (u8)OS_InPortByte((u16)(basePort + 41));
    OS_OutPortByte((u16)(basePort + 41), value & 0xfd);
    OS_OutPortByte((u16)(basePort + 70), 0x80);
    OS_OutPortByte((u16)(basePort + 67), 0xff);
    OS_OutPortByte((u16)(basePort + 103), 0x22);
    do {
        value = (u8)OS_InPortByte((u16)(basePort + 67));
    } while ((value & 0x9f) == 0);
    return value;
}

int scsiInitWideNego(u32 basePort, u8 cardIndex)
{
    struct sccb *sccb = BL_Card[cardIndex].currentSCCB;
    struct sccb_mgr_target *target = &sccbMgrTbl[cardIndex][sccb->TargID];
    if ((target->status & 0x30) == 0x20) {
        target->status = (target->status & 0xcf) | 0x20;
        target->eepromValue &= 0x7f;
        return 0;
    }
    OS_OutPortWord((u16)(basePort + 128), (u16)(0x8600 | sccb->Sccb_idmsg));
    OS_OutPortWord((u16)(basePort + 130), 0x2004);
    OS_OutPortWord((u16)(basePort + 136), 0x8601);
    OS_OutPortWord((u16)(basePort + 138), 0x8602);
    OS_OutPortWord((u16)(basePort + 140), 0x8603);
    OS_OutPortWord((u16)(basePort + 142), 0x6800);
    OS_OutPortWord((u16)(basePort + 144), 0x8601);
    OS_OutPortWord((u16)(basePort + 146), 0x2010);
    OS_OutPortByte((u16)(basePort + 103), 0x54);
    target->status = (target->status & 0xcf) | 0x10;
    return 1;
}

int scsiTargWideNego(u32 basePort, u8 cardIndex)
{
    struct sccb *sccb = BL_Card[cardIndex].currentSCCB;
    struct sccb_mgr_target *target = &sccbMgrTbl[cardIndex][sccb->TargID];
    u8 message = (u8)scsiFetchMsg((u16)basePort, sccb);
    u8 value;
    int result;
    if ((signed char)target->eepromValue >= 0)
        message = 0;
    if (message != 0) {
        target->status |= 0x10;
        value = 0;
    } else {
        value = 0x10;
        target->status &= 0xef;
    }
    scsiSetSyncValue((u16)basePort, sccb->TargID, value, target);
    if (sccb->Sccb_scsistat == 4) {
        while ((OS_InPortByte((u16)(basePort + 68)) & 0x20) != 0)
            ;
        OS_OutPortByte((u16)(basePort + 68), 2);
        target->status |= 0x20;
        return OS_OutPortByte((u16)(basePort + 101), 0x28);
    }
    while ((OS_InPortByte((u16)(basePort + 68)) & 0x20) != 0)
        ;
    OS_OutPortByte((u16)(basePort + 68), 0x0a);
    result = scsiInitWideRespond(basePort, (u8)(((signed char)target->eepromValue) < 0));
    target->status |= 0x30;
    return result;
}

int scsiInitWideRespond(u32 basePort, u8 width)
{
    u8 value = (u8)OS_InPortByte((u16)(basePort + 41));
    OS_OutPortByte((u16)(basePort + 41), value | 2);
    OS_OutPortWord((u16)(basePort + 136), 0x8601);
    OS_OutPortWord((u16)(basePort + 138), 0x8602);
    OS_OutPortWord((u16)(basePort + 140), 0x8603);
    OS_OutPortWord((u16)(basePort + 142), 0x6800);
    OS_OutPortWord((u16)(basePort + 146), (u16)(0x8600 | width));
    OS_OutPortWord((u16)(basePort + 148), 0x2010);
    value = (u8)OS_InPortByte((u16)(basePort + 41));
    OS_OutPortByte((u16)(basePort + 41), value & 0xfd);
    OS_OutPortByte((u16)(basePort + 70), 0x80);
    OS_OutPortByte((u16)(basePort + 67), 0xff);
    OS_OutPortByte((u16)(basePort + 103), 0x22);
    do {
        value = (u8)OS_InPortByte((u16)(basePort + 66));
    } while ((value & 0x9f) == 0);
    return value;
}

int autoCmdCmplt(u32 basePort, u8 cardIndex)
{
    struct sccb *sccb = BL_Card[cardIndex].currentSCCB;
    struct sccb_mgr_target *target = &sccbMgrTbl[cardIndex][sccb->TargID];
    u8 status = (u8)OS_InPortByte((u16)(basePort + 104));
    target->opaque0[sccb->Lun] = 0;
    if (status == 0) {
        target->selectEligible = 0;
        return queueCmdComplete(&BL_Card[cardIndex], sccb);
    }
    if (status == 40) {
        target->selectEligible = 1;
        sccb->Sccb_MGRFlags |= 1;
        return queueSelectFail(&BL_Card[cardIndex].currentSCCB, cardIndex);
    }
    if (sccb->Sccb_scsistat == 3) {
        target->status |= 0xc0;
        target->eepromValue &= 0xfc;
        BL_CardFlags[20 * cardIndex] |= 0x40;
        return 5 * cardIndex;
    }
    if (sccb->Sccb_scsistat == 4) {
        target->status = (target->status & 0xcf) | 0x20;
        target->eepromValue &= 0x7f;
        BL_CardFlags[20 * cardIndex] |= 0x40;
        return 5 * cardIndex;
    }
    if ((sccb->Sccb_XferState & 8) != 0) {
        target->selectEligible = 0;
        return queueCmdComplete(&BL_Card[cardIndex], sccb);
    }
    sccb->SccbStatus = 4;
    sccb->TargetStatus = status;
    if (status != 2) {
        target->selectEligible = 0;
        return queueCmdComplete(&BL_Card[cardIndex], sccb);
    }
    target->opaque0[sccb->Lun] = 1;
    if (sccb->CdbLength == 1) {
        target->selectEligible = 0;
        return queueCmdComplete(&BL_Card[cardIndex], sccb);
    }
    if (sccb->CdbLength == 0)
        sccb->CdbLength = 14;
    {
        int result = scsiSenseSetup(&BL_Card[cardIndex].currentSCCB);
        BL_CardFlags[20 * cardIndex] |= 0x40;
        return result;
    }
}
