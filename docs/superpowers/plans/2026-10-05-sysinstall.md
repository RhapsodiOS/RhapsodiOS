# sysinstall (install-media phase 5a) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Milestone B: the phase 4 media, now starting the curses
installer `sysinstall`, installs onto a blank disk that then boots alone
under SeaBIOS and IA32 UEFI to `login:` and accepts SSH with the password
chosen during install.

**Architecture:**
- `sysinstall` is one C program in `src/cdis-3/sysinstall.tproj`. Its pure
  logic (layout, sets, config, write-phase step runner) is in curses-free
  files with host unit tests, and its screens sit on `Libcurses-1`.
- `driverDetect` is a sibling of `driverLoader` in `src/driverkit-3`, with
  its ID matching in a host-testable file.
- `vm/instmedia` learns the set files and the media's generic boot drivers.

**Tech Stack:** C (gnu89; `cc` on the Rhapsody guest, clang on the Windows
host for tests), 4.4BSD curses, DriverKit's `driverServer.h` RPCs, Python
3.13 for `vm/instmedia`, QEMU via `vm/qemu_boot.py`.

**Spec:** `docs/superpowers/specs/2026-10-05-sysinstall-design.md`
(phase 5a of `docs/superpowers/specs/2026-09-22-install-media-design.md`;
phase 4's record is `docs/build/instmedia-live.md`).

## Global Constraints

- English only. No `.lproj` other than `English.lproj` remains in `cdis-3`.
- Root filesystem UFS only; target layout: ESP `0xEF` at LBA 2048 for
  131072 sectors, `0xA7` active from LBA 133120 to the last whole cylinder
  of the LBA-assisted geometry.
- LBA-assisted geometry: `spt` 63; heads 255 above 63×255×1024 sectors,
  else 255/128/64/32/16 by `(sectors/63)/1024` > 128/64/32/16; CHS past
  cylinder 1023 is 1023/254/63. Must equal `vm/build_uefi_image.py`'s
  `lba_assist_geometry` and `chs`.
- Disks under 1 GB are refused. The ESP image must be exactly 131072
  sectors.
- The target is mounted at `/private/var/tmp/mnta`; `I` =
  `/System/Installation`; set files live in `I/Sets/*.set`.
- Every menu answers to a digit or letter, so `qemu_boot.py --type`
  (letters, digits, `"-_=` space `/` `.`, Enter only) can drive it.
- Media Boot Drivers: `EISABus PCIBus PS2Keyboard EIDE AHCI ISASerialPort`;
  media Active Drivers: `VGA`.
- Installed `Boot Drivers`: `EISABus PCIBus PS2Keyboard` plus the chosen
  disk controller; installed `Active Drivers`: chosen network, display and
  audio drivers, the input drivers, and `BPF`.
- `driverDetect` lives at `/usr/sbin/driverDetect`; commands `driverDetect`,
  `-l <family…>`, `-w <root> <driver…>`.
- PCI enumeration goes through device `"PCI0"` with
  `"PCI_Maximums("` and `"PCI_ConfigReg(Dev:%d Func:%d Bus:%d Reg:%d)"`
  via `_IOLookupByDeviceName` / `_IOGetCharValues` (`driverkit/driverServer.h`).
- Probes use `_IOProbeDriver(device_master_self(), data, size)`, which
  takes the table text in memory.
- CLAUDE.md: commit subjects start with a subsystem prefix, short, no
  metadata; check legacy files for Mac-Roman bytes before editing; boot
  tests only on temporary images; never write or delete
  `vm/work/rhap-i386-bootstrapped.img`; quit guests via QMP `quit`.

## Review Focus

1. **A disk that already has partitions** chosen for **Auto**: everything,
   including the old label area, must be overwritten so `disk -i` sees only
   the new table. Task 2: `test_auto_ignores_an_existing_table`.
2. **A disk whose size isn't a whole number of cylinders:** the `0xA7`
   entry ends on the last whole cylinder, never past the disk. Task 2:
   `test_auto_rounds_down_to_a_whole_cylinder` (1 GB + 1000 sectors).
3. **A set naming a package twice, or two sets sharing a package:** each
   apk is passed to `apk add` once. Task 3:
   `test_union_lists_each_package_once`.
4. **A password with characters `crypt()` salts can't hold, or longer than
   8 characters:** the hash uses only the first 8, the salt only
   `[./0-9A-Za-z]`. Task 3: `test_salt_alphabet_and_eight_char_limit`.
5. **Two cards matched by one driver, or a driver with no `Auto Detect
   IDs`:** two matches give `Instance0`/`Instance1` tables; a driver without
   IDs is never "detected". Task 4: `test_two_cards_one_driver` and
   `test_driver_without_ids_never_matches`.

---

## File structure

| File | Job |
|---|---|
| `src/cdis-3/sysinstall.tproj/{Makefile,PB.project,Makefile.preamble,Makefile.postamble}` | Tool project, copied from `gc.tproj`; `LIBS = -lcurses` |
| `src/cdis-3/sysinstall.tproj/layout.{c,h}` | Geometry, CHS, Auto layout, Advanced rules, MBR encode/decode |
| `src/cdis-3/sysinstall.tproj/sets.{c,h}` | Parse `*.set`; union of chosen sets |
| `src/cdis-3/sysinstall.tproj/config.{c,h}` | Template rendering, `master.passwd` edit, salt |
| `src/cdis-3/sysinstall.tproj/steps.{c,h}` | Write-phase command list and runner (runner injected) |
| `src/cdis-3/sysinstall.tproj/disks.{c,h}` | Candidate disks (Rhapsody-only; no host test) |
| `src/cdis-3/sysinstall.tproj/ui.{c,h}`, `main.c` | Curses widgets and the screen sequence |
| `src/cdis-3/sysinstall.tproj/tests/{Makefile,*_test.c}` | Host tests (clang), pattern of `src/bootefi-1/tests/Makefile` |
| `src/cdis-3/sets/base.set` | The base set |
| `src/driverkit-3/driverDetect/{Makefile,driverDetect.c,match.c,match.h,driverDetect.8}` | The tool; `match.c` is host-tested |
| `src/driverkit-3/driverDetect/tests/{Makefile,match_test.c}` | Host tests |
| `vm/instmedia/{live,build,test_live,test_build}.py` | Media boot drivers, set checks, set-driven `Packages` |

---

### Task 1: Spike the three risks on a guest (controller)

**Files:** none in the repo. Scratch C and scripts in the session scratchpad.
Ledger the results; each failed risk becomes a ruling before Task 2.

- [ ] **Step 1: Boot a private guest** from `vm/work/rhap-i386-bootstrapped.img`
  with `-snapshot`, a blank 2 GB raw `hd1` (temporary file), and
  `-device ne2k_pci` (recipes: memories *Private QEMU guest from the
  bootstrapped image* and *i386 guest driver load testing*). NE2K must not
  be in the guest's Boot or Active Drivers.

- [ ] **Step 2: Risk 1, probe from memory.** Compile on the guest a C
  program that does `kl_com_add("/usr/Devices/NE2K.config/NE2K_reloc",
  "NE2K")`, builds NE2K's `Default.table` text in memory with
  `"Location" = "Dev:%d Func:0 Bus:0"` (slot from QEMU's `info pci`),
  `kl_com_load` with its Server Name, then `_IOProbeDriver(device_master_self(),
  buf, len)` — linking `kl_com.m`'s logic as driverLoader does (or by
  copying `kl_com.m` and building with `cc -ObjC`). Also run a
  `PCI0`/`PCI_ConfigReg` scan printing each `vendor|device<<16`.
  **Pass:** the scan lists `0x802910ec`; after the probe, `ifconfig en0`
  exists. **Fail:** ledger the error; fallback ruling is `-l` writing the
  table to `/private/tmp` of the *target* is impossible before the disk
  screen, so SCSI-at-start would be dropped and network loaded after mount.

- [ ] **Step 3: Risk 3, MBR + ESP + label without reboot.** On the guest:
  write sector 0 of `/dev/rhd1h` with `boot0`'s first 446 bytes, the Auto
  table for 2 GB (values in Task 2) and `0x55AA` (a perl one-liner or the
  scratch C); write 131072 zero sectors at LBA 2048 (stand-in ESP); run
  `disk -i -b /dev/rhd1h`; `mount /dev/hd1a /mnt`; `touch /mnt/x`; `umount`.
  **Pass:** `disk` prints "Rhapsody partition base = 133120", newfs runs,
  mount works. Read `hd1` back on the host with `rhap_image` to confirm the
  UFS sits at 133120 + 320.

- [ ] **Step 4: Risk 2, the same under UEFI.** Boot the same guest image
  through `qemu_boot.py uefi … --esp <ESP image> --hd1 <blank>` (phase 1's
  two-disk layout; ESP from `instmedia.hdimage.esp_image`) and repeat Step
  3. **Pass:** as Step 3. **Fail:** read `disk.c`'s geometry path, rule on
  a fix (e.g. `disk -i` taking geometry from the label when `diskInfo` is
  zero), and add it as a task before Task 7.

- [ ] **Step 5: Ledger** `Task 1: risk N PASS|FAIL …` with log paths, and
  quit the guest via QMP.

### Task 2: `layout.c` — geometry, Auto, Advanced rules, MBR

**Files:**
- Create: `src/cdis-3/sysinstall.tproj/layout.{c,h}`, `src/cdis-3/sysinstall.tproj/tests/{Makefile,layout_test.c}`

**Interfaces — Produces:**
```c
#define ESP_LBA      2048u
#define ESP_SECTORS  131072u
#define A7_LBA       133120u
struct part { unsigned char type, active; unsigned long start, count; };
struct table { struct part p[4]; };
void lba_geometry(unsigned long total, unsigned *heads, unsigned *spt);
void lba_to_chs(unsigned long lba, unsigned heads, unsigned spt, unsigned char out[3]);
int  layout_auto(unsigned long total, struct table *t);      /* 0, or -1 if < 1 GB */
const char *layout_check(unsigned long total, const struct table *t); /* NULL = ok, else reason */
void mbr_encode(const unsigned char boot0[446], unsigned long total, const struct table *t, unsigned char out[512]);
int  mbr_decode(const unsigned char in[512], struct table *t); /* -1 without 0x55AA */
```

- [ ] **Step 1: Write the failing tests** in `layout_test.c` (a tiny
  `CHECK(cond)` macro counting failures; `main` returns non-zero on any):
  - `test_geometry_matches_build_uefi_image`: totals 2097152, 4194304,
    8388608, 16777216 give heads 32, 128, 255, 255 (spt 63).
  - `test_chs_matches_build_uefi_image`: for 2 GB (128/63), LBA 2048 →
    `{0x20,0x21,0x00}`, LBA 133119 → `{0x41,0x01,0x10}`, LBA 133120 →
    `{0x41,0x02,0x10}`, LBA 4193279 → `{0x7f,0xbf,0x07}`; for 8 GB, LBA
    16771859 → `{0xfe,0xff,0xff}`.
  - `test_auto_2gb`: entries ESP `0xEF` 2048/131072 inactive, `0xA7`
    133120/4060160 active, others empty.
  - `test_auto_rounds_down_to_a_whole_cylinder`: total 2097152+1000 →
    `0xA7` count 1963520.
  - `test_auto_refuses_under_1gb`: 2097151 → -1.
  - `test_auto_ignores_an_existing_table`: decode an MBR holding a FAT
    entry, run `layout_auto`, encode: only the two new entries remain.
  - `test_check_rules`: refused, each with a non-NULL reason: no `0xA7`;
    two `0xA7`; `0xA7` not active; ESP of 131071 sectors; overlap;
    `0xA7` end not on a cylinder; entry past the disk. Accepted: the Auto
    table plus a third `0x07` entry in free space.
  - `test_mbr_roundtrip`: encode then decode gives the same table; bytes
    446..509 hold the entries with CHS from `lba_to_chs`, 510..511 are
    `0x55 0xAA`, 0..445 are `boot0`.

- [ ] **Step 2: Run** `cd src/cdis-3/sysinstall.tproj/tests && make test-layout`
  (Makefile modelled on `src/bootefi-1/tests/Makefile`: `CC := clang` when
  default, `-std=gnu89 -g -O0 -Wall -Werror -I..`, binaries in `BUILD/`).
  Expected: compile error (no `layout.h`).

- [ ] **Step 3: Implement `layout.c`.** Geometry and CHS per Global
  Constraints; Auto sets the `0xA7` count to
  `(total / (heads*spt)) * heads*spt - A7_LBA`.

- [ ] **Step 4: Run** `make test-layout`. Expected: `layout: 0 failures`.

- [ ] **Step 5: Commit** `cdis: add sysinstall's disk layout and MBR code, with host tests`.

### Task 3: `sets.c`, `config.c` and `base.set`

**Files:**
- Create: `src/cdis-3/sysinstall.tproj/{sets,config}.{c,h}`, `tests/{sets_test,config_test}.c`, `src/cdis-3/sets/base.set`

**Interfaces — Produces:**
```c
struct set { char name[32], title[64], desc[128]; int required; char **pkgs; int npkgs; };
int  set_parse(const char *name, const char *text, struct set *s);  /* 0 or -1 */
int  set_union(const struct set *sets, const int *chosen, int n, char ***out); /* count; "files" first */
char *render(const char *tmpl, const char *disk);                   /* @DISK@ -> disk; malloc'd */
char *passwd_set_root(const char *passwd, const char *hash);        /* NULL if no root line */
void make_salt(unsigned seed, char out[3]);
```
`set_parse` keywords: `title`, `description`, `required` (`yes`/`no`),
then package names; `#` lines and blank lines ignored.

- [ ] **Step 1: Write the failing tests:**
  - `test_parse_base_set`: parse the real `../../sets/base.set`: title
    `Base system`, required, first package `files`, contains `driverkit`
    and `libcurses`.
  - `test_union_lists_each_package_once`: sets {a,b,files} and {b,c} →
    `files,a,b,c`.
  - `test_render`: `"/dev/@DISK@a\t/\tufs\trw\t\t1  1\n"` with `hd0` →
    `/dev/hd0a…`, matching `templates/fstab` rendered the same way.
  - `test_passwd_set_root`: same cases as `vm/instmedia/test_live.py`'s
    `test_render_and_password` (root line replaced, nobody kept, no-root →
    NULL).
  - `test_salt_alphabet_and_eight_char_limit`: 1000 seeds give only
    `[./0-9A-Za-z]`; on the host, skip the `crypt()` half (guest-only,
    checked in Task 10).

- [ ] **Step 2: Run** `make test-sets test-config`. Expected: compile errors.

- [ ] **Step 3: Write `base.set`** — header from the spec, then every
  package phase 4's `p4-repo7` media carried (`ls vm/work/p4-apks` plus the
  image's universal apks, minus `-hdrs`/`-obj`; the list is the 65 package
  names `instmedia.apkrepo.index` returns, plus `driverkit`, `libcurses`),
  sorted, `files` first. Then implement `sets.c` and `config.c`.

