# i386 VESA kernel support: boot gates, run 2026-09-22

Spec 2 added three functions to the i386 kernel: `VBEModeInfo2IODisplayInfo`,
`FBAllocateVBEConsole`, and a call to the second from `BasicAllocateConsole`.
The byte checks passed earlier (see
`src/kernel-7/reconstruction/vbe/divergences.md`). This page records the boot
gates that followed.

**All three gates pass.**

- **Gate 2.** `sarld` links spec 1's reconstructed `VBE20DisplayDriver` against
  the new kernel. The evidence is positive: the driver's own messages appear in
  the log, and no other boot driver is lost.
- **Gate 3.** The driver loads and prints all three expected lines, plus two
  more.
- **Graphics mode.** Booted in graphics mode, the new kernel behaves exactly
  like the pre-Task-4 kernel.

A **negative control** shows the failure these gates were built to catch. The
same driver on a kernel without the symbol fails at the booter with
`rld(): Undefined symbols: _VBEModeInfo2IODisplayInfo`, and the kernel logs
`configureDriver: driver class 'VBE20DisplayDriver' was not loaded`.

## What was booted

Every input was hashed just before use, and each image was read back before
its boot.

| Role | File | Bytes | SHA-256 |
| --- | --- | --- | --- |
| New kernel (Task 4 build of `e2d02efe8`) | `vm/work/task4c-mach_kernel` | 1,490,352 | `74B12FCD53E886AAFCBB29AD400C5DEDD10B26F04BBA0FBC6E02DAEFEA25CFF4` |
| Control kernel (pre-Task-4) | `vm/work/task3-mach_kernel-final` | 1,490,352 | `1C0F8B804A5ECEF5124B3FCE9C3335356B7692B7C1FD11E2A40CFD6B87F7215D` |
| Negative-control kernel (pre-spec-2) | `D:/RhapsodiOS/vm/install/mach_kernel`, built `Fri Sep 18 12:06:49 PDT 2026` | 1,486,184 | `9916E7C0BDAC2D4E28A5236AC303677A7A45A8ABFE229B307CEBEAC70721CF8D` |
| Driver `_reloc` (spec 1's `$DRVBUILT`) | `vbe20-recon/out/i386/drvVBE20DisplayDriver/VBE20DisplayDriver.config/VBE20DisplayDriver_reloc` | 102,412 | `77399531152E287487668F6222467CF9C1ECA449859B169A66352B608A3A36A1` |
| Driver `Default.table` | same bundle | 482 | `02EF18A5D57FF8DA03543211DB8F12799803B6B2A0A7812114405A4B73C04C15` |
| Master image | `D:/RhapsodiOS/vm/golden.img` | 8,589,934,592 | `E1968E3EF57F3060AA01CEAB8B4D5C49C067E6ACC5F8626EBABEEFE0E663879F` |
| Booter in that image | `/usr/standalone/i386/boot`, also at image offsets 32768 and 98304 | 39,616 | `AA06C3C5BFE56C79573E36D20C662DA10CA67D0CEC5BE17F13A5B562F6B5F2C2` |
| `sarld` in that image | `/usr/standalone/i386/sarld` | 148,108 | `BBFB53F28725908DCC54E247EDEFD6BD78C9B5405D0C95E4B0D8B33D131AFEBA` |

The driver `_reloc` hash is exactly the `rebuilt_sha256` in spec 1's ledger.

The new kernel is the one Task 4 built from `e2d02efe8`. Since then the only
kernel source change is a comment rewrite in `BasicConsole.c`. With comments
stripped, that file is identical at `e2d02efe8` and at `HEAD`.
`git status src/kernel-7` at `f853aae61` was clean. This task synced nothing
and built nothing.

The negative-control kernel has neither `_VBEModeInfo2IODisplayInfo` nor
`_FBAllocateVBEConsole` in its symbol table. The other two kernels have both
symbols, defined and external (`n_type 0x0F`).

**The booter that runs is Apple's `boot` v5.0.41.1, not `src/boot-2`.** Its
copies in the boot area are byte-identical to `/usr/standalone/i386/boot`. It
contains no `Graphics Mode` string, so the graphics-mode logic in
`src/boot-2/i386/boot2/graphics.c` does not describe this boot.

## Procedure

All runs were made from `vm/` in the `vbe20-kernel` worktree, one after
another, on this host, on 2026-09-22 between 17:30 and 18:08 EDT. The image
was rebuilt from `golden.img` before every boot:

```bash
MSYS_NO_PATHCONV=1 python graft-kernel.py D:/RhapsodiOS/vm/golden.img <kernel> work/test.img
# with the driver:
mv work/test.img work/kern.img
MSYS_NO_PATHCONV=1 python install-driver.py work/kern.img <bundle> work/test.img
```

**`install-driver.py` does not run as written on this host.** It clones its
input with `cp -c`, a macOS clone flag, and GNU cp 8.32 in Git Bash rejects
it (`cp: unknown option -- c`). This run used a wrapper script that imports
`install-driver.py` unchanged and replaces only that one call with
`shutil.copyfile`. The bundle install, the `Instance0.table` it writes and the
`Boot Drivers` edit all ran through the tool's own code. The `Boot Drivers`
change was written by `set_table_key`.

Before each boot, `/mach_kernel` and every installed driver file were read
back out of `work/test.img` and hashed against the source. All matched.
`Boot Drivers` then read
`EIDE ISASerialPort Floppy PS2Keyboard PCIBus EISABus VBE20DisplayDriver`, so
the new driver links last. `Active Drivers` was left as the image ships it,
`CirrusLogicGD5434DisplayDriver BusMouse NE2K`. **`Boot Drivers` alone was
enough; the driver never had to be listed in `Active Drivers`.**

Boots used `qemu-shot.py`. The verbose runs typed
`--keys $'mach_kernel -v\n' --keys-at 8`. The graphics-mode runs sent no keys
at all (see below). All runs in one comparison used the same `--at` list.

## Gate 2: `sarld` links the driver

Three verbose boots were run back to back: new kernel without the driver
(`A1`), new kernel with it (`B`), then new kernel without it again (`A2`).

**The driver's own messages appear.** From `B`'s `serial.log`, straight after
`Registering: EISA0`, as lines 49 to 53:

```
VBEDisplay0: VESA video driver initialization.
VBEDisplay0: Skipping framebuffer initialization (card not in VBE mode).
VBEDisplay0: Driver loaded to export VBE mode list.
VBEDisplay0: No VBE modes found.
Registering: VBEDisplay0
```

Code that never linked cannot print these lines.

**No cascade.** `A1` and `A2` each register the same 12 devices: `hc0` and
`hd0` (EIDE), `ISASerialPort0`, `fc0` (Floppy), `PS2Controller` and
`PCKeyboard0` (PS2Keyboard), `PCI0`, `EISA0`, `event0`, `kmDevice0`,
`Display0` and `en0`. `B` registers all 12, plus `VBEDisplay0`. None is
missing.

This check is weaker than it looks. `VBE20DisplayDriver` is last in
`Boot Drivers`, and the cascade described in
`docs/boot/sarld-driver-link-limit.md` only hits drivers linked *after* a
failure. So a failure of this driver's link could not have shown up as a lost
boot driver. Gate 2 therefore rests on the driver's own lines and on the
negative control below.

**`B` against `A2`, in order.** The logs match line for line, except for two
things:

- **The five driver lines** above.
- **Line 9.** `available memory = 121.09 megabytes. vm_page_free_count = 3c8c`
  becomes `121.08 ... 3c8b`: one page fewer. *[inference]* That page is the
  memory the booter gave the linked driver. How much the booter reserves per
  driver was not measured.

`A1` differs from both `A2` and `B` in one more way, the position of
`Power management is enabled.` relative to the phantom-IRQ lines (see
"The comparison rules as applied").

**The negative control.** `negB` booted the pre-spec-2 kernel with the same
bundle, installed and hash-checked the same way. The booter stopped on its
own screen for ten seconds, and the 9.6 s frame shows the whole driver-loading
sequence:

```
Loading binary for VBE20DisplayDriver device driver.
Error occurred while linking driver VBE20DisplayDriver:
rld(): Undefined symbols:
_VBEModeInfo2IODisplayInfo
Error linking VBE20DisplayDriver device Driver.
Reading configuration file '/private/Drivers/i386/VBE20DisplayDriver.config/Instance0.table'.
Errors encountered while starting up the computer.
Pausing 10 seconds...
```

The kernel's log for that run has none of the driver's lines. At the same
point it has:

```
configureDriver: driver class 'VBE20DisplayDriver' was not loaded
Driver VBE20DisplayDriver could not be configured
```

Neither of those lines appears in `B`. `negB` still registers the other 12
devices. That is expected, because this driver links last.

**The booter screen in the passing case is inconclusive, and is not used as
evidence.** A second with-driver boot, `B2early`, captured every 0.1 s after
the keys. Its last booter frame, at 9.6 s, shows the six earlier drivers
loading with no error between them. It ends on
`Loading binary for VBE20DisplayDriver device driver.`, before the result of
that link. By 9.7 s the kernel's console has replaced it. `B2early`'s
`serial.log` is byte-identical to `B`'s.

## Gate 3: the driver loads

All three lines the gate requires are present in `B` and `B2early`, matched on
their fixed text. The `%s` prints as `VBEDisplay0`. The driver also printed
`Driver loaded to export VBE mode list.` and `No VBE modes found.`

**"Skipping framebuffer initialization" is the correct path, and the input
behind it was measured.** A separate pair of boots saved the guest's physical
`0x11000..0x131FF` with QMP `pmemsave`. The offsets below come from our
`KERNBOOTSTRUCT` layout. The whole of `_reserved` (`0x1138C..0x130D7`) is
zero, on both the verbose and the graphics-mode boot, from the booter's
prompt through 60 s. That includes `0x12854` and `0x12858`. The driver reads
`0x12858` and `0x12870`, and `FBAllocateVBEConsole`'s guards read `0x12854`
and `0x12858`.

**`_VBE20DisplayDriver_instance` caused no trouble.** Spec 1 flagged one
difference as possibly mattering at load time: the reference leaves this
symbol an unallocated common, while our `kl_ld` allocates it. It did not stop
the link, the load, initialisation or registration. Whether anything read the
symbol during this boot is **not established**.

## The graphics-mode boot

**Typing a kernel name does not give a graphics-mode boot on this booter.**
`gC1` typed `mach_kernel` and Return, without `-v`, at 8 s. The booter stayed
in text mode, and the kernel came up on the same 640x480 text console as a
verbose boot.

The graphics panel only appears when the booter's ten-second countdown runs
out untouched. So the graphics-mode runs sent **no keys**. The panel,
"Rhapsody Developer Release 2 / Starting Rhapsody", is on screen by 15 s.
`gC1` was a single boot and is reported only as this observation.

The graphics comparison was run as control, new, control, new, control:
`dC1`, `dN`, `dC2`, `dN2`, `dC3`. A second new-kernel boot and a third control
were added to the planned A-B-A to test a timing difference in one transient
frame (see below).

| Pair | Serial (line 4 date masked; phantom lines excluded from order) | Frames at 45, 60, 95, 120 s |
| --- | --- | --- |
| `dC1` / `dN` | identical | **0 px** |
| `dN` / `dC2` | identical | **0 px** |
| `dC2` / `dN2` | identical | **0 px** |
| `dN2` / `dC3` | identical | **0 px** |
| `dC1` / `dC2` (control against control) | identical | 0 px |

The frames match without any mask, because the graphics console shows no
clock. Every settled frame of all five boots has one SHA-256,
`C0F78DDB...7C247ED`, with the `Configuring Network` panel over the Rhapsody
panel. Line 4, the
build banner, keeps the same config and version text on both kernels;
only the date differs.

**The early frames vary with timing, and that variation is not tied to the
kernel.** At 24 s the three first boots were at three different stages:
`dC1` at "Starting mach messaging server", `dC2` at "Configuring device
drivers" and `dN` at "Configuring network". At 30 s `dN` was already on the
settled panel and both controls were not. The repeat reversed that: `dN2`
was at the controls' earlier stage, and `dC3` showed `dN`'s lead. So the lead
seen in `dN` shows up on the control kernel too.

**The graphics-mode boot hands the kernel no video information.** The two
saved `KERNBOOTSTRUCT` ranges, from a graphics-mode and a verbose boot of the
new kernel, differ in only two fields:

- `bootString`: empty on the graphics boot, `" -v"` on the verbose one.
- `graphicsMode` at `0x1114C`: 1 on the graphics boot, 0 on the verbose one.

`boot_video` (`0x130D8`, 24 bytes) is zero on both. **So this booter does
not write `video.v_baseAddr`, even in graphics mode.** The brief said
graphics mode is "the only path on which the booter writes
`video.v_baseAddr`". That is true of `src/boot-2`, and there only when the
config sets a `Graphics Mode` key (`graphics.c:189-190`); this image's
`System.config` sets none. It is not true of the booter these boots run.

*[inference]* The booter's panel is not a linear VBE mode. It has no `VESA`
or `VBE2` string and no `0x4F02` immediate. What mode it does set was not
determined.

A graphics-mode boot of the new kernel **with** the driver (`dB`) also prints
all five driver lines. Its serial log differs from `dN`'s only in line 9 and
the driver lines (with the phantom lines excluded from the order), and its
settled frames are pixel-identical to `dN`'s.

## The comparison rules as applied

- **Serial line 4.** Only the date is masked, with a strict pattern. The rest
  of the line, `; root(rcbuilder):kernel-154.5.1-7.obj/RELEASE_I386`, must
  match, and it does in every pair.
- **Serial order.** **The phantom-IRQ race is wider than the brief names.**
  All 14 boots in this session, the two memory-dump boots included, log
  exactly eight `intr: phantom IRQ 15, EOI to master` lines.
  Their position moves between boots of the *same* kernel: before or after
  `Power management is enabled.`, split around it (`dN2`), or with one line
  inside the IDE probe block (`dC3`, line 37). Seen in `A1` against `A2`,
  `dN` against `dN2`, and `dC1` against `dC3`. Outside those eight lines,
  every same-configuration pair matches line for line.
- **Frames.** The mask was fixed before the frames were compared. It covers
  the `HH:MM:SS` cells of the two boot-clock text rows, in pixel rows
  102..121: row 102..113 at x 72..135 (the `init:` line) and row 114..121 at
  x 104..167 (the `date` line). The text grid is 8 px by 12 px, from (16, 42).
  - **`B` against `A2`:** 0 px outside the mask. (44 px inside it, all clock
    digits.)
  - **`B` against `B2early`:** 0 px outside the mask.
  - **`A1` against `A2`:** 490 px outside the mask, in text row 4. `A1` has
    `Power management is enabled.` there, `A2` a phantom-IRQ line. This is
    the serial race above, showing on screen, and it happens between two
    boots of the same kernel with no driver. So the verbose-mode frame
    comparison can fail for a same-kernel pair, and it is not used as a gate
    here.

## Captures and hashes

The captures are gitignored and live in the worktree's `vm/shots-t5-*/`.
**They cannot be regenerated.** Every rebuild changes the kernel's build stamp
(serial line 4). The drift between sessions (Task 4 measured 2,518 px between
two boots of the same kernel on one day) means the same boot cannot be
reproduced later. The hashes below are the only durable trace of what was
measured.

| Run | Kernel | Driver | Keys | `serial.log` lines, SHA-256 | Settled frame SHA-256 |
| --- | --- | --- | --- | --- | --- |
| `A1` | new | no | `-v` | 76, `9F92F63957A36D4F00B2F07968F25BF8BED580F008B95C42CC79E3954696A7D4` | `6EFDC4D328C8A1CF53390B559185BCAF0ED76FCDC247060EF14B908C30CC1240` |
| `B` | new | yes | `-v` | 81, `36BECEACC1DE7D774999B19B7672616F7E9F4DEA8D00C462DC210275CEDB9084` | `125C4133B06BB46E8E3D06262EF225C9F44FB3ECCE0BC933CF639FFBC4474F76` |
| `A2` | new | no | `-v` | 76, `9807128AA606AE7D0ABCBAE617EC2248F782D7B596D00FB51A3E89454A53A262` | `D5203E97A0BCF679BEB81FA42A7D1FB95BC196112902D4E4D00096D845B603CD` |
| `negB` | pre-spec-2 | yes | `-v` | 78, `C12DB3154A83503601E053B23EE29C78708BD381F474D66C24C620E1DFD385C7` | `FEE0085EE63256EA117C431F4D07D58036B4C64ECD726DDEAAA61BFB45410A20` |
| `B2early` | new | yes | `-v` | 81, same as `B` | `C636B60A5A665AEDAAEEC2B30E1B8258F45500C44DFC027BD78E496A3763F3F6` |
| `gC1` | control | no | `mach_kernel` | 76, `70190DAFE05BC8238CE82C897469C06B8EA3B54FFCDADDA27CE63880B8A8A456` | `264EEF4806ED8B3130520DD8D00DA3E1612F991FA8851D67EE282705069D8982` |
| `dC1` | control | no | none | 76, `BA96AEBAB0223C392852EF7FDF031CB1AC5FF1349175C8E410AAC9C0A768C51E` | `C0F78DDBF960E899952BBD309674B31E0C01E519A25D1B83D791092CF7C247ED` |
| `dN` | new | no | none | 76, same as `A2` | same as `dC1` |
| `dC2` | control | no | none | 76, same as `dC1` | same as `dC1` |
| `dN2` | new | no | none | 76, `F270EA4C79F5704FBBF6F8B61CD5863D9E3646DDFC32D45D6AF65FA2D8D66885` | same as `dC1` |
| `dC3` | control | no | none | 76, `A4AFB1B5451102421365A476EB36825F1B3FB4BF968D6E9742CDB72C8C0B6E3D` | same as `dC1` |
| `dB` | new | yes | none | 81, `ABD376F17DE47FB3D792BBF72B12442DB5095364EC1C4D67A42095E92E786297` | same as `dC1` |

"Settled frame" is the 95 s capture; in each run it is identical to the 60 s
one, and in the no-keys runs to 45 s and 120 s as well. Other frames cited
above:

- `negB` 9.6 s, the booter's link error: `0D457D238718FA05FA835D0EF1580705274F4C0C56F20D47F7A4C5C957B21001`.
- `B2early` 9.6 s: `672A287DEDC6704E8092DA94933AA5188E2D6BEB88BD7A8AD470E4EFDE0BE127`.
- `dC1` 15 s, the graphics panel: `2D8B530DCEB2BBD88A185183B852A76660E4EBD9EDDF5261021F1D52E7F32E1D`.

The `KERNBOOTSTRUCT` dumps, 8,704 bytes each:

- `shots-t5-kbsG/kbs-16s.bin`, graphics mode, identical at 30 s and 60 s:
  `112527A34A5B5F201675E2BA46F14A69177D3D32C024F467BD7DBA03A03741E4`.
- `shots-t5-kbsV/kbs-30s.bin`, verbose, identical at 12 s and 60 s:
  `BF8E76C552B2A347C3F3740D7EEB6500BE45B7DC8966E363F1F68CF6A53F56C6`.

`A2`'s and `dN`'s `serial.log` are byte-identical to Task 4's
`shots-t4c-post`. `dC1`'s and `dC2`'s are byte-identical to Task 4's
`shots-t4c-preC`. `B`'s settled frame is byte-identical to Task 4's `post2`
and `preC`. So this afternoon's boots landed in the same timing state as
Task 4's third pass.

## What this does and does not establish

It establishes:

- The new kernel exports what the driver needs. `sarld` links the
  reconstructed driver against it without error, and the driver instantiates,
  initialises, logs, reports an empty mode list and registers as
  `VBEDisplay0`. The pre-spec-2 kernel, given the same bundle, fails exactly
  as spec 1 predicted: an undefined `_VBEModeInfo2IODisplayInfo`.
- Linking the driver costs no other boot driver its registration. As noted
  under Gate 2, that check is structurally weak.
- On the default graphics-mode path, the new kernel's console output matches
  the pre-Task-4 kernel's. Across five alternating boots, the settled frames
  are pixel-identical and the serial logs identical, apart from the build date
  and the phantom-IRQ race.
- On this image, `FBAllocateVBEConsole`'s guard inputs are zero on both boot
  paths, measured in guest memory rather than inferred. So the new arm returns
  `NULL` and the VGA console is used, as intended.
- `_VBE20DisplayDriver_instance` being allocated rather than common does not
  prevent the load.

It does **not** establish:

- **That the frame-buffer console works.** Nothing has run
  `FBAllocateVBEConsole` past its guard. Nothing writes `0x12854`/`0x12858`
  until spec 3 supplies a producer.
- That `VBEModeInfo2IODisplayInfo` runs correctly. The driver links against
  it, but the "Skipping" path never calls it. Its evidence is still the byte
  comparison.
- Anything about the driver's `using VBE mode %d` path, its mode-list export
  with a non-empty list, or its `getCharValues:` parameters.
- Anything about `src/boot-2`. Every boot here ran Apple's v5.0.41.1 booter.
- Anything on hardware. These are QEMU `pc` boots with a Cirrus adapter.
