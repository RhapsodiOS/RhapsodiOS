# Kernel PCI and PCMCIA Reconstruction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Map the 24 Objective-C methods of DriverKit's PCI and PCMCIA layer in Apple's shipped DR2 i386 kernel to our five `libDriver` sources, record the divergences, and fix them.

**Architecture:** Three tooling changes come first, each test-first: accept `MH_EXECUTE` in the Mach-O reader; add an Objective-C method index that recovers `address -> name` from `__OBJC` runtime metadata (a linked kernel names no methods in its symbol table); and add analysis scoping so a source map may cover a declared subset of a 1.4 MB binary without weakening the exact-partition check. Then the usual report pass and fix pass.

**Tech Stack:** Python 3.13.9, binrecon (`tools/binrecon`), IDA Professional 9.2, Ghidra 12.1 on Java 21, angr 9.3.0, pytest 9.1.1, jsonschema 4.26.0.

**Spec:** `docs/superpowers/specs/2026-07-25-kernel-pci-pcmcia-reconstruction-design.md`

**Prior art:** `docs/superpowers/plans/2026-07-25-intel-bus-driver-binary-reconstruction.md` did this for two drivers. Its conventions are reused unchanged. Read `src/drivers-i386/bus/Intel824X0PCI/reconstruction/divergences.md` before Task 7 — it is the worked example the reports should resemble.

## Global Constraints

- Python is 3.13.9 at `./.venv-binrecon/Scripts/python.exe`. Every binrecon invocation needs `PYTHONPATH=tools/binrecon` and runs from the repository root.
- **Test baseline is 650 passed, 4 skipped, 0 failed.** Verify before you start. Any failure you see is yours.
- IDA `version` must be `9.2`; Ghidra `12.1` with Java 21; angr `9.3.0`.
- The reference kernel lives at `C:\Users\raynorpat\Downloads\test\mach_kernel_dr2_x86` and is **never** committed. Size 1404116, SHA-256 `BE98A33F71B80AEE00A6921333943DA02D0B676C8AF056843EB868C14EBB497C`.
- Architecture `i386`, endianness `little`.
- All SHA-256 values are **uppercase**. `source_path` values are repo-relative POSIX (forward slashes, no drive letter, no `.`/`..`).
- Source-map arrays sorted by `(address, tuple(reference_names))`; `reference_names` and `reasons` sorted and unique.
- Ledger vocabulary is exactly `unexamined`, `signature-confirmed`, `control-flow-confirmed`, `assembly-matched`, `intentional-mismatch`. The tool forbids skipping states; `intentional-mismatch` requires passing through a reviewed state plus `--reason` and `--reviewer` (use `Pat Raynor`). `rebuilt_sha256` stays `null`.
- **`assembly-matched` requires instruction-level evidence from a rebuilt binary.** No build host is reachable, so it cannot be claimed. `control-flow-confirmed` is the ceiling for a source-only change.
- A diverging function stays `unexamined` in the report pass and is written up; the fix pass advances it.
- Commit messages: short, subsystem-prefixed (`binrecon: `, `driverkit: `), one to two lines, no metadata, no trailers.
- **Another agent commits to this repository concurrently.** Stage only your own files by explicit path. Never `git add -A`, never `git commit -a`.

## Reference method inventory

The 24 methods, their IMPs, and their type encodings. Tasks 3, 6 and 7 assert against this table.

| IMP | Name | Module |
| --- | --- | --- |
| `0x1fd0d4` | `+[IODirectDevice(IOPCIDirectDevice) isPCIPresent]` | `IOPCIDirectDevice.m` |
| `0x1fd114` | `-[IODirectDevice(IOPCIDirectDevice) isPCIPresent]` | `IOPCIDirectDevice.m` |
| `0x1fd154` | `+[IODirectDevice(IOPCIDirectDevice) getPCIConfigSpace:withDeviceDescription:]` | `IOPCIDirectDevice.m` |
| `0x1fd208` | `-[IODirectDevice(IOPCIDirectDevice) getPCIConfigSpace:]` | `IOPCIDirectDevice.m` |
| `0x1fd248` | `+[IODirectDevice(IOPCIDirectDevice) setPCIConfigSpace:withDeviceDescription:]` | `IOPCIDirectDevice.m` |
| `0x1fd2fc` | `-[IODirectDevice(IOPCIDirectDevice) setPCIConfigSpace:]` | `IOPCIDirectDevice.m` |
| `0x1fd33c` | `+[IODirectDevice(IOPCIDirectDevice) getPCIConfigData:atRegister:withDeviceDescription:]` | `IOPCIDirectDevice.m` |
| `0x1fd3dc` | `-[IODirectDevice(IOPCIDirectDevice) getPCIConfigData:atRegister:]` | `IOPCIDirectDevice.m` |
| `0x1fd428` | `+[IODirectDevice(IOPCIDirectDevice) setPCIConfigData:atRegister:withDeviceDescription:]` | `IOPCIDirectDevice.m` |
| `0x1fd4c8` | `-[IODirectDevice(IOPCIDirectDevice) setPCIConfigData:atRegister:]` | `IOPCIDirectDevice.m` |
| `0x1fd514` | `-[IOPCIDeviceDescription(Private) _initWithDelegate:]` | `IOPCIDeviceDescription.m` |
| `0x1fd5c4` | `-[IOPCIDeviceDescription free]` | `IOPCIDeviceDescription.m` |
| `0x1fd5fc` | `-[IOPCIDeviceDescription getPCIdevice:function:bus:]` | `IOPCIDeviceDescription.m` |
| `0x1fd644` | `-[IODirectDevice(IOPCMCIADirectDevice) mapAttributeMemoryTo:findSpace:]` | `IOPCMCIADirectDevice.m` |
| `0x1fd8c4` | `-[IODirectDevice(IOPCMCIADirectDevice) unmapAttributeMemory]` | `IOPCMCIADirectDevice.m` |
| `0x1fda10` | `-[IOPCMCIADeviceDescription(Private) _initWithDelegate:]` | `IOPCMCIADeviceDescription.m` |
| `0x1fda64` | `-[IOPCMCIADeviceDescription free]` | `IOPCMCIADeviceDescription.m` |
| `0x1fdae0` | `-[IOPCMCIADeviceDescription numTuples]` | `IOPCMCIADeviceDescription.m` |
| `0x1fdb08` | `-[IOPCMCIADeviceDescription tupleList]` | `IOPCMCIADeviceDescription.m` |
| `0x1fdbc0` | `-[IOPCMCIATuple(Private) initWithKernTuple:]` | `IOPCMCIATuple.m` |
| `0x1fdc60` | `-[IOPCMCIATuple free]` | `IOPCMCIATuple.m` |
| `0x1fdcb0` | `-[IOPCMCIATuple code]` | `IOPCMCIATuple.m` |
| `0x1fdcc4` | `-[IOPCMCIATuple length]` | `IOPCMCIATuple.m` |
| `0x1fdcd4` | `-[IOPCMCIATuple data]` | `IOPCMCIATuple.m` |

