# Xserve PPC bootstrap verification

Status: **blocked on the kernel header provider's missing private host tool** on
2026-08-02. This
is an evidence record for the incomplete run, not a successful full-build
claim. No workaround, host fallback, seed, or copy helper was used.

## Host and filesystem prerequisite

The verification host was `root@10.10.0.113`, running Darwin 6.0 on PowerPC.
Its ordinary `/build` directory was on the case-insensitive HFS root device
`/dev/disk0s2`, so the build was moved to a reversible case-sensitive UFS
sparse image without changing configured paths or moving the old directory.

Jaguar's `hdiutil` rejected the requested unpartitioned form:

```text
/usr/bin/hdiutil create -type SPARSE -size 16g -fs UFS -layout NONE ...
the file system "UFS" requires a partition map
```

The live-supported equivalent was:

```sh
/usr/bin/install -d -m 755 /var/rhapsodios-build
/usr/bin/hdiutil create -type SPARSE -size 16g -fs UFS -layout SPUD \
  /var/rhapsodios-build/RhapsodiOSBuild
```

No `-ov` option was used, and creation was guarded by an existence check for
both the base name and `.sparseimage`. The created image attached as new
`/dev/disk1`; `hdiutil info` identified `/dev/disk1s2` as `Apple_UFS`, while
the root remained `/dev/disk0s2`. Only after that identity check was it
mounted:

```sh
/sbin/mount -t ufs /dev/disk1s2 /build
```

Verification reported `/dev/disk1s2 on /build (local)`, 15,441,967 KiB
available, and two files named `RbuildCaseProbe` and `rbuildcaseprobe` existed
independently. Both probes were removed. Mounting over `/build` hides but
preserves the old HFS directory contents.

For recovery after a reboot, attach and discover the device dynamically; do
not persist the device number shown above:

```sh
image=/var/rhapsodios-build/RhapsodiOSBuild.sparseimage
attach_output=$(/usr/bin/hdiutil attach -nomount "$image") || exit 1
printf '%s\n' "$attach_output"
ufs_device=$(printf '%s\n' "$attach_output" |
  awk '$2 == "Apple_UFS" { print $1 }')
test -n "$ufs_device" || exit 1
/usr/bin/hdiutil info
# Verify the selected slice belongs to this image and is not disk0, then:
/sbin/mount -t ufs "$ufs_device" /build
```

To detach, first stop builds, verify `mount` identifies the selected slice at
`/build`, unmount it, derive its whole image device from the current attach
output, verify that mapping again with `hdiutil info`, and run
`hdiutil detach` on that whole image device. Unmounting reveals the preserved
old `/build` directory.

## Developer Tools evidence

Captured at `2026-08-02 04:52:12 UTC`:

```text
cc --version
cc (GCC) 3.1 20020420 (prerelease)

gnumake --version
GNU Make version 3.79
Built for powerpc-apple-darwin6.0

ld -v
ld: unknown flag: -v

as -v </dev/null
Apple Computer, Inc. version cctools-446.1.obj~1, GNU assembler version 1.38
```

Jaguar's linker does not implement a version option (`-v`, `-V`, and `-help`
were all rejected), so the literal requested `ld -v` result is retained above.
The assembler's stdin was redirected because bare `as -v` otherwise consumes
the remaining SSH script as assembly input.

The capability probe succeeded:

```text
cc -arch ppc -c cc-arch-ppc.c -o cc-arch-ppc.o
/build/evidence/cc-arch-ppc.o: Mach-O object ppc
```

The selected profile was
`/build/src/rbuild-1/toolchains/gcc-darwin.conf`, with checksum
`3605479895 552`. It configures `/usr/bin/cc`, `/usr/bin/ar`,
`/usr/bin/ranlib`, `/usr/bin/make`, `/usr/bin/gnutar`, `/usr/bin/gzip`, and
`/usr/bin/rsync`; target flags include `-arch ppc`, `-nostdinc`, framework and
header paths rooted below `/build/bootstrap-root`, and
`-Wl,-syslibroot,/build/bootstrap-root`.

