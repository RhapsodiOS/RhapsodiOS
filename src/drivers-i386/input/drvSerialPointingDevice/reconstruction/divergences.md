# drvSerialPointingDevice divergences

Reference: `SerialPointingDevice_reloc`, SHA-256 `59C0C95C5A4D93456BDD6667970AC4A3605A961FEAC2CF7CE97F586D3A958F59`
Analyses: IDA 9.2, angr 9.3.0

## Stated limitation: two analyzers, not three

**Ghidra is disabled in this driver's profile** (`tools/binrecon/profiles/serialpointingdevice.json`,
`analyzers.ghidra.enabled: false`). With Ghidra enabled, normalization aborts with
`Ghidra relocation operand metadata is ambiguous` (`tools/binrecon/binrecon/normalize.py:432`),
leaving `complete: false` and no consensus. That is a known binrecon limitation, approved by the
user, and not something this pass works around. The consequences for the evidence in this
document are:

- `tools/binrecon/out/serialpointingdevice/published/` holds `analysis-reference-ida.json`,
  `analysis-reference-angr.json` and `consensus-reference.json`. There is **no**
  `analysis-reference-ghidra.json`.
- `run-summary.json`'s `analyzers` list has two entries, and every `analyzer_agreement.analyzers`
  in `ledger.json` reads `["IDA", "angr"]`.
- The analyzer-disagreement section below compares **IDA against angr only**. A partition claim
  that Ghidra would have corroborated in drvPS2Mouse rests here on two analyzers.

The analyze run itself was performed and verified by the controller; this pass confirmed the
existing state rather than re-running it. `run-summary.json` reports `complete: true` and
`reference_sha256` `59C0C95C…`, matching the plan's table.

## Baseline build

**No baseline build is recorded here.** The driver compiles today, but the fix pass (Task 6)
establishes the baseline properly — staged `SerialPointingDevice_reloc` size and the four
`parity_check.py` counts — and no size is invented in this document.

Three scaffolding facts are recorded now so the fix pass can check them:

- `Load_Commands.sect` **is** present in
  `SerialPointingDevice.drvproj/SerialPointingDevice.lksproj/` and is named in that directory's
  `Makefile` `OTHERSRCS`, so the plan's blanket note that this driver has no such file is out of
  date. It is **163 bytes** where the reference's `Loaded Server,Load Commands` section is
  **164**. See Finding 14.
- The reference carries a `Loaded Server,Unload Commands` section of **102 bytes**
  (`"# \n# This loadable kernel driver is not unloadable. (I think) this file\n# is still
  necessary.\n#\n\n\n\n\n\n\n"`). Nothing in this repository produces that section. Closing the
  gap is a build-system change the spec puts out of scope; recorded, not fixed.
- The reference carries a `__TEXT,__const` section of **170 bytes** holding
  `_SerialPointingDevice_VERS_STRING` (160 bytes at 5330) and `_SerialPointingDevice_VERS_NUM`
  (10 bytes at 5490). Those are emitted by NeXT's `vers_string` machinery, not written by hand,
  and no driver in this repository produces them. Same class of gap as `Unload Commands`;
  recorded, not fixed.

The reference's other `Loaded Server` sections are `Server Name` 20 (`SerialPointingDevice`),
`Instance Var` 29 (`SerialPointingDevice_instance`) and `Server Version` 1 (`2`).

## Summary

| Bucket | Count |
| --- | --- |
| mapped | 16 |
| unmapped | 2 |
| duplicate_candidates | 0 |
| boundary_disputed | 0 |

**All 18 reference functions were read at instruction level.** Every instruction of the full
4468-byte `__TEXT,__text` section was disassembled from the published IDA analysis, annotated
with its relocation targets (selector names, string literals, data symbols and ivar offsets),
and compared line by line against `SerialPointingDevice.m`. Nothing in this driver was reviewed
at control-flow level only, and nothing was reviewed by grep or by name.

Of the 16 mapped functions, **5** have instruction streams that reproduce the reference exactly
and are `assembly-matched` in the ledger:

| Address | Function |
| --- | --- |
| 1016 | `-[SerialPointingDevice getResolution]` |
| 3700 | `-[SerialPointingDevice MPlusProtocol]` |
| 4324 | `-[SerialPointingDevice MMProtocol]` |
| 4364 | `-[SerialPointingDevice RBProtocol]` |
| 4404 | `-[SerialPointingDevice UnknownProtocol]` |

All five nonetheless depend on Finding 1 for their ivar offsets (`0x12c` in `getResolution`,
`0x154` in the three terminating protocol handlers) and on Finding 4 for `_active`'s linkage;
neither of those differences appears in the emitted instruction stream, which is why the status
is `assembly-matched` rather than `unexamined`. `getResolution` additionally carries the
declaration-level return-type divergence recorded under Finding 2.

The remaining **11** each carry at least one confirmed body divergence and stay `unexamined` in
the ledger, per the convention that a diverging function is left for the fix pass. The 2 unmapped
glue methods are `intentional-mismatch`.

Beyond the function bodies, the object's Objective-C metadata was decoded directly from the
Mach-O (`__class`, `__meta_class`, `__instance_vars`, `__inst_meth`, `__cls_meth`,
`__meth_var_types`, `__class_names`, `__DATA,__data`, `__TEXT,__cstring`) and compared against
`SerialPointingDevice.h` / `SerialPointingDevice.m`. Findings 1, 2, 3 and 4 come from that
metadata rather than from any single function body, and Finding 1 is the largest divergence in
this driver.

## Function partition: sizes

The brief's partition table lists sizes as the gaps between consecutive symbol addresses
(28, 880, 108, 16, 72, 96, 264, 308, 104, 1380, 444, 24, 600, 40, 40, 40, 12, 12). IDA reports
the function extents with the inter-function `nop` alignment padding excluded (26, 880, 105, 16,
72, 93, 263, 305, 103, 1379, 442, 22, 598, 40, 40, 40, 12, 12). Addresses and names agree
exactly. IDA is authoritative for the partition, so `source-map.json` and `ledger.json` carry
IDA's extents. This is a padding accounting difference, not an analyzer disagreement.

