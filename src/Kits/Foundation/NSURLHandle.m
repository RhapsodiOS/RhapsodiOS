/*	NSURLHandle.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSURLHandle.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSBundle.h>
#import <Foundation/NSData.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSObjCRuntime.h>
#import <Foundation/NSRunLoop.h>
#import <Foundation/NSString.h>

@class NSFileURLHandle, NSHTTPURLHandle;

static NSMutableArray *registeredURLHandleClasses;

extern NSBundle *_NSFoundationBundle(void);

NSString *NSHTTPPropertyStatusCodeKey = @"NSHTTPPropertyStatusCodeKey";
NSString *NSHTTPPropertyStatusReasonKey = @"NSHTTPPropertyStatusReasonKey";
NSString *NSHTTPPropertyServerHTTPVersionKey = @"NSHTTPPropertyServerHTTPVersionKey";
NSString *NSHTTPPropertyRedirectionHeadersKey = @"NSHTTPPropertyRedirectionHeadersKey";
NSString *NSHTTPPropertyErrorPageDataKey = @"NSHTTPPropertyErrorPageDataKey";

@implementation NSURLHandle

#if defined(__ppc__) || defined(__POWERPC__)
+ (void)initialize {
    if (self == [NSURLHandle class]) {
        registeredURLHandleClasses = [[NSMutableArray alloc] init];
        [self registerURLHandleClass:[NSFileURLHandle class]];
        [self registerURLHandleClass:[NSHTTPURLHandle class]];
    }
}
#endif

// Call this to register a new subclass of NSURLHandle.
+ (void)registerURLHandleClass:(Class)anURLHandleSubclass {
#if defined(__ppc__) || defined(__POWERPC__)
    [registeredURLHandleClasses addObject:anURLHandleSubclass];
#else
    // TODO: Implement this method
#endif
}

+ (Class)URLHandleClassForURL:(NSURL *)anURL {
#if defined(__ppc__) || defined(__POWERPC__)
    unsigned index, count = [registeredURLHandleClasses count];
    for (index = 0; index < count; ++index) {
        Class handleClass = [registeredURLHandleClasses objectAtIndex:index];
        if ([handleClass canInitWithURL:anURL])
            return handleClass;
    }
#else
    // TODO: Implement this method
#endif
    return nil;
}

- (NSURLHandleStatus)status {
#if defined(__ppc__) || defined(__POWERPC__)
    return _status;
#else
    // TODO: Implement this method
    return (NSURLHandleStatus)0;
#endif
}

// If status is NSURLHandleLoadFailed, failureReason returns the reason;
// otherwise, it returns nil.
- (NSString *)failureReason {
#if defined(__ppc__) || defined(__POWERPC__)
    if ([self status] == NSURLHandleLoadFailed)
        return (NSString *)_data;

    NSLog(@"Handle %@ received message -failureReason when its status was not NSURLHandleLoadFailed!", self);
    return nil;
#else
    // TODO: Implement this method
    return nil;
#endif
}

- (void)addClient:(id <NSURLHandleClient>)client {
#if defined(__ppc__) || defined(__POWERPC__)
    if (_clients == nil)
        _clients = [[NSMutableArray alloc] init];
    [_clients addObject:client];
#else
    // TODO: Implement this method
#endif
}

- (void)removeClient:(id <NSURLHandleClient>)client {
#if defined(__ppc__) || defined(__POWERPC__)
    [_clients removeObject:client];
#else
    // TODO: Implement this method
#endif
}

- (void)loadInBackground {
#if defined(__ppc__) || defined(__POWERPC__)
    if (_status == NSURLHandleLoadInProgress) {
        NSLog(@"Cannot start a second background load using the same handle while one is in progress");
        return;
    }
    if (_status != NSURLHandleNotLoaded)
        [self flushCachedData];
    [self beginLoadInBackground];
    _status = NSURLHandleLoadInProgress;
    [_clients makeObjectsPerformSelector:
        @selector(URLHandleResourceDidBeginLoading:) withObject:self];
#else
    // TODO: Implement this method
#endif
}

- (void)cancelLoadInBackground {
#if defined(__ppc__) || defined(__POWERPC__)
    if ([self status] == NSURLHandleLoadInProgress) {
        [self endLoadInBackground];
        [self flushCachedData];
        [_clients makeObjectsPerformSelector:
            @selector(URLHandleResourceDidCancelLoading:) withObject:self];
    }
#else
    // TODO: Implement this method
#endif
}

// Blocks until all data is available.
- (NSData *)resourceData {
#if defined(__ppc__) || defined(__POWERPC__)
    NSURLHandleStatus status;
    NSData *data;
    NSString *format;
    NSString *reason;
    NSArray *clients;
    unsigned count;
    unsigned index;

    status = [self status];

    if (status == NSURLHandleLoadSucceeded)
        return [self availableResourceData];
    if (status == NSURLHandleLoadFailed)
        return nil;
    if (status != NSURLHandleNotLoaded
        && (status != NSURLHandleLoadInProgress || _data != nil)) {
        while ([self status] == NSURLHandleLoadInProgress) {
            NSDate *limitDate = [NSDate dateWithTimeIntervalSinceNow:0.25];
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                      beforeDate:limitDate];
        }
        return [self availableResourceData];
    }

    data = [self loadInForeground];
    if (data != nil) {
        if (_data != nil) {
            [_data release];
            _data = [data retain];
            _status = NSURLHandleLoadSucceeded;
        }
        [_clients makeObjectsPerformSelector:
            @selector(URLHandleResourceDidFinishLoading:) withObject:self];
    } else {
        format = [_NSFoundationBundle()
            localizedStringForKey:@"Don't know how to load URL %@"
                             value:nil table:@"URL"];
        reason = [NSString stringWithFormat:format, self];
        if (_data != nil) {
            [_data release];
            _data = [reason retain];
            _status = NSURLHandleLoadFailed;
        }
        clients = _clients == nil ? nil : [NSArray arrayWithArray:_clients];
        count = [clients count];
        for (index = 0; index < count; ++index)
            [[clients objectAtIndex:index]
                URLHandle:self resourceDidFailLoadingWithReason:reason];
    }
    return data;
#else
    // TODO: Implement this method
    return nil;
#endif
}

// Immediately returns whatever data is available.
- (NSData *)availableResourceData {
#if defined(__ppc__) || defined(__POWERPC__)
    return _status == NSURLHandleLoadFailed ? nil : _data;
#else
    // TODO: Implement this method
    return nil;
#endif
}

- (void)flushCachedData {
#if defined(__ppc__) || defined(__POWERPC__)
    if ([self status] == NSURLHandleLoadInProgress) {
        [self cancelLoadInBackground];
    } else {
        if (_data != nil) {
            [_data release];
            _data = [[NSMutableData data] retain];
        }
        _status = NSURLHandleNotLoaded;
    }
#else
    // TODO: Implement this method
#endif
}

// Sends the failure message to clients.
- (void)backgroundLoadDidFailWithReason:(NSString *)reason {
#if defined(__ppc__) || defined(__POWERPC__)
    NSArray *clients;
    unsigned count;
    unsigned index;

    if (_data != nil) {
        [_data release];
        _data = [reason retain];
        _status = NSURLHandleLoadFailed;
    } else {
        _status = NSURLHandleNotLoaded;
    }

    clients = _clients == nil ? nil : [NSArray arrayWithArray:_clients];
    count = [clients count];
    for (index = 0; index < count; ++index)
        [[clients objectAtIndex:index]
            URLHandle:self resourceDidFailLoadingWithReason:reason];
#else
    // TODO: Implement this method
#endif
}

- (void)didLoadBytes:(NSData *)newBytes loadComplete:(BOOL)yorn {
#if defined(__ppc__) || defined(__POWERPC__)
    NSArray *clients;
    unsigned count;
    unsigned index;

    if (_data != nil) {
        [(NSMutableData *)_data appendData:newBytes];
        if (yorn) {
            NSData *completedData = [NSData dataWithData:_data];
            [_data release];
            _data = [completedData retain];
            _status = NSURLHandleLoadSucceeded;
        }
    } else if (yorn) {
        _status = NSURLHandleNotLoaded;
    }

    clients = _clients == nil ? nil : [NSArray arrayWithArray:_clients];
    count = [clients count];
    for (index = 0; index < count; ++index) {
        id client = [clients objectAtIndex:index];
        [client URLHandle:self resourceDataDidBecomeAvailable:newBytes];
        if (yorn)
            [client URLHandleResourceDidFinishLoading:self];
    }
#else
    // TODO: Implement this method
#endif
}

+ (BOOL)canInitWithURL:(NSURL *)anURL {
#if defined(__ppc__) || defined(__POWERPC__)
    if (self != [NSURLHandle class])
        NSRequestConcreteImplementation(self, _cmd, [NSURLHandle class]);
    return NO;
#else
    // TODO: Implement this method
    return NO;
#endif
}

+ (NSURLHandle *)cachedHandleForURL:(NSURL *)anURL {
#if defined(__ppc__) || defined(__POWERPC__)
    if (self == [NSURLHandle class]) {
        Class handleClass = [self URLHandleClassForURL:anURL];
        if (handleClass != Nil)
            return [handleClass cachedHandleForURL:anURL];
    } else {
        NSRequestConcreteImplementation(self, _cmd, [NSURLHandle class]);
    }
#else
    // TODO: Implement this method
#endif
    return nil;
}

- initWithURL:(NSURL *)anURL cached:(BOOL)willCache {
#if defined(__ppc__) || defined(__POWERPC__)
    self = [super init];
    if (self != nil) {
        _data = willCache ? [[NSMutableData data] retain] : nil;
        _status = NSURLHandleNotLoaded;
        _clients = nil;
    }
    return self;
#else
    // TODO: Implement this method
    return nil;
#endif
}

- (void)dealloc {
#if defined(__ppc__) || defined(__POWERPC__)
    [_data release];
    _data = nil;
    [_clients release];
    _clients = nil;
    [super dealloc];
#else
    // TODO: Implement this method
#endif
}

// Must be overridden by subclasses.
- (id)propertyForKey:(NSString *)propertyKey {
#if defined(__ppc__) || defined(__POWERPC__)
    NSRequestConcreteImplementation(self, _cmd, [NSURLHandle class]);
    return nil;
#else
    // TODO: Implement this method
    return nil;
#endif
}

- (id)propertyForKeyIfAvailable:(NSString *)propertyKey {
#if defined(__ppc__) || defined(__POWERPC__)
    NSRequestConcreteImplementation(self, _cmd, [NSURLHandle class]);
    return nil;
#else
    // TODO: Implement this method
    return nil;
#endif
}

- (BOOL)writeProperty:(id)propertyValue forKey:(NSString *)propertyKey {
#if defined(__ppc__) || defined(__POWERPC__)
    NSRequestConcreteImplementation(self, _cmd, [NSURLHandle class]);
    return NO;
#else
    // TODO: Implement this method
    return NO;
#endif
}

// Must be overridden by subclasses; returns success or failure.
- (BOOL)writeData:(NSData *)data {
#if defined(__ppc__) || defined(__POWERPC__)
    NSRequestConcreteImplementation(self, _cmd, [NSURLHandle class]);
    return NO;
#else
    // TODO: Implement this method
    return NO;
#endif
}

// Called from resourceData.
- (NSData *)loadInForeground {
#if defined(__ppc__) || defined(__POWERPC__)
    NSRequestConcreteImplementation(self, _cmd, [NSURLHandle class]);
    return nil;
#else
    // TODO: Implement this method
    return nil;
#endif
}

// Called from loadInBackground.
- (void)beginLoadInBackground {
#if defined(__ppc__) || defined(__POWERPC__)
    NSRequestConcreteImplementation(self, _cmd, [NSURLHandle class]);
#else
    // TODO: Implement this method
#endif
}

// Called from cancelLoadInBackground.
- (void)endLoadInBackground {
#if defined(__ppc__) || defined(__POWERPC__)
    NSRequestConcreteImplementation(self, _cmd, [NSURLHandle class]);
#else
    // TODO: Implement this method
#endif
}

@end
