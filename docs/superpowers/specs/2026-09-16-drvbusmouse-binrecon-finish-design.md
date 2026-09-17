# Finish drvBusMouse under binrecon

Drive `drvBusMouse` to function-level instruction-stream identity with Apple's
shipped i386 `BusMouse_reloc`, then guest-build and measure. The report pass
and fix pass already closed the class hierarchy, strings, Loaded Server
sections, and Findings 1–19. This pass wires version objects locally, re-measures
with IDA binrecon, and chases `raw_equal` / `masked_equal` on the three named
compiler residuals.

This continues
[2026-07-25-i386-input-driver-binary-reconstruction-design.md](2026-07-25-i386-input-driver-binary-reconstruction-design.md)
and the committed artifacts under
`src/drivers-i386/input/drvBusMouse/reconstruction/`. That spec's rule that a
rebuilt `_reloc` is not fed to binrecon is **superseded for this driver only**.
The report-pass claim that `__TEXT,__const` / `vers_string` is out of scope is
**also superseded for this driver only**. Sibling input drivers, `src/kernel-7`,
and `driverTools` stay out of scope.

## Motivation

`src/drivers-i386/README` currently says this driver "compiles; reconstructed
against the reference binary, fixes applied, not yet tested." `divergences.md`
already names the leftover work:

- `_GetIRQFromBoard` is 12 bytes long (124 vs 112). gcc spills the masked
  nibble copy to `[ebp-8]` where the reference keeps it in `cl`. Task 12 tried
  `unsigned char` and `unsigned int` spellings under capstone; both cost the
  same 12 bytes.
- `_MouseIntHandler` is 8 bytes short (400 vs 408). The reference widens
  left-button before `xor 1` and spills the shifted right-button byte; ours
  keeps those in registers and emits an extra `and al, 1`.
- `-[BusMouse setIntValues:forParameter:count:]` is 12 bytes short (136 vs
  148). gcc hoists `parameterArray` and keeps the compare count immediate.
  The same leftover as `drvPS2Mouse`.
- `__TEXT,__const` is absent. Apple emits `_BusMouse_VERS_STRING` (160 bytes)
  and `_BusMouse_VERS_NUM` (10 bytes) via `vers_string`. Cirrus already showed
  that a driver-local `OTHER_GENERATED_OFILES += $(VERS_OFILE)` produces those
  symbols.
- `vm/build-i386-input-recon.sh` was deleted in `d529b15f1` (unrelated rbuild
  work). Guest builds of this driver have no harness in the current tree.
- Ledger `rebuilt_sha256` is still `null`. Task 12 compared the rebuilt stream
  with capstone, not with IDA binrecon `raw_equal` / `masked_equal`.

Done means those gaps are closed or proven unreachable from source shape, not
that QEMU moves a pointer.

## 1. Done bar

A paired function is done when `raw_equal` or `masked_equal` is true on a
comparison produced from the current `BusMouse_reloc`, or when the leftover is
recorded in
`src/drivers-i386/input/drvBusMouse/reconstruction/divergences.md` with the
`binrecon function --name` dump and an explicit *accept* disposition.

The campaign is done when every paired hand-written function meets that bar,
unpaired leftovers are only the two build-generated glue methods
(`+[BusMouseKernelServerInstance kernelServerInstance]`,
`+[BusMouseVersion driverKitVersionForBusMouse]`), `__TEXT,__const` contains
`_BusMouse_VERS_STRING` and `_BusMouse_VERS_NUM`, `parity_check.py` reports
`missing_strings` 0 and `missing_symbols` 0, and `ledger.json`
`rebuilt_sha256` is the last kept `_reloc`.

`cfg_equal` is not a signal. Status may remain `different` because of
`cfg differs` or `instruction layout differs`. The flags that count are
`raw_equal` and `masked_equal`.

Hardware testing stays out. The README line remains that the driver is not
yet tested on a real mouse.

## 2. Architecture

This is a reconstruction campaign, not a new subsystem. `BusMouse` already
subclasses `PCPointer` and adds no ivars. Findings 1–19 stay closed. The
in-kernel `src/kernel-7` pointer code is a different class and is not this
driver.

The loop is: edit one site → sync only this driver → guest `gnumake` → copy
`BusMouse_reloc` back to gitignored `out/i386/drvBusMouse/` → IDA-analyze the
rebuild → `binrecon function --list`.

Phases, in order:

**Phase 0 — harness.** If `vm/build-i386-input-recon.sh` is missing, restore
it as it existed immediately before `d529b15f1` (content from `1b1b68b93`,
including the `drvISASerialPort` case). If a sibling campaign already put a
harness there, keep their file and add a `drvBusMouse` arm rather than
replacing it. This campaign only *runs* `drvBusMouse`. Add a `rebuilt` key
to `tools/binrecon/profiles/busmouse.json` and disable Ghidra and angr for
analyze. `output_dir` stays `../out/busmouse`. Committed `reconstruction/`
artifacts remain the human-reviewed record. Gitignored analyzer JSON under
`tools/binrecon/out/busmouse/` will be overwritten by IDA-only analyze; do
not treat leftover Ghidra/angr files as current.

**Phase 1 — baseline.** Guest-build the current tree with no source edits.
Write `reconstruction/function-worklist.md` from `binrecon function --list`.
This is the regression snapshot.

**Phase 2 — version objects.** Create the Kernel Server
`Makefile.postamble` with `OTHER_GENERATED_OFILES += $(VERS_OFILE)`. The
Kernel Server `Makefile` already `-include`s it and names it in `OTHERSRCS`;
the file itself is missing. Gate: `__TEXT,__const` contains
`_BusMouse_VERS_STRING` and `_BusMouse_VERS_NUM`. Do not match the 160-byte
string (host and timestamp). Do not edit `driverTools` or guest-installed
makefiles. The Driver-project MH_BUNDLE is not a gate.

**Phase 3 — cheapest-first grinding.** The three residuals only:
`_GetIRQFromBoard`, `_MouseIntHandler`,
`-[BusMouse setIntValues:forParameter:count:]`. One written experiment per
rebuild. Stop a function when the cheapest leftover is register allocation
or stack spill. Glue stays generated.

The eight methods already claimed `assembly-matched` are a regression gate:
if any of them lose `masked_equal` after an edit, revert.

`validConfiguration:`, `interruptHandler`, `_BusMouseThread`, `mouseInit:`,
`free`, `getHandler:level:argument:forInterrupt:`, `getResolution`,
`getIntValues:forParameter:count:`.

## 3. Current evidence (do not rediscover)

These claims are already proven in
`src/drivers-i386/input/drvBusMouse/reconstruction/divergences.md`. This
finish pass treats them as given.

| Function | Addr | Ref size (IDA) | Ledger | What still differs |
|---|---|---|---|---|
| `_GetIRQFromBoard` | 0 | 109 | `intentional-mismatch` | gcc spill of `lowBits`; 124 vs 112 |
| `-[BusMouse validConfiguration:]` | 112 | 129 | `assembly-matched` | regression gate |
| `_MouseIntHandler` | 244 | 406 | `intentional-mismatch` | widen/spill; 400 vs 408 |
| `-[BusMouse interruptHandler]` | 652 | 53 | `assembly-matched` | regression gate |
| `_BusMouseThread` | 708 | 123 | `assembly-matched` | regression gate |
| `-[BusMouse mouseInit:]` | 832 | 392 | `assembly-matched` | regression gate |
| `-[BusMouse free]` | 1224 | 41 | `assembly-matched` | regression gate |
| `-[BusMouse getHandler:level:argument:forInterrupt:]` | 1268 | 39 | `assembly-matched` | regression gate |
| `-[BusMouse getResolution]` | 1308 | 16 | `assembly-matched` | regression gate |
| `-[BusMouse getIntValues:forParameter:count:]` | 1324 | 93 | `assembly-matched` | regression gate |
| `-[BusMouse setIntValues:forParameter:count:]` | 1420 | 146 | `intentional-mismatch` | gcc hoist/spill; 136 vs 148 |
| `+[BusMouseKernelServerInstance kernelServerInstance]` | 1568 | 12 | `intentional-mismatch` | generated glue |
| `+[BusMouseVersion driverKitVersionForBusMouse]` | 1580 | 12 | `intentional-mismatch` | generated glue |

Reference SHA-256:
`A1AAB49F4D9F2BA90B4D7105F3D76BBF054F6D2D150B041D2156FC4F75E71864`.
Reference file size 29796. Last Task 12 rebuild was 99120 bytes unstripped,
`__TEXT,__text` 1584 against Apple's 1592. IDA is authoritative for extents;
symbol-gap sizes include inter-function `nop` padding and are not the
comparison extent.

`Default.table` already diffs clean ignoring `"Driver Version"`.
`Load_Commands.sect` is 164 bytes. `Unload_Commands.sect` is 102 bytes.
`__TEXT,__cstring` is 340 bytes with an identical set. `__DATA,__bss` is 48
bytes with identical symbols at identical addresses. None of those is
reopened.

Do not reopen Findings 1–19. The doubled `outb(0x23E, 0x80)`, the unguarded
`target` send in `setIntValues:`, and the shared `return NO` in
`validConfiguration:` stay as they landed.

