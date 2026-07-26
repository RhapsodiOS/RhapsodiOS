# Foundation Reconstruction, Stage 1 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Teach binrecon to read Apple's fat Foundation framework and extract its Objective-C ABI, then reconstruct `NSGeometry.m`, `NSRange.m` and `NSDecimal.m` against it as a proof of the whole pipeline.

**Architecture:** Six binrecon changes land first, each independently tested against synthetic Mach-O fixtures — `MH_DYLIB` acceptance, fat-container slice selection, an `__OBJC` ABI extractor, an `abi` emitter, an `abi-check` verifier, and a `module-scope` generator. Then a profile is written and IDA analyses the 43 scoped functions. Then the three modules are reconstructed against that analysis, gated by `abi-check` and a 28-function C test suite.

**Tech Stack:** Python 3.12 (binrecon, pytest 9.1.1, jsonschema 4.26.0), IDA Professional 9.2, Objective-C compiled in a Rhapsody guest via `src/rbuild-1`.

## Global Constraints

- Spec of record: [docs/superpowers/specs/2026-07-26-foundation-i386-reconstruction-design.md](../specs/2026-07-26-foundation-i386-reconstruction-design.md).
- Shipped fat container (input to `extract-slice` only): `C:/Users/raynorpat/Downloads/test/DR2/Frameworks/Foundation.framework/Versions/C/Foundation`, SHA-256 `215935DFAB3C083AB97E24F6B74B76C4AE668783892510F02D71AD9BFDE5192B`, size 3,425,564.
- **Reference of record:** the extracted thin i386 slice at `C:/Users/raynorpat/Downloads/test/Foundation-i386`, size **1,630,488**, SHA-256 **`1165B9063ADD5672514455CA2C9830625BEA2BCE5E46126FB5E8652114C909D6`**. This is what `$BINRECON_REFERENCE` points at and what every profile, analysis and comparison uses. `runner.py:312` cross-checks the analyzer's reported input identity against the profile's, so the container is never handed to an analyzer.
- **No header under `src/Kits/Foundation` may be modified.** If reconstruction appears to need a header change, stop and report.
- **No decompiler-generated identifiers in committed source.** No `param_1`, `v3`, `sub_42501428`, or decompiler comments. Source is written from an understanding of the behaviour, in the idiom of the surrounding headers.
- **Working directory is the worktree** `D:\RhapsodiOS\.claude\worktrees\foundation-recon` (branch `foundation-recon`). Run every command from there.
- **The venv lives at the main repo root and is gitignored, so the worktree has none.** Use the absolute interpreter path `/d/RhapsodiOS/.venv-binrecon/Scripts/python.exe` with `PYTHONPATH=tools/binrecon`, which resolves `binrecon` to the worktree's copy. Anywhere this plan writes `/d/RhapsodiOS/.venv-binrecon/Scripts/python.exe`, substitute the absolute path.
- Test command: `PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests -q`
- **The full suite takes about 5 minutes** (753 passed, 4 skipped at baseline). During a red/green cycle run only the focused test file — those finish in seconds. Run the full suite once before committing.
- Commit messages: start with the subsystem (`binrecon: `, `Foundation: `, `docs: `), one to two lines, describe behaviour not files, no metadata or trailers.
- **Never `git add -A` or `git add .`** — this repo tracks `__pycache__`, so every test run dirties a dozen `.pyc` files. Each commit step in this plan already names its exact paths; use those and nothing else. Leave the `.pyc` churn uncommitted.
- Do not add Foundation to `src/Manifest`, do not build the framework as a framework, and do not touch the 63 stub `.m` files outside this stage's three.

---

### Task 1: Confirm the guest can compile a Foundation module

This is spec §5.3, the stage's go/no-go gate. Everything after it assumes a Foundation `.m` compiles to a `.o` without any Foundation implementation existing. If it does not, stop and report — the finding reshapes the whole program.

**Files:**
- Create: `docs/superpowers/plans/notes/2026-07-26-foundation-compile-probe.md`

**Interfaces:**
- Consumes: nothing.
- Produces: a recorded compiler invocation that later tasks reuse verbatim to build the three modules.

- [ ] **Step 1: Find how the guest compiles an existing framework**

`src/Libsystem-2` and `src/LibcAT-1` are the two frameworks already built (both appear in `src/Manifest`). Read the build scripts to find the working invocation:

```bash
grep -rn "Libsystem-2\|LibcAT-1" src/rbuild-1/*.sh | head -20
```

Record which script builds them and how it invokes the guest.

- [ ] **Step 2: Compile the unmodified stub to an object**

`src/Kits/Foundation/NSGeometry.m` is currently a stub whose method bodies are all `// TODO`. Compile it as-is — this probes the headers, not our code. In the guest, from `src/Kits/Foundation`:

```bash
cc -c -I. -I/System/Library/Frameworks/System.framework/Headers -o /tmp/NSGeometry.o NSGeometry.m
```

Adjust the include paths to match what Step 1 found for `Libsystem-2`. The point is to discover the working invocation, not to use this one verbatim.

- [ ] **Step 3: Record the outcome**

Write `docs/superpowers/plans/notes/2026-07-26-foundation-compile-probe.md` containing: the exact working command line, the guest image used, the compiler version, and either `RESULT: compiles` with the `.o` size, or `RESULT: blocked` with the full error text.

- [ ] **Step 4: Gate**

If the result is `blocked`, **stop here and report to the user.** Do not proceed to Task 2. The spec's decomposition assumes this works and must be revised if it does not.

If it compiles, continue.

- [ ] **Step 5: Commit**

```bash
git add docs/superpowers/plans/notes/2026-07-26-foundation-compile-probe.md
git commit -m "Foundation: record the guest compile probe for stage 1"
```

---

### Task 2: Accept MH_DYLIB in the Mach-O reader

**Files:**
- Modify: `tools/binrecon/binrecon/macho.py:11-18` (constants), `tools/binrecon/binrecon/macho.py:138-142` (file type check)
- Modify: `tools/binrecon/tests/macho_fixture.py:4-12` (constants)
- Test: `tools/binrecon/tests/test_macho.py`

**Interfaces:**
- Consumes: nothing.
- Produces: `binrecon.macho.MH_DYLIB = 6`; `read_macho` no longer rejects file type 6.

- [ ] **Step 1: Write the failing test**

Append to `tools/binrecon/tests/test_macho.py`:

```python
def test_reads_a_dylib(tmp_path):
    from binrecon.macho import MH_DYLIB, read_macho
    from macho_fixture import build_macho_fixture

    path = tmp_path / "libthing.dylib"
    path.write_bytes(build_macho_fixture(file_type=MH_DYLIB))

    document = read_macho(path)

    assert document["input"]["architecture"] == "i386"
    assert any(section["name"] == "__TEXT,__text" for section in document["sections"])
```

- [ ] **Step 2: Run test to verify it fails**

Run: `PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests/test_macho.py::test_reads_a_dylib -q`

Expected: FAIL with `ImportError: cannot import name 'MH_DYLIB'`.

- [ ] **Step 3: Add the constant to the fixture builder**

In `tools/binrecon/tests/macho_fixture.py`, beside the other file-type constants:

```python
MH_DYLIB = 6
```

- [ ] **Step 4: Add the constant and accept it in the reader**

In `tools/binrecon/binrecon/macho.py`, beside `MH_BUNDLE = 8`:

```python
MH_DYLIB = 6
```

Then replace the file-type check:

```python
    if file_type not in (MH_OBJECT, MH_PRELOAD, MH_BUNDLE, MH_EXECUTE, MH_DYLIB):
        raise MachOFormatError(
            f"unsupported Mach-O file type {file_type}; "
            "expected MH_OBJECT, MH_PRELOAD, MH_BUNDLE, MH_EXECUTE or MH_DYLIB"
        )
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests -q`

Expected: PASS, no regressions.

- [ ] **Step 6: Commit**

```bash
git add tools/binrecon/binrecon/macho.py tools/binrecon/tests/macho_fixture.py tools/binrecon/tests/test_macho.py
git commit -m "binrecon: read MH_DYLIB images"
```

---

### Task 3: Read fat containers and extract a slice

Apple ships Foundation as a fat container holding an i386 and a ppc slice.
Everything downstream — the IDA adapter, `runner.py`'s identity check, `compare`,
`source-map` — works on a thin Mach-O and cross-checks the analyzer's reported
`input.sha256`/`size`/`path` against `profile.reference_identity`
(`tools/binrecon/binrecon/runner.py:312`). Making the reader silently report a
slice's identity while the profile names the container would break that check.

So the container is **materialized into a thin slice file once**, and the profile
points at that file. binrecon learns to read fat containers and to write a slice
out; it does not learn to pretend a container is a slice.

**Files:**
- Modify: `tools/binrecon/binrecon/macho.py` (add `FAT_MAGIC`, `extract_slice`, fat rejection in `load_image`, split `read_macho`)
- Modify: `tools/binrecon/binrecon/cli.py` (register `extract-slice`)
- Test: `tools/binrecon/tests/test_macho_fat.py` (create)

**Interfaces:**
- Consumes: `MH_DYLIB` from Task 2.
- Produces:
  - `binrecon.macho.is_fat(data: bytes) -> bool`.
  - `binrecon.macho.extract_slice(data: bytes, architecture: str) -> bytes` — the named slice's bytes, raising `MachOFormatError` naming the architectures present when there is no match.
  - `binrecon.macho.load_image(path) -> tuple[bytes, dict]` — the image payload and its analysis document. Raises `MachOFormatError` on a fat input, directing the caller to `extract-slice`.
  - `binrecon.macho.read_macho(path) -> dict` — unchanged signature and return, now a wrapper over `load_image`.
  - CLI `binrecon extract-slice --input PATH --architecture NAME --output PATH`.

**No schema changes.** `profile-v1` gains no `slice` field and `analysis-v1`
gains no `container` block: the profile's reference *is* a thin Mach-O, exactly
as for every existing driver target.

- [ ] **Step 1: Write the failing tests**

Create `tools/binrecon/tests/test_macho_fat.py`:

```python
import struct

import pytest

from binrecon.macho import (
    MH_DYLIB, MachOFormatError, extract_slice, is_fat, load_image, read_macho,
)
from macho_fixture import build_macho_fixture


def _fat(*slices):
    """Pack (cpu_type, payload) pairs into a fat container."""
    header = struct.pack(">2I", 0xCAFEBABE, len(slices))
    entries, blob, offset = b"", b"", 4096
    for cpu_type, payload in slices:
        entries += struct.pack(">5I", cpu_type, 0, offset, len(payload), 12)
        blob += payload
        offset += len(payload)
    padding = 4096 - len(header) - len(entries)
    assert padding >= 0, "fat header table does not fit before the first slice"
    return header + entries + b"\0" * padding + blob


def test_recognizes_a_fat_container():
    assert is_fat(_fat((7, build_macho_fixture(file_type=MH_DYLIB))))
    assert not is_fat(build_macho_fixture(file_type=MH_DYLIB))


def test_extracts_the_named_slice():
    i386 = build_macho_fixture(file_type=MH_DYLIB, architecture="i386")
    ppc = build_macho_fixture(file_type=MH_DYLIB, architecture="ppc")

    assert extract_slice(_fat((7, i386), (18, ppc)), "i386") == i386
    assert extract_slice(_fat((7, i386), (18, ppc)), "ppc") == ppc


def test_missing_slice_names_what_is_present():
    ppc = build_macho_fixture(file_type=MH_DYLIB, architecture="ppc")

    with pytest.raises(MachOFormatError, match="ppc"):
        extract_slice(_fat((18, ppc)), "i386")


def test_a_slice_running_past_the_file_is_an_error():
    truncated = _fat((7, build_macho_fixture(file_type=MH_DYLIB)))[:-16]

    with pytest.raises(MachOFormatError, match="past end of file"):
        extract_slice(truncated, "i386")


def test_load_image_rejects_a_fat_container(tmp_path):
    path = tmp_path / "Fat"
    path.write_bytes(_fat((7, build_macho_fixture(file_type=MH_DYLIB))))

    with pytest.raises(MachOFormatError, match="extract-slice"):
        read_macho(path)


def test_load_image_returns_the_payload_and_document(tmp_path):
    thin = build_macho_fixture(file_type=MH_DYLIB)
    path = tmp_path / "Thin"
    path.write_bytes(thin)

    payload, document = load_image(path)

    assert payload == thin
    assert document["input"]["architecture"] == "i386"
    assert document["input"]["size"] == len(thin)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests/test_macho_fat.py -q`

Expected: FAIL with `ImportError: cannot import name 'extract_slice'`.

- [ ] **Step 3: Add fat parsing to macho.py**

Add beside the other constants:

```python
FAT_MAGIC = 0xCAFEBABE
_FAT_ARCH = struct.Struct(">5I")
```

Add these above `read_macho`:

