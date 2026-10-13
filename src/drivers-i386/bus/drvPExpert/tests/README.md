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

## APIC masks and deferred interrupts

Compile `apic_mask_test.c` with native `cc`. It includes the production APIC
controller with simulated I/O APIC entries and inputs. Fourteen checks cover edge
retention during priority masking, explicit disable/re-enable, level masking,
and trigger-mode changes, missing PCI routes, failed mappings, unsupported
local APIC modes/addresses, missing PIT routing and partially usable I/O APIC
sets. Rejected admission leaves firmware interrupt routing untouched. No privileged port
instructions are executed.

Compile `ioapic_probe_test.c` with native `cc` to check the production chip
probe. Zero/all-ones version reads reject an absent chip without writing its
entries; a valid 24-pin chip is initialized and masked only after admission.

Compile `mptable_routes_test.c` with native `cc` for nine production MP routing
checks: missing PCI assignments, valid lookup, unknown controllers, pins/GSI
outside the supported range, unsupported PCI bus IDs and truncated entry lists.

Generate and run the kernel deferral fixture:

```sh
python interrupt_deferral_test.py interrupt-deferral-test.c
cc interrupt-deferral-test.c -o interrupt-deferral-test
./interrupt-deferral-test
```

It extracts the production masking and dispatch functions, substituting CPU
interrupt controls and a capture controller. Nine checks cover enable changes
under a raised IPL, multiple deferred IRQs at the same priority, upper IRQ
bits, exactly-once draining and a nested edge deferred until interrupt return.
Mixed edge/level cases check that a lower-priority edge arrival preserves the
hardware mask of a higher-priority level input while pending or in service.
Actual edge delivery and disk integrity are verified separately by traced
QEMU boots and a 32 MiB write/fsync/readback workload.

## Automatic selection and capability limits

Generate `automatic_selection_test.c` with `automatic_selection_test.py` and
`platform_capability_test.c` with `platform_capability_test.py`, then compile
both with native `cc`. Run the selection executable once per case, numbered
0 through 12; run the capability executable without arguments.

The selection fixture extracts actual kernel defaults and includes production
`pexpert.c`. It checks activation without flags, each zero override, failed
initializers, APIC-dependent clock/AP startup, single-CPU behavior and one-time
initialization. Privileged initializers are replaced by controlled outcomes;
this verifies selection, not hardware presence. The capability fixture extracts
production MSR-base admission and AP-startup bounds; only MSR instructions and
AP launch are simulated. It covers x2APIC/high addresses, enabling xAPIC and a
retained CPU list that omits the BSP. Actual detection, parsing of overrides,
timing and disk interrupt delivery are checked separately in QEMU.
