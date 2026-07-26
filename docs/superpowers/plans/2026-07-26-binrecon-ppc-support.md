# PowerPC support in binrecon — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Teach `tools/binrecon` to read big-endian PowerPC Mach-O and drive IDA against it, so the PPC `SCSIServer` and `SCSITape` drivers can be reconstructed.

**Architecture:** A new `binrecon/arch.py` holds one descriptor per architecture (endianness, struct layouts, CPU type, IDA processor name, relocation decoder key). `binrecon/macho.py` selects a descriptor from the file header and uses its layouts everywhere, with two relocation decoders — the existing i386 one, moved verbatim, and a new PowerPC one that fuses paired relocations. The IDA adapter takes the processor name and endianness from the descriptor and passes both through its mapping manifest to the in-IDA export script, which validates against them instead of hardcoded values. Ghidra and angr explicitly reject non-i386 profiles.

**Tech Stack:** Python 3.12 (`.venv-binrecon`), pytest 9.1.1, jsonschema 4.26.0, IDA Professional 9.2.

**Spec:** [docs/superpowers/specs/2026-07-26-binrecon-ppc-support-design.md](../specs/2026-07-26-binrecon-ppc-support-design.md)

## Global Constraints

- i386 output must not change. `read_macho` on every existing i386 fixture and reference produces identical documents; every existing test passes unmodified except where this plan says otherwise (Task 2 Step 6, Task 3 Step 6). The only permitted behavioural difference is the wording of the section-alignment error message.
- Analyzer scope is IDA only. Ghidra and angr stay i386-only and must fail loudly on a PPC profile.
- Reference binaries stay outside git. They live under `C:\Users\raynorpat\Downloads\test\Drivers\ppc` and are referenced through `${BINRECON_REFERENCE}`.
- No driver source is touched. No source map, ledger, or divergence report is produced — those are the follow-on specs.
- Run everything from the repository root `D:/RhapsodiOS` with `PYTHONPATH=tools/binrecon` and the interpreter `./.venv-binrecon/Scripts/python.exe`.
- Commit message style: subsystem prefix, one to two lines, no metadata. Use `binrecon: ` for every commit in this plan.

## File Structure

| Path | Responsibility |
| --- | --- |
| `tools/binrecon/binrecon/arch.py` | **new.** Architecture descriptors: name, endianness, struct prefix, Mach-O struct layouts, CPU type, IDA processor name, relocation decoder key. The only place a per-architecture fact is written down. |
| `tools/binrecon/binrecon/macho.py` | Reads Mach-O using a descriptor's layouts. Holds both relocation decoders. |
| `tools/binrecon/binrecon/adapters/ida.py` | Chooses the IDA processor and fills the mapping manifest from the descriptor. |
| `tools/binrecon/adapters/ida/export_analysis.py` | Validates IDA's database against the manifest's processor and endianness. |
| `tools/binrecon/binrecon/adapters/ghidra.py`, `angr.py` | Reject non-i386 profiles. |
| `tools/binrecon/tests/macho_fixture.py` | Builds i386 and PPC fixture images and PPC relocation entries. |
| `tools/binrecon/tests/test_arch.py` | **new.** Descriptor lookup and consistency. |
| `tools/binrecon/tests/test_macho.py` | Reader tests, i386 and PPC. |
| `tools/binrecon/tests/test_objc_index.py` | Objective-C metadata walk, both byte orders. |
| `tools/binrecon/tests/test_ida_adapter.py` | Adapter argv/manifest and exporter gate tests. |
| `tools/binrecon/ppc_invariant_check.py` | **new.** Cross-checks a PPC reader run against properties that only hold if the decode is correct. |
| `tools/binrecon/profiles/*-ppc.json` | **new.** Seven reference-only IDA profiles. |
| `tools/binrecon/README.md` | Documents PPC support and its limits. |

---

### Task 1: Architecture descriptors

**Files:**
- Create: `tools/binrecon/binrecon/arch.py`
- Test: `tools/binrecon/tests/test_arch.py`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `class ArchitectureError(ValueError)`
  - `@dataclass(frozen=True) class MachOLayouts` with fields `header`, `load_command`, `segment_command`, `section`, `symtab_command`, `nlist`, `relocation_info`, each a `struct.Struct`
  - `@dataclass(frozen=True) class Architecture` with fields `name: str`, `endianness: str`, `struct_prefix: str`, `cpu_type: int`, `ida_processor: str`, `relocation_decoder: str`, `layouts: MachOLayouts`
  - `I386: Architecture`, `PPC: Architecture`
  - `architecture_for_name(name: str) -> Architecture`
  - `architecture_for_cpu_type(cpu_type: int, endianness: str) -> Architecture`

- [ ] **Step 1: Write the failing test**

Create `tools/binrecon/tests/test_arch.py`:

```python
import dataclasses

import pytest

from binrecon.arch import (
    I386,
    PPC,
    Architecture,
    ArchitectureError,
    architecture_for_cpu_type,
    architecture_for_name,
)


def test_descriptors_carry_the_per_architecture_facts():
    assert (I386.name, I386.endianness, I386.struct_prefix) == ("i386", "little", "<")
    assert (I386.cpu_type, I386.ida_processor, I386.relocation_decoder) == (7, "metapc", "i386")
    assert (PPC.name, PPC.endianness, PPC.struct_prefix) == ("ppc", "big", ">")
    assert (PPC.cpu_type, PPC.ida_processor, PPC.relocation_decoder) == (18, "ppc", "ppc")


def test_layouts_agree_in_size_and_differ_in_byte_order():
    for field in dataclasses.fields(I386.layouts):
        left = getattr(I386.layouts, field.name)
        right = getattr(PPC.layouts, field.name)
        assert left.size == right.size
        assert left.format.startswith("<") and right.format.startswith(">")
    assert I386.layouts.header.size == 28
    assert I386.layouts.section.size == 68
    assert I386.layouts.nlist.size == 12
    assert I386.layouts.relocation_info.size == 8


def test_lookup_by_name():
    assert architecture_for_name("i386") is I386
    assert architecture_for_name("ppc") is PPC


def test_unknown_name_names_the_supported_set():
    with pytest.raises(ArchitectureError, match="i386, ppc"):
        architecture_for_name("mips")


def test_lookup_by_cpu_type_requires_matching_byte_order():
    assert architecture_for_cpu_type(7, "little") is I386
    assert architecture_for_cpu_type(18, "big") is PPC
    with pytest.raises(ArchitectureError, match="read as big-endian"):
        architecture_for_cpu_type(7, "big")
    with pytest.raises(ArchitectureError, match="CPU type 12"):
        architecture_for_cpu_type(12, "big")


def test_descriptors_are_immutable():
    with pytest.raises(dataclasses.FrozenInstanceError):
        PPC.name = "other"
    assert isinstance(PPC, Architecture)
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests/test_arch.py -q
```

Expected: collection error, `ModuleNotFoundError: No module named 'binrecon.arch'`.

- [ ] **Step 3: Write the implementation**

Create `tools/binrecon/binrecon/arch.py`:

```python
"""Per-architecture facts shared by the Mach-O reader and the analyzer adapters."""

from dataclasses import dataclass
import struct


class ArchitectureError(ValueError):
    """Raised when an architecture is unknown or disagrees with the input."""


@dataclass(frozen=True)
class MachOLayouts:
    """Mach-O on-disk structures in one architecture's byte order."""

    header: struct.Struct
    load_command: struct.Struct
    segment_command: struct.Struct
    section: struct.Struct
    symtab_command: struct.Struct
    nlist: struct.Struct
    relocation_info: struct.Struct


def _layouts(prefix: str) -> MachOLayouts:
    return MachOLayouts(
        header=struct.Struct(f"{prefix}7I"),
        load_command=struct.Struct(f"{prefix}2I"),
        segment_command=struct.Struct(f"{prefix}II16sIIIIiiII"),
        section=struct.Struct(f"{prefix}16s16sIIIIIIIII"),
        symtab_command=struct.Struct(f"{prefix}6I"),
        nlist=struct.Struct(f"{prefix}IBBHI"),
        relocation_info=struct.Struct(f"{prefix}iI"),
    )


@dataclass(frozen=True)
class Architecture:
    """Everything binrecon needs to know that varies by architecture."""

    name: str
    endianness: str
    struct_prefix: str
    cpu_type: int
    ida_processor: str
    relocation_decoder: str
    layouts: MachOLayouts


I386 = Architecture(
    name="i386",
    endianness="little",
    struct_prefix="<",
    cpu_type=7,
    ida_processor="metapc",
    relocation_decoder="i386",
    layouts=_layouts("<"),
)

PPC = Architecture(
    name="ppc",
    endianness="big",
    struct_prefix=">",
    cpu_type=18,
    ida_processor="ppc",
    relocation_decoder="ppc",
    layouts=_layouts(">"),
)

_SUPPORTED = (I386, PPC)
_BY_NAME = {architecture.name: architecture for architecture in _SUPPORTED}
_BY_CPU_TYPE = {architecture.cpu_type: architecture for architecture in _SUPPORTED}


def architecture_for_name(name: str) -> Architecture:
    """Return the descriptor a profile's ``architecture`` string names."""
    try:
        return _BY_NAME[name]
    except (KeyError, TypeError):
        supported = ", ".join(sorted(_BY_NAME))
        raise ArchitectureError(
            f"unsupported architecture {name!r}; expected one of {supported}"
        ) from None


def architecture_for_cpu_type(cpu_type: int, endianness: str) -> Architecture:
    """Return the descriptor for a Mach-O CPU type read in a given byte order."""
    architecture = _BY_CPU_TYPE.get(cpu_type)
    if architecture is None or architecture.endianness != endianness:
        raise ArchitectureError(
            f"unsupported Mach-O CPU type {cpu_type} read as {endianness}-endian; "
            "expected i386 (7, little-endian) or ppc (18, big-endian)"
        )
    return architecture
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests/test_arch.py -q
```

Expected: `6 passed`.

- [ ] **Step 5: Commit**

```bash
cd /d/RhapsodiOS && git add tools/binrecon/binrecon/arch.py tools/binrecon/tests/test_arch.py && git commit -m "binrecon: add architecture descriptors for i386 and ppc"
```

---

### Task 2: Read PowerPC headers, segments, sections, and symbols

**Files:**
- Modify: `tools/binrecon/tests/macho_fixture.py`
- Modify: `tools/binrecon/binrecon/macho.py:10-34` (constants and layouts), `:111-137` (header identity), `:139-304` (command walk), `:315-323` (input identity), `:532-582` (`_read_symbols`)
- Modify: `tools/binrecon/tests/test_macho.py:170-175`
- Test: `tools/binrecon/tests/test_macho.py`

