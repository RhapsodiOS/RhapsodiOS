# Writing IODisplay's six absent methods

Reconstruct the six functions Apple's shipped `IODisplay_reloc` contains that
`src/driverkit-3/libDriver/ppc` does not, writing each from its disassembly.

**Nothing in this spec is compile-verified.** There is no PowerPC toolchain.

## Motivation

The platform-driver measurement found `IODisplay` to be the only driver in that
batch with genuine unresolved gaps: six functions present in the shipped binary
and absent from source after an exhaustive grep of the whole tree. Every other
driver measured across four specs resolved to zero or near-zero.

`src/drivers-ppc/reconstruction/IODisplay/findings.md` records them. This spec
writes them.

### Why this is the riskiest work in the series

The four preceding specs measured. This one writes ~772 bytes of PowerPC-derived
Objective-C with **no compiler to check it and no test that can run**. The
SCSITape spec did exactly this kind of work — four method bodies from
disassembly — and its reviews found **four material errors** before they were
corrected.

The discipline that follows from that is §3: every method is written from its
own disassembly, reviewed against that disassembly, and anything the
disassembly does not settle is recorded as unresolved rather than invented.

## 1. Scope

### 1.1 The six functions

| Function | Address | Size |
| --- | --- | --- |
| `+[IOSmartDisplay probe:]` | `0x0010` | 60 |
| `_UnpackString` | `0x0314` | 232 |
| `-[IOSmartADBDisplay findADBDisplayInfoForType:]` | `0x0754` | 324 |
| `-[IOSmartADBDisplay IOSMADBGetAVDeviceID:size:]` | `0x1248` | 44 |
| `-[IOSmartADBDisplay IOSMADBGetLogicalRegister:size:result:size:]` | `0x1274` | 104 |
| `-[IOSmartADBDisplay IOSMADBSetLogicalRegister:size:]` | `0x12ec` | 68 |

All six go into `src/driverkit-3/libDriver/ppc/IOSmartDisplay.m`, which already
defines `IOSmartDisplay`, `IOSmartADBDisplay` and `IOSmartDDCDisplay`.

**Amended: five, not six.** `findADBDisplayInfoForType:` is not written, for
the reason given in §3.6. Everything else in this spec stands.

Reference: `IODisplay.config/IODisplay_reloc`, 32640 bytes, SHA-256
`FD38FBA638BE85555D342D5349EABDE764F8562084DECEB1A3D33FDAC166B3F1`.

### 1.2 What the evidence already establishes

Determined before this spec was written, and not to be re-derived:

- **`sub_4C` and `sub_1330` are `_objc_msgSend`.** Both are unnamed PowerPC jump
  islands (`lis r12` / `mr` / `mtctr` / `bctr`); their targets resolve through
  the Mach-O relocation table, which `read_macho` carries and the IDA export
  does not. Every `bl` to an island must be resolved this way, never guessed.
- **`IOSmartADBDisplay`'s ivars** are `UInt8 adbAddr`, `UInt8 waitAckValue`,
  `SInt16 avDisplayID`, `const AVDeviceInfo *deviceInfo`
  (`IOSmartDisplay.m:67-74`). The `lha` (signed halfword) load at `+0x120` in
  `IOSMADBGetAVDeviceID:size:` matches `SInt16 avDisplayID`.
- **`-[IOSmartDisplay setLogicalRegister:data:]`** (`IOSmartDisplay.m:463`) and
  **`getLogicalRegister:data:`** (`:486`) already exist, both taking `UInt16`.
  The `IOSMADB*` methods are thin wrappers over them.
- **External symbols available:** `_IOMalloc`, `_IOSleep`, `_adb_devices`,
  `_adb_readreg`, `_adb_register_dev`, `_adb_writereg`, `_kprintf`,
  `_objc_msgSend`, `_objc_msgSendSuper`, `_sprintf`, `_strtol`.
- **`-0x2C2` is `-706`, and that is `IO_R_INVALID_ARG`**, defined at
  `src/driverkit-3/driverkit/return.h:44`. Located by searching this tree
  before the spec was written, per §3.3 — the SCSITape spec's observation that
  every unknown constant in it was defined somewhere in this tree held again.
  Write the name, not the literal.
- **`configTable` returns `IOConfigTable *`** (`IOTreeDevice.m:351`), and no
  such static exists in `IOSmartDisplay.m` today. §3.4's question is
  therefore already answered: it must be **introduced**, as a
  file-static `IOConfigTable *`.

  **Correction, from the work itself:** the C identifier is **`configTable`**,
  not `_configTable`. IDA displays the Mach-O symbol, and Mach-O prefixes every
  C symbol with an underscore. The same symbol table proves the rule on names
  whose source is already in hand — `_smInited` and `_ADB2SmartDisplay` are the
  source's `smInited` (line 105) and `ADB2SmartDisplay` (line 106), and
  `_SMADBHandler` is `SMADBHandler` (line 430). Writing `_configTable` in C
  would have produced the Mach-O symbol `__configTable`. Everywhere below that
  this spec writes `_configTable`, read `configTable`.

