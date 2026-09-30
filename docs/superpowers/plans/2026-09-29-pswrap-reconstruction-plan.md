# pswrap Reconstruction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reconstruct Rhapsody's `/usr/bin/pswrap` in-tree under `src/Commands/pswrap.tproj` from NeXTDPS's `pswrap-117.0.2`, close the `binrecon` gaps that block analyzing a standalone i386 Mach-O executable, and verify the rebuilt tool against the shipped reference by diffing its generated code.

**Architecture:** Vendor the base source, build it with the existing rbuild i386 toolchain on a private QEMU guest, analyze the reference and the rebuild with `binrecon`, and drive both binaries over a corpus of `.psw` inputs with an exhaustive flag matrix, diffing every generated header, body, and message. Where the base source and the shipped 1.009 revision disagree, the reference's emitted code is the specification.

**Tech Stack:** C (NeXT-era cc, i386 Mach-O), Project Builder / `pb_makefiles` via `rbuild`, QEMU i386 guest, Python 3.13.9, binrecon (`tools/binrecon`), IDA Professional 9.4, angr 9.3.0, pytest.

**Spec:** `docs/superpowers/specs/2026-09-29-pswrap-reconstruction-design.md`

## Global Constraints

- Reference binary is `C:\Users\raynorpat\Downloads\test\pswrap`, 107756 bytes, SHA-256 `8276BAC9E9EF09B6841DEDBEB9E61AF38E9BDF2531348F82FC7720C0C2CA825D`. It is **never** committed.
- The rebuilt binary is linked with the guest's toolchain, so it is *not* byte- or layout-identical to the prebound reference. `normalized-functions` acceptance is expected to fail; behavioral parity of the generated code is the acceptance criterion.
- Commit messages are short, subsystem-prefixed, one to two lines, no metadata.
- Changes to the vendored source are surgical: each difference from the base must be justified by reference output observed on the guest.

## Reference identities

| Item | Value |
| --- | --- |
| Reference path | `C:\Users\raynorpat\Downloads\test\pswrap` |
| Size / SHA-256 | 107756 / `8276BAC9E9EF09B6841DEDBEB9E61AF38E9BDF2531348F82FC7720C0C2CA825D` |
| Format | Mach-O i386, `NOUNDEFS|DYLDLINK|PREBOUND` |
| Base source | `https://github.com/johnjh/NeXTDPS` `pswrap-117.0.2` |
| binrecon profile | `tools/binrecon/profiles/pswrap.json` |

---

### Task 1: Vendor the base source

- [x] Download `pswrap-117.0.2` into `src/Commands/pswrap.tproj/`: `main.c`, `psw.c`, `psw.h`, `pswpriv.h`, `pswdict.{c,h}`, `pswfile.c`, `pswparser.y`, `pswsemantics.{c,h}`, `pswstring.c`, `pswtypes.h`, `pswversion.h`, `systemnames.{c,ps}`, `dpsfriends.h`, `lexer.l`, `lexfix`, `yaccfix`, `yyerror.c`, `sysnames2c.awk`, `makefile`, `pswrap.1`.
- [x] Confirm the shipped version string `V1.009  Wed Apr 19 17:50:24 PDT 1989` and the `unix` OS text match the vendored `pswversion.h`, and that the reference contains the non-`NeXT` `(char *)pad` templates.

### Task 2: binrecon profile and analyzer gaps

- [x] Create `tools/binrecon/profiles/pswrap.json` (i386/little, reference `${BINRECON_REFERENCE}` with expected size and SHA-256, rebuilt `${BINRECON_REBUILT}`, IDA 9.4 timeout 900, angr 9.3.0, acceptance `normalized-functions`, output `../out/pswrap`).
- [x] Fix `adapters/ida/export_analysis.py`: classify the synthetic `SEG_ABSSYM`/class `"ABS"` segment with BSS/XTRN as zero-fill.
- [x] Fix `adapters/ida/export_analysis.py`: fall back to `ida_name.get_name` for functions `idautils.Names()` omits, so `source-map-v1`'s at-least-one-name rule is satisfied.
- [x] Add regression tests for both in `tools/binrecon/tests/test_ida_adapter.py`.
- [x] Run `binrecon analyze` and `binrecon source-map`; record the structural result.

### Task 3: Build integration

- [x] Add `Makefile`, `Makefile.preamble`, `Makefile.postamble`, and `PB.project`.
- [x] `Makefile.preamble`: `-UNeXT -Dos_unix -Dos_mach -DFRIENDSFILE='"<dpsclient/dpsfriends.h>"' -I$(SRCROOT)`.
- [x] Check in `pswparser.c`, `y.tab.h` and `lexer.c` generated with the guest's `yacc` and `lex -l`, and `sysnames_gen.c` from `sysnames2c.awk systemnames.ps`.
- [x] `Makefile.postamble`: empty `pswparser.c:` and `lexer.c:` rules so the `pb_makefiles` `.y.c`/`.l.c` suffix rules cannot fire.
- [x] Build on the guest with `rbuild buildpackage`; confirm the generated code matches the reference for a sample.

### Task 4: Source reconciliations against the reference

Each item was established by running the reference on the guest and reading its output.