```python
def _architecture_name(cpu_type: int) -> str:
    """Name a fat entry's architecture from its CPU type alone.

    ``architecture_for_cpu_type`` requires the caller to already know the byte
    order and rejects a mismatch, but a fat table entry carries only the CPU
    type — the slice's own header decides its endianness. Try both.
    """
    for endianness in ("little", "big"):
        try:
            return architecture_for_cpu_type(cpu_type, endianness).name
        except ArchitectureError:
            continue
    return f"cpu-type-{cpu_type}"


def is_fat(data: bytes) -> bool:
    """Report whether an image is a fat container rather than a thin Mach-O."""
    if len(data) < 8:
        return False
    (magic,) = struct.unpack_from(">I", data, 0)
    return magic == FAT_MAGIC


def extract_slice(data: bytes, architecture: str) -> bytes:
    """Return the bytes of a fat container's named architecture slice.

    A slice is a complete Mach-O whose internal offsets are relative to its own
    start, so the returned bytes parse exactly like a thin image.
    """
    if not is_fat(data):
        raise MachOFormatError("input is not a fat Mach-O container")
    (_, count) = struct.unpack_from(">2I", data, 0)
    if 8 + count * _FAT_ARCH.size > len(data):
        raise MachOFormatError("fat header declares more slices than the file holds")
    present = []
    for index in range(count):
        cpu_type, _subtype, offset, size, _align = _FAT_ARCH.unpack_from(
            data, 8 + index * _FAT_ARCH.size
        )
        name = _architecture_name(cpu_type)
        present.append(name)
        if name != architecture:
            continue
        if offset + size > len(data):
            raise MachOFormatError(
                f"fat slice {name} runs past end of file at offset {offset}"
            )
        return data[offset:offset + size]
    raise MachOFormatError(
        f"fat container has no {architecture} slice; it holds "
        + ", ".join(sorted(present))
    )
```

- [ ] **Step 4: Split read_macho into load_image plus a wrapper**

Rename `def read_macho(path: Path) -> dict[str, Any]:` to:

```python
def load_image(path: Path) -> tuple[bytes, dict[str, Any]]:
```

Immediately after its existing `digest` guard, before `_select_architecture`,
insert the fat rejection:

```python
    if is_fat(data):
        raise MachOFormatError(
            f"{identity.path} is a fat Mach-O container; extract a thin slice "
            "first with 'binrecon extract-slice' and point the profile at that"
        )
```

Bind the returned document to a name and return the pair — change the function's
final `return {` to `document = {`, and after the closing brace add:

```python
    return data, document
```

Then add the wrapper immediately after:

```python
def read_macho(path: Path) -> dict[str, Any]:
    """Return the analysis document for an image, discarding its raw payload."""
    _payload, document = load_image(path)
    return document
```

- [ ] **Step 5: Register the extract-slice command**

In `tools/binrecon/binrecon/cli.py`, add `"extract-slice"` to the `COMMANDS`
tuple and register the parser beside the others:

```python
    extract = subparsers.add_parser("extract-slice")
    extract.add_argument("--input", required=True)
    extract.add_argument("--architecture", required=True)
    extract.add_argument("--output", required=True)
```

Add to the import block at the top of `cli.py`:

```python
from binrecon.macho import extract_slice, load_image
```

`main` dispatches with inline `if args.command == ...` blocks, each wrapping its
work in a try/except that prints `binrecon: {error}` to stderr and returns 1.
`os`, `sys`, `json` and `Path` are already imported at module level. Follow that
shape:

```python
    if args.command == "extract-slice":
        try:
            payload = extract_slice(
                Path(args.input).read_bytes(), args.architecture
            )
            Path(args.output).write_bytes(payload)
            digest = hashlib.sha256(payload).hexdigest().upper()
            print(f"wrote {args.output} size={len(payload)} sha256={digest}")
            return 0
        except (OSError, ValueError, ValidationError) as error:
            print(f"binrecon: {error}", file=sys.stderr)
            return 1
```

`hashlib` is not currently imported in `cli.py`; add `import hashlib` to the
import block.

- [ ] **Step 6: Run tests to verify they pass**

Run: `PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests/test_macho_fat.py tools/binrecon/tests/test_macho.py -q`

Expected: PASS.

Then the full suite once:

Run: `PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests -q`

Expected: PASS, no regressions. Existing callers of `read_macho` are unaffected —
the wrapper preserves its signature and return.

- [ ] **Step 7: Extract the real slice and verify its identity**

```bash
PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -m binrecon extract-slice --input "C:/Users/raynorpat/Downloads/test/DR2/Frameworks/Foundation.framework/Versions/C/Foundation" --architecture i386 --output "C:/Users/raynorpat/Downloads/test/Foundation-i386"
```

Expected exactly:

```
wrote C:/Users/raynorpat/Downloads/test/Foundation-i386 size=1630488 sha256=1165B9063ADD5672514455CA2C9830625BEA2BCE5E46126FB5E8652114C909D6
```

If the size or hash differs, stop — the slice is the reference of record for
every later task and its identity is fixed by spec §1.1.

Then confirm the reader accepts it:

```bash
PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -c "
from binrecon.macho import read_macho
d = read_macho(r'C:\Users\raynorpat\Downloads\test\Foundation-i386')
print(d['input']['architecture'], d['input']['size'])
print(len([s for s in d['sections'] if s['name'].startswith('__OBJC')]), 'OBJC sections')
"
```

Expected: `i386 1630488` and `21 OBJC sections`.

- [ ] **Step 8: Commit**

```bash
git add tools/binrecon/binrecon/macho.py tools/binrecon/binrecon/cli.py tools/binrecon/tests/test_macho_fat.py
git commit -m "binrecon: read fat Mach-O containers and extract a named slice"
```
---

---

### Task 4: Extract classes and ivars from `__OBJC`

**Files:**
- Create: `tools/binrecon/binrecon/objc_abi.py`
- Test: `tools/binrecon/tests/test_objc_abi.py` (create)

**Interfaces:**
- Consumes: `load_image` from Task 3; the `__OBJC` section-walking idiom in `binrecon/macho.py:423` (`objc_methods_from_sections`).
- Produces:
  - `binrecon.objc_abi.ObjcReader(payload, sections, endianness)` with methods `cstring(address)`, `at(address, count)`, `method_list(address)`.
  - `binrecon.objc_abi.read_classes(reader, symtab_address) -> list[dict]` returning class records shaped `{"name", "superclass", "instance_size", "info", "ivars", "instance_methods", "class_methods"}`.
  - `binrecon.objc_abi.method_symbol_index(document) -> dict[int, str]` mapping a method's implementation address to its `-[Class selector]` symbol name, built from an analysis document's `symbols` list.
  - ivar records shaped `{"name", "type", "offset"}`; method records shaped `{"selector", "types"}`.

**The reference is a prebound dylib.** Measured on the real slice: 369 of its
3,253 method entries carry a selector pointer that the static linker rewrote to
a uniqued selector in the shared runtime's table, at an address outside this
image — spread over 56 of the 80 modules. Naively dereferencing those pointers
raises. All 369 are recoverable from the symbol table, which names every method
`-[Class selector]`; zero are unresolvable. `ObjcReader` therefore takes an
optional `method_names` index and falls back to it. This is not an edge case to
defer: Task 5 walks every module, so it is hit immediately.

- [ ] **Step 1: Write the failing test**

Create `tools/binrecon/tests/test_objc_abi.py`. The fixture follows the same
shape as `tools/binrecon/tests/test_objc_index.py`, extended with an ivar list:

```python
import struct

from binrecon.objc_abi import ObjcReader, read_classes

BASE = 0x1000


def build_blob(prefix="<"):
    """One class with a superclass, two ivars, one instance and one class method."""
    blob = bytearray(0x300)

    def put(offset, *values):
        struct.pack_into(f"{prefix}{len(values)}I", blob, offset, *values)

    def put_str(offset, text):
        raw = text.encode("ascii") + b"\0"
        blob[offset:offset + len(raw)] = raw

    # objc_symtab: sel_ref_cnt, refs, then cls_def_cnt/cat_def_cnt as u16 pair
    put(0x20, 0, 0)
    struct.pack_into(f"{prefix}HH", blob, 0x28, 1, 0)
    put(0x2C, BASE + 0x40)
    # objc_class: isa, super, name, version, info, instance_size, ivars, methodList
    put(0x40, BASE + 0x60, BASE + 0x1C0, BASE + 0x110, 0, 1, 12, BASE + 0x200, BASE + 0xA0)
    # metaclass: isa, super, name, version, info, instance_size, ivars, methodList
    put(0x60, 0, 0, BASE + 0x110, 0, 2, 0, 0, BASE + 0xC0)
    # method lists: obsolete, count, then (sel, types, imp)
    put(0xA0, 0, 1, BASE + 0x130, BASE + 0x140, 0x2000)
    put(0xC0, 0, 1, BASE + 0x150, BASE + 0x140, 0x2100)
    # objc_ivar_list: count, then (name, type, offset)
    put(0x200, 2)
    put(0x204, BASE + 0x170, BASE + 0x180, 4)
    put(0x210, BASE + 0x190, BASE + 0x1A0, 8)

    put_str(0x110, "Thing")
    put_str(0x130, "doThing")
    put_str(0x140, "v8@8:12")
    put_str(0x150, "makeThing:")
    put_str(0x170, "_count")
    put_str(0x180, "I")
    put_str(0x190, "_name")
    put_str(0x1A0, "@")
    put_str(0x1C0, "NSObject")
    return bytes(blob)


SECTIONS = [{"name": "__OBJC,__blob", "address": BASE, "size": 0x300, "offset": 0}]


def test_reads_class_layout_and_ivars():
    reader = ObjcReader(build_blob(), SECTIONS, "little")

    assert read_classes(reader, BASE + 0x20) == [{
        "name": "Thing",
        "superclass": "NSObject",
        "instance_size": 12,
        "info": 1,
        "ivars": [
            {"name": "_count", "type": "I", "offset": 4},
            {"name": "_name", "type": "@", "offset": 8},
        ],
        "instance_methods": [{"selector": "doThing", "types": "v8@8:12"}],
        "class_methods": [{"selector": "makeThing:", "types": "v8@8:12"}],
    }]


def test_reads_big_endian_the_same_way():
    reader = ObjcReader(build_blob(">"), SECTIONS, "big")
    assert read_classes(reader, BASE + 0x20)[0]["name"] == "Thing"


def test_recovers_a_prebound_selector_from_the_symbol_table():
    """A selector pointer outside the image is resolved via the symbol table."""
    blob = bytearray(build_blob())
    # Point the instance method's selector at an address no section backs.
    struct.pack_into("<I", blob, 0xA8, 0x41406990)

    reader = ObjcReader(bytes(blob), SECTIONS, "little",
                        method_names={0x2000: "-[Thing doThing]"})

    assert read_classes(reader, BASE + 0x20)[0]["instance_methods"] == [
        {"selector": "doThing", "types": "v8@8:12"}
    ]


def test_an_unresolvable_prebound_selector_is_an_error():
    from binrecon.objc_abi import ObjcAbiError

    blob = bytearray(build_blob())
    struct.pack_into("<I", blob, 0xA8, 0x41406990)
    reader = ObjcReader(bytes(blob), SECTIONS, "little")

    with pytest.raises(ObjcAbiError, match="outside the image"):
        read_classes(reader, BASE + 0x20)


def test_method_symbol_index_keys_on_implementation_address():
    from binrecon.objc_abi import method_symbol_index

    document = {"symbols": [
        {"name": "-[Thing doThing]", "address": 0x2000, "section": "__TEXT,__text"},
        {"name": "+[Thing(Extra) make]", "address": 0x2100, "section": "__TEXT,__text"},
        {"name": "_NotAMethod", "address": 0x2200, "section": "__TEXT,__text"},
        {"name": "-[Thing imported]", "address": 0, "section": None},
    ]}

    assert method_symbol_index(document) == {
        0x2000: "-[Thing doThing]",
        0x2100: "+[Thing(Extra) make]",
    }
```

The offset `0xA8` is the instance method list's first `selector` field: the list
header sits at `0xA0` and is two words, so the first method record begins at
`0xA8`. `pytest` must be imported at the top of the test file.

- [ ] **Step 2: Run test to verify it fails**

Run: `PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests/test_objc_abi.py -q`

Expected: FAIL with `ModuleNotFoundError: No module named 'binrecon.objc_abi'`.

- [ ] **Step 3: Write the reader and class extraction**

Create `tools/binrecon/binrecon/objc_abi.py`:

```python
"""Read Objective-C ABI facts out of a linked image's ``__OBJC`` segment.

A linked image names no methods in its symbol table beyond the ``-[Class sel]``
form, and names no ivars at all. The runtime metadata is the only source for
instance sizes, ivar offsets and type encodings, which are the parts of the ABI
that client code is compiled against.
"""

import struct


class ObjcAbiError(ValueError):
    """Raised when ``__OBJC`` metadata is absent or malformed."""


_PREFIX = {"little": "<", "big": ">"}


class ObjcReader:
    """Random access to an image by virtual address."""

    def __init__(self, payload, sections, endianness, method_names=None):
        self.payload = payload
        # imp address -> "-[Class selector]", consulted when a selector pointer
        # was rewritten by prebinding to an address outside this image.
        self.method_names = method_names or {}
        self.prefix = _PREFIX[endianness]
        self._word = struct.Struct(f"{self.prefix}I")
        self._spans = [
            (section["address"], section["size"], section["offset"])
            for section in sections
            if section.get("size")
        ]

    def offset_of(self, address):
        for start, size, offset in self._spans:
            if start <= address < start + size:
                return offset + (address - start)
        return None

    def at(self, address, count):
        """Return ``count`` 32-bit words starting at ``address``."""
        offset = self.offset_of(address)
        if offset is None or offset + 4 * count > len(self.payload):
            raise ObjcAbiError(f"address 0x{address:x} is not backed by the image")
        return struct.unpack_from(f"{self.prefix}{count}I", self.payload, offset)

    def halves(self, address, count):
        offset = self.offset_of(address)
        if offset is None or offset + 2 * count > len(self.payload):
            raise ObjcAbiError(f"address 0x{address:x} is not backed by the image")
        return struct.unpack_from(f"{self.prefix}{count}H", self.payload, offset)

    def cstring(self, address):
        if not address:
            return None
        offset = self.offset_of(address)
        if offset is None:
            raise ObjcAbiError(f"string address 0x{address:x} is not backed by the image")
        end = self.payload.find(b"\0", offset)
        if end < 0:
            raise ObjcAbiError(f"unterminated string at 0x{address:x}")
        return self.payload[offset:end].decode("latin1")

    def method_list(self, address):
        """Return ``[{selector, types}]`` for an ``objc_method_list``."""
        if not address or self.offset_of(address) is None:
            return []
        _obsolete, count = self.at(address, 2)
        methods = []
        for index in range(count):
            selector, types, imp = self.at(address + 8 + 12 * index, 3)
            methods.append({
                "selector": self.selector(selector, imp),
                "types": self.cstring(types),
            })
        return methods

    def selector(self, address, imp):
        """Name a method's selector, tolerating prebound selector pointers.

        The reference is a prebound dylib: the static linker rewrote 369 of its
        3,253 method-name pointers to uniqued selectors in the shared runtime's
        table, at addresses outside this image. Those are recovered from the
        symbol table, where the method is named ``-[Class selector]`` or
        ``+[Class(Category) selector]``.
        """
        if self.offset_of(address) is not None:
            return self.cstring(address)
        symbol = self.method_names.get(imp)
        if symbol is None:
            raise ObjcAbiError(
                f"selector pointer 0x{address:x} is outside the image and no "
                f"symbol names the method implemented at 0x{imp:x}"
            )
        return symbol[symbol.index(" ") + 1:-1]

    def ivar_list(self, address):
        """Return ``[{name, type, offset}]`` for an ``objc_ivar_list``."""
        if not address or self.offset_of(address) is None:
            return []
        (count,) = self.at(address, 1)
        ivars = []
        for index in range(count):
            name, types, offset = self.at(address + 4 + 12 * index, 3)
            ivars.append({
                "name": self.cstring(name),
                "type": self.cstring(types),
                "offset": offset,
            })
        return ivars


def method_symbol_index(document):
    """Map each method's implementation address to its symbol name.

    Used to recover selectors whose pointers prebinding moved outside the image.
    """
    return {
        symbol["address"]: symbol["name"]
        for symbol in document["symbols"]
        if symbol["section"] is not None
        and symbol["name"].startswith(("-[", "+["))
    }


def read_classes(reader, symtab_address):
    """Return the class records an ``objc_symtab`` defines."""
    _sel_ref_count, _refs = reader.at(symtab_address, 2)
    class_count, category_count = reader.halves(symtab_address + 8, 2)
    definitions = reader.at(symtab_address + 12, class_count + category_count)
    classes = []
    for pointer in definitions[:class_count]:
        (metaclass, superclass, name, _version, info,
         instance_size, ivars, method_list) = reader.at(pointer, 8)
        _mi, _ms, _mn, _mv, _minfo, _msize, _mivars, class_methods = reader.at(
            metaclass, 8
        )
        classes.append({
            "name": reader.cstring(name),
            "superclass": reader.cstring(superclass),
            "instance_size": instance_size,
            "info": info,
            "ivars": reader.ivar_list(ivars),
            "instance_methods": reader.method_list(method_list),
            "class_methods": reader.method_list(class_methods),
        })
    return classes
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests/test_objc_abi.py -q`

Expected: PASS, 2 tests.

- [ ] **Step 5: Commit**

```bash
git add tools/binrecon/binrecon/objc_abi.py tools/binrecon/tests/test_objc_abi.py
git commit -m "binrecon: extract Objective-C class layouts and ivars from __OBJC"
```

---

### Task 5: Extract modules, categories and exported symbols

**Files:**
- Modify: `tools/binrecon/binrecon/objc_abi.py`
- Test: `tools/binrecon/tests/test_objc_abi.py`

**Interfaces:**
- Consumes: `ObjcReader`, `read_classes` from Task 4; `load_image` from Task 3.
- Produces:
  - `binrecon.objc_abi.read_modules(path) -> dict[str, dict]` mapping module name (e.g. `"NSGeometry.m"`) to an `abi-v1` document.
  - Document shape: `{"schema_version": "abi-v1", "module", "classes", "categories", "text_symbols", "data_symbols"}`.
  - Category records: `{"name", "class", "instance_methods", "class_methods"}`.

C symbols are attributed to a module by address: a symbol belongs to the module
whose nearest preceding Objective-C method it follows is not reliable (spec
§2.1), so `read_modules` instead attributes only what `__module_info` proves —
Objective-C definitions — and leaves `text_symbols`/`data_symbols` empty. Task 6
fills them from an explicit per-module symbol list, because for C functions the
header that declares them is the only sound attribution.

- [ ] **Step 1: Write the failing test**

Append to `tools/binrecon/tests/test_objc_abi.py`:

```python
def build_module_blob(prefix="<"):
    """A module defining no classes and one category on NSCoder."""
    blob = bytearray(0x300)

    def put(offset, *values):
        struct.pack_into(f"{prefix}{len(values)}I", blob, offset, *values)

    def put_str(offset, text):
        raw = text.encode("ascii") + b"\0"
        blob[offset:offset + len(raw)] = raw

    # objc_module: version, size, name, symtab
    put(0x00, 7, 16, BASE + 0x100, BASE + 0x20)
    put(0x20, 0, 0)
    struct.pack_into(f"{prefix}HH", blob, 0x28, 0, 1)
    put(0x2C, BASE + 0x80)
    # objc_category: category_name, class_name, instance_methods, class_methods
    put(0x80, BASE + 0x120, BASE + 0x110, BASE + 0xE0, 0)
    put(0xE0, 0, 1, BASE + 0x160, BASE + 0x140, 0x2200)

    put_str(0x100, "NSGeometry.m")
    put_str(0x110, "NSCoder")
    put_str(0x120, "NSGeometryCoding")
    put_str(0x140, "{?=ff}8@8:12")
    put_str(0x160, "decodePoint")
    return bytes(blob)


MODULE_SECTIONS = [
    {"name": "__OBJC,__module_info", "address": BASE, "size": 16, "offset": 0},
    {"name": "__OBJC,__blob", "address": BASE, "size": 0x300, "offset": 0},
]


def test_reads_a_module_with_a_category():
    from binrecon.objc_abi import read_modules_from_sections

    modules = read_modules_from_sections(build_module_blob(), MODULE_SECTIONS, "little")

    assert modules == {"NSGeometry.m": {
        "schema_version": "abi-v1",
        "module": "NSGeometry.m",
        "classes": [],
        "categories": [{
            "name": "NSGeometryCoding",
            "class": "NSCoder",
            "instance_methods": [
                {"selector": "decodePoint", "types": "{?=ff}8@8:12"}
            ],
            "class_methods": [],
        }],
        "text_symbols": [],
        "data_symbols": [],
    }}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests/test_objc_abi.py::test_reads_a_module_with_a_category -q`

Expected: FAIL with `ImportError: cannot import name 'read_modules_from_sections'`.

- [ ] **Step 3: Implement category and module extraction**

Append to `tools/binrecon/binrecon/objc_abi.py`:

```python
def read_categories(reader, symtab_address):
    """Return the category records an ``objc_symtab`` defines."""
    class_count, category_count = reader.halves(symtab_address + 8, 2)
    definitions = reader.at(symtab_address + 12, class_count + category_count)
    categories = []
    for pointer in definitions[class_count:]:
        category_name, class_name, instance_methods, class_methods = reader.at(
            pointer, 4
        )
        categories.append({
            "name": reader.cstring(category_name),
            "class": reader.cstring(class_name),
            "instance_methods": reader.method_list(instance_methods),
            "class_methods": reader.method_list(class_methods),
        })
    return categories


def read_modules_from_sections(payload, sections, endianness, method_names=None):
    """Return ``{module name: abi-v1 document}`` for an image's ``__OBJC``."""
    reader = ObjcReader(payload, sections, endianness, method_names)
    info = next(
        (s for s in sections if s["name"] == "__OBJC,__module_info" and s.get("size")),
        None,
    )
    if info is None:
        raise ObjcAbiError("image has no __OBJC,__module_info section")

    modules = {}
    for index in range(info["size"] // 16):
        address = info["address"] + 16 * index
        _version, _size, name, symtab = reader.at(address, 4)
        module = reader.cstring(name)
        if module in modules:
            raise ObjcAbiError(f"__module_info names {module} more than once")
        modules[module] = {
            "schema_version": "abi-v1",
            "module": module,
            "classes": read_classes(reader, symtab),
            "categories": read_categories(reader, symtab),
            "text_symbols": [],
            "data_symbols": [],
        }
    return modules


def read_modules(path):
    """Return ``{module name: abi-v1 document}`` for an image on disk."""
    from .macho import load_image

    payload, document = load_image(path)
    return read_modules_from_sections(
        payload, document["sections"], document["input"]["endianness"],
        method_symbol_index(document),
    )
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests/test_objc_abi.py -q`

Expected: PASS, 3 tests.

- [ ] **Step 5: Verify against the real reference**

```bash
PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -c "
from binrecon.objc_abi import read_modules
m = read_modules(r'C:\Users\raynorpat\Downloads\test\Foundation-i386')
print(len(m), 'modules')
g = m['NSGeometry.m']
print(g['classes'], len(g['categories']))
print(g['categories'][0]['name'], g['categories'][0]['class'])
print([x['selector'] for x in g['categories'][0]['instance_methods']])
print('NSString instance_size', [c['instance_size'] for c in m['NSString.m']['classes']])
"
```

Expected: `80 modules`; `[] 1`; `NSGeometryCoding NSCoder`; the six selectors
`encodePoint:`, `decodePoint`, `encodeSize:`, `decodeSize`, `encodeRect:`,
`decodeRect` in some order; and a non-empty instance-size list for `NSString.m`.

- [ ] **Step 6: Commit**

```bash
git add tools/binrecon/binrecon/objc_abi.py tools/binrecon/tests/test_objc_abi.py
git commit -m "binrecon: map Objective-C modules to their classes and categories"
```

---

### Task 6: Emit per-module ABI documents with `binrecon abi`

**Files:**
- Modify: `tools/binrecon/binrecon/objc_abi.py` (symbol attribution)
- Modify: `tools/binrecon/binrecon/cli.py` (register `abi`)
- Create: `tools/binrecon/binrecon/schema/abi-v1.json`
- Test: `tools/binrecon/tests/test_abi_cli.py` (create)

**Interfaces:**
- Consumes: `read_modules` from Task 5.
- Produces:
  - CLI `binrecon abi --profile P --module M [--module M ...] --symbols FILE --output DIR`.
  - `binrecon.objc_abi.attach_symbols(modules, assignment, symbols) -> None`, where `assignment` maps module name to a list of symbol names.
  - One `<Module without .m>.json` per requested module in `DIR`.

- [ ] **Step 1: Write the failing test**

Create `tools/binrecon/tests/test_abi_cli.py`:

```python
import json

from binrecon.objc_abi import attach_symbols


def test_attaches_symbols_by_declared_assignment():
    modules = {"NSRange.m": {
        "schema_version": "abi-v1", "module": "NSRange.m",
        "classes": [], "categories": [],
        "text_symbols": [], "data_symbols": [],
    }}
    symbols = [
        {"name": "_NSUnionRange", "address": 0x1000, "section": "__TEXT,__text"},
        {"name": "_NSZeroRect", "address": 0x2000, "section": "__DATA,__data"},
        {"name": "_NSStringFromRect", "address": 0x1040, "section": "__TEXT,__text"},
        {"name": "_undefined", "address": 0, "section": None},
    ]

    attach_symbols(modules, {"NSRange.m": ["_NSUnionRange", "_NSZeroRect"]}, symbols)

    assert modules["NSRange.m"]["text_symbols"] == ["_NSUnionRange"]
    assert modules["NSRange.m"]["data_symbols"] == ["_NSZeroRect"]


def test_unknown_symbol_is_an_error():
    import pytest
    from binrecon.objc_abi import ObjcAbiError

    modules = {"NSRange.m": {
        "schema_version": "abi-v1", "module": "NSRange.m",
        "classes": [], "categories": [],
        "text_symbols": [], "data_symbols": [],
    }}
    with pytest.raises(ObjcAbiError, match="_NSNope"):
        attach_symbols(modules, {"NSRange.m": ["_NSNope"]}, [])
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests/test_abi_cli.py -q`

Expected: FAIL with `ImportError: cannot import name 'attach_symbols'`.

- [ ] **Step 3: Implement symbol attachment**

Append to `tools/binrecon/binrecon/objc_abi.py`:

```python
def attach_symbols(modules, assignment, symbols):
    """Record each module's exported C symbols, split by segment.

    ``assignment`` maps a module name to the symbol names it owns. C functions
    carry no module attribution in the image (spec §2.1), so the assignment is
    declared from the module's public header rather than inferred.
    """
    by_name = {symbol["name"]: symbol for symbol in symbols}
    for module, names in assignment.items():
        if module not in modules:
            raise ObjcAbiError(f"assignment names unknown module {module}")
        text, data = [], []
        for name in names:
            symbol = by_name.get(name)
            if symbol is None:
                raise ObjcAbiError(f"image exports no symbol named {name}")
            section = symbol["section"]
            if section is None:
                raise ObjcAbiError(f"{name} is undefined in the image")
            bucket = text if section.startswith("__TEXT") else data
            bucket.append(name)
        modules[module]["text_symbols"] = sorted(text)
        modules[module]["data_symbols"] = sorted(data)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests/test_abi_cli.py -q`

Expected: PASS, 2 tests.

- [ ] **Step 5: Write the abi-v1 schema**

Create `tools/binrecon/binrecon/schema/abi-v1.json`:

```json
{
 "$schema": "https://json-schema.org/draft/2020-12/schema",
 "$id": "abi-v1.json",
 "title": "Objective-C ABI for one translation unit, version 1",
 "type": "object",
 "additionalProperties": false,
 "required": ["schema_version", "module", "classes", "categories",
              "text_symbols", "data_symbols"],
 "properties": {
  "schema_version": { "const": "abi-v1" },
  "module": { "type": "string" },
  "classes": { "type": "array", "items": { "$ref": "#/$defs/class" } },
  "categories": { "type": "array", "items": { "$ref": "#/$defs/category" } },
  "text_symbols": { "type": "array", "items": { "type": "string" } },
  "data_symbols": { "type": "array", "items": { "type": "string" } }
 },
 "$defs": {
  "method": {
   "type": "object",
   "additionalProperties": false,
   "required": ["selector", "types"],
   "properties": {
    "selector": { "type": "string" },
    "types": { "type": "string" }
   }
  },
  "ivar": {
   "type": "object",
   "additionalProperties": false,
   "required": ["name", "type", "offset"],
   "properties": {
    "name": { "type": "string" },
    "type": { "type": "string" },
    "offset": { "type": "integer", "minimum": 0 }
   }
  },
  "class": {
   "type": "object",
   "additionalProperties": false,
   "required": ["name", "superclass", "instance_size", "info", "ivars",
                "instance_methods", "class_methods"],
   "properties": {
    "name": { "type": "string" },
    "superclass": { "type": ["string", "null"] },
    "instance_size": { "type": "integer", "minimum": 0 },
    "info": { "type": "integer", "minimum": 0 },
    "ivars": { "type": "array", "items": { "$ref": "#/$defs/ivar" } },
    "instance_methods": { "type": "array", "items": { "$ref": "#/$defs/method" } },
    "class_methods": { "type": "array", "items": { "$ref": "#/$defs/method" } }
   }
  },
  "category": {
   "type": "object",
   "additionalProperties": false,
   "required": ["name", "class", "instance_methods", "class_methods"],
   "properties": {
    "name": { "type": "string" },
    "class": { "type": "string" },
    "instance_methods": { "type": "array", "items": { "$ref": "#/$defs/method" } },
    "class_methods": { "type": "array", "items": { "$ref": "#/$defs/method" } }
   }
  }
 }
}
```

- [ ] **Step 6: Register the CLI command**

In `tools/binrecon/binrecon/cli.py`, add `"abi"` to the `COMMANDS` tuple and
register the parser beside the others:

```python
    abi = subparsers.add_parser("abi")
    abi.add_argument("--profile", required=True)
    abi.add_argument("--module", action="append", required=True)
    abi.add_argument("--symbols", required=True)
    abi.add_argument("--output", required=True)
```

Add these to the existing import block at the top of `cli.py`:

```python
from binrecon.macho import load_image
from binrecon.objc_abi import (
    ObjcAbiError, attach_symbols, method_symbol_index, read_modules_from_sections,
)
```

`main` dispatches with inline `if args.command == ...` blocks, each wrapping its
work in a try/except that prints `binrecon: {error}` to stderr and returns 1.
`os`, `sys`, `json` and `Path` are already imported at module level. Follow that
shape — add this block beside the others:

```python
    if args.command == "abi":
        try:
            profile = load_profile(Path(args.profile), os.environ)
            payload, document = load_image(profile.reference.path)
            modules = read_modules_from_sections(
                payload, document["sections"], document["input"]["endianness"],
                method_symbol_index(document),
            )
            assignment = json.loads(Path(args.symbols).read_text())
            attach_symbols(modules, assignment, document["symbols"])

            output = Path(args.output)
            output.mkdir(parents=True, exist_ok=True)
            for module in args.module:
                if module not in modules:
                    raise ValueError(f"image defines no module {module}")
                target = output / (module.removesuffix(".m") + ".json")
                target.write_text(
                    json.dumps(modules[module], indent=1, sort_keys=True) + "\n"
                )
                print(f"wrote {target}")
            return 0
        except (OSError, ValueError, ValidationError, ObjcAbiError) as error:
            print(f"binrecon: {error}", file=sys.stderr)
            return 1
```

`read_macho` emits symbol records shaped
`{"name": str, "address": int, "binding": str, "section": str | None}`, where
`section` is the `"__SEG,__sect"` name for a defined symbol and `None` for an
undefined one. `attach_symbols` above relies on exactly that.

- [ ] **Step 7: Run the full suite**

Run: `PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests -q`

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add tools/binrecon/binrecon/objc_abi.py tools/binrecon/binrecon/cli.py tools/binrecon/binrecon/schema/abi-v1.json tools/binrecon/tests/test_abi_cli.py
git commit -m "binrecon: emit per-module Objective-C ABI documents"
```

---
### Task 7: Verify a build against committed ABI with `binrecon abi-check`

**Files:**
- Create: `tools/binrecon/binrecon/abi_check.py`
- Modify: `tools/binrecon/binrecon/cli.py`
- Test: `tools/binrecon/tests/test_abi_check.py` (create)

**Interfaces:**
- Consumes: `read_modules_from_sections` and `ObjcAbiError` from Task 5; `load_image` from Task 3.
- Produces:
  - `binrecon.abi_check.external_symbols(document) -> set[str]` — the names of every externally-visible defined symbol in a built object.
  - `binrecon.abi_check.module_from_object(payload, document, module) -> dict` — an `abi-v1` document describing one compiled object, tolerating objects with no Objective-C content.
  - `binrecon.abi_check.diff_abi(expected, actual) -> list[str]` — one line per divergence, empty when the two agree.
  - CLI `binrecon abi-check --abi-dir DIR --built MODULE=PATH [--built MODULE=PATH ...]`, exit 0 on agreement, 1 on any divergence.

Two things this task must get right, both of which an earlier draft got wrong:

**One `.o` is one translation unit,** so its external defined symbols *are* that
module's C symbols. They are compared for real. Do not copy the expected symbol
lists onto the actual document — that would make the check pass by construction.

**A compiled object may have no `__OBJC` segment at all.** `NSRange.m` and
`NSDecimal.m` define no classes or categories, so their objects carry no
`__module_info` section and `read_modules_from_sections` raises. With no
`__module_info` there is also no way to infer which module an object is, which is
why `--built` takes an explicit `MODULE=PATH` pair rather than a bare path.

**Symbol comparison is by name set, not by section.** The committed
`abi/<Module>.json` records `text_symbols` and `data_symbols` separately because
that is where Apple's linker put them, but whether a `const NSRect` lands in
`__DATA,__data` or `__TEXT,__const` is a codegen choice, not ABI. `diff_abi`
compares the union of the two lists against the object's external defined
symbols; it does not enforce the split.

- [ ] **Step 1: Write the failing tests**

Create `tools/binrecon/tests/test_abi_check.py`:

```python
import pytest

from binrecon.abi_check import diff_abi, external_symbols


def _module(**overrides):
    document = {
        "schema_version": "abi-v1",
        "module": "NSThing.m",
        "classes": [{
            "name": "NSThing",
            "superclass": "NSObject",
            "instance_size": 12,
            "info": 1,
            "ivars": [{"name": "_count", "type": "I", "offset": 4}],
            "instance_methods": [{"selector": "count", "types": "I8@8:12"}],
            "class_methods": [],
        }],
        "categories": [],
        "text_symbols": ["_NSThingHelper"],
        "data_symbols": ["_NSThingZero"],
    }
    document.update(overrides)
    return document


def test_identical_documents_agree():
    assert diff_abi(_module(), _module()) == []


def test_reports_a_changed_ivar_offset():
    actual = _module()
    actual["classes"][0]["ivars"][0]["offset"] = 8

    assert diff_abi(_module(), actual) == [
        "NSThing._count: offset expected 4, actual 8"
    ]


def test_reports_a_changed_instance_size():
    actual = _module()
    actual["classes"][0]["instance_size"] = 16

    assert diff_abi(_module(), actual) == [
        "NSThing: instance_size expected 12, actual 16"
    ]


def test_reports_a_missing_selector():
    actual = _module()
    actual["classes"][0]["instance_methods"] = []

    assert diff_abi(_module(), actual) == ["NSThing: missing instance method -count"]


def test_reports_a_changed_type_encoding():
    actual = _module()
    actual["classes"][0]["instance_methods"][0]["types"] = "i8@8:12"

    assert diff_abi(_module(), actual) == [
        "NSThing.-count: types expected I8@8:12, actual i8@8:12"
    ]


def test_reports_a_missing_c_symbol():
    actual = _module(text_symbols=[], data_symbols=["_NSThingZero"])

    assert diff_abi(_module(), actual) == [
        "NSThing.m: missing exported symbol _NSThingHelper"
    ]


def test_reports_an_unexpected_c_symbol():
    actual = _module(text_symbols=["_NSThingHelper", "_NSThingSurprise"])

    assert diff_abi(_module(), actual) == [
        "NSThing.m: unexpected exported symbol _NSThingSurprise"
    ]


def test_symbols_may_move_between_text_and_data():
    """Section placement of a constant is codegen, not ABI."""
    actual = _module(text_symbols=["_NSThingHelper", "_NSThingZero"],
                     data_symbols=[])

    assert diff_abi(_module(), actual) == []


def test_external_symbols_ignores_local_and_undefined():
    document = {"symbols": [
        {"name": "_public", "address": 0x1000, "binding": "external",
         "section": "__TEXT,__text"},
        {"name": "_helper", "address": 0x1040, "binding": "local",
         "section": "__TEXT,__text"},
        {"name": "_imported", "address": 0, "binding": "external",
         "section": None},
    ]}

    assert external_symbols(document) == {"_public"}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests/test_abi_check.py -q`

Expected: FAIL with `ModuleNotFoundError: No module named 'binrecon.abi_check'`.

- [ ] **Step 3: Implement the diff**

Create `tools/binrecon/binrecon/abi_check.py`:

```python
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
        wanted = {item["name"]: item for item in expected[key]}
        found = {item["name"]: item for item in actual[key]}
        for name in sorted(set(wanted) - set(found)):
            findings.append(f"{module}: missing {label} {name}")
        for name in sorted(set(found) - set(wanted)):
            findings.append(f"{module}: unexpected {label} {name}")
        for name in sorted(set(wanted) & set(found)):
            if key == "classes":
                _diff_class(findings, wanted[name], found[name])
            else:
                if wanted[name]["class"] != found[name]["class"]:
                    findings.append(
                        f"{module}: category {name} expected on "
                        f"{wanted[name]['class']}, actual {found[name]['class']}"
                    )
                owner = f"{found[name]['class']}({name})"
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests/test_abi_check.py -q`

Expected: PASS, 9 tests.

- [ ] **Step 5: Register the CLI command**

Add `"abi-check"` to `COMMANDS` and register the parser:

```python
    abi_check = subparsers.add_parser("abi-check")
    abi_check.add_argument("--abi-dir", required=True)
    abi_check.add_argument("--built", action="append", required=True,
                           metavar="MODULE=PATH")
```

Add to the import block:

```python
from binrecon.abi_check import diff_abi, module_from_object
```

Handler, in the same inline style as the others:

```python
    if args.command == "abi-check":
        try:
            built = {}
            for pair in args.built:
                module, separator, path = pair.partition("=")
                if not separator or not module or not path:
                    raise ValueError(
                        f"--built expects MODULE=PATH, got {pair!r}"
                    )
                payload, document = load_image(Path(path))
                built[module] = module_from_object(payload, document, module)

            findings = []
            for expected_path in sorted(Path(args.abi_dir).glob("*.json")):
                expected = json.loads(expected_path.read_text())
                actual = built.pop(expected["module"], None)
                if actual is None:
                    findings.append(
                        f"{expected['module']}: no --built object was supplied"
                    )
                    continue
                findings.extend(diff_abi(expected, actual))
            for module in sorted(built):
                findings.append(f"{module}: no committed ABI document to check")

            for line in findings:
                print(f"abi-check: {line}")
            if findings:
                print(f"abi-check: {len(findings)} divergence(s)")
                return 1
            print("abi-check: ABI matches")
            return 0
        except (OSError, ValueError, ValidationError, ObjcAbiError) as error:
            print(f"binrecon: {error}", file=sys.stderr)
            return 1
```

`ObjcAbiError` must be importable in `cli.py`; Task 6 already added it to the
import block.

- [ ] **Step 6: Run the full suite and commit**

Run: `PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests -q`

Expected: PASS.

```bash
git add tools/binrecon/binrecon/abi_check.py tools/binrecon/binrecon/cli.py tools/binrecon/tests/test_abi_check.py
git commit -m "binrecon: check a build's Objective-C ABI against committed evidence"
```
---

---

### Task 8: Generate a module's analysis scope

**Files:**
- Create: `tools/binrecon/binrecon/module_scope.py`
- Modify: `tools/binrecon/binrecon/cli.py`
- Test: `tools/binrecon/tests/test_module_scope.py` (create)

**Interfaces:**
- Consumes: `read_modules_from_sections` from Task 5; `load_image` from Task 3.
- Produces:
  - `binrecon.module_scope.function_ranges(symbols, text_section, names) -> list[dict]` returning sorted, non-overlapping `{"start", "end"}` records.
  - CLI `binrecon module-scope --profile P --module M [--module M ...] --symbols FILE`, printing the `analysis_scope` array as JSON.

- [ ] **Step 1: Write the failing tests**

Create `tools/binrecon/tests/test_module_scope.py`:

```python
import pytest

from binrecon.module_scope import function_ranges