**Interfaces:**
- Consumes: `binrecon.arch.architecture_for_cpu_type`, `Architecture`, `MachOLayouts`.
- Produces:
  - `macho_fixture.build_macho_fixture(*, extra_command=b"", file_type=MH_OBJECT, base_address=0x1000, architecture="i386", text=None, relocations=None) -> bytes`
  - `macho_fixture.CPU_TYPE_POWERPC = 18`
  - `macho.read_macho(path)` accepting big-endian PPC images; `document["input"]["architecture"]` is `"ppc"` and `["endianness"]` is `"big"` for them.
  - Private: `macho._select_architecture(data: bytes) -> Architecture`.

- [ ] **Step 1: Write the failing test**

Replace the top of `tools/binrecon/tests/macho_fixture.py` (lines 1–26, through the `build_macho_fixture` signature) so the builder takes an architecture, an explicit `__text` payload, and explicit relocation entries. Keep every module-level constant that tests already import; they stay i386:

```python
import struct


MH_MAGIC = 0xFEEDFACE
CPU_TYPE_I386 = 7
CPU_TYPE_POWERPC = 18
MH_OBJECT = 1
MH_PRELOAD = 5
MH_BUNDLE = 8
LC_SEGMENT = 1
LC_SYMTAB = 2
LC_UNIXTHREAD = 5

HEADER = struct.Struct("<7I")
SEGMENT = struct.Struct("<II16sIIIIiiII")
SECTION = struct.Struct("<16s16sIIIIIIIII")
SYMTAB = struct.Struct("<6I")
NLIST = struct.Struct("<IBBHI")
RELOCATION = struct.Struct("<iI")

_PREFIXES = {"i386": "<", "ppc": ">"}
_CPU_TYPES = {"i386": CPU_TYPE_I386, "ppc": CPU_TYPE_POWERPC}


def _structs(architecture):
    prefix = _PREFIXES[architecture]
    return {
        "header": struct.Struct(f"{prefix}7I"),
        "segment": struct.Struct(f"{prefix}II16sIIIIiiII"),
        "section": struct.Struct(f"{prefix}16s16sIIIIIIIII"),
        "symtab": struct.Struct(f"{prefix}6I"),
        "nlist": struct.Struct(f"{prefix}IBBHI"),
        "relocation": struct.Struct(f"{prefix}iI"),
        "word": struct.Struct(f"{prefix}I"),
        "pair": struct.Struct(f"{prefix}II"),
    }


def _name(value: str) -> bytes:
    return value.encode("ascii").ljust(16, b"\0")


def build_macho_fixture(*, extra_command: bytes = b"", file_type: int = MH_OBJECT,
                        base_address: int = 0x1000, architecture: str = "i386",
                        text: bytes | None = None,
                        relocations: bytes | None = None) -> bytes:
```

Then rewrite the body to use `layout = _structs(architecture)` in place of the module-level structs, with these differences from today:

```python
    layout = _structs(architecture)
    # A four-byte vanilla relocation owns the complete field at offset zero.
    text = b"\0" * 4 if text is None else text
    data = b"DATA"
    strings = b"\0_external\0"
    if relocations is None:
        relocation_word = 0 | (2 << 25) | (1 << 27)
        relocations = layout["relocation"].pack(0, relocation_word)
    relocation_count = len(relocations) // layout["relocation"].size

    segment_size = layout["segment"].size + 2 * layout["section"].size
    thread_payload = layout["word"].pack(0xAABBCCDD) + b"unknown-thread-state"
    thread_command = layout["pair"].pack(
        LC_UNIXTHREAD, 8 + len(thread_payload)
    ) + thread_payload
    commands_size = (segment_size + layout["symtab"].size + len(thread_command)
                     + len(extra_command))
    data_start = layout["header"].size + commands_size
    text_offset = data_start
    data_offset = text_offset + len(text)
    relocation_offset = data_offset + len(data)
    symbol_offset = relocation_offset + len(relocations)
    string_offset = symbol_offset + layout["nlist"].size
```

The segment command keeps `len(text) + len(data)` as both vm and file size, `__text` gets `len(text)` and `relocation_count`, `__data` sits at `base_address + len(text)` with `len(data)`, and the header uses `_CPU_TYPES[architecture]`. The remaining packing is today's code with `layout[...]` substituted. The default i386 call must produce exactly today's bytes.

Add PPC relocation helpers at the end of the module:

```python
PPC_RELOC_VANILLA = 0
PPC_RELOC_PAIR = 1
PPC_RELOC_BR24 = 3
PPC_RELOC_HI16 = 4
PPC_RELOC_LO16 = 5
PPC_RELOC_HA16 = 6
PPC_RELOC_SECTDIFF = 8
PPC_RELOC_JBSR = 13


def ppc_relocation(address, symbolnum, *, kind, length=2, pcrel=0, extern=0):
    """One non-scattered big-endian relocation_info entry."""
    word = (((symbolnum & 0xFFFFFF) << 8) | ((pcrel & 1) << 7)
            | ((length & 3) << 5) | ((extern & 1) << 4) | (kind & 0xF))
    return struct.pack(">iI", address, word)


def ppc_pair(other_half, *, kind=PPC_RELOC_PAIR, length=2):
    """A PAIR entry, whose r_address field carries the other half."""
    return ppc_relocation(other_half, 0xFFFFFF, kind=kind, length=length)


def ppc_scattered(address, value, *, kind, length=2, pcrel=0):
    """One scattered big-endian relocation entry."""
    word = (0x80000000 | ((pcrel & 1) << 30) | ((length & 3) << 28)
            | ((kind & 0xF) << 24) | (address & 0xFFFFFF))
    return struct.pack(">II", word, value)


def patch_u32(blob: bytes, offset: int, value: int) -> bytes:
    result = bytearray(blob)
    struct.pack_into("<I", result, offset, value)
    return bytes(result)
```

Now add the reader tests to `tools/binrecon/tests/test_macho.py`. Extend the fixture import list with `CPU_TYPE_POWERPC` and append:

```python
def test_reads_big_endian_ppc_preload_image(tmp_path):
    blob = build_macho_fixture(
        architecture="ppc", file_type=MH_PRELOAD, base_address=0,
        text=b"\0" * 16, relocations=b"",
    )
    path = tmp_path / "ppc.o"
    path.write_bytes(blob)

    document = read_macho(path)

    assert document["input"]["architecture"] == "ppc"
    assert document["input"]["endianness"] == "big"
    assert [section["name"] for section in document["sections"]] == [
        "__TEXT,__text", "__DATA,__data",
    ]
    assert [section["size"] for section in document["sections"]] == [16, 4]
    assert document["symbols"] == [
        {"name": "_external", "address": 0, "binding": "external", "section": None}
    ]
    assert document["relocations"] == []
    assert document["extensions"]["macho"]["header"]["cpu_type"] == CPU_TYPE_POWERPC
    validate_document("analysis-v1", document)


def test_ppc_and_i386_documents_differ_only_in_identity_fields(tmp_path):
    def read(architecture):
        path = tmp_path / f"{architecture}.o"
        path.write_bytes(build_macho_fixture(architecture=architecture, relocations=b""))
        document = read_macho(path)
        document["input"].pop("path")
        document["input"].pop("sha256")
        return document

    little = read("i386")
    big = read("ppc")

    assert little["input"] == {"size": big["input"]["size"], "architecture": "i386",
                               "endianness": "little"}
    assert big["input"]["architecture"] == "ppc"
    assert little["sections"] == big["sections"]
    assert little["symbols"] == big["symbols"]


def test_rejects_swapped_header_by_naming_the_cpu_type(tmp_path):
    # Bytes FE ED FA CE read big-endian are a valid magic, so the CPU type is
    # what exposes a little-endian image mislabelled as big-endian.
    blob = patch_u32(build_macho_fixture(), 0, 0xCEFAEDFE)
    path = tmp_path / "swapped.o"
    path.write_bytes(blob)

    with pytest.raises(MachOFormatError, match="CPU type"):
        read_macho(path)
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests/test_macho.py -q
```

Expected: the three new tests fail — `unsupported Mach-O magic` for the PPC ones — while the 36 existing tests still pass.

- [ ] **Step 3: Select the architecture from the header**

In `tools/binrecon/binrecon/macho.py`, add the import and the selector, and delete the seven module-level `struct.Struct` constants (`_MACH_HEADER` through `_RELOCATION_INFO`) — every use is replaced in this step and Task 3:

```python
from .arch import Architecture, ArchitectureError, architecture_for_cpu_type
```

```python
def _select_architecture(data: bytes) -> Architecture:
    """Identify the image's architecture from its magic and CPU type."""
    if len(data) < 8:
        raise MachOFormatError("input is shorter than a Mach-O header identity")
    for endianness, prefix in (("big", ">"), ("little", "<")):
        magic, cpu_type = struct.unpack_from(f"{prefix}2I", data, 0)
        if magic == MH_MAGIC:
            try:
                return architecture_for_cpu_type(cpu_type, endianness)
            except ArchitectureError as error:
                raise MachOFormatError(str(error)) from error
    (raw,) = struct.unpack_from(">I", data, 0)
    raise MachOFormatError(
        f"unsupported Mach-O magic 0x{raw:08x}; expected 32-bit i386 or ppc"
    )
```

- [ ] **Step 4: Use the descriptor's layouts through the command walk**

