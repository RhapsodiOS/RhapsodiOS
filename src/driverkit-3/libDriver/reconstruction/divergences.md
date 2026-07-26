# libDriver PCI/PCMCIA divergences

Reference: `mach_kernel_dr2_x86`, 1404116 bytes, SHA-256
`BE98A33F71B80AEE00A6921333943DA02D0B676C8AF056843EB868C14EBB497C`
Analyses: IDA 9.2, Ghidra 12.1, angr 9.3.0, all scoped to `[0x1FD0D4, 0x1FDCE0)`

Five modules are covered: `src/driverkit-3/libDriver/pci/IOPCIDirectDevice.m`,
`.../pci/IOPCIDeviceDescription.m`, `.../pcmcia/IOPCMCIADirectDevice.m`,
`.../pcmcia/IOPCMCIADeviceDescription.m` and `.../pcmcia/IOPCMCIATuple.m`.

## What is being compared

This is worth stating plainly before any of the findings, because it changes how
a near-total match should be read. The five `.m` files were not hand-written
against a reference — `git log` shows each entering the tree in a single import
commit (`19ffee9a Original Darwin 0.3 Sources`) and each still carries Apple's
1999 `@APPLE_LICENSE_HEADER_START@` block over a 1994 NeXT `HISTORY` block naming
Dean Reece and Curtis Galloway. They are Apple's own Darwin 0.3 sources. Two of
the five were subsequently touched — `64a7d057` and `525eece3`, each an
`#import`-line change only — so this is not a claim that the files are untouched
since import, only that nothing beyond an include path has diverged from what
Apple shipped.

The reference is Rhapsody DR2, roughly two years earlier. So this pass compares
**Apple's later source against Apple's earlier binary**. A high match rate is the
expected outcome and is not evidence that anyone reconstructed anything well; the
useful output is the small set of places where the two genuinely differ, and the
places where *our tree's supporting headers* — which are not Apple's — change what
that source compiles into.

That last category turned out to be where every real divergence lives.

## Baseline build

**No build was performed as part of this pass, and no build host is reachable.**
No parity run, no rebuilt artifact, no `assembly-matched` claim. Nothing in this
document estimates or invents build output.

One artifact that already exists on disk is used, and only as a labelled
cross-check: `out/i386/mach_kernel`, 1468416 bytes, SHA-256
`BF2DD8536EAC57A9C5EEF37397B2E7E97F4CD73C32813B5236733DE6C7CA8943`, mtime
2026-07-25 13:04. **Its provenance is not proven.** Nothing establishes which
revision of the tree it was built from or with which compiler. It is used below
to corroborate three findings and to refute two candidate findings; where it is
used, it is named. No finding rests on it alone, and no ledger status was granted
because of it.

What it does buy is real, though. Because it contains a compiled
`IOPCIDirectDevice.m` and `IOPCIDeviceDescription.m`, thirteen of the
twenty-four reference methods could be disassembled on both sides and compared
instruction by instruction. Ten of those thirteen decode to **identical mnemonic
and encoding-length sequences**, differing only in link-time absolute addresses.
The three that do not are Findings 1 and 2.

## Summary

| Bucket | Count |
| --- | --- |
| mapped | 23 |
| unmapped | 1 |
| duplicate_candidates | 0 |
| boundary_disputed | 0 |

All 24 reference methods were read at instruction level on the reference side —
3100 bytes of `__TEXT,__text` in total, so a complete read was affordable and no
function was skimmed or deferred.

On *our* side the picture is uneven and the distinction matters:

- **13 methods compared at instruction level on both sides.** Every method of
  `IOPCIDirectDevice.m` and `IOPCIDeviceDescription.m` that the reference has
  also exists in `out/i386/mach_kernel`, so all thirteen were disassembled from
  both binaries and diffed instruction by instruction (see Baseline build above).
  Ten matched exactly; three carry the divergences in Findings 1 and 2.
- **11 methods compared at control-flow level only.** The three PCMCIA modules
  are absent from our kernel (see below), so for
  `mapAttributeMemoryTo:findSpace:`, `unmapAttributeMemory` and the nine
  `IOPCMCIADeviceDescription` / `IOPCMCIATuple` methods the comparison is the
  reference's disassembly read against our source text: branch structure,
  constants, struct offsets, message-send order and call targets. That is a
  weaker evidence class and is labelled as such throughout.
- **0 methods left unexamined.**

Five methods carry a finding and therefore stay `unexamined` in the ledger, per
the convention established by the driver passes: a method known to diverge is
written up here rather than given a status it has not earned. The other nineteen
are `control-flow-confirmed`. None is `assembly-matched`; that requires a rebuilt
binary and no build was run. (Those counts are as of the report pass. The fix
pass advanced four of the five; see Post-fix parity below.)

Six findings follow. Findings 1 to 3 share one root cause — two kernel-side bus
headers in our tree are stubs — and are the only behavioural divergences found.
Finding 4 is a source typo with tooling consequences, Finding 5 is an accepted
later-Apple addition, Finding 6 is accepted dead code.

The headline: **the five modules' own source text is faithful to DR2 down to the
instruction in every place it could be checked.** Every divergence found is
caused by something outside those five files.

## Scoping

The three analyses were scoped at source, in
`tools/binrecon/profiles/kernel-driverkit.json`, to a single range
`{"start": 2085076, "end": 2088160}` — `0x1FD0D4` to `0x1FDCE0`, the range in
effect for this pass. (The `end` value has since been corrected to `2088215` /
`0x1FDD17` in commit `013c4787` — see below.) That range is the
contiguous run of `__text` that the five modules' object files contribute to the
linked kernel, and nothing else. IDA returns exactly 24 functions for it, which
is exactly the 24 Objective-C methods those five modules define. No hand-narrowing
of the analysis or of the source map was needed or performed.

`--objc-methods` is required and `--scope-to-objc` is not. A linked `MH_EXECUTE`
names no Objective-C methods in its symbol table, and this was measured rather
than assumed: the reference's symbol table holds 4156 entries and ours 4423, and
**neither contains a single symbol whose name starts with `+[` or `-[`.** What
both do carry are 103 and 98 `.objc_class_name_*` / `.objc_category_name_*`
labels respectively — class identity, never method identity. The address-to-name
mapping therefore comes entirely from the `__OBJC,__module_info` walk.
`--scope-to-objc` would have widened the analysis to every Objective-C method in
the kernel, which is far more than these five modules.

