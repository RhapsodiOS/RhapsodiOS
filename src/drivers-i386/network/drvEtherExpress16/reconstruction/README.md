# EtherExpress16 reconstruction

The i386 `drvEtherExpress16` source reconstruction uses the reference
`EtherExpress16.config/EtherExpress16_reloc` binary (52,800
bytes, SHA-256
`2BF1F8563BABD7CDC4C7BA625E9963033A6B56BFE237A43308707944228AACE8`). The
IDA 9.4 function partition contains 68 functions: 39 Objective-C methods and
29 C helpers. `source-map.json` maps every function to the implementation, and
`verify_evidence.py` checks the partition and pinned reference identity.

The reconstruction restores the `IOEthernet` superclass and the 492-byte
instance layout, including the 56-byte reset jump buffer. It recovers the
adapter control-port handshake, EEPROM access, shared-memory allocation,
82586 SCB/CBL setup, transmit queue handling, receive descriptor rings,
interrupt recovery, and multicast setup from IDA. Helper port transfers and
descriptor indexes follow the reference's word and byte widths. The IDA and
angr function partitions differ; the source map records the IDA partition as
the reviewed reference boundary rather than claiming analyzer agreement.

## Verification

Run the reconstruction checks from the repository root:

```powershell
.\.venv-binrecon\Scripts\python.exe -m pytest src/drivers-i386/network/drvEtherExpress16/reconstruction/tests -q
$env:PYTHONPATH = "tools/binrecon"
.\.venv-binrecon\Scripts\python.exe -m binrecon validate --profile tools/binrecon/profiles/etherexpress16.json
.\.venv-binrecon\Scripts\python.exe src/drivers-i386/network/drvEtherExpress16/reconstruction/verify_evidence.py --analysis tools/binrecon/out/etherexpress16/published/analysis-reference-ida.json --source-map src/drivers-i386/network/drvEtherExpress16/reconstruction/source-map.json --repo-root .
```

The source passed a local Clang Objective-C syntax check using the test support
headers and a small DriverKit compatibility prelude. The legacy i386 DriverKit
build environment was unavailable, so no rebuilt relocatable was produced and
`verify_binary.py` could not yet compare rebuilt Objective-C metadata or method
inventory against the reference. Hardware behavior has not been exercised.

Binrecon analysis artifacts are kept under `tools/binrecon/out/etherexpress16`
and are not committed. To regenerate them, set `BINRECON_REFERENCE` to the
reference binary path and run:

```powershell
$env:PYTHONPATH = "tools/binrecon"
$env:BINRECON_REFERENCE = "C:\path\to\EtherExpress16_reloc"
.\.venv-binrecon\Scripts\python.exe -m binrecon analyze --profile tools/binrecon/profiles/etherexpress16.json
```
