# ca-certificates package

## Goal

Ship Mozilla's trusted root CA certificates as an apk, installed in one
common place, so that OpenSSL and anything ported later find them without
configuration. The project is `src/ca-certificates-1`. rbuild packages it as
`ca-certificates-<pkgver>-universal.apk`, and it is listed in `src/Manifest`.

## Non-goals

- Making the certificates usable by the in-tree OpenSSL 0.9.5a for modern
  chains. That release predates SHA-256 and elliptic-curve signatures, so it
  loads these roots but cannot verify most current server chains. Fixing that
  is an OpenSSL upgrade, not this package.
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
Makefile        hand-written, like keymaps-1: all, installhdrs, install, installsrc, clean
apk/pkginfo     pkgname=ca-certificates, pkgver=<YYYYMMDD>, license=MPL-2.0,
                url=https://curl.se/docs/caextract.html, makedepends=build-base
certs/*.pem     one PEM per root; the CA label is kept as a comment above BEGIN
SOURCE          upstream file name, Mozilla date line, SHA-256 of the original
                cacert.pem, cert count, and the MPL notice from cacert.pem's header
refresh.py      host-side maintainer tool, never run in the guest
```

`pkgver` is the date in `cacert.pem`'s "Certificate data from Mozilla as of:"
line, as `YYYYMMDD`. rbuild copies the version into the apk name unchanged
(`package_canon_version`), and apk accepts an all-digit version.

`src/Manifest` gets `dir     ca-certificates-1     all`, placed before `cc-1`.
`BootstrapManifest` is untouched.

## What the apk installs

| Path | What it is |
|---|---|
| `/System/Library/OpenSSL/certs/<Name>.pem` | the per-CA PEMs, mode 0444 |
| `/System/Library/OpenSSL/cert.pem` | the bundle, `cat` of `certs/*.pem` in sorted order at `make install`, mode 0444 |
| `/System/Library/OpenSSL/certs/ca-certificates.crt` | symlink to `../cert.pem`, the bundle name Debian and Alpine software hardcodes |
| `/private/etc/ssl/certs` | symlink to `/System/Library/OpenSSL/certs` |
| `/private/etc/ssl/cert.pem` | symlink to `/System/Library/OpenSSL/cert.pem` |
| `/usr/share/doc/ca-certificates/SOURCE` | provenance and the MPL notice, following pico's licence-doc precedent |

`/System/Library/OpenSSL` is the primary location: it is the in-tree
OpenSSL's `--openssldir`, so its compiled-in `certs/` and `cert.pem` defaults
resolve to these files. `/etc/ssl` is a real directory holding two symlinks,
not a single link, so other packages can still add to it (for example an
`openssl.cnf`). The symlink targets are absolute.

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

Follows `keymaps-1`: no GNUSource, no framework makefiles beyond what it needs
for `DSTROOT`. It must run under the build box's GNU Make 3.74, so no
target-specific variables. `install` creates the directories, copies the PEMs
with `install -c -m 444`, builds `cert.pem` with `cat` and creates the three
symlinks. `installhdrs` and `clean` do nothing. `installsrc` copies the
project's files.

The package is universal like `keymaps-1` and `sounds-1`, the other data-only
packages. rbuild's compiler probes still run for it.

## Verification

Done on the build box under a private `/build/<name>` root:

1. `rbuild buildpackage` produces the apk. Inspect its file list, symlink
   targets and modes against the table above.
2. Install it into a scratch root together with the openssl apk. Both must
   install, with the shared `certs/` directory.
3. The in-tree 0.9.5a `openssl` reads all N certs from `cert.pem`
   (`crl2pkcs7 -nocrl -certfile` piped to `pkcs7 -print_certs`, counting
   subjects) and N equals the cert count in `SOURCE`.
4. The same bundle resolves through `/etc/ssl/cert.pem`,
   `/etc/ssl/certs/ca-certificates.crt` and `/etc/ssl/certs/<Name>.pem`.

On the host, `refresh.py` is exercised against the real download and against
crafted bad input: a duplicate subject, a duplicate name differing only in
case, a truncated PEM, and a wrong checksum. Each must fail and leave `certs/`
untouched.

## Unverified until implementation

- That curl publishes `cacert.pem.sha256` at the URL and the label format
  `refresh.py` will parse. Both are from memory.
- That apk-tools lets two packages own one directory, which the shared
  `certs/` relies on.
- That the in-tree apk-tools accepts an all-digit `pkgver` such as
  `20260924`. rbuild passes it through; the apk side is from memory of
  Alpine's usage.
- That the guest's `install` and `ln -s` behave as the Makefile assumes.
