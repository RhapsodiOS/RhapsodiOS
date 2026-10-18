#ifndef SCREAMER_ADAPTER_SHIM_H
#define SCREAMER_ADAPTER_SHIM_H
#import <objc/Object.h>
#import <driverkit/NXSoundParameterTags.h>
#include <stdarg.h>
#include <machdep/ppc/DeviceTree.h>
typedef unsigned long UInt32;
typedef unsigned long ByteCount;
#define IO_R_SUCCESS 0
#define kReferenceProperty 0x00010000UL
#define IO_R_INVALID_ARG 1
#define IO_R_IO 2
enum {PM_READY,PM_STANDBY,PM_SUSPENDED,PM_OFF};
enum {PM_DISABLED,PM_ENABLED};
#define IPLDEVICE 7
#define IO_DEVICE_INTERRUPT_MSG 100
void IOSendInterrupt(void *,void *,unsigned int);
typedef unsigned int IOReturn;
typedef unsigned int PMPowerState;
typedef unsigned int PMPowerManagementState;
typedef void *IODMABuffer;
typedef void (*IOInterruptHandler)(void);
typedef void (*IOAudioInterruptClearFunc)(void);
enum {NX_SoundDeviceLineOut=25,NX_SoundDeviceSpeakerOut,NX_SoundDeviceCDOut,
    NX_SoundDeviceAux1Out,NX_SoundDeviceAux2Out,NX_SoundDeviceMicIn,
    NX_SoundDeviceLineIn,NX_SoundDeviceCDIn,NX_SoundDeviceAux1In,NX_SoundDeviceAux2In};
@protocol IOPower
@end
@interface IODeviceDescription : Object
@end
@interface IOAudio : Object
{ id input,output; unsigned int rate; }
- init;
- _inputChannel;
- _outputChannel;
- (unsigned int)sampleRate;
- (void)_setSampleRate:(unsigned int)v;
- (void)_setDataEncoding:(unsigned int)v;
- (void)_setChannelCount:(unsigned int)v;
- (BOOL)_setParameter:(NXSoundParameterTag)t toInt:(int)v forObject:(id)o;
- (BOOL)_attemptToStopDMAForChannel:(id)channel;
- (BOOL)_attemptToStartDMAForChannel:(id)channel channelStatus:(BOOL)active;
- (int)_intValueForParameter:(NXSoundParameterTag)t forObject:(id)o;
- (void)_getSupportedParameters:(NXSoundParameterTag *)p count:(unsigned int *)n forObject:(id)o;
- (BOOL)_getValues:(NXSoundParameterTag *)p count:(unsigned int *)n forParameter:(NXSoundParameterTag)t forObject:(id)o;
@end
@interface TestStream : Object { unsigned int rate; }
- (unsigned int)samplingRate;
- (void)setSamplingRate:(unsigned int)v;
@end
@interface TestLock : Object { unsigned int held; }
- lock;
- unlock;
- (void)acquire;
- (void)release;
@end
@interface IOTreeDevice : Object
{ @public void *fixture; unsigned int node; id parent; }
+ findForIndex:(UInt32)index;
- parent;
- getRef;
- propertyTable;
- getDevicePath:(char *)path maxLength:(int)length useAlias:(BOOL)alias;
- (IOReturn)getProperty:(const char *)name flags:(unsigned long)flags value:(void **)value length:(ByteCount *)length;
@end
#endif
