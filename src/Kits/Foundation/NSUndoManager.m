/*	NSUndoManager.m
	Copyright 1994-1997, Apple Computer, Inc. All rights reserved.
*/

#import <Foundation/NSUndoManager.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSBundle.h>
#import <Foundation/NSException.h>
#import <Foundation/NSInvocation.h>
#import <Foundation/NSNotification.h>
#import <Foundation/NSObjCRuntime.h>
#import <Foundation/NSRunLoop.h>
#import <Foundation/NSString.h>
#import <Foundation/NSZone.h>

extern NSBundle *_NSFoundationBundle(void);

NSString * const NSUndoManagerCheckpointNotification = @"NSUndoManagerCheckpointNotification";
NSString * const NSUndoManagerWillUndoChangeNotification = @"NSUndoManagerWillUndoChangeNotification";
NSString * const NSUndoManagerWillRedoChangeNotification = @"NSUndoManagerWillRedoChangeNotification";
NSString * const NSUndoManagerDidUndoChangeNotification = @"NSUndoManagerDidUndoChangeNotification";
NSString * const NSUndoManagerDidRedoChangeNotification = @"NSUndoManagerDidRedoChangeNotification";
NSString * const NSUndoManagerDidOpenUndoGroupNotification = @"NSUndoManagerDidOpenUndoGroupNotification";
NSString * const NSUndoManagerWillCloseUndoGroupNotification = @"NSUndoManagerWillCloseUndoGroupNotification";

static BOOL DebugUndo;

@interface _NSUndoObject : NSObject {
@public
    _NSUndoObject *next;
    _NSUndoObject *previous;
    id _target;
}
- (id)initWithTarget:(id)target;
- (id)target;
- (void)invoke;
- (BOOL)isBeginMark;
- (BOOL)isEndMark;
@end

@interface _NSUndoBeginMark : _NSUndoObject {
@public
    NSString *_groupIdentifier;
}
- (BOOL)isBeginMark;
- (NSString *)groupIdentifier;
- (void)setGroupIdentifier:(NSString *)identifier;
@end

@interface _NSUndoEndMark : _NSUndoObject
- (BOOL)isEndMark;
@end

@interface _NSUndoLightInvocation : _NSUndoObject {
@public
    SEL _selector;
    id _arg;
}
- (id)initWithTarget:(id)target selector:(SEL)selector object:(id)object;
#if defined(__ppc__) || defined(__POWERPC__)
- (id)_argument;
#endif
@end

@interface _NSUndoInvocation : _NSUndoObject {
@public
    NSInvocation *_invocation;
}
- (id)initWithTarget:(id)target invocation:(NSInvocation *)invocation;
@end

@interface _NSUndoStack : NSObject {
@public
    unsigned _max;
    unsigned _count;
    unsigned _nestingLevel;
    _NSUndoObject *_head;
}
- (unsigned)nestingLevel;
- (unsigned)count;
- (unsigned)max;
- (void)setMax:(unsigned)max;
- (void)push:(id)object;
- (void)markBegin;
- (void)markEnd;
- (id)topUndoObject;
- (id)popUndoObject;
- (BOOL)popAndInvoke;
- (void)removeObject:(id)object;
- (void)removeAllObjects;
- (void)removeAllObjectsWithTarget:(id)target;
- (void)_removeBottom;
- (id)_beginMark;
- (NSString *)groupIdentifier;
- (void)setGroupIdentifier:(NSString *)identifier;
@end

@interface NSUndoManager (NSUndoManagerPrivate)
#if defined(__ppc__) || defined(__POWERPC__)
- (id)_undoStack;
#endif
- (void)_setGroupIdentifier:(NSString *)identifier;
- (void)_registerUndoObject:(id)object;
- (void)_postCheckpointNotification;
- (void)_processEndOfEventNotification:(id)argument;
- (void)_prepareEventGrouping;
@end

static void NSUndoPost(NSString *name, id object)
{
    [[NSNotificationCenter defaultCenter] postNotificationName:name object:object];
}

static void NSUndoRaise(id object, SEL selector, NSString *reason)
{
    NSString *selectorName;
    NSString *className;

#if defined(__ppc__) || defined(__POWERPC__)
    selectorName = NSStringFromSelector(selector);
    className = NSStringFromClass([object class]);
#else
    className = NSStringFromClass([object class]);
    selectorName = NSStringFromSelector(selector);
#endif

    [NSException raise:NSInternalInconsistencyException
                format:reason
                  selectorName, className, object];
}

