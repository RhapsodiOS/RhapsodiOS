/*	NSDebug.h
	Debug utilities - do not depend on this in production code
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

/**************************************************************************
WARNING: Unsupported API.

This module contains material that is only partially supported -- if
at all.  Do not depend on the existance of any of these symbols in your
code in future releases of this software.  Certainly, do not depend on
the symbols in this header in production code.  The format of any data
produced by the functions in this header may also change at any time.

However, it should be noted that the features (but not necessarily the
exact implementation) in this file have been found to be generally useful,
and in some cases invaluable, and are not likely to go away anytime soon.
**************************************************************************/

#import <Foundation/NSObject.h>
#import <Foundation/NSAutoreleasePool.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSPort.h>

/* The environment component of this API

The boolean- and integer-valued variables declared in this header,
plus some values set by methods, read starting values from the
process's environment at process startup.  This is mostly a benefit
if you need to initialize these variables to some non-default value
before your program's main() routine gets control, but it also
allows you to change the value without modifying your program's
source. (Variables can be set and methods called around specific
areas within a program, too, of course.)

This opens the door to various possibilites, such as a
statistics-gathering application which spawns off the process to
be measured, providing a custom environment.  The parent process
could then read the output of the statistics from the file
descriptor it had opened, and specified in the environment.

In sh/ksh/zsh or other sh-influenced shell, you can set the value in
the environment like this:
% export NSKeepAllocationStatistics=YES
% myProg

or for just that process:
% NSKeepAllocationStatistics=YES myProg

In a csh/tcsh or other csh-influenced shell, you do this:
> setenv NSKeepAllocationStatistics YES
> myProg


The initialization from the environment happens very early, but may
not have happened yet at the time of a +load method statically linked
into an application (as opposed to one in a dynamically loaded module). 
But as noted in the "Foundation Release Notes", +load methods that are
statically linked into an application are tricky to use and are not
recommended.

Here is a table of the variables/values initialized from the environment
at startup.  Some of these just set variables, others call methods to
set the values.

NAME OF ENV. VARIABLE		       DEFAULT	SET TO...
NSDebugEnabled				  NO	"YES"
NSZombieEnabled				  NO	"YES"
NSDeallocateZombies			  NO	"YES"
NSHangOnMallocError			  NO	"YES"
NSHangOnUncaughtException		  NO	"YES"

NSNegativeRetainCheckEnabled		  NO	"YES"

NSEnableAutoreleasePool			 YES	"NO"
NSAutoreleaseFreedObjectCheckEnabled	  NO	"YES"
NSAutoreleaseHighWaterMark		  0	non-negative integer
NSAutoreleaseHighWaterResolution	  0	non-negative integer

NSKeepAllocationStatistics		  NO	"YES"
NSAllocationStatisticsOutputMask     0xFFFFFFFF	32-bit decimal, hex, or octal number

*/

/****************	General		****************/

FOUNDATION_EXPORT BOOL NSDebugEnabled;
	// General-purpose global boolean. Applications and frameworks
	// may choose to do some extra checking, or use different
	// algorithms, or log informational messages, or whatever, if
	// this variable is true (ex: if (NSDebugEnabled) { ... }).

FOUNDATION_EXPORT BOOL NSZombieEnabled;
	// Enable object zombies. When an object is deallocated, its isa
	// pointer is modified to be that of a "zombie" class (whether or
	// not the storage is then freed can be controlled by the
	// NSDeallocateZombies variable). Messages sent to the zombie
	// object cause logged messages and can be broken on in a debugger.
	// The default is NO.

FOUNDATION_EXPORT BOOL NSDeallocateZombies;
	// Determines whether the storage of objects that have been
	// "zombified" is then freed or not. The default value (NO)
	// is most suitable for debugging messages sent to zombie
	// objects. And since the memory is never freed, storage
	// allocated to an object will never be reused, either (which
	// is sometimes useful otherwise).

FOUNDATION_EXPORT BOOL NSHangOnMallocError;
	// MACH only: Cause the process to hang after printing out the
	// "Malloc-related error detected with code N" message to stderr.
	// A backtrace can be gotten from the process with the 'sample'
	// utility, or the process can be attached to with a debugger.
	// The default is NO. Has no effect on non-MACH platforms.

