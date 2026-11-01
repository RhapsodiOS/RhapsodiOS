/*	NSHTTPSocket.h
	Private socket transport used by the PPC HTTP URL loader.
*/

#import <Foundation/NSObject.h>

@class NSData, NSHost;

#if defined(__ppc__) || defined(__POWERPC__)
@interface NSHTTPSocket : NSObject
{
    unsigned int _socket;
    NSData *_surplusBytes;
}

- initWithSocket:(unsigned int)socket;
+ (id)descriptorWithStreamSocket;
- (void)connectToHost:(NSHost *)host withPort:(unsigned int)port;
- (NSData *)readAvailableData:(unsigned int)length;
- (void)writeData:(NSData *)data;
- (void)returnSurplusBytes:(NSData *)data;

@end
#endif