- [ ] **Step 4: Run** `make test-sets test-config`. Expected: 0 failures.

- [ ] **Step 5: Commit** `cdis: add sysinstall's set files, template rendering and password edit`.

### Task 4: `driverDetect`'s matching

**Files:**
- Create: `src/driverkit-3/driverDetect/match.{c,h}`, `tests/{Makefile,match_test.c}`

**Interfaces — Produces:**
```c
struct pcidev { unsigned dev, func, bus; unsigned long pid, sid; };  /* pid = reg 0x00, sid = reg 0x2c */
int  ids_match(const char *autoDetectIDs, unsigned long pid, unsigned long sid); /* boot-2 testIDs rules */
int  table_value(const char *table, const char *key, char *out, int outlen);    /* "key" = "value"; */
struct match { char driver[64], family[32]; struct pcidev d; int instance; };
int  match_all(const char **tables, const char **names, int ntables,
               const struct pcidev *devs, int ndevs, struct match *out, int max);
int  write_location(const char *table, const struct pcidev *d, char **out);     /* sets "Location" */
```
`ids_match` reproduces `src/boot-2/i386/libsaio/drivers.c:319-363`
exactly (vendor 0 or 0xffff never matches; `ID`, `ID&mask`, `ID:SID`,
`ID&m:SID&m`, leading `:` reuses the previous primary). `match_all` uses
only tables whose `"Bus Type"` is `"PCI"`; instances count per driver from 0.

