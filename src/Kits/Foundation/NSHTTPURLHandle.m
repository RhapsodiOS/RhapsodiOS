/* Private HTTP URL resource handler for the PPC Foundation URL loader. */

#import <Foundation/NSHTTPURLHandle.h>
#import <Foundation/NSHTTPConnection.h>
#import <Foundation/NSHTTPRequest.h>
#import <Foundation/NSBundle.h>
#import <Foundation/NSData.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSRange.h>
#import <Foundation/NSValue.h>
#import <Foundation/NSString.h>
#import <Foundation/NSURL.h>

#if defined(__ppc__) || defined(__POWERPC__)

extern NSBundle *_NSFoundationBundle(void);
extern int _NSParseStringToGenericURLComponents(NSString *string,
    NSRange *scheme, NSRange *user, NSRange *password, NSRange *host,
    NSRange *port, NSRange *path, NSRange *parameters, NSRange *query,
    NSRange *fragment);

@interface NSURL (NSHTTPURLHandlePrivate)
- (NSString *)_relativeURLPath;
@end

static NSMutableDictionary *httpURLHandleCache;
static NSString *NSErrorPageInProgressKey = @"_NSErrorPageInProgress";

@implementation NSHTTPURLHandle

+ (void)initialize {
    if (self == [NSHTTPURLHandle class])
        httpURLHandleCache = [[NSMutableDictionary alloc] init];
}

+ (NSURL *)canonicalHTTPURLForURL:(NSURL *)url {
    NSURL *absoluteURL = [url absoluteURL];
    if (absoluteURL == nil)
        return nil;
    NSString *absolute = [absoluteURL absoluteString];

    NSString *host = [absoluteURL host];
    if (host == nil || [host length] == 0)
        host = @"localhost";
    host = [host lowercaseString];
    NSNumber *port = [absoluteURL port];
    if (port == nil)
        port = [NSNumber numberWithUnsignedInt:80];
    NSString *path = [absoluteURL _relativeURLPath];
    if (path == nil)
        path = @"/";
    NSRange pathRange;
    NSRange fragmentRange;
    (void)_NSParseStringToGenericURLComponents(absolute, NULL, NULL, NULL,
        NULL, NULL, &pathRange, NULL, NULL, &fragmentRange);
    unsigned length = [absolute length];
    if (fragmentRange.length != 0)
        length -= fragmentRange.length + 1;
    unsigned pathEnd = pathRange.location + pathRange.length;
    NSString *suffix = pathEnd < length
        ? [absolute substringWithRange:NSMakeRange(pathEnd, length - pathEnd)]
        : nil;
    NSString *canonical = suffix == nil
        ? [NSString stringWithFormat:@"http://%@:%@%@", host, port, path]
        : [NSString stringWithFormat:@"http://%@:%@%@%@", host, port, path, suffix];
    return [NSURL URLWithString:canonical];
}

+ (BOOL)canInitWithURL:(NSURL *)url {
    NSString *scheme = [url scheme];
    return scheme != nil && [scheme compare:@"http" options:NSCaseInsensitiveSearch] == NSOrderedSame;
}

+ (NSURLHandle *)cachedHandleForURL:(NSURL *)url {
    NSURL *canonical = [self canonicalHTTPURLForURL:url];
    NSHTTPURLHandle *handle = [httpURLHandleCache objectForKey:
        [canonical absoluteString]];
    if (handle == nil) {
        handle = [[self alloc] initWithURL:url cached:YES];
        if (handle != nil)
            [httpURLHandleCache setObject:handle
                forKey:[canonical absoluteString]];
    }
    return handle;
}

- initWithURL:(NSURL *)url cached:(BOOL)cached {
    self = [super initWithURL:url cached:cached];
    if (self != nil) {
        _url = [[[self class] canonicalHTTPURLForURL:url] retain];
        _headers = cached ? [[NSMutableDictionary alloc] init] : nil;
        _connection = nil;
        _redirectedHandle = nil;
    }
    return self;
}

