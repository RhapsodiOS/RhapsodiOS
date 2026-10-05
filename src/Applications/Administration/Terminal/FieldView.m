#import "FieldView.h"
#import "FieldPrint.h"
#import <objc/objc-runtime.h>
#import <AppKit/NSGraphics.h>
#import <AppKit/NSCursor.h>
#import <AppKit/NSApplication.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSFontManager.h>
#import <AppKit/NSFontPanel.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSControl.h>
#import <AppKit/NSScroller.h>
#import <AppKit/NSText.h>
#import <AppKit/NSPanel.h>
#import <AppKit/NSScreen.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSPasteboard.h>
#import <Foundation/NSString.h>
#import <AppKit/obsoleteNSCStringText.h>
#import <Foundation/NSBundle.h>
#import <Foundation/NSData.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSRunLoop.h>
#import <Foundation/NSTimer.h>
#import <AppKit/dpsfriends.h>
#import <AppKit/psops.h>
#import <Foundation/NSException.h>
#import <objc/objc-runtime.h>
#include "TerminalScreen.h"
#include "FindCharacters.h"
#include "WordBoundary.h"
#include "WordSelection.h"
#include "Terminal.h"
#include "TerminalApp.h"

extern id _theDefaultsObject;

static TerminalChunk *fieldSelectionBuffer;
static NSMutableData *fieldSelectionStream;
static unsigned char fieldSelectionByte;
static NSPoint hackPoint;

#include <ctype.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

void killSelIfNecessary(FieldView *view)
{
    unsigned int lineIndex;

    if ((TERMINAL_FIELD_FLAGS(view) & 0x06000000u) == 0)
        return;

    lineIndex = view->lines->count - view->cursorx + view->_cursory;
    if (lineIndex < view->selPt0.line || lineIndex > view->selPt1.line)
        return;

    [view refreshscreen];
    [view _highlightsel:view->topline to:view->topline + view->cursorx
                 isLit:0];
    TERMINAL_FIELD_SET_FLAGS(view,
        TERMINAL_FIELD_FLAGS(view) & 0xF9FFFFFFu);
}

void _PSsplat(float x, float y, float width, float height,
              float sourceY, float destinationY)
{
    static const unsigned char template[0x58] = {
        0x80, 0x09, 0x00, 0x55, 0x02, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x83, 0x00, 0xFF, 0xFF,
        0x00, 0x00, 0x00, 0x71, 0x02, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x01, 0x83, 0x00, 0x00, 0x09,
        0x00, 0x00, 0x00, 0x48, 0x63, 0x6F, 0x6D, 0x70,
        0x6F, 0x73, 0x69, 0x74, 0x65, 0x00, 0x00, 0x00
    };
    unsigned char sequence[sizeof(template)];
    const float values[6] = { x, y, width, height, sourceY, destinationY };
    static const unsigned char offsets[6] = { 8, 16, 24, 32, 48, 56 };
    unsigned int i;
    DPSContext context;

    memcpy(sequence, template, sizeof(sequence));
    for (i = 0; i < 6; ++i) {
        union {
            float value;
            unsigned int bits;
        } representation;
        unsigned int bits;

        representation.value = values[i];
        bits = representation.bits;
        sequence[offsets[i]] = (unsigned char)(bits >> 24);
        sequence[offsets[i] + 1] = (unsigned char)(bits >> 16);
        sequence[offsets[i] + 2] = (unsigned char)(bits >> 8);
        sequence[offsets[i] + 3] = (unsigned char)bits;
    }

    context = DPSGetCurrentContext();
    DPSBinObjSeqWrite(context, sequence, 0x55);
}

static void writeDPSFloat(unsigned char *bytes, float value)
{
    union {
        float value;
        unsigned int bits;
    } representation;

    representation.value = value;
    bytes[0] = (unsigned char)(representation.bits >> 24);
    bytes[1] = (unsigned char)(representation.bits >> 16);
    bytes[2] = (unsigned char)(representation.bits >> 8);
    bytes[3] = (unsigned char)representation.bits;
}

static void writeDPSWord(unsigned char *bytes, unsigned int value)
{
    bytes[0] = (unsigned char)(value >> 24);
    bytes[1] = (unsigned char)(value >> 16);
    bytes[2] = (unsigned char)(value >> 8);
    bytes[3] = (unsigned char)value;
}

static void writeDPSShort(unsigned char *bytes, unsigned short value)
{
    bytes[0] = (unsigned char)(value >> 8);
    bytes[1] = (unsigned char)value;
}

void FVmovetoshow(float x, float y, const char *text)
{
    static const unsigned char template[0x30] = {
        0x80, 0x00, 0x00, 0x05, 0x00, 0x00, 0x00, 0x30,
        0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x83, 0x00, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x6B,
        0x05, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x28,
        0x83, 0x00, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0xA0
    };
    unsigned char sequence[sizeof(template)];
    unsigned char paddingBytes[3] = { 0, 0, 0 };
    unsigned int length;
    unsigned int padding;
    DPSContext context;

    memcpy(sequence, template, sizeof(sequence));
    length = (unsigned int)strlen(text);
    padding = (~(length + 3u)) & 3u;
    writeDPSWord(sequence + 4, 0x30u + length + padding);
    writeDPSFloat(sequence + 12, x);
    writeDPSFloat(sequence + 20, y);
    writeDPSShort(sequence + 0x22, (unsigned short)length);

    context = DPSGetCurrentContext();
    (*context->procs->BinObjSeqWrite)(context, sequence, sizeof(sequence));
    (*context->procs->WriteStringChars)(context, text, length);
    if (padding != 0)
        (*context->procs->WriteStringChars)(context, paddingBytes, padding);
}

void TermMovetoShow(const char *text, double x, double y)
{
    static const unsigned char template[0x30] = {
        0x80, 0x00, 0x00, 0x05, 0x00, 0x00, 0x00, 0x30,
        0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x83, 0x00, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x6B,
        0x05, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x28,
        0x83, 0x00, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0xA0
    };
    unsigned char sequence[sizeof(template)];
    unsigned char paddingBytes[3] = { 0, 0, 0 };
    unsigned int length;
    unsigned int padding;
    DPSContext context;

    memcpy(sequence, template, sizeof(sequence));
    length = (unsigned int)strlen(text);
    padding = (~(length + 3u)) & 3u;
    writeDPSWord(sequence + 4, 0x30u + length + padding);
    writeDPSFloat(sequence + 12, (float)x);
    writeDPSFloat(sequence + 20, (float)y);
    writeDPSShort(sequence + 0x22, (unsigned short)length);

    context = DPSGetCurrentContext();
    (*context->procs->BinObjSeqWrite)(context, sequence, sizeof(sequence));
    (*context->procs->WriteStringChars)(context, text, length);
    if (padding != 0)
        (*context->procs->WriteStringChars)(context, paddingBytes, padding);
}

void FVmovetoashow(float x, float y, float advance, const char *text)
{
    static const unsigned char template[0x40] = {
        0x80, 0x00, 0x00, 0x07, 0x00, 0x00, 0x00, 0x40,
        0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x83, 0x00, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x6B,
        0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x05, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x38,
        0x83, 0x00, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x0A
    };
    unsigned char sequence[sizeof(template)];
    unsigned char paddingBytes[3] = { 0, 0, 0 };
    unsigned int length;
    unsigned int padding;
    DPSContext context;

    memcpy(sequence, template, sizeof(sequence));
    length = (unsigned int)strlen(text);
    padding = (~(length + 3u)) & 3u;
    writeDPSWord(sequence + 4, 0x40u + length + padding);
    writeDPSFloat(sequence + 12, x);
    writeDPSFloat(sequence + 20, y);
    writeDPSFloat(sequence + 36, advance);
    writeDPSShort(sequence + 0x32, (unsigned short)length);

    context = DPSGetCurrentContext();
    (*context->procs->BinObjSeqWrite)(context, sequence, sizeof(sequence));
    (*context->procs->WriteStringChars)(context, text, length);
    if (padding != 0)
        (*context->procs->WriteStringChars)(context, paddingBytes, padding);
}

void FVshow(float x, float y, FieldView *view, const char *text)
{
    float cellHeight;

    if (view->drawsLineAtRightEdge == 0)
        return;
    cellHeight = (float)view->bheight;
    y = y + cellHeight;
    y = y - view->desc;
    if (view->screenfont != nil)
        FVmovetoshow(x, y, text);
    else
        FVmovetoashow(x, y, view->dx, text);
}

typedef struct {
    unsigned char attributes;
    unsigned char length;
    unsigned short reserved;
    char *text;
} TerminalTextChunkEntry;

typedef char TerminalTextChunkAttributeOffsetMustBeZero[
    (offsetof(TerminalTextChunkEntry, attributes) == 0) ? 1 : -1];
typedef char TerminalTextChunkLengthOffsetMustBeOne[
    (offsetof(TerminalTextChunkEntry, length) == 1) ? 1 : -1];
typedef char TerminalTextChunkPointerOffsetMustMatchTarget[
    (offsetof(TerminalTextChunkEntry, text) ==
     (sizeof(void *) == 4 ? 4 : 8)) ? 1 : -1];

static TerminalChunk *addData(TerminalChunk *chunk,
                                     unsigned char attributes,
                                     unsigned int column, const char *text,
                                     unsigned int length, unsigned int width)
{
    TerminalTextChunkEntry *last;
    NSZone *zone;
    unsigned int oldCapacity;
    unsigned int i;
    unsigned int end;

    end = column + length;
    if (chunk->count != 0) {
        last = (TerminalTextChunkEntry *)
            (chunk->elements + (chunk->count - 1) * chunk->elementSize);
        if (last->attributes >= attributes) {
            memcpy(last->text + column, text, length);
            if (last->length < end)
                last->length = (unsigned char)end;
            return chunk;
        }
    }

    if (chunk->count == chunk->allocated) {
        oldCapacity = chunk->allocated;
        chunk = ChunkRealloc(chunk);
        zone = NSZoneFromPointer(chunk);
        for (i = oldCapacity; i < chunk->allocated; ++i) {
            last = (TerminalTextChunkEntry *)
                (chunk->elements + (size_t)i * chunk->elementSize);
            last->text = NSZoneMalloc(zone, (size_t)width + 1);
        }
    }

    last = (TerminalTextChunkEntry *)
        (chunk->elements + (size_t)chunk->count * chunk->elementSize);
    last->attributes = attributes;
    last->length = (unsigned char)end;
    last->reserved = 0;
    memset(last->text, ' ', width);
    memcpy(last->text + column, text, length);
    ++chunk->count;
    return chunk;
}

static TerminalLine *nodeAndCharAt(TerminalLine *line, unsigned int column,
                                   char *character)
{
    unsigned int start;

    *character = 0;
    while (line != NULL && line->column <= column) {
        start = line->column;
        if (column < start + line->length) {
            *character = line->text[column - start];
            return line;
        }
        line = line->next;
    }
    return NULL;
}

@implementation FieldView

- (id)initWithFrame:(NSRect)frame
{
    unsigned int i;

    [super initWithFrame:frame];

    enablePSOutput = 0;
    lineZone = [self zone];
    lines = ChunkMalloc(8, 0x100, 0, 1, lineZone);
    for (i = 0; i < 3; ++i)
        backChunk[i] = ChunkMalloc(0x10, 0x0a, 0, 0, lineZone);
    for (i = 0; i < 4; ++i)
        underChunk[i] = ChunkMalloc(0x10, 0x0a, 0, 0, lineZone);
    for (i = 0; i < 4; ++i)
        textChunk[i] = ChunkMalloc(8, 0x0a, 0, 0, lineZone);

    cursorx = 0;
    height = 0;
    bheight = 0;
    bwidth = 0;
    topline = 0;
    desc = 0.0f;
    dx = 0.0f;
    font = nil;
    delegate = nil;
    invalidated = 1;
    backColor[0] = [[NSColor whiteColor] copy];
    backColor[1] = [[NSColor blackColor] copy];
    backColor[2] = [[NSColor darkGrayColor] copy];
    textColor[0] = [[NSColor blackColor] copy];
    textColor[1] = [[NSColor whiteColor] copy];
    textColor[2] = [[NSColor blackColor] copy];
    textColor[3] = [[NSColor darkGrayColor] copy];
    cursorColor = [[NSColor lightGrayColor] copy];
    drawsLineAtRightEdge = 1;
    return self;
}

- (BOOL)isFlipped
{
    return YES;
}

- (void)setUpGState
{
    id activeFont = screenfont != nil ? screenfont : font;
    [activeFont set];
    [super setUpGState];
}