TEXT = {"name": "__TEXT,__text", "address": 0x1000, "size": 0x100}
SYMBOLS = [
    {"name": "_alpha", "address": 0x1000, "section": "__TEXT,__text"},
    {"name": "_beta", "address": 0x1040, "section": "__TEXT,__text"},
    {"name": "_gamma", "address": 0x1080, "section": "__TEXT,__text"},
    {"name": "_data", "address": 0x2000, "section": "__DATA,__data"},
    {"name": "_undefined", "address": 0, "section": None},
]


def test_emits_one_range_per_named_function():
    assert function_ranges(SYMBOLS, TEXT, ["_alpha", "_gamma"]) == [
        {"start": 0x1000, "end": 0x1040},
        {"start": 0x1080, "end": 0x1100},
    ]


def test_ranges_are_sorted_regardless_of_request_order():
    assert function_ranges(SYMBOLS, TEXT, ["_gamma", "_alpha"])[0]["start"] == 0x1000


def test_a_symbol_outside_text_is_an_error():
    with pytest.raises(ValueError, match="_data"):
        function_ranges(SYMBOLS, TEXT, ["_data"])


def test_an_unknown_symbol_is_an_error():
    with pytest.raises(ValueError, match="_nope"):
        function_ranges(SYMBOLS, TEXT, ["_nope"])
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests/test_module_scope.py -q`

Expected: FAIL with `ModuleNotFoundError: No module named 'binrecon.module_scope'`.

- [ ] **Step 3: Implement range generation**

Create `tools/binrecon/binrecon/module_scope.py`:

```python
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
    # Aliased symbols share an address; collapse to one boundary per distinct
    # address so every alias gets the same non-empty extent rather than the
    # first one getting a zero-length range that analysis_scope would reject.
    addresses = sorted({value for value, _ in in_text})
    boundaries = addresses + [text_end]
    extent_by_address = {
        address: (address, boundaries[index + 1])
        for index, address in enumerate(addresses)
    }
    extent = {name: extent_by_address[value] for value, name in in_text}

    known = {symbol["name"] for symbol in symbols}
    ranges = []
    for name in names:
        if name not in extent:
            reason = "is not a function in __text" if name in known else "is not exported"
            raise ValueError(f"{name} {reason}")
        start, end = extent[name]
        ranges.append({"start": start, "end": end})
    return sorted(ranges, key=lambda item: item["start"])
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests/test_module_scope.py -q`

Expected: PASS, 4 tests.

- [ ] **Step 5: Register the CLI command**

Add `"module-scope"` to `COMMANDS` and:

```python
    module_scope = subparsers.add_parser("module-scope")
    module_scope.add_argument("--profile", required=True)
    module_scope.add_argument("--module", action="append", required=True)
    module_scope.add_argument("--symbols", required=True)
```

Add to the import block:

```python
from binrecon.module_scope import function_ranges
```

Handler — it collects the module's Objective-C method symbols from `__OBJC` and
its C function symbols from the declared assignment, then emits the ranges.
Data-only names in the assignment (`_NSZeroRect` and friends) are not functions
and are filtered out:

```python
    if args.command == "module-scope":
        try:
            profile = load_profile(Path(args.profile), os.environ)
            payload, document = load_image(profile.reference.path)
            modules = read_modules_from_sections(
                payload, document["sections"], document["input"]["endianness"],
                method_symbol_index(document),
            )
            assignment = json.loads(Path(args.symbols).read_text())
            text_names = {
                symbol["name"] for symbol in document["symbols"]
                if symbol["section"] == "__TEXT,__text"
            }

            names = []
            for module in args.module:
                if module not in modules:
                    raise ValueError(f"image defines no module {module}")
                names.extend(
                    name for name in assignment.get(module, []) if name in text_names
                )
                for item in modules[module]["classes"]:
                    for method in item["instance_methods"]:
                        names.append(f"-[{item['name']} {method['selector']}]")
                    for method in item["class_methods"]:
                        names.append(f"+[{item['name']} {method['selector']}]")
                for item in modules[module]["categories"]:
                    owner = f"{item['class']}({item['name']})"
                    for method in item["instance_methods"]:
                        names.append(f"-[{owner} {method['selector']}]")
                    for method in item["class_methods"]:
                        names.append(f"+[{owner} {method['selector']}]")

            text = next(
                s for s in document["sections"] if s["name"] == "__TEXT,__text"
            )
            ranges = function_ranges(document["symbols"], text, names)
            print(json.dumps(ranges, indent=1))
            print(f"# {len(ranges)} ranges", file=sys.stderr)
            return 0
        except (OSError, ValueError, ValidationError, ObjcAbiError) as error:
            print(f"binrecon: {error}", file=sys.stderr)
            return 1
```

- [ ] **Step 6: Run the full suite and commit**

Run: `PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests -q`

Expected: PASS.

```bash
git add tools/binrecon/binrecon/module_scope.py tools/binrecon/binrecon/cli.py tools/binrecon/tests/test_module_scope.py
git commit -m "binrecon: generate an analysis scope from Objective-C module membership"
```

---

### Task 9: Report source mapping per module

**Files:**
- Modify: `tools/binrecon/binrecon/source_map.py`
- Test: `tools/binrecon/tests/test_source_map.py`

**Interfaces:**
- Consumes: `read_modules_from_sections` from Task 5.
- Produces:
  - `binrecon.source_map.summarize_by_module(document, ownership) -> dict` mapping module name to a count per bucket.
  - `build_source_map(..., ownership=None)` gains a keyword argument; when given, the emitted document carries a `by_module` key. Existing bucket semantics and the four top-level bucket lists are unchanged.

`build_source_map` (`tools/binrecon/binrecon/source_map.py:222`) partitions
functions into four top-level lists — `mapped`, `unmapped`,
`duplicate_candidates`, `boundary_disputed` — whose entries carry
`{"address", "size", "reference_names": [...]}`. The summary reads those lists.

- [ ] **Step 1: Write the failing test**

Append to `tools/binrecon/tests/test_source_map.py`:

```python
def test_summarizes_buckets_by_owning_module():
    from binrecon.source_map import summarize_by_module

    document = {
        "mapped": [
            {"address": 1, "size": 4,
             "reference_names": ["-[NSCoder(NSGeometryCoding) decodePoint]"]},
            {"address": 2, "size": 4, "reference_names": ["_NSUnionRange"]},
        ],
        "unmapped": [
            {"address": 3, "size": 4,
             "reference_names": ["-[NSCoder(NSGeometryCoding) encodePoint:]"]},
            {"address": 4, "size": 4, "reference_names": ["_NSSomethingElse"]},
        ],
        "duplicate_candidates": [],
        "boundary_disputed": [],
    }
    ownership = {
        "-[NSCoder(NSGeometryCoding) decodePoint]": "NSGeometry.m",
        "-[NSCoder(NSGeometryCoding) encodePoint:]": "NSGeometry.m",
        "_NSUnionRange": "NSRange.m",
    }

    assert summarize_by_module(document, ownership) == {
        "NSGeometry.m": {"mapped": 1, "unmapped": 1,
                         "duplicate_candidates": 0, "boundary_disputed": 0},
        "NSRange.m": {"mapped": 1, "unmapped": 0,
                      "duplicate_candidates": 0, "boundary_disputed": 0},
    }
```

`_NSSomethingElse` has no owner and must not appear — that is the assertion
that the summary ignores functions outside the stage's modules.

- [ ] **Step 2: Run test to verify it fails**

Run: `PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests/test_source_map.py::test_summarizes_buckets_by_owning_module -q`

Expected: FAIL with `ImportError: cannot import name 'summarize_by_module'`.

- [ ] **Step 3: Implement the summary**

Add to `tools/binrecon/binrecon/source_map.py`, above `build_source_map`:

```python
_BUCKETS = ("mapped", "unmapped", "duplicate_candidates", "boundary_disputed")


def summarize_by_module(document, ownership):
    """Count each source-map bucket per owning translation unit.

    ``ownership`` maps a function name to its module, as proved by
    ``__OBJC,__module_info`` for methods and declared by header for C functions.
    Functions with no known owner are omitted rather than bucketed as unknown;
    the top-level lists already account for them.
    """
    summary = {}
    for bucket in _BUCKETS:
        for entry in document[bucket]:
            module = next(
                (ownership[name] for name in entry["reference_names"]
                 if name in ownership),
                None,
            )
            if module is None:
                continue
            counts = summary.setdefault(module, {name: 0 for name in _BUCKETS})
            counts[bucket] += 1
    return summary
```

- [ ] **Step 4: Wire it into the report**

Change `build_source_map`'s signature to accept the ownership map:

```python
def build_source_map(
    reference_analysis, macho_document, sites, *, disputed=None, extra_names=None,
    ownership=None,
):
```

and replace its final `return {...}` with:

```python
    document = {
        "schema_version": "source-map-v1",
        "reference_sha256": reference_analysis["input"]["sha256"].upper(),
        "mapped": _canonical(mapped),
        "unmapped": _canonical(unmapped),
        "duplicate_candidates": _canonical(duplicates),
        "boundary_disputed": _canonical(boundary),
    }
    if ownership:
        document["by_module"] = summarize_by_module(document, ownership)
    return document
```

Add `by_module` to `tools/binrecon/binrecon/schema/source-map-v1.json` as an
optional property:

```json
  "by_module": {
   "type": "object",
   "additionalProperties": {
    "type": "object",
    "additionalProperties": false,
    "required": ["mapped", "unmapped", "duplicate_candidates", "boundary_disputed"],
    "properties": {
     "mapped": { "$ref": "#/$defs/nonnegative_integer" },
     "unmapped": { "$ref": "#/$defs/nonnegative_integer" },
     "duplicate_candidates": { "$ref": "#/$defs/nonnegative_integer" },
     "boundary_disputed": { "$ref": "#/$defs/nonnegative_integer" }
    }
   }
  }
```

- [ ] **Step 5: Run the full suite and commit**

Run: `PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests -q`

Expected: PASS.

```bash
git add tools/binrecon/binrecon/source_map.py tools/binrecon/binrecon/schema/source-map-v1.json tools/binrecon/tests/test_source_map.py
git commit -m "binrecon: report source mapping per Objective-C module"
```

---

### Task 10: Analyse the reference

**Files:**
- Create: `tools/binrecon/profiles/foundation-i386.json`
- Create: `src/Kits/Foundation/reconstruction/symbols.json`
- Create: `docs/superpowers/plans/notes/2026-07-26-foundation-analysis-run.md`

**Interfaces:**
- Consumes: every binrecon change from Tasks 2–9.
- Produces: `tools/binrecon/out/foundation-i386/published/analysis-reference-ida.json`, the analysis of record for Tasks 12–15.

- [ ] **Step 1: Write the symbol assignment**

The 37 C symbols and 3 data symbols, assigned by the header that declares them.
Create `src/Kits/Foundation/reconstruction/symbols.json`:

```json
{
 "NSGeometry.m": [
  "_NSZeroPoint", "_NSZeroSize", "_NSZeroRect",
  "_NSEqualPoints", "_NSEqualSizes", "_NSEqualRects",
  "_NSIsEmptyRect", "_NSInsetRect", "_NSIntegralRect", "_NSUnionRect",
  "_NSIntersectionRect", "_NSIntersectsRect", "_NSContainsRect",
  "_NSDivideRect", "_NSOffsetRect", "_NSPointInRect", "_NSMouseInRect",
  "_NSStringFromPoint", "_NSStringFromSize", "_NSStringFromRect",
  "_NSPointFromString", "_NSSizeFromString", "_NSRectFromString"
 ],
 "NSRange.m": [
  "_NSUnionRange", "_NSIntersectionRange", "_NSIntersectsRange",
  "_NSStringFromRange", "_NSRangeFromString"
 ],
 "NSDecimal.m": [
  "_NSDecimalCopy", "_NSDecimalCompact", "_NSDecimalCompare",
  "_NSDecimalRound", "_NSDecimalNormalize", "_NSDecimalAdd",
  "_NSDecimalSubtract", "_NSDecimalMultiply", "_NSDecimalDivide",
  "_NSDecimalPower", "_NSDecimalMultiplyByPowerOf10", "_NSDecimalString"
 ]
}
```

`_NSIntersectsRange` is exported but declared in no public header; it is recorded
here and called out in Task 15's `divergences.md`.

- [ ] **Step 2: Write the profile without a scope**

Create `tools/binrecon/profiles/foundation-i386.json`:

```json
{
  "schema_version": "profile-v1",
  "name": "Foundation i386 reconstruction",
  "architecture": "i386",
  "endianness": "little",
  "reference": {
    "path": "${BINRECON_REFERENCE}",
    "expected_size": 1630488,
    "expected_sha256": "1165B9063ADD5672514455CA2C9830625BEA2BCE5E46126FB5E8652114C909D6"
  },
  "analyzers": {
    "ida": {
      "enabled": true,
      "executable": "C:/Program Files/IDA Professional 9.2/idat.exe",
      "timeout_seconds": 5400,
      "version": "9.2"
    },
    "ghidra": { "enabled": false },
    "angr": { "enabled": false }
  },
  "comparison": {
    "acceptance": "normalized-functions",
    "ignore_metadata": [],
    "entry_points": []
  },
  "output_dir": "../out/foundation-i386"
}
```

The reference is the **thin i386 slice** extracted in Task 3 Step 7, not the fat
container. `runner.py:312` requires the analyzer's reported input identity to
equal `profile.reference_identity`, so the profile and the analyzer must see the
same file — which is why the slice is materialized rather than sliced on the fly.

- [ ] **Step 3: Validate**

If Task 3's extraction is no longer on disk, redo it:

```bash
PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -m binrecon extract-slice --input "C:/Users/raynorpat/Downloads/test/DR2/Frameworks/Foundation.framework/Versions/C/Foundation" --architecture i386 --output "C:/Users/raynorpat/Downloads/test/Foundation-i386"
```

```bash
BINRECON_REFERENCE="C:/Users/raynorpat/Downloads/test/Foundation-i386" PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -m binrecon validate --profile tools/binrecon/profiles/foundation-i386.json
```

Expected: `reference ...Foundation-i386 size=1630488 sha256=1165B906...`. A
size or hash mismatch means `expected_sha256` in the profile disagrees with the
extracted slice — stop and reconcile.

- [ ] **Step 4: Generate the scope**

```bash
BINRECON_REFERENCE="C:/Users/raynorpat/Downloads/test/Foundation-i386" PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -m binrecon module-scope --profile tools/binrecon/profiles/foundation-i386.json --module NSGeometry.m --module NSRange.m --module NSDecimal.m --symbols src/Kits/Foundation/reconstruction/symbols.json
```

Expected: a JSON array and `# 43 ranges` on stderr. **If the count is not 43,
stop and reconcile against spec §3.7 before continuing** — a different count
means the symbol assignment or the category walk is wrong.