**This map deliberately covers 24 of the kernel's functions.** The kernel has
thousands. Nothing here says anything about the rest of it.

One defect in the scope was found and has since been fixed. `-[IOPCMCIATuple
data]` starts at `0x1FDCD4` and is 67 bytes long, so it ends at `0x1FDD17`; the
scope used for this pass ended at `0x1FDCE0`, twelve bytes in, cutting the last
55 bytes off. IDA and Ghidra both returned the whole 67-byte body anyway, but
angr returned a zero-size function at that address, and the clipped scope is the
most likely reason. The old `end` was computed from the last function's entry
point rather than its extent; it should have been 2088215 (`0x1FDD17`) rather
than 2088160. This did not cost any coverage on the authoritative analysis.
**The scope has been corrected to `end: 2088215` in commit `013c4787`.** The
analyses referenced throughout this document, including the ones published in
`tools/binrecon/out/kernel-driverkit/`, were produced under the old,
uncorrected scope; a re-analysis under the fixed scope would be needed for
angr's zero-size entry at `0x1FDCD4` to clear.

## The missing PCMCIA modules

**Three of the five modules are absent from our kernel entirely.** Walking
`__OBJC,__module_info` in both binaries:

| Module | DR2 reference | `out/i386/mach_kernel` |
| --- | --- | --- |
| `IOPCIDirectDevice.m` | present | present |
| `IOPCIDeviceDescription.m` | present | present |
| `IOPCMCIADirectDevice.m` | present | **absent** |
| `IOPCMCIADeviceDescription.m` | present | **absent** |
| `IOPCMCIATuple.m` | present | **absent** |

The reference declares 78 modules and ours 75, and the difference is exactly
those three: our kernel contains every module the DR2 kernel contains, minus
these, and no extras. Correspondingly our kernel has
`.objc_category_name_IODirectDevice_IOPCIDirectDevice` but no
`.objc_category_name_IODirectDevice_IOPCMCIADirectDevice`.

The sources exist and the build system references them everywhere it should.
`src/driverkit-3/libDriver/Makefile` lists all three in `pcmcia_BUS_MFILES`
(line 133), folds that into `i386_KERN_MFILES` (line 175), and lists `pcmcia` in
`SOURCE_DIRS` (line 46), `BUS_LIST` (line 55) and `KERNEL_DIRS` (line 276).

Candidate causes that were checked and **ruled out** — kept here because, per
the resolution below, they now corroborate that explanation rather than being
dead ends:

- *Missing headers.* Every header the three files import resolves:
  `driverkit/KernDeviceDescription.h`, `driverkit/i386/PCMCIAKernBus.h`,
  `driverkit/KernBusMemory.h`, `driverkit/KernDevice.h`,
  `driverkit/IODirectDevicePrivate.h`,
  `driverkit/i386/IOEISADeviceDescriptionPrivate.h`,
  `driverkit/i386/IOPCMCIATuplePrivate.h`, `objc/List.h` (at `src/cc-791/cc/objc/List.h`).
- *`PCMCIA_SOCKET_LIST` and friends undefined.* They are defined in
  `src/kernel-7/driverkit/i386/PCMCIAKernBus.h`, but only inside
  `#ifdef DRIVER_PRIVATE`, and the three `.m` files define `KERNEL_PRIVATE`
  rather than `DRIVER_PRIVATE`. That looked like the answer until
  `src/driverkit-3/libDriver/Makefile:70` turned out to put `-DDRIVER_PRIVATE`
  in `KERN_CFLAGS`. The macros are visible.
- *`Range` unusable.* `- (Range)range` is declared on `KernBusRange` in
  `src/kernel-7/driverkit/KernBus.h:175`, so `memRange = [resource range];`
  in `mapAttributeMemoryTo:findSpace:` has a struct return type in scope and
  compiles.
- *Build-system omission.* Ruled out above.

**Resolved: this is an upstream omission, not a misconfiguration in this tree.**
Per the project owner, Apple's Darwin 0.3 release did not ship these three
modules in the *kernel* build — most likely an oversight on Apple's part — so
there is nothing in this tree to keep hunting for.

One nuance matters here. The *sources* were shipped: `git log` confirms all
five `.m` files, the three PCMCIA ones included, entered this repository at
commit `19ffee9a Original Darwin 0.3 Sources`, as part of the driverkit
component (see What is being compared, above). What Apple did not ship is
whatever makes the *kernel* actually link those three objects in — the sources
arrived with Darwin 0.3, the kernel-side inclusion did not, and that gap is
upstream. The candidate causes ruled out above are not dead ends under this
reading; they corroborate it, by showing there is nothing locally broken for
the missing kernel-side inclusion to be blamed on.

This reconciliation is the owner's account plus the local observations above,
not something a build has verified — no build was performed for this pass or
since (see Baseline build). Exactly where the kernel-side chain breaks would
still need a build host to pin down. But it is no longer a mystery to
investigate: the three modules were never expected to be in a Darwin 0.3 kernel
build. Consequently, the absence is not a defect to fix in this build
configuration — if PCMCIA support in the kernel is wanted, `IOPCMCIADirectDevice.m`,
`IOPCMCIADeviceDescription.m` and `IOPCMCIATuple.m` would need to be added to
the kernel build deliberately, as a feature decision rather than a repair. What
this costs this pass is unchanged and is not softened by the explanation:
eleven of the twenty-four methods could only be compared at control-flow level,
stated in the Summary.

## Analyzer disagreement

The three analyzers do not agree on the function partition, and the shortfall
matters more here than it did for the drivers. For a relocatable driver object,
the Mach-O symbol table names every method and independently corroborates every
address-to-name mapping. **A linked kernel names no methods at all**, so the
`__OBJC,__module_info` walk is the sole source of that mapping and
cross-analyzer agreement was the only independent check planned on it. With
Ghidra short by five and angr short by one, **that check is weaker than planned
and this mapping is not as well corroborated as the drivers' mappings were.**

What partly compensates, and is worth stating because it is a different field
rather than a different source: the module symtab records the *source file name*
alongside each method list, so `source_path` in the map is read out of the binary
rather than inferred from a class name. All 24 file attributions come from those
`module_info` `name` fields. That is still one metadata walk, not an independent
second opinion, so it narrows the exposure without closing it.

