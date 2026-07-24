# i386 Platform Expert — Phase 3: Discovery — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the platform expert the single owner of hardware discovery — CPU identification, firmware table scanning, PCI configuration access, EISA and ISA Plug and Play enumeration — publishing everything it finds through `pexpert_i386.h`, and selecting one of three platform families from the results.

**Architecture:** Discovery runs first and unconditionally during `i386_init()`, before `pmap_bootstrap`, copying every table it finds into a static arena so nothing points at firmware memory. Family selection then reads the published results. The pure parsers are developed test-first against a host-built test binary; the hardware-touching code is verified by boot.

**Tech Stack:** C, NeXT `pb_makefiles`, `gnumake`, the in-tree C89 test harness pattern from `src/rbuild-1/tests/test.h`, QEMU boot verification.

## Global Constraints

- **Design spec:** `docs/specs/2026-07-24-i386-platform-expert-design.md`.
- **Phases 1 and 2 must be complete** and their exit criteria met.
- **This phase is test-first for the parsers.** Every function that takes a byte buffer and returns a structure gets a failing test before it gets an implementation. Hardware-touching code (port I/O, CPUID) is boot-verified instead — do not fake hardware in the test harness.
- **`machine_slot[0].cpu_subtype` must remain `CPU_SUBTYPE_586` and `cpu_model` must remain `"586"`.** The existing code forces these with the comment *"force a 586/Pentium CPU type, otherwise we crash, probably due to cctools not supporting higher subtypes"* and keeps the real CPUID switch under `#if 0`. Phase 3 populates the **new** `i386_platform_info` fields from CPUID but does not change what is reported to Mach. Re-enabling the real subtype is separate work.
- **No AML interpreter.** ACPI support is static-table parsing only: RSDP, RSDT, XSDT, MADT, FADT, HPET. Nothing evaluates bytecode.
- **Nothing acts on the MP or MADT tables in this phase.** They are discovered and published. APIC support is Phase 5 or later.
- **The arena is fixed at 8 KB.** On overflow, publish the affected table pointer as `NULL` and print a console warning. Never publish a truncated table.
- **Commit messages** start with `pexpert: `; one to two lines; no metadata.
- **All boot testing uses a throwaway copy of `vm/rhapsody.vmdk`.**

## Header bootstrap: unresolved, read before a packaged build

This phase adds a **new** kernel-tree header, `machdep/i386/pexpert_i386.h`, and the platform expert compiles against it. That works in the manual guest workflow but not yet in a clean `rbuild buildall`, for a reason that is structural rather than a plan defect:

- `HEADER_PATHS = -I$(KERNEL_HEADERS)/machdep` resolves to **installed** headers, supplied by the `kernel-hdrs` package.
- `kernel-hdrs` is listed in `basedeps[]` (`src/rbuild-1/builder.c:441`) and is therefore pulled in by every `build-base` dependency, including drvPExpert's.
- No in-tree project currently produces it: `src/kernel-7/dpkg/` holds exactly one control file, `Package: kernel`. It is seeded.
- rbuild *does* support producing it — a Manifest target of `headers` builds `<package>-hdrs` (`src/rbuild-1/builder.c:941`), so `dir kernel-7 headers` would yield `kernel-hdrs` from source.
- But `builder_setupdirs()` runs unconditionally at `src/rbuild-1/builder.c:979`, **before** the `do_hdr` / `do_bin` split, so even a `headers` build installs the project's full `Build-Depends` — which for `kernel` includes `drvpexpert`. That closes a cycle: `kernel-hdrs` needs `drvpexpert`, and `drvpexpert` needs `kernel-hdrs`.

Manifest ordering cannot break this, because rbuild reads one control file per project and cannot vary dependencies per target.

**Phases 1 and 2 are unaffected** — they add no kernel headers and compile fine against the seeded `kernel-hdrs`. The decision is only needed before Task 1 of this phase lands in a packaged build. Options, in the order they should be considered:

1. **Let the platform expert own and install `pexpert_i386.h`.** The PExpert defines and populates those structures, so it is the natural producer; the kernel and bus drivers become consumers. Removes the cycle outright and keeps one owner per header. Costs: the kernel gains an include path into a driver project, and the install must land in the same PrivateHeaders tree.
2. **Drop `drvpexpert` from `kernel`'s `Build-Depends` and supply `pexperti386.o` another way** — for instance by having the kernel link against the object in the build tree rather than from the chroot. Removes the cycle at its source but changes how the kernel link is fed.
3. **Teach rbuild to skip binary-only dependencies for `headers` targets.** The correct general fix, and the largest; it is a change to `builder_setupdirs()` and belongs in its own piece of work.

Do not begin Task 1 of this phase in a packaged build until one of these is chosen and recorded here.

---

### Task 1: The public contract and the table arena

**Files:**
- Create: `src/kernel-7/machdep/i386/pexpert_i386.h`
- Create: `src/drivers-i386/bus/drvPExpert/i386/arena.c`
- Create: `src/drivers-i386/bus/drvPExpert/i386/arena.h`
- Modify: `src/drivers-i386/bus/drvPExpert/i386/Makefile`, `PB.project`

`pexpert_i386.h` goes in the **kernel tree**, not the platform expert: it is a contract header, installed by the existing `i386_installhdrs` rule, and the platform expert reaches it through `HEADER_PATHS`. This is the deliberate no-duplication rule from the spec — the ppc project's duplicated `powermac.h` has already drifted 22 lines.

**Interfaces:**
- Produces `pexpert_i386.h` with `i386_platform_info_t`, `i386_firmware_info_t`, the `I386_CLASS_*` and `I386_HV_*` constants, and the two `extern` globals.
- Produces `arena.h`: `void *pexpert_arena_copy(const void *src, unsigned int len);` returning `NULL` on overflow, and `void pexpert_arena_report(void);`.

- [ ] **Step 1: Write the public contract header**

`src/kernel-7/machdep/i386/pexpert_i386.h`:

```c
/*
 * i386 platform expert public interface.
 *
 * Populated by the platform expert (pexperti386.o) during early boot and read
 * by the kernel and by DriverKit bus drivers.  See
 * docs/specs/2026-07-24-i386-platform-expert-design.md.
 */

#ifndef _PEXPERT_I386_H_
#define _PEXPERT_I386_H_

/* Platform class, selected by i386_identify(). */
#define I386_CLASS_ATPC		1	/* ISA/EISA, no PCI */
#define I386_CLASS_PCIPC	2	/* PCI, no ACPI */
#define I386_CLASS_ACPIPC	3	/* PCI and ACPI static tables */

/* Hypervisor identity.  Orthogonal to class: a guest normally has both. */
#define I386_HV_NONE		0
#define I386_HV_VMWARE		1
#define I386_HV_VBOX		2
#define I386_HV_QEMU		3
#define I386_HV_HYPERV		4

typedef struct i386_platform_info {
    int			class;
    int			hypervisor;
    char		cpu_vendor[13];		/* CPUID leaf 0, NUL terminated */
    char		cpu_model[64];
    unsigned int	cpu_family;
    unsigned int	cpu_model_id;
    unsigned int	cpu_stepping;
    unsigned int	cpu_feature_edx;	/* CPUID leaf 1 EDX */
    unsigned int	cpu_feature_ecx;	/* CPUID leaf 1 ECX */
    unsigned int	tsc_hz;			/* 0 if no TSC */
} i386_platform_info_t;

/*
 * Every pointer below refers to a platform-expert-owned copy in the discovery
 * arena, never to firmware memory.  NULL means absent or not copied.
 */
typedef struct i386_firmware_info {
    void		*mp_fps;		/* MP Floating Pointer Structure */
    void		*mp_config;		/* MP Configuration Table */
    void		*pir_table;		/* $PIR PCI IRQ routing table */
    void		*pnp_bios;		/* $PnP installation check */
    void		*acpi_rsdp;
    void		*acpi_rsdt;
    void		*acpi_xsdt;
    void		*acpi_madt;
    void		*acpi_fadt;
    void		*acpi_hpet;
    void		*bios32;		/* BIOS32 service directory */
    void		*pci_bios;		/* PCI BIOS entry via BIOS32 */
    int			pci_config_mechanism;	/* 0 none, 1, 2 */
    int			pci_last_bus;
    int			eisa_present;
    int			eisa_slots;
    int			isapnp_cards;		/* CSNs assigned, 0 if none */
} i386_firmware_info_t;

extern i386_platform_info_t	i386_platform_info;
extern i386_firmware_info_t	i386_firmware_info;

/* PCI configuration space access.  Returns 0 on success, -1 on failure. */
extern int pexpert_pci_config_read(int bus, int dev, int fn, int off,
				   int size, unsigned int *val);
extern int pexpert_pci_config_write(int bus, int dev, int fn, int off,
				    int size, unsigned int val);

#endif /* _PEXPERT_I386_H_ */
```

- [ ] **Step 2: Write the arena header**

`src/drivers-i386/bus/drvPExpert/i386/arena.h`:

```c
/*
 * Discovery arena.
 *
 * Firmware tables live in the BIOS ROM window and in ACPI reclaim memory.
 * Rather than map and hold those regions, discovery copies what it needs here
 * during early boot, while low memory is still plainly reachable and before
 * pmap_bootstrap runs.  Everything published in i386_firmware_info points in
 * here.
 */

#ifndef _PEXPERT_ARENA_H_
#define _PEXPERT_ARENA_H_

#define PEXPERT_ARENA_SIZE	8192

/*
 * Copy len bytes into the arena and return the copy, or NULL if the arena is
 * exhausted.  A NULL return must be published as an absent table; never
 * publish a partial copy.
 */
extern void *pexpert_arena_copy(const void *src, unsigned int len);

/* Print arena usage, and a warning if any copy was refused. */
extern void pexpert_arena_report(void);

#endif /* _PEXPERT_ARENA_H_ */
```

- [ ] **Step 3: Write the arena implementation**

`src/drivers-i386/bus/drvPExpert/i386/arena.c`:

```c
#import <mach/mach_types.h>

#import "arena.h"

static char		arena[PEXPERT_ARENA_SIZE];
static unsigned int	arena_used;
static int		arena_refused;

void *
pexpert_arena_copy(const void *src, unsigned int len)
{
    unsigned int	aligned = (len + 3) & ~3u;
    char		*dst;

    if (src == 0 || len == 0)
	return (0);

    if (arena_used + aligned > PEXPERT_ARENA_SIZE) {
	arena_refused++;
	return (0);
    }

    dst = &arena[arena_used];
    arena_used += aligned;

    bcopy((const char *)src, dst, len);

    return (dst);
}

void
pexpert_arena_report(void)
{
    printf("PExpert: discovery arena %d/%d bytes used\n",
	   arena_used, PEXPERT_ARENA_SIZE);

    if (arena_refused)
	printf("PExpert: WARNING %d firmware table(s) too large for the arena "
	       "and were not copied; they are reported as absent.  Raise "
	       "PEXPERT_ARENA_SIZE in arena.h.\n", arena_refused);
}
```

- [ ] **Step 4: Define the two globals**

Add to `src/drivers-i386/bus/drvPExpert/i386/i386_init.c`, near the other globals:

```c
#import <machdep/i386/pexpert_i386.h>

i386_platform_info_t	i386_platform_info;
i386_firmware_info_t	i386_firmware_info;
```

- [ ] **Step 5: Register in the build and confirm the header installs**

`Makefile`: add `arena.c` to `CFILES`, `arena.h` to `HFILES`.
`PB.project`: add both to `OTHER_LINKED` / `H_FILES`.

```bash
powershell -File vm/rhap-vm.ps1 sync
powershell -File vm/rhap-vm.ps1 ssh "cd /build/source/src/kernel-7 && gnumake installhdrs DSTROOT=/"
powershell -File vm/rhap-vm.ps1 ssh "ls -l '/System/Library/Frameworks/System.framework/Versions/B/PrivateHeaders/machdep/i386/pexpert_i386.h'"
```

The mechanism is `MACHINE_LCLEXPORT` in `src/kernel-7/conf/Makefile.i386`, which lists `machdep/i386` and installs its `*.h` into `LCLDIR` (`src/kernel-7/conf/Makefile.template:170`). It is **not** the `i386_installhdrs` rule, which installs only `${FEATURES}`.

Two properties of that export path matter here and are already satisfied:

- `MACHINE_LCLEXPORT` installs with a plain `install`, **no `unifdef`**. The stripping pass at `Makefile.template:977` (`-UKERNEL_PRIVATE -UDRIVER_PRIVATE`) belongs to `install_md_std_hdrs`, which iterates `MACHINE_EXPORT` — and `MACHINE_EXPORT` does not include `machdep/i386`. So `KERNEL_PRIVATE`-guarded content in `machdep/i386` headers survives into PrivateHeaders. This is what makes Phase 1's `-DKERNEL_PRIVATE` work for `bios.h`.
- `pexpert_i386.h` as written is **not** wrapped in `#ifdef KERNEL_PRIVATE`, so it would survive either path. Keep it that way — bus drivers consume it.

**Read the header-bootstrap note in this plan's preamble before running a packaged `rbuild` build**; the manual `installhdrs` above is sufficient for the `rhap-vm.ps1` workflow only.

