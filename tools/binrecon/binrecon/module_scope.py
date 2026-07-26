"""Generate an ``analysis_scope`` for a set of Objective-C modules.

Apple shipped Foundation with profile-guided function ordering, so a module's
code is scattered across ``__text`` — 1,273 disjoint runs across the framework
(spec §2.1). ``analysis_scope`` already accepts a list of disjoint ranges; what
is needed is a generator, because hand-listing them is unmaintainable.
"""


def function_ranges(symbols, text_section, names):
    """Return sorted ``{start, end}`` ranges, one per named function.

    Each range spans the function's body: from its entry point to the next
    defined text symbol, or to the end of ``__text`` for the last one.
    """
    text_start = text_section["address"]
    text_end = text_start + text_section["size"]
    in_text = sorted(
        (symbol["address"], symbol["name"])
        for symbol in symbols
        if symbol["section"] == text_section["name"]
        and text_start <= symbol["address"] < text_end
    )
    boundaries = [value for value, _ in in_text] + [text_end]
    extent = {
        name: (value, boundaries[index + 1])
        for index, (value, name) in enumerate(in_text)
    }

    known = {symbol["name"] for symbol in symbols}
    ranges = []
    for name in names:
        if name not in extent:
            reason = "is not a function in __text" if name in known else "is not exported"
            raise ValueError(f"{name} {reason}")
        start, end = extent[name]
        ranges.append({"start": start, "end": end})
    return sorted(ranges, key=lambda item: item["start"])
