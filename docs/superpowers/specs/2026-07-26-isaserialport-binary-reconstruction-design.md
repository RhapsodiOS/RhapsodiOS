# Binary reconstruction of drvISASerialPort

Reconstruct `drvISASerialPort` against Apple's shipped i386 driver binary, using
the `tools/binrecon` toolchain. A report pass maps every reference function to our
source and records the divergences; a fix pass then repairs them, sequenced by
translation unit from smallest to largest.

This completes
[2026-07-25-i386-input-driver-binary-reconstruction-design.md](2026-07-25-i386-input-driver-binary-reconstruction-design.md),
which reconstructed the other five i386 input drivers and deferred this one
because it is the largest and most structurally divergent of the six. Everything
that effort used — reference-only profiles, `binrecon source-map`, the
`load_source_map` semantic loader, the `reconstruction/` artifact layout, the
`ledger-v1` vocabulary, `tools/binrecon/parity_check.py`, and
`vm/build-i386-input-recon.sh` — is in place and proven on six drivers, and is
reused unchanged.

## Motivation

`src/drivers-i386/README` marks `drvISASerialPort` "needs compiled and then
tested". The input-driver effort described it as failing to compile; that is no
longer true (§2.1). Scoping this work read the reference Mach-O, ran the
analyzers, and built the driver on the Rhapsody guest, and found the divergence
is concentrated in *structure* rather than logic: the reference is four
translation units where ours is one file (§2.2), it keeps driver state in
file-scope statics where ours keeps it in instance variables (§2.3), and its
entire chip identification table is absent from our tree (§2.5).

`__text` is only 2.3% over the reference, yet just 16 of 30 sections match. That
gap is the shape of this work.

## 1. Scope

### 1.1 Target

| Driver | Reference binary | File size | `__text` | Functions | Hand-written |
| --- | --- | --- | --- | --- | --- |
| drvISASerialPort | `ISASerialPort.config/ISASerialPort_reloc` | 67328 | 24412 | 45 | 43 |

SHA-256 `4CAA1BB9E8CE3309560F14E352F3D68902EA1C59937DC84DBB5EBCDA330EA932`.
The binary retains a full symbol table, so address-to-name resolution is exact
rather than inferred. The two functions that are not hand-written are the
build-generated glue described in the prior spec's §2.8.

### 1.2 Config table is in scope

`ISASerialPort.drvproj/Default.table` is compared against the reference copy, as
in both prior specs. It is checked-in source, not build output.

`"Driver Version"` is emitted by Apple's build and stays out of the comparison.

### 1.3 Out of scope

`src/kernel-7` is untouched. No other driver is touched.

No attempt is made to obtain or cross-build an i386 libgcc (§2.8). No
`Unload_Commands.sect` — the reference has no such section. No boot testing, no
QEMU run, and no binrecon comparison of a rebuilt artifact against the reference;
verification is defined in §4.2.

## 2. Findings that shaped this design

All of these come from reading the reference Mach-O, running the analyzers, and
building the driver on the guest, before any reconstruction work.

### 2.1 The driver builds now — that changed since it was deferred

