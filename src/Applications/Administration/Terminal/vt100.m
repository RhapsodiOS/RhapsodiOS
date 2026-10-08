#import "Emulation.h"
#import "Terminal.h"
#import <AppKit/NSApplication.h>
#import <objc/objc-runtime.h>
#include <stdio.h>
#include <string.h>

@implementation vt100

- (id)initDefaults:(const TerminalEmulationDefaults *)defaults
{
    [super initDefaults:defaults];
    vt52Emulator = [[vt52 allocWithZone:[self zone]] initDefaults:defaults];
    [vt52Emulator setTerminal:(Terminal *)self];
    tabs = ChunkMalloc(1, 0x40, 0, 0x50, [self zone]);
    text = ChunkMalloc(1, 0x20, 0, 0x10, [self zone]);
    args = ChunkMalloc(2, 0x40, 0, 1, [self zone]);
    [self setDefaults:defaults];
    return self;
}

- (void)setTerminal:(Terminal *)value
{
    [super setTerminal:value];
    [vt52Emulator setTerminal:term];
}

- (void)dealloc
{
    free(text);
    free(tabs);
    free(args);
    [vt52Emulator release];
    [super dealloc];
}

- (void)setDefaults:(const TerminalEmulationDefaults *)defaults
{
    vflags &= ~0x40000000u;
    vflags = (vflags & ~0x04000000u) |
             (((unsigned int)(unsigned char)defaults->var5 << 26) &
              0x04000000u);
    vflags = (vflags & ~0x10000000u) |
             (((unsigned int)(unsigned char)defaults->var5 << 28) &
              0x10000000u);
    [vt52Emulator setDefaults:defaults];
    [super setDefaults:defaults];
}

- (void)termDidResize:(id)sender
{
    unsigned char defaultTabs[256];
    unsigned int columns;

    memset(defaultTabs, 0xFF, sizeof(defaultTabs));
    columns = term->height;
    if (columns > tabs->allocated)
        tabs = ChunkGrow(tabs, columns);
    else
        tabs->count = columns;
    memcpy(tabs->elements, defaultTabs, columns);
    [super termDidResize:sender];
}

- (void)wrapoutput
{
    unsigned int row;

    if ((eflags & 0x10000000u) != 0) {
        [term _clearcursor];
        if (term->_cursory == (unsigned char)(term->drawCursOK - 1))
            [term _lscrollup:1];
        else {
            row = (unsigned int)term->_cursory + 1u;
            if (row >= term->cursorx)
                row = (unsigned int)term->cursorx - 1u;
            term->_cursory = (unsigned char)row;
        }
        term->cursory = 0;
    } else {
        --term->cursory;
    }
}

- (void)linefeed
{
    int nextRow;

    if ((int)term->_cursory == (int)(unsigned char)term->drawCursOK - 1) {
        [term _lscrollup:1];
        return;
    }

    nextRow = term->_cursory + 1;
    if (nextRow > (int)term->cursorx - 1)
        nextRow = (int)term->cursorx - 1;
    term->_cursory = (unsigned char)nextRow;
}

- (void)revlinefeed
{
    int previousRow;

    if (term->_cursory == term->bot) {
        [term _lscrolldown:term->_cursory to:term->drawCursOK lines:1];
        return;
    }

    previousRow = term->_cursory - 1;
    term->_cursory = (unsigned char)(previousRow >= 0 ? previousRow : 0);
}

- (void)reset
{
    unsigned int row;
    unsigned int height;
    unsigned int flags;

    height = term->height;
    [term refreshscreen];
    for (row = 0; row < height; ++row)
        tabs->elements[row] = (unsigned char)((row & 7u) == 0);

    eflags = (eflags & 0xEC7FFFFFu) | 0x10000000u;
    vflags &= 0x1400FFFFu;
    term->bot = 0;
    term->drawCursOK = term->cursorx;
    term->_cursory = 0;
    term->cursory = 0;
    flags = TERMINAL_FIELD_FLAGS(term) & 0x0FFF7FFFu;
    TERMINAL_FIELD_SET_FLAGS(term, flags);
    [term _sclear:0 to:term->cursorx];
}

