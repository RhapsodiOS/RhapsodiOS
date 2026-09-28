"""Compare a rebuilt object's Objective-C ABI against committed evidence.

Instruction-level divergence between our build and Apple's is expected and
tolerated (spec §3.2). ABI divergence is not: client code is compiled against
these offsets, sizes and encodings.
"""

from .objc_abi import ObjcAbiError, method_symbol_index, read_modules_from_sections


def external_symbols(document):
    """Return the names of a built object's externally-visible definitions.

    Local symbols are static helpers, which are ours to choose. Symbols with no
    section are imports, which are not definitions.
    """
    return {
        symbol["name"] for symbol in document["symbols"]
        if symbol["binding"] == "external" and symbol["section"] is not None
    }


def module_from_object(payload, document, module):
    """Describe one compiled object as an ``abi-v1`` document.

    A translation unit that defines no classes or categories produces an object
    with no ``__OBJC,__module_info`` section; that is not an error, it is an
    empty Objective-C surface.
    """
    try:
        modules = read_modules_from_sections(
            payload, document["sections"], document["input"]["endianness"],
            method_symbol_index(document),
        )
    except ObjcAbiError:
        modules = {}

    if len(modules) > 1:
        raise ObjcAbiError(
            f"{module}: object defines more than one module: "
            + ", ".join(sorted(modules))
        )
    found = next(iter(modules.values()), None)
    if found is not None and found["module"] != module:
        raise ObjcAbiError(
            f"{module}: object declares module {found['module']}"
        )

    return {
        "schema_version": "abi-v1",
        "module": module,
        "classes": [] if found is None else found["classes"],
        "categories": [] if found is None else found["categories"],
        "text_symbols": sorted(external_symbols(document)),
        "data_symbols": [],
    }


def _method_map(methods, sign):
    return {f"{sign}{method['selector']}": method["types"] for method in methods}


def _diff_methods(findings, owner, expected, actual, sign):
    wanted = _method_map(expected, sign)
    found = _method_map(actual, sign)
    kind = "instance" if sign == "-" else "class"
    for selector in sorted(set(wanted) - set(found)):
        findings.append(f"{owner}: missing {kind} method {selector}")
    for selector in sorted(set(found) - set(wanted)):
        findings.append(f"{owner}: unexpected {kind} method {selector}")
    for selector in sorted(set(wanted) & set(found)):
        if wanted[selector] != found[selector]:
            findings.append(
                f"{owner}.{selector}: types expected {wanted[selector]}, "
                f"actual {found[selector]}"
            )


def _diff_class(findings, expected, actual):
    name = expected["name"]
    for field in ("superclass", "instance_size", "info"):
        if expected[field] != actual[field]:
            findings.append(
                f"{name}: {field} expected {expected[field]}, actual {actual[field]}"
            )

    wanted = {ivar["name"]: ivar for ivar in expected["ivars"]}
    found = {ivar["name"]: ivar for ivar in actual["ivars"]}
    for ivar in sorted(set(wanted) - set(found)):
        findings.append(f"{name}: missing ivar {ivar}")
    for ivar in sorted(set(found) - set(wanted)):
        findings.append(f"{name}: unexpected ivar {ivar}")
    for ivar in sorted(set(wanted) & set(found)):
        for field in ("offset", "type"):
            if wanted[ivar][field] != found[ivar][field]:
                findings.append(
                    f"{name}.{ivar}: {field} expected {wanted[ivar][field]}, "
                    f"actual {found[ivar][field]}"
                )

    _diff_methods(findings, name, expected["instance_methods"],
                  actual["instance_methods"], "-")
    _diff_methods(findings, name, expected["class_methods"],
                  actual["class_methods"], "+")


def _exported(document):
    return set(document["text_symbols"]) | set(document["data_symbols"])


def diff_abi(expected, actual):
    """Return one line per divergence; an empty list means the ABI matches."""
    findings = []
    module = expected["module"]

    for label, key in (("class", "classes"), ("category", "categories")):
        #  A category's __OBJC metadata identifies it by host class as well
        #  as name -- two legal same-named categories on different classes
        #  (the reference carries NSDetailedDescription on both Protocol and
        #  NSObject) are distinct entries, so the key must be the pair.
        if key == "categories":
            wanted = {(item["name"], item["class"]): item for item in expected[key]}
            found = {(item["name"], item["class"]): item for item in actual[key]}
        else:
            wanted = {item["name"]: item for item in expected[key]}
            found = {item["name"]: item for item in actual[key]}
        for name in sorted(set(wanted) - set(found)):
            if isinstance(name, tuple):
                findings.append(f"{module}: missing {label} {name[0]} on {name[1]}")
            else:
                findings.append(f"{module}: missing {label} {name}")
        for name in sorted(set(found) - set(wanted)):
            if isinstance(name, tuple):
                findings.append(f"{module}: unexpected {label} {name[0]} on {name[1]}")
            else:
                findings.append(f"{module}: unexpected {label} {name}")
        for name in sorted(set(wanted) & set(found)):
            if key == "classes":
                _diff_class(findings, wanted[name], found[name])
            else:
                owner = f"{found[name]['class']}({name[0]})"
                _diff_methods(findings, owner, wanted[name]["instance_methods"],
                              found[name]["instance_methods"], "-")
                _diff_methods(findings, owner, wanted[name]["class_methods"],
                              found[name]["class_methods"], "+")

    # Section placement of a constant is a codegen choice, not ABI; compare the
    # union of the two buckets rather than each bucket separately.
    wanted_symbols, found_symbols = _exported(expected), _exported(actual)
    for name in sorted(wanted_symbols - found_symbols):
        findings.append(f"{module}: missing exported symbol {name}")
    for name in sorted(found_symbols - wanted_symbols):
        findings.append(f"{module}: unexpected exported symbol {name}")

    return findings
