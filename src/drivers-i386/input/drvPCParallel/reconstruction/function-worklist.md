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

## Task 6 — Finding 53 uninitialized control byte

Guest rebuild after rewriting `probeForController` and `initDevice` to `and`/`or`
an uninitialized local. Reloc SHA-256
`F1FDFD0943E86BA99F2AA510DF54AFE1CD1A9F7ACB675CA17755CC32DBDD6883` (165600 bytes).
Parity: `missing_strings (0):`, `missing_symbols (0):`.

`--name` both methods: `status=different`, `masked_equal=False`. gcc 2.x `-O`
folded Apple's bit-by-bit immediates (`or …, 1Eh`, `and …, 0C7h`, `and bl, 0FCh` /
`or bl, 0Ch`). Ledger 112 / 1452 stay `intentional-mismatch`.

Regression: every Task 4/5 `identical` and `masked-eq` row stayed equal (0 lost).
Accessor name-pairing unpaired rows closed: `--list` is now 75 functions, 0 unpaired.
`autofeedOutput` / `minPhys` / `setControlRegister:` / `setInUse:` are `identical`.

```
  diff    ref    new  flags       name

     0      6      6  masked-eq   +[ParallelPortKernelServerInstance kernelServerInstance]
     0      6      6  identical   +[ParallelPortVersion driverKitVersionForParallelPort]
     0      7      7  identical   -[IOParallelPort IOThreadDelay]
     0      7      7  identical   -[IOParallelPort autofeedOutput]
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
     0      7      7  identical   -[IOParallelPort minPhys]
     0      7      7  identical   -[IOParallelPort minorDevNum]
     0      7      7  identical   -[IOParallelPort physbuf]
     0      6      6  identical   -[IOParallelPort readFromPort]
     0      8      8  identical   -[IOParallelPort setAutofeedOutput:]
     0      8      8  identical   -[IOParallelPort setBusyMaxRetries:]
     0      8      8  identical   -[IOParallelPort setBusyRetryInterval:]
     0      8      8  identical   -[IOParallelPort setConfigRegister:]
     0      8      8  identical   -[IOParallelPort setControlRegister:]
     0      8      8  identical   -[IOParallelPort setDataRegister:]
     0      8      8  identical   -[IOParallelPort setIOThreadDelay:]
     0      8      8  identical   -[IOParallelPort setInUse:]
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
     1     34     34  masked-eq   -[IOParallelPort setBlockSize:]
     1     34     34  masked-eq   -[IOParallelPort setMinPhys:]
     1     18     18  masked-eq   _ppminphys
     2     11      9              -[IOParallelPort controlRegisterContents]
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
    27     93     95              -[IOParallelPort writeToPort]
    60     76     73              -[IOParallelPort initDevice]
    61     87     85              _IOParallelPortInterruptHandler
    68     52     48              -[IOParallelPort probeForController]
    70     84     81              __strobeChar
    83     73     81              _ppstrategy
   112    139    141              _ppwrite
   163    172    188              _ppioctl
   201    277    278              -[IOParallelPort initFromDeviceDescription:]
   210    208    203              _IOParallelPortThread

75 functions: 40 byte-identical, 35 differing, 0 unpaired
```

## Task 7 — reverse `_strobeChar` load-then-test

Guest rebuild after loading the device pointer and three registers before testing
`pp_softc[portNum].count`. Reloc SHA-256
`562D9829B43605A045C84FA4253C90206BECE0E236695BB3782B2E9D5A867A1E` (165620 bytes).
Parity: `missing_strings (0):`, `missing_symbols (0):`.

`--name __strobeChar`: `status=different`, `masked_equal=False`. Both sides now load
before `cmp dword ptr [eax+2004h], 0`. Diff 70 → 55 (84 vs 80). Leftover is gcc 2.x
CSE / register allocation (`bl` vs `[ebp+var_1]`; one `_pp_softc` load vs three).
Ledger 4232 stays `intentional-mismatch` (compiler-shaped accept).

Regression: every Task 6 `identical` and `masked-eq` row stayed equal (0 lost).
`--list` remains 75 functions, 40 identical, 14 masked-eq, 0 unpaired.

