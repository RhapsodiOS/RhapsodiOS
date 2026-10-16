# Foundation PPC Selector Coverage Audit (2026-10-07)

Ran `tools/binrecon/selector_check.py` against the MOSXS PPC Foundation image
and `src/Kits/Foundation`. The checker reports 3,397 reference selectors and
3,404 source definitions, with no missing selectors, renames, or duplicates.
All seven source-only entries correspond to documented architecture or
category-placement differences:

- `+[NSConcretePortCoder debugDescription]` is a PPC-only selector.
- `+[NSPathStore2 pathStoreWithCString:]` and
  `+[NSTask taskWithPath:arguments:]` are i386-only selectors.
- `-[NSCoder(NSTypedstreamCompatibility) encodeNXObject:]` and
  `-[NSCoder(NSTypedstreamCompatibility) decodeNXObject]` are the i386
  category placements; PPC places the methods on `NSCoder` itself.
- `-[NSObject(NSDebuggerExtras) printForDebugger:]` and
  `-[NSProxy(NSDebuggerExtras) printForDebugger:]` are i386-only selectors.

The corresponding architecture and category differences are recorded in
`src/Kits/Foundation/reconstruction/divergences.md`. This audit establishes
selector-name coverage only; it does not compare method bodies, encodings,
ownership, or compiled layouts. No tests or builds were run.

The same checker was run against the DR2 i386 Foundation image. It reports
3,253 reference selectors, the same 3,404 source definitions, and no missing
selectors, renames, or duplicates. Its 151 source-only entries are not a
compiled i386 inventory: `selector_check.py` does not preprocess
architecture guards, so PPC-only implementations are still counted. The
i386 result establishes selector-name coverage only; it does not prove which
conditional implementations enter an i386 build or compare encodings and
layouts. No tests or builds were run.
