from pathlib import Path

from selector_check import source_methods


def test_unhide_without_activation_restores_hidden_windows_in_reference_order():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    assert "-[NSApplication unhideWithoutActivation]" in methods
    assert "-[NSApplication(NSWindowCache) _makeHODWindowsPerform:]" in methods
    assert "-[NSWindow _tempUnhideHODWindow]" in methods
    assert "-[NSWindow _canHide]" in methods

    source = (appkit / "NSApplication.m").read_text()
    cache_body = source.rsplit("- (void)_makeHODWindowsPerform:", 1)[1].split("\n}", 1)[0]
    assert "_NSAppKitLock(256" in cache_body
    assert "0xA0000000U) == 0x20000000U" in cache_body
    assert "_NSAppKitUnlock(264" in cache_body

    body = source.rsplit("- (void)unhideWithoutActivation", 1)[1].split("\n}", 1)[0]
    assert "_appFlags._doingUnhide" in body
    assert "_appFlags._hidden" in body
    assert "_NXReorderWindows()" in body
    assert body.index("NSApplicationWillUnhideNotification") < body.index("NS_DURING")
    assert "window != _appIcon" in body
    assert "[window styleMask] & 0x10000000" in body
    assert "[window _canHide]" in body
    assert "[window _tempHide:NO relWin:relativeWindow]" in body
    assert "@selector(_tempUnhideHODWindow)" in body
    assert "NSZoneFree([self zone], _hiddenList)" in body
    assert "_hiddenList = NULL" in body
    assert "_hiddenCount = 0" in body
    assert "_NXOrderKeyAndMain()" in body
    assert "NSApplicationDidUnhideNotification" in body
    assert "[localException raise]" in body


def test_window_temporary_hide_preserves_relative_order_when_restored():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    assert "-[NSWindow _tempHide:relWin:]" in methods

    source = (appkit / "NSWindow.m").read_text()
    body = source.rsplit("- (id)_tempHide:(BOOL)hide relWin:(int)relativeWindow", 1)[1].split("\n}", 1)[0]
    assert "_wFlags.visible" in body
    assert "[self orderOut:nil]" in body
    assert "_wFlags.tempHidden = YES" in body
    assert "[self orderWindow:NSWindowBelow relativeTo:relativeWindow]" in body
    assert "[self orderWindow:NSWindowAbove relativeTo:0]" in body
    assert "_wFlags.tempHidden = NO" in body
