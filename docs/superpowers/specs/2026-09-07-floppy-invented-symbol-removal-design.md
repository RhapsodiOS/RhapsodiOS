# drvPCFloppy: removing the invented symbol surface

Make `drvPCFloppy` export the same symbol set as Apple's `Floppy_reloc`, and fix
the one live memory-corruption bug found while measuring it. Behaviour is
otherwise unchanged.

This is the first of three pieces. The other two — reconstructing
`FloppyController` and `IOFloppyDrive`, whose internals were invented — get
their own specs and depend on this one landing first.

## 1. Why this exists

An instance-size audit across every driver with a reference binary, run after
two heap overflows in `drvPCMCIABus` were traced to undeclared ivars, found
`drvPCFloppy` diverging in three ways. Two are large and deferred. The third is
a set of twelve symbols we export that Apple does not, plus two Apple exports
that we do not — and, discovered while investigating those, a live corruption
bug.

Comparing `__text` and `__DATA` symbols, filtering out our build's stabs debug
entries:

| Ours only | |
| --- | --- |
| `_appendOperationToQueue`, `_dequeueOperation`, `_queueEmpty` | queue helpers |
| `_densityValues`, `_diskLabelValues`, `_fcOpcodeValues`, `_fdCommandValues`, `_fdIoctlNameValues`, `_fdrValues`, `_midValues` | `IONamedValue` tables |
| `-[IODiskPartitionNEW(Private) isAnyOtherOpen]` | duplicate override |
| `_diskIoReturnValues.126`, `_protocols.82` | function-local statics |

| Reference only | |
| --- | --- |
| `_diskIoReturnValues`, `_protocols` | file-scope globals |
| `_fcUnitNum`, `_ssi_1mb`, `_ssi_2mb`, `_ssi_4mb` | controller and drive state we lack |
| `_Floppy_VERS_NUM`, `_Floppy_VERS_STRING` | build metadata |
| `___clz_tab`, `__udivdi3` | libgcc 64-bit support |

**The name tables are not invented data.** The reference contains every string
they hold — `FDCMD_MOTOR_ON`, `FDCMD_EJECT` and the rest — and in fact contains
no string we lack, sharing all 104 of its strings with ours. What differs is
**linkage**, and it is inverted in both directions: where Apple used file scope
we used function-local, and where Apple used function-local we used file scope.
That inversion is the substance of this piece.

## 2. Scope

Five changes. Success is the symbol comparison converging and the driver
building.

### 2.1 Invert the linkage on eight data objects

**To file scope**, gaining the reference's symbols:

| Object | Now |
| --- | --- |
| `protocols[]` | function-local in `+[IODiskPartitionNEW requiredProtocols]`, `IODiskPartitionNEW.m:48` |
| `diskIoReturnValues[]` | function-local in `IODiskNew.m:308` |

**To function-local**, losing symbols the reference does not export, the seven
name tables:

| Table | Defined at |
| --- | --- |
| `fdCommandValues` | `Geometry.m:228` |
| `densityValues` | `Geometry.m:244` |
| `midValues` | `Geometry.m:258` |
| `fdrValues` | `Geometry.m:192`, with an `extern` at `FloppyDriveInt2.m:17` |
| `fcOpcodeValues` | `FloppyCmds.m:32` *and* `Geometry.m:291` — see below |
| `diskLabelValues` | `IODiskPartitionNEW.m:23` |
| `fdIoctlNameValues` | `Bsd.m:106` |

Two need care:

- **`fdrValues` is shared across three files.** `Geometry.m:192` defines it as a
  non-static global and `FloppyDriveInt2.m:17` declares it `extern`. The
  reference exports no such symbol, so Apple did not share it across
  translation units; each consumer gets its own copy.
- **`fcOpcodeValues` is declared twice under one name, with two different
  types** — `static const IONamedValue fcOpcodeValues[]` at `FloppyCmds.m:32`
  and non-static `unsigned int fcOpcodeValues[]` at `Geometry.m:291`. The
  exported symbol comes from the latter. Resolving this is part of the move.

