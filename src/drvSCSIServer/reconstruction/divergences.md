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
| 16 | `+[SCSIServer requiredProtocols]` | `assembly-matched` (data divergence found; see Finding below — ledger CLI refuses the backward transition to `unexamined`) | trivial 5-instruction leaf, no divergence in the *code*; the *data* it returns diverges |
| 36 | `+[SCSIServer probe:]` | `unexamined` | Finding: extra IOLog calls |
| 228 | `-[SCSIServer initFromDeviceDescription:]` | `unexamined` | Finding: wrong registerSCSIController: argument; Finding: extra IOLog call; Finding: extra objc_getClass call |
| 480 | `-[SCSIServer registerSCSIController:]` | `unexamined` | Finding: extra IOLog call |
| 632 | `-[SCSIServer serverConnect:taskPort:]` | `unexamined` | Finding: wrong selector name; Finding: extra objc_getClass call |
| 772 | `-[SCSIServer getCharValues:forParameter:count:]` | `unexamined` | Finding: extra bounds guard absent from reference; Finding: extra objc_getClass call |

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
underflow write. Whether to reproduce the reference's underflow write or keep our guard is a Task 12
decision (compare `## Apple's own defects` conventions used by sibling reconstructions — reproduce
by default unless there's a reason not to). Left `unexamined`.

This function also calls `objc_getClass("IODevice")` where the reference loads a static reference
instead — see "Finding: our source calls `objc_getClass()` where the reference loads static
references" below.

## Finding: our source calls `objc_getClass()` where the reference loads static references

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
| 1732 | `-[IOSCSISession free]` | `unexamined` | Finding: missing `notify_port` argument to `IOTaskPortDeallocate()`; Finding: cleanup-callback mechanism diverges; addendum above: extra `objc_getClass("Object")` call |
| 2076 | `-[IOSCSISession name]` | `assembly-matched` | 4-instruction leaf; returns literal 0 |
| 2092 | `_findReservation` | `assembly-matched` | walks the circular list, matches the 0x18-byte element layout field-for-field |
| 2196 | `_addReservation` | `assembly-matched` | calls `findReservation` (confirmed by local symbol name) then `IOMalloc`, links the new entry with the same four steps and offsets as the source |
| 2388 | `_removeReservation` | `unexamined` | Finding: pointer-arithmetic bug corrupts the wrong field when unlinking |
| 2544 | `_blastAllReservations` | `assembly-matched` | `while` loop freeing 0x18-byte entries, correctly fixes up `next->prev` |

**The reservation structure.** All four reservation functions — in both the reference disassembly and
our source's own documented layout (`IOSCSISession.m:1160-1168`) — agree on a 24-byte (`0x18`)
element with offset `+0` = next, `+4` = prev (a circular doubly-linked list embedded in the session
structure: the list head is `*(session+4)` itself, not a separately-allocated sentinel node — the
list is empty exactly when `head->next == head`, with no `NULL` terminator anywhere), `+8`/`+0xC`
= target high/low, `+0x10`/`+0x14` = lun high/low. `_findReservation` (2092), `_addReservation`
(2196) and `_blastAllReservations` (2544) all read and write those exact offsets correctly and match
the reference instruction for instruction. There is **no** layout disagreement between our four
functions or against the reference — the one divergence in this group (`_removeReservation`) is a
C-level implementation bug within a single function, not a structural disagreement, so it is reported
as one finding below rather than a structure-wide one.

## Finding: `_removeReservation` corrupts the wrong field when unlinking an entry

**Source:** `IOSCSISession.m:1308` (`removeReservation`), specifically lines 1350-1352.

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

**Our source:**
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

**Consequence:** this is a real, non-cosmetic bug, not a register-allocation artifact: removing a
reservation (1) never updates the successor entry's actual `prev` pointer — it is left dangling,
pointing at the just-freed `current` node — and (2) clobbers the successor entry's `lun_high` field
with the (unrelated) `prev` pointer value, corrupting live reservation data for every entry still in
the list after the removed one. `_addReservation`'s own equivalent step
(`new_entry[1] = (int)last_entry;`, `IOSCSISession.m:1237`) and `blastAllReservations`' equivalent
step (`next[1] = list_head;`, `IOSCSISession.m:1283`) both use array-index notation and get the
scaling right; only `removeReservation` mixes in raw pointer arithmetic on a byte offset comment
without going through `(char *)` or index notation. Left `unexamined`; Task 12 should change
`*(int **)(next + 4) = prev;` to `next[1] = (int)prev;` (or `*(int **)((char *)next + 4) = prev;`).

## Finding: `-[IOSCSISession free]` omits an argument and diverges on its cleanup-callback mechanism

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
being declared and defined with a `mach_port_t port` parameter earlier in the very same file.

**Consequence:** a real divergence — the reference passes `notify_port` to the deallocation call;
our source's call site drops the argument entirely, so `IOTaskPortDeallocate`'s body (which reads its
`port` parameter) would receive whatever happened to be left in the argument register rather than the
intended port. Left `unexamined`; Task 12 should change the call to
`IOTaskPortDeallocate(notify_port);`.

**Reference behaviour, cleanup callback:** at addresses 1940-1948, the reference has exactly one test
before the cleanup call:
```
1940  cmpwi cr1, r30, 0     ; r30 = session_object_id
1944  beq cr1, loc_7A0      ; skip the call if session_object_id == 0
1948  bl sub_7BC            ; unconditional call, no argument registers set up beforehand
```
`sub_7BC` is a 16-byte jump island (`lis r12,0 / ori r12,r12,0 / mtctr r12 / bctr`, raw bytes
`3D800000 618C0000 7D8903A6 4E800420`) whose immediate halves are both literally zero in the object's
raw bytes — the same shape used by three of this function's other calls (`objc_msgSend`,
`objc_msgSendSuper`, `IOFree`, all of which are `UNDEF`-bound imports per the symbol table) rather
than the two islands elsewhere in this same function that resolve to real link-time addresses
(`_IOTaskPortDeallocate` at 2028, `_IOReleaseNotifyForFunc` at 2044, both `lis r12,name@h` / `ori
r12,r12,name@l` with genuinely non-zero low halves). This function's own jump islands prove the
codebase's convention for "load a value from a global variable" elsewhere (addresses 1912-1916, the
`objc_super.class` field: `lis r9, stru_5198.ext@ha` / `lwz r9, stru_5198.ext@l(r9)`) always uses
`lwz` — a memory load — which is absent from the `sub_7BC` call sequence entirely. This rules out the
call being a runtime dereference of a mutable global function-pointer variable; it is a single,
unconditional, compile/link-time-fixed call, gated by exactly one test.

