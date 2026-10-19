from pathlib import Path

from selector_check import source_methods


def test_control_owns_its_cell_and_forwards_target_action_and_tag():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    expected = {
        "-[NSControl isEnabled]",
        "-[NSControl setEnabled:]",
        "-[NSControl updateCell:]",
        "-[NSControl updateCellInside:]",
        "-[NSControl cell]",
        "-[NSControl setCell:]",
        "-[NSControl target]",
        "-[NSControl setTarget:]",
        "-[NSControl action]",
        "-[NSControl setAction:]",
        "-[NSControl tag]",
        "-[NSControl setTag:]",
        "-[NSActionCell target]",
        "-[NSActionCell setTarget:]",
        "-[NSCell _setControlView:]",
        "-[NSActionCell _setControlView:]",
    }
    assert expected <= methods

    control = (appkit / "NSControl.m").read_text()
    assert "if (cell == _cell)\n        return;" in control
    assert "[_cell _setControlView:nil];" in control
    assert "[_cell release];" in control
    assert "_cell = [cell retain];" in control
    assert "[_cell _setControlView:self];" in control
    assert "return [_cell target];" in control
    assert "return [_cell action];" in control


def test_action_cell_records_its_owning_control_view():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    source = (appkit / "NSActionCell.m").read_text()
    assert "_controlView = [view isKindOfClass:[NSView class]] ? view : nil;" in source
    assert "return _target;" in source
    assert "_target = target;" in source


def test_control_forwards_basic_cell_values_and_display_attributes():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    expected = {
        "-[NSControl isContinuous]",
        "-[NSControl setContinuous:]",
        "-[NSControl alignment]",
        "-[NSControl setAlignment:]",
        "-[NSControl font]",
        "-[NSControl setFont:]",
        "-[NSControl objectValue]",
        "-[NSControl setObjectValue:]",
        "-[NSControl stringValue]",
        "-[NSControl setStringValue:]",
        "-[NSControl intValue]",
        "-[NSControl setIntValue:]",
        "-[NSControl floatValue]",
        "-[NSControl setFloatValue:]",
        "-[NSControl doubleValue]",
        "-[NSControl setDoubleValue:]",
        "-[NSControl selectedCell]",
        "-[NSControl selectedTag]",
        "-[NSControl ignoresMultiClick]",
        "-[NSControl setIgnoresMultiClick:]",
    }
    assert expected <= methods

    source = (appkit / "NSControl.m").read_text()
    assert "return [_cell objectValue];" in source
    assert "[_cell setObjectValue:objectValue];" in source
    assert "return [_cell stringValue];" in source
    assert "[_cell setStringValue:stringValue];" in source
    assert "(_conFlags.enabled != 0)" in source
    assert "return _cell ? [_cell isEnabled]" in source
    assert "[_cell setEnabled:enabled];" in source
    assert "if ([_cell controlView] == self)\n            return;" in source
    assert "if (!enabled)\n        [self abortEditing];" in source
    assert "[self setNeedsDisplay:YES];" in source
    assert "_conFlags.ignoreMultiClick = ignoresMultiClick;" in source


def test_control_forwards_first_responder_and_sender_value_actions():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    expected = {
        "-[NSControl acceptsFirstResponder]",
        "-[NSControl refusesFirstResponder]",
        "-[NSControl setRefusesFirstResponder:]",
        "-[NSControl sendActionOn:]",
        "-[NSControl takeIntValueFrom:]",
        "-[NSControl takeFloatValueFrom:]",
        "-[NSControl takeDoubleValueFrom:]",
        "-[NSControl takeStringValueFrom:]",
        "-[NSControl takeObjectValueFrom:]",
        "-[NSControl attributedStringValue]",
        "-[NSControl setAttributedStringValue:]",
    }
    assert expected <= methods

    source = (appkit / "NSControl.m").read_text()
    assert "return [_cell acceptsFirstResponder];" in source
    assert "return [_cell sendActionOn:mask];" in source
    assert "[self setIntValue:[sender intValue]];" in source
    assert "[self setFloatValue:[sender floatValue]];" in source
    assert "[self setDoubleValue:[sender doubleValue]];" in source
    assert "[self setStringValue:[sender stringValue]];" in source
    assert "[self setObjectValue:[sender objectValue]];" in source


def test_control_cell_class_registry_inherits_and_creates_default_cells():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    expected = {
        "+[NSControl initialize]",
        "+[NSControl cellClass]",
        "+[NSControl setCellClass:]",
        "-[NSControl initWithFrame:]",
    }
    assert expected <= methods

    source = (appkit / "NSControl.m").read_text()
    assert "NSControlCellClasses" in source
    assert "[NSControlCellClasses objectForKey:controlClass]" in source
    assert "[controlClass superclass]" in source
    assert "[NSControlCellClasses setObject:cellClass forKey:self];" in source
    assert "[NSControlCellClasses removeObjectForKey:self];" in source
    assert "[[cellClass allocWithZone:[self zone]] initTextCell:@\"\"]" in source
    assert "[self setCell:cell];" in source
    assert "[self setVersion:41];" in source


def test_control_forwards_cell_sizing_and_interaction_settings():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    expected = {
        "-[NSControl isOpaque]",
        "-[NSControl needsPanelToBecomeKey]",
        "-[NSControl performClick:]",
        "-[NSControl sizeToFit]",
        "-[NSControl setFloatingPointFormat:left:right:]",
    }
    assert expected <= methods

    source = (appkit / "NSControl.m").read_text()
    assert "NSSize size = [_cell cellSize];" in source
    assert "[self setFrameSize:size];" in source
    assert "[_cell setFloatingPointFormat:autoRange left:leftDigits right:rightDigits];" in source
    assert "[_cell performClick:sender];" in source


