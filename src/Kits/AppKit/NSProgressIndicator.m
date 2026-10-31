/*	NSProgressIndicator.m
	Copyright (c) 1994-1997, Apple Computer, Inc.
	All rights reserved.
*/

#import <AppKit/NSProgressIndicator.h>
#import <AppKit/NSGraphics.h>
#import <AppKit/NSInterfaceStyle.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSColor.h>
#import <Foundation/NSAutoreleasePool.h>
#import <Foundation/NSLock.h>
#import <Foundation/NSBundle.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSValue.h>
#import <Foundation/NSRunLoop.h>
#import <Foundation/NSThread.h>
#import <Foundation/NSTimer.h>
#import <math.h>

@interface NSProgressIndicator (NSProgressIndicatorPrivate)
+ (NSImage *)_barberImage:(CGFloat)height;
+ (NSImage *)_gaugeImage:(CGFloat)height;
- (void)_commonInit;
- (void)_animationIdler:(id)sender;
- (void)_animationThread;
- (BOOL)_isThreadedAnimationLooping;
- (void)_startAnimationWithThread:(BOOL)threaded;
- (void)_compositeAndUnlockCachedImage;
- (void)_createCachedImage:(NSSize)size;
- (void)_creteCachedImageLockIfNeeded;
- (id)_lockCachedImage;
- (void)_lockUnlockCachedImage:(BOOL)lock;
- (void)_drawFrame;
- (void)_drawAnimationStep;
- (void)_drawProgressArea;
- (void)_drawRemainderArea;
- (NSRect)_getGaugeFrame;
- (CGFloat)_getPosition:(double)value;
- (NSRect)_getProgressFrame;
- (NSRect)_getRemainderFrame;
- (void)_drawWindowsGaugeRects:(NSRect)rect;
- (void)_systemColorChanged:(id)notification;
- (void)_drawFrame;
- (void)_drawRemainderArea;
- (void)_fillGrayRect:(NSRect *)rect with:(int)gray;
- (void)_drawProgressArea;
- (void)_drawAnimationStep;
@end

@implementation NSProgressIndicator

+ (NSImage *)_barberImage:(CGFloat)height
{
	static NSMutableDictionary *cache = nil;
	if (!cache)
		cache = [[NSMutableDictionary alloc] init];
	return [self _createImage:cache :@"BarberPole" :height];
}

+ (NSImage *)_gaugeImage:(CGFloat)height
{
	static NSMutableDictionary *cache = nil;
	if (!cache)
		cache = [[NSMutableDictionary alloc] init];
	return [self _createImage:cache :@"GaugePole" :height];
}

+ (NSImage *)_createImage:(NSMutableDictionary *)cache :(NSString *)name :(CGFloat)height
{
	NSNumber *key = [NSNumber numberWithFloat:height];
	NSImage *image = [cache objectForKey:key];
	if (image)
		return image;
	NSString *path = [[NSBundle bundleForClass:self] pathForImageResource:name];
	image = [[[NSImage alloc] initWithContentsOfFile:path] autorelease];
	if (image) {
		NSSize size = [image size];
		size.height = height;
		[image setSize:size];
		[image setScalesWhenResized:YES];
		[cache setObject:image forKey:key];
	}
	return image;
}

- (id)initWithFrame:(NSRect)frame
{
	self = [super initWithFrame:frame];
	if (self) {
		_isIndeterminate = YES;
		_isBezeled = YES;
		_threadedAnimation = NO;
		_minimum = 0.0;
		_maximum = 100.0;
		[self _commonInit];
	}
	return self;
}

- (void)_commonInit
{
	_value = _minimum;
	_animationIndex = 0;
	_animationDelay = 5.0 / 60.0;
	_progressIndicatorFlags.isSpinning = NO;
	_animationThreadLock = nil;
	_cachedImageLock = nil;
	_cachedImage = nil;
}

- (NSTimeInterval)animationDelay
{
	return _animationDelay;
}

- (void)setAnimationDelay:(NSTimeInterval)delay
{
	if (_animationDelay != delay) {
		_animationDelay = delay;
		if (_timer) {
			[self stopAnimation:self];
			[self startAnimation:nil];
		}
	}
}

- (double)doubleValue
{
	return _value;
}

- (void)incrementBy:(double)delta
{
	[self setDoubleValue:_value + delta];
}

- (BOOL)isBezeled
{
	return _isBezeled;
}

- (void)setBezeled:(BOOL)flag
{
	if (_isBezeled != flag) {
		_isBezeled = flag;
		[self setNeedsDisplay:YES];
	}
}

