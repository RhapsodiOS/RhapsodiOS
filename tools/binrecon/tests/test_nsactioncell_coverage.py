from pathlib import Path

from selector_check import source_methods


def test_action_cell_state_selectors_use_their_declared_storage():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    assert {
        "-[NSActionCell controlView]",
        "-[NSActionCell setAction:]",
        "-[NSActionCell tag]",
        "-[NSActionCell setTag:]",
    } <= methods

    source = (appkit / "NSActionCell.m").read_text()
    assert "return _controlView;" in source
    assert "_action = action;" in source
    assert "return _tag;" in source
    assert "_tag = tag;" in source


def test_action_cell_overrides_the_base_action_with_its_stored_selector():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    assert "-[NSActionCell action]" in methods
    assert "-[NSCell action]" in methods

    action_cell = (appkit / "NSActionCell.m").read_text()
    cell = (appkit / "NSCell.m").read_text()
    assert "return _action;" in action_cell
    assert "- (SEL)action\n{\n    return nil;\n}" in cell


def test_action_cell_refreshes_the_control_after_image_or_state_changes():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    assert {
        "-[NSActionCell setImage:]",
        "-[NSActionCell setEnabled:]",
        "-[NSActionCell setBezeled:]",
        "-[NSActionCell setBordered:]",
    } <= methods

    source = (appkit / "NSActionCell.m").read_text()
    assert "NSImage *oldImage = [self image];" in source
    assert "[super setImage:image];" in source
    assert "if (![oldImage isEqual:[self image]])" in source
    assert "[(NSControl *)[self controlView] updateCell:self];" in source
    assert "[super setEnabled:enabled];" in source
    assert "[super setBezeled:bezeled];" in source
    assert "[super setBordered:bordered];" in source


def test_action_cell_refreshes_alignment_changes_only_when_the_value_differs():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    assert "-[NSActionCell setAlignment:]" in methods

    source = (appkit / "NSActionCell.m").read_text()
    assert "if ([self alignment] != alignment)" in source
    assert "[super setAlignment:alignment];" in source
    assert "[(NSControl *)[self controlView] updateCell:self];" in source