```
  diff    ref    new  flags       name

     0      6      6  masked-eq   +[ParallelPortKernelServerInstance kernelServerInstance]
     0      6      6  identical   +[ParallelPortVersion driverKitVersionForParallelPort]
     0      7      7  identical   -[IOParallelPort IOThreadDelay]
     0      7      7  identical   -[IOParallelPort autofeedOutput]
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
     0      7      7  identical   -[IOParallelPort minPhys]
     0      7      7  identical   -[IOParallelPort minorDevNum]
     0      7      7  identical   -[IOParallelPort physbuf]
     0      6      6  identical   -[IOParallelPort readFromPort]
     0      8      8  identical   -[IOParallelPort setAutofeedOutput:]
     0      8      8  identical   -[IOParallelPort setBusyMaxRetries:]
     0      8      8  identical   -[IOParallelPort setBusyRetryInterval:]
     0      8      8  identical   -[IOParallelPort setConfigRegister:]
     0      8      8  identical   -[IOParallelPort setControlRegister:]
     0      8      8  identical   -[IOParallelPort setDataRegister:]
     0      8      8  identical   -[IOParallelPort setIOThreadDelay:]
     0      8      8  identical   -[IOParallelPort setInUse:]
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
     1     34     34  masked-eq   -[IOParallelPort setBlockSize:]
     1     34     34  masked-eq   -[IOParallelPort setMinPhys:]
     1     18     18  masked-eq   _ppminphys
     2     11      9              -[IOParallelPort controlRegisterContents]
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
    27     93     95              -[IOParallelPort writeToPort]
    55     84     80              __strobeChar
    60     76     73              -[IOParallelPort initDevice]
    61     87     85              _IOParallelPortInterruptHandler
    68     52     48              -[IOParallelPort probeForController]
    83     73     81              _ppstrategy
   112    139    141              _ppwrite
   163    172    188              _ppioctl
   201    277    278              -[IOParallelPort initFromDeviceDescription:]
   210    208    203              _IOParallelPortThread

75 functions: 40 byte-identical, 35 differing, 0 unpaired
```

## Task 8 — cheapest-first source-shape experiment lists

Skipped (do not grind): glue, physbuf/setPhysbuf, already-identical,
Finding 53 leftover (`initDevice`, `probeForController`), strobeChar leftover,
inb stack-slot (`controlRegisterContents` / `statusRegisterContents`), BOOL
materialization (`probe:`, `isInitialized`).

Dumps kept under `tools/binrecon/out/parallelport/task8-dumps/`. Tried items
are marked when an experiment is reverted.

### `-[IOParallelPort msgTypeToIOReturn:]` (diff 4)

Star: jump-table bodies `0xFFFFFD1E` / `0xFFFFFD2B` swapped (OFFLINE vs BUSY).
Matched: rebuilt `7DD159FCB4BCD936009C2B5FB9F89859A4E171DAA75266036958CF45AF1C2D23`.

1. Swap `PP_MSG_BUSY` and `PP_MSG_OFFLINE` case order so OFFLINE is emitted first — **kept, masked_equal**
2. Order cases by jump-table index: NOT_READY, SUCCESS, TIMEOUT, NO_PAPER, BUSY, OFFLINE
3. Order cases by `msgType` numeric value
4. Fall through TIMEOUT into default (both return `IO_R_IO`)

### `-[IOParallelPort cmdBufExec:]` (diff 6)

Star: `cmdBuffer->link.prev` store before vs after `link.next`; `add esp,8` scheduling.
Accepted leftover: rebuilt `49863885A11EC0AE2FFD49F9297D54E0702CBC364C1ABEB398D73F5AB742456A`.

1. Store `link.prev` before `link.next` (`cmdBuffer->link.prev = oldTail` first) — **kept**; leftover is `add esp,8` scheduling
2. Compute `&ioQueue` into a local before the two stores — **skipped** (invented temp / register-picking)
3. Empty-queue test as `ioQueue.prev == &ioQueue` vs `next` — **tried, reverted** (`cmp edx, eax`)
4. Declaration order: `oldTail` before vs after the lock — **skipped** (C89)

### `-[IOParallelPort cmdBufAlloc]` (diff 11)

Star: extra `esi` / separate lock local; Apple keeps the buffer in `ebx` and
sends `lock` with the `new` result still in `eax`.
Matched: rebuilt `EC622A557A0FD4AB3D3B444F6C4B731747B10FC83B1EC02844990F84F7B895C3`.

