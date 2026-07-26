# Binary reconstruction of the PowerPC SCSIServer

Reconstruct `src/drvSCSIServer` against Apple's shipped PowerPC `SCSIServer_reloc`,
using the `tools/binrecon` toolchain. A report pass dispositions every reference
function and records the divergences; a fix pass then repairs them, sequenced by
translation unit.

This is the second of three specs. The first,
[2026-07-26-binrecon-ppc-support-design.md](2026-07-26-binrecon-ppc-support-design.md),
taught binrecon to read big-endian PowerPC Mach-O and drive IDA against it; it is
complete and merged, and its seven analyses are on disk under
`tools/binrecon/out/*-ppc/`. The third spec covers `SCSITape`.

## Motivation

`src/drvSCSIServer` is an unverified reimplementation — `SCSIServer.m` (431
lines) and `IOSCSISession.m` (2627 lines) — that has never been compared against
Apple's binary. Scoping this work ran the comparison, and roughly half the
driver's code has no counterpart in our source: **41 of 68 reference functions
map, 27 do not**, 5724 unmapped bytes against 5796 mapped.

The reason is structural. The project is `PROJECTTYPE = "Kernel Server"` and has
**no MiG interface definition**. Apple's binary contains a MiG-generated interface —
18 `__XIOSCSISession_*` server routines plus the `_IOSCSISessionMig_server`
demux. Our tree hand-writes that apparatus instead: a 562-line block holding a
demux, 18 `_IOSCSISession_*_handler` functions and a
`_IOSCSISessionMig_handlers[18]` dispatch table, written from decompiler output
(its comments say so, and use `param_1`-style names).

**That hand-written dispatch table is wired wrong on every entry** (§2.2). The
driver could not have worked, and nothing in our source reveals it — the correct
order exists only in Apple's binary.

## 1. Scope

### 1.1 Target

| Driver | Reference binary | File size | `__text` | Named functions | Jump islands |
| --- | --- | --- | --- | --- | --- |
| drvSCSIServer | `SCSIServer.config/SCSIServer_reloc` | 51044 | 13744 | 68 | 138 |

SHA-256 `E813777748A4FAC9348AA1CF4E979863B96D75B09FDAC16DF586031499A122A2`.
The binary retains a full symbol table including Objective-C method names, so
address-to-name resolution is exact rather than inferred.

