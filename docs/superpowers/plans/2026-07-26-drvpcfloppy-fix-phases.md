# drvPCFloppy Fix Phases Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Resolve the 69 divergences the report pass recorded, bringing drvPCFloppy's behaviour into agreement with Apple's shipped `Floppy_reloc`.

**Architecture:** Five phases in dependency order — controller, generic disk family, drive, disk and geometry, BSD. Each phase resolves the findings `reconstruction/divergences.md` records for its files, restores the diagnostic strings those files emit, ends in a guest build, and advances the ledger. Findings with a shared root cause are one task, not one task per affected function.

**Tech Stack:** Objective-C for DriverKit 3 (NeXT `cc`, C89), built by `gnumake` inside a Rhapsody QEMU guest. Verification by `tools/binrecon` on the Windows host.

**Spec:** [2026-07-25-drvpcfloppy-binary-reconstruction-design.md](../specs/2026-07-25-drvpcfloppy-binary-reconstruction-design.md) §4.3 and §5.
**Predecessor:** [2026-07-25-drvpcfloppy-reconstruction.md](2026-07-25-drvpcfloppy-reconstruction.md) — the pre-pass and report pass, complete.

## Global Constraints

- **The evidence lives in `src/drivers-i386/ide/drvPCFloppy/reconstruction/divergences.md`.** Every task below names the sections it resolves. Each section states the reference disassembly beside our source and what differs. Read the section before editing; do not re-derive the analysis, and do not act on the summary in this plan alone.
- **`ledger.json` is the register of record.** A function whose divergence is resolved advances from `unexamined` to the strongest status the new evidence supports. A divergence deliberately kept becomes `intentional-mismatch` with a reason and a reviewer, which the ledger CLI requires.
- **Fixes touch only what the ledger flags.** No adjacent cleanup, no refactoring of code that is not divergent. The pre-pass carve-out is over.
- **Source directory:** `src/drivers-i386/ide/drvPCFloppy/Floppy.drvproj/Floppy.lksproj` — `$LKS` below.
- **Python invocation:** `PYTHONPATH=tools/binrecon .venv-binrecon/Scripts/python.exe`, from the repository root.
- **Guest builds are a user handoff.** The user runs `vm/build-i386-floppy.sh` manually and returns `/tmp/Floppy.log` plus the staged `Floppy_reloc`. Stop and ask; do not proceed on assumption.
- **Commit messages** start with `drvPCFloppy: `, are one to two lines, describe behaviour rather than listing files, and carry no metadata and no trailers of any kind. Project rule CLAUDE.md §5; it overrides default commit formatting.
- **The driver cannot be compiled on the host.** Static checks and review are the per-task gates; the build is the per-phase gate.

## Baseline

The state every phase must improve on, measured against the build at `ledger.json`'s `rebuilt_sha256`:

| Axis | Value | Composition |
|---|---:|---|
| `missing_symbols` | 1 | `__udivdi3`, libgcc's. Already at target — **any rise is a regression.** |
| `missing_strings` | 92 | diagnostics and `IONamedValue` tables, distributed across phases |
| `missing_imports` | 3 | `.objc_class_name_NXSpinLock`, `.objc_class_name_Protocol`, `_strcpy` |

Ledger status at the start: 104 `assembly-matched`, 49 `control-flow-confirmed`, 69 `unexamined`, 3 `intentional-mismatch`.

**Monotonicity rule.** After each phase, none of the three counts may rise and the ledger's `unexamined` count must fall by that phase's divergence count. A phase that fails this does not commit.

---

## Phase 1 — Controller

16 divergences across `FloppyCnt.m`, `FloppyCntIo.m`, `FloppyCmds.m`, `FloppyArch.m`. Smallest phase and depends on nothing, so it establishes the fix-verify rhythm.

### Task 1.1: The command-byte-count offset bug

The largest single defect in the layer. Five FDC command builders write the command-byte count to the wrong struct offset, so no command bytes reach the hardware through any of them.

