# Install media phase 4: pure-apk live root and hard-disk media — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build, on the Windows host and only from our own apks, a hard-disk
install medium that boots to the installer's menu under SeaBIOS and IA32
UEFI, and a pre-installed disk that boots multi-user to `login:` and accepts
an SSH password login.

**Architecture:**
- **The missing apks first.** A private QEMU guest builds the *boot
  closure*: the kernel, the boot drivers, the booters, `diskdev_cmds` and
  `network_cmds` with their dependencies, and `cdis-3`, Apple's CD
  installation system.
- **The installer is `cdis-3`.** Its package parks the installer script
  inert as `/private/etc/rc.cdrom.hidden`, and the media's builder makes it
  live, which is the pattern the design already uses. It gains the
  installed-system templates.
- **Five host modules in `vm/instmedia/`:**
  - `collect.py` gathers the apks into one directory, and `apkrepo.py`
    indexes it.
  - `rootfs.py` lays the payloads out as a node tree the way `apk add`
    would.
  - `live.py` adds the live overlay, or the installed-system files for
    `--preinstalled`.
  - `hdimage.py` writes the MBR, the ESP and the `0xA7` partition as
    `disk -i -b` does.
  - `build.py` checks the tree, writes the image and reads it back.
- **`vm/qemu_boot.py`** learns to boot the media from `hd1` and to give the
  guest a network card.

**Tech Stack:**
- Python 3.13, standard library only, with `unittest`
- QEMU 11.1: SeaBIOS and the bundled `edk2-i386-code.fd`
- rbuild on an i386 Rhapsody DR2 guest booted from
  `vm/work/rhap-i386-bootstrapped.img` with `-snapshot`

**Spec:** `docs/superpowers/specs/2026-09-22-install-media-design.md`, phase
4, with *Host builder*, *Live environment*, *Installed-system
configuration* and *Testing*.

## Already verified

Every host file in this plan was prototyped before the plan was written, in
a scratch copy of `vm/` and of the two `src/` projects it changes. The
executor still runs everything again. These are the expected results:

- **Host tests:** 94 `vm` tests pass, none skipped when
  `RHAPSODY_MEDIA_DIR` and `RHAPSODY_BOOTSTRAP_IMAGE` are set. They are
  `hdimage` 8, `apkrepo` 10, `rootfs` 17, `live` 9, `build` 13, `collect`
  5, `label` 8 (one new) and `qemu_boot` 24. All 5 `cdis-3` template tests
  pass.
- **Real apks:** `collect` read all 68 universal apks off the bootstrapped
  image and decompressed each one without error. With the phase 2 apks,
  `rootfs` laid down 44 packages, 362 directories and 3649 other entries,
  and no conflicts. Phase 2's real `apk add --root --initdb` printed exactly
  those counts: `OK: 44 packages, 362 dirs, 3649 files`.
- **QEMU:** the new `qemu_boot` arguments (`--boot-hd1`, `--nic ne2k_pci`
  and `--ssh-port`) start QEMU under both firmwares.
- **Not verified yet:**
  - anything that runs on the guest (Tasks 1 and 3)
  - the two Makefile changes, which only rbuild can check (Task 3)
  - the boots of the finished images (Task 11)

## Where this plan departs from the spec

1. **Boot closure first, not every world apk** (Pat, 2026-09-27). The
   world's other ~40 projects come later. The live root is every apk that
   exists.
2. **The installer is `cdis-3`, Apple's DR2 CD installer** (Pat), not a new
   project.
   - `cdis-3` installs its Perl `rc.cdrom` inert, as
     `/private/etc/rc.cdrom.hidden`, along with `rc.cdrom.x86` and
     `rc.cdrom.PPC`. Its tools go in `/System/Installation/CDIS`
     (`pickdisk`, `findroot`, `gc`, `popconsole` and others), and its
     target mount point is `/private/var/tmp/mnta`.
   - The live overlay makes `rc.cdrom.hidden` live as
     `/private/etc/rc.cdrom`. So the spec's `/Installation/Target` gives
     way to CDIS's `mnta`.
   - The installed-system templates go in `cdis-3`, installed at
     `/System/Installation/CDIS/templates`.
   - Phase 4's gate is CDIS's first menu. With no `sysconfig` tool, which
     `cdis-3` doesn't build, `rc.cdrom` asks for a language. Typing `1`
     must bring up its Intel warning, and that proves the keyboard too.
   - Phase 5 keeps CDIS's UI and `pickdisk`. It replaces the `fdisk` and
     tarball steps with `mbrinst`, `disk -i -b` and `apk add`.
3. **`/System/Installation` exists on every root**, because the `cdis`
   apk installs it. So the check on the installed system is that
   `/etc/rc.cdrom` is absent. `rc` and `rc.boot` start the installer only
   when both exist.
4. **The network card is NE2K, an Active Driver.**
   - `driverLoader` is being reconstructed elsewhere and ships in the
     `driverkit` apk at `/usr/sbin/driverLoader`, DR2's path (Pat,
     2026-09-27). `files`' `startup/0700_Devices` runs `driverLoader a`,
     which loads the Active Drivers.
   - The spec's `Intel1000` is not used. It installs as `Pro1000.config`,
     and its shipped `Instance0.table` describes one real machine: an
     82547EI with `Auto Detect IDs` `0x10198086` only, at
     `Dev:1 Func:0 Bus:2`, IRQ 3. QEMU's e1000 (`8086:100E`) doesn't match
     it.
   - NE2K's `Default.table` auto-detects (`"Location" = ""`), and the build
     guests already use it with QEMU's `ne2k_pci`. Task 1 checks that, with
     only its `Default.table`, it loads as an Active Driver under DR2's
     `driverLoader`, the reference the reconstruction follows.
   - The `Instance0.table` template's Active Drivers are therefore
     `Default.table`'s list plus `NE2K`. Its Boot Drivers are the spec's:
     `EISABus PCIBus PS2Keyboard EIDE AHCI`.
5. **`/private/Devices` was missing.** `files` links `/usr/Devices` and
   `/System/Library/Devices` to `../private/Devices`, but nothing in the
   tree makes `/private/Devices`, which on DR2 is a link to `Drivers/i386`.
   `driverLoader` reads through `/usr/Devices`, so `system_config-1`, which
   installs the i386 `System.config`, now makes that link too.
6. **`-hdrs` and `-obj` companions are left out** of every root. They
   repeat files their base package ships, and apk refuses them (phase 2).
7. **`collect.py` instead of `vm/fetch-apks.ps1`.**
   - The bootstrap apks are read off the image on the host, without writing
     it, and checked in full. Only the universal builds are used, as in
     phase 2's proven root.
   - The Task 3 apks are fetched one at a time as each is built.
8. **The pre-installed image has no apk database, and `pwd_mkdb` is not
   run.** The builder doesn't run apk.
   - Without `lookupd`, libc's `getpwnam` reads `/etc/master.passwd`
     directly (`src/Libinfo-1/lookup.subproj/lu_user.c:315-317`,
     `gen.subproj/getpwent.c:287`).
   - `lookupd` would come from `netinfo-1`, which is in neither the closure
     nor `src/Manifest`. So the hash in `master.passwd` is what logins
     check.
9. **The SSH gate forwards host port 2549**, since 2222 is the shared build
   box.
10. **No `--form` flag yet:** the disk form only. Phase 6 adds the CD.

## Global Constraints

- **Worktree:** `.claude/worktrees/install-media-p4`, on branch
  `install-media-p4`, which already exists. Parallel sessions share the main
  checkout's git index, so stage explicit paths only and never run a bare
  `git stash`.
