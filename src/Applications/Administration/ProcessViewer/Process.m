#import <Foundation/Foundation.h>
#import <objc/objc-class.h>
#include <errno.h>
#include <string.h>
#include <strings.h>
#include <sys/sysctl.h>
#include <sys/types.h>
#include <unistd.h>
#import "Process.h"

extern int table(int, int, void *, int, unsigned int);

static NSMapTable *_allProcessesByPid = NULL;
static char *argumentBuffer = NULL;
static NSArray *sortKeys = nil;
static char _ProcessSortTypes[] = { '@', 'f', 'f', 'f', 'f' };
static NSString * const ProcessKeys[] = {
    @"NAME", @"%MEM", @"%CPU", @"RSIZE", @"VSIZE", @"USER",
    @"PID", @"PPID", @"PGID", @"STAT", @"TIME", nil
};
static NSString *keyName = @"_NAME";
static NSString *_localizedProcessStatusValues[] = {
    @"Launching", @"Running", @"Sleeping", @"Suspended", @"Zombie"
};

@implementation MapTableEnumerator

+ (id)_newWithMapTable:(void *)table
{
    MapTableEnumerator *enumerator = [[self alloc] init];
    NSMapEnumerator mapEnumerator;

    mapEnumerator = NSEnumerateMapTable((NSMapTable *)table);
    enumerator->_mapEnum._pi = mapEnumerator._pi;
    enumerator->_mapEnum._nk = mapEnumerator._nk;
    enumerator->_mapEnum._bs = mapEnumerator._bs;
    return enumerator;
}

- (id)nextObject
{
    void *key;
    void *value;

    if (NSNextMapEnumeratorPair((NSMapEnumerator *)&_mapEnum, &key, &value))
        return value;
    return nil;
}

@end

@implementation Process

+ (void)initialize
{
    if (self == [Process class]) {
        NSZone *zone = NSDefaultMallocZone();
#ifdef PROCESSVIEWER_TEST
        _allProcessesByPid = NSCreateMapTableWithZone(NSIntMapKeyCallBacks,
            NSIntMapValueCallBacks, 0, zone);
#endif
        sortKeys = [[NSArray allocWithZone:zone] initWithObjects:
            ProcessKeys[0], ProcessKeys[1], ProcessKeys[2],
            ProcessKeys[3], ProcessKeys[4], nil];
    }
}

+ (BOOL)getSortContext:(ProcessSortContext *)context
                forKey:(id)key
             ascending:(BOOL)ascending
{
    unsigned int index;
    unsigned int count;

    if (context == NULL || key == nil || sortKeys == nil)
        return NO;

    count = [sortKeys count];
    for (index = 0; index < count; ++index) {
        id sortKey = [sortKeys objectAtIndex:index];
        if ([sortKey isEqual:key]) {
            context->key = sortKey;
            context->compareAsNumber = _ProcessSortTypes[index];
            context->ascending = ascending;
            return YES;
        }
    }

    return NO;
}

