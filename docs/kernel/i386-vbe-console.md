# i386 VESA kernel support: boot gates, run 2026-09-22

Spec 2 added two functions to the i386 kernel, `VBEModeInfo2IODisplayInfo`
and `FBAllocateVBEConsole`, and a call to the second from
`BasicAllocateConsole`.
The byte checks passed earlier (see
`src/kernel-7/reconstruction/vbe/divergences.md`). This page records the boot
gates that followed.

Spec 3 (the booter enters a VBE mode and the kernel maps the frame buffer)
extends this record: its gates G1 to G5, run 2026-09-23, are in
[Spec 3](#spec-3-the-vbe-booter-and-the-frame-buffer-console-run-2026-09-23)
at the end. Its G5 refutes one spec 2 inference below, and each place that
states it is labelled.

**All three gates pass.**

- **Gate 2.** `sarld` links spec 1's reconstructed `VBE20DisplayDriver` against
  the new kernel. The evidence is positive: the driver's own messages appear in
  the log, and no other boot driver is lost — though that check is weak by
  itself, since this driver links last in `Boot Drivers`, so nothing links
  after it for a failure to take down. *[inference, see below]* An
  undefined-symbol link failure would not cascade at other positions either.
  **[REFUTED — spec 3 G5, measured at the first position: the next link
  fails with `rld(): virtual memory exhausted (malloc failed)`, every later
  one is refused, and the kernel panics `Missing EISA kernel bus class`.]**
- **Gate 3.** The driver loads and prints all three expected lines, plus two
  more.
- **Graphics mode.** Booted in graphics mode, the new kernel behaves exactly
  like the pre-Task-4 kernel, apart from the build date and the phantom-IRQ
  race.

A **negative control** shows the failure these gates were built to catch. The
same driver on a kernel without the symbol fails at the booter with
`rld(): Undefined symbols: _VBEModeInfo2IODisplayInfo`, and the kernel logs
`configureDriver: driver class 'VBE20DisplayDriver' was not loaded`.
**[Stock booter only. Spec 3's booter no longer passes a driver that failed
to link to the kernel, so this kernel line would not appear with it
(*[inference, from the code]*, not booted); see spec 3's limits.]**

## What was booted

Every input was hashed just before use, and each image was read back before
its boot.

| Role | File | Bytes | SHA-256 |
| --- | --- | --- | --- |
| New kernel (Task 4 build of `e2d02efe8`) | `vm/work/task4c-mach_kernel` | 1,490,352 | `74B12FCD53E886AAFCBB29AD400C5DEDD10B26F04BBA0FBC6E02DAEFEA25CFF4` |
| Control kernel (pre-Task-4) | `vm/work/task3-mach_kernel-final` | 1,490,352 | `1C0F8B804A5ECEF5124B3FCE9C3335356B7692B7C1FD11E2A40CFD6B87F7215D` |
| Negative-control kernel (pre-spec-2) | the main checkout's gitignored `vm/install/mach_kernel`, built `Fri Sep 18 12:06:49 PDT 2026` | 1,486,184 | `9916E7C0BDAC2D4E28A5236AC303677A7A45A8ABFE229B307CEBEAC70721CF8D` |
| Driver `_reloc` (spec 1's `$DRVBUILT`) | `.worktrees/vbe20-recon/out/i386/drvVBE20DisplayDriver/VBE20DisplayDriver.config/VBE20DisplayDriver_reloc` | 102,412 | `77399531152E287487668F6222467CF9C1ECA449859B169A66352B608A3A36A1` |
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

**No other boot driver lost.** `A1` and `A2` each register the same 12 devices: `hc0` and
`hd0` (EIDE), `ISASerialPort0`, `fc0` (Floppy), `PS2Controller` and
`PCKeyboard0` (PS2Keyboard), `PCI0`, `EISA0`, `event0`, `kmDevice0`,
`Display0` and `en0`. `B` registers all 12, plus `VBEDisplay0`. None is
missing.

This check is weaker than it looks, for two independent reasons.
`VBE20DisplayDriver` is last in `Boot Drivers`, and the cascade described in
`docs/boot/sarld-driver-link-limit.md` only hits drivers linked *after* a
failure — so a failure of this driver's link could not have shown up as a
lost boot driver. Separately, *[inference, from
`src/cctools-2/ld/symbols.c:3523`/`ld.c:2059` and
`rld.c:402-405`/`1493`/`1674-1676`]*: an undefined-symbol error is raised via
`error()`, which unloads only the one driver, not via `fatal()`→`cleanup()`,
which is what sets the cascade latch that `sarld-driver-link-limit.md`
describes — and that document's cascade is specific to a malloc fatal
(`rld(): virtual memory exhausted`), a different failure class from this
driver's undefined symbol. So this failure would not have cascaded at any
position, not merely because it linked last. **[REFUTED — spec 3 G5: with
the driver first, the undefined-symbol error is followed by exactly that
malloc fatal on the next driver, EIDE, and the latch then refuses the other
five. The `error()`/`fatal()` reading holds for the first error; what it
missed is that the next link can fail on memory.]** Gate 2 therefore rests on the
driver's own lines and on the negative control below. The negative control
does not settle the cascade question either way, since it too links the driver
last; commit `4d6f874bc`'s message says it "confirms" the no-cascade reading,
and it cannot.

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
devices, and it does not panic. That is expected, because this driver links
last: nothing links after it to be lost, and `EISABus`, the driver whose loss
spec 1's predicted `panic: Missing EISA kernel bus class` names, links before
it. So this run observed only the undefined-symbol failure, in a position
where a cascade could not show. That it would not cascade elsewhere is the
inference above, not a result of this run. **[REFUTED for the first
position — spec 3 G5.]**

**Provenance gap.** `negB`'s kernel is pre-spec-2 by build date (`Fri Sep 18
12:06:49 PDT 2026`) and lacks both new symbols, but its exact source revision
was not recorded, and it is 4,168 bytes smaller than the new kernel
(1,486,184 vs 1,490,352) — a second, unexplained difference. This does not
weaken the conclusion: the booter's own error names the missing symbol
directly (`rld(): Undefined symbols: _VBEModeInfo2IODisplayInfo`), independent
of whatever else differs between the two kernels.

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
not write `video.v_baseAddr`, even in graphics mode.** The plan's Task 5
Step 3 said graphics mode is "the only path on which the booter writes
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
- **Serial order.** **The phantom-IRQ race is wider than the plan's rule 2
  ("The comparison, tightened") names.**
  All 14 boots in this session, the two memory-dump boots included, log
  exactly eight `intr: phantom IRQ 15, EOI to master` lines.
  Their position moves between boots of the *same* kernel: before or after
  `Power management is enabled.`, split around it (`dN2`), or with one line
  inside the IDE probe block (`dC3`, line 37). Seen in `A1` against `A2`,
  `dN` against `dN2`, and `dC1` against `dC3`. Outside those eight lines,
  every same-configuration pair matches line for line.
- **No gate rests on this widened rule.** The planned A-B-A triple
  (`dC1`/`dN`/`dC2`) passes that rule 2 as the plan states it, unmodified: their raw
  serial diffs are empty even without excluding the phantom lines. Only the
  two pairs added afterward to chase the timing anomaly, `dC2`/`dN2` and
  `dN2`/`dC3`, needed the wider exclusion to read as identical. The table
  below applies the widened rule uniformly for convenience, but no gate
  depends on the widening.
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
  `VBEDisplay0`. The pre-spec-2 kernel, given the same bundle, fails with the
  undefined symbol spec 1 predicted, `_VBEModeInfo2IODisplayInfo`. The cascade
  and panic spec 1 also predicted were not seen, but with the driver linked
  last this run could not have seen them. That they would not occur at other
  positions is an inference from `rld.c`, recorded under Gate 2.
  **[REFUTED for the first position — spec 3 G5 measured both the cascade
  and the panic there.]**
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
  until spec 3 supplies a producer. **[UPDATED — spec 3 G2: it works on
  QEMU, at VBE mode 257.]**
- That `VBEModeInfo2IODisplayInfo` runs correctly. The driver links against
  it, but the "Skipping" path never calls it. Its evidence is still the byte
  comparison. **[UPDATED — spec 3 G2: it now runs, inside
  `FBAllocateVBEConsole`, for one 8 bpp mode; see spec 3's limits.]**
- Anything about the driver's `using VBE mode %d` path, its mode-list export
  with a non-empty list, or its `getCharValues:` parameters. **[UPDATED —
  spec 3 G2 exercised the first two; `getCharValues:` is still untested.]**
- Anything about `src/boot-2`. Every boot here ran Apple's v5.0.41.1 booter.
  **[Spec 3's G1 to G3 ran `src/boot-2`.]**
- Anything on hardware. These are QEMU `pc` boots with a Cirrus adapter.

## Spec 3: the VBE booter and the frame-buffer console, run 2026-09-23

Spec 3 gave our booter, `src/boot-2`, OPENSTEP 4.2 User Patch 4's VBE code.
It enumerates the VBE modes on every boot into `vbeModes` (`kbs+0x1870`).
When a loaded driver's table has a `VBE Mode` key, it sets that mode last,
from text mode, and records it in `vbeCurrentMode` (`kbs+0x1858`). The
kernel then maps that mode's frame buffer in `pmap_bootstrap`, reserves the
range, and publishes the mapped address at `0x12854` (`kbs+0x1854`). So
`FBAllocateVBEConsole` gets past its guard, and the boot console draws
through the frame-buffer console. The byte and build evidence is in
`src/boot-2/reconstruction/vbe/divergences.md` and
`src/kernel-7/reconstruction/vbe/divergences.md`. This part records the boot
gates of spec 3's design, §7, in the form revised after its Task 3.

- **G1 passes. Without a VBE mode, nothing changes for the kernel.** The
  new booter against Task 5's: identical serial, identical kernel-phase
  frames, `kbs+0x1854..0x186F` and `boot_video` zero. As 4.2 does, the new
  booter fills the mode array on every boot. A default boot shows 4.2's
  mode-`0x12` panel and hands the kernel `graphicsMode` 1.
- **G2 passes. The VBE path works on QEMU cirrus at mode 257.** The booter
  records the mode and 8 mode records, and the kernel publishes
  `0x0D3D4000`. The driver logs `using VBE mode 257` and eight mode lines,
  and the kernel's scrolling console draws through the frame buffer at
  640x480.
- **G3 passes, both cases.** For `VBE Mode` = 999 the booter prints `VBE
  mode 999 not supported.` and `Using VBE Mode 257.`, then boots as G2. On
  QEMU's `isa-cirrus-vga` it prints `VESA not available.`, writes no record,
  and the kernel's VGA console follows.
- **G4 passes. With the stock booter, the new kernel matches spec 2's.**
  The driver takes its "Skipping" path, the serial matches but for the build
  date, and `0x12854` stays zero.
- **G5 is measured: with the driver first and the symbol missing, the
  failed link cascades.** The next driver's link fails with `rld(): virtual
  memory exhausted (malloc failed)`, the other five are refused, no device
  registers, and the kernel panics `Missing EISA kernel bus class`. This is
  a finding about the stock `sarld`, not a failure of spec 3. It refutes
  spec 2's no-cascade inference for the first position, and the four places
  above that state it are labelled. **The failed link, not the order, sets
  it off** [measured, by a control boot added after review]: the same order
  with the stock booter, on the final kernel, which has the symbol, links
  all seven boot drivers and registers every device. How the failed link
  leads to the next link's malloc failure was not determined.
  **[QUALIFIED — final review m3: the two runs differ in the kernel as
  well as in the symbol. The negative-control kernel is 4,168 bytes smaller
  than the final one, for reasons spec 2's provenance gap left unrecorded.
  The G5 section says so; this summary did not.]**

### What was booted

Every input was hashed before the first boot. Every image was rebuilt from
`golden.img` and read back before its boot.

| Role | File | Bytes | SHA-256 |
| --- | --- | --- | --- |
| Final booter (Task 7c build, the sources of `a0cc94d34`) | `vm/work/t7c-boot` | 45,008 | `8AA489F19C80875AE9149647C94C7AB526FD116338F1014B4AED464347547735` |
| G1 control booter (Task 5 build, the sources of `3ba0a3466`) | `vm/work/t5-ours-boot` | 44,384 | `A75FCA09F27B28A46A5626289F4A36335FAB273F556341390E5461B9C556F31A` |
| Final kernel (Task 8c build, the sources of `85636dc91`) | `vm/work/t8c-mach_kernel` | 1,490,352 | `56A4B3433A6E519018FA0631DA91B7731BB65C382EDEDDDC3BEE623701BE69E2` |
| Spec 2 kernel (G4 control; spec 2's "new kernel") | `vm/work/task4c-mach_kernel` | 1,490,352 | `74B12FCD53E886AAFCBB29AD400C5DEDD10B26F04BBA0FBC6E02DAEFEA25CFF4` |
| G5 kernel (spec 2's negative control) | `vm/work/negctl-mach_kernel` | 1,486,184 | `9916E7C0BDAC2D4E28A5236AC303677A7A45A8ABFE229B307CEBEAC70721CF8D` |
| Driver `_reloc` | `VBE20DisplayDriver.config/VBE20DisplayDriver_reloc` (spec 2's bundle) | 102,412 | `77399531152E287487668F6222467CF9C1ECA449859B169A66352B608A3A36A1` |
| Driver `Default.table` (`"VBE Mode" = "257"`) | same bundle | 482 | `02EF18A5D57FF8DA03543211DB8F12799803B6B2A0A7812114405A4B73C04C15` |
| Driver `VBE20DisplayDriver` | same bundle | 9,472 | `B75EF6A698C443CD3621B052AA4B8BBBEE886789808681C5C600756B076B3901` |
| Driver `English.lproj/Localizable.strings` | same bundle | 87 | `C2FDA3A61DAE9401149166FBC3E913AB4D605D222AFB109619D4D824AA54AF5A` |
| Master image | `D:/RhapsodiOS/vm/golden.img` | 8,589,934,592 | `E1968E3EF57F3060AA01CEAB8B4D5C49C067E6ACC5F8626EBABEEFE0E663879F` |
| Stock booter (G4, G5) | both boot slots of that image | 39,616 | `AA06C3C5BFE56C79573E36D20C662DA10CA67D0CEC5BE17F13A5B562F6B5F2C2` |
| `sarld` (every boot) | `/usr/standalone/i386/sarld` in that image | 148,108 | `BBFB53F28725908DCC54E247EDEFD6BD78C9B5405D0C95E4B0D8B33D131AFEBA` |

- The bundle also holds an empty `VBE20DisplayDriver_reloc.err`, which is
  installed and read back with the rest.
- `git status --short src/` was clean before the first boot. Nothing was
  synced or built. No `src/boot-2` or `src/kernel-7` commit follows the
  commits named above.
  **[UPDATED — after the final review: two source commits now follow, and
  the final artifacts are `vm/work/tfin-boot` (`584f61abb`) and
  `vm/work/tfin-mach_kernel` (`ac27eb145`), not the Task 7c and 8c builds in
  this table. G1 to G5 ran with those. The final artifacts were re-checked
  by three boots; see "After the gates: the final booter and kernel".]**
- The negative-control kernel still has neither `_VBEModeInfo2IODisplayInfo`
  nor `_FBAllocateVBEConsole`. The other two kernels define both.
- **Which booter ran.** Ours prints `Rhapsody boot v5.0.2` on its 5 s frame,
  the stock booter `Rhapsody boot v5.0.41.1`. Every boot below that counts
  shows the right one. The banner cannot tell our two booters apart; the
  boot-slot readback does.

### Procedure

All runs were made in the `vbe20-kernel` worktree, one QEMU at a time, on
2026-09-23 between 12:08 and 13:23 EDT; G5's control boot, added after
review, between 13:56 and 14:09 EDT. Before every boot, `vm/work/test.img`
was rebuilt from `golden.img` in this order:

```bash
MSYS_NO_PATHCONV=1 python graft-kernel.py D:/RhapsodiOS/vm/golden.img <kernel> work/test.img
# with the driver; the intermediate copy was staged on another disk:
MSYS_NO_PATHCONV=1 python install-driver.py <staged copy> <bundle> work/test.img [--first]
# G3 case 1 only:
MSYS_NO_PATHCONV=1 python rhap_inject.py work/test.img set-key \
    /private/Drivers/i386/VBE20DisplayDriver.config/Instance0.table "VBE Mode" 999
# with our booter; writes and verifies both boot slots:
MSYS_NO_PATHCONV=1 python install-booter.py work/test.img <booter>
```

Then these were read back out of the image:
- `/mach_kernel`, and every file of the bundle, against their sources;
- `Instance0.table`, which equalled `Default.table`, with `999` in G3 case 1;
- `Boot Drivers`, with the driver last, or first with `--first`;
- `Active Drivers`, left as shipped: `CirrusLogicGD5434DisplayDriver
  BusMouse NE2K`;
- both boot slots: our booter followed by zeros, or byte-equal to
  `golden.img`'s.

All matched. System.config has no `VBE Mode`, `VBE Check` or `Query` key.
The image was then hashed; the hashes are in the table below.

- **Boots** used `qemu-shot.py --vga cirrus` with `--pmemsave
  60:0x11000:0x2200`.
- **Verbose runs** typed `--keys $'mach_kernel -v\n' --keys-at 8`.
  **Default runs** sent no keys.
- **One comparison, one `--at` list:** all runs in a comparison used the
  same one.
- **G3 case 2** used a throwaway wrapper. It loads `qemu-shot.py`
  unchanged, and replaces only its `-vga cirrus` with `-vga none -device
  <device>`.

The comparison rules are spec 2's, with rule 4 as amended in spec 3's
Task 5:
- serial line 4 has only its date masked;
- the IDE-probe line, `Power management is enabled.` and the eight
  `intr: phantom IRQ 15, EOI to master` lines may change places;
- frames are compared outside the clock-cell mask above. A candidate passes
  when it equals a control there, or differs only where the two controls
  differ from each other.

### G1: nothing changes for the kernel without a VBE mode

Final kernel, no driver, no `VBE Mode` key. Verbose A-B-A: `A1` Task 5's
booter, `B` the final booter, `A2` Task 5's booter. Then `Bdef`, the final
booter with no keys.

- **Serial.** `A1` and `B` are byte-identical, line 4 included. `A2` moves
  `Power management is enabled.` among the phantom lines, and is otherwise
  identical.
- **Kernel-phase frames.** `B` equals `A1` pixel for pixel at 15, 30, 60
  and 120 s. `A2` differs from both by 980 px at 15 s and by 490 px in the
  settled frames. That is the phantom-line race, the difference the amended
  rule 4 allows.
- **Booter-phase frames**, recorded, not compared. The 5 s prompt is one
  frame in all three runs. A verbose boot draws no panel, even with the new
  booter's panel code.
- **Dumps.** `graphicsMode` is 0 in all three. `kbs+0x1854..0x186F` is zero
  in all three. `boot_video` (`0x20D8..0x20EF`) is zero in all three.
- **`A1` = `A2`,** with no VBE bytes.
- **`B`'s mode array is filled, as 4.2 fills it on every boot.** It holds 8
  records from `0x1870`:

  | Mode | Size | Depth |
  | --- | --- | --- |
  | 257 | 640x480 | 8 |
  | 272 | 640x480 | 15 |
  | 259 | 800x600 | 8 |
  | 275 | 800x600 | 15 |
  | 261 | 1024x768 | 8 |
  | 278 | 1024x768 | 15 |
  | 263 | 1280x1024 | 8 |
  | 281 | 1280x1024 | 15 |

  - Every record has attributes `0x00BB` and frame buffer `0xFC000000`.
  - The 9th record is zero, and so is everything after it.
  - `A1` and `B` differ in 103 bytes, all inside `0x1870..0x192F`.
- **Default boot (`Bdef`).**
  - At 11 to 15 s it shows **4.2's 352x264 mode-`0x12` panel**, "Rhapsody
    Developer Release 2 / Starting Rhapsody" with the wait cursor. Its
    non-background pixels lie in x 152..494, y 108..370. The 13 s frame is
    byte-identical to Task 7a's panel frame.
  - From 20 s the kernel's graphical console follows. From 30 s it is
    spec 2's settled `Configuring Network` frame.
  - **The kernel receives `graphicsMode` 1**, Task 3b's reading of 4.2.
    The dump differs from `B`'s only in `bootString` and `graphicsMode`.
  - The serial is `B`'s, with one phantom line moved. It ends at `Continue
    without network? (y/n)`.

### G2: the VBE path

Final booter, final kernel, and the driver last in `Boot Drivers` with
`VBE Mode` = 257, on cirrus. Two runs: `g2-v` (verbose) and `g2-d`
(default).

- **Dump.** Both runs agree:
  - `0x12854` = `0x0D3D4000`;
  - the record at `0x12858` names **mode 257** (640x480, 640 bytes per
    line, 8 bpp, model 4, frame buffer `0xFC000000`);
  - **8 records** from `0x12870`, G1's eight, and the 9th is zero;
  - `graphicsMode` is 0 on both, the default boot too.

  The two dumps differ only in `bootString`. Each is byte-identical to
  Task 8c's dump of the same boot.
- **Serial**, 88 lines each. The driver's lines, straight after
  `Registering: EISA0`:

  ```
  Display0: VESA video driver initialization.
  Display0: using VBE mode 257
  Display0: VBE mode 257 is width=640, height=480, bpp=8
  Display0: VBE mode 272 is width=640, height=480, bpp=15
  Display0: VBE mode 259 is width=800, height=600, bpp=8
  Display0: VBE mode 275 is width=800, height=600, bpp=15
  Display0: VBE mode 261 is width=1024, height=768, bpp=8
  Display0: VBE mode 278 is width=1024, height=768, bpp=15
  Display0: VBE mode 263 is width=1280, height=1024, bpp=8
  Display0: VBE mode 281 is width=1280, height=1024, bpp=15
  Registering: Display0
  ```

  That is one mode line per record. No line the booter prints appears in
  the serial log. Set against G1's `B`, the other differences are:
  - line 9, one page fewer (as in spec 2);
  - the Cirrus driver now `Display1`, with one more line, `Display1: Can't
    set memory range, using default.`. That line appears in every cirrus
    boot where the driver takes the VBE path, since spec 3's Task 7, and in
    none where it skips. *[inference]* The VBE driver already holds the same
    frame buffer range.
- **The kernel's scrolling text console draws through the frame-buffer
  console at 640x480.** Every frame from 20 s on is 640x480: a white
  480x360 window titled `Rhapsody Operating System` at (80, 60), black text,
  on a slate `(103,103,152)` ground. The border runs x 77..562, y 57..422.
  Both runs end on one frame, the text scrolled to `Continue without
  network? (y/n)`. The default boot is also this text console: the booter
  hands the kernel `graphicsMode` 0 and draws nothing in the VBE mode.
- **`boot_video`** is zero, as in G1's dumps.
- **First frame:** our banner, in both runs.
- **Booter-phase frames**, recorded. `g2-d` shows the panel from 11 s,
  with `Loading Rhapsody` and then `Reading Rhapsody configuration`.

### G3: the fallback

**Case 1, `VBE Mode` = 999** (`g3-999`, default boot, frames every second
from 10 to 24 s):
- Frames 13 to 18 s show the panel.
- **Frames 19 to 23 s** show the booter's text screen, the 5 s pause:

  ```
  VBE mode 999 not supported.
  Using VBE Mode 257.
  ```

- From 24 s on it is G2's console window, ending on G2's final frame.
- **The dump is byte-identical to `g2-d`'s** (mode 257, 8 records,
  `0x0D3D4000`).
- The serial has `using VBE mode 257` and the eight mode lines. It differs
  from `g2-d`'s only in where the IDE-probe and phantom lines fall.

**Case 2, an adapter with no usable VBE.** Two QEMU devices were tried, each
as `-vga none -device <device>` with G2's image, default boot.
- **`isa-vga` offers usable VBE**, so it is not this case.
  - The booter records 27 usable modes, every one with a linear frame
    buffer at `0xE0000000` (8, 15 and 32 bpp, from 640x480 to 1920x1080).
  - The booter sets mode 257, the driver logs `using VBE mode 257` and 27
    mode lines, and the frame-buffer console window draws as on cirrus.
  - So G2's path also ran on a second adapter model.
- **`isa-cirrus-vga` offers no usable VBE.** This is the case.
  - Frames 11 to 16 s show the panel.
  - **Frames 17 to 21 s** show the single line **`VESA not available.`**
  - **From 22 s the kernel's VGA console** appears, 640x480 in 16 colours.
    It has the same geometry as G1's verbose frames, and ends at `Continue
    without network? (y/n)`.
  - **The dump has no record:** `0x1854..0x20D7` is zero, the current mode
    included. **`graphicsMode` is 0**, although this default boot's panel
    had set it to 1. `boot_video` is zero.
  - The driver takes spec 2's path: `Skipping framebuffer initialization
    (card not in VBE mode).`, `Driver loaded to export VBE mode list.`, `No
    VBE modes found.`, `Registering: VBEDisplay0`.
  - The Cirrus driver finds a `GD5430` and rejects it (`unsupported PCI
    hardware`). `driverLoader` then registers `VGADisplay0`.
  - Why this adapter has no usable mode was not determined. *[inference]*
    Its BIOS lists modes without a linear frame buffer, because an ISA card
    has no PCI BAR to report one, and `vbeModeIsUsable` requires that
    attribute.
    - That is one cause among several. `VESA not available.` is printed
      whenever `enumerateVBEModes()` returns 0 (`vbe.c:196-198`). It also
      returns 0 when `getVBEInfo` fails, or when `VESAVersion` is below
      `0x200` (`vbe.c:139-143`). And the reproduced `VideoModePtr` defect
      (`vbe.c:145-153`) reads the mode list from the wrong address whenever
      the BIOS's segment is not 0. Which of these held was not determined.
      **[UPDATED — after the final review: the final booter forms that
      address as `segment * 16 + offset` (review I3). This case was not
      re-run with it, so whether its result depended on the defect is still
      not determined.]**
- **`No usable VBE mode. Reverting to VGA.`** was not seen. *[inference,
  `vbe.c:196-215`]* With this code it cannot be: it needs
  `enumerateVBEModes()` to return non-zero while `vbeModes[0]` is empty.

### G4: the kernel alone

Stock booter and the driver, last. Verbose A-B-A: `A1` spec 2's kernel,
`B2` the final kernel, `A2` spec 2's kernel.

**One `B` run is void.** Its 5 s frame caught the stock booter before its
banner (`Sizing memory... 131048K`), so by the rule it proves nothing. It
was rerun at once as `B2`, with the same arguments. (Its serial and dump
match `B2`'s under the rules. Its settled frames, at 60 and 120 s, equal
`A2`'s outside the clock mask. Its 30 s frame was mid-boot, 14,901 px from
its own 60 s frame.)

- **Both kernels log `Skipping framebuffer initialization (card not in VBE
  mode).`** They also log spec 2's other four driver lines, and neither logs
  `using VBE mode`.
- **Serial.** Line 4 differs only in its date. With phantom lines set aside,
  `A1`, `B2` and `A2` are identical.
- **`0x12854` is zero in `B2`'s dump.** All four dumps are one file:
  `kbs+0x1854..0x20D7` zero, `graphicsMode` 0, `boot_video` zero. The stock
  booter records nothing.
- **Frames.**
  - At 60 and 120 s, `B2` equals `A1` outside the clock mask. `A2` differs
    from both by 490 px, in one text row: the phantom race.
  - At 30 s, rule 4 reports 490 px in that row where `A1` and `A2` agree and
    `B2` does not. **This is a methodology artefact, not a kernel
    difference.** `A1` ran late: its 15 s frame is still the booter, and its
    `init` stamp reads `05:00:21` against `05:00:14`. So its 30 s frame is
    mid-boot, two text lines short of the settled screen, and 14,775 px from
    its own 60 s frame. Scrolled two lines less, its row 4 happens to hold
    a phantom line, as `A2`'s does. `B2`'s 30 s frame equals its own 60 s
    frame.
  - The 15 s frames are not comparable: `A1`'s is the booter's, the others
    the kernel's.

### G5: link order

Negative-control kernel, stock booter, verbose. `C1` and `C2` had no driver.
`N` had the driver installed with `install-driver.py --first`, and its
`Boot Drivers` read back `VBE20DisplayDriver EIDE ISASerialPort Floppy
PS2Keyboard PCIBus EISABus`. Frames were taken every 0.1 s from 8.2 to
20 s, the same list for all three.

**The booter's driver-loading lines are in `N`'s frames.** The 9.5 s frame
shows:

```
Loading binary for VBE20DisplayDriver device driver.
Error occurred while linking driver VBE20DisplayDriver:
rld(): Undefined symbols:
_VBEModeInfo2IODisplayInfo
Error linking VBE20DisplayDriver device Driver.
Reading configuration file '/private/Drivers/i386/VBE20DisplayDriver.config/Instance0.table'.
Loading binary for EIDE device driver.
Error occurred while linking driver EIDE:
rld(): virtual memory exhausted (malloc failed)
Error linking EIDE device Driver.
Reading configuration file '/private/Drivers/i386/EIDE.config/Instance0.table'.
Loading binary for ISASerialPort device driver.
Error occurred while linking driver ISASerialPort:
previous fatal errors occured, can no longer succeedError linking ISASerialPort device Driver.
```

The screen at 9.8 s stays up for the 10 s pause. On it, `Floppy`,
`PS2Keyboard`, `PCIBus` and `EISABus` each fail with `previous fatal errors
occured, can no longer succeed`. Then come `Errors encountered while
starting up the computer.` and `Pausing 10 seconds...`.

**`N`'s kernel log has 13 lines.** After the BSD copyright it reads
`panic: Missing EISA kernel bus class`, with no `ISA bus`, no `DriverKit
version`, and **no `Registering:` line**. The console shows `System Panic: /
Missing EISA kernel bus class / (Type 'r' to reboot or 'm' for monitor)`.
`C1` and `C2` each register spec 2's 12 devices: `hc0 hd0 ISASerialPort0
fc0 PS2Controller PCKeyboard0 PCI0 EISA0 event0 kmDevice0 Display0 en0`.

**So at the first position the failed link cascades, and takes down all
six other boot drivers.** That the failed link, and not the order, is what
sets it off is measured by the control boot below.
- The first failure is the undefined symbol. The booter reports it and moves
  on to the next driver, as spec 2's `rld.c` reading said.
- The next link, EIDE's, then fails on memory. That is a fatal error, and
  `rld`'s latch refuses everything after it. This is the cascade in
  `docs/boot/sarld-driver-link-limit.md`, with its panic, and it matches
  spec 1's original prediction.
- *[inference]* The failed link uses up nodes of the stock `sarld`'s
  1,000-node allocator, the limit that document describes, and EIDE's link
  runs past it. Whether the failed link leaks those nodes, or only uses
  them, was not determined.
- A successful first link does not do this. Spec 3's Task 7c booted the
  driver first against spec 2's kernel, which has the symbol, with the
  same `sarld`, and all seven boot drivers registered. **Those boots
  (`shots-t7c-red-first-b`, `shots-t7c-green-first`) ran our booter, not
  the stock one.** The control boot below repeats the order with the stock
  booter.
- The rebuilt 8,000-node `sarld` that document describes is not on
  `golden.img`, and was not tried.

This is a finding about `sarld`, recorded, not a failure of spec 3. It turns
spec 2's "an undefined-symbol link failure would not cascade at other
positions either" from an inference into a refutation, **for the first
position**. The middle positions were not tried.

**The control boot, added after review: the driver first, with the
symbol.** G5 as first run left one question open. Did the driver-first
order set off the cascade, rather than the failed link? The clean
driver-first boots above ran our booter. Both booters load the same `sarld`
from the image, but the order had not been tried with the stock booter. So
one more verbose A-B-A was run, with G5's `--at` list and a dump at 60 s:
- **`A1` and `A2`:** the final kernel (`t8c`, which has the symbol), the
  stock booter, and the driver last. This is G4's `B2` image.
- **`B`:** the same, with the driver installed by `install-driver.py
  --first`. `Boot Drivers` read back `VBE20DisplayDriver EIDE ISASerialPort
  Floppy PS2Keyboard PCIBus EISABus`.

Every readback matched, as in the procedure above. In addition,
`/usr/standalone/i386/sarld` was read out of each image (`BBFB53F2...`),
and both boot slots hashed as the stock booter (`AA06C3C5...`). All three
5 s frames are `A5149E2C...`, `Rhapsody boot v5.0.41.1`.

**All seven boot drivers link, and every device registers** [measured]:
- **`B`'s booter lines are in frame.** Its last booter frame, at 9.9 s,
  shows `Loading binary for VBE20DisplayDriver device driver.` and its
  `Reading configuration file` line. Then EIDE, ISASerialPort, Floppy,
  PS2Keyboard and PCIBus each load, then `Loading binary for EISABus device
  driver.`, with no error line anywhere. By 10.0 s the kernel's console has
  replaced it, so EISABus's own result is not in frame. There is no
  `Pausing 10 seconds...`.
- **The controls' booter lines are in frame too.** `A1`'s at 10.0 s and
  `A2`'s at 9.7 s each show the six stock drivers and then
  `VBE20DisplayDriver` loading, with no error, and `Starting Rhapsody`.
- **Serial** (81 lines each). `B` registers 13 devices:
  - `VBEDisplay0` first, straight after `DriverKit version 500`, with spec
    2's five driver lines;
  - then `hc0 hd0 ISASerialPort0 fc0 PS2Controller PCKeyboard0 PCI0 EISA0
    event0 kmDevice0 Display0 en0`.

  `A1` and `A2` register the same 13, with the driver's five lines after
  `Registering: EISA0`. Against `A1`, with line 4's date masked, `B`
  differs only in where those five lines fall. Line 9 is the same. No run
  panics.
- **Controls against each other and against G4.** `A1` against `A2`: the
  phantom lines alone move. With the phantom lines set aside, `A1` and `A2`
  are identical to G4's `B2`.
- **Dumps.** `A1` = `A2` = G4's four (`E38F01A8...`). `B`'s differs from
  them in 29 bytes, in `0x16C..0x19D`, the boot-driver bookkeeping.
  `kbs+0x1854..0x20D7` and `boot_video` are zero, and `graphicsMode` is 0.
- **Frames.**
  - At 30, 60 and 120 s, rule 4 reports 94 px in text row 0 as a finding.
    It is the moved driver lines. `B` shows `Registering: EISA0` there,
    where both controls show `Registering: VBEDisplay0` (viewed). The rest
    of `B`'s differences lie where `A1` and `A2` differ from each other,
    the phantom race.
    **[CORRECTED — final review m1: only `A1` shows `Registering:
    VBEDisplay0` in text row 0; `A2`'s rows 0-3 are phantom-IRQ lines
    (viewed again, 30 s). The 94 px lie in row 0 (rows 42..49, cols
    120..204), at pixels where `A1`'s line and `A2`'s phantom line happen
    to agree and `B`'s `Registering: EISA0` does not [measured, `cmp.py
    aba`, re-run].]**
  - The mid-boot frames at 22 and 25 s show the same thing, in text rows
    0 to 2 at 25 s (viewed). The two controls there already differ from
    each other by 18,297 and 3,101 px.
    **[CORRECTED — final review m2: at 22 s it is not the same thing. The
    819 px outside the controls' difference span rows 42..461: the three
    runs are at different points of the boot there, a boot-phase
    difference. Only 25 s shows the moved driver lines (468 px, rows
    42..73) [measured, `cmp.py aba`, re-run].]**

**So the order alone does not cascade** [measured]. With the stock booter
and `sarld`, the driver linked first costs no boot driver and no device.
- The negative-control kernel with no driver loses nothing (`C1`, `C2`).
- The driver first on a kernel with the symbol loses nothing (`B`).
- Only the two together, where the driver's link fails, cascade (`N`).

So G5's attribution, the failed link, is now measured rather than
inferred. One qualification: `N` and `B` differ in the kernel, and the
negative-control kernel differs from the final kernel by more than the
symbol. It is 4,168 bytes smaller, for reasons spec 2's provenance gap left
unrecorded. How the failed link leads to EIDE's malloc failure is still
**not determined**. *[inference, from the code]* The undefined-symbol
`error()` sets `errors` and returns (`ld.c:2046-2064`).
`internal_rld_load` then unloads the one set through
`internal_rld_unload` and returns 0 (`rld.c:402-405`), with no longjmp. So
"unloads only the one driver" was right as a reading. The step from there
to EIDE's malloc failure was not traced.

### Captures and hashes

The captures are gitignored and live in the worktree's `vm/shots-t9-*/`.
**They cannot be regenerated.** Boot timing under TCG drifts from session to
session; this session ran slower than spec 3's earlier ones, and several
15 s frames caught the booter. The hashes below are the only durable trace
of what was measured.

| Run | Kernel | Booter | Driver | Keys | `test.img` | `serial.log` lines, SHA-256 | 5 s frame | Last frame | Dump |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| G1 `A1` | final | Task 5 | no | `-v` | `6C28DE8B9EE73DBEA03C72D565726D55CF5EA92057C385A9472DD0E054336150` | 76, `D0962D4A7DDB11FD3553958C6A4FCD177E559BAC64DF23B615489ACD06F55E62` | `276180227B367AC76892E4879BF72C521E3677502B0B40A54469FB248862D91C` | `125C4133B06BB46E8E3D06262EF225C9F44FB3ECCE0BC933CF639FFBC4474F76` | `F9D7CC4D44A365EBE97AAE2A70071A4F3493C9670BCDC0B9E42FA01A33C29000` |
| G1 `B` | final | final | no | `-v` | `E7AB2CE2EF710DF190A85DB95E8059EC6648B9A23BC03239AD4598E3047CF46A` | 76, same as `A1` | same | same as `A1` | `8F112EE8F4DB49617E6DD97AF6D6C8C252886D57EEF05071226E68DB860EC070` |
| G1 `A2` | final | Task 5 | no | `-v` | same as `A1` | 76, `DC99B29330702DB57A70F2F5110AF78D705EC16FE36A5E74C28FFFC3794D20D6` | same | `6EFDC4D328C8A1CF53390B559185BCAF0ED76FCDC247060EF14B908C30CC1240` | same as `A1` |
| G1 `Bdef` | final | final | no | none | same as `B` | 76, `96EE10C4BAFE85BD66A3936069DAA643790189D2DE7F79D49495C28A79FDBAFD` | same | `C0F78DDBF960E899952BBD309674B31E0C01E519A25D1B83D791092CF7C247ED` | `2091AB2920FBB508ABF58A133A6D6182E72F5399183BD5FF2AC85EA373A31C72` |
| G2 `g2-v` | final | final | last | `-v` | `FD7B2E0EAEB3FAC1938171772527DB0A95C2EC648B9012799FEBBD515CBE14C0` | 88, `79AE61B62EC0139EA2C349BE9D6DF006C7E3057D84605F8F5D04D47996F8BE25` | same | `3CA1D670E7BE699CCE459AD980D2CDAEC105E7758BBA072B18EDD34465C630E5` | `037855BF30B96E8D9C9ADEB2E0D2A17F153A5D99F139221ECE1979C5A85515AD` |
| G2 `g2-d` | final | final | last | none | `194628FEE03FF07A8320DB7288911847AE577B73883BA24477EE35EBD3F190E8` | 88, `C419BE0170B0E6A190E241791F071F42DDD3F48DA16B0587630EE2BC73FF5329` | same | same as `g2-v` | `22D0777219BA57D399852EBA281B21E713DB89E98EE7CA4405F74CAE2748BC8A` |
| G3 `g3-999` | final | final | last, 999 | none | `5907B7D45611485999C7AFB0B0FABFDE2EE4188EE153D90BDB02194DE0291B77` | 88, `6E6553BE99B09006EA016758B6CC952BA11D39820E102181B8EABDF532C97F0D` | same | same as `g2-v` | same as `g2-d` |
| G3 `isavga` | final | final | last | none | `19E9ABEC09AAEE9195EFBD1F96A8B785A35744A78FEEFDA0F6D305892D0AFD60` | 102, `877CC9CDC58F9E44E930F66625B1A2D3C3D0D07EE47EE24558D4979EDCE02BB6` | `5AF1FBA8AE70E687AF1B705A89057FA7D354CEFC01A9F1C0991731DC9B3E85C7` | `9FDDA6EA3BA425C28BE2FD9DC5BFCBC9A201BD47FD6279B26CC66F57B49E58C4` | `9EFB96D12A0D99DA2CDF777ECC9FA25EC783AE564B5295B2D3B88140B64E044E` |
| G3 `isacirrus` | final | final | last | none | `28D9D89ED996994683B41486BC16CE33F5FF17DDFC9B5EA9895A189E2A209B6D` | 79, `C36C31C7597D93F3F873DDD437E58CBA920AAE690AC469AEB305E8349E9DD8C4` | `7643F82F88C5E55D7D3BFF2148401C0B0CB1F90D97492AECA6776F33F6D339CB` | `980D163B2258F4F7D58B051EF5B800EB71A56B66895FFFFDDB5C352CD7E80428` | `0563C39CFD56DF2D14D75C20CBE3C958396C9CA829280DC555D4B03A40B446F6` |
| G4 `A1` | spec 2 | stock | last | `-v` | `B5F33C3F3F21ECEBDFF582EB2D69BE9F4C62BCF72716D172D46DFCD5BFBDC2F5` | 81, `8752382617A4C25020B2640C42EBA43114DB60CE1C22DBBC31B07E4F621E035F` | `A5149E2CC68FF382EB431953610182ED23190BEC7CAC38E2557C665AE95B5E70` | `3577E55423C69B8EE167DE65F058EAE2A652BB586DD7472B367FD4EB9DE056B8` | `E38F01A818D60C390AC4231AC823332E7C96FD3C7D302F80C5087CFC455D3AA3` |
| G4 `B` (void) | final | stock | last | `-v` | `A0191872822AE2C864BDF311BF49FF2770248B9F81BD39C3DD4AB59D85FB568D` | 81, `4C584F8594A2DC8431F45721373E48016AA2858F9AD33727B4A92D73E0B73644` | `12B45462D217AFD6E90E9B97783B5D9FBAF1893D5D5F14BA2CB438E3D46E7718` (no banner) | `A940B0680871C7456CF23644C53D68BE4F3569DD232EA22F72A290AF3248367A` | same as `A1` |
| G4 `B2` | final | stock | last | `-v` | `E87E4AF21B9942D998A9FCBBC54F04321BBE18A5D004BF40AE7E3FA1500EA0DF` | 81, `F4228F3DC4A0ED957E6CADAE2E09D57D1F204595CBB38EF2C12323269A12E387` | `A5149E2C...` | `6EFDC4D3...` (G1 `A2`'s) | same as `A1` |
| G4 `A2` | spec 2 | stock | last | `-v` | `9E359B71B4CFF62DE72E8DA9134C2B1C20E95B4CF0821A5FA2EB8EEEC044635C` | 81, `10D60C78D670F30A458CC8876AC28B125C9227544DA3BB732035EB2E5499DB7E` | `A5149E2C...` | `125C4133...` (G1 `A1`'s) | same as `A1` |
| G5 `C1` | negative control | stock | no | `-v` | `994A66C6E87D4F24A6BCA3AFDDA5BB908E38AC95C9F8B3356A48194610F7A3F9` | 76, `BB9B88CDC7D0E34FBE512AE1D798FD2EE9AA95E4715719D30DF45F85ED3F57CA` | `A5149E2C...` | `125C4133...` | `5F62165DC0E7585FB14418C2AB27D0C1EB90385B9875A494E447AB7EDA062C5C` |
| G5 `N` | negative control | stock | first | `-v` | `BD9BB9626412B07E261D5EF1B9ABA799407538C416C26DC4333BC605EBE829C6` | 13, `5E2DFEFCBEDEBE08A449FD12A08B0964A5F79468C49210BAE51C0608DA8F3108` | `A5149E2C...` | `9A232CF2E374914794D9F0A4284724A3A73EE8416A8D4D02EA442ABC2D4812FB` | `CB8FC8ABE4FA60C629E8546BC98A014DBD8F581942F16951AE6F81228F09FEFB` |
| G5 `C2` | negative control | stock | no | `-v` | same as `C1` | 76, `BED3D3B5EB53314CCAA9BD4CE8D23E8A96B3512E34E574D289C659889063D973` | `A5149E2C...` | `2627808805CD85BE8016F40EFAB5EB8384E0076C684E35C73EE9B12597C5E47E` | same as `C1` |
| G5 control `A1` | final | stock | last | `-v` | `E0D8A6E0D7F3E961E7265034751D5F9B79E8E56BA6B6C22DB5D10583B15B0999` | 81, `E7F83FB0F85EF8E38132851569E3CD9EB13E05377645D68CF27D727B6B7B0292` | `A5149E2C...` | `DF0E11C99322B9DD8B6DCD195CE0CD36E23EB58D06988ED393A0E1E0074DCEE8` | `E38F01A8...` (G4's) |
| G5 control `B` | final | stock | first | `-v` | `C93F8911B5978C1D74B12231B89A05EC0BBD43C8190C207D41EA84524FE80FB0` | 81, `3FFE6ADC7AFB9D33B73D7E69CF45BCB5579156B7876929F8BB00C75FC0E113D5` | `A5149E2C...` | `7A54A50FBF6649DEB76B169274514FC34C48BF49FF5737C7914C260DB70D5DBA` | `BB04640DB8E6E42F71D9E750442CC4AB438605D5F9A9461DA62B95C6DF594E67` |
| G5 control `A2` | final | stock | last | `-v` | `0B21939EAEE1D42CA4A6B6B20DBBDDB6BD46BDF81889761D680B6003B349C135` | 81, `7A111C7A7EA0B4576947985B3A1A13642BEDF27AC38A2C417C890A6C2CC52366` | `A5149E2C...` | `6EFDC4D3...` (G4 `B2`'s) | `E38F01A8...` (G4's) |

- "Last frame" is the 120 s capture, or the 95 s or 90 s one where that was
  the last. In every run it equals the 60 s frame.
- Images with the driver differ in hash even when built the same way,
  because the install stamps new inodes with the wall clock.
- Dumps are 8,704 bytes of guest physical `0x11000..0x131FF`, taken at 60 s.

Other frames cited above:
- G1 `Bdef` 13 s, 4.2's panel:
  `1CCB2F43C1F2D17FD0E2A773AFC8A0A93250D8B03F3CB805C10059621F07FDEA`.
- G3 `g3-999` 19 s, the fallback messages:
  `9B5D0FF4C65BFFB1B9BF4A7F804526E0747F71C744D58C2560F8D21B3B01EC1C`.
- G3 `isacirrus` 17 s, `VESA not available.`:
  `D54933C8950A4E132C05CF9944CBCAB4F0DBAE4F45438F3853A3DBD4017EA0CB`.
- G5 `N` 9.5 s, the link errors:
  `178B8C6D2081C952D95D4572A42AA1674A0529D22A928D6C04F55512615FBBCC`.
- G5 `N` 9.8 s, the paused screen:
  `C064D2337DE1F692B972AEC894F2B24AF4A7E0F4456157B8EC056E7EB301703E`.
- G5 control `B` 9.9 s, the driver first and no error:
  `4E71C13351BB008D911B8EB5D5A16BF26D6D7C7E766941366ADF388C2B5A8B51`.
- G5 control `A1` 10.0 s and `A2` 9.7 s, the driver last and no error:
  `B8A24A22367A37D7C0ED94F1F20CED74F05686DAD4F1101720F08E61098E65BC`,
  `35446A20C1EA34ED5324B044354EBA35142A64E7D8132D9034AA9483AE817C89`.

### What this does and does not establish

It establishes, on QEMU:
- **Without a VBE mode, our booter changes nothing the kernel sees except
  the filled mode array.** The array is 4.2's behaviour, and the driver
  reads it only when a mode is set.
  **[CORRECTED — final review I4: the driver reads the array with no mode
  set too.** `VBE20DisplayDriver.m:209` calls `parseVESAModes:` after both
  arms. Task 7c's RED capture shows it: `vm/shots-t7c-red-first-b/
  serial.log:28-37` has `Skipping framebuffer initialization` and then all
  eight `VBE mode N is ...` lines. So with our booter, a system with the
  driver installed but no mode set exports the enumerated list; see the
  note after the negative-control signature below.**]**
- **With a mode set, the whole path runs:**
  - the booter records the mode;
  - `pmap_bootstrap` maps the frame buffer and publishes the address;
  - `FBAllocateVBEConsole` passes its guard and calls
    `VBEModeInfo2IODisplayInfo`;
  - the kernel's console draws through the frame buffer;
  - the driver takes its `using VBE mode` path and exports a non-empty
    mode list.

  This held on cirrus, and on `isa-vga` at a different frame-buffer
  address.
- **Both fallbacks behave as 4.2's code says:** a mode the BIOS does not
  list, and an adapter with no usable mode.
- **With the stock booter, the final kernel behaves as spec 2's.**
- **With the stock `sarld` and a kernel lacking the symbol, the driver
  linked first cascades and panics.** With the stock booter and a kernel
  that has the symbol, the driver linked first costs nothing: the failed
  link, not the order, sets the cascade off.
  **[QUALIFIED — final review m3: the two runs differ in the kernel as
  well as in the symbol. The negative-control kernel is 4,168 bytes smaller
  than the final one, for reasons spec 2's provenance gap left
  unrecorded.]**

It does **not** establish:
- **Anything on hardware.** These are QEMU `pc` boots. The VBE path ran on
  the cirrus and `isa-vga` adapters, the fallback on `isa-cirrus-vga`, and
  QEMU's `std` VGA was not booted here.
- **Any mode but 257.** It is an 8 bpp packed-pixel mode. Direct-colour
  modes, other sizes, and the other arms of `VBEModeInfo2IODisplayInfo`
  were not exercised.
- **The alert-console consequence** (spec 3 §8). `kmDevice.m:85` (the
  `AllocConsole()` macro) and `:962` (`kmAlertConsole`) call
  `BasicAllocateConsole()`, so on a VBE boot their windows go through the
  frame-buffer console too.
  - A frame-buffer alert window opens only while `fbMode` is neither text
    nor alert, that is, once the Window Server owns the screen. A VBE boot
    stays in text mode until then.
  - So no frame-buffer alert, and no VBE-boot panic, was observed. Spec 3's
    Task 8c fix (the window type stored before the wipe test) is verified
    by code reading and disassembly only. G5's panic was on the VGA console.
- **The negative-control signature, with our booter.** Spec 3's Task 7c
  rebuilt 4.2's `loadOtherConfigs`. With our booter, a boot driver whose
  link fails no longer reaches `kernBootStruct->config` or the loaded-driver
  list.
  - So spec 2's kernel line `configureDriver: driver class ... was not
    loaded` would not appear on a failed-link boot with our booter
    *[inference, from the code; not booted]*.
  - The same holds for such a driver's `VBE Mode`.
  - G5 used the stock booter, so it is unaffected.
  - **[ADDED — final review I4: a second change with our booter.** With the
    driver installed but no mode set (no `VBE Mode` key, or a lookup miss),
    the driver takes its "Skipping" path and still exports the booter's
    enumerated modes (Task 7c's RED capture: eight). Spec 2's `No VBE modes
    found.` then no longer appears. It still does when no mode is usable,
    as in G3's `isa-cirrus-vga` run.**]**
- **The untried paths:**
  - `loadBootDrivers`, the driver-floppy path, and its forced divergence;
  - the `Query` prompt;
  - `VBE Check`'s adapter warning, `The VBE video driver can not be used
    with this display adapter.`;
  - the driver's `getCharValues:`.
- **The Window Server** on the VBE display.
- **The cascade at any position but the first.** Also untried: the rebuilt
  8,000-node `sarld`.
- **How the failed link leads to the next link's malloc failure.**
- **[ADDED — final review I3.] A non-zero `VideoModePtr` segment.** Both
  QEMU adapters report `0000:FD1A`, where 4.2's `(segment << 16) | offset`
  and the real-mode address agree. With a BIOS that keeps its list in ROM
  (`C000:xxxx`), 4.2's form reads physical `0xC000xxxx` on the booter's flat
  data segment: zero modes, or one `int 10h/4F01` per word until a
  `0xFFFF`, and since the enumerator runs on every boot, on every boot
  *[inference, from the code]*. At the user's request the final booter
  forms `segment * 16 + offset`, a forced divergence from that reference
  defect. The fix is verified by disassembly only
  (`src/boot-2/reconstruction/vbe/divergences.md`, "Final review fixes");
  the gates ran before it.
- **[ADDED — final review I2.] The frame buffer near 1 GB of kernel VA.**
  These boots have 128 MB of RAM, far below the wall. The final kernel's
  bound, which maps nothing and leaves `0x12854` zero when the mapping would
  end past `VM_MAX_KERNEL_ADDRESS`, is verified by code reading and
  disassembly only (`src/kernel-7/reconstruction/vbe/divergences.md`,
  "Final review fix: the 1 GB bound"). Its effect, a VGA console behind a
  VBE screen, was not seen.

### After the gates: the final booter and kernel

**The gates G1 to G5 above ran with `t7c-boot` and `t8c-mach_kernel`. The
final artifacts are the `tfin` builds below.** The final whole-branch review
led to two source changes, both by the user's decision, and to comment
corrections that ride along with them:
- **the booter** reads the BIOS mode list at `segment * 16 + offset`,
  where 4.2 uses `(segment << 16) | offset` (review I3; `584f61abb`;
  `src/boot-2/reconstruction/vbe/divergences.md`, "Final review fixes");
- **the kernel** maps nothing, and leaves `0x12854` zero, when the frame
  buffer would end past `VM_MAX_KERNEL_ADDRESS` (review I2; `ac27eb145`;
  `src/kernel-7/reconstruction/vbe/divergences.md`, "Final review fix: the
  1 GB bound").

| Role | File | Bytes | SHA-256 |
| --- | --- | --- | --- |
| Final booter (the sources of `584f61abb`) | `vm/work/tfin-boot` | 45,008 | `8B06C0A3B1F3B2FB07353F83FA87025370FAAB05AEFD0035FB76CD2C1BB8F675` |
| its `boot.sys` | `vm/work/tfin-boot.sys` | 1,078,648 | `2AFA0646205B54EE5BE16CDC0C697832AB426698EC752BE6FAA9E0A874C04C48` |
| Final kernel (the sources of `ac27eb145`) | `vm/work/tfin-mach_kernel` | 1,490,352 | `17D496898DF6891EC194EB57CEAC1D0EEB8BB9C915F635B05C9CBBE9C36C864B` |

Against the gated builds [measured]:
- **The booter** differs from `t7c-boot` in 192 bytes, all inside the mode
  enumerator. Its size, `booter 45008 bytes of 45056, 48 to spare`, and
  every symbol address are `t7c`'s.
- **The kernel** differs from `t8c-mach_kernel` in `_pmap_bootstrap`, which
  gains the bound's four instructions (1,076 to 1,092 bytes), and in the
  addresses of the code before it, which moves down 16 bytes. Spec 2's
  oracles still match (`VBEModeInfo2IODisplayInfo` 411 of 411 bytes with
  its 31 table entries; `_BasicAllocateConsole` 60 of 60), and so does
  `FBPutC` against 4.2.

**The re-check boots** [measured], on 2026-09-23 between 16:03 and 16:15
EDT, one QEMU at a time, each on an image rebuilt from `golden.img` as in
"Procedure" (the intermediate copy staged on another disk) and read back
before its boot: `/mach_kernel` = the final kernel, the driver bundle equal
to spec 2's (`_reloc` = `77399531...`), `sarld` `BBFB53F2...`, and both boot
slots holding the final booter followed by zeros, or the stock booter
(`AA06C3C5...`). All three were verbose (`mach_kernel -v` typed at 8 s) on
`--vga cirrus`, with the dump at 60 s. The controls are Task 9's captures of
the same runs, from the earlier session.

| Run | Booter | Driver | `test.img` | `serial.log` lines, SHA-256 | 5 s frame | Last frame | Dump |
| --- | --- | --- | --- | --- | --- | --- | --- |
| G2 `tfin-g2-v` | final | last, `VBE Mode` 257 | `C07F17293F2DAC922A19543988A8F8E74D92CA036D293D75B7130E9EF3557D6A` | 88, `1201D0F7921210B1AA6922A27AFFF4C3307F5955D210C727174CFC39A845588A` | `276180227B36...` | `3CA1D670...` (G2's) | `037855BF...` (G2 `g2-v`'s) |
| G4 `tfin-g4` | stock | last, `VBE Mode` 257 | `6FB8CA26358FF3A8004C2438B5D7F72CCB29EB95856462541D345CE4D795B6DA` | 81, `1358874D959369936F690891A827E8050B33DDBF5812F9DD2CE987F9DBE198BC` | `A5149E2C...` | `C636B60A5A665AEDAAEEC2B30E1B8258F45500C44DFC027BD78E496A3763F3F6` | `E38F01A8...` (G4's) |
| G1 `tfin-g1` | final | no | `427F8FB51D8F4D82E240A94BE552DF0E55921649BCA00961AF78A93E6FD7ECC6` | 76, `F0C58220655304052E6DC08294ED316AF602460EB7F7351C20272817871DBADC` | `276180227B36...` | `C636B60A...` | `8F112EE8...` (G1 `B`'s) |

- **G2, the VBE path.** The dump is byte-identical to G2's `g2-v`:
  `0x12854` = `0x0D3D4000`, the current mode 257 (640x480, 8 bpp), 8 records
  from `0x1870`, record 8 zero, `boot_video` zero, `graphicsMode` 0. The
  serial has `Display0: using VBE mode 257` and the eight mode lines, and
  equals `g2-v`'s but for line 4's date and one phantom line moving (rule
  3). The 30, 60 and 120 s frames are G2's `3CA1D670...`, the kernel's
  console readable in its window on the frame buffer (viewed at 60 s). The
  earlier frames are mid-boot at different points in the two sessions.
  QEMU reports segment 0 (`0000:FD1A`), so the `VideoModePtr` fix changes
  nothing here, as the identical dump shows.
- **G4 in miniature, the stock booter and the final kernel.** `0x12854` is
  zero: the dump is G4's `E38F01A8...` (`kbs+0x1854..0x20D7` zero). The
  driver takes its "Skipping" path and prints `No VBE modes found.`. Against
  spec 2's kernel (G4 `A1`, `A2`) the serial differs only in line 4's date
  and in phantom lines and `Power management is enabled.` changing place
  (rule 3). Rule 4 against G4 `A1` and `A2`: 5 s identical; 30, 60 and
  120 s equal `A2` outside the clock mask; 15 s is mid-boot in every run
  and not comparable, as in G4.
- **G1's verbose check, the final booter and kernel with no mode.** The
  serial equals G1 `B`'s line for line but for line 4's date. The dump is
  byte-identical to G1 `B`'s: the 8 records, `kbs+0x1854..0x186F` and
  `boot_video` zero, `graphicsMode` 0. Every frame equals G1 `B`'s outside
  the clock mask; rule 4 against G1 `A1` and `A2` passes at every capture.

**So the final booter and kernel pass the three checks the fixes could
touch.** The fixes' own paths, a non-zero `VideoModePtr` segment and a
frame buffer near 1 GB of kernel VA, are not reached by any of these boots;
see "What this does and does not establish". G3 and G5 were not re-run.
G5 used the stock booter and the negative-control kernel, which neither fix
touches, and G3's case 1 ran on cirrus, whose segment is 0. **G3's case 2
could differ:** the cause of `isa-cirrus-vga`'s `VESA not available.` was
not determined, and the old `VideoModePtr` form is one candidate (G3,
above).

The captures are in `vm/shots-tfin-*/`, gitignored, and like the others
cannot be regenerated.
