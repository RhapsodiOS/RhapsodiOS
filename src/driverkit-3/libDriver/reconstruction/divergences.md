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

That last category is where this document originally placed every real
divergence. A build showed that the supporting headers are *not* what changes
the emitted code here; a second experiment then found what does — **the static
type of the message receiver at the call site.** Findings 1 and 2 are resolved
by that change and no longer diverge in the current build. The header work
stays, on its own terms, but it was never the mechanism.

## Baseline build

**No build was performed as part of the report or fix passes, and no build host
was reachable then.** No parity run, no rebuilt artifact, no `assembly-matched`
claim. Nothing in this document estimates or invents build output. (Builds have
since been performed, described in the two subsections at the end of this
section. The first falsified the fix pass's central prediction; the second
confirmed the mechanism that replaced it and resolved Findings 1 and 2. Still no
parity run, so `assembly-matched` remains unclaimed.)

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

### The verification build, and what it falsified

A build host was subsequently reached and **six kernel builds were made** in
order to test the fix pass's prediction that declaring `@interface PCIKernBus`
would change the emitted code. It does not. The prediction was wrong, and the
detail is recorded here because the *procedure* took five attempts to get right
and every wrong attempt looked like a success.

The final build satisfies every precondition:

- `out/i386/mach_kernel`, built 2026-07-26 11:02, SHA-256
  `DA6E06AE910CFDC48BA33B8648CBCFB74EE7DCBC904BBA180B9CD86DA06F02AD`. This
  supersedes the unproven-provenance artifact described above; its provenance
  *is* known.
- The updated header is installed where the compiler actually reads it.
  `grep -c isPCIPresent
  /System/Library/Frameworks/System.framework/PrivateHeaders/driverkit/i386/PCIKernBus.h`
  returns **1**.
- GCC's `-H` include trace confirms it opens *that* file, not the source-tree
  copy, while compiling the affected modules.
- The affected objects were force-recompiled: `touch` on the five `.m` files
  under `libDriver/pci` and `libDriver/pcmcia`, after a prior `gnumake clean`.

The result, measured in that kernel:

- `-[IOPCIDeviceDescription(Private) _initWithDelegate:]` is still at
  `0x20A2F0` — **the same address it held in every one of the six builds** — and
  still contains `83 f8 01` (`cmp eax, 1`), with no `3c 01` anywhere in it.
- All four `ConfigSpace` methods still lack `0f b6 c3` (`movzx eax, bl`).

Apple's reference does have `3c 01` and `0f b6 c3` at those sites; that half of
the comparison was always correct and is unchanged. **What is falsified is the
stated cause.** Declaring the interface does not produce Apple's codegen.

That falsification is kept in place rather than deleted. It is what makes the
answer below trustworthy: the header hypothesis was stated, installed, forced
through six builds, and measured to do nothing, so the mechanism that *did* work
was not simply the first guess that happened to coincide with a rebuild.

### The receiver-typing build, and what it confirmed

The replacement hypothesis the falsification left behind — that this GCC ignores
a declared method signature entirely when the receiver is `id` — was then
tested, and it holds.

Commit `53f1fc3a` changed `getThePCIBus()` to return `PCIKernBus *` instead of
`id` and typed all seven receiver locals: six in
`src/driverkit-3/libDriver/pci/IOPCIDirectDevice.m` and one in
`src/driverkit-3/libDriver/pci/IOPCIDeviceDescription.m:70`. Nothing else
changed. The build that followed is the current reference point for this
document:

- `out/i386/mach_kernel`, 1472800 bytes, built 2026-07-26 11:47, SHA-256
  `A82940452938737FB8514C334434CEAF70B4DC39179A4047B4153D9B589325C1`. It
  supersedes `DA6E06AE...` and the unproven-provenance artifact before it.

Measured in that kernel:

- `-[IOPCIDeviceDescription(Private) _initWithDelegate:]` contains `3c 01`
  (`cmp al, 1`) and no `83 f8 01`.
- It also **moved to `0x20abc4`**, from the `0x20a2f0` it had held unchanged
  through all six earlier builds. That movement is the strongest single signal
  in this experiment: it shows the object genuinely recompiled differently
  rather than being relinked from a stale `.o`, which is precisely the failure
  mode that produced every false negative before it.
- `+[IODirectDevice(IOPCIDirectDevice) getPCIConfigSpace:withDeviceDescription:]`
  and `+setPCIConfigSpace:withDeviceDescription:` contain `0f b6 c3`
  (`movzx eax, bl`), as do `-getPCIConfigData:atRegister:` and
  `-setPCIConfigData:atRegister:`.

**Mechanism, confirmed by experiment:** with an `id` receiver this GCC assumes
an `id`-sized return and applies the default argument promotions no matter how
many visible headers declare the selector. A typed receiver is what lets it
reach the declared `BOOL` return and `unsigned char` parameters. That single
mechanism accounts for Findings 1 and 2 together, and it explains why installing
the declarations changed nothing on their own.

**The header change stays, and is still correct.** A header describing a class
should declare that class, and the declaration is exactly what a typed receiver
then consults — the typed receiver would have nothing to read without it. It
simply was not sufficient by itself, which is what this document previously got
wrong.