- [ ] **Step 6: Build, diff symbols, boot gate, commit**

Expected symbol additions: `_i386_platform_info`, `_i386_firmware_info`, `_pexpert_arena_copy`, `_pexpert_arena_report`. Boot to login.

```bash
git add src/kernel-7/machdep/i386/pexpert_i386.h src/drivers-i386/bus/drvPExpert
git commit -m "pexpert: add the i386 platform expert public contract and table arena"
```

---

### Task 2: Test harness and the ACPI static table parser

**Files:**
- Create: `src/drivers-i386/bus/drvPExpert/tests/test.h`
- Create: `src/drivers-i386/bus/drvPExpert/tests/Makefile`
- Create: `src/drivers-i386/bus/drvPExpert/tests/test_acpi.c`
- Create: `src/drivers-i386/bus/drvPExpert/i386/acpi.c`
- Create: `src/drivers-i386/bus/drvPExpert/i386/acpi.h`

The tests build as a **host binary** with plain `cc`, linking only the pure parser objects. They never link the kernel or touch hardware.

**Interfaces:**
- Produces, in `acpi.h`:
  - `int acpi_checksum_ok(const void *table, unsigned int len);`
  - `int acpi_rsdp_valid(const void *rsdp);`
  - `unsigned int acpi_table_length(const void *table);`
  - `int acpi_table_is(const void *table, const char *sig);`

- [ ] **Step 1: Copy the test harness**

Copy `src/rbuild-1/tests/test.h` verbatim to `src/drivers-i386/bus/drvPExpert/tests/test.h`, changing only the include guard from `RBUILD_TEST_H` to `PEXPERT_TEST_H`.

- [ ] **Step 2: Write the failing test**

`src/drivers-i386/bus/drvPExpert/tests/test_acpi.c`:

```c
#include "test.h"
#include "../i386/acpi.h"

/* An RSDP is 20 bytes for revision 0: signature, checksum, OEMID, revision,
   RsdtAddress.  The whole 20 bytes must sum to zero mod 256. */
static unsigned char rsdp_good[20] = {
    'R','S','D',' ','P','T','R',' ',	/* signature            */
    0x00,				/* checksum, fixed below */
    'R','H','A','P','S','D',		/* OEMID                */
    0x00,				/* revision 0           */
    0x00,0x00,0x10,0x00			/* RsdtAddress          */
};

static void
fix_checksum(unsigned char *p, unsigned int len, unsigned int csum_off)
{
    unsigned int	i, sum = 0;

    p[csum_off] = 0;
    for (i = 0; i < len; i++)
	sum += p[i];
    p[csum_off] = (unsigned char)(0x100 - (sum & 0xff));
}

TEST(test_checksum_accepts_zero_sum)
{
    fix_checksum(rsdp_good, 20, 8);
    CHECK_INT(acpi_checksum_ok(rsdp_good, 20), 1);
}

TEST(test_checksum_rejects_corruption)
{
    unsigned char	bad[20];

    fix_checksum(rsdp_good, 20, 8);
    memcpy(bad, rsdp_good, 20);
    bad[19] ^= 0xff;
    CHECK_INT(acpi_checksum_ok(bad, 20), 0);
}

TEST(test_rsdp_valid_accepts_good_signature)
{
    fix_checksum(rsdp_good, 20, 8);
    CHECK_INT(acpi_rsdp_valid(rsdp_good), 1);
}

TEST(test_rsdp_valid_rejects_wrong_signature)
{
    unsigned char	bad[20];

    fix_checksum(rsdp_good, 20, 8);
    memcpy(bad, rsdp_good, 20);
    bad[0] = 'X';
    CHECK_INT(acpi_rsdp_valid(bad), 0);
}

/* A generic SDT header is 36 bytes; length is at offset 4, little endian. */
TEST(test_table_length_reads_offset_4)
{
    unsigned char	sdt[36];

    memset(sdt, 0, sizeof sdt);
    memcpy(sdt, "APIC", 4);
    sdt[4] = 0x2c; sdt[5] = 0x00; sdt[6] = 0x00; sdt[7] = 0x00;
    CHECK_INT(acpi_table_length(sdt), 0x2c);
}

TEST(test_table_is_matches_signature)
{
    unsigned char	sdt[36];

    memset(sdt, 0, sizeof sdt);
    memcpy(sdt, "APIC", 4);
    CHECK_INT(acpi_table_is(sdt, "APIC"), 1);
    CHECK_INT(acpi_table_is(sdt, "FACP"), 0);
}

static void
run_all(void)
{
    RUN(test_checksum_accepts_zero_sum);
    RUN(test_checksum_rejects_corruption);
    RUN(test_rsdp_valid_accepts_good_signature);
    RUN(test_rsdp_valid_rejects_wrong_signature);
    RUN(test_table_length_reads_offset_4);
    RUN(test_table_is_matches_signature);
}

TEST_MAIN()
```

- [ ] **Step 3: Write the test Makefile**

`src/drivers-i386/bus/drvPExpert/tests/Makefile`:

```make
# Host-side unit tests for the platform expert's pure parsers.
#
# These link only parser objects, never kernel code.  Parsers must therefore
# stay free of port I/O, kernel headers and global hardware state; anything
# that touches hardware is boot-verified instead.

CC = cc
# Plain -ansi/-pedantic break Rhapsody System headers (__inline, u_int32_t).
CFLAGS = -Wall -O -I../i386 -DPEXPERT_HOSTTEST

TESTS = test_acpi

.PHONY: test clean

test: $(TESTS)
	@fail=0; for t in $(TESTS); do echo "== $$t =="; ./$$t || fail=1; done; \
		[ $$fail -eq 0 ] && echo "ALL TESTS PASSED" || (echo "TESTS FAILED"; exit 1)

test_acpi: test_acpi.c ../i386/acpi.c
	$(CC) $(CFLAGS) -o $@ test_acpi.c ../i386/acpi.c

clean:
	rm -f $(TESTS) *.o
```

- [ ] **Step 4: Run the test and verify it fails**

```bash
powershell -File vm/rhap-vm.ps1 sync
powershell -File vm/rhap-vm.ps1 ssh "cd /build/source/src/drivers-i386/bus/drvPExpert/tests && gnumake test"
```

Expected: FAIL — `../i386/acpi.c` does not exist.

- [ ] **Step 5: Write acpi.h**

`src/drivers-i386/bus/drvPExpert/i386/acpi.h`:

```c
/*
 * ACPI static table access.  Structure parsing only -- there is deliberately
 * no AML interpreter and there never will be one.
 *
 * Every function here is pure: buffer in, answer out, no port I/O and no
 * kernel state, so it can be unit tested on the host.
 */

#ifndef _PEXPERT_ACPI_H_
#define _PEXPERT_ACPI_H_

#define ACPI_RSDP_SIG		"RSD PTR "
#define ACPI_RSDP_SIGLEN	8
#define ACPI_RSDP_V0_LEN	20
#define ACPI_SDT_HDR_LEN	36

/* 1 if the bytes of table sum to zero mod 256, else 0. */
extern int acpi_checksum_ok(const void *table, unsigned int len);

/* 1 if rsdp has the RSDP signature and a valid 20-byte checksum, else 0. */
extern int acpi_rsdp_valid(const void *rsdp);

/* Length field at offset 4 of a system description table header. */
extern unsigned int acpi_table_length(const void *table);

/* 1 if the table's four signature bytes equal sig, else 0. */
extern int acpi_table_is(const void *table, const char *sig);

#endif /* _PEXPERT_ACPI_H_ */
```

- [ ] **Step 6: Write acpi.c**

`src/drivers-i386/bus/drvPExpert/i386/acpi.c`:

```c
#import "acpi.h"

int
acpi_checksum_ok(const void *table, unsigned int len)
{
    const unsigned char	*p = (const unsigned char *)table;
    unsigned int	i, sum = 0;

    if (p == 0 || len == 0)
	return (0);

    for (i = 0; i < len; i++)
	sum += p[i];

    return ((sum & 0xff) == 0);
}

int
acpi_rsdp_valid(const void *rsdp)
{
    const unsigned char	*p = (const unsigned char *)rsdp;
    int			i;

    if (p == 0)
	return (0);

    for (i = 0; i < ACPI_RSDP_SIGLEN; i++)
	if (p[i] != (unsigned char)ACPI_RSDP_SIG[i])
	    return (0);

    return (acpi_checksum_ok(p, ACPI_RSDP_V0_LEN));
}

unsigned int
acpi_table_length(const void *table)
{
    const unsigned char	*p = (const unsigned char *)table;

    if (p == 0)
	return (0);

    return ((unsigned int)p[4]        |
	    ((unsigned int)p[5] << 8)  |
	    ((unsigned int)p[6] << 16) |
	    ((unsigned int)p[7] << 24));
}

int
acpi_table_is(const void *table, const char *sig)
{
    const unsigned char	*p = (const unsigned char *)table;
    int			i;

    if (p == 0 || sig == 0)
	return (0);

    for (i = 0; i < 4; i++)
	if (p[i] != (unsigned char)sig[i])
	    return (0);

    return (1);
}
```

Note the deliberate absence of `<string.h>` and of any kernel header: this file must compile both against the host libc for tests and inside the kernel-server build.

- [ ] **Step 7: Run the tests and verify they pass**

```bash
powershell -File vm/rhap-vm.ps1 ssh "cd /build/source/src/drivers-i386/bus/drvPExpert/tests && gnumake test"
```

Expected: `ALL TESTS PASSED`, 8 checks, 0 failures.

- [ ] **Step 8: Add acpi.c to the kernel-server build and commit**

`Makefile`: add `acpi.c` to `CFILES`, `acpi.h` to `HFILES`. `PB.project` likewise. Build the platform expert to confirm it compiles in the kernel context too.

```bash
git add src/drivers-i386/bus/drvPExpert
git commit -m "pexpert: add ACPI static table parsing with host-side unit tests"
```

---

### Task 3: MP Floating Pointer and $PIR parsers

Same test-first shape as Task 2.

**Files:**
- Create: `src/drivers-i386/bus/drvPExpert/i386/mptable.c`, `mptable.h`
- Create: `src/drivers-i386/bus/drvPExpert/i386/pirtable.c`, `pirtable.h`
- Create: `src/drivers-i386/bus/drvPExpert/tests/test_mptable.c`, `test_pirtable.c`
- Modify: `src/drivers-i386/bus/drvPExpert/tests/Makefile` (add both to `TESTS` with matching rules)

**Interfaces:**
- `mptable.h`: `int mp_fps_valid(const void *fps);` — checks the `_MP_` signature, a length field of 1 (meaning 16 bytes) and a zero byte-sum. `unsigned int mp_fps_config_addr(const void *fps);` — the physical address at offset 4. `int mp_config_valid(const void *cfg);` — checks the `PCMP` signature and the checksum over its `base_table_length`.
- `pirtable.h`: `int pir_valid(const void *pir);` — checks the `$PIR` signature and a zero byte-sum over the length at offset 6. `int pir_slot_count(const void *pir);` — `(length - 32) / 16`.

- [ ] **Step 1: Write failing tests for both parsers**

Follow the exact shape of `test_acpi.c`: build a synthetic byte array for each structure, a local `fix_checksum` helper, and one `TEST` per accept case and per reject case. Cover, for each parser: valid structure accepted, wrong signature rejected, corrupted checksum rejected, and the derived accessor (`mp_fps_config_addr`, `pir_slot_count`) returning the planted value.

- [ ] **Step 2: Run and verify both fail**

```bash
powershell -File vm/rhap-vm.ps1 ssh "cd /build/source/src/drivers-i386/bus/drvPExpert/tests && gnumake test"
```

Expected: FAIL, missing source files.

- [ ] **Step 3: Implement both parsers**

Write `mptable.{c,h}` and `pirtable.{c,h}` following the constraints proven by Task 2: no `<string.h>`, no kernel headers, no port I/O, byte-at-a-time little-endian assembly like `acpi_table_length`. Reuse `acpi_checksum_ok` by including `acpi.h` rather than writing a second checksum routine — the algorithm is identical for all three table families.

- [ ] **Step 4: Run tests, verify pass, add to the kernel-server build, commit**

```bash
git add src/drivers-i386/bus/drvPExpert
git commit -m "pexpert: add MP table and \$PIR parsing with host-side unit tests"
```

---

### Task 4: EISA identifier decode and the PnP resource tag parser

The PnP resource-data tag format is shared by ISA PnP cards, PnP BIOS device nodes and EISA function data. Today it is parsed independently by six Objective-C files in `drvEISABus` totalling 2,530 lines (`PnPResources.m` 571, `PnPDeviceResources.m` 660, `pnpMemory.m` 525, `pnpIOPort.m` 262, `pnpIRQ.m` 256, `pnpDMA.m` 256). This task produces the one C parser they will be rebuilt on in Phase 4.

