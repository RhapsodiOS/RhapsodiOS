# drvSCSIServer divergences

Reference: `SCSIServer.config/SCSIServer_reloc`, SHA-256
`E813777748A4FAC9348AA1CF4E979863B96D75B09FDAC16DF586031499A122A2`, `__text`
13744 bytes.
Analysis: IDA 9.2 (`tools/binrecon/out/scsiserver-ppc/published/analysis-reference-ida.json`).
Ghidra and angr are i386-only and cannot analyse this binary.

No PowerPC build exists in this environment, so nothing recorded here is
compile-verified. Every claim rests on the reference disassembly.

## Starting state

| Bucket | Count | Bytes |
| --- | --- | --- |
| mapped | 41 | 5796 |
| unmapped | 27 | 5724 |
| duplicate_candidates | 0 | — |
| boundary_disputed | 0 | — |

## READ THIS FIRST: SCSIServer Task 3 re-verified every finding below

**Everything under this heading was written before the SCSIServer
reconstruction's Task 3, and parts of it had already been overtaken by fixes or
were wrong when written.** Task 3 opened the current source for every finding
and re-derived the reference behaviour from the disassembly before touching
anything. Do not use a finding below as a worklist item without checking it
against the "Task 3 disposition" table immediately following.

Two claims below are **wrong as written** and are corrected in place at their
own sections:

1. `__OBJC,__protocol+0` is **not** the `IOSCSIController` protocol. Both of the
   binary's two `Protocol` records are named `IOSCSIControllerExported`, and no
   `"IOSCSIController"` string exists in `__OBJC,__class_names` at all. This
   affects the `requiredProtocols` finding and the `initForDevice` wrapper
   finding, which both assert the opposite.
2. "our source calls `objc_getClass()` where the reference loads static
   references" is right about three sites and wrong about the fourth: inside a
   *category*, the reference really does make a runtime call — to
   `_objc_getOrigClass`, which is one of its 34 imports. There are five sites,
   not four.

One further claim is wrong: `IOTaskPortAllocateName`'s finding says our call
site "passes `self`, an `id`, where the reference expects a `mach_port_t
name`". The reference passes `self` too (`mr r3, r30` at address 1300, straight
into the `bl` at 1304 whose relocation names `__TEXT,__text+6460`). Our call
site matches the reference exactly; only `IOTaskPortAllocateName`'s own body and
return type are open.

### Task 3 disposition

`already-fixed` = the source no longer matches the finding. `still-open` = it
did, and Task 3 repaired it. `claim-wrong` = the finding misdescribes the
reference. `deferred` = still open, out of Task 3's file scope.

| Finding | Verdict | Disposition |
| --- | --- | --- |
| `requiredProtocols` wrong indirection / storage class | still-open + claim-wrong | fixed: function-scope `static Protocol *protocols[] = { @protocol(IOSCSIControllerExported), nil }` |
| `probe:` logs where the reference does not | still-open | fixed: three `IOLog` calls removed |
| `initFromDeviceDescription:` wrong `registerSCSIController:` argument | already-fixed (`c3a70903`) | none |
| `initFromDeviceDescription:` extra `IOLog` | still-open | fixed |
| `registerSCSIController:` extra `IOLog` | still-open | fixed |
| `serverConnect:taskPort:` wrong (underscored) selector | already-fixed (`b2d798bd`) | none |
| `getCharValues:forParameter:count:` extra bounds guard | still-open | resolved the other way: the `if (bytesWritten > 0)` guard stays, and Apple's `values[-1]` underflow is recorded as `intentional-mismatch` at address 772 |
| `objc_getClass()` vs static references | still-open + claim-wrong | fixed at all five sites, as plain `[super ...]` / `[IOSCSISession alloc]` |
| twelve wrappers never send their message | still-open | fixed: all twelve now dispatch |
| `IOSCSISession_returnFromScStatus` declared `void` | still-open | fixed: `int` in `IOSCSISession.h` and `.m`, returning the dispatched value |
| `-[IOSCSISession free]` drops `IOTaskPortDeallocate`'s argument | already-fixed (`5b4d62ec`) | none |
| `-[IOSCSISession free]` returns `self` | already-fixed | none |
| `-[IOSCSISession free]` cleanup callback | still-open | fixed: direct `IOExitThread()`, callback typedef and extern removed |
| OOL wrappers' "`vm_deallocate`" guess | still-open | fixed: `IOUnmapPhysicalFromIOTask` |
| `_removeReservation` pointer arithmetic | already-fixed (`5c17f9cb`) | none |
| session-structure comment's swapped next/prev | already-fixed (`e853646a`) | none |
| `_reserveTarget:lun:` dead duplicate method | already-fixed (`bc7c14da`) | none |
| `IOSCSIControllerExported` undeclared | already-fixed (`47f6a92c`) | none |
| `IOTaskWireMemory` declared `void` | already-fixed (`84fffeb1`) | none |
| `IOSCSISession_initForDevice` missing `deviceNameCnt` | already-fixed (`b6c5147d`) | none |
| `IODereferenceClientTask` wrong table/offset | already-fixed (`92384e9b`, `a495abfc`) | none |
| `IOReleaseNotifyForFunc` call-site argument | already-fixed (`2b33628e`) | none |
| MiG dispatch-table order; PIC-displacement comment | moot (`5ac4f5c7` deleted both) | none |
| `IOTaskPortAllocateName`'s `self` argument | claim-wrong | none needed; recorded above |
| `IOTaskPortAllocateName` / `IOTaskPortDeallocate` / `IOTaskUnwireMemory` / `IOReferenceClientTask` / `IODereferenceClientTask` stub bodies; `IOReleaseNotifyForFunc`'s `notifClientObjects` | still-open | five stub bodies still open; `notifClientObjects` **closed by Task 4** |
| six functions our tree lacks entirely | still-open | **closed by Task 4** |

**New finding Task 3 recorded but did not fix:**
`-[IOSCSISession initServerWithTask:sendPort:]` (address 1160) writes
`session_struct+0x14` from `IOForkThread(&_serverThreadFunc, self)` (addresses
1352-1372; the `bl` at 1364 relocates to `_IOForkThread`), not from
`objc_msgSend(self, (SEL)0xa70)` as our source has it. Fixing it requires
`_serverThreadFunc`, one of the six absent functions, so it belongs with them.
Full evidence in `reconstruction/SCSIServer/findings.md`.
**Closed by Task 4**, which wrote `_serverThreadFunc` and then replaced the
message send at `IOSCSISession.m` with
`IOForkThread((IOThreadFunc)serverThreadFunc, self)`.

## Task 4: the six absent functions

All six are written, in `IOTask.m` (five) and `IOSCSISession.m` (one). The
per-function instruction accounts are in `.superpowers/sdd/task-4-report.md`
and in the comment heading each definition; three findings are worth carrying
here because they correct statements elsewhere in this file:

- **`_entry` is `IOTask_kern`**, and its fields are `map`/`itk_space`, not
  `task_port`/`port_funcs`. See the "Groundwork" note below.
- **`notifClientObjects` never existed.** `_notifClients` runs 0x4094-0x4193,
  exactly 32 eight-byte entries; the "parallel array at 0x4098" was entry 0's
  own `+4` field. `IOReleaseNotifyForFunc` now reads `client_entry[1]`, which is
  the field `IORequestNotifyForClientTask` writes at address 8708.
- **`_notifyThread` is a thread handle, not a boundary marker.** The array
  bounds in `IOReferenceClientTask`/`IODereferenceClientTask` use *scattered*
  relocations against `__DATA,__data+136` — the assembler's encoding for
  `&_clientReferences[32]` — while the two genuine `_notifyThread` reads/writes
  (8712/8716 and 8212/8216) are plain relocations. The addresses coincide; the
  expressions do not.

One `intentional-mismatch` was recorded: address 8412, the `_notifClientCnt`
leak, detailed at the `_IORequestNotifyForClientTask` section below.

## Summary

Tally across all 68 ledger entries, transcribed from `reconstruction/SCSIServer/ledger.json`
after Task 4. (Earlier revisions of this table read
`assembly-matched 14 / intentional-mismatch 3 / unexamined 51`, which was
already 18 entries adrift of the ledger before Task 3 touched it; Task 3 left it
at `15 / 24 / 1 / 28`.)

| Status | Count |
| --- | --- |
| `assembly-matched` | 15 |
| `intentional-mismatch` | 25 |
| `signature-confirmed` | 6 |
| `unexamined` | 22 |
| **Total** | **68** |

Task 4 advanced its six addresses from `unexamined` to `signature-confirmed`
(2672, 6588, 7320, 7576, 7624, 8412) and then 8412 on to
`intentional-mismatch`. It deliberately did not claim `control-flow-confirmed`
or `assembly-matched` for any of them: nothing here compiles.

The 25 `intentional-mismatch` entries are: the 18 MiG-generated dispatch stubs
(`__XIOSCSISession_*`, addresses 9212-13376, dispositioned by Task 9); the
hand-written MiG demux (`_IOSCSISessionMig_server`, address 13520, disposed in
Task 6); the two build-generated classes (`+[SCSIServerKernelServerInstance
kernelServerInstance]`, address 13708, and `+[SCSIServerVersion
driverKitVersionForSCSIServer]`, address 13728 — see "Disposition of the 27 unmapped
entries" below); and the four places where Tasks 3 and 4 declined to reproduce
a demonstrable defect in the reference, per
`docs/superpowers/plans/2026-07-25-kernel-pci-pcmcia-reconstruction.md:968`
("reproduce Apple's *form*, not Apple's *defects*"):

| Address | Function | Defect kept out of our tree |
| --- | --- | --- |
| 772 | `-[SCSIServer getCharValues:forParameter:count:]` | unconditional `stb r0, -1(r9)` at 976-984, reached with `r31 == 0` via the `bge cr1, loc_3D0` break at 936 — a one-byte write before the caller's buffer |
| 4828 | `_IOSCSISession_executeRequestScatter` | `release` at 5084 then `cmpwi cr1, r31, 0` / `beq cr1, loc_1428` at 5088-5092 with `r31` unchanged, so the wire-failure path falls into 5096-5156 and uses the freed descriptor twice more |
| 5760 | `_IOSCSISession_executeSCSI3RequestScatter` | the same shape at 6016 and 6020-6024 in the SCSI-3 variant |
| 8412 | `_IORequestNotifyForClientTask` | the `_notifClientCnt` leak: the failure returns at 8592-8604 and 8656-8680 clear the reserved slot but never undo the increment at 8548-8552, though the third failure path at 8820-8836 does (Task 4) |

The six `signature-confirmed` entries are address 1160,
`-[IOSCSISession initServerWithTask:sendPort:]`, and the five functions Task 4
wrote that are not `intentional-mismatch`: 2672 `_serverThreadFunc`, 6588
`_IOTaskPortAllocate`, 7320 `_IOConvertTaskPortToVMTask`, 7576
`_IODestroyMappedVMTask` and 7624 `__io_task_notification`.

Of the 68 functions, **47 were read at instruction level**: the 41 functions Tasks 3-6
compared against our source (15 confirmed `assembly-matched`, 4 `intentional-mismatch`,
22 left `unexamined` with a recorded finding of a real, non-cosmetic divergence), plus the 6 functions this
task reads directly from the reference disassembly because our tree has no
counterpart to compare them against at all (see "Finding: six functions our tree lacks
entirely" below).

**6 functions are absent from our tree entirely** — no definition, stub, or even a
declaration with a matching name exists anywhere in `src/drvSCSIServer`, except
`_IORequestNotifyForClientTask`, which is declared `extern` and called but never
defined. A further **18 entries** (now `intentional-mismatch`, dispositioned by Task 9)
are the reference's own MiG-generated dispatch-stub bodies (`__XIOSCSISession_*`,
addresses 9212-13376) — compiler output from the project's lost `.defs` file, not
hand-written source, regenerated in `IOSCSISessionMig.defs` rather than transcribed by
hand. The remaining **1 entry** (address 1160,
`-[IOSCSISession initServerWithTask:sendPort:]`, now `signature-confirmed`) *is* implemented in our
tree, at `IOSCSISession.m:234`, but under a misspelled selector name (see "Finding:
`-[IOSCSISession(Private) _initServerWithTask:sendPort:]` carries a spurious
underscore" below); it stays `signature-confirmed` because only its name, not its full
instruction sequence, has been checked so far, and its disposition is Task 8's.
6 + 18 + 1 = 25, plus the 2 build-generated classes now `intentional-mismatch` = 27,
matching the unmapped count in "Starting state" above.

## Out of scope

**138 jump islands.** IDA finds 206 functions; 138 are unnamed 16-byte
`lis`/`mr`/`mtctr`/`bctr` sequences — build-generated branch glue for calls that
exceed the PowerPC branch displacement. They are not source and are excluded
from the map by `filter_named_functions.py`. Note that a 16-byte size alone does
not identify one: `+[IOSCSISession controllerNameList]`, `-[IOSCSISession name]`
and `+[SCSIServerVersion driverKitVersionForSCSIServer]` are also 16 bytes.

**Two build-generated classes.**
`+[SCSIServerKernelServerInstance kernelServerInstance]` (address 13708, 20
bytes) and `+[SCSIServerVersion driverKitVersionForSCSIServer]` (13728, 16
bytes) are emitted by the Kernel Server build from the project's own settings,
not written by hand. They remain in the `unmapped` bucket permanently.

## The analyzer gap at address 0

`+[SCSIServer deviceStyle]` occupies address 0 in the symbol table, but IDA
emits no function entry there, so it cannot appear in `source-map.json` — the map
covers 68 functions, not the symbol table's 69. Our `SCSIServer.m:37` implements
it. This is the same mismatch `ppc_invariant_check.py --analysis` reported during
the binrecon PowerPC acceptance run, and it is an analyzer artifact, not a
missing function.

## SCSIServer.m block

Task 3 read all six `SCSIServer` class methods (addresses 16-1096, `analysis-reference-ida.named.json`)
instruction by instruction against `SCSIServer.m`.

| Address | Function | Status | Reason |
| --- | --- | --- | --- |
| 16 | `+[SCSIServer requiredProtocols]` | `assembly-matched` (data divergence found; see Finding below — ledger CLI refuses the backward transition to `unexamined`) | trivial 5-instruction leaf, no divergence in the *code*; the *data* it returns diverges |
| 36 | `+[SCSIServer probe:]` | `unexamined` | Finding: extra IOLog calls |
| 228 | `-[SCSIServer initFromDeviceDescription:]` | `unexamined` | Finding: wrong registerSCSIController: argument; Finding: extra IOLog call; Finding: extra objc_getClass call |
| 480 | `-[SCSIServer registerSCSIController:]` | `unexamined` | Finding: extra IOLog call |
| 632 | `-[SCSIServer serverConnect:taskPort:]` | `unexamined` | Finding: wrong selector name; Finding: extra objc_getClass call |
| 772 | `-[SCSIServer getCharValues:forParameter:count:]` | `intentional-mismatch` | Finding: bounds guard absent from reference — kept deliberately, see the Summary table above; Finding: extra objc_getClass call (fixed by Task 3) |

`requiredProtocols` (address 16) accounts for every reference *instruction* with no unexplained
difference, but the *data* the five instructions return does diverge (see the Finding immediately
below) — a review caught this after the original disposition, and the ledger CLI refuses to move
the entry back to `unexamined` (backward transitions are forbidden by design), so the status field
still reads `assembly-matched` even though the divergence is real and unresolved. The other five
functions each have at least one real, non-cosmetic divergence from the reference disassembly, so
per the ledger convention they stay `unexamined` rather than being marked `control-flow-confirmed`;
the findings below are for Task 12 to repair.

## Finding: `+[SCSIServer requiredProtocols]` returns an array with the wrong pointer indirection, backed by a static of the wrong storage class

**Source:** `SCSIServer.m:21-25` (declaration of `_scsiServerProtocols` and its initializer),
returned by `SCSIServer.m:118-121`.

**Reference behaviour:** the function (address 16, 20 bytes, `assembly-matched`) computes the
address of `_protocols.26` and returns it — that part was already confirmed instruction-for-instruction.
What was not checked in the original pass is the *data* at that address:

- `_protocols.26` sits at address 16384 in `__DATA,__data` (symbol table: `{'name':
  '_protocols.26', 'address': 16384, 'binding': 'local', 'section': '__DATA,__data'}`).
- A relocation at address 16384 rewrites the first element to point into `__OBJC,__protocol`:
  `{'address': 16384, 'kind': 'ppc-vanilla-32-absolute', 'target': '__OBJC,__protocol', 'addend': 0}`.
  The `__OBJC,__protocol` section itself starts at address 21424 (`{'name': '__OBJC,__protocol',
  'address': 21424, 'offset': 23916, 'size': 40, ...}`), so after relocation `protocols[0] ==
  21424` — a pointer directly *to* the `Protocol` struct, i.e. `protocols` has type `Protocol *[]`.
- **Correction (Task 3).** That record's `protocol_name` field (address 21428) reads
  `"IOSCSIControllerExported"`, not `IOSCSIController`. Both of the section's two 20-byte records
  carry the *same* name pointer (`__OBJC,__class_names+36`), and no `"IOSCSIController"` string
  exists anywhere in `__OBJC,__class_names`; the two records are the two translation units'
  independent copies of the same protocol. Every statement below and elsewhere in this document
  that calls the first record "the `IOSCSIController` protocol" is wrong. Evidence, including the
  fifteen decoded method descriptions, is in `reconstruction/SCSIServer/findings.md`.
- `_protocols.26` is gcc's standard mangling for a **function-local static** (the `.26` suffix
  disambiguates a local named `protocols` from other locals across the translation unit) — meaning
  Apple declared `static Protocol *protocols[] = {...}` *inside* `+requiredProtocols` itself, not at
  file scope.

**Our source:** `SCSIServer.m:21-25` declares `extern Protocol
*objc_protocol_IOSCSIController;` and initializes the array as
`static Protocol *_scsiServerProtocols[] = { &objc_protocol_IOSCSIController, NULL };` — i.e.
`&objc_protocol_IOSCSIController` is the address of the *pointer variable*
`objc_protocol_IOSCSIController`, not the address of the `Protocol` struct it points to. That makes
our element type `Protocol **`, one indirection level off from the reference's `Protocol *`.
Separately, `_scsiServerProtocols` is declared at file scope (`SCSIServer.m:22`), not as a
function-local static the way the mangled reference symbol name implies.

**Consequence:** on the eventual PPC rebuild, `protocols[0]` would hold the address of the
`objc_protocol_IOSCSIController` pointer cell rather than the address of the protocol struct itself
— any runtime code that dereferences `requiredProtocols()[0]` expecting a `Protocol *` (e.g. `class_conforms_to:` /
`respondsTo:` machinery, or IOKit's own protocol-conformance checks) would read the wrong bytes. This
is a real divergence, not a cosmetic one, so per the project's own convention ("a divergence that is
not intentional is not a status") it should not be left recorded as `assembly-matched`.

**Ledger status:** the entry could not be moved back to `unexamined` to reflect this. Attempted:

```
$ BINRECON_REFERENCE="$REF" PYTHONPATH=tools/binrecon $PY -m binrecon ledger \
  --profile tools/binrecon/profiles/scsiserver-ppc.json --ledger "$RECON/ledger.json" \
  --address 16 --status unexamined --reviewer claude --reason "..."
