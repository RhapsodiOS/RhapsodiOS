# pswrap Reconstruction Design

**Status:** implemented and verified on 2026-09-29; widened against the
reference on 2026-09-30 (see *Widening pass* below).

## Goal

Reconstruct Rhapsody's `/usr/bin/pswrap` (the Display PostScript wrapper
generator) in-tree under `src/Commands/pswrap.tproj`, driven by the
`tools/binrecon` toolchain, using NeXTDPS's `pswrap-117.0.2` source as the
reconstruction base, and verify the result against the shipped reference.

## Evidence

| Item | Value |
|---|---|
| Reference | `C:\Users\raynorpat\Downloads\test\pswrap` |
| Reference size / SHA-256 | 107756 / `8276BAC9E9EF09B6841DEDBEB9E61AF38E9BDF2531348F82FC7720C0C2CA825D` |
| Reference format | Mach-O i386 executable, `NOUNDEFS|DYLDLINK|PREBOUND` |
| Base source | `https://github.com/johnsonjh/NeXTDPS` `pswrap-117.0.2` |
| binrecon profile | `tools/binrecon/profiles/pswrap.json` |
| binrecon output | `tools/binrecon/out/pswrap/` (ignored) |

The reference binary carries the exact `PSW_VERSION` string from the base
source (`V1.009  Wed Apr 19 17:50:24 PDT 1989`), the `unix` (not `mac`)
`PSW_OS`, and the `<dpsclient/dpsfriends.h>` friends file. It is also
byte-for-byte the same size as the reference machine's own
`/usr/bin/pswrap` (107756 bytes), which is the strongest single piece of
evidence that the base source is the right revision.

## Toolchain gaps closed in binrecon

Two defects blocked analyzing a standalone `MH_EXECUTE` with IDA 9.4:

1. **Synthetic `ABS` segment.** IDA fabricates a `SEG_ABSSYM`/class `"ABS"`
   segment for absolute symbols in an executable; it has no file backing, so
   `adapters/ida/export_analysis.py` rejected it as *"segment backing is not
   wholly covered by one artifact mapping run"*. It is now classified with
   BSS/XTRN as synthetic zero-fill.
2. **Unnamed functions.** `idautils.Names()` omits IDA's default `sub_XXXX`
   function names, so 112 of 138 functions exported with an empty `names`
   list and `source-map-v1`, which requires at least one name, refused to
   run. The exporter now falls back to `ida_name.get_name` for unnamed
   functions.

Both have regression tests in `tools/binrecon/tests/test_ida_adapter.py`.

## Build integration

`src/Commands/pswrap.tproj` is a Project Builder tool project
(`Makefile`, `Makefile.preamble`, `Makefile.postamble`, `PB.project`) that
rbuild builds for i386 with the existing toolchain. Four decisions were
required, each established from the reference binary rather than assumed:

- **`NeXT` must be undefined.** rbuild's `RC_CFLAGS` always adds `-DNeXT`,
  but the reference contains psw.c's non-`NeXT` `(char *)pad` padding
  templates and `char pad[3]`, and no `(char *)_dpsCtxt` template.
  `Makefile.preamble` adds `-UNeXT` after `RC_CFLAGS`, which wins.
- **`os_unix` and `os_mach`.** These select the unix `PSW_OS`, the `-S`
  shlib option and pswfile.c's `os_mach` branches.
- **Pre-generated parser and lexer.** rbuild's build sysroot has no yacc
  or lex, so `pswparser.c`, `y.tab.h` and `lexer.c` are generated once with
  the guest's own NeXT-era `yacc` and `lex` and checked in. `Makefile.postamble`
  gives them empty rules so the pb_makefiles `.y.c`/`.l.c` suffix rules
  cannot fire.
- **`lex -l`.** flex's lex-compatibility mode is what supplies the
  `yylineno` the lexer relies on; plain `flex` leaves it undefined.

## Source reconciliation against the reference

The base source is close but not identical to the revision Apple shipped.
The differences below were found by comparing generated output and are now
reconstructed in the in-tree source:

- **`pswsemantics.c`:** the reference emits
  `  if (0) *pad = 0;    /* quiets compiler warnings */` as the last
  statement of any wrap whose `-p` padding local is declared. `FinalizePSWrapDef`
  now emits it under the same `pad` guard.
- **`lexer.l`:** the base `yywrap` reports `end of input file/missing endps`
  when the scanner is not in state 0 at EOF, testing AT&T lex's
  `yybgin != (yysvec+1)` state vector (flex has no such globals). The
  reference has no such message at all: it says nothing when the input runs
  out, whether or not a definition was left open, and lets the parser report
  the syntax error that follows. `yywrap` now only handles the `feof`
  continuation.
- **`main.c` `-p`:** the base's non-`NeXT` `-p` branch did `pad++`, which
  never disabled padding. The reference clears the flag (`pad = 0`), matching
  `pswrap.1`'s "disables padding of strings".
- **`psw.c` ANSI prototypes:** the base omits `const` on input strings and
  arrays. The reference declares a string or array *input* `const` (never a
  scalar and never an output), so `EmitANSIPrototypes` now does too.
- **`psw.c` user names:** by default the reference packs every user-name
  body inline with the literal string bodies in `_dpsQ` (or `_dpsQ1`) and
  gives each `DPS_LITERAL|DPS_NAME` / `DPS_EXEC|DPS_NAME` tag a length and
  offset, exactly as it does for strings. The pool is filled in body order
  (so it is reverse source order), duplicate text is stored once, and
  constants name tags need no runtime mapping. The base's `DPSMapNames`
  machinery survives in the reference behind the `-n` option; see the
  widening pass.
