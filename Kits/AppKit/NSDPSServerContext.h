/*
    NSDPSServerContext.h

    A DPSContext Object that talks to the NeXT Window Server
    Copyright (c) 1994-1997, Apple Computer, Inc.
    All rights reserved.
*/

#import <AppKit/NSDPSContext.h>
#import <AppKit/AppKitDefines.h>
#import <mach/mach.h>

@class NSEvent;

/* used with NSRunLoop's performSelector:target:argument:order:modes: */
enum {
    DPSFlushContextRunLoopOrdering = 800000
};

typedef struct _DPSTaggedMsg {
    msg_header_t header;
    msg_type_t type;
    int values[2];
} DPSTaggedMsg;
  /* Start of a message passed to DPSSendTaggedMsg. */

@interface NSDPSServerContext : NSDPSContext {
 /*All instance variables are private*/
 @private
  /* data being parsed, NULL if no valid data */
    char *bufStart;
  /* size of buffer we're parsing if data was ooline, 0 if inline */
    int oolineSize;
  /* parsing ptrs into data buffer */
    char *bufCurr;
    char *bufEnd;
  /* filter routine for events */
    void *eventFunc;
  /* dead key events */
    void *deadDownEvent;
    void *deadUpEvent;
  /* port to get PS messages on */
    NSPort *inPort;
  /* port to send PS messages to */
    NSPort *outPort;
  /* set of flags */
    struct {
      /* do we need to get more data from PS? */
	unsigned int needMoreData:1;
      /* should we free the data pointed to by bufStart? */
	unsigned int freeBufStart:1;
      /* has someone called DPSStartWaitCursorTimer? */
	unsigned int didStartWCTimer:1;
      /* do we owe Window Server a wait cursor ack? */
	unsigned int needsWCAck:1;
      /* perf flag for monitoring Q size */
	unsigned int evQGrowing:1;
      /* pmon sending mode (used by send_data to make pmon events) */
	unsigned int sendMode:4;
      /* did parse the incoming message ? */
        unsigned int didParseMessage:1;
      /* should disable auto ping temporarily ? */
        unsigned int disableAutoPing:1;
	unsigned int reserved:21;
    } flags;
  /* port to receive Pings on */
    NSPort *pingPort;
  /* count of last ping we received */
    int lastPingReceived;
  /* the timestamp of the last event we've handed to the app */
    int eventTimeToAckWC;
  /* the timestamp of the last event we've recevied */
    int lastEventTimeReceived;
  /* ever incrementing count of pings */
    int lastPingSent;
  /* list of asynchronous ping handlers */
    NSMutableArray *asyncPings;
    NSString *hostName;
    NSString *serverName;
    unsigned int _reservedDPSServerContext;
}

- initWithHostName:(NSString *)hostName serverName:(NSString *)serverName textProc:(DPSTextProc)textProc errorProc:(DPSErrorProc)errorProc timeout:(NSTimeInterval)timeout secure:(BOOL)secureFlag encapsulated:(BOOL)doEncapsulated;

- (NSString *)hostName;
- (NSString *)serverName;

- (int)sendPort:(NSPort *)port withAllRights:(BOOL)flag;

- (int)sendTaggedMsg:(DPSTaggedMsg *)msg;

- (void)sendEOF;

- (NSEvent *)nextEventMatchingMask:(unsigned int)mask untilDate:(NSDate *)expiration inMode:(NSString *)mode dequeue:(BOOL)deqFlag;
+ (NSEvent *)nextEventMatchingMask:(unsigned int)mask untilDate:(NSDate *)expiration inMode:(NSString *)mode dequeue:(BOOL)deqFlag;

+ (void)setEventCoalescingEnabled:(BOOL)flag;
+ (BOOL)isEventCoalescingEnabled;

+ (void)setDeadKeyProcessingEnabled:(BOOL)flag;
+ (BOOL)isDeadKeyProcessingEnabled;

+ (void)setEventsTraced:(BOOL)flag;
+ (BOOL)areEventsTraced;

@end

APPKIT_EXTERN const char *DPSNameFromTypeAndIndex(short type, int index);

APPKIT_EXTERN int DPSDefineUserObject(int index);
  /* Maps a PostScript object to a user object index.  If index is 0, a new
     userobject index is allocated;  otherwise the supplied index is used.
     In either case, the new index for the object is returned.  This index
     can be passed to a pswrap generated function taking a "userobject"
     parameter.  This routine should be called with the object that is
     to be indexed on the top of the operand stack.
  */

APPKIT_EXTERN int DPSNextUserObject();

APPKIT_EXTERN void DPSAllocUserObjectLock();
  /* allocates and initializes a simple lock to protect the user object index */

APPKIT_EXTERN void DPSUndefineUserObject(int index);
  /* Unmaps a previously created user object. */
