# IOADBDevice reconstruction findings

**Nothing in this document is compile-verified.** There is no PowerPC toolchain and no host C
compiler in this tree; `make` was never run against this project and no claim is made that any of it
compiles, links, loads or behaves as Apple's does. **For a driver with no prior in-tree source this
gap is wider than in any preceding spec in this series** — every other reconstruction had Apple's own
source next to the binary to contradict a wrong reading. Here nothing constrains a wrong reading
except the disassembly itself, so this document records uncertainty rather than resolving it by
plausibility.

## Artifacts

| Artifact | Size | SHA-256 |
| --- | --- | --- |
| `IOADBDevice.config/IOADBDevice` | 8496 | `AA6067113CE1E6E2902DE33EEC3209F2BEF3E7BF2C821FEB235E72881227A515` |
| `IOADBDevice.config/IOADBDevice_reloc` | 34180 | `EA515EE4794B771E1482344E921EE51D7D5E8AEAD77927CBC0DED9282E6997B5` |
| `IOADBDevice.config/Default.table` | 420 | `CFBD3FE21532B0C51CBE5FA0A6D87FC11C1AE6FA4E4D4D731953210F40DCB3F0` |
| `IOADBDevice.config/adbservd` | 21624 | `D8E0A85D3E930410B2FA1BEBFF1E3067036BB8FB00CDD38B24E5FA55AA5885AC` |

`src/drivers-ppc/reconstruction/IOADBDevice/source-map.json`'s own `reference_sha256` reproduces the
`IOADBDevice_reloc` hash above exactly.

`adbservd` (21624 bytes on disk, 1488 bytes of `__text`, 30 C functions, no Objective-C) is this
driver's userspace companion and is **out of scope**: `--scope-to-objc` maps nothing for it, so no
mechanical check applies. It has its own spec.

### Sections

```
__TEXT,__text      addr 0x0000  size 5524
__TEXT,__cstring   addr 0x1594  size 1252
__TEXT,__const     addr 0x1a78  size  202
__DATA,__data      addr 0x2000  size   24
__DATA,__bss       addr 0x2018  size 3852
__DATA,__common    addr 0x2f24  size    4
```

`__TEXT,__const`'s first 32 bytes are `ioadbDeviceIoctl`'s eight-entry jump table; the remaining 170
are the build's `@(#)PROGRAM:IOADBDevice PROJECT:drvIOADBDevice-4 DEVELOPER:root BUILT:Tue Nov 23
19:12:23 PST 1999` string and its padding. That date is the shipping build.

## Correspondence

Source map built with `binrecon source-map --objc-methods --scope-to-objc` against
`IOADBDevice_reloc`:

```
mapped 15 unmapped 2 dup 0 disputed 0
  unmapped: +[IOADBDeviceKernelServerInstance kernelServerInstance]
  unmapped: +[IOADBDeviceVersion driverKitVersionForIOADBDevice]
```

**All fifteen Objective-C methods the reference analysis has functions for map.** Only the two
build-generated accessors remain, which is the expected floor for every driver in this series. A
sixteenth method, `+[IOADBDevice GetTable:length:]`, is written but cannot appear here at all --
see below.

```
-[IOADBDevice initForDevice:result:]                  -> IOADBDevice.m:268
-[IOADBDevice free]                                   -> IOADBDevice.m:341
-[IOADBDevice getADBInfo:]                            -> IOADBDevice.m:365
-[IOADBDevice flushADBDevice]                         -> IOADBDevice.m:388
-[IOADBDevice readADBDeviceRegister:buffer:length:]   -> IOADBDevice.m:411
-[IOADBDevice writeADBDeviceRegister:buffer:length:]  -> IOADBDevice.m:434
-[IOADBDevice setState:mask:]                         -> IOADBDevice.m:457
-[IOADBDevice getState]                               -> IOADBDevice.m:470
-[IOADBDevice watchState:mask:]                       -> IOADBDevice.m:481
+[ADBServer serverMajor:]                             -> ADBServer.m:232
+[ADBServer deviceStyle]                              -> ADBServer.m:272
+[ADBServer requiredProtocols]                        -> ADBServer.m:301
+[ADBServer probe:]                                   -> ADBServer.m:349
-[ADBServer initFromDeviceDescription:]               -> ADBServer.m:427
-[ADBServer getIntValues:forParameter:count:]         -> ADBServer.m:475
```

(paths relative to
`src/drivers-ppc/input/drvIOADBDevice/IOADBDevice.drvproj/IOADBDevice.lksproj/`).

- Total functions in the reference analysis (`ioadbdevice-ppc`): 67, 5312 bytes — 212 bytes short of
  `__text`, the one function IDA omits.
- Objective-C methods with function entries: 17 — 15 mapped + 2 unmapped, 2416 bytes. An eighteenth
  Objective-C method, `+GetTable:length:` (212 bytes), has no function entry.
- Out of scope: 50 — 44 unnamed jump islands (704 bytes) and 6 named C functions (2192 bytes).
- `duplicate_candidates`: 0. `boundary_disputed`: 0.

**`+[IOADBDevice GetTable:length:]` does not appear in the map at all, not even as unmapped -- and
that is a property of IDA's analysis, not of Apple's binary.** Its implementation address in
`__OBJC,__cls_meth` is `0` because it is the first function in `__text`, and IDA's function list
carries no entry at `0`: its lowest entry is `0xd4`, the jump island that belongs to this very
function. The map's universe is scoped to that function list, so a function IDA never recorded
cannot be classified by it.

The code is there. `__text+0` reads `7c0802a6` -- `mflr r0` -- and runs 212 bytes to a `blr` at
`0xd0`, followed by a four-instruction jump island at `0xd4`-`0xe0`; `-initForDevice:result:` does
not begin until `0xe4`. The arithmetic confirms it independently: `__TEXT,__text` is 5524 bytes and
the 67 functions IDA reports total 5312. **The 212-byte difference is exactly this function.** The
body is transcribed at `IOADBDevice.m:200`.

See "The misreading" below for how this came to be recorded the other way round.

### Selector check

```
reference selectors: 18
our definitions:     16

