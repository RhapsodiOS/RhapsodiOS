from pathlib import Path

from selector_check import source_methods


def test_clip_view_state_accessors():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    expected = {
        "-[NSClipView backgroundColor]",
        "-[NSClipView setBackgroundColor:]",
        "-[NSClipView initWithFrame:]",
        "-[NSClipView copiesOnScroll]",
        "-[NSClipView setCopiesOnScroll:]",
        "-[NSClipView documentCursor]",
        "-[NSClipView setDocumentCursor:]",
        "-[NSClipView documentRect]",
        "-[NSClipView documentVisibleRect]",
        "-[NSClipView documentView]",
        "-[NSClipView constrainScrollPoint:]",
        "-[NSClipView setNextKeyView:]",
        "-[NSClipView setDocumentView:]",
        "-[NSClipView _alignCoords]",
        "-[NSClipView _pinDocRect]",
        "-[NSClipView viewBoundsChanged:]",
        "-[NSClipView acceptsFirstResponder]",
        "-[NSClipView isFlipped]",
        "-[NSClipView isOpaque]",
        "-[NSClipView needsPanelToBecomeKey]",
        "-[NSClipView _drawsBackground]",
        "-[NSClipView _setDrawsBackground:]",
    }
    assert expected <= methods

    source = (appkit / "NSClipView.m").read_text()
    assert "return _backgroundColor;" in source
    assert "return _cursor;" in source
    assert "return _docView;" in source
    assert "return _docRect;" in source
    assert "return _docView ? [_docView convertRect:[self bounds] fromView:self] : NSZeroRect;" in source
    assert "return !_cvFlags.noCopyOnScroll;" in source
    assert "_cvFlags.noCopyOnScroll = !copiesOnScroll;" in source
    assert "return _docView ? [_docView acceptsFirstResponder] : NO;" in source
    assert "return _cvFlags.isFlipped;" in source
    assert "return [self _drawsBackground];" in source
    assert "return NO;" in source
    assert "return _cvFlags.drawsBackground;" in source
    assert "_cvFlags.drawsBackground = drawsBackground;" in source
    assert "[_window invalidateCursorRectsForView:self];" in source
    assert "[_docView setNextKeyView:nextKeyView];" in source
    assert "[super setNextKeyView:nextKeyView];" in source
    assert "- (void)setDocumentView:(NSView *)documentView" in source
    assert "removeObserver:self name:NSViewFrameDidChangeNotification object:_docView" in source
    assert "removeObserver:self name:NSViewBoundsDidChangeNotification object:_docView" in source
    assert "addObserver:self selector:@selector(viewFrameChanged:) name:NSViewFrameDidChangeNotification object:documentView" in source
    assert "addObserver:self selector:@selector(viewBoundsChanged:) name:NSViewBoundsDidChangeNotification object:documentView" in source
    assert "_docView = documentView;" in source
    assert "[self _pinDocRect];" in source
    assert "_cvFlags.isFlipped = documentFlipped;" in source
    assert "[self _invalidateFocus];" in source
    assert "_docRect = [_docView frame];" in source
    assert "[notification object] == _docView" in source
    assert "SEL selector = @selector(_reflectDocumentViewBoundsChange);" in source
    assert "[superview respondsToSelector:selector]" in source
    assert "[superview performSelector:selector];" in source
    assert "_docRect.origin.x + _docRect.size.width - bounds.size.width" in source
    assert "_docRect.origin.y + _docRect.size.height - bounds.size.height" in source
    assert "[self allocateGState];" in source
    assert "[self setBackgroundColor:[NSColor controlBackgroundColor]];" in source
    assert "[self _setDrawsBackground:YES];" in source
    assert "_halftone = NSZoneMalloc(NULL, 8);" in source
