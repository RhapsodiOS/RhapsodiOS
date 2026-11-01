/*	NSHTTPConnection.h
	Private request queue and response transport for the PPC HTTP URL loader.
*/

#import <Foundation/NSObject.h>

@class NSData, NSDictionary, NSConditionLock, NSHost, NSLock, NSMutableArray;
@class NSNotification, NSPort, NSPortMessage, NSString, NSURL, NSHTTPRequest;
@class NSHTTPSocket;

#if defined(__ppc__) || defined(__POWERPC__)
@interface NSHTTPConnection : NSObject
{
    NSPort *_port;
    NSHost *_host;
    unsigned int _remotePort;
    NSLock *_lock;
    NSMutableArray *_newJobs;
    void *_completedJobs;
    int _currentSynchCondition;
    NSMutableArray *_synchCompletedJobs;
    NSConditionLock *_synchLock;
    NSHTTPSocket *_socket;
}

+ (id)cachedConnectionForHost:(NSHost *)host port:(unsigned int)port;
+ (id)connectionForHost:(NSString *)host port:(unsigned int)port;
- initWithHost:(NSHost *)host port:(unsigned int)port;
- (NSHost *)host;
- (unsigned int)remotePortNumber;
- (NSData *)sendRequestSynchronously:(NSHTTPRequest *)request
                             headers:(NSDictionary **)headers;
- (void)enqueueRequest:(NSHTTPRequest *)request forClient:(id)client;
- (void)cancelRequest:(NSHTTPRequest *)request;
- (void)cancelFetchOfURL:(NSURL *)url;
- (void)receivedHeaders:(NSDictionary *)headers forRequest:(NSHTTPRequest *)request;
- (void)receivedDataBlock:(NSData *)data forRequest:(NSHTTPRequest *)request
                 finished:(BOOL)finished;
- (void)connectionFailedDuringRequest:(NSHTTPRequest *)request;
- (void)requestWasCancelled:(NSHTTPRequest *)request;
- (void)handlePortMessage:(NSPortMessage *)message;
- (void)portBecameInvalid:(NSNotification *)notification;
- (int)_nextSynchCondition;

@end
#endif