- [ ] **Step 1: Write the failing tests:**
  - `test_ids_forms`: plain, mask, secondary, leading-colon, vendor 0xffff.
  - `test_real_tables`: read `src/drivers-i386/network/drvNE2k/NE2K.drvproj/Default.table`
    and `ide/drvAHCI/AHCI.drvproj/Default.table`: pid `0x802910ec` matches
    NE2K (family `Network`), `0x29228086` matches AHCI.
  - `test_two_cards_one_driver`: two NE2K devices → instances 0 and 1.
  - `test_driver_without_ids_never_matches`: VGA's table matches nothing.
  - `test_write_location`: `"Location" = "";` becomes
    `"Location" = "Dev:3 Func:0 Bus:0";`; a table with no Location key gets
    one appended.

- [ ] **Step 2: Run** `cd src/driverkit-3/driverDetect/tests && make test`.
  Expected: compile error.

- [ ] **Step 3: Implement `match.c`.** Check `Default.table` files touched
  by the test for Mac-Roman bytes only if editing them (they're read-only here).

- [ ] **Step 4: Run** `make test`. Expected: `match: 0 failures`.

- [ ] **Step 5: Commit** `driverkit: add driverDetect's PCI ID matching, with host tests`.

### Task 5: The `driverDetect` tool

**Files:**
- Create: `src/driverkit-3/driverDetect/{Makefile,driverDetect.c,driverDetect.8}` (+ `kl_com.m`/`kl_com.h` reused from `../driverLoader` by path in the Makefile)
- Modify: `src/driverkit-3/Makefile:5,11` (add `driverDetect` to `SUBDIR` and `INSTALL_SUBDIR`)

**Interfaces — Consumes:** Task 4's `match.h`; `kl_com_add/kl_com_load`;
`_IOLookupByDeviceName`, `_IOGetCharValues`, `_IOProbeDriver`,
`device_master_self()`.
**Produces:** the command line in Global Constraints. Output of the list
mode, one line per match, tab-separated:
`<family>\t<driver>\tDev:%d Func:%d Bus:%d\t0x%08lx`. `-w` writes
`<root>/private/Drivers/i386/System.config/Instance0.table` from
`<root>/System/Installation/CDIS/templates/Instance0-i386.table` if present,
else from `/System/Installation/CDIS/templates/…`, setting `Boot Drivers`
and `Active Drivers` per Global Constraints, and
`<root>/private/Drivers/i386/<drv>.config/Instance<N>.table` for each chosen
PCI driver via `write_location`. Exit 0 on success, 1 with a message on
stderr otherwise.

- [ ] **Step 1:** Copy `driverLoader/Makefile`'s shape (`PROGRAM=driverDetect`,
  `BINDIR=/usr/sbin`, `CFILES=driverDetect.c match.c`, `MFILES=../driverLoader/kl_com.m`,
  same `LIBS`), write the tool and its man page.
