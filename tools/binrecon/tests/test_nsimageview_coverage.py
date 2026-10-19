from pathlib import Path

from selector_check import source_methods


def test_image_view_forwards_image_cell_state_and_drag_operations():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    expected = {
        "-[NSImageView action]",
        "-[NSImageView concludeDragOperation:]",
        "-[NSImageView draggingEntered:]",
        "-[NSImageView imageAlignment]",
        "-[NSImageView imageFrameStyle]",
        "-[NSImageView imageScaling]",
        "-[NSImageView image]",
        "-[NSImageView initWithFrame:]",
        "-[NSImageView isEditable]",
        "-[NSImageView isOpaque]",
        "-[NSImageView performDragOperation:]",
        "-[NSImageView setAction:]",
        "-[NSImageView setEditable:]",
        "-[NSImageView setImage:]",
        "-[NSImageView setImageAlignment:]",
        "-[NSImageView setImageFrameStyle:]",
        "-[NSImageView setImageScaling:]",
        "-[NSImageView(NSImageViewPrivate) registerForDrags]",
    }
    assert expected <= methods

    source = (appkit / "NSImageView.m").read_text()
    assert "[self setCellClass:[NSImageCell class]];" in source
    assert "return [[self cell] image];" in source
    assert "[[self cell] setImage:image];" in source
    assert "[self setNeedsDisplay:YES];" in source
    assert "return cell ? [cell isOpaque] : NO;" in source
    assert "[self registerForDraggedTypes:[NSImage imagePasteboardTypes]];" in source
    assert "NSDragOperationCopy | NSDragOperationGeneric" in source
    assert "[[NSImage alloc] initWithPasteboard:[sender draggingPasteboard]]" in source
    assert "[self sendAction:_action to:_target];" in source
