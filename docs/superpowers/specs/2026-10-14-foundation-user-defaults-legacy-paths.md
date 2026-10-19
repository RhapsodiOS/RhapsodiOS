# Foundation Legacy Defaults Path Correction

## Goal

Match `NSUserDefaultsConvertOldDefaultsToNew` to the paired i386 and PPC IDA
path roots and lock-acquisition order while preserving its serialization and
domain-write behavior.

## Evidence

The Foundation store path passed to the converter is `_path`, initialized as
`NSOpenStepDirectoryForUser(username, YES)/Defaults` in `NSUserDefaults.m`.
Both IDA targets form the `NSGlobalDomain.defaults` sentinel path from that
store path. Source currently forms it from the store path's parent.

The remaining legacy-file roots differ by target:

- i386 (`0x4254becc`, 1301 bytes) derives the store path's parent, then appends
  `lock` and `data`. The IDA constant objects point to `lock` and `data`.
  Current source already uses these i386 roots.
- PPC (`0x425720f8`, 896 bytes) derives the store path's parent, appends the
  `UserDefaults` directory, then appends `lock` and `data`. IDA string objects
  confirm `UserDefaults`, `lock`, and `data`. Current source omits the
  intermediate `UserDefaults` directory.

Both targets look for per-domain legacy files as
`<store path>/<domain>.defaults`; current source already does this. Their
`__NSGrabLock_old` helpers are separately reconstructed as
`NSUserDefaultsGrabLegacyLock`; this design does not change that algorithm.
Both target converters acquire that lock before checking the global sentinel
and data file. Current source performs those checks before acquiring the lock.

## Proposed change

In `NSUserDefaultsConvertOldDefaultsToNew`:

1. Build `legacyGlobal` from `defaultsPath/NSGlobalDomain.defaults` on both
   targets.
2. Keep i386 `legacyDataPath` and `lockPath` at
   `<parent of defaultsPath>/data` and `/lock`.
3. On PPC only, derive a `UserDefaults` directory under the parent and build
   `legacyDataPath` and `lockPath` beneath it.
4. Acquire the legacy lock before checking the sentinel and data file. If
   either check skips conversion, unlock before returning, matching both IDA
   bodies.
5. Preserve data removal, deserialization, domain iteration, and per-domain
   write behavior.

The change is limited to the converter's path construction and lock/check
order, plus any source-map line anchors changed by that edit. Add an audit
entry with the paired addresses, architecture-specific roots, and lock order.

## Verification

Static review only, consistent with the approved reconstruction workflow: check
the path construction against both IDA bodies and confirm source-map JSON and
line anchors remain valid. Do not run tests or builds.

## Open detail

IDA shows the target's `NSGlobalDomain.defaults` existence check before it
tests for the data file; preserve that order when adjusting source paths.