## 4. Components

| Piece | Job |
|---|---|
| `BusMouse.m` | Only translation unit edited in Phase 3. Findings 1–19 stay as they are. |
| `BusMouse.h` | Not touched. Superclass, types, and selectors already match the reference. |
| Kernel Server `Makefile.postamble` | Created at `BusMouse.drvproj/BusMouse.lksproj/Makefile.postamble`. One line: `OTHER_GENERATED_OFILES += $(VERS_OFILE)`. `Makefile` already `-include`s it. |
| `vm/build-i386-input-recon.sh` | Restored if missing; otherwise keep a sibling harness and add the `drvBusMouse` arm. This campaign only *runs* `drvBusMouse`. |
| `tools/binrecon/profiles/busmouse.json` | Adds `"rebuilt": { "path": "${BINRECON_REBUILT}" }`; IDA stays on; Ghidra and angr `enabled: false`. |
| `reconstruction/function-worklist.md` | Created after Phase 1; refreshed when a diagnosed gap closes or a function is accepted. |
| `reconstruction/divergences.md` | VERS gap closed; exhausted experiment lists live here. |
| `reconstruction/ledger.json` | Status of record. `rebuilt_sha256` set from the last kept `_reloc`. |
| `reconstruction/source-map.json` | Line numbers only, when bodies move. |
| `src/drivers-i386/README` | Status line updated at the end. |

Out of bounds: `src/kernel-7`, other input drivers, `src/driverTools-1`,
guest-installed `kernelserver.make`, compiler flags beyond the existing
`-Wno-format -DDRIVER_PRIVATE`, hand-written glue, QEMU, boot, hardware.
Do not re-enable Ghidra or angr.

`BINRECON_REFERENCE` is:

```
C:\Users\raynorpat\Downloads\test\Drivers\i386\BusMouse.config\BusMouse_reloc
```

`BINRECON_REBUILT` is the host-staged copy:

```
out/i386/drvBusMouse/BusMouse.config/BusMouse_reloc
```

## 5. Data flow

1. Host edits one allowed site (`BusMouse.m`, the new `Makefile.postamble`,
   the harness, or the binrecon profile).
2. `powershell -File vm/sync-src.ps1 -Path drivers-i386/input/drvBusMouse`.
   When the restored harness is the change, also sync `vm/build-i386-input-recon.sh`.
   Never `-All`.
3. Guest: strip CR from the harness if `/bin/sh` is the 1999 Bourne shell,
   then `sh /build/source/vm/build-i386-input-recon.sh drvBusMouse`. Copy
   `/build/out/i386/drvBusMouse/BusMouse.config/BusMouse_reloc` to host
   `out/i386/drvBusMouse/` (gitignored).
4. Host: set both `BINRECON_*` variables. Run
   `binrecon analyze --profile tools/binrecon/profiles/busmouse.json`
   (IDA only). Then `binrecon function --list` and, for the open function,
   `--name`. Analyze may exit 1 until `normalized-functions` acceptance
   passes; that is expected during the campaign. The gate is that
   `tools/binrecon/out/busmouse/published/` contains
   `analysis-reference-ida.json`, `analysis-rebuilt-ida.json`, and
   `comparison-ida.json`. Do not treat leftover Ghidra/angr published files
   as current.
5. Also run `tools/binrecon/parity_check.py` against `__TEXT,__cstring` and
   `__TEXT,__text` symbol names. A missing reference string or symbol is a
   finding. Extra unstripped locals are not.
6. After Phase 2, confirm `__TEXT,__const` contains the two `vers_string`
   symbols.
7. Record the outcome in `divergences.md` before the next edit. Advance the
   ledger only on a kept rebuild.

Analyzer output under `tools/binrecon/out/busmouse/` stays uncommitted.
Never commit the reference binary or a rebuilt `_reloc`.

## 6. Error handling

- Guest build fails: stop. Fix or revert. Do not advance the ledger or invent
  section sizes.
- Guest unreachable: leave the campaign open. Do not claim instruction-stream
  results from an old `_reloc`.
- Any of the eight already-matched methods lose `masked_equal`: revert,
  record as failed-with-regression, continue the list.
- The `VERS_OFILE` line is a reconstruction, not an experiment: keep it even
  if `__text` extents do not close.
- Experiment non-match with no regression: revert, mark tried, next item.
- Experiment list empty and leftover is register allocation or stack spill:
  accept as `intentional-mismatch` with the `binrecon function --name` dump
  and a reviewer. Do not add dummy locals or reorder statements to chase
  gcc 2.7.
