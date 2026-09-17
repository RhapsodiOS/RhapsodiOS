# i386 sound drivers: reconstruction status

Status of the effort to rebuild our `src/drivers-i386/sound` sources against
Apple's shipped `*_reloc` binaries with `tools/binrecon`. The shape here is
different from the SCSI and video efforts: **every reference driver already had a
source counterpart**, and every reference method name but one had a name-level
match. Nothing was missing wholesale, and none of these are inventions. Two of
the four targets have been carried through report and fix passes and now map
almost completely; the other two have had only the cross-cutting scaffolding
passes and no function-level work.

## Coverage

"Mapped" is reference `__TEXT,__text` functions resolving to a definition in our
source, from the committed `source-map.json`. Every driver carries two
build-generated symbols (`+[<Name>KernelServerInstance kernelServerInstance]`
and `+[<Name>Version driverKitVersionFor<Name>]`) emitted by the Kernel Server
project type; they are correctly absent from source and account for the
`unmapped` count in both finished drivers.

| Driver | Reference binary | Size | `__text` | Fns | Mapped | Status |
| --- | --- | --- | --- | --- | --- | --- |
| drvSB8Sound | `SoundBlaster8_reloc` | 53552 | 8896 | 29 | 27 | report + fix passes done; **builds** |
| drvBeepSound | `Beep_reloc` | 37984 | 2060 | 13 | 11 | report + fix passes done; not built |
| drvES1x88Sound | `ES1x88AudioDriver_reloc` | 53280 | 8660 | 25 | — | scaffolding only; no report pass |
| drvSB16Sound | `SoundBlaster16_reloc` | 58224 | 13572 | 28 | — | scaffolding only; no report pass |
| drvIntelAC97Sound | none | — | — | — | — | modern addition, no reference |
| drvSB128Sound | none | — | — | — | — | modern addition, no reference |

95 reference functions across the four targets, of which 87 are hand-written and
8 are build-generated glue. All four retain full symbol tables, so
address-to-name resolution is exact rather than gap-derived.

`MicrosoftSound.config` exists in Apple's i386 set with **no source directory at
all**. `drvIntelAC97Sound` and `drvSB128Sound` are modern additions with no
reference binary and are out of scope; the README marks `drvSB128Sound` complete.

Profiles exist for all four targets — `tools/binrecon/profiles/{beep,
soundblaster8, soundblaster16, es1x88audiodriver}.json` — so the two unstarted
drivers are set up and waiting rather than unscoped.

## What the scoping pass found

Reading the reference symbol tables, `__TEXT,__cstring` sections, `__DATA`
contents and config tables **before any analyzer run** turned up one defect per
driver, and they are not variations of a theme:

- **drvBeepSound had no `+probe:`.** A DriverKit driver cannot load without one.
  This was the most serious single finding in the effort.
- **drvSB16Sound validates the wrong IRQ set** — it admits an interrupt the
  hardware does not use and rejects one it does.
- **drvES1x88Sound carries SoundBlaster16 code**: four methods copied from a
  different card's driver.
- **drvSB8Sound was already in good shape**, which is why it was the one taken
  furthest first.

Three of the four also had gaps in their config table sets, three were missing
`PB.project` scaffolding entirely, and all four had `Loaded Server` sections that
were close to Apple's but not exact.

## Cross-cutting passes — all four drivers

Three passes were applied across the whole family before any per-driver
reconstruction, and they are the reason the two unstarted drivers are
nonetheless in better shape than they were:

- **Config tables** matched to Apple's, including drvSB16Sound's `SB16PnP.table`,
  `SB16SingleDMAChannelPnP.table` and `SingleDMAChannel.table`, and
  drvES1x88Sound's `ESPnP.table`. `"Driver Version"` is emitted by Apple's build
  and stays out of the comparison.
- **`Loaded Server` sections** matched to Apple's.
- **`PB.project` scaffolding** added where it was missing.

## drvSB8Sound — furthest along

27 of 29 reference functions map; the two that do not are the build-generated
glue. The ledger records **27 `assembly-matched`** and 2 `intentional-mismatch`.

This is the only sound driver that has been **built in the guest**. The first
attempt aborted before compiling anything: the top-level `Makefile.preamble` and
`Makefile.postamble` carried NEXTSTEP-era *driver*-project rules that break an
aggregate build. Fixing that was a prerequisite to measuring anything.

The fix pass also settled a cluster of help-bundle divergences — renaming the
bundle to `SB8.rtfd` to match `Default.table` and Apple's layout, restoring the
`InfoFiles` install and the `DriverHelp`-to-`Help` rename, and putting back a
single anchor byte in the help table of contents.

