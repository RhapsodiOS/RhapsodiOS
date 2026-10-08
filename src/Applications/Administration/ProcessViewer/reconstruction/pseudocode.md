# Decompiled reference evidence

IDA Professional 9.4 ran Hex-Rays against the verified PowerPC executable. Its
Python API successfully decompiled all 78 Objective-C method symbols and five
application C functions: 83 application functions total, with zero decompilation
failures. The address, name, size, owner, and available static callers are in
`function-worklist.md`; class, ivar, and raw method type encodings are in
`abi.md`.

The pseudocode and IDA database are generated analysis artifacts, not source.
They stay outside version control at:

```
tools/binrecon/out/processviewer-ppc/application-pseudocode.c
tools/binrecon/out/processviewer-ppc/ProcessViewer.i64
```

They were generated from the reference identified in `reference.md`, using the
ignored one-run script `tools/binrecon/out/processviewer-ppc/decompile_app.py`.
The script waits for IDA auto-analysis, checks
`ida_hexrays.init_hexrays_plugin()`, decompiles every symbol-named method and
these helpers: `_main`, `_floatFromNumberWithSuffix`, `_sortFunction`,
`__readTypesFromFile`, and `_NameForUID`. IDA writes each owned function to the
pseudocode file and records per-function exceptions; the run had zero.

Review pseudocode against the IDA-exported PowerPC instructions. It contains
unresolved Objective-C selector/data references and compiler-derived types, so
it is evidence for control flow, calls, and constants, not a drop-in source
translation. Record any contradicted observation before relying on it during
implementation.
