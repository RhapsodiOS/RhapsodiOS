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
| 16 | `+[SCSIServer requiredProtocols]` | `assembly-matched` | trivial 5-instruction leaf, no divergence |
| 36 | `+[SCSIServer probe:]` | `unexamined` | Finding: extra IOLog calls |
| 228 | `-[SCSIServer initFromDeviceDescription:]` | `unexamined` | Finding: wrong registerSCSIController: argument; Finding: extra IOLog call |
| 480 | `-[SCSIServer registerSCSIController:]` | `unexamined` | Finding: extra IOLog call |
| 632 | `-[SCSIServer serverConnect:taskPort:]` | `unexamined` | Finding: wrong selector name |
| 772 | `-[SCSIServer getCharValues:forParameter:count:]` | `unexamined` | Finding: extra bounds guard absent from reference |

Only `requiredProtocols` (address 16) accounts for every reference instruction with no unexplained
difference. The other five each have at least one real, non-cosmetic divergence from the reference
disassembly, so per the ledger convention they stay `unexamined` rather than being marked
`control-flow-confirmed`; the findings below are for Task 12 to repair.

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
underflow write. Whether to reproduce the reference's underflow write or keep our guard is a Task 12
decision (compare `## Apple's own defects` conventions used by sibling reconstructions — reproduce
by default unless there's a reason not to). Left `unexamined`.
