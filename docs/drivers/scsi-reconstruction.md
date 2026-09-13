# i386 SCSI drivers: reconstruction status

Findings from comparing our sources against Apple's shipped `*_reloc` binaries
with `tools/binrecon`. The headline is that the eight drivers are not eight
partial reconstructions at different stages. Two are essentially complete, one
is a modern addition with no reference, and the other five are stubs — and two
of those are built on the wrong hardware model, so they could not work even if
completed as written.

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
| drvAdaptec6X60 | 79 | 18 | stub, wrong architecture |
| drvDPT2000 | 55 | 10 | stub; missing the `EATASCSIBus` class |
| drvBusLogicFP | 123 | 7 | stub |
| drvSym53C8xx | 158 | 158 | reconstructed against the reference; guest `_reloc` produced; not hardware-tested |
| drvAdaptec2940 | 170 | 10 | stub; missing the `SCSIBus` class |

`drvAMDPCSCSIDriver` has no reference bundle. It is a modern addition rather
than a reconstruction and is out of scope here.

## The class-name divergence

Five of the seven name their principal class differently from the reference.
This is the same pattern already resolved in drvPCMCIABus, and it is why five
drivers initially resolved **zero** symbols — a total mismatch rather than a
partial one.

| Driver | Ours | Reference |
| --- | --- | --- |
| drvAdaptec6X60 | `AIC6X60Controller` | `AIC6X60` |
| drvBusLogic | `BLController` | `BLCController` |
| drvBusLogicFP | `BusLogicFPSCSI` | `BLFPController` |
| drvDPT2000 | `DPTSCSIDriver` | `EATAController` |
| drvSym53C8xx | `SYM53c8` | `SYM53c8` |

drvAdaptec1542B (`AHAController`) and drvAdaptec2940 (`Adaptec2940`) already
match. The `(PrivateMethods)` and `(IOThread)` category split is correct in
every driver, and the `*Controller.m` / `*Routines.m` / `*Thread.m` file
layout mirrors it — that part was reconstructed well throughout.

Renaming is necessary but sufficient only for drvBusLogic, where it took the
count from 26 to 30 and left five genuinely missing functions.

## The architecture problem

Two drivers do not merely lack functions. They implement a different hardware
interface from the chip they target.

### drvAdaptec6X60

`AIC6X60Routines.m` programs a **mailbox interface**: `AIC_CMD_INIT` carrying
`mb_cnt`, in and out mailbox arrays, `AIC_CMD_START_SCSI`,
`AIC_CMD_SET_MB_ENABLE`, `AIC_CMD_GET_BIOS_INFO`. That is the AHA-154x host
adapter command protocol, for a board whose onboard processor accepts mailbox
commands. The driver was cloned from drvAdaptec1542B and kept its architecture.

The AIC-6260/6360 has no onboard processor and no mailbox interface. It is a
low-level SCSI protocol chip: the host drives selection, reselection, message
and data phases directly. Apple's driver does exactly that — of its 79
functions, 54 are C functions forming an Adaptec HIM plus a SCSI sequencer:

    _HIM6X60Initialize  _HIM6X60ISR        _HIM6X60QueueSCB    _HIM6X60AbortSCB
    _selection          _reselection       _scsiBusFree        _scsiBusReset
    _targetREQuest      _samePhaseREQuest  _interpretMessageIn _prepareMessageOut
    _negotiateSDTR      _updateSDTR        _resetSDTR
    _dataInPIO          _dataOutPIO        _dataPhaseDMA
    _repinsb _repinsw _repinsd  _repoutsb _repoutsw _repoutsd

Our 18 resolved symbols are DriverKit method shells, not the engine. Sixteen
symbols exist in our source that the reference does not have — `_aic_cmd`,
`_aic_probe_cmd`, `_aicTimeout`, and the mailbox-era `allocCcb:`,
`ccbFromCmd:ccb:`, `freeCcb:`, `runPendingCommands` — all residue of the wrong
model.

Our driver sends commands the chip does not implement, so it cannot work on
real hardware regardless of how much of the remainder is filled in.

### drvSym53C8xx

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
