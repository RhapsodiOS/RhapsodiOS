/*	NSHTTPConnection.m
	HTTP request queue and response transport for the PPC URL loader.
*/

#import <Foundation/NSHTTPConnection.h>

#if defined(__ppc__) || defined(__POWERPC__)

#import <Foundation/NSArray.h>
#import <Foundation/NSBundle.h>
#import <Foundation/NSCharacterSet.h>
#import <Foundation/NSData.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSException.h>
#import <Foundation/NSHost.h>
#import <Foundation/NSLock.h>
#import <Foundation/NSNotification.h>
#import <Foundation/NSPort.h>
#import <Foundation/NSPortMessage.h>
#import <Foundation/NSRunLoop.h>
#import <Foundation/NSString.h>
#import <Foundation/NSThread.h>
#import <Foundation/NSURL.h>
#import <Foundation/NSValue.h>
#import <Foundation/NSAutoreleasePool.h>
#import <Foundation/NSHTTPRequest.h>
#import <Foundation/NSHTTPSocket.h>

#include <stdlib.h>
#include <string.h>

static NSCharacterSet *NSHTTPConnectionHeaderWhitespaceSet;

typedef struct _NSHTTPConnectionClientMessage {
    unsigned kind;
    id client;
    id object;
    struct _NSHTTPConnectionClientMessage *next;
} NSHTTPConnectionClientMessage;

typedef struct {
    unsigned kind;
    id client;
    id object;
    NSHTTPConnectionClientMessage *next;
} NSHTTPConnectionSignalMessage;

@interface NSHTTPConnection (NSHTTPConnectionBackgroundThread)
- (void)processRequests:(id)argument;
- (char *)_findCRLF:(char *)start length:(unsigned)length;
- (NSDictionary *)fetchHeadersForRequest:(NSHTTPRequest *)request
                          connectionDied:(char *)connectionDied;
- (NSDictionary *)enrichedHeadersFromHeaders:(NSDictionary *)headers
                                  andStatus:(NSString *)status;
- (unsigned)numberDataBytesForRequest:(NSHTTPRequest *)request
                          withHeaders:(NSDictionary *)headers;
- (void)fetchResponseForRequest:(NSHTTPRequest *)request;
- (void)signalMessage:(NSHTTPConnectionSignalMessage *)message;
- (void)signalTaskCompletion;
- (void)signalConnectionFailureForRequest:(NSHTTPRequest *)request;
- (void)signalDataBlock:(NSData *)data forRequest:(NSHTTPRequest *)request
               finished:(BOOL)finished;
- (void)signalHeaders:(NSDictionary *)headers complete:(BOOL)complete
           forRequest:(NSHTTPRequest *)request;
@end

static NSLock *NSHTTPConnectionCacheLock;
static NSMutableArray *NSHTTPConnectionCache;
static NSHTTPConnectionClientMessage *NSHTTPConnectionAvailableMessages;
extern NSBundle *_NSFoundationBundle(void);

static NSHTTPConnectionClientMessage *NSHTTPConnectionNewMessage(void)
{
    NSHTTPConnectionClientMessage *message;

    [NSHTTPConnectionCacheLock lock];
    message = NSHTTPConnectionAvailableMessages;
    if (message != NULL)
        NSHTTPConnectionAvailableMessages = message->next;
    [NSHTTPConnectionCacheLock unlock];
    if (message == NULL)
        message = malloc(sizeof(NSHTTPConnectionClientMessage));
    message->object = nil;
    message->client = nil;
    message->next = NULL;
    return message;
}

static void NSHTTPConnectionFreeMessage(NSHTTPConnectionClientMessage *message)
{
    [NSHTTPConnectionCacheLock lock];
    message->next = NSHTTPConnectionAvailableMessages;
    NSHTTPConnectionAvailableMessages = message;
    [NSHTTPConnectionCacheLock unlock];
}

