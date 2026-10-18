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

Baseline on 64-bit WSL: existing TAS descriptor sizeof check fails because
unsigned long is 64 bits; existing Platform Expert tests reject period
#import headers under GCC pedantic. These predate the new driver.