### Reference-versus-rebuilt comparison in this build

Because the three PCMCIA modules are also present in this kernel (see The
missing PCMCIA modules), all 24 reference methods could be disassembled on both
sides for the first time. Comparing them by walking `__OBJC,__module_info` in
each binary and disassembling each method's extent with capstone:

- All 24 methods have **identical extents** on both sides.
- **23 of 24 decode to identical mnemonic and operand sequences**, differing
  only in link-time absolute addresses. (The 24th,
  `-[IOPCIDeviceDescription getPCIdevice:function:bus:]`, differs only in the
  inter-object padding after its `ret` — `00 00` in the reference against
  `90 90` in ours — so its code is identical too.)
- The one genuine remaining divergence is
  `-[IODirectDevice(IOPCMCIADirectDevice) unmapAttributeMemory]`, where the
  reference's two `84 c0` (`test al, al`) are `85 c0` (`test eax, eax`) in ours.
  That is Finding 3, which until this build was a prediction and is now a
  measurement.

This was an ad-hoc check using binrecon's Objective-C metadata walk plus
capstone, **not** a `binrecon compare` parity run and not a three-analyzer pass,
so it does not by itself earn any entry an `assembly-matched` status. It is
recorded because it is the first two-sided evidence this pass has had.

### The formal parity run, and why binrecon still cannot certify it

A real `binrecon analyze` parity pass has since been run against this same
kernel. It required a tooling change first: binrecon pairs reference and rebuilt
functions by **section-relative offset**, which is correct for relocatable driver
objects but cannot work for two independently linked kernels — ours carries more
code ahead of the region, so not one of the 24 methods paired. The first run
returned 24 `missing-rebuilt` and 26 `missing-reference` with nothing compared.

Commit `8ae85861` added a second, additive pairing pass: functions the offset
pass leaves unmatched on both sides are paired by a uniquely shared symbol name,
ambiguous names are left unpaired rather than guessed, and each record carries a
`pairing` field of `offset`, `name` or `null` so the two evidence classes are
never confused. With it, all 24 reference methods pair, leaving the expected two
rebuilt-only extras (`property_IODeviceType:length:`, `property_IOSlotName:length:`).

**binrecon's own verdict is `different` for all 24, and that verdict is not
informative here.** Every equality signal it computes is defeated by link
addresses in a way it cannot see through:

- `cfg_equal` is false for all 24 — including the three that are byte-identical
  — because basic blocks are keyed by address.
- `raw_equal` and `masked_equal` hold for only 3 of 24, and masking cannot help:
  a linked `MH_EXECUTE` has its relocations applied and discarded, so **both
  analyses carry zero relocations** and there is nothing to mask. The three that
  do match byte-for-byte are exactly the accessors with no outbound call and no
  absolute data reference — `-[IOPCIDeviceDescription getPCIdevice:function:bus:]`,
  `-[IOPCMCIATuple code]` and `-[IOPCMCIATuple length]`.
- Ghidra and angr paired nothing at all, because their function-name renderings
  differ from IDA's, so no alias is shared. angr also recovers different
  boundaries under scoping, which the scoping design predicted.

**What the published analyses do establish**, read directly rather than through
the comparator: all 24 pairs have **identical instruction counts**, and every
operand difference across all 24 falls into exactly three classes —

1. IDA branch auto-labels (`loc_1FD388` against `loc_20AA38`), which encode the
   absolute address;
2. IDA data auto-labels (`stru_23A7B8.super_class` against
   `stru_25F8DC.super_class`) — same field, same struct, different auto-name;
3. the two `test al, al` against `test eax, eax` in `unmapAttributeMemory`.

So the earlier ad-hoc finding is reproduced from binrecon-published,
three-analyzer-scoped data: **23 of 24 methods are instruction-for-instruction
identical to Apple's modulo link addresses, and Finding 3 is the only semantic
divergence among all 24.**

**No entry earns `assembly-matched` from this run either.** The comparator did
not certify the equality; a script reading its output did. The gap is narrow and
now precisely located: `normalized_operands` canonicalizes registers but not
IDA's address-derived auto-labels, so `loc_*`, `stru_*` and `off_*` defeat it.
Canonicalizing those is what would let binrecon certify this class of
comparison itself.

### Finding 3's cause, fully localised

The same run pins Finding 3 to one line. `unmapAttributeMemory` is the **only**
site among all 24 methods that tests the *result* of a `char`-returning selector
sent to an untyped receiver, at
`src/driverkit-3/libDriver/pcmcia/IOPCMCIADirectDevice.m:141`:

```objc
if ([window memoryInterface] && [window attributeMemory])
```

Its sibling `mapAttributeMemoryTo:findSpace:` messages window objects just as
freely but sends only setters and never tests a return value, which is why it
matches byte-for-byte with `id` locals. One construct, one divergence — the
mechanism confirmed for Findings 1 and 2 above, in its last unfixed instance.

Both selectors are declared `- (char)` in the 82365 driver's
`PCICWindow.h`, which is why the reference tests `al`. Fixing it needs a typed
receiver, and the type is **not** a free choice: Finding 13 of the
Intel82365PCMCIA reconstruction recovered from Apple's driver binary that
`PCICWindow` adopts a `PCMCIAWindow` protocol and `PCICWindow(Attributes)`
adopts `PCMCIAWindowAttributes`. That split matches this call site exactly —
`memoryInterface` is on the main class, `attributeMemory` and
`setAttributeMemory:` on the category — so the receiver's type is
`id <PCMCIAWindow, PCMCIAWindowAttributes>`.