In `read_macho`, replace the header unpack and identity checks (today's lines 118–137) with:

```python
    architecture = _select_architecture(data)
    layouts = architecture.layouts
    (
        magic,
        cpu_type,
        cpu_subtype,
        file_type,
        command_count,
        commands_size,
        flags,
    ) = _unpack(layouts.header, data, 0, "Mach-O header")
    if file_type not in (MH_OBJECT, MH_PRELOAD, MH_BUNDLE, MH_EXECUTE):
        raise MachOFormatError(
            f"unsupported Mach-O file type {file_type}; "
            "expected MH_OBJECT, MH_PRELOAD, MH_BUNDLE or MH_EXECUTE"
        )
```

Then substitute throughout the rest of `read_macho`: `_MACH_HEADER` → `layouts.header`, `_LOAD_COMMAND` → `layouts.load_command`, `_SEGMENT_COMMAND` → `layouts.segment_command`, `_SECTION` → `layouts.section`, `_SYMTAB_COMMAND` → `layouts.symtab_command`. Change the section alignment error to drop the architecture name:

```python
                    raise MachOFormatError(
                        f"{section_context}: alignment exponent exceeds 32-bit address width "
                        f"at file offset 0x{section_offset:x}"
                    )
```

Thread the descriptor into the two readers and take the identity from it:

```python
    symbols, symbol_names = _read_symbols(data, symtab, raw_sections, layouts)
    raw_relocations = _read_relocations(data, raw_sections, symbol_names, architecture)
```

```python
            "architecture": architecture.name,
            "endianness": architecture.endianness,
```

In `_read_symbols`, add the `layouts` parameter and replace `_NLIST` with `layouts.nlist`:

```python
def _read_symbols(
    data: bytes,
    symtab: tuple[int, int, int, int, int] | None,
    sections: list[dict[str, Any]],
    layouts,
) -> tuple[list[dict[str, Any]], list[str]]:
```

In `_read_relocations`, add the `architecture` parameter and, for now, keep its body unchanged apart from replacing `_RELOCATION_INFO` with `architecture.layouts.relocation_info` and the two i386 literals:

```python
def _read_relocations(
    data: bytes,
    sections: list[dict[str, Any]],
    symbol_names: list[str],
    architecture,
) -> list[dict[str, Any]]:
```

```python
            if length == 3:
                raise MachOFormatError(
                    f"{entry_context}: relocation length code 3 is invalid for "
                    f"{architecture.name}"
                )
```

```python
            field_value = int.from_bytes(field, architecture.endianness, signed=pc_relative)
```

```python
                    "kind": f"{architecture.name}-{type_name}-{width * 8}-{relative}",
```

- [ ] **Step 5: Run the tests**

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests/test_macho.py -q
```

Expected: the three new tests pass. `test_rejects_64_bit_and_big_endian_magic` now fails, because `0xCEFAEDFE` is no longer rejected on magic.

- [ ] **Step 6: Narrow the obsolete magic test**

In `tools/binrecon/tests/test_macho.py`, replace `test_rejects_64_bit_and_big_endian_magic` (lines 170–175) with:

```python
def test_rejects_64_bit_magic(tmp_path):
    path = write_fixture(tmp_path, patch_u32(build_macho_fixture(), 0, 0xFEEDFACF))

    with pytest.raises(MachOFormatError, match="magic"):
        read_macho(path)
```

The byte-swapped case is now covered by `test_rejects_swapped_header_by_naming_the_cpu_type`.

- [ ] **Step 7: Run the full suite**

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon -q
```

Expected: all tests pass, no failures, no errors.

- [ ] **Step 8: Commit**

```bash
cd /d/RhapsodiOS && git add tools/binrecon/binrecon/macho.py tools/binrecon/tests/macho_fixture.py tools/binrecon/tests/test_macho.py && git commit -m "binrecon: read big-endian PowerPC Mach-O headers, sections, and symbols"
```

---

### Task 3: Decode non-scattered PowerPC relocations

**Files:**
- Modify: `tools/binrecon/binrecon/macho.py` (`_read_relocations` split, `read_macho` relocation wiring)
- Modify: `tools/binrecon/tests/test_macho.py:325-336`
- Test: `tools/binrecon/tests/test_macho.py`

**Interfaces:**
- Consumes: `macho_fixture.ppc_relocation`, `ppc_pair`, and the `PPC_RELOC_*` constants from Task 2.
- Produces:
  - `macho._read_relocations(data, sections, symbol_names, architecture) -> tuple[list[dict], list[dict]]` returning `(semantic, raw)`. This is a signature change from Task 2's single-list return; `read_macho` unpacks both.
  - Semantic records carry exactly `address`, `kind`, `target`, `addend`.
  - PPC semantic kinds: `ppc-vanilla-32-absolute`, `ppc-hi16-32-absolute`, `ppc-ha16-32-absolute`, `ppc-lo16-32-absolute`, `ppc-jbsr-24-pc-relative`, `ppc-br24-24-pc-relative`.
  - PPC raw records carry the i386 field set plus `"scattered": bool`.

**Reference semantics** (from the spec §3.5, verified against `SCSIServer_reloc`):

| Principal | Pair carries | Value |
| --- | --- | --- |
| `HI16` | low half in `r_address` | `(hi << 16) \| lo` |
| `HA16` | low half in `r_address` | `(hi << 16) + sign_extend16(lo)` |
| `LO16` | high half in `r_address` | `(hi << 16) \| lo` |
| `JBSR` | true target (0 for external) in `r_address` | pair value; the branch field itself points at a jump island |
| `BR24` | no pair | `sign_extend26(word & 0x03FFFFFC) + relocation address` |
| `VANILLA` | no pair | the 32-bit word |

Addend is `value - target_section["address"]` when the target is a section, and `value` when the target is an external symbol or absolute.

- [ ] **Step 1: Write the failing test**

Append to `tools/binrecon/tests/test_macho.py` (extend the fixture import list with `PPC_RELOC_BR24`, `PPC_RELOC_HA16`, `PPC_RELOC_HI16`, `PPC_RELOC_JBSR`, `PPC_RELOC_LO16`, `PPC_RELOC_PAIR`, `PPC_RELOC_VANILLA`, `ppc_pair`, `ppc_relocation`):

```python
def write_ppc(tmp_path, text, relocations, name="ppc.o"):
    path = tmp_path / name
    path.write_bytes(build_macho_fixture(
        architecture="ppc", text=text, relocations=relocations,
    ))
    return path


def semantic(document):
    return {entry["address"]: entry for entry in document["relocations"]}


def test_ppc_ha16_pair_applies_the_signed_low_half(tmp_path):
    # lis r3,2 ; addi r3,r3,-1 -> external symbol value 0x0001FFFF
    text = struct.pack(">II", 0x3C600002, 0x3863FFFF)
    relocations = (
        ppc_relocation(0, 0, kind=PPC_RELOC_HA16, extern=1) + ppc_pair(0xFFFF)
    )

    document = read_macho(write_ppc(tmp_path, text, relocations))

    assert semantic(document)[0x1000] == {
        "address": 0x1000, "kind": "ppc-ha16-32-absolute",
        "target": "_external", "addend": 0x1FFFF,
    }


def test_ppc_hi16_pair_concatenates_without_the_ha16_adjustment(tmp_path):
    text = struct.pack(">II", 0x3C600002, 0x3863FFFF)
    relocations = (
        ppc_relocation(0, 0, kind=PPC_RELOC_HI16, extern=1) + ppc_pair(0xFFFF)
    )

    document = read_macho(write_ppc(tmp_path, text, relocations))

    assert semantic(document)[0x1000]["addend"] == 0x2FFFF
    assert semantic(document)[0x1000]["kind"] == "ppc-hi16-32-absolute"


def test_ppc_lo16_pair_takes_the_high_half_from_the_pair(tmp_path):
    # __data sits at 0x1008 when __text is eight bytes long.
    text = struct.pack(">II", 0x38601008, 0x60000000)
    relocations = ppc_relocation(0, 2, kind=PPC_RELOC_LO16) + ppc_pair(0x0000)

    document = read_macho(write_ppc(tmp_path, text, relocations))

    assert semantic(document)[0x1000] == {
        "address": 0x1000, "kind": "ppc-lo16-32-absolute",
        "target": "__DATA,__data", "addend": 0,
    }


def test_ppc_vanilla_pointer_is_section_relative(tmp_path):
    text = struct.pack(">II", 0x00001004, 0x00000000)
    relocations = ppc_relocation(0, 1, kind=PPC_RELOC_VANILLA)

    document = read_macho(write_ppc(tmp_path, text, relocations))

    assert semantic(document)[0x1000] == {
        "address": 0x1000, "kind": "ppc-vanilla-32-absolute",
        "target": "__TEXT,__text", "addend": 4,
    }


def test_ppc_jbsr_names_the_symbol_and_records_the_island(tmp_path):
    # bl +8 into the island at 0x1008, whose real target is the symbol.
    text = struct.pack(">III", 0x48000009, 0x60000000, 0x4E800020)
    relocations = ppc_relocation(0, 0, kind=PPC_RELOC_JBSR, extern=1) + ppc_pair(0)

    document = read_macho(write_ppc(tmp_path, text, relocations))

    assert semantic(document)[0x1000] == {
        "address": 0x1000, "kind": "ppc-jbsr-24-pc-relative",
        "target": "_external", "addend": 0,
    }
    raw = document["extensions"]["macho"]["relocations"]
    assert [entry["kind"] for entry in raw] == [
        "ppc-jbsr-24-pc-relative", "ppc-pair-16-absolute",
    ]
    assert raw[0]["original_bytes"] == "48000009"


def test_ppc_br24_resolves_against_the_relocation_address(tmp_path):
    text = struct.pack(">II", 0x48000009, 0x60000000)
    relocations = ppc_relocation(0, 1, kind=PPC_RELOC_BR24, pcrel=1)

    document = read_macho(write_ppc(tmp_path, text, relocations))

    assert semantic(document)[0x1000] == {
        "address": 0x1000, "kind": "ppc-br24-24-pc-relative",
        "target": "__TEXT,__text", "addend": 8,
    }


def test_ppc_raw_relocations_keep_every_file_entry(tmp_path):
    text = struct.pack(">II", 0x3C600002, 0x3863FFFF)
    relocations = (
        ppc_relocation(0, 0, kind=PPC_RELOC_HA16, extern=1) + ppc_pair(0xFFFF)
    )

    document = read_macho(write_ppc(tmp_path, text, relocations))

    raw = document["extensions"]["macho"]["relocations"]
    assert len(raw) == 2
    assert len(document["relocations"]) == 1
    assert [entry["scattered"] for entry in raw] == [False, False]


def test_ppc_principal_without_its_pair_is_rejected(tmp_path):
    text = struct.pack(">II", 0x3C600002, 0x60000000)
    relocations = (
        ppc_relocation(0, 0, kind=PPC_RELOC_HA16, extern=1)
        + ppc_relocation(4, 1, kind=PPC_RELOC_VANILLA)
    )

    with pytest.raises(MachOFormatError, match="requires a PAIR"):
        read_macho(write_ppc(tmp_path, text, relocations))


def test_ppc_orphan_pair_is_rejected(tmp_path):
    text = struct.pack(">II", 0x60000000, 0x60000000)
    relocations = ppc_pair(0x1234)

    with pytest.raises(MachOFormatError, match="unexpected PAIR"):
        read_macho(write_ppc(tmp_path, text, relocations))


def test_ppc_unsupported_relocation_type_names_type_and_offset(tmp_path):
    text = struct.pack(">II", 0x60000000, 0x60000000)
    relocations = ppc_relocation(0, 1, kind=9)

    with pytest.raises(MachOFormatError, match=r"relocation type 9.*file offset 0x"):
        read_macho(write_ppc(tmp_path, text, relocations))
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests/test_macho.py -q -k ppc
```

Expected: the new PPC relocation tests fail — the i386 decoder mis-reads the entries and produces `ppc-vanilla-…`-shaped kinds with wrong addends, or raises on the length code.

- [ ] **Step 3: Split the decoders**

In `tools/binrecon/binrecon/macho.py`, rename the existing `_read_relocations` to `_decode_i386_relocations`, keeping its body exactly as Task 2 left it, and have it return both lists at the end:

```python
def _decode_i386_relocations(data, sections, symbol_names, architecture):
    ...
    semantic = [
        {key: relocation[key] for key in ("address", "kind", "target", "addend")}
        for relocation in result
    ]
    return semantic, result
```

Add the dispatcher above it:

```python
_RELOCATION_FIELDS = ("address", "kind", "target", "addend")


def _read_relocations(data, sections, symbol_names, architecture):
    """Return (semantic, raw) relocation records for one image."""
    if architecture.relocation_decoder == "ppc":
        return _decode_ppc_relocations(data, sections, symbol_names, architecture)
    return _decode_i386_relocations(data, sections, symbol_names, architecture)
```

In `read_macho`, replace the projection block with:

```python
    relocations, raw_relocations = _read_relocations(
        data, raw_sections, symbol_names, architecture
    )
```

and delete the now-dead `relocation_fields` lines that rebuilt `relocations` from `raw_relocations`. Keep the existing sort of `relocations` and of `extensions.macho.relocations` untouched — the extension sort key must gain nothing, so `scattered` stays out of it.

- [ ] **Step 4: Write the PowerPC decoder**

Add to `tools/binrecon/binrecon/macho.py`:

```python
PPC_RELOC_VANILLA = 0
PPC_RELOC_PAIR = 1
PPC_RELOC_BR14 = 2
PPC_RELOC_BR24 = 3
PPC_RELOC_HI16 = 4
PPC_RELOC_LO16 = 5
PPC_RELOC_HA16 = 6
PPC_RELOC_SECTDIFF = 8
PPC_RELOC_JBSR = 13

_PPC_TYPE_NAMES = {
    PPC_RELOC_VANILLA: "vanilla",
    PPC_RELOC_PAIR: "pair",
    PPC_RELOC_BR14: "br14",
    PPC_RELOC_BR24: "br24",
    PPC_RELOC_HI16: "hi16",
    PPC_RELOC_LO16: "lo16",
    PPC_RELOC_HA16: "ha16",
    PPC_RELOC_SECTDIFF: "sectdiff",
    PPC_RELOC_JBSR: "jbsr",
}
# Field width in bits, and whether the type consumes a following PAIR.
_PPC_FIELD_BITS = {
    PPC_RELOC_VANILLA: 32, PPC_RELOC_PAIR: 16, PPC_RELOC_BR14: 14,
    PPC_RELOC_BR24: 24, PPC_RELOC_HI16: 16, PPC_RELOC_LO16: 16,
    PPC_RELOC_HA16: 16, PPC_RELOC_SECTDIFF: 32, PPC_RELOC_JBSR: 24,
}
_PPC_PAIRED = frozenset(
    (PPC_RELOC_HI16, PPC_RELOC_LO16, PPC_RELOC_HA16, PPC_RELOC_JBSR,
     PPC_RELOC_SECTDIFF)
)


def _sign_extend(value: int, bits: int) -> int:
    sign = 1 << (bits - 1)
    return (value & (sign - 1)) - (value & sign)


def _ppc_entries(data, section, section_index, architecture):
    """Read one section's relocation table into decoded field dictionaries."""
    layout = architecture.layouts.relocation_info
    count = section["relocation_count"]
    context = (
        f"load command {section['command_index']} section "
        f"{section['section_in_segment']} (global {section_index}) relocations"
    )
    if count > len(data) // layout.size:
        raise MachOFormatError(
            f"{context}: relocation count is too large at file offset "
            f"0x{section['relocation_offset']:x}"
        )
    _checked_slice(data, section["relocation_offset"], count * layout.size, context)
    entries = []
    for index in range(count):
        offset = section["relocation_offset"] + index * layout.size
        first, second = _unpack(layout, data, offset, context)
        raw_first = first & 0xFFFFFFFF
        if raw_first & 0x80000000:
            entries.append({
                "offset": offset, "scattered": True,
                "address": raw_first & 0xFFFFFF,
                "pc_relative": bool(raw_first & (1 << 30)),
                "length": (raw_first >> 28) & 0x3,
                "type": (raw_first >> 24) & 0xF,
                "value": second, "symbolnum": None, "external": False,
            })
        else:
            entries.append({
                "offset": offset, "scattered": False, "address": raw_first,
                "pc_relative": bool((second >> 7) & 1),
                "length": (second >> 5) & 0x3,
                "external": bool((second >> 4) & 1),
                "type": second & 0xF,
                "symbolnum": (second >> 8) & 0xFFFFFF, "value": None,
            })
    return entries, context


def _ppc_instruction(data, section, entry, context):
    """Return the four-byte word the relocation patches."""
    if section["zero_fill"]:
        return 0, b"\0\0\0\0"
    field = _checked_slice(data, section["offset"] + entry["address"], 4, context)
    return int.from_bytes(field, "big"), field


def _ppc_section_of(sections, value):
    for candidate in sections:
        if candidate["size"] and (
            candidate["address"] <= value < candidate["address"] + candidate["size"]
        ):
            return candidate
    return None


def _decode_ppc_relocations(data, sections, symbol_names, architecture):
    semantic: list[dict[str, Any]] = []
    raw: list[dict[str, Any]] = []
    for section_index, section in enumerate(sections):
        entries, context = _ppc_entries(data, section, section_index, architecture)
        index = 0
        while index < len(entries):
            entry = entries[index]
            where = f"{context} at file offset 0x{entry['offset']:x}"
            kind = entry["type"]
            if kind == PPC_RELOC_PAIR:
                raise MachOFormatError(f"{where}: unexpected PAIR without a principal")
            if kind not in _PPC_TYPE_NAMES:
                raise MachOFormatError(
                    f"{where}: unsupported relocation type {kind}"
                )
            pair = None
            if kind in _PPC_PAIRED:
                pair = entries[index + 1] if index + 1 < len(entries) else None
                if pair is None or pair["type"] != PPC_RELOC_PAIR:
                    raise MachOFormatError(
                        f"{where}: {_PPC_TYPE_NAMES[kind]} requires a PAIR entry"
                    )
            if entry["address"] > section["size"] - 4 or section["size"] < 4:
                raise MachOFormatError(f"{where}: relocation field crosses owning section")

            word, field = _ppc_instruction(data, section, entry, where)
            low = word & 0xFFFF
            if kind == PPC_RELOC_VANILLA:
                value = word
            elif kind == PPC_RELOC_HI16:
                value = (low << 16) | (pair["address"] & 0xFFFF)
            elif kind == PPC_RELOC_HA16:
                value = (low << 16) + _sign_extend(pair["address"] & 0xFFFF, 16)
            elif kind == PPC_RELOC_LO16:
                value = ((pair["address"] & 0xFFFF) << 16) | low
            elif kind == PPC_RELOC_JBSR:
                value = pair["address"]
            elif kind == PPC_RELOC_BR24:
                value = (_sign_extend(word & 0x03FFFFFC, 26)
                         + section["address"] + entry["address"])
            elif kind == PPC_RELOC_BR14:
                value = (_sign_extend(word & 0xFFFC, 16)
                         + section["address"] + entry["address"])
            else:  # PPC_RELOC_SECTDIFF, only ever scattered
                raise MachOFormatError(
                    f"{where}: SECTDIFF is only supported as a scattered relocation"
                )

            target, target_section = _ppc_target(
                entry, sections, symbol_names, where
            )
            addend = value - target_section["address"] if target_section else value
            relative = "pc-relative" if kind in (PPC_RELOC_BR14, PPC_RELOC_BR24,
                                                 PPC_RELOC_JBSR) else "absolute"
            name = f"ppc-{_PPC_TYPE_NAMES[kind]}-{_PPC_FIELD_BITS[kind]}-{relative}"
            semantic.append({"address": section["address"] + entry["address"],
                             "kind": name, "target": target, "addend": addend})
            raw.append(_ppc_raw(section, entry, name, target, addend, field))
            if pair is not None:
                # A PAIR's r_address is the other half of the value, not an
                # offset, so the record is addressed at its principal and its
                # bytes are that half.
                raw.append(_ppc_pair_raw(section, entry, pair))
                index += 1
            index += 1
    return semantic, raw


def _ppc_pair_raw(section, principal, pair):
    record = _ppc_raw(section, principal, "ppc-pair-16-absolute", None,
                      pair["address"],
                      (pair["address"] & 0xFFFF).to_bytes(2, "big"))
    record["type"] = pair["type"]
    record["scattered"] = pair["scattered"]
    record["width"] = 2
    return record


def _ppc_target(entry, sections, symbol_names, where):
    """Resolve a non-scattered entry's target name and owning section."""
    if entry["external"]:
        if entry["symbolnum"] >= len(symbol_names):
            raise MachOFormatError(
                f"{where}: invalid symbol index {entry['symbolnum']}"
            )
        return symbol_names[entry["symbolnum"]], None
    if entry["symbolnum"] == 0:
        # Mach-O's R_ABS pseudo-section means no relocation target.
        return None, None
    if entry["symbolnum"] > len(sections):
        raise MachOFormatError(
            f"{where}: invalid section ordinal {entry['symbolnum']}"
        )
    section = sections[entry["symbolnum"] - 1]
    return section["name"], section


def _ppc_raw(section, entry, kind, target, addend, field):
    return {
        "address": section["address"] + entry["address"],
        "kind": kind,
        "target": target,
        "addend": addend,
        "type": entry["type"],
        "pc_relative": entry["pc_relative"],
        "width": 4,
        "external": entry["external"],
        "section": section["name"],
        "section_ordinal": section["ordinal"],
        "target_section_ordinal": None,
        "original_bytes": field.hex().upper(),
        "scattered": entry["scattered"],
    }
```

Set `target_section_ordinal` in `_decode_ppc_relocations` after resolving the target: when `target_section` is not `None`, assign `raw[-1]["target_section_ordinal"] = target_section["ordinal"]` before appending the pair record.

- [ ] **Step 5: Run the tests**

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests/test_macho.py -q
```

Expected: all PPC relocation tests pass.

- [ ] **Step 6: Confirm the i386 length-code test still matches**

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests/test_macho.py -q -k "length_code or scattered or relocation"
```

Expected: pass. The i386 message now interpolates `architecture.name`, which is the literal `i386` for those fixtures, so `test_rejects_relocation_length_code_three` (matching `.*i386`) is unaffected. If it fails, the substitution in Task 2 Step 4 was wrong — fix it there rather than weakening the test.

- [ ] **Step 7: Run the full suite and commit**

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon -q
```

Expected: all pass.

```bash
cd /d/RhapsodiOS && git add tools/binrecon/binrecon/macho.py tools/binrecon/tests/test_macho.py && git commit -m "binrecon: decode non-scattered PowerPC relocations and fuse their pairs"
```

---

### Task 4: Decode scattered PowerPC relocations

**Files:**
- Modify: `tools/binrecon/binrecon/macho.py` (`_decode_ppc_relocations`)
- Test: `tools/binrecon/tests/test_macho.py`

**Interfaces:**
- Consumes: `macho_fixture.ppc_scattered`, `ppc_pair`, `PPC_RELOC_SECTDIFF`.
- Produces: semantic kinds `ppc-scattered-hi16-32-absolute`, `ppc-scattered-ha16-32-absolute`, `ppc-scattered-lo16-32-absolute`, `ppc-sectdiff-32-absolute`.

**Semantics:** a scattered entry's `r_value` identifies the target — the section containing it — and the field still holds the combined value. `addend = value - target_section["address"]`, the same rule as everywhere else. For `SECTDIFF` the principal's `r_value` is the left side, its scattered `PAIR`'s `r_value` is the right side, and the 32-bit field holds `left - right + addend`, so `addend = field - (left - right)`; the target is the section containing the left side.

- [ ] **Step 1: Write the failing test**

Append to `tools/binrecon/tests/test_macho.py` (extend the fixture import list with `PPC_RELOC_SECTDIFF` and `ppc_scattered`):

```python
def test_ppc_scattered_lo16_resolves_through_the_scattered_value(tmp_path):
    # __data sits at 0x1008; the field names 0x100C, four bytes into it.
    text = struct.pack(">II", 0x3860100C, 0x60000000)
    relocations = (
        ppc_scattered(0, 0x1008, kind=PPC_RELOC_LO16) + ppc_pair(0x0000)
    )

    document = read_macho(write_ppc(tmp_path, text, relocations))

    assert semantic(document)[0x1000] == {
        "address": 0x1000, "kind": "ppc-scattered-lo16-32-absolute",
        "target": "__DATA,__data", "addend": 4,
    }


def test_ppc_scattered_ha16_applies_the_signed_low_half(tmp_path):
    text = struct.pack(">II", 0x3C600002, 0x60000000)
    relocations = (
        ppc_scattered(0, 0x1000, kind=PPC_RELOC_HA16) + ppc_pair(0xFFFF)
    )

    document = read_macho(write_ppc(tmp_path, text, relocations))

    assert semantic(document)[0x1000] == {
        "address": 0x1000, "kind": "ppc-scattered-ha16-32-absolute",
        "target": "__TEXT,__text", "addend": 0xFFFF,
    }


def test_ppc_sectdiff_reports_the_difference_and_its_addend(tmp_path):
    # field = (__data - __text) + 8 = 0x1008 - 0x1000 + 8 = 0x10
    text = struct.pack(">II", 0x00000010, 0x60000000)
    relocations = (
        ppc_scattered(0, 0x1008, kind=PPC_RELOC_SECTDIFF)
        + ppc_scattered(0, 0x1000, kind=PPC_RELOC_PAIR)
    )

    document = read_macho(write_ppc(tmp_path, text, relocations))

    assert semantic(document)[0x1000] == {
        "address": 0x1000, "kind": "ppc-sectdiff-32-absolute",
        "target": "__DATA,__data", "addend": 8,
    }


def test_ppc_scattered_value_outside_every_section_is_rejected(tmp_path):
    text = struct.pack(">II", 0x3860100C, 0x60000000)
    relocations = (
        ppc_scattered(0, 0x9000, kind=PPC_RELOC_LO16) + ppc_pair(0x0000)
    )

    with pytest.raises(MachOFormatError, match="scattered relocation target"):
        read_macho(write_ppc(tmp_path, text, relocations))


def test_ppc_sectdiff_requires_a_scattered_pair(tmp_path):
    text = struct.pack(">II", 0x00000010, 0x60000000)
    relocations = (
        ppc_scattered(0, 0x1008, kind=PPC_RELOC_SECTDIFF) + ppc_pair(0x0000)
    )

    with pytest.raises(MachOFormatError, match="SECTDIFF requires a scattered PAIR"):
        read_macho(write_ppc(tmp_path, text, relocations))
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests/test_macho.py -q -k scattered
```

Expected: failures — scattered principals currently take the non-scattered target path and produce the wrong kind and target.

- [ ] **Step 3: Handle scattered entries in the decoder**

In `_decode_ppc_relocations`, before the value computation, branch on `entry["scattered"]`. Add this scattered arm inside the loop, immediately after the pair lookup and bounds check:

```python
            if entry["scattered"]:
                target_section = _ppc_section_of(sections, entry["value"])
                if target_section is None:
                    raise MachOFormatError(
                        f"{where}: scattered relocation target 0x{entry['value']:x} "
                        "is outside every section"
                    )
                word, field = _ppc_instruction(data, section, entry, where)
                low = word & 0xFFFF
                if kind == PPC_RELOC_SECTDIFF:
                    if pair is None or not pair["scattered"]:
                        raise MachOFormatError(
                            f"{where}: SECTDIFF requires a scattered PAIR entry"
                        )
                    difference = entry["value"] - pair["value"]
                    addend = _sign_extend(word, 32) - difference
                    name = "ppc-sectdiff-32-absolute"
                elif kind == PPC_RELOC_HI16:
                    addend = ((low << 16) | (pair["address"] & 0xFFFF)) - target_section["address"]
                    name = "ppc-scattered-hi16-32-absolute"
                elif kind == PPC_RELOC_HA16:
                    addend = ((low << 16) + _sign_extend(pair["address"] & 0xFFFF, 16)
                              - target_section["address"])
                    name = "ppc-scattered-ha16-32-absolute"
                elif kind == PPC_RELOC_LO16:
                    addend = (((pair["address"] & 0xFFFF) << 16) | low) - target_section["address"]
                    name = "ppc-scattered-lo16-32-absolute"
                else:
                    raise MachOFormatError(
                        f"{where}: unsupported scattered relocation type {kind}"
                    )
                semantic.append({"address": section["address"] + entry["address"],
                                 "kind": name, "target": target_section["name"],
                                 "addend": addend})
                raw.append(_ppc_raw(section, entry, name, target_section["name"],
                                    addend, field))
                raw[-1]["target_section_ordinal"] = target_section["ordinal"]
                if pair is not None:
                    raw.append(_ppc_pair_raw(section, entry, pair))
                    index += 1
                index += 1
                continue
```

Extend `_PPC_PAIRED` handling so `SECTDIFF` accepts a scattered `PAIR`: the existing pair lookup already rejects a missing pair, and the branch above rejects a non-scattered one.

- [ ] **Step 4: Run the tests**

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests/test_macho.py -q
```

Expected: all pass.

- [ ] **Step 5: Commit**

```bash
cd /d/RhapsodiOS && git add tools/binrecon/binrecon/macho.py tools/binrecon/tests/test_macho.py && git commit -m "binrecon: decode scattered PowerPC relocations and section differences"
```

---

### Task 5: Objective-C metadata in both byte orders

**Files:**
- Modify: `tools/binrecon/binrecon/macho.py:420-529` (`objc_methods_from_sections`, `objc_method_index`)
- Modify: `tools/binrecon/binrecon/cli.py:230`
- Test: `tools/binrecon/tests/test_objc_index.py`

**Interfaces:**
- Consumes: `binrecon.arch.I386`, `PPC`, `architecture_for_name`.
- Produces: `objc_methods_from_sections(payload, sections, endianness="little")`, `objc_method_index(path)` (reads the endianness from the image itself).

- [ ] **Step 1: Write the failing test**

In `tools/binrecon/tests/test_objc_index.py`, parameterize the builder and add a big-endian case. Replace `_build()`'s two `struct` calls and the test at the bottom:

```python
def _build(prefix="<"):
    """One class with an instance and a class method, plus one category."""
    blob = bytearray(0x200)

    def put(offset, *values):
        struct.pack_into(f"{prefix}{len(values)}I", blob, offset, *values)

    def put_str(offset, text):
        raw = text.encode("ascii") + b"\0"
        blob[offset:offset + len(raw)] = raw
```

and inside it replace the `cls_def_cnt`/`cat_def_cnt` pack with:

```python
    struct.pack_into(f"{prefix}HH", blob, 0x28, 1, 1)
```

Add:

```python
def test_recovers_methods_from_big_endian_metadata():
    index = objc_methods_from_sections(_build(">"), SECTIONS, endianness="big")

    assert index == {
        0x2000: ["-[Thing doThing]"],
        0x2100: ["+[Thing makeThing:]"],
        0x2200: ["-[Thing(Extra) extraThing]"],
        0x2300: ["+[Thing(Extra) makeExtra]"],
    }


def test_big_endian_metadata_read_as_little_endian_finds_nothing():
    assert objc_methods_from_sections(_build(">"), SECTIONS) == {}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests/test_objc_index.py -q
```

Expected: `TypeError: objc_methods_from_sections() got an unexpected keyword argument 'endianness'`.

- [ ] **Step 3: Parameterize the metadata walk**

In `tools/binrecon/binrecon/macho.py`, replace the three module-level Objective-C structs and the function signature:

```python
_MODULE_INFO_SECTION = "__OBJC,__module_info"
_OBJC_STRUCTS = {
    "little": {"module": struct.Struct("<4I"), "klass": struct.Struct("<8I"),
               "category": struct.Struct("<4I"), "counts": struct.Struct("<HH"),
               "list_header": struct.Struct("<2I"), "method": struct.Struct("<3I")},
    "big": {"module": struct.Struct(">4I"), "klass": struct.Struct(">8I"),
            "category": struct.Struct(">4I"), "counts": struct.Struct(">HH"),
            "list_header": struct.Struct(">2I"), "method": struct.Struct(">3I")},
}


def objc_methods_from_sections(payload, sections, endianness="little"):
```

Inside, bind `layout = _OBJC_STRUCTS[endianness]` and replace every hardcoded format: `_OBJC_MODULE` → `layout["module"]`, `_OBJC_CLASS` → `layout["klass"]`, `_OBJC_CATEGORY` → `layout["category"]`, `struct.unpack_from("<2I", …)` → `layout["list_header"].unpack_from(…)`, `struct.unpack_from("<3I", …)` → `layout["method"].unpack_from(…)`, `struct.unpack_from("<HH", …)` → `layout["counts"].unpack_from(…)`, and `struct.unpack_from(f"<{total}I", …)` → `struct.unpack_from(f"{'>' if endianness == 'big' else '<'}{total}I", …)`.

Update `objc_method_index` to take the byte order from the image:

```python
def objc_method_index(path):
    """Map each Objective-C method implementation address to its names."""
    document = read_macho(path)
    return objc_methods_from_sections(
        Path(path).read_bytes(), document["sections"],
        endianness=document["input"]["endianness"],
    )
```

- [ ] **Step 4: Run the tests**

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests/test_objc_index.py tools/binrecon/tests/test_cli.py -q
```

Expected: all pass. `binrecon/cli.py:230` needs no change because it calls `objc_method_index`, which now derives the byte order itself; confirm by reading that line.

- [ ] **Step 5: Commit**

```bash
cd /d/RhapsodiOS && git add tools/binrecon/binrecon/macho.py tools/binrecon/tests/test_objc_index.py && git commit -m "binrecon: read Objective-C metadata in either byte order"
```

---

### Task 6: IDA adapter chooses the processor from the profile

**Files:**
- Modify: `tools/binrecon/binrecon/adapters/ida.py:70-92` (`_mapping_manifest`), `:286` (argv)
- Test: `tools/binrecon/tests/test_ida_adapter.py`

**Interfaces:**
- Consumes: `binrecon.arch.architecture_for_name`.
- Produces: manifest `input` object gaining `"ida_processor"` alongside `architecture` and `endianness`; argv element `-p{processor}`.

- [ ] **Step 1: Write the failing test**

Append to `tools/binrecon/tests/test_ida_adapter.py`:

```python
def test_ppc_profile_selects_the_ppc_processor(tmp_path):
    input_path = tmp_path / "input.bin"
    input_path.write_bytes(build_macho_fixture(architecture="ppc", relocations=b""))
    profile = _profile(tmp_path, input_path)
    profile.document["architecture"] = "ppc"
    profile.document["endianness"] = "big"
    captured = {}

    def runner(argv, **kwargs):
        captured["argv"] = list(argv)
        raise RuntimeError("stop after argv capture")

    with pytest.raises(Exception):
        export_with_ida(profile, "reference", tmp_path / "out.json", runner=runner)

    assert captured["argv"][1:4] == ["-c", "-A", "-pppc"]


def test_ppc_mapping_manifest_carries_architecture_and_processor(tmp_path):
    input_path = tmp_path / "input.bin"
    input_path.write_bytes(build_macho_fixture(architecture="ppc", relocations=b""))
    profile = _profile(tmp_path, input_path)
    profile.document["architecture"] = "ppc"
    profile.document["endianness"] = "big"

    manifest = ida_host._mapping_manifest(profile, profile.reference_identity)

    assert manifest["input"]["architecture"] == "ppc"
    assert manifest["input"]["endianness"] == "big"
    assert manifest["input"]["ida_processor"] == "ppc"


def test_i386_mapping_manifest_still_names_metapc(tmp_path):
    input_path = tmp_path / "input.bin"
    input_path.write_bytes(build_macho_fixture())
    profile = _profile(tmp_path, input_path)

    manifest = ida_host._mapping_manifest(profile, profile.reference_identity)

    assert manifest["input"]["architecture"] == "i386"
    assert manifest["input"]["ida_processor"] == "metapc"
```

Simplify the first test if `_profile`'s existing helpers already capture argv — reuse the pattern at `tests/test_ida_adapter.py:97-140`, which asserts `argv[1:4] == ["-c", "-A", "-pmetapc"]`, rather than the ad-hoc runner above. The assertion that matters is `argv[3] == "-pppc"`.

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests/test_ida_adapter.py -q -k "ppc or metapc"
```

Expected: failures — the argv is `-pmetapc` and the manifest has no `ida_processor`.

- [ ] **Step 3: Take the processor from the descriptor**

In `tools/binrecon/binrecon/adapters/ida.py`, import the descriptor lookup:

```python
from binrecon.arch import ArchitectureError, architecture_for_name
```

Add a helper and use it in both places:

```python
def _architecture(profile):
    name = profile.document.get("architecture", "i386")
    try:
        return architecture_for_name(name)
    except ArchitectureError as error:
        raise IdaAdapterError(str(error)) from error
```

In `_mapping_manifest`, replace the `input` object:

```python
    architecture = _architecture(profile)
    manifest = {"schema_version": "ida-mapping-v1",
                "input": {"size": identity.size, "sha256": identity.sha256,
                          "architecture": architecture.name,
                          "endianness": architecture.endianness,
                          "ida_processor": architecture.ida_processor},
                "runs": runs}
```

In `export_with_ida`, replace the literal in argv:

```python
        argv = [
            str(executable), "-c", "-A", f"-p{_architecture(profile).ida_processor}",
            f"-o{database}", f"-L{native_log}",
            "-S" + _script_command(script.resolve(), temporary, identity, mapping,
                                    mapping_sha256),
            str(identity.path),
        ]
```

- [ ] **Step 4: Run the tests**

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests/test_ida_adapter.py -q
```

Expected: the new tests pass; existing manifest tests fail because the `input` key set grew. Update every affected expectation in `test_ida_adapter.py` (lines around 132, 678, 994, 1244) to include `"ida_processor": "metapc"`, and update `_validate_mapping`'s expected key set in Task 7 — until then those exporter tests fail, which is expected and resolved by the next task.

- [ ] **Step 5: Commit**

```bash
cd /d/RhapsodiOS && git add tools/binrecon/binrecon/adapters/ida.py tools/binrecon/tests/test_ida_adapter.py && git commit -m "binrecon: pick the IDA processor from the profile architecture"
```

---

### Task 7: Exporter validates against the manifest

**Files:**
- Modify: `tools/binrecon/adapters/ida/export_analysis.py:208-222` (`_validate_mapping` identity), `:395-410` (processor and endianness gate), `:662-666` (emitted identity)
- Test: `tools/binrecon/tests/test_ida_adapter.py`

**Interfaces:**
- Consumes: manifest field `input.ida_processor` from Task 6.
- Produces: `collect_analysis` accepting a PPC database when the manifest asks for one; emitted `input.architecture`/`input.endianness` taken from the manifest.

- [ ] **Step 1: Write the failing test**

Append to `tools/binrecon/tests/test_ida_adapter.py`, following the existing fake-module pattern used by `test_exporter_collects_and_sorts_ida_metadata`:

```python
def test_exporter_accepts_a_ppc_database_when_the_manifest_asks_for_one(tmp_path):
    modules = _fake_modules()  # the helper the existing exporter tests use
    modules["ida_ida"].inf_get_procname = lambda: "PPC"
    modules["ida_ida"].inf_is_be = lambda: True
    mapping = _mapping(architecture="ppc", endianness="big", ida_processor="ppc")

    document = export_analysis.collect_analysis(
        input_path, size, digest, modules=modules, mapping=mapping
    )

    assert document["input"]["architecture"] == "ppc"
    assert document["input"]["endianness"] == "big"


def test_exporter_rejects_a_little_endian_database_for_a_ppc_manifest(tmp_path):
    modules = _fake_modules()
    modules["ida_ida"].inf_get_procname = lambda: "metapc"
    modules["ida_ida"].inf_is_be = lambda: False
    mapping = _mapping(architecture="ppc", endianness="big", ida_processor="ppc")

    with pytest.raises(export_analysis.ExportError, match="processor"):
        export_analysis.collect_analysis(
            input_path, size, digest, modules=modules, mapping=mapping
        )


def test_exporter_rejects_a_big_endian_database_for_an_i386_manifest(tmp_path):
    modules = _fake_modules()
    modules["ida_ida"].inf_is_be = lambda: True
    mapping = _mapping(architecture="i386", endianness="little", ida_processor="metapc")

    with pytest.raises(export_analysis.ExportError, match="endian"):
        export_analysis.collect_analysis(
            input_path, size, digest, modules=modules, mapping=mapping
        )
```

Write `_fake_modules()` and `_mapping(...)` as module-level helpers extracted from the existing exporter tests' inline setup (`tests/test_ida_adapter.py:678-710` and `:994-1020`), so the new tests and the old ones share one builder. Keep the old tests' behaviour identical — they pass `architecture="i386", endianness="little", ida_processor="metapc"`.

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests/test_ida_adapter.py -q -k exporter
```

Expected: the PPC cases fail with `IDA processor is not metapc: 'PPC'`, and the manifest key-set check rejects `ida_processor`.

- [ ] **Step 3: Make the gate manifest-driven**

In `tools/binrecon/adapters/ida/export_analysis.py`, widen the manifest identity check:

```python
    identity = mapping["input"]
    if (not isinstance(identity, dict) or
            set(identity) != {"size", "sha256", "architecture", "endianness",
                              "ida_processor"} or
            identity["size"] != size or str(identity["sha256"]).upper() != digest or
            not isinstance(identity["architecture"], str) or
            identity["endianness"] not in ("little", "big") or
            not isinstance(identity["ida_processor"], str)):
        raise ExportError("artifact mapping identity does not match analyzed input")
```

Replace the processor and endianness assertions in `collect_analysis`:

```python
    expected_processor = mapping["input"]["ida_processor"]
    expected_big_endian = mapping["input"]["endianness"] == "big"
    if not isinstance(processor, str) or processor.lower() != expected_processor.lower():
        raise ExportError(
            f"IDA processor is not {expected_processor}: {processor!r}"
        )
    if exactly_32 is not True:
        raise ExportError("IDA database is not exactly 32-bit")
    if big_endian is not expected_big_endian:
        raise ExportError(
            "IDA database endianness does not match the requested "
            f"{mapping['input']['endianness']}-endian analysis"
        )
```

Note `_validate_mapping` runs before these lines and returns `runs`; keep reading the expectations from `mapping` directly, as above.

Emit the identity from the manifest:

```python
        "input": {
            "path": str(input_path.resolve()), "size": size, "sha256": digest,
            "architecture": mapping["input"]["architecture"],
            "endianness": mapping["input"]["endianness"],
        },
```

- [ ] **Step 4: Run the tests**

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests/test_ida_adapter.py -q
```

Expected: all pass, including the Task 6 tests that were failing.

- [ ] **Step 5: Run the full suite and commit**

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon -q
```

```bash
cd /d/RhapsodiOS && git add tools/binrecon/adapters/ida/export_analysis.py tools/binrecon/tests/test_ida_adapter.py && git commit -m "binrecon: validate the IDA database against the manifest architecture"
```

---

### Task 8: Ghidra and angr refuse non-i386 profiles

**Files:**
- Modify: `tools/binrecon/binrecon/adapters/ghidra.py:520` (`export_with_ghidra`)
- Modify: `tools/binrecon/binrecon/adapters/angr.py:279` (`export_with_angr`)
- Test: `tools/binrecon/tests/test_ghidra_adapter.py`, `tools/binrecon/tests/test_angr_adapter.py`

**Interfaces:**
- Consumes: profile `architecture`.
- Produces: `GhidraAdapterError` / `AngrAdapterError` raised before any subprocess runs.

- [ ] **Step 1: Write the failing tests**

Append to `tools/binrecon/tests/test_ghidra_adapter.py`:

```python
def test_rejects_non_i386_profile_before_running_ghidra(tmp_path):
    input_path = tmp_path / "input.bin"
    input_path.write_bytes(build_macho_fixture(architecture="ppc", relocations=b""))
    profile = _profile(tmp_path, input_path)
    profile.document["architecture"] = "ppc"

    def runner(*args, **kwargs):
        raise AssertionError("Ghidra must not be started for a ppc profile")

    with pytest.raises(GhidraAdapterError, match="i386-only"):
        export_with_ghidra(profile, "reference", tmp_path / "out.json", runner=runner)
```

Append the same shape to `tools/binrecon/tests/test_angr_adapter.py`, using that module's `_profile` helper, `AngrAdapterError`, and `export_with_angr`.

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests/test_ghidra_adapter.py tools/binrecon/tests/test_angr_adapter.py -q -k i386
```

Expected: `AssertionError: Ghidra must not be started for a ppc profile`, or a different error than the expected one.

- [ ] **Step 3: Add the guards**

At the top of `export_with_ghidra`, before `_configuration(profile)`:

```python
    architecture = profile.document.get("architecture", "i386")
    if architecture != "i386":
        raise GhidraAdapterError(
            f"the Ghidra adapter is i386-only and cannot analyse {architecture}"
        )
```

At the top of `export_with_angr`, the same with `AngrAdapterError`:

```python
    architecture = profile.document.get("architecture", "i386")
    if architecture != "i386":
        raise AngrAdapterError(
            f"the angr adapter is i386-only and cannot analyse {architecture}"
        )
```

- [ ] **Step 4: Run the tests**

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon -q
```

Expected: all pass.

- [ ] **Step 5: Commit**

```bash
cd /d/RhapsodiOS && git add tools/binrecon/binrecon/adapters/ghidra.py tools/binrecon/binrecon/adapters/angr.py tools/binrecon/tests/test_ghidra_adapter.py tools/binrecon/tests/test_angr_adapter.py && git commit -m "binrecon: reject non-i386 profiles in the Ghidra and angr adapters"
```

---

### Task 9: PowerPC profiles and README

**Files:**
- Create: `tools/binrecon/profiles/scsiserver-ppc.json`, `scsiserver-bundle-ppc.json`, `scsitape-ppc.json`, `scsitape-bundle-ppc.json`, `scsitape-preload-ppc.json`, `scsitape-postload-ppc.json`, `stblocksize-ppc.json`
- Modify: `tools/binrecon/README.md`
- Test: `tools/binrecon/tests/test_profile.py`

**Interfaces:**
- Consumes: nothing from earlier tasks at runtime; the profiles are data.
- Produces: seven reference-only IDA profiles validating against `profile-v1`.

- [ ] **Step 1: Write the failing test**

Append to `tools/binrecon/tests/test_profile.py`:

```python
import json
from pathlib import Path

import pytest

PPC_PROFILES = sorted(
    (Path(__file__).parents[1] / "profiles").glob("*-ppc.json")
)


def test_seven_ppc_profiles_exist():
    assert [path.name for path in PPC_PROFILES] == [
        "scsiserver-bundle-ppc.json", "scsiserver-ppc.json",
        "scsitape-bundle-ppc.json", "scsitape-postload-ppc.json",
        "scsitape-ppc.json", "scsitape-preload-ppc.json", "stblocksize-ppc.json",
    ]


@pytest.mark.parametrize("path", PPC_PROFILES, ids=lambda path: path.name)
def test_ppc_profiles_are_reference_only_ida_runs(path):
    document = json.loads(path.read_text(encoding="utf-8"))

    assert document["schema_version"] == "profile-v1"
    assert document["architecture"] == "ppc"
    assert document["endianness"] == "big"
    assert document["reference"] == {"path": "${BINRECON_REFERENCE}"}
    assert "rebuilt" not in document
    assert document["analyzers"]["ida"]["enabled"] is True
    assert document["analyzers"]["ghidra"]["enabled"] is False
    assert document["analyzers"]["angr"]["enabled"] is False
    assert document["output_dir"].startswith("../out/")
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests/test_profile.py -q -k ppc
```

Expected: `assert [] == [...]` — no profiles yet.

- [ ] **Step 3: Write the profiles**

Create each file with this content, substituting `name` and `output_dir` from the table below:

```json
{
  "schema_version": "profile-v1",
  "name": "<NAME>",
  "architecture": "ppc",
  "endianness": "big",
  "reference": {
    "path": "${BINRECON_REFERENCE}"
  },
  "analyzers": {
    "ida": {
      "enabled": true,
      "executable": "C:/Program Files/IDA Professional 9.2/idat.exe",
      "timeout_seconds": 900,
      "version": "9.2"
    },
    "ghidra": {
      "enabled": false,
      "executable": "D:/ghidra/support/analyzeHeadless.bat",
      "timeout_seconds": 900,
      "version": "12.1"
    },
    "angr": {
      "enabled": false,
      "executable": ".venv-binrecon/Scripts/python.exe",
      "timeout_seconds": 900,
      "version": "9.3.0"
    }
  },
  "comparison": {
    "acceptance": "normalized-functions",
    "ignore_metadata": [],
    "entry_points": []
  },
  "output_dir": "<OUTPUT_DIR>"
}
```

| File | `name` | `output_dir` |
| --- | --- | --- |
| `scsiserver-ppc.json` | `SCSIServer ppc reconstruction` | `../out/scsiserver-ppc` |
| `scsiserver-bundle-ppc.json` | `SCSIServer ppc loader bundle` | `../out/scsiserver-bundle-ppc` |
| `scsitape-ppc.json` | `SCSITape ppc reconstruction` | `../out/scsitape-ppc` |
| `scsitape-bundle-ppc.json` | `SCSITape ppc loader bundle` | `../out/scsitape-bundle-ppc` |
| `scsitape-preload-ppc.json` | `SCSITape ppc PreLoad helper` | `../out/scsitape-preload-ppc` |
| `scsitape-postload-ppc.json` | `SCSITape ppc PostLoad helper` | `../out/scsitape-postload-ppc` |
| `stblocksize-ppc.json` | `SCSITape ppc stblocksize helper` | `../out/stblocksize-ppc` |

- [ ] **Step 4: Run the test**

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests/test_profile.py -q
```

Expected: all pass.

- [ ] **Step 5: Document PowerPC support**

Append to `tools/binrecon/README.md`, after the "Install on Windows" section:

```markdown
## PowerPC targets

Binrecon reads 32-bit big-endian PowerPC Mach-O (`CPU_TYPE_POWERPC`, 18) in
addition to i386. Set `"architecture": "ppc"` and `"endianness": "big"` in the
profile; the reader picks its byte order from the file header and the IDA
adapter runs `idat -pppc`.

Only IDA analyses PowerPC. The Ghidra and angr adapters are i386-only and
reject a PowerPC profile before starting any subprocess, because they replay
the Mach-O layout and apply relocations themselves, and neither knows how to
encode PowerPC instruction fields.

PowerPC relocations are decoded as paired fixups. `extensions.macho.relocations`
keeps one record per file entry, `PAIR` entries included; the top-level
`relocations` list fuses each principal with its pair into a single record whose
addend is the reconstructed 32-bit value relative to its target. `HA16`'s signed
low half is applied, so `HA16` and `HI16` yield different addends for the same
halves.

The seven PowerPC profiles (`profiles/*-ppc.json`) are reference-only: the
repository cannot build PowerPC drivers today, so there is no rebuilt artifact
to compare against.
```

- [ ] **Step 6: Commit**

```bash
cd /d/RhapsodiOS && git add tools/binrecon/profiles tools/binrecon/README.md tools/binrecon/tests/test_profile.py && git commit -m "binrecon: add the PowerPC SCSI profiles and document PowerPC support"
```

---

### Task 10: Invariant check against the real binaries

**Files:**
- Create: `tools/binrecon/ppc_invariant_check.py`
- Test: `tools/binrecon/tests/test_ppc_invariant_check.py`

**Interfaces:**
- Consumes: `binrecon.macho.read_macho`.
- Produces:
  - `check_document(document) -> list[str]` returning violation messages, empty when clean
  - `main(argv=None) -> int`, exit 0 when clean, 1 otherwise
  - CLI: `python tools/binrecon/ppc_invariant_check.py --binary PATH [--analysis PATH]`

**What it asserts** (spec §5.2): every fused relocation whose target names a section resolves to an address inside that section, one byte past its end, or — for an external or absolute target — is reported as unresolved rather than failed; every `jbsr` island lands in `__TEXT,__text`; every `vanilla` relocation inside `__OBJC` points into `__OBJC` or `__TEXT,__cstring`; raw `PAIR` count equals the number of paired principals; and, when `--analysis` is given, every `__text` symbol address is a function start in the IDA document.

- [ ] **Step 1: Write the failing test**

Create `tools/binrecon/tests/test_ppc_invariant_check.py`:

```python
import struct

import pytest

from macho_fixture import (
    PPC_RELOC_HA16,
    PPC_RELOC_LO16,
    build_macho_fixture,
    ppc_pair,
    ppc_relocation,
)
from binrecon.macho import read_macho
from ppc_invariant_check import check_document


def _document(tmp_path, text, relocations):
    path = tmp_path / "ppc.o"
    path.write_bytes(build_macho_fixture(
        architecture="ppc", text=text, relocations=relocations,
    ))
    return read_macho(path)


def test_clean_image_reports_no_violations(tmp_path):
    text = struct.pack(">II", 0x38601008, 0x60000000)
    relocations = ppc_relocation(0, 2, kind=PPC_RELOC_LO16) + ppc_pair(0x0000)

    assert check_document(_document(tmp_path, text, relocations)) == []


def test_section_target_resolving_outside_its_section_is_reported(tmp_path):
    # Claims __DATA,__data but reconstructs 0x00050000, far outside it.
    text = struct.pack(">II", 0x38600000, 0x60000000)
    relocations = ppc_relocation(0, 2, kind=PPC_RELOC_LO16) + ppc_pair(0x0005)

    violations = check_document(_document(tmp_path, text, relocations))

    assert len(violations) == 1
    assert "__DATA,__data" in violations[0]
    assert "0x50000" in violations[0]


def test_missing_pair_records_are_reported(tmp_path):
    text = struct.pack(">II", 0x3C600002, 0x3863FFFF)
    relocations = ppc_relocation(0, 0, kind=PPC_RELOC_HA16, extern=1) + ppc_pair(0xFFFF)
    document = _document(tmp_path, text, relocations)
    document["extensions"]["macho"]["relocations"] = [
        entry for entry in document["extensions"]["macho"]["relocations"]
        if entry["kind"] != "ppc-pair-16-absolute"
    ]

    violations = check_document(document)

    assert any("PAIR" in violation for violation in violations)
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests/test_ppc_invariant_check.py -q
```

Expected: `ModuleNotFoundError: No module named 'ppc_invariant_check'`.

- [ ] **Step 3: Write the checker**

Create `tools/binrecon/ppc_invariant_check.py`:

```python
"""Cross-check a PowerPC Mach-O read against properties a correct decode implies.

Fixtures prove the decoder against hand-written arithmetic. This proves it
against the reference binaries: a byte-order or HA16 mistake scatters
reconstructed values outside every section, which shows up here.
"""

import argparse
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).parent))