- (void)dealloc {
    [self endLoadInBackground];
    [_url release];
    [_headers release];
    [_connection release];
    [_redirectedHandle release];
    [super dealloc];
}

- (BOOL)writeData:(NSData *)data { return NO; }
- (BOOL)writeProperty:(id)value forKey:(NSString *)key { return NO; }

- (NSURL *)_URL { return _url; }
- (NSHTTPURLHandle *)_redirectedHandle { return _redirectedHandle; }

- (BOOL)inRedirectionLoop {
    NSMutableArray *visited = [[NSMutableArray alloc]
        initWithObjects:[_url relativeString], nil];
    NSHTTPURLHandle *handle = _redirectedHandle;
    while (handle != nil) {
        NSString *urlString = [[handle _URL] absoluteString];
        if ([visited indexOfObject:urlString] != NSNotFound) {
            [visited release];
            return YES;
        }
        [visited addObject:urlString];
        handle = [handle _redirectedHandle];
    }
    [visited release];
    return NO;
}

- (id)propertyForKey:(NSString *)key {
    NSHTTPRequest *request;
    NSString *host;
    unsigned port;
    NSHTTPConnection *connection;
    NSDictionary *headers;
    unsigned status;

    if ([self status] != NSURLHandleNotLoaded)
        return [self propertyForKeyIfAvailable:key];

    request = [[NSHTTPRequest alloc] initWithMethod:@"GET" URL:_url];
    host = [_url host];
    if ([_url port] != nil)
        port = [[_url port] unsignedIntValue];
    else
        port = 80;
    connection = [NSHTTPConnection connectionForHost:host port:port];
    if (connection == nil)
        return nil;
    headers = nil;
    (void)[connection sendRequestSynchronously:request headers:&headers];
    status = [[headers objectForKey:NSHTTPPropertyStatusCodeKey] unsignedIntValue];

    if (_headers != nil) {
        [_headers release];
        _headers = [headers copy];
    }
    if (status < 300 || status >= 400) {
        if (_headers == nil)
            return [headers objectForKey:[key lowercaseString]];
        return [self propertyForKeyIfAvailable:key];
    }
    if ([key isEqualToString:NSHTTPPropertyRedirectionHeadersKey] && _headers == nil)
        return headers;

    _redirectedHandle = [[self redirectedHandleFromHeaders:headers] retain];
    if ([key isEqualToString:NSHTTPPropertyRedirectionHeadersKey])
        return _headers;
    if ([self inRedirectionLoop]) {
        return nil;
    }
    id redirectedValue = [_redirectedHandle propertyForKey:key];
    if (_headers == nil) {
        [_redirectedHandle release];
        _redirectedHandle = nil;
    }
    return redirectedValue;
}

- (id)propertyForKeyIfAvailable:(NSString *)key {
    if (_redirectedHandle != nil) {
        if ([key isEqualToString:NSHTTPPropertyRedirectionHeadersKey])
            return [_headers count] != 0 ? _headers : nil;
        return [_redirectedHandle propertyForKeyIfAvailable:key];
    }
    return [_headers objectForKey:[key lowercaseString]];
}

- (void)flushCachedData {
    [super flushCachedData];
    if (_headers != nil) {
        [_headers release];
        _headers = [[NSMutableDictionary alloc] init];
    }
    [_redirectedHandle release];
    _redirectedHandle = nil;
}

- (void)endLoadInBackground {
    if (_redirectedHandle != nil) {
        [_redirectedHandle endLoadInBackground];
    } else if (_connection != nil) {
        [_connection cancelFetchOfURL:_url];
        [_connection release];
        _connection = nil;
    }
}

