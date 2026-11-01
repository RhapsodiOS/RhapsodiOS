# drvDECchip21140 reconstruction

This driver source is reconstructed against Apple's i386
`DECchip21140NetworkDriver_reloc` reference (SHA-256
`9F5FF95CB96A049288D33E537C97FAA75279F0A5EDBCD319950B7FFD391C789A`, 54,728
bytes). IDA recovered 49 functions: 46 hand-written Objective-C methods, the
`IOUpdateDescriptorFromNetBuf` C helper, and two Kernel Server generated
accessors. The generated accessors are emitted by the Kernel Server project.
The class declaration follows the recovered instance layout from `ioBase` at
`0x174` through `subVendorDeviceID` at `0x354`.

The driver bundle includes all 13 adapter tables, all 13 localized string
files, and the reference DriverHelp resources. The project manifests compile
all three source files and list the complete resource set. The private source
restores the descriptor rings, receive/transmit and interrupt paths, serial
ROM address handling, setup-frame filtering, and vendor-specific CSR12
initialization.

Run source and bundle checks from the repository root on Windows:

```powershell
$env:PYTHONPATH = 'tools/binrecon'
$env:BINRECON_REFERENCE = 'C:/path/to/DECchip21140NetworkDriver.config/DECchip21140NetworkDriver_reloc'
.\.venv-binrecon\Scripts\python.exe -m unittest src.drivers-i386.network.drvDECchip21140.reconstruction.test_reference -v
```

The five checks compare source selectors, project resource manifests, source
imports, Kernel Server compilation units, and byte-for-byte bundle resources
against the reference. `tools/binrecon/profiles/decchip21140.json` runs IDA and
angr against the reference. The current BinRecon run completed both reference
analyses but had no rebuilt binary for function comparison, so it does not
establish binary parity.

The source checks pass. An i386 APK build remains unverified: syncing to the
configured build guest failed because `127.0.0.1:2222` refused the SSH
connection. The driver has not been tested on physical DEC 21140 hardware.
