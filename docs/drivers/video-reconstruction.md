# i386 video drivers: reconstruction status

Status of the effort to rebuild our `src/drivers-i386/video` sources against
Apple's shipped `*_reloc` binaries with `tools/binrecon`. The headline is that
the eleven drivers fall into four groups that have nothing to do with each
other: one driver is reconstructed and verified against its reference, one is
reconstructed in part, one has been fully analysed but not yet rewritten, and
the remaining eight have had no reconstruction pass at all — four of them
because no reference binary exists to reconstruct against.

Unlike the SCSI effort, where most drivers were stubs that shared a class-naming
defect, the video drivers that have been worked share a different problem: our
sources were **inventions**, not partial reconstructions. Cirrus, ThinkPad and
VGA each began with a class that shared no symbol, no string and no class name
with the binary it was supposed to reproduce, so there was nothing to diff and
every function had to be written from the disassembly.

## Coverage

"Partition entries" is how many pieces the committed `source-map.json` divides
the reference's `__TEXT,__text` into, and "Mapped" is how many of those resolve
to a definition in our source. Entries are not quite the same as functions: the
partition also covers fragments the analyzer carves out that the symbol table
does not name, so for `drvVGA` the two counts differ (see below). The two
build-generated symbols every driver has
(`+[<Name>KernelServerInstance kernelServerInstance]` and
`+[<Name>Version driverKitVersionFor<Name>]`) are emitted by the Kernel Server
project type and are correctly absent from source.

| Driver | Reference binary | Partition entries | Mapped | Status |
| --- | --- | --- | --- | --- |
| drvCirrusLogicGD5434 | `CirrusLogicGD5434DisplayDriver_reloc` | 21 | 19 | **built, linked, parity clean**; 17/21 byte-identical |
| drvIBMThinkPad760EDDisplay | `IBMThinkPad760EDDisplayDriver_reloc` | 40 | 28 | compiles and links; 17/29 in-scope extents match |
| drvVGA | `VGA_reloc` + `VGA_psdrvr` | 38 + 53 | 0 + 0 | analysed in full, **not yet rewritten** |
| drvATIMach64 | `ATIMach64DisplayDriver_reloc` | — | — | no reconstruction pass |
| drvATIRage | `ATIRageDisplayDriver_reloc` | — | — | no reconstruction pass |
| drvS3Generic | `S3GenericDisplayDriver_reloc` | — | — | no reconstruction pass; README marks complete |
| drvMatroxMGA | `MatroxMGA2064WDisplayDriver_reloc` | — | — | excluded by instruction; name divergence below |
| drv3DfxVoodooVSA | none | — | — | modern addition, no reference |
| drvNVidiaRiva | none | — | — | modern addition, no reference |
| drvVBoxVideo | none | — | — | modern addition, no reference |
| drvVMWareVideo | none | — | — | modern addition, no reference |

Four reference bundles in Apple's i386 set have **no source directory at all**:
`DiamondStealthDisplayDriver`, the four `Number9*` drivers, the two `Weitek*`
drivers, and `QVision`. The Number9 and Weitek drivers and
`MatroxMGA2064WDisplayDriver` were excluded from the current effort by
instruction. `QVision` exists as an untracked working tree in the main checkout
but is not on this branch.

## drvCirrusLogicGD5434 — reconstructed and verified

The only video driver whose reconstruction has been closed against a build.

Apple's `__OBJC,__module_info` names the source files outright, so the file
partition is not inferred: `CirrusLogicGD5434DisplayDriver.m` (`__text` 0–3588),
`ProgramDAC.m` (3588–4364), and the build-generated
`CirrusLogicGD5434DisplayDriver_instance.m` (4364–4388). Our invented source was
604 lines implementing a class subclassing `IOPCIDirectDevice` with 30 methods —
`writeCRTC:value:`, `drawPixel:y:color:`, `fillRect:y:width:height:color:` —
not one of which appears in the reference. It was replaced outright.

What is verified:

- Builds in the Rhapsody guest with `make exit=0` and links.
- `parity_check.py` reports **zero missing strings and zero missing symbols**.
  The 26 extras are stab entries from our unstripped `-g` build.
- **17 of 21 functions are byte-identical** to the reference under relocation
  masking, re-derived independently during review rather than taken on trust.
- All 30 `__TEXT,__const` register sets and all 52 mode-table entries in
  `_GD5434_modeTable` and `_GD5446_modeTable` were re-parsed from the written C
  and byte-compared against the binary, with zero mismatches.
- Ledger: 15 `assembly-matched`, 3 `control-flow-confirmed`, 1
  `signature-confirmed`, 2 `unexamined` (the build-generated glue, byte-identical
  but deliberately not credited).

