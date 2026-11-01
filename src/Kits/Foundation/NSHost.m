/*	NSHost.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSHost.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSMutableArray.h>
#import <Foundation/NSMutableDictionary.h>
#import <Foundation/NSLock.h>
#import <Foundation/NSString.h>

#include <arpa/inet.h>
#include <netdb.h>
#include <netinet/in.h>
#include <string.h>
#include <unistd.h>

static BOOL NSHostCacheEnabled = YES;
static NSMutableDictionary *NSHostCache;
extern NSLock *_NSHostTableLock;

NSString *NSHostName(void) {
#if defined(__ppc__) || defined(__POWERPC__)
    char hostname[276];
    unsigned length;

    if (gethostname(hostname, 257) != 0)
        return @"";
    length = (unsigned)strlen(hostname);
    return [NSString stringWithCString:hostname length:length];
#else
    return @"localhost";
#endif
}

@interface NSHost (NSHostPrivate)
+ (NSHost *)_hostWithHostEntry:(struct hostent *)entry;
+ (NSHost *)_hostWithHostEntry:(struct hostent *)entry name:(NSString *)name;
- (id)_initWithHostEntry:(struct hostent *)entry name:(NSString *)name;
@end

@implementation NSHost

+ (NSHost *)currentHost {
    char hostname[260];
    struct hostent *entry;
    struct in_addr loopback;
    NSString *name;
    unsigned length;

    if (gethostname(hostname, 257) != 0)
        return nil;
    entry = gethostbyname(hostname);
    if (entry == NULL) {
        loopback.s_addr = htonl(INADDR_LOOPBACK);
        entry = gethostbyaddr((const char *)&loopback, sizeof(loopback), AF_INET);
    }
    length = strlen(hostname);
    name = [NSString stringWithCString:hostname length:length];
    return [self _hostWithHostEntry:entry name:name];
}

+ (NSHost *)hostWithName:(NSString *)name {
    struct hostent *entry = gethostbyname([name cString]);

    return [self _hostWithHostEntry:entry];
}

+ (NSHost *)hostWithAddress:(NSString *)address {
    in_addr_t addressValue = inet_addr([address cString]);
    struct hostent *entry;

    if (addressValue == (in_addr_t)-1)
        return nil;
    entry = gethostbyaddr((const char *)&addressValue, sizeof(addressValue), AF_INET);
    return [self _hostWithHostEntry:entry];
}

+ (void)setHostCacheEnabled:(BOOL)flag {
    NSHostCacheEnabled = flag;
}

+ (BOOL)isHostCacheEnabled {
    return NSHostCacheEnabled;
}

+ (void)flushHostCache {
    if (_NSHostTableLock != nil)
        [_NSHostTableLock lock];
    [NSHostCache release];
    NSHostCache = nil;
    if (_NSHostTableLock != nil)
        [_NSHostTableLock unlock];
}

- (BOOL)isEqualToHost:(NSHost *)aHost {
    NSArray *otherAddresses;
    unsigned addressCount;
    unsigned index;

    if (aHost == nil)
        return NO;
    if (aHost == self)
        return YES;
    otherAddresses = [aHost addresses];
    addressCount = [addresses count];
    for (index = 0; index < addressCount; index++) {
        if ([otherAddresses containsObject:[addresses objectAtIndex:index]])
            return YES;
    }
    return NO;
}

- (NSString *)name {
    return [names objectAtIndex:0];
}

- (NSArray *)names {
    return names;
}

- (NSString *)address {
    return [addresses objectAtIndex:0];
}

- (NSArray *)addresses {
    return addresses;
}

- (NSString *)description {
    NSString *name;
    NSArray *hostNames;
    NSArray *hostAddresses;

#if defined(__ppc__) || defined(__POWERPC__)
    name = [self name];
    hostNames = [self names];
    hostAddresses = [self addresses];
#else
    hostAddresses = [self addresses];
    hostNames = [self names];
    name = [self name];
#endif
    return [NSString stringWithFormat:@"Host %@ (%@ %@)",
                                      name, hostNames, hostAddresses];
}

+ (NSHost *)_hostWithHostEntry:(struct hostent *)entry name:(NSString *)name {
    NSHost *host;
    struct in_addr internetAddress;
    const char *addressString;
    const char *lengthString;
    unsigned addressLength;
    NSString *address;

    if (entry == NULL)
        return nil;
    if (NSHostCacheEnabled) {
        if (_NSHostTableLock != nil)
            [_NSHostTableLock lock];
        host = [NSHostCache objectForKey:name];
        if (_NSHostTableLock != nil)
            [_NSHostTableLock unlock];
        if (host != nil)
            return host;
    }
    host = [[self allocWithZone:NULL] _initWithHostEntry:entry name:name];
    memmove(&internetAddress, *entry->h_addr_list, entry->h_length);
    addressString = inet_ntoa(internetAddress);
#if defined(__ppc__) || defined(__POWERPC__)
    lengthString = inet_ntoa(internetAddress);
    addressLength = (unsigned)strlen(lengthString);
#else
    addressLength = (unsigned)strlen(addressString);
    addressString = inet_ntoa(internetAddress);
#endif
    address = [NSString stringWithCString:addressString length:addressLength];
    if (NSHostCacheEnabled) {
        if (_NSHostTableLock != nil)
            [_NSHostTableLock lock];
        if (NSHostCache == nil)
            NSHostCache = [[NSMutableDictionary allocWithZone:NULL] initWithCapacity:6];
        [NSHostCache setObject:host forKey:name];
        [NSHostCache setObject:host forKey:address];
        if (_NSHostTableLock != nil)
            [_NSHostTableLock unlock];
    }
    return [host autorelease];
}

+ (NSHost *)_hostWithHostEntry:(struct hostent *)entry {
    NSString *name;

    if (entry == NULL)
        return nil;
    name = [NSString stringWithCString:entry->h_name
                                 length:(unsigned)strlen(entry->h_name)];
    return [self _hostWithHostEntry:entry name:name];
}

- (id)_initWithHostEntry:(struct hostent *)entry name:(NSString *)name {
    NSString *canonicalName;
    char **alias;
    char **address;

    if (entry == NULL) {
        return nil;
    }
    names = [[NSMutableArray allocWithZone:NULL] initWithCapacity:0];
    [names addObject:name];
    canonicalName = [NSString stringWithCString:entry->h_name
                                         length:(unsigned)strlen(entry->h_name)];
    if (![name isEqualToString:canonicalName])
        [names addObject:canonicalName];
    for (alias = entry->h_aliases; *alias != NULL; alias++) {
        NSString *aliasName = [NSString stringWithCString:*alias
                                                    length:(unsigned)strlen(*alias)];

        if (![name isEqualToString:aliasName])
            [names addObject:aliasName];
    }

    addresses = [[NSMutableArray allocWithZone:NULL] initWithCapacity:0];
    for (address = entry->h_addr_list; *address != NULL; address++) {
        struct in_addr internetAddress;
        const char *addressString;
        const char *lengthString;
        unsigned addressLength;

        memmove(&internetAddress, *address, entry->h_length);
        addressString = inet_ntoa(internetAddress);
#if defined(__ppc__) || defined(__POWERPC__)
        lengthString = inet_ntoa(internetAddress);
        addressLength = (unsigned)strlen(lengthString);
#else
        addressLength = (unsigned)strlen(addressString);
        addressString = inet_ntoa(internetAddress);
#endif
        [addresses addObject:[NSString stringWithCString:addressString
                                                  length:addressLength]];
    }
    return self;
}

- (void)dealloc {
    [names release];
    [addresses release];
    [super dealloc];
}

@end
