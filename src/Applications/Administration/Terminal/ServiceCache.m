#import "TerminalServices.h"

#import <AppKit/NSPanel.h>
#import <Foundation/NSBundle.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSFileManager.h>
#import <Foundation/NSException.h>
#import <Foundation/NSPathUtilities.h>
#import <Foundation/NSAutoreleasePool.h>
#import <Foundation/NSProcessInfo.h>
#import <Foundation/NSString.h>
#import <Foundation/NSZone.h>
#import <AppKit/NSApplication.h>
#import <AppKit/NSPasteboard.h>

#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

extern int NXIsPrint(int character);
extern void NSUpdateDynamicServices(void);

@interface ServiceCache (ServiceCacheIO)
- (char)checkFile:(const char *)path forNaughtyModes:(unsigned int)modes;
- (char)readService:(TerminalServiceRecord *)service fromFile:(FILE *)file
    zone:(NSZone *)zone;
- (void)discardServices;
- (void)saveService:(TerminalServiceRecord *)service inSlot:(int)slot;
- (void)importService:(TerminalServiceRecord *)destination
    from:(TerminalServiceRecord *)source;
- (int)addNewTermService:(TerminalServiceRecord *)service;
- (void)removeServiceAt:(int)index;
- (char)readService:(TerminalServiceRecord *)service fromFile:(FILE *)file
    zone:(NSZone *)zone;
- (char)serviceSetChanged;
- (char)updateServicesFile;
- (void)writeServices;
- (void)writeService:(TerminalServiceRecord *)service toFile:(FILE *)file;
@end

@implementation ServiceCache

- (id)init
{
    char path[1032];
    const char *home = [NSHomeDirectory() cString];
    NSZone *zone;
    size_t length;

    if (home != NULL) {
        sprintf(path, "%s/%s/%s", home, "Library", "services");
        zone = [self zone];
        length = strlen(path);
        self->dirPath = NSZoneMalloc(zone, length + 1);
        if (self->dirPath != NULL)
            strcpy(self->dirPath, path);

        sprintf(path, "%s/%s/%s", home, "Library", "Terminal.service");
        zone = [self zone];
        length = strlen(path);
        self->cacheFile = NSZoneMalloc(zone, length + 1);
        if (self->cacheFile != NULL)
            strcpy(self->cacheFile, path);

        sprintf(path, "%s/%s", self->dirPath, "DefaultServices");
        zone = [self zone];
        length = strlen(path);
        self->mapFile = NSZoneMalloc(zone, length + 1);
        if (self->mapFile != NULL)
            strcpy(self->mapFile, path);

        self->serviceDirectory = nil;
    }

    self->saveOK = 1;
    self->needsSave = 0;
    return self;
}

- (void)setOKToSave:(char)allowed
{
    if (allowed != self->saveOK) {
        self->saveOK = allowed;
        if (allowed == 1 && self->needsSave != 0)
            [self writeServices];
    }
}