static NSMutableDictionary *NSHTTPConnectionSynchronousRecord(
    NSDictionary *headers, NSHTTPRequest *request)
{
    return [[NSMutableDictionary alloc] initWithObjectsAndKeys:
        headers, @"NSHTTPHeadersKey",
        [NSMutableData data], @"NSHTTPDataKey",
        request, @"NSHTTPRequestKey", nil];
}

@implementation NSHTTPConnection

+ (void)initialize
{
    if (self != [NSHTTPConnection class])
        return;
    NSHTTPConnectionCacheLock = [[NSLock alloc] init];
    NSHTTPConnectionCache = [[NSMutableArray alloc] init];
}

+ (id)cachedConnectionForHost:(NSHost *)host port:(unsigned int)port
{
    NSHTTPConnection *connection = nil;
    unsigned index;

    [NSHTTPConnectionCacheLock lock];
    for (index = 0; index < [NSHTTPConnectionCache count]; ++index) {
        NSHTTPConnection *candidate = [NSHTTPConnectionCache objectAtIndex:index];
        if ([[candidate host] isEqualToHost:host] &&
            [candidate remotePortNumber] == port) {
            connection = candidate;
            break;
        }
    }
    [NSHTTPConnectionCacheLock unlock];
    return connection;
}

+ (id)connectionForHost:(NSString *)host port:(unsigned int)port
{
    NSHost *resolvedHost = [NSHost hostWithAddress:host];
    NSHTTPConnection *connection;

    if (resolvedHost == nil)
        resolvedHost = [NSHost hostWithName:host];
    if (resolvedHost == nil)
        return nil;

    connection = [self cachedConnectionForHost:resolvedHost port:port];
    if (connection != nil)
        return connection;

    connection = [[[self alloc] initWithHost:resolvedHost port:port] autorelease];
    [NSHTTPConnectionCacheLock lock];
    [NSHTTPConnectionCache addObject:connection];
    [NSHTTPConnectionCacheLock unlock];
    return connection;
}

- initWithHost:(NSHost *)host port:(unsigned int)port
{
    self = [super init];
    if (self != nil) {
        _socket = nil;
        _port = nil;
        _host = [host retain];
        _remotePort = port;
        _newJobs = [[NSMutableArray alloc] init];
        _completedJobs = NULL;
        _currentSynchCondition = -1;
        _synchCompletedJobs = [[NSMutableArray alloc] init];
        _synchLock = [[NSConditionLock alloc] initWithCondition:-1];
        _lock = [[NSLock alloc] init];
    }
    return self;
}

- (NSHost *)host
{
    return _host;
}

- (unsigned int)remotePortNumber
{
    return _remotePort;
}

- (int)_nextSynchCondition
{
    int candidate;

    [_synchLock lock];
    candidate = _currentSynchCondition + 1;
    if (candidate >= 0) {
        _currentSynchCondition = candidate;
        [_synchLock unlock];
        return candidate;
    }

    if (_currentSynchCondition == 0x7fffffff)
        _currentSynchCondition = -2;
    [_synchLock unlock];
    for (candidate = 0; candidate != 0x7fffffff; ++candidate) {
        BOOL used = NO;
        unsigned index;
        unsigned count;
        NSHTTPConnectionClientMessage *message;

        [_lock lock];
        count = [_newJobs count];
        for (index = 0; index < count && !used; ++index)
            used = [[_newJobs objectAtIndex:index] _condition] == candidate;
        [_lock unlock];
        if (!used) {
            [_lock lock];
            for (message = _completedJobs; message != NULL && !used;
                 message = message->next)
                used = [(NSHTTPRequest *)message->client _condition] == candidate;
            [_lock unlock];
        }
        if (!used) {
            [_lock lock];
            count = [_synchCompletedJobs count];
            for (index = 0; index < count && !used; ++index)
                used = [[[_synchCompletedJobs objectAtIndex:index]
                    objectForKey:@"NSHTTPRequestKey"] _condition] == candidate;
            [_lock unlock];
        }
        if (!used)
            return candidate;
    }
    NSLog(@"Ran out of condition lock values for HTTP requests!");
    [_synchLock lock];
    candidate = _currentSynchCondition - 1;
    _currentSynchCondition = candidate;
    [_synchLock unlock];
    return candidate;
}