- (void)ctrloutput:(unsigned char)value
{
    unsigned int column;

    if ((eflags & 0x00800000u) != 0) {
        ((id (*)(id, SEL, unsigned char))objc_msgSend)(self, (SEL)writer,
                                                        value);
        return;
    }

    if (value > 27u) {
        if ((eflags & 0x01000000u) != 0)
            ((id (*)(id, SEL, unsigned char))objc_msgSend)(self, (SEL)writer,
                                                            value);
        return;
    }

    switch (value) {
    case 7:
        NSBeep();
        break;
    case 8:
        if (term->cursory != 0) {
            --term->cursory;
        } else if ((eflags & 0x01800000u) == 0x01800000u &&
                   term->_cursory != 0) {
            term->cursory = (unsigned char)(term->height - 1u);
            --term->_cursory;
        }
        break;
    case 9:
        column = term->cursory;
        do {
            ++column;
        } while (column < term->height && tabs->elements[column] == 0);
        if (column >= term->height)
            column = (unsigned int)term->height - 1u;
        term->cursory = (unsigned char)column;
        break;
    case 10:
    case 11:
    case 12:
        if ((int)term->_cursory == (int)(unsigned char)term->drawCursOK - 1)
            [term _lscrollup:1];
        else {
            column = (unsigned int)term->_cursory + 1u;
            if (column >= term->cursorx)
                column = (unsigned int)term->cursorx - 1u;
            term->_cursory = (unsigned char)column;
        }
        if ((eflags & 0x02000000u) != 0)
            term->cursory = 0;
        break;
    case 13:
        term->cursory = 0;
        break;
    case 14:
        vflags |= 0x00800000u;
        break;
    case 15:
        vflags &= ~0x00800000u;
        break;
    case 24:
    case 26:
        eflags &= ~0x01000000u;
        break;
    case 27:
        eflags |= 0x01000000u;
        writer = @selector(vt100Escape:);
        break;
    default:
        break;
    }
}

- (void)vt100Escape:(unsigned char)value
{
    unsigned int flags;
    unsigned int style;
    unsigned int column;
    unsigned int row;

    switch (value) {
    case '#': writer = @selector(vt100Hash:); return;
    case '(': writer = @selector(vt100CharsetG0:); return;
    case ')': writer = @selector(vt100CharsetG1:); return;
    case 'D':
        if ((int)term->_cursory ==
            (int)(unsigned char)term->drawCursOK - 1) {
            [term _lscrollup:(unsigned char)term->bot
                          to:(unsigned char)term->drawCursOK
                       lines:1];
        } else {
            row = (unsigned int)term->_cursory + 1u;
            if (row >= term->cursorx)
                row = (unsigned int)term->cursorx - 1u;
            term->_cursory = (unsigned char)row;
        }
        break;
    case 'E':
        term->cursory = 0;
        if ((int)term->_cursory ==
            (int)(unsigned char)term->drawCursOK - 1) {
            [term _lscrollup:(unsigned char)term->bot
                          to:(unsigned char)term->drawCursOK
                       lines:1];
        } else {
            row = (unsigned int)term->_cursory + 1u;
            if (row >= term->cursorx)
                row = (unsigned int)term->cursorx - 1u;
            term->_cursory = (unsigned char)row;
        }
        break;
    case 'H':
        column = term->cursory;
        if (column < tabs->allocated)
            tabs->elements[column] = 1;
        break;
    case 'M':
        [self revlinefeed];
        break;
    case '[':
        writer = @selector(vt100CSI:);
        return;
    case ']':
        writer = @selector(vt100string:);
        return;
    case 'c':
        [self reset];
        break;
    case '=':
        vflags |= 0x40000000u;
        break;
    case '>':
        vflags &= ~0x40000000u;
        break;
    case 'Z':
        [term output:"\033[?1;2c" len:7];
        break;
    case '7':
        flags = vflags;
        flags = (flags & ~0x00070000u) |
                ((flags & 0x03800000u) >> 3);
        flags = (flags & ~0x000F0000u) |
                ((TERMINAL_FIELD_FLAGS(term) >> 12) & 0x000F0000u);
        vflags = flags;
        sx = term->cursory;
        sy = term->_cursory;
        break;
    case '8':
        flags = vflags;
        flags = (flags & ~0x03800000u) |
                ((flags & 0x00070000u) << 3);
        vflags = flags;
        style = (vflags >> 16) & 0xFu;
        TERMINAL_FIELD_SET_FLAGS(term,
            (TERMINAL_FIELD_FLAGS(term) & 0x0FFFFFFFu) | (style << 28));
        term->cursory = sx;
        term->_cursory = sy;
        break;
    default:
        break;
    }

    eflags &= ~0x01000000u;
}

