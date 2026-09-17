# Apple PnPDump nlist

Date: 2026-09-17

## Tool identity

| Field | Value |
| --- | --- |
| Path | `C:\Users\raynorpat\Downloads\test\Drivers\i386\EISABus.config\PnPDump` |
| SHA-256 | `006DC6BB73CEBC6243DA669E5199AEC808F309E72C3EE617A3FD8ED310364772` |
| Size | 59260 bytes |
| Mach-O | i386 (`cpu_type` 7), `MH_EXECUTE` (`file_type` 2) |

## ObjC classes (`.objc_class_name_*`)

| Class | Present | Shared compile candidate |
| --- | --- | --- |
| PnPDependentResources | yes | yes |
| PnPDeviceResources | yes | yes |
| PnPLogicalDevice | yes | yes |
| PnPResource | yes | yes |
| PnPResources | yes | yes |
| pnpDMA | yes | yes |
| pnpIOPort | yes | yes |
| pnpIRQ | yes | yes |
| pnpMemory | yes | yes |
| IODeviceMaster | yes | no (tool-local) |
| NXLock | yes | no (tool-local) |
| List | yes | no (runtime) |
| Object | yes | no (runtime) |
| Protocol | yes | no (runtime) |

All nine shared PnP resource classes are present. None of the kernel-only classes appear in the tool nlist (`EISAKernBus*`, `EISAResourceDriver`, `PnPBios`, `PnPArgStack`).

**Shared compile list (nine candidates):** PnPDependentResources, PnPDeviceResources, PnPLogicalDevice, PnPResource, PnPResources, pnpDMA, pnpIOPort, pnpIRQ, pnpMemory.

## Entry point and I/O symbols

| Symbol | Binding | Section | Address | Notes |
| --- | --- | --- | --- | --- |
| `_main` | external | `__TEXT,__text` | `0x3d78` | tool entry |
| `_IOMalloc` | external | `__TEXT,__text` | `0x6b94` | **local** definition |
| `_IOFree` | external | `__TEXT,__text` | `0x6ba4` | **local** definition |
| `_IOLog` | external | `__TEXT,__text` | `0x7070` | **local** definition |
| `_IOGetTimestamp` | external | `__TEXT,__text` | `0x6fd8` | **local** definition |
| `_IOScheduleFunc` | external | `__TEXT,__text` | `0x6c98` | **local** definition |
| `_IOUnscheduleFunc` | external | `__TEXT,__text` | `0x6f1c` | local |
| `__IOLookupByDeviceName` | external | `__TEXT,__text` | `0x7358` | **local** callout |
| `__IOGetCharValues` | external | `__TEXT,__text` | `0x76a8` | **local** callout |
| `__IOLookupByObjectNumber` | external | `__TEXT,__text` | `0x71ec` | local callout |
| `__IOGetIntValues` | external | `__TEXT,__text` | `0x7484` | local callout |
| `__IOSetIntValues` | external | `__TEXT,__text` | `0x78c8` | local callout |
| `__IOSetCharValues` | external | `__TEXT,__text` | `0x7a68` | local callout |
| `__IOCreateMachPort` | external | `__TEXT,__text` | `0x8e0c` | local callout |
| `.objc_class_name_IODeviceMaster` | external | — | `0x0` | class; methods local in `__TEXT` |
| `.objc_class_name_NXLock` | external | — | `0x0` | class; methods local in `__TEXT` |

`IODeviceMaster` and `NXLock` method symbols (`+[IODeviceMaster new]`, `-[NXLock lock]`, etc.) are all local in `__TEXT,__text`.

## Split decisions

### `IOStubs.m` — **required (yes)**

The tool binary defines `_IOMalloc`, `_IOFree`, `_IOLog`, `_IOGetTimestamp`, `_IOScheduleFunc`, and the `__IO*` device-master callouts locally in `__TEXT,__text` rather than importing them from a shared library. These stubs must live in a tool-only compilation unit when the nine shared PnP classes are split out of `R.m`. Today they are bundled in `R.m` alongside the PnP classes and `main`; extracting them to `IOStubs.m` is required for the shared-class / tool-only split.

### `IODeviceMaster.m` / `NXLock.m` — **stay (yes)**

Both classes are implemented locally in the tool (`+[IODeviceMaster new]`, `-[IODeviceMaster lookUpByDeviceName:…]`, `-[NXLock init]`, `-[NXLock lock]`, etc.). They are not kernel shared-compile inputs and remain in `PnPDump.tproj` as separate sources.

## Reference analysis

| Artifact | SHA-256 | binrecon `complete` | Notes |
| --- | --- | --- | --- |
| PnPDump (tool) | `006DC6BB…` | `true` | `pnpdump.json`, IDA + angr, Ghidra off |
| EISABus_reloc (kernel) | `8F252AF6…` | `true` | reused published `tools/binrecon/out/eisabus/` from main checkout |