- (char)loadServiceSet
{
    struct stat status;
    char copyBuffer[4196];
    int sourceFD;
    int destinationFD;
    ssize_t byteCount;
    int copiedExamples = 0;
    const char *examplesPath;
    FILE *file;
    int index;
    NSZone *zone;

    [self discardServices];
    if (self->dirPath != NULL) {
        if (stat(self->dirPath, &status) == -1) {
            if (mkdir(self->dirPath, 0x2F3u) == -1)
                return 0;
        } else if (![self checkFile:self->dirPath forNaughtyModes:2]) {
            return 0;
        }

        if (stat(self->cacheFile, &status) != -1 && status.st_size != 0) {
            if (![self checkFile:self->cacheFile forNaughtyModes:18])
                return 0;
        } else {
            examplesPath = [[[NSBundle mainBundle]
                pathForResource:@"DefaultServices" ofType:@"svcs"]
                cString];
            if (examplesPath != NULL && self->offeredExamples == 0) {
                sourceFD = open(examplesPath, O_RDONLY, 0);
                if (sourceFD != -1) {
                    if (NSRunAlertPanel(
                            [[NSBundle mainBundle] localizedStringForKey:
                                @"Terminal Services" value:@"Terminal Services"
                                table:nil],
                            [[NSBundle mainBundle] localizedStringForKey:
                                @"No services are defined.  Would you like to load a set of example services?"
                                value:@"No services are defined.  Would you like to load a set of example services?"
                                table:nil],
                            [[NSBundle mainBundle] localizedStringForKey:
                                @"Load Examples" value:@"Load Examples"
                                table:nil],
                            [[NSBundle mainBundle] localizedStringForKey:
                                @"Don't Load" value:@"Don't Load" table:nil],
                            nil) == 1) {
                        destinationFD = open(self->cacheFile,
                            O_WRONLY | O_CREAT | O_TRUNC, 420);
                        if (destinationFD == -1) {
                            NSRunAlertPanel(
                                [[NSBundle mainBundle] localizedStringForKey:
                                    @"Can't Create" value:@"Can't Create"
                                    table:nil],
                                [[NSBundle mainBundle] localizedStringForKey:
                                    @"Can't create %s.  No services can be exported."
                                    value:@"Can't create %s.  No services can be exported."
                                    table:nil],
                                nil, nil, nil, self->cacheFile);
                            return 0;
                        }
                        while ((byteCount = read(sourceFD, copyBuffer,
                                0x1060u)) != 0)
                            write(destinationFD, copyBuffer, byteCount);
                        close(destinationFD);
                        copiedExamples = 1;
                    }
                    close(sourceFD);
                }
            }
            if (copiedExamples == 0) {
                destinationFD = open(self->cacheFile,
                    O_WRONLY | O_CREAT | O_TRUNC, 420);
                if (destinationFD == -1) {
                    NSRunAlertPanel(
                        [[NSBundle mainBundle] localizedStringForKey:
                            @"Can't Create" value:@"Can't Create" table:nil],
                        [[NSBundle mainBundle] localizedStringForKey:
                            @"Can't create %s.  No services can be exported."
                            value:@"Can't create %s.  No services can be exported."
                            table:nil],
                        nil, nil, nil, self->cacheFile);
                    return 0;
                }
                close(destinationFD);
            }
            if (stat(self->cacheFile, &status) == -1) {
                [[NSAssertionHandler currentHandler]
                    handleFailureInMethod:_cmd object:self file:@"ServiceCache.m"
                    lineNumber:141 description:@"Cannot stat service cache."];
            }
        }

        self->offeredExamples = 1;
        self->lastMod = status.st_mtimespec.tv_sec;
        zone = [self zone];
        self->theSet = NSZoneMalloc(zone, sizeof(TerminalServiceSet));
        self->theSet->count = 10;
        zone = [self zone];
        self->theSet->records = NSZoneMalloc(zone,
            sizeof(TerminalServiceRecord) * self->theSet->count);
        file = fopen(self->cacheFile, "r");
        if (file == NULL) {
            NSBeep();
            zone = [self zone];
            NSZoneFree(zone, self->theSet->records);
            zone = [self zone];
            NSZoneFree(zone, self->theSet);
            return 0;
        }

        for (index = 0; !feof(file); ++index) {
            if (index >= self->theSet->count) {
                zone = [self zone];
                self->theSet->records = NSZoneRealloc(zone,
                    self->theSet->records,
                    sizeof(TerminalServiceRecord) *
                        (self->theSet->count + 10));
                self->theSet->count += 10;
            }
            zone = [self zone];
            if (![self readService:&self->theSet->records[index]
                    fromFile:file zone:zone])
                break;
        }
        fclose(file);
        self->theSet->count = index;
        self->initialized = 1;
        if ([self serviceSetChanged])
            [self updateServicesFile];
    }
    return 1;
}

- (char)serviceSetChanged
{
    struct stat status;

    if (self->initialized == 0)
        return 1;
    if (self->cacheFile == NULL || stat(self->cacheFile, &status) == -1 ||
        status.st_mtime > self->lastMod)
        return 1;
    return 0;
}

- (char)checkFile:(const char *)path forNaughtyModes:(unsigned int)modes
{
    struct stat status;

    if (stat(path, &status) != -1) {
        if (status.st_uid == getuid() && (status.st_mode & modes) == 0)
            return 1;
        NSRunAlertPanel(
            [[NSBundle mainBundle] localizedStringForKey:
                @"Suspicious Permissions" value:@"Suspicious Permissions"
                table:nil],
            [[NSBundle mainBundle] localizedStringForKey:
                @"Permissions on %s look suspicious.  Terminal won't be able to export any services."
                value:@"Permissions on %s look suspicious.  Terminal won't be able to export any services."
                table:nil],
            nil, nil, nil, path);
    }
    return 0;
}

