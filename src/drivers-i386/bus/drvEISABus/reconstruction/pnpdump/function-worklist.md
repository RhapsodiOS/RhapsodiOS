# PnPDump function worklist

Date: 2026-09-17
Branch: `pnpdump-binrecon-finish`

First dual guest rebuild after the Task 3 source split. No instruction-shape edits in this pass.

## Identities

### Tool (`PnPDump`)

| Side | SHA-256 | Size | `__TEXT,__text` |
| --- | --- | --- | --- |
| Reference | `006DC6BB73CEBC6243DA669E5199AEC808F309E72C3EE617A3FD8ED310364772` | 59260 | 21865 |
| Rebuilt | `04B61B40568C6830F076C83D45FE7511EE2FE04AE68C0043BF4BCF5B3E2EF8B9` | 299684 | 17391 |

### Reloc (`EISABus_reloc`)

| Side | SHA-256 | Size | `__TEXT,__text` |
| --- | --- | --- | --- |
| Reference | `8F252AF66CD49A8E03B51E57E90CB613D0B9DC1602263F4B7B6393E483977B23` | 100752 | 28808 |
| Rebuilt | `4430CA7B3DE0161164445D54DAF584B88CB0D48DFF5E7D55F565670A900E41F8` | 603952 | 27424 |

Rebuilt Mach-Os are the guest copies under `out/i386/drvEISABus/EISABus.config/` (magic `CE FA ED FE`). Size growth vs Apple is unstripped debug, not a finding.

## Parity

Both `parity_check.py` runs: `missing_strings (0)`, `missing_symbols (0)`, exit 0.

## Analyses

| Profile | Reference SHA match | Rebuilt IDA | `complete` | Notes |
| --- | --- | --- | --- | --- |
| `pnpdump.json` | yes (reused) | yes | `true` | IDA + angr; Ghidra off |
| `eisabus.json` | yes (`8F252AF6…`) | yes | `true` | IDA only for this dual run (see Concerns) |

Normalized-functions acceptance is FAIL on both, as expected before the instruction-stream campaign.

## Shared-name set (93)

Names that appear in **both** `binrecon function --list` outputs among the nlist-selected nine classes (`PnPDependentResources`, `PnPDeviceResources`, `PnPLogicalDevice`, `PnPResource`, `PnPResources`, `pnpDMA`, `pnpIOPort`, `pnpIRQ`, `pnpMemory`):

- `+[PnPDeviceResources setReadPort:]`
- `+[PnPDeviceResources setVerbose:]`
- `-[PnPDependentResources goodConfig]`
- `-[PnPDependentResources init]`
- `-[PnPDependentResources setGoodConfig:]`
- `-[PnPDeviceResources ID]`
- `-[PnPDeviceResources csn]`
- `-[PnPDeviceResources deviceCount]`
- `-[PnPDeviceResources deviceList]`
- `-[PnPDeviceResources deviceName]`
- `-[PnPDeviceResources deviceWithID:]`
- `-[PnPDeviceResources free]`
- `-[PnPDeviceResources initForBuf:Length:CSN:]`
- `-[PnPDeviceResources initForBufNoHeader:Length:CSN:]`
- `-[PnPDeviceResources parseConfig:Length:]`
- `-[PnPDeviceResources serialNumber]`
- `-[PnPDeviceResources setDeviceName:Length:]`
- `-[PnPDeviceResources setID:]`
- `-[PnPDeviceResources setSerialNumber:]`
- `-[PnPLogicalDevice ID]`
- `-[PnPLogicalDevice addCompatID:]`
- `-[PnPLogicalDevice compatIDs]`
- `-[PnPLogicalDevice depResources]`
- `-[PnPLogicalDevice deviceName]`
- `-[PnPLogicalDevice findMatchingDependentFunction:ForConfig:]`
- `-[PnPLogicalDevice free]`
- `-[PnPLogicalDevice init]`
- `-[PnPLogicalDevice logicalDeviceNumber]`
- `-[PnPLogicalDevice resources]`
- `-[PnPLogicalDevice setDeviceName:Length:]`
- `-[PnPLogicalDevice setID:]`
- `-[PnPLogicalDevice setLogicalDeviceNumber:]`
- `-[PnPResource free]`
- `-[PnPResource init]`
- `-[PnPResource list]`
- `-[PnPResource matches:Using:]`
- `-[PnPResource objectAt:Using:]`
- `-[PnPResource setDepStart:]`
- `-[PnPResources addDMA:]`
- `-[PnPResources addIOPort:]`
- `-[PnPResources addIRQ:]`
- `-[PnPResources addMemory:]`
- `-[PnPResources configure:Using:]`
- `-[PnPResources dma]`
- `-[PnPResources free]`
- `-[PnPResources initFromDeviceDescription:]`
- `-[PnPResources initFromRegisters:]`
- `-[PnPResources init]`
- `-[PnPResources irq]`
- `-[PnPResources markStartDependentResources]`
- `-[PnPResources memory]`
- `-[PnPResources port]`
- `-[PnPResources print]`
- `-[pnpDMA addDMAToList:]`
- `-[pnpDMA dmaChannels]`
- `-[pnpDMA initFrom:Length:]`
- `-[pnpDMA matches:]`
- `-[pnpDMA number]`
- `-[pnpDMA print]`
- `-[pnpDMA writePnPConfig:Index:]`
- `-[pnpIOPort alignment]`
- `-[pnpIOPort initFrom:Length:Type:]`
- `-[pnpIOPort initWithBase:Length:]`
- `-[pnpIOPort length]`
- `-[pnpIOPort lines_decoded]`
- `-[pnpIOPort matches:]`
- `-[pnpIOPort max_base]`
- `-[pnpIOPort min_base]`
- `-[pnpIOPort print]`
- `-[pnpIOPort writePnPConfig:Index:]`
- `-[pnpIRQ addToIRQList:]`
- `-[pnpIRQ initFrom:Length:]`
- `-[pnpIRQ irqs]`
- `-[pnpIRQ matches:]`
- `-[pnpIRQ number]`
- `-[pnpIRQ print]`
- `-[pnpIRQ setHigh:Level:]`
- `-[pnpIRQ writePnPConfig:Index:]`
- `-[pnpMemory alignment]`
- `-[pnpMemory bit16]`
- `-[pnpMemory bit32]`
- `-[pnpMemory bit8]`
- `-[pnpMemory highAddressDecode]`
- `-[pnpMemory initFrom:Length:Type:]`
- `-[pnpMemory initWithBase:Length:Bit16:Bit32:HighAddr:Is32:]`
- `-[pnpMemory is32]`
- `-[pnpMemory length]`
- `-[pnpMemory matches:]`
- `-[pnpMemory max_base]`
- `-[pnpMemory min_base]`
- `-[pnpMemory print]`
- `-[pnpMemory setControl:]`
- `-[pnpMemory writePnPConfig:Index:]`