- (void)setupFont:(NSFont *)value
{
    NSFont *screenFont;
    float ascender;
    float descender;
    float lineHeight;
    float measuredWidth;
    NSString *fontName;
    const char *fontNameBytes;

    screenFont = [value screenFont];
    measuredWidth = [value widthOfString:@"M"];
    if (screenFont != nil) {
        bwidth = (unsigned char)[screenFont widthOfString:@"M"];
        dx = (float)bwidth - 0.5f - measuredWidth;
    } else {
        bwidth = (unsigned char)ceil(measuredWidth);
        dx = (float)bwidth - 0.5f - measuredWidth;
    }
    font = value;
    screenfont = screenFont;

    NSTextFontInfo(value, &ascender, &descender, &lineHeight);
    desc = descender;
    bheight = (unsigned char)(int)lineHeight;
    fontName = [value fontName];
    fontNameBytes = [fontName cString];
    if (fontNameBytes != NULL && strncmp(fontNameBytes, "Ohlfs", 5) == 0) {
        measuredWidth = [value descender];
        desc -= measuredWidth / [value pointSize];
        bheight = (unsigned char)(int)((float)bheight - measuredWidth /
                                       [value pointSize]);
    }
}

- (NSSize)windowWillResize:(id)sender toSize:(NSSize)frameSize
{
    NSWindow *window;
    NSRect currentFrame;
    float columnsDelta;
    float rowsDelta;
    int columns;
    int rows;

    (void)sender;
    window = [self window];
    currentFrame = [window frame];

    columnsDelta = frameSize.width - currentFrame.size.width;
    rowsDelta = frameSize.height - currentFrame.size.height;
    columns = (int)(columnsDelta / (float)bwidth) + (int)height;
    rows = (int)(rowsDelta / (float)bheight) + (int)cursorx;

    if (columns < 10)
        columns = 10;
    else if (columns > 255)
        columns = 255;
    if (rows < 3)
        rows = 3;
    else if (rows > 255)
        rows = 255;

    [self sizeEmulationTo:(unsigned int)columns :(unsigned int)rows];

    frameSize.width = currentFrame.size.width +
        ((float)columns - (float)height) * (float)bwidth;
    frameSize.height = currentFrame.size.height +
        ((float)rows - (float)cursorx) * (float)bheight;
    return frameSize;
}

- (void)setDefaults:(const TerminalEmulationDefaults *)defaults
{
    NSFont *selectedFont;
    NSFont *fallbackFont;
    NSFontPanel *panel;
    NSString *alertTitle;
    NSString *alertMessage;
    NSString *button;
    NSString *fallbackName;
    NSString *fallbackSize;
    NSBundle *bundle;
    float *fontWidths;
    BOOL missingFont;

    selectedFont = [NSFont fontWithName:defaults->var11 size:defaults->var12];
    missingFont = selectedFont == nil;
    fontWidths = missingFont ? NULL : [selectedFont widths];
    if (missingFont || fontWidths['i'] != fontWidths['W']) {
        bundle = [NSBundle mainBundle];
        if (missingFont) {
            alertTitle = [bundle localizedStringForKey:@"Nonexistent Font"
                value:nil table:nil];
            alertMessage = [bundle localizedStringForKey:
                @"The font '%@' does not exist." value:nil table:nil];
        } else {
            alertTitle = [bundle localizedStringForKey:@"Inappropriate Font"
                value:nil table:nil];
            alertMessage = [bundle localizedStringForKey:
                @"%@ %.1f-point is not a constant-width font."
                value:nil table:nil];
        }
        button = [bundle localizedStringForKey:@"OK" value:nil table:nil];
        if (missingFont)
            NSRunAlertPanel(alertTitle, alertMessage, button, nil, nil,
                            defaults->var11);
        else
            NSRunAlertPanel(alertTitle, alertMessage, button, nil, nil,
                            defaults->var11, defaults->var12);

        fallbackName = [bundle localizedStringForKey:@"Ohlfs"
            value:nil table:nil];
        fallbackSize = [bundle localizedStringForKey:@"10.0"
            value:nil table:nil];
        fallbackFont = [NSFont fontWithName:fallbackName
            size:(float)atof([fallbackSize cString])];
        selectedFont = fallbackFont;
    }

    [self setupFont:selectedFont];
    panel = [NSFontPanel sharedFontPanel];
    [panel setPanelFont:font isMultiple:NO];
    if (((TERMINAL_FIELD_FLAGS(self) & 0x08000000u) != 0) !=
        (defaults->var3 != 0)) {
        if ((TERMINAL_FIELD_FLAGS(self) & 0x08000000u) != 0)
            [self disablePSOutput];
        else
            [self enablePSOutput];
        TERMINAL_FIELD_SET_FLAGS(self,
            (TERMINAL_FIELD_FLAGS(self) & 0xF7FFFFFFu) |
            ((defaults->var3 != 0) ? 0x08000000u : 0));
    }
    [self sizeEmulationTo:defaults->var8 :defaults->var7];
}

- (void)changeFont:(id)sender
{
    NSFont *selectedFont;
    NSFontPanel *panel;
    NSBundle *bundle;
    float *fontWidths;
    NSString *fontName;
    NSString *alertTitle;
    NSString *alertMessage;
    NSString *button;
    float pointSize;

    selectedFont = [sender convertFont:font];
    fontWidths = [selectedFont widths];
    if (fontWidths['i'] == fontWidths['W']) {
        [self setupFont:selectedFont];
        [self sizeEmulationTo:height :cursorx];
        [self recordDefaultsChanges];
        return;
    }

    bundle = [NSBundle mainBundle];
    alertTitle = [bundle localizedStringForKey:@"Inappropriate Font"
        value:nil table:nil];
    alertMessage = [bundle localizedStringForKey:
        @"%@ %.1f-point is not a constant-width font.  The current font will not be changed."
        value:nil table:nil];
    button = [bundle localizedStringForKey:@"OK" value:nil table:nil];
    fontName = [selectedFont fontName];
    pointSize = [selectedFont pointSize];
    NSRunAlertPanel(alertTitle, alertMessage, button, nil, nil,
                    fontName, pointSize);
    panel = [NSFontPanel sharedFontPanel];
    [panel setPanelFont:font isMultiple:NO];
}

- (void)copyFont:(id)sender
{
    NSText *editor;
    NSFontManager *fontManager;

    editor = [[NSText allocWithZone:[self zone]] initWithFrame:NSZeroRect];
    if (editor == nil) {
        NSBeep();
        return;
    }

    [self addSubview:editor];
    [editor setFont:font];
    [editor setDelegate:self];
    [editor setTarget:self];
    [editor setAction:@selector(changeFont:)];
    [editor copyFont:sender];
    fontManager = [NSFontManager sharedFontManager];
    [fontManager setDelegate:self];
    [editor selectText:self];
}

- (void)pasteFont:(id)sender
{
    NSText *editor;
    NSFontManager *fontManager;
    NSFont *selectedFont;
    NSBundle *bundle;
    float *fontWidths;
    NSString *alertTitle;
    NSString *alertMessage;
    NSString *button;

    editor = [[NSText allocWithZone:[self zone]] initWithFrame:NSZeroRect];
    if (editor == nil) {
        NSBeep();
        return;
    }

    [self addSubview:editor];
    [editor setEditable:YES];
    [editor setDelegate:self];
    [editor setAction:@selector(changeFont:)];
    fontManager = [NSFontManager sharedFontManager];
    [fontManager setDelegate:self];
    [editor setUsesFontPanel:YES];
    [editor selectText:self];
    selectedFont = [fontManager selectedFont];
    fontWidths = [selectedFont widths];
    if (fontWidths['i'] == fontWidths['W']) {
        [self setupFont:selectedFont];
        [self sizeEmulationTo:height :cursorx];
        [self recordDefaultsChanges];
    } else {
        bundle = [NSBundle mainBundle];
        alertTitle = [bundle localizedStringForKey:@"Inappropriate Font"
            value:nil table:nil];
        alertMessage = [bundle localizedStringForKey:
            @"%@ %.1f-point is not a constant-width font.  The current font will not be changed."
            value:nil table:nil];
        button = [bundle localizedStringForKey:@"OK" value:nil table:nil];
        NSRunAlertPanel(alertTitle, alertMessage, button, nil, nil,
            [selectedFont fontName], [selectedFont pointSize]);
        [[NSFontPanel sharedFontPanel] setPanelFont:font isMultiple:NO];
    }
}

- (void)recordDefaultsChanges
{
    TerminalEmulationDefaults *defaults;
    NSString *fontName;
    NSString *copy;

    defaults = (TerminalEmulationDefaults *)[(Terminal *)self defaults];
    if (defaults->var11 != nil)
        [defaults->var11 release];
    fontName = [font fontName];
    copy = [[NSString allocWithZone:NSZoneFromPointer(defaults)]
        initWithString:fontName];
    defaults->var11 = copy;
    if (copy == nil) {
        [[NSAssertionHandler currentHandler]
            handleFailureInMethod:_cmd
            object:self
            file:[NSString stringWithCString:"FieldView.m"]
            lineNumber:901
            description:@"Can't malloc"];
    }
    defaults->var12 = [font pointSize];
    defaults->var7 = cursorx;
    defaults->var8 = height;
    if ([(TerminalApp *)NSApp prefWindowVisible])
        [[(TerminalApp *)NSApp prefManager] terminalDidBecomeMain:self];
}

- (void)setUpWithDefaults:(const TerminalEmulationDefaults *)defaults
{
    NSWindow *mainWindow;
    NSWindow *window;
    NSScreen *screen;
    NSRect mainFrame;
    NSRect visibleFrame;
    unsigned int originX;
    unsigned int originY;
    unsigned int flags;

    enablePSOutput = 0;
    flags = TERMINAL_FIELD_FLAGS(self) & 0x0FFFFFFFu;
    TERMINAL_FIELD_SET_FLAGS(self, flags);
    originX = defaults->var13;
    originY = defaults->var14;

    mainWindow = [NSApp mainWindow];
    screen = [NSScreen mainScreen];
    if (mainWindow != nil && screen != nil) {
        mainFrame = [mainWindow frame];
        visibleFrame = [screen visibleFrame];
        if (mainFrame.origin.x < visibleFrame.size.width - 160.0f &&
            mainFrame.origin.y + mainFrame.size.height > 160.0f) {
            originX = (unsigned int)(int)(mainFrame.origin.x + 25.0f);
            originY = (unsigned int)(int)(mainFrame.origin.y +
                mainFrame.size.height - 25.0f);
        }
    }

    window = [self window];
    [window setFrameOrigin:NSMakePoint((float)originX, (float)originY)];
    flags = TERMINAL_FIELD_FLAGS(self) | 0x08000000u;
    TERMINAL_FIELD_SET_FLAGS(self, flags);
    [self setDefaults:defaults];

    window = [self window];
    [window setBackgroundColor:[NSColor whiteColor]];
    [window display];
    [window makeKeyAndOrderFront:self];
}

- (id)delegate
{
    return delegate;
}

- (id)emulator
{
    [NSException raise:NSInvalidArgumentException
        format:@"*** Subclass responsibility: %s", sel_getName(_cmd)];
    return self;
}

- (id)defaults
{
    [NSException raise:NSInvalidArgumentException
        format:@"*** Subclass responsibility: %s", sel_getName(_cmd)];
    return nil;
}

- (void)setDelegate:(id)value
{
    if (delegate != nil)
        [delegate autorelease];
    delegate = value;
    [delegate retain];
}

- (void)setScroller:(id)value
{
    if (scroller != nil)
        [scroller release];
    scroller = value;
    [scroller retain];
}

- (void)_getFieldPrintViewInfo:(FieldPrintViewInfo *)info
{
    info->topline = topline;
    info->cursorx = cursorx;
    info->selectionFlags = TERMINAL_FIELD_FLAGS(self);
    info->selectionStart = selPt0;
    info->selectionEnd = selPt1;
    info->lines = lines;
    info->font = font;
    info->desc = desc;
    info->dx = dx;
    info->columns = height;
    info->cellWidth = bwidth;
    info->cellHeight = bheight;
}

- (void)resetCursorRects
{
    [self addCursorRect:[self bounds] cursor:[NSCursor IBeamCursor]];
}

- (void)windowHook:(unsigned int)columns :(unsigned int)rows
{
    (void)columns;
    (void)rows;
}

- (void)windowDidBecomeMain:(id)sender
{
    [[NSFontPanel new] setSelectedFont:font isMultiple:NO];
}

- (void)print:(id)sender
{
    (void)sender;
    [FieldPrint fieldPrint:self];
}

- (unsigned int)width
{
    return height;
}

- (unsigned int)height
{
    return cursorx;
}

- (void)disablePSOutput
{
    drawsLineAtRightEdge = 0;
}

- (void)enablePSOutput
{
    drawsLineAtRightEdge = 1;
}

- (void)setDrawCursOK:(char)value
{
    drawCursOK = value;
}

- (char)drawCursOK
{
    return drawCursOK;
}

- (void)setWrap
{
    unsigned int lineIndex;

    lineIndex = _cursory + lines->count - cursorx;
    terminalLineSetWrapped(lines, lineIndex, 1);
}

- (void)setDrawsLineAtRightEdge:(char)value
{
    drawsLineAtRightEdge = value;
}

- (char)drawsLineAtRightEdge
{
    return drawsLineAtRightEdge;
}

