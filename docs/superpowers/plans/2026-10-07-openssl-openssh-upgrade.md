# OpenSSL 0.9.8zh and OpenSSH Upgrade Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the in-tree OpenSSL 0.9.5a and OpenSSH 2.3.0p1 with OpenSSL 0.9.8zh and the newest OpenSSH the host `cc` builds, as universal rbuild apks, with a privsep `sshd` user and an sshd that stock modern clients reach.

**Architecture:** Each project gets a pristine upstream import commit followed by labelled Rhapsody patch commits. OpenSSL builds once per arch with its asm and is `lipo`'d universal. OpenSSH builds in one universal pass with a post-configure `config.h` arch guard. `files-5` gains the `sshd` user (flat files and NetInfo), `/var/empty` and new key generation. Everything is built and checked on a private `-snapshot` i386 guest.

**Tech Stack:** OpenSSL 0.9.8zh `Configure`/perlasm; OpenSSH portable autoconf; CoreOS ReleaseControl `GNUSource.make` under GNU Make 3.74; rbuild; NetInfo (`netinfod`, `niutil`, `nidump`); PowerShell guest helpers in `vm/`; QEMU.

**Spec:** `docs/superpowers/specs/2026-10-07-openssl-openssh-upgrade-design.md`

## Global Constraints

