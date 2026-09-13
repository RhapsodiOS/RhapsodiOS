# i386 SCSI drivers: reconstruction status

Findings from comparing our sources against Apple's shipped `*_reloc` binaries
with `tools/binrecon`. The headline is that the eight drivers are not eight
partial reconstructions at different stages. Two are essentially complete, one
is reconstructed against its reference and guest-compiled, one is a modern
addition with no reference, and the other four are stubs — and one of those
(`drvSym53C8xx`) is still built on the wrong hardware model.

## Coverage

Resolved counts are defined `__TEXT,__text` symbols in the reference that
resolve to a definition in our source, after correcting the class-name
divergence described below. The two build-generated symbols every driver has
(`+[<Name>KernelServerInstance kernelServerInstance]` and
`+[<Name>Version driverKitVersionFor<Name>]`) are emitted by the Kernel Server
project type and are correctly absent from source.

| Driver | Reference | Resolved | Status |
| --- | --- | --- | --- |
| drvAdaptec1542B | 36 | 34 | complete; only build glue absent |
| drvBusLogic | 37 | 35 | complete; only build glue absent |
| drvAdaptec6X60 | 79 | 77 | reconstructed against the reference; guest `_reloc` produced; not hardware-tested |
| drvDPT2000 | 55 | 10 | stub; missing the `EATASCSIBus` class |
| drvBusLogicFP | 123 | 7 | stub |
| drvSym53C8xx | 158 | 12 | stub, wrong architecture |
| drvAdaptec2940 | 170 | 10 | stub; missing the `SCSIBus` class |

`drvAMDPCSCSIDriver` has no reference bundle. It is a modern addition rather
than a reconstruction and is out of scope here.

## The class-name divergence

Four of the seven still name their principal class differently from the
reference. This is the same pattern already resolved in drvPCMCIABus, and it
is why those drivers initially resolved **zero** symbols — a total mismatch
rather than a partial one.

| Driver | Ours | Reference |
| --- | --- | --- |
| drvAdaptec6X60 | `AIC6X60` | `AIC6X60` |
| drvBusLogic | `BLController` | `BLCController` |
| drvBusLogicFP | `BusLogicFPSCSI` | `BLFPController` |
| drvDPT2000 | `DPTSCSIDriver` | `EATAController` |
| drvSym53C8xx | `SYM53c8Controller` | `SYM53c8` |

drvAdaptec1542B (`AHAController`), drvAdaptec6X60 (`AIC6X60`), and
drvAdaptec2940 (`Adaptec2940`) already match. The `(PrivateMethods)` and `(IOThread)` category split is correct in
every driver, and the `*Controller.m` / `*Routines.m` / `*Thread.m` file
layout mirrors it — that part was reconstructed well throughout.

Renaming is necessary but sufficient only for drvBusLogic, where it took the
count from 26 to 30 and left five genuinely missing functions.

## The architecture problem

`drvAdaptec6X60` used to implement an AHA-154x mailbox instead of the AIC-6X60
HIM; that rewrite is done (see below). `drvSym53C8xx` still implements a
different hardware interface from the chip it targets.

### drvAdaptec6X60

Reconstructed against `AIC6X60SCSI_reloc`. The AHA-154x mailbox clone
(`AIC6X60Routines.m`, `aic_cmd`, `allocCcb:`, `runPendingCommands`) is gone.
The live tree is a DriverKit `AIC6X60` class plus an Adaptec HIM
(`HIM6X60.c`) and SCSI sequencer (`AIC6X60Sequencer.c`) that program
AIC-6260/6360 ports directly: selection, reselection, message and data
phases, SDTR, PIO and DMA. 77 of 79 reference `__text` functions map; the
two absences are Kernel Server glue. A guest `Adaptec6X60_reloc` was
produced. Not hardware-tested. Linux `aic6x60` was not used as a template.

### drvSym53C8xx

The reference contains 136 C functions forming a CAM/SIM implementation, with
Symbios's own naming: `_CCBInSIMQueue`, `_AddToDeviceList`,
`_DeletePathFromDeviceTable`, `_FCalcSync`, `_FSetWide`, `_FWideInit`,
`_FResumeXFer`, `_FSendMsg`, `_AutosenseSetup`, `_BeginScan`. Our source
resolves 12 of 158.

This one matters beyond completeness: QEMU emulates `lsi53c895a`, a member of
this chip family, so a working drvSym53C8xx would be the natural SCSI path for
the emulated target. It is also the largest reconstruction of the group.

## Missing classes

Two drivers are missing an entire second class, which is why their counts stay
low even where the principal class name already matches:

- drvAdaptec2940 has no `SCSIBus` (13 methods across the class and its
  `(PrivateMethods)` category).
- drvDPT2000 has no `EATASCSIBus` (19 methods likewise).

## Link blockers found and fixed

Independent of reconstruction, two drivers could not have linked:

- **drvBusLogic** called `ddm_init`, `ddm_exp` and `ddm_thr` throughout
  `BusLogicController.m` with nothing defining them. Its own header records
  that it was "Created from the Adaptec 1542 driver", which carries the macros
  in `AHAControllerPrivate.h`; they were lost in the copy. Restored in
  `BusLogicControllerPrivate.h`.
- **drvSym53C8xx** had the same gap across 20 call sites. Restored in
  `SYM53c8ControllerPrivate.h`.

drvBusLogicFP, drvDPT2000 and drvAdaptec2940 do not call these macros at all
and need no such definitions. The related `ASSERT` is a no-op macro from
`kernserv/prototypes.h`, reached transitively, and was never a problem.

## Tooling note

The source-map scanner could not see K&R definitions where the return type sits
on its own line and the name starts at column zero:

    static void
    ahaTimeout(void *arg)

This is common NeXT and BSD formatting and made `_ahaTimeout` and its
equivalents appear missing when they were present. Fixed in
`binrecon/source_map.py`; it recovers about one symbol per driver, so it does
not change any of the counts above materially.