- (BOOL)isFlipped
{
	return YES;
}

- (BOOL)isIndeterminate
{
	return _isIndeterminate;
}

- (void)setIndeterminate:(BOOL)flag
{
	if (_isIndeterminate != flag) {
		[self stopAnimation:self];
		_isIndeterminate = flag;
		[self setNeedsDisplay:YES];
	}
}

- (BOOL)isOpaque
{
	return YES;
}

- (double)maxValue
{
	return _maximum;
}

- (void)setMaxValue:(double)value
{
	_maximum = value;
	if (!_isIndeterminate)
		[self setNeedsDisplay:YES];
}

- (double)minValue
{
	return _minimum;
}

- (void)setMinValue:(double)value
{
	_minimum = value;
	if (!_isIndeterminate)
		[self setNeedsDisplay:YES];
}

- (void)setDoubleValue:(double)value
{
	if (value > _maximum)
		value = _maximum;
	if (value < _minimum)
		value = _minimum;
	if (_value != value) {
		_value = value;
		if (!_isIndeterminate)
			[self setNeedsDisplay:YES];
	}
}

- (void)setUsesThreadedAnimation:(BOOL)flag
{
	_threadedAnimation = flag;
}

- (BOOL)usesThreadedAnimation
{
	return _threadedAnimation;
}

- (void)startAnimation:(id)sender
{
	[self _startAnimationWithThread:_threadedAnimation];
}

- (void)stopAnimation:(id)sender
{
	if (_isIndeterminate) {
		if ([self _isThreadedAnimationLooping]) {
			_progressIndicatorFlags.isSpinning = NO;
			[_animationThreadLock lock];
			[_animationThreadLock unlock];
		}
		if (_timer) {
			[_timer invalidate];
			[_timer release];
			_timer = nil;
		}
	}
}

- (void)_startAnimationWithThread:(BOOL)threaded
{
	if (_isIndeterminate && !_timer && ![self _isThreadedAnimationLooping]) {
		if (threaded) {
			if (!_animationThreadLock)
				_animationThreadLock = [[NSLock allocWithZone:[self zone]] init];
			_progressIndicatorFlags.isSpinning = YES;
			[NSThread detachNewThreadSelector:@selector(_animationThread)
				toTarget:self withObject:nil];
		} else {
			_timer = [NSTimer timerWithTimeInterval:_animationDelay
				target:self selector:@selector(_animationIdler:) userInfo:nil repeats:YES];
			[[NSRunLoop currentRunLoop] addTimer:_timer forMode:NSDefaultRunLoopMode];
		}
	}
}

- (BOOL)_isThreadedAnimationLooping
{
	return _progressIndicatorFlags.isSpinning;
}

- (void)_animationIdler:(id)sender
{
	[self animate:self];
}

- (void)animate:(id)sender
{
	if (_isIndeterminate && !_threadedAnimation) {
		++_animationIndex;
		[self setNeedsDisplay:YES];
	}
}

- (void)_animationThread
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	while ([self _isThreadedAnimationLooping]) {
		++_animationIndex;
		[self setNeedsDisplay:YES];
		[NSThread sleepUntilDate:[NSDate dateWithTimeIntervalSinceNow:_animationDelay]];
	}
	[pool release];
}

- (void)_creteCachedImageLockIfNeeded
{
	if (!_cachedImageLock)
		_cachedImageLock = [[NSLock allocWithZone:[self zone]] init];
}

- (void)_lockUnlockCachedImage:(BOOL)lock
{
	[self _creteCachedImageLockIfNeeded];
	if (lock)
		[_cachedImageLock lock];
	else
		[_cachedImageLock unlock];
}

- (void)_createCachedImage:(NSSize)size
{
	if (!_cachedImage) {
		_cachedImage = [[NSImage allocWithZone:[self zone]] initWithSize:size];
		[_cachedImage setScalesWhenResized:YES];
	}
}

- (id)_lockCachedImage
{
	NSRect bounds = [self bounds];
	[self _lockUnlockCachedImage:YES];
	if (_cachedImage) {
		if (!NSEqualSizes([_cachedImage size], bounds.size))
			[_cachedImage setSize:bounds.size];
	} else {
		[self _createCachedImage:bounds.size];
	}
	return _cachedImage;
}

- (void)_compositeAndUnlockCachedImage
{
	NSRect bounds = [self bounds];
	NSPoint point = NSMakePoint(bounds.origin.x,
		bounds.origin.y + bounds.size.height);
	[_cachedImage compositeToPoint:point operation:NSCompositeCopy];
	[self _lockUnlockCachedImage:NO];
}