- [ ] **Step 2: Build on the guest** with `rbuild kernel` (driverkit is built
  by the kernel run; memory *i386 kernel build on bootstrapped guest*), fetch
  the `driverkit` apk, and check it carries `usr/sbin/driverDetect`.
- [ ] **Step 3: Guest check** on the Task 1 guest setup: `driverDetect` lists
  `Network\tNE2K\tDev:… Func:0 Bus:0\t0x802910ec`; `driverDetect -l Network`
  brings up `en0`; `driverDetect -w /mnt NE2K` on a scratch UFS writes both
  tables (cat them). Ledger the output.
- [ ] **Step 4: Commit** `driverkit: add driverDetect, which lists, loads and records the drivers for the machine's PCI devices`.

### Task 6: `steps.c` and `disks.c`

**Files:**
- Create: `src/cdis-3/sysinstall.tproj/{steps,disks}.{c,h}`, `tests/steps_test.c`

**Interfaces — Produces:**
```c
struct plan { char disk[8]; struct table t; const char *pw_hash; char **pkgs; int npkgs;
              char **drivers; int ndrivers; };
typedef int (*runner)(const char *argv0, char *const argv[], void *ctx); /* exit status */
int steps_run(const struct plan *p, runner run, void (*progress)(int step, const char *what),
              char *failed_cmd, int len);         /* 0, or the failed step number */
int disks_list(char names[][8], unsigned long sizes[], int max); /* skips the live root's disk */
```
`steps_run` performs the spec's *Write phase* 1–9 in order. Steps 1–2 and
the file writes in 6 go through small file-I/O helpers taking the target
root as a parameter so the test points them at a temp directory; every
external command goes through `run`.

