/*	NSInputManager.m
	Copyright (c) 1994-1997, Apple Computer, Inc.
	All rights reserved.
*/

#import <AppKit/NSInputManager.h>
#import <AppKit/NSApplication.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSData.h>
#import <Foundation/NSArchiver.h>
#import <Foundation/NSAutoreleasePool.h>

static NSInputManager *_NSCurrentInputManager;
static NSArray *_NSActiveInputManagers;
static unsigned int _NSActiveInputIndex;

@interface NSInputServer (NSInputManagerStatus)
- (void)_inputClientChangedStatus:(unsigned)status
				inputClient:(id)client
					arg1:(unsigned)arg1
					arg2:(unsigned)arg2;
- (void)markedTextAbandoned:(id)sender;
- (void)activeConversationWillChange:(id)sender fromOldConversation:(long)conversation;
- (void)terminate:(id)sender;
@end

@interface NSInputManager (NSInputManagerSelection)
+ (void)setCurrentInputManager:(NSInputManager *)manager;
@end

@implementation NSInputManager

+ (NSInputManager *)currentInputManager
{
	return _NSCurrentInputManager;
}

+ (NSArray *)activeInputManagerArray
{
	return _NSActiveInputManagers;
}

+ (unsigned int)indexOfCurrentInputManager
{
	return _NSActiveInputIndex;
}

+ (unsigned int)currentInputManagerIndex
{
	return (unsigned int)[_NSActiveInputManagers indexOfObject:_NSCurrentInputManager];
}

+ (void)setCurrentInputManagerAtIndex:(unsigned int)index
{
	if (index > 0x3E7) {
		id manager = [_NSActiveInputManagers objectAtIndex:index - 1000];
		[manager setEnabled:YES];
	} else {
		id manager = [_NSActiveInputManagers objectAtIndex:index];
		[self setCurrentInputManager:manager];
	}
}

+ (BOOL)worksWhenModal
{
	return YES;
}

- (NSImage *)image
{
	return _image;
}

- (NSString *)language
{
	return _language;
}

- (NSString *)localizedInputManagerName
{
	return _visibleName;
}

- (NSInputServer *)server
{
	return (NSInputServer *)_server;
}

- (BOOL)wantsToInterpretAllKeystrokes
{
	return (_flags & 0x10) != 0;
}

- (BOOL)wantsToHandleMouseEvents
{
	return (_flags & 0x8000) != 0;
}

- (BOOL)wantsToDelayTextChangeNotifications
{
	return (_flags & 0x10000) != 0;
}

- (id)_currentClient
{
	return _currentClient;
}

- (id)_trueName
{
	return _trueName;
}

- (id)bundleObject
{
	return _bundleObj;
}

- (long)conversationIdentifier
{
	return [_currentClient conversationIdentifier];
}

- (BOOL)hasMarkedText
{
	return [_currentClient hasMarkedText];
}

- (BOOL)isEnabled
{
	return (_flags & 1) != 0;
}

- (void)inputClientBecomeFirstResponder:(id)client
{
	if ((_flags & 0x20000U) != 0) {
		if (client != _currentClient) {
			_flags |= 0x100000U;
			if ([client respondsToSelector:@selector(conversationIdentifier)] &&
				(![client respondsToSelector:@selector(_acceptsMarkedText)] ||
					[client _acceptsMarkedText])) {
				_flags |= 0x2000U;
				_currentClient = client;
			} else {
				_flags &= ~0x2000U;
				_currentClient = nil;
			}
		}
		[self setEnabled:(_flags & 0x2000U) != 0];
	}
}

- (void)inputClientResignFirstResponder:(id)client
{
	if ((_flags & 1U) != 0 &&
		[client respondsToSelector:@selector(hasMarkedText)] &&
		[client hasMarkedText]) {
		[client unmarkText];
		[_server markedTextAbandoned:self];
		if (client == _currentClient) {
			long conversation = [_currentClient conversationIdentifier];
			[_server activeConversationWillChange:self fromOldConversation:conversation];
		}
	}
	[self setEnabled:NO];
}

- (void)inputClientResignKeyWindow:(id)client
{
	if ((_flags & 1U) != 0 &&
		[client respondsToSelector:@selector(hasMarkedText)] &&
		[client hasMarkedText] && client == _currentClient) {
		long conversation = [_currentClient conversationIdentifier];
		[_server activeConversationWillChange:self fromOldConversation:conversation];
	}
	[self setEnabled:NO];
}