renames (0):
duplicates (0):
missing (2):
    +[IOADBDeviceKernelServerInstance kernelServerInstance]
    +[IOADBDeviceVersion driverKitVersionForIOADBDevice]
extra (0):
```

Zero renames and zero extras: every selector we define is spelled as Apple's binary spells it, and we
define nothing Apple's binary does not have. The two missing are the Kernel Server build products.
`selector_check.py` matches on selector string rather than on function-start validity, which is why
it saw `+GetTable:length:` in the binary all along -- and why its earlier "missing (3)" was the first
place the tree recorded a method that is in fact present.

### The three modules

`__OBJC,__module_info` recovers Apple's own source file names:

```
module 0: name="IOADBDevice.m"           defs: IOADBDevice
module 1: name="ADBServer.m"             defs: ADBServer
module 2: name="IOADBDevice_instance.m"  defs: IOADBDeviceVersion, IOADBDeviceKernelServerInstance
```

Our two source files carry Apple's names. `__text` order matches module order and, within a module,
is source order: `IOADBDevice`'s ten methods -- `+GetTable:length:` first, at `__text+0` -- then
`initalize`; `ADBServer`'s six methods then the
five character-device C functions; then the two generated accessors. Both files are laid out that
way, with the C functions after their `@end`.

## Map validation

`load_source_map` enforces an exact partition between the map's addresses and the reference analysis
passed to it, so verifying a `--scope-to-objc` map requires scoping the analysis to the same covered
addresses first: the map does not claim the 44 unnamed jump islands or the 6 C functions, and the
bucket reconciliation below accounts for those 50 separately.

```
analysis functions 67 -> scoped 17
load_source_map OK
```

## Buckets

`bucket_functions.py` against `ioadbdevice-ppc`'s published analysis and this map:

```
total functions: 67
  mapped: 15
  1-crt-dyld: 0
  2-picsymbol-stub: 0
  3-unnamed-jump-island: 44
  4-build-generated-class: 2
      0x1570  +[IOADBDeviceKernelServerInstance kernelServerInstance]  (20 bytes)
      0x1584  +[IOADBDeviceVersion driverKitVersionForIOADBDevice]  (16 bytes)
  5-fn-with-source-site: 0
  6-fn-no-source-site: 6
      0x5fc  _initalize  (436 bytes)
      0xd84  _adbServeropen  (224 bytes)
      0xe94  _adbServerclose  (220 bytes)
      0xfa0  _adbServerioctlDispatch  (172 bytes)
      0x108c  _adbServerIoctl  (444 bytes)
      0x1278  _ioadbDeviceIoctl  (696 bytes)
counted: 67
RECONCILES: yes
```

Buckets 1 and 2 are empty as expected for a statically linked `_reloc` kernel server.

### Bucket 6 resolved to bucket 5 by hand

`bucket_functions.py` reads bucket membership from the `--scope-to-objc` map, which by construction
claims no C functions, so all six land in bucket 6. All six now have source sites:

| Function | Address | Source site |
| --- | --- | --- |
| `_initalize` | `0x5fc` | `IOADBDevice.m:570` |
| `_adbServeropen` | `0xd84` | `ADBServer.m:537` |
| `_adbServerclose` | `0xe94` | `ADBServer.m:591` |
| `_adbServerioctlDispatch` | `0xfa0` | `ADBServer.m:654` |
| `_adbServerIoctl` | `0x108c` | `ADBServer.m:736` |
| `_ioadbDeviceIoctl` | `0x1278` | `ADBServer.m:878` |

**Bucket 6 is therefore empty in fact and bucket 5 holds six.** The tool cannot see this, and the
line numbers above are the citation. Every function in this binary now has a source site except the
two build-generated accessors. `+GetTable:length:` is written (`IOADBDevice.m:200`) but appears in
no bucket, because the bucket table enumerates IDA's 67 functions and IDA has no function for it.

## Invariant check

```
symbol +[IOADBDevice GetTable:length:] at 0x0 has no function start in the analysis, but code is present: the bytes there are a function prologue, so the analysis omits a real function
18 scattered/difference-form relocations (target section verified, field is a difference, not an address)
5 HI16/HA16-LO16 pairs checked (reconstructed values must agree)
648 fused relocations, 1 violations
```

The single violation is `+GetTable:length:` at `__text+0`, the same shape Mesh's `_AllocateEventLog`
at `0x0` produces. It is a property of IDA's analysis, not of Apple's binary: the symbol exists, the
address is `0`, the code is there, and IDA's function list does not record it. The checker's older
wording -- "is not a function start" -- was true and was read here as "there is no code there",
which it never said; the checker now says which of the two it means. Every one of the 648 fused
relocations otherwise reconstructs to an address inside a declared section, and all five
`HI16`/`HA16`–`LO16` pairs agree.

## The misreading

This is recorded as a finding because it is one, and because it survived five merged specs.

**What the tool said.** `ppc_invariant_check.py`'s `check_functions` printed:

```
symbol +[IOADBDevice GetTable:length:] at 0x0 is not a function start
```

**What was inferred.** That there is no code at address `0` — that the symbol is a placeholder, that
Apple shipped the selector without a body, and that there was therefore nothing to transcribe. Three
places in this document, plus `IOADBDevice.h`, `IOADBDevice.m`, the design spec and the plan, stated
it as settled fact. The worst formulation was in this file: *"It is a property of Apple's binary, not
of our read."* That is exactly backwards.

**Why it is wrong.**

1. The message says only that the address is not in the analyzer's function list. It says nothing
   about the bytes. IDA misses the function at `__text+0` in every PowerPC driver measured in this
   series.
2. `read_macho` reports address `0` for **undefined** symbols too — `_IOLog`, `_objc_msgSend`,
   `_panic` and eighteen others in this binary alone. A *defined* symbol at `__text+0` is
   indistinguishable from them in that view, which is what made `0` look like "no address" rather
   than "the first address".
3. The bytes settle it: `__text+0` is `7c0802a6`, `mflr r0`, and the function runs 212 bytes to a
   `blr` at `0xd0`.
4. So does the arithmetic: `__text` is 5524 bytes, IDA's 67 functions total 5312, and the difference
   is 212.

**What was done.** The checker now reads the instruction word at the symbol and, when it is a
prologue, says that code is present and that the analysis omits a real function. The five other
drivers whose `findings.md` carried the same misreading are corrected in place; each names a real
unmapped function, not a phantom:

| Driver | Function at `__text+0` | First word |
| --- | --- | --- |
| `drvPPCOHare` | `+[AppleOHare probe:]` | `7c0802a6` |
| `drvPPCBurgundy` | `+[PPCBurgundy probe:]` | `7c0802a6` |
| `drvPPCSym8xx` | `-[Sym8xxController(Execute) commandRequestOccurred]` | `7c0802a6` |
| `drvPPCMesh` | `_AllocateEventLog` | `7c0802a6` |
| `drvPPC53c96` | `+[Apple96_SCSI probe:]` | `7c0802a6` |
| `IODisplay` | `-[IOSmartDisplay registerLoudly]` | `9421ffe0` |

Their bodies are not written here; that is separate work. Their mapped counts do not change, because
IDA never had these functions to map.

## Class layout, and the stub superclass correction

Read from `__OBJC,__class` and `__OBJC,__instance_vars`, walking each metaclass through `isa` for the
class-method lists. Field order used: `isa, super_class, name, version, info, instance_size, ivars,
methods, cache, protocols`.

```
raw fields: ['0x3164', '0x332c', '0x3320', '0x0', '0x1', '0x8', '0x3874', '0x3278', '0x0', '0x0']
class IOADBDevice : Object   instance_size=8 (0x8)
     +0x0004  ^v                           _priv

