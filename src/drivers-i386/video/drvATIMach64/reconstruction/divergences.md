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

## BIOS transition reconstruction

- The BIOS wrapper, GDT descriptor setup/restore methods, and source-level
  protected-mode assembly are reconstructed from the IDA function bodies and
  exact reference byte ranges. The assembly verifier compares rebuilt
  instruction bytes, relocation targets, symbol sizes, and runtime-patched
  far operands once an i386 Mach-O artifact is available.
- The kernel loader makes executable mappings writable with
  `vm_protect(..., VM_PROT_ALL)`, which permits the two reference routines to
  patch their immediate far-transfer operands at runtime.
- Native test fixtures substitute `_ATIbios32`; they do not execute privileged
  transfers. This host lacks a C/Objective-C compiler and assembler, so neither
  those fixtures nor byte-for-byte assembly parity have been run yet. Guest
  build and hardware/ROM execution remain open verification steps.
- The public BIOS ROM scan, CRTC/VGA/aperture services, query paths, DPMS/APM,
  I/O-base lookup, refresh-rate query, and fixed invalid refresh-change result
  are implemented from their IDA bodies. Python source/evidence checks pass;
  the focused ObjC/C fixture remains uncompiled because `cc` is unavailable.
- `ATI(Private)` mode selection/validation, query-buffer replacement, VRAM
  probing, BIOS/PCI aperture verification, and three-range mapping rollback are
  now reconstructed in `ATIPrivate.m`. Their Python source checks pass; they
  still need the target Objective-C test harness and a rebuilt driver to prove
  runtime behavior and binary parity.
- The placeholder ATI implementation has been replaced by the recovered
  initialization, mapping policy, display-state transitions, and accessors.
  Lifecycle source checks pass, but runtime allocation/configuration traces
  and the target ABI remain unverified without the guest compiler/runtime.
- DAC programming, revision detection, gamma scaling, brightness bounds, and
  sparse/dense transfer-table handling are reconstructed in `ProgramDAC.m`.
  The DriverKit `ioPorts.h` primitive confirms each `outb` includes the
  reference `lock; incl` synchronization. Table counts that do not divide 256
  retain the truncated repetition count, and the reference's count-zero/negative
  hazards are not normalized away. Python checks pass; `make check-dac` cannot
  compile because `cc` is unavailable.
- The kernel-server preamble now includes all reconstructed Objective-C/C
  units and links the i386 assembly object through the historical
  `OTHERLINKEDOFILES` path. The stripped load-command file was restored with
  its `WIRE` directive, and a focused guest build script stages both the
  relocatable server and package archive. The actual build has not run: this
  checkout has no `vm/vm.conf`, and the Windows host has neither the guest
  connection nor the Rhapsody compiler.