- [x] `pswsemantics.c` `FinalizePSWrapDef`: emit `  if (0) *pad = 0;    /* quiets compiler warnings */` as the last statement of a wrap with a declared `pad`.
- [x] `lexer.l` `yywrap`: report nothing at end of input, as the reference does (superseded in Task 7, which removed the `end of input file/missing endps` diagnostic and the state test entirely).
- [x] `main.c`: `-p` clears padding (`pad = 0`), rather than incrementing it.
- [x] `psw.c` `EmitANSIPrototypes`: declare string and array *inputs* `const`.
- [x] `psw.c`: emit user names as inline `DPS_LITERAL|DPS_NAME` / `DPS_EXEC|DPS_NAME` tags with length and offset, packed into the same pool as literal strings, deduplicated, and remove the `DPSMapNames`/`_dps_nameVals`/`_dpsCodes` path.
- [x] `psw.c`: emit `DPSWriteNumString(ctx, dps_t<T>, arr, count, scale)` for `numstring` arguments instead of the `HNumHeader` + `DPSWriteStringChars` sequence; add the `T_*NUMSTR` cases to `CTypeToResultType`.
- [x] `dpsfriends.h`: add the `DPSWriteNumString` macro.

### Task 5: Differential verification

- [x] Build the differential harness: `pswrap` inputs run by both binaries with identical `-h`/`-o` names and flags, diffing `out.h`, `out.c`, stdout, stderr and exit status.
- [x] Cover names, literal and hex strings, `numstring` (all types, subscripts and scales), arrays, split statics, duplicates, bare/unknown names, ANSI and non-ANSI, `-p`, `-b`, `-r`, `-s`, and the sample. 16 inputs × 9 flag sets = 144 pairs, all identical.
- [x] Confirm the sample reports `HEADER_IDENTICAL` and `BODY_IDENTICAL`.
- [x] Re-fetch the fresh rebuild to `out/pswrap/pswrap.i386` and re-validate the profile.

### Task 6: Widening pass (2026-09-30)

A wider corpus and a wider option set, with the reference decompiled under IDA 9.4 to settle what inputs could not.

- [x] Inventory the reference's option parser from its decompilation: `-H`, `-I`, `-S`, `-a`, `-b`, `-e`, `-h`, `-n`, `-o`, `-p`, `-r`, `-s`, `-w`.
- [x] `main.c`: add `-H <dir>`, `-I <text>`, `-e <qualifier>` (default `extern`) and `-n`, with `friendsDir`, `includeFile`, `externPrefix` and `inlineNames` globals.
- [x] `pswfile.c`: `InitOFile` emits `#include <dir/dpsfriends.h>` for `-H`; `InitHFile` emits `#include <text>` for `-I`.
- [x] `psw.c` `EmitPrototype`: emit `"%s void %s("` with the `-e` qualifier.
- [x] `psw.c`: restore `ConsNameToken`/`nameTokens`/`nNames`, `EmitNameTagAcquisition`, `EmitMappedNames`, the `-n` `0, 0, 0` name tags, the `nNames`-forces-`writable` rule, and the `-a` `_dpsCodes` declaration in `EmitLocals`.
- [x] `lexer.l`/`lexer.c` `yywrap`: drop the `end of input file/missing endps` diagnostic and its state test.
- [x] `psw.c` `CheckSize` and `BuildTypesAndAssignAddresses`: round the constant subscript *value*, not the running total, and never round a numstring.
- [x] `psw.c` `ConstructStatics`: do not treat a subscripted numstring as an input array when deciding to split `_dpsQ`/`_dpsQ1`.
- [x] Re-verify: 499 differential pairs (`-a`,`-r`,`-p`,`-b`,`-s`,`-n`,`-e`,`-H`,`-I` combinations over 45 inputs), 20 size cases, 7 end-of-input cases; re-check the binary string tables.

### Task 6b: Literal-set closure pass (2026-09-30)

- [x] Classify the three paired `__text` differences as crt/dyld glue (`start`, crt1 `__start`, `__call_mod_init_funcs`, `__dyld_func_lookup`), not pswrap code.
- [x] Diff the printable `__cstring` literal sets from the IDA analyses: 2 reference-only (`"%d, "`, `"%s, "`) vs 8 rebuild-only (six dead numstring `DPSWriteStringChars`/`sizeof` templates plus `", %d);\n"`-style tails).
- [x] `psw.c` `WriteObjSeq`: format the `DPSWriteNumString` subscript/scale through `"%d, "`/`"%s, "` fragments with a bare closing literal, and delete the unreachable numstring `sizeof` pad branches (every numstring `continue`s before them).
- [x] Recover the wedged guest (kernel spin at `EIP 0xab9c`; QMP `system_reset` insufficient, relaunched `boot.py`; `/build` core survived, only the scratch `/build/psw` was recreated).
- [x] Rebuild (80716 bytes) and re-verify: difftest/difftest2/difftest3/difftest4 (all pairs identical), sizeprobe2 (20/20 SAME), functest (`HEADER_IDENTICAL`/`BODY_IDENTICAL`), eofprobe.
- [x] Re-run `binrecon analyze`: the printable `__cstring` sets are now exactly equal (0/0, section 9961 bytes in both). Remaining `code` residue is the crt/dyld glue, libc stubs and the offset-pairing desync.

### Task 7: Documentation

- [x] Write `docs/superpowers/specs/2026-09-29-pswrap-reconstruction-design.md`.
- [x] Record this plan.
- [x] Report the structural acceptance result: `normalized-functions` does **not** pass, and why (size, section layout, symbol stubs), so it is not mistaken for a silent failure.
