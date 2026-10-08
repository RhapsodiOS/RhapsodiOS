#import "Emulation.h"
#import "Terminal.h"
#import <AppKit/NSApplication.h>
#import <objc/objc-runtime.h>

@implementation vt52

- (void)vt100Emulator:(id)value
{
    vt100Emulator = value;
}

- (id)initDefaults:(const TerminalEmulationDefaults *)defaults
{
    [self setDefaults:defaults];
    return self;
}

- (void)setDefaults:(const TerminalEmulationDefaults *)defaults
{
    vt52flags = (unsigned char)((vt52flags & 0x3Fu) |
                                (((unsigned char)defaults->var5 << 6) &
                                 0x40u));
    [super setDefaults:defaults];
}

- (void)translateChars:(char *)bytes len:(unsigned int)length
{
    unsigned int i;
    unsigned char value;

    if ((vt52flags & 0x20u) == 0)
        return;

    for (i = 0; i < length; ++i) {
        value = (unsigned char)bytes[i];
        switch (value) {
        case '\\': bytes[i] = '+'; break;
        case '_': bytes[i] = ' '; break;
        case 'a': bytes[i] = '*'; break;
        case 'f': bytes[i] = 'o'; break;
        case 'g':
        case 'j': case 'k': case 'l': case 'm': case 'n':
        case 't': case 'u': case 'v': case 'w':
            bytes[i] = '+';
            break;
        case 'o': case 'p': case 'q': bytes[i] = '-'; break;
        case 'r': case 's': bytes[i] = '_'; break;
        case 'x': bytes[i] = '|'; break;
        case '|': bytes[i] = '#'; break;
        case '}': bytes[i] = (char)0xA3; break;
        case '~': bytes[i] = (char)0xB7; break;
        default: break;
        }
    }
}

- (void)wrapoutput
{
    --term->cursory;
}

- (int)key:(id)event
{
    static const unsigned char specialKeyMap[4] = { 0, 0, 6, 0x4C };
    static const char appKeyPrefix[] = "\033";
    static const char appKeyMinus[] = "?m";
    static const char appKeyPlus[] = "?l";
    static const char appKeyPeriod[] = "?n";
    static const char appKeyControl[] = "?M";
    static const char keyP[] = "\033P";
    static const char keyQ[] = "\033Q";
    static const char keyR[] = "\033R";
    static const char keyS[] = "\033S";
    int disposition;
    signed char value;
    unsigned short special;

    disposition = [super key:event];
    if (disposition == 0 || disposition == 1)
        return disposition;

    if (disposition == 3) {
        special = (unsigned short)[[event characters] characterAtIndex:0];
        [term outputChar:27];
        [term outputChar:specialKeyMap[(unsigned short)(special - 0xF700u)]];
        return 1;
    }

    if (disposition != 2)
        return 1;

    value = (signed char)[event charValue];
    if ((vt52flags & 0x80u) != 0) {
        [term pasteText:appKeyPrefix];
        if (value == '/')
            [term outputChar:'R'];
        else if (value > '/') {
            if (value == '=')
                [term outputChar:'Q'];
            else if (value > '=') {
                if (value == '`' || value == '~')
                    [term outputChar:'P'];
            } else if (value <= '9') {
                [term outputChar:'?'];
                [term outputChar:(unsigned char)(value + 64)];
            }
        } else if (value == '+')
            [term pasteText:appKeyPlus];
        else if (value > '+') {
            if (value == '-')
                [term pasteText:appKeyMinus];
            else if (value == '.')
                [term pasteText:appKeyPeriod];
        } else if (value == 3)
            [term pasteText:appKeyControl];
        else if (value == '*')
            [term outputChar:'S'];
        return 1;
    }

    if (value == '/')
        [term pasteText:keyR];
    else if (value > '/') {
        if (value == '=')
            [term pasteText:keyQ];
        else if (value > '=') {
            if (value == '`' || value == '~')
                [term pasteText:keyP];
            return 1;
        } else if (value <= '9')
            return 0;
    } else {
        if (value == '+') {
            [term outputChar:(vt52flags & 0x40u) != 0 ? ',' : '+'];
            return 1;
        }
        if (value <= '+') {
            if (value == 3)
                [term outputChar:13];
            else if (value == '*')
                [term pasteText:keyS];
            return 1;
        }
        if (value >= '-')
            return 0;
    }
    return 1;
}