from binrecon.macho import read_macho

_PAIRED_KINDS = ("hi16", "ha16", "lo16", "jbsr", "sectdiff")


def _sections(document):
    return [section for section in document["sections"] if section["size"]]


def _resolves(sections, name, address):
    for section in sections:
        if section["name"] == name:
            return section["address"] <= address <= section["address"] + section["size"]
    return False


def _section_of(sections, address):
    for section in sections:
        if section["address"] <= address < section["address"] + section["size"]:
            return section["name"]
    return None


def check_document(document):
    """Return a list of violation messages; empty means the decode is consistent."""
    violations = []
    sections = _sections(document)
    section_names = {section["name"] for section in sections}
    raw = document.get("extensions", {}).get("macho", {}).get("relocations", [])

    for relocation in document["relocations"]:
        target = relocation["target"]
        if target is None or target not in section_names:
            continue
        base = next(section["address"] for section in sections
                    if section["name"] == target)
        value = base + relocation["addend"]
        if not _resolves(sections, target, value):
            violations.append(
                f"{relocation['kind']} at 0x{relocation['address']:x} claims {target} "
                f"but reconstructs 0x{value:x}"
            )

    for entry in raw:
        if entry["kind"].startswith("ppc-jbsr"):
            island = entry["address"] + _island_displacement(entry)
            if _section_of(sections, island) != "__TEXT,__text":
                violations.append(
                    f"jbsr at 0x{entry['address']:x} branches to 0x{island:x}, "
                    "which is outside __TEXT,__text"
                )
        if entry["kind"].startswith("ppc-vanilla") and entry["section"].startswith("__OBJC"):
            owner = _section_of(sections, entry["addend"] + _base(sections, entry["target"]))
            if owner is not None and not (owner.startswith("__OBJC")
                                          or owner == "__TEXT,__cstring"):
                violations.append(
                    f"__OBJC pointer at 0x{entry['address']:x} points into {owner}"
                )

    principals = sum(1 for entry in raw
                     if any(f"ppc-{kind}" in entry["kind"] or
                            f"scattered-{kind}" in entry["kind"]
                            for kind in _PAIRED_KINDS))
    pairs = sum(1 for entry in raw if entry["kind"] == "ppc-pair-16-absolute")
    if principals != pairs:
        violations.append(
            f"{principals} paired principals but {pairs} PAIR records"
        )
    return violations