### Ghidra: 19 of 24, and the pattern is the linker's padding

Ghidra reports no function at `0x1FD0D4`, `0x1FD514`, `0x1FD644`, `0x1FDA10` or
`0x1FDBC0`. On the nineteen it does report it agrees with IDA **exactly, with zero
disagreements**, not only on start address and size but on instruction count and
basic-block count as well — including the 329-byte `unmapAttributeMemory` at 111
instructions over 9 blocks, and the 70-byte `getPCIdevice:function:bus:` at 32
instructions over 10 blocks. That is a strong signal for those nineteen.

The five misses are not random and they are not, as first suspected, the
`(Private)` category methods — three of the five are `(Private)`, but Ghidra finds
plenty of other category methods including `-[IODirectDevice(IOPCIDirectDevice)
isPCIPresent]` and `-[IODirectDevice(IOPCMCIADirectDevice) unmapAttributeMemory]`.
Reading the bytes in the gap before each of the 24 function starts settles it:

| Function | Pad bytes before it | Ghidra |
| --- | --- | --- |
| `0x1FD0D4` | `00 00 00` (just outside the scope) | no |
| `0x1FD514` | `00 00 00` | no |
| `0x1FD644` | `00 00` | no |
| `0x1FDA10` | `00 00 00` | no |
| `0x1FDBC0` | `00` | no |
| all nineteen others | `90`, `90 90`, `90 90 90` or nothing | yes |

The correlation is perfect. `90` is the assembler's `.align` padding *inside* an
object file; `00` is the link editor's zero fill *between* object files. So all
five zero-padded functions are the first function contributed by an object
file — `0x1FD0D4` included: the three bytes immediately before it are `00 00
00`, the same link-editor zero fill as the other four, just outside the scope
rather than inside it, because `0x1FD0D4` is the first function of the first
object file the scope covers. Ghidra's function finder evidently walks forward
through decoded code and treats a `90` run as alignment to step over but a `00`
run as data, breaking the chain at each object boundary.

IDA is authoritative for the partition; this is a Ghidra detection gap, not
evidence that the five functions are missing. Recorded, no action taken.

### angr: 23 of 24, plus 23 padding runs promoted to functions

angr reports 47 functions in the scope. Twenty-three are real. Twenty-three more
are alignment padding: every one is a run of one to three `0x90` bytes, either in
the gap before a real function or at an intra-function branch target. `0x1FD112`
and `0x1FD152` (`9090`), `0x1FD3D9` and `0x1FD425` (`909090`), `0x1FD69E` at
`mapAttributeMemoryTo:` + 90, and eighteen more of the same kind. `CFGFast`
recovers more than the metadata declares, and none of those twenty-three is
code. The 47th function reported is the remaining extra, and it is not padding:
it is the 158-byte misstart at `0x1FDBBF`, covered below as one of the two real
angr defects.

Two real angr defects, both traceable to the same zero padding that defeats
Ghidra:

- `0x1FDBC0` is missing because angr started the function one byte early, at
  `0x1FDBBF`, on the single `00` pad byte — decoding `00 55 89` as
  `add byte ptr [ebp-0x77], dl` and then continuing correctly for 158 bytes. So
  **`-[IOPCMCIATuple(Private) initWithKernTuple:]` rests on IDA alone**: Ghidra
  has nothing there and angr has a bogus leading instruction.
- `0x1FDCD4` (`-[IOPCMCIATuple data]`) is reported with size 0, almost certainly
  because the scope ends twelve bytes into it (see Scoping). angr contributes
  nothing usable for that method either, though Ghidra corroborates IDA's 67
  bytes there.

Net: two of the twenty-four methods have only a single analyzer behind them, and
one more has two.

## Finding 1: `[thePCIBus isPCIPresent] == YES` is compared as a 32-bit word

**Reference address:** `0x1FD514`, `-[IOPCIDeviceDescription(Private) _initWithDelegate:]`
**Source:** `src/driverkit-3/libDriver/pci/IOPCIDeviceDescription.m:78`

**Reference behaviour**

```
102 mov edx, ds:paIspcipresent
108 push edx
109 push esi                       ; thePCIBus
110 call _objc_msgSend             ; [thePCIBus isPCIPresent]
115 add esp, 8
118 3C 01   cmp al, 1              ; test the BOOL that came back in al
120 75 25   jnz loc_1FD5B3         ; -> leave private->valid at 0
```

**Ours**, at the corresponding point in `out/i386/mach_kernel` (`0x20A366`):

```
83 F8 01   cmp eax, 1
75 25      jnz ...
```

**Difference:** the reference compares `al`, ours compares the whole of `eax`.
The two functions are otherwise instruction-for-instruction identical — 67
instructions each, same order, same encoding lengths — and this single byte is
the entire size difference between them, 176 bytes in the reference against 177
in ours.

**Root cause:** `src/kernel-7/driverkit/i386/PCIKernBus.h` in our tree is a stub.
Its `HISTORY` block reads `11 Oct 2025 raynorpat / Created proper PCI bus support
for i386`, and past the licence header its entire body is one `#import` and four
`#define`s of resource-key strings.
**It declares no `@interface PCIKernBus` and no methods at all.** With no
declaration of `isPCIPresent` in scope at `IOPCIDeviceDescription.m:78`, GCC
assumes the message returns `id` and compares 32 bits. Apple's DR2 build had a
declaration returning `BOOL`, so it compared 8. That the declaration is genuinely
absent is not an inference: `cmp eax, 1` in our own binary proves GCC found no
signature for the selector, since it emits `cmp al, 1` whenever it has one.

For contrast, the driver-side copy of the same header,
`src/drivers-i386/bus/drvPCIBus/PCIBus.drvproj/PCIBus.lksproj/PCIKernBus.h`, does
declare `- (BOOL)isPCIPresent;` at line 64 and
`configAddress:device:function:bus:`, `getRegister:device:function:bus:data:` and
`setRegister:device:function:bus:data:` at lines 77, 82 and 88. The kernel-side
copy is the one that was stubbed.

**Disposition:** fix

