/*	NSData.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSData.h>
#import <Foundation/NSException.h>
#import <Foundation/NSObjCRuntime.h>
#import <Foundation/NSZone.h>
#import <Foundation/NSString.h>
#import <Foundation/NSURL.h>
#import <Foundation/NSCoder.h>
#import <Foundation/NSDebug.h>
#import <Foundation/NSLock.h>
#import <mach/mach.h>
#include <cthreads.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

extern void _NSGenericFree(void *ptr);
extern int _NSmkstemp83(char *path, const char *prefix, int *descriptor);
#if defined(__ppc__) || defined(__POWERPC__)
extern int _NSReadBytesFromFile(char *path, void **bytes, unsigned *length,
                                NSZone *zone, char allocatePages);
#else
extern int _NSReadBytesFromFile(char *path, void **bytes, unsigned *length,
                                NSZone *zone);
#endif

@interface NSString (NSDataFilePathConversion)
- (BOOL)getFileSystemRepresentation:(char *)buffer maxLength:(unsigned)maxLength;
@end

@interface NSConcreteData : NSData {
@public
    unsigned char _flags;
    unsigned char _padding[3];
    unsigned _length;
    unsigned _capacity;
    unsigned char *_bytes;
}

- (id)initWithBytes:(const void *)bytes length:(unsigned)length
               copy:(BOOL)copy freeWhenDone:(BOOL)freeWhenDone
        bytesAreVM:(BOOL)bytesAreVM;
- (BOOL)_bytesAreVM;
- (void)dealloc;

@end

@interface NSData (NSConcreteDataPrivate)
- (id)initWithBytes:(const void *)bytes length:(unsigned)length
               copy:(BOOL)copy freeWhenDone:(BOOL)freeWhenDone
        bytesAreVM:(BOOL)bytesAreVM;
- (BOOL)_bytesAreVM;
@end

@interface NSSubrangeData : NSData {
@public
    unsigned _reserved;
    NSRange _range;
    NSData *_data;
}

- (id)initWithData:(NSData *)data range:(NSRange)range;
- (BOOL)_bytesAreVM;

@end

@interface NSConcreteMutableData : NSMutableData {
@public
    unsigned char _flags;
    unsigned char _padding[3];
    unsigned _length;
    unsigned _capacity;
    unsigned char *_bytes;
}

- (id)initWithCapacity:(unsigned)capacity;
- (unsigned)length;
- (const void *)bytes;
- (void *)mutableBytes;
- (void)setLength:(unsigned)length;
- (void)appendBytes:(const void *)bytes length:(unsigned)length;
- (void)appendData:(NSData *)data;
- (void)increaseLengthBy:(unsigned)extraLength;
- (void)replaceBytesInRange:(NSRange)range withBytes:(const void *)bytes;
- (void)resetBytesInRange:(NSRange)range;
- (void)dealloc;

@end

extern id _NSMethodExceptionProem(id object, SEL selector);
extern NSLock *_NSGlobalRetainLock;

#if defined(__ppc__) || defined(__POWERPC__)
volatile unsigned int __NSDataRetainLock;
extern int _NSIsMultiThreaded;

static BOOL NSDataLockRetainCount(void)
{
    if (!_NSIsMultiThreaded)
        return NO;
    for (;;) {
        unsigned oldValue;
        unsigned acquired;
        unsigned one = 1;

        __asm__ volatile(
            "1: lwarx %0,0,%2\n\t"
            "cmpwi %0,0\n\t"
            "bne- 2f\n\t"
            "stwcx. %3,0,%2\n\t"
            "bne- 1b\n\t"
            "isync\n\t"
            "li %1,1\n\t"
            "b 3f\n"
            "2: li %1,0\n"
            "3:"
            : "=&r" (oldValue), "=&r" (acquired)
            : "r" (&__NSDataRetainLock), "r" (one)
            : "cr0", "memory");
        if (acquired && oldValue == 0)
            return YES;
        cthread_yield();
    }
}

static void NSDataUnlockRetainCount(BOOL locked)
{
    if (locked) {
        __asm__ volatile("sync" ::: "memory");
        __NSDataRetainLock = 0;
    }
}
#else
static BOOL NSDataLockRetainCount(void)
{
    if (_NSGlobalRetainLock == nil)
        return NO;
    [_NSGlobalRetainLock lock];
    return YES;
}

static void NSDataUnlockRetainCount(BOOL locked)
{
    if (locked)
        [_NSGlobalRetainLock unlock];
}
#endif

static void NSDataCopyBytes(void *destination, const void *source,
                            unsigned length) {
    if (NSPageSize() <= length
        && (((unsigned)source | (unsigned)destination) & (NSPageSize() - 1)) == 0) {
        unsigned pageLength = NSRoundDownToMultipleOfPageSize(length);
        NSCopyMemoryPages(source, destination, pageLength);
        source = (const unsigned char *)source + pageLength;
        destination = (unsigned char *)destination + pageLength;
        length -= pageLength;
    }
    if (length != 0)
        memmove(destination, source, length);
}

#if defined(__ppc__) || defined(__POWERPC__)
#define NSDataInlineBytesFlag 0x80000000U
#define NSDataFreeWhenDoneFlag 0x40000000U
#define NSDataBytesAreVMFlag 0x20000000U
#define NSDataFlagsMask 0xE0000000U
#else
#define NSDataInlineBytesFlag 0x00000001U
#define NSDataFreeWhenDoneFlag 0x00000002U
#define NSDataBytesAreVMFlag 0x00000004U
#define NSDataFlagsMask 0x00000007U
#endif

static unsigned NSDataGetFlags(const unsigned char *flags) {
    return *(const unsigned *)flags & NSDataFlagsMask;
}

static void NSDataUpdateFlags(unsigned char *flags, unsigned clearMask,
                              unsigned setMask) {
    unsigned *word = (unsigned *)flags;

    *word = (*word & ~clearMask) | setMask;
}

static unsigned NSDataReadInt32(const unsigned char *bytes) {
    return (unsigned)bytes[0] | ((unsigned)bytes[1] << 8)
        | ((unsigned)bytes[2] << 16) | ((unsigned)bytes[3] << 24);
}

static void NSDataWriteInt32(unsigned char *bytes, unsigned value) {
    bytes[0] = (unsigned char)value;
    bytes[1] = (unsigned char)(value >> 8);
    bytes[2] = (unsigned char)(value >> 16);
    bytes[3] = (unsigned char)(value >> 24);
}

static unsigned NSDataFirstByteAfterIntersecting(const unsigned char *left,
                                                 const unsigned char *right,
                                                 unsigned length) {
    while (length != 0) {
        length--;
        if ((left[length] & right[length]) != 0)
            return length + 1;
    }
    return 0;
}

static BOOL NSDataAllZeroBytes(const unsigned char *bytes, unsigned length) {
    while (length-- != 0) {
        if (*bytes++ != 0)
            return NO;
    }
    return YES;
}

static BOOL NSDataIsCompressedBitVector(const unsigned char *bytes,
                                        unsigned length) {
    return length != 0 && bytes[length - 1] == 0;
}

static unsigned NSDataCompressedBitVectorRunCount(const unsigned char *bytes,
                                                   unsigned length) {
    return bytes[length - 2];
}

static unsigned NSDataCompressedBitVectorPayloadLength(unsigned length,
                                                        unsigned runCount) {
    return length - runCount * 3 - 2;
}

static void NSDataCompressedBitVectorRun(const unsigned char *bytes,
                                         unsigned payloadLength,
                                         unsigned index,
                                         unsigned *offset,
                                         unsigned *zeroLength) {
    const unsigned char *run = bytes + payloadLength + index * 3;

    *offset = (unsigned)run[0] | ((unsigned)run[1] << 8);
    *zeroLength = run[2];
}

static BOOL NSDataGetFileSystemPath(NSString *path, char *buffer, unsigned capacity) {
    unsigned maxLength;

    if (path == nil || capacity == 0)
        return NO;
    maxLength = capacity - 1;
    if (maxLength > 1024)
        maxLength = 1024;
    return [path getFileSystemRepresentation:buffer maxLength:maxLength];
}

int _NSMapBytesFromFile(NSString *path, vm_offset_t *address,
                        vm_size_t *length) {
#if defined(__ppc__) || defined(__POWERPC__)
    return _NSReadBytesFromFile(path, (void **)address, (unsigned *)length,
                                NULL, 1);
#else
    char filePath[1028];
    struct stat status;
    vm_size_t mappedLength;
    int descriptor;
    kern_return_t result;

    if (![path getFileSystemRepresentation:filePath maxLength:1024])
        return NO;
    *address = 0;
    descriptor = open(filePath, O_RDONLY, 0666);
    if (descriptor < 0)
        return NO;
    if (fstat(descriptor, &status) < 0) {
        int savedError = cthread_errno();
        close(descriptor);
        cthread_set_errno_self(savedError);
        errno = savedError;
        return NO;
    }
    mappedLength = (vm_size_t)status.st_size;
    result = map_fd(descriptor, 0, address, TRUE, mappedLength);
    if (result != KERN_SUCCESS) {
        int savedError = cthread_errno();
        close(descriptor);
        cthread_set_errno_self(savedError);
        errno = savedError;
        return NO;
    }
    close(descriptor);
    *length = mappedLength;
    if (NSKeepAllocationStatistics)
        NSRecordAllocationEvent(NSVMAllocateEvent, *address, *length);
    return 1;
#endif
}

BOOL _NSWriteBytesToFile(NSString *path, const void *bytes,
                         unsigned length, BOOL atomically) {
    char filePath[1028];
    char temporaryPath[1044];
    char backupPath[1044];
    struct stat status;
    mode_t mask;
    mode_t fileMode;
    int descriptor;

    if (!NSDataGetFileSystemPath(path, filePath, sizeof(filePath)))
        return NO;
    if (stat(filePath, &status) == 0) {
        fileMode = status.st_mode;
    } else {
        if (errno != ENOENT)
            return NO;
        mask = umask(0);
        umask(mask);
        fileMode = (mode_t)(~mask & 0666);
    }

    if (atomically) {
        char *slash = strrchr(filePath, '/');
        if (slash == NULL)
            temporaryPath[0] = 0;
        else {
            unsigned directoryLength = (unsigned)(slash - filePath + 1);
            if (directoryLength >= sizeof(temporaryPath))
                return NO;
            memcpy(temporaryPath, filePath, directoryLength);
            temporaryPath[directoryLength] = 0;
        }
        if (_NSmkstemp83(temporaryPath, "data", &descriptor) < 0)
            return NO;
    } else {
        descriptor = open(filePath, O_WRONLY | O_CREAT | O_TRUNC, 0666);
    }
    if (descriptor < 0)
        return NO;
    if (length != 0 && write(descriptor, bytes, length) != (ssize_t)length) {
        int savedError = errno;
        if (atomically)
            unlink(temporaryPath);
        close(descriptor);
        errno = savedError;
        return NO;
    }
    fsync(descriptor);
    close(descriptor);

    if (atomically) {
        if (rename(temporaryPath, filePath) < 0) {
            int savedError = errno;

            if (savedError != EINVAL) {
                unlink(temporaryPath);
                errno = savedError;
                return NO;
            }
            {
                char *slash = strrchr(filePath, '/');
                if (slash == NULL)
                    backupPath[0] = 0;
                else {
                    unsigned directoryLength = (unsigned)(slash - filePath + 1);
                    if (directoryLength >= sizeof(backupPath)) {
                        unlink(temporaryPath);
                        return NO;
                    }
                    memcpy(backupPath, filePath, directoryLength);
                    backupPath[directoryLength] = 0;
                }
            }
            if (_NSmkstemp83(backupPath, "data", &descriptor) < 0) {
                unlink(temporaryPath);
                errno = savedError;
                return NO;
            }
            close(descriptor);
            unlink(backupPath);
            if (rename(filePath, backupPath) < 0 ||
                rename(temporaryPath, filePath) < 0) {
                int moveError = errno;
                BOOL backupRestored = access(backupPath, F_OK) < 0;
                if (!backupRestored)
                    backupRestored = rename(backupPath, filePath) == 0;
                unlink(temporaryPath);
                if (backupRestored)
                    unlink(backupPath);
                errno = moveError;
                return NO;
            }
            unlink(backupPath);
        }
        chmod(filePath, fileMode);
    }
    return YES;
}

@implementation NSConcreteData

- (id)init {
    return [self initWithBytes:NULL length:0 copy:NO freeWhenDone:NO bytesAreVM:NO];
}

- (id)initWithBytes:(const void *)bytes length:(unsigned)length
               copy:(BOOL)copy freeWhenDone:(BOOL)freeWhenDone
        bytesAreVM:(BOOL)bytesAreVM {
    NSConcreteData *result = self;

    if (length > 0x3FFFFFFF) {
        id proem = _NSMethodExceptionProem(self, _cmd);
        [NSException raise:NSInvalidArgumentException
                    format:@"%@: absurd %s: %d", proem, "length", length];
    }
    if (length == 0) {
        NSDataUpdateFlags(&_flags, NSDataFlagsMask, 0);
        _length = 0;
        _capacity = 0;
        _bytes = NULL;
#if defined(__ppc__) || defined(__POWERPC__)
        if (freeWhenDone && bytes != NULL)
            _NSGenericFree((void *)bytes);
#endif
        return self;
    }

    if (copy) {
        if (length < NSPageSize()) {
            if (length > 16) {
                Class dataClass = [self class];
                NSZone *zone = NSZoneFromPointer(self);
                NSDeallocateObject(self);
                result = NSAllocateObject(dataClass, length - 16, zone);
            }
            result->_capacity = length;
            memmove(&result->_bytes, bytes, length);
            NSDataUpdateFlags(&result->_flags, NSDataFlagsMask,
                              NSDataInlineBytesFlag);
        } else {
            unsigned pageCapacity = NSRoundUpToMultipleOfPageSize(length);
            result->_capacity = pageCapacity;
            result->_bytes = NSAllocateMemoryPages(pageCapacity);
            if ((((unsigned)result->_bytes | (unsigned)bytes) &
                 (NSPageSize() - 1)) == 0) {
                unsigned pageLength = NSRoundDownToMultipleOfPageSize(length);
                if (pageLength != 0)
                    NSCopyMemoryPages(bytes, result->_bytes, pageLength);
                if (length > pageLength)
                    memmove(result->_bytes + pageLength,
                            (const unsigned char *)bytes + pageLength,
                            length - pageLength);
            } else {
                memmove(result->_bytes, bytes, length);
            }
            NSDataUpdateFlags(&result->_flags, NSDataFlagsMask,
                              NSDataFreeWhenDoneFlag | NSDataBytesAreVMFlag);
        }
    } else {
        result->_capacity = bytesAreVM
            ? NSRoundUpToMultipleOfPageSize(length) : length;
        result->_bytes = (unsigned char *)bytes;
        NSDataUpdateFlags(&result->_flags, NSDataFlagsMask,
            (bytesAreVM ? NSDataBytesAreVMFlag : 0) |
            (freeWhenDone ? NSDataFreeWhenDoneFlag : 0));
    }
    result->_length = length;
    return result;
}

- (unsigned)length {
    return _length;
}

- (void)getBytes:(void *)buffer {
    NSDataCopyBytes(buffer, (NSDataGetFlags(&_flags) & NSDataInlineBytesFlag)
        != 0 ? (const void *)&_bytes : _bytes, _length);
}

- (void)getBytes:(void *)buffer length:(unsigned)length {
    if (_length < length)
        length = _length;
    NSDataCopyBytes(buffer, (NSDataGetFlags(&_flags) & NSDataInlineBytesFlag)
        != 0 ? (const void *)&_bytes : _bytes, length);
}

- (void)getBytes:(void *)buffer range:(NSRange)range {
    unsigned length = range.length;
    const unsigned char *source;

    if (length == 0)
        return;
    if (_length <= range.location) {
        id proem = _NSMethodExceptionProem(self, _cmd);
        [NSException raise:NSRangeException
                    format:@"%@: location %u exceeds data length %u",
         proem, range.location, _length];
    }
    if (_length < range.location + length)
        length = _length - range.location;
    source = (NSDataGetFlags(&_flags) & NSDataInlineBytesFlag) != 0
        ? (const unsigned char *)&_bytes : _bytes;
    NSDataCopyBytes(buffer, source + range.location, length);
}

- (int)deserializeIntAtIndex:(unsigned)index {
    const unsigned char *bytes;

    if (_length < index + 4) {
        id proem;
        NSString *rangeString;

#if defined(__ppc__) || defined(__POWERPC__)
        proem = _NSMethodExceptionProem(self, _cmd);
        rangeString = NSStringFromRange(NSMakeRange(index, 4));
#else
        rangeString = NSStringFromRange(NSMakeRange(index, 4));
        proem = _NSMethodExceptionProem(self, _cmd);
#endif
        [NSException raise:NSRangeException
                    format:@"%@: range %@ exceeds data length %u",
         proem, rangeString, _length];
    }
    bytes = (NSDataGetFlags(&_flags) & NSDataInlineBytesFlag) != 0
        ? (const unsigned char *)&_bytes : _bytes;
    return (int)NSDataReadInt32(bytes + index);
}

- (void)deserializeInts:(int *)intBuffer count:(unsigned)count
                atIndex:(unsigned)index {
    unsigned length = count * 4;
    const unsigned char *bytes;
    unsigned item;

    if (_length < length + index) {
        if (length != 0) {
            id proem;
            NSString *rangeString;

#if defined(__ppc__) || defined(__POWERPC__)
            proem = _NSMethodExceptionProem(self, _cmd);
            rangeString = NSStringFromRange(NSMakeRange(index, length));
#else
            rangeString = NSStringFromRange(NSMakeRange(index, length));
            proem = _NSMethodExceptionProem(self, _cmd);
#endif
            [NSException raise:NSRangeException
                        format:@"%@: range %@ exceeds data length %u",
             proem, rangeString, _length];
        } else {
            id proem = _NSMethodExceptionProem(self, _cmd);
            [NSException raise:NSRangeException
                        format:@"%@: location %u exceeds data length %u",
             proem, index, _length];
        }
    }
    bytes = (NSDataGetFlags(&_flags) & NSDataInlineBytesFlag) != 0
        ? (const unsigned char *)&_bytes : _bytes + index;
    for (item = 0; item < count; item++) {
        *intBuffer++ = (int)NSDataReadInt32(bytes);
        bytes += 4;
    }
}

- (int)deserializeIntAtCursor:(unsigned *)cursor {
    unsigned index = *cursor;
    const unsigned char *bytes;
    int value;

    if (_length < index + 4) {
        id proem;
        NSString *rangeString;

#if defined(__ppc__) || defined(__POWERPC__)
        proem = _NSMethodExceptionProem(self, _cmd);
        rangeString = NSStringFromRange(NSMakeRange(index, 4));
#else
        rangeString = NSStringFromRange(NSMakeRange(index, 4));
        proem = _NSMethodExceptionProem(self, _cmd);
#endif
        [NSException raise:NSRangeException
                    format:@"%@: range %@ exceeds data length %u",
         proem, rangeString, _length];
    }
    bytes = (NSDataGetFlags(&_flags) & NSDataInlineBytesFlag) != 0
        ? (const unsigned char *)&_bytes : _bytes;
    value = (int)NSDataReadInt32(bytes + index);
    *cursor = index + 4;
    return value;
}

- (unsigned)deserializeAlignedBytesLengthAtCursor:(unsigned *)cursor {
    unsigned index = *cursor;
    const unsigned char *bytes;
    unsigned value;

    if (_length < index + 4) {
        id proem;
        NSString *rangeString;

#if defined(__ppc__) || defined(__POWERPC__)
        proem = _NSMethodExceptionProem(self, _cmd);
        rangeString = NSStringFromRange(NSMakeRange(index, 4));
#else
        rangeString = NSStringFromRange(NSMakeRange(index, 4));
        proem = _NSMethodExceptionProem(self, _cmd);
#endif
        [NSException raise:NSRangeException
                    format:@"%@: range %@ exceeds data length %u",
         proem, rangeString, _length];
    }
    bytes = (NSDataGetFlags(&_flags) & NSDataInlineBytesFlag) != 0
        ? (const unsigned char *)&_bytes : _bytes;
    value = NSDataReadInt32(bytes + index);
    index += 4;
    *cursor = index;
    if (value == 0x80000000U) {
        unsigned padding;

        if (_length < index + 8) {
            id proem;
            NSString *rangeString;

#if defined(__ppc__) || defined(__POWERPC__)
            proem = _NSMethodExceptionProem(self, _cmd);
            rangeString = NSStringFromRange(NSMakeRange(index, 8));
#else
            rangeString = NSStringFromRange(NSMakeRange(index, 8));
            proem = _NSMethodExceptionProem(self, _cmd);
#endif
            [NSException raise:NSRangeException
                        format:@"%@: range %@ exceeds data length %u",
             proem, rangeString, _length];
        }
        value = NSDataReadInt32(bytes + index);
        padding = NSDataReadInt32(bytes + index + 4);
        index += padding + 8;
        *cursor = index;
    }
    return value;
}

- (const void *)bytes {
    return (NSDataGetFlags(&_flags) & NSDataInlineBytesFlag) != 0
        ? (const void *)&_bytes : _bytes;
}

- (BOOL)_bytesAreVM {
    return (NSDataGetFlags(&_flags) & NSDataBytesAreVMFlag) != 0;
}

- (id)copyWithZone:(NSZone *)zone {
    return [self retain];
}

- (id)retain {
    unsigned *refCount = (unsigned *)&_flags;
    BOOL locked = NSDataLockRetainCount();
#if defined(__ppc__) || defined(__POWERPC__)
    unsigned value = *refCount;
    unsigned count = value & 0x1fffffffU;

    if (count != 0x1fffffffU)
        *refCount = (value & 0xe0000000U) | ((count + 1) & 0x1fffffffU);
#else
    unsigned count;

    count = *refCount >> 3;
    if (count != 0x1fffffffU)
        *refCount = (*refCount & 7U) | ((count + 1) << 3);
#endif
    NSDataUnlockRetainCount(locked);
    if (NSKeepAllocationStatistics)
        NSRecordAllocationEvent(NSObjectInternalRefIncrementedEvent, self);
    return self;
}

- (oneway void)release {
    unsigned *refCount = (unsigned *)&_flags;
    BOOL shouldDeallocate = NO;
    BOOL locked;

    if (NSKeepAllocationStatistics)
        NSRecordAllocationEvent(NSObjectInternalRefDecrementedEvent, self);
    locked = NSDataLockRetainCount();
#if defined(__ppc__) || defined(__POWERPC__)
    {
        unsigned value = *refCount;
        unsigned count = value & 0x1fffffffU;

        if (count != 0) {
            if (count != 0x1fffffffU)
                *refCount = (value & 0xe0000000U)
                    | ((count - 1) & 0x1fffffffU);
        } else {
            shouldDeallocate = YES;
        }
    }
#else
    if ((*refCount & 0xfffffff8U) != 0) {
        unsigned count = *refCount >> 3;

        if (count != 0x1fffffffU)
            *refCount = (*refCount & 7U) | ((count - 1) << 3);
    } else {
        shouldDeallocate = YES;
    }
#endif
    NSDataUnlockRetainCount(locked);
    if (shouldDeallocate)
        [self dealloc];
}

- (unsigned)retainCount {
#if defined(__ppc__) || defined(__POWERPC__)
    return (*(unsigned *)&_flags & 0x1fffffffU) + 1;
#else
    return (*(unsigned *)&_flags >> 3) + 1;
#endif
}

- (void)dealloc {
    unsigned flags = NSDataGetFlags(&_flags);

    if ((flags & (NSDataInlineBytesFlag | NSDataFreeWhenDoneFlag)) ==
        NSDataFreeWhenDoneFlag) {
        if ((flags & NSDataBytesAreVMFlag) != 0)
            NSDeallocateMemoryPages(_bytes, _capacity);
        else
            _NSGenericFree(_bytes);
    }
    [super dealloc];
}

@end

@implementation NSSubrangeData

- (id)init {
    id proem = _NSMethodExceptionProem(self, _cmd);
    [NSException raise:NSGenericException
                format:@"%@: should never be called", proem];
    return nil;
}

- (id)initWithData:(NSData *)data range:(NSRange)range {
    unsigned dataLength = [data length];

    if (dataLength < range.location + range.length) {
        if (range.length == 0) {
            id proem = _NSMethodExceptionProem(self, _cmd);
            [NSException raise:NSRangeException
                        format:@"%@: location %u exceeds data length %u",
             proem, range.location, dataLength];
        } else {
            id proem;
            NSString *rangeString;

#if defined(__ppc__) || defined(__POWERPC__)
            proem = _NSMethodExceptionProem(self, _cmd);
            rangeString = NSStringFromRange(range);
#else
            rangeString = NSStringFromRange(range);
            proem = _NSMethodExceptionProem(self, _cmd);
#endif
            [NSException raise:NSRangeException
                        format:@"%@: range %@ exceeds data length %u",
             proem, rangeString, dataLength];
        }
    }
    if ([data isKindOfClass:[NSSubrangeData class]]) {
        NSSubrangeData *subrange = (NSSubrangeData *)data;
        _range.location = range.location + subrange->_range.location;
        _range.length = range.length;
        _data = [subrange->_data retain];
    } else {
        _range = range;
        _data = [data copyWithZone:NULL];
    }
    return self;
}

- (unsigned)length {
    return _range.length;
}

- (const void *)bytes {
    return (const unsigned char *)[_data bytes] + _range.location;
}

- (BOOL)_bytesAreVM {
    return [_data _bytesAreVM];
}

- (void)getBytes:(void *)buffer range:(NSRange)range {
    unsigned length = range.length;
    const unsigned char *source;

    if (length == 0)
        return;
    if (_range.length <= range.location) {
        id proem = _NSMethodExceptionProem(self, _cmd);
        [NSException raise:NSRangeException
                    format:@"%@: range location %u exceeds data length %u",
         proem, range.location, _range.length];
    }
    if (_range.length < range.location + length)
        length = _range.length - range.location;
    source = (const unsigned char *)[_data bytes] + _range.location + range.location;
    if (length >= NSPageSize() &&
        (((unsigned)source | (unsigned)buffer) & (NSPageSize() - 1)) == 0) {
        unsigned pageLength = NSRoundDownToMultipleOfPageSize(length);
        NSCopyMemoryPages(source, buffer, pageLength);
        source += pageLength;
        buffer = (unsigned char *)buffer + pageLength;
        length -= pageLength;
    }
    if (length != 0)
        memmove(buffer, source, length);
}

- (void)getBytes:(void *)buffer {
    NSDataCopyBytes(buffer,
                    (const unsigned char *)[_data bytes] + _range.location,
                    _range.length);
}

- (void)getBytes:(void *)buffer length:(unsigned)length {
    if (_range.length < length)
        length = _range.length;
    NSDataCopyBytes(buffer,
                    (const unsigned char *)[_data bytes] + _range.location,
                    length);
}

- (int)deserializeIntAtIndex:(unsigned)index {
    const unsigned char *bytes;

    if (_range.length < index + 4) {
        id proem;
        NSString *rangeString;

#if defined(__ppc__) || defined(__POWERPC__)
        proem = _NSMethodExceptionProem(self, _cmd);
        rangeString = NSStringFromRange(NSMakeRange(index, 4));
#else
        rangeString = NSStringFromRange(NSMakeRange(index, 4));
        proem = _NSMethodExceptionProem(self, _cmd);
#endif
        [NSException raise:NSRangeException
                    format:@"%@: range %@ exceeds data length %u",
         proem, rangeString, _range.length];
    }
    bytes = (const unsigned char *)[_data bytes] + _range.location + index;
    return (int)NSDataReadInt32(bytes);
}

- (void)deserializeInts:(int *)intBuffer count:(unsigned)count
                atIndex:(unsigned)index {
    unsigned length = count * 4;
    const unsigned char *bytes;
    unsigned item;

    if (_range.length < length + index) {
        if (length != 0) {
            id proem;
            NSString *rangeString;

#if defined(__ppc__) || defined(__POWERPC__)
            proem = _NSMethodExceptionProem(self, _cmd);
            rangeString = NSStringFromRange(NSMakeRange(index, length));
#else
            rangeString = NSStringFromRange(NSMakeRange(index, length));
            proem = _NSMethodExceptionProem(self, _cmd);
#endif
            [NSException raise:NSRangeException
                        format:@"%@: range %@ exceeds data length %u",
             proem, rangeString, _range.length];
        } else {
            id proem = _NSMethodExceptionProem(self, _cmd);
            [NSException raise:NSRangeException
                        format:@"%@: location %u exceeds data length %u",
             proem, index, _range.length];
        }
    }
    bytes = (const unsigned char *)[_data bytes] + _range.location + index;
    for (item = 0; item < count; item++) {
        *intBuffer++ = (int)NSDataReadInt32(bytes);
        bytes += 4;
    }
}

- (int)deserializeIntAtCursor:(unsigned *)cursor {
    unsigned index = *cursor;
    const unsigned char *bytes;

    if (_range.length < index + 4) {
        id proem;
        NSString *rangeString;

#if defined(__ppc__) || defined(__POWERPC__)
        proem = _NSMethodExceptionProem(self, _cmd);
        rangeString = NSStringFromRange(NSMakeRange(index, 4));
#else
        rangeString = NSStringFromRange(NSMakeRange(index, 4));
        proem = _NSMethodExceptionProem(self, _cmd);
#endif
        [NSException raise:NSRangeException
                    format:@"%@: range %@ exceeds data length %u",
         proem, rangeString, _range.length];
    }
    bytes = (const unsigned char *)[_data bytes] + _range.location + index;
    *cursor = index + 4;
    return (int)NSDataReadInt32(bytes);
}

- (id)copyWithZone:(NSZone *)zone {
    (void)zone;
    return [self retain];
}

- (id)retain {
    unsigned *refCount = &_reserved;
#if defined(__ppc__) || defined(__POWERPC__)
    BOOL locked = NSDataLockRetainCount();
    unsigned value = *refCount;
    unsigned count = value & 0x1fffffffU;

    if (count != 0x1fffffffU)
        *refCount = (value & 0xe0000000U) | ((count + 1) & 0x1fffffffU);
    NSDataUnlockRetainCount(locked);
#else
    unsigned count;

    if (_NSGlobalRetainLock != nil)
        [_NSGlobalRetainLock lock];
    count = *refCount >> 3;
    if (count != 0x1fffffffU)
        *refCount = (*refCount & 7U) | ((count + 1) << 3);
    if (_NSGlobalRetainLock != nil)
        [_NSGlobalRetainLock unlock];
#endif
    if (NSKeepAllocationStatistics)
        NSRecordAllocationEvent(NSObjectInternalRefIncrementedEvent, self);
    return self;
}

- (oneway void)release {
    unsigned *refCount = &_reserved;
#if defined(__ppc__) || defined(__POWERPC__)
    BOOL shouldDeallocate = NO;
    BOOL locked;

    if (NSKeepAllocationStatistics)
        NSRecordAllocationEvent(NSObjectInternalRefDecrementedEvent, self);
    locked = NSDataLockRetainCount();
    if ((*refCount & 0x1fffffffU) != 0) {
        unsigned count = *refCount & 0x1fffffffU;

        if (count != 0x1fffffffU)
            *refCount = (*refCount & 0xe0000000U)
                | ((count - 1) & 0x1fffffffU);
    } else {
        shouldDeallocate = YES;
    }
    NSDataUnlockRetainCount(locked);
    if (shouldDeallocate)
        [self dealloc];
#else
    BOOL shouldDeallocate = NO;

    if (NSKeepAllocationStatistics)
        NSRecordAllocationEvent(NSObjectInternalRefDecrementedEvent, self);
    if (_NSGlobalRetainLock != nil)
        [_NSGlobalRetainLock lock];
    if ((*refCount & 0xfffffff8U) != 0) {
        unsigned count = *refCount >> 3;

        if (count != 0x1fffffffU)
            *refCount = (*refCount & 7U) | ((count - 1) << 3);
    } else {
        shouldDeallocate = YES;
    }
    if (_NSGlobalRetainLock != nil)
        [_NSGlobalRetainLock unlock];
    if (shouldDeallocate)
        [self dealloc];
#endif
}

- (unsigned)retainCount {
#if defined(__ppc__) || defined(__POWERPC__)
    return (_reserved & 0x1fffffffU) + 1;
#else
    return (_reserved >> 3) + 1;
#endif
}

- (void)dealloc {
    [_data release];
    [super dealloc];
}

@end

static void NSConcreteMutableDataSetupBytes(NSConcreteMutableData *data) {
    if (data->_capacity < NSPageSize()) {
        data->_bytes = NSZoneMalloc(NSZoneFromPointer(data), data->_capacity);
        NSDataUpdateFlags(&data->_flags, NSDataBytesAreVMFlag, 0);
    } else {
        data->_bytes = NSAllocateMemoryPages(data->_capacity);
        NSDataUpdateFlags(&data->_flags, 0, NSDataBytesAreVMFlag);
    }
}

static void NSConcreteMutableDataGrowBytes(NSConcreteMutableData *data) {
    unsigned oldCapacity = data->_capacity;
    unsigned copyLength = data->_length;
    unsigned newCapacity = copyLength +
        (copyLength < NSPageSize() ? copyLength >> 1 : copyLength >> 2);
    unsigned char *newBytes;

    if (newCapacity < oldCapacity)
        newCapacity = oldCapacity;
    newCapacity = (newCapacity + 3) & ~3U;
    data->_capacity = newCapacity;
    if (data->_bytes == NULL) {
        NSConcreteMutableDataSetupBytes(data);
    } else if (newCapacity < NSPageSize()) {
        data->_bytes = NSZoneRealloc(NSZoneFromPointer(data), data->_bytes,
                                     newCapacity);
        NSDataUpdateFlags(&data->_flags, NSDataBytesAreVMFlag, 0);
    } else {
        unsigned pageCapacity = NSRoundUpToMultipleOfPageSize(newCapacity);
        newBytes = NSAllocateMemoryPages(pageCapacity);
        if (copyLength != 0)
            memmove(newBytes, data->_bytes, copyLength);
        if ((NSDataGetFlags(&data->_flags) & NSDataBytesAreVMFlag) != 0)
            NSDeallocateMemoryPages(data->_bytes, copyLength);
        else
            NSZoneFree(NSZoneFromPointer(data), data->_bytes);
        data->_bytes = newBytes;
        NSDataUpdateFlags(&data->_flags, 0, NSDataBytesAreVMFlag);
    }
}

@implementation NSConcreteMutableData

- (id)init {
    return [self initWithCapacity:0];
}

- (id)initWithCapacity:(unsigned)capacity {
    unsigned roundedCapacity;

    if (capacity > 0x3FFFFFFF) {
        id proem = _NSMethodExceptionProem(self, _cmd);
        [NSException raise:NSInvalidArgumentException
                    format:@"%@: absurd %s: %d", proem, "capacity", capacity];
    }
    roundedCapacity = (capacity + (capacity >> 2) + 3) & ~3U;
    if (roundedCapacity >= NSPageSize())
        roundedCapacity = NSRoundUpToMultipleOfPageSize(roundedCapacity);
    _capacity = roundedCapacity;
    _length = 0;
    return self;
}

- (id)initWithBytes:(const void *)source length:(unsigned)length
               copy:(BOOL)copy freeWhenDone:(BOOL)freeWhenDone
        bytesAreVM:(BOOL)bytesAreVM {
    (void)copy;
    if (length > 0x3FFFFFFF) {
        id proem = _NSMethodExceptionProem(self, _cmd);
        [NSException raise:NSInvalidArgumentException
                    format:@"%@: absurd %s: %d", proem, "length", length];
    }
    self = [self initWithCapacity:length];
    if (_bytes == NULL)
        NSConcreteMutableDataSetupBytes(self);
    NSDataCopyBytes(_bytes, source, length);
    if (freeWhenDone) {
        if (bytesAreVM)
            NSDeallocateMemoryPages((void *)source,
                                    NSRoundUpToMultipleOfPageSize(length));
        else
            _NSGenericFree((void *)source);
    }
    _length = length;
    return self;
}

- (unsigned)length {
    return _length;
}

- (BOOL)_bytesAreVM {
    return (NSDataGetFlags(&_flags) & NSDataBytesAreVMFlag) != 0;
}

- (const void *)bytes {
    if (_bytes == NULL)
        NSConcreteMutableDataSetupBytes(self);
    return _bytes;
}

- (void *)mutableBytes {
    if (_bytes == NULL)
        NSConcreteMutableDataSetupBytes(self);
    return _bytes;
}

- (void)setLength:(unsigned)length {
    unsigned oldLength;

    if (length > 0x3FFFFFFF) {
        id proem = _NSMethodExceptionProem(self, _cmd);
        [NSException raise:NSInvalidArgumentException
                    format:@"%@: absurd %s: %d", proem, "length", length];
    }
    oldLength = _length;
    _length = length;
    if (_capacity < length || _bytes == NULL)
        NSConcreteMutableDataGrowBytes(self);
    if (length > oldLength)
        memset(_bytes + oldLength, 0, length - oldLength);
}

- (void)appendBytes:(const void *)bytes length:(unsigned)length {
    unsigned oldLength;

    if (length == 0)
        return;
    oldLength = _length;
    _length += length;
    if (_length > _capacity || _bytes == NULL)
        NSConcreteMutableDataGrowBytes(self);
    NSDataCopyBytes(_bytes + oldLength, bytes, length);
}

- (void)appendData:(NSData *)data {
    unsigned length = [data length];
    unsigned oldLength;

    if (length == 0)
        return;
    oldLength = _length;
    _length += length;
    if (_length > _capacity || _bytes == NULL)
        NSConcreteMutableDataGrowBytes(self);
    NSDataCopyBytes(_bytes + oldLength, [data bytes], length);
}

- (void)increaseLengthBy:(unsigned)extraLength {
    unsigned oldLength;

    if (extraLength == 0)
        return;
    if (extraLength > 0x3FFFFFFF) {
        id proem = _NSMethodExceptionProem(self, _cmd);
        [NSException raise:NSInvalidArgumentException
                    format:@"%@: absurd %s: %d", proem, "extra length", extraLength];
    }
    oldLength = _length;
    _length += extraLength;
    if (_length > _capacity || _bytes == NULL)
        NSConcreteMutableDataGrowBytes(self);
    memset(_bytes + oldLength, 0, extraLength);
}

- (void)replaceBytesInRange:(NSRange)range withBytes:(const void *)bytes {
    unsigned end;

    if (range.length == 0)
        return;
    if (_length < range.location) {
        id proem = _NSMethodExceptionProem(self, _cmd);
        [NSException raise:NSRangeException
                    format:@"%@: range location %u exceeds data length %u",
         proem, range.location, _length];
    }
    end = range.location + range.length;
    if (_length < end) {
        _length = end;
        if (_length > _capacity)
            NSConcreteMutableDataGrowBytes(self);
    }
    if (_bytes == NULL)
        NSConcreteMutableDataSetupBytes(self);
    NSDataCopyBytes(_bytes + range.location, bytes, range.length);
}

- (void)resetBytesInRange:(NSRange)range {
    unsigned end;

    if (range.length == 0)
        return;
    if (_length < range.location) {
        id proem = _NSMethodExceptionProem(self, _cmd);
        [NSException raise:NSRangeException
                    format:@"%@: range location %u exceeds data length %u",
         proem, range.location, _length];
    }
    end = range.location + range.length;
    if (_length < end) {
        _length = end;
        if (_length > _capacity)
            NSConcreteMutableDataGrowBytes(self);
    }
    if (_bytes == NULL)
        NSConcreteMutableDataSetupBytes(self);
    memset(_bytes + range.location, 0, range.length);
}

- (int)deserializeIntAtIndex:(unsigned)index {
    if (_length < index + 4) {
        id proem;
        NSString *rangeString;

#if defined(__ppc__) || defined(__POWERPC__)
        proem = _NSMethodExceptionProem(self, _cmd);
        rangeString = NSStringFromRange(NSMakeRange(index, 4));
#else
        rangeString = NSStringFromRange(NSMakeRange(index, 4));
        proem = _NSMethodExceptionProem(self, _cmd);
#endif
        [NSException raise:NSRangeException
                    format:@"%@: range %@ exceeds data length %u",
         proem, rangeString, _length];
    }
    return (int)NSDataReadInt32(_bytes + index);
}

- (void)deserializeInts:(int *)intBuffer count:(unsigned)count
                atIndex:(unsigned)index {
    unsigned length = count * 4;
    const unsigned char *bytes = _bytes + index;
    unsigned item;

    if (_length < length + index) {
        if (length != 0) {
            id proem;
            NSString *rangeString;

#if defined(__ppc__) || defined(__POWERPC__)
            proem = _NSMethodExceptionProem(self, _cmd);
            rangeString = NSStringFromRange(NSMakeRange(index, length));
#else
            rangeString = NSStringFromRange(NSMakeRange(index, length));
            proem = _NSMethodExceptionProem(self, _cmd);
#endif
            [NSException raise:NSRangeException
                        format:@"%@: range %@ exceeds data length %u",
             proem, rangeString, _length];
        } else {
            id proem = _NSMethodExceptionProem(self, _cmd);
            [NSException raise:NSRangeException
                        format:@"%@: location %u exceeds data length %u",
             proem, index, _length];
        }
    }
    for (item = 0; item < count; item++) {
        *intBuffer++ = (int)NSDataReadInt32(bytes);
        bytes += 4;
    }
}

- (int)deserializeIntAtCursor:(unsigned *)cursor {
    unsigned index = *cursor;
    const unsigned char *bytes = _bytes + index;

    if (_length < index + 4) {
        id proem;
        NSString *rangeString;

#if defined(__ppc__) || defined(__POWERPC__)
        proem = _NSMethodExceptionProem(self, _cmd);
        rangeString = NSStringFromRange(NSMakeRange(index, 4));
#else
        rangeString = NSStringFromRange(NSMakeRange(index, 4));
        proem = _NSMethodExceptionProem(self, _cmd);
#endif
        [NSException raise:NSRangeException
                    format:@"%@: range %@ exceeds data length %u",
         proem, rangeString, _length];
    }
    *cursor = index + 4;
    return (int)NSDataReadInt32(bytes);
}

- (void)serializeInt:(int)value {
    unsigned oldLength = _length;

    _length += 4;
    if (_length > _capacity || _bytes == NULL)
        NSConcreteMutableDataGrowBytes(self);
    NSDataWriteInt32(_bytes + oldLength, (unsigned)value);
}

- (void)serializeInt:(int)value atIndex:(unsigned)index {
    unsigned end = index + 4;
    unsigned oldLength = _length;

    if (_length < end) {
        _length = end;
        if (_length > _capacity || _bytes == NULL)
            NSConcreteMutableDataGrowBytes(self);
        if (oldLength < index)
            memset(_bytes + oldLength, 0, index - oldLength);
    }
    if (_bytes == NULL)
        NSConcreteMutableDataSetupBytes(self);
    NSDataWriteInt32(_bytes + index, (unsigned)value);
}

- (void)serializeInts:(int *)intBuffer count:(unsigned)count {
    unsigned length = count * 4;
    unsigned oldLength = _length;
    unsigned item;

    _length += length;
    if (_length > _capacity || _bytes == NULL)
        NSConcreteMutableDataGrowBytes(self);
    for (item = 0; item < count; item++)
        NSDataWriteInt32(_bytes + oldLength + item * 4,
                         (unsigned)intBuffer[item]);
}

- (void)serializeInts:(int *)intBuffer count:(unsigned)count
              atIndex:(unsigned)index {
    unsigned length = count * 4;
    unsigned end = index + length;
    unsigned oldLength = _length;
    unsigned item;

    if (_length < end) {
        _length = end;
        if (_length > _capacity || _bytes == NULL)
            NSConcreteMutableDataGrowBytes(self);
        if (oldLength < index)
            memset(_bytes + oldLength, 0, index - oldLength);
    }
    if (_bytes == NULL)
        NSConcreteMutableDataSetupBytes(self);
    for (item = 0; item < count; item++)
        NSDataWriteInt32(_bytes + index + item * 4,
                         (unsigned)intBuffer[item]);
}

- (void)serializeAlignedBytesLength:(unsigned)length {
    unsigned pageSize = NSPageSize();
    unsigned oldLength = _length;
    unsigned padding;

    if (length >= pageSize &&
        ((oldLength + 4) & (pageSize - 1)) != 0) {
        padding = pageSize - ((pageSize - 1) & (oldLength + 12));
        _length = oldLength + 12 + padding;
        if (_length > _capacity || _bytes == NULL)
            NSConcreteMutableDataGrowBytes(self);
        NSDataWriteInt32(_bytes + oldLength, 0x80000000U);
        NSDataWriteInt32(_bytes + oldLength + 4, length);
        NSDataWriteInt32(_bytes + oldLength + 8, padding);
        if (padding != 0)
            memset(_bytes + oldLength + 12, 0, padding);
    } else {
        _length += 4;
        if (_length > _capacity || _bytes == NULL)
            NSConcreteMutableDataGrowBytes(self);
        NSDataWriteInt32(_bytes + _length - 4, length);
    }
}

- (void)serializeAlignedBytes:(const void *)source length:(unsigned)length {
    unsigned oldLength = _length;
    unsigned alignedLength = (length + 3) & ~3U;
    unsigned trailingPadding = alignedLength - length;
    unsigned pageSize = NSPageSize();
    unsigned headerLength = 4;
    unsigned pagePadding = 0;
    unsigned payloadOffset;

    if (length >= pageSize &&
        ((oldLength + 4) & (pageSize - 1)) != 0) {
        pagePadding = pageSize - ((pageSize - 1) & (oldLength + 12));
        headerLength = 12 + pagePadding;
    }
    payloadOffset = oldLength + headerLength;
    _length = payloadOffset + length + trailingPadding;
    if (_length > _capacity || _bytes == NULL)
        NSConcreteMutableDataGrowBytes(self);
    if (pagePadding != 0) {
        NSDataWriteInt32(_bytes + oldLength, 0x80000000U);
        NSDataWriteInt32(_bytes + oldLength + 4, length);
        NSDataWriteInt32(_bytes + oldLength + 8, pagePadding);
        memset(_bytes + oldLength + 12, 0, pagePadding);
    } else {
        NSDataWriteInt32(_bytes + oldLength, length);
    }
    if (length != 0)
        NSDataCopyBytes(_bytes + payloadOffset, source, length);
    if (trailingPadding != 0)
        memset(_bytes + payloadOffset + length, 0, trailingPadding);
}

- (id)retain {
    unsigned *refCount = (unsigned *)&_flags;
    BOOL locked = NSDataLockRetainCount();
#if defined(__ppc__) || defined(__POWERPC__)
    unsigned value = *refCount;
    unsigned count = value & 0x1fffffffU;

    if (count != 0x1fffffffU)
        *refCount = (value & 0xe0000000U) | ((count + 1) & 0x1fffffffU);
#else
    unsigned count;

    count = *refCount >> 3;
    if (count != 0x1fffffffU)
        *refCount = (*refCount & 7U) | ((count + 1) << 3);
#endif
    NSDataUnlockRetainCount(locked);
    if (NSKeepAllocationStatistics)
        NSRecordAllocationEvent(NSObjectInternalRefIncrementedEvent, self);
    return self;
}

- (oneway void)release {
    unsigned *refCount = (unsigned *)&_flags;
    BOOL shouldDeallocate = NO;
    BOOL locked;

    if (NSKeepAllocationStatistics)
        NSRecordAllocationEvent(NSObjectInternalRefDecrementedEvent, self);
    locked = NSDataLockRetainCount();
#if defined(__ppc__) || defined(__POWERPC__)
    {
        unsigned value = *refCount;
        unsigned count = value & 0x1fffffffU;

        if (count != 0) {
            if (count != 0x1fffffffU)
                *refCount = (value & 0xe0000000U)
                    | ((count - 1) & 0x1fffffffU);
        } else {
            shouldDeallocate = YES;
        }
    }
#else
    if ((*refCount & 0xfffffff8U) != 0) {
        unsigned count = *refCount >> 3;

        if (count != 0x1fffffffU)
            *refCount = (*refCount & 7U) | ((count - 1) << 3);
    } else {
        shouldDeallocate = YES;
    }
#endif
    NSDataUnlockRetainCount(locked);
    if (shouldDeallocate)
        [self dealloc];
}

- (unsigned)retainCount {
#if defined(__ppc__) || defined(__POWERPC__)
    return (*(unsigned *)&_flags & 0x1fffffffU) + 1;
#else
    return (*(unsigned *)&_flags >> 3) + 1;
#endif
}

- (void)dealloc {
    if (_bytes != NULL) {
        if ((NSDataGetFlags(&_flags) & NSDataBytesAreVMFlag) != 0)
            NSDeallocateMemoryPages(_bytes, _capacity);
        else
            NSZoneFree(NSZoneFromPointer(self), _bytes);
    }
    [super dealloc];
}

@end

id
_NSNewImmutableData(const void *bytes, unsigned length, NSZone *zone)
{
    id data = NSAllocateObject([NSConcreteData class], 0, zone);

    return [data initWithBytes:bytes length:length copy:YES freeWhenDone:NO
                   bytesAreVM:NO];
}

id
_NSNewImmutableDataNoCopy(const void *bytes, unsigned length, NSZone *zone)
{
    id data = NSAllocateObject([NSConcreteData class], 0, zone);

    return [data initWithBytes:bytes length:length copy:NO freeWhenDone:YES
                   bytesAreVM:NO];
}

@implementation NSData

+ (id)allocWithZone:(NSZone *)zone {
    Class dataClass = self;

    if (self == [NSData class])
        dataClass = [NSConcreteData class];
    return NSAllocateObject(dataClass, 0, zone);
}

- (unsigned)length {
    NSRequestConcreteImplementation(self, _cmd, [NSData class]);
    return 0;
}

- (const void *)bytes {
    NSRequestConcreteImplementation(self, _cmd, [NSData class]);
    return nil;
}

- (NSString *)description {
    static const char hexDigits[] = "0123456789abcdef";
    unsigned length = [self length];
    NSMutableString *description = [[NSMutableString allocWithZone:NULL]
        initWithCapacity:2 * length + (length >> 2) + 16];
    const unsigned char *bytes = [self bytes];
    unsigned stringLength;
    unsigned index;

    stringLength = [description length];
    [description replaceCharactersInRange:NSMakeRange(stringLength, 0)
                                withString:@"<"];
    for (index = 0; length - index >= 4; index += 4) {
        char group[9];
        NSString *groupString;

        group[0] = hexDigits[bytes[index] >> 4];
        group[1] = hexDigits[bytes[index] & 0x0f];
        group[2] = hexDigits[bytes[index + 1] >> 4];
        group[3] = hexDigits[bytes[index + 1] & 0x0f];
        group[4] = hexDigits[bytes[index + 2] >> 4];
        group[5] = hexDigits[bytes[index + 2] & 0x0f];
        group[6] = hexDigits[bytes[index + 3] >> 4];
        group[7] = hexDigits[bytes[index + 3] & 0x0f];
        group[8] = ' ';
        groupString = [[NSString allocWithZone:NULL]
            initWithCString:group length:sizeof(group)];
        stringLength = [description length];
        [description replaceCharactersInRange:NSMakeRange(stringLength, 0)
                                    withString:groupString];
        [groupString release];
    }
    for (; index < length; index++) {
        char digits[2];
        NSString *digitString;

        digits[0] = hexDigits[bytes[index] >> 4];
        digits[1] = hexDigits[bytes[index] & 0x0f];
        digitString = [[NSString allocWithZone:NULL]
            initWithCString:digits length:sizeof(digits)];
        stringLength = [description length];
        [description replaceCharactersInRange:NSMakeRange(stringLength, 0)
                                    withString:digitString];
        [digitString release];
    }
    stringLength = [description length];
    [description replaceCharactersInRange:NSMakeRange(stringLength, 0)
                                withString:@">"];
    return [description autorelease];
}

- (void)getBytes:(void *)buffer {
    const void *source;
    unsigned length;

#if defined(__ppc__) || defined(__POWERPC__)
    length = [self length];
    source = [self bytes];
#else
    source = [self bytes];
    length = [self length];
#endif

    NSDataCopyBytes(buffer, source, length);
}

- (void)getBytes:(void *)buffer length:(unsigned)length {
    unsigned dataLength = [self length];

    if (length > dataLength)
        length = dataLength;
    NSDataCopyBytes(buffer, [self bytes], length);
}

- (void)getBytes:(void *)buffer range:(NSRange)range {
    unsigned dataLength;
    unsigned length;

    if (range.length == 0)
        return;
    dataLength = [self length];
    if (dataLength <= range.location) {
        id proem = _NSMethodExceptionProem(self, _cmd);
        [NSException raise:NSRangeException
                    format:@"%@: range location %u exceeds data length %u",
         proem, range.location, dataLength];
    }
    length = range.length;
    if (dataLength < range.location + length)
        length = dataLength - range.location;
    NSDataCopyBytes(buffer,
                    (const unsigned char *)[self bytes] + range.location,
                    length);
}

- (BOOL)isEqualToData:(NSData *)other {
    unsigned length = [self length];
    const void *leftBytes;
    const void *rightBytes;

    if (other == nil || length != [other length])
        return NO;
#if defined(__ppc__) || defined(__POWERPC__)
    leftBytes = [self bytes];
    rightBytes = [other bytes];
#else
    rightBytes = [other bytes];
    leftBytes = [self bytes];
#endif
    return memcmp(leftBytes, rightBytes, length) == 0;
}

- (Class)classForCoder {
    return [NSData class];
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeDataObject:self];
}

- (id)initWithCoder:(NSCoder *)coder {
    [self release];
    return [[coder decodeDataObject] retain];
}

- (id)replacementObjectForPortCoder:(id)coder {
    (void)coder;
    return self;
}

- (unsigned)hash {
    const unsigned char *bytes = [self bytes];
    unsigned length = [self length];
    unsigned hash = 0;

    if (length > 16)
        length = 16;
    while (length > 0) {
        unsigned highBits;

        hash = bytes[--length] + 16 * hash;
        highBits = hash & 0xf0000000U;
        if (highBits != 0)
            hash ^= highBits >> 24;
        hash &= ~highBits;
    }
    return hash;
}

- (BOOL)isEqualToBitVector:(NSData *)other {
    const unsigned char *left;
    const unsigned char *right;
    unsigned leftLength;
    unsigned rightLength;
    unsigned commonLength;

#if defined(__ppc__) || defined(__POWERPC__)
    leftLength = [self length];
    left = [self bytes];
    rightLength = [other length];
    right = [other bytes];
#else
    left = [self bytes];
    leftLength = [self length];
    right = [other bytes];
    rightLength = [other length];
#endif
    commonLength = leftLength < rightLength ? leftLength : rightLength;

    if (commonLength != 0 && memcmp(left, right, commonLength) != 0)
        return NO;
    if (leftLength > commonLength)
        return NSDataAllZeroBytes(left + commonLength,
                                  leftLength - commonLength);
    if (rightLength > commonLength)
        return NSDataAllZeroBytes(right + commonLength,
                                  rightLength - commonLength);
    return YES;
}

- (unsigned)numberOfSetBits {
    static const unsigned char nibbleBits[16] = {
        0, 1, 1, 2, 1, 2, 2, 3, 1, 2, 2, 3, 2, 3, 3, 4
    };
    const unsigned char *bytes = [self bytes];
    unsigned length = [self length];
    unsigned count = 0;

    while (length-- != 0) {
        unsigned byte = *bytes++;
        count += nibbleBits[byte >> 4] + nibbleBits[byte & 0x0f];
    }
    return count;
}

- (BOOL)intersectsBitVector:(NSData *)other {
    const unsigned char *left = [self bytes];
    unsigned leftLength = [self length];
    const unsigned char *right = [other bytes];
    unsigned rightLength = [other length];
    unsigned length;

    length = leftLength < rightLength ? leftLength : rightLength;
    return NSDataFirstByteAfterIntersecting(left, right, length) != 0;
}

- (BOOL)_intersectsBitVectorMaybeCompressed:(NSData *)other {
    unsigned leftLength = [self length];
    const unsigned char *left = [self bytes];
    unsigned rightLength = [other length];
    const unsigned char *right = [other bytes];
    unsigned payloadLength;
    unsigned runCount;
    unsigned sourceOffset = 0;
    unsigned decodedOffset = 0;
    unsigned run;

    if (rightLength == 0)
        return NO;
    if (!NSDataIsCompressedBitVector(right, rightLength))
        return NSDataFirstByteAfterIntersecting(
            left, right, leftLength < rightLength ? leftLength : rightLength) != 0;

    runCount = NSDataCompressedBitVectorRunCount(right, rightLength);
    payloadLength = NSDataCompressedBitVectorPayloadLength(rightLength, runCount);
    for (run = 0; run <= runCount; run++) {
        unsigned encodedOffset;
        unsigned zeroLength;
        unsigned segmentLength;
        unsigned compareLength;

        if (run == runCount) {
            encodedOffset = payloadLength;
            zeroLength = 0;
        } else {
            NSDataCompressedBitVectorRun(right, payloadLength, run,
                                         &encodedOffset, &zeroLength);
        }
        segmentLength = encodedOffset - sourceOffset;
        if (decodedOffset < leftLength) {
            compareLength = leftLength - decodedOffset;
            if (compareLength > segmentLength)
                compareLength = segmentLength;
            if (NSDataFirstByteAfterIntersecting(left + decodedOffset,
                    right + sourceOffset, compareLength) != 0)
                return YES;
        }
        sourceOffset = encodedOffset;
        decodedOffset += segmentLength + zeroLength;
        if (decodedOffset >= leftLength)
            return NO;
    }
    return NO;
}

- (NSData *)intersectionWithBitVector:(NSData *)other {
    const unsigned char *left = [self bytes];
    unsigned length = [self length];
    const unsigned char *right = [other bytes];
    unsigned otherLength = [other length];
    unsigned commonLength = length < otherLength ? length : otherLength;
    unsigned resultLength = NSDataFirstByteAfterIntersecting(
        left, right, commonLength);
    unsigned char *result;
    unsigned index;

    if (resultLength == 0)
        return [NSData data];
    result = NSZoneMalloc(NULL, resultLength);
    for (index = 0; index < resultLength; index++)
        result[index] = left[index] & right[index];
    return [NSData dataWithBytesNoCopy:result length:resultLength];
}

- (NSData *)unionWithBitVector:(NSData *)other {
    const unsigned char *left = [self bytes];
    unsigned leftLength = [self length];
    const unsigned char *right = [other bytes];
    unsigned rightLength = [other length];
    unsigned commonLength = leftLength < rightLength ? leftLength : rightLength;
    unsigned resultLength = leftLength < rightLength ? rightLength : leftLength;
    unsigned char *result = NSZoneMalloc(NULL, resultLength);
    unsigned index;

    for (index = 0; index < commonLength; index++)
        result[index] = left[index] & right[index];
    if (resultLength > commonLength) {
        const unsigned char *tail = leftLength > rightLength ? left : right;

        memmove(result + commonLength, tail + commonLength,
                resultLength - commonLength);
    }
    return [NSData dataWithBytesNoCopy:result length:resultLength];
}

- (id)_compressIfNeeded {
    unsigned length = [self length];
    const unsigned char *bytes = [self bytes];
    unsigned trimmedLength = length;
    unsigned packedRuns[256];
    unsigned runCount = 0;
    unsigned removedZeros = 0;
    unsigned index = 0;
    BOOL trimmedTrailingZeros = NO;

    if (trimmedLength != 0 && bytes[trimmedLength - 1] == 0) {
        trimmedTrailingZeros = YES;
        while (trimmedLength != 0 && bytes[trimmedLength - 1] == 0)
            trimmedLength--;
    }
    if (trimmedLength <= 5 && !trimmedTrailingZeros)
        return self;
    if (trimmedLength > 6) {
        while (index < trimmedLength - 6) {
            unsigned zeroLength = 1;

            if (bytes[index] != 0) {
                index++;
                continue;
            }
            if (index + 1 < trimmedLength && bytes[index + 1] == 0) {
                while (index + zeroLength < trimmedLength &&
                       zeroLength <= 0xfe && bytes[index + zeroLength] == 0)
                    zeroLength++;
            }
            if (zeroLength > 5) {
                packedRuns[runCount++] =
                    (zeroLength << 16) | ((index - removedZeros) & 0xffffU);
                removedZeros += zeroLength;
                if (runCount > 0xfe || index + zeroLength > 0xfffe)
                    break;
            }
            index += zeroLength;
        }
    }
    if (runCount == 0) {
        if (!trimmedTrailingZeros)
            return self;
        return [NSData dataWithBytes:bytes length:trimmedLength];
    } else {
        unsigned char *compressed = NSZoneMalloc(NULL, trimmedLength);
        unsigned outputOffset = 0;
        unsigned sourceOffset = 0;
        unsigned removed = 0;
        unsigned run;

        packedRuns[runCount] =
            (trimmedLength - removedZeros) & 0xffffU;
        for (run = 0; run <= runCount; run++) {
            unsigned encodedOffset = packedRuns[run] & 0xffffU;
            unsigned zeroLength = (packedRuns[run] >> 16) & 0xffU;
            unsigned segmentEnd = encodedOffset + removed;
            unsigned segmentLength = segmentEnd - sourceOffset;

            if (segmentLength != 0) {
                memmove(compressed + outputOffset, bytes + sourceOffset,
                        segmentLength);
                outputOffset += segmentLength;
            }
            sourceOffset = segmentEnd + zeroLength;
            removed += zeroLength;
        }
        for (run = 0; run < runCount; run++) {
            unsigned packed = packedRuns[run];

            compressed[outputOffset++] = (unsigned char)packed;
            compressed[outputOffset++] = (unsigned char)(packed >> 8);
            compressed[outputOffset++] = (unsigned char)(packed >> 16);
        }
        compressed[outputOffset++] = (unsigned char)runCount;
        compressed[outputOffset++] = 0;
        return [NSData dataWithBytesNoCopy:compressed length:outputOffset];
    }
}

- (id)_decompressIfNeeded {
    unsigned length = [self length];
    const unsigned char *bytes = [self bytes];
    unsigned runCount;
    unsigned payloadLength;
    NSMutableData *result;
    unsigned sourceOffset = 0;
    unsigned run;

    if (!NSDataIsCompressedBitVector(bytes, length))
        return self;
    runCount = NSDataCompressedBitVectorRunCount(bytes, length);
    payloadLength = NSDataCompressedBitVectorPayloadLength(length, runCount);
    result = [NSMutableData dataWithCapacity:10 * length];
    for (run = 0; run <= runCount; run++) {
        unsigned encodedOffset;
        unsigned zeroLength;
        unsigned segmentLength;

        if (run == runCount) {
            encodedOffset = payloadLength;
            zeroLength = 0;
        } else {
            NSDataCompressedBitVectorRun(bytes, payloadLength, run,
                                         &encodedOffset, &zeroLength);
        }
        segmentLength = encodedOffset - sourceOffset;
        if (segmentLength != 0)
            [result appendBytes:bytes + sourceOffset length:segmentLength];
        if (zeroLength != 0)
            [result increaseLengthBy:zeroLength];
        sourceOffset = encodedOffset;
    }
    return result;
}

- (BOOL)isEqual:(id)object {
    if (object == self)
        return YES;
    if (object == nil || ![object isKindOfClass:[NSData class]])
        return NO;
    return [self isEqualToData:object];
}

- (id)initWithBytes:(const void *)bytes length:(unsigned)length
               copy:(BOOL)copy freeWhenDone:(BOOL)freeWhenDone
        bytesAreVM:(BOOL)bytesAreVM {
    NSRequestConcreteImplementation(self, _cmd, [NSData class]);
    return self;
}

- (BOOL)_bytesAreVM {
    return NO;
}

- (BOOL)writeToFile:(NSString *)path atomically:(BOOL)useAuxiliaryFile {
    unsigned length = [self length];
    const void *bytes = length == 0 ? "" : [self bytes];

    return _NSWriteBytesToFile(path, bytes, length, useAuxiliaryFile);
}

- (BOOL)writeToURL:(NSURL *)url atomically:(BOOL)atomically {
#if defined(__ppc__) || defined(__POWERPC__)
    if ([url isFileURL])
        return [self writeToFile:[url path] atomically:atomically];
    return [[url URLHandleUsingCache:NO] writeData:self];
#else
    if (![url isFileURL])
        return NO;
    return [self writeToFile:[url path] atomically:atomically];
#endif
}

+ (id)data {
    return [[[self allocWithZone:NULL]
        initWithBytes:NULL length:0 copy:NO freeWhenDone:NO bytesAreVM:NO]
        autorelease];
}

+ (id)dataWithBytes:(const void *)bytes length:(unsigned)length {
    return [[[self allocWithZone:NULL]
        initWithBytes:bytes length:length copy:YES freeWhenDone:NO
        bytesAreVM:NO] autorelease];
}

+ (id)dataWithBytesNoCopy:(void *)bytes length:(unsigned)length {
    return [[[self allocWithZone:NULL]
        initWithBytes:bytes length:length copy:NO freeWhenDone:YES
        bytesAreVM:NO] autorelease];
}

+ (id)dataWithContentsOfFile:(NSString *)path {
    return [[[self allocWithZone:NULL] initWithContentsOfFile:path] autorelease];
}

+ (id)dataWithContentsOfURL:(NSURL *)url {
    return [[[self allocWithZone:NULL] initWithContentsOfURL:url] autorelease];
}

+ (id)dataWithContentsOfMappedFile:(NSString *)path {
    return [[[self allocWithZone:NULL] initWithContentsOfMappedFile:path] autorelease];
}

- (id)initWithBytes:(const void *)bytes length:(unsigned)length {
    return [self initWithBytes:bytes length:length copy:YES freeWhenDone:NO bytesAreVM:NO];
}

- (id)initWithBytesNoCopy:(void *)bytes length:(unsigned)length {
    return [self initWithBytes:bytes length:length copy:NO freeWhenDone:YES bytesAreVM:NO];
}

- (id)initWithContentsOfFile:(NSString *)path {
    char filePath[1028];
    void *bytes;
    unsigned length;

    [path getFileSystemRepresentation:filePath maxLength:1024];
#if defined(__ppc__) || defined(__POWERPC__)
    if (!_NSReadBytesFromFile(filePath, &bytes, &length, [self zone], 0)) {
#else
    if (!_NSReadBytesFromFile(filePath, &bytes, &length, [self zone])) {
#endif
        [super dealloc];
        return nil;
    }
    return [self initWithBytes:bytes length:length
                          copy:NO freeWhenDone:YES bytesAreVM:NO];
}

- (id)initWithContentsOfURL:(NSURL *)url {
    if ([url isFileURL])
        return [self initWithContentsOfFile:[url path]];
#if defined(__ppc__) || defined(__POWERPC__)
    {
        NSData *data = [url resourceDataUsingCache:NO];
        if (data != nil)
            return [self initWithData:data];
    }
#endif
    return nil;
}

- (id)initWithContentsOfMappedFile:(NSString *)path {
#if defined(__ppc__) || defined(__POWERPC__)
    return [self initWithContentsOfFile:path];
#else
    vm_offset_t address;
    vm_size_t length;

    if (!_NSMapBytesFromFile(path, &address, &length)) {
        [super dealloc];
        return nil;
    }
    return [self initWithBytes:(const void *)address length:(unsigned)length
                          copy:NO freeWhenDone:YES bytesAreVM:YES];
#endif
}

- (id)initWithData:(NSData *)data {
    unsigned length = [data length];
    const void *bytes;
    BOOL bytesAreVM;

    if (length == 0)
        return [self initWithBytes:NULL length:0
                              copy:NO freeWhenDone:NO bytesAreVM:NO];
#if defined(__ppc__) || defined(__POWERPC__)
    bytes = [data bytes];
    bytesAreVM = [data _bytesAreVM];
#else
    bytesAreVM = [data _bytesAreVM];
    bytes = [data bytes];
#endif
    return [self initWithBytes:bytes length:length
                          copy:YES freeWhenDone:NO bytesAreVM:bytesAreVM];
}

- (id)copyWithZone:(NSZone *)zone {
    NSData *copy = NSAllocateObject([NSConcreteData class], 0, zone);

    copy = [copy initWithData:self];
    return copy;
}

- (id)mutableCopyWithZone:(NSZone *)zone {
    NSMutableData *copy = NSAllocateObject([NSConcreteMutableData class], 0, zone);
    return [copy initWithData:self];
}

- (NSData *)subdataWithRange:(NSRange)range {
    unsigned length = [self length];
    NSZone *zone = NSZoneFromPointer(self);

    if (range.length == 0) {
        NSData *empty = _NSNewImmutableData(NULL, 0, zone);
        return [empty autorelease];
    }
    if (length < range.location + range.length) {
        id proem;
        NSString *rangeString;

#if defined(__ppc__) || defined(__POWERPC__)
        proem = _NSMethodExceptionProem(self, _cmd);
        rangeString = NSStringFromRange(range);
#else
        rangeString = NSStringFromRange(range);
        proem = _NSMethodExceptionProem(self, _cmd);
#endif
        [NSException raise:NSRangeException
                    format:@"%@: range %@ exceeds data length %u",
         proem, rangeString, length];
    }
    if (range.location == 0 && range.length == length)
        return [[self copyWithZone:zone] autorelease];
    if (range.length > 0x3F &&
        (self->isa == [NSConcreteData class] || range.length > 0x7FFF)) {
        NSSubrangeData *subrange = [[NSSubrangeData allocWithZone:zone]
                                    initWithData:self range:range];
        return [subrange autorelease];
    }
    NSData *copy = [[NSData allocWithZone:zone]
                    initWithBytes:(const unsigned char *)[self bytes] + range.location
                    length:range.length];
    return [copy autorelease];
}

+ (id)dataWithData:(NSData *)data {
    id result;
    unsigned length;
    const void *bytes;

#if defined(__ppc__) || defined(__POWERPC__)
    result = [self allocWithZone:NULL];
    length = [data length];
    bytes = [data bytes];
#else
    length = [data length];
    bytes = [data bytes];
    result = [self allocWithZone:NULL];
#endif
    result = [result initWithBytes:bytes length:length copy:YES
                     freeWhenDone:NO bytesAreVM:NO];
    return [result autorelease];
}

@end

@implementation NSMutableData

+ (id)allocWithZone:(NSZone *)zone {
    Class dataClass = self;

    if (self == [NSMutableData class])
        dataClass = [NSConcreteMutableData class];
    return NSAllocateObject(dataClass, 0, zone);
}

- (Class)classForCoder {
    return [NSMutableData class];
}

- (void)serializeAlignedBytes:(const void *)bytes length:(unsigned)length {
    unsigned alignedLength = (length + 3) & ~3U;
    unsigned padding = alignedLength - length;

    [self serializeAlignedBytesLength:length];
    [self appendBytes:bytes length:length];
    if (padding != 0)
        [self increaseLengthBy:padding];
}

- (void)unionBitVector:(NSData *)bitVector {
    unsigned length = [self length];
    const unsigned char *source = [bitVector bytes];
    unsigned bitVectorLength = [bitVector length];
    unsigned char *destination;
    unsigned index;

    if (bitVectorLength > length) {
        [self setLength:bitVectorLength];
        length = bitVectorLength;
    }
    destination = [self mutableBytes];
    for (index = 0; index < bitVectorLength; index++)
        destination[index] |= source[index];
}

- (void)intersectBitVector:(NSData *)bitVector {
    unsigned length = [self length];
    const unsigned char *source = [bitVector bytes];
    unsigned bitVectorLength = [bitVector length];
    unsigned char *destination;
    unsigned index;

    if (bitVectorLength < length) {
        [self setLength:bitVectorLength];
        length = bitVectorLength;
    }
    destination = [self mutableBytes];
    for (index = 0; index < length; index++)
        destination[index] &= source[index];
}

- (void)_unionBitVectorMaybeCompressed:(NSData *)bitVector {
    unsigned sourceLength = [bitVector length];
    const unsigned char *source = [bitVector bytes];
    unsigned runCount;
    unsigned payloadLength;
    unsigned sourceOffset = 0;
    unsigned destinationOffset = 0;
    unsigned currentLength;
    unsigned char *destination;
    unsigned run;

    if (sourceLength == 0)
        return;
    if (!NSDataIsCompressedBitVector(source, sourceLength)) {
        [self unionBitVector:bitVector];
        return;
    }
    runCount = NSDataCompressedBitVectorRunCount(source, sourceLength);
    payloadLength = NSDataCompressedBitVectorPayloadLength(sourceLength,
                                                            runCount);
    currentLength = [self length];
    destination = [self mutableBytes];
    for (run = 0; run <= runCount; run++) {
        unsigned encodedOffset;
        unsigned zeroLength;
        unsigned segmentLength;
        unsigned end;
        unsigned index;

        if (run == runCount) {
            encodedOffset = payloadLength;
            zeroLength = 0;
        } else {
            NSDataCompressedBitVectorRun(source, payloadLength, run,
                                         &encodedOffset, &zeroLength);
        }
        segmentLength = encodedOffset - sourceOffset;
        end = destinationOffset + segmentLength + zeroLength;
        if (currentLength < end) {
            currentLength = end;
            [self setLength:end];
            destination = [self mutableBytes];
        }
        for (index = 0; index < segmentLength; index++)
            destination[destinationOffset + index] |=
                source[sourceOffset + index];
        sourceOffset = encodedOffset;
        destinationOffset = end;
    }
}

- (void *)mutableBytes {
    NSRequestConcreteImplementation(self, _cmd, [NSMutableData class]);
    return nil;
}

- (void)setLength:(unsigned)length {
    NSRequestConcreteImplementation(self, _cmd, [NSMutableData class]);
}

- (void)appendBytes:(const void *)bytes length:(unsigned)length {
    unsigned oldLength;
    unsigned char *destination;

    if (length == 0)
        return;
    oldLength = [self length];
    [self setLength:oldLength + length];
    destination = [self mutableBytes];
    NSDataCopyBytes(destination + oldLength, bytes, length);
}

- (void)appendData:(NSData *)other {
    unsigned length = [other length];
    unsigned oldLength;
    unsigned char *destination;

    if (length == 0)
        return;
    oldLength = [self length];
    [self setLength:oldLength + length];
    destination = [self mutableBytes];
    NSDataCopyBytes(destination + oldLength, [other bytes], length);
}

- (void)increaseLengthBy:(unsigned)extraLength {
    unsigned length;

    if (extraLength > 0x3FFFFFFF) {
        id proem = _NSMethodExceptionProem(self, _cmd);
        [NSException raise:NSInvalidArgumentException
                    format:@"%@: absurd %s: %d", proem, "extra length", extraLength];
    }
    length = [self length];
    [self setLength:length + extraLength];
}

- (void)replaceBytesInRange:(NSRange)range withBytes:(const void *)bytes {
    unsigned oldLength;
    unsigned char *destination;

    if (range.length == 0)
        return;
    oldLength = [self length];
    if (oldLength < range.location) {
        id proem = _NSMethodExceptionProem(self, _cmd);
        [NSException raise:NSRangeException
                    format:@"%@: range location %u exceeds data length %u",
         proem, range.location, oldLength];
    }
    if (oldLength < range.location + range.length)
        [self setLength:range.location + range.length];
    destination = [self mutableBytes];
    NSDataCopyBytes(destination + range.location, bytes, range.length);
}

- (void)resetBytesInRange:(NSRange)range {
    unsigned oldLength;
    unsigned char *destination;

    if (range.length == 0)
        return;
    oldLength = [self length];
    if (oldLength < range.location) {
        id proem = _NSMethodExceptionProem(self, _cmd);
        [NSException raise:NSRangeException
                    format:@"%@: range location %u exceeds data length %u",
         proem, range.location, oldLength];
    }
    if (oldLength < range.location + range.length)
        [self setLength:range.location + range.length];
    destination = [self mutableBytes];
    memset(destination + range.location, 0, range.length);
}

- (void)setData:(NSData *)data {
    unsigned length = [data length];
    [self replaceBytesInRange:NSMakeRange(0, length) withBytes:[data bytes]];
    [self setLength:length];
}

+ (id)dataWithCapacity:(unsigned)aNumItems {
    return [[[self allocWithZone:NULL] initWithCapacity:aNumItems] autorelease];
}

+ (id)dataWithLength:(unsigned)length {
    return [[[self allocWithZone:NULL] initWithLength:length] autorelease];
}

- (id)initWithCapacity:(unsigned)capacity {
    (void)capacity;
    NSRequestConcreteImplementation(self, _cmd, [NSMutableData class]);
    return nil;
}

- (id)initWithLength:(unsigned)length {
    id data = [self initWithCapacity:length];
    [data setLength:length];
    return data;
}

@end
