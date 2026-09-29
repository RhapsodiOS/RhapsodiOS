# Interceptor validation record

| Check | PowerPC | i386 |
|---|---|---|
| Profile identity | Primary 145364-byte binary and hash validated | DR2 140216-byte extracted slice and hash validated |
| Dylib reader/schema | 540 symbols, 57332 text bytes | 629 symbols in the thin DR2 image |
| IDA 9.4 reference export | 392 functions | 419 functions |
| Other reference exports | i386 adapters are unsupported for PowerPC | Ghidra 416 and angr 1085 functions; see `build-environment.md` |
| Reference-only analyze | complete; CLI exit 1 because no rebuilt binary exists for normalized-functions acceptance | complete; CLI exit 1 because no rebuilt binary exists for normalized-functions acceptance |
| Public header hashes | pass | pass (all nine copied headers match the primary bundle) |
| ABI harness source | authored; not compiled or run without the historical toolchain | authored; not compiled or run without the historical toolchain |
| ABI, source, and runtime execution | blocked by missing compatible guest/toolchain | blocked by missing compatible guest/toolchain |
| NSSimpleBitmap static body review | pass; implementation tracks recovered fields/getters | pass against the DR2 i386 body; offsets were independently checked |
| Bitmap behavior test execution | blocked by missing compatible guest/toolchain | blocked by missing compatible guest/toolchain |
| NSShape scanline and operation review | static implementation; description remains incomplete | static cross-check supports shared format; runtime pending |
| Shape behavior test execution | blocked by missing compatible guest/toolchain | blocked by missing compatible guest/toolchain |

A reference-only analysis is an evidence-generation result when its summary says `complete: true` and contains the IDA record. The command exits 1 because comparison acceptance is not met without a rebuilt artifact; this is not a parity result.

The Objective-C metadata helper yields 151 names for 234 primary method symbols. Resolve that gap before using the helper as a complete owner map. The profile binary has 541 symbols and 151 names from the same helper; neither binary contains STABS. No framework source has yet been reconstructed or compiled.
