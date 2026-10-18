# Screamer validation

| Gate | Result |
| --- | --- |
| Deterministic C tests | Not yet complete |
| Period PPC build and package | Not run |
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
