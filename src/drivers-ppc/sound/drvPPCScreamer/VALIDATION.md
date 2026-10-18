# Screamer validation

| Gate | Result |
| --- | --- |
| Deterministic C tests | Pass: identity, discovery, codec, runtime, routing, IRQ and power failure injection |
| Period Objective-C adapter tests | Pass on cc-771.4 / GCC 2.7.2.1 and Rhapsody Objective-C runtime |
| Kernel header installation | Pass, including installed PEDAVBus.h content comparison |
| Platform Expert PPC build | Pass; DAVbus service definitions present in PPC Mach-O |
| Screamer PPC bundle | Pass from an isolated staged source tree; PPC-only Mach-O PRELOAD and matching generated server name/glue |
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
Additional candidates (PowerMac3,2/3,3, Screamer iMacs, Lombard/Pismo) require
complete wiring evidence, an implemented platform backend, and their own
physical results. Headphone sense evidence alone does not establish routing
or power support.

| Model / firmware | Codec / profile evidence | Tests / target build | Physical audio | Physical power |
| --- | --- | --- | --- | --- |
| PowerMac3,1 / 4.2.8f1 (Sawtooth) | Published 343S0184 Screamer properties, Proj7 power; fixture passes | C and adapter tests pass; PPC artifact recorded below | Not run; no physical machine available | Not run; platform PM prerequisite blocked |
| PowerMac3,2 / 3,3 | Sense corroboration only; complete profile not validated | Generic implementation builds; no model acceptance | Not run | Not run |
| Screamer iMacs, Lombard, Pismo | Candidates; each needs supported platform and wiring evidence | No model acceptance | Not run | Not run |

The native build evidence and artifact hashes are in
[2026-10-18-build.md](tests/evidence/2026-10-18-build.md). The implementation
validated there is commit `ca218dba6`; later documentation changes do not imply
new measured hardware results.

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
