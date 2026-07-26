# Binary reconstruction of the PowerPC SCSITape family

Reconstruct `src/drvSCSITape` against Apple's four shipped PowerPC binaries —
the kernel driver and its three user-space helpers — using the `tools/binrecon`
toolchain. A report pass dispositions every reference function; a fix pass then
repairs the divergences and writes the five functions our tree lacks.

This is the third of three specs. The first,
[2026-07-26-binrecon-ppc-support-design.md](2026-07-26-binrecon-ppc-support-design.md),
taught binrecon to read big-endian PowerPC Mach-O and drive IDA against it. The
second,
[2026-07-26-scsiserver-ppc-reconstruction-design.md](2026-07-26-scsiserver-ppc-reconstruction-design.md),
reconstructed `SCSIServer`. Both are complete and merged, and spec 1's analyses
are on disk under `tools/binrecon/out/*-ppc/`.

## Motivation

`src/drvSCSITape` is an unverified reimplementation — `SCSITape.m` (1198 lines),
`SCSITapeKern.m` (747), `PreLoad.m` (53), `PostLoad.m` (124) and
`stblocksize.c` (200) — never compared against Apple's binaries.

Measured with `binrecon source-map`, it is in **far better shape than
`SCSIServer` was**: the driver maps 44 of its 50 named functions, where
`SCSIServer` mapped 41 of 68 and carried 51 findings. The gap here is five
absent functions and whatever the examination turns up inside the 49 that map.

That difference is worth stating plainly, because it changes what this spec is
for. `SCSIServer`'s report existed to establish how far the tree had drifted.
This one exists to close a small, well-bounded gap and to verify the large
part that already corresponds.

## 1. Scope

### 1.1 Reference artifacts

All four binaries under `C:\Users\raynorpat\Downloads\test\Drivers\ppc\SCSITape.config`:

| Artifact | Type | Size | SHA-256 |
| --- | --- | --- | --- |
| `SCSITape_reloc` | MH_PRELOAD | 47624 | `ABB8D7E5FDEB9188A4C58D10AE6A7A1313A79EFBE49513AD3804E386BB65131A` |
| `PreLoad` | MH_EXECUTE | 9060 | `177355F05BDCBD6EDE34121F93E6B6A176B105ACF8EAD1945761A9E1D3BFB60A` |
| `PostLoad` | MH_EXECUTE | 21520 | `A6025294E3E1AB96270BBE3AFAD73A3885C7C5F44644241E44DD553632699F87` |
| `stblocksize` | MH_EXECUTE | 13408 | `E36D1320E5543E9F8B46D522D19150DC6BA21B348C6ECAB8D13AE9CF83BC7648` |

Analyses of record are spec 1's acceptance-run outputs under
`tools/binrecon/out/{scsitape,scsitape-preload,scsitape-postload,stblocksize}-ppc/published/`.
They are not regenerated; if they ever are, each `input.sha256` must still match
the value above.

### 1.2 Starting state

| Artifact | Named | Mapped | Unmapped | Mapped bytes | Unmapped bytes |
| --- | --- | --- | --- | --- | --- |
| `SCSITape_reloc` | 50 | 44 | 6 | 7696 | 2140 |
| `PreLoad` | 12 | 1 | 11 | 276 | 724 |
| `PostLoad` | 16 | 1 | 15 | 592 | 868 |
| `stblocksize` | 20 | 3 | 17 | 828 | 1132 |

The helpers' unmapped counts are almost entirely linkage glue (§1.4), not
missing source. Their real content is `_main` in each, plus `_read_block_limits`
and `_usage` in `stblocksize`.

### 1.3 The five absent functions

| Function | Artifact | Bytes |
| --- | --- | --- |
| `-[SCSITape initSCSITape:target:lun:controller:majorDeviceNumber:]` | `SCSITape_reloc` | 908 |
| `-[SCSITape executeRequest:buffer:client:senseBuf:]` | `SCSITape_reloc` | 832 |
| `-[SCSITape reserveAllLuns]` | `SCSITape_reloc` | 236 |
| `-[SCSITape releaseAllLuns]` | `SCSITape_reloc` | 128 |
| `_do_ioc` | `stblocksize` | 228 |

2332 bytes in total. Unlike `SCSIServer`'s absent set — Mach IPC plumbing and a
644-byte notification handler — these are ordinary Objective-C methods on a
class our tree already has, plus one C helper. That is why this spec writes them
rather than deferring them (§4.1).

### 1.4 Out of scope

Recorded once each in `divergences.md`, never mapped, and permanently resident
in the `unmapped` bucket:

- **94 unnamed jump islands** in `SCSITape_reloc` — build-generated
  `lis`/`mr`/`mtctr`/`bctr` branch glue, excluded from the map by
  `filter_named_functions.py` because they carry no name.
