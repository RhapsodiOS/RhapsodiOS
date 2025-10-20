/*
	NSSavePanel.h
	Application Kit
	Copyright (c) 1994-1997, Apple Computer, Inc.
	All rights reserved.
*/

#import <AppKit/NSPanel.h>

/* Tags of views in the SavePanel */

enum {
    NSFileHandlingPanelImageButton	= 150,
    NSFileHandlingPanelTitleField	= 151,
    NSFileHandlingPanelBrowser		= 152,
    NSFileHandlingPanelCancelButton	= NSCancelButton,
    NSFileHandlingPanelOKButton		= NSOKButton,
    NSFileHandlingPanelForm		= 155,
    NSFileHandlingPanelHomeButton	= 156,
    NSFileHandlingPanelDiskButton	= 157,
    NSFileHandlingPanelDiskEjectButton	= 158
};		

@class NSBrowser, NSURL;

#ifndef WIN32
@interface NSSavePanel : NSPanel
{
    /*All instance variables are private*/
    NSBrowser		*_browser;
    id                  _form;
    id                  _homeButton;
    id                  _okButton;
    id			_removableDeviceButton;
    id                  _separator;
    id                  _accessoryView;
    NSString		*_filename;
    NSString		*_directory;
    NSArray		*_filenames;
    NSString		*_requiredType;
    void		*_columns;
    void		*_reserved2;
    int                 _cdcolumn;
    id                  _scroller;
    BOOL		_recyclable;
    struct __spFlags {
        unsigned int        opening:1;
        unsigned int        exitOk:1;
        unsigned int        allowMultiple:1;
        unsigned int        dirty:1;
        unsigned int        invalidateMatrices:1;
        unsigned int        filtered:1;
        unsigned int        canChooseFolders:1;
        unsigned int        treatsFilePackagesAsDirectories:1;
        unsigned int        largeFS:1;
        unsigned int	    delegateValidatesNew:1;
        unsigned int	    canChooseFiles:1;
        unsigned int        checkCase:1;
        unsigned int        cancd:1;
        unsigned int        UnixExpert:1;
        unsigned int        reserved:2;
        unsigned int        delegateCompares:1;
        unsigned int        delegateFilters:1;
        unsigned int	    RESERVED:14;
    }                   _spFlags;
    void		*_reserved;
}
#else
@interface NSSavePanel : NSObject
{
    /*All instance variables are private*/
    NSString *_filename;
    NSString *_directory;
    NSArray  *_filenames;
    NSString *_requiredType;
    NSString *_title;
    NSView   *_accessoryView;
    struct __spFlags {
        unsigned int        RESERVED2:1;
        unsigned int        allowMultiple:1;
        unsigned int        canChooseFolders:1;
        unsigned int        RESERVED:29;
    }         _spFlags;
}
#endif WIN32

+ (NSSavePanel *)savePanel;

- (void)ok:(id)sender;
- (void)cancel:(id)sender;
- (int)runModalForDirectory:(NSString *)path file:(NSString *)name;
- (int)runModal;
- (NSString *)filename;
- (NSURL *)URL;
- (void)setDirectory:(NSString *)path;
- (NSString *)directory;
- (void)setPrompt:(NSString *)prompt;
- (NSString *)prompt;
- (void)setTitle:(NSString *)title;
- (NSString *)title;
- (void)setRequiredFileType:(NSString *)type;
- (NSString *)requiredFileType;
- (void)setTreatsFilePackagesAsDirectories:(BOOL)flag;
- (BOOL)treatsFilePackagesAsDirectories;
- (void)setAccessoryView:(NSView *)aView;
- (NSView *)accessoryView;
- (void)setDelegate:(id)anObject;
- (void)validateVisibleColumns;
- (void)selectText:(id)sender;

@end

@interface NSObject(NSSavePanelDelegate)
- (BOOL)panel:(id)sender isValidFilename:(NSString *)filename;
- (BOOL)panel:(id)sender shouldShowFilename:(NSString *)filename;
- (NSComparisonResult)panel:(id)sender compareFilename:(NSString *)file1 with:(NSString *)file2 caseSensitive:(BOOL)caseSensitive;
@end
