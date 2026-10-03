/* IDA 9.4 recovered entry points. See reconstruction/interfaces.md for
 * exact source addresses, call edges, calling-convention notes and evidence.
 */
#ifndef _ADAPTEC2940HIM_H
#define _ADAPTEC2940HIM_H

#include "Adaptec2940Types.h"

#ifdef __cplusplus
extern "C" {
#endif

/* 0x1220: _PH_ReadConfigOSM; decompiled prototype. */
int PH_ReadConfigOSM(void);

/* 0x122c: _PH_WriteConfigOSM; decompiled prototype. */
int PH_WriteConfigOSM(void);

/* 0x1238: _PH_GetNumOfBusesOSM; decompiled prototype. */
int PH_GetNumOfBusesOSM(void);

/* 0x231c: _PH_ScbCompleted; decompiled prototype. */
void * PH_ScbCompleted(int);

/* 0x2340: _a2940Timeout; decompiled prototype. */
int a2940Timeout(int);

/* 0x26e0: _PH_EnableInt; decompiled prototype. */
int PH_EnableInt(int);

/* 0x2710: _PH_DisableInt; decompiled prototype. */
int PH_DisableInt(int);

/* 0x273c: _Ph_NonInit; decompiled prototype. */
int Ph_NonInit(int);

/* 0x277c: _PH_Special; decompiled prototype. */
int PH_Special(char, int, int);

/* 0x2984: _Ph_Abort; decompiled prototype. */
void Ph_Abort(void);

/* 0x298c: _Ph_IntSrst; decompiled prototype. */
char Ph_IntSrst(int);

/* 0x2a54: _Ph_ResetChannel; decompiled prototype. */
char Ph_ResetChannel(int);

/* 0x2b34: _Ph_CheckSyncNego; decompiled prototype. */
char Ph_CheckSyncNego(int);

/* 0x2ba0: _Ph_CheckLength; decompiled prototype. */
char Ph_CheckLength(int, short);

/* 0x2c60: _Ph_CdbAbort; decompiled prototype. */
char Ph_CdbAbort(int, int);

/* 0x2d58: _Ph_ResetSCSI; decompiled prototype. */
unsigned char Ph_ResetSCSI(int);

/* 0x2ee4: _Ph_BadSeq; decompiled prototype. */
char Ph_BadSeq(int, int);

/* 0x2f54: _Ph_CheckCondition; decompiled prototype. */
char Ph_CheckCondition(int, short);

/* 0x3080: _Ph_TargetAbort; decompiled prototype. */
int Ph_TargetAbort(int, int, int);

/* 0x31b8: _Ph_SendTrmMsg; stored signature. */
int Ph_SendTrmMsg(unsigned int, unsigned int);

/* 0x31c4: _Ph_TrmCmplt; decompiled prototype. */
int Ph_TrmCmplt(void);

/* 0x31d0: _Ph_BusReset; decompiled prototype. */
void Ph_BusReset(void);

/* 0x31d8: _Ph_SendMsgo; decompiled prototype. */
unsigned char Ph_SendMsgo(unsigned char *a1, int);

/* 0x333c: _Ph_SetNeedNego; decompiled prototype. */
char Ph_SetNeedNego(unsigned char, short);

/* 0x3364: _Ph_Negotiate; decompiled prototype. */
char Ph_Negotiate(int, int);

/* 0x35bc: _Ph_SyncSet; decompiled prototype. */
int Ph_SyncSet(int);

/* 0x3630: _Ph_SyncNego; decompiled prototype. */
unsigned char Ph_SyncNego(int, int);

/* 0x369c: _Ph_ExtMsgi; decompiled prototype. */
char Ph_ExtMsgi(int, int);

/* 0x3b90: _Ph_ExtMsgo; decompiled prototype. */
int Ph_ExtMsgo(int, int);

/* 0x3d4c: _Ph_HandleMsgi; decompiled prototype. */
char Ph_HandleMsgi(int, int);

/* 0x3fe4: _Ph_IntSelto; decompiled prototype. */
char Ph_IntSelto(int, int);

/* 0x4078: _Ph_IntFree; decompiled prototype. */
char Ph_IntFree(int, int);

/* 0x415c: _Ph_ParityError; decompiled prototype. */
unsigned char Ph_ParityError(int, int);

/* 0x418c: _Ph_Wt4Req; decompiled prototype. */
int Ph_Wt4Req(int, short);

/* 0x4224: _Ph_MemorySet; decompiled prototype. */
char Ph_MemorySet(unsigned char *a1, char, int);

/* 0x4258: _Ph_Pause; decompiled prototype. */
unsigned char Ph_Pause(int);

/* 0x4288: _Ph_UnPause; decompiled prototype. */
int Ph_UnPause(int);

/* 0x42a8: _Ph_WriteHcntrl; decompiled prototype. */
unsigned char Ph_WriteHcntrl(short, unsigned char, ...);

/* 0x430c: _Ph_ReadIntstat; decompiled prototype. */
int Ph_ReadIntstat(short);

/* 0x4378: _Ph_Delay; decompiled prototype. */
unsigned char Ph_Delay(int, int);

/* 0x4450: _Ph_ScbRenego; decompiled prototype. */
char Ph_ScbRenego(int, unsigned char);

/* 0x44cc: _Ph_ClearFast20Reg; decompiled prototype. */
unsigned char Ph_ClearFast20Reg(int, int);

/* 0x4550: _Ph_LogFast20Map; decompiled prototype. */
void Ph_LogFast20Map(int, unsigned char *a2);

/* 0x4618: _PH_ScbSend; decompiled prototype. */
char PH_ScbSend(int);

/* 0x46d4: _PH_IntHandler; IDA usercall; rebuilt entry is cdecl. */
int PH_IntHandler(int, int);

/* 0x4ab4: _PH_PollInt; decompiled prototype. */
int PH_PollInt(int);

/* 0x4b10: _PH_RelocatePointers; decompiled prototype. */
int PH_RelocatePointers(int, unsigned short);

/* 0x4b2c: _Ph_ChainAppendEnd; decompiled prototype. */
char Ph_ChainAppendEnd(int, unsigned int *a2);

/* 0x4b7c: _Ph_ChainInsertFront; decompiled prototype. */
void Ph_ChainInsertFront(void);

/* 0x4b84: _Ph_ChainRemove; decompiled prototype. */
int Ph_ChainRemove(int, unsigned int *a2);

/* 0x4bcc: _Ph_ChainPrevious; decompiled prototype. */
int Ph_ChainPrevious(int *a1, int);

/* 0x4c10: _Ph_ScbPrepare; decompiled prototype. */
int Ph_ScbPrepare(int, int *a2);

/* 0x4c5c: _Ph_SendCommand; decompiled prototype. */
int Ph_SendCommand(int **a1, int);

/* 0x4d40: _Ph_TerminateCommand; decompiled prototype. */
void Ph_TerminateCommand(int, char);

/* 0x4df0: _Ph_PostCommand; decompiled prototype. */
void * Ph_PostCommand(int);

/* 0x4e60: _Ph_RemoveAndPostScb; decompiled prototype. */
void * Ph_RemoveAndPostScb(int, int);

/* 0x4e84: _Ph_PostNonActiveScb; decompiled prototype. */
void * Ph_PostNonActiveScb(int, int);

/* 0x4eb0: _Ph_TermPostNonActiveScb; decompiled prototype. */
void * Ph_TermPostNonActiveScb(int);

/* 0x4ed8: _Ph_AbortChannel; decompiled prototype. */
unsigned char Ph_AbortChannel(int, char);

/* 0x4f9c: _Ph_HaHardReset; decompiled prototype. */
unsigned char Ph_HaHardReset(int);

/* 0x50a0: _Ph_SetHaData; decompiled prototype. */
int Ph_SetHaData(int);

/* 0x5100: _Ph_SetScbMark; decompiled prototype. */
int Ph_SetScbMark(int);

/* 0x5124: _Ph_HaSoftReset; decompiled prototype. */
void Ph_HaSoftReset(void);

/* 0x512c: _Ph_BusDeviceReset; decompiled prototype. */
unsigned char Ph_BusDeviceReset(int);

/* 0x52b4: _Ph_SoftReset; decompiled prototype. */
void Ph_SoftReset(void);

/* 0x52bc: _Ph_GetScbStatus; decompiled prototype. */
int Ph_GetScbStatus(int, int);

/* 0x52f4: _Ph_SetMgrStat; decompiled prototype. */
unsigned char Ph_SetMgrStat(unsigned char *a1);

/* 0x5328: _Ph_WriteBiosInfo; decompiled prototype. */
unsigned char Ph_WriteBiosInfo(int, unsigned short, int, unsigned short);

/* 0x53d0: _Ph_ReadBiosInfo; decompiled prototype. */
unsigned char Ph_ReadBiosInfo(int, unsigned short, int, unsigned short);

/* 0x5478: _Ph_OutBuffer; decompiled prototype. */
unsigned char Ph_OutBuffer(short, int, int);

/* 0x54c4: _Ph_InBuffer; decompiled prototype. */
unsigned char Ph_InBuffer(short, int, int);

/* 0x54f4: _Ph_ScbAbort; decompiled prototype. */
char Ph_ScbAbort(int);

/* 0x5584: _SWAPCurrScratchRam; decompiled prototype. */
int SWAPCurrScratchRam(int, char);

/* 0x563c: _Ph_InsertBookmark; decompiled prototype. */
char Ph_InsertBookmark(int);

/* 0x5660: _Ph_RemoveBookmark; decompiled prototype. */
int Ph_RemoveBookmark(int);

/* 0x567c: _Ph_AsynchEvent; decompiled prototype. */
int Ph_AsynchEvent(int, int, int);

/* 0x56b0: _Ph_GetDrvrConfig; decompiled prototype. */
int Ph_GetDrvrConfig(int);

/* 0x56fc: _Ph_InitDrvrHA; decompiled prototype. */
int Ph_InitDrvrHA(int);

/* 0x57b4: _PH_GetBiosInfo; IDA usercall; rebuilt entry is cdecl. */
int PH_GetBiosInfo(int, char, char, unsigned char *a4);

/* 0x59e4: _PH_CalcDataSize; decompiled prototype. */
int PH_CalcDataSize(int, short);

/* 0x59fc: _Ph_CheckBiosPresence; decompiled prototype. */
int Ph_CheckBiosPresence(int);

/* 0x5a28: _Ph_GetOptimaConfig; decompiled prototype. */
int Ph_GetOptimaConfig(int);

/* 0x5a60: _Ph_CalcOptimaSize; decompiled prototype. */
int Ph_CalcOptimaSize(unsigned short);

/* 0x5a8c: _Ph_OptimaEnque; decompiled prototype. */
unsigned char Ph_OptimaEnque(unsigned char, int, short);

/* 0x5af0: _Ph_OptimaEnqueHead; decompiled prototype. */
int Ph_OptimaEnqueHead(unsigned char, int, int);

/* 0x5b24: _Ph_OptimaQHead; decompiled prototype. */
unsigned char Ph_OptimaQHead(char, int, short);

/* 0x5c20: _Ph_OptimaCmdComplete; decompiled prototype. */
int Ph_OptimaCmdComplete(int, unsigned char, int);

/* 0x5dfc: _Ph_OptimaRequestSense; decompiled prototype. */
int Ph_OptimaRequestSense(int, char);

/* 0x5ea8: _Ph_OptimaClearDevQue; decompiled prototype. */
void Ph_OptimaClearDevQue(void);

/* 0x5eb0: _Ph_OptimaIndexClearBusy; decompiled prototype. */
int Ph_OptimaIndexClearBusy(int, unsigned char);

/* 0x5ecc: _Ph_OptimaClearTargetBusy; decompiled prototype. */
int Ph_OptimaClearTargetBusy(int, unsigned char);

/* 0x5ef4: _Ph_OptimaClearChannelBusy; decompiled prototype. */
void Ph_OptimaClearChannelBusy(void);

/* 0x5efc: _Ph_SetOptimaHaData; decompiled prototype. */
int Ph_SetOptimaHaData(int);

/* 0x5fb4: _Ph_SetOptimaScratch; decompiled prototype. */
char Ph_SetOptimaScratch(int);

/* 0x6120: _Ph_ScbPageJustifyQIN; decompiled prototype. */
int Ph_ScbPageJustifyQIN(int);

/* 0x6178: _Ph_OptimaMoreFreeScb; decompiled prototype. */
int Ph_OptimaMoreFreeScb(int, int);

/* 0x61d0: _Ph_OptimaGetFreeScb; decompiled prototype. */
int Ph_OptimaGetFreeScb(int, int);

/* 0x627c: _Ph_OptimaReturnFreeScb; decompiled prototype. */
int Ph_OptimaReturnFreeScb(int, unsigned char);

/* 0x62dc: _Ph_OptimaClearQinFifo; decompiled prototype. */
int Ph_OptimaClearQinFifo(int);

/* 0x6300: _Ph_MovPtrToScratch; decompiled prototype. */
unsigned int Ph_MovPtrToScratch(short, unsigned int, int);

/* 0x6384: _Ph_OptimaLoadFuncPtrs; decompiled prototype. */
unsigned int * Ph_OptimaLoadFuncPtrs(int);

/* 0x640c: _Ph_OptimaAbortActive; decompiled prototype. */
int Ph_OptimaAbortActive(int);

/* 0x6708: _Ph_OptimaEnableNextScbArray; decompiled prototype. */
unsigned char Ph_OptimaEnableNextScbArray(int);

/* 0x673c: _PH_GetNumOfBuses; decompiled prototype. */
int PH_GetNumOfBuses(void);

/* 0x6848: _PH_FindMechanism; decompiled prototype. */
int PH_FindMechanism(void);

/* 0x6880: _PH_FindHA; decompiled prototype. */
int PH_FindHA(short, short);

/* 0x6918: _PH_GetConfig; decompiled prototype. */
unsigned char PH_GetConfig(int);

/* 0x6b1c: _PH_InitHA; decompiled prototype. */
int PH_InitHA(int);

/* 0x6cf4: _Ph_ReadConfig; IDA usercall; rebuilt entry is cdecl. */
int Ph_ReadConfig(int, unsigned char, int, unsigned char, unsigned char, unsigned char);

/* 0x6e44: _Ph_WriteConfig; IDA usercall; rebuilt entry is cdecl. */
int Ph_WriteConfig(int, unsigned char, int, unsigned char, unsigned char, unsigned char, unsigned int);

/* 0x6fb8: _Ph_AccessConfig; decompiled prototype. */
int Ph_AccessConfig(unsigned char);

/* 0x7078: _Ph_AutoTermCable; IDA usercall; rebuilt entry is cdecl. */
int Ph_AutoTermCable(char, int);

/* 0x7170: _Ph_NoAssistTerm; decompiled prototype. */
unsigned char Ph_NoAssistTerm(int);

/* 0x7260: _Ph_RebuildEEControl; decompiled prototype. */
int Ph_RebuildEEControl(int, short);

/* 0x728c: _Ph_ReadEeprom; decompiled prototype. */
int Ph_ReadEeprom(unsigned short *a1, int);

/* 0x752c: _Ph_UpdateEeprom; decompiled prototype. */
int Ph_UpdateEeprom(unsigned short *a1, int, unsigned short);

/* 0x76e0: _Ph_ReadE2Register; decompiled prototype. */
int Ph_ReadE2Register(short, int, int);

/* 0x77d0: _Ph_WriteE2Register; decompiled prototype. */
int Ph_WriteE2Register(short, int, int, short);

/* 0x7960: _Ph_EnableEraseWriteEE; decompiled prototype. */
int Ph_EnableEraseWriteEE(int, int);

/* 0x79e4: _Ph_DisableEraseWriteEE; decompiled prototype. */
int Ph_DisableEraseWriteEE(int, int);

/* 0x7a60: _Ph_SendStartBitEE; decompiled prototype. */
int Ph_SendStartBitEE(short);

/* 0x7ac0: _Ph_SendAddressEE; decompiled prototype. */
short Ph_SendAddressEE(short, int, short);

/* 0x7b78: _Ph_Wait2usec; decompiled prototype. */
unsigned char Ph_Wait2usec(unsigned char, short);

/* 0x7ba8: _Ph_LoadSequencer; host block uses byte offsets from Types.h. */
extern unsigned char P_Seq_01[A2940_SEQ_IMAGE_SIZE];
extern unsigned char P_SeqExist[A2940_SEQ_PRESENCE_SIZE];
int Ph_LoadSequencer(Adaptec2940HostInfo *host);

/* 0x7d20: _Ph_ReadCableStatus; decompiled prototype. */
int Ph_ReadCableStatus(int);

#ifdef __cplusplus
}
#endif

#endif /* _ADAPTEC2940HIM_H */