- (void)vt100CharsetG0:(unsigned char)value
{
    if (value == '0' || value == '2')
        vflags |= 0x02000000u;
    else if (value == '1' || value == 'A' || value == 'B')
        vflags &= ~0x02000000u;
    eflags &= ~0x01000000u;
}

- (void)vt100CharsetG1:(unsigned char)value
{
    if (value == '0' || value == '2')
        vflags |= 0x01000000u;
    else if (value == '1' || value == 'A' || value == 'B')
        vflags &= ~0x01000000u;
    eflags &= ~0x01000000u;
}

- (void)vt100Hash:(unsigned char)value
{
    static char alignmentLine[256];
    unsigned char savedColumn;
    unsigned char savedRow;
    unsigned int row;

    if (value == '8') {
        if (alignmentLine[0] == 0)
            memset(alignmentLine, 'E', sizeof(alignmentLine));
        savedColumn = term->cursory;
        savedRow = term->_cursory;
        [term _lclear:0 to:term->cursorx];
        for (row = 0; row < term->cursorx; ++row) {
            term->cursory = 0;
            term->_cursory = (unsigned char)row;
            [term _mark:alignmentLine len:term->height];
        }
        term->_cursory = savedRow;
        term->cursory = savedColumn;
    }
    eflags &= ~0x01000000u;
}

- (void)vt100CSI:(unsigned char)value
{
    writer = @selector(vt100DoCSI:);
    args->count = 1;
    ((unsigned short *)args->elements)[0] = 0;
    narg = 0;
    vflags = (vflags & ~0x08000000u) |
             (value == '?' ? 0x08000000u : 0);
    if (value != '?')
        [self vt100DoCSI:value];
}

- (void)vt100Private:(unsigned char)value
{
    unsigned int mode;
    unsigned int enabled;

    if (value != 'h' && value != 'l') {
        eflags &= ~0x01000000u;
        return;
    }

    enabled = (unsigned int)(value == 'h');
    while (narg < args->count) {
        mode = ((unsigned short *)args->elements)[narg];
        ++narg;
        if (mode == 0 || mode > 20)
            continue;

        switch (mode) {
        case 1:
            vflags = (vflags & ~0x20000000u) | (enabled << 29);
            break;
        case 2:
            if (!enabled) {
                [term refreshscreen];
                [term setEmulator:vt52Emulator];
                [vt52Emulator reset];
            }
            break;
        case 3:
            if (enabled) {
                if ((vflags & 0x04000000u) != 0 || term->height <= 0x83u)
                    [term sizeEmulationTo:132 :term->cursorx];
            } else if ((vflags & 0x04000000u) != 0 || term->height <= 0x4Fu) {
                [term sizeEmulationTo:80 :term->cursorx];
            }
            break;
        case 4:
            TERMINAL_FIELD_SET_FLAGS(
                term,
                (TERMINAL_FIELD_FLAGS(term) & ~0x00008000u) |
                    (enabled << 15));
            break;
        case 5:
            break;
        case 6:
            vflags = (vflags & ~0x80000000u) | (enabled << 31);
            break;
        case 7:
            eflags = (eflags & ~0x10000000u) | (enabled << 28);
            break;
        case 8:
            eflags = (eflags & ~0x20000000u) | (enabled << 29);
            break;
        case 20:
            eflags = (eflags & ~0x02000000u) | (enabled << 25);
            break;
        default:
            break;
        }
    }

    eflags &= ~0x01000000u;
}

