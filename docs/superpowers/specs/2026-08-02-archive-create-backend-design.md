# Configured Archive-Create Backend Design

## Problem

Jaguar GNU tar 1.13 emits GNU `@LongLink` records for paths longer than 100 bytes even when invoked with `--posix`. Those type `L` records are not ustar and are correctly rejected by rbuild's strict archive validator. Jaguar has no GNU tar `--format=ustar` support, while `/bin/pax -w -x ustar` emits standard ustar prefix fields.

The existing toolchain schema overloads `tar` for both archive extraction and APK creation. Creation also hard-codes tar-specific `-C ... -cf -` arguments, so a standards-compliant non-tar creator cannot be selected cleanly.

## Architecture

Keep `tar` as the configured extraction and listing executable. Replace the tar-specific creation field with two required generic fields:

- `archive_create`: absolute executable used only to produce the uncompressed APK archive stream.
- `archive_create_flags`: whitespace-separated creator arguments expanded with the existing toolchain word expansion helper.

The Darwin/Jaguar profile selects:

```text
archive_create=/bin/pax
archive_create_flags=-w -x ustar
```

For a configured build, `pkginfo_build_apk` starts the archive child in the package root and invokes:

```text
/bin/pax -w -x ustar .
```

Its stdout remains connected to the existing configured gzip process. `tar` is not considered as a configured creation fallback. A missing executable or empty flags fails before opening an accepted APK output.

When `pkginfo_build_apk` is called without a toolchain, preserve the existing compatibility behavior: `tar -C ROOT -cf - . | gzip -9`. This fallback supports existing unit and library callers but is never reachable from a validated configured build.

## Components

### Toolchain schema

`Toolchain` owns and frees `archive_create` and `archive_create_flags`. The generic field table parses both keys, rejects duplicates and unknown legacy `tar_create_flags`, and requires nonempty values during validation. Existing profile fingerprinting covers the new fields because it hashes the complete profile file.

### APK creation

Configured creation expands `archive_create_flags`, builds `[archive_create, flags..., "."]`, and passes the package root as the archive child's working directory. The child treats `chdir` failure as exit 127. The gzip child and pipe/error cleanup behavior remain unchanged.

Legacy creation keeps its current tar argv and does not change directory in the child.

### PowerShell bootstrap contract

The canonical key list requires both new fields. Preflight reads `archive_create`, verifies it is an absolute executable using the existing executable loop, and validates the complete profile before any build output is accepted. Tests prove missing, duplicate, unknown-old-key, and unsafe/nonexecutable creator profiles fail.

## Verification

Tests cover:

- Toolchain load, validation, ownership/free behavior, missing creator, and missing/blank creator flags.
- Configured pkginfo argv and child working directory independently of tar syntax.
- Unconfigured legacy tar argv remains unchanged.
- A real package containing a path longer than 100 bytes is created by pax, decompressed, and scanned record-by-record. Every nonzero tar header must use a typeflag from `0` through `5`; no GNU `L` record or `@LongLink` name may appear. The resulting APK must also pass strict validation and extraction.
- PowerShell profile parsing and preflight include the new required executable.

No live installation, copying, sysroot fallback, remote bootstrap, or archive-validator relaxation is part of this change.