@implementation _NSUndoObject

- (id)init
{
    return [self initWithTarget:nil];
}

- (id)initWithTarget:(id)target
{
    [super init];
    _target = target;
    return self;
}

- (id)target
{
    return _target;
}

- (BOOL)isBeginMark { return NO; }
- (BOOL)isEndMark { return NO; }

- (void)invoke
{
    [NSException raise:NSInternalInconsistencyException
                format:@"- invoke is Subclass responsability"];
}

@end

@implementation _NSUndoBeginMark

- (BOOL)isBeginMark { return YES; }

- (NSString *)groupIdentifier { return _groupIdentifier; }

- (void)setGroupIdentifier:(NSString *)identifier
{
    NSString *copy = [identifier copyWithZone:[self zone]];
    [_groupIdentifier release];
    _groupIdentifier = copy;
}

- (NSString *)description
{
    return @"beginUndoGrouping";
}

- (void)dealloc
{
    [_groupIdentifier release];
    [super dealloc];
}

@end

@implementation _NSUndoEndMark

- (BOOL)isEndMark { return YES; }

- (NSString *)description
{
    return @"endUndoGrouping";
}

@end

@implementation _NSUndoLightInvocation

- (id)initWithTarget:(id)target selector:(SEL)selector object:(id)object
{
    [super initWithTarget:target];
    _selector = selector;
    _arg = [object retain];
    return self;
}

- (void)invoke
{
    objc_msgSend(_target, _selector, _arg);
}

#if defined(__ppc__) || defined(__POWERPC__)
- (id)_argument
{
    return _arg;
}
#endif

- (NSString *)description
{
    NSString *targetClass;
    NSString *selectorName;
    NSString *argumentClass;

#if defined(__ppc__) || defined(__POWERPC__)
    targetClass = NSStringFromClass([_target class]);
    selectorName = NSStringFromSelector(_selector);
    argumentClass = _arg ? NSStringFromClass([_arg class]) : nil;
#else
    argumentClass = _arg ? NSStringFromClass([_arg class]) : nil;
    selectorName = NSStringFromSelector(_selector);
    targetClass = NSStringFromClass([_target class]);
#endif

    return [NSString stringWithFormat:@"target: %@ 0x%x -- selector:%@ -- arg:%@ 0x%x",
            targetClass, _target, selectorName, argumentClass, _arg];
}

- (void)dealloc
{
    [_arg release];
    [super dealloc];
}

@end

@implementation _NSUndoInvocation

- (id)initWithTarget:(id)target invocation:(NSInvocation *)invocation
{
    [super initWithTarget:target];
    _invocation = [invocation retain];
    [_invocation retainArguments];
    return self;
}

- (void)invoke
{
    [_invocation invokeWithTarget:_target];
}

- (NSString *)description
{
    NSString *targetClass;
    NSString *selectorName;

#if defined(__ppc__) || defined(__POWERPC__)
    targetClass = NSStringFromClass([_target class]);
    selectorName = NSStringFromSelector([_invocation selector]);
#else
    selectorName = NSStringFromSelector([_invocation selector]);
    targetClass = NSStringFromClass([_target class]);
#endif

    return [NSString stringWithFormat:@"target: %@ 0x%x -- selector:%@",
            targetClass, _target, selectorName];
}

- (void)dealloc
{
    [_invocation release];
    [super dealloc];
}

@end

@implementation _NSUndoStack

- (id)init
{
    [super init];
    _max = 0;
    _count = 0;
    _head = nil;
    return self;
}

- (unsigned)nestingLevel { return _nestingLevel; }
- (unsigned)count { return _count; }
- (unsigned)max { return _max; }

- (void)setMax:(unsigned)max
{
    _max = max;
    while (_max && _count > _max)
        [self _removeBottom];
}

- (void)push:(id)object
{
    _NSUndoObject *item = object;
    if (DebugUndo) {
        NSString *stackClassName;
        NSString *itemClassName;
#if defined(__ppc__) || defined(__POWERPC__)
        stackClassName = NSStringFromClass([self class]);
        itemClassName = NSStringFromClass([item class]);
#else
        itemClassName = NSStringFromClass([item class]);
        stackClassName = NSStringFromClass([self class]);
#endif
        NSLog(@"%@ 0x%x pushing %@ object %@",
              stackClassName, self, itemClassName, item);
    }
    item->next = _head;
    if (_head) {
        item->previous = _head->previous;
        _head->previous = item;
    } else {
        item->previous = item;
    }
    _head = item;

    if ([item isEndMark]) {
        if (_nestingLevel == 0) {
            NSUndoRaise(self, _cmd, @"%@ -- %@ 0x%x pushing more ends than begins onto stack");
        }
        _nestingLevel--;
        if (_nestingLevel == 0 && _max && _count > _max)
            [self _removeBottom];
    } else if ([item isBeginMark]) {
        if (_nestingLevel == 0)
            _count++;
        _nestingLevel++;
    }
}

