# ca-certificates package

## Goal

Ship Mozilla's trusted root CA certificates as an apk, installed in one
common place, so that OpenSSL and anything ported later find them without
configuration. The project is `src/ca-certificates-1`. rbuild packages it as
`ca-certificates-<pkgver>-1-universal.apk` (rbuild takes the `-1` from the
directory name), and it is listed in `src/Manifest`.

## Non-goals

- Making the certificates usable by the in-tree OpenSSL 0.9.5a for modern
  chains. That release predates SHA-256 and elliptic-curve signatures, so it
  is expected to load these roots (read from its source, not run) but cannot
  verify most current server chains. Fixing that is an OpenSSL upgrade, not
  this package.
- Hashed `<hash>.0` links in `certs/`. `cert.pem` is what libssl's default
  paths load, so `certs/` is storage only and cannot serve as a CApath. The
  links can be added later, either with `c_rehash` at build time or from a
  precomputed list.
- An `update-ca-certificates` script, install scripts, or runtime
  dependencies. rbuild's `pkginfo` has no `depends` key.
- Trust customisation (local CAs, per-CA disabling).

## Source of the PEM files

Mozilla publishes only `certdata.txt` (NSS format), not PEMs. We take
curl.se's `cacert.pem` (<https://curl.se/docs/caextract.html>), which curl's
`mk-ca-bundle` generates from `certdata.txt` and filters to TLS server-auth
trust. curl publishes a SHA-256 beside each release. The conversion is curl's,
not Mozilla's own.

The upstream bundle is split into one PEM per CA and the pieces are checked
in. The bundle itself is not checked in, so the repo holds one copy of the
data.

## Layout of `src/ca-certificates-1/`

```
Makefile        Common.make wrapper, like pico-1: an install:: recipe only
apk/pkginfo     pkgname=ca-certificates, pkgver=<YYYYMMDD>, license=MPL-2.0,
                url=https://curl.se/docs/caextract.html, makedepends=build-base
certs/*.pem     one PEM per root; the CA label is kept as a comment above BEGIN
SOURCE          upstream file name, Mozilla date line, SHA-256 of the original
                cacert.pem, cert count, an MPL 2.0 statement, and cacert.pem's
                header verbatim
refresh.py      host-side maintainer tool, never run in the guest
tests/          unittest suite for refresh.py
```

`pkgver` is the date in `cacert.pem`'s "Certificate data from Mozilla as of:"
line, as `YYYYMMDD`. rbuild appends the directory's `-1`, so `.PKGINFO` says
`pkgver = <YYYYMMDD>-1` and the apk is named
`ca-certificates-<YYYYMMDD>-1-universal.apk`.

`src/Manifest` gets `dir     ca-certificates-1     all`, placed before `cc-1`.
`BootstrapManifest` is untouched.

## What the apk installs

| Path | What it is |
|---|---|
| `/System/Library/OpenSSL/certs/<Name>.pem` | the per-CA PEMs, mode 0444 |
| `/System/Library/OpenSSL/cert.pem` | the bundle, `cat` of `certs/*.pem` in sorted order at `make install`, mode 0444 |
| `/System/Library/OpenSSL/certs/ca-certificates.crt` | symlink to `../cert.pem`, the bundle name Debian and Alpine software hardcodes |
| `/private/etc/ssl/certs` | symlink to `../../../System/Library/OpenSSL/certs` |
| `/private/etc/ssl/cert.pem` | symlink to `../../../System/Library/OpenSSL/cert.pem` |
| `/usr/share/doc/ca-certificates/SOURCE` | provenance and the MPL notice, following pico's licence-doc precedent |

`/System/Library/OpenSSL` is the primary location: it is the in-tree
OpenSSL's `--openssldir`, so its compiled-in `certs/` and `cert.pem` defaults
resolve to these files. `/etc/ssl` is a real directory holding two symlinks,
not a single link, so other packages can still add to it (for example an
`openssl.cnf`). The Makefile links the two `/etc/ssl` entries to absolute
targets; rbuild's `builder_relativize_symlinks` rewrites any absolute link
whose target exists in the package into a relative one, so the apk carries the
relative forms above. They resolve to the same files.

The bundle is generated so there is one source of truth. Ordering is by file
name, so it is reproducible.

OpenSSL's own `Makefile.ssl` also creates `certs/` under the same directory,
so the two apks share that directory.

## refresh.py

Run on the host by a maintainer. It takes a URL (default curl.se's
`cacert.pem`) or a local file, and needs `openssl` on `PATH`.

1. Fetch `cacert.pem` and its `.sha256`; refuse to continue if they differ.
2. Split it into `certs/`, naming each file from the CA label.
3. Validate before writing anything:
   - every PEM parses with the host `openssl x509`;
   - **subject DNs are unique.** In 0.9.5a `X509_STORE_add_cert` returns an
     error when a cert's subject equals one already in the store
     (`x509_object_cmp` compares subject names only), and
     `X509_load_cert_file` treats that as fatal, so a bundle with two certs of
     one subject silently stops loading partway;
   - file names are unique ignoring case, because the repo is checked out on
     Windows;
   - the cert count equals the number of `BEGIN CERTIFICATE` lines upstream.
