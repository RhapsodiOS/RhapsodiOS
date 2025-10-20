/*
        NSTabView.h
        Application Kit
        Copyright (c) 1997, Apple Computer, Inc.
        All rights reserved.
*/

#import <AppKit/NSView.h>

//================================================================================
//	Forward Class References
//================================================================================

@class NSTabViewItem;
@class NSMutableArray;
@class NSTabViewItem;
@class NSFont;
@class NSArray;

//================================================================================
//	enums
//================================================================================

typedef enum _NSTabViewType {
    NSTopTabsBezelBorder	= 0,		// the default
    NSLeftTabsBezelBorder	= 1,		// Not yet supported. Default to NSTopTabsBezelBorder
    NSBottomTabsBezelBorder	= 2,		// Not yet supported. Default to NSTopTabsBezelBorder
    NSRightTabsBezelBorder	= 3,		// Not yet supported. Default to NSTopTabsBezelBorder
    NSNoTabsBezelBorder		= 4,
    NSNoTabsLineBorder		= 5,
    NSNoTabsNoBorder		= 6
} NSTabViewType;

//================================================================================
//	NSTabView Interface
//================================================================================

@interface NSTabView : NSView
{
    @private
    	
    	/* Persistent properties */
    
    NSMutableArray	*_tabViewItems;			// array of NSTabViewItem
    NSTabViewItem	*_selectedTabViewItem;		// nil only if _tabViewItems is empty
    NSFont		*_font;				// font use to display the tab label
    NSTabViewType	_tabViewType;
    BOOL		_allowTruncatedLabels;
    id                  _delegate;

    	/* Non-Persistent properties */

    BOOL		_truncatedLabels;		// YES if labels need to be displayed truncated
    BOOL		_drawsBackground;		// YES if we draw the background when borderless
    NSTabViewItem	*_pressedTabViewItem;		// using during tracking
    int			_endTabWidth;			// Width of the end tab. It depends on the font used.
    int			_maxOverlap;			// Maximum tab overlap. Function of _enTabWidth
    int			_tabHeight;			// Cache height of tabs
    NSTabViewItem	*_tabViewItemWithKeyView;	// the tabViewItem with the keyView "outline"
    NSView 		*_originalNextKeyView;		// Original nextKeyView of the tabView. Needed to restore the keyViewLoop.
    struct __NSTabViewDelegateRespondTo {
        int shouldSelectTabViewItem:1;
        int willSelectTabViewItem:1;
        int didSelectTabViewItem:1;
        int didChangeNumberOfTabViewItems:1;
        int reserved:28;
    } _delegateRespondTo;

    	/* Unused fields */
    
    void		*_tabViewUnused1;			
    void		*_tabViewUnused2;
    void		*_tabViewUnused3;
}

	/* Select */

- (void)selectTabViewItem:(NSTabViewItem *)tabViewItem;
- (void)selectTabViewItemAtIndex:(int)index;				// May raise an NSRangeException
- (void)selectTabViewItemWithIdentifier:(id)identifier;			// May raise an NSRangeException if identifier not found
- (void)takeSelectedTabViewItemFromSender:(id)sender;			// May raise an NSRangeException

	/* Navigation */

- (void)selectFirstTabViewItem:(id)sender;
- (void)selectLastTabViewItem:(id)sender;
- (void)selectNextTabViewItem:(id)sender;
- (void)selectPreviousTabViewItem:(id)sender;

	/* Getters */

- (NSTabViewItem *)selectedTabViewItem;					// return nil if none are selected
- (NSFont *)font;							// returns font used for all tab labels.
- (NSTabViewType)tabViewType;
- (NSArray *)tabViewItems;
- (BOOL)allowsTruncatedLabels;
- (NSSize)minimumSize;							// returns the minimum size of the tab view
- (BOOL)drawsBackground;  						// only relevant for borderless tab view type

	/* Setters */

- (void)setFont:(NSFont *)font;
- (void)setTabViewType:(NSTabViewType)tabViewType;
- (void)setAllowsTruncatedLabels:(BOOL)allowTruncatedLabels;
- (void)setDrawsBackground:(BOOL)flag;  					// only relevant for borderless tab view type

	/* Add/Remove tabs */

- (void)addTabViewItem:(NSTabViewItem *)tabViewItem;				// Add tab at the end.
- (void)insertTabViewItem:(NSTabViewItem *)tabViewItem atIndex:(int)index;	// May raise an NSRangeException
- (void)removeTabViewItem:(NSTabViewItem *)tabViewItem;				// tabViewItem must be an existing tabViewItem

	/* Delegate */

- (void)setDelegate:(id)anObject;
- (id)delegate;

	/* Hit testing */

- (NSTabViewItem *)tabViewItemAtPoint:(NSPoint)point;			// point in local coordinates. returns nil if none.

	/* Geometry */

- (NSRect)contentRect;							// Return the rect available for a "page". 

	/* Query */

- (int)numberOfTabViewItems;
- (int)indexOfTabViewItem:(NSTabViewItem *)tabViewItem;			// NSNotFound if not found
- (NSTabViewItem *)tabViewItemAtIndex:(int)index;			// May raise an NSRangeException	
- (int)indexOfTabViewItemWithIdentifier:(id)identifier;			// NSNotFound if not found

@end

//================================================================================
//	NSTabViewDelegate protocol
//================================================================================

@interface NSObject(NSTabViewDelegate)
- (BOOL)tabView:(NSTabView *)tabView shouldSelectTabViewItem:(NSTabViewItem *)tabViewItem;
- (void)tabView:(NSTabView *)tabView willSelectTabViewItem:(NSTabViewItem *)tabViewItem;
- (void)tabView:(NSTabView *)tabView didSelectTabViewItem:(NSTabViewItem *)tabViewItem;
- (void)tabViewDidChangeNumberOfTabViewItems:(NSTabView *)TabView;
@end