**Rationale:** this is a latent ABI hazard, not a live bug. The compiled callee
settles the question directly. `out/i386/drvPCIBus/PCIBus.config/PCIBus_reloc`
holds an actual `-[PCIKernBus isPCIPresent]` — the same unproven-provenance
caveat applies to this artifact as to `out/i386/mach_kernel` (see Baseline
build):

```
test dword ptr [eax+0x18], 0xffffff00
setne al
and  eax, 0xff          ; explicitly zero-extends to 0/1
ret
```

`and eax, 0xff` zero-extends the result before it returns, so with the only
implementation this tree builds, `eax` is already 0 or 1 whenever `al` would be
checked, and `cmp eax, 1` behaves identically to `cmp al, 1`. The
intermittent-failure scenario this finding previously described —
`private->valid` left `NO` and `getPCIdevice:function:bus:` returning
`IO_R_NO_DEVICE` — is not demonstrated by this build and is contradicted by it.

What is real is the exposure: with no declaration in scope, GCC cannot know the
method returns `BOOL`, so nothing in the source enforces that `isPCIPresent`'s
upper 24 bits stay zero. The ABI only defines `al` for a `char`/`BOOL` return, so
a conforming implementation is free to leave garbage above it, and such an
implementation would break under `cmp eax, 1`. Today's callee happens to
zero-extend; nothing in the type system guarantees the next one will.

The fix belongs in the header, not in the module: restore an `@interface
PCIKernBus` declaring at least `isPCIPresent`, `configAddress:device:function:bus:`,
`getRegister:device:function:bus:data:` and `setRegister:device:function:bus:data:`,
with the signatures the driver-side header already carries. It removes a real
fragility even though it is not causing a failure today. Finding 2 is fixed by
the same change.

**Outcome:** fixed in commit `99a55c1b`. `src/kernel-7/driverkit/i386/PCIKernBus.h`
now carries an `@interface PCIKernBus : KernBus` declaring the eleven methods the
shipped `PCIBus_reloc` metadata attests, `- (BOOL)isPCIPresent;` among them, so
`IOPCIDeviceDescription.m:78` has a `BOOL` signature in scope and should emit
`cmp al, 1`. No ivars are declared kernel-side; the kernel only messages the
object. Ledger `0x1FD514` advanced `unexamined` -> `control-flow-confirmed`. Not
`assembly-matched`: no build was run, so the predicted `cmp al, 1` is unverified.

## Finding 2: the config-register number is not narrowed before `getRegister:` / `setRegister:`

**Reference addresses:** `0x1FD154`
(`+[IODirectDevice(IOPCIDirectDevice) getPCIConfigSpace:withDeviceDescription:]`)
and `0x1FD248` (the `set` twin)
**Source:** `src/driverkit-3/libDriver/pci/IOPCIDirectDevice.m:95-99`, `:133-137`

**Reference behaviour**, in the 64-iteration config-space loop:

```
131 0F B6 C3   movzx eax, bl        ; ebx is the loop counter `address`, an int
134 50         push eax             ; -> getRegister:  (narrowed to a byte)
135 mov edx, ds:paGetregisterDev
141 push edx
142 push edi                        ; thePCIBus
143 call _objc_msgSend
148 add esp, 1Ch
```

**Ours**, at the same offset in `out/i386/mach_kernel` (`0x209FB7`):

```
53   push ebx                       ; the full 32-bit int
```

**Difference:** four bytes of narrowing replaced by a one-byte push, in each of
the two class methods. Everything else in both functions matches exactly, same
order and encodings, and this is the whole of the size difference: 178 bytes
against 175, and 180 against 177.

**Root cause:** the same stub `PCIKernBus.h` as Finding 1. The reference's
`getRegister:` declares its first parameter as `unsigned char` (the driver-side
header still does, at line 82), so GCC converts the `int address` loop counter at
the call site. With no declaration in scope our build applies the default
argument promotions and pushes the `int` whole.

Note that `+[IODirectDevice getPCIConfigData:atRegister:withDeviceDescription:]`
does *not* diverge here — both binaries emit `movzx eax, [ebp+var_8]` — because
that method's *own* parameter is declared `(unsigned char)address` in
`driverkit/i386/IOPCIDirectDevice.h`, which our tree does have. The divergence
only appears where the narrowing has to come from the callee's declaration.

**Disposition:** fix

**Rationale:** lower severity than Finding 1 and worth saying so. The callee reads
its parameter as `unsigned char` off the stack, i386 is little-endian, and the
loop counter only ever holds 0 to 252, so the byte actually delivered is correct
today and the behaviour is identical. What makes it worth fixing is that it is the
same one-line header change as Finding 1, and that the current state means the
compiler is type-checking none of these four calls — a future argument-order or
type error in `getRegister:device:function:bus:data:` would pass silently.

**Outcome:** fixed in commit `99a55c1b`, by the same header. `getRegister:` and
`setRegister:` now declare their first four parameters `unsigned char`, matching
the reference's `i28@8:12C16C20C24C28^L32` and `...L32`, so the `int address`
loop counter should be narrowed at the call site. Ledger `0x1FD154` and
`0x1FD248` advanced `unexamined` -> `control-flow-confirmed`.

## Finding 3: `unmapAttributeMemory` will hit the same undeclared-`BOOL` problem

**Reference address:** `0x1FD8C4`, `-[IODirectDevice(IOPCMCIADirectDevice) unmapAttributeMemory]`
**Source:** `src/driverkit-3/libDriver/pcmcia/IOPCMCIADirectDevice.m:141`

**Reference behaviour**

```
145 mov ecx, ds:paMemoryinterfac
151 push ecx
152 push ebx                        ; window
153 call _objc_msgSend              ; [window memoryInterface]
158 add esp, 1Ch
161 84 C0   test al, al
163 74 77   jz loc_1FD9E0           ; -> next iteration

165 mov edx, ds:paAttributememor
171 push edx
172 push ebx
173 call _objc_msgSend              ; [window attributeMemory]
178 add esp, 8
181 84 C0   test al, al
183 74 63   jz loc_1FD9E0
```

**Our source**

```objc
if ([window memoryInterface] && [window attributeMemory]) {
```

**Difference — predicted, not measured.** `src/kernel-7/driverkit/i386/PCMCIAKernBus.h`
is a stub in exactly the same way `PCIKernBus.h` is: past the licence header, one
`#import`, eight `#define`s, no `@interface PCMCIAKernBus` and no method
declarations at all. Neither
`memoryInterface` nor `attributeMemory` is declared anywhere our tree can see
them, so the two `test al, al` byte tests above should come out as `test eax, eax`
word tests, with the same undefined-upper-bits exposure as Finding 1.

