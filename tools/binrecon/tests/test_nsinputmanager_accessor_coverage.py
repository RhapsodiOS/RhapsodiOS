from pathlib import Path

from selector_check import source_methods


def test_input_manager_class_accessor_returns_current_manager_global():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    assert "+[NSInputManager currentInputManager]" in methods

    source = (appkit / "NSInputManager.m").read_text()
    assert "static NSInputManager *_NSCurrentInputManager;" in source
    body = source.rsplit("+ (NSInputManager *)currentInputManager", 1)[1].split("\n}", 1)[0]
    assert "return _NSCurrentInputManager;" in body


def test_input_manager_active_array_accessor_returns_reference_global():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    assert "+[NSInputManager activeInputManagerArray]" in methods

    source = (appkit / "NSInputManager.m").read_text()
    assert "static NSArray *_NSActiveInputManagers;" in source
    body = source.rsplit("+ (NSArray *)activeInputManagerArray", 1)[1].split("\n}", 1)[0]
    assert "return _NSActiveInputManagers;" in body


def test_input_manager_index_accessors_use_reference_globals_and_array_lookup():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    selectors = (
        "+[NSInputManager indexOfCurrentInputManager]",
        "+[NSInputManager currentInputManagerIndex]",
    )
    assert set(selectors) <= methods

    source = (appkit / "NSInputManager.m").read_text()
    assert "static unsigned int _NSActiveInputIndex;" in source
    index = source.rsplit("+ (unsigned int)indexOfCurrentInputManager", 1)[1].split("\n}", 1)[0]
    assert "return _NSActiveInputIndex;" in index
    current = source.rsplit("+ (unsigned int)currentInputManagerIndex", 1)[1].split("\n}", 1)[0]
    assert "[_NSActiveInputManagers indexOfObject:_NSCurrentInputManager]" in current


def test_input_manager_selection_index_routes_current_and_menu_entries():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    assert "+[NSInputManager setCurrentInputManagerAtIndex:]" in methods

    source = (appkit / "NSInputManager.m").read_text()
    body = source.rsplit("+ (void)setCurrentInputManagerAtIndex:(unsigned int)index", 1)[1].split("\n}", 1)[0]
    assert "index > 0x3E7" in body
    assert "objectAtIndex:index - 1000" in body
    assert "setEnabled:YES" in body
    assert "objectAtIndex:index" in body
    assert "setCurrentInputManager:manager" in body


def test_input_manager_accessors_return_reference_fields_and_flag_bits():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    selectors = (
        "-[NSInputManager image]",
        "-[NSInputManager language]",
        "-[NSInputManager localizedInputManagerName]",
        "-[NSInputManager server]",
        "-[NSInputManager wantsToInterpretAllKeystrokes]",
        "-[NSInputManager wantsToHandleMouseEvents]",
        "-[NSInputManager wantsToDelayTextChangeNotifications]",
    )
    assert set(selectors) <= methods

    source = (appkit / "NSInputManager.m").read_text()
    for signature, expression in (
        ("- (NSImage *)image", "_image"),
        ("- (NSString *)language", "_language"),
        ("- (NSString *)localizedInputManagerName", "_visibleName"),
        ("- (NSInputServer *)server", "(NSInputServer *)_server"),
    ):
        body = source.rsplit(signature, 1)[1].split("\n}", 1)[0]
        assert f"return {expression};" in body

    for selector, bit in (
        ("wantsToInterpretAllKeystrokes", "0x10"),
        ("wantsToHandleMouseEvents", "0x8000"),
        ("wantsToDelayTextChangeNotifications", "0x10000"),
    ):
        body = source.rsplit(f"- (BOOL){selector}", 1)[1].split("\n}", 1)[0]
        assert bit in body


def test_input_manager_client_accessors_forward_reference_state():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    selectors = (
        "-[NSInputManager _currentClient]",
        "-[NSInputManager _trueName]",
        "-[NSInputManager bundleObject]",
        "-[NSInputManager conversationIdentifier]",
        "-[NSInputManager hasMarkedText]",
        "-[NSInputManager isEnabled]",
        "-[NSInputManager markedRange]",
        "-[NSInputManager selectedRange]",
        "-[NSInputManager validAttributesForMarkedText]",
    )
    assert set(selectors) <= methods

    source = (appkit / "NSInputManager.m").read_text()
    for signature, expression in (
        ("- (id)_currentClient", "_currentClient"),
        ("- (id)_trueName", "_trueName"),
        ("- (id)bundleObject", "_bundleObj"),
        ("- (long)conversationIdentifier", "[_currentClient conversationIdentifier]"),
        ("- (BOOL)hasMarkedText", "[_currentClient hasMarkedText]"),
        ("- (NSRange)markedRange", "[_currentClient markedRange]"),
        ("- (NSRange)selectedRange", "[_currentClient selectedRange]"),
        ("- (NSArray *)validAttributesForMarkedText", "[_currentClient validAttributesForMarkedText]"),
    ):
        body = source.rsplit(signature, 1)[1].split("\n}", 1)[0]
        assert f"return {expression};" in body

    enabled = source.rsplit("- (BOOL)isEnabled", 1)[1].split("\n}", 1)[0]
    assert "return (_flags & 1) != 0;" in enabled