- `VERS_OFILE` still missing after the local postamble: record whether
  `BusMouse_vers.c` / `.o` were generated and whether they appear on the
  `kl_ld` line. Existence stays unmet. Do not edit shared project types.
- `parity_check.py` missing a reference string or `__text` symbol: defect in
  the last edit; revert or fix before continuing.
- Ghidra/angr stay disabled. Do not treat their absence as a new analyzer
  disagreement.
- Do not reopen Findings 1–19.

## 7. Experiment lists

Source-shape only. One item per rebuild. A match ends the row. Empty list
without a match is unreachable. Rewrite from the Phase 1 worklist if ranking
differs; these are starters, not a license to skip measurement.

### 7.1 `_GetIRQFromBoard` (addr 0)

Residual today: gcc spills `lowBits` to `[ebp-8]` (+12 bytes). Task 12 already
tried `unsigned char` vs `unsigned int` under capstone.

1. Drop `lowBits`; test `(changed & 0x0f)` inline at the three later bit tests.
2. Use `lowBits` for bit 0 as well (`if (lowBits & 1)`), matching the later tests.
3. Retry `unsigned int lowBits` under IDA (last trial was capstone-only).
4. Write the IRQ-2 case as `else if (lowBits & 8) irq = 2; else irq = 0;`
   instead of nested.

Do not change the port (`0x23E`), the `0xF000` count, or the 5/4/3/2/0 ladder.

### 7.2 `_MouseIntHandler` (addr 244)

Residual today: 8 bytes smaller. Reference widens left-button before `xor 1`
and spills the shifted right-button byte; ours keeps those in registers and
emits an extra `and al, 1`.

1. Widen left before the xor: `left = (unsigned int)(buttonByte >> 7); left ^= 1;`
2. Stage right through a byte temporary, then `~temp & 1`.
3. Compute right as `((buttonByte >> 5) & 1) ^ 1` instead of `~(...) & 1`.

Do not reorder the ten port accesses, the doubled `outb(0x23E, 0x80)`, or the
busy-accumulate vs post-and-clear split.

### 7.3 `-[BusMouse setIntValues:forParameter:count:]` (addr 1420)

Residual today: 12 bytes smaller; gcc hoists `parameterArray` and keeps the
compare count immediate. Same leftover as `drvPS2Mouse`.

1. Pass `[self getResolution]` and the sign-extended inverted value directly,
   with no `resolutionValue` / `invertedValue` locals.
2. Swap the declaration order of those two locals if `--name` shows reversed
   stack slots.

If `--name` after Phase 1 shows only the hoist/spill, treat the list as empty.
Do not add dummy spills to chase 148.

### 7.4 Regression only

`validConfiguration:`, `interruptHandler`, `_BusMouseThread`, `mouseInit:`,
`free`, `getHandler:…`, `getResolution`, `getIntValues:…`. No experiments.

## 8. Testing

No QEMU, no boot, no hardware. Verification is the guest `_reloc` plus host
checks.

**Phase 1 baseline.** Harness reports success (`fail=0` / `EXIT=0`), a
staged `_reloc`, worklist written. Record size, `parity_check.py` counts,
and per-function `raw_equal` / `masked_equal`. Expect `__TEXT,__text` near
1584, `__TEXT,__const` still absent, `missing_strings` 0, `missing_symbols`
0. The eight already-matched methods should still have `masked_equal`.

**After `VERS_OFILE`.** `__TEXT,__const` exists and names
`_BusMouse_VERS_STRING` and `_BusMouse_VERS_NUM`. Contents may differ (host
and timestamp). The eight matched methods must not regress. `__text`
identity of the three residuals may stay mismatched.

**After each experiment rebuild.** `binrecon function --list` is the
worklist. Match → `assembly-matched`. Exhausted list → leave
`intentional-mismatch` with the dump.

**Final.** README names the new `masked_equal` counts, that the version
objects exist, and that the driver is still untested on hardware. Ledger
`rebuilt_sha256` is the last kept `_reloc`.

## 9. Success criteria

- `vm/build-i386-input-recon.sh` is back in the tree and
  `sh … drvBusMouse` stages a `_reloc`.
- `_BusMouse_VERS_STRING` and `_BusMouse_VERS_NUM` exist in the `_reloc`.
- Each of the 11 hand-written functions is `assembly-matched` or recorded
  unreachable with its exhausted list.
- The eight previously `assembly-matched` methods still have `masked_equal`.
- Glue is still generated, not hand-written.
- `missing_strings` 0, `missing_symbols` 0.
- No shared makefile or other-driver edits beyond ensuring
  `vm/build-i386-input-recon.sh` has a working `drvBusMouse` arm.
