/*
	NSTabViewItem.h
        Application Kit
        Copyright (c) 1997, Apple Computer, Inc.
        All rights reserved.
*/

#import <Foundation/Foundation.h>

//================================================================================
//	Forward Class References
//================================================================================

@class NSTabView;
@class NSString;
@class NSView;
@class NSColor;

//================================================================================
//	enums
//================================================================================

typedef enum _NSTabState {
    NSSelectedTab = 0,
    NSBackgroundTab = 1,
    NSPressedTab = 2
} NSTabState;

//================================================================================
//	NSTabViewItem interface
//================================================================================

@interface NSTabViewItem : NSObject <NSCoding>
{
    @private
    
    	/* Persistent properties */
    
    id			_identifier;    
    NSString		*_label;			// the label
    NSView		*_view;				// view to be displayed
    NSView		*_initialFirstResponder;	// initial first responder for that view
    NSColor		*_color;			// the color of the tab. By default [NSColor controlColor]
    NSTabView		*_tabView;			// back pointer to the tabView. Could be nil.

    	/* Non-persistent properties */
    
    NSTabState		_tabState;			// NSSelectedTab, NSBackgroundTab, or NSPressedTab
    NSView		*_lastKeyView;			// Equal to [_initialFirstResponder previouseKeyView])
    BOOL 		_hasCustomColor;		// YES if _color != [NSColor controlColor]
    BOOL		_labelSizeValid;		// YES if _labelSize is valid
    BOOL		_truncatedLabelsSize;		// YES if _labelSize is the size of the truncated label
    NSSize		_labelSize;			// Cached label size. Valid if _labelSizeValid equal YES
    NSRect		_tabRect;			// Cached tabRect

    	/* Unused */
    
    void		*NSTabViewItemUnused1;
    void		*NSTabViewItemUnused2;
}

	/* Initialization */

- (id)initWithIdentifier:(id)identifier;

    	/* Getters */

- (id)identifier;
- (id)view;
- (id)initialFirstResponder;
- (NSString *)label;
- (NSColor *)color;
- (NSTabState)tabState;
- (NSTabView *)tabView;

    	/* Setters */

- (void)setIdentifier:(id)identifier;
- (void)setLabel:(NSString *)label;
- (void)setColor:(NSColor *)color;
- (void)setView:(NSView *)view;
- (void)setInitialFirstResponder:(NSView *)view;

	/* Tab Drawing/Measuring */

- (void)drawLabel:(BOOL)shouldTruncateLabel inRect:(NSRect)tabRect;	// Override to change the drawing of the label
- (NSSize)sizeOfLabel:(BOOL)shouldTruncateLabel;			// Override if width is not the label width (for example if an icon is added)

@end

