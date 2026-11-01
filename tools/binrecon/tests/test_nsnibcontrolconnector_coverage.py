from pathlib import Path

from selector_check import source_methods


def test_nib_control_connector_installs_target_and_resolved_action():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    assert "-[NSNibControlConnector establishConnection]" in methods

    source = (appkit / "NSNibControlConnector.m").read_text()
    body = source.rsplit("- (void)establishConnection", 1)[1].split("\n}", 1)[0]
    assert "[self source]" in body
    assert "[self destination]" in body
    assert "[self label]" in body
    assert "[source setTarget:destination]" in body
    assert "respondsToSelector:action" in body
    assert "[source setAction:action]" in body


def test_nib_control_connector_uses_reference_action_registration_mode():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    source = (appkit / "NSNibControlConnector.m").read_text()
    assert "static BOOL NSNibControlConnectorUsesMappedActions;" in source
    assert "[self setVersion:207]" in source
    assert "@selector(isInInterfaceBuilder)" in source
    assert "sel_getUid(name)" in source
    assert "sel_registerName(name)" in source


def test_nib_control_connector_normalizes_archived_action_labels():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    assert "-[NSNibControlConnector initWithCoder:]" in methods

    source = (appkit / "NSNibControlConnector.m").read_text()
    initializer = source.rsplit("- (id)initWithCoder:(NSCoder *)coder", 1)[1].split("\n}", 1)[0]
    assert "[super initWithCoder:coder]" in initializer
    assert "rangeOfString:@\":\"" in initializer
    assert "NSNotFound" in initializer
    assert "stringByAppendingString:@\":\"" in initializer
    assert "versionForClassName:@\"NSNibControlConnector\"" in initializer
    assert 'versionForClassName:@"NSNibControlConnector"] <= 206' in initializer


def test_nib_control_connector_maps_legacy_action_names():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    source = (appkit / "NSNibControlConnector.m").read_text()
    for old_action, new_action in (
        ("alignSelLeft:", "alignLeft:"),
        ("alignSelRight:", "alignRight:"),
        ("alignSelCenter:", "alignCenter:"),
        ("printPSCode:", "print:"),
        ("smartPrintPSCode:", "print:"),
        ("faxPSCode:", "fax:"),
        ("smartFaxPSCode:", "fax:"),
        ("showHelpPanel:", "showHelp:"),
    ):
        assert f'@"{old_action}"' in source
        assert f'@"{new_action}"' in source
    assert 'NSLog(@"The action method `%@\' is invalid; please remove it from your .nib file"' in source
