from pathlib import Path

from selector_check import source_methods


def test_color_picker_implements_reference_selectors_and_base_behavior():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    selectors = {
        "-[NSColorPicker _getTiffImage:ownedBy:]",
        "-[NSColorPicker _getTiffImage:ownedBy:asImageRep:]",
        "-[NSColorPicker initWithPickerMask:colorPanel:]",
        "-[NSColorPicker insertNewButtonImage:in:]",
        "-[NSColorPicker provideNewButtonImage]",
        "-[NSColorPicker alphaControlAddedOrRemoved:]",
        "-[NSColorPicker setMode:]",
        "-[NSColorPicker _insertionOrder]",
        "-[NSColorPicker attachColorList:]",
        "-[NSColorPicker colorPanel]",
        "-[NSColorPicker detachColorList:]",
        "-[NSColorPicker viewSizeChanged:]",
    }
    assert selectors <= methods

    source = (appkit / "NSColorPicker.m").read_text()
    assert "_colorPanel = owningColorPanel" in source
    assert "return _colorPanel" in source
    assert "if (_imageObject == nil)" in source
    assert "[buttonCell setImage:newButtonImage]" in source