- (void)_insertline:(unsigned int)count
{
    unsigned int limit;

    if (count == 0)
        count = 1;
    limit = (unsigned int)term->drawCursOK - term->bot;
    if (count >= limit)
        count = limit;
    if (term->_cursory >= term->bot &&
        term->_cursory < term->drawCursOK)
        [term _lscrolldown:term->_cursory to:term->drawCursOK lines:count];
}

- (void)_deleteline:(unsigned int)count
{
    unsigned int limit;

    if (count == 0)
        count = 1;
    limit = (unsigned int)term->drawCursOK - term->bot;
    if (count >= limit)
        count = limit;
    if (term->_cursory >= term->bot &&
        term->_cursory < term->drawCursOK)
        [term _lscrollup:term->_cursory to:term->drawCursOK lines:count];
}

- (void)_deletechar:(unsigned int)count
{
    if (count == 0)
        count = 1;
    [term _bdelete:term->_cursory :term->cursory bytes:count];
}

- (void)vt100DoCSI:(unsigned char)value
{
    unsigned int count;
    unsigned int argument;
    unsigned int firstParameter;
    unsigned int secondParameter;
    unsigned int nextArgument;
    int boundary;
    int topRow;
    int bottomRow;

    argument = 0;
    if (narg < args->count) {
        argument = ((unsigned short *)args->elements)[narg];
        ++narg;
    }
    count = argument;
    if (count == 0)
        count = 1;

    switch (value) {
    case 'A':
        while (count-- != 0) {
            if (term->_cursory < term->bot || term->_cursory == 0)
                continue;
            --term->_cursory;
        }
        break;
    case 'B':
        while (count-- != 0) {
            boundary = (int)term->drawCursOK - 1;
            if ((int)term->_cursory > boundary ||
                (int)term->_cursory == (int)term->cursorx - 1)
                break;
            ++term->_cursory;
        }
        break;
    case 'C':
        while (count-- != 0) {
            boundary = (int)term->height - 1;
            if ((int)term->cursory > boundary)
                break;
            ++term->cursory;
        }
        break;
    case 'D':
        while (count-- != 0) {
            if (term->cursory == 0)
                break;
            --term->cursory;
        }
        break;
    case 'J':
        if (argument == 0) {
            [term _lclear:(unsigned int)term->_cursory + 1
                        to:term->cursorx];
            [term _bclear:term->_cursory from:term->cursory];
        } else if (argument == 1) {
            [term _lclear:0 to:term->_cursory];
            [term _bclear:term->_cursory to:term->cursory];
        } else if (argument == 2) {
            [term _lclear:0 to:term->cursorx];
        }
        break;
    case 'K':
        if (argument == 0)
            [term _bclear:term->_cursory from:term->cursory];
        else if (argument == 1)
            [term _bclear:term->_cursory to:term->cursory];
        else if (argument == 2)
            [term _lclear:term->_cursory
                       to:(unsigned int)term->_cursory + 1];
        break;
    case 'm':
        for (;;) {
            switch (argument) {
            case 0:
                term->aflags.bytes[0] &= 0x0Fu;
                break;
            case 1:
                term->aflags.bytes[0] |= 0x20u;
                break;
            case 4:
                term->aflags.bytes[0] |= 0x40u;
                break;
            case 5:
                term->aflags.bytes[0] |= 0x80u;
                break;
            case 7:
                term->aflags.bytes[0] |= 0x10u;
                break;
            case 22:
                term->aflags.bytes[0] &= 0xDFu;
                break;
            case 24:
                term->aflags.bytes[0] &= 0xBFu;
                break;
            case 25:
                term->aflags.bytes[0] &= 0x7Fu;
                break;
            case 27:
                term->aflags.bytes[0] &= 0xEFu;
                break;
            default:
                break;
            }
            if (narg >= args->count)
                break;
            argument = ((unsigned short *)args->elements)[narg++];
        }
        break;
    case 'c':
        [term output:"\033[?1;2c" len:7];
        break;
    case 'n':
        if (argument == 5) {
            [term output:"\033[0n" len:4];
        } else if (argument == 6) {
            char response[24];
            int row;
            int length;

            row = term->_cursory;
            if ((vflags & 0x80000000u) != 0)
                row -= term->bot;
            length = sprintf(response, "\033[%d;%dR", row + 1,
                             (int)term->cursory + 1);
            [term output:response len:(unsigned int)length];
        }
        break;
    case 'H':
    case 'f':
        if (narg < args->count)
            nextArgument = ((unsigned short *)args->elements)[narg++];
        else
            nextArgument = 0;
        if (nextArgument == 0)
            nextArgument = 1;
        boundary = (int)count - 1;
        if ((vflags & 0x80000000u) != 0) {
            boundary += term->bot;
            if (boundary >= term->drawCursOK)
                boundary = (int)term->drawCursOK - 1;
        } else if (boundary >= term->cursorx) {
            boundary = (int)term->cursorx - 1;
        }
        term->_cursory = (unsigned char)boundary;
        boundary = (int)nextArgument - 1;
        if (boundary >= term->height)
            boundary = (int)term->height - 1;
        term->cursory = (unsigned char)boundary;
        break;
    case 'L':
    case 'M':
    case 'P':
        if (args->count != 0) {
            if (value == 'L')
                [self _insertline:argument];
            else if (value == 'M')
                [self _deleteline:argument];
            else
                [self _deletechar:argument];
        }
        while (narg < args->count) {
            nextArgument = ((unsigned short *)args->elements)[narg++];
            if (value == 'L')
                [self _insertline:nextArgument];
            else if (value == 'M')
                [self _deleteline:nextArgument];
            else
                [self _deletechar:nextArgument];
        }
        break;
    case 'g':
        if (argument == 3) {
            memset(tabs->elements, 0, term->height);
        } else if (argument == 0 && term->cursory < tabs->allocated) {
            tabs->elements[term->cursory] = 0;
        }
        break;
    case 'r':
        if (narg < args->count)
            secondParameter = ((unsigned short *)args->elements)[narg++];
        else
            secondParameter = 0;
        firstParameter = argument;
        [term refreshscreen];
        if (firstParameter == 0 && secondParameter == 0) {
            firstParameter = 1;
            secondParameter = term->cursorx;
        } else if (firstParameter == 1 && secondParameter == 24 &&
                   (vflags & 0x04000000u) == 0) {
            secondParameter = term->cursorx;
        }
        if (firstParameter == 0)
            firstParameter = 1;
        if (secondParameter == 0)
            secondParameter = 1;
        topRow = (int)firstParameter - 1;
        bottomRow = (int)secondParameter - 1;
        if (bottomRow >= term->cursorx)
            bottomRow = (int)term->cursorx - 1;
        if (bottomRow < topRow)
            bottomRow = topRow;
        term->bot = (unsigned char)topRow;
        term->drawCursOK = (char)(bottomRow + 1);
        term->_cursory = (vflags & 0x80000000u) != 0 ?
                         term->bot : 0;
        term->cursory = 0;
        break;
    default:
        break;
    }

    eflags &= ~0x01000000u;
}

