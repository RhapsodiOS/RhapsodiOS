#import "FieldPrint.h"
#import "FieldView.h"
#include "TerminalScreen.h"

#import <AppKit/NSPrintInfo.h>
#import <AppKit/NSNibLoading.h>
#import <AppKit/NSPrintOperation.h>
#import <AppKit/NSPrintPanel.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSApplication.h>
#import <AppKit/NSGraphics.h>
#import <AppKit/psops.h>

#include <math.h>

static NSPrintInfo *fieldPrintInfo;
static FieldPrint *fieldPrintView;

@implementation FieldPrint

+ (void)fieldPrint:(id)view
{
    NSRect windowRect;
    NSWindow *window;

    windowRect = NSMakeRect(-0.0f, 0.0f, 176.0f, -0.0f);
    window = [[[NSWindow alloc] initWithContentRect:windowRect
                                          styleMask:2
                                            backing:2
                                              defer:NO] autorelease];

    if (fieldPrintInfo == nil)
        fieldPrintInfo = [NSPrintInfo sharedPrintInfo];
    if (fieldPrintView == nil) {
        fieldPrintView = [[self alloc] initWithFrame:windowRect];
        [NSBundle loadNibNamed:@"PrintAccessory.nib" owner:fieldPrintView];
    }

    fieldPrintView->fieldView = (FieldView *)view;
    fieldPrintView->top = 0;
    fieldPrintView->bot = fieldPrintView->fieldView->lines->count;
    [fieldPrintView setFrameSize:NSMakeSize(
        (float)fieldPrintView->fieldView->height *
            (float)fieldPrintView->fieldView->bwidth,
        (float)fieldPrintView->fieldView->lines->count *
            (float)fieldPrintView->fieldView->bheight)];
    [fieldPrintView->rangeMatrix selectCellAtRow:2 column:0];
    [fieldPrintView->rangeButton setImage:[NSImage imageNamed:@"PrintVisible"]];
    [[window contentView] addSubview:fieldPrintView];

    [fieldPrintInfo setHorizontalPagination:NSFitPagination];
    [fieldPrintInfo setVerticalPagination:NSAutoPagination];
    [fieldPrintInfo setHorizontallyCentered:YES];
    [fieldPrintInfo setVerticallyCentered:NO];
    [fieldPrintInfo setLeftMargin:2.0f];
    [fieldPrintInfo setRightMargin:2.0f];
    [fieldPrintInfo setTopMargin:2.0f];
    [fieldPrintInfo setBottomMargin:2.0f];

    [fieldPrintView->rangeButton setEnabled:NO];
    [fieldPrintView->attrButton setEnabled:NO];
    [NSApp setPerformingPrint:YES];
    [fieldPrintView print:fieldPrintView];
    [NSApp setPerformingPrint:NO];
    [fieldPrintView removeFromSuperview];
}

- (BOOL)isFlipped
{
    return YES;
}

- (void)print:(id)sender
{
    NSPrintPanel *panel;
    NSPrintOperation *operation;

    panel = [NSPrintPanel printPanel];
    operation = [NSPrintOperation printOperationWithView:self
                                                printInfo:fieldPrintInfo];
    [panel setAccessoryView:accessoryView];
    [operation setPrintPanel:panel];
    [operation runOperation];
    (void)sender;
}

- (void)adjustPageHeightNew:(float *)newBottom
                       top:(float)oldTop
                    bottom:(float)oldBottom
                     limit:(float)bottomLimit
{
    float rowSpan;
    float rowHeight;

    rowHeight = fieldView->bheight;
    rowSpan = (oldBottom - oldTop) / rowHeight;
    *newBottom = (float)(floor((double)rowSpan) * (double)rowHeight +
                         (double)oldTop);
    (void)bottomLimit;
}

- (void)drawRect:(NSRect)rect
{
    unsigned int firstRow;
    unsigned int lastRow;
    unsigned int row;

    firstRow = (unsigned int)floor((double)(float)rect.origin.y /
                                   ((double)fieldView->bheight - 0.1));
    if (firstRow >= 28)
        firstRow -= 28;
    lastRow = (unsigned int)ceil((double)(float)(rect.origin.y + rect.size.height) /
                                 ((double)fieldView->bheight - 0.1));
    if (lastRow >= 28)
        lastRow -= 28;

    [fieldView->font set];
    for (row = firstRow; row < lastRow; row++) {
        TerminalLine *line;

        line = terminalLineAt(fieldView->lines, row + top);
        while (line != 0) {
            unsigned char attributes;
            float x;
            float y;
            BOOL bold;

            attributes = [attributeMatrix selectedRow] == 0
                ? line->attributes : 0;
            x = (float)line->column * (float)fieldView->bwidth - 0.1f;
            y = (float)row * (float)fieldView->bheight - 0.1f;
            bold = NO;

            if ((attributes & 1) != 0) {
                PSsetgray(NSLightGray);
                NSRectFill(NSMakeRect(x, y,
                    (float)line->length * (float)fieldView->bwidth - 0.1f,
                    (float)fieldView->bheight - 0.1f));
            }

            PSsetgray((attributes & 8) != 0 ? NSDarkGray : NSBlack);
            if ((attributes & 4) != 0) {
                NSRectFill(NSMakeRect(x,
                    y + (float)fieldView->bheight - fieldView->desc + 1.0f,
                    (float)line->length * (float)fieldView->bwidth - 0.1f,
                    0.1f));
            }

            bold = (attributes & 2) != 0;
            y += (float)fieldView->bheight - fieldView->desc;
            PSmoveto(x, y);
            PSashow(fieldView->dx, 0.0f, line->text);
            if (bold) {
                float offset;

                for (offset = 0.25f; offset <= 1.0f; offset = offset + 0.25f) {
                    PSmoveto(x + offset, y);
                    PSashow(fieldView->dx, 0.0f, line->text);
                }
            }
            line = line->next;
        }
    }
}

- (void)rangePicked:(id)sender
{
    int row;
    NSRect frame;
    unsigned int rowCount;
    NSString *imageName;

    row = [rangeMatrix selectedRow];
    imageName = nil;
    if (row == 0) {
        imageName = @"PrintVisible";
        top = fieldView->topline;
        bot = top + fieldView->cursorx;
    } else if (row == 1) {
        imageName = @"PrintSelection";
        if ((TERMINAL_FIELD_FLAGS(fieldView) & 0x06000000u) != 0 &&
            (fieldView->selPt0.line < fieldView->selPt1.line ||
             fieldView->selPt0.col < fieldView->selPt1.col)) {
            top = fieldView->selPt0.line;
            bot = fieldView->selPt1.line + 1;
        } else {
            top = 0;
            bot = 0;
        }
    } else if (row == 2) {
        imageName = @"PrintAll";
    }

    if (imageName != nil)
        [rangeButton setImage:[NSImage imageNamed:imageName]];

    rowCount = bot - top;
    frame = [self frame];
    frame.size.height = (float)(rowCount * fieldView->bheight);
    [self setFrameSize:frame.size];
    (void)sender;
}

- (void)attributesPicked:(id)sender
{
    int row;
    NSString *imageName;

    row = [attributeMatrix selectedRow];
    if (row == 0)
        imageName = @"PrintAttributes";
    else if (row == 1)
        imageName = @"PrintNoAttributes";
    else {
        (void)sender;
        return;
    }

    [attrButton setImage:[NSImage imageNamed:imageName]];
    (void)sender;
}

@end
