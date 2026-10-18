# PPC Screamer audio

Native Rhapsody DriverKit `PPCScreamer : IOAudio <IOPower>`, with a separate
PPC-only bundle and a DAVbus service in Platform Expert. It reuses the canonical
TAS DBDMA and deadline helpers as build inputs; no loaded TAS bundle is needed.

Discovery requires an explicit Screamer identity, matching delivered memory
and interrupt resources, complete firmware routing and rates, and a supported
KeyLargo backend. The PowerMac3,1 BootROM 4.2.8f1 property fixture includes its
Proj7 amplifier power sequence. Other machines are candidates until their
firmware, platform sequence and physical results are recorded independently.

PCM is 16-bit big-endian stereo, with firmware-advertised discrete rates and a
44.1 kHz baseline. Full duplex shares one clock; conflicting rates are rejected.
Controls expose only resolved analog inputs, four-bit gain/attenuation, user
mute and debounced headphone routing. Initial output is muted. Unsupported
codec, input and power models are declined.
Changing the selected input while either stream runs is rejected.

Power callbacks stop framework streams. Clients must restart them after wake:
IOAudio provides no reliable queue-position token for automatic resume. System
PPC power dispatch is still a stub, so driver-local power tests do not establish
physical sleep/wake support. Hot unload is unavailable: published IOAudio
workers retain the object, locks and DMA resources until reboot.

Run the host C tests with `make -C tests -f Makefile.host test`. The adapter test
requires the period Objective-C compiler/runtime:

```
gnumake -C tests -f Makefile.host SDK=/path/to/driverkit-3 adapter-test
```

Build and boot the updated PPC kernel containing `pmap_set_cache_spec`, install
its headers, and build the updated Platform Expert. The original kernel's
cache-spec routine ignores the requested cache policy. Descriptor allocation
requires private wired pages and rejects aliases before hardware activation.
Use the period PPC toolchain with DriverTools installed. From the driver directory:

```
gnumake clean
gnumake RC_ARCHS=ppc NEXT_ROOT=/path/to/sdk
```

For a builder that copies one project at a time, stage its canonical inputs:

```
sh package-source.sh /path/to/repository/src /tmp/screamer-source-package
```

The output must be empty and outside the source tree. Build the generated root
Makefile with the same PPC flags, or pass that root to rbuild. Package metadata
rejects i386. See [VALIDATION.md](VALIDATION.md) for actual build results and
the outstanding package and physical acceptance gates.