Note `isPCIPresent` appears twice, as a class and an instance method at different addresses. A walk that follows only instance method lists returns 19 and starts at `0x1fd2fc` — both wrong.

## Objective-C metadata layout

The on-disk structures the Task 2 walk decodes. All fields are 32-bit little-endian.

| Struct | Fields, in order |
| --- | --- |
| `objc_module` (16 B) | `version`, `size`, `name` (char\*), `symtab` (ptr) |
| `objc_symtab` (12 B + defs) | `sel_ref_cnt`, `refs` (ptr), `cls_def_cnt` (u16), `cat_def_cnt` (u16), then `cls_def_cnt + cat_def_cnt` pointers |
| `objc_class` (32 B) | `isa` (metaclass ptr), `super_class`, `name` (char\*), `version`, `info`, `instance_size`, `ivars`, `methodList` |
| `objc_category` (16 B) | `category_name` (char\*), `class_name` (char\*), `instance_methods`, `class_methods` |
| `objc_method_list` (8 B + entries) | `obsolete`, `method_count`, then `method_count` entries |
| `objc_method` (12 B) | `method_name` (SEL, a char\*), `method_types` (char\*), `method_imp` |

Class methods live on the class's `isa` (metaclass) `methodList`; a category's class methods live in its `class_methods` list.

## File Structure

**Created:**

| Path | Responsibility |
| --- | --- |
| `tools/binrecon/tests/test_objc_index.py` | Tests for the Objective-C metadata walk and the index |
| `tools/binrecon/profiles/kernel-driverkit.json` | Reference-only profile for the kernel |
| `src/driverkit-3/libDriver/reconstruction/source-map.json` | Function partition for the 24 methods |
| `src/driverkit-3/libDriver/reconstruction/ledger.json` | Parity ledger |
| `src/driverkit-3/libDriver/reconstruction/divergences.md` | Report-pass findings |

**Modified:**

| Path | Change |
| --- | --- |
| `tools/binrecon/binrecon/macho.py` | Accept `MH_EXECUTE`; add `objc_method_index` and its helper |
| `tools/binrecon/binrecon/source_map.py` | Merge the Objective-C index into the address-to-name mapping; add analysis scoping |
| `tools/binrecon/binrecon/cli.py` | `source-map` gains `--objc-methods` and `--scope-to-objc`, and `--source-dir` becomes repeatable |
| `tools/binrecon/tests/test_macho.py` | `MH_EXECUTE` acceptance test |
| `tools/binrecon/tests/test_source_map_builder.py` | Merge and scoping tests |
| `src/driverkit-3/libDriver/Makefile:46` | Add `pcmcia` to `SOURCE_DIRS` |

---

### Task 1: Accept MH_EXECUTE in the Mach-O reader

**Files:**
- Modify: `tools/binrecon/binrecon/macho.py:12-14,132-135`
- Test: `tools/binrecon/tests/test_macho.py`

**Interfaces:**
- Consumes: `tests/macho_fixture.build_macho_fixture(*, extra_command=b"", file_type=MH_OBJECT, base_address=0x1000)`, which already parameterises `file_type`.
- Produces: `read_macho()` accepting file type 2, which Tasks 3 and 6 rely on.

- [ ] **Step 1: Write the failing test**

Append to `tools/binrecon/tests/test_macho.py`:

```python
def test_read_macho_accepts_a_linked_executable(tmp_path):
    from tests.macho_fixture import build_macho_fixture

    target = tmp_path / "kernel"
    target.write_bytes(build_macho_fixture(file_type=2))

    document = read_macho(target)

    assert document["input"]["architecture"] == "i386"
    assert any(section["name"] == "__TEXT,__text" for section in document["sections"])
```

Match the file's existing import style — if it imports the fixture at module scope, put the import there instead and drop the local one.

- [ ] **Step 2: Run it and confirm it fails**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests/test_macho.py::test_read_macho_accepts_a_linked_executable -q
```

Expected: FAIL with `unsupported Mach-O file type 2`.

- [ ] **Step 3: Add the constant and accept it**

In `tools/binrecon/binrecon/macho.py`, beside the existing `MH_OBJECT = 1` / `MH_PRELOAD = 5` / `MH_BUNDLE = 8`, add:

```python
MH_EXECUTE = 2
```

Then change the guard at line 132 from:

```python
    if file_type not in (MH_OBJECT, MH_PRELOAD, MH_BUNDLE):
        raise MachOFormatError(
            f"unsupported Mach-O file type {file_type}; "
            "expected MH_OBJECT, MH_PRELOAD or MH_BUNDLE"
        )