## Commands and phase evidence

Source-only sync completed successfully:

```powershell
powershell -NoProfile -File vm\sync-src.ps1 -All
```

The canonical rbuild phase also completed successfully:

```powershell
powershell -NoProfile -File vm\build-src.ps1 -Rbuild
```

Preflight passed on UFS. The remote C suite ended `ALL TESTS PASSED`, including
359 APK validator checks; `bootstrap-resume.sh` and `bootstrap-closure.sh`
passed. The installed private tools were PPC Mach-O executables:

```text
/build/tools/bin/rbuild   76956 bytes
/build/tools/bin/relpath  16180 bytes
```

`find /tmp -name '_*' -type f` returned no files. The canonical workflow did
not upload or invoke a `/tmp/_*` helper.

Before `-Fresh`, the host baseline was captured with exactly:

```sh
find /System /usr /lib -type f -exec cksum {} \; |
  sort > /build/host-before.cksum
```

`/lib` does not exist on this Jaguar installation, which `find` reported
verbatim; `/System` and `/usr` were still processed. The run began at
`2026-08-02T04:53:57Z`, ended at `2026-08-02T05:00:13Z`, produced 31,521
records, and the baseline file checksum was:

```text
1378348179 3042335 /build/host-before.cksum
```

Then the streamed end-to-end command was started:

```powershell
powershell -NoProfile -File vm\build-src.ps1 -All -Fresh
```

Fresh preflight passed, only the five configured output roles were reset,
`/build/src` and the host baseline remained present, the rbuild tests passed
again, and the private tools were rebuilt. The command stopped during the
first bootstrap entry, before a target C compile or link. Therefore no include
search, linker map, build-base closure, APK listing, reconstruction,
interruption, package-boundary, kernel/driver, world, or no-op result exists
for this run.

## Reproducible blocker and root cause

The first manifest entry is relative:

```text
dir CoreOSMakefiles-1 all
```

The SSH command's working directory was `/var/root`. The persistent log
`/build/state/logs/coreosmakefiles-0-1-all.log` records:

```text
command: /usr/bin/rsync -avr /var/root/CoreOSMakefiles-1/ ...
link_stat /var/root/CoreOSMakefiles-1/. : No such file or directory
status: failed with status 23
```

The failure path is deterministic:

1. `manifest_read()` retains file-manifest sources exactly as written.
2. `runner_manifest()` passes the relative `entry->source` unchanged to
   `builder_scan()` and `builder_build()`.
3. The generated world phase changes directory to `/build/src`; the generated
   bootstrap phase does not.
4. The builder consequently resolves `CoreOSMakefiles-1` under `/var/root`.

At the stop point `/build/repo` and `/build/bootstrap-root` contained no files,
and `/build/state` contained no `.done` marker. Resume did not accept the
failed package.

The focused, compatibility-preserving follow-up is in
`vm/build-src-lib.ps1` and `vm/test-build-src.ps1`: first add a failing command
generation test requiring the bootstrap phase to execute from `/build/src`,
then add the same explicit `cd` already used by the world phase. Existing
`rbuild` callers historically resolve relative manifest entries from their
working directory, so changing that CLI contract is broader than this defect.
After the PowerShell regression and all existing C/trace/PowerShell suites
pass, rerun this verification from `-All -Fresh`. Do not copy the project,
seed an APK, or add a host fallback.

### Accepted fix and second verification run

Commit `48a0504c` added the focused regression and made bootstrap change to the
synced source root. The local PowerShell suite then passed 182 checks. A second
canonical run began with:

```powershell
powershell -NoProfile -File vm\build-src.ps1 -All -Fresh
```

The persistent log proves the original defect is fixed: rbuild scanned and
rsynced `/build/src/CoreOSMakefiles-1`, not `/var/root/CoreOSMakefiles-1`.
Both `installhdrs` and `install` completed successfully using the configured
sysroot flags. The run then stopped before producing the first APK.

