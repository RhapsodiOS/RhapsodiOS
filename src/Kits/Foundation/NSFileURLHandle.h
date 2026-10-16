/* Private file: URL resource handler. */

#import <Foundation/NSURLHandle.h>

@class NSData, NSDictionary, NSFileHandle, NSNotification, NSString, NSURL;

#if defined(__ppc__) || defined(__POWERPC__)
@interface NSFileURLHandle : NSURLHandle
{
    NSString *_path;
    NSFileHandle *_fh;
    NSDictionary *_properties;
}

+ (BOOL)canInitWithURL:(NSURL *)url;
+ (NSURLHandle *)cachedHandleForURL:(NSURL *)url;
- initWithURL:(NSURL *)url cached:(BOOL)cached;
- (NSData *)loadInForeground;
- (BOOL)writeData:(NSData *)data;
- (id)propertyForKey:(NSString *)key;
- (id)propertyForKeyIfAvailable:(NSString *)key;
- (BOOL)writeProperty:(id)value forKey:(NSString *)key;
- (void)beginLoadInBackground;
- (void)endLoadInBackground;
- (void)flushCachedData;
- (void)_backgroundFileLoadCompleted:(NSNotification *)notification;
@end
#endif