Neither protocol was declared anywhere in `src/`. Both now are.

### The protocols, and the fix

`src/kernel-7/driverkit/i386/PCMCIA.h` was a two-line `// TODO` stub that
`autoconf_i386.m` already imported. It now carries the four protocols an
adapter driver's objects adopt, recovered from the `__OBJC,__protocol` section
of Apple's shipped `PCIC_reloc` — five records, of which four are
`PCMCIAAdapter` (3 methods), `PCMCIASocket` (21), `PCMCIAWindow` (15) and
`PCMCIAWindowAttributes` (16). The fifth is `IOPower`, which DriverKit already
declares in `driverkit/IOPower.h` and which is therefore not repeated.

Every selector and every type came from that section's method-description
lists, so the signatures are Apple's rather than inferred — `c9@8:12c16` for
`- (char)setEnabled:(char)`, `{?=b1b1b1b1b2b1b1}8@8:12` for
`- (PCMCIAStatus)status`, and so on. That last encoding is worth noting: it is
bit-for-bit the `PCMCIAStatus` bitfield already declared for
`statusChangedForSocket:changedStatus:`, which independently confirms that
typedef's layout.

**Declaration order is the reverse of the binary's**, and this was measured
rather than assumed. `PCICWindow`'s own class method list in the same binary
ends with `initWithSocket:memoryWindow:number:` and begins with `set16Bit:`;
reversed, it reads `initWithSocket:…, validSockets, socket, setSocket:,
systemAddress, cardAddress, mapSize, setMapWithSize:…` — getter/setter pairs in
a natural source order. GCC emits these lists in reverse source order, so the
header restores the order Apple wrote.

`PCMCIAStatus` moved from `PCMCIAKernBus.h` into `PCMCIA.h`, which now owns it,
and `PCMCIAKernBus.h` imports it. Both files guard their bodies with
`#ifdef DRIVER_PRIVATE`, so nothing changes about when the typedef is visible.
libDriver compiles with `-DDRIVER_PRIVATE` in `KERN_CFLAGS`, and
`IOPCMCIADirectDevice.m` already imports `PCMCIAKernBus.h`, so the protocols
reach the call site without a new import.

The fix itself is the receiver's type at line 137:

```objc
id <PCMCIAWindow, PCMCIAWindowAttributes>	window;
```

`memoryInterface`, `setEnabled:` and `socket` come from `PCMCIAWindow`;
`attributeMemory` and `setAttributeMemory:` from `PCMCIAWindowAttributes`. The
split is Apple's, and it matches this call site exactly.

**This is a prediction, not yet a measurement.** It asserts that a
protocol-qualified `id <P>` reaches the declared `char` return where a bare `id`
did not — which is the documented purpose of protocol qualification, but the
same class of claim that six builds falsified earlier in this document. It is
confirmed when a rebuilt kernel's `-[IODirectDevice unmapAttributeMemory]`
contains two `84 c0` and no `85 c0`. Until then no ledger entry advances, and
Finding 3 stays `unexamined`.

Because `pb_makefiles` tracks no header dependencies and libDriver reads its
headers from the installed `System.framework` tree, verifying this needs the
kernel headers reinstalled and `pcmcia/*.m` touched before the build — the
omission that produced several of the false negatives recorded above.

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

- **13 methods compared at instruction level on both sides during the report
  pass.** Every method of `IOPCIDirectDevice.m` and `IOPCIDeviceDescription.m`
  that the reference has also existed in the kernel artifact available then, so
  all thirteen were disassembled from both binaries and diffed instruction by
  instruction (see Baseline build above). Ten matched exactly; three carried the
  divergences in Findings 1 and 2.
- **11 methods were compared at control-flow level only during the report and
  fix passes**, because the three PCMCIA modules were absent from the kernel
  artifact then available. For `mapAttributeMemoryTo:findSpace:`,
  `unmapAttributeMemory` and the nine `IOPCMCIADeviceDescription` /
  `IOPCMCIATuple` methods the comparison was the reference's disassembly read
  against our source text: branch structure, constants, struct offsets,
  message-send order and call targets. That is a weaker evidence class and is
  labelled as such throughout this document.
  **That limitation has since been lifted and was never permanent.** All three
  modules are present in the 2026-07-26 11:47 build (see The missing PCMCIA
  modules), so all 24 methods are now comparable on both sides, and a first
  two-sided read of all 24 has been done (see Baseline build). The
  control-flow-only labels below record how the findings were originally
  reached, not what is possible now.
- **0 methods left unexamined.**

Five methods carry a finding and therefore stay `unexamined` in the ledger, per
the convention established by the driver passes: a method known to diverge is
written up here rather than given a status it has not earned. The other nineteen
are `control-flow-confirmed`. None is `assembly-matched`; that requires a
`binrecon compare` parity run against a rebuilt binary, and none has been run.
(Those counts are as of the report pass. The fix pass advanced four of the five;
the verification pass then reset three of those four to `unexamined` when the
build falsified the fix. Twenty are `control-flow-confirmed` today and four are
`unexamined`. See Post-fix parity below.)

