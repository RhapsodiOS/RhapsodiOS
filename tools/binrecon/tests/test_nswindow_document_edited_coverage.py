from pathlib import Path

from selector_check import source_methods


def test_document_edited_state_updates_frame_and_window_menu():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    assert "-[NSWindow _setDocumentEdited:]" in methods
    assert "-[NSWindow setDocumentEdited:]" in methods

    source = (appkit / "NSWindow.m").read_text()
    setter = source.rsplit("- (void)_setDocumentEdited:(BOOL)flag", 1)[1].split("\n}", 1)[0]
    assert "if (_wFlags.docEdited == flag)" in setter
    assert "return;" in setter
    assert "_wFlags.docEdited = flag;" in setter
    assert "[_borderView setDocumentEdited:flag]" in setter
    assert "[NSApp updateWindowsItem:self]" in setter

    public = source.rsplit("- (void)setDocumentEdited:(BOOL)flag", 1)[1].split("\n}", 1)[0]
    assert "[self _setDocumentEdited:flag]" in public
    assert 'NSInterfaceStyleForKey(@"NSWindowInterfaceStyle", self) == 3' in public
    assert "[_counterpart _setDocumentEdited:flag]" in public