- (void)markBegin
{
    [self push:[[_NSUndoBeginMark allocWithZone:[self zone]] initWithTarget:nil]];
}

- (void)markEnd
{
    [self push:[[_NSUndoEndMark allocWithZone:[self zone]] initWithTarget:nil]];
}

- (id)topUndoObject { return _head; }

- (id)popUndoObject
{
    _NSUndoObject *item = _head;
    if (!item)
        return nil;
    if (DebugUndo) {
        NSString *stackClassName;
        NSString *itemClassName;
#if defined(__ppc__) || defined(__POWERPC__)
        stackClassName = NSStringFromClass([self class]);
        itemClassName = NSStringFromClass([item class]);
#else
        itemClassName = NSStringFromClass([item class]);
        stackClassName = NSStringFromClass([self class]);
#endif
        NSLog(@"%@ 0x%x popping %@ object %@",
              stackClassName, self, itemClassName, item);
    }
    _head = item->next;
    if (_head)
        _head->previous = item->previous;
    if ([item isBeginMark]) {
        if (_nestingLevel == 0) {
            NSUndoRaise(self, _cmd, @"%@ -- %@ 0x%x popping more begins than ends from stack");
        }
        if (_nestingLevel-- == 1)
            _count--;
    } else if ([item isEndMark]) {
        _nestingLevel++;
    }
    return [item autorelease];
}

- (BOOL)popAndInvoke
{
    int depth = 0;
    BOOL invoked = NO;
    _NSUndoObject *item;

    if (_head && ![_head isEndMark]) {
        NSUndoRaise(self, _cmd, @"%@ -- %@ 0x%x popping more begins than ends from stack");
    }
    do {
        if ([_head isBeginMark]) {
            depth--;
        } else if ([_head isEndMark]) {
            depth++;
        } else {
            item = [self popUndoObject];
            [item invoke];
            invoked = YES;
            continue;
        }
        [self popUndoObject];
    } while (_head != nil && depth > 0);
    return invoked;
}

- (id)_beginMark
{
    unsigned depth = _nestingLevel;
    _NSUndoObject *item = _head;
    while (item) {
        if ([item isEndMark])
            depth++;
        if ([item isBeginMark] && depth != 0) {
            if (--depth == 0)
                return item;
        }
        item = item->next;
    }
    return nil;
}

- (NSString *)groupIdentifier
{
    return [[self _beginMark] groupIdentifier];
}

- (void)setGroupIdentifier:(NSString *)identifier
{
    _NSUndoBeginMark *beginMark = [self _beginMark];

    if (beginMark == nil) {
        NSUndoRaise(self, _cmd, @"%@: %@ 0x%x is in invalid state, calling setGroupIdentifier with no begin group mark\n");
    }
    [beginMark setGroupIdentifier:identifier];
}

- (void)removeObject:(id)object
{
    _NSUndoObject *item = object;
    if (item == _head) {
        _head = item->next;
        if (_head)
            _head->previous = item->previous;
    } else {
        _NSUndoObject *newer = item->previous;
        if (newer)
            newer->next = item->next;
        if (item->next)
            item->next->previous = newer;
        else if (_head)
            _head->previous = newer;
    }
    if (item->next == nil && item->previous == item)
        _head = nil;
    [item release];
}

- (void)removeAllObjects
{
    while (_head) {
        _NSUndoObject *item = _head;
        _head = item->next;
        [item release];
    }
    _count = 0;
    _nestingLevel = 0;
}

- (void)removeAllObjectsWithTarget:(id)target
{
    _NSUndoObject *item = _head;
    while (item) {
        _NSUndoObject *older = item->next;
        if ([item target] == target)
            [self removeObject:item];
        item = older;
    }
}