**Files:** `$LKS/FloppyCntIo.m`
**Resolves:** divergences.md "Grouped: command-byte-count / result-byte-count offset bug", plus the per-function sections for `doConfigure:` and `doSpecify:`.

- [ ] **Step 1: Read the evidence.** The grouped section states the correct offsets and the affected functions; the `doConfigure:` and `doSpecify:` sections give the per-function disassembly.
- [ ] **Step 2: Fix all five call sites in one edit.** They share a root cause — a single wrong offset constant applied consistently. Prefer correcting the shared definition over patching five sites, if the source expresses it that way.
- [ ] **Step 3: Verify the offsets against the disassembly** quoted in divergences.md for each of the five, individually. A shared root cause does not guarantee a shared correct value.
- [ ] **Step 4: Commit.**

### Task 1.2: `sendCmd:` reads its own command opcode at the wrong offset

**Files:** `$LKS/FloppyCmds.m:187`
**Resolves:** divergences.md "`-[FloppyController sendCmd:]`"

- [ ] **Step 1: Read the section.** It documents a systematic +3-byte offset error.
- [ ] **Step 2: Apply the fix and verify against the quoted disassembly.**
- [ ] **Step 3: Commit.**

### Task 1.3: Implement `doCmdXfr:`

The only genuinely unimplemented method in the driver — its body is a bare `TODO`.

**Files:** `$LKS/FloppyCmds.m:42`
**Resolves:** divergences.md "`-[FloppyController doCmdXfr:]`"

- [ ] **Step 1: Read the section**, which gives the reference's full control flow.
- [ ] **Step 2: Implement it** from the disassembly. This is the one place in this plan writing a body from scratch is correct.
- [ ] **Step 3: Verify** every basic block and call in the reference has a counterpart.
- [ ] **Step 4: Commit.**

### Task 1.4: Restore the raw FDC status codes

Several low-level I/O routines return driverkit `IO_R_*` constants where the reference returns raw FDC status codes, breaking the hung/timeout flag propagation chain.

**Files:** `$LKS/FloppyCntIo.m`
**Resolves:** divergences.md "Grouped: driverkit `IO_R_*` constants substituted for raw FDC status codes", and "`-[FloppyController fcWaitIntr:timeout:]`"

- [ ] **Step 1: Read both sections.**
- [ ] **Step 2: Replace the substituted constants with the reference's values**, and check each caller still interprets the returned value correctly — the point of this fix is the propagation chain, so a corrected callee with an uncorrected caller is worse than neither.
- [ ] **Step 3: Commit.**

### Task 1.5: The remaining controller divergences

**Files:** `$LKS/FloppyArch.m`, `$LKS/FloppyCnt.m`, `$LKS/FloppyCntIo.m`
**Resolves:** divergences.md sections for `dmaStart:dmaStruct:`, `dmaDone:dmaStruct:`, `initFromDeviceDescription:`, `fcCmdXfr:`, `fcCmdXfrExecute:`, `flushIntrMsgs`

- [ ] **Step 1: Work through each section in turn**, committing per function or per closely-related pair. `dmaStart:`/`dmaDone:` share a wrong VM-map struct offset and belong in one commit.
- [ ] **Step 2: Commit.**

### Task 1.6: Restore the controller's diagnostic strings

**Files:** `$LKS/FloppyCnt.m`, `$LKS/FloppyCntIo.m`, `$LKS/FloppyCmds.m`, `$LKS/FloppyArch.m`
**Resolves:** part of the 92 missing strings — the `FCCMD_*` name table and the controller's `IOLog` messages.

- [ ] **Step 1: List the reference strings this layer should emit.**

```bash
PYTHONPATH=tools/binrecon .venv-binrecon/Scripts/python.exe tools/binrecon/parity_check.py "C:/Users/raynorpat/Downloads/test/Drivers/i386/Floppy.config/Floppy_reloc" out/i386/drvPCFloppy/Floppy.config/Floppy_reloc | sed -n '/^missing_strings/,/^missing_symbols/p'
```

