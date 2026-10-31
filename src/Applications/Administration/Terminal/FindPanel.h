#ifndef TERMINAL_FIND_PANEL_H
#define TERMINAL_FIND_PANEL_H

#import <Foundation/NSObject.h>

@interface FindPanel : NSObject
{
    id findPanel;
}

- (id)findPanel;
- (void)findPanel:(id)sender;
- (void)enterSelection:(id)sender;
- (void)doFind:(id)sender findBackwards:(char)backwards;
- (void)findNext:(id)sender;
- (void)findPrevious:(id)sender;
- (char)importFindText:(id)sender;
- (char)exportFindText:(id)sender;

@end

#endif