Paste the array into the profile as `"analysis_scope"`.

- [ ] **Step 5: Analyse, timing the run**

```bash
BINRECON_REFERENCE="C:/Users/raynorpat/Downloads/test/Foundation-i386" PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -m binrecon analyze --profile tools/binrecon/profiles/foundation-i386.json
```

Expected: `complete: true` and a populated `tools/binrecon/out/foundation-i386/published/`.

If it fails with `IDA output exceeds maximum JSON size`, **do not raise the
limit** (spec §1.4). Narrow to one module at a time by regenerating the scope
with a single `--module`, and record the split in Step 7's note.

- [ ] **Step 6: Confirm the export**

```bash
PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -c "
import json
d = json.load(open('tools/binrecon/out/foundation-i386/published/analysis-reference-ida.json'))
print(d['input']['sha256'])
print(len(d['functions']), 'functions')
"
```

Expected: `1165B9063ADD5672514455CA2C9830625BEA2BCE5E46126FB5E8652114C909D6` and 43 functions.

- [ ] **Step 7: Record the run and commit**

Write `docs/superpowers/plans/notes/2026-07-26-foundation-analysis-run.md` with
the wall-clock time, the published JSON size, the IDA version, and whether the
run needed splitting. Spec §5.5 wants this so later stages can size their groups
from data.

```bash
git add tools/binrecon/profiles/foundation-i386.json src/Kits/Foundation/reconstruction/symbols.json docs/superpowers/plans/notes/2026-07-26-foundation-analysis-run.md
git commit -m "binrecon: add the Foundation i386 profile and record the stage 1 analysis run"
```

---

### Task 11: Commit the ABI baseline

**Files:**
- Create: `src/Kits/Foundation/reconstruction/abi/NSGeometry.json`, `NSRange.json`, `NSDecimal.json`

**Interfaces:**
- Consumes: `binrecon abi` from Task 6; `symbols.json` from Task 10.
- Produces: the committed ABI evidence that Task 15's `abi-check` runs against.

- [ ] **Step 1: Emit the three documents**

```bash
BINRECON_REFERENCE="C:/Users/raynorpat/Downloads/test/Foundation-i386" PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -m binrecon abi --profile tools/binrecon/profiles/foundation-i386.json --module NSGeometry.m --module NSRange.m --module NSDecimal.m --symbols src/Kits/Foundation/reconstruction/symbols.json --output src/Kits/Foundation/reconstruction/abi
```

- [ ] **Step 2: Verify the contents against the spec**

```bash
PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -c "
import json, pathlib
for name in ('NSGeometry', 'NSRange', 'NSDecimal'):
    d = json.loads(pathlib.Path(f'src/Kits/Foundation/reconstruction/abi/{name}.json').read_text())
    print(name, 'classes', len(d['classes']), 'categories', len(d['categories']),
          'text', len(d['text_symbols']), 'data', len(d['data_symbols']))
    for c in d['categories']:
        print('  ', c['class'], c['name'], sorted(m['selector'] for m in c['instance_methods']))
"
```

Expected, matching spec §3.7 and §4 item 3:

```
NSGeometry classes 0 categories 1 text 20 data 3
   NSCoder NSGeometryCoding ['decodePoint', 'decodeRect', 'decodeSize', 'encodePoint:', 'encodeRect:', 'encodeSize:']
NSRange classes 0 categories 0 text 5 data 0
NSDecimal classes 0 categories 0 text 12 data 0
```

If any count differs, stop and reconcile — the ABI baseline is what every later
gate is measured against.

Then validate all three against the schema written in Task 6:

```bash
PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -c "
import json, pathlib, jsonschema
schema = json.loads(pathlib.Path('tools/binrecon/binrecon/schema/abi-v1.json').read_text())
for path in sorted(pathlib.Path('src/Kits/Foundation/reconstruction/abi').glob('*.json')):
    jsonschema.validate(json.loads(path.read_text()), schema)
    print('ok', path.name)
"
```

Expected: three `ok` lines and no exception.

- [ ] **Step 3: Commit**

```bash
git add src/Kits/Foundation/reconstruction/abi
git commit -m "Foundation: record the ABI baseline for NSGeometry, NSRange and NSDecimal"
```

---

### Task 12: Reconstruct NSDecimal.m

The largest of the three at 4,356 bytes across 12 functions, and the only one
with substantial algorithmic content. Eleven are behaviourally testable now;
`NSDecimalString` is deferred to stage 3.

**Files:**
- Modify: `src/Kits/Foundation/NSDecimal.m`
- Create: `src/Kits/Foundation/reconstruction/tests/test_decimal.c`

**Interfaces:**
- Consumes: the analysis from Task 10; declarations in `src/Kits/Foundation/NSDecimal.h` (do not modify).
- Produces: definitions for `NSDecimalCopy`, `NSDecimalCompact`, `NSDecimalCompare`, `NSDecimalRound`, `NSDecimalNormalize`, `NSDecimalAdd`, `NSDecimalSubtract`, `NSDecimalMultiply`, `NSDecimalDivide`, `NSDecimalPower`, `NSDecimalMultiplyByPowerOf10`, `NSDecimalString`, with exactly the signatures in `NSDecimal.h`.

- [ ] **Step 1: Write the failing tests**

`NSDecimal` is `{signed exponent:8; unsigned length:4; unsigned isNegative:1;
unsigned isCompact:1; unsigned reserved:18; unsigned short mantissa[8]}` — a
base-10000 little-endian mantissa scaled by `10^exponent`. A `length` of 0 with
`isNegative` set is NaN.

Create `src/Kits/Foundation/reconstruction/tests/test_decimal.c`:

```c
/*  Behavioural tests for NSDecimal.m, stage 1 of the Foundation
    reconstruction. Covers the 11 NSDecimal functions that do not touch
    NSString; NSDecimalString is deferred to stage 3.  */

#import <Foundation/NSDecimal.h>
#include <stdio.h>
#include <string.h>

static int failures = 0;

#define CHECK(condition) \
    do { \
        if (!(condition)) { \
            printf("FAIL %s:%d %s\n", __FILE__, __LINE__, #condition); \
            failures++; \
        } \
    } while (0)

/*  Build a decimal from a base-10000 mantissa, most significant word last.  */
static NSDecimal make(int negative, int exponent, int length,
                      unsigned short w0, unsigned short w1)
{
    NSDecimal d;
    memset(&d, 0, sizeof(d));
    d._isNegative = negative;
    d._exponent = exponent;
    d._length = length;
    d._mantissa[0] = w0;
    d._mantissa[1] = w1;
    return d;
}

static NSDecimal nan_value(void)
{
    NSDecimal d;
    memset(&d, 0, sizeof(d));
    d._length = 0;
    d._isNegative = 1;
    return d;
}

static void test_copy(void)
{
    NSDecimal source = make(0, -2, 1, 1234, 0), target;
    NSDecimalCopy(&target, &source);
    CHECK(memcmp(&target, &source, sizeof(NSDecimal)) == 0);
}

static void test_compare(void)
{
    NSDecimal one = make(0, 0, 1, 1, 0);
    NSDecimal two = make(0, 0, 1, 2, 0);
    NSDecimal minus_one = make(1, 0, 1, 1, 0);

    CHECK(NSDecimalCompare(&one, &two) == NSOrderedAscending);
    CHECK(NSDecimalCompare(&two, &one) == NSOrderedDescending);
    CHECK(NSDecimalCompare(&one, &one) == NSOrderedSame);
    CHECK(NSDecimalCompare(&minus_one, &one) == NSOrderedAscending);
}

static void test_compare_across_exponents(void)
{
    /*  100 * 10^0  ==  1 * 10^2  */
    NSDecimal a = make(0, 0, 1, 100, 0);
    NSDecimal b = make(0, 2, 1, 1, 0);
    CHECK(NSDecimalCompare(&a, &b) == NSOrderedSame);
}

static void test_compact_removes_trailing_zero_words(void)
{
    NSDecimal d = make(0, 0, 2, 5, 0);
    NSDecimalCompact(&d);
    CHECK(d._length == 1);
    CHECK(d._isCompact != 0);
}

static void test_add(void)
{
    NSDecimal a = make(0, 0, 1, 2, 0), b = make(0, 0, 1, 3, 0), r;
    CHECK(NSDecimalAdd(&r, &a, &b, NSRoundPlain) == NSCalculationNoError);
    CHECK(r._length == 1 && r._mantissa[0] == 5 && r._isNegative == 0);
}

static void test_add_with_differing_exponents(void)
{
    /*  1 * 10^2 + 5 * 10^0 == 105  */
    NSDecimal a = make(0, 2, 1, 1, 0), b = make(0, 0, 1, 5, 0), r;
    CHECK(NSDecimalAdd(&r, &a, &b, NSRoundPlain) == NSCalculationNoError);

    NSDecimal expected = make(0, 0, 1, 105, 0);
    CHECK(NSDecimalCompare(&r, &expected) == NSOrderedSame);
}

static void test_subtract(void)
{
    NSDecimal a = make(0, 0, 1, 3, 0), b = make(0, 0, 1, 5, 0), r;
    CHECK(NSDecimalSubtract(&r, &a, &b, NSRoundPlain) == NSCalculationNoError);
    CHECK(r._isNegative == 1 && r._mantissa[0] == 2);
}

static void test_subtract_to_zero(void)
{
    NSDecimal a = make(0, 0, 1, 7, 0), r;
    CHECK(NSDecimalSubtract(&r, &a, &a, NSRoundPlain) == NSCalculationNoError);
    CHECK(r._length == 0 && r._isNegative == 0);
}

static void test_multiply(void)
{
    NSDecimal a = make(0, 0, 1, 6, 0), b = make(0, 0, 1, 7, 0), r;
    CHECK(NSDecimalMultiply(&r, &a, &b, NSRoundPlain) == NSCalculationNoError);
    CHECK(r._mantissa[0] == 42);
}

static void test_multiply_adds_exponents(void)
{
    NSDecimal a = make(0, 2, 1, 3, 0), b = make(0, 3, 1, 2, 0), r;
    CHECK(NSDecimalMultiply(&r, &a, &b, NSRoundPlain) == NSCalculationNoError);
    CHECK(r._exponent == 5 && r._mantissa[0] == 6);
}

static void test_multiply_by_negative(void)
{
    NSDecimal a = make(0, 0, 1, 4, 0), b = make(1, 0, 1, 5, 0), r;
    CHECK(NSDecimalMultiply(&r, &a, &b, NSRoundPlain) == NSCalculationNoError);
    CHECK(r._isNegative == 1 && r._mantissa[0] == 20);
}

static void test_divide(void)
{
    NSDecimal a = make(0, 0, 1, 42, 0), b = make(0, 0, 1, 6, 0), r;
    CHECK(NSDecimalDivide(&r, &a, &b, NSRoundPlain) == NSCalculationNoError);

    NSDecimal expected = make(0, 0, 1, 7, 0);
    CHECK(NSDecimalCompare(&r, &expected) == NSOrderedSame);
}

static void test_divide_by_zero(void)
{
    NSDecimal a = make(0, 0, 1, 1, 0), zero = make(0, 0, 0, 0, 0), r;
    CHECK(NSDecimalDivide(&r, &a, &zero, NSRoundPlain) == NSCalculationDivideByZero);
    CHECK(NSDecimalIsNotANumber(&r));
}

static void test_nan_propagates(void)
{
    NSDecimal a = make(0, 0, 1, 1, 0), bad = nan_value(), r;
    NSDecimalAdd(&r, &a, &bad, NSRoundPlain);
    CHECK(NSDecimalIsNotANumber(&r));
}

static void test_power(void)
{
    NSDecimal base = make(0, 0, 1, 3, 0), r;
    CHECK(NSDecimalPower(&r, &base, 4, NSRoundPlain) == NSCalculationNoError);
    CHECK(r._mantissa[0] == 81);
}

static void test_power_of_zero_is_one(void)
{
    NSDecimal base = make(0, 0, 1, 9, 0), r;
    CHECK(NSDecimalPower(&r, &base, 0, NSRoundPlain) == NSCalculationNoError);

    NSDecimal one = make(0, 0, 1, 1, 0);
    CHECK(NSDecimalCompare(&r, &one) == NSOrderedSame);
}

static void test_multiply_by_power_of_10(void)
{
    NSDecimal n = make(0, 0, 1, 5, 0), r;
    CHECK(NSDecimalMultiplyByPowerOf10(&r, &n, 3, NSRoundPlain) == NSCalculationNoError);
    CHECK(r._exponent == 3 && r._mantissa[0] == 5);

    CHECK(NSDecimalMultiplyByPowerOf10(&r, &n, -2, NSRoundPlain) == NSCalculationNoError);
    CHECK(r._exponent == -2 && r._mantissa[0] == 5);
}

static void test_normalize_aligns_exponents(void)
{
    NSDecimal a = make(0, 2, 1, 1, 0), b = make(0, 0, 1, 5, 0);
    CHECK(NSDecimalNormalize(&a, &b, NSRoundPlain) == NSCalculationNoError);
    CHECK(a._exponent == b._exponent);

    NSDecimal hundred = make(0, 0, 1, 100, 0);
    CHECK(NSDecimalCompare(&a, &hundred) == NSOrderedSame);
}

static void test_round_down_truncates(void)
{
    /*  1.27 rounded to 1 place: Down -> 1.2, Up -> 1.3 (header's table)  */
    NSDecimal value = make(0, -2, 1, 127, 0), r;

    NSDecimalRound(&r, &value, 1, NSRoundDown);
    NSDecimal expected_down = make(0, -1, 1, 12, 0);
    CHECK(NSDecimalCompare(&r, &expected_down) == NSOrderedSame);

    NSDecimalRound(&r, &value, 1, NSRoundUp);
    NSDecimal expected_up = make(0, -1, 1, 13, 0);
    CHECK(NSDecimalCompare(&r, &expected_up) == NSOrderedSame);
}

static void test_round_plain_and_bankers_on_a_tie(void)
{
    /*  Header's table: 1.25 -> Plain 1.3, Bankers 1.2
                        1.35 -> Plain 1.4, Bankers 1.4  */
    NSDecimal quarter = make(0, -2, 1, 125, 0);
    NSDecimal three_five = make(0, -2, 1, 135, 0);
    NSDecimal r, expected;

    NSDecimalRound(&r, &quarter, 1, NSRoundPlain);
    expected = make(0, -1, 1, 13, 0);
    CHECK(NSDecimalCompare(&r, &expected) == NSOrderedSame);

    NSDecimalRound(&r, &quarter, 1, NSRoundBankers);
    expected = make(0, -1, 1, 12, 0);
    CHECK(NSDecimalCompare(&r, &expected) == NSOrderedSame);

    NSDecimalRound(&r, &three_five, 1, NSRoundBankers);
    expected = make(0, -1, 1, 14, 0);
    CHECK(NSDecimalCompare(&r, &expected) == NSOrderedSame);
}

static void test_round_in_place(void)
{
    /*  The header promises result may alias number.  */
    NSDecimal value = make(0, -2, 1, 127, 0);
    NSDecimalRound(&value, &value, 1, NSRoundDown);

    NSDecimal expected = make(0, -1, 1, 12, 0);
    CHECK(NSDecimalCompare(&value, &expected) == NSOrderedSame);
}

static void test_add_in_place(void)
{
    /*  The header promises result may alias either operand.  */
    NSDecimal a = make(0, 0, 1, 2, 0), b = make(0, 0, 1, 3, 0);
    CHECK(NSDecimalAdd(&a, &a, &b, NSRoundPlain) == NSCalculationNoError);
    CHECK(a._mantissa[0] == 5);
}

int main(void)
{
    test_copy();
    test_compare();
    test_compare_across_exponents();
    test_compact_removes_trailing_zero_words();
    test_add();
    test_add_with_differing_exponents();
    test_subtract();
    test_subtract_to_zero();
    test_multiply();
    test_multiply_adds_exponents();
    test_multiply_by_negative();
    test_divide();
    test_divide_by_zero();
    test_nan_propagates();
    test_power();
    test_power_of_zero_is_one();
    test_multiply_by_power_of_10();
    test_normalize_aligns_exponents();
    test_round_down_truncates();
    test_round_plain_and_bankers_on_a_tie();
    test_round_in_place();
    test_add_in_place();

    printf("%s: %d failure(s)\n", failures ? "FAILED" : "PASSED", failures);
    return failures != 0;
}
```

