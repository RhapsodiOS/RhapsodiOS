from pathlib import Path

from selector_check import source_methods


def test_typesetter_implements_reference_selectors_and_base_behavior():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    selectors = {
        "+[NSTypesetter printingAdjustmentInLayoutManager:forNominallySpacedGlyphRange:packedGlyphs:count:]",
        "+[NSTypesetter sharedSystemTypesetter]",
        "-[NSTypesetter baselineOffsetInLayoutManager:glyphIndex:]",
        "-[NSTypesetter layoutGlyphsInLayoutManager:startingAtGlyphIndex:maxNumberOfLineFragments:nextGlyphIndex:]",
    }
    assert selectors <= methods

    source = (appkit / "NSTypesetter.m").read_text()
    assert "[NSSimpleHorizontalTypesetter sharedInstance]" in source
    assert "requestConcreteImplementation(self, _cmd)" in source
    assert "return NSBaselineNotSet" in source
    assert "substituteFontForFont:" in source
    assert "_widthOfPackedGlyphs:packedGlyphs count:packedGlyphsCount" in source
    assert "10000.0" in source