- [ ] **Step 1: Write the failing test** `test_command_order_and_stop_on_failure`:
  a fake runner records argv; for `hd0` with two packages the recorded
  commands are, in order: `disk -i -b /dev/rhd0h`, `mount /dev/hd0a
  /private/var/tmp/mnta`, `apk add --root … --initdb …/files-*.apk`,
  `apk add --root …` with the rest, `chroot … /usr/sbin/pwd_mkdb -p
  /etc/master.passwd`, `/usr/sbin/driverDetect -w … <drivers>`, `umount`,
  `sync`; making the `mount` call fail returns step 4 and runs nothing
  after it. Plus `test_refuses_a_live_rc_cdrom` (step 8).
- [ ] **Step 2: Run** `make test-steps`. Expected: compile error.
- [ ] **Step 3: Implement** `steps.c` (MBR via Task 2's `mbr_encode`; ESP
  via `popen("gzip -dc …")` with a 131072-sector check) and `disks.c`
  (`DKIOCNUMBLKS` on `/dev/rhd0-3h`, `/dev/rsd0-7h`; no host test).
- [ ] **Step 4: Run** `make test`. Expected: all suites 0 failures.
- [ ] **Step 5: Commit** `cdis: add sysinstall's write phase and disk discovery`.

### Task 7: Screens, the tool project, and the `cdis-3` cleanup

