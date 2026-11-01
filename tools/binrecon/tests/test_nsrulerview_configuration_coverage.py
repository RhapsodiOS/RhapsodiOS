from pathlib import Path

from selector_check import source_methods


def test_ruler_view_configuration_accessors():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    expected = {
        "-[NSRulerView orientation]",
        "-[NSRulerView setOrientation:]",
        "-[NSRulerView scrollView]",
        "-[NSRulerView setScrollView:]",
        "-[NSRulerView clientView]",
        "-[NSRulerView setClientView:]",
        "-[NSRulerView setMarkers:]",
        "-[NSRulerView addMarker:]",
        "-[NSRulerView removeMarker:]",
        "-[NSRulerView _markerAreaRect]",
        "-[NSRulerView _setDraggingMarker:]",
        "-[NSRulerView accessoryView]",
        "-[NSRulerView setAccessoryView:]",
        "-[NSRulerView setFrameSize:]",
        "-[NSRulerView markers]",
        "-[NSRulerView originOffset]",
        "-[NSRulerView setOriginOffset:]",
        "-[NSRulerView ruleThickness]",
        "-[NSRulerView setRuleThickness:]",
        "-[NSRulerView reservedThicknessForMarkers]",
        "-[NSRulerView setReservedThicknessForMarkers:]",
        "-[NSRulerView reservedThicknessForAccessoryView]",
        "-[NSRulerView setReservedThicknessForAccessoryView:]",
        "-[NSRulerView baselineLocation]",
        "-[NSRulerView requiredThickness]",
        "-[NSRulerView isFlipped]",
        "-[NSRulerView isOpaque]",
        "-[NSRulerView invalidateHashMarks]",
        "-[NSRulerView dealloc]",
    }
    assert expected <= methods

    source = (appkit / "NSRulerView.m").read_text()
    assert "return _orientation;" in source
    assert "return _scrollView;" in source
    assert "_scrollView = scrollView;" in source
    assert "[self invalidateHashMarks];" in source
    assert "_markers = [[NSMutableArray allocWithZone:[self zone]] initWithCapacity:count];" in source
    assert "[marker thicknessRequiredInRuler]" in source
    assert "[_markers addObject:marker];" in source
    assert "[NSMutableArray arrayWithObject:marker]" in source
    assert "[_markers removeObject:marker];" in source
    assert "[self setNeedsDisplayInRect:[self _markerAreaRect]];" in source
    assert "requiredThickness += 2.0f;" in source
    assert "[self setReservedThicknessForMarkers:requiredThickness];" in source
    assert "return _clientView;" in source
    assert "rulerView:self willSetClientView:clientView" in source
    assert "_clientView = clientView;" in source
    assert "[self _setDraggingMarker:nil];" in source
    assert "return _accessoryView;" in source
    assert "[_accessoryView removeFromSuperview];" in source
    assert "_accessoryView = accessoryView;" in source
    assert "[accessoryView setFrame:rulerBounds];" in source
    assert "[self addSubview:accessoryView];" in source
    assert "[self setReservedThicknessForAccessoryView:requiredThickness];" in source
    assert "[super setFrameSize:newSize];" in source
    assert "accessoryFrame.size.height = rulerBounds.size.height;" in source
    assert "accessoryFrame.size.width = rulerBounds.size.width;" in source
    assert "return _markers;" in source
    assert "return _originOffset;" in source
    assert "return _ruleThickness;" in source
    assert "return _thicknessForMarkers;" in source
    assert "return _thicknessForAccessoryView;" in source
    assert "[_scrollView tile];" in source
    assert "[self setNeedsDisplay:YES];" in source
    assert "if (_orientation == NSHorizontalRuler)" in source
    assert "return [[_scrollView documentView] isFlipped];" in source
    assert "return YES;" in source
    assert "return _thicknessForAccessoryView + _thicknessForMarkers + _ruleThickness;" in source
    assert "[_cachedHashDict release];" in source
    assert "_cachedHashDict = nil;" in source
    assert "[_clientView rulerView:self willSetClientView:nil];" in source
    assert "[_cachedHashDict release];" in source
    assert "[_markers release];" in source
    assert "[_units release];" in source
    assert "[super dealloc];" in source