- (NSData *)sendRequestSynchronously:(NSHTTPRequest *)request
                             headers:(NSDictionary **)headers
{
    int condition = [self _nextSynchCondition];
    NSMutableDictionary *record = nil;
    unsigned count;
    unsigned index;

    [request _setCondition:condition];
    [self enqueueRequest:request forClient:self];
    while (![_synchLock tryLockWhenCondition:condition]) {
        NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:0.01];
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                  beforeDate:limit];
    }
    [_synchLock unlockWithCondition:-1];
    [_lock lock];
    count = [_synchCompletedJobs count];
    for (index = 0; index < count; ++index) {
        NSDictionary *candidate = [_synchCompletedJobs objectAtIndex:index];
        if ([candidate objectForKey:@"NSHTTPRequestKey"] == request) {
            record = [candidate retain];
            [_synchCompletedJobs removeObjectAtIndex:index];
            break;
        }
    }
    [_lock unlock];
    if (record == nil) {
        if (headers != NULL)
            *headers = nil;
        return nil;
    }
    record = [record autorelease];
    if (headers != NULL)
        *headers = [record objectForKey:@"NSHTTPHeadersKey"];
    return [record objectForKey:@"NSHTTPDataKey"];
}

- (void)enqueueRequest:(NSHTTPRequest *)request forClient:(id)client
{
    [request _setClient:client];
    [_lock lock];
    if (client == self) {
        unsigned index = 0;
        while (index < [_newJobs count] &&
               [[_newJobs objectAtIndex:index] _client] == self)
            ++index;
        [_newJobs insertObject:request atIndex:index];
    } else {
        [_newJobs addObject:request];
    }
    [_lock unlock];

    if (_port == nil) {
        _port = [[NSPort port] retain];
        [_port setDelegate:self];
        [[NSNotificationCenter defaultCenter] addObserver:self
            selector:@selector(portBecameInvalid:)
            name:NSPortDidBecomeInvalidNotification object:_port];
        [[NSRunLoop currentRunLoop] addPort:_port forMode:NSDefaultRunLoopMode];
        [NSThread detachNewThreadSelector:@selector(processRequests:)
                                  toTarget:self withObject:_port];
    }
}

- (void)cancelRequest:(NSHTTPRequest *)request
{
    id client;

    [_lock lock];
    client = [[request _client] retain];
    if ([_newJobs indexOfObject:request] != NSNotFound)
        [_newJobs removeObject:request];
    [request _setClient:nil];
    [_lock unlock];
    [client requestWasCancelled:request];
    [client release];
}

- (void)cancelFetchOfURL:(NSURL *)url
{
    NSHTTPRequest *request = nil;
    unsigned count;
    unsigned index;

    [_lock lock];
    count = [_newJobs count];
    for (index = 0; index < count; ++index) {
        NSHTTPRequest *candidate = [_newJobs objectAtIndex:index];
        if ([candidate fetchesURL:url]) {
            request = candidate;
            break;
        }
    }
    [_lock unlock];
    if (request != nil)
        [self cancelRequest:request];
}

- (void)receivedHeaders:(NSDictionary *)headers forRequest:(NSHTTPRequest *)request
{
    NSMutableDictionary *record = NSHTTPConnectionSynchronousRecord(
        headers, request);

    [_lock lock];
    [_synchCompletedJobs addObject:record];
    [_lock unlock];
    [record release];
}

