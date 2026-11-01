from pathlib import Path

from selector_check import source_methods


def test_window_simple_state_methods_match_reference_ivars():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    selectors = (
        "-[NSWindow firstResponder]",
        "-[NSWindow contentView]",
        "-[NSWindow representedFilename]",
        "-[NSWindow delegate]",
        "-[NSWindow backgroundColor]",
        "-[NSWindow initialFirstResponder]",
        "-[NSWindow frameAutosaveName]",
        "-[NSWindow miniwindowImage]",
        "-[NSWindow acceptsMouseMovedEvents]",
        "-[NSWindow areCursorRectsEnabled]",
        "-[NSWindow keyViewSelectionDirection]",
        "-[NSWindow useOptimizedDrawing:]",
        "-[NSWindow setInitialFirstResponder:]",
        "-[NSWindow _setCounterpart:]",
        "-[NSWindow _postingEnabled]",
        "-[NSWindow _disablePosting]",
        "-[NSWindow _setWantsToBeOnMainScreen:]",
    )
    assert set(selectors) <= methods

    source = (appkit / "NSWindow.m").read_text()
    expected_bodies = {
        "- (NSResponder *)firstResponder": "return _firstResponder;",
        "- (id)contentView": "return _contentView;",
        "- (NSString *)representedFilename": "return _representedFilename;",
        "- (id)delegate": "return _delegate;",
        "- (NSColor *)backgroundColor": "return _backgroundColor;",
        "- (NSView *)initialFirstResponder": "return _initialFirstResponder;",
        "- (NSString *)frameAutosaveName": "return _frameSaveName;",
        "- (NSImage *)miniwindowImage": "return _miniIcon;",
        "- (BOOL)acceptsMouseMovedEvents": "return (_winEventMask & 0x20) != 0;",
        "- (BOOL)areCursorRectsEnabled": "return !_wFlags.cursorRectsDisabled;",
        "- (NSSelectionDirection)keyViewSelectionDirection": "return _wFlags.keyViewSelectionDirection;",
        "- (void)useOptimizedDrawing:(BOOL)flag": "_wFlags.optimizeDrawing = flag;",
        "- (void)setInitialFirstResponder:(NSView *)view": "_initialFirstResponder = view;",
        "- (id)_setCounterpart:(id)counterpart": "_counterpart = counterpart;",
        "- (BOOL)_postingEnabled": "return _postingDisabled == 0;",
        "- (void)_disablePosting": "++_postingDisabled;",
        "- (void)_setWantsToBeOnMainScreen:(BOOL)flag": "_wFlags.wantsToBeOnMainScreen = flag;",
    }
    for signature, expected in expected_bodies.items():
        body = source.rsplit(signature, 1)[1].split("\n}", 1)[0]
        assert expected in body


def test_window_private_state_helpers_match_reference_flags():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    selectors = (
        "-[NSWindow _wantsToDestroyRealWindow]",
        "-[NSWindow hasDynamicDepthLimit]",
        "-[NSWindow _counterpart]",
        "-[NSWindow _getCounterpart]",
        "-[NSWindow _borderView]",
        "-[NSWindow _lastLeftHit]",
        "-[NSWindow _lastRightHit]",
        "-[NSWindow _avoidsActivation]",
        "-[NSWindow _isTerminating]",
        "-[NSWindow _makingFirstResponderForMouseDown]",
        "-[NSWindow _titleIsRepresentedFilename]",
        "-[NSWindow _wantToBeModal]",
        "-[NSWindow _windowDying]",
        "-[NSWindow becomesKeyOnlyIfNeeded]",
        "-[NSWindow _resetDisableCounts]",
        "-[NSWindow _setNeedsZoom:]",
        "-[NSWindow _setShowingModalFrame:]",
        "-[NSWindow _setWin32MouseActivationInProgress:]",
        "-[NSWindow _setOneShotIsDelayed:]",
    )
    assert set(selectors) <= methods

    source = (appkit / "NSWindow.m").read_text()
    expected_bodies = {
        "- (BOOL)_wantsToDestroyRealWindow": "return _wFlags.wantsToDestroyRealWindow;",
        "- (BOOL)hasDynamicDepthLimit": "return _wFlags.dynamicDepthLimit;",
        "- (id)_counterpart": "return _counterpart;",
        "- (id)_getCounterpart": "return _counterpart;",
        "- (id)_borderView": "return _borderView;",
        "- (id)_lastLeftHit": "return _lastLeftHit;",
        "- (id)_lastRightHit": "return _lastRightHit;",
        "- (BOOL)_avoidsActivation": "return _wFlags.avoidsActivation;",
        "- (BOOL)_isTerminating": "return _wFlags.isTerminating;",
        "- (BOOL)_makingFirstResponderForMouseDown": "return _wFlags.makingFirstResponderForMouseDown;",
        "- (BOOL)_titleIsRepresentedFilename": "return _wFlags.titleIsRepresentedFilename;",
        "- (BOOL)_wantToBeModal": "return _wFlags.wantsToBeModal;",
        "- (BOOL)_windowDying": "return _wFlags.windowDying;",
        "- (BOOL)becomesKeyOnlyIfNeeded": "return NO;",
        "- (id)_resetDisableCounts": "_flushDisabled = 0;",
        "- (id)_setNeedsZoom:(id)flag": "_wFlags.needsZoom = YES;",
        "- (void)_setShowingModalFrame:(BOOL)flag": "_wFlags.showingModalFrame = flag;",
        "- (void)_setWin32MouseActivationInProgress:(BOOL)flag": "_wFlags.win32MouseActivationInProgress = flag;",
        "- (id)_setOneShotIsDelayed:(BOOL)flag": "_wFlags.delayedOneShot = flag;",
    }
    for signature, expected in expected_bodies.items():
        body = source.rsplit(signature, 1)[1].split("\n}", 1)[0]
        assert expected in body