**Whether each table can actually become function-local is determined per
table during implementation.** A table read by two functions in one file stays
file-static; the symbol disappears only if the move is genuinely available.

### 2.2 Replace the three queue helpers with Mach macros

`queueEmpty`, `dequeueOperation` and `appendOperationToQueue` in `Thread.m` are
open-coded circular doubly-linked-list operations over a `{next, prev}` head,
with links at word offsets 8 and 9 of the operation record. `<kern/queue.h>`
provides these as macros, which inline — which is why the reference exports no
equivalent. The header is not currently used anywhere in this driver.

### 2.3 Delete the duplicate `isAnyOtherOpen`

`IOLogicalDiskNEW.m:126` implements it and the reference has only that one.
`IODiskPartitionNEW.m:978` is an override that walks the same logical-disk
chain. Removing it leaves the inherited implementation, which is what the
reference has.

### 2.4 Add `lastAccess` to `IOFloppyDrive`

This is the live bug. Three sites write and read a 64-bit timestamp through a
raw offset:

```c
FloppyDriveInt.m:669   IOGetTimestamp((unsigned long long *)((char *)self + 0x170));
FloppyDriveInt2.m:588  lastTimeLow  = *(unsigned *)((char *)self + 0x170);
FloppyDriveInt2.m:589  lastTimeHigh = *(unsigned *)((char *)self + 0x174);
```

`0x170` is `lastAccess`, a `Q`, in the reference's `IOFloppyDrive`. In ours it
is `_numHeads` at +368 and `_flags` at +372, so every timestamp write destroys
the head count and the flags word, and every read returns them as a time. The
field is added by name and the three sites use it; Piece C places it at the
reference's offset when it rebuilds the class.

### 2.5 Out of scope

- `FloppyController` and `IOFloppyDrive` reconstruction — Pieces B and C.
- The 82 raw-offset sites in `IOFloppyDisk`'s categories. They are correct as of
  the superclass fix and are a separate cleanup.
- `_fcUnitNum` and `_ssi_1mb`/`_ssi_2mb`/`_ssi_4mb` — controller and drive
  geometry state belonging to Pieces B and C.

## 3. Verification

The symbol comparison that found this is the acceptance test. Filtering our
stabs entries, after the change:

- the `__text` ours-only set goes from **twelve** symbols to zero — the seven
  tables, the three queue helpers, `isAnyOtherOpen`, and
  `_diskIoReturnValues.126`;
- in `__DATA`, `_protocols.82` becomes `_protocols`, matching the reference;
- `_diskIoReturnValues` appears at file scope;
- `_Floppy_VERS_NUM` and `_Floppy_VERS_STRING` remain reference-only, being
  build metadata.

Note that `_protocols` is a `__DATA` symbol and was not among the twelve, which
are all `__text`. Both sections need comparing.

`___clz_tab` and `__udivdi3` are libgcc 64-bit support. It is plausible that
naming `lastAccess` as a 64-bit field is what pulls them in, matching the
reference — worth observing, but not predicted here, since the current code
already performs 64-bit access through the raw pointer.

There is no unit-test framework in this driver. Verification is the metadata
comparison plus a build that completes.

## 4. Risks

**The `fcOpcodeValues` collision may be concealing a live bug.** Two objects of
different types share one name across two files; at least one consumer is
plausibly reading data of the wrong shape today. Renaming is easy. What it
exposes may not be, and belongs in the driver's divergence record rather than
being absorbed silently here.

**The queue macro substitution is the only change that can break the operation
thread.** The open-coded functions treat the head specially — a link pointing
back at the head marks the end of the list. `<kern/queue.h>`'s macros must be
read and confirmed to do the same before the swap, not assumed to.

**Adding `lastAccess` grows `IOFloppyDrive` from 416 to 424**, moving it further
from the reference's 444 in size while fixing the corruption. Accepted: Piece C
rebuilds the class.

## 5. Sequencing

Six changes across four drivers are committed but unbuilt, three of them
altering class inheritance. **This piece should be built and verified before
Pieces B and C begin**, so that those measure against a known-good baseline
instead of compounding unverified changes.