- [ ] **Step 2: Restore the `FCCMD_*` table as an `IONamedValue` array.** The reference imports `_IOFindNameForValue`, so these are name-lookup tables, not loose literals. Match Apple's exact spelling and punctuation — parity compares strings byte for byte.
- [ ] **Step 3: Restore the `IOLog` call sites** the divergence sections identify, at the points the reference calls them.
- [ ] **Step 4: Commit.**

### Task 1.7: Phase 1 build checkpoint

- [ ] **Step 1: Hand off to the user.** Ask them to run `vm/build-i386-floppy.sh` and return `/tmp/Floppy.log` plus the staged `Floppy_reloc`. Wait.
- [ ] **Step 2: Confirm `make exit=0`** and review the log for `undeclared`, `conflicting types` and any `may not respond to` naming a selector this phase touched.
- [ ] **Step 3: Measure all three axes.**

```bash
PYTHONPATH=tools/binrecon .venv-binrecon/Scripts/python.exe tools/binrecon/parity_check.py "C:/Users/raynorpat/Downloads/test/Drivers/i386/Floppy.config/Floppy_reloc" out/i386/drvPCFloppy/Floppy.config/Floppy_reloc | grep -E "^[a-z_]+ \("
PYTHONPATH=tools/binrecon .venv-binrecon/Scripts/python.exe tools/binrecon/import_check.py "C:/Users/raynorpat/Downloads/test/Drivers/i386/Floppy.config/Floppy_reloc" out/i386/drvPCFloppy/Floppy.config/Floppy_reloc | grep -E "^missing_imports"
```

Expected: `missing_symbols` still 1; `missing_strings` below 92 by the number restored in Task 1.6; `missing_imports` still 3. Any rise is a regression — fix it before advancing the ledger.

- [ ] **Step 4: Advance the ledger** for all 16 functions, each to the strongest status its new evidence supports.
- [ ] **Step 5: Refresh `rebuilt_sha256`** in `ledger.json` to this build, and commit the ledger with the phase.

---

## Phase 2 — Generic disk family

14 divergences across `IODiskNew.m`, `IODriveNEW.m`, `IOLogicalDiskNEW.m`, `IODiskPartitionNEW.m`, `kernelDiskMethodsNEW.m`. Second because `IOFloppyDisk` and `IOFloppyDrive` inherit from these classes, so phases 3 and 4 are validated against a corrected base.

divergences.md numbers this layer's findings 1 through 7. Each is one task.

- [ ] **Task 2.1 — Finding 1:** the reference's `-[IODiskNEW free]` forces `eax` to zero on every path and returns `nil`; ours returns `self` (`IODiskNew.m:99`). Check callers before changing the return — a caller that tests the result will change behaviour.
- [ ] **Task 2.2 — Finding 2:** three sites use `[[Class alloc] init]` where the reference sends a single `+new`.
- [ ] **Task 2.3 — Finding 3:** `-[IODiskPartitionNEW writeLabel:]` — three distinct issues: a dropped timestamp write, a wrong checksum-zero offset, and a missing log argument. One task, three commits if that reads more clearly.
- [ ] **Task 2.4 — Finding 4:** `setBlockDeviceOpen:` and `setRawDeviceOpen:` compute "any device open" from `_labelValid` instead of the block/raw composite.
- [ ] **Task 2.5 — Finding 5:** five `IOReturn` methods fall through to the epilogue relying on incidental register contents instead of returning an explicit constant. Verify the reference's exact constant per method; do not assume `IO_R_SUCCESS` throughout.
- [ ] **Task 2.6 — Finding 6:** `-[IOLogicalDiskNEW readAt:…]` and `writeAt:…` zero `*actualLength` on error paths where the reference does not.
- [ ] **Task 2.7 — Finding 7:** `completeTransfer:withStatus:actualLength:` calls the wrong selector.
- [ ] **Task 2.8 — Strings:** restore this layer's `DKIOC*` names and disk-label diagnostics, per Task 1.6's method.
- [ ] **Task 2.9 — Build checkpoint:** as Task 1.7, with `unexamined` falling by 14.