raw fields: ['0x318c', '0x3354', '0x3348', '0x0', '0x1', '0x10c', '0x3884', '0x32ec', '0x0', '0x0']
class ADBServer : IODevice   instance_size=268 (0x10c)
     +0x0108  {ioadb_state="ioadb"@}       state
```

The raw fields settle the index question by inspection rather than by convention: `0x3320` lies
inside `__OBJC,__class_names` and reads `IOADBDevice`; `0x332c` also lies inside it and reads
`Object`. Index 2 is the name, index 1 the superclass.

**`IOADBDevice : Object`.** The packaging stub declared `IOADBDevice : IODevice`, inferred from the
binary's linked-class list — where `IODevice` does appear, because `ADBServer` needs it. `Object` is
linked too, and only the class table distinguishes them. `IOADBDevice.h:33` was corrected. This is
the first of the three defects the disciplines caught in the stub.

Both classes' `protocols` field (index 9) is `0`: neither class formally adopts a protocol. The one
`__OBJC,__protocol` entry exists solely because `+requiredProtocols` returns a list referencing
`@protocol(ADBprotocol)`.

## The signatures, from encodings

Every signature below is from `__OBJC,__meth_var_types`; **none was inferred from instructions.**

```
IOADBDevice  +GetTable:length:                       i12@4:8^{?=iiiilL}12^i16     0x0
IOADBDevice  -initForDevice:result:                  @12@4:8l12^i16               0xe4
IOADBDevice  -free                                   @4@4:8                       0x39c
IOADBDevice  -getADBInfo:                            i8@4:8^{?=iiiilL}12          0x484
IOADBDevice  -flushADBDevice                         i4@4:8                       0x4c8
IOADBDevice  -readADBDeviceRegister:buffer:length:   i16@4:8i12*16^i20            0x514
IOADBDevice  -writeADBDeviceRegister:buffer:length:  i16@4:8i12*16i20             0x570
IOADBDevice  -setState:mask:                         i12@4:8I12I16                0x5cc
IOADBDevice  -getState                               I4@4:8                       0x5dc
IOADBDevice  -watchState:mask:                       i12@4:8^I12I16               0x5ec

