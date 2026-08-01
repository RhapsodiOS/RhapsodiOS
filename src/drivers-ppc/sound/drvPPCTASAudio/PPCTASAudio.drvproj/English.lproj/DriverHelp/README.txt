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

Output selection is intentionally only mute-all followed by selective
unmute of the real speaker, headphone, and line-out GPIOs.  There is no
invented output mux or codec-route operation: OpenBSD's pinned i2s driver
uses exactly those external mute GPIOs for its output selector:
https://github.com/openbsd/src/blob/229406285b562176139341c58aea5014bfb768a3/sys/arch/macppc/dev/i2s.c

The codec mixers use 4.20 unity (10 00 00), matching the pinned OpenBSD
TAS3001C and TAS3004 initial images and TI's TAS3004 software reference:
https://github.com/openbsd/src/blob/229406285b562176139341c58aea5014bfb768a3/sys/arch/macppc/dev/tumbler.c
https://github.com/openbsd/src/blob/229406285b562176139341c58aea5014bfb768a3/sys/arch/macppc/dev/snapper.c
https://www.ti.com/lit/an/slea030/slea030.pdf
The TAS3004 DRC shadow remains six bytes, as in that pinned OpenBSD register
model, despite inconsistent surviving datasheet descriptions.

Only microphone and line-in are selectable.  The required firmware
codec-input-data-mux GPIO selects microphone (inactive) or line-in (active),
while both use one stable codec mixer input.  CD and auxiliary source tags
are rejected, and jack/output routing never changes the input selection.
The advertised IOAudio input-gain range 0..32768 maps monotonically to TAS
4.20 coefficients 10 00 00 (unity/0 dB) through 20 00 00 (+6 dB).
Output VOLUME is a distinct 8.16 register: the pinned OpenBSD integer-dB
table supplies -56..0 dB (00 00 68 through 01 00 00), while -57..-84 dB
is the table's hard mute.  Mixer/input gain remains 4.20 as described above.
