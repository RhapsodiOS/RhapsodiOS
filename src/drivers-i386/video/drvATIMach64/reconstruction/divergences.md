# drvATIMach64 divergences and decisions

## Reference-only baseline

- Stock BinRecon/IDA 9.4 analysis is complete and reports 52 functions. Its normalized-function acceptance is false because there is no rebuilt artifact.
- Reviewed IDA export corrects the two omitted assembly functions by exact symbols, decodes complete far-transfer instructions at `0x273d` and `0x2811`, and records exclusive ends `0x2755` and `0x2883`. The corrected export contains 54 functions.
- No reference/rebuilt parity conclusion is available yet.
- The current source skeleton does not match the recovered `ATI` class/category symbols; initial source mapping therefore remains unresolved and is not counted as implementation coverage.
- No compatible hardware or ROM execution has been performed.

## ABI and data recovery

- IDA metadata fixes the `ATI` object extent at 620 bytes (552-byte inherited
  extent plus the 68-byte own-ivar tail) and `ATI_BIOS` at 16 bytes. Exact
  offsets and recovered declarations are recorded in `abi.md`.
- Static fixtures cover all 54 `IODisplayInfo` records, all 15 30-byte CRTC
  records, both gamma arrays, and all recovered named-value tables. Python
  comparisons pass against IDA's original-byte and relocation-derived export.
- Host-side mock C checks were attempted through GNU Make 4.4.1, but this
  Windows host has no `cc`, `clang`, `gcc`, or `cl` executable. Native C and
  target i386 compilation remain unverified until the configured Rhapsody
  guest toolchain is available.