**Files:**
- Create: `src/cdis-3/sysinstall.tproj/{ui.c,ui.h,main.c,Makefile,PB.project,Makefile.preamble,Makefile.postamble}`
- Modify: `src/cdis-3/Makefile` (`TOOLS` += `sysinstall.tproj`; `GLOBAL_RESOURCES` drop `French.lproj German.lproj Italian.lproj Spanish.lproj Swedish.lproj`; `OTHERSRCS` drop `rc.cdrom.PPC rc.cdrom.x86`), `src/cdis-3/PB.project` (same), `src/cdis-3/Makefile.postamble` (drop `SCRIPT2`/`SCRIPT3` and their installs and the three `.lproj` `rm` lines; install `sets/*.set` to `$(DSTROOT)/System/Installation/Sets`), `src/cdis-3/rc.cdrom` (hook only), `src/cdis-3/mkinstallcd.sh:201-214` (English only, no `rc.cdrom.*`), `src/cdis-3/apk/pkginfo` (`makedepends` += `libcurses`)
- Delete: `src/cdis-3/{French,German,Italian,Spanish,Swedish}.lproj`, `src/cdis-3/rc.cdrom.x86`, `src/cdis-3/rc.cdrom.PPC`
- Test: `src/cdis-3/tests/test_templates.py` (extend)