Six findings follow. Findings 1 to 3 were believed to share one root cause — two
kernel-side bus headers in our tree are stubs. **That root cause was tested and
disproved.** The mechanism they actually share is a different one and is now
**confirmed by experiment: an untyped `id` receiver at the call site**, which
makes this GCC ignore the declared signature entirely. Typing the receivers
(commit `53f1fc3a`) resolved Findings 1 and 2, whose emitted code now matches
the reference. Finding 3 is the same construct in a module the fix did not
touch, and is now measured rather than predicted. Finding 4 is a source typo
with tooling consequences, Finding 5 is an accepted later-Apple addition,
Finding 6 is accepted dead code.

The headline: **the five modules' own source text is faithful to DR2 down to the
instruction in every place it could be checked.** Every divergence found is
caused by something outside those five files' logic — and what, exactly, is now
answered: the static type of the receiver at four PCI call sites and one PCMCIA
one. The header explanation was the answer this document first gave, and a build
disproved it before a second experiment found the real one.

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

**Resolved: they were a build artifact — stale objects — and they are present
now.** The account below is kept in the order it was learned, because the wrong
answer was recorded here confidently and a reader deserves to see it retracted
rather than removed.

### What was observed, and in which artifact

**Three of the five modules were absent from the kernel artifacts available to
the report, fix and verification passes.** Walking `__OBJC,__module_info` in
both binaries at that time:

| Module | DR2 reference | our kernel, up to the 11:02 build |
| --- | --- | --- |
| `IOPCIDirectDevice.m` | present | present |
| `IOPCIDeviceDescription.m` | present | present |
| `IOPCMCIADirectDevice.m` | present | **absent** |
| `IOPCMCIADeviceDescription.m` | present | **absent** |
| `IOPCMCIATuple.m` | present | **absent** |

The reference declared 78 modules and ours 75, and the difference was exactly
those three: our kernel contained every module the DR2 kernel contains, minus
these, and no extras. Correspondingly our kernel had
`.objc_category_name_IODirectDevice_IOPCIDirectDevice` but no
`.objc_category_name_IODirectDevice_IOPCMCIADirectDevice`.

The sources exist and the build system references them everywhere it should.
`src/driverkit-3/libDriver/Makefile` lists all three in `pcmcia_BUS_MFILES`
(line 133), folds that into `i386_KERN_MFILES` (line 175), and lists `pcmcia` in
`SOURCE_DIRS` (line 46), `BUS_LIST` (line 55) and `KERNEL_DIRS` (line 276).

Candidate causes that were checked and **ruled out** — kept here because, per
the resolution below, they were right to rule out: the wiring really was
correct, and the objects really were simply never compiled:

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

### The superseded account: an upstream Darwin 0.3 omission

This document previously recorded, on the project owner's report, that Apple's
Darwin 0.3 release did not ship these three modules in the *kernel* build — most
likely an oversight on Apple's part — so that the absence was upstream,
permanent, and not a defect to fix here. It added the nuance that the *sources*
were shipped (`git log` confirms all five `.m` files entered this repository at
commit `19ffee9a Original Darwin 0.3 Sources`) and that what Apple had not
shipped was whatever makes the kernel actually link the three objects in. It
concluded that adding PCMCIA to the kernel would be a deliberate feature
decision rather than a repair, and that the eleven one-sided comparisons were a
permanent limitation.

**That account is superseded by measurement.** It was explicitly recorded as the
owner's report plus local observations rather than as something a build had
verified, and a build has now contradicted it.

### The measurement

All three modules are present in the kernel built 2026-07-26 11:47
(`A82940452938737FB8514C334434CEAF70B4DC39179A4047B4153D9B589325C1`, see
Baseline build). Comparing Objective-C metadata between Apple's reference kernel
and ours:

```
reference PCI/PCMCIA methods: 24
ours now:                     26
reference methods MISSING from ours: 0
ours-only: 2   (-[IOPCIDeviceDescription property_IODeviceType:length:],
                -[IOPCIDeviceDescription property_IOSlotName:length:])
```

The two extras are Finding 5's accepted later-Apple additions. Nothing the
reference has is missing.

**Cause: the same staleness that produced every other false signal in this
work.** Those objects had never been compiled, and a forced recompile — `touch`
on the `.m` files under `libDriver/pcmcia` — built and linked them. The build
system's wiring was correct all along, which is why every candidate cause ruled
out above was correctly ruled out.

This is a **third instance of the same class of build-system trap** already
recorded under Build-system facts, learned the hard way: this tree does not
track header dependencies, headers are consumed from an installed copy rather
than the source tree, and objects that were never built are not rebuilt merely
because their sources are listed in the Makefile. All three produce output that
is indistinguishable from a genuine negative result.

### What this changes

- **The eleven one-sided comparisons are no longer a permanent limitation.**
  Two-sided comparison of all 24 methods is possible now and a first pass over
  all 24 has been done (see Baseline build).
- **"Adding PCMCIA to the kernel is a deliberate feature decision, not a
  repair" is wrong.** It builds already; nothing needs adding.
