# Reference divergences

The reference-only baseline has no rebuilt image, so no binary parity result exists yet. Do not mark compiler lowering, relocations, source-map differences, or hardware behavior as matching until Tasks 2–9 produce a fresh i386 build and paired binrecon report.

IDA 9.4 is the only analyzer enabled in this baseline. The configured 9.2 directory contains a license file but no batch executable. Ghidra and angr remain disabled, so this report makes no multi-analyzer consensus claim.

IDA's type database labels several driver-private structures with content hashes and gives some class superclasses only opaque byte prefixes. Their observed sizes and offsets are recorded in `interfaces.md`; Task 2 must preserve those facts while resolving source names and inherited layouts from the DriverKit ABI.