def test_input_manager_text_input_methods_forward_to_current_client():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    selectors = (
        "-[NSInputManager characterIndexForPoint:]",
        "-[NSInputManager doCommandBySelector:]",
        "-[NSInputManager firstRectForCharacterRange:]",
        "-[NSInputManager unmarkText]",
    )
    assert set(selectors) <= methods

    source = (appkit / "NSInputManager.m").read_text()
    for signature, expression in (
        ("- (unsigned int)characterIndexForPoint:(NSPoint)thePoint", "[_currentClient characterIndexForPoint:thePoint]"),
        ("- (void)doCommandBySelector:(SEL)aSelector", "[_currentClient doCommandBySelector:aSelector]"),
        ("- (NSRect)firstRectForCharacterRange:(NSRange)theRange", "[_currentClient firstRectForCharacterRange:theRange]"),
        ("- (void)unmarkText", "[_currentClient unmarkText]"),
    ):
        body = source.rsplit(signature, 1)[1].split("\n}", 1)[0]
        assert expression in body


def test_input_manager_archives_and_unarchives_text_input_payloads():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    selectors = (
        "-[NSInputManager attributedSubstringFromRange:]",
        "-[NSInputManager insertText:]",
        "-[NSInputManager setMarkedText:selectedRange:]",
    )
    assert set(selectors) <= methods

    source = (appkit / "NSInputManager.m").read_text()
    attributed = source.rsplit("- (NSAttributedString *)attributedSubstringFromRange:", 1)[1].split("\n}", 1)[0]
    assert "[_currentClient attributedSubstringFromRange:theRange]" in attributed
    assert "(_flags & 0x200) == 0" in attributed
    assert "[NSArchiver archivedDataWithRootObject:substring]" in attributed

    insert = source.rsplit("- (void)insertText:(id)string\n{", 1)[1].split("\n}", 1)[0]
    assert "[string isKindOfClass:[NSData class]]" in insert
    assert "[NSUnarchiver unarchiveObjectWithData:string]" in insert
    assert "[_currentClient insertText:string]" in insert

    marked = source.rsplit("- (void)setMarkedText:(id)string selectedRange:(NSRange)selection", 1)[1].split("\n}", 1)[0]
    assert "[string isKindOfClass:[NSData class]]" in marked
    assert "[NSUnarchiver unarchiveObjectWithData:string]" in marked
    assert "[_currentClient setMarkedText:string selectedRange:selection]" in marked


def test_input_manager_get_marked_text_forwards_both_out_parameters():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    assert "-[NSInputManager getMarkedText:selectedRange:]" in methods

    source = (appkit / "NSInputManager.m").read_text()
    body = source.rsplit("- (void)getMarkedText:(id *)text selectedRange:(NSRange *)range", 1)[1].split("\n}", 1)[0]
    assert "[_currentClient getMarkedText:text selectedRange:range]" in body


def test_input_manager_routes_inserted_text_to_server_for_active_interpreter():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    assert "-[NSInputManager insertText:client:]" in methods

    source = (appkit / "NSInputManager.m").read_text()
    body = source.rsplit("- (void)insertText:(id)string client:(id)client", 1)[1].split("\n}", 1)[0]
    assert "client == _currentClient" in body
    assert "(_flags & 0x2000) != 0" in body
    assert "_server != nil" in body
    assert "(_flags & 1) != 0" in body
    assert "[_server insertText:string client:self]" in body
    assert "[client insertText:string]" in body


def test_input_manager_termination_releases_server_and_owned_state():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    assert "-[NSInputManager _terminate]" in methods
    assert "-[NSInputManager dealloc]" in methods

    source = (appkit / "NSInputManager.m").read_text()
    terminate = source.rsplit("- (void)_terminate", 1)[1].split("\n}", 1)[0]
    assert "_flags |= 2U" in terminate
    assert "[_server terminate:self]" in terminate
    assert "[_server release]" in terminate
    assert "_server = nil;" in terminate

    dealloc = source.rsplit("- (void)dealloc", 1)[1].split("\n}", 1)[0]
    assert "[self _terminate];" in dealloc
    for ivar in (
        "_bundleObj", "_trueName", "_connectionName", "_hostName", "_procToExec",
        "_visibleName", "_bundleName", "_keybindings", "_keyBindingsName", "_language", "_image",
    ):
        assert f"[{ivar} release];" in dealloc
    assert "[super dealloc];" in dealloc


