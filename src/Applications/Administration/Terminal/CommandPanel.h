#ifndef TERMINAL_COMMAND_PANEL_H
#define TERMINAL_COMMAND_PANEL_H

#import <Foundation/NSObject.h>

@interface CommandPanel : NSObject
{
    id commandForm;
    id commandHistory[10];
    int currentIndex;
    int lastIndex;
}
- (void)showPanel;
- (void)commandEntered:(id)sender;
- (char)control:(id)control textView:(id)textView
    doCommandBySelector:(SEL)selector;
@end

#endif