- (char)readService:(TerminalServiceRecord *)service fromFile:(FILE *)file
    zone:(NSZone *)zone
{
    char line[4192];
    char command[4192];
    int fields[10];
    unsigned int flags;
    char *newline;
    int index;
    id allocatedName;

    fgets(line, sizeof(line), file);
    if (feof(file) || sscanf(line,
            "%d %d %d %d %d %d %d %d %d %d %u",
            &fields[0], &fields[1], &fields[2], &fields[3], &fields[4],
            &fields[5], &fields[6], &fields[7], &fields[8], &fields[9],
            &flags) != 11)
        return 0;

    service->reserved = fields[0];
    for (index = 0; index < 9; ++index)
        service->options[index] = fields[index + 1];
    service->flags = flags;

    fgets(line, sizeof(line), file);
    newline = strchr(line, '\n');
    if (newline != NULL)
        *newline = '\0';
    allocatedName = [NSString allocWithZone:zone];
    service->name = [allocatedName initWithCString:line];

    fgets(line, sizeof(line), file);
    newline = strchr(line, '\n');
    if (newline != NULL)
        *newline = '\0';
    [self convertPrintable:line toString:command];
    service->command = NSZoneMalloc(zone, strlen(command) + 1);
    strcpy((char *)service->command, command);
    return 1;
}

- (void)disableOfferExamples
{
    self->offeredExamples = 1;
}

- (void)discardServices
{
    int index;
    TerminalServiceRecord *record;
    NSZone *zone;

    if (self->theSet != NULL) {
        for (index = 0; index < self->theSet->count; ++index) {
            record = &self->theSet->records[index];
            [record->name release];
            zone = [self zone];
            NSZoneFree(zone, (void *)record->command);
        }
        zone = [self zone];
        NSZoneFree(zone, self->theSet);
        self->theSet = NULL;
    }
    self->initialized = 0;
}

- (TerminalServiceSet *)serviceSet
{
    return self->theSet;
}

- (void)convertString:(char *)source toPrintable:(char *)destination
{
    size_t index;
    size_t length = strlen(source);
    char *output = destination;

    for (index = 0; index < length; ++index) {
        if (NXIsPrint(source[index]) != 0) {
            if (source[index] == '\\') {
                *output++ = '\\';
                *output++ = '\\';
            } else {
                *output++ = source[index];
            }
        } else {
            sprintf(output, "\\%3u", (unsigned int)(int)source[index]);
            output += strlen(output);
        }
    }
    *output = '\0';
}

- (void)convertPrintable:(char *)source toString:(char *)destination
{
    char *input = source;
    char *output = destination;

    while (*input != '\0') {
        if (*input == '\\') {
            ++input;
            if (*input == '\\') {
                *output++ = '\\';
                ++input;
            } else {
                char saved = input[3];
                input[3] = '\0';
                *output++ = (char)atoi(input);
                input[3] = saved;
                input += 3;
            }
        } else {
            *output++ = *input++;
        }
    }
    *output = '\0';
}

- (void)loadCommandsMenu
{
}

- (void)saveService:(TerminalServiceRecord *)service inSlot:(int)slot
{
    TerminalServiceRecord *savedService;
    NSZone *zone;

    if (self->theSet == NULL || slot >= self->theSet->count)
        return;

    savedService = &self->theSet->records[slot];
    [savedService->name release];
    zone = [self zone];
    NSZoneFree(zone, (void *)savedService->command);
    [self importService:savedService from:service];
    [self serviceSetChanged];
}

- (void)importService:(TerminalServiceRecord *)destination
    from:(TerminalServiceRecord *)source
{
    NSZone *zone;
    char *command;

    bcopy(source, destination, sizeof(TerminalServiceRecord));
    zone = [self zone];
    destination->name = [[NSString allocWithZone:zone]
        initWithString:source->name];
    command = NSZoneMalloc(zone, strlen(source->command) + 1);
    destination->command = command;
    if (destination->name == nil || command == NULL) {
        [[NSAssertionHandler currentHandler] handleFailureInMethod:_cmd
            object:self file:@"ServiceCache.m" lineNumber:404
            description:@"Out of memory in service cache zone."];
    }
    strcpy(command, source->command);
}

- (int)addNewTermService:(TerminalServiceRecord *)service
{
    NSZone *zone;
    TerminalServiceRecord *records;

    if (self->theSet == NULL)
        return -1;

    ++self->theSet->count;
    zone = [self zone];
    records = NSZoneRealloc(zone, self->theSet->records,
        sizeof(TerminalServiceRecord) * self->theSet->count);
    self->theSet->records = records;
    if (records == NULL) {
        [[NSAssertionHandler currentHandler] handleFailureInMethod:_cmd
            object:self file:@"ServiceCache.m" lineNumber:412
            description:@"Out of memory in service cache zone."];
    }
    [self importService:&records[self->theSet->count - 1] from:service];
    [self serviceSetChanged];
    return self->theSet != NULL ? self->theSet->count - 1 : -1;
}

