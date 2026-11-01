# Foundation NSUserDefaults Domain-List Copy Correction

## Goal

Match `NSUserDefaultsConvertOldDefaultsToNew2`'s mutable copy call to the
paired i386 and PPC Foundation implementations.

## Evidence

The helper is mapped at `NSUserDefaults.m:508`: i386 `_NSConvertOldDefaultsToNew2`
(`0x42566820`, 621 bytes) and PPC `_NSConvertOldDefaultsToNew2`
(`0x42572478`, 676 bytes). PPC IDA explicitly sends `mutableCopy` to the
directory listing. The current source sends `mutableCopyWithZone:` with a null
zone. i386 Hex-Rays renders the selector operand as an unnamed data reference
and shows no explicit argument; it then sends `removeObjectAtIndex:` to the
result. i386 disassembly confirms the directory-listing result is passed as
the receiver to a second `objc_msgSend`, with the previously pushed selector
still on the stack and no zone argument. Together, this supports the same
no-argument mutable copy call shape on i386, though its selector spelling is
not independently recovered from the decompilation.

The rest of both converter bodies agrees with the source: sentinel check,
PPC-only conversion log, reverse filtering of `.lock`, `.time`, `.defaults`,
and hidden names, reverse domain processing, per-domain lock acquisition,
readability check, copy, unlock, and release. PPC pseudocode shows the full
`copyPath:toPath:handler:` argument list; i386 disassembly confirms its two
paths and null handler are also passed. The proposed correction is limited to
the mutable-copy selector.

## Proposed change

Replace `mutableCopyWithZone:NULL` with `mutableCopy` in
`NSUserDefaultsConvertOldDefaultsToNew2`. Preserve the nil check, reverse
filtering, lock flow, and domain-copy behavior. Do not change the separate main
converter's path or call order.

## Verification

Compare the source call shape with both IDA bodies and validate the affected
source-map anchors and `git diff --check`. Do not run tests or builds.

## Scope boundary

This is a single selector-call correction. It does not resolve the separate
`NSUserDefaultsConvertOldDefaultsToNew` call-order differences recorded in
`reconstruction/divergences.md`.
