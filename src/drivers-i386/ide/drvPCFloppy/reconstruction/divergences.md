# drvPCFloppy divergences

Report-pass findings for the reconstruction of drvPCFloppy against Apple's
shipped `Floppy_reloc`. Produced per
[2026-07-25-drvpcfloppy-binary-reconstruction-design.md](../../../../../docs/superpowers/specs/2026-07-25-drvpcfloppy-binary-reconstruction-design.md)
§4.2. The companion artifacts are `source-map.json`, which partitions all 225
reference functions, and `ledger.json`, which records a parity status for each.

Every function was compared on control-flow shape, call targets, literal
constants, I/O port addresses and struct field offsets, against the IDA 9.2
disassembly of the reference. Naming-level divergences are absent from this
report because the pre-pass closed them all before analysis began.

## Status summary

| Layer | Files | Functions | assembly-matched | control-flow-confirmed | divergent |
|---|---|---|---:|---:|---:|
| 1 — Controller | `FloppyCnt.m`, `FloppyCntIo.m`, `FloppyCmds.m`, `FloppyArch.m` | 29 | 11 | 2 | 16 |
| 2 — Generic disk family | `IODiskNew.m`, `IODriveNEW.m`, `IOLogicalDiskNEW.m`, `IODiskPartitionNEW.m`, `kernelDiskMethodsNEW.m` | 83 | 51 | 18 | 14 |
| 3 — Drive | `IOFloppyDrive.m`, `FloppyDriveInt.m`, `FloppyDriveInt2.m`, `VolCheck.m` | 50 | 25 | 7 | 18 |
| 4 — Disk and geometry | `IOFloppyDisk.m`, `Geometry.m`, `Request.m`, `Thread.m`, `Support.m` | 42 | 8 | 22 | 12 |
| 5 — BSD | `Bsd.m` | 18 | 9 | 0 | 9 |
| **Total** | | **222** | **104** | **49** | **69** |

Three further functions are build-generated and carry `intentional-mismatch` in
the ledger, bringing it to 225 entries.

## Unmapped functions and their reason classes

All three are `build-generated` — emitted by `kl_ld` or libgcc, with no
hand-written source to map to:

| Function | Size | Origin |
|---|---:|---|
| `__udivdi3` | 264 | libgcc 64-bit division helper |
| `+[FloppyKernelServerInstance kernelServerInstance]` | 12 | `kl_ld` kernel-server scaffolding |
| `+[FloppyVersion driverKitVersionForFloppy]` | 12 | `kl_ld` version stamp |

No reference function is `absent-from-sources`. The spec asserted seventeen were,
then three; both figures were wrong. Every function Apple compiled by hand has a
counterpart in our tree, and the source map resolves 222 of 225 to a file and
line.

## Configuration and resource comparison

`Default.table` differs from Apple's only in the build-stamped `"Driver Version"`
line. `English.lproj` is byte-identical to the shipped bundle, `Localizable.strings`
and the `Floppy.rtfd` help tree included. `Load_Commands.sect` matches the
reference's `Loaded Server,Load Commands` section apart from a trailing space on
its first line. None of these is a finding.

## Parity baseline

Measured against the guest build the fix phases start from, whose SHA-256 is
recorded as `rebuilt_sha256` in `ledger.json`:

| Axis | Original baseline | Fix-phase baseline |
|---|---:|---:|
| `missing_symbols` | 163 | 1 |
| `missing_strings` | 94 | 92 |
| `missing_imports` | 7 | 3 |
| `unresolvable_imports` | 10 | 0 |

`unresolvable_imports` counts symbols our build references that the kernel does
not export — relocations that can never bind. At 0, the driver can load. See the
addendum for how these went undetected until the final review.

**Symbol parity is closed.** The single remaining entry is `__udivdi3`, libgcc's
64-bit division helper, which no source in this project writes. Every function
Apple compiled by hand is present in our build under its own name.

The three remaining missing imports are findings rather than naming artifacts,
and each belongs to a fix phase:

| Import | Why it is missing |
|---|---|
| `.objc_class_name_NXSpinLock` | allocated by runtime lookup, `IOFloppyDisk.m:190` |
| `.objc_class_name_Protocol` | no compile-time protocol reference survives |
| `_strcpy` | the reference calls it; our sources never do |

The first two are the `objc_getClass("…")` sites listed under Layer 4 below: a
link-time class reference is only emitted when the source names the class
directly, so converting those five sites is what restores these imports. This is
the defect commit `8890be17` recorded — reconstructed sources must link classes,
not look them up.

`missing_strings` is untouched by the pre-pass, as designed: restoring the 92
diagnostic messages and `IONamedValue` tables is fix-phase work, distributed
across the layers that emit them.

## Findings

Findings are grouped by fix phase, in the order spec §4.3 sets. Within each,
systematic findings that recur across several functions are stated once rather
than repeated per function.


## Layer 1 — Controller

Source root: `D:\RhapsodiOS-floppy\src\drivers-i386\ide\drvPCFloppy\Floppy.drvproj\Floppy.lksproj\`

### -[FloppyController dmaStart:dmaStruct:] — `FloppyArch.m:47`

**Wrong struct-field offset for the VM map pointer (`FloppyArch.m:62-69`).** Source reads the map pointer from `cmdParams+0x04`:
```c
vmMap = *(unsigned int *)((char *)cmdParams + 0x04);
bufferAddr = *(unsigned int *)((char *)cmdParams + 0x20);
pmap = _vm_map_pmap_EXTERNAL(vmMap, bufferAddr);
```
The disassembly never touches `cmdParams+0x04`; it reads the map from **offset 0x58**:
```
156c  mov  ecx, [edx+20h]      ; addr -> arg2
1570  mov  edx, [edx+58h]      ; map  -> arg1
1573  push edx
156f  push ecx
1574  call _vm_map_pmap_EXTERNAL
```
`FloppyArch.m`'s own doc-comment claims offset 0x04 holds the VM map — that comment is itself the source of the error; disassembly is authoritative. This feeds a bogus "map" value into `pmap_resident_extract`, producing a wrong (or crashing) physical address.

**`isEISAPresent` invoked once in source, three times in the disassembly.** Source caches the check and reuses it once computed. The binary sends `isEisaPresent` at `0x1590` (size-limit gate), `0x15df` (bounce-buffer-vs-direct decision), and `0x167f` (xfer-mode argument) — three separate sends. Likely behaviorally inert (static hardware capability, unlikely to change mid-call) but is a verifiable missing-calls divergence per the call-targets axis.

Everything else (the `0x100000` size threshold, direction-bit logic, `_flags` bit-3 handling, bounce-buffer bcopy direction/condition, `dmaStruct` field writes and bit masks, `reserveDMALock`/`dma_mask_chan(2)` ordering, `dma_chan_xfer_mode`/`dma_xfer_chan` argument order) matches.

### -[FloppyController dmaDone:dmaStruct:] — `FloppyArch.m:176`

**Same wrong VM-map offset as `dmaStart:dmaStruct:`** (`FloppyArch.m:188-194`): source reads `cmdParams+0x04`, disassembly reads `cmdParams+0x58` (`0x16e8-0x16f0`).

Everything else (retry loop: 2 decrements to −1 sentinel = 3 attempts with `IOSleep(2)` between, `is_dma_done`/`dma_mask_chan`/`get_dma_count` sequence, the `panic("FloppyArch: Invalid dma byte count\n")` guard, `transferredBytes = requested - remaining` computation, bounce-buffer copy-back gating and direction, `dma_xfer_done`/`releaseDMALock`) matches. The dead re-test of the panic condition at `0x1746` in the disassembly is a compiler artifact from `panic` not being marked noreturn in this build; the source's omission of that unreachable code is not a real divergence.

### -[FloppyController doCmdXfr:] — `FloppyCmds.m:42`

**Entire function is an unimplemented stub.** The 551-byte/24-block reference masks the command opcode, merges the motor-select byte into the request, conditionally calls `doConfigure:`/`doSpecify:` when the drive changes, dispatches via two jump tables to call `doMotorOn:`, `seek:head:density:` (with a 20 ms `IOSleep`), and finally `sendCmd:`, then post-processes errors including a RECALIBRATE-specific retry. Source is:
```c
- (IOReturn)doCmdXfr:(void *)cmdParams
{
    // TODO: Implement command transfer execution
    return IO_R_SUCCESS;
}
```
It never calls `sendCmd:`, `doMotorOn:`, `doConfigure:`, `doSpecify:`, or `seek:head:density:`. This is a complete functional omission — the driver cannot actually execute a floppy transfer command through this entry point.

### -[FloppyController sendCmd:] — `FloppyCmds.m:187`

**Systematic +3-byte offset error on the cmd-bytes / result-bytes array bases**, which also corrupts the command-opcode read itself. The disassembly establishes the command-byte array starts at `cmdParams+0xC` and the result/status array at `cmdParams+0x28`:
```
1ad5  mov  cl, [ecx+0Ch]     ; cmdOpcode read directly from +0xC
1bc8  add  edi, 0Ch          ; cmd-byte send loop starts at +0xC
1ac5  add  edx, 28h          ; result/status base = +0x28
1c80  add  eax, 28h          ; result-byte receive loop base = +0x28
```
Source adds an extra `+3` at every one of these sites:
```c
// FloppyCmds.m:208
cmdOpcode = *(unsigned char *)((char *)cmdParams + 0x0f) & 0x1f;   // should be +0x0c
// FloppyCmds.m:256
cmdBytesPtr = (unsigned char *)((char *)cmdParams + 0x0c + 3);     // should be +0x0c
// FloppyCmds.m:300-301
resultBytesPtr = (unsigned char *)((char *)cmdParams + 0x28) +
                 *(unsigned int *)((char *)cmdParams + 0x4c) + 3;  // should drop the "+3"