**This could not be confirmed.** `IOPCMCIADirectDevice.m` is not in
`out/i386/mach_kernel`, so there is no compiled counterpart to disassemble, and
the claim rests on the type rules plus the measured behaviour of the identical
construct in Finding 1. It is recorded as a finding rather than a certainty
because the fix is the same header work and skipping it would leave a known
exposure undocumented.

The rest of the method matches the reference on a control-flow read and is
recorded under "Examined with no divergence found".

**Disposition:** fix

**Rationale:** if the prediction holds, the consequence is a spurious match, not
a missed one. With `test eax, eax`, dirty bits above `al` make a false `BOOL`
read as true, so a window that is *not* the attribute-memory window could be
wrongly treated as one and torn down, while the real attribute-memory window is
walked past unmatched. Fixing it is the same change as Findings 1 and 2 applied
to the PCMCIA header. Whoever applies it should confirm the prediction against a
build rather than assume it.

**Outcome:** not fixed; the finding stands. Commit `99a55c1b` does give
`src/kernel-7/driverkit/i386/PCMCIAKernBus.h` a real `@interface PCMCIAKernBus`,
but that does not reach this line. `memoryInterface` and `attributeMemory` are
not `PCMCIAKernBus` methods: `window` here is an adapter-supplied object, and
walking `__OBJC,__module_info` in the reference `PCMCIABus_reloc` shows the bus
driver declares no window class at all. The only declarations of the two
selectors anywhere in the tree are `- (char)memoryInterface` and
`- (char)attributeMemory` on `PCICWindow`, in the 82365 adapter driver, which
`libDriver` cannot see. Their return types are not invented, though: `PCIC_reloc`,
in the same reference directory as this kernel's `mach_kernel_dr2_x86`, attests
`-[PCICWindow memoryInterface]`, `-[PCICWindow attributeMemory]` and
`-[PCICSocket memoryInterface]`, all encoded `c8@8:12` there, so a `char` return
is recoverable, not guessed. What is genuinely missing is a kernel-visible class
to hang them on — `PCMCIABus_reloc` declares no window or socket class at all,
and `window` here is an adapter-supplied object outside `PCMCIAKernBus`'s own
interface — so declaring `memoryInterface`/`attributeMemory` on `PCMCIAKernBus`
would still mean inventing a home the reference does not have, and that was not
done. `src/kernel-7/driverkit/i386/PCMCIA.h`, a two-line `// TODO` stub in the
same directory already imported by `autoconf_i386.m`, is the likely home if a
kernel-visible window/socket interface is ever added. Ledger `0x1FD8C4` stays
`unexamined`, per the convention that a method known to diverge is written up
rather than given a status it has not earned.

## Finding 4: `-[IOPCMCIATuple data]` carries a stray semicolon and does not map

**Reference address:** `0x1FDCD4`
**Source:** `src/driverkit-3/libDriver/pcmcia/IOPCMCIATuple.m:83`

**Ours**

```objc
- (unsigned char *) data;
{
```

**Difference:** a semicolon between the method declaration and its body. This is
the sole reason `-[IOPCMCIATuple data]` sits in the source map's `unmapped`
bucket rather than `mapped` — `binrecon.source_map.source_sites` treats a
declaration line ending in `;` as a forward declaration and does not record a
definition site (`source_map.py:110`, `:134`). Every other method in the five
modules mapped.

The generated code is not affected. The reference's 67-byte body and our source
agree completely: the `private->data == NULL` guard, `IOMalloc(private->length)`,
`bcopy([private->kernTuple data], private->data, private->length)` with the
arguments in that order, and the return of `private->data`.

Note also that the method's `unsigned length;` local is never used. The compiler
discards it and the reference's frame shows no slot for it.

**Disposition:** fix

**Rationale:** the semicolon is Apple's own typo, not ours, and old GCC accepted
it — the DR2 kernel contains the method, so it compiled there too. It is worth
removing anyway because it costs a source-map entry and therefore a ledger
`source_path`, and because a stricter compiler will reject it. The change is one
character and cannot alter behaviour.

**Outcome:** fixed in the commit that carries this record. The semicolon is gone
from `IOPCMCIATuple.m:83`. Ledger `0x1FDCD4` advanced `unexamined` ->
`control-flow-confirmed` and now carries `source_path`
`src/driverkit-3/libDriver/pcmcia/IOPCMCIATuple.m` and `source_line` 83, which it
could not before. The unused `unsigned length;` local was left alone.

## Finding 5: our `IOPCIDeviceDescription` has two methods DR2 does not (accepted)

**Source:** `src/driverkit-3/libDriver/pci/IOPCIDeviceDescription.m:123-140`

The reference's `IOPCIDeviceDescription.m` module declares exactly three methods:
`-[IOPCIDeviceDescription(Private) _initWithDelegate:]`,
`-[IOPCIDeviceDescription free]` and
`-[IOPCIDeviceDescription getPCIdevice:function:bus:]`. Ours adds two more, and
`out/i386/mach_kernel` confirms they are really built:

```
-[IOPCIDeviceDescription property_IODeviceType:length:]   @16@8:12*16^I20
-[IOPCIDeviceDescription property_IOSlotName:length:]     @16@8:12*16^I20
```

The first appends `" "IOTypePCI` to the inherited device-type string; the second
formats `"Dev=%d Func=%d Bus=%d"` from the private struct.

**Disposition:** accept

**Rationale:** these are additions Apple made between DR2 and Darwin 0.3, not
divergences to correct. The `property_*` device-inspection protocol did not exist
in DR2 — no module in the reference implements it — so their absence there is
expected. Removing them to match the reference would delete working functionality
that later Apple releases depend on. They have no reference address and therefore
no ledger entry.

**Outcome:** accepted, no code change. No ledger entry exists to transition.

## Finding 6: unused `_busPrivate` locals in both PCMCIA direct-device methods (accepted)

**Source:** `src/driverkit-3/libDriver/pcmcia/IOPCMCIADirectDevice.m:56`, `:124`

Both methods open with

```objc
struct _eisa_private *private = _busPrivate;
```

