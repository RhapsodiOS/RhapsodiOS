from pathlib import Path

from selector_check import source_methods


def test_window_state_accessors_return_reference_backed_fields():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    selectors = (
        "-[NSWindow windowNumber]",
        "-[NSWindow isVisible]",
        "-[NSWindow hidesOnDeactivate]",
        "-[NSWindow isOneShot]",
        "-[NSWindow isFlushWindowDisabled]",
        "-[NSWindow viewsNeedDisplay]",
        "-[NSWindow isAutodisplay]",
        "-[NSWindow isDocumentEdited]",
        "-[NSWindow isExcludedFromWindowsMenu]",
        "-[NSWindow worksWhenModal]",
        "-[NSWindow backingType]",
        "-[NSWindow level]",
        "-[NSWindow depthLimit]",
        "-[NSWindow isReleasedWhenClosed]",
        "-[NSApplication isRunning]",
    )
    assert set(selectors) <= methods

    window_source = (appkit / "NSWindow.m").read_text()
    application_source = (appkit / "NSApplication.m").read_text()
    expected_bodies = {
        "- (int)windowNumber": "return _windowNum;",
        "- (BOOL)isVisible": "return _wFlags.visible;",
        "- (BOOL)hidesOnDeactivate": "return _wFlags.hidesOnDeactivate;",
        "- (BOOL)isOneShot": "return _wFlags.oneShot;",
        "- (BOOL)isFlushWindowDisabled": "return _flushDisabled != 0;",
        "- (BOOL)viewsNeedDisplay": "return _wFlags.viewsNeedDisplay;",
        "- (BOOL)isAutodisplay": "return _wFlags.autodisplay;",
        "- (BOOL)isDocumentEdited": "return _wFlags.docEdited;",
        "- (BOOL)isExcludedFromWindowsMenu": "return _wFlags.excludedFromWindowsMenu;",
        "- (BOOL)worksWhenModal": "return NO;",
        "- (NSBackingStoreType)backingType": "return (NSBackingStoreType)_wFlags.backing;",
        "- (int)level": "return _level;",
        "- (NSWindowDepth)depthLimit": "if (_wFlags.depthLimit != 0)",
        "- (BOOL)isReleasedWhenClosed": "return !_wFlags.dontFreeWhenClosed;",
    }
    for signature, expected in expected_bodies.items():
        body = window_source.rsplit(signature, 1)[1].split("\n}", 1)[0]
        assert expected in body

    depth_limit = window_source.rsplit("- (NSWindowDepth)depthLimit", 1)[1].split("\n}", 1)[0]
    assert "NSAvailableWindowDepths()[_wFlags.depthLimit - 1]" in depth_limit
    assert "return 0;" in depth_limit

    running = application_source.rsplit("- (BOOL)isRunning", 1)[1].split("\n}", 1)[0]
    assert "return _running > 0;" in running


def test_window_boolean_setters_update_reference_backed_flags():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    selectors = (
        "-[NSWindow setOneShot:]",
        "-[NSWindow setAutodisplay:]",
        "-[NSWindow setExcludedFromWindowsMenu:]",
        "-[NSWindow setReleasedWhenClosed:]",
    )
    assert set(selectors) <= methods

    source = (appkit / "NSWindow.m").read_text()
    expected_bodies = {
        "- (void)setOneShot:(BOOL)flag": "_wFlags.oneShot = flag;",
        "- (void)setAutodisplay:(BOOL)flag": "_wFlags.autodisplay = flag;",
        "- (void)setExcludedFromWindowsMenu:(BOOL)flag": "_wFlags.excludedFromWindowsMenu = flag;",
        "- (void)setReleasedWhenClosed:(BOOL)flag": "_wFlags.dontFreeWhenClosed = !flag;",
    }
    for signature, expected in expected_bodies.items():
        body = source.rsplit(signature, 1)[1].split("\n}", 1)[0]
        assert expected in body


def test_window_display_flags_and_flush_counter_match_reference():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    selectors = (
        "-[NSWindow setViewsNeedDisplay:]",
        "-[NSWindow disableFlushWindow]",
    )
    assert set(selectors) <= methods

    source = (appkit / "NSWindow.m").read_text()
    views = source.rsplit("- (void)setViewsNeedDisplay:(BOOL)flag", 1)[1].split("\n}", 1)[0]
    assert "_wFlags.viewsNeedDisplay = flag;" in views
    assert "_wFlags.autodisplay" in views
    assert "[self isVisible]" in views
    assert "[self displayIfNeeded]" in views

    flush = source.rsplit("- (void)disableFlushWindow", 1)[1].split("\n}", 1)[0]
    assert "++_flushDisabled;" in flush


def test_window_key_state_and_flush_reenable_match_reference():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    selectors = (
        "-[NSWindow styleMask]",
        "-[NSWindow canBecomeKeyWindow]",
        "-[NSWindow isKeyWindow]",
        "-[NSWindow isMainWindow]",
        "-[NSWindow enableFlushWindow]",
    )
    assert set(selectors) <= methods

    source = (appkit / "NSWindow.m").read_text()
    style = source.rsplit("- (unsigned int)styleMask", 1)[1].split("\n}", 1)[0]
    assert "[_borderView styleMask]" in style
    assert "return _styleMask;" in style

    can_become_key = source.rsplit("- (BOOL)canBecomeKeyWindow", 1)[1].split("\n}", 1)[0]
    assert "[self styleMask] & (NSTitledWindowMask | NSResizableWindowMask)" in can_become_key

    for signature, field in (
        ("- (BOOL)isKeyWindow", "_wFlags.isKeyWindow"),
        ("- (BOOL)isMainWindow", "_wFlags.isMainWindow"),
    ):
        body = source.rsplit(signature, 1)[1].split("\n}", 1)[0]
        assert field in body
        assert "[NSApp isActive]" in body

    enable = source.rsplit("- (void)enableFlushWindow", 1)[1].split("\n}", 1)[0]
    assert "if (_flushDisabled != 0)" in enable
    assert "--_flushDisabled;" in enable
    assert "NSLog(@\"[NSWindow enableFlushWindow]" in enable


def test_window_level_and_backing_type_reach_the_server_for_numbered_windows():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    selectors = ("-[NSWindow setLevel:]", "-[NSWindow setBackingType:]")
    assert set(selectors) <= methods

    source = (appkit / "NSWindow.m").read_text()
    level = source.rsplit("- (void)setLevel:(int)newLevel", 1)[1].split("\n}", 1)[0]
    assert "_level = newLevel;" in level
    assert "if (_windowNum > 0)" in level
    assert "PSsetwindowlevel(newLevel, _windowNum);" in level

    backing = source.rsplit("- (void)setBackingType:(NSBackingStoreType)bufferingType", 1)[1].split("\n}", 1)[0]
    assert "_wFlags.backing = bufferingType;" in backing
    assert "if (_windowNum > 0)" in backing
    assert "PSsetwindowtype(bufferingType, _windowNum);" in backing
