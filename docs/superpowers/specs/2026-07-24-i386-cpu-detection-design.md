# i386 CPU Detection — Design

Date: 2026-07-24
Status: approved

## Problem

`machine_configure()` in `src/kernel-7/machdep/i386/i386_init.c` has two `#if 0`
blocks that disable the entire CPUID path, followed by an unconditional
override:

```c
machine_slot[0].cpu_subtype = CPU_SUBTYPE_586;
(void) strcpy(cpu_model, "586");
```

The override was added in commit 41ac8557 because without it the system did not
reach multi-user — `init` failed to exec. The commit message recorded the cause
as unknown: *"Something off on how the cpu_subtype is handled further
downstream."*

Consequences of the current state: `hw.model` reports `"586"` on every machine,
the CPUID code is dead weight, and the real defect is still present.

## Root cause

The defect is in unmodified Apple code. `git diff` against the Darwin 0.3 import
(19ffee9a) confirms `machdep/i386/kern_machdep.c` and `mach/machine.h` are
byte-identical to the original.

`grade_cpu_subtype()` in `machdep/i386/kern_machdep.c` switches on the *host*
subtype. Values outside the explicit `386`/`486`/`486SX`/`586` cases fall into a
`default:` arm that computes:

```c
return CPU_SUBTYPE_INTEL_FAMILY_MAX -
    CPU_SUBTYPE_INTEL_FAMILY(ms->cpu_subtype) -
    CPU_SUBTYPE_INTEL_FAMILY(cpu_subtype);
```

That is `15 - host_family - binary_family`, almost certainly a missing-parens
slip for `15 - (host_family - binary_family)`. Two consequences:

1. **Inverted preference.** On a family-6 host an `i386_ALL` slice (family 3)
   grades `15-6-3 = 6` while a `586` slice (family 5) grades `15-6-5 = 4`. The
   worse slice wins.

2. **Total failure at family >= 12.** On family 15 an `i386_ALL` slice grades
   `15-15-3 = -3`. `fatfile_getarch()` in `kern/mach_fat.c` starts at
   `best_grade = 0` and only accepts `grade > best_grade`, so it selects nothing
   and returns `LOAD_BADARCH`. Every fat binary fails to exec, including `init`.

Family 15 is not exotic: it is the base CPUID family of the Pentium 4 and of
every AMD processor from K8 through Zen, since those report base family `0xF`
with the real family in the extended field. The observed failures were on real
AMD hardware and on VMware passing an AMD host through. Apple shipped this code
only on family 4/5/6 parts, so the bug stayed latent.

## Constraint: prebuilt DR2 userland

`machine_slot[0].cpu_subtype` is not kernel-internal. It reaches userspace
through `host_info()` (`kern/host.c`) and `processor_info()` (`kern/processor.c`),
where it is consumed by prebuilt Rhapsody DR2 binaries — `dyld`, `libsys` — that
cannot be patched and whose arch tables stop at `CPU_SUBTYPE_PENTII_M5` =
`CPU_SUBTYPE_INTEL(6, 5)`.

Our own `src/cctools-2/libmacho/arch.c` degrades gracefully for unknown i386
subtypes (`NXGetArchInfoFromCpuType()` synthesizes a description;
`NXFindBestFatArch()` has a `default:` fallback chain). Whether DR2's older copy
does the same is unverifiable without booting. The design therefore reports a
conservative subtype and keeps a boot-time escape hatch.

## Scope

Two kernel files:

- `src/kernel-7/machdep/i386/kern_machdep.c` — rewrite subtype grading.
- `src/kernel-7/machdep/i386/i386_init.c` — restore CPU detection, remove the
  override.

No changes to `mach/machine.h`, `kern/mach_fat.c`, `kern/mach_loader.c`,
`bsd/kern/kern_sysctl.c`, or anything under `src/cctools-2/`.

Plus one host-side addition outside the kernel: `tools/cpusubtype-test/`, a
regression test that compiles the real `kern_machdep.c` on the development host
and asserts the grading table. The grading logic is pure integer arithmetic over
the `CPU_SUBTYPE_*` macros, so it is verifiable without target hardware — and
this bug stayed latent for 27 years precisely because nothing checked it.
`tools/` is already the tracked home for host-side tooling with its own tests.

## Design

### 1. Fat-slice grading (`kern_machdep.c`)

Replace both i386 functions with a host-subtype-agnostic form modeled on
`machdep/ppc/kern_machdep.c`, which carries Apple's own comment that it should
track `best_arch.c` in cctools. The preference order is taken from the
`CPU_TYPE_I386` case of `NXFindBestFatArch()` in
`src/cctools-2/libmacho/arch.c`: after an exact match, a post-Pentium host
prefers `586`, then `486`, then `i386_ALL`, then `486SX`, then any other Intel
subtype.