- **Six crt/dyld startup routines per helper**: `start`, `__start`,
  `__call_mod_init_funcs`, `__dyld_init_check`, `dyld_stub_binding_helper`,
  `__dyld_func_lookup`.
- **Every 36-byte `__picsymbol_stub` entry** — 5 in `PreLoad`, 9 in `PostLoad`,
  10 in `stblocksize`. Confirmed arithmetically against each binary's stub
  section: 180, 324 and 360 bytes respectively, all exact multiples of 36, and
  matching the libc names one for one (`_printf`, `_ioctl`, `_open`, …).
- **`+[SCSITapeKernelServerInstance kernelServerInstance]`** (20 bytes) and
  **`+[SCSITapeVersion driverKitVersionForSCSITape]`** (16), emitted by the
  Kernel Server build exactly as `SCSIServer`'s pair were.

Unlike the jump islands, the glue is *named*, so `filter_named_functions.py`
cannot remove it and it stays in `unmapped`. It is explained there rather than
filtered out of sight — the same treatment `SCSIServer`'s build-generated
classes received.

No PowerPC build is attempted (§4.1). No other driver is touched.

## 2. Findings that shape the work

### 2.1 The jump table belongs to `executeMTOperation:`

`SCSITape_reloc` is the only binary in the family carrying
`PPC_RELOC_SECTDIFF` relocations — 14 of them at `0x2e34`–`0x2e68`, the start of
`__TEXT,__const`. These are the fixups whose 32-bit wrap broke the IDA exporter
during spec 1's acceptance run.

Resolved, they are a switch jump table, and every target lies inside
`-[SCSITape executeMTOperation:]`:

| Entry | Target | Entry | Target |
| --- | --- | --- | --- |
| 0 | `0x140c` | 7–13 | `0x14f0` |
| 1 | `0x1418` | | |
| 2 | `0x1448` | | |
| 3 | `0x1478` | | |
| 4 | `0x14a4` | | |
| 5 | `0x14d4` | | |
| 6 | `0x14dc` | | |

Seven distinct case bodies, with entries 7 through 13 collapsing onto one shared
target. The report must establish that our `executeMTOperation:` has the same
case set in the same order and the same collapse. A reordered jump table is the
same class of defect as `SCSIServer`'s mis-wired MiG dispatch table — a mapping
that exists only in Apple's binary and is invisible in our source alone.

### 2.2 What spec 2 learned that this spec should not re-learn

Three techniques, each of which cost a review cycle to discover:

- **Jump islands resolve through the Mach-O external relocation table.** The IDA
  export does not carry it; `binrecon.macho.read_macho` does. Two questions
  recorded as unanswerable in spec 2 were one relocation lookup away.
- **Message and MiG type descriptors are named symbols in `__TEXT,__const`**
  (`<arg>Check` / `<arg>Type`), decodable against
  `src/kernel-7/mach/message.h:707-726`. That is stronger evidence than
  instruction shapes, and it carries Apple's own argument names.
- **When a constant or type is unknown, search this tree before recording it as
  undeterminable.** Every such item in spec 2 was defined in
  `src/kernel-7/mach/`, `src/kernel-7/ipc/` or `src/cc-1`. Investigation had
  stopped at "not in this binary" instead of "not in this tree".

## 3. Design

### 3.1 Artifact layout

`drvVGA` established the layout for a multi-binary driver, and this follows it:
per-binary subdirectories for the machine-readable artifacts, one prose document
for the whole family.

```
src/drvSCSITape/reconstruction/
    divergences.md
    SCSITape/{source-map.json,ledger.json}
    PreLoad/{source-map.json,ledger.json}
    PostLoad/{source-map.json,ledger.json}
    stblocksize/{source-map.json,ledger.json}
```

Each `--source-dir` is the subproject directory that holds the sources —
`SCSITape.drvproj/SCSITape.lksproj`, `PreLoad.tproj`, `PostLoad.tproj`,
`stblocksize.tproj`. Neither `source-map` nor `selector_check.py` recurses.

### 3.2 Two phases

**Phase 1 — report.** All 49 functions examined at instruction level and
dispositioned, with findings in `divergences.md`. Committed in full before any
source change, so the evidence records the tree as found.

Ledger vocabulary is spec 2's: `assembly-matched` where our source accounts for
every instruction *and the data it depends on*; `control-flow-confirmed` where
differences are cosmetic; `signature-confirmed` where the body was not opened;
`intentional-mismatch` for deliberate divergence, with reason and reviewer. A
non-intentional divergence is **not** a status — the entry stays `unexamined`
with a finding, so a reader can distinguish "examined and correct" from
"examined and wrong".

