# PowerPC support in binrecon

Teach `tools/binrecon` to read big-endian PowerPC Mach-O and to drive IDA against
it, so that the PPC `SCSIServer` and `SCSITape` drivers can be reconstructed the
same way the i386 drivers were.

This is the first of three specs. It delivers tooling only: no driver source is
touched, and no source map or ledger is produced for either driver. Those are
the two follow-on specs (§7).

## Motivation

`src/drvSCSIServer` and `src/drvSCSITape` are unverified reimplementations —
`IOSCSISession.m` (2627 lines), `SCSIServer.m` (431), `SCSITape.m` (1198),
`SCSITapeKern.m` (747), plus three user-space helpers — that have never been
compared against Apple's shipped binaries. Both drivers ship only for PPC in the
reference set; there is no i386 `SCSIServer.config` or `SCSITape.config` to fall
back on, so the reconstruction cannot avoid PowerPC.

binrecon is i386/little-endian at every layer that matters:

- `binrecon/macho.py` rejects any magic that is not little-endian `0xFEEDFACE`
  and any CPU type that is not `CPU_TYPE_I386`; every `struct.Struct` is `"<"`;
  `_read_relocations` extracts the `relocation_info` bitfields in the order the
  little-endian ABI lays them out, and emits `i386-`-prefixed kinds.
- `binrecon/adapters/ida.py` invokes IDA with `-pmetapc`, and
  `adapters/ida/export_analysis.py` refuses to export unless the database
  reports `metapc` and little-endian.
- `binrecon/adapters/ghidra.py` and `adapters/ghidra/ExportAnalysis.java` pin
  `x86:LE:32:default` and apply relocations with a whole-word little-endian
  patcher.

Every analyzer path — the IDA one included — calls `read_macho`, because that is
what produces the mapping manifest proving IDA analysed the bytes we think it
did. So the reader port is unavoidable regardless of which analyzer is used.

## 1. Scope

### 1.1 Reference artifacts

All seven files under `C:\Users\raynorpat\Downloads\test\Drivers\ppc`, CPU type
18 (PowerPC), big-endian, 32-bit:

| Artifact | Type | Size | SHA-256 | `__text` | Symbols | `__text` symbols | Relocs |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `SCSIServer.config/SCSIServer_reloc` | MH_PRELOAD | 51044 | `E813777748A4FAC9348AA1CF4E979863B96D75B09FDAC16DF586031499A122A2` | 13744 | 159 | 69 | 1781 |
| `SCSITape.config/SCSITape_reloc` | MH_PRELOAD | 47624 | `ABB8D7E5FDEB9188A4C58D10AE6A7A1313A79EFBE49513AD3804E386BB65131A` | 11356 | 89 | 51 | 1692 |
| `SCSIServer.config/SCSIServer` | MH_BUNDLE | 8496 | `9B1ABF19321F183BF3DD05FE6BDC5CD8F6E3BDAFC808A47C05386EACC51D1665` | 80 | 8 | 3 | 0 |
| `SCSITape.config/SCSITape` | MH_BUNDLE | 8492 | `70543A05980576D06E548F4FBA94A23CABF5A9CC16E3A6DEFB89E6FEBA262C72` | 80 | 8 | 3 | 0 |
| `SCSITape.config/PreLoad` | MH_EXECUTE | 9060 | `177355F05BDCBD6EDE34121F93E6B6A176B105ACF8EAD1945761A9E1D3BFB60A` | 824 | 29 | 7 | 0 |
| `SCSITape.config/PostLoad` | MH_EXECUTE | 21520 | `A6025294E3E1AB96270BBE3AFAD73A3885C7C5F44644241E44DD553632699F87` | 1140 | 33 | 7 | 0 |
| `SCSITape.config/stblocksize` | MH_EXECUTE | 13408 | `E36D1320E5543E9F8B46D522D19150DC6BA21B348C6ECAB8D13AE9CF83BC7648` | 1604 | 37 | 10 | 0 |

Both `_reloc` drivers retain full symbol tables including Objective-C method
names, so address-to-name resolution is exact rather than inferred. They also
carry a custom `Loaded Server` segment (four sections: server name, load
commands, instance variables, version) alongside `__TEXT`, `__DATA`, and a
twenty-section `__OBJC`.

The three `MH_EXECUTE` helpers are dyld executables and bring load commands the
reader has not seen before: `LC_LOAD_DYLINKER`, `LC_LOAD_DYLIB`,
`LC_TWOLEVEL_HINTS`, `LC_DYSYMTAB`, plus `__PAGEZERO`, `__la_symbol_ptr`,
`__nl_symbol_ptr`, and `__picsymbol_stub` sections.

`MH_PRELOAD` itself is not new: the i386 `_reloc` drivers already analysed under
IDA are `MH_PRELOAD` too. Only the architecture changes.