binrecon: backward ledger transition is forbidden
```

`binrecon.ledger.transition()` enforces a strictly non-decreasing state order
(`unexamined -> signature-confirmed -> control-flow-confirmed -> assembly-matched`) and raises
`LedgerError("backward ledger transition is forbidden")` for any attempt to move an entry earlier in
that order — there is no CLI-supported way to un-confirm an entry once `assembly-matched` is
reached. Per this task's constraint against hand-editing `ledger.json`, the entry's `status` field
was left as `assembly-matched` and is **not** an accurate signal that this function is fully
resolved; this Finding is the authoritative record that address 16 has an unresolved divergence
Task 12 must fix (correct the indirection to `Protocol *_scsiServerProtocols[]` initialized with
`objc_protocol_IOSCSIController` directly, not `&objc_protocol_IOSCSIController` — and decide whether
to also relocate the array to function-local scope to match the reference's storage class).

## Finding: `+[SCSIServer probe:]` logs where the reference has no log calls

**Source:** `SCSIServer.m:60` (`probe:`).

**Reference behaviour:** the reference function (address 36, 176 bytes) is fully accounted for by
44 instructions: prologue, `_server == NULL` test, the `alloc`/`initFromDeviceDescription:` sequence
that assigns `_server`, the boolean-normalize idiom (`addic`/`subfe`) that turns `_server != 0` into
0/1, and — on the else side — the `registerSCSIController:` call. There is no `bl` to anything else
in either branch; the function falls straight from the assignment/normalize sequence to the shared
epilogue. None of the three message strings our source logs
(`"SCSIServer: probe successful..."`, `"SCSIServer: probe failed..."`,
`"SCSIServer: probe - registering additional controller\n"`) appear anywhere in the reference's
string table (`analysis-reference-ida.named.json` `strings`), which rules out the calls being
present but unresolved by the exporter.

**Our source:** calls `IOLog(...)` three times — once for each of the success/failure branches
inside the `_server == NULL` arm, and once, unconditionally, in the `else` arm — none of which the
comment block above the function claims comes from the decompiled evidence.

**Consequence:** harmless in isolation (adds diagnostic output only), but it is behaviour the
reference does not have, so it cannot be marked matched. Left `unexamined`; Task 12 should either
remove the three `IOLog` calls or, if kept deliberately, get an `intentional-mismatch` disposition
with reviewer sign-off.

## Finding: `-[SCSIServer initFromDeviceDescription:]` passes the wrong argument to `registerSCSIController:`, and logs where the reference does not

**Source:** `SCSIServer.m:138` (`initFromDeviceDescription:`), specifically line 154.

**Reference behaviour:** at entry, ObjC convention has r3=self, r4=`_cmd`, r5=the incoming
`deviceDescription` argument. The function copies r3 into r30 (`mr r30, r3`, address 252) and r5
into r29 (`mr r29, r5`, address 256) purely for later reuse, but does not touch r3 or r5 themselves.
The very next call (address 260-268: load `@selector(registerSCSIController:)` into r4, `bl
sub_1D0`) fires with r3 and r5 still holding their entry values — i.e. it is
`objc_msgSend(self, @selector(registerSCSIController:), deviceDescription)`, not
`registerSCSIController:self`.

**Our source:** `registerResult = (int)[self registerSCSIController:self];` (line 154) — passes
`self`, not `deviceDescription`, as the controller argument. The comment directly above (lines
144-153) already flags this as a guess: *"This appears to be `[self registerSCSIController:self]`
but that doesn't make sense... For now, let's interpret this as a registration capability check."*
The disassembly resolves that uncertainty: the argument is the incoming `deviceDescription`, matching
`probe:`'s own use of `registerSCSIController:` on subsequent probes (`SCSIServer.m:101`, which
correctly passes `deviceDescription`).

Separately: after `[self registerDevice]` and setting `_server = self` (addresses 368-392), the
reference moves straight to `mr r3, r31` (restoring the super-init result) and the epilogue — there
is no `bl` to anything else, and `"SCSIServer: Initialized successfully..."` does not appear in the
reference's string table. Our source's final `IOLog(...)` call (line 197) has no counterpart, the
same pattern as the `probe:` finding above.

**Consequence:** the wrong-argument bug is a real behavioural divergence — our `registerSCSIController:`
receives the wrong object, so on the eventual PPC rebuild the controller-name array would be checked
against the wrong device's `directDevice`/`name`. Left `unexamined`; Task 12 should change line 154
to `[self registerSCSIController:deviceDescription]` and address the extra `IOLog` call the same way
as the `probe:` finding.

This function also has a third divergence, of the same species as the wrong-selector-name finding
below: it calls `objc_getClass("IODevice")` where the reference loads a static reference instead —
see "Finding: our source calls `objc_getClass()` where the reference loads static references" below.

## Finding: `-[SCSIServer registerSCSIController:]` logs where the reference has no log call

**Source:** `SCSIServer.m:218` (`registerSCSIController:`).

**Reference behaviour:** the function (address 480, 136 bytes, 34 instructions, all accounted for)
runs `directDevice`/`name`, the three-part failure test (`NULL`, empty string, `_controllerCount >
7`), the `nil` early-return, and on success stores the name at `_controllerNames[currentCount]`,
increments `_controllerCount`, sets r3 to `self`, and falls straight into the epilogue. There is no
call after the store at address 588; `"SCSIServer: Registered SCSI controller..."` is not present in
the reference's string table.

**Our source:** calls `IOLog("SCSIServer: Registered SCSI controller '%s' (count: %d)\n", ...)`
(line 258-259) right before `return self;`, with no reference counterpart.

**Consequence:** same class of issue as the two findings above — added diagnostics not present in
the reference. Left `unexamined` for Task 12.

## Finding: `-[SCSIServer serverConnect:taskPort:]` sends the wrong selector name to `IOSCSISession`

**Source:** `SCSIServer.m:284` (`serverConnect:taskPort:`), specifically line 309;
`IOSCSISession.h:79` and `IOSCSISession.m:234` declare/implement the same selector.

**Reference behaviour:** the `__message_refs` entry the function loads before its second `bl` to
`sub_2F4` is `paInitserverwith` (address 20788). That message ref resolves to the selector string at
address 23096, which reads exactly `"initServerWithTask:sendPort:"` — no leading underscore. It is
the only string in the whole reference binary containing `"initServerWith"`; there is no
underscore-prefixed variant anywhere in the string table.

**Our source:** declares and calls `_initServerWithTask:sendPort:` (leading underscore) in three
places: `IOSCSISession.h:79`, `IOSCSISession.m:234` (the implementation), and `SCSIServer.m:309`
(this call site). The ledger's own name for the address-1160 function (out of this block's scope,
Task 4's territory) is likewise `-[IOSCSISession initServerWithTask:sendPort:]`, without the
underscore, agreeing with the string table.

**Consequence:** a selector name is part of the Objective-C runtime contract — `_cmd` dispatch
matches the string exactly, so a leading-underscore selector is a different selector, not a
formatting variant. This is exactly the class of defect `SCSIServer Task 8: correct selector names`
is scoped to fix project-wide; this instance is called out here because it sits inside a Task 3
function and blocks a `assembly-matched`/`control-flow-confirmed` disposition for address 632. Left
`unexamined`.

This function also calls `objc_getClass("IOSCSISession")` where the reference loads a static
`__cls_refs` entry instead — see "Finding: our source calls `objc_getClass()` where the reference
loads static references" below.

## Finding: `-[SCSIServer getCharValues:forParameter:count:]` adds a bounds guard the reference does not have

**Source:** `SCSIServer.m:342` (`getCharValues:forParameter:count:`), specifically lines 421-423.

**Reference behaviour:** after the comma-list loop exits (either by the bottom-of-loop test at
addresses 964-972, or by the `bge cr1, loc_3D0` break at address 936 when the next entry would not
fit), execution falls unconditionally into addresses 976-984: `add r9, r31, r25` /
`stb r0, -1(r9)`, i.e. `values[bytesWritten - 1] = '\0'` with no guard on `bytesWritten`. If the
break at address 936 fires on the very first loop iteration — i.e. `*count` is too small to hold
even one controller name plus its separator — `bytesWritten` is still 0 at that point, and the
reference writes to `values[-1]`, one byte before the caller's buffer.

**Our source:** wraps the equivalent store in `if (bytesWritten > 0) { values[bytesWritten - 1] =
'\0'; }` (lines 421-423), which the comment above presents as a direct transcription of the
decompiled store, not as a deliberate correction.

**Consequence:** a real control-flow divergence, not a register-allocation artifact: our source
skips the terminator write in the edge case where the reference would perform (a buggy) one-byte
underflow write. **Resolved:** the "reproduce by default" reading this paragraph used to advise is
superseded. The governing convention is
`docs/superpowers/plans/2026-07-25-kernel-pci-pcmcia-reconstruction.md:968` — "reproduce Apple's
*form*, not Apple's *defects*" — so the guard stays and address 772 is `intentional-mismatch`.

This function also calls `objc_getClass("IODevice")` where the reference loads a static reference
instead — see "Finding: our source calls `objc_getClass()` where the reference loads static
references" below.

## Finding: our source calls `objc_getClass()` where the reference loads static references

**Corrected and resolved by Task 3.** Three corrections to what follows. (a) There are **five**
sites, not three plus a Task 4 addendum: `IOSCSISession.m`'s two super sends, `SCSIServer.m`'s two
super sends and `SCSIServer.m`'s `+alloc` receiver. (b) The fourth site — `[super init]` inside
`@implementation IOSCSISession (Private)` — is **not** a static reference in the reference either:
addresses 1212-1224 materialise the string `"Object"` and `bl` a jump island whose relocation names
the imported `_objc_getOrigClass`, storing its result into the `objc_super`. That is what this
tree's own compiler emits for `[super ...]` in a *category* (`src/cc-1/cc/objc-act.c:8421`,
`get_orig_class_reference`) as opposed to in a class `@implementation` (`:8388`, `ucls_super_ref`).
(c) The suggested fix — "replace all three call sites with build-time class references … consistent
with how `SCSIServer.m` already declares `extern Protocol *objc_protocol_IOSCSIController`" — was
not taken, because that extern was itself the fabricated construct fixed by the `requiredProtocols`
repair. All five sites are now plain Objective-C syntax (`[super ...]`, `[IOSCSISession alloc]`),
which is what produces each of the reference's three shapes without inventing anything.

**Source:** `SCSIServer.m:177` and `SCSIServer.m:362` (both `objc_getClass("IODevice")`, building an
`objc_super` struct for a super-call), and `SCSIServer.m:298` (`objc_getClass("IOSCSISession")`,
building the receiver for `+alloc`).

**Reference behaviour:** none of the three call sites resolve to a `bl` in the reference. `_objc_getClass`
does not appear anywhere among the reference binary's 34 imports (checked the full import list, not
just the string table, so this rules out an unresolved-by-the-exporter false negative). Instead:

- Inside `-[SCSIServer initFromDeviceDescription:]` (address 228), at addresses 328-336, the
  `superStruct.class` field is filled by loading `stru_5198.super_class` directly (`lis r9,
  stru_5198.super_class@ha` / `lwz r9, stru_5198.super_class@l(r9)` / `stw r9, ...`) — a static,
  already-resolved `objc_super`-style class reference, not a runtime `objc_getClass()` call.
- Inside `-[SCSIServer getCharValues:forParameter:count:]` (address 772), the identical
  three-instruction sequence recurs at addresses 1004-1012, loading the same
  `stru_5198.super_class` field for its own super-call.
- Inside `-[SCSIServer serverConnect:taskPort:]` (address 632), at addresses 672-680, r3 (the first
  `objc_msgSend` argument, the receiver for `+alloc`) is loaded from the `__cls_refs` entry
  `paIoscsisession` (symbol table address 20880) — `lis r3, paIoscsisession@ha` / `lwz r3,
  paIoscsisession@l(r3)` — immediately followed (addresses 676-684) by loading `paAlloc` into r4 and
  the `bl sub_2F4` (`objc_msgSend`). `paIoscsisession`'s class-name string (verified in the named
  export's `strings` table) reads `"IOSCSISession"` at address 21544, confirming it is the class
  reference for `IOSCSISession`, resolved at link time, not looked up at runtime.

**Our source:** all three sites call `objc_getClass("IODevice")` / `objc_getClass("IOSCSISession")`
to obtain the same class pointers at runtime instead of reading them from build-time-resolved
references (`SCSIServer.m:177`, `SCSIServer.m:298`, `SCSIServer.m:362`).

**Consequence:** this is the same species of defect already recorded three times above for the added
`IOLog` calls — a call our source makes at a site the reference does not call anything — except here
the pattern is `objc_getClass()` instead of `IOLog()`, and it recurs at three of the six sites in
this block (`initFromDeviceDescription:`, `serverConnect:taskPort:`, `getCharValues:forParameter:count:`).
Functionally `objc_getClass("X")` and a resolved class/`super_class` reference to the same class
should produce the same pointer at runtime, so this is lower-severity than the wrong-argument or
wrong-selector-name findings above, but it is still behaviour the reference does not have (an extra
runtime call, and a reliance on `_objc_getClass` being importable at all — which the reference does
not need, since it is not among its imports). All three functions are already left `unexamined` for
other reasons (see the findings above, each cross-referencing this one), so no ledger status changes
because of this finding by itself; Task 12 should replace all three call sites with build-time class
references the same way the reference does, consistent with how `SCSIServer.m` already declares
`extern Protocol *objc_protocol_IOSCSIController` for the protocol-array case above rather than
looking that up at runtime either.

**Task 4 addendum:** the same pattern recurs a fourth time at `IOSCSISession.m:168`
(`super_struct.class = objc_getClass("Object");`, inside `-[IOSCSISession free]`, address 1732).
Reference addresses 1912-1920 fill the `objc_super.class` field by loading `stru_5198.ext@ha`/
`stru_5198.ext@l` directly (`lis r9, stru_5198.ext@ha` / `lwz r9, stru_5198.ext@l(r9)` / `stw r9,
0x50+var_14(r1)`) — the same static-reference shape as the three `SCSIServer.m` sites above, just a
different field of the same `stru_5198` structure, and consistent with `IOSCSISession`'s declared
superclass (`IOSCSISession.h:31`, `@interface IOSCSISession : Object`). No new ledger entry changes
because of this by itself — address 1732 is already `unexamined` for the two reasons in "Finding:
`-[IOSCSISession free]` calls the wrong argument count and diverges on its cleanup-callback
mechanism" below.

## IOSCSISession class and reservations

Task 4 read the five `IOSCSISession` class methods (addresses 1604-2088) and the four reservation
functions (addresses 2092-2655, `_findReservation`/`_addReservation`/`_removeReservation`/
`_blastAllReservations`) instruction by instruction against `IOSCSISession.m`, using the same named
export as Task 3 (`analysis-reference-ida.named.json`) plus the unfiltered
`published/analysis-reference-ida.json` to resolve what the nine functions' `bl`-to-jump-island call
sites actually target (raw instruction bytes, since the named export strips the 138 jump islands
themselves and reports `calls: []` for every function in this block).

| Address | Function | Status | What was compared |
| --- | --- | --- | --- |
| 1604 | `+[IOSCSISession controllerNameList]` | `assembly-matched` | 4-instruction leaf; returns literal 0 |
| 1620 | `-[IOSCSISession init]` | `assembly-matched` | loads the `free` selector ref, calls `[self free]` |
| 1676 | `-[IOSCSISession initForDevice:result:]` | `assembly-matched` | identical shape to `init`, args unused |
| 1732 | `-[IOSCSISession free]` | `unexamined` | Finding: missing `notify_port` argument to `IOTaskPortDeallocate()` (a compile error given the header declaration); Finding: cleanup call resolves to `IOExitThread()`, not a callback; Finding: returns `self` where the reference returns `nil`; addendum above: extra `objc_getClass("Object")` call |
| 2076 | `-[IOSCSISession name]` | `assembly-matched` | 4-instruction leaf; returns literal 0 |
| 2092 | `_findReservation` | `assembly-matched` | walks the circular list, matches the 0x18-byte element layout field-for-field |
| 2196 | `_addReservation` | `assembly-matched` | calls `findReservation` (confirmed by local symbol name) then `IOMalloc`, links the new entry with the same four steps and offsets as the source |
| 2388 | `_removeReservation` | `assembly-matched` | Finding: pointer-arithmetic bug corrupts the wrong field when unlinking (fixed by commit `5c17f9cb`; see the finding below) |
| 2544 | `_blastAllReservations` | `assembly-matched` | `while` loop freeing 0x18-byte entries, correctly fixes up `next->prev` |

**The reservation structure.** All four reservation functions — in both the reference disassembly and
our source's own documented layout (`IOSCSISession.m:1160-1168`) — agree on a 24-byte (`0x18`)
element with offset `+0` = next, `+4` = prev (a circular doubly-linked list; the list is empty
exactly when `head->next == head`, with no `NULL` terminator anywhere), `+8`/`+0xC` = target
high/low, `+0x10`/`+0x14` = lun high/low. `_findReservation` (2092), `_addReservation` (2196) and
`_blastAllReservations` (2544) all read and write those exact offsets correctly and match the
reference instruction for instruction. There is **no** layout disagreement between our four functions
or against the reference — the one divergence in this group (`_removeReservation`) is a C-level
implementation bug within a single function, not a structural disagreement, so it is reported as one
finding below rather than a structure-wide one.

The four functions establish only that `*(session+4)` holds a pointer to the list's head node —
used identically as the `next`/`prev` anchor in `_findReservation`'s and `_removeReservation`'s
empty-list test (`head == head->next`), `_addReservation`'s insertion, and `_blastAllReservations`'
teardown loop. None of them determines where that head node itself is allocated or how large it is;
the earlier claim that it is "embedded in the session structure, not separately allocated" overstates
what this evidence shows, so it is corrected here rather than repeated as established fact.

Our own source's comments disagree with each other on which field is which. `IOSCSISession.m:114-115`
(the doc comment above `-[IOSCSISession free]`, describing the fields of the structure at
`*(self+4)`) reads "offset +0: prev pointer (circular list)" / "offset +4: next pointer (circular
list)" — the opposite order from `IOSCSISession.m:1161-1162` (the reservation-structure doc comment
above the four functions below), which reads "offset +0: next pointer (circular list)" / "offset +4:
prev pointer (circular list)". The code itself follows the latter, `+0` = next / `+4` = prev — e.g.
`addReservation`'s `new_entry[0] = (int)session_struct;` (`IOSCSISession.m:1242`, commented
`new_entry->next = ...`) and `new_entry[1] = (int)last_entry;` (`IOSCSISession.m:1239`, commented
`new_entry->prev = ...`). The `-free` comment's offset labels are simply wrong for this layout; Task
12 should fix that comment rather than leave a fix-pass reader who trusts it with the fields
backwards.

## Finding: `_removeReservation` corrupts the wrong field when unlinking an entry (resolved)

**Source:** `IOSCSISession.m:667` (`removeReservation`), specifically lines 706-707. (Citation
updated in the final whole-branch review fix pass; was `:1308`/lines 1350-1352 before Task 10's
IOTask.m/.h split shifted this content.)

**Reference behaviour:** at addresses 2468-2480, after locating the matching entry (`r3` = `current`),
the reference does:
```
2468  lwz r11, 0(r3)     ; next = current->next        (offset +0)
2472  lwz r9, 4(r3)      ; prev = current->prev         (offset +4)
2476  stw r9, 4(r11)     ; next->prev = prev             (offset +4 of next)
2480  stw r11, 0(r9)     ; prev->next = next             (offset +0 of prev)
```
Both stores land on the field at byte offset `+4` (`prev`) and `+0` (`next`) of the neighbouring
entries — a correct doubly-linked-list unlink, matching `_addReservation`'s and
`_blastAllReservations`' own use of the same offsets.

**Our source (as originally recorded, before the fix below):**
```c
next = (int *)current[0];  /* current->next */
prev = (int *)current[1];  /* current->prev */