- Finding 3, which was a prediction inside that gap, is now a measurement.

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

**Ours, as originally found**, at the corresponding point in the kernel artifact
then available (`0x20A366`, in the function at `0x20A2F0`):

```
83 F8 01   cmp eax, 1
75 25      jnz ...
```

**Difference:** the reference compared `al`, ours compared the whole of `eax`.
The two functions were otherwise instruction-for-instruction identical — 67
instructions each, same order, same encoding lengths — and this single byte was
the entire size difference between them, 176 bytes in the reference against 177
in ours.

**The divergence was real, survived the header fix, and is now resolved.** It
was re-measured unchanged in the verification build (`DA6E06AE...`) and then
measured *gone* in the receiver-typing build (`A8294045...`, see Baseline
build): `-[IOPCIDeviceDescription(Private) _initWithDelegate:]` now contains
`3c 01` and no `83 f8 01`, and the two functions are 176 bytes on both sides.

**Root cause: confirmed by experiment — an untyped `id` receiver.** The first
cause this document gave was tested and is wrong; both are recorded below,
because the falsification is what makes the confirmation worth believing.

**The falsified account.** This document previously asserted the cause with
confidence, and that assertion was falsified by measurement. What it said:
`src/kernel-7/driverkit/i386/PCIKernBus.h` in our tree was a stub — past the
licence header, one `#import` and four `#define`s of resource-key strings, **no
`@interface PCIKernBus` and no method declarations at all** — so with no
declaration of `isPCIPresent` in scope at `IOPCIDeviceDescription.m:78`, GCC
assumed the message returned `id` and compared 32 bits. The inference drawn from
that was: restore the interface and GCC will emit `cmp al, 1`.

**It does not.** The interface was restored, installed, and the objects
force-recompiled, and the emitted code was byte-identical to before — same
address, same `83 f8 01`. The reasoning that "`cmp eax, 1` proves GCC found no
signature, since it emits `cmp al, 1` whenever it has one" was the load-bearing
step, and it is false in the direction that matters: GCC had the signature and
still emitted `cmp eax, 1`, because the receiver was `id`.

**The confirmed mechanism: untyped receivers.** Both divergent call sites
messaged an untyped receiver:

- `src/driverkit-3/libDriver/pci/IOPCIDeviceDescription.m:70` —
  `id thePCIBus = [KernBus lookupBusInstanceWithName:"PCI" busId:0];`
- `src/driverkit-3/libDriver/pci/IOPCIDirectDevice.m:59` —
  `id thePCIBus = getThePCIBus();`

With an `id` receiver, this vintage of GCC applies no declared method signature
at all: it assumes an `id`-sized return and the default argument promotions no
matter how many visible headers declare the selector. A typed receiver is what
makes the declaration reachable. That accounts for Findings 1 and 2 together and
explains why installing the declarations changed nothing on their own.

**The experiment.** Commit `53f1fc3a` changed `getThePCIBus()` to return
`PCIKernBus *` instead of `id` and typed all seven receiver locals — six in
`IOPCIDirectDevice.m`, one in `IOPCIDeviceDescription.m:70`. Nothing else
changed. In the resulting kernel (`A8294045...`, built 2026-07-26 11:47):

- `_initWithDelegate:` contains `3c 01` and no `83 f8 01`.
- `_initWithDelegate:` **moved to `0x20abc4`**, from the `0x20a2f0` it had held
  unchanged through all six earlier builds. That movement is the strongest
  single signal available here: it shows the object genuinely recompiled
  differently, which is exactly what the four stale builds before it failed to
  do.

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

What is real is the exposure: nothing in the source enforces that
`isPCIPresent`'s upper 24 bits stay zero. The ABI only defines `al` for a
`char`/`BOOL` return, so a conforming implementation is free to leave garbage
above it, and such an implementation would break under `cmp eax, 1`. Today's
callee happens to zero-extend; nothing guarantees the next one will. **That
exposure is now closed**: the compare is `cmp al, 1` in the current build.

**Outcome: fixed by typing the receiver. The header change also stays, on its
own terms.**

`src/kernel-7/driverkit/i386/PCIKernBus.h` carries an `@interface PCIKernBus :
KernBus` declaring the eleven methods the shipped `PCIBus_reloc` metadata
attests, `- (BOOL)isPCIPresent;` among them (commit `99a55c1b`). No ivars are
declared kernel-side; the kernel only messages the object. That edit was
justified at the time as *the fix for this divergence*, and it was not — it
changed no emitted byte. It stays because a header describing a class should
declare the class, the driver-side copy
(`src/drivers-i386/bus/drvPCIBus/PCIBus.drvproj/PCIBus.lksproj/PCIKernBus.h`)
already does, and the declaration is what a typed receiver goes on to consult.
It was necessary and not sufficient.

The fix is commit `53f1fc3a`, which typed `thePCIBus` as `PCIKernBus *` at
`IOPCIDeviceDescription.m:70`. The emitted code now matches the reference on the
checked pattern.

**The ledger entry stays `unexamined`.** `0x1FD514` is not advanced on this
evidence. Advancing an entry on an inference is exactly what went wrong in the
fix pass, and a targeted byte check is not the measured reference-versus-rebuilt
comparison the status requires. Its reason records the confirmed mechanism and
the applied fix; see The ledger correction.

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

