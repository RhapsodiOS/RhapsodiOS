# i386 bus drivers: reconstruction status

Findings from comparing our sources against Apple's shipped `*_reloc` binaries
with `tools/binrecon`, plus a direct read of the `__OBJC` metadata in both.

Three buses, five drivers, and one kernel-side support layer:

| Bus | Bus driver | Sub-driver |
| --- | --- | --- |
| EISA / ISA PnP | `drvEISABus` | — |
| PCI | `drvPCIBus` | `Intel824X0PCI` (host-bridge chipset) |
| PCMCIA | `drvPCMCIABus` | `Intel82365PCMCIA` (PCIC adapter) |

Underneath all three sits `src/driverkit-3/libDriver`, whose PCI and PCMCIA
modules link into the kernel and provide the `IODirectDevice` categories and
device-description classes the bus drivers talk to.

The headline is that these five are not five partial reconstructions at the same
stage. Two — `drvPCMCIABus` and `Intel82365PCMCIA` — have a class surface
byte-identical to the reference and carry a built artifact proving it. Two more
are substantially reconstructed but their fixes have **never been compiled**.
`drvEISABus` is the outlier: it is the largest of the five, 152 of its 164
functions have never been opened, and it is recorded as crashing.

## Class surface, measured against each reference

The strongest signal available without a fresh build, because it catches defects
instruction-level comparison cannot see. Every class shared with the reference,
compared on superclass, `instance_size`, and each ivar's offset and type
encoding:

| Driver | Shared classes | Wrong superclass | Size mismatch | Offset/type diffs |
| --- | --- | --- | --- | --- |
| `drvEISABus` | 18 | 0 | 1 | 8 |
| `drvPCIBus` | 4 | 1 | 1 | 2 |
| `drvPCMCIABus` | 39 | 0 | **0** | 3 (all benign) |
| `Intel824X0PCI` | 3 | 0 | **0** | **0** |
| `Intel82365PCMCIA` | 6 | 0 | **0** | **0** |

Protocol records are **identical in all five** — same count, same names, same
order. Category record counts match in all five as well.

### The four real defects

**`drvPCIBus` — `PCIResourceDriver` inherits the wrong class.** The reference
gives it `IODirectDevice` at 812 bytes; the built artifact has `IODevice` at 780.
The 32-byte gap is exactly the difference between the two base classes. Fixed in
source by `75c3ef2b9` (09-06) but **not yet compiled** — a rebuild should land at
812 with the superclass corrected.

**`drvEISABus` — `EISAKernBus` declares state Apple's does not.** The reference
is 16 bytes with **zero ivars**; ours is 28 bytes with three (`_eisaData`,
`_slotCount`, `_initialized`). Over-declaration is the safe direction — we
allocate more than we use, so nothing overflows — but Apple kept this state
somewhere else, and the divergence is unresolved.

**`drvEISABus` — `EISAKernBusInterrupt` carries an extra ivar.** Five where the
reference has four; `_irqEnabled` at offset 57 fits inside existing padding, so
`instance_size` still agrees at 60. This sits with Finding 5 in that driver's
`divergences.md`, which records the class as having no IRQ registration,
trigger-mode setup or dispatch trampoline at all.

**`drvEISABus` — `PnPBios` permutes three saved-GDT slots.** The reference orders
them `saveGDTBiosCode`, `saveGDTBiosData`, `saveGDTBiosEntry`, `saveGDTKData` at
offsets 80/88/96/104; ours is `BiosCode`, `BiosEntry`, `KData`, `BiosData`. Total
size agrees. Whether this is a functional defect or merely a self-consistent
relabelling **was not audited here**; it sits next to Finding 2, which already
disposes the GDT lifecycle as `fix`.

### What is cosmetic

Most of the remaining ivar differences are not defects:

- **Underscore prefixes.** We name ivars `_foo` where the reference names them
  `foo`, throughout. Recorded, deliberately not changed.
- **Equivalent encodings.** `L` versus `I` (both 32-bit on i386), `[80C]` versus
  `[80c]`, `(?)` versus `[2I]` for the GDT slot pairs.
- **Equivalent aggregates.** `PCMCIAKernBus`'s `busRange` struct versus our two
  `unsigned int`s at the same offsets; `PCMCIAid`'s `[5*]` array versus our five
  separate `char *`. Same bytes, same layout, different spelling.

Symbol-set deltas are similarly quiet: each reference has only 2–10 symbols our
builds lack, and nearly all are build glue (`_<Name>_VERS_NUM`,
`_<Name>_VERS_STRING`) or compiler-emitted statics (`_xxx.86`, `_init.117`,
`_protocols.96`). Our unstripped builds carry thousands of extra stabs entries;
that is expected and is not a finding.

