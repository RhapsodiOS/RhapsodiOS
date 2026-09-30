# pswrap Reconstruction Design

**Status:** implemented and verified on 2026-09-29.

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
Two behavioral differences were found by comparing generated output and are
now reconstructed in the in-tree source:

- **`pswsemantics.c`:** the reference emits
  `  if (0) *pad = 0;    /* quiets compiler warnings */` as the last
  statement of any wrap whose `-p` padding local is declared. `FinalizePSWrapDef`
  now emits it under the same `pad` guard.
- **`lexer.l`:** the base `yywrap` tests AT&T lex's `yybgin != (yysvec+1)`
  state vector, which flex does not provide. It now uses flex's equivalent
  `YY_START != INITIAL` under `#ifdef FLEX_SCANNER`, keeping the AT&T form
  for a true AT&T lex.
- **`main.c` `-p`:** the base's non-`NeXT` `-p` branch did `pad++`, which
  never disabled padding. The reference clears the flag (`pad = 0`), matching
  `pswrap.1`'s "disables padding of strings".
- **`psw.c` ANSI prototypes:** the base omits `const` on input strings and
  arrays. The reference declares a string or array *input* `const` (never a
  scalar and never an output), so `EmitANSIPrototypes` now does too.
- **`psw.c` user names:** the base emits a `DPSMapNames` call with a
  `_dps_names`/`_dps_nameVals` pair and (under `-a`) a `_dpsCodes` cache. The
  reference instead packs every user-name body inline with the literal string
  bodies in `_dpsQ` (or `_dpsQ1`) and gives each `DPS_LITERAL|DPS_NAME` /
  `DPS_EXEC|DPS_NAME` tag a length and offset, exactly as it does for strings.
  The pool is filled in body order (so it is reverse source order), duplicate
  text is stored once, and constants name tags need no runtime mapping. The
  whole `DPSMapNames`/`_dpsCodes` machinery is removed.
- **`psw.c` numstrings:** the base writes a hand-built `HNumHeader` plus the
  body and its pad via three `DPSWriteStringChars` calls. The reference emits
  one `DPSWriteNumString(ctx, dps_t<T>, arr, count, scale)` call and no
  header. `CTypeToResultType` gained the four `T_*NUMSTR` cases and the
  vendored `dpsfriends.h` gained the `DPSWriteNumString` macro it was missing.

## Verification

Built on a private `-snapshot` QEMU i386 guest. The rebuilt and the
reference `/usr/bin/pswrap` were run on the same input with the same `-h`
and `-o` names:

- generated **header: byte-identical**
- generated **C body: byte-identical**

A differential harness drives sixteen inputs through nine flag combinations
(`-a`, `-r`, `-p`, `-b`, `-s`, and pairs), diffing `out.h`, `out.c`, stdout,
stderr and the exit status on every pair. The inputs exercise well-known and
user names, `-p` padding, `numstring` (all four element types, constant and
variable subscripts, and constant and variable scales), literal and hex
string bodies, user-object arrays, split statics, duplicate text, ANSI
prototypes, and reentrant statics. All 144 pairs are identical, including
the byte-identical generated code above.

`binrecon analyze` publishes analyses for both artifacts and both analyzers
(IDA 9.4 and angr 9.3.0), and `binrecon compare` records the structural
result. `normalized-functions` acceptance does **not** pass, and this is
expected, not hidden: the rebuilt binary is 80464 bytes against the
reference's prebound 107756, the section layout differs (13 sections), and
the two are linked with different symbol stubs (each names many reference
functions the other lacks). Structural acceptance is a byte/layout
criterion; the behavioral criterion the tool actually satisfies is the
byte-identical generated code above.
