# Foundation PPC Fast Java Bundle Setup Design

## Goal

Reconstruct the MOSXS PPC Foundation fast Java bundle setup export and its
flag-controlled entry path in `NSJavaBundleSetup`, using only behavior
confirmed by the live PPC IDA database. Keep the existing non-fast setup path
and the DR2 i386 behavior intact.

## Target evidence

The MOSXS PPC Foundation image contains `__NSFastJavaBundleSetup` at
`0x4257dd78..0x4257e414`, `NSJavaBundleSetup` at `0x4257bb14`, and the private
`__NSJavaPathCompsForBundle` helper at `0x4257ea94..0x4257eb48`. The setup
entry checks `_usesFastJavaBundleSetup > 0`; when true it calls the fast helper
with the incoming bundle and settings dictionary. Otherwise it continues
through the existing setup path.

The helper normalizes settings with `NSJavaDefinitiveSetupDictionary`, builds
the Java class path from configured bundle paths, the VM default class path,
user paths, and ordered paths obtained from Java-providing frameworks and
bundles. It posts the setup and VM-creation notifications, creates the VM,
registers native library paths, creates the system class loader, marks Java
bundles loaded, loads requested classes, and posts setup completion. The path
helper defaults a missing settings dictionary from the bundle info dictionary,
then returns either absolute `NSJavaPath` components or type-checked
`NSJavaUserPath` components according to its selector argument.

Source already defines `_usesFastJavaBundleSetup`, both `NSBundle` flag
accessors, and `-[NSBundle _setJavaClassesLoaded]`. The current PPC ABI overlay
does not list the fast setup text export, and the shared symbol and ownership
maps do not assign it. A PPC symbol audit reports this as the only remaining
unclaimed exported function. The i386 image has no corresponding export.

The two selector references that Hex-Rays leaves unnamed are resolved by their
call roles and the matching ordinary setup path. At `0x4257e320`, the fast
body sends a zero-argument message to each Java-providing bundle immediately
after `_setJavaClassesLoaded`; the ordinary path sends the same selector at
`0x4257c0b0`. This is `-[NSBundle load]`, also present as the `load` selector
string and implementation `-[NSBundle load]` at `0x4258bc6c`. At
`0x4257e3bc`, the fast body sends each configured class name to the VM; the
ordinary path performs the same VM call at `0x4257c14c`. The current
`NSJavaSetup.m` expresses it as `[javaVM loadClass:className]`, and the
Foundation binary contains the `loadClass:` selector string. These are
respectively a zero-arg bundle message and a one-object-argument VM message.
The existing `NSJavaSetupVirtualMachine` wrapper is outside this slice.

## Design

Add a PPC-guarded private path-components helper and a PPC-guarded fast setup
function in `NSJavaSetup.m`. Implement the helper's dictionary fallback,
normalization, selector-controlled path choice, and result ownership to match
the IDA body. Implement the fast setup in the target's observed operation
order, reusing existing Foundation setup, path, bundle, notification, and
class-loader APIs where they match the decompiled calls. Preserve notification
ordering, the VM creation result path, library search-path registration,
bundle-loaded marking, requested class loading, and final setup notification.

Add the flag check at the start of `NSJavaBundleSetup` only for PPC. It must
return the fast helper's result directly when the flag is positive, and fall
through to the current source implementation otherwise. Leave i386 routing and
all existing non-fast behavior unchanged.

## Scope and metadata

- Modify `NSJavaSetup.m` for the PPC-only helper, fast setup implementation,
  and flag-controlled route.
- Add `__NSFastJavaBundleSetup` to
  `reconstruction/abi-ppc/NSJavaSetup.json` and `reconstruction/symbols.json`;
  add the source identifier `_NSFastJavaBundleSetup` to
  `reconstruction/ownership.json`, owned by `NSJavaSetup.m`.
- Do not add the export to the i386 ABI manifest or change
  `NSJavaSetupVirtualMachine`.
- Keep all behavior within the confirmed PPC call graph. Do not add guessed
  Java runtime APIs or broaden the existing non-fast path.

## Verification

Compare the helper, fast setup body, and dispatch branch against the three PPC
IDA functions, including notification order, selector signatures, and return
paths. Check PPC ABI and shared symbol/ownership records, confirm the export is
no longer unclaimed, and run `git diff --check`. Do not run tests or builds.
