#import "ProcessTableView.h"

@interface NSTableHeaderView (ProcessViewerPrivate)
- (NSRect)_headerCellRectOfColumn:(int)column;
@end

#ifdef PROCESSVIEWER_TEST
void PVTestInstallProcessTableHeaderViewClass(NSTableHeaderView *headerView)
{
    if (headerView != nil)
        *((Class *)headerView) = [ProcessTableHeaderView class];
}
#define PVInstallProcessTableHeaderViewClass(headerView) PVTestInstallProcessTableHeaderViewClass(headerView)
#else
#define PVInstallProcessTableHeaderViewClass(headerView) do { NSTableHeaderView *pvHeaderView = (headerView); if (pvHeaderView != nil) *((Class *)pvHeaderView) = [ProcessTableHeaderView class]; } while (0)
#endif

@implementation ProcessTableView

- (id)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (self != nil) {
        PVInstallProcessTableHeaderViewClass([self headerView]);
        _highlightedColumnIdentifier = nil;
    }
    return self;
}

- (id)highlightedColumnIdentifier
{
    return _highlightedColumnIdentifier;
}

- (void)setHighlightedColumn:(int)column
{
    if (column < 0) {
        _highlightedColumnIdentifier = nil;
    } else {
        NSTableColumn *tableColumn = [[self tableColumns] objectAtIndex:column];
        _highlightedColumnIdentifier = [tableColumn identifier];
    }
}

@end

@implementation ProcessTableHeaderView

- (void)drawRect:(NSRect)rect
{
    ProcessTableView *tableView = (ProcessTableView *)[self tableView];
    id highlightedIdentifier = [tableView highlightedColumnIdentifier];
    int column;

    [super drawRect:rect];
    if (highlightedIdentifier == nil)
        return;

    column = [tableView columnWithIdentifier:highlightedIdentifier];
    if (column >= 0) {
        NSTableColumn *tableColumn = [[tableView tableColumns] objectAtIndex:column];
        NSRect cellRect = [self _headerCellRectOfColumn:column];
        [[tableColumn headerCell] highlight:YES withFrame:cellRect inView:self];
    }
}

- (void)_modifySelectionWithEvent:(NSEvent *)event onColumn:(int)column
{
    ProcessTableView *tableView = (ProcessTableView *)[self tableView];
    int selectedColumn = [tableView selectedColumn];
    BOOL toggleOff = NO;

    if (column < 0)
        return;

    if (([event modifierFlags] & NSCommandKeyMask) != 0 && column == selectedColumn)
        toggleOff = YES;

    if (selectedColumn >= 0) {
        NSRect oldRect = [self _headerCellRectOfColumn:selectedColumn];
        [self setNeedsDisplayInRect:oldRect];
    }

    if (toggleOff) {
        [tableView selectColumn:-1 byExtendingSelection:NO];
    } else {
        NSRect newRect = [self _headerCellRectOfColumn:column];
        NSTableColumn *tableColumn = [[tableView tableColumns] objectAtIndex:column];
        NSCell *headerCell = [tableColumn headerCell];
        id target = [headerCell target];
        SEL action = [headerCell action];

        [self setNeedsDisplayInRect:newRect];
        [tableView selectColumn:column byExtendingSelection:NO];
        if (target != nil && action != NULL)
            [target performSelector:action withObject:headerCell];
    }
}

@end