```

to:

```python
    if file_type not in (MH_OBJECT, MH_PRELOAD, MH_BUNDLE, MH_EXECUTE):
        raise MachOFormatError(
            f"unsupported Mach-O file type {file_type}; "
            "expected MH_OBJECT, MH_PRELOAD, MH_BUNDLE or MH_EXECUTE"
        )
```

- [ ] **Step 4: Run the test and the full suite**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests -q
```

Expected: `651 passed, 4 skipped`.

- [ ] **Step 5: Verify it reads the real kernel**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -c "
from pathlib import Path
from binrecon.macho import read_macho
d = read_macho(Path(r'C:\Users\raynorpat\Downloads\test\mach_kernel_dr2_x86'))
print('sha256', d['input']['sha256'])
print('sections', len(d['sections']), 'symbols', len(d['symbols']))
print([s['name'] for s in d['sections']][:6])
"
```

Expected: sha256 `BE98A33F71B80AEE00A6921333943DA02D0B676C8AF056843EB868C14EBB497C`, and a non-empty section list including `__TEXT,__text`.

**If this raises**, the reader does not tolerate a linked executable's layout — most likely the `__PAGEZERO` segment, which has `vmsize` 4096 and zero file content. Fix the reader to skip or tolerate zero-file-size segments, add a regression test using `build_macho_fixture`, and re-run Step 4 before continuing. Do not work around it in a caller.

- [ ] **Step 6: Commit**

```bash
git add tools/binrecon/binrecon/macho.py tools/binrecon/tests/test_macho.py
git commit -m "binrecon: accept MH_EXECUTE so linked kernels can be read"
```

---

### Task 2: Decode Objective-C method metadata

The core of the effort. A linked kernel names no methods in its symbol table, so `address -> name` must come from the runtime metadata.

**Files:**
- Modify: `tools/binrecon/binrecon/macho.py`
- Test: `tools/binrecon/tests/test_objc_index.py` (create)

**Interfaces:**
- Produces: `macho.objc_methods_from_sections(payload: bytes, sections: list[dict]) -> dict[int, list[str]]`, mapping each IMP to sorted unique names in `-[Class selector]` / `+[Class selector]` / `-[Class(Category) selector]` form. `sections` entries need only `address`, `size` and `offset` keys.

Split this way so the walk is testable without constructing a whole valid Mach-O. Task 3 adds the file-level wrapper.

- [ ] **Step 1: Write the failing test**

Create `tools/binrecon/tests/test_objc_index.py`:

```python
import struct

from binrecon.macho import objc_methods_from_sections

BASE = 0x1000


def _build():
    """One class with an instance and a class method, plus one category."""
    blob = bytearray(0x200)

    def put(offset, *values):
        struct.pack_into(f"<{len(values)}I", blob, offset, *values)

    def put_str(offset, text):
        raw = text.encode("ascii") + b"\0"
        blob[offset:offset + len(raw)] = raw

    # objc_module: version, size, name, symtab
    put(0x00, 0, 16, BASE + 0x100, BASE + 0x20)
    # objc_symtab: sel_ref_cnt, refs, then cls_def_cnt/cat_def_cnt as u16 pair
    put(0x20, 0, 0)
    struct.pack_into("<HH", blob, 0x28, 1, 1)
    put(0x2C, BASE + 0x40, BASE + 0x80)
    # objc_class: isa, super, name, version, info, instance_size, ivars, methodList
    put(0x40, BASE + 0x60, 0, BASE + 0x110, 0, 0, 0, 0, BASE + 0xA0)
    # metaclass: only isa/name/methodList matter
    put(0x60, 0, 0, BASE + 0x110, 0, 0, 0, 0, BASE + 0xC0)
    # objc_category: category_name, class_name, instance_methods, class_methods
    put(0x80, BASE + 0x120, BASE + 0x110, BASE + 0xE0, 0)
    # method lists: obsolete, count, then (sel, types, imp)
    put(0xA0, 0, 1, BASE + 0x130, BASE + 0x140, 0x2000)
    put(0xC0, 0, 1, BASE + 0x150, BASE + 0x140, 0x2100)
    put(0xE0, 0, 1, BASE + 0x160, BASE + 0x140, 0x2200)

    put_str(0x100, "Test.m")
    put_str(0x110, "Thing")
    put_str(0x120, "Extra")
    put_str(0x130, "doThing")
    put_str(0x140, "v8@8:12")
    put_str(0x150, "makeThing:")
    put_str(0x160, "extraThing")
    return bytes(blob)


SECTIONS = [
    {"name": "__OBJC,__module_info", "address": BASE, "size": 16, "offset": 0},
    {"name": "__OBJC,__blob", "address": BASE, "size": 0x200, "offset": 0},
]


def test_recovers_instance_class_and_category_methods():
    index = objc_methods_from_sections(_build(), SECTIONS)

    assert index == {
        0x2000: ["-[Thing doThing]"],
        0x2100: ["+[Thing makeThing:]"],
        0x2200: ["-[Thing(Extra) extraThing]"],
    }


def test_returns_empty_when_there_is_no_module_info():
    sections = [{"name": "__TEXT,__text", "address": BASE, "size": 4, "offset": 0}]

    assert objc_methods_from_sections(b"\0" * 16, sections) == {}
```

- [ ] **Step 2: Run it and confirm it fails**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests/test_objc_index.py -q
```

Expected: `ImportError: cannot import name 'objc_methods_from_sections'`.