### 1.2 Analyzer

IDA Professional 9.2 only, matching the existing IDA-only profiles
(`vga-psdrvr`, `beep`). IDA's native Mach-O loader handles the PPC image and its
relocations, so no hand-written relocation application is needed.

### 1.3 Out of scope

Ghidra and angr stay i386-only. Enabling Ghidra would mean rewriting
`ExportAnalysis.java`'s relocation application to encode PowerPC instruction
fields — 24-bit branch displacements, 16-bit high/low/adjusted immediates, PAIR
pairing, section differences — and that is the riskiest possible place to start.
A PPC profile that enables either adapter is rejected with a clear error.

No i386 behaviour changes. `read_macho` output for every existing i386 fixture
and reference must be identical after the port; the only permitted difference is
the wording of two error messages that name i386 explicitly (§2.2).

No rebuilt-artifact comparison: the repository cannot build PPC drivers today
(`src/drivers-ppc/README` lists every PPC driver as "needs compiled and then
tested"), so PPC profiles are reference-only, as the i386 report passes were.

No driver source changes, no source map, no ledger, no divergence report.

## 2. Architecture

### 2.1 `binrecon/arch.py`

One descriptor per architecture, and the only place that knows a per-architecture
fact:

| Field | i386 | ppc |
| --- | --- | --- |
| `name` | `i386` | `ppc` |
| `endianness` | `little` | `big` |
| `struct_prefix` | `<` | `>` |
| `cpu_type` | 7 | 18 |
| `ida_processor` | `metapc` | `ppc` |
| `relocation_decoder` | `decode_i386` | `decode_ppc` |

Lookup is by CPU type for the reader and by profile `architecture` string for the
adapters; the two must agree or the run fails.

### 2.2 `binrecon/macho.py`

The header is read twice: once to identify magic and CPU type (which requires
trying both byte orders), then with the selected descriptor's struct set. Magic
must be `0xFEEDFACE` in the descriptor's byte order; the swapped-magic form
(`0xCEFAEDFE`) is rejected with a message naming what was found.

Everything else — the `_checked_slice` bounds discipline, segment and section
walking, symbol table reading, content hashing, the `analysis-v1` document shape
— stays one shared code path, with `struct` layouts taken from the descriptor.
`input.architecture` and `input.endianness` come from the descriptor instead of
the current hardcoded `"i386"` / `"little"`. Two i386-specific error messages
("exceeds i386 address width", "length code 3 is invalid for i386") become
architecture-neutral.

`objc_methods_from_sections` and `objc_method_index` take the descriptor too, so
`binrecon source-map --objc-methods` works on PPC. The `__OBJC` metadata walk is
otherwise unchanged.

### 2.3 `binrecon/adapters/ida.py`

`-pmetapc` becomes `-p{descriptor.ida_processor}`. The mapping manifest — which
the adapter already writes, hashes, and hands to the in-IDA script — gains the
expected processor name and endianness. The adapter continues to build the
manifest from `read_macho`.

### 2.4 `adapters/ida/export_analysis.py`

The hardcoded `metapc` and not-big-endian assertions are replaced by comparisons
against the manifest values. This stays a hard gate: if IDA's database disagrees
with what the host requested, the export fails rather than producing an analysis
document for the wrong architecture. The processor comparison remains
case-insensitive (IDA reports `PPC` for the big-endian PowerPC processor). The
32-bit check is unchanged. `input.architecture` and `input.endianness` in the
emitted document come from the manifest.

### 2.5 Ghidra and angr adapters

Each gains one guard: if the profile's architecture is not `i386`, raise
`GhidraAdapterError` / `AngrAdapterError` saying the adapter is i386-only. The
existing `x86:LE:32:default` language checks stay exactly as they are.

### 2.6 Profiles

No schema change. `profile.py` already carries `architecture` and `endianness`,
and `runner.py` already maps `ppc` to big-endian. PPC profiles set
`"architecture": "ppc"`, `"endianness": "big"`, enable only `ida`, and use
`${BINRECON_REFERENCE}` for the artifact path.

## 3. PowerPC relocation decoding

### 3.1 Bitfield order

On big-endian, the second word of a non-scattered `relocation_info` lays out as
`r_symbolnum` in bits 31–8, `r_pcrel` at bit 7, `r_length` at bits 6–5,
`r_extern` at bit 4, `r_type` at bits 3–0 — the mirror of the little-endian
extraction the reader performs today. Scattered entries keep the same shape as
i386: `r_scattered` at bit 31, `r_pcrel` at 30, `r_length` at 29–28, `r_type` at
27–24, `r_address` at 23–0, with the second word holding `r_value`.

Reading these in the little-endian order produces plausible-looking garbage
rather than an error, so §5.1 gives it a dedicated fixture.

### 3.2 Types present

Decoded with the correct layout, the two `_reloc` drivers contain:

| Type | SCSIServer | SCSITape |
| --- | --- | --- |
| `PPC_RELOC_PAIR` | 783 | 702 |
| `PPC_RELOC_LO16` | 302 | 252 |
| `PPC_RELOC_VANILLA` | 215 | 260 |
| `PPC_RELOC_JBSR` | 173 | 198 |
| `PPC_RELOC_HA16` | 150 | 152 |
| `PPC_RELOC_HI16` | 138 | 94 |
| scattered `LO16` | 10 | 3 |
| scattered `HA16` | 10 | 3 |
| scattered `SECTDIFF` | 0 | 14 |
| scattered `PAIR` | 0 | 14 |

All entries have `r_length` 2 (four-byte field). There are no `BR14`, `BR24`, or
`LO14` relocations. The decoder still handles the full documented type set where
the encoding is unambiguous, and raises `MachOFormatError` — naming the type,
section, and file offset — for anything it does not cover, in keeping with the
reader's existing habit of refusing rather than guessing.

### 3.3 Pairing invariant

Every `HI16`, `HA16`, `LO16`, and `JBSR` entry is immediately followed by its
`PAIR`. The counts above satisfy this exactly: SCSIServer has 763 non-scattered
principals plus 20 scattered `LO16`/`HA16` principals against 783 `PAIR`
entries; SCSITape has 696 plus 6 against 702, with its 14 scattered `SECTDIFF`
entries matched by 14 scattered `PAIR` entries. A principal without its pair, or
a pair without its principal, is an error.

### 3.4 Field extraction

The patched field is not a whole word. For `HI16`, `HA16`, and `LO16` it is the
low 16 bits of the 32-bit instruction at `r_address`; for `JBSR` it is the 24-bit
branch displacement. The decoder extracts and reports the sub-word field, while
`original_bytes` records the full four-byte instruction word so a reviewer can
see the instruction.

### 3.5 Value reconstruction

The principal's field holds one half of a 32-bit value and its `PAIR`'s
`r_address` field holds the other:

- `HI16` + `PAIR`: `value = (high << 16) | (low & 0xFFFF)`
- `HA16` + `PAIR`: `value = (high << 16) + sign_extend16(low)`
- `LO16` + `PAIR`: the pair carries the high half; combined as for `HI16`
- `JBSR` + `PAIR`: the pair carries the true target address, while the branch
  field points at a jump island
- scattered `SECTDIFF` + `PAIR`: `value = left_r_value - right_r_value + field`

The `HA16` adjustment is the one that bites: ignoring it leaves roughly half the
high-half relocations off by `0x10000`, silently, and only at some addresses.

Addends follow the existing i386 rule unchanged — subtract the target section's
base address for section and local targets, leave the value as-is for external
symbol targets.

### 3.6 Document representation

The two existing views of relocations keep their existing meanings:

- `extensions.macho.relocations` records one entry per raw file entry, `PAIR`
  entries included, with type, length, pc-relative flag, extern flag, scattered
  flag, and `original_bytes`. This round-trips the file.
- `relocations` — what `compare` and `consensus` consume — records one fused
  entry per logical fixup, addressed at the principal, carrying the target
  symbol or section name and the single reconstructed addend.

Fused kinds: `ppc-vanilla-32-absolute`, `ppc-hi16-32-absolute`,
`ppc-ha16-32-absolute`, `ppc-lo16-32-absolute`, `ppc-jbsr-24-pc-relative`,
`ppc-scattered-hi16-32-absolute`, `ppc-scattered-ha16-32-absolute`,
`ppc-scattered-lo16-32-absolute`, `ppc-sectdiff-32-absolute`.

## 4. Error handling

Every rejection names what was found and where. Unsupported magic or CPU type
reports the actual value and the byte order it was read in. An undecodable
relocation type reports type, section name, and file offset. A `PAIR` without its
principal, or a principal without its pair, is an error naming both offsets. A
reconstructed value that cannot be attributed to a section or symbol is reported,
not silently zeroed.

The IDA export script keeps failing hard on a processor or endianness mismatch
against the manifest. The Ghidra and angr adapters fail immediately on a
non-i386 profile rather than analysing it wrongly.

## 5. Verification

### 5.1 Fixtures and unit tests

`tests/macho_fixture.py` takes an architecture parameter and can emit big-endian
PPC images. New fixtures cover:

- `MH_PRELOAD` with `__OBJC` and a custom named segment
- `MH_BUNDLE`
- dyld `MH_EXECUTE` with `__PAGEZERO`, `__la_symbol_ptr`, `__nl_symbol_ptr`,
  `__picsymbol_stub`, `LC_DYSYMTAB`, `LC_LOAD_DYLINKER`, `LC_LOAD_DYLIB`,
  `LC_TWOLEVEL_HINTS`
- one relocation fixture per decoded type, with hand-computed expected addends,
  including an `HA16` case whose low half is negative (so an unadjusted decode
  is off by `0x10000`) and a `HI16` case with the same halves (so the two
  cannot be confused)
- a bitfield-order fixture: an entry whose little-endian reading yields a
  different, self-consistent-looking type and symbol index than its correct
  big-endian reading
- malformed cases: unpaired principal, orphan `PAIR`, unsupported type,
  swapped-magic header

`tests/test_macho.py`, `test_ida_adapter.py`, and `test_objc_index.py` gain PPC
cases. Every existing i386 test stays untouched and must stay green; that is the
proof the port did not shift i386 output.

### 5.2 Invariant check on the real binaries

Fixtures only prove the decoder against arithmetic written by the same person who
wrote the decoder. A check script asserts properties that hold only if the decode
is right, over both `_reloc` drivers:

- every fused `HI16`/`HA16`/`LO16` value lands inside a mapped section or names a
  defined symbol
- every `JBSR` island target lies inside `__TEXT,__text`
- every `VANILLA` relocation in `__OBJC` points at a `__OBJC` or `__cstring`
  address
- the §3.3 pairing counts hold exactly
- symbol addresses from the symbol table coincide with IDA's function starts

A bit-order or `HA16` error scatters values outside every section and fails this
loudly.

### 5.3 Hand verification

Ten `lis`/`addi`/`ori` sites are disassembled and checked by hand against the
decoder's output, chosen to include the loads of `_server` and `_sSessionIndex`
in SCSIServer, at least one `JBSR` to an external symbol, and one scattered
`SECTDIFF` in SCSITape's `__TEXT,__const`.

### 5.4 Acceptance

The spec is done when all of the following hold, with output shown:

1. `binrecon validate` and `binrecon analyze` exit 0 for all seven PPC profiles.
2. The emitted `analysis-v1` documents validate against the schema.
3. The §5.2 invariant check passes on both `_reloc` drivers.
4. The §5.3 hand verification agrees at all ten sites.
5. `pytest` is green across the whole `tools/binrecon` suite, i386 tests
   included and unmodified.
6. `binrecon source-map --binary <SCSIServer_reloc> --objc-methods` runs and
   names Objective-C methods, and `binrecon analyze --ledger` creates a ledger
   from a PPC analysis. (Smoke test of the downstream path; the map's content
   is spec 2's subject.)

## 6. Deliverables

| Path | Change |
| --- | --- |
| `tools/binrecon/binrecon/arch.py` | new — architecture descriptors |
| `tools/binrecon/binrecon/macho.py` | parameterized by descriptor; `decode_ppc` added |
| `tools/binrecon/binrecon/adapters/ida.py` | processor and endianness from descriptor, into the manifest |
| `tools/binrecon/adapters/ida/export_analysis.py` | manifest-driven processor/endianness gate |
| `tools/binrecon/binrecon/adapters/ghidra.py` | reject non-i386 profiles |
| `tools/binrecon/binrecon/adapters/angr.py` | reject non-i386 profiles |
| `tools/binrecon/profiles/scsiserver-ppc.json` | new (and `scsiserver-bundle-ppc`, `scsitape-ppc`, `scsitape-bundle-ppc`, `scsitape-preload-ppc`, `scsitape-postload-ppc`, `stblocksize-ppc`) |
| `tools/binrecon/tests/macho_fixture.py` | architecture parameter, PPC images |
| `tools/binrecon/tests/test_macho.py`, `test_ida_adapter.py`, `test_objc_index.py` | PPC cases |
| `tools/binrecon/ppc_invariant_check.py` | new — §5.2 check |
| `tools/binrecon/README.md` | PPC section; states plainly that Ghidra and angr remain i386-only |

Reference binaries stay outside git and are addressed through
`${BINRECON_REFERENCE}`. Analysis output goes under `tools/binrecon/out/`, which
is already ignored.

## 7. Follow-on specs

- **Spec 2 — SCSIServer reconstruction.** Map all 69 `__text` symbols of
  `SCSIServer_reloc` to `SCSIServer.m` and `IOSCSISession.m`, produce
  `reconstruction/{source-map.json,ledger.json,divergences.md}` under
  `src/drvSCSIServer`, then a fix pass.
- **Spec 3 — SCSITape reconstruction.** The same for `SCSITape_reloc`'s 51
  `__text` symbols across `SCSITape.m` and `SCSITapeKern.m`, plus the three
  user-space helpers against `PreLoad`, `PostLoad`, and `stblocksize`.
