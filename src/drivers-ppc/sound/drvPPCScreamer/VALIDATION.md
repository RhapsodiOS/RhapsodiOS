# Screamer validation

| Gate | Result |
| --- | --- |
| Deterministic C tests | Pass: identity, discovery, codec, runtime, routing, IRQ and power failure injection |
| Period Objective-C adapter tests | Pass on cc-771.4 / GCC 2.7.2.1 and Rhapsody Objective-C runtime |
| Kernel header installation | Pass, including installed PEDAVBus.h content comparison |
| Platform Expert PPC build | Pass; DAVbus service definitions present in PPC Mach-O |
| Screamer PPC bundle | Pass from an isolated staged source tree; PPC-only Mach-O PRELOAD and matching generated server name/glue |
| Private descriptor cache provider | Pass: actual provider model and PPC object compile; updated kernel required, physical execution pending |
| Source staging | Pass: canonical helper equality, no source mutation, stale products excluded, nonempty destination rejected |
| rbuild PPC APK | Pending: seed repository lacks dependency `drivertools` |
| rbuild i386 rejection | Pass: rejects the explicit PPC package architecture before compilation |
| Legacy AWACS whole-bundle build | Pending: existing `_entry` references are undeclared in PPCSoundPrivate.m; modified PPCSound.m compiles |
| Sawtooth physical playback/capture | Not run; no machine available to this execution |
| Physical sleep/wake | Blocked by platform PM prerequisite; not run |

No hardware support is claimed by a synthetic fixture or host test.
Native power transitions stop framework streams. Clients must restart them:
IOAudio exposes no stable queue-position/lifetime token with which to prove
safe automatic resume. The C runtime tests validated-owner buffer rebuilds,
but the native adapter deliberately supplies no resume validator.
The continuation implements the firmware/codec/platform paths below. These are
source and software results; every physical acceptance column remains pending.
The private PCM handoff also requires rebuilding the kernel DriverKit audio
objects, alongside the updated kernel cache provider and Platform Expert.

| Model / firmware | Routing/profile provenance | Software coverage | Physical audio / power |
| --- | --- | --- | --- |
| PowerMac3,1 / 4.2.8f1 | Published Screamer DT, Proj7 | Captured-property fixture, routing/power/adapter | Not run / platform PM pending |
| PowerMac3,2 / 3,3 | Complete explicit firmware required; no model-only fallback | Firmware-shaped model variations and known sense policy | Not run / platform PM pending |
| PowerMac2,1 / 2,2 / 4,1 | Apple 4.1.9f1 kiheis-sound, distinct speaker polarity | Firmware-derived object fixtures; both front jack bits, rear line out, combined plugs, both polarities, PCM phase correction | Not run / platform PM pending |
| PowerBook1,1 / 1.0f1 | Captured identity/resources; Apple PowerBook1,1 patch supplies absent objects | Strict fallback guards, Paddington power/mux, mic/line/media-bay CD selection | Not run / platform PM pending |
| PowerBook3,1 / 4.1.8f5 | Captured identity/resources/objects, independently confirmed by Apple firmware | Proj10 timing, programmable mux, no parallel output, mic/line routing | Not run / platform PM pending |

A complete PowerMac3,2 DT was not located. Its synthetic model variation does
not prove a profile or successful attachment on that machine. Full live iMac
DTs were not located; their routing evidence comes from the original Apple
firmware, with provenance recorded in [SOURCES.md](SOURCES.md).

The original native build evidence is preserved in
[2026-10-18-build.md](tests/evidence/2026-10-18-build.md). Continuation results
are recorded separately in
[2026-10-18-profiles.md](tests/evidence/2026-10-18-profiles.md).

Physical handoff checklist, pending for each claimed model:

1. Save firmware properties, boot logs, build hashes, and exactly-one-driver
   attachment results from a throwaway installation.
2. Record ten minutes of simultaneous 44.1 kHz stereo playback/capture and
   100 start/stop cycles. Check channel order, pitch, actual signals, independent
   stops, every advertised rate, and rejection of a conflicting duplex rate.
3. Exercise each exposed input with its documented electrical source, gain,
   volume endpoints, mute, and jack changes while idle and streaming.
4. Once platform sleep entry, callback delivery and resume ordering exist,
   perform ten physical sleep/wake cycles with idle/active streams and jack
   changes during sleep. Record the required client restart of native streams.

No step on this physical checklist has been reported as passed.

Baseline on 64-bit WSL: existing TAS descriptor sizeof check fails because
unsigned long is 64 bits; existing Platform Expert tests reject period
#import headers under GCC pedantic. These predate the new driver.
