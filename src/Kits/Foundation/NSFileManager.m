/*	NSFileManager.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSFileManager.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSData.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSException.h>
#import <Foundation/NSLock.h>
#import <Foundation/NSMapTable.h>
#import <Foundation/NSPathUtilities.h>
#import <Foundation/NSProcessInfo.h>
#import <Foundation/NSScanner.h>
#import <Foundation/NSSet.h>
#import <Foundation/NSString.h>
#import <Foundation/NSValue.h>

#include <sys/stat.h>
#include <sys/mount.h>
#include <sys/dir.h>
#include <sys/time.h>
#include <dirent.h>
#include <cthreads.h>
#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <pwd.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <unistd.h>

@interface NSFileManager (NSFileManagerPathConversion)
- (BOOL)getFileSystemRepresentation:(char *)cname maxLength:(unsigned)max withPath:(NSString *)path;
@end

@interface NSFileManager (NSFileManagerReplication)
- (NSArray *)_posixPathComponentsWithPath:(NSString *)path;
- (BOOL)_replicatePath:(NSString *)source atPath:(NSString *)destination
             operation:(int)operation fileMap:(NSMapTable *)fileMap
               handler:(id)handler;
@end

@interface NSString (NSFileSystemRepresentation)
- (BOOL)getFileSystemRepresentation:(char *)cname maxLength:(unsigned)max;
@end

@interface NSCheapMutableString : NSMutableString
- (void)setContentsNoCopy:(void *)contents length:(unsigned)length
    freeWhenDone:(BOOL)freeBuffer isUnicode:(BOOL)isUnicode;
- (BOOL)getBytes:(char *)buffer maxLength:(unsigned)maxLength
    filledLength:(unsigned *)usedLength encoding:(NSStringEncoding)encoding
    allowLossyConversion:(BOOL)allowLossy range:(NSRange)range
    remainingRange:(NSRangePointer)remainingRange;
@end

@interface NSStringArray : NSArray
+ (id)stringArrayWithUTF8Data:(NSData *)data;
@end

extern NSStringEncoding _NSDefaultFileSystemEncoding(void);
extern int _NSGetDirectory2(char *path, size_t size);
extern int _NSConvertToASCIIorUnicode2(const void *bytes, unsigned length,
                                      NSStringEncoding encoding, BOOL flag,
                                      void *result, NSZone *zone);
extern ssize_t _NSWriteToFileDescriptor(int descriptor, const void *buffer,
                                        size_t length);
extern int _NSProcessID(void);
extern id _NSMethodExceptionProem(id object, SEL selector);
extern unsigned NSPushAutoreleasePool(void);
extern void NSPopAutoreleasePool(unsigned token);
extern NSLock *_NSTempFileCounterLock;
extern NSLock *_NSUniqueStringCounterLock;

static BOOL fileStat(NSFileManager *manager, NSString *path, struct stat *status) {
    char filePath[1028];

    return [manager getFileSystemRepresentation:filePath maxLength:1024 withPath:path]
        && lstat(filePath, status) == 0;
}

static BOOL fileStatFollow(NSFileManager *manager, NSString *path,
                           struct stat *status) {
    char filePath[1028];

    return [manager getFileSystemRepresentation:filePath maxLength:1024 withPath:path]
        && stat(filePath, status) == 0;
}

int _NSMoveFile(char *oldPath, char *newPath) {
    return rename(oldPath, newPath);
}

static unsigned short extension_counter_303;

int _NSmkstemp83(char *path, const char *prefix, int *descriptor) {
    static const char hex[] = "0123456789abcdef";
    unsigned directoryLength = (unsigned)strlen(path);
    unsigned short counter;
    unsigned short firstCounter;
    unsigned short process;
    unsigned short firstProcess;
    char name[13];

    *descriptor = -1;
    if (_NSUniqueStringCounterLock != nil)
        [_NSTempFileCounterLock lock];
    counter = extension_counter_303++;
    if (extension_counter_303 > 4095)
        extension_counter_303 = 0;
    if (_NSUniqueStringCounterLock != nil)
        [_NSTempFileCounterLock unlock];
    firstCounter = counter;
    strncpy(name, prefix, 4);
    name[4] = '\0';
    if (directoryLength != 0 && path[directoryLength - 1] != '/')
        path[directoryLength++] = '/';
    process = (unsigned short)_NSProcessID();
    firstProcess = process;

    for (;;) {
        unsigned value;
        unsigned index;

        value = process;
        for (index = 0; index < 4; index++) {
            name[7 - index] = hex[value & 0xf];
            value >>= 4;
        }
        name[8] = '.';
        value = counter;
        for (index = 0; index < 3; index++) {
            name[11 - index] = hex[value & 0xf];
            value >>= 4;
        }
        name[12] = '\0';
        path[directoryLength] = '\0';
        memcpy(path + directoryLength, name, sizeof(name));
        *descriptor = open(path, O_RDWR | O_CREAT | O_EXCL, 0600);
        if (*descriptor >= 0)
            return 0;
        if (cthread_errno() != EEXIST)
            return -1;

        counter = (unsigned short)((counter + 1) & 0x0fff);
        if (counter == firstCounter) {
            process = (unsigned short)(process + 1);
            if (process == firstProcess)
                return -1;
        }
    }
}

int _NSOpenFileDescriptor(char *path, int flags, int mode) {
#if defined(__ppc__) || defined(__POWERPC__)
    int descriptor = open(path, flags);
#else
    int descriptor = open(path, flags, mode);
#endif
    struct stat status;

    if (descriptor < 0)
        return -1;
    if (fstat(descriptor, &status) == 0 && !S_ISDIR(status.st_mode))
        return descriptor;
    close(descriptor);
    return -1;
}

ssize_t _NSReadFromFileDescriptor(int descriptor, void *buffer, size_t length) {
    return read(descriptor, buffer, length);
}

int _NSCloseFileDescriptor(int descriptor) {
    return close(descriptor);
}

int _NSFileAccessModes(NSString *path, BOOL *exists, BOOL *readable,
                      BOOL *writable, BOOL *executable, BOOL *isDirectory,
                      int *times) {
    char filePath[1028];
    struct stat status;
    int result;

    if (exists != NULL)
        *exists = NO;
    if (readable != NULL)
        *readable = NO;
    if (writable != NULL)
        *writable = NO;
    if (executable != NULL)
        *executable = NO;
    if (isDirectory != NULL)
        *isDirectory = NO;
    if (times != NULL) {
        times[0] = 0;
        times[1] = 0;
    }
    result = [path getFileSystemRepresentation:filePath maxLength:1024];
    if (!result)
        return result;
    result = stat(filePath, &status);
    if (result != 0)
        return result;
    if (exists != NULL)
        *exists = YES;
    if (readable != NULL) {
#if defined(__ppc__) || defined(__POWERPC__)
        result = access(filePath, R_OK) == 0;
        *readable = result;
#else
        result = access(filePath, R_OK);
        *readable = result == 0;
#endif
    }
    if (writable != NULL) {
#if defined(__ppc__) || defined(__POWERPC__)
        result = access(filePath, W_OK) == 0;
        *writable = result;
#else
        result = access(filePath, W_OK);
        *writable = result == 0;
#endif
    }
    if (executable != NULL) {
#if defined(__ppc__) || defined(__POWERPC__)
        result = access(filePath, X_OK) == 0;
        *executable = result;
#else
        result = access(filePath, X_OK);
        *executable = result == 0;
#endif
    }
    if (isDirectory != NULL)
        *isDirectory = (status.st_mode & 0xF000) == 0x4000;
    if (times != NULL) {
#if defined(__ppc__) || defined(__POWERPC__)
        memcpy(times, &status.st_size, sizeof(status.st_size));
#else
        times[0] = (int)status.st_ctimespec.tv_nsec;
        times[1] = (int)status.st_birthtimespec.tv_sec;
#endif
    }
    return result;
}

int _NSFileAccessibleForMode(NSString *path, int mode) {
    char filePath[1028];

    return [path getFileSystemRepresentation:filePath maxLength:1024]
        && access(filePath, mode) == 0;
}

int _NSSetDirectory2(char *path) {
    return chdir(path) == 0;
}

int _NSCreateDirectory2(char *path) {
    return mkdir(path, 0777) == 0;
}

int _NSDeleteFile2(char *path) {
    return unlink(path) == 0;
}

int _NSRemoveDirectory2(char *path) {
    return rmdir(path) == 0;
}

int _NSCreateDirectory(NSString *path) {
    char filePath[1028];

    if (![path getFileSystemRepresentation:filePath maxLength:1024])
        return 0;
    return _NSCreateDirectory2(filePath);
}

static unsigned statHash(NSMapTable *table, const void *key) {
    const struct stat *status = (const struct stat *)key;

    (void)table;
    return (unsigned)status->st_ino | ((unsigned)status->st_dev << 8);
}

static BOOL statEqual(NSMapTable *table, const void *left, const void *right) {
    const struct stat *leftStatus = (const struct stat *)left;
    const struct stat *rightStatus = (const struct stat *)right;

    (void)table;
    return leftStatus->st_dev == rightStatus->st_dev
        && leftStatus->st_ino == rightStatus->st_ino;
}

static NSMapTable *NSFileStatMapCreate(void) {
    NSMapTableKeyCallBacks keyCallbacks = NSOwnedPointerMapKeyCallBacks;

    keyCallbacks.hash = statHash;
    keyCallbacks.isEqual = statEqual;
    return NSCreateMapTableWithZone(keyCallbacks, NSObjectMapValueCallBacks,
                                    0, NULL);
}

static BOOL NSFileManagerReportReplicationError(NSFileManager *manager,
                                                id handler, BOOL shouldReport,
                                                NSString *path,
                                                NSString *error,
                                                NSString *toPath,
                                                NSString *errnoText) {
    NSDictionary *errorInfo;

    if (!shouldReport) {
        return NO;
    }
    if (toPath != nil && errnoText != nil) {
        errorInfo = [NSDictionary dictionaryWithObjectsAndKeys:
            path, @"Path", error, @"Error", toPath, @"ToPath",
            errnoText, @"Errno", nil];
    } else if (toPath != nil) {
        errorInfo = [NSDictionary dictionaryWithObjectsAndKeys:
            path, @"Path", error, @"Error", toPath, @"ToPath", nil];
    } else {
        errorInfo = [NSDictionary dictionaryWithObjectsAndKeys:
            path, @"Path", error, @"Error", nil];
    }
    return [handler fileManager:manager shouldProceedAfterError:errorInfo];
}

int _NSSetFileModificationUNIXTime(NSString *path, time_t seconds) {
    char filePath[1028];
    struct timeval times[2];

    if (![path getFileSystemRepresentation:filePath maxLength:1024])
        return NO;
    times[0].tv_sec = seconds;
    times[0].tv_usec = 0;
    times[1] = times[0];
    return utimes(filePath, times) == 0;
}

static time_t NSFileManagerUNIXTimeFromDate(NSDate *date) {
#if defined(__ppc__) || defined(__POWERPC__)
    double seconds = [date timeIntervalSinceReferenceDate] + 978307200.0;
    int converted;
    unsigned int bits;

    if (seconds >= 2147483648.0) {
        converted = (int)(seconds - 2147483648.0);
        bits = (unsigned int)converted ^ 0x80000000U;
    } else {
        converted = (int)seconds;
        bits = (unsigned int)converted;
    }
    return (time_t)(int)bits;
#else
    long double seconds = (long double)[date timeIntervalSinceReferenceDate]
        + 978307200.0L;
    long long converted = (long long)seconds;

    return (time_t)(int)converted;
#endif
}

static int setFileStat(NSFileManager *manager, struct stat *status, NSString *path) {
    char filePath[1028];
    BOOL success;

    if (![manager getFileSystemRepresentation:filePath maxLength:1024 withPath:path])
        return NO;
    success = chmod(filePath, status->st_mode) == 0;
    if (chown(filePath, status->st_uid, status->st_gid) != 0)
        success = NO;
    return _NSSetFileModificationUNIXTime(path, status->st_mtime) && success;
}

NSString * const NSFileType = @"NSFileType";
NSString * const NSFileTypeDirectory = @"NSFileTypeDirectory";
NSString * const NSFileTypeRegular = @"NSFileTypeRegular";
NSString * const NSFileTypeSymbolicLink = @"NSFileTypeSymbolicLink";
NSString * const NSFileTypeSocket = @"NSFileTypeSocket";
NSString * const NSFileTypeCharacterSpecial = @"NSFileTypeCharacterSpecial";
NSString * const NSFileTypeBlockSpecial = @"NSFileTypeBlockSpecial";
NSString * const NSFileTypeUnknown = @"NSFileTypeUnknown";
NSString * const NSFileSize = @"NSFileSize";
NSString * const NSFileModificationDate = @"NSFileModificationDate";
NSString * const NSFileReferenceCount = @"NSFileReferenceCount";
NSString * const NSFileDeviceIdentifier = @"NSFileDeviceIdentifier";
NSString * const NSFileIdentifier = @"NSFileIdentifier";
NSString * const NSFileOwnerAccountName = @"NSFileOwnerAccountName";
NSString * const NSFileGroupOwnerAccountName = @"NSFileGroupOwnerAccountName";
NSString * const NSFilePosixPermissions = @"NSFilePosixPermissions";
NSString * const NSFileSystemNumber = @"NSFileSystemNumber";
NSString * const NSFileSystemFileNumber = @"NSFileSystemFileNumber";
NSString * const NSFileSystemSize = @"NSFileSystemSize";
NSString * const NSFileSystemFreeSize = @"NSFileSystemFreeSize";
NSString * const NSFileSystemNodes = @"NSFileSystemNodes";
NSString * const NSFileSystemFreeNodes = @"NSFileSystemFreeNodes";

@interface NSFileManager (NSDirectoryListingInternal)
- (NSArray *)directoryContentsAtPath:(NSString *)path matchingExtension:(NSString *)extension options:(unsigned)options keepExtension:(BOOL)keepExtension;
@end

#if defined(__ppc__) || defined(__POWERPC__)
#define NSAllDescendantPathsEnumeratorIndex idx
#else
#define NSAllDescendantPathsEnumeratorIndex index
#endif

@interface NSAllDescendantPathsEnumerator : NSDirectoryEnumerator {
    NSString *path;
    NSArray *contents;
    unsigned NSAllDescendantPathsEnumeratorIndex;
    NSString *prepend;
    NSDictionary *fileAttributes;
    NSDictionary *directoryAttributes;
    NSAllDescendantPathsEnumerator *under;
    BOOL cross;
}
+ (id)newWithPath:(NSString *)path prepend:(NSString *)prepend attributes:(NSDictionary *)attributes cross:(BOOL)cross;
- (id)_under;
@end

@interface NSFileAttributes : NSDictionary {
    NSDictionary *dict;
    struct stat statInfo;
}
+ (id)attributesWithStat:(struct stat *)status;
- (id)objectForKey:(id)key;
@end

@interface _NSUserAccount : NSObject {
    NSString *_loginName;
    NSString *_fullName;
    unsigned _accountNumber;
    NSString *_homeDirectory;
    void *_reserved;
}
+ (id)accountWithName:(NSString *)name;
+ (id)accountWithNumber:(unsigned)number;
+ (id)currentAccount;
- (unsigned)accountNumber;
- (NSString *)accountName;
- (NSString *)fullName;
- (NSString *)homeDirectory;
- (id)initWithPasswordEntry:(struct passwd *)entry;
- (id)userDictionary;
@end

@interface _NSGroupAccount : NSObject {
    NSString *_groupName;
    unsigned _accountNumber;
    NSMutableArray *_users;
    void *_reserved;
}
+ (id)accountWithName:(NSString *)name;
+ (id)accountWithNumber:(unsigned)number;
+ (id)currentAccount;
- (unsigned)accountNumber;
- (NSString *)accountName;
- (NSMutableArray *)members;
- (id)initWithGroupEntry:(struct group *)entry;
- (id)groupDictionary;
@end

static NSMutableDictionary *LoginDictionary;
static NSMapTable *UidMapTable;
static BOOL PasswordsSearched;
static NSMutableDictionary *GroupDictionary;
static NSMapTable *GidMapTable;
static BOOL GroupsSearched;

static const void *NSFileManagerAccountMapKey(unsigned number) {
    return (const void *)(unsigned long)number;
}

static void NSLoadUserAccountDictionaries(id accountClass) {
    struct passwd *entry;

    setpwent();
    while ((entry = getpwent()) != NULL) {
        if (NSMapGet(UidMapTable, NSFileManagerAccountMapKey(entry->pw_uid)) == NULL) {
            id account = [[accountClass allocWithZone:NULL]
                initWithPasswordEntry:entry];
            (void)account;
        }
    }
    endpwent();
    PasswordsSearched = YES;
}

static void NSLoadGroupAccountDictionaries(id accountClass) {
    struct group *entry;

    setgrent();
    while ((entry = getgrent()) != NULL) {
        NSNumber *lookupKey = [NSNumber numberWithShort:(short)entry->gr_gid];

        if (NSMapGet(GidMapTable, lookupKey) == NULL) {
            id account = [[accountClass allocWithZone:NULL]
                initWithGroupEntry:entry];
            (void)account;
        }
    }
    endgrent();
    GroupsSearched = YES;
}

static NSFileManager *NSFileManagerDefaultManager;

BOOL _NSFileExistsAtPath(NSFileManager *manager, const unichar *characters,
                         unsigned length, struct stat *status) {
    char filePath[1028];
    NSCheapMutableString *path =
        [[NSCheapMutableString allocWithZone:NULL] init];

    [path setContentsNoCopy:(void *)characters length:length freeWhenDone:NO
                  isUnicode:YES];
    if (![manager getFileSystemRepresentation:filePath maxLength:1026
                                      withPath:path]) {
        [path release];
        return NO;
    }
    [path release];
    if (lstat(filePath, status) < 0)
        return NO;
    return (status->st_mode & 0xF200) == 0xA200
        || (status->st_mode & 0xF000) != 0xA000
        || stat(filePath, status) >= 0;
}

static BOOL NSFileManagerReportRemovalError(NSFileManager *manager, id handler,
                                           NSString *path, BOOL shouldProceed) {
    NSDictionary *errorInfo;

    if (!shouldProceed)
        return NO;
    errorInfo = [NSDictionary dictionaryWithObjectsAndKeys:
        path, @"Path", @"Error removing", @"Error", nil];
    return [handler fileManager:manager shouldProceedAfterError:errorInfo];
}

int _NSFileModificationUNIXTime(NSString *path, BOOL followLink) {
    char filePath[1028];
    struct stat status;

    if (![path getFileSystemRepresentation:filePath maxLength:1024])
        return 0;
    if ((followLink ? stat(filePath, &status) : lstat(filePath, &status)) < 0)
        return 0;
    return (int)status.st_mtime;
}

static NSString *NSFileTypeForMode(mode_t mode) {
    switch (mode & S_IFMT) {
        case S_IFDIR: return NSFileTypeDirectory;
        case S_IFREG: return NSFileTypeRegular;
        case S_IFLNK: return NSFileTypeSymbolicLink;
        case S_IFSOCK: return NSFileTypeSocket;
        case S_IFCHR: return NSFileTypeCharacterSpecial;
        case S_IFBLK: return NSFileTypeBlockSpecial;
        default: return NSFileTypeUnknown;
    }
}

static NSDictionary *NSFileAttributesFillDictionary(struct stat *status) {
    NSMutableDictionary *values = [[NSMutableDictionary allocWithZone:NULL] init];
    NSDate *modificationDate;
    id value;
    id ownerName;
    id groupName;
    id fileType;

    value = [NSNumber numberWithUnsignedLongLong:(unsigned long long)status->st_size];
    if (value != nil)
        [values setObject:value forKey:NSFileSize];
    modificationDate = [NSDate dateWithTimeIntervalSince1970:
        (NSTimeInterval)status->st_mtime];
    if (modificationDate != nil)
        [values setObject:modificationDate forKey:NSFileModificationDate];
    value = [NSNumber numberWithUnsignedLong:
        (unsigned long)(status->st_mode & 0xFFF)];
    if (value != nil)
        [values setObject:value forKey:NSFilePosixPermissions];
    value = [NSNumber numberWithUnsignedLong:(unsigned long)status->st_nlink];
    if (value != nil)
        [values setObject:value forKey:NSFileReferenceCount];
    value = [NSNumber numberWithUnsignedLong:(unsigned long)status->st_dev];
    if (value != nil)
        [values setObject:value forKey:NSFileSystemNumber];
    value = [NSNumber numberWithUnsignedLong:(unsigned long)status->st_ino];
    if (value != nil)
        [values setObject:value forKey:NSFileSystemFileNumber];
    ownerName = [[_NSUserAccount accountWithNumber:(unsigned)status->st_uid]
        accountName];
    if (ownerName != nil)
        [values setObject:ownerName forKey:NSFileOwnerAccountName];
    groupName = [[_NSGroupAccount accountWithNumber:(unsigned)status->st_gid]
        accountName];
    if (groupName != nil)
        [values setObject:groupName forKey:NSFileGroupOwnerAccountName];
    fileType = NSFileTypeForMode(status->st_mode);
    if (fileType != nil)
        [values setObject:fileType forKey:NSFileType];
    if (S_ISCHR(status->st_mode) || S_ISBLK(status->st_mode))
        [values setObject:[NSNumber numberWithUnsignedLong:(unsigned long)status->st_rdev]
                   forKey:NSFileDeviceIdentifier];
    return values;
}

@implementation NSFileManager

+ (void)initialize {
    [_NSUserAccount initialize];
    [_NSGroupAccount initialize];
}

+ (NSFileManager *)defaultManager {
    if (NSFileManagerDefaultManager == nil) {
        NSFileManager *manager = [self allocWithZone:NULL];
        NSFileManagerDefaultManager = [manager init];
    }
    return NSFileManagerDefaultManager;
}

- (void)dealloc {
    if (self != NSFileManagerDefaultManager)
        [super dealloc];
}

- (NSString *)currentDirectoryPath {
    char path[1028];
    unsigned length;

    if (!_NSGetDirectory2(path, 0x402))
        return nil;
    length = 0;
    while (path[length] != '\0')
        length++;
    return [self stringWithFileSystemRepresentation:path length:length];
}

- (BOOL)changeCurrentDirectoryPath:(NSString *)path {
    char filePath[1028];

    if (![self getFileSystemRepresentation:filePath maxLength:1024 withPath:path])
        return NO;
    return _NSSetDirectory2(filePath);
}

- (BOOL)getFileSystemRepresentation:(char *)cname maxLength:(unsigned)max withPath:(NSString *)path {
    unsigned length;
    unsigned pathLength;
    NSStringEncoding encoding;

    if (path == nil) {
        cname[0] = '\0';
        return NO;
    }
    if ([path isEqualToString:@""])
        return NO;
#if defined(__ppc__) || defined(__POWERPC__)
    encoding = _NSDefaultFileSystemEncoding();
    pathLength = [path length];
#else
    pathLength = [path length];
    encoding = _NSDefaultFileSystemEncoding();
#endif
    if (![path getBytes:cname
              maxLength:max
           filledLength:&length
               encoding:encoding
    allowLossyConversion:NO
                  range:NSMakeRange(0, pathLength)
          remainingRange:NULL]) {
        cname[0] = '\0';
        return NO;
    }
    cname[length] = '\0';
    return YES;
}

- (NSDictionary *)fileAttributesAtPath:(NSString *)path traverseLink:(BOOL)yorn {
    struct stat status;

    if (!(yorn ? fileStatFollow(self, path, &status)
               : fileStat(self, path, &status)))
        return nil;
    return [NSFileAttributes attributesWithStat:&status];
}

- (BOOL)changeFileAttributes:(NSDictionary *)attributes atPath:(NSString *)path {
    char filePath[1028];
    id permissions;
    id modificationDate;
    id ownerName;
    id groupName;
    uid_t userID = (uid_t)-1;
    gid_t groupID = (gid_t)-1;
    BOOL success = YES;

    if ([attributes isKindOfClass:[NSFileAttributes class]])
        return setFileStat(self, &((NSFileAttributes *)attributes)->statInfo, path);
    if (![self getFileSystemRepresentation:filePath maxLength:1024 withPath:path])
        return NO;

    permissions = [attributes objectForKey:NSFilePosixPermissions];
    modificationDate = [attributes objectForKey:NSFileModificationDate];
    ownerName = [attributes objectForKey:NSFileOwnerAccountName];
    groupName = [attributes objectForKey:NSFileGroupOwnerAccountName];
    if (permissions != nil)
        success = chmod(filePath, (mode_t)(unsigned short)[permissions shortValue]) == 0;

    if (ownerName != nil) {
        _NSUserAccount *owner = [_NSUserAccount accountWithName:ownerName];
        userID = (uid_t)(short)[owner accountNumber];
    } else if (groupName != nil) {
        userID = (uid_t)-1;
    }
    if (groupName != nil) {
        _NSGroupAccount *group = [_NSGroupAccount accountWithName:groupName];
        groupID = (gid_t)(short)[group accountNumber];
    }
    if (ownerName != nil || groupName != nil) {
        if (chown(filePath, userID, groupID) != 0)
            success = NO;
    }

    if (modificationDate != nil) {
        time_t seconds = NSFileManagerUNIXTimeFromDate(modificationDate);
        if (!_NSSetFileModificationUNIXTime(path, seconds))
            return NO;
    }
    return success;
}

- (BOOL)fileExistsAtPath:(NSString *)path {
    struct stat status;
    unichar characters[1026];
    unsigned length = [path length];

    if (length >= 0x402)
        length = 0x402;
    [path getCharacters:characters range:NSMakeRange(0, length)];
    return _NSFileExistsAtPath(self, characters, length, &status);
}

- (BOOL)fileExistsAtPath:(NSString *)path isDirectory:(BOOL *)isDirectory {
    struct stat status;
    unichar characters[1026];
    unsigned length = [path length];

    if (length >= 0x402)
        length = 0x402;
    [path getCharacters:characters range:NSMakeRange(0, length)];
    if (!_NSFileExistsAtPath(self, characters, length, &status))
        return NO;
    if (isDirectory != NULL)
        *isDirectory = (status.st_mode & 0xF000) == 0x4000;
    return YES;
}

- (BOOL)isReadableFileAtPath:(NSString *)path {
    return _NSFileAccessibleForMode(path, R_OK);
}

- (BOOL)isWritableFileAtPath:(NSString *)path {
    return _NSFileAccessibleForMode(path, W_OK);
}

- (BOOL)isExecutableFileAtPath:(NSString *)path {
    return _NSFileAccessibleForMode(path, X_OK);
}

typedef struct {
    unsigned char isCString;
    unsigned char allocated;
    unsigned char reserved[2];
    char *cstring;
    unichar *characters;
    unsigned length;
    unsigned char inlineStorage[1008];
} NSFileManagerConversionBuffer;

static void NSFileManagerConvertNameToUTF8(const char *name, unsigned nameLength,
                                           char *output, unsigned *outputLength,
                                           NSCheapMutableString *string) {
    NSFileManagerConversionBuffer converted;

    if (!_NSConvertToASCIIorUnicode2(name, nameLength,
                                      _NSDefaultFileSystemEncoding(), YES,
                                      &converted, NULL)
        || converted.length == 0) {
        output[0] = '\0';
        *outputLength = 0;
        return;
    }
    if (converted.isCString)
        [NSException raise:NSInternalInconsistencyException
                    format:@"%@: Didn't get Unicode", @"_convertToUTF8"];

    [string setContentsNoCopy:converted.characters length:converted.length
                freeWhenDone:NO isUnicode:YES];
    [string getBytes:output maxLength:*outputLength filledLength:outputLength
            encoding:NSUTF8StringEncoding allowLossyConversion:NO
               range:NSMakeRange(0, converted.length) remainingRange:NULL];
    if (converted.allocated)
        NSZoneFree(NULL, converted.characters);
}

static NSArray *NSFileManagerDirectoryList(const char *directoryPath,
                                          const char *suffix,
                                          unsigned suffixLength,
                                          unsigned options,
                                          BOOL keepExtension) {
    int descriptor;
    long base;
    int bytesRead;
    int capacity = 256;
    unsigned contentsLength = 0;
    char *contents;
    char *conversionBuffer;
    NSCheapMutableString *string;
    char directoryEntries[8192];

    descriptor = open(directoryPath, O_RDONLY, 0777);
    if (descriptor < 0)
        return nil;
    string = [[NSCheapMutableString allocWithZone:NULL] init];
    conversionBuffer = NSZoneMalloc(NULL, 0x1000);
    contents = NSZoneMalloc(NULL, capacity);
    do {
        struct direct *entry;
        char *end;

        bytesRead = getdirentries(descriptor, directoryEntries,
                                  sizeof(directoryEntries), &base);
        if (bytesRead <= 0)
            break;
        entry = (struct direct *)directoryEntries;
        end = directoryEntries + bytesRead;
        while ((char *)entry < end) {
            unsigned nameLength = entry->d_namlen;
            unsigned outputLength;

            if (entry->d_ino != 0
                && !((nameLength == 1 && entry->d_name[0] == '.')
                     || (nameLength == 2 && entry->d_name[0] == '.'
                         && entry->d_name[1] == '.'))
                && (suffix == NULL || (suffixLength < nameLength
                    && ((options & 1)
                        ? strcasecmp(entry->d_name + nameLength - suffixLength,
                                     suffix)
                        : strcmp(entry->d_name + nameLength - suffixLength,
                                 suffix)) == 0))) {
                if (suffix != NULL && !keepExtension)
                    nameLength -= suffixLength;
                nameLength++;
                outputLength = 0x1000;
                NSFileManagerConvertNameToUTF8(entry->d_name, nameLength,
                                               conversionBuffer, &outputLength,
                                               string);
                if (capacity < (int)(contentsLength + outputLength)) {
                    do {
                        capacity += 256;
                    } while (capacity < (int)(contentsLength + outputLength));
                    contents = NSZoneRealloc(NULL, contents, capacity);
                }
                memmove(contents + contentsLength, conversionBuffer,
                        outputLength);
                contentsLength += outputLength;
                contents[contentsLength - 1] = '\0';
            }
            entry = (struct direct *)((char *)entry + entry->d_reclen);
        }
    } while (bytesRead > 0);
    NSZoneFree(NULL, conversionBuffer);
    [string release];
    close(descriptor);
    if (bytesRead != -1) {
        NSData *data = [NSData dataWithBytesNoCopy:contents length:contentsLength];
        return [NSStringArray stringArrayWithUTF8Data:data];
    }
    NSZoneFree(NULL, contents);
    return nil;
}

- (NSArray *)directoryContentsAtPath:(NSString *)path matchingExtension:(NSString *)extension options:(unsigned)options keepExtension:(BOOL)keepExtension {
    char directoryPath[1028];
    char extensionPath[1028];
    const char *suffix = NULL;
    unsigned suffixLength = 0;

    if (![self getFileSystemRepresentation:directoryPath maxLength:1024 withPath:path])
        return nil;
    if (extension != nil) {
        extensionPath[0] = '.';
        if (![self getFileSystemRepresentation:extensionPath + 1
                                     maxLength:1023
                                      withPath:extension])
            return nil;
        suffix = extensionPath;
        suffixLength = strlen(suffix);
    }
    return NSFileManagerDirectoryList(directoryPath, suffix, suffixLength,
                                      options, keepExtension);
}

- (BOOL)isDeletableFileAtPath:(NSString *)path {
    NSString *parent = [path stringByDeletingLastPathComponent];
    struct stat parentStatus;
    struct stat pathStatus;

    if (parent == nil || [parent length] == 0)
        parent = [self currentDirectoryPath];
    if (![self isWritableFileAtPath:parent]
        || !fileStat(self, parent, &parentStatus))
        return NO;
    if (!(parentStatus.st_mode & S_ISVTX) || ![self fileExistsAtPath:path])
        return YES;
    if (!fileStat(self, path, &pathStatus))
        return NO;
    return pathStatus.st_uid == getuid();
}

- (NSString *)pathContentOfSymbolicLinkAtPath:(NSString *)path {
    char filePath[1028];
    char linkContents[1024];
    ssize_t length;

    if (![self getFileSystemRepresentation:filePath maxLength:1024 withPath:path])
        return nil;
    length = readlink(filePath, linkContents, sizeof(linkContents));
    if (length < 0)
        return nil;
    return [self stringWithFileSystemRepresentation:linkContents length:(unsigned)length];
}

- (BOOL)createSymbolicLinkAtPath:(NSString *)path pathContent:(NSString *)otherpath {
    char linkPath[1028];
    char linkContents[1028];
    BOOL success;

    success = [self getFileSystemRepresentation:linkPath maxLength:1024
                                       withPath:path];
    if (![self getFileSystemRepresentation:linkContents maxLength:1024
                                  withPath:otherpath])
        success = NO;
    return success && symlink(linkContents, linkPath) == 0;
}

- (NSArray *)_posixPathComponentsWithPath:(NSString *)path {
    NSMutableArray *components = [[NSMutableArray allocWithZone:NULL] init];
    NSScanner *scanner;
    unsigned length;
    unsigned index = 0;

    components = [components autorelease];
    scanner = [NSScanner scannerWithString:path];
    length = [path length];
    if (length == 0)
        return nil;
    if ([path characterAtIndex:0] == '/') {
        [components addObject:@"/"];
        index = 1;
    }
    while (index < length) {
        if ([path characterAtIndex:index] != '/') {
            NSString *component;

            [scanner setScanLocation:index];
            if ([scanner scanUpToString:@"/" intoString:&component]) {
                [components addObject:component];
                index = [scanner scanLocation];
            }
        }
        index++;
    }
    return components;
}

- (BOOL)_replicatePath:(NSString *)source atPath:(NSString *)destination
             operation:(int)operation fileMap:(NSMapTable *)fileMap
               handler:(id)handler {
    struct stat status;
    BOOL shouldNotify = [handler respondsToSelector:
        @selector(fileManager:willProcessPath:)];
    BOOL shouldReport = [handler respondsToSelector:
        @selector(fileManager:shouldProceedAfterError:)];
    BOOL sourcePathConverted;
    BOOL destinationPathConverted;
    mode_t fileType;
    char sourceFile[1028];
    char destinationFile[1028];
    NSString *mappedPath;

    if (shouldNotify)
        [handler fileManager:self willProcessPath:destination];
    if (!fileStat(self, source, &status)) {
        if (shouldReport)
            NSFileManagerReportReplicationError(self, handler, shouldReport, source,
                                                @"Doesn't Exist", nil, nil);
        return NO;
    }

    fileType = status.st_mode & S_IFMT;
    if (fileType == S_IFDIR) {
        unsigned pool = NSPushAutoreleasePool();
        NSString *sourcePrefix = [source stringByAppendingString:@"/"];
        NSString *destinationPrefix = [destination stringByAppendingString:@"/"];
        NSArray *contents = [self directoryContentsAtPath:source];
        mode_t originalMode = status.st_mode;
        unsigned index;
        BOOL succeeded = NO;

        if (contents == nil) {
            succeeded = NSFileManagerReportReplicationError(self, handler, shouldReport,
                source, @"Can't read directory contents", nil, nil);
            return succeeded;
        }

        status.st_mode = 0777;
        if (![self createDirectoryAtPath:destination
                              attributes:[NSFileAttributes attributesWithStat:&status]]) {
            succeeded = NSFileManagerReportReplicationError(self, handler, shouldReport,
                destination, @"Couldn't create directory", nil, nil);
            return succeeded;
        }
        status.st_mode = originalMode;

        for (index = [contents count]; index > 0; index--) {
            NSString *name = [contents objectAtIndex:index - 1];
            NSString *sourceChild = [sourcePrefix stringByAppendingString:name];
            NSString *destinationChild = [destinationPrefix stringByAppendingString:name];

            if (![self _replicatePath:sourceChild atPath:destinationChild
                           operation:operation fileMap:fileMap handler:handler]) {
                return NO;
            }
        }

        setFileStat(self, &status, destination);
        NSPopAutoreleasePool(pool);
        return YES;
    }

    if (operation != 0
        && (fileType == S_IFREG || fileType == S_IFCHR || fileType == S_IFBLK)) {
        sourcePathConverted =
            [self getFileSystemRepresentation:sourceFile maxLength:1024
                                      withPath:source];
        destinationPathConverted =
            [self getFileSystemRepresentation:destinationFile maxLength:1024
                                      withPath:destination];
        if (sourcePathConverted && destinationPathConverted
            && link(sourceFile, destinationFile) == 0)
            return YES;

        if (operation == 2) {
            int savedErrno;
            NSString *errnoText;

            if (!shouldReport)
                return NO;
            savedErrno = cthread_errno();
            errnoText = [NSString stringWithFormat:@"%d", savedErrno];
            return NSFileManagerReportReplicationError(self, handler, shouldReport, source,
                @"Couldn't link", destination, errnoText);
        }
    }

    mappedPath = fileMap != NULL ? (NSString *)NSMapGet(fileMap, &status) : nil;
    if (mappedPath != nil) {
        sourcePathConverted =
            [self getFileSystemRepresentation:sourceFile maxLength:1024
                                      withPath:mappedPath];
        destinationPathConverted =
            [self getFileSystemRepresentation:destinationFile maxLength:1024
                                      withPath:destination];
        if (sourcePathConverted && destinationPathConverted
            && link(sourceFile, destinationFile) == 0)
            return YES;

        if (!shouldReport)
            return NO;
        return NSFileManagerReportReplicationError(self, handler, shouldReport, mappedPath,
            @"Couldn't link", destination, nil);
    }

    if (fileType == S_IFREG) {
        unsigned pool = NSPushAutoreleasePool();
        NSData *contents = [self contentsAtPath:source];
        BOOL succeeded;

        if (contents == nil) {
            succeeded = NSFileManagerReportReplicationError(self, handler, shouldReport,
                source, @"Couldn't open", nil, nil);
            return succeeded;
        }
        succeeded = [self createFileAtPath:destination contents:contents
                                attributes:[NSFileAttributes attributesWithStat:&status]];
        if (succeeded)
            NSPopAutoreleasePool(pool);
        if (succeeded && fileMap != NULL) {
            struct stat *keyCopy = NSZoneMalloc(NULL, sizeof(*keyCopy));

            memcpy(keyCopy, &status, sizeof(*keyCopy));
            NSMapInsertKnownAbsent(fileMap, keyCopy, destination);
        }
        if (succeeded) {
            return YES;
        }
    } else if (fileType == S_IFLNK) {
        NSString *linkContents = [self pathContentOfSymbolicLinkAtPath:source];

        if (linkContents != nil
            && [self createSymbolicLinkAtPath:destination pathContent:linkContents])
            return YES;
    } else if (fileType == S_IFCHR || fileType == S_IFBLK) {
        if ([self getFileSystemRepresentation:destinationFile maxLength:1024
                                      withPath:destination]
            && mknod(destinationFile, status.st_mode, status.st_rdev) == 0)
            return YES;
    } else {
        [NSException raise:NSInvalidArgumentException
                    format:@"unknown file type %x for file %@", status.st_mode, source];
        return YES;
    }

    if (!shouldReport)
        return NO;
    return NSFileManagerReportReplicationError(self, handler, shouldReport, destination,
                                               @"Couldn't create", nil, nil);
}

- (BOOL)contentsEqualAtPath:(NSString *)path1 andPath:(NSString *)path2 {
    struct stat firstStatus;
    struct stat secondStatus;
    mode_t firstType;
    mode_t secondType;

    if (!fileStat(self, path1, &firstStatus)
        || !fileStat(self, path2, &secondStatus))
        return NO;
    if (firstStatus.st_dev == secondStatus.st_dev
        && firstStatus.st_ino == secondStatus.st_ino)
        return YES;

    firstType = firstStatus.st_mode & S_IFMT;
    secondType = secondStatus.st_mode & S_IFMT;
    if (firstType != secondType)
        return NO;
    if (firstType == S_IFCHR || firstType == S_IFBLK)
        return firstStatus.st_rdev == secondStatus.st_rdev;
    if (firstType == S_IFLNK) {
        NSString *firstContents;
        NSString *secondContents;

#if defined(__i386__)
        secondContents = [self pathContentOfSymbolicLinkAtPath:path2];
        firstContents = [self pathContentOfSymbolicLinkAtPath:path1];
#else
        firstContents = [self pathContentOfSymbolicLinkAtPath:path1];
        secondContents = [self pathContentOfSymbolicLinkAtPath:path2];
#endif

        return [firstContents isEqualToString:secondContents];
    }
    if (firstType == S_IFDIR) {
        NSArray *firstContents = [self directoryContentsAtPath:path1];
        NSArray *secondContents = [self directoryContentsAtPath:path2];
        NSSet *secondContentSet = [NSSet setWithArray:secondContents];
        unsigned count = [firstContents count];
        NSString *firstPrefix = [path1 stringByAppendingString:@"/"];
        NSString *secondPrefix = [path2 stringByAppendingString:@"/"];

        if (count == [secondContentSet count]) {
            while (count != 0) {
                NSString *name = [firstContents objectAtIndex:--count];

                if (![secondContentSet containsObject:name]
                    || ![self contentsEqualAtPath:
                        [firstPrefix stringByAppendingString:name]
                        andPath:[secondPrefix stringByAppendingString:name]])
                    return NO;
            }
            return YES;
        }
        return NO;
    }
    if (firstType != S_IFREG) {
        [NSException raise:NSInvalidArgumentException
                    format:@"unknown file type %x for file %@",
                           firstStatus.st_mode, path1];
        return NO;
    }
    if (firstStatus.st_ctimespec.tv_nsec != secondStatus.st_ctimespec.tv_nsec)
        return NO;
    if (firstStatus.st_birthtimespec.tv_sec != secondStatus.st_birthtimespec.tv_sec)
        return NO;

    {
        char firstPathCheck[1028];
        char secondPath[1028];
        char *firstPath;
        unsigned char firstBuffer[8192];
        unsigned char secondBuffer[8192];
        int firstDescriptor;
        int secondDescriptor;
        BOOL equal = YES;

        if (![self getFileSystemRepresentation:firstPathCheck maxLength:1024
                                       withPath:path1])
            return NO;
        firstPath = (char *)[self fileSystemRepresentationWithPath:path1];
        firstDescriptor = _NSOpenFileDescriptor(firstPath, O_RDONLY, 0);
        if (firstDescriptor < 0)
            return NO;
        if (![self getFileSystemRepresentation:secondPath maxLength:1024
                                       withPath:path2]) {
            _NSCloseFileDescriptor(firstDescriptor);
            return NO;
        }
        secondDescriptor = _NSOpenFileDescriptor(secondPath, O_RDONLY, 0);
        if (secondDescriptor < 0) {
            _NSCloseFileDescriptor(firstDescriptor);
            return NO;
        }

        while (1) {
            ssize_t firstLength = _NSReadFromFileDescriptor(firstDescriptor,
                firstBuffer, sizeof(firstBuffer));

            if (firstLength <= 0) {
                if (firstLength < 0)
                    equal = NO;
                break;
            }
            if (_NSReadFromFileDescriptor(secondDescriptor, secondBuffer,
                    (size_t)firstLength) != firstLength
                || memcmp(firstBuffer, secondBuffer, (size_t)firstLength) != 0) {
                equal = NO;
                break;
            }
        }
        if (_NSCloseFileDescriptor(firstDescriptor) != 0)
            equal = NO;
        if (_NSCloseFileDescriptor(secondDescriptor) != 0)
            equal = NO;
        return equal;
    }
}

- (BOOL)linkPath:(NSString *)src toPath:(NSString *)dest handler:handler {
    return [self _replicatePath:src atPath:dest operation:2
                        fileMap:NULL handler:handler];
}

- (BOOL)copyPath:(NSString *)src toPath:(NSString *)dest handler:handler {
    NSMapTable *fileMap = NSFileStatMapCreate();
    BOOL succeeded = [self _replicatePath:src atPath:dest operation:0
                                  fileMap:fileMap handler:handler];

    NSFreeMapTable(fileMap);
    return succeeded;
}

- (BOOL)movePath:(NSString *)src toPath:(NSString *)dest handler:handler {
    BOOL shouldReport = [handler respondsToSelector:
        @selector(fileManager:shouldProceedAfterError:)];
    BOOL shouldNotify = [handler respondsToSelector:
        @selector(fileManager:willProcessPath:)];
    char sourceFile[1028];
    char destinationFile[1028];
    NSArray *components;
    NSMutableArray *temporaryComponents;
    NSString *temporaryPath;
    char *temporaryFile;
    NSMapTable *fileMap;
    BOOL succeeded;
    BOOL sourcePathConverted;
    BOOL destinationPathConverted;

    if (shouldNotify)
        [handler fileManager:self willProcessPath:dest];
    sourcePathConverted =
        [self getFileSystemRepresentation:sourceFile maxLength:1024 withPath:src];
    destinationPathConverted =
        [self getFileSystemRepresentation:destinationFile maxLength:1024 withPath:dest];
    if (!sourcePathConverted || !destinationPathConverted
        || [self fileExistsAtPath:dest]) {
        if (shouldReport)
            NSFileManagerReportReplicationError(self, handler, shouldReport, src,
                                                @"Already Exists", nil, nil);
        return NO;
    }
    if (_NSMoveFile(sourceFile, destinationFile) == 0)
        return YES;

    components = [self _posixPathComponentsWithPath:dest];
    temporaryComponents = [components mutableCopyWithZone:NULL];
    [temporaryComponents replaceObjectAtIndex:[temporaryComponents count] - 1
                                   withObject:[[NSProcessInfo processInfo]
                                       globallyUniqueString]];
    temporaryPath = [temporaryComponents componentsJoinedByString:@"/"];
    [temporaryComponents release];
    temporaryFile = (char *)[self fileSystemRepresentationWithPath:temporaryPath];
    fileMap = NSFileStatMapCreate();
    succeeded = [self _replicatePath:src atPath:temporaryPath operation:1
                             fileMap:fileMap handler:handler];
    NSFreeMapTable(fileMap);
    if (!succeeded) {
        [self removeFileAtPath:temporaryPath handler:handler];
        return NO;
    }

    if (_NSMoveFile(temporaryFile, destinationFile) != 0) {
        [self removeFileAtPath:temporaryPath handler:handler];
        if (!shouldReport)
            return NO;
        return NSFileManagerReportReplicationError(self, handler, shouldReport, temporaryPath,
            @"Error renaming", dest, nil);
    }
    return [self removeFileAtPath:src handler:handler];
}

- (BOOL)removeFileAtPath:(NSString *)path handler:(id)handler {
    BOOL shouldProceed = [handler respondsToSelector:@selector(fileManager:shouldProceedAfterError:)];
    BOOL shouldNotify = [handler respondsToSelector:@selector(fileManager:willProcessPath:)];
    struct stat status;
    char filePath[1028];

    if (shouldNotify)
        [handler fileManager:self willProcessPath:path];
    if (!fileStat(self, path, &status))
        return NSFileManagerReportRemovalError(self, handler, path, shouldProceed);

    if ((status.st_mode & 0xF000) != 0x4000) {
        if ([self getFileSystemRepresentation:filePath maxLength:1024 withPath:path]
            && unlink(filePath) == 0)
            return YES;
        return NSFileManagerReportRemovalError(self, handler, path, shouldProceed);
    }

    {
        NSArray *contents;
        NSMutableString *childPath = [[path mutableCopyWithZone:NULL] autorelease];
        unsigned childStart = [path length] + 1;
        unsigned childLength = 0;
        unsigned index;
        BOOL pathConversionFailed;

        [childPath replaceCharactersInRange:NSMakeRange([childPath length], 0)
                                 withString:@"/"];
        if ([path isEqualToString:@"."] || [path isEqualToString:@".."])
            [NSException raise:NSInvalidArgumentException
                        format:@"attempting to remove \".\" or \"..\""];
        pathConversionFailed =
            ![self getFileSystemRepresentation:filePath maxLength:1024 withPath:path];
        chmod(filePath, (status.st_mode & 0x3f) | 0700);
        if (rmdir(filePath) == 0)
            return YES;

        contents = [self directoryContentsAtPath:path];
        if (contents == nil) {
            NSDictionary *errorInfo;

            if (!shouldProceed)
                return NO;
            errorInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                path, @"Path", @"Could not read directory", @"Error", nil];
            return [handler fileManager:self shouldProceedAfterError:errorInfo];
        }
        for (index = [contents count]; index > 0; index--) {
            NSString *component = [contents objectAtIndex:index - 1];

            if (childLength != 0)
                [childPath replaceCharactersInRange:NSMakeRange(childStart, childLength)
                                          withString:@""];
            [childPath replaceCharactersInRange:NSMakeRange([childPath length], 0)
                                     withString:component];
            childLength = [component length];

            if (![self removeFileAtPath:childPath handler:handler]
                && !NSFileManagerReportRemovalError(self, handler, path, shouldProceed))
                return NO;
        }
        {
            char temporaryPath[1044];
            NSString *parent = [path stringByDeletingLastPathComponent];
            int descriptor;
            BOOL moved = NO;
            int result = -1;

            if ([self getFileSystemRepresentation:temporaryPath maxLength:1024 withPath:parent]
                && _NSmkstemp83(temporaryPath, "del", &descriptor) == 0) {
                close(descriptor);
                unlink(temporaryPath);
                if (rename(filePath, temporaryPath) == 0)
                    moved = YES;
            }

            if (!pathConversionFailed) {
                if (!moved)
                    strcpy(temporaryPath, filePath);
                result = rmdir(temporaryPath);
            }
            if (!pathConversionFailed && result < 0 && cthread_errno() == ENOTEMPTY) {
#if defined(__ppc__) || defined(__POWERPC__)
                NSArray *entries = NSFileManagerDirectoryList(temporaryPath,
                                                               NULL, 0, 0, YES);
                NSString *directoryPath = [self stringWithFileSystemRepresentation:
                    temporaryPath length:(unsigned)strlen(temporaryPath)];
                unsigned index;

                for (index = [entries count]; index > 0; index--) {
                    NSString *entryPath = [directoryPath
                        stringByAppendingPathComponent:[entries objectAtIndex:index - 1]];
                    [self removeFileAtPath:entryPath handler:nil];
                }
#else
                DIR *directory = opendir(temporaryPath);

                if (directory != NULL) {
                    struct dirent *entry;
                    unsigned directoryLength = strlen(temporaryPath);

                    while ((entry = readdir(directory)) != NULL) {
                        char *entryPath;
                        size_t nameLength;

                        if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0)
                            continue;
                        nameLength = strlen(entry->d_name);
                        if (directoryLength + nameLength + 2 > sizeof(temporaryPath)) {
                            break;
                        }
                        temporaryPath[directoryLength] = '/';
                        entryPath = temporaryPath + directoryLength + 1;
                        memcpy(entryPath, entry->d_name, nameLength + 1);
                        if (unlink(temporaryPath) < 0) {
                            temporaryPath[directoryLength] = '\0';
                            break;
                        }
                        temporaryPath[directoryLength] = '\0';
                    }
                    if (closedir(directory) == 0)
                        result = rmdir(temporaryPath);
                }
#endif
            }
            if (result == 0)
                return YES;
        }
    }
    return NSFileManagerReportRemovalError(self, handler, path, shouldProceed);
}

- (NSArray *)directoryContentsAtPath:(NSString *)path {
    return [self directoryContentsAtPath:path
                       matchingExtension:nil
                                 options:0
                           keepExtension:YES];
}

- (NSDirectoryEnumerator *)enumeratorAtPath:(NSString *)path {
    NSDictionary *attributes = [self fileAttributesAtPath:path traverseLink:YES];

    if (attributes == nil)
        return nil;
    return [[NSAllDescendantPathsEnumerator
        newWithPath:path prepend:nil attributes:attributes cross:YES] autorelease];
}

- (NSArray *)subpathsAtPath:(NSString *)path {
    return [[self enumeratorAtPath:path] allObjects];
}

- (BOOL)createDirectoryAtPath:(NSString *)path attributes:(NSDictionary *)attributes {
    if (!_NSCreateDirectory(path))
        return NO;
    if (attributes != nil)
        [self changeFileAttributes:attributes atPath:path];
    return YES;
}

- (BOOL)directoryCanBeCreatedAtPath:(NSString *)path {
    NSString *parent;
    char *filePath = (char *)[path fileSystemRepresentation];

    parent = [path stringByDeletingLastPathComponent];

    if (!_NSFileAccessibleForMode(parent, 3))
        return NO;
    if (_NSCreateDirectory2(filePath)) {
        _NSRemoveDirectory2(filePath);
    } else if (cthread_errno() != EEXIST) {
        return NO;
    }
    return YES;
}

- (NSData *)contentsAtPath:(NSString *)path {
    return [[[NSData allocWithZone:NULL] initWithContentsOfFile:path] autorelease];
}

- (BOOL)createFileAtPath:(NSString *)path contents:(NSData *)data attributes:(NSDictionary *)attr {
#if defined(__ppc__) || defined(__POWERPC__)
    NSData *contents = data == nil ? [NSData data] : data;
    BOOL success = [contents writeToFile:path atomically:YES];

    if (success && attr != nil)
        [self changeFileAttributes:attr atPath:path];
    return success;
#else
    NSString *temporaryPath = [path stringByAppendingString:
        [[NSProcessInfo processInfo] globallyUniqueString]];
    char temporaryFile[1028];
    char destinationFile[1028];
    int descriptor;
    BOOL success;
    unsigned length;

    if (![self getFileSystemRepresentation:temporaryFile maxLength:1024 withPath:temporaryPath])
        return NO;
    descriptor = _NSOpenFileDescriptor(temporaryFile, O_WRONLY | O_CREAT, 0700);
    if (descriptor < 0)
        return NO;
    length = [data length];
    success = _NSWriteToFileDescriptor(descriptor, [data bytes], length)
        == (ssize_t)length;
    if (_NSCloseFileDescriptor(descriptor) != 0)
        success = NO;
    if (![self getFileSystemRepresentation:destinationFile maxLength:1024 withPath:path]
        || _NSMoveFile(temporaryFile, destinationFile) != 0) {
        success = NO;
        _NSDeleteFile2(temporaryFile);
    }
    if (success && attr != nil)
        [self changeFileAttributes:attr atPath:path];
    return success;
#endif
}

- (NSDictionary *)fileSystemAttributesAtPath:(NSString *)path {
    char filePath[1028];
    struct statfs status;
    id fileSystemSize;
    id fileSystemFreeSize;
    id fileSystemNodes;
    id fileSystemFreeNodes;
    id fileSystemNumber;

    if (![self getFileSystemRepresentation:filePath maxLength:1024 withPath:path]
        || statfs(filePath, &status) != 0)
        return nil;

#if defined(__ppc__) || defined(__POWERPC__)
    fileSystemNumber = [NSNumber numberWithUnsignedLong:
        (unsigned long)status.f_fsid.val[0]];
    fileSystemSize = [NSNumber numberWithUnsignedLongLong:
        (unsigned long long)status.f_bsize * status.f_blocks];
    fileSystemFreeSize = [NSNumber numberWithUnsignedLongLong:
        (unsigned long long)status.f_bsize * status.f_bavail];
    fileSystemNodes = [NSNumber numberWithUnsignedLong:
        (unsigned long)status.f_files];
    fileSystemFreeNodes = [NSNumber numberWithUnsignedLong:
        (unsigned long)status.f_ffree];
#else
    fileSystemFreeNodes = [NSNumber numberWithUnsignedLong:
        (unsigned long)status.f_ffree];
    fileSystemNodes = [NSNumber numberWithUnsignedLong:
        (unsigned long)status.f_files];
    fileSystemFreeSize = [NSNumber numberWithUnsignedLongLong:
        (unsigned long long)status.f_bsize * status.f_bavail];
    fileSystemSize = [NSNumber numberWithUnsignedLongLong:
        (unsigned long long)status.f_bsize * status.f_blocks];
    fileSystemNumber = [NSNumber numberWithUnsignedLong:
        (unsigned long)status.f_fsid.val[0]];
#endif

    return [NSDictionary dictionaryWithObjectsAndKeys:
        fileSystemSize, NSFileSystemSize,
        fileSystemFreeSize, NSFileSystemFreeSize,
        fileSystemNodes, NSFileSystemNodes,
        fileSystemFreeNodes, NSFileSystemFreeNodes,
        fileSystemNumber, NSFileSystemNumber,
        nil];
}

- (const char *)fileSystemRepresentationWithPath:(NSString *)path {
    char bytes[1028];
    unsigned length;
    unsigned pathLength;
    NSStringEncoding encoding;
    NSData *data;

    if (path == nil) {
#if defined(__ppc__) || defined(__POWERPC__)
        [NSException raise:NSInvalidArgumentException
                    format:@"%@: nil path parameter",
                           _NSMethodExceptionProem(self, _cmd)];
#else
        [NSException raise:NSInvalidArgumentException
                    format:@"nil passed to fileSystemRepresentationWithPath:"];
#endif
    }
    if ([path isEqualToString:@""]) {
#if defined(__ppc__) || defined(__POWERPC__)
        [NSException raise:NSInvalidArgumentException
                    format:@"%@: empty string path parameter",
                           _NSMethodExceptionProem(self, _cmd)];
#else
        [NSException raise:NSInvalidArgumentException
                    format:@"empty string passed to fileSystemRepresentationWithPath:"];
#endif
    }
#if defined(__ppc__) || defined(__POWERPC__)
    encoding = _NSDefaultFileSystemEncoding();
    pathLength = [path length];
#else
    pathLength = [path length];
    encoding = _NSDefaultFileSystemEncoding();
#endif
    if (![path getBytes:bytes
              maxLength:1024
           filledLength:&length
               encoding:encoding
    allowLossyConversion:NO
                  range:NSMakeRange(0, pathLength)
          remainingRange:NULL]) {
        [NSException raise:NSInvalidArgumentException
                    format:@"*** Couldn't convert path '%@' to file system representation",
                           _NSMethodExceptionProem(self, _cmd), path];
    }
    bytes[length] = '\0';
    data = [NSData dataWithBytes:bytes length:length + 1];
    return [data bytes];
}

- (NSString *)stringWithFileSystemRepresentation:(const char *)str length:(unsigned)len {
    NSString *string;
#if defined(__ppc__) || defined(__POWERPC__)
    string = [[NSString allocWithZone:NULL]
        initWithBytes:str length:len encoding:_NSDefaultFileSystemEncoding()];
#else
    NSStringEncoding encoding = _NSDefaultFileSystemEncoding();
    string = [[NSString allocWithZone:NULL]
        initWithBytes:str length:len encoding:encoding];
#endif
    return [string autorelease];
}

@end

@implementation _NSUserAccount

+ (void)initialize {
    if (UidMapTable == NULL) {
#if defined(__ppc__) || defined(__POWERPC__)
        NSMapTableValueCallBacks valueCallBacks = {0};

        valueCallBacks.retain = NSObjectMapValueCallBacks.describe;
#else
        NSMapTableValueCallBacks valueCallBacks = NSObjectMapValueCallBacks;
#endif
        UidMapTable = NSCreateMapTableWithZone(NSIntMapKeyCallBacks,
                                               valueCallBacks, 0, NULL);
    }
    if (LoginDictionary == NULL)
        LoginDictionary = [[NSMutableDictionary allocWithZone:NULL] init];
}

+ (id)accountWithName:(NSString *)name {
    id account = [LoginDictionary objectForKey:name];

    if (account == nil && !PasswordsSearched) {
        NSLoadUserAccountDictionaries(self);
        account = [LoginDictionary objectForKey:name];
    }
    return account;
}

+ (id)accountWithNumber:(unsigned)number {
    id account = NSMapGet(UidMapTable, NSFileManagerAccountMapKey(number));

    if (account == nil) {
        struct passwd *entry = NULL;

        if (!PasswordsSearched)
            entry = getpwuid((uid_t)number);
        if (entry != NULL) {
            account = [[self allocWithZone:NULL] initWithPasswordEntry:entry];
        }
        if (account == nil) {
            account = [self allocWithZone:NULL];
            ((_NSUserAccount *)account)->_accountNumber = number;
            NSMapInsert(UidMapTable, NSFileManagerAccountMapKey(number), account);
            [account release];
        }
    }
    return account;
}

+ (id)currentAccount {
    return [self accountWithNumber:(unsigned)getuid()];
}

- (unsigned)accountNumber {
    return _accountNumber;
}

- (NSString *)accountName {
    return _loginName;
}

- (NSString *)fullName {
    return _fullName;
}

- (NSString *)homeDirectory {
    return _homeDirectory;
}

- (id)initWithPasswordEntry:(struct passwd *)entry {
    if (entry == NULL) {
        [self release];
        return nil;
    }
    if (entry->pw_name != NULL)
        _loginName = [[NSString allocWithZone:NULL]
            initWithCString:entry->pw_name length:(unsigned)strlen(entry->pw_name)];
    if (entry->pw_dir != NULL)
        _homeDirectory = [[NSString allocWithZone:NULL]
            initWithCString:entry->pw_dir length:(unsigned)strlen(entry->pw_dir)];
    if (entry->pw_gecos != NULL)
        _fullName = [[NSString allocWithZone:NULL]
            initWithCString:entry->pw_gecos length:(unsigned)strlen(entry->pw_gecos)];
    _accountNumber = (unsigned)entry->pw_uid;
    NSMapInsert(UidMapTable, NSFileManagerAccountMapKey(_accountNumber), self);
    [self release];
    if (_loginName != nil)
        [LoginDictionary setObject:self forKey:_loginName];
    return self;
}

- (id)userDictionary {
    NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];

    if (_loginName != nil)
        [dictionary setObject:_loginName forKey:@"Login Name"];
    if (_fullName != nil)
        [dictionary setObject:_fullName forKey:@"Full Name"];
    if (_homeDirectory != nil)
        [dictionary setObject:_homeDirectory forKey:@"Home Directory"];
    if (_accountNumber != 0)
        [dictionary setObject:[NSString stringWithFormat:@"%u", _accountNumber]
                       forKey:@"Account Number"];
    return dictionary;
}

- (unsigned)hash {
    return (unsigned)[_loginName hash];
}

- (BOOL)isEqual:(id)object {
    if (object == self)
        return YES;
    if (![object isKindOfClass:[_NSUserAccount class]])
        return NO;
    return [_loginName isEqualToString:[object accountName]]
        && _accountNumber == [object accountNumber];
}

- (NSString *)description {
    return [[self userDictionary] description];
}

@end

@implementation _NSGroupAccount

+ (void)initialize {
    if (GidMapTable == NULL) {
#if defined(__ppc__) || defined(__POWERPC__)
        NSMapTableValueCallBacks valueCallBacks = {0};

        valueCallBacks.retain = NSObjectMapValueCallBacks.describe;
#else
        NSMapTableValueCallBacks valueCallBacks = NSObjectMapValueCallBacks;
#endif
        GidMapTable = NSCreateMapTableWithZone(NSIntMapKeyCallBacks,
                                               valueCallBacks, 0, NULL);
    }
    if (GroupDictionary == NULL)
        GroupDictionary = [[NSMutableDictionary allocWithZone:NULL] init];
}

+ (id)accountWithName:(NSString *)name {
    id account = [GroupDictionary objectForKey:name];

    if (account == nil && !GroupsSearched) {
        NSLoadGroupAccountDictionaries(self);
        account = [GroupDictionary objectForKey:name];
    }
    return account;
}

+ (id)accountWithNumber:(unsigned)number {
    id account = NSMapGet(GidMapTable, NSFileManagerAccountMapKey(number));

    if (account == nil) {
        struct group *entry = NULL;

        if (!GroupsSearched)
            entry = getgrgid((gid_t)number);
        if (entry != NULL) {
            account = [[self allocWithZone:NULL] initWithGroupEntry:entry];
        }
        if (account == nil) {
            account = [self allocWithZone:NULL];
            ((_NSGroupAccount *)account)->_accountNumber = number;
            NSMapInsert(GidMapTable, NSFileManagerAccountMapKey(number), account);
            [account release];
        }
    }
    return account;
}

+ (id)currentAccount {
    return [self accountWithNumber:(unsigned)getgid()];
}

- (unsigned)accountNumber {
    return _accountNumber;
}

- (NSString *)accountName {
    return _groupName;
}

- (NSMutableArray *)members {
    return _users;
}

- (id)initWithGroupEntry:(struct group *)entry {
    char **member;

    if (entry == NULL) {
        [self release];
        return nil;
    }
    if (entry->gr_name != NULL)
        _groupName = [[NSString allocWithZone:NULL]
            initWithCString:entry->gr_name length:(unsigned)strlen(entry->gr_name)];
    _accountNumber = (unsigned)entry->gr_gid;
    if (entry->gr_mem != NULL) {
        _users = [[NSMutableArray allocWithZone:NULL] init];
        for (member = entry->gr_mem; *member != NULL; member++) {
            NSString *name = [NSString stringWithCString:*member
                                                  length:(unsigned)strlen(*member)];
            [_users addObject:name];
        }
    }
    NSMapInsert(GidMapTable, NSFileManagerAccountMapKey(_accountNumber), self);
    [self release];
    if (_groupName != nil)
        [GroupDictionary setObject:self forKey:_groupName];
    return self;
}

- (id)groupDictionary {
    NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];

    if (_groupName != nil)
        [dictionary setObject:_groupName forKey:@"Group Name"];
    if (_accountNumber != 0)
        [dictionary setObject:[NSString stringWithFormat:@"%u", _accountNumber]
                       forKey:@"Account Number"];
    if (_users != nil)
        [dictionary setObject:_users forKey:@"Group Members"];
    return dictionary;
}

- (unsigned)hash {
    return (unsigned)[_groupName hash];
}

- (BOOL)isEqual:(id)object {
    if (object == self)
        return YES;
    if (![object isKindOfClass:[_NSGroupAccount class]])
        return NO;
    return [_groupName isEqualToString:[object accountName]]
        && _accountNumber == [object accountNumber];
}

- (NSString *)description {
    return [[self groupDictionary] description];
}

@end

@implementation NSFileAttributes

+ (id)attributesWithStat:(struct stat *)status {
    NSFileAttributes *attributes = [self allocWithZone:NULL];

    memmove(&attributes->statInfo, status, sizeof(attributes->statInfo));
    return [attributes autorelease];
}

- (void)dealloc {
    [dict release];
    [super dealloc];
}

- (id)objectForKey:(id)key {
    if (dict != nil)
        return [dict objectForKey:key];
    if ([key isEqualToString:NSFileModificationDate])
        return [NSDate dateWithTimeIntervalSince1970:(NSTimeInterval)statInfo.st_mtime];
    if ([key isEqualToString:NSFileSize])
        return [NSNumber numberWithUnsignedLongLong:(unsigned long long)statInfo.st_size];
    if ([key isEqualToString:NSFilePosixPermissions])
        return [NSNumber numberWithUnsignedLong:(unsigned long)(statInfo.st_mode & 0xFFF)];
    if ([key isEqualToString:NSFileType])
        return NSFileTypeForMode(statInfo.st_mode);
    if ([key isEqualToString:NSFileReferenceCount])
        return [NSNumber numberWithUnsignedLong:(unsigned long)statInfo.st_nlink];
    if ([key isEqualToString:NSFileSystemNumber])
        return [NSNumber numberWithUnsignedLong:(unsigned long)statInfo.st_dev];
    if ([key isEqualToString:NSFileSystemFileNumber])
        return [NSNumber numberWithUnsignedLong:(unsigned long)statInfo.st_ino];
    if ([key isEqualToString:NSFileOwnerAccountName])
        return [[_NSUserAccount accountWithNumber:(unsigned)statInfo.st_uid]
            accountName];
    if ([key isEqualToString:NSFileGroupOwnerAccountName])
        return [[_NSGroupAccount accountWithNumber:(unsigned)statInfo.st_gid]
            accountName];
    if ([key isEqualToString:NSFileDeviceIdentifier]
        && (S_ISCHR(statInfo.st_mode) || S_ISBLK(statInfo.st_mode)))
        return [NSNumber numberWithUnsignedLong:(unsigned long)statInfo.st_rdev];
    return nil;
}

- (unsigned)count {
    if (dict == nil)
        dict = NSFileAttributesFillDictionary(&statInfo);
    return [dict count];
}

- (NSEnumerator *)keyEnumerator {
    if (dict == nil)
        dict = NSFileAttributesFillDictionary(&statInfo);
    return [dict keyEnumerator];
}

- (unsigned)hash {
    if (dict == nil)
        dict = NSFileAttributesFillDictionary(&statInfo);
    return [dict hash];
}

- (BOOL)isEqual:(id)object {
    NSFileAttributes *other;

    if (object == nil)
        return NO;
    if (object->isa != self->isa)
        return [object isEqual:self];
    other = object;
    return statInfo.st_ino == other->statInfo.st_ino
        && statInfo.st_dev == other->statInfo.st_dev
        && statInfo.st_mtime == other->statInfo.st_mtime
        && statInfo.st_mode == other->statInfo.st_mode
        && statInfo.st_size == other->statInfo.st_size
        && statInfo.st_nlink == other->statInfo.st_nlink
        && statInfo.st_uid == other->statInfo.st_uid
        && statInfo.st_gid == other->statInfo.st_gid;
}

- (NSDate *)fileModificationDate {
    return [NSDate dateWithTimeIntervalSince1970:
                (NSTimeInterval)statInfo.st_mtime];
}

- (NSString *)fileType {
    return NSFileTypeForMode(statInfo.st_mode);
}

- (unsigned long long)fileSize {
    return (unsigned long long)(unsigned)statInfo.st_size;
}

- (unsigned long)filePosixPermissions {
    return (unsigned long)(statInfo.st_mode & 0xFFF);
}

- (NSString *)fileOwnerAccountName {
    return [[_NSUserAccount accountWithNumber:(unsigned)statInfo.st_uid]
        accountName];
}

- (unsigned long)fileOwnerAccountNumber {
    return (unsigned long)statInfo.st_uid;
}

- (NSString *)fileGroupOwnerAccountName {
    return [[_NSGroupAccount accountWithNumber:(unsigned)statInfo.st_gid]
        accountName];
}

- (unsigned long)fileGroupOwnerAccountNumber {
    return (unsigned long)statInfo.st_gid;
}

- (unsigned long)fileSystemNumber {
    return (unsigned long)statInfo.st_dev;
}

- (unsigned long)fileSystemFileNumber {
    return (unsigned long)statInfo.st_ino;
}

@end

@implementation NSDictionary (NSFileAttributes)

- (unsigned long long)fileSize {
    return (unsigned long long)[[self objectForKey:NSFileSize] longLongValue];
}

- (NSDate *)fileModificationDate {
    return [self objectForKey:NSFileModificationDate];
}

- (NSString *)fileType {
    return [self objectForKey:NSFileType];
}

- (unsigned long)filePosixPermissions {
    return (unsigned long)[[self objectForKey:NSFilePosixPermissions]
        unsignedIntValue] & 0xFFF;
}

- (NSString *)fileOwnerAccountName {
    return [self objectForKey:NSFileOwnerAccountName];
}

- (unsigned long)fileOwnerAccountNumber {
    return 0;
}

- (NSString *)fileGroupOwnerAccountName {
    return [self objectForKey:NSFileGroupOwnerAccountName];
}

- (unsigned long)fileGroupOwnerAccountNumber {
    return 0;
}

- (unsigned long)fileSystemNumber {
    return (unsigned long)[[self objectForKey:NSFileSystemNumber]
        unsignedIntValue];
}

- (unsigned long)fileSystemFileNumber {
    return (unsigned long)[[self objectForKey:NSFileSystemFileNumber]
        unsignedIntValue];
}

@end

@implementation NSDirectoryEnumerator

- (NSDictionary *)fileAttributes {
    NSRequestConcreteImplementation(self, _cmd, [NSDirectoryEnumerator class]);
    return nil;
}

- (NSDictionary *)directoryAttributes {
    NSRequestConcreteImplementation(self, _cmd, [NSDirectoryEnumerator class]);
    return nil;
}

- (id)nextObject {
    NSRequestConcreteImplementation(self, _cmd, [NSDirectoryEnumerator class]);
    return nil;
}

- (void)skipDescendents {
    NSRequestConcreteImplementation(self, _cmd, [NSDirectoryEnumerator class]);
}

@end

@implementation NSAllDescendantPathsEnumerator

+ (id)newWithPath:(NSString *)directoryPath
          prepend:(NSString *)prefix
       attributes:(NSDictionary *)attributes
            cross:(BOOL)crossFilesystems {
    NSAllDescendantPathsEnumerator *enumerator = [[self allocWithZone:NULL] init];
    NSFileManager *manager = [NSFileManager defaultManager];

    enumerator->contents = [[manager directoryContentsAtPath:directoryPath] retain];
    enumerator->prepend = [prefix copyWithZone:NULL];
    enumerator->path = [[directoryPath stringByAppendingString:@"/"] retain];
    enumerator->directoryAttributes = [attributes retain];
    enumerator->cross = crossFilesystems;
    return enumerator;
}

- (id)_under {
    return under;
}

- (void)dealloc {
    [under release];
    [contents release];
    [path release];
    [prepend release];
    [directoryAttributes release];
    [fileAttributes release];
    [super dealloc];
}

- (NSDictionary *)directoryAttributes {
    return directoryAttributes;
}

- (NSDictionary *)fileAttributes {
    return fileAttributes;
}

- (id)nextObject {
    NSFileManager *manager;
    NSString *name = nil;
    NSString *entryPath = nil;
    struct stat status;

    if (under != nil) {
        id object = [under nextObject];

        if (object != nil) {
            [fileAttributes release];
            fileAttributes = [under->fileAttributes retain];
            [directoryAttributes release];
            directoryAttributes = [under->directoryAttributes retain];
            return object;
        }
        [under release];
        under = nil;
    }

    [fileAttributes release];
    fileAttributes = nil;
    while (NSAllDescendantPathsEnumeratorIndex < [contents count]) {
        if (fileAttributes != nil)
            break;
        name = [contents objectAtIndex:NSAllDescendantPathsEnumeratorIndex++];
        entryPath = [path stringByAppendingString:name];
        manager = [NSFileManager defaultManager];
        if (fileStat(manager, entryPath, &status)) {
            fileAttributes = [[NSFileAttributes attributesWithStat:&status] retain];
            if (fileAttributes != nil && !cross
                && [fileAttributes fileSystemNumber]
                    != [directoryAttributes fileSystemNumber])
                fileAttributes = nil;
        }
    }
    if (fileAttributes == nil)
        return nil;

    if (S_ISDIR(status.st_mode)) {
        NSString *childPrefix = prepend != nil
            ? [prepend stringByAppendingPathComponent:name] : name;
        under = [NSAllDescendantPathsEnumerator
            newWithPath:entryPath
               prepend:childPrefix
            attributes:fileAttributes
                 cross:cross];
    }
    return prepend != nil
        ? [prepend stringByAppendingPathComponent:name]
        : name;
}

- (void)skipDescendents {
    if (under == nil || [under _under] != nil) {
        [under skipDescendents];
    } else {
        [under release];
        under = nil;
    }
}

@end