## Unmapped: build-generated

`+[SerialPointingDeviceKernelServerInstance kernelServerInstance]` (4444) and
`+[SerialPointingDeviceVersion driverKitVersionForSerialPointingDevice]` (4456) are emitted by
the Kernel Server project type and `Load_Commands.sect`, not written by hand. Accepted.

The first returns `&_SerialPointingDevice_instance` (`__DATA,__common`, 8244); the second
returns `500` (0x1F4). Their owning classes come from the same generated glue: `__class`
declares `SerialPointingDeviceVersion : IODevice` (instance_size 264) and
`SerialPointingDeviceKernelServerInstance : Object` (instance_size 4), and `__class_names`
carries the generated translation unit name `SerialPointingDevice_instance.m` alongside the
hand-written `SerialPointingDevice.m`. `__cls_meth` holds two one-entry method lists —
`driverKitVersionForSerialPointingDevice` typed `i8@8:12` and `kernelServerInstance` typed
`^^{?}8@8:12`.

`_SerialPointingDevice_VERS_STRING` (5330, `__const`), `_SerialPointingDevice_VERS_NUM` (5490,
`__const`) and `_SerialPointingDevice_instance` (8244, `__common`) are data symbols outside
`__TEXT,__text` and therefore do not appear anywhere in the source map, which lists functions
only. Neither do `_mouseTypeList` (8192), `_protocolList` (8216) or `_active` (8240), which live
in `__DATA,__data`.

## Analyzer disagreement

**There is none about the partition.** IDA and angr agree on all 18 function addresses and on all
18 sizes, byte for byte. No boundary is disputed; `boundary_disputed` and `duplicate_candidates`
are both empty.

**angr reports 57 functions where IDA reports 18.** The 39 extra entries are:

- **38 one-to-three-byte fragments** sitting on inter-function and intra-function `nop` alignment
  padding, at 26, 61, 238, 355, 470, 686, 867, 1013, 1083, 1146, 1174, 1197, 1330, 1463, 1563,
  1769, 1875, 2483, 2511, 2715, 2738, 2751, 2790, 2817, 2841, 2939, 2971, 2987, 3218, 3255, 3377,
  3387, 3410, 3477, 3686, 3698, 3722 and 4322. Each sits immediately after a `jmp` and immediately
  before the next basic block, which is where NeXT's assembler pads to a 4-byte boundary.
- **one entry covering the `__const` data symbol** `_SerialPointingDevice_VERS_NUM` (5490,
  10 bytes), which is not code at all.

angr also splits basic blocks more finely than IDA inside the real functions — 70 blocks against
IDA's 37 in `-[SerialPointingDevice mouseInit:]`, 96 against 55 in `-[SerialPointingDevice
detect]`, 31 against 20 in `-[SerialPointingDevice FiveBProtocol]`. The `calls` lists are
identical in every function. None of this is a partition disagreement, and per the convention
IDA is authoritative, so none of it affects the source map.

## Configuration table

`src/drivers-i386/input/drvSerialPointingDevice/SerialPointingDevice.drvproj/Default.table`
diffs clean against
`C:\Users\raynorpat\Downloads\test\Drivers\i386\SerialPointingDevice.config\Default.table`
ignoring `"Driver Version"` — that key is the only line that differs, and it is emitted by
Apple's build. There is no Task 2 defect here.

---

## Finding 1: `SerialPointingDevice` derives from `PCPointer`, not `IODirectDevice`

**Source:** `src/drivers-i386/input/drvSerialPointingDevice/SerialPointingDevice.drvproj/SerialPointingDevice.lksproj/SerialPointingDevice.h:47`

**Reference metadata**

`__class` (decoded, 40-byte stride, 3 entries):

```
SerialPointingDevice                     : PCPointer   instance_size = 356 (0x164)
SerialPointingDeviceVersion              : IODevice    instance_size = 264
SerialPointingDeviceKernelServerInstance : Object      instance_size = 4
```

`__instance_vars` (76 bytes, 6 entries):

```
ivar "verbose"       type "c"                          offset 324 (0x144)
ivar "mainThread"    type "^v"                         offset 328 (0x148)
ivar "mouseType"     type "i"                          offset 332 (0x14c)
ivar "protocol"      type "i"                          offset 336 (0x150)
ivar "portDevice"    type "@"                          offset 340 (0x154)
ivar "pointerEvent"  type "{?=\"timeStamp\"Q\"data\"(?)}" offset 344 (0x158)
```

`__class_names` is `SerialPointingDevice`, `PCPointer`, `Object`, `SerialPointingDevice.m`,
`SerialPointingDeviceVersion`, `IODevice`, `SerialPointingDeviceKernelServerInstance`,
`SerialPointingDevice_instance.m`. The Objective-C class references in the symbol table are
`.objc_class_name_PCPointer`, `.objc_class_name_IODevice` and `.objc_class_name_Object` — there
is **no reference to `IODirectDevice` anywhere in the object**.

**Our source**

```objc
typedef struct {
    unsigned int timestamp_low;
    unsigned int timestamp_high;
    unsigned char buttons;
    char deltaX;
    char deltaY;
} MouseEvent;