FOUNDATION_EXPORT BOOL NSHangOnUncaughtException;
	// If set to YES, causes the process to hang after logging the
	// "*** Uncaught exception:" message. A backtrace can be gotten
	// from the process with the 'sample' utility, or the process can
	// be attached to with a debugger. The default is NO.

FOUNDATION_EXPORT BOOL NSIsFreedObject(id anObject);
	// Returns YES if the value passed as the parameter is a pointer
	// to a freed object. Note that memory allocation packages will
	// eventually reuse freed memory blocks to satisfy a request.
	// NSZombieEnabled and NSDeallocateZombies can be used to prevent
	// reuse of allocated objects.

/****************	Retain count monitoring		****************/

FOUNDATION_EXPORT BOOL NSNegativeRetainCheckEnabled;

FOUNDATION_EXPORT void _NSNegativeRetain(void *object, int virtual_retains);
	// Called when an object being autoreleased or released is
	// about to have less than zero virtual retains. The virtual
	// retain count is the number of real retains on the object
	// minus the number of times the object occurs in all autorelease
	// pools in all threads. This check is enabled by setting the
	// environment variable "NSNegativeRetainCheckEnabled" as
	// explained above, or by setting NSNegativeRetainCheckEnabled
	// flag to YES. This uses the allocation statistics facility
	// described above, and so requires NSKeepAllocationStatistics
	// to be YES. Note that this facility does not indicate which
	// autorelease or release of the object is extraneous; it is
	// not necessarily the one which makes the virtual retain count
	// negative, nor one that occurs while the virtual retain count
	// is negative. Note also that an extraneous release may cause
	// an object to be deallocated without its virtual retain count
	// becoming negative.

/****************	Stack processing	****************/

FOUNDATION_EXPORT void *NSFrameAddress(unsigned frame);
FOUNDATION_EXPORT void *NSReturnAddress(unsigned frame);
	// Returns the value of the frame pointer or return address,
	// respectively, of the specified frame. Frames are numbered
	// sequentially, with the "current" frame being zero, the
	// previous frame being 1, etc. The current frame is the
	// frame in which either of these functions is called. For
	// example, NSReturnAddress(0) returns an address near where
	// this function was called, NSReturnAddress(1) returns the
	// address to which control will return when current frame
	// exits, etc. If the requested frame does not exist, then
	// NULL is returned. The behavior of these functions is
	// undefined in the presence of code which has been compiled
	// without frame pointers.

FOUNDATION_EXPORT unsigned NSCountFrames(void);
	// Returns the number of call frames on the stack. The behavior
	// of this functions is undefined in the presence of code which
	// has been compiled without frame pointers.

/****************	Autorelease pool debugging	****************/

@interface NSAutoreleasePool (NSAutoreleasePoolDebugging)

// Functions used as interesting breakpoints in a debugger
FOUNDATION_EXPORT void _NSAutoreleaseNoPool(void *object);
	// Called to log the "Object X of class Y autoreleased with no
	// pool in place - just leaking" message.

FOUNDATION_EXPORT void _NSAutoreleaseFreedObject(void *freedObject);
	// Called when a previously freed object would be released
	// by an autorelease pool. See +enableFreedObjectCheck: below.

FOUNDATION_EXPORT void _NSAutoreleaseHighWaterLog(unsigned int count);
	// Called whenever a high water mark is reached by a pool.
	// See +setPoolCountHighWaterMark: below.

+ (void)enableRelease:(BOOL)enable;
	// Enables or disables autorelease pools; that is, whether or
	// not the autorelease pools send the -release message to their
	// objects when each pool is released. This message affects only
	// the pools of the autorelease pool stack of the current thread
	// (and any future pools in that thread). The "default default"
	// value can be set in the initial environment when a program
	// is launched with the NSEnableAutoreleasePool environment
	// variable (see notes at the top of this file) -- as thread
	// pool-stacks are created, they take their initial enabled
	// state from that environment variable.

+ (void)showPools;
	// Displays to stderr the state of the current thread's
	// autorelease pool stack.

+ (void)resetTotalAutoreleasedObjects;
+ (unsigned)totalAutoreleasedObjects;
	// Returns the number of objects autoreleased (in ALL threads,
	// currently) since the counter was last reset to zero with
	// +resetTotalAutoreleasedObjects.

