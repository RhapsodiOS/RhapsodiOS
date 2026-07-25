# drvPCMCIABus divergences

Reference: `PCMCIABus_reloc`, SHA-256 `B0D8A35E4C55DD7DF2F77B7F8BC07A453D843C24814B874C47B737B3425607ED`
Analyses: IDA 9.2, Ghidra 12.1, angr 9.3.0

## Baseline build

The driver builds clean today. Artifact: `out/i386/drvPCMCIABus/PCMCIABus.config/PCMCIABus_reloc`,
size 344196 bytes (verified present on disk). This is larger than the reference's
92192 bytes because our build is unstripped; that size difference is expected and is
not a finding. This contradicts `src/drivers-i386/README`, which still says
drvPCMCIABus "needs compiled and then tested" — the driver in fact compiles and
produces a valid, symbol-matching Mach-O object today. The README was not edited as
part of this pass.

## Summary

| Bucket | Count |
| --- | --- |
| mapped | 53 |
| unmapped | 31 |
| duplicate_candidates | 0 |
| boundary_disputed | 0 |

Of the 84 total reference functions, roughly 35 were examined at instruction level
(full disassembly read side-by-side with source, including every function in the
naming-divergence group below plus the hardware-facing helpers called out as
priority), about 18 more were examined at control-flow level (IDA/Ghidra block and
call-count agreement checked, source read and compared structurally, but not every
instruction verified), and 9 large private `PCMCIAKernBus` methods — see
"Deprioritized" below — were not examined at all beyond confirming they exist and
build, because of their size and the time budget for this pass. Nine functions carry
a confirmed divergence and are documented as Findings below; they remain
`unexamined` in the ledger per the convention established by the drvPCIBus pass,
where a diverging function is left `unexamined` and written up instead of marked
with a weaker positive status.

## Naming divergence: confirmed, and mostly (not entirely) cosmetic

The major finding handed into this pass — that 22 of the 31 unmapped entries are
naming divergence, not missing code — is confirmed independently. Reading our built
binary's own symbol table (`out/i386/drvPCMCIABus/PCMCIABus.config/PCMCIABus_reloc`,
via `binrecon.macho.read_macho`) shows:

- 9 C functions carry an extra leading underscore in our source's compiled symbol:
  `__addString`, `__addStrings`, `__freeString`, `__sanitizeStringCopy`,
  `__parse_VERS_1`, `__parse_MANFID`, `__parse_CONFIG`, `__parse_CFTABLE_ENTRY`,
  `__parse_FUNCID` — Apple's source declares these without the doubled underscore
  (`addString` etc., which the compiler renders as `_addString` in the symbol
  table); ours declares `_addString` etc., which the compiler renders as
  `__addString`.
- 13 Objective-C methods belong to a class our binary names `PCMCIAPool` /
  `PCMCIAPoolElement`; the reference names them `_PCMCIAPool` / `_PCMCIAPoolElement`
  (confirmed via the IDA function-name list, e.g. `-[_PCMCIAPool init]` at
  0x49A4/18852).

A third instance of the same pattern, not called out in the original 22-count, turned
up while resolving the two `(Parsing)`-category entries below: our source's
`-[PCMCIAKernBus(Parsing) _allocResourcesForDescription:fromTupleList:]` and
`-[PCMCIAKernBus(Parsing) _parseTuple:intoDeviceDescription:]` carry a leading
underscore on the **selector itself**, which the reference does not
(`sel_allocResourcesForDescription:fromTupleList:` and
`sel_parseTuple:intoDeviceDescription:` in the reference's `__meth_var_names`,
confirmed with no underscore). The reference's Mach-O symbol table does carry the
`(Parsing)` category (`.objc_category_name_PCMCIAKernBus_Parsing` at 0xE0C0/57536)
matching our own category grouping — IDA's function-name list simply drops the
category name when reporting `-[PCMCIAKernBus allocResourcesForDescription:...]`,
which is why the source map's automatic matcher couldn't line these two up. Once the
category and the extra underscore are accounted for, these two are the same
functions.

**Whether the bodies are equivalent is mixed.** Checking each of the 24 functions in
this combined group (9 C functions + 13 Pool/PoolElement methods + 2 Parsing-category
methods) against the reference disassembly:

- 15 match exactly at the instruction level: `_freeString`, `_addString`,
  `_addStrings`, `_sanitizeStringCopy`, `_parse_CFTABLE_ENTRY` (control-flow level —
  see below), `-[PCMCIAKernBus(Parsing) allocResourcesForDescription:fromTupleList:]`,
  `-[PCMCIAKernBus(Parsing) parseTuple:intoDeviceDescription:]`, `-[_PCMCIAPool init]`,
  `-[_PCMCIAPool free]`, `-[_PCMCIAPool removeObject:]`, `-[_PCMCIAPool allocElement]`,
  `-[_PCMCIAPool releaseObject:]`, `-[_PCMCIAPoolElement initWithPCMCIAPool:object:]`,
  `-[_PCMCIAPoolElement free]`, `-[_PCMCIAPoolElement object]`.
- 9 carry a real, confirmed body divergence beyond the name: `_parse_VERS_1`,
  `_parse_CONFIG`, `_parse_MANFID`, `_parse_FUNCID` (Finding 2), `-[_PCMCIAPool
  addObject:]`, `-[_PCMCIAPool addList:]`, `-[_PCMCIAPool allocObjectByMethod:]`,
  `-[_PCMCIAPool allocElementByMethod:]` (Finding 3), and `-[_PCMCIAPool allocObject]`
  (Finding 4).