The input-driver spec recorded this driver as failing to compile. Commit
`bc46d79d` ("drvISASerialPort: convert to C89 and drop conflicting
declarations") fixed that. `kl_ld` now links a 202028-byte `_reloc`.

What remains is not a compile error but the same packaging rule that drvPCParallel
hit: `post_copy_tables` runs `chmod` on `$(NAME).config/*.table`, which does not
exist because the table lives in the `.drvproj` directory, so `gnumake` exits 2
after a successful link. drvPCParallel's fix applies verbatim —
`GLOBAL_RESOURCES = Default.table`, matching the four sibling input drivers.

This is fixed in Phase 0 rather than later, because until it is fixed every
subsequent phase's "build exits 0" gate is vacuous.

### 2.2 The reference is four translation units plus libgcc; ours is one file

The boundaries are not guessed. `_RX_enqueueLongEvent` is a `static` emitted
**three** times, and `_xxx.86` — the `outb()` inline-asm static from
`driverkit/i386/ioPorts.h` — appears exactly **four** times, once per translation
unit that performs port I/O. `___clz_tab` appears twice, from two libgcc objects.

| TU | `__text` range | Size | Contents | Linkage |
| --- | --- | --- | --- | --- |
| 1 | 0–18704 | 18.7 KB | the ObjC class, `activatePort`, `deactivatePort`, four timeout handlers, `PCMCIA_yanked`, `executeEvent`, `FIFOIntHandler`, `NonFIFOIntHandler` | all `local` |
| 2 | 18704–20684 | 2.0 KB | `identifyChip`, `initChip`, `programChip` | all `external` |
| 3 | 20684–23200 | 2.5 KB | `TX_enqueueEvent`, `RX_dequeueEvent`, `RX_dequeueData`, `validateRingBufferSize`, `freeRingBuffer`, `allocateRingBuffer` | all `external` |
| 4 | 23200–23776 | 0.6 KB | `flowMachine`, `watchState` | all `external` |

After TU 4 come the two glue methods (23776, 23788) and libgcc's `__udivdi3`
(23800) and `__umoddi3` (24064).

The reference's 11 externally defined `__text` symbols are **exactly** TUs 2–4's
functions. That is the cross-module interface, and it determines what
`ISASerialPortInternal.h` must declare.

Our `ISASerialPort.m` is 5349 lines holding all of it.

### 2.3 The state model is inverted

`__OBJC,__instance_vars` is **28 bytes** in the reference and **820** in ours.

**The report pass corrected this section's original explanation.** It is not that
Apple scatters driver state into file-scope statics; it is that Apple keeps
**exactly two instance variables** — an embedded 304-byte `Port` struct at offset
296, and a pointer to it at 600. The `__instance_vars` metadata is 28 bytes
because an `ivar_list` is 4 bytes of count plus 12 per ivar, and 4 + 12×2 = 28,
confirmed by decoding the section directly.

That single design choice explains the rest of the driver. The 11 exported C
functions take a `Port *` or a `Queue *` — **none of them takes an
`ISASerialPort *`** — so they reach driver state through a plain C struct pointer
and never need the `@interface`. Our ~30 scattered ivars consolidate into one
embedded struct rather than dispersing into statics.

`_Chip` (180 bytes, 9 entries × 20) and `_msr_state_lut` (16 bytes) are genuinely
file-scope in `__DATA,__data`, as are four `_xxx.NN` sets in `__DATA,__bss` — but
those are tables and compiler residue, not per-port state.

This is the largest structural change in the effort and the reason every ivar
dereference in the reference disassembly is currently unmatchable against our
source. Per the approved decision, the inversion is carried out in full, targeting
the reference's 28 bytes.

### 2.4 All 24 missing symbols are C functions

`parity_check.py` reports 24 missing `__text` symbols, and every one is a C
function that is `static` in our source where the reference exports it, or is
spelled one underscore deeper: `_activatePort`, `_deactivatePort`, `_identifyChip`,
`_initChip`, `_programChip`, `_RX_enqueueLongEvent`, `_TX_enqueueEvent`,
`_RX_dequeueEvent`, `_RX_dequeueData`, `_validateRingBufferSize`,
`_freeRingBuffer`, `_allocateRingBuffer`, `_flowMachine`, `_watchState`,
`_executeEvent`, `_FIFOIntHandler`, `_NonFIFOIntHandler`, `_PCMCIA_yanked`,
`_dataLatTOHandler`, `_frameTOHandler`, `_delayTOHandler`, `_heartBeatTOHandler`,
`__udivdi3`, `__umoddi3`.

`parity_check.py` compares symbol **names** only, so a `static`-versus-`external`
change is invisible to it. Linkage must be verified by reading the rebuilt
binary's nlist directly with `binrecon.macho.read_macho`, checking `binding` and
`section`. That is the method that confirmed the linkage work on the other six
drivers.

### 2.5 The chip identification table is absent

The reference names twelve parts, backed by the 180-byte `_Chip` table:

```
82510, ST16C650, 16650, 16C1550, 16550AF/C/CF, 16550,
16550 with defective FIFO, 16C1450, 8250A or 16450, 16450, 8250, Unknown
```

plus `Auto`. Our source names a different, smaller set — `16550A`, `16750`,
`16950`, `16550?` — and has no equivalent table. `identifyChip` must be written
from the reference disassembly against the decoded `_Chip` layout.

### 2.6 Every config key differs

| Reference | Ours |
| --- | --- |
| `Chip Type` | `ChipType` |
| `Bus Type` | `PortType` |
| `Chip Clock` | `ClockRate` |
| `Heart Beat Interval` | `HeartBeat` |
| `TX Buffer Size` | `TXBufSize` |
| `RX Buffer Size` | `RXBufSize` |
| `Enable MSR Interrupts` | *(absent)* |
| `Instance` | `PortNum` |
| `Serial` | *(absent)* |

Every key our code reads is one the shipped `Default.table` never supplies, so
every one parses as absent. This is the same class of defect that stopped
`drvPS2Mouse` loading and that disabled `Intel824X0PCI` — at nine keys rather than
one.

29 `__cstring` entries are missing in total: these keys, the chip names from §2.5,
and nine `IOLog` format strings.

### 2.7 Two one-line scaffolding defects

`Default.table` is missing the `"Version" = "5.00"` line the reference carries.

`Load_Commands.sect` is **163 bytes and must be 164**: its first line is `#\n`
where the reference has `# \n`, with a trailing space. That same one-byte defect
has now been found in four of the six input drivers.

The reference has **no** `Loaded Server,Unload Commands` section — unlike
drvBusMouse, drvPS2Keyboard, drvPS2Mouse and drvSerialPointingDevice, and like
drvPCParallel. None is to be created.

### 2.8 The 64-bit division helpers are a decompiler artifact

Our source declares `__udivdi3` and `__umoddi3` as explicit four-argument
functions and **calls them directly** at `ISASerialPort.m:3308-3309` and
`:3934-3935`. That is not how these work: gcc emits calls to them implicitly from
ordinary `unsigned long long` division and modulo. The four-argument form is a
decompiler rendering of `call ___udivdi3` with the 64-bit operands already pushed.

The call sites become plain 64-bit arithmetic, which is what Apple's source must
have said.

The hand-written helpers themselves **stay**, as a documented substitute for an
i386 libgcc this host does not have: `/usr/lib/libcc.a` on the guest is a PPC
archive, and linking drvPCParallel emitted
`ld: warning /usr/lib/libcc.a archive's cputype (18, architecture ppc) does not
match cputype (7) for specified -arch flag: i386 (can't load from it)`.
Because our source names them `__udivdi3`/`__umoddi3` in C, the compiler emits
`___udivdi3`/`___umoddi3`, which is exactly what gcc's implicit calls resolve to —
so removing the explicit calls does not break the link.

`___clz_tab` therefore stays absent, leaving `__TEXT,__const` at roughly 196
against the reference's 682. That ~486-byte gap is a recorded environment
limitation, not a finding to chase.

### 2.9 Evidence is IDA and angr, not Ghidra

With Ghidra enabled, normalization aborts with
`Ghidra relocation operand metadata is ambiguous` (`normalize.py:432`), leaving
`complete: false` and no reference consensus. This is the same known binrecon
limitation that affects three of the five drivers in the prior effort, approved
there and applying unchanged here.

Ghidra is therefore disabled in this driver's profile. IDA and angr complete with
`complete: true` and a valid reference consensus; IDA reports 45 functions,
matching the symbol count exactly. `divergences.md` states the reduced analyzer
set as a limitation of this driver's evidence, and its analyzer-disagreement
section compares IDA against angr only.

Fixing `normalize.py` remains the better answer and belongs to its own effort,
because twelve already-committed reconstructions depend on that code.

### 2.10 The starting point, measured

| Section | Reference | Ours |
| --- | --- | --- |
| `__TEXT,__text` | 24412 | 24980 |
| `__TEXT,__cstring` | 742 | 649 |
| `__TEXT,__const` | 682 | 196 |
| `__DATA,__data` | 196 | 36 |
| `__OBJC,__class` | 120 | 120 |
| `__OBJC,__instance_vars` | 28 | 820 |
| `Loaded Server,Load Commands` | 164 | 163 |

Sections matching by size: **16 of 30** — the weakest start of any driver in
either effort, despite `__text` being only 2.3% over. The divergence is
structural, not logical.

## 3. Artifact layout

### 3.1 Committed

```
src/drivers-i386/input/drvISASerialPort/reconstruction/
    source-map.json      # source-map-v1, complete 45-function partition
    ledger.json          # ledger-v1, human-reviewed parity ledger
    divergences.md       # report-pass findings, including table divergences
```

Also committed: `tools/binrecon/profiles/isaserialport.json`, a reference-only
profile copied from `parallelport.json` with `analyzers.ghidra.enabled: false`
(§2.9) and `output_dir` set to `../out/isaserialport`; and a `drvISASerialPort`
case added to `vm/build-i386-input-recon.sh`'s `case` dispatch.

### 3.2 Not committed

The reference binary (already external to the repo), the rebuilt `_reloc` staged
under `out/i386/` — which `.gitignore` excludes — and all analyzer output under
`tools/binrecon/out/`.

### 3.3 Reference path

`BINRECON_REFERENCE` is per-shell-session:

```
C:\Users\raynorpat\Downloads\test\Drivers\i386\ISASerialPort.config\ISASerialPort_reloc
```

### 3.4 The four translation units

TU 1 is **`ISASerialPort.m`**, confirmed from `__OBJC,__module_info`, which names
exactly two modules: `ISASerialPort.m` and the build-generated
`ISASerialPort_instance.m`.

The other three filenames are **not recoverable from the binary**. Apple's build
recorded only Objective-C modules, and TUs 2–4 contain no Objective-C, so they
have no `module_info` entry. The names below are ours, chosen for their contents,
and `divergences.md` must say so plainly — otherwise a later reader will mistake
them for recovered facts.

| TU | File | Exports |
| --- | --- | --- |
| 1 | `ISASerialPort.m` *(confirmed)* | nothing; all `local` |
| 2 | `ISASerialPortChip.c` *(our name)* | `identifyChip`, `initChip`, `programChip` |
| 3 | `ISASerialPortQueue.c` *(our name)* | `TX_enqueueEvent`, `RX_dequeueEvent`, `RX_dequeueData`, `validateRingBufferSize`, `freeRingBuffer`, `allocateRingBuffer` |
| 4 | `ISASerialPortFlow.c` *(our name)* | `flowMachine`, `watchState` |

`.c` rather than `.m` because they hold no Objective-C, which means they belong in
the Makefile's `CFILES` and not `CLASSES`.

One new header, `ISASerialPortInternal.h`, carries the 11 external declarations
and the file-scope state TU 1 shares with them. It lands in the **first** fix-pass
phase, because every phase must leave the driver linking.

File names do not affect `__text` layout, so this naming choice cannot affect
parity. It affects the Makefile and any future address-based re-mapping only.

### 3.5 A finding the reference volunteers

`__OBJC,__class_names` shows the class conforms to a **`PortDevices`** protocol,
alongside `IODirectDevice`, `IODevice` and `Object`. Protocol conformance is part
of TU 1's phase.

## 4. The two passes

### 4.1 Report pass

Runs once, needs no VM.

1. **Analyze.** `binrecon analyze --profile tools/binrecon/profiles/isaserialport.json`
   produces IDA 9.2 and angr 9.3.0 analyses plus `consensus-reference.json` under
   the gitignored `tools/binrecon/out/isaserialport/`. **Expect exit 1**:
   reference-only profiles can never satisfy `normalized-functions` acceptance,
   because that compares a reference against a rebuilt artifact. The gate is
   `complete: true` plus a reference consensus, never the exit code.

2. **Map.** `binrecon source-map` against our single `ISASerialPort.m`. All 45
   functions map to one file; the four-TU boundaries are recorded as a finding
   with their address ranges but are not yet enacted. Every function lands in
   exactly one bucket: `mapped`, `unmapped` (build-generated glue),
   `boundary_disputed`, or `duplicate_candidates`.

3. **Diff.** Read the disassembly of every mapped function against our source:
   control-flow shape, literal constants, I/O port addresses and access
   directions, struct field offsets, call targets.

4. **Compare the table.** Diff `Default.table` against the reference, ignoring
   `"Driver Version"`.

5. **Report.** Write `divergences.md` with reference disassembly beside our source
   per finding, and assign each function a `ledger-v1` status. A function that
   matches gets the strongest status the evidence supports; one that diverges
   stays `unexamined` with a `divergences.md` entry. `rebuilt_sha256` is `null`
   throughout.

Two obligations this report pass carries that its six predecessors did not:

- **Decode the `_Chip` table field by field.** All 180 bytes. `identifyChip` is
  written from it in Phase 4, and a gap here becomes an invention there.
- **Confirm which side of each TU boundary every function falls on.** The symbol
  addresses are a strong prior — the three `_RX_enqueueLongEvent` copies and four
  `_xxx.86` sets agree — but the disassembly is the evidence.

**Done when** `load_source_map(path, reference_analysis=…, repo_root=…)` prints
`source map OK`, every `unmapped` entry has a stated reason class, and no function
lacks a ledger entry.

### 4.2 Fix pass, sequenced TU 4 → 3 → 2 → 1

Four phases, smallest translation unit first. TUs 4, 3 and 2 total 5.1 KB, have
clean external interfaces, and are independently verifiable. TU 1 is 18.7 KB and
calls into all three, so it goes last with three settled modules beneath it.

**Every phase leaves the driver linking.** That is why `ISASerialPortInternal.h`
and the §2.3 ivar-to-static inversion arrive in the first phase rather than the
last: an exported C function in another translation unit cannot reach an instance
variable, so the inversion is what makes extraction possible at all.

**Verification per phase**, matching the prior spec's §4.3:

1. **Compiles.** `vm/build-i386-input-recon.sh drvISASerialPort` exits 0 and stages
   a `_reloc`. Warnings are captured and reviewed but do not gate.
2. **String and symbol parity.** `tools/binrecon/parity_check.py` against the
   reference. Reported, not gated: our build is unstripped and carries extras. A
   reference string or symbol missing from our build is a finding; an extra one of
   ours is not automatically a finding.
3. **Linkage.** Read the rebuilt nlist directly (§2.4). `parity_check.py` cannot
   see linkage.
4. **Sections.** Compare section sizes against the reference, so progress from the
   current 16 of 30 is visible per phase.
5. **Reline.** Regenerate the source map and the ledger's `source_line` values,
   and confirm `load_source_map` prints `source map OK`. This is mandatory and is
   the step most easily forgotten — in the prior effort a fix pass left its map
   pointing past the end of the file, and another left it pinned to an uncommitted
   tree.

**Disposition.** Every `divergences.md` finding resolves one of two ways: the
source changes to match the reference and the ledger status advances to what the
new evidence supports, or the divergence is accepted as `intentional-mismatch`
with both a reason and a reviewer. No entry ends `unexamined`.

**Ledger honesty.** `assembly-matched` means the rebuilt instruction stream was
read against the reference. `control-flow-confirmed` means block shape and call
targets were checked but not every instruction. Six of the prior effort's thirteen
tasks had defects caught by review, and three were caught on precisely this. A
status stronger than the work performed is the worst failure mode available here.

**Constants resolve to definitions, never to comments.** Our source's inline
comments beside named constants have been wrong four separate times in the sibling
effort — most sharply an `IODelay(30)` whose comment claimed 30 ms while the code
delayed 30 µs against a reference wanting 30 ms, and a set of `IO_R_*` names whose
comments disagreed with `return.h`. This driver's `__udivdi3` comments (§2.8) are
another instance.

## 5. Sequencing

**Phase 0 — tooling and scaffolding.** Write `tools/binrecon/profiles/isaserialport.json`.
Add the `drvISASerialPort` case to `vm/build-i386-input-recon.sh`. Land the three
fixes that need no disassembly: the missing `"Version" = "5.00"` line,
`Load_Commands.sect` 163 → 164 bytes, and `GLOBAL_RESOURCES = Default.table`
(§2.1, §2.7).

*Verify:* `binrecon validate` prints the reference identity with no rebuilt
artifact; `gnumake` exits 0; `Default.table` differs from the reference only in
`"Driver Version"`; `Load_Commands.sect` is 164 bytes.

**Phase 1 — report pass.** §4.1, against the single `ISASerialPort.m`.

*Verify:* `load_source_map` prints `source map OK`.

**Phase 2 — TU 4 and the structural foundation** (0.6 KB). Create
`ISASerialPortInternal.h`. Perform the §2.3 ivar-to-static inversion. Extract
`flowMachine` and `watchState` into `ISASerialPortFlow.c` with `external` linkage.

*Verify:* the five §4.2 checks.

**Phase 3 — TU 3** (2.5 KB). Extract the six ring-buffer functions into
`ISASerialPortQueue.c`.

*Verify:* the five §4.2 checks.

**Phase 4 — TU 2** (2.0 KB). Extract `identifyChip`, `initChip` and `programChip`
into `ISASerialPortChip.c`. Write the `_Chip` table from the report pass's decode
and rewrite `identifyChip` against it, replacing our four invented part names with
the reference's twelve (§2.5).

*Verify:* the five §4.2 checks, plus `identifyChip`'s size against the reference's
684 bytes (§6).

**Phase 5 — TU 1** (18.7 KB). The class itself. The nine config-key fixes land
here — seven renames plus `Enable MSR Interrupts` and `Serial`, which our source does
not read at all — because `initFromDeviceDescription:` (address 264) reads them
(§2.6). Also
the `PortDevices` protocol conformance (§3.5) and the §2.8 division fix.

*Verify:* the five §4.2 checks.

**Phase 6 — README.** Update the `drvISASerialPort` status line in
`src/drivers-i386/README` — the one line the prior effort deliberately left
alone — to the wording its five siblings now use.

## 6. Failure modes

**The ivar-to-static inversion is the single riskiest change.** 820 bytes of
instance variables down to 28. The interrupt handlers `FIFOIntHandler` and
`NonFIFOIntHandler` run at raised IPL and read this state; misclassifying one
field's storage could produce a fault no static check catches. Mitigation: the
reference's 28 bytes are decoded field by field in the report pass, and the
inversion follows that decode rather than following which fields the exported C
functions happen to touch.

**A function placed on the wrong side of a TU boundary shifts every later
address.** The symbol addresses agree with the repeated-static evidence, but the
report pass must confirm each boundary from the disassembly rather than assume it.

**Three of the four filenames are inventions** (§3.4). They cannot affect parity,
but `divergences.md` must label them as ours so they are not later mistaken for
recovered facts.

**`identifyChip` written from disassembly can overfit.** The reference is 684
bytes. A rebuilt function materially larger means structure was invented rather
than reconstructed. Per-function size against the reference is the check, as it
was for drvBusMouse.

**The libgcc gap is permanent on this host** (§2.8). `___clz_tab` stays absent and
`__TEXT,__const` settles near 196 against 682. Recorded, not chased.

**Evidence is two analyzers** (§2.9). IDA is authoritative for the partition;
angr is the independent second opinion. Disagreements go to `boundary_disputed`
for human resolution rather than being voted away.

**angr `CFGFast` misses on indirect control flow** are recorded as CFG errors and
never read as "function absent".

**A failed or timed-out analyzer run** yields `complete: false` and cannot report
passing acceptance. Leftover output from an earlier run is never accepted as
evidence.

**The Rhapsody guest may be unavailable.** Phase 0's scaffolding fixes and the
Phase 1 report pass still deliver in full; Phases 2 through 5 block.

## 7. Deliverables

- `src/drivers-i386/input/drvISASerialPort/reconstruction/source-map.json`
- `src/drivers-i386/input/drvISASerialPort/reconstruction/ledger.json`
- `src/drivers-i386/input/drvISASerialPort/reconstruction/divergences.md`
- `tools/binrecon/profiles/isaserialport.json`
- `ISASerialPortInternal.h`, declaring the 11 exported functions and the shared
  file-scope state
- `ISASerialPortChip.c`, `ISASerialPortQueue.c`, `ISASerialPortFlow.c`
- `ISASerialPort.lksproj/Makefile` extended with `CFILES` and the new header
- `ISASerialPort.lksproj/Load_Commands.sect` corrected to 164 bytes
- `ISASerialPort.drvproj/Default.table` gaining `"Version" = "5.00"`
- `ISASerialPort.drvproj/Makefile` gaining `GLOBAL_RESOURCES = Default.table`
- `vm/build-i386-input-recon.sh` extended to `drvISASerialPort`
- `src/drivers-i386/README` status line updated

Not deliverables: any `Unload_Commands.sect`, any change under `src/kernel-7`, any
i386 libgcc work, any `normalize.py` change to re-enable Ghidra, and any boot
test.
