# Terminal reference identity

Primary bundle: `C:\Users\raynorpat\Downloads\test\Applications_ppc\Administration\Terminal.app`.

| Artifact | Size | SHA-256 | Observed format |
| --- | ---: | --- | --- |
| `Terminal` | 333472 bytes | `B83EDEF820DF31A406FBFBBFB86DD5B80DB6818BD6D8BD14211680F2BD8E57D7` | 32-bit big-endian PowerPC `MH_EXECUTE` |
| `Headers/TerminalDOProtocol.h` | 66 bytes | `A3E26A281F7DE4B40D6E3CDD3DB8176A0E57E246CC242807641836E9C173880C` | Import stub for absent original source path |
| `Developer/Headers/Apps/TerminalDOProtocol.h` | 1921 bytes | `379478A579B89C27DC4066C81F348094468446A3048BA1E02AA59D9F2BD4F793` | Supporting protocol declaration |

The executable contains 191288 bytes in `__TEXT,__text`, 972 symbol-table
entries, and 441 distinct Objective-C method addresses in the current binrecon
method index. The method-address count is a preliminary observation only; the
coverage denominator is established by complete executable code ownership and
alias/boundary reconciliation.

The Mach-O declares these dependencies:

- `/System/Library/Frameworks/AppKit.framework/Versions/C/AppKit`
- `/System/Library/Frameworks/Foundation.framework/Versions/C/Foundation`
- `/System/Library/Frameworks/System.framework/Versions/B/System`

No separate i386 Terminal binary has been identified in the supplied
`C:\Users\raynorpat\Downloads\test` tree. See `build-environment.md` for the
search scope and current architecture limitations.

The Terminal executable's `LC_LOAD_DYLIB` record for AppKit is current version
1.124.6 with timestamp `0x383b3ba7`. The supplied top-level AppKit binary's
`LC_ID_DYLIB` is version 1.124.3 with timestamp `0x36ceb55f`; the DR2 universal
AppKit PPC slice is version 1.69.0 with timestamp `0x3550d100`. Neither is an
identity match for Terminal's recorded AppKit dependency, so neither should be
used to decide whether Terminal's prebound external selector pointers match
their source-level sends.

Reference binaries and generated analyzer outputs remain outside the source
tree and version control.
