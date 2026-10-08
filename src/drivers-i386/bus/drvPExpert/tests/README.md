# i386 platform expert checks

## ACPI parser

These checks compile the production parser into a host executable. The physical
mapping stub is unused by the tested routines; no firmware or port I/O runs.
The test covers valid discovery data, bad checksums, RSDP length validation,
truncated MADT headers and entries, and processor IDs beyond xAPIC's range.

From this directory, on Rhapsody:

```sh
cc acpi_parser_test.c -o /tmp/acpi-parser-test
/tmp/acpi-parser-test
```

On a modern host with Clang:

```sh
clang -std=gnu89 -Wno-int-to-pointer-cast acpi_parser_test.c -o acpi-parser-test
./acpi-parser-test
```

A successful run prints ten PASS lines and `0 failures`. These tests do not
verify interrupt delivery, clock calibration, processor startup, or booting.

## Physical mappings

Build and run `physical_mapping_test.c` the same way as the parser test (add
`-Wno-pointer-to-int-cast` on a 64-bit host). It includes the production mapper
and substitutes the VM calls. The i386 kernel uses 8 KB VM pages, although its
hardware pages are 4 KB. The checks cover VM reservations, aligned physical
and virtual addresses, page counts, and returned byte offsets for consecutive
firmware mappings. This test reproduces the mapping overlap that caused the
first configured kernel boot to panic.

## SMP trampoline execution

Assemble `../i386/smp_tramp.s` with the native Rhapsody assembler, then run:

```sh
python smp_trampoline_test.py smp_tramp.o /tmp/smp-trampoline-test
```

This requires `qemu-system-i386` on PATH (or the `--qemu` argument). It creates
a disposable floppy fixture and executes the actual native trampoline with
ESP reset to zero, identity and kernel mappings, and code/data segments based
at `0xc0000000`. The final entry checks its stack argument. The original
trampoline faults before reaching that entry; the patched trampoline prints
PASS. This checks the transition and stack setup, not AP startup IPIs or the
kernel's SMP lifecycle.

## Optional boot-path regressions

The three Python generators below extract the affected production functions
and clock storage into small C fixtures. Generate them on a host with Python,
then compile and run the generated files with native Rhapsody `cc`:

```sh
python clock_width_test.py clock-width-test.c
python lapic_calibration_test.py lapic-calibration-test.c
python acpi_shutdown_test.py acpi-shutdown-test.c
cc clock-width-test.c -o clock-width-test && ./clock-width-test
cc lapic-calibration-test.c -o lapic-calibration-test && ./lapic-calibration-test
cc acpi-shutdown-test.c -o acpi-shutdown-test && ./acpi-shutdown-test
```

The clock test covers 32-bit LAPIC countdowns, fractional ticks, reloads,
repeated reads and the original PIT source. Calibration substitutes a running
hardware clock and an inaccurate spin delay, including sample overshoot and a
stopped reference clock. The shutdown test checks that a power-button SCI
acknowledges the event and requests both halt and powerdown with public SDK
headers. Hardware boot, timing and actual power-off are separate runtime checks.
