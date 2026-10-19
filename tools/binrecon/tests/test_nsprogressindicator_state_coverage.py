from pathlib import Path

from selector_check import source_methods


def test_progress_indicator_public_state_methods_match_reference_fields():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    selectors = (
        "-[NSProgressIndicator _commonInit]",
        "-[NSProgressIndicator animationDelay]",
        "-[NSProgressIndicator doubleValue]",
        "-[NSProgressIndicator incrementBy:]",
        "-[NSProgressIndicator initWithFrame:]",
        "-[NSProgressIndicator isBezeled]",
        "-[NSProgressIndicator isFlipped]",
        "-[NSProgressIndicator isIndeterminate]",
        "-[NSProgressIndicator isOpaque]",
        "-[NSProgressIndicator maxValue]",
        "-[NSProgressIndicator minValue]",
        "-[NSProgressIndicator setAnimationDelay:]",
        "-[NSProgressIndicator setBezeled:]",
        "-[NSProgressIndicator setDoubleValue:]",
        "-[NSProgressIndicator setIndeterminate:]",
        "-[NSProgressIndicator setMaxValue:]",
        "-[NSProgressIndicator setMinValue:]",
        "-[NSProgressIndicator setUsesThreadedAnimation:]",
        "-[NSProgressIndicator usesThreadedAnimation]",
    )
    assert set(selectors) <= methods

    source = (appkit / "NSProgressIndicator.m").read_text()
    expected_bodies = {
        "- (void)_commonInit": "_value = _minimum;",
        "- (NSTimeInterval)animationDelay": "return _animationDelay;",
        "- (double)doubleValue": "return _value;",
        "- (BOOL)isBezeled": "return _isBezeled;",
        "- (BOOL)isFlipped": "return YES;",
        "- (BOOL)isIndeterminate": "return _isIndeterminate;",
        "- (BOOL)isOpaque": "return YES;",
        "- (double)maxValue": "return _maximum;",
        "- (double)minValue": "return _minimum;",
        "- (void)setUsesThreadedAnimation:(BOOL)flag": "_threadedAnimation = flag;",
        "- (BOOL)usesThreadedAnimation": "return _threadedAnimation;",
    }
    for signature, expected in expected_bodies.items():
        body = source.rsplit(signature, 1)[1].split("\n}", 1)[0]
        assert expected in body

    initializer = source.rsplit("- (id)initWithFrame:(NSRect)frame", 1)[1].split("\n}", 1)[0]
    assert "_isIndeterminate = YES;" in initializer
    assert "_isBezeled = YES;" in initializer
    assert "_minimum = 0.0;" in initializer
    assert "_maximum = 100.0;" in initializer
    assert "[self _commonInit];" in initializer

    common_init = source.rsplit("- (void)_commonInit", 1)[1].split("\n}", 1)[0]
    assert "_animationIndex = 0;" in common_init
    assert "_animationDelay = 5.0 / 60.0;" in common_init

    set_value = source.rsplit("- (void)setDoubleValue:(double)value", 1)[1].split("\n}", 1)[0]
    assert "if (value < _minimum)" in set_value
    assert "if (value > _maximum)" in set_value
    assert "_value = value;" in set_value
    assert "if (!_isIndeterminate)" in set_value


def test_progress_indicator_value_and_display_mutations_follow_reference():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    source = (appkit / "NSProgressIndicator.m").read_text()

    increment = source.rsplit("- (void)incrementBy:(double)delta", 1)[1].split("\n}", 1)[0]
    assert "[self setDoubleValue:_value + delta];" in increment

    set_bezeled = source.rsplit("- (void)setBezeled:(BOOL)flag", 1)[1].split("\n}", 1)[0]
    assert "if (_isBezeled != flag)" in set_bezeled
    assert "_isBezeled = flag;" in set_bezeled
    assert "[self setNeedsDisplay:YES];" in set_bezeled

    for signature, ivar in (
        ("- (void)setMinValue:(double)value", "_minimum"),
        ("- (void)setMaxValue:(double)value", "_maximum"),
    ):
        body = source.rsplit(signature, 1)[1].split("\n}", 1)[0]
        assert f"{ivar} = value;" in body
        assert "if (!_isIndeterminate)" in body
        assert "[self setNeedsDisplay:YES];" in body

    delay = source.rsplit("- (void)setAnimationDelay:(NSTimeInterval)delay", 1)[1].split("\n}", 1)[0]
    assert "if (_animationDelay != delay)" in delay
    assert "if (_timer)" in delay
    assert "[self stopAnimation:self];" in delay
    assert "[self startAnimation:nil];" in delay

    indeterminate = source.rsplit("- (void)setIndeterminate:(BOOL)flag", 1)[1].split("\n}", 1)[0]
    assert "if (_isIndeterminate != flag)" in indeterminate
    assert "[self stopAnimation:self];" in indeterminate
    assert "_isIndeterminate = flag;" in indeterminate
    assert "[self setNeedsDisplay:YES];" in indeterminate