**Files:**
- Create: `src/drivers-i386/bus/drvPExpert/i386/chips/eisa.c`, `chips/eisa.h`
- Create: `src/drivers-i386/bus/drvPExpert/i386/pnp_resource.c`, `pnp_resource.h`
- Create: `src/drivers-i386/bus/drvPExpert/tests/test_eisa.c`, `test_pnp_resource.c`
- Modify: `src/drivers-i386/bus/drvPExpert/tests/Makefile`

**Interfaces:**
- `chips/eisa.h`, pure half only: `unsigned int eisa_id_decode(const unsigned char id[4]);` and `void eisa_id_string(unsigned int id, char out[8]);` — the three-letter compressed manufacturer code plus product and revision. Modelled on `EISAParseID` at `src/drivers-i386/bus/drvEISABus/EISABus.drvproj/EISABus.lksproj/eisa.c:63`. The port-touching half (`eisa_slot_id`, reading `0xC80 + (slot << 12)`) goes in the same file but is not unit tested.
- `pnp_resource.h`:

```c
#define PNP_RES_IRQ	1
#define PNP_RES_DMA	2
#define PNP_RES_IO	3
#define PNP_RES_MEM	4

typedef struct pnp_resource {
    int			type;		/* PNP_RES_* */
    unsigned int	base;		/* IO/mem base, or IRQ/DMA mask */
    unsigned int	length;		/* IO/mem length, 0 for IRQ/DMA */
    int			dependent;	/* dependent-function index, -1 if none */
} pnp_resource_t;

/*
 * Walk the PnP resource data in buf and fill out[] with at most max entries.
 * Returns the number written, or -1 if the data is malformed.
 */
extern int pnp_resource_parse(const unsigned char *buf, unsigned int len,
			      pnp_resource_t *out, int max);
```

- [ ] **Step 1: Write the failing tests**

For `test_eisa.c`, cover: a known compressed ID round-trips to the expected three-letter string, and a zero ID and an all-ones ID are both handled without reading out of bounds.

For `test_pnp_resource.c`, build a synthetic tag stream by hand and cover, at minimum: a small IRQ tag yields one `PNP_RES_IRQ` with the planted mask; a small IO-port tag yields base and length; a large memory-range tag yields base and length; a start-dependent / end-dependent pair sets `dependent` on the enclosed entries; an END tag terminates; a stream that runs off the end of `len` returns -1; and a stream with more resources than `max` returns exactly `max`.

That last case matters — a silent truncation here becomes a device that appears to have fewer resources than it does.

- [ ] **Step 2: Run and verify they fail**

- [ ] **Step 3: Implement both**

Read `eisa.c:63` (`EISAParseID`) and `PnPResources.m` in `drvEISABus` before writing, and reproduce the wire format they decode rather than inventing one. Keep both new files free of kernel headers and port I/O **except** for the `eisa_slot_id` function, which must be guarded so the host test build excludes it:

```c
#ifndef PEXPERT_HOSTTEST
#import <machdep/i386/io_inline.h>

unsigned int
eisa_slot_id(int slot)
{
    /* ... port access, boot-verified only ... */
}
#endif /* !PEXPERT_HOSTTEST */
```

`PEXPERT_HOSTTEST` is already defined by the test Makefile's `CFLAGS`.

- [ ] **Step 4: Run tests, verify pass, add to the kernel-server build, commit**

`Makefile`: add `pnp_resource.c` to `CFILES`. `chips/Makefile`: add `eisa.c` to `CFILES`, `eisa.h` to `HFILES`.

```bash
git add src/drivers-i386/bus/drvPExpert
git commit -m "pexpert: add EISA ID decode and a shared PnP resource tag parser"
```

---

### Task 5: Split identify_machine.c out of i386_init.c

**Files:**
- Create: `src/drivers-i386/bus/drvPExpert/i386/identify_machine.c`
- Modify: `src/drivers-i386/bus/drvPExpert/i386/i386_init.c` (remove the moved code)

**Interfaces:**
- Produces: `void i386_identify_cpu(void);` — fills the CPU fields of `i386_platform_info`.
- Produces: `void i386_configure_machine(void);` — the former `static machine_configure()`, renamed and made non-static so the family vtables in Task 9 can point at it.
- Produces: `int i386_identify_hypervisor(void);` — returns an `I386_HV_*` value.
- Produces: `int cpuid_supported(void);` and `void cpuid_signature(unsigned int leaf, char out[13]);`

- [ ] **Step 1: Move the CPU identification code**

Cut from `i386_init.c` into `identify_machine.c`: the `cpuid_t` typedef, `cpuid()`, `get_cpuid()`, `is486_or_higher()`, `machine_configure()`, the `cpu_model[65]` and `machine[65]` definitions, and the `EFL_ID` define. Keep the static `subtype` variable's `kernargs` entry in `i386_init.c` and make `subtype` a non-static global so `get_cpuid()` can still read it; declare it `extern int subtype;` in `identify_machine.c`.

**Rename `machine_configure` to `i386_configure_machine` and drop its `static`.** Task 9's family vtables take its address, so it must have external linkage. Update its one caller in `i386_init()` at the same time. Add `void i386_identify_cpu(void);` as a small non-static wrapper holding the new CPUID population from Steps 2-3 below, so the vtable entry point and the identification entry point stay distinct.

- [ ] **Step 2: Populate the new platform info fields without changing what Mach sees**

Extend `i386_configure_machine()` — now in `identify_machine.c` — to fill `i386_platform_info` from a real CPUID call:

```c
    {
	cpuid_t	pid = get_cpuid();

	i386_platform_info.cpu_family   = pid.family;
	i386_platform_info.cpu_model_id = pid.model;
	i386_platform_info.cpu_stepping = pid.step;

	if (pid.family == 0x0f)
	    i386_platform_info.cpu_family += pid.ext_family;
	if (pid.family == 0x0f || pid.family == 0x06)
	    i386_platform_info.cpu_model_id += (pid.ext_model << 4);
    }
```

**Leave the two lines below untouched.** They are the existing deliberate workaround and this phase does not change them:

```c
    machine_slot[0].cpu_subtype = CPU_SUBTYPE_586;
    (void) strcpy(cpu_model, "586");
```

Also leave the large `#if 0` block that contains the real subtype switch exactly where it is. Re-enabling it is separate work that requires a cctools fix.

Copy `cpu_model` into `i386_platform_info.cpu_model` after the `strcpy`, so the published struct agrees with what Mach reports.

- [ ] **Step 3: Add the vendor string and feature words**

Add a CPUID leaf-0 call filling `i386_platform_info.cpu_vendor` (EBX, EDX, ECX in that order, 12 bytes plus a NUL) and a leaf-1 call filling `cpu_feature_edx` and `cpu_feature_ecx`. Guard both on the `EFL_ID` test that `get_cpuid()` already performs — on a CPU without CPUID, leave the fields zero and `cpu_vendor` an empty string.