and never use `private` again. `_busPrivate` sits at ivar offset 280 (`0x118`) in
`IODirectDevice`; the reference reads `[self+0x114]` (`_deviceDescriptionDelegate`)
repeatedly in both functions and never touches `0x118`. The compiler discards the
local and emits nothing for it, so this is not a divergence from the reference at
all.

**Disposition:** accept

**Rationale:** dead code in Apple's own source, and per the repository's own rule
on adjacent dead code it is mentioned rather than removed. Recorded so that a
later reader does not mistake it for a missing feature.

**Outcome:** accepted, no code change. Both locals are still there. The two
methods' ledger entries were not touched by this finding.

## Examined with no divergence found

Everything below was checked and matches. It is recorded positively because a
report whose only content is six findings would misrepresent how much of this
layer is confirmed correct.

**Ten PCI methods, byte-for-byte.** `+`/`-isPCIPresent`, `-getPCIConfigSpace:`,
`-setPCIConfigSpace:`, `+`/`-getPCIConfigData:atRegister:`,
`+`/`-setPCIConfigData:atRegister:`, `-[IOPCIDeviceDescription free]` and
`-[IOPCIDeviceDescription getPCIdevice:function:bus:]` decode to identical
mnemonic and encoding-length sequences in both binaries, differing only in
link-time absolute addresses. That covers the whole config-space read and write
path except the two loops in Finding 2.

**Every `IOReturn` constant.** `0xFFFFFD40` is `IO_R_NO_DEVICE` (-704),
`0xFFFFFD2B` is `IO_R_BUSY` (-725), `0xFFFFFD42` is `IO_R_RESOURCE` (-702) and
`0xFFFFFD43` is `IO_R_NO_MEMORY` (-701), all matching
`src/driverkit-3/driverkit/return.h:39-64` and our source's use of them at each
site. `mapAttributeMemoryTo:findSpace:` returns `IO_R_RESOURCE` from two separate
`nil` checks that the compiler merged into one block at `0x1FD6F9`, exactly as
our source's two `return IO_R_RESOURCE;` statements would.

**All 24 method type encodings.** Read out of `__OBJC,__meth_var_types` and
checked against our `@interface` declarations. Every one agrees, including
`i13@8:12^I16c20` for `mapAttributeMemoryTo:findSpace:` (`vm_address_t *` plus
`BOOL`), `v8@8:12` for `unmapAttributeMemory`, `C8@8:12` and `I8@8:12` for
`-[IOPCMCIATuple code]` and `length`, and `^@8@8:12` for `tupleList`.

Two encodings looked like divergences and are not:

- `-[IOPCIDeviceDescription getPCIdevice:function:bus:]` encodes its three
  parameters as `*` (`char *`) although our header declares them
  `(unsigned char *)`, and `-[IOPCMCIATuple data]` encodes its return as `*`
  although our header declares `(unsigned char *)`. Old GCC collapses any
  pointer-to-`QImode`-integer to `*` regardless of signedness. Our own build of
  the same declarations produces `i20@8:12*16*20*24` for `getPCIdevice:`, which
  settles it empirically. Note the encoder *does* distinguish signedness for
  scalars — `code` is `C`, `isPCIPresent` is `c`.
- `IOPCIConfigSpace` encodes as `^{?=...}`, an anonymous struct tag, although
  `src/kernel-7/driverkit/i386/PCI.h:17` declares
  `typedef struct _IOPCIConfigSpace {...} IOPCIConfigSpace;` with a tag. The
  reference's `__meth_var_types` does carry 21 named tags elsewhere
  (`{task=`, `{disktab=`, `{iovec=`, `{timeval=` and so on) so the encoder is
  capable of emitting them, but our own build produces `{?=` for this struct too:
  GCC replaces the record's `TYPE_NAME` with the typedef's `TYPE_DECL` and then
  falls back to `?`. Not a divergence.

**The `IOPCIConfigSpace` layout, field by field.** The reference's
`^{?=SSSSb8b24CCCC[6L]LSSLLLCCCC[48L]}` decomposes exactly onto
`src/kernel-7/driverkit/i386/PCI.h:17-40`: four `unsigned short`
(VendorID, DeviceID, Command, Status), `RevisionID:8` and `ClassCode:24`, four
`unsigned char` (CacheLineSize, LatencyTimer, HeaderType, BuiltInSelfTest),
`BaseAddress[6]`, CardbusCISpointer, SubVendorID and SubDeviceID, ROMBaseAddress
with reserved3 and reserved4, four `unsigned char`
(InterruptLine, InterruptPin, MinGrant, MaxLatency) and `VendorUnique[48]` —
256 bytes, the PCI config space. Field order and widths are identical, so
config-space reads decode correctly.

**Every private-struct layout.** `struct _pci_private` is `IOMalloc(4)` with
`valid` at +0, `devNum` +1, `funNum` +2, `busNum` +3, matching
`IOPCIDeviceDescription.m:47-50`. `struct _pcmcia_private` is `IOMalloc(8)` with
`tupleCount` at +0 and `tupleList` at +4. `struct _tuple_private` is
`IOMalloc(0x10)` with `kernTuple` at +0, `code` at +4, `length` at +8 and `data`
at +0x0C, matching `IOPCMCIATuple.m:34-39` including the three padding bytes
after `code`.

**Every ivar offset the 24 methods touch**, compared across both binaries:
`IODirectDevice._deviceDescriptionDelegate` at +276 (`0x114`),
`IOPCIDeviceDescription._pci_private` at +36 (`0x24`),
`IOPCMCIADeviceDescription._pcmcia_private` at +36, `IOPCMCIATuple._private` at
+4, and identical `instance_size` for `IODeviceDescription` (32),
`IODirectDevice` (296), `IOEISADeviceDescription` (36) and
`IOPCIDeviceDescription` (40).

**Signed and unsigned loop comparisons.** `+getPCIConfigSpace:` uses
`cmp ebx, 0FFh` / `jle` — a signed test, matching our `int address` against
`address < 0x100`. `-[IOPCMCIADeviceDescription free]`, `tupleList` and
`unmapAttributeMemory` all use `jbe` / `ja` / `jnb`, matching our `int i` promoted
to unsigned against an `unsigned` count.