- (void)drawRect:(NSRect)rect
{
	id image = [self _lockCachedImage];
	[image lockFocus];
	[self _drawFrame];
	if (_isIndeterminate) {
		[self _drawAnimationStep];
	} else {
		[self _drawProgressArea];
		[self _drawRemainderArea];
	}
	[image unlockFocus];
	[self _compositeAndUnlockCachedImage];
}

- (NSRect)_getGaugeFrame
{
	NSRect frame = [self bounds];
	CGFloat inset = NSInterfaceStyleForKey(NSInterfaceStyleDefault, nil) == NSWindows95InterfaceStyle || !_isBezeled ? 1.0 : 2.0;
	return NSInsetRect(frame, inset, inset);
}

- (CGFloat)_getPosition:(double)value
{
	NSRect gauge = [self _getGaugeFrame];
	CGFloat end = gauge.origin.x + gauge.size.width;
	CGFloat position = end;
	if (_maximum > _minimum) {
		position = floor(gauge.size.width * (value - _minimum) / (_maximum - _minimum) + gauge.origin.x + 0.5);
		if (position >= end)
			position = end;
	}
	return position;
}

- (NSRect)_getProgressFrame
{
	NSRect frame = [self _getGaugeFrame];
	CGFloat fullWidth = frame.size.width;
	CGFloat width = [self _getPosition:_value] - frame.origin.x;
	if (width > fullWidth)
		width = fullWidth;
	if (NSInterfaceStyleForKey(NSInterfaceStyleDefault, nil) == NSWindows95InterfaceStyle && width < fullWidth) {
		CGFloat pixel = floor(frame.size.height * 0.75);
		width = pixel * floor((width + pixel - 1.0) / pixel);
	}
	frame.size.width = width;
	return frame;
}

- (NSRect)_getRemainderFrame
{
	NSRect frame = [self _getGaugeFrame];
	CGFloat end = frame.origin.x + frame.size.width;
	CGFloat position = [self _getPosition:_value];
	if (position > end)
		position = end;
	if (NSInterfaceStyleForKey(NSInterfaceStyleDefault, nil) == NSWindows95InterfaceStyle && position != end) {
		CGFloat pixel = floor(frame.size.height * 0.75);
		position = pixel * floor((position - frame.origin.x + pixel - 1.0) / pixel) + frame.origin.x;
	}
	frame.size.width = end - position;
	return frame;
}

- (void)_drawWindowsGaugeRects:(NSRect)rect
{
	if (!NSIsEmptyRect(rect)) {
		CGFloat stripeWidth = floor(rect.size.height * 0.75);
		NSRect stripe = NSMakeRect(rect.origin.x, rect.origin.y, stripeWidth, rect.size.height);
		[[NSColor controlColor] set];
		NSRectFill(rect);
		[[NSColor progressIndicatorColor] set];
		while (stripe.origin.x < rect.origin.x + rect.size.width) {
			if (stripe.origin.x + stripe.size.width > rect.origin.x + rect.size.width)
				stripe.size.width = rect.origin.x + rect.size.width - stripe.origin.x;
			NSRectFill(NSInsetRect(stripe, 1.0, 1.0));
			stripe.origin.x += stripeWidth;
		}
	}
}

- (void)_systemColorChanged:(id)notification
{
	[self display];
}

- (void)_fillGrayRect:(NSRect *)rect with:(int)gray
{
	[[NSColor colorWithDeviceWhite:(CGFloat)gray / 5.0 alpha:1.0] set];
	NSRectFill(*rect);
}

- (void)_drawFrame
{
	BOOL windowsStyle = NSInterfaceStyleForKey(NSInterfaceStyleDefault, nil) == NSWindows95InterfaceStyle;
	NSRect frame = [self bounds];
	if (windowsStyle || _isBezeled) {
		if (windowsStyle) {
			[[NSColor controlShadowColor] set];
			NSRectFill(frame);
		} else {
			[self _fillGrayRect:&frame with:2];
		}
		frame.origin.x += 1.0;
		frame.origin.y += 1.0;
		frame.size.width -= 1.0;
		frame.size.height -= 1.0;
		[[NSColor whiteColor] set];
		NSRectFill(frame);
	}
	if (!windowsStyle) {
		[[NSColor blackColor] set];
		NSFrameRect(NSInsetRect([self bounds], 1.0, 1.0));
	}
}