- (void)receivedDataBlock:(NSData *)data forRequest:(NSHTTPRequest *)request
                 finished:(BOOL)finished
{
    int condition;
    unsigned count;
    unsigned index;

    [_lock lock];
    condition = [request _condition];
    if (condition == -1) {
        [_lock unlock];
        return;
    }
    if (data != nil && [data length] != 0) {
        count = [_synchCompletedJobs count];
        for (index = 0; index < count; ++index) {
            NSMutableDictionary *record = [_synchCompletedJobs objectAtIndex:index];
            if ([record objectForKey:@"NSHTTPRequestKey"] == request) {
                [[record objectForKey:@"NSHTTPDataKey"] appendData:data];
                break;
            }
        }
    }
    [_lock unlock];
    if (finished) {
        [_synchLock unlockWithCondition:-1];
        [_synchLock unlockWithCondition:condition];
    }
}

- (void)connectionFailedDuringRequest:(NSHTTPRequest *)request
{
    [self signalConnectionFailureForRequest:request];
}

- (void)requestWasCancelled:(NSHTTPRequest *)request
{
    int condition;
    unsigned count;
    unsigned index;

    [_lock lock];
    condition = [request _condition];
    [request _setCondition:-1];
    count = [_synchCompletedJobs count];
    for (index = 0; index < count; ++index) {
        NSDictionary *record = [_synchCompletedJobs objectAtIndex:index];
        if ([record objectForKey:@"NSHTTPRequestKey"] == request) {
            [_synchCompletedJobs removeObjectAtIndex:index];
            break;
        }
    }
    [_lock unlock];
    [_synchLock unlockWithCondition:-1];
    [_synchLock unlockWithCondition:condition];
}

- (void)handlePortMessage:(NSPortMessage *)portMessage
{
    NSHTTPConnectionClientMessage *message;
    (void)portMessage;

    for (;;) {
        id client;
        NSHTTPRequest *request;

        [_lock lock];
        message = _completedJobs;
        if (message != NULL)
            _completedJobs = message->next;
        [_lock unlock];
        if (message == NULL)
            return;

        request = (NSHTTPRequest *)message->client;
        client = [request _client];
        switch (message->kind) {
        case 0:
            if (client != nil)
                [client connectionFailedDuringRequest:request];
            break;
        case 1:
        case 2:
            if (client != nil)
                [client receivedDataBlock:(NSData *)message->object
                               forRequest:request
                                 finished:(message->kind == 2)];
            break;
        case 3:
            [_lock lock];
            if ([_newJobs count] == 0) {
                [_lock unlock];
                [[NSRunLoop currentRunLoop] removePort:_port
                                               forMode:NSDefaultRunLoopMode];
                [[NSNotificationCenter defaultCenter] removeObserver:self
                    name:NSPortDidBecomeInvalidNotification object:_port];
                [_port release];
                _port = nil;
            } else {
                [_lock unlock];
                [NSThread detachNewThreadSelector:@selector(processRequests:)
                    toTarget:self withObject:nil];
            }
            break;
        case 4:
        case 5:
            if (client != nil) {
                [client receivedHeaders:(NSDictionary *)message->object
                             forRequest:request];
                if (message->kind == 5)
                    [client receivedDataBlock:nil forRequest:request finished:YES];
            }
            break;
        default:
            NSLog(@"Got unknown status code %d from HTTP background thread!",
                message->kind);
            NSHTTPConnectionFreeMessage(message);
            continue;
        }
        [message->object release];
        [message->client release];
        NSHTTPConnectionFreeMessage(message);
    }
}

- (void)portBecameInvalid:(NSNotification *)notification
{
    (void)notification;
    [_lock lock];
    [[NSNotificationCenter defaultCenter] removeObserver:self
        name:NSPortDidBecomeInvalidNotification object:_port];
    [_port invalidate];
    _port = [[NSPort port] retain];
    [_port setDelegate:self];
    [[NSRunLoop currentRunLoop] addPort:_port forMode:NSDefaultRunLoopMode];
    [[NSNotificationCenter defaultCenter] addObserver:self
        selector:@selector(portBecameInvalid:)
        name:NSPortDidBecomeInvalidNotification object:_port];
    [_lock unlock];
    [self handlePortMessage:nil];
}