---

## Phase 3 — Drive

18 divergences across `IOFloppyDrive.m`, `FloppyDriveInt.m`, `FloppyDriveInt2.m`, `VolCheck.m`.

### Task 3.1: The FDC command-buffer offsets

The largest finding in the phase, spanning 9–12 functions. divergences.md tabulates the wrong and correct offsets: the source uses `+0x24`/`+0x5c`/`+0x14`/`+0x30`/`+0x34`/`+0x54`/`+0x3c` where the disassembly proves `+0x0C`/`+0x08`/`+0x50`/`+0x20`/`+0x24`/`+0x58`/`+0x48`.

- [ ] **Step 1: Read the systematic finding section in full**, including its per-function table.
- [ ] **Step 2: Determine whether these are field offsets in one shared struct.** If so, correct the struct definition once rather than every access site — that is the real root cause and the smaller change.
- [ ] **Step 3: Verify every affected function** against its disassembly individually. Note `+0x24` appears in both columns for different fields; a blind substitution will corrupt one of them.
- [ ] **Step 4: Commit.**

- [ ] **Task 3.2:** `updateReadyStateInt` is declared `void`, but the disassembly computes and returns a ready-state code. Changing the return type touches every caller.
- [ ] **Task 3.3:** `allocateDisk` returns the opposite convention from what the disassembly and its own caller expect.
- [ ] **Task 3.4:** `ejectMedia`, `registerVolCheck`, `unregisterVolCheck` hardcode `IO_R_SUCCESS` instead of propagating the call result.
- [ ] **Task 3.5:** `registerVolCheck` calls `volCheckRegister` with a dropped third argument.
- [ ] **Task 3.6:** `logRwErr:block:status:readFlag:` — parameter types disagree with the call sites and the `IOLog` argument order is swapped.
- [ ] **Task 3.7:** `initFromDeviceDescription:::` hardcodes default geometry instead of reading the global tables.
- [ ] **Task 3.8 — Strings:** restore the `FDCMD_*`, `FD_DENS_*` and `FD_MID_*` tables and this layer's `IOLog` messages. This is the largest string group.
- [ ] **Task 3.9 — Build checkpoint:** as Task 1.7, with `unexamined` falling by 18.

---

## Phase 4 — Disk and geometry

12 divergences across `IOFloppyDisk.m`, `Geometry.m`, `Request.m`, `Thread.m`, `Support.m`. The largest phase by code size.

- [ ] **Task 4.1:** `capacityFromSize:` and `sizeListFromCapacities:sizeList:` use wrong `FloppyGeometry` field offsets.
- [ ] **Task 4.2:** `blocksToEndOfCylinderFromBlockNumber:` has an inverted band-search loop.
- [ ] **Task 4.3:** `fdGetSectSizeInfo` is missing an `IOPanic` path.
- [ ] **Task 4.4:** three sites make a spurious extra `init` call on freshly-`alloc`'d objects. Systematic — one task.
- [ ] **Task 4.5:** `dowire` has the wrong return type and `executeSubrequest:` discards it, so a wire failure is never detected. Fix together; the second is only reachable once the first returns a value.
- [ ] **Task 4.6:** `sweepQueueInsert` has ascending and descending queue selection swapped.
- [ ] **Task 4.7:** `clearOperationsOnQueue:` has too narrow an `IOFree` condition.
- [ ] **Task 4.8:** `operationThread` is missing its two-queue elevator (SCAN) scheduler entirely. The largest behavioural gap in the driver — read the section carefully and expect this task alone to take as long as several others.

### Task 4.9: Link the lock classes instead of looking them up

Closes two of the three remaining missing imports.