def test_input_manager_enabled_state_tracks_current_visible_text_client():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    assert "-[NSInputManager setEnabled:]" in methods

    source = (appkit / "NSInputManager.m").read_text()
    body = source.rsplit("- (void)setEnabled:(BOOL)flag", 1)[1].split("\n}", 1)[0]
    assert "[[NSApp keyWindow] firstResponder]" in body
    assert "_flags |= 0x100000U" in body
    assert "@selector(conversationIdentifier)" in body
    assert "@selector(_acceptsMarkedText)" in body
    assert "_flags |= 0x2000U" in body
    assert "_currentClient = client;" in body
    assert "_flags &= ~0x2000U" in body
    assert "(_flags & 0x22000U) == 0x22000U" in body
    assert "@selector(window)" in body
    assert "[[_currentClient window] isVisible]" in body
    assert "_flags |= 1U" in body
    assert "_flags &= ~1U" in body


def test_input_manager_first_responder_updates_client_and_enabled_state():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    assert "-[NSInputManager inputClientBecomeFirstResponder:]" in methods

    source = (appkit / "NSInputManager.m").read_text()
    body = source.rsplit("- (void)inputClientBecomeFirstResponder:(id)client", 1)[1].split("\n}", 1)[0]
    assert "(_flags & 0x20000U) != 0" in body
    assert "client != _currentClient" in body
    assert "_flags |= 0x100000U" in body
    assert "@selector(conversationIdentifier)" in body
    assert "@selector(_acceptsMarkedText)" in body
    assert "_flags |= 0x2000U" in body
    assert "_currentClient = client;" in body
    assert "_flags &= ~0x2000U" in body
    assert "[self setEnabled:(_flags & 0x2000U) != 0];" in body


def test_input_manager_first_responder_resignation_reports_marked_text_and_conversation():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    assert "-[NSInputManager inputClientResignFirstResponder:]" in methods

    source = (appkit / "NSInputManager.m").read_text()
    body = source.rsplit("- (void)inputClientResignFirstResponder:(id)client", 1)[1].split("\n}", 1)[0]
    assert "(_flags & 1U) != 0" in body
    assert "@selector(hasMarkedText)" in body
    assert "[client hasMarkedText]" in body
    assert "[client unmarkText]" in body
    assert "[_server markedTextAbandoned:self]" in body
    assert "client == _currentClient" in body
    assert "[_currentClient conversationIdentifier]" in body
    assert "[_server activeConversationWillChange:self fromOldConversation:conversation]" in body
    assert "[self setEnabled:NO]" in body


def test_input_manager_key_window_resignation_reports_active_conversation():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    assert "-[NSInputManager inputClientResignKeyWindow:]" in methods

    source = (appkit / "NSInputManager.m").read_text()
    body = source.rsplit("- (void)inputClientResignKeyWindow:(id)client", 1)[1].split("\n}", 1)[0]
    assert "(_flags & 1U) != 0" in body
    assert "@selector(hasMarkedText)" in body
    assert "[client hasMarkedText]" in body
    assert "client == _currentClient" in body
    assert "[_currentClient conversationIdentifier]" in body
    assert "[_server activeConversationWillChange:self fromOldConversation:conversation]" in body
    assert "[self setEnabled:NO]" in body


def test_input_manager_marked_text_notifications_set_pending_flags():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    selectors = (
        "-[NSInputManager markedTextAbandoned:]",
        "-[NSInputManager markedTextSelectionChanged:client:]",
        "-[NSInputManager worksWhenModal]",
        "+[NSInputManager worksWhenModal]",
    )
    assert set(selectors) <= methods

    source = (appkit / "NSInputManager.m").read_text()
    abandoned = source.rsplit("- (void)markedTextAbandoned:(id)cli", 1)[1].split("\n}", 1)[0]
    assert "_flags |= 0x40000U;" in abandoned
    changed = source.rsplit("- (void)markedTextSelectionChanged:(NSRange)newSel client:(id)cli", 1)[1].split("\n}", 1)[0]
    assert "_flags |= 0x80000U;" in changed
    assert "+ (BOOL)worksWhenModal" in source
    assert "return YES;" in source.rsplit("+ (BOOL)worksWhenModal", 1)[1].split("\n}", 1)[0]
    assert "- (BOOL)worksWhenModal" in source
    assert "return YES;" in source.rsplit("- (BOOL)worksWhenModal", 1)[1].split("\n}", 1)[0]