/* Unlink from list: prev->next = next, next->prev = prev */
*(int **)(next + 4) = prev;   /* next->prev = prev */
*prev = (int)next;             /* prev->next = next */
```
`next` is declared `int *`. In C, `next + 4` on an `int *` advances by `4 * sizeof(int)` = 16 bytes,
not 4 bytes — so `*(int **)(next + 4) = prev;` writes `prev` into the byte at offset `+0x10` of
`next`'s entry, which per the structure layout above is `next`'s **`lun_high`** field, not its `prev`
field. The second line, `*prev = (int)next;`, is correct (offset `+0` of `prev`, matching the
reference's `stw r11, 0(r9)`).

**Resolved:** commit `5c17f9cb` changed the first line to `next[1] = (int)prev;` (`IOSCSISession.m:706`
as of this fix pass), matching `_addReservation`'s and `_blastAllReservations`' own array-index
notation for the same field and eliminating the raw-pointer-arithmetic scaling bug. The ledger already
recorded this address (2388) as `assembly-matched`; this divergences.md entry was simply never updated
to match until now.

**Consequence:** this is a real, non-cosmetic bug, not a register-allocation artifact: removing a
reservation (1) never updates the successor entry's actual `prev` pointer — it is left dangling,
pointing at the just-freed `current` node — and (2) clobbers the successor entry's `lun_high` field
with the (unrelated) `prev` pointer value, corrupting live reservation data for every entry still in
the list after the removed one. `_addReservation`'s own equivalent step
(`new_entry[1] = (int)last_entry;`, `IOSCSISession.m:598`) and `blastAllReservations`' equivalent
step (`next[1] = list_head;`, `IOSCSISession.m:646`) both use array-index notation and get the
scaling right; only `removeReservation` mixed in raw pointer arithmetic on a byte offset comment
without going through `(char *)` or index notation — see "Resolved" above for the fix.

## Finding: `-[IOSCSISession free]` omits an argument, misidentifies its cleanup call as a callback, and returns `self` where the reference returns `nil`

**Source:** `IOSCSISession.m:122` (`free`), specifically lines 157 and 181-188.

**Reference behaviour, `IOTaskPortDeallocate` call:** at addresses 1856-1872, the reference reloads
`notify_port` from `*(session_struct+0xC)` into `r3` (address 1860) and then, with `r3` still holding
that value, calls the jump island at address 2028 — which resolves, by name, to the reference's own
local `_IOTaskPortDeallocate` function (address 6652; confirmed via the symbol table, `{'address':
6652, 'binding': 'local', 'name': '_IOTaskPortDeallocate', 'section': '__text'}`) — i.e.
`IOTaskPortDeallocate(notify_port)`, one argument, matching its own declared signature
(`IOSCSISession.h:153`, `void IOTaskPortDeallocate(mach_port_t port);`, and its own definition body at
`IOSCSISession.m:1744`, `void IOTaskPortDeallocate(mach_port_t port)`).

**Our source:** calls `IOTaskPortDeallocate();` (line 157) with **no** arguments, despite the function
being declared and defined with a `mach_port_t port` parameter earlier in the very same file:
`IOSCSISession.h:153` declares `void IOTaskPortDeallocate(mach_port_t port);`, and this header is
included by `IOSCSISession.m` (the definition at `IOSCSISession.m:1744` matches). With that prototype
in scope at the call site, `IOTaskPortDeallocate();` is not merely a behavioural divergence caught
only at runtime — it is a **"too few arguments to function" compile-time error** in standard C.

**Consequence:** a real divergence — the reference passes `notify_port` to the deallocation call;
our source's call site drops the argument entirely, so `IOTaskPortDeallocate`'s body (which reads its
`port` parameter) would receive whatever happened to be left in the argument register rather than the
intended port. Because a prototype for `IOTaskPortDeallocate` is already visible at this call site,
this additionally fails to compile as written, which raises its priority for Task 12 relative to
divergences that only manifest at runtime. Left `unexamined`; Task 12 should change the call to
`IOTaskPortDeallocate(notify_port);`.

**Reference behaviour, cleanup callback:** at addresses 1940-1948, the reference has exactly one test
before the cleanup call:
```
1940  cmpwi cr1, r30, 0     ; r30 = session_object_id
1944  beq cr1, loc_7A0      ; skip the call if session_object_id == 0
1948  bl sub_7BC            ; unconditional call, no argument registers set up beforehand
```
`sub_7BC` is the 16-byte jump island at address 1980 (`lis r12,0` / `ori r12,r12,0` / `mtctr r12` /
`bctr`, raw bytes `3D800000 618C0000 7D8903A6 4E800420`). The earlier pass could not identify its
target because the IDA export used elsewhere in this document does not carry the Mach-O external
relocation table. The reference binary itself does, and `binrecon.macho.read_macho` reads it; the
island's own two instructions carry relocations:
```
1980  ppc-hi16-32-absolute  target=_IOExitThread  external=True
1984  ppc-lo16-32-absolute  target=_IOExitThread  external=True
```
`_IOExitThread` is among the reference's 34 named imports (`{'address': 24832, 'name':
'<self>:_IOExitThread'}` in the published IDA export's `imports` list) — the earlier finding's claim
that it was absent from the imports was a lookup miss (the export's import entries are prefixed
`<self>:`), not a genuine absence. `sub_7BC` resolves to `IOExitThread()`, not to any
function-pointer variable: the call is `if (session_object_id != 0) IOExitThread();` — the session's
own server thread exiting when the session that owns it is freed.

**Our source:**
```c
if (session_object_id != 0) {
    if (_scsiSessionCleanupCallback != NULL) {
        _scsiSessionCleanupCallback();
    }
}
```
models the call as a dereference of `extern session_cleanup_callback_t _scsiSessionCleanupCallback`
(declared at `IOSCSISession.m:40`, with no definition anywhere in this file), gated by a second,
additional `NULL` check the reference does not perform.

**Consequence:** the reference's single test gates a direct, fixed `IOExitThread()` call — there is
no callback to identify and no callback variable to define; the "callback" framing in the original
finding and in the source's own comment block (`IOSCSISession.m:171-183`) is itself the divergence to
fix, not just the extra `NULL` check. Left `unexamined`; Task 12 should replace the
`_scsiSessionCleanupCallback` declaration, its `NULL` check, and the indirect call with a direct call
to `IOExitThread()`.

**Reference behaviour, return value:** both paths through the function converge on the same
instruction. The `beq cr1, loc_7A0` at address 1944 (taken when `session_object_id == 0`) branches to
address 1952; falling through the `bl sub_7BC` at address 1948 also reaches address 1952 next, with
no intervening register writes on either path. Address 1952 is `li r3, 0`, followed immediately by
the epilogue (`addi r1, r1, 0x50` / restore `lr`, `r30`, `r31` / `blr`) — `-[IOSCSISession free]`
always returns `nil`, on both branches.

**Our source:** `IOSCSISession.m:191` ends `return self;`.

**Consequence:** this is not cosmetic. `-[IOSCSISession init]` (`IOSCSISession.m:74-82`,
`result = [self free]; return result;`) and `-[IOSCSISession initForDevice:result:]`
(`IOSCSISession.m:96-104`, `free_result = [self free]; return free_result;`) both return whatever
`[self free]` returns. With the reference's `return nil`, an `alloc`/`init` (or
`alloc`/`initForDevice:result:`) call correctly hands the caller back `nil`, signalling that the
object tore itself down instead of initializing. With our source's `return self`, the same call
sequence hands the caller back a pointer to the object that `free` just finished tearing down (its
session structure `IOFree`'d, its ports deallocated, `[super free]` already invoked) — the caller has
no way to detect the failure and is left holding a pointer to a freed object. Left `unexamined`;
Task 12 should change `IOSCSISession.m:191` to `return nil;`.

## C-callable Objective-C dispatch wrappers (Task 5)

Task 5 read all 18 hand-written C wrappers (addresses 3028-6444, `analysis-reference-ida.named.json`
plus raw instruction bytes for the `bl`-to-jump-island targets the named export strips) against
`IOSCSISession.m`. Every `lis`/`lwz` pair loading a `pa<Name>` operand was resolved through the
reference's relocation table (`binrecon.macho.read_macho`'s `extensions.macho.relocations`): the
`ha16`/`lo16` pair at the load site names a slot in `__OBJC,__message_refs` (a flat array of 4-byte
selector-pointer slots, stride 4, base offset in the section corresponding to address 20748, not a
full `{imp, sel}` message-ref struct), whose own relocation names an offset into
`__OBJC,__meth_var_names` (base address 22808) or, for the one class reference in this block
(`paIomemorydescri`), `__OBJC,__cls_refs` (base address 20880) resolving through `__OBJC,__class_names`
(base address 21464) — in both cases the final offset was looked up against the named export's
`strings` table to read the literal selector or class name.

| Address | Function | Status | What was compared |
| --- | --- | --- | --- |
| 3028 | `_IOSCSISession_initForDevice` | `assembly-matched` | calls `IOGetObjectForDeviceName`, then `objc_msgSend(conformsTo:, @protocol(IOSCSIControllerExported))`; stores result at `session_struct+8` |
| 3204 | `_IOSCSISession_free` | `assembly-matched` | 11-instruction leaf, `objc_msgSend(session, free)`, no controller indirection |
| 3264 | `_IOSCSISession_releaseAllUnits` | `assembly-matched` | `objc_msgSend(controller, releaseAllUnitsForOwner:, session)` then a direct call to `_blastAllReservations(session)` |
| 3372 | `_IOSCSISession_reserveTarget` | `assembly-matched` | `objc_msgSend(controller, reserveTarget:lun:forOwner:, ...)` then conditional `_addReservation` |
| 3544 | `_IOSCSISession_releaseTarget` | `unexamined` | Finding: dispatch stubbed out (see below) |
| 3796 | `_IOSCSISession_reserveSCSI3Target` | `unexamined` | Finding: dispatch stubbed out |
| 3984 | `_IOSCSISession_releaseSCSI3Target` | `unexamined` | Finding: dispatch stubbed out |
| 4204 | `_IOSCSISession_numberOfTargets` | `unexamined` | Finding: dispatch stubbed out |
| 4288 | `_IOSCSISession_executeRequest` | `unexamined` | Finding: dispatch stubbed out (control flow and delegation to `executeRequestScatter` otherwise match) |
| 4544 | `_IOSCSISession_executeRequestOOLScatter` | `unexamined` | Finding: dispatch stubbed out; Finding: `IOTaskWireMemory` return-type mismatch |
| 4828 | `_IOSCSISession_executeRequestScatter` | `intentional-mismatch` | Finding: dispatch stubbed out (fixed by Task 3); the reference's use-after-free on the wire-failure path is deliberately not reproduced — see the Summary table above |
| 5220 | `_IOSCSISession_executeSCSI3Request` | `unexamined` | Finding: dispatch stubbed out (mirrors 4288 with SCSI-3 offsets) |
| 5476 | `_IOSCSISession_executeSCSI3RequestOOLScatter` | `unexamined` | Finding: dispatch stubbed out; Finding: `IOTaskWireMemory` return-type mismatch |
| 5760 | `_IOSCSISession_executeSCSI3RequestScatter` | `intentional-mismatch` | Finding: dispatch stubbed out (fixed by Task 3); same deliberate use-after-free divergence as 4828 |
| 6152 | `_IOSCSISession_resetSCSIBus` | `unexamined` | Finding: dispatch stubbed out |
| 6236 | `_IOSCSISession_returnFromScStatus` | `unexamined` | Finding: dispatch stubbed out; Finding: wrong return type |
| 6304 | `_IOSCSISession_maxTransfer` | `assembly-matched` | `objc_msgSend(controller, maxTransfer)`, result stored through output pointer |
| 6388 | `_IOSCSISession_getDMAAlignment` | `assembly-matched` | `objc_msgSend(controller, getDMAAlignment:, alignment)`, pointer passed directly as the message argument |

**Selector identity (Step 2 of the brief).** Every one of the 18 wrappers' `pa<Name>` operands was
resolved as above. All 18 name the *correct* selector or class for the method the source's own code
or comments say it is dispatching — `paFree`→`"free"`, `paReleaseallunit`→`"releaseAllUnitsForOwner:"`,
`paConformsto`→`"conformsTo:"`, `paReservetargetL`→`"reserveTarget:lun:forOwner:"`,
`paReleasetargetL`→`"releaseTarget:lun:forOwner:"`, `paReservescsi3ta`→`"reserveSCSI3Target:lun:forOwner:"`,
`paReleasescsi3ta`→`"releaseSCSI3Target:lun:forOwner:"`, `paNumberoftarget`→`"numberOfTargets"`,
`paExecuterequest_0`→`"executeRequest:buffer:client:"`, `paExecuterequest`→`"executeRequest:ioMemoryDescriptor:"`,
`paExecutescsi3re_0`→`"executeSCSI3Request:buffer:client:"`, `paExecutescsi3re`→`"executeSCSI3Request:ioMemoryDescriptor:"`,
`paResetscsibus`→`"resetSCSIBus"`, `paReturnfromscst`→`"returnFromScStatus:"`, `paMaxtransfer`→`"maxTransfer"`,
`paGetdmaalignmen`→`"getDMAAlignment:"`, `paIomemorydescri`→ class `"IOMemoryDescriptor"`,
`paAlloc`/`paInitwithiorang`/`paSetclient`/`paWirememory`/`paRelease`/`paUnwirememory`→`"alloc"` /
`"initWithIORange:count:byReference:"` / `"setClient:"` / `"wireMemory:"` / `"release"` / `"unwireMemory"`.
The `@protocol(IOSCSIControllerExported)` used by `initForDevice` (address 3028) was independently
confirmed by walking `__OBJC,__protocol` (base 21424, two 20-byte `Protocol` records — the first is
the `IOSCSIController` protocol from the Task 3 `requiredProtocols` finding, the second, at offset 20,
is this one) through to its `protocol_name` field, which reads `"IOSCSIControllerExported"` — matching
our source's literal text exactly, even though (see Finding: `-[IOSCSISession initForDevice:result:]` wrapper (address 3028) uses an undeclared protocol name) that protocol is never declared.
**No wrong-selector finding exists in this block** — the spec's warning that "a wrapper dispatching a
different selector than ours is a plausible finding here" did not materialize for any of the 18; the
defect this block actually has (below) is a different species entirely.

## Finding: `-[IOSCSISession initForDevice:result:]` wrapper (address 3028) uses an undeclared protocol name

**Source:** `IOSCSISession.m:441` (`_IOSCSISession_initForDevice`), which calls `objc_msgSend(conformsTo:, @protocol(IOSCSIControllerExported))`.

**Reference behaviour:** the dispatch at address 3028 loads a protocol pointer from `__OBJC,__protocol` and passes it as the argument to `conformsTo:`. The reference binary's `__OBJC,__protocol` section (base 21424) contains two 20-byte `Protocol` struct records. **Corrected by Task 3:** *both* records' `protocol_name` fields point at `__OBJC,__class_names+36` and read `"IOSCSIControllerExported"` — the first record is not `IOSCSIController`, and no such string exists in the binary. The two records are `SCSIServer.m`'s and `IOSCSISession.m`'s independent static copies of the same protocol; this call site uses the second (its own translation unit's) and `+[SCSIServer requiredProtocols]` uses the first.

**Our source:** declares and uses `@protocol(IOSCSIControllerExported)` at `IOSCSISession.m:441` but does not declare the protocol itself anywhere in the source tree. The only protocol declaration in `IOSCSISession.h` is `@protocol IOSCSIController` (line 19), a different name. Similarly, `SCSIServer.m:21` declares `extern Protocol *objc_protocol_IOSCSIController;` to reference the compiled protocol struct by its mangled name, but there is no declaration of `objc_protocol_IOSCSIControllerExported`.

**Consequence:** on a PPC rebuild, `@protocol(IOSCSIControllerExported)` fails to compile — the reference's own GCC Objective-C front end (`src/cc-1/cc/objc-act.c`, `build_protocol_expr`) resolves `@protocol(X)` purely by calling `lookup_protocol()` against the compiler's internal `protocol_chain`, which is populated only by an actual `@protocol X ... @end` definition or a forward `@protocol X;` declaration (`start_protocol`/`objc_declare_protocols`). It never consults C-level extern symbols, so an `extern Protocol *objc_protocol_IOSCSIControllerExported;` declaration — the fix this finding originally recorded, by analogy with `SCSIServer.m:21`'s `objc_protocol_IOSCSIController` — would not satisfy `lookup_protocol()` and the file would still fail to compile with "Cannot find protocol declaration for `IOSCSIControllerExported`". (`SCSIServer.m:21`'s pattern solves a different problem: obtaining the compiled `Protocol *` for a *file-scope static array initializer*, where `@protocol(IOSCSIController)` is a natural fit but the codebase instead reads it via an extern name; `IOSCSISession.m:1086`'s use is an ordinary function-body expression, which still requires the protocol to be declared to the parser regardless.) The actual, corrected fix (Task 12): add `@protocol IOSCSIControllerExported @end` to `IOSCSISession.h`, matching the existing `@protocol IOSCSIController` declaration's style — this is what makes `lookup_protocol()` succeed at `IOSCSISession.m:1086`.

**The six execute variants read together (Step 3 of the brief).** `executeRequest` (4288),
`executeRequestScatter` (4828) and `executeRequestOOLScatter` (4544), and their `executeSCSI3*`
counterparts (5220, 5760, 5476), are structurally identical between the reference and our source, and
consistent within each pair:
- `executeRequest`/`executeSCSI3Request` test a request-embedded buffer field (legacy offset `+0x14`,
  SCSI-3 offset `+0x24`); if absent, they check `findReservation` and would dispatch
  `executeRequest:buffer:client:`/`executeSCSI3Request:buffer:client:` directly with `NULL`/`NULL` for
  the buffer arguments; if present, they build a single-entry `{size, address}` range on the stack and
  tail-call the matching `*Scatter` function with `rangeCount=8` (one range, `count = rangeCount >> 3`).
  The reference's own `_IOSCSISession_executeRequest` (4288) resolves its final `bl` (address 4496,
  via relocation addend 4828) directly to `_IOSCSISession_executeRequestScatter`'s entry point, and the
  argument registers at that call site (`r3`=session, `r4`=request, `r5`=client — untouched since
  entry — `r6`=`&ioRange`, `r7`=8, `r8`=result) match `executeRequestScatter`'s own parameter
  assignment instruction for instruction; the reference's `_IOSCSISession_executeSCSI3Request` (5220)
  does the identical thing into `_IOSCSISession_executeSCSI3RequestScatter` (5760, relocation addend at
  the call site's island). Our source's `return IOSCSISession_executeRequestScatter(session, request,
  client, &ioRange, 8, result);` (`IOSCSISession.m:1197-1198`) and the SCSI-3 equivalent
  (`IOSCSISession.m:908-909`) reproduce this delegation exactly, including the constant `8`.
  (Citations updated in the final whole-branch review fix pass for the constant -1010 line shift
  Task 10's IOTask.m/.h split introduced.)
- `executeRequestOOLScatter`/`executeSCSI3RequestOOLScatter` both wire the out-of-line buffer, then
  forward the OOL address and length as the `ioRanges`/`rangeCount` arguments to the matching
  `*Scatter` function (not `*Request`), then unwire. In the reference, `executeRequestOOLScatter`'s
  (4544) second `bl` resolves (relocation addend 4828) to `_IOSCSISession_executeRequestScatter`'s own
  entry, with the call-site argument registers matching `executeRequestScatter`'s parameter assignment
  the same way as above; `executeSCSI3RequestOOLScatter` (5476) resolves its second `bl` (relocation
  addend 5760) to `_IOSCSISession_executeSCSI3RequestScatter`'s entry the same way. Our source's
  `IOSCSISession_executeRequestScatter(session, request, client, oolData, oolDataSize, result)`
  (`IOSCSISession.m:1376-1377`) and the SCSI-3 equivalent (`IOSCSISession.m:1082-1083`) match.
- No in-line/out-of-line mix-up exists anywhere in the set: the legacy trio consistently uses offsets
  `+0x14` (buffer)/`+0x10` (direction)/`+0x20` (status) and the SCSI-3 trio consistently uses
  `+0x24`/`+0x20`/`+0x30`, in both the reference disassembly and our source's comments and field
  accesses, and neither track ever borrows the other's offsets or delegates to the other track's
  `*Scatter` function.
- The one thing this reading surfaced that is **not** a mix-up but is still worth recording: all six
  functions share the same "dispatch stubbed out" defect below, so the delegation structure above is
  the only part of these six functions the reference and our source currently have in common.

## Finding: twelve of the eighteen wrapper functions never send the Objective-C message the reference sends

**Source:** `IOSCSISession.m:1572` (`releaseTarget`, line 1605-1608), `:1512` (`reserveSCSI3Target`,
line 1535-1539), `:1446` (`releaseSCSI3Target`, line 1475-1478), `:1406` (`numberOfTargets`, line
1414-1417), `:1131` (`executeRequest`, line 1175-1180), `:1229` (`executeRequestScatter`, lines
1252-1318 throughout), `:1347` (`executeRequestOOLScatter`, via its call into the stubbed
`executeRequestScatter`), `:842` (`executeSCSI3Request`, line 885-889), `:937`
(`executeSCSI3RequestScatter`, lines 960-1026 throughout), `:1053` (`executeSCSI3RequestOOLScatter`,
via its call into the stubbed `executeSCSI3RequestScatter`), `:798` (`resetSCSIBus`, lines 806-809),
`:780` (`returnFromScStatus`, lines 787-789). (Citations updated in the final whole-branch review fix
pass; the Task 10 IOTask.m/.h split shifted every one of these by a constant -1010 lines, since none
of these twelve functions themselves moved out of IOSCSISession.m.)

**Reference behaviour:** for every one of these twelve addresses, the disassembly contains a real
`bl` to a jump island whose relocation resolves to `_objc_msgSend` (confirmed for each site
individually via the same relocation-table technique used above and in Task 4), loading the correct
selector (see the selector-identity paragraph above) and the correct receiver
(`*(*(session+4)+8)`, i.e. the controller/device object, loaded identically to the six matched
functions). `executeRequestScatter`/`executeSCSI3RequestScatter` additionally show full,
instruction-accounted-for `[[IOMemoryDescriptor alloc] initWithIORange:count:byReference:]`,
`setClient:`, `wireMemory:`, `unwireMemory`, and `release` sequences.

**Our source:** every one of these call sites is a `/* TODO: ... */` comment containing the *correct*
call (right selector, right arguments, right receiver) followed by code that never executes it —
typically `exec_result = 0;` / `result = 0;` / `target_count = 0;` assigned directly instead of calling
`objc_msgSend`, or (for `executeRequestScatter`/`executeSCSI3RequestScatter`) `ioMemDesc = NULL;`
instead of allocating one, which then forces the function down its own "allocation failed" branch
every time. `resetSCSIBus` and `returnFromScStatus` don't call their controller method at all, not even
in stub form. The comments are not guesses about behaviour the disassembly doesn't support — cross-
referenced above, every commented-out call matches the reference's real call byte for byte (selector,
argument count and order) — but none of the twelve execute.

**Consequence:** this is a severe, non-cosmetic divergence covering exactly two-thirds of this block.
None of `reserveSCSI3Target`, `releaseSCSI3Target`, `releaseTarget`, `numberOfTargets`, `resetSCSIBus`,
`returnFromScStatus`, or any of the six `executeRequest*`/`executeSCSI3Request*` variants would
actually reach the SCSI controller on the eventual PPC rebuild — every one of them reports success (or
a hardcoded not-reserved/allocation-failure error) without ever performing the operation a caller
requested. `reserveSCSI3Target`/`releaseSCSI3Target`/`releaseTarget` compound this by then calling
`addReservation`/`removeReservation` on the strength of a `result`/`is_reserved` value that was never
actually obtained from the controller. Left `unexamined` for all twelve; Task 12 should uncomment and
wire up each stubbed call (the comments already state the correct selector and arguments for every
site, so this is mechanical rather than requiring new investigation).

## Finding: `IOSCSISession_returnFromScStatus` discards the reference's return value and declares the wrong return type

**Source:** `IOSCSISession.m:209` (header) and `:1790` (definition), both declaring
`void IOSCSISession_returnFromScStatus(id session, unsigned int scStatus)`.

**Reference behaviour:** address 6236 (52 bytes). After `bl sub_1890` (the `objc_msgSend(controller,
returnFromScStatus:, scStatus)` call, confirmed above), the function falls straight through to its
epilogue (`addi r1,r1,0x40` / restore `lr` / `blr`) with no intervening instruction that touches `r3`.
`r3` therefore still holds `objc_msgSend`'s return value when the function returns — i.e. the
reference function returns whatever `-[controller returnFromScStatus:]` returns; it is not `void`.

**Our source:** declared `void` in both the header and the definition, and (per the Finding above) does
not call the controller at all. Even if the stubbed call were wired up, a `void`-declared function has
nowhere to put the controller's return value for its own caller to see.

**Consequence:** on top of the missing dispatch, this function's signature itself cannot reproduce the
reference's behaviour without changing — any caller of `IOSCSISession_returnFromScStatus` (this is the
MiG-facing side of the demux Task 6 will reconstruct) needs the converted `IOReturn` value this
function is supposed to hand back. Left `unexamined`; Task 12 should change the return type to `int`
(or the appropriate `IOReturn` typedef) in both the header and definition, `return` the dispatched
value, and wire up the call per the Finding above.

## Finding: `executeRequestOOLScatter` and `executeSCSI3RequestOOLScatter` assign the result of a `void`-declared function to an `int` (resolved)

**Source:** `IOTask.h:44` now declares `int IOTaskWireMemory(unsigned int address, int length);` (moved
from `IOSCSISession.h:142`, and changed from `void` to `int` by commit `84fffeb1`, resolving the type
mismatch this finding originally recorded — see below); the call sites at `IOSCSISession.m:1361`
(`executeRequestOOLScatter`) and `:1067` (`executeSCSI3RequestOOLScatter`) (moved from `:2371`/`:2077`
by Task 10's IOTask.m/.h split) both write `wire_result = IOTaskWireMemory((unsigned int)oolData,
oolDataSize);` and then branch on `if (wire_result != 0)`.

**Reference behaviour:** in both OOL wrappers, the first `bl` (address 4624 in
`executeRequestOOLScatter`, resolving via relocation addend to address 6716; address 5556 in
`executeSCSI3RequestOOLScatter`, resolving to the same address 6716 — a single shared helper used by
both) is followed immediately by `cmpwi cr1, r3, 0` / `beq cr1, ...`, i.e. the reference treats this
call's `r3` return value as meaningful and branches on it. A `void` function has no defined return
value to branch on; the reference's own behaviour requires this helper to return an `int`.

**Our source (as recorded when this finding was written):** declared the callee `void`
(`IOSCSISession.m:142`, now `IOTask.h:44`) while simultaneously using it as
though it returns `int` at both call sites. Assigning the result of a `void` expression to an `int`
variable, and then comparing that variable to `0`, is a `C` type error — this does not compile as
written, independent of the missing-dispatch Finding above (`IOTaskWireMemory` is presumably one of
this file's own functions rather than a controller message, so it is not covered by that Finding, but
the call sites are inside two of this block's 18 functions, which is why it is recorded here rather
than deferred to Task 6). Separately, the reference's fourth call in each OOL wrapper (address 4716 in
`executeRequestOOLScatter`, address 5648 in `executeSCSI3RequestOOLScatter`) resolves by name to the
imported `_IOUnmapPhysicalFromIOTask` (not `vm_deallocate`, which is what both of our source's
"TODO: Call vm_deallocate(...)" comments guess it is); this is a secondary naming detail Task 6 or 12
should resolve when it reconciles `IOTaskWireMemory`/`IOTaskUnwireMemory` against whatever "plumbing"
functions the reference actually links.

**Consequence:** a real, compile-blocking type mismatch inside two of this block's 18 functions (the
declaration is header-wide, so every other caller of `IOTaskWireMemory` would need the same fix).
Resolved: commit `84fffeb1` changed `IOTaskWireMemory`'s declaration (in both `IOTask.h` and
`IOTask.m`) to return `int`, matching the reference's own use of the call's result and both call
sites' existing use of it. The stub body itself (never issuing `vm_map_pageable`/the reference's
actual helper, reading `_page_size` instead of `_page_mask`) is separate, unresolved stub-body work —
see the `_IOTaskWireMemory`/`_IOTaskUnwireMemory` finding above.

## Task plumbing and the MiG demux (Task 6)

Task 6 read the seven `IOTask`-plumbing functions (addresses 6460-9179) and the MiG demux
(13520) against `IOSCSISession.m`, resolving every `bl` to an unnamed jump island through
`binrecon.macho.read_macho`'s relocation table (`extensions.macho.relocations`) the same way
Tasks 4 and 5 did — the named export strips `calls` for all eight of these functions too.

| Address | Function | Status | What was compared |
| --- | --- | --- | --- |
| 6460 | `_IOTaskPortAllocateName` | `unexamined` | Finding: stub replaces the real `port_allocate`/`port_rename` calls; wrong return type |
| 6652 | `_IOTaskPortDeallocate` | `unexamined` | Finding: stub replaces the real `port_deallocate` call; wrong return type |
| 6716 | `_IOTaskWireMemory` | `unexamined` | Finding: stub replaces the real `vm_map_pageable` call; wrong return type; wrong mask symbol |
| 6812 | `_IOTaskUnwireMemory` | `unexamined` | Finding: stub replaces the real `vm_map_pageable` call (the same helper as Wire, not a second function); wrong return type; wrong mask symbol |
| 6908 | `_IOReferenceClientTask` | `unexamined` | Finding: stub replaces the real `port_rename` call; true signature recovered |
| 7156 | `_IODereferenceClientTask` | `unexamined` | Finding: wrong table and wrong field offset for the refcount |
| 8988 | `_IOReleaseNotifyForFunc` | `unexamined` | Finding: invented parallel array not present in the reference |
| 13520 | `_IOSCSISessionMig_server` | `intentional-mismatch` | hand-written demux stood in for MiG output; replaced by Task 9's `IOSCSISessionMig.defs`, whose argument types were then corrected against the reference's own `<arg>Check`/`<arg>Type` descriptors. ID range (0x1092-0x10a3) and reply-header convention match, but the dispatch table was wired wrong on all 18 entries — see the ledger's own `--reason` text for this entry, and its `source_path`/`source_line` (now citing `IOSCSISessionMig.defs`, since the demux is build output with no checked-in source line of its own), which are the durable record per this task's tooling constraints |

**Groundwork: the `__SCSIServer_deviceStyle_` loads are all `_entry`, not a class method.** All
seven plumbing functions load a pointer via `lis`/`lwz __SCSIServer_deviceStyle_@ha`/`@l` in the
named export. This is the same "analyzer gap at address 0" artifact described above: the exporter's
disassembly view falls back to the nearest preceding *symbol table* name
(`+[SCSIServer deviceStyle]`, address 0) whenever a load has no local symbol of its own, because IDA
emits no function entry at address 0 to attach the name to correctly. `read_macho`'s relocation
table resolves every one of these loads to the actual external symbol `_IOTask_kern`, in every one
of the seven functions. This is not a divergence — it is why the raw disassembly looks like it is
loading a class method instead of a data pointer, and it is recorded so a future reader doesn't need
to re-derive it.

**Resolved (Task 4): the global's name and both field names were wrong, the offsets were right.**
`_IOTask_kern` accounts for 23 of the reference's relocations and `_IOTask` — a different global — for
the other 4 (both in `__io_task_notification`, at 7696/7700 and 8176/8180). Neither is called
`_entry`; that name appeared nowhere but our own declaration. Both globals are DriverKit's own:
`src/driverkit-3/libDriver/Kernel/generalFuncsPrivate.m:72-74` declares `port_name_t IOTask;` and
`task_t IOTask_kern;  // kernel internal version of IOTask`. `IOTask_kern` is therefore a
`struct task *` (`src/kernel-7/kern/task.h:74`), and the two offsets our declaration covered are
`+0x18` = `map`, struct task's "Address space description" (`kern/task.h:81`, the `vm_map_pageable`
argument), and `+0xa4` = `itk_space`, the task's IPC space — the latter confirmed independently by
`src/kernel-7/driverkit/driverServerXXX.m:343`, which writes `IOTask_kern->itk_space` as the first
argument of the same `ipc_object_copyin_compat` call this driver makes. The old field names
`task_port` and `port_funcs` were guesses: neither offset holds a port or a function table. **No
offset outside the declaration is touched**, by these seven functions or by Task 4's six, so the
declaration needed renaming, not extending. `IOTask.m`'s declaration now reads `IOTask_kern` with
fields `map`/`itk_space`, and `IOTask` is declared alongside it.