Of those 93 on the **tool** `--list`: 41 byte-identical, 44 differing, 8 unpaired (`missing-reference` on the Apple tool — kernel-side methods that the shared compile also emits into PnPDump). Zero tool-only or reloc-only names among the nine classes.

## Tool-only names

Present on the tool `--list` and **not** in the nine-class shared set:

- Entry: `_main`, `_bail`
- `IODeviceMaster`: `+[IODeviceMaster new]`, `-[IODeviceMaster free]`, `lookUpByDeviceName:objectNumber:deviceKind:`, `lookUpByObjectNumber:deviceKind:deviceName:`, `getCharValues:…`, `getIntValues:…`, `setCharValues:…`, `setIntValues:…`, `createMachPort:objectNumber:`
- `NXLock`: `init`, `free`, `lock`, `unlock`
- Local DriverKit-ish stubs in `IOStubs.m`: `_IOMalloc`, `_IOFree`, `_IOLog`, `_IOPanic`, `_IOSleep`, `_IODelay`, `_IOCopyMemory`, `_IOGetTimestamp`, `_IOScheduleFunc`, `_IOUnscheduleFunc`, `_IOInitGeneralFuncs`, `_IOFindNameForValue`, `_IOFindValueForName`, `_IOExitThread`, `_IOForkThread`, `_IOResumeThread`, `_IOSuspendThread`, `_calloutThread`
- MIG / PM wrappers (Apple has full `__TEXT` bodies; rebuilt currently has local 6-instruction `return -1` stubs): `__IOCallDeviceMethod`, `__IOGetCharValues`, `__IOGetIntValues`, `__IOSetCharValues`, `__IOSetIntValues`, `__IOLookupByDeviceName`, `__IOLookupByObjectNumber`, `__IOCreateMachPort`, `__IOCopyMemory`, `__IOGetSystemConfig`, `__IOGetDriverConfig`, `__IOGetEISADeviceConfig`, `__IOMapEISADeviceMemory`, `__IOMapEISADevicePorts`, `__IOUnMapEISADevicePorts`, `__IOProbeDriver`, `__IOUnloadDriver`, `__PMGetPowerEvent`, `__PMGetPowerStatus`, `__PMRestoreDefaults`, `__PMSetPowerManagement`, `__PMSetPowerState`
- CRT / dyld / libc imports and glue: `start`, `__start`, `__call_mod_init_funcs`, `__dyld_init_check`, `__dyld_func_lookup`, `dyld_stub_binding_helper`, `__objcInit`, `_objc_msgSend`, `_objc_msgSendSuper`, `_printf`, `_fprintf`, `_sprintf`, `_vsprintf`, `_syslog`, `_malloc`, `_free`, `_bcopy`, `_exit`, `_strcmp`, `_strncpy`, `_device_master_self`, `_port_allocate`, `_msg_receive`, `_msg_rpc`, `_mig_get_reply_port`, `_mig_dealloc_reply_port`, `_mutex_try_lock`, `_mutex_wait_lock`, `_spin_lock`, `_cond_signal`, `_condition_wait`, `_cthread_fork`, `_cthread_exit`, `_thread_resume`, `_thread_suspend`, `_kern_timestamp`
- Unpaired tool extras: `___IOCopyMemory` (`missing-reference`); `_cond_broadcast` (`missing-rebuilt`)

