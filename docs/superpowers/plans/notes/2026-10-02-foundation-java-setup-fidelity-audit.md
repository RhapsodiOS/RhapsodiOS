# Foundation NSJavaSetup IDA fidelity audit

Reference: the DR2 i386 Foundation IDA database `6c2a913dc37a`.

The current `NSJavaSetup.m` already reconstructs most of the implementation.
I compared its main setup and loader paths against the corresponding IDA
pseudocode: `NSJavaDefinitiveSetupDictionary`, `_NSJavaAbsolutePath`,
`NSJavaBundleSetup`, `NSJavaClassLoaderForPath`,
`NSJavaSpecifiedClassesForBundle`, `NSJavaResourceLocatorForPath`, vector to
array conversion, class-loader enumeration, convenience entry points, and
`NSJavaBundleCleanup`.

The reviewed branches agree on these behaviors:

- Defaults are applied only when the default value has the expected class;
  array defaults are prepended to valid property-list arrays.
- Relative Java roots are resolved against the bundle path, the recorded
  bundle path, or `.`; relative entries are then joined to that root.
- Bundle setup appends the VM's default class path and user paths, creates the
  VM, loads the other bundles, registers native library search paths, and
  loads requested classes.
- The class-loader path reuses the shared loader only when requested, appends
  later paths to its resource locator, and converts returned Java vectors to
  Foundation arrays.
- Cleanup removes each derived library search path through the runtime class.

At the time of this audit, the only `NSJavaSetup.m` TODOs were
`NSJavaSetupVirtualMachine` and `NSJavaObjectNamedInPath`. Neither name appears
in the complete NSJava function inventory of the DR2 i386 Foundation target,
so this binary does not establish their implementations. A repository-wide
source search also found no alternate definitions. Their implementation status
has since changed for the PowerPC-only `NSJavaObjectNamedInPath` wrapper; see
the PPC follow-up below. `NSJavaSetupVirtualMachine` remains unimplemented.

This was a source-to-pseudocode review only. No code edits, tests, or builds
were made for NSJavaSetup in this pass.

## Project ABI cross-check

The extracted i386 project ABI record at
`src/Kits/Foundation/reconstruction/abi/NSJavaSetup.json` confirms the same
boundary for this target: its `text_symbols` lists the implemented setup and
loader functions, but not `NSJavaSetupVirtualMachine` or
`NSJavaObjectNamedInPath`. The PPC export is intentionally absent from this
i386 ABI record.

## Secondary JavaVM.framework reference

Located and opened the matching DR2 binary at
`C:\Users\raynorpat\Downloads\test\DR2\Frameworks\JavaVM.framework\Versions\A\JavaVM`
in IDA instance `f9610f8dff81`. Its `+[NSJavaVirtualMachine
defaultVirtualMachine]` body (`0x5cd00fc0`) returns the first existing VM;
otherwise it creates and initializes the default configuration, asks
`NSJavaVirtualMachine` to initialize, and then returns the first registered VM
or nil. Its `-[NSJavaVirtualMachine initWithClassPath:]` body (`0x5cd01168`)
rejects a second VM, resolves and loads the ObjCJava bridge, registers the VM,
looks up `NSLoadVirtualMachine`, and calls it with the class path. The binary's
diagnostic strings confirm the bridge-load and symbol-lookup failure paths.
The same binary's `-[NSJavaVirtualMachine findClass:]` (`0x5cd01278`) maps to
`NSClassFromString`, while `defineClass:withName:` (`0x5cd01288`) resolves
`NSAddClassFile` in the bridge and calls it with the VM data, class name, and
class bytes.

This establishes the runtime side of VM creation, but it does not reveal the
two missing Foundation C wrappers in the DR2 i386 target: neither appears in
that target's function/symbol index, and the DR2 AppKit binary has no references
to them. The PPC Foundation target separately supplies the
`NSJavaObjectNamedInPath` wrapper described below. `NSJavaSetupVirtualMachine`
remains unavailable in the inspected Foundation targets.

## Version boundary from Apple API reference

Apple's archived Foundation Functions Reference lists both
`NSJavaSetupVirtualMachine` and `NSJavaObjectNamedInPath` as available in
Mac OS X 10.2 and later, and deprecated in 10.5. The reference binary used
for this audit is the earlier DR2 Foundation target. This version boundary is
consistent with the wrappers' absence from the target's function inventory and
supports treating them as post-target APIs rather than missing DR2
implementations. The documentation confirms their contracts but does not
supply implementation bodies: `NSJavaSetupVirtualMachine` sets up and returns
the VM, while `NSJavaObjectNamedInPath` creates a named object through a class
loader already set up for that path.

Reference: [Apple archived Foundation Functions Reference](https://leopard-adc.pepas.com/documentation/Cocoa/Reference/Foundation/Miscellaneous/Foundation_Functions/Reference/reference.html), sections `NSJavaSetupVirtualMachine` and `NSJavaObjectNamedInPath`.

## PPC wrapper follow-up (2026-10-05)

The MOSXS PowerPC Foundation database exports `_NSJavaObjectNamedInPath` at
`0x4257C89C`. IDA confirms its body obtains
`NSJavaClassLoaderForPath(path, YES)`, resolves
`NSJavaPathResourceLocatorClassName`, and sends `instantiate::` to that class
with the loader followed by the requested name. `NSJavaSetup.m` now follows
that call sequence, and the declaration and definition are guarded for PPC.
The DR2 i386 database has no `_NSJavaObjectNamedInPath` function, so the i386
ABI and shared symbol inventory remain unchanged. The Java VM category
declarations in the source identify the two-argument `instantiate::` selector.

### PPC wrapper source parity recheck (2026-10-05)

Rechecked the current guarded body against IDA pseudocode and disassembly at
`0x4257c89c`. The source preserves the binary argument order
`NSJavaClassLoaderForPath(path, YES)`, class lookup using
`com.apple.util.PathResourceLocator`, and `instantiate: :name` message with
loader before name. The current header and implementation both use the PPC
guard, and the i386 ABI manifest still does not claim this post-DR2 symbol. No
source or ABI changes were needed; no tests or builds were run.

### PPC virtual-machine setup wrapper (2026-10-05)

The MOSXS PPC Foundation database exports `_NSJavaSetupVirtualMachine` at
`0x4257cae0`. IDA confirms that it copies `[NSBundle mainBundle]`'s info
dictionary, sets `NSJavaRoot` to `/`, calls `NSJavaSetup` with the mutable
copy, releases the copy, and returns the setup result. The source now matches
that sequence and guards both declaration and definition for PPC. The DR2
i386 target has no matching function; `abi-ppc/NSJavaSetup.json` records the
PPC-only export while the i386 ABI manifest and shared symbol inventory remain
unchanged. No tests or builds were run.