**Interfaces — Consumes:** Tasks 2, 3, 6. **Produces:**
`/System/Installation/CDIS/sysinstall`; `rc.cdrom` (installed as
`rc.cdrom.hidden`, made live by the builder) is:
```sh
#!/bin/sh
/System/Installation/CDIS/sysinstall || exec /bin/sh
```
- `ui.h`: `int ui_menu(const char *title, const char **items, int n);`
  (items labelled `1`…`9`, `a`…; returns index or -1),
  `int ui_checklist(const char *title, const char **items, int *on, int n, const int *locked);`
  (digits toggle, Return accepts), `int ui_input(const char *title, char *buf, int len, int noecho);`,
  `void ui_message(const char *title, const char *text);`,
  `void ui_progress(int step, int nsteps, const char *what, const char *tail);`.
- Screen order and texts per the spec's *Screens*; the Drivers screen runs
  `driverDetect` and pre-ticks per the spec's rule (sdN → loaded SCSI
  driver; hdN → AHCI if matched, else EIDE).

- [ ] **Step 1: Write the failing test** in `test_templates.py`:
  `test_english_only_and_the_hook` — no `*.lproj` but `English.lproj`; no
  `rc.cdrom.x86`/`rc.cdrom.PPC`; `rc.cdrom`'s lines equal the hook above;
  the postamble installs `sets/` and not `SCRIPT2`/`SCRIPT3`; `Makefile`
  `TOOLS` lists `sysinstall.tproj`.
- [ ] **Step 2: Run** `cd src/cdis-3 && python -m unittest discover -s tests`. Expected: FAIL.
- [ ] **Step 3: Do the cleanup and write the screens.** Check each edited
  legacy file for Mac-Roman bytes first (`grep -P '[\x80-\xff]'`).
- [ ] **Step 4: Run** the Python tests and `make test` in
  `sysinstall.tproj/tests`. Expected: all pass.
- [ ] **Step 5: Commit** (two commits): `cdis: drop the perl installer and non-English strings, leaving rc.cdrom a hook` and `cdis: add sysinstall's curses screens`.

### Task 8: Media changes in `vm/instmedia`

**Files:**
- Modify: `vm/instmedia/live.py`, `vm/instmedia/build.py`, `vm/instmedia/test_live.py`, `vm/instmedia/test_build.py`

**Interfaces — Produces:** `live.SETS = INSTALLATION + "/Sets"`;
`live.MEDIA_BOOT_DRIVERS = "EISABus PCIBus PS2Keyboard EIDE AHCI ISASerialPort"`;
`live.MEDIA_ACTIVE_DRIVERS = "VGA"`; `live.read_sets(tree) -> {name: [pkg…]}`;
`build.check_sets(apks, sets) -> [problem…]`.

- [ ] **Step 1: Write the failing tests:**
  `test_media_table_uses_generic_boot_drivers` (live root's
  `Instance0.table` `Boot Drivers`/`Active Drivers` equal the constants);
  `test_only_set_packages_are_carried` (a repo apk named in no set is
  refused by `build` with "in no set"); `test_a_set_naming_a_missing_package_is_refused`;
  `test_packages_dir_holds_the_set_packages`. Fixture: `test_live.make_repo`'s
  cdis apk gains `System/Installation/Sets/base.set` listing its packages.
