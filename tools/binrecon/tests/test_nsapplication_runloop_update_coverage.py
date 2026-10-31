from pathlib import Path

from selector_check import source_methods


def test_application_windows_update_is_scheduled_once_in_default_and_modal_modes():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    assert "-[NSApplication setWindowsNeedUpdate:]" in methods

    source = (appkit / "NSApplication.m").read_text()
    body = source.rsplit("- (void)setWindowsNeedUpdate:(BOOL)needUpdate", 1)[1].split("\n}", 1)[0]
    assert "!_appFlags._postedWindowsNeedUpdateNote && needUpdate" in body
    assert "performSelector:@selector(_handleWindowsNeedUpdateNote:)" in body
    assert "NSUpdateWindowsRunLoopOrdering" in body
    assert "_appFlags._postedWindowsNeedUpdateNote = YES;" in body


def test_application_windows_update_handler_clears_flag_then_updates_and_notifies_input_manager():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    assert "-[NSApplication _handleWindowsNeedUpdateNote:]" in methods

    source = (appkit / "NSApplication.m").read_text()
    body = source.rsplit("- (void)_handleWindowsNeedUpdateNote:(id)notification", 1)[1].split("\n}", 1)[0]
    assert "_appFlags._postedWindowsNeedUpdateNote = NO;" in body
    assert "[self updateWindows];" in body
    assert "[[NSInputManager currentInputManager] _notifyInputServerIfNeeded];" in body


def test_application_delay_window_ordering_returns_self():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    assert "-[NSApplication delayWindowOrdering]" in methods

    source = (appkit / "NSApplication.m").read_text()
    body = source.rsplit("- (id)delayWindowOrdering", 1)[1].split("\n}", 1)[0]
    assert "return self;" in body


def test_application_open_file_state_reads_reference_global():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    assert "-[NSApplication _isDoingOpenFile]" in methods

    source = (appkit / "NSApplication.m").read_text()
    assert "static BOOL _doingOpenFile;" in source
    body = source.rsplit("- (BOOL)_isDoingOpenFile", 1)[1].split("\n}", 1)[0]
    assert "return _doingOpenFile;" in body


def test_application_prevent_window_ordering_forwards_to_window_server_helper():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    assert "-[NSApplication preventWindowOrdering]" in methods

    source = (appkit / "NSApplication.m").read_text()
    body = source.rsplit("- (void)preventWindowOrdering", 1)[1].split("\n}", 1)[0]
    assert "_NXPreventWindowOrdering(self, _cmd);" in body
