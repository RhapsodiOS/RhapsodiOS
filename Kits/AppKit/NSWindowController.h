/*
 	NSWindowController.h
        Application Kit
        Copyright (c) 1997, Apple Computer, Inc.
        All rights reserved.
*/

#import <Foundation/Foundation.h>
#import <AppKit/NSNibDeclarations.h>

//================================================================================
//	Definitions
//================================================================================

@class NSWindow;
@class NSDocument;

//================================================================================
//	interface NSWindowController
//================================================================================

@interface NSWindowController : NSObject <NSCoding> {
    @private
    NSWindow 		*_window;
    NSString 		*_windowNibName;
    NSString 		*_windowFrameAutosaveName;
    NSDocument 		*_document;
    NSArray 		*_topLevelObjects;
    id			_owner;
    struct __wcFlags {
        unsigned int shouldCloseDocument:1;
        unsigned int shouldCascade:1;
        unsigned int nibIsLoaded:1;
        unsigned int RESERVED:29;
    } _wcFlags;
    void 		*_reserved1;
    void 		*_reserved2;
}

    // Initializers

- (id)initWithWindowNibName:(NSString *)windowNibName;	// self is the owner
- (id)initWithWindowNibName:(NSString *)windowNibName owner:(id)owner;

- (id)initWithWindow:(NSWindow *)window;

    // window nib Name

- (NSString *)windowNibName;
- (id)owner;

    // Document

- (void)setDocument:(NSDocument *)document;
- (id)document;

    // Frame autosave name

- (void)setWindowFrameAutosaveName:(NSString *)name;
- (NSString *)windowFrameAutosaveName;

    // should close document

- (void)setShouldCloseDocument:(BOOL)flag;
- (BOOL)shouldCloseDocument;

    // Cascade

- (void)setShouldCascadeWindows:(BOOL)flag;
- (BOOL)shouldCascadeWindows;

    // Window Management

- (void)close;
- (NSWindow *)window;
- (IBAction)showWindow:(id)sender;
- (NSString *)windowTitleForDocumentDisplayName:(NSString *)displayName;

    // Window loading (likely to be overriden)

- (BOOL)isWindowLoaded;

- (void)windowDidLoad;
- (void)windowWillLoad;

    // Window loading (unlikely to be overriden)

- (void)loadWindow;

@end
