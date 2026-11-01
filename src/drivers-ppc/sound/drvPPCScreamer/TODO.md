# Screamer remaining work

The native driver and additional machine profiles are implemented. These
unchecked items track remaining evidence, integration and acceptance work;
software tests do not establish physical hardware support. See
[VALIDATION.md](VALIDATION.md) for the current gates and
[SOURCES.md](SOURCES.md) for firmware provenance.

## Kernel and packaging

- [ ] Link and boot a PPC kernel containing the updated Platform Expert,
  descriptor cache provider and DriverKit audio objects (`IOAudio.o` and
  `AudioChannel.o`), together with the Screamer bundle. Record build hashes
  and boot logs; standalone object and bundle builds are already covered.
- [ ] Supply the missing `drivertools` dependency in the package seed
  repository, then build and inspect the PPC APK through `rbuild`.
- [ ] Resolve the existing undeclared `_entry` references in the legacy
  AWACS `PPCSoundPrivate.m` and rerun its whole-bundle compatibility build.

## Firmware and profile evidence

- [ ] Obtain complete real-machine firmware/device-tree captures for
  PowerMac3,2 and PowerMac3,3. Verify codec identity, resources, connectors,
  mux and power objects against discovery and profile fixtures. Keep the
  requirement for complete explicit firmware; model variations alone do
  not prove attachment.
- [ ] Obtain full live device trees for PowerMac2,1, PowerMac2,2 and
  PowerMac4,1, and compare them with the existing Apple 4.1.9f1
  `kiheis-sound` profiles, including speaker polarity and jack wiring.
- [ ] On Lombard and Pismo, compare the attached driver's resolved profile
  with the captured properties. Verify Lombard's strict Apple patch
  fallback when `sound-objects` are absent and Pismo's programmable mux.
- [ ] Record firmware versions and provenance for new captures; add only
  relevant audio properties to fixtures and exclude identifying data.

## Physical acceptance

Run and record the [physical handoff checklist](VALIDATION.md) for Sawtooth,
PowerMac3,2/3,3, PowerMac2,1/2,2/4,1, Lombard and Pismo. Use throwaway
installations and retain results per model and firmware version.

- [ ] Confirm exactly one audio driver attaches and that advertised
  inputs, outputs and rates match the machine's wiring.
- [ ] Run ten minutes of simultaneous 44.1 kHz stereo playback/capture
  and 100 start/stop cycles. Check actual signals, channel order, pitch,
  independent stream stops, every advertised rate and conflicting duplex
  rate rejection.
- [ ] Exercise all exposed inputs, gain, volume endpoints, mute and jack
  changes while idle and streaming. Include iMac speaker phase correction
  and microphone channel duplication, Lombard mic/line/media-bay CD, and
  Pismo mic/line selection.
- [ ] After PPC platform sleep entry, power callbacks and resume ordering
  exist, run ten physical sleep/wake cycles with idle/active streams and
  jack changes during sleep. Native clients must restart streams after
  wake; automatic stream resume is not implemented.

## Evidence updates

- [ ] Update [VALIDATION.md](VALIDATION.md) and append dated evidence under
  [tests/evidence](tests/evidence/) as gates pass. Keep firmware-derived,
  synthetic-test and physical results distinct. Existing build results are
  in [the original build log](tests/evidence/2026-10-18-build.md) and
  [the profile continuation](tests/evidence/2026-10-18-profiles.md).
