# Screamer source evidence

New code implements hardware facts through Rhapsody DriverKit. No GPL code,
tables, or comments are copied. Most fixtures are synthetic; none establishes
physical hardware validation.

`FixtureSawtooth` separately transcribes only relevant properties from a
[PowerMac3,1 BootROM 4.2.8f1 dump](https://mail-index.netbsd.org/port-macppc/2010/11/30/msg001285.html).
It is firmware evidence, without a physical result from this project. The
specific `screamer` compatibility followed by legacy `awacs` is accepted;
contradictory explicit codec models remain rejected. The dump has counted
16.16 rates, capitalized `Keylargo`, a PCI BAR and mac-io range, output ports
1/2, and logical InSense bits reversed by Apple's `sndHWGetInSenseBits`.
Apple's `parseAndActivateInit` maps operation 2 to programmable output 0.
The Proj7 power object uses GPIO5 at 0x6f (0x05/0x04), waits 300 ms on power-on,
and clears programmable output 0 before its 200 ms power-off delay. USB iSub,
SSprockets notifications, telephony inputs and alternate sound-in controls
are outside the analog PCM interface.

| Reference | Pin | Evidence used |
| --- | --- | --- |
| [Apple Screamer](https://github.com/apple-oss-distributions/AppleOnboardAudio/tree/46f2f8a643cc36e1332feece6e39dd42a37302ab/AppleLegacyAudio/AppleScreamerAudio) | 46f2f8a643cc36e1332feece6e39dd42a37302ab | awacs_hw.h register map, ready bit 22, busy bit 24, payload fields, rate codes, pre-calibration delay; active GC_Recalibrate and double readback protocol in AppleScreamerAudio.cpp. |
| [Apple power](https://github.com/apple-oss-distributions/AppleOnboardAudio/blob/46f2f8a643cc36e1332feece6e39dd42a37302ab/AppleLegacyAudio/AudioHardwarePower.cpp) | same AppleOnboardAudio pin | Project power objects are wiring-specific, not interchangeable defaults. Commented timing alternatives are not active sequences. |
| [Apple KeyLargo](https://github.com/apple-oss-distributions/AppleKeyLargo/blob/d53ef3af164ee7f3323a46f1db01846e233b0f33/KeyLargo.h) | d53ef3af164ee7f3323a46f1db01846e233b0f33 | FCR1 location and variant-specific audio/I2S/USB bit meanings. Bit definitions alone do not prove a machine power sequence. |
| [NetBSD AWACS](https://github.com/NetBSD/src/blob/2622ed57a3e1c4995403c4c4f510bc1722be4f03/sys/arch/macppc/dev/awacs.c) | 2622ed57a3e1c4995403c4c4f510bc1722be4f03 | Controller/output/input register order; use_gpio4 sense mask for PowerMac3,1/3,2/3,3; no_parallel_output for PowerBook3,1. |
| [NetBSD obio](https://github.com/NetBSD/src/blob/2622ed57a3e1c4995403c4c4f510bc1722be4f03/sys/arch/macppc/dev/obio.c) | same NetBSD pin | Paddington input enabling differs from KeyLargo and cannot inherit its FCR policy. |
| [OpenBSD AWACS](https://github.com/openbsd/src/blob/c30c84965dc47c6c65e75cc3b5dd6eb181819bfa/sys/arch/macppc/dev/awacs.c) | c30c84965dc47c6c65e75cc3b5dd6eb181819bfa | Independent register/rate and connector corroboration. |

Repository reuse: drvPPCTASAudio/PPCDBDMAAudio and TASTime remain the canonical
implementations. The AWACS reconstruction is not treated as validated hardware
behavior. PPC APM.c returns PM_R_BAD_STATE and supplies no power events.

## Additional profiles and firmware search, 2026-10-18

Two first-hand Linux-visible device trees are available in Stan Johnson's
linuxppc-dev reports: [Lombard, 2025-10-30](https://www.mail-archive.com/linuxppc-dev@lists.ozlabs.org/msg246634.html)
([attachment](https://www.mail-archive.com/linuxppc-dev@lists.ozlabs.org/msg246634/dtc_lombard.txt.xz))
and [Pismo, 2025-10-29](https://www.mail-archive.com/linuxppc-dev@lists.ozlabs.org/msg246558.html)
([attachment](https://www.mail-archive.com/linuxppc-dev@lists.ozlabs.org/msg246558/dtc_pismo.txt.xz)).
These are real-machine `/proc/device-tree` captures and may include Linux's
early firmware fixups. Their compressed SHA-256 values are respectively
`bfd164d0f7a3edd869fd964f72579ef5f83f526e238f8aa59711c6b9be651f65` and
`40a6d4796c902c2376fbdf7f1846bbb20ee5313bafbf73447685cecf3f888331`.
Only relevant audio properties are transcribed into tests; no serial numbers,
MAC addresses or complete ROM images are distributed here.

Pismo is PowerBook3,1, BootROM 4.1.8f5, Keylargo PCI device 0x22, codec
343S0184/device-id 10/subframe 0. Its objects specify Proj10PowerControl,
logical headphone bit 1, and a MuxProgOut map selecting internal mic through
programmable output 1. The active power sequence is GPIO5 on, 80 ms, clear
programmable output 0, 200 ms, then codec activation. Power-off sets that output
before the 200 ms delay, codec sleep and GPIO5 off. Both parallel-output bits
remain clear during normal microphone operation, consistent with the
[first-hand Pismo speaker fix](https://mail-index.netbsd.org/netbsd-bugs/2008/08/27/msg005584.html).

Lombard is PowerBook1,1, BootROM 1.0f1, Paddington PCI device 0x17, codec
343S0184/device-id 2/subframe 0. This capture has no sound-objects. Apple's
[PowerBook1,1 DeviceTreeUpdater personality](https://github.com/apple-oss-distributions/AppleOnboardAudio/blob/46f2f8a643cc36e1332feece6e39dd42a37302ab/AppleOnboardAudio.xcodeproj/project.pbxproj#L502)
supplies its missing table. `ScreamerLombardProfile` transcribes those hardware
facts; discovery requires the exact root, codec, vendor/device, subframe and
bus identities and uses it only when objects are absent. Profile `source=1`
identifies this Apple patch; `source=0` identifies resolved firmware objects.
The original patched property SHA-256 is
`0e5d51927b102a2aa25bff2ace8cce7551a7631290fc3307a87a9e21a3b660fa`.

Apple's [Proj9 mux implementation](https://github.com/apple-oss-distributions/AppleOnboardAudio/blob/46f2f8a643cc36e1332feece6e39dd42a37302ab/AppleLegacyAudio/AudioHardwareMux.cpp#L101)
uses Heathrow byte 0x37: clear mask 0x0b, wait 2 ms for microphone selection,
set bit 0, then wait 320 ms. Media-bay analog CD uses the table's port 3 and
the mux's immediate clear operation. External sound-in uses port 2; built-in
mic uses port 1. Unused header bits are not added to the active sequence.
Proj6 power uses little-endian FCR 0x38 clock 0x2000/power_n 0x1000 and a
10 ms settle after platform enable. See the separately pinned backend
[register evidence](../../bus/drvPExpert/tests/DAVBUS.md).

Apple's original [iMac 4.1.9 updater](https://download.info.apple.com/Apple_Support_Area/Apple_Software_Updates/English-North_American/Macintosh/iMac/iMac_FWUpdate_4.1.9.smi.bin)
is still downloadable. Wrapper SHA-256:
`f48d467f555cc1ecf2512747e45d167c11a8d9cbb050602dd898961868a63042`.
Its decompressed Open Firmware SHA-256 is
`d94eca77f2061b64cd63a6264a79ad4833566c47cb859766ece827425ca8b470`.
The named `kiheis-sound` definition at offset 0x4a756 supplies the iMac
detects, outputs, inputs and PhaseInversion feature. The product-ID branch
at 0x4ac84 selects Proj5Speaker param 1 for PowerMac2,2 and PowerMac4,1,
and the default param 0 for PowerMac2,1. The model builder derives these from
IDs 0x82, 0x101 and 0x81 respectively; these are firmware-derived facts,
not a live iMac device-tree capture.

Logical sense bits 2/4 describe the two front headphone jacks and bit 8 the
rear external-speaker connector. Any external plug disables the internal
amplifier. Front headphones use codec output C; the rear connector uses A.
Front headphones take priority when both are present. Apple's
[output policy](https://github.com/apple-oss-distributions/AppleOnboardAudio/blob/46f2f8a643cc36e1332feece6e39dd42a37302ab/AppleLegacyAudio/AudioHardwareOutput.cpp)
and [PCM engine](https://github.com/apple-oss-distributions/AppleOnboardAudio/blob/46f2f8a643cc36e1332feece6e39dd42a37302ab/AppleLegacyAudio/Apple02DBDMAAudioDMAEngine.cpp)
corroborate the shared speaker/headphone port and internal-speaker-only right
phase inversion. AppleScreamerAudio's internal-mic mode copies left to right.
Corrections operate on explicit big-endian stereo samples at the CPU DMA
handoff; they are not applied to external stereo capture or headphone output.

PowerMac3,2 and PowerMac3,3 remain admitted through complete explicit Screamer
firmware with the already corroborated logical headphone bit 2. Their tests
vary the model on a firmware-shaped topology; they are not additional captured
trees. No complete PowerMac3,2 capture was located. Physical results remain
pending for every model, including Sawtooth.