Fresh had removed all five output roles but recreated only their parent
directory. The rbuild phase recreated `/build/tools`, and runner logging
recreated `/build/state`; `/build/repo`, `/build/bootstrap-root`, and
`/build/built` remained absent. After writing `.PKGINFO` in the private header
root, `pkginfo_build_apk()` attempted to open
`/build/repo/coreosmakefiles-hdrs-9.1-1.apk` with `O_CREAT`. Since the repository
parent did not exist, `open()` failed and the builder returned failure without
an APK. At this stop point the repository, sysroot, and built output contained
no files and state contained no `.done` record.

The focused follow-up should add failing PowerShell command-generation tests
for phase-owned output creation, then have bootstrap create its configured
repository, sysroot, and state directories before rbuild. Kernel/driver and
world phases should likewise create their configured built/state directories,
so granular entry points do not depend on a prior `-All -Fresh`. Use the
already-validated `/usr/bin/install -d`; do not seed an APK, copy a package, or
add a host fallback. After the regression and full test suites pass, rerun
Task 9 from `-All -Fresh`.

### Phase-directory fix and third verification run

Commit `4557a606` added phase-owned output creation and repository-input
checks. Its local PowerShell suite passed 191 checks. The next canonical
`-All -Fresh` run built, validated, and replayed these artifacts:

```text
coreosmakefiles-9.1-1.apk
coreosmakefiles-hdrs-9.1-1.apk
pb-makefiles-hdrs-89.5.1-1.apk
project-makefiles-hdrs-118.2.1-1.apk
architecture-hdrs-226-1.apk
```

Each completed entry has a `.done` record. The kernel header entry has none.
Its persistent log is
`/build/state/logs/kernel-154.5.1-7-headers.log` and ends with:

```text
[ configuring RELEASE_PPC ]
/usr/local/bin/config: Command not found.
make: *** No rule to make target `install_mi_hdrs'. Stop.
```

The source of the required host tool is
`src/Commands/bootstrap_cmds/config.tproj`. Kernel `doconf.csh` already
supports a `CONFIG_DIR` environment override, but no private `config` tool was
built and the bootstrap builder did not provide that variable. It therefore
fell back to `/usr/local/bin`, contrary to the private-tool boundary. The
failed `config` invocation left `RELEASE_PPC` without its generated Makefile;
the later missing rule is a consequence, not a second cause.

The focused follow-up should use TDD to source-build and install the host
`config` executable under `/build/tools` during the rbuild/tool phase, verify
it is a PPC Mach-O executable, and propagate its directory through the
bootstrap build context so `doconf` uses `CONFIG_DIR` below `/build/tools`.
The regression should prove the kernel command/log contains the private path
and no `/usr/local/bin/config`. Do not install the tool into the live host,
copy an existing executable, seed an APK, or relax the sysroot flags.

## Host audit at the stopped boundary

A second identical checksum command was run after the first-project failure.
This is only an audit through the stopped boundary, not the required
post-world audit. It ran from `2026-08-02T05:02:58Z` through
`2026-08-02T05:09:45Z`, produced the same 31,521 records and the same aggregate
checksum (`1378348179 3042335`), and `diff -u` produced zero lines. Its metadata
and empty diff are stored below `/build/evidence`.

The later stopped-boundary audits were also identical:

| Stop boundary | UTC interval | Records | Aggregate checksum | Diff |
| --- | --- | ---: | --- | ---: |
| Missing repository directory | 05:17:08–05:24:02 | 31,521 | `1378348179 3042335` | 0 lines |
| Missing private kernel `config` tool | 05:27:37–05:38:33 | 31,521 | `1378348179 3042335` | 0 lines |

These results prove no live-host file mutation through each recorded failure;
they do not replace the required audit after a complete world build.

### Private-config fix and fourth verification run

Commit `25c2e49c` source-builds the historical kernel `config` program into
`/build/tools/bin`, passes that directory through `CONFIG_DIR`, and includes a
regression for the kernel command boundary. The local PowerShell suite passed
207 checks. Focused Xserve evidence below
`/build/evidence/private-config-25c2e49c` proves that `rbuild`, `relpath`, and
`config` are PPC Mach-O executables, `doconf` generated the `RELEASE_PPC`
Makefile and ioconf sources with the private program, and
`/usr/local/bin/config` remained absent.

The next canonical run again began with:

```powershell
powershell -NoProfile -File vm\build-src.ps1 -All -Fresh
```

The rbuild tests and bootstrap closure test passed, and the run replayed the
five packages listed above. Kernel configuration then passed the earlier
failure boundary. The kernel header build stopped while generating its first
MIG interfaces:

```text
mig -typed -MD -I. -I.. -I$REL_SOURCE_DIR -DKERNEL -DKERNEL_SERVER ...
cc: unrecognized option `-typed'
/usr/bin/mig: /build/bootstrap-root/usr/libexec/migcom: No such file or directory
make[3]: *** [mach/mach_interface.h] Error 127
```