ADBServer    +serverMajor:                           i8@4:8@12                    0x7d0
ADBServer    +deviceStyle                            i4@4:8                       0x8f4
ADBServer    +requiredProtocols                      ^@4@4:8                      0x904
ADBServer    +probe:                                 c8@4:8@12                    0x918
ADBServer    -initFromDeviceDescription:             @8@4:8@12                    0xb40
ADBServer    -getIntValues:forParameter:count:       i16@4:8^I12*16^I20           0xc6c
```

Three signature facts the encodings settled that instructions never would have, and that the
packaging stub had wrong:

1. **`-initForDevice:result:` takes `l`, a `long`, not an object.** The stub declared `(id)device`.
   It is the ADB device's `uniqueID`, and `initalize` is what assigns those uniqueIDs.
2. **The three state methods use `I` / `^I` — `unsigned int`, not `IOADBDeviceState`,** which is
   `unsigned long` and would encode `L` / `^L`. The same binary encodes `IOADBDeviceInfo`'s `long
   uniqueID` and `unsigned long flags` as `l` and `L`, so this compiler does distinguish them and `I`
   is decisive.
3. **The register buffers encode `*`, i.e. `char *`.** `unsigned char *` would encode `^C`. The
   stub, and `IOADBBus.h`'s `ADBprotocol`, both say `unsigned char *`.

`+requiredProtocols`' `^@` cannot distinguish `Protocol **` from `id *`; `IODevice.h` declares it
`Protocol **`, so that spelling was kept and the ambiguity is recorded below.

### The protocol, resolved rather than guessed

`+requiredProtocols` returns `_protocols.30`, eight bytes at `__DATA,__data+0x10`. Its first word
carries a `ppc-vanilla-32-absolute` relocation to `__OBJC,__protocol+0`; its second word is zero. The
`Protocol` structure there is `{0x2, 0x3360, 0x0, 0x3000, 0x0}` — `isa` 2, name `ADBprotocol`, no
protocol list, instance methods at `__OBJC,__cat_inst_meth`. That list's six descriptions are:

```
adb_register_handler::      i16@4:8i12^?20
writeADBDeviceRegister::::  i24@4:8i12i16*20i28
readADBDeviceRegister::::   i24@4:8i12i16*20^i28
flushADBDevice:             i12@4:8i16
getADBInfo::                i16@4:8i12^{?=iiiilL}20
GetTable::                  i16@4:8^{?=iiiilL}12^i20
```

That is **exactly** `IOADBBus.h`'s `ADBprotocol`, selector for selector. It is **not**
`IOADBBusProt.h`'s, whose `buffer:`/`length:` keywords would produce different selectors.
`IOADBBus.h` is therefore the header this reconstruction imports, and the packaging stub's note about
a "buffer:/length: spelling divergence" in the protocol is resolved: the divergent header is
`IOADBBusProt.h`, and this binary does not use it.

`_protocols.30`'s gcc suffix marks a *function-scope* static — file-scope statics in this binary keep
bare names (`_gADBDriver`, `_gDeviceTable`) — so the array is declared inside `+requiredProtocols`.

## Derived data layouts

None of these is in the metadata. All are derived from stride arithmetic and offset usage, and every
name in them except `info` is invented.

### `_priv` — 28 bytes

`-initForDevice:result:` allocates `NXZoneCalloc(zone, 1, 0x1C)`, copies six words from a
`gDeviceTable` entry into `+0x00..0x17`, and stores the table index at `+0x18`. `-getADBInfo:` copies
`+0x00..0x17` straight into an `IOADBDeviceInfo *`, and `-flushADBDevice` and the two register
methods read `+0x04` and pass it as the ADB *device* argument — which is `IOADBDeviceInfo.address`.

### `gDeviceTable` — stride 28, 64 entries

Every index expression is `(i*8 - i)*4`. `+0x00..0x17` is the `IOADBDeviceInfo`; `+0x18` holds the
`id` claiming the slot (written with `self`, cleared in `-free`, and cleared again by `initalize`).

The assertion string at `0x15c0` is `"ASSERTION gDeviceTable[index].info.uniqueID == uniqueID failed
at line %d in %s\n"`. That is `#e` stringification, so **`gDeviceTable`, the local `index`, the field
`info`, and the argument `uniqueID` are recovered, not invented.**

Storage is 1792 bytes (`gDeviceTable` at `__DATA,__bss+0`, `gDeviceCount` at `+0x700`), so the array
is `[64]`. `adb_io.h`'s `ADB_DEVICE_COUNT` and `IOADBBus.h`'s `IO_ADB_MAX_DEVICE` are both **16**, and
no constant with the value 64 exists anywhere in this tree. **64 is a literal and is recorded as
unnamed.**

The table is *packed*, not indexed by ADB address: `initalize` walks addresses 1 through 15 and
appends only present devices, assigning each a one-based `uniqueID` of its own. So at most 15 of the
64 slots can ever be used, and the declared bound is 64 for no reason this binary explains.

### `gADBDeviceIdMap` — stride 8, 256 entries

`+probe:` `bzero`s `0x800` bytes; every index expression is `i*8`; the minor number that indexes it is
masked `& 0xff`; the two words of an entry are used as an object pointer (`+0x00`) and an in-use flag
(`+0x04`). 256 x 8 = 2048 = the whole reservation. **256 is also unnamed in this tree.**

### The two ioctl payloads

Derived entirely from offsets, and then confirmed independently by the ioctl command words, which
encode `sizeof` the payload:

```c
typedef struct {                       /* 32 bytes = 0x020 */
    int             command;                       /* +0x000 */
    IOReturn        result;                        /* +0x004 */
    union {
        long            uniqueID;                  /* command 2 */
        IOADBDeviceInfo deviceInfo;                /* command 3, 24 bytes */
        struct { int whichRegister;                /* +0x008 */
                 char buffer[IO_ADB_MAX_PACKET];   /* +0x00c */
                 int length; } reg;                /* +0x014, commands 5, 6 */
        struct { unsigned int state;               /* +0x008 */
                 unsigned int mask; } st;          /* +0x00c, commands 7, 8, 9 */
    } u;                                           /* +0x008 */
} ioadb_device_request_t;

typedef struct {                       /* 396 bytes = 0x18C */
    int             command;                       /* +0x000 */
    IOReturn        result;                        /* +0x004 */
    IOADBDeviceInfo table[IO_ADB_MAX_DEVICE];      /* +0x008, 384 bytes */
    int             length;                        /* +0x188 */
} ioadb_table_request_t;
```

`0x20` and `0x18C` are literally the length fields of the two `_IOWR` command words, so **two
independent derivations agree**: the offsets say 32 and 396, and the encodings say 0x020 and 0x18C.
The 384-byte table is also exactly `IO_ADB_MAX_DEVICE * sizeof(IOADBDeviceInfo)`, which is what
`IOADBBus.h`'s comment on `GetTable:length:` demands ("an array that is `IO_ADB_MAX_DEVICE` long").
Every type name and field name above is invented; only the offsets and sizes are evidence.

### `ioadb_state`

`{ioadb_state="ioadb"@}`, four bytes at `+0x108` on top of `IODevice`'s `0x108`. The one encoded
field is the whole struct, so **no fields were invented**. **Nothing in this binary — neither the six
`ADBServer` methods nor any of the five C functions — touches `+0x108`.** The ivar is declared and
unused. Recorded, not explained.

## The six C functions

These are C: there are no type encodings, so **every signature is derived**, and each derivation is
stated in a comment above the function it belongs to.

| Function | Derived signature | What the derivation rests on |
| --- | --- | --- |
| `initalize` | `static int initalize(void)` | its one call site at `0x120` sets up no arguments and tests `r3` against zero |
| `adbServeropen` | `static int adbServeropen(dev_t dev)` | `r3` alone is read and masked `& 0xff`; `r4`-`r6` untouched |
| `adbServerclose` | `static int adbServerclose(dev_t dev)` | same |
| `adbServerioctlDispatch` | `static int adbServerioctlDispatch(dev_t dev, int cmd, void *data)` | `r3`, `r4`, `r5` read; `r5` moved to `r4` at `0xfc0` and passed on |
| `adbServerIoctl` | `static int adbServerIoctl(int cmd, void *data)` | the call at `0xfd0` passes `(cmd, data)` |
| `ioadbDeviceIoctl` | `static int ioadbDeviceIoctl(int unit, void *data)` | the call at `0xffc` passes `(minor(dev), data)` |