- **No Apple bits:** every byte on the media comes from our apks or our own
  builds. No DR2 media and no `golden.img`, not even as templates.
  (`cdis-3`'s source is in the tree and built by rbuild, so it qualifies.)
- **Builder rules:** stage in memory, never on NTFS. Standard library only.
  Deterministic output: sorted walks, apk mtimes preserved, no host
  timestamps.
- **Hard-disk layout, exactly:**
  - LBA 0 holds `boot0` and the fdisk table. Entry 1 is type `0xEF` at LBA
    2048 for 131072 sectors (64 MB). Entry 2 is type `0xA7`, active, from
    LBA 133120 to the last sector.
  - The ESP is FAT32 holding only `/EFI/BOOT/BOOTIA32.EFI`.
  - The `0xA7` interior is what `disk -i -b` writes: `boot1` at LBA
    133120, and label copies at +15/30/45 with `secsize` 512 and absolute
    `p_base` and `d_boot0_blkno`. Two `boot2` copies sit at those
    `d_boot0_blkno` locations, and the UFS starts at
    `(dl_front + p_base) × 512`.
- **The live overlay holds only:**
  - `/private/etc/rc.cdrom`, made from `cdis`'s `rc.cdrom.hidden`
  - `/private/Drivers/i386/System.config/Instance0.table`, with
    `Kernel Flags` = `rootdev=hd1a`
  - `/System/Installation/Packages/*.apk`
  - `/System/Installation/esp.img.gz`
- **The installed-system files:**
  - `fstab`
  - `Instance0.table`, with `Kernel Flags` = `rootdev=hdNa` and
    `Boot Graphics` = `No`
  - `hostconfig`, with `APPLETALK`, `AUTOMOUNT` and `TIMESYNC` = `-NO-`
  - root's hash in `master.passwd`

  `/etc/rc.cdrom` must be absent on the installed system.
- **Pre-installed password:** a fixed test password, stored as a
  precomputed DES crypt hash in the builder's test configuration.
- **Tests:** run from the worktree's `vm/` as
  `python -m unittest instmedia.<module> -v`. `label`'s reference-image
  tests need `RHAPSODY_MEDIA_DIR=D:/RhapsodiOS/vm`.
- **Guests (CLAUDE.md §6):**
  - Boot only `-snapshot` copies of `vm/work/rhap-i386-bootstrapped.img`.
    Never write, move or delete that shared base image.
  - Never boot `vm/golden.img`, `vm/rhapsody.vmdk` or `vm/work/test.img`.
    `qemu_boot.py` opens every disk with `-snapshot`.
  - Quit guests with QMP `quit` only.
  - Use one ssh session at a time, with no polling loops.
  - Fetch each apk to the host as soon as it is built.
  - Delete the scratch `vm.conf` files, which hold the guest password,
    when done.
  - The guest on 2222 belongs to other sessions.
- **Commits:** `<subsystem>: <what it does>`, one or two lines, with no
  metadata and no trailers.
- **Legacy sources may hold Mac-Roman bytes.** Before editing a file under
  `src/` with the Edit tool, check it with
  `LC_ALL=C grep -c $'[\x80-\xff]'`. `cdis-3/README.mkinstallcd.md` has
  some; the files this plan edits have none.

## Review Focus

Failure modes the spec implies that most tasks' tests don't show. Each has
its test in the owning task.
1. **A package member whose parent directory is a symlink** (`etc/...`,
   `usr/include/...`) should land where the link leads. A claim made
   through the link is a conflict at the real path. Task 6:
   `test_a_symlinked_parent_is_followed` and
   `test_a_claim_through_a_symlink_is_reported_at_the_real_path`.
2. **A member under a symlink to nowhere** should be refused with a
   message, as `apk add` would fail. Task 6:
   `test_extracting_through_a_dangling_symlink_is_refused`. Task 9:
   `test_main_reports_a_package_it_cannot_lay_down`.
3. **The image's repository and a rebuild carrying the same package
   (`files`):** the rebuild should win, and the old builds go. Task 7:
   `test_a_later_source_replaces_every_build_of_a_package`.
4. **`/usr/Devices` not reaching `Instance0.table`** would leave
   `driverLoader` without its table and the disk without a network, with
   no error anywhere. Task 9:
   `test_preinstalled_needs_usr_devices_to_reach_the_table`.
5. **A damaged apk on the image** (its filesystem has DUP blocks) should be
   refused, never copied. Task 7: `test_damaged_apks_are_refused`.

## File structure

| File | Job |
|---|---|
| `src/cdis-3/templates/{fstab,hostconfig,Instance0.table}` | Installed-system templates; `@DISK@` is the disk name |
| `src/cdis-3/Makefile.postamble` | Also installs the templates in `/System/Installation/CDIS/templates` |
| `src/cdis-3/tests/test_templates.py` | Host tests: each template against the file it derives from |
| `src/system_config-1/Makefile.postamble` | Also links `/private/Devices` to `Drivers/i386` |
| `vm/instmedia/label.py` | `for_filesystem` passes `boot0` through |
| `vm/instmedia/hdimage.py` | MBR, ESP, `0xA7` interior, cylinder-aligned size |
| `vm/instmedia/testapks.py` | Synthetic apks for tests |
| `vm/instmedia/apkrepo.py` | Index a flat apk directory, one build per package |
| `vm/instmedia/rootfs.py` | Node tree from apk payloads, conflicts, overlay |
| `vm/instmedia/collect.py` | Image repository plus added builds into one directory |
| `vm/instmedia/testconfig.py` | The test password and its hash |
| `vm/instmedia/live.py` | Live root and pre-installed root |
| `vm/instmedia/build.py` | CLI: checks, sizing, write, read back |
| `vm/qemu_boot.py` | `--boot-hd1`, `--nic`, `--ssh-port` |
| `docs/build/instmedia-live.md` | What phase 4 built and how it was checked |

Tasks 1 and 3 run on a guest and are the controller's own work. Task 3
takes hours, so start it as soon as Task 2 is committed, and do Tasks 4 to
10 while it runs.

---

### Task 1: Show NE2K loads as an Active Driver with only its Default.table (guest spike, no code)

Decision 4 rests on this. The reconstructed `driverLoader` follows DR2's,
so DR2's behaviour here is the reference. If this fails, stop and report
to Pat before any other task.

**Files:** none in the repo. Scratch: `<scratch>/p4guest/`.

- [ ] **Step 1: Pick free ports and write the launcher.** Check that 2547
  and 4547 are free (`netstat -ano | grep -E ':2547 |:4547 '` prints
  nothing), then write `<scratch>/p4guest/launch.py`:

```python
"""A private, -snapshot build guest from rhap-i386-bootstrapped.img.

ssh: 127.0.0.1:2547 -> guest 10.10.0.240:22; QMP: 127.0.0.1:4547.
"""
import os
import subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
IMAGE = "D:/RhapsodiOS/vm/work/rhap-i386-bootstrapped.img"

args = [
    "qemu-system-i386", "-name", "p4-build", "-M", "pc", "-cpu", "pentium",
    "-accel", "tcg", "-m", "512", "-nodefaults", "-vga", "cirrus",
    "-display", "none", "-snapshot",
    "-drive", "file=%s,format=raw,if=ide,index=0,media=disk" % IMAGE,
    "-netdev", "user,id=n0,net=10.10.0.0/16,host=10.10.0.1,dns=10.10.0.3,"
               "hostfwd=tcp:127.0.0.1:2547-10.10.0.240:22",
    "-device", "ne2k_pci,netdev=n0,addr=03.0,mac=52:54:00:12:34:56",
    "-serial", "file:%s" % os.path.join(HERE, "com1.log"),
    "-serial", "file:%s" % os.path.join(HERE, "com2.log"),
    "-rtc", "base=utc",
    "-qmp", "tcp:127.0.0.1:4547,server=on,wait=off",
]
flags = subprocess.DETACHED_PROCESS | subprocess.CREATE_NEW_PROCESS_GROUP
with open(os.path.join(HERE, "qemu-stderr.log"), "wb") as err:
    proc = subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=err,
                            creationflags=flags)
print("qemu pid %d" % proc.pid)
```

- [ ] **Step 2: Make the scratch remote tools.**

```bash
P=<scratch>/p4guest
mkdir -p $P/vm
cp .claude/worktrees/install-media-p4/vm/{rhap-remote,build-src-lib,sync-src,sync-src-lib,guest-remote}.ps1 $P/vm/
sed -e 's/^Port=.*/Port=2547/' -e 's|^RemoteRoot=.*|RemoteRoot=/build/p4|' \
    -e '/^RemoteRoot=/a LocalRoot=D:/RhapsodiOS/.claude/worktrees/install-media-p4' \
    D:/RhapsodiOS/vm/vm.conf > $P/vm/vm.conf
```

- [ ] **Step 3: Boot it.** Run `python $P/launch.py`. Wait about 3
  minutes; sshd comes up late, and an earlier attempt gets "Connection
  aborted".

- [ ] **Step 4: Hide NE2K's Configure-written Instance0.table, so
  `driverLoader` has only `Default.table`, which is all our apk ships.
  Leave NE2K in Active Drivers.** Write `$P/spike.sh`:

```sh
grep -n 'Drivers' /private/Drivers/i386/System.config/Instance0.table
mv /private/Drivers/i386/NE2K.config/Instance0.table /tmp/NE2K-Instance0.table
ls /private/Drivers/i386/NE2K.config
/sbin/reboot
```

  Run it: `powershell -NoProfile -File $P/vm/guest-remote.ps1 -Run $P/spike.sh`.
  The `grep` must show NE2K in Active Drivers. The connection drops at the
  reboot.

- [ ] **Step 5: Judge it.** Wait about 5 minutes, then run a script that
  prints `ifconfig en0` and `ls /private/Drivers/i386/NE2K.config`.
  - **Pass:** ssh answers, `en0` has `inet 10.10.0.240`, and
    `NE2K.config` holds no `Instance0.table`.
  - **If it fails:** first `system_reset` over QMP and type `-v` at
    `boot:`, because non-verbose boots sometimes hang after "console up".
    If it still fails, stop and report to Pat with `com2.log`.
    - The likely fallback is a harness `Instance0.table` for NE2K, with
      `"Location" = "Dev:3 Func:0 Bus:0"` to match `addr=03.0`. That is a
      design change, so it's Pat's call.

- [ ] **Step 6:** Leave the guest running for Task 3, which reboots it
  clean. Record the result, with the `com2.log` excerpt, for Task 12.

### Task 2: Templates in cdis-3, and the /private/Devices link

**Files:**
- Create: `src/cdis-3/templates/fstab`, `src/cdis-3/templates/hostconfig`,
  `src/cdis-3/templates/Instance0.table`,
  `src/cdis-3/tests/test_templates.py`
- Modify: `src/cdis-3/Makefile.postamble` (end of `after_install`) and
  `src/system_config-1/Makefile.postamble` (the `after_install` loop)

**Interfaces:**
- Produces:
  - The `cdis` apk gains `/System/Installation/CDIS/templates/{fstab,hostconfig,Instance0.table}`.
    Every `@DISK@` is the disk name. It keeps `/private/etc/rc.cdrom.hidden`,
    `rc.cdrom.x86`, `rc.cdrom.PPC`, `/System/Installation/CDIS/*` and
    `/private/var/tmp/mnta`. Task 8 reads these paths.
  - The `system-config` apk gains the symlink
    `/private/Devices -> Drivers/i386`.

- [ ] **Step 1: Write the tests.** `src/cdis-3/tests/test_templates.py`:

```python
"""The installed-system templates against the files they derive from.

    cd src/cdis-3 && python -m unittest discover -s tests -v
"""
import os
import re
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.dirname(HERE)
SRC = os.path.dirname(PROJECT)
TEMPLATES = os.path.join(PROJECT, "templates")
NAMES = ("fstab", "hostconfig", "Instance0.table")


def read(*parts):
    with open(os.path.join(*parts), "rb") as f:
        return f.read()


def table_keys(text):
    return re.findall(rb'^"([^"]+)"\s*=', text, re.M)


def table_value(text, key):
    return re.search(rb'^"%s"\s*=\s*"([^"]*)";' % re.escape(key), text,
                     re.M).group(1)


class TestTemplates(unittest.TestCase):
    def test_fstab_is_fstab_hds_root_line(self):
        root_line = read(SRC, "files-5", "private", "etc",
                         "fstab.hd").split(b"\n")[0] + b"\n"
        self.assertEqual(read(TEMPLATES, "fstab").replace(b"@DISK@", b"hd0"),
                         root_line)

    def test_hostconfig_is_files_copy_with_three_services_off(self):
        ours = read(TEMPLATES, "hostconfig").split(b"\n")
        theirs = read(SRC, "files-5", "private", "etc",
                      "hostconfig").split(b"\n")
        self.assertEqual(len(ours), len(theirs))
        changed = [(a, b) for a, b in zip(theirs, ours) if a != b]
        self.assertEqual(changed, [
            (b"APPLETALK=-YES-", b"APPLETALK=-NO-"),
            (b"AUTOMOUNT=-YES-", b"AUTOMOUNT=-NO-"),
            (b"TIMESYNC=-YES-", b"TIMESYNC=-NO-")])
        self.assertIn(b"SSHSERVER=-YES-", ours)

    def test_instance0_has_default_tables_keys_and_the_overrides(self):
        ours = read(TEMPLATES, "Instance0.table")
        default = read(SRC, "system_config-1", "i386", "Default.table")
        self.assertEqual(table_keys(ours), table_keys(default))
        self.assertEqual(table_value(ours, b"Boot Drivers"),
                         b"EISABus PCIBus PS2Keyboard EIDE AHCI")
        self.assertEqual(table_value(ours, b"Active Drivers"),
                         table_value(default, b"Active Drivers") + b" NE2K")
        self.assertEqual(table_value(ours, b"Kernel Flags"),
                         b"rootdev=@DISK@a")
        self.assertEqual(table_value(ours, b"Boot Graphics"), b"No")
        for key in (b"Version", b"Kernel", b"Install Mode", b"APM"):
            self.assertEqual(table_value(ours, key),
                             table_value(default, key))

    def test_the_postamble_installs_every_template(self):
        postamble = read(PROJECT, "Makefile.postamble")
        for name in NAMES:
            self.assertIn(b"templates/" + name.encode(), postamble)

    def test_no_carriage_returns(self):
        for name in NAMES:
            self.assertNotIn(b"\r", read(TEMPLATES, name), name)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run them to see them fail.**
  `cd src/cdis-3 && python -m unittest discover -s tests -v`. Expected:
  errors, because `templates/` doesn't exist.

- [ ] **Step 3: Write the templates.** `src/cdis-3/templates/Instance0.table`:

```text
/*
 * The system configuration table of an installed RhapsodiOS disk.  The
 * installer, and the install-media builder, replace every @DISK@ with the
 * disk's name (hd0, sd0, ...).
 *
 * Default.table's keys (src/system_config-1), except:
 *   Boot Drivers    the IDE and AHCI controllers instead of Floppy and
 *                   ISASerialPort.
 *   Active Drivers  adds NE2K, the network card; driverLoader loads it at
 *                   startup (/etc/startup/0700_Devices).
 *   Kernel Flags    the root is partition a of @DISK@.
 *   Boot Graphics   off, for a text console.
 */

/* Version of this File */
"Version" = "5.00";

/* Drivers to probe at boot time */
"Boot Drivers" = "EISABus PCIBus PS2Keyboard EIDE AHCI";

/* Bundles to load/probe later */
"Active Drivers" = "PS2Mouse BusMouse SerialPointingDevice ParallelPort VGA NE2K";

/* Which kernel to load */
"Kernel" = "mach_kernel";

/* Other kernel flags */
"Kernel Flags" = "rootdev=@DISK@a";
"Boot Graphics" = "No";
"Install Mode" = "No";
"APM" = "Yes";
```

`src/cdis-3/templates/fstab` is one line, with tabs exactly as in
`files-5/private/etc/fstab.hd`:

```bash
printf '/dev/@DISK@a\t/\tufs\trw\t\t1  1\n' > src/cdis-3/templates/fstab
```

`src/cdis-3/templates/hostconfig` is `files`' copy with three services off:

```bash
sed -e 's/^APPLETALK=-YES-$/APPLETALK=-NO-/' -e 's/^AUTOMOUNT=-YES-$/AUTOMOUNT=-NO-/' \
    -e 's/^TIMESYNC=-YES-$/TIMESYNC=-NO-/' src/files-5/private/etc/hostconfig \
    > src/cdis-3/templates/hostconfig
```

In `src/cdis-3/Makefile.postamble`, append two lines at the end of
`after_install`, after `$(MKDIRS) $(DSTROOT)/private/var/tmp/mntb`. The
lines start with a tab. rbuild copies the whole project directory, so the
relative `templates/` paths resolve, as `$(SCRIPT1)` does:

```make
	$(MKDIRS) $(DSTROOT)$(INSTALLDIR)/$(NAME)/templates
	$(INSTALL) -c -o root -g wheel -m 444 templates/fstab templates/hostconfig templates/Instance0.table $(DSTROOT)$(INSTALLDIR)/$(NAME)/templates
```

- [ ] **Step 4: Run the tests.** All 5 pass.

- [ ] **Step 5: Commit.**

```bash
git add src/cdis-3/templates src/cdis-3/tests src/cdis-3/Makefile.postamble
git commit -m "cdis: carry the installed-system fstab, hostconfig and Instance0.table templates"
```

- [ ] **Step 6: The Devices link.** In `src/system_config-1/Makefile.postamble`'s
  `after_install` loop, add this line after
  `$(CHGRP) -R wheel $$to_dir; \`, with two leading tabs like its
  neighbours:

```make
		ln -fs Drivers/$$arch $(DSTROOT)/private/Devices; \
```

  The loop installs only architectures that have a `SRCROOT/<arch>`
  directory, and only `i386/` exists, so the link names the architecture
  whose `System.config` this is. Task 3 checks the built apk.

- [ ] **Step 7: Commit.**

```bash
git add src/system_config-1/Makefile.postamble
git commit -m "system_config: link /private/Devices to Drivers/i386, which /usr/Devices leads through"
```

### Task 3: Build the boot closure on the guest (controller; runs in the background)

**Files:** none planned. Each fix found while building goes in its own
commit, as `<project>: <fix>`, like phase 2's zlib and OpenSSL fixes.
Output: `D:/RhapsodiOS/vm/work/p4-apks/`, with one apk or more per project
below.

The closure, in order, with the profile each project needs. U is
`gcc-darwin-universal.conf`; I is `gcc-darwin-i386.conf --arch i386`.

| Chain | Projects | Why |
|---|---|---|
| A | rbuild itself; `driverTools-1` (U); `rbuild kernel` (I) | the drivers and boot-2 need `drivertools`; the kernel run builds `driverkit-3` (which carries `driverLoader`), `kernload-1` and `kernel-7` |
| B | `drivers-i386/bus/drvEISABus`, `bus/drvPCIBus`, `input/drvPS2Keyboard`, `ide/drvEIDE`, `ide/drvAHCI` and `network/drvNE2k` (all I) | the Boot Drivers and the network card; `drvEIDE` also makes `drveide-hdrs`, which `diskdev_cmds` and `cdis-3` need |
| C | `yacc-1`, `flex-1`, `LibcAT-1`, `Libtelnet-1`, `gawk-1` (U) | build dependencies of `network_cmds` and `boot-2` |
| D | `Commands/network_cmds`, `Commands/diskdev_cmds`, `dhcpcd-1`, `gnuzip-1`, `system_config-1`, `cdis-3` (U) | mount, fsck, newfs, disk, ifconfig, syslogd and inetd; DHCP; gzip; `System.config` and `/private/Devices`; the installer |
| E | `boot-2` (I) | boot0, boot1, boot2 and `sarld` |

The phase 2 apks in `vm/work/p2-apks` (files, zlib, apk-tools, perl,
OpenSSL and OpenSSH) are uploaded rather than rebuilt. perl is what CDIS's
`rc.cdrom` runs on.

- [ ] **Step 1: Reboot the Task 1 guest clean.** Its snapshot holds the
  spike's edit. `/sbin/reboot` it, and quit QEMU with QMP `quit` as soon
  as `com2.log` shows a new "i386 kernel console up". Relaunch with
  `python $P/launch.py`. With `-snapshot`, the new boot starts from the
  untouched image.

- [ ] **Step 2: Make the build root, and upload the phase 2 apks and the
  sources.**

```bash
printf 'mkdir -p /build/p4/src /build/p4/repo /build/p4/out /build/p4/state /build/p4/bin && echo made\n' > $P/mk.sh
powershell -NoProfile -File $P/vm/guest-remote.ps1 -Run $P/mk.sh
mkdir -p $P/up/src/p4-upload $P/vmup && cp D:/RhapsodiOS/vm/work/p2-apks/*.apk $P/up/src/p4-upload/
cp $P/vm/*.ps1 $P/vmup/ && sed "s|^LocalRoot=.*|LocalRoot=$P/up|" $P/vm/vm.conf > $P/vmup/vm.conf
powershell -NoProfile -File $P/vmup/sync-src.ps1 -Path p4-upload
for p in rbuild-1 driverTools-1 driverkit-3 kernload-1 kernel-7 drivers-i386 yacc-1 flex-1 LibcAT-1 \
         Libtelnet-1 gawk-1 Commands/network_cmds Commands/diskdev_cmds dhcpcd-1 gnuzip-1 \
         system_config-1 cdis-3 boot-2; do
    powershell -NoProfile -File $P/vm/sync-src.ps1 -Path $p || break
done
```

  `sync-src` gives the guest exactly the execute bits git records
  (cf9660879).

- [ ] **Step 3: Write the chain runner,** `$P/chain.sh.in`. Replace the
  `@JOBS@` line for each chain. Each job is `<srcdir>:<U|I>`, or
  `kernel:I`.

```sh
cat > /build/p4/chain.sh <<'CHAINEOF'
# Build the listed projects in order, stopping at the first failure.
B=/build/p4
TC=$B/src/rbuild-1/toolchains
cd /
for job in @JOBS@; do
    P=`echo $job | cut -d: -f1`
    K=`echo $job | cut -d: -f2`
    if [ "$K" = I ]; then A="--toolchain $TC/gcc-darwin-i386.conf --arch i386"
    else A="--toolchain $TC/gcc-darwin-universal.conf"; fi
    N=`basename $P`
    echo "== $P start `date`"
    if [ "$P" = kernel ]; then
        $B/bin/rbuild kernel --state $B/kstate $A $B/src $B/repo $B/out > $B/state/$N.out 2>&1
    else
        $B/bin/rbuild buildpackage --state $B/state --dir $A $B/src/$P $B/repo $B/out > $B/state/$N.out 2>&1
    fi
    rc=$?
    echo "== $P end `date` RBUILD_RC=$rc"
    tail -15 $B/state/$N.out
    for f in $B/out/*.apk; do ln -f $f $B/repo/`basename $f`; done
    test $rc -eq 0 || exit 1
done
echo "== out"; ls -l $B/out
CHAINEOF
trap '' 1
nohup sh /build/p4/chain.sh > /build/p4/chain.log 2>&1 &
wait $!
sed -n '/RBUILD_RC\|== out/,$p' /build/p4/chain.log | tail -60
```

- [ ] **Step 4: Chain A.** Put this before the chain in `$P/chainA.sh`,
  then generate the rest from `chain.sh.in`, with
  `@JOBS@` = `driverTools-1:U kernel:I`:

```sh
cd /build/p4/src/rbuild-1 && /bin/make CC=/usr/bin/cc all > /build/p4/state/rbuild-all.out 2>&1 \
    && cp rbuild /build/p4/bin/rbuild || { echo "rbuild build failed"; exit 1; }
for f in /build/repo/*.apk; do ln $f /build/p4/repo/`basename $f` 2>/dev/null; done
cp /build/p4/src/p4-upload/*.apk /build/p4/out/
for f in /build/p4/out/*.apk; do ln -f $f /build/p4/repo/`basename $f`; done
rm -f /build/p4/repo/files-*-i386.apk
perl -e 'print crypt("rhapsodi","rh"),"\n"'
```

  - The `perl` line must print `rhME8brSxdukA`, the hash in Task 8's
    `testconfig.py`. If it prints something else, Rhapsody's `crypt()`
    wins, and Task 8 uses its string.
  - Run it in the background:
    `powershell -NoProfile -File $P/vm/guest-remote.ps1 -Run $P/chainA.sh`.
    It takes about 45 minutes. Wait for the notification.

- [ ] **Step 5: Fetch after every chain.**

```bash
printf 'ls /build/p4/out | grep "\\.apk$"\n' > $P/ls.sh
mkdir -p D:/RhapsodiOS/vm/work/p4-apks
for f in $(powershell -NoProfile -File $P/vm/guest-remote.ps1 -Run $P/ls.sh 2>/dev/null | tr -d '\r' | grep '\.apk$'); do
    test -f D:/RhapsodiOS/vm/work/p4-apks/$f && continue
    MSYS_NO_PATHCONV=1 powershell -NoProfile -File $P/vm/guest-remote.ps1 -Fetch /build/p4/out/$f -To D:/RhapsodiOS/vm/work/p4-apks/$f
done
```

  The uploaded phase 2 apks come back too. That's harmless, because
  `collect` lets the last added directory win.

- [ ] **Step 6: Chains B, C, D and E,** in that order, each followed by
  Step 5. Expect about 60, 60, 90 and 20 minutes.
  - B: `drivers-i386/bus/drvEISABus:I drivers-i386/bus/drvPCIBus:I drivers-i386/input/drvPS2Keyboard:I drivers-i386/ide/drvEIDE:I drivers-i386/ide/drvAHCI:I drivers-i386/network/drvNE2k:I`
  - C: `yacc-1:U flex-1:U LibcAT-1:U Libtelnet-1:U gawk-1:U`
  - D: `Commands/network_cmds:U Commands/diskdev_cmds:U dhcpcd-1:U gnuzip-1:U system_config-1:U cdis-3:U`
  - E: `boot-2:I`

- [ ] **Step 7: When a build fails.**
  1. Read `$B/state/<name>.out`.
  2. A failed rbuild leaves `/private/tmp/roots/<pkg>.roots/`. Rerun its
     logged chroot `make` line with `-k` there to see every error in one
     pass.
  3. Fix the source in the worktree, re-sync that project, and rerun the
     chain from the failed job.
  4. Commit each fix alone, as `<project>: <what it fixes>`.
  5. A dependency missing from the repo means a project is missing from
     the closure. Add it to the chain, and note it for Task 12.

- [ ] **Step 8: Check the three packages this phase changed or depends on.**

```bash
cd D:/RhapsodiOS/vm/work/p4-apks
python -c "import tarfile,glob; [print(f, [(m.name, m.linkname) for m in tarfile.open(f,'r:gz') if m.name.lstrip('./') == 'private/Devices']) for f in glob.glob('system-config-*.apk')]"
python -c "import tarfile,glob; [print(f, sorted(m.name.lstrip('./') for m in tarfile.open(f,'r:gz') if 'templates/' in m.name or 'rc.cdrom' in m.name)) for f in glob.glob('cdis-*.apk')]"
python -c "import tarfile,glob; [print(f, [m.name for m in tarfile.open(f,'r:gz') if m.name.endswith('sbin/driverLoader')]) for f in glob.glob('driverkit-*.apk')]"
```

  - `system-config` must show `('private/Devices', 'Drivers/i386')`.
  - `cdis` must list the three templates, `private/etc/rc.cdrom.hidden`,
    `rc.cdrom.x86` and `rc.cdrom.PPC`.
  - `driverkit` must list `usr/sbin/driverLoader`. If it doesn't, the
    reconstruction hasn't reached this branch yet. Once it's on master,
    merge master into `install-media-p4`, re-sync `driverkit-3`, rerun
    `kernel:I`, and fetch again. Gates 1 and 2 don't need it; gates 3 and
    4 wait for it, and `build.py` refuses a pre-installed image without it.

- [ ] **Step 9: Done when** `vm/work/p4-apks` holds, besides the phase 2
  apks, at least one apk from every project in chains A–E, each opening
  with `python -c "import tarfile,sys; tarfile.open(sys.argv[1],'r:gz').getmembers()" <apk>`.
  Leave the guest up until Task 11's builds pass, in case an apk has to be
  rebuilt. Then quit it with QMP `quit` on 4547, and delete `$P/vm/vm.conf`
  and `$P/vmup/vm.conf`.

### Task 4: The hard-disk image writer

**Files:**
- Modify: `vm/instmedia/label.py` (`for_filesystem`), `vm/instmedia/test_label.py`
- Create: `vm/instmedia/hdimage.py`, `vm/instmedia/test_hdimage.py`

**Interfaces:**
- Consumes: `build_uefi_image.lba_assist_geometry`, `_part_entry`,
  `ESP_LBA`, `ESP_BOOT_PATH`, `DISK_BOOTSZ`, `EFI_SYSTEM`, `FDISK_NEXTNAME`;
  `fat32.build`; `label.for_filesystem`, `label.place`, `label.DISK_COPIES`;
  `ufs.write`; `ufs_geometry.geometry`.
- Produces:
  - `hdimage.esp_image(efi: bytes) -> bytes`, of exactly 64 MB.
  - `hdimage.disk_sectors(fs_sectors) -> int`.
  - `hdimage.write(path, fs_sectors, boot0, boot1, boot2, esp, nodes, now, name="RhapsodiOS") -> (Geometry, total_sectors)`,
    raising `hdimage.ImageError`.
  - Constants `ESP_LBA=2048`, `ESP_SECTORS=131072`, `A7_LBA=133120`,
    `FRONT=320` and `BOOT2_BLKNOS=(64, 192)`.

- [ ] **Step 1: Write the failing tests.** Add to `test_label.py`'s
  `TestForFilesystem`:

```python
    def test_passes_boot_blocks_through(self):
        g = ufs_geometry.geometry(fssize=8217087, secsize=1024, nsect=63,
                                  ntrak=16, rpm=3600)
        self.assertEqual(
            label.for_filesystem(g, front=160, p_base=0, ncylinders=16383,
                                 name="Disk", d_type="fixed_rw_ide",
                                 boot0=(32, 96)),
            label.label(**dict(GOLDEN, minfree=5, d_name="Disk",
                               boot0=(32, 96), tag=0)))
```

`vm/instmedia/test_hdimage.py`:

```python
import os
import struct
import tempfile
import unittest

import build_uefi_image as bui
import fat32
import rhap_image
import ufs_check
from ufs_extract import Node
from instmedia import hdimage, readback

NOW = 946684800
BOOT0 = bytes([0x11]) * 446
BOOT1 = bytes([0x22]) * 510 + b"\x55\xaa"
BOOT2 = bytes(range(256)) * 160          # 40960 bytes, 80 sectors
EFI = b"MZ" + b"not really a PE image" * 100
NODES = [
    Node("/", "dir", 0o755, 0, 0, NOW, None),
    Node("/mach_kernel", "reg", 0o444, 0, 0, NOW, b"kernel" * 5000),
    Node("/private", "dir", 0o755, 0, 0, NOW, None),
    Node("/private/tftpboot", "dir", 0o755, 0, 0, NOW, None),
    Node("/private/tftpboot/mach_kernel", "hlink", 0, 0, 0, 0,
         "/mach_kernel"),
    Node("/etc", "lnk", 0o755, 0, 0, NOW, "private/etc"),
]


class TestDiskSectors(unittest.TestCase):
    def test_ends_on_a_cylinder_of_its_own_geometry(self):
        for fs in (16384, 1000000, 2000000, 4194304):
            total = hdimage.disk_sectors(fs)
            heads, spt = bui.lba_assist_geometry(total)
            self.assertEqual(total % (heads * spt), 0)
            self.assertGreaterEqual(total,
                                    hdimage.A7_LBA + hdimage.FRONT + fs)
            self.assertLess(total - (hdimage.A7_LBA + hdimage.FRONT + fs),
                            heads * spt)


class TestWrite(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.path = os.path.join(cls.tmp.name, "disk.img")
        cls.esp = hdimage.esp_image(EFI)
        cls.g, cls.total = hdimage.write(cls.path, 16384, BOOT0, BOOT1,
                                         BOOT2, cls.esp, NODES, NOW)
        with open(cls.path, "rb") as f:
            cls.head = f.read((hdimage.A7_LBA + hdimage.FRONT) * 512)

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def sectors(self, lba, n=1):
        return self.head[lba * 512:(lba + n) * 512]

    def test_mbr_holds_boot0_and_the_two_entries(self):
        mbr = self.sectors(0)
        geo = bui.lba_assist_geometry(self.total)
        self.assertEqual(mbr[:446], BOOT0)
        self.assertEqual(mbr[446:462], bui._part_entry(
            0xEF, 2048, 131072, geo))
        self.assertEqual(mbr[462:478], bui._part_entry(
            0xA7, 133120, self.total - 133120, geo, active=True))
        self.assertEqual(mbr[478:510], bytes(32))
        self.assertEqual(mbr[510:], b"\x55\xaa")

    def test_esp_holds_the_loader(self):
        esp = self.sectors(2048, 131072)
        self.assertEqual(esp, self.esp)
        self.assertEqual(fat32.read_file(esp, "EFI/BOOT/BOOTIA32.EFI"), EFI)

    def test_partition_interior_is_what_disk_i_b_writes(self):
        self.assertEqual(self.sectors(133120), BOOT1)
        for rel in (64, 192):
            self.assertEqual(self.sectors(133120 + rel, 80), BOOT2)
        for rel in (15, 30, 45):
            copy = self.sectors(133120 + rel, 2)
            self.assertEqual(copy[:4], b"dlV3")
            self.assertEqual(struct.unpack_from(">i", copy, 4)[0],
                             133120 + rel)
            self.assertEqual(struct.unpack_from(">ii", copy, 124),
                             (133120 + 64, 133120 + 192))
        with rhap_image.Image(self.path) as img:
            self.assertEqual(img.label["secsize"], 512)
            self.assertEqual(img.label["front"], 320)
            self.assertEqual(img.label["p_base"], 133120)
            self.assertEqual(img.label["p_size"], self.g.fssize)
            self.assertEqual(img.part_start, (133120 + 320) * 512)

    def test_filesystem_reads_back_clean(self):
        self.assertEqual(readback.diff(self.path, NODES), [])
        self.assertEqual(ufs_check.check(self.path), [])


class TestRefusals(unittest.TestCase):
    def write(self, **kw):
        args = dict(boot0=BOOT0, boot1=BOOT1, boot2=BOOT2,
                    esp=hdimage.esp_image(EFI))
        args.update(kw)
        with tempfile.TemporaryDirectory() as tmp:
            hdimage.write(os.path.join(tmp, "d.img"), 16384, args["boot0"],
                          args["boot1"], args["boot2"], args["esp"], NODES,
                          NOW)

    def test_boot1_over_a_sector(self):
        with self.assertRaises(hdimage.ImageError):
            self.write(boot1=b"x" * 513)

    def test_boot2_past_dl_front(self):
        with self.assertRaises(hdimage.ImageError):
            self.write(boot2=b"x" * (128 * 512 + 1))

    def test_esp_of_the_wrong_size(self):
        with self.assertRaises(hdimage.ImageError):
            self.write(esp=b"x" * 512)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run them to see them fail.**
  `cd vm && python -m unittest instmedia.test_label instmedia.test_hdimage -v`.
  Expected: a `TypeError` about `boot0`, and `ModuleNotFoundError` for
  `hdimage`.

- [ ] **Step 3: Implement.** In `label.py`, give `for_filesystem` a
  `boot0` argument and pass it to `label()`:

```python
def for_filesystem(g, front, p_base, ncylinders, name, d_type,
                   boot0=(-1, -1)):
    """The label for a filesystem of ufs_geometry g, as disk -i would write
    it after newfs: partition a covers g.fssize sectors from p_base, and
    carries g's block, fragment and cylinder-group sizes, newfs's default
    density and g's minfree.  boot0 is d_boot0_blkno, as for label()."""
    return label(secsize=g.secsize, ntracks=g.ntrak, nsectors=g.nsect,
                 ncylinders=ncylinders, rpm=g.rpm, front=front,
                 p_base=p_base, p_size=g.fssize, bsize=g.bsize,
                 fsize=g.fsize, cpg=g.cpg, density=4 * g.fsize,
                 minfree=g.minfree, name=name, d_name=name, d_type=d_type,
                 boot0=boot0)
```

`vm/instmedia/hdimage.py`:

```python
"""The hard-disk form of the install media.

    LBA 0       boot0 and the fdisk table: entry 1 is the ESP (0xEF) at
                2048 for 131072 sectors, entry 2 the active 0xA7 partition
                from 133120 to the last sector
    LBA 2048    the ESP: FAT32, 64 MB, holding only /EFI/BOOT/BOOTIA32.EFI
    LBA 133120  the 0xA7 partition as `disk -i -b` lays it out on an fdisk
                disk: boot1 in its first sector, label copies at +15/30/45
                with secsize 512 and absolute p_base and d_boot0_blkno,
                boot2 at +64 and +192, and the UFS from +320 (dl_front)

The disk ends on a cylinder boundary of the LBA-assisted geometry the BIOS
will pick for it, so the 0xA7 entry's end CHS is exact (see the CHS
translation risk in the install-media design).
"""
import build_uefi_image as bui
import fat32
from instmedia import label, ufs, ufs_geometry

SECTOR = 512
ESP_LBA = bui.ESP_LBA               # 2048
# 64 MB: EDK2's FAT driver ignores a FAT32 volume with too few clusters.
ESP_SECTORS = 131072
A7_LBA = ESP_LBA + ESP_SECTORS      # 133120
# diskdev_cmds/disk.tproj/hd.c: a 160 KB front porch, and the two boot2
# copies at 32 KB and 96 KB into the partition, in secsize-512 sectors.
FRONT = 160 * 1024 // SECTOR
BOOT2_BLKNOS = (32 * 1024 // SECTOR, 96 * 1024 // SECTOR)
# disk.c refuses a boot2 copy that runs past dl_front.
BOOT2_MAX_SECTORS = FRONT - BOOT2_BLKNOS[1]
NSECT, NTRAK, RPM = 63, 16, 3600


class ImageError(Exception):
    pass


def esp_image(efi):
    """The ESP's bytes: FAT32 holding the loader at the removable-media path
    UEFI firmware boots from."""
    return fat32.build(ESP_SECTORS, {bui.ESP_BOOT_PATH: efi},
                       label="RHAPEFI", hidden_sectors=ESP_LBA)


def disk_sectors(fs_sectors):
    """Total sectors for at least fs_sectors of UFS, rounded up to a whole
    cylinder of the disk's own LBA-assisted geometry."""
    total = A7_LBA + FRONT + fs_sectors
    while True:
        heads, spt = bui.lba_assist_geometry(total)
        rounded = -(-total // (heads * spt)) * (heads * spt)
        if bui.lba_assist_geometry(rounded) == (heads, spt):
            return rounded
        total = rounded


def write(path, fs_sectors, boot0, boot1, boot2, esp, nodes, now,
          name="RhapsodiOS"):
    """Write the disk image to path; returns (ufs geometry, total sectors).

    boot0, boot1 and boot2 are the booters from the boot apk
    (/usr/standalone/i386/boot0, boot1 and boot), esp is esp_image()'s
    result, and nodes and now go to ufs.write.
    """
    if len(boot1) > SECTOR:
        raise ImageError("boot1 is %d bytes; it must fit in one sector"
                         % len(boot1))
    if len(boot2) > BOOT2_MAX_SECTORS * SECTOR:
        raise ImageError("boot2 is %d bytes; at most %d fit between its "
                         "second copy and dl_front"
                         % (len(boot2), BOOT2_MAX_SECTORS * SECTOR))
    if len(esp) != ESP_SECTORS * SECTOR:
        raise ImageError("the ESP image is %d bytes, not %d"
                         % (len(esp), ESP_SECTORS * SECTOR))
    total = disk_sectors(fs_sectors)
    g = ufs_geometry.geometry(fssize=total - A7_LBA - FRONT,
                              secsize=SECTOR, nsect=NSECT, ntrak=NTRAK,
                              rpm=RPM)
    geo = bui.lba_assist_geometry(total)
    mbr = bytearray(SECTOR)
    mbr[:bui.DISK_BOOTSZ] = boot0[:bui.DISK_BOOTSZ]
    mbr[446:462] = bui._part_entry(bui.EFI_SYSTEM, ESP_LBA, ESP_SECTORS, geo)
    mbr[462:478] = bui._part_entry(bui.FDISK_NEXTNAME, A7_LBA,
                                   total - A7_LBA, geo, active=True)
    mbr[510:512] = b"\x55\xaa"
    lbl = label.for_filesystem(
        g, front=FRONT, p_base=A7_LBA, ncylinders=total // g.spc,
        name=name, d_type="fixed_rw_ide",
        boot0=(A7_LBA + BOOT2_BLKNOS[0], A7_LBA + BOOT2_BLKNOS[1]))
    with open(path, "wb") as f:
        f.truncate(total * SECTOR)
        f.write(mbr)
        f.seek(ESP_LBA * SECTOR)
        f.write(esp)
        f.seek(A7_LBA * SECTOR)
        f.write(boot1)
        label.place(f, lbl, label.DISK_COPIES, A7_LBA)
        for blk in BOOT2_BLKNOS:
            f.seek((A7_LBA + blk) * SECTOR)
            f.write(boot2)
        ufs.write(f, (A7_LBA + FRONT) * SECTOR, g, nodes, now)
    return g, total
```

- [ ] **Step 4: Run the tests.**
  `cd vm && RHAPSODY_MEDIA_DIR=D:/RhapsodiOS/vm python -m unittest instmedia.test_label instmedia.test_hdimage -v`.
  All pass, and `TestAgainstDiskI` says `ok`, not `skipped`.

- [ ] **Step 5: Commit.**

```bash
git add vm/instmedia/label.py vm/instmedia/test_label.py vm/instmedia/hdimage.py vm/instmedia/test_hdimage.py
git commit -m "instmedia: write the hard-disk install media's MBR, ESP and 0xA7 partition as disk -i -b does"
```

### Task 5: The apk repository index

**Files:**
- Create: `vm/instmedia/testapks.py`, `vm/instmedia/apkrepo.py`,
  `vm/instmedia/test_apkrepo.py`

**Interfaces:**
- Produces:
  - `apkrepo.Apk(path, name, version, cpu, info)`.
  - `apkrepo.index(directory) -> {pkgname: Apk}`.
  - `apkrepo.read_pkginfo(path_or_bytes) -> dict`.
  - `apkrepo.open_apk(path_or_bytes) -> tarfile.TarFile`.
  - `apkrepo.member_name(str) -> str` and `apkrepo.is_control(str) -> bool`.
  - `apkrepo.RepoError`.
  - `testapks.make(dir, filename, info, members, dot_slash=True)`, with
    `testapks.tar_bytes`, `pkginfo`, `d`, `f`, `ln`, `hard`, `dev` and `T`.

- [ ] **Step 1: Write the test helper and the failing tests.**
  `vm/instmedia/testapks.py`:

```python
"""Synthetic apks for the install-media builder's tests.

make() writes a gzip'd tar the way rbuild packs one: .PKGINFO first, then
the members, named with a leading "./" unless dot_slash is False (the
bootstrap repository's apks have it, rbuild's newer ones do not).
"""
import gzip
import io
import os
import tarfile

T = 946684800


def pkginfo(name, version="1", arch="universal-apple-rhapsody", **extra):
    lines = ["pkgname = %s" % name, "pkgver = %s" % version,
             "arch = %s" % arch]
    lines += ["%s = %s" % kv for kv in sorted(extra.items())]
    return ("\n".join(lines) + "\n").encode()


def d(path, mode=0o755, mtime=T):
    return ("dir", path, mode, mtime, None)


def f(path, data, mode=0o644, mtime=T, uid=0, gid=0):
    return ("reg", path, mode, mtime, data, uid, gid)


def ln(path, target, mtime=T):
    return ("sym", path, 0o755, mtime, target)


def hard(path, target, mtime=T):
    return ("lnk", path, 0o644, mtime, target)


def dev(path, kind, major, minor, mode=0o640, mtime=T):
    return (kind, path, mode, mtime, (major, minor))


def tar_bytes(info, members, dot_slash=True):
    buf = io.BytesIO()
    prefix = "./" if dot_slash else ""
    with tarfile.open(fileobj=buf, mode="w", format=tarfile.USTAR_FORMAT) as t:
        if info is not None:
            ti = tarfile.TarInfo(".PKGINFO")
            ti.size, ti.mtime = len(info), T
            t.addfile(ti, io.BytesIO(info))
        for m in members:
            kind, path, mode, mtime = m[:4]
            ti = tarfile.TarInfo(prefix + path)
            ti.mode, ti.mtime = mode, mtime
            payload = None
            if kind == "dir":
                ti.type = tarfile.DIRTYPE
            elif kind == "reg":
                payload = m[4]
                ti.size = len(payload)
                ti.uid, ti.gid = m[5], m[6]
            elif kind == "sym":
                ti.type, ti.linkname = tarfile.SYMTYPE, m[4]
            elif kind == "lnk":
                ti.type, ti.linkname = tarfile.LNKTYPE, prefix + m[4]
            else:
                ti.type = tarfile.CHRTYPE if kind == "chr" else tarfile.BLKTYPE
                ti.devmajor, ti.devminor = m[4]
            t.addfile(ti, io.BytesIO(payload) if payload is not None else None)
    return gzip.compress(buf.getvalue(), mtime=0)


def make(directory, filename, info, members=(), dot_slash=True):
    path = os.path.join(directory, filename)
    with open(path, "wb") as out:
        out.write(tar_bytes(info, members, dot_slash))
    return path
```

`vm/instmedia/test_apkrepo.py`:

```python
import os
import tempfile
import unittest

from instmedia import apkrepo, testapks as ta


class TestMemberName(unittest.TestCase):
    def test_strips_dot_slash_and_slashes(self):
        self.assertEqual(apkrepo.member_name("./usr/bin/"), "usr/bin")
        self.assertEqual(apkrepo.member_name("usr/bin"), "usr/bin")
        self.assertEqual(apkrepo.member_name("././a"), "a")
        self.assertEqual(apkrepo.member_name("."), "")
        self.assertEqual(apkrepo.member_name("./"), "")

    def test_control_members(self):
        for name in (".PKGINFO", ".pre-install", ".post-deinstall",
                     ".SIGN.RSA.key.pub"):
            self.assertTrue(apkrepo.is_control(name))
        for name in (".hidden", "PKGINFO", "usr/.PKGINFO"):
            self.assertFalse(apkrepo.is_control(name))


class TestReadPkginfo(unittest.TestCase):
    def test_reads_it_wherever_it_sits(self):
        with tempfile.TemporaryDirectory() as tmp:
            info = ta.pkginfo("grep", "2.1-1", depend="libsystem csu")
            path = ta.make(tmp, "grep.apk", None,
                           [ta.d("usr"), ta.f(".PKGINFO", info)])
            got = apkrepo.read_pkginfo(path)
            with open(path, "rb") as fh:
                self.assertEqual(apkrepo.read_pkginfo(fh.read()), got)
        self.assertEqual(got["pkgname"], "grep")
        self.assertEqual(got["pkgver"], "2.1-1")
        self.assertEqual(got["depend"], "libsystem csu")

    def test_refuses_an_apk_without_one(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = ta.make(tmp, "x.apk", None, [ta.d("usr")])
            with self.assertRaises(apkrepo.RepoError):
                apkrepo.read_pkginfo(path)


class TestIndex(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = self.tmp.name

    def tearDown(self):
        self.tmp.cleanup()

    def add(self, filename, name, arch):
        ta.make(self.dir, filename, ta.pkginfo(name, arch=arch))

    def test_prefers_i386_then_universal(self):
        self.add("libc-1-i386.apk", "libc", "i386-apple-rhapsody")
        self.add("libc-1-universal.apk", "libc", "universal-apple-rhapsody")
        self.add("grep-1-universal.apk", "grep", "universal-apple-rhapsody")
        got = apkrepo.index(self.dir)
        self.assertEqual(sorted(got), ["grep", "libc"])
        self.assertEqual(got["libc"].cpu, "i386")
        self.assertEqual(os.path.basename(got["libc"].path),
                         "libc-1-i386.apk")
        self.assertEqual(got["grep"].cpu, "universal")

    def test_leaves_out_hdrs_and_obj_companions(self):
        self.add("libc-1-universal.apk", "libc", "universal-apple-rhapsody")
        self.add("libc-hdrs-1-universal.apk", "libc-hdrs",
                 "universal-apple-rhapsody")
        self.add("libc-obj-1-universal.apk", "libc-obj",
                 "universal-apple-rhapsody")
        self.assertEqual(sorted(apkrepo.index(self.dir)), ["libc"])

    def test_refuses_a_ppc_only_package(self):
        self.add("pexpert-1-ppc.apk", "drvpexpert", "ppc-apple-rhapsody")
        with self.assertRaisesRegex(apkrepo.RepoError, "only for ppc"):
            apkrepo.index(self.dir)

    def test_refuses_two_builds_for_one_cpu(self):
        self.add("files-1-universal.apk", "files", "universal-apple-rhapsody")
        self.add("files-2-universal.apk", "files", "universal-apple-rhapsody")
        with self.assertRaisesRegex(apkrepo.RepoError, "two universal"):
            apkrepo.index(self.dir)

    def test_refuses_an_unknown_arch(self):
        self.add("x-1.apk", "x", "m68k-next-nextstep")
        with self.assertRaises(apkrepo.RepoError):
            apkrepo.index(self.dir)

    def test_ignores_other_files(self):
        self.add("grep-1-universal.apk", "grep", "universal-apple-rhapsody")
        open(os.path.join(self.dir, "grep-1-universal.apk.src"), "w").close()
        self.assertEqual(sorted(apkrepo.index(self.dir)), ["grep"])


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run them to see them fail.** `cd vm && python -m unittest instmedia.test_apkrepo -v`
  gives `ModuleNotFoundError: No module named 'instmedia.apkrepo'`.

- [ ] **Step 3: Implement** `vm/instmedia/apkrepo.py`:

```python
"""Index a flat directory of rbuild apks.

An apk is a gzip'd tar whose .PKGINFO holds "key = value" lines.  index()
picks one build per pkgname: the i386 one when there is one, else the
universal one, and refuses a package built only for ppc.  -hdrs and -obj
companions are left out, because they repeat files their base package
ships and apk refuses to install a path two packages both claim.
"""
import collections
import io
import os
import tarfile

Apk = collections.namedtuple("Apk", "path name version cpu info")

# Members apk reads as metadata.  Everything else, /.hidden included, is
# data (see src/apk-tools-1/PORTING.md).
CONTROL = (".PKGINFO", ".pre-install", ".post-install", ".pre-deinstall",
           ".post-deinstall")
COMPANION_SUFFIXES = ("-hdrs", "-obj")
CPUS = ("i386", "universal", "ppc")


class RepoError(Exception):
    pass


def member_name(name):
    """A tar member name as a root-relative path: no "./" prefix and no
    leading or trailing slash; "" for the archive's own "." entry."""
    while name.startswith("./"):
        name = name[2:]
    name = name.strip("/")
    return "" if name == "." else name


def is_control(name):
    return name in CONTROL or name.startswith(".SIGN.")


def open_apk(source):
    """A tarfile over source, an apk's path or its bytes."""
    if isinstance(source, bytes):
        return tarfile.open(fileobj=io.BytesIO(source), mode="r:gz")
    return tarfile.open(source, "r:gz")


def parse_pkginfo(text):
    info = {}
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        info[key.strip()] = value.strip()
    return info


def read_pkginfo(source):
    """The .PKGINFO of source (a path or the apk's bytes) as a dict."""
    with open_apk(source) as tar:
        for m in tar:
            if member_name(m.name) == ".PKGINFO" and m.isfile():
                return parse_pkginfo(
                    tar.extractfile(m).read().decode("latin-1"))
    raise RepoError("%s has no .PKGINFO"
                    % (source if isinstance(source, str) else "apk"))


def cpu_of(arch):
    """"i386-apple-rhapsody" -> "i386"; also accepts the bare CPU."""
    cpu = arch.split("-", 1)[0]
    if cpu not in CPUS:
        raise RepoError("unknown arch %r" % arch)
    return cpu


def index(directory):
    """{pkgname: Apk} for the apks in directory, one build per package."""
    builds = collections.defaultdict(dict)
    for fn in sorted(os.listdir(directory)):
        if not fn.endswith(".apk"):
            continue
        path = os.path.join(directory, fn)
        info = read_pkginfo(path)
        name = info.get("pkgname")
        if not name:
            raise RepoError("%s: .PKGINFO has no pkgname" % fn)
        if name.endswith(COMPANION_SUFFIXES):
            continue
        cpu = cpu_of(info.get("arch", ""))
        if cpu in builds[name]:
            raise RepoError("two %s builds of %s: %s and %s"
                            % (cpu, name,
                               os.path.basename(builds[name][cpu].path), fn))
        builds[name][cpu] = Apk(path, name, info.get("pkgver", ""), cpu, info)
    chosen = {}
    for name in sorted(builds):
        for cpu in ("i386", "universal"):
            if cpu in builds[name]:
                chosen[name] = builds[name][cpu]
                break
        else:
            raise RepoError("%s is built only for ppc" % name)
    return chosen
```

- [ ] **Step 4: Run the tests.** All 10 pass.

- [ ] **Step 5: Commit.**

```bash
git add vm/instmedia/testapks.py vm/instmedia/apkrepo.py vm/instmedia/test_apkrepo.py
git commit -m "instmedia: index a directory of apks, one build per package"
```

### Task 6: Lay apk payloads out as a node tree

**Files:**
- Create: `vm/instmedia/rootfs.py`, `vm/instmedia/test_rootfs.py`

**Interfaces:**
- Consumes: `apkrepo.open_apk`, `member_name`, `is_control`;
  `ufs_extract.Node`.
- Produces:
  - `rootfs.Tree(root_mtime=0)`, with these methods:
    - `.add(path, kind, mode, uid, gid, mtime, data, owner)` and
      `.put(node)`
    - `.get(path) -> Node|None` and `.data(path) -> bytes`
    - `.resolve(path) -> str`
    - `.nodes() -> [Node]`, with `/` first and parents first
    - `.newest_mtime() -> int`
    - `.conflicts`, a list of `rootfs.Conflict(path, first, second)`
  - `rootfs.add_apk(tree, path_or_bytes, owner)`.
  - `rootfs.TreeError`.

- [ ] **Step 1: Write the failing tests.** `vm/instmedia/test_rootfs.py`:

```python
import os
import tempfile
import unittest

from ufs_extract import Node
from instmedia import rootfs, testapks as ta

T = ta.T
FILES = [ta.d("private"), ta.d("private/etc"), ta.ln("etc", "private/etc"),
         ta.f(".hidden", b"mach\n"), ta.d("usr"),
         ta.d("private/dev"), ta.dev("private/dev/hd0a", "blk", 3, 0),
         ta.dev("private/dev/rhd0a", "chr", 15, 0),
         ta.f("private/etc/motd", b"hi\n")]


def tree_of(*apks):
    """A Tree holding the given (owner, members, dot_slash) apks."""
    tree = rootfs.Tree()
    for owner, members, dot_slash in apks:
        rootfs.add_apk(tree, ta.tar_bytes(ta.pkginfo(owner), members,
                                          dot_slash), owner)
    return tree


class TestAddApk(unittest.TestCase):
    def test_every_kind_lands_with_its_metadata(self):
        tree = tree_of(("files", FILES, True))
        self.assertEqual(tree.get("/etc"),
                         Node("/etc", "lnk", 0o755, 0, 0, T, "private/etc"))
        self.assertEqual(tree.get("/private/dev/hd0a").data, (3, 0))
        self.assertEqual(tree.get("/private/dev/hd0a").kind, "blk")
        self.assertEqual(tree.get("/private/dev/rhd0a").kind, "chr")
        self.assertEqual(tree.get("/private/etc/motd").mode, 0o644)
        self.assertEqual(tree.conflicts, [])

    def test_control_members_are_skipped_and_dot_files_kept(self):
        members = [ta.f(".post-install", b"#!/bin/sh\n", 0o755),
                   ta.f(".hidden", b"x")]
        tree = tree_of(("files", members, True))
        self.assertIsNone(tree.get("/.PKGINFO"))
        self.assertIsNone(tree.get("/.post-install"))
        self.assertEqual(tree.get("/.hidden").data, b"x")

    def test_names_without_dot_slash_read_the_same(self):
        a = tree_of(("files", FILES, True)).nodes()
        b = tree_of(("files", FILES, False)).nodes()
        self.assertEqual(a, b)

    def test_a_symlinked_parent_is_followed(self):
        tree = tree_of(("files", FILES, True),
                       ("openssh", [ta.d("etc"), ta.f("etc/ssh_config", b"c")],
                        False))
        self.assertEqual(tree.get("/private/etc/ssh_config").data, b"c")
        self.assertIsNone(tree.get("/etc/ssh_config"))
        self.assertEqual(tree.get("/etc").kind, "lnk")
        self.assertEqual(tree.conflicts, [])

    def test_missing_parents_are_made(self):
        tree = tree_of(("zlib", [ta.f("usr/lib/libz.a", b"z")], False))
        self.assertEqual(tree.get("/usr").kind, "dir")
        self.assertEqual(tree.get("/usr/lib").kind, "dir")

    def test_hard_link_names_its_target(self):
        tree = tree_of(("kernel", [ta.f("mach_kernel", b"k" * 100, 0o444),
                                   ta.d("private"), ta.d("private/tftpboot"),
                                   ta.hard("private/tftpboot/mach_kernel",
                                           "mach_kernel")], True))
        self.assertEqual(tree.get("/private/tftpboot/mach_kernel").data,
                         "/mach_kernel")
        self.assertEqual(tree.data("/private/tftpboot/mach_kernel"),
                         b"k" * 100)

    def test_hard_link_to_nothing_is_refused(self):
        with self.assertRaises(rootfs.TreeError):
            tree_of(("x", [ta.hard("b", "a")], False))

    def test_extracting_through_a_dangling_symlink_is_refused(self):
        with self.assertRaises(rootfs.TreeError):
            tree_of(("files", [ta.ln("usr", "nowhere/at/all")], False),
                    ("x", [ta.f("usr/bin/x", b"x")], False))


class TestConflicts(unittest.TestCase):
    def test_a_file_two_packages_claim_is_reported_and_first_kept(self):
        tree = tree_of(("files", FILES, True),
                       ("other", [ta.f("private/etc/motd", b"no\n")], False))
        self.assertEqual(tree.conflicts, [rootfs.Conflict(
            "/private/etc/motd", "files", "other")])
        self.assertEqual(tree.data("/private/etc/motd"), b"hi\n")

    def test_a_claim_through_a_symlink_is_reported_at_the_real_path(self):
        tree = tree_of(("files", FILES, True),
                       ("other", [ta.f("etc/motd", b"no\n")], False))
        self.assertEqual([c.path for c in tree.conflicts],
                         ["/private/etc/motd"])

    def test_shared_directories_merge(self):
        tree = tree_of(("a", [ta.d("usr"), ta.d("usr/bin"),
                              ta.f("usr/bin/a", b"a")], False),
                       ("b", [ta.d("usr"), ta.d("usr/bin"),
                              ta.f("usr/bin/b", b"b")], False))
        self.assertEqual(tree.conflicts, [])
        self.assertEqual(tree.data("/usr/bin/b"), b"b")

    def test_a_directory_over_a_file_is_a_conflict(self):
        tree = tree_of(("a", [ta.f("x", b"a")], False),
                       ("b", [ta.d("x")], False))
        self.assertEqual(tree.conflicts, [rootfs.Conflict("/x", "a", "b")])
        self.assertEqual(tree.get("/x").kind, "reg")

    def test_a_file_over_a_directory_is_a_conflict(self):
        tree = tree_of(("a", [ta.d("x")], False),
                       ("b", [ta.f("x", b"b")], False))
        self.assertEqual(tree.conflicts, [rootfs.Conflict("/x", "a", "b")])


class TestPutAndNodes(unittest.TestCase):
    def test_put_replaces_and_makes_parents(self):
        tree = tree_of(("files", FILES, True))
        tree.put(Node("/etc/motd", "reg", 0o600, 0, 0, T + 5, b"new\n"))
        tree.put(Node("/Local/Library/Receipts", "dir", 0o755, 0, 0, T, None))
        self.assertEqual(tree.get("/private/etc/motd"),
                         Node("/private/etc/motd", "reg", 0o600, 0, 0,
                              T + 5, b"new\n"))
        self.assertEqual(tree.get("/Local/Library").kind, "dir")
        self.assertEqual(tree.conflicts, [])

    def test_put_refuses_a_file_over_a_directory(self):
        tree = tree_of(("files", FILES, True))
        with self.assertRaises(rootfs.TreeError):
            tree.put(Node("/usr", "reg", 0o644, 0, 0, T, b"x"))

    def test_nodes_put_each_directory_before_its_contents(self):
        tree = tree_of(("z", [ta.f("b/c/d", b"x"), ta.f("a", b"y"),
                              ta.f("b-c", b"z")], False))
        paths = [n.path for n in tree.nodes()]
        self.assertEqual(paths[0], "/")
        for i, p in enumerate(paths[1:], 1):
            self.assertIn(os.path.dirname(p), paths[:i])
        self.assertEqual(paths, sorted(paths, key=rootfs._sort_key))

    def test_newest_mtime(self):
        tree = tree_of(("z", [ta.f("a", b"y", mtime=T + 99)], False))
        self.assertEqual(tree.newest_mtime(), T + 99)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run them to see them fail** (`ModuleNotFoundError`).

- [ ] **Step 3: Implement** `vm/instmedia/rootfs.py`:

```python
"""Build a node tree from apk payloads, as `apk add` would lay them down.

Control members (.PKGINFO and the install scripts) are skipped; everything
else is data.  A member whose parent directory is a symlink in the tree
goes where the symlink leads, as it would when apk extracts into a real
filesystem: `files` makes etc a link to private/etc, so a package's etc/foo
lands in /private/etc/foo.  Directories two packages share merge; any other
path two packages both claim is recorded in Tree.conflicts, because apk add
would refuse the second package, and the first package's node is kept.
Install scripts are not run.
"""
import collections
import posixpath
import tarfile

from ufs_extract import Node
from instmedia import apkrepo

Conflict = collections.namedtuple("Conflict", "path first second")
OVERLAY = "(overlay)"
MAX_LINKS = 32


class TreeError(Exception):
    pass


def _sort_key(path):
    return () if path == "/" else tuple(path[1:].split("/"))


class Tree:
    def __init__(self, root_mtime=0):
        self._nodes = {"/": Node("/", "dir", 0o755, 0, 0, root_mtime, None)}
        self._owner = {"/": None}
        self.conflicts = []

    def get(self, path):
        return self._nodes.get(path)

    def data(self, path):
        """The contents of the regular file at path (links followed)."""
        node = self._nodes.get(self.resolve(path))
        if node is not None and node.kind == "hlink":
            node = self._nodes[node.data]
        if node is None or node.kind != "reg":
            raise TreeError("%s is not a regular file in the tree" % path)
        return node.data

    def nodes(self):
        """Every node, "/" first and each directory before its contents."""
        return [self._nodes[p] for p in sorted(self._nodes, key=_sort_key)]

    def newest_mtime(self):
        return max(n.mtime for n in self._nodes.values())

    def resolve(self, path):
        """path with every symlink along it followed, the last one too."""
        parent = self._dir(posixpath.dirname(path), None, 0, False)
        return self._follow(posixpath.join(parent, posixpath.basename(path)))

    def _follow(self, path, depth=0):
        node = self._nodes.get(path)
        if node is None or node.kind != "lnk":
            return path
        if depth > MAX_LINKS:
            raise TreeError("too many symlinks resolving %s" % path)
        target = posixpath.normpath(posixpath.join(
            posixpath.dirname(path), node.data))
        parent = self._dir(posixpath.dirname(target), None, 0, False)
        return self._follow(posixpath.join(parent,
                                           posixpath.basename(target)),
                            depth + 1)

    def _dir(self, path, owner, mtime, create):
        """The real path of directory path, following symlinks.  Missing
        directories are made when create is set, else refused."""
        real = "/"
        for part in [p for p in path.split("/") if p]:
            here = posixpath.join(real, part)
            real = self._follow(here)
            node = self._nodes.get(real)
            if node is None:
                # apk cannot extract through a symlink to nowhere either.
                if not create or real != here:
                    raise TreeError("%s: no directory %s" % (path, real))
                self._nodes[real] = Node(real, "dir", 0o755, 0, 0, mtime,
                                         None)
                self._owner[real] = owner
            elif node.kind != "dir":
                raise TreeError("%s: %s is a %s, not a directory"
                                % (path, real, node.kind))
        return real

    def add(self, path, kind, mode, uid, gid, mtime, data, owner):
        """Add a member of owner's apk at path ("/"-rooted)."""
        parent = self._dir(posixpath.dirname(path), owner, mtime, True)
        full = posixpath.join(parent, posixpath.basename(path))
        if kind == "hlink":
            data = self.resolve(data)
            target = self._nodes.get(data)
            if target is None or target.kind != "reg":
                raise TreeError("%s: hard link to %s, which is not a "
                                "regular file" % (path, data))
        existing = self._nodes.get(full)
        if existing is not None:
            if kind == "dir" and self._nodes.get(
                    self._follow(full), existing).kind == "dir":
                return
            if not (kind != "dir" and existing.kind != "dir"
                    and self._owner[full] == owner):
                self.conflicts.append(Conflict(full, self._owner[full],
                                               owner))
                return
        self._nodes[full] = Node(full, kind, mode, uid, gid, mtime, data)
        self._owner[full] = owner

    def put(self, node):
        """Place node, replacing whatever is at its path; the overlay's way
        in.  Missing parents are made."""
        parent = self._dir(posixpath.dirname(node.path), OVERLAY,
                           node.mtime, True)
        full = posixpath.join(parent, posixpath.basename(node.path))
        existing = self._nodes.get(full)
        if existing is not None and (existing.kind == "dir") != (
                node.kind == "dir"):
            raise TreeError("overlay %s would replace a %s with a %s"
                            % (full, existing.kind, node.kind))
        self._nodes[full] = node._replace(path=full)
        self._owner[full] = OVERLAY


def add_apk(tree, source, owner):
    """Add every data member of the apk at source (a path or its bytes)."""
    with apkrepo.open_apk(source) as tar:
        for m in tar:
            name = apkrepo.member_name(m.name)
            if not name or apkrepo.is_control(name):
                continue
            path = "/" + name
            mode = m.mode & 0o7777
            if m.isdir():
                kind, data = "dir", None
            elif m.isreg():
                kind, data = "reg", tar.extractfile(m).read()
            elif m.issym():
                kind, data = "lnk", m.linkname
            elif m.islnk():
                kind, data = "hlink", "/" + apkrepo.member_name(m.linkname)
            elif m.ischr() or m.isblk():
                kind = "chr" if m.ischr() else "blk"
                data = (m.devmajor, m.devminor)
            else:
                raise TreeError("%s: %s has unsupported tar type %r"
                                % (owner, name, m.type))
            tree.add(path, kind, mode, m.uid, m.gid, int(m.mtime), data,
                     owner)
```

- [ ] **Step 4: Run the tests.** All 17 pass.

- [ ] **Step 5: Commit.**

```bash
git add vm/instmedia/rootfs.py vm/instmedia/test_rootfs.py
git commit -m "instmedia: lay apk payloads out as a node tree the way apk add would"
```

### Task 7: Collect the apks into one repository

**Files:**
- Create: `vm/instmedia/collect.py`, `vm/instmedia/test_collect.py`

**Interfaces:**
- Consumes: `apkrepo.open_apk`, `read_pkginfo`; `rhap_image.Image`.
- Produces:
  - The CLI `python -m instmedia.collect OUTDIR --image IMAGE [--add DIR ...]`.
  - `collect.merge(*sources) -> {filename: bytes}`, where each source is a
    list of `(filename, bytes)`.
  - `collect.image_apks(image)` and `collect.dir_apks(dir)`.
  - `collect.CollectError`.

- [ ] **Step 1: Write the failing tests.** `vm/instmedia/test_collect.py`:

```python
import os
import unittest

from instmedia import collect, testapks as ta

IMAGE = os.environ.get("RHAPSODY_BOOTSTRAP_IMAGE")


def apk(name, pkgname, arch="universal-apple-rhapsody", body=b"x"):
    return (name, ta.tar_bytes(ta.pkginfo(pkgname, arch=arch),
                               [ta.f("usr/share/" + name, body)]))


class TestMerge(unittest.TestCase):
    def test_a_later_source_replaces_every_build_of_a_package(self):
        base = [apk("files-1-universal.apk", "files"),
                apk("grep-1-universal.apk", "grep")]
        added = [apk("files-1-universal.apk", "files", body=b"new"),
                 apk("kernel-1-i386.apk", "kernel", "i386-apple-rhapsody")]
        got = collect.merge(base, added)
        self.assertEqual(sorted(got), ["files-1-universal.apk",
                                       "grep-1-universal.apk",
                                       "kernel-1-i386.apk"])
        self.assertEqual(got["files-1-universal.apk"], added[0][1])

    def test_a_renamed_rebuild_drops_the_old_file(self):
        got = collect.merge([apk("files-1-universal.apk", "files")],
                            [apk("files-2-universal.apk", "files")])
        self.assertEqual(sorted(got), ["files-2-universal.apk"])

    def test_damaged_apks_are_refused(self):
        name, data = apk("grep-1-universal.apk", "grep", body=b"y" * 5000)
        with self.assertRaisesRegex(collect.CollectError, "damaged"):
            collect.merge([(name, data[:len(data) // 2])])

    def test_the_same_filename_twice_in_one_source_is_refused(self):
        with self.assertRaises(collect.CollectError):
            collect.merge([apk("a.apk", "a"), apk("a.apk", "b")])


@unittest.skipUnless(IMAGE, "set RHAPSODY_BOOTSTRAP_IMAGE to the "
                     "bootstrapped guest image to read its repository")
class TestImage(unittest.TestCase):
    def test_reads_the_universal_bootstrap_apks(self):
        got = collect.image_apks(IMAGE)
        names = [n for n, _ in got]
        self.assertEqual(len(names), 68)
        self.assertIn("libsystem-25.1-2-universal.apk", names)
        self.assertTrue(all(n.endswith("-universal.apk") for n in names))
        collect.merge(got)
```

- [ ] **Step 2: Run them to see them fail** (`ModuleNotFoundError`).

- [ ] **Step 3: Implement** `vm/instmedia/collect.py`:

```python
"""Gather the apks the install media is built from into one directory.

    python -m instmedia.collect OUTDIR --image IMAGE [--add DIR ...]

Takes the universal apks in IMAGE's /build/repo, the bootstrapped build
guest's repository, read in place without writing the image.  Then every
apk in each --add directory, in order; an added apk replaces the image's
builds, and any earlier added build, of the same package.  The image's thin
-i386 bootstrap builds are left out: the universal pass rebuilt those, and
phase 2's apk-installed root was proven with the universal ones.

Every apk is decompressed in full on the way in, so a damaged one is
refused rather than copied: the image's filesystem has known DUP blocks.
"""
import argparse
import os
import sys
import tarfile
import zlib

import rhap_image
from instmedia import apkrepo

REPO = "/build/repo"


class CollectError(Exception):
    pass


def verify(name, data):
    """The apk's pkgname, after reading every member of it."""
    try:
        with apkrepo.open_apk(data) as tar:
            for m in tar:
                if m.isreg():
                    tar.extractfile(m).read()
        return apkrepo.read_pkginfo(data)["pkgname"]
    except (OSError, EOFError, tarfile.TarError, zlib.error, KeyError,
            apkrepo.RepoError) as e:
        raise CollectError("%s is damaged: %s" % (name, e))


def image_apks(image):
    """[(filename, bytes)] for the universal apks in image's repository."""
    out = []
    with rhap_image.Image(image) as img:
        repo = img.resolve(REPO)
        if repo is None:
            raise CollectError("%s has no %s" % (image, REPO))
        for name, ino, _ in sorted(img.listdir(REPO)):
            if name.endswith("-universal.apk"):
                out.append((name, img.read_file(ino)))
    return out


def dir_apks(directory):
    out = []
    for name in sorted(os.listdir(directory)):
        if name.endswith(".apk"):
            with open(os.path.join(directory, name), "rb") as f:
                out.append((name, f.read()))
    return out


def merge(*sources):
    """{filename: bytes}: each source's apks replace earlier sources'
    apks of the same package."""
    chosen = {}                 # pkgname -> [(filename, bytes)]
    for source in sources:
        mine = {}
        for name, data in source:
            mine.setdefault(verify(name, data), []).append((name, data))
        chosen.update(mine)
    out = {}
    for builds in chosen.values():
        for name, data in builds:
            if name in out:
                raise CollectError("two apks named %s" % name)
            out[name] = data
    return out


def main(argv):
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("outdir")
    p.add_argument("--image", required=True)
    p.add_argument("--add", action="append", default=[])
    a = p.parse_args(argv[1:])
    try:
        if os.path.exists(a.outdir) and os.listdir(a.outdir):
            raise CollectError("%s is not empty" % a.outdir)
        apks = merge(image_apks(a.image), *[dir_apks(d) for d in a.add])
    except CollectError as e:
        print("instmedia.collect: %s" % e, file=sys.stderr)
        return 1
    os.makedirs(a.outdir, exist_ok=True)
    for name in sorted(apks):
        with open(os.path.join(a.outdir, name), "wb") as f:
            f.write(apks[name])
    print("%s: %d apks" % (a.outdir, len(apks)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
```

- [ ] **Step 4: Run the tests, the image one included.**
  `cd vm && RHAPSODY_BOOTSTRAP_IMAGE=D:/RhapsodiOS/vm/work/rhap-i386-bootstrapped.img python -m unittest instmedia.test_collect -v`.
  All 5 pass; `TestImage` says `ok`. It only reads the image.

- [ ] **Step 5: Commit.**

```bash
git add vm/instmedia/collect.py vm/instmedia/test_collect.py
git commit -m "instmedia: collect the bootstrap image's apks and newer builds into one repository"
```

### Task 8: Compose the live root and the pre-installed root

**Files:**
- Create: `vm/instmedia/testconfig.py`, `vm/instmedia/live.py`,
  `vm/instmedia/test_live.py`

**Interfaces:**
- Consumes:
  - `rootfs.Tree` and `rootfs.add_apk`
  - `apkrepo.index`'s result
  - the `cdis` apk's paths from Task 2: `/private/etc/rc.cdrom.hidden` and
    `/System/Installation/CDIS/templates/{fstab,hostconfig,Instance0.table}`
- Produces:
  - `live.compose(apks, esp, preinstalled=False, password_hash=None) -> (nodes, conflicts)`
  - `live.install_order(apks) -> [Apk]`, with `files` first
  - `live.render(template, disk)` and
    `live.set_root_password(passwd, crypted)`
  - the constants `live.INSTALLATION`, `CDIS`, `TEMPLATES`,
    `SYSTEM_TABLE`, `FSTAB`, `HOSTCONFIG`, `MASTER_PASSWD`, `RC_CDROM` and
    `RC_CDROM_INERT`
  - `live.ComposeError`
  - `testconfig.TEST_PASSWORD` and `TEST_PASSWORD_HASH`

- [ ] **Step 1: Write the failing tests.** `vm/instmedia/test_live.py`:

```python
import gzip
import os
import tempfile
import unittest

from instmedia import apkrepo, live, testapks as ta

PASSWD = (b"##\n# comment\n##\nnobody:*:-2:-2::0:0:Unprivileged:/:/dev/null\n"
          b"root:*:0:0::0:0:System Administrator:/:/bin/tcsh\n")
TABLE = (b'"Boot Drivers" = "EISABus PCIBus PS2Keyboard EIDE AHCI";\n'
         b'"Active Drivers" = "VGA NE2K";\n'
         b'"Kernel Flags" = "rootdev=@DISK@a";\n')
FSTAB = b"/dev/@DISK@a\t/\tufs\trw\t1 1\n"
HOSTCONFIG = b"APPLETALK=-NO-\nSSHSERVER=-YES-\n"
RC_CDROM = b"#!/usr/bin/perl -w\nprint 'installer';\n"


def make_repo(directory):
    """files, cdis and one package that installs through etc/."""
    ta.make(directory, "files-1-universal.apk", ta.pkginfo("files"), [
        ta.d("private"), ta.d("private/etc"), ta.ln("etc", "private/etc"),
        ta.d("usr"), ta.ln("usr/Devices", "../private/Devices"),
        ta.f("private/etc/master.passwd", PASSWD, 0o600),
        ta.f("private/etc/hostconfig", b"APPLETALK=-YES-\n"),
        ta.d("System"), ta.d("private/Drivers"),
        ta.d("private/Drivers/i386"),
        ta.d("private/Drivers/i386/System.config")])
    cdis = "System/Installation/CDIS/"
    ta.make(directory, "cdis-156.1-universal.apk", ta.pkginfo("cdis"), [
        ta.d("System/Installation"), ta.d("System/Installation/CDIS"),
        ta.f(cdis + "pickdisk", b"pickdisk", 0o555),
        ta.d(cdis + "templates"),
        ta.f(cdis + "templates/fstab", FSTAB, 0o444),
        ta.f(cdis + "templates/Instance0.table", TABLE, 0o444),
        ta.f(cdis + "templates/hostconfig", HOSTCONFIG, 0o444),
        ta.f("private/etc/rc.cdrom.hidden", RC_CDROM, 0o555),
        ta.f("private/etc/rc.cdrom.x86", b"1;\n", 0o444),
        ta.d("private/var"), ta.d("private/var/tmp"),
        ta.d("private/var/tmp/mnta")], dot_slash=False)
    ta.make(directory, "aaa-1-universal.apk", ta.pkginfo("aaa"),
            [ta.f("etc/aaa.conf", b"a")], dot_slash=False)


class TestRender(unittest.TestCase):
    def test_render_and_password(self):
        self.assertEqual(live.render(FSTAB, "hd0"),
                         b"/dev/hd0a\t/\tufs\trw\t1 1\n")
        got = live.set_root_password(PASSWD, "rhME8brSxdukA")
        self.assertIn(b"\nroot:rhME8brSxdukA:0:0::0:0:System Administrator"
                      b":/:/bin/tcsh\n", got)
        self.assertIn(b"nobody:*:", got)
        with self.assertRaises(live.ComposeError):
            live.set_root_password(b"nobody:*:1:1\n", "x")


class TestCompose(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        make_repo(cls.tmp.name)
        cls.apks = apkrepo.index(cls.tmp.name)
        cls.esp = b"E" * 4096
        nodes, cls.conflicts = live.compose(cls.apks, cls.esp)
        cls.live = {n.path: n for n in nodes}
        nodes, _ = live.compose(cls.apks, cls.esp, preinstalled=True,
                                password_hash="rhME8brSxdukA")
        cls.pre = {n.path: n for n in nodes}

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def test_files_goes_first_so_packages_follow_its_links(self):
        self.assertEqual(live.install_order(self.apks)[0].name, "files")
        self.assertEqual(self.live["/private/etc/aaa.conf"].data, b"a")
        self.assertEqual(self.conflicts, [])

    def test_live_overlay_makes_cdis_live(self):
        rc = self.live[live.RC_CDROM]
        self.assertEqual((rc.kind, rc.mode, rc.data), ("reg", 0o755, RC_CDROM))
        self.assertEqual(self.live[live.RC_CDROM_INERT].data, RC_CDROM)
        self.assertEqual(self.live[live.SYSTEM_TABLE].data,
                         live.render(TABLE, "hd1"))
        self.assertEqual(self.live["/private/var/tmp/mnta"].kind, "dir")

    def test_live_carries_every_apk_and_the_esp(self):
        for fn in os.listdir(self.tmp.name):
            with open(os.path.join(self.tmp.name, fn), "rb") as f:
                self.assertEqual(
                    self.live["/System/Installation/Packages/" + fn].data,
                    f.read())
        self.assertEqual(gzip.decompress(
            self.live["/System/Installation/esp.img.gz"].data), self.esp)

    def test_preinstalled_renders_the_templates_for_hd0(self):
        self.assertEqual(self.pre[live.FSTAB].data,
                         b"/dev/hd0a\t/\tufs\trw\t1 1\n")
        self.assertEqual(self.pre[live.SYSTEM_TABLE].data,
                         live.render(TABLE, "hd0"))
        self.assertEqual(self.pre[live.HOSTCONFIG].data, HOSTCONFIG)
        passwd = self.pre[live.MASTER_PASSWD]
        self.assertEqual(passwd.mode, 0o600)
        self.assertIn(b"\nroot:rhME8brSxdukA:", passwd.data)

    def test_preinstalled_does_not_start_the_installer(self):
        self.assertNotIn(live.RC_CDROM, self.pre)
        self.assertNotIn("/System/Installation/Packages", self.pre)
        self.assertNotIn("/System/Installation/esp.img.gz", self.pre)
        self.assertNotIn(live.FSTAB, self.live)

    def test_every_node_takes_a_time_from_the_apks(self):
        for n in self.live.values():
            self.assertLessEqual(n.mtime, ta.T)

    def test_no_files_apk_is_refused(self):
        with self.assertRaises(live.ComposeError):
            live.compose({k: v for k, v in self.apks.items()
                          if k != "files"}, self.esp)

    def test_preinstalled_needs_a_password(self):
        with self.assertRaises(live.ComposeError):
            live.compose(self.apks, self.esp, preinstalled=True)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run them to see them fail** (`ModuleNotFoundError`).

- [ ] **Step 3: Implement.** Write `vm/instmedia/testconfig.py`. If the
  guest printed a different hash in Task 3 Step 4, use that one:

```python
"""The pre-installed image's fixed test password.

The hash is precomputed, because Python 3.13 has no crypt module: it is
crypt("rhapsodi", "rh"), traditional DES, from Git Bash's perl, and
Rhapsody's own crypt() gives the same string (checked on the build guest
with perl 5.004).  DES crypt reads only the first 8 characters.
"""
TEST_PASSWORD = "rhapsodi"
TEST_PASSWORD_HASH = "rhME8brSxdukA"
```

`vm/instmedia/live.py`:

```python
"""Compose the install media's root: every apk, then the live overlay.

The apks go in the order the installer installs them, files first so the
etc, var and tmp links exist, then the rest by package name.  The cdis apk
brings the installer: /System/Installation/CDIS and its tools, the
installer script parked inert as /private/etc/rc.cdrom.hidden, and
/private/var/tmp/mnta, where it mounts the target.  The live overlay adds
only:

    /private/etc/rc.cdrom        rc.cdrom.hidden, made live; rc and rc.boot
                                 run it when /System/Installation is there
    .../System.config/Instance0.table
                                 CDIS's template for hd1, the disk the
                                 media is in the QEMU harness
    /System/Installation/Packages/*.apk  every apk the root was made from
    /System/Installation/esp.img.gz      the ESP the installer writes

With preinstalled set there is no overlay.  Instead the installed-system
templates are rendered for hd0, and root gets the test password, so the
image boots as an installed disk.  /System/Installation is there too, from
the cdis apk, but without /private/etc/rc.cdrom rc starts the system.
"""
import gzip
import os

from ufs_extract import Node
from instmedia import rootfs

INSTALLATION = "/System/Installation"
CDIS = INSTALLATION + "/CDIS"
TEMPLATES = CDIS + "/templates"
SYSTEM_TABLE = "/private/Drivers/i386/System.config/Instance0.table"
FSTAB = "/private/etc/fstab"
HOSTCONFIG = "/private/etc/hostconfig"
MASTER_PASSWD = "/private/etc/master.passwd"
RC_CDROM = "/private/etc/rc.cdrom"
RC_CDROM_INERT = RC_CDROM + ".hidden"
MEDIA_DISK = "hd1"
INSTALLED_DISK = "hd0"


class ComposeError(Exception):
    pass


def render(template, disk):
    """A template with its device name filled in."""
    return template.replace(b"@DISK@", disk.encode("ascii"))


def set_root_password(passwd, crypted):
    """master.passwd's text with root's password field replaced."""
    lines = passwd.split(b"\n")
    for i, line in enumerate(lines):
        fields = line.split(b":")
        if fields[0] == b"root" and len(fields) > 1:
            fields[1] = crypted.encode("ascii")
            lines[i] = b":".join(fields)
            return b"\n".join(lines)
    raise ComposeError("master.passwd has no root entry")


def install_order(apks):
    if "files" not in apks:
        raise ComposeError("no files apk: it makes the root's links and "
                           "/dev")
    return [apks["files"]] + [apks[n] for n in sorted(apks) if n != "files"]


def compose(apks, esp, preinstalled=False, password_hash=None):
    """(nodes, conflicts) for apks, apkrepo.index()'s result.

    esp is the ESP image hdimage writes, stored gzip'd for the installer.
    """
    order = install_order(apks)
    tree = rootfs.Tree()
    for apk in order:
        rootfs.add_apk(tree, apk.path, apk.name)
    now = tree.newest_mtime()
    tree.put(tree.get("/")._replace(mtime=now))

    def template(name):
        return tree.data(TEMPLATES + "/" + name)

    def put_file(path, data, mode=0o644):
        tree.put(Node(path, "reg", mode, 0, 0, now, data))

    if preinstalled:
        if password_hash is None:
            raise ComposeError("a pre-installed image needs a password hash")
        put_file(FSTAB, render(template("fstab"), INSTALLED_DISK))
        put_file(SYSTEM_TABLE,
                 render(template("Instance0.table"), INSTALLED_DISK))
        put_file(HOSTCONFIG, template("hostconfig"))
        put_file(MASTER_PASSWD,
                 set_root_password(tree.data(MASTER_PASSWD), password_hash),
                 0o600)
    else:
        put_file(RC_CDROM, tree.data(RC_CDROM_INERT), 0o755)
        put_file(SYSTEM_TABLE, render(template("Instance0.table"), MEDIA_DISK))
        tree.put(Node(INSTALLATION + "/Packages", "dir", 0o755, 0, 0, now,
                      None))
        for apk in order:
            with open(apk.path, "rb") as f:
                put_file("%s/Packages/%s" % (INSTALLATION,
                                             os.path.basename(apk.path)),
                         f.read())
        put_file(INSTALLATION + "/esp.img.gz",
                 gzip.compress(esp, compresslevel=9, mtime=0))
    return tree.nodes(), list(tree.conflicts)
```

- [ ] **Step 4: Run the tests.** All 9 pass.

- [ ] **Step 5: Commit.**

```bash
git add vm/instmedia/testconfig.py vm/instmedia/live.py vm/instmedia/test_live.py
git commit -m "instmedia: compose the live root, with CDIS made live, and the pre-installed root"
```

### Task 9: The builder CLI

**Files:**
- Create: `vm/instmedia/build.py`, `vm/instmedia/test_build.py`

**Interfaces:**
- Consumes: everything from Tasks 4 to 8, plus `readback.diff`,
  `ufs_check.check` and `space.NoSpace`.
- Produces:
  - the CLI `python -m instmedia.build --repo DIR --efi FILE --out IMAGE [--preinstalled] [--fs-mb N]`
  - `build.build(repo, efi_path, out, preinstalled=False, fs_mb=None) -> (napks, nnodes, geometry, total_sectors)`
  - `build.check_tree`, `check_dev`, `boot_drivers`, `fs_sectors` and
    `BuildError`
  - the constants `DEVICES_TABLE`, `NETWORK_DRIVER` and `CDIS_NEEDS`

- [ ] **Step 1: Write the failing tests.** `vm/instmedia/test_build.py`:

```python
import contextlib
import io
import os
import tempfile
import unittest

import rhap_image
from ufs_extract import Node
from instmedia import build, live, testapks as ta, test_live

BOOT_DRIVERS = ("EISABus", "PCIBus", "PS2Keyboard", "EIDE", "AHCI")
CDIS = "System/Installation/CDIS/"


def make_bootable_repo(directory, drivers=BOOT_DRIVERS + ("NE2K",),
                       driver_loader=True, devices_link=True, extra=()):
    """test_live's repo plus what a bootable root must have."""
    test_live.make_repo(directory)
    ta.make(directory, "boot-64-i386.apk",
            ta.pkginfo("boot", "64", "i386-apple-rhapsody"), [
                ta.f("usr/standalone/i386/boot0", b"\x33" * 446),
                ta.f("usr/standalone/i386/boot1", b"\x44" * 510 + b"\x55\xaa"),
                ta.f("usr/standalone/i386/boot", b"B" * 30000),
                ta.f("usr/standalone/i386/sarld", b"S" * 1000)],
            dot_slash=False)
    ta.make(directory, "kernel-154.5.1-i386.apk",
            ta.pkginfo("kernel", "154.5.1", "i386-apple-rhapsody"), [
                ta.f("mach_kernel", b"K" * 70000, 0o444), ta.d("private"),
                ta.d("private/tftpboot"),
                ta.hard("private/tftpboot/mach_kernel", "mach_kernel")])
    for name in drivers:
        ta.make(directory, "drv%s-1-i386.apk" % name.lower(),
                ta.pkginfo("drv" + name.lower(), "1", "i386-apple-rhapsody"),
                [ta.f("private/Drivers/i386/%s.config/%s_reloc"
                      % (name, name), name.encode() * 100)], dot_slash=False)
    if devices_link:
        ta.make(directory, "system-config-46-universal.apk",
                ta.pkginfo("system-config", "46"),
                [ta.ln("private/Devices", "Drivers/i386")], dot_slash=False)
    base = [ta.f("usr/sbin/sshd", b"sshd"), ta.f("sbin/mount", b"mount"),
            ta.f("usr/libexec/getty", b"getty"), ta.f("usr/bin/perl", b"pl"),
            ta.f("private/etc/rc.cdrom.PPC", b"1;\n"),
            ta.f(CDIS + "English.lproj/Localizable.strings", b"\"A\" = \"a\";"),
            ta.f(CDIS + "findroot", b"f"), ta.f(CDIS + "gc", b"g"),
            ta.f(CDIS + "popconsole", b"p"),
            ta.dev("private/dev/hd0a", "blk", 3, 0),
            ta.dev("private/dev/rhd0a", "chr", 15, 0),
            ta.dev("private/dev/null", "chr", 3, 2)]
    if driver_loader:
        base.append(ta.f("usr/sbin/driverLoader", b"dl"))
    ta.make(directory, "base-cmds-1-universal.apk", ta.pkginfo("base-cmds"),
            base + list(extra), dot_slash=False)


class TestBuild(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.repo = os.path.join(self.tmp.name, "repo")
        os.mkdir(self.repo)
        self.efi = os.path.join(self.tmp.name, "BOOTIA32.EFI")
        with open(self.efi, "wb") as f:
            f.write(b"MZ" + b"e" * 5000)
        self.out = os.path.join(self.tmp.name, "media.img")

    def tearDown(self):
        self.tmp.cleanup()

    def test_live_media_builds_and_reads_back(self):
        make_bootable_repo(self.repo)
        napks, nnodes, g, total = build.build(self.repo, self.efi, self.out)
        self.assertEqual(napks, 3 + 2 + len(BOOT_DRIVERS) + 1 + 1 + 1)
        with rhap_image.Image(self.out) as img:
            self.assertIsNotNone(img.resolve("/private/etc/rc.cdrom"))
            self.assertIsNotNone(
                img.resolve("/System/Installation/Packages/"
                            "kernel-154.5.1-i386.apk"))

    def test_preinstalled_builds_and_reads_back(self):
        make_bootable_repo(self.repo)
        build.build(self.repo, self.efi, self.out, preinstalled=True)
        with rhap_image.Image(self.out) as img:
            self.assertIsNone(img.resolve("/private/etc/rc.cdrom"))
            fstab = img.read_file(img.resolve("/private/etc/fstab"))
        self.assertEqual(fstab, b"/dev/hd0a\t/\tufs\trw\t1 1\n")

    def test_a_missing_boot_driver_is_named(self):
        make_bootable_repo(self.repo, drivers=("EISABus", "PCIBus",
                                               "PS2Keyboard", "EIDE", "NE2K"))
        with self.assertRaisesRegex(build.BuildError, "AHCI_reloc"):
            build.build(self.repo, self.efi, self.out)
        self.assertFalse(os.path.exists(self.out))

    def test_preinstalled_needs_driverloader_and_the_network_card(self):
        make_bootable_repo(self.repo, drivers=BOOT_DRIVERS,
                           driver_loader=False)
        with self.assertRaises(build.BuildError) as cm:
            build.build(self.repo, self.efi, self.out, preinstalled=True)
        self.assertIn("missing /usr/sbin/driverLoader", str(cm.exception))
        self.assertIn("missing /private/Drivers/i386/NE2K.config/NE2K_reloc",
                      str(cm.exception))

    def test_the_media_does_not_need_driverloader(self):
        make_bootable_repo(self.repo, drivers=BOOT_DRIVERS,
                           driver_loader=False)
        build.build(self.repo, self.efi, self.out)

    def test_preinstalled_needs_usr_devices_to_reach_the_table(self):
        make_bootable_repo(self.repo, devices_link=False)
        with self.assertRaisesRegex(build.BuildError,
                                    "/usr/Devices/System.config/"
                                    "Instance0.table does not lead"):
            build.build(self.repo, self.efi, self.out, preinstalled=True)

    def test_conflicts_are_refused(self):
        make_bootable_repo(self.repo)
        ta.make(self.repo, "rival-1-universal.apk", ta.pkginfo("rival"),
                [ta.f("usr/sbin/sshd", b"other")], dot_slash=False)
        with self.assertRaisesRegex(build.BuildError,
                                    "/usr/sbin/sshd: claimed by base-cmds "
                                    "and rival"):
            build.build(self.repo, self.efi, self.out)

    def test_a_too_small_filesystem_is_refused(self):
        make_bootable_repo(self.repo, extra=[ta.f("big", b"b" * 3000000)])
        with self.assertRaisesRegex(build.BuildError, "--fs-mb"):
            build.build(self.repo, self.efi, self.out, fs_mb=1)
        self.assertFalse(os.path.exists(self.out))

    def test_main_reports_errors_without_a_traceback(self):
        make_bootable_repo(self.repo, drivers=())
        err = io.StringIO()
        with contextlib.redirect_stderr(err):
            self.assertEqual(build.main(["build", "--repo", self.repo,
                                         "--efi", self.efi, "--out",
                                         self.out]), 1)
        self.assertIn("missing /private/Drivers/i386/EIDE.config/EIDE_reloc",
                      err.getvalue())

    def test_main_reports_a_package_it_cannot_lay_down(self):
        make_bootable_repo(self.repo)
        ta.make(self.repo, "zz-1-universal.apk", ta.pkginfo("zz"),
                [ta.ln("usr/lost", "nowhere/at/all"),
                 ta.f("usr/lost/file", b"x")], dot_slash=False)
        err = io.StringIO()
        with contextlib.redirect_stderr(err):
            self.assertEqual(build.main(["build", "--repo", self.repo,
                                         "--efi", self.efi, "--out",
                                         self.out]), 1)
        self.assertIn("no directory /usr/nowhere", err.getvalue())


class TestChecks(unittest.TestCase):
    def test_dev_majors(self):
        nodes = [Node("/private/dev/hd1a", "blk", 0o640, 0, 5, 0, (3, 8)),
                 Node("/private/dev/rsd0a", "chr", 0o640, 0, 5, 0, (14, 0)),
                 Node("/private/dev/sd0a", "blk", 0o640, 0, 5, 0, (7, 0)),
                 Node("/private/dev/rhd0a", "blk", 0o640, 0, 5, 0, (15, 0)),
                 Node("/private/dev/fd", "dir", 0o555, 0, 0, 0, None),
                 Node("/private/dev/urandom", "chr", 0o644, 0, 0, 0, (17, 1)),
                 Node("/private/dev/tty", "chr", 0o666, 0, 0, 0, (2, 0))]
        self.assertEqual(build.check_dev(nodes), [
            "/private/dev/sd0a is blk 7, the kernel wants blk 6",
            "/private/dev/rhd0a is blk 15, the kernel wants chr 15"])

    def test_boot_drivers(self):
        self.assertEqual(build.boot_drivers(
            b'"Kernel" = "mach_kernel";\n"Boot Drivers" = "EIDE  AHCI";\n'),
            ["EIDE", "AHCI"])
        with self.assertRaises(build.BuildError):
            build.boot_drivers(b'"Kernel" = "mach_kernel";\n')

    def test_fs_sectors_is_whole_megabytes_with_headroom(self):
        nodes = [Node("/a", "reg", 0o644, 0, 0, 0, b"x" * 3000000)]
        got = build.fs_sectors(nodes, 1024 * 1024)
        self.assertEqual(got % 2048, 0)
        self.assertGreaterEqual(got * 512, 3000000 * 5 // 4 + 1024 * 1024)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run them to see them fail** (`ModuleNotFoundError`).

- [ ] **Step 3: Implement** `vm/instmedia/build.py`:

```python
"""Build the hard-disk install media, or a pre-installed disk, from apks.

    python -m instmedia.build --repo DIR --efi BOOTIA32.EFI --out IMAGE
                              [--preinstalled] [--fs-mb N]

DIR is a flat directory of apks (instmedia.collect makes one).  The image
is staged in memory and read back before it is kept: readback.diff against
the node tree and ufs_check.check on the allocation accounting must both be
clean.  Refused, with every problem listed: paths two packages both claim,
a root missing a file its boot needs, and /dev nodes whose majors disagree
with the kernel's.
"""
import argparse
import os
import re
import sys

import ufs_check
from instmedia import (apkrepo, hdimage, live, readback, rootfs, space,
                       testconfig)

BOOTERS = "/usr/standalone/i386"
DRIVERS = "/private/Drivers/i386"
# driverLoader reads the system table through /usr/Devices, which files
# links to ../private/Devices.
DEVICES_TABLE = "/usr/Devices/System.config/Instance0.table"
# The card the pre-installed image's SSH gate uses (QEMU's ne2k_pci), an
# Active Driver that driverLoader loads at startup.
NETWORK_DRIVER = "NE2K"
# What CDIS's rc.cdrom runs before its first menus.
CDIS_NEEDS = ["/usr/bin/perl", live.RC_CDROM, "/private/etc/rc.cdrom.x86",
              "/private/etc/rc.cdrom.PPC",
              live.CDIS + "/English.lproj/Localizable.strings",
              live.CDIS + "/findroot", live.CDIS + "/gc",
              live.CDIS + "/popconsole", live.CDIS + "/pickdisk"]
# The majors /dev must use: sd from the kernel's own tables
# (src/kernel-7/bsd/dev/i386/conf.c: bdevsw 6, cdevsw 14), hd and fd from
# the "Block Major"/"Character Major" the EIDE and Floppy drivers register
# (drvEIDE and drvPCFloppy Default.table), console/null/zero/random from
# conf.c.  Checked by name prefix, longest first.
DEV_MAJORS = (("rhd", "chr", 15), ("rsd", "chr", 14), ("rfd", "chr", 41),
              ("hd", "blk", 3), ("sd", "blk", 6), ("fd", "blk", 1))
DEV_EXACT = {"console": ("chr", 0), "null": ("chr", 3), "zero": ("chr", 3),
             "random": ("chr", 17), "urandom": ("chr", 17)}
LIVE_HEADROOM = 32 * 1024 * 1024
# The installed system makes a swapfile, host keys and logs on first boot.
PREINSTALLED_HEADROOM = 512 * 1024 * 1024


class BuildError(Exception):
    pass


def boot_drivers(table):
    m = re.search(rb'"Boot Drivers"\s*=\s*"([^"]*)"', table)
    if m is None:
        raise BuildError("Instance0.table has no Boot Drivers")
    return m.group(1).decode("ascii").split()


def check_tree(nodes, preinstalled):
    """What the booters, the kernel and the image's startup need that the
    root lacks: CDIS's pieces on the media; sshd, driverLoader, the network
    card and the /usr/Devices path on the pre-installed disk."""
    by_path = {n.path: n for n in nodes}
    table = by_path[live.SYSTEM_TABLE].data
    need = ["/mach_kernel", BOOTERS + "/boot0", BOOTERS + "/boot1",
            BOOTERS + "/boot", BOOTERS + "/sarld"]
    need += ["%s/%s.config/%s_reloc" % (DRIVERS, name, name)
             for name in boot_drivers(table)]
    if preinstalled:
        need += ["/usr/sbin/sshd", "/sbin/mount", "/usr/libexec/getty",
                 "/usr/sbin/driverLoader",
                 "%s/%s.config/%s_reloc" % (DRIVERS, NETWORK_DRIVER,
                                            NETWORK_DRIVER)]
    else:
        need += CDIS_NEEDS
    problems = ["missing %s" % p for p in need if p not in by_path]
    if preinstalled:
        tree = rootfs.Tree()
        for n in nodes[1:]:
            tree.put(n)
        try:
            real = tree.resolve(DEVICES_TABLE)
        except rootfs.TreeError as e:
            real = str(e)
        if real != live.SYSTEM_TABLE:
            problems.append("%s does not lead to %s (%s)"
                            % (DEVICES_TABLE, live.SYSTEM_TABLE, real))
    return problems


def check_dev(nodes):
    """/dev nodes whose kind or major the kernel would not agree with."""
    problems = []
    for n in nodes:
        if not n.path.startswith("/private/dev/") or n.kind not in (
                "chr", "blk"):
            continue
        name = n.path.rsplit("/", 1)[1]
        want = DEV_EXACT.get(name)
        if want is None:
            want = next(((k, m) for p, k, m in DEV_MAJORS
                         if name.startswith(p)), None)
        if want is not None and (n.kind, n.data[0]) != want:
            problems.append("%s is %s %d, the kernel wants %s %d"
                            % ((n.path, n.kind, n.data[0]) + want))
    return problems


def fs_sectors(nodes, headroom):
    """A filesystem size, in 512-byte sectors, for nodes plus headroom."""
    data = sum(-(-len(n.data) // 1024) * 1024 for n in nodes
               if n.kind == "reg")
    size = max(data * 5 // 4, len(nodes) * 4096 * 2) + headroom
    return -(-size // (1024 * 1024)) * 2048


def build(repo, efi_path, out, preinstalled=False, fs_mb=None):
    apks = apkrepo.index(repo)
    with open(efi_path, "rb") as f:
        esp = hdimage.esp_image(f.read())
    nodes, conflicts = live.compose(
        apks, esp, preinstalled=preinstalled,
        password_hash=testconfig.TEST_PASSWORD_HASH if preinstalled else None)
    problems = ["%s: claimed by %s and %s" % c for c in conflicts]
    problems += check_tree(nodes, preinstalled) + check_dev(nodes)
    if problems:
        raise BuildError("\n".join(problems))
    by_path = {n.path: n for n in nodes}
    boot0, boot1, boot2 = (by_path[BOOTERS + "/" + name].data
                           for name in ("boot0", "boot1", "boot"))
    now = max(n.mtime for n in nodes)
    sectors = fs_mb * 2048 if fs_mb else fs_sectors(
        nodes, PREINSTALLED_HEADROOM if preinstalled else LIVE_HEADROOM)
    try:
        g, total = hdimage.write(out, sectors, boot0, boot1, boot2, esp,
                                 nodes, now)
    except space.NoSpace:
        os.remove(out)
        raise BuildError("%d MB of UFS is too small for this root; pass a "
                         "larger --fs-mb" % (sectors // 2048))
    problems = readback.diff(out, nodes) + ufs_check.check(out)
    if problems:
        raise BuildError("the image does not read back clean:\n"
                         + "\n".join(problems))
    return len(apks), len(nodes), g, total


def main(argv):
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--repo", required=True)
    p.add_argument("--efi", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--preinstalled", action="store_true")
    p.add_argument("--fs-mb", type=int, default=None)
    a = p.parse_args(argv[1:])
    try:
        napks, nnodes, g, total = build(a.repo, a.efi, a.out,
                                        a.preinstalled, a.fs_mb)
    except (BuildError, apkrepo.RepoError, live.ComposeError,
            rootfs.TreeError, hdimage.ImageError) as e:
        print("instmedia.build: %s" % e, file=sys.stderr)
        return 1
    print("%s: %d apks, %d nodes, %d MB of UFS, %d MB disk"
          % (a.out, napks, nnodes, g.fssize // 2048, total // 2048))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
```

- [ ] **Step 4: Run these tests, then every instmedia test.** All 13 of
  these pass. Then run:
  `cd vm && RHAPSODY_MEDIA_DIR=D:/RhapsodiOS/vm python -m unittest instmedia.test_build instmedia.test_hdimage instmedia.test_apkrepo instmedia.test_rootfs instmedia.test_live instmedia.test_collect instmedia.test_label instmedia.test_ufs instmedia.test_ufs_geometry instmedia.test_space instmedia.test_sample -v`.
  Everything passes. The one expected skip is `TestImage`, which runs only
  when `RHAPSODY_BOOTSTRAP_IMAGE` is set.

- [ ] **Step 5: Commit.**

```bash
git add vm/instmedia/build.py vm/instmedia/test_build.py
git commit -m "instmedia: build the hard-disk media from apks, refusing conflicts and missing boot files"
```

### Task 10: Boot the media from hd1, with a network card

**Files:**
- Modify: `vm/qemu_boot.py` (docstring, `build_args`, `run`, `main`),
  `vm/test_qemu_boot.py`

**Interfaces:**
- Produces: `build_args(..., boot_hd1=False, nic=None, ssh_port=None)`,
  `run(..., boot_hd1=False, nic=None, ssh_port=None)`, and the CLI flags
  `--boot-hd1`, `--nic MODEL` and `--ssh-port PORT`. `boot_hd1` without
  `hd1`, or `ssh_port` without `nic`, raises `ValueError`.

- [ ] **Step 1: Write the failing tests.** Replace `vm/test_qemu_boot.py`
  with this. It is the current file plus the three new keywords in
  `test_main_passes_hd1_and_typed_to_run`, and the new
  `TestInstallMediaHarness`:

```python
import os
import tempfile
import unittest
import unittest.mock as mock

import qemu_boot


class TestBuildArgs(unittest.TestCase):
    def test_bios_boots_seabios_without_pflash(self):
        args = qemu_boot.build_args("bios", "D:/w/disk.img", "D:/out", 4444,
                                    "D:/fw")
        joined = " ".join(args)
        self.assertNotIn("if=pflash", joined)
        self.assertIn("-snapshot", args)
        self.assertIn("file=D:/w/disk.img,format=raw,if=ide,index=0,media=disk",
                      args)
        self.assertIn("file:%s" % os.path.join("D:/out", "console.log"), args)
        self.assertIn("file:%s" % os.path.join("D:/out", "kernel.log"), args)

    def test_uefi_boots_edk2_i386_with_its_vars_copy_in_outdir(self):
        joined = " ".join(qemu_boot.build_args("uefi", "D:/w/disk.img",
                                               "D:/out", 4444, "D:/fw"))
        self.assertIn("readonly=on,file=%s"
                      % os.path.join("D:/fw", "edk2-i386-code.fd"), joined)
        self.assertIn("unit=1,file=%s"
                      % os.path.join("D:/out", "edk2-i386-vars.fd"), joined)
        self.assertIn("-cpu Nehalem", joined)
        self.assertIn("PIIX4_PM.disable_s3=1", joined)
        self.assertIn("-m 256", joined)

    def test_esp_adds_a_virtio_disk(self):
        args = qemu_boot.build_args("bios", "a.img", "o", 1, "fw",
                                    esp="esp.img")
        self.assertIn("id=esp,file=esp.img,format=raw,if=none", args)
        self.assertIn("virtio-blk-pci,drive=esp", args)

    def test_unknown_mode_raises(self):
        with self.assertRaises(ValueError):
            qemu_boot.build_args("efi", "a.img", "o", 1, "fw")


class TestSafety(unittest.TestCase):
    def test_golden_image_is_refused(self):
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "golden.img")
            open(path, "w").close()
            with self.assertRaises(SystemExit):
                qemu_boot.refuse_masters(path)

    def test_rhapsody_vmdk_is_refused(self):
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "rhapsody.vmdk")
            open(path, "w").close()
            with self.assertRaises(SystemExit):
                qemu_boot.refuse_masters(path)

    def test_master_name_is_refused_case_insensitively(self):
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "Golden.IMG")
            open(path, "w").close()
            with self.assertRaises(SystemExit):
                qemu_boot.refuse_masters(path)

    def test_other_images_are_allowed(self):
        fd, path = tempfile.mkstemp()
        os.close(fd)
        try:
            qemu_boot.refuse_masters(path)
        finally:
            os.unlink(path)

    def test_default_firmware_dir_is_qemus_share_directory(self):
        with mock.patch("shutil.which",
                        return_value="C:/q/qemu-system-i386.exe"), \
             mock.patch("os.path.realpath", side_effect=lambda p: p):
            self.assertEqual(
                qemu_boot.default_firmware_dir("qemu-system-i386"),
                os.path.join("C:/q", "share"))


class TestRunReportsQemuFailures(unittest.TestCase):
    def _fake_image(self, tmpdir):
        path = os.path.join(tmpdir, "disk.img")
        open(path, "w").close()
        return path

    def test_qmp_connect_failure_names_the_stderr_log(self):
        with tempfile.TemporaryDirectory() as tmp:
            image = self._fake_image(tmp)
            outdir = os.path.join(tmp, "out")
            fake_proc = mock.Mock()
            fake_proc.poll.return_value = 1
            with mock.patch("qemu_boot.subprocess.Popen",
                            return_value=fake_proc), \
                 mock.patch("qemu_boot.qemu_shot.QMP",
                            side_effect=RuntimeError("no connection")):
                with self.assertRaises(SystemExit) as ctx:
                    qemu_boot.run("bios", image, outdir, [1], "fw")
            self.assertIn(os.path.join(outdir, "qemu-stderr.log"),
                         str(ctx.exception))

    def test_lost_qmp_connection_during_screenshot_names_the_stderr_log(self):
        with tempfile.TemporaryDirectory() as tmp:
            image = self._fake_image(tmp)
            outdir = os.path.join(tmp, "out")
            fake_proc = mock.Mock()
            fake_proc.poll.return_value = None
            fake_qmp = mock.Mock()
            fake_qmp.execute.side_effect = ConnectionResetError("reset")
            with mock.patch("qemu_boot.subprocess.Popen",
                            return_value=fake_proc), \
                 mock.patch("qemu_boot.qemu_shot.QMP",
                            return_value=fake_qmp), \
                 mock.patch("qemu_boot.time.sleep", return_value=None):
                with self.assertRaises(SystemExit) as ctx:
                    qemu_boot.run("bios", image, outdir, [1], "fw")
            self.assertIn(os.path.join(outdir, "qemu-stderr.log"),
                         str(ctx.exception))

    def test_popen_failure_closes_the_stderr_log_and_propagates(self):
        # No SystemExit wraps this one: only the QMP-connect and screenshot
        # failures above are translated into a diagnostic SystemExit, because
        # only those have a running QEMU process (and thus a stderr log
        # worth pointing at) to report on. A Popen failure means QEMU never
        # started, so the original error (FileNotFoundError, here standing
        # in for "qemu-system-i386 is not on PATH") is left to propagate
        # unchanged; the fix under test is only that it no longer leaks the
        # open stderr log handle on the way out.
        with tempfile.TemporaryDirectory() as tmp:
            image = self._fake_image(tmp)
            outdir = os.path.join(tmp, "out")
            opened = []

            def tracking_open(*args, **kwargs):
                f = open(*args, **kwargs)
                opened.append(f)
                return f

            with mock.patch("qemu_boot.subprocess.Popen",
                            side_effect=FileNotFoundError("no qemu")), \
                 mock.patch("qemu_boot.open", tracking_open, create=True):
                with self.assertRaises(FileNotFoundError):
                    qemu_boot.run("bios", image, outdir, [1], "fw")
            self.assertEqual(len(opened), 1)
            self.assertTrue(opened[0].closed)


class TestSecondDiskAndTyping(unittest.TestCase):
    def test_hd1_is_the_primary_slave_and_snapshotted(self):
        args = qemu_boot.build_args("bios", "a.img", "o", 1, "fw",
                                    hd1="b.img")
        self.assertIn("file=b.img,format=raw,if=ide,index=1,media=disk",
                      args)
        self.assertIn("-snapshot", args)

    def test_parse_typed(self):
        self.assertEqual(qemu_boot.parse_typed("70:fsck -n /dev/rhd1a"),
                         (70.0, "fsck -n /dev/rhd1a"))
        self.assertEqual(qemu_boot.parse_typed("6:-s"), (6.0, "-s"))

    def test_parse_typed_refuses_bad_specs(self):
        for spec in ("fsck", "5:a|b"):
            with self.assertRaises(ValueError):
                qemu_boot.parse_typed(spec)

    def test_run_types_each_key_then_enter(self):
        with tempfile.TemporaryDirectory() as tmp:
            image = os.path.join(tmp, "disk.img")
            open(image, "w").close()
            fake_qmp = mock.Mock()
            with mock.patch("qemu_boot.subprocess.Popen"), \
                 mock.patch("qemu_boot.qemu_shot.QMP",
                            return_value=fake_qmp), \
                 mock.patch("qemu_boot.time.sleep", return_value=None):
                qemu_boot.run("bios", image, os.path.join(tmp, "out"), [],
                              "fw", typed=[(5.0, "-s")])
            keys = [c.kwargs["keys"] for c in fake_qmp.execute.call_args_list
                    if c.args == ("send-key",)]
            self.assertEqual(keys, [[{"type": "qcode", "data": "minus"}],
                                    [{"type": "qcode", "data": "s"}],
                                    [{"type": "qcode", "data": "ret"}]])

    def test_main_passes_hd1_and_typed_to_run(self):
        with mock.patch("qemu_boot.run") as run:
            qemu_boot.main(["qemu_boot.py", "bios", "a.img", "out",
                            "--hd1", "b.img", "--type", "6:-s",
                            "--type", "70:fsck -n /dev/rhd1a",
                            "--at", "90", "--firmware-dir", "fw"])
        run.assert_called_once_with(
            "bios", "a.img", "out", [90.0], "fw", esp=None, hd1="b.img",
            typed=[(6.0, "-s"), (70.0, "fsck -n /dev/rhd1a")],
            boot_hd1=False, nic=None, ssh_port=None)


class TestInstallMediaHarness(unittest.TestCase):
    def test_boot_hd1_puts_the_media_first_and_keeps_hd0(self):
        args = qemu_boot.build_args("bios", "target.img", "o", 1, "fw",
                                    hd1="media.img", boot_hd1=True)
        self.assertIn("id=hd0,file=target.img,format=raw,if=none", args)
        self.assertIn("ide-hd,drive=hd0,bus=ide.0,unit=0,bootindex=1", args)
        self.assertIn("id=hd1,file=media.img,format=raw,if=none", args)
        self.assertIn("ide-hd,drive=hd1,bus=ide.0,unit=1,bootindex=0", args)
        self.assertNotIn("order=c", args)
        self.assertNotIn("file=media.img,format=raw,if=ide,index=1,"
                         "media=disk", args)
        self.assertIn("-snapshot", args)

    def test_boot_hd1_under_uefi(self):
        args = qemu_boot.build_args("uefi", "target.img", "o", 1, "fw",
                                    hd1="media.img", boot_hd1=True)
        self.assertIn("ide-hd,drive=hd1,bus=ide.0,unit=1,bootindex=0", args)
        self.assertIn("Nehalem", args)

    def test_boot_hd1_needs_hd1(self):
        with self.assertRaises(ValueError):
            qemu_boot.build_args("bios", "a.img", "o", 1, "fw",
                                 boot_hd1=True)

    def test_nic_with_an_ssh_forward(self):
        args = qemu_boot.build_args("bios", "a.img", "o", 1, "fw",
                                    nic="ne2k_pci", ssh_port=2549)
        self.assertIn("user,id=n0,hostfwd=tcp:127.0.0.1:2549-:22", args)
        self.assertIn("ne2k_pci,netdev=n0,addr=03.0", args)

    def test_nic_without_a_forward_and_none_by_default(self):
        args = qemu_boot.build_args("bios", "a.img", "o", 1, "fw",
                                    nic="ne2k_pci")
        self.assertIn("user,id=n0", args)
        self.assertNotIn("-netdev", qemu_boot.build_args(
            "bios", "a.img", "o", 1, "fw"))

    def test_ssh_port_needs_a_nic(self):
        with self.assertRaises(ValueError):
            qemu_boot.build_args("bios", "a.img", "o", 1, "fw",
                                 ssh_port=2549)

    def test_main_passes_the_harness_options(self):
        with mock.patch("qemu_boot.run") as run:
            qemu_boot.main(["qemu_boot.py", "uefi", "t.img", "out",
                            "--hd1", "m.img", "--boot-hd1", "--nic",
                            "ne2k_pci", "--ssh-port", "2549", "--at", "600",
                            "--firmware-dir", "fw"])
        run.assert_called_once_with(
            "uefi", "t.img", "out", [600.0], "fw", esp=None, hd1="m.img",
            typed=[], boot_hd1=True, nic="ne2k_pci", ssh_port=2549)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run them to see them fail.**
  `cd vm && python -m unittest test_qemu_boot -v` fails with
  `unexpected keyword argument 'boot_hd1'`.

- [ ] **Step 3: Implement.** Replace `vm/qemu_boot.py` with:

```python
#!/usr/bin/env python3
"""Boot a disk image under QEMU and capture its consoles and screen.

    python vm/qemu_boot.py {bios,uefi} IMAGE OUTDIR [--esp ESP_IMAGE]
                           [--hd1 IMAGE [--boot-hd1]] [--nic MODEL]
                           [--ssh-port PORT] [--type SECONDS:TEXT ...]
                           [--at SECONDS[,SECONDS...]] [--firmware-dir DIR]

bios boots QEMU's own SeaBIOS.  uefi boots the IA32 edk2 firmware QEMU ships
as share/edk2-i386-code.fd, so no OVMF build is needed.  IMAGE is the first
IDE disk (i440FX/PIIX3, the controller the EIDE boot driver probes); --esp
adds a virtio disk for the two-disk layout, whose loader sits on an
ESP-only disk.  --hd1 adds a second IDE disk, the primary slave, which the
guest sees as hd1; --boot-hd1 makes it the boot disk, as the install
media is in the design's harness, with IMAGE, the blank target, still hd0.
--nic adds a network card of that QEMU model on QEMU's user network, and
--ssh-port forwards that 127.0.0.1 port to the guest's ssh.  Each --type
types TEXT and presses Enter at SECONDS, for a boot prompt or a single-user
shell.

OUTDIR gets console.log (COM1: firmware and loader), kernel.log (COM2: the
kernel's serial console) and shot-<N>s.png screenshots.  QEMU quits after
the last --at or --type time.

Every drive is opened with -snapshot, so no boot ever writes an image, and
any path named golden.img or rhapsody.vmdk is refused outright, wherever it
lives (so the main checkout's masters are refused from a worktree too).
QEMU gets native paths straight from Python: Git Bash does not rewrite
`-serial file:/d/...` for native programs, which is why this is not a shell
script.  Standard library only.
"""
import argparse
import importlib.util
import os
import shutil
import subprocess
import sys
import time

_HERE = os.path.dirname(os.path.abspath(__file__))
_MASTERS = ("golden.img", "rhapsody.vmdk")
DEFAULT_AT = "60,120,180"


def _load_qemu_shot():
    spec = importlib.util.spec_from_file_location(
        "qemu_shot", os.path.join(_HERE, "qemu-shot.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


qemu_shot = _load_qemu_shot()
# What --type can send: qemu-shot's boot-prompt keys plus a path's.
KEYS = dict(qemu_shot.KEY_MAP, **{"/": ["slash"], ".": ["dot"]})


def refuse_masters(path):
    """Exit if path is one of the read-only master images, wherever it
    lives: by same-file identity against this checkout's own copy, or by
    basename against golden.img/rhapsody.vmdk anywhere (e.g. the main
    checkout, when running from a worktree that has no copy of its own)."""
    for name in _MASTERS:
        master = os.path.join(_HERE, name)
        if (os.path.exists(master) and os.path.exists(path)
                and os.path.samefile(path, master)):
            raise SystemExit("refusing to boot %s: it is a read-only master"
                             % path)
    if os.path.basename(path).lower() in (n.lower() for n in _MASTERS):
        raise SystemExit("refusing to boot %s: it is a read-only master"
                         % path)


def default_firmware_dir(qemu):
    found = shutil.which(qemu)
    if found is None:
        raise SystemExit("%s is not on PATH" % qemu)
    return os.path.join(os.path.dirname(os.path.realpath(found)), "share")


def parse_typed(spec):
    """"SECONDS:TEXT" -> (seconds, text), refusing keys KEYS cannot send."""
    seconds, sep, text = spec.partition(":")
    if not sep:
        raise ValueError("--type wants SECONDS:TEXT, not %r" % spec)
    for ch in text:
        if ch not in KEYS:
            raise ValueError("--type cannot send %r" % ch)
    return float(seconds), text


def build_args(mode, image, outdir, qmp_port, firmware_dir, esp=None,
               hd1=None, qemu="qemu-system-i386", boot_hd1=False, nic=None,
               ssh_port=None):
    if boot_hd1 and hd1 is None:
        raise ValueError("boot_hd1 needs an hd1 image")
    if ssh_port is not None and nic is None:
        raise ValueError("ssh_port needs a nic")
    if boot_hd1:
        # bootindex puts hd1 first in both firmwares' boot order; SeaBIOS
        # then gives it drive 0x80, the drive boot0 reads.
        disks = ["-drive", "id=hd0,file=%s,format=raw,if=none" % image,
                 "-device", "ide-hd,drive=hd0,bus=ide.0,unit=0,bootindex=1",
                 "-drive", "id=hd1,file=%s,format=raw,if=none" % hd1,
                 "-device", "ide-hd,drive=hd1,bus=ide.0,unit=1,bootindex=0"]
    else:
        disks = ["-drive",
                 "file=%s,format=raw,if=ide,index=0,media=disk" % image]
    args = [qemu, "-M", "pc", "-m", "256", "-nodefaults", "-vga", "cirrus",
            "-display", "none", "-snapshot"] + disks + [
            "-serial", "file:%s" % os.path.join(outdir, "console.log"),
            "-serial", "file:%s" % os.path.join(outdir, "kernel.log"),
            "-rtc", "base=%s" % qemu_shot.RTC_BASE,
            "-qmp", "tcp:127.0.0.1:%d,server=on,wait=off" % qmp_port]
    if mode == "uefi":
        # Nehalem: QEMU's default CPU model lacks features edk2 asserts on.
        # disable_s3: stops edk2 reserving low ACPI NVS for S3 resume, which
        # would cap the contiguous memory the kernel is given.
        args += ["-cpu", "Nehalem", "-global", "PIIX4_PM.disable_s3=1",
                 "-drive", "if=pflash,format=raw,unit=0,readonly=on,file=%s"
                 % os.path.join(firmware_dir, "edk2-i386-code.fd"),
                 "-drive", "if=pflash,format=raw,unit=1,file=%s"
                 % os.path.join(outdir, "edk2-i386-vars.fd")]
    elif mode == "bios":
        args += ["-cpu", "pentium"]
        if not boot_hd1:
            args += ["-boot", "order=c"]
    else:
        raise ValueError("mode must be bios or uefi, not %r" % mode)
    if esp is not None:
        args += ["-drive", "id=esp,file=%s,format=raw,if=none" % esp,
                 "-device", "virtio-blk-pci,drive=esp"]
    if hd1 is not None and not boot_hd1:
        args += ["-drive",
                 "file=%s,format=raw,if=ide,index=1,media=disk" % hd1]
    if nic is not None:
        netdev = "user,id=n0"
        if ssh_port is not None:
            netdev += ",hostfwd=tcp:127.0.0.1:%d-:22" % ssh_port
        args += ["-netdev", netdev,
                 "-device", "%s,netdev=n0,addr=03.0" % nic]
    return args


def run(mode, image, outdir, at_points, firmware_dir, esp=None, hd1=None,
        typed=(), boot_hd1=False, nic=None, ssh_port=None):
    for path in (image, esp, hd1):
        if path is not None:
            if not os.path.exists(path):
                raise SystemExit("no such image: %s" % path)
            refuse_masters(path)
    os.makedirs(outdir, exist_ok=True)
    if mode == "uefi":
        shutil.copyfile(os.path.join(firmware_dir, "edk2-i386-vars.fd"),
                        os.path.join(outdir, "edk2-i386-vars.fd"))
    port = qemu_shot.find_free_port()
    stderr_path = os.path.join(outdir, "qemu-stderr.log")
    proc = None
    qmp = None
    try:
        stderr_f = open(stderr_path, "wb")
        try:
            proc = subprocess.Popen(
                build_args(mode, image, outdir, port, firmware_dir, esp=esp,
                           hd1=hd1, boot_hd1=boot_hd1, nic=nic,
                           ssh_port=ssh_port),
                stdout=subprocess.DEVNULL, stderr=stderr_f)
        finally:
            stderr_f.close()
        start = time.monotonic()
        try:
            qmp = qemu_shot.QMP("127.0.0.1", port)
        except RuntimeError as e:
            raise SystemExit(_qemu_failure_message(proc, stderr_path, e))
        events = sorted([(t, None) for t in at_points] + list(typed),
                        key=lambda e: e[0])
        for t, text in events:
            remaining = t - (time.monotonic() - start)
            if remaining > 0:
                time.sleep(remaining)
            try:
                if text is not None:
                    _type(qmp, text)
                    print("typed %r at %ss" % (text, qemu_shot.fmt_seconds(t)))
                    continue
                ppm = os.path.join(outdir, "_shot.ppm")
                qmp.execute("screendump", filename=ppm)
                with open(ppm, "rb") as f:
                    w, h, _, pixels = qemu_shot.parse_ppm(f.read())
                os.remove(ppm)
            except (OSError, RuntimeError) as e:
                raise SystemExit(_qemu_failure_message(proc, stderr_path, e))
            png = os.path.join(outdir,
                               "shot-%ss.png" % qemu_shot.fmt_seconds(t))
            qemu_shot.write_png(png, w, h, pixels)
            print("wrote %s" % png)
    finally:
        if qmp is not None:
            try:
                qmp.execute("quit")
            except Exception:
                pass
            qmp.close()
        if proc is not None:
            try:
                proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=5)
    print("console: %s" % os.path.join(outdir, "console.log"))
    print("kernel:  %s" % os.path.join(outdir, "kernel.log"))


def _type(qmp, text):
    for ch in text + "\n":
        qmp.execute("send-key", keys=[{"type": "qcode", "data": code}
                                      for code in KEYS[ch]])
        time.sleep(0.05)


def _qemu_failure_message(proc, stderr_path, error):
    status = proc.poll()
    if status is not None:
        return ("QEMU exited with status %s during the boot; its stderr "
                "is in %s" % (status, stderr_path))
    return ("lost the QMP connection (%s) while QEMU was still running; "
            "its stderr is in %s" % (error, stderr_path))


def main(argv):
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("mode", choices=("bios", "uefi"))
    p.add_argument("image")
    p.add_argument("outdir")
    p.add_argument("--esp", default=None)
    p.add_argument("--hd1", default=None)
    p.add_argument("--boot-hd1", action="store_true")
    p.add_argument("--nic", default=None, metavar="MODEL")
    p.add_argument("--ssh-port", type=int, default=None)
    p.add_argument("--type", dest="typed", action="append", default=[],
                   type=parse_typed, metavar="SECONDS:TEXT")
    p.add_argument("--at", default=DEFAULT_AT,
                   help="comma-separated screenshot times in seconds")
    p.add_argument("--firmware-dir", default=None)
    a = p.parse_args(argv[1:])
    at_points = [float(x) for x in a.at.split(",") if x]
    firmware_dir = a.firmware_dir or default_firmware_dir("qemu-system-i386")
    run(a.mode, a.image, a.outdir, at_points, firmware_dir, esp=a.esp,
        hd1=a.hd1, typed=a.typed, boot_hd1=a.boot_hd1, nic=a.nic,
        ssh_port=a.ssh_port)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
```

- [ ] **Step 4: Run the tests.** All 24 pass. Then smoke-test QEMU itself:

```bash
Q=<scratch>/qsmoke; mkdir -p $Q
cd vm && python -c "import sys; [open(p,'wb').truncate(8<<20) for p in sys.argv[1:]]" $Q/t.img $Q/m.img
python qemu_boot.py bios $Q/t.img $Q/bios --hd1 $Q/m.img --boot-hd1 --nic ne2k_pci --ssh-port 2599 --at 4
python qemu_boot.py uefi $Q/t.img $Q/uefi --hd1 $Q/m.img --boot-hd1 --nic ne2k_pci --ssh-port 2599 --at 4
```

  Each run writes `shot-4s.png`. `qemu-stderr.log` holds at most TCG's
  `CPUID ... lm` warning.

- [ ] **Step 5: Commit.**

```bash
git add vm/qemu_boot.py vm/test_qemu_boot.py
git commit -m "vm: boot the install media from hd1 and give the guest a network card in qemu_boot"
```

### Task 11: Build the images and run the four gates (controller)

**Files:** none in the repo. Output goes to `vm/work/p4-repo/`,
`vm/work/p4-gate/` and `vm/logs/p4-gate/`, all gitignored.

- [ ] **Step 1: Build `BOOTIA32.EFI` in the worktree.** It's gitignored, so
  the worktree has none:

```bash
cd src/bootefi-1 && PATH="/c/Program Files/LLVM/bin:$PATH" make
```

  If clang stops on `incompatible-pointer-types`, rerun with
  `make CC="clang -Wno-error=incompatible-pointer-types -Wno-error=int-conversion -Wno-error=incompatible-function-pointer-types"`.
  Never pass `LINK=` on the command line.

- [ ] **Step 2: Collect and build.**

```bash
cd vm
python -m instmedia.collect work/p4-repo --image work/rhap-i386-bootstrapped.img \
    --add work/p2-apks --add work/p4-apks
python -m instmedia.build --repo work/p4-repo --efi ../src/bootefi-1/BUILD/BOOTIA32.EFI --out work/p4-gate/media.img
python -m instmedia.build --repo work/p4-repo --efi ../src/bootefi-1/BUILD/BOOTIA32.EFI --out work/p4-gate/preinstalled.img --preinstalled
```

  Each build prints its apk, node and size counts and exits 0.
  - A conflict or missing path is a packaging bug. Fix the package, rebuild
    it on the Task 3 guest, fetch it, remove `work/p4-repo` (`collect`
    refuses a non-empty one) and rerun from `collect`.
  - Until the `driverkit` apk carries `driverLoader`, the pre-installed
    build stops with `missing /usr/sbin/driverLoader`. Build and gate the
    media meanwhile.
  - Record the counts and every fix for Task 12.

- [ ] **Step 3: Gates 1 and 2, the media under both firmwares.** First find
  when CDIS's language menu appears:

```bash
python -c "open('work/p4-gate/blank.img','wb').truncate(2<<30)"
python qemu_boot.py bios work/p4-gate/blank.img logs/p4-gate/media-bios --hd1 work/p4-gate/media.img --boot-hd1 --at 60,120,180,240,300,360
```

  The menu's text starts `Type 1 to use the English language and USA
  keyboard while installing Darwin OS.` Call the first screenshot time that
  shows it T. Then answer it:

```bash
python qemu_boot.py bios work/p4-gate/blank.img logs/p4-gate/media-bios-typed --hd1 work/p4-gate/media.img --boot-hd1 --type "<T+10>:1" --type "<T+60>:1" --at <T+5>,<T+40>,<T+90>,<T+120>
```

  Repeat both runs with `uefi` in place of `bios`, into
  `logs/p4-gate/media-uefi*`.
  - **Pass:**
    - The language menu shows.
    - After `1`, the Intel warning shows, starting `You are about to
      configure a disk to install Darwin OS 1.0 for Intel.`
    - `kernel.log` shows the root on `hd1a`: `rootdev 308`, meaning major
      3, minor 8.
    - Under UEFI, `console.log` shows the loader choosing the disk it was
      read from.
  - **Record, don't judge,** what follows the second `1`: `pickdisk`'s
    disk list (`BOOT_DISK` / `WHICH_DISK`), or its failure. Phase 5 builds
    on it.
  - If the language menu never comes, read the shots and logs and fix the
    root cause. Perl errors land on the console.

- [ ] **Step 4: Gates 3 and 4, the pre-installed disk under both firmwares,
  with SSH.** These need the `driverLoader` apk (Task 3 Step 8). Make the
  gate login config:

```bash
G=<scratch>/p4gate; mkdir -p $G/vm && cp vm/{rhap-remote,build-src-lib,sync-src,sync-src-lib,guest-remote}.ps1 $G/vm/
sed -e 's/^Port=.*/Port=2549/' -e 's/^Password=.*/Password=rhapsodi/' D:/RhapsodiOS/vm/vm.conf > $G/vm/vm.conf
printf '%s\n' 'echo logged in to the pre-installed disk' 'uname -a' 'mount' 'ifconfig en0' \
  'test -f /etc/rc.cdrom && echo rc.cdrom PRESENT || echo no rc.cdrom' \
  'ls -l /usr/Devices/System.config/Instance0.table' > $G/login.sh
```

  Then, for each of `bios` and `uefi`, start the boot in the background:

```bash
python qemu_boot.py bios work/p4-gate/preinstalled.img logs/p4-gate/pre-bios --nic ne2k_pci --ssh-port 2549 --at 120,240,360,480,600,720,840
```

  About 8 minutes in (the first boot makes the host keys), make one login
  attempt:
  `powershell -NoProfile -File $G/vm/guest-remote.ps1 -Run $G/login.sh`.
  If it's refused because sshd isn't up yet, try once more at about 12
  minutes.
  - **Pass:**
    - The login succeeds with the password `rhapsodi`.
    - `mount` shows `/dev/hd0a on /` read-write, and `en0` has an address
      from QEMU's DHCP (10.0.2.x), which means `driverLoader` loaded NE2K.
    - `no rc.cdrom` prints, and the table resolves through `/usr/Devices`.
    - A screenshot shows the console `login:`.
  - Before the second firmware's run, remove the `[127.0.0.1]:2549` line
    from `C:/Users/RAYNOR~2/AppData/Local/Temp/rhap-known_hosts`. Every
    first boot makes new host keys, and `-snapshot` discards them.

- [ ] **Step 5:** Record the passing shots' paths and the key log lines for
  Task 12, then delete `$G/vm/vm.conf`.

### Task 12: Record it

**Files:**
- Create: `docs/build/instmedia-live.md`
- Modify: `docs/superpowers/specs/2026-09-22-install-media-design.md`

- [ ] **Step 1: Write `docs/build/instmedia-live.md`,** in the style of
  `docs/build/instmedia-ufs.md`. It holds:
  - a module table (`collect`, `apkrepo`, `rootfs`, `live`, `hdimage`,
    `build`)
  - the boot closure, with every project Task 3 added and why
  - the exact commands from Task 11
  - a results table for the four gates, with dates, image sizes, apk and
    node counts, and what `pickdisk` did
  - *Worth knowing*:
    - CDIS as the installer: the inert `rc.cdrom.hidden`, the missing
      `sysconfig` and the language menu
    - NE2K as an Active Driver, with Task 1's evidence
    - the `/private/Devices` link
    - `getpwnam` reading `master.passwd` without `lookupd`
    - the companion rule
    - every packaging fix Tasks 3 and 11 needed

- [ ] **Step 2: Update the spec,** noting each change as "(Before phase 4;
  now ...)" in the style phases 1 and 2 used:
  - *Installer*: phases 4 and 5 build on `cdis-3`. Its `rc.cdrom` is made
    live from `rc.cdrom.hidden`, the templates live in
    `/System/Installation/CDIS/templates`, and the target mounts at CDIS's
    `/private/var/tmp/mnta`, not `/Installation/Target`.
  - *Live environment*: the overlay list. The "checked absent on target"
    rule becomes `/etc/rc.cdrom` only, because `cdis` installs
    `/System/Installation` everywhere.
  - *Installed-system configuration*, the `Instance0.table` row: Active
    Drivers add `NE2K`, not `Intel1000`, and why.
  - *Testing*'s runner line: `-device ne2k_pci` and host port 2549, not
    `e1000` and 2222.
  - Risk 1: what phase 4 showed. Risk 7: the `getpwnam` finding.

- [ ] **Step 3: Commit.**

```bash
git add docs/build/instmedia-live.md docs/superpowers/specs/2026-09-22-install-media-design.md
git commit -m "docs: record phase 4's pure-apk media, CDIS as the installer and NE2K under driverLoader"
```
