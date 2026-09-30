# pswrap Reconstruction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Status:** executed and verified on 2026-09-29. All tasks below are complete;
the one non-passing acceptance criterion is recorded in Task 6 with the reason
it does not apply to this artifact.

**Goal:** Reconstruct Rhapsody's `/usr/bin/pswrap` (the Display PostScript
wrapper generator) in-tree under `src/Commands/pswrap.tproj`, using NeXTDPS's
`pswrap-117.0.2` source as the base, and verify the result against the shipped
reference.

**Architecture:** Import the historical C/yacc/lex tool source verbatim, adjust
it only where the reference binary proves Apple's revision differs from the base,
generate the parser and lexer once with the guest's NeXT-era tools, and build it
as a Project Builder tool project under rbuild. Verify behavior, not just
structure: the rebuilt and reference `pswrap` must produce byte-identical
generated output.

**Tech Stack:** Historical C, yacc (byacc), flex 2.5.4 lex-compatibility mode,
Project Builder makefiles, rbuild i386 toolchain, Python 3.13 binrecon tooling
with IDA 9.4 and angr 9.3.0.

**Spec:** [Approved design](../specs/2026-09-29-pswrap-reconstruction-design.md).

## Global Constraints

- Reconstruct under `src/Commands/pswrap.tproj`; keep the historical source
  layout and filenames.
- The reference binary and all analyzer databases remain outside Git.
- Do not modify the reference binary, the guest's installed `/usr/bin/pswrap`,
  or any shared guest base. Test only in a private disposable guest overlay.
- Preserve observable behavior exactly: version string, `PSW_OS`, friends file,
  option handling, and generated output bytes.
- Behavior proven by the reference outranks the base source when they disagree;
  record each reconciliation with the evidence that drove it.
- Do not count successful compilation, source-map coverage, or analyzer
  agreement alone as behavioral parity.
- Stage only task-owned files. Unrelated untracked files stay untouched.
- Commit messages: `subsystem: description`, one to two lines, no trailers.

## Review Focus

- Base source differs from Apple's shipped revision in small behavioral ways:
  find them by comparing generated output, not by inspection alone (Task 4).
- `NeXT` macros change the generated padding templates and the emitted helpers:
  the build must not define them even though rbuild's `RC_CFLAGS` tries to (Task 3).
- The base lexer assumes AT&T lex internals that flex does not provide: the
  `yywrap` state test must be made flex-aware without breaking a true AT&T lex (Task 4).
- Standalone `MH_EXECUTE` analysis under IDA 9.4 exposed two exporter defects:
  fix them at the toolchain level with regression tests, not by hand-patching
  per-run output (Task 1).
- Structural acceptance is a byte/layout criterion. A prebound reference can
  never match a freshly linked binary; state this plainly rather than tuning
  the comparison (Task 6).

## Task 1: Close the IDA exporter gaps that block standalone executables

**Files:** Modify `tools/binrecon/adapters/ida/export_analysis.py`; extend
`tools/binrecon/tests/test_ida_adapter.py`.
**Interfaces:** Preserve the `export_analysis.py` output schema; only the
segment classification and function-name population change.

- [x] Record the baseline suite result before changing anything: 974 passed, 4 skipped, 2 pre-existing failures in `test_profile.py` (`test_ppc_profile_inventory`, `test_ppc_profiles_are_reference_only_ida_runs[interceptor-ppc.json]`), both unrelated to pswrap.
- [x] Add a failing test that IDA's synthetic `SEG_ABSSYM`/class `"ABS"` segment is accepted as zero-fill rather than rejected for having no file backing (`test_ida_absolute_symbol_segment_is_synthetic_zero_fill`).
- [x] Classify the `ABS` class with BSS/XTRN as synthetic zero-fill in `export_analysis.py`.
- [x] Add a failing test that a function IDA has not named still exports its default `sub_XXXX` name (`test_ida_function_falls_back_to_default_name`).
- [x] Fall back to `ida_name.get_name(canonical_entry)` when `idautils.Names()` yields nothing for a function; this took unnamed functions from 112/138 to 0.
- [x] Run `tools/binrecon/tests/test_ida_adapter.py`: 53 passed, 2 skipped.
- [x] Confirm the reference now exports 138 functions, 751 symbols, 15588 strings, 30 imports.

## Task 2: Vendor the base source and create the binrecon profile

**Files:** Create `src/Commands/pswrap.tproj/` (all base sources); create
`tools/binrecon/profiles/pswrap.json`.
**Interfaces:** The profile is a `profile-v1` document with `${BINRECON_REFERENCE}`
and `${BINRECON_REBUILT}`, pinned reference size and SHA-256, and analyzers
IDA 9.4 plus angr 9.3.0.