def test_control_defers_cell_draw_info_until_its_size_changes():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    assert "-[NSControl calcSize]" in methods
    assert "-[NSControl setNeedsDisplay]" in methods

    source = (appkit / "NSControl.m").read_text()
    assert "if (_conFlags.calcSize)" in source
    assert "[_cell calcDrawInfo:[self bounds]];" in source
    assert "_conFlags.calcSize = NO;" in source
    assert "[super setNeedsDisplay:YES];" in source


def test_control_invalidates_frame_size_and_only_draws_its_own_cell():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    assert "-[NSControl setFrameSize:]" in methods
    assert "-[NSControl selectCell:]" in methods
    assert "-[NSControl drawCell:]" in methods

    source = (appkit / "NSControl.m").read_text()
    assert "if (oldSize.width != newSize.width || oldSize.height != newSize.height)" in source
    assert "[super setFrameSize:newSize];" in source
    assert "if (cell && cell == _cell)" in source
    assert "[self display];" in source
    assert "if (cell && cell == _cell && ![cell target])" in source
    assert "[cell setState:![cell target]];" in source
    assert "[self updateCell:_cell];" in source


def test_control_returns_only_its_own_active_field_editor():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    assert "-[NSControl currentEditor]" in methods

    source = (appkit / "NSControl.m").read_text()
    assert "[[self window] fieldEditor:NO forObject:self]" in source
    assert "id delegate = [editor delegate];" in source
    assert "if (delegate != self)\n        delegate = [delegate delegate];" in source
    assert "return delegate == self ? editor : nil;" in source


def test_control_abort_editing_detaches_editor_and_cell():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    assert "-[NSControl abortEditing]" in methods

    source = (appkit / "NSControl.m").read_text()
    assert "NSText *editor = [self currentEditor];" in source
    assert "[editor setDelegate:nil];" in source
    assert "[[self window] endEditingFor:nil];" in source
    assert "[cell endEditing:editor];" in source
    assert "return editor != nil;" in source


def test_control_dispatches_actions_through_the_shared_application():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    assert "-[NSControl sendAction:to:]" in methods
    source = (appkit / "NSControl.m").read_text()
    assert "[[NSApplication sharedApplication] sendAction:action to:target from:self]" in source


def test_control_updates_the_cell_first_responder_indicator():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    expected = {
        "-[NSControl becomeFirstResponder]",
        "-[NSControl resignFirstResponder]",
        "-[NSControl becomeKeyWindow]",
        "-[NSControl resignKeyWindow]",
    }
    assert expected <= methods

    source = (appkit / "NSControl.m").read_text()
    assert "[_cell respondsToSelector:@selector(setShowsFirstResponder:)]" in source
    assert "[_cell setShowsFirstResponder:YES];" in source
    assert "[_cell setShowsFirstResponder:NO];" in source
    assert "[[self window] firstResponder] == self" in source
    assert "[self setNeedsDisplay:YES];" in source


def test_control_commits_rich_text_or_plain_field_editor_content_to_the_cell():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    assert "-[NSControl validateEditing]" in methods
    assert "-[NSControl _validateEditing:]" in methods

    source = (appkit / "NSControl.m").read_text()
    assert "NSText *editor = [self currentEditor];" in source
    assert "[self _validateEditing:editor];" in source
    assert "[cell allowsEditingTextAttributes]" in source
    assert "[editor isKindOfClass:[NSTextView class]]" in source
    assert "[cell setAttributedStringValue:[(NSTextView *)editor textStorage]];" in source
    assert "[cell setStringValue:[editor string]];" in source


def test_control_uses_cell_context_menu_before_view_fallback():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    assert "-[NSControl menuForEvent:]" in methods

    source = (appkit / "NSControl.m").read_text()
    assert "[_cell menuForEvent:event inRect:[self bounds] ofView:self]" in source
    assert "return menu ? menu : [super menuForEvent:event];" in source


def test_control_forwards_cursor_and_right_mouse_events_to_its_cell():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    assert {
        "-[NSControl mouseDownFlags]",
        "-[NSControl resetCursorRects]",
        "-[NSControl rightMouseDown:]",
    } <= methods

    source = (appkit / "NSControl.m").read_text()
    assert "return [_cell mouseDownFlags];" in source
    assert "NSRect rect = [self bounds];" in source
    assert "if (!NSIsEmptyRect(rect))" in source
    assert "[_cell resetCursorRect:rect inView:self];" in source
    assert "[self mouseDown:event];" in source


def test_control_draws_its_cell_with_window_focus_highlighting():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    assert "-[NSControl drawRect:]" in methods

    source = (appkit / "NSControl.m").read_text()
    assert "NSWindow *window = [self window];" in source
    assert "if ([window firstResponder] == self)" in source
    assert "highlight = [window isKeyWindow];" in source
    assert "[_cell highlight:highlight withFrame:[self bounds] inView:self];" in source
    assert "[_cell drawWithFrame:[self bounds] inView:self];" in source
    assert "[_cell highlight:NO withFrame:[self bounds] inView:self];" in source


def test_control_reports_editable_only_when_its_cell_is_editable_and_selectable():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    assert "-[NSControl _hasEditableCell]" in methods

    source = (appkit / "NSControl.m").read_text()
    assert "return _cell && [_cell isEditable] && [_cell isSelectable];" in source


def test_control_releases_its_cell_after_aborting_editing_on_deallocation():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    assert "-[NSControl dealloc]" in methods

    source = (appkit / "NSControl.m").read_text()
    assert "[self abortEditing];" in source
    assert "[_cell release];" in source
    assert "_cell = nil;" in source
    assert "[super dealloc];" in source
