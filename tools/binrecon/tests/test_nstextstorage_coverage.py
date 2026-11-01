from pathlib import Path

from selector_check import source_methods


def test_text_storage_tracks_edits_and_notifies_layout_managers():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    expected = {
        "-[NSTextStorage _isEditing]",
        "-[NSTextStorage _lockForReading]",
        "-[NSTextStorage _lockForWriting]",
        "-[NSTextStorage _notifyEdited:range:changeInLength:invalidatedRange:]",
        "-[NSTextStorage _unlock]",
        "-[NSTextStorage addLayoutManager:]",
        "-[NSTextStorage changeInLength]",
        "-[NSTextStorage edited:range:changeInLength:]",
        "-[NSTextStorage editedMask]",
        "-[NSTextStorage editedRange]",
        "-[NSTextStorage endEditing]",
        "-[NSTextStorage init]",
        "-[NSTextStorage layoutManagers]",
        "-[NSTextStorage processEditing]",
        "-[NSTextStorage removeLayoutManager:]",
        "-[NSTextStorage setDelegate:]",
        "-[NSTextStorage delegate]",
        "-[NSTextStorage beginEditing]",
        "-[NSTextStorage dealloc]",
    }
    assert expected <= methods

    source = (appkit / "NSTextStorage.m").read_text()
    assert "_editedRange.location = NSNotFound;" in source
    assert "NSTextStorageWillProcessEditingNotification" in source
    assert "NSTextStorageDidProcessEditingNotification" in source
    assert "[layoutManager setTextStorage:self];" in source
    assert "textStorage:self" in source