- (void)sizeEmulationTo:(unsigned int)columns :(unsigned int)rows
{
    id window;
    NSRect frame;
    NSRect bounds;
    NSRect heightBounds;
    NSRect nextFrame;
    float cellWidth;
    float cellHeight;
    float inset;
    float widthDelta;
    float heightDelta;
    float rowsDelta;
    double converted;

    if (columns == 0 && rows == 0)
        return;
    if (columns > 255)
        columns = 255;
    if (rows > 255)
        rows = 255;

    window = [self window];
    frame = [window frame];
    bounds = [self bounds];
    heightBounds = [self bounds];

    /* Match the PPC 2^52 integer-to-float conversion sequence. */
    converted = (double)((uint32_t)(columns * bwidth));
    cellWidth = (float)converted;
    converted = (double)((uint32_t)(rows * bheight));
    cellHeight = (float)converted;
    inset = 6.0f;

    widthDelta = (cellWidth - bounds.size.width) + inset;
    heightDelta = (cellHeight - heightBounds.size.height) + inset;
    nextFrame.origin.x = frame.origin.x;
    nextFrame.size.width = frame.size.width + widthDelta;
    nextFrame.size.height = frame.size.height + heightDelta;
    rowsDelta = frame.size.height - nextFrame.size.height;
    nextFrame.origin.y = frame.origin.y + rowsDelta;
    [window setFrame:nextFrame display:NO];
    [window display];
}

- (void)setFrameSize:(NSSize)newSize
{
    unsigned int oldRows;
    unsigned int oldColumns;
    unsigned int oldCursorRow;
    unsigned int retainedRows;
    unsigned int index;
    unsigned int rowsBeforeTrim;
    unsigned int oldScrollback;
    unsigned int flags;
    double converted;
    float inset;
    float cellHeight;
    float cellWidth;
    float rowValue;
    float columnValue;
    NSZone *zone;
    union {
        uint64_t bits;
        double value;
    } biasedInteger;
    TerminalLine *line;
    TerminalLine *joined;
    TerminalLine *left;
    TerminalLine *right;

    oldRows = cursorx;
    oldColumns = height;
    oldCursorRow = cursorx - _cursory;
    oldScrollback = lines->count - cursorx;

    [self removeScroller];
    [self reinstateScroller];
    [super setFrameSize:newSize];

    inset = 6.0f;
    biasedInteger.bits = 0x4330000080000000ULL |
        (uint32_t)(bheight ^ 0x80u);
    converted = biasedInteger.value - 4503601774854144.0;
    cellHeight = (float)converted;
    rowValue = (newSize.height - inset) / cellHeight;
    cursorx = (unsigned char)(int)rowValue;

    biasedInteger.bits = 0x4330000080000000ULL |
        (uint32_t)(bwidth ^ 0x80u);
    converted = biasedInteger.value - 4503601774854144.0;
    cellWidth = (float)converted;
    columnValue = (newSize.width - inset) / cellWidth;
    height = (unsigned char)(int)columnValue;

    if (oldColumns != height) {
        if ([[self emulator] autowrapIsOn]) {
            index = 0;
            while (index < lines->count) {
                while (terminalLineIsWrapped(lines, index) &&
                       lineLength(terminalLineAt(lines, index)) < height &&
                       index + 1 < lines->count) {
                    joined = lineAppend(terminalLineAt(lines, index),
                                        terminalLineAt(lines, index + 1));
                    lines->count--;
                    memmove(lines->elements + (size_t)index * 8,
                            lines->elements + (size_t)(index + 1) * 8,
                            (size_t)(lines->count - index) * 8);
                    terminalLineSet(lines, index, joined);
                }

                if (index < lines->count &&
                    lineLength(terminalLineAt(lines, index)) > height) {
                    line = terminalLineAt(lines, index);
                    lineSplit(line, height, &left, &right);
                    if (lines->count == lines->allocated) {
                        lines = ChunkRealloc(lines);
                        self->lines = lines;
                    }
                    memmove(lines->elements + (size_t)(index + 1) * 8,
                            lines->elements + (size_t)index * 8,
                            (size_t)(lines->count - index) * 8);
                    ++lines->count;
                    terminalLineSet(lines, index, left);
                    terminalLineSetWrapped(lines, index, 1);
                    terminalLineSet(lines, index + 1, right);
                }
                ++index;
            }
        } else {
            for (index = 0; index < lines->count; ++index) {
                line = terminalLineAt(lines, index);
                if (lineLength(line) > height)
                    terminalLineSet(lines, index, truncateLine(line, height));
            }
        }
    }

    retainedRows = lines->count < oldRows ? lines->count : oldRows;
    rowsBeforeTrim = lines->count;
    if (rowsBeforeTrim > cursorx &&
        (TERMINAL_FIELD_FLAGS(self) & 0x08000000u) == 0) {
        unsigned int removeCount = rowsBeforeTrim - cursorx;
        index = removeCount;
        while (index != 0) {
            --index;
            lineFree(terminalLineAt(lines, index));
        }
        memmove(lines->elements, lines->elements + (size_t)removeCount * 8,
                (size_t)cursorx * 8);
        lines->count = cursorx;
    }

    if (rowsBeforeTrim > cursorx) {
        _cursory = (unsigned char)(oldCursorRow > cursorx
            ? 0 : cursorx - oldCursorRow);
    } else if (rowsBeforeTrim < cursorx) {
        unsigned int previousCount = rowsBeforeTrim;
        lines = ChunkGrow(lines, cursorx);
        self->lines = lines;
        memset(lines->elements + (size_t)previousCount * 8, 0,
               (size_t)(cursorx - previousCount) * 8);
        _cursory = (unsigned char)(_cursory + previousCount - retainedRows);
    } else if (retainedRows < cursorx) {
        _cursory = (unsigned char)(cursorx - oldCursorRow);
    }

    [[self emulator] termDidResize:self];
    if (cursory >= height)
        cursory = height - 1;

    if (oldScrollback == topline)
        topline = lines->count - cursorx;
    else if ((TERMINAL_FIELD_FLAGS(self) & 0x08000000u) != 0 &&
             topline > lines->count - cursorx)
        topline = lines->count - cursorx;

    flags = TERMINAL_FIELD_FLAGS(self) & 0xFE7FFFFFu;
    if (lines->count - cursorx < topline + cursorx) {
        if (lines->count - cursorx != topline)
            flags |= 0x01000000u;
    } else {
        flags |= 0x00800000u;
    }
    TERMINAL_FIELD_SET_FLAGS(self, flags);

    if ((flags & 0x06000000u) != 0) {
        if (selPt0.col >= height)
            selPt0.col = height;
        if (selPt1.col >= height)
            selPt1.col = height;
    }

    zone = [self zone];
    (void)zone;
    for (index = 0; index < 4; ++index) {
        unsigned int entry;
        TerminalChunk *chunk = textChunk[index];
        for (entry = 0; entry < chunk->count; ++entry) {
            TerminalTextChunkEntry *textEntry = (TerminalTextChunkEntry *)
                (chunk->elements + entry * chunk->elementSize);
            textEntry->text = NSZoneRealloc(zone, textEntry->text,
                                             (unsigned int)height + 1);
        }
        chunk->count = 0;
        underChunk[index]->count = 0;
    }
    for (index = 0; index < 3; ++index)
        backChunk[index]->count = 0;

    [self sizeEmulationTo:height :cursorx];
    [self resetCursorRects];
    [self invalidate];
}

- (void)removeScroller
{
    NSWindow *window;
    NSView *contentView;
    NSRect contentFrame;
    NSRect scrollerFrame;

    window = [self window];
    [window disableFlushWindow];
    [self disablePSOutput];
    [self _clearSelection];
    [self scrollTo:lines->count - cursorx];
    if ([self respondsToSelector:@selector(pruneNumLinesTo:)])
        [(Terminal *)self pruneNumLinesTo:cursorx];
    [self reflectPosition];

    scrollerFrame = [scroller frame];
    contentView = [window contentView];
    contentFrame = [contentView frame];
    contentFrame.size.width -= scrollerFrame.size.width + 1.0f;
    [self setFrameOrigin:contentFrame.origin];
    [self setBoundsSize:contentFrame.size];

    [scroller removeFromSuperview];
    [scroller setEnabled:NO];
    [contentView setAutoresizesSubviews:NO];
    [window setContentSize:contentFrame.size];
    [contentView setAutoresizesSubviews:YES];
    [window enableFlushWindow];
    [contentView setNeedsDisplay:YES];
}

- (void)reinstateScroller
{
    NSWindow *window;
    NSView *contentView;
    NSRect contentFrame;
    NSRect scrollerFrame;
    NSRect newScrollerFrame;
    NSPoint newOrigin;

    window = [self window];
    [window disableFlushWindow];
    contentView = [window contentView];
    contentFrame = [contentView frame];
    scrollerFrame = [scroller frame];

    [contentView setAutoresizesSubviews:NO];
    [window setContentSize:NSMakeSize(contentFrame.size.width +
                                     scrollerFrame.size.width + 1.0f,
                                     contentFrame.size.height)];
    [contentView setAutoresizesSubviews:YES];

    newOrigin.x = scrollerFrame.size.width + 1.0f;
    newOrigin.y = contentFrame.origin.y;
    [self setFrameOrigin:newOrigin];
    [self setBoundsSize:contentFrame.size];

    newScrollerFrame = NSMakeRect(0.0f, 0.0f, scrollerFrame.size.width,
                                  contentFrame.size.height);
    [contentView addSubview:scroller];
    [scroller setFrame:newScrollerFrame];
    [window enableFlushWindow];
    [contentView setNeedsDisplay:YES];
}

- (void)dealloc
{
    [self invalidate];
    [super dealloc];
}

- (void)invalidate
{
    if (enablePSOutput == 0) {
        enablePSOutput = 1;
        [scroller invalidate];
        [delegate invalidate];
    }
}

- (void)reflectPosition
{
    unsigned int lineCount;

    lineCount = lines->count;
    if (lineCount == cursorx) {
        if ([scroller isEnabled])
            [scroller setEnabled:NO];
    } else {
        if (![scroller isEnabled])
            [scroller setEnabled:YES];
        [scroller setFloatValue:(float)topline / (float)(lineCount - cursorx)
                 knobProportion:(float)cursorx / (float)lineCount];
    }
}

- (char)isSelected:(unsigned int)column :(unsigned int)line
{
    if ((TERMINAL_FIELD_FLAGS(self) & 0x06000000u) == 0)
        return 0;
    if (line < selPt0.line ||
        (line == selPt0.line && column < selPt0.col))
        return 0;
    if (line > selPt1.line ||
        (line == selPt1.line && column >= selPt1.col))
        return 0;
    return 1;
}

- (id)selStream
{
    unsigned int line;
    unsigned int rowLength;
    unsigned int column;
    TerminalLine *terminalLine;
    char *lineBuffer;
    unsigned int requiredCapacity;

    if ((TERMINAL_FIELD_FLAGS(self) & 0x06000000u) == 0 ||
        (selPt1.line == selPt0.line && selPt1.col == selPt0.col))
        return nil;

    line = selPt0.line;
    requiredCapacity = (unsigned int)height + 1u;
    if (fieldSelectionBuffer == NULL) {
        fieldSelectionBuffer = ChunkMalloc(1, 0x20, requiredCapacity, 1,
                                           NSDefaultMallocZone());
    } else if (fieldSelectionBuffer->count < requiredCapacity) {
        if (requiredCapacity >= fieldSelectionBuffer->allocated) {
            fieldSelectionBuffer = ChunkGrow(fieldSelectionBuffer,
                                             requiredCapacity);
        } else {
            fieldSelectionBuffer->count = requiredCapacity;
        }
    }

    if (fieldSelectionBuffer == NULL)
        return nil;

    if (fieldSelectionStream != nil)
        [fieldSelectionStream release];
    fieldSelectionStream = [[NSMutableData alloc] init];
    if (fieldSelectionStream == nil)
        return nil;

    lineBuffer = (char *)fieldSelectionBuffer->elements;
    terminalLine = terminalLineAt(lines, line);
    lineToString(terminalLine, lineBuffer);
    if (line == selPt1.line) {
        column = selPt1.col;
        rowLength = lineLength(terminalLine);
        if (column > rowLength)
            column = rowLength;
        [fieldSelectionStream appendBytes:lineBuffer + selPt0.col
                                   length:column - selPt0.col];
    } else {
        rowLength = lineLength(terminalLine);
        [fieldSelectionStream appendBytes:lineBuffer + selPt0.col
                                   length:rowLength - selPt0.col];
        if (!terminalLineIsWrapped(lines, line)) {
            static const char newline = '\n';
            [fieldSelectionStream appendBytes:&newline length:1];
        }

        while (++line < selPt1.line) {
            terminalLine = terminalLineAt(lines, line);
            lineToString(terminalLine, lineBuffer);
            [fieldSelectionStream appendBytes:lineBuffer
                                       length:(unsigned int)strlen(lineBuffer)];
            if (!terminalLineIsWrapped(lines, line)) {
                static const char newline = '\n';
                [fieldSelectionStream appendBytes:&newline length:1];
            }
        }

        terminalLine = terminalLineAt(lines, selPt1.line);
        lineToString(terminalLine, lineBuffer);
        rowLength = (unsigned int)strlen(lineBuffer);
        column = selPt1.col;
        if (column > rowLength)
            column = rowLength;
        [fieldSelectionStream appendBytes:lineBuffer length:column];
    }

    if (selPt1.col > strlen(lineBuffer)) {
        static const char newline = '\n';
        [fieldSelectionStream appendBytes:&newline length:1];
    }
    return fieldSelectionStream;
}

