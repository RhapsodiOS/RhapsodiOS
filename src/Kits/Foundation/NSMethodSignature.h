/*	NSMethodSignature.h
	Type information for selectors
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSObject.h>

@interface NSMethodSignature : NSObject {
    @private
    const char	*_types;
    int		_nargs;
    unsigned	_sizeofParams;
    unsigned	_returnValueLength;
    void	*_parmInfoP;
    int		*_fixup;
    void	*_reserved;
}

- (unsigned)numberOfArguments;
- (const char *)getArgumentTypeAtIndex:(unsigned)index;

- (unsigned)frameLength;

- (BOOL)isOneway;

- (const char *)methodReturnType;
- (unsigned)methodReturnLength;

@end