### 1.3 Two methods are already legible

Recorded here so the work starts from evidence rather than from scratch, and so
a reviewer can check these independently.

**`+[IOSmartDisplay probe:]`** — `mr r3, r5` moves the third argument
(`deviceDescription`) into the receiver register, `r4` is loaded from the
`configTable` selector reference, `bl` reaches `_objc_msgSend`, and the result
is stored to a static before `li r3, 1` returns. That is:

```objc
configTable = [deviceDescription configTable];
return YES;
```

**`-[IOSmartADBDisplay IOSMADBGetAVDeviceID:size:]`** — dereferences its second
argument, compares to 4, returns `-706` on mismatch; otherwise `lha` from
`+0x120` and stores to the first argument, returning 0.

### 1.4 Out of scope

- **Any build or claim of buildability.** No PowerPC toolchain exists.
- **Modifying the other five drivers** in `src/driverkit-3/libDriver/ppc`, or
  any measurement artifact.
- **`IONDRVSupport`, `PPCSerialPort`, `Floppy`** and the glue-stub tooling.
- **Re-measuring `IODisplay`.** Its source map and `findings.md` are regenerated
  at the end (§4 item 5), not re-derived.

## 2. Design

All six go into `IOSmartDisplay.m`, placed next to the methods they relate to
and matching the file's existing style — its brace placement, its `UInt16` /
`SInt16` / `IOReturn` type spellings, its comment idiom. The file is Apple's
original source; new code must not be distinguishable by formatting.

`_UnpackString` is a static C function; the other five are methods on their
respective classes. `+probe:` needs whatever static `_configTable` resolves to —
§3.4.

## 3. Method

### 3.1 One method at a time, each from its own disassembly

A disassembly listing of all six, annotated with relocation targets, is prepared
before any code is written. Each method is transcribed from **its own listing**,
not from a paraphrase and not from a sibling method that looks similar.

### 3.2 Every branch accounted for

For each method, every instruction must be explained by the written code. A
branch with no counterpart in the source is either a missed case or a
misreading, and both are defects.

### 3.3 Unknown constants are looked up, not invented

Any bare constant must be traced to a named constant in this
tree before being written as one. Search `src/driverkit-3`, `src/kernel-7` and
the DriverKit headers. **If no name is found, write the numeric literal with a
comment recording that the name could not be located** — do not invent a
plausible `IO_R_*` spelling. The SCSITape spec's lesson was that every unknown
constant in it was defined somewhere in this tree; the search must be real
before the conclusion is.

### 3.4 `_configTable` must be resolved, not assumed

`+probe:` stores its result into a static that IDA names `_configTable`. Whether
that static already exists in `IOSmartDisplay.m`, exists under another name, or
must be introduced is a question for the source, and the answer is recorded. If
it must be introduced, its type comes from what `configTable` returns.

### 3.5 What cannot be determined is recorded

A method whose behaviour the disassembly does not settle — an ambiguous
argument type, an unresolvable call target, a constant with no name — is written
with the uncertainty stated in a comment, and listed in the deliverable's
findings. **An honestly recorded uncertainty is a result; a confident guess is a
defect.**

### 3.6 Amendment: the class-hierarchy divergence, and why one method is not written

Writing the six turned up a divergence between this tree's `IOSmartDisplay` and
Apple's shipped one that is larger than any single method. It is recorded here
because it is the more valuable result.

#### The evidence

`IODisplay_reloc` carries `__OBJC,__class` and `__OBJC,__instance_vars`. Read
with `read_macho`, they give Apple's own superclass links, ivar names, type
encodings and offsets — measurements, not inferences:

```
class                            super_class      instance_size
IOSmartDisplay                   IODevice          284  (0x11C)
IOSmartADBDisplay                IOSmartDisplay    300  (0x12C)
IOSmartDDCDisplay                IOSmartDisplay    412  (0x19C)

IOSmartDisplay ivars (4)
   attachedFramebuffer     @         +0x108
   attachedRefCon          I         +0x10C
   priv                    ^v        +0x110
   _IOSmartDisplay_reserved [2i]     +0x114

IOSmartADBDisplay ivars (6)
   adbAddr                 C         +0x11C
   waitAckValue            C         +0x11D
   wiggleLADAddr           C         +0x11E
   avDisplayID             s         +0x120
   numModes                i         +0x124
   modeList                ^I        +0x128
```

`.objc_class_name_IODevice` is an undefined external in the symbol table.

This tree declares `@interface IOSmartDisplay:Object` (`IOSmartDisplay.m:44`).
Under `Object` the class inherits 4 bytes, so its own ivars start at `+0x04`,
its instance size is `0x18`, and `IOSmartADBDisplay`'s ivars start at `+0x18`.
Apple's inherit **264** bytes of `IODevice` instead — **260 bytes more** — and
Apple's `IOSmartADBDisplay` has **six** ivars where this tree has four:
`wiggleLADAddr`, `numModes` and `modeList` in place of a single
`const AVDeviceInfo * deviceInfo`.