- **`psw.c` numstrings:** the base writes a hand-built `HNumHeader` plus the
  body and its pad via three `DPSWriteStringChars` calls. The reference emits
  one `DPSWriteNumString(ctx, dps_t<T>, arr, count, scale)` call and no
  header. `CTypeToResultType` gained the four `T_*NUMSTR` cases and the
  vendored `dpsfriends.h` gained the `DPSWriteNumString` macro it was missing.

## Widening pass (2026-09-30)

A second differential campaign ran a wider corpus with a wider option set,
and the reference was decompiled with IDA to settle what the extra inputs
could not. It found four options the base source does not have, one error
message the base prints and the reference does not, and two size-accounting
bugs. All are reconstructed above/in-tree:

- **`-H <dir>`** emits `#include <dir/dpsfriends.h>` instead of the
  `FRIENDSFILE` literal. `-I <text>` makes the generated header emit
  `#include <text>` after its `#define`. **`-e <text>`** replaces the
  `extern` qualifier in generated prototypes (default `extern`).
  **`-n`** turns inline name packing off, restoring the base's
  `_dps_names`/`_dps_nameVals`/`_dpsCodes`/`DPSMapNames` machinery with
  `_dpsp[i].val.nameVal = _dpsCodes[i]` copies under `-a`. The reference's
  Usage text does not document any of the four, so neither does ours.
- **User-name emission is gated, not replaced.** `SetNameTag` pools a
  non-well-known name only while inline packing is on; with `-n` it conses
  the name onto `nameTokens` and `EmitFieldConstructor` leaves the tag
  `0, 0, 0`. A pool of names therefore also forces `writable`, and `-n`
  removes the name bytes from the sizes.
- **Constant-subscript string sizing.** The base rounds the *running* total
  up to four bytes after adding a constant subscript, and does it for
  numstrings too. The reference rounds the *subscript value* up instead, and
  never rounds a numstring (whose four-byte header the library pads itself).
  Both `CheckSize` and `BuildTypesAndAssignAddresses` follow the reference,
  which is what makes a numstring or a const array beside a pooled name come
  out 1-3 bytes smaller than the base computed.
- **Static splitting.** `ConstructStatics` re-derives "this wrap has an input
  array" from the tokens and counted a subscripted numstring as one, so a
  numstring plus a pooled name was split into `_dpsQ`/`_dpsQ1` while the
  reference keeps one `_dpsQ`. Numstrings are now excluded there too.
- **`_dpsCodes` declaration.** Under `-a` the `-n` path needs
  `static long int _dpsCodes[<n>] = {-1};` from `EmitLocals`; it was missing.

## Verification

Built on a private `-snapshot` QEMU i386 guest. The rebuilt and the
reference `/usr/bin/pswrap` were run on the same input with the same `-h`
and `-o` names:

- generated **header: byte-identical**
- generated **C body: byte-identical**

A differential harness drives the inputs through flag combinations
(`-a`, `-r`, `-p`, `-b`, `-s`, `-n`, `-e`, `-H`, `-I`, and pairs), diffing
`out.h`, `out.c`, stdout, stderr and the exit status on every pair. The
inputs exercise well-known and user names, `-p` padding, `numstring` (all
four element types, constant and variable subscripts, and constant and
variable scales), literal and hex string bodies, user-object arrays, split
statics, duplicate text, ANSI prototypes, reentrant statics, output
arguments, context arguments, the large header, raised token counts, escaped
and hex string bodies, every radix form, and truncated input in five scanner
states. **499 pairs are identical**, plus 20 targeted size cases and 7
end-of-input cases, including the byte-identical generated code above.

`binrecon analyze` publishes analyses for both artifacts and both analyzers
(IDA 9.4 and angr 9.3.0) from the current rebuild
(`F6A041A48122EA8CA70417608167B94AE26FB5F183C3512071C34DC67629ECDD`), and
`binrecon compare` records the structural result: `exact-image`,
`exact-sections` and `normalized-functions` all fail, with 377 `code`, 13
`layout`, 3555 `metadata`, 1 `padding` and 1 `relocation` findings across 13
sections. That is expected, not hidden: the rebuilt binary is 80716 bytes
against the reference's prebound 107756, and the two are linked with
different symbol stubs and a different section layout, so the metadata
findings dominate. Structural acceptance is a byte/layout criterion; the
behavioral criterion the tool actually satisfies is the byte-identical
generated code above. (The 2026-09-30 pass then identified the dominant
cause of that residue — an optimization-level mismatch — and reduced it
drastically; see `2026-09-30-pswrap-structural-residue.md`.)

A string-table comparison of the two binaries is now exact: the printable
`__cstring` literal sets are identical, with zero entries on either side and
the section at the reference's 9961 bytes. Reaching it took one more
`WriteObjSeq` fix on top of the numstring port: the reference formats the
`DPSWriteNumString` argument list through `sprintf` fragments
(`"%d, "`/`"%s, "` with a shared closing literal) rather than separate
`", %d);\n"`-style calls, and it contains no numstring
`DPSWriteStringChars` variants at all, so the base's unreachable
`_dpsP[...].length * sizeof` pad templates in the non-numstring path are
deleted. The code-level structural residue is the crt/dyld glue
(`start`, crt1's `__start`, `__call_mod_init_funcs`,
`__dyld_func_lookup`), the libc `__picsymbol_stub` entries, and the
offset-pairing desync their differing sizes cause — link-toolchain
artifacts, not pswrap code.