Two things remain open. `determineConfiguration` is the single function that
failed control-flow confirmation: the reference inlines its string comparison as
`repe cmpsb` where our build emits `call _strncmp`, 7 calls against 8. A
`chipType` signedness hypothesis was investigated and **refuted** — the
reference's `__OBJC,__instance_vars` encodes `chipType` as `'i'`, so declaring it
unsigned would break a section that currently matches. The current diagnosis is
that `repe cmpsb` is gcc's `strcmp` builtin rather than a flag artefact: across
nine literals in six drivers the `ecx` count is always `strlen(literal) + 1`, so
`strncmp(..., "PCI", 4)` should be `strcmp(..., "PCI")`. Untested.

The second is the version bundle (below), which affects both driven drivers.

## drvIBMThinkPad760EDDisplay — reconstructed in part

Despite its name this driver does not target an IBM part. `Default.table` sets
`"Auto Detect IDs" = "0x96601023"` — Trident Microsystems TGUI9660 — and the
binary's strings say `Trident Cyber938x not detected - trying anyway` and
`TVGA BIOS SetMode failure`. Panel brightness, refresh rate and STN/TFT panel
typing all run through IBM's SMAPI BIOS. One binary serves both the ThinkPad 560
and the 760E/760ED, distinguished only by which config table the installer picks.

Of its 18204 bytes of `__text`, only 6552 were in scope. The rest is
`vidBIOS.m` (six methods, 1156 bytes) and `_emu486` (10496 bytes), a 486
real-mode emulator — both **deferred to the drvVGA effort**, which owns their
reconstruction. `VGA_reloc` carries the same six `vidBIOS` methods across an
identical 1156-byte extent, which is strong evidence of a single shared source
file compiled into each driver, and makes the two copies cross-validating for
whoever reconstructs them.

What is verified: all three in-scope objects compile, and `kl_ld` produces a
`_reloc`. **The spec's original premise that this driver could not link was
wrong** — `kl_ld` performs a relocatable link, so undefined symbols do not
abort it, and `_emu486` is simply absent rather than undefined because only the
deferred `vidBIOS.m` references it. `parity_check.py` consequently runs, and
reports `_emu486` as the sole missing symbol plus the eight deferred `vidBIOS`
strings.

What is not: **17 of the 29 in-scope function extents match the reference and 12
do not**, so no entry can be byte-confirmed. All 40 ledger entries are
`unexamined`, which is the only defensible status while that holds.

Three of the twelve now have high-confidence diagnoses with exact proposed source
and a predicted extent; five remain genuinely unexplained; one (`+8` on
`initFromDeviceDescription:`) is confirmed **explained, not a defect** — gcc
tail-merged three `IOLog` arms, so the reference has 27 `call _IOLog`
instructions for 30 logical calls, and a rewrite cannot reproduce that.

> **There are uncompiled changes on this branch.** Commit `1cb44e28` edits
> `IBMThinkPad760ED.m` intending to close four divergences and has never been
> through a compiler — the build guest went offline mid-pass. The extent table in
> the driver's `divergences.md` reflects the last *measured* build at
> `fd0e7355`, not that commit. Its "Resuming when the build guest returns"
> section is the ordered checklist.

## drvVGA — analysed, not rewritten

`drvVGA` is the furthest along in analysis and the furthest behind in code. Both
of its binaries have been decompiled and documented, and **neither has been
rewritten**: both source maps report zero mapped functions.

| Binary | Mach-O type | File size | `__text` | Functions | Partition entries |
| --- | --- | --- | --- | --- | --- |
| `VGA_reloc` | MH_PRELOAD | 71112 | 18048 | 36 | 38 |
| `VGA_psdrvr` | MH_BUNDLE | 26584 | 7057 | 22 | 53 |

The two columns differ because the partition also carries fragments IDA carves
out that the symbol table does not name. In `VGA_reloc` those are the two
unnamed routines past the end of `_emu486`; in `VGA_psdrvr` the gap is much
wider, because most of that bundle is `_emu486`-style code with few symbols.
`VGA_reloc`'s 36 functions are the symbol table's 30 plus six `-[vidBIOS …]`
methods that carry no symbol-table entry and are recovered from
`__OBJC,__inst_meth`.

Our `VGA.lksproj` implements a class `VGA` subclassing `IOFrameBufferDisplay`;
Apple's `VGA_reloc` implements `IOVGADisplay`, `IOVGADisplay(VESAMode)` and
`vidBIOS`. Our `VGA_psdrvr.tproj` is a 127-line invented printing API; Apple's
`VGA_psdrvr` is the Window Server's framebuffer and cursor driver. They share no
symbol, so every reference function sits in `unmapped`.

The ledger records 36 `unexamined` and 2 `intentional-mismatch`. `_emu486`
(8088 bytes here) and the `vidBIOS` class are this effort's to reconstruct, and
`drvIBMThinkPad760EDDisplay` is blocked on them.