- (const char *)selStr
{
    NSMutableData *stream;

    stream = [self selStream];
    if (stream == nil)
        return NULL;
    [stream getBytes:&fieldSelectionByte length:1];
    return [stream bytes];
}

- (void)_singleClick:(unsigned int)line :(unsigned int)column
{
    unsigned int flags;
    unsigned int length;

    column = (unsigned char)column;
    length = lineLength(terminalLineAt(lines, line));
    if (column > length)
        column = (unsigned char)length;

    selPt1.line = line;
    selPt1.col = (unsigned char)column;
    selPt0 = selPt1;

    flags = TERMINAL_FIELD_FLAGS(self);
    flags = (flags & ~0x00400000u) | 0x02000000u;
    TERMINAL_FIELD_SET_FLAGS(self, flags);
}

- (void)_doubleClick:(unsigned int)line :(unsigned char)column
{
    static const char openingDelimiters[] = "[]]{}}())";
    static const char closingDelimiters[] = "][}{)(";
    char delimiters[4] = { '\033', '/', 'Z', '\0' };
    const char *pair;
    TerminalSelectionPoint match;
    unsigned int flags;
    char character;

    flags = (TERMINAL_FIELD_FLAGS(self) & 0xF9BFFFFFu) | 0x04000000u;
    TERMINAL_FIELD_SET_FLAGS(self, flags);
    character = (char)charAt(terminalLineAt(lines, line), column);

    pair = strchr(openingDelimiters, (unsigned char)character);
    if (pair == NULL || pair[1] == character) {
        pair = strchr(closingDelimiters, (unsigned char)character);
        if (pair != NULL) {
            delimiters[0] = pair[0];
            delimiters[1] = pair[1];
            if ([self findMatchingDelimiter:line :column :&match
                delimChars:delimiters backwards:1]) {
                selPt0 = match;
                selPt1 = match;
                [self _dragEnd:line :(unsigned char)(column + 1)];
                return;
            }
        }
    } else {
        delimiters[0] = pair[0];
        delimiters[1] = pair[1];
        if ([self findMatchingDelimiter:line :column :&match
            delimChars:delimiters backwards:0]) {
            selPt0.line = line;
            selPt0.col = column;
            selPt1 = selPt0;
            [self _dragEnd:line :(unsigned char)(match.col + 1)];
            TERMINAL_FIELD_SET_FLAGS(self,
                TERMINAL_FIELD_FLAGS(self) | 0x00400000u);
            return;
        }
    }

    [self findPrevWord:line :column :&selPt0];
    selPt1 = selPt0;
    [self findNextWord:line :column :&match];
    [self _dragEnd:match.line :match.col];
}

- (void)_drag:(unsigned int)line :(unsigned char)column
{
    unsigned int mode;
    unsigned int flags;
    unsigned int row;
    unsigned int boundary;
    TerminalSelectionPoint point;

    flags = TERMINAL_FIELD_FLAGS(self);
    mode = (flags >> 25) & 3u;
    if (mode == 3u) {
        if (flags & 0x00400000u) {
            if (line >= selPt0.line) {
                row = line;
                while (terminalLineIsWrapped(lines, row))
                    ++row;
                column = (unsigned char)height;
                [self _dragEnd:row :column];
                return;
            }

            row = selPt0.line;
            while (terminalLineIsWrapped(lines, row))
                ++row;
            if (selPt1.line > row)
                [self _dragEnd:row :(unsigned char)height];
            flags = TERMINAL_FIELD_FLAGS(self) ^ 0x00400000u;
            TERMINAL_FIELD_SET_FLAGS(self, flags);
            row = line;
            while (row != 0 && terminalLineIsWrapped(lines, row - 1u))
                --row;
            line = row;
            column = 0;
        } else {
            if (line > selPt1.line) {
                row = selPt1.line;
                while (row != 0 && terminalLineIsWrapped(lines, row - 1u))
                    --row;
                if (selPt0.line < row)
                    [self _dragEnd:row :0];
                flags = TERMINAL_FIELD_FLAGS(self) ^ 0x00400000u;
                TERMINAL_FIELD_SET_FLAGS(self, flags);
                row = line;
                while (terminalLineIsWrapped(lines, row))
                    ++row;
                [self _dragEnd:row :(unsigned char)height];
                return;
            }
            while (line != 0 && terminalLineIsWrapped(lines, line - 1u))
                --line;
            column = 0;
        }
    } else if (mode == 2u) {
        if (flags & 0x00400000u) {
            if (line < selPt0.line ||
                (line == selPt0.line && column <= selPt0.col)) {
                [self findNextWord:selPt0.line :selPt0.col :&point];
                [self _dragEnd:point.line :(unsigned char)point.col];
                flags = TERMINAL_FIELD_FLAGS(self) ^ 0x00400000u;
                TERMINAL_FIELD_SET_FLAGS(self, flags);
                [self findPrevWord:line :column :&point];
            } else {
                [self findPrevWord:line :column :&point];
            }
            [self _dragEnd:point.line :(unsigned char)point.col];
            return;
        }

        if (line > selPt1.line ||
            (line == selPt1.line && column >= selPt1.col)) {
            [self findPrevWord:selPt1.line
                            :(unsigned int)(selPt1.col - 1u) :&point];
            [self _dragEnd:point.line :(unsigned char)point.col];
            flags = TERMINAL_FIELD_FLAGS(self) ^ 0x00400000u;
            TERMINAL_FIELD_SET_FLAGS(self, flags);
            [self findNextWord:line :column :&point];
        } else {
            [self findPrevWord:line :column :&point];
        }
        [self _dragEnd:point.line :(unsigned char)point.col];
        return;
    }

    if (mode == 1u) {
        boundary = lineLength(terminalLineAt(lines, line));
        if (column > boundary) {
            if (flags & 0x00400000u) {
                if (line < selPt0.line) {
                    while (terminalLineIsWrapped(lines, line))
                        ++line;
                    column = (unsigned char)height;
                } else {
                    column = (unsigned char)boundary;
                }
            } else if (line < selPt1.line) {
                while (terminalLineIsWrapped(lines, line))
                    ++line;
                column = (unsigned char)height;
            } else {
                column = (unsigned char)boundary;
            }
        }
    }
    [self _dragEnd:line :column];
}

- (void)hackRoutine:(id)sender
{
    NSDate *now;
    unsigned int line;
    unsigned int column;

    (void)sender;
    now = [NSDate date];
    if ([NSApp nextEventMatchingMask:0x44
                           untilDate:now
                               inMode:NSDefaultRunLoopMode
                             dequeue:NO] != nil)
        return;

    [self _point:&hackPoint toPosition:&line :&column];
    [self _autoScrollTo:line];
    [self _drag:line :(unsigned char)column];
    [[self window] flushWindow];
}

- (void)_dragEnd:(unsigned int)line :(unsigned char)column
{
    TerminalDelimiterPoint start;
    TerminalDelimiterPoint end;
    TerminalDelimiterPoint click;
    TerminalDragUpdate update;
    unsigned int flags;
    unsigned int index;

    start.line = selPt0.line;
    start.col = selPt0.col;
    end.line = selPt1.line;
    end.col = selPt1.col;
    click.line = line;
    click.col = column;
    flags = TERMINAL_FIELD_FLAGS(self);
    terminalDragUpdate(start, end, click,
                       (flags & 0x00400000u) != 0, &update);

    for (index = 0; index < update.highlightCount; ++index) {
        TerminalHighlightRange *range = &update.highlights[index];
        [self _highlight:range->start.line :(unsigned char)range->start.col
                      to:range->end.line :(unsigned char)range->end.col
                  isLit:(char)range->isLit];
    }

    selPt0.line = update.start.line;
    selPt0.col = update.start.col;
    selPt1.line = update.end.line;
    selPt1.col = update.end.col;
    flags = (flags & ~0x00400000u) |
            (update.backwards ? 0x00400000u : 0);
    TERMINAL_FIELD_SET_FLAGS(self, flags);
}

- (void)_shiftClick:(unsigned int)line :(unsigned char)column
{
    unsigned int flags;
    unsigned int mode;

    flags = TERMINAL_FIELD_FLAGS(self);
    mode = (flags >> 25) & 3u;
    if (mode != 0) {
        if (terminalShiftClickMovesEnd(mode, height, selPt0.line,
                                       selPt0.col, selPt1.line, selPt1.col,
                                       line, column))
            flags |= 0x00400000u;
        else
            flags &= ~0x00400000u;
        TERMINAL_FIELD_SET_FLAGS(self, flags);
    }
    [self enablePSOutput];
}

- (void)_tripleClick:(unsigned int)line :(unsigned char)column
{
    unsigned int firstRow;
    unsigned int lastRow;
    unsigned int flags;

    if (!terminalTripleClickRowRange(lines->elements + 4, 8, lines->count,
                                     line, &firstRow, &lastRow))
        return;
    selPt0.line = firstRow;
    selPt0.col = 0;
    selPt1 = selPt0;
    flags = TERMINAL_FIELD_FLAGS(self);
    flags = (flags & 0xF9BFFFFFu) | 0x06000000u;
    TERMINAL_FIELD_SET_FLAGS(self, flags);
    [self _dragEnd:lastRow :(unsigned char)height];
    (void)column;
}

- (void)_clearcursor
{
    unsigned int column;
    unsigned int lineIndex;
    unsigned int drawRow;
    unsigned int state;
    TerminalLine *line;
    char character;
    unsigned char attributes;
    char selected;
    int back;

    column = cursory - (cursory == height);
    lineIndex = lines->count - cursorx + _cursory;
    line = terminalLineAt(lines, lineIndex);
    selected = [self isSelected:column :lineIndex];
    line = nodeAndCharAt(line, column, &character);
    attributes = line == NULL ? 0 : line->attributes;

    if ((TERMINAL_FIELD_FLAGS(self) & 0x00020000u) == 0)
        return;
    TERMINAL_FIELD_SET_FLAGS(self, TERMINAL_FIELD_FLAGS(self) & 0xFFFDFFFFu);
    if (character == 0) {
        character = ' ';
        attributes = 0;
    }

    state = TERMINAL_FIELD_FLAGS(self) & 0x01800000u;
    if (state != 0) {
        if (state != 0x01000000u)
            return;
        drawRow = lines->count - cursorx + _cursory;
        if (topline + cursorx <= drawRow)
            return;
        drawRow -= topline;
    } else {
        drawRow = _cursory;
    }

    back = selected ? 3 : 2;
    [self _smark:&character len:1 attr:attributes at:drawRow :column back:back];
    [self refreshscreen];
}

- (void)_clearSelection
{
    if ((TERMINAL_FIELD_FLAGS(self) & 0x06000000u) != 0) {
        [self _highlightsel:topline to:topline + cursorx isLit:0];
        TERMINAL_FIELD_SET_FLAGS(self, TERMINAL_FIELD_FLAGS(self) & 0xF9FFFFFFu);
        if (invalidated)
            [self _cursor];
    }
}

- (void)_cursor
{
    unsigned int column;
    unsigned int lineIndex;
    unsigned int row;
    unsigned int shape;
    unsigned int flags;
    char selected;
    TerminalLine *line;
    TerminalLine *characterLine;
    char character;
    unsigned char attributes;
    NSRect rect;

    column = cursory - (cursory == height);
    lineIndex = lines->count - cursorx + _cursory;
    line = terminalLineAt(lines, lineIndex);
    character = 0;
    selected = [self isSelected:column :lineIndex];
    characterLine = nodeAndCharAt(line, column, &character);
    if (characterLine == NULL)
        attributes = 0;
    else
        attributes = characterLine->attributes;

    flags = TERMINAL_FIELD_FLAGS(self) | 0x00020000u;
    TERMINAL_FIELD_SET_FLAGS(self, flags);
    shape = (unsigned int)cursorShape;
    if ((flags & 0x01800000u) == 0) {
        rect = NSMakeRect((float)(column * bwidth), (float)(_cursory * bheight),
                          (float)bwidth, (float)bheight);
        if (shape == 0) {
            [cursorColor set];
            NSRectFill(rect);
        } else {
            unsigned int colorIndex;
            float thickness;

            colorIndex = (attributes & 1) != 0 ? 1 : 0;
            if (selected)
                colorIndex = 2;
            [backColor[colorIndex] set];
            NSRectFill(rect);

            if ((shape & 0x10u) != 0) {
                NSFrameRect(rect);
            } else if (shape == 1) {
                thickness = (float)(bheight >> 3);
                if (thickness < 2.0f)
                    thickness = 2.0f;
                rect.origin.y += rect.size.height - thickness;
                rect.size.height = thickness;
                NSRectFill(rect);
            } else {
                rect.size.width = 1.0f;
                NSRectFill(rect);
            }
        }

        if (character != 0) {
            [self _smark:&character len:1 attr:attributes at:_cursory :column back:0];
            [self refreshscreen];
        }
    } else if ((flags & 0x01800000u) == 0x01000000u &&
               topline + cursorx > lineIndex) {
        row = lineIndex - topline;
        rect = NSMakeRect((float)(column * bwidth), (float)(row * bheight),
                          (float)bwidth, (float)bheight);
        if (shape == 0) {
            [cursorColor set];
            NSRectFill(rect);
        } else {
            unsigned int colorIndex;
            float thickness;

            colorIndex = (attributes & 1) != 0 ? 1 : 0;
            if (selected)
                colorIndex = 2;
            [backColor[colorIndex] set];
            NSRectFill(rect);

            if ((shape & 0x10u) != 0) {
                NSFrameRect(rect);
            } else if (shape == 1) {
                thickness = (float)(bheight >> 3);
                if (thickness < 2.0f)
                    thickness = 2.0f;
                rect.origin.y += rect.size.height - thickness;
                rect.size.height = thickness;
                NSRectFill(rect);
            } else {
                rect.size.width = 1.0f;
                NSRectFill(rect);
            }
        }

        if (character != 0) {
            [self _smark:&character len:1 attr:attributes at:row :column back:0];
            [self refreshscreen];
        }
    }
}

