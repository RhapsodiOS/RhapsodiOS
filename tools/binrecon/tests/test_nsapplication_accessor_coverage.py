from pathlib import Path

from selector_check import source_methods


def _application_methods():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0]: entry for entry in source_methods(appkit)}
    return appkit, methods


def test_application_state_getters_return_reference_flag_bits():
    appkit, methods = _application_methods()
    for selector in (
        "-[NSApplication isActive]",
        "-[NSApplication isHidden]",
        "-[NSApplication _isDoingHide]",
        "-[NSApplication _isDoingUnhide]",
        "-[NSApplication _isDeactPending]",
    ):
        assert selector in methods

    source = (appkit / "NSApplication.m").read_text()
    for selector, field in (
        ("isActive", "_appFlags._active"),
        ("isHidden", "_appFlags._hidden"),
        ("_isDoingHide", "_appFlags._doingHide"),
        ("_isDoingUnhide", "_appFlags._doingUnhide"),
        ("_isDeactPending", "_appFlags._deactPending"),
    ):
        body = source.rsplit(f"- (BOOL){selector}", 1)[1].split("\n}", 1)[0]
        assert f"return {field}" in body


def test_application_window_accessors_match_reference_visibility_guard():
    appkit, methods = _application_methods()
    for selector in (
        "-[NSApplication keyWindow]",
        "-[NSApplication mainWindow]",
        "-[NSApplication _keyWindow]",
        "-[NSApplication _mainWindow]",
        "-[NSApplication _appIcon]",
        "-[NSApplication _appListener]",
        "-[NSApplication context]",
    ):
        assert selector in methods

    source = (appkit / "NSApplication.m").read_text()
    for selector, field in (("keyWindow", "_keyWindow"), ("mainWindow", "_mainWindow")):
        body = source.rsplit(f"- (NSWindow *){selector}", 1)[1].split("\n}", 1)[0]
        assert "_appFlags._active" in body
        assert "_appFlags._invalidState" in body
        assert f"return {field}" in body
        assert "return nil" in body

    for selector, signature, field in (
        ("_keyWindow", "id", "_keyWindow"),
        ("_mainWindow", "id", "_mainWindow"),
        ("_appIcon", "id", "_appIcon"),
        ("_appListener", "id", "_appListener"),
        ("context", "NSDPSContext *", "_context"),
    ):
        body = source.rsplit(f"- ({signature}){selector}", 1)[1].split("\n}", 1)[0]
        assert f"return {field}" in body


def test_application_event_and_menu_accessors_return_reference_fields():
    appkit, methods = _application_methods()
    for selector in (
        "-[NSApplication currentEvent]",
        "-[NSApplication mainMenu]",
        "-[NSApplication _eventDelegate]",
    ):
        assert selector in methods

    source = (appkit / "NSApplication.m").read_text()
    for signature, field in (
        ("- (NSEvent *)currentEvent", "_currentEvent"),
        ("- (NSMenu *)mainMenu", "(NSMenu *)_mainMenu"),
        ("- (id)_eventDelegate", "_eventDelegate"),
    ):
        body = source.rsplit(signature, 1)[1].split("\n}", 1)[0]
        assert f"return {field};" in body


def test_application_menu_alias_and_private_menu_assignment_match_reference():
    appkit, methods = _application_methods()
    for selector in (
        "-[NSApplication menu]",
        "-[NSApplication setMenu:]",
        "-[NSApplication _setMainMenu:]",
    ):
        assert selector in methods

    source = (appkit / "NSApplication.m").read_text()
    menu = source.rsplit("- (id)menu", 1)[1].split("\n}", 1)[0]
    assert "return [self mainMenu];" in menu
    set_menu = source.rsplit("- (void)setMenu:(id)menu", 1)[1].split("\n}", 1)[0]
    assert "[self setMainMenu:menu];" in set_menu
    private_set = source.rsplit("- (void)_setMainMenu:(id)menu", 1)[1].split("\n}", 1)[0]
    assert "_mainMenu = menu;" in private_set


def test_application_front_window_uses_main_context_and_window_cache():
    appkit, methods = _application_methods()
    assert "-[NSApplication _mainContextID]" in methods
    assert "-[NSApplication frontWindow]" in methods

    source = (appkit / "NSApplication.m").read_text()
    context = source.rsplit("- (int)_mainContextID", 1)[1].split("\n}", 1)[0]
    assert "*((int *)_threadingSupport)" in context
    front = source.rsplit("- (NSWindow *)frontWindow", 1)[1].split("\n}", 1)[0]
    assert "NSWindowListForContext([self _mainContextID], 1, &windowNumber);" in front
    assert "[self windowWithWindowNumber:windowNumber]" in front


def test_application_modal_state_matches_reference_run_count_and_session():
    appkit, methods = _application_methods()
    assert "-[NSApplication _isRunningModal]" in methods
    assert "-[NSApplication modalWindow]" in methods

    source = (appkit / "NSApplication.m").read_text()
    running = source.rsplit("- (BOOL)_isRunningModal", 1)[1].split("\n}", 1)[0]
    assert "*((unsigned int *)&_appFlags) & 0x10000000U" in running
    assert "return _running > 1;" in running
    assert "return _running > 0;" in running

    modal = source.rsplit("- (NSWindow *)modalWindow", 1)[1].split("\n}", 1)[0]
    assert "if ([self _isRunningModal])" in modal
    assert "if (_NXLastModalSession != NULL)" in modal
    assert "return _NXLastModalSession->window;" in modal


