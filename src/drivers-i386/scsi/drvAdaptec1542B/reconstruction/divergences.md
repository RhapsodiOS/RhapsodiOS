# drvAdaptec1542B divergences

Reference: `Adaptec1542B_reloc`, SHA-256 `C4160F413776FF3559408BD802946EFB9624A249BF6CB0F2EAE6C212B0B40A24`
Analyses: IDA 9.2, Ghidra 12.1, angr 9.3.0 (angr not used as evidence per the task brief; it
over-segments this binary via `CFGFast` the same way it did for the bus drivers -- IDA found the
36 functions that exactly match the Mach-O symbol table, so IDA is treated as the authoritative
partition and Ghidra as a second opinion on bodies)

## Baseline build

This driver has **not been built**. There is no artifact under `out/i386/` for `drvAdaptec1542B`
(`out/i386/drvAdaptec1542B` does not exist), and `src/drivers-i386/README` lists
`drvAdaptec1542B - needs compiled and then tested`. This pass compares the reference binary's
disassembly directly against the checked-in source; there is no rebuilt binary to diff against,
so `rebuilt_sha256` in `ledger.json` is `null` for every entry. Nothing here should be read as
implying the driver has been compiled, linked, or run.

## Summary

| Bucket | Count |
| --- | --- |
| mapped | 34 |
| unmapped | 2 |
| duplicate_candidates | 0 |
| boundary_disputed | 0 |

Of the 34 mapped functions, 33 were read and compared instruction-by-instruction against the
source and found to match exactly (`assembly-matched` in the ledger). The 34th,
`-[AHAController ccbFromCmd:ccb:]` (1300 bytes, the largest function in the binary), was verified
instruction-by-instruction for its CDB opcode-group switch, its `cdb_ctrl` validation, and its
`pages == 0` DMA path; the `pages == 1` and `pages > 1` scatter/gather branches were checked
structurally (call targets, selectors, and the `aha_put_24` field writes) rather than traced
operand-by-operand, so it is recorded as `control-flow-confirmed` rather than `assembly-matched`.
No divergence was found anywhere in `ccbFromCmd:ccb:`, including the parts examined only
structurally.

**No behavioural divergence was found in any of the 34 mapped functions.** This matches the
task's framing: this driver is the most complete of the reconstructed SCSI drivers, and this pass
is a fidelity check rather than a reconstruction. The two unmapped entries are build-generated
Kernel Server glue, exactly as in the three bus drivers already examined.

Both analyzers agree closely across the whole binary: for every one of the 34 mapped functions,
IDA and Ghidra report byte-identical instructions, blocks, and (modulo Ghidra not resolving a
`target` address for PLT-style external calls the way IDA does, which IDA fills in and Ghidra
leaves `null`) call targets. No analyzer disagreement was found anywhere in this driver -- unlike
drvPCIBus's `test_M1` gap or drvEISABus's PnP-thunk region, there is no case here where one tool
sees a function the other does not.

## Method

Every function was read from `tools/binrecon/out/adaptec1542b/published/analysis-reference-ida.json`
using a small Python script against the scratch `binrecon` checkout (the in-tree
`tools/binrecon/binrecon/macho.py` was broken mid-edit by another agent during this pass and was
not touched or imported). Branch targets were resolved from the JSON's own `blocks[].successors`
list rather than by hand-computing hex jump displacements from the linear disassembly listing;
an early manual mis-read of two functions' control flow (corrected before being recorded here)
is the reason this method was adopted throughout instead of eyeballing `loc_XXXX` labels.

## Register and structure layout confirmed from disassembly

These are not divergences -- they are the concrete evidence, extracted while reading every
function, that the hand-written offsets in `AHATypes.h` and the ivar layout implied by
`AHAController.h`/`AHAControllerPrivate.h`/`AHAThread.h` match the compiled reference exactly.
Recorded here once instead of repeated in each finding below.