+ (void)enableFreedObjectCheck:(BOOL)enable;
	// Enables or disables freed-object checking for the pool stack
	// of the current thread (and any future pools in that thread).
	// When enabled, an autorelease pool will call the function
	// _NSAutoreleaseFreedObject() when it is about to attempt to
	// release an object that the runtime has marked as freed (and
	// then it doesn't attempt to send -release to the freed storage).
	// The pointer to the freed storage is passed to that function.
	// The "default default" value can be set in the initial
	// environment when a program is launched with the
	// NSAutoreleaseFreedObjectCheckEnabled environment variable
	// (see notes at the top of this file) -- as thread pool-stacks
	// are created, they take their initial freed-object-check state
	// from that environment variable.

+ (unsigned int)autoreleasedObjectCount;
	// Returns the total number of autoreleased objects in all pools
	// in the current thread's pool stack.

+ (unsigned int)topAutoreleasePoolCount;
	// Returns the number of autoreleased objects in top pool of
	// the current thread's pool stack.

+ (unsigned int)poolCountHighWaterMark;
+ (void)setPoolCountHighWaterMark:(unsigned int)count;
	// Sets the pool count high water mark for the pool stack of
	// the current thread (and any future pools in that thread). When
	// 'count' objects have accumulated in the top autorelease pool,
	// the pool will call _NSAutoreleaseHighWaterLog(), which
	// generates a message to stderr. The number of objects in the
	// top pool is passed as the parameter to that function. The
	// default high water mark is 0, which disables pool count
	// monitoring. The "default default" value can be set in the
	// initial environment when a program is launched with the
	// NSAutoreleaseHighWaterMark environment variable (see notes at
	// the top of this file) -- as thread pool-stacks are created,
	// they take their initial high water mark value from that
	// environment variable. See also +setPoolCountHighWaterResolution:.

+ (unsigned int)poolCountHighWaterResolution;
+ (void)setPoolCountHighWaterResolution:(unsigned int)res;
	// Sets the pool count high water resolution for the pool stack of
	// the current thread (and any future pools in that thread). A
	// call to _NSAutoreleaseHighWaterLog() is generated every multiple
	// of 'res' objects above the high water mark. If 'res' is zero
	// (the default), only one call to _NSAutoreleaseHighWaterLog() is
	// made, when the high water mark is reached. The "default default"
	// value can be set in the initial environment when a program is
	// launched with the NSAutoreleaseHighWaterResolution environment
	// variable (see notes at the top of this file) -- as thread
	// pool-stacks are created, they take their initial high water
	// resolution value from that environment variable. See also
	// +setPoolCountHighWaterMark:.

@end

/****************	Allocation statistics	****************/

// The statistics-keeping facilities generate output on various types of
// events. Currently, output logs can be generated for use of the zone
// allocation functions (NSZoneMalloc(), etc.), and allocation and
// deallocation of objects (and other types of lifetime-related events).

FOUNDATION_EXPORT BOOL NSKeepAllocationStatistics;
	// Default is NO.

FOUNDATION_EXPORT unsigned int NSAllocationStatisticsOutputMask;
	// Bit-mask enabling recording of particular allocation events.
	// See the "mask" defines below. The default value is 0xFFFFFFFF.

// Object allocation event types
#define NSObjectAllocatedEvent			0
#define NSObjectDeallocatedEvent		1
#define NSObjectCopiedEvent			2
#define NSObjectAutoreleasedEvent		3
#define NSObjectExtraRefIncrementedEvent	4
#define NSObjectExtraRefDecrementedEvent	5
#define NSObjectInternalRefIncrementedEvent	6
#define NSObjectInternalRefDecrementedEvent	7
#define NSObjectPoolDeallocStartedEvent		8
#define NSObjectPoolDeallocFinishedEvent	9
#define NSJavaObjectAllocatedEvent		10
#define NSJavaObjectFinalizedEvent		11

// Object allocation event masks
#define NSObjectAllocatedEventMask		(1 << 0)
#define NSObjectDeallocatedEventMask		(1 << 1)
#define NSObjectCopiedEventMask			(1 << 2)
#define NSObjectAutoreleasedEventMask		(1 << 3)
#define NSObjectExtraRefIncrementedEventMask	(1 << 4)
#define NSObjectExtraRefDecrementedEventMask	(1 << 5)
#define NSObjectInternalRefIncrementedEventMask	(1 << 6)
#define NSObjectInternalRefDecrementedEventMask	(1 << 7)
#define NSObjectPoolDeallocStartedEventMask	(1 << 8)
#define NSObjectPoolDeallocFinishedEventMask	(1 << 9)
#define NSJavaObjectAllocatedEventMask		(1 << 10)
#define NSJavaObjectFinalizedEventMask		(1 << 11)