- [ ] **Step 4: Add hypervisor detection**

```c
int
i386_identify_hypervisor(void)
{
    char	sig[13];

    /* CPUID leaf 0x40000000 returns a 12-byte vendor signature in EBX:ECX:EDX
       on every hypervisor that implements the paravirt leaf convention.  On
       bare metal the leaf is normally not implemented and returns zeros or
       the highest-basic-leaf result, neither of which matches below. */

    if (!cpuid_supported())
	return (I386_HV_NONE);

    cpuid_signature(0x40000000, sig);

    if (strncmp(sig, "VMwareVMware", 12) == 0)	return (I386_HV_VMWARE);
    if (strncmp(sig, "VBoxVBoxVBox", 12) == 0)	return (I386_HV_VBOX);
    if (strncmp(sig, "KVMKVMKVM",     9) == 0)	return (I386_HV_QEMU);
    if (strncmp(sig, "TCGTCGTCGTCG", 12) == 0)	return (I386_HV_QEMU);
    if (strncmp(sig, "Microsoft Hv", 12) == 0)	return (I386_HV_HYPERV);

    return (I386_HV_NONE);
}
```

Write the `cpuid_supported()` and `cpuid_signature(leaf, out)` helpers alongside; `cpuid_supported()` is the `EFL_ID` toggle already inside `get_cpuid()`, factored out.

- [ ] **Step 5: Register in the build, boot gate, commit**

Boot and confirm the console still reports the same CPU as the baseline — this task must not change any user-visible output yet.

```bash
git add src/drivers-i386/bus/drvPExpert
git commit -m "pexpert: split CPU identification out of i386_init

Publishes real CPUID data in i386_platform_info; the reported Mach subtype
stays forced to 586."
```

---

### Task 6: Split mem_init.c out of i386_init.c

**Files:**
- Create: `src/drivers-i386/bus/drvPExpert/i386/mem_init.c`
- Modify: `src/drivers-i386/bus/drvPExpert/i386/i386_init.c`

- [ ] **Step 1: Move the memory code**

Cut from `i386_init.c` into `mem_init.c`: `size_memory()`, `alloc_cnvmem()`, `alloc_pages()`, `bios_extdata_addr()`, and the file-static `first_addr`, `last_addr`, `first_addr0`, `last_addr0`, `maxmem` variables. Make `maxmem` a non-static global, since `i386_init.c`'s `kernargs` table takes its address; declare `extern unsigned int maxmem;` in `i386_init.c`.

Keep `mem_region[]`, `num_regions`, `mem_size`, `virtual_avail` and `virtual_end` defined in `mem_init.c` and declare them `extern` in `i386_init.c`.

- [ ] **Step 2: Build, diff symbols, boot gate, commit**

Expected: no new or removed global symbols — this is a pure file split.

```bash
git add src/drivers-i386/bus/drvPExpert
git commit -m "pexpert: split memory sizing out of i386_init"
```

---

### Task 7: Boot info, PCI configuration access, and BIOS32

**Files:**
- Create: `src/drivers-i386/bus/drvPExpert/i386/bootinfo.c`, `bootinfo.h`
- Create: `src/drivers-i386/bus/drvPExpert/i386/chips/pcicfg.c`, `chips/pcicfg.h`
- Create: `src/drivers-i386/bus/drvPExpert/i386/chips/bios32.c`, `chips/bios32.h`
- Create: `src/drivers-i386/bus/drvPExpert/i386/pci_config.c`

**Interfaces:**
- `bootinfo.h`: `void bootinfo_collect(void);` — reads `KERNBOOTSTRUCT`'s `eisaSlotInfo`, the `EISA_func_info_t` array and `PCI_bus_info_t`, copies them into the arena, and sets `i386_firmware_info.eisa_present`, `eisa_slots`, `pci_config_mechanism` and `pci_last_bus`.
- `chips/pcicfg.h`: `extern const pci_config_ops_t pcicfg_mech1_ops;` and `pcicfg_mech2_ops`. `int pcicfg_probe_mechanism(void);` returning 1, 2 or 0.
- `chips/bios32.h`: `void bios32_scan(void);` — finds the BIOS32 service directory and the PCI BIOS entry and publishes both in `i386_firmware_info`.
- `pci_config.c`: `extern const pci_config_ops_t *i386_pci_config_ops;` — set by `bios32_scan()`/`pcicfg_probe_mechanism()` to whichever ops set won.
- `pci_config.c`: defines `pci_config_ops_t` (in `pexpert_i386.h`), the `pexpert_pci_config_read`/`write` wrappers, and the `i386_pci_config_ops` pointer they dispatch through.

- [ ] **Step 1: Add pci_config_ops_t to the public header**

Insert into `src/kernel-7/machdep/i386/pexpert_i386.h`, above the `pexpert_pci_config_read` declarations:

```c
typedef struct pci_config_ops {
    const char	*name;			/* "mechanism 1", "mechanism 2", "BIOS32" */
    int		(*read)(int bus, int dev, int fn, int off,
			int size, unsigned int *val);
    int		(*write)(int bus, int dev, int fn, int off,
			 int size, unsigned int val);
    int		last_bus;
} pci_config_ops_t;
```

- [ ] **Step 2: Write bootinfo.c**

Read `src/boot-2/i386/boot2/boot.c:347-371` and `src/kernel-7/machdep/i386/kernBootStruct.h` first, so the field names and the `EISA_CONFIG_ADDR` layout match what the booter actually writes.

Treat every field as **advisory**: if `EISA_SUPPORT` was compiled out of the booter, the EISA fields are zero, which means *unknown*, not *no EISA hardware*. Set `eisa_present` only from a positive slot-ID probe in Task 9's discovery order, never from a zero boot-struct field alone.

This replaces `drvEISABus`'s reads at the hardcoded `EISA_SLOT_DATA_ADDR` / `EISA_CONFIG_DATA_ADDR` addresses (`eisa.c:40,42`), an implicit booter-to-driver contract that nothing versions.

- [ ] **Step 3: Write chips/pcicfg.c**

Implement configuration mechanism #1 (`0xCF8` address, `0xCFC` data) and mechanism #2 (`0xCF8` enable, `0xCFA` forward, `0xC000`-based). Model the probe on `src/boot-2/i386/libsaio/pci.c` `testMethod1` and `testMethod2` — the booter already does exactly this probe, so reproduce its logic rather than a different one, and have `bootinfo_collect()`'s value be the hint that `pcicfg_probe_mechanism()` confirms.

Support `size` of 1, 2 and 4 bytes in both `read` and `write`; return -1 for any other size, for `bus > last_bus`, for `dev > 31` or `fn > 7`.