1. Drop `conditionLock` local; use `cmdBuffer->conditionLock` as the expression — **kept, masked_equal**
2. Assign `conditionLock` after `new`, then send through that local only
3. Declaration order: lock local before buffer local

### `-[IOParallelPort waitForCmdBuf]` (diff 13)

Star: `setnz` ternary for `unlockWith:` vs `push 0`/`push 1` if/else; inverted
`jz`/`jnz` on the prev-link arm.
Accepted leftover: rebuilt `D9B5138F47C5CFFF3682FE9D7FBBD6BD1E7D05CFCC11A3F78F6E7D6FE3DF440A`.

1. Replace ternary with if/else `unlockWith:1` / `unlockWith:0` — **kept** (empty→0)
2. Invert the prev-buffer if/else arms (`if (prev == &ioQueue)` first) — **kept** (`prev !=` first)
3. Invert the next-buffer if/else arms — **not needed** (already matched)
4. Load `next` before `prev` — **already the source**
5. Signedness of queue pointer locals — **skipped** (leftover is scheduling)

### `-[IOParallelPort printerInit]` (diff 14)

Star: control byte in `[ebp+var_1]` vs `bl`; Apple keeps `self` in `ebx`.
Accepted leftover: rebuilt `D9B5138F47C5CFFF3682FE9D7FBBD6BD1E7D05CFCC11A3F78F6E7D6FE3DF440A`.

1. Split `controlValue = defaults & ~INIT` into load then `&=` — **tried, no codegen change**
2. Write `outb(..., controlValue)` after a separate `controlValue |= INIT` — **already the source**
3. Reload `controlRegister` from `self` between the two `outb`s by naming `self->` — **already the source**
4. Declare `controlValue` after a dummy-width sibling is forbidden; try `int` vs `unsigned char` — **tried, regression** (38 identical, 2 unpaired)

### `-[IOParallelPort _waitForDevice:isReady:]` (diff 17)

Star: extra stack slot for `inb`; `cmp [ivar], ebx` vs `cmp ivar, 0`; `inc ebx`
vs `add esp` order.
Accepted leftover: rebuilt `76CA62E75C2467B5E0BFA25A61BB433DF1385F389D0D4DA66E98FD8411CD753F`.

