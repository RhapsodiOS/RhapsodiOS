# drvBusMouse divergences

Reference: `BusMouse_reloc`, SHA-256 `A1AAB49F4D9F2BA90B4D7105F3D76BBF054F6D2D150B041D2156FC4F75E71864`
Analyses: IDA 9.2, Ghidra 12.1, angr 9.3.0 (all three enabled; `run-summary.json` reports
`"complete": true`)

## Summary

| Bucket | Count |
| --- | --- |
| mapped | 11 |
| unmapped | 2 |
| duplicate_candidates | 0 |
| boundary_disputed | 0 |

Ledger status distribution **after Task 4**: **7 `assembly-matched`**,
**6 `intentional-mismatch`**, **0 `unexamined`**. The report pass that produced everything
above this line left 2 `assembly-matched`, 9 `unexamined` and 2 `intentional-mismatch`. See
the "Fix pass (Task 12): results" section and Task 4 at the end of this document for the
resolution of every finding, the per-function size comparison and the emitted section sizes.

**The body of this document is the report pass. Task 12 rewrote all 11 hand-written
functions as a unit** under the spec's §4.3 approved exception. The reason is stated plainly:
the reference's ten `__cstring` entries and our source's ten share only three
(`BusMouse`, `Inverted`, `Resolution`), and all three are keys or names rather than messages.
Every log message in our source is our own wording. That is not a wording problem — it is the
signature of code whose control flow was reconstructed independently rather than recovered.

Two qualifications, both of which change what Task 12 has to do:

1. **Three of the four static C functions were plainly produced by a decompiler, not invented.**
   `GetIRQFromBoard`, `MouseIntHandler` and `BusMouseThread` in `BusMouse.m` carry
   Ghidra's naming conventions (`uVar`, `param_1`, `iVar`) and reproduce the reference's
   control flow closely — `GetIRQFromBoard`'s nested `if` ladder and its `0xf000`-iteration
   `do`/`while` are the reference's shape instruction for instruction. What went wrong is
   downstream of the decompilation: the decompiler's rendering of `outb()`'s own inline-asm
   side effect became real source statements (Finding 6), the `msg_header_t` became an invented
   struct (Finding 8), the handler's dead `eax` became a return value (Finding 7), and every
   `IOLog` string was rewritten. Task 12 is repairing a transcription, not writing from nothing.
2. **The Objective-C half is genuinely wrong at the root.** `BusMouse` derives from `PCPointer`
   and declares **no ivars of its own** (Finding 1). Every ivar access in the reference is one
   slot away from where our class puts it, and `mouseInit:` returns `BOOL` where ours returns
   `IOReturn` with inverted polarity (Finding 2). This is the same root divergence drvPS2Mouse,
   drvSerialPointingDevice and drvPCParallel each carried, and it must land atomically.

Five selectors are shared with drvPS2Mouse at **identical reference sizes** —
`getHandler:level:argument:forInterrupt:` 40, `getResolution` 16,
`getIntValues:forParameter:count:` 96, `setIntValues:forParameter:count:` 148, plus
`mouseInit:` as a name. drvPS2Mouse's fix pass is complete and reviewed, so its source is
known-good for those. Where this document says "follow drvPS2Mouse" it means exactly that:
copy the shape from
`src/drivers-i386/input/drvPS2Mouse/PS2Mouse.drvproj/PS2Mouse.lksproj/PS2Mouse.m`. The one
place drvBusMouse must **not** follow it is the `target` nil checks in `setIntValues:` — see
Finding 11.

## Examination depth

**All 13 reference functions were read at instruction level.** Every instruction of the full
1592-byte `__text` section was disassembled from the published IDA analysis and compared
against `BusMouse.m`. Nothing was reviewed at control-flow level only and nothing was reviewed
by grep. In addition the Objective-C metadata was decoded directly from the Mach-O
(`__class`, `__meta_class`, `__cls_meth`, `__inst_meth`, `__class_names`, `__meth_var_types`,
`__meth_var_names`, `__module_info`, `__bss`, `__common`, `__cstring`, and the four
`Loaded Server` sections); Findings 1, 2, 3, 4 and 5 come from that metadata rather than from
any single function body.

Section §"Reference specification, function by function" at the end of this document carries
the annotated disassembly of all 11 hand-written functions — control-flow shape, every literal,
every I/O port and direction, every struct field offset and every call target. **Task 12 should
be able to write `BusMouse.m` from that section without opening the binary again.**

## Baseline build

**No build was attempted in the report pass and none was required.** Task 12 established the
baseline: `EXIT=0`, `make exit=0`, a staged `_reloc` of 108416 bytes, `missing_strings` 7 and
`missing_symbols` 0 — matching what this section predicted.

Two scaffolding facts are recorded now so the fix pass can check them:

- `Load_Commands.sect` exists in `BusMouse.drvproj/BusMouse.lksproj/` and is named in that
  directory's `Makefile` `OTHERSRCS`, but it is **163 bytes** where the reference's
  `Loaded Server,Load Commands` section is **164**. See Finding 15.
- `Unload_Commands.sect` **does not exist** and is required: the reference carries a
  `Loaded Server,Unload Commands` section of **102 bytes**. See Finding 16. drvPS2Mouse
  recorded the same gap as out of scope on the grounds that nothing in this repository produces
  the section; for drvBusMouse it is called out as a finding because the file itself is a
  hand-written project input, exactly like `Load_Commands.sect`.

For reference, the sizes Task 12's build should be measured against:

| Section | Reference size |
| --- | --- |
| `__TEXT,__text` | 1592 |
| `__TEXT,__cstring` | 340 |
| `__TEXT,__const` | 170 |
| `__DATA,__bss` | 48 |
| `__DATA,__common` | 4 |
| `__DATA,__data` | present, size 0 |
| `__OBJC,__message_refs` | 60 |
| `__OBJC,__class` | 120 |
| `__OBJC,__meta_class` | 120 |
| `__OBJC,__cls_meth` | 40 |
| `__OBJC,__inst_meth` | 104 |
| `__OBJC,__class_names` | 111 |
| `__OBJC,__meth_var_types` | 112 |
| `__OBJC,__meth_var_names` | 389 |
| `__OBJC,__module_info` | 32 |
| `__OBJC,__instance_vars` | present, size 0 |
| `Loaded Server,Server Name` | 8 (`BusMouse`) |
| `Loaded Server,Load Commands` | 164 |
| `Loaded Server,Unload Commands` | 102 |
| `Loaded Server,Instance Var` | 17 (`BusMouse_instance`) |
| `Loaded Server,Server Version` | 1 (`2`) |

The 170 bytes of `__TEXT,__const` content are `_BusMouse_VERS_STRING` (160 bytes,
`@(#)PROGRAM:BusMouse  PROJECT:drvBusMouse-6  DEVELOPER:root  BUILT:Sat Mar 28 22:03:09 PST 1998\n`
zero-padded) and `_BusMouse_VERS_NUM` (10 bytes, `6`). As drvPS2Mouse recorded, no driver in
this repository emits NeXT's `vers_string` symbols; that gap is out of scope and is not a
finding.

## Required `__text` function order

The reference lays the thirteen functions out in this order, and `source-map.json`'s addresses
are only comparable if `BusMouse.m` defines them in it:

```
GetIRQFromBoard, validConfiguration:, MouseIntHandler, interruptHandler,
BusMouseThread, mouseInit:, free, getHandler:, getResolution,
getIntValues:, setIntValues:
```

The two `static` C functions are **interleaved among the methods**, inside the
`@implementation` block, which C and Objective-C both allow. Confirmation independent of the
`__text` addresses: `__OBJC,__inst_meth` stores the eight methods in exactly the reverse of
that order, which is how the compiler emits a method list.

## Function partition: sizes

The brief's partition table lists sizes as the gaps between consecutive symbol addresses
(112, 132, 408, 56, 124, 392, 44, 40, 16, 96, 148, 12, 12). IDA reports function extents with
the inter-function `nop` alignment padding excluded (109, 129, 406, 53, 123, 392, 41, 39, 16,
93, 146, 12, 12). Addresses and names agree exactly. IDA is authoritative for the partition, so
`source-map.json` and `ledger.json` carry IDA's extents. This is a padding accounting
difference, not a disagreement about what exists. Note `-[BusMouse mouseInit:]` is the one
function whose two figures agree at 392 — its last instruction ends exactly on a 4-byte
boundary.

## Analyzer agreement

**IDA and Ghidra agree on twelve functions exactly** — identical address, size and basic-block
count for every one of `_GetIRQFromBoard` (0/109/11), `-[BusMouse validConfiguration:]`
(112/129/7), `_MouseIntHandler` (244/406/8), `-[BusMouse interruptHandler]` (652/53/3),
`_BusMouseThread` (708/123/8), `-[BusMouse mouseInit:]` (832/392/14), `-[BusMouse free]`
(1224/41/1), `-[BusMouse getHandler:level:argument:forInterrupt:]` (1268/39/1),
`-[BusMouse getResolution]` (1308/16/1), `-[BusMouse getIntValues:forParameter:count:]`
(1324/93/7), `-[BusMouse setIntValues:forParameter:count:]` (1420/146/7) and
`+[BusMouseVersion driverKitVersionForBusMouse]` (1580/12/1).

**Ghidra does not detect `+[BusMouseKernelServerInstance kernelServerInstance]` at 1568.**
Ghidra's function list has 12 entries where IDA and angr both have 13. This is precisely the
gap drvPS2Mouse recorded for `+[PS2MouseKernelServerInstance kernelServerInstance]` at 1780 and
drvPCIBus recorded for `-[PCIKernBus test_M1]`: a 12-byte glue method whose neighbour at the
next address is detected with identical bytes and size. A Ghidra detection gap for one
function, not a body disagreement.

**angr reports 33 functions.** All 13 real functions are present at identical addresses with
identical sizes. The 20 extra entries are 19 one-to-three-byte fragments plus one data entry:

- inter-function `nop` padding: 109 (3), 241 (3), 650 (2), 705 (3), 831 (1), 1265 (3),
  1307 (1), 1417 (3)
- *interior* alignment padding, each sitting immediately after an unconditional `jmp` and
  before the next basic block of the same function: 62 (2), 179 (1), 219 (1), 493 (3),
  813 (3), 873 (3), 967 (1), 1013 (3), 1366 (2), 1394 (2), 1518 (2)
- `_BusMouse_VERS_STRING` at 1932 (159), a `__TEXT,__const` data symbol angr walked as code

