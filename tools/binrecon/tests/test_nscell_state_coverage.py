from pathlib import Path

from selector_check import source_methods


def test_cell_state_selectors_read_and_update_reference_flags():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    expected = {
        "-[NSCell type]",
        "-[NSCell state]",
        "-[NSCell setState:]",
        "-[NSCell isEnabled]",
        "-[NSCell setEnabled:]",
        "-[NSCell isEditable]",
        "-[NSCell setEditable:]",
        "-[NSCell isSelectable]",
        "-[NSCell setSelectable:]",
        "-[NSCell isHighlighted]",
        "-[NSCell isContinuous]",
        "-[NSCell setContinuous:]",
        "-[NSCell isScrollable]",
        "-[NSCell wraps]",
        "-[NSCell isBordered]",
        "-[NSCell setBordered:]",
        "-[NSCell isBezeled]",
        "-[NSCell setBezeled:]",
        "-[NSCell(NSCellMixedState) allowsMixedState]",
        "-[NSCell(NSCellMixedState) setAllowsMixedState:]",
        "-[NSCell allowsEditingTextAttributes]",
        "-[NSCell setAllowsEditingTextAttributes:]",
        "-[NSCell importsGraphics]",
        "-[NSCell setImportsGraphics:]",
        "-[NSCell sendsActionOnEndEditing]",
        "-[NSCell setSendsActionOnEndEditing:]",
        "-[NSCell refusesFirstResponder]",
        "-[NSCell setRefusesFirstResponder:]",
        "-[NSCell showsFirstResponder]",
        "-[NSCell setShowsFirstResponder:]",
        "-[NSCell mnemonicLocation]",
        "-[NSCell setMnemonicLocation:]",
        "-[NSCell acceptsFirstResponder]",
        "-[NSCell hasValidObjectValue]",
        "-[NSCell isOpaque]",
        "-[NSCell alignment]",
        "-[NSCell _allowsContextMenus]",
        "-[NSCell _contents]",
        "-[NSCell _highlightsWithHighlightRect]",
        "-[NSCell _prefersTrackingWhenDisabled]",
        "-[NSCell _useUserKeyEquivalent]",
        "-[NSCell _usesUserKeyEquivalent]",
        "-[NSCell controlView]",
        "-[NSCell keyEquivalent]",
        "-[NSCell setType:]",
        "-[NSCell _convertToText:]",
    }
    assert expected <= methods

    source = (appkit / "NSCell.m").read_text()
    for flag in (
        "_cFlags.type",
        "_cFlags.state",
        "_cFlags.inMixedState",
        "_cFlags.allowsMixedState",
        "_cFlags.disabled",
        "_cFlags.editable",
        "_cFlags.selectable",
        "_cFlags.wasSelectable",
        "_cFlags.highlighted",
        "_cFlags.continuous",
        "_cFlags.scrollable",
        "_cFlags.noWrap",
        "_cFlags.bordered",
        "_cFlags.bezeled",
        "_cFlags.allowsEditingTextAttributes",
        "_cFlags.importsGraphics",
        "_cFlags.sendsActionOnEndEditing",
        "_cFlags.refusesFirstResponder",
        "_cFlags.showsFirstResponder",
        "_cFlags.mnemonicLocation",
        "_cFlags.hasInvalidObject",
        "_cFlags.alignment",
        "_cFlags.useUserKeyEquivalent",
    ):
        assert flag in source


def test_cell_mixed_state_is_reported_only_when_allowed():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    source = (appkit / "NSCell.m").read_text()
    assert "if (_cFlags.allowsMixedState && _cFlags.inMixedState)\n        return NSMixedState;" in source
    assert "if (_cFlags.allowsMixedState)\n        _cFlags.inMixedState = state == NSMixedState;" in source


def test_cell_text_attribute_flags_remain_mutually_consistent():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    source = (appkit / "NSCell.m").read_text()
    assert "if (!allowsEditingTextAttributes)\n        _cFlags.importsGraphics = NO;" in source
    assert "if (importsGraphics)\n        _cFlags.allowsEditingTextAttributes = YES;" in source


