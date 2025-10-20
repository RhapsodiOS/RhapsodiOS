/*
        NSOutlineView.h
        Application Kit
        Copyright (c) 1997, Apple Computer, Inc.
        All rights reserved.
*/

#import <AppKit/NSTableView.h>
#import <AppKit/AppKitDefines.h>

@class NSTableView;
@class NSTableHeaderView;
@class NSTableColumn;
@class NSMouseTracker;
@class NSNotification;
@class NSString;

typedef struct __OvFlags {
#ifdef __BIG_ENDIAN__
    unsigned int	delegateWillDisplayCell:1;
    unsigned int	delegateShouldEditTableColumn:1;
    unsigned int	delegateShouldSelectItem:1;
    unsigned int	delegateShouldSelectTableColumn:1;
    unsigned int	delegateSelectionShouldChangeInOutlineView:1;
    unsigned int	delegateShouldCollapseItem:1;
    unsigned int	delegateShouldExpandItem:1;
    unsigned int	autoresizesOutlineColumn:1;
    unsigned int	autoSaveExpandItems:1;
    unsigned int	enableExpandNotifications:1;
    unsigned int	delegateWillDisplayOutlineCell:1;
    unsigned int	removeChildInProgress:1;
    unsigned int	_reserved:20;
#else
    unsigned int	_reserved:20;
    unsigned int	removeChildInProgress:1;
    unsigned int	delegateWillDisplayOutlineCell:1;
    unsigned int	enableExpandNotifications:1;
    unsigned int	autoSaveExpandItems:1;
    unsigned int	autoresizesOutlineColumn:1;
    unsigned int	delegateShouldExpandItem:1;
    unsigned int	delegateShouldCollapseItem:1;
    unsigned int	delegateSelectionShouldChangeInOutlineView:1;
    unsigned int	delegateShouldSelectTableColumn:1;
    unsigned int	delegateShouldSelectItem:1;
    unsigned int	delegateShouldEditTableColumn:1;
    unsigned int	delegateWillDisplayCell:1;
#endif
} _OVFlags;

@interface NSOutlineView : NSTableView {
  @private
    int			_numberOfRows;
    void		*_Rows;
    void		*_REItemCache;
    void		*_REChildCache;
    int			_REItemCount;
    int			_REChildCount;
    NSTableColumn	*_outlineTableColumn;
    BOOL                _initedRows;
    BOOL		_indentationMarkerInCell;
    int			_indentationPerLevel;
    NSButtonCell       	*_outlineCell;
    NSRect		_outlineFrame;
    NSMouseTracker 	*_tracker;
    NSNotificationCenter *_NC;
    _OVFlags		_ovFlags;
    NSLock		*_ovLock;
    long       		*_indentArray;
    long		_originalWidth;
    NSMutableSet	*_expandSet;
    long		_unused;
    long       		_indentArraySize;
    long		_ovReserved[3];
}

// OutlineTableColumn is the column that displays data in a hierarchical fashion,
//	indented one identationlevel per level, decorated with indentation marker
- (void)setOutlineTableColumn: (NSTableColumn *)outlineTableColumn;
- (NSTableColumn *)outlineTableColumn;

// Outline control
- (BOOL)isExpandable:(id)item;		// can the item contain other items?
- (void)expandItem:(id)item expandChildren:(BOOL)expandChildren;
- (void)expandItem:(id)item;		// Above with expandChildren == NO.
- (void)collapseItem:(id)item collapseChildren:(BOOL)collapseChildren;
- (void)collapseItem:(id)item;		// Above with collapseChildren == NO.
- (void)reloadItem:(id)item reloadChildren:(BOOL)reloadChildren;
- (void)reloadItem:(id)item;		// Above with reloadChildren == NO.

// Item/Row translation
- (id)itemAtRow:(int)row;
- (int)rowForItem:(id)item;