angr also splits basic blocks more finely than IDA within the real functions (for example 27
blocks against IDA's 14 in `-[BusMouse mouseInit:]`, 13 against 8 in `_BusMouseThread`). None
of this is a partition disagreement.

No boundary is genuinely disputed; `boundary_disputed` and `duplicate_candidates` are both
empty.

## Configuration table

`src/drivers-i386/input/drvBusMouse/BusMouse.drvproj/Default.table` diffs clean against
`C:\Users\raynorpat\Downloads\test\Drivers\i386\BusMouse.config\Default.table` ignoring
`"Driver Version"`. Task 2 landed correctly; there is no Task 2 defect here.

## Unmapped: build-generated

`+[BusMouseKernelServerInstance kernelServerInstance]` (1568) and
`+[BusMouseVersion driverKitVersionForBusMouse]` (1580) are emitted by the Kernel Server
project type and `Load_Commands.sect`, not written by hand. Accepted.

The first returns `&_BusMouse_instance` (`__DATA,__common`, 0x2030 = 8240); the second returns
`500` (0x1F4). Their owning classes come from the same generated translation unit: `__class`
declares `BusMouseKernelServerInstance : Object` (instance_size 4) and
`BusMouseVersion : IODevice` (instance_size 264), and `__class_names` carries the generated
unit name `BusMouse_instance.m` alongside the hand-written `BusMouse.m`. `__module_info` has
exactly two 16-byte entries, one per translation unit.

`_BusMouse_VERS_STRING` (1932, `__const`), `_BusMouse_VERS_NUM` (2092, `__const`) and
`_BusMouse_instance` (8240, `__common`) are data symbols outside `__TEXT,__text` and therefore
do not appear anywhere in the source map, which lists functions only.

---

## Finding 1: `BusMouse` derives from `PCPointer` and has no ivars of its own

**Source:** `src/drivers-i386/input/drvBusMouse/BusMouse.drvproj/BusMouse.lksproj/BusMouse.h:38`

**Reference metadata**

`__class` (120 bytes, decoded):

```
BusMouse                     : PCPointer   instance_size = 324 (0x144)  ivars = NULL
BusMouseVersion              : IODevice    instance_size = 264 (0x108)
BusMouseKernelServerInstance : Object      instance_size =   4
```

**`__OBJC,__instance_vars` is present in the object at size 0** — the NeXT compiler always
emits the section and IDA simply drops zero-size sections, which is what an earlier draft of
this document mistook for absence. `BusMouse`'s `ivars` field is a null pointer. The three UNDEF Objective-C class references are
`.objc_class_name_PCPointer`, `.objc_class_name_IODevice` and `.objc_class_name_Object` —
there is no reference to `IODirectDevice` anywhere.

**Our source**

```objc
@interface BusMouse : IODirectDevice
{
@private
    unsigned int resolution;
    BOOL inverted;
    id mouseEventPort;
}
```

**Difference:** every ivar the code touches is inherited. `src/kernel-7/bsd/dev/i386/PCPointer.h`
declares `@interface PCPointer : IODirectDevice { id target; unsigned resolution; BOOL
inverted; @private int _reserved[4]; }`, which on top of a 0x128-byte `IODirectDevice` gives:

| Offset | Reference ivar | Owner | Our ivar at that offset |
| --- | --- | --- | --- |
| 0x128 | `target` | `PCPointer` | `resolution` |
| 0x12c | `resolution` | `PCPointer` | `inverted` |
| 0x130 | `inverted` | `PCPointer` | `mouseEventPort` |
| 0x134–0x143 | `_reserved[4]` | `PCPointer` | *(past the end of our object)* |

Total 0x144 = **324, exactly the reference's `instance_size`**, with `ivars = NULL` because
`BusMouse` adds nothing. The in-tree `PCPointer.h` is a byte-exact match for the base class
Apple compiled against — the same conclusion drvPS2Mouse reached, where the two extra ivars
`controller`/`force_detection` took it from 324 to 332.

Every ivar access in the reference is therefore **one slot below** where our declarations put
it. `-[BusMouse getResolution]` reads `[eax+0x12c]`; ours would emit `[eax+0x128]`.
`-[BusMouse interruptHandler]` and `-[BusMouse setIntValues:…]` message `[…+0x128]`, which is
PCPointer's `target`; our `mouseEventPort` is at 0x130.

**Disposition:** fix

**Rationale:** this is the root divergence. No function body containing an ivar access can
match until the hierarchy matches. Re-parenting to `PCPointer` deletes all three of our ivar
declarations (`resolution` and `inverted` become inherited, `mouseEventPort` becomes
PCPointer's `target`) and supplies `PCPatoi` (Finding 12) and the `RESOLUTION`/`INVERTED` key
macros. Not speculative: the base class is already in the tree and its layout is confirmed
against the binary. drvPS2Mouse's `Makefile` already shows the pattern — `-DDRIVER_PRIVATE`
must be added to the lksproj `Makefile` so `<bsd/dev/i386/PCPointer.h>` and
`<bsd/dev/i386/PCPointerDefs.h>` expose their contents.

## Finding 2: method return types, `mouseInit:` polarity, and a class method the reference does not have

**Source:** `src/drivers-i386/input/drvBusMouse/BusMouse.drvproj/BusMouse.lksproj/BusMouse.h:47`–`71`

**Reference metadata**

`__inst_meth` is one list of **8** methods (8-byte header + 8 × 12 = 104 bytes). Name, type
encoding and implementation address, in the order the list stores them:

```
setIntValues:forParameter:count:        i20@8:12^I16*20I24         1420
getIntValues:forParameter:count:        i20@8:12^I16*20^I24        1324
getResolution                           i8@8:12                    1308
getHandler:level:argument:forInterrupt: c24@8:12^^?16^I20^I24I28   1268
free                                    @8@8:12                    1224
mouseInit:                              c12@8:12@16                 832
interruptHandler                        v8@8:12                     652
validConfiguration:                     c12@8:12@16                 112
```

`__cls_meth` is 40 bytes = **two** 20-byte lists of one method each, and they belong to
`BusMouseVersion` (`driverKitVersionForBusMouse`, `i8@8:12`) and
`BusMouseKernelServerInstance` (`kernelServerInstance`, `^^{?}8@8:12`). `BusMouse`'s
meta-class has `methodLists = NULL`: **the reference `BusMouse` has no class methods.**

**Our source**

```objc
+ (BOOL)probe:(IODeviceDescription *)deviceDescription;   /* returns NO */
- (IOReturn)mouseInit:(IODeviceDescription *)deviceDescription;
- (unsigned int)getResolution;
- (BOOL)getHandler:(IOInterruptHandler *)handler level:(unsigned int *)ipl
          argument:(void **)arg forInterrupt:(unsigned int)localInterrupt;
```

**Difference:**

- `mouseInit:` returns **`BOOL`** (`c12@8:12@16`) in the reference, with **1 = success, 0 =
  failure**. Ours returns `IOReturn`, where success is `IO_R_SUCCESS` = 0 and failure is
  `IO_R_INVALID_ARG` = −706. **The polarity is inverted**: our successful `mouseInit:` returns
  0, which a `BOOL`-expecting caller reads as failure, and our failing one returns −706, which
  reads as true. `PCPointer.h:70` declares `- (BOOL)mouseInit:deviceDescription` and `PCPointer`
  is what calls it, so once Finding 1 re-parents the class this becomes a live bug. Confirmed
  in the code: `mouseInit:` ends `mov eax, 1` at 1210 on the success path and `xor eax, eax`
  at 866 and 960 on the two failure paths.
- `validConfiguration:` is likewise `c12@8:12@16` — `BOOL`, which ours already is (confirmed:
  `mov eax, 1` at 212, `xor eax, eax` at 232).
- `getResolution` returns **`int`** (`i8@8:12`). Ours returns `unsigned int`, which encodes as
  `I8@8:12`. `PCPointer.h:64` also declares `- (int)getResolution`. Same as drvPS2Mouse.
- `getHandler:…`'s `argument:` parameter is encoded `^I` — pointer to `unsigned int`. Ours
  declares `void **arg`, which encodes as `^^v`. The emitted instruction stream is identical
  either way (`mov dword ptr [ecx], 0DEADBEEFh`); only the type metadata differs. Same as
  drvPS2Mouse.
- `+probe:` **must be removed.** The reference emits no class method list for `BusMouse` at
  all. Keeping it would add a third 20-byte list to `__cls_meth` (40 → 60), add `probe:` to
  `__meth_var_names` and add a 14th function to `__text`. Our implementation returns `NO`
  unconditionally, so nothing depends on it.
- `interruptHandler` is `v8@8:12` (`void`), which ours already is; `free` is `@8@8:12`
  (returns `id`), which our bare `- free` already is.

**Disposition:** fix, in the same change as Finding 1.

## Finding 3: the reference's `__DATA,__bss` layout, and what each object holds

**Source:** `src/drivers-i386/input/drvBusMouse/BusMouse.drvproj/BusMouse.lksproj/BusMouse.m:58`–`73`

**Reference `__DATA,__bss`** (48 bytes at 0x2000, plus `__common` at 0x2030):

| Address | Symbol | Size | What it holds |
| --- | --- | --- | --- |
| 0x2000 | `_xxx.86` | 4 | build residue — `outb()`'s inline-asm static, the only one referenced |
| 0x2004 | `_xxx.89` | 4 | build residue — a second `out*()` static, never referenced |
| 0x2008 | `_xxx.92` | 4 | build residue — a third `out*()` static, never referenced |
| 0x200c | `_higherLevelsBusy` | 4 | `int`/`unsigned`; 1 while an event is in flight |
| 0x2010 | `_event` | 12 | `PCPointerEvent` — the event handed to the target |
| 0x201c | `_summedEvent` | 12 | `PCPointerEvent` — deltas accumulated while busy |
| 0x2028 | `_lastRightButton` | 4 | `int`, initialized to −1 |
| 0x202c | `_lastLeftButton` | 4 | `int`, initialized to −1 |
| 0x2030 | `_BusMouse_instance` (`__common`) | 4 | build-generated |

**The `_xxx.NN` trio is confirmed build residue, not driver state.**
`src/driverkit-3/driverkit/i386/ioPorts.h` defines

```c
static __inline__ void outb(IOEISAPortAddress port, unsigned char data)
{
    static int xxx;
    asm volatile("outb %2,%1; lock; incl %0"
                 : "=m" (xxx) : "d" (port), "a" (data), "0" (xxx) : "cc");
}
```

and `outw`/`outl` are identical but for the mnemonic. Each `static int xxx` becomes a distinct
`_xxx.<line>` symbol named for its line in the preprocessed translation unit, which is why
there are exactly three, evenly spaced. Every one of the ten `outb()` sites in the reference emits
`F0 FF 05 00 20 00 00` — `lock incl ds:0x2000` — against `_xxx.86` alone; `.89` and `.92` are
allocated by the three inline definitions being instantiated and are never touched. They cost
8 bytes of `__bss` and nothing else. This confirms the earlier pass's conclusion.

**The two 12-byte objects are `PCPointerEvent`.** `<bsd/dev/i386/PCPointerDefs.h>` declares

```c
typedef struct _t_PCPointerEvent {
    ns_time_t timeStamp;                /* +0, 8 bytes */
    union {
        unsigned char buf[4];           /* +8 */
        struct { unsigned int leftButton:1, rightButton:1, pad:6; int dx:8; int dy:8; } values;
    } data;
} PCPointerEvent;                       /* 12 bytes */
```

Every access in the reference lands on that layout:

- `_IOGetTimestamp(&_event)` at 545 writes the 8-byte `timeStamp` at 0x2010.
- `and byte ptr [0x2018], 0FEh` / `or byte ptr [0x2018], dl` (496, 505) is a bitfield write of
  `data.values.leftButton`; `and 0FDh` / `or al` (515, 522) with `al = right + right` is
  `data.values.rightButton`. 0x2018 is `_event + 8` = `data.buf[0]`.
- `mov ds:[0x2019], dl` (558) and `mov ds:[0x201A], al` (572) are plain byte stores of
  `data.buf[1]` and `data.buf[2]` — `dx` and `dy`, byte-aligned bitfields that gcc stores
  directly.
- `add ds:[0x2025], al` and `add ds:[0x2026], bl` (476, 482) are `_summedEvent + 9` and
  `+ 10`, the same `dx`/`dy` bytes of the accumulator. drvPS2Mouse's `_summedEvent` accesses
  are at exactly the same offsets.
- `mov ds:[0x201C], 0` and `mov ds:[0x2020], 0` (620, 630) clear `_summedEvent.timeStamp`'s two
  halves; `mov ds:[0x2025], 0` / `mov ds:[0x2026], 0` (606, 613) clear its deltas.

**Our source**

```c
static unsigned int lastLeftButton = 0;
static unsigned int lastRightButton = 0;
static unsigned int higherLevelsBusy = 0;
static unsigned int summedEvent = 0;
static char accumulatedDeltaX = 0;
static char accumulatedDeltaY = 0;
static unsigned int ioPortCount = 0;
static struct { unsigned int timestamp_high; unsigned int timestamp_low;
                unsigned char buttons; char deltaX; char deltaY; } mouseEvent;
```

**Difference:**

- `_summedEvent` is a 12-byte `PCPointerEvent` in the reference. Ours splits it into a 4-byte
  `unsigned int summedEvent` plus two loose `char` accumulators that are not adjacent to it and
  are declared before an unrelated object. The reference's zeroing of `_summedEvent`'s
  timestamp has no counterpart at all.
- `ioPortCount` has **no counterpart anywhere in the reference**; see Finding 6.
- `mouseEvent` happens to have the right *shape* (4 + 4 + 1 + 1 + 1 padded to 12, so buttons at
  +8 and deltas at +9/+10), but the field names invert the timestamp halves and it is not the
  declared `PCPointerEvent` type, so the bitfield writes the reference performs cannot be
  expressed against it.
- Declaration order is wrong throughout, so our `__bss` layout cannot match: the reference's
  order is `higherLevelsBusy`, `event`, `summedEvent`, `lastRightButton`, `lastLeftButton`.
  Note `lastRightButton` precedes `lastLeftButton`.
- The reference's `__DATA,__data` section is **absent**, meaning none of these statics carries
  an explicit initializer. drvPS2Mouse's fix pass learned this the hard way: NeXT's compiler
  places an explicitly initialized static in `__data` even when the initializer is zero. Our
  `= 0` initializers must be dropped or `__bss` will come up short and `__data` will appear.

**Disposition:** fix

## Finding 4: the reference's `__cstring` set, and which function owns each string

**Source:** `src/drivers-i386/input/drvBusMouse/BusMouse.drvproj/BusMouse.lksproj/BusMouse.m`, various

**Reference `__cstring`** (340 bytes at 1592, complete, with the site that references each):

| Address | String | Owning function | Reference site |
| --- | --- | --- | --- |
| 1592 | `Bus Mouse : No bus mouse installed.\n` | `-[BusMouse validConfiguration:]` | 167 |
| 1629 | `Bus Mouse : configured IRQ (%d) doesn't equal actual IRQ (%d)\n` | `-[BusMouse validConfiguration:]` | 222 |
| 1692 | `BusMouseThread: msg_receive() returned %d\n` | `_BusMouseThread` | 772 |
| 1735 | `BusMouseThread: Bogus msg_local_port\n` | `_BusMouseThread` | 816 |
| 1773 | `BusMouse` | `-[BusMouse mouseInit:]` | 876 (`setName:`) and 893 (`setDeviceKind:`) |
| 1782 | `BusMouse mouseInit: no configuration table\n` | `-[BusMouse mouseInit:]` | 950 |
| 1826 | `Inverted` | three functions | `mouseInit:` 968, `getIntValues:` 1370, `setIntValues:` 1494 |
| 1835 | `Resolution` | three functions | `mouseInit:` 1023, `getIntValues:` 1341, `setIntValues:` 1437 |
| 1846 | `BusMouse mouseInit: no resolution in config table.  Default is %d\n` | `-[BusMouse mouseInit:]` | 1065 |
| 1913 | `Bus mouse running\n` | `-[BusMouse mouseInit:]` | 1200 |

**Four distinct spellings must be reproduced byte for byte:**

1. **`Bus Mouse : ` — with a space before the colon — in exactly the two strings that belong to
   `-[BusMouse validConfiguration:]`, and nowhere else.**
2. `BusMouseThread: ` — no space before the colon — in the two strings that belong to
   `_BusMouseThread`.
3. `BusMouse mouseInit: ` — no space before the colon — in the two `mouseInit:` diagnostics.
4. `Bus mouse running\n` — **lower-case `m`, one word `mouse`, no prefix at all** — the success
   message at the end of `mouseInit:`.

Two further byte-level details:

- `no resolution in config table.  Default is %d` has **two spaces** after the period, exactly
  as drvPS2Mouse's equivalent string does.
- `configured IRQ (%d) doesn't equal actual IRQ (%d)` contains an ASCII apostrophe in
  `doesn't`.

Adding the string lengths (37 + 63 + 43 + 38 + 9 + 44 + 9 + 11 + 67 + 19) gives exactly 340,
the reference `__cstring` size, so the set above is complete and no string is shared with any
other section.

**Our source** carries `BusMouse: Bus mouse not detected (signature mismatch)`,
`BusMouse: IRQ mismatch - config: %d, detected: %d`, `BusMouse: msg_receive failed: %d`,
`BusMouse: interrupt port mismatch`, `BusMouse: No config table`,
`BusMouse: Using default resolution %d` and `BusMouse: Initialized successfully` — seven
replacements — plus `BusMouse`, `Inverted` and `Resolution`, which match.

**Difference:** seven of the ten strings are our own wording. The mapping above is one-to-one:
each of our seven replaces exactly one reference string at exactly one site, and no site in
either version logs something the other does not. **The wording is invented; the set of log
points is not.**

**Disposition:** fix

## Finding 5: `_GetIRQFromBoard` is a global symbol, not `static`

**Source:** `src/drivers-i386/input/drvBusMouse/BusMouse.drvproj/BusMouse.lksproj/BusMouse.m:76`

**Reference:** the symbol table records `_GetIRQFromBoard` at address 0 with binding
**`global`**. It is the only `__TEXT,__text` symbol in the object that is not `local` —
`_MouseIntHandler` (244) and `_BusMouseThread` (708) are both `local`, and so is every method.

**Our source:** `static unsigned int GetIRQFromBoard(void)`.

**Difference:** a `static` function emits a local symbol. This is directly observable in the
symbol table and in `parity_check.py`'s symbol comparison.

**Disposition:** fix — drop `static` from `GetIRQFromBoard` only. `MouseIntHandler` and
`BusMouseThread` stay `static`.

## Finding 6: `ioPortCount` is a transcribed decompiler artifact, not driver state

**Source:** `src/drivers-i386/input/drvBusMouse/BusMouse.drvproj/BusMouse.lksproj/BusMouse.m:64`
and its ten increment sites (`:166`, `:265`, `:274`, `:353`)

**Reference behaviour:** every `outb()` in the reference emits two instructions —
`out dx, al` followed by `F0 FF 05 00 20 00 00`, `lock incl ds:_xxx.86`. That second
instruction is *inside* the `outb()` inline asm (Finding 3), emitted by
`driverkit/i386/ioPorts.h`, and the counter it increments is the compiler's own anonymous
static. There is no separate counter object in `__bss` and no driver-authored increment
anywhere.

**Our source**

```c
static unsigned int ioPortCount = 0;
...
    outb(0x23e, 0x80);
    LOCK();
    UNLOCK();
    outb(0x23e, 0x80);
    ...
    outb(0x23e, 0);
    LOCK();
    ioPortCount = ioPortCount + 6;      /* MouseIntHandler */
    UNLOCK();
```

and `ioPortCount = ioPortCount + 1;` after the single `outb()` in `validConfiguration:` (twice)
and in `mouseInit:` (once), together with a pair of empty `LOCK()`/`UNLOCK()` macros defined at
`BusMouse.m:40`–`41`.

**Difference:** the decompiler rendered `lock incl _xxx.86` as an increment of a named global
and the transcription turned it into real source. The tell is `+ 6` in `MouseIntHandler`: the
six `outb()` calls in that function each increment the counter once, and whoever wrote this
collapsed them into a single statement at the point of the last one. The result is a static
the reference does not have (4 more bytes of `__bss` in the wrong place) plus ten
read-modify-write sequences of real emitted code the reference does not contain.

**Disposition:** fix. Delete `ioPortCount`, all four increment statements and the `LOCK()` /
`UNLOCK()` macros and their call sites. `outb()` supplies the `lock incl` by itself.

## Finding 7: `MouseIntHandler` returns a value; the reference's returns `void`

**Source:** `src/drivers-i386/input/drvBusMouse/BusMouse.drvproj/BusMouse.lksproj/BusMouse.m:116`

**Reference behaviour:** the shared epilogue at 640 is
`lea esp,[ebp-18h]; pop ebx; pop esi; pop edi; mov esp,ebp; pop ebp; ret` with no preceding
`xor eax, eax` and no `mov eax, …` on any path that reaches it as a return value. `eax` is
written at 474 (`mov eax, esi`) only as scratch for the immediately following
`add ds:[0x2025], al`, and after the `_IOSendInterrupt` call it holds whatever that function
left. The function reads its arguments at `[ebp+8]` and `[ebp+0Ch]` only and never touches
`[ebp+10h]`.

`driverkit/driverTypes.h:248` declares
`typedef void (*IOInterruptHandler)(void *identity, void *state, unsigned int arg);`

**Our source**

```c
static unsigned int MouseIntHandler(unsigned int param_1, unsigned int param_2)
{
    ...
    returnValue = 0;
    ...
        returnValue = xMovement;     /* busy path */
    ...
    return returnValue;
}
```

**Difference:** the decompiler saw `eax` live at the epilogue and synthesised a return value;
the transcription made it an `unsigned int` return and then invented two values for it. The
handler is a DriverKit `IOInterruptHandler` and must be
`static void MouseIntHandler(void *identity, void *state, unsigned int arg)`. Also note the
declared parameter types: the reference pushes `[ebp+0Ch]` then `[ebp+8]` straight through to
`_IOSendInterrupt`, whose DriverKit signature takes `void *`, so the casts our source performs
at the call site (`(void *)param_1`) exist only because the parameters were declared
`unsigned int`.

**Disposition:** fix. This is also where the already-in-tree build repair lands — that change
stopped using `IOSendInterrupt`'s non-existent return value, which was the right call; the
remaining half is the handler's own return type.

## Finding 8: `_BusMouseThread` receives a bare `msg_header_t`, not an invented struct

**Source:** `src/drivers-i386/input/drvBusMouse/BusMouse.drvproj/BusMouse.lksproj/BusMouse.m:51`–`55`
and `:209`

**Reference behaviour**

```
708  sub  esp, 18h                  ; a 24-byte message buffer
720  lea  ebx, [ebp-18h]
744  mov  dword ptr [ebx+4],  18h   ; msg.msg_size = 24
751  mov  [ebx+0Ch], esi            ; msg.msg_local_port = port
754  push 0                         ; timeout
756  push 0                         ; option
758  push ebx
759  call _msg_receive
784  cmp  dword ptr [ebx+14h], 232325h   ; msg.msg_id == IO_DEVICE_INTERRUPT_MSG
793  cmp  [ebx+0Ch], esi                 ; msg.msg_local_port == port
```

24 bytes with `msg_size` at +4, `msg_local_port` at +0x0C and `msg_id` at +0x14 is exactly
Mach's `msg_header_t`, and `sizeof(msg_header_t)` is what is stored into `msg_size`.
0x232325 is `IO_DEVICE_INTERRUPT_MSG` — `driverkit/interruptMsg.h:54` defines it as
`IO_INTERRUPT_MSG_ID_BASE + 2` with the base at `0x232323`.

**Our source**

```c
typedef struct {
    msg_header_t header;
    msg_type_t   type;
    int          msgId;
} interrupt_msg_t;
...
    msg.header.msg_size = sizeof(interrupt_msg_t);   /* 36, not 24 */
    msg.header.msg_local_port = interruptPort;
    ret = msg_receive(&msg.header, MSG_OPTION_NONE, 0);
    ...
    if (msg.msgId == IO_DEVICE_INTERRUPT_MSG)        /* reads offset 32, not 20 */
```

**Difference:** the invented `interrupt_msg_t` is 36 bytes, so `msg_size` is declared as 36 and
the message ID is read from offset 32, which is 12 bytes past where `msg_receive` writes it.
The struct's `type` field has no counterpart. The reference's shape is
`msg_header_t msg, *msgPtr = &msg;` — and there is a working in-tree template for exactly this
loop at `src/kernel-7/bsd/dev/i386/PS2Keyboard.m:435` (`kbdThread`), whose emitted shape the
reference reproduces line for line down to the `continue` after the `msg_receive` failure log.

Note also that the reference's failure test is against `RCV_SUCCESS`, not `KERN_SUCCESS`
(`PS2Keyboard.m:454` uses `RCV_SUCCESS`); both are 0 so the emitted `test eax, eax` is the same,
but the source should say `RCV_SUCCESS`.

**Disposition:** fix

## Finding 9: `validConfiguration:` waits 30 microseconds where the reference waits 30 milliseconds

**Source:** `src/drivers-i386/input/drvBusMouse/BusMouse.drvproj/BusMouse.lksproj/BusMouse.m:269`

**Reference behaviour**

```
116  mov  edx, 23Fh
121  mov  al, 91h
123  out  dx, al               ; outb(0x23F, 0x91)
124  lock inc ds:_xxx.86
131  push 7530h                ; 30000
136  call _us_spin             ; us_spin(30000)
141  add  esp, 4
```

`_us_spin` is an UNDEF import of this object. `src/kernel-7/machdep/i386/machine_clock.c:147`
defines `void us_spin(unsigned int us)` as a calibrated busy-wait in **microseconds**, and
`src/kernel-7/bsd/i386/param.h:138` exposes it as `#define DELAY(n) us_spin(n)`.
0x7530 = 30000 µs = **30 milliseconds**.

**Our source**

```c
    outb(0x23f, 0x91);
    ...
    /* Delay for hardware to settle (30ms) */
    IODelay(30);
```

**Difference:** `IODelay(30)` is **30 microseconds — a thousand times shorter** than the
reference's wait, and the comment beside it says 30 ms, which is what makes this worth calling
out separately: the comment is right and the code is wrong. The reference imports neither
`_IODelay` nor `_IOSleep`; the only timing symbol it imports is `_us_spin`. This is the answer
to the brief's `_us_spin` question — **one call site, `-[BusMouse validConfiguration:]` at 136,
`us_spin(30000)` between writing 0x91 to port 0x23F and writing the 0xA5 signature to port
0x23D.**

`us_spin` has no prototype in any installed header; only the `DELAY(n)` macro in
`<bsd/i386/param.h>` names it. Task 12 will need either that import or a local
`extern void us_spin(unsigned int);`. Whichever it picks, the emitted call must be to
`_us_spin` with the single argument 30000, not to `_IODelay`.

**Disposition:** fix. Getting this wrong is a probe that runs a thousand times too fast — the
signature readback at 159 happens before the controller has settled.

## Finding 10: `getIntValues:`/`setIntValues:` return `IO_R_UNSUPPORTED`, not `IO_R_INVALID_ARG`

**Source:** `src/drivers-i386/input/drvBusMouse/BusMouse.drvproj/BusMouse.lksproj/BusMouse.m:423`
and `BusMouse.m:475`

**Reference behaviour:** `-[BusMouse getIntValues:forParameter:count:]` at 1387 and
`-[BusMouse setIntValues:forParameter:count:]` at 1511, both on the "parameter name matched
neither `Resolution` nor `Inverted`" path:

```
mov eax, 0FFFFFD39h
```

`0xFFFFFD39` is −711. `driverkit/return.h:51` defines `IO_R_UNSUPPORTED` as `(-711)`;
`IO_R_INVALID_ARG` is `(-706)` = `0xFFFFFD3E`.

**Our source:** `return IO_R_INVALID_ARG;` at both sites.

**Difference:** exactly two sites, one per method. Identical to drvPS2Mouse's Finding 9, which
was fixed. Both methods leave `count` untouched in the reference, as ours do.

**Disposition:** fix

## Finding 11: `setIntValues:` messages `target` unconditionally, and both branches share one send

**Source:** `src/drivers-i386/input/drvBusMouse/BusMouse.drvproj/BusMouse.lksproj/BusMouse.m:459`
and `BusMouse.m:480`

**Reference behaviour:** the two branches of `setIntValues:` converge on a single `objc_msgSend`
at 1549, reached from the `Resolution` branch by an explicit `jmp` at 1490:

```
1470  mov  ecx, ds:paGetresolution
1476  push ecx
1477  push ebx
1478  call _objc_msgSend          ; [self getResolution]
1483  push eax                    ;   argument
1484  mov  edx, ds:paSetresolution
1490  jmp  1541                   ;   -> the shared tail
...
1531  movsx eax, cl               ; Inverted branch: sign-extended char
1534  push eax
1535  mov  edx, ds:paSetinverted
1541  push edx                    ; <- shared tail: selector
1542  mov  ebx, [ebx+128h]        ;    target, loaded and messaged unconditionally
1548  push ebx
1549  call _objc_msgSend
```

There is no test of `[ebx+128h]` before the send on either path.

**Our source** does the two sends separately, once per branch — but, importantly, **also
without a nil check**, unlike drvPS2Mouse's:

```objc
    [mouseEventPort setResolution:resolutionValue];
    ...
    [mouseEventPort setInverted:invertedValue];
```

**Difference:** only the code shape, not the behaviour. Our source is *closer* to the reference
here than drvPS2Mouse's is: drvPS2Mouse kept `if (target != nil)` guards around both sends and
recorded them as an accepted intentional mismatch under its Finding 10. **Task 12 must not copy
those guards across.** Keep the unguarded sends and let the compiler share the tail.

The reference does nil-check the same ivar in `-[BusMouse interruptHandler]` at 658, so the
asymmetry is deliberate in Apple's code, exactly as it was in drvPS2Mouse.

**Disposition:** fix — but the fix is only the ivar rename (`mouseEventPort` → inherited
`target`, Finding 1). The absence of a nil check is already right.

## Finding 12: `mouseInit:` parses the resolution with `strtoul`, not `PCPatoi`

**Source:** `src/drivers-i386/input/drvBusMouse/BusMouse.drvproj/BusMouse.lksproj/BusMouse.m:335`

**Reference behaviour**

```
1046  test ecx, ecx
1048  jnz  1080                          ; non-NULL -> parse
1050  mov  dword ptr [esi+12Ch], 190h    ; resolution = 400
1060  push 190h
1065  push offset "BusMouse mouseInit: no resolution in config table.  Default is %d\n"
1070  call _IOLog
1075  add  esp, 8
1078  jmp  1095
1080  push ecx                           ; the string
1081  call _PCPatoi
1086  mov  [esi+12Ch], eax
1092  add  esp, 4
```

`_PCPatoi` is an UNDEF import of this object.

**Our source:** `resolution = strtoul(resolutionStr, NULL, 0);`

**Difference:** the reference calls `PCPatoi`, declared in
`src/kernel-7/bsd/dev/i386/PCPointer.h:45` as `int PCPatoi(char *p)` and defined in
`PCPointer.m`. `strtoul` with base 0 accepts `0x`/`0` prefixes that `PCPatoi` does not, and is
a different symbol in the linked image. `PCPatoi` arrives for free with Finding 1's
re-parenting, since `PCPointer.h` declares it. Identical to drvPS2Mouse's Finding 8, which was
fixed the same way.

The default value 0x190 = 400 and the `%d` log both match our source; only the parse call and
the message text differ.

**Disposition:** fix

## Finding 13: `mouseInit:` initializes a different set of statics

**Source:** `src/drivers-i386/input/drvBusMouse/BusMouse.drvproj/BusMouse.lksproj/BusMouse.m:339`–`345`

**Reference behaviour** (1095–1159), in exactly this order:

```
1095  mov  dword ptr ds:_higherLevelsBusy, 0        ; 0x200C
1105  mov  byte  ptr ds:[2026h], 0                  ; _summedEvent.data.buf[2]  (dy)
1112  mov  byte  ptr ds:[2025h], 0                  ; _summedEvent.data.buf[1]  (dx)
1119  mov  dword ptr ds:[201Ch], 0                  ; _summedEvent.timeStamp lo
1129  mov  dword ptr ds:[2020h], 0                  ; _summedEvent.timeStamp hi
1139  mov  dword ptr ds:_lastLeftButton,  0FFFFFFFFh
1149  mov  dword ptr ds:_lastRightButton, 0FFFFFFFFh
```

Seven stores: `higherLevelsBusy = 0`, the whole of `_summedEvent` zeroed field by field, and
both last-button trackers set to **−1**. `_event` is **not** touched, and neither `inverted`
nor `resolution` is pre-set beyond what the config-table parse writes.

**Our source**

```c
    higherLevelsBusy = 0;
    accumulatedDeltaY = 0;
    accumulatedDeltaX = 0;
    summedEvent = 0;
    mouseEvent.timestamp_high = 0;
    lastLeftButton = 0xffffffff;
    lastRightButton = 0xffffffff;
```

**Difference:** the set is nearly right and the ordering (dY before dX, left before right) is
exactly right, which is further evidence this region came from a decompiler. Two errors:
`mouseEvent.timestamp_high = 0` clears a field of `_event` that the reference never touches,
and it is standing in for the second half of `_summedEvent`'s timestamp, which the reference
*does* clear. Once Finding 3 gives `summedEvent` its real 12-byte type the whole block becomes
`higherLevelsBusy = 0; summedEvent.data.buf[2] = 0; summedEvent.data.buf[1] = 0;
summedEvent.timeStamp = 0; lastLeftButton = -1; lastRightButton = -1;`.

Also note the reference stores −1 as `0FFFFFFFFh` into objects it treats as signed elsewhere
(`cmp ds:_lastLeftButton, edi` at 445 against a value that is only ever 0 or 1). Declaring them
`int` rather than `unsigned int` reproduces the `-1` literal cleanly.

**Disposition:** fix

## Finding 14: `MouseIntHandler` issues the port-0x23E command twice for the button read

**Source:** `src/drivers-i386/input/drvBusMouse/BusMouse.drvproj/BusMouse.lksproj/BusMouse.m:131`–`137`

**Reference behaviour**

```
253  mov  edx, 23Eh
258  mov  al, 80h
260  out  dx, al           ; outb(0x23E, 0x80)
261  lock inc ds:_xxx.86
268  out  dx, al           ; outb(0x23E, 0x80)   -- the SAME dx and al, reused
269  lock inc ds:_xxx.86
276  mov  edx, 23Ch
281  in   al, dx           ; inb(0x23C)
```

The compiler reloaded neither `dx` nor `al` for the second `out`, which is how two identical
`outb(0x23E, 0x80)` calls in a row compile. Every other command byte is issued once:
0xA0 at 322, 0xC0 at 363, 0xE0 at 392, 0x00 at 429.

**Our source** already has the doubled write, so this is **not a divergence** — it is recorded
because it looks like a transcription slip and is not one. Task 12 must keep both.

**Disposition:** accept — our source already matches.

## Finding 15: `Load_Commands.sect` is one byte short

**Source:** `src/drivers-i386/input/drvBusMouse/BusMouse.drvproj/BusMouse.lksproj/Load_Commands.sect`

**Reference** `Loaded Server,Load Commands`, 164 bytes:

```
'# \n# This loadable kernel driver does not use a Mig-generated interface,\n# so no handler or server interface is specified.\n#\n# This driver must be wired down.\nWIRE\n'
```

**Ours**, 163 bytes: identical but for the first line, which is `#` + newline where the
reference's is `#` + space + newline. That single missing space is the whole 164-vs-163
difference; the remaining 162 bytes are identical.

This is the same one-byte defect found in three other drivers.

**Disposition:** fix

## Finding 16: `Unload_Commands.sect` does not exist and is required

**Source:** `src/drivers-i386/input/drvBusMouse/BusMouse.drvproj/BusMouse.lksproj/` (absent)

**Reference** `Loaded Server,Unload Commands`, 102 bytes:

```
'# \n# This loadable kernel driver is not unloadable. (I think) this file\n# is still necessary.\n#\n\n\n\n\n\n\n'
```

Note the same `# ` first line as `Load_Commands.sect`, the parenthetical `(I think)` verbatim,
and the **six** trailing blank lines after the lone `#` line.

**Ours:** the file does not exist, and `Load_Commands.sect` is the only `.sect` named in the
lksproj `Makefile`'s `OTHERSRCS`.

**Disposition:** fix. drvPS2Mouse recorded this gap as out of scope on the grounds that nothing
in the repository produces the section; that reasoning does not apply here, because
`Load_Commands.sect` proves the mechanism works — the file is an ordinary project input listed
in `OTHERSRCS` and picked up by `kernelserver.make`. Creating `Unload_Commands.sect` with the
102 bytes above and adding it to `OTHERSRCS` should close the last `Loaded Server` section gap.
Task 12 should verify that `kernelserver.make` names the file that way before assuming it.

---

# Reference specification, function by function

Everything below is read from the reference disassembly. Addresses are `__text`-relative
decimal, matching the source map. This section is the rewrite target.

## `_GetIRQFromBoard` — 0, IDA extent 109, **global** symbol

Signature: `unsigned int GetIRQFromBoard(void)` — non-static (Finding 5). No arguments, no
calls. I/O: `inb(0x23E)` only; **no writes at all**.

```
  0  push ebp; mov ebp,esp; sub esp,8; push ebx
  7  xor  bl, bl                ; changed = 0
  9  mov  edx, 23Eh
 14  in   al, dx                ; prev = inb(0x23E)
 15  mov  [ebp-4], al
 18  mov  ecx, 0F000h           ; count = 61440
 23  nop
 24  mov  edx, 23Eh             ; loop top
 29  in   al, dx                ; cur = inb(0x23E)
 30  mov  dl, [ebp-4]
 33  xor  dl, al
 35  or   bl, dl                ; changed |= prev ^ cur
 37  mov  [ebp-4], al           ; prev = cur
 40  dec  ecx
 41  test ecx, ecx
 43  jg   24                    ; signed compare: count is int
 45  mov  cl, bl
 47  and  cl, 0Fh               ; low nibble copy
 50  test bl, 1
 53  jz   64
 55  mov  ebx, 5                ; bit 0 toggled -> IRQ 5
 60  jmp  100
 64  test cl, 2
 67  jz   76
 69  mov  ebx, 4                ; bit 1 -> IRQ 4
 74  jmp  100
 76  test cl, 4
 79  jz   88
 81  mov  ebx, 3                ; bit 2 -> IRQ 3
 86  jmp  100
 88  xor  ebx, ebx              ; default 0
 90  test cl, 8
 93  jz   100
 95  mov  ebx, 2                ; bit 3 -> IRQ 2
100  mov  eax, ebx
102  pop ebx; mov esp,ebp; pop ebp; ret
```

**Port and bit detail, stated plainly.** The board is polled at **port 0x23E** — the same
control/command port `MouseIntHandler` and `mouseInit:` write, read here rather than written.
It is read once before the loop and then **61440** more times. The accumulator is the OR of
every consecutive-sample XOR, i.e. the set of bits that changed state at any point during the
poll. The IRQ is then decoded from the **lowest set bit**, tested in ascending order and
mapping **bit 0 → IRQ 5, bit 1 → IRQ 4, bit 2 → IRQ 3, bit 3 → IRQ 2**, with **0** returned
when none of the low four bits ever changed. Bits 4–7 are ignored. `and cl, 0Fh` at 47 masks
the copy used for the second, third and fourth tests; the first test uses the unmasked byte.
The mask is inert given the bits tested, but reproducing it is what makes 47–49 appear.

**Our source is already semantically correct here** — same port, same 0xF000 count, same
XOR-OR accumulation, same nested ladder, same 5/4/3/2/0 mapping. The only changes Task 12 needs
are the storage class (Finding 5) and whatever produces the masked copy.

## `-[BusMouse validConfiguration:]` — 112, IDA extent 129

Signature: `- (BOOL)validConfiguration:deviceDescription` (`c12@8:12@16`). Returns 1 on match,
0 otherwise.

I/O ports: **write 0x91 → 0x23F**, **write 0xA5 → 0x23D**, **read 0x23D**.
Calls: `_us_spin`, `_IOLog` ×2, `_objc_msgSend` (`interrupt`), `_GetIRQFromBoard`.

```
112  push ebp; mov ebp,esp; push ebx
116  mov  edx, 23Fh
121  mov  al, 91h
123  out  dx, al                     ; outb(0x23F, 0x91)
124  lock inc ds:_xxx.86
131  push 7530h
136  call _us_spin                   ; us_spin(30000)  == 30 ms   (Finding 9)
141  add  esp, 4
144  mov  edx, 23Dh
149  mov  al, 0A5h
151  out  dx, al                     ; outb(0x23D, 0xA5)
152  lock inc ds:_xxx.86
159  in   al, dx                     ; inb(0x23D)   -- dx still 0x23D
160  mov  cl, al
162  cmp  cl, 0A5h
165  jz   180
167  push offset 'Bus Mouse : No bus mouse installed.\n'
172  call _IOLog
177  jmp  232                        ; return NO
180  mov  edx, ds:paInterrupt
186  push edx
187  mov  eax, [ebp+10h]             ; deviceDescription
190  push eax
191  call _objc_msgSend              ; [deviceDescription interrupt]
196  mov  ebx, eax                   ; configured IRQ
198  call _GetIRQFromBoard
203  mov  ecx, eax                   ; detected IRQ
205  add  esp, 8
208  cmp  ebx, ecx
210  jnz  220
212  mov  eax, 1                     ; return YES
217  jmp  234
220  push ecx                        ;   %d #2 = detected
221  push ebx                        ;   %d #1 = configured
222  push offset "Bus Mouse : configured IRQ (%d) doesn't equal actual IRQ (%d)\n"
227  call _IOLog
232  xor  eax, eax                   ; return NO
234  pop ebx; mov esp,ebp; pop ebp; ret
```

Argument order in the second `IOLog` is **configured first, detected second**. Note there is no
`add esp` after either `IOLog` — the epilogue's `mov esp, ebp` cleans up.

## `_MouseIntHandler` — 244, IDA extent 406

Signature: `static void MouseIntHandler(void *identity, void *state, unsigned int arg)`
(Finding 7). `arg` (`[ebp+10h]`) is never read.

I/O ports, in order: **write 0x80 → 0x23E** (twice), **read 0x23C**, **write 0xA0 → 0x23E**,
**read 0x23C**, **write 0xC0 → 0x23E**, **read 0x23C**, **write 0xE0 → 0x23E**, **read 0x23C**,
**write 0x00 → 0x23E**. Ten port accesses in total: six writes to 0x23E and four reads of 0x23C.
Calls: `_IOGetTimestamp`, `_IOSendInterrupt`.

```
244  push ebp; mov ebp,esp; sub esp,0Ch; push edi; push esi; push ebx
253  mov  edx, 23Eh
258  mov  al, 80h
260  out  dx, al          ; outb(0x23E, 0x80)
261  lock inc ds:_xxx.86
268  out  dx, al          ; outb(0x23E, 0x80) again -- see Finding 14
269  lock inc ds:_xxx.86
276  mov  edx, 23Ch
281  in   al, dx          ; b = inb(0x23C)      -- buttons + X low nibble
282  mov  cl, al
284  mov  [ebp-0Ch], cl
287  shr  al, 7
290  movzx edx, al
293  mov  edi, edx
295  xor  edi, 1          ; left  = ((b >> 7) & 1) ^ 1      -> active low, bit 7
298  mov  al, cl
300  shr  al, 5
303  mov  [ebp-8], al
306  mov  dl, al
308  not  edx
310  mov  ecx, edx
312  and  ecx, 1          ; right = (~(b >> 5)) & 1         -> active low, bit 5
315  mov  edx, 23Eh
320  mov  al, 0A0h
322  out  dx, al          ; outb(0x23E, 0xA0)   -- select X high
323  lock inc ds:_xxx.86
330  mov  edx, 23Ch
335  in   al, dx
336  mov  bl, al
338  mov  esi, 0Fh
343  and  esi, ebx
345  shl  esi, 4
348  mov  al, [ebp-0Ch]
351  and  eax, 0Fh
354  or   esi, eax        ; dx = ((xhigh & 0x0F) << 4) | (b & 0x0F)
356  mov  edx, 23Eh
361  mov  al, 0C0h
363  out  dx, al          ; outb(0x23E, 0xC0)   -- select Y low
364  lock inc ds:_xxx.86
371  mov  edx, 23Ch
376  in   al, dx
377  mov  bl, al
379  and  bl, 0Fh
382  mov  [ebp-0Ch], bl   ; ylow & 0x0F
385  mov  edx, 23Eh
390  mov  al, 0E0h
392  out  dx, al          ; outb(0x23E, 0xE0)   -- select Y high
393  lock inc ds:_xxx.86
400  mov  edx, 23Ch
405  in   al, dx
406  mov  bl, al
408  and  ebx, 0Fh
411  shl  ebx, 4
414  movzx eax, byte ptr [ebp-0Ch]
418  or   ebx, eax        ; y = ((yhigh & 0x0F) << 4) | (ylow & 0x0F)
420  neg  ebx             ; dy = -y                        <-- sign flip
422  mov  edx, 23Eh
427  xor  al, al
429  out  dx, al          ; outb(0x23E, 0x00)   -- release / idle
430  lock inc ds:_xxx.86
437  test esi, esi
439  jnz  465
441  test ebx, ebx
443  jnz  465
445  cmp  ds:_lastLeftButton, edi
451  jnz  465
453  cmp  ds:_lastRightButton, ecx
459  jz   640                       ; nothing changed -> return
465  cmp  ds:_higherLevelsBusy, 0
472  jz   496
474  mov  eax, esi                  ; --- busy: accumulate only ---
476  add  ds:[2025h], al            ; summedEvent.data.buf[1] += (char)dx
482  add  ds:[2026h], bl            ; summedEvent.data.buf[2] += (char)dy
488  jmp  640
496  and  ds:[2018h], 0FEh          ; --- not busy: post the event ---
503  mov  edx, edi
505  or   ds:[2018h], dl            ; event.data.values.leftButton  = left
511  mov  al, cl
513  add  al, al
515  and  ds:[2018h], 0FDh
522  or   ds:[2018h], al            ; event.data.values.rightButton = right
528  mov  ds:_lastLeftButton,  edi
534  mov  ds:_lastRightButton, ecx
540  push offset _event             ; 0x2010
545  call _IOGetTimestamp           ; IOGetTimestamp(&event.timeStamp)
550  mov  edx, esi
552  add  dl, ds:[2025h]
558  mov  ds:[2019h], dl            ; event.data.buf[1] = dx + summed dx
564  mov  al, ds:[2026h]
570  add  al, bl
572  mov  ds:[201Ah], al            ; event.data.buf[2] = summed dy + dy
578  mov  ds:_higherLevelsBusy, 1
588  push 232325h                   ; IO_DEVICE_INTERRUPT_MSG
593  mov  edx, [ebp+0Ch]            ; state
596  push edx
597  mov  eax, [ebp+8]              ; identity
600  push eax
601  call _IOSendInterrupt          ; IOSendInterrupt(identity, state, 0x232325)
606  mov  byte ptr ds:[2025h], 0    ; summedEvent.data.buf[1] = 0
613  mov  byte ptr ds:[2026h], 0    ; summedEvent.data.buf[2] = 0
620  mov  dword ptr ds:[201Ch], 0   ; summedEvent.timeStamp = 0  (lo)
630  mov  dword ptr ds:[2020h], 0   ; summedEvent.timeStamp = 0  (hi)
640  lea esp,[ebp-18h]; pop ebx; pop esi; pop edi; mov esp,ebp; pop ebp; ret
```

Things worth stating explicitly, because getting any of them wrong is silent:

- **Both buttons are active low.** Left is bit 7 of the first read, inverted; right is bit 5,
  inverted. Middle is not read.
- **X comes from two different reads:** its low nibble is the low nibble of the *button* byte,
  its high nibble from the 0xA0 read. Y comes from the 0xC0 and 0xE0 reads.
- **Y is negated** (`neg ebx` at 420) and X is not.
- The four-way "did anything change" test at 437–459 is `dx != 0 || dy != 0 ||
  lastLeftButton != left || lastRightButton != right`; when all four are false the handler
  returns without touching anything, including `_higherLevelsBusy`.
- On the busy path the last-button trackers are **not** updated and no timestamp is taken.
- On the post path the accumulated deltas are folded into the event *and then* the accumulator
  is fully cleared, timestamp included.
- `_higherLevelsBusy` is set to 1 **before** `IOSendInterrupt`, and is cleared only by
  `-[BusMouse interruptHandler]`.

## `-[BusMouse interruptHandler]` — 652, IDA extent 53

Signature: `- (void)interruptHandler` (`v8@8:12`). No I/O ports.

```
652  push ebp; mov ebp,esp
655  mov  eax, [ebp+8]              ; self
658  cmp  dword ptr [eax+128h], 0   ; target   (PCPointer ivar)
665  jz   691
667  push offset _event             ; 0x2010, the whole 12-byte PCPointerEvent
672  mov  edx, ds:paDispatchpointe
678  push edx
679  mov  eax, [eax+128h]
685  push eax
686  call _objc_msgSend             ; [target dispatchPointerEvent:&event]
691  mov  ds:_higherLevelsBusy, 0   ; both paths
701  mov esp,ebp; pop ebp; ret
```

`_higherLevelsBusy = 0` runs on the nil path too. Our source has this shape correctly; only the
ivar is wrong (Finding 1).

## `_BusMouseThread` — 708, IDA extent 123

Signature: `static void BusMouseThread(BusMouse *driver)` — one argument. No I/O ports.
Calls: `_objc_msgSend` (`interruptPort`, `interruptHandler`), `_msg_receive`, `_IOLog` ×2.

```
708  push ebp; mov ebp,esp; sub esp,18h; push edi; push esi; push ebx
717  mov  edi, [ebp+8]              ; driver
720  lea  ebx, [ebp-18h]            ; &msg   -- 24 bytes, a bare msg_header_t
723  mov  edx, ds:paInterruptport
729  push edx
730  push edi
731  call _objc_msgSend             ; port = [driver interruptPort]
736  mov  esi, eax
738  add  esp, 8                    ; <- loop re-entry A (after a 2-arg push)
741  nop; nop; nop
744  mov  dword ptr [ebx+4],  18h   ; msg.msg_size = sizeof(msg_header_t) = 24
751  mov  [ebx+0Ch], esi            ; msg.msg_local_port = port
754  push 0                         ; timeout  = 0
756  push 0                         ; option   = MSG_OPTION_NONE
758  push ebx
759  call _msg_receive
764  add  esp, 0Ch
767  test eax, eax
769  jz   784
771  push eax
772  push offset 'BusMouseThread: msg_receive() returned %d\n'
777  call _IOLog
782  jmp  738                       ; continue
784  cmp  dword ptr [ebx+14h], 232325h   ; msg.msg_id == IO_DEVICE_INTERRUPT_MSG
791  jnz  744                       ; not ours -> loop, silently
793  cmp  [ebx+0Ch], esi            ; msg.msg_local_port == port
796  jnz  816
798  mov  edx, ds:paInterrupthandl
804  push edx
805  push edi
806  call _objc_msgSend             ; [driver interruptHandler]
811  jmp  738
816  push offset 'BusMouseThread: Bogus msg_local_port\n'
821  call _IOLog
826  add  esp, 4
829  jmp  744
```

This is an infinite loop with no exit. The `jmp 738` targets are the compiler folding the
two-argument stack cleanup into the loop back-edge; a plain `while (TRUE) { … continue; }`
produces this. `src/kernel-7/bsd/dev/i386/PS2Keyboard.m:435` (`kbdThread`) is a working in-tree
source template with the same shape minus the second port comparison.

## `-[BusMouse mouseInit:]` — 832, IDA extent 392

Signature: `- (BOOL)mouseInit:deviceDescription` (`c12@8:12@16`). **1 = success, 0 = failure.**

I/O ports: **write 0x00 → 0x23E**, once, at 1181.
Calls: `_objc_msgSend` ×7, `_IOLog` ×3, `_PCPatoi`, `_IOForkThread`.

```
832  push ebp; mov ebp,esp; push esi; push ebx
837  mov  esi, [ebp+8]              ; self
840  mov  eax, [ebp+10h]            ; deviceDescription
843  push eax
844  mov  edx, ds:paValidconfigura
850  push edx
851  push esi
852  call _objc_msgSend             ; [self validConfiguration:deviceDescription]
857  mov  cl, al
859  add  esp, 0Ch
862  test cl, cl
864  jnz  876
866  xor  eax, eax                  ; return NO  -- no log on this path
868  jmp  1215
876  push offset 'BusMouse'
881  mov  eax, ds:paSetname
886  push eax
887  push esi
888  call _objc_msgSend             ; [self setName:"BusMouse"]
893  push offset 'BusMouse'
898  mov  edx, ds:paSetdevicekind
904  push edx
905  push esi
906  call _objc_msgSend             ; [self setDeviceKind:"BusMouse"]
911  mov  eax, ds:paConfigtable     ; selector pushed before the inner send
916  push eax
917  mov  edx, ds:paDevicedescript
923  push edx
924  push esi
925  call _objc_msgSend             ; [self deviceDescription]
930  add  esp, 8
933  mov  ecx, eax
935  push ecx
936  call _objc_msgSend             ; [<that> configTable]
941  mov  ebx, eax                  ; configTable
943  add  esp, 20h
946  test ebx, ebx
948  jnz  968
950  push offset 'BusMouse mouseInit: no configuration table\n'
955  call _IOLog
960  xor  eax, eax                  ; return NO
962  jmp  1215
968  push offset 'Inverted'
973  mov  eax, ds:paValueforstring
978  push eax
979  push ebx
980  call _objc_msgSend             ; [configTable valueForStringKey:"Inverted"]
985  mov  ecx, eax
987  add  esp, 0Ch
990  test ecx, ecx
992  jz   1016
994  cmp  byte ptr [ecx], 79h       ; 'y'
997  jz   1004
999  cmp  byte ptr [ecx], 59h       ; 'Y'
1002 jnz  1016
1004 mov  byte ptr [esi+130h], 1    ; inverted = YES
1011 jmp  1023
1016 mov  byte ptr [esi+130h], 0    ; inverted = NO
1023 push offset 'Resolution'
1028 mov  edx, ds:paValueforstring
1034 push edx
1035 push ebx
1036 call _objc_msgSend             ; [configTable valueForStringKey:"Resolution"]
1041 mov  ecx, eax
1043 add  esp, 0Ch
1046 test ecx, ecx
1048 jnz  1080
1050 mov  dword ptr [esi+12Ch], 190h    ; resolution = 400
1060 push 190h
1065 push offset 'BusMouse mouseInit: no resolution in config table.  Default is %d\n'
1070 call _IOLog
1075 add  esp, 8
1078 jmp  1095
1080 push ecx
1081 call _PCPatoi
1086 mov  [esi+12Ch], eax           ; resolution = PCPatoi(str)
1092 add  esp, 4
1095 ... the seven static initializations of Finding 13 ...
1159 mov  eax, ds:paEnableallinter
1164 push eax
1165 push esi
1166 call _objc_msgSend             ; [self enableAllInterrupts]
1171 add  esp, 8
1174 mov  edx, 23Eh
1179 xor  al, al
1181 out  dx, al                    ; outb(0x23E, 0x00)
1182 lock inc ds:_xxx.86
1189 push esi
1190 push offset _BusMouseThread
1195 call _IOForkThread             ; IOForkThread(BusMouseThread, self)
1200 push offset 'Bus mouse running\n'
1205 call _IOLog
1210 mov  eax, 1                    ; return YES
1215 lea esp,[ebp-8]; pop ebx; pop esi; mov esp,ebp; pop ebp; ret
```

Ordering that matters: `validConfiguration:` first and it is the only gate; `setName:` and
`setDeviceKind:` both take the literal `"BusMouse"`; the config table is fetched as
`[[self deviceDescription] configTable]` (**not** from the argument); `Inverted` is parsed
before `Resolution`; the statics are initialized **after** the config-table parse; interrupts
are enabled **before** the port write; the thread is forked last; and the success log is
`Bus mouse running\n` with no prefix.

`Inverted` accepts a leading `y` or `Y` and nothing else, exactly as our source does and
exactly as drvPS2Mouse's `Force Detection` parse does.

## `-[BusMouse free]` — 1224, IDA extent 41 — **assembly-matched**

```
1224 push ebp; mov ebp,esp; sub esp,8
1230 mov  edx, ds:paFree
1236 push edx
1237 mov  edx, [ebp+8]
1240 mov  [ebp-8], edx            ; super.receiver = self
1243 mov  edx, ds:[403Ch+4]       ; super.class = _BusMouse's super_class field
1249 mov  [ebp-4], edx
1252 lea  eax, [ebp-8]
1255 push eax
1256 call _objc_msgSendSuper
1261 mov esp,ebp; pop ebp; ret
```

`- free { return [super free]; }`, which is exactly our source. The `super_class` field
reference is to `__class + 4` and is the same instruction whatever the superclass is, so this
body is byte-identical today and stays byte-identical after Finding 1.

## `-[BusMouse getHandler:level:argument:forInterrupt:]` — 1268, IDA extent 39 — **assembly-matched**

```
1268 push ebp; mov ebp,esp
1271 mov  eax, [ebp+10h]              ; handler
1274 mov  edx, [ebp+14h]              ; ipl
1277 mov  ecx, [ebp+18h]              ; argument
1280 mov  dword ptr [eax], offset _MouseIntHandler
1286 mov  dword ptr [edx], 3
1292 mov  dword ptr [ecx], 0DEADBEEFh
1298 mov  eax, 1
1303 mov esp,ebp; pop ebp; ret
```

`forInterrupt:` (`[ebp+1Ch]`) is never read. Our body compiles to this byte for byte; only the
`argument:` type encoding differs (Finding 2), which does not appear in the code. Identical to
drvPS2Mouse's, at the identical size of 40 including padding — **follow drvPS2Mouse**.

## `-[BusMouse getResolution]` — 1308, IDA extent 16

```
1308 push ebp; mov ebp,esp
1311 mov  eax, [ebp+8]
1314 mov  eax, [eax+12Ch]     ; resolution  (PCPointer ivar)
1320 mov esp,ebp; pop ebp; ret
```

`- (int)getResolution { return resolution; }`. Our body would emit `[eax+128h]` under our ivar
layout, so it is **not** matched today; Finding 1 alone fixes it. Identical to drvPS2Mouse's at
the identical size of 16 — **follow drvPS2Mouse**.

## `-[BusMouse getIntValues:forParameter:count:]` — 1324, IDA extent 93

Signature: `- (IOReturn)getIntValues:(unsigned *)array forParameter:(IOParameterName)name
count:(unsigned *)count` (`i20@8:12^I16*20^I24`). `count` is never read or written.

```
1324 push ebp; mov ebp,esp; push edi; push esi; push ebx
1330 mov  edx, [ebp+8]         ; self
1333 mov  ebx, [ebp+10h]       ; parameterArray
1336 mov  eax, [ebp+14h]       ; parameterName
1339 mov  esi, eax
1341 mov  edi, offset 'Resolution'
1346 mov  ecx, 0Bh             ; 11 = strlen("Resolution") + 1
1351 cld
1352 test al, 0                ; 2-byte alignment filler
1354 repe cmpsb
1356 jnz  1368
1358 mov  edx, [edx+12Ch]      ; value = resolution
1364 jmp  1403
1368 mov  esi, eax
1370 mov  edi, offset 'Inverted'
1375 mov  ecx, 9               ; 9 = strlen("Inverted") + 1
1380 cld
1381 test al, 0
1383 repe cmpsb
1385 jz   1396
1387 mov  eax, 0FFFFFD39h      ; IO_R_UNSUPPORTED (-711)
1392 jmp  1407
1396 movsx edx, byte ptr [edx+130h]   ; value = (signed char)inverted
1403 mov  [ebx], edx           ; *parameterArray = value
1405 xor  eax, eax             ; IO_R_SUCCESS
1407 lea esp,[ebp-0Ch]; pop ebx; pop esi; pop edi; mov esp,ebp; pop ebp; ret
```

The comparisons are fixed-length, **including the terminating NUL** (11 and 9), and `Resolution`
is tested first. `inverted` is read sign-extended from a byte. Identical shape and identical
size (96 with padding) to drvPS2Mouse's — **follow drvPS2Mouse**, whose reviewed source uses
unrolled `do`/`while` compare loops with `i = 11` and `i = 9`, and change only
`IO_R_INVALID_ARG` → `IO_R_UNSUPPORTED` (Finding 10).

## `-[BusMouse setIntValues:forParameter:count:]` — 1420, IDA extent 146

Signature: `- (IOReturn)setIntValues:(unsigned *)array forParameter:(IOParameterName)name
count:(unsigned)count` (`i20@8:12^I16*20I24`). `count` is never read.

```
1420 push ebp; mov ebp,esp; sub esp,4; push edi; push esi; push ebx
1429 mov  ebx, [ebp+8]         ; self
1432 mov  eax, [ebp+14h]       ; parameterName
1435 mov  esi, eax
1437 mov  edi, offset 'Resolution'
1442 mov  dword ptr [ebp-4], 0Bh
1449 mov  ecx, [ebp-4]
1452 cld
1453 test al, 0
1455 repe cmpsb
1457 jnz  1492
1459 mov  edx, [ebp+10h]
1462 mov  edx, [edx]
1464 mov  [ebx+12Ch], edx      ; resolution = *parameterArray
1470 mov  ecx, ds:paGetresolution
1476 push ecx
1477 push ebx
1478 call _objc_msgSend        ; [self getResolution]
1483 push eax
1484 mov  edx, ds:paSetresolution
1490 jmp  1541
1492 mov  esi, eax
1494 mov  edi, offset 'Inverted'
1499 mov  ecx, 9
1504 cld
1505 test al, 0
1507 repe cmpsb
1509 jz   1520
1511 mov  eax, 0FFFFFD39h      ; IO_R_UNSUPPORTED (-711)
1516 jmp  1556
1520 mov  ecx, [ebp+10h]
1523 mov  cl, [ecx]
1525 mov  [ebx+130h], cl       ; inverted = *(char *)parameterArray
1531 movsx eax, cl
1534 push eax
1535 mov  edx, ds:paSetinverted
1541 push edx                  ; shared tail
1542 mov  ebx, [ebx+128h]      ; target -- no nil check (Finding 11)
1548 push ebx
1549 call _objc_msgSend        ; [target setResolution:] / [target setInverted:]
1554 xor  eax, eax             ; IO_R_SUCCESS
1556 lea esp,[ebp-10h]; pop ebx; pop esi; pop edi; mov esp,ebp; pop ebp; ret
```

Note that the `Resolution` branch **re-reads the value through `[self getResolution]`** rather
than forwarding `*parameterArray`, and that `setInverted:` is passed the sign-extended `char`.
Identical shape and identical size (148 with padding) to drvPS2Mouse's — **follow
drvPS2Mouse**, with two changes: `IO_R_UNSUPPORTED` (Finding 10, already fixed there) and
**drop the `target != nil` guards** drvPS2Mouse kept (Finding 11).

## `+[BusMouseKernelServerInstance kernelServerInstance]` — 1568, 12 bytes

```
1568 push ebp; mov ebp,esp; mov eax, offset _BusMouse_instance (0x2030); mov esp,ebp; pop ebp; ret
```

## `+[BusMouseVersion driverKitVersionForBusMouse]` — 1580, 12 bytes

```
1580 push ebp; mov ebp,esp; mov eax, 1F4h (500); mov esp,ebp; pop ebp; ret
```

## Functions examined with no divergence found

Instruction-level match (`assembly-matched` in the ledger): `-[BusMouse free]` (1224) and
`-[BusMouse getHandler:level:argument:forInterrupt:]` (1268). These are the only two functions
in the driver whose emitted instruction streams reproduce the reference exactly today.
`getHandler:` still carries the declaration-level divergence recorded under Finding 2
(`argument:` is `unsigned int *`, not `void **`), which does not appear in the code.

No function in this driver was reviewed at control-flow level only.

---

# Fix pass (Task 12): results

All eleven hand-written functions were rewritten from the specification above and the file was
reordered to the reference's `__text` order. Build, parity and per-function sizes below are
measured against `out/i386/drvBusMouse/BusMouse.config/BusMouse_reloc` as produced by
`sh vm/build-i386-input-recon.sh drvBusMouse` on the Rhapsody guest.

## Build and parity

| | Baseline | After |
| --- | --- | --- |
| harness | `EXIT=0` | `EXIT=0` |
| `gnumake` | `make exit=0` | `make exit=0` |
| `_reloc` size | 108416 | 99120 |
| `missing_strings` | **7** | **0** |
| `missing_symbols` | 0 | 0 |
| `extra_strings` | **7** | **0** |
| `extra_symbols` | 19 | 17 |
| `parity_check.py` | exit 1 | exit **0** |

The 17 remaining `extra_symbols` are all debug stabs of an unstripped build (`BusMouse.m`,
`io_inline.h`, the generated `BusMouse_instance.m`, and one `:fNN` line-number stab per
function). The reference is stripped to 13 `__text` symbols.

## Per-function sizes against the reference partition

Sizes are the gaps between consecutive `__TEXT,__text` symbol addresses, the same convention
the brief's partition table uses.

| function | ref addr | ref size | our size | delta |
| --- | ---: | ---: | ---: | ---: |
| `_GetIRQFromBoard` | 0 | 112 | 124 | **+12** |
| `-[BusMouse validConfiguration:]` | 112 | 132 | 132 | +0 |
| `_MouseIntHandler` | 244 | 408 | 400 | -8 |
| `-[BusMouse interruptHandler]` | 652 | 56 | 56 | +0 |
| `_BusMouseThread` | 708 | 124 | 124 | +0 |
| `-[BusMouse mouseInit:]` | 832 | 392 | 392 | +0 |
| `-[BusMouse free]` | 1224 | 44 | 44 | +0 |
| `-[BusMouse getHandler:level:argument:forInterrupt:]` | 1268 | 40 | 40 | +0 |
| `-[BusMouse getResolution]` | 1308 | 16 | 16 | +0 |
| `-[BusMouse getIntValues:forParameter:count:]` | 1324 | 96 | 96 | +0 |
| `-[BusMouse setIntValues:forParameter:count:]` | 1420 | 148 | 136 | -12 |
| `+[BusMouseKernelServerInstance kernelServerInstance]` | 1568 | 12 | 12 | +0 |
| `+[BusMouseVersion driverKitVersionForBusMouse]` | 1580 | 12 | 12 | +0 |
| **total** | | **1592** | **1584** | **-8** |

**One function overshoots, by 12 bytes.** Ten of thirteen match the reference size exactly and
two come in smaller. The overfit guard is satisfied: nothing here is structure that was
invented rather than reconstructed, and the three residuals are named individually below.

## Instruction-stream comparison

Both binaries were disassembled with capstone and compared instruction by instruction, with
link-time addresses normalized away (the two images place `__cstring` at different bases and
ours runs 12 bytes long from `_GetIRQFromBoard` onward). **Ten of the thirteen functions
reproduce the reference's instruction stream exactly.** The three that do not:

- **`_GetIRQFromBoard`** - 52 instructions against the reference's 44. gcc spills the masked
  low-nibble copy to `[ebp-8]` and reloads it before each of the three later bit tests, where
  the reference keeps it in `cl` and puts the result in `ebx`. Every other instruction
  corresponds one for one. Register allocation, not structure; `unsigned char` and
  `unsigned int` spellings of the copy were both tried and both cost the same 12 bytes.
- **`_MouseIntHandler`** - 115 instructions against 117, and 8 bytes shorter. Two places where
  the reference is looser: it widens the left-button value to 32 bits *before* the `xor 1`
  where ours does the `xor` at byte width, and it spills the shifted right-button byte to
  `[ebp-8]` where ours keeps it in a register. One place where ours is looser: an extra
  `and al, 1` in the `rightButton` bitfield store, because gcc did not prove the value was
  already 0 or 1. All ten port accesses, both `__bss` paths and every offset match.
- **`-[BusMouse setIntValues:forParameter:count:]`** - 52 instructions against 56, 12 bytes
  shorter. The reference spills both the `parameterArray` pointer and the compare count to the
  stack (`sub esp, 4`); ours hoists the load and keeps the count immediate. Both `repe cmpsb`
  comparisons, both ivar stores, the shared unguarded `objc_msgSend` tail and
  `IO_R_UNSUPPORTED` all match.

## Emitted sections against the reference

| Section | Reference | Ours |
| --- | ---: | ---: |
| `__TEXT,__text` | 1592 | 1584 |
| `__TEXT,__cstring` | 340 | **340** |
| `__TEXT,__const` | 170 | *absent* |
| `__DATA,__bss` | 48 | **48** |
| `__DATA,__common` | 4 | **4** |
| `__OBJC,__message_refs` | 60 | **60** |
| `__OBJC,__class` | 120 | **120** |
| `__OBJC,__meta_class` | 120 | **120** |
| `__OBJC,__cls_meth` | 40 | **40** |
| `__OBJC,__inst_meth` | 104 | **104** |
| `__OBJC,__class_names` | 111 | **111** |
| `__OBJC,__meth_var_types` | 112 | **112** |
| `__OBJC,__meth_var_names` | 389 | **389** |
| `__OBJC,__module_info` | 32 | **32** |
| `__OBJC,__symbols` | 36 | **36** |
| `Loaded Server,Server Name` | 8 | **8** |
| `Loaded Server,Load Commands` | 164 | **164** |
| `Loaded Server,Unload Commands` | 102 | **102** |
| `Loaded Server,Instance Var` | 17 | **17** |
| `Loaded Server,Server Version` | 1 | **1** |

Every section matches but `__text` and `__TEXT,__const`. The `__const` gap is
`_BusMouse_VERS_STRING` and `_BusMouse_VERS_NUM`; as recorded above, no driver in this
repository emits NeXT's `vers_string` symbols, and that remains out of scope.

Stronger than the sizes: all four string tables are **identical sets** - `__TEXT,__cstring`,
`__OBJC,__class_names`, `__OBJC,__meth_var_types` and `__OBJC,__meth_var_names`.
`__DATA,__bss` is identical **symbol for symbol at identical addresses**: `_xxx.86`,
`_xxx.89`, `_xxx.92`, `_higherLevelsBusy`, `_event`, `_summedEvent`, `_lastRightButton`,
`_lastLeftButton`, then `_BusMouse_instance` in `__common`. And decoding `__OBJC,__class` and
`__OBJC,__meta_class` out of both images gives the same six records: `instance_size` 324 with
`ivars = 0x0` for `BusMouse`, 264 for `BusMouseVersion`, 4 for
`BusMouseKernelServerInstance`, and `methodLists = NULL` on `BusMouse`'s meta-class.

## Resolution of each finding

| Finding | Resolution |
| --- | --- |
| 1 - derives from `PCPointer`, no own ivars | **Fixed.** `@interface BusMouse : PCPointer` with no ivar block; `-DDRIVER_PRIVATE` added to the `.lksproj` Makefile. Verified in the rebuilt binary: `instance_size` 324, `ivars = 0x0`, `__instance_vars` empty, and every ivar access at 0x128/0x12c/0x130. |
| 2 - return types, `mouseInit:` polarity, `+probe:` | **Fixed, in the same commit as Finding 1.** `mouseInit:` and `validConfiguration:` return `BOOL` (1 = success); `getResolution` returns `int`; `argument:` is `unsigned int *`; `+probe:` removed. Verified: `__meth_var_types` is an identical set including `c12@8:12@16` and `i8@8:12`, `__cls_meth` is 40 bytes, and the meta-class `methodLists` is NULL. |
| 3 - `__DATA,__bss` layout | **Fixed.** The five statics are declared in the reference's order with no initializers, `_event` and `_summedEvent` as `PCPointerEvent`. `__bss` is 48 bytes with identical symbols at identical addresses, and `__DATA,__data` is gone. |
| 4 - the `__cstring` set | **Fixed.** All ten strings reproduced byte for byte, including `Bus Mouse : ` with the space in exactly the two `validConfiguration:` strings, the two spaces after the period, and `Bus mouse running`. `missing_strings` and `extra_strings` are both 0 and the section is 340 bytes. |
| 5 - `_GetIRQFromBoard` is global | **Fixed.** `static` dropped. Verified at nlist level: the symbol is `external` in `__TEXT,__text`; `_MouseIntHandler` and `_BusMouseThread` remain `local`. |
| 6 - `ioPortCount` is decompiler residue | **Fixed.** The static, its four increment statements and the empty `LOCK()`/`UNLOCK()` macros are gone. The rebuilt binary emits `lock incl ds:_xxx.86` from `outb()` alone, ten times, and carries no counter object. |
| 7 - `MouseIntHandler` returns a value | **Fixed.** Now `static void MouseIntHandler(void *identity, void *state, unsigned int arg)`; `arg` is never read, matching the reference's untouched `[ebp+10h]`. |
| 8 - the invented `interrupt_msg_t` | **Fixed.** A bare `msg_header_t msg, *msgPtr = &msg;` - 24 bytes, `msg_size` at +4, `msg_local_port` at +0x0C, `msg_id` at +0x14 - and the failure test is against `RCV_SUCCESS`. |
| 9 - 30 us where the reference waits 30 ms | **Fixed.** `IODelay(30)` replaced by `us_spin(30000)` through a local `extern void us_spin(unsigned int);`. `_us_spin` is an undefined import of the rebuilt object and neither `_IODelay` nor `_IOSleep` is. |
| 10 - `IO_R_UNSUPPORTED`, not `IO_R_INVALID_ARG` | **Fixed** at both sites. `mov eax, 0FFFFFD39h` in both methods. |
| 11 - `setIntValues:` messages `target` unguarded | **Kept, deliberately.** drvPS2Mouse's `if (target != nil)` guards were **not** copied across. Verified: both branches converge on one `mov ebx,[ebx+128h]; push ebx; call _objc_msgSend` with no test. |
| 12 - `PCPatoi`, not `strtoul` | **Fixed.** `_PCPatoi` is an undefined import; `strtoul` and `<libkern/libkern.h>` are gone. |
| 13 - the set of statics `mouseInit:` initializes | **Fixed.** Seven stores in the reference's order: `higherLevelsBusy = 0`, `summedEvent.data.buf[2]`, `buf[1]`, `summedEvent.timeStamp`, then both trackers to -1. `_event` is not touched. |
| 14 - the doubled port-0x23E command | **Accepted; both writes kept.** The rebuilt binary emits `out dx,al` twice from the same `dx` and `al`. |
| 15 - `Load_Commands.sect` one byte short | **Fixed.** First line is now `#`, space, newline; the file is 164 bytes and the emitted section is 164. |
| 16 - `Unload_Commands.sect` absent | **Fixed.** Copied byte for byte from drvPS2Mouse's (102 bytes, six trailing blank lines intact) and added to the `.lksproj` Makefile's `OTHERSRCS`; `kernelserver.make`'s `UNLOAD_SECTION = Unload_Commands.sect` picks it up. The emitted section is 102 bytes. |

## Three findings the fix pass discovered

**Finding 17 - the `Inverted` parse is written in the positive form.** The reference branches
`test ecx,ecx; jz(set 0)`, `cmp [ecx],'y'; jz(set 1)`, `cmp [ecx],'Y'; jnz(set 0)`, and places
the `mov byte [esi+130h], 1` block *before* the `0` block. That is
`if (str != NULL && (*str == 'y' || *str == 'Y')) inverted = YES; else inverted = NO;`. The
negated form this document and drvPS2Mouse both use mirrors the two blocks. Fixed; `mouseInit:`
now reproduces the reference's stream exactly.

**Finding 18 - `getIntValues:`/`setIntValues:` compare with an inlined `strcmp`, not a loop.**
The reference's `cld; repe cmpsb` with `ecx` = 11 and 9 is gcc's expansion of
`strcmp(name, "Resolution")` against a constant string when the result is only tested for
zero, the count being `strlen + 1`. The unrolled `do`/`while` compare loops this document
recommended taking from drvPS2Mouse are a decompiler rendering of that expansion, and they
build 32 and 36 bytes over the reference. Rewritten as `strcmp(...) == 0`, which gcc inlines
with no `_strcmp` import: `getIntValues:` lands on 96 bytes exactly and `setIntValues:` on 136.
**This is the one place where following drvPS2Mouse was wrong**, and it is worth checking
against drvPS2Mouse's own reference.

**Finding 19 - `validConfiguration:` shares one `return NO`.** The reference tests the failure
case first and lets both failure paths fall into a single `xor eax, eax`:
`if (signature != 0xa5) { IOLog(...); } else { ...; if (equal) return YES; IOLog(...); }`
followed by `return NO;`. Writing the two failures as early returns duplicates the
`xor eax, eax` and changes the block order. Fixed; the function now reproduces the reference's
stream exactly.

## Ledger

13 entries, **0 `unexamined`**: 7 `assembly-matched`, 6 `intentional-mismatch`.

- `assembly-matched` - the rebuilt instruction stream was disassembled and compared against the
  reference's and is identical once link-time addresses are normalized:
  `validConfiguration:`, `interruptHandler`, `BusMouseThread`, `mouseInit:`, `free`,
  `getHandler:level:argument:forInterrupt:`, `getResolution`.
- `intentional-mismatch` - a named residual remains: `_GetIRQFromBoard`, `_MouseIntHandler`,
  `getIntValues:forParameter:count:` and `setIntValues:forParameter:count:` for the
  register-allocation differences described above (and in Task 4), plus the two
  build-generated glue methods, which keep task 11's reviewer.

## Phase 1 baseline

2026-09-16 guest rebuild of the current tree, no `BusMouse.m` edits. Guest
log: `=== input-recon done fail=0 built: drvBusMouse ===` (`make exit=0`).
Staged unstripped `BusMouse_reloc` is **99112** bytes, SHA-256
`5DC76B2EF94D3C24A8DBEAB4D1B7307B7A70C66D4A02ED0D3AB0448C48429A38`.
`parity_check.py`: `missing_strings` **0**, `missing_symbols` **0**,
`extra_strings` **0**, `extra_symbols` **17**. `__TEXT,__text` is 1584;
`__TEXT,__const` is still absent. This `_reloc` is not kept as the campaign
result; `rebuilt_sha256` is unchanged. See `function-worklist.md`.

## Phase 2 / Task 3: Kernel Server `VERS_OFILE`

2026-09-16. Created
`BusMouse.drvproj/BusMouse.lksproj/Makefile.postamble` as the single line
`OTHER_GENERATED_OFILES += $(VERS_OFILE)` (trailing newline, LF). No
Driver-project postamble. `driverTools` and guest-installed makefiles were
not edited. `BusMouse.m` was not edited.

Guest rebuild: `=== input-recon done fail=0 built: drvBusMouse ===`
(`make exit=0`). Host SHA-256 of the staged unstripped `BusMouse_reloc` is
still `5DC76B2EF94D3C24A8DBEAB4D1B7307B7A70C66D4A02ED0D3AB0448C48429A38`
(99112 bytes) — byte-identical to the Phase 1 object. `__TEXT,__text` is
still 1584. `__TEXT,__const` is still absent.
`_BusMouse_VERS_STRING` and `_BusMouse_VERS_NUM` are **MISSING** from the
nlist. `parity_check.py` is unchanged (`missing_strings` 0,
`missing_symbols` 0, `extra_strings` 0, `extra_symbols` 17). All seven
locked regression-gate methods still have `masked-eq` or `identical`.

**Guest evidence for the unmet existence gate.** The postamble is on the
guest (40 bytes, exact contents). `gnumake -p` in the lksproj shows
`VERSIONING_SYSTEM = next-sgs` and
`OTHER_GENERATED_OFILES = $(INSTANCE_OBJFILE) $(VERS_OFILE)` — the
postamble was included — but there is no `VERS_OFILE =` assignment.
`/System/Developer/Makefiles/VersioningSystems` contains only
`apple-generic.make` and `next-cvs.make`; there is no `next-sgs.make`, so
`common.make`'s `-include` of that path is silent and `$(VERS_OFILE)`
expands empty. `find` under the driver tree returned no `*vers*` files.
The object directory has `BusMouse.o` and `BusMouse_instance.o` only.
`kl_ld` line (no `*_vers.o`):

```
/usr/bin/kl_ld -o /build/src/drivers-i386/input/drvBusMouse/BusMouse.config/BusMouse_reloc -n BusMouse  -i BusMouse_instance -l Load_Commands.sect -u Unload_Commands.sect  -arch i386  /build/src/drivers-i386/input/drvBusMouse/BusMouse.build/objects-optimized/BusMouse.drvproj/BusMouse.lksproj/BusMouse.o             /build/src/drivers-i386/input/drvBusMouse/BusMouse.build/objects-optimized/BusMouse.drvproj/BusMouse.lksproj/BusMouse_instance.o
```

Existence stays unmet. The postamble line is kept (diagnosed reconstruction,
not an experiment). See `function-worklist.md`.

### Task 3 follow-up: `VERSIONING_SYSTEM = apple-generic`

2026-09-16. In-tree Kernel Server preamble now starts with
`VERSIONING_SYSTEM = apple-generic`; existing preamble contents kept.
Postamble still `OTHER_GENERATED_OFILES += $(VERS_OFILE)`. `driverTools`
and guest-installed makefiles were not edited.

Guest rebuild: `=== input-recon done fail=0 built: drvBusMouse ===`
(`make exit=0`). Log shows `Creating .../BusMouse_vers.c` (twice, with
`*** Warning: the CURRENT_PROJECT_VERSION variable is not set.`), compile of
`BusMouse_vers.i386.o`, and `kl_ld` with `BusMouse_vers.o` after
`_instance.o`:

```
/usr/bin/kl_ld -o /build/src/drivers-i386/input/drvBusMouse/BusMouse.config/BusMouse_reloc -n BusMouse  -i BusMouse_instance -l Load_Commands.sect -u Unload_Commands.sect  -arch i386  /build/src/drivers-i386/input/drvBusMouse/BusMouse.build/objects-optimized/BusMouse.drvproj/BusMouse.lksproj/BusMouse.o             /build/src/drivers-i386/input/drvBusMouse/BusMouse.build/objects-optimized/BusMouse.drvproj/BusMouse.lksproj/BusMouse_instance.o /build/src/drivers-i386/input/drvBusMouse/BusMouse.build/objects-optimized/BusMouse.drvproj/BusMouse.lksproj/BusMouse_vers.o
```

Host staged unstripped `BusMouse_reloc` is **100372** bytes, SHA-256
`2EAA0112FDA184A6F13305EB6438E2A20C6125D1DF37FB370868824D8C2FC1F9`.
`__TEXT,__text` is still 1584. `__TEXT,__const` is **present, 92 bytes**.
`parity_check.py`: `missing_strings` 0, `missing_symbols` 0,
`extra_strings` 0, `extra_symbols` **18** (the extra stab is generated
`BusMouse_vers.c`). All seven locked regression-gate methods still have
`masked-eq` or `identical`. `--list` instruction-diff table is unchanged
from Phase 1. `rebuilt_sha256` is not set.

Nlist in `__TEXT,__const`: `_BusMouseVersionString` and
`_BusMouseVersionNumber` (both external). SGS names
`_BusMouse_VERS_STRING` and `_BusMouse_VERS_NUM` are still **MISSING**.
The `__const` section gap is closed; the leftover is the apple-generic
symbol names, same as Cirrus. Do not compare the 160-byte SGS string to
Apple's. See `function-worklist.md`.

## Task 4 / Phase 3: cheapest-first grinding

2026-09-16. Ranking from `--list` (ignore glue; ignore raw_equal /
masked_equal / identical) superseded the plan's starter order:
`getIntValues:` (7), `setIntValues:` (20), `_MouseIntHandler` (22),
`_GetIRQFromBoard` (24). `BusMouse.m` was not kept-changed. Locked
regression gates stayed `masked-eq` / `identical` on every measured
rebuild. Glue is still only the two generated class methods.

Final accepted-source reloc: 100372 bytes, SHA-256
`55BB1C543C383A311E57447DDD6B722D251ED577D2769BC9ECD0475334C9815D`
(vers timestamp differs from Task 3's `2EAA0112…`).
`parity_check.py`: `missing_strings` 0, `missing_symbols` 0.
Ledger after this pass: **7 `assembly-matched`**, **6 `intentional-mismatch`**,
**0 `unexamined`**.

### `-[BusMouse getIntValues:forParameter:count:]` — accept (gcc spill)

Capstone had this assembly-matched; IDA shows 7 diffs. `--name` dump
(status=different; `instruction layout differs`):

```
  reference                               rebuilt
  … same prologue, same mov esi/edi, mov ecx,0Bh, cld, test al,0, cmpsb …
* jnz loc_558                             jnz loc_55C
* mov edx, [edx+12Ch]                     mov eax, [edx+12Ch]
* jmp loc_57B                             jmp loc_57F
  … same Inverted cmpsb ecx=9 …
* jz loc_574                              jz loc_578
  mov eax, 0FFFFFD39h                     mov eax, 0FFFFFD39h
* jmp loc_57F                             jmp loc_583
* movsx edx, byte ptr [edx+130h]          movsx eax, byte ptr [edx+130h]
* mov [ebx], edx                          mov [ebx], eax
  xor eax, eax                            xor eax, eax
  lea esp, [ebp-0Ch]                      lea esp, [ebp-0Ch]
  … same epilogue …
```

Same calls, same constants, same offsets 0x12C / 0x130, same
`IO_R_UNSUPPORTED`. Leftover is the stored value in `edx` vs `eax` and
the jump labels that follow. Dummy locals were not added.

**Disposition:** accept. Ledger `intentional-mismatch`, reviewer
`Pat Raynor`, reason gcc spill.

### `-[BusMouse setIntValues:forParameter:count:]` — accept (gcc spill)

`--name` differs only by gcc hoist/spill of `parameterArray` / compare
count (ours smaller, 49 vs 53 instructions). No missing call, no wrong
offset. Starter list treated as empty; Exp 1/2 were not run. Dummy
spills were not added to chase 148.

```
  reference                               rebuilt
* sub esp, 4
  …
* mov eax, [ebp+arg_C]                    mov eax, [ebp+arg_8]
* mov esi, eax                            mov esi, [ebp+arg_C]
* mov [ebp+var_4], 0Bh                    mov ecx, 0Bh
* mov ecx, [ebp+var_4]
  … same cmpsb, [ebx+12Ch] store, getResolution send, shared unguarded
    tail to [ebx+128h], IO_R_UNSUPPORTED, both objc_msgSend present …
* lea esp, [ebp-10h]                      lea esp, [ebp-0Ch]
```

**Disposition:** accept. Ledger `intentional-mismatch`, reviewer
`Pat Raynor`, reason gcc spill.

### `_MouseIntHandler` — accept / unreachable

Starter experiments, each rebuilt and measured; gates never lost
`masked-eq` / `identical`. Source restored after every miss.

| Exp | change | result |
| --- | --- | --- |
| 1 | widen left before `^= 1` | miss, 22→21 diffs, no regression; reverted |
| 2 | `unsigned char temp` for `buttonByte >> 5` | miss, 22 diffs (gcc elided `temp`); reverted |
| 3 | `right = ((buttonByte >> 5) & 1) ^ 1` | miss, 21 diffs (spilled `var_8`, dropped extra `and al,1`); reverted |

Empty list. Leftover is register allocation / scheduling: `sub esp,10h`
vs `0Ch`, xor-before-movzx on left, no `[ebp-8]` spill of the right
shift, extra `and al,1` on the bitfield store. Same ten port accesses,
doubled `outb(0x23e, 0x80)`, busy-accumulate vs post-and-clear.

**Disposition:** accept as unreachable. Ledger `intentional-mismatch`,
reviewer `Pat Raynor`.

### `_GetIRQFromBoard` — accept / unreachable

Port 0x23E, 0xF000 count, and the 5/4/3/2/0 ladder were not changed
except inside named experiments, all reverted.

| Exp | change | result |
| --- | --- | --- |
| 1 | drop `lowBits`, inline `(changed & 0x0f)` | miss, 24→18 diffs; gcc dropped the mask and tested `bl`; reverted |
| 2 | `if (lowBits & 1)` | miss, 24 diffs (`test bl, 1` still); reverted |
| 3 | `unsigned int lowBits` | miss, 24→22 diffs; mask in `esi`, extra `push esi`; reverted |
| 4 | flatten IRQ-2 `else if` | miss, 24 diffs (same dump as original); reverted |

Empty list. Leftover is gcc spilling the masked nibble to `[ebp-8]` and
putting the IRQ in `ecx` instead of `ebx`. Dummy locals were not added.

**Disposition:** accept as unreachable. Ledger `intentional-mismatch`,
reviewer `Pat Raynor`.

## Closing

Campaign grinding is complete. 7/11 hand-written functions are IDA
masked-eq or identical: `-[BusMouse validConfiguration:]`,
`-[BusMouse interruptHandler]`, `_BusMouseThread`, `-[BusMouse mouseInit:]`,
`-[BusMouse free]`, `-[BusMouse getHandler:level:argument:forInterrupt:]`,
`-[BusMouse getResolution]`. Four leftovers were accepted as gcc 2.7
register allocation / spill / scheduling:
`-[BusMouse getIntValues:forParameter:count:]` (edx vs eax store),
`-[BusMouse setIntValues:forParameter:count:]` (parameterArray/count hoist),
`_MouseIntHandler` (button-decode scheduling), `_GetIRQFromBoard`
(masked-nibble spill). Two Kernel Server glue methods remain generated.
Last kept rebuilt `BusMouse_reloc` is 100372 bytes, SHA-256
`55BB1C543C383A311E57447DDD6B722D251ED577D2769BC9ECD0475334C9815D`.
`__TEXT,__const` is 92 bytes with apple-generic `_BusMouseVersionString` /
`_BusMouseVersionNumber`; SGS `_BusMouse_VERS_*` names are absent
(documented leftover, same as Cirrus). Not yet tested on hardware.

## Default.table: "Server Name" came out twice

2026-09-25. Not a divergence: the earlier comparisons of `Default.table` with
the reference did not allow for the build's append.

The driver build's `post_copy_tables` rule
(`src/driverTools-1/DriverProjectType/driver.make:154-159`) appends
`"Server Name" = "$(NAME)";` to every table. That is where the reference's line,
just before the build-stamped `"Driver Version"`, comes from. Our source table
carried the line as well, so the built table had it twice. The line is gone from
the source, and the built table now matches the reference's except for the build
stamp.