- [ ] **Step 2: Run the tests to verify they fail**

In the guest, using the invocation recorded in Task 1:

```bash
cc -I src/Kits/Foundation -o /tmp/test_decimal src/Kits/Foundation/reconstruction/tests/test_decimal.c src/Kits/Foundation/NSDecimal.m && /tmp/test_decimal
```

Expected: FAILED with a large failure count — the stub returns nothing useful.

- [ ] **Step 3: Read the reference implementations**

The analysis document carries disassembly, not decompiled C: each function record
is `{"address", "size", "names": [...], "blocks", "instructions", "calls",
"confidence"}`, and each instruction is `{"address", "bytes", "mnemonic",
"operands", "normalized_operands", "relocations"}`.

Create `src/Kits/Foundation/reconstruction/tests/dump.py` — Tasks 13 and 14
reuse it:

```python
"""Print the reference disassembly for functions whose name matches a prefix.

Usage: dump.py PREFIX [PREFIX ...]
"""

import json
import sys

ANALYSIS = "tools/binrecon/out/foundation-i386/published/analysis-reference-ida.json"

prefixes = tuple(sys.argv[1:])
document = json.load(open(ANALYSIS))
for function in sorted(document["functions"], key=lambda f: f["address"]):
    names = function["names"]
    if not any(name.startswith(prefixes) for name in names):
        continue
    print("=" * 70)
    print(f"{', '.join(names)}  @ {function['address']:#x}  {function['size']} bytes")
    for instruction in function["instructions"]:
        print(f"  {instruction['address']:#010x}  "
              f"{instruction['mnemonic']:<8} {instruction['operands']}")
```

Then:

```bash
PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe src/Kits/Foundation/reconstruction/tests/dump.py _NSDecimal
```

For pseudocode rather than disassembly, open the slice in IDA at the addresses
this prints. The analysis JSON is the artifact of record for what the reference
*is*; IDA's decompiler is a convenience for reading it.

- [ ] **Step 4: Write the implementations**

Replace the body of `src/Kits/Foundation/NSDecimal.m`. Keep the existing Apple
copyright header. Signatures must match `NSDecimal.h` exactly.

Reconstruct each function from the behaviour the decompilation shows, written in
the idiom of the header. Per the Global Constraints, no decompiler identifiers
survive into the committed source: name the working variables for what they
hold (`carry`, `borrow`, `shift`, `words`), not `v3` or `param_1`.

Leave `NSDecimalString` returning a correct `NSString` construction even though
it cannot be tested until stage 3 — do not stub it.

- [ ] **Step 5: Run the tests until they pass**

```bash
cc -I src/Kits/Foundation -o /tmp/test_decimal src/Kits/Foundation/reconstruction/tests/test_decimal.c src/Kits/Foundation/NSDecimal.m && /tmp/test_decimal
```

Expected: `PASSED: 0 failure(s)`.

If a test disagrees with the reference's actual behaviour, the *test* is what
changes — the reference is the authority. Record any such correction in Task 15's
`divergences.md` so the reasoning is reviewable.

- [ ] **Step 6: Commit**

```bash
git add src/Kits/Foundation/NSDecimal.m src/Kits/Foundation/reconstruction/tests/test_decimal.c src/Kits/Foundation/reconstruction/tests/dump.py
git commit -m "Foundation: reconstruct NSDecimal arithmetic against the DR2 reference"
```

---

### Task 13: Reconstruct NSGeometry.m

20 C functions and the six `NSCoder (NSGeometryCoding)` category methods, 3,792
bytes. Fourteen C functions are testable now; six string converters wait for
stage 3 and the six category methods wait for stage 2.

**Files:**
- Modify: `src/Kits/Foundation/NSGeometry.m`
- Create: `src/Kits/Foundation/reconstruction/tests/test_geometry.c`

**Interfaces:**
- Consumes: the analysis from Task 10; declarations in `src/Kits/Foundation/NSGeometry.h` (do not modify).
- Produces: the 20 functions and 3 constants named in `symbols.json` under `NSGeometry.m`, plus `@implementation NSCoder (NSGeometryCoding)`.

- [ ] **Step 1: Write the failing tests**

Create `src/Kits/Foundation/reconstruction/tests/test_geometry.c`:

```c
/*  Behavioural tests for NSGeometry.m, stage 1 of the Foundation
    reconstruction. Covers the 14 functions that do not touch NSString;
    the six string converters are deferred to stage 3, and the
    NSGeometryCoding category to stage 2.  */

#import <Foundation/NSGeometry.h>
#include <stdio.h>

static int failures = 0;

#define CHECK(condition) \
    do { \
        if (!(condition)) { \
            printf("FAIL %s:%d %s\n", __FILE__, __LINE__, #condition); \
            failures++; \
        } \
    } while (0)

#define CHECK_RECT(r, x, y, w, h) \
    CHECK((r).origin.x == (x) && (r).origin.y == (y) && \
          (r).size.width == (w) && (r).size.height == (h))

static void test_zero_constants(void)
{
    CHECK(NSZeroPoint.x == 0.0 && NSZeroPoint.y == 0.0);
    CHECK(NSZeroSize.width == 0.0 && NSZeroSize.height == 0.0);
    CHECK_RECT(NSZeroRect, 0.0, 0.0, 0.0, 0.0);
}

static void test_equality(void)
{
    CHECK(NSEqualPoints(NSMakePoint(1, 2), NSMakePoint(1, 2)));
    CHECK(!NSEqualPoints(NSMakePoint(1, 2), NSMakePoint(2, 1)));
    CHECK(NSEqualSizes(NSMakeSize(3, 4), NSMakeSize(3, 4)));
    CHECK(!NSEqualSizes(NSMakeSize(3, 4), NSMakeSize(4, 3)));
    CHECK(NSEqualRects(NSMakeRect(1, 2, 3, 4), NSMakeRect(1, 2, 3, 4)));
    CHECK(!NSEqualRects(NSMakeRect(1, 2, 3, 4), NSMakeRect(1, 2, 3, 5)));
}

static void test_is_empty_rect(void)
{
    CHECK(NSIsEmptyRect(NSMakeRect(0, 0, 0, 10)));
    CHECK(NSIsEmptyRect(NSMakeRect(0, 0, 10, 0)));
    CHECK(!NSIsEmptyRect(NSMakeRect(0, 0, 1, 1)));
}

static void test_inset_rect(void)
{
    NSRect r = NSInsetRect(NSMakeRect(0, 0, 10, 10), 2, 3);
    CHECK_RECT(r, 2.0, 3.0, 6.0, 4.0);
}

static void test_offset_rect(void)
{
    NSRect r = NSOffsetRect(NSMakeRect(1, 2, 10, 10), 3, 4);
    CHECK_RECT(r, 4.0, 6.0, 10.0, 10.0);
}

static void test_integral_rect(void)
{
    NSRect r = NSIntegralRect(NSMakeRect(1.5, 2.4, 3.1, 4.8));
    /*  Integral: origin floors outward, corner ceils outward.  */
    CHECK_RECT(r, 1.0, 2.0, 4.0, 6.0);

    CHECK(NSIsEmptyRect(NSIntegralRect(NSMakeRect(1, 1, 0, 5))));
}

static void test_union_rect(void)
{
    NSRect r = NSUnionRect(NSMakeRect(0, 0, 2, 2), NSMakeRect(4, 4, 2, 2));
    CHECK_RECT(r, 0.0, 0.0, 6.0, 6.0);
}

static void test_union_rect_with_empty(void)
{
    NSRect solid = NSMakeRect(1, 2, 3, 4);
    CHECK(NSEqualRects(NSUnionRect(solid, NSZeroRect), solid));
    CHECK(NSEqualRects(NSUnionRect(NSZeroRect, solid), solid));
}

static void test_intersection_rect(void)
{
    NSRect r = NSIntersectionRect(NSMakeRect(0, 0, 4, 4), NSMakeRect(2, 2, 4, 4));
    CHECK_RECT(r, 2.0, 2.0, 2.0, 2.0);

    CHECK(NSIsEmptyRect(
        NSIntersectionRect(NSMakeRect(0, 0, 1, 1), NSMakeRect(5, 5, 1, 1))));
}

static void test_intersects_rect(void)
{
    CHECK(NSIntersectsRect(NSMakeRect(0, 0, 4, 4), NSMakeRect(2, 2, 4, 4)));
    CHECK(!NSIntersectsRect(NSMakeRect(0, 0, 1, 1), NSMakeRect(5, 5, 1, 1)));
    /*  Edge contact is not intersection.  */
    CHECK(!NSIntersectsRect(NSMakeRect(0, 0, 1, 1), NSMakeRect(1, 0, 1, 1)));
}

static void test_contains_rect(void)
{
    CHECK(NSContainsRect(NSMakeRect(0, 0, 10, 10), NSMakeRect(2, 2, 3, 3)));
    CHECK(!NSContainsRect(NSMakeRect(0, 0, 4, 4), NSMakeRect(2, 2, 4, 4)));
    CHECK(NSContainsRect(NSMakeRect(0, 0, 4, 4), NSMakeRect(0, 0, 4, 4)));
}

static void test_point_in_rect(void)
{
    NSRect r = NSMakeRect(0, 0, 4, 4);
    CHECK(NSPointInRect(NSMakePoint(2, 2), r));
    CHECK(!NSPointInRect(NSMakePoint(5, 2), r));
    CHECK(NSPointInRect(NSMakePoint(0, 0), r));
}

static void test_mouse_in_rect(void)
{
    /*  NSMouseInRect is flipped-aware; on the lower edge it differs from
        NSPointInRect for a non-flipped rect.  */
    NSRect r = NSMakeRect(0, 0, 4, 4);
    CHECK(NSMouseInRect(NSMakePoint(2, 2), r, NO));
    CHECK(!NSMouseInRect(NSMakePoint(9, 9), r, NO));
}

static void test_divide_rect(void)
{
    NSRect slice, remainder;
    NSDivideRect(NSMakeRect(0, 0, 10, 10), &slice, &remainder, 3, NSMinXEdge);
    CHECK_RECT(slice, 0.0, 0.0, 3.0, 10.0);
    CHECK_RECT(remainder, 3.0, 0.0, 7.0, 10.0);

    NSDivideRect(NSMakeRect(0, 0, 10, 10), &slice, &remainder, 4, NSMinYEdge);
    CHECK_RECT(slice, 0.0, 0.0, 10.0, 4.0);
    CHECK_RECT(remainder, 0.0, 4.0, 10.0, 6.0);
}

static void test_divide_rect_beyond_extent(void)
{
    NSRect slice, remainder;
    NSDivideRect(NSMakeRect(0, 0, 10, 10), &slice, &remainder, 20, NSMinXEdge);
    CHECK_RECT(slice, 0.0, 0.0, 10.0, 10.0);
    CHECK(NSIsEmptyRect(remainder));
}

int main(void)
{
    test_zero_constants();
    test_equality();
    test_is_empty_rect();
    test_inset_rect();
    test_offset_rect();
    test_integral_rect();
    test_union_rect();
    test_union_rect_with_empty();
    test_intersection_rect();
    test_intersects_rect();
    test_contains_rect();
    test_point_in_rect();
    test_mouse_in_rect();
    test_divide_rect();
    test_divide_rect_beyond_extent();

    printf("%s: %d failure(s)\n", failures ? "FAILED" : "PASSED", failures);
    return failures != 0;
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cc -I src/Kits/Foundation -o /tmp/test_geometry src/Kits/Foundation/reconstruction/tests/test_geometry.c src/Kits/Foundation/NSGeometry.m && /tmp/test_geometry
```

