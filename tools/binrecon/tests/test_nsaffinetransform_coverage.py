from pathlib import Path

from selector_check import source_methods


def test_affine_transform_implements_reference_selectors():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    selectors = {
        "+[NSAffineTransform transform]",
        "+[NSAffineTransform initialize]",
        "-[NSAffineTransform init]",
        "-[NSAffineTransform initWithTransform:]",
        "-[NSAffineTransform translateXBy:yBy:]",
        "-[NSAffineTransform rotateByDegrees:]",
        "-[NSAffineTransform rotateByRadians:]",
        "-[NSAffineTransform scaleBy:]",
        "-[NSAffineTransform scaleXBy:yBy:]",
        "-[NSAffineTransform invert]",
        "-[NSAffineTransform appendTransform:]",
        "-[NSAffineTransform prependTransform:]",
        "-[NSAffineTransform transformPoint:]",
        "-[NSAffineTransform transformSize:]",
        "-[NSAffineTransform transformBezierPath:]",
        "-[NSAffineTransform set]",
        "-[NSAffineTransform concat]",
        "-[NSAffineTransform transformStruct]",
        "-[NSAffineTransform setTransformStruct:]",
        "-[NSAffineTransform copyWithZone:]",
        "-[NSAffineTransform encodeWithCoder:]",
        "-[NSAffineTransform initWithCoder:]",
        "-[NSAffineTransform _fillFloatArray:]",
    }
    assert selectors <= methods

    source = (appkit / "NSAffineTransform.m").read_text()
    assert "DPSconcat(" in source
    assert "DPSsendfloatarray(" in source
    assert "DPSsetmatrix(" in source
    assert "encodeArrayOfObjCType" in source
    assert "decodeArrayOfObjCType" in source
    assert "sin(" in source
    assert "cos(" in source
    assert "old.m11 * old.m22 - old.m12 * old.m21" in source
    append = source.split("- (void)appendTransform:", 1)[1].split("\n}", 1)[0]
    assert "old.m11 * other.m11 + old.m12 * other.m21" in append
    assert "old.tX * other.m11 + old.tY * other.m21 + other.tX" in append
    prepend = source.split("- (void)prependTransform:", 1)[1].split("\n}", 1)[0]
    assert "other.m11 * old.m11 + other.m12 * old.m21" in prepend
    assert "other.tX * old.m11 + other.tY * old.m21 + old.tX" in prepend
