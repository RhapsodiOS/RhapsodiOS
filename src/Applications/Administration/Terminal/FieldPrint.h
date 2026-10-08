#ifndef TERMINAL_FIELD_PRINT_H
#define TERMINAL_FIELD_PRINT_H

#import <AppKit/NSView.h>
#import <AppKit/NSMatrix.h>

@class FieldView;

@interface FieldPrint : NSView
{
    FieldView *fieldView;
    unsigned int top;
    unsigned int bot;
    id accessoryView;
    NSMatrix *attributeMatrix;
    id attrButton;
    NSMatrix *rangeMatrix;
    id rangeButton;
}

- (BOOL)isFlipped;
- (void)print:(id)sender;
- (void)adjustPageHeightNew:(float *)newBottom
                       top:(float)oldTop
                    bottom:(float)oldBottom
                     limit:(float)bottomLimit;
- (void)drawRect:(NSRect)rect;
- (void)rangePicked:(id)sender;
- (void)attributesPicked:(id)sender;

+ (void)fieldPrint:(id)view;

@end

#endif