- (void)_removeBottom
{
    _NSUndoObject *previous = _head->previous;
    int depth = 0;

    if (![previous isBeginMark])
        NSUndoRaise(self, _cmd, @"Error while removing bottom of undo stack.");

    do {
        if ([previous isBeginMark]) {
            depth++;
        } else if ([previous isEndMark]) {
            depth--;
        }
        previous = previous->previous;
        [previous->next release];
    } while (depth > 0);

    _head->previous = previous;
    _head->previous->next = nil;
    _count--;
}

- (NSString *)description
{
    int index = 0;
    NSString *result = [NSString stringWithFormat:@"Stack: 0x%x\n", self];
    _NSUndoObject *item;
    for (item = _head; item != nil; item = item->next)
        result = [NSString stringWithFormat:@"%@%d: %@\n", result, index++, item];
    return result;
}

- (void)dealloc
{
    if (DebugUndo)
        NSLog(@"Deallocing undo stack: 0x%x", self);
    while (_head)
        [self popUndoObject];
    [super dealloc];
}

@end

@implementation NSUndoManager

- (id)init
{
    _undoStack = [[_NSUndoStack allocWithZone:[self zone]] init];
    _redoStack = [[_NSUndoStack allocWithZone:[self zone]] init];
    _disabled = 0;
    _flags.undoing = 0;
    _flags.redoing = 0;
    _flags.groupsByEvent = 1;
    _target = nil;
    _runLoopModes = [[NSArray allocWithZone:[self zone]] initWithObjects:nil];
    return self;
}

- (void)dealloc
{
    [[NSRunLoop currentRunLoop] cancelPerformSelector:@selector(_processEndOfEventNotification:)
                                               target:self argument:nil];
    [_undoStack release];
    [_redoStack release];
    [_runLoopModes release];
    [super dealloc];
}

- (void)beginUndoGrouping
{
    if (_disabled)
        return;
    if (!_flags.undoing && !_flags.redoing)
        [self _prepareEventGrouping];
    _NSUndoStack *stack = _flags.undoing ? _redoStack : _undoStack;
    if (!_flags.groupsByEvent || [stack nestingLevel] != 0)
        [self _postCheckpointNotification];
    [stack markBegin];
    if (!_flags.undoing && !_flags.redoing)
        NSUndoPost(NSUndoManagerDidOpenUndoGroupNotification, self);
}

- (void)endUndoGrouping
{
#if defined(__ppc__) || defined(__POWERPC__)
    if (_disabled)
        return;
#endif
    _NSUndoStack *stack = _flags.undoing ? _redoStack : _undoStack;
    [self _postCheckpointNotification];
    if ([stack nestingLevel] == 0) {
        NSUndoRaise(self, _cmd, @"%@: %@ 0x%x is in invalid state, endUndoGrouping called with no matching begin\n");
    }
    if (!_flags.undoing && !_flags.redoing)
        NSUndoPost(NSUndoManagerWillCloseUndoGroupNotification, self);
    [stack markEnd];
}

- (int)groupingLevel
{
    _NSUndoStack *stack = _flags.undoing ? _redoStack : _undoStack;
    return (int)[stack nestingLevel];
}
- (void)disableUndoRegistration { _disabled++; }

- (void)enableUndoRegistration
{
    if (_disabled == 0) {
        NSUndoRaise(self, _cmd, @"%@: %@ 0x%x is in invalid state, enableUndoRegistration may only be invoked with matching call to disableUndoRegistration\n");
    }
    _disabled--;
}

- (BOOL)isUndoRegistrationEnabled { return _disabled == 0; }
- (BOOL)groupsByEvent { return _flags.groupsByEvent; }
- (void)setGroupsByEvent:(BOOL)groupsByEvent { _flags.groupsByEvent = groupsByEvent ? 1 : 0; }
- (void)setLevelsOfUndo:(unsigned)levels { [_undoStack setMax:levels]; }
- (unsigned)levelsOfUndo { return [_undoStack max]; }

- (void)setRunLoopModes:(NSArray *)runLoopModes
{
    NSArray *oldRunLoopModes = _runLoopModes;
    _runLoopModes = [runLoopModes copyWithZone:[self zone]];
    [oldRunLoopModes release];
}

- (NSArray *)runLoopModes { return _runLoopModes; }

- (void)registerUndoWithTarget:(id)target selector:(SEL)selector object:(id)object
{
    _NSUndoLightInvocation *undo = [[_NSUndoLightInvocation allocWithZone:[self zone]]
                                     initWithTarget:target selector:selector object:object];
    [self _registerUndoObject:undo];
}