- (void)_delayedCursor:(id)sender
{
    (void)sender;
    if (invalidated != 0) {
        [self _clearSelection];
        [self _cursor];
        [self _refresh];
        [self _cursor];
        [(Terminal *)self updateWindowStatus];
    }
}

- (void)_sclear:(unsigned int)first to:(unsigned int)last
{
    unsigned int visibleFirst;
    unsigned int visibleLast;

    visibleFirst = first < topline ? topline : first;
    visibleLast = last > topline + cursorx ? topline + cursorx : last;
    if (visibleFirst < visibleLast)
        [self refreshscreen];
}

- (void)_rawclear:(unsigned int)first to:(unsigned int)last
{
    NSRect rect;

    [backColor[0] set];
    rect = NSMakeRect(0, first * bheight,
                      height * bwidth, (last - first) * bheight);
    NSRectFill(rect);
}

- (void)_rawscrollup:(unsigned int)first to:(unsigned int)last
                lines:(unsigned int)count
{
    unsigned int pixelDistance;
    unsigned int step;
    unsigned int remainder;
    unsigned int remainderAccumulator;
    unsigned int extra;
    unsigned int frame;
    float firstY;
    float spanHeight;
    float width;
    float remainingHeight;
    float frameHeight;
    float frameY;
    float splatY;
    double converted;
    NSRect rect;
    NSWindow *window;

    converted = (double)(unsigned int)((first + count) * bheight);
    firstY = (float)converted;
    converted = (double)(unsigned int)(height * bwidth);
    width = (float)converted;
    converted = (double)(unsigned int)((last - first - count) * bheight);
    spanHeight = (float)converted;

    if ((TERMINAL_FIELD_FLAGS(self) & 0x00008000u) != 0 && count <= 2u)
        return;

    if (drawsLineAtRightEdge != 0) {
        converted = (double)(unsigned int)(first * bheight);
        _PSsplat(0.0f, firstY, width, spanHeight, 0.0f,
                 (float)converted);
        return;
    }

    [backColor[0] set];

    pixelDistance = (unsigned int)(bheight * count);
    step = pixelDistance / 6u;
    remainder = pixelDistance % 6u;
    converted = (double)(unsigned int)((last - first) * bheight);
    remainingHeight = (float)converted;
    remainderAccumulator = 0;
    converted = (double)(unsigned int)(first * bheight);
    firstY = (float)converted;

    for (frame = 0; frame < 6u; ++frame) {
        remainderAccumulator += remainder;
        if (remainderAccumulator > 5u) {
            remainderAccumulator -= 6u;
            extra = 1u;
        } else {
            extra = 0u;
        }

        frameHeight = (float)(double)(step + extra);
        remainingHeight -= frameHeight;
        frameY = firstY + remainingHeight;

        if (drawsLineAtRightEdge != 0) {
            splatY = firstY + (float)(double)step;
            splatY += (float)(double)extra;
            _PSsplat(0.0f, splatY, width, remainingHeight, 0.0f, firstY);
        }

        rect = NSMakeRect(0.0f, frameY, width, frameHeight);
        NSRectFill(rect);
        window = [self window];
        [window flushWindow];
        if (drawsLineAtRightEdge != 0)
            PSWait();
    }
}

- (void)_rawscrolldown:(unsigned int)first to:(unsigned int)last
                  lines:(unsigned int)count
{
    unsigned int pixelDistance;
    unsigned int step;
    unsigned int remainder;
    unsigned int remainderAccumulator;
    unsigned int extra;
    unsigned int frame;
    unsigned int remainderStep;
    float firstY;
    float spanHeight;
    float width;
    float remainingHeight;
    float frameHeight;
    double converted;
    NSRect rect;
    NSWindow *window;

    converted = (double)(unsigned int)(first * bheight);
    firstY = (float)converted;
    converted = (double)(unsigned int)(height * bwidth);
    width = (float)converted;
    converted = (double)(unsigned int)((last - first - count) * bheight);
    spanHeight = (float)converted;

    if ((TERMINAL_FIELD_FLAGS(self) & 0x00008000u) != 0 && count <= 2u)
        return;

    if (drawsLineAtRightEdge != 0) {
        converted = (double)(unsigned int)((first + count) * bheight);
        _PSsplat(0.0f, firstY, width, spanHeight, 0.0f,
                 (float)converted);
        return;
    }

    [backColor[0] set];

    pixelDistance = (unsigned int)(bheight * count);
    step = pixelDistance / 6u;
    remainder = pixelDistance % 6u;
    converted = (double)(unsigned int)((last - first) * bheight);
    remainingHeight = (float)converted;
    remainderAccumulator = 0;

    for (frame = 0; frame < 6u; ++frame) {
        remainderAccumulator += remainder;
        if (remainderAccumulator > 5u) {
            remainderAccumulator -= 6u;
            extra = 1u;
        } else {
            extra = 0u;
        }

        remainderStep = step + extra;
        frameHeight = (float)(double)remainderStep;

        if (drawsLineAtRightEdge != 0)
            _PSsplat(0.0f, firstY, width,
                     remainingHeight - frameHeight, 0.0f,
                     firstY + frameHeight);

        rect = NSMakeRect(0.0f, firstY, width, frameHeight);
        NSRectFill(rect);
        firstY += frameHeight;
        remainingHeight -= frameHeight;
        window = [self window];
        [window flushWindow];
        if (drawsLineAtRightEdge != 0)
            PSWait();
    }
}

- (void)_sscrollup:(unsigned int)first to:(unsigned int)last
              lines:(unsigned int)count
{
    unsigned int visibleFirst;
    unsigned int visibleLast;
    unsigned int firstRow;
    unsigned int lastRow;

    visibleFirst = first < topline ? topline : first;
    visibleLast = last > topline + cursorx ? topline + cursorx : last;
    if (visibleFirst >= visibleLast)
        return;

    firstRow = visibleFirst - topline;
    lastRow = visibleLast - topline;

    if (lastRow - firstRow >= count) {
        [self _rawscrollup:firstRow to:lastRow lines:count];
        [self _rawclear:lastRow - count to:lastRow];
    } else {
        [self _rawclear:firstRow to:lastRow];
    }
}

- (void)_sscrolldown:(unsigned int)first to:(unsigned int)last
                lines:(unsigned int)count
{
    unsigned int visibleFirst;
    unsigned int visibleLast;
    unsigned int firstRow;
    unsigned int lastRow;

    visibleFirst = first < topline ? topline : first;
    visibleLast = last > topline + cursorx ? topline + cursorx : last;
    if (visibleFirst >= visibleLast)
        return;

    firstRow = visibleFirst - topline;
    lastRow = visibleLast - topline;

    if (lastRow - firstRow >= count) {
        [self _rawscrolldown:firstRow to:lastRow lines:count];
        [self _rawclear:firstRow to:firstRow + count];
    } else {
        [self _rawclear:firstRow to:lastRow];
    }
}

- (void)_srhclear:(unsigned int)first to:(unsigned int)last
{
    unsigned int cursorLine;

    [self _sclear:first to:last];
    if ((TERMINAL_FIELD_FLAGS(self) & 0x06000000u) != 0)
        [self _highlightsel:first to:last isLit:1];

    cursorLine = lines->count - cursorx + _cursory;
    if (cursorLine >= first && cursorLine < last &&
        [[self delegate] autowrapIsOn] && invalidated)
        [self _cursor];
}

- (void)_srhscrollup:(unsigned int)first to:(unsigned int)last
                lines:(unsigned int)count
{
    unsigned int visibleFirst;
    unsigned int visibleLast;

    visibleFirst = first < topline ? topline : first;
    visibleLast = last > topline + cursorx ? topline + cursorx : last;
    if (visibleFirst >= visibleLast)
        return;

    if (visibleLast - visibleFirst >= count) {
        [self _rawscrollup:visibleFirst - topline
                        to:visibleLast - topline lines:count];
        [self _sclear:visibleLast - count to:visibleLast];
    } else {
        [self _sclear:visibleFirst to:visibleLast];
    }
}

- (void)_srhscrolldown:(unsigned int)first to:(unsigned int)last
                  lines:(unsigned int)count
{
    unsigned int visibleFirst;
    unsigned int visibleLast;

    visibleFirst = first < topline ? topline : first;
    visibleLast = last > topline + cursorx ? topline + cursorx : last;
    if (visibleFirst >= visibleLast)
        return;

    if (visibleLast - visibleFirst >= count) {
        [self _rawscrolldown:visibleFirst - topline
                          to:visibleLast - topline lines:count];
        [self _sclear:visibleFirst to:visibleFirst + count];
    } else {
        [self _sclear:visibleFirst to:visibleLast];
    }
}

- (void)_scrollTo:(unsigned int)line
{
    unsigned int nextTop;
    unsigned int lineCount;
    unsigned int flags;

    lineCount = lines->count - cursorx;
    nextTop = line > lineCount ? lineCount : line;
    if (nextTop == topline)
        return;

    if (nextTop + cursorx > topline && nextTop < topline + cursorx) {
        if (nextTop >= topline) {
            unsigned int delta = nextTop - topline;
            topline = nextTop;
            flags = TERMINAL_FIELD_FLAGS(self) & 0xFE7FFFFFu;
            if (lineCount < topline + cursorx) {
                if (lineCount != topline)
                    flags |= 0x01000000u;
            } else {
                flags |= 0x00800000u;
            }
            TERMINAL_FIELD_SET_FLAGS(self, flags);
            [self _srhscrollup:topline to:topline + cursorx lines:delta];
        } else {
            unsigned int delta = topline - nextTop;
            topline = nextTop;
            flags = TERMINAL_FIELD_FLAGS(self) & 0xFE7FFFFFu;
            if (lineCount < topline + cursorx) {
                if (lineCount != topline)
                    flags |= 0x01000000u;
            } else {
                flags |= 0x00800000u;
            }
            TERMINAL_FIELD_SET_FLAGS(self, flags);
            [self _srhscrolldown:topline to:topline + cursorx lines:delta];
        }
    } else {
        topline = nextTop;
        flags = TERMINAL_FIELD_FLAGS(self) & 0xFE7FFFFFu;
        if (lineCount < topline + cursorx) {
            if (lineCount != topline)
                flags |= 0x01000000u;
        } else {
            flags |= 0x00800000u;
        }
        TERMINAL_FIELD_SET_FLAGS(self, flags);
        [self _srhclear:topline to:topline + cursorx];
    }
}

- (void)positionFrom:(id)sender
{
    unsigned char savedPositionFlag = aflags.bytes[1] & 0x80;
    NSScrollerPart hitPart;

    aflags.bytes[1] &= 0x7f;
    hitPart = [(NSScroller *)sender hitPart];
    switch (hitPart) {
    case NSScrollerDecrementPage:
        [self pageUp];
        break;
    case NSScrollerKnob: {
        unsigned int lineCount;
        float fraction;
        float position;
        unsigned int targetLine;

        [self lockFocus];
        fraction = [(NSScroller *)sender floatValue];
        lineCount = lines->count - cursorx;
        position = fraction * (float)lineCount;
        if (position >= 2147483648.0f)
            targetLine = (unsigned int)(position - 2147483648.0f) +
                0x80000000u;
        else
            targetLine = (unsigned int)position;
        [self _scrollTo:targetLine];
        [self unlockFocus];
        break;
    }
    case NSScrollerIncrementPage:
        [self pageDown];
        break;
    case NSScrollerDecrementLine:
        [self lineUp];
        break;
    case NSScrollerIncrementLine:
        [self lineDown];
        break;
    default:
        break;
    }
    aflags.bytes[1] = (aflags.bytes[1] & 0x7f) | savedPositionFlag;
    [self recordDefaultsChanges];
    [[self window] flushWindow];
    PSWait();
}

