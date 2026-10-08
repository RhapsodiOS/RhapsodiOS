# OpenSSL 0.9.8zh and OpenSSH upgrade

## Goal

Replace the Darwin 0.3 OpenSSL 0.9.5a (April 2000) and OpenSSH 2.3.0p1
(October 2000) in `src/OpenSSL` and `src/OpenSSH` with the newest releases
that build with the host `cc` (Apple gcc 2.7.2.1/2.95-era), Perl 5.005 and
Rhapsody's libc, as universal (i386 + ppc) rbuild packages.

The wanted outcomes are security fixes, SSH interop with stock modern
clients, and TLS that can verify current certificate chains, as far as
those releases can deliver them.

## Non-goals

- A newer compiler, Perl, pthreads or libc. That is the prerequisite for
  OpenSSL 3.x and current OpenSSH, and is a separate project.
- Upstream support. Both release lines are end-of-life; this upgrade buys
  ten to fifteen years of fixes, not an ongoing security stream.
- TLS 1.1/1.2. They arrived in OpenSSL 1.0.1, so most modern HTTPS servers
  will still refuse 0.9.8zh.
- A zlib upgrade. If the chosen OpenSSH needs zlib newer than the system's
  1.1.3, that is recorded and handled separately (see the probe).
- Changing `docs/build/rhapsody-bootstrap.md`, which builds SSH on a stock
  host and does not use these packages.

## Current state

- Nothing in the tree links against `libcrypto`/`libssl`; cvs and ncftp only
  probe for them in `configure`.
- OpenSSL builds in one universal pass with no endian define and no asm,
  from a pre-generated `Makefile.ssl` and `crypto/opensslconf.h`
  (`3c7ea3755`), with `no-idea` because the tree's IDEA sources are empty.
  Its own `shlibs` step makes `libcrypto.0.9.dylib`/`libssl.0.9.dylib`.
- The OpenSSH project Makefile passes `-DBROKEN_GETADDRINFO
  -Dgetaddrinfo=fake_getaddrinfo -Dcrc32=crcsum32` and `--sysconfdir=/etc`;
  `Makefile.in` carries the make 3.74 `fixpaths` VPATH fix (`7b2e689f8`).
- `files-5/private/etc/startup/1700_IPServices` generates an RSA1
  `/etc/ssh_host_key` and a DSA `/etc/ssh_host_dsa_key` with 2.3.0
  `ssh-keygen` syntax, then starts `/usr/sbin/sshd`.
- Users are defined twice: the flat `passwd`/`master.passwd`/`group` files
  in `files-5/private/etc` (single-user mode, and the live media, which has
  no `lookupd`) and the binary NetInfo database
  `files-5/private/etc/netinfo/local.nidb` (what `lookupd` serves). Neither
  has an `sshd` user.

## Version selection

**OpenSSL** is fixed at **0.9.8zh**, the final 0.9.8 release (December
2015).

**OpenSSH** is the highest portable release that passes a probe on a
private snapshot guest (the bootstrapped i386 image with `-snapshot` on
port 2221, never the shared build box). A release passes when it:

1. supports OpenSSL 0.9.8zh according to its `INSTALL`/`configure`;
2. configures and builds universal with the host `cc` without invasive
   source changes (a handful of local portability fixes is acceptable; a
   C99-to-gnu89 rewrite is not);
3. accepts the system zlib 1.1.3, with `--without-zlib-version-check` if
   that release has the option.

The probe walks up from 3.2.3p1 and stops at the first release that fails;
the release before it ships. Milestones that matter:

| OpenSSH | Gains |
|---|---|
| 3.7 | `aes*-ctr` ciphers |
| 3.9 | `diffie-hellman-group14-sha1` |
| 5.7 | ECDH key exchange and ECDSA host keys |
| 5.8 | `ssh-keygen -A` |
| 6.5 | curve25519, ed25519 and chacha20-poly1305, all built in: stock OpenSSH 10 clients connect with no `-o` options |

The probe is throwaway. Its per-release result (pass, or the first failure
and why) is added to this spec as an appendix before implementation of the
OpenSSH tree starts.

