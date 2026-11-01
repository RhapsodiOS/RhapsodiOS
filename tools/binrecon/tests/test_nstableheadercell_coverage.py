from pathlib import Path

from selector_check import source_methods


def test_table_header_cell_implements_reference_selectors_and_drawing():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    selectors = {
        "-[NSTableHeaderCell _convertToText:]",
        "-[NSTableHeaderCell _drawContents:faceColor:textColor:inView:]",
        "-[NSTableHeaderCell drawInteriorWithFrame:inView:]",
        "-[NSTableHeaderCell drawWithFrame:inView:]",
        "-[NSTableHeaderCell highlight:withFrame:inView:]",
    }
    assert selectors <= methods

    source = (appkit / "NSTableHeaderCell.m").read_text()
    assert "[NSFont titleBarFontOfSize:-1.0f]" in source
    assert "NSRectFillListWithColors(rects, colors, 7)" in source
    assert "highlightWithLevel:2.0f / 3.0f" in source
    assert "shadowWithLevel:0.2f" in source
    assert "imageRectForBounds:cellFrame" in source
    assert "[super _convertToText:object]" in source