- (id)prepareWithInvocationTarget:(id)target
{
    _target = target;
    return self;
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector
{
    NSMethodSignature *signature = [super methodSignatureForSelector:selector];
    if (!signature)
        signature = [_target methodSignatureForSelector:selector];
    return signature;
}

- (void)forwardInvocation:(NSInvocation *)invocation
{
    if (!_target) {
        NSString *selectorName;
        NSString *className;
        NSString *invocationSelectorName;

#if defined(__ppc__) || defined(__POWERPC__)
        selectorName = NSStringFromSelector(_cmd);
        className = NSStringFromClass([self class]);
        invocationSelectorName = NSStringFromSelector([invocation selector]);
#else
        invocationSelectorName = NSStringFromSelector([invocation selector]);
        className = NSStringFromClass([self class]);
        selectorName = NSStringFromSelector(_cmd);
#endif
        [NSException raise:NSInternalInconsistencyException
                    format:@"%@: %@ 0x%x received forwarded invocation while invocation target is nil. Call prepareWithInvocationTarget: before invoking %@",
                    selectorName, className, self, invocationSelectorName];
    }
    [invocation setTarget:nil];
    _NSUndoInvocation *undo = [[_NSUndoInvocation allocWithZone:[self zone]]
                                initWithTarget:_target invocation:invocation];
    [self _registerUndoObject:undo];
    _target = nil;
}

- (void)setActionName:(NSString *)actionName { [self _setGroupIdentifier:actionName]; }
- (NSString *)undoActionName
{
    NSString *name = [_undoStack groupIdentifier];
    return name ? name : @"";
}

- (NSString *)redoActionName
{
    NSString *name = [_redoStack groupIdentifier];
    return name ? name : @"";
}

- (BOOL)canUndo { return [_undoStack count] != 0; }
- (BOOL)canRedo
{
    [self _postCheckpointNotification];
    return [_redoStack count] != 0;
}

- (BOOL)isUndoing { return _flags.undoing; }
- (BOOL)isRedoing { return _flags.redoing; }

- (void)undo
{
    [self _postCheckpointNotification];
    if (_flags.registeredForCallback && [_undoStack nestingLevel] == 1) {
        [self endUndoGrouping];
        _flags.registeredForCallback = 0;
#if defined(__ppc__) || defined(__POWERPC__)
        [[NSRunLoop currentRunLoop]
            cancelPerformSelector:@selector(_processEndOfEventNotification:)
                           target:self argument:nil];
#endif
    }
    if ([_undoStack nestingLevel] != 0) {
        NSUndoRaise(self, _cmd, @"%@: %@ 0x%x is in invalid state, undo was called with too many nested undo groups");
    }
    [self undoNestedGroup];
}

- (void)undoNestedGroup
{
    [self _postCheckpointNotification];
    _flags.undoing = 1;
    _NSUndoObject *top = [_undoStack topUndoObject];
    if (top && ![top isEndMark]) {
        _flags.undoing = 0;
        NSUndoRaise(self, _cmd, @"%@: %@ 0x%x is in invalid state, call endUndoGrouping on undo manager before calling this method\n");
    }
    if (top) {
        NSUndoPost(NSUndoManagerWillUndoChangeNotification, self);
        [self beginUndoGrouping];
#if defined(__ppc__) || defined(__POWERPC__)
        if (!_disabled)
#endif
        [_redoStack setGroupIdentifier:[_undoStack groupIdentifier]];
        [_undoStack popAndInvoke];
        [self endUndoGrouping];
        NSUndoPost(NSUndoManagerDidUndoChangeNotification, self);
    }
    _flags.undoing = 0;
}

- (void)redo
{
    if (![self canRedo])
        return;
    _flags.redoing = 1;
    _NSUndoObject *top = [_redoStack topUndoObject];
    if (top && ![top isEndMark]) {
        _flags.redoing = 0;
        NSUndoRaise(self, _cmd, @"%@: %@ 0x%x is in invalid state, do not invoke this method while undoing\n");
    }
    if (top) {
        NSUndoPost(NSUndoManagerWillRedoChangeNotification, self);
        [self beginUndoGrouping];
#if defined(__ppc__) || defined(__POWERPC__)
        if (!_disabled)
#endif
        [_undoStack setGroupIdentifier:[_redoStack groupIdentifier]];
        [_redoStack popAndInvoke];
        [self _postCheckpointNotification];
        [self endUndoGrouping];
        NSUndoPost(NSUndoManagerDidRedoChangeNotification, self);
    }
    _flags.redoing = 0;
}

- (void)removeAllActions
{
    [_undoStack removeAllObjects];
    [_redoStack removeAllObjects];
    _target = nil;
    _flags.undoing = 0;
    _flags.redoing = 0;
    _disabled = 0;
    if (_flags.registeredForCallback) {
#if defined(__ppc__) || defined(__POWERPC__)
        _flags.registeredForCallback = 0;
        [[NSRunLoop currentRunLoop] cancelPerformSelector:@selector(_processEndOfEventNotification:)
                                                   target:self argument:nil];
#else
        [_undoStack markBegin];
#endif
    }
}

- (void)removeAllActionsWithTarget:(id)target
{
    [_undoStack removeAllObjectsWithTarget:target];
    [_redoStack removeAllObjectsWithTarget:target];
}

- (NSString *)undoMenuTitleForUndoActionName:(NSString *)actionName
{
    NSString *format = [_NSFoundationBundle() localizedStringForKey:@"&Undo %@"
                                                               value:@"" table:@"undo"];
    return [NSString stringWithFormat:format, actionName];
}

- (NSString *)redoMenuTitleForUndoActionName:(NSString *)actionName
{
    NSString *format = [_NSFoundationBundle() localizedStringForKey:@"&Redo %@"
                                                               value:@"" table:@"undo"];
    return [NSString stringWithFormat:format, actionName];
}

- (NSString *)undoMenuItemTitle
{
    if ([self canUndo]) {
        NSString *name = [self undoActionName];
        if ([name length])
            return [self undoMenuTitleForUndoActionName:name];
    }
    return [_NSFoundationBundle() localizedStringForKey:@"&Undo" value:@"" table:@"undo"];
}

- (NSString *)redoMenuItemTitle
{
    if ([self canRedo]) {
        NSString *name = [self redoActionName];
        if ([name length])
            return [self redoMenuTitleForUndoActionName:name];
    }
    return [_NSFoundationBundle() localizedStringForKey:@"&Redo" value:@"" table:@"undo"];
}

@end

@implementation NSUndoManager (NSUndoManagerPrivate)

#if defined(__ppc__) || defined(__POWERPC__)
- (id)_undoStack
{
    return _undoStack;
}
#endif

- (void)_postCheckpointNotification
{
    if (!_flags.postingCheckpointNotification) {
        _flags.postingCheckpointNotification = 1;
        NSUndoPost(NSUndoManagerCheckpointNotification, self);
        _flags.postingCheckpointNotification = 0;
    }
}

- (void)_prepareEventGrouping
{
    _NSUndoStack *stack = _flags.undoing ? _redoStack : _undoStack;
    if (_flags.groupsByEvent && !_flags.registeredForCallback && [stack nestingLevel] == 0) {
        _flags.registeredForCallback = 1;
        [self beginUndoGrouping];
        [[NSRunLoop currentRunLoop] performSelector:@selector(_processEndOfEventNotification:)
                                              target:self argument:nil
                                               order:NSUndoCloseGroupingRunLoopOrdering
                                                modes:_runLoopModes];
    }
}

- (void)_processEndOfEventNotification:(id)argument
{
    if (_flags.groupsByEvent && _flags.registeredForCallback) {
        _flags.registeredForCallback = 0;
        [self endUndoGrouping];
    }
}

- (void)_registerUndoObject:(id)object
{
    if (_disabled) {
        [object release];
        return;
    }
    if (!_flags.undoing && !_flags.redoing)
        [_redoStack removeAllObjects];
#if defined(__ppc__) || defined(__POWERPC__)
    [self _prepareEventGrouping];
#else
    [self _postCheckpointNotification];
#endif
    _NSUndoStack *stack = _flags.undoing ? _redoStack : _undoStack;
    if ([stack nestingLevel] == 0) {
        NSUndoRaise(self, _cmd, @"%@: %@ 0x%x is in invalid state, must begin a group before registering undo\n");
    }
    [stack push:object];
}

- (void)_setGroupIdentifier:(NSString *)identifier
{
    if (!identifier || _disabled)
        return;
    [self _prepareEventGrouping];
    _NSUndoStack *stack = _flags.undoing ? _redoStack : _undoStack;
    if ([stack nestingLevel] == 0) {
        NSUndoRaise(self, _cmd, @"%@: %@ 0x%x is in invalid state, calling setGroupIdentifier with no begin group mark\n");
    }
    [stack setGroupIdentifier:identifier];
}

@end