// Indentation
- (int)levelForItem:(id)item;
- (int)levelForRow:(int)row;
- (BOOL)isItemExpanded:(id)item;
- (void)setIndentationPerLevel:(float)indentationPerLevel;
- (float)indentationPerLevel;
// The indentation marker is the visual indicator for an item that is expandable
//  (i.e. disclosure triangle, +/- indicators) 
- (void)setIndentationMarkerFollowsCell: (BOOL)drawInCell;
- (BOOL)indentationMarkerFollowsCell;
- (void)setAutoresizesOutlineColumn: (BOOL)resize;
- (BOOL)autoresizesOutlineColumn;

// Persistence
- (BOOL)autosaveExpandedItems;
- (void)setAutosaveExpandedItems:(BOOL)save;
@end

// Data Source Note: Specifying nil as the item will refer to the "root" item(s).
@interface NSObject(NSOutlineViewDataSource)
// required
- (id)outlineView:(NSOutlineView *)outlineView child:(int)index ofItem:(id)item;
- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item;
- (int)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item;
- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item;
// optional
- (void)outlineView:(NSOutlineView *)outlineView setObjectValue:(id)object forTableColumn:(NSTableColumn *)tableColumn byItem:(id)item;
- (id)outlineView:(NSOutlineView *)outlineView itemForPersistentObject:(id)object;
- (id)outlineView:(NSOutlineView *)outlineView persistentObjectForItem:(id)item;
@end

@interface NSObject(NSOutlineViewDelegate)
// NSTableView replacements
- (void)outlineView:(NSOutlineView *)outlineView willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)tableColumn item:(id)item;
- (BOOL)outlineView:(NSOutlineView *)outlineView shouldEditTableColumn:(NSTableColumn *)tableColumn item:(id)item;
- (BOOL)selectionShouldChangeInOutlineView:(NSOutlineView *)outlineView;
- (BOOL)outlineView:(NSOutlineView *)outlineView shouldSelectItem:(id)item;
- (BOOL)outlineView:(NSOutlineView *)outlineView shouldSelectTableColumn:(NSTableColumn *)tableColumn;
// NSOutlineView specific
- (BOOL)outlineView:(NSOutlineView *)outlineView shouldExpandItem:(id)item;
- (BOOL)outlineView:(NSOutlineView *)outlineView shouldCollapseItem:(id)item;
- (void)outlineView:(NSOutlineView *)outlineView willDisplayOutlineCell:(id)cell forTableColumn:(NSTableColumn *)tableColumn item:(id)item;
@end

/* Notifications */
APPKIT_EXTERN NSString *NSOutlineViewSelectionDidChangeNotification;
APPKIT_EXTERN NSString *NSOutlineViewColumnDidMoveNotification;		// @"NSOldColumn", @"NSNewColumn"
APPKIT_EXTERN NSString *NSOutlineViewColumnDidResizeNotification;	// @"NSTableColumn", @"NSOldWidth"
APPKIT_EXTERN NSString *NSOutlineViewSelectionIsChangingNotification;

APPKIT_EXTERN NSString *NSOutlineViewItemWillExpandNotification;	// NSObject
APPKIT_EXTERN NSString *NSOutlineViewItemDidExpandNotification;		// NSObject
APPKIT_EXTERN NSString *NSOutlineViewItemWillCollapseNotification;	// NSObject
APPKIT_EXTERN NSString *NSOutlineViewItemDidCollapseNotification;	// NSObject

@interface NSObject(NSOutlineViewNotifications)
- (void)outlineViewSelectionDidChange:(NSNotification *)notification;
- (void)outlineViewColumnDidMove:(NSNotification *)notification;
- (void)outlineViewColumnDidResize:(NSNotification *)notification;
- (void)outlineViewSelectionIsChanging:(NSNotification *)notification;
- (void)outlineViewItemWillExpand:(NSNotification *)notification;
- (void)outlineViewItemDidExpand:(NSNotification *)notification;
- (void)outlineViewItemWillCollapse:(NSNotification *)notification;
- (void)outlineViewItemDidCollapse:(NSNotification *)notification;
@end