def test_cell_border_and_bezel_styles_are_exclusive_and_refresh_the_control():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    source = (appkit / "NSCell.m").read_text()
    assert "_cFlags.bordered = bordered;\n    _cFlags.bezeled = NO;" in source
    assert "_cFlags.bezeled = bezeled;\n    _cFlags.bordered = NO;" in source
    assert "[(NSControl *)[self controlView] updateCell:self];" in source


def test_cell_mnemonic_location_uses_the_reference_sentinel():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    source = (appkit / "NSCell.m").read_text()
    assert "_cFlags.mnemonicLocation == 0xFF" in source
    assert "(location == (NSUInteger)0x7FFFFFFF || location > 0xFE) ? 0xFF : location" in source


def test_cell_first_responder_and_value_validity_follow_state_flags():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    source = (appkit / "NSCell.m").read_text()
    assert "return !_cFlags.refusesFirstResponder && [self isEnabled];" in source
    assert "return !_cFlags.hasInvalidObject;" in source


def test_cell_private_drawing_and_key_equivalent_flags_match_reference():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    source = (appkit / "NSCell.m").read_text()
    assert "- (BOOL)_allowsContextMenus\n{\n    return YES;\n}" in source
    assert "- (BOOL)_highlightsWithHighlightRect\n{\n    return YES;\n}" in source
    assert "- (BOOL)_prefersTrackingWhenDisabled\n{\n    return NO;\n}" in source
    assert "_cFlags.useUserKeyEquivalent = YES;\n    return self;" in source


def test_base_cell_has_no_control_view_and_uses_an_empty_key_equivalent():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    source = (appkit / "NSCell.m").read_text()
    assert "- (NSView *)controlView\n{\n    return nil;\n}" in source
    assert "- (NSString *)keyEquivalent\n{\n    return @\"\";\n}" in source


def test_cell_type_changes_convert_text_and_image_cells_as_reference_does():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    source = (appkit / "NSCell.m").read_text()
    assert "if (type == NSTextCellType)\n        [self _convertToText:@\"Cell\"];" in source
    assert "else if (type == NSImageCellType)\n        [self setImage:nil];" in source
    assert "_cFlags.type = type;" in source
    assert "[_support release];" in source
    assert "_cFlags.type = NSTextCellType;" in source
    assert "[NSFont messageFontOfSize:12.0f]" in source
    assert "[self setObjectValue:string];" in source



def test_cell_object_value_tracks_validity_and_uses_string_accessors():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    assert "-[NSCell objectValue]" in methods
    assert "-[NSCell setObjectValue:]" in methods

    source = (appkit / "NSCell.m").read_text()
    assert "if (_cFlags.hasInvalidObject)\n        return nil;\n    return [self _contents];" in source
    assert "_cFlags.hasInvalidObject = NO;\n    [self _setContents:objectValue];" in source
    assert "-[NSCell _setContents:]" in methods
    assert "contents ? [contents copyWithZone:[self zone]] : nil;" in source


def test_cell_image_accessors_use_image_type_and_support_storage():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    assert "-[NSCell image]" in methods
    assert "-[NSCell setImage:]" in methods

    source = (appkit / "NSCell.m").read_text()
    assert "if (_cFlags.type == NSImageCellType)\n        return (NSImage *)_support;" in source
    assert "if (_cFlags.type != NSImageCellType || ![[self image] isEqual:image])" in source
    assert "_cFlags.type = NSImageCellType;" in source
    assert "[_support release];" in source
    assert "_support = [image retain];" in source


def test_cell_drawing_and_title_rects_apply_border_insets():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    assert "-[NSCell drawingRectForBounds:]" in methods
    assert "-[NSCell titleRectForBounds:]" in methods

    source = (appkit / "NSCell.m").read_text()
    assert "inset = _cFlags.bezeled ? 2.0f : 3.0f;" in source
    assert "return NSInsetRect(bounds, inset, inset);" in source
    assert "if (_cFlags.type == NSTextCellType)\n        return NSInsetRect(bounds, inset, inset);" in source


def test_cell_formatter_storage_and_entry_validation_use_reference_map():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    assert "-[NSCell formatter]" in methods
    assert "-[NSCell setFormatter:]" in methods
    assert "-[NSCell isEntryAcceptable:]" in methods

    source = (appkit / "NSCell.m").read_text()
    assert "static NSMapTable *NSCellFormatters;" in source
    assert "NSMapGet(NSCellFormatters, self)" in source
    assert "NSMapInsert(NSCellFormatters, self, formatter);" in source
    assert "NSMapRemove(NSCellFormatters, self);" in source
    assert "[formatter getObjectValue:&objectValue forString:string errorDescription:NULL]" in source


