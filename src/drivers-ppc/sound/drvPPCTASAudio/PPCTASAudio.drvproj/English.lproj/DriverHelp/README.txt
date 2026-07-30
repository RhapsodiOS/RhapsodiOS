PPCTASAudio firmware matching

The driver table uses the broad "i2s" match because supported Power Mac
firmware does not expose a single, uniform TAS device name.  A table match is
only a request to probe: the driver must remain detached unless TASCore finds
one unique, internally consistent tumbler (TAS3001C) or snapper (TAS3004)
sound hierarchy.  Other I2S audio hardware is intentionally rejected.

Power-management callbacks and the TAS sleep/wake state machine are
implemented and tested.  The current PPC PMSetPowerState path does not
dispatch DriverKit IOPower callbacks end-to-end, so actual system sleep/wake
awaits PMU/platform dispatch integration and is not currently supported.
