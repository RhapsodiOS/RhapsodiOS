from pathlib import Path

from selector_check import source_methods


def test_input_manager_notifier_compares_flags_and_reports_changes_to_server():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    assert "-[NSInputManager _notifyInputServerIfNeeded]" in methods

    source = (appkit / "NSInputManager.m").read_text()
    body = source.rsplit("- (void)_notifyInputServerIfNeeded", 1)[1].split("\n}", 1)[0]
    assert "if (_flags != _lastFlags)" in body
    for status in ("0x08", "0x04", "0x10", "0x01", "0x20", "0x02", "0x40"):
        assert status in body
    assert "_inputClientChangedStatus:status" in body
    assert "inputClient:self" in body
    assert "_lastFlags = _flags;" in body


def test_input_manager_notifier_updates_client_snapshot_and_drains_pool():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    source = (appkit / "NSInputManager.m").read_text()
    body = source.rsplit("- (void)_notifyInputServerIfNeeded", 1)[1].split("\n}", 1)[0]
    assert "[_lastClient release];" in body
    assert "_lastClient = [_currentClient retain];" in body
    assert "[pool drain];" in body
