#import "Emulation.h"
#import "TerminalApp.h"
#import "TerminalDefaults.h"
#import "Terminal.h"
#import "TString.h"

#import <AppKit/NSColor.h>
#import <AppKit/NSGraphics.h>
#import <AppKit/NSWindow.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSCoder.h>
#import <Foundation/NSException.h>
#import <Foundation/NSString.h>
#import <Foundation/NSUserDefaults.h>
#import <Foundation/NSZone.h>

#include <string.h>
#include <stdlib.h>

extern id _theDefaultsObject;

void getDefaultColors(id *colors)
{
    NSString *colorString;
    NSArray *components;
    unsigned index;
    unsigned componentIndex;
    float red;
    float green;
    float blue;
    float gray;
    NSColor *color;

    NS_DURING
    colorString = [(NSUserDefaults *)_theDefaultsObject stringForKey:@"TextColors"];
    if (colorString != nil) {
        components = [(NSMutableArray *)[colorString
            componentsSeparatedByString:@" "] retain];
        [(NSMutableArray *)components removeObject:@""];
        if (components != nil) {
            for (index = 0; index < 8; index++) {
                componentIndex = index * 3;
                red = [[components objectAtIndex:componentIndex] floatValue];
                green = [[components objectAtIndex:componentIndex + 1] floatValue];
                blue = [[components objectAtIndex:componentIndex + 2] floatValue];
                color = [[NSColor colorWithCalibratedRed:red green:green
                    blue:blue alpha:1.0] colorUsingColorSpaceName:
                        NSCalibratedRGBColorSpace];
                colors[index] = color;

                if (NSBitsPerPixelFromDepth([NSWindow defaultDepthLimit]) == 2) {
                    gray = [color whiteComponent] + 0.15;
                    gray = (int)(gray * 3.0) / 3.0;
                    [color release];
                    colors[index] = [[NSColor
                        colorWithCalibratedWhite:gray alpha:1.0]
                        colorUsingColorSpaceName:NSCalibratedWhiteColorSpace];
                }
            }
            [components release];
        }
    }
    NS_HANDLER
        (void)localException;
    NS_ENDHANDLER
}

TerminalEmulationDefaults *defaultsFromDB(NSZone *zone)
{
    TerminalEmulationDefaults *defaults;
    const char *shell;
    size_t shellLength;
    NSString *fontName;
    NSString *attributes;

    if (zone == NULL)
        zone = NSDefaultMallocZone();
    defaults = NSZoneMalloc(zone, sizeof(*defaults));
    if (defaults == NULL)
        return NULL;
    defaults->var0 = (signed char)[(NSUserDefaults *)_theDefaultsObject
        boolForKey:@"AutoFocus"];
    defaults->var1 = (signed char)[(NSUserDefaults *)_theDefaultsObject
        boolForKey:@"Autowrap"];
    defaults->var2 = (signed char)[(NSUserDefaults *)_theDefaultsObject
        boolForKey:@"Keypad"];
    defaults->var3 = (signed char)[(NSUserDefaults *)_theDefaultsObject
        boolForKey:@"Scrollback"];
    defaults->var4 = (signed char)[(NSUserDefaults *)_theDefaultsObject
        boolForKey:@"SourceDotLogin"];
    defaults->var5 = (signed char)[(NSUserDefaults *)_theDefaultsObject
        boolForKey:@"StrictEmulation"];
    defaults->var6 = (signed char)[(NSUserDefaults *)_theDefaultsObject
        boolForKey:@"Translate"];
    defaults->var7 = (unsigned short)[(NSUserDefaults *)_theDefaultsObject
        integerForKey:@"Rows"];
    defaults->var8 = (unsigned short)[(NSUserDefaults *)_theDefaultsObject
        integerForKey:@"Columns"];
    defaults->var9 = (signed char)[(NSUserDefaults *)_theDefaultsObject
        integerForKey:@"Meta"];
    defaults->var12 = (float)[(NSUserDefaults *)_theDefaultsObject
        integerForKey:@"NSFixedPitchFontSize"];
    defaults->var13 = (unsigned int)[(NSUserDefaults *)_theDefaultsObject
        integerForKey:@"WinLocX"];
    defaults->var14 = (unsigned int)[(NSUserDefaults *)_theDefaultsObject
        integerForKey:@"WinLocY"];
    defaults->var15 = (unsigned char)[(NSUserDefaults *)_theDefaultsObject
        integerForKey:@"TitleBits"];
    defaults->var17 = [(NSUserDefaults *)_theDefaultsObject
        integerForKey:@"SaveLines"];
    defaults->var18 = [(NSUserDefaults *)_theDefaultsObject
        integerForKey:@"ShellExitAction"];
    defaults->var20 = [(NSUserDefaults *)_theDefaultsObject
        integerForKey:@"TextAttributes"];

    getDefaultColors(defaults->var19);

    shell = [NSApp shell];
    shellLength = strlen(shell);
    defaults->var10 = NSZoneMalloc(zone, shellLength + 1);
    strcpy(defaults->var10, shell);

    fontName = [[NSString allocWithZone:zone] initWithString:
        [(NSUserDefaults *)_theDefaultsObject stringForKey:@"NSFixedPitchFont"]];
    defaults->var11 = fontName;

    defaults->var16 = [[TString allocWithZone:zone] init];
    attributes = [[NSString allocWithZone:zone] initWithString:
        [(NSUserDefaults *)_theDefaultsObject stringForKey:@"CustomTitle"]];
    [(TString *)defaults->var16 setStringValue:attributes];
    [attributes release];

    return defaults;
}