- (NSData *)loadInForeground {
    NSString *host;
    unsigned port;

    if (_redirectedHandle != nil)
        return [_redirectedHandle resourceData];

    if (_connection == nil) {
        host = [_url host];
        if ([_url port] != nil)
            port = [[_url port] unsignedIntValue];
        else
            port = 80;
        _connection = [[NSHTTPConnection connectionForHost:host port:port] retain];
        if (_connection == nil)
            return nil;
    }

    NSHTTPRequest *request = [[NSHTTPRequest alloc] initWithMethod:@"GET" URL:_url];
    NSDictionary *headers = nil;
    NSData *data = [_connection sendRequestSynchronously:request headers:&headers];
    unsigned status = [[headers objectForKey:NSHTTPPropertyStatusCodeKey] unsignedIntValue];
    [request release];
    if (status >= 300 && status < 400) {
        _redirectedHandle = [[self redirectedHandleFromHeaders:headers] retain];
        if ([self inRedirectionLoop]) {
            data = nil;
        } else {
            data = [_redirectedHandle resourceData];
        }
        if (_headers == nil) {
            [_redirectedHandle release];
            _redirectedHandle = nil;
        }
        return data;
    }
    if (status >= 400)
        return nil;
    return data;
}

- (void)beginLoadInBackground {
    NSString *host;
    unsigned port;

    if (_redirectedHandle != nil) {
        [_redirectedHandle loadInBackground];
        return;
    }
    if (_connection != nil)
        return;
    if ([_url port] != nil)
        port = [[_url port] unsignedIntValue];
    else
        port = 80;
    host = [_url host];
    _connection = [[NSHTTPConnection connectionForHost:host port:port] retain];
    if (_connection == nil) {
        NSString *format = [_NSFoundationBundle() localizedStringForKey:
            @"Could not connect to host %@" value:@"" table:@"URL"];
        [self backgroundLoadDidFailWithReason:[NSString stringWithFormat:format,
            [_url host]]];
        return;
    }
    NSHTTPRequest *request = [[NSHTTPRequest alloc] initWithMethod:@"GET" URL:_url];
    [_connection enqueueRequest:request forClient:self];
    [request release];
}

- (NSHTTPURLHandle *)redirectedHandleFromHeaders:(NSDictionary *)headers {
    NSString *location = [headers objectForKey:@"Location"];
    if (location == nil)
        location = [headers objectForKey:@"location"];
    if (location == nil)
        return nil;
    NSURL *url = [NSURL URLWithString:location relativeToURL:_url];
    NSURL *canonical = [[self class] canonicalHTTPURLForURL:url];
    if (_headers != nil)
        return (NSHTTPURLHandle *)[[self class] cachedHandleForURL:canonical];
    return [[[[self class] alloc] initWithURL:canonical cached:NO] autorelease];
}

- (void)receivedHeaders:(NSDictionary *)headers forRequest:(id)request {
    unsigned status = [[headers objectForKey:NSHTTPPropertyStatusCodeKey] unsignedIntValue];
    if (status >= 200 && status < 300) {
        if (_headers != nil)
        {
            [_headers release];
            _headers = [headers copy];
        }
    } else if (status >= 300 && status < 400) {
        if (_headers != nil && headers != nil) {
            [_headers release];
            _headers = [headers copy];
        }
        _redirectedHandle = [[self redirectedHandleFromHeaders:headers] retain];
        if ([self inRedirectionLoop]) {
            NSString *format = [_NSFoundationBundle() localizedStringForKey:
            @"Detected a redirection loop while attempting to load URL %@"
            value:nil table:@"URL"];
            [self backgroundLoadDidFailWithReason:[NSString stringWithFormat:format, _url]];
        } else {
            [_redirectedHandle addClient:self];
            [_redirectedHandle loadInBackground];
        }
    } else if (status >= 400 && status <= 599) {
        NSString *reason = [headers objectForKey:NSHTTPPropertyStatusReasonKey];
        NSString *format = [_NSFoundationBundle() localizedStringForKey:
            @"HTTP request failed for URL %@:%@" value:nil table:@"URL"];
        [self backgroundLoadDidFailWithReason:[NSString stringWithFormat:format,
            _url, reason]];
    } else {
        NSLog(@"Received unknown HTTP server response %@: %@", _url,
            [headers objectForKey:NSHTTPPropertyStatusReasonKey]);
        NSString *reason = [_NSFoundationBundle() localizedStringForKey:
            @"Got unknown status code %d from HTTP background thread!"
            value:nil table:@"URL"];
        [self backgroundLoadDidFailWithReason:[NSString stringWithFormat:reason, status]];
        [(NSHTTPRequest *)request _setCondition:0];
    }
    if (status < 200 || status >= 300) {
        [_connection release];
        _connection = nil;
    }
}

