#import "FontTrap.h"

#import <AppKit/NSFontPanel.h>
#import <AppKit/NSControl.h>
#import <Foundation/NSBundle.h>
#import <Foundation/NSException.h>

@interface NSObject (FontTrapTargetCallbacks)
- (void)receiveFontFromTrap:(NSFont *)font;
- (void)fontTrapDidResignFirstResponder;
@end

@implementation FontTrap

- (id)initWithFrame:(NSRect)frame
{
    return [super initWithFrame:frame];
}

- (BOOL)acceptsFirstResponder
{
    return YES;
}

- (void)changeFont:(id)sender
{
    NSFontManager *fontManager;
    NSFont *font;
    NSBundle *bundle;
    float *widths;
    NSString *alertTitle;
    NSString *alertMessage;
    NSString *button;
    float pointSize;

    fontManager = [NSFontManager sharedFontManager];
    if (fontManager == nil) {
        [[NSAssertionHandler currentHandler]
            handleFailureInMethod:_cmd
            object:self
            file:@"FontTrap.m"
            lineNumber:26
            description:@"No font manager?"];
    }

    font = [fontManager convertFont:[(NSControl *)fontTarget font]];
    pointSize = [font pointSize];
    if (pointSize >= 128.0) {
        bundle = [NSBundle mainBundle];
        alertTitle = [bundle localizedStringForKey:@"Font Too Large"
            value:nil table:nil];
        alertMessage = [bundle localizedStringForKey:
            @"That font is too large to use in a Terminal window.  Choose a font smaller than %d point."
            value:nil table:nil];
        button = [bundle localizedStringForKey:@"OK" value:nil table:nil];
        NSRunAlertPanel(alertTitle, alertMessage, button, nil, nil, 128);
        return;
    }

    if (pointSize <= 5.0) {
        bundle = [NSBundle mainBundle];
        alertTitle = [bundle localizedStringForKey:@"Font Too Small"
            value:nil table:nil];
        alertMessage = [bundle localizedStringForKey:
            @"That font is too small to use in a Terminal window.  Choose a font larger than %d point."
            value:nil table:nil];
        button = [bundle localizedStringForKey:@"OK" value:nil table:nil];
        NSRunAlertPanel(alertTitle, alertMessage, button, nil, nil, 5);
        return;
    }

    widths = [font widths];
    if (widths == NULL) {
        bundle = [NSBundle mainBundle];
        alertTitle = [bundle localizedStringForKey:@"No Metrics"
            value:nil table:nil];
        alertMessage = [bundle localizedStringForKey:
            @"Can't find font metrics for requested font."
            value:nil table:nil];
        button = [bundle localizedStringForKey:@"OK" value:nil table:nil];
        NSRunAlertPanel(alertTitle, alertMessage, button, nil, nil);
        return;
    }

    if (widths['i'] == widths['W']) {
        [targetProxy receiveFontFromTrap:font];
        return;
    }

    bundle = [NSBundle mainBundle];
    alertTitle = [bundle localizedStringForKey:@"Inappropriate Font"
        value:nil table:nil];
    alertMessage = [bundle localizedStringForKey:
        @"The font '%@' can't be used because it is not a constant-width font."
        value:nil table:nil];
    button = [bundle localizedStringForKey:@"OK" value:nil table:nil];
    NSRunAlertPanel(alertTitle, alertMessage, button, nil, nil,
        [font fontName]);
}

- (BOOL)resignFirstResponder
{
    [targetProxy fontTrapDidResignFirstResponder];
    return YES;
}

@end