@interface SerialPointingDevice : IODirectDevice
{
@private
    id mouseEventPort;
    unsigned int resolution;
    BOOL inverted;
    BOOL verbose;
    void *mainLoopThread;
    int mouseType;
    int protocolType;
    id serialPortObject;
    MouseEvent mouseEvent;
}
```

**Difference:** the reference class owns exactly six ivars, all at 0x144 and above. Everything
below that comes from `PCPointer`:

| Offset | Reference ivar | Owner | Our declaration |
| --- | --- | --- | --- |
| 0x128 | `target` | `PCPointer` | `mouseEventPort` (own) |
| 0x12c | `resolution` | `PCPointer` | `resolution` (own) |
| 0x130 | `inverted` | `PCPointer` | `inverted` (own) |
| 0x134–0x143 | `_reserved[4]` | `PCPointer` | absent |
| 0x144 | `verbose` | `SerialPointingDevice` | `verbose` |
| 0x148 | `mainThread` | `SerialPointingDevice` | `mainLoopThread` |
| 0x14c | `mouseType` | `SerialPointingDevice` | `mouseType` |
| 0x150 | `protocol` | `SerialPointingDevice` | `protocolType` |
| 0x154 | `portDevice` | `SerialPointingDevice` | `serialPortObject` |
| 0x158 | `pointerEvent` | `SerialPointingDevice` | `mouseEvent` |

`PCPointer` is already in this repository at `src/kernel-7/bsd/dev/i386/PCPointer.h` /
`PCPointer.m`, declared as `@interface PCPointer : IODirectDevice { id target; unsigned
resolution; BOOL inverted; @private int _reserved[4]; }`. That layout puts `target` at 0x128,
`resolution` at 0x12c, `inverted` at 0x130 and `_reserved` at 0x134–0x143 on top of a 0x128-byte
`IODirectDevice`, which is exactly the reference's layout. The in-tree `PCPointer.h` is a
byte-exact match for the base class Apple compiled against, and this is the same structural
finding drvPS2Mouse recorded — the pattern repeats.

Our declarations produce an instance size of 0x150 (336): they omit `_reserved[4]` and pack
`verbose` immediately after `inverted`, so **every ivar from `verbose` onwards is at the wrong
offset**, and the header's own offset comments (`// Offset 0x144`, `// Offset 0x158`) describe a
layout the code does not actually produce.

The `pointerEvent` type encoding `{?="timeStamp"Q"data"(?)}` is `PCPointerEvent`, which
`src/kernel-7/bsd/dev/i386/PCPointerDefs.h` already declares as an 8-byte `ns_time_t timeStamp`
followed by a 4-byte union whose `data.buf[0..2]` are the buttons and the X and Y deltas —
12 bytes, and 0x158 + 12 = 0x164 = 356, the reference's `instance_size` exactly. Our hand-rolled
`MouseEvent` typedef in `SerialPointingDevice.h:39` is a redeclaration of that type with
different member names and a different encoding.

Four ivar names also differ verbatim in `__instance_vars`: `mainLoopThread` vs `mainThread`,
`protocolType` vs `protocol`, `serialPortObject` vs `portDevice`, `mouseEvent` vs `pointerEvent`.

**Disposition:** fix

**Rationale:** this is the root divergence in the driver. Every ivar offset in every function
body depends on it, so no function's emitted code can match until the hierarchy matches.
Re-parenting to `PCPointer` removes three of our nine ivar declarations (they become inherited),
supplies `PCPatoi` (Finding 6), supplies the `PCPointerEvent` type, and supplies the `RESOLUTION`
/ `INVERTED` key macros. The work is not speculative: the base class is already in the tree and
its layout is confirmed against the binary. **It must land in the same change as Finding 2**, for
the reason Finding 2 gives.

## Finding 2: method return types, signatures and the `mainLoop` return value

**Source:** `SerialPointingDevice.h:62`–`92` and `SerialPointingDevice.m:71`, `:280`, `:532`,
`:540`, `:556`, `:593`

**Reference metadata**

`__inst_meth` (15 entries, name and type encoding):

```
UnknownProtocol                  v8@8:12
RBProtocol                       v8@8:12
MMProtocol                       v8@8:12
FiveBProtocol                    v8@8:12
MPlusProtocol                    v8@8:12
MSProtocol                       v8@8:12
detect                           c8@8:12
getByte:sleep:                   c13@8:12*16c20
mainLoop:                        ^?12@8:12@16
setIntValues:forParameter:count: i20@8:12^I16*20I24
getIntValues:forParameter:count: i20@8:12^I16*20^I24
setEventTarget:                  c12@8:12@16
getResolution                    i8@8:12
free                             @8@8:12
mouseInit:                       c12@8:12@16
```

Confirmed in the code:

- `-[SerialPointingDevice mouseInit:]` ends `mov eax, 1` on the success path (860) and
  `xor eax, eax` (896) on every one of its six failure paths.
- `-[SerialPointingDevice setEventTarget:]` (1032) is `xor eax, eax` when
  `[super setEventTarget:]` returns false (1079) and `mov eax, 1` when it succeeds (1090).
- `-[SerialPointingDevice mainLoop:]` ends `xor eax, eax` (1760) — it writes `eax` before
  returning.
- `_mainLoop`, the C function at 0, likewise ends `xor eax, eax` (20) after its single
  `objc_msgSend`.
- `-[SerialPointingDevice getByte:sleep:]` reads its `sleep:` argument as a byte
  (`mov bl, [ebp+arg_C]`, 1787) and stores through its first argument a byte at a time
  (`mov [edi], dl`, 1839).

**Our source**

```objc
static void mainLoop(id driver);
- (IOReturn)mouseInit:(IODeviceDescription *)deviceDescription;
- (unsigned int)getResolution;
- (void)setEventTarget:(id)target;
- (BOOL)getByte:(unsigned char *)byte sleep:(BOOL)shouldSleep;
- (void)mainLoop:(id)arg;
```

**Difference:**

- `mouseInit:` returns **`BOOL`** in the reference, with **1 = success, 0 = failure**. Ours
  returns `IOReturn`, with **0 (`IO_R_SUCCESS`) = success** and `IO_R_BUSY` /
  `IO_R_INVALID_ARG` / `IO_R_NOT_FOUND` = failure. **The polarity is inverted**: our successful
  `mouseInit:` returns 0, which a `BOOL`-expecting caller reads as failure, and our
  `IO_R_BUSY` failure returns a nonzero value, which reads as success.
- `setEventTarget:` returns **`BOOL`** in the reference, propagating what `[super
  setEventTarget:]` returned. Ours returns `void` and discards the result. This is a body
  difference, not only a declaration difference: our emitted code cannot contain the
  `xor eax, eax` / `mov eax, 1` pair at 1079/1090.
- `getResolution` returns **`int`** (`i8@8:12`). Ours returns `unsigned int`, which would encode
  as `I8@8:12`. This one does not appear in the emitted code.
- `mainLoop:` is typed `^?12@8:12@16` — it returns a function pointer, and the body writes
  `eax = 0` before returning. Ours returns `void`, which would encode `v12@8:12@16` and would
  not emit the `xor eax, eax`.