## OpenSSL 0.9.8zh

### Tree

- One commit imports the pristine `openssl-0.9.8zh` tarball over
  `src/OpenSSL/openssl`, extracted with `core.autocrlf=false`.
- Labelled Rhapsody patch commits follow, starting with a
  `rhapsody-i386-cc` target in `Configure` beside the existing
  `rhapsody-ppc-cc`.

### Configure flags

No algorithm or feature is disabled by default: `no-idea`, `no-asm`,
`no-hw` and `no-sha512` are all gone. One is added back only when the guest
build proves it necessary, with a Makefile comment naming the error. SHA-512
is the expected candidate (64-bit arithmetic under gcc 2.x).

The hardware ENGINEs (`no-hw`) are built because they cost nothing if they
compile. With no `dlopen` on Rhapsody, OpenSSL's DSO layer falls back to its
null method and the engines simply fail to load. Random seeding comes from
the kernel's `/dev/urandom` either way.

### Per-arch build

The x86 perlasm and ppc (`ppc.pl` → `osx_ppc32`) assembly are per-arch, so
the single universal pass becomes, in the project Makefile:

1. Configure `rhapsody-i386-cc` (`-DL_ENDIAN`, x86 asm) and build in one
   build directory.
2. Configure `rhapsody-ppc-cc` (`-DB_ENDIAN`, ppc asm) and build in a
   second.
3. `lipo` the two `libcrypto.a`, `libssl.a` and `apps/openssl` into
   universal files, then run the existing `shlibs` and `strip` steps on
   them.
4. Install headers from one arch. If the two generated `opensslconf.h`
   differ, install one merged file with the differing parts under
   `#if defined(__ppc__)` / `#elif defined(__i386__)`.

If Rhapsody's cctools `as`, or perlasm under Perl 5.005, rejects an arch's
assembly, that arch alone falls back to `no-asm`, with a comment recording
the assembler error.

The `shadow_source` and `Version :=` steps follow 0.9.8's rename of
`Makefile.ssl` to `Makefile`.

### Libraries and paths

- Install names become `/usr/lib/libcrypto.0.9.8.dylib` and
  `/usr/lib/libssl.0.9.8.dylib` (the ABI changed), compatibility version
  0.9.8. `libcrypto.dylib`/`libssl.dylib` stay symlinks.
- `OPENSSLDIR` stays `/System/Library/OpenSSL`, where the ca-certificates
  package installs `cert.pem`, which 0.9.8 loads by default.
- `apk/pkginfo`: `pkgver = 0.9.8zh`; other fields unchanged.

## OpenSSH

### Tree

- One commit imports the pristine portable release chosen by the probe over
  `src/OpenSSH/openssh`.
- Each existing local workaround is carried forward only if retesting shows
  it is still needed:
  - `-Dcrc32=crcsum32` (upstream renamed its function to `ssh_crc32` in the
    3.x line);
  - `-DBROKEN_GETADDRINFO -Dgetaddrinfo=fake_getaddrinfo` (against
    `openbsd-compat`'s fake-rfc2553);
  - the `fixpaths` VPATH fix, if `Makefile.in` still has that rule.

### Configure

- `--sysconfdir=/etc` stays, so `sshd_config` and host keys stay in `/etc`.
- Add `--with-privsep-user=sshd --with-privsep-path=/var/empty`.
- Add `--without-zlib-version-check` if the probe found it necessary.

### Universal build

OpenSSH has no assembly and stays a single universal pass. autoconf
measures the build arch, so a post-configure step checks `config.h` for
arch-dependent results (`WORDS_BIGENDIAN`, `SIZEOF_*`, and anything else
the probe shows differing between an i386 and a ppc configure) and wraps
them in `__BIG_ENDIAN__`/`__ppc__` guards, so the ppc slice does not
inherit the i386 guest's answers.

### Packaging

- `apk/pkginfo`: `pkgver` set to the chosen release.
- Clients in `/usr/bin`, `sshd` in `/usr/sbin`, `sftp-server` and
  `ssh-keysign` in `/usr/libexec`.
- Man pages stay disabled, as today.
- Root keeps password logins: the vm tooling logs in as `root` with a
  password, and root is a fresh install's main account. If the chosen
  release's default `PermitRootLogin` is anything but `yes` (7.0 and later
  default to `prohibit-password`), a labelled patch sets `PermitRootLogin
  yes` in the shipped `sshd_config`.

