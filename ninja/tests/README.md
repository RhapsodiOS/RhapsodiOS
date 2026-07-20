# apk integration tests (Tasks 5, 9, 10, 11)

These scripts exercise the vendored apk-tools 2.0_pre11 CLI against disposable
`--root` trees. They are intended to run on Darwin/RhapsodiOS after `apk` is
built; writing and committing them on other hosts is fine.

## Setup

```sh
export APK=/path/to/built/apk
# Optional fallback used by scripts if APK unset:
#   $ROOT/src/apk-tools/apk
#   ${DSTROOT:-/tmp/rhapsody/dst}/sbin/apk
```

## Run

```sh
sh ninja/tests/apk-roundtrip.sh   # Task 5: file:// mkapk → index → add
sh ninja/tests/apk-deps.sh        # Task 9: A→B→C deps + unmet abort
sh ninja/tests/apk-http.sh        # Task 10: same repo over HTTP
sh ninja/tests/apk-conflict.sh    # Task 11: path conflict + tamper reject
```

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | Passed (`OK` printed) |
| 77 | Skipped — `apk` not found/executable (CI can treat as skip, not fail) |
| other | Failed |

## Notes

- Pre11 `apk index` writes the index to **stdout** (no `-o`); scripts gzip that
  stream to `APK_INDEX.gz` (the name `apk` opens for local and HTTP repos).
- Repo entries use `file://…` or `http://127.0.0.1:PORT/`.
- `apk add --initdb` creates the DB under `--root` on first install.