**Our source:**
```c
if (session_object_id != 0) {
    if (_scsiSessionCleanupCallback != NULL) {
        _scsiSessionCleanupCallback();
    }
}
```
two nested tests — the `session_object_id != 0` test that matches the reference, and a second,
additional `NULL` check on `_scsiSessionCleanupCallback` (a global function-pointer variable) before
dereferencing and calling it.

**Consequence:** the reference performs one test and one fixed call; our source performs two tests
and models the target as a runtime-checked, re-loadable function pointer. Functionally the two are
equivalent whenever `_scsiSessionCleanupCallback` is never actually reassigned away from a valid
non-`NULL` value at runtime, so this may be low-severity in practice, but it is not what the
instructions show, and — honestly — **I could not identify what `sub_7BC` actually targets**: it is
not among the reference's 34 named imports, not a local symbol the exporter could resolve, and (per
the missing-relocation check above) is not covered by any relocation entry in this export either, so
its ultimate target is unresolved by the available tooling, not just by this review. Left
`unexamined`; Task 12 should confirm the intended callback semantics against a from-scratch review of
this call site (ideally with a tool that can resolve the raw `SCSIServer_reloc` external-relocation
table directly) before deciding whether to keep the `NULL`-checked global-pointer model or replace it
with a single fixed call.