- (void)jumpToSelection:(id)sender
{
    (void)sender;
    [[self window] disableFlushWindow];
    [self lockFocus];
    if ((TERMINAL_FIELD_FLAGS(self) & 0x06000000u) != 0)
        [self _smartAutoScrollTo:selPt0.line];
    else
        [self _scrollTo:lines->count - cursorx];
    [self unlockFocus];
    [self reflectPosition];
    [[self window] enableFlushWindow];
    [[self window] flushWindow];
}

- (void)scrollTo:(unsigned int)line
{
    [self lockFocus];
    [self _scrollTo:line];
    [self unlockFocus];
    [self reflectPosition];
}

- (void)_srclear:(unsigned int)first to:(unsigned int)last
{
    unsigned int visibleFirst;
    unsigned int visibleLast;
    unsigned int row;
    TerminalLine *line;

    visibleFirst = first < topline ? topline : first;
    visibleLast = last > topline + cursorx ? topline + cursorx : last;
    if (visibleFirst >= visibleLast)
        return;

    [self _sscrollup:visibleFirst - topline to:visibleLast - topline];
    for (row = visibleFirst; row < visibleLast; ++row) {
        line = terminalLineAt(lines, row);
        while (line != NULL) {
            [self _smark:line->text len:line->length attr:line->attributes
                     at:row - topline :(unsigned int)line->column back:1];
            line = line->next;
        }
    }
    [self refreshscreen];
}

- (void)_refresh
{
    unsigned int state;
    unsigned int lineCount;
    NSWindow *window;

    state = (TERMINAL_FIELD_FLAGS(self) >> 20) & 3;
    if (state == 1) {
        if ((TERMINAL_FIELD_FLAGS(self) & 0x01800000u) == 0) {
            [self _srscrollup:topline + bot
                           to:topline + (unsigned char)drawCursOK
                        lines:top];
        } else if ((TERMINAL_FIELD_FLAGS(self) & 0x01800000u) == 0x01000000u) {
            lineCount = lines->count - cursorx;
            [self _srscrolldown:lineCount - top to:lineCount + bot lines:top];
            [self _srscrolldown:lineCount + (unsigned char)drawCursOK - top
                             to:lines->count lines:top];
            if (lineCount >= topline + cursorx)
                TERMINAL_FIELD_SET_FLAGS(self,
                    (TERMINAL_FIELD_FLAGS(self) & 0xFE7FFFFFu) | 0x00800000u);
        }
        top = 0;
        goto refresh_view;
    }
    if (state == 2)
        [self refreshscreen];

refresh_view:
    TERMINAL_FIELD_SET_FLAGS(self,
        TERMINAL_FIELD_FLAGS(self) & 0xFFCFFFFFu);
    [self reflectPosition];
    window = [self window];
    [window flushWindow];
}

- (void)_srscrollup:(unsigned int)first to:(unsigned int)last
               lines:(unsigned int)count
{
    unsigned int visibleFirst;
    unsigned int visibleLast;

    visibleFirst = first < topline ? topline : first;
    visibleLast = last > topline + cursorx ? topline + cursorx : last;
    if (visibleFirst >= visibleLast)
        return;

    if (visibleLast - visibleFirst >= count) {
        [self _sscrollup:visibleFirst - topline
                      to:visibleLast - topline
                   lines:count];
        [self _sscrollup:visibleLast - count to:visibleLast];
    } else {
        [self _sscrollup:visibleFirst to:visibleLast];
    }
}

- (void)_srscrolldown:(unsigned int)first to:(unsigned int)last
                 lines:(unsigned int)count
{
    unsigned int visibleFirst;
    unsigned int visibleLast;

    visibleFirst = first < topline ? topline : first;
    visibleLast = last > topline + cursorx ? topline + cursorx : last;
    if (visibleFirst >= visibleLast)
        return;

    if (visibleLast - visibleFirst >= count) {
        [self _sscrolldown:visibleFirst - topline
                        to:visibleLast - topline
                     lines:count];
        [self _sscrolldown:visibleFirst to:visibleFirst + count];
    } else {
        [self _sscrolldown:visibleFirst to:visibleLast];
    }
}

- (void)_lscrolldown:(unsigned int)first to:(unsigned int)last
                lines:(unsigned int)count
{
    unsigned int lineCount;
    unsigned int firstDiscarded;
    unsigned int i;
    unsigned char *slot;

    [self _refresh];
    lineCount = lines->count - cursorx;
    firstDiscarded = last - count + lineCount;
    for (i = 0; i < count; ++i) {
        slot = lines->elements + (firstDiscarded + i) * 8;
        lineFree(terminalLineAt(lines, firstDiscarded + i));
    }

    slot = lines->elements + lineCount * 8 + first * 8;
    memmove(slot + count * 8, slot,
            (size_t)(last - first - count) * 8);
    memset(slot, 0, (size_t)count * 8);
    [self _srscrolldown:lineCount + first
                     to:lineCount + last
                  lines:count];
}

- (void)_lscrollup:(unsigned int)first to:(unsigned int)last
               lines:(unsigned int)count
{
    unsigned int lineCount;
    unsigned int state;
    unsigned int i;
    unsigned char *slot;

    [self _refresh];
    state = TERMINAL_FIELD_FLAGS(self) & 0x08000000u;
    if (state != 0) {
        lineCount = lines->count - cursorx;
        if (topline == lineCount)
            topline += count;
        lines = terminalLineBufferScrollUpRows(lines, lines->count,
                                               cursorx, first, last, count);
        lineCount = lines->count - cursorx;
    } else {
        for (i = 0; i < count; ++i) {
            slot = lines->elements + (first + i) * 8;
            lineFree(terminalLineAt(lines, first + i));
        }
        lineCount = lines->count - cursorx;
    }

    if (state == 0) {
        slot = lines->elements + (lineCount + first) * 8;
        memmove(slot, slot + count * 8,
                (size_t)(last - first - count) * 8);
        memset(slot + (last - first - count) * 8, 0,
               (size_t)count * 8);
    }

    state = TERMINAL_FIELD_FLAGS(self) & 0x01800000u;
    if (state == 0x01000000u) {
        [self _sscrollup:lineCount - count to:lineCount + first lines:count];
        [self _srscrolldown:lineCount + last - count
                         to:lines->count
                      lines:count];
        if (lineCount >= topline + cursorx)
            TERMINAL_FIELD_SET_FLAGS(self,
                (TERMINAL_FIELD_FLAGS(self) & 0xFE7FFFFFu) | 0x00800000u);
    } else if (state == 0) {
        [self _srscrolldown:topline + first to:topline + last lines:count];
    }
    if (lines->count != cursorx)
        [self reflectPosition];
}

- (void)_lclear:(unsigned int)first to:(unsigned int)last
{
    unsigned int count;
    unsigned int lineCount;
    unsigned int state;
    unsigned int i;
    unsigned char *slot;

    count = last - first;
    [self _refresh];
    state = TERMINAL_FIELD_FLAGS(self) & 0x08000000u;
    if (state != 0) {
        lineCount = lines->count - cursorx;
        if (topline == lineCount)
            topline += count;
        lines = terminalLineBufferClearRows(lines, lines->count,
                                            cursorx, first, last);
        lineCount = lines->count - cursorx;
    } else {
        for (i = first; i < last; ++i) {
            slot = lines->elements + i * 8;
            lineFree(terminalLineAt(lines, i));
        }
        lineCount = lines->count - cursorx;
        memset(lines->elements + (size_t)(lineCount + first) * 8, 0,
               (size_t)count * 8);
    }

    state = TERMINAL_FIELD_FLAGS(self) & 0x01800000u;
    if (state == 0x01000000u) {
        [self _srscrolldown:lineCount to:lineCount + last lines:count];
        [self _sclear:lineCount + last to:lines->count];
        if (lineCount >= topline + cursorx)
            TERMINAL_FIELD_SET_FLAGS(self,
                (TERMINAL_FIELD_FLAGS(self) & 0xFE7FFFFFu) | 0x00800000u);
    } else if (state == 0) {
        [self _sclear:topline + first to:topline + last];
    }
    if (lines->count != cursorx)
        [self reflectPosition];
}

- (void)_bclear:(unsigned int)line to:(unsigned int)column
{
    unsigned int lineIndex;
    unsigned int state;
    unsigned int drawRow;
    NSRect rect;

    [self _refresh];
    lineIndex = lines->count - cursorx + line;
    {
        TerminalLine *updatedLine = lineClearTo(terminalLineAt(lines, lineIndex), column);
        terminalLineSet(lines, lineIndex, updatedLine);
    }
    if (lineIndex != 0)
        terminalLineSetWrapped(lines, lineIndex - 1, 0);

    state = TERMINAL_FIELD_FLAGS(self) & 0x01800000u;
    if (state == 0) {
        drawRow = line;
    } else if (state == 0x01000000u && topline + cursorx >
               lines->count - cursorx + _cursory) {
        drawRow = lineIndex - topline;
    } else {
        return;
    }

    [backColor[0] set];
    rect = NSMakeRect(0, drawRow * bheight,
                      (column + 1) * bwidth, bheight);
    NSRectFill(rect);
}

- (void)_bclear:(unsigned int)line from:(unsigned int)column
{
    unsigned int lineIndex;
    unsigned int state;
    unsigned int drawRow;
    NSRect rect;

    [self _refresh];
    lineIndex = lines->count - cursorx + line;
    {
        TerminalLine *updatedLine = lineClearFrom(terminalLineAt(lines, lineIndex), column);
        terminalLineSet(lines, lineIndex, updatedLine);
    }
    terminalLineSetWrapped(lines, lineIndex, 0);

    state = TERMINAL_FIELD_FLAGS(self) & 0x01800000u;
    if (state == 0) {
        drawRow = line;
    } else if (state == 0x01000000u && topline + cursorx >
               lines->count - cursorx + _cursory) {
        drawRow = lineIndex - topline;
    } else {
        return;
    }

    [backColor[0] set];
    rect = NSMakeRect(column * bwidth, drawRow * bheight,
                      (height - column) * bwidth, bheight);
    NSRectFill(rect);
}

- (void)_lscrollup:(unsigned int)count
{
    unsigned int state;
    unsigned int lineCount;
    unsigned int i;
    unsigned char *slot;

    state = (TERMINAL_FIELD_FLAGS(self) >> 20) & 3u;
    if (state == 1) {
        if (top <= 11) {
            top += count;
        } else {
            [self _clearSelection];
            TERMINAL_FIELD_SET_FLAGS(self,
                (TERMINAL_FIELD_FLAGS(self) & 0xFFCFFFFFu) | 0x00100000u);
            top = count;
        }
    } else if (state == 0 || state == 2) {
        if (state == 2)
            [self _clearSelection];
        TERMINAL_FIELD_SET_FLAGS(self,
            (TERMINAL_FIELD_FLAGS(self) & 0xFFCFFFFFu) | 0x00100000u);
        top = count;
    }

    state = TERMINAL_FIELD_FLAGS(self) & 0x08000000u;
    if (state != 0) {
        lines = terminalLineBufferScrollUpRows(lines, lines->count,
                                               cursorx, bot, drawCursOK,
                                               count);
    } else {
        for (i = 0; i < count; ++i) {
            slot = lines->elements + (bot + i) * 8;
            lineFree(terminalLineAt(lines, bot + i));
        }
    }

    lineCount = lines->count - cursorx;
    if (state == 0) {
        slot = lines->elements + (lineCount + bot) * 8;
        memmove(slot, slot + count * 8,
                (size_t)(drawCursOK - bot - count) * 8);
        memset(slot + (size_t)(drawCursOK - bot - count) * 8, 0,
               (size_t)count * 8);
    }
    scrolls = _cursory;
}

- (void)_bdelete:(unsigned int)line :(unsigned int)column bytes:(unsigned int)count
{
    unsigned int lineIndex;
    TerminalLine *updatedLine;

    lineIndex = lines->count - cursorx + line;
    updatedLine = lineDeleteChars(terminalLineAt(lines, lineIndex), column, count);
    terminalLineSet(lines, lineIndex, updatedLine);
}

- (void)_binsert:(unsigned int)line :(unsigned int)column bytes:(unsigned int)count
{
    unsigned int lineIndex;
    TerminalLine *updatedLine;

    lineIndex = lines->count - cursorx + line;
    updatedLine = insertChars(terminalLineAt(lines, lineIndex), column, count);
    terminalLineSet(lines, lineIndex, updatedLine);
}

- (void)lineUp
{
    if (topline != 0)
        [self scrollTo:topline - 1];
}

- (void)lineDown
{
    if (topline < lines->count - cursorx)
        [self scrollTo:topline + 1];
}

- (void)pageUp
{
    if (topline <= cursorx - 2)
        [self scrollTo:0];
    else
        [self scrollTo:topline - cursorx + 2];
}

- (void)pageDown
{
    if (topline >= lines->count - cursorx - cursorx + 2)
        [self scrollTo:lines->count - cursorx];
    else
        [self scrollTo:topline + cursorx - 2];
}

