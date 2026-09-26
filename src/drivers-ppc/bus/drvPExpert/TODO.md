# drvPExpert TODO

## Older iMac machine routes

Both come from `get_machine_id()` in `powermac/identify_machine.c`. Neither is
part of the MacRISC work; confirm each against a real machine's Open Firmware
`/compatible` before changing it.

- [ ] **PowerMac2,1 (iMac G3, slot-loading, 1999) takes the Yosemite route.**
  The Yosemite family assumes a Heathrow-style interrupt controller and
  `HEATHROW_SIZE` Mac-IO, but Linux treats this machine as Core99 (UniNorth
  with KeyLargo Mac-IO and an OpenPIC). It should pass the MacRISC capability
  checks (750 CPU, `uni-north`, KeyLargo `device-id` 0x22). Moving it means
  dropping its Yosemite comparison, adding it to the MacRISC catalog, and
  removing it from the preserved-route list in `PEMacRISCSelectRoute()` and the
  MacRISC plan's invariants.

- [ ] **Tray-loading iMac G3 (1998) may never match.** The legacy table
  compares the plain string `iMac`, while Linux names this machine `iMac,1`.
  If firmware says `iMac,1`, the machine falls through to MacRISC discovery,
  fails on its Grackle host bridge, and panics as unsupported. It is
  Paddington/Grackle hardware, so the fix is an `iMac,1` comparison on the
  Yosemite route, plus the same string in `PEMacRISCSelectRoute()`'s legacy
  list.