def test_application_activation_accessors_match_reference_flag_bits():
    appkit, methods = _application_methods()
    selectors = (
        "-[NSApplication _mouseActivationInProgress]",
        "-[NSApplication _setMouseActivationInProgress:]",
        "-[NSApplication _setKeyWindow:]",
        "-[NSApplication _setMainWindow:]",
    )
    assert set(selectors) <= methods.keys()

    source = (appkit / "NSApplication.m").read_text()
    mouse = source.rsplit("- (BOOL)_mouseActivationInProgress", 1)[1].split("\n}", 1)[0]
    assert "*((unsigned int *)&_appFlags) & 0x01000000U" in mouse
    set_mouse = source.rsplit("- (id)_setMouseActivationInProgress:(BOOL)flag", 1)[1].split("\n}", 1)[0]
    assert "(flag << 24) & 0x01000000U" in set_mouse
    assert "return self;" in set_mouse

    for selector, signature, field in (
        ("_setKeyWindow:", "- (id)_setKeyWindow:(id)window", "_keyWindow"),
        ("_setMainWindow:", "- (id)_setMainWindow:(id)window", "_mainWindow"),
    ):
        body = source.rsplit(signature, 1)[1].split("\n}", 1)[0]
        assert f"{field} = window;" in body
        assert "return self;" in body


def test_application_event_mutation_and_active_state_match_reference():
    appkit, methods = _application_methods()
    selectors = (
        "-[NSApplication _lastEventTime]",
        "-[NSApplication _setCurrentEvent:]",
        "-[NSApplication setIsActive:]",
    )
    assert set(selectors) <= methods.keys()

    source = (appkit / "NSApplication.m").read_text()
    last_event = source.rsplit("- (int)_lastEventTime", 1)[1].split("\n}", 1)[0]
    assert "0x10800000U) == 0x10800000U" in last_event
    assert "[_currentEvent type] == 15" in last_event
    assert "return (int)[_currentEvent timestamp];" in last_event

    set_event = source.rsplit("- (void)_setCurrentEvent:(NSEvent *)event", 1)[1].split("\n}", 1)[0]
    assert "[event isEqual:_currentEvent]" in set_event
    assert "[_currentEvent release];" in set_event
    assert "_currentEvent = [event retain];" in set_event

    active = source.rsplit("- (void)setIsActive:(BOOL)flag", 1)[1].split("\n}", 1)[0]
    assert "0x20000000U" in active
    assert "0xDFFFFFFFU" in active


def test_application_activation_state_accessors_use_shared_counters():
    appkit, methods = _application_methods()
    selectors = (
        "-[NSApplication _currentActivation]",
        "-[NSApplication _pendingActCount]",
        "-[NSApplication _setCurrentActivation:]",
    )
    assert set(selectors) <= methods.keys()

    source = (appkit / "NSApplication.m").read_text()
    assert "static int _currentActivation;" in source
    assert "static int _deferredCurrentActivation;" in source
    current = source.rsplit("- (int)_currentActivation", 1)[1].split("\n}", 1)[0]
    assert "return _currentActivation;" in current
    pending = source.rsplit("- (int)_pendingActCount", 1)[1].split("\n}", 1)[0]
    assert "return _deferredCurrentActivation;" in pending
    setter = source.rsplit("- (id)_setCurrentActivation:(int)value", 1)[1].split("\n}", 1)[0]
    assert "_currentActivation = value;" in setter
    assert "return self;" in setter


def test_application_icon_image_defaults_and_draws_into_cached_image():
    appkit, methods = _application_methods()
    assert "-[NSApplication applicationIconImage]" in methods
    assert "-[NSApplication setApplicationIconImage:]" in methods

    source = (appkit / "NSApplication.m").read_text()
    assert "static NSImage *_iconImage;" in source
    getter = source.rsplit("- (NSImage *)applicationIconImage", 1)[1].split("\n}", 1)[0]
    assert "[NSImage imageNamed:@\"NSApplicationIcon\"]" in getter
    assert "[self setApplicationIconImage:" in getter
    assert "return _iconImage;" in getter

    setter = source.rsplit("- (void)setApplicationIconImage:(NSImage *)image", 1)[1].split("\n}", 1)[0]
    assert "[image size]" in setter
    assert "[[NSImage alloc] initWithSize:size]" in setter
    assert "[_iconImage setScalesWhenResized:YES];" in setter
    assert "[_iconImage lockFocus];" in setter
    assert "[NSColor clearColor]" in setter
    assert "NSRectFill(NSMakeRect(0.0, 0.0, size.width, size.height));" in setter
    assert "[image compositeToPoint:NSZeroPoint operation:NSCompositeSourceOver];" in setter
    assert "[_iconImage unlockFocus];" in setter


def test_application_event_delegate_setter_tracks_supported_callback():
    appkit, methods = _application_methods()
    assert "-[NSApplication _setEventDelegate:]" in methods

    source = (appkit / "NSApplication.m").read_text()
    setter = source.rsplit("- (void)_setEventDelegate:(id)delegate", 1)[1].split("\n}", 1)[0]
    assert "if (_eventDelegate != delegate)" in setter
    assert "_eventDelegate = delegate;" in setter
    assert "@selector(application:receivedEvent:dequeued:)" in setter
    assert "_appFlags._hasEventDelegate = delegate != nil" in setter
