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
| Copy helper static implementation | pass; body review confirms element widths, row pitches and min-span behavior | pass; i386 stack args and loop bodies confirm shared contract |
| Copy helper test execution | blocked by missing compatible guest/toolchain | blocked by missing compatible guest/toolchain |
| NSDirectBitmap metadata accessors | PPC and i386 bodies agree; source and default-state tests authored; runtime pending | shared implementation; runtime pending |
| Mach IPC layouts and RPC contracts | screen/cursor request/reply bodies statically matched; test transport authored, execution pending | IDs and async cursor request independently confirmed; shared native descriptors/test harness, execution pending |
| IPC ABI and transport test execution | blocked by missing compatible guest/toolchain | blocked by missing compatible guest/toolchain |
| Intercepted rectangle core | PPC static review and source authored; test command parses, execution pending | shared source intended for both; build/runtime comparison pending |
| Client/rectangle notification dispatch | PPC static review and source authored; test command parses, execution pending | shared source intended for both; build/runtime comparison pending |
| NSShape scanline, operation, and description review | PPC static implementation; source authored; runtime pending | shared format/source intended for both; runtime pending |
| Shape behavior test execution | blocked by missing compatible guest/toolchain | blocked by missing compatible guest/toolchain |
| Framebuffer setup, map/unmap, remap, metadata, conversion tables, accessors, cache ownership, lock stubs, and bounds | PPC static review and source authored; runtime pending | DR2 i386 confirms shared contracts and the zero-origin bounds difference; runtime pending |
| Framebuffer and IPC test targets | authored; dry-run parses | authored; dry-run parses |
| Framebuffer test execution | blocked: host has no Objective-C compiler, Rhapsody SDK, or configured guest | blocked: host has no Objective-C compiler, Rhapsody SDK, or configured guest |

A reference-only analysis is an evidence-generation result when its summary says `complete: true` and contains the IDA record. The command exits 1 because comparison acceptance is not met without a rebuilt artifact; this is not a parity result.

The Objective-C metadata helper yields 151 names for 234 primary method symbols. Resolve that gap before using the helper as a complete owner map. The profile binary has 541 symbols and 151 names from the same helper; neither binary contains STABS. Several framework source units are reconstructed, but a rebuilt framework has not been compiled.