@end

@implementation NSHTTPConnection (NSHTTPConnectionBackgroundThread)

- (char *)_findCRLF:(char *)start length:(unsigned)length
{
    unsigned index;
    BOOL sawCarriageReturn = NO;

    if (length == 0)
        return NULL;
    index = 0;
    while (index < length) {
        while (index < length && start[index] == '\r') {
            sawCarriageReturn = YES;
            ++index;
        }
        if (index >= length)
            break;
        if (start[index] != '\n' || !sawCarriageReturn) {
            sawCarriageReturn = NO;
            ++index;
            continue;
        }
        return start + index - 1;
    }
    return NULL;
}

- (unsigned)numberDataBytesForRequest:(NSHTTPRequest *)request
                          withHeaders:(NSDictionary *)headers
{
    unsigned status;
    id contentLength;

    if ([[request requestMethod] isEqualToString:@"HEAD"])
        return 0;
    status = [[headers objectForKey:@"NSHTTPPropertyStatusCodeKey"]
        unsignedIntValue];
    if ((status >= 100 && status < 200) || status == 204 || status == 304)
        return 0;
    contentLength = [headers objectForKey:@"content-length"];
    if (contentLength != nil && [contentLength length] != 0)
        return [contentLength unsignedIntValue];
    return 0x7fffffffU;
}

- (NSDictionary *)enrichedHeadersFromHeaders:(NSDictionary *)headers
                                  andStatus:(NSString *)statusLine
{
    NSMutableDictionary *result = [[NSMutableDictionary alloc]
        initWithDictionary:headers];
    NSRange firstSeparator = [statusLine rangeOfString:@" "];
    NSString *reason = nil;

    if (firstSeparator.location != NSNotFound) {
        [result setObject:[statusLine substringToIndex:firstSeparator.location]
                   forKey:@"NSHTTPPropertyServerHTTPVersionKey"];
        NSRange remainingRange = NSMakeRange(firstSeparator.location + 1,
            [statusLine length] - firstSeparator.location - 1);
        NSRange nextSeparator = [statusLine rangeOfString:@" "
            options:NSLiteralSearch range:remainingRange];

        if (nextSeparator.location != NSNotFound) {
            NSRange statusRange = NSMakeRange(firstSeparator.location + 1,
                nextSeparator.location - firstSeparator.location - 1);
            NSString *statusText = [statusLine substringWithRange:statusRange];
            [result setObject:[NSNumber numberWithInt:[statusText intValue]]
                       forKey:@"NSHTTPPropertyStatusCodeKey"];
            reason = [statusLine substringFromIndex:nextSeparator.location + 1];
        } else {
            NSString *statusText = [statusLine substringFromIndex:
                firstSeparator.location + 1];

            if ([statusText length] == 3 && [statusText intValue] > 99) {
                [result setObject:[NSNumber numberWithInt:[statusText intValue]]
                           forKey:@"NSHTTPPropertyStatusCodeKey"];
                return [result autorelease];
            }
        }
    }
    if (reason == nil) {
        [result setObject:[NSNumber numberWithInt:599]
                   forKey:@"NSHTTPPropertyStatusCodeKey"];
        reason = [_NSFoundationBundle() localizedStringForKey:
            @"Bad header received from server" value:nil table:@"URL"];
    }
    [result setObject:reason forKey:@"NSHTTPPropertyStatusReasonKey"];
    return [result autorelease];
}