So: the naming divergence itself is purely cosmetic (a compiler-visible artifact of
how the identifiers were spelled in our source vs. Apple's), but it is not evidence
that the bodies underneath are equivalent — roughly a third of them are not, for
reasons unrelated to naming.

## Unmapped: build-generated

`+[PCMCIABusKernelServerInstance kernelServerInstance]` and
`+[PCMCIABusVersion driverKitVersionForPCMCIABus]` — emitted by the Kernel Server
project type, not written by hand. Accepted, same as the equivalent pair in
drvPCIBus. Ghidra has no function at `kernelServerInstance`'s address (0x51F0/20984);
IDA and our own binary both show a normal 12-byte function there, so this is the
same kind of single-function analyzer detection gap seen elsewhere (see below), not
a body disagreement — noted here rather than as a separate section since there is
only the one instance in this group.

## Unmapped: genuinely absent from our source

Five reference functions are called by our source (via `extern` forward
declarations) but never defined anywhere in this project:

- `_stringForFunctionID` — declared `extern` in `PCMCIAid.m:369`, called at
  `PCMCIAid.m:379`.
- `_configTableLookupServerAttribute` — declared `extern` in `PCMCIAKernBus.m:64`
  with signature `(const char *busName, int busId, const char *attribute)`, called
  three times in `+[PCMCIAKernBus probe:]`. Note drvEISABus defines its own function
  with the same name but a *different*, two-argument signature
  (`EISAKernBus.m:473`, `(const char *serverName, const char *attribute)`) — the two
  drivers each expect a private helper of this name, not a shared kernel export, so
  drvEISABus's copy cannot satisfy drvPCMCIABus's caller even if the two were linked
  together.
- `_parsePrefix`, `_parsenum`, `_LookForPCMCIAID` — declared `extern` in
  `PCMCIAResourceDriver.m:90-92`, called from
  `-[PCMCIAResourceDriver getCharValues:forParameter:count:]`.

This was verified two ways. First, `grep` across the whole `drvPCMCIABus` source
tree finds only the `extern` declarations and call sites for all five names, never a
definition. Second, reading our built binary's own symbol table shows all five as
**undefined external symbols** (`binding: external, section: None`, i.e. present in
the relocation table with no code behind them):
`__LookForPCMCIAID`, `__parsePrefix`, `__parsenum`, `__stringForFunctionID`,
`_configTableLookupServerAttribute` (the first four carry the same extra-underscore
pattern as the naming-divergence group above; the fifth does not, because
`configTableLookupServerAttribute` was declared without underscore in our source to
begin with). The reference binary, by contrast, has real 74-341 byte function bodies
at these five addresses (per the source map's `unmapped` list), meaning Apple's
driver was self-contained here and ours is not — this is a genuine implementation
gap, not a naming issue. See Finding 1.

The task brief also asked whether `_parseIDTable` and `_parseTable` are still
genuinely absent, per an earlier pass's finding. That still holds for
`_parseIDTable` (no trace anywhere in `drvPCMCIABus`). `_parseTable`, however, is not
a *function* in the reference binary at all — it is a `mov ebx, offset _parseTable`
data reference inside `-[PCMCIAKernBus(Parsing) parseTuple:intoDeviceDescription:]`,
pointing at the `{code, handler}` dispatch table that our source implements as the
local static array `tupleParserTable` (`PCMCIAKernBusParsing.m:111`). Since it is
data, not code, it was never a candidate for the function source map or this
ledger; the two dispatch tables have equivalent shape and contents (confirmed via
the `parseTuple:intoDeviceDescription:` disassembly matching our loop over
`tupleParserTable`), just different static names, which is not tracked by this pass.

## Analyzer disagreement: two single-function Ghidra detection gaps

Ghidra's function list has no entry at `-[_PCMCIAPool init]` (0x49A4/18852, 137
bytes) or at `+[PCMCIABusKernelServerInstance kernelServerInstance]`
(0x51F0/20984, 12 bytes). IDA reports normal functions at both addresses matching
the Mach-O symbol table, and the immediately surrounding functions agree between the
two analyzers, so these are Ghidra detection gaps for two individual functions
rather than body disagreements — the same pattern documented for `test_M1` in the
drvPCIBus pass. Per the brief, IDA is authoritative for the partition; noted here
rather than affecting the source map or ledger.

## Finding 1: five functions genuinely missing from our source (severe — driver cannot load)

**Source:** none — `_stringForFunctionID`, `_configTableLookupServerAttribute`,
`_parsePrefix`, `_parsenum`, `_LookForPCMCIAID` are declared `extern` and called but
never defined anywhere in `drvPCMCIABus`.

**Difference:** the reference binary contains real, self-contained implementations
of all five (74, 341, 75, 58 and 151 bytes respectively). Our build produces a
Mach-O object with these five as unresolved external symbols. Given this is an
`MH_PRELOAD` object (a kernel-loadable driver, not a normal linked executable), the
object file itself can still be produced — which is consistent with the task's
"builds clean" baseline — but nothing in this codebase, nor in drvEISABus's
differently-signed `configTableLookupServerAttribute`, supplies these five symbols
at driver-load time.

**Disposition:** fix

**Rationale:** unlike the accepted cosmetic naming divergence, this is a real
functional gap. `getCharValues:forParameter:count:` (the driver's primary
config-string query entry point — used for `IDs(`, `...IDs(`, and
`LocationForInstance(` parameters) is unreachable for any of its three real
parameter prefixes without `_parsePrefix`/`_parsenum`/`_LookForPCMCIAID`, and
`+probe:` cannot read per-socket `Verbose`/`PCMCIA Memory Base`/`PCMCIA Memory
Length` config attributes without `_configTableLookupServerAttribute`. Reproducing
these five bodies (all present, small, and fully disassembled in the reference) is
follow-up implementation work, not something this analysis pass does, but it is the
single highest-priority gap found.

## Finding 2: four tuple parsers add verbose-gated logging the reference never had

**Source:** `_parse_VERS_1` (`PCMCIAKernBusParsing.m:124`), `_parse_CONFIG`
(`:244`), `_parse_MANFID` (`:667`), `_parse_FUNCID` (`:699`).

**Reference behaviour:** none of the four ever tests the `verbose` argument
(`arg_0`). Full instruction dumps of all four show no comparison against `arg_0` and
no call to `_IOLog` anywhere in their bodies — confirmed by call lists containing
only `_addStrings`/`_addString`/`_objc_msgSend`/`_sprintf`, never `_IOLog`.

**Our source:** all four wrap several `IOLog(...)` calls in `if (verbose) { ... }`
blocks (e.g. `_parse_VERS_1` logs the major/minor version and the manufacturer,
product and two additional-info strings; `_parse_CONFIG` logs the tuple name,
register base address and mask presence; `_parse_MANFID`/`_parse_FUNCID` log their
tuple name and parsed value).

By contrast, the fifth parser in the same dispatch table, `_parse_CFTABLE_ENTRY`
(`PCMCIAKernBusParsing.m:299`), genuinely does check `verbose` in the reference —
its first instructions are `mov cl, [ebp+arg_0]; cmp cl, 1; jnz ...` gating the
first of ~30 `_IOLog` calls — so the reference's tuple-parser verbose behaviour is
parser-specific, not uniformly absent.

**Disposition:** accept

**Rationale:** `verbose` is otherwise unused in these four reference functions —
extra logging when the caller has turned verbose mode on doesn't change any
returned value, ivar, or control flow, only console output. Noted because it is a
real, confirmed difference across four functions, not a hypothetical one.

## Finding 3: `_PCMCIAPool` add/alloc-by-method paths drop a NULL/nil guard

**Source:** `-[_PCMCIAPool addObject:]` (`PCMCIAPool.m:89`), `-[_PCMCIAPool
addList:]` (`:77`), `-[_PCMCIAPool allocObjectByMethod:]` (`:182`), `-[_PCMCIAPool
allocElementByMethod:]` (`:117`).

**Reference behaviour:** none of the four check anything before doing their real
work. `addObject:`/`addList:` go straight into
`[poolData->elementList addObject:/appendList:]` with no test of `_poolData` or the
incoming object/list. `allocObjectByMethod:`/`allocElementByMethod:` go straight
into the search loop (`[elementList count]`) with no test of `_poolData` or
`method`. Confirmed by reading the complete instruction sequence for each — none
contain a `test`/`cmp` against `self`'s ivar-4 (`_poolData`) or the incoming
argument before the first `objc_msgSend`.

**Our source:** `addObject:`/`addList:` guard with
`if (poolData != NULL && object/list != nil)`; `allocObjectByMethod:`/
`allocElementByMethod:` guard with `if (poolData == NULL || method == NULL) return nil;`.

**Disposition:** accept

**Rationale:** `_poolData` is only ever NULL before `-init` runs (every
`PCMCIAPool` in this driver comes from `[[PCMCIAPool alloc] init]`, which always
sets `_poolData`), and every caller of `allocObjectByMethod:`/
`allocElementByMethod:` in this driver passes a compile-time `@selector(...)`, never
NULL. The guards are defensive code that cannot currently be exercised, not a
behavioural difference in practice — same category as drvPCIBus's Finding 2 — but
they are real, confirmed extra branches the reference does not have.

## Finding 4: `-[_PCMCIAPool allocObject]` peeks before removing instead of one destructive call

**Source:** `PCMCIAPool.m:161`

**Reference behaviour**

```
push 0
mov edx, sel_removeObjectAt:
push edx
mov edx, [esi]        ; elementList
push edx
call _objc_msgSend     ; object = [elementList removeObjectAt:0]
mov ebx, eax
test ebx, ebx
jz done                 ; nil -> return nil, no addObject: call
push ebx
mov edx, sel_addObject:
push edx
mov esi, [esi+4]        ; objectList
push esi
call _objc_msgSend      ; [objectList addObject:object]
```

**Our source**

```c
object = [poolData->elementList objectAt:0];
if (object != nil) {
    [poolData->elementList removeObjectAt:0];
    [poolData->objectList addObject:object];
}
return object;
```

**Difference:** the reference calls `removeObjectAt:0` exactly once — its return
value is both the "is there anything to allocate" test and the object added to
`objectList`. Our source calls `objectAt:0` first (a non-destructive peek), then, if
that returned non-nil, calls `removeObjectAt:0` again (discarding its return value)
before adding the peeked object to `objectList`. This is one extra `objc_msgSend`
per successful call, confirmed against the full instruction dump (reference: 2
calls total in this function; ours issues 3 send sites for the same operation).

**Disposition:** accept

**Rationale:** assuming `List`'s `objectAt:0` and `removeObjectAt:0` agree on which
object occupies index 0 between the two calls (true here — nothing else can run
between them on this single-threaded driver call path) and agree on nil-on-empty
behaviour, the two are behaviourally equivalent, just with one redundant message
send. Flagged because it is a real, confirmed structural difference, not because it
changes observable behaviour.

## Finding 5: `waitForSocketReady` never detects a ready socket (severe — functional bug)

**Source:** `PCMCIAKernBusPrivate.m:56`

**Reference behaviour**

```
mov ebx, 64h                 ; retries = 100
loc:
push socket
call _objc_msgSend            ; status = [socket status]
test al, al
jge loc_continue               ; signed(al) >= 0 -> not ready yet, keep looping
mov eax, 1                      ; signed(al) < 0 (bit 7 set) -> ready
jmp done
loc_continue:
push 1F4h                        ; IODelay(500)
call _IODelay
dec ebx
jnz loc
xor eax, eax                      ; timed out -> return 0
```

**Our source**

```c
static BOOL waitForSocketReady(id socket)
{
    unsigned char status;
    int retries;

    retries = 100;
    do {
        status = [socket status];
        if (status < 0) {           /* Signed char < 0 means bit 7 is set */
            return YES;
        }
        IODelay(500);
        retries = retries - 1;
    } while (retries != 0);

    return NO;
}
```

**Difference:** `status` is declared `unsigned char`. In C, an `unsigned char`
compared with `< 0` is always false — the comparison, and the `return YES;` branch
it guards, is dead code that a standards-conforming compiler is free to (and here
does) delete entirely. Disassembling our own built binary confirms this: our
compiled `waitForSocketReady` (`out/i386/drvPCMCIABus/PCMCIABus.config/PCMCIABus_reloc`
at file address 3524) calls `[socket status]`, **discards the result without ever
testing it**, unconditionally calls `IODelay(500)`, decrements the retry counter,
loops, and always falls through to `return NO` once the 100 retries are exhausted —
there is no branch to an early return at all in the compiled code. The reference
implements the identical algorithm but with a *signed* comparison (`test al, al;
jge`), so it correctly detects `status`'s bit 7 (the ready flag) and returns `YES`
immediately once the card reports ready, rather than always waiting out the full
~50ms (100 × 500µs) and returning failure.

**Disposition:** fix

**Rationale:** this is not cosmetic — it is a type bug (should be `signed char` or
`char`, matching the correctly-typed `char status` in the sibling function
`-[PCMCIAKernBus enableSocket:]` at `PCMCIAKernBusPrivate.m:1219`, which uses the
identical `status < 0` idiom correctly because there `status` is declared plain
`char`). Every caller of `waitForSocketReady` — `-[PCMCIAKernBus
configureSocket:withDriverTable:]` and three call sites inside
`-[PCMCIAKernBus tupleListFromSocket:mappedAddress:]` — treats a `0` return as "the
socket never became ready" and logs an error / aborts the read. As built today, this
driver's `waitForSocketReady` **always** returns that failure, regardless of actual
hardware state, after an unconditional ~50ms delay each call. This is the most
severe divergence found in this pass; `enableSocket:`'s independent, correctly-typed
copy of the same wait loop is unaffected.

**Outcome:** fixed. `status` in `waitForSocketReady` is now declared plain `char`,
matching the correctly-typed `char status` in the sibling `enableSocket:` loop; the
loop and retry algorithm are unchanged. Not recompiled, so the resulting object
code was not re-disassembled and compared against the reference. Ledger status
advanced from `unexamined` to `control-flow-confirmed`.

## Finding 6: `-[PCMCIAKernBus init]` guards a global list that can never actually be nil

**Source:** `PCMCIAKernBus.m:339`

**Reference behaviour:** unconditionally does
`[_busInstances addObject:self]` — no test of `_busInstances` against nil anywhere
in the function (full instruction dump: `objc_msgSendSuper` for `[super init]`,
alloc+init a `List` into `_adapters`, alloc+init a `HashTable` into `_socketMap`,
then straight into `[_busInstances addObject:self]`, `setBusId:0`, etc. — 10 calls,
1 basic block, no branches).

**Our source:**

```objc
if (_busInstances == nil) {
    _busInstances = [[List alloc] init];
}
[_busInstances addObject:self];
```

**Difference:** our source adds a nil-check-and-lazily-create branch around a class
(not instance) global that the reference never checks.

**Disposition:** accept

**Rationale:** `_busInstances` is set unconditionally in `+[PCMCIAKernBus
initialize]` (`PCMCIAKernBus.m:154`, `PCMCIAKernBus.m:163`), and Objective-C
guarantees `+initialize` runs before any instance method — including `-init` — is
ever sent to the class. `_busInstances` is therefore never actually nil by the time
any `-init` executes, making our guard dead code in practice, not a behavioural
difference. Noted for completeness since it is a real, confirmed extra branch.

## Deprioritized: large `PCMCIAKernBus(Private)` methods not examined

Given the size of this driver (84 functions total) and the priorities in the task
brief (naming-divergence group, tuple-parsing paths, hardware I/O), the following
nine functions were confirmed to exist, build, and agree between IDA and Ghidra on
block/call counts, but were **not read against source** at all — they remain
`unexamined` in the ledger for size/time reasons, not because a divergence was
suspected: `-[PCMCIAKernBus statusChangedForSocket:changedStatus:]` (1113 bytes),
`-[PCMCIAKernBus configureSocket:withDescription:]` (3114 bytes, the largest
function in the binary), `-[PCMCIAKernBus allocateSharedMemory:ForDescription:
AndSocket:]` (1814 bytes), `-[PCMCIAKernBus probeDevice:withDescription:]` (924
bytes), `-[PCMCIAKernBus configureSocket:withDriverTable:]` (543 bytes), `-[PCMCIAKernBus
configureDriverWithTable:]` (Private category, 264 bytes), `-[PCMCIAKernBus
configureSocket:]` (262 bytes), `-[PCMCIAKernBus copyTupleList:]` (215 bytes), and
`-[PCMCIAKernBus configTable:matchesSocket:]` (221 bytes). These are the natural
next targets for a follow-up pass.

## Functions examined with no divergence found

Instruction-level match (`assembly-matched` in the ledger): `_freeString`,
`_addString`, `_addStrings`, `_isValidPCMCIA_IDChar`, `_sanitizeStringCopy`,
`-[PCMCIAKernBus(Parsing) allocResourcesForDescription:fromTupleList:]`,
`-[PCMCIAKernBus(Parsing) parseTuple:intoDeviceDescription:]`, `-[_PCMCIAPool
init]`, `-[_PCMCIAPool free]`, `-[_PCMCIAPool removeObject:]`, `-[_PCMCIAPool
allocElement]`, `-[_PCMCIAPool releaseObject:]`, `-[_PCMCIAPoolElement
initWithPCMCIAPool:object:]`, `-[_PCMCIAPoolElement free]`, `-[_PCMCIAPoolElement
object]`, `-[PCMCIAKernBus setBusRange:]`, `-[PCMCIAKernBus setVerbose:]`,
`+[PCMCIAKernBus requiredProtocols]`, `+[PCMCIAKernBus deviceStyle]`, `-[PCMCIAKernBus
allocateResourcesForDeviceDescription:]`, `-[PCMCIAKernBus enableSocket:]`,
`-[PCMCIAKernBus disableSocket:]`, `_markRange`, `_findBIOSMemoryRange`,
`-[PCMCIATuple initFromData:length:]`, `-[PCMCIATuple free]`, `-[PCMCIATuple code]`,
`-[PCMCIATuple data]`, `-[PCMCIATuple length]`.

Control-flow-level match, no divergence found but not verified instruction by
instruction (`control-flow-confirmed` in the ledger): `_parse_CFTABLE_ENTRY`,
`_printDescription`, `+[PCMCIAid IOLogCardInformation:]`, `-[PCMCIAid
initFromDescription:]`, `-[PCMCIAid initFromIDString:]`, `-[PCMCIAid free]`,
`-[PCMCIAid matchesID:]`, `-[PCMCIAid IOLog]`, `+[PCMCIAKernBus initialize]`,
`+[PCMCIAKernBus probe:]`, `+[PCMCIAKernBus configureDriverWithTable:]`,
`-[PCMCIAKernBus free]`, `-[PCMCIAKernBus memoryRangeResource]`, `-[PCMCIAKernBus
addAdapter:]`, `-[PCMCIAKernBus removeAdapter:]`, `-[PCMCIAKernBus
allocMemoryWindowForSocket:]`, `-[PCMCIAKernBus allocIOWindowForSocket:]`,
`-[PCMCIAKernBus freeMemoryWindowElement:]`, `-[PCMCIAKernBus
mapMemory:ForSocket:ToCardAddress:]`, `-[PCMCIAKernBus
mapAttributeMemory:ForSocket:CardBase:]`, `-[PCMCIAKernBus
findAndReserveRangeBase:Length:AlignedTo:]`, `-[PCMCIAKernBus
testIDs:ForAdapter:andSocket:]`, `-[PCMCIAKernBus entry:matchesUserIOPorts:]`,
`-[PCMCIAKernBus reserveIOPorts:UsingEntry:]`, `-[PCMCIAKernBus
tupleListFromSocket:mappedAddress:]`, `+[PCMCIAResourceDriver probe:]`,
`-[PCMCIAResourceDriver initFromDeviceDescription:]`, `-[PCMCIAResourceDriver
getCharValues:forParameter:count:]`.
