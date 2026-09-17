# drvPS2Mouse divergences

Reference: `PS2Mouse_reloc`, SHA-256 `4C43D8A9AE0B83ACD1BA4D17340A4C6BF5FDACD84634CE5C7FC457D97DE11A7E`
Analyses: IDA 9.2, Ghidra 12.1, angr 9.3.0

## Baseline build

**The build has never been attempted for this driver.** There is no `out/i386/drvPS2Mouse/`
artifact on disk and no recorded parity run. The fix pass (Task 4) establishes the baseline
build and records the staged `PS2Mouse_reloc` size and the four parity counts; no size is
invented here.

Section sizes our build produces are likewise unmeasured. Two scaffolding facts are recorded
now so the fix pass can check them:

- `Load_Commands.sect` is present in `PS2Mouse.drvproj/PS2Mouse.lksproj/` (added by Task 2,
  named in that directory's `Makefile` `OTHERSRCS`), but it is **163 bytes** where the
  reference's `Loaded Server,Load Commands` section is **164**. See Finding 12.
- The reference carries a `Loaded Server,Unload Commands` section of 102 bytes
  (`"# \n# This loadable kernel driver is not unloadable. (I think) this file\n# is still
  necessary.\n#\n\n\n\n\n\n\n"`). Nothing in this repository produces that section, including
  the three already-reconstructed bus drivers. Closing that gap is a build-system change the
  spec puts out of scope; recorded, not fixed.

### Baseline established by the fix pass (Task 4)

The driver builds clean on the Rhapsody guest: `EXIT=0`, `fail=0`, staging a **103316-byte**
`PS2Mouse_reloc`. That is far larger than the reference's 30204 because our build is
unstripped; the size gap is expected and is not a finding. Baseline
`parity_check.py`: `missing_strings` **5**, `missing_symbols` **0**, `extra_strings` **5**,
`extra_symbols` **16**.

After the fix pass the staged `_reloc` is 95068 bytes and parity is `missing_strings` **0**,
`missing_symbols` **0**, `extra_strings` **0**, `extra_symbols` **16**. The 16 extras are
`__TEXT,__text` local and stabs symbols that only exist because our build is unstripped, plus
the two build-generated glue methods; the reference has no local symbol table at all.

**Section sizes after the fix pass: 28 of the reference's 31 sections match byte for byte**,
including every `__OBJC` section (`__class` 120, `__meta_class` 120, `__cls_meth` 40,
`__inst_meth` 128, `__class_names` 111, `__meth_var_types` 116, `__meth_var_names` 528,
`__instance_vars` 28, `__module_info` 32, `__symbols` 36, `__message_refs` 72),
`__TEXT,__cstring` 355, `__DATA,__data` 0, `__DATA,__bss` 56, `__DATA,__common` 4, and all
four `Loaded Server` sections our build emits. Three differ:

| Section | Reference | Ours | Why |
| --- | --- | --- | --- |
| `__TEXT,__text` | 1804 | 1956 → **1856** | see the follow-up pass below; the residual 52 bytes are the null guards accepted under Finding 13 |
| `__TEXT,__const` | 170 | *absent* | `_PS2Mouse_VERS_STRING` (160 bytes) and `_PS2Mouse_VERS_NUM` (10 bytes) |
| `Loaded Server,Unload Commands` | 102 | *absent* | recorded above |

The `__const` gap is the same class of build-system gap as `Unload Commands`: those two
symbols are emitted by NeXT's `vers_string` machinery, not written by hand. Task 5 added the
Kernel Server `Makefile.postamble` line `OTHER_GENERATED_OFILES += $(VERS_OFILE)`. The
symbols are still absent: the guest has no `next-sgs.make`, so `$(VERS_OFILE)` expands empty,
`PS2Mouse_vers.c` / `.o` were never generated, and they do not appear on `kl_ld`.
`driverTools` was not edited. **Accepted with guest evidence;** see Task 5.

### Follow-up pass: the `__text` overshoot was mis-attributed

The fix pass blamed the whole 152-byte `__text` excess on the guards accepted under Findings 10,
13 and 14. That attribution was wrong. **88 of those 152 bytes were two defects in the parameter
methods**, found when drvBusMouse — same `PCPointer` superclass, same two methods — disassembled
its own rebuilt binary, and confirmed here against `PS2Mouse_reloc` before any edit. They are
recorded as Findings 15 and 16 and are now fixed. Per-function extents, measured from real
function symbols (our build carries 284 `__TEXT,__text` symbols including debug stabs, several
sharing an address, so a naive symbol-gap walk gives wrong answers):

| Function | Reference | Before | After |
| --- | --- | --- | --- |
| `-[PS2Mouse getIntValues:forParameter:count:]` | 96 | 128 | **96** |
| `-[PS2Mouse setIntValues:forParameter:count:]` | 148 | 204 | **136** |
| `__TEXT,__text` total | 1804 | 1956 | **1856** |

The driver still builds clean on the guest (`EXIT=0`, `fail=0`), staging a 94632-byte `_reloc`,
and `parity_check.py` still reports `missing_strings` **0**, `missing_symbols` **0**,
`extra_strings` **0**, `extra_symbols` **16**.

The residual +52 is: `initWithController:` +60, `isMousePresent` +8 and `resetMouse` +8 — the
null guards accepted under Finding 13 — less `_PS2MouseIntHandler` −8, `mouseInit:` −4 and
`setIntValues:` −12, all three of which are code-generation differences, not source ones.
Finding 13's guards are therefore the only *source-level* excess left in this driver.

`__DATA,__bss` reaching the reference's 56 bytes required dropping the explicit `= NULL`
initializer on the `controllerFunctions` file static. NeXT's compiler places an explicitly
initialized static in `__DATA,__data` even when the initializer is zero, which left our
`__data` at 4 bytes and `__bss` at 50 against the reference's 0 and 56.

## Summary

| Bucket | Count |
| --- | --- |
| mapped | 11 |
| unmapped | 2 |
| duplicate_candidates | 0 |
| boundary_disputed | 0 |

All 13 reference functions were read at instruction level — every instruction of the full
1804-byte `__text` section was disassembled and compared against `PS2Mouse.m`. Nothing in this
driver was reviewed at control-flow level only, and nothing was reviewed by grep.

Of the 11 mapped functions, **2** have instruction streams that match our source exactly
(`-[PS2Mouse getHandler:level:argument:forInterrupt:]` and `-[PS2Mouse getResolution]`, both
`assembly-matched`); both nonetheless carry declaration-level divergences recorded under
Finding 2, which do not appear in the emitted code. The remaining **9** each carry at least one
confirmed body divergence and stayed `unexamined` in the ledger, per the convention that a
diverging function is left for the fix pass. The 2 unmapped glue methods are
`intentional-mismatch`.

**Fix pass (Task 4) outcome.** All 9 were resolved. Four became `control-flow-confirmed` with
no residual divergence (`mouseInit:`, `readConfigTable:`, `interruptOccurred`,
`getIntValues:forParameter:count:`); five carry a divergence this document accepts under
Finding 10, 13 or 14 and are `intentional-mismatch`, reviewed by Pat Raynor
(`isMousePresent`, `resetMouse`, `initWithController:`, `_PS2MouseIntHandler`,
`setIntValues:forParameter:count:`). No entry is `assembly-matched` on the strength of the fix
pass: the rebuilt object was compared against the reference at the level of section sizes,
Objective-C metadata, the string set and the symbol set — all of which now agree — but its
`__text` was not disassembled and re-compared instruction for instruction, so that claim is
not made.

**Follow-up pass outcome.** Findings 15 and 16 were fixed and Finding 10's acceptance was
reversed. The rebuilt `__text` for both parameter methods *was* disassembled and re-compared
instruction for instruction against the reference, so `-[PS2Mouse getIntValues:forParameter:
count:]` advances from `control-flow-confirmed` to `assembly-matched` (now exactly the
reference's 96 bytes), and `-[PS2Mouse setIntValues:forParameter:count:]` stays
`intentional-mismatch` with its reason rewritten: the nil guards are gone, and the only residual
is the reference's stack spill of the compare count and of `parameterArray`, which leaves ours
12 bytes smaller. Counts are now `assembly-matched` 3, `control-flow-confirmed` 3,
`intentional-mismatch` 7.

Beyond the function bodies, the object's Objective-C metadata was decoded directly from the
Mach-O (`__class`, `__instance_vars`, `__inst_meth`, `__cls_meth`, `__meth_var_types`,
`__bss`, `__cstring`) and compared against `PS2Mouse.h`/`PS2Mouse.m`. Findings 1, 2 and 5 come
from that metadata rather than from any single function body, and they are the largest
divergences in this driver.

## Function partition: sizes

The brief's partition table lists sizes as the gaps between consecutive symbol addresses
(180, 112, 40, 352, 216, 528, 52, 40, 16, 96, 148, 12, 12). IDA reports the function extents
with the inter-function `nop` alignment padding excluded (179, 109, 37, 350, 214, 525, 50, 39,
16, 93, 146, 12, 12). Addresses and names agree exactly in both. IDA is authoritative for the
partition, so `source-map.json` and `ledger.json` carry IDA's extents. This is a padding
accounting difference, not a disagreement about what exists.

## Unmapped: build-generated

`+[PS2MouseKernelServerInstance kernelServerInstance]` (1780) and
`+[PS2MouseVersion driverKitVersionForPS2Mouse]` (1792) are emitted by the Kernel Server
project type and `Load_Commands.sect`, not written by hand. Accepted.

The first returns `&_PS2Mouse_instance` (`__common`, 0x4038); the second returns `500`
(0x1F4). Their owning classes come from the same generated glue: `__class` declares
`PS2MouseKernelServerInstance : Object` and `PS2MouseVersion : IODevice`, and
`__class_names` carries the generated translation unit name `PS2Mouse_instance.m` alongside
the hand-written `PS2Mouse.m`.

`_PS2Mouse_VERS_STRING` (2159, `__const`), `_PS2Mouse_VERS_NUM` (2319, `__const`) and
`_PS2Mouse_instance` (16440, `__common`) are data symbols outside `__TEXT,__text` and
therefore do not appear anywhere in the source map, which lists functions only.

## Analyzer disagreement

**Ghidra does not detect `+[PS2MouseKernelServerInstance kernelServerInstance]` at 1780.**
Ghidra's function list has 12 entries where IDA and angr both have 13; the missing one is the
12-byte glue method at 1780. The neighbouring function at 1792 has identical bytes, blocks and
size in all three analyzers, so this is a Ghidra detection gap for one function, not a body
disagreement. This is the same class of gap drvPCIBus recorded for `-[PCIKernBus test_M1]`.
Per the convention IDA is authoritative for the partition, so this does not affect the source
map.

**Ghidra under-reports indirect calls.** For every function whose calls go through the
`_func_list` function-pointer table, Ghidra records fewer `calls` than IDA:
`-[PS2Mouse isMousePresent]` 0 vs 6, `-[PS2Mouse resetMouse]` 0 vs 2,
`-[PS2Mouse initWithController:]` 12 vs 17, `_PS2MouseIntHandler` 3 vs 6. Sizes and basic-block
counts are identical in both analyzers in every one of those functions, so this is Ghidra
declining to record `call eax`/`call edx` edges, not a difference of opinion about the code.

**angr reports 37 functions.** All 13 real functions are present at identical addresses with
identical sizes. The 24 extra entries are 22 one-to-three-byte fragments sitting on the
inter-function `nop` alignment padding (149, 179, 277, 289, 329, 357, 637, 682, 811, 871, 898,
963, 1075, 1202, 1297, 1425, 1478, 1519, 1578, 1606, 1629, 1730) plus two entries covering the
`__const` data symbols `_PS2Mouse_VERS_STRING` (2159, 160 bytes) and `_PS2Mouse_VERS_NUM`
(2319, 10 bytes). angr also splits basic blocks more finely than IDA within the real
functions. None of this is a partition disagreement.

No boundary is genuinely disputed; `boundary_disputed` and `duplicate_candidates` are both
empty.

## Configuration table

`src/drivers-i386/input/drvPS2Mouse/PS2Mouse.drvproj/Default.table` diffs clean against
`C:\Users\raynorpat\Downloads\test\Drivers\i386\PS2Mouse.config\Default.table` ignoring
`"Driver Version"`. Task 2's key rename landed correctly; there is no Task 2 defect here.

---

## Finding 1: `PS2Mouse` derives from `PCPointer`, not `IODirectDevice`

**Source:** `src/drivers-i386/input/drvPS2Mouse/PS2Mouse.drvproj/PS2Mouse.lksproj/PS2Mouse.h:38`

**Reference metadata**

`__class` (decoded):

```
PS2Mouse                     : PCPointer   instance_size = 332 (0x14C)
PS2MouseVersion              : IODevice
PS2MouseKernelServerInstance : Object
```

`__instance_vars` (28 bytes, 2 entries):

```
ivar "controller"       type "@"  offset 324 (0x144)
ivar "force_detection"  type "c"  offset 328 (0x148)
```

The three UNDEF Objective-C class references are `.objc_class_name_PCPointer`,
`.objc_class_name_IODevice` and `.objc_class_name_Object` — there is no reference to
`IODirectDevice` anywhere in the object.

**Our source**

```objc
@interface PS2Mouse : IODirectDevice
{
@private
    unsigned int resolution;
    BOOL inverted;
    id mouseEventPort;
    id controller;
    BOOL forceDetection;
}
```

**Difference:** the reference class owns exactly two ivars. Everything else the code touches
comes from `PCPointer`:

| Offset | Reference ivar | Owner | Our declaration |
| --- | --- | --- | --- |
| 0x128 | `target` | `PCPointer` | `mouseEventPort` (own) |
| 0x12c | `resolution` | `PCPointer` | `resolution` (own) |
| 0x130 | `inverted` | `PCPointer` | `inverted` (own) |
| 0x134–0x143 | `_reserved[4]` | `PCPointer` | absent |
| 0x144 | `controller` | `PS2Mouse` | `controller` (own) |
| 0x148 | `force_detection` | `PS2Mouse` | `forceDetection` (own) |

`PCPointer` is already in this repository at
`src/kernel-7/bsd/dev/i386/PCPointer.h` / `PCPointer.m`, declared as
`@interface PCPointer : IODirectDevice { id target; unsigned resolution; BOOL inverted;
@private int _reserved[4]; }`. That layout puts `target` at 0x128, `resolution` at 0x12c,
`inverted` at 0x130 and `_reserved` at 0x134–0x143 on top of a 0x128-byte `IODirectDevice`,
giving a total instance size of 0x14C = **332 — exactly the reference's `instance_size`**. The
in-tree `PCPointer.h` is a byte-exact match for the base class Apple compiled against.

Note also that the reference's ivar name is `force_detection`, with an underscore; ours is
`forceDetection`. Objective-C ivar names are emitted verbatim into `__instance_vars`, so this
is observable in the binary.

**Disposition:** fix

**Rationale:** this is the root divergence in the driver. Every ivar offset in every function
body depends on it, so no function's emitted code can match until the hierarchy matches.
Re-parenting to `PCPointer` also removes three of our five ivar declarations (they become
inherited) and supplies `PCPatoi` (Finding 8) and the `RESOLUTION`/`INVERTED` key macros. The
work is not speculative: the base class is already in the tree and its layout is confirmed
against the binary.

**Resolution (Task 4):** fixed. `PS2Mouse.h` now declares `@interface PS2Mouse : PCPointer`
and imports `<bsd/dev/i386/PCPointer.h>` and `<bsd/dev/i386/PCPointerDefs.h>`; the lksproj
`Makefile` gained `-DDRIVER_PRIVATE` so those headers expose their contents, matching the
convention the three bus drivers already use. `resolution`, `inverted` and `mouseEventPort`
were deleted as own ivars — the first two are now inherited and the third is PCPointer's
`target` — leaving exactly `controller` and `force_detection`, and the ivar was renamed from
`forceDetection` to `force_detection` to match `__instance_vars`. Verified in our rebuilt
object: `__class` reports `instance_size = 332`, `__instance_vars` is 28 bytes, the class name
list is `PS2Mouse`/`PCPointer`/`Object` with no `IODirectDevice` reference in the Objective-C
metadata, and the debug symbols place `controller` at bit offset 2592 (0x144) and
`force_detection` at 2624 (0x148). Ledger: `control-flow-confirmed` across the affected
entries.

## Finding 2: method return types and signatures

**Source:** `src/drivers-i386/input/drvPS2Mouse/PS2Mouse.drvproj/PS2Mouse.lksproj/PS2Mouse.h:49`
and `PS2Mouse.m` throughout

**Reference metadata**

`__inst_meth` (10 entries, name and type encoding):

```
mouseInit:                              c12@8:12@16
initWithController:                     c12@8:12@16
readConfigTable:                        c12@8:12@16
resetMouse                              v8@8:12
isMousePresent                          c8@8:12
interruptOccurred                       v8@8:12
getResolution                           i8@8:12
getHandler:level:argument:forInterrupt: c24@8:12^^?16^I20^I24I28
getIntValues:forParameter:count:        i20@8:12^I16*20^I24
setIntValues:forParameter:count:        i20@8:12^I16*20I24
```

Confirmed in the code: `-[PS2Mouse initWithController:]` ends `mov eax, 1` on the success path
(630) and `xor eax, eax` on both failure paths (352→671, 671); `-[PS2Mouse mouseInit:]` ends
`movsx eax, al` (169) — it sign-extends the `BOOL` its callee returned — and `xor eax, eax`
on both of its own failure paths (104, 145). `-[PS2Mouse resetMouse]` (292–328) never writes
`eax` at all.

**Our source**

```objc
- (IOReturn)mouseInit:(IODeviceDescription *)deviceDescription;
- (IOReturn)initWithController:(id)controllerDevice;
- (IOReturn)resetMouse;
- (unsigned int)getResolution;
- (BOOL)getHandler:(IOInterruptHandler *)handler
             level:(unsigned int *)ipl
          argument:(void **)arg
      forInterrupt:(unsigned int)localInterrupt;
```

**Difference:**

- `mouseInit:` and `initWithController:` return **`BOOL`** in the reference, with **1 =
  success, 0 = failure**. Ours return `IOReturn`, with **0 (`IO_R_SUCCESS`) = success** and
  `IO_R_NOT_ATTACHED`/`IO_R_INVALID_ARG` = failure. The polarity is inverted: our successful
  `initWithController:` returns 0, which a `BOOL`-expecting caller reads as failure, and our
  failing one returns −729, which reads as true.
- `resetMouse` returns **`void`**. Ours returns `IOReturn` (`IO_R_NOT_ATTACHED` /
  `IO_R_SUCCESS`).
- `getResolution` returns **`int`** (`i8@8:12`). Ours returns `unsigned int`, which would
  encode as `I8@8:12`. The in-tree `PCPointer.h:64` also declares `- (int)getResolution`.
- `getHandler:…`'s `argument:` parameter is encoded `^I` — pointer to `unsigned int`. Ours
  declares `void **arg`, which encodes as `^^v`. The emitted instruction stream is identical
  either way (`mov dword ptr [ecx], 0xdeadbeef`); only the type metadata differs.

**Disposition:** fix

**Rationale:** the `mouseInit:`/`initWithController:` polarity is not cosmetic. `PCPointer` is
what calls `mouseInit:`, and `PCPointer.h:70` declares it `- (BOOL)mouseInit:deviceDescription`.
Once Finding 1 re-parents the class, our current `IOReturn` return would report every
successful probe as a failure and every `IO_R_NOT_ATTACHED` failure as a success. This must be
fixed in the same change as Finding 1, not after it.

**Resolution (Task 4):** fixed, in the same commit as Finding 1 as its rationale requires.
`mouseInit:`, `initWithController:` and `readConfigTable:` now return `BOOL` with 1 = success;
every `IO_R_SUCCESS` return on those paths became `YES` and every `IO_R_NOT_ATTACHED` /
`IO_R_INVALID_ARG` became `NO`. `resetMouse` returns `void`, `getResolution` returns `int`, and
`getHandler:`'s `argument:` parameter is now `unsigned int *`. Verified in the rebuilt object:
`__meth_var_types` is 116 bytes as in the reference and carries `c12@8:12@16`, `v8@8:12`,
`i8@8:12` and `^^?16^I20^I24I28`, with no `I8@8:12` and no `^^v` encoding.

## Finding 3: `readConfigTable:` takes the config table, not the device description

**Source:** `src/drivers-i386/input/drvPS2Mouse/PS2Mouse.drvproj/PS2Mouse.lksproj/PS2Mouse.m:309`
(and the call site at `PS2Mouse.m:516`)

**Reference behaviour**

`-[PS2Mouse mouseInit:]`, 108–138 — the result of `configTable` is the argument to
`readConfigTable:`:

```
108  mov  edx, [0x2004]        ; @selector(configTable)
114  push edx
115  mov  edx, [ebp+0x10]      ; deviceDescription
118  push edx
119  call _objc_msgSend        ; eax = [deviceDescription configTable]
124  push eax                  ;   <-- argument to the next message
125  mov  edx, [0x2008]        ; @selector(readConfigTable:)
131  push edx
132  push ebx                  ; self
133  call _objc_msgSend        ; [self readConfigTable:<configTable>]
```

`-[PS2Mouse readConfigTable:]`, 692–729 — the argument is messaged with `valueForStringKey:`
directly, with no intervening `configTable` send:

```
692  mov  esi, [ebp+0x10]      ; esi = the argument
695  test esi, esi
697  jne  0x2cc
699  push 0x795                ; "PS2Mouse readConfigTable: no configuration table\n"
704  call _IOLog
709  xor  eax, eax             ; return NO
...
716  push 0x7c7                ; "Force Detection"
721  mov  edx, [0x2034]        ; @selector(valueForStringKey:)
727  push edx
728  push esi                  ;   <-- the argument is the receiver
729  call _objc_msgSend
```

**Our source**

```objc
- (BOOL)readConfigTable:(IODeviceDescription *)deviceDescription
{
    if (deviceDescription == nil) {
        IOLog("PS2Mouse: No device description provided\n");
        return NO;
    }
    configTable = [deviceDescription configTable];
    forceDetectionStr = [configTable valueForStringKey:"Force Detection"];
```

and in `mouseInit:`:

```objc
    configTable = [deviceDescription configTable];   /* result unused */
    success = [self readConfigTable:deviceDescription];
```

**Difference:** the reference's `readConfigTable:` receives an `IOConfigTable` and its nil
check tests the config table. Ours receives the `IODeviceDescription`, tests that instead, and
does the `configTable` send internally — while `mouseInit:` *also* sends `configTable` and
throws the result away into an unused local. The reference sends `configTable` exactly once,
in `mouseInit:`. The nil-check semantics differ too: a valid device description with no
configuration table passes our check and fails the reference's.

**Disposition:** fix

**Resolution (Task 4):** fixed. `readConfigTable:` now takes an `IOConfigTable *` and
nil-checks that, and `mouseInit:` sends `configTable` exactly once, passing the result
straight through: `[self readConfigTable:[deviceDescription configTable]]`. The unused local
in `mouseInit:` is gone.

## Finding 4: `Force Detection` sense — RESOLVED, no inversion needed

**Source:** `src/drivers-i386/input/drvPS2Mouse/PS2Mouse.drvproj/PS2Mouse.lksproj/PS2Mouse.m:414`
and `PS2Mouse.m:328`

This is the question Task 2 deferred. **The disassembly settles it, and our current test is
correct as written.**

**Reference behaviour — how the value is stored**

`-[PS2Mouse readConfigTable:]`, 716–760:

```
716  push 0x7c7                      ; "Force Detection"
721  mov  edx, [0x2034]              ; @selector(valueForStringKey:)
727  push edx
728  push esi                        ; the config table
729  call _objc_msgSend
734  add  esp, 0xc
737  test eax, eax
739  je   0x2f8                      ; NULL           -> store 0
741  cmp  byte ptr [eax], 0x79       ; 'y'
744  je   0x2ef                      ; 'y'            -> store 1
746  cmp  byte ptr [eax], 0x59       ; 'Y'
749  jne  0x2f8                      ; anything else  -> store 0
751  mov  byte ptr [ebx+0x148], 1    ; 0x2ef: force_detection = 1
758  jmp  0x2ff
760  mov  byte ptr [ebx+0x148], 0    ; 0x2f8: force_detection = 0
```

**Reference behaviour — how the value gates the check**

`-[PS2Mouse initWithController:]`, 418–451:

```
418  cmp  byte ptr [esi+0x148], 0    ; force_detection
425  jne  0x1c3                      ;   nonzero -> JUMP PAST the presence check, to 451
427  mov  ecx, [0x2018]              ; @selector(isMousePresent)
433  push ecx
434  push esi
435  call _objc_msgSend              ; [self isMousePresent]
440  add  esp, 8
443  test al, al
445  je   0x280                      ;   NO -> setManualDataHandling:NO, log, return NO
451  ...                             ; <- force_detection != 0 lands here: attach
```

**Our source**

```objc
/* PS2Mouse.m:328 */
forceDetectionStr = [configTable valueForStringKey:"Force Detection"];
if ((forceDetectionStr == NULL) ||
    ((*forceDetectionStr != 'y') && (*forceDetectionStr != 'Y'))) {
    forceDetection = NO;
} else {
    forceDetection = YES;
}

/* PS2Mouse.m:414 */
if (!forceDetection) {
    mousePresent = [self isMousePresent];
    if (!mousePresent) {
        [controller setManualDataHandling:NO];
        IOLog("PS2Mouse: couldn't find a mouse!\n");
        return IO_R_NOT_ATTACHED;
    }
}
```

**Answer:** `Force Detection = Yes` **bypasses the presence check and attaches regardless.**
The reference stores 1 for a leading `y`/`Y` and 0 otherwise — byte for byte what our parse
does — and `jne` at 425 skips the entire `isMousePresent` block when the byte is nonzero. Our
`if (!forceDetection) { …presence check… }` at `PS2Mouse.m:414` is semantically identical.
**Task 4 must not invert this test.** The name is a slight misnomer in Apple's own binary
("force detection" meaning "force the attach, skip detection"), which is presumably why the
question arose; the code is unambiguous.

**Disposition:** accept — our source already matches the reference. No change required.

**Resolution (Task 4):** accepted unchanged, as this finding directs. `PS2Mouse.m`'s
`if (!force_detection) { …presence check… }` was **not** inverted. The only edit in that
region was renaming the ivar to `force_detection` (Finding 1) and returning `NO` instead of
`IO_R_NOT_ATTACHED` (Finding 2); the sense of the test is exactly as it was.

## Finding 5: static-storage layout and the event struct

**Source:** `src/drivers-i386/input/drvPS2Mouse/PS2Mouse.drvproj/PS2Mouse.lksproj/PS2Mouse.m:36`–`61`

**Reference `__DATA,__bss`** (56 bytes at 0x4000, plus `__common` at 0x4038):

| Address | Symbol | Size |
| --- | --- | --- |
| 0x4000 | `_indexInSequence` | 4 |
| 0x4004 | `_currentEvent` | 12 |
| 0x4010 | `_pendingEvent` | 12 |
| 0x401c | `_summedEvent` | 12 |
| 0x4028 | `_lastTimeStamp` | 8 |
| 0x4030 | `_seqBeingProcessed` | 1 |
| 0x4031 | `_seqInProgress` | 1 |
| 0x4032 | *(2 bytes padding)* | 2 |
| 0x4034 | `_func_list` | 4 |
| 0x4038 | `_PS2Mouse_instance` (`__common`) | 4 |

The brief's expectation is confirmed exactly: `_lastTimeStamp` is 8 bytes,
`_seqBeingProcessed` and `_seqInProgress` are 1 byte each, and there are 2 bytes of padding
before `_func_list`.

The 12-byte event layout is pinned down by the accesses in `_PS2MouseIntHandler`. The handler
writes the incoming packet bytes at `[edx + 0x400c]` (1309) and `[edx + 0x4018]` (1131, 1222)
with `edx = _indexInSequence`, i.e. at `event + 8 + index`; it stores the 64-bit timestamp at
0x4004/0x4008 (1357, 1366), i.e. at `event + 0`; and it accumulates deltas at 0x4025/0x4026
(1162, 1174), i.e. at `_summedEvent + 9` and `+ 10`. That gives:

```c
struct {
    ns_time_t     timestamp;   /* +0, 8 bytes */
    unsigned char buttons;     /* +8  */
    char          deltaX;      /* +9  */
    char          deltaY;      /* +10 */
    char          pad;         /* +11 */
};                             /* 12 bytes */
```

**Our source**

```c
static int seqInProgress = 0;         /* 4 bytes */
static int seqBeingProcessed = 0;     /* 4 bytes */
static int indexInSequence = 0;
static char accumulatedDeltaX = 0;
static char accumulatedDeltaY = 0;
static struct { unsigned char buttons; char deltaX; char deltaY; } currentPacket;
static struct { unsigned char buttons; char deltaX; char deltaY; } nextPacket;
static ns_time_t currentEventTime = 0;
static unsigned int lastTimeStamp_low = 0;
static int lastTimeStamp_high = 0;
```

**Difference:**

- The reference's three event buffers are single 12-byte structs that carry their own
  timestamp. Ours splits each into a 3-byte packet struct with the timestamp held in a
  separate, non-adjacent object (`currentEventTime`), and has no equivalent of
  `_summedEvent`'s struct form at all — just two loose `char` accumulators.
- `_seqBeingProcessed` and `_seqInProgress` are 1 byte each in the reference; ours declares
  both as `int` (4 bytes).
- `_lastTimeStamp` is one 8-byte object; ours is two separate 4-byte objects.
- Declaration order differs throughout, so the `__bss` layout our build emits cannot match.

**Disposition:** fix

**Rationale:** this is not merely cosmetic — Finding 6 is a live bug that falls directly out
of it.

**Resolution (Task 4):** fixed. The three event buffers are now single
`PCPointerEvent` objects — `currentEvent`, `pendingEvent`, `summedEvent` — the type
`<bsd/dev/i386/PCPointerDefs.h>` already declares as an 8-byte `ns_time_t timeStamp` followed
by a 4-byte union whose `data.buf[0..2]` are the buttons and the X and Y deltas, exactly the
12-byte shape the reference's accesses imply. The two loose `char` accumulators became
`summedEvent.data.buf[1]`/`[2]`, the split `lastTimeStamp_low`/`_high` pair became one
`ns_time_t lastTimeStamp`, and `seqBeingProcessed`/`seqInProgress` became `BOOL`. Declaration
order now follows the reference's `__bss` order. Verified: `__DATA,__bss` is 56 bytes and
`__DATA,__data` is 0, both matching the reference (see the baseline-build section for the
`= NULL` initializer that had to be dropped to get there).

## Finding 6: `interruptOccurred` dispatches the wrong memory

**Source:** `src/drivers-i386/input/drvPS2Mouse/PS2Mouse.drvproj/PS2Mouse.lksproj/PS2Mouse.m:562`

**Reference behaviour**

```
1431  mov  eax, [ebp+8]                 ; self
1434  cmp  dword ptr [eax+0x128], 0     ; target
1441  je   0x5bb
1443  push 0x4004                       ; &_currentEvent   <-- the whole 12-byte event
1448  mov  edx, [0x2038]                ; @selector(dispatchPointerEvent:)
1454  push edx
1455  mov  eax, [eax+0x128]
1461  push eax
1462  call _objc_msgSend
1467  mov  byte ptr [0x4030], 0         ; _seqBeingProcessed = 0  (both paths)
```

**Our source**

```objc
if (mouseEventPort != nil) {
    [mouseEventPort dispatchPointerEvent:&currentEventTime];
}
seqBeingProcessed = 0;
```

**Difference:** the reference passes `&_currentEvent`, whose first 8 bytes are the timestamp
and whose bytes 8/9/10 are `buttons`/`deltaX`/`deltaY`. Ours passes `&currentEventTime` — an
8-byte `ns_time_t` that is **not** followed by `currentPacket`. In our declaration order
(`PS2Mouse.m:36`–`61`) `currentEventTime` is declared *after* `currentPacket` and `nextPacket`
and *before* `lastTimeStamp_low`/`lastTimeStamp_high`. The event port therefore reads its
button and delta bytes out of the low bytes of `lastTimeStamp_low`, not out of the packet the
handler just assembled.

The control-flow shape is otherwise correct, including the detail that `seqBeingProcessed = 0`
executes on both the nil and non-nil paths.

**Disposition:** fix

**Rationale:** a real defect, not a stylistic difference. Every dispatched pointer event
carries garbage buttons and deltas. It is fixed by Finding 5 (declare the 12-byte event struct
and pass `&currentEvent`), and should not be patched independently.

**Resolution (Task 4):** fixed, as a consequence of Finding 5 rather than independently.
`interruptOccurred` now reads `[target dispatchPointerEvent:&currentEvent]` — the inherited
`PCPointer` ivar at 0x128, and the whole 12-byte event whose timestamp, buttons and deltas are
contiguous. The live defect is gone: dispatched events no longer carry the low bytes of an
unrelated object as their buttons and deltas.

## Finding 7: `initWithController:` sends the wrong 8042 command bytes

**Source:** `src/drivers-i386/input/drvPS2Mouse/PS2Mouse.drvproj/PS2Mouse.lksproj/PS2Mouse.m:432`–`453`

**Reference behaviour**

```
451  mov  eax, [0x4034]         ; _func_list
456  push 0x20                  ;   command 0x20 = READ COMMAND BYTE
458  mov  eax, [eax]            ;   func_list[0]
460  call eax
462  mov  eax, [0x4034]
467  mov  eax, [eax+4]          ;   func_list[1] = read a byte
470  call eax
472  mov  bl, al
474  and  bl, 0xdf              ;   clear bit 5
477  or   bl, 2                 ;   set bit 1
480  mov  eax, [0x4034]
485  push 0x60                  ;   command 0x60 = WRITE COMMAND BYTE
487  mov  eax, [eax]            ;   func_list[0]
489  call eax
491  mov  edx, [0x4034]
497  movzx eax, bl
500  push eax
501  mov  eax, [edx+0x10]       ;   func_list[4] = write a byte
504  call eax
```

**Our source**

```objc
if (controllerFunctions->reserved[0] != NULL) {
    ((void (*)(void))controllerFunctions->reserved[0])();      /* no argument */
}
if (controllerFunctions->reserved[1] != NULL) {
    statusByte = ((unsigned char (*)(void))controllerFunctions->reserved[1])();
} else {
    statusByte = 0;
}
if (controllerFunctions->reserved[0] != NULL) {
    ((void (*)(unsigned char))controllerFunctions->reserved[0])(0x07);
}
if (controllerFunctions->reserved[4] != NULL) {
    ((void (*)(unsigned char))controllerFunctions->reserved[4])((statusByte & 0xDF) | 0x02);
}
```

**Difference:** the reference passes **0x20** to the first `func_list[0]` call and **0x60** to
the second. Ours passes **no argument** to the first and **0x07** to the second. 0x20 and 0x60
are the standard 8042 "read command byte" and "write command byte" opcodes, and the read /
mask / write sandwich between them is the classic sequence for enabling the auxiliary-device
interrupt (clear bit 5 = un-disable the mouse clock, set bit 1 = enable IRQ12). Our 0x07 is
not a meaningful 8042 command in this position, and the argument-less first call leaves the
callee reading whatever happens to be on the stack.

The mask arithmetic (`& 0xDF | 0x02`), the function-table slots used (0, 1, 0, 4) and the
ordering all match.

**Disposition:** fix

**Rationale:** this determines whether IRQ12 is ever enabled on the controller. Getting the
command bytes wrong means the mouse never delivers interrupts.

**Resolution (Task 4):** fixed. The first `func_list[0]` call now passes
`K8042_READ_COMMAND_BYTE` (0x20) and the second passes `K8042_WRITE_COMMAND_BYTE` (0x60), two
new defines beside the existing PS/2 command defines. The argument-less first call is gone.
IRQ12 is now actually enabled on the controller.

## Finding 8: `readConfigTable:` parses the resolution with `strtoul`, not `PCPatoi`

**Source:** `src/drivers-i386/input/drvPS2Mouse/PS2Mouse.drvproj/PS2Mouse.lksproj/PS2Mouse.m:356`

**Reference behaviour**

```
840  test eax, eax
842  jne  0x368                       ; non-NULL -> parse
844  mov  dword ptr [ebx+0x12c], 0x96 ; resolution = 150
854  push 0x96
859  push 0x7eb                       ; "PS2Mouse readConfigTable: no resolution in
                                      ;  config table.  Default is %d\n"
864  call _IOLog
869  jmp  0x374
872  push eax                         ; 0x368: the string
873  call _PCPatoi
878  mov  dword ptr [ebx+0x12c], eax
884  mov  eax, 1                      ; return YES
```

`_PCPatoi` is an undefined external symbol in this object (UNDEF, 0x615c).

**Our source**

```objc
resolutionStr = [configTable valueForStringKey:"Resolution"];
if (resolutionStr == NULL) {
    resolution = 0x96;
    IOLog("PS2Mouse: Using default resolution %d\n", 0x96);
} else {
    resolution = strtoul(resolutionStr, NULL, 0);
}
```

**Difference:** the reference calls `PCPatoi`, declared in `src/kernel-7/bsd/dev/i386/PCPointer.h:45`
as `int PCPatoi(char *p)` and defined in `PCPointer.m`. Ours calls `strtoul` with base 0, which
accepts `0x`/`0` prefixes that `PCPatoi` does not, and is a different symbol in the linked
image. The default-value path and the `0x96` literal match; only the log text differs
(Finding 11).

**Disposition:** fix

**Rationale:** `PCPatoi` arrives for free with Finding 1's re-parenting, since `PCPointer.h`
declares it.

**Resolution (Task 4):** fixed. `resolution = PCPatoi((char *)resolutionStr);` replaces
the `strtoul` call. `PCPatoi` is declared by `PCPointer.h`, so it arrived with Finding 1 as
predicted; the build produces no implicit-declaration warning for it and the reference's
`_PCPatoi` UNDEF is reproduced.

## Finding 9: `getIntValues:`/`setIntValues:` return `IO_R_UNSUPPORTED`, not `IO_R_INVALID_ARG`

**Source:** `src/drivers-i386/input/drvPS2Mouse/PS2Mouse.drvproj/PS2Mouse.lksproj/PS2Mouse.m:609`
and `PS2Mouse.m:668`

**Reference behaviour**

`-[PS2Mouse getIntValues:forParameter:count:]` at 1599 and
`-[PS2Mouse setIntValues:forParameter:count:]` at 1723, both on the "parameter name matched
neither `Resolution` nor `Inverted`" path:

```
mov eax, 0xfffffd39
```

`0xFFFFFD39` is −711. `driverkit/return.h:51` defines `IO_R_UNSUPPORTED` as `(-711)`;
`IO_R_INVALID_ARG` is `(-706)` = `0xFFFFFD3E`.

**Our source**

```objc
if (!match) {
    return IO_R_INVALID_ARG;
}
```

**Difference:** both methods return `IO_R_UNSUPPORTED` in the reference and `IO_R_INVALID_ARG`
in ours. There are exactly two such sites, one per method.

Both string comparisons themselves match exactly — `repe cmpsb` with `ecx = 11` against
`"Resolution"` and `ecx = 9` against `"Inverted"`, which is what our unrolled compare loops
(`i = 11` / `i = 9`) reproduce. `getIntValues:` reads `inverted` with `movsx edx, byte
[edx+0x130]` (sign-extending a signed `char`) where ours writes `(unsigned int)inverted`; for
the only values it ever holds (0 and 1) these are identical. Neither method touches `count`.

**Disposition:** fix

**Rationale:** "this driver does not know that parameter" is `IO_R_UNSUPPORTED`, and callers
that branch on the specific `IOReturn` would observe the difference. Same class of finding as
drvPCIBus's Findings 6 and 7.

**Resolution (Task 4):** fixed. Both no-match paths now return `IO_R_UNSUPPORTED`. The
two `repe cmpsb`-shaped compare loops and the sign-extending read of `inverted` were left
exactly as they were, since the report pass confirmed both already match.

## Finding 10: `setIntValues:` nil-checks the event port; the reference does not

**Source:** `src/drivers-i386/input/drvPS2Mouse/PS2Mouse.drvproj/PS2Mouse.lksproj/PS2Mouse.m:650`
and `PS2Mouse.m:676`

**Reference behaviour**

```
1682  mov  ecx, [0x203c]        ; @selector(getResolution)
1688  push ecx
1689  push ebx
1690  call _objc_msgSend
1695  push eax
1696  mov  edx, [0x2040]        ; @selector(setResolution:)
1702  jmp  0x6d9
1753  push edx
1754  mov  ebx, [ebx+0x128]     ; target -- loaded and messaged unconditionally
1760  push ebx
1761  call _objc_msgSend
```

and the `Inverted` path at 1737–1761, likewise with no test of `[ebx+0x128]` before the send.

**Our source**

```objc
if (mouseEventPort != nil) {
    [mouseEventPort setResolution:resolutionValue];
}
...
if (mouseEventPort != nil) {
    [mouseEventPort setInverted:invertedValue];
}
```

**Difference:** the reference messages `target` unconditionally in both branches of
`setIntValues:`. Ours guards both sends with a nil check. (Note the reference *does* nil-check
the same ivar in `interruptOccurred` at 1434, so this is a deliberate asymmetry in Apple's
code, not an oversight in our reading.)

**Disposition:** accept

**Rationale:** Objective-C messages to `nil` are no-ops that return 0, so the guarded and
unguarded forms behave identically. Recorded because it is a real, confirmed control-flow
difference from the reference, and because it is the only place our added guards are provably
free of behavioural effect.

**Resolution (Task 4):** accepted unchanged. Both `target` nil checks in `setIntValues:`
remain. Ledger: `-[PS2Mouse setIntValues:forParameter:count:]` is `intentional-mismatch`,
reviewed by Pat Raynor, for exactly this reason.

**Resolution (follow-up pass): superseded and FIXED — see Finding 16.** Accepting these guards
was a mistake. They are 32 of the 56 bytes by which `setIntValues:` overshot the reference, and
parity with the shipped binary is the point of this reconstruction; drvBusMouse's
`setIntValues:`, verified against its own reference, sends unconditionally. Both guards were
removed.

## Finding 11: string set

**Source:** `src/drivers-i386/input/drvPS2Mouse/PS2Mouse.drvproj/PS2Mouse.lksproj/PS2Mouse.m`, various

**Reference `__cstring`** (355 bytes at 1804, complete):

```
1804  'PS2Controller'
1818  "initPointer: Can't find PS2Controller (%s)\n"
1862  'PS2Mouse: no PS2Controller present\n'
1898  'PS2Mouse'
1907  "PS2Mouse: couldn't find a mouse!\n"
1941  'PS2Mouse readConfigTable: no configuration table\n'
1991  'Force Detection'
2007  'Inverted'
2016  'Resolution'
2027  'PS2Mouse readConfigTable: no resolution in config table.  Default is %d\n'
2100  'PS2Mouse: mouse reset\n'
2123  'PS2Mouse: mouse reset after resync\n'
```

**Difference:** seven of the twelve are already present in our source. Five are absent, and we
carry five the reference does not:

| Reference string | Address | Site | Our text |
| --- | --- | --- | --- |
| `initPointer: Can't find PS2Controller (%s)\n` | 1818 | `mouseInit:` 94 | `PS2Mouse.m:530` — `PS2Mouse: Failed to get controller: %s\n` |
| `PS2Mouse readConfigTable: no configuration table\n` | 1941 | `readConfigTable:` 699 | `PS2Mouse.m:318` — `PS2Mouse: No device description provided\n` |
| `PS2Mouse readConfigTable: no resolution in config table.  Default is %d\n` | 2027 | `readConfigTable:` 859 | `PS2Mouse.m:353` — `PS2Mouse: Using default resolution %d\n` |
| `PS2Mouse: mouse reset\n` | 2100 | `_PS2MouseIntHandler` 956 | `PS2Mouse.m:149` — `PS/2 Mouse: Self-test passed response received - re-enabling\n` |
| `PS2Mouse: mouse reset after resync\n` | 2123 | `_PS2MouseIntHandler` 1033 | `PS2Mouse.m:179` — `PS/2 Mouse: Self-test response after timeout - re-enabling\n` |

Note that `initPointer: Can't find PS2Controller (%s)` lives in **`mouseInit:`** (0), not in
`initWithController:` (332) — the reference's `initWithController:` logs only
`PS2Mouse: no PS2Controller present\n` (347) and `PS2Mouse: couldn't find a mouse!\n` (661).
That is exactly how our split is arranged, so the brief's open question about which of the two
holds it is answered: `mouseInit:`, and our split already matches. The reference's message text
still names `initPointer`, a method this class does not have — a leftover from an earlier
revision of Apple's own source, preserved verbatim.

Also note the two-space run in `no resolution in config table.  Default is %d` — it is two
spaces in the reference and must be reproduced exactly.

**Disposition:** fix

**Resolution (Task 4):** fixed. All five strings replaced with the reference's text,
including the two-space run in `no resolution in config table.  Default is %d`. Verified:
`parity_check.py` reports `missing_strings` 0 and `extra_strings` 0 against the reference, and
our `__TEXT,__cstring` is 355 bytes — the reference's size exactly.

## Finding 12: `Load_Commands.sect` is one byte short

**Source:** `src/drivers-i386/input/drvPS2Mouse/PS2Mouse.drvproj/PS2Mouse.lksproj/Load_Commands.sect`

**Reference** `Loaded Server,Load Commands`, 164 bytes:

```
'# \n# This loadable kernel driver does not use a Mig-generated interface,\n# so no handler or server interface is specified.\n#\n# This driver must be wired down.\nWIRE\n'
```

**Ours**, 163 bytes:

```
'#\n# This loadable kernel driver does not use a Mig-generated interface,\n# so no handler or server interface is specified.\n#\n# This driver must be wired down.\nWIRE\n'
```

**Difference:** the reference's first line is `# ` — hash, space, newline. Ours is `#`,
newline. That single missing space is the whole 164-vs-163 difference; the remaining 162 bytes
are identical.

**Disposition:** fix

**Rationale:** a one-character correction to a file Task 2 added, and the difference between a
byte-exact section and a near-miss. The `Loaded Server,Unload Commands` section (102 bytes)
remains unproduced by anything in this repository, as recorded in the baseline-build note
above; that one is out of scope.

**Resolution (Task 4):** fixed. `Load_Commands.sect`'s first line is now `# `. Verified:
the file is 164 bytes and our `Loaded Server,Load Commands` section is 164 bytes, matching the
reference.

## Finding 13: defensive null guards the reference does not have

**Source:** `src/drivers-i386/input/drvPS2Mouse/PS2Mouse.drvproj/PS2Mouse.lksproj/PS2Mouse.m:127`,
`:253`, `:334`, `:367`, `:389`

**Reference behaviour:** `_PS2MouseIntHandler` (915), `-[PS2Mouse isMousePresent]` (184),
`-[PS2Mouse resetMouse]` (295) and `-[PS2Mouse initWithController:]` (405, 451, 462, 480, 491)
all load `_func_list` and immediately dereference it. There is no `test`/`cmp` against zero on
`_func_list` or on any of its slots anywhere in the binary.

**Our source (before Task 3):** four `if (controllerFunctions == NULL)` early returns plus six
per-slot `!= NULL` guards inside `initWithController:`.

**Disposition:** fix

**Rationale:** `_func_list` is set from `[controller controllerAccessFunctions]` before any of
these run, and the reference simply trusts it. The guards were real added code the reference
does not contain. Parity with the shipped binary is the point of this reconstruction, so they
come out.

**Resolution (Task 4):** accepted unchanged at the time. That acceptance is reversed below.

**Correction (follow-up pass):** the Task 4 sentence that the guards were "most" of the 152-byte
`__text` excess was wrong when written. The guards were 76 of those 152 bytes; the other 88
belonged to Findings 15 and 16, now fixed.

**Resolution (Task 3):** fixed. The three `controllerFunctions == NULL` early returns in
`_PS2MouseIntHandler`, `isMousePresent` and `resetMouse` are gone. In `initWithController:`
the drain is now an unguarded `reserved[3]()` call and the 8042 read/mask/write sandwich is
four unguarded slot-0/1/0/4 calls, with no outer `controllerFunctions != NULL` and no
`else { statusByte = 0; }`. `if (controllerDevice == nil)` and `if (!force_detection)` were
left alone; Force Detection was not inverted. `Select-String` for
`controllerFunctions == NULL|controllerFunctions != NULL|reserved[[0-9]] != NULL` has no
matches.

Guest rebuild `fail=0`, staged unstripped `_reloc` 94416 bytes. `--list` against the Task 2
baseline (diffs 11/4/83/133):

| Function | Task 2 | Task 3 |
| --- | --- | --- |
| `-[PS2Mouse isMousePresent]` | 11 / 37 / 39 | **9 / 37 / 37 `masked-eq`** |
| `-[PS2Mouse resetMouse]` | 4 / 13 / 15 | **2 / 13 / 13 `masked-eq`** |
| `-[PS2Mouse initWithController:]` | 83 / 108 / 125 | **35 / 108 / 108** |
| `_PS2MouseIntHandler` | 133 / 120 / 114 | **133 / 120 / 112** |

`--name` confirms `masked_equal=True` for `isMousePresent` and `resetMouse` (the remaining
instruction diffs are `_func_list` vs `_controllerFunctions` and jump targets). Those two
advance to `assembly-matched`. `initWithController:` and `_PS2MouseIntHandler` still differ
and stay `intentional-mismatch` for Task 4/6; the edit is kept even though those extents did
not fully close. Residual on the handler is Finding 14 (`unsigned int` / `return 0`).

Regression gate held: `getHandler:level:argument:forInterrupt:` stayed `masked-eq`,
`getResolution` stayed `identical`, `getIntValues:forParameter:count:` stayed at 7 diffs.

## Finding 14: `_PS2MouseIntHandler` return value and `mouseInit:` initialization set

**Source:** `src/drivers-i386/input/drvPS2Mouse/PS2Mouse.drvproj/PS2Mouse.lksproj/PS2Mouse.m:122`
and `PS2Mouse.m:486`–`509`

**Reference behaviour**

`_PS2MouseIntHandler` never writes `eax` on any exit path — the shared epilogue at 1415 is
`lea esp,[ebp-0x20]; pop ebx; pop esi; pop edi; mov esp,ebp; pop ebp; ret` with no preceding
`xor eax, eax`. It reads its arguments only at `[ebp+8]` and `[ebp+0xc]` and forwards both to
`IOSendInterrupt(identity, state, 0x232325)`.

`-[PS2Mouse mouseInit:]` (10–58) initializes exactly six locations:

```
10  mov byte  ptr [0x4031], 0     ; _seqInProgress
17  mov byte  ptr [0x4030], 0     ; _seqBeingProcessed
24  mov dword ptr [0x4000], 0     ; _indexInSequence
34  mov byte  ptr [0x4026], 0     ; _summedEvent.deltaY
41  mov byte  ptr [0x4025], 0     ; _summedEvent.deltaX
48  mov dword ptr [ebx+0x12c], 0x96  ; resolution = 150
```

**Our source**

```c
static unsigned int PS2MouseIntHandler(unsigned int param_1, unsigned int param_2)
...
    return 0;
```

and in `mouseInit:` we additionally clear `currentPacket`, `nextPacket`, `currentEventTime`,
`lastTimeStamp_low`, `lastTimeStamp_high`, and set `inverted = NO; forceDetection = NO;`.

**Difference:** the handler is a DriverKit `IOInterruptHandler`, which returns `void`; ours
declares `unsigned int` and returns 0. And `mouseInit:` in our source initializes a strict
superset of what the reference does — the reference leaves `_currentEvent`, `_pendingEvent`
and `_lastTimeStamp` untouched and does not pre-set `inverted` or `force_detection`.

**Disposition:** accept

**Rationale:** DriverKit discards the handler's return value, so returning 0 is inert. The
extra `mouseInit:` clears are dead stores: `readConfigTable:` runs on the very next line of the
success path and writes both `inverted` and `force_detection` unconditionally, and the event
buffers are fully overwritten before they are ever read (`_indexInSequence` is zeroed, so the
handler always fills byte 0 first). Recorded because both are real, confirmed differences from
the reference; neither is worth a source change on its own, and Finding 5 will rewrite this
region anyway.

**Resolution (Task 4):** split. The `mouseInit:` half was **fixed** — since Finding 5
rewrote this region anyway, the dead stores went with it, and `mouseInit:` now initializes
exactly the reference's six locations (`seqInProgress`, `seqBeingProcessed`,
`indexInSequence`, `summedEvent.data.buf[2]`, `summedEvent.data.buf[1]`, `resolution = 0x96`)
and no longer pre-sets `inverted` or `force_detection` or clears the event buffers. The
handler-return half was **accepted unchanged** at the time: `PS2MouseIntHandler` still
returned `unsigned int` and still returned 0, which DriverKit discards. Ledger:
`_PS2MouseIntHandler` is `intentional-mismatch` (jointly with Finding 13);
`-[PS2Mouse mouseInit:]` is `control-flow-confirmed` with no residual divergence.

**Resolution (this campaign, Task 4):** Finding 14 handler-return half **fixed**. Do not
reopen the already-fixed `mouseInit:` half. `PS2MouseIntHandler` is now `static void`;
every `return 0` inside the handler is a bare `return`. `-getHandler:…` still assigns
`*handler = (IOInterruptHandler)PS2MouseIntHandler`. Guest rebuild `fail=0`, staged
unstripped `_reloc` 94408 bytes. `--list` vs Task 3: `_PS2MouseIntHandler` 133/120/112 →
**119/120/111**. Rebuilt epilogue is `mov esp,ebp; pop ebp; retn` with no `xor eax,eax`
(the reference never wrote eax either). Not `raw_equal` / `masked_equal`; leftover is
Task 6. `--name` (prologue + epilogue):

```
_PS2MouseIntHandler
  status=different raw_equal=False masked_equal=False
  reason: calls differ
  reason: cfg differs
  reason: function range bytes differ
  reason: instruction shape differs

  reference                               rebuilt
  push ebp                                push ebp
  mov ebp, esp                            mov ebp, esp
* sub esp, 14h                            sub esp, 0Ch
* push edi
* push esi
  push ebx                                push ebx
* mov edi, [ebp+arg_0]                    mov edx, ds:_controllerFunctions
* mov esi, [ebp+arg_4]
* mov edx, ds:_func_list
  ...
* lea esp, [ebp-20h]
* pop ebx
* pop esi
* pop edi
  mov esp, ebp                            mov esp, ebp
  pop ebp                                 pop ebp
  retn                                    retn
```

Residual diffs are `_func_list` vs `_controllerFunctions`, the smaller frame (no
edi/esi save), timestamp spill, and inverted `seqBeingProcessed` branch layout.

## Finding 15: the parameter-name compares are `strcmp`, not a hand-unrolled loop

**Source:** `src/drivers-i386/input/drvPS2Mouse/PS2Mouse.drvproj/PS2Mouse.lksproj/PS2Mouse.m:508`
and `PS2Mouse.m:526`

**Reference behaviour** — `getIntValues:` at 1536, verified by disassembling `PS2Mouse_reloc`:

```
1553  mov  edi, 0x7e0           ; "Resolution"
1558  mov  ecx, 0xb             ; strlen("Resolution") + 1
1563  cld
1564  test al, 0
1566  repe cmpsb
1568  jne  0x62c
...
1582  mov  edi, 0x7d7           ; "Inverted"
1587  mov  ecx, 9               ; strlen("Inverted") + 1
1592  cld
1593  test al, 0
1595  repe cmpsb
1597  je   0x648
```

`setIntValues:` at 1632 does the same, except that gcc spilled the first count: `mov [ebp-4],
0xb; mov ecx, [ebp-4]`. `RESOLUTION` and `INVERTED` resolve, in `src/kernel-7/bsd/dev/i386/
PCPointer.h:42-43`, to `"Resolution"` and `"Inverted"` — 11 and 9 bytes with the terminating NUL.

**Our source (before):** a hand-unrolled character-compare loop — `i = 11; do { if (i == 0)
break; i--; match = (*param == *key); param++; key++; } while (match);` — which gcc emitted as
`dec ebx; mov al,[ecx]; cmp [edx],al; sete al`.

**Difference:** a fixed-length `repe cmpsb` whose result is tested only for zero is gcc inlining
`strcmp` against a string constant. Our loop reproduced the semantics but not the code: it cost
`getIntValues:` +32 bytes and `setIntValues:` +32 of its +56.

**Disposition:** FIX

**Resolution (follow-up pass):** fixed. Both methods now use `strcmp(parameterName, RESOLUTION)
== 0` / `strcmp(parameterName, INVERTED) == 0`, the same shape as drvBusMouse. The rebuilt
`getIntValues:` is **exactly** the reference's 96 bytes and its instruction stream matches the
reference one for one — same opcodes, same encoding lengths, `repe cmpsb` at 11 then 9 — the only
byte differences being the scratch register gcc chose for the value (`eax` where the reference
used `edx`) and the `__cstring` addresses. Ledger: `assembly-matched`.

## Finding 16: `setIntValues:` messages `target` unconditionally

**Source:** `src/drivers-i386/input/drvPS2Mouse/PS2Mouse.drvproj/PS2Mouse.lksproj/PS2Mouse.m:526`
(the guards were at `:589` and `:615` before the fix)

This is Finding 10 re-decided. Finding 10 recorded the divergence correctly and then accepted it;
the follow-up pass rejects that acceptance.

**Reference behaviour** — both branches of `setIntValues:` fall through to one shared tail at
1753 that loads `target` from `[ebx+0x128]` and calls `objc_msgSend`. There is no `test` or `cmp`
of that ivar anywhere in the function; the `Resolution` branch jumps straight into the tail from
1702 and the `Inverted` branch falls into it from 1751.

**Our source (before):** `if (target != nil) { [target setResolution:…]; }` and
`if (target != nil) { [target setInverted:…]; }`.

**Difference:** two branches the reference does not have — the remaining +24 of `setIntValues:`'s
+56, on top of Finding 15's +32.

**Disposition:** FIX

**Rationale:** the guards are behaviourally inert (messages to `nil` are no-ops returning 0), so
this is purely a parity question, and parity with the shipped binary is the object of the
exercise. drvBusMouse's `setIntValues:`, verified against its own reference, sends
unconditionally.

**Resolution (follow-up pass):** fixed. Both guards removed. `setIntValues:` went from 204 bytes
to 136 and its rebuilt stream was disassembled and read against the reference at 1632–1777: every
instruction corresponds — `repe cmpsb` at 11 and 9, `resolution` written to `+0x12C` and re-read
through `[self getResolution]`, `inverted` written to `+0x130` and forwarded sign-extended, and
the single unguarded `objc_msgSend` to `target` at `+0x128` shared by both branches.

**Residual, accepted:** ours is now 12 bytes **smaller** than the reference's 148, because gcc
hoists the `parameterArray` load into the prologue and keeps the compare count as an immediate
where the reference spilled both to the stack (`sub esp,4`; `mov [ebp-4],0xb`; `mov ecx,[ebp-4]`;
and two reloads of `[ebp+0x10]`). That is a code-generation difference with no source-level
counterpart, and drvBusMouse's verified `setIntValues:` lands on the identical 136. Ledger:
`-[PS2Mouse setIntValues:forParameter:count:]` stays `intentional-mismatch`, reviewed by Pat
Raynor, with its reason rewritten from the now-obsolete nil-guard text to this one.

## Functions examined with no divergence found

Instruction-level match (`assembly-matched` in the ledger):
`-[PS2Mouse getHandler:level:argument:forInterrupt:]` (1480),
`-[PS2Mouse getResolution]` (1520), and — since the follow-up pass —
`-[PS2Mouse getIntValues:forParameter:count:]` (1536), whose stream was re-read against the
reference after Finding 15 was fixed. The first two still carry declaration-level
divergences recorded under Finding 2 (`getResolution` returns `int` not `unsigned int`;
`getHandler:`'s `argument:` is `unsigned int *` not `void **`), and `getResolution`'s single
`mov eax, [eax+0x12c]` only lands on the right ivar once Finding 1 is applied. Neither
divergence appears in the code, which is why the status is `assembly-matched` rather than
`unexamined`.

No function in this driver was reviewed at control-flow level only.

## Phase 1 baseline

2026-09-16 guest rebuild of the current tree, no `PS2Mouse.m` edits. Live
`System.framework` has no `PrivateHeaders`; `gnumake` was given bootstrap-root
`-I` for `Versions/B/PrivateHeaders` and `Versions/B/Headers`. Guest log:
`=== input-recon done fail=0 built: drvPS2Mouse ===`. Staged unstripped
`PS2Mouse_reloc` is **94604** bytes, SHA-256
`78273466617EE2960E4912D22F386BDBA295DB7863E985D172A1D063B3899473`.
`parity_check.py`: `missing_strings` **0**, `missing_symbols` **0**,
`extra_strings` **0**, `extra_symbols` **16**. This `_reloc` is not kept as
the campaign result; `rebuilt_sha256` is unchanged. Finding 13/14/VERS are
still in source. See `function-worklist.md`.

## Task 3: Finding 13 guards dropped

2026-09-16 guest rebuild after removing every `controllerFunctions` null guard.
Guest log: `=== input-recon done fail=0 built: drvPS2Mouse ===`. Staged unstripped
`PS2Mouse_reloc` is **94416** bytes, SHA-256
`6817E812FFD0B853FB403D58FC6C883AF2544DF63AE59669A73C91B4486E8365`.
`parity_check.py`: `missing_strings` **0**, `missing_symbols` **0**,
`extra_strings` **0**, `extra_symbols` **16**. Finding 14's handler return and the
missing `VERS_OFILE` line are still in source. See `function-worklist.md`.

## Task 4: Finding 14 handler declared void

2026-09-16 guest rebuild after changing `PS2MouseIntHandler` to `static void` and
replacing every `return 0` in the handler with `return`. Guest log:
`=== input-recon done fail=0 built: drvPS2Mouse ===`. Staged unstripped
`PS2Mouse_reloc` is **94408** bytes, SHA-256
`30CB12E57AB8774148915AA5954328A0C644D66407343ECA8877C0F350DBBA94`.
`parity_check.py`: `missing_strings` **0**, `missing_symbols` **0**,
`extra_strings` **0**, `extra_symbols` **16**. Finding 14 handler-return half is
**fixed**; the `mouseInit:` half was already fixed and was not reopened. Residual
on `_PS2MouseIntHandler` (119 diffs, not masked-eq) is left for Task 6. The
missing `VERS_OFILE` line is still in source. See `function-worklist.md`.

## Task 5: Kernel Server `VERS_OFILE` postamble

2026-09-16 guest rebuild after creating
`PS2Mouse.lksproj/Makefile.postamble` as the single line
`OTHER_GENERATED_OFILES += $(VERS_OFILE)`. No Driver-project postamble, no
`PS2Mouse.m` edit, no `driverTools` edit. Guest log:
`=== input-recon done fail=0 built: drvPS2Mouse ===`. Staged unstripped
`PS2Mouse_reloc` is still **94408** bytes, SHA-256
`30CB12E57AB8774148915AA5954328A0C644D66407343ECA8877C0F350DBBA94` — identical
to Task 4, because nothing that `kl_ld` consumes changed.

Gate **unmet.** `__TEXT,__const` is still absent. `_PS2Mouse_VERS_STRING` and
`_PS2Mouse_VERS_NUM` are both **MISSING**. Guest evidence:

- `kl_ld` linked `PS2Mouse.o` and `PS2Mouse_instance.o` only; no `PS2Mouse_vers.o`.
- Object dir has `PS2Mouse.o` / `PS2Mouse_instance.o` (and `.i386.o`); no `*vers*`.
- Derived src has `PS2Mouse_instance.m` only; no `PS2Mouse_vers.c`.
- `/System/Developer/Makefiles/VersioningSystems` has `apple-generic.make` and
  `next-cvs.make` only. There is no `next-sgs.make` there or under
  `pb_makefiles`. `common.make` `-include`s `$(VERSIONING_SYSTEM).make`; with
  that file missing, `$(VERS_OFILE)` expands empty, so the postamble appends
  nothing.

No remaining local makefile fix: setting `VERSIONING_SYSTEM = next-sgs` in this
driver would still include a file the guest does not have. Installing
`next-sgs.make` is a guest-installed makefile / `driverTools` change, which this
task forbids. **Accepted.** Do not compare the 160-byte string to Apple's.

`--list` is unchanged vs Task 4 (same SHA). Regression gate held:
`getHandler:…` `masked-eq`, `getResolution` `identical`, `getIntValues:` still
7 diffs, `isMousePresent` and `resetMouse` `masked-eq`. See
`function-worklist.md`.

## Task 6: cheapest-first grinding

2026-09-17. Guest rebuild `fail=0` after the kept `readConfigTable:` edit.
Staged unstripped `_reloc` **94408** bytes, SHA-256
`948DCB8066528D89F8E83B03C62B988769A9B92A0DFF6C2DF6B40AFB989EE771`.
`parity_check.py`: `missing_strings` **0**, `missing_symbols` **0**,
`extra_strings` **0**, `extra_symbols` **16**. Glue is still only the two
generated `+[` methods.

Regression gate held: `getHandler:…` `masked-eq`, `getResolution` `identical`,
`isMousePresent` `masked-eq`, `resetMouse` `masked-eq`, `interruptOccurred`
`masked-eq`, `getIntValues:` stayed at 7 diffs.

### `-[PS2Mouse getIntValues:forParameter:count:]` — accepted, compiler-shaped

`--name` before any Task 6 edit. Same prologue, `repe cmpsb` at 11 then 9,
`IO_R_UNSUPPORTED` (`0xFFFFFD39`), offsets `+12Ch` / `+130h`. Leftover is
register allocation:

```
  reference                               rebuilt
* mov edx, [edx+12Ch]                     mov eax, [edx+12Ch]
* movsx edx, byte ptr [edx+130h]          movsx eax, byte ptr [edx+130h]
* mov [ebx], edx                          mov [ebx], eax
```

Jump labels differ only as layout. No missing call, no wrong offset. Did not
add dummy locals. Ledger: `intentional-mismatch`, reviewer Pat Raynor. This
reverses the earlier `assembly-matched` claim; IDA still shows 7 diffs.

### `-[PS2Mouse readConfigTable:]` — matched

`--name` showed inverted NULL/`y`/`Y` branch layout (ours `jz` to store 1 and
an inline store-0; reference `jnz` to store 0 with store-1 fall-through).
Force Detection sense was not inverted.

Experiment: rewrite both Force Detection and Inverted to the positive form
already used by drvBusMouse:

```
if ((str != NULL) && ((*str == 'y') || (*str == 'Y'))) {
    flag = YES;
} else {
    flag = NO;
}
```

Kept. `--list` 18/65 → **12/65 `masked-eq`**. `--name` `masked_equal=True`;
remaining diffs are jump labels. Commit
`drvPS2Mouse: match readConfigTable y/Y branch layout to the reference`.
Declaration-order experiment not tried; not needed.

### `-[PS2Mouse setIntValues:forParameter:count:]` — accepted, gcc spill

`--name` is the 12-byte spill already recorded under Finding 16. Ours is
smaller (49 vs 53 instructions). Reference has `sub esp, 4`,
`mov [ebp+var_4], 0Bh; mov ecx, [ebp+var_4]`, and reloads of `[ebp+arg_8]`
(`parameterArray`). Ours hoists `parameterArray` into `eax` and keeps the
compare count as `mov ecx, 0Bh`. Same calls (`getResolution`, shared
`setResolution:`/`setInverted:` tail), same constants (11, 9, `0xFFFFFD39`),
same offsets (`+12Ch`, `+130h`, `+128h`). No dummy spills. Ledger stays
`intentional-mismatch`, reviewer Pat Raynor.

### `-[PS2Mouse mouseInit:]` — accepted unreachable

`--name` store order already matches:

```
mov ds:_seqInProgress, 0
mov ds:_seqBeingProcessed, 0
mov ds:_indexInSequence, 0
mov ds:byte_4026, 0          ; summedEvent.deltaY
mov ds:byte_4025, 0          ; summedEvent.deltaX
mov dword ptr [ebx+12Ch], 96h
```

Starter list items (2) BOOL as 0 and (3) resolution as 150 do not match the
dump: the stores are already 0 and `0x96`. Leftover is gcc layout of
`if (result != IO_R_SUCCESS) { IOLog(...); return NO; }` — reference `jz`
over an inline error path, ours `jnz` to a trailing one — plus the same
inversion on `readConfigTable:`. Same calls (`IOGetObjectForDeviceName`,
`stringFromReturn:`, `IOLog`, `configTable`, `readConfigTable:`,
`initWithController:`), same constants, same offsets. Empty list.
Accepted unreachable. Ledger: `intentional-mismatch`, reviewer Pat Raynor.

### `-[PS2Mouse initWithController:]` — tried and/or split, then accepted

`--name` leftover after Tasks 3–5: `_func_list` vs `_controllerFunctions`,
`isMousePresent` fail-path `jz` to a trailing cleanup vs `jnz` over an
inline one, and 8042 mask codegen (`and bl, 0DFh; or bl, 2; movzx eax, bl`
vs `mov eax, ebx; or al, 2; and eax, 0DFh`). Packet/8042 order (0x20 read,
read byte, 0x60 write, write data) already matches. Force Detection was
not inverted.

Tried: split the mask into `statusByte &= 0xDF; statusByte |= 0x02` after
the command-byte read, then pass `statusByte`. Guest rebuild `fail=0`,
reloc 94432 bytes. `--list` `initWithController:` 35→30, not `masked-eq`.
Gates held. **Reverted.** Marked tried.

Remaining diffs are compiler/ABI-shaped (`_func_list` name, fail-path
scheduling, and/or that the split did not close). Empty list. Accepted
unreachable. Ledger: `intentional-mismatch`, reviewer Pat Raynor.

### `_PS2MouseIntHandler` — accepted, compiler/ABI-shaped

`--name` leftover is `_func_list` vs `_controllerFunctions`, frame
(`sub esp, 14h` + `push edi`/`push esi` vs `sub esp, 0Ch` + `ebx` only),
timestamp copy through extra stack slots, and inverted
`seqBeingProcessed` `jz`/`jnz`. Did not reorder resync / timeout /
`seqBeingProcessed` / `seqInProgress` branches. Did not add dummy locals.
Accepted as compiler/ABI-shaped. Ledger: `intentional-mismatch`,
reviewer Pat Raynor.

### Already matching (skipped)

`getHandler:level:argument:forInterrupt:` `masked-eq`, `getResolution`
`identical`, `interruptOccurred` `masked-eq` (promoted to
`assembly-matched` in the ledger), `isMousePresent` `masked-eq`,
`resetMouse` `masked-eq`. Both `+[` glue methods stay generated.