- (void)vt100CollectArgs:(unsigned char)value
{
    unsigned int current;

    if (value >= '0' && value <= '9') {
        current = args->count - 1;
        ((unsigned short *)args->elements)[current] =
            (unsigned short)(((unsigned int)((unsigned short *)args->elements)[current] * 10u) +
                             (unsigned int)(value - '0'));
        return;
    }

    if (value == ';') {
        current = args->count;
        ++args->count;
        if (current == args->allocated)
            args = ChunkRealloc(args);
        ((unsigned short *)args->elements)[args->count - 1] = 0;
        return;
    }

    if ((vflags & 0x08000000u) != 0)
        [self vt100Private:value];
    else
        [self vt100DoCSI:value];
}

- (void)vt100CollectString:(unsigned char)value
{
    unsigned int length;
    char *string;

    length = text->count;
    ++text->count;
    text->elements[length] = value;
    if (text->count == text->allocated)
        text = ChunkRealloc(text);

    if (value > 0x1Fu && text->count <= 0x400u)
        return;

    text->elements[text->count - 1] = 0;
    string = (char *)text->elements;
    if (text->count > 0x51u) {
        string += text->count - 0x51u;
        string[0] = '.';
        string[1] = '.';
        string[2] = '.';
    }
    [term pasteText:string];
    eflags &= 0xFE7FFFFFu;
}