Unlike the two display drivers, `VGA_psdrvr` is a **real** Window Server driver
with 53 functions. The equivalent bundles in the Cirrus and ThinkPad configs are
34-byte version stubs containing only dyld glue and `_VERS_STRING`/`_VERS_NUM`,
with no code to reconstruct.

## The version bundle is missing from both built drivers

Neither driver's build emits the `.config` bundle executable that sits beside the
`_reloc` and carries `_VERS_STRING`/`_VERS_NUM`. Apple's bundles have one;
`vm/build-i386-video-recon.sh` prints `WARNING: no <name> version bundle
produced`. Measured on Cirrus: reference `__TEXT,__const` is 2562 bytes with both
symbols, ours is 2392 with neither, a delta of 170.

`parity_check.py` cannot see this — it covers only `__TEXT,__cstring` strings and
`__TEXT,__text` symbols, so `__const` is outside its scope and its green result
is narrower than it looks. The spec's §1.2 named bundle existence as its only
verification criterion for these stubs, so that criterion is currently **unmet**.

The cause is unproven. The strongest in-repo account is that
`src/pb_makefiles-1/next-sgs.make:36-45` generates `$(NAME)_vers.c`, but nothing
links `$(VERS_OFILE)` unless `OTHER_GENERATED_OFILES` picks it up — which for a
Kernel Server comes from
`src/driverTools-1/KernelServerProjectType/kernelserver.make.preamble:8-10`
through an optional `-include` that is silently skipped when that file is not
installed on the guest. An earlier hypothesis blaming `drvS3Generic`'s outer
`Makefile.postamble` was refuted: its include is an absolute path to
`/NextDeveloper/Makefiles/`, absent from this tree, at the aggregate level, which
builds no code.

## Analyzer coverage is narrower than intended

Both driven drivers ran with **IDA alone**, and in both cases the disablements
are recorded with their verbatim errors rather than asserted:

- **angr** fails on both binaries inside `__TEXT,__const`, not in code. Its
  CFGFast disassembles the `_gamma8` lookup table as instructions, aborting with
  `block at address N is outside function at address M`. The failing offset is
  +172 into the table in both drivers, whose `_gamma8` is byte-identical.
- **Ghidra** produces a document, but `normalize.py` rejects it: an instruction
  whose two operands both own a relocation gives `Ghidra relocation operand
  metadata is ambiguous`.
- **Ghidra additionally cannot run from this checkout at all.** It refuses any
  project path containing a dot-prefixed directory, and the worktree lives under
  `.claude/worktrees/`, so it aborts with `Path element starting with '.' is not
  permitted` before reaching any analysis. To observe its real behaviour, run it
  once with a dot-free scratch `output_dir`.

Accepting a single-analyzer result rests on the Mach-O symbol table, which is
linker-emitted ground truth rather than a fourth opinion: for Cirrus all 21
functions appear in it with addresses and extents identical to IDA's, and for the
ThinkPad all 31 below 6552 do. Both documents were corrected during review to
state that an unretained Ghidra agreement **carries no weight**.

## Tooling notes

- `binrecon source-map --source-dir` must name the `.lksproj` directory.
  `source_map.py:84` globs `*.m` and `*.c` **non-recursively**, so pointing it at
  a driver's top directory silently scans nothing and reports every function
  unmapped. This produced a false "all unmapped" baseline before it was caught.
- The scanner cannot see assembly definitions at all, so
  `drvIBMThinkPad760EDDisplay`'s `_smapi_asm` stays `unmapped` permanently. That
  is a scanner limitation, not a defect, and renaming the symbol to satisfy the
  tool would be wrong.
- `SFILES` is **not** a pb_makefiles variable. Assembly must go in `OTHERLINKED`
  plus `OTHERLINKEDOFILES`, as `src/drivers-ppc/bus/drvPExpert/powermac/Makefile`
  does. An `SFILES` line is a silent no-op: the `.o` is never built and the symbol
  becomes an extra undefined at link.
- `binrecon ledger` used to discard `--reason` for every status except
  `intentional-mismatch`, while `cli.py` required and forwarded it and the command
  exited 0. Fixed; both video ledgers have been backfilled from their divergence
  documents.
- A profile that declares a `rebuilt` artifact makes `binrecon validate` fail
  unless `BINRECON_REBUILT` is exported too — it resolves the artifact eagerly and
  prints nothing at all, including the reference identity, when the variable is
  unset.

## Build host

All guest builds run on the Rhapsody host named in `vm/vm.conf` (`10.10.0.113`)
over PuTTY, per `docs/drivers/drvVGA-baseline-build.md`. That host went offline
partway through the extent-closing pass and every remaining item — verifying
`1cb44e28`, applying the queued diagnoses, and settling the version bundle — is
blocked behind its return.