- [ ] **Step 3: Implement the walk**

Add to `tools/binrecon/binrecon/macho.py`. Place it after `read_macho` and match the file's existing style.

```python
_MODULE_INFO_SECTION = "__OBJC,__module_info"
_OBJC_MODULE = struct.Struct("<4I")
_OBJC_CLASS = struct.Struct("<8I")
_OBJC_CATEGORY = struct.Struct("<4I")


def objc_methods_from_sections(payload, sections):
    """Map each Objective-C method implementation address to its names.

    A linked executable names no methods in its symbol table, so the runtime
    metadata is the only source of address-to-name for them.
    """
    spans = [s for s in sections if s.get("size")]

    def offset_of(address):
        for span in spans:
            start = span["address"]
            if start <= address < start + span["size"]:
                return span["offset"] + (address - start)
        return None

    def read(structure, address):
        offset = offset_of(address)
        if offset is None or offset + structure.size > len(payload):
            return None
        return structure.unpack_from(payload, offset)

    def text(address):
        offset = offset_of(address)
        if offset is None:
            return None
        end = payload.find(b"\0", offset)
        if end < 0:
            return None
        return payload[offset:end].decode("latin1")

    index = {}

    def collect(list_address, owner, sign):
        if not list_address:
            return
        offset = offset_of(list_address)
        if offset is None:
            return
        _, count = struct.unpack_from("<2I", payload, offset)
        for entry in range(count):
            base = offset + 8 + entry * 12
            if base + 12 > len(payload):
                return
            selector_address, _types, imp = struct.unpack_from("<3I", payload, base)
            selector = text(selector_address)
            if not selector or not imp:
                continue
            index.setdefault(imp, set()).add(f"{sign}[{owner} {selector}]")

    module_section = next(
        (s for s in sections if s["name"] == _MODULE_INFO_SECTION), None
    )
    if module_section is None:
        return {}

    for ordinal in range(module_section["size"] // _OBJC_MODULE.size):
        module_offset = module_section["offset"] + ordinal * _OBJC_MODULE.size
        if module_offset + _OBJC_MODULE.size > len(payload):
            break
        _version, _size, _name, symtab = _OBJC_MODULE.unpack_from(payload, module_offset)
        symtab_offset = offset_of(symtab) if symtab else None
        if symtab_offset is None:
            continue
        class_count, category_count = struct.unpack_from("<HH", payload, symtab_offset + 8)
        total = class_count + category_count
        definitions = struct.unpack_from(f"<{total}I", payload, symtab_offset + 12) if total else ()

        for position, definition in enumerate(definitions):
            if position < class_count:
                fields = read(_OBJC_CLASS, definition)
                if fields is None:
                    continue
                isa, _super, name_address = fields[0], fields[1], fields[2]
                owner = text(name_address)
                if not owner:
                    continue
                collect(fields[7], owner, "-")
                metaclass = read(_OBJC_CLASS, isa) if isa else None
                if metaclass is not None:
                    collect(metaclass[7], owner, "+")
            else:
                fields = read(_OBJC_CATEGORY, definition)
                if fields is None:
                    continue
                category_name, class_name, instance_methods, class_methods = fields
                owner_class = text(class_name)
                owner_category = text(category_name)
                if not owner_class or not owner_category:
                    continue
                owner = f"{owner_class}({owner_category})"
                collect(instance_methods, owner, "-")
                collect(class_methods, owner, "+")

    return {address: sorted(names) for address, names in index.items()}
```

If `struct` is not already imported at the top of `macho.py`, add it.

- [ ] **Step 4: Run the tests**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests/test_objc_index.py -q
```

Expected: `2 passed`.

- [ ] **Step 5: Run the full suite**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests -q
```

Expected: `653 passed, 4 skipped`.

- [ ] **Step 6: Commit**

```bash
git add tools/binrecon/binrecon/macho.py tools/binrecon/tests/test_objc_index.py
git commit -m "binrecon: recover Objective-C method addresses from runtime metadata"
```

---

### Task 3: The file-level Objective-C index, checked against the kernel

**Files:**
- Modify: `tools/binrecon/binrecon/macho.py`
- Test: `tools/binrecon/tests/test_objc_index.py`

**Interfaces:**
- Consumes: `objc_methods_from_sections` from Task 2, and `read_macho` from Task 1.
- Produces: `macho.objc_method_index(path: Path) -> dict[int, list[str]]`, used by Task 4.

- [ ] **Step 1: Write the failing test**

Append to `tools/binrecon/tests/test_objc_index.py`:

```python
from pathlib import Path

from binrecon.macho import objc_method_index


def test_objc_method_index_is_empty_for_a_binary_with_no_objc(tmp_path):
    from tests.macho_fixture import build_macho_fixture

    target = tmp_path / "plain"
    target.write_bytes(build_macho_fixture())

    assert objc_method_index(target) == {}
```

- [ ] **Step 2: Run it and confirm it fails**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests/test_objc_index.py -q
```

Expected: `ImportError: cannot import name 'objc_method_index'`.

- [ ] **Step 3: Implement it**

Add to `macho.py`, after `objc_methods_from_sections`:

```python
def objc_method_index(path):
    """Map each Objective-C method implementation address to its names."""
    document = read_macho(path)
    return objc_methods_from_sections(Path(path).read_bytes(), document["sections"])
```

`Path` is already imported in this module; if not, add it.

- [ ] **Step 4: Run the tests**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests/test_objc_index.py -q
```