- Work in the worktree `D:\RhapsodiOS\.claude\worktrees\openssl-openssh` (branch `openssl-openssh`, from `master`). Never `git add`/`git commit` in `D:\RhapsodiOS` itself: other sessions share its index.
- Commit messages: one or two lines, starting with the subsystem (`OpenSSL: `, `OpenSSH: `, `files: `, `vm: `, `docs: `), describing what changes. **No trailers or metadata of any kind** (CLAUDE.md).
- Versions: OpenSSL `0.9.8zh`. OpenSSH: the release Task 3 records in the spec appendix, written below as `<SSHVER>` (e.g. `6.6p1`).
- Downloads need the user's explicit go-ahead first. Give each filename, its source URL and its size when asking. Keep the tarballs in `D:\RhapsodiOS\vm\work\openssl-openssh\`, not in the worktree (worktrees can vanish while idle).
- Pristine imports are extracted with no line-ending conversion, and all guest transfers use `git -c core.autocrlf=false`. After any sync, `tr -cd '\r' < <proj>/Makefile | wc -c` must print `0` on the guest.
- OpenSSL Configure options are exactly `--prefix=/usr --openssldir=/System/Library/OpenSSL rhapsody-<arch>-cc`. `no-idea`, `no-asm`, `no-hw` and `no-sha512` are **not** passed. One is added only after a build proves it necessary, scoped to the failing arch where possible, with a Makefile comment quoting the error.
- OpenSSL install layout stays as today: libraries in `/usr/lib`, `openssl` and `c_rehash` in `/usr/bin`, headers in `/usr/local/include/openssl`, `OPENSSLDIR` `/System/Library/OpenSSL`. Install names: `/usr/lib/libcrypto.0.9.8.dylib` and `/usr/lib/libssl.0.9.8.dylib`, compatibility version `0.9.8`, with `libcrypto.dylib` and `libssl.dylib` symlinks.
- OpenSSH configure keeps `--sysconfdir=/etc --disable-suid-ssh` where the release still accepts it, and adds `--with-privsep-user=sshd --with-privsep-path=/var/empty`. `--without-zlib-version-check` is added only if the Task 3 appendix says so.
- sshd user: `sshd`, uid 75, gid 75, home `/var/empty`, shell `/noshell`, passwd `*`, realname `sshd Privilege separation`. Group `sshd`, gid 75, passwd `*`.
- Shipped `sshd_config` has `PermitRootLogin yes`.
- Guest: a private guest booted from `vm/work/rhap-i386-bootstrapped.img` with `-snapshot` and `-display none`. Use ssh `127.0.0.1:2231 -> :22`, telnet `127.0.0.1:2331 -> :23`, and QMP `tcp:127.0.0.1:4471`; other sessions use 2221/2222. Never touch the shared box on 2222, and never write or delete the base image. Quit only with QMP `quit` on 4471, never by killing qemu by name. Stop the guest with `/sbin/reboot`, never `halt`, and never let `fsck -y` run on it.
- Guest working area: `/build/ossl` only. Private repository `/build/ossl/repo`: hard links of `/build/repo/*` plus the apks built here. rbuild is `/build/tools/bin/rbuild`; universal builds use `--toolchain /build/src/rbuild-1/toolchains/gcc-darwin-universal.conf`. Delete an old apk before rebuilding the same version. Copy every apk to `vm\work\openssl-openssh\apks\` with `vm\guest-remote.ps1 -Fetch` as soon as it is built: a `-snapshot` guest loses everything when it stops.
- Guest shell: `ls` exits 0 for missing paths, so test existence with `test -f`/`test -d`. GNU Make 3.74 has no `$(call)`, `$(if)` or target-specific variables, and a later duplicate rule wins silently.
- The ppc slices are built and inspected (`lipo -info`, `otool -L`) but never run. Results must say so.

## Shell variables used throughout

Every host command runs from Git Bash and assumes:

```bash
W=/d/RhapsodiOS/.claude/worktrees/openssl-openssh
V=/d/RhapsodiOS/vm/work/openssl-openssh
S=<this session's scratchpad>
```

The scratch `vm.conf` for the private guest lives in `$S` (`Port=2231`, `RemoteRoot=/build/ossl`, `LocalRoot=` the worktree). It holds the guest password, so delete it when finished. Commands that pass `/`-leading arguments to Windows programs need `MSYS_NO_PATHCONV=1`.

## File Map

| Path | Task | Responsibility |
|---|---|---|
| `src/OpenSSL/openssl/**` | 1, 2 | Pristine 0.9.8zh, then the `rhapsody-i386-cc`/`rhapsody-ppc-cc` Configure targets |
| `src/OpenSSL/Makefile` | 2 | Per-arch configure/build/install, `lipo`, header merge, `shlibs`, `strip`, `test` |
| `src/OpenSSL/apk/pkginfo` | 2 | `pkgver = 0.9.8zh` |
| `docs/superpowers/specs/2026-10-07-openssl-openssh-upgrade-design.md` | 3, 9 | Probe appendix; verification results |
| `src/OpenSSH/openssh/**` | 4, 5 | Pristine `<SSHVER>`, then only the retested local fixes and `PermitRootLogin yes` |
| `src/OpenSSH/Makefile` | 5 | Configure flags, post-configure `config.h` arch guard |
| `src/OpenSSH/archguard.sh` | 5 | Rewrites arch-dependent `config.h` defines under `__BIG_ENDIAN__` guards |
| `src/OpenSSH/apk/pkginfo` | 5 | `pkgver = <SSHVER>` |
| `src/files-5/private/etc/{passwd,master.passwd,group}` | 6 | Flat-file `sshd` user and group |
| `src/files-5/private/var/Makefile` | 6 | `empty` added to `EMPTYDIRS` |
| `src/files-5/private/etc/startup/1700_IPServices` | 6 | Host-key generation for the new release |
| `src/files-5/private/etc/netinfo/local.nidb/{Collection,Transaction}` | 7 | NetInfo `sshd` records |
| `vm/rhap-remote.ps1`, `vm/SSH CONNECTION.md` | 8 | Appended (`=+`) legacy algorithm options |

## Review Focus

1. **An upgraded root keeps its 2.3.0-era `/etc/sshd_config`.** apk protects `private/etc`, so the new sshd may meet an old config whose directives it no longer knows. A person expects sshd to keep starting after the upgrade. Task 9 runs `sshd -t` on the 2.3.0 config. If that is fatal, stop and report it to the user, because the spec does not decide what happens then.
2. **Existing RSA1 and DSA host keys in `/etc`.** A person expects sshd to start beside them and keygen to leave them alone. Task 9 keeps the old keys on the test guest and checks that they are unchanged afterwards.
3. **Modern `scp` uses SFTP by default.** A person expects both `scp` and `scp -O` (the legacy protocol) to work. Task 9 tests both.
4. **A thin build (`--arch i386`).** The per-arch OpenSSL Makefile must work with one arch in `RC_ARCHS` too. Task 2 builds both a thin and a universal apk.
5. **A ppc slice built from i386-measured answers.** In OpenSSH this is `config.h`; in OpenSSL it is `opensslconf.h`. A person expects ppc byte order and type sizes to come out right. Tasks 2 and 5 diff the per-arch outputs and assert the guards.

---

### Task 1: Import OpenSSL 0.9.8zh

**Files:**
- Replace: `src/OpenSSL/openssl/**`

**Interfaces:**
- Produces: a pristine `openssl-0.9.8zh` tree at `src/OpenSSL/openssl`. `Configure` and `Makefile` are at the top level, and there is no `Makefile.ssl`.

- [ ] **Step 1: Create the worktree.** `git worktree add .claude/worktrees/openssl-openssh -b openssl-openssh master` from `D:\RhapsodiOS`.
- [ ] **Step 2: Ask for the download go-ahead**, naming `openssl-0.9.8zh.tar.gz` and `openssl-0.9.8zh.tar.gz.sha256` from `https://www.openssl.org/source/old/0.9.x/` with their sizes. Ask about the OpenSSH probe tarballs in the same message (see Task 3, Step 1), so the user approves once.
- [ ] **Step 3: Download into `$V` and verify.** Expected: `sha256sum openssl-0.9.8zh.tar.gz` matches the `.sha256` file.
- [ ] **Step 4: Replace the tree.** `git rm -r -q src/OpenSSL/openssl`, then extract the tarball, rename `openssl-0.9.8zh` to `src/OpenSSL/openssl`, and `git add` it. Expected: `grep OPENSSL_VERSION_TEXT src/OpenSSL/openssl/crypto/opensslv.h` shows `0.9.8zh`, and `git diff --cached --stat | tail -1` shows only `src/OpenSSL/openssl` paths.
- [ ] **Step 5: Check line endings and modes.** Expected: `git diff --cached | grep -c $'\r'` prints `0`, and `Configure` and `config` are mode `100755` in `git ls-files -s`.
- [ ] **Step 6: Commit** `OpenSSL: import pristine 0.9.8zh over 0.9.5a`.

### Task 2: Build OpenSSL universal per arch with asm

**Files:**
- Modify: `src/OpenSSL/openssl/Configure` (the `rhapsody-ppc-cc` line; add `rhapsody-i386-cc`)
- Modify: `src/OpenSSL/Makefile`
- Modify: `src/OpenSSL/apk/pkginfo`

**Interfaces:**
- Consumes: Task 1's tree.
- Produces: `openssl-0.9.8zh-universal.apk` (and an i386 thin apk) in `/build/ossl/repo`, installing `/usr/lib/libcrypto.0.9.8.dylib` and `/usr/lib/libssl.0.9.8.dylib`. Task 3 and Task 5 build against it.

- [ ] **Step 1: Configure targets.**
  - Edit `rhapsody-ppc-cc`: keep its compiler flags, and take its asm fields (cpu-specific objects and perlasm flavour) from 0.9.8zh's `darwin-ppc-cc` line.
  - Add `rhapsody-i386-cc` beside it: `cc:-O3 -DL_ENDIAN` with `BN_LLONG ${x86_gcc_des} ${x86_gcc_opts}`, and the asm fields from `darwin-i386-cc`.
  - In both, the dso and shared fields stay empty, because Rhapsody has no `dlfcn`.
  - Commit `OpenSSL: add Rhapsody i386 and ppc Configure targets that build the Darwin assembly`.
- [ ] **Step 2: Rewrite the project Makefile build.** It still includes `GNUSource.make`, but overrides configure, build and install with recipes that loop `for arch in $(RC_ARCHS)` in shell (make 3.74 has no `$(call)`). For each arch:
  1. shadow the source into `$(OBJROOT)/$$arch`;
  2. run `./Configure` with the Global Constraints options and `rhapsody-$$arch-cc`;
  3. build with `CC="cc -arch $$arch"` and the existing `AR`;
  4. run `make install INSTALL_PREFIX=$(OBJROOT)/dst-$$arch`.

  Then:
  - `lipo -create` each arch's `libcrypto.a`, `libssl.a` and `bin/openssl` into `$(DSTROOT)`.
  - Copy everything else from the first arch's tree.
  - If `opensslconf.h` differs between arches, install a merged file with the differing hunks under `#if defined(__ppc__)` / `#elif defined(__i386__)` (a single arch installs it unchanged).
  - `Version`/`FileVersion` come from `VERSION=` in the top-level `Makefile`, and `FileVersion` becomes `0.9.8`. `shlibs` and `strip` stay as they are.
  - `test::` runs `make test` in `$(OBJROOT)/i386`.
  - Commit `OpenSSL: build each arch with its assembly and lipo the results universal`.
- [ ] **Step 3: Set `pkgver = 0.9.8zh`** in `apk/pkginfo` and commit `OpenSSL: package 0.9.8zh`.
- [ ] **Step 4: Boot the private guest** (Global Constraints ports) and set up `/build/ossl/{src,repo}`. Expected: `ssh` reaches it on 2231, and `test -d /build/ossl/repo` succeeds.
- [ ] **Step 5: Sync and build universal.** `sync-src.ps1 -Path OpenSSL` with the scratch `vm.conf`, then on the guest run `rbuild buildpackage --toolchain .../gcc-darwin-universal.conf /build/ossl/src/OpenSSL /build/ossl/repo /build/ossl/repo`. Expected: exit 0. If an arch's asm fails to assemble, re-run that arch's make with `-k` in the leftover root to see every error. Then fall back that arch alone to `no-asm`, or add `no-sha512` if SHA-512 fails, with the error quoted in a Makefile comment and its own commit. Fetch the apk at once.
- [ ] **Step 6: Inspect the apk.** Extract it into `/build/ossl/inspect`. Expected:
  - `lipo -info` on `usr/lib/libcrypto.0.9.8.dylib`, `usr/lib/libssl.0.9.8.dylib` and `usr/bin/openssl` reports `ppc i386`;
  - `otool -L usr/bin/openssl` shows both `/usr/lib/lib*.0.9.8.dylib` install names with compatibility version `0.9.8`;
  - `usr/lib/libcrypto.dylib` is a symlink to `libcrypto.0.9.8.dylib`;
  - `opensslconf.h` defines no `OPENSSL_NO_IDEA`, `OPENSSL_NO_HW` or `OPENSSL_NO_ASM` (and no `OPENSSL_NO_SHA512` unless Step 5 added it);
  - if the arches differed, the guard pattern is present, and `cc -arch ppc -E`/`cc -arch i386 -E` of a file that includes it each yield that arch's original values.
- [ ] **Step 7: Run `make test` on i386.** Run the project's `test` target on the guest with `RC_ARCHS=i386`. Expected: the run ends with OpenSSL's `ALL TESTS SUCCESSFUL` (or the 0.9.8 equivalent), with no failing test.
- [ ] **Step 8: Build thin.** Run the same buildpackage with `--toolchain .../gcc-darwin-i386.conf --arch i386`. Expected: exit 0, and `lipo -info` of `libcrypto.0.9.8.dylib` reports i386 only. Fetch the apk.
- [ ] **Step 9: Run the TLS check.**
  - On the host, make a SHA-256 test CA and a server cert for `10.10.0.2` with Python driving host `openssl`.
  - Run `openssl s_server -accept 4433 -tls1 -cipher DEFAULT@SECLEVEL=0 -cert ... -key ...`.
  - On the guest, with the extracted `openssl`, run `s_client -connect 10.10.0.2:4433 -tls1 -CAfile /build/ossl/bundle.pem`, where `bundle.pem` is `cert.pem` from the ca-certificates apk plus the test CA.

  Expected: `Verify return code: 0 (ok)` and `Protocol  : TLSv1`. Record the commands and output for Task 9.

### Task 3: Probe the newest OpenSSH that builds (throwaway)

**Files:**
- Modify: `docs/superpowers/specs/2026-10-07-openssl-openssh-upgrade-design.md` (appendix only)

**Interfaces:**
- Consumes: Task 2's universal openssl apk.
- Produces: `<SSHVER>`, plus whether it needs `--without-zlib-version-check`, written in the spec appendix. Tasks 4 to 9 use them.

- [ ] **Step 1: Downloads** (approved in Task 1, Step 2). Get the portable tarballs and their `.asc` signatures from `https://cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/` into `$V/probe/`, in this test order:
  - milestones `3.7.1p2`, `3.9p1`, `5.7p1`, `5.8p2`, `6.5p1`;
  - then every later release in order, starting from `6.6p1`.

  Verify each with `gpg --verify` against the release key published in the same directory. Fetch later tarballs only as the ladder reaches them.
- [ ] **Step 2: Prepare the probe root.** Extract the openssl apk to `/build/ossl/sslroot`. Each probe runs in `/build/ossl/probe/<ver>`.
- [ ] **Step 3: Probe each release in order.** For each one:
  1. Read its `INSTALL`/`configure` OpenSSL minimum. A minimum above 0.9.8zh means **fail**.
  2. Run `./configure --sysconfdir=/etc --with-privsep-user=sshd --with-privsep-path=/var/empty` with `CPPFLAGS=-I/build/ossl/sslroot/usr/local/include` and `LDFLAGS=-L/build/ossl/sslroot/usr/lib`. If configure rejects zlib 1.1.3, retry once with `--without-zlib-version-check` and note it.
  3. Run `make CC="cc -arch i386 -arch ppc"`.

  A release **passes** when all of that succeeds with at most a handful of small local portability fixes, each written down. It **fails** when it needs C99-to-gnu89 rewriting or a newer OpenSSL. Stop at the first failure. If the last pass and the first failure are milestones more than one release apart, probe the releases in between to find the last one that passes.
- [ ] **Step 4: Fill the appendix.** Add a table of every probed release (pass, or the first error), the chosen `<SSHVER>`, its local fixes, and whether it needs `--without-zlib-version-check`. Commit `docs: record the OpenSSH probe and choose <SSHVER>`.
- [ ] **Step 5: Show the user the appendix** before Task 4, since it picks the shipped version.

### Task 4: Import OpenSSH `<SSHVER>`

**Files:**
- Replace: `src/OpenSSH/openssh/**`

**Interfaces:**
- Consumes: `<SSHVER>` from Task 3.
- Produces: a pristine portable tree at `src/OpenSSH/openssh`.

- [ ] **Step 1: Replace the tree** the same way as Task 1, Steps 4 and 5. Expected: `version.h` names `<SSHVER>`, there are no CRs, and `configure` is `100755`.
- [ ] **Step 2: Commit** `OpenSSH: import pristine <SSHVER> over 2.3.0p1`.

### Task 5: Build OpenSSH universal

**Files:**
- Modify: `src/OpenSSH/Makefile`
- Create: `src/OpenSSH/archguard.sh`
- Modify: `src/OpenSSH/openssh/sshd_config` (only if the default `PermitRootLogin` is not `yes`)
- Modify: `src/OpenSSH/openssh/**` (only the Task 3 fixes, and the `fixpaths` VPATH fix if `Makefile.in` still has that rule)
- Modify: `src/OpenSSH/apk/pkginfo`

**Interfaces:**
- Consumes: Task 2's openssl apk in `/build/ossl/repo`, and Task 4's tree.
- Produces: `openssh-<SSHVER>-universal.apk`, with `sshd` at `/usr/sbin/sshd`, clients in `/usr/bin`, `sftp-server` and `ssh-keysign` in `/usr/libexec`, and `sshd_config` in `/private/etc`. Task 9 installs it.
- `archguard.sh <config.h>`: rewrites `config.h` in place. Every `#define`/`#undef` it knows to be arch-dependent becomes a block guarded by `__BIG_ENDIAN__`. It exits non-zero if the file has an arch-dependent macro it does not know.

- [ ] **Step 1: Measure what differs.** On the guest, configure the pristine tree twice in scratch dirs, once with `CC="cc -arch i386"` and once with `CC="cc -arch ppc"`, and `diff` the two `config.h`. Expected: a short list (at least `WORDS_BIGENDIAN`). That list is `archguard.sh`'s known-macro set.
- [ ] **Step 2: Write `archguard.sh`** for that list. Hook it into the Makefile after configure. Expected: run on the i386 `config.h`, `cc -arch ppc -E -dM` of a file including it matches the ppc `config.h` values for every listed macro, and `cc -arch i386 -E -dM` matches the i386 values.
- [ ] **Step 3: Set the Makefile flags.** Use the Global Constraints configure flags. Drop `-Dcrc32=crcsum32`, `-DBROKEN_GETADDRINFO` and `-Dgetaddrinfo=fake_getaddrinfo`, and bring each one back only if the build or the login test in Task 9 fails without it, with a comment saying why. Keep `MANPAGES=""` and `--disable-suid-ssh` if configure still accepts it. Commit `OpenSSH: configure <SSHVER> with sshd privsep and guard arch-dependent config.h results`.
- [ ] **Step 4: Root login.** If `sshd_config`'s `PermitRootLogin` default is not `yes`, set `PermitRootLogin yes` and commit `OpenSSH: allow root password logins in the shipped sshd_config`. Apply each Task 3 fix in its own `OpenSSH: ...` commit.
- [ ] **Step 5: Set `pkgver = <SSHVER>`** and commit `OpenSSH: package <SSHVER>`.
- [ ] **Step 6: Build.** Sync, then run `rbuild buildpackage` universal into `/build/ossl/repo`. Expected: exit 0. Fetch the apk at once.
- [ ] **Step 7: Inspect.** Expected:
  - `lipo -info` of `usr/sbin/sshd`, `usr/bin/ssh` and `usr/libexec/sftp-server` reports `ppc i386`;
  - `otool -L usr/bin/ssh` lists `/usr/lib/libcrypto.0.9.8.dylib`;
  - `private/etc/sshd_config` contains an uncommented `PermitRootLogin yes`, or the release's compiled default is `yes`;
  - `usr/sbin/sshd -t -f <extracted sshd_config>` run on the guest reports only the missing host keys.

### Task 6: files — sshd user, /var/empty, key generation

**Files:**
- Modify: `src/files-5/private/etc/passwd`, `master.passwd`, `group`
- Modify: `src/files-5/private/var/Makefile`
- Modify: `src/files-5/private/etc/startup/1700_IPServices`

**Interfaces:**
- Produces: the flat-file `sshd` entries, `/private/var/empty` (`root:wheel`, 755), and a key block that matches `<SSHVER>`.

- [ ] **Step 1: Add the flat-file entries.** Append to `passwd`: `sshd:*:75:75:sshd Privilege separation:/var/empty:/noshell`. Append to `master.passwd`: `sshd:*:75:75::0:0:sshd Privilege separation:/var/empty:/noshell`. Append to `group`: `sshd:*:75:`. Expected: each file still has no CR or non-ASCII byte (`file` says `ASCII text`).
- [ ] **Step 2: Add `empty` to `EMPTYDIRS`** in `private/var/Makefile`. Expected: on the guest, `make install DSTROOT=/build/ossl/files-dst` in `files-5/private/var` creates `private/var/empty`, and `ls -ld` on it shows `drwxr-xr-x root wheel`.
- [ ] **Step 3: Replace the key block** in `1700_IPServices`:
  - If `<SSHVER>` is 5.8 or later: `ssh-keygen -A`.
  - Otherwise, one `if [ ! -f /etc/ssh_host_<type>_key ]` check per type `<SSHVER>` supports (`rsa`, `dsa`, plus `ecdsa` from 5.7), each running `ssh-keygen -t <type> -f /etc/ssh_host_<type>_key -N ""`.
  - The `ConsoleMessage` and `/usr/sbin/sshd &` lines stay. Old `/etc/ssh_host_key` and `/etc/ssh_host_dsa_key` are never removed.

  Expected: `sh -n 1700_IPServices` exits 0.
- [ ] **Step 4: Commit** `files: add the sshd privsep user and /var/empty, and generate current host key types`.

### Task 7: files — NetInfo sshd records

**Files:**
- Modify: `src/files-5/private/etc/netinfo/local.nidb/Collection`, `Transaction`

**Interfaces:**
- Produces: a `local.nidb` holding `/users/sshd` and `/groups/sshd` with the Global Constraints values, and no other change.

- [ ] **Step 1: Dump the old database for comparison.** Copy the checked-in `local.nidb` to the guest as `/private/etc/netinfo/osslscratch.nidb`. Start `netinfod osslscratch`, then run `nidump -t localhost/osslscratch passwd .` and `nidump -t ... group .` into `/build/ossl/nidb-before.{passwd,group}`.
- [ ] **Step 2: Add the records.** `niutil -t localhost/osslscratch -create /users/sshd`, then `-createprop` for `name`, `passwd` (`*`), `uid` (75), `gid` (75), `realname`, `home` and `shell`. Do the same for `/groups/sshd` with `name`, `passwd` and `gid`.
- [ ] **Step 3: Verify the records.** Expected: `niutil -t localhost/osslscratch -read /users/sshd` shows exactly the Global Constraints values, and `diff nidb-before.passwd nidb-after.passwd` (and the same for group) shows exactly one added `sshd` line each.
- [ ] **Step 4: Copy back and clean up.** Kill that `netinfod` by its pid (not by name). Copy `Collection` and `Transaction` back into the worktree, then remove `osslscratch.nidb` from the guest.
- [ ] **Step 5: Re-verify from the tree.** Serve the copied-back files under a fresh scratch tag and re-run the Step 3 checks. Expected: same result.
- [ ] **Step 6: Commit** `files: add the sshd user and group to the local NetInfo database`. Use a second commit-message paragraph holding the two `nidump` diffs: they are the review evidence for a binary change.

### Task 8: vm — appended legacy SSH options

**Files:**
- Modify: `vm/rhap-remote.ps1:20-23`
- Modify: `vm/SSH CONNECTION.md`

**Interfaces:**
- Produces: `$script:RhapLegacySshOptions` using `KexAlgorithms=+diffie-hellman-group1-sha1`, `HostKeyAlgorithms=+ssh-dss`, `Ciphers=+3des-cbc` and `MACs=+hmac-sha1`. All other options are unchanged.

- [ ] **Step 1: Change the four options** to the `=+` form, and update `SSH CONNECTION.md`'s login line and prose to say the legacy algorithms are appended to the client defaults.
- [ ] **Step 2: Check against the old sshd.** Run `vm\guest-remote.ps1 -Run "uname -a"` with the scratch `vm.conf` against the private guest, which still runs its host-built 3.2.3p1 sshd. Expected: exit 0 and Rhapsody's `uname` output.
- [ ] **Step 3: Commit** `vm: append the legacy SSH algorithms to the client defaults so both old and new sshd answer`.

### Task 9: End-to-end on the guest, and record the results

**Files:**
- Modify: `docs/superpowers/specs/2026-10-07-openssl-openssh-upgrade-design.md` (a "Verification results" appendix)

**Interfaces:**
- Consumes: the apks from Tasks 2 and 5, the `files-5` changes from Tasks 6 and 7, and `vm/rhap-remote.ps1` from Task 8.

- [ ] **Step 1: Save the old sshd state** on the private guest: copy `/etc/sshd_config` (the guest's own) to `/build/ossl/old-sshd_config`, and record `md5` of each `/etc/ssh_host_*`. If the guest has no 2.3.0-era `sshd_config`, use the one from the old tree (`git show master:src/OpenSSH/openssh/sshd_config`).
- [ ] **Step 2: Install.**
  - Extract the openssl and openssh universal apks over `/` with `gzip -dc | pax -r -pe` (dropping `.PKGINFO` and the install scripts).
  - Install Task 6's `passwd`, `master.passwd`, `group` and `1700_IPServices`, and create `/private/var/empty` (`root:wheel`, 755).
  - Add the Task 7 records to the guest's live local domain with `niutil -create`/`-createprop` (the guest's own `local.nidb` holds its credentials, so it is not replaced).
  - Make sure `SSHSERVER=-YES-` is in `/etc/hostconfig`, and that nothing in the guest's startup still launches `/usr/local/sbin/sshd`.
- [ ] **Step 3: Reboot** with `/sbin/reboot`. Expected: within a few minutes, one `ssh` attempt on 2231 succeeds. If it doesn't, log in over telnet on 2331 and read `/var/log/system.log`.
- [ ] **Step 4: Check the server side.** Expected:
  - `/usr/sbin/sshd` is the running daemon;
  - the `/etc/ssh_host_*` key types `<SSHVER>` supports exist;
  - the Step 1 checksums of the old keys are unchanged;
  - during a login, `ps -axo uid,command` shows the `sshd` network child with uid 75;
  - `niutil -read . /users/sshd` finds the record;
  - `grep '^sshd:' /etc/passwd` prints the entry.
- [ ] **Step 5: Check the client side**, from the stock Windows OpenSSH client with no `-o` options if `<SSHVER>` ≥ 6.5 (otherwise only the appended options from `SSH CONNECTION.md`):
  - root password login works;
  - `scp` and `scp -O` each round-trip a 1 MB file with an identical `sha256sum`;
  - an `sftp` `put`/`get` round-trip works.
- [ ] **Step 6: Check the tooling and the upgrade case.**
  - `vm\guest-remote.ps1 -Run "uname -a"` against this guest exits 0.
  - `/usr/sbin/sshd -t -f /build/ossl/old-sshd_config`: expected exit 0 (warnings allowed). If it is fatal, stop and report it to the user (Review Focus 1).
- [ ] **Step 7: Record the results.** Add a "Verification results" appendix to the spec with a table of every check from Tasks 2 and 9 and its result. It must say that the ppc slices were built and inspected, not run. Commit `docs: record the OpenSSL 0.9.8zh and OpenSSH <SSHVER> verification`.
- [ ] **Step 8: Clean up.** Send QMP `quit` on 4471, delete the scratch `vm.conf`, and confirm the base image's mtime is unchanged.
