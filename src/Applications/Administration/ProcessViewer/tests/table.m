#import <AppKit/NSTableColumn.h>
#import "../ProcessTableView.h"
#import "test_support.h"

int main(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    ProcessTableView *table = [[ProcessTableView alloc]
        initWithFrame:NSMakeRect(0.0, 0.0, 320.0, 200.0)];
    NSTableHeaderView *header = [[NSTableHeaderView alloc]
        initWithFrame:NSMakeRect(0.0, 0.0, 320.0, 20.0)];
    Class originalHeaderClass = [header class];
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"NAME"];

    PVTestInstallProcessTableHeaderViewClass(header);
    PV_CHECK([header isKindOfClass:[ProcessTableHeaderView class]]);
    *((Class *)header) = originalHeaderClass;

    [table addTableColumn:column];
    [table setHighlightedColumn:0];
    PV_CHECK_OBJECTS_EQUAL([table highlightedColumnIdentifier], @"NAME");
    [table setHighlightedColumn:-1];
    PV_CHECK([table highlightedColumnIdentifier] == nil);

    [column release];
    [header release];
    [table release];
    [pool release];
    return PVFinish();
}