## Parity ledgers

`ledger.json` per driver. Statuses are forward-only, and `assembly-matched`
requires instruction-level evidence from a *rebuilt* binary — a source-only fix
pass cannot exceed `control-flow-confirmed`.

| Driver | Entries | assembly-matched | control-flow | unexamined | intentional | Bound to artifact |
| --- | --- | --- | --- | --- | --- | --- |
| `drvEISABus` | 164 | 3 | 9 | **152** | 0 | no |
| `drvPCIBus` | 29 | 16 | 8 | 3 | 2 | no |
| `drvPCMCIABus` | 84 | 29 | 34 | 19 | 2 | no |
| `Intel824X0PCI` | 4 | 0 | 2 | 0 | 2 | no |
| `Intel82365PCMCIA` | 82 | 0 | 76 | 0 | 6 | no |
| `libDriver` (kernel) | 24 | **24** | 0 | 0 | 0 | **yes** |

Only the kernel-side ledger has `rebuilt_sha256` set. For the five drivers,
nothing pins those statuses to a specific binary, so a stale or unrelated
artifact would inherit them silently. Binding them is cheap and worth doing on
the next build.

`Intel82365PCMCIA` is the clearest case of a ledger lagging reality: its 76
`control-flow-confirmed` entries were capped there because the fix pass had no
build host, but a build has since been produced (07-26 23:26). Those entries are
now promotable on evidence that already exists.

## Findings and dispositions

| Driver | Findings | fix | accept | `divergences.md` |
| --- | --- | --- | --- | --- |
| `drvEISABus` | 6 | 4 | 2 | 627 lines |
| `drvPCIBus` | 7 | 4 | 3 | 454 lines |
| `drvPCMCIABus` | 6 | 2 | 4 | 535 lines |
| `Intel824X0PCI` | 10 | 9 | 1 | 916 lines |
| `Intel82365PCMCIA` | 18 | 17 | 1 | 2116 lines |
| `libDriver` | 6 | 4 | 2 | 1479 lines |

Every `fix` disposition has been applied in source. What varies is whether the
result was ever compiled.

## Build currency — three of five are stale

Comparing the last commit that touched **code** (not documentation) against the
staged artifact each measurement above was taken from:

| Driver | Last code commit | Artifact | Verdict |
| --- | --- | --- | --- |
| `drvEISABus` | `42d30750e` 07-26 00:11 | 07-25 23:11 | **stale** |
| `drvPCIBus` | `75c3ef2b9` 09-06 22:35 | 07-25 13:44 | **stale** |
| `drvPCMCIABus` | `37b9274e5` 07-27 00:44 | 07-27 00:46 | current |
| `Intel824X0PCI` | `a646c3a8b` 07-25 15:06 | 07-25 13:19 | **stale** |
| `Intel82365PCMCIA` | `be3934511` 07-26 17:23 | 07-26 23:26 | current |

`drvPCIBus` is the most consequential: its artifact predates the superclass fix
by six weeks, which is why the measurement above still shows `IODevice`.

`Intel824X0PCI` has never had a verifying build at all. Its ten findings
rewrote nine `__cstring` entries to match the reference character for character,
and none of that is compile-checked — including whether
`-[Intel824X0 initFromDeviceDescription:]` still fits the reference's 459 bytes.

## Per-bus notes

### PCI

`drvPCIBus` is small (29 functions) and well understood: 16 `assembly-matched`,
seven findings, four fixed. Three of its seven findings were **accepted** rather
than fixed — `test_M2`, `isPCIPresent` and the config-register accessor differ
from the reference in ways the write-ups justify. Its one structural defect is
the superclass, fixed and awaiting a build.

`Intel824X0PCI` is 548 bytes of `__TEXT,__text` — four functions, all read at
instruction level. Its class surface is already **perfect**: three classes, zero
differences of any kind. Its problem is entirely in string data and device-ID
attribution, and entirely unbuilt.

### PCMCIA

The most complete of the three buses.

`drvPCMCIABus` has 39 classes matching the reference on superclass,
`instance_size` and ivar layout **exactly** — the three remaining offset/type
entries are the benign aggregate spellings described above. Its Finding 1 (five
functions called but never defined, rated "severe — driver cannot load") is
genuinely resolved: `_stringForFunctionID`, `_configTableLookupServerAttribute`,
`_parsePrefix`, `_parsenum` and `_LookForPCMCIAID` are all present in source and
in the built artifact. Two heap overflows from undeclared ivars were fixed in the
same effort.