- The C function `mainLoop` likewise returns 0 in the reference; ours is declared `static void`
  and would not emit the `xor eax, eax` at 20.
- `getByte:sleep:`'s first parameter is encoded `*` — `char *`. Ours declares
  `unsigned char *byte`, which encodes as `^C`. The emitted store is a byte store either way;
  only the type metadata differs.

**Disposition:** fix

**Rationale:** the `mouseInit:` polarity is not cosmetic. `PCPointer` is what calls `mouseInit:`,
and `PCPointer.h:70` declares it `- (BOOL)mouseInit:deviceDescription`. Once Finding 1 re-parents
the class, our current `IOReturn` return would report every successful probe as a failure and the
duplicate-instance rejection as a success. `PCPointer.h` also declares
`- (BOOL)setEventTarget:eventTarget` and `- (int)getResolution` with exactly the reference's
types, so all three corrections arrive with the re-parenting and **must land in the same change
as Finding 1**, not after it.

## Finding 3: `_mouseTypeList` slot 3 is `W`, not `M` — SETTLED from `detect`

**Source:** `SerialPointingDevice.m:50`

**Reference data.** `__DATA,__data` at 8192 holds six `char *`, decoded through their
relocations:

```
8192  _mouseTypeList[0] -> "UNKNOWN"
8196  _mouseTypeList[1] -> "M"
8200  _mouseTypeList[2] -> "V3"
8204  _mouseTypeList[3] -> "W"
8208  _mouseTypeList[4] -> "W3"
8212  _mouseTypeList[5] -> "C"
```

(The `__cstring` emission order — `C`, `W3`, `W`, `V3`, `M`, `UNKNOWN` at 4468–4487 — is the
reverse of the array order, which is expected and is not itself a divergence.)

**Reference behaviour — every site in `-[SerialPointingDevice detect]` that writes `mouseType`:**

```
2461  mov dword ptr [esi+14Ch], 1   ; saw 'M'  (0x4D) with mouseType == 0; also protocol = 1
2499  mov dword ptr [esi+14Ch], 2   ; saw '3'  (0x33) with mouseType == 1
2829  mov dword ptr [esi+14Ch], 3   ; 4-byte "*?" reply completed and mouseType == 1
2844  mov dword ptr [esi+14Ch], 4   ; 4-byte "*?" reply completed and mouseType != 1
2972  mov dword ptr [esi+14Ch], 5   ; (byte & 0xBF) == 0x0F on the baud-rate sweep
```

and the case-3 dispatch that reaches 2829/2844:

```
2820  cmp  dword ptr [esi+14Ch], 1  ; mouseType
2827  jnz  loc_B1C                  ;   -> 2844, mouseType = 4
2829  mov  dword ptr [esi+14Ch], 3
```

**Answer.** `W` is the name for **a mouse that identified itself with a bare `M` — no `3` — and
then answered the `*?` capability query**. The five reachable values name a systematic 2×2 plus
one:

| `mouseType` | Name | Reached when |
| --- | --- | --- |
| 1 | `M` | sent `M`, no `*?` reply |
| 2 | `V3` | sent `M3`, no `*?` reply |
| 3 | `W` | sent `M`, *and* answered `*?` |
| 4 | `W3` | sent `M3`, *and* answered `*?` |
| 5 | `C` | Mouse Systems, found by the baud-rate sweep |

`M`/`V3` are the 2-button and 3-button members of the plain-Microsoft family; `W`/`W3` are the
2-button and 3-button members of the extended family that supports the `*?` query. Slot 3 is
therefore the 2-button extended mouse, and naming it `W` is what makes the table consistent.

**Our source**

```c
static const char *mouseTypeNames[] = {
    "UNKNOWN",
    "M",
    "V3",
    "M",        /* <- slot 3 */
    "W3",
    "C"
};
```