All six are `local` symbols in the symbol table, hence `static`.

**The dispatch shape is what constrains the rest.** `adbServerioctlDispatch` masks `dev` with `0xff`
— which is `<bsd/sys/types.h>`'s `minor()`, `((x) & 0xff)`, the one place these constants trace to a
name — and routes minor 0 to `adbServerIoctl` and every other minor to `ioadbDeviceIoctl`. So minor 0
is the server's own node and carries session management; minors 1 and up are per-device nodes and
carry the nine ADB commands. Neither handler ever receives `dev`.

### What the layer does

`+[ADBServer serverMajor:]` registers eleven cdevsw entry points, **eight of them `_enodev`**:
`open`, `close` and `ioctl` are the only real ones. That narrowness is what the C functions turn out
to be: no read, no write, no select, no mmap. Everything goes through `ioctl`.

- `adbServeropen` allocates an `IOADBDevice` for the unit — `[IOADBDevice alloc]` only, uninitialised
  — and fails `ENODEV` if the session was never claimed, `EACCES` if it is already open.
- `adbServerIoctl`'s `0x40546101` walks `gADBDeviceIdMap` under `gMapLock` for a free unit, claims it,
  and `sprintf`s `/dev/radbki%02d` back into the caller's buffer. That is how a client learns which
  node to open.
- `ioadbDeviceIoctl` is a jump table over commands 2-9, one arm per `IOADBDevice` method, each
  storing the method's `IOReturn` into the payload's `result` word. Command 1 (`GetTable`) is handled
  by `adbServerIoctl` instead, against the class rather than an instance.
- `adbServerclose` frees the object and clears `inUse`. It **cannot fail**: `r27` is set to zero at
  `0xeb8` and never written again, so all three of its abnormal cases are traces, not errors.
- `initalize` builds `gDeviceTable` once from `[gADBDriver getADBInfo:device :&info]` for ADB
  addresses 1..15, packing present devices and translating `adb.h`'s flag bits.

### The ioctl command values

**No name for any of the three exists in this tree.** `adb.h`, `adb_io.h`, `IOADBBus.h`,
`IOADBBusProt.h` and the `sys/ioctl.h` family were all searched; the only `'a'`-group ioctl anywhere
in the tree is `netiso`'s `SIOCGSTYPE`. They are written as the literals the binary compares against,
with their decomposition under `<bsd/sys/ioccom.h>` recorded in comments and verified arithmetically:

| Value | Decomposition | Used by |
| --- | --- | --- |
| `0x40546101` | `_IOR('a', 1, char[84])` | `adbServerIoctl` — allocate a session, return its node path |
| `0xC0206102` | `_IOWR('a', 2, ioadb_device_request_t)` | routed to `ioadbDeviceIoctl` |
| `0xC18C6103` | `_IOWR('a', 3, ioadb_table_request_t)` | `adbServerIoctl` for `GetTable`; also routed to `ioadbDeviceIoctl` |

**One of Apple's own names survives, and it is not written as a macro.** `adbServerIoctl`'s first
`kprintf` on entering the `0x40546101` arm prints `"... IOADB_KERN_GETDEVICE\n"`. That is a string
constant, not a definition: the header that defined `IOADB_KERN_GETDEVICE` is not in this tree, and
writing a macro here would be an invention wearing a recovered name. The name is recorded; the
literal is what the code compares.

The nine *payload* command values, 1 through 9, are likewise unnamed. 1 is `GetTable`; 2 through 9
are the eight `IOADBDevice` methods in `__text` order, which the jump table at `__TEXT,__const+0`
confirms exactly:

```
case 2 -> 0x1308  initForDevice:result:
case 3 -> 0x134c  getADBInfo:
case 4 -> 0x1378  flushADBDevice
case 5 -> 0x13a0  readADBDeviceRegister:buffer:length:
case 6 -> 0x1420  writeADBDeviceRegister:buffer:length:
case 7 -> 0x14a8  setState:mask:
case 8 -> 0x14bc  getState
case 9 -> 0x14d4  watchState:mask:
```

Command 0 exists in neither handler.

## Named constants

Every bare constant traced:

| Value | Name | Source |
| --- | --- | --- |
| `-0x2BD` (-701) | `IO_R_NO_MEMORY` | `driverkit/return.h:39` |
| `-0x2C0` (-704) | `IO_R_NO_DEVICE` | `driverkit/return.h:42` |
| `-0x2C1` (-705) | `IO_R_PRIVILEGE` | `driverkit/return.h:43` |
| `-0x2C7` (-711) | `IO_R_UNSUPPORTED` | `driverkit/return.h:51` |
| `0` (returns) | `IO_R_SUCCESS` | `driverkit/return.h:38` |
| `1` (`+deviceStyle`) | `IO_IndirectDevice` | `driverkit/driverTypes.h:89` |
| `1` (device flags out) | `kIOADBDeviceAvailable` | `IOADBBus.h:57` |
| `1` (bus flags in) | `ADB_FLAGS_PRESENT` | `adb.h:74` |
| `2` (bus flags in) | `ADB_FLAGS_REGISTERED` | `adb.h:75` |
| `4` (bus flags in) | `ADB_FLAGS_UNRESOLVED` | `adb.h:76` |
| `6` (bus flags in) | the two above, or'd | `adb.h:75`+`:76` |
| `0xff` (dev masks) | `minor()` | `bsd/sys/types.h:111` |
| `0x13` (19) | `ENODEV` | `bsd/sys/errno.h:98` |
| `0xd` (13) | `EACCES` | `bsd/sys/errno.h:90` |
| `6` (ioctl returns) | `ENXIO` | `bsd/sys/errno.h:82` |
| `0x16` (22) | `EINVAL` | `bsd/sys/errno.h:101` |
| `8` (register buffer) | `IO_ADB_MAX_PACKET` | `IOADBBus.h:63` |
| `16` (ioctl table) | `IO_ADB_MAX_DEVICE` | `IOADBBus.h:62` |
| `24` (adb_devices stride) | `sizeof(struct adb_device)` | `adb.h:114` |
| `0x1C` | `sizeof(IOADBDevicePriv)` | derived |
| **`64`** | **unnamed** | `gDeviceTable` bound |
| **`256`** | **unnamed** | `gADBDeviceIdMap` bound |
| **`255` / `0x100`** | **unnamed** | `+probe:` session clamp |
| `15` | `MAX_BUS_DEVICE_ADDRESS` / `ADB_ADDR_HIGH`, neither imported | `adb_bus.h:155`, `adb.h:133` |
| **`0x1000`, `0x10000`** | **unnamed** | driver-side device flags |
| **`128`** | **unnamed** | `ioadbDeviceIoctl` dump buffers |
| **`0x40546101`, `0xC0206102`, `0xC18C6103`** | **unnamed** | ioctl commands |
| **`1`-`9`** | **unnamed** | ioctl payload commands |

