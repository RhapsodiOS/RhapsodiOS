"""Report exported functions that no module's symbol assignment claims.

Objective-C definitions carry their owning module in ``__OBJC,__module_info``.
Plain C functions do not, so they are attributed by hand in ``symbols.json``.
Nothing checked that the hand-written assignment was complete, and two stages
have now each discovered exported functions it silently omitted.
"""


def unclaimed_text_symbols(document, assignment):
    """Return sorted names of exported functions no module claims.

    Objective-C method symbols are excluded: ``__module_info`` attributes them,
    so they are not the assignment's responsibility.
    """
    claimed = {name for names in assignment.values() for name in names}
    return sorted(
        symbol["name"] for symbol in document["symbols"]
        if symbol["binding"] == "external"
        and symbol["section"] == "__TEXT,__text"
        and not symbol["name"].startswith(("-[", "+["))
        and symbol["name"] not in claimed
    )
