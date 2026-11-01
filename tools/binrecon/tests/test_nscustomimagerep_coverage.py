from pathlib import Path

from selector_check import source_methods


def test_custom_image_rep_accessors_and_drawing_follow_reference():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    selectors = (
        "-[NSCustomImageRep delegate]",
        "-[NSCustomImageRep drawSelector]",
        "-[NSCustomImageRep draw]",
    )
    assert set(selectors) <= methods

    source = (appkit / "NSCustomImageRep.m").read_text()
    delegate = source.rsplit("- (id)delegate", 1)[1].split("\n}", 1)[0]
    assert "return _drawObject;" in delegate
    selector = source.rsplit("- (SEL)drawSelector", 1)[1].split("\n}", 1)[0]
    assert "return _drawMethod;" in selector

    draw = source.rsplit("- (BOOL)draw", 1)[1].split("\n}", 1)[0]
    assert "_drawObject == nil" in draw
    assert "respondsToSelector:_drawMethod" in draw
    assert "performSelector:_drawMethod withObject:self" in draw
    assert "return NO;" in draw
    assert "return YES;" in draw


def test_custom_image_rep_initialization_and_coding_preserve_draw_target():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    selectors = (
        "-[NSCustomImageRep initWithDrawSelector:delegate:]",
        "-[NSCustomImageRep encodeWithCoder:]",
        "-[NSCustomImageRep initWithCoder:]",
    )
    assert set(selectors) <= methods

    source = (appkit / "NSCustomImageRep.m").read_text()
    initializer = source.rsplit("- (id)initWithDrawSelector:(SEL)method delegate:(id)object", 1)[1].split("\n}", 1)[0]
    assert "[super init]" in initializer
    assert "_drawMethod = method;" in initializer
    assert "_drawObject = object;" in initializer

    encode = source.rsplit("- (void)encodeWithCoder:(NSCoder *)coder", 1)[1].split("\n}", 1)[0]
    assert "[super encodeWithCoder:coder]" in encode
    assert "[coder encodeObject:_drawObject]" in encode
    assert "encodeValueOfObjCType:@encode(SEL) at:&_drawMethod" in encode

    decode = source.rsplit("- (id)initWithCoder:(NSCoder *)coder", 1)[1].split("\n}", 1)[0]
    assert "[super initWithCoder:coder]" in decode
    assert "_drawObject = [coder decodeObject];" in decode
    assert "decodeValueOfObjCType:@encode(SEL) at:&_drawMethod" in decode