- (void)removeServiceAt:(int)index
{
    TerminalServiceSet *serviceSet = self->theSet;
    TerminalServiceRecord *records;
    NSZone *zone;
    int oldCount;

    if (serviceSet == NULL || index >= serviceSet->count)
        return;

    oldCount = serviceSet->count;
    if (index != oldCount - 1) {
        bcopy(&serviceSet->records[index + 1], &serviceSet->records[index],
            sizeof(TerminalServiceRecord) * (oldCount - index - 1));
    }
    --serviceSet->count;
    zone = [self zone];
    records = NSZoneRealloc(zone, serviceSet->records,
        sizeof(TerminalServiceRecord) * serviceSet->count);
    serviceSet->records = records;
    if (records == NULL) {
        [[NSAssertionHandler currentHandler] handleFailureInMethod:_cmd
            object:self file:@"ServiceCache.m" lineNumber:431
            description:@"Out of memory in service cache zone."];
    }
    [self serviceSetChanged];
}

- (void)writeService:(TerminalServiceRecord *)service toFile:(FILE *)file
{
    char printable[8200];

    [self convertString:(char *)service->command toPrintable:printable];
    fprintf(file,
        "%d %d %d %d %d %d %d %d %d %d %u\n%s\n%s\n",
        (int)service->reserved,
        (int)service->options[0], (int)service->options[1],
        (int)service->options[2], (int)service->options[3],
        (int)service->options[4], (int)service->options[5],
        (int)service->options[6], (int)service->options[7],
        (int)service->options[8], service->flags,
        [(NSString *)service->name cString], printable);
}

- (void)writeServices
{
    int existingFile = 0;
    FILE *file;
    int index;

    if (self->theSet != NULL) {
        if (self->saveOK != 0) {
            if (access(self->cacheFile, 0) != 0 ||
                (existingFile = 1,
                    [self checkFile:self->cacheFile forNaughtyModes:18])) {
                file = fopen(self->cacheFile, "w");
                if (file != NULL) {
                    if (existingFile == 0) {
                        chown(self->cacheFile, getuid(), (gid_t)-1);
                        chmod(self->cacheFile, 0x1A4u);
                    }
                    for (index = 0; index < self->theSet->count; ++index)
                        [self writeService:&self->theSet->records[index]
                            toFile:file];
                    fclose(file);
                    self->lastMod = time(NULL);
                    [self updateServicesFile];
                } else {
                    NSRunAlertPanel(
                        [[NSBundle mainBundle] localizedStringForKey:
                            @"Can't Write" value:@"Can't Write" table:nil],
                        [[NSBundle mainBundle] localizedStringForKey:
                            @"Can't write %s.  No services can be exported."
                            value:@"Can't write %s.  No services can be exported."
                            table:nil],
                        nil, nil, nil, self->cacheFile);
                }
            }
        } else {
            self->needsSave = 1;
        }
    }
}