Analyzer coverage is the best in any of these efforts: **IDA, Ghidra and angr all
ran and all completed**, `run-summary.json` reports `complete: true` with a
non-null reference consensus and four files in `published/`. Ghidra did *not* hit
the relocation-operand normalization abort that disabled it on the video drivers,
so no analyzer was disabled and no profile change was needed.

One qualification on the 27 `assembly-matched` entries: the ledger's
`rebuilt_sha256` is **null**, so those claims are not tied to a named artifact.
The driver was built, but the ledger does not record *which* build the
instruction streams were read against, and `out/i386/` holds no sound binaries
today. That is the same gap the video effort hit, and closing it means
re-running the transitions against a rebuilt binary the ledger can name.

## drvBeepSound — mapped and fixed, but never built

11 of 13 reference functions map, the two unmapped being build glue. All three
analyzers ran and completed here too.

The ledger is the one place this driver reads differently from drvSB8Sound:
**7 `assembly-matched` and 6 `intentional-mismatch`** out of 13. That ratio is
worth understanding before trusting the driver — for a 2060-byte `__text`, nearly
half the entries are recorded divergences rather than matches, each with a reason
in `reconstruction/divergences.md`.

The fix pass added the missing `+probe:`, matched Apple's data and sleep path,
and corrected the beep timing arithmetic — an error caught during the report pass
itself rather than by a build.

> **No rebuilt artifact exists.** `out/i386/` contains no `drvBeepSound`
> directory, so every statement in its divergence document derives from the
> reference binary and our source text, never from a rebuilt binary. The
> `Loaded Server` section sizes our build actually produces are **unmeasured**,
> and the document records the reference sizes specifically so a future build can
> be compared against them.

## drvES1x88Sound and drvSB16Sound — not started

Neither has a `reconstruction/` directory, so no report pass has run: no source
map, no ledger, no divergence document. What is known about them is the scoping
pass's findings above and the cross-cutting table, `Loaded Server` and
`PB.project` work.

Both defects found at scoping time are still open. drvES1x88Sound's four
SoundBlaster16-derived methods are the more interesting problem, because a
name-level map will show them as present and correct — they exist, they compile,
they are simply the wrong card's code. A function-level comparison is what
catches that.

## Tooling notes

These apply to any resumption of the two unstarted drivers.

- `binrecon source-map --source-dir` must name the directory that actually holds
  the `.m` files. `source_map.py:84` globs `*.m` and `*.c` **non-recursively**, so
  pointing it at a driver's top directory silently scans nothing and reports every
  function unmapped — a false baseline that has already been produced once in the
  video effort.
- `binrecon analyze` exits 1 on a reference-only profile and that is success: the
  `normalized-functions` acceptance level compares a reference against a *rebuilt*
  artifact these profiles do not have. The gate is `"complete": true` in
  `run-summary.json` plus a written `published/consensus-reference.json`.
- `binrecon ledger` used to discard `--reason` for every status except
  `intentional-mismatch`, while `cli.py` required and forwarded it and the command
  exited 0 — so reasons were silently lost. Fixed. The sound ledgers predate the
  fix and have **not** been backfilled; the video ledgers have. The damage is
  visible in the files: drvBeepSound carries 6 reasons across 13 entries and
  drvSB8Sound 2 across 29, and in both cases those counts are exactly the
  driver's `intentional-mismatch` total — the one branch the old code did
  persist. Every other reason was supplied at transition time and dropped.
- A profile that declares a `rebuilt` artifact makes `binrecon validate` fail
  unless `BINRECON_REBUILT` is exported too. The four sound profiles are
  reference-only and do not have this problem, but adding a `rebuilt` section —
  which is what makes `binrecon compare` runnable at all — introduces it.
- Never claim a ledger status stronger than the work performed.
  `assembly-matched` means the rebuilt instruction stream was read against the
  reference; `control-flow-confirmed` means block shape and call targets were
  checked but not every instruction. drvBeepSound has no rebuilt binary, so its
  `assembly-matched` entries rest on the report pass's reading rather than on a
  measured build — read its divergence document before relying on them.

## Build host

Guest builds run on the Rhapsody host named in `vm/vm.conf` (`10.10.0.113`) over
PuTTY, per `docs/drivers/drvVGA-baseline-build.md`. That host is currently
offline, so building drvBeepSound for the first time — the most valuable single
next step for this family — is blocked behind its return.