**Files:** `$LKS/Bsd.m:228`, `$LKS/IOFloppyDisk.m:102`, `:190`, `:200`, `$LKS/Request.m:369`
**Resolves:** the `objc_getClass` sites; the defect commit `8890be17` recorded.

- [ ] **Step 1: Replace each `[[objc_getClass("NXConditionLock") alloc] init]` with a direct class reference**, e.g. `[[NXConditionLock alloc] init]`. A link-time class reference is only emitted when the source names the class directly, which is what restores the imports.
- [ ] **Step 2: Confirm `<machkit/NXLock.h>` is imported** in each file that now names a class directly.
- [ ] **Step 3: Verify after the phase build** that `missing_imports` drops from 3 to 2, leaving `.objc_class_name_Protocol` and `_strcpy`. Only `NXSpinLock` is an `objc_getClass` site; `Protocol` is missing for a different reason — see the addendum in `divergences.md`.
- [ ] **Step 4: Commit.**

- [ ] **Task 4.10 — Strings:** restore this layer's diagnostics.
- [ ] **Task 4.11 — Build checkpoint:** as Task 1.7, with `unexamined` falling by 12 and `missing_imports` reaching 1.

---

## Phase 5 — BSD

9 divergences in `Bsd.m`. Last, because it calls into every layer below it.

**A caveat on this phase's evidence.** Layer 5's analysis completed on its third dispatch after two infrastructure failures, so it had less settling time than the other four. Re-read each section against the disassembly before acting, and treat a finding that does not reproduce as a reporting error rather than forcing the fix.

### Task 5.1: The partition output parameter

The systemic finding, and the one with the widest blast radius.

**Resolves:** divergences.md "Systemic finding: `partition` output parameter is a raw flag, not a pointer to allocated memory"

- [ ] **Step 1: Verify the claim first.** It asserts `identifyBsdDev` performs no allocation at all in the reference — no `IOMalloc` call. Confirm that against the disassembly before changing anything, because the fix inverts how three callers treat the value.
- [ ] **Step 2: Correct `identifyBsdDev` and the three callers together** — `HandleBsdOpen`, `HandleBsdClose`, `HandleBsdIoctl`. Splitting them leaves the driver inconsistent between commits.
- [ ] **Step 3: Commit.**

- [ ] **Task 5.2:** `HandleBsdIoctl` — the `DKIOCFORMAT`, format-capacities, and label read/write cases differ substantially from the reference; some are re-implemented, some absent. The largest single function in the phase at 2,656 bytes.
- [ ] **Task 5.3:** `fakeStrategySuccess`, `HandleBsdStrategy` and `HandleBsdRead` — the last returns the wrong errno for an unformatted disk.
- [ ] **Task 5.4:** `attachBsdDiskInterfaceToDrive:` swaps the block and character major numbers between the two `dev_t` fields; `detachBsdDiskInterfaceFromDrive:` diverges alongside it.
- [ ] **Task 5.5 — `_strcpy`:** the reference calls `strcpy` and our sources never do. Find the site from the import and the surrounding disassembly. Closes the last missing import.
- [ ] **Task 5.6 — Strings:** restore this layer's diagnostics.
- [ ] **Task 5.7 — Build checkpoint:** as Task 1.7, with `unexamined` reaching 0.

---

## Done

Per spec §5, the effort is complete when all of the following hold:

- the guest build exits 0 and `Floppy_reloc` stages;
- `missing_symbols` is 1 — `__udivdi3` only;
- `missing_strings` is 0, or every remainder carries an `intentional-mismatch` ledger entry with a reason and a reviewer;
- `missing_imports` is 0, or the remainder is dispositioned the same way;
- `load_source_map` passes against the committed source map;
- every one of the 225 ledger entries is `signature-confirmed` or better, or `intentional-mismatch`;
- `src/drivers-i386/README` records drvPCFloppy's new state.

Functional testing — booting a guest, attaching the driver, reading a floppy image — remains out of scope, per the spec's done bar. It is the natural next effort once this one closes.
