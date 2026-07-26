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
| 1732 | `-[IOSCSISession free]` | `unexamined` | Finding: missing `notify_port` argument to `IOTaskPortDeallocate()` (a compile error given the header declaration); Finding: cleanup call resolves to `IOExitThread()`, not a callback; Finding: returns `self` where the reference returns `nil`; addendum above: extra `objc_getClass("Object")` call |
| 2076 | `-[IOSCSISession name]` | `assembly-matched` | 4-instruction leaf; returns literal 0 |
| 2092 | `_findReservation` | `assembly-matched` | walks the circular list, matches the 0x18-byte element layout field-for-field |
| 2196 | `_addReservation` | `assembly-matched` | calls `findReservation` (confirmed by local symbol name) then `IOMalloc`, links the new entry with the same four steps and offsets as the source |
| 2388 | `_removeReservation` | `unexamined` | Finding: pointer-arithmetic bug corrupts the wrong field when unlinking |
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
| 4828 | `_IOSCSISession_executeRequestScatter` | `unexamined` | Finding: dispatch stubbed out (IOMemoryDescriptor alloc/init/wire/unwire/release and controller execute calls all commented out) |
| 5220 | `_IOSCSISession_executeSCSI3Request` | `unexamined` | Finding: dispatch stubbed out (mirrors 4288 with SCSI-3 offsets) |
| 5476 | `_IOSCSISession_executeSCSI3RequestOOLScatter` | `unexamined` | Finding: dispatch stubbed out; Finding: `IOTaskWireMemory` return-type mismatch |
| 5760 | `_IOSCSISession_executeSCSI3RequestScatter` | `unexamined` | Finding: dispatch stubbed out (mirrors 4828 with SCSI-3 offsets) |
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

**Source:** `IOSCSISession.m:1086` (`_IOSCSISession_initForDevice`), which calls `objc_msgSend(conformsTo:, @protocol(IOSCSIControllerExported))`.

**Reference behaviour:** the dispatch at address 3028 loads a protocol pointer from `__OBJC,__protocol` and passes it as the argument to `conformsTo:`. The reference binary's `__OBJC,__protocol` section (base 21424) contains two 20-byte `Protocol` struct records. The first, at offset 0, describes the `IOSCSIController` protocol (matching the finding in Task 3's `requiredProtocols` analysis). The second, at offset 20, contains a `protocol_name` field that reads exactly `"IOSCSIControllerExported"` — the name the reference passes to the conformance check.

**Our source:** declares and uses `@protocol(IOSCSIControllerExported)` at `IOSCSISession.m:1086` but does not declare the protocol itself anywhere in the source tree. The only protocol declaration in `IOSCSISession.h` is `@protocol IOSCSIController` (line 19), a different name. Similarly, `SCSIServer.m:21` declares `extern Protocol *objc_protocol_IOSCSIController;` to reference the compiled protocol struct by its mangled name, but there is no declaration of `objc_protocol_IOSCSIControllerExported`.

