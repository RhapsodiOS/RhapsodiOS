/*	NSHTTPSocket.m
	Private socket transport used by the PPC HTTP URL loader.
*/

#import <Foundation/NSHTTPSocket.h>

#if defined(__ppc__) || defined(__POWERPC__)

#import <Foundation/NSBundle.h>
#import <Foundation/NSData.h>
#import <Foundation/NSException.h>
#import <Foundation/NSFileHandle.h>
#import <Foundation/NSHost.h>
#import <Foundation/NSString.h>

#include <errno.h>
#include <netdb.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

extern NSBundle *_NSFoundationBundle(void);
extern const char *_NSErrnoMessage(void);

@implementation NSHTTPSocket

- initWithSocket:(unsigned int)socket {
    if ((self = [super init]) != nil) {
        _socket = socket;
        _surplusBytes = nil;
    }
    return self;
}

+ (id)descriptorWithStreamSocket {
    int socketDescriptor = socket(AF_INET, SOCK_STREAM, 0);
    return [[[self alloc] initWithSocket:socketDescriptor] autorelease];
}

- (void)dealloc {
    close(_socket);
    [_surplusBytes release];
    _surplusBytes = nil;
    [super dealloc];
}

- (void)connectToHost:(NSHost *)host withPort:(unsigned int)port {
    NSString *hostName = [host name];
    struct hostent *hostEntry = gethostbyname([hostName cString]);
    struct sockaddr address;

    if (hostEntry == NULL) {
        NSString *reason = [_NSFoundationBundle()
            localizedStringForKey:@"Can't determine IP address of host: %@."
            value:nil table:nil];
        [NSException raise:NSGenericException format:reason, hostName];
    }

    memset(&address, 0, sizeof(address));
    address.sa_family = AF_INET;
    *((unsigned short *)address.sa_data) = port;
    memmove(&address.sa_data[2], hostEntry->h_addr_list[0], hostEntry->h_length);

    if (connect(_socket, &address, sizeof(address)) < 0) {
        NSString *reason = [_NSFoundationBundle()
            localizedStringForKey:@"Can't connect to host %@ using port %d"
            value:nil table:nil];
        [NSException raise:NSGenericException format:reason,
            hostName, port];
    }
}

- (NSData *)readAvailableData:(unsigned int)length {
    void *buffer;
    ssize_t bytesRead;

    if (_surplusBytes != nil) {
        NSData *data = [_surplusBytes autorelease];
        _surplusBytes = nil;
        return data;
    }

    if (length == 0)
        length = 4096;
    buffer = malloc(length);
    bytesRead = recv(_socket, buffer, length, 0);
    if (bytesRead == 0) {
        free(buffer);
        return nil;
    }
    if (bytesRead < 0) {
        free(buffer);
        if (errno == 35)
            return [NSData data];
        [NSException raise:NSFileHandleOperationException format:@"recv: %s",
            _NSErrnoMessage()];
    }

    {
        NSData *data = [NSData dataWithBytes:buffer length:(unsigned int)bytesRead];
        free(buffer);
        return data;
    }
}

- (void)writeData:(NSData *)data {
    const char *bytes = [data bytes];
    unsigned int remaining = [data length];

    while (remaining > 0) {
        ssize_t bytesWritten = send(_socket, bytes, remaining, 0);
        if (bytesWritten <= 0) {
            [NSException raise:NSFileHandleOperationException format:@"send: %s",
                _NSErrnoMessage()];
        }
        bytes += bytesWritten;
        remaining -= (unsigned int)bytesWritten;
    }
}

- (void)returnSurplusBytes:(NSData *)data {
    if (_surplusBytes != nil) {
        NSMutableData *newSurplus = [[NSMutableData alloc] initWithData:_surplusBytes];
        [newSurplus appendData:data];
        [_surplusBytes release];
        _surplusBytes = [[NSData alloc] initWithData:newSurplus];
        [newSurplus release];
    } else {
        _surplusBytes = [data retain];
    }
}

@end

#endif
