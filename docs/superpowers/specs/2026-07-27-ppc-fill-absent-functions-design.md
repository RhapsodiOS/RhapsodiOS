# Filling the absent functions in Mesh, 53c96 and Gem

Write the five functions Apple's shipped binaries contain that our sources
lack, and **replace one function whose logic is wrong**.

**Nothing in this spec is compile-verified.** There is no PowerPC toolchain.

## Motivation

Five measurement specs established what sixteen shipped PowerPC drivers contain
and what our tree does not. Most gaps turned out to be renames, build-generated
accessors or compiler runtime. A small number are genuinely absent bodies.

This spec writes the ones that are both genuinely absent and safe to write now.

### What is in scope, and what it costs

| Driver | Function | Size | Kind |
| --- | --- | --- | --- |
| `Gem` | `_mace_crc` | 68 B | **replace — existing logic is wrong** |
| `Gem` | `_crc416` | 100 B | absent |
| `Mesh` | `ResetHardware:reason:` | 76 B | absent |
| `Mesh` | `ResetMESH:reason:` | 348 B | absent |
| `Mesh` | `IssueAbort` | 352 B | absent |
| `Mesh` | `killActiveCommandAndResetBus:reason:` | 92 B | absent |
| `53c96` | `maxTransfer` | 40 B | absent |

**1076 bytes.** The IODisplay spec, the only prior work of this kind, was 772
bytes and hit a blocker partway.

### Gem's two are not a reconstruction

`_crc416` and `_mace_crc` in `drvPPCGem_reloc` are **byte-for-byte identical**
to the same functions in `drvPPCBMac_reloc` and `drvPPCMace_reloc`. Both of
those drivers' *sources* are in the tree, and both were measured against their
own binaries and found to match.

So Gem's two functions are **transcribed from verified in-tree source**
(`BMacEnetPrivate.m:1622` / `:1660`, `MaceEnetPrivate.m:1510` / `:1548`), not
reconstructed from disassembly. That is a materially higher confidence than
anything else in this spec, and §3.1 requires the byte-identity to be
re-confirmed before the transcription is trusted.

### Gem's `_mace_crc` is a correction, not an addition

The network spec found `GemEnetPrivate.m:135` defines `_mace_crc` under the
right name with a **different algorithm** — a byte-wise CRC-32 with polynomial
`0xEDB88320`, where Apple's is `crc416`-based with `0x04C11DB7`. They are not
equivalent. Measured on five MAC addresses under big-endian halfword reads:

```
01:00:5E:00:00:01   apple hash 31   ours hash 54
33:33:00:00:00:01   apple hash 62   ours hash 23
FF:FF:FF:FF:FF:FF   apple hash 63   ours hash 47
00:00:00:00:00:00   apple hash 14   ours hash 19
01:23:45:67:89:AB   apple hash 41   ours hash 18
```

**0 of 5 agree.** The hash indexes the multicast filter — `_mace_crc` is called
from `_addToHashTableMask:` / `_removeFromHashTableMask:`
(`GemEnetPrivate.m:1071`, `:1110`), reached from `GemEnet.m:445` / `:463`, and
`_updateGemHashTableMask` (`:1049-1053`) writes the result into the GMAC hash
registers. Our driver programs the wrong bucket, so it drops multicast frames
it should accept.

This is the only change in the series with a demonstrated runtime consequence.

### 1.3 Out of scope, and why

- **`drvPPCATA`'s `calcIdeConfigWord:` (664 B) and `setTransferRate:` (36 B).**
  `calcIdeConfigWord:` is the largest absent function anywhere in the series,
  and `drvPPCATA` is the driver whose two source directories carry
  **conflicting revisions of `ata_extern.h`** — `kControllerTypeCmd646X` is
  `0x04` in one and `0x01` in the other. A function computing an IDE config
  word is precisely the kind that reads those constants. Writing it before the
  header conflict is settled risks encoding the wrong revision, undetectably.
- **`+[PPCBurgundy probe:]`.** It sits at address `0` with no IDA function
  entry — the same case that made `+[IOSmartDisplay probe:]` unmappable and
  `+[AppleOHare probe:]` appear as a phantom gap. There is no function body to
  transcribe.
- **`__udivdi3` / `__divdi3`.** libgcc compiler runtime, not driver source.
  They must **not** be written.
- **Any build, or any claim of buildability.**

## 2. Design

### 2.1 Both copies stay identical

`Mesh` and `53c96` each exist twice: the `src/kernel-7/bsd/dev/ppc/` original
and the `src/drivers-ppc/` copy created by the packaging spec. **Every change
goes into both**, so `tools/ppc_package_check.py` continues to report no
divergences.