+ (id)enumerateProcessesAndFetch:(BOOL)fetch
{
    if (fetch || _allProcessesByPid == NULL) {
        NSTask *task = [[NSTask alloc] init];
        NSPipe *pipe = [[NSPipe alloc] init];
        NSFileHandle *readHandle;
        NSData *data;
        NSString *output;
        const char *bytes;
        const char *lineStart;
        const char *lineEnd;
        NSMapTable *oldProcesses = NULL;

        [task setLaunchPath:@"/bin/ps"];
        [task setArguments:[NSArray arrayWithObject:@"caux"]];
        [task setStandardOutput:pipe];
        [task launch];
        readHandle = [pipe fileHandleForReading];
        data = [readHandle readDataToEndOfFile];
        [task release];
        [pipe release];

        output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (output != nil) {
            if (_allProcessesByPid != NULL) {
                oldProcesses = NSCopyMapTableWithZone(_allProcessesByPid, NSDefaultMallocZone());
            } else {
                _allProcessesByPid = NSCreateMapTableWithZone(
                    NSIntMapKeyCallBacks, NSIntMapValueCallBacks, 0,
                    NSDefaultMallocZone());
            }

            bytes = [output cString];
            lineStart = strchr(bytes, '\n');
            while (lineStart != NULL) {
                NSString *row;
                NSScanner *scanner;
                NSCharacterSet *whitespace = [NSCharacterSet whitespaceCharacterSet];
                NSString *user;
                NSString *cpu;
                NSString *memory;
                NSString *virtualSize;
                NSString *residentSize;
                NSString *tty;
                NSString *status;
                NSString *cpuTime;
                Process *process;
                long long pidValue = 0;

                ++lineStart;
                lineEnd = strchr(lineStart, '\n');
                if (lineEnd == NULL || lineEnd <= lineStart)
                    break;
                row = [[NSString alloc] initWithCString:lineStart
                                                 length:(unsigned int)(lineEnd - lineStart)];
                scanner = [NSScanner scannerWithString:row];
                [scanner setCharactersToBeSkipped:whitespace];
                user = nil;
                cpu = nil;
                memory = nil;
                virtualSize = nil;
                residentSize = nil;
                tty = nil;
                status = nil;
                cpuTime = nil;

                [scanner scanUpToCharactersFromSet:whitespace intoString:&user];
                [scanner scanLongLong:&pidValue];
                [scanner scanUpToCharactersFromSet:whitespace intoString:&cpu];
                [scanner scanUpToCharactersFromSet:whitespace intoString:&memory];
                [scanner scanUpToCharactersFromSet:whitespace intoString:&virtualSize];
                [scanner scanUpToCharactersFromSet:whitespace intoString:&residentSize];
                [scanner scanUpToCharactersFromSet:whitespace intoString:&tty];
                [scanner scanUpToCharactersFromSet:whitespace intoString:&status];
                [scanner scanUpToCharactersFromSet:whitespace intoString:&cpuTime];

                if (user != nil && pidValue > 0 && pidValue != (long long)getpid()) {
                    process = (Process *)NSMapGet(_allProcessesByPid,
                        (const void *)(unsigned long)pidValue);
                    if (process == nil)
                        process = [[self allocWithZone:NSDefaultMallocZone()]
                            initWithPid:(int)pidValue];
                    else if (oldProcesses != NULL)
                        NSMapRemove(oldProcesses, (const void *)(unsigned long)pidValue);

                    [process->_values setObject:user forKey:ProcessKeys[5]];
                    if (cpu != nil) [process->_values setObject:cpu forKey:ProcessKeys[2]];
                    if (memory != nil) [process->_values setObject:memory forKey:ProcessKeys[1]];
                    if (virtualSize != nil) [process->_values setObject:virtualSize forKey:ProcessKeys[4]];
                    if (residentSize != nil) [process->_values setObject:residentSize forKey:ProcessKeys[3]];
                    if (tty != nil) [process->_values setObject:tty forKey:@"TTY"];
                    if (cpuTime != nil) [process->_values setObject:cpuTime forKey:ProcessKeys[10]];
                    [process _update];
                }
                [row release];
                lineStart = lineEnd;
            }
            [output release];
        }

        if (oldProcesses != NULL) {
            if (NSCountMapTable(oldProcesses) != 0) {
                NSArray *staleProcesses = NSAllMapTableValues(oldProcesses);
                [staleProcesses makeObjectsPerformSelector:@selector(invalidate)];
            }
            NSFreeMapTable(oldProcesses);
        }
    }

    return [NSAllMapTableValues(_allProcessesByPid)
        sortedArrayUsingFunction:sortFunction context:NULL];
}

- (id)initWithPid:(int)pid
{
    self = [super init];
    if (self != nil) {
        _values = [[NSMutableDictionary allocWithZone:[self zone]] initWithCapacity:5];
        _pid = pid;
        NSMapInsert(_allProcessesByPid, (const void *)(unsigned long)pid, self);
    }
    return self;
}

- (void)dealloc
{
    [_args release];
    [_values release];
    [super dealloc];
}

- (void)invalidate
{
    [[NSNotificationCenter defaultCenter]
        postNotificationName:@"ProcessBecameInvalidNotification" object:self];
    NSMapRemove(_allProcessesByPid, (const void *)(unsigned long)_pid);
    [self release];
}

- (id)objectForKey:(id)key
{
    return [_values objectForKey:key];
}

- (unsigned int)processId
{
    return _pid;
}

- (unsigned int)parentProcessId
{
    return _ppid;
}

- (unsigned int)processGroupId
{
    return _pgid;
}

- (unsigned int)savedUserId
{
    return _saved_euid;
}

- (id)tty
{
    return [_values objectForKey:@"TTY"];
}

- (id)arguments
{
    if (_args == nil) {
        char *end;
        char *start;

        if (argumentBuffer == NULL)
            argumentBuffer = NSZoneMalloc(NSDefaultMallocZone(), 4096);

        if (table(6, _pid, argumentBuffer, 1, 4096) == 1) {
            NSMutableArray *arguments = [[NSMutableArray allocWithZone:[self zone]]
                initWithCapacity:0];
            end = argumentBuffer + 4084;
            start = end;
            while (start >= argumentBuffer) {
                if (start[0] == '\0' && start[1] == '\0' &&
                    start[2] == '\0' && start[3] == '\0') {
                    start += 4;
                    break;
                }
                start -= 4;
            }

            if (start >= argumentBuffer) {
                char *lastArgumentEnd = start;
                char *entry;

                for (entry = start; entry < end; entry += strlen(entry) + 1) {
                    if (index(entry, '=') == NULL)
                        lastArgumentEnd = entry + strlen(entry) + 1;
                }

                for (entry = start; entry < lastArgumentEnd;
                     entry += strlen(entry) + 1) {
                    NSString *argument = [[NSString allocWithZone:[self zone]]
                        initWithCString:entry];
                    [arguments addObject:argument];
                    [argument release];
                }
            }
            _args = arguments;
        }
    }

    return _args;
}

