from pathlib import Path

from selector_check import source_methods


def _appkit_and_methods():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    return appkit, {entry[0] for entry in source_methods(appkit)}


def test_window_cache_mutators_preserve_reference_flag_fields():
    appkit, methods = _appkit_and_methods()
    selectors = (
        "-[NSApplication(NSWindowCache) _setCacheWindowNum:forWindow:]",
        "-[NSApplication(NSWindowCache) _setHidesOnDeactivateInCache:forWindow:]",
        "-[NSApplication(NSWindowCache) _setVisibleInCache:forWindow:]",
        "-[NSApplication(NSWindowCache) _removeWindowFromCache:]",
        "-[NSApplication(NSWindowCache) _isVisibleUsingCache:]",
    )
    for selector in selectors:
        assert selector in methods

    source = (appkit / "NSApplication.m").read_text()
    number = source.rsplit("- (void)_setCacheWindowNum:(int)windowNumber forWindow:(id)window", 1)[1].split("\n}", 1)[0]
    assert "entry->windowNumber = windowNumber" in number

    hides = source.rsplit("- (void)_setHidesOnDeactivateInCache:(BOOL)hidesOnDeactivate forWindow:(id)window", 1)[1].split("\n}", 1)[0]
    assert "0x20000000U" in hides
    assert "_getWindowCache:window add:YES" in hides

    visible = source.rsplit("- (void)_setVisibleInCache:(BOOL)visible forWindow:(id)window", 1)[1].split("\n}", 1)[0]
    assert "0x40000000U" in visible
    assert "_getWindowCache:window add:YES" in visible
    assert "_checkForTerminateAfterLastWindowClosed:" in visible

    remove = source.rsplit("- (void)_removeWindowFromCache:(id)window", 1)[1].split("\n}", 1)[0]
    assert "0x80000000U" in remove
    assert "_getWindowCache:window add:NO" in remove

    is_visible = source.rsplit("- (BOOL)_isVisibleUsingCache:(id)window", 1)[1].split("\n}", 1)[0]
    assert "_getWindowCache:window add:NO" in is_visible
    assert "0x40000000U" in is_visible


def test_last_window_close_scheduling_matches_application_policy():
    appkit, methods = _appkit_and_methods()
    assert "-[NSApplication(NSWindowCache) _checkForTerminateAfterLastWindowClosed:]" in methods

    source = (appkit / "NSApplication.m").read_text()
    body = source.rsplit("- (void)_checkForTerminateAfterLastWindowClosed:(id)window", 1)[1].split("\n}", 1)[0]
    assert "_isWindowObjectInCache(self, _windowCache)" in body
    assert "applicationShouldTerminateAfterLastWindowClosed:" in body
    assert "[self terminate:self]" in body


def test_update_windows_using_cache_only_updates_visible_cache_entries():
    appkit, methods = _appkit_and_methods()
    selector = "-[NSApplication(NSWindowCache) _updateWindowsUsingCache]"
    assert selector in methods

    source = (appkit / "NSApplication.m").read_text()
    body = source.rsplit("- (void)_updateWindowsUsingCache", 1)[1].split("\n}", 1)[0]
    assert "[_windowCache length] / sizeof(*entries)" in body
    assert "(entries[index].flags & 0xC0000000U) == 0x40000000U" in body
    assert "[entries[index].window update]" in body


def test_public_update_windows_posts_notifications_around_visible_updates():
    appkit, methods = _appkit_and_methods()
    selector = "-[NSApplication updateWindows]"
    assert selector in methods

    source = (appkit / "NSApplication.m").read_text()
    body = source.rsplit("- (void)updateWindows", 1)[1].split("\n}", 1)[0]
    assert "NSApplicationWillUpdateNotification" in body
    assert "[self _updateWindowsUsingCache]" in body
    assert "NSApplicationDidUpdateNotification" in body
    assert body.index("NSApplicationWillUpdateNotification") < body.index("_updateWindowsUsingCache")
    assert body.index("_updateWindowsUsingCache") < body.index("NSApplicationDidUpdateNotification")
