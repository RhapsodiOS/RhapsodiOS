from pathlib import Path

from selector_check import source_methods


def test_text_container_reference_methods():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    expected = {
        "-[NSTextContainer containerSize]",
        "-[NSTextContainer containsPoint:]",
        "-[NSTextContainer heightTracksTextView]",
        "-[NSTextContainer initWithContainerSize:]",
        "-[NSTextContainer isSimpleRectangularTextContainer]",
        "-[NSTextContainer layoutManager]",
        "-[NSTextContainer lineFragmentPadding]",
        "-[NSTextContainer lineFragmentRectForProposedRect:sweepDirection:movementDirection:remainingRect:]",
        "-[NSTextContainer replaceLayoutManager:]",
        "-[NSTextContainer setContainerSize:]",
        "-[NSTextContainer setHeightTracksTextView:]",
        "-[NSTextContainer setLayoutManager:]",
        "-[NSTextContainer setLineFragmentPadding:]",
        "-[NSTextContainer setTextView:]",
        "-[NSTextContainer setWidthTracksTextView:]",
        "-[NSTextContainer textView]",
        "-[NSTextContainer widthTracksTextView]",
        "-[NSTextContainer(NSPrivate) _containerObservesTextViewFrameChanges]",
        "-[NSTextContainer(NSPrivate) _containerTextViewFrameChanged:]",
        "-[NSTextContainer(NSPrivate) _resizeAccordingToTextView:]",
        "-[NSTextContainer(NSPrivate) _setContainerObservesTextViewFrameChanges:]",
    }
    assert expected <= methods

    source = (appkit / "NSTextContainer.m").read_text()
    assert "NSViewFrameDidChangeNotification" in source
    assert "[_layoutManager textContainerChangedGeometry:self];" in source
    assert "(_tcFlags.widthTracksTextView || _tcFlags.heightTracksTextView)" in source
    assert "return NSPointInRect(point, bounds);" in source
    assert "*remainingRect = NSZeroRect;" in source