Expected: `3 passed`. Then confirm the full suite:

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests -q
```

Expected: `654 passed, 4 skipped`.

- [ ] **Step 5: Check it against the real kernel — the gate for this task**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -c "
from pathlib import Path
from binrecon.macho import objc_method_index
index = objc_method_index(Path(r'C:\Users\raynorpat\Downloads\test\mach_kernel_dr2_x86'))
wanted = {a: n for a, n in index.items() if any('PCI' in x or 'PCMCIA' in x for x in n)}
print('total methods', len(index), '| PCI/PCMCIA', len(wanted))
for address in sorted(wanted):
    print(f'  0x{address:x} {wanted[address]}')
"
```

Expected: **24** PCI/PCMCIA methods, matching the plan's *Reference method inventory* table exactly — same addresses, same names, including both `isPCIPresent` entries and the five `+` methods. The total across the whole kernel will be far larger; only the filtered set is being asserted.

If the count is 19, the walk is following only instance method lists — the metaclass and category class-method branches in Task 2 Step 3 are not firing. Fix before continuing; every later task depends on this being right.

- [ ] **Step 6: Commit**

```bash
git add tools/binrecon/binrecon/macho.py tools/binrecon/tests/test_objc_index.py
git commit -m "binrecon: add a file-level Objective-C method index"
```

---

### Task 4: Merge the index into the source-map builder

**Files:**
- Modify: `tools/binrecon/binrecon/source_map.py:20-31,172-205`
- Test: `tools/binrecon/tests/test_source_map_builder.py`

**Interfaces:**
- Consumes: `objc_method_index` from Task 3.
- Produces: `build_source_map(reference_analysis, macho_document, sites, *, disputed=None, extra_names=None)`, where `extra_names` is a `dict[int, list[str]]` merged additively with the symbol table.

- [ ] **Step 1: Write the failing test**

Append to `tools/binrecon/tests/test_source_map_builder.py`. It already defines `_analysis(functions, sha256="A" * 64)` at line 378 and `_function(address, size, names)` at line 382 — reuse both rather than inventing new fixtures.

```python
def test_extra_names_resolve_a_source_site_the_symbol_table_cannot():
    analysis = _analysis([_function(0x2000, 0x10, ["sub_2000"])])
    macho = {"symbols": []}
    sites = {"-[Thing doThing]": [("src/thing.m", 12)]}

    document = build_source_map(
        analysis, macho, sites, extra_names={0x2000: ["-[Thing doThing]"]}
    )

    assert document["mapped"] == [
        {
            "address": 0x2000,
            "size": 0x10,
            "reference_names": ["sub_2000"],
            "source_path": "src/thing.m",
            "source_line": 12,
        }
    ]


def test_extra_names_are_merged_with_the_symbol_table_not_substituted_for_it():
    analysis = _analysis([_function(0x2000, 0x10, ["sub_2000"])])
    macho = {
        "symbols": [
            {"name": "_helper", "address": 0x2000, "binding": "local", "section": "__text"}
        ]
    }
    sites = {"_helper": [("src/thing.c", 3)], "-[Thing doThing]": [("src/thing.m", 12)]}

    document = build_source_map(
        analysis, macho, sites, extra_names={0x2000: ["-[Thing doThing]"]}
    )

    # Both names resolve to a site, so the address is genuinely ambiguous.
    assert [entry["address"] for entry in document["duplicate_candidates"]] == [0x2000]
```

The first test is the capability: a name the symbol table omits still reaches a source site. The second is the safety property from spec §3.4 — the merge is additive, so a real ambiguity surfaces in `duplicate_candidates` rather than being silently resolved by preferring one source.

The `reference_names` stay verbatim from the analysis (`sub_2000`); `extra_names` is a lookup aid, not a rename. That matches the existing behaviour tested by `test_build_source_map_keeps_analysis_names_verbatim_but_resolves_via_symbol_table`.

- [ ] **Step 2: Run it and confirm it fails**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests/test_source_map_builder.py -q
```

Expected: FAIL — `build_source_map() got an unexpected keyword argument 'extra_names'`.

- [ ] **Step 3: Implement the merge**

In `tools/binrecon/binrecon/source_map.py`, change the signature at line 172 to add the keyword, then merge it into the symbol index. After the existing `symbols = defined_symbols(macho_document)` at line 184, add:

```python
    if extra_names:
        merged = {address: set(names) for address, names in symbols.items()}
        for address, names in extra_names.items():
            merged.setdefault(address, set()).update(names)
        symbols = {address: sorted(names) for address, names in merged.items()}
```

The merge is additive: where both sources name an address, both names are kept. That preserves existing driver behaviour exactly and lets `duplicate_candidates` surface genuine ambiguity rather than hiding it.

- [ ] **Step 4: Run the tests and the full suite**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests -q
```