1. `for (tries = 0; ; tries++)` with the bound test inside — **kept** (xor/`inc` order now matches)
2. `while (1)` + `if (!(busyMaxRetries > tries || wait)) break;` — **skipped** (same shape as kept for-loop)
3. Compare `tries < busyMaxRetries` (operand-reversed) — **kept** (first `cmp [ivar], ebx` / extra `nop`)
4. Store `status` then mask (`unsigned char` vs `int`) — **tried, no inb spill**
5. Declaration order: `slept` before `tries` before `status` — **skipped** (xor order already matches)
6. `wait == YES` tested before the retry bound — **skipped** (would invert Apple's bound-then-wait)

### `_ppopen` (diff 22)

Star: Apple two-range signed `cmp`/`jg`/`jge` vs our `lea`/`cmp 1`/`jbe`.
Accepted leftover: rebuilt `5F8A0FDE2A167B1DF11035829FA2D2117D5D101357BFE2EB6BEC5D33D70AD624`.

1. Nested `if (result > -725) { if (result != 0) return EIO; } else { ... }` — **kept** (inverted to `<= BUSY` so `jg` matches)
2. `if (result > PP_BUSY_ERROR)` then `test` zero; else `>= TIMEOUT` accept; else `> PAPER` reject; else `< OFFLINE` reject — **kept**
3. Operand-reversed `result < 0` first — **skipped** (would invert the matched tree)
4. Keep `result` in a signed `int` and compare constants in Apple's order — **already the source**

### `-[IOParallelPort writeToPort]` (diff 27)

Star: switch-arm layout (`or al,2` first vs `or al,10h`); IO_R_IO falls into
shared `mov edi, [ebx+0Ch]`.
Accepted leftover: rebuilt `D13D6D48DA5CB5B131E2F1BBF6A56A59B68EEC72583A7A74FC18880CF159C6EF`.

1. Fall through `IO_R_IO` into `default` for `returnCode = cmdBuffer->returnCode` — **kept**
2. Reorder cases: BUSY, NO_PAPER, OFFLINE, TIMEOUT, SUCCESS, IO, default — **kept**
3. Reorder cases to match Apple's binary-search pivots (`-726` first) — **already matched**
4. Assign `returnCode = 0` as `xor` by not naming it until after the switch — **already the source**
5. `if/else if` chain instead of `switch` — **skipped** (leftover is SUCCESS polarity)

### `_IOParallelPortInterruptHandler` (diff 61)

Star: extra stack slot / `lea esi, [ebp+var_1]` for status; inverted
`(status & 0x28) == 0x08` branch; SELECT test uses `[esi]` vs flags in `dl`.

1. Keep `statusByte` on stack and re-read it for SELECT/busy
2. Invert the `(status & 0x28) == 0x08` if/else
3. SELECT-set then SELECT-clear as if/else rather than if/else if
4. Load `writing` from `pp_softc[portNum].device` a second time (Apple does)
5. `portNum` in `ebx` vs `esi`; declaration order of `physbuf` / `dataRegAddr` / `delay`
6. Read-path `count != 0` vs `count > 0`; write-path `count > 0` vs `<= 0`

### `_ppstrategy` (diff 83)

Star: extra `sub esp,4` / `port` spill; inverted B_READ test; Apple reindexes
`pp_softc` instead of keeping a base pointer.

1. Invert READ/WRITE if/else
2. Recompute `minor(bp->b_dev)` at each `pp_softc` access (no `portNum` local)
3. Drop `portNum` local; use `minor(bp->b_dev)` as the expression
4. Set `B_DONE` before vs after the `result == 0` test
5. `if (result == 0) { clear B_ERROR; return 0; }` vs `if (result) error`
6. Switch case order: paper/offline, timeout, busy, default

### `_ppwrite` (diff 112)

Star: more stack (initialized locals); `initDevice` range is `lea+cmp 1` vs
Apple's signed `cmp`/`jle`; uio pointer copied to two slots.

1. Nested signed range tests matching `_ppopen` / Finding 49
2. Do not pre-zero `iov` / `tempBuffer` / `dataCopied` / `copySize`
3. Keep `uio` as the argument; drop `uioPtr`
4. `if (uio_segflg == UIO_SYSSPACE)` inverted vs `!=`
5. Declaration order: `port` / `result` / `initResult` first, copy locals later
6. Clamp `copySize` with `if (iov_len > 0x8000) copySize = 0x8000; else copySize = iov_len`

### `_ppioctl` (diff 163)

Star: different switch binary-search pivots (`40047004h` vs `40047011h`).

1. Reorder cases to numeric ioctl value
2. Reorder cases SET-then-GET as in the reference dump
3. GET-then-SET grouped by field (delay, minPhys, thread delay, ...)
4. `if/else if` chain instead of `switch`
5. Timeout `0xFFFFFFFF` test as `== (unsigned)-1` vs `== 0xFFFFFFFF`
6. Drop `timeout` local; pass `*uintData * 1000` as the expression

### `-[IOParallelPort initFromDeviceDescription:]` (diff 201)

Star: extra `var_20=0`; `strcmp` inlined with different length/pointer setup;
error-path `free` register choice.

1. `strcmp(minorDevStr, "0")` vs length-2 `cmpsb` locals (`int n = 2`)
2. Declaration order: `configTable` / `minorDevStr` / `driverName` / `portRanges`
3. Invert each early-return `if` so the success path is the `else`
4. `numPortRanges > 1` vs `!= 1` vs `>= 2`
5. Keep `self` in a local vs using `self` throughout
6. `validRange` test as else-if vs nested if

### `_IOParallelPortThread` (diff 210)

Star: `commandType` loaded then `test`/`cmp 1` vs `cmp dword, 1`; status in
`[ebp+var_1]` vs `bl`; first not-ready decode if/else polarity.

1. `if (commandType == 1) exit; if (commandType != 0) goto complete;` as load-to-local first
2. `switch (commandType)`
3. Store `statusByte` then mask (force stack slot)
4. Invert first not-ready `(status & 8)` if/else
5. Second decode: `errorFlag = 0` then `if (!(status & 8)) errorFlag = 1` as separate statements
6. `ioTimeout` / `elapsedTime` / `timeout` declaration order
7. `while (msgResult != 0)` vs `while (1)` with breaks
