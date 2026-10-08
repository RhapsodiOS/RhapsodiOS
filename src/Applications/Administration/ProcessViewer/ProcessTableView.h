#import <AppKit/NSEvent.h>
#import <AppKit/NSCell.h>
#import <AppKit/NSTableColumn.h>
#import <AppKit/NSTableHeaderView.h>
#import <AppKit/NSTableView.h>

@interface ProcessTableHeaderView : NSTableHeaderView
- (void)drawRect:(NSRect)rect;
- (void)_modifySelectionWithEvent:(NSEvent *)event onColumn:(int)column;
@end

@interface ProcessTableView : NSTableView {
    id _highlightedColumnIdentifier;
}
- (id)initWithCoder:(NSCoder *)coder;
- (id)highlightedColumnIdentifier;
- (void)setHighlightedColumn:(int)column;
@end