// FloppyCmds.m:351-353
st0 = ((unsigned char *)((char *)cmdParams + 0x28))[3];   // should be [0]
st1 = ((unsigned char *)((char *)cmdParams + 0x28))[4];   // should be [1]
st2 = ((unsigned char *)((char *)cmdParams + 0x28))[5];   // should be [2]
```
(Verified directly: `FloppyCmds.m:208` reads `cmdParams+0x0f`, i.e. `0x0c+3`.) The same +3 shift then propagates into the sector-size math, the RECALIBRATE ST0/PCN check, and the SEEK cylinder-verify check. Because `cmdOpcode` itself is misread, the function's entire command-class dispatch (needs-interrupt switch, result-interpretation switch, RECALIBRATE/SEEK special cases) is corrupted. The count fields (`0x1C`, `0x38`, `0x24`, `0x40/44/48/4C`) are correctly offset — confirmed against `sendCmd:`'s own reads at `FloppyCmds.m:257` (`+0x1c`) and `:299` (`+0x38`) — only the two byte-array bases and everything indexed off them are wrong.

**Success-path bytes-transferred calculation wrongly reuses the abnormal-path sector-size formula for WRITE commands.** Reference's normal-termination path (`0x1ed0`) sets `field_48` to the full DMA byte count unconditionally for any write with `dmaByteCount != 0`; the cmd==5/cmd==9 sector-size recomputation (`0x1e05-0x1e34`) exists **only** in the abnormal-termination branch. Source duplicates that recomputation into the success path too (`FloppyCmds.m:358-370`), so a successful WRITE_DATA/WRITE_DELETED_DATA computes `field_48` from N/R result fields instead of just using `dmaByteCount`, diverging whenever the FDC's returned N/R don't reduce to exactly `dmaByteCount`.

Everything else (DMA start/done sequencing, cmd-byte send/result-byte receive loop mechanics, interrupt-wait timeout clamp, the full CRC/overrun/no-data/not-writable/missing-AM/ST2 error-code table, the epilogue's DMA-abort-on-error / timeout-forces-result=1 / cylinder-cache-invalidation sequence) matches.

### -[FloppyController initFromDeviceDescription:] — `FloppyCnt.m:172`

**Inverted `enableAllInterrupts` success check (`FloppyCnt.m:185-187`).** Disassembly treats nonzero as failure:
```
2205  test eax, eax
2207  jnz  loc_2334      ; nonzero == failure -> cleanup
```
Source does the opposite:
```c
if ([self enableAllInterrupts] == NO) {   // NO == 0 == IO_R_SUCCESS
    return [self free];
}
```
This calls `[self free]` on *success* and silently continues past an actual failure. Should be `!= IO_R_SUCCESS`.

**Super-init failure bypasses the shared cleanup path (`FloppyCnt.m:180-182`).** Every failure branch in the disassembly funnels into a shared `loc_2334` that calls `[self free]` before returning — including the super-init failure:
```
21e5  call _objc_msgSendSuper
21ed  test eax, eax
21ef  jz   loc_2334        ; same [self free] cleanup as every other failure
```
Source special-cases this one path to skip `free` entirely:
```c
if ([super initFromDeviceDescription:deviceDescription] == nil) {
    return nil;
}
```

### -[FloppyController fcCmdXfr:] — `FloppyCnt.m:348`

**Wrong return value on both failure paths (`FloppyCnt.m:362-364, 373-376`).** The disassembly's tail is unambiguous — success, `IOMalloc` failure, and lock-alloc failure all funnel into the same `xor eax,eax; retn` (`0x2562-0x256d`): this function **always** returns 0. Source instead returns `IO_R_NO_MEMORY` (−701) on both failure branches:
```c
if (request == NULL) {
    return IO_R_NO_MEMORY;     // should be 0 (IO_R_SUCCESS)
}
...
if (requestLock == nil) {
    IOFree(request, 0x10);
    return IO_R_NO_MEMORY;     // should be 0 (IO_R_SUCCESS)
}
```
This function is an async submit-and-wait; the caller reads actual status from `cmdParams->field_40`, not this return value, so returning nonzero here misrepresents queueing failures as command failures.

### -[FloppyController fcCmdXfrExecute:] — `FloppyCnt.m:517`

**Uninitialized local used on reset failure (`FloppyCnt.m:598, 624-625`).** Disassembly stores `[self i82077Reset:0]`'s live return value into `cmdParams+0x40` when the reset fails:
```
25c6  call _objc_msgSend    ; [self i82077Reset:0]
25ce  test eax, eax
25d0  jz   loc_25DC
25d2  mov  [ebx+40h], eax   ; cmdParams->field_40 = reset's actual return value
```
Source discards that call's return value in the `if` condition and instead uses a `result` local that was only ever assigned inside the *other* branch, so the `else` reads it uninitialized:
```c
if (((_flags & 0x01) == 0) ||
    ([self i82077Reset:0] == IO_R_SUCCESS)) {
    ...
    result = *(int *)((char *)cmdParams + 0x40);   // only assigned here
    ...
} else {
    *(int *)((char *)cmdParams + 0x40) = result;   // reads uninitialized
}
```

**Drive-number read from offset 0x14 instead of 0x5C (`FloppyCnt.m:542, 548, 565, 572`).** Disassembly validates and passes the drive number from `cmdParams+0x5C` consistently:
```
25dc  cmp  byte ptr [ebx+5Ch], 1     ; validity check
267c  movzx eax, byte ptr [ebx+5Ch]  ; -> doMotorOn:
26ac  movzx eax, byte ptr [ebx+5Ch]  ; -> doMotorOff:
```
Source reads offset `0x14` for the validity check and both motor calls instead.

**Wrong offset for the case-4 status-flag clear (`FloppyCnt.m:574-576`).** Disassembly clears a bit at `cmdParams+0x50` (`and byte ptr [ebx+50h], 0FBh`); source uses `cmdParams+0x4e`, two bytes off.

### -[FloppyController doConfigure:] — `FloppyCntIo.m:79`

**Command-byte-count written to offset 0x4C instead of 0x1C (`FloppyCntIo.m:108`):**
```c
*(unsigned int *)(cmdBuffer + 0x4c) = 4;   // should be +0x1c
```
Disassembly writes this field at `var_44`, which — buffer base `ebp-0x60` — is `buffer+0x1C`:
```
2d2e  mov  [ebp+var_44], 4   ; buffer+0x1C = 4
```
`sendCmd:` reads the actual command-byte-count from `cmdParams+0x1c` (confirmed at `FloppyCmds.m:257`) and resets `cmdParams+0x4c` to 0 at its own entry (`FloppyCmds.m:214`) before this write could matter. Net effect: the real field stays 0 from `bzero`, so `sendCmd:`'s send-loop never executes — CONFIGURE's command bytes are never sent to the FDC. **This same offset bug (0x4C used for the 0x1C field) recurs in `doSpecify:`, `getDriveStatus:` (both call sites), `recal`, and `seek:head:density:` — see the grouped note below.**

**Hardcoded configuration byte (`FloppyCntIo.m:98`):** `cmdBuffer[0x0e] = 0x18;` is a fixed literal. Disassembly computes it at runtime from two globals not present anywhere in the reconstructed driver:
```
2d0b  mov al, ds:_cf2_fifo_value
2d11  or  al, 10h
2d13  or  al, ds:_cf2_efifo
```
i.e. `fifoThreshold | 0x10 | efifoFlag`. `0x18` happens to match `fifo=8, efifo=0`, but the value is no longer runtime-configurable and will silently diverge if those globals are ever nonzero elsewhere.

### -[FloppyController doSpecify:] — `FloppyCntIo.m:162`

Same offset-mapping bug as `doConfigure:`: command-byte-count (3, for SPECIFY) written to `cmdBuffer+0x4c` instead of `+0x1c`, so `sendCmd:` never sends SPECIFY's bytes either.

**`IO_R_INVALID_ARG` used instead of the raw error code 4 for a bogus density (`FloppyCntIo.m:197`).** Disassembly's bogus-density path returns literal `4`:
```
2de7  mov eax, 4          ; return 4
```
Source returns the driverkit symbolic constant `IO_R_INVALID_ARG` instead, which does not equal `4`. (See the grouped IO_R_* constant-substitution note below — this function is one instance of that systemic issue.) All of the SRT/HUT/CCR bit-pattern computation per density case (0xAF/HLT|=0x20 for density 1/2, 0xA4/HLT|=0x1E for density 3, CCR values 2/0/3) is otherwise correct.

### Grouped: command-byte-count / result-byte-count offset bug (Systemic, `FloppyCntIo.m`)

The buffer-offset confusion identified in `doConfigure:` recurs across every FDC-command-builder function in `FloppyCntIo.m`:

- **`getDriveStatus:` (`FloppyCntIo.m:611`, both `sendCmd:` call sites, lines ~660/670 and ~720/730):** cmd-byte-count written to `+0x4c` instead of `+0x1c`, expected-result-count written to `+0x2c` instead of `+0x38`.
- **`recal` (`FloppyCntIo.m:930`, line 949/955):** same two offsets wrong.
- **`seek:head:density:` (`FloppyCntIo.m:993`, line 1008/1024):** same two offsets wrong.

In each case `sendCmd:` reads the real fields from `+0x1c` (byte count) and `+0x38` (expected result count); since these builders never write there, both fields are left at 0 by the initial `bzero`, so `sendCmd:`'s send-loop and result-receive-loop never iterate for any of CONFIGURE, SPECIFY, SENSE_DRIVE_STATUS (either call site inside `getDriveStatus:`), RECALIBRATE, or SEEK. Combined with `doCmdXfr:`'s stub status, effectively no FDC command constructed by this layer currently reaches the hardware with its command bytes intact. (`recal`/`seek:head:density:` additionally zero `cmdBuffer+0x44`/`+0x40` where the disassembly's `var_40`/`var_3C` map to `+0x20`/`+0x24`; since the buffer is already `bzero`'d this particular pair has no behavioral effect, but it is the same offset-mapping confusion.)

### Grouped: driverkit `IO_R_*` constants substituted for raw FDC status codes (Systemic, `FloppyCntIo.m`)

`sendCmd:` in `FloppyCmds.m` compares against small raw integers internally (`result == 10`, `result == 1`, `result = 0x12`, etc. — confirmed correct there). `FloppyCntIo.m` instead returns/compares driverkit symbolic constants that do not equal those raw values:

- **`fcWaitPio:` (`FloppyCntIo.m:390-431`, verified directly):** returns `IO_R_VM_FAILURE` for a direction mismatch (disassembly: raw `0xA`) and `IO_R_TIMEOUT` for exhaustion (disassembly: raw `1`) — the source's own comments (`// 10`, `// 1`) show the author knew the intended raw values but wired up the wrong constants.
- **`fcWaitIntr:timeout:` (`FloppyCntIo.m:328`):** returns `IO_R_TIMEOUT` instead of raw `1` on the `RCV_TIMED_OUT` path.
- **`floppyInterrupt:` (`FloppyCntIo.m:453`):** returns `IO_R_TIMEOUT` instead of raw `1` on poll exhaustion.
- **`getDriveStatus:` (`FloppyCntIo.m:611`):** the post-`sendCmd:` `result == {1, 0x12, 0xA}` three-way check that sets `_flags` bit 0 (hung, disasm `0x2c32`) and bit 2 (disasm `0x2c41`) is rebuilt against `IO_R_TIMEOUT`/other `IO_R_*` comparisons (plus an extra `IO_R_NO_DEVICE` branch with no disassembly counterpart), so it can never match `sendCmd:`'s actual raw-int return values.
- **`doSpecify:`** — see above, `IO_R_INVALID_ARG` vs raw `4`.

Net effect: the phase-error / controller-hung (`_flags` bit 0/2) propagation chain between these low-level I/O routines and `sendCmd:`/`getDriveStatus:` is broken, since the sentinel values never match.

### -[FloppyController fcWaitIntr:timeout:] — `FloppyCntIo.m:328`

**`msg_receive` called with `MSG_OPTION_NONE` instead of `RCV_TIMEOUT` (`FloppyCntIo.m:347`).** Disassembly pushes option literal `0x100`:
```
2f6c  push 100h
```
`src/kernel-7/mach/message.h` defines `RCV_TIMEOUT 0x0100` — the flag that makes the `timeout` argument meaningful. Without it, `msg_receive` has no reason to honor the supplied timeout, so this function would block indefinitely waiting for an interrupt message instead of returning after `timeout` ms. Also uses `IO_R_TIMEOUT` instead of raw `1` (see grouped note above). Everything else (EISA-gated 5 ms pre-sleep, success/non-timeout-error both routing to `floppyInterrupt:`) matches.

### -[FloppyController flushIntrMsgs] — `FloppyCntIo.m:524`

**Same `msg_receive` option-flag bug as `fcWaitIntr:timeout:`** (`FloppyCntIo.m:540`): `MSG_OPTION_NONE` instead of `0x100`/`RCV_TIMEOUT`, which defeats the intended non-blocking poll (`timeout=0`) — the call would block instead of returning immediately when nothing is pending.

**Always returns success (`FloppyCntIo.m:577`).** Disassembly returns `edi`, which is `floppyInterrupt:`'s own nonzero error code when that call fails; the drain loop only forces `edi` back to 0 on its *own* (swallowed) failures, never on `floppyInterrupt:`'s. Source's only `return` is an unconditional `IO_R_SUCCESS`, silently dropping a `floppyInterrupt:` failure (e.g. its 9999-poll timeout) that callers such as `i82077Reset:` should see. The drain loop mechanics, printf gating (only when a message was actually pending), and the `RCV_TIMED_OUT`-means-nothing-to-flush handling are otherwise correct.

### Functions confirmed to match cleanly (no divergence)

