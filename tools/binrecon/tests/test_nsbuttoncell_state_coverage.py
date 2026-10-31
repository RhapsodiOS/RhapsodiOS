from pathlib import Path

from selector_check import source_methods


def test_button_cell_state_accessors_match_reference_storage():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    expected = {
        "-[NSButtonCell gradientType]",
        "-[NSButtonCell setGradientType:]",
        "-[NSButtonCell sound]",
        "-[NSButtonCell setSound:]",
        "-[NSButtonCell isBordered]",
        "-[NSButtonCell isTransparent]",
        "-[NSButtonCell setBordered:]",
        "-[NSButtonCell setTransparent:]",
        "-[NSButtonCell highlightsBy]",
        "-[NSButtonCell setHighlightsBy:]",
        "-[NSButtonCell showsStateBy]",
        "-[NSButtonCell setShowsStateBy:]",
        "-[NSButtonCell _altContents]",
        "-[NSButtonCell _setAltContents:]",
        "-[NSButtonCell _sound]",
        "-[NSButtonCell _setSound:]",
        "-[NSButtonCell keyEquivalent]",
        "-[NSButtonCell setKeyEquivalent:]",
        "-[NSButtonCell keyEquivalentModifierMask]",
        "-[NSButtonCell setKeyEquivalentModifierMask:]",
        "-[NSButtonCell title]",
        "-[NSButtonCell setTitle:]",
        "-[NSButtonCell alternateTitle]",
        "-[NSButtonCell setAlternateTitle:]",
        "-[NSButtonCell imagePosition]",
        "-[NSButtonCell setImagePosition:]",
        "-[NSButtonCell(NSButtonCellPrivate) _hasImage]",
        "-[NSButtonCell(NSButtonCellPrivate) _hasTitle]",
        "-[NSButtonCell alternateMnemonicLocation]",
        "-[NSButtonCell setAlternateMnemonicLocation:]",
        "-[NSButtonCell(NSButtonCellBezelStyles) bezelStyle]",
        "-[NSButtonCell(NSButtonCellBezelStyles) setBezelStyle:]",
        "-[NSButtonCell(NSButtonCellPrivate) showsBorderOnlyWhileMouseInside]",
        "-[NSButtonCell(NSButtonCellPrivate) setShowsBorderOnlyWhileMouseInside:]",
        "-[NSButtonCell(NSButtonCellPrivate) mouseEntered:]",
        "-[NSButtonCell(NSButtonCellPrivate) mouseExited:]",
        "-[NSButtonCell(NSButtonCellPrivate) imageDimsWhenDisabled]",
        "-[NSButtonCell(NSButtonCellPrivate) setImageDimsWhenDisabled:]",
    }
    assert expected <= methods

    source = (appkit / "NSButtonCell.m").read_text()
    assert "_bcFlags.gradientType" in source
    assert "_bcFlags.doesNotDimImage" in source
    assert "_sound" in source
    assert "_altContents" in source
    assert "_keyEquivalent" in source
    assert "_contents" in source
    assert "_bcFlags2.keyEquivalentModifierMask" in source
    assert "_bcFlags2.bezelStyle" in source
    assert "_bcFlags2.showsBorderOnlyWhileMouseInside" in source
    assert "_bcFlags2.mouseInside" in source
    assert "_bcFlags.alternateMnemonicLocation" in source
    assert "_bcFlags.imageOverlaps" in source
    assert "_bcFlags.bordered" in source
    assert "_bcFlags.transparent" in source
    assert "_bcFlags.pushIn" in source
    assert "_bcFlags.changeContents" in source
    assert "setNeedsDisplay:YES" in source


def test_button_cell_state_cycle_and_highlight_behavior_match_reference():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    assert "-[NSButtonCell nextState]" in methods
    assert "-[NSButtonCell _highlightsWithHighlightRect]" in methods

    source = (appkit / "NSButtonCell.m").read_text()
    assert "if ([self buttonType] == NSRadioButton)\n        return NSOnState;" in source
    assert "return [super nextState];" in source
    assert "- (BOOL)_highlightsWithHighlightRect\n{\n    return NO;\n}" in source


def test_button_cell_transparency_blocks_highlight_state_changes():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    assert "-[NSButtonCell _shouldSetHighlightToFlag:]" in methods

    source = (appkit / "NSButtonCell.m").read_text()
    assert "- (BOOL)_shouldSetHighlightToFlag:(BOOL)flag\n{\n    if (_bcFlags.transparent)\n        return NO;\n    return [super _shouldSetHighlightToFlag:flag];\n}" in source


def test_button_cell_default_indicator_capability_uses_reference_flag():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    assert "-[NSButtonCell(NSButtonCellPrivate) _canBecomeDefaultButtonCell]" in methods

    source = (appkit / "NSButtonCell.m").read_text()
    assert "- (BOOL)_canBecomeDefaultButtonCell\n{\n    return _bcFlags.useButtonImageSource;\n}" in source