## Tool `--list` summary (IDA)

186 functions: **43** byte-identical, **0** masked-eq, **133** remaining differing, **10** unpaired.

## Reachability

Cheapest remaining rows, tool IDA `--list` order:

**Already compiler-shaped** (same mnemonic stream; bytes / PIC / call targets differ — not a source rewrite):

- 41 shared accessors already `identical` (getters/setters on the nine classes).
- Diff 0 with empty flags: `IODeviceMaster` wrappers, `_IOMalloc` / `_IOFree`, CRT glue. Instruction text matches; call-site bytes and CFG tags do not (`calls differ`).
- Diff 1: `+[PnPDeviceResources setReadPort:]` is PIC displacement only (`_readPort - 5B0Ch` vs `_readPort - 3C74h`). Similar small PIC/immediate rows (`setVerbose:`, `deviceCount`, `addDMAToList:`, `addToIRQList:`).

**Source-shaped** (need later campaign work, not this commit):

- MIG/PM names: Apple 60–200+ instruction bodies vs rebuilt 6-instruction `mov eax, -1; leave; ret`.
- Shared-class extras in the rebuilt tool (`missing-reference` on Apple PnPDump): `writePnPConfig:Index:` on DMA/port/IRQ/memory, `-[PnPResources configure:Using:]`, `-[PnPResources initFromDeviceDescription:]`, `-[PnPLogicalDevice findMatchingDependentFunction:ForConfig:]`, `-[PnPDependentResources init]`.
- Large remaining bodies: `-[PnPDeviceResources parseConfig:Length:]` (diff 857), `_main` (357), `-[PnPResources initFromRegisters:]` (173), `-[pnpMemory initFrom:Length:Type:]` (119).

Start the instruction-stream campaign on the compiler-shaped PIC/call-target rows and the already-identical accessors (confirm they stay identical after any compile-flag change). Leave MIG stub shape and the large parse/`_main` bodies for dedicated later tasks.

## Source map

`python -m binrecon source-map` against the Apple tool + `PnPDump.tproj` + `EISABus.lksproj` (`--objc-methods`): mapped 138, unmapped 37 (CRT/dyld/libc), duplicate_candidates 2 (`_bail` and `_main` also match `dumpConfig.m`), boundary_disputed 0.

## Waivers (2026-09-17)

Human decision after Task 4 review:

- **`-DDRIVER_PRIVATE` on the tool is a compile gate, not an identity chase.** Keep it. Shared `PnPResources.m` imports `KernDeviceDescription.h`, which is empty without the flag. Do not remove it in later tasks to “match the old plan line.”
- **Reloc `--list` / `--name` is IDA-only for the rest of this campaign.** Ghidra stays enabled on `eisabus.json` but rebuilt Ghidra/angr failures are accepted. Do not spend later tasks getting those two analyzers green.

## Concerns

- Reloc rebuilt **angr** failed (`block at address 1444 is outside function at address 1465`). Reloc rebuilt **Ghidra** failed (`Ghidra relocation operand metadata is ambiguous`). Reloc dual-run `complete: true` is IDA-only. Apple reloc Ghidra/angr reference at `D:\RhapsodiOS\tools\binrecon\out\eisabus\` is unchanged.
- Ghidra cannot use a project path under `.worktrees` (`Path element starting with '.' is not permitted`). Reloc IDA output for this run lives in `D:\RhapsodiOS\tools\binrecon\out\eisabus-task4\` (not committed).
- Guest compile needed `-DDRIVER_PRIVATE`, bootstrap-root `LOCAL_LDFLAGS`, `LIBS = -lDriver`, basename `MFILES` + `vpath`, local MIG stubs, and `"$PnP"` in shared `PnPResources.m`. Those landed in the preceding `drvEISABus:` compile-fix commit.