Twenty constants traced to names; **seven distinct groups could not be**, and are written as
literals with comments saying so. That ratio is the story of the C functions: the Objective-C half of
this driver traced almost everything (its only failures were the three array bounds), and the C half
failed on most of what matters — the wire protocol.

`15` deserves its own note, and an earlier draft of this document got it wrong. It claimed the value
had no name anywhere in the tree. **Two names for it exist:** `MAX_BUS_DEVICE_ADDRESS`
(`src/architecture-1/adb_bus.h:155`) and `ADB_ADDR_HIGH` (`src/kernel-7/bsd/dev/adb.h:133`). Neither
header is imported by `IOADBDevice.m`, so writing the digits is still defensible — adopting one of
the two would assert which name Apple reached for, and nothing in the binary says. But the assertion
of absence was false and is retracted.

What the binary *does* settle is the operator, and that part stands: this compiler preserves the
relational operator it is given — `blt` for the `<` loops in `-initForDevice:result:`, `ble` for the
`<=` one in `adbServerIoctl` — and `initalize`'s bound test at `0x764` is `cmpwi 0xF` followed by
`ble`, so the source said `<= 15`.

## The one divergence that is not reproducible

`_gADBDriver` is a **local** symbol in the shipped binary. Local means `static` in the source:
`drvPPCCuda_reloc` carries both bindings, and its Apple source shows `local` for exactly the `static`
ones (`return_buff_pointer`, `bImmediate_buff_needed`, `cuda_state_transition_delay_ticks`) and
`external` for the plain globals (`cuda_initted`). So the test is sound.

But `__OBJC,__module_info` names two modules, `IOADBDevice.m` and `ADBServer.m`, and **both reference
`_gADBDriver`** — `-flushADBDevice`, the two register methods and `initalize` in the first, `+probe:`
in the second. A file-scope static cannot be reached from another translation unit. Its storage sits
inside `ADBServer.m`'s `__DATA,__data` block (the `__data` and `__bss` layouts split cleanly along
module order), so it is **defined non-static in `ADBServer.m` and declared `extern` in
`IOADBDevice.m`**, at the cost of one symbol binding the original had as local. This is the same
compromise the in-tree PortServer reconstruction records for `ttyiops_devsw`.

Every other file-scope symbol is single-module and is genuinely `static`: `initialized`,
`gDeviceTable`, `gDeviceCount` and `initalize` in `IOADBDevice.m`; `gADBServerMajor`,
`gADBServerLoaded`, `gMapLock`, `gNumSessions`, `gADBDeviceIdMap`, `adbServeropen`, `adbServerclose`,
`adbServerioctlDispatch`, `adbServerIoctl` and `ioadbDeviceIoctl` in `ADBServer.m`.

## Recovered names

Not invented. Every one of these came out of the binary:

- **From the symbol table:** `gDeviceTable`, `gDeviceCount`, `gADBDriver`, `initialized`, `initalize`,
  `gADBServerMajor`, `gADBServerLoaded`, `gMapLock`, `gNumSessions`, `gADBDeviceIdMap`,
  `adbServeropen`, `adbServerclose`, `adbServerioctlDispatch`, `adbServerIoctl`, `ioadbDeviceIoctl`.
- **From the assertion string:** the field name `info`, the local `index` and the argument `uniqueID`
  of `-initForDevice:result:`.
- **From the ivar encoding:** the struct tag `ioadb_state` and its field `ioadb`.
- **From `__OBJC,__module_info`:** the source file names `IOADBDevice.m` and `ADBServer.m`.
- **From a `kprintf` format string:** `IOADB_KERN_GETDEVICE`, recorded but deliberately not written
  as a macro (see above).
- **`initalize`'s misspelling.** Apple's, reproduced. Correcting it would break the symbol
  correspondence this whole effort measures.

## Invented names

Nothing below is in the binary. These are inventions, and saying otherwise would be false.

- **Types:** `IOADBDevicePriv`, `IOADBDeviceEntry`, `ADBDeviceIdMapEntry`, `ioadb_device_request_t`,
  `ioadb_table_request_t`.
- **Fields:** `IOADBDevicePriv.info`, `IOADBDevicePriv.index`, `IOADBDeviceEntry.device`,
  `ADBDeviceIdMapEntry.device`, `ADBDeviceIdMapEntry.inUse`, and every field of both request structs
  (`command`, `result`, `u`, `uniqueID`, `deviceInfo`, `reg`, `whichRegister`, `buffer`, `length`,
  `st`, `state`, `mask`, `table`).
- **Locals:** `rtn`, `value`, `configTable`, `maxSessions`, `result`, `device`, `index`, `unit`, `i`,
  `buf`, `req`, `adbDevice`.
- **Arguments:** `result`, `deviceInfo`, `whichRegister`, `buffer`, `length`, `state`, `mask`,
  `table`, `deviceDescription`, `parameterArray`, `parameterName`, `count`, `dev`, `cmd`, `data`,
  `unit`.