One minor unresolved item: the reference defines five file-static data objects
(`_parseIDTable`, `_parseTable` in `__DATA,__data`; `_driverConfigTables`,
`_busInstances`, `_defaultConfigEntry` in `__DATA,__bss`) with no same-named
counterpart in our build. Two of those names do exist as statics in our source
(`PCMCIAKernBus.m:56`, `PCMCIAKernBusParsing.m:43`). This is a static-storage
naming or structural difference, not missing code, and it is unaudited.

`Intel82365PCMCIA` went from 13 missing symbols at baseline to **13 of 13
present** in the current build — including the entire `PCIC_PCI` class, the
window-programming routines `_setWindow`, `_setMemoryWindow`, `_setIoWindow`, and
`_socketIsValid`. Its five protocol records and four adoptions are byte-identical
to the reference, as are all six class layouts.

### EISA

`drvEISABus` is where the remaining work is. 164 ledger entries — more than the
other four combined — of which **152 have never been opened**. Only three are
`assembly-matched`. The pass that produced its findings followed a priority list
(`PnPBios.m`, `eisa.c`, the PnP paths, port I/O) rather than attempting uniform
coverage.

Its central finding is that the PnP BIOS real-mode/PM16 calling apparatus is
reconstructed on the wrong model: fixed 8-word argument marshalling where the
reference marshals per-call variable-length arguments, permanent GDT installation
where the reference borrows and restores per call, and no interrupt disabling
around the mode transition. Three of those four are disposed `fix`.

`src/drivers-i386/README` records this driver as crashing. Nothing in the static
comparison contradicts that.

## The kernel boundary

`src/driverkit-3/libDriver`'s 24 PCI/PCMCIA methods are **24 of 24
`assembly-matched`**, verified two independent ways (binrecon's published IDA
analyses, and a raw capstone disassembly diff), with the ledger bound to
`out/i386/mach_kernel` SHA-256 `797b9887…`. That build (07-26 18:37) postdates
every change to the five PCI/PCMCIA modules, so the binding describes current
source.

That result deserves one caveat its own write-up makes: these five `.m` files are
**Apple's own Darwin 0.3 sources**, entering the tree in a single import commit.
Comparing them against a DR2 binary measures Apple against Apple. A high match
rate is the expected outcome, not evidence of good reconstruction. The useful
output was the six findings where they genuinely differ.

Two signatures across the kernel/driver boundary once diverged. Both are now
reconciled in source:

| Method | Reference | Now |
| --- | --- | --- |
| `-[PCIKernBus testIDs:dev:fun:bus:]` | `(const char *)` + three `unsigned char` | matches (`PCIKernBus.h:94`) |
| `-[PCMCIAKernBus statusChangedForSocket:changedStatus:]` | `PCMCIAStatus` bitfield | matches (`PCMCIAKernBus.h:60`) |

The `testIDs:` fix also deleted three call-site casts that existed only to
satisfy the wrong prototype. `maxBusNum` / `maxDevNum` differ in signedness only,
which is ABI-identical and needs no follow-up.

`PCMCIA.h` — which declares `PCMCIAStatus` and the four PCMCIA protocols — is
**duplicated** at `src/kernel-7/driverkit/i386/` and
`src/driverkit-3/driverkit/i386/`. The two are currently byte-identical (md5
`56df959e…`) and each carries a note naming the other. Driver builds consume the
`driverkit-3` copy; editing only the kernel copy silently changes nothing, which
has caused a wrong diagnosis before.

## Reproducing

Profiles: `tools/binrecon/profiles/{eisabus,pcibus,pcmciabus,intel824x0,intel82365pcmcia,kernel-driverkit}.json`.
Per-driver records live in `src/drivers-i386/bus/<Name>/reconstruction/` and
`src/driverkit-3/libDriver/reconstruction/` — `ledger.json`, `source-map.json`,
`divergences.md`, and for the two PCI/PCMCIA bus drivers a `signatures.md`
covering the `__OBJC` metadata their function-level pass does not.

## What is not established

None of these drivers has been tested on hardware or under emulation. A
byte-identical driver is not a working one, and three of the five have not even
been compiled since their fixes landed. The immediate next step is a build of
`drvPCIBus`, `drvEISABus` and `Intel824X0PCI`, which would verify nineteen
applied findings at once and let four ledgers be bound to real artifacts.

One record is known stale: `src/drivers-i386/README:6` says `drvPCIBus`'s
`testIDs:dev:fun:bus:` prototype is "not yet reconciled". It was reconciled; the
header now carries Apple's signature.