4. Replace `certs/`, rewrite `SOURCE`, and print the new `pkgver`.

A failed validation leaves the tree unchanged.

## Makefile

A `Common.make` wrapper like `pico-1`, which supplies `installhdrs`,
`installsrc` and `clean`. Only `install::` is written: it makes the
directories, installs each PEM with `install -c` (the guest's `install` moves
its source without `-c`), builds `cert.pem` with `cat`, sets it to mode 0444,
and makes the three symlinks. It runs under the build box's GNU Make 3.74, so
it uses no target-specific variables. The package is universal like
`keymaps-1` and `sounds-1`, the other data-only packages; rbuild's compiler
probes still run for it.

## Verification

Run on an i386 build guest under a private `/build/<name>` root, with
`rbuild buildpackage --toolchain <gcc-darwin-i386.conf>` (the guest needs it):

1. `rbuild buildpackage` produces the apk. Inspect its file list, symlink
   targets and modes against the table above.
2. No file in the ca-certificates apk is also in the openssl apk. Directories
   such as `certs/` are shared, which apk allows according to apk-tools'
   source (database.c reports a conflict only for a file owned by another
   package); a shared file would be the real conflict. Checked by comparing the
   two apks' member lists, or, where no openssl apk exists, by reading the
   OpenSSL project's install rules.
3. The in-tree 0.9.5a `openssl` reads all N certs from `cert.pem`
   (`crl2pkcs7 -nocrl -certfile` piped to `pkcs7 -print_certs`, counting
   subjects) and N equals the cert count in `SOURCE`. Item 3 could only be run
   with the guest's 0.9.8 openssl; the 0.9.5a run is still open (see "Verified
   during implementation", "Still open").
4. The same bundle resolves through `/etc/ssl/cert.pem`,
   `/etc/ssl/certs/ca-certificates.crt` and `/etc/ssl/certs/<Name>.pem`,
   checked by following the links inside the extracted package root.

On the host, `refresh.py` is exercised against the real download and against
crafted bad input: a duplicate subject, a duplicate name differing only in
case, a truncated PEM, and a wrong checksum. Each must fail and leave `certs/`
untouched.

## Verified during implementation

From the host-side import (Task 2):

- curl.se publishes `cacert.pem.sha256` as `<64 hex>  cacert.pem`. The header's
  fourth line is `## Certificate data from Mozilla as of: Thu Aug 13 03:12:01
  2026 GMT`, and each certificate is a label, an `=====` underline and a PEM
  block with LF endings, as `refresh.py` parses. The real bundle has 121
  certificates, no duplicate subjects and no file-name collisions. One label
  (NetLock's "Arany (Class Gold)" root) has accented letters, so its file name
  is transliterated to `NetLock_Arany_Class_Gold_Fotanusitvany.pem`.

On a private QEMU i386 guest booted from `rhap-i386-bootstrapped.img` with
`-snapshot`, 2026-09-25:

- The guest's `install` moves its source without `-c` and keeps it with `-c`;
  `ln -fs` makes the expected links.
- rbuild passed the all-digit `pkgver` through: the apk is
  `ca-certificates-20260813-1-universal.apk` and `.PKGINFO` says
  `pkgver = 20260813-1`. Both i386 and ppc compiler and linker probes passed.
- The check script asserted the apk's contents: `certs/` holds the 121 PEMs,
  all mode 0444; `cert.pem` is a regular 0444 file equal to the sorted
  concatenation of `certs/*.pem`; following the links inside the extracted root
  reaches the 121 PEMs and the bundle through `/etc/ssl`. The script prints
  PACKAGE_TEST_OK only after every assertion passes. The `SOURCE` file was
  installed with mode 0444 by the Makefile's `INSTALL_FILE` line (seen in the
  build log), but its mode was not separately asserted.
- The guest's `openssl` (0.9.8, built for sshd) reads all 121 certificates from
  `cert.pem` and `openssl verify -CAfile cert.pem` accepts a root against it.
- OpenSSL 0.9.5a's install rules (`src/OpenSSL/openssl/Makefile.ssl` lines
  344-347 and `src/OpenSSL/openssl/apps/Makefile.ssl` lines 98-105) make the
  directories `misc`, `certs`, `private` and `lib` under the openssldir and
  install only the `misc/*` scripts and `openssl.cnf` there, and no `cert.pem`
  or `certs/*.pem`, so the two packages share the `certs/` directory and no
  file.

Still open:

- The load check with the in-tree OpenSSL 0.9.5a. The guest's `/usr/local/ssl`
  openssl is 0.9.8, and `/build/repo` has no openssl apk. The unique-subject
  rule rests on reading the 0.9.5a source, not on running it.
- `apk add` was never run on this package (no `apk` binary on the guest), so
  the shared-directory behaviour rests on reading apk-tools' source.
- Whether the in-tree apk-tools accepts a version of the form `20260813-1` in
  `apk add`, the same shape as every other package's version. The guest had no
  `apk` binary, so only rbuild's packaging was exercised.
