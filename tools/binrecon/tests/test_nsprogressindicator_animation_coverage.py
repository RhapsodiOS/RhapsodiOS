from pathlib import Path

from selector_check import source_methods


def test_progress_indicator_animation_dispatch_matches_reference():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    selectors = (
        "-[NSProgressIndicator _animationIdler:]",
        "-[NSProgressIndicator _animationThread]",
        "-[NSProgressIndicator _isThreadedAnimationLooping]",
        "-[NSProgressIndicator _startAnimationWithThread:]",
        "-[NSProgressIndicator animate:]",
        "-[NSProgressIndicator startAnimation:]",
        "-[NSProgressIndicator stopAnimation:]",
    )
    assert set(selectors) <= methods

    source = (appkit / "NSProgressIndicator.m").read_text()
    start = source.rsplit("- (void)startAnimation:(id)sender", 1)[1].split("\n}", 1)[0]
    assert "[self _startAnimationWithThread:_threadedAnimation];" in start

    idler = source.rsplit("- (void)_animationIdler:(id)sender", 1)[1].split("\n}", 1)[0]
    assert "[self animate:self];" in idler

    looping = source.rsplit("- (BOOL)_isThreadedAnimationLooping", 1)[1].split("\n}", 1)[0]
    assert "return _progressIndicatorFlags.isSpinning;" in looping

    animate = source.rsplit("- (void)animate:(id)sender", 1)[1].split("\n}", 1)[0]
    assert "if (_isIndeterminate && !_threadedAnimation)" in animate
    assert "++_animationIndex;" in animate
    assert "[self setNeedsDisplay:YES];" in animate

    thread = source.rsplit("- (void)_animationThread", 1)[1].split("\n}", 1)[0]
    assert "NSAutoreleasePool *pool" in thread
    assert "while ([self _isThreadedAnimationLooping])" in thread
    assert "[NSThread sleepUntilDate:" in thread


def test_progress_indicator_animation_timer_can_be_started_and_stopped():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    source = (appkit / "NSProgressIndicator.m").read_text()

    start = source.rsplit("- (void)_startAnimationWithThread:(BOOL)threaded", 1)[1].split("\n}", 1)[0]
    assert "if (_isIndeterminate && !_timer && ![self _isThreadedAnimationLooping])" in start
    assert "[NSTimer timerWithTimeInterval:_animationDelay" in start
    assert "selector:@selector(_animationIdler:)" in start
    assert "[[NSRunLoop currentRunLoop] addTimer:_timer forMode:NSDefaultRunLoopMode];" in start
    assert "[NSThread detachNewThreadSelector:@selector(_animationThread)" in start

    stop = source.rsplit("- (void)stopAnimation:(id)sender", 1)[1].split("\n}", 1)[0]
    assert "if (_isIndeterminate)" in stop
    assert "_progressIndicatorFlags.isSpinning = NO;" in stop
    assert "[_timer invalidate];" in stop
    assert "_timer = nil;" in stop


def test_progress_indicator_cached_image_lock_and_draw_dispatch_match_reference():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    selectors = (
        "-[NSProgressIndicator _compositeAndUnlockCachedImage]",
        "-[NSProgressIndicator _createCachedImage:]",
        "-[NSProgressIndicator _creteCachedImageLockIfNeeded]",
        "-[NSProgressIndicator _lockCachedImage]",
        "-[NSProgressIndicator _lockUnlockCachedImage:]",
        "-[NSProgressIndicator drawRect:]",
    )
    assert set(selectors) <= methods

    source = (appkit / "NSProgressIndicator.m").read_text()
    lock = source.rsplit("- (id)_lockCachedImage", 1)[1].split("\n}", 1)[0]
    assert "NSRect bounds = [self bounds];" in lock
    assert "[self _lockUnlockCachedImage:YES];" in lock
    assert "NSEqualSizes([_cachedImage size], bounds.size)" in lock
    assert "[_cachedImage setSize:bounds.size];" in lock
    assert "[self _createCachedImage:bounds.size];" in lock

    create = source.rsplit("- (void)_createCachedImage:(NSSize)size", 1)[1].split("\n}", 1)[0]
    assert "[[NSImage allocWithZone:[self zone]] initWithSize:size]" in create
    assert "[_cachedImage setScalesWhenResized:YES];" in create

    draw = source.rsplit("- (void)drawRect:(NSRect)rect", 1)[1].split("\n}", 1)[0]
    assert "id image = [self _lockCachedImage];" in draw
    assert "[image lockFocus];" in draw
    assert "if (_isIndeterminate)" in draw
    assert "[self _drawAnimationStep];" in draw
    assert "[self _drawProgressArea];" in draw
    assert "[self _drawRemainderArea];" in draw
    assert "[image unlockFocus];" in draw
    assert "[self _compositeAndUnlockCachedImage];" in draw