- (void)ctrloutput:(unsigned char)value
{
    switch (value) {
    case 7:
        NSBeep();
        break;
    case 8:
        if (term->cursory != 0)
            --term->cursory;
        break;
    case 9:
        term->cursory = (unsigned char)((term->cursory + 8u) & 0xF8u);
        if (term->cursory > term->height)
            term->cursory = term->height;
        break;
    case 10:
        if (term->_cursory == term->cursorx - 1)
            [term _lscrollup:1];
        else
            ++term->_cursory;
        if ((eflags & 0x02000000u) != 0)
            term->cursory = 0;
        break;
    case 13:
        if ((eflags & 0x02000000u) != 0)
            term->cursory = 0;
        break;
    case 27:
        eflags |= 0x01000000u;
        writer = @selector(vt52Escape:);
        break;
    default:
        break;
    }

    if (value > 27u && (eflags & 0x01000000u) != 0) {
        SEL handler = writer;

        if (handler == @selector(vt52Escape:) ||
            handler == @selector(vt52getline:) ||
            handler == @selector(vt52getcol:)) {
            ((id (*)(id, SEL, char))objc_msgSend)(self, handler,
                                                   (char)value);
        } else if (handler == @selector(lineUp)) {
            [term lineUp];
            eflags &= ~0x01000000u;
        }
    }
}

- (id)vt52getline:(char)value
{
    destinationLine = (unsigned char)(value - 0x20);
    writer = @selector(vt52getcol:);
    return self;
}

- (id)vt52getcol:(char)value
{
    term->cursorx = (unsigned char)(value - 0x20);
    term->cursory = destinationLine;
    eflags &= ~0x01000000u;
    return self;
}

- (id)vt52Escape:(unsigned char)value
{
    switch (value) {
    case 0x3C:
        if (vt100Emulator != nil) {
            [term setEmulator:vt100Emulator];
            [vt100Emulator setTerminal:term];
        }
        break;
    case 0x3D:
        vt52flags |= 0x80u;
        break;
    case 0x3E:
        vt52flags &= (unsigned char)~0x80u;
        break;
    case 0x41:
        if (term->_cursory != 0)
            --term->_cursory;
        break;
    case 0x42:
        if (term->_cursory < (unsigned char)(term->cursorx - 1u))
            ++term->_cursory;
        else
            term->_cursory = (unsigned char)(term->cursorx - 1u);
        break;
    case 0x43:
        if (term->cursory < (unsigned char)(term->height - 1u))
            ++term->cursory;
        else
            term->cursory = (unsigned char)(term->height - 1u);
        break;
    case 0x44:
        if (term->cursory != 0)
            --term->cursory;
        break;
    case 0x46:
        vt52flags |= 0x20u;
        break;
    case 0x47:
        vt52flags &= (unsigned char)~0x20u;
        break;
    case 0x48:
        term->_cursory = 0;
        term->cursory = 0;
        break;
    case 0x49:
        if (term->_cursory != 0)
            --term->_cursory;
        else
            [term _lscrolldown:0 to:term->cursorx lines:1];
        break;
    case 0x4A:
        [term _lclear:(unsigned int)term->_cursory + 1u to:term->cursorx];
        [term _bclear:term->_cursory from:term->cursory];
        break;
    case 0x4B:
        [term _bclear:term->_cursory from:term->cursory];
        break;
    case 0x5A:
        [term output:"\033/Z"];
        break;
    case 0x59:
        writer = @selector(vt52getline:);
        return self;
    default:
        break;
    }

    if (value != 0x59) {
        eflags &= ~0x01000000u;
    }
    return self;
}

- (void)reset
{
    [term _clearcursor];
    eflags &= 0xFCFFFFFFu;
    term->bot = 0;
    term->drawCursOK = term->cursorx;
    term->_cursory = 0;
    term->cursory = 0;
    TERMINAL_FIELD_SET_FLAGS(term, TERMINAL_FIELD_FLAGS(term) & 0x0FFFFFFFu);
    [term _sclear:0 to:term->cursorx];
}

@end