## Uncertainties

Every one of these is recorded rather than resolved.

1. **The declared bound of `gDeviceTable`.** Storage says 64; no named constant with that value
   exists in this tree, and the only ADB device-count constants are 16. Written as a literal. Made
   stranger by `initalize`, which can never fill more than 15 of them.
2. **The declared bound of `gADBDeviceIdMap`.** 256 from storage, unnamed.
3. **The session clamp `255`/`0x100` in `+probe:`.** Unnamed. It is a comparison against `0xff`
   followed by an assignment of `0x100`, so it is a clamp and not a mask.
4. **Which name, if any, `initalize`'s loop bound 15 had.** Two constants of that value exist in the
   tree — `MAX_BUS_DEVICE_ADDRESS` (`adb_bus.h:155`) and `ADB_ADDR_HIGH` (`adb.h:133`) — and
   `IOADBDevice.m` imports neither header. The digits are written; the choice between the three is
   not recoverable. (An earlier draft asserted no such constant existed. It was wrong.)
5. **The driver-side device flag bits `0x1000` and `0x10000`.** Unnamed. The bus-side bits they are
   translated from are all named in `adb.h`; the driver's own encoding is not defined anywhere.
6. **The three ioctl command words and the nine payload command values.** Unnamed. One of the twelve,
   `IOADB_KERN_GETDEVICE`, has a name recoverable from a trace string but no definition.
7. **The 84-byte payload of `IOADB_KERN_GETDEVICE`.** Only ever used as a `sprintf` destination, so
   nothing beyond "it begins with a string" is derivable. No type is declared for it.
8. **The 128-byte dump buffers in `ioadbDeviceIoctl`.** Two distinct frame slots prove there are two
   of them and that each is 128 bytes; 128 has no name.
9. **Whether `ioadbDeviceIoctl`'s dump index is one function-scope variable or two block-scoped
   ones.** Both loops use `r30`, which command 5 clobbers over `adbDevice` once it is done with it.
   Indistinguishable. Function scope written.
10. **Whether `initalize`'s presence test is `if (present) {...}` or `if (!present) continue;`.**
    `0x670`'s `beq` to the increment is what both compile to. The block form is written.
11. **Whether `+requiredProtocols` returns `Protocol **` or `id *`.** `^@` cannot tell them apart;
    `IODevice.h`'s spelling was adopted.
12. **The trailing arguments of the three cdevsw entry points.** A `d_open` is called with flag,
    devtype and proc; a `d_ioctl` with flag and proc. None of the three reads them. Not recoverable,
    and not invented — the `IOSwitchFunc` casts in `+serverMajor:` remain correct either way, since
    `devsw.h` declares that type as `int (*)()`.
13. **Apple's line numbering.** The assertion in `-initForDevice:result:` passes line 115; ours will
    not match, and nothing recoverable fixes that.
14. **What `ADBServer`'s `state` ivar is for.** Declared at `+0x108`, touched by nothing in the
    binary — not by the six methods, and not by the five C functions either. Task 4 was the check
    that could have answered this and it did not.
15. **`_gADBDriver`'s original linkage.** See above. Not reproducible in standard C.
16. **Whether `IOADBDeviceInfo` was really untagged in Apple's source.** Every occurrence encodes
    `{?=iiiilL}`. `IOADBBus.h`'s `typedef struct _adbDeviceInfo {...}` would encode
    `{_adbDeviceInfo=iiiilL}`. Field count, order and types agree exactly — `int, int, int, int, long,
    unsigned long` — so Apple's `IOADBDevice.m` carried its own untagged copy, presumably the
    1997-12-19 original that `IOADBBus.h`'s history names. The instruction was to reuse rather than
    redeclare, so the tagged one is imported and **the shipped encoding is not reproduced.** This is
    the only place where following that rule knowingly produces a different encoding than the binary.
17. **`0xC18C6103` does not fit in an `int`.** Both comparisons against it are `cmpw`, the signed
    compare, so the command variable is a signed `int` and the constant is matched by bit pattern.
    Written as the binary does it.
18. **Nothing compiles.** No syntax, type or link error in these four files has been ruled out.

## Not claimed

The map proves the *selectors* match Apple's binary and that every function has a source site. It
does not prove the *bodies* do, and no check available here can. Specifically, none of the following
is claimed: that this compiles, that it links, that it loads, that a `kernload` of it would produce a
working `/dev/radbki00`, or that any single instruction of the 5524 bytes of `__text` was transcribed
correctly. What is claimed is that every one of them was read, and that every place where the reading
was ambiguous is in the list above.

## Calibration (spec 4.1): what this cost, and what it says about DEC21x4Ethernet

This spec exists partly to decide whether `DEC21x4Ethernet`'s 55 KB — ten times this driver — is
worth attempting. The measured facts first, then the verdict.

### Measured

| | Count |
| --- | --- |
| Functions written | **22** — 16 Objective-C methods, 6 C functions |
| Bytes of `__text` written | **4784** of 5524 in `__text` (87%) |
| Functions found unwritable | **0** |
| Functions out of scope by construction | 46 — 44 jump islands, 2 build-generated accessors |
| Uncertainties standing | **18** |
| Defects caught in review | **5** — 4 in the packaging stub, 1 in this document |
| Constants traced to a name | 20 |
| Constant groups with no name in this tree | 7 |
| Commits | 5 (Tasks 1, 2, 3, 4, 5), plus the corrections recorded below |

**Nothing in this binary was found unwritable.** An earlier version of this table read 21 written and
1 unwritable, the unwritable one being `+[IOADBDevice GetTable:length:]`. That was wrong: the
function is 212 bytes at `__text+0` and is now written. The denominator changed with it — 5312 was
IDA's function total, not `__text`'s size, and the 212-byte difference between them *was* the
function said to be missing.

**The four defects were all in the stub the packaging spec produced**, and every one of them was
found by a discipline rather than by reading code:

1. `IOADBDevice`'s superclass was `IODevice`; the class table says `Object`. Found by reading the
   class table instead of inferring from the linked-class list.
2. `-initForDevice:` took an `id`; the encoding says `l`, a `long`. Found by settling signatures from
   `__OBJC,__meth_var_types`.
3. The three state methods used `IOADBDeviceState` (`unsigned long`); the encodings say `I`,
   `unsigned int`. Same discipline.
4. The register buffers were `unsigned char *`; the encodings say `*`, `char *`. Same discipline.

None of these is visible to any check available here — `source_map` compares selectors only. All four
would have shipped silently.

### Where the effort went, and where the uncertainty came from

The split between the two halves is the interesting number, because the C half is the analogue of
Tulip's 116 C functions.

| | Objective-C (16 fns) | C (6 fns) |
| --- | --- | --- |
| Bytes written | 2592 | 2192 |
| Uncertainties produced | 9 | 9 |
| Unnamed constant groups | 3 | 5 |
| Uncertainties per function | 0.56 | **1.5** |

**Per byte the two halves cost about the same. Per function the C half produced two and a half times
the unresolvable uncertainty, and it is the C half that failed to name constants.** That is the
single most important measurement in this document, because the ratio does not depend on this
driver's peculiarities — it depends on the absence of type encodings, which is a property of C.

Three specific things made the C functions harder, and all three generalise:

1. **Signatures had to be derived from register usage at call sites.** This worked here only because
   the six functions form one small, closed call graph with a dispatcher at its centre:
   `adbServerioctlDispatch` reads exactly `r3`, `r4`, `r5`, and the two calls it makes pin both
   handlers' argument lists. Remove the dispatcher and two of the six signatures become unrecoverable.
   **A function reached only through a function-pointer table has no call site to read at all** — and
   the cdevsw entry points are exactly that case, which is why three of the six still carry an
   explicitly unrecoverable tail (uncertainty 12).
2. **The constants that failed to trace were the protocol constants.** Not array bounds this time:
   ioctl command words, device flag bits, packet buffer sizes. Tasks 1–3 predicted precisely this
   ("in a network driver, unnamed constants are register bit definitions and timing values, and
   getting one wrong is invisible and consequential"). The prediction held, one driver early.
3. **The layouts had no metadata at all.** Both ioctl payloads were derived purely from offsets. What
   rescued them was a second, independent derivation: the ioctl command words encode `sizeof` the
   payload, and 32 and 396 came out of the offsets before they were checked against `0x020` and
   `0x18C`. **That cross-check is the only reason those two structs are stated as confidently as they
   are**, and it was luck that the protocol carried its own sizes.

What was *not* hard: transcription. The individual bodies are straight-line, and only three of the
twenty-two — `-initForDevice:result:`, `+probe:` and `ioadbDeviceIoctl` — needed real branch
bookkeeping. The largest function in the binary, `ioadbDeviceIoctl` at 760 bytes, turned out to be
the *easiest* large function, because a jump table with one arm per method has no dropped branch to
hide: the table itself enumerates them.

One question Task 4 was expected to answer and did not: **`ADBServer`'s `state` ivar at `+0x108` is
touched by nothing in the binary**, not by the six methods and not by the five C functions. Tasks 1–3
recorded it as possibly explained by the C functions. It is not. It stays recorded.

### Verdict on DEC21x4Ethernet

Tasks 1–3 recommended: *attempt it, but sliced — structure and `IOEthernet` overrides first, SROM and
media tables as a separate spec that may legitimately end BLOCKED. Budget 5–8x, not 10x, because
`IOADBBus.h` gave this driver its types, protocol and half its signatures for free and Tulip has no
such header.*

**That stands, with two revisions.**

**Revision 1: the slice boundary should be Objective-C versus C, not structure versus SROM.** The
measurement above says the two halves have different costs, different failure modes, and different
verifiability. Do `DEC21x4Ethernet`'s 40 Objective-C methods as one spec. That half is genuinely
tractable: signatures come from encodings for free, `IOEthernet` constrains the semantics, and it
produces a `source-map` result — a *mechanical* pass/fail — at the end. Everything the disciplines
caught here, they caught on that half.

**Revision 2: the 116 C functions should be time-boxed, not scoped, and 5–8x does not apply to them.**
By count they are 19x this driver's six. Per-function cost will be *higher*, not lower, for two
reasons this spec measured rather than guessed: signature derivation degrades as the call graph grows
(the dispatcher trick does not scale), and a Tulip driver's C layer is where the register definitions
live — the exact class of constant that failed to trace here. Extrapolating 1.5 uncertainties per C
function gives roughly **170 recorded uncertainties** for that half alone, which is not a
reconstruction, it is a catalogue. A spec that produces a catalogue is still worth having, but it
should say so up front rather than discovering it at function 60.

Concretely, the sequencing I would now recommend:

1. **`DEC21x4Ethernet`, Objective-C only.** 40 methods, all encodings available, `IOEthernet` as the
   semantic constraint, mechanical acceptance via `source-map`. Budget 3–4x this whole spec. Expect
   it to succeed.
2. **`adbservd` next, not third.** 1488 bytes, 30 pure C functions, no Objective-C at all. It is the
   *cheapest possible* test of the C-only workflow, and it is this driver's own companion, so the
   ioctl protocol derived above is directly checkable against it — the eighteen unnamed constants
   here may well be named there. **That is the highest-value 1.5 KB in the remaining set** and it was
   not obvious before this spec measured where the uncertainty comes from.
3. **`DEC21x4Ethernet`'s C half only after (2).** Time-boxed, with BLOCKED as an accepted outcome for
   any function whose signature cannot be derived, and with the explicit expectation that unnamed
   register constants will be the norm rather than the exception.

The one thing that would change all of this is a PowerPC toolchain. Every reconstruction spec has
ended with that sentence and this one strengthens it more than any of them: 22 functions were written
here and **zero of them have been compiled**. For the Objective-C half a wrong body is at least
constrained by a selector check; for the C half there is no check at all. Until something can
compile, the C half of a 55 KB driver is 116 unverified assertions.