- [x] Fetch NeXTDPS `pswrap-117.0.2` and place every base file under `src/Commands/pswrap.tproj`: `main.c`, `psw.c`, `psw.h`, `pswpriv.h`, `pswdict.{c,h}`, `pswfile.c`, `pswparser.y`, `pswsemantics.{c,h}`, `pswstring.c`, `pswtypes.h`, `pswversion.h`, `systemnames.{c,ps}`, `dpsfriends.h`, `lexer.l`, `lexfix`, `yaccfix`, `yyerror.c`, `sysnames2c.awk`, `makefile`, `pswrap.1`.
- [x] Confirm the base revision against the reference strings: `V1.009  Wed Apr 19 17:50:24 PDT 1989`, `unix` `PSW_OS`, `<dpsclient/dpsfriends.h>`, non-NeXT padding templates, and flex scanner strings. Confirm the reference is 107756 bytes, the same size as the reference guest's own `/usr/bin/pswrap` dated Apr 6 1998.
- [x] Create `tools/binrecon/profiles/pswrap.json` with `expected_size` 107756 and SHA-256 `8276bac9…0c2ca825d`, IDA 9.4 enabled, ghidra disabled, angr 9.3.0 enabled, acceptance `normalized-functions`, output `../out/pswrap`.
- [x] Run `binrecon validate --profile tools/binrecon/profiles/pswrap.json`; it passes.

## Task 3: Build the project under rbuild

**Files:** Create `src/Commands/pswrap.tproj/{Makefile,Makefile.preamble,Makefile.postamble,PB.project}`;
check in generated `pswparser.c`, `y.tab.h`, `lexer.c`, `sysnames_gen.c`.
**Interfaces:** The project must honor rbuild's `RC_CFLAGS`, `OBJROOT`,
`SYMROOT`, `DSTROOT` and install `pswrap` into the guest tool root.

- [x] Generate the parser and lexer once on the guest with its own NeXT-era `yacc` and `flex -l`, and the system-name table with `awk -f sysnames2c.awk systemnames.ps`, because rbuild's build sysroot has no yacc or lex. Check the results in.
- [x] Give `pswparser.c` and `lexer.c` empty rules in `Makefile.postamble` so the pb_makefiles `.y.c`/`.l.c` suffix rules cannot regenerate them.
- [x] Set `LOCAL_CFLAGS = -UNeXT -Dos_unix -Dos_mach -DFRIENDSFILE='"<dpsclient/dpsfriends.h>"' -I$(SRCROOT)`; `-UNeXT` must come after rbuild's `RC_CFLAGS` `-DNeXT` so it wins.
- [x] Write `Makefile` and `PB.project` listing the C sources, headers (including `y.tab.h`), and `OTHERSRCS`.
- [x] Build with `rbuild buildpackage` on a private, disposable guest; remove the stale out directory first because an existing apk makes rbuild skip the build. Result: rc=0, fetched `out/pswrap/pswrap.i386`, 88680 bytes, SHA-256 `f16513a9…8170e472`, Mach-O i386 `NOUNDEFS|DYLDLINK`.

## Task 4: Reconcile the base source against the reference

**Files:** Modify `src/Commands/pswrap.tproj/pswsemantics.c` and
`src/Commands/pswrap.tproj/lexer.l`.
**Interfaces:** No interface changes; both edits make emitted behavior match the
reference.

- [x] Compare generated header and body output from the rebuilt and reference binaries to expose source-level differences.
- [x] `pswsemantics.c`: declare `extern int pad;` and, under the `pad` guard after `EmitBody`, emit `  if (0) *pad = 0;    /* quiets compiler warnings */` before the closing brace, matching the reference.
- [x] `lexer.l`: under `#ifdef FLEX_SCANNER`, test `YY_START != INITIAL` in `yywrap`; keep the AT&T-lex `yybgin != (yysvec+1)` form in the `#else`.

## Task 5: Prove behavioral parity on the guest

**Files:** Temporary private-guest scripts only (outside Git).
**Interfaces:** Both binaries must be invoked with identical inputs and identical
`-h`/`-o` output names.

- [x] Run the reference `/usr/bin/pswrap` and the rebuilt binary on the same `sample.psw`.
- [x] Compare outputs: generated header byte-identical, generated C body byte-identical.

## Task 6: Run the binrecon pipeline and record the structural result

**Files:** Produce `tools/binrecon/out/pswrap/published/*` (ignored); record the
outcome in the spec.
**Interfaces:** `analyze`, `source-map`, and `compare` must all run to completion
for reference and rebuilt.

- [x] Run `binrecon analyze` for the reference-only and full profiles; it publishes `analysis-{reference,rebuilt}-{ida,angr}.json` and `consensus-{reference,rebuilt}.json`.
- [x] Run `binrecon source-map`: 0 mapped, 138 unmapped, 0 duplicate candidates, 0 boundary disputes — expected, since the stripped reference carries `sub_*` names that cannot match source names.
- [x] Run `binrecon compare`; it publishes `comparison-{ida,angr}.json` with `acceptance = {exact-image: false, exact-sections: false, normalized-functions: false}` and reason totals including 109 missing rebuilt functions, 118 missing reference functions, and 13 differing section layouts.
- [x] Record that `normalized-functions` does not pass and why it cannot: the rebuilt binary is 88680 bytes against the reference's prebound 107756 with different symbol stubs, so byte/layout acceptance is not the applicable criterion. Behavioral parity (Task 5) is the criterion actually met.

## Handoff and self-review

Spec components map to tasks as follows: toolchain gaps to Task 1, vendoring and
profile to Task 2, build integration to Task 3, source reconciliation to Task 4,
behavioral verification to Task 5, and structural analysis to Task 6. Every
review-focus item has an owning task and a recorded result. All five review-focus
conditions have explicit owning tasks. No source was modified while writing this
plan.

Recommended follow-up: none. The reconstruction is complete; the remaining
`normalized-functions` gap is a recorded property of comparing a prebound
reference against a fresh link, not an open task.
