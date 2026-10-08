import re
from pathlib import Path

import pytest


SOURCE_PATH = (
    Path(__file__).resolve().parents[3]
    / "src/Applications/Administration/Terminal/FieldView.m"
)
TERMINAL_SOURCE_PATH = SOURCE_PATH.with_name("Terminal.m")
DEFAULTS_SOURCE_PATH = SOURCE_PATH.with_name("TerminalDefaults.m")


def method_body(source, signature):
    start = source.index(signature)
    body_start = source.index("{", start)
    end = source.find("\n- (", body_start)
    return source[body_start:end if end >= 0 else None]


def test_default_color_loader_catches_objc_exceptions_like_ppc():
    source = DEFAULTS_SOURCE_PATH.read_text(encoding="utf-8")
    method = source.split("void getDefaultColors(id *colors)", 1)[1].split(
        "\nTerminalEmulationDefaults *defaultsFromDB", 1
    )[0]
    compact = re.sub(r"\s+", " ", method)

    assert "NS_DURING" in method
    assert "NS_HANDLER (void)localException; NS_ENDHANDLER" in compact


def test_child_exit_clears_and_flushes_cursor_only_for_key_window():
    source = SOURCE_PATH.with_name("Terminal.m").read_text(encoding="utf-8")
    method = source.split("- (void)childExit:(id)sender status:(id)statusObject", 1)[1].split(
        "\n- (BOOL)windowShouldClose:", 1
    )[0]
    compact = re.sub(r"\s+", " ", method)

    assert (
        "if ([[self window] isKeyWindow]) { [self lockFocus]; [self _clearcursor]; "
        "[self unlockFocus]; [[self window] flushWindow]; } "
        "[self setDrawCursOK:0];"
    ) in compact


def test_child_exit_closes_exited_shell_after_killing_it():
    source = TERMINAL_SOURCE_PATH.read_text(encoding="utf-8")
    method = method_body(source, "- (void)childExit:(id)sender status:")
    selectors = re.findall(r"\[exitedShell\s+([A-Za-z_]\w*)", method)

    assert selectors[:2] == ["kill", "close"]


def test_dirt_monitor_retains_and_registers_notify_port_in_ppc_order():
    source = SOURCE_PATH.with_name("DirtMonitor.m").read_text(encoding="utf-8")
    method = method_body(source, "- (id)init")
    start = method.index("[NSPort portWithMachPort:port]")
    selectors = [
        method.find("] retain]", start),
        method.find("[notifyPort setDelegate:self]", start),
        method.find("[NSRunLoop currentRunLoop]", start),
        method.find("[runLoop addPort:notifyPort forMode:NSDefaultRunLoopMode]", start),
    ]

    assert -1 not in selectors
    assert selectors == sorted(selectors)


def test_window_resize_updates_status_before_scheduling_delayed_reflow():
    source = TERMINAL_SOURCE_PATH.read_text(encoding="utf-8")
    method = method_body(source, "- (NSSize)windowWillResize:")
    compact = re.sub(r"\s+", " ", method)

    assert (
        "defaults->var15 = oldTitleBits; [self displayWindowStatus:self]; "
        "[self performSelector:@selector(windowHook::) withObject:self "
        "afterDelay:0.5];"
    ) in compact


def test_file_name_allocation_failure_uses_recovered_assertion_context():
    source = TERMINAL_SOURCE_PATH.read_text(encoding="utf-8")
    method = method_body(source, "- (void)setFileName:")
    compact = re.sub(r"\s+", " ", method)

    assert (
        "[[NSAssertionHandler currentHandler] handleFailureInMethod:_cmd "
        "object:self file:[NSString stringWithCString:\"Terminal.m\"] "
        "lineNumber:133 description:@\"Couldn't malloc space for file name.\"];"
    ) in compact


def test_base_emulation_c0_dispatch_leaves_unhandled_controls_as_no_ops():
    source = SOURCE_PATH.with_name("Emulation.m").read_text(encoding="utf-8")
    method = method_body(source, "- (void)ctrloutput:")
    cases = [int(value) for value in re.findall(r"case\s+(\d+)\s*:", method)]

    assert cases == [7, 8, 9, 10, 13]
    assert "default: break;" in re.sub(r"\s+", " ", method)


def test_emulation_function_key_return_uses_ppc_flag_bit_30():
    source = SOURCE_PATH.with_name("Emulation.m").read_text(encoding="utf-8")
    method = method_body(source, "- (int)key:")
    compact = re.sub(r"\s+", " ", method)

    assert "return (eflags & 0x40000000u) != 0 ? 2 : 0;" in compact


