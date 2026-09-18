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

## Task 6 experiment lists (2026-09-17)

Written **before** the first source-shape `.m` edit. Cheapest `differing` first.
One idea per remaining non-equal paired **tool** function. Tag is `shared` or `tool-only`.
Tried experiments are marked in place after a miss. Empty `none` lists accept as
`compiler-shaped leftover after exhausted source-shape list` (reviewer Pat Raynor).

CRT/dyld/libc rows are not hand-written; they are listed so the paired-tool set is complete,
then left alone. Unpaired `missing-reference` shared-class names are **not** paired tool
functions and have no experiment list.

Accepted 2026-09-17: remaining `none` hand-written rows are `intentional-mismatch` in the PnPDump ledger (shared names also on reloc unless already `assembly-matched`). Experiment lists below were not rewritten.

- `-[IODeviceMaster getCharValues:forParameter:objectNumber:count:]` (tool-only, diff 0): none — identical mnemonic stream; `calls differ` only
- `-[IODeviceMaster getIntValues:forParameter:objectNumber:count:]` (tool-only, diff 0): none — identical mnemonic stream; `calls differ` only
- `-[IODeviceMaster lookUpByDeviceName:objectNumber:deviceKind:]` (tool-only, diff 0): none — identical mnemonic stream; `calls differ` only
- `-[IODeviceMaster lookUpByObjectNumber:deviceKind:deviceName:]` (tool-only, diff 0): none — identical mnemonic stream; `calls differ` only
- `-[IODeviceMaster setCharValues:forParameter:objectNumber:count:]` (tool-only, diff 0): none — identical mnemonic stream; `calls differ` only
- `-[IODeviceMaster setIntValues:forParameter:objectNumber:count:]` (tool-only, diff 0): none — identical mnemonic stream; `calls differ` only
- `_IOExitThread` (tool-only, diff 0): none — identical mnemonic stream; `calls differ` only
- `_IOForkThread` (tool-only, diff 0): none — identical mnemonic stream; `calls differ` only
- `_IOFree` (tool-only, diff 0): none — identical mnemonic stream; `calls differ` only
- `_IOMalloc` (tool-only, diff 0): none — identical mnemonic stream; `calls differ` only
- `_IOResumeThread` (tool-only, diff 0): none — identical mnemonic stream; `calls differ` only
- `_IOSuspendThread` (tool-only, diff 0): none — identical mnemonic stream; `calls differ` only
- `__dyld_func_lookup` (tool-only, diff 0): none — CRT/dyld/libc glue; not hand-written
- `dyld_stub_binding_helper` (tool-only, diff 0): none — CRT/dyld/libc glue; not hand-written
- `+[PnPDeviceResources setReadPort:]` (shared, diff 1; reloc masked-eq d=0): none — PIC displacement of `_readPort` only; reloc already masked-eq
- `-[PnPDeviceResources deviceCount]` (shared, diff 1; reloc masked-eq d=0): none — PIC selector displacement only; reloc already masked-eq
- `-[PnPLogicalDevice addCompatID:]` (shared, diff 1; reloc masked-eq d=0): none — PIC selector displacement only; reloc already masked-eq
- `_IOLog` (tool-only, diff 1): none — PIC leftover
- `__call_mod_init_funcs` (tool-only, diff 1): none — CRT/dyld/libc glue; not hand-written
- `__objcInit` (tool-only, diff 1): none — CRT/dyld/libc glue; not hand-written
- `_bcopy` (tool-only, diff 1): none — CRT/dyld/libc glue; not hand-written
- `_cond_signal` (tool-only, diff 1): none — CRT/dyld/libc glue; not hand-written
- `_condition_wait` (tool-only, diff 1): none — CRT/dyld/libc glue; not hand-written
- `_cthread_exit` (tool-only, diff 1): none — CRT/dyld/libc glue; not hand-written
- `_cthread_fork` (tool-only, diff 1): none — CRT/dyld/libc glue; not hand-written
- `_device_master_self` (tool-only, diff 1): none — CRT/dyld/libc glue; not hand-written
- `_exit` (tool-only, diff 1): none — CRT/dyld/libc glue; not hand-written
- `_fprintf` (tool-only, diff 1): none — CRT/dyld/libc glue; not hand-written
- `_free` (tool-only, diff 1): none — CRT/dyld/libc glue; not hand-written
- `_kern_timestamp` (tool-only, diff 1): none — CRT/dyld/libc glue; not hand-written
- `_malloc` (tool-only, diff 1): none — CRT/dyld/libc glue; not hand-written
- `_mig_dealloc_reply_port` (tool-only, diff 1): none — CRT/dyld/libc glue; not hand-written
- `_mig_get_reply_port` (tool-only, diff 1): none — CRT/dyld/libc glue; not hand-written
- `_msg_receive` (tool-only, diff 1): none — CRT/dyld/libc glue; not hand-written
- `_msg_rpc` (tool-only, diff 1): none — CRT/dyld/libc glue; not hand-written
- `_mutex_try_lock` (tool-only, diff 1): none — CRT/dyld/libc glue; not hand-written
- `_mutex_wait_lock` (tool-only, diff 1): none — CRT/dyld/libc glue; not hand-written
- `_objc_msgSend` (tool-only, diff 1): none — CRT/dyld/libc glue; not hand-written
- `_objc_msgSendSuper` (tool-only, diff 1): none — CRT/dyld/libc glue; not hand-written
- `_port_allocate` (tool-only, diff 1): none — CRT/dyld/libc glue; not hand-written
- `_printf` (tool-only, diff 1): none — CRT/dyld/libc glue; not hand-written
- `_spin_lock` (tool-only, diff 1): none — CRT/dyld/libc glue; not hand-written
- `_sprintf` (tool-only, diff 1): none — CRT/dyld/libc glue; not hand-written
- `_strcmp` (tool-only, diff 1): none — CRT/dyld/libc glue; not hand-written
- `_strncpy` (tool-only, diff 1): none — CRT/dyld/libc glue; not hand-written
- `_syslog` (tool-only, diff 1): none — CRT/dyld/libc glue; not hand-written
- `_thread_resume` (tool-only, diff 1): none — CRT/dyld/libc glue; not hand-written
- `_thread_suspend` (tool-only, diff 1): none — CRT/dyld/libc glue; not hand-written
- `_vsprintf` (tool-only, diff 1): none — CRT/dyld/libc glue; not hand-written
- `+[PnPDeviceResources setVerbose:]` (shared, diff 2; reloc masked-eq d=1): none — extra PIC load of extern `_verbose_ptr`; reloc already masked-eq
- `-[NXLock unlock]` (tool-only, diff 2): none — jump labels only
- `-[pnpDMA addDMAToList:]` (shared, diff 2; reloc different d=2): omit explicit `return self` so eax is not copied from edx (local vs expression) — **MATCHED** tool+reloc `raw_equal` (Task 6)
- `-[pnpIOPort initWithBase:Length:]` (shared, diff 2; reloc different d=1): none — PIC / objc super_class displacement only
- `-[pnpIRQ addToIRQList:]` (shared, diff 2; reloc different d=2): omit explicit `return self` so eax is not copied from edx (local vs expression) — **MATCHED** tool+reloc `raw_equal` (Task 6)
- `-[pnpMemory initWithBase:Length:Bit16:Bit32:HighAddr:Is32:]` (shared, diff 2; reloc different d=1): none — PIC / objc class-pointer displacement only
- `_IOPanic` (tool-only, diff 2): none — PIC leftover
- `__dyld_init_check` (tool-only, diff 2): none — CRT/dyld/libc glue; not hand-written
- `-[NXLock lock]` (tool-only, diff 3): none — jump labels / PIC leftovers
- `_bail` (tool-only, diff 3): none — PIC leftover on the syslog path
- `-[NXLock free]` (tool-only, diff 4): none — PIC / objc class-pointer leftover
- `_IOCopyMemory` (tool-only, diff 4): none — PIC leftover
- `_IOSleep` (tool-only, diff 5): local vs expression for the msg_receive timeout block — **tried, kept**; leftover is PIC displacement of `_sleepPort`; **accepted** compiler-shaped
- `-[IODeviceMaster createMachPort:objectNumber:]` (tool-only, diff 6): return the MIG call result instead of `self` (local vs expression) — **tried, kept**; mnemonic stream matches; leftover is call-site PIC; **accepted** compiler-shaped
- `-[NXLock init]` (tool-only, diff 6): declaration order of the existing mutex/cond zeroing stores — **tried, kept**; leftover is PIC selector / super_class; **accepted** compiler-shaped
- `-[PnPResources free]` (shared, diff 6; reloc different d=1): none — PIC selector / objc super_class vs ext leftover
- `-[PnPResource free]` (shared, diff 8; reloc different d=3): none — extra PIC selector push plus super_class vs ext leftover
- `-[PnPResource init]` (shared, diff 8; reloc different d=3): none — PIC selector leftover; jump labels only besides PIC
- `-[PnPDeviceResources free]` (shared, diff 9; reloc different d=4): none — extra PIC selector push plus super_class vs ext leftover
- `_IOFindValueForName` (tool-only, diff 9): loop shape of the table walk — **tried, kept**; leftover is load/add scheduling; **accepted** compiler-shaped
- `-[PnPLogicalDevice free]` (shared, diff 10; reloc different d=3): none — extra PIC selector push plus super_class vs ext leftover
- `-[PnPLogicalDevice init]` (shared, diff 11; reloc different d=1): none — PIC selector leftover; reloc is class-pointer names only
- `-[pnpIRQ setHigh:Level:]` (shared, diff 11; reloc different d=11): invert outer test to `if (high)` / `else` (if vs else if) — **tried, kept**; leftover is register allocation (`edx`/`al` vs `eax`/`dl`); **accepted** compiler-shaped on both
- `_IOFindNameForValue` (tool-only, diff 11): loop shape of the table walk — **tried, kept**; leftover is lea/add scheduling plus PIC; **accepted** compiler-shaped
- `-[PnPDeviceResources deviceWithID:]` (shared, diff 12; reloc different d=10): `if (device)` plus `if (ID != id) continue; return device` — **tried, kept**; leftover is inverted ID-compare jump (equivalent CFG); **accepted** compiler-shaped on both
- `-[pnpIOPort print]` (shared, diff 12; reloc different d=9): none — Apple tool calls `_printf`, reloc both call `_IOLog`; dual-bar forbids swapping
- `-[PnPDeviceResources initForBufNoHeader:Length:CSN:]` (shared, diff 13; reloc different d=6): none — PIC selectors plus `_printf` vs `_IOLog` on the error path
- `-[PnPLogicalDevice setDeviceName:Length:]` (shared, diff 14; reloc different d=14): `if (_deviceNameLength == 0)` plus signed `copyLength = 0x4f; if (copyLength > length)` — **tried, kept**; leftover is IDA `__src` vs `arg_8` plus jump labels; reloc **masked_equal**; tool **accepted** compiler-shaped
- `+[IODeviceMaster new]` (tool-only, diff 15): local vs expression for the allocated object — **tried, kept**; leftover is PIC of `_thisTasksId` / alloc selector; **accepted** compiler-shaped
- `-[PnPResources addDMA:]` (shared, diff 15; reloc different d=9): nested `[[_dma list] addObject:]` (local vs expression) — **tried, kept**; reloc **masked_equal**; tool leftover is PIC selector displacements; **accepted** compiler-shaped
- `-[PnPResources addIOPort:]` (shared, diff 15; reloc different d=9): nested `[[_port list] addObject:]` (local vs expression) — **tried, kept**; reloc **masked_equal**; tool leftover is PIC selector displacements; **accepted** compiler-shaped
- `-[PnPResources addIRQ:]` (shared, diff 15; reloc different d=9): nested `[[_irq list] addObject:]` (local vs expression) — **tried, kept**; reloc **masked_equal**; tool leftover is PIC selector displacements; **accepted** compiler-shaped
- `-[PnPResources addMemory:]` (shared, diff 15; reloc different d=9): nested `[[_memory list] addObject:]` (local vs expression) — **tried, kept**; reloc **masked_equal**; tool leftover is PIC selector displacements; **accepted** compiler-shaped
- `__start` (tool-only, diff 17): none — CRT/dyld/libc glue; not hand-written
- `-[PnPResources init]` (shared, diff 20; reloc different d=6): none — PIC selector leftover
- `-[pnpMemory matches:]` (shared, diff 20; reloc different d=19): loop shape / `if` vs `else if` on the channel compare — **tried, kept**; reloc **masked_equal**; tool leftover is PIC selector; **accepted** compiler-shaped
- `-[pnpMemory setControl:]` (shared, diff 22; reloc different d=21): if vs else if — **tried, miss**; omit reciprocal zeros plus omit return self — **tried, kept**; leftover is char-arg vs Apple pointer reload plus PIC/jpt register; **accepted** compiler-shaped on both
- `-[PnPDeviceResources setDeviceName:Length:]` (shared, diff 24; reloc different d=24): ivars plus `if (_deviceNameLength == 0)` plus signed min 0x4f — **tried, kept**; leftover is IDA `__src` vs `arg_8` plus jump labels; reloc **masked_equal**; tool **accepted** compiler-shaped
- `-[PnPResources print]` (shared, diff 24; reloc different d=18): none — Apple tool `_printf` vs rebuilt `_IOLog`; reloc both `_IOLog`
- `-[pnpIRQ initFrom:Length:]` (shared, diff 26; reloc different d=22): mask and flags as buffer expressions — **tried, kept**; leftover is extra buffer-pointer copy / PIC / IDA names; **accepted** compiler-shaped on both
- `-[pnpIOPort matches:]` (shared, diff 30; reloc different d=27): alignment local plus 16-bit `otherBase` — **tried, kept**; leftover is PIC / register vs stack; **accepted** compiler-shaped on both
- `-[pnpIRQ print]` (shared, diff 31; reloc different d=16): none — Apple tool `_printf` vs rebuilt `_IOLog`; reloc both `_IOLog`
- `-[PnPResource objectAt:Using:]` (shared, diff 32; reloc different d=25): if vs else if on the type dispatch — **tried, kept**; leftover is usingList local / nested list plus inner jump polarity; **accepted** compiler-shaped on both
- `_IOInitGeneralFuncs` (tool-only, diff 32): statement order of the existing assignments — **tried, miss** (head/tail swap reverted); leftover is PIC GOT vs lea plus getClass; **accepted** compiler-shaped
- `-[pnpDMA initFrom:Length:]` (shared, diff 33; reloc different d=22): loop shape of the channel-mask walk — **tried, kept**; leftover is `_count` zero / buffer pointer versus `data[1]`; **accepted** compiler-shaped on both
- `_IODelay` (tool-only, diff 36): local vs expression for the timestamp add — **tried, kept**; leftover is explicit carry vs `adc` plus loop buffer reuse; **accepted** compiler-shaped
- `-[PnPResource matches:Using:]` (shared, diff 37; reloc different d=23): count==0 else-wrap — **tried, kept**; leftover is Apple list/count stack-trick vs configList local / PIC; **accepted** compiler-shaped on both
- `-[pnpMemory print]` (shared, diff 38; reloc different d=21): none — Apple tool `_printf` vs rebuilt `_IOLog`; reloc both `_IOLog`
- `-[pnpDMA matches:]` (shared, diff 44; reloc different d=33): if vs else if on `otherCount != 1` — **tried, kept**; leftover is Apple tool `_printf` vs `_IOLog`, double `[number]` / in-loop `dmaChannels` vs local; **accepted** compiler-shaped on both
- `-[pnpIRQ matches:]` (shared, diff 44; reloc different d=33): if vs else if on `otherCount != 1` — **tried, kept**; leftover is Apple tool `_printf` vs `_IOLog`, double `[number]` / in-loop `irqs` vs local; **accepted** compiler-shaped on both
- `-[pnpDMA print]` (shared, diff 48; reloc different d=34): none — Apple tool `_printf` vs rebuilt `_IOLog`; reloc both `_IOLog`
- `__PMRestoreDefaults` (tool-only, diff 51): none — Apple 60–200+ instruction MIG/PM body vs local 6-instruction `return -1` stub
- `_IOUnscheduleFunc` (tool-only, diff 52): loop shape of the callout-chain walk — **tried, kept**; leftover is PIC GOT vs lea plus unlink addr math; **accepted** compiler-shaped
- `__IOMapEISADevicePorts` (tool-only, diff 56): none — Apple 60–200+ instruction MIG/PM body vs local 6-instruction `return -1` stub
- `__IOUnMapEISADevicePorts` (tool-only, diff 56): none — Apple 60–200+ instruction MIG/PM body vs local 6-instruction `return -1` stub
- `__PMSetPowerManagement` (tool-only, diff 61): none — Apple 60–200+ instruction MIG/PM body vs local 6-instruction `return -1` stub
- `__PMSetPowerState` (tool-only, diff 61): none — Apple 60–200+ instruction MIG/PM body vs local 6-instruction `return -1` stub
- `__PMGetPowerEvent` (tool-only, diff 65): none — Apple 60–200+ instruction MIG/PM body vs local 6-instruction `return -1` stub
- `__IOCreateMachPort` (tool-only, diff 69): none — Apple 60–200+ instruction MIG/PM body vs local 6-instruction `return -1` stub
- `__PMGetPowerStatus` (tool-only, diff 71): none — Apple 60–200+ instruction MIG/PM body vs local 6-instruction `return -1` stub
- `__IOProbeDriver` (tool-only, diff 77): none — Apple 60–200+ instruction MIG/PM body vs local 6-instruction `return -1` stub
- `__IOUnloadDriver` (tool-only, diff 77): none — Apple 60–200+ instruction MIG/PM body vs local 6-instruction `return -1` stub
- `-[PnPResources markStartDependentResources]` (shared, diff 78; reloc different d=22): statement order of the four list walks — **tried, kept** as nested `[[list] count]` setDepStart; leftover is PIC / last-push register plus return self; **accepted** compiler-shaped on both
- `-[pnpIOPort initFrom:Length:Type:]` (shared, diff 84; reloc different d=72): declaration order of existing locals after the header parse — **tried, kept**; leftover is type-8/9 layout / flags-bit polarity plus tool `_printf` vs `_IOLog`; **accepted** compiler-shaped on both
- `_calloutThread` (tool-only, diff 85): loop shape of the callout dispatch — **tried, kept**; leftover is PIC GOT sentinel / reversed timestamp cmp / unlink math; **accepted** compiler-shaped
- `__IOCopyMemory` (tool-only, diff 86): none — Apple full body vs local stub
- `__IOLookupByObjectNumber` (tool-only, diff 87): none — Apple 60–200+ instruction MIG/PM body vs local 6-instruction `return -1` stub
- `__IOLookupByDeviceName` (tool-only, diff 88): none — Apple 60–200+ instruction MIG/PM body vs local 6-instruction `return -1` stub
- `__IOSetIntValues` (tool-only, diff 95): none — Apple 60–200+ instruction MIG/PM body vs local 6-instruction `return -1` stub
- `__IOMapEISADeviceMemory` (tool-only, diff 96): none — Apple 60–200+ instruction MIG/PM body vs local 6-instruction `return -1` stub
- `__IOSetCharValues` (tool-only, diff 96): none — Apple 60–200+ instruction MIG/PM body vs local 6-instruction `return -1` stub
- `_IOGetTimestamp` (tool-only, diff 102): local vs expression for the 64-bit store — **tried, miss** (`*1000ULL` local store regressed `--list`); leftover is hand-rolled scale versus Apple `shld`/`adc`; **accepted** compiler-shaped
- `__IOGetSystemConfig` (tool-only, diff 103): none — Apple 60–200+ instruction MIG/PM body vs local 6-instruction `return -1` stub
- `__IOGetDriverConfig` (tool-only, diff 106): none — Apple 60–200+ instruction MIG/PM body vs local 6-instruction `return -1` stub
- `-[pnpMemory initFrom:Length:Type:]` (shared, diff 119; reloc different d=161): declaration order of existing locals after the header parse — **tried, kept**; leftover is type-switch layout / extra zeros / tool `_printf`; **accepted** compiler-shaped on both
- `__IOGetIntValues` (tool-only, diff 130): none — Apple 60–200+ instruction MIG/PM body vs local 6-instruction `return -1` stub
- `__IOGetCharValues` (tool-only, diff 131): none — Apple 60–200+ instruction MIG/PM body vs local 6-instruction `return -1` stub
- `-[PnPDeviceResources initForBuf:Length:CSN:]` (shared, diff 134; reloc different d=149): declaration order of the header locals — **tried, kept**; leftover is Apple byte-copy ID loop / tool `_printf`; **accepted** compiler-shaped on both
- `_IOScheduleFunc` (tool-only, diff 162): loop shape of the insertion walk — **tried, kept**; leftover is Apple tail-pointer / shld*1e9 versus mul; **accepted** compiler-shaped
- `__IOCallDeviceMethod` (tool-only, diff 167): none — Apple 60–200+ instruction MIG/PM body vs local 6-instruction `return -1` stub
- `-[PnPResources initFromRegisters:]` (shared, diff 173; reloc different d=91): loop shape of the register walk — **tried, kept**; leftover is verbose PIC / selector displacements; **accepted** compiler-shaped on both
- `__IOGetEISADeviceConfig` (tool-only, diff 224): none — Apple 60–200+ instruction MIG/PM body vs local 6-instruction `return -1` stub
- `_main` (tool-only, diff 357): statement order of the existing option/dispatch blocks (large body; one idea only)
- `-[PnPDeviceResources parseConfig:Length:]` (shared, diff 857; reloc different d=890): loop shape of the tag walk (large body; one idea only)
