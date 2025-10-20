/*
	NSFontPanel.h
	Application Kit
	Copyright (c) 1994-1997, Apple Computer, Inc.
	All rights reserved.
*/

#import <AppKit/NSPanel.h>
#import <AppKit/NSFont.h>

@class NSMatrix;
@class NSButton;
@class NSPopUpButton;

/* Tags of views in the FontPanel */

enum {
    NSFPPreviewButton			= 131,
    NSFPRevertButton			= 130,
    NSFPSetButton			= 132,
    NSFPPreviewField			= 128,
    NSFPSizeField			= 129,
    NSFPSizeTitle			= 133,
    NSFPCurrentField			= 134
};

@interface NSFontPanel : NSPanel {
    /*All instance variables are private*/
    NSMatrix 		*_faces;
    NSMatrix 		*_families;
    id                  _preview;
    id                  _current;
    id                  _size;
    NSMatrix 		*_sizes;
    id                  _manager;
    id                  _selFont;
/* Rick, 97/04/22.  The variable _selMetrics is slated for removal.  It is no longer set by any method, and was unreliable anyway.
*/
    struct _NSFontMetrics *_selMetrics;
/* Rick, 97/04/23.  The variable _curTag is slated for removal.  It is no longer used or set; and has been replaced by _curSelFace.
*/
    int                 _curTag;
    id                  _accessoryView;
/* Rick, 97/04/22.  The _keyBuffer variable is slated for removal.  It is no longer set and should not be used.
*/
    NSString		*_keyBuffer;
    NSButton		*_setButton;
    id                  _separator;
    id                  _sizeTitle;
    NSString		*_lastPreview;
    NSPopUpButton	*_fontSetButton;
    id		        _chooser;
    NSMutableArray      *_titles;
    id		        _previewBox;
    struct __fpFlags {
        unsigned int        multipleFont:1;
        unsigned int        dirty:1;
        unsigned int	    doingPreviewButton:1;
        unsigned int        amPreviewing:1;
        unsigned int        alwaysPreview:1;
        unsigned int        dontPreview:1;
	unsigned int	    sizeFieldChanged:1;
	unsigned int	    sizeValueCacheIsValid:1;
	unsigned int	    sizeFieldIsRelative:1;
        unsigned int        RESERVED:24;
    } _fpFlags;
    float		_cachedSizeValue;
    id _familyDict; /* current family dict, obtained from manager */
    id _curSelFace;
}

+ (NSFontPanel *)sharedFontPanel;
+ (BOOL)sharedFontPanelExists;

- (NSView *)accessoryView;
- (void)setAccessoryView:(NSView *)aView;
- (void)setPanelFont:(NSFont *)fontObj isMultiple:(BOOL)flag;
- (NSFont *)panelConvertFont:(NSFont *)fontObj;
- (BOOL)worksWhenModal;
- (BOOL)isEnabled;
- (void)setEnabled:(BOOL)flag;

@end
