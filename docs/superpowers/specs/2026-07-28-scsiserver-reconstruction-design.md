# SCSIServer Reconstruction Design

**Date:** 2026-07-28
**Reference:** `C:/Users/raynorpat/Downloads/test/Drivers/ppc/SCSIServer.config/SCSIServer_reloc`
**Source:** `src/drvSCSIServer/SCSIServer.drvproj/SCSIServer.lksproj`

## 1. Goal

Measure Apple's shipped `SCSIServer` against our source, write the nine absent
function bodies, and wire `IOTask.m` into the build.

This is a finishing job, not a reconstruction from scratch. `drvSCSIServer` was
substantially reconstructed in an earlier session — `IOSCSISession.m` is 1,617
lines and `IOTask.m` carries five commits of prior work including review fixes —
but it has never been measured with binrecon, and `IOTask.m` was never added to
the build.

## 2. What the binary contains

`__text` is 13,744 bytes across **69 defined `__TEXT,__text` symbols**, verified
via `binrecon.macho.read_macho`. They partition as:

| Origin | Count | Disposition |
| --- | --- | --- |
| MIG server (`__XIOSCSISession_*` ×18, `_IOSCSISessionMig_server`) | 19 | Generated; verified against the `.defs`, not mapped |
| Build-generated (`SCSIServerVersion`, `SCSIServerKernelServerInstance`) | 2 | Recorded and excluded |
| Hand-written | 48 | Mapped; 39 present, 9 absent |

The 48 hand-written functions are **13 Objective-C methods and 35 C functions**.
That ratio drives the mapping decision in §4.2 and is the reverse of every prior
driver in this series.

The 18 `__XIOSCSISession_*` stubs pair with the 18 `_IOSCSISession_*` wrappers,
matching `Makefile.preamble`'s note that `IOSCSISessionMigUser.c` is deliberately
excluded "because the 18 `IOSCSISession_*` wrapper functions already provide the
client-facing symbols by hand."

### 2.1 Classes

From `__OBJC,__class` (field order `isa, super_class, name, version, info,
instance_size, ivars, methods, cache, protocols`, 40-byte stride):

```
SCSIServer                     : IODevice   instance_size = 300
IOSCSISession                  : Object     instance_size = 8
SCSIServerVersion              : IODevice   instance_size = 264
SCSIServerKernelServerInstance : Object     instance_size = 4
```

Our source implements the first two plus an `IOSCSISession (Private)` category.
The latter two are build-generated and have no source counterpart, matching the
pattern established in the four prior driver specs.

**Read ivars from `__OBJC,__instance_vars` during the work.** `IOSCSISession`'s
`instance_size = 8` implies `isa` plus one 4-byte ivar, but the name and type
must come from the binary, not from this inference.

## 3. The nine absent functions

Verified absent by direct symbol lookup against all three `.m` files. Two earlier
automated passes disagreed with each other — one used substring matching and
under-reported, the other a malformed definition regex and over-reported — so
this list was settled by per-symbol `grep -c "\bNAME\b"`.

**Objective-C (4).** These are the entire construction and teardown path for both
classes; our source has the operational methods but nothing that builds or
destroys the objects.

- `-[IOSCSISession init]`
- `-[IOSCSISession initForDevice:result:]`
- `-[IOSCSISession free]`
- `-[SCSIServer initFromDeviceDescription:]`

**C (5).**

- `_IOConvertTaskPortToVMTask`
- `_IODestroyMappedVMTask`
- `_IOTaskPortAllocate`
- `__io_task_notification`
- `_serverThreadFunc`

`_serverThreadFunc` and `__io_task_notification` are expected to be the hardest:
a thread entry point and a Mach notification handler, both likely to touch the
`_entry` table discussed in §5.

## 4. Method — how each partition is handled

### 4.1 The function at `__text` offset 0

**`+[SCSIServer deviceStyle]` sits at `__text+0` and IDA's analysis will not
report it as a function.** Its first word is `9421ffe0` (`stwu r1,-32(r1)`) — real
code. This is not a phantom, not a synthetic bundle symbol, and not evidence of
an absent body.

This is stated explicitly because the opposite conclusion was recorded across
five earlier specs in this series and had to be retracted in 22 places. The
symptom is `ppc_invariant_check` reporting `symbol +[SCSIServer deviceStyle] at
0x0 is not a function start`; that message means only that IDA's function list
lacks an entry there. `read_macho` also reports address 0 for *undefined*
symbols, which is what made the two cases look alike.

`+[SCSIServer deviceStyle]` **is** present in our source (`SCSIServer.m:37`). It
is therefore neither a gap nor a phantom — it will simply be absent from the
source map's universe, because `--scope-to-objc` builds that universe from IDA's
function list. Record it as a known exclusion with its reason; do not count it as
unmapped work.

### 4.2 Mapping

**35 of the 48 hand-written functions are C** — the 18 `_IOSCSISession_*`
wrappers, the 10 IOTask plumbing functions, and 7 others including
`_serverThreadFunc` and the four reservation routines. Only 13 are Objective-C
methods. Every prior spec in this series used `--scope-to-objc`, which restricts
the analysis to Objective-C methods and would silently drop all 35. A map that
looked complete under the usual invocation would in fact cover 13 of 48.

`--scope-to-objc` was adopted because `source-map-v1` requires every function in
the reference analysis to be named, and IDA's unnamed PowerPC jump islands
violate that. But the tree already carries a purpose-built answer:
`tools/binrecon/filter_named_functions.py` produces a copy of an analysis-v1
document with unnamed entries removed and every other field, including
`input.sha256`, left intact.

**Primary route:**

1. Run `filter_named_functions.py` over the reference analysis to drop the
   unnamed glue stubs.