- **-[FloppyController doEject:]** — `FloppyCmds.m:72`. Zeroes `cmdParams+0x40`, returns success, no other side effects.
- **-[FloppyController doMotorOff:]** — `FloppyCmds.m:96`. Motor bit `0x10<<drive` cleared from the DOR shadow (`self+0x13A`), drive-select bits OR'd in, single `OUT 0x3F2`, no sleep.
- **-[FloppyController doMotorOn:]** — `FloppyCmds.m:134`. Early-out when motor already on; `motorBit | drive | shadowDOR` written to `OUT 0x3F2`; `IOSleep(1000)` spin-up delay only on the actual turn-on path.
- **_floppyDriveType** — `FloppyCnt.m:73`. CMOS register 0x10, nibble selection by drive index, warning-only-for-type-1-or-2, and the final >4-clamp all match exactly.
- **_numFloppyDrives** — `FloppyCnt.m:133`. Reproduces identical branch outcomes for every reachable input; the boolean is expressed via a different but equivalent form (`!= 0xFF` on the pre-increment value vs. the disassembly's `setnz` on the post-increment value) — not a real divergence.
- **-[FloppyController free]** — `FloppyCnt.m:275`. Exit-sentinel enqueue/signal/wait/cleanup handshake with the worker thread matches the disassembly exactly, including the doubly-linked-list splice logic.
- **+[FloppyController probe:]** — `FloppyCnt.m:422`. Port/interrupt-count validation, controller alloc/init/name/registration sequence, and the drive-probe loop all match.
- **_FloppyControllerThread** — `FloppyCnt.m:643`. Dequeue unlink logic (all three link-list cases: head-only, tail-only, neither), the exit-sentinel (`node->field_0==0`) check, and the drain-then-relock loop match.
- **-[FloppyController clearPollIntr]** — `FloppyCntIo.m:32`. 4-iteration outer loop × 2-iteration inner `fcGetByte:` drain, with `fcSendByte:8` sent only on the first 3 outer iterations, matches exactly.
- **-[FloppyController doPerpendicular:gap:]** — `FloppyCntIo.m:131`. Correctly reproduces the *binary's own* unimplemented stub (unconditional `return 0`, both parameters ignored) — this is a genuine no-op in Apple's shipped code, not a reconstruction gap.
- **-[FloppyController fcGetByte:]** — `FloppyCntIo.m:256`. `fcWaitPio:0x40` then `inb(0x3F5)` into `*bytePtr` on success, matches exactly.
- **-[FloppyController fcSendByte:]** — `FloppyCntIo.m:290`. `fcWaitPio:0` then `outb(0x3F5, byte)` on success, matches exactly.
- **-[FloppyController i82077Reset:]** — `FloppyCntIo.m:776`. The reset pulse (DOR=0, `IODelay(500)`, DOR=4, both to port 0x3F2), the density→CCR mapping for all four cases (density 2/3→CCR 0, density 1/default→CCR 2, with the default case also zeroing `field_139` first), the `clearPollIntr` call, the retry-whole-sequence-on-`doConfigure:`-failure goto loop (clearing `_flags&2` first), the `doSpecify:`-driven `_flags` bit-0 update and DOR bit-3 (IRQ/DMA enable) gating, and the motor-on/recal/motor-off probe dance all reproduce the disassembly correctly.


## Layer 2 — Generic disk family

Scope: `IODiskNew.m`, `IODiskPartitionNEW.m`, `IODriveNEW.m`, `IOLogicalDiskNEW.m`, `kernelDiskMethodsNEW.m` (83 functions). 14 of the 83 diverge from the reference binary; the rest match (51 instruction-for-instruction, 18 control-flow-equivalent). Findings below are grouped where the same root cause recurs across functions.

---

### 1. `-[IODiskNEW free]` returns `nil`, not `self`

**Source:** `IODiskNew.m:84-100`
**Reference:** addr `0x4bac`, both branches converge on block `0x4be3`.

```
4be3  xor  eax, eax        ; return value forced to 0/nil on every path
4be5  mov  ebx, [ebp+var_4]
4be8  mov  esp, ebp
```

The reference zeroes `eax` unconditionally before returning, regardless of whether a chained logical disk was freed. Source instead has `return self;` at line 99. The in-source comment even flags the uncertainty ("Note: Original decompiled code doesn't show super free call... this may be because the actual freeing happens elsewhere") but the disassembly is unambiguous: this method returns `nil`.

---

### 2. `[[Class alloc] init]` in source vs. a single `+new` send in the reference

Three call sites construct fresh objects with `alloc`/`init` (two `objc_msgSend` calls) where the reference issues exactly one `objc_msgSend` to `+new`:

- `-[IODiskNEW registerDevice]` (`IODiskNew.m:201`, addr `0x4a38`): source does `_LogicalDiskLock = [[NXLock alloc] init];`. Reference (`0x4a55`-`0x4a63`) pushes the `new` selector and the `NXLock` class ref and makes **one** `objc_msgSend` call.
- `+[IODiskPartitionNEW probe:]` (`IODiskPartitionNEW.m:75`, addr `0x4c04`): source does `logicalDisk = [[IODiskPartitionNEW alloc] init];`. Reference (`0x4cac`-`0x4cba`) makes one `objc_msgSend` to `+new` on the `IODiskPartitionNEW` class ref.
- `-[IODiskPartitionNEW(Private) _probeLabel:]` (`IODiskPartitionNEW.m:884`, addr `0x5800`): source does `partition = [[IODiskPartitionNEW alloc] init];`. Reference (`0x5883`-`0x5891`) again makes a single `objc_msgSend` to `+new`.

This is a call-target divergence (extra `alloc` send not present in the reference) at all three sites. `+new` and `[[alloc] init]` are usually equivalent unless a subclass overrides `+new` without overriding `init`/`alloc`, so this is worth fixing for byte-for-byte fidelity even though it is unlikely to change behavior for these classes.

---

### 3. `-[IODiskPartitionNEW writeLabel:]` — three distinct issues

**Source:** `IODiskPartitionNEW.m:319-480`, addr `0x5160`.

**(a) The probe timestamp is silently discarded instead of being written into the label.**

Source (lines 385-391):
```c
// Set timestamp (stock disk_label has no dl_label_time; keep probeTime)
IOGetTimestamp(&timestamp);
(void)timestamp;

label_p->dl_label_blkno = 0;
*checksumPtr = 0;
```

Reference (`0x5287`-`0x52a0`):
```
5287  lea   ecx, [ebp+var_8]
528a  push  ecx
528b  call  IOGetTimestamp
5290  mov   ecx, [ebp+var_8]
5293  mov   eax, [ebp+arg_8]
5296  mov   [eax+28h], ecx      ; label_p+0x28 = timestamp (low dword)
5299  mov   dword ptr [eax+4], 0 ; label_p->dl_label_blkno = 0
52a0  mov   word ptr [esi], 0    ; see (b)
```
The reference *does* store the low 32 bits of `IOGetTimestamp()` into `label_p+0x28`. The comment's premise ("stock disk_label has no dl_label_time") is contradicted by the disassembly — there is a real field at that offset and the reference writes to it. Per the disassembly-is-authoritative rule, the comment is the finding: the timestamp write is missing from the source.

**(b) `*checksumPtr = 0` clears the wrong field.**

For both label versions the reference computes **two different offsets**, but the source collapses them into one (`checksumOffset`):

| Branch | reference "zero" pointer | reference buffer-checksum offset (`var_2C`) | source `checksumOffset` (used for both) |
|---|---|---|---|
| DL_V1/DL_V2 | `label_p + 0x1c58` (`0x5223`-`0x5226`) | `0x1c46` (`0x522c`) | `0x1c46` (line 370) |
| DL_V3 | `label_p + 0x240` (`0x5277`-`0x527a`) | `0x22e` (`0x5280`) | `0x22e` (line 375) |

The buffer-checksum offset (used later at `0x52f3` to store the byte-swapped `checksum16()` result into `buffer`) matches the source exactly. But the *separate* pointer used to zero a field in `label_p` before computing the checksum (`0x52a0 mov word ptr [esi], 0`) uses a different offset (`+0x18` / `+0x12` further into the struct) that the source never computes — `checksumPtr` in source is defined as `label_p + checksumOffset`, so `*checksumPtr = 0` zeroes the wrong two bytes of `label_p` (the field at `+0x1c46`/`+0x22e`, not the field the reference actually clears at `+0x1c58`/`+0x240`).

**(c) The second "BAD LABEL" `IOLog` is missing an argument.**

First bad-label branch (label version check fails, `0x5243`-`0x525b`) pushes only `name` before the format string `aSWritelabelBad` — matches source line 380 `IOLog("%s writeLabel: BAD LABEL", name);`.

Second bad-label branch (post-checksum `check_label()` verification fails, `0x5317`-`0x5333`) additionally pushes the `check_label()` result (`edx`, pushed at `0x5317`, *before* the `[self name]` send) as a third argument, and uses a **different string constant**, `aSWritelabelBad_0`:
```
5317  push  edx                      ; checkResult
5318  mov   ecx, ds:paName
531f  mov   eax, [self]
5323  call  objc_msgSend             ; eax = [self name]
532b  mov   edx, eax
532d  push  edx                      ; name
532e  push  offset aSWritelabelBad_0 ; different format string
5333  call  IOLog
```
Source (lines 413-415) reuses the exact same one-argument call as the first branch: `IOLog("%s writeLabel: BAD LABEL", name);`. The reference's second message takes an extra numeric argument (the failing `checkResult`) and a distinct format string, which the source doesn't reproduce.

---

### 4. `setBlockDeviceOpen:` / `setRawDeviceOpen:` compute "any device open" from the wrong flag

**Source:** `IODiskPartitionNEW.m:496-520`, addrs `0x577c` (`setBlockDeviceOpen:`) and `0x57c8` (`setRawDeviceOpen:`).

Both setters call `[self setInstanceOpen:(_labelValid != 0)]` — i.e. they derive "is this instance open" from the *label-valid* flag (offset `0x154`), which has nothing to do with device-open state.

The reference computes it from the block/raw open flags instead:
```
578f  test  dword ptr [edx+154h], 0FFFF00h   ; mask selects bytes at +0x155/+0x156
5799  setnz al                                ;   = _blockDeviceOpen || _rawDeviceOpen
579c  and   eax, 0FFh
57a1  push  eax
57a2  mov   ecx, ds:paSetinstanceope
57a9  call  objc_msgSend                       ; [self setInstanceOpen:(blockOpen||rawOpen)]
```
The 32-bit read at `[edx+154h]` masked with `0x00FFFF00` picks up bytes `0x155` (`_blockDeviceOpen`) and `0x156` (`_rawDeviceOpen`) while excluding `0x154` (`_labelValid`) and `0x157`. So the reference's "is open" test is `_blockDeviceOpen != 0 || _rawDeviceOpen != 0`, evaluated *after* the just-updated flag is stored — not `_labelValid != 0`. Both setters need to test the block/raw-open pair, not `_labelValid`.

---

### 5. `IOReturn`-declared methods that fall through to the epilogue without an explicit success/error constant

Five functions are declared to return `IOReturn` and the source explicitly returns `IO_R_SUCCESS` (or a specific error constant) on every path, but the reference disassembly has at least one path that reaches the epilogue with no `mov eax, <const>` — the return value is just whatever register content is left over from the preceding call:

- `-[IODiskPartitionNEW(Private) _initPartition:disktab:]` (`IODiskPartitionNEW.m:854`, addr `0x5924`): falls straight from the `registerUnixDisk:` call into the epilogue; `eax` = registerUnixDisk's return value, not the source's explicit `IO_R_SUCCESS`.
- `-[IODiskPartitionNEW(Private) _probeLabel:]` (`IODiskPartitionNEW.m:899` / line 894-897, addr `0x5800`): the `_partition != 0` branch falls from the `IOLog` call straight to the shared epilogue (`0x5843 jmp loc_5919`); `eax` = `IOLog`'s return value, not `IO_R_SUCCESS`.
- `-[IODriveNEW ejectMedia]` (`IODriveNEW.m:85`, addr `0x5f8c`): falls from the `setLastReadyState:` call straight to the epilogue; `eax` happens to equal `self` (a leftover register value from earlier in the function), not `IO_R_SUCCESS`.
- `-[IODiskNEW(kernelDiskMethodsPrivate) registerUnixDisk:]` (`kernelDiskMethodsNEW.m:100-120`, addr `0x723c`): the "bogus partition" branch falls from `IOLog` to the epilogue (`eax` = `IOLog`'s result, not `IO_R_INVALID`); the two success branches fall through with `eax` = the `_devAndIdInfo` pointer, not `IO_R_SUCCESS`.
- `-[IODiskNEW(kernelDiskMethodsPrivate) unregisterUnixDisk:]` (`kernelDiskMethodsNEW.m:127-147`, addr `0x7294`): same shape as `registerUnixDisk:` — all three paths (`bogus partition`, `liveId` clear, `partitionId[]` clear) fall to their own local epilogue without setting `eax` to `IO_R_INVALID`/`IO_R_SUCCESS`.

Every call site of these five methods within this layer discards the return value, so there is currently no observable behavior change from the source's explicit-return version. Flagging because `registerUnixDisk:`/`unregisterUnixDisk:` in particular are also called from outside this layer (e.g. `IOFloppyDisk`), where a caller could plausibly check the result.

---

### 6. `-[IOLogicalDiskNEW readAt:...]` / `writeAt:...` zero `*actualLength` on error paths the reference doesn't

**Source:** `IOLogicalDiskNEW.m:172-200` (`readAt:length:buffer:actualLength:client:`, addr `0x6d10`) and `IOLogicalDiskNEW.m:237-275` (`writeAt:length:buffer:actualLength:client:`, addr `0x6dc8`).

Source adds a defensive `if (actualLength) { *actualLength = 0; }` before returning on every error path. The reference returns the error code directly with no such write:

```
; readAt, _diskParamCommon failure path
6d3a  test  eax, eax
6d3c  jnz   loc_6D65        ; loc_6D65 is the bare epilogue — no *actualLength write
```
```
; writeAt, write-protected path
6de2  test  al, al
6de4  jz    loc_6DF0
6de6  mov   eax, 0FFFFFD31h
6deb  jmp   loc_6E3B        ; loc_6E3B is the bare epilogue — no *actualLength write

; writeAt, _diskParamCommon failure path
6e10  test  eax, eax
6e12  jnz   loc_6E3B        ; same bare epilogue
```
This affects `readAt:` (1 error path: lines 187-192) and `writeAt:` (2 error paths: lines 251-254 and 263-266). The corresponding `readAsyncAt:`/`writeAsyncAt:` methods have no `actualLength` parameter and correctly have no such logic — they match the reference exactly. `_diskParamCommon:length:deviceOffset:bytesToMove:` itself also matches the reference exactly; the extra zeroing is only added by its two callers.

---

### 7. `-[IODiskNEW(kernelDiskMethods) completeTransfer:withStatus:actualLength:]` calls the wrong selector

**Source:** `kernelDiskMethodsNEW.m:77`: `errno = [self _errnoFromReturn:status];`
**Reference:** addr `0x71ac`, `0x71c4`: selector is `paErrnofromretur` → `errnoFromReturn:` (no underscore).

`IODiskNEW` implements `- (int)errnoFromReturn:(IOReturn)rtn` (`IODiskNew.m:58`, matches the reference exactly — see verdict for that function). No `_errnoFromReturn:` selector is declared or implemented anywhere in this driver (confirmed by grep across `Floppy.lksproj`); `Bsd.m`'s own caller uses the correct `errnoFromReturn:` name. This looks like a stray underscore left over from the naming pre-pass and should be `[self errnoFromReturn:status]`.

---

### Passing notes (not treated as findings)

- `-[IODiskNEW stringFromReturn:]` (`IODiskNew.m:298`, addr `0x4ad8`): the reference walks an *external* table symbol `_diskIoReturnValues` plus a companion count global (`off_C72C`) that gates whether the table is consulted at all before falling back to `[super stringFromReturn:]`. The source instead defines a local `static const` array with a 3-field entry format (`{code, string, terminator}`) containing only a terminator entry. For the base `IODiskNEW` class both produce the same observable behavior (immediately defers to super, since the table is/would be empty), so this is not flagged as a divergence — just worth knowing the entry layout doesn't literally mirror the reference's.
- `-[IODiskPartitionNEW(Private) checkSafeConfig:]` calls `[self isAnyOtherOpen]`, which — per the already-known, out-of-scope finding — resolves to our tree's `-[IODiskPartitionNEW(Private) isAnyOtherOpen]` override instead of the inherited `-[IOLogicalDiskNEW isAnyOtherOpen]` the reference would dispatch to (the reference has no such override on `IODiskPartitionNEW`). `checkSafeConfig:`'s own control flow matches the reference exactly; the divergence lives entirely in the already-flagged extra method, not in `checkSafeConfig:` itself.
- `-[IODiskPartitionNEW(Private) _initPartition:disktab:]`'s super call to `setFormattedInternal:` uses `objc_getOrigClass` at runtime instead of the statically-resolved `objc_super` struct used elsewhere in this file. This is because `_initPartition:disktab:` is defined in the `(Private)` category rather than the main `@implementation`; it's a compiler code-generation artifact for category methods, not something the source can or should replicate.


## Layer 3 — Drive

### Systematic finding: the FDC command-buffer struct offsets are wrong

Nine functions build or consume the 0x60-byte `cmdBuffer`/`fdIoReq` structure that gets
handed to `-fdSendCmd:` / `_fcCmdXfr:`. The source consistently places the fields at the
offsets documented in the "From decompiled code" comments, but those offsets do not match
where the disassembly actually reads/writes them. The true layout, confirmed independently
from `fdSeek:head:`, `fdRecal`, `fdReadId:statp:`, `fdGenRwCmd:...`, `fdGetStatus:`,
`updateReadyStateInt`, `fdEjectInt`, `motorOffCheck` and `fdRwCommon:...` is:

| field | true offset (disasm) | offset the source uses |
|---|---|---|
| FDC controller number | `+0x00` | `+0x00` (correct) |
| timeout (ms) | `+0x04` | `+0x04` (correct) |
| command-type / op selector for `fcCmdXfr:` (1 = raw FDC bytes, 5 = SENSE DRIVE STATUS, 4 = motor off) | `+0x08` | `+0x5c` (wrong) |
| raw FDC command byte (byte 0 of the D/H/M/... sequence) | `+0x0C` | `+0x24` (wrong) |
| head/unit byte | `+0x0D` | `+0x25` (wrong) |
| cylinder byte (SEEK) | `+0x0E` | `+0x26` (wrong) |
| phase | `+0x1C` | `+0x1C` (correct) |
| buffer pointer | `+0x20` | `+0x30` (wrong) |
| expected byte count | `+0x24` | `+0x34` (wrong) |
| result-bytes-expected | `+0x38` | `+0x38` (correct, except fdFormatTrack, see below) |
| FDC raw result byte, fed to `fdrToIo()` | `+0x40` | `+0x40` (correct) |
| status byte returned by SENSE DRIVE STATUS | `+0x50` | `+0x14` (wrong) |
| actual bytes transferred (post-transfer) | `+0x48` | `+0x3c` (wrong) |
| VM map / task | `+0x58` | `+0x54` (wrong, except fdFormatTrack where it's coincidentally right) |
| unit number stashed by `fdSendCmd:` | `+0x5C` | `+0x10` (wrong) |

Evidence (representative — `fdSeek:head:`, disassembly around `0x3241`-`0x3266`):
```
3241  and      [ebp+var_54], 0C0h      ; var_54 == cmdBuffer+0x0C
3245  or       [ebp+var_54], 0Fh       ; SEEK opcode 0x0F written at +0x0C
3251  and      [ebp+var_53], 7         ; var_53 == cmdBuffer+0x0D
325c  and      [ebp+var_53], 0FBh
3260  or       [ebp+var_53], al        ; head<<2 written at +0x0D
3266  mov      [ebp+var_52], dl        ; var_52 == cmdBuffer+0x0E, track byte
```
Source (`FloppyDriveInt.m:608-615`):
```c
cmdBuffer[0x24] = 0x0F;  // SEEK command
cmdBuffer[0x25] = cmdBuffer[0x25] & 3;
cmdBuffer[0x25] = cmdBuffer[0x25] | ((head & 1) << 2);
cmdBuffer[0x26] = (unsigned char)track;
```
The same `0x0C`/`0x0D` vs `0x24`/`0x25` mismatch recurs verbatim in `fdRecal`
(`cmdBuffer[0x24] = 7;`), `fdReadId:statp:` (`cmdBuffer[0x24]`/`[0x25]`), `fdFormatTrack:head:`
(`cmdBuffer[0x24]`..`[0x29]`) and `fdGenRwCmd:blockCount:fdIoReq:readFlag:`
(`cmdBytes = cmdStruct + 0x24;`, disasm: `lea esi, [edi+0Ch]`).

The `+0x08` command-type field is confirmed independently in `fdGetStatus:` (`mov [ebp+var_58], 5`,
i.e. `+0x08`, vs source's `cmdBuffer + 0x5c = 5`), `updateReadyStateInt` (same pattern),
`fdEjectInt` (`mov [ebp+var_58], 4` at `+0x08` vs source's `+0x5c = 4`), `motorOffCheck`
(identical), and `fdRwCommon:...` (`mov [ebp+var_58], 1` at `+0x08` vs source's `+0x5c = 1`).

`fdGetStatus:` additionally writes the result field at source-offset `+0x60`, which is
**out of bounds** — `cmdBuffer` is declared `unsigned char cmdBuffer[0x60]` (valid indices
`0`-`0x5f`). `updateReadyStateInt` has the identical out-of-bounds write. The true offset for
that field (confirmed via disasm `mov [ebp+var_5C], ...`) is `+0x04` (the timeout), not `+0x60`.

`fdGetStatus:` and `updateReadyStateInt` also read the SENSE DRIVE STATUS result byte from
`cmdBuffer[0x14]`, but disasm reads it from `var_10` == `cmdBuffer+0x50`:
```
330a  mov      dl, [ebp+var_10]     ; var_10 == cmdBuffer+0x50
330d  mov      [edi], dl            ; *status = cmdBuffer[0x50]
```

`fdSendCmd:` stores the unit number at `cmd[0x5C]`, not `cmd[0x10]` as the source has it:
```
3620  mov      [esi+5Ch], al        ; cmd[0x5C] = unit
```
vs source (`FloppyDriveInt.m:664`): `cmd[0x10] = unit;`

`rawReadInt:sectCount:buffer:` and `fdRwCommon:...` both write the buffer pointer at
`+0x20` (not `+0x30`), the expected-byte-count at `+0x24` (not `+0x34`), the VM
task at `+0x58` (not `+0x54`), and read the actual-transferred-byte-count from `+0x48`
(not `+0x3c`):
```
3402  mov      [ebp+var_40], edx     ; var_40 == +0x20, buffer pointer
340f  mov      [ebp+var_3C], edi     ; var_3C == +0x24, expected bytes
341a  mov      [ebp+var_8],  eax     ; var_8  == +0x58, VM task
3432  mov      eax, [ebp+var_18]     ; var_18 == +0x48, actual bytes
```

Net effect: every one of these nine functions builds command buffers that put the wrong
byte in the wrong slot, so if the driver ever ran, the FDC would receive garbage command
bytes (the real command byte lands where the source thinks a `0` phase-pad field goes, and
vice versa) and status/byte-count reads would pull from uninitialized or unrelated bytes.
This is the single biggest issue in the layer.

Affected functions: `-fdFormatTrack:head:`, `-fdGenRwCmd:blockCount:fdIoReq:readFlag:`,
`-fdGetStatus:`, `-fdReadId:statp:`, `-fdRecal`, `-fdSeek:head:`, `-fdSendCmd:`,
`-rawReadInt:sectCount:buffer:`, `-updateReadyStateInt`, `-fdEjectInt`,
`-fdRwCommon:block:blockCnt:buffer:client:actualLength:`, `-motorOffCheck`.

(`fdReadId:statp:`'s tail — the 7-byte status copy at `cmdBuffer[0x28..0x2e]` into `statp` —
and `fdGenRwCmd:...`'s control fields at `+4/+8/+0x1c/+0x38/+0x3c` and its byte-by-byte
command-byte construction (head/unit/N/EOT/GPL/DTL values and order) are otherwise correct;
only the base offset of the command-byte block is wrong there.)

---

### `-updateReadyStateInt` — declared `void`, but the disassembly computes and returns a ready-state code

`FloppyDriveInt.m:766-807`. Disassembly (`0x36ea`-`0x370e`) computes `eax = 0` (ready),
`1` (command failed) or `2` (not ready/wrong unit) and returns it in `eax` — this is the
function's actual return value. The reconstructed source is declared `-(void)`, computes
`readyState` into a local and then does nothing with it ("we might be storing it" — the
comment even flags the gap). The caller, `-pollMedia` (`IOFloppyDrive.m:271`), does
`result = [self updateReadyStateInt];` and branches on `result == 0`, so as written this
cannot compile/work correctly — the method needs to return `int`/`IOReturn` and propagate
`readyState`.

---

### `-allocateDisk` returns the opposite convention from what the disassembly (and its caller) expect

`FloppyDriveInt.m:219-280`. Disassembly ends:
```
39a3  test     eax, eax
39a5  setnz    al          ; al = 1 if the new IOFloppyDisk was allocated, 0 if alloc failed
39a8  and      eax, 0FFh
```
i.e. the function returns a plain boolean: 1 = success, 0 = failure. The caller,
`-pollMedia` (`IOFloppyDrive.m:6cbb`-`6ccc` / source line 283-287), does
`allocated = [self allocateDisk]; if (allocated) return YES;` — also expecting nonzero-on-success.
But the reconstructed source returns `(diskObject != nil) ? IO_R_SUCCESS : IO_R_NO_MEMORY;`,
and `IO_R_SUCCESS == 0`. So on a *successful* allocation the source returns `0`, which
`pollMedia`'s own `if (allocated)` then treats as failure — the two ends of this call are
mutually inconsistent. `allocateDisk` should return a plain `BOOL` (`diskObject != nil`),
not an `IOReturn`.

---

### `-ejectMedia`, `-registerVolCheck`, `-unregisterVolCheck` — hardcoded `IO_R_SUCCESS` instead of propagating the call result

None of these three set `eax` after their final `objc_msgSend`/C call; the disassembly lets
whatever that call returned become the method's own return value:
```
; -ejectMedia, IOFloppyDrive.m:6c66
6c66  call     near ptr _objc_msgSend   ; [self fdEjectInt]
6c6b  mov      ebx, [ebp+var_C]         ; no eax assignment — falls through with fdEjectInt's result
```
```
; -registerVolCheck, VolCheck.m:9145
9145  call     near ptr _volCheckRegister
914a  mov      ebx, [ebp+var_4]         ; no eax assignment
```
```
; -unregisterVolCheck, VolCheck.m:915b
915b  call     near ptr _volCheckUnregister
9160  mov      esp, ebp                 ; no eax assignment
```
The source instead does `[self fdEjectInt]; return IO_R_SUCCESS;` and
`volCheckRegister(...); return IO_R_SUCCESS;` / `volCheckUnregister(self); return IO_R_SUCCESS;`,
discarding the real result and always returning 0. `fdEjectInt` can legitimately return a
nonzero seek error on its fatal path, so `ejectMedia` silently swallowing that is a real
behavioral difference, not just cosmetic.

---

### `-registerVolCheck` — `volCheckRegister` is called with a dropped third argument

`VolCheck.m:116-131`. Disassembly:
```
9117  push     ebx                       ; self
9118  mov      edx, ds:paCharacterdevof
911e  push     edx
911f  mov      edx, ds:paIofloppydisk
9125  push     edx
9126  call     near ptr _objc_msgSend    ; [IOFloppyDisk characterDevOfDrive:self]
912b  push     eax                       ; characterDev result pushed — but not popped by the
                                          ;  next call's own cleanup ("add esp, 0Ch" below only
                                          ;  reclaims that call's own 3 args)
912c  push     ebx
912d  mov      edx, ds:paBlockdevofdriv
9133  push     edx
9134  mov      edx, ds:paIofloppydisk
913a  push     edx
913b  call     near ptr _objc_msgSend    ; [IOFloppyDisk blockDevOfDrive:self]
9140  add      esp, 0Ch
9143  push     eax                       ; blockDev
9144  push     ebx                       ; self
9145  call     near ptr _volCheckRegister
```
The leftover `characterDev` push from `912b` is still on the stack when `volCheckRegister`
is called, sitting right below `self`/`blockDev` — i.e. `volCheckRegister` is a 3-argument
call `volCheckRegister(self, blockDev, characterDev)` (this leftover-argument pattern is used
throughout this binary, e.g. `_pmap_resident_extract` in `floppyMalloc`/`physContBlocks`/`vFloppyCopy`).
The source (`VolCheck.m:122-128`) computes `characterDev` into a local and then never uses it —
it's dead code — and calls `volCheckRegister(self, blockDev);` with only two arguments. If
`volCheckRegister`'s real prototype takes three arguments, the reconstructed call is missing one.

---

### `-logRwErr:block:status:readFlag:` — parameter types don't match the call sites, and the `IOLog` argument order is swapped

`FloppyDriveInt2.m:528-554`. All call sites (in `fdRwCommon:...`, e.g. `0x3ea2`) pass a
**string literal** (`"FATAL"`, `"RETRYING"`, `"RECALIBRATING"`) for `operation`, and pass the
FDC status **by value** (`mov edx, [ebp+var_20]; push edx` — the raw int, not an address) for
`status`:
```
3e9c  push     ecx                     ; readFlag
3e9d  push     edx                     ; status BY VALUE (var_20 == fdcStatus int, not &fdcStatus)
3ea1  push     edi                     ; block
3ea2  push     offset aRecalibrating   ; operation — a C string, not an unsigned int
```
The source declares `operation` as `unsigned` (then casts it back to `const char *` when
formatting — a real, if currently self-consistent, type mismatch) and declares `status` as
`unsigned char *`, dereferencing it inside the method. The caller in the reconstructed
`fdRwCommon:...` happens to pass `&fdcStatus` and the method happens to dereference it, so the
*value* that ends up in the log message is currently correct by construction, but the ABI
doesn't match the disassembly (no pointer is actually formed/dereferenced there) and should be
fixed for fidelity: `operation` should be `const char *`, `status` should be `unsigned` (by
value).

Separately, the final `IOLog` call's argument order is swapped relative to the source. Tracing
the stack at the `IOLog` call site (`0x4051`) gives, in argument order:
`driveName, block, operationType("Read"/"Write"), operation("FATAL"/"RETRYING"/...), statusString`
(the leftover `operation` push from `4012` ends up as the *last* varargs slot, after
`statusString`). The source's call (`FloppyDriveInt2.m:551-553`) instead orders the last two as
`..., (const char *)operation, statusString` matching the format string
`"%s: Sector %d cmd = %s; %s: %s"` positionally, but the *computed* order from the disassembly
puts `statusString` before the leftover `operation`, i.e. the last two `%s` conversions are
transposed from what the source produces. This is exactly the kind of diagnostic-string
divergence called out as worth confirming for this layer.

---

### `-initFromDeviceDescription:::` — default geometry is hardcoded instead of read from the global tables

`IOFloppyDrive.m:172-259`. The source hardcodes the 720KB defaults:
```c
_fdcNumber = 1; _totalBytes = 0xb4000; _writePrecomp = 1; _sectorSize = 0x200;
_sectorSizeCode = 2; _sectorsPerTrack = 9; _readWriteGapLength = 0x1b; _formatGapLength = 0x54;
```
The disassembly instead loads these from data tables/pointers, not literals:
```
6710  mov      edx, ds:_fdDensityInfo      ; edx = &fdDensityInfo (a POINTER, not the int 1)
6716  mov      [esi+190h], edx              ; stored into the _fdcNumber field
671c  mov      edx, ds:dword_C28C            ; totalBytes from a global, not the literal 0xb4000
6722  mov      [esi+194h], edx
6728  mov      edx, ds:dword_C290              ; writePrecomp from a global, not the literal 1
672e  mov      [esi+198h], edx
6734  mov      eax, ds:off_C264                  ; sector-size info table pointer
6739  mov      edx, [eax]
673b  mov      [esi+19Ch], edx                    ; sectorSize = *(off_C264+0)
6741  mov      edx, [eax+4]
6744  mov      [esi+1A0h], edx                     ; sectorSizeCode = *(off_C264+4)
674a  mov      edx, [eax+8]
674d  mov      [esi+1A4h], edx                      ; sectorsPerTrack = *(off_C264+8)
6753  mov      eax, [eax+0Ch]
6756  mov      [esi+1A8h], eax                        ; gapLength = *(off_C264+0xC)
```
Most strikingly, `_fdcNumber` (offset `0x190`) is assigned the **address** of `_fdDensityInfo`
(a 4-byte pointer store), not an integer `1` — inconsistent with every other place in this
layer that treats offset `0x190` as a one-byte field (`fdFormatTrack:head:`, `fdSendCmd:`).
Assuming `dword_C28C`/`dword_C290`/`off_C264[0..3]` are in fact initialized elsewhere to the
same 720KB values the source hardcodes, the visible behavior may currently coincide, but the
source doesn't reference the real global tables and the `_fdcNumber` pointer-vs-int mismatch
needs verifying against whatever actually lives at offset `0x190`/`_fdDensityInfo`'s layout —
worth an explicit follow-up against Geometry.m/the density tables, which are outside this
layer's files.

---

### Minor / informational

- `_physContBlocks` (`FloppyDriveInt2.m:50-118`) recomputes `vm_map_pmap_EXTERNAL(map)` on
  every loop iteration (`0x44c4`-`0x44cd`) where the source computes `pmap` once before the
  loop and reuses it. Since `vm_map_pmap` is a pure function of `map`, this doesn't change
  results — noted for completeness, not counted as a behavioral divergence.
- The task's called-out expectation — that the reference emits `FDCMD_*`/`FD_DENS_*`/`FD_MID_*`
  name-table lookups and `IOLog` diagnostics this layer's source lacks — is confirmed exactly
  once in this layer: `-logRwErr:block:status:readFlag:` calls `_IOFindNameForValue` against
  `_fdrValues` and formats an `IOLog`, and the source *does* have both (see the parameter/arg-order
  finding above for the divergence in how they're wired). No other function in this layer's
  disassembly calls `_IOLog` or a name-table lookup that the source lacks outright.


## Layer 4 — Disk and geometry

Summary: 42 functions examined, 12 diverge from the reference, 30 match (either
byte-for-byte trivial or control-flow/constant/call equivalent). The "DMA bounce
buffer" lead called out in the task brief (missing `alloc_cnvmem`, `get_dma_addr`,
`dma_xfer_abort` imports) does **not** apply to this layer — see the dedicated
note at the end. The largest real finding in this layer is a missing
error-check on `dowire`'s return value inside `executeSubrequest:`, and a
completely missing disk-elevator (SCAN) scheduler inside `operationThread`.

---

### `_fdGetSectSizeInfo` (Geometry.m:206)

Two behavioural differences, both real:

1. **Missing `IOPanic` call.** The reference calls `_IOPanic("fdGetSectSizeInfo: ...")`
   when no table entry matches, then returns 0. The reconstructed source never
   calls `IOPanic` at all and instead falls out of its `while` loop to
   `return _ssi_1mb;`.
2. **Wrong match semantics.** The reference's loop only ever compares
   `entry[0] == density` (the density argument) — it does **not** treat a
   terminal `entry[0] == 0` as a wildcard match:
   ```
   4438  cmp   [eax], edx      ; entry[0] == density ?
   443a  jnz   loc_4444
   443c  mov   eax, [eax+4]    ; return entry[1]
   ...
   4444  add   eax, 8          ; entry += 2
   4447  cmp   dword ptr [eax+4], 0
   444b  jnz   loc_4438
   444d  push  offset aFdgetsectsizei
   4452  call  near ptr _IOPanic
   4457  xor   eax, eax
   ```
   The source instead has:
   ```c
   if (entry[0] == density || entry[0] == 0) {
       return (unsigned int *)entry[1];
   }
   ```
   Because `fdDensitySectsize`'s 4th pair is `{0, (unsigned)_ssi_1mb}`, the
   source's `|| entry[0] == 0` clause makes it silently return `_ssi_1mb` for
   *any* unrecognized density, whereas the reference walks one more pair (the
   `{0,0}` terminator), fails the `entry[1] != 0` continuation check, and
   panics. For density values other than 1/2/3 this is an observable
   behavioural difference (silent fallback vs. kernel panic).

---

### `+[IOFloppyDisk capacityFromSize:]` (Geometry.m:381) and `+[IOFloppyDisk sizeListFromCapacities:sizeList:]` (Geometry.m:498)

**Both functions read the wrong `FloppyGeometry` fields.** They use
`geometryEntry[4]` (sectorsPerTrack) and `geometryEntry[6]` (bandLayout
pointer, 0 for fixed-geometry entries) to compute `sizeInKB`. The reference
uses `geometryEntry[1]` (total block count) and `geometryEntry[5]`
(sectorSize):

`capacityFromSize:` (0x47f8):
```
4810  lea   eax, [edx+edx*2]
4813  lea   eax, [eax+eax*8]     ; eax = 27*index
4816  add   eax, edx             ; eax = 28*index  (byte offset of entry)
4818  mov   esi, [ecx+eax+4]     ; esi = geometryEntry[1]   (blocks)
481c  imul  esi, [ecx+eax+14h]   ; esi *= geometryEntry[5]  (sectorSize)
4823  mov   eax, esi
4826  shr   eax, 0Ah             ; sizeInKB = (blocks*sectorSize) >> 10
```
`sizeListFromCapacities:sizeList:` (0x4798) does the identical
`[ebx+eax+4]` / `[ebx+eax+14h]` (field-1 / field-5) computation at 0x47c4-0x47cf.

Reconstructed source (both functions, same pattern):
```c
blocks = geometryEntry[4];           // Offset 0x10 from entry start
sectorsPerTrack = geometryEntry[6];  // Offset 0x18 from entry start
sizeInKB = (unsigned int)(blocks * sectorsPerTrack) >> 10;
```
Verified against the `FloppyGeometry` data itself (Geometry.m:313-352): for
the 1.44MB entry, field[1]=0xb40(2880), field[4]=0x12(18, sectorsPerTrack),
field[5]=0x200(512), field[6]=0 (bandLayout, fixed geometry). The correct
computation `field[1]*field[5]>>10 = 2880*512/1024 = 1440` matches the format
name. The source's computation `field[4]*field[6]>>10 = 18*0>>10 = 0` is
wrong for every fixed-geometry entry, and for variable-geometry entries
`field[6]` is a nonzero *pointer* (e.g. `appleBandLayout1600`), producing a
huge garbage value instead of a KB size. `capacityFromSize:` therefore never
correctly maps a disk size back to a capacity ID, and
`sizeListFromCapacities:sizeList:` fills its output array with 0 (or a huge
number) instead of correct KB sizes.

Note: the sibling method `+[IOFloppyDisk geometryOfCapacity:]` only ever
compares `geometryEntry[0]` (capacity ID) and is unaffected — it matches the
reference cleanly.

---

### `-[IOFloppyDisk blocksToEndOfCylinderFromBlockNumber:]` (Geometry.m:553)

The variable-geometry search loop's inequality is inverted relative to the
reference.

Reference (0x46fc):
```
4720  add   edx, 0Ch          ; geometryArray += 3
4723  cmp   [edx], ecx        ; geometryArray[0] vs blockNumber
4725  ja    loc_4720          ; loop WHILE geometryArray[0] > blockNumber
```
i.e. `while (*geometryArray > blockNumber) geometryArray += 3;` — advance
past bands whose start exceeds the target, stop at the first band whose
start is `<= blockNumber`.

Source:
```c
while (blockNumber >= *geometryArray) {
    geometryArray += 3;
}
```
This is the opposite direction. For a descending band table (as documented
at the top of Geometry.m: "Bands are ordered from outermost … to innermost"),
this condition is false on the very first entry for any block number less
than the largest band's start, so the loop body never executes and the
function silently uses band 0 (the wrong, outermost band) for almost every
call.

For comparison, the sibling functions that do the same kind of table walk
get the direction right:
- `cachePointerFromCylinderNumber:` (0x45bc, `jbe`/loop-while-`<=`) matches
  its source's `while (geometryArray[1] <= cylinderNumber) geometryArray += 3;`.
- `cylinderFromBlockNumber:::` (0x4618, `ja`/loop-while-`>`) matches its
  source's `while (blockNumber < *geometryArray) geometryArray += 3;`.

Only `blocksToEndOfCylinderFromBlockNumber:` has the condition backwards;
it should read `while (*geometryArray > blockNumber) geometryArray += 3;`
(equivalently `while (blockNumber < *geometryArray)`), matching the idiom
used correctly two functions away in the same file.

---

### Extra spurious `init` calls on freshly-`alloc`'d objects (systematic, 3 sites)

In three places the reconstructed source calls `[[cls alloc] init]` (or does
an `alloc` immediately followed by `init`) where the reference performs a
**bare `alloc`** and defers the real initialization to a later, separately
guarded point in the same function — or, in `free`'s case, sends `initWith:`
directly to the `alloc` result with no intervening plain `init` at all. Each
instance is real (confirmed by checking the exact `objc_msgSend` call count
and selector sequence, not just by naming) and adds one extra Objective-C
message send not present in the binary.

1. **`-[IOFloppyDisk free]` (IOFloppyDisk.m:83), `completionLock`.**
   Reference (0x62ed-0x630d) pushes args for `alloc` and `initWith:1` up
   front, then issues exactly two `objc_msgSend` calls: `[NXConditionLock
   alloc]` followed immediately by `[<result> initWith:1]`. There is no
   third call for a plain `init`. Source:
   ```c
   completionLock = [[objc_getClass("NXConditionLock") alloc] init];
   [completionLock initWith:1];
   ```
   sends `init` (not present in the binary) in addition to the correct
   `initWith:1`.

2. **`-[IOFloppyDisk initFromDeviceDescription::::]` (IOFloppyDisk.m:161),
   `_operationLock` and `_queueLock`.**
   Reference allocates both with a **bare `alloc`** and stores the raw
   result:
   ```
   6059  ... paAlloc ; push ; paNxspinlock ; push ; call objc_msgSend
   606c  mov [esi+144h], eax        ; _operationLock = alloc result (no init)
   ...
   6092  ... paAlloc ; push ; paNxconditionloc ; push ; call objc_msgSend
   60a5  mov [esi+158h], eax        ; _queueLock = alloc result (no init)
   ```
   The real `init`/`initWith:0` calls happen much later (0x6103-0x6126),
   gated behind the "geometry/operationLock/queueLock all non-nil" check.
   Source calls `init` immediately at the alloc site *in addition to* the
   correctly-placed later calls:
   ```c
   _operationLock = [[objc_getClass("NXSpinLock") alloc] init];   // extra init
   ...
   _queueLock = [[objc_getClass("NXConditionLock") alloc] init];  // extra init
   ...
   [_operationLock init];            // this one is correct/present in the binary
   [_queueLock initWith:0];          // this one is correct/present in the binary
   ```

3. **`-[IOFloppyDisk constructRequest:blockStart:byteCount:buffer:bufferMap:]`
   (Request.m:302), `lockObject`.**
   Reference (0x73bc-0x73c9) does a bare `[NXConditionLock alloc]` and stores
   the result directly into `request+0x18`; the `initWith:0` call happens
   afterward at 0x7400-0x740c, only once the allocation is known to have
   succeeded. Source again inserts an extra `init`:
   ```c
   lockObject = [[objc_getClass("NXConditionLock") alloc] init];
   *(id *)((char *)request + 0x18) = lockObject;
   ...
   [lockObject initWith:0];   // correct/present in the binary
   ```

Net effect: each of these three objects receives one additional `init`
message the reference never sends. Depending on what NeXT's `NXSpinLock`/
`NXConditionLock` `-init` actually does, this is either harmless (if `-init`
is idempotent/cheap) or re-initializes already-initialized lock state; either
way it is a call-target divergence per the reference disassembly.

---

### `_dowire` (Request.m:39) — wrong return type, and `-[IOFloppyDisk executeSubrequest:]` (Request.m:629) — missing wire-failure handling

This is the most significant functional finding in the layer, and supersedes
the DMA-import lead for this specific layer (see note below).

`dowire` is declared `static void dowire(...)` in the source. In the
reference, `dowire` ends by simply falling out of `_vm_map_pageable`'s call
with no further modification of `eax`:
```
7f0d  call  near ptr _vm_map_pageable
7f12  mov   ebx, [ebp+var_4]
7f15  mov   esp, ebp
7f17  pop   ebp
7f18  retn
```
so `dowire`'s return value **is** `vm_map_pageable`'s `kern_return_t`, not
void. `executeSubrequest:` relies on this:
```
7cef  call  _dowire                  ; dowire(kernel_map, cachePointer, byteCount, /*wire*/1)
7cf4  add   esp, 1Ch
7cf7  test  eax, eax
7cf9  jz    loc_7D04                 ; success -> proceed
7cfb  mov   [ebp+var_4], 0FFFFFD22h  ; failure -> stash error code
7d02  jmp   loc_7D4B                 ; ... and skip straight to return,
                                      ; WITHOUT calling docopy or the
                                      ; unwire dowire() call
...
7d4b  mov   eax, [edi+8]             ; parentRequest
7d4e  mov   ecx, [ebp+var_4]
7d51  mov   [eax+1Ch], ecx           ; parentRequest->0x1c = 0xFFFFFD22
```
i.e. if wiring the cache memory fails, the reference sets the parent
request's status to an error code (0xFFFFFD22) and returns immediately,
**skipping both the `docopy` transfer and the compensating unwire call**.

The reconstructed source never checks a return value from `dowire` (it
can't — the function is declared `void`), unconditionally performs the
`docopy`, and unconditionally performs the second (`unwire`) `dowire` call,
then always returns `IO_R_SUCCESS` (aside from the earlier
cylinder-error-flag check). On a wiring failure the source will still copy
to/from memory that failed to wire.

Fix shape: `dowire` should return the `kern_return_t` from
`_vm_map_pageable`, and `executeSubrequest:` needs an `if (wireResult != 0) {
parentRequest->1c = <errcode>; return <errcode>; }` branch immediately after
the first `dowire` call, before the `docopy`/second-`dowire` sequence.

(Separately, note that the *second* `dowire` call's return value is not
checked by the reference either, so no corresponding check is needed after
the unwire.)

Everything else in `executeSubrequest:` — the cylinder error-flag check, the
`cachePointerFromBlockNumber:` / geometry field lookups, the isWrite
dispatch into `docopy`'s argument order — matches the reference.

**Note on the DMA-import lead:** the task brief flagged that the reference
binary imports `alloc_cnvmem`, `get_dma_addr`, `vm_map_pageable`,
`vm_map_pmap_EXTERNAL`, and `dma_xfer_abort`, while asking us to check
whether `dowire`/`docopy`/`vFloppyCopy`/`physContBlocks` account for the
difference. Neither `vFloppyCopy` nor `physContBlocks` are part of this
layer's 42 functions (they must live in a different translation
unit/layer — likely `FloppyVm.m`, which `Request.m` `#import`s but which
was not assigned to layer 4). Within this layer, `dowire` and `docopy` are
the *only* functions that touch VM/kernel-map APIs, and they already call
`_vm_map_pageable` and `_vm_map_pmap_EXTERNAL` (plus
`_pmap_resident_extract`, `_bcopy`) exactly as the reference does — `grep`
across the full layer-4 disassembly listing shows **zero** occurrences of
`alloc_cnvmem`, `get_dma_addr`, or `dma_xfer_abort` anywhere in these 42
functions. Whoever owns the layer containing `vFloppyCopy`/`physContBlocks`
should pick up that part of the lead; for layer 4 the only real kernel-API
divergence is the missing wire-failure check documented above.

---

### `_sweepQueueInsert` (Thread.m:271) — ascending/descending queue selection is swapped

`sweepQueueInsert` decides whether a newly-queued operation goes into the
ascending or the descending sweep queue. The tie-break sub-condition (equal
cylinder) is reconstructed correctly, but the strict-inequality branch is
backwards.

Reference (0x901c):
```
9025  cmp  [eax+4], edx     ; operation[1] (opCyl) vs currentCylinder
9028  jb   loc_9032         ; opCyl <  currentCylinder -> loc_9032
902a  jnz  loc_9040         ; opCyl >  currentCylinder -> loc_9040
902c  cmp  [ebp+arg_10], 1  ; opCyl == currentCylinder: sweepDirection == 1 ?
9030  jnz  loc_9040
                             ; (opCyl == currentCylinder && sweepDirection==1) falls to loc_9032
9032  ... call _queueOperationDecending(descendingQueue, operation)
9040  ... call _queueOperationAscending(ascendingQueue, operation)
```
So the reference calls **descending** when `opCyl < currentCylinder` (or tied
with `sweepDirection==1`), and **ascending** when `opCyl > currentCylinder`
(or tied with `sweepDirection!=1`).

Source:
```c
if ((operationCylinder <= currentCylinder) &&
    ((currentCylinder != operationCylinder) || (sweepDirection != 1))) {
    queueOperationAscending(ascendingQueue, operation);   // called when opCyl < currentCylinder
    return;
}
queueOperationDecending(descendingQueue, operation);       // called when opCyl > currentCylinder
```
The tie-break clause (`sweepDirection != 1`) is reproduced faithfully, but
the strict `<`/`>` cases call the *opposite* queue-insertion function from
the reference. Every non-tied insertion goes into the wrong sweep queue.

For contrast, `_sweepQueueReorder` (Thread.m:315), which uses the identical
comparison idiom twice (moving entries between the two queues), was checked
against the same pattern and its both loops match the reference exactly —
the bug is isolated to `sweepQueueInsert`.

---

### `-[IOFloppyDisk clearOperationsOnQueue:]` (Thread.m:489) — IOFree condition too narrow

Reference dispatches on `operationType`:
```
8e70  mov  eax, [ebx]
8e72  cmp  eax, 2
8e75  jz   loc_8E90          ; type 2
8e77  jb   loc_8E80          ; type < 2  (i.e. type 0 OR type 1) -> IOFree
8e79  cmp  eax, 4
8e7c  jz   loc_8EA4          ; type 4
8e7e  jmp  loc_8E4D          ; type 3 (or anything else) -> no-op
```
i.e. the `IOFree(queueEntry, 0x28)` branch fires for **both type 0 and type
1**. Source only frees when `operationType == 1`:
```c
if (operationType == 1) {
    IOFree(queueEntry, 0x28);
}
else if (operationType == 2) { ... }
else if (operationType == 4) { ... }
```
A type-0 (read) entry found on one of these secondary queues would be
unlinked but never freed by the reconstructed source — a leak relative to
the reference's `< 2` check. (Types 2 and 4 match the reference exactly,
including which struct field holds the lock object to `unlockWith:0`.)

---

### `-[IOFloppyDisk operationThread]` (Thread.m:745) — missing disk-elevator (SCAN) scheduler

This is the largest divergence in the layer (732 bytes / 135 basic blocks in
the reference vs. a much simpler dispatcher in the source).

The reference's prologue (0x8026-0x8053) initializes **five** separate
self-referential circular queue heads (locals at `var_8`, `var_10`, `var_18`,
`var_20`, `var_28`) plus sweep-scheduling state (`var_2C`=0 "current
cylinder", `var_30`=1 "sweep direction", `var_38`, `var_3C`, `var_40`=1).
The dispatch loop calls `_sweepQueueInsert` and `_sweepQueueReorder` (both
defined earlier in this same file) to route each dequeued main-queue
operation into one of the two direction-sorted sweep queues, and drives the
actual read/write/eject/format/abort work off of *those* queues via a
5-entry jump table (`jpt_8423`), tracking head position and direction as it
goes (e.g. `var_2C` is updated to the just-serviced cylinder after each
`bringCylinderOnline:`/`commitDirtyCylinder:` at 0x8470-0x8476,
0x8508-0x850b, 0x8552-0x8555).

The reconstructed source's `operationThread` implements none of this: it
dequeues directly from the single FIFO queue at `self+0x150` and dispatches
straight into a `switch (operationType)` with no elevator queues, no
`sweepQueueInsert`/`sweepQueueReorder` calls, and no head-position tracking.
Concretely:

- Reference calls: `_IOFree, _objc_msgSend, _panic, _sweepQueueInsert,
  _sweepQueueReorder`. The source calls neither `sweepQueueInsert` nor
  `sweepQueueReorder` anywhere.
- Case 0 (read) in the reference calls `bringCylinderOnline:cylinderNumber
  isFormatted:` with a *computed* flag (`!var_38`, at 0x8455-0x8461); the
  source hardcodes `isFormatted:YES`.
- Case 4 (abort-and-exit) in the reference, after aborting subrequests on
  every cylinder, calls `[self clearOperationsOnQueue:]` **five times**
  (once per sweep-queue local, 0x88cd-0x8934) before signalling completion.
  The source's case 4 does not call `clearOperationsOnQueue:` at all.

Given the scope of this function (135 blocks), a full block-by-block
remediation map was not attempted here; the finding above establishes that
the whole scheduling structure needs to be rebuilt around
`sweepQueueInsert`/`sweepQueueReorder` and the five internal queues, not
just patched in place. `queueOperationAscending`, `queueOperationDecending`,
and `sweepQueueReorder` themselves (the three helper functions this
scheduler depends on) were separately verified to match the reference
(aside from the `sweepQueueInsert` bug noted above), so they are usable
as-is once `operationThread` is rebuilt to call them.


## Layer 5 — BSD

Source under review: `D:\RhapsodiOS-floppy\src\drivers-i386\ide\drvPCFloppy\Floppy.drvproj\Floppy.lksproj\Bsd.m`

### Systemic finding: `partition` output parameter is a raw flag, not a pointer to allocated memory

**Root cause — `identifyBsdDev` (Bsd.m:540, ref addr 0x13d8).** The reference's `identifyBsdDev` has **no calls at all** (the layer-5.txt entry for this function has no `calls:` line whatsoever — confirmed zero external calls, so it never touches `IOMalloc`). When the drive's major number matches (`expectedMajor == major`), the reference does:

```
1450  mov  esi, [ebp+arg_C]      ; esi = partOut (== &caller's local "partition" variable)
1453  or   byte ptr [esi], 1     ; *(one dereference of partOut) |= 1
```

`arg_C` is the address of the caller's stack slot (the same slot that was zeroed earlier via `mov dword ptr [esi],0` at 0x13f5, i.e. `*partOut = 0`). So the single dereference of `partOut` **is** the caller's `partition` variable — the reference stores the flag bit `0`/`1` **directly into the `partition` output slot itself**. It never allocates memory and never treats `partition` as a pointer to a separately-owned byte.

The source instead implements this as a real allocation:

```c
if (expectedMajor == major) {
    if (*partOut == NULL) {
        *partOut = (void *)IOMalloc(1);   // ← call that does not exist in the binary
    }
    partFlags = (unsigned char *)*partOut;
    *partFlags |= 1;
}
```

This is an extra, fabricated `IOMalloc(1)` call (a leaked allocation on every match, never freed by any caller), and it changes what `partition` *means*: in the source it is meant to be a pointer to a heap byte; in the binary it is the flag value (0 or 1) packed directly into the slot.

**Consequence — every caller that reads `partition` back is broken.** All three consumers dereference `partition` as if it were a valid pointer:

```c
partFlags = (unsigned char *)partition;
if ((partFlags != NULL) && ((*partFlags & 1) != 0)) { ... }
```

but the reference tests the raw integer directly, with no NULL check and no dereference:

- `_HandleBsdIoctl` (0x908) at 0x947: `test [ebp+var_C], 1` / `jnz loc_9AB` (return ENXIO)
- `_HandleBsdOpen` (0x448) at 0x4aa: `test [ebp+var_C], 1`
- `_HandleBsdClose` (0x4e4) at 0x525: `test [ebp+var_C], 1`

Since `partition` only ever holds `0` or `1` in the real binary, `partFlags = (unsigned char *)1` in the source is a non-NULL "pointer" that the source code then **dereferences** (`*partFlags & 1`) — reading memory at address `0x1`. Traced through `_HandleBsdOpen`/`_HandleBsdClose`, this also **flips the outcome** when `partition == 0`:

| `partition` value | Reference behavior | Source behavior | Match? |
|---|---|---|---|
| 0 | `test 0,1` → ZF=1 → branch taken (e.g. `setRawDeviceOpen`) | `partFlags==NULL` → condition false → **else** branch (`setBlockDeviceOpen`) | **Inverted** |
| 1 | `test 1,1` → ZF=0 → other branch (`setBlockDeviceOpen`) | `partFlags==(uchar*)1` (non-NULL) → dereferences address `0x1` → undefined/faulting read | **Diverges / crash risk** |

This affects `_HandleBsdOpen`, `_HandleBsdClose`, and the two ENXIO guards inside `_HandleBsdIoctl` that test `var_C`/`partition`. Fix direction (not applied — this task is evidence only): `partition` should be treated as a plain integer flag value passed by value through the out-parameter slot, not as `void **` pointing at allocated storage.

---

### `_HandleBsdIoctl` (Bsd.m:44, ref addr 0x908, size 2656)

This is half the layer by size and has the most divergences.

**1. Missing ioctl cases.** The reference's cmd dispatch (0x9fa–0xab8) is a linear compare cascade against exactly these 12 values, falling through to `jmp loc_1324` (`return EINVAL`, `mov eax,16h`) for anything else: `0x40346601`, `0x40046418`, `0x20006415`, `0x40046417`, `0x4020660a`, `0x40046419`, `0x40306405`, `0x80046602`, `0x5c5c6400`, `0x80046417`, `0x9c5c6401`, `0x80046603`, `0xc0606600`.

The source additionally implements four cases that are **absent from the reference and fall through to its default `EINVAL`**:
- `0x40086416` (DKIOCISWRITABLE) — source calls `[disk isWriteProtected]`; no such comparison or call exists in the binary.
- `0x2000641a` (DKIOCCHECKINSERT) — source calls `[drive pollMedia]`; `pollMedia` is never referenced anywhere in this function's disassembly.
- `0x20006414` (DKIOCGLABEL) and `0x80606401` (DKIOCSLABEL) — source returns `EINVAL` for these, which happens to match the reference's default behavior only because they hit the same default path (not because the reference special-cases them).

**2. Wrong constant for the "last ready state" case, and it's a no-op in the reference.** Source case `0x40046603` calls `*data = [deviceInfo lastReadyState]`. The reference instead compares against **`0x80046603`** (`a9a: cmp ebx, 80046603h`) and on match jumps straight to `loc_132C` (cleanup) — it never touches `data` and never sends any `lastReadyState`-like selector. `0x40046603` never appears in the reference's cascade at all (would hit `default → EINVAL`).

**3. Format-capacities case (`0x4020660a`) is a different implementation entirely.** Source hand-builds a fixed 4-int list into `data[1..3]`:
```c
formatCapacities = [deviceInfo formatCapacities];
buffer = (int *)data[1];
*buffer = 3;
buffer[1]=0x20; buffer[2]=0x100; buffer[3]=0x800;
```
Reference (0x12f0–0x1320):
```
12f0  push  [__dst]                  ; data
12f4  push  paFormatcapaciti
12fb  push  [var_4]                  ; drive  (NOT deviceInfo)
12ff  call  objc_msgSend             ; [drive formatCapacities:data]  (arg passed!)
1307  mov   ecx, eax
1309  push  ecx
130a  push  paSizelistfromca
1311  push  paIofloppydisk
1318  call  objc_msgSend             ; [IOFloppyDisk sizeListFromCapacities:ecx]
```
The reference calls `[drive formatCapacities:data]` (an argument-taking variant sent to `drive`, not `deviceInfo`) and then feeds the result into a **second, entirely different class message** `[IOFloppyDisk sizeListFromCapacities:...]` that has no counterpart anywhere in the source. There is no `IOMalloc`, no hardcoded `3/0x20/0x100/0x800` store sequence anywhere near this block — the source's implementation is fabricated relative to the binary.

**4. Read/write label cases (`0x5c5c6400`, `0x9c5c6401`) are fully implemented in the reference but stubbed to `EINVAL` in the source.** Source:
```c
case 0x5c5c6400: result = EINVAL; break;   // "not supported on floppy"
case 0x9c5c6401: result = EINVAL; break;
```
Reference for `0x5c5c6400` (0xac0–0xb04):
```
ac0  push 1C5Ch ; call IOMalloc         ; 7260-byte buffer
acc  push ebx(buf); push paReadlabel; push [var_8](disk); call objc_msgSend   ; [disk readLabel:buf]
ae7  (on success) rep movsd ecx=0x717   ; copy buf -> data (7260 bytes)
af6  push 1C5Ch; push ebx; call IOFree
```
and for `0x9c5c6401` (0xb0c–0xb49): identical shape but copies `data -> buf` first, then `push paWritelabel_0` → `[disk writeLabel:buf]`, then frees. Both cases are real, implemented operations in the binary (selectors `paReadlabel` / `paWritelabel_0`, 0x1C5C-byte IOMalloc/IOFree, 0x717-dword `movsd` copy) with **no corresponding code in the source at all**.

**5. `0xc0606600` (DKIOCFORMAT) switches on a different value with different logic.** Source:
```c
cmdType = data[0];                 // switch on data[0]: 1=start, 2=cylinder, 3=end
```
Reference (0xd90–0xda9):
```
d90  mov esi,[__dst]
d93  mov cl,[esi+0Ch]      ; byte at data+0x0C, NOT data[0]
d96  and ecx, 1Fh          ; masked to 5 bits
d99  cmp ecx, 0Dh(13); jz loc_E24
da2  jg loc_DB0
da4  cmp ecx, 7;  jz loc_DBC
da9  jmp loc_1050          ; default
db0  cmp ecx, 0Fh(15); jz loc_DEC
```
The reference switches on `(byte at data+0xC) & 0x1F` against `{7, 13, 15}`, not on `data[0]` against `{1, 2, 3}`. The branch bodies also don't correspond 1:1 to the source's three cases — e.g. the `ecx==13` branch (0xe24 onward) checks `deviceInfo+0x164` (capacity) is non-zero, calls `[deviceInfo isWriteProtected]`, calls the **no-argument** `[drive formatCapacities]` (note: no `data` argument here, unlike case `0x4020660a` above which does pass one), tests the capacity against the formatCapacities bitmask, then runs a full async op-queue/lock/wait sequence (alloc op type 3, `NXConditionLock`, queue insert, `lockWhen:`/`unlock`, then detach/reattach) — this is structurally different from and far more elaborate than the source's simple `[deviceInfo formatCylinder:cylinder data:formatData]` call for `cmdType==2`. The `ecx==7` and `ecx==15` branches toggle/inspect `deviceInfo+0x16C` in ways that don't map onto the source's `cmdType==1`/`cmdType==3` detach/attach handling either. Offset `0x168` (format-in-progress flag used by the guard clause) is used consistently between source and reference, but the case-13/7/15 dispatch built around offset `0x16C` and the byte-at-+0xC selector has no source equivalent.

**6. Guard-clause boolean structure differs (minor, but changes behavior in one state).** Source:
```c
if ((deviceInfo == nil || *(int*)(deviceInfo+0x168) == 0) &&
    (cmd != 0xc0606600) && (disk == nil))
    return ENXIO;
```
Reference (0x990–0x9ab):
```
990  test eax,eax (deviceInfo) ; jz loc_9A5        ; deviceInfo==nil -> skip cmd check, go straight to disk check
994  cmp [eax+168h],0 ; jz loc_9A5                  ; devInfo->0x168==0 -> also skip cmd check
99d  cmp ebx, 0C0606600h ; jz loc_9B8               ; only reached when deviceInfo!=nil AND ->0x168!=0
9a5  cmp [var_8],0 ; jnz loc_9B8                    ; disk!=nil -> continue
9ab  return ENXIO
```
This is `ENXIO if (deviceInfo==nil || devInfo->0x168==0 || cmd!=FORMAT) && disk==nil`, i.e. `cmd != FORMAT` is OR'd in alongside the nil-checks, not AND'd separately as in the source. They diverge when `deviceInfo != nil`, `deviceInfo->0x168 != 0`, `cmd != 0xc0606600`, and `disk == nil`: the reference returns ENXIO in this state; the source's version evaluates its `&&` chain to false and falls through to process the ioctl with a nil `disk`.

**7. Redundant `driveNumberOfDrive:` call (informational, non-behavioral).** The reference sends `[IOFloppyDisk driveNumberOfDrive:drive]` twice (0x94d–0x963 and again at 0x9b8–0x9ce) to recompute the same value; the source computes it once and reuses the variable. No observable difference since the value can't change between the two sends, but it is a genuine extra call-target the source doesn't reproduce.

**Clean matches within this function:** `DKIOCGGEOM` (0x40346601, ref 0x10f8) and `DKIOCSGEOM` (0x80046602, ref 0x108c) both match the source closely, including all struct offsets (`deviceInfo+0x164`, `+0x148`, `+0x14c`/geometry `+8/+0xc/+0x10/+0x14`, and the `data`/`ebx` field layout at `+4,+8,+0xc,+0x14,+0x18,+0x1c,+0x20,+0x24,+0x28,+0x2c,+0x2d,+0x30`).

---

No further divergences beyond the systemic `partition`-flag issue documented above were found in `_HandleBsdOpen` or `_HandleBsdClose` (both trace precisely to the pattern shown in the table above). `_fdminphys` (Bsd.m:509, ref 0x13c8) and `_HandleBsdSize` (Bsd.m:757, ref 0x1368) are exact instruction-for-instruction matches (same offsets `b_bcount`@+0x30, same `< 3` / `== 0` guard structure, same `[disk blockSize]` selector) — clean.

---

### `_fakeStrategySuccess` (Bsd.m:715, ref addr 0x55c)

The tail of the function (the `[deviceInfo completeTransfer:bp withStatus:IO_R_SUCCESS actualLength:bp->b_bcount]` call, using `bp+0x38`=`b_dev`, `bp+0x30`=`b_bcount`) matches the source exactly. However, between fetching `deviceInfo` and making that call, the reference performs two divisions that have **no counterpart in the source at all**:

```
5a1  mov  edi, [ecx+14Ch]        ; edi = deviceInfo->0x14c  (geometry pointer — same field HandleBsdIoctl calls "geometry")
5a7  mov  edx, [ebx+48h]         ; edx = bp+0x48
5aa  mov  eax, edx
5ac  xor  edx, edx
5ae  div  dword ptr [edi+10h]    ; (bp+0x48) / (geometry->0x10)   — result discarded
5b4  test edx, edx
5b6  jnz  loc_5CC
5b8  mov  eax, [edi+10h]
5bb  imul eax, [edi+14h]         ; geometry->0x10 * geometry->0x14
5bf  mov  [ebp+var_10], eax
5c2  mov  edx, [ebx+30h]         ; bp+0x30 (b_bcount)
5c5  mov  eax, edx
5c7  xor  edx, edx
5c9  div  [ebp+var_10]           ; b_bcount / (geometry->0x10 * geometry->0x14)  — result discarded
```

Both quotients are computed and then immediately overwritten/discarded (`eax` is reloaded at 0x5cc before the `completeTransfer:` call). The source has no equivalent code path touching `deviceInfo+0x14c`, `bp+0x48`, or performing any division. Because these are genuine `div` instructions, a zero divisor (`geometry->0x10 == 0`, or the product `geometry->0x10 * geometry->0x14 == 0`) would fault (`#DE`) in the real binary — a possible crash path with no source-level equivalent, not just dead code. The reconstructed source is missing this computation entirely.

---

### `_HandleBsdStrategy` (Bsd.m:799, ref addr 0x7f8)

Structurally a very close match: same three early-error constants (`-0x2c7`/`ENOTTY` init at entry, `-0x2c0` for `identifyResult==0`, `-0x44e` for `disk==NULL`, `-0x44d` for not-formatted), the `bufFlags & 0x4040000 == 0x40000` → `IOVmTaskForBuf` check, and the `bufFlags & 0x100000` read/write split with the exact `readAsyncAt:length:buffer:pending:client:` / `writeAsyncAt:...` argument mapping (`bp+0x48`=at, `bp+0x30`=length, `bp+0x3c`=buffer) all match source precisely.

One divergence: source's async-success shortcut is
```c
if (result == 0) {
    return;   // skips BOTH completeTransfer: and errnoFromReturn:
}
```
But the reference only skips `completeTransfer:` on success — it unconditionally falls through to the `errnoFromReturn:` call regardless of `result`:
```
8d3  test ebx, ebx
8d5  jz   loc_8EE        ; skips completeTransfer (8d7) but NOT errnoFromReturn (8ee)
...
8ee  push ebx            ; result (0 on success)
8ef  mov  ecx, paErrnofromretur
...
8fa  call objc_msgSend   ; [disk errnoFromReturn:result] — always executed, even when result==0
```
There is no early `ret` anywhere in this function's disassembly (only one `retn`, at the very end, address 0x907) — the source's `return;` on success has no counterpart; the reference always sends `errnoFromReturn:` before returning. Low severity since the return value is discarded either way (the source's own comment on the other `errnoFromReturn:` call notes this), but it is a genuine extra call on the success path.

---

### `_HandleBsdRead` (Bsd.m:890, ref addr 0x5ec)

The detach/fake-strategy path (`deviceInfo->0x168 != 0` → decrement, maybe reattach, `physio(fakeStrategySuccess, ...)`) and the normal path's `physio(HandleBsdStrategy, ...)` call both match the source precisely, including the `0xc030`-relative `deviceBuf` lookup and the `0x100000` (B_READ) flag.

**Divergence: wrong error code for "not formatted".** Source:
```c
isFormatted = [disk isFormatted];
if (!isFormatted) {
    return ENXIO;  // Device not formatted (0x16 = 22 = EINVAL in some contexts)
}
```
Reference:
```
6da  test al, al
6dc  jnz  loc_6E8
6de  mov  eax, 16h        ; EINVAL (22), NOT ENXIO (6)
6e3  jmp  loc_741
```
The reference returns `0x16` (EINVAL) when the disk isn't formatted; the source returns `ENXIO` (6). The source's own comment shows the author noticed the tension but wrote the wrong constant anyway. (Contrast with `_HandleBsdWrite` below, which gets this exact case right.)

---

### `_HandleBsdWrite` (Bsd.m:986, ref addr 0x74c) — clean

Every guard, constant, and call matches: `ENXIO` (6) for the three-way invalid-device guard, **`EINVAL` (0x16)** for not-formatted (correct, unlike `_HandleBsdRead`), and `physio(HandleBsdStrategy, deviceBuf, dev, 0, fdminphys, uio, blockSize)` with flag `0` for write. No divergence.

---

### `+[IOFloppyDisk blockDevOfDrive:]`, `+[IOFloppyDisk characterDevOfDrive:]`, `+[IOFloppyDisk driveNumberOfDrive:]` — clean

All three match the source exactly, including the bit tricks: `blockDevOfDrive:` computes `(driveNumber << 3) | 0x100` via `shl eax,3` + `or ah,1`; `characterDevOfDrive:` computes `(driveNumber << 3) | 0x2900` via `shl eax,3` + `or ah,29h`; `driveNumberOfDrive:` walks the 8-entry table at `_Drives` checking flags-bit-0 then the object pointer at `+4`, exactly as coded in Bsd.m:1134. No divergence.

---

### `+[IOFloppyDisk registerDrive:]` (Bsd.m:1199, ref addr 0x40) — clean

The `IOAddToCdevswAt` call matches argument-for-argument and order-for-order: `(0x29, HandleBsdOpen, HandleBsdClose, HandleBsdRead, HandleBsdWrite, HandleBsdIoctl, enodev, nulldev, seltrue, enodev, enodev, enodev)`. The `IOAddToBdevswAt` call likewise matches exactly: `(1, HandleBsdOpen, HandleBsdClose, HandleBsdStrategy, HandleBsdIoctl, enodev, HandleBsdSize, 0)`. Slot search, `IOMalloc(0x80)`/cleanup-on-failure ordering, `setBlockMajor:1`/`setCharacterMajor:0x29`, and the final flags/drive-pointer stores at `+0`/`+4` all match Bsd.m precisely. No divergence — this function is the clean baseline for the "device-switch registration" axis.

---

### `+[IOFloppyDisk unregisterDrive:]` (Bsd.m:1327, ref addr 0x1c8) — clean

`IOFree(deviceInfo, 0x80)` (offset `0xc030`) before `bzero(entry, 0x34)` (offset `0xc000`), `DrivesRegistered--`, and the conditional `IORemoveFromBdevsw(1)` / `IORemoveFromCdevsw(0x29)` all match Bsd.m exactly, same order, same major numbers. No divergence.

---

### `-[IOFloppyDisk attachBsdDiskInterfaceToDrive:]` (Bsd.m:1376, ref addr 0x2bc)

Several divergences here:

**1. Block/character major numbers are swapped between the two dev_t fields.** Source:
```c
blockDevMajor = [[self class] blockMajor];
*(int *)((char *)0xc028 + devInfoOffset) = (blockDevMajor << 8) | blockDevMinor;
charDevMajor = [[self class] characterMajor];
*(int *)((char *)0xc02c + devInfoOffset) = (charDevMajor << 8) | charDevMinor;
```
Reference:
```
335  mov ecx, ds:paCharactermajor     ; characterMajor selector used to fill the 0xC028 field
...
361  mov [ebx+0C028h], eax            ; (characterMajor << 8) | minor  stored at +0xC028
367  mov ecx, ds:paBlockmajor         ; blockMajor selector used to fill the 0xC02C field
...
38c  mov [ebx+0C02Ch], eax            ; (blockMajor << 8) | minor  stored at +0xC02C
```
The reference stores `characterMajor` into the field at `+0xc028` and `blockMajor` into `+0xc02c` — exactly reversed from what the source computes for those same two offsets. The minor-number half (`driveNumber*8`, computed once and reused for both fields via `lea esi,[edi*8]`) is correct in both.

**2. Wrong receiver for the "has dev info" check.** Source calls a boolean method on `drive`: `hasDevInfo = [drive _hasDevInfo];`. The reference instead sends the *same* getter selector (`paDevandidinfo`, the one used later for `_getDevInfo`) to **`self`**, not `drive`, and simply tests the pointer result for non-zero:
```
2fc  mov ecx, ds:paDevandidinfo
303  mov ecx, [ebp+self]      ; self, not drive (arg_8)
307  call objc_msgSend        ; [self <devAndIdInfo-getter>]
30f  test eax, eax
311  jnz  loc_398              ; non-nil -> "has info" (copy) branch
```
This selector is sent to `self` a total of three times in this function (0x307, 0x3a3, 0x3d3-area) to test-then-fetch-then-fetch-again the same value, where the source calls two conceptually distinct methods (`_hasDevInfo` on `drive`, `_getDevInfo` on `self`) once each. The receiver mismatch (self vs. drive) for the initial check is the behaviorally significant part.

**3. Return-value mismatches with `IO_R_SUCCESS`/`IO_R_INVALID_ARG`.** Source:
```c
if (driveNumber == -1) return IO_R_INVALID_ARG;
...
return IO_R_SUCCESS;
```
Reference:
```
2ee  cmp edi, 0FFFFFFFFh
2f1  jnz loc_2FC
2f3  xor eax, eax          ; returns 0 on the invalid-driveNumber path
...
3f7  mov eax, 1            ; returns 1 on the success path
```
Elsewhere in this same file, every other "success" return is realized as `xor eax,eax` (0) — consistent with `IO_R_SUCCESS == 0` — which makes `mov eax,1` here for the success path, and `xor eax,eax` (0) for the invalid-argument path, look inverted relative to the source's `IO_R_SUCCESS`/`IO_R_INVALID_ARG` constants (0 read as success elsewhere in this file, but here 0 is the *failure* path and 1 is *success*).

---

### `-[IOFloppyDisk detachBsdDiskInterfaceFromDrive:]` (Bsd.m:1448, ref addr 0x408)

Source returns `IO_R_SUCCESS` explicitly on both the invalid-`driveNumber` path and the normal path:
```c
if (driveNumber == -1) return IO_R_SUCCESS;
...
*flagsPtr &= 0xfd;
return IO_R_SUCCESS;
```
The reference never loads a fixed return constant anywhere in the function:
```
42f  cmp eax, 0FFFFFFFFh
432  jz  loc_442                      ; jumps straight to the epilogue — eax still holds -1 (the failed driveNumberOfDrive: result)
434  and byte ptr ds:_Drives[edx*4], 0FDh
442  mov esp, ebp
444  pop ebp
445  retn                             ; eax still holds driveNumber (0-7) here, not a success constant
```
The reference's "return value" is whatever `driveNumberOfDrive:` left in `eax` — `-1` on the invalid path, or the raw `driveNumber` (0–7) on the normal path — never the fixed `IO_R_SUCCESS` constant the source returns in both cases. Low practical impact since callers of this method in this file (the `DKIOCEJECT`/`DKIOCFORMAT` cases in `_HandleBsdIoctl`) don't inspect its return value, but it is a genuine divergence from the documented contract.


---

## Addendum — corrections from the final review

Recorded after the report was committed. The layer sections above are left as
written; where one of them is wrong, the correction is here rather than edited
into the original, so the record of what the analysis actually concluded is
preserved.

### Two findings the report missed

**`Bsd.m` dereferences the reference's `__DATA` link addresses as absolute
pointers.** The reference's `__DATA,__data` begins at `0xc000`, and five sites
transcribe link-time addresses from that section as integer constants:
`Bsd.m:1401` (`(char *)0xc008 + devInfoOffset`), `:1415` (`0xc028`), `:1422`
(`0xc02c`), `:1438` and `:1462` (both `0xc000`). In a relocatable driver
`__DATA` lands wherever `kl_ld` places it, so `bzero((char *)0xc008, 0x28)`
writes into low physical memory on the first BSD attach. Layer 5 analysed this
code and concluded "No divergence" — it compared the arithmetic and the order of
operations, which do match, without questioning the addresses themselves. The
repair is one file-scope table in `Bsd.m` replacing all five sites. This belongs
to fix phase 5 and is the most dangerous single item in this document.

**Ten symbols the kernel does not export.** The rebuilt driver referenced
`_DrivesRegistered`, `__IOExitThread`, `__IOForkThread`, `___kernel_map`,
`___page_mask`, `___page_size`, `___xxx`, `__dma_mask_chan`, `_floppyMalloc` and
`_vm_map_pmap` — none of which the kernel exports, so none could ever bind.
Most were the same spurious-leading-underscore defect the pre-pass fixed
elsewhere; `floppyMalloc` was `static` while being called across translation
units; `DrivesRegistered` and `__xxx` were declared and never defined; and
`vm_map_pmap` is a kernel macro whose only exported form is
`vm_map_pmap_EXTERNAL`. All ten are fixed. They went unnoticed because
`import_check.py` computed only reference-minus-rebuilt, which is structurally
blind to an *extra* undefined symbol; the tool now takes the kernel binary and
reports `unresolvable_imports` as well.

Fixing them exposed a further genuine defect. `FloppyArch.m:22-23` declared
`vm_map_pmap_EXTERNAL` with two parameters and `pmap_resident_extract` with one;
the kernel's are one and two respectively
(`src/kernel-7/vm/vm_map.c:2988`, `src/kernel-7/machdep/i386/pmap.c:1385`). The
one-parameter `pmap_resident_extract` calls at `FloppyArch.m:69` and `:193` were
therefore reading their `va` argument off the stack, yielding a wrong physical
address for every floppy DMA transfer. Corrected in the same pass.

### Three statements above that are wrong

- **Layer 2, finding 7** reports `kernelDiskMethodsNEW.m:77` calling
  `_errnoFromReturn:`. That was true when the analysis ran and was fixed before
  this report was committed; the line now reads `errnoFromReturn:`. The
  corresponding fix-phase task is a no-op.
- **Layer 4** speculates that `vFloppyCopy` and `physContBlocks` "likely" live in
  `FloppyVm.m`. There is no such file — `Request.m:11` imports `FloppyVm.h`, and
  both functions are in `FloppyDriveInt2.m`, covered by Layer 3.
- **`.objc_class_name_Protocol`** is attributed to the `objc_getClass` sites. It
  is not one of them: the reference's `__OBJC,__protocol` section is 140 bytes
  against our 0, so what is missing is a `@protocol` declaration, which is
  generic-disk-family work. Converting the `objc_getClass` sites restores
  `NXSpinLock` only, taking `missing_imports` from 3 to 2 rather than to 1.

### Scope of the "no function is absent" claim

The statement above that every function Apple compiled by hand has a counterpart
in our tree is a claim about **names**, and in those terms it holds: 224 of 225
reference symbols are present in the rebuild, and the source map resolves 222 to
a file and line. It is not a claim about completeness of implementation. Several
functions that are present by name diverge substantially in body — Layer 5 says
of one that "the source's implementation is fabricated relative to the binary."
Presence by name is the starting point for the fix phases, not evidence of
coverage.
