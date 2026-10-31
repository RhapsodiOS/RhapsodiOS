from pathlib import Path

from selector_check import source_methods


def test_graphics_context_implements_reference_selectors():
    appkit = Path(__file__).resolve().parents[3] / "src" / "Kits" / "AppKit"
    methods = {entry[0] for entry in source_methods(appkit)}
    selectors = {
        "+[NSGraphicsContext currentContext]",
        "+[NSGraphicsContext setCurrentContext:]",
        "-[NSGraphicsContext isDrawingToScreen]",
        "-[NSGraphicsContext saveGraphicsState]",
        "-[NSGraphicsContext restoreGraphicsState]",
        "-[NSGraphicsContext flush]",
        "-[NSGraphicsContext wait]",
        "-[NSGraphicsContext flushGraphics]",
    }
    assert selectors <= methods

    source = (appkit / "NSGraphicsContext.m").read_text()
    assert "[NSDPSContext currentContext]" in source
    assert "[NSDPSContext setCurrentContext:context]" in source
    assert source.count("requestConcreteImplementation(self)") == 6
    assert "[self flush];" in source
    assert "[self flushGraphics];" in source