- (int)compare:(id)other context:(ProcessSortContext *)context
{
    id key = context != NULL ? context->key : [sortKeys objectAtIndex:0];
    BOOL ascending = context != NULL ? context->ascending : YES;
    char kind = context != NULL ? context->compareAsNumber : '@';
    id left;
    id right;

    if (other == nil)
        return 1;

    left = [self objectForKey:key];
    right = [other objectForKey:key];

    if (!ascending) {
        id swap = left;
        left = right;
        right = swap;
    }

    if (left == nil || right == nil) {
        if (left == right)
            return 0;
        return left == nil ? -1 : 1;
    }

    switch (kind) {
        case '@':
            return [left caseInsensitiveCompare:right];
        case 'i': {
            int leftValue = [left intValue];
            int rightValue = [right intValue];
            if (leftValue < rightValue)
                return -1;
            if (leftValue > rightValue)
                return 1;
            return 0;
        }
        case 'f': {
            double leftValue = floatFromNumberWithSuffix(left);
            double rightValue = floatFromNumberWithSuffix(right);
            if (leftValue < rightValue)
                return -1;
            if (leftValue > rightValue)
                return 1;
            return 0;
        }
        default:
            NSLog(@"Invalid sort specifier %c", kind);
            return 0;
    }
}

- (id)dictionaryRepresentation
{
    NSMutableDictionary *dictionary = [_values mutableCopyWithZone:NSDefaultMallocZone()];

    [dictionary setObject:[NSNumber numberWithUnsignedInt:_saved_euid] forKey:@"UID"];
    [dictionary setObject:[NSNumber numberWithInt:_pid] forKey:ProcessKeys[6]];
    [dictionary setObject:[NSNumber numberWithInt:_ppid] forKey:ProcessKeys[7]];
    [dictionary setObject:[NSNumber numberWithInt:_pgid] forKey:ProcessKeys[8]];
    return [dictionary autorelease];
}

- (id)description
{
    return [NSString stringWithFormat:@"<%s 0x%lx (pid %d)>",
        isa->name, (unsigned long)self, _pid];
}

@end

double floatFromNumberWithSuffix(id number)
{
    double value = [number doubleValue];

    if ([number hasSuffix:@"K"])
        value = (float)(value * 1024.0);
    if ([number hasSuffix:@"M"])
        value = (float)(value * 1048576.0);
    if ([number hasSuffix:@"G"])
        return (float)(value * 1073741824.0);
    return value;
}

int sortFunction(id left, id right, void *context)
{
    return [left compare:right context:(ProcessSortContext *)context];
}

@implementation Process (Private)

- (void)_setCString:(const char *)value forKey:(id)key
{
    if (value != NULL && *value != '\0') {
        NSString *oldValue = [_values objectForKey:key];
        if (oldValue == nil || strcmp([oldValue cString], value) != 0) {
            NSString *newValue = [NSString stringWithCString:value];
            [_values setObject:newValue forKey:key];
        }
    } else {
        [_values removeObjectForKey:key];
    }
}

- (void)_update
{
    int mib[4] = { 1, 14, 1, _pid };
    struct kinfo_proc processInfo;
    size_t length = sizeof(processInfo);
    const char *processName;
    if (sysctl(mib, 4, &processInfo, &length, NULL, 0) < 0) {
        NSLog(@"sysctl failed: %s", strerror(errno));
        return;
    }

    processName = processInfo.kp_proc.p_comm;
    if (strlen(processName) == 16) {
        NSArray *arguments = [self arguments];
        if (arguments != nil && [arguments count] != 0) {
            NSString *path = [[arguments objectAtIndex:0] lastPathComponent];
            [_values setObject:path forKey:ProcessKeys[0]];
            processName = NULL;
        }
    }
    if (processName != NULL)
        [self _setCString:processName forKey:@"NAME"];

    _ppid = processInfo.kp_eproc.e_ppid;
    _pgid = processInfo.kp_eproc.e_pgid;
    _saved_euid = processInfo.kp_eproc.e_pcred.p_svuid;
    _real_uid = processInfo.kp_eproc.e_pcred.p_ruid;
    {
        id userName = NameForUID(_real_uid);
        if (userName != nil)
        [_values setObject:userName forKey:ProcessKeys[5]];
    }

    if (processInfo.kp_proc.p_stat >= SIDL && processInfo.kp_proc.p_stat <= SZOMB)
        [_values setObject:_localizedProcessStatusValues[
                        processInfo.kp_proc.p_stat - SIDL]
                        forKey:ProcessKeys[9]];
}

@end