def test_emulation_output_starts_with_ppc_length_loop_without_extra_pointer_guard():
    source = SOURCE_PATH.with_name("Emulation.m").read_text(encoding="utf-8")
    method = method_body(source, "- (void)output:(char *)bytes len:")
    compact = re.sub(r"\s+", " ", method)

    assert "remaining = length; while (remaining != 0)" in compact
    assert "if (term == nil || bytes == 0) return;" not in compact


def test_vt52_cursor_address_prefix_preserves_escape_state_until_column():
    source = SOURCE_PATH.with_name("vt52.m").read_text(encoding="utf-8")
    method = method_body(source, "- (id)vt52Escape:")
    compact = re.sub(r"\s+", " ", method)
    y_case = method.split("case 0x59:", 1)[1].split("case 0x5A:", 1)[0]

    assert "writer = @selector(vt52getline:); return self;" in re.sub(r"\s+", " ", y_case)
    assert "if (value != 0x59) { eflags &= ~0x01000000u; }" in compact


def test_vt52_device_attributes_escape_outputs_literal_before_state_clear():
    source = SOURCE_PATH.with_name("vt52.m").read_text(encoding="utf-8")
    method = method_body(source, "- (id)vt52Escape:")
    compact = re.sub(r"\s+", " ", method)
    assert "case 0x5A: [term output:\"\\033/Z\"]; break;" in compact
    assert compact.index("[term output:\"\\033/Z\"]") < compact.index(
        "eflags &= ~0x01000000u;"
    )


def test_preferences_loads_bundle_nib_with_owner_table_and_view_zone():
    source = SOURCE_PATH.with_name("Preferences.m").read_text(encoding="utf-8")
    method = method_body(source, "- (id)init")
    compact = re.sub(r"\s+", " ", method)

    expected = (
        "bundle = [NSBundle bundleForClass:[self class]]; "
        "nibPath = [bundle pathForResource:@\"Preferences\" ofType:@\"nib\"]; "
        "ownerTable = [NSDictionary dictionaryWithObjectsAndKeys:self, "
        "@\"NSOwner\", nil]; [NSBundle loadNibFile:nibPath "
        "externalNameTable:ownerTable withZone:[self zone]];"
    )
    assert expected in compact
    assert "[self setCurrentTerminal:nil]" in compact
    assert "[self setUpButtons:0]" not in compact


def test_main_conditionally_loads_window_top_resource_before_event_loop():
    source = SOURCE_PATH.with_name("TerminalMain.m").read_text(encoding="utf-8")
    main = source.split("int main(", 1)[1]
    compact = re.sub(r"\s+", " ", main)

    assert 'pathForResource:@"WindowTop" ofType:@"tiff"' in compact
    assert "if (nibPath != nil)" in compact
    assert "[NSBundle loadNibFile:nibPath externalNameTable:ownerTable withZone:[application zone]];" in compact
    assert "[application finishLaunching]" not in compact


def test_terminal_do_overrides_preserve_distributed_object_parameter_qualifiers():
    source = SOURCE_PATH.with_name("TerminalDO.m").read_text(encoding="utf-8")
    typed_window_method = source.split(
        "- (void)runCommand:(NSString *)command windowType:", 1
    )[1].split("\n}", 1)[0]
    data_method = source.split(
        "- (void)runCommand:(NSString *)command inputData:(NSData *)inputData", 1
    )[1].split("\n}", 1)[0]

    assert "windowHandle:(inout int *)windowHandle" in typed_window_method
    assert "returnCode:(out int *)returnCode" in typed_window_method
    assert "returnCode:(out int *)returnCode" in data_method


def test_defaults_loader_preserves_ppc_allocation_and_assignment_flow():
    source = DEFAULTS_SOURCE_PATH.read_text(encoding="utf-8")
    method = source.split(
        "TerminalEmulationDefaults *defaultsFromDB(NSZone *zone)", 1
    )[1].split("\nvoid writeDefaultsToTypedStream", 1)[0]
    compact = re.sub(r"\s+", " ", method)

    assert "defaults = NSZoneMalloc(zone, sizeof(*defaults)); if (defaults == NULL) return NULL;" in compact
    assert "memset(defaults" not in method
    assert "NSAutoreleasePool" not in method
    assert "defaults->var10 = NSZoneMalloc(zone, shellLength + 1); strcpy(defaults->var10, shell);" in compact


def test_outputdata_uses_ppc_first_responder_then_cursor_clear_sequence():
    source = TERMINAL_SOURCE_PATH.read_text(encoding="utf-8")
    method = method_body(source, "- (id)outputdata:(const char *)bytes len:")
    pre_output = method.split("[emulator output:bytes len:length];", 1)[0]
    compact = re.sub(r"\s+", " ", pre_output)

    assert "[self lockFocus]; [self _clearcursor];" in compact
    assert "[self _clearSelection]" not in pre_output


