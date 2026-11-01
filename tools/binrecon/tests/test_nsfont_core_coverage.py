from pathlib import Path

from selector_check import source_methods


def test_font_core_metadata_and_immutable_copy_selectors():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    assert {
        "-[NSFont fontName]",
        "-[NSFont pointSize]",
        "-[NSFont copy]",
        "-[NSFont copyWithZone:]",
        "-[NSFont retainCount]",
    } <= methods

    source = (appkit / "NSFont.m").read_text()
    assert "return _name ? _name : @\"Helvetica\";" in source
    assert "return _size;" in source
    assert "return [self retain];" in source
    assert "return -1;" in source