**`[super ...]` dispatch.** The reference uses `objc_getOrigClass("IOEISADeviceDescription")`
in both `_initWithDelegate:` methods and `objc_getOrigClass("Object")` in
`initWithKernTuple:` — the category form — and a static `__OBJC,__class` super
struct in the three plain-`@implementation` `free` methods. That matches which of
our methods sit in a category and which do not, and confirms
`IOPCIDeviceDescription : IOEISADeviceDescription` and
`IOPCMCIADeviceDescription : IOEISADeviceDescription` as our headers declare them.

**The eleven PCMCIA-side methods at control-flow level.** Branch structure,
constants, message-send order and call targets in `mapAttributeMemoryTo:findSpace:`
(639 bytes, 12 blocks), `unmapAttributeMemory` (329 bytes, 9 blocks), the four
`IOPCMCIADeviceDescription` methods and the five `IOPCMCIATuple` methods all match
our source. Two details worth naming because they are easy to get backwards and
are right: `[memWindow setMapWithSize:memRange.length systemAddress:memRange.base
cardAddress:0]` takes the *second* dword of the `Range` returned in `eax:edx` as
the size and the first as the address, which is what our source does; and the
window-teardown sequence is `setAttributeMemory:NO`, `setEnabled:NO`,
`[[window socket] setMemoryInterface:NO]`, `removeObject:`, `free`, `break`, in
that order.

## Uncertainty and limits of this pass

- **No build, no parity run, no `assembly-matched`.** Nineteen methods reach
  `control-flow-confirmed` and that is the ceiling this pass can reach. Findings 1
  and 2 are the only ones with instruction-level evidence on both sides, and even
  they rest on an artifact of unproven provenance.
- **Eleven of twenty-four methods were compared at control-flow level only**,
  because the three PCMCIA modules are missing from our kernel — an upstream
  Darwin 0.3 omission, not a defect here (see The missing PCMCIA modules).
  Finding 3 is a prediction within that gap, not a measurement. If those three
  modules are ever added to the kernel build, all eleven should be re-compared
  at instruction level before they are trusted.
- **Two methods rest on a single analyzer.**
  `-[IOPCMCIATuple(Private) initWithKernTuple:]` has IDA only — Ghidra missed it
  and angr mis-started it a byte early. `-[IOPCMCIATuple data]` has IDA and
  Ghidra, angr having returned size 0. Combined with the absence of method
  symbols in a linked kernel, the address-to-name mapping for those two is the
  least corroborated in the set. Nothing contradicts it, but nothing independent
  confirms it either.
- **The reference is DR2 and our source is Darwin 0.3.** Where the two differ it
  is not always obvious which direction is "correct". Finding 5 is a clear case of
  a later addition that should stay; a subtler version-drift difference could in
  principle be sitting inside one of the eleven control-flow-only comparisons
  without being visible at that resolution.
- **The scope end used for this pass was 55 bytes short** of the end of the last
  function (2088160 / `0x1FDCE0` against the 2088215 / `0x1FDD17` it should have
  been), because the old value was computed from the last function's entry point
  rather than its extent. It cost nothing measurable on IDA or Ghidra but is the
  most likely cause of angr's zero-size entry at `0x1FDCD4`. **Fixed in
  `013c4787`.** The published analyses in `tools/binrecon/out/kernel-driverkit/`
  were produced under the old scope; a re-analysis under the corrected scope
  would be needed for that entry to clear.
- **The two stub headers were not audited beyond what these five modules need.**
  `src/kernel-7/driverkit/i386/PCIKernBus.h` and `.../PCMCIAKernBus.h` are stubs
  in their entirety. The only other importer in the tree is
  `src/kernel-7/driverkit/i386/autoconf_i386.m`, which was not examined; it is
  exposed to the same class of problem as Findings 1 to 3.

## The two kernel bus interfaces, as written

The header work behind Findings 1 to 3 is recorded here rather than only in the
commit, because it is the one part of this pass that was not derived from the
kernel reference.

Both interfaces come from the shipped bus drivers' Objective-C metadata, read out
of `PCIBus.config/PCIBus_reloc` and `PCMCIABus.config/PCMCIABus_reloc` by walking
`__OBJC,__module_info` to each class's method list and printing the
`__meth_var_types` string beside each selector. `PCIKernBus` reports
`instance_size` 44 and eleven methods; `PCMCIAKernBus` reports 40 and fifteen.
Both instance sizes agree with the ivar layouts our own driver-side headers
declare, which is an independent check that the right classes were read.

Two encodings needed a decision:

- `-[PCMCIAKernBus statusChangedForSocket:changedStatus:]` takes
  `{?=b1b1b1b1b2b1b1}` — seven bit-fields totalling eight bits. That is exactly
  the `PCMCIAStatus` the 82365 adapter driver declares in
  `src/drivers-i386/bus/Intel82365PCMCIA/PCIC.drvproj/PCIC.lksproj/PCICSocket.h`:
  `present:1`, `locked:1`, `ejectRequest:1`, `insertRequest:1`,
  `batteryStatus:2`, `writeProtect:1`, `ready:1`. The kernel header declares the
  same struct under the same name and with the same fields in the same order.
  **It is a second declaration, not a shared one** — the two live in different
  projects with no header in common, and neither can reach the other's include
  path. No translation unit sees both today, so nothing is broken, but a future
  file that imports both will get a duplicate `typedef`. Unifying them needs a
  home for the type that both projects can import, which is a larger change than
  this pass is scoped for.
- `-[PCMCIAKernBus setBusRange:]` takes `{?=II}`, and the class's own `busRange`
  ivar encodes as `{?="base"I"length"I}`. That is `Range` from
  `src/kernel-7/driverkit/KernBus.h:113`, field names included, so the existing
  type is used rather than a new one. The anonymous `?` tag here is not the
  `IOPCIConfigSpace` collapse — GCC emits `{_Range=...}` for a tagged struct, so
  a bare `?` means the type had no tag at all. Apple's `Range` was apparently an
  anonymous-struct typedef, where ours is `struct _Range` (`KernBus.h:113`): a
  real but harmless encoding-only divergence between the two `Range` definitions,
  not a GCC collapse.

