# drvPCParallel instruction-stream baseline

Phase 1 snapshot after Tasks 1–3. No reloc shape edits. IDA 9.2 comparison
against Apple's `ParallelPort_reloc`. Measured 2026-09-16.

## Reloc hashes

| Artifact | Size | SHA-256 |
|---|---:|---|
| Reference | 45312 | `D188A4D909005683B0C943C84CD99514C14A84AD1D378425B3B1DB343F1EAAA2` |
| Rebuilt | 165552 | `FA106F9173FC78D431579AA8CCD458C8FF2FC35B2AA5036F8FDD42B6DBB51D56` |

`binrecon validate` printed the reference sha256 above. Rebuilt is the unstripped
guest `kl_ld` image. `IOParallelPort` `instance_size` is **404** on both
(`__OBJC,__class` word 5). `parity_check.py`: `missing_strings (0):`,
`missing_symbols (0):`. Extra symbols on our side are STABS / unstripped noise.

## Sections and VERS

| Section | Reference | Rebuilt |
|---|---:|---:|
| `__TEXT,__text` | 7416 | 7120 |
| `__TEXT,__cstring` | 476 | 476 |
| `__TEXT,__const` | 170 | **absent** |
| `__OBJC,__instance_vars` | 328 | 328 |

Reference `__TEXT,__const` holds `_ParallelPort_VERS_STRING` and
`_ParallelPort_VERS_NUM`. The rebuilt reloc has neither symbol and no
`__const` section. `PCParallelPort.lksproj/Makefile.postamble` contains
`OTHER_GENERATED_OFILES += $(VERS_OFILE)`, but `VERS_OFILE` is empty: the
guest `kernelserver.make` link line is `IOParallelPort.o IOParallelPortKern.o
ParallelPort_instance.o` only. Task 3's line is present; it did not emit
version objects.

## Guest build

Specified harness (`sh /build/source/vm/build-i386-input-recon.sh drvPCParallel`)
failed before a reloc:

```
gnumake[1]: *** No rule to make target `prebuild'.  Stop.
make exit=2
gnumake: *** [prebuild@PostLoad.tproj] Error 2
FAILED: no ParallelPort_reloc for ParallelPort
```

Task 2 restored `TOOLS = PCParallelPort.lksproj PostLoad.tproj PreLoad.tproj`.
Those tproj Makefiles are handwritten Unix tools (`all` / `install` / `clean`),
not Project Builder `tool.make` projects, so `driver.make` dies at
`prebuild@PostLoad.tproj`. Reloc came from `gnumake` inside
`PCParallelPort.lksproj` (`kernelserver.make`, exit 0), then staged to
`/build/out/i386/drvPCParallel/ParallelPort.config/`. Staging log:

```
=== input-recon done fail=0 built: drvPCParallel ===
```

`ld: warning /usr/lib/libcc.a ... ppc ... i386` (can't load from it) on both
the drvproj-level and lksproj-level links; the i386 preload reloc still wrote.

## Tools

| File | Staged | Size | Type |
|---|---|---:|---|
| `InstallPPDev` | no | — | PreLoad `gnumake` failed: `IODeviceMaster.m` `illegal expression, found unsigned` (lines 138, 1161, 1184, 1207). Not a missing-crt link yet. |
| `RemovePPDev` | yes | 17568 | Mach-O executable **ppc** (`MH_MAGIC` `feedface`, cputype 18), not i386. Host `cc` without `-arch i386`. |

Do not open tool bodies. Phase 3 / Task 10 converts both tproj trees to
`tool.make`.

## `--list` counts (IDA)

`binrecon analyze --profile tools/binrecon/profiles/parallelport.json` with
angr enabled dies during rebuilt consensus:

`relocation 0 overlaps an instruction but is undeclared`

(angr rebuilt, reloc 0 at address 9, `i386-vanilla-32-absolute` →
`__OBJC,__message_refs`). IDA both sides normalize (75 functions each).
This snapshot is **IDA-only**. Analyze exit 1 with
`normalized-functions=FAIL` is expected. Published:
`analysis-reference-ida.json`, `analysis-rebuilt-ida.json`,
`comparison-ida.json`.

| Class | Count |
|---|---:|
| identical (`raw_equal`) | 36 |
| `masked_equal` (not raw) | 14 |
| differing (neither) | 23 |
| unpaired | 4 |
| **total** | **77** |

Summary line from `--list`:

```
77 functions: 36 byte-identical, 37 differing, 4 unpaired
```

The summary's "differing" includes the 14 `masked-eq` rows.

Unpaired:

| Status | Name |
|---|---|
| missing-reference | `-[IOParallelPort autofeedOutput]` |
| missing-rebuilt | `-[IOParallelPort minPhys]` |
| missing-reference | `-[IOParallelPort setControlRegister:]` |
| missing-rebuilt | `-[IOParallelPort setInUse:]` |

The comparison also name-pairs reference `autofeedOutput` with rebuilt
`minPhys`, and reference `setControlRegister:` with rebuilt `setInUse:`.
Those paired rows are identical instruction streams (ivar getter at `+14Ch`,
ivar setter at `+13Ch`); the leftover unpaired names are the swapped
accessors.

## 18 `control-flow-confirmed` plus three reopened

Ledger still has 50 `assembly-matched` / 18 `control-flow-confirmed` / 7
`intentional-mismatch`. `--list` against this reloc:

| Ledger | Name | `--list` |
|---|---|---|
| CFC | `-[IOParallelPort _waitForDevice:isReady:]` | differing 17 |
| CFC | `-[IOParallelPort initFromDeviceDescription:]` | differing 201 |
| CFC | `-[IOParallelPort free]` | masked-eq 4 |
| CFC | `-[IOParallelPort getIntValues:forParameter:count:]` | masked-eq 5 |
| CFC | `-[IOParallelPort setMinPhys:]` | masked-eq 1 |
| CFC | `-[IOParallelPort setBlockSize:]` | masked-eq 1 |
| CFC | `-[IOParallelPort writeToPort]` | differing 27 |
| CFC | `-[IOParallelPort msgTypeToIOReturn:]` | differing 4 |
| CFC | `-[IOParallelPort cmdBufAlloc]` | differing 11 |
| CFC | `-[IOParallelPort cmdBufExec:]` | differing 6 |
| CFC | `-[IOParallelPort waitForCmdBuf]` | differing 13 |
| CFC | `_IOParallelPortThread` | differing 210 |
| CFC | `_IOParallelPortInterruptHandler` | differing 61 |
| CFC | `_ppopen` | differing 22 |
| CFC | `_ppread` | masked-eq 2 |
| CFC | `_ppwrite` | differing 112 |
| CFC | `_ppstrategy` | differing 83 |
| CFC | `_ppioctl` | differing 163 |
| reopened (`intentional-mismatch`) | `-[IOParallelPort initDevice]` | differing 62 |
| reopened (`intentional-mismatch`) | `-[IOParallelPort probeForController]` | differing 24 |
| reopened (`intentional-mismatch`) | `__strobeChar` | differing 70 |

`--list` spells the strobe helper `__strobeChar`. Four CFC rows are already
`masked_equal` (`free`, `getIntValues:forParameter:count:`, `setMinPhys:`,
`setBlockSize:`) plus `_ppread`.

## Are the cheapest differing rows source-shaped?

No. The cheapest unmasked `different` rows are already compiler-shaped or
name-pairing:

- `autofeedOutput` / `setControlRegister:` vs `minPhys` / `setInUse:` —
  identical accessor bodies, swapped names.
- `controlRegisterContents` / `statusRegisterContents` — reference keeps the
  `in al, dx` result in `[ebp+var_1]` (`sub esp, 4`); rebuilt leaves it in
  `eax`. Stack slot, not a source constant.
- `+[IOParallelPort probe:]` — `jz` / `mov eax,1` / `xor eax,eax` vs
  `setnz` / `and eax, 0FFh`. BOOL materialization.
- `isInitialized` — same BOOL pattern (`jnz`/`mov eax,1` vs `xor edx` /
  `jz` / `inc edx`).

Source-shaped signal starts at `msgTypeToIOReturn:` (jump-table slot values
`0xFFFFFD1E` / `0xFFFFFD2B` swapped). Later CFC rows (`cmdBuf*`,
`writeToPort`, the `_pp*` entry points) remain the grind set. Do not grind
the accessor pairing or the inb stack-slot leftovers.

## Full `--list`

```
  diff    ref    new  flags       name

     0      6      6  masked-eq   +[ParallelPortKernelServerInstance kernelServerInstance]
     0      6      6  identical   +[ParallelPortVersion driverKitVersionForParallelPort]
     0      7      7  identical   -[IOParallelPort IOThreadDelay]
     0      7      7  identical   -[IOParallelPort blockSize]
     0      7      7  identical   -[IOParallelPort busyMaxRetries]
     0      7      7  identical   -[IOParallelPort busyRetryInterval]
     0     19     19  masked-eq   -[IOParallelPort cmdBufComplete:]
     0     16     16  masked-eq   -[IOParallelPort cmdBufFree:]
     0      7      7  identical   -[IOParallelPort configRegister]
     0      7      7  identical   -[IOParallelPort controlRegisterDefaults]
     0      7      7  identical   -[IOParallelPort controlRegister]
     0      7      7  identical   -[IOParallelPort dataBuffer]
     0      7      7  identical   -[IOParallelPort dataRegister]
     0     16     16  masked-eq   -[IOParallelPort getHandler:level:argument:forInterrupt:]
     0      7      7  identical   -[IOParallelPort intHandlerDelay]
     0      7      7  identical   -[IOParallelPort interruptMessage]
     0      7      7  identical   -[IOParallelPort ioTimeout]
     0      7      7  identical   -[IOParallelPort isInUse]
     0     14     14  masked-eq   -[IOParallelPort lockSize]
     0      7      7  identical   -[IOParallelPort majorDevNum]
     0      7      7  identical   -[IOParallelPort minorDevNum]
     0      7      7  identical   -[IOParallelPort physbuf]
     0      6      6  identical   -[IOParallelPort readFromPort]
     0      8      8  identical   -[IOParallelPort setAutofeedOutput:]
     0      8      8  identical   -[IOParallelPort setBusyMaxRetries:]
     0      8      8  identical   -[IOParallelPort setBusyRetryInterval:]
     0      8      8  identical   -[IOParallelPort setConfigRegister:]
     0      8      8  identical   -[IOParallelPort setDataRegister:]
     0      8      8  identical   -[IOParallelPort setIOThreadDelay:]
     0      8      8  identical   -[IOParallelPort setIntHandlerDelay:]
     0      8      8  identical   -[IOParallelPort setInterruptMessage:]
     0      8      8  identical   -[IOParallelPort setIoTimeout:]
     0      8      8  identical   -[IOParallelPort setMajorDevNum:]
     0      8      8  identical   -[IOParallelPort setMinorDevNum:]
     0      8      8  identical   -[IOParallelPort setPhysbuf:]
     0      8      8  identical   -[IOParallelPort setStatusRegister:]
     0      8      8  identical   -[IOParallelPort setStatusWord:]
     0      8      8  identical   -[IOParallelPort setWaitForever:]
     0      7      7  identical   -[IOParallelPort statusRegister]
     0      7      7  identical   -[IOParallelPort statusWord]
     0     14     14  masked-eq   -[IOParallelPort unlockSize]
     0      7      7  identical   -[IOParallelPort waitForever]
     0     14     14  masked-eq   _ppclose
     1     29     29  masked-eq   -[IOParallelPort attachInterruptPort]
     1      7      7              -[IOParallelPort autofeedOutput]
     1     34     34  masked-eq   -[IOParallelPort setBlockSize:]
     1     34     34  masked-eq   -[IOParallelPort setMinPhys:]
     1     18     18  masked-eq   _ppminphys
     2     11      9              -[IOParallelPort controlRegisterContents]
     2      8      8              -[IOParallelPort setControlRegister:]
     2     11      9              -[IOParallelPort statusRegisterContents]
     2     48     48  masked-eq   _ppread
     4     23     21              +[IOParallelPort probe:]
     4     71     71  masked-eq   -[IOParallelPort free]
     4     35     35              -[IOParallelPort msgTypeToIOReturn:]
     5     59     59  masked-eq   -[IOParallelPort getIntValues:forParameter:count:]
     6     46     46              -[IOParallelPort cmdBufExec:]
     8     13     11              -[IOParallelPort isInitialized]
    11     27     30              -[IOParallelPort cmdBufAlloc]
    13     47     46              -[IOParallelPort waitForCmdBuf]
    14     24     23              -[IOParallelPort printerInit]
    17     45     43              -[IOParallelPort _waitForDevice:isReady:]
    22     43     41              _ppopen
    24     52     34              -[IOParallelPort probeForController]
    27     93     95              -[IOParallelPort writeToPort]
    61     87     85              _IOParallelPortInterruptHandler
    62     76     67              -[IOParallelPort initDevice]
    70     84     81              __strobeChar
    83     73     81              _ppstrategy
   112    139    141              _ppwrite
   163    172    188              _ppioctl
   201    277    278              -[IOParallelPort initFromDeviceDescription:]
   210    208    203              _IOParallelPortThread
     -      -      7  missing-reference  -[IOParallelPort autofeedOutput]
     -      7      -  missing-rebuilt  -[IOParallelPort minPhys]
     -      -      8  missing-reference  -[IOParallelPort setControlRegister:]
     -      8      -  missing-rebuilt  -[IOParallelPort setInUse:]

77 functions: 36 byte-identical, 37 differing, 4 unpaired
```