Those three are, field for field, this tree's `AVDeviceInfo` struct
(`IOSmartDisplay.m:59-65`) flattened into the object. The shipped driver built
its display description from the config table at runtime; this tree's source
reaches a compiled-in `static const AVDeviceInfo` table through a pointer.
Different mechanism, same data.

#### The consequence

`-[IOSmartADBDisplay findADBDisplayInfoForType:]` (`i6@4:8S12`, i.e.
`- (IOReturn) findADBDisplayInfoForType:(UInt16)type`) touches **only** the
three ivars this tree does not have — `+0x11E` (`stb`), `+0x124` (address
taken, passed to `UnpackString`) and `+0x128` (`stw`, then `lwz` for the return
value). It touches no ivar this tree does have. What it does is legible:

```
sprintf( key, "adb%dWiggle", type);
str = [configTable valueForStringKey:key];
if( str) { wiggleLADAddr = strtol( str, 0, 0); [configTable freeString:str]; }
else	  { wiggleLADAddr = 4; }

sprintf( key, "adb%dModes", type);
str = [configTable valueForStringKey:key];
if( str) {
    str2 = [configTable valueForStringKey:str];		// indirect: the value names another key
    if( str2) {
	modeList = UnpackString( str2, &numModes);
	[configTable freeString:str2];
    }
    [configTable freeString:str];
}
return( modeList ? noErr : -49);
```

Writing it would mean adding three ivars to `IOSmartADBDisplay` and — if the
offsets were to be reproduced at all — changing `IOSmartDisplay`'s superclass
from `Object` to `IODevice`, in a `driverkit-3` framework class shared with
`IOApplePCIBus` and the deferred `IONDRVSupport`. That is a redesign, not a
transcription, with no compiler to catch what it breaks.

**The decision taken was to write what is writable and record the divergence as
the finding.** `findADBDisplayInfoForType:` is therefore not written, and stays
unmapped. That is the correct outcome, not a failure.

#### Blast radius

The five functions that *are* written are unaffected: every ivar reference in
them is by name, so the compiler assigns the offset, and none depends on a
literal offset matching Apple's. `IOSMADBGetAVDeviceID:size:`'s reading of
`+0x120` as `avDisplayID` is confirmed by Apple's ivar table (`avDisplayID`,
encoding `s`, offset 288) — the *name and type* are right even though the
*offset* does not correspond under this tree's layout, and by-name access is
all the source needs.

`IOSmartDDCDisplay` carries the same +260 shift on `edid1` and nothing more.
Whether other `libDriver/ppc` sources declare `:Object` where the shipped
binary used a DriverKit superclass was **not** checked, and is left open.

## 4. Acceptance

1. **Amended: five** of the six functions exist in
   `src/driverkit-3/libDriver/ppc/IOSmartDisplay.m`, with the signatures the
   binary's selectors imply. `findADBDisplayInfoForType:` is not among them,
   per §3.6.
2. For each, a written account maps **every instruction** in its disassembly to
   the source that produces it, including every branch.
3. Every constant is either a named constant found in this tree, or a numeric
   literal with a comment recording that no name was found.
4. `configTable`'s resolution is recorded per §3.4.
5. `binrecon source-map` is regenerated for `IODisplay` and its `findings.md`
   updated. **Amended: the four written Objective-C methods move from unmapped
   to mapped**, and the map still reconciles. `_UnpackString` is a C function
   and is outside `--scope-to-objc`'s view, so it appears in neither list; its
   evidence is the bucket table. `findADBDisplayInfoForType:` stays unmapped,
   per §3.6. This is the only mechanical check available and it is a real one:
   it confirms the selectors match the binary exactly.
6. The binrecon suite is green at **845 passed, 4 skipped**; `ppc_package_check.py`
   still reports no divergences.
7. Every uncertainty from §3.5 is listed in the deliverable.

**Not claimed:** that any of this compiles, links, loads, runs, or is
behaviourally correct. Item 5 proves the *selectors* match the binary. It does
not prove the *bodies* do, and no check available here can.

### 4.1 The likeliest failure

Not a wrong instruction — a plausible-looking body that quietly drops a branch,
or a constant given a confident but invented name. Items 2 and 3 exist for
exactly those, and both require showing the work rather than asserting the
result.

## 5. Follow-on work

- **A PowerPC toolchain**, which would turn every "not claimed" above into
  something checkable. This spec is the strongest argument yet for it.
- **`IONDRVSupport`, `PPCSerialPort`, `Floppy`** behind the glue-stub work.
- **`drvPPCATA`**, blocked on its conflicting `ata_extern.h` revisions.
- **`IOADBDevice` and `DEC21x4Ethernet`**, whose stubs now exist.