def _base(sections, name):
    for section in sections:
        if section["name"] == name:
            return section["address"]
    return 0


def _island_displacement(entry):
    word = int(entry["original_bytes"], 16)
    field = word & 0x03FFFFFC
    return field - 0x04000000 if field & 0x02000000 else field


def check_functions(document, analysis):
    """Report __text symbols that are not function starts in an IDA analysis."""
    starts = {function["address"] for function in analysis["functions"]}
    return [
        f"symbol {symbol['name']} at 0x{symbol['address']:x} is not a function start"
        for symbol in document["symbols"]
        if symbol["section"] == "__TEXT,__text" and symbol["address"] not in starts
    ]


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", required=True)
    parser.add_argument("--analysis")
    arguments = parser.parse_args(argv)

    document = read_macho(Path(arguments.binary))
    violations = check_document(document)
    if arguments.analysis:
        analysis = json.loads(Path(arguments.analysis).read_text(encoding="utf-8"))
        violations += check_functions(document, analysis)

    for violation in violations:
        print(violation)
    print(f"{len(document['relocations'])} fused relocations, "
          f"{len(violations)} violations")
    return 1 if violations else 0


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 4: Run the test**

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon/tests/test_ppc_invariant_check.py -q
```

Expected: `3 passed`.

- [ ] **Step 5: Run it against both reference drivers**

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe tools/binrecon/ppc_invariant_check.py --binary "C:/Users/raynorpat/Downloads/test/Drivers/ppc/SCSIServer.config/SCSIServer_reloc"
```