- [ ] **Step 4: Write chips/bios32.c**

Scan `0xE0000`–`0xFFFFF` on 16-byte boundaries for the `_32_` signature, validate the byte-sum, copy the service directory into the arena, publish it as `i386_firmware_info.bios32`, then query it for the PCI BIOS service (`$PCI`) and publish that as `pci_bios`. Build the real-mode calls on the platform expert's own `bios32()` thunk from Phase 1 — do not add a second thunk.

- [ ] **Step 5: Write pci_config.c**

```c
#import <machdep/i386/pexpert_i386.h>

#import "chips/pcicfg.h"

const pci_config_ops_t	*i386_pci_config_ops;

int
pexpert_pci_config_read(int bus, int dev, int fn, int off,
			int size, unsigned int *val)
{
    if (i386_pci_config_ops == 0 || val == 0)
	return (-1);

    return ((*i386_pci_config_ops->read)(bus, dev, fn, off, size, val));
}

int
pexpert_pci_config_write(int bus, int dev, int fn, int off,
			 int size, unsigned int val)
{
    if (i386_pci_config_ops == 0)
	return (-1);

    return ((*i386_pci_config_ops->write)(bus, dev, fn, off, size, val));
}
```

- [ ] **Step 6: Build, boot gate, commit**

The gate here is that the kernel still boots and `drvPCIBus` still finds devices through its own unmodified `pci.c` — nothing consumes the new service until Phase 4.

```bash
git add src/kernel-7/machdep/i386/pexpert_i386.h src/drivers-i386/bus/drvPExpert
git commit -m "pexpert: add boot-info collection and a unified PCI config service"
```

---

### Task 8: The firmware table scan

**Files:**
- Create: `src/drivers-i386/bus/drvPExpert/i386/firmware_scan.c`, `firmware_scan.h`

**Interfaces:**
- `void firmware_scan(void);` — populates every remaining pointer field in `i386_firmware_info`.

- [ ] **Step 1: Implement the scan**

Search order and regions, all validated by the Task 2 and 3 parsers before anything is copied into the arena:

- **ACPI RSDP** — the first 1 KB of the EBDA (whose segment is at `0x40E`), then `0xE0000`–`0xFFFFF`, on 16-byte boundaries. On a hit, follow `RsdtAddress` to the RSDT, walk its entry array and copy MADT (`APIC`), FADT (`FACP`) and HPET (`HPET`) if present. If revision ≥ 2, prefer `XsdtAddress`.
- **MP Floating Pointer** — the first KB of the EBDA, the last KB of base memory, then `0xF0000`–`0xFFFFF`. On a hit, follow to the `PCMP` configuration table.
- **`$PIR`** — `0xF0000`–`0xFFFFF` on 16-byte boundaries.
- **`$PnP`** — `0xF0000`–`0xFFFFF` on 16-byte boundaries.

Copy each validated table into the arena with `pexpert_arena_copy()`. **A `NULL` return publishes the field as `NULL`**; never publish a partial copy. Call `pexpert_arena_report()` once at the end.

- [ ] **Step 2: Boot gate**

Boot and confirm the arena report prints. On the QEMU guest, expect ACPI RSDP and `$PIR` to be found and MP tables to be present or absent depending on the QEMU version — record whichever it is in the commit message as the observed guest baseline.

- [ ] **Step 3: Commit**

```bash
git add src/drivers-i386/bus/drvPExpert
git commit -m "pexpert: scan and cache MP, \$PIR, \$PnP and ACPI static tables"
```

---

### Task 9: ISA Plug and Play, PnP BIOS, family selection, and the property dump

**Files:**
- Create: `src/drivers-i386/bus/drvPExpert/i386/chips/isapnp.c`, `chips/isapnp.h`
- Create: `src/drivers-i386/bus/drvPExpert/i386/pnpbios.c`, `pnpbios.h`
- Create: `src/drivers-i386/bus/drvPExpert/i386/families/atpc.c`, `atpc.h`
- Create: `src/drivers-i386/bus/drvPExpert/i386/families/pcipc.c`, `pcipc.h`
- Create: `src/drivers-i386/bus/drvPExpert/i386/families/acpipc.c`, `acpipc.h`
- Modify: `src/drivers-i386/bus/drvPExpert/i386/identify_machine.c` (add `i386_identify()`)
- Modify: `src/drivers-i386/bus/drvPExpert/i386/i386_init.c` (call `i386_identify()` before `pmap_bootstrap`)

**Interfaces:**
- Produces `i386_init_t` in `pexpert_i386.h`:

```c
typedef struct i386_init {
    const char			*name;
    void			(*configure_machine)(void);
    void			(*initialize_interrupts)(void);
    void			(*initialize_rtclock)(void);
    void			(*initialize_processors)(void);
    const pci_config_ops_t	*pci_config;
} i386_init_t;

extern i386_init_t	*i386_init_p;
```

`initialize_rtclock` returns `void`, not `int` as the design spec and the ppc `powermac_init_t` have it: the i386 implementation is `machine_clock_init()`, which returns `void`. Do not add a return value it does not have.

- Produces, in `chips/isapnp.h`: `int isapnp_isolate(void);` — runs the initiation key and isolation protocol, assigns CSNs, and returns the number of cards found.
- Produces, in `pnpbios.h`: `int pnpbios_enumerate(void);` — walks PnP BIOS device nodes, returning the count.
- Produces, in `identify_machine.c`: `void i386_identify(void);` and `void i386_display_platform(void);`
- Produces, in `families/*.h`: `extern i386_init_t atpc_init, pcipc_init, acpipc_init;`

- [ ] **Step 1: Implement chips/isapnp.c behind a boot argument**

Implement the ISA PnP protocol: the 32-byte initiation key LFSR, relocatable read-port selection, `isolateCard`, CSN assignment, logical-device select, and configuration register read/write. Read `drvEISABus/…/bios.c:189,257,279` (`readIsolationBit`, `computeChecksum`, `isolateCard`) and `EISAKernBus+PlugAndPlay.m:74-94` first and reproduce the protocol they implement — this is one implementation replacing both.

**Gate the isolation pass behind a boot argument.** Add `isapnp` to the `kernargs` table in `i386_init.c` with a default of 0, and have discovery step 5 run only when it is non-zero:

```c
    if (isapnp_enable)
	i386_firmware_info.isapnp_cards = isapnp_isolate();
    else
	i386_firmware_info.isapnp_cards = 0;
```

The default is off deliberately. Moving isolation from `drvEISABus` load time to early boot changes when cards receive CSNs, and **QEMU has no ISA PnP cards, so the available harness cannot test this path.** It must be validated on real hardware with `isapnp=1` before the default flips.