This is a missing stage-zero build tool, not a reason to reorder the target
manifest. `kernel-7 headers` must precede the complete
`Commands/bootstrap_cmds` target package because that package consumes the
target headers. PATH therefore selects Jaguar `/usr/bin/mig` at this point.
That wrapper does not recognize the Rhapsody `-typed` option and, with
`NEXT_ROOT=/build/bootstrap-root`, looks for `migcom` in the deliberately
isolated but still-incomplete target sysroot.

The source owners are `Commands/bootstrap_cmds/migcom.tproj`,
`migcom_typd.tproj`, and `migcom_untypd.tproj`, all listed by the aggregate
`PB.project`. Each project generates `lexxer.o` and `parser.o` from `lexxer.l`
and `parser.y`, links its declared C sources without an explicit library, and
historically installs its executable in `/usr/libexec`. The first project also
installs its source wrapper `mig.sh` as `/usr/bin/mig`; unlike Jaguar's wrapper,
it understands `-typed` and selects `/usr/libexec/migcom_typd`. The untyped
variant additionally links the tree's `migcom_untypd_vers_stub.o`.

The focused follow-up should add failing phase-generation tests, then
source-build these host generator programs alongside the existing private
`config` and `relpath` tools. The private MIG wrapper must bind both its
compiler/preprocessor and three back ends to paths below `/build/tools`; it
must not copy the installed Jaguar tools, install into `/usr`, seed an APK, or
weaken target include isolation. Exact failure, package/state snapshots, and
include-search evidence are retained below
`/build/evidence/missing-stage0-mig-25c2e49c`.

The exact stopped-boundary host audit completed at 14:06Z. Both snapshots
contain 31,521 records and have the aggregate checksum
`1378348179 3042335`; `cmp -s` passed and the retained `host-diff.txt` is zero
bytes. The expected diagnostic for Jaguar's absent `/lib` directory was the
only stderr. This proves no live-host file mutation through the missing-MIG
failure, but it does not replace the audit required after a complete world
build.

### Private-MIG fix and fifth verification run

Commit `f56ac29d` extends the private Rbuild phase with source-built classic,
typed, and untyped MIG back ends and a private wrapper. Focused Xserve proof
below `/build/evidence/private-mig-f56ac29d` passed the native rbuild suite,
all three MIG smoke cases, a real kernel `installhdrs` run, and an exact
31,521-record host audit with no diff.

The next canonical `-All -Fresh` run passed the rbuild, bootstrap-resume, and
bootstrap-closure suites. It entered `kernel-154.5.1-7 headers`, where private
MIG successfully generated the classic, typed, and untyped interfaces. The
kernel header export then exposed another missing stage-zero command:

```text
/bin/sh: /usr/local/bin/decomment: No such file or directory
Header file bsd/dev/ppc/evio.h not exported
```

