from pathlib import Path

from selector_check import source_methods


def test_image_cell_geometry_and_style_selectors_match_reference():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    expected = {
        "-[NSImageCell image]",
        "-[NSImageCell imageAlignment]",
        "-[NSImageCell setImageAlignment:]",
        "-[NSImageCell imageScaling]",
        "-[NSImageCell setImageScaling:]",
        "-[NSImageCell imageFrameStyle]",
        "-[NSImageCell setImageFrameStyle:]",
        "-[NSImageCell isOpaque]",
        "-[NSImageCell cellSizeForBounds:]",
        "-[NSImageCell drawingRectForBounds:]",
        "-[NSImageCell imageRectForBounds:]",
        "-[NSImageCell titleRectForBounds:]",
        "-[NSImageCell _highlightsWithHighlightRect]",
        "-[NSImageCell highlight:withFrame:inView:]",
        "-[NSImageCell trackMouse:inRect:ofView:untilMouseUp:]",
        "-[NSImageCell setFormatter:]",
        "-[NSImageCell _setContents:]",
    }
    assert expected <= methods

    source = (appkit / "NSImageCell.m").read_text()
    for field in ("_align", "_scale", "_style", "_contents"):
        assert field in source
    assert "return _style == NSImageFrameGrayBezel\n        || _style == NSImageFrameGroove\n        || _style == NSImageFrameButton;" in source
    assert "return NSMakeSize(6.0f, 6.0f);" in source
    assert "return NSMakeSize(4.0f, 4.0f);" in source
    assert "return bounds;" in source


def test_image_cell_content_replacement_releases_old_image():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    source = (appkit / "NSImageCell.m").read_text()
    assert "if (_contents == contents)\n        return;" in source
    assert "[_contents release];" in source
    assert "_contents = [contents retain];" in source



def test_image_cell_assignment_validates_images_and_clears_scaled_cache():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    assert "-[NSImageCell setImage:]" in methods
    assert "-[NSImageCell setObjectValue:]" in methods

    source = (appkit / "NSImageCell.m").read_text()
    assert "[self setObjectValue:image];" in source
    assert "[objectValue isKindOfClass:[NSImage class]]" in source
    assert "[NSException raise:NSInvalidArgumentException" in source
    assert "[_scaledImage release];\n    _scaledImage = nil;\n    [super setObjectValue:objectValue];" in source


def test_image_cell_interior_draws_scaled_and_aligned_image_with_clipping():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    assert "-[NSImageCell drawInteriorWithFrame:inView:]" in methods

    source = (appkit / "NSImageCell.m").read_text()
    assert "if (_scale == NSScaleToFit)" in source
    assert "if (_scale == NSScaleProportionally" in source
    assert "[view isFlipped]" in source
    assert "[view convertSize:drawSize toView:nil]" in source
    assert "NSRectClip(imageRect);" in source
    assert "[_scaledImage setSize:drawSize];" in source
    assert "[image compositeToPoint:point operation:NSCompositeSourceOver];" in source


def test_image_cell_draws_frame_style_before_the_image_interior():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    assert "-[NSImageCell drawWithFrame:inView:]" in methods

    source = (appkit / "NSImageCell.m").read_text()
    assert "case NSImageFrameGrayBezel:\n            NSDrawDarkBezel(frame, frame);" in source
    assert "case NSImageFrameGroove:\n            NSDrawGroove(frame, frame);" in source
    assert "case NSImageFrameButton:\n            NSDrawButton(frame, frame);" in source
    assert "[self drawInteriorWithFrame:frame inView:view];" in source
