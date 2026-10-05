#import "Emulation.h"
#import "Terminal.h"
#import <AppKit/NSApplication.h>
#import <objc/objc-runtime.h>

@implementation Emulation

- (void)setTerminal:(Terminal *)value
{
    term = value;
}

- (Terminal *)terminal
{
    return term;
}

- (void)translateChars:(char *)bytes len:(unsigned int)length
{
    (void)bytes;
    (void)length;
}

- (void)ctrloutput:(unsigned char)value
{
    unsigned int column;

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
        column = ((unsigned int)term->cursory + 8u) & 0xF8u;
        if (column >= term->height)
            column = (unsigned int)term->height - 1u;
        term->cursory = (unsigned char)column;
        break;
    case 10:
        if (term->_cursory == term->cursorx - 1u)
            [term _lscrollup:1];
        else
            ++term->_cursory;
        break;
    case 13:
        term->cursory = 0;
        break;
    default:
        break;
    }
}

- (short)metaCharacter
{
    return (short)meta;
}

- (char)autowrapIsOn
{
    return (eflags & 0x10000000u) != 0;
}

- (id)initDefaults:(const TerminalEmulationDefaults *)defaults
{
    [self setDefaults:defaults];
    return self;
}

- (void)setDefaults:(const TerminalEmulationDefaults *)defaults
{
    meta = (unsigned short)(short)defaults->var9;
    eflags = (eflags & 0xBFFFFFFFu) |
             (((unsigned int)(unsigned char)defaults->var2 << 30) &
              0x40000000u) | 0x20000000u;
    eflags = (((unsigned int)(unsigned char)defaults->var1 << 28) &
              0x10000000u) | (eflags & 0xE9FFFFFFu);
    eflags = (defaults->var5 != 1 ? 0x08000000u : 0) |
             (eflags & 0xF7FFFFFFu);
}

- (void)termDidResize:(id)sender
{
    (void)sender;
    term->bot = 0;
    term->drawCursOK = term->cursorx;
}

- (void)wrapoutput
{
    if ([self autowrapIsOn]) {
        [term setWrap];
        if (term->_cursory == term->cursorx - 1u)
            [term _lscrollup:1];
        else
            ++term->_cursory;
        term->cursory = 0;
    }
}

- (void)output:(char *)bytes len:(unsigned int)length
{
    unsigned int remaining;
    unsigned int printable;
    unsigned int run;
    unsigned int available;
    Terminal *currentEmulator;

    remaining = length;
    while (remaining != 0) {
        if ((unsigned char)bytes[0] <= 0x1Fu || (eflags & 0x01000000u) != 0) {
            do {
                ((void (*)(id, SEL, unsigned char))objc_msgSend)(
                    self, @selector(ctrloutput:),
                    (unsigned char)bytes[0]);
                ++bytes;
                --remaining;
            } while (remaining != 0 &&
                     (((eflags & 0x01000000u) != 0) ||
                      ((unsigned char)bytes[0] <= 0x1Fu &&
                       self == [term emulator])));

            currentEmulator = [term emulator];
            if (self != currentEmulator) {
                if (currentEmulator != nil)
                    [currentEmulator output:bytes len:remaining];
                return;
            }
        } else {
            for (printable = 0; printable < remaining; ++printable) {
                if ((unsigned char)bytes[printable] <= 0x1Fu)
                    break;
            }

            while (1) {
                available = term->height - term->cursory;
                if (term->height == term->cursory) {
                    [self wrapoutput];
                    available = term->height - term->cursory;
                    if (term->height == term->cursory)
                        break;
                }

                run = printable < available ? printable : available;
                if (run != 0) {
                    [self translateChars:(char *)bytes len:run];
                    [term output:bytes len:run];
                    bytes += run;
                    remaining -= run;
                    printable -= run;
                    if (printable != 0)
                        continue;
                }
                break;
            }

            if (printable != 0) {
                bytes += printable;
                remaining -= printable;
            }
        }
    }
}

- (int)key:(id)event
{
    id characters;
    unsigned short character;
    unsigned int modifiers;
    signed char keyValue;

    characters = [event characters];
    character = (unsigned short)[characters characterAtIndex:0];
    modifiers = (unsigned int)[event modifierFlags];

    if ((modifiers & 0x00100000u) != 0) {
        NSBeep();
        return 1;
    }

    if ((eflags & 0x20000000u) == 0 && [event isARepeat])
        return 1;

    if ((modifiers & 0x00200000u) != 0) {
        if ((unsigned short)(character + 0x0900u) <= 3u)
            return 3;
        if ((modifiers & 0x00080000u) != 0) {
            [self deAlternatize:event];
            return (eflags & 0x40000000u) == 0;
        }
        if (character == 3u)
            return 2;
        return (eflags & 0x40000000u) != 0 ? 2 : 0;
    }

    if ((modifiers & 0x00080000u) != 0) {
        if (meta != 0) {
            if (meta > 0) {
                [self deAlternatize:event];
                [term outputChar:(unsigned char)meta];
            }
        } else {
            [self deAlternatize:event];
            keyValue = (signed char)[event charValue];
            [event setChar:(int)((unsigned char)keyValue | 0x80u)];
        }
    } else if ((eflags & 0x02000000u) != 0 &&
               (signed char)[event charValue] == 13) {
        [term outputChar:13];
        [event setChar:10];
    }

    return 0;
}

- (void)deAlternatize:(id)event
{
    unsigned int flags;
    id characters;

    flags = (unsigned int)[event modifierFlags];
    if ((flags & 0x00080000u) == 0)
        return;

    [event setModifierFlags:flags & 0xFFF7FFFFu];
    if ((flags & 0x00040000u) != 0)
        characters = [event characters];
    else
        characters = [event charactersIgnoringModifiers];
    [event setChars:characters];
    characters = [event charactersIgnoringModifiers];
    [event setChars:characters];
}

@end