**Phase 2 — fix.** Source changes only, one translation unit per commit, each
citing the ledger entries it resolves: the five absent bodies, the naming and
declaration class, and small precisely-evidenced in-body corrections. Artifacts
regenerated at the end so they describe the finished tree.

### 3.3 Tooling constraints carried forward

Established by spec 2 and true here:

- `binrecon ledger` transitions are forward-only, one step at a time, with no way
  back to `unexamined`; `unexamined → intentional-mismatch` needs an intermediate
  `signature-confirmed`. Decide an entry's final status before transitioning it.
- `--reason` is persisted only for `intentional-mismatch`, so `divergences.md` is
  the durable record of what was compared for every other status.
- Seed each ledger with `tools/binrecon/seed_ledger.py` from its source map, not
  with `analyze --ledger`, which would seed from the raw analyzer function list.

### 3.4 A gitignore rule this spec must widen

Spec 2 added `**/reconstruction/*.lock`, which matches only directly beneath
`reconstruction/`. With per-binary subdirectories the lock files land at
`reconstruction/SCSITape/ledger.json.lock` and would be tracked. `drvVGA` has
exactly that problem today, with two tracked lock files. Widen the rule to
`**/reconstruction/**/*.lock` and untrack `drvVGA`'s two.

## 4. Verification

### 4.1 What cannot be verified

There is no PowerPC compiler in this environment: `vm/` holds only
`build-i386-*.sh`, and the Rhapsody guest builds i386. **Nothing in this spec is
compile-verified, including the five newly written function bodies.**

This spec writes those bodies where spec 2 deferred its own, because they are
ordinary Objective-C methods on an existing class and one C helper rather than
Mach IPC plumbing. That lowers the risk; it does not remove it. Spec 2's reviews
found four material errors in exactly this kind of disassembly-derived
description before they were corrected, so each body must be written from the
reference disassembly directly and reviewed against it, not from a paraphrase.

`parity_check.py` and `import_check.py` both require a rebuilt binary and remain
unavailable.

### 4.2 Acceptance

Done when all of the following hold, with output shown:

1. The regenerated maps report:

   | Artifact | Mapped | Unmapped |
   | --- | --- | --- |
   | `SCSITape` | 48 | 2 |
   | `PreLoad` | 1 | 11 |
   | `PostLoad` | 1 | 15 |
   | `stblocksize` | 4 | 16 |

   with 0 `duplicate_candidates` and 0 `boundary_disputed` throughout. Every row
   reconciles against §1.2's named-function count: 50, 12, 16 and 20. The
   unmapped entries are exactly §1.4's out-of-scope classes.

2. `selector_check.py` exits 0 against `SCSITape.drvproj/SCSITape.lksproj` —
   renames and duplicates both empty. The two build-generated classes remain
   `missing`.

3. `load_source_map` accepts all four checked-in maps against their reference
   analyses and the files on disk.

4. Every ledger entry across the four ledgers is accounted for: either it reaches
   a terminal status (`assembly-matched`, `control-flow-confirmed`,
   `signature-confirmed` or `intentional-mismatch`) with a reviewer, or it remains
   `unexamined` carrying a recorded finding *and* an explicit statement in
   `divergences.md` of why the fix pass did not repair it.

   This is deliberately weaker than "none is `unexamined`". §3.2 scopes the fix
   pass to the five absent bodies, the naming and declaration class, and small
   precisely-evidenced corrections — so a large divergence found inside a mapped
   function would legitimately remain open. Spec 2 asserted the stronger form and
   could not meet it, ending with 31 open entries; stating the achievable
   condition here avoids repeating that.

5. `ppc_invariant_check.py --binary SCSITape_reloc` still reports 0 relocation
   violations, confirming the evidence base did not shift.

6. `divergences.md` records every finding, including §2.1's jump-table
   comparison, each with the reference evidence that establishes it.

7. The binrecon suite is green.

These checks prove structural correspondence to Apple's binaries. They do not
prove the driver builds or runs, and this spec does not claim otherwise.

## 5. Follow-on work

- **A PowerPC build.** The tree already carries the pieces: a PowerPC assembler
  and linker relocation support in `src/cctools-2` (`as/ppc.c`,
  `as/ppc-opcode.h`, `ld/ppc_reloc.c`) and GCC's `rs6000` configuration in
  `src/cc-1`. Standing one up would compile-verify this spec's five bodies,
  discharge everything spec 2 deferred, and make `parity_check.py` and
  `import_check.py` usable.
- **Spec 2's deferred work.** The 12 stub wrapper bodies and 6 absent bodies in
  `src/drvSCSIServer`, listed in that driver's `divergences.md` under
  "Phase 2 outcome".
