from pathlib import Path

from selector_check import source_methods


def test_image_rep_state_accessors_match_reference():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    selectors = {
        "+[NSImageRep initialize]",
        "-[NSImageRep setSize:]",
        "-[NSImageRep size]",
        "-[NSImageRep setAlpha:]",
        "-[NSImageRep hasAlpha]",
        "-[NSImageRep setOpaque:]",
        "-[NSImageRep isOpaque]",
        "-[NSImageRep setColorSpaceName:]",
        "-[NSImageRep colorSpaceName]",
        "-[NSImageRep setBitsPerSample:]",
        "-[NSImageRep bitsPerSample]",
        "-[NSImageRep setPixelsWide:]",
        "-[NSImageRep pixelsWide]",
        "-[NSImageRep setPixelsHigh:]",
        "-[NSImageRep pixelsHigh]",
        "-[NSImageRep _gsave]",
        "-[NSImageRep _grestore]",
        "-[NSImageRep _canDrawOutsideOfItsBounds]",
    }
    assert selectors <= methods

    source = (appkit / "NSImageRep.m").read_text()
    assert "[self setVersion:17]" in source
    assert "_repFlags.hasAlpha = alpha" in source
    assert "_repFlags.isOpaque = opaque" in source
    assert "_repFlags.bitsPerSample = anInt" in source
    assert "_pixelsWide = anInt" in source
    assert "_pixelsHigh = anInt" in source
    assert "_colorSpaceName = [string copyWithZone:[self zone]]" in source
    assert "_colorSpaceName != nil ? _colorSpaceName : NSDeviceRGBColorSpace" in source

    save = source.rsplit("- (void)_gsave", 1)[1].split("\n}", 1)[0]
    restore = source.rsplit("- (void)_grestore", 1)[1].split("\n}", 1)[0]
    assert "++_repFlags.gsaved" in save
    assert "_repFlags.gsaved == 1" in save
    assert "PSgsave()" in save
    assert "--_repFlags.gsaved" in restore
    assert "_repFlags.gsaved == 0" in restore
    assert "PSgrestore()" in restore


def test_image_rep_drawing_copy_and_cleanup_follow_reference():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    selectors = {
        "-[NSImageRep draw]",
        "-[NSImageRep drawAtPoint:]",
        "-[NSImageRep drawInRect:]",
        "-[NSImageRep copyWithZone:]",
        "-[NSImageRep dealloc]",
    }
    assert selectors <= methods

    source = (appkit / "NSImageRep.m").read_text()
    point_draw = source.rsplit("- (BOOL)drawAtPoint:", 1)[1].split("\n}", 1)[0]
    assert "_size.width <= 0.0 || _size.height <= 0.0" in point_draw
    assert "[self _gsave]" in point_draw
    assert "PStranslate(point.x, point.y)" in point_draw
    assert "[self draw]" in point_draw
    assert "[self _grestore]" in point_draw

    rect_draw = source.rsplit("- (BOOL)drawInRect:", 1)[1].split("\n}", 1)[0]
    assert "rect.size.width / _size.width" in rect_draw
    assert "rect.size.height / _size.height" in rect_draw
    assert "PSscale(" in rect_draw

    copy = source.rsplit("- (id)copyWithZone:", 1)[1].split("\n}", 1)[0]
    assert "NSCopyObject(self, 0, zone)" in copy
    assert "[_colorSpaceName copyWithZone:zone]" in copy

    dealloc = source.rsplit("- (void)dealloc", 1)[1].split("\n}", 1)[0]
    assert "while (_repFlags.gsaved != 0)" in dealloc
    assert "[_colorSpaceName release]" in dealloc
    assert "[super dealloc]" in dealloc


def test_image_rep_coding_preserves_reference_archive_versions():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    assert "-[NSImageRep encodeWithCoder:]" in methods
    assert "-[NSImageRep initWithCoder:]" in methods

    source = (appkit / "NSImageRep.m").read_text()
    encode = source.rsplit("- (void)encodeWithCoder:", 1)[1].split("\n}", 1)[0]
    assert "[coder encodeSize:_size]" in encode
    assert "[coder encodeValueOfObjCType:@encode(BOOL)" in encode
    assert 'encodeValuesOfObjCTypes:"iii@"' in encode

    decode = source.rsplit("- (id)initWithCoder:", 1)[1].split("\n}", 1)[0]
    assert '[coder versionForClassName:@"NSImageRep"]' in decode
    assert "[super initWithCoder:coder]" in decode
    assert "[coder decodeSize]" in decode
    assert 'decodeValuesOfObjCTypes:"iii@"' in decode
    assert 'decodeValuesOfObjCTypes:"iis@ss"' in decode
    assert 'decodeValuesOfObjCTypes:"iisssss"' in decode
    assert 'decodeValuesOfObjCTypes:"iissss"' in decode
    assert "NSCalibratedWhiteColorSpace" in decode
    assert "NSCalibratedRGBColorSpace" in decode
    assert "NSDeviceCMYKColorSpace" in decode