- (void)_mark:(char *)bytes len:(unsigned int)length
{
    unsigned int lineIndex;
    unsigned int flags;
    unsigned int state;
    unsigned int redrawState;
    unsigned int redrawRow;
    TerminalLine *node;
    TerminalLine *line;

    lineIndex = lines->count - cursorx + _cursory;
    node = newNode(bytes, length, (int8_t)cursory,
                   (int8_t)(TERMINAL_FIELD_FLAGS(self) >> 28), lineZone);
    line = insertNode(node, terminalLineAt(lines, lineIndex));
    terminalLineSet(lines, lineIndex, line);

    killSelIfNecessary(self);

    if (_cursory < scrolls)
        [self _refresh];

    state = (TERMINAL_FIELD_FLAGS(self) >> 20) & 3u;
    if (state == 0) {
        TERMINAL_FIELD_SET_FLAGS(self,
            (TERMINAL_FIELD_FLAGS(self) & 0xFFCFFFFFu) | 0x00200000u);
        state = 2;
    }
    if (state == 2) {
        redrawState = (TERMINAL_FIELD_FLAGS(self) >> 23) & 3u;
        if (redrawState == 2) {
            redrawRow = _cursory + lines->count - cursorx - topline;
            [self _smark:bytes len:length
                    attr:(unsigned char)(TERMINAL_FIELD_FLAGS(self) >> 28)
                     at:redrawRow :cursory back:2];
        } else if (redrawState == 0) {
            [self _smark:bytes len:length
                    attr:(unsigned char)(TERMINAL_FIELD_FLAGS(self) >> 28)
                     at:_cursory :cursory back:2];
        }
    }

    scrolls = _cursory;
    cursory = (unsigned char)(cursory + length);
}

- (void)_smark:(const char *)text len:(unsigned int)length
          attr:(unsigned char)attributes at:(unsigned int)row
              :(unsigned int)column back:(int)back
{
    float rect[4];
    unsigned int style;
    unsigned int underline;

    if (row >= cursorx)
        return;

    rect[0] = (float)(column * bwidth);
    rect[1] = (float)(row * bheight);
    rect[2] = (float)(length * bwidth);
    rect[3] = (float)bheight;
    if (back == 3)
        backChunk[2] = ChunkAdd(backChunk[2], rect);
    else if ((attributes & 1) != 0 && back != 0)
        backChunk[1] = ChunkAdd(backChunk[1], rect);
    else if (back == 2)
        backChunk[0] = ChunkAdd(backChunk[0], rect);

    style = (attributes & 2) != 0 ? 2 :
            (attributes & 8) != 0 ? 3 :
            (attributes & 1) != 0 ? 1 : 0;
    textChunk[style] = addData(textChunk[style], attributes, column, text,
                               length, height);

    underline = attributes & 4;
    if (underline != 0) {
        rect[1] += bheight - (int)desc;
        rect[3] = 1.0f;
        if ((attributes & 2) != 0)
            underChunk[2] = ChunkAdd(underChunk[2], rect);
        else if ((attributes & 8) != 0)
            underChunk[3] = ChunkAdd(underChunk[3], rect);
        else if ((attributes & 1) != 0)
            underChunk[1] = ChunkAdd(underChunk[1], rect);
        else
            underChunk[0] = ChunkAdd(underChunk[0], rect);
    }
}

- (void)_highlightsel:(unsigned int)first to:(unsigned int)last isLit:(char)isLit
{
    [self _highlight:selPt0.line :(unsigned char)selPt0.col
                  to:selPt1.line :(unsigned char)selPt1.col
                  in:first to:last isLit:isLit];
}

- (void)_highlight:(unsigned int)line :(unsigned char)column
                to:(unsigned int)endLine :(unsigned char)endColumn
               in:(unsigned int)firstVisible :(unsigned int)lastVisible
             isLit:(char)isLit
{
    unsigned int firstLine;
    unsigned int lastLine;
    unsigned int firstColumn;
    unsigned int lastColumn;
    unsigned int visibleFirst;
    unsigned int visibleLast;
    unsigned int endColumnForRow;
    unsigned int startLine;
    unsigned int finishLine;

    firstLine = line;
    lastLine = endLine;
    firstColumn = column;
    lastColumn = endColumn;
    visibleFirst = firstVisible > topline ? firstVisible : topline;
    visibleLast = lastVisible < topline + cursorx ? lastVisible : topline + cursorx;
    if (visibleLast <= visibleFirst || line >= visibleLast || endLine < visibleFirst ||
        (line == endLine && column == endColumn))
        return;

    if (firstLine < visibleFirst) {
        firstLine = visibleFirst;
        firstColumn = 0;
    }
    if (lastLine >= visibleLast) {
        lastLine = visibleLast - 1;
        lastColumn = height;
    }
    if (firstColumn >= height) {
        ++firstLine;
        firstColumn = 0;
    }
    if (lastColumn == 0 && lastLine != 0) {
        --lastLine;
        lastColumn = height;
    }

    startLine = firstLine - topline;
    finishLine = lastLine - topline;
    if (firstColumn != 0) {
        if (startLine == finishLine) {
            [self _sshighlight:finishLine :firstColumn :finishLine :lastColumn isLit:isLit];
            return;
        }
        [self _sshighlight:startLine :firstColumn :startLine :height isLit:isLit];
        ++startLine;
    }
    if (lastColumn < height) {
        [self _sshighlight:finishLine :0 :finishLine :lastColumn isLit:isLit];
        if (finishLine == 0)
            return;
        --finishLine;
    }
    if (startLine <= finishLine) {
        endColumnForRow = height;
        [self _sshighlight:startLine :0 :finishLine :endColumnForRow isLit:isLit];
    }
}

- (void)_highlight:(unsigned int)line :(unsigned char)column
                to:(unsigned int)endLine :(unsigned char)endColumn
             isLit:(char)isLit
{
    [self _highlight:line :column
                  to:endLine :endColumn
                  in:topline :topline + cursorx isLit:isLit];
}

- (id)_sshighlight:(unsigned int)firstLine :(unsigned int)firstColumn
                  :(unsigned int)lastLine :(unsigned int)lastColumn
             isLit:(char)isLit
{
    unsigned int row;
    unsigned int endX;
    unsigned int currentX;
    unsigned int first;
    unsigned int runLength;
    unsigned int available;
    unsigned int back;
    TerminalLine *line;
    float rect[4];

    if (firstLine == lastLine && firstColumn == lastColumn)
        return self;

    back = isLit == 0 ? 2 : 3;
    endX = lastColumn * bwidth;
    for (row = firstLine; row <= lastLine; ++row) {
        line = terminalLineAt(lines, topline + row);
        currentX = firstColumn * bwidth;
        while (line != NULL) {
            if (firstColumn < (unsigned int)line->column + line->length) {
                if (lastColumn < line->column)
                    break;
                first = firstColumn > line->column ? firstColumn : line->column;
                available = lastColumn - firstColumn;
                if (available > line->length)
                    available = line->length;
                if (available > (unsigned int)line->column + line->length - firstColumn)
                    available = (unsigned int)line->column + line->length - firstColumn;
                runLength = lastColumn - first;
                if (runLength > available)
                    runLength = available;
                if (runLength != 0) {
                    if (first * bwidth > currentX) {
                        rect[0] = (float)currentX;
                        rect[1] = (float)(row * bheight);
                        rect[2] = (float)(first * bwidth - currentX);
                        rect[3] = (float)bheight;
                        backChunk[isLit == 0 ? 0 : 2] =
                            ChunkAdd(backChunk[isLit == 0 ? 0 : 2], rect);
                    }
                    [self _smark:line->text + first - line->column
                             len:runLength attr:line->attributes
                              at:row :first back:back];
                    currentX = (first + runLength) * bwidth;
                }
            }
            line = line->next;
        }
        if (endX > currentX) {
            rect[0] = (float)currentX;
            rect[1] = (float)(row * bheight);
            rect[2] = (float)(endX - currentX);
            rect[3] = (float)bheight;
            backChunk[isLit == 0 ? 0 : 2] =
                ChunkAdd(backChunk[isLit == 0 ? 0 : 2], rect);
        }
    }
    [self refreshscreen];
    return self;
}

- (void)refreshscreen
{
    unsigned int index;
    unsigned int itemIndex;
    unsigned int pass;
    unsigned int passCount;
    TerminalChunk *chunk;
    TerminalChunk *text;
    TerminalChunk *under;
    TerminalTextChunkEntry *entry;
    float y;

    for (index = 0; index < 3; ++index) {
        chunk = backChunk[index];
        if (chunk->count != 0) {
            [backColor[index] set];
            NSRectFillList((const NSRect *)chunk->elements, (int)chunk->count);
            chunk->count = 0;
        }
    }

    for (index = 0; index < 4; ++index) {
        text = textChunk[index];
        if (text->count == 0)
            continue;

        [textColor[index] set];
        under = underChunk[index];
        if (under->count != 0) {
            NSRectFillList((const NSRect *)under->elements, (int)under->count);
            under->count = 0;
        }

        passCount = index == 2 &&
                    (TERMINAL_FIELD_FLAGS(self) & 0x00080000u) != 0
                  ? 2 : 1;
        for (pass = 0; pass < passCount; ++pass) {
            for (itemIndex = text->count; itemIndex != 0; --itemIndex) {
                entry = (TerminalTextChunkEntry *)
                    (text->elements + (itemIndex - 1) * text->elementSize);
                entry->text[entry->length] = '\0';
                y = (float)((unsigned int)entry->attributes * bheight);
                FVshow(pass == 0 ? 0.0f : 1.0f, y, self, entry->text);
            }
        }
        text->count = 0;
    }
}

@end

static unsigned char fieldFindFold(unsigned char value)
{
    if (terminalFindIgnoreCase == 1 && value < 0x80 && isalpha(value))
        return (unsigned char)tolower(value);
    return value;
}

static char fieldFind(FieldView *view, const char *query, int backwards)
{
    char *pattern;
    size_t patternLength;
    uint32_t originLine;
    uint32_t originColumn;
    uint32_t startLine;
    uint32_t startColumn;
    uint32_t endLine;
    uint32_t endColumn;
    uint32_t flags;
    int current;
    int first;
    char found;

    if (query == 0 || query[0] == '\0')
        return 0;

    patternLength = strlen(query) + 1u;
    pattern = (char *)NSZoneMalloc([view zone], patternLength);
    if (pattern == 0)
        return 0;
    strcpy(pattern, query);
    if (terminalFindIgnoreCase == 1) {
        char *character;
        for (character = pattern; *character != '\0'; ++character)
            *character = (char)fieldFindFold((unsigned char)*character);
    }

    flags = TERMINAL_FIELD_FLAGS(view);
    if ((flags & 0x06000000u) != 0) {
        if (backwards) {
            originLine = view->selPt0.line;
            originColumn = view->selPt0.col;
        } else {
            originLine = view->selPt1.line;
            originColumn = view->selPt1.col;
        }
    } else {
        originLine = view->lines->count - view->cursorx + view->_cursory;
        originColumn = view->cursory;
    }

    openFStream(view->lines, originLine, (unsigned char)originColumn);
    getPosition(&endLine, &endColumn);

    found = 0;
    first = 1;
    while (first || (backwards
               ? cmpFStream(endLine, endColumn) > 0
               : cmpFStream(endLine, endColumn) < 0)) {
        uint32_t candidateLine;
        uint32_t candidateColumn;
        const char *character;
        int matched;

        first = 0;
        current = backwards ? prevGetChar() : nextGetChar();
        if (current == 0)
            break;
        if (fieldFindFold((unsigned char)current) !=
            fieldFindFold((unsigned char)pattern[0]))
            continue;

        if (backwards) {
            getPosition(&candidateLine, &candidateColumn);
            nextGetChar();
        } else {
            prevGetChar();
            getPosition(&candidateLine, &candidateColumn);
            nextGetChar();
        }

        matched = 1;
        for (character = pattern + 1; *character != '\0'; ++character) {
            current = nextGetChar();
            if (current == 0 ||
                fieldFindFold((unsigned char)current) !=
                fieldFindFold((unsigned char)*character)) {
                matched = 0;
                break;
            }
        }

        if (matched) {
            getPosition(&endLine, &endColumn);
            flags = TERMINAL_FIELD_FLAGS(view);
            if ((flags & 0x06000000u) == 0 ||
                view->selPt0.line != candidateLine ||
                view->selPt0.col != candidateColumn ||
                view->selPt1.line != endLine ||
                view->selPt1.col != endColumn) {
                [view _clearcursor];
                [view _clearSelection];
                [view _smartAutoScrollTo:candidateLine];
                TERMINAL_FIELD_SET_FLAGS(view,
                    (TERMINAL_FIELD_FLAGS(view) & 0xF9FFFFFFu) |
                    0x02000000u);
                view->selPt0.line = candidateLine;
                view->selPt0.col = candidateColumn;
                view->selPt1.line = endLine;
                view->selPt1.col = endColumn;
                [view _highlightsel:view->topline
                                  to:view->topline + view->cursorx
                               isLit:1];
                [view reflectPosition];
                [[view delegate] findPanel];
                found = 1;
            }
            break;
        }

        seekPos(candidateLine, (unsigned char)candidateColumn);
        if (!backwards)
            nextGetChar();
    }

    NSZoneFree([view zone], pattern);
    return found;
}