**Ours, as originally found**, at the same offset in the kernel artifact then
available (`0x209FB7`):

```
53   push ebx                       ; the full 32-bit int
```

**Difference:** four bytes of narrowing replaced by a one-byte push, in each of
the two class methods. Everything else in both functions matched exactly, same
order and encodings, and this was the whole of the size difference: 178 bytes
against 175, and 180 against 177.

**The divergence was real, survived the header fix, and is now resolved.** All
four `ConfigSpace` methods were re-checked in the verification build
(`DA6E06AE...`) and none of them contained `0f b6 c3`. In the receiver-typing
build (`A8294045...`, see Baseline build) the two class methods
`+getPCIConfigSpace:withDeviceDescription:` and
`+setPCIConfigSpace:withDeviceDescription:` contain `0f b6 c3`, as do
`-getPCIConfigData:atRegister:` and `-setPCIConfigData:atRegister:`, and all
eight `ConfigSpace`/`ConfigData` methods now agree with the reference on where
that narrowing does and does not appear.

**Root cause: confirmed by experiment — the same untyped `id` receiver as
Finding 1.**

The first stated cause was the same stub `PCIKernBus.h` as Finding 1: the
reference's `getRegister:` declares its first parameter as `unsigned char` (the
driver-side header still does, at line 82), so GCC converts the `int address`
loop counter at the call site, and with no declaration in scope our build
applies the default argument promotions and pushes the `int` whole. The
prediction was that declaring the parameters `unsigned char` would produce
`movzx eax, bl`.

**It does not.** The declarations were added, installed and force-recompiled,
and the four methods still pushed the full 32-bit int. The receiver at
`IOPCIDirectDevice.m:59` was an untyped `id`, and this GCC ignores declared
signatures entirely for an `id` receiver, applying default argument promotion
regardless — so the declaration was never reached. Commit `53f1fc3a` typed
`getThePCIBus()`'s return and the six receiver locals in that file as
`PCIKernBus *`, and the narrowing appeared.

Note that `+[IODirectDevice getPCIConfigData:atRegister:withDeviceDescription:]`
does *not* diverge here — both binaries emit `movzx eax, [ebp+var_8]` — because
that method's *own* parameter is declared `(unsigned char)address` in
`driverkit/i386/IOPCIDirectDevice.h`, which our tree does have. The divergence
only appeared where the narrowing has to come from the callee's declaration,
reached through an `id` receiver, which is what the experiment then confirmed.

**Where `0f b6 c3` should and should not appear.** This is easy to get wrong by
counting methods rather than reading them, so it is recorded explicitly. Of the
eight `ConfigSpace`/`ConfigData` methods, exactly four carry `0f b6 c3` in the
reference — `+getPCIConfigSpace:withDeviceDescription:`,
`+setPCIConfigSpace:withDeviceDescription:`, `-getPCIConfigData:atRegister:` and
`-setPCIConfigData:atRegister:` — and our current build carries it in exactly
the same four. The other four do not carry it **in either binary**, for two
different and legitimate reasons: the two instance `ConfigSpace` methods
(`-getPCIConfigSpace:`, `-setPCIConfigSpace:`) are 64-byte forwarding wrappers
with no loop counter to narrow, and the two `+ConfigData:...
withDeviceDescription:` class methods narrow from a stack slot
(`movzx eax, [ebp+var_8]`) rather than from `bl`. So the absence of
`0f b6 c3` from `-[IODirectDevice(IOPCIDirectDevice) setPCIConfigSpace:]` is not
an anomaly and is not an open question: that method is 64 bytes on both sides
and decodes identically modulo link-time addresses.

**Disposition:** fix

**Rationale:** lower severity than Finding 1 and worth saying so. The callee reads
its parameter as `unsigned char` off the stack, i386 is little-endian, and the
loop counter only ever holds 0 to 252, so the byte actually delivered was correct
even before the fix and the behaviour was identical. The reason originally given
for fixing it — that it is the same one-line header change as Finding 1 — turned
out to carry no weight, because that change affected no emitted byte. What the
real fix buys is the thing that was always the point: the compiler now
type-checks these calls, where before it type-checked none of them and a future
argument-order or type error in `getRegister:device:function:bus:data:` would
have passed silently.

**Outcome: fixed by typing the receiver. The header change also stays, on its
own terms.**

`getRegister:` and `setRegister:` declare their first four parameters
`unsigned char` in `src/kernel-7/driverkit/i386/PCIKernBus.h` (commit
`99a55c1b`), matching the reference's `i28@8:12C16C20C24C28^L32` and `...L32`.
Those declarations are correct and stay — they are what the typed receiver now
consults — but on their own they changed nothing. The fix is commit `53f1fc3a`,
typing `getThePCIBus()` and the six receiver locals in `IOPCIDirectDevice.m` as
`PCIKernBus *`.

**Ledger `0x1FD154` and `0x1FD248` stay `unexamined`**, for the same reason
given under Finding 1: they await a measured reference-versus-rebuilt
comparison, not another inference.

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

**Difference — predicted when this was written, and now measured.** The
prediction was that the two `test al, al` byte tests above would come out as
`test eax, eax` word tests in our build, with the same undefined-upper-bits
exposure as Finding 1.