void writeDefaultsToTypedStream(const TerminalEmulationDefaults *defaults,
    const struct TerminalExtraWindowInfo *windowInfo, NSCoder *stream)
{
    const char *attributes;
    const char *fontName;
    int version;
    unsigned index;

    version = 5;
    attributes = [[(TString *)defaults->var16 stringValue] cString];
    fontName = [(NSString *)defaults->var11 cString];
    [stream encodeValueOfObjCType:"i" at:&version];
    [stream encodeValuesOfObjCTypes:"ffccccccccssc**fiic*ii",
        &windowInfo->x, &windowInfo->y, &windowInfo->hidden,
        &defaults->var0, &defaults->var1, &defaults->var2, &defaults->var3,
        &defaults->var4, &defaults->var5, &defaults->var6,
        &defaults->var7, &defaults->var8, &defaults->var9,
        &defaults->var10, &fontName, &defaults->var12,
        &defaults->var13, &defaults->var14, &defaults->var15,
        &attributes, &defaults->var17, &defaults->var18];
    for (index = 0; index < 8; index++)
        [stream encodeObject:defaults->var19[index]];
    [stream encodeValueOfObjCType:"i" at:&defaults->var20];
}

TerminalEmulationDefaults *readDefaultsFromTypedStream(NSCoder *stream,
    struct TerminalExtraWindowInfo *windowInfo, NSZone *zone)
{
    TerminalEmulationDefaults *defaults;
    int version;
    char *fontName;
    char *attributes;
    unsigned index;
    BOOL convertColorsToGray;
    float gray;
    id color;

    if (zone == NULL)
        return NULL;
    defaults = NSZoneMalloc(zone, sizeof(*defaults));
    if (defaults == NULL)
        return NULL;
    fontName = NULL;
    attributes = NULL;

    NS_DURING
        [stream decodeValueOfObjCType:"i" at:&version];
        if (version > 5)
            [[NSException exceptionWithName:NSInvalidArgumentException
                reason:@"File format > current file format version"
                userInfo:nil] raise];
        [stream decodeValuesOfObjCTypes:"ffccccccccssc**fiic*ii",
            &windowInfo->x, &windowInfo->y, &windowInfo->hidden,
            &defaults->var0, &defaults->var1, &defaults->var2, &defaults->var3,
            &defaults->var4, &defaults->var5, &defaults->var6,
            &defaults->var7, &defaults->var8, &defaults->var9,
            &defaults->var10, &fontName, &defaults->var12,
            &defaults->var13, &defaults->var14, &defaults->var15,
            &attributes, &defaults->var17, &defaults->var18];

        defaults->var16 = [[TString allocWithZone:zone] init];
        [(TString *)defaults->var16 setStringValue:
            [NSString stringWithCString:attributes]];
        if (attributes != NULL)
            free(attributes);
        defaults->var11 = [[NSString stringWithCString:fontName] copy];
        if (fontName != NULL)
            free(fontName);

        if (version <= 3) {
            getDefaultColors(defaults->var19);
        } else {
            convertColorsToGray = version == 4
                && NSBitsPerPixelFromDepth([NSWindow defaultDepthLimit]) == 2;
            for (index = 0; index < 8; index++) {
                if (version > 4)
                    color = [[stream decodeObject] copy];
                else
                    color = [[stream decodeNXColor] copy];
                defaults->var19[index] = color;
                if (convertColorsToGray) {
                    gray = [[color colorUsingColorSpaceName:
                        NSCalibratedWhiteColorSpace] whiteComponent] + 0.15;
                    gray = (int)(gray * 3.0) / 3.0;
                    [color release];
                    defaults->var19[index] = [[[NSColor
                        colorWithCalibratedWhite:gray alpha:1.0]
                        colorUsingColorSpaceName:NSCalibratedWhiteColorSpace]
                        copy];
                }
            }
        }
        if (version > 3)
            [stream decodeValueOfObjCType:"i" at:&defaults->var20];
        if (version == 2) {
            windowInfo->x /= 1120.0;
            windowInfo->y /= 832.0;
        }
    NS_HANDLER
        (void)localException;
        NSZoneFree(zone, defaults);
        defaults = NULL;
    NS_ENDHANDLER

    return defaults;
}