- [ ] **Step 2: Run** `cd vm && python -m unittest instmedia.test_live instmedia.test_build`. Expected: FAIL.
- [ ] **Step 3: Implement.** The media's table is CDIS's i386 template
  rendered for `hd1` with the two driver keys replaced.
- [ ] **Step 4: Run** the vm suite (the phase 4 command in
  `docs/build/instmedia-live.md`). Expected: all pass.
- [ ] **Step 5: Commit** `instmedia: boot the media on generic drivers and carry the packages its sets name`.

### Task 9: Build the closure and the images (controller)

**Files:** none in the repo; fixes get their own `<project>: …` commits.

- [ ] **Step 1:** On a private guest (memory *Private QEMU build guest*),
  build in order: `Libcurses-1` (U), `rbuild kernel` (I, for `driverkit` with
  `driverDetect`), `cdis-3` (I). Fetch into `vm/work/p5-apks`.
- [ ] **Step 2:** `python -m instmedia.collect vm/work/p5-repo --image
  vm/work/rhap-i386-bootstrapped.img --add vm/work/p2-apks --add
  vm/work/p4-apks --add vm/work/p5-apks`, then build `media.img` and
  `preinstalled.img` into `vm/work/p5-gate/`. Expected: both build; record
  counts.
- [ ] **Step 3: Regression:** rerun phase 4's Gates 3 and 4 on
  `preinstalled.img` (commands in `docs/build/instmedia-live.md`).

### Task 10: The gates (controller)

Every run boots temporary images; blank targets are fresh
`python -c "open(p,'wb').truncate(N)"` files. Drive screens with
`qemu_boot.py --type T:KEYS`; find timings with a first `--at` pass.

- [ ] **Gate 1:** SeaBIOS, media `hd1`, blank 2 GB `hd0`, `--nic ne2k_pci`:
  Auto, default drivers, base set, password `rhapsodi2`. Then boot `hd0`
  alone under SeaBIOS and under UEFI with `--nic ne2k_pci --ssh-port 2549`;
  SSH as root with `rhapsodi2`. **Pass:** `login:` on both, SSH runs
  `uname -a`, `mount` shows `/dev/hd0a on /`, `apk info` (or
  `ls /var/lib/apk`) shows the database. Also confirms Task 3's `crypt()`.
- [ ] **Gate 2:** the same install with the media booted under UEFI.
- [ ] **Gate 3:** install onto a 4 GB `hd0` (SeaBIOS), then boot it alone
  under SeaBIOS.
- [ ] **Gate 4:** from Gate 1's runs: the installer's Welcome screen lists
  NE2K loaded; on the installed disk `NE2K.config/Instance0.table` holds
  `Location`, NE2K is in `Active Drivers` (not Boot), and `en0` gets
  10.0.2.15.
- [ ] **Gate 5:** Advanced: create the ESP and `0xA7` entries by hand on a
  blank 2 GB disk, install, boot alone under SeaBIOS.
- [ ] Ledger each gate's shots and log paths.

### Task 11: Record it

**Files:**
- Create: `docs/build/sysinstall.md` (style of `docs/build/instmedia-live.md`: modules, screens, commands, results table, *Worth knowing*)
- Modify: `docs/superpowers/specs/2026-09-22-install-media-design.md` (phase 5 row and *Installer* section: "(Before phase 5; now `sysinstall` …)"; retire risk 5/6 notes as the gates show), `docs/superpowers/specs/2026-10-05-sysinstall-design.md` (status, any rulings)

- [ ] **Step 1:** Write the doc and the spec notes.
- [ ] **Step 2: Commit** `docs: record phase 5a, sysinstall and driverDetect`.
