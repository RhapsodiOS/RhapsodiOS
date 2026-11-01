from pathlib import Path

from selector_check import source_methods


def test_view_core_geometry_hierarchy_and_autoresizing_accessors():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    expected = {
        "-[NSView initWithFrame:]",
        "-[NSView window]",
        "-[NSView superview]",
        "-[NSView subviews]",
        "-[NSView frame]",
        "-[NSView bounds]",
        "-[NSView isFlipped]",
        "-[NSView isOpaque]",
        "-[NSView needsDisplay]",
        "-[NSView autoresizesSubviews]",
        "-[NSView setAutoresizesSubviews:]",
        "-[NSView autoresizingMask]",
        "-[NSView setAutoresizingMask:]",
        "-[NSView isDescendantOf:]",
        "-[NSView opaqueAncestor]",
        "-[NSView isRotatedFromBase]",
        "-[NSView isRotatedOrScaledFromBase]",
        "-[NSView acceptsFirstMouse:]",
        "-[NSView shouldDelayWindowOrderingForEvent:]",
        "-[NSView mouse:inRect:]",
        "-[NSView tag]",
        "-[NSView viewWithTag:]",
        "-[NSView frameRotation]",
        "-[NSView boundsRotation]",
        "-[NSView enclosingScrollView]",
        "-[NSView _hasgState]",
        "-[NSView postsFrameChangedNotifications]",
        "-[NSView postsBoundsChangedNotifications]",
        "-[NSView _noVerticalAutosizing]",
        "-[NSView _allowsContextMenus]",
        "-[NSView _isAncestorOf:]",
        "-[NSView _setNoVerticalAutosizing:]",
        "-[NSView viewWillMoveToSuperview:]",
        "-[NSView viewWillMoveToWindow:]",
    }
    assert expected <= methods

    source = (appkit / "NSView.m").read_text()
    assert "self = [super init];" in source
    assert "_frame = frameRect;" in source
    assert "_bounds = NSMakeRect(0.0f, 0.0f, frameRect.size.width, frameRect.size.height);" in source
    assert "return _window;" in source
    assert "return _superview;" in source
    assert "return _subviews ? (NSArray *)_subviews : [NSArray array];" in source
    assert "return _frame;" in source
    assert "return _bounds;" in source
    assert "return _vFlags.autoresizeSubviews;" in source
    assert "_vFlags.autosizing = mask;" in source
    assert "if ([self isOpaque])\n        return self;" in source
    assert "return _vFlags.rotatedFromBase;" in source
    assert "return _vFlags.rotatedOrScaledFromBase;" in source
    assert "return NO;" in source
    assert "return NSMouseInRect(point, rect, [self isFlipped]);" in source
    assert "return -1;" in source
    assert "[[subviews objectAtIndex:index] viewWithTag:tag]" in source
    assert "atan2(transform.m12, transform.m11) * 57.29577951308232f" in source
    assert "if (_frameMatrix)" in source
    assert "if (_drawMatrix)" in source
    assert "[ancestor isKindOfClass:[NSScrollView class]]" in source
    assert "self == [scrollView contentView] || [self isDescendantOf:[scrollView contentView]]" in source
    assert "return _gState != 0;" in source
    assert "return !_vFlags.frameChangeNotesSuspended;" in source
    assert "return !_vFlags.boundsChangeNotesSuspended;" in source
    assert "return _vFlags.noVerticalAutosizing;" in source
    assert "- (BOOL)_allowsContextMenus\n{\n    return YES;" in source
    assert "if ([subviews containsObject:view])\n        return YES;" in source
    assert "_vFlags.noVerticalAutosizing = noVerticalAutosizing;" in source