Analysis of record: `tools/binrecon/out/scsiserver-ppc/published/analysis-reference-ida.json`
(IDA 9.2, produced by spec 1's acceptance run). Regenerating it is not required;
if it is regenerated, its `input.sha256` must still match the value above.

### 1.2 Starting state

Measured with `binrecon source-map` against the current tree:

| Bucket | Count | Bytes |
| --- | --- | --- |
| mapped | 41 | 5796 |
| unmapped | 27 | 5724 |
| duplicate_candidates | 0 | — |
| boundary_disputed | 0 | — |

The 27 unmapped entries fall into four groups:

| Group | Count | Bytes |
| --- | --- | --- |
| `__XIOSCSISession_*` MiG server routines | 18 | 3732 |
| Mach task / memory / notification plumbing | 5 | 1364 |
| `-[IOSCSISession initServerWithTask:sendPort:]`, `_serverThreadFunc` | 2 | 592 |
| Build-generated Objective-C classes | 2 | 36 |

`selector_check.py` against the same sources reports 1 rename, 0 duplicates,
2 missing (both build-generated) and 1 extra.

### 1.3 Out of scope

The 138 unnamed 16-byte jump islands (`lis`/`mr`/`mtctr`/`bctr`) are
build-generated branch glue, not source. They are excluded from source mapping
and recorded once in `divergences.md`.

`+[SCSIServerKernelServerInstance kernelServerInstance]` and
`+[SCSIServerVersion driverKitVersionForSCSIServer]` are emitted by the Kernel
Server build from the project's own settings. They are recorded, not written by
hand, and remain in the `unmapped` bucket when the work is done.

No PowerPC build is attempted (§4.1). No other driver is touched. `src/kernel-7`
and `src/driverkit-3` are untouched. The `SCSITape` driver is spec 3.

## 2. Findings that drive the work

### 2.1 The MiG interface is recoverable from the binary

Every fact the `.defs` needs is present in the reference:

| Fact | Value | Evidence |
| --- | --- | --- |
| Subsystem name | `IOSCSISessionMig` | the demux symbol is `_IOSCSISessionMig_server`; MiG names a subsystem's demux `<subsystem>_server` |
| Subsystem base message ID | 4242 (`0x1092`) | demux `addic r0, r0, -0x1092` |
| Routine count | 18 | demux `cmplwi cr1, r0, 0x11` + `bgt` |
| Reply message ID | request + 100 | demux `addic r0, r0, 0x64` |
| Routine names | `IOSCSISession_free`, `IOSCSISession_initForDevice`, … | MiG emits a server stub as `_X<routine>`, matching the `__XIOSCSISession_*` symbols |
| Routine order | see §2.2 | the 18 relocations in `__TEXT,__const` at `0x37a4` |
| Per-routine signature | request/reply sizes, argument count and direction | each `__X` stub's field loads and stores |

The subsystem name matters for more than the demux: `pb_makefiles` derives the
generated filenames from the `.defs` basename, so the file must be
`IOSCSISessionMig.defs` (§3.6). Naming it `IOSCSISession.defs` would make MiG
generate an `IOSCSISession.h` that collides with our hand-written header.

The demux reaches its dispatch table through `lis r9, 0` / `addi r9, r9, -0xAA4`
— the scattered `HA16`/`LO16` relocation pair whose 32-bit wrap broke the
exporter during spec 1. `r_value` is `0x37a4`, inside `__TEXT,__const`.

### 2.2 The dispatch table order is wrong on every entry

Apple's table, read from those 18 relocations, against ours from
`IOSCSISession.m`:

| Msg ID | Apple | Ours |
| --- | --- | --- |
| 4242 | `free` | `reserveSCSI3Target` |
| 4243 | `initForDevice` | `releaseSCSI3Target` |
| 4244 | `releaseAllUnits` | `reserveTarget` |
| 4245 | `reserveTarget` | `releaseTarget` |
| 4246 | `releaseTarget` | `executeSCSI3Request` |
| 4247 | `reserveSCSI3Target` | `executeSCSI3RequestScatter` |
| 4248 | `releaseSCSI3Target` | `executeSCSI3RequestOOLScatter` |
| 4249 | `numberOfTargets` | `executeRequest` |
| 4250 | `executeRequest` | `executeRequestScatter` |
| 4251 | `executeSCSI3Request` | `executeRequestOOLScatter` |
| 4252 | `executeRequestScatter` | `resetSCSIBus` |
| 4253 | `executeSCSI3RequestScatter` | `numberOfTargets` |
| 4254 | `executeRequestOOLScatter` | `getDMAAlignment` |
| 4255 | `executeSCSI3RequestOOLScatter` | `maxTransfer` |
| 4256 | `resetSCSIBus` | `releaseAllUnits` |
| 4257 | `returnFromScStatus` | `free` |
| 4258 | `maxTransfer` | `initForDevice` |
| 4259 | `getDMAAlignment` | `returnFromScStatus` |

No message ID dispatches to the correct routine. The ID range and the range
check are right; only the order is wrong. Authoring the `.defs` fixes this by
construction, because MiG emits the table in routine order.

### 2.3 A misread PIC displacement

Our source comments on the `-0xaa4` offset: "you would need to use linker
scripts or compiler-specific directives to place this at the correct address."
That misreads a position-independent displacement — the table's offset from the
code's anchor register — as a required absolute address. Nothing needs placing
anywhere. This belief is why the author treated a faithful reconstruction as
impossible, so it is recorded as a finding in its own right.

### 2.4 Six functions absent, one misnamed, one invented

Absent from our sources entirely, to be reconstructed from disassembly:

| Function | Bytes | State in our tree |
| --- | --- | --- |
| `__io_task_notification` | 644 | absent |
| `_IORequestNotifyForClientTask` | 480 | declared `extern`, never defined |
| `_serverThreadFunc` | 276 | absent |
| `_IOConvertTaskPortToVMTask` | 160 | absent |
| `_IOTaskPortAllocate` | 48 | absent (only `_IOTaskPortAllocateName` exists) |
| `_IODestroyMappedVMTask` | 32 | absent |

Misnamed: `-[IOSCSISession(Private) _initServerWithTask:sendPort:]`
(`IOSCSISession.m:234`) carries a spurious leading underscore; Apple's is
`-[IOSCSISession(Private) initServerWithTask:sendPort:]`. The category is
already correct.

Invented: `-[IOSCSISession(Private) _reserveTarget:lun:]` has no counterpart in
the reference. The report pass dispositions it — deleted if we invented it,
explained if it corresponds to something Apple named differently.

### 2.5 Translation-unit boundaries

Link order makes one object file's functions contiguous, so a change of name
family across a contiguous block is evidence of a boundary:

| Address range | Contents | Inferred unit |
| --- | --- | --- |
| 0–1096 | `SCSIServer` class methods | `SCSIServer.m` |
| 1160–2948 | `IOSCSISession` methods, reservations, `_serverThreadFunc` | `IOSCSISession.m` |
| 3028–6460 | 18 `IOSCSISession_*` C wrappers | `IOSCSISession.m` (§2.6) |
| 6460–9212 | task, memory-wiring and death-notification plumbing | new `IOTask.m` |
| 9212–13708 | 18 `__XIOSCSISession_*` stubs and the demux | MiG output |
| 13708–13744 | build-generated classes | build output |

### 2.6 The 18 `IOSCSISession_*` wrappers are hand-written, and stay

MiG generates a user stub per routine, so it is worth establishing directly that
the `_IOSCSISession_*` block at 3028–6460 is *not* that generated output —
otherwise the fix pass would delete 2856 more bytes of our source in error.

It is not. `_IOSCSISession_free` (44 bytes) loads a selector reference from
`__OBJC,__message_refs` and branches to `_objc_msgSend` through a jump island:

```
mflr  r0, lr            ; prologue
lis   r4, paFree@ha     ; selector "free" from __OBJC,__message_refs
lwz   r4, paFree@l(r4)
bl    sub_CB0           ; island -> _objc_msgSend
li    r3, 0             ; return 0
blr   lr
```

`_IOSCSISession_numberOfTargets` (68 bytes) does the same and stores the result
through its out-parameter. A MiG user stub builds a request message and calls
`mach_msg`; these dispatch an Objective-C message instead. They are hand-written
C wrappers over the session object — `IOSCSISession_free(session)` is
`[session free]` — which is exactly what our tree has, and they map cleanly.

They therefore stay in `IOSCSISession.m`, and MiG's generated user side must not
be compiled into the driver (§3.6), or it would define colliding
`_IOSCSISession_*` symbols.

Their block order transposes `free`/`initForDevice` and both `Scatter`/
`OOLScatter` pairs relative to the `.defs` order, consistent with hand-written
source order. That ordering is not evidence of a separate translation unit, so
no split is made; if the report pass finds such evidence, it records it and the
fix pass may act on it.

## 3. Design

### 3.1 Two phases

**Phase 1 — report.** Produces three artifacts under
`src/drvSCSIServer/reconstruction/`, the layout every i386 pass used:

- `source-map.json` — a `source-map-v1` document, generated then hand-corrected.
- `ledger.json` — a `ledger-v1` entry per reference function.
- `divergences.md` — prose findings, following the drvEISABus and
  drvISASerialPort format: summary table, then one section per finding, each
  presenting the reference's disassembled behaviour before comparing it to ours.

Phase 1 is committed in full before any source changes, so the evidence stands
independently of the repairs and records the tree as it was found.

**Phase 2 — fix.** Source changes only, one translation unit per commit, each
citing the ledger entries it resolves. The map and ledger are regenerated at the
end so the artifacts describe the finished tree.

### 3.2 Two mechanical facts about the tooling

Both were established by running it, and both will otherwise waste time:

- The reference analysis must pass through
  `tools/binrecon/filter_named_functions.py` first. The 138 unnamed jump islands
  violate `source-map-v1`'s requirement that every function carry a name;
  unfiltered, `source-map` fails with `analysis function at address 212 has no
  names`.
- `--source-dir` and `selector_check.py`'s source argument must point at
  `src/drvSCSIServer/SCSIServer.drvproj/SCSIServer.lksproj`, not at
  `src/drvSCSIServer`. Neither scanner recurses; pointing at the project root
  silently yields 0 mapped and 68 unmapped.

### 3.3 The analyzer gap at address 0

`+[SCSIServer deviceStyle]` occupies address 0 in the symbol table, but IDA
emits no function there, so it cannot appear in `source-map.json` at all — the
map covers 68 functions, not 69. It gets a `divergences.md` entry recording that
`SCSIServer.m:37` implements it and that the absence is an analyzer artifact.
This is the same mismatch `ppc_invariant_check.py --analysis` reported during
spec 1's acceptance run.

### 3.4 Target tree

| Path | Change |
| --- | --- |
| `IOSCSISessionMig.defs` | new — subsystem `IOSCSISessionMig`, base ID 4242, 18 routines in Apple's order |
| `IOSCSISession.m` | hand-rolled MiG apparatus deleted (562 lines); task plumbing moved out; `_serverThreadFunc` added; selector renamed; the 18 C wrappers retained |
| `IOTask.m` | new — task, memory-wiring and notification plumbing, moved and completed |
| `IOTask.h` | new — declarations split out of `IOSCSISession.h` |
| `SCSIServer.m` | unchanged in responsibility; fixes only where the report finds them |
| `Makefile.preamble` | `DEFSFILES` and the generated server object (§3.6) |
| `PB.project` | `FILESTABLE` gains `IOTask.m` and `IOTask.h`; the `.defs` is listed as an other source |
| `reconstruction/` | new — `source-map.json`, `ledger.json`, `divergences.md` |

### 3.6 How the `.defs` enters the build

`pb_makefiles` distinguishes two keys, and the distinction matters:
`MIGFILES` is documented as "`.mig` files (no `.defs` files)", while `DEFSFILES`
is the list of `.defs` files to run MiG over. So the declaration goes in
`SCSIServer.lksproj/Makefile.preamble` as `DEFSFILES = IOSCSISessionMig.defs`,
not in `MIGFILES` and not in `PB.project`'s `FILESTABLE`.

`common.make:238` expands each entry into three generated sources —
`%.h`, `%User.c` and `%Server.c`. Being generated does not make them compile:
`LOCAL_OFILES` (`common.make:242`) is built from the declared source lists plus
`OTHER_GENERATED_OFILES`, so the project chooses which generated file becomes an
object.

Only the server side may be compiled. Adding `IOSCSISessionMigServer.o` to
`OTHER_GENERATED_OFILES` produces the 18 `__XIOSCSISession_*` stubs and the
`_IOSCSISessionMig_server` demux; leaving `IOSCSISessionMigUser.c` uncompiled
avoids duplicate `_IOSCSISession_*` symbols against the hand-written wrappers of
§2.6. This matches the reference binary, which contains the server stubs and the
demux but resolves `_IOSCSISession_*` to the Objective-C wrappers.

Because MiG cannot be run here, the exact flag spelling this project needs is
confirmed by reading `src/pb_makefiles-1/common.make` rather than by building.
The plan states what to read; a PowerPC build pass is what would finally prove
it.

### 3.5 Ledger vocabulary

- `assembly-matched` — reference disassembly read instruction by instruction, our
  source agrees.
- `control-flow-confirmed` — structure matches, differences cosmetic.
- `signature-confirmed` — name, size and arguments agree; body not opened.
- `intentional-mismatch` — deliberate divergence, with reason and reviewer.

All 41 mapped functions are examined at instruction level, so they end at
`assembly-matched` or `control-flow-confirmed`, or their divergence is fixed in
Phase 2. No entry remains `unexamined`.

## 4. Verification

### 4.1 What cannot be verified

There is no PowerPC compiler in this environment: `vm/` holds only
`build-i386-*.sh`, and the Rhapsody guest builds i386. **No source change in
this spec is compile-verified**, so syntax and type errors can survive to a
future build.

Two things reduce the exposure, neither a substitute for a compiler: the `.defs`
removes 562 lines of hand-written code rather than adding more, and every
reconstructed function's signature is taken from its reference disassembly
rather than invented. A PowerPC build pass is the real gate and is future work.

`parity_check.py` and `import_check.py` both require a rebuilt binary and are
therefore unavailable here.

### 4.2 Acceptance

The work is done when all of the following hold, with output shown:

1. `selector_check.py` exits 0 — renames and duplicates both empty. It reports
   1 rename today. The 2 missing entries remain (build-generated, §1.3) and the
   1 extra is dispositioned.
2. The regenerated `source-map.json` reports **48 mapped, 20 unmapped**, 0
   duplicate_candidates, 0 boundary_disputed.

   The 48 are the 41 that map today plus the seven this work supplies: the
   renamed `initServerWithTask:sendPort:`, `_serverThreadFunc`, and the five
   absent plumbing functions of §2.4. The 20 are the 2 build-generated classes
   plus the 18 `__XIOSCSISession_*` stubs.

   The stubs stay unmapped for a mechanical reason worth stating rather than
   discovering: `source-map` maps a reference function to a *source site in the
   tree*, and MiG's generated `IOSCSISessionMigServer.c` does not exist here
   because MiG cannot run in this environment. Recovering the `.defs` is what
   makes those stubs correct; it cannot make them mapped. A build pass that runs
   MiG would move all 18 into `mapped` and take the totals to 66/2.
3. `load_source_map` accepts the checked-in map against the reference analysis
   and the files on disk, validating the exact function partition, names, sizes
   and source-line bounds.
4. All 68 ledger entries carry a status, a reviewer and a reason; none is
   `unexamined`.
5. `ppc_invariant_check.py --binary SCSIServer_reloc --analysis <analysis>`
   still reports 0 relocation violations, confirming the evidence base did not
   shift. The one known symbol-versus-function-start mismatch
   (`+[SCSIServer deviceStyle]` at 0) is expected and is §3.3's subject.
6. `divergences.md` records every finding in §2, each with the reference
   evidence that establishes it.

This project has no test suite for driver source, unlike spec 1's tooling. These
checks prove structural correspondence to Apple's binary; they do not prove the
driver builds or runs, and the spec does not claim otherwise.

## 5. Follow-on work

- **Spec 3 — SCSITape reconstruction.** `SCSITape_reloc`'s 51 `__text` symbols
  across `SCSITape.m` and `SCSITapeKern.m`, plus the three user-space helpers
  against `PreLoad`, `PostLoad` and `stblocksize`.
- **A PowerPC build.** Until one exists, every PowerPC reconstruction is
  structurally verified but not compile-verified. Standing this up would let
  `parity_check.py` and `import_check.py` run and would turn §4.1's caveat into
  a real gate.
