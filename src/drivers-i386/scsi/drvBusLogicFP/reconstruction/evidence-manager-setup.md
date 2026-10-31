# Adapter manager setup evidence

Reference identity: `C86447845EE31FE61DBD91037DFCFAAF0AD65B994463539C8370AEAA9E960C0E`.

`SccbMgr_config_adapter` at `0x432c` finds an existing 20-byte card record by I/O base or allocates the first empty slot, initializes the card's target table on first use, and stores the index/info pointer. It initializes bus-master/crossbow/default-map state, programs the one-hot host ID and interrupt registers, copies EEPROM settings into per-target bytes, sets the host-ID and wide-ID flags, and returns the card pointer. The source follows each branch/store in IDA pseudocode; direct success-path execution is deferred because this host cannot run the historical i386 DriverKit target.

`SccbMgr_scsi_reset` at `0x50fc` optionally issues the EEPROM-provided reset setup, resets the SCSI bus, handles the bus-master timeout bit and associated status writes, then calls SCAM initialization. `manager_reset_without_bus_interrupt` covers the path with the bus-master status bit clear. `SccbMgr_sense_adapter` and `phaseDecode` are covered in `evidence-manager-probe.md`.

The card record tail was corrected from IDA's actual stores: manager index `+14`, queue cursor `+15`, flags `+16`, host ID `+17`, opaque bytes `+18..+19`. `tests/layout.c` now asserts these offsets in the i386 compile.
