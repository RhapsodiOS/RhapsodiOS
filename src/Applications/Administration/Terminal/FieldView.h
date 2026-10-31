#ifndef TERMINAL_FIELD_VIEW_H
#define TERMINAL_FIELD_VIEW_H

#import <AppKit/NSView.h>
#import <AppKit/NSColor.h>
#import <Foundation/NSZone.h>

#include "Emulation.h"
#include "Chunk.h"


typedef struct {
    unsigned int line;
    unsigned char col;
    unsigned char _padding[3];
} TerminalSelectionPoint;

typedef char TerminalSelectionPointSizeMustBeEight[
    (sizeof(TerminalSelectionPoint) == 8) ? 1 : -1];
typedef char TerminalSelectionColumnMustFollowLine[
    (offsetof(TerminalSelectionPoint, col) == 4) ? 1 : -1];

typedef struct {
    unsigned int topline;
    unsigned int cursorx;
    unsigned int selectionFlags;
    TerminalSelectionPoint selectionStart;
    TerminalSelectionPoint selectionEnd;
    TerminalChunk *lines;
    id font;
    float desc;
    float dx;
    unsigned char columns;
    unsigned char cellWidth;
    unsigned char cellHeight;
} FieldPrintViewInfo;

typedef struct {
    unsigned char bytes[4];
} TerminalFieldFlags;

typedef char TerminalFieldFlagsMustBeFour[
    (sizeof(TerminalFieldFlags) == 4) ? 1 : -1];

void TermMovetoShow(const char *text, double x, double y);

#define TERMINAL_FIELD_FLAGS(view) \
    (((unsigned int)(view)->aflags.bytes[0] << 24) | \
     ((unsigned int)(view)->aflags.bytes[1] << 16) | \
     ((unsigned int)(view)->aflags.bytes[2] << 8))
#define TERMINAL_FIELD_SET_FLAGS(view, value) do { \
    (view)->aflags.bytes[0] = (unsigned char)((value) >> 24); \
    (view)->aflags.bytes[1] = (unsigned char)((value) >> 16); \
    (view)->aflags.bytes[2] = (unsigned char)((value) >> 8); \
} while (0)

@interface FieldView : NSView
{
@public
    TerminalChunk *lines;
    unsigned int topline;
    id scroller;
    id delegate;
    TerminalSelectionPoint selPt0;
    TerminalSelectionPoint selPt1;
    TerminalChunk *backChunk[3];
    TerminalChunk *underChunk[4];
    TerminalChunk *textChunk[4];
    NSColor *backColor[3];
    NSColor *textColor[4];
    NSColor *cursorColor;
    int cursorShape;
    unsigned char bwidth;
    unsigned char bheight;
    float desc;
    id font;
    id screenfont;
    float dx;
    TerminalFieldFlags aflags;
    unsigned char height;
    unsigned char cursorx;
    unsigned char cursory;
    unsigned char _cursory;
    unsigned char scrolls;
    unsigned char top;
    unsigned char bot;
    char drawCursOK;
    char invalidated;
    char enablePSOutput;
    char drawsLineAtRightEdge;
    NSZone *lineZone;
}

- (id)initWithFrame:(NSRect)frame;
- (BOOL)isFlipped;
- (void)setUpGState;
- (void)setupFont:(id)value;
- (NSSize)windowWillResize:(id)sender toSize:(NSSize)frameSize;
- (void)changeFont:(id)sender;
- (void)copyFont:(id)sender;
- (void)pasteFont:(id)sender;
- (void)recordDefaultsChanges;
- (void)setUpWithDefaults:(const TerminalEmulationDefaults *)defaults;
- (void)setDefaults:(const TerminalEmulationDefaults *)defaults;
- (void)resetCursorRects;
- (void)windowHook:(unsigned int)width :(unsigned int)height;
- (void)windowDidBecomeMain:(id)sender;
- (void)invalidate;
- (id)delegate;
- (void)setDelegate:(id)value;
- (void)setScroller:(id)value;
- (void)_getFieldPrintViewInfo:(FieldPrintViewInfo *)info;
- (void)reflectPosition;
- (void)refreshscreen;
- (void)_clearcursor;
- (void)_clearSelection;
- (void)_sclear:(unsigned int)first to:(unsigned int)last;
- (void)_srhclear:(unsigned int)first to:(unsigned int)last;
- (void)_srhscrollup:(unsigned int)first to:(unsigned int)last lines:(unsigned int)count;
- (void)_srhscrolldown:(unsigned int)first to:(unsigned int)last lines:(unsigned int)count;
- (void)_rawscrollup:(unsigned int)first to:(unsigned int)last lines:(unsigned int)count;
- (void)_rawscrolldown:(unsigned int)first to:(unsigned int)last lines:(unsigned int)count;
- (void)_rawclear:(unsigned int)first to:(unsigned int)last;
- (void)_scrollTo:(unsigned int)line;
- (void)positionFrom:(id)sender;
- (void)jumpToSelection:(id)sender;
- (void)_autoScrollTo:(unsigned int)line;
- (void)_smartAutoScrollTo:(unsigned int)line;
- (void)_point:(NSPoint *)point toPosition:(unsigned int *)line
               :(unsigned int *)column;
