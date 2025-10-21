/*	NSUndoManager.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSUndoManager.h>

@implementation NSUndoManager

- (void)beginUndoGrouping {
    // TODO: Implement this method
}

- (void)endUndoGrouping {
    // TODO: Implement this method
}

- (int)groupingLevel {
    // TODO: Implement this method
    return 0;
}

- (void)disableUndoRegistration {
    // TODO: Implement this method
}

- (void)enableUndoRegistration {
    // TODO: Implement this method
}

- (BOOL)isUndoRegistrationEnabled {
    // TODO: Implement this method
    return NO;
}

- (BOOL)groupsByEvent {
    // TODO: Implement this method
    return NO;
}

- (void)setGroupsByEvent:(BOOL)groupsByEvent {
    // TODO: Implement this method
}

- (void)setLevelsOfUndo:(unsigned)levels {
    // TODO: Implement this method
}

- (unsigned)levelsOfUndo {
    // TODO: Implement this method
    return 0;
}

- (void)setRunLoopModes:(NSArray *)runLoopModes {
    // TODO: Implement this method
}

- (NSArray *)runLoopModes {
    // TODO: Implement this method
    return nil;
}

- (void)undo {
    // TODO: Implement this method
}

- (void)redo {
    // TODO: Implement this method
}

- (void)undoNestedGroup {
    // TODO: Implement this method
}

- (BOOL)canUndo {
    // TODO: Implement this method
    return NO;
}

- (BOOL)canRedo {
    // TODO: Implement this method
    return NO;
}

- (BOOL)isUndoing {
    // TODO: Implement this method
    return NO;
}

- (BOOL)isRedoing {
    // TODO: Implement this method
    return NO;
}

- (void)removeAllActions {
    // TODO: Implement this method
}

- (void)removeAllActionsWithTarget:(id)target {
    // TODO: Implement this method
}

- (void)registerUndoWithTarget:(id)target selector:(SEL)selector object:(id)anObject {
    // TODO: Implement this method
}

- (id)prepareWithInvocationTarget:(id)target {
    // TODO: Implement this method
    return nil;
}

- (void)forwardInvocation:(NSInvocation *)anInvocation {
    // TODO: Implement this method
}

- (NSString *)undoActionName {
    // TODO: Implement this method
    return nil;
}

- (NSString *)redoActionName {
    // TODO: Implement this method
    return nil;
}

- (void)setActionName:(NSString *)actionName {
    // TODO: Implement this method
}

- (NSString *)undoMenuItemTitle {
    // TODO: Implement this method
    return nil;
}

- (NSString *)redoMenuItemTitle {
    // TODO: Implement this method
    return nil;
}

- (NSString *)undoMenuTitleForUndoActionName:(NSString *)actionName {
    // TODO: Implement this method
    return nil;
}

- (NSString *)redoMenuTitleForUndoActionName:(NSString *)actionName {
    // TODO: Implement this method
    return nil;
}

@end
