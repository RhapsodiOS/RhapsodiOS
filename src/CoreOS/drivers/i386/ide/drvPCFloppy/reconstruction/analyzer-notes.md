# Why binrecon runs IDA only on this driver

Both other analyzers fail, for unrelated reasons. Neither failure is a defect in
the driver, and both were diagnosable only after binrecon's normalizer was taught
to name the artifact, analyzer and instruction in its errors.

**angr mis-decodes our binary.** At `0x27` it reports a one-byte
`lodsd eax, dword ptr [esi]`, but relocation 0 covers `0x27..0x2b` — four bytes,
`i386-vanilla-32-pc-relative`. angr began decoding inside a `call`/`jmp rel32`
that starts at `0x26`, so the relocation no longer lies within the instruction it
belongs to and normalization refuses it.

**Ghidra cannot attribute relocations to operands.** At `0x3ab8` in the
*reference*, `CMP dword ptr [0x00000000], EDI` carries a relocation targeting
`_page_size`. Ghidra leaves the operand unrelocated and prints no symbol, so
binrecon's textual owner-matching finds zero candidates among
`['dword ptr [0x00000000]', 'EDI']` and reports the ownership as ambiguous.

Fixing either adapter is out of scope. Re-enable them only with evidence that
the underlying behaviour has changed.