Expected: `0 violations`, with roughly 998 fused relocations for SCSIServer.

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe tools/binrecon/ppc_invariant_check.py --binary "C:/Users/raynorpat/Downloads/test/Drivers/ppc/SCSITape.config/SCSITape_reloc"
```

Expected: `0 violations`, roughly 990 fused relocations for SCSITape.

If either reports violations, do not weaken the check — the decoder is wrong. The likely culprits, in order: the `HA16` sign extension, the `LO16` pair being read as the low rather than the high half, and the non-scattered bitfield order.

- [ ] **Step 6: Commit**

```bash
cd /d/RhapsodiOS && git add tools/binrecon/ppc_invariant_check.py tools/binrecon/tests/test_ppc_invariant_check.py && git commit -m "binrecon: add the PowerPC relocation invariant check"
```

---

### Task 11: Acceptance run against all seven artifacts

**Files:**
- Modify: none (verification only; record results in the commit message if anything is fixed)
- Test: the whole suite plus real IDA runs

**Interfaces:**
- Consumes: everything above.
- Produces: analysis documents under `tools/binrecon/out/*-ppc/` (git-ignored) and a verified acceptance record.

- [ ] **Step 1: Validate every profile resolves its artifact**

For each profile, export `BINRECON_REFERENCE` and run `validate`. SCSIServer first:

```bash
cd /d/RhapsodiOS && BINRECON_REFERENCE="C:/Users/raynorpat/Downloads/test/Drivers/ppc/SCSIServer.config/SCSIServer_reloc" PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m binrecon validate --profile tools/binrecon/profiles/scsiserver-ppc.json
```

Expected: exit 0, printing the absolute path, size 51044, and SHA-256 `E813777748A4FAC9348AA1CF4E979863B96D75B09FDAC16DF586031499A122A2`.

Repeat for the other six, with these artifact paths and expected sizes:

| Profile | `BINRECON_REFERENCE` (under `C:/Users/raynorpat/Downloads/test/Drivers/ppc/`) | Size |
| --- | --- | --- |
| `scsiserver-bundle-ppc` | `SCSIServer.config/SCSIServer` | 8496 |
| `scsitape-ppc` | `SCSITape.config/SCSITape_reloc` | 47624 |
| `scsitape-bundle-ppc` | `SCSITape.config/SCSITape` | 8492 |
| `scsitape-preload-ppc` | `SCSITape.config/PreLoad` | 9060 |
| `scsitape-postload-ppc` | `SCSITape.config/PostLoad` | 21520 |
| `stblocksize-ppc` | `SCSITape.config/stblocksize` | 13408 |

- [ ] **Step 2: Analyze all seven with IDA**

```bash
cd /d/RhapsodiOS && BINRECON_REFERENCE="C:/Users/raynorpat/Downloads/test/Drivers/ppc/SCSIServer.config/SCSIServer_reloc" PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m binrecon analyze --profile tools/binrecon/profiles/scsiserver-ppc.json --output tools/binrecon/out/scsiserver-ppc/run-summary.json
```

Expected: exit 0; `tools/binrecon/out/scsiserver-ppc/` holds the IDA analysis document and the run summary. Repeat for the other six profiles with their artifact paths and output directories.

If IDA's loader refuses an artifact, record the exact message and stop — do not fall back to a raw binary load, since that would bypass the mapping-manifest integrity check. The i386 `MH_PRELOAD` drivers already load under IDA, so a refusal would be new information worth reporting.

- [ ] **Step 3: Re-run the invariant check with the IDA analysis**

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe tools/binrecon/ppc_invariant_check.py --binary "C:/Users/raynorpat/Downloads/test/Drivers/ppc/SCSIServer.config/SCSIServer_reloc" --analysis tools/binrecon/out/scsiserver-ppc/reference.analysis.json
```

Expected: `0 violations`. The `--analysis` argument adds the symbol-versus-function-start check; if IDA names a `__text` symbol that is not a function start, list those symbols in the acceptance notes rather than suppressing the check — they are candidates for the follow-on reconstruction's `boundary_disputed` bucket. Use the actual analysis filename that `analyze` wrote; list the directory first if unsure.

- [ ] **Step 4: Hand-verify ten relocation sites**

Disassemble and confirm the decoder's output at ten sites in `SCSIServer_reloc`, chosen to include: the `HA16`/`LO16` pair that loads `_server` (symbol value `0x408C`), the pair that loads `_sSessionIndex` (`0x4090`), at least one external `JBSR` (for example the call to `_objc_msgSendSuper` at `__text+0x410`, whose island is at `__text+0x448`), and one scattered pair near `__text+0x3538`. For each, check that the instruction's immediate halves combine to the address the fused record claims.

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -c "
from binrecon.macho import read_macho
d = read_macho(r'C:/Users/raynorpat/Downloads/test/Drivers/ppc/SCSIServer.config/SCSIServer_reloc')
for r in d['relocations'][:40]:
    print(hex(r['address']), r['kind'], r['target'], hex(r['addend']))
"
```

Expected: `ha16`/`lo16` records whose target plus addend is a real symbol or section address. Record the ten verified sites in the acceptance notes.

- [ ] **Step 5: Smoke-test the downstream path**

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m binrecon source-map --binary "C:/Users/raynorpat/Downloads/test/Drivers/ppc/SCSIServer.config/SCSIServer_reloc" --analysis tools/binrecon/out/scsiserver-ppc/reference.analysis.json --objc-methods --output tools/binrecon/out/scsiserver-ppc/source-map.prepared.json
```

Expected: exit 0 and Objective-C method names present in the output. Check `binrecon source-map --help` for the exact required arguments before running; supply whatever it requires.

```bash
cd /d/RhapsodiOS && BINRECON_REFERENCE="C:/Users/raynorpat/Downloads/test/Drivers/ppc/SCSIServer.config/SCSIServer_reloc" PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m binrecon analyze --profile tools/binrecon/profiles/scsiserver-ppc.json --ledger tools/binrecon/out/scsiserver-ppc/ledger.json --output tools/binrecon/out/scsiserver-ppc/run-summary.json
```

Expected: exit 0 and a ledger written.

- [ ] **Step 6: Run the full suite one last time**

```bash
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m pytest tools/binrecon -q
```

Expected: all pass, zero failures.

- [ ] **Step 7: Record the acceptance results**

Append a short "PowerPC acceptance" section to `tools/binrecon/README.md` listing, for each of the seven artifacts, the exit status of `analyze` and the invariant check's violation count. Then commit:

```bash
cd /d/RhapsodiOS && git add tools/binrecon/README.md && git commit -m "binrecon: record the PowerPC acceptance run for the SCSI artifacts"
```

---

## Self-Review Notes

- Spec §2.1–2.6 map to Tasks 1, 2, 6, 7, 8, 9; §3 maps to Tasks 3 and 4; §4 error handling is exercised by the rejection tests in Tasks 2, 3, 4, 7, 8; §5.1 is Tasks 2–5, §5.2 is Task 10, §5.3–5.4 are Task 11; §6 deliverables are all covered, with `objc` (§2.2) in Task 5.
- Signature change to watch: Task 2 gives `_read_relocations` a fourth parameter and a single-list return; Task 3 changes that return to a `(semantic, raw)` tuple and renames the i386 body. Any task executed out of order must honour Task 3's tuple form.
- The manifest key set grows in Task 6 and is accepted in Task 7. Between those two commits the exporter tests fail; that is called out in Task 6 Step 4 and resolved in Task 7 Step 4. If you need every commit green, do Tasks 6 and 7 as a single commit.
