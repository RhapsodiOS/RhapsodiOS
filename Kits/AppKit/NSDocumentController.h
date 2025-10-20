/*
 	NSDocumentController.h
        Application Kit
        Copyright (c) 1997, Apple Computer, Inc.
        All rights reserved.
*/

#import <Foundation/Foundation.h>
#import <AppKit/NSNibDeclarations.h>

@class NSMenuItem;
@class NSOpenPanel;
@class NSWindow;
@class NSDocument;
@class NSURL;

//================================================================================
//	interface NSDocumentController
//================================================================================

@interface NSDocumentController : NSObject {
    @private
    NSMutableArray 	*_documents;
    struct __controllerFlags {
        unsigned int shouldCreateUI:1;
        unsigned int RESERVED:31;
    } _controllerFlags;
    NSArray		*_types;		// from info.plist with key NSTypes
    void 		*_reserved1;
    void 		*_reserved2;
}

+ (id)sharedDocumentController;

// document creation (doesn't create the windowControllers)

- (id)makeUntitledDocumentOfType:(NSString *)type;
- (id)makeDocumentWithContentsOfFile:(NSString *)fileName ofType:(NSString *)type;
- (id)makeDocumentWithContentsOfURL:(NSURL *)url ofType:(NSString *)type;

// Create and open a document

- (id)openUntitledDocumentOfType:(NSString*)type display:(BOOL)display;
- (id)openDocumentWithContentsOfFile:(NSString *)fileName display:(BOOL)display;
- (id)openDocumentWithContentsOfURL:(NSURL *)url display:(BOOL)display;

// With or Without UI

- (BOOL)shouldCreateUI;
- (void)setShouldCreateUI:(BOOL)flag;

// Actions

- (IBAction)saveAllDocuments:(id)sender;
- (IBAction)openDocument:(id)sender;
- (IBAction)newDocument:(id)sender;

// Open Panel

- (NSArray *)fileNamesFromRunningOpenPanel;
- (NSArray *)URLsFromRunningOpenPanel;
- (int)runModalOpenPanel:(NSOpenPanel *)openPanel forTypes:(NSArray *)openableFileExtensions;

// Dealing with all the documents

- (BOOL)closeAllDocuments;
- (BOOL)reviewUnsavedDocumentsWithAlertTitle:(NSString *)title cancellable:(BOOL)cancellable;
- (NSArray *)documents;
- (BOOL)hasEditedDocuments;

- (id)currentDocument;
- (NSString *)currentDirectory;

// Finding documents

- (id)documentForWindow:(NSWindow *)window;
- (id)documentForFileName:(NSString *)fileName;

// menu validation

- (BOOL)validateMenuItem:(NSMenuItem *)anItem;

// Types and extensions

- (NSString *)displayNameForType:(NSString *)type;
- (NSString *)typeFromFileExtension:(NSString *)fileExtension;
- (NSArray *)fileExtensionsFromType:(NSString *)type;
- (Class)documentClassForType:(NSString *)type;

@end

