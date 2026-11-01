from pathlib import Path

from selector_check import source_methods


def test_text_attachment_implements_reference_selectors():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    selectors = {
        "-[NSTextAttachment attachmentCell]",
        "-[NSTextAttachment setAttachmentCell:]",
        "-[NSTextAttachment initWithFileWrapper:]",
        "-[NSTextAttachment copyWithZone:]",
        "-[NSTextAttachment dealloc]",
        "-[NSTextAttachment description]",
        "-[NSTextAttachment encodeWithCoder:]",
        "-[NSTextAttachment fileWrapper]",
        "-[NSTextAttachment initWithCoder:]",
        "-[NSTextAttachment setFileWrapper:]",
    }
    assert selectors <= methods

    source = (appkit / "NSTextAttachment.m").read_text()
    assert "_flags.cellWasExplicitlySet" in source
    assert "setAttachment:self" in source
    assert "NSImageRep imageRepClassForData" in source
    assert 'encodeValuesOfObjCTypes:"c@"' in source
    assert 'decodeValuesOfObjCTypes:"c@"' in source
