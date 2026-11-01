#ifndef _ADAPTECU2_SCSI_PRIVATE_H_
#define _ADAPTECU2_SCSI_PRIVATE_H_

#import "AdaptecU2SCSI.h"
#include "AdaptecU2CHIMPrivate.h"

typedef struct AdaptecU2OSMIOB AdaptecU2OSMIOB;
struct AdaptecU2AttachedTarget {
    AdaptecU2SCSI *controller;
    AdaptecU2TargetTSCB *targetTSH;
    AdaptecU2TargetTSCB *storage;
    unsigned int size;
    AdaptecU2TargetProfile profile;
    queue_head_t waiting;
    queue_head_t active;
};

struct AdaptecU2OSMIOB {
    AdaptecU2IOB iob;
    unsigned char *reserveAllocation;
    union {
        AdaptecU2SCSI *controller;
        AdaptecU2AttachedTarget *target;
    } owner;
    AdaptecU2SGElement *sgAllocation;
    unsigned int retryCount;
    unsigned int timestamp[2];
    int interruptPort;
    AdaptecU2TransportSpecific transport;
    unsigned char transportReserved[8];
    unsigned char sense[28];
    queue_chain_t link;
};

typedef struct {
    AdaptecU2SCSI *controller;
    queue_chain_t link;
} AdaptecU2AdapterQueueEntry;
extern queue_head_t adapterQ[64];

/* Names retain the seven address identities from the frozen inventory. */
unsigned short sub_189120(unsigned short value);
unsigned int sub_18914C(unsigned int value);
unsigned short sub_189174(unsigned short value);
unsigned int sub_18918C(unsigned int value);
unsigned short sub_1891A0(unsigned short value);
unsigned int sub_1891B0(unsigned int value);
void sub_18B2A8(thread_call_spec_t context, thread_call_t call);

AdaptecU2OSMIOB *_allocOSMIOB(AdaptecU2AdapterProfile profile);
void _freeOSMIOB(AdaptecU2OSMIOB *iob, AdaptecU2AdapterProfile profile);
AdaptecU2OSMIOB *AllocOSMIOB(AdaptecU2SCSI *controller);
void FreeOSMIOB(AdaptecU2SCSI *controller, AdaptecU2OSMIOB *iob);
void SendIOBsMaybe(AdaptecU2AttachedTarget *target);
void EnqueueOsmIOB(AdaptecU2OSMIOB *iob, AdaptecU2AttachedTarget *target);
void HandleHIMFrozen(AdaptecU2OSMIOB *iob);
void ResetSCSIBus(AdaptecU2SCSI *controller, AdaptecU2Command *command);
unsigned int ProbeTarget(AdaptecU2SCSI *controller, AdaptecU2Command *command);
void ValidateTargets(AdaptecU2OSMIOB *iob);
void CleanupWaitingQ(AdaptecU2AttachedTarget *target);
unsigned int NormalPostRoutine(AdaptecU2IOB *iob);
unsigned int PostUnfreezeHIMQueue(AdaptecU2IOB *iob);
unsigned int PostProtocolAutoConfig(AdaptecU2IOB *iob);
unsigned int PostRoutineResetHW(AdaptecU2IOB *iob);
unsigned int PostRoutineEventResetHW(AdaptecU2IOB *iob);
unsigned int PostRoutineEventPAC(AdaptecU2IOB *iob);
unsigned int PostProbe(AdaptecU2IOB *iob);
void AdaptecU2SCSITimeout(void *iob);

#endif
