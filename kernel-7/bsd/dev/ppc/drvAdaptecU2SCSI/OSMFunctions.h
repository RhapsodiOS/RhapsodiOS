#ifndef _DRVADAPTECU2SCSI_OSMFUNCTIONS_H_
#define _DRVADAPTECU2SCSI_OSMFUNCTIONS_H_

#import <kern/thread_call.h>
#import <mach/mach_types.h>

#ifdef __cplusplus
extern "C" {
#endif

void *AdptMallocContiguous(unsigned int size);
void AdptFreeContiguous(void *addr, unsigned int size);

void *_allocOSMIOB(void *p1, void *p2, void *p3, void *p4,
                   void *p5, void *p6, void *p7, void *p8);
void *_AllocOSMIOB(void *adapter);
void _freeOSMIOB(void *iobPtr, void *p1, void *p2, void *p3,
                 void *p4, void *p5, void *p6, void *p7);
void _FreeOSMIOB(void *adapter, void *iob);
void _CleanupWaitingQ(void *targetStruct);
void _EnqueueOsmIOB(void *iob, void *targetStruct);

int ProbeTarget(void *adapter, void *request);
int NormalPostRoutine(void *iob);

void AU2Handler(int interruptType, void *state, void *context);
void AdaptecU2SCSIIOThread(thread_call_spec_t spec, thread_call_t call);

extern void *OSMRoutines[31];

#ifdef __cplusplus
}
#endif

#endif /* _DRVADAPTECU2SCSI_OSMFUNCTIONS_H_ */