def test_window_geometry_constraints_delegate_to_frame_and_counterpart():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    selectors = (
        "-[NSWindow aspectRatio]",
        "-[NSWindow setAspectRatio:]",
        "-[NSWindow resizeIncrements]",
        "-[NSWindow setResizeIncrements:]",
        "-[NSWindow resizeFlags]",
        "-[NSWindow convertBaseToScreen:]",
        "-[NSWindow convertScreenToBase:]",
        "-[NSWindow miniwindowTitle]",
        "-[NSWindow setMiniwindowTitle:]",
    )
    assert set(selectors) <= methods

    source = (appkit / "NSWindow.m").read_text()
    expected_bodies = {
        "- (NSSize)aspectRatio": "return [_borderView aspectRatio];",
        "- (void)setAspectRatio:(NSSize)ratio": "[_borderView setAspectRatio:ratio];",
        "- (NSSize)resizeIncrements": "return [_borderView resizeIncrements];",
        "- (void)setResizeIncrements:(NSSize)increments": "[_borderView setResizeIncrements:increments];",
        "- (int)resizeFlags": "return [_borderView resizeFlags];",
        "- (NSPoint)convertBaseToScreen:(NSPoint)point": "_frame.origin.x + point.x",
        "- (NSPoint)convertScreenToBase:(NSPoint)point": "point.x - _frame.origin.x",
        "- (NSString *)miniwindowTitle": "return [_counterpart miniwindowTitle];",
        "- (void)setMiniwindowTitle:(NSString *)title": "[_counterpart setMiniwindowTitle:title];",
    }
    for signature, expected in expected_bodies.items():
        body = source.rsplit(signature, 1)[1].split("\n}", 1)[0]
        assert expected in body
    title_setter = source.rsplit("- (void)setMiniwindowTitle:(NSString *)title", 1)[1].split("\n}", 1)[0]
    assert 'NSInterfaceStyleForKey(@"NSWindowInterfaceStyle", self) != 3' in title_setter


def test_window_frame_and_event_forwarding_match_reference():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    selectors = (
        "-[NSWindow frame]",
        "-[NSWindow currentEvent]",
        "-[NSWindow performKeyEquivalent:]",
        "-[NSWindow postEvent:atStart:]",
    )
    assert set(selectors) <= methods

    source = (appkit / "NSWindow.m").read_text()
    expected_bodies = {
        "- (NSRect)frame": "return _frame;",
        "- (NSEvent *)currentEvent": "return [NSApp currentEvent];",
        "- (BOOL)performKeyEquivalent:(NSEvent *)event": "return [_contentView performKeyEquivalent:event];",
        "- (void)postEvent:(NSEvent *)event atStart:(BOOL)flag": "[NSApp postEvent:event atStart:flag];",
    }
    for signature, expected in expected_bodies.items():
        body = source.rsplit(signature, 1)[1].split("\n}", 1)[0]
        assert expected in body


def test_window_mouse_moved_event_toggle_updates_server_and_event_mask():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    assert "-[NSWindow setAcceptsMouseMovedEvents:]" in methods

    source = (appkit / "NSWindow.m").read_text()
    setter = source.rsplit("- (void)setAcceptsMouseMovedEvents:(BOOL)flag", 1)[1].split("\n}", 1)[0]
    assert "if (_windowNum > 0)" in setter
    assert "_NSEnableMouseMovedEventsForWindow([self context])" in setter
    assert "_NSDisableMouseMovedEventsForWindow([self context])" in setter
    assert "_winEventMask |= 0x20;" in setter
    assert "_winEventMask = 0;" in setter


def test_window_auxiliary_and_size_accessors_match_reference_fields():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    selectors = (
        "-[NSWindow _auxStorage]",
        "-[NSWindow _isImageCache]",
        "-[NSWindow minSize]",
        "+[NSWindow defaultDepthLimit]",
    )
    assert set(selectors) <= methods

    source = (appkit / "NSWindow.m").read_text()
    expected_bodies = {
        "- (NSWindowAuxiliaryOpaque *)_auxStorage": "return _auxiliaryStorage;",
        "- (BOOL)_isImageCache": "return _wFlags.isImageCache;",
        "- (NSSize)minSize": "return _sizeLimits[0];",
        "+ (NSWindowDepth)defaultDepthLimit": "return _NXDefaultWindowDepthLimit();",
    }
    for signature, expected in expected_bodies.items():
        body = source.rsplit(signature, 1)[1].split("\n}", 1)[0]
        assert expected in body
    min_size = source.rsplit("- (NSSize)minSize", 1)[1].split("\n}", 1)[0]
    assert "if (_sizeLimits != 0)" in min_size
    assert "return NSZeroSize;" in min_size