- (void)receivedDataBlock:(NSData *)data forRequest:(id)request finished:(BOOL)finished {
    if ([self status] == NSURLHandleLoadInProgress) {
        [self didLoadBytes:data loadComplete:finished];
    } else if (_headers != nil) {
        NSMutableData *inProgressData =
            [_headers objectForKey:NSErrorPageInProgressKey];

        if (inProgressData != nil) {
            [inProgressData appendData:data];
            if (finished) {
                NSMutableDictionary *updatedHeaders = [_headers mutableCopy];
                NSMutableData *page = [[NSMutableData alloc]
                    initWithData:inProgressData];
                [updatedHeaders setObject:page
                    forKey:NSHTTPPropertyErrorPageDataKey];
                [updatedHeaders removeObjectForKey:NSErrorPageInProgressKey];
                [page release];
                [_headers release];
                _headers = [updatedHeaders copy];
                [updatedHeaders release];
            }
        } else {
            NSMutableDictionary *updatedHeaders = [_headers mutableCopy];
            if (finished) {
                [updatedHeaders setObject:data
                    forKey:NSHTTPPropertyErrorPageDataKey];
            } else {
                inProgressData = [[NSMutableData alloc] initWithData:data];
                [updatedHeaders setObject:inProgressData
                    forKey:NSErrorPageInProgressKey];
                [inProgressData release];
            }
            [_headers release];
            _headers = [updatedHeaders copy];
            [updatedHeaders release];
        }
    }
}

- (void)connectionFailedDuringRequest:(id)request {
    NSString *format = [_NSFoundationBundle() localizedStringForKey:
        @"Lost connection to host %@" value:@"" table:@"URL"];
    NSString *reason = [NSString stringWithFormat:format,
        [_connection description]];
    [self backgroundLoadDidFailWithReason:reason];
}

- (void)requestWasCancelled:(id)request {
}

- (void)URLHandle:(NSURLHandle *)sender resourceDataDidBecomeAvailable:(NSData *)data {
    [self didLoadBytes:data loadComplete:NO];
}

- (void)URLHandleResourceDidBeginLoading:(NSURLHandle *)sender {
}

- (void)URLHandleResourceDidFinishLoading:(NSURLHandle *)sender {
    [self didLoadBytes:nil loadComplete:YES];
    if (_headers == nil) {
        [_redirectedHandle release];
        _redirectedHandle = nil;
    }
}

- (void)URLHandleResourceDidCancelLoading:(NSURLHandle *)sender {
    [_clients makeObjectsPerformSelector:
        @selector(URLHandleResourceDidCancelLoading:) withObject:self];
    if (_headers == nil) {
        [_redirectedHandle release];
        _redirectedHandle = nil;
    }
}

- (void)URLHandle:(NSURLHandle *)sender resourceDidFailLoadingWithReason:(NSString *)reason {
    [self backgroundLoadDidFailWithReason:reason];
    if (_headers == nil) {
        [_redirectedHandle release];
        _redirectedHandle = nil;
    }
}

- (void)didLoadBytes:(NSData *)data loadComplete:(BOOL)complete {
    if (_headers != nil && _redirectedHandle != nil) {
        unsigned index, count = [_clients count];
        for (index = 0; index < count; ++index)
            [[_clients objectAtIndex:index]
                URLHandle:self resourceDataDidBecomeAvailable:data];
        if (complete) {
            [super didLoadBytes:nil loadComplete:YES];
        }
    } else {
        [super didLoadBytes:data loadComplete:complete];
    }
}

@end

#endif