## files: privsep user, /var/empty, startup

### sshd user and group

uid and gid 75 (the numbers Mac OS X later used for `sshd`):

- Flat files in `files-5/private/etc`:
  - `passwd`: `sshd:*:75:75:sshd Privilege separation:/var/empty:/noshell`
  - `master.passwd`: the matching 10-field entry
  - `group`: `sshd:*:75:`
- NetInfo `local.nidb`: matching `/users/sshd` (`name`, `passwd` `*`,
  `uid` 75, `gid` 75, `realname`, `home` `/var/empty`, `shell` `/noshell`)
  and `/groups/sshd` (`name`, `passwd` `*`, `gid` 75).

The `local.nidb` edit is made on a private snapshot guest:

1. Copy the checked-in `local.nidb` into the guest's `/etc/netinfo` under a
   scratch tag.
2. Serve that tag with its own `netinfod` and add the two records with
   `niutil -t localhost/<tag>`.
3. Stop that `netinfod`, copy `Collection` and `Transaction` back into the
   tree, and remove the scratch tag.

The commit message carries a `nidump passwd` and `nidump group` diff of the
old and new databases, showing that only the two `sshd` records were added.

### /var/empty

A new `empty` directory in `files-5/private/var`, `root:wheel`, mode 755.
sshd refuses a privsep path that is group- or world-writable or not owned
by root.

### Host keys and startup

In `1700_IPServices`:

- If the chosen release is 5.8 or later, the key-generation block becomes
  `ssh-keygen -A`, which creates each key type the release supports and
  skips existing ones.
- Otherwise it becomes per-file checks with explicit `-t rsa`, `-t dsa`
  (and `-t ecdsa` from 5.7), like `rhapsody-bootstrap.md`.
- Existing `/etc/ssh_host_*` keys are never touched.
- The sshd start line stays `/usr/sbin/sshd &`.

## Tooling and docs

- `vm/rhap-remote.ps1` and `vm/SSH CONNECTION.md` change their legacy
  `-o KexAlgorithms=…`, `HostKeyAlgorithms=…`, `Ciphers=…` and `MACs=…`
  options from replacing the lists to appending to them (`=+…`), so one
  command line reaches both the old host-built sshd on existing guests and
  the new packaged one.

## Testing

All runs use a private snapshot guest. The shared build box is never used.

OpenSSL:

- `make test` passes on the i386 build.
- `lipo -info` shows i386 and ppc in `libcrypto.0.9.8.dylib`,
  `libssl.0.9.8.dylib` and `openssl`.
- On the guest, `openssl s_client -CAfile /System/Library/OpenSSL/cert.pem`
  verifies a connection to an `openssl s_server -tls1` on the Windows host
  whose chain is SHA-256-signed by a test CA.
- The ppc slice is built and inspected but not run: there is no ppc runtime
  box. The results say so.

OpenSSH:

- On a guest with the new `files`, `openssl` and `openssh` apks installed,
  `1700_IPServices` generates host keys and starts `sshd`.
- `ps` shows sshd's network child running as uid 75.
- The stock Windows OpenSSH client logs in with no `-o` options if the
  release is 6.5 or later, otherwise with the minimal appended set that
  `vm/SSH CONNECTION.md` documents. A file round-trips through `scp` and
  through `sftp`.
- Multi-user: `niutil -read . /users/sshd` finds the record. Single-user:
  `/etc/passwd` has the `sshd` entry.
- `vm/rhap-remote.ps1` reaches both an old host-built sshd guest and the
  new packaged one.

## Commits

Per project: one pristine-import commit, then labelled patch commits
(`OpenSSL: …`, `OpenSSH: …`, `files: …`, `vm: …`), each describing what it
changes.

## Appendix: OpenSSH probe results

Filled in by the probe before the OpenSSH tree is imported.
