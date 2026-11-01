# Source provenance

This driver is a clean implementation of behavior and register facts from
published hardware documentation and permissively licensed reference code.
No source code was copied from the references listed below, and no GPL source
was used. References are pinned where possible so future upstream changes do
not silently change the evidence.

## OpenBSD reference implementation

The OpenBSD source tree is pinned at commit
[`229406285b562176139341c58aea5014bfb768a3`](https://github.com/openbsd/src/tree/229406285b562176139341c58aea5014bfb768a3).
`i2s.c`, `tumbler.c`, `snapper.c`, `i2sreg.h`, and `kiic.c` carry Tsubai
Masanari's permissive three-clause BSD-style notice. `macgpio.c` carries the
Internet Research Institute's older four-clause BSD-style notice, including
its advertising acknowledgement. The repository's licensing policy is
described by the [OpenBSD copyright policy](https://www.openbsd.org/policy.html).

- [`i2s.c`](https://github.com/openbsd/src/blob/229406285b562176139341c58aea5014bfb768a3/sys/arch/macppc/dev/i2s.c)
  supplied the external GPIO evidence: output selection and master mute act on
  speaker, headphone, and line-out mute GPIOs, while jack handling selects
  those paths without a TAS output-route register write. Its device-tree
  discovery also identifies the platform mute, detect, and hardware-reset
  GPIO roles.
- [`tumbler.c`](https://github.com/openbsd/src/blob/229406285b562176139341c58aea5014bfb768a3/sys/arch/macppc/dev/tumbler.c)
  was used to cross-check TAS3001C subaddresses, payload widths, 64fs/I2S/20-bit
  initialization, muted stereo volume, all-pass biquads, and Mixer 1 unity with
  Mixer 2 muted.
- [`snapper.c`](https://github.com/openbsd/src/blob/229406285b562176139341c58aea5014bfb768a3/sys/arch/macppc/dev/snapper.c)
  was used to cross-check TAS3004 subaddresses, payload widths, ACR use for
  analog input selection, all-pass initialization, fixed SDIN1 unity mixing,
  and the six-byte DRC payload.
- [`i2sreg.h`](https://github.com/openbsd/src/blob/229406285b562176139341c58aea5014bfb768a3/sys/arch/macppc/dev/i2sreg.h)
  was consulted for I2S register layout and format/clock bit meanings.
- [`kiic.c`](https://github.com/openbsd/src/blob/229406285b562176139341c58aea5014bfb768a3/sys/arch/macppc/dev/kiic.c)
  was consulted for KeyWest-family I2C transaction ordering and status use.
- [`macgpio.c`](https://github.com/openbsd/src/blob/229406285b562176139341c58aea5014bfb768a3/sys/arch/macppc/dev/macgpio.c)
  was consulted for Apple mac-io GPIO child enumeration, `reg` offsets, and
  `AAPL,interrupts`/`interrupts` property fallback.

These files were behavioral cross-checks only. The implementation uses the
Rhapsody DriverKit and Platform Expert interfaces already present in this
tree, not OpenBSD kernel interfaces or copied OpenBSD routines.

## Texas Instruments documentation

- [TAS3001C digital audio processor, SLAS226B](https://media.digikey.com/pdf/Data%20Sheets/Texas%20Instruments%20PDFs/TAS3001C.pdf)
  defines the TAS3001C register map, I2S format, 4.20 mixer coefficients,
  8.16 volume coefficients, reset defaults, soft-volume behavior, and
  initialization
  sequencing. This surviving distributor mirror contains the TI data manual;
  the [canonical TI TAS3001C URL](https://www.ti.com/lit/ds/symlink/tas3001c.pdf)
  now returns 404. The still-live TI
  [TAS3001C I2C application report, SLEA001](https://www.ti.com/lit/an/slea001/slea001.pdf)
  corroborates transaction widths, wait states, volume ramp timing, and fast
  load. The part describes one serial digital output feeding external analog
  hardware, not a speaker/headphone/line-out endpoint mux.
- [TAS3004 digital audio processor with codec](https://www.ti.com/lit/ds/symlink/tas3004.pdf)
  defines the TAS3004 register map, ACR, mixer inputs, stereo DAC outputs,
  reset defaults, and DRC fields. The mixers combine SDIN/ADC sources into the
  left/right signal path; they are not physical endpoint selectors.
- [TAS3004 software reference design concept, SLEA030](https://www.ti.com/lit/an/slea030/slea030.pdf)
  was used to cross-check signal-flow intent and unity 4.20 mixer values. Its
  main left/right and optional second-codec subwoofer arrangement does not
  define an internal speaker/headphone/line-out selector.

The TAS3004 datasheet is internally inconsistent about the DRC register
length: Appendix Table A-1 reports a width of five, while section 4.10 and
Table A-9 show an eight-byte I2C instruction consisting of device address,
subaddress, and **six data bytes**. The driver uses six data bytes, matching
the detailed field table and the pinned OpenBSD `snapper.c` implementation.

The output attenuation conversion uses the pinned OpenBSD integer-dB volume
table: 0 dB is `01 00 00`, -42 dB is `00 02 09`, and values below the
table's -56 dB floor are hard mute. This 8.16 volume format is intentionally
distinct from the 4.20 mixer/input-gain format, whose unity value is
`10 00 00`.

The codec initialization code also writes each left/right biquad register in
its actual sequential register slot. It does not reproduce published sample
code variants that duplicate RB1 or omit/duplicate later RB registers.

## Apple Open Source reference

The following files were consulted from Apple's
[`AppleOnboardAudio-258.3.1`](https://github.com/apple-oss-distributions/AppleOnboardAudio/tree/AppleOnboardAudio-258.3.1)
tag:

- [`AppleTAS3004Audio.cpp`](https://github.com/apple-oss-distributions/AppleOnboardAudio/blob/AppleOnboardAudio-258.3.1/AppleOnboardAudio/AppleTAS3004Audio.cpp)
  for Apple hardware terminology and TAS3004 control organization;
- [`AppleOnboardAudio.cpp`](https://github.com/apple-oss-distributions/AppleOnboardAudio/blob/AppleOnboardAudio-258.3.1/AppleOnboardAudio/AppleOnboardAudio.cpp)
  for the separation between the audio engine, platform services, and output
  selection; and
- [`PlatformInterfaceGPIO.cpp`](https://github.com/apple-oss-distributions/AppleOnboardAudio/blob/AppleOnboardAudio-258.3.1/AppleOnboardAudio/PlatformInterfaceGPIO.cpp)
  for the platform GPIO roles used by onboard audio.

Those Apple sources are distributed under the Apple Public Source License
2.0 in that repository. They were used as documentary corroboration only; no
APSL implementation code was copied into this driver.

## Routing conclusion

The TI parts expose audio-path mixers and one main stereo output, but no
register that selects the machine's external speaker, headphone, and line-out
endpoints. The pinned OpenBSD implementation independently shows those
endpoints controlled by their platform GPIO mutes. Together, those facts are
the basis for this driver's mute-all/selective-unmute GPIO routing and its
fixed codec mixer path.