**It is confirmed.** `IOPCMCIADirectDevice.m` is compiled into the kernel built
2026-07-26 11:47 (see The missing PCMCIA modules), so the method could finally
be disassembled on our side. `-[IODirectDevice(IOPCMCIADirectDevice)
unmapAttributeMemory]` sits at `0x20aff8`, is 332 bytes on both sides, and
decodes to the reference's instruction sequence except at exactly two places:
the reference's two `84 c0` (`test al, al`) are `85 c0` (`test eax, eax`) in
ours. Those two instructions are the only operand-level difference across the
whole method, and this is the only one of the 24 methods that still differs.

**The mechanism is the confirmed one, not the disproved one.** The original
explanation — "no declaration in scope, therefore a 32-bit test", borrowed from
Finding 1's stub-header account — was tested against a build and does not hold.
What does hold is the untyped receiver: `window` at
`IOPCMCIADirectDevice.m:138` is an `id`, exactly as `thePCIBus` was, and typing
the PCI receivers is what fixed Findings 1 and 2. This finding is the same
construct in the module that fix did not touch, and it is the one place the
mechanism can still be seen in the current build.

`src/kernel-7/driverkit/i386/PCMCIAKernBus.h` was a stub in exactly the same way
`PCIKernBus.h` was — past the licence header, one `#import`, eight `#define`s,
no `@interface PCMCIAKernBus` and no method declarations at all — and now
carries a real interface (commit `99a55c1b`). As the Outcome below explains,
that does not reach this line, because `memoryInterface` and `attributeMemory`
are not `PCMCIAKernBus` methods.

The rest of the method matches the reference on a control-flow read and is
recorded under "Examined with no divergence found".

**Disposition:** fix

**Rationale:** the consequence is a spurious match, not a missed one. With
`test eax, eax`, dirty bits above `al` make a false `BOOL` read as true, so a
window that is *not* the attribute-memory window could be wrongly treated as one
and torn down, while the real attribute-memory window is walked past unmatched.
Fixing it was originally assumed to be the same header change as Findings 1 and
2 applied to the PCMCIA header; that assumption was wrong, since the header
change did not fix Findings 1 or 2. What did fix them was typing the receiver,
and the equivalent change here needs a kernel-visible type to name — see the
Outcome. Whoever applies it should confirm the result against a build, which is
now cheap: the module compiles, so the byte check is two-sided.

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
kernel-visible window/socket interface is ever added — and it is that class,
used as `window`'s declared type, that the Finding 1/2 mechanism says is needed
here, not a declaration bolted onto `PCMCIAKernBus`. Ledger `0x1FD8C4` stays
`unexamined`, per the convention that a method known to diverge is written up
rather than given a status it has not earned.

The one thing that has changed is the evidence class: this is no longer a
prediction. The module is compiled, the divergence is measured, and it is the
only operand-level difference left across all 24 methods.

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

**The eleven PCMCIA-side methods at control-flow level** — the evidence class
available when this was written; all eleven are now comparable on both sides,
and the two-sided read described under Baseline build found ten of them
identical modulo link-time addresses, with `unmapAttributeMemory` (Finding 3)
the only exception. Branch structure,
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

- **No parity run and no `assembly-matched`.** `control-flow-confirmed` is still
  the ceiling. The two-sided read of all 24 methods described under Baseline
  build was an ad-hoc metadata-walk-plus-capstone check, not a `binrecon
  compare` parity run, so it does not earn any entry a stronger status. Running
  that parity comparison is the next thing a build host should be used for.
- **The cause of Findings 1 and 2 is known: an untyped `id` receiver**, tested
  by typing the receivers (`53f1fc3a`) and confirmed by the resulting build.
  The earlier stub-header explanation was tested and disproved and is retained
  in Finding 1 as superseded. Anyone citing this document should cite the
  receiver mechanism, and should note that the header declarations, while
  correct and retained, changed no emitted byte on their own.
- **Eleven of twenty-four methods were compared at control-flow level only
  during the report and fix passes**, because the three PCMCIA modules were
  absent from the kernel artifacts then available. **That was never permanent
  and no longer applies:** the modules were stale objects, they are present in
  the current build, and all eleven have now been compared on both sides (see
  The missing PCMCIA modules and Baseline build). Finding 3 is a measurement
  rather than a prediction as a result. What remains outstanding is the parity
  run, not the availability of the code.
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
- **The two headers were not audited beyond what these five modules need.**
  `src/kernel-7/driverkit/i386/PCIKernBus.h` and `.../PCMCIAKernBus.h` were
  stubs in their entirety and now carry the interfaces described below. The only
  other importer in the tree is `src/kernel-7/driverkit/i386/autoconf_i386.m`,
  which was not examined.

## The two kernel bus interfaces, as written

The header work behind Findings 1 to 3 is recorded here rather than only in the
commit, because it is the one part of this pass that was not derived from the
kernel reference. It stays in the tree — the declarations are correct, were read
out of Apple's own shipped metadata, and are what a typed receiver consults —
even though on their own they fixed neither Finding 1 nor Finding 2.

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