**Difference:** our slot 3 is `"M"`, duplicating slot 1. Our `detect` reaches slot 3 by exactly
the reference's route — `SerialPointingDevice.m:222`, `if (mouseType == 1) mouseType = 3; else
mouseType = 4;` — so this is purely a wrong entry in the name table, not a missing code path.
The brief's concern that our `detect` "has no `W` path at all" is not borne out: the path exists
and is correct; only the label it prints is wrong. The consequence is cosmetic — a 2-button
extended mouse is logged as `M`, indistinguishable from a plain Microsoft mouse — and the string
`W` is absent from our `__cstring` entirely (Finding 13).

**Disposition:** fix — change slot 3 to `"W"`. The disassembly settles it; nothing is guessed.

## Finding 4: four `static`-versus-`external` linkage divergences

**Source:** `SerialPointingDevice.m:46` (`mouseTypeNames`), `:56` (`protocolList`), `:66`
(`active`), `:71` (`mainLoop`)

**Reference symbols**

| Symbol | Address | Section | Binding | Size |
| --- | --- | --- | --- | --- |
| `_mainLoop` | 0 | `__TEXT,__text` | **external** | 26 |
| `_mouseTypeList` | 8192 | `__DATA,__data` | **external** | 24 |
| `_protocolList` | 8216 | `__DATA,__data` | **external** | 24 |
| `_active` | 8240 | `__DATA,__data` | **external** | 1 |

`__DATA,__data` totals **49 bytes** = 24 + 24 + 1, so there is nothing else in it and `_active`
is confirmed 1 byte wide — a `BOOL`, not an `int`. Every one of the fifteen Objective-C methods
is `local`; these four are the only external definitions the object contributes.

**Our source** declares all four `static`, and names the first `mouseTypeNames` rather than
`mouseTypeList`.

**Difference:** linkage, and one name. `static` emits no symbol-table entry at all, so our object
cannot reproduce the reference's four external definitions. The emitted instruction streams are
unaffected. Precedent for the fix is commit `b27e22b8` in drvPCMCIABus.

`_protocolList` itself **matches the reference exactly** — 8216 through 8236 decode to
`UNKNOWN`, `MS`, `M+`, `5B`, `MM`, `RB`, which is our `protocolList` verbatim, and
`-[SerialPointingDevice mainLoop:]` indexes it at 1579 exactly as our source does. The only thing
wrong with it is the `static`.

**Disposition:** fix

## Finding 5: `mouseInit:` acquires the serial port with `nil`, not `self`

**Source:** `SerialPointingDevice.m:339`

**Reference behaviour**, `-[SerialPointingDevice mouseInit:]` 404–430:

```
404  push 0                        ;   <-- the acquire: argument
406  mov  edx, ds:paAcquire        ; @selector(acquire:)
412  push edx
413  mov  edx, [esi+154h]          ; portDevice
419  push edx
420  call _objc_msgSend            ; [portDevice acquire:nil]
425  add  esp, 0Ch
428  test eax, eax
430  jz   loc_1D8                  ;   zero -> success
```

**Our source**

```objc
ret = [serialPortObject acquire:self];
if (ret != IO_R_SUCCESS) { … }
```

**Difference:** the reference passes a literal `0` — `nil` — where ours passes `self`. The
success test is identical in both (zero means success). `IOSerialPort`'s `acquire:` takes the
"wait if busy" flag in the DriverKit serial-port protocol, so passing `self` is both the wrong
value and the wrong kind of value; the driver would be asking the port to block rather than to
fail fast.

**Disposition:** fix

## Finding 6: `mouseInit:` parses the resolution with `PCPatoi`, not `atoi`

**Source:** `SerialPointingDevice.m:368`

**Reference behaviour**, 643–700:

```
643  test eax, eax
645  jnz  loc_2B0                     ; non-NULL -> parse
647  mov  dword ptr [esi+12Ch], 0C8h  ; resolution = 200
657  push 0C8h
662  … [self name] …
679  push offset aSNoResolutionI      ; "%s: No resolution in config table.  Defaulting to %d\n"
684  jmp  loc_2DF                     ; -> IOLog
688  push eax                         ; 0x2B0: the string
689  call _PCPatoi
694  mov  [esi+12Ch], eax             ; resolution = PCPatoi(str)
```

`_PCPatoi` is an undefined external symbol in this object.

**Our source**

```objc
resolution = atoi(resolutionStr);
```

with `#import <stdlib.h>` at `SerialPointingDevice.m:39`.

**Difference:** the reference calls `PCPatoi`, declared in
`src/kernel-7/bsd/dev/i386/PCPointer.h:45` as `int PCPatoi(char *p)` and defined in
`PCPointer.m`. Ours calls `atoi`, a different symbol in the linked image with different
accepted syntax. The default-value path and the `0xC8` literal match exactly; the log text does
not (Finding 13).

**Disposition:** fix

**Rationale:** `PCPatoi` arrives for free with Finding 1's re-parenting, since `PCPointer.h`
declares it. The `<stdlib.h>` import becomes unused for this purpose.

## Finding 7: `free` does not clear the port device after releasing it

**Source:** `SerialPointingDevice.m:270`

**Reference behaviour**, `-[SerialPointingDevice free]` 940–1001:

```
940  mov  ds:_active, 0
947  cmp  dword ptr [ebx+154h], 0     ; portDevice
954  jz   loc_3D2                     ;   -> 978
956  mov  edx, ds:paRelease           ; @selector(release)
962  push edx
963  mov  edx, [ebx+154h]
969  push edx
970  call _objc_msgSend               ; [portDevice release]
975  add  esp, 8
978  mov  edx, ds:paFree              ; 0x3D2: [super free]
```

There is no store to `[ebx+154h]` between the `release` send and the `[super free]` send.

**Our source**

```objc
if (serialPortObject != nil) {
    [serialPortObject release];
    serialPortObject = nil;
}
```

**Difference:** the extra `serialPortObject = nil;`. Everything else in the method matches
instruction for instruction: the `verbose`-gated log, `active = NO`, the nil check, the release,
and the `objc_msgSendSuper` to `free` whose result is returned.

**Disposition:** fix — it is one line, and the object is about to be deallocated, so nothing
depends on the store.

## Finding 8: `getByte:sleep:` is a `do`/`while`, not a `while`

**Source:** `SerialPointingDevice.m:563`

**Reference behaviour**, `-[SerialPointingDevice getByte:sleep:]` 1772–1874. The prologue ends at
1791 and falls straight into the loop body at 1792; `_active` is tested only at the **bottom**:

```
1792 (loop head)
1792  movsx eax, bl                    ; sleep:
1795  push  eax
1796  lea   eax, [ebp+var_8]           ; &data
1799  push  eax
1800  lea   eax, [ebp+var_4]           ; &eventType
1803  push  eax
1804  mov   edx, ds:paDequeueeventDa   ; @selector(dequeueEvent:data:sleep:)
1810  push  edx
1811  mov   edx, [esi+154h]            ; portDevice
1817  push  edx
1818  call  _objc_msgSend
1823  add   esp, 14h
1826  test  eax, eax
1828  jnz   loc_747                    ;   error -> return NO
1830  cmp   [ebp+var_4], 55h
1834  jnz   loc_738                    ;   -> 1848
1836  mov   dl, [ebp+var_8]
1839  mov   [edi], dl                  ; *byte = data
1841  mov   eax, 1                     ; return YES
1846  jmp   loc_749
1848  cmp   [ebp+var_4], 0
1852  jz    loc_747                    ;   no data -> return NO
1854  cmp   ds:_active, 0
1861  jnz   loc_700                    ;   -> 1792, loop
1863  xor   eax, eax                   ; return NO
```

**Our source**

```objc
while (active) {
    ret = [serialPortObject dequeueEvent:&eventType data:&data sleep:shouldSleep];
    …
}
return NO;
```

**Difference:** the reference always attempts **one** dequeue before it consults `_active`; ours
returns `NO` immediately if `active` is already false. Everything inside the loop matches exactly
— the argument order, the `0x55` event-type test, the byte store, the `eventType == 0` early
return and the error return.