- (id)vt100string:(unsigned char)value
{
    if (value >= '0' && value <= '2')
        return self;

    if (value == ';') {
        writer = @selector(vt100CollectString:);
        text->count = 0;
        eflags |= 0x00800000u;
    } else {
        eflags &= 0xFE7FFFFFu;
    }
    return self;
}

- (void)translateChars:(char *)bytes len:(unsigned int)length
{
    unsigned int index;
    unsigned char value;

    if ((vflags & 0x01800000u) != 0x01800000u &&
        (vflags & 0x02800000u) != 0x02000000u)
        return;

    for (index = 0; index < length; ++index) {
        value = (unsigned char)bytes[index];
        switch (value) {
        case '\\': bytes[index] = '+'; break;
        case '_': bytes[index] = ' '; break;
        case 'a': bytes[index] = '*'; break;
        case 'f': bytes[index] = 'o'; break;
        case 'g':
        case 'j': case 'k': case 'l': case 'm': case 'n':
        case 't': case 'u': case 'v': case 'w':
            bytes[index] = '+';
            break;
        case 'o': bytes[index] = (char)0xC5; break;
        case 'p': case 'q': bytes[index] = '-'; break;
        case 'r':
        case 's': bytes[index] = '#'; break;
        case 'x': bytes[index] = '|'; break;
        case '|': bytes[index] = '_'; break;
        case '}': bytes[index] = (char)0xA3; break;
        case '~': bytes[index] = (char)0xB7; break;
        default: break;
        }
    }
}

- (int)key:(id)event
{
    static const unsigned char specialKeyMap[4] = { 'A', 'B', 'C', 'D' };
    static const char applicationKeyPrefix[] = "\033O";
    static const char applicationKeyEnter[] = "\033OM";
    static const char applicationKeyPlus[] = "\033Ol";
    static const char applicationKeyMinus[] = "\033Om";
    static const char applicationKeyPeriod[] = "\033On";
    int disposition;
    signed char value;
    unsigned short special;

    disposition = [super key:event];
    if (disposition == 0 || disposition == 1)
        return disposition;

    if (disposition == 3) {
        special = (unsigned short)[[event characters] characterAtIndex:0];
        [term outputChar:27];
        [term outputChar:(vflags & 0x20000000u) != 0 ? 'O' : '['];
        [term outputChar:specialKeyMap[(unsigned short)(special - 0xF700u)]];
        return 1;
    }

    if (disposition != 2)
        return 1;

    value = (signed char)[event charValue];
    if ((vflags & 0x40000000u) != 0) {
        if (value == 3) {
            [term pasteText:applicationKeyEnter];
            return 1;
        }
        if (value == '+') {
            [term pasteText:applicationKeyPlus];
            return 1;
        }
        if (value == '-') {
            [term pasteText:applicationKeyMinus];
            return 1;
        }
        if (value == '.') {
            [term pasteText:applicationKeyPeriod];
            return 1;
        }
        if (value >= '1' && value <= '4') {
            [term pasteText:applicationKeyPrefix];
            if (((unsigned int)[event modifierFlags] & 0x00020000u) != 0)
                [term outputChar:(unsigned char)(value + 0x1F)];
            else
                [term outputChar:(unsigned char)(value + 0x40)];
            return 1;
        }
        if (value == '0' || (value >= '5' && value <= '9')) {
            [term pasteText:applicationKeyPrefix];
            [term outputChar:(unsigned char)(value + 0x40)];
            return 1;
        }
        return 0;
    }

    if (value == '+') {
        [term outputChar:(vflags & 0x10000000u) != 0 ? ',' : '+'];
        return 1;
    }
    if (value == 3) {
        if ((eflags & 0x02000000u) != 0) {
            [term outputChar:13];
            [event setChar:10];
        } else {
            [event setChar:13];
        }
        return 0;
    }
    if (value >= '1' && value <= '4') {
        [term pasteText:applicationKeyPrefix];
        [term outputChar:(unsigned char)(value + 0x1F)];
        return 1;
    }
    return 0;
}

@end
