# i386 SCSI drivers: reconstruction status

Findings from comparing our sources against Apple's shipped `*_reloc` binaries
with `tools/binrecon`. The headline is that the eight drivers are not eight
partial reconstructions at different stages. Two are essentially complete,
three are reconstructed against their reference and guest-compiled but not
hardware-tested, one is a modern addition with no reference, and the other two
are stubs.

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
| drvAdaptec6X60 | 79 | 77 | reconstructed; guest `_reloc`; 54 functions unexamined; not hardware-tested |
| drvDPT2000 | 56 | 54 | reconstructed against the reference; guest `_reloc` produced on the ppc rbuild guest; not hardware-tested |
| drvBusLogicFP | 123 | 7 | stub |
| drvSym53C8xx | 158 | 158 | reconstructed against the reference; guest `_reloc` produced; not hardware-tested |
| drvAdaptec2940 | 170 | 10 | stub; missing the `SCSIBus` class |

`drvAMDPCSCSIDriver` has no reference bundle. It is a modern addition rather
than a reconstruction and is out of scope here.

## The class-name divergence

Two of the seven still name their principal class differently from the
reference. This is the same pattern already resolved in drvPCMCIABus, and it
is why those drivers initially resolved **zero** symbols — a total mismatch
rather than a partial one. drvAdaptec6X60, drvDPT2000, and drvSym53C8xx now
match.

| Driver | Ours | Reference |
| --- | --- | --- |
| drvAdaptec6X60 | `AIC6X60` | `AIC6X60` |
| drvBusLogic | `BLController` | `BLCController` |
| drvBusLogicFP | `BusLogicFPSCSI` | `BLFPController` |
| drvDPT2000 | `EATAController` (+ `EATASCSIBus`) | `EATAController` (+ `EATASCSIBus`) |
| drvSym53C8xx | `SYM53c8` | `SYM53c8` |

drvAdaptec1542B (`AHAController`), drvAdaptec6X60 (`AIC6X60`), drvAdaptec2940
(`Adaptec2940`), and drvDPT2000 (`EATAController` + `EATASCSIBus`) already
match. The `(PrivateMethods)` and `(IOThread)` category split is correct in
the other drivers. drvAdaptec6X60 no longer has `AIC6X60Routines.m` after the
HIM rewrite. drvSym53C8xx folded IOThread methods onto the main
`@implementation SYM53c8` (empty `SYM53c8(IOThread)` remains so `SYM53c8Thread.m`
stays in `CLASSES`) and deleted `SYM53c8Routines.m`.

Renaming is necessary but sufficient only for drvBusLogic, where it took the
count from 26 to 30 and left five genuinely missing functions.

## Closed architecture mismatches

`drvAdaptec6X60` used to implement an AHA-154x mailbox instead of the AIC-6X60
HIM; that rewrite is done (see below). `drvSym53C8xx` used to be a BusLogic CCB
clone vs CAM/SIM + SCRIPTS; that reconstruction closed in Tasks 6–11.

### drvAdaptec6X60

Reconstructed against `AIC6X60SCSI_reloc`. The AHA-154x mailbox clone
(`AIC6X60Routines.m`, `aic_cmd`, `allocCcb:`, `runPendingCommands`) is gone.
The live tree is a DriverKit `AIC6X60` class plus an Adaptec HIM
(`HIM6X60.c`) and SCSI sequencer (`AIC6X60Sequencer.c`) that program
AIC-6260/6360 ports directly: selection, reselection, message and data
phases, SDTR, PIO and DMA. The reconstruction ledger is 13
assembly-matched, 10 control-flow-confirmed, 54 unexamined, and 2 Kernel
Server glue. A guest `Adaptec6X60_reloc` was produced. Not
hardware-tested. Linux `aic6x60` was not used as a template.

## drvSym53C8xx

The reference contains 136 C functions forming a CAM/SIM implementation, with
Symbios's own naming: `_CCBInSIMQueue`, `_AddToDeviceList`,
`_DeletePathFromDeviceTable`, `_FCalcSync`, `_FSetWide`, `_FWideInit`,
`_FResumeXFer`, `_FSendMsg`, `_AutosenseSetup`, `_BeginScan`. Those names now
resolve in `SYM53c8SIM.c` / `SYM53c8CAM.c`. Guest `_reloc` produced; not
hardware-tested.

This one matters beyond completeness: QEMU emulates `lsi53c895a`, a member of
this chip family, so a working drvSym53C8xx would be the natural SCSI path for
the emulated target. It is also the largest reconstruction of the group.

## Missing classes

One driver is still missing an entire second class, which is why its count
stays low even where the principal class name already matches:

- drvAdaptec2940 has no `SCSIBus` (13 methods across the class and its
  `(PrivateMethods)` category).
- drvDPT2000 now has `EATASCSIBus` (19 methods across the class and its
  `(PrivateMethods)` category), matching the reference.

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
