from pathlib import Path

from selector_check import source_methods


def test_nib_outlet_connector_installs_outlet_through_setter_or_ivar():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    assert "+[NSNibOutletConnector initialize]" in methods
    assert "-[NSNibOutletConnector initWithCoder:]" in methods
    assert "-[NSNibOutletConnector establishConnection]" in methods

    source = (appkit / "NSNibOutletConnector.m").read_text()
    body = source.rsplit("- (void)establishConnection", 1)[1].split("\n}", 1)[0]
    assert 'stringWithFormat:@"set%@%@:"' in body
    assert "respondsToSelector:action" in body
    assert "performSelector:action withObject:source" in body
    assert "object_setInstanceVariable(destination, [label UTF8String], source)" in body


def test_nib_outlet_connector_migrates_old_outlet_names_for_legacy_archives():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    source = (appkit / "NSNibOutletConnector.m").read_text()
    assert "static NSString *NSNibOutletConnectorCompatibleName" in source
    assert 'isEqualToString:@"keyView"' in source
    assert 'NSClassFromString(@"NSWindowTemplate")' in source
    assert 'return @"initialFirstResponder";' in source
    assert 'isEqualToString:@"textDelegate"' in source
    assert 'return @"delegate";' in source
    assert 'versionForClassName:@"NSNibOutletConnector"] <= 206' in source
