
/*
	NSPageLayout.h
	Application Kit
	Copyright (c) 1994-1997, Apple Computer, Inc.
	All rights reserved.
*/

#import <AppKit/NSApplication.h>
#import <AppKit/NSPanel.h>
#import <AppKit/AppKitDefines.h>

@class NSButton;
@class NSPrintInfo;

#ifndef WIN32
enum {
    NSPLImageButton			= 50,
    NSPLTitleField			= 51,
    NSPLPaperNameButton			= 52,
    NSPLUnitsButton			= 54,
    NSPLWidthForm			= 55,
    NSPLHeightForm			= 56,
    NSPLOrientationMatrix		= 57,
    NSPLCancelButton			= NSCancelButton,
    NSPLOKButton			= NSOKButton
};
#endif WIN32

#ifndef WIN32
@interface NSPageLayout : NSPanel
{
    /*All instance variables are private*/
    id                  _height;
    id                  _width;
    NSButton 		*_ok;
    id                  _cancel;
    id                  _orientation;
    id                  _paperNamePopUp;
    id                  _unitsPopUp;
    int                 _exitTag;
    id                  _paperView;
    id                  _paperViewShadow;
    id                  _accessoryView;
    NSPrintInfo		*_printInfo;
    unsigned char	_currUnits;
    BOOL                _otherPaper;
    BOOL		_recyclable;
    unsigned int _reservedPageLayout1;
}

+ (NSPageLayout *)pageLayout;

- (void)setAccessoryView:(NSView *)aView;
- (NSView *)accessoryView;

#ifndef WIN32
- (void)pickedButton:(id)sender;
- (void)pickedPaperSize:(id)sender;
- (void)pickedOrientation:(id)sender;
- (void)pickedUnits:(id)sender;
- (void)convertOldFactor:(float *)oldFactor newFactor:(float *)newFactor;
#endif WIN32

- (void)readPrintInfo;
- (void)writePrintInfo;
- (NSPrintInfo *)printInfo;
- (int)runModalWithPrintInfo:(NSPrintInfo *)pInfo;
- (int)runModal;

@end

@interface NSApplication(NSPageLayoutPanel)
- (void)runPageLayout:(id)sender;
@end

#else  WIN32

@interface NSPageLayout : NSObject
{
    /*All instance variables are private*/
    void *_printdlg;
    NSPrintInfo *_printInfo;
    id _accessoryView;
    unsigned int _reservedPageLayout1;
}

+ (NSPageLayout *)pageLayout;

- (void)setAccessoryView:(NSView *)aView;
- (NSView *)accessoryView;
- (void)readPrintInfo;
- (void)writePrintInfo;
- (NSPrintInfo *)printInfo;
- (int)runModalWithPrintInfo:(NSPrintInfo *)pInfo;
- (int)runModal;

@end

@interface NSApplication(NSPageLayoutPanel)
- (void)runPageLayout:(id)sender;
@end


#endif WIN32


