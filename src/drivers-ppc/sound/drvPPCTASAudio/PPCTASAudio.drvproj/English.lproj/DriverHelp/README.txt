PPCTASAudio firmware matching

The driver table uses the broad "i2s" match because supported Power Mac
firmware does not expose a single, uniform TAS device name.  A table match is
only a request to probe: the driver must remain detached unless TASCore finds
one unique, internally consistent tumbler (TAS3001C) or snapper (TAS3004)
sound hierarchy.  Other I2S audio hardware is intentionally rejected.

The main I2S device description cannot bind the child GPIO jack-detect
interrupt.  While the device is ready, the driver therefore polls jack state
every 250 ms and retains the normal two-sample, 5 ms debounce.  Jack routing
may consequently lag a physical insertion or removal by about 250 ms.

Teardown disables DMA interrupts before bounded stop/reset.  If hardware does
not stop, the driver fail-mutes and deliberately preserves DMA resources
rather than freeing descriptors that the controller could still access.

IOAudio does not terminate its worker threads during -free.  After successful
initialization this driver therefore quiesces hardware but retains its object,
locks, and singleton callout ownership.  A loaded instance cannot be unloaded
or replaced safely; a second probe remains rejected until system restart.

Power-management callbacks and the TAS sleep/wake state machine are
implemented and tested.  The current PPC PMSetPowerState path does not
dispatch DriverKit IOPower callbacks end-to-end, so actual system sleep/wake
awaits PMU/platform dispatch integration and is not currently supported.
