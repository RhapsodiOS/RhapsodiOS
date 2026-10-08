# Intel 82595 reconstruction

The i386 `drvIntel82595-21` implementation is reconstructed from
`Intel82595NetworkDriver.config/Intel82595NetworkDriver_reloc` (64,816 bytes,
SHA-256 `B40292EBBF8CF29922C079487A31F530633B0FC3DC04BB25BF1B9E8887E44684`).
IDA 9.4 pseudocode and disassembly were reviewed for all 57 handwritten methods,
with an independent second review. The two remaining methods are the kernel
server instance and DriverKit 500 accessors emitted by `kernelserver.make`.
`source-map.json` and `ledger.json` account for all 59 reference functions,
including the probe at address zero.

## Recovered behavior

The reconstruction restores the actual IOEthernet inheritance and ivar layout,
probe ownership, zero-success IOReturn handling, banked port sequences, EEPROM
clocks/checksum, board-specific IRQ encodings, and the Intel PnP key. Receive and
transmit memory allocation, packet queues, multicast command construction,
interrupt acknowledgements, and debugger polling follow the reference.
The EM595 selects the first matching CIS tuple. The `i82595eeprom` buffer occupies
128 bytes at offset 12; its complete instance is 140 bytes. Intel82595 and its
adapter subclasses have 420-byte instances with driver ivars starting at 372.

Original behavior is deliberately retained, including full-word transfers for
odd byte counts, debugger transmit's minimum 64-byte buffer access, its unbounded
completion polling, and the Plus board's unconditional successful `busConfig`
return. This is a reconstruction, not a redesign of those contracts.

The project now uses the same aggregate / `.drvproj` / `.lksproj` hierarchy as
the other i386 drivers. `apk/pkginfo` declares the i386 architecture and native
build dependencies. The installed bundle contains the six recovered tables and
six English string resources. No help resource was present in the reference;
the driver-local `movehelp` override handles that case.

## Verification

`tests/verify.sh` runs native C and Objective-C tests using simulated ports and
DriverKit objects. The Objective-C test executable compiles the seven production
source files, with the real legacy Objective-C runtime. It covers probe lifetime,
interrupt enablement, both memory capacities, all IRQ maps, PnP key writes,
transmit queues/statistics, multicast setup, receive failures/filtering/wrap,
odd transfers, debugger timeouts, and first-match CIS selection.

`verify_binary.py` checks i386, the complete 59-method inventory, external
symbols, and all nine class layouts against the reference. It permits the
documented representation change from the opaque EEPROM union to its recovered
128-byte buffer; offsets and total instance size must still match.
`verify_evidence.py` checks the reference identity, reviewed function partition,
source locations, evidence hashes, and rebuilt identity.

Binrecon ran both IDA 9.4 and angr 9.3.0. The combined reference consensus is
disputed because their function partitions and relocation interpretations
differ; the ledger records this rather than claiming analyzer agreement.
The Objective-C metadata and reviewed IDA partition define the 59-method scope.
Strict exact-image, exact-section and normalized-function equivalence do not
pass. Reviewed control flow and ABI/inventory checks are the reconstruction's
acceptance criteria; no assembly-equivalence claim is made.

The rebuilt binary omits four unused C strings: `%s%02x`, `:`,
`Intel 82595A-2 stepping`, and `Intel 82595TX stepping`. IDA shows no code
references to the first two or to the table holding the stepping labels.
The EEPROM type encoding and generated version metadata also differ. The
multicast address copy uses the kernel's `bcopy` for six bytes in place of the
original inline copy, adding that one external symbol.

Native i386 compilation, linking and installation succeeded, and both test
executables passed. The verified rebuilt relocatable is 56,588 bytes, SHA-256
`7450620F254EFD2C59DC644F3BD50BE5A39AE8454809B513EBF3CA9D2563ACFC`.
Full APK generation remains unverified: `rbuild` stalled on filesystem I/O in
the isolated build guest, and the guest failed to recover after restart.
The final packaging-only version/server-key edits therefore still need a
successful end-to-end package build. The source is ready for that retry using
the supplied helper; no APK success is claimed.

Actual 82595 hardware operation remains untested. The guest supplies the native
compiler and packaging environment; its emulated NE2000 does not exercise an
82595 adapter.

## Reproduce

After syncing this driver and populating the build guest's package repository
with its dependencies, run from the host repository root:

```powershell
powershell -NoProfile -File vm/guest-remote.ps1 -Run vm/build-i386-intel82595.sh
```

The helper runs tests and `rbuild buildpackage --arch i386
--dir --target all`, placing APKs in `/build/out/drvIntel82595-rbuild`.

On the analysis host, set `PYTHONPATH=tools/binrecon` and
`BINRECON_REFERENCE` to the reference binary, then run from the repository root:

```text
python -m binrecon analyze --profile tools/binrecon/profiles/intel82595.json
python src/drivers-i386/network/drvIntel82595/reconstruction/verify_binary.py REFERENCE REBUILT
python src/drivers-i386/network/drvIntel82595/reconstruction/verify_evidence.py --analysis tools/binrecon/out/intel82595/published/analysis-reference-ida.json --source-map src/drivers-i386/network/drvIntel82595/reconstruction/source-map.json --ledger src/drivers-i386/network/drvIntel82595/reconstruction/ledger.json --repo-root . --final --rebuilt REBUILT
```

For the two-binary comparison, also set `BINRECON_REBUILT` and use
`tools/binrecon/profiles/intel82595-compare.json`. Its strict comparison is
expected to fail for the differences described above. Local analysis artifacts and
native build logs are under `tools/binrecon/out/intel82595/`; binary inputs and
build outputs are not committed. The ledger pins the reviewed evidence hashes.
