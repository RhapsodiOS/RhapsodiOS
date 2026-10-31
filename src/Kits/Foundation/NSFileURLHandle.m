/* Private file: URL resource handler. */

#import <Foundation/NSFileURLHandle.h>
#import <Foundation/NSBundle.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSFileHandle.h>
#import <Foundation/NSFileManager.h>
#import <Foundation/NSNotification.h>
#import <Foundation/NSPathUtilities.h>
#import <Foundation/NSString.h>
#import <Foundation/NSURL.h>

#if defined(__ppc__) || defined(__POWERPC__)

extern NSBundle *_NSFoundationBundle(void);

static NSMutableDictionary *fileURLHandleCache;

@implementation NSFileURLHandle

+ (void)initialize {
#if defined(__ppc__) || defined(__POWERPC__)
    fileURLHandleCache = [[NSMutableDictionary alloc] init];
#endif
}

+ (BOOL)canInitWithURL:(NSURL *)url {
#if defined(__ppc__) || defined(__POWERPC__)
    NSString *scheme = [url scheme];
    return scheme != nil && [scheme compare:@"file" options:NSCaseInsensitiveSearch] == NSOrderedSame;
#else
    return NO;
#endif
}

+ (NSURLHandle *)cachedHandleForURL:(NSURL *)url {
#if defined(__ppc__) || defined(__POWERPC__)
    NSString *path = [[[url absoluteURL] path] stringByStandardizingPath];
    NSFileURLHandle *handle = [fileURLHandleCache objectForKey:path];
    if (handle == nil) {
        handle = [[self alloc] initWithURL:url cached:YES];
        [fileURLHandleCache setObject:handle forKey:path];
        [handle loadInBackground];
    }
    return handle;
#else
    return nil;
#endif
}

- initWithURL:(NSURL *)url cached:(BOOL)cached {
#if defined(__ppc__) || defined(__POWERPC__)
    self = [super initWithURL:url cached:cached];
    if (self != nil) {
        _path = [[[url standardizedURL] path] retain];
        _fh = nil;
    }
    return self;
#else
    return nil;
#endif
}

- (void)dealloc {
#if defined(__ppc__) || defined(__POWERPC__)
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_path release];
    _path = nil;
    [_fh release];
    _fh = nil;
    [super dealloc];
#endif
}

- (NSData *)loadInForeground {
#if defined(__ppc__) || defined(__POWERPC__)
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:_path];
    if (handle == nil)
        return nil;
    NSData *data = [handle readDataToEndOfFile];
    [handle closeFile];
    return data;
#else
    return nil;
#endif
}

- (BOOL)writeData:(NSData *)data {
#if defined(__ppc__) || defined(__POWERPC__)
    BOOL written = [data writeToFile:_path atomically:YES];
    if (written)
        [self flushCachedData];
    return written;
#else
    return NO;
#endif
}

- (id)propertyForKey:(NSString *)key {
#if defined(__ppc__) || defined(__POWERPC__)
    if (_properties == nil) {
        NSDictionary *attributes = [[NSFileManager defaultManager]
            fileAttributesAtPath:_path traverseLink:NO];
        _properties = [attributes copy];
    }
    return [self propertyForKeyIfAvailable:key];
#else
    return nil;
#endif
}

- (id)propertyForKeyIfAvailable:(NSString *)key {
#if defined(__ppc__) || defined(__POWERPC__)
    return [_properties objectForKey:key];
#else
    return nil;
#endif
}

- (BOOL)writeProperty:(id)value forKey:(NSString *)key {
#if defined(__ppc__) || defined(__POWERPC__)
    NSDictionary *attributes = [[NSDictionary alloc]
        initWithObjectsAndKeys:value, key, nil];
    NSFileManager *manager = [NSFileManager defaultManager];
    BOOL success = [manager changeFileAttributes:attributes atPath:_path];
    [attributes release];

    if (_properties != nil && [_properties objectForKey:key] != value) {
        NSMutableDictionary *updated = [[NSMutableDictionary alloc]
            initWithDictionary:_properties];
        [updated setObject:value forKey:key];
        [_properties release];
        _properties = [[NSDictionary alloc] initWithDictionary:updated];
        [updated release];
    }
    return success;
#else
    return NO;
#endif
}

- (void)beginLoadInBackground {
#if defined(__ppc__) || defined(__POWERPC__)
    if (_fh == nil) {
        _fh = [NSFileHandle fileHandleForReadingAtPath:_path];
        if (_fh != nil) {
            [[NSNotificationCenter defaultCenter] addObserver:self
                selector:@selector(_backgroundFileLoadCompleted:)
                name:NSFileHandleReadToEndOfFileCompletionNotification object:_fh];
            [_fh readToEndOfFileInBackgroundAndNotify];
        } else {
            NSString *format = [_NSFoundationBundle() localizedStringForKey:
                @"Couldn't open" value:@"" table:nil];
            [self backgroundLoadDidFailWithReason:
                [NSString stringWithFormat:format, _path]];
        }
    }
#endif
}

- (void)endLoadInBackground {
#if defined(__ppc__) || defined(__POWERPC__)
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_fh closeFile];
    _fh = nil;
#endif
}

- (void)flushCachedData {
#if defined(__ppc__) || defined(__POWERPC__)
    if (_properties != nil) {
        [_properties release];
        _properties = nil;
    }
    [super flushCachedData];
#endif
}

- (void)_backgroundFileLoadCompleted:(NSNotification *)notification {
#if defined(__ppc__) || defined(__POWERPC__)
    NSData *data = [[notification userInfo] objectForKey:NSFileHandleNotificationDataItem];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self didLoadBytes:data loadComplete:YES];
    [_fh closeFile];
    _fh = nil;
#endif
}

@end

#endif