- (void)_srclear:(unsigned int)first to:(unsigned int)last;
- (void)_srscrollup:(unsigned int)first to:(unsigned int)last lines:(unsigned int)count;
- (void)_srscrollup:(unsigned int)first to:(unsigned int)last;
- (void)_srscrolldown:(unsigned int)first to:(unsigned int)last lines:(unsigned int)count;
- (void)_srscrolldown:(unsigned int)first to:(unsigned int)last;
- (void)_lclear:(unsigned int)first to:(unsigned int)last;
- (void)_mark:(char *)bytes len:(unsigned int)length;
- (void)_bclear:(unsigned int)line to:(unsigned int)column;
- (void)_bclear:(unsigned int)line from:(unsigned int)column;
- (void)_lscrolldown:(unsigned int)first to:(unsigned int)last lines:(unsigned int)count;
- (void)_lscrollup:(unsigned int)first to:(unsigned int)last lines:(unsigned int)count;
- (void)_lscrollup:(unsigned int)count;
- (void)_bdelete:(unsigned int)line :(unsigned int)column bytes:(unsigned int)count;
- (void)_binsert:(unsigned int)line :(unsigned int)column bytes:(unsigned int)count;
- (void)_sscrollup:(unsigned int)first to:(unsigned int)last lines:(unsigned int)count;
- (void)_sscrollup:(unsigned int)first to:(unsigned int)last;
- (void)_sscrolldown:(unsigned int)first to:(unsigned int)last lines:(unsigned int)count;
- (void)_sscrolldown:(unsigned int)first to:(unsigned int)last;
- (void)lineUp;
- (void)lineDown;
- (void)pageUp;
- (void)pageDown;
- (void)scrollTo:(unsigned int)line;
- (char)isSelected:(unsigned int)column :(unsigned int)line;
- (void)mouseDown:(id)event;
- (id)selStream;
- (const char *)selStr;
- (void)selectAll:(id)sender;
- (void)findPrevWord:(unsigned int)line :(unsigned int)column
                   :(TerminalSelectionPoint *)result;
- (void)findNextWord:(unsigned int)line :(unsigned int)column
                   :(TerminalSelectionPoint *)result;
- (char)findMatchingDelimiter:(unsigned int)line
                            :(unsigned int)column
                    :(TerminalSelectionPoint *)result
                 delimChars:(const char *)delimiters
                  backwards:(char)backwards;
- (void)copy:(id)sender;
- (id)validRequestorForSendType:(id)sendType returnType:(id)returnType;
- (BOOL)writeSelectionToPasteboard:(id)pasteboard types:(id)types;
- (void)clearScrollback:(id)sender;
- (void)_singleClick:(unsigned int)line :(unsigned int)column;
- (void)_doubleClick:(unsigned int)line :(unsigned char)column;
- (void)_drag:(unsigned int)line :(unsigned char)column;
- (void)hackRoutine:(id)sender;
- (void)_dragEnd:(unsigned int)line :(unsigned char)column;
- (void)_tripleClick:(unsigned int)line :(unsigned char)column;
- (void)_shiftClick:(unsigned int)line :(unsigned char)column;
- (char)find:(const char *)text;
- (char)bfind:(const char *)text;
- (void)_smark:(const char *)text len:(unsigned int)length attr:(unsigned char)attributes at:(unsigned int)row :(unsigned int)column back:(int)back;
- (id)_sshighlight:(unsigned int)firstLine :(unsigned int)firstColumn :(unsigned int)lastLine :(unsigned int)lastColumn isLit:(char)isLit;
- (void)_refresh;
- (void)_cursor;
- (void)_delayedCursor:(id)sender;
- (void)_highlightsel:(unsigned int)first to:(unsigned int)last isLit:(char)isLit;
- (void)_highlight:(unsigned int)line :(unsigned char)column to:(unsigned int)endLine :(unsigned char)endColumn isLit:(char)isLit;
- (void)_highlight:(unsigned int)line :(unsigned char)column to:(unsigned int)endLine :(unsigned char)endColumn in:(unsigned int)firstVisible :(unsigned int)lastVisible isLit:(char)isLit;
- (unsigned int)width;
- (unsigned int)height;
- (void)disablePSOutput;
- (void)enablePSOutput;
- (void)setDrawCursOK:(char)value;
- (char)drawCursOK;
- (void)setWrap;
- (void)setDrawsLineAtRightEdge:(char)value;
- (char)drawsLineAtRightEdge;
- (void)sizeEmulationTo:(unsigned int)columns :(unsigned int)rows;
- (void)removeScroller;
- (void)reinstateScroller;

@end

#endif
