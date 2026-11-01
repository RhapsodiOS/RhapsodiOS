from pathlib import Path

from selector_check import source_methods


def test_hides_on_deactivate_updates_window_cache_and_server_state():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    selector = "-[NSWindow setHidesOnDeactivate:]"
    assert selector in methods

    source = (appkit / "NSWindow.m").read_text()
    body = source.rsplit("- (void)setHidesOnDeactivate:(BOOL)flag", 1)[1].split("\n}", 1)[0]
    assert 'NSGetBooleanDefault("NSHideOnDeactivateEnabled")' in body
    assert "flag == NO || NSWindowHidesOnDeactivateEnabled" in body
    assert "_wFlags.hidesOnDeactivate = flag;" in body
    assert "_wFlags.haveFreeCursorRects = NO;" in body
    assert "[NSApp _setHidesOnDeactivateInCache:flag forWindow:self]" in body
    assert "_NSSetHidesOnDeactivate([self context], flag, _wFlags.visible);" in body
    assert "_NSAppKitLock" in body
    assert "_NSAppKitUnlock" in body