Expected: `656 passed, 4 skipped` (654 after Task 3, plus this task's two). **The existing source-map tests must all still pass** — a regression here breaks the three completed driver reconstructions.

- [ ] **Step 5: Commit**

```bash
git add tools/binrecon/binrecon/source_map.py tools/binrecon/tests/test_source_map_builder.py
git commit -m "binrecon: let a source map resolve names the symbol table omits"
```

---

### Task 5: Analysis scoping and the CLI flags

`schema._validate_source_map_context` (`schema.py:253`) demands exact set equality between a source map's addresses and its analysis's functions. A 24-method map against a whole-kernel analysis is rejected. Scope the analysis, not the check.

**Files:**
- Modify: `tools/binrecon/binrecon/source_map.py`, `tools/binrecon/binrecon/cli.py`
- Test: `tools/binrecon/tests/test_source_map_builder.py`

**Interfaces:**
- Produces: `source_map.scope_analysis(analysis: dict, addresses: set[int]) -> dict`, returning a copy whose `functions` list keeps only those addresses, everything else unchanged. And two `source-map` CLI flags: `--objc-methods` (bool) and `--scope-to-objc` (bool).

- [ ] **Step 1: Write the failing test**

Append to `tools/binrecon/tests/test_source_map_builder.py`:

```python
def test_scope_analysis_keeps_only_the_named_addresses_and_the_identity():
    analysis = _analysis([
        {"address": 0x1000, "size": 8, "names": ["a"]},
        {"address": 0x2000, "size": 8, "names": ["b"]},
    ])

    scoped = scope_analysis(analysis, {0x2000})

    assert [f["address"] for f in scoped["functions"]] == [0x2000]
    assert scoped["input"] == analysis["input"]
    assert [f["address"] for f in analysis["functions"]] == [0x1000, 0x2000]
```

The last assertion matters: scoping must not mutate its input, or a caller that scopes twice gets nonsense.

- [ ] **Step 2: Run it and confirm it fails**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests/test_source_map_builder.py -q
```

Expected: `NameError` / `ImportError` for `scope_analysis`.

- [ ] **Step 3: Implement it**

Add to `tools/binrecon/binrecon/source_map.py`:

```python
def scope_analysis(analysis, addresses):
    """Return a copy of an analysis keeping only the named functions.

    The input identity is preserved, so a source map built against the result
    still binds to the real binary by SHA-256 while covering a declared subset
    of a large image.
    """
    scoped = dict(analysis)
    scoped["functions"] = [
        function for function in analysis["functions"]
        if function["address"] in addresses
    ]
    return scoped
```

- [ ] **Step 4: Wire up the CLI**

In `tools/binrecon/binrecon/cli.py`, add two flags to the `source-map` subparser, following the style of its existing arguments:

```python
    parser.add_argument("--objc-methods", action="store_true",
                        help="resolve names from Objective-C metadata as well as "
                             "the symbol table")
    parser.add_argument("--scope-to-objc", action="store_true",
                        help="restrict the analysis to the Objective-C methods "
                             "found by --objc-methods")
```

In the subcommand body, when `--objc-methods` is set, build the index and pass it through; when `--scope-to-objc` is also set, narrow the analysis first:

```python
    extra_names = None
    if args.objc_methods:
        extra_names = objc_method_index(args.binary)
        if args.scope_to_objc:
            analysis = scope_analysis(analysis, set(extra_names))
```

`--scope-to-objc` without `--objc-methods` is a usage error; reject it with a clear message rather than silently doing nothing.

Import `objc_method_index` from `binrecon.macho` and `scope_analysis` from `binrecon.source_map` at the top of `cli.py`, matching the existing import style.

**Also make `--source-dir` repeatable.** Our sources live in two directories (`libDriver/pci` and `libDriver/pcmcia`), and `source_sites` globs one directory non-recursively, so a single path cannot cover both. Change the argument to `action="append"` and merge the resulting site maps:

```python
    sites = {}
    for directory in args.source_dir:
        for key, locations in source_sites(args.repo_root, directory).items():
            sites.setdefault(key, []).extend(locations)
```

Merging by extending is deliberate: a selector defined in both directories yields two candidate sites and lands in `duplicate_candidates`, which is the honest outcome. Update the argument's `help` to say it may be repeated, and check whether any existing caller passes `--source-dir` once — `action="append"` yields a list either way, so the merge loop handles both.

- [ ] **Step 5: Run the full suite**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests -q
```

Expected: `657 passed, 4 skipped`.

- [ ] **Step 6: Confirm the CLI help shows the flags**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m binrecon source-map --help
```

Expected: `--objc-methods` and `--scope-to-objc` both listed, and `--source-dir` documented as repeatable.

- [ ] **Step 7: Commit**

```bash
git add tools/binrecon/binrecon/source_map.py tools/binrecon/binrecon/cli.py tools/binrecon/tests/test_source_map_builder.py
git commit -m "binrecon: scope a source map to a subset of a large binary"
```

---

### Task 6: Profile the kernel and run the analyzers

**Files:**
- Create: `tools/binrecon/profiles/kernel-driverkit.json`

**Interfaces:**
- Produces: `tools/binrecon/out/kernel-driverkit/published/analysis-reference-{ida,ghidra,angr}.json`, which Task 7 reads.

- [ ] **Step 1: Write the profile**

Create `tools/binrecon/profiles/kernel-driverkit.json`. This is `profiles/intel82365pcmcia.json` with `name`, `output_dir`, and raised timeouts — the kernel is 1.4 MB against the drivers' 39 KB.

```json
{
  "schema_version": "profile-v1",
  "name": "kernel DriverKit PCI/PCMCIA reconstruction",
  "architecture": "i386",
  "endianness": "little",
  "reference": {
    "path": "${BINRECON_REFERENCE}"
  },
  "analyzers": {
    "ida": {
      "enabled": true,
      "executable": "C:/Program Files/IDA Professional 9.2/idat.exe",
      "timeout_seconds": 3600,
      "version": "9.2"
    },
    "ghidra": {
      "enabled": true,
      "executable": "D:/ghidra/support/analyzeHeadless.bat",
      "timeout_seconds": 3600,
      "version": "12.1"
    },
    "angr": {
      "enabled": true,
      "executable": ".venv-binrecon/Scripts/python.exe",
      "timeout_seconds": 3600,
      "version": "9.3.0"
    }
  },
  "comparison": {
    "acceptance": "normalized-functions",
    "ignore_metadata": [],
    "entry_points": []
  },
  "output_dir": "../out/kernel-driverkit"
}
```

- [ ] **Step 2: Validate it**

```bash
BINRECON_REFERENCE="C:/Users/raynorpat/Downloads/test/mach_kernel_dr2_x86" PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m binrecon validate --profile tools/binrecon/profiles/kernel-driverkit.json
```

Expected: exit 0, size `1404116`, SHA-256 `BE98A33F71B80AEE00A6921333943DA02D0B676C8AF056843EB868C14EBB497C`.

- [ ] **Step 3: Run the analyzers**

```bash
BINRECON_REFERENCE="C:/Users/raynorpat/Downloads/test/mach_kernel_dr2_x86" PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m binrecon analyze --profile tools/binrecon/profiles/kernel-driverkit.json
```

Expected: **exit 1** with `"complete": true`, `"rebuilt_sha256": null`, `"comparisons": []`. Exit 1 is correct for every reference-only run — `runner.py:259` computes acceptance from comparisons, and with none the tool refuses to report a pass. The gate is `"complete": true` plus a populated `published/`.

**Run this detached, owned by the session.** It is a long-lived child process and dies with its parent if launched from a subagent that exits. Expect this to take considerably longer than the drivers did.

- [ ] **Step 4: Confirm the analyzers found the 24 methods**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -c "
import json
from pathlib import Path
from binrecon.macho import objc_method_index
index = objc_method_index(Path(r'C:\Users\raynorpat\Downloads\test\mach_kernel_dr2_x86'))
wanted = {a for a, n in index.items() if any('PCI' in x or 'PCMCIA' in x for x in n)}
for analyzer in ('ida', 'ghidra', 'angr'):
    p = f'tools/binrecon/out/kernel-driverkit/published/analysis-reference-{analyzer}.json'
    found = {f['address'] for f in json.load(open(p))['functions']}
    print(analyzer, 'total', len(found), '| of our 24 found', len(wanted & found),
          '| missing', sorted(hex(a) for a in wanted - found))
"
```

Expected: IDA and Ghidra find all 24. **This is the cross-check that the metadata walk is right** — the analyzers discover function boundaries independently, so agreement between their entry points and our IMPs corroborates both. Any address IDA finds but our index missed, or vice versa, is a finding for Task 7 and must be understood before proceeding.

- [ ] **Step 5: Confirm nothing is tracked**

```bash
git status --porcelain tools/binrecon/out
```

Expected: no output.

- [ ] **Step 6: Commit**

```bash
git add tools/binrecon/profiles/kernel-driverkit.json
git commit -m "binrecon: add the kernel DriverKit reference-only profile"
```

---

### Task 7: Report pass

**Files:**
- Create: `src/driverkit-3/libDriver/reconstruction/{source-map.json,ledger.json,divergences.md}`

**Interfaces:**
- Consumes: the analyses from Task 6 and the CLI flags from Task 5.
- Produces: the findings Task 8 applies.

- [ ] **Step 1: Generate the scoped source map**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m binrecon source-map \
  --reference-analysis tools/binrecon/out/kernel-driverkit/published/analysis-reference-ida.json \
  --binary "C:/Users/raynorpat/Downloads/test/mach_kernel_dr2_x86" \
  --source-dir src/driverkit-3/libDriver/pci \
  --source-dir src/driverkit-3/libDriver/pcmcia \
  --repo-root . \
  --objc-methods --scope-to-objc \
  --output src/driverkit-3/libDriver/reconstruction/source-map.json
```

Both source directories are passed, using the repeatable flag Task 5 added.

**`--scope-to-objc` scopes to every Objective-C method in the kernel, not just ours** — that is far more than 24. Narrow the result to the addresses in the plan's *Reference method inventory* table before validating: drop every entry whose address is not one of the 24, and record in `divergences.md` that the map is deliberately scoped to the five modules. Keep every array sorted by `(address, tuple(reference_names))` after editing.

- [ ] **Step 2: Review the buckets**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -c "
import json
d = json.load(open('src/driverkit-3/libDriver/reconstruction/source-map.json'))
for key in ('mapped', 'unmapped', 'duplicate_candidates', 'boundary_disputed'):
    print(key, len(d[key]))
for entry in d['unmapped']:
    print('  unmapped:', entry['reference_names'])
"
```

Expected: 24 entries total. The three PCMCIA modules' methods should map to `src/driverkit-3/libDriver/pcmcia/*.m` even though those objects are absent from *our* kernel — the report compares Apple's binary against our source, which exists.

- [ ] **Step 3: Disassembly-diff all 24 methods**

The analyses carry **disassembly, not decompiled C**: per function, `instructions` (address, `bytes`, `mnemonic`, `operands`, `normalized_operands`, `relocations`), `blocks`, and `calls`.

Work one module at a time, in the inventory table's address order. For each method compare control-flow shape, literal constants, I/O port addresses, struct field offsets, and call targets against our source.

Two anchors specific to this layer:
- The reference's type encodings are recorded per method in `__OBJC,__meth_var_types`. A mismatch against our declaration is a real ABI divergence — the same class of finding that dominated the PCIC driver's Finding 11.
- `getPCIConfigSpace:` and friends take `^{?=SSSSb8b24CCCC[6L]LSSLLLCCCC[48L]}`, a PCI config-space struct. Check our struct's field order and widths against that encoding; a mismatch there silently corrupts every config-space read.

- [ ] **Step 4: Write `divergences.md`**

Create `src/driverkit-3/libDriver/reconstruction/divergences.md`, following the structure of `src/drivers-i386/bus/Intel824X0PCI/reconstruction/divergences.md`. Required sections beyond the per-finding ones:

- Header naming the reference and its SHA-256 `BE98A33F71B80AEE00A6921333943DA02D0B676C8AF056843EB868C14EBB497C`
- `## Baseline build` — state plainly that no build was run and no build host is reachable. **Do not invent or estimate build output.**
- `## Summary` with bucket counts, and an explicit statement of how many methods were examined at instruction level versus control-flow level versus not at all
- `## Scoping` — how the analysis was scoped, and the fact that this map covers 24 of the kernel's functions by design
- `## The missing PCMCIA modules` — our kernel lacks `IOPCMCIADeviceDescription`, `IOPCMCIADirectDevice` and `IOPCMCIATuple` entirely although the sources exist and the Makefile lists them; the cause needs a build to determine
- `## Analyzer disagreement` — anything from Task 6 Step 4

- [ ] **Step 5: Create the ledger**

All 24 methods need an entry. Seed with `binrecon.ledger.new_ledger`/`write_ledger` at `unexamined`, then transition with the CLI:

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m binrecon ledger \
  --profile tools/binrecon/profiles/kernel-driverkit.json \
  --ledger src/driverkit-3/libDriver/reconstruction/ledger.json \
  --address 0x1fdcd4 --status control-flow-confirmed \
  --source-path src/driverkit-3/libDriver/pcmcia/IOPCMCIATuple.m \
  --source-line <the source_line the source map recorded>
```

The tool forbids skipping states, so `intentional-mismatch` requires passing through a reviewed state first, plus `--reason` and `--reviewer "Pat Raynor"`.

- [ ] **Step 6: Validate the source map**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -c "
from pathlib import Path
from binrecon.schema import load_json, load_source_map
from binrecon.source_map import scope_analysis
from binrecon.macho import objc_method_index
analysis = load_json(Path('tools/binrecon/out/kernel-driverkit/published/analysis-reference-ida.json'))
index = objc_method_index(Path(r'C:\Users\raynorpat\Downloads\test\mach_kernel_dr2_x86'))
wanted = {a for a, n in index.items() if any('PCI' in x or 'PCMCIA' in x for x in n)}
load_source_map(
    Path('src/driverkit-3/libDriver/reconstruction/source-map.json'),
    reference_analysis=scope_analysis(analysis, wanted),
    repo_root=Path.cwd(),
)
print('source map valid')
"
```

Expected: `source map valid`.

- [ ] **Step 7: Commit**

```bash
git add src/driverkit-3/libDriver/reconstruction
git commit -m "driverkit: add the kernel PCI/PCMCIA reconstruction report"
```

---

### Task 8: Fix pass

**Files:**
- Modify: files named in `src/driverkit-3/libDriver/reconstruction/divergences.md`
- Modify: `src/driverkit-3/libDriver/reconstruction/{ledger.json,divergences.md}`

- [ ] **Step 1: Apply each finding marked `fix`**

Work one finding at a time, in document order. Change only the lines each finding names. No adjacent cleanup, no reformatting.

**Nothing can be compiled** — no build host is reachable. Re-read every edit as a compiler would: declaration and definition agreement, selector spelling, format specifiers against their arguments, and struct field order against the reference's type encodings.

**Governing principle**, carried from the driver effort: reproduce Apple's *form*, not Apple's *defects*. Match names, types, layout, linkage and comments exactly; where the reference is demonstrably buggy, keep our correct behaviour and record it as `intentional-mismatch` with its evidence.

- [ ] **Step 2: Advance the ledger**

For each fixed method, set the status the change now supports. `control-flow-confirmed` is the ceiling without a build.

- [ ] **Step 3: Record outcomes**

Append an `**Outcome:**` line to each finding stating what changed, the commit, and the new ledger status. Add a `## Post-fix parity` section recording that no build or parity run was performed and why.

- [ ] **Step 4: Commit**

```bash
git add src/driverkit-3/libDriver
git commit -m "driverkit: align the kernel PCI/PCMCIA layer with the reference

Applies the divergences confirmed by the reconstruction report pass."
```

---

### Task 9: Fix the SOURCE_DIRS omission

Independent of everything above, and safe.

**Files:**
- Modify: `src/driverkit-3/libDriver/Makefile:46`

- [ ] **Step 1: Add the missing directory**

Line 46 reads:

```make
SOURCE_DIRS= User Kernel ppc i386 eisa pci
```

Change it to:

```make
SOURCE_DIRS= User Kernel ppc i386 eisa pci pcmcia
```

`BUS_LIST` (line 55) and `KERNEL_DIRS` (line 276) already include `pcmcia`; `SOURCE_DIRS` feeds only the `tags` and `installsrc` targets (lines 378 and 394), so this fixes source installation and tag generation. **It is not the cause of the missing PCMCIA objects** — say so in the commit message so nobody reads it as the fix for that.

- [ ] **Step 2: Confirm nothing else omits it**

```bash
grep -n "eisa pci\|pci pcmcia\|BUS_LIST\|KERNEL_DIRS\|SOURCE_DIRS" src/driverkit-3/libDriver/Makefile
```

Expected: every list that enumerates buses now includes `pcmcia`.

- [ ] **Step 3: Commit**

```bash
git add src/driverkit-3/libDriver/Makefile
git commit -m "driverkit: add pcmcia to libDriver SOURCE_DIRS

Fixes installsrc and tags; not the cause of the absent PCMCIA objects."
```

---

## Verification summary

| Gate | Where | Command |
| --- | --- | --- |
| `MH_EXECUTE` accepted | Task 1 | `read_macho` on the real kernel returns the expected SHA-256 |
| Metadata walk correct | Task 3 | index yields exactly the 24 methods in the inventory table |
| No regression | Tasks 1-5 | `pytest tools/binrecon/tests -q` reaches 657 passed, 4 skipped |
| Analysis complete | Task 6 | `"complete": true`, populated `published/` |
| Walk corroborated | Task 6 | IDA/Ghidra function entry points coincide with our 24 IMPs |
| Source map valid | Task 7 | `load_source_map` against the scoped analysis |
| Every method ledgered | Task 7 | 24 entries |
