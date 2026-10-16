/*	NSURL.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSURL.h>
#import <Foundation/NSFileManager.h>
#import <Foundation/NSString.h>
#import <Foundation/NSRange.h>
#import <Foundation/NSValue.h>
#import <Foundation/NSZone.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSException.h>
#import <Foundation/NSPathUtilities.h>
#import <Foundation/NSBundle.h>
#import <Foundation/NSMapTable.h>
#import <Foundation/NSCoder.h>

#if defined(__ppc__) || defined(__POWERPC__)
#define NSURLBaseURLIvar _baseURL
#else
#define NSURLBaseURLIvar _base
#endif

extern NSBundle *_NSFoundationBundle(void);

@interface NSString (NSURLPathSupport)
- (NSString *)stringByAddingPercentEscapes;
- (NSString *)stringByRemovingPercentEscapes;
- (NSString *)standardizedURLPath;
- (NSString *)standardizedNativePath;
@end
NSString *NSURLFileScheme = @"file";

static NSString *NSURLLocalHost = @"localhost";
extern id _NSMethodExceptionProem(id object, SEL aSelector);

@interface NSAbsoluteURL : NSURL {
@private
    NSString *_scheme;
}
- initWithString:(NSString *)URLString relativeToURL:(NSURL *)baseURL;
@end

typedef struct {
    NSRange scheme;
    NSRange user;
    NSRange password;
    NSRange host;
    NSRange port;
    NSRange path;
    NSRange parameters;
    NSRange query;
    NSRange fragment;
} NSURLComponents;

static NSRange NSURLMakeComponentRange(unsigned int start, unsigned int end) {
    return NSMakeRange(start, end - start);
}

int _NSParseStringToGenericURLComponents(NSString *string,
    NSRange *scheme, NSRange *user, NSRange *password, NSRange *host,
    NSRange *port, NSRange *path, NSRange *parameters, NSRange *query,
    NSRange *fragment) {
    unsigned length = [string length];
    unsigned end = length;
    unsigned start = 0;
    unsigned index;
    unsigned authorityEnd;
    unsigned hostStart;
    unsigned delimiter;
    unichar localCharacters[257];
    unichar *characters = localCharacters;

    if (length > 256)
        characters = NSZoneMalloc(NULL, sizeof(unichar) * (length + 1));
    [string getCharacters:characters range:NSMakeRange(0, length)];
    characters[length] = 0;

    if (scheme != NULL)
        *scheme = NSMakeRange(0, 0);
    if (user != NULL)
        *user = NSMakeRange(0, 0);
    if (password != NULL)
        *password = NSMakeRange(0, 0);
    if (host != NULL)
        *host = NSMakeRange(0, 0);
    if (port != NULL)
        *port = NSMakeRange(0, 0);
    if (path != NULL)
        *path = NSMakeRange(0, 0);
    if (parameters != NULL)
        *parameters = NSMakeRange(0, 0);
    if (query != NULL)
        *query = NSMakeRange(0, 0);
    if (fragment != NULL) {
#if defined(__ppc__) || defined(__POWERPC__)
        *fragment = NSMakeRange(length, 0);
#else
        *fragment = NSMakeRange(0, 0);
#endif
    }

    for (index = 0; index < end; index++) {
        unichar character = characters[index];

        if (character == '#') {
            if (fragment != NULL)
                *fragment = NSURLMakeComponentRange(index + 1, end);
            end = index;
            break;
        }
    }

    for (index = 0; index < end; index++) {
        unichar character = characters[index];

        if (character == ':') {
            if (scheme != NULL)
                *scheme = NSURLMakeComponentRange(0, index);
            start = index + 1;
            break;
        }
        if (!((character >= 'a' && character <= 'z')
              || (character >= 'A' && character <= 'Z')
              || (character >= '-' && character <= '.')
              || character == '+'))
            break;
    }

#if defined(__ppc__) || defined(__POWERPC__)
    if (user != NULL)
        *user = NSMakeRange(start, 0);
    if (password != NULL)
        *password = NSMakeRange(start, 0);
    if (host != NULL)
        *host = NSMakeRange(start, 0);
    if (port != NULL)
        *port = NSMakeRange(start, 0);
#endif

    if (end - start > 1 && characters[start] == '/'
        && characters[start + 1] == '/') {
        unsigned authorityStart = start + 2;

        authorityEnd = authorityStart;
        while (authorityEnd < end
               && characters[authorityEnd] != '/')
            authorityEnd++;
        hostStart = authorityStart;
#if defined(__ppc__) || defined(__POWERPC__)
        if (user != NULL)
            *user = NSMakeRange(authorityStart, 0);
        if (password != NULL)
            *password = NSMakeRange(authorityStart, 0);
#endif
        for (index = authorityStart; index < authorityEnd; index++) {
            if (characters[index] == '@') {
                unsigned userInfoColon = authorityStart;

                while (userInfoColon < index
                       && characters[userInfoColon] != ':')
                    userInfoColon++;
                if (userInfoColon < index) {
                    if (user != NULL)
                        *user = NSURLMakeComponentRange(authorityStart,
                                                        userInfoColon);
                    if (password != NULL)
                        *password = NSURLMakeComponentRange(userInfoColon + 1,
                                                           index);
                } else if (user != NULL) {
                    *user = NSURLMakeComponentRange(authorityStart, index);
                }
#if defined(__ppc__) || defined(__POWERPC__)
                if (userInfoColon == index && password != NULL)
                    *password = NSMakeRange(index, 0);
#endif
                hostStart = index + 1;
                break;
            }
        }
#if defined(__ppc__) || defined(__POWERPC__)
        if (host != NULL)
            *host = NSMakeRange(hostStart, 0);
        if (port != NULL)
            *port = NSMakeRange(authorityEnd, 0);
#endif
        for (index = hostStart; index < authorityEnd; index++) {
            if (characters[index] == ':') {
                if (host != NULL)
                    *host = NSURLMakeComponentRange(hostStart, index);
                if (port != NULL)
                    *port = NSURLMakeComponentRange(index + 1, authorityEnd);
                break;
            }
        }
        if (index == authorityEnd && host != NULL)
            *host = NSURLMakeComponentRange(hostStart, authorityEnd);
        start = authorityEnd;
    }

#if defined(__ppc__) || defined(__POWERPC__)
    if (query != NULL)
        *query = NSMakeRange(end, 0);
#endif
    for (index = start; index < end; index++) {
        if (characters[index] == '?') {
            if (query != NULL)
                *query = NSURLMakeComponentRange(index + 1, end);
            end = index;
            break;
        }
    }
#if defined(__ppc__) || defined(__POWERPC__)
    if (parameters != NULL)
        *parameters = NSMakeRange(end, 0);
#endif
    for (index = start; index < end; index++) {
        if (characters[index] == ';') {
            if (parameters != NULL)
                *parameters = NSURLMakeComponentRange(index + 1, end);
            end = index;
            break;
        }
    }
    if (path != NULL)
        *path = NSURLMakeComponentRange(start, end);
    if (characters != localCharacters)
        NSZoneFree(NULL, characters);
    return 1;
}

static void NSURLParseComponents(NSString *string, NSURLComponents *components) {
    (void)_NSParseStringToGenericURLComponents(string, &components->scheme,
        &components->user, &components->password, &components->host,
        &components->port, &components->path, &components->parameters,
        &components->query, &components->fragment);

    if (components->scheme.length == 0)
        components->scheme.location = NSNotFound;
#if defined(__ppc__) || defined(__POWERPC__)
    if (components->user.length == 0)
        components->user.location = NSNotFound;
    if (components->password.length == 0)
        components->password.location = NSNotFound;
    if (components->host.length == 0)
        components->host.location = NSNotFound;
    if (components->port.length == 0)
        components->port.location = NSNotFound;
    if (components->parameters.length == 0)
        components->parameters.location = NSNotFound;
    if (components->query.length == 0)
        components->query.location = NSNotFound;
    if (components->fragment.length == 0)
        components->fragment.location = NSNotFound;
#else
    if (components->user.location == 0 && components->user.length == 0)
        components->user.location = NSNotFound;
    if (components->password.location == 0 && components->password.length == 0)
        components->password.location = NSNotFound;
    if (components->host.location == 0 && components->host.length == 0)
        components->host.location = NSNotFound;
    if (components->port.location == 0 && components->port.length == 0)
        components->port.location = NSNotFound;
    if (components->parameters.location == 0 && components->parameters.length == 0)
        components->parameters.location = NSNotFound;
    if (components->query.location == 0 && components->query.length == 0)
        components->query.location = NSNotFound;
    if (components->fragment.location == 0 && components->fragment.length == 0)
        components->fragment.location = NSNotFound;
#endif
}

static NSString *NSURLStringForComponent(NSString *string, NSRange range) {
    if (range.location == NSNotFound || range.length == 0)
        return nil;
    return [string substringWithRange:range];
}

#if defined(__ppc__) || defined(__POWERPC__)
static NSString *NSURLStandardizedPathFromComponents(NSArray *components) {
    NSMutableArray *pathComponents = [[NSMutableArray allocWithZone:NULL]
        initWithArray:components];
    unsigned index = 0;
    NSString *firstComponent;
    NSString *lastComponent;
    NSString *path;

    while (index < [pathComponents count]) {
        NSString *component = [pathComponents objectAtIndex:index];

        if ([component isEqualToString:@"."]) {
            [pathComponents removeObjectAtIndex:index];
        } else if ([component isEqualToString:@".."] && index != 0
                   && ![[pathComponents objectAtIndex:index - 1]
                       isEqualToString:@".."] ) {
            [pathComponents removeObjectAtIndex:index];
            [pathComponents removeObjectAtIndex:--index];
        } else {
            index++;
        }
    }

    firstComponent = [pathComponents objectAtIndex:0];
    if ([firstComponent length] != 0) {
        lastComponent = [pathComponents lastObject];
        if ([lastComponent length] != 0) {
            path = [pathComponents componentsJoinedByString:@"/"];
        } else {
            [pathComponents removeLastObject];
            path = [NSString stringWithFormat:@"%@/",
                    [pathComponents componentsJoinedByString:@"/"]];
        }
    } else {
        [pathComponents removeObjectAtIndex:0];
        lastComponent = [pathComponents lastObject];
        if ([lastComponent length] != 0) {
            path = [NSString stringWithFormat:@"/%@",
                    [pathComponents componentsJoinedByString:@"/"]];
        } else {
            [pathComponents removeLastObject];
            path = [NSString stringWithFormat:@"/%@/",
                    [pathComponents componentsJoinedByString:@"/"]];
        }
    }
    [pathComponents release];
    return path;
}
#endif

#if defined(__ppc__) || defined(__POWERPC__)
static void NSURLNotifyClientsAndRemoveHandle(NSURL *URL, NSURLHandle *handle,
    SEL selector, NSString *reason, BOOL enumerateFirst,
    NSMapTable **clientsAddress) {
    NSMapTable *clients = *clientsAddress;
    NSMutableArray *matchingClients;
    NSMapEnumerator enumerator;
    void *key;
    void *value;
    unsigned count;
    unsigned index;

    if (clients == NULL)
        return;
    if (enumerateFirst)
        enumerator = NSEnumerateMapTable(clients);
    matchingClients = [[NSMutableArray alloc] init];
    if (!enumerateFirst)
        enumerator = NSEnumerateMapTable(clients);
    while (NSNextMapEnumeratorPair(&enumerator, &key, &value)) {
        if (value == handle)
            [matchingClients addObject:(id)key];
    }
    count = [matchingClients count];
    for (index = 0; index < count; index++) {
        id client = [matchingClients objectAtIndex:index];

        if ([client respondsToSelector:selector]) {
            if (selector == @selector(URL:resourceDidFailLoadingWithReason:))
                [client performSelector:selector withObject:URL
                    withObject:reason];
            else
                [client performSelector:selector withObject:URL];
        }
        NSMapRemove(clients, client);
    }
    [handle removeClient:URL];
    if (NSCountMapTable(clients) == 0) {
        NSFreeMapTable(clients);
        *clientsAddress = NULL;
    }
    [matchingClients release];
}
#endif

@implementation NSURL

- initWithScheme:(NSString *)scheme host:(NSString *)host path:(NSString *)path {
    NSString *URLString;
    NSString *escapedScheme;
    NSString *escapedHost;

    if (![path isAbsolutePath]) {
        [NSException raise:NSInvalidArgumentException
                    format:@"%@: path %@ is not absolute.",
         _NSMethodExceptionProem(self, _cmd), path];
        return nil;
    }
#if defined(__ppc__) || defined(__POWERPC__)
    escapedScheme = [scheme stringByAddingPercentEscapes];
    escapedHost = [host stringByAddingPercentEscapes];
    path = [path standardizedURLPath];
    if (escapedScheme == nil || escapedHost == nil || path == nil) {
        [self release];
        return nil;
    }
#else
    path = [path standardizedURLPath];
    escapedHost = [host stringByAddingPercentEscapes];
    escapedScheme = [scheme stringByAddingPercentEscapes];
#endif
    URLString = [NSString stringWithFormat:@"%@://%@%@", escapedScheme,
                 escapedHost, path];
    return [self initWithString:URLString];
}

- initFileURLWithPath:(NSString *)path {
    BOOL isDirectory;

    if (path == nil || [path length] == 0) {
        [NSException raise:NSInvalidArgumentException
                    format:@"-[NSURL initFileURLWithPath:]: must supply a non-empty path"];
        return nil;
    }
    if (![path isAbsolutePath]) {
        path = [path stringByStandardizingPath];
    }
    if ([path characterAtIndex:[path length] - 1] != '/') {
#if defined(__ppc__) || defined(__POWERPC__)
        if ([[NSFileManager defaultManager] fileExistsAtPath:path
                                                 isDirectory:&isDirectory]
            && isDirectory)
#else
        [[NSFileManager defaultManager] fileExistsAtPath:path
                                             isDirectory:&isDirectory];
        if (isDirectory)
#endif
            path = [path stringByAppendingString:@"/"];
    }
    if ([path isAbsolutePath])
        return [self initWithScheme:NSURLFileScheme host:NSURLLocalHost path:path];
    NSString *URLString = [path standardizedURLPath];
#if defined(__ppc__) || defined(__POWERPC__)
    if (URLString == nil) {
        [self release];
        return nil;
    }
#endif
    return [self initWithString:URLString];
}

+ (id)fileURLWithPath:(NSString *)path {
    return [[[self alloc] initFileURLWithPath:path] autorelease];
}

- initWithString:(NSString *)URLString {
    return [self initWithString:URLString relativeToURL:nil];
}

- initWithString:(NSString *)URLString relativeToURL:(NSURL *)baseURL {
    NSURLComponents components;

    if (URLString == nil) {
        [NSException raise:NSInvalidArgumentException
                    format:@"%@: string must be non-nil.",
         _NSMethodExceptionProem(self, _cmd)];
        return nil;
    }
    NSURLParseComponents(URLString, &components);
    if (components.scheme.length != 0) {
        [self release];
        return [[NSAbsoluteURL allocWithZone:NULL]
            initWithString:URLString relativeToURL:nil];
    }
    self = [super init];
    if (self != nil) {
        _urlString = [[NSString stringWithString:URLString] retain];
        NSURLBaseURLIvar = [baseURL retain];
    }
    return self;
}

#if defined(__ppc__) || defined(__POWERPC__)
- initWithCoder:(NSCoder *)coder {
    char hasBaseURL = NO;
    NSURL *baseURL = nil;
    NSString *relativeString;

    [coder decodeValueOfObjCType:@encode(char) at:&hasBaseURL];
    if (hasBaseURL)
        baseURL = [coder decodeObject];
    relativeString = [coder decodeObject];
    return [self initWithString:relativeString relativeToURL:baseURL];
}

- (void)encodeWithCoder:(NSCoder *)coder {
    char hasBaseURL = NSURLBaseURLIvar != nil;

    [coder encodeValueOfObjCType:@encode(char) at:&hasBaseURL];
    if (NSURLBaseURLIvar != nil)
        [coder encodeObject:NSURLBaseURLIvar];
    [coder encodeObject:[self relativeString]];
}
#endif

+ (id)URLWithString:(NSString *)URLString {
    return [[[self alloc] initWithString:URLString] autorelease];
}

+ (id)URLWithString:(NSString *)URLString relativeToURL:(NSURL *)baseURL {
    return [[[self alloc] initWithString:URLString relativeToURL:baseURL] autorelease];
}

- (NSString *)absoluteString {
    NSURL *baseURL = [self baseURL];
    NSString *relativeString = [self relativeString];
    NSString *baseString;
    NSURLComponents baseComponents;
    NSURLComponents relativeComponents;
    NSString *basePrefix;
    unsigned int basePathEnd;
    unsigned int relativePathEnd;

    if (baseURL == nil
        || !_NSParseStringToGenericURLComponents(relativeString,
            &relativeComponents.scheme, NULL, NULL, NULL, NULL,
            &relativeComponents.path, &relativeComponents.parameters,
            &relativeComponents.query, &relativeComponents.fragment)
        || relativeComponents.scheme.length != 0)
        return relativeString;

    baseString = [baseURL relativeString];
    if (!_NSParseStringToGenericURLComponents(baseString,
            &baseComponents.scheme, NULL, NULL, NULL, NULL,
            &baseComponents.path, &baseComponents.parameters,
            &baseComponents.query, &baseComponents.fragment))
        return relativeString;

    if (relativeComponents.path.location != 0) {
        if (baseComponents.scheme.length == 0)
            return relativeString;
        return [NSString stringWithFormat:@"%@:%@",
            NSURLStringForComponent(baseString, baseComponents.scheme), relativeString];
    }

    basePathEnd = baseComponents.path.location + baseComponents.path.length;
    if (relativeComponents.path.length != 0) {
        basePrefix = [baseString substringToIndex:baseComponents.path.location];
        if ([relativeString characterAtIndex:relativeComponents.path.location] == '/')
            return [basePrefix stringByAppendingString:relativeString];

        relativePathEnd = relativeComponents.path.location + relativeComponents.path.length;
        return [NSString stringWithFormat:@"%@%@%@", basePrefix,
            [self _absoluteURLPath], [relativeString substringFromIndex:relativePathEnd]];
    }

    if (relativeComponents.parameters.length != 0) {
        basePrefix = [baseString substringToIndex:basePathEnd];
        return [NSString stringWithFormat:@"%@;%@", basePrefix,
            [relativeString substringFromIndex:relativeComponents.parameters.location]];
    }
    if (relativeComponents.query.length != 0) {
        basePrefix = [baseString substringToIndex:basePathEnd];
        return [NSString stringWithFormat:@"%@?%@", basePrefix,
            [relativeString substringFromIndex:relativeComponents.query.location]];
    }

#if defined(__ppc__) || defined(__POWERPC__)
    basePrefix = [baseString substringToIndex:basePathEnd];
    return [NSString stringWithFormat:@"%@%@", basePrefix, relativeString];
#else
    basePathEnd = baseComponents.query.location + baseComponents.query.length;
    basePrefix = [baseString substringToIndex:basePathEnd];
    return [NSString stringWithFormat:@"%@%@", basePrefix, relativeString];
#endif
}

- (NSString *)relativeString { // The relative portion of a URL. If baseURL is nil, or if the receiver is itself absolute, this is the same as absoluteString.
    return _urlString;
}

- (NSString *)_relativeURLPath {
    NSURLComponents components;

    NSURLParseComponents(_urlString, &components);
    if (components.path.length == 0) {
#if defined(__ppc__) || defined(__POWERPC__)
        if ([self baseURL] == nil
            && [[self resourceSpecifier] hasPrefix:@"//"])
            return @"/";
#endif
        return nil;
    }
    return [_urlString substringWithRange:components.path];
}

- (NSString *)_absoluteURLPath {
    NSString *relativePath = [self _relativeURLPath];
    NSURL *baseURL = [self baseURL];
    NSURLComponents components;
    NSMutableArray *pathComponents;
#if !defined(__ppc__) && !defined(__POWERPC__)
    unsigned int index;
#endif
#if defined(__ppc__) || defined(__POWERPC__)
    NSString *basePath;
    NSString *absolutePath;
#endif

    NSURLParseComponents([self relativeString], &components);
    if (baseURL == nil || components.scheme.location != NSNotFound)
        return relativePath;
    if (relativePath == nil || [relativePath length] == 0)
        return [baseURL _relativeURLPath];
    if ([relativePath characterAtIndex:0] == '/')
        return relativePath;

#if defined(__ppc__) || defined(__POWERPC__)
    basePath = [baseURL _relativeURLPath];
    if (basePath == nil) {
        pathComponents = [[NSMutableArray alloc] init];
    } else {
        pathComponents = [[NSMutableArray alloc]
            initWithArray:[basePath componentsSeparatedByString:@"/"]];
        if ([pathComponents count] != 0)
            [pathComponents removeLastObject];
    }
#else
    pathComponents = [NSMutableArray arrayWithArray:
        [[baseURL _relativeURLPath] componentsSeparatedByString:@"/"]];
    [pathComponents removeLastObject];
#endif
    [pathComponents addObjectsFromArray:
        [relativePath componentsSeparatedByString:@"/"]];
#if defined(__ppc__) || defined(__POWERPC__)
    absolutePath = NSURLStandardizedPathFromComponents(pathComponents);
    [pathComponents release];
    return absolutePath;
#else
    index = 0;
    while (index < [pathComponents count]) {
        NSString *component = [pathComponents objectAtIndex:index];

        if ([component isEqualToString:@"."]) {
            [pathComponents removeObjectAtIndex:index];
        } else if (![component isEqualToString:@".."] || index == 0
                   || [[pathComponents objectAtIndex:index - 1]
                       isEqualToString:@".."]) {
            index++;
        } else {
            [pathComponents removeObjectAtIndex:index];
            [pathComponents removeObjectAtIndex:index - 1];
            index--;
        }
    }

    if ([[pathComponents objectAtIndex:0] length] == 0) {
        [pathComponents removeObjectAtIndex:0];
        if ([[pathComponents lastObject] length] != 0)
            return [NSString stringWithFormat:@"/%@",
                [pathComponents componentsJoinedByString:@"/"]];
        [pathComponents removeAllObjects];
        return [NSString stringWithFormat:@"/%@/",
            [pathComponents componentsJoinedByString:@"/"]];
    }
    if ([[pathComponents lastObject] length] == 0) {
        [pathComponents removeAllObjects];
        return [NSString stringWithFormat:@"%@/",
            [pathComponents componentsJoinedByString:@"/"]];
    }
    return [pathComponents componentsJoinedByString:@"/"];
#endif
}

- (NSURL *)baseURL { // May be nil.
    return NSURLBaseURLIvar;
}

- (NSURL *)absoluteURL { // If the receiver is itself absolute, this returns self.
    NSURL *absoluteURL;

    if ([self baseURL] == nil)
        return self;
    absoluteURL = [[NSAbsoluteURL alloc] initWithString:[self absoluteString]
                                           relativeToURL:nil];
#if defined(__ppc__) || defined(__POWERPC__)
    return [absoluteURL autorelease];
#else
    return absoluteURL;
#endif
}

- (NSString *)scheme {
    return [[self baseURL] scheme];
}

- (NSString *)resourceSpecifier {
    return [self relativeString];
}

- (NSString *)host {
    NSURLComponents components;

    NSURLParseComponents(_urlString, &components);
    if (components.host.location == NSNotFound) {
        if (components.path.location == 0)
            return [[self baseURL] host];
        return nil;
    }
    return [NSURLStringForComponent(_urlString, components.host) stringByRemovingPercentEscapes];
}

- (NSNumber *)port {
    NSURLComponents components;
    NSString *portString;

    NSURLParseComponents(_urlString, &components);
    if (components.port.location == NSNotFound) {
        if (components.path.location == 0)
            return [[self baseURL] port];
        return nil;
    }
    portString = NSURLStringForComponent(_urlString, components.port);
    if (portString == nil)
        return nil;
    return [NSNumber numberWithInt:[portString intValue]];
}

- (NSString *)user {
    NSURLComponents components;

    NSURLParseComponents(_urlString, &components);
    if (components.user.location == NSNotFound) {
        if (components.path.location == 0)
            return [[self baseURL] user];
        return nil;
    }
    return [NSURLStringForComponent(_urlString, components.user) stringByRemovingPercentEscapes];
}

- (NSString *)password {
    NSURLComponents components;

    NSURLParseComponents(_urlString, &components);
    if (components.password.location == NSNotFound) {
        if (components.path.location == 0)
            return [[self baseURL] password];
        return nil;
    }
    return NSURLStringForComponent(_urlString, components.password);
}

- (NSString *)path {
    return [[self _absoluteURLPath] standardizedNativePath];
}

- (NSString *)fragment {
    NSURLComponents components;

    NSURLParseComponents(_urlString, &components);
    return [NSURLStringForComponent(_urlString, components.fragment) stringByRemovingPercentEscapes];
}

- (NSString *)parameterString {
    NSRange parameters;

    if (!_NSParseStringToGenericURLComponents(_urlString, NULL, NULL, NULL,
            NULL, NULL, NULL, &parameters, NULL, NULL))
        return nil;
    if (parameters.length != 0)
        return [_urlString substringWithRange:parameters];
    if (parameters.location != 0)
        return nil;
    return [[self baseURL] parameterString];
}

- (NSString *)query {
    NSRange query;

    if (!_NSParseStringToGenericURLComponents(_urlString, NULL, NULL, NULL,
            NULL, NULL, NULL, NULL, &query, NULL))
        return nil;
    if (query.length != 0)
        return [_urlString substringWithRange:query];
    if (query.location != 0)
        return nil;
    return [[self baseURL] query];
}

- (NSString *)relativePath { // The same as path if baseURL is nil.
#if defined(__ppc__) || defined(__POWERPC__)
    return [[self _relativeURLPath] standardizedNativePath];
#else
    NSURLComponents components;

    NSURLParseComponents(_urlString, &components);
    if (components.path.location == NSNotFound || components.path.length == 0)
        return nil;
    return [[_urlString substringWithRange:components.path] standardizedNativePath];
#endif
}

- (BOOL)isFileURL { // Whether the scheme is file:; if YES, [path] is suitable for NSFileManager or NSPathUtilities.
    return [[self scheme] isEqualToString:NSURLFileScheme];
}

- (id)copyWithZone:(NSZone *)zone {
    return [self retain];
}

#if defined(__ppc__) || defined(__POWERPC__)
- (BOOL)isEqual:(id)object {
    NSURL *otherURL;
    NSURL *otherBaseURL;
    NSURL *baseURL;

    if (![object isKindOfClass:[NSURL class]])
        return NO;
    otherURL = object;
    otherBaseURL = [otherURL baseURL];
    baseURL = [self baseURL];
    if (otherBaseURL != nil) {
        if (baseURL == nil || ![otherBaseURL isEqual:baseURL])
            return NO;
    } else if (baseURL != nil) {
        return NO;
    }
    return [[self relativeString] isEqual:[otherURL relativeString]];
}

- (NSURL *)URLRelativeToBaseURL:(NSURL *)baseURL {
    NSURL *absoluteURL = [self absoluteURL];
    NSURL *absoluteBaseURL = [baseURL absoluteURL];
    NSString *scheme = [absoluteURL scheme];
    NSString *baseScheme = [absoluteBaseURL scheme];
    NSString *host = [absoluteURL host];
    NSString *baseHost = [absoluteBaseURL host];
    NSString *relativeString = [absoluteURL relativeString];
    NSString *baseRelativeString = [absoluteBaseURL relativeString];
    NSString *relativePath;
    NSString *standardizedPath;
    NSRange pathRange;

    if ((scheme != nil && baseScheme == nil)
            || (scheme == nil && baseScheme != nil))
        return absoluteURL;
    if ([scheme caseInsensitiveCompare:baseScheme] != NSOrderedSame)
        return absoluteURL;
    if ((host != nil && baseHost == nil) || (host == nil && baseHost != nil))
        return absoluteURL;
    if ([host caseInsensitiveCompare:baseHost] != NSOrderedSame)
        return absoluteURL;
    if ([relativeString isEqual:baseRelativeString])
        return absoluteURL;

    relativePath = [[absoluteURL path] urlPathRelativeToPath:[absoluteBaseURL path]];
    _NSParseStringToGenericURLComponents(relativeString, NULL, NULL, NULL,
        NULL, NULL, &pathRange, NULL, NULL, NULL);
    standardizedPath = [relativePath standardizedURLPath];
    if (standardizedPath == nil)
        return absoluteURL;
    if (NSMaxRange(pathRange) < [relativeString length])
        standardizedPath = [standardizedPath stringByAppendingString:
            [relativeString substringFromIndex:NSMaxRange(pathRange)]];
    return [NSURL URLWithString:standardizedPath relativeToURL:absoluteBaseURL];
}

- (unsigned int)hash {
    return [[self relativeString] hash];
}
#endif

- (NSString *)description {
    if ([self baseURL] == nil)
        return [self relativeString];
    return [NSString stringWithFormat:@"%@ -- %@", [self relativeString],
            [self baseURL]];
}

- (void)dealloc {
    [_urlString release];
    [NSURLBaseURLIvar release];
    [super dealloc];
}

#if defined(__ppc__) || defined(__POWERPC__)
- (NSURL *)standardizedURL {
    NSString *string = [self absoluteString];
    NSURLComponents components;
    NSString *path;
    NSString *standardizedPath;
    NSString *prefix;
    NSString *suffix;
    NSString *standardizedString;

    NSURLParseComponents(string, &components);
    path = [string substringWithRange:components.path];
    standardizedPath = NSURLStandardizedPathFromComponents(
        [path componentsSeparatedByString:@"/"]);
    prefix = [string substringToIndex:components.path.location];
    suffix = [string substringFromIndex:NSMaxRange(components.path)];
    standardizedString = [NSString stringWithFormat:@"%@%@%@", prefix,
        standardizedPath, suffix];
    return [NSURL URLWithString:standardizedString];
}
#endif

// Blocks to load the data if necessary. A cached equivalent URL's data is
// returned when shouldUseCache is YES; NO starts a new load.
- (NSData *)resourceDataUsingCache:(BOOL)shouldUseCache {
#if defined(__ppc__) || defined(__POWERPC__)
    NSURLHandle *handle = [self URLHandleUsingCache:shouldUseCache];
    return [handle resourceData];
#else
    // TODO: Implement this method
    return nil;
#endif
}

// Starts an asynchronous load and registers the client for notifications.
// Only one such background load can proceed at a time.
- (void)loadResourceDataNotifyingClient:(id)client usingCache:(BOOL)shouldUseCache {
#if defined(__ppc__) || defined(__POWERPC__)
    NSURLHandle *handle = [self URLHandleUsingCache:shouldUseCache];
    SEL dataSelector = @selector(URL:resourceDataDidBecomeAvailable:);
    SEL finishSelector = @selector(URLResourceDidFinishLoading:);
    SEL failureSelector = @selector(URL:resourceDidFailLoadingWithReason:);

    if (handle == nil) {
        if ([client respondsToSelector:failureSelector]) {
            NSString *reason = [NSString stringWithFormat:
                [_NSFoundationBundle() localizedStringForKey:
                    @"Don't know how to load URL %@" value:nil table:@"URL"], self];
            [client URL:self resourceDidFailLoadingWithReason:reason];
        }
        return;
    }

    switch ([handle status]) {
        case NSURLHandleLoadSucceeded:
            if ([client respondsToSelector:dataSelector])
                [client URL:self resourceDataDidBecomeAvailable:
                    [handle availableResourceData]];
            if ([client respondsToSelector:finishSelector])
                [client URLResourceDidFinishLoading:self];
            break;
        case NSURLHandleLoadInProgress:
            if ([client respondsToSelector:dataSelector])
                [client URL:self resourceDataDidBecomeAvailable:
                    [handle availableResourceData]];
            if (_clients == NULL)
                _clients = NSCreateMapTableWithZone(NSObjectMapKeyCallBacks,
                    NSObjectMapValueCallBacks, 10, [self zone]);
            NSMapInsert((NSMapTable *)_clients, client, handle);
            [handle addClient:self];
            break;
        case NSURLHandleNotLoaded:
            if (_clients == NULL)
                _clients = NSCreateMapTableWithZone(NSObjectMapKeyCallBacks,
                    NSObjectMapValueCallBacks, 10, [self zone]);
            NSMapInsert((NSMapTable *)_clients, client, handle);
            [handle addClient:self];
            [handle loadInBackground];
            break;
        case NSURLHandleLoadFailed:
            if ([client respondsToSelector:failureSelector])
                [client URL:self resourceDidFailLoadingWithReason:
                    [handle failureReason]];
            break;
        default:
            NSLog(@"Encountered unknown NSURLHandle status value %d",
                [handle status]);
            break;
    }
#else
    // TODO: Implement this method
#endif
}


- (id)propertyForKey:(NSString *)propertyKey {
#if defined(__ppc__) || defined(__POWERPC__)
    NSURLHandle *handle = [self URLHandleUsingCache:NO];
    return [handle propertyForKey:propertyKey];
#else
    // TODO: Implement this method
    return nil;
#endif
}

- (BOOL)setResourceData:(NSData *)data {
#if defined(__ppc__) || defined(__POWERPC__)
    NSURLHandle *handle = [self URLHandleUsingCache:YES];
    return [handle writeData:data];
#else
    // TODO: Implement this method
    return NO;
#endif
}

- (BOOL)setProperty:(id)property forKey:(NSString *)propertyKey {
#if defined(__ppc__) || defined(__POWERPC__)
    NSURLHandle *handle = [self URLHandleUsingCache:YES];
    return [handle writeProperty:property forKey:propertyKey];
#else
    // TODO: Implement this method
    return NO;
#endif
}

// Sophisticated clients can request the handle directly. NO creates a new
// handle even if an equivalent URL has been loaded.
- (NSURLHandle *)URLHandleUsingCache:(BOOL)shouldUseCache {
#if defined(__ppc__) || defined(__POWERPC__)
    Class handleClass = [NSURLHandle URLHandleClassForURL:self];

    if (handleClass == Nil)
        return nil;
    if (shouldUseCache)
        return [handleClass cachedHandleForURL:self];
    return [[[handleClass alloc] initWithURL:self cached:NO] autorelease];
#else
    // TODO: Implement this method
    return nil;
#endif
}

#if defined(__ppc__) || defined(__POWERPC__)

- (void)URLHandle:(NSURLHandle *)sender
    resourceDataDidBecomeAvailable:(NSData *)newBytes {
    NSMapTable *clients = (NSMapTable *)_clients;
    NSMapEnumerator enumerator;
    void *key;
    void *value;

    if (clients == NULL)
        return;
    enumerator = NSEnumerateMapTable(clients);
    while (NSNextMapEnumeratorPair(&enumerator, &key, &value)) {
        if (value == sender &&
            [(id)key respondsToSelector:
                @selector(URL:resourceDataDidBecomeAvailable:)])
            [(id)key URL:self resourceDataDidBecomeAvailable:newBytes];
    }
}

- (void)URLHandleResourceDidBeginLoading:(NSURLHandle *)sender {
}

- (void)URLHandleResourceDidFinishLoading:(NSURLHandle *)sender {
    NSURLNotifyClientsAndRemoveHandle(self, sender,
        @selector(URLResourceDidFinishLoading:), nil, NO,
        (NSMapTable **)&_clients);
}

- (void)URLHandleResourceDidCancelLoading:(NSURLHandle *)sender {
    NSURLNotifyClientsAndRemoveHandle(self, sender,
        @selector(URLResourceDidCancelLoading:), nil, YES,
        (NSMapTable **)&_clients);
}

- (void)URLHandle:(NSURLHandle *)sender
    resourceDidFailLoadingWithReason:(NSString *)reason {
    NSURLNotifyClientsAndRemoveHandle(self, sender,
        @selector(URL:resourceDidFailLoadingWithReason:), reason,
        NO, (NSMapTable **)&_clients);
}
#endif
@end

@implementation NSAbsoluteURL

- initWithString:(NSString *)URLString relativeToURL:(NSURL *)baseURL {
    NSURLComponents components;
    NSString *scheme;
    NSString *relativeString;

    if (baseURL != nil) {
#if defined(__ppc__) || defined(__POWERPC__)
        [NSException raise:NSInvalidArgumentException
                    format:@"%@: illegal to provide a non-nil base URL parameter when creating an absolute URL.",
         _NSMethodExceptionProem(self, _cmd)];
#else
        [NSException raise:NSInvalidArgumentException
                    format:@"%@: illegal to provide a non-nil base URL when creating an absolute URL.",
         _NSMethodExceptionProem(self, _cmd)];
#endif
        return nil;
    }
    NSURLParseComponents(URLString, &components);
    if (components.scheme.length == 0) {
        [NSException raise:NSInvalidArgumentException
                    format:@"%@: must provide a scheme when creating an absolute URL",
         _NSMethodExceptionProem(self, _cmd)];
        return nil;
    }
    scheme = [URLString substringToIndex:
        components.scheme.location + components.scheme.length];
    relativeString = [URLString substringFromIndex:
        components.scheme.location + components.scheme.length + 1];
    self = [super initWithString:relativeString relativeToURL:nil];
    if (self != nil)
        _scheme = [scheme retain];
    return self;
}

- (void)dealloc {
    [_scheme release];
    [super dealloc];
}

- (NSURL *)baseURL {
    return nil;
}

- (NSString *)scheme {
    return [_scheme stringByRemovingPercentEscapes];
}

- (NSString *)relativeString {
    return [NSString stringWithFormat:@"%@:%@", _scheme, [super relativeString]];
}

- (NSString *)resourceSpecifier {
    return [super relativeString];
}

@end