// Zone allocation event types
#define NSZoneMallocEvent			16
#define NSZoneCallocEvent			17
#define NSZoneReallocEvent			18
#define NSZoneFreeEvent				19
#define NSVMAllocateEvent			20
#define NSVMDeallocateEvent			21
#define NSVMCopyEvent				22
#define NSZoneCreatedEvent			23
#define NSZoneRecycledEvent			24

// Zone allocation event masks
#define NSZoneMallocEventMask			(1 << 16)
#define NSZoneCallocEventMask			(1 << 17)
#define NSZoneReallocEventMask			(1 << 18)
#define NSZoneFreeEventMask			(1 << 19)
#define NSVMAllocateEventMask			(1 << 20)
#define NSVMDeallocateEventMask			(1 << 21)
#define NSVMCopyEventMask			(1 << 22)
#define NSZoneCreatedEventMask			(1 << 23)
#define NSZoneRecycledEventMask			(1 << 24)

FOUNDATION_EXPORT void NSRecordAllocationEvent(int eventType, ...);
	// Notes an object or zone allocation event and various other
	// statistics, such as the time and current thread. The additional
	// arguments to be passed to this function vary by the type of
	// event. The behavior is undefined (and likely catastrophic) if
	// the correct arguments for 'eventType' are not provided.
	// This function is usually called within an if statement that
	// checks NSKeepAllocationStatistics, like:
	//	if (NSKeepAllocationStatistics)
	//	    NSRecordAllocationEvent(NSObjectAllocatedEvent, ...);
	// However, NSRecordAllocationEvent() can be called any time,
	// and it does not check NSKeepAllocationStatistics itself.
	//
	// The parameter prototypes for each event type are shown below.
	//   NSRecordAllocationEvent(NSObjectAllocatedEvent, newObj, numExtraBytes)
	//   NSRecordAllocationEvent(NSObjectDeallocatedEvent, curObj)
	//   NSRecordAllocationEvent(NSObjectCopiedEvent, curObj, numExtraBytes, newObj)
	//   NSRecordAllocationEvent(NSObjectAutoreleasedEvent, curObj)
	//   NSRecordAllocationEvent(NSObjectExtraRefIncrementedEvent, curObj)
	//   NSRecordAllocationEvent(NSObjectExtraRefDecrementedEvent, curObj)
	//   NSRecordAllocationEvent(NSObjectInternalRefIncrementedEvent, curObj)
	//   NSRecordAllocationEvent(NSObjectInternalRefDecrementedEvent, curObj)
	//   NSRecordAllocationEvent(NSObjectPoolDeallocStartedEvent)
	//   NSRecordAllocationEvent(NSObjectPoolDeallocFinishedEvent)
	//   NSRecordAllocationEvent(NSJavaObjectAllocatedEvent, newJavaObj, size, className, javaStackTrace)
	//   NSRecordAllocationEvent(NSJavaObjectFinalizedEvent, curJavaObj, className, javaStackTrace)
	//   NSRecordAllocationEvent(NSZoneMallocEvent, newPtr, size)
	//   NSRecordAllocationEvent(NSZoneCallocEvent, newPtr, size)
	//   NSRecordAllocationEvent(NSZoneReallocEvent, currentPtr, newSize, newPtr)
	//   NSRecordAllocationEvent(NSZoneFreeEvent, currentPtr)
	//   NSRecordAllocationEvent(NSVMAllocateEvent, newPtr, size)
	//   NSRecordAllocationEvent(NSVMDeallocateEvent, currentPtr, size)
	//   NSRecordAllocationEvent(NSVMCopyEvent, currentPtr, size, newPtr)
	//   NSRecordAllocationEvent(NSZoneCreatedEvent, zone, startSize, gran)
	//   NSRecordAllocationEvent(NSZoneRecycledEvent, zone)
	//
	// Only the Foundation should have reason to use many of these.
	// Do not call NSRecordAllocationEvent(NSZoneMallocEvent, ...)
	// after NSZoneMalloc(), for example, in your own code because
	// NSZoneMalloc() has already done this for you. The only common
	// use of this function should be with these two events:
	//	NSObjectInternalRefIncrementedEvent
	//	NSObjectInternalRefDecrementedEvent
	// when a class overrides -retain and -release to do its own
	// reference counting.
	//
	// The allocation record is packaged into a message and sent to a
	// Mach port. A monitoring program needs to register a port on the
	// local machine with some name, and then the program to be
	// monitored needs to be started with its environment set up to
	// start allocation statistics and specify the name of the port
	// to which it should send the messages. The monitoring program
	// then uses the two functions NSWaitForAllocationEvent() and
	// NSParseAllocationEvent() to receive and parse event messages.
	//
	// A port is registered with a name something like this code:
	//   eventPort = [[NSPort alloc] init];
	//   if (![[NSPortNameServer defaultPortNameServer]
	//	      registerPort:eventPort name:@"Froboz-stats-port"]) {
	//	[eventPort release];
	//	eventPort = nil;
	//   }
	// Note that the port name should not simply be the name of the
	// monitoring program, as that is used for other purposes. The
	// port name should not contain the commercial-at ("@"), colon
	// (":"), period ("."), or slash ("\", "/") characters; these
	// characters are reserved for the future use of the allocation
	// event subsystem. Also, the name should only contain printing
	// ASCII characters, for maximum portability.
	//
	// The program to be monitored must be (or have been) launched with
	// the variable "NSAllocationStatisticsOutputPortName" set in its
	// environment. The Foundation will lookup the port specified by
	// that name when it first needs it. Alternatively, you can arrange
	// for the program to be monitored to set this port itself with the
	// NSSetAllocationStatisticsOutputPort() function, which can be
	// done at any time, but only affects the destination of allocation
	// events that occur after it is called. If the environment variable
	// "NSAllocationStatisticsOutputPortName" is not set, events will be
	// discarded until NSSetAllocationStatisticsOutputPort() is called.
	//
	// The monitoring process then waits for messages to come from the
	// event port it registered with NSWaitForAllocationEvent(), and
	// parses the raw messages with NSParseAllocationEvent().