- (void)setEnabled:(BOOL)flag
{
	id client = [[NSApp keyWindow] firstResponder];

	if (client != nil && client != _currentClient) {
		_flags |= 0x100000U;
		if ([client respondsToSelector:@selector(conversationIdentifier)] &&
			(![client respondsToSelector:@selector(_acceptsMarkedText)] ||
				[client _acceptsMarkedText])) {
			_flags |= 0x2000U;
			_currentClient = client;
		} else {
			_flags &= ~0x2000U;
			_currentClient = nil;
		}
	}

	if (flag && (_flags & 0x22000U) == 0x22000U &&
		[_currentClient respondsToSelector:@selector(window)] &&
		[[_currentClient window] isVisible])
		_flags |= 1U;
	else
		_flags &= ~1U;
}

- (void)markedTextAbandoned:(id)cli
{
	_flags |= 0x40000U;
}

- (void)markedTextSelectionChanged:(NSRange)newSel client:(id)cli
{
	_flags |= 0x80000U;
}

- (NSRange)markedRange
{
	return [_currentClient markedRange];
}

- (NSRange)selectedRange
{
	return [_currentClient selectedRange];
}

- (void)getMarkedText:(id *)text selectedRange:(NSRange *)range
{
	[_currentClient getMarkedText:text selectedRange:range];
}

- (NSAttributedString *)attributedSubstringFromRange:(NSRange)theRange
{
	id substring = [_currentClient attributedSubstringFromRange:theRange];

	if ((_flags & 0x200) == 0)
		return (NSAttributedString *)[NSArchiver archivedDataWithRootObject:substring];
	return substring;
}

- (void)insertText:(id)string
{
	if ([string isKindOfClass:[NSData class]])
		string = [NSUnarchiver unarchiveObjectWithData:string];
	[_currentClient insertText:string];
}

- (void)insertText:(id)string client:(id)client
{
	if (client == _currentClient && (_flags & 0x2000) != 0 &&
		_server != nil && (_flags & 1) != 0)
		[_server insertText:string client:self];
	else
		[client insertText:string];
}

- (void)setMarkedText:(id)string selectedRange:(NSRange)selection
{
	if ([string isKindOfClass:[NSData class]])
		string = [NSUnarchiver unarchiveObjectWithData:string];
	[_currentClient setMarkedText:string selectedRange:selection];
}

- (NSArray *)validAttributesForMarkedText
{
	return [_currentClient validAttributesForMarkedText];
}

- (unsigned int)characterIndexForPoint:(NSPoint)thePoint
{
	return [_currentClient characterIndexForPoint:thePoint];
}

- (void)doCommandBySelector:(SEL)aSelector
{
	[_currentClient doCommandBySelector:aSelector];
}

- (NSRect)firstRectForCharacterRange:(NSRange)theRange
{
	return [_currentClient firstRectForCharacterRange:theRange];
}

- (void)unmarkText
{
	[_currentClient unmarkText];
}

- (void)_terminate
{
	_flags |= 2U;
	if (_server != nil) {
		[_server terminate:self];
		[_server release];
		_server = nil;
	}
}

- (void)dealloc
{
	[self _terminate];
	[_bundleObj release];
	[_trueName release];
	[_connectionName release];
	[_hostName release];
	[_procToExec release];
	[_visibleName release];
	[_bundleName release];
	[_keybindings release];
	[_keyBindingsName release];
	[_language release];
	[_image release];
	[super dealloc];
}

- (BOOL)worksWhenModal
{
	return YES;
}

- (void)_notifyInputServerIfNeeded
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	unsigned int status = 0, arg1 = 0, arg2 = 0;

	if (_flags != _lastFlags) {
		if (_flags & 0x40000) {
			status = 0x08;
			_flags &= ~0x40000U;
		}
		if ([_currentClient conversationIdentifier] !=
			[_lastClient conversationIdentifier]) {
			status |= 0x04;
			arg1 = (unsigned int)[_currentClient conversationIdentifier];
			_flags &= ~0x100000U;
		} else if (_flags & 0x80000) {
			NSRange range = [_currentClient selectedRange];

			status |= 0x10;
			arg1 = (unsigned int)range.location;
			arg2 = (unsigned int)range.length;
			_flags &= ~0x80000U;
		}
		if ((_flags & 0x20000) != (_lastFlags & 0x20000))
			status |= (_flags & 0x20000) ? 0x01 : 0x20;
		if ((_flags & 1) != (_lastFlags & 1))
			status |= (_flags & 1) ? 0x02 : 0x40;
		if (status != 0)
			[_server _inputClientChangedStatus:status inputClient:self
				arg1:arg1 arg2:arg2];
	}
	_lastFlags = _flags;
	[_lastClient release];
	_lastClient = [_currentClient retain];
	[pool drain];
}

@end