The difference is live during shutdown: a protocol handler blocked in
`getByte:sleep:YES` that returns after `MMProtocol`/`RBProtocol`/`UnknownProtocol` has cleared
`_active` will, in the reference, make one more dequeue attempt (draining or blocking on the
port); ours returns immediately. It also matters at start-up if `detect` is ever reached before
`active` is set.

**Disposition:** fix

## Finding 9: `detect`'s baud-rate sweep runs a fourth iteration

**Source:** `SerialPointingDevice.m:150`

**Reference behaviour**, 3011–3128:

```
3011  mov  ebx, 4B0h                   ; baudRate = 1200
3019  nop
3020 (loop head)
3020  mov  eax, ebx
3022  add  eax, ebx                    ; eax = baudRate * 2
3024  push eax
3025  push 33h
3027  …                                ; [portDevice executeEvent:0x33 data:baudRate*2]
3046  push 0 / push 73h / push 55h     ; [portDevice enqueueEvent:0x55 data:0x73 sleep:0]
3074  push 64h ; call _IOSleep         ; IOSleep(100)
3081  …                                ; [self getByte:&byte sleep:NO]
3103  test al, al
3105  jz   loc_C30                     ;   -> 3120
3107  mov  al, [ebp+var_1]
3110  and  al, 0BFh
3112  cmp  al, 0Fh
3114  jz   loc_B9C                     ;   -> 2972, mouseType = 5
3120  add  ebx, ebx                    ; baudRate *= 2
3122  cmp  ebx, 2580h                  ; 9600
3128  jle  loc_BCC                     ;   -> 3020
```

**Our source**

```objc
baudRate = 1200;
while (baudRate < 9600) {
    [serialPortObject executeEvent:0x33 data:(baudRate * 2)];
    …
    baudRate *= 2;
}
```

**Difference:** the reference is a `do`/`while` whose test is `baudRate <= 9600` at the bottom;
ours is a `while` whose test is `baudRate < 9600` at the top. The reference therefore runs
**four** iterations, with `baudRate` 1200, 2400, 4800 and 9600 — sending `executeEvent:0x33` with
2400, 4800, 9600 and **19200**. Ours runs **three**, stopping after the 9600 event.

A Mouse Systems mouse that only answers at 19200 baud is never found by our version. Everything
else in the sweep matches: the `executeEvent:0x3B data:0x10` that precedes it (2988), the
`enqueueEvent:0x55 data:0x73 sleep:0` probe, the `IOSleep(100)`, the `(byte & 0xBF) == 0x0F`
test, and the `enqueueEvent:0x55 data:0x55` / `data:0x52` / `protocol = 3` epilogue at 3139–3189.

**Disposition:** fix

## Finding 10: the event-dispatch timing gate is a single 64-bit unsigned compare

**Source:** `SerialPointingDevice.m:738`–`746` (`MSProtocol`) and `:856`–`864`
(`FiveBProtocol`)

**Reference behaviour.** The identical sequence appears three times — `MSProtocol` 3603–3646 and
`FiveBProtocol` 4017–4052 and 4229–4272:

```
3603  mov  ecx, [ebp+var_14]           ; current timestamp, low
3606  mov  ebx, [ebp+var_10]           ; current timestamp, high
3609  sub  ecx, [ebp+var_C]            ; - last, low
3612  sbb  ebx, [ebp+var_8]            ; - last, high, with borrow
3615  mov  [ebp+var_28], ecx
3618  mov  [ebp+var_24], ebx
3621  cmp  [ebp+var_24], 0             ; high word of the 64-bit difference
3625  ja   loc_D4E                     ;   nonzero -> DO NOT dispatch
3631  jnz  loc_E3E
3633  cmp  [ebp+var_28], 26259FFh      ; 39,999,999
3640  ja   loc_D4E                     ;   >= 40,000,000 -> DO NOT dispatch
3646  … dispatchPointerEvent: …
```

That is one unsigned 64-bit comparison: **dispatch if and only if
`current - last < 40000000`**, computed with the borrow from the low-word subtraction. (The
`jnz` at 3631 is unreachable — `cmp x, 0` never sets CF, so the `ja` at 3625 fails only when
`ZF = 1`. It is gcc's redundant second half of an unsigned 64-bit comparison, not a third
branch.)

**Our source**

```objc
shouldDispatch = NO;
if (currentTimestampHigh == lastTimestampHigh) {
    if (currentTimestampLow - lastTimestampLow < 40000000) {
        shouldDispatch = YES;
    }
} else if (currentTimestampHigh > lastTimestampHigh) {
    shouldDispatch = YES;
}
```

**Difference:** two independent errors.

1. **The high-word case is inverted.** When the high word advanced, ours dispatches
   unconditionally; the reference refuses to. A difference in the high word means more than 4.29
   seconds elapsed between the packet's first and last byte, which is precisely the stale event
   the gate exists to suppress. Ours dispatches it.
2. **The low-word case ignores the borrow.** Ours compares the two low words directly when the
   high words are equal; the reference subtracts the full 64-bit value. When the high words are
   equal these agree, so this half is only wrong in combination with (1).

The rest of the packet assembly matches instruction for instruction in both handlers: the
64-bit timestamp store to `pointerEvent.timeStamp` (`[ecx+158h]`, `[ecx+15Ch]`), the three-step
button masking (`and 0xFE` / `or left`, `and 0xFD` / `or right*2`, `and 3`), the delta stores to
`[ecx+161h]` and `[ecx+162h]`, and the `target != nil` guard.

**Disposition:** fix. The whole gate should be one `ns_time_t` subtraction and one comparison
against 40000000, which is also what Finding 1's `PCPointerEvent`/`ns_time_t` types make natural
to write.

## Finding 11: `FiveBProtocol` updates `lastTimestamp` after the third byte only

**Source:** `SerialPointingDevice.m:872`–`873`

**Reference behaviour.** The `FiveBProtocol` jump table at 3828 dispatches
`{0 → 3848, 1 → 4104, 2 → 3908, 3 → 4104, 4 → 4116}`. Cases 2 and 4 both assemble and dispatch a
packet, but they end differently:

```
case 2, at 4087 (reached from 4015 nil-target and from 4084 after dispatch):
  4087  mov  edx, [ebp+var_14]      ; current low
  4090  mov  ecx, [ebp+var_10]      ; current high
  4093  mov  [ebp+var_C], edx       ; last = current
  4096  mov  [ebp+var_8], ecx
  4099  jmp  def_EED                ; -> 3780, loop; byteIndex is 3

case 4, at 4223 / 4307:
  4223  jz   loc_F1F                ; -> 3871
  4307  jmp  loc_F1F                ; -> 3871
  3871  xor  esi, esi               ; byteIndex = 0
  3873  jmp  def_EED                ; -> 3780, loop
```

Case 4 has no counterpart to 4087–4096. `lastTimestamp` is left holding the value
`IOGetTimestamp` wrote in case 0.

**Our source**

```objc
case 2:
case 4:
    …
    /* Update last timestamp */
    lastTimestampLow = currentTimestampLow;
    lastTimestampHigh = currentTimestampHigh;

    if (byteIndex == 4) { byteIndex = 0; } else { byteIndex++; }
    break;
```

**Difference:** our combined `case 2: case 4:` runs the `lastTimestamp` update on both. The
reference runs it on case 2 only. Combined with Finding 10 this changes which of the two events
in a five-byte packet can be dispatched: in the reference both events are gated against the
timestamp taken in case 0, whereas ours gates the second event against the first.

Everything else in the handler matches: the case-0 sync test `(byte & 0xF8) == 0x80` (3860–3869),
the inverted button extraction `((byte >> 2) ^ 1) & 1` and `(byte ^ 1) & 1` (3876–3900), the
`savedByte = byte` shared by cases 1 and 3 (4104), `deltaX = savedByte` / `deltaY = byte`, and
the `byteIndex = 0` after case 4 versus `byteIndex++` after case 2.

**Disposition:** fix

## Finding 12: the reference logs nothing in `MSProtocol` or `FiveBProtocol` — SETTLED

**Source:** `SerialPointingDevice.m:664`–`666` and `:801`–`803`

**Reference behaviour.** `-[SerialPointingDevice MSProtocol]` (3256, 442 bytes) makes exactly
four calls, at 3333, 3392, 3484 and 3673: `_objc_msgSend`, `_IOGetTimestamp`, `_IOGetTimestamp`,
`_objc_msgSend`. `-[SerialPointingDevice FiveBProtocol]` (3724, 598 bytes) makes exactly six, at
3797, 3852, 3912, 4079, 4120 and 4299: `_objc_msgSend`, `_IOGetTimestamp`, `_IOGetTimestamp`,
`_objc_msgSend`, `_IOGetTimestamp`, `_objc_msgSend`.

**Neither function calls `_IOLog`, and neither tests `verbose` (`[esi+144h]`) anywhere.** Both
begin with their local initializations and go straight into the `getByte:sleep:YES` loop.

**Our source**

```objc
if (verbose) {
    IOLog("%s: MSProtocol started\n", [self name]);
}
```

and the matching `%s: FiveBProtocol started\n` in `FiveBProtocol`.

**Difference:** both blocks are ours alone. The two format strings are absent from the
reference's `__cstring` (Finding 13), and there is no `verbose` test or `_IOLog` call in either
function to hold them.

**Disposition:** fix — delete both blocks.

## Finding 13: string set

**Source:** `SerialPointingDevice.m`, various

**Reference `__TEXT,__cstring`** (862 bytes at 4468, complete):

```
4468  'C'                4470 'W3'          4473 'W'           4475 'V3'
4478  'M'                4480 'UNKNOWN'     4488 'RB'          4491 'MM'
4494  '5B'               4497 'M+'          4500 'MS'
4503  'SerialPointingDevice: Duplicate instance aborting.\n'
4555  'SerialPointingDevice'
4576  'PointingDevice'
4591  '%s: Missing configuration table.\n'
4625  'Verbose'
4633  '%s: Verbose mode active.\n'
4659  'Port Device'
4671  '%s: No Serial Port specified in config table.\n'
4718  '%s: "%s" is not a registered port.\n'
4754  '%s: Serial Port "%s" is already in use.\n'
4795  '%s: Acquired port "%s".\n'
4820  'Inverted'         4829 'YES'         4833 'NO'
4836  '%s: Invert = %s\n'
4853  'Resolution'
4864  '%s: No resolution in config table.  Defaulting to %d\n'
4918  '%s: Resolution = %d\n'
4939  '%s: No mouse detected on serial port %s.\n'
4981  '%s: Detected mouse type %s on serial port %s.\n'
5028  "SerialPointingDevice: Instance being free'd.\n"
5074  '%s: Main thread started.\n'
5100  '%s: Detected Mouse Type %s, %s Protocol.\n'
5142  'SerialPorintingDevice: Main thread terminated.\n'
5190  '%s: Attempting to detect mouse\n'
5222  '%s: Listening ... {'
5242  '}\n'
5245  '%s: Sending *? Command {'
5270  '[v%d, 9600=%s, x=%s, sub=%d, prot=%d, buttons=%d, res=%02x]'
```

**Difference.** The string set is in the best shape of any driver in this effort — every message
matches ours verbatim, including the reference's own typo `SerialPorintingDevice: Main thread
terminated.` at 5142, which our source already reproduces. Exactly three discrepancies remain:

| Kind | String | Site |
| --- | --- | --- |
| **missing** | `W` | `_mouseTypeList[3]`, Finding 3 |
| **wrong text** | `%s: No resolution in config table.  Defaulting to %d\n` — **two** spaces after the period | `SerialPointingDevice.m:366` has one |
| **extra (ours)** | `%s: MSProtocol started\n`, `%s: FiveBProtocol started\n` | Finding 12 |

The two-space run in `config table.  Defaulting` is a real two spaces in the reference and must be
reproduced exactly.

**Disposition:** fix

## Finding 14: `Load_Commands.sect` is one byte short

**Source:** `SerialPointingDevice.drvproj/SerialPointingDevice.lksproj/Load_Commands.sect`

**Reference** `Loaded Server,Load Commands`, 164 bytes:

```
'# \n# This loadable kernel driver does not use a Mig-generated interface,\n# so no handler or server interface is specified.\n#\n# This driver must be wired down.\nWIRE\n'
```

**Ours**, 163 bytes:

```
'#\n# This loadable kernel driver does not use a Mig-generated interface,\n# so no handler or server interface is specified.\n#\n# This driver must be wired down.\nWIRE\n'
```

**Difference:** the reference's first line is `# ` — hash, space, newline. Ours is `#`, newline.
That single missing space is the whole 164-versus-163 difference; the remaining 162 bytes are
identical. Identical to drvPS2Mouse's Finding 12.