- (char)updateServicesFile
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *home = NSHomeDirectory();
    NSString *candidate;
    NSString *servicePath;
    NSMutableDictionary *serviceInfo;
    NSMutableArray *serviceEntries;
    TerminalServiceRecord *record;
    const char *pathBytes;
    char *bundleBase = NULL;
    char *extensionStart;
    char *lastSlash;
    NSAutoreleasePool *pool;
    int candidateIndex;
    int index;
    int canExport;

    if (self->serviceDirectory == nil) {
        NSArray *components = [NSArray arrayWithObjects:@"Library", @"Services",
            @"Terminal.service", @"Resources", nil];
        NSString *component[4];
        [components getObjects:(id *)component];
        candidate = home;
        canExport = 1;
        for (candidateIndex = 0; candidateIndex <= 4; ++candidateIndex) {
            if (![fileManager isWritableFileAtPath:candidate] &&
                ![fileManager fileExistsAtPath:candidate]) {
                NSRunAlertPanel(
                    [bundle localizedStringForKey:@"Can't Write" value:@"Can't Write" table:nil],
                    [bundle localizedStringForKey:@"Can't write %@.  No services can be exported." value:@"Can't write %@.  No services can be exported." table:nil],
                    nil, nil, nil, candidate);
                canExport = 0;
            }
            if (candidateIndex == 4)
                break;
            candidate = [candidate stringByAppendingPathComponent:component[candidateIndex]];
        }
        self->serviceDirectory = [candidate retain];
        if (canExport == 0) {
            [self setOKToSave:0];
            return 0;
        }
    }

    servicePath = [self->serviceDirectory stringByAppendingPathComponent:
        @"Terminal.service"];
    pathBytes = [servicePath cString];
    if (pathBytes == NULL)
        return 0;
    if ([fileManager fileExistsAtPath:servicePath]) {
        NSDictionary *attributes = [fileManager fileAttributesAtPath:servicePath
            traverseLink:YES];
        if (![self checkFile:pathBytes forNaughtyModes:18]) {
            [self setOKToSave:0];
            return 0;
        }
        if ([[attributes fileModificationDate] timeIntervalSince1970] >= self->lastMod)
            return 1;
    } else {
        chmod(pathBytes, 0x1A4u);
    }

    NSString *resourceBundlePath = [bundle pathForResource:@"Services" ofType:@"subproj"];
    pathBytes = [resourceBundlePath cString];
    if (pathBytes != NULL) {
        bundleBase = (char *)pathBytes;
        extensionStart = strstr(bundleBase, ".subproj");
        if (extensionStart != NULL) {
            *extensionStart = '\0';
            lastSlash = rindex(bundleBase, '/');
            if (lastSlash != NULL)
                bundleBase = lastSlash + 1;
        }
    }

    pool = [[NSAutoreleasePool alloc] init];
    serviceInfo = [NSMutableDictionary dictionaryWithCapacity:1];
    serviceEntries = [NSMutableArray arrayWithCapacity:self->theSet->count];
    for (index = 0; index < self->theSet->count; ++index) {
        record = &self->theSet->records[index];
        if ((record->options[0] & 1) == 0 || record->options[1] == 0)
            continue;

        NSMutableDictionary *entry = [NSMutableDictionary dictionaryWithCapacity:6];
        NSMutableArray *sendTypes = [NSMutableArray arrayWithCapacity:2];
        NSMutableDictionary *menuTitles = [NSMutableDictionary dictionaryWithCapacity:2];

        if ((record->options[1] & 2) != 0)
            [sendTypes addObject:NSStringPboardType];
        if ((record->options[1] & 8) != 0)
            [sendTypes addObject:NSFilenamesPboardType];
        if ((record->options[1] & 4) != 0)
            [sendTypes addObject:NSRTFPboardType];
        if ((record->options[1] & 1) != 0)
            [sendTypes addObject:@""];

        [entry setObject:@"provideService" forKey:@"NSMessage"];
        [entry setObject:@"Terminal" forKey:@"NSPortName"];
        [entry setObject:sendTypes forKey:@"NSSendTypes"];
        if ((record->options[4] & 1) != 0 && (record->options[6] & 4) != 0) {
            NSArray *returnTypes = [NSArray arrayWithObjects:NSStringPboardType,
                NSRTFPboardType, nil];
            [entry setObject:returnTypes forKey:@"NSReturnTypes"];
        }

        NSString *processName = [[NSProcessInfo processInfo] processName];
        [menuTitles setObject:[NSString stringWithFormat:@"%@/%@",
            processName, record->name] forKey:@"default"];
        if (bundleBase != NULL) {
            NSString *localizedName = [bundle localizedStringForKey:record->name
                value:@"" table:@"Services"];
            if (localizedName != nil && ![localizedName isEqual:record->name])
                [menuTitles setObject:[NSString stringWithFormat:@"%@/%@",
                    processName, localizedName]
                    forKey:[NSString stringWithCString:bundleBase]];
        }
        [entry setObject:menuTitles forKey:@"NSMenuItem"];
        if (record->reserved != 32) {
            NSString *equivalent = [NSString stringWithFormat:@"%c", record->reserved];
            [entry setObject:[bundle localizedStringForKey:equivalent
                value:@"default" table:nil] forKey:@"NSKeyEquivalent"];
        }
        [entry setObject:[NSString stringWithFormat:@"%u", record->flags]
            forKey:@"NSUserData"];
        if ((record->options[3] & 1) == 0)
            [entry setObject:@"1200000" forKey:@"NSTimeout"];
        [serviceEntries addObject:entry];
    }
    [serviceInfo setObject:serviceEntries forKey:@"NSServices"];
    if ([serviceInfo writeToFile:servicePath atomically:YES]) {
        NSUpdateDynamicServices();
        [pool release];
        return 1;
    }

    NSRunAlertPanel(
        [bundle localizedStringForKey:@"Can't Write" value:@"Can't Write"
            table:nil],
        [bundle localizedStringForKey:
            @"Can't write %@.  No services can be exported."
            value:@"Can't write %@.  No services can be exported."
            table:nil], nil, nil, nil, servicePath);
    [self setOKToSave:0];
    [pool release];
    return 0;
}

@end
