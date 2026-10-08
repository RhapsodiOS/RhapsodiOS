#ifndef TERMINAL_SERVICES_H
#define TERMINAL_SERVICES_H

#import <Foundation/NSObject.h>

@class NSString;

typedef struct {
    id name;
    char reserved;
    const char *command;
    unsigned char options[9];
    unsigned int flags;
} TerminalServiceRecord;

typedef struct {
    int count;
    TerminalServiceRecord *records;
} TerminalServiceSet;

_Static_assert(sizeof(TerminalServiceRecord) == 28,
    "Terminal service record stride");
_Static_assert(__builtin_offsetof(TerminalServiceRecord, command) == 8,
    "Terminal service command offset");
_Static_assert(__builtin_offsetof(TerminalServiceRecord, options) == 12,
    "Terminal service options offset");
_Static_assert(__builtin_offsetof(TerminalServiceRecord, flags) == 24,
    "Terminal service flags offset");
_Static_assert(sizeof(TerminalServiceSet) == 8,
    "Terminal service-set header layout");
_Static_assert(__builtin_offsetof(TerminalServiceSet, records) == 4,
    "Terminal service-set records offset");

@interface ServiceCache : NSObject
{
@public
    TerminalServiceSet *theSet;
    long lastMod;
    char initialized;
    char _padding0[3];
    char *dirPath;
    char *mapFile;
    char *cacheFile;
    NSString *serviceDirectory;
    char saveOK;
    char needsSave;
    char offeredExamples;
    char _padding1;
}

- (char)loadServiceSet;
- (char)serviceSetChanged;
- (TerminalServiceSet *)serviceSet;

@end

_Static_assert(sizeof(ServiceCache) == 36,
    "Terminal ServiceCache PPC/i386 instance size");
typedef struct {
    @defs(ServiceCache);
} TerminalServiceCacheLayout;

_Static_assert(__builtin_offsetof(TerminalServiceCacheLayout, theSet) == 4,
    "Terminal ServiceCache service-set offset");
_Static_assert(__builtin_offsetof(TerminalServiceCacheLayout, lastMod) == 8,
    "Terminal ServiceCache modification-time offset");
_Static_assert(__builtin_offsetof(TerminalServiceCacheLayout, initialized) == 12,
    "Terminal ServiceCache initialization-state offset");
_Static_assert(__builtin_offsetof(TerminalServiceCacheLayout, dirPath) == 16,
    "Terminal ServiceCache directory-path offset");
_Static_assert(__builtin_offsetof(TerminalServiceCacheLayout, mapFile) == 20,
    "Terminal ServiceCache map-path offset");
_Static_assert(__builtin_offsetof(TerminalServiceCacheLayout, cacheFile) == 24,
    "Terminal ServiceCache cache-path offset");
_Static_assert(__builtin_offsetof(TerminalServiceCacheLayout, serviceDirectory) == 28,
    "Terminal ServiceCache service-directory offset");
_Static_assert(__builtin_offsetof(TerminalServiceCacheLayout, saveOK) == 32,
    "Terminal ServiceCache save-state offset");
_Static_assert(__builtin_offsetof(TerminalServiceCacheLayout, needsSave) == 33,
    "Terminal ServiceCache dirty-state offset");
_Static_assert(__builtin_offsetof(TerminalServiceCacheLayout, offeredExamples) == 34,
    "Terminal ServiceCache example-offer state offset");

#endif