def test_outputdata_flushes_its_window_after_cursor_update():
    source = TERMINAL_SOURCE_PATH.read_text(encoding="utf-8")
    method = method_body(source, "- (id)outputdata:(const char *)bytes len:")
    after_cursor = method.split(
        "TERMINAL_FIELD_SET_FLAGS(self, TERMINAL_FIELD_FLAGS(self) & ~0x00010000u);",
        1,
    )[1].split("if (isMiniaturized)", 1)[0]
    compact = re.sub(r"\s+", " ", after_cursor)

    assert "[[self window] flushWindow];" in compact
    assert "[self refreshscreen]" not in compact


def test_outputdata_timer_passes_terminal_as_user_info():
    source = TERMINAL_SOURCE_PATH.read_text(encoding="utf-8")
    method = method_body(source, "- (id)outputdata:(const char *)bytes len:")
    compact = re.sub(r"\s+", " ", method)

    assert (
        "selector:@selector(handleDirtTimer:) userInfo:self repeats:NO]"
        in compact
    )


def test_outputdata_retains_timer_and_unlocks_focus_after_pruning():
    source = TERMINAL_SOURCE_PATH.read_text(encoding="utf-8")
    method = method_body(source, "- (id)outputdata:(const char *)bytes len:")
    compact = re.sub(r"\s+", " ", method)

    assert (
        "longTermTimer = [[NSTimer scheduledTimerWithTimeInterval:0.1 "
        "target:self selector:@selector(handleDirtTimer:) userInfo:self "
        "repeats:NO] retain];"
    ) in compact
    assert "[self pruneNumLinesTo:(unsigned int)saveLines]; [self unlockFocus];" in compact


def test_outputdata_updates_application_status_only_when_hidden():
    source = TERMINAL_SOURCE_PATH.read_text(encoding="utf-8")
    method = method_body(source, "- (id)outputdata:(const char *)bytes len:")
    compact = re.sub(r"\s+", " ", method)

    assert "if ([NSApp isHidden]) [NSApp updateAppStatus];" in compact
    assert "[NSApp delegate]" not in method
    assert "displayWindowStatus" not in method


def test_outputdata_cancels_old_cursor_perform_before_rescheduling():
    source = TERMINAL_SOURCE_PATH.read_text(encoding="utf-8")
    method = method_body(source, "- (id)outputdata:(const char *)bytes len:")
    compact = re.sub(r"\s+", " ", method)
    cancel = compact.index(
        "[NSRunLoop cancelPreviousPerformRequestsWithTarget:self "
        "selector:@selector(_delayedCursor:) object:self];"
    )
    schedule = compact.index(
        "[self performSelector:@selector(_delayedCursor:) withObject:self "
        "afterDelay:0.1];"
    )
    update_status = compact.index("[self updateWindowStatus];")

    assert cancel < schedule < update_status


def test_select_all_uses_the_ppc_focus_pair_and_flush_tail():
    source = SOURCE_PATH.read_text(encoding="utf-8")
    method = method_body(source, "- (void)selectAll:(id)sender")
    selectors = re.findall(
        r"\[(?:self|window)\s+([A-Za-z_]\w*(?::)?)", method
    )

    assert selectors == [
        "lockFocus",
        "_clearSelection",
        "_highlightsel:",
        "unlockFocus",
        "window",
        "flushWindow",
    ]


def test_clear_scrollback_matches_ppc_selector_sequence():
    source = SOURCE_PATH.read_text(encoding="utf-8")
    method = source.split("- (void)clearScrollback:(id)sender", 1)[1].split(
        "\n@end", 1
    )[0]

    selectors = re.findall(
        r"\[(?:self|window|contentView)\s+([A-Za-z_]\w*(?::)?)", method
    )

    assert selectors == [
        "lockFocus",
        "_clearSelection",
        "window",
        "disableFlushWindow",
        "scrollTo:",
        "window",
        "contentView",
        "setNeedsDisplay:",
        "window",
        "enableFlushWindow",
        "display",
        "reflectPosition",
        "unlockFocus",
    ]


def test_scroll_to_uses_focus_lock_around_ppc_viewport_update():
    source = SOURCE_PATH.read_text(encoding="utf-8")
    method = method_body(source, "- (void)scrollTo:(unsigned int)line")
    selectors = re.findall(r"\[self\s+([A-Za-z_]\w*(?::)?)", method)

    assert selectors == ["lockFocus", "_scrollTo:", "unlockFocus", "reflectPosition"]


def test_field_view_delegate_setter_autoreleases_old_value_like_ppc():
    source = SOURCE_PATH.read_text(encoding="utf-8")
    method = method_body(source, "- (void)setDelegate:(id)value")
    compact = re.sub(r"\s+", " ", method)

    assert "if (delegate != nil) [delegate autorelease]; delegate = value; [delegate retain];" in compact