## Finding: `_IOTaskPortAllocateName` never issues its own two Mach calls, and is declared `void` where the reference returns a status

**Source:** `IOTask.m:88-107` (`IOTaskPortAllocateName`), declared `void` at both
`IOTask.h:22` and `IOTask.m:88`. (Moved from `IOSCSISession.m:1760-1779`/`IOSCSISession.h:158` by
Task 10's IOTask.m/.h split; citation updated in the final whole-branch review fix pass.)

**Reference behaviour:** the function (address 6460, 96 bytes) loads `_entry->port_funcs` and calls
the imported `_port_allocate(port_funcs, &allocated_port)` (relocation at address 6500 names
`_port_allocate` directly). `mr. r3,r3` / `bne cr0, loc_1984` (addresses 6504-6508) test that result
and, on failure, skip straight to the epilogue with `r3` still holding `port_allocate`'s error code —
**no instruction clears `r3` before the return** on that path. On success, `port_funcs` is reloaded
and the imported `_port_rename(port_funcs, allocated_port, name)` is called (relocation at address
6528 names `_port_rename`); the epilogue immediately follows that call too, again with no
intervening write to `r3`. Both paths therefore return whatever the last kernel call placed in `r3`
— the reference function is not `void`, it returns an `int` status.

**Our source:** calls neither `port_allocate` nor `port_rename`. `result = 0;` is hardcoded (line
1772) in place of the `port_allocate` call the adjacent comment already names
(`FUN_000019ac(port_funcs, &allocated_port)`), and the `port_rename` call
(`FUN_0000199c(port_funcs, allocated_port, name)`) is left as a comment inside the `if (result == 0)`
body with nothing executing it. Both the header and definition declare the function `void`.

**Consequence:** this is the same "TODO comment plus a hardcoded value instead of the real call"
pattern already recorded for twelve of the eighteen C wrappers in the finding above ("twelve of the
eighteen wrapper functions never send the Objective-C message the reference sends") — here the
missing calls are two Mach IPC primitives instead of an `objc_msgSend`, so on the eventual PPC
rebuild a session would never actually receive a renamed port name for its notification port.
Separately, the `void` return type is wrong independent of the stub: `IOSCSISession.m:253` (the call
site stayed in IOSCSISession.m across the IOTask.m split; line renumbered) already
calls `result = IOTaskPortAllocateName(self);`, assigning a `void` expression to `result` — a second,
independent compile error at that call site (which also passes `self`, an `id`, where the reference
expects a `mach_port_t name`; that call site is outside this task's eight addresses and is left for
whichever task disposes it). Left `unexamined`; Task 12 should wire up the two calls named in the
existing comments and change the declaration in both the header and definition to return `int`
(propagating the last kernel call's result), matching the reference and the caller's existing use of
the return value.

## Finding: `_IOTaskPortDeallocate` never issues its own Mach call, and is declared `void` where the reference returns a status

**Source:** `IOTask.m:113-123` (`IOTaskPortDeallocate`), declared `void` at both
`IOTask.h:37` and `IOTask.m:113`. (Moved from `IOSCSISession.m:1744-1754`/`IOSCSISession.h:153` by
Task 10's IOTask.m/.h split; citation updated in the final whole-branch review fix pass.)

**Reference behaviour:** the function (address 6652, 48 bytes) loads `_entry->port_funcs`, moves the
`port` argument into `r4` (`mr r4, r3` at address 6664, from the incoming `r3`), and calls the
imported `_port_deallocate(port_funcs, port)` (relocation at address 6680 names `_port_deallocate`
directly) — matching the comment's own guess of "`mach_port_deallocate()`" closely enough to confirm
which call this is. The epilogue (`addi r1, r1, 0x40` at address 6684) follows immediately, with no
instruction clearing `r3` — the function returns whatever `port_deallocate` returned.

**Our source:** the body is only the comment `/* TODO: Call mach_port_deallocate(); FUN_00001a2c(port_funcs, port) */`
with no call executed at all.

**Consequence:** same species as the finding above and the twelve stubbed wrappers — this instance's
port-name deallocation never actually happens on the eventual PPC rebuild. This is also the function
the "`-[IOSCSISession free]` omits an argument" finding already flagged from the *caller's* side (the
call site drops the `notify_port` argument entirely); that finding and this one are two independent
defects in the same call chain, not duplicates of each other. Left `unexamined`; Task 12 should wire
up the `port_deallocate` call and change the declaration in both the header and definition to return
`int`.

## Finding: `_IOTaskWireMemory` and `_IOTaskUnwireMemory` never issue their shared Mach call, are declared `void` where the reference returns a status, and read the wrong mask symbol (partially resolved)

**Source:** `IOTask.m:138-157` (`IOTaskWireMemory`) and `:164-182` (`IOTaskUnwireMemory`),
declared at `IOTask.h:44`/`:50`, and both computing
`~(_page_size - 1)` against `extern unsigned int _page_size;` (`IOTask.m:22`). (Moved from
`IOSCSISession.m:1691-1709`/`:1716-1734`/`IOSCSISession.h:142`/`:148`/`IOSCSISession.m:34` by Task
10's IOTask.m/.h split; citations updated in the final whole-branch review fix pass.)

**Since this finding was recorded:** commit `84fffeb1` changed `IOTaskWireMemory`'s declared return
type from `void` to `int` (in both `IOTask.h` and `IOTask.m`) so it matches its callers, which was
the part of this finding within that task's scope. `IOTaskUnwireMemory` is still declared `void`, and
neither function issues the shared `vm_map_pageable` call or reads `_page_mask` instead of
`_page_size` — those parts of this finding remain open.

**Reference behaviour:** both functions (address 6716, 80 bytes; address 6812, 80 bytes) have an
identical shape: load `_entry->task_port` (offset `0x18`), load a mask value directly from the
imported external `_page_mask` (relocation at addresses 6740/6744 for Wire, 6836/6840 for Unwire —
**not** `_page_size`), compute `start = address & ~page_mask` and
`end = (address + length + page_mask) & ~page_mask`, and call the imported `_vm_map_pageable(task_port, start, end, wireFlag)`
— relocations at addresses 6776 and 6872 **both** name the identical external symbol
`_vm_map_pageable`; the two calls are not two different kernel functions, they are the same one
called with a different final argument (`li r6, 0` for Wire, `li r6, 1` for Unwire, matching the
comment's own "wire"/"unwire" framing). Both epilogues follow their `bl` immediately with no
instruction clearing `r3` — both functions return `vm_map_pageable`'s result.

**Our source:** neither function calls `vm_map_pageable` (or anything); the body ends at the comment
`/* TODO: Call kernel vm_wire()/vm_unwire() function; FUN_00001a8c(...)/FUN_00001aec(...) */`, naming
what look like two distinct placeholder functions where the reference uses one shared real function.
Separately, both functions read a locally-declared `_page_size` and subtract 1 to build the mask,
where the reference reads a precomputed `_page_mask` external directly — a different imported symbol
name than the one our source declares, so even with the stub filled in, linking against `_page_size`
would not reproduce the reference's actual symbol dependency (`_page_mask`) even though the
arithmetic result would likely be numerically equivalent if both kernel globals are set consistently.

**Consequence:** same missing-call species as the two findings above (no DMA memory ever gets wired
on the eventual rebuild); the `void`-vs-`int` return type mismatch is the same defect the
`executeRequestOOLScatter`/`executeSCSI3RequestOOLScatter` finding above already recorded from the
*caller's* side ("assign the result of a `void`-declared function to an `int`") — that finding and
this one describe the same header-wide type error from opposite ends of the same call, not
duplicates. This finding adds the two callees' own confirmation that the reference does return a
value, plus the `_page_mask`-vs-`_page_size` symbol mismatch, which that earlier finding did not
cover. Left `unexamined` for both addresses; Task 12 wired up `IOTaskWireMemory`'s return type
(commit `84fffeb1`, matching the `executeRequestOOLScatter` finding's request), but not
`IOTaskUnwireMemory`'s, nor either function's `vm_map_pageable` call or `_page_mask`-vs-`_page_size`
symbol mismatch — those remain open for whichever task next picks up stub-body work.

## Finding: `_IOReferenceClientTask` never issues its own Mach call, and its sole parameter is a slot handle into `_clientReferences`, not a bare decompiler pointer

**Source:** `IOTask.m:214-300`, declared `int IOReferenceClientTask(int **param_1)`. (Moved from
`IOSCSISession.m:1590-1676` by Task 10's IOTask.m/.h split; citation updated in the final
whole-branch review fix pass.)

**Reference behaviour:** the function (address 6908, 232 bytes) matches our source's own control flow
exactly — the in-range test against `&_clientReferences[0]`/`&_notifyThread` (addresses 6940-6980),
the linear search for a zero slot (addresses 6984-7052), the "no slots" return of `6` (address 7088),
and the final `*current_entry += 1` (addresses 7100-7108) all correspond instruction-for-instruction
to the source's own commented decompilation. The one place behaviour actually diverges: at address
7076, the call our source's comment calls "a kernel function to set up the reference" (`FUN_00001be4`)
resolves, via relocation, to the imported `_port_rename` — the same real function
`_IOTaskPortAllocateName` calls above — invoked as `port_rename(port_funcs, originalParam1Value, foundSlot)`
(the entry `r3`/`r4`/`r5` at the call site are `port_funcs`, the *original* `*param_1` value from
function entry — reloaded from `0(r30)`, not the updated `current_entry` — and the newly found slot
pointer). The reference then branches on that call's result (addresses 7092-7096: `cmpwi cr1,
r3, 0` / `bne cr1, ...`), returning the error code early rather than falling through to increment the
refcount, before the unconditional increment path.

**Our source:** `result = 0; /* TODO: Call actual kernel function */
/* result = FUN_00001be4(_entry->port_funcs, *param_1, search_ptr); */` — the call is never issued,
so `result` is always `0` and the refcount is always incremented even when the reference's
`port_rename` would have failed and returned early.

**True signature (Step 3 of the brief):** `param_1`'s *type* is already right — the parameter really
is an `int **`, exactly as transcribed — what is wrong is only its meaningless decompiler name. Every
use inside the function (the entry-range test, the search-and-store-back at `*param_1 = search_ptr`,
and the final increment through the resulting pointer) treats it as **a pointer to the caller's own
storage cell holding a slot pointer into `_clientReferences[0..31]`**: on entry, if
`*clientReferenceSlot` does not already point inside that table, the function finds a free slot,
establishes it via `port_rename`, and writes the slot's address back through
`*clientReferenceSlot`; either way it then increments the reference count stored *at* that slot
(`_clientReferences[i]` is a bare `int` refcount, not a struct — matching `_findReservation`'s
sibling functions' own use of `_clientReferences`). This reading is independently corroborated by two
other findings in this section: `_IODereferenceClientTask` (below) expects the identical
`_clientReferences`/`_notifyThread`-range pointer as its own argument, and `_IOReleaseNotifyForFunc`
(below) is shown to store exactly such a slot pointer — not a raw Mach port — in
`notifClients[i*2]`, the same cell layout `IOReferenceClientTask`'s callers would populate. The
recovered true signature for Task 12's declaration is therefore:
```c
int IOReferenceClientTask(int **clientReferenceSlot);
```
(same type as today, renamed parameter, with a comment documenting the in/out slot-handle
semantics above) rather than any change to the parameter's type or count.

**Consequence:** the missing `port_rename` call is the same species of defect as the plumbing
findings above (a `TODO` stub instead of the real call), with the added effect that a failed
port-name setup is silently treated as success. Left `unexamined`; Task 12 should wire up the
`port_rename` call using the original `*param_1` entry value and the found slot, branch on its
result the way the reference does, and rename the parameter per the recovered signature above.

## Finding: `_IODereferenceClientTask` validates and decrements against the wrong table

**Source:** `IOTask.m:313-354`, declared `int IODereferenceClientTask(int *clientEntry)`. (Moved from
`IOSCSISession.m:1519-1563` by Task 10's IOTask.m/.h split; citation updated in the final
whole-branch review fix pass.)

**Reference behaviour:** the function (address 7156, 148 bytes) performs its in-range test against
`&_clientReferences[0]`/`&_notifyThread` — the identical bounds `_IOReferenceClientTask` uses for the
*same* table (addresses 7180-7220) — then reads and writes the refcount at **offset `+0`** of the
argument (`lwz r0, 0(r11)` / `stw r0, 0(r11)`, addresses 7224-7252), decrementing it and, when it
reaches zero, loading `_entry->port_funcs` and calling the imported `_port_deallocate` (relocation at
address 7276) before returning `0`. `_clientReferences[i]` is a bare `int` (one refcount per slot, no
sibling field), so offset `+0` is the *entire* entry — there is no offset `+4` field to read here.

**Our source:** checks the pointer against `&notifClients[0]`/`&notifClients[64]` (lines 1532-1533) —
a *different* global array, one with two `int`s per entry — and reads/writes the refcount at
`clientEntry[1]`, i.e. offset `+4` (lines 1538, 1546, 1549), not offset `+0`.

**Consequence:** a real, non-cosmetic bug, not a register-allocation artifact. If this function is
ever called with a genuine `_clientReferences` slot pointer (the type its sibling
`IOReferenceClientTask` produces and the type the reference's own bounds check expects), our source's
range check would reject it (`_clientReferences` and `notifClients` are different global arrays at
different addresses — see the "Groundwork" and the `_IOReleaseNotifyForFunc` finding below), and even
if the range check were bypassed, decrementing `clientEntry[1]` would touch memory one `int` past the
slot the reference decrements. Left `unexamined`; Task 12 should change the bounds check to
`&_clientReferences[0]`/`&_notifyThread` and the refcount access to offset `+0` (`*clientEntry`, not
`clientEntry[1]`), and wire up the stubbed `_port_deallocate` cleanup call (currently
`result = 0; /* Placeholder */`, the same TODO-stub pattern as the findings above).

## Finding: `_IOReleaseNotifyForFunc` invents a parallel object array the reference does not have (call-site argument partially resolved)

**Source:** `IOTask.m:76-78` (declares `notifClients[64]`, `notifClientObjects[32]` and
`notifClientCnt`) and `:372-404` (`IOReleaseNotifyForFunc`, specifically lines 387-388 and 395).
(Moved from `IOSCSISession.m:1464-1466`/`:1479-1507` by Task 10's IOTask.m/.h split; citation updated,
and the call-site argument fixed, in the final whole-branch review fix pass — see below.)

**Reference behaviour:** the function (address 8988, 192 bytes) walks the same 32-entry, 8-byte-stride
`_notifClients` array our source declares (confirmed via the reference's own local symbol table:
`_notifClients` at address 16532, size matching 32 × 8 = 256 bytes, immediately followed by
`_notifClientCnt` at 16788 — there is **no third global anywhere in `__DATA,__data`/`__DATA,__bss`**
between `_notifyThread` (16520) and `_notifClientCnt` (16788) other than `_notifClients` itself, i.e.
no room for a `notifClientObjects`-sized array to exist). Per entry, the reference compares offset
`+0` against `deathPort` (`r27`) and offset `+4`, loaded from the *same* entry
(`lwz r0, 4(r31)`, address 9080), against `session` (`r28`) — the session identity is stored **inline**
as the second field of the 8-byte entry, not looked up in a separate array indexed by `i`. On a
match, the reference passes **the value loaded from offset `+0`** (`r9`, `mr r3, r9` at address 9092)
— not the entry's address — to `_IODereferenceClientTask` (relocation at address 9096 confirms the
target is address 7156, this task's own `_IODereferenceClientTask`).

**Our source (as of the final whole-branch review fix pass):** still declares a second, separate array
`static id notifClientObjects[32];` (`IOTask.m:77`) and still checks `notifClientObjects[i] == session`
(`:388`) instead of a second field of the same entry, but the call now reads
`IODereferenceClientTask((int *)client_entry[0])` (`:395`) — passing the *value* held in the slot,
not its address, per the reference behaviour above.

**Consequence:** one of the two compounding divergences this finding originally recorded is resolved,
the other is not. `notifClientObjects` still does not exist in the reference's data layout — it is
invented storage with no backing global, so the match test at `:388` can still never agree with the
reference's own (`notifClients[i*2+1] == session`, not `notifClientObjects[i] == session`); that part
of this finding remains open. The `IODereferenceClientTask` call site now passes the value stored in
`notifClients[i*2]` (a `_clientReferences` slot pointer, per the `IOReferenceClientTask` finding
above), matching the reference, rather than the notifClients entry's own address. Whoever next picks
up stub-body work should remove `notifClientObjects` and store the session pointer at
`notifClients[i*2+1]` instead.

## Disposition of the 27 unmapped entries (Task 7)

Task 7 covers everything Tasks 3-6 left out of scope: the MiG dispatch-table wiring, the
"impossible to place" belief that follows from it, the 6 functions our tree has no counterpart for
at all, and two naming defects. Evidence for each finding below was reproduced from the reference
binary and our own source, not asserted.

## Finding: the hand-written MiG dispatch table is wired in the wrong order — every one of the 18 message IDs reaches the wrong handler

**Source:** `IOSCSISession.m:921-940` (`_IOSCSISessionMig_handlers`), consumed by
`IOSCSISessionMig_server` (`IOSCSISession.m:411`; already `intentional-mismatch` per Task 6, reproduced
here because the *reason* recorded there is this table's wiring).

**The demux arithmetic.** The reference's `_IOSCSISessionMig_server` (address 13520) computes, from
the incoming message's `msgh_id` (loaded into `r0` at address 13572, already offset by MiG's usual
`+100` convention for the *outgoing* reply — see below):

```
13576  addic  r0, r0, 0x64        ; reply_id = msgh_id + 0x64 (100), stored into the reply header
...
13608  addic  r0, r0, -0x1092     ; index = msgh_id - 0x1092  (0x1092 = 4242)
13612  cmplwi cr1, r0, 0x11       ; index > 0x11 (17) ?  -> out-of-range, reject
...
13624  lis    r9, 0
13628  addi   r9, r9, -0xAA4      ; r9 = table_base (see the PIC finding below)
```

So the reference accepts message IDs `0x1092`-`0x10A3` (4242-4259, 18 routines — matching
`cmplwi cr1, r0, 0x11`, i.e. `index` must be `<= 17`), computes `reply_id = request_id + 100`, and
indexes a table of 18 function pointers at `r9 + index*4`.

**Apple's table order**, reproduced (not asserted) from the reference's own relocations, which is the
authoritative record of which function pointer sits at which table slot (`__TEXT,__const`, base
`0x37a4`, one 4-byte pointer-relocation per slot, in address order):

```
cd /d/RhapsodiOS && PYTHONPATH=tools/binrecon $PY -c "
from binrecon.macho import read_macho
import os
d = read_macho(os.environ['REF'])
syms = {s['address']: s['name'] for s in d['symbols'] if s['section'] == '__TEXT,__text'}
table = sorted((r for r in d['extensions']['macho']['relocations']
                if r['section'] == '__TEXT,__const'), key=lambda r: r['address'])
for index, r in enumerate(table):
    print('%2d  id %d  0x%04x -> %s' % (index, 4242 + index, r['address'], syms.get(r['addend'], '?')))
"
```
```
 0  id 4242  0x37a4 -> __XIOSCSISession_free
 1  id 4243  0x37a8 -> __XIOSCSISession_initForDevice
 2  id 4244  0x37ac -> __XIOSCSISession_releaseAllUnits
 3  id 4245  0x37b0 -> __XIOSCSISession_reserveTarget
 4  id 4246  0x37b4 -> __XIOSCSISession_releaseTarget
 5  id 4247  0x37b8 -> __XIOSCSISession_reserveSCSI3Target
 6  id 4248  0x37bc -> __XIOSCSISession_releaseSCSI3Target
 7  id 4249  0x37c0 -> __XIOSCSISession_numberOfTargets
 8  id 4250  0x37c4 -> __XIOSCSISession_executeRequest
 9  id 4251  0x37c8 -> __XIOSCSISession_executeSCSI3Request
10  id 4252  0x37cc -> __XIOSCSISession_executeRequestScatter
11  id 4253  0x37d0 -> __XIOSCSISession_executeSCSI3RequestScatter
12  id 4254  0x37d4 -> __XIOSCSISession_executeRequestOOLScatter
13  id 4255  0x37d8 -> __XIOSCSISession_executeSCSI3RequestOOLScatter
14  id 4256  0x37dc -> __XIOSCSISession_resetSCSIBus
15  id 4257  0x37e0 -> __XIOSCSISession_returnFromScStatus
16  id 4258  0x37e4 -> __XIOSCSISession_maxTransfer
17  id 4259  0x37e8 -> __XIOSCSISession_getDMAAlignment
```

**Our table order** (`IOSCSISession.m:921-940`, `_IOSCSISessionMig_handlers[18]`, the literal array
entries in source order, each already commented with its intended message ID):

```
 0  _IOSCSISession_reserveSCSI3Target_handler            /* 0x1092 */
 1  _IOSCSISession_releaseSCSI3Target_handler            /* 0x1093 */
 2  _IOSCSISession_reserveTarget_handler                 /* 0x1094 */
 3  _IOSCSISession_releaseTarget_handler                 /* 0x1095 */
 4  _IOSCSISession_executeSCSI3Request_handler           /* 0x1096 */
 5  _IOSCSISession_executeSCSI3RequestScatter_handler    /* 0x1097 */
 6  _IOSCSISession_executeSCSI3RequestOOLScatter_handler /* 0x1098 */
 7  _IOSCSISession_executeRequest_handler                /* 0x1099 */
 8  _IOSCSISession_executeRequestScatter_handler          /* 0x109A */
 9  _IOSCSISession_executeRequestOOLScatter_handler       /* 0x109B */
10  _IOSCSISession_resetSCSIBus_handler                   /* 0x109C */
11  _IOSCSISession_numberOfTargets_handler                /* 0x109D */
12  _IOSCSISession_getDMAAlignment_handler                /* 0x109E */
13  _IOSCSISession_maxTransfer_handler                    /* 0x109F */
14  _IOSCSISession_releaseAllUnits_handler                /* 0x10A0 */
15  _IOSCSISession_free_handler                           /* 0x10A1 */
16  _IOSCSISession_initForDevice_handler                  /* 0x10A2 */
17  _IOSCSISession_returnFromScStatus_handler             /* 0x10A3 */
```

**Side by side, by table slot (message ID = 4242 + slot):**

| Slot | ID | Apple's routine | Our routine | Match? |
| --- | --- | --- | --- | --- |
| 0 | 4242 | `free` | `reserveSCSI3Target` | no |
| 1 | 4243 | `initForDevice` | `releaseSCSI3Target` | no |
| 2 | 4244 | `releaseAllUnits` | `reserveTarget` | no |
| 3 | 4245 | `reserveTarget` | `releaseTarget` | no |
| 4 | 4246 | `releaseTarget` | `executeSCSI3Request` | no |
| 5 | 4247 | `reserveSCSI3Target` | `executeSCSI3RequestScatter` | no |
| 6 | 4248 | `releaseSCSI3Target` | `executeSCSI3RequestOOLScatter` | no |
| 7 | 4249 | `numberOfTargets` | `executeRequest` | no |
| 8 | 4250 | `executeRequest` | `executeRequestScatter` | no |
| 9 | 4251 | `executeSCSI3Request` | `executeRequestOOLScatter` | no |
| 10 | 4252 | `executeRequestScatter` | `resetSCSIBus` | no |
| 11 | 4253 | `executeSCSI3RequestScatter` | `numberOfTargets` | no |
| 12 | 4254 | `executeRequestOOLScatter` | `getDMAAlignment` | no |
| 13 | 4255 | `executeSCSI3RequestOOLScatter` | `maxTransfer` | no |
| 14 | 4256 | `resetSCSIBus` | `releaseAllUnits` | no |
| 15 | 4257 | `returnFromScStatus` | `free` | no |
| 16 | 4258 | `maxTransfer` | `initForDevice` | no |
| 17 | 4259 | `getDMAAlignment` | `returnFromScStatus` | no |

Every one of the 18 slots names a different routine than Apple's table at that slot. This is not a
handful of transposed neighbours — the two orderings share no fixed point at all.

**Consequence:** because the reply-ID convention (`request_id + 100`) and the accepted ID range
(`0x1092`-`0x10A3`) both match, a client's RPC will be *accepted* (it passes the bounds check) and
will *get a reply in the shape the client expects* (the reply ID arithmetic is right) — but the reply
will come from the *wrong handler*. A `reserveSCSI3Target` request (ID 4247) dispatches through our
table's slot 5, which calls `executeSCSI3RequestScatter_handler`, not
`reserveSCSI3Target_handler`. No message ID in the current table reaches the routine the reference
dispatches for that same ID. This is the central finding of Task 7: the demux Task 6 already flagged
as `intentional-mismatch` is not merely "different code, same effect" — it is wired to run the wrong
handler for every single request, which Task 9 (recovering the MiG interface) must fix by re-deriving
the table from `IOSCSISessionMig.defs` rather than by reordering entries to match the list above,
since the `.defs` file, not this table, is this project's source of truth going forward.

## Finding: the dispatch-table comment misreads a resolved PIC displacement as an address requiring manual placement

**Source:** `IOSCSISession.m:899-916` (the comment block above `_IOSCSISessionMig_handlers`).

**Our source's comment reads:**
> "For proper linkage, this table needs to be at the correct offset in memory. ... For a complete
> recreation, you would need to use linker scripts or compiler-specific directives to place this at
> the correct address."

**Reference behaviour:** the instructions the comment is trying to explain are, at addresses
13624-13628:
```
13624  lis  r9, 0
13628  addi r9, r9, -0xAA4
```
Read as *static* immediates, `r9` would end up holding `0 + (-0xAA4) = -0xAA4` — a nonsense address.
But these two instructions are not static immediates: each carries a **scattered relocation pair**
(`ppc-scattered-ha16-32-absolute` at 13624, `ppc-scattered-lo16-32-absolute` at 13628), and both
relocation entries' own `r_value` field (the value Mach-O scattered relocations use to identify which
section the reference is *to*, confirmed by instrumenting `binrecon.macho._ppc_section_of` directly
rather than trusting the semantic `addend` field, which reports the offset *from* that section, not
the absolute value) is **`0x37a4`** — the exact base address of the dispatch table in
`__TEXT,__const` (`__TEXT,__const`'s section address is `14084`/`0x3704`; `0x37a4` falls inside it,
and it is literally slot 0 of the table dumped in the finding above). The linker, at build time,
rewrote the `lis`/`addi` immediate halves so that executing them at runtime produces `r9 = 0x37a4`
directly — not `-0xAA4`. `-0xAA4` is simply the *pre-relocation placeholder* the assembler originally
encoded (as if the table's address were `0`); it is an artifact of reading the still-relocatable
object code as if it were already linked, not a real runtime displacement and not an address that
needs "linker scripts or compiler-specific directives" to place anywhere. The whole point of a
scattered relocation is that the linker already resolves this for you at the final link — that is
what "scattered" relocations are *for* in PIC/position-independent Mach-O object code.

**Consequence:** this is not a cosmetic misreading — it is the reasoning that led the comment's author
to treat a faithful reconstruction of the dispatch table's addressing as impossible without
"linker scripts or compiler-specific directives", which is very likely *why* the table ended up
hand-ordered by best guess (see the finding above) rather than derived mechanically from the
reference. There is nothing to place at a fixed address: `_IOSCSISessionMig_handlers` is an ordinary
static array; whatever address the linker gives it, `lis`/`addi`-with-relocation (or, in C, just
naming the array) resolves correctly, exactly the way our own `_IOSCSISessionMig_handlers` array
already does today (it has no special placement and does not need one) — the reference's approach and
ours are actually compatible in this respect. Task 9, when re-deriving the table from
`IOSCSISessionMig.defs`, does not need to solve a placement problem; the ordering problem in the
finding above is the only real defect here.

## Finding: six functions our tree lacks entirely

**Source:** none — no definition exists anywhere in `src/drvSCSIServer` for five of these; the sixth
(`_IORequestNotifyForClientTask`) is declared `extern` at `IOSCSISession.m:19` and called at
`IOSCSISession.m:282`, but never defined in this file or anywhere else in the project.

Each function below was dumped with Task 3 Step 1's command (disassembly by address against
`analysis-reference-ida.named.json`) and, because the named export strips jump-island calls, every
`bl` target was independently resolved through `binrecon.macho.read_macho`'s relocation table the
same way the "resolving a jump island" technique above resolved `_IOExitThread`.

| Function | Address | Bytes | State in our tree |
| --- | --- | --- | --- |
| `__io_task_notification` | 7624 | 644 | absent |
| `_IORequestNotifyForClientTask` | 8412 | 480 | declared `extern`, never defined |
| `_serverThreadFunc` | 2672 | 276 | absent |
| `_IOConvertTaskPortToVMTask` | 7320 | 160 | absent |
| `_IOTaskPortAllocate` | 6588 | 48 | absent (only `_IOTaskPortAllocateName` exists, a different, already-mapped function at address 6460) |
| `_IODestroyMappedVMTask` | 7576 | 32 | absent |

### `__io_task_notification` (address 7624, 644 bytes) — the largest of the six

Takes no visible arguments (consistent with being a thread entry point — see
`_IORequestNotifyForClientTask` below, which forks it via `_IOForkThread(&__io_task_notification, 0)`).
Behaviour, traced instruction-for-instruction with every `bl` resolved via relocation:

1. Calls `_IOTaskPortAllocate(&localPort)` (the sibling function documented below, address 6588). On
   failure (non-zero result), logs `IOLog("_io_task_notification: IOTaskPortAllocate - %d\n", result)`
   and jumps straight to the drain phase (step 4; address 7692's `b loc_1F14` targets address 7956,
   the drain phase's own entry point, not the cleanup/exit tail directly).
2. On success, calls the imported `task_set_special_port_EXTERNAL(_IOTask, 2, localPort)` — installs
   the newly allocated port as special-port slot `2` (`TASK_NOTIFY_PORT`, `src/kernel-7/mach/task_special_ports.h:93`,
   "Task receives kernel IPC notifications here") of the global task handle **`_IOTask`** — not
   `_IOTask_kern`. This is a distinct undefined external: the relocations at the load site (addresses
   7696/7700) name `_IOTask` directly, confirmed by dumping every `IOTask`-containing relocation target
   in `__TEXT,__text`:
   ```
   PYTHONPATH=tools/binrecon $PY -c "
   from binrecon.macho import read_macho
   import os
   d = read_macho(os.environ['REF'])
   for r in d['extensions']['macho']['relocations']:
       if r['section'] == '__TEXT,__text' and 'IOTask' in str(r['target']):
           print(r['address'], r['target'])
   "
   ```
   Of the 27 `IOTask*`-named relocations in `__TEXT,__text`, exactly four — 7696, 7700 (this call) and
   8176, 8180 (the mirror-image reset in step 4) — name `_IOTask`; the other 23 (across the seven
   already-mapped plumbing functions and `_IOConvertTaskPortToVMTask`/`_IORequestNotifyForClientTask`
   below) all name `_IOTask_kern`. `_IOTask` and `_IOTask_kern` are therefore two different undefined
   globals, and `__io_task_notification` is the *only* function in the reference that reads `_IOTask`;
   nothing here confirms it is the same external our source's `_entry`/`IOTask_kern` groundwork reads
   in the seven mapped plumbing functions, so that claim is withdrawn. On failure, logs
   `"_io_task_notification: task_set_special_port - %d\n"` and jumps to the drain phase (7736's
   `b loc_1F14` also targets 7956).
3. On success, enters what is effectively an unbounded server loop: builds a Mach message buffer with
   `msg_size` set to `0x20` (32) at offset `+4` of the header, and calls the imported
   `_msg_receive(hdr, 0x100, 0xEA60)` repeatedly. `0x100` is `RCV_TIMEOUT`
   (`src/kernel-7/mach/message.h:762`, "Terminate on timeout elapsed"); `0xEA60` (60000) is the
   millisecond timeout paired with it.
   - A result of `-0xCB` (-203) is `RCV_TIMED_OUT` (`message.h:800`) and retries the receive.
   - Any other non-zero result logs `"_io_task_notification: msg_receive - %d\n"` and falls into the
     drain phase (7752's `b loc_1F14` also targets 7956).
   - A result of `0` (message received) first checks `_notifClientCnt`: if it is already `0`, control
     jumps straight past the drain phase to the cleanup/exit tail (address 8176; nothing to drain).
     Otherwise it scans the 32-entry, 8-byte-stride `_notifClients` array — the same global
     `_IOReleaseNotifyForFunc` (address 8988, already examined in Task 6) walks — comparing each
     entry's first field against the just-received message's source port field. On a match, it calls
     `_IODereferenceClientTask` (address 7156, already mapped) with the entry's first field, `bzero`s
     the 8-byte entry, decrements `_notifClientCnt`, and calls `_msg_send` once (an
     acknowledgement/reply). Whether or not slot `i` matched, the scan advances to `i+1`; when
     `_notifClientCnt` reaches zero mid-scan, or the scan exhausts all 32 slots, control returns to the
     top of the loop and calls `_msg_receive` again for the next notification. The function does not
     return in the ordinary case — it is a permanent per-notification-thread server loop.
4. **The drain phase (addresses 7956-8172), skipped entirely by the earlier pass.** Every error path
   above (`b loc_1F14` at 7692, 7736, 7752) branches here, and the main loop falls into it after every
   successfully received message. It is a *second*, independent 32-slot pass over `_notifClients`, run
   whenever the thread is about to exit (any error, or the loop's own `_notifClientCnt == 0` check
   already routes around it — see above) — its job is to synthesize a "this session's notification is
   gone" broadcast to every client still registered, not to process one received message:
   - 7956-7968: if `_notifClientCnt` is already `0`, skip straight to the cleanup/exit tail (8176); no
     clients to notify.
   - 7972-8044: builds a fresh message header on the stack: `msg_size = 0x20` (32, address
     7980/7984), and `msg_id = 0x41` (`li r0, 0x41` / `stw r0, hdr+0x14` at 8000/8004) — `0x41` is
     `NOTIFY_PORT_DELETED` (`src/kernel-7/mach/notify.h:152-153`, `NOTIFY_FIRST` (`0100` = 0x40) `+ 1`,
     "A send or send-once right was deleted"), plus a `msg_type_t`/NDR-style bitfield built at
     8008-8044 for the message body.
   - 8048-8172: `i = 0`; while `i <= 31` and `_notifClientCnt != 0`: if `_notifClients[i]`'s first field
     is `0` (empty), skip to `i+1`. Otherwise: store `_notifClients[i]`'s second field (offset `+4`,
     loaded at 8100) into the header's `msg_remote_port` field, call
     `_IODereferenceClientTask(_notifClients[i][0])` (the entry's first field), `bzero` the 8-byte
     entry, decrement `_notifClientCnt`, call `_msg_send(hdr, 1, 0)`, then advance to `i+1`. When the
     loop exits (count reached zero or all 32 slots scanned), control falls into the cleanup/exit tail
     at 8176.

   A source written from the earlier description (which jumped straight from the error paths to the
   8176-8228 exit tail) would silently drop this entire client-teardown broadcast.
5. The cleanup/exit tail (address 8176-8231, reached from the drain phase above and from the loop's own
   `_notifClientCnt == 0` short-circuit): resets special-port slot `2` back to
   `task_set_special_port_EXTERNAL(_IOTask, 2, 0)` (undoing step 2 — confirmed `_IOTask`, not
   `_IOTask_kern`, by the same relocation dump above: addresses 8176/8180 are the other two of the four
   `_IOTask` uses in the whole binary), calls `_IOTaskPortDeallocate` (address 6652, already mapped) on
   the locally allocated port unless it is already `0`, zeroes the global `_notifyThread` (marking "no
   notification thread is running" — the same global `_IORequestNotifyForClientTask` below checks
   before forking a new one), then calls the imported `_IOExitThread()`, which does not return; the
   disassembler's own epilogue bytes after that call are unreachable.

Special-port slot `2`, the `_msg_receive`/`_msg_send` option and notification-ID constants above are
all now named from this tree's own Mach headers (`task_special_ports.h`, `message.h`, `notify.h`), so
none of them are "could not determine" any longer.

**Resolved (Task 4): it is both.** The question of whether `_notifClients[i]`'s first field is a bare
Mach port name or a `_clientReferences` slot pointer is a false alternative. `_IOReferenceClientTask`'s
one unidentified call — the `bl` at address 7076, which the Mach-O relocation table names
`_port_rename`, with `r3 = _IOTask_kern->itk_space`, `r4 = *clientReferenceSlot` and `r5` = the slot's
own address — *renames* the client's port to the address of its `_clientReferences` slot. From that
call onwards the slot's address **is** the port's name in the IOTask's IPC space, which is why
`_IODereferenceClientTask` can hand the same pointer straight to `_port_deallocate` as a name
(address 7276, with `r4` still holding the incoming pointer from the `mr r4, r3` at 7168), and why
`_IOConvertTaskPortToVMTask` passes the rewritten cell to `ipc_object_copyin_compat` as a `mach_port_t`.

### `_IORequestNotifyForClientTask` (address 8412, 480 bytes)

Three arguments, confirmed against our source's own extern declaration and call site
(`IOSCSISession.m:19`, `int IORequestNotifyForClientTask(mach_port_t task, mach_port_t notifyPort,
mach_port_t *deathPort);`, called at `IOSCSISession.m:282` as
`IORequestNotifyForClientTask(task, *(mach_port_t *)(session_struct+0xc), (mach_port_t
*)(session_struct+0x10))` — this call site's own arguments confirm the disassembly's reading below
field-for-field):

- param1 (`r3`, kept on the stack) — the `task` argument, a task port, passed unchanged into two Mach
  IPC "compat" calls described below.
- param2 (`r4`, saved in `r26`) — stored, unmodified, into the new `_notifClients[i]` entry's second
  field (offset `+4`, addresses 8704/8708) once registration succeeds. The reference itself is the
  evidence here: it stores param2 into the entry's offset `+4`, which `__io_task_notification`'s drain
  phase (above) and `_IOReleaseNotifyForFunc` both load as `msg_remote_port` — i.e. a **send-right port
  name used as the `msg_send` destination** — not merely "session identity" inferred from our own call
  site. Our call site passes `self` here (cast through `mach_port_t`); that our source happens to pass
  the same kind of value does not itself establish what the reference's field means — the direction of
  evidence runs from the reference's own use (a message destination) to a judgement about our source's
  divergence, not the other way around.
- param3 (`r5`, saved in `r29`) — an in/out `int **`, passed *as-is* to `_IOReferenceClientTask`
  (address 6908, already mapped; matches that function's own recovered `int
  **clientReferenceSlot` signature exactly), *dereferenced* to obtain the value stored into
  `_notifClients[i]`'s first field (offset `+0`), and finally overwritten with the forked notification
  thread's ID before returning. Our call site passes `(mach_port_t *)(session_struct+0x10)` — the
  "death port" field documented in the session-structure comment — so this parameter is, physically,
  the address of that field, even though the disassembly treats its pointee as a `_clientReferences`
  slot value, not literally a Mach port name.

Behaviour:
1. Scans `_notifClients[0..31]` for the first entry whose first field is `0` (empty). If all 32 are
   occupied, returns `-0x2BE` (-702) immediately.
2. Marks the found slot reserved (`stwx -1, ...`) and increments `_notifClientCnt` up front (so a
   concurrent scan will not reuse the same slot while this call is still in progress).
3. Calls the imported `_ipc_object_copyout_compat(_IOTask_kern->port_funcs, param1, 0x11,
   clientReferenceSlot)`. `0x11` (17) is `MACH_MSG_TYPE_MOVE_SEND`
   (`src/kernel-7/mach/message.h:275`, "Must hold send rights") — the copyout is moving a send right
   for `param1` (the task port) out of the caller's space. On failure, un-reserves the slot (`stwx 0`,
   address 8592-8596) and returns the error — **without decrementing `_notifClientCnt`** (see the
   leak noted below).
4. Calls `_IOReferenceClientTask(clientReferenceSlot)` (address 6908). On failure, calls the imported
   `_ipc_object_copyin_compat(port_funcs, *clientReferenceSlot, 6, 0, &param1-stack-copy)` (undoing
   step 3's copyout; `6` is `MSG_TYPE_PORT`, `src/kernel-7/mach/message.h:716`, matching
   `_IOConvertTaskPortToVMTask`'s own use of the same constant for the same
   `ipc_object_copyin_compat(space, name, msgt_name, dealloc, objectp)` call, defined at
   `src/kernel-7/ipc/ipc_object.c:963`), un-reserves the slot (8656-8672), and returns the error —
   again **without decrementing `_notifClientCnt`**.
5. On success, commits: stores `*clientReferenceSlot` into the entry's first field, stores `param2`
   (session) into the entry's second field.
6. Checks the global `_notifyThread`; if a notification thread is already running, skips straight to
   the success return (only one `__io_task_notification` thread ever runs, shared across every
   registered client).
7. Otherwise calls the imported `_IOForkThread(&__io_task_notification, 0)` and stores the result into
   `_notifyThread`. If the fork failed (result still `0`), unwinds everything: calls
   `_ipc_object_copyin_compat` again (the same release as step 4), calls `_IODereferenceClientTask`,
   writes `0` back through `clientReferenceSlot`, `bzero`s the entry, **decrements `_notifClientCnt`**
   (address 8820-8836 — this third failure path, unlike the two above, does clean up the count), and
   returns a distinct error code `-0x2BF` (-703).
8. On any success path, returns `0`.

**Finding: the two early failure paths leak `_notifClientCnt`.** Steps 3 and 4's failure returns
(addresses 8592 and 8656) un-reserve the slot they just claimed (`_notifClients[i][0] = 0`) but do
**not** decrement `_notifClientCnt`, even though step 2 (address 8548-8552) already incremented it
before either call ran. Only the third failure path (step 7, address 8820-8836) decrements. This is a
real bug in the reference itself — every `ipc_object_copyout_compat`/`IOReferenceClientTask` failure
permanently inflates `_notifClientCnt` by one relative to the number of live entries in
`_notifClients`, which `__io_task_notification`'s drain-phase loop and its own `_notifClientCnt != 0`
gating condition both trust as an accurate count.

**Resolved (Task 4): not reproduced.** The "reproduce Apple's own defects by default" advice this
paragraph used to give is superseded — the governing convention is
`docs/superpowers/plans/2026-07-25-kernel-pci-pcmcia-reconstruction.md:968`, "reproduce Apple's *form*,
not Apple's *defects*; where the reference is demonstrably buggy, keep our correct behaviour and record
it as `intentional-mismatch` with its evidence". A count that only ever grows pins the notification
thread alive with no clients left (its `_notifClientCnt != 0` tests at 7816-7824 and 7956-7968 never
fire) and mis-bounds both of its scans (7848-7856 and 8164-8172). `IOTask.m`'s
`IORequestNotifyForClientTask` therefore decrements `_notifClientCnt` on both early failure paths, with
the reasoning in a comment at each site; address 8412 is `intentional-mismatch` in the ledger carrying
the addresses above.

Both "type" constants passed to `_ipc_object_copyout_compat`/`_ipc_object_copyin_compat` are now named
above; the one remaining open question is the precise reason the same stack slot that held `param1` on
entry is reused as the *output* parameter of the `ipc_object_copyin_compat` cleanup calls (steps 4 and
7) rather than a fresh local — the disassembly is consistent with this being an ordinary "throwaway
output, never read again" pattern, but that is an inference, not a confirmed fact, and is out of scope
to resolve further since it depends on the internal semantics of an imported Mach kernel routine.

### `_serverThreadFunc` (address 2672, 276 bytes)

Single argument (`r3`, kept in `r31` for the whole function) — a session object, confirmed by its use
as the receiver of `objc_msgSend(session, free)` (selector resolved via the reference's own
`__OBJC,__message_refs`/`__OBJC,__meth_var_names` relocation chain, the same technique Task 5 used,
to the literal string `"free"`) at three different points in the function.

**`0x1400` is an option word, not a buffer size — the earlier pass had this backwards.** The function
allocates two stack buffers exactly `0x400` (1024) bytes apart (`r30` at `r1+0x850-0x818`, `r29` at
`r1+0x850-0x418`; `0x818 - 0x418 = 0x400`). The *first* buffer's `msg_size` field (offset `+4`) is set
to `0x400` at addresses 2720/2724 (`li r0, 0x400` / `stw r0, 4(r30)`) — that is the actual receive
buffer size. `0x1400` is loaded separately, into `r4`, as the third argument of the
`_msg_receive(requestBuffer, 0x1400, 0)` call at address 2732/2740 — the *option* word, exactly the
same argument position Critical finding 3 already reads as an option in `__io_task_notification`
(where the option is `0x100`), so the earlier description of `_serverThreadFunc` contradicted its own
reading of the sibling function. `0x1400 = RCV_LARGE (0x1000) | RCV_INTERRUPT (0x400)`
(`src/kernel-7/mach/message.h:765` and `:764`): receive into a buffer that may be reallocated if the
incoming message is larger than provided, and terminate the receive on a software interrupt. The
receive timeout argument is `0`.

Behaviour, corrected against the full disassembly (address 2672-2944):

1. Prologue (2672-2696) saves `r28`-`r31` and `lr`; allocates the `0x850`-byte frame described above.
   `r31` = session (entry `r3`); `r30` = &requestBuffer; `r29` = &replyBuffer; `r28` = the `"free"`
   selector reference.
2. Loop top (address 2716): stores the session pointer into `requestBuffer+0xC` (word index 3 — the
   same offset every MiG handler in our own source reads as `session = (id)request[3];`, e.g.
   `IOSCSISession.m:534` and every other handler between lines 526-892), sets `requestBuffer.msg_size =
   0x400`, then calls `_msg_receive(requestBuffer, 0x1400, 0)` as described above.
3. **On `_msg_receive` failure** (addresses 2752-2780): logs
   `"SS%d: Server Thread Receive Error(%d) - terminating\n"` via `IOLog`, then calls
   `objc_msgSend(session, free)`. `-[IOSCSISession free]` (already documented above, address 1732)
   calls `_IOExitThread()` whenever the session's `session_object_id` field is non-zero — true for a
   live per-session server thread — so this call does not return; the thread exits inside it. The
   disassembler still emits the following instructions (they are not physically removed), but they are
   unreachable in the ordinary case.
4. **On `_msg_receive` success** (address 2784, also the fallthrough after step 3's *unreachable*
   instructions): calls `_IOSCSISessionMig_server(requestBuffer, replyBuffer)` (address 13520, already
   `intentional-mismatch`).
5. **The `Mig_server` return-polarity is the opposite of what the earlier pass recorded.** At address
   2796/2800: `cmpwi cr1, r3, 0` / `bne cr1, loc_B2C` (2860) — **non-zero means the message was
   handled**, and branches to the reply-send path (step 7); the earlier description had this
   inverted. Falling through (`r3 == 0`, "not dispatched") goes to the notification-ID guard next.
6. **The notification-ID guard** (addresses 2804-2832), reached only when `Mig_server` returned `0`:
   reads `requestBuffer.msg_id` (offset `+0x14`, the same header field `__io_task_notification`'s
   drain phase writes) into `r9`, then `addi r0, r9, -0x41` / `cmplwi cr1, r0, 0xB` / `bgt cr1,
   loc_B2C` — i.e. `msg_id - 0x41 <=u 11`, the inclusive range `0x41`-`0x4C`. Outside that range,
   control falls through to the reply-send path (step 7) anyway. Inside the range: if `msg_id == 0x41`
   (`NOTIFY_PORT_DELETED`, `src/kernel-7/mach/notify.h:152-153`) or `msg_id == 0x45`
   (`NOTIFY_PORT_DESTROYED`, `notify.h:157`, `NOTIFY_FIRST + 5`), both converge on the same handling
   (address 2836-2856): zero the word at offset `+0x10` of the structure pointed to by `session+4` (the
   same anchor pointer the "Groundwork" note above documents), then `objc_msgSend(session, free)` —
   again ending the thread via `_IOExitThread()`, the same way step 3 does. Any other value in
   `0x41`-`0x4C` (neither `0x41` nor `0x45`) branches back to the loop top (address 2716) without
   replying at all — the message is silently ignored. These two constants are the same
   `NOTIFY_PORT_DELETED`/`NOTIFY_PORT_DESTROYED` notification IDs `__io_task_notification`'s drain
   phase sends (`0x41`); they are Mach kernel notification IDs about the death of a port this thread
   holds, not MiG message IDs, which is why they don't fit this project's `0x1092`-`0x10A3` demux
   range — that mismatch is exactly what earlier flagged them as unidentifiable.
7. **The reply half, entirely missing from the earlier pass** (address 2860-2908, `loc_B2C`), reached
   either because `Mig_server` returned non-zero (handled) or because `msg_id` fell outside the
   notification range: reads `replyBuffer.RetCode` (offset `0x1C`) and tests it against two MiG status
   constants before sending the reply. `RetCode == -0x131` (`MIG_NO_REPLY`) branches back to the loop
   top (2716) *without* sending any reply at all. Otherwise, `RetCode == -0x12F` (`MIG_BAD_ID`) is
   rewritten in place to `-0x2C6` before falling through. Either way (unless `MIG_NO_REPLY` looped
   away), the function calls `_msg_send(replyBuffer, 5, 0)` — option `5 = SEND_TIMEOUT (0x0001) |
   SEND_INTERRUPT (0x0004)` (`message.h:755`/`:758`), timeout `0`.
8. **On `_msg_send` success** (address 2908): branches back to the loop top (2716) for the next
   request.
9. **On `_msg_send` failure** (addresses 2912-2940): logs
   `"SS%d: Server Thread Send Error(%d) - terminating\n"` via `IOLog`, then
   `objc_msgSend(session, free)` — again ending the thread via `_IOExitThread()`, the same as step 3.
10. **The function has no epilogue and never executes a `blr`.** Its last instruction (address 2944) is
    `b loc_A9C` (2716), an unconditional branch back to the loop top — not a return. The only two ways
    this function's execution ever ends are the two `_IOExitThread()` calls inside `[session free]`
    (steps 3 and 6/9); the disassembler-visible instruction at 2944 is dead code reachable only if
    `[session free]` were somehow to return, which it does not for a live session.

This is, structurally, the per-session counterpart to `__io_task_notification` above: one is the
RPC-request server loop, the other is the death-notification listener loop, and
`_IORequestNotifyForClientTask` (above) is what forks the latter.

The two values (`0x41`/`0x45`) the earlier pass could not identify are now named — `NOTIFY_PORT_DELETED`
and `NOTIFY_PORT_DESTROYED` (`src/kernel-7/mach/notify.h:152-158`) — and the reply half, the
`Mig_server` polarity, the buffer-size/option-word confusion, and the no-return ending are all
corrected above.

### `_IOConvertTaskPortToVMTask` (address 7320, 160 bytes)

Single argument (`r3`) — a task port, saved to a stack slot (`saved_r3`) at entry. The function passes
*the address of that stack slot* to `_IOReferenceClientTask(&saved_r3)` (address 6908) — i.e. it
fabricates a throwaway `int *` slot for the call rather than reusing a persistent one, since it has no
`_clientReferences`-style slot of its own to offer. If that call fails (address 7356), returns `0`
immediately (address 7360-7364).

**The dereference call at the end uses the possibly-modified local copy, not the original `taskPort` —
this needs stating explicitly, since `_IOReferenceClientTask`'s own recovered signature (above) writes
back through its argument.** `_IOReferenceClientTask(int **clientReferenceSlot)` finds a free
`_clientReferences` slot and writes that slot's address back through `*clientReferenceSlot` whenever
the slot doesn't already point inside the table — true here, since `saved_r3` starts out holding a raw
task port name, not a `_clientReferences`-range pointer. So after this call, `saved_r3` no longer holds
the original `taskPort` value; it holds the found slot's address. Every later use of `saved_r3` in this
function — the `ipc_object_copyin_compat` call below (address 7380, `lwz r4,
0x50+saved_r3(r1)`) and the final `_IODereferenceClientTask` call (address 7428, `lwz r3,
0x50+saved_r3(r1)`) — reads this modified value, not the raw port. A reimplementer must reuse the
same stack cell `_IOReferenceClientTask` was given, not re-read the caller's original argument, to
reproduce this.

On success, calls the imported `_ipc_object_copyin_compat(_IOTask_kern->port_funcs, savedSlotValue, 6,
0, &outObject)` (address 7376-7396; `_IOTask_kern` confirmed by the relocation dump above — this call
site is one of the 23 that name `_IOTask_kern`, not one of the four that name `_IOTask`; `port_funcs`
at offset `0xA4` is the `ipc_space_t space` argument of `ipc_object_copyin_compat(ipc_space_t space,
mach_port_t name, mach_msg_type_name_t msgt_name, boolean_t dealloc, ipc_object_t *objectp)`,
`src/kernel-7/ipc/ipc_object.c:963`; `6` is `MSG_TYPE_PORT`, `message.h:716`).

**The failure-path gap the earlier pass flagged as untraced is three instructions, now confirmed
directly.** On `ipc_object_copyin_compat` failure (`bne cr1, loc_1D04` at address 7404), control jumps
straight to address 7428 — skipping the `convert_port_to_map`/save-into-`r31`/`ipc_port_release_send`
sequence at 7408-7424 entirely, so `r31` (the eventual return value) is still `0` from the function's
own initialization (address 7340). Address 7428 (`lwz r3, 0x50+saved_r3(r1)`) is also where the
success path falls through to after 7424, so both paths converge there: it reloads the (possibly
slot-rewritten) `saved_r3` value and calls `_IODereferenceClientTask(savedSlotValue)` unconditionally,
dropping the reference obtained earlier regardless of whether the copyin succeeded. If that dereference
call itself fails (address 7440 not taken), the function calls the imported `_vm_map_deallocate` on
whatever is in `r31` (`0` on the copyin-failure path, traced above; the real map on the success path)
and forces `r31 = 0` before returning. Otherwise it returns `r31` unchanged — `0` on the
copyin-failure path (there was never a map to return), or the `vm_map_t` obtained from
`_convert_port_to_map` on the full success path. The earlier "not traced in full detail" caveat for
this edge is withdrawn; the three-instruction gap above is the complete failure-path behaviour.

### `_IOTaskPortAllocate` (address 6588, 48 bytes)

Single argument (`r3`, moved to `r4`), a `mach_port_t *name` out-parameter. The entire body is one
call: `return port_allocate(_IOTask_kern->port_funcs, name);` — a direct tail call to the imported
`_port_allocate`, nothing else. This is a distinct, simpler sibling of the already-mapped
`_IOTaskPortAllocateName` (address 6460, Task 6): that function calls both `port_allocate` *and*
`port_rename`; this one only allocates and returns the raw result. Our source has no function at all
under this name — only `IOTaskPortAllocateName` exists.

### `_IODestroyMappedVMTask` (address 7576, 32 bytes) — the smallest of the six

Single argument (`r3`), passed through unchanged. The entire body is one call:
`return vm_map_deallocate(vmTask);` — a direct tail call to the imported `_vm_map_deallocate`, with no
other instructions.

## Naming findings (Task 8's territory)

**Finding: `-[IOSCSISession(Private) _initServerWithTask:sendPort:]` carries a spurious leading
underscore.**

**Source:** `IOSCSISession.h:79` (declaration) and `IOSCSISession.m:234` (implementation), both named
`_initServerWithTask:sendPort:` (leading underscore); the category, `(Private)`, is already correct.

**Reference behaviour:** the same string-table evidence the existing "Finding:
`-[SCSIServer serverConnect:taskPort:]` sends the wrong selector name to `IOSCSISession`" (SCSIServer.m
block, above) already established applies here too: the only string in the entire reference binary
containing `"initServerWith"` is `"initServerWithTask:sendPort:"`, with no underscore-prefixed variant
anywhere in the string table. Apple's selector is `initServerWithTask:sendPort:` — no leading
underscore.

**Consequence:** this is the exact same defect already recorded once (from the *caller's* side, in
`SCSIServer.m`) — this is the *declaration/definition* side, at address 1160 in the ledger (still
`unexamined`, out of Tasks 3-6's scope, deferred here). A leading-underscore selector is a distinct
selector to the Objective-C runtime, not a formatting variant; renaming it is exactly the class of fix
`SCSIServer Task 8: correct selector names` is scoped to make project-wide. Task 8 should rename this
method (declaration, implementation, and the `SCSIServer.m:309` call site already flagged) to
`initServerWithTask:sendPort:`, matching the reference and the `(Private)` category, which needs no
change.

**Finding: `-[IOSCSISession(Private) _reserveTarget:lun:]` has no counterpart in the reference at all.**

**Source:** `IOSCSISession.m:311-366` (comment and implementation of the ObjC method
`_reserveTarget:lun:`, declared at `IOSCSISession.m:326`).

**Reference behaviour:** `tools/binrecon/selector_check.py "$REF" "$SRC"` compares every selector our
source declares against every selector the reference's Objective-C metadata declares:

```
$ PYTHONPATH=tools/binrecon $PY tools/binrecon/selector_check.py "$REF" "$SRC"
reference selectors: 15
our definitions:     14

renames (1):
    -[IOSCSISession(Private) _initServerWithTask:sendPort:]    IOSCSISession.m:234

duplicates (0):

missing (2):
    +[SCSIServerKernelServerInstance kernelServerInstance]
    +[SCSIServerVersion driverKitVersionForSCSIServer]

extra (1):
    -[IOSCSISession(Private) _reserveTarget:lun:]
```
`_reserveTarget:lun:` is the tool's one `extra` entry: it exists in our source under no name the
reference declares, renamed or otherwise (contrast with `_initServerWithTask:sendPort:` above, which
the tool correctly identifies as a *rename* of a reference selector, not an addition). The two
`missing` entries are the build-generated classes this task already dispositions as
`intentional-mismatch` above, not naming defects.

Separately: this method's own body (`IOSCSISession.m:311-366`) does exactly what the already-mapped,
`assembly-matched` C function `IOSCSISession_reserveTarget` (address 3372, Task 5) does — same
controller lookup at session-structure offset `+8`, same `reserveTarget:lun:forOwner:` selector, same
conditional `addReservation` call — just re-expressed as an Objective-C method instead of a plain C
function, and (a minor, separate detail) without that C function's explicit `(int)(char)target`
sign-extension, so `target_val >> 0x1f` in the ObjC method is always `0` regardless of `target`'s high
bit, whereas the C function's equivalent shift can be `-1`. Neither `source-map.json` nor the
reference's own message-ref/selector metadata (checked directly, not merely absent from the tool's
`missing` list) shows this method corresponding to *anything* in the reference under *any* name.

**Disposition Task 8 should apply:** this is not a naming defect to correct — there is no reference
name to rename it *to*. Task 8 should leave this method's name alone but flag it to whoever owns Task
12 (fixing Phase 1 divergences) as unreachable, duplicate logic layered on top of the already-correct
`IOSCSISession_reserveTarget` C wrapper, worth removing rather than renaming.

## Finding: `IOSCSISession_initForDevice`'s wrapper prototype is one parameter short of what the recovered `.defs` requires (resolved)

**Source:** `IOSCSISession.h:130`, `int IOSCSISession_initForDevice(id session, const char *deviceName);`;
implementation at `IOSCSISession.m:429`.

**Reference behaviour:** `__XIOSCSISession_initForDevice`'s own message-type descriptor for `deviceName`
is `MSG_TYPE_CHAR` (8), not `MSG_TYPE_STRING_C` (12) — a masked, variable-length check identical in
shape to the `ioRanges` scatter arguments, not a `c_string`. The stub itself passes three arguments to
`_IOSCSISession_initForDevice`: `r3` (session), `r4` (`request+0x1C`, the pointer), and `r5` (a separate
byte count extracted from the descriptor's `msg_type_number` via `extrwi`). `IOSCSISessionMig.defs` now
declares `in deviceName : array[*:80] of char;` to match, which is MiG's standard variable-length-array
convention: the generated call adds an implicit `deviceNameCnt` (or similarly-named) count parameter
after the pointer, matching the stub's three-argument call exactly.

**Our source (as of the final whole-branch review fix pass):** `IOSCSISession_initForDevice(id session,
const char *deviceName, unsigned int deviceNameCnt)` — a third parameter, `deviceNameCnt`, was added to
both the header declaration and the definition, matching the count parameter MiG's generated
`IOSCSISessionMigServer.c` passes. This is a pure declaration/definition signature change with no new
body logic; `deviceNameCnt` is accepted but not yet read by the function body, consistent with the
byte-count validation this function does not otherwise perform.

**Consequence:** the compile-time arity mismatch between the MiG-generated caller (three arguments) and
this wrapper (previously two) is resolved. `IOSCSISessionMigServer.c` is still not checked into this
tree (it is MiG build output), so this remains structurally verified rather than compile-verified.

## Acceptance

Regenerated from the finished tree (Task 13). Nothing here is compile-verified — there
is no PowerPC compiler in this environment; every gate below proves structural
correspondence to the reference binary, not that the driver builds or runs.

### Regenerated source map

```
mapped                 41
unmapped               27
duplicate_candidates   0
boundary_disputed      0
```

**This does not match the 42 mapped / 26 unmapped this task's brief projected.** The
brief expected the 41 that mapped before this regeneration plus one — the renamed
`-[IOSCSISession initServerWithTask:sendPort:]` (address 1160) — for 42, with the 26
unmapped being the 2 build-generated classes, the 18 `__XIOSCSISession_*` MiG stubs, and
the 6 bodies Phase 2 deferred.

What actually happened: the rename *did* map, exactly as predicted. But
`_IOSCSISessionMig_server` (address 13520) — which the previously-committed, stale
`source-map.json` had matched to `IOSCSISession.m:411` — no longer maps after the source
changes made across Tasks 9-12. Line 411 of `IOSCSISession.m` is a blank line between two
unrelated C wrappers (`IOSCSISession_free` and `IOSCSISession_initForDevice`); it never
contained any part of a demux implementation. The old match was a matcher false positive,
not a real correspondence — the ledger already knew this (address 13520 has carried
`intentional-mismatch` since Task 9, with reason "our IOSCSISessionMig_server is
hand-written where Apple's is MiG output..."). `_IOSCSISessionMig_server` is, like the 18
stub bodies, MiG-generated build output belonging to `IOSCSISessionMigServer.c`, which
does not exist in this tree, so `source-map` correctly cannot find a source site for it
either. The rename's `+1` and the resolved false positive's `-1` cancel out: **41
mapped, 27 unmapped**, not 42/26.

The 27 unmapped break down as 2 build-generated classes + 18 MiG stub bodies + 6
Phase-2-deferred bodies + 1 MiG-generated demux (`_IOSCSISessionMig_server`) = 27. This
also supersedes spec §4.2 item 2's figure of 48/20 (itself already a correction of the
spec's original, unreachable 66/2): that figure assumed all six deferred bodies would be
written and did not anticipate the demux losing its spurious map entry, so 48/20 is not
met either, for the same reason 42/26 is not met. `duplicate_candidates` and
`boundary_disputed` are 0, as expected.

### Ledger reconciliation

The ledger was re-seeded fresh from the regenerated source map with `seed_ledger.py`
(68 entries, all `unexamined`), then every one of the 68 previously-recorded statuses was
replayed through `binrecon ledger`, one forward transition at a time (`unexamined` -to
`intentional-mismatch` by way of an intermediate `signature-confirmed`; `assembly-matched`
by way of `signature-confirmed` then `control-flow-confirmed`). Comparing the replayed
ledger against the statuses saved before re-seeding, **every entry landed on exactly the
status it held before** — no entry's evidence-supported disposition differs from what the
old ledger recorded. This was checked explicitly for the two entries whose source-map
membership changed (addresses 1160 and 13520): address 1160 was already
`signature-confirmed` (name-only check from Task 8, pending full instruction-level review)
and its underlying evidence is unaffected by now appearing in the `mapped` bucket; address
13520's `intentional-mismatch` disposition and reason already accounted for its status as
non-source-backed MiG output, so its move from `mapped` to `unmapped` changes nothing
about the correctness of that status.

Final ledger tally (68 entries):

| Status | Count |
| --- | --- |
| `assembly-matched` | 15 |
| `intentional-mismatch` | 21 |
| `signature-confirmed` | 1 |
| `unexamined` | 31 |
| **Total** | **68** |

**This does not meet spec §4.2 item 4** ("All 68 ledger entries carry a status, a reviewer and a
reason; none is `unexamined`"), for the same class of reason §4.2 item 2's 48/20 figure is not met
above: item 4 assumed the deferred-body and stub-dispatch work would be complete by acceptance time,
which it is not. Each of the 31 `unexamined` entries retains an unfixed divergence, not an oversight
— breaking down by `source_path`/`names` in the ledger itself:
- **6** have no source at all (`_serverThreadFunc`, `_IOTaskPortAllocate`,
  `_IOConvertTaskPortToVMTask`, `_IODestroyMappedVMTask`, `__io_task_notification`,
  `_IORequestNotifyForClientTask`) — the Phase-2-deferred bodies under "six functions our tree lacks
  entirely"; there is nothing yet for the ledger to examine.
- **12** are twelve of the eighteen C-callable dispatch wrappers (`IOSCSISession_releaseTarget`,
  `reserveSCSI3Target`, `releaseSCSI3Target`, `numberOfTargets`, `executeRequest`,
  `executeRequestOOLScatter`, `executeRequestScatter`, `executeSCSI3Request`,
  `executeSCSI3RequestOOLScatter`, `executeSCSI3RequestScatter`, `resetSCSIBus`,
  `returnFromScStatus`) — the "twelve of the eighteen wrapper functions never send the Objective-C
  message the reference sends" finding; real source exists, but the dispatch is still stubbed out.
- **7** are the `IOTask.m` plumbing functions (`IOTaskPortAllocateName`, `IOTaskPortDeallocate`,
  `IOTaskWireMemory`, `IOTaskUnwireMemory`, `IOReferenceClientTask`, `IODereferenceClientTask`,
  `IOReleaseNotifyForFunc`) — each has a real finding above; some are now partially resolved by this
  fix pass and earlier Task 12 commits (`IOTaskWireMemory`'s return type, the
  `IODereferenceClientTask` call-site argument), but the underlying stub bodies (missing Mach calls,
  `notifClientObjects` fabrication, etc.) remain, so the ledger status is correctly left
  `unexamined` rather than advanced.
- **1** is `-[IOSCSISession free]` (address 1732) — its own finding above.
- **5** are the `SCSIServer.m` findings (`probe:`, `initFromDeviceDescription:`,
  `registerSCSIController:`, `serverConnect:taskPort:`, `getCharValues:forParameter:count:`) — several
  of these were fixed by earlier Task 12 commits, but per this project's divergence convention
  (task-13-report.md), a fixed logging/argument difference does not by itself advance ledger status
  without a full re-examination pass, so these remain `unexamined` intentionally.

6 + 12 + 7 + 1 + 5 = 31. See "Phase 2 outcome" below for which of these findings this fix pass
resolved versus left open — this acceptance section's own numbers are Task 13's as regenerated, not
re-run by this pass.

### Gate results (Step 4)

**`selector_check.py`:**

```
reference selectors: 15
our definitions:     13

renames (0):

duplicates (0):

missing (2):
    +[SCSIServerKernelServerInstance kernelServerInstance]
    +[SCSIServerVersion driverKitVersionForSCSIServer]

extra (0):
exit=0
```

Matches expectation: `renames (0)`, `duplicates (0)`, `exit=0`. The 2 "missing" selectors
are the build-generated classes documented above under "Out of scope" — they are expected
to have no hand-written definition.

**Artifact validation** (`identify` + `load_ledger` + `load_source_map`):

```
artifacts validate
exit=0
```

**`ppc_invariant_check.py`:**

```
symbol +[SCSIServer deviceStyle] at 0x0 is not a function start
20 scattered/difference-form relocations (target section verified, field is a difference, not an address)
10 HI16/HA16-LO16 pairs checked (reconstructed values must agree)
998 fused relocations, 1 violations
exit=1
```

998 fused relocations with 0 relocation-decode violations, matching expectation. The
single reported violation is the known `+[SCSIServer deviceStyle]`
symbol-versus-function-start mismatch at address 0, documented above under "The analyzer
gap at address 0" — an IDA analyzer artifact (69 symbols vs. 68 function entries), not a
new or unexplained finding. `exit=1` is expected here because the checker's violation
count is nonzero only due to this single, already-documented, non-relocation case.

**`pytest tools/binrecon`:**

```
760 passed, 4 skipped in 75.47s
exit=0
```

All binrecon tooling tests pass; Task 1's tooling is not broken by this task's
regeneration.

## Phase 2 outcome

This section exists so a future fix pass has a work list without reading every commit body between
Task 7 and the final whole-branch review. Status is drawn from the actual commit history
(`git log -- src/drvSCSIServer`), the current source, and the ledger's `unexamined` list, not
reasserted from memory. "Resolved" means the specific defect the finding describes no longer matches
the current source; it does not mean the ledger status was advanced (see the §4.2 item 4 discussion
above for why several resolved findings still carry `unexamined`).

**Resolved:**

| Finding | Commit(s) |
| --- | --- |
| `_removeReservation` pointer-arithmetic bug when unlinking | `5c17f9cb` |
| `-[IOSCSISession free]`'s `IOTaskPortDeallocate` call and return value | `5b4d62ec` |
| Session-structure doc comment's swapped next/prev field order | `e853646a` |
| `-[IOSCSISession(Private) _reserveTarget:lun:]` unreachable duplicate method | `bc7c14da` (removed) |
| `IOSCSISession_initForDevice:result:`'s undeclared `IOSCSIControllerExported` protocol | `1c6886ea` (empty declaration), superseded by this fix pass importing `driverkit/scsiTypes.h`'s real protocol (Minor 10) |
| `-[SCSIServer serverConnect:taskPort:]`'s wrong (underscore-prefixed) selector name | `b2d798bd` |
| `-[SCSIServer initFromDeviceDescription:]` passing the wrong argument to `registerSCSIController:` | `c3a70903` (the logging-difference half of this finding is still open, see below) |
| The hand-written MiG dispatch table's wrong wiring order | moot — `5ac4f5c7` deleted the hand-rolled table and demux entirely, replacing it with the recovered `IOSCSISessionMig.defs` |
| The dispatch-table comment misreading a PIC displacement as a manual-placement address | moot for the same reason (the comment's subject no longer exists in source) |
| `IODereferenceClientTask` validating/decrementing against the wrong table (`notifClients` instead of `_clientReferences`) | `92384e9b` (bounds check and offset), `a495abfc` (one-past-the-end bound) — the `_port_deallocate` cleanup call inside it is still a stub, see below |
| `IOTaskWireMemory` declared `void` where the reference returns a status | `84fffeb1` (return-type only; the stub body itself is still open, see below) |
| The recovered `.defs`'s use of `unsigned`/`mach_port_t`, not part of this tree's MiG dialect | this fix pass (Critical 1) |
| `IOVMTaskPort` having no C `ctype` | this fix pass (Critical 2) |
| `IOSCSISession_initForDevice`'s two-parameter wrapper vs. the `.defs`'s three-argument call | this fix pass (Important 3) |
| `IOReleaseNotifyForFunc` passing `&notifClients[i*2]` (an address) instead of the value stored there to `IODereferenceClientTask` | this fix pass (Important 4) — the `notifClientObjects` fabrication in the same finding is still open, see below |

**Closed by SCSIServer Task 3** (see the disposition table at the top of this file for the
already-fixed and claim-wrong verdicts as well):

| Finding | How |
| --- | --- |
| `+[SCSIServer requiredProtocols]`'s wrong pointer indirection / static storage class | function-scope `static Protocol *protocols[] = { @protocol(IOSCSIControllerExported), nil }`; the fabricated `extern Protocol *objc_protocol_IOSCSIController` and its file-scope array are gone |
| `+[SCSIServer probe:]` logging where the reference has none | three `IOLog` calls removed |
| `-[SCSIServer initFromDeviceDescription:]` logging where the reference has none | `IOLog` removed |
| `-[SCSIServer registerSCSIController:]` logging where the reference has none | `IOLog` removed |
| `-[SCSIServer getCharValues:forParameter:count:]`'s extra bounds guard | kept; Apple's own `values[-1]` underflow write is `intentional-mismatch` at address 772, with the addresses in a comment |
| Our source calling `objc_getClass()` where the reference loads static `__cls_refs` | all five sites are now plain `[super ...]` / `[IOSCSISession alloc]`; see the correction on that finding |
| Twelve of the eighteen C-callable wrapper functions never send the Objective-C message the reference sends | all twelve dispatch now, each with the reference addresses and the `__OBJC,__message_refs` slot in a comment; the two `*Scatter` bodies clear the descriptor after the wire-failure `release` rather than reproduce Apple's use-after-release (`intentional-mismatch` at 4828 and 5760) |
| `IOSCSISession_returnFromScStatus` still declared `void`, discarding the reference's return value | `int` in `IOSCSISession.h:196` and `IOSCSISession.m`, returning the dispatched value |
| The OOL wrappers' "`vm_deallocate`" naming guess | `IOUnmapPhysicalFromIOTask`, resolved through the relocation at 4716/5648 |
| `-[IOSCSISession free]`'s cleanup "callback" | direct `IOExitThread()`; the `session_cleanup_callback_t` typedef and its extern are removed |

**Open (still needs a fix pass):**

| Finding | Why still open |
| --- | --- |
| `IOTaskPortAllocateName` never issuing its two Mach calls, still declared `void` | unchanged stub |
| `IOTaskPortDeallocate` never issuing its Mach call, still declared `void` | unchanged stub |
| `IOTaskUnwireMemory` never issuing its Mach call, still declared `void`, reads `_page_size` not `_page_mask` | unchanged stub (only its sibling `IOTaskWireMemory`'s return type was fixed) |
| `IOReferenceClientTask` never issuing its `port_rename` call | unchanged stub |
| `IODereferenceClientTask`'s stubbed `_port_deallocate` cleanup call | unchanged stub (only the bounds/offset/one-past-the-end parts were fixed) |
| `IOReleaseNotifyForFunc`'s fabricated `notifClientObjects` array and its match condition | unchanged (only the `IODereferenceClientTask` call-site argument was fixed, this pass) |
| Six functions our tree lacks entirely (`_serverThreadFunc`, `_IOTaskPortAllocate`, `_IOConvertTaskPortToVMTask`, `_IODestroyMappedVMTask`, `__io_task_notification`, `_IORequestNotifyForClientTask`) | no source exists yet; these are the Phase-2-deferred bodies |
| `-[IOSCSISession initServerWithTask:sendPort:]` calls `objc_msgSend(self, (SEL)0xa70)` where the reference calls `IOForkThread(&_serverThreadFunc, self)` | new in Task 3; blocked on `_serverThreadFunc`, so it belongs with the row above |