def test_cell_string_values_format_and_parse_contents_with_invalid_state():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    assert "-[NSCell stringValue]" in methods
    assert "-[NSCell setStringValue:]" in methods
    assert "-[NSCell _formatObjectValue:invalid:]" in methods
    assert "-[NSCell _objectValue:forString:]" in methods

    source = (appkit / "NSCell.m").read_text()
    assert "return [self _formatObjectValue:_contents invalid:_cFlags.hasInvalidObject];" in source
    assert "BOOL valid = [self _objectValue:&objectValue forString:stringValue];" in source
    assert "_cFlags.hasInvalidObject = !valid;" in source


def test_cell_attributed_string_values_follow_formatter_and_invalid_fallbacks():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    assert "-[NSCell attributedStringValue]" in methods
    assert "-[NSCell setAttributedStringValue:]" in methods
    assert "-[NSCell _attributedStringValue:invalid:]" in methods
    assert "-[NSCell _unformattedAttributedStringValue:]" in methods
    assert "-[NSCell _textAttributes]" in methods

    source = (appkit / "NSCell.m").read_text()
    assert "[formatter attributedStringForObjectValue:objectValue" in source
    assert "withDefaultAttributes:[self _textAttributes]]" in source
    assert "[formatter editingStringForObjectValue:objectValue]" in source
    assert "_cFlags.hasInvalidObject = !valid;" in source
    assert "if (!objectValue || invalid)" in source


def test_cell_numeric_values_convert_through_formatted_strings_and_numbers():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    expected = {
        "-[NSCell intValue]",
        "-[NSCell setIntValue:]",
        "-[NSCell floatValue]",
        "-[NSCell setFloatValue:]",
        "-[NSCell doubleValue]",
        "-[NSCell setDoubleValue:]",
        "-[NSCell takeIntValueFrom:]",
        "-[NSCell takeFloatValueFrom:]",
        "-[NSCell takeDoubleValueFrom:]",
        "-[NSCell takeStringValueFrom:]",
        "-[NSCell takeObjectValueFrom:]",
    }
    assert expected <= methods

    source = (appkit / "NSCell.m").read_text()
    assert "if (_cFlags.type != NSTextCellType)\n        return 0;" in source
    assert "return [_contents intValue];" in source
    assert "return [[self stringValue] intValue];" in source
    assert "NSNumber *number;" in source
    assert "number = [NSNumber numberWithInt:intValue];" in source
    assert "[self setObjectValue:number];" in source
    assert "return [self doubleValue];" in source
    assert "[self setDoubleValue:floatValue];" in source
    assert "[self setIntValue:[sender intValue]];" in source
    assert "[self setDoubleValue:[sender doubleValue]];" in source


def test_cell_computes_a_centered_image_rect_and_keeps_draw_info_hook_empty():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    assert {
        "-[NSCell imageRectForBounds:]",
        "-[NSCell calcDrawInfo:]",
    } <= methods

    source = (appkit / "NSCell.m").read_text()
    assert "NSImage *image = [self image];" in source
    assert "if (!image)\n        return bounds;" in source
    assert "if (_cFlags.bordered || _cFlags.bezeled)\n        inset = _cFlags.bezeled ? 2.0f : 3.0f;" in source
    assert "contentRect = NSInsetRect(bounds, inset, inset);" in source
    assert "return NSMakeRect(contentRect.origin.x" in source
    assert "- (void)calcDrawInfo:(NSRect)rect\n{\n}" in source


def test_cell_font_storage_tracks_text_cell_type_and_replaces_image_support():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    assert {"-[NSCell font]", "-[NSCell setFont:]"} <= methods

    source = (appkit / "NSCell.m").read_text()
    assert "return _cFlags.type == NSTextCellType ? (NSFont *)_support : nil;" in source
    assert "if (_cFlags.type != NSTextCellType || !_support)" in source
    assert "_cFlags.type = NSTextCellType;" in source
    assert "_support = [font retain];" in source
    assert "NSFont *defaultFont;" in source
    assert "defaultFont = [NSFont messageFontOfSize:12.0f];" in source