- (void)_drawRemainderArea
{
	NSRect frame = [self _getRemainderFrame];
	if (NSIsEmptyRect(frame))
		return;
	if (NSInterfaceStyleForKey(NSInterfaceStyleDefault, nil) == NSWindows95InterfaceStyle) {
		[[NSColor controlColor] set];
		NSRectFill(frame);
		return;
	}
	CGFloat width = frame.size.width;
	CGFloat stripe = 1.0;
	if (width >= stripe) {
		[[NSColor controlBackgroundColor] set];
		NSRectFill(frame);
		if (width >= 2.0) {
			frame.origin.x += stripe;
			frame.size.width -= stripe;
			[self _fillGrayRect:&frame with:4];
			if (width >= 3.0) {
				frame.origin.x += stripe;
				frame.size.width -= stripe;
				[self _fillGrayRect:&frame with:3];
				if (width >= 4.0) {
					frame.origin.x += stripe;
					frame.size.width -= stripe;
					frame.origin.y += stripe;
					frame.size.height -= stripe;
					[self _fillGrayRect:&frame with:0];
					if (width >= 5.0) {
						frame.size.width -= stripe;
						frame.size.height -= stripe;
						[self _fillGrayRect:&frame with:2];
					}
				}
			}
		}
	}
}

- (void)_drawProgressArea
{
	NSRect frame = [self _getProgressFrame];
	if (NSIsEmptyRect(frame))
		return;
	if (NSInterfaceStyleForKey(NSInterfaceStyleDefault, nil) == NSWindows95InterfaceStyle) {
		[self _drawWindowsGaugeRects:frame];
		return;
	}
	NSImage *image = [NSProgressIndicator _barberImage:frame.size.height];
	NSSize imageSize = [image size];
	[[NSColor progressIndicatorColor] set];
	NSRectFill(frame);
	if (frame.size.width > 1.0) {
		CGFloat rightWidth = frame.size.width < 8.0 ? frame.size.width : 8.0;
		NSRect source = NSMakeRect(imageSize.width - rightWidth, 0.0, rightWidth, imageSize.height);
		[image compositeToPoint:NSMakePoint(frame.origin.x + frame.size.width - rightWidth, frame.origin.y)
			fromRect:source operation:NSCompositeSourceOver];
		if (frame.size.width > 8.0) {
			CGFloat leftWidth = frame.size.width - 8.0 < 4.0 ? frame.size.width - 8.0 : 4.0;
			source = NSMakeRect(1.0, 0.0, leftWidth, imageSize.height);
			[image compositeToPoint:frame.origin fromRect:source operation:NSCompositeSourceOver];
			if (frame.size.width > 20.0) {
				CGFloat x = frame.origin.x + 4.0;
				CGFloat end = frame.origin.x + frame.size.width - 8.0;
				while (x < end) {
					CGFloat width = end - x < 48.0 ? end - x : 48.0;
					source = NSMakeRect(2.0, 0.0, width, imageSize.height);
					[image compositeToPoint:NSMakePoint(x, frame.origin.y)
						fromRect:source operation:NSCompositeSourceOver];
					x += width;
				}
			}
		}
	}
}

- (void)_drawAnimationStep
{
	NSRect frame = [self _getGaugeFrame];
	if (NSIsEmptyRect(frame))
		return;
	if (NSInterfaceStyleForKey(NSInterfaceStyleDefault, nil) == NSWindows95InterfaceStyle) {
		CGFloat pixel = floor(frame.size.height * 0.75);
		if (pixel <= 0.0)
			return;
		_animationIndex %= (int)pixel;
		CGFloat firstWidth = _animationIndex - 0.75;
		NSRect segment = frame;
		segment.size.width = firstWidth;
		[self _drawWindowsGaugeRects:segment];
		segment = frame;
		segment.origin.x += firstWidth;
		segment.size.width -= firstWidth;
		[self _drawWindowsGaugeRects:segment];
		return;
	}
	NSImage *image = [NSProgressIndicator _gaugeImage:frame.size.height];
	NSSize imageSize = [image size];
	if (imageSize.width <= 0.0)
		return;
	_animationIndex %= 4;
	CGFloat tileWidth = imageSize.width / 0.75;
	CGFloat sourceX = imageSize.width - floor(floor(tileWidth) / 4.0 * _animationIndex - 0.75);
	CGFloat x = frame.origin.x;
	CGFloat end = frame.origin.x + frame.size.width;
	[[NSColor controlColor] set];
	NSRectFill(frame);
	while (x < end) {
		CGFloat width = end - x < tileWidth ? end - x : tileWidth;
		NSRect source = NSMakeRect(sourceX, 0.0, width, imageSize.height);
		[image compositeToPoint:NSMakePoint(x, frame.origin.y)
			fromRect:source operation:NSCompositeSourceOver];
		x += width;
	}
}

@end
