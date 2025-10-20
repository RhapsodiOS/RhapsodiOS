/*	NSArchiver.h
	Archiving objects
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSCoder.h>
#import <Foundation/NSHashTable.h>
#import <Foundation/NSMapTable.h>

@class NSString, NSData, NSMutableData, NSMutableDictionary, NSMutableArray;

/************		Archiving: Writing	****************/

@interface NSArchiver : NSCoder {
@private
    NSMutableData	*mdata;
    NSMapTable		*pointerTable;
    void		*stringTable;
    NSHashTable		*ids;
    NSMutableDictionary	*map;
    NSMapTable		*replacementTable;
    void		*reserved;
}

- (id)initForWritingWithMutableData:(NSMutableData *)mdata;
    
- (NSMutableData *)archiverData;

- (void)encodeRootObject:(id)rootObject;
- (void)encodeConditionalObject:(id)object;

+ (NSData *)archivedDataWithRootObject:(id)rootObject;

+ (BOOL)archiveRootObject:(id)rootObject toFile:(NSString *)path;

- (void)encodeClassName:(NSString *)trueName intoClassName:(NSString *)inArchiveName;
- (NSString *)classNameEncodedForTrueClassName:(NSString *)trueName;

- (void)replaceObject:(id)object withObject:(id)newObject;

@end

/************		Archiving: Reading		****************/

@interface NSUnarchiver : NSCoder {
@private
    id			data;
    unsigned		cursor;
    NSZone		*objectZone;
    unsigned		systemVersion;
    signed char		streamerVersion;
    NSMapTable		*pointerTable;
    NSMapTable		*stringTable;
    NSMapTable		*classVersions;
    int			lastLabel;
    NSMutableDictionary	*map;
    void		*allUnarchivedObjects;
    void		*reserved;
}

- (id)initForReadingWithData:(NSData *)data;

- (void)setObjectZone:(NSZone *)zone;
- (NSZone *)objectZone;

- (BOOL)isAtEnd;

- (unsigned)systemVersion;

+ (id)unarchiveObjectWithData:(NSData *)data;
+ (id)unarchiveObjectWithFile:(NSString *)path;

+ (void)decodeClassName:(NSString *)inArchiveName asClassName:(NSString *)trueName;

- (void)decodeClassName:(NSString *)inArchiveName asClassName:(NSString *)trueName;

+ (NSString *)classNameDecodedForArchiveClassName:(NSString *)inArchiveName;
- (NSString *)classNameDecodedForArchiveClassName:(NSString *)inArchiveName;

- (void)replaceObject:(id)object withObject:(id)newObject;

@end

/************		Exceptions		****************/

FOUNDATION_EXPORT NSString * const NSInconsistentArchiveException;

/************		Object call back		****************/

@interface NSObject (NSArchiverCallback)

- (Class)classForArchiver;
- (id)replacementObjectForArchiver:(NSArchiver *)archiver;

@end
