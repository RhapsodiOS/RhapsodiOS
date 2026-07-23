/*
	NSPasteboard.h
	Application Kit
	Copyright (c) 1994-1997, Apple Computer, Inc.
	All rights reserved.
*/

#import <Foundation/NSObject.h>
#import <AppKit/AppKitDefines.h>
#import <Foundation/NSURL.h>

@class NSString;
@class NSMutableArray;
@class NSArray;
@class NSData;
@class NSFileWrapper;

/* standard Pasteboard types */

APPKIT_EXTERN NSString *NSStringPboardType;
APPKIT_EXTERN NSString *NSFilenamesPboardType;
APPKIT_EXTERN NSString *NSPostScriptPboardType;
APPKIT_EXTERN NSString *NSTIFFPboardType;
APPKIT_EXTERN NSString *NSRTFPboardType;
APPKIT_EXTERN NSString *NSTabularTextPboardType;
APPKIT_EXTERN NSString *NSFontPboardType;
APPKIT_EXTERN NSString *NSRulerPboardType;
APPKIT_EXTERN NSString *NSFileContentsPboardType;
APPKIT_EXTERN NSString *NSColorPboardType;
APPKIT_EXTERN NSString *NSRTFDPboardType;
APPKIT_EXTERN NSString *NSPICTPboardType;
APPKIT_EXTERN NSString *NSURLPboardType;

/* standard Pasteboard names */

APPKIT_EXTERN NSString *NSGeneralPboard;
APPKIT_EXTERN NSString *NSFontPboard;
APPKIT_EXTERN NSString *NSRulerPboard;
APPKIT_EXTERN NSString *NSFindPboard;
APPKIT_EXTERN NSString *NSDragPboard;


APPKIT_EXTERN NSString *NSCreateFilenamePboardType(NSString *fileType);
APPKIT_EXTERN NSString *NSCreateFileContentsPboardType(NSString *fileType);
APPKIT_EXTERN NSString *NSGetFileType(NSString *pboardType);
APPKIT_EXTERN NSArray *NSGetFileTypes(NSArray *pboardTypes);

@interface NSPasteboard : NSObject
{
    /*All instance variables are private*/
    id                  _owner;
    int                 _realChangeCount;
    int                 _ourChangeCount;
    id                  _pboard;
    NSMutableArray	*_owners;
    NSArray	        *_types;
    NSMutableArray	*_typesProvided;
    NSString		*_name;
    NSString		*_host;
    int			_serverVersion;
    int			_blockedState;
    NSData		*_asynchData;
}

+ (NSPasteboard *)generalPasteboard;
+ (NSPasteboard *)pasteboardWithName:(NSString *)name;
+ (NSPasteboard *)pasteboardWithUniqueName;

+ (NSArray *)typesFilterableTo:(NSString *)type;

+ (NSPasteboard *)pasteboardByFilteringFile:(NSString *)filename;
+ (NSPasteboard *)pasteboardByFilteringData:(NSData *)data ofType:(NSString *)type;
+ (NSPasteboard *)pasteboardByFilteringTypesInPasteboard:(NSPasteboard *)pboard;

- (NSString *)name;

- (void)releaseGlobally;

- (int)declareTypes:(NSArray *)newTypes owner:(id)newOwner;
- (int)addTypes:(NSArray *)newTypes owner:(id)newOwner;
- (int)changeCount;

- (NSArray *)types;
- (NSString *)availableTypeFromArray:(NSArray *)types;

- (BOOL)setData:(NSData *)data forType:(NSString *)dataType;
- (NSData *)dataForType:(NSString *)dataType;

- (BOOL)setPropertyList:(id)plist forType:(NSString *)dataType;
- (id)propertyListForType:(NSString *)dataType;

- (BOOL)setString:(NSString *)string forType:(NSString *)dataType;
- (NSString *)stringForType:(NSString *)dataType;

@end

@interface NSPasteboard(NSFileContents)
- (BOOL)writeFileContents:(NSString *)filename;
- (NSString *)readFileContentsType:(NSString *)type toFile:(NSString *)filename;

- (BOOL)writeFileWrapper:(NSFileWrapper *)wrapper;
- (NSFileWrapper *)readFileWrapper;

@end

@interface NSURL(NSPasteboardSupport)
+ (NSURL *)URLFromPasteboard:(NSPasteboard *)pasteBoard;
- (void)writeToPasteboard:(NSPasteboard *)pasteBoard;
@end

@interface NSObject(NSPasteboardOwner)
- (void)pasteboard:(NSPasteboard *)sender provideDataForType:(NSString *)type;
- (void)pasteboardChangedOwner:(NSPasteboard *)sender;
@end

