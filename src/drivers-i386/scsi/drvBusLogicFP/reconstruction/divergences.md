# Divergences and reference-derived test expectations

## Analyzer disagreement

The reference-only binrecon run completed with IDA 9.4 and angr 9.3.0. Consensus labels reference evidence `disputed` due conflicting function-boundary and reference claims; its 329 analyzer groups are not a one-to-one function inventory. IDA identifies 123 named ranges and the text symbol partition confirms those names. Ledger entries therefore begin unexamined and carry a partial agreement status; no analyzer consensus is claimed.

## Request path expectations from IDA

- At `0x0668`, the controller clears exactly 48 bytes in the request command record, writes request/buffer/client at offsets 4/8/12, invokes `executeCmdBuf:` and returns status at offset 16.
- At `0x10c0`, an invalid CDB control byte sets status 7 and returns without queuing; data translation failure sets status 14. Split data into page-bounded entries and cap the scatter/gather list at 17 entries. Exact address and transfer-count cases will be recorded before controller assertions are written.
- At `0x13e8`, completion reason and host/SCSI status mappings are as listed in `abi.md`; normal completion unlinks the SCCB before setting residual and status.

## Not yet measured

The binary-derived ordered port traces and state transitions for shared IRQ, timeout/abort/reset, unexpected SCSI messages, negotiation, SCAM termination, and EEPROM polling have not yet been recorded. These paths must be examined in IDA assembly/decompilation before assertions are added. This file deliberately does not invent test outcomes from Linux-derived code.

## Shared IRQ and timeout expectation from IDA

For a card with base port `B`, shared-IRQ probe access is exactly one byte read at `B+55`, then mask bit `0x20`. With the bit clear, no `SccbMgr_isr` call occurs. With the bit set, the ISR follows the read. If `levelIRQ` is true, the interrupt-enable message occurs after either branch. This follows `interruptOccurred` (`0x06ec`) and `SccbMgr_my_int` (`0x4938`).

Timeout scanning at `0x07d4` takes one timestamp and walks outstanding nodes in list order. A node expires at or after its deadline, is unlinked and decremented before reason-1 completion; one or more expirations trigger one bus-reset request after the scan. Tests must assert ordering as well as final statuses.

## Protocol and configuration trace expectations from IDA

- `scsiDecodeMsg` (`0x5b2c`) routes extended message `1` into the parser. The parser accepts length/type `(3,3)` for sync negotiation and `(2,2)` for wide negotiation; any other pair sets message status 7 and rejects. Unknown messages set host status 20, message status 7, wait for the bus handshake bit at `B+68` to clear, then write `0x0a` there. The `B+101 <- 0x28` reject command is reached for codes `8` and `>0x7f`. One acknowledgement value appears undefined in Hex-Rays output; get that expected byte from the instructions before making a mock assertion.
- Sync selector output for target 0 is `OUT B+96`; target 15 is `OUT B+87`. Negotiated byte follows the selected port write and is stored at target-state offset 208. Sync/wide initiator negotiation writes a fixed ordered register program; timing class 0..3 changes only the value at `B+142` among `0x8600`, `0x8632`, `0x8619`, `0x860c`.
- `utilEERead(B,address)` clocks exactly 16 samples from `IN B+34 & 1`, returning bits MSB first; it does not poll for ready during the sample loop. Each serial output bit uses `OUT B+34` with data/clock/clock-low in order. `utilEEWrite` sends command 5 and 16 data bits MSB first, calls `Wait(B,7)`, and returns the register to idle. `utilEESendCmdAddr` clocks a three-bit opcode and 8 or 10 address bits according to `IN B+41 & 0x10` (start bit `0x80` or `0x200`, shifted through bit 0); this replaces the preliminary notes' incorrect two-bit/7-or-9 interpretation.
- `ScamInit` inspects 8 or 16 IDs based on `IN B+41 & 0x10`; EEPROM word 10 bit 2 triggers bus reset, one-second wait, arbitration until success, then selection and assignment. Both arbitration line waits and retry-until-success are unbounded in the reference. A reconstruction must preserve observed limits rather than invent a timeout.


## Concrete request, abort and SCSI-path fixtures

For page size 4096, the direct helper at `0x1914` returns false for `(0x1000,260)` and `(0x1efc,260)`, and true for `(0x1efd,260)`. In `sccbFromCmd:` at `0x10c0`, the virtual range `(0x10ffd,4)` spans two pages; after successful mapping it produces two SG entries with lengths 3 and 1, starts at SCCB byte 100, has SG byte count 16 at SCCB byte 4/8 fields, and increments the command's mapped byte count by 4. An aligned `18*4096` request computes 18 pages but caps the emitted list at 17 entries, each 4096 bytes, so the initialized transfer is 69,632 bytes; the unrepresented final page remains outside that initial SG transfer and must be reflected by completion residual handling. A zero-length request takes the single/direct opcode-3 path and sets data length and data pointer to zero. For a CDB group with either low control bit set, status 7 is set and there is no manager start. A failed sense-buffer translation logs and uses sense length 1 but continues; a failed data-buffer translation sets status 14 and rejects.

`SccbMgr_abort_sccb` at `0x484c` takes the manager lock at manager-info `+4`, reads `IN B+41`, and returns `-1` after unlock if bit `0x08` is set. For a queued SCCB it calls `queueFindSccb`, unlocks, decrements the active word at manager-info `+12`, and if that reaches zero writes `IN B+12 & 0xfc` back to `B+12`; then it sets SCCB byte `+48` to 2 and calls the function pointer at `+40`. If it is not queued and not the currently active SCCB at card `+0`, it scans at most 33 disconnected slots and returns `-1` if absent; otherwise it returns 0.

In `scsiDecodeMsg` at `0x5b2c`, extended-message prefix byte 1 first acknowledges the bus, then `scsiHandleExtMsg` reads length and type. `(3,3)` enters target sync negotiation; `(2,2)` enters target wide negotiation. Unknown pairs store status 7, wait for the handshake bit at `B+68` to clear, write `2` to `B+68`, then reject with `0x0a` to `B+68` and `0x28` to `B+101`. For EEPROM reads, `utilEERead(B,0)` calls command/address transfer with command 6/address 0 and reads exactly 16 bits; SCAM first reads address 10, and an EEPROM value with bit 2 clear skips the reset/arbitration/assignment block in `ScamInit`.