FOUNDATION_EXPORT NSPort *NSGetAllocationStatisticsOutputPort(void);
FOUNDATION_EXPORT void NSSetAllocationStatisticsOutputPort(NSPort *port);
	// Get and set the port to which allocation event messages are
	// sent. These functions are called in the process to be monitored.
	// Note that if NSKeepAllocationStatistics is on, but no thread
	// or process is removing the messages sent to this port from the
	// port's queue, the current process may be blocked from execution.

typedef struct {	// This is structure version 0
    unsigned long	struct_version;	// structure version number
    unsigned long	seqno;	// event sequence number
    unsigned long	type;	// type of event
    NSTimeInterval	time;	// time event occurred
    unsigned long long	thread;	// identifier for event's thread
    unsigned long long	zone;	// identifier for event's zone
    unsigned long long	ptr;	// pointer involved in event
    unsigned long long	data;	// extra information for some events
    unsigned long	size;	// size of allocation for some events
    unsigned char	cls[128];  // class name of object if appropriate
} NSAllocationEvent0;

FOUNDATION_EXPORT BOOL NSWaitForAllocationEvent(NSPort *eventPort, void **message, NSTimeInterval timeout);
	// Blocks the calling thread waiting for a message on the specified
	// event port, which has been registered and to which event messages
	// are going to be sent, as described above. In *message, pass in a
	// pointer allocated with NSZoneMalloc(); it will be reallocated
	// larger as necessary. message and *message may not be NULL.

FOUNDATION_EXPORT void NSParseAllocationEvent(void *message, void *alloc_event, unsigned long long **backtrace, unsigned long *num_backtrace);
	// Parses a raw allocation event message returned by
	// NSWaitForAllocationEvent(). The second parameter is a pointer
	// to a flavor of NSAllocationEvent struct type, as defined above.
	// The first field of this structure must be initialized with the
	// version of the structure. In *backtrace, pass in a pointer
	// allocated with NSZoneMalloc(); it will be reallocated larger as
	// necessary. alloc_event, backtrace, and num_backtrace may each
	// be NULL if the value returned by reference for that parameter
	// is not interesting.

