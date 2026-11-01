from pathlib import Path

from selector_check import source_methods


def test_status_item_implements_registered_selectors_and_forwarding():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    selectors = {
        "+[NSStatusItem(NSStatusItem_Private) _itemInStatusBar:withLength:withPriority:]",
        "-[NSStatusItem statusBar]",
        "-[NSStatusItem(NSStatusItemCommon) action]",
        "-[NSStatusItem(NSStatusItemCommon) attributedTitle]",
        "-[NSStatusItem(NSStatusItemCommon) highlightMode]",
        "-[NSStatusItem(NSStatusItemCommon) image]",
        "-[NSStatusItem(NSStatusItemCommon) isEnabled]",
        "-[NSStatusItem(NSStatusItemCommon) menu]",
        "-[NSStatusItem(NSStatusItemCommon) sendActionOn:]",
        "-[NSStatusItem(NSStatusItemCommon) setAction:]",
        "-[NSStatusItem(NSStatusItemCommon) setAttributedTitle:]",
        "-[NSStatusItem(NSStatusItemCommon) setEnabled:]",
        "-[NSStatusItem(NSStatusItemCommon) setHighlightMode:]",
        "-[NSStatusItem(NSStatusItemCommon) setImage:]",
        "-[NSStatusItem(NSStatusItemCommon) setMenu:]",
        "-[NSStatusItem(NSStatusItemCommon) setTitle:]",
        "-[NSStatusItem(NSStatusItemCommon) setToolTip:]",
        "-[NSStatusItem(NSStatusItemCommon) title]",
        "-[NSStatusItem(NSStatusItemCommon) toolTip]",
        "-[NSStatusItem(NSStatusItemView) setView:]",
        "-[NSStatusItem(NSStatusItemView) view]",
        "-[NSStatusItem(NSStatusItem_Private) _adjustLength]",
        "-[NSStatusItem(NSStatusItem_Private) _button]",
        "-[NSStatusItem(NSStatusItem_Private) _initInStatusBar:withLength:withPriority:]",
        "-[NSStatusItem(NSStatusItem_Private) _window]",
    }
    assert selectors == {method for method in methods if "NSStatusItem" in method}

    source = (appkit / "NSStatusItem.m").read_text()
    assert "_createStatusItemControlInWindow:_fWindow" in source
    assert "NSSquareStatusItemLength" in source
    assert "NSVariableStatusItemLength" in source
    assert "_setLength:length ofStatusItemWindow:_fWindow" in source
    assert "setNeedsDisplay:YES" in source
    assert "setStatusMenu:menu" in source