- **`struct ccb`** (declared in `AHATypes.h`): confirmed `sizeof(struct ccb) == 0x108` (264
  bytes) from three independent call sites (`IOFreeLow(ahaCcb, sizeof(struct ccb)*16)` using
  literal `0x1080`; `&ahaCcb[AHA_QUEUE_SIZE-1]` computed as `ahaCcb + 0xF78`; `ccbVirt += 0x108`
  in `aha_setup_mb_area`'s loop). Field offsets confirmed: `cdb_len`@2, `host_status`@0xE,
  `target_status`@0xF, `cdb`@0x12, `dmaList`@0xA0, `total_xfer_len`@0xE4, `mb_out`@0xE8,
  `startTime`@0xEC (8 bytes), `timeoutPort`@0xF4, `cmdBuf`@0xF8, `in_use`@0xFC, `ccbQ`@0x100 --
  every one of these lines up exactly with the field order declared in the header.
- **`aha_mb_t`**: `mb_stat`@0, `ccb_addr[3]`@1-3 (4 bytes total), confirmed from
  `aha_setup_mb_area`'s `aha_put_24` calls and `AHA_MB_CNT`(16)`*4 == 0x40` used as the
  `mb_in`-within-`aha_mb_area` offset.
- **`AHACommandBuf`** (declared in `AHAControllerPrivate.h`): `op`@0, `scsiReq`@4, `buffer`@8,
  `client`@0xC, `result`@0x10, `cmdLock`@0x14, `link`@0x18 -- confirmed from
  `executeRequest:buffer:client:`'s local-struct field writes and `commandRequestOccurred`'s
  `queue_remove`/switch-on-`op` code.
- **`AHAController` ivars**: `config`@0x244 (`dma_channel`@0x244, `irq`@0x245,
  `scsi_id:mbz`@0x246 -- matching the packed-bitfield declaration), `ioBase`@0x248,
  `ahaBoardId`@0x24A, `ioThreadRunning`@0x24B, `ahaMbArea`@0x24C, `ahaCcb`@0x250,
  `numFreeCcbs`@0x254, `commandQ`@0x258, `commandLock`@0x260, `outstandingQ`@0x264,
  `outstandingCount`@0x26C, `pendingQ`@0x270, `dmaLockCount`@0x278, `maxQueueLen`@0x27C,
  `queueLenTotal`@0x280, `totalCommands`@0x284, `interruptPortKern`@0x288 -- every ivar in
  `AHAController.h`'s declared order lines up with a distinct, correctly-ordered offset.
- **Register bitfields** (`AHATypes.h`): `aha_stat_reg_t.dataout_full` (bit 3, mask `0x08`),
  `.datain_full` (bit 2, `0x04`), `.cmd_err` (bit 0, `0x01`), `.idle`/`.mb_init_needed` (bits
  4/5, combined mask `0x30`); `aha_intr_reg_t.cmd_done` (bit 2, `0x04`), `.mb_in_full` (bit 0,
  `0x01`); `aha_ctrl_reg_t.sw_rst` (bit 6, `0x40`), `.scsi_rst` (bit 4, `0x10`), `.intr_clr`
  (bit 5, `0x20`) -- every mask used in the disassembly's `test`/`and`/`out` sequences matches
  the header's bitfield declarations exactly, including `isPCIPresent`-style De Morgan
  rewrites (e.g. `aha_reset_board`'s `while (!stat.idle || !stat.mb_init_needed)` compiled as
  `(stat & 0x30) != 0x30`).
- **Command opcodes and constants**: `AHA_CMD_INIT`(1), `AHA_CMD_START_SCSI`(2),
  `AHA_CMD_DO_INQUIRY`(4), `AHA_CMD_GET_CONFIG`(0xB), `AHA_CMD_GET_BIOS_INFO`(0x28),
  `AHA_CMD_SET_MB_ENABLE`(0x29), `AHA_MB_OUT_START`(1), `AHA_CCB_INITIATOR_RESID`(3) -- all
  confirmed as literal immediates at the disassembly's `aha_put_cmd`/`ccb->oper` write sites.
  `AHAOp` (`AO_Execute`=0, `AO_Reset`=1, `AO_Abort`=2) and `completeStatus` (`CS_Complete`=0,
  `CS_Timeout`=1, `CS_Reset`=2) enum values are confirmed from the `switch`/`cmp` sequences in
  `commandRequestOccurred`, `timeoutOccurred` and `commandCompleted:reason:`.

## Cosmetic-only difference: missing diagnostic-access counter

**Source:** `AHARoutines.m` (`aha_start_scsi`, `aha_probe_cmd`, `aha_cmd`, `aha_reset_board`);
`AHAController.m` (`interruptOccurred`); `AHAThread.m` (`threadResetBus:`).

**Reference behaviour:** after every hardware register write performed through
`aha_put_cmd`/`aha_put_ctrl` (i.e. every `outb` to the command or control register), the
reference does `inc ds:_xxx_N` -- a global counter with no resolved symbol name (IDA could not
name it). This appears once per `outb` site: once in `aha_start_scsi`, three times in
`aha_probe_cmd` (once per `outb`: the command byte, each argument byte in the `arglen` loop, and
the `aha_clr_intr` write), three times in `aha_cmd` (the same three-site pattern), twice in
`aha_reset_board` (the `sw_rst` write and the `aha_clr_intr` write), and once each in the inlined
`aha_clr_intr`/`aha_put_ctrl` call sites inside `interruptOccurred` and `threadResetBus:`. Each
of the functions above uses a numerically distinct global (`_xxx_86`, `_xxx_100`, `_xxx_102`,
etc. by disassembly address), consistent with one counter variable per compiled `outb`/`outl`
call site rather than one shared counter.

**Our source:** issues the identical `outb` sequences on the identical ports/values, with no
counter anywhere.

**Disposition:** accept

**Rationale:** this is the same finding as drvEISABus's Finding 6
(`src/drivers-i386/bus/drvEISABus/reconstruction/divergences.md`) -- a per-write internal
diagnostics/statistics counter with no resolved name and no effect on device behaviour. It is
the *only* difference found anywhere in this driver's 34 mapped functions, and it does not
change control flow, register values written to hardware, or any value the driver returns to a
caller. Recorded here rather than left unmentioned because every function that touches hardware
registers was checked instruction-by-instruction and this is the one place a literal
byte-for-byte match does not hold.

## Note: `for (q = &outstandingQ; q != &pendingQ; q = &pendingQ)` only ever processes `outstandingQ`

**Source:** `AHAThread.m` `-threadResetBus:` (line 110) and `-timeoutOccurred` (line 414, as
`for (queue = &outstandingQ; queue != &pendingQ; queue = &pendingQ)`).

Both functions loop over "the outstanding queue, then the pending queue" using a two-value for
loop whose increment sets the loop variable directly to the terminating sentinel value
(`&pendingQ`). Standard C `for` semantics check the loop condition *before* running the body on
each pass, including the pass immediately after the increment -- so once the increment sets
`q = &pendingQ`, the very next condition check (`q != &pendingQ`) is false and the loop body
never runs a second time. In practice this means these two loops only ever drain `outstandingQ`;
`pendingQ` is never touched by either of them, despite the source's shape suggesting it processes
both queues.

This is **not a reconstruction divergence** -- it was checked against the reference's compiled
block structure (verified via `blocks[].successors` in both functions) and the reference
exhibits exactly the same behaviour: the block that follows draining `outstandingQ` flows
directly to the post-loop code, never back through a second pass with `q == &pendingQ`.
Our source and the reference agree perfectly here; this is presumably an artifact already
present in NeXT's original 1993 source (not something introduced by this reconstruction), and is
noted only because it is easy to misread as a bug in the reconstruction when it is in fact a
faithfully-reproduced property of the shared C source. No disposition is recorded because there
is no divergence to act on.

## Functions examined with no divergence found

Instruction-level match (`assembly-matched` in the ledger, all 33): `+[AHAController probe:]`,
`-[AHAController initFromDeviceDescription:]`, `-[AHAController maxTransfer]`,
`-[AHAController free]`, `-[AHAController numQueueSamples]`,
`-[AHAController sumQueueLengths]`, `-[AHAController maxQueueLength]`,
`-[AHAController resetStats]`, `-[AHAController executeRequest:buffer:client:]`,
`-[AHAController resetSCSIBus]`, `-[AHAController interruptOccurred]`,
`-[AHAController interruptOccurredAt:]`, `-[AHAController otherOccurred:]`,
`-[AHAController receiveMsg]`, `-[AHAController timeoutOccurred]`,
`-[AHAController commandRequestOccurred]`, `-[AHAController probeAtPortBase:]`,
`-[AHAController executeCmdBuf:]`, `_aha_start_scsi`, `_aha_probe_cmd`, `_aha_cmd`,
`_aha_reset_board`, `_aha_setup_mb_area`, `_aha_unlock_mb`,
`-[AHAController threadExecuteRequest:]`, `-[AHAController threadResetBus:]`,
`-[AHAController runPendingCommands]`, `-[AHAController commandCompleted:reason:]`,
`-[AHAController allocCcb:]`, `-[AHAController freeCcb:]`,
`-[AHAController completeDMA:length:]`, `-[AHAController abortDMA:length:]`, `_ahaTimeout`.

Control-flow-level match (`control-flow-confirmed` in the ledger): `-[AHAController
ccbFromCmd:ccb:]` -- see "Summary" above for exactly which parts were traced instruction-by-
instruction versus checked structurally.

## Unmapped: build-generated

`+[Adaptec1542BKernelServerInstance kernelServerInstance]` and
`+[Adaptec1542BVersion driverKitVersionForAdaptec1542B]` -- emitted by the Kernel Server project
type and `Load_Commands.sect`, not written by hand. Accepted, same as the equivalent pair in
drvPCIBus, drvPCMCIABus and drvEISABus.

## What was not attempted

This pass compared disassembly against source; it did not attempt to build the driver, run it,
or verify its behaviour against real or emulated AHA-1542B hardware. The task's own framing
(34 of 36 functions already mapped, our source defines nothing the reference lacks) held up
under this pass -- no fix pass is warranted, since no divergence with any observable behavioural
effect was found.

## Intentional divergence: clamp `currentTime - ccb->startTime` in `commandCompleted:reason:` (issue #28)

2026-09-26. `AHAThread.m`'s `commandCompleted:reason:` computes
`scsiReq->totalTime = currentTime - ccb->startTime` on the unsigned 64-bit
`ns_time_t` from `IOGetTimestamp()`. A backward clock step between the CCB's
`startTime` stamp and this read (see issue #26 -- rare, not fully closed
under heavy load) wraps that subtraction to roughly `1.8e19` ns instead of a
small delta. `totalTime` is now clamped to 0 when `currentTime <=
ccb->startTime`. Not a reconstruction fidelity finding against the reference
binary -- the disassembly for this site was not re-examined for this
behavior; recorded here because it changes behavior at a function this
document otherwise lists as `assembly-matched` against the reference.
