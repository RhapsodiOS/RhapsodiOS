from pathlib import Path

from selector_check import source_methods


def test_scroll_view_state_accessors():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    expected = {
        "-[NSScrollView contentView]",
        "-[NSScrollView documentVisibleRect]",
        "-[NSScrollView documentView]",
        "-[NSScrollView verticalScroller]",
        "-[NSScrollView horizontalScroller]",
        "-[NSScrollView borderType]",
        "-[NSScrollView hasVerticalScroller]",
        "-[NSScrollView hasHorizontalScroller]",
        "-[NSScrollView setHasVerticalScroller:]",
        "-[NSScrollView setHasHorizontalScroller:]",
        "-[NSScrollView _update]",
        "-[NSScrollView horizontalLineScroll]",
        "-[NSScrollView horizontalPageScroll]",
        "-[NSScrollView verticalLineScroll]",
        "-[NSScrollView verticalPageScroll]",
        "-[NSScrollView setHorizontalLineScroll:]",
        "-[NSScrollView setHorizontalPageScroll:]",
        "-[NSScrollView setVerticalLineScroll:]",
        "-[NSScrollView setVerticalPageScroll:]",
        "-[NSScrollView lineScroll]",
        "-[NSScrollView pageScroll]",
        "-[NSScrollView setLineScroll:]",
        "-[NSScrollView setPageScroll:]",
        "-[NSScrollView acceptsFirstResponder]",
        "-[NSScrollView isFlipped]",
        "-[NSScrollView isOpaque]",
        "-[NSScrollView needsPanelToBecomeKey]",
        "-[NSScrollView _drawsBackground]",
        "-[NSScrollView _setDrawsBackground:]",
        "-[NSScrollView _commonNewScroll:]",
        "-[NSScrollView _newScroll:]",
        "-[NSScrollView _contentView]",
        "-[NSScrollView setCopiesOnScroll:]",
        "-[NSScrollView setInterfaceStyle:]",
        "-[NSScrollView setNextKeyView:]",
        "-[NSScrollView resizeSubviewsWithOldSize:]",
        "-[NSScrollView setVerticalScroller:]",
        "-[NSScrollView setHorizontalScroller:]",
        "-[NSScrollView scrollsDynamically]",
        "-[NSScrollView contentSize]",
        "-[NSScrollView setBorderType:]",
        "-[NSScrollView setScrollsDynamically:]",
        "-[NSScrollView documentCursor]",
        "-[NSScrollView setDocumentCursor:]",
        "-[NSScrollView backgroundColor]",
        "-[NSScrollView setBackgroundColor:]",
        "-[NSScrollView _reflectDocumentViewBoundsChange]",
        "-[NSScrollView(NSRulerSupport) rulersVisible]",
        "-[NSScrollView(NSRulerSupport) hasHorizontalRuler]",
        "-[NSScrollView(NSRulerSupport) hasVerticalRuler]",
        "+[NSScrollView(NSRulerSupport) rulerViewClass]",
        "+[NSScrollView(NSRulerSupport) setRulerViewClass:]",
        "-[NSScrollView(NSRulerSupport) horizontalRulerView]",
        "-[NSScrollView(NSRulerSupport) verticalRulerView]",
        "-[NSScrollView(NSRulerSupport) setRulersVisible:]",
        "-[NSScrollView(NSRulerSupport) setHasHorizontalRuler:]",
        "-[NSScrollView(NSRulerSupport) setHasVerticalRuler:]",
    }
    assert expected <= methods

    source = (appkit / "NSScrollView.m").read_text()
    assert "return _contentView;" in source
    assert "return _contentView ? [_contentView documentVisibleRect] : NSZeroRect;" in source
    assert "return [_contentView documentView];" in source
    assert "return _vScroller;" in source
    assert "return _hScroller;" in source
    assert "return _sFlags.borderType;" in source
    assert "return _sFlags.vScrollerRequired;" in source
    assert "return _sFlags.hScrollerRequired;" in source
    assert "return !_sFlags.noDynamicScrolling;" in source
    assert "return [_contentView bounds].size;" in source
    assert "_sFlags.borderType = borderType;" in source
    assert "_sFlags.noDynamicScrolling = !scrollsDynamically;" in source
    assert "return [_contentView documentCursor];" in source
    assert "[_contentView setDocumentCursor:documentCursor];" in source
    assert "return [_contentView backgroundColor];" in source
    assert "[_contentView setBackgroundColor:backgroundColor];" in source
    assert "[_horizontalRuler updateRuler];" in source
    assert "[_horizontalRuler setNeedsDisplay:YES];" in source
    assert "[_verticalRuler updateRuler];" in source
    assert "[_verticalRuler setNeedsDisplay:YES];" in source
    assert "return _sFlags.showRulers;" in source
    assert "return _sFlags.hasHorizontalRuler;" in source
    assert "return _sFlags.hasVerticalRuler;" in source
    assert "static Class NSScrollViewRulerClass;" in source
    assert "return NSScrollViewRulerClass ? NSScrollViewRulerClass : [NSRulerView class];" in source
    assert "NSScrollViewRulerClass = rulerViewClass;" in source
    assert "initWithScrollView:self orientation:NSHorizontalRuler" in source
    assert "initWithScrollView:self orientation:NSVerticalRuler" in source
    assert "_sFlags.showRulers = rulersVisible;" in source
    assert "_sFlags.hasHorizontalRuler = hasHorizontalRuler;" in source
    assert "_sFlags.hasVerticalRuler = hasVerticalRuler;" in source
    assert "[self _newScroll:YES];" in source
    assert "[self _newScroll:NO];" in source
    assert "[_vScroller setFrameSize:NSMakeSize(-100.0f, -100.0f)];" in source
    assert "[_hScroller setFrameSize:NSMakeSize(-100.0f, -100.0f)];" in source
    assert "[self _update];" in source
    assert "- (id)_update\n{\n    [self tile];\n    [self setNeedsDisplay:YES];\n    return self;" in source
    assert "return ((float *)_reserved1)[2];" in source
    assert "return ((float *)_reserved1)[0];" in source
    assert "return ((float *)_reserved1)[3];" in source
    assert "return ((float *)_reserved1)[1];" in source
    assert "((float *)_reserved1)[2] = horizontalLineScroll > 0.0f ? horizontalLineScroll : 0.0f;" in source
    assert "((float *)_reserved1)[0] = horizontalPageScroll > 0.0f ? horizontalPageScroll : 0.0f;" in source
    assert "((float *)_reserved1)[3] = verticalLineScroll > 0.0f ? verticalLineScroll : 0.0f;" in source
    assert "((float *)_reserved1)[1] = verticalPageScroll > 0.0f ? verticalPageScroll : 0.0f;" in source
    assert "return [self verticalLineScroll];" in source
    assert "return [self verticalPageScroll];" in source
    assert "[self setHorizontalLineScroll:lineScroll];" in source
    assert "[self setVerticalLineScroll:lineScroll];" in source
    assert "[self setHorizontalPageScroll:pageScroll];" in source
    assert "[self setVerticalPageScroll:pageScroll];" in source
    assert "return [_contentView acceptsFirstResponder];" in source
    assert "return YES;" in source
    assert "return [self _drawsBackground];" in source
    assert "return NO;" in source
    assert "return !_sFlags.doesNotDrawBackground;" in source
    assert "_sFlags.doesNotDrawBackground = !drawsBackground;" in source
    assert "[_vScroller removeFromSuperview];" in source
    assert "[_hScroller removeFromSuperview];" in source
    assert "[self _commonNewScroll:verticalScroller];" in source
    assert "[self _commonNewScroll:horizontalScroller];" in source
    assert "[scroller setTarget:self];" in source
    assert "[scroller setAction:@selector(_doScroller:)];" in source
    assert "frame.size.height = 100.0f;" in source
    assert "frame.size.width = 100.0f;" in source
    assert "[scroller setArrowsPosition:NSScrollerArrowsMaxEnd];" in source
    assert "[scroller checkSpaceForParts];" in source
    assert "[_contentView setCopiesOnScroll:copiesOnScroll];" in source
    assert "[super setInterfaceStyle:interfaceStyle];" in source
    assert "[_contentView setNextKeyView:nextKeyView];" in source
    assert "[super setNextKeyView:nextKeyView];" in source
    assert "- (void)resizeSubviewsWithOldSize:(NSSize)oldSize\n{\n    [self _update];" in source