| Function | Files |
| --- | --- |
| Mesh's four | `src/kernel-7/bsd/dev/ppc/drvAppleMesh_SCSI/MESH_DBDMA.m` **and** `src/drivers-ppc/scsi/drvPPCMesh/PPCMesh.drvproj/PPCMesh.lksproj/MESH_DBDMA.m` |
| `maxTransfer` | `src/kernel-7/bsd/dev/ppc/drvApple96_SCSI/Apple96SCSI.m` **and** its `src/drivers-ppc/scsi/drvPPC53c96/…` copy |
| Gem's two | `src/drivers-ppc/network/drvPPCGem/GemEnet.drvproj/GemEnet.lksproj/GemEnetPrivate.m` only — Gem has no kernel-7 origin |

The check is the acceptance test for this: §4 item 6.

### 2.2 Style

Each function goes into the file that already holds its class or category,
matching that file's existing style — brace placement, type spellings, comment
idiom. These are Apple's files; new code must not stand out by formatting.

## 3. Method

### 3.1 Gem: confirm identity, then transcribe

Before transcribing, **re-confirm** that Gem's `_crc416` and `_mace_crc` are
byte-identical to BMac's and Mace's, by comparing the instruction bytes from
the published analyses. If they are not identical, the transcription premise
fails and the work becomes a reconstruction — stop and say so.

Then transcribe both from the verified in-tree source, replacing Gem's existing
wrong `_mace_crc` in place. Record which source file was transcribed from.

### 3.2 Mesh and 53c96: write from disassembly

Each from its own listing. The disciplines the IODisplay spec established and
that its review confirmed are worth having:

- **Settle every method signature from the binary's `__OBJC,__meth_var_types`
  encodings**, not by inferring from instructions. That is what caught
  IODisplay's by-pointer/by-value distinction.
- **Resolve every `bl` to an unnamed `sub_XXXX` through `read_macho`'s
  relocation table.** They are jump islands; IDA's export does not carry the
  target.
- **Account for every instruction and every branch in writing.** A branch with
  no counterpart in the source is a missed case or a misreading.
- **Trace every bare constant to a named constant in this tree before writing
  it as one.** `IO_R_INVALID_ARG` was found this way in the IODisplay spec, and
  the SCSITape spec's observation that every unknown constant was defined
  somewhere in this tree has held twice.
- **Read ivar names and offsets from `__OBJC,__instance_vars`**, not from our
  headers. That is what exposed IODisplay's class-hierarchy divergence.

### 3.3 Check the hierarchy before writing any ivar access

IODisplay's reconstruction was blocked because our `IOSmartDisplay` derives
from `Object` while Apple's derives from `IODevice`, giving Apple's class ~260
bytes of ivars ours does not have.

**Before writing any function that reads an ivar, compare the shipped class's
`super_class` and `instance_size` against our source.** `maxTransfer` reads
`+0x268` and Mesh's methods may read others. If the layouts disagree, the
affected function is **not writable** and is recorded as such, exactly as
`findADBDisplayInfoForType:` was.

### 3.4 Uncertainty is recorded, not resolved by guessing

A confident guess is a defect; a recorded uncertainty is a result.

## 4. Acceptance

1. Gem's `_crc416` and `_mace_crc` are byte-identity-confirmed against BMac and
   Mace, transcribed from the named in-tree source, and Gem's previous
   `_mace_crc` is gone.
2. The five absent functions exist, or are recorded as not writable per §3.3
   with the evidence.
3. For every function written from disassembly, a written account maps **every
   instruction** to the source producing it, including every branch.
4. Every constant is a named constant found in this tree, or a literal with a
   comment recording that no name was found.
5. Source maps regenerated for Mesh, 53c96 and Gem. **Mesh's unmapped drops
   from 6 to 2** and **53c96's from 3 to 2**, leaving only build-generated
   accessors. Gem stays at 2 — its two are C functions, outside
   `--scope-to-objc`. All three still reconcile.
6. `tools/ppc_package_check.py` reports **no divergences** — proving both
   copies of every changed file stayed identical.
7. binrecon suite green at **845 passed, 4 skipped**.
8. Every uncertainty is listed in the affected driver's `findings.md`, and the
   Gem multicast correction is recorded there with its measured consequence.

**Not claimed:** that any of this compiles, links, loads or is behaviourally
correct. Item 5 proves the *selectors* match; it does not prove the *bodies*
do. The one exception is Gem's pair, which is transcribed from source already
verified to match its own binaries — a stronger claim, but still not a compiled
one.

### 4.1 The likeliest failure

For Mesh's two large methods (348 B and 352 B, the biggest written in the
series), a plausible body that quietly drops a branch. For Gem, transcribing
from the wrong donor or leaving the old `_mace_crc` behind. Items 1 and 3 exist
for exactly those.

## 5. Follow-on work

- **`drvPPCATA`'s two functions**, after the `ata_extern.h` conflict is settled
  — which itself needs establishing which revision the shipped binary compiled
  against, answerable from the binary.
- **`findADBDisplayInfoForType:`**, blocked on IODisplay's hierarchy divergence.
- **A PowerPC toolchain**, which would make every "not claimed" above
  checkable. After two reconstruction specs, this is the clearest gap in the
  whole effort.