```c
int
grade_cpu_subtype (cpu_subtype)
cpu_subtype_t	cpu_subtype;
{
	struct machine_slot *ms = &machine_slot[cpu_number()];

	if (cpu_subtype == ms->cpu_subtype)
		return 6;

	if (CPU_SUBTYPE_INTEL_FAMILY(cpu_subtype) >
	    CPU_SUBTYPE_INTEL_FAMILY(ms->cpu_subtype))
		return 0;

	switch (cpu_subtype) {
	    case CPU_SUBTYPE_586:	/* == CPU_SUBTYPE_PENT */
		return 5;
	    case CPU_SUBTYPE_486:
		return 4;
	    case CPU_SUBTYPE_I386_ALL:	/* == CPU_SUBTYPE_386 */
		return 3;
	    case CPU_SUBTYPE_486SX:
		return 2;
	}

	return 1;
}

int
check_cpu_subtype (cpu_subtype)
cpu_subtype_t	cpu_subtype;
{
	return (grade_cpu_subtype(cpu_subtype) != 0);
}
```

A comment block above `grade_cpu_subtype()` names the cctools function the order
tracks and records why the original `switch (ms->cpu_subtype)` was removed,
mirroring how `machdep/ppc/kern_machdep.c` documents its own ordering.

The `switch (ms->cpu_subtype)` disappears. That is the point: grading no longer
depends on the host's exact subtype value, so it remains correct at family 15
and beyond, and cannot be broken by raising the clamp in section 3.

Deriving `check_cpu_subtype()` from `grade_cpu_subtype()` removes a second copy
of the same logic. The two currently duplicate it, which is how they could
disagree — a slice `grade` accepts but `check` rejects would be selected by
`fatfile_getarch()` and then refused by `load_machfile()`.

Intentional behavior changes, all toward cctools:

- `i386_ALL` now outranks `486SX` on a 486 or 586 host. The old code had it
  backwards; cctools reaches `i386_ALL` first for those hosts.
- Slice preference is correctly ordered on family-6 hosts (`586` > `486` >
  `i386_ALL`). The old arithmetic inverted it.
- A same-family, different-model slice (e.g. `PENTII_M3` on a `PENTPRO` host)
  grades 1 instead of 0, so it is acceptable rather than rejected. Within an
  Intel family the instruction set does not differ in any way Rhapsody
  distinguishes, and cctools' last-resort tier selects such slices too.

Note that `CPU_SUBTYPE_586`, `CPU_SUBTYPE_PENT` and `CPU_SUBTYPE_INTEL(5, 0)`
are all the value 5, and `CPU_SUBTYPE_I386_ALL` and `CPU_SUBTYPE_386` are both
3. Each appears once as a case label.

### 2. CPU detection (`i386_init.c`)

Three functions replacing the existing `cpuid()` / `get_cpuid()` /
`machine_configure()`. Same shape as what is there now; no new layering.

**`cpuid(leaf, regs)`** — raw instruction wrapper returning all four registers
rather than only `eax`. Retains the `pushl`/`popl %ebx` save-restore added in
commit a80a0ca1, since `ebx` is reserved under PIC. Results are written through
plain `unsigned int`; the current helper passes a bitfield struct through an
`"=a"` register constraint, which is unreliable on this compiler vintage.

**`cpu_identify(&id)`** — fills family, model, vendor string and brand string.
Query sequence, with each step gated on the previous one:

- CPUID availability: *toggle* `EFL_ID` (bit 21) and compare against the saved
  value, restoring EFLAGS unconditionally. The current code only sets the bit,
  which proves nothing if it was already set, and returns without restoring on
  one path.
- Leaf 0 → maximum basic leaf (`eax`) and the 12-byte vendor string
  (`ebx`, `edx`, `ecx`).
- Leaf 1, only if maximum basic leaf >= 1 → family, model, stepping. Fold the
  extended family when base family is `0xF`; fold the extended model when base
  family is `0xF` or `0x6`.
- Leaf `0x80000000` → maximum extended leaf, honored only if the returned value
  is `> 0x80000000`. Some processors echo the basic maximum here.
- Leaves `0x80000002`–`0x80000004`, only if maximum extended leaf is
  `>= 0x80000004` → the 48-byte brand string.

The `subtype=` boot argument (already wired up in the `kernargs` table) bypasses
CPUID entirely and supplies family and model directly, as it did before.

**`machine_configure()`** — maps the result onto the two globals and applies the
FPU gate described in section 4.

`is486_or_higher()` is fixed to restore EFLAGS on its `FALSE` path. It currently
returns with `EFL_AC` still set.

### 3. Reported identity

`machine_slot[0].cpu_subtype` is clamped so that no value outside DR2's arch
table is ever published:

| detected                                  | reported                |
|-------------------------------------------|-------------------------|
| CPUID unavailable                         | `CPU_SUBTYPE_486`       |
| family <= 4                               | `CPU_SUBTYPE_486`       |
| family 5                                  | `CPU_SUBTYPE_586`       |
| family >= 6 (including base `0xF` + ext.) | `CPU_SUBTYPE_PENTPRO`   |

The first row is written as `<= 4` rather than `== 4` deliberately. Real hardware
below family 4 never reaches this code — `is486_or_higher()` halts first — but the
`subtype=` boot argument can assert any family, so the mapping is total by
construction rather than relying on that.

There is no `486SX` row: a CPU without a hardware FPU now halts (section 4), so
the `cpu_config.fpu_type == FPU_HDW` test the disabled code used to choose
between `486` and `486SX` is gone.

`cpu_model[]` carries the real CPU identity. It is free-form text reached only
through the `hw.model` sysctl (`bsd/kern/kern_sysctl.c`), so no loader can choke
on it. In preference order:

1. The brand string, with leading and trailing whitespace trimmed. Intel
   left-pads it, and the 48-byte field is space- or NUL-filled on the right.
2. `"<vendor> family %d model %d"` using the effective family and model.
3. `"i86 family %d model %d"` when no vendor string is available.

Sizes fit `cpu_model[65]`: the brand string is 48 bytes plus NUL, and the vendor
form is at most about 34. `sprintf` is available from `bsd/kern/subr_prf.c`.

`machine` remains `"i386"` and `machine_slot[0].cpu_type` remains
`CPU_TYPE_I386`.

Rejected as unnecessary: reporting the exact `PENTII_M3` / `PENTII_M5` value on
genuine Pentium II hardware. It would be a few lines and carries no risk, but
nothing consumes the distinction.

### 4. Failure modes

| condition                | behavior                                                                       |
|--------------------------|--------------------------------------------------------------------------------|
| No hardware FPU          | `while (cpu_config.fpu_type != FPU_HDW) asm volatile("hlt");` after `fp_configure()` |
| Not 486 or higher        | existing halt loop, now restoring EFLAGS correctly                             |
| CPUID absent             | treated as a 486; no vendor or brand string; boots normally                    |
| Extended leaves absent   | vendor + family/model fallback string                                          |
| `subtype=N` boot arg     | skips CPUID; `subtype=5` forces `586`                                          |

The FPU gate is a halt loop rather than a `panic()` because `panic()` cannot run
at this point. `machine_configure()` is called from `i386_init()` before VM setup
and before `dbf_init()` installs the double-fault handler, while `panic()` in
`bsd/kern/subr_prf.c` takes `panic_lock` (initialized later by `panic_init()`),
dereferences `current_thread()->pcb`, and calls `boot()`. A panic there would
most likely triple-fault into a reboot loop. The existing rejection of non-486
CPUs is a halt loop for the same reason, and this matches it.

Floating-point emulation has been removed from this tree — `fp_emul` appears in
`conf/files.i386` only as `optional fp_emul` with no configuration enabling it,
so `FP_EMUL` is 0 and `fp_configure()` leaves `fpu_type` at `FPU_NONE`. Today
that is not a clean failure: `fp_noextension()` throws `EXC_EMULATION` at each
process as it reaches a floating-point instruction. Halting at boot is honest by
comparison.

Consequence worth naming: the `-f` / `RB_NOFP` boot flag forces `FPU_NONE` in
`fp_configure()`, so it now reaches the FPU halt loop. That flag existed to
exercise the emulator, which is gone. The `RB_NOFP` code path itself is left
untouched.

## Verification

Success criteria: both `#if 0` blocks and the forced-subtype override are gone
from `machine_configure()`, and:

1. The kernel builds clean on the Rhapsody guest.
2. It boots to multi-user on the AMD / VMware target and `init` runs. This is
   the real test of the `PENTPRO` clamp ceiling, since it is the first time
   prebuilt DR2 `dyld` sees a family-6 host subtype.
3. `sysctl hw.model` reports the brand string; `uname -m` reports `i386`.
4. `hostinfo` and `arch` run clean. Both route the reported subtype through
   DR2's arch tables.
5. A fat binary and a thin `i386_ALL` binary both exec.
6. Booting with `subtype=5` reports `586` and still reaches multi-user, proving
   the recovery lever works before it is needed.
7. Booting with `subtype=4` reports `486` and still reaches multi-user.

Per CLAUDE.md section 6, all boot testing runs against a temporary copy of the
disk image so it cannot collide with other debugging sessions.

If step 2 fails, step 6 is the fallback: `subtype=5` at the boot prompt restores
today's known-good behavior without rebuilding, and the clamp ceiling in
section 3 can be lowered to `CPU_SUBTYPE_586` as a one-line change.