2. Run `source-map` with `--objc-methods` and **without** `--scope-to-objc`.

This maps the C functions and the Objective-C methods in one pass.

**This is the first use of `filter_named_functions.py` on PowerPC** — it was
written for an i386 case (`VGA_reloc`'s `_emu486`). If it does not produce a
clean map, fall back to `--scope-to-objc` and triage the C functions through
`bucket_functions.py`: they land in bucket 6, and the operator moves each
confirmed match into bucket 5 with its file and line. Record which route was
used and why.

Scope validation must consider all four categories — `mapped`, `unmapped`,
`duplicate_candidates`, `boundary_disputed` — not `mapped ∪ unmapped` alone.

### 4.3 MIG verification

The 19 generated functions are excluded from the gap list but checked against
`IOSCSISessionMig.defs`, which is currently verified by nothing. For each
`__XIOSCSISession_<routine>` stub, read from the disassembly:

- the routine number it dispatches on,
- the request/reply message sizes,
- the argument count and in/out direction.

Compare each against the corresponding `routine` declaration in the `.defs`.

A wrong `.defs` produces a server that mis-decodes every message of that routine
at runtime, and no amount of correct `IOSCSISession.m` compensates. **If a
mismatch is found, report it and stop** — rewriting the `.defs` is a separate
change with its own blast radius, and it would invalidate the generated side of
the build.

No MIG binary is available here, so this is a read-and-compare against the
declarations, not a regenerate-and-diff. It catches wrong routine numbers and
argument-count or size mismatches; it does not catch subtle codegen differences.

### 4.4 Disciplines for the nine bodies

Each of these has caught a real defect earlier in this series:

- Settle every method signature from `__OBJC,__meth_var_types` — never infer it
  from instructions.
- Resolve every `bl` to an unnamed `sub_XXXX` through `read_macho`'s relocation
  table. PowerPC jump islands (`lis r12 / ori / mtctr / bctr`) are not in IDA's
  export.
- Read ivars from `__OBJC,__instance_vars`, never by inference.
- Trace every bare constant to a named constant in this tree before writing it as
  one.
- Account for every instruction and every branch in writing.
- A confident guess is a defect; a recorded uncertainty is a result.

## 5. Build wiring

Add `IOTask.m` to `CLASSES` and `IOTask.h` to `HFILES` in
`SCSIServer.lksproj/Makefile`. The file has never been built: `CLASSES` currently
reads `SCSIServer.m IOSCSISession.m`, and the `Makefile` has not been touched
since the tree move.

`IOTask.m` declares the kernel dispatch table by raw offset:

```c
extern struct {
    char pad1[0x18];
    mach_port_t task_port;     /* offset +0x18 */
    char pad2[0x8c];
    void *port_funcs;          /* offset +0xa4 */
} *_entry;
```

Nothing in the tree declares `_entry` or `IOTaskWireMemory` except `IOTask.h`
itself, so these offsets are PPC-binary-derived with no in-tree corroboration.

`Makefile.preamble` sets `INCLUDED_ARCHS = i386 ppc`, and there is **no i386
`SCSIServer` binary** in the reference set, so the offsets cannot be checked for
that architecture. Per the decision taken during design, they go in as-is and the
exposure is recorded in `findings.md` rather than guarded with `#if
defined(__ppc__)`. A wrong offset here would wire or unwire the wrong memory on
i386 rather than fail at build time; the finding must say so plainly.

`drvSCSIServer` appears in no build list, so nothing builds this project today
under either architecture.

## 6. Artifacts

To `src/drvSCSIServer/reconstruction/SCSIServer/`, following the sibling
`drvSCSITape` precedent rather than `src/drivers-ppc/reconstruction/` —
`drvSCSIServer` is a top-level architecture-neutral project, not a PPC driver.

- `source-map.json`
- `ledger.json`
- `findings.md`

Cross-reference from `src/drivers-ppc/reconstruction/report-scsi.md`, which
already covers Mesh and Sym8xx.

## 7. Acceptance

1. The source map covers **47** of the 48 hand-written functions, with every
   unmapped entry enumerated and explained. The 48th is `+[SCSIServer
   deviceStyle]`, which cannot appear in any map because IDA's function list has
   no entry at `__text+0` (§4.1); it is a known exclusion, not a gap, and is
   confirmed present at `SCSIServer.m:37` by `selector_check.py`, which matches
   by string rather than by address.
2. `duplicate_candidates` is 0, or every entry is enumerated with evidence.
3. Bucket reconciliation reports `RECONCILES: yes`.
4. The MIG check reports per-routine agreement with `IOSCSISessionMig.defs`, or
   names the specific mismatch and stops.
5. All nine bodies written, each with an instruction-by-instruction account
   covering every branch.
6. `IOTask.m`/`IOTask.h` in `CLASSES`/`HFILES`.
7. The binrecon suite stays green (854 passed, 4 skipped at time of writing).

## 8. Constraints

- **No PowerPC toolchain and no host C compiler. Nothing compiles, and no claim
  of buildability may be made** — only of correspondence to the binary.
- Do not modify `src/kernel-7/`.
- Do not rewrite `IOSCSISessionMig.defs` under this spec; §4.3 governs.
- Commits: `drvSCSIServer: ` prefix, one to two lines, no metadata or trailers.

## 9. Risks

- The `_entry` offsets are unverified for i386 and enter the build under this
  spec.
- `_serverThreadFunc` may reference the reservation globals in ways that
  constrain data-section layout this spec has not measured. `IOTask.m`'s existing
  comments cite a client reference array at `0x4008`–`0x4087` with `_notifyThread`
  at `0x4088`; those addresses are from the earlier session and are themselves
  unverified by this measurement.
- If the `.defs` check fails, the spec stops short of its goal by design.