- (NSDictionary *)fetchHeadersForRequest:(NSHTTPRequest *)request
                          connectionDied:(char *)connectionDied
{
    NSMutableData *buffer = [[NSMutableData alloc] init];
    NSMutableDictionary *headers = [[NSMutableDictionary alloc] init];
    NSString *statusLine = nil;
    NSString *lastKey = nil;
    BOOL boundaryFound = NO;

    if (NSHTTPConnectionHeaderWhitespaceSet == nil)
        NSHTTPConnectionHeaderWhitespaceSet =
            [[NSCharacterSet whitespaceAndNewlineCharacterSet] retain];
    for (;;) {
        NSData *chunk = nil;
        NS_DURING
            chunk = [_socket readAvailableData:512];
        NS_HANDLER
            chunk = nil;
        NS_ENDHANDLER
        if (chunk == nil)
            break;
        [buffer appendData:chunk];
        for (;;) {
            unsigned length = [buffer length];
            char *bytes = (char *)[buffer bytes];
            char *end = [self _findCRLF:bytes length:length];
            unsigned lineLength;
            NSString *line;

            if (end == NULL)
                break;
            lineLength = end - bytes;
            line = [[[NSString alloc] initWithCString:bytes length:lineLength]
                autorelease];
            {
                NSData *remainder = [NSData dataWithBytes:bytes + lineLength + 2
                    length:length - lineLength - 2];
                [buffer setData:remainder];
            }
            if ([line length] == 0) {
                boundaryFound = YES;
                break;
            }
            if (statusLine == nil) {
                if (![line hasPrefix:@"HTTP/"]) {
                    NSLog(@"Found bad HTTP header line <%@>", line);
                    [_socket returnSurplusBytes:buffer];
                    if (connectionDied != NULL)
                        *connectionDied = 0;
                    return nil;
                }
                statusLine = [line copy];
                continue;
            }
            if ([line characterAtIndex:0] == ' ' ||
                [line characterAtIndex:0] == '\t') {
                NSString *oldValue = [headers objectForKey:lastKey];
                [headers setObject:[oldValue stringByAppendingString:line]
                            forKey:lastKey];
                continue;
            }
            {
                NSRange colon = [line rangeOfString:@":"];
                if (colon.location == NSNotFound) {
                    NSLog(@"Found bad HTTP header line <%@>", line);
                    continue;
                }
                lastKey = [[line substringToIndex:colon.location] lowercaseString];
                {
                    NSString *value = [line substringFromIndex:colon.location + 1];
                    unsigned leading = 0;
                    while (leading < [value length] &&
                           [NSHTTPConnectionHeaderWhitespaceSet
                               characterIsMember:[value characterAtIndex:leading]])
                        leading++;
                    if (leading != 0)
                        value = [value substringFromIndex:leading];
                    [headers setObject:value forKey:lastKey];
                }
            }
        }
        if (boundaryFound)
            break;
    }

    if (connectionDied != NULL)
        *connectionDied = !boundaryFound;
    if (boundaryFound && [buffer length] != 0) {
        [_socket returnSurplusBytes:buffer];
    }
    {
        NSDictionary *result = [self enrichedHeadersFromHeaders:headers
            andStatus:statusLine];
        [buffer release];
        [headers release];
        [statusLine release];
        (void)request;
        return result;
    }
}

- (void)fetchResponseForRequest:(NSHTTPRequest *)request
{
    char connectionDied = 0;
    NSDictionary *headers = [self fetchHeadersForRequest:request
        connectionDied:&connectionDied];
    unsigned remaining = [self numberDataBytesForRequest:request
        withHeaders:headers];

    if (connectionDied) {
        if (headers == nil || remaining != 0)
            [self signalConnectionFailureForRequest:request];
        else
            [self signalTaskCompletion];
        return;
    }

    if (headers != nil)
        [self signalHeaders:headers complete:NO forRequest:request];
    while (remaining != 0) {
        unsigned length = remaining > 512 ? 512 : remaining;
        NSData *data = nil;
        NS_DURING
            data = [_socket readAvailableData:length];
        NS_HANDLER
            data = nil;
        NS_ENDHANDLER
        if (data == nil)
            break;
        if ([data length] != 0) {
            if (remaining != 0x7fffffffU) {
                if ([data length] >= remaining)
                    remaining = 0;
                else
                    remaining -= [data length];
            }
            [self signalDataBlock:data forRequest:request finished:NO];
        }
    }
    [self signalDataBlock:nil forRequest:request finished:YES];
}

