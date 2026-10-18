# Screamer source evidence

New code implements hardware facts through Rhapsody DriverKit. No GPL code,
tables, or comments are copied. Constructed fixtures are synthetic and are not
firmware dumps or hardware validation.

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