@implementation FieldView (FieldDraw)

- (void)drawRect:(NSRect)dirtyRect
{
    NSRect bounds;

    if (dirtyRect.size.height < 0.0f)
        return;

    [self setBoundsOrigin:NSMakePoint(-3.0f, -3.0f)];
    [backColor[0] set];
    bounds = [self bounds];
    NSRectFill(bounds);
    [self _srhclear:topline to:topline + cursorx];
    if (invalidated)
        [self _cursor];
    [self reflectPosition];

    if (drawsLineAtRightEdge) {
        bounds = [self bounds];
        bounds.origin.x = floor(bounds.size.width) - 4.0;
        bounds.size.width = 1.0f;
        PSsetgray(NSBlack);
        NSRectFill(bounds);
    }
}
@end

@implementation FieldView (FieldMouseScroll)

- (void)mouseDown:(id)event
{
    NSPoint point;
    NSWindow *window;
    id nextEvent;
    NSTimer *hackTimer;
    unsigned int line;
    unsigned int column;
    unsigned int clickCount;
    unsigned int modifiers;
    unsigned int flags;

    hackTimer = nil;
    point = [event locationInWindow];
    hackPoint = [self convertPoint:point fromView:nil];
    clickCount = (unsigned int)[event clickCount];
    if (clickCount > 1u)
        hackPoint.x -= (float)(bwidth >> 1);

    [self _point:&hackPoint toPosition:&line :&column];
    if (line < topline || line >= topline + cursorx)
        return;

    [self _clearcursor];
    flags = TERMINAL_FIELD_FLAGS(self);
    modifiers = (unsigned int)[event modifierFlags];
    if ((flags & 0x06000000u) != 0 &&
        (modifiers & (0x00020000u | 0x00080000u)) != 0) {
        [self _shiftClick:line :(unsigned char)column];
    } else {
        [self _clearSelection];
        if (clickCount == 1u)
            [self _singleClick:line :column];
        else if (clickCount == 2u)
            [self _doubleClick:line :(unsigned char)column];
        else
            [self _tripleClick:line :(unsigned char)column];
    }

    window = [self window];
    [window flushWindow];
    PSWait();
    nextEvent = [window nextEventMatchingMask:68u];
    while (nextEvent == nil || [nextEvent type] != 2) {
        point = [nextEvent locationInWindow];
        hackPoint = [self convertPoint:point fromView:nil];
        [self _point:&hackPoint toPosition:&line :&column];
        [self _autoScrollTo:line];
        [self _drag:line :(unsigned char)column];

        window = [self window];
        [window flushWindow];
        PSWait();

        if (hackPoint.y < 0.0f ||
            hackPoint.y >= (float)((unsigned int)bheight * cursorx)) {
            if (hackTimer == nil) {
                hackTimer = [[NSTimer timerWithTimeInterval:0.1
                    target:self selector:@selector(hackRoutine:)
                    userInfo:self repeats:YES] retain];
                [[NSRunLoop currentRunLoop]
                    addTimer:hackTimer forMode:NSDefaultRunLoopMode];
                [[NSRunLoop currentRunLoop]
                    addTimer:hackTimer forMode:NSModalPanelRunLoopMode];
                [[NSRunLoop currentRunLoop]
                    addTimer:hackTimer forMode:NSEventTrackingRunLoopMode];
            }
        }

        nextEvent = [window nextEventMatchingMask:68u];
        if (hackTimer != nil) {
            [hackTimer invalidate];
            [hackTimer release];
            hackTimer = nil;
        }
    }

    if (invalidated) {
        [self _cursor];
        window = [self window];
        [window flushWindow];
        PSWait();
    }
    [self _clearcursor];
}

- (void)_autoScrollTo:(unsigned int)line
{
    unsigned int flags;
    unsigned int wasDisabled;

    flags = TERMINAL_FIELD_FLAGS(self);
    wasDisabled = flags & 0x00008000u;
    TERMINAL_FIELD_SET_FLAGS(self, flags & 0xFFFF7FFFu);

    if (line >= topline) {
        if (line >= topline + cursorx)
            [self _scrollTo:line - cursorx + 1u];
    } else {
        [self _scrollTo:line];
    }

    flags = TERMINAL_FIELD_FLAGS(self) & 0xFFFF7FFFu;
    if (wasDisabled != 0)
        flags |= 0x00008000u;
    TERMINAL_FIELD_SET_FLAGS(self, flags);
    [self reflectPosition];
}

- (FieldView *)_smartAutoScrollTo:(unsigned int)line
{
    unsigned int inset;
    unsigned int visibleEnd;
    unsigned int target;

    inset = cursorx >> 3;
    visibleEnd = topline + cursorx;
    if (line < topline + inset || line >= visibleEnd - inset) {
        target = line - cursorx / 3u;
        if ((int32_t)target < 0)
            target = 0;
        [self _scrollTo:target];
    }
    [self reflectPosition];
    return self;
}

- (void)_point:(NSPoint *)point toPosition:(unsigned int *)line
               :(unsigned int *)column
{
    float x;
    float y;
    float maximumX;
    float horizontal;
    float vertical;
    float visibleHeight;
    float maximumLine;

    x = point->x;
    y = point->y;
    if (x < 0.0f)
        x = 0.0f;
    maximumX = (float)((unsigned int)bwidth * (unsigned int)height);
    if (x > maximumX)
        x = maximumX;
    horizontal = (x + (float)(bwidth >> 1)) / (float)bwidth;
    *column = (unsigned int)horizontal;

    if (y < 0.0f) {
        vertical = -y / 2.0f;
        if (vertical > (float)topline) {
            *line = 0;
            return;
        }
        *line = (unsigned int)((float)topline + y / 2.0f);
        return;
    }

    visibleHeight = (float)((unsigned int)bheight * (unsigned int)cursorx);
    if (y > visibleHeight) {
        vertical = (float)topline + (float)cursorx +
                   (y - visibleHeight) / 2.0f;
        maximumLine = (float)lines->count;
        if (vertical >= maximumLine) {
            *line = lines->count - 1u;
            *column = height;
        } else {
            *line = (unsigned int)vertical;
        }
        return;
    }

    vertical = (float)topline + y / (float)bheight;
    *line = (unsigned int)vertical;
}

- (void)findPrevWord:(unsigned int)line :(unsigned int)column
                   :(TerminalSelectionPoint *)result
{
    TerminalLine *row;
    unsigned int nextColumn;
    int character;

    for (;;) {
        row = terminalLineAt(lines, line);
        nextColumn = prevWord(row, column);
        if (nextColumn != 0)
            break;

        character = charAt(row, 0);
        if (!iswordchar(character) || line == 0 ||
            !terminalLineIsWrapped(lines, line - 1u))
            break;

        row = terminalLineAt(lines, line - 1u);
        character = charAt(row, height - 1u);
        if (!iswordchar(character))
            break;

        --line;
        column = height - 1u;
    }

    result->line = line;
    result->col = (unsigned char)nextColumn;
}

- (void)findNextWord:(unsigned int)line :(unsigned int)column
                   :(TerminalSelectionPoint *)result
{
    TerminalLine *row;
    int character;
    unsigned int nextColumn;

    row = terminalLineAt(lines, line);
    nextColumn = nextWord(row, column);
    while (nextColumn == height && terminalLineIsWrapped(lines, line)) {
        character = charAt(row, height - 1u);
        if (!iswordchar(character))
            break;

        row = terminalLineAt(lines, line + 1u);
        character = charAt(row, 0);
        if (!iswordchar(character))
            break;

        ++line;
        nextColumn = nextWord(row, 0);
        if (nextColumn != height)
            break;
    }
    if (nextColumn == 0)
        nextColumn = height;

    result->line = line;
    result->col = (unsigned char)nextColumn;
}

- (char)findMatchingDelimiter:(unsigned int)line
                            :(unsigned int)column
                    :(TerminalSelectionPoint *)result
                 delimChars:(const char *)delimiters
                  backwards:(char)backwards
{
    TerminalDelimiterPoint match;

    if (!delimiters || !*delimiters || !result ||
        line >= lines->count)
        return 0;
    if (!terminalFindMatchingDelimiter(lines, line, (unsigned char)column,
                                       height, delimiters, backwards, &match))
        return 0;
    result->line = match.line;
    result->col = match.col;
    return 1;
}

- (char)find:(const char *)text
{
    return fieldFind(self, text, 0);
}

- (char)bfind:(const char *)text
{
    return fieldFind(self, text, 1);
}

- (void)copy:(id)sender
{
    id requestor;
    id pasteboard;
    id types;

    (void)sender;
    requestor = [self validRequestorForSendType:NSStringPboardType
                                      returnType:nil];
    if (requestor == nil)
        return;

    pasteboard = [NSPasteboard pasteboardWithName:NSGeneralPboard];
    types = [NSPasteboard typesFilterableTo:NSStringPboardType];
    [pasteboard declareTypes:types owner:self];
    [self writeSelectionToPasteboard:pasteboard types:types];
}

- (id)validRequestorForSendType:(id)sendType returnType:(id)returnType
{
    if (sendType != nil &&
        [sendType isEqualToString:NSStringPboardType] &&
        (TERMINAL_FIELD_FLAGS(self) & 0x06000000u) != 0 &&
        (selPt1.line != selPt0.line || selPt1.col != selPt0.col))
        return self;
    return nil;
}

- (BOOL)writeSelectionToPasteboard:(id)pasteboard types:(id)types
{
    id typeEnumerator;
    id type;
    id selectionStream;
    id selectionString;
    unsigned int length;

    typeEnumerator = [types objectEnumerator];
    for (;;) {
        type = [typeEnumerator nextObject];
        if (type == nil)
            return 0;
        if ([type isEqualToString:NSStringPboardType]) {
            selectionStream = [self selStream];
            if (selectionStream != nil)
                break;
        }
    }

    length = (unsigned int)[selectionStream length];
    selectionString = [NSString stringWithCString:[self selStr]
                                           length:length];
    [pasteboard setString:selectionString forType:NSStringPboardType];
    [pasteboard setData:selectionStream forType:NSRTFPboardType];
    return 1;
}

- (void)selectAll:(id)sender
{
    unsigned int flags;
    NSWindow *window;

    (void)sender;
    [self lockFocus];
    [self _clearSelection];

    flags = TERMINAL_FIELD_FLAGS(self);
    flags = (flags & 0xF9FFFFFFu) | 0x02000000u;
    TERMINAL_FIELD_SET_FLAGS(self, flags);
    selPt0.line = 0;
    selPt0.col = 0;
    selPt1.col = height;
    selPt1.line = lines->count - 1u;

    [self _highlightsel:topline to:topline + cursorx isLit:1];
    [self unlockFocus];
    window = [self window];
    [window flushWindow];
}

- (void)clearScrollback:(id)sender
{
    unsigned int screenStart;
    unsigned int firstVisible;
    unsigned int lastVisible;
    unsigned int row;
    unsigned int oldCount;
    unsigned int cursorOffset;
    TerminalChunk *rows;
    NSWindow *window;
    NSView *contentView;

    (void)sender;
    /* The PPC call leaves sender in an unused argument register. */
    [self lockFocus];
    [self _clearSelection];

    window = [self window];
    [window disableFlushWindow];

    rows = lines;
    oldCount = rows->count;
    screenStart = oldCount - cursorx;
    cursorOffset = _cursory;
    [self scrollTo:screenStart];
    window = [self window];
    contentView = [window contentView];
    [contentView setNeedsDisplay:YES];
    window = [self window];
    [window enableFlushWindow];

    if (!terminalClearScrollbackRange(rows->elements + 4, 8, oldCount,
                                     cursorx, cursorOffset,
                                     &firstVisible, &lastVisible))
        goto finish;

    for (row = 0; row < firstVisible; ++row)
        lineFree(terminalLineAt(rows, row));

    {
        unsigned int destination = 0;

        for (row = firstVisible; row <= lastVisible; ++row) {
            terminalLineSet(rows, destination,
                            terminalLineAt(rows, row));
            terminalLineSetWrapped(rows, destination,
                                   terminalLineIsWrapped(rows, row));
            ++destination;
        }
    }

    for (row = lastVisible - firstVisible + 1u;
         row <= lastVisible; ++row) {
        terminalLineSet(rows, row, NULL);
        terminalLineSetWrapped(rows, row, 0);
    }

    for (row = lastVisible + 1u; row < oldCount; ++row)
        lineFree(terminalLineAt(rows, row));

    for (row = lastVisible + 1u; row < cursorx; ++row) {
        terminalLineSet(rows, row, NULL);
        terminalLineSetWrapped(rows, row, 0);
    }

    rows->count = cursorx;
    topline = 0;
    _cursory = (unsigned char)(cursorOffset + screenStart - firstVisible);

finish:
    [self display];
    [self reflectPosition];
    [self unlockFocus];
}

@end
