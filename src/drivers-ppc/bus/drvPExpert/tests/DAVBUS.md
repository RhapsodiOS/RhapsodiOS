# DAVbus platform backends

These services publish a clock/power backend, not codec or machine audio
acceptance. The audio driver still validates Screamer identity and wiring.

| PCI vendor/device | Family | LE control register | Ready / off |
| --- | --- | --- | --- |
| 106b:0022 | KeyLargo (1) | 0x3c | Existing DAVbus selector, clock and cell sequence; restore saved selector on off. |
| 106b:0025 | Pangea (2) | 0x3c | Same documented DAVbus bits as KeyLargo. |
| 106b:0010, 106b:0017 | Heathrow/Paddington (3) | 0x38 | Set clock 0x2000, clear power_n 0x1000; off sets power_n before clearing clock. |

Intrepid 106b:003e remains rejected: its corresponding FCR1 bits control USB2.
Heathrow power bits overlap the numeric KeyLargo I2S0 mask, so family 3 must
not apply that register mask. Explicit I2S ownership still excludes DAVbus.
Every transition holds the platform audio lock, preserves unrelated bits and
checks readback. Failure retains ownership. A failed off invalidates the
active marker, so a later ready request must reprogram the hardware.

Binding requires the selected machine class, Apple vendor and supported
device ID, the PE mac-io physical base/span, a single matching affine PCI
memory `ranges` entry with one child address/size cell, and exactly one
direct `davbus`/`awacs` child. All three controller/output/input ranges must
fit that bus, align, meet register extents, and not overlap. The controller
must equal PE's audio physical base. Binding performs no MMIO.

The legacy Yosemite-class initialization binds DAVbus only; it publishes no
KeyWest/GPIO/I2S transport. Modern KeyWest initialization rejects Heathrow
and Paddington IDs. Existing modern KeyWest discovery remains intact.
PowerMac2,1/2,2/4,1 and PowerBook3,1 use the Core99/Sawtooth machine path;
PowerBook1,1 remains on the legacy Yosemite/Heathrow path. These class choices
do not add a guessed mac-io span fallback for any model.

`PEDAVBusSetInputMux` is family 3 only, capability 2. It accepts 0/1, requires
active DAVbus ownership, masks only byte 0x37 bits 0x0b and verifies the
result. The Screamer runtime owns the Proj9 reset/select/settling sequence.
Family 3 advertises no GPIO5 amplifier capability. This is not a public
general-purpose GPIO write service.

## Source evidence

- [Apple KeyLargo.h](https://github.com/apple-oss-distributions/AppleKeyLargo/blob/d53ef3af164ee7f3323a46f1db01846e233b0f33/KeyLargo.h):
  variant IDs, `kKeyLargoFCR1`, audio/I2S bits and Intrepid USB aliases.
- [Apple Heathrow.cpp](https://github.com/apple-oss-distributions/AppleHeathrow/blob/0b31bd35d3e94029d7fc0d6fbf21ac1859c22e18/Heathrow.cpp):
  `readRegUInt32`/`writeRegUInt32` use byte-reversed accesses.
- [Apple AudioHardwarePower.h](https://github.com/apple-oss-distributions/AppleOnboardAudio/blob/46f2f8a643cc36e1332feece6e39dd42a37302ab/AppleLegacyAudio/AudioHardwarePower.h)
  and its `.cpp`: Proj6 FCR offset/mask/on/off, plus 10 ms clock settling
  before recalibration. The driver caller owns that settling interval.
- [Apple AudioHardwareMux.cpp](https://github.com/apple-oss-distributions/AppleOnboardAudio/blob/46f2f8a643cc36e1332feece6e39dd42a37302ab/AppleLegacyAudio/AudioHardwareMux.cpp)
  and its `.h`: Proj9/Mux101 byte 0x37, mask 0x0b, internal mic selection 1,
  reset then 2 ms/320 ms delays. Do not add the unused channel-enable bit.
- [NetBSD PCI IDs](https://github.com/NetBSD/src/blob/2622ed57a3e1c4995403c4c4f510bc1722be4f03/sys/dev/pci/pcidevs):
  Apple Heathrow 0x10, Paddington 0x17, KeyLargo 0x22, Pangea 0x25.
- [Linux feature.c](https://github.com/torvalds/linux/blob/58161ead29e50d70a317ea26b472e0c7508e69da/arch/powerpc/platforms/powermac/feature.c):
  model-to-Core99/Pangea/Paddington classification corroboration. Consulted
  for hardware facts only; no GPL implementation, tables or comments copied.
- First-hand [Lombard](https://www.mail-archive.com/linuxppc-dev@lists.ozlabs.org/msg246634/dtc_lombard.txt.xz)
  and [Pismo](https://www.mail-archive.com/linuxppc-dev@lists.ozlabs.org/msg246558/dtc_pismo.txt.xz)
  device-tree captures establish matching mac-io PCI ranges and resource
  triplets. Lombard raw interrupts 17/8/9 become table indices 9/16/17 after
  the existing DriverKit XOR 0x18, matching Yosemite audio/output/input.
  Pismo uses two-cell 24/1, 9/0, 10/0 interrupts; the existing Core99 parser
  supplies three source numbers. No new legacy IRQ remap was added.

## Verification

Run from a host with a C compiler:

```sh
make -C src/drivers-ppc/bus/drvPExpert/tests -f Makefile.host \
  'HOST_CFLAGS=-std=c89 -Wall -Wextra -Werror -Wno-deprecated' test
```

Tests cover family-specific exact write traces, each ready/off write failure,
readback failure, retained ownership and reinitialization, I2S exclusion,
task-context checks, Proj9 masks/capabilities, and production firmware binding
with malformed, duplicate, conflicting and unsupported resources. Existing
MPIC, KeyWest/I2S/GPIO and interrupt-depth tests remain in the same gate.
Host tests do not establish a period PPC build, physical audio or sleep/wake.
