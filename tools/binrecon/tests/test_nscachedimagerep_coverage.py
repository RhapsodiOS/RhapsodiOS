from pathlib import Path

from selector_check import source_methods


def test_cached_image_rep_window_rect_and_opacity_follow_reference():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    selectors = {
        "+[NSCachedImageRep initialize]",
        "-[NSCachedImageRep initWithWindow:rect:]",
        "-[NSCachedImageRep window]",
        "-[NSCachedImageRep rect]",
        "-[NSCachedImageRep setAlpha:]",
        "-[NSCachedImageRep _canDrawOutsideOfItsBounds]",
    }
    assert selectors <= methods

    source = (appkit / "NSCachedImageRep.m").read_text()
    initializer = source.rsplit("- (id)initWithWindow:(NSWindow *)window rect:(NSRect)rect", 1)[1].split("\n}", 1)[0]
    assert "[super init]" in initializer
    assert "_window = [window retain];" in initializer
    assert "_origin = rect.origin;" in initializer
    assert "[self setSize:rect.size]" in initializer
    assert "[self setOpaque:YES]" in initializer

    getter = source.rsplit("- (NSWindow *)window", 1)[1].split("\n}", 1)[0]
    assert "_NXSharedKitImagesWindow(_window)" in getter
    assert "[_NXSharedKitImagesWindow(_window) retain]" in getter

    setter = source.rsplit("- (void)setAlpha:(BOOL)flag", 1)[1].split("\n}", 1)[0]
    assert "[super setAlpha:flag]" in setter
    assert "_repFlags.cacheAlphaComputed = YES;" in setter


def test_cached_image_rep_lazy_parameters_match_window_depth():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    source = (appkit / "NSCachedImageRep.m").read_text()
    compute = source.rsplit("- (void)_computeParams", 1)[1].split("\n}", 1)[0]
    assert "if (_repFlags.cacheParamsComputed)" in compute
    assert "[[self window] depthLimit]" in compute
    assert "[NSWindow defaultDepthLimit]" in compute
    assert "ceil(size.width)" in compute
    assert "ceil(size.height)" in compute
    assert "NSBitsPerSampleFromDepth(depth)" in compute
    assert "NSColorSpaceFromDepth(depth)" in compute
    assert "_repFlags.cacheParamsComputed = YES;" in compute

    getters = {
        "bitsPerSample": "- (int)bitsPerSample",
        "colorSpaceName": "- (NSString *)colorSpaceName",
        "pixelsWide": "- (int)pixelsWide",
        "pixelsHigh": "- (int)pixelsHigh",
    }
    for selector, signature in getters.items():
        body = source.rsplit(signature, 1)[1].split("\n}", 1)[0]
        assert "if (!_repFlags.cacheParamsComputed)" in body
        assert "[self _computeParams]" in body
