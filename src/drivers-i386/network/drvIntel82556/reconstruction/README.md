# Intel82556 i386 reconstruction

The driver source covers the complete handwritten implementation of the
68,284-byte `Intel82556NetworkDriver_reloc` supplied in
`Drivers/i386/Intel82556NetworkDriver.config`. Its SHA-256 is
`C26B34F0A07346F20C1D51795C601BED436CF3BE20E0AB6882E98C9114508B72`.

This is a source reconstruction reviewed against IDA disassembly. Strict
BinRecon normalized-function acceptance remains **FAIL**; this is not a
byte-identical rebuild or a claim of hardware validation.

## Coverage and recovered contracts

| Component | Reference functions | Source |
|---|---:|---|
| Shared engine and memory/reset helpers | 60 | `Intel82556.m` |
| Buffer pool and wrapper callbacks | 6 | `Intel82556Buf.m` |
| EISA adapter and IRQ table helper | 13 | `IntelPRO100EISA.m` |
| PCI adapter | 11 | `IntelPRO100PCI.m` |
| Generated kernel-server instance/version | 2 | `CreateKLLDInstance.sh` |
| Total | 92 | 90 handwritten, 2 generated |

`source-map.json` accounts for every reference function once, without missing,
duplicate, or disputed entries. The two generated functions map to their
actual generator in `src/driverTools-1`, not handwritten substitutes.
`ledger.json` records source-to-reference review at `control-flow-confirmed`;
that status does not override the failed binary comparison.

The original superclass is `IOEthernet`, with `IOPower` protocol conformance.
Its 38 driver ivars begin at offset `0x174`; its complete i386 instance is
512 bytes. `Intel82556Buf` has ten own ivars and a 40-byte instance. Neither
adapter adds ivars. Native layout tests check these against the real guest
DriverKit superclass, rather than inserting padding to imitate it.

The reconstructed DMA layouts are SCP 12, ISCP 8, SCB 44, self-test result 8,
TCB 68, TBD 16, RFD 72, and RBD 28 bytes. Hardware fields are volatile;
separate byte/word writes observed in the original are retained. `I556Dump`
preserves the 88-byte dump area as bytes instead of guessing unnamed bitfields.

Private selectors use one underscore. Debugger receive takes a length pointer
and returns `void`; debugger send also returns `void`. The port, latch,
DBRT and MAC-address hooks preserve their original return conventions. Buffer
allocation and recycling use the recovered ownership, guard words, and deferred
free behavior. Runtime class lookups have been replaced by the original direct
class references. The C helper names drop exactly one Mach-O underscore.

IDA recovered all 92 function boundaries and now decompiles all 92 functions.
Initially six functions failed: `_hwInit`, debugger receive, and both adapters'
`resetPLXchip`/`lockDBRT`. Reviewed import declarations and stack reanalysis fixed
these failures without modifying binary bytes. `ida_annotations.py` repeats
the type corrections, adds source links, and exports the pseudocode. All source
implementations were also reviewed directly against assembly.
The empty base adapter hooks are present in the reference and are intentional.

## Build and tests

The Aggregate, Driver and Kernel Server projects now build the four actual
source files. The EISA and PCI tables, strings, help resources, server instance,
version 2 and WIRE load commands are restored. The unrelated userspace inspector
executable and nib are not reconstructed or bundled.

The native verification uses Apple cc-771.4 (GCC 2.7.2.1), `gnumake`,
`pb_makefiles`, and `kl_ld` in a private QEMU snapshot of the bootstrapped
Rhapsody image. Its page size is **8192**, and the 7436-byte control/descriptor
arena fits the original one-page allocation. No shared guest or base disk is
modified. `vm/build-i386-intel82556.sh` builds, runs the native tests, stages
installation, and archives the result under `/build/codex-drvintel82556`.

The original sources fail native compilation and contain only four of eight
required core-test selectors. Reconstructed source passes native compilation,
pool ownership tests, reference layout checks and core behavioral tests.
See [tests/README.md](tests/README.md) for test scope and commands. Mocked tests
exercise source behavior; they do not test real DMA, interrupts or PHY operation.

An installed `.config` archive is produced. The repository's APK recipe is
restored, but an `rbuild` APK run is blocked by a missing `cc` dependency package
in this guest's package repository; the native build and staged install succeed.

## Reproduce binary evidence

From the repository root, using `.venv-binrecon/Scripts/python.exe`:

```powershell
$env:PYTHONPATH = 'tools/binrecon'
$env:BINRECON_REFERENCE = 'C:/path/to/Intel82556NetworkDriver_reloc'
$env:BINRECON_REBUILT = 'C:/path/to/rebuilt/Intel82556NetworkDriver_reloc'
& .venv-binrecon/Scripts/python.exe -m binrecon analyze `
  --profile tools/binrecon/profiles/intel82556-compare.json
& .venv-binrecon/Scripts/python.exe `
  src/drivers-i386/network/drvIntel82556/reconstruction/verify_evidence.py `
  --reference $env:BINRECON_REFERENCE --rebuilt $env:BINRECON_REBUILT `
  --analysis tools/binrecon/out/intel82556-compare/published/analysis-reference-ida.json
```

The reference-only profile is `tools/binrecon/profiles/intel82556.json`.
It exits 1 with `complete: true` because it has no rebuilt input. The comparison
profile also exits 1 when normalized functions differ. Neither is relabeled PASS.
Use `verify_evidence.py --refresh` after source line changes; it validates the
reference hash and full partition with BinRecon's semantic source-map loader.
With a rebuilt input it also checks the complete Objective-C method inventory
and kernel import set for equality.

Generated binaries, IDBs, assembly exports, comparisons and logs remain in
ignored `tools/binrecon/out/intel82556` and `intel82556-compare` directories.
See [validation.md](validation.md) for the final artifact identity and results.

## Preserved reference behavior

Reconstruction deliberately preserves several unusual paths: failed `hwInit`
can retain the dump allocation; an oversize receive schedules reset and returns
without releasing the debugger lock; failed transmit address translation drops
the descriptor until list reset; debugger send copies at least 64 bytes; and
debugger receive reports a length including CRC. These are visible in the
reference disassembly, not newly designed recovery policies. Modernizing them
would be a separate behavioral change.