def test_window_did_become_main_uses_ppc_font_panel_selectors():
    source = SOURCE_PATH.read_text(encoding="utf-8")
    method = method_body(source, "- (void)windowDidBecomeMain:(id)sender")
    compact = re.sub(r"\s+", " ", method)

    assert "[[NSFontPanel new] setSelectedFont:font isMultiple:NO];" in compact


def test_mutable_event_set_chars_retains_new_string_like_ppc():
    source = SOURCE_PATH.with_name("MutableEvent.m").read_text(encoding="utf-8")
    method = method_body(source, "- (void)setChars:(NSString *)characters")
    compact = re.sub(r"\s+", " ", method)

    assert "[_data.key.keys release]; _data.key.keys = [characters retain];" in compact
    assert "((unsigned char *)&_reservedEvent1)[0] = 0;" in compact


@pytest.mark.parametrize(
    "signature",
    [
        "- (void)_lscrolldown:(unsigned int)first to:(unsigned int)last",
        "- (void)_lscrollup:(unsigned int)first to:(unsigned int)last",
        "- (void)_lclear:(unsigned int)first to:(unsigned int)last",
    ],
)
def test_line_mutation_methods_refresh_before_changing_rows(signature):
    source = SOURCE_PATH.read_text(encoding="utf-8")
    method = method_body(source, signature)
    selectors = re.findall(r"\[self\s+([A-Za-z_]\w*(?::)?)", method)

    assert selectors[0] == "_refresh"


def test_logical_clear_uses_ppc_scrolled_and_screen_redraw_calls():
    source = SOURCE_PATH.read_text(encoding="utf-8")
    method = method_body(
        source, "- (void)_lclear:(unsigned int)first to:(unsigned int)last"
    )
    compact = re.sub(r"\s+", " ", method)

    assert "[self _srscrolldown:lineCount to:lineCount + last lines:count];" in compact
    assert "[self _sclear:lineCount + last to:lines->count];" in compact
    assert "[self _sclear:topline + first to:topline + last];" in compact


def test_logical_scroll_up_uses_ppc_redraw_dispatch():
    source = SOURCE_PATH.read_text(encoding="utf-8")
    method = method_body(
        source,
        "- (void)_lscrollup:(unsigned int)first to:(unsigned int)last",
    )
    compact = re.sub(r"\s+", " ", method)

    assert (
        "[self _sscrollup:lineCount - count to:lineCount + first lines:count];"
        in compact
    )
    assert (
        "[self _srscrolldown:lineCount + last - count to:lines->count lines:count];"
        in compact
    )
    assert (
        "[self _srscrolldown:topline + first to:topline + last lines:count];"
        in compact
    )


def test_refresh_uses_full_buffer_count_for_second_scrollback_redraw():
    source = SOURCE_PATH.read_text(encoding="utf-8")
    method = method_body(source, "- (void)_refresh")
    compact = re.sub(r"\s+", " ", method)

    assert "[self _srscrolldown:lineCount - top to:lineCount + bot lines:top];" in compact
    assert (
        "[self _srscrolldown:lineCount + (unsigned char)drawCursOK - top "
        "to:lines->count lines:top];"
    ) in compact
    assert (
        "[self _srscrollup:topline + bot to:topline + (unsigned char)drawCursOK "
        "lines:top];"
    ) in compact


def test_refresh_uses_ppc_position_and_window_flush_sequence():
    source = SOURCE_PATH.read_text(encoding="utf-8")
    method = method_body(source, "- (void)_refresh")
    compact = re.sub(r"\s+", " ", method)

    assert "[self reflectPosition]; window = [self window]; [window flushWindow];" in compact


def test_prune_scrollback_uses_ppc_redraw_and_flush_sequence():
    source = SOURCE_PATH.with_name("Terminal.m").read_text(encoding="utf-8")
    method = method_body(source, "- (void)pruneNumLinesTo:")
    compact = re.sub(r"\s+", " ", method)

    assert (
        "[contentView setNeedsDisplay:YES]; [self display]; "
        "[self reflectPosition]; terminalWindow = [self window]; "
        "[terminalWindow enableFlushWindow];"
    ) in compact
    selectors = re.findall(
        r"\[(?:self|terminalWindow|contentView)\s+([A-Za-z_]\w*(?::)?)",
        method,
    )
    assert selectors == [
        "window",
        "disableFlushWindow",
        "_clearSelection",
        "contentView",
        "setNeedsDisplay:",
        "display",
        "reflectPosition",
        "window",
        "enableFlushWindow",
    ]