- (void)processRequests:(id)argument
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    (void)argument;

    for (;;) {
        NSHTTPRequest *request;
        BOOL failed = NO;

        [_lock lock];
        if ([_newJobs count] == 0) {
            [_lock unlock];
            break;
        }
        request = [[_newJobs objectAtIndex:0] retain];
        [_newJobs removeObjectAtIndex:0];
        [_lock unlock];

        [pool release];
        pool = [[NSAutoreleasePool alloc] init];
        _socket = [NSHTTPSocket descriptorWithStreamSocket];
        NS_DURING
            [_socket connectToHost:_host withPort:_remotePort];
        NS_HANDLER
            failed = YES;
        NS_ENDHANDLER
        if (!failed) {
            NS_DURING
                [_socket writeData:[request serializedRequest]];
            NS_HANDLER
                failed = YES;
            NS_ENDHANDLER
        }
        if (failed)
            [self signalConnectionFailureForRequest:request];
        else
            [self fetchResponseForRequest:request];
        [_socket release];
        _socket = nil;
    }

    [self signalTaskCompletion];
    [pool release];
}

- (void)signalMessage:(NSHTTPConnectionSignalMessage *)messagePointer
{
    NSHTTPConnectionClientMessage *message = messagePointer;
    NSPortMessage *portMessage;
    NSDate *limitDate;
    BOOL sent;

    message->next = NULL;
    [_lock lock];
    if (_completedJobs == NULL) {
        _completedJobs = message;
    } else {
        NSHTTPConnectionClientMessage *tail = _completedJobs;
        while (tail->next != NULL)
            tail = tail->next;
        tail->next = message;
    }

    portMessage = [[NSPortMessage alloc] initWithSendPort:_port
        receivePort:nil components:nil];
    [_lock unlock];
    limitDate = [NSDate dateWithTimeIntervalSinceNow:0.1];
    sent = [portMessage sendBeforeDate:limitDate];
    if (!sent)
        NSLog(@"Couldn't send port message!");
}

- (void)signalTaskCompletion
{
    NSHTTPConnectionClientMessage *message = NSHTTPConnectionNewMessage();
    message->kind = 3;
    [self signalMessage:(NSHTTPConnectionSignalMessage *)message];
}

- (void)signalConnectionFailureForRequest:(NSHTTPRequest *)request
{
    NSHTTPConnectionClientMessage *message;
    if ([request _client] == nil)
        return;
    message = NSHTTPConnectionNewMessage();
    message->kind = 0;
    message->client = [request retain];
    [self signalMessage:(NSHTTPConnectionSignalMessage *)message];
}

- (void)signalDataBlock:(NSData *)data forRequest:(NSHTTPRequest *)request
               finished:(BOOL)finished
{
    NSHTTPConnectionClientMessage *message = NSHTTPConnectionNewMessage();
    message->kind = finished ? 2 : 1;
    message->client = [request retain];
    message->object = [data retain];
    [self signalMessage:(NSHTTPConnectionSignalMessage *)message];
}

- (void)signalHeaders:(NSDictionary *)headers complete:(BOOL)complete
           forRequest:(NSHTTPRequest *)request
{
    NSHTTPConnectionClientMessage *message = NSHTTPConnectionNewMessage();
    message->kind = complete ? 5 : 4;
    message->client = [request retain];
    message->object = [headers retain];
    [self signalMessage:(NSHTTPConnectionSignalMessage *)message];
}

@end

#endif