**Consequence:** on a PPC rebuild, `@protocol(IOSCSIControllerExported)` expands to a reference to an identifier that does not exist in any scope — the symbol table will have no `_objc_protocol_IOSCSIControllerExported` or equivalent to link to. This is a **compile error**, not a runtime mismatch: the preprocessor or compiler must resolve `@protocol(X)` to a symbol-table entry at build time. The reference clearly uses `IOSCSIControllerExported` (not `IOSCSIController`), so the fix is to declare `extern Protocol *objc_protocol_IOSCSIControllerExported;` to reference the compiled protocol struct — the same pattern used for `objc_protocol_IOSCSIController` in `SCSIServer.m:21`. This belongs in the same category as the two type errors already recorded (missing `notify_port` argument, `void`/`int` mismatch) — it is not merely a naming divergence but a compile error. Left `unexamined`; Task 12 should add a declaration like `extern Protocol *objc_protocol_IOSCSIControllerExported;` to `IOSCSISession.m`, matching the reference's compiled protocol, and review the source to ensure `IOSCSIControllerExported` is the protocol Apple intended to test (not `IOSCSIController`).

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
  client, &ioRange, 8, result);` (`IOSCSISession.m:2207-2208`) and the SCSI-3 equivalent
  (`IOSCSISession.m:1918-1919`) reproduce this delegation exactly, including the constant `8`.
- `executeRequestOOLScatter`/`executeSCSI3RequestOOLScatter` both wire the out-of-line buffer, then
  forward the OOL address and length as the `ioRanges`/`rangeCount` arguments to the matching
  `*Scatter` function (not `*Request`), then unwire. In the reference, `executeRequestOOLScatter`'s
  (4544) second `bl` resolves (relocation addend 4828) to `_IOSCSISession_executeRequestScatter`'s own
  entry, with the call-site argument registers matching `executeRequestScatter`'s parameter assignment
  the same way as above; `executeSCSI3RequestOOLScatter` (5476) resolves its second `bl` (relocation
  addend 5760) to `_IOSCSISession_executeSCSI3RequestScatter`'s entry the same way. Our source's
  `IOSCSISession_executeRequestScatter(session, request, client, oolData, oolDataSize, result)`
  (`IOSCSISession.m:2386-2387`) and the SCSI-3 equivalent (`IOSCSISession.m:2092-2093`) match.
- No in-line/out-of-line mix-up exists anywhere in the set: the legacy trio consistently uses offsets
  `+0x14` (buffer)/`+0x10` (direction)/`+0x20` (status) and the SCSI-3 trio consistently uses
  `+0x24`/`+0x20`/`+0x30`, in both the reference disassembly and our source's comments and field
  accesses, and neither track ever borrows the other's offsets or delegates to the other track's
  `*Scatter` function.
- The one thing this reading surfaced that is **not** a mix-up but is still worth recording: all six
  functions share the same "dispatch stubbed out" defect below, so the delegation structure above is
  the only part of these six functions the reference and our source currently have in common.

## Finding: twelve of the eighteen wrapper functions never send the Objective-C message the reference sends

**Source:** `IOSCSISession.m:2582` (`releaseTarget`, line 2615-2618), `:2522` (`reserveSCSI3Target`,
line 2545-2549), `:2456` (`releaseSCSI3Target`, line 2485-2488), `:2416` (`numberOfTargets`, line
2424-2427), `:2141` (`executeRequest`, line 2185-2190), `:2239` (`executeRequestScatter`, lines
2262-2328 throughout), `:2357` (`executeRequestOOLScatter`, via its call into the stubbed
`executeRequestScatter`), `:1852` (`executeSCSI3Request`, line 1895-1899), `:1947`
(`executeSCSI3RequestScatter`, lines 1970-2036 throughout), `:2063` (`executeSCSI3RequestOOLScatter`,
via its call into the stubbed `executeSCSI3RequestScatter`), `:1808` (`resetSCSIBus`, lines 1816-1819),
`:1790` (`returnFromScStatus`, lines 1797-1799).

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

## Finding: `executeRequestOOLScatter` and `executeSCSI3RequestOOLScatter` assign the result of a `void`-declared function to an `int`

**Source:** `IOSCSISession.m:142` declares `void IOTaskWireMemory(unsigned int address, int length);`;
the call sites at `IOSCSISession.m:2371` (`executeRequestOOLScatter`) and `:2077`
(`executeSCSI3RequestOOLScatter`) both write `wire_result = IOTaskWireMemory((unsigned int)oolData,
oolDataSize);` and then branch on `if (wire_result != 0)`.

**Reference behaviour:** in both OOL wrappers, the first `bl` (address 4624 in
`executeRequestOOLScatter`, resolving via relocation addend to address 6716; address 5556 in
`executeSCSI3RequestOOLScatter`, resolving to the same address 6716 — a single shared helper used by
both) is followed immediately by `cmpwi cr1, r3, 0` / `beq cr1, ...`, i.e. the reference treats this
call's `r3` return value as meaningful and branches on it. A `void` function has no defined return
value to branch on; the reference's own behaviour requires this helper to return an `int`.

**Our source:** declares the callee `void` (`IOSCSISession.m:142`) while simultaneously using it as
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
declaration is header-wide, so every other caller of `IOTaskWireMemory` would need the same fix). Left
`unexamined` for both addresses (4544, 5476); Task 12 should change `IOSCSISession.m:142`'s declaration
to return `int`, matching the reference's own use of the call's result.

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
| 13520 | `_IOSCSISessionMig_server` | `intentional-mismatch` | hand-written demux stands in for MiG output pending Task 9 (`IOSCSISessionMig.defs`); ID range (0x1092-0x10a3) and reply-header convention match, but the dispatch table is wired wrong on all 18 entries — see the ledger's own `--reason` text for this entry, which is the durable record per this task's tooling constraints |

**Groundwork: the `__SCSIServer_deviceStyle_` loads are all `_entry`, not a class method.** All
seven plumbing functions load a pointer via `lis`/`lwz __SCSIServer_deviceStyle_@ha`/`@l` in the
named export. This is the same "analyzer gap at address 0" artifact described above: the exporter's
disassembly view falls back to the nearest preceding *symbol table* name
(`+[SCSIServer deviceStyle]`, address 0) whenever a load has no local symbol of its own, because IDA
emits no function entry at address 0 to attach the name to correctly. `read_macho`'s relocation
table resolves every one of these loads to the actual external symbol `_IOTask_kern`, in every one
of the seven functions — confirming these are all reads of the `_entry` structure our source
declares at `IOSCSISession.m:15-31`, and that the offsets read from it (`0xA4` = `port_funcs`,
loaded in all seven; `0x18` = `task_port`, loaded in `IOTaskWireMemory`/`IOTaskUnwireMemory`) match
our source's own documented field layout exactly. This is not a divergence — it is why the raw
disassembly looks like it is loading a class method instead of a data pointer, and it is recorded so
a future reader doesn't need to re-derive it.

## Finding: `_IOTaskPortAllocateName` never issues its own two Mach calls, and is declared `void` where the reference returns a status

**Source:** `IOSCSISession.m:1760-1779` (`IOTaskPortAllocateName`), declared `void` at both
`IOSCSISession.h:158` and `IOSCSISession.m:1760`.

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
Separately, the `void` return type is wrong independent of the stub: `IOSCSISession.m:270` already
calls `result = IOTaskPortAllocateName(self);`, assigning a `void` expression to `result` — a second,
independent compile error at that call site (which also passes `self`, an `id`, where the reference
expects a `mach_port_t name`; that call site is outside this task's eight addresses and is left for
whichever task disposes it). Left `unexamined`; Task 12 should wire up the two calls named in the
existing comments and change the declaration in both the header and definition to return `int`
(propagating the last kernel call's result), matching the reference and the caller's existing use of
the return value.

## Finding: `_IOTaskPortDeallocate` never issues its own Mach call, and is declared `void` where the reference returns a status

**Source:** `IOSCSISession.m:1744-1754` (`IOTaskPortDeallocate`), declared `void` at both
`IOSCSISession.h:153` and `IOSCSISession.m:1744`.

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

## Finding: `_IOTaskWireMemory` and `_IOTaskUnwireMemory` never issue their shared Mach call, are declared `void` where the reference returns a status, and read the wrong mask symbol

**Source:** `IOSCSISession.m:1691-1709` (`IOTaskWireMemory`) and `:1716-1734` (`IOTaskUnwireMemory`),
both declared `void` (`IOSCSISession.h:142`/`:148`), and both computing
`~(_page_size - 1)` against `extern unsigned int _page_size;` (`IOSCSISession.m:34`).

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
cover. Left `unexamined` for both addresses; Task 12 should wire up the shared `vm_map_pageable`
call, change both declarations to return `int` (the existing `executeRequestOOLScatter` finding
already calls for this), and read `_page_mask` directly rather than declaring and computing from a
separate `_page_size`.

## Finding: `_IOReferenceClientTask` never issues its own Mach call, and its sole parameter is a slot handle into `_clientReferences`, not a bare decompiler pointer

**Source:** `IOSCSISession.m:1590-1676`, declared `int IOReferenceClientTask(int **param_1)`.

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

**Source:** `IOSCSISession.m:1519-1563`, declared `int IODereferenceClientTask(int *clientEntry)`.

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

## Finding: `_IOReleaseNotifyForFunc` invents a parallel object array the reference does not have

**Source:** `IOSCSISession.m:1464-1466` (declares `notifClients[64]`, `notifClientObjects[32]` and
`notifClientCnt`) and `:1479-1507` (`IOReleaseNotifyForFunc`, specifically lines 1494-1495 and 1498).

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

**Our source:** declares a second, separate array `static id notifClientObjects[32];`
(`IOSCSISession.m:1465`) and checks `notifClientObjects[i] == session` (line 1495) instead of a second
field of the same entry, then calls `IODereferenceClientTask(&notifClients[i * 2])` (line 1498) —
passing the *address* of the entry, not the *value stored at* the entry's first field.

**Consequence:** two compounding, real divergences. First, `notifClientObjects` does not exist in the
reference's data layout at all — it is invented storage with no backing global, so the match test at
line 1495 can never agree with the reference's own (`notifClients[i*2+1] == session`, not
`notifClientObjects[i] == session`). Second, the argument passed to `IODereferenceClientTask` is
wrong in exactly the way the finding above predicts: the reference passes the *value* stored in
`notifClients[i*2]` (a `_clientReferences` slot pointer, per the `IOReferenceClientTask` finding
above) while our source passes `&notifClients[i*2]` (the notifClients entry's own address) — neither
of which is a `_clientReferences`-range pointer, which is exactly why `IODereferenceClientTask`'s
bounds check (against `notifClients`, not `_clientReferences`) had to be wrong for our source's own
call site to ever pass it. All three functions' defects in this section trace back to the same root
cause: our source's local reimplementation of the client-reference/notification bookkeeping does not
carry the `_clientReferences`-slot-pointer design all the way through. Left `unexamined`; Task 12
should remove `notifClientObjects`, store the session pointer at `notifClients[i*2+1]` instead, and
change the `IODereferenceClientTask` call to pass `notifClients[i*2]` (the stored slot pointer), not
its address.
