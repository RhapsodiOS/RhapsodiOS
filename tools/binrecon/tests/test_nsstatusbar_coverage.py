from pathlib import Path

from selector_check import source_methods


def test_status_bar_implements_registered_selectors_and_backend_behavior():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    selectors = {
        "+[NSStatusBar systemStatusBar]",
        "-[NSStatusBar isVertical]",
        "-[NSStatusBar removeStatusItem:]",
        "-[NSStatusBar statusItemWithLength:]",
        "-[NSStatusBar thickness]",
        "-[NSStatusBar(NSStatusBarDPS) _DPSadjustWindows]",
        "-[NSStatusBar(NSStatusBarDPS) _DPSinsertWindow:withPriority:]",
        "-[NSStatusBar(NSStatusBarDPS) _DPSremoveWindow:]",
        "-[NSStatusBar(NSStatusBarDPS) _DPSsetupInfo]",
        "-[NSStatusBar(NSStatusBarDPS) _cornerLocationForWindowWithSize:]",
        "-[NSStatusBar(NSStatusBar_Appearance) _createStatusItemControlInWindow:]",
        "-[NSStatusBar(NSStatusBar_Appearance) _createStatusItemWindow]",
        "-[NSStatusBar(NSStatusBar_Appearance) _direction]",
        "-[NSStatusBar(NSStatusBar_Appearance) _initialOffset]",
        "-[NSStatusBar(NSStatusBar_Appearance) _lengthForSize:]",
        "-[NSStatusBar(NSStatusBar_Appearance) _placement]",
        "-[NSStatusBar(NSStatusBar_Appearance) drawBackgroundInRect:inView:highlight:]",
        "-[NSStatusBar(NSStatusBar_Private) _init]",
        "-[NSStatusBar(NSStatusBar_Private) _insertStatusItemWindow:withPriority:]",
        "-[NSStatusBar(NSStatusBar_Private) _lockName]",
        "-[NSStatusBar(NSStatusBar_Private) _name]",
        "-[NSStatusBar(NSStatusBar_Private) _refreshWindows]",
        "-[NSStatusBar(NSStatusBar_Private) _removeStatusItemWindow:]",
        "-[NSStatusBar(NSStatusBar_Private) _setLength:ofStatusItemWindow:]",
        "-[NSStatusBar(NSStatusBar_Private) _statusItemWithLength:withPriority:]",
        "-[NSStatusBarButton highlightMode]",
        "-[NSStatusBarButton initWithFrame:inStatusBar:]",
        "-[NSStatusBarButton setHighlightMode:]",
        "-[NSStatusBarButton setStatusMenu:]",
        "-[NSStatusBarButton statusMenu]",
        "-[NSStatusBarButtonCell _fillBackground:withAlternateColor:]",
        "-[NSStatusBarButtonCell _textHighlightColor]",
        "-[NSStatusBarButtonCell drawWithFrame:inView:]",
        "-[NSStatusBarButtonCell highlightMode]",
        "-[NSStatusBarButtonCell setHighlightMode:]",
        "-[NSStatusBarButtonCell setStatusBar:]",
        "-[NSStatusBarButtonCell setStatusMenu:]",
        "-[NSStatusBarButtonCell statusMenu]",
        "-[NSStatusBarButtonCell trackMouse:inRect:ofView:untilMouseUp:]",
        "-[NSStatusBarWindow _showToolTip]",
        "-[NSStatusBarWindow initWithContentRect:]",
    }
    assert selectors == {method for method in methods if "NSStatusBar" in method}

    source = (appkit / "NSStatusBar.m").read_text()
    assert "SBPSinsertwindow" in source
    assert "SBPSremovewindow" in source
    assert "SBPSadjustwindows" in source
    assert "nextdict /%s known not" in source
    assert "[NSMenuView menuBarHeight]" in source
    assert "NSMakePoint(-8.0f, 0.0f)" in source
    assert "_cornerLocationForWindowWithSize:" in source
    assert "NSStatusBarButtonCell" in source
    assert "setCellClass:" in source
    assert "trackWithEvent:event" in source
    assert "[self setLevel:21]" in source
    assert "setStatusMenu:menu" in source
