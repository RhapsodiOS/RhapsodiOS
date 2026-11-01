from pathlib import Path

from selector_check import source_methods


def test_paragraph_style_and_tab_accessors():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    expected = {
        "+[NSParagraphStyle defaultParagraphStyle]",
        "-[NSParagraphStyle _initWithParagraphStyle:]",
        "-[NSParagraphStyle alignment]",
        "-[NSParagraphStyle firstLineHeadIndent]",
        "-[NSParagraphStyle headIndent]",
        "-[NSParagraphStyle lineBreakMode]",
        "-[NSParagraphStyle lineSpacing]",
        "-[NSParagraphStyle maximumLineHeight]",
        "-[NSParagraphStyle minimumLineHeight]",
        "-[NSParagraphStyle paragraphSpacing]",
        "-[NSParagraphStyle tabStops]",
        "-[NSParagraphStyle tailIndent]",
        "-[NSTextTab initWithType:location:]",
        "-[NSTextTab location]",
        "-[NSTextTab tabStopType]",
        "-[NSMutableParagraphStyle _mutateTabStops]",
        "-[NSMutableParagraphStyle addTabStop:]",
        "-[NSMutableParagraphStyle removeTabStop:]",
        "-[NSMutableParagraphStyle setAlignment:]",
        "-[NSMutableParagraphStyle setFirstLineHeadIndent:]",
        "-[NSMutableParagraphStyle setHeadIndent:]",
        "-[NSMutableParagraphStyle setLineBreakMode:]",
        "-[NSMutableParagraphStyle setLineSpacing:]",
        "-[NSMutableParagraphStyle setMaximumLineHeight:]",
        "-[NSMutableParagraphStyle setMinimumLineHeight:]",
        "-[NSMutableParagraphStyle setParagraphSpacing:]",
        "-[NSMutableParagraphStyle setParagraphStyle:]",
        "-[NSMutableParagraphStyle setTabStops:]",
        "-[NSMutableParagraphStyle setTailIndent:]",
    }
    assert expected <= methods

    source = (appkit / "NSParagraphStyle.m").read_text()
    assert "return _lineSpacing;" in source
    assert "return _paragraphSpacing;" in source
    assert "return (NSTextAlignment)_flags.alignment;" in source
    assert "return (NSLineBreakMode)_flags.lineBreakMode;" in source
    assert "return _tabStops ? _tabStops : defaultTabStops();" in source
    assert "_tabStops = [style->_tabStops copyWithZone:[self zone]];" in source
    assert "return _location;" in source
    assert "return (NSTextTabType)_flags.type;" in source
    assert "index <= 12" in source
    assert "28.0f * index" in source
    assert "NSArray *tabStops = _tabStops ? _tabStops : defaultTabStops();" in source
    assert "NSMutableArray *mutableStops = [tabStops mutableCopyWithZone:[self zone]];" in source
    assert "_tabStops = mutableStops;" in source
    assert "[self _mutateTabStops];" in source
    assert "[mutableStops insertObject:tab atIndex:index];" in source
    assert "[mutableStops addObject:tab];" in source
    assert "_flags.alignment = alignment;" in source
    assert "_flags.lineBreakMode = lineBreakMode;" in source
    assert "[self setTabStops:[style tabStops]];" in source