The persistent kernel log contains 90 such command failures and 90 distinct
omitted-header messages. The owner is the aggregate's
`Commands/bootstrap_cmds/decomment.tproj`: it builds only `decomment.c`, has no
explicit library dependency, and historically installs to `/usr/local/bin`.
Kernel `conf/Makefile.template` hardcodes that historical path. When `unifdef`
cannot produce the stripped form, its fallback redirects missing `decomment`
output to a `.strip` file and treats the empty result as a deliberately
unexported header. The focused fix must source-build `decomment` beside the
other private tools and parameterize the kernel command path; it must not
install into the live host or silently retain the omission.

The incomplete header build also revealed an independent archive-format
boundary. The generated `.PKGINFO` identity is correct, but the strict APK
validator quarantined `kernel-hdrs-154.5.1-7.apk`. Raw header 522 is GNU type
`L`, `././@LongLink`, carrying the 102-byte pathname ending in
`bsd/dev/i386/EventSrcPCKeyboard.h`; the following type-0 name is truncated.
GNU tar 1.13 emits the same sequence for a disposable fixture with `--posix`,
`POSIXLY_CORRECT=1 --posix`, and `--portability`, and does not support
`--format=ustar`. In contrast, Jaguar `/bin/pax -w -x ustar` writes the same
path as a standard ustar header using the prefix field. The archive-create
contract therefore needs either a configurable pax-style backend or an
internal deterministic ustar writer. Accepting GNU LongLink would redefine
the package format and requires a correspondingly broader validator security
review; changing GNU tar flags alone cannot fix this host.

Exact logs, all 90 omissions, repo/state snapshots, include-search output, the
quarantined archive listing and identity, raw-header diagnosis, and disposable
tar-format probes are retained below
`/build/evidence/missing-stage0-decomment-f56ac29d`.

The exact stopped-boundary audit again contains 31,521 records. Both snapshots
have aggregate checksum `1378348179 3042335`, `cmp -s` passed, and the retained
diff is zero bytes; Jaguar's expected absent-`/lib` diagnostic was the only
stderr. No live-host file changed through either failure.

### Decomment/pax fix and sixth verification run

Commit `d46988df` completes the portable `decomment` source fix after the
private-tool and configurable pax-style archive-creation work. Focused Xserve
evidence below `/build/evidence/decomment-pax-d46988df` records successful sync
and Rbuild exits, the native 51-member long-path pax fixture with no GNU
LongLink, all rbuild/resume/closure tests, a PPC private `decomment` smoke test,
and another identical host audit.

The canonical command itself then exposed a host-side transport defect before
bootstrap:

```text
build-src: preflight
build-src preflight: ok
/bin/sh: U+FEFFset: command not found
build-src: fresh output reset
/bin/sh: U+FEFFset: command not found
build-src: rbuild
/bin/sh: U+FEFFset: command not found
build-src: private decomment smoke failed
build-src: rbuild failed (exit 1)
```

The intended payload begins with ASCII `set -e`, but the redirected
`Process.StandardInput` stream uses a UTF-8 encoding whose preamble is
`EF BB BF`. A direct wire probe through the same SSH process configuration
produced exactly `ef bb bf 73 65 74 20 2d 65 0a`; Jaguar therefore attempts to
execute `U+FEFFset` rather than `set`. This disables fail-fast behavior in every
generated phase. The Rbuild smoke guard is a positive production assertion,
not the expected negative kernel-export fixture in the PowerShell tests; after
Fresh, state, repository, and tools all remained empty, so its message is not
evidence of a successfully executed private decomment binary.

The focused follow-up must make both streaming and capture SSH stdin explicitly
UTF-8 without a preamble and add a real process-boundary regression that checks
the first bytes received by a child. Testing only the in-memory `$payload`
string cannot detect a preamble added by `StreamWriter`. Exact wire facts,
normalized wrapper output, and zero-file stop snapshots are retained below
`/build/evidence/stdin-bom-d46988df`.

The stopped-boundary audit again passed exactly: 31,521 records and aggregate
checksum `1378348179 3042335` in both snapshots, with a zero-byte diff. Fresh
did not mutate `/System` or `/usr` before the transport failure.
