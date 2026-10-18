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
