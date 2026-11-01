/* Private HTTP URL resource handler. */

#import <Foundation/NSURLHandle.h>

@class NSData, NSDictionary, NSHTTPConnection, NSMutableDictionary, NSString, NSURL;

#if defined(__ppc__) || defined(__POWERPC__)
@interface NSHTTPURLHandle : NSURLHandle
{
    NSURL *_url;
    NSDictionary *_headers;
    NSHTTPConnection *_connection;
    NSHTTPURLHandle *_redirectedHandle;
}

+ (NSURL *)canonicalHTTPURLForURL:(NSURL *)url;
+ (BOOL)canInitWithURL:(NSURL *)url;
+ (NSURLHandle *)cachedHandleForURL:(NSURL *)url;
- initWithURL:(NSURL *)url cached:(BOOL)cached;
- (NSURL *)_URL;
- (NSHTTPURLHandle *)_redirectedHandle;
- (BOOL)inRedirectionLoop;
- (id)propertyForKey:(NSString *)key;
- (id)propertyForKeyIfAvailable:(NSString *)key;
- (BOOL)writeProperty:(id)value forKey:(NSString *)key;
- (BOOL)writeData:(NSData *)data;
- (void)flushCachedData;
- (NSData *)loadInForeground;
- (void)beginLoadInBackground;
- (void)endLoadInBackground;
- (NSHTTPURLHandle *)redirectedHandleFromHeaders:(NSDictionary *)headers;
- (void)receivedDataBlock:(NSData *)data forRequest:(id)request finished:(BOOL)finished;
- (void)receivedHeaders:(NSDictionary *)headers forRequest:(id)request;
- (void)connectionFailedDuringRequest:(id)request;
- (void)requestWasCancelled:(id)request;
- (void)URLHandle:(NSURLHandle *)sender resourceDataDidBecomeAvailable:(NSData *)data;
- (void)URLHandleResourceDidBeginLoading:(NSURLHandle *)sender;
- (void)URLHandleResourceDidFinishLoading:(NSURLHandle *)sender;
- (void)URLHandleResourceDidCancelLoading:(NSURLHandle *)sender;
- (void)URLHandle:(NSURLHandle *)sender resourceDidFailLoadingWithReason:(NSString *)reason;
- (void)didLoadBytes:(NSData *)data loadComplete:(BOOL)complete;
@end
#endif