Everything else maps directly: `C` to `unsigned char`, `L` to `unsigned long`,
`^L` to `unsigned long *`, `c` to `BOOL`, `i` to `int` (or `IOReturn`, which is
`typedef int`, on the three methods that return a driver status), `^@` to
`Protocol **`, `r*` to `const char *`, `*` to `unsigned char *` on
`configAddress:`'s three out-parameters, following this document's own note that
old GCC collapses any pointer-to-byte to `*`.

Neither header declares ivars. The kernel only sends these objects messages; the
storage belongs to the loadable driver, and declaring a second copy of the layout
would create a divergence to maintain for no gain.

## Signatures our bus drivers do not match

The metadata read for the headers also answers a question nobody had asked: does
our `drvPCIBus` and `drvPCMCIABus` implement what Apple declared? Mostly yes —
twenty-three of the twenty-six methods agree exactly. Three do not, and two of
the three are settled: our own source shows they are bugs in our drivers, not
alternate valid signatures. **Nothing was changed on either side in this pass**
— `drvPCIBus` and `drvPCMCIABus` were outside its scope.

| Method | Reference | Ours |
| --- | --- | --- |
| `-[PCIKernBus maxBusNum]`, `maxDevNum` | `i8@8:12`, so `- (int)` | `- (unsigned int)` |
| `-[PCIKernBus testIDs:dev:fun:bus:]` | `c21@8:12r*16C20C24C28`, so `(const char *)ids` and three `unsigned char` | `(unsigned int *)ids` and three `unsigned int` |
| `-[PCMCIAKernBus statusChangedForSocket:changedStatus:]` | `{?=b1b1b1b1b2b1b1}`, the `PCMCIAStatus` bitfield | `(unsigned int)status` |

The first is genuinely ABI-identical — `int` and `unsigned int` return in `eax`
identically — and needs no follow-up. The other two are not open questions: our
own source proves the reference is right in both cases.

`PCIKernBus.m:366` opens `- (BOOL)testIDs:(unsigned int *)ids dev:...` with
`const char *idStr = (const char *)ids;` and then string-parses it character by
character — the body only ever treats `ids` as a byte string. All three call
sites (`PCIKernBus.m:247`, `:277`, and `PCIResourceDriver.m:411`) cast a `char`
buffer *to* `(unsigned int *)` purely to satisfy our wrong prototype. Apple's
`const char *` plus three `unsigned char` is unambiguously correct; ours is a
mis-reconstruction, not an alternate signature.

`PCMCIAKernBus.m:705` does `if ((changedStatus & 1) == 0)` — literally testing
`status.present`, the first bit of the `PCMCIAStatus` bitfield. Apple's bitfield
parameter is correct; our `(unsigned int)status` is not. Neither divergence is
reachable across the affected boundary today — `testIDs:` is sent only from
inside `drvPCIBus`, and our PCMCIA stack is self-consistent because the 82365
driver's `PCMCIAStatusChange` protocol also declares `(unsigned int)status` —
but that reflects the current callers, not evidence the signatures are right.

Correcting `testIDs:dev:fun:bus:` on `PCIKernBus` and
`statusChangedForSocket:changedStatus:` on `PCMCIAKernBus` to match the
reference is follow-up work for `drvPCIBus`'s and `drvPCMCIABus`'s own
reconstruction passes.

Our ivar *names* diverge too, though the layouts do not. The reference's
`PCIKernBus` names them `maxBusNum`, `maxDevNum`, `BIOS16Present`,
`configMethod1`, `configMethod2`, `specialCycle1`, `specialCycle2`,
`BIOS32Present`, `BIOS32Entry`, `majorVersion`, `minorVersion`; the reference's
`PCMCIAKernBus` names them `adapters`, `busRange` (a `Range`, where ours has two
separate `unsigned int`s at the same offsets), `socketTable`, `verbose` (a `char`,
where ours has an `int` in a slot that pads to the same size) and `attrMem`. Both
`instance_size` values still match. These belong in the two drivers' own
reconstruction records, not this one, and are noted here only because this is
where they were found.

## Post-fix parity

**No build was performed and no parity run was performed.** There is no route to
a Rhapsody build host from here, which is the same reason the report pass could
not run one. `binrecon compare` therefore had nothing to compare:
`rebuilt_sha256` stays `null`, no entry is `assembly-matched`, and no number in
this document was estimated to stand in for one.

Every change in this pass landed uncompiled. That includes two headers included
by four `libDriver` modules and by `src/kernel-7/driverkit/i386/autoconf_i386.m`,
so a mistake in them would surface in five translation units that nobody here can
compile. In place of a build, the following were checked by reading:

- Every type the new declarations name resolves from an import already present
  or newly added: `IOReturn` from `driverkit/return.h` (added to `PCIKernBus.h`),
  `IODeviceStyle` from `driverkit/driverTypes.h` (added to `PCMCIAKernBus.h`),
  `Range` and `KernBus` from `driverkit/KernBus.h`, `Protocol` from the
  `@class Protocol` at `objc/objc.h:136` that `KernBus.h` already pulls in. Both
  additions are headers all five translation units already include transitively.
- No selector declared in either header is declared elsewhere in a reachable
  header with a different signature. The four class methods that are also
  declared in `driverkit/IODevice.h` and `driverkit/KernBus.h` — `probe:`,
  `deviceStyle`, `requiredProtocols`, `configureDriverWithTable:` — are written
  with the same spellings those headers use, so a translation unit that sees both
  sees one consistent declaration rather than a conflict.
- Both new `@interface` blocks sit inside the existing `#ifdef DRIVER_PRIVATE`,
  as `KernBus.h`'s own contents do, and `libDriver/Makefile:70` puts
  `-DDRIVER_PRIVATE` in `KERN_CFLAGS`.
- `drvPCIBus` and `drvPCMCIABus` declare these same two classes in their own
  project-local headers and reach them through quoted includes, so no translation
  unit sees two `@interface` blocks for either class. That is true today and is
  not enforced by anything.

The consequence for the ledger is that `control-flow-confirmed` is the ceiling.
Twenty-three of the twenty-four entries are there; `-[IODirectDevice
unmapAttributeMemory]` at `0x1FD8C4` stays `unexamined` because Finding 3 is
unfixed. The predicted code changes behind Findings 1 and 2 — `cmp al, 1` in
`_initWithDelegate:`, `movzx eax, bl` before the two config-space loops — are
predictions until a build confirms them, and confirming them is the first thing a
build host should be used for.
