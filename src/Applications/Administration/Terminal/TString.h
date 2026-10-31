#ifndef TERMINAL_TSTRING_H
#define TERMINAL_TSTRING_H

#import <Foundation/NSObject.h>
#import <Foundation/NSString.h>

#include "Chunk.h"

@interface TString : NSObject
{
    TerminalChunk *text;
}

- (id)_createIfNecessary;
- (id)stringValue;
- (void)setStringValue:(id)value;
- (void)empty;
- (void)dealloc;

@end

#endif