**No build was performed by the fix pass and no parity run was performed.**
There was no route to a Rhapsody build host at the time, which is the same
reason the report pass could not run one. `binrecon compare` therefore had
nothing to compare: `rebuilt_sha256` stays `null`, no entry is
`assembly-matched`, and no number in this document was estimated to stand in for
one. A build has since been run by the verification pass (see Baseline build);
it was a targeted byte check, not a parity run, so `rebuilt_sha256` is still
`null`.

Every change in the fix pass landed uncompiled. That includes two headers included
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
The fix pass left twenty-three of the twenty-four entries there, with
`-[IODirectDevice unmapAttributeMemory]` at `0x1FD8C4` `unexamined` because
Finding 3 is unfixed. The predicted code changes behind Findings 1 and 2 —
`cmp al, 1` in `_initWithDelegate:`, `movzx eax, bl` before the two config-space
loops — were predictions until a build confirmed them, and confirming them was
named as the first thing a build host should be used for.

### The ledger correction

That is what a build host was used for, and the predictions did not hold. Three
entries had been advanced to `control-flow-confirmed` on the strength of the
prediction alone, and were **reset to `unexamined`**:

| Address | Method | Finding |
| --- | --- | --- |
| 2085204 / `0x1FD154` | `+[IODirectDevice getPCIConfigSpace:withDeviceDescription:]` | 2 |
| 2085448 / `0x1FD248` | `+[IODirectDevice setPCIConfigSpace:withDeviceDescription:]` | 2 |
| 2086164 / `0x1FD514` | `-[IOPCIDeviceDescription(Private) _initWithDelegate:]` | 1 |

The ledger holds 20 `control-flow-confirmed` and 4 `unexamined` across 24
entries. `0x1FDCD4` (Finding 4) keeps `control-flow-confirmed`; that fix was a
source change with no codegen prediction attached to it.

**Those three entries stay `unexamined` after the receiver-typing experiment,
and only their reasons have changed.** The reasons now record that the mechanism
is confirmed — an untyped receiver — that the fix is in commit `53f1fc3a`, and
that the emitted code matches the reference on the checked byte patterns. They
also record what the entries are still waiting for: the measured
reference-versus-rebuilt comparison. Advancing them on the strength of another
inference is precisely what went wrong the last time, and a targeted byte check
plus an ad-hoc disassembly diff is not a parity run. The status will move when
`binrecon compare` moves it.

**This reset could not be made with the `binrecon ledger` CLI.**
`tools/binrecon/binrecon/ledger.py:269` raises `backward ledger transition is
forbidden`: the tool models evidence as only ever strengthening, and has no path
for a measurement that falsifies an earlier inference. The three entries were
therefore edited directly in `ledger.json`, preserving the file's canonical
serialization (`sort_keys`, `(",", ":")` separators, trailing newline) and its
sorted and unique invariants; the result was re-validated with
`binrecon.ledger.validate_ledger` and the source map re-loaded, both clean.
A reader comparing this file against the CLI's rules should know why it does not
look like something the CLI produced. **That limitation is unchanged**, so the
subsequent rewrite of those three entries' reasons was made the same way, by
editing `ledger.json` directly under the same invariants.

### Build-system facts, learned the hard way

Three properties of this build silently produced stale output during this work.
The first two cost four of the six verification builds; the third produced the
false "upstream Darwin 0.3 omission" conclusion recorded above. Anyone testing a
change in this tree should read these first.

- **DriverKit headers are consumed from an installed copy, not from the source
  tree.** The compiler reads
  `/System/Library/Frameworks/System.framework/Versions/B/PrivateHeaders/driverkit/...`,
  so editing `src/kernel-7/driverkit/i386/PCIKernBus.h` has *no effect at all*
  until the header is reinstalled. Verify with
  `grep -c <symbol> /System/Library/Frameworks/System.framework/PrivateHeaders/driverkit/i386/PCIKernBus.h`
  and confirm which file the compiler actually opens with GCC's `-H` include
  trace. Do not assume the source-tree edit is what is being compiled.
- **The build does not track header dependencies.** Updating the installed
  header does not cause dependent objects to rebuild. The `.m` files must be
  force-recompiled — `touch` them, after a `gnumake clean` if there is any
  doubt — or the link will reuse objects compiled against the old header and the
  resulting kernel will look exactly like a genuine negative result.
- **An object that was never built is not built merely because its source is
  listed in the Makefile.** The three PCMCIA modules were correctly wired into
  `pcmcia_BUS_MFILES`, `i386_KERN_MFILES` and `KERNEL_DIRS`, and were still
  absent from every kernel until the `.m` files under `libDriver/pcmcia` were
  `touch`ed. Their absence was read as evidence about what Apple shipped in
  Darwin 0.3 — an upstream, permanent omission — and it was nothing of the kind.
  Verify a module's presence by walking `__OBJC,__module_info` in the linked
  kernel, not by reasoning about the build files.

All three failure modes produce output that is indistinguishable from the thing
being measured: the first two give a kernel byte-identical to the previous one,
which looks exactly like "the change had no effect", and the third gives a
missing module that looks exactly like "this was never meant to be here". Six
builds were needed to reach one trustworthy answer on the first two, and the
third stood as a recorded conclusion until a forced recompile refuted it.