**Disposition:** fix

## Finding 15: `MSProtocol` and `FiveBProtocol` leave the current timestamp uninitialized

**Source:** `SerialPointingDevice.m:659`–`660` and `:796`–`797`

**Reference behaviour.** Both handlers zero **both** halves of both timestamps in their prologue:

```
MSProtocol      3287  mov [ebp+var_8],  0     ; last, high
                3280  mov [ebp+var_C],  0     ; last, low
                3294  mov [ebp+var_14], 0     ; current, low
                3301  mov [ebp+var_10], 0     ; current, high

FiveBProtocol   3741  mov [ebp+var_C],  0     3748  mov [ebp+var_8],  0
                3755  mov [ebp+var_14], 0     3762  mov [ebp+var_10], 0
```

**Our source** initializes `lastTimestampLow`/`lastTimestampHigh` to 0 but declares
`currentTimestampLow` and `currentTimestampHigh` uninitialized.

**Difference:** ours reads `currentTimestampHigh` in the dispatch gate. In practice
`IOGetTimestamp((ns_time_t *)&currentTimestampLow)` writes eight bytes, which covers
`currentTimestampHigh` provided the compiler lays the two adjacent — the same trick the reference
uses on its own frame slots — and the gate is only reached after that call. So this is latent
rather than live. It is recorded because it is a real, confirmed difference from the reference
and because Finding 10 rewrites this region anyway.

**Disposition:** fix, as part of Finding 10.

## Finding 16: `getIntValues:`/`setIntValues:` return `IO_R_UNSUPPORTED`, not `IO_R_INVALID_ARG`

**Source:** `SerialPointingDevice.m:446` and `:514`

**Reference behaviour.** `-[SerialPointingDevice getIntValues:forParameter:count:]` at 1167 and
`-[SerialPointingDevice setIntValues:forParameter:count:]` at 1448, both on the "parameter name
matched neither `Resolution` nor `Inverted`" path:

```
mov eax, 0FFFFFD39h
```

`0xFFFFFD39` is −711. `src/driverkit-3/driverkit/return.h:51` defines `IO_R_UNSUPPORTED` as
`(-711)`; `IO_R_INVALID_ARG` is `(-706)` = `0xFFFFFD3E`.

**Our source**

```objc
if (!match) {
    return IO_R_INVALID_ARG;
}
```

**Difference:** both methods return `IO_R_UNSUPPORTED` in the reference and `IO_R_INVALID_ARG` in
ours. There are exactly two such sites, one per method.

Both string comparisons themselves match: `repe cmpsb` with `ecx = 0x0B` against `"Resolution"`
(1126–1134, 1222–1235) and `ecx = 9` against `"Inverted"` (1155–1163, 1339–1347), which is what
our unrolled compare loops (`i = 11` / `i = 9`) reproduce. `getIntValues:` reads `inverted` with
`movsx edx, byte [edx+130h]` (1176) where ours writes `(unsigned int)inverted`; for the only
values it ever holds these are identical. `setIntValues:` messages `target` unconditionally in
both branches (1271, 1373) and our source does the same, so there is no added nil guard here.
Neither method touches `count` in the reference, and neither does ours.

**Disposition:** fix

**Rationale:** "this driver does not know that parameter" is `IO_R_UNSUPPORTED`, and callers that
branch on the specific `IOReturn` would observe the difference. Same class of finding as
drvPS2Mouse's Finding 9.

## Observations that are not findings

Three differences were confirmed in the disassembly and deliberately **not** raised as findings,
because they are codegen shape with no behavioural or metadata consequence. They are listed so a
reviewer spot-checking the disassembly does not mistake their absence for an oversight.

- **`MSProtocol`'s masked byte.** The reference masks in place (`and [ebp+var_1], 7Fh` at 3349)
  and then tests `[var_1] & 0x40`; our source keeps `byte` and `maskedByte` separate and tests
  the unmasked `byte`. Masking bit 7 cannot change bit 6 or any lower bit, so every subsequent
  test and extraction is identical.
- **The unreachable `default:` in `MSProtocol`.** The reference increments `byteIndex` before the
  switch and lets `default` fall back to the loop head with the incremented value; ours sets
  `byteIndex = 0`. Case 2 resets `byteIndex` to 0 in both (the reference shares case 0's
  `xor esi, esi` at 3406), so `byteIndex` never exceeds 2 and the default is dead code either
  way.
- **`detect`'s `resolution` local.** The reference computes `byte & 0x3F` inline inside the
  `verbose` block at 2867; ours assigns it to a local at `SerialPointingDevice.m:219` and logs the
  local. The local is used nowhere else, so the two forms are equivalent.

Everything else that was checked and found to match is stated inline in the finding that covers
the surrounding code, rather than being listed separately.

## Nothing left unsettled

Every question the brief raised was resolved from the disassembly:

- **`_mouseTypeList` slot 3** — settled, Finding 3. `W` is the 2-button member of the extended
  `W`/`W3` family, reached from `detect` at 2829 when a mouse that sent a bare `M` answers the
  `*?` query. No `intentional-mismatch` is needed and nothing is guessed.
- **The four linkage divergences** — settled, Finding 4. All four are `external` in the reference
  and `static` in ours; `_active` is confirmed 1 byte, and `__DATA,__data`'s 49 bytes account for
  all three data objects exactly.
- **Logging in `MSProtocol` and `FiveBProtocol`** — settled, Finding 12. Neither function calls
  `_IOLog` or tests `verbose`; our two strings are additions.

The one thing this pass **cannot** claim is three-analyzer corroboration of the function
partition, for the reason given in the stated-limitation section at the top.
