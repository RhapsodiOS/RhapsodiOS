from pathlib import Path

from selector_check import source_methods


def _appkit_and_methods():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    return appkit, {entry[0] for entry in source_methods(appkit)}


def test_window_number_changes_update_modal_sessions_and_hidden_windows():
    appkit, methods = _appkit_and_methods()
    assert "-[NSApplication _windowNumber:changedTo:]" in methods
    assert "-[NSApplication _removeHiddenWindow:]" in methods

    source = (appkit / "NSApplication.m").read_text()
    body = source.rsplit("- (void)_windowNumber:(int)oldWindowNumber changedTo:(int)newWindowNumber", 1)[1].split("\n}", 1)[0]
    assert "_NXLastModalSession" in body
    assert "session->windowNumber == oldWindowNumber" in body
    assert "session->windowNumber = newWindowNumber" in body
    assert "newWindowNumber == -1" in body
    assert "[self _removeHiddenWindow:oldWindowNumber]" in body
    assert "_hiddenList[index] = newWindowNumber" in body

    remove_body = source.rsplit("- (id)_removeHiddenWindow:(int)windowNumber", 1)[1].split("\n}", 1)[0]
    assert "_hiddenCount - 1" in remove_body
    assert "memmove" in remove_body
    assert "_hiddenCount--" in remove_body


def test_window_number_lookup_uses_valid_window_cache_entries():
    appkit, methods = _appkit_and_methods()
    assert "-[NSApplication(NSWindowCache) _findWindowUsingCache:]" in methods
    assert "-[NSApplication windowWithWindowNumber:]" in methods

    source = (appkit / "NSApplication.m").read_text()
    body = source.rsplit("- (id)_findWindowUsingCache:(int)windowNumber", 1)[1].split("\n}", 1)[0]
    assert "_windowCache == nil" in body
    assert "mutableBytes" in body
    assert "sizeof(*entries)" in body
    assert "(int)entries[index].flags < 0" in body
    assert "entries[index].windowNumber != windowNumber" in body
    assert "_NSAppKitLock(85" in body
    assert "_NSAppKitUnlock(91" in body
    assert "_NSAppKitUnlock(96" in body

    wrapper = source.rsplit("- (NSWindow *)windowWithWindowNumber:(int)windowNum", 1)[1].split("\n}", 1)[0]
    assert "[self _findWindowUsingCache:windowNum]" in wrapper


def test_window_cache_lookup_reuses_tombstones_and_grows_by_one_entry():
    appkit, methods = _appkit_and_methods()
    assert "-[NSApplication(NSWindowCache) _getWindowCache:add:]" in methods

    source = (appkit / "NSApplication.m").read_text()
    body = source.rsplit("- (NSApplicationWindowCacheEntry *)_getWindowCache:(id)window add:(BOOL)add", 1)[1].split("\n}", 1)[0]
    assert "initWithCapacity:96" in body
    assert "entries[index].flags < 0" in body
    assert "entries[index].window == window" in body
    assert "memset(entry, 0, sizeof(*entry))" in body
    assert "setLength:length + sizeof(*entries)" in body


def test_application_window_list_add_remove_and_enumeration_match_reference():
    appkit, methods = _appkit_and_methods()
    selectors = (
        "-[NSApplication _addWindow:]",
        "-[NSApplication _removeWindow:]",
        "-[NSApplication windows]",
    )
    assert set(selectors) <= methods

    source = (appkit / "NSApplication.m").read_text()
    add = source.rsplit("- (id)_addWindow:(id)window", 1)[1].split("\n}", 1)[0]
    assert "[window windowNumber]" in add
    assert "[_windowList indexOfObject:windowNumber] == NSNotFound" in add
    assert "[_windowList addObject:windowNumber];" in add

    remove = source.rsplit("- (id)_removeWindow:(id)window", 1)[1].split("\n}", 1)[0]
    assert "[_windowList removeObject:windowNumber];" in remove
    assert "if (_keyWindow == window)" in remove
    assert "if (_mainWindow == window)" in remove
    assert "[self _removeWindowFromCache:window];" in remove

    windows = source.rsplit("- (NSArray *)windows", 1)[1].split("\n}", 1)[0]
    assert "[_windowList objectAtIndex:index]" in windows
    assert "intValue" in windows
    assert "[self windowWithWindowNumber:" in windows