Expected: FAILED.

- [ ] **Step 3: Read the reference implementations**

Using `dump.py` from Task 12:

```bash
PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe src/Kits/Foundation/reconstruction/tests/dump.py _NSEqual _NSIsEmpty _NSInset _NSIntegral _NSUnionRect _NSIntersectionRect _NSIntersectsRect _NSContains _NSDivide _NSOffset _NSPointIn _NSMouseIn _NSStringFromPoint _NSStringFromSize _NSStringFromRect _NSPointFrom _NSSizeFrom _NSRectFrom '-[NSCoder'
```

Pay particular attention to `NSIntegralRect`'s rounding direction and
`NSMouseInRect`'s flipped handling — both have behaviour the tests above assert
from documented convention, and the reference is the authority if they disagree.

- [ ] **Step 4: Write the implementations**

Replace the body of `src/Kits/Foundation/NSGeometry.m`, keeping the Apple
copyright header. It must define:

- the three constants `NSZeroPoint`, `NSZeroSize`, `NSZeroRect`;
- the 20 out-of-line functions from `symbols.json`;
- `@implementation NSCoder (NSGeometryCoding)` with `encodePoint:`,
  `decodePoint`, `encodeSize:`, `decodeSize`, `encodeRect:` and `decodeRect`,
  each driving `NSCoder`'s `encodeValueOfObjCType:at:` /
  `decodeValueOfObjCType:at:` as the reference does.

The category compiles against `NSCoder.h` without `NSCoder` being implemented,
which is what makes it stage 1's ABI surface. Do not stub its methods.

- [ ] **Step 5: Run the tests until they pass**

```bash
cc -I src/Kits/Foundation -o /tmp/test_geometry src/Kits/Foundation/reconstruction/tests/test_geometry.c src/Kits/Foundation/NSGeometry.m && /tmp/test_geometry
```

Expected: `PASSED: 0 failure(s)`.

- [ ] **Step 6: Commit**

```bash
git add src/Kits/Foundation/NSGeometry.m src/Kits/Foundation/reconstruction/tests/test_geometry.c
git commit -m "Foundation: reconstruct NSGeometry against the DR2 reference"
```

---

### Task 14: Reconstruct NSRange.m

The smallest module — 5 functions, 636 bytes, of which 3 are testable now.

**Files:**
- Modify: `src/Kits/Foundation/NSRange.m`
- Create: `src/Kits/Foundation/reconstruction/tests/test_range.c`

**Interfaces:**
- Consumes: the analysis from Task 10; declarations in `src/Kits/Foundation/NSRange.h` (do not modify).
- Produces: `NSUnionRange`, `NSIntersectionRange`, `NSIntersectsRange`, `NSStringFromRange`, `NSRangeFromString`.

- [ ] **Step 1: Write the failing tests**

Create `src/Kits/Foundation/reconstruction/tests/test_range.c`:

```c
/*  Behavioural tests for NSRange.m, stage 1 of the Foundation reconstruction.
    NSStringFromRange and NSRangeFromString are deferred to stage 3.  */

#import <Foundation/NSRange.h>
#include <stdio.h>

/*  Exported by NSRange.m but declared in no public header; see
    reconstruction/divergences.md.  */
extern BOOL NSIntersectsRange(NSRange range1, NSRange range2);

static int failures = 0;

#define CHECK(condition) \
    do { \
        if (!(condition)) { \
            printf("FAIL %s:%d %s\n", __FILE__, __LINE__, #condition); \
            failures++; \
        } \
    } while (0)

#define CHECK_RANGE(r, loc, len) \
    CHECK((r).location == (unsigned)(loc) && (r).length == (unsigned)(len))

static void test_union_range(void)
{
    CHECK_RANGE(NSUnionRange(NSMakeRange(0, 2), NSMakeRange(5, 3)), 0, 8);
    CHECK_RANGE(NSUnionRange(NSMakeRange(5, 3), NSMakeRange(0, 2)), 0, 8);
    CHECK_RANGE(NSUnionRange(NSMakeRange(0, 10), NSMakeRange(2, 3)), 0, 10);
}

static void test_union_range_with_empty(void)
{
    CHECK_RANGE(NSUnionRange(NSMakeRange(4, 0), NSMakeRange(4, 6)), 4, 6);
}

static void test_intersection_range(void)
{
    CHECK_RANGE(NSIntersectionRange(NSMakeRange(0, 5), NSMakeRange(3, 5)), 3, 2);
    CHECK_RANGE(NSIntersectionRange(NSMakeRange(3, 5), NSMakeRange(0, 5)), 3, 2);
}

static void test_intersection_range_when_disjoint(void)
{
    NSRange r = NSIntersectionRange(NSMakeRange(0, 2), NSMakeRange(9, 2));
    CHECK(r.length == 0);

    /*  Touching but not overlapping is still empty.  */
    CHECK(NSIntersectionRange(NSMakeRange(0, 3), NSMakeRange(3, 3)).length == 0);
}

static void test_intersection_range_when_nested(void)
{
    CHECK_RANGE(NSIntersectionRange(NSMakeRange(0, 10), NSMakeRange(4, 2)), 4, 2);
}

static void test_intersects_range(void)
{
    CHECK(NSIntersectsRange(NSMakeRange(0, 5), NSMakeRange(3, 5)));
    CHECK(!NSIntersectsRange(NSMakeRange(0, 2), NSMakeRange(9, 2)));
    CHECK(!NSIntersectsRange(NSMakeRange(0, 3), NSMakeRange(3, 3)));
}

int main(void)
{
    test_union_range();
    test_union_range_with_empty();
    test_intersection_range();
    test_intersection_range_when_disjoint();
    test_intersection_range_when_nested();
    test_intersects_range();

    printf("%s: %d failure(s)\n", failures ? "FAILED" : "PASSED", failures);
    return failures != 0;
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cc -I src/Kits/Foundation -o /tmp/test_range src/Kits/Foundation/reconstruction/tests/test_range.c src/Kits/Foundation/NSRange.m && /tmp/test_range
```

Expected: FAILED.

- [ ] **Step 3: Read the reference implementations**

Using `dump.py` from Task 12:

```bash
PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe src/Kits/Foundation/reconstruction/tests/dump.py _NSUnionRange _NSIntersectionRange _NSIntersectsRange _NSStringFromRange _NSRangeFromString
```

- [ ] **Step 4: Write the implementations**

Replace the body of `src/Kits/Foundation/NSRange.m`, keeping the Apple copyright
header. Define all five functions. `NSIntersectsRange` has no public declaration,
so declare it in the `.m` above its definition with external linkage — do not add
it to `NSRange.h`.

- [ ] **Step 5: Run the tests until they pass**

```bash
cc -I src/Kits/Foundation -o /tmp/test_range src/Kits/Foundation/reconstruction/tests/test_range.c src/Kits/Foundation/NSRange.m && /tmp/test_range
```

Expected: `PASSED: 0 failure(s)`.

- [ ] **Step 6: Commit**

```bash
git add src/Kits/Foundation/NSRange.m src/Kits/Foundation/reconstruction/tests/test_range.c
git commit -m "Foundation: reconstruct NSRange against the DR2 reference"
```

---

### Task 15: Verify the stage and record divergences

**Files:**
- Create: `src/Kits/Foundation/reconstruction/divergences.md`
- Create: `src/Kits/Foundation/reconstruction/geometry-range-decimal/source-map.json`
- Create: `src/Kits/Foundation/reconstruction/geometry-range-decimal/ledger.json`

**Interfaces:**
- Consumes: everything.
- Produces: the reviewed evidence that closes spec §4.

- [ ] **Step 1: Run abi-check against the built objects**

Build the three modules to objects in the guest, then:

```bash
PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -m binrecon abi-check --abi-dir src/Kits/Foundation/reconstruction/abi --built NSGeometry.m=/tmp/NSGeometry.o --built NSRange.m=/tmp/NSRange.o --built NSDecimal.m=/tmp/NSDecimal.o
```

Expected: `abi-check: ABI matches`, exit 0. This is spec §4 gate 1.

If it reports a divergence, fix the **source**, never the committed `abi/*.json`
— that file is evidence about Apple's binary, not about ours.

- [ ] **Step 2: Run all three test suites**

```bash
/tmp/test_decimal && /tmp/test_geometry && /tmp/test_range
```

Expected: three `PASSED: 0 failure(s)` lines. This is spec §4 gate 2, 28
functions.

- [ ] **Step 3: Run source-map**

`source-map` takes the analysis and the binary directly, not a profile:

```bash
PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -m binrecon source-map --reference-analysis tools/binrecon/out/foundation-i386/published/analysis-reference-ida.json --binary "C:/Users/raynorpat/Downloads/test/Foundation-i386" --source-dir src/Kits/Foundation --repo-root . --objc-methods --output src/Kits/Foundation/reconstruction/geometry-range-decimal/source-map.json
```

`--objc-methods` is required here: the six `NSGeometryCoding` methods are named
by `__OBJC` metadata, and without it they resolve to nothing.

Then check the result:

```bash
PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -c "
import json
d = json.load(open('src/Kits/Foundation/reconstruction/geometry-range-decimal/source-map.json'))
print({k: len(v) for k, v in d.items() if isinstance(v, list)})
"
```

Expected: all 43 functions in `mapped`, and `unmapped`,
`duplicate_candidates` and `boundary_disputed` all empty. This is spec §4 item 6.

- [ ] **Step 4: Run compare and build the ledger**

```bash
BINRECON_REFERENCE="C:/Users/raynorpat/Downloads/test/Foundation-i386" PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -m binrecon compare --profile tools/binrecon/profiles/foundation-i386.json --reference-analysis tools/binrecon/out/foundation-i386/published/analysis-reference-ida.json --rebuilt-analysis tools/binrecon/out/foundation-i386/published/analysis-rebuilt-ida.json --output src/Kits/Foundation/reconstruction/geometry-range-decimal/ledger.json
```

This is spec §4 gate 3, **evidence only**. Instruction divergence is expected —
the reference is a linked PIC dylib and our build is relocatable objects. Do not
chase parity.

Review every ledger entry and set its status with `binrecon ledger`, per the
existing driver workflow.

- [ ] **Step 5: Write divergences.md**

Create `src/Kits/Foundation/reconstruction/divergences.md`. It is shared and
append-only across all ten stages, so open with a heading for this stage. It
must record at minimum:

- `NSIntersectsRange` is exported by `NSRange.m` but declared in no public
  header; reconstructed with external linkage and declared in the `.m`.
- Every ledger entry dispositioned as *explained by codegen* or *real*, with
  the reason.
- Any test whose expectation was corrected against the reference's actual
  behaviour during Tasks 12–14, and what the reference does instead.
- The 15 functions written but not behaviourally tested in this stage, and which
  stage picks each up (9 string-facing → stage 3; 6 `NSGeometryCoding` → stage 2).
- **The observed ledger review cost** — how long reviewing 43 entries took, and
  the resulting per-function rate. Spec §5.5 wants this so stages 3–5, which
  face modules of 88 and 127 methods, can size their groups from data rather
  than guesswork. Without this number the largest stages get planned blind.

- [ ] **Step 6: Confirm no header changed**

```bash
git diff --stat HEAD -- 'src/Kits/Foundation/*.h'
```

Expected: empty output. This is spec §4 item 9 and a Global Constraint.

- [ ] **Step 7: Run the binrecon suite one final time**

```bash
PYTHONPATH=tools/binrecon /d/RhapsodiOS/.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests -q
```

Expected: PASS. This is spec §4 item 8.

- [ ] **Step 8: Commit**

```bash
git add src/Kits/Foundation/reconstruction
git commit -m "Foundation: record stage 1 parity evidence and divergences"
```