- [ ] **Step 2: Implement pnpbios.c**

Use the `$PnP` installation-check structure published by Task 8, and the Phase 1 `bios32()` thunk, to enumerate PnP BIOS device nodes. Feed each node's resource data to `pnp_resource_parse()` from Task 4. This replaces `drvEISABus/…/bios.c:56` (`call_pnp_bios`) — one thunk, not two.

- [ ] **Step 3: Write the three families**

Each is a struct literal reusing shared function pointers, following `families/gossamer.c` in the ppc project. `atpc.c`:

```c
#import <machdep/i386/pexpert_i386.h>

#import "atpc.h"
#import "../chips/i8259.h"

extern void	i386_configure_machine(void);
extern void	intr_initialize(void);
extern int	machine_clock_init(void);
extern void	NO_ENTRY(void);

i386_init_t atpc_init = {
    "PC/AT",
    i386_configure_machine,	/* configure_machine     */
    intr_initialize,		/* initialize_interrupts */
    machine_clock_init,		/* initialize_rtclock    */
    NO_ENTRY,			/* initialize_processors */
    0,				/* no PCI                */
};
```

`pcipc.c` and `acpipc.c` are identical except for `name` and for `pci_config`, which is set from `i386_pci_config_ops` at selection time rather than statically. Add `void NO_ENTRY(void) { }` to `i386_init.c`, mirroring `powermac_init.c:435`.

- [ ] **Step 4: Write i386_identify() and wire it into the boot sequence**

In `identify_machine.c`:

```c
void
i386_identify(void)
{
    i386_identify_cpu();
    i386_platform_info.hypervisor = i386_identify_hypervisor();

    bootinfo_collect();

    i386_firmware_info.pci_config_mechanism = pcicfg_probe_mechanism();
    bios32_scan();

    firmware_scan();

    if (isapnp_enable)
	i386_firmware_info.isapnp_cards = isapnp_isolate();

    if (i386_firmware_info.pci_config_mechanism == 0) {
	i386_platform_info.class = I386_CLASS_ATPC;
	i386_init_p = &atpc_init;
    } else if (i386_firmware_info.acpi_rsdp != 0) {
	i386_platform_info.class = I386_CLASS_ACPIPC;
	i386_init_p = &acpipc_init;
	acpipc_init.pci_config = i386_pci_config_ops;
    } else {
	i386_platform_info.class = I386_CLASS_PCIPC;
	i386_init_p = &pcipc_init;
	pcipc_init.pci_config = i386_pci_config_ops;
    }

    i386_display_platform();
}
```

In `i386_init()`, call `i386_identify()` immediately after `i386_configure_machine()` and **before** `intr_initialize()` and `pmap_bootstrap()`. The arena copies must happen while low memory is plainly reachable.

- [ ] **Step 5: Write the property dump**

`i386_display_platform()` prints, in the style of `powermac_init.c`'s `display_machine_class` / `display_machine_info`:

```
PExpert: Intel PCI PC class machine (hypervisor: QEMU)
PExpert: CPU GenuineIntel family 6 model 6 stepping 3, reported as 586
PExpert: PCI config mechanism 1, buses 0..0
PExpert: ACPI RSDP found; MADT yes FADT yes HPET no
PExpert: MP FPS not found; $PIR found; $PnP not found
PExpert: EISA not present; ISA PnP disabled (isapnp=1 to enable)
PExpert: discovery arena 1284/8192 bytes used
```

This dump is the Phase 3 verification oracle — it is how a reviewer confirms discovery works without a debugger.

- [ ] **Step 6: Boot gate**

Boot on the QEMU guest and compare the dump against expectations: `I386_CLASS_ACPIPC`, hypervisor QEMU or none depending on whether the guest runs KVM or TCG, PCI mechanism 1, ACPI RSDP found, EISA absent, ISA PnP disabled.

**If the class comes out `ATPC`,** PCI mechanism probing failed — check Task 7 Step 3 against `libsaio/pci.c` `testMethod1` rather than adjusting the family selection.

- [ ] **Step 7: Commit**

```bash
git add src/kernel-7/machdep/i386/pexpert_i386.h src/drivers-i386/bus/drvPExpert
git commit -m "pexpert: add ISA PnP, PnP BIOS, family selection and a boot property dump

ISA PnP isolation defaults off pending real-hardware validation."
```

---

### Task 10: Update the boot documentation

**Files:**
- Modify: `docs/boot/boot-i386.md`

- [ ] **Step 1: Document the discovery step in the early-boot trace**

Add to "Architecture entry and early machine setup", after the `i386_init()` paragraph:

```markdown
`i386_init()` calls `i386_identify()` before `pmap_bootstrap()`. Discovery reads CPUID, the boot struct's EISA and PCI fields, the PCI configuration mechanism, BIOS32, and then scans for the MP Floating Pointer, `$PIR`, `$PnP` and the ACPI RSDP, copying each validated table into an 8 KB platform-expert arena. It then selects one of three platform families — `atpc`, `pcipc`, `acpipc` — and publishes `i386_init_p`. Nothing acts on the MP or MADT tables yet; they are discovered and published only. **Source anchor:** `src/drivers-i386/bus/drvPExpert/i386/identify_machine.c` `i386_identify()`; `src/drivers-i386/bus/drvPExpert/i386/firmware_scan.c`; `src/kernel-7/machdep/i386/pexpert_i386.h`.
```

- [ ] **Step 2: Commit**

```bash
git add docs/boot/boot-i386.md
git commit -m "docs: record platform expert discovery in the i386 boot trace"
```

---

## Phase 3 exit criteria

1. `gnumake test` in `src/drivers-i386/bus/drvPExpert/tests` passes with zero failures, covering the ACPI, MP, `$PIR`, EISA-ID and PnP-resource parsers.
2. The kernel boots to login and prints the platform property dump.
3. On the QEMU guest the dump reports class `ACPI PC`, PCI config mechanism 1, ACPI RSDP found, EISA absent, ISA PnP disabled.
4. `machine_slot[0].cpu_subtype` is still `CPU_SUBTYPE_586` and `cpu_model` is still `"586"`.
5. The arena reports no refused copies.
6. `drvPCIBus`, `drvEISABus` and `drvPCMCIABus` are still unmodified and still working — nothing consumes the new services until Phase 4.

## Known gap carried into Phase 4

**ISA PnP isolation is untested.** It defaults off (`isapnp=1` enables it) because QEMU has no ISA PnP cards. Phase 4's `drvEISABus` rehosting depends on this code path, so it must be validated on real hardware before that rehosting can be trusted, even though it will build and link without it.