def test_progress_indicator_determinate_geometry_matches_reference():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    selectors = (
        "-[NSProgressIndicator _getGaugeFrame]",
        "-[NSProgressIndicator _getPosition:]",
        "-[NSProgressIndicator _getProgressFrame]",
        "-[NSProgressIndicator _getRemainderFrame]",
    )
    assert set(selectors) <= methods

    source = (appkit / "NSProgressIndicator.m").read_text()
    gauge = source.rsplit("- (NSRect)_getGaugeFrame", 1)[1].split("\n}", 1)[0]
    assert "NSInterfaceStyleForKey(NSInterfaceStyleDefault, nil) == NSWindows95InterfaceStyle" in gauge
    assert "|| !_isBezeled ? 1.0 : 2.0" in gauge

    position = source.rsplit("- (CGFloat)_getPosition:(double)value", 1)[1].split("\n}", 1)[0]
    assert "floor(gauge.size.width * (value - _minimum) / (_maximum - _minimum) + gauge.origin.x + 0.5)" in position
    assert "if (position >= end)" in position

    progress = source.rsplit("- (NSRect)_getProgressFrame", 1)[1].split("\n}", 1)[0]
    assert "[self _getPosition:_value]" in progress
    assert "height * 0.75" in progress
    assert "(width + pixel - 1.0) / pixel" in progress

    remainder = source.rsplit("- (NSRect)_getRemainderFrame", 1)[1].split("\n}", 1)[0]
    assert "[self _getPosition:_value]" in remainder
    assert "height * 0.75" in remainder
    assert "(position - frame.origin.x + pixel - 1.0) / pixel" in remainder


def test_progress_indicator_windows_gauge_and_system_color_dispatch_match_reference():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    assert "-[NSProgressIndicator _drawWindowsGaugeRects:]" in methods
    assert "-[NSProgressIndicator _systemColorChanged:]" in methods

    source = (appkit / "NSProgressIndicator.m").read_text()
    gauge = source.rsplit("- (void)_drawWindowsGaugeRects:(NSRect)rect", 1)[1].split("\n}", 1)[0]
    assert "if (!NSIsEmptyRect(rect))" in gauge
    assert "floor(rect.size.height * 0.75)" in gauge
    assert "[NSColor controlColor]" in gauge
    assert "[NSColor progressIndicatorColor]" in gauge
    assert "NSInsetRect(stripe, 1.0, 1.0)" in gauge

    color = source.rsplit("- (void)_systemColorChanged:(id)notification", 1)[1].split("\n}", 1)[0]
    assert "[self display];" in color


def test_progress_indicator_determinate_drawing_helpers_match_reference():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    selectors = (
        "-[NSProgressIndicator _drawFrame]",
        "-[NSProgressIndicator _drawRemainderArea]",
        "-[NSProgressIndicator _fillGrayRect:with:]",
    )
    assert set(selectors) <= methods

    source = (appkit / "NSProgressIndicator.m").read_text()
    frame = source.rsplit("- (void)_drawFrame", 1)[1].split("\n}", 1)[0]
    assert "NSInterfaceStyleForKey(NSInterfaceStyleDefault, nil) == NSWindows95InterfaceStyle" in frame
    assert "[NSColor controlShadowColor]" in frame
    assert "[NSColor whiteColor]" in frame
    assert "[NSColor blackColor]" in frame
    assert "NSFrameRect(NSInsetRect([self bounds], 1.0, 1.0));" in frame

    remainder = source.rsplit("- (void)_drawRemainderArea", 1)[1].split("\n}", 1)[0]
    assert "[self _getRemainderFrame]" in remainder
    assert "[[NSColor controlColor] set];" in remainder
    assert "[self _fillGrayRect:&frame with:4];" in remainder
    assert "[self _fillGrayRect:&frame with:3];" in remainder
    assert "[self _fillGrayRect:&frame with:0];" in remainder
    assert "[self _fillGrayRect:&frame with:2];" in remainder


def test_progress_indicator_progress_and_indeterminate_drawing_paths_match_reference():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    assert "-[NSProgressIndicator _drawProgressArea]" in methods
    assert "-[NSProgressIndicator _drawAnimationStep]" in methods

    source = (appkit / "NSProgressIndicator.m").read_text()
    progress = source.rsplit("- (void)_drawProgressArea", 1)[1].split("\n}", 1)[0]
    assert "[self _getProgressFrame]" in progress
    assert "[self _drawWindowsGaugeRects:frame];" in progress
    assert "[NSProgressIndicator _barberImage:frame.size.height]" in progress
    assert "NSCompositeSourceOver" in progress

    animation = source.rsplit("- (void)_drawAnimationStep", 1)[1].split("\n}", 1)[0]
    assert "[self _getGaugeFrame]" in animation
    assert "[self _drawWindowsGaugeRects:segment];" in animation
    assert "[NSProgressIndicator _gaugeImage:frame.size.height]" in animation
    assert "_animationIndex %= 4;" in animation


def test_progress_indicator_class_image_factories_match_reference():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    selectors = (
        "+[NSProgressIndicator _barberImage:]",
        "+[NSProgressIndicator _createImage:::]",
        "+[NSProgressIndicator _gaugeImage:]",
    )
    assert set(selectors) <= methods

    source = (appkit / "NSProgressIndicator.m").read_text()
    barber = source.rsplit("+ (NSImage *)_barberImage:(CGFloat)height", 1)[1].split("\n}", 1)[0]
    assert '"BarberPole"' in barber
    assert "_createImage:" in barber
    gauge = source.rsplit("+ (NSImage *)_gaugeImage:(CGFloat)height", 1)[1].split("\n}", 1)[0]
    assert '"GaugePole"' in gauge
    assert "_createImage:" in gauge
    create = source.rsplit("+ (NSImage *)_createImage:", 1)[1].split("\n}", 1)[0]
    assert "[cache objectForKey:key]" in create
    assert "pathForImageResource:name" in create
    assert "[image setSize:size];" in create
