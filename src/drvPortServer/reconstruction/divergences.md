# drvPortServer reconstruction divergences

Report pass over Apple's shipped `PortServer_reloc`
(`reference_sha256` `D724803154872B1D8199BE0426EAC4FDBE499C56FB81CCF07D5706916FF9B949`,
69112 bytes, `MH_PRELOAD` i386). This document records where our reimplementation in
`src/drvPortServer/PortServer.drvproj/PortServer.lksproj/` diverges from that binary.
**It changes no driver source.** Task 7 repairs the compile blockers and Task 8 applies
the divergence fixes.

Line numbers are against the tree as committed at the time of the pass
(`AppleIOPSSafeCondLock.m` 632 lines, `IOPortSession.m` 1132, `IOPortSessionKern.m` 860,
`PDPseudo.m` 283, `PortServer.m` 548, `ttyiops.m` 2206).

> **All line numbers here are pre-repair.** Task 7 fixes five files' structural damage
> (Section 4) and will shift them. The authoritative post-repair locations are in the
> regenerated `source-map.json`, not in this document.

---

## 1. Coverage and examination depth

The reference partitions into **113 functions**: 110 hand-written, 2 pieces of
build-generated Kernel Server glue, and 1 libgcc helper. The 110 were analysed in three
passes, split by source file.

| Pass | Source files | Functions | Matches | Divergences |
|---|---|---|---|---|
| 1 | `AppleIOPSSafeCondLock.m`, `IOPortSession.m` | 44 | 8 | 36 |
| 2 | `PDPseudo.m`, `PortServer.m`, `IOPortSessionKern.m` | 41 | 3 | 38 |
| 3 | `ttyiops.m` | 25 | 8 | 17 |
| **Total** | | **110** | **19** | **91** |

| Depth | After the report pass | After the Task 8 fix pass | What the post-fix count means |
|---|---|---|---|
| `assembly-matched` | 19 | **43** | A fix part re-read the reference function's full instruction stream and our source transcribes it |
| `control-flow-confirmed` | 0 | **41** | Block shape, call targets and constants checked against the stream, but a compiler-dependent spelling or a partial read blocks a stronger claim |
| `signature-confirmed` | 0 | **3** | Only the reference's own type metadata backs the repair (564, 592, 680 -- see Finding 9) |
| `unexamined` | 91 | **20** | Repaired but never re-verified after editing, or not repaired at all |
| `intentional-mismatch` | 3 | **6** | The 3 build/libgcc entries, plus Findings 67, 79 (`ttyiops_close`) and 80 |
| **Total** | **113** | **113** | |

The report pass read all 110 mapped functions' full instruction streams and used
`unexamined` only for a function that diverges. The fix pass then applied the repairs; the
post-fix column records what each part **re-verified after editing**, which is a stricter
bar. Where the three parts disagreed or were vague about a function, the ledger carries the
weaker status; the per-finding `**Outcome**` paragraphs in Section 11 say which, and why.

Source-map buckets: **88 / 22 / 3 / 0 before the fix pass, 110 / 3 / 0 / 0 after**
(mapped / unmapped / duplicate_candidates / boundary_disputed). The 19 recoverable unmapped
entries were functions whose reference name did not exist in our source because the name or
the method kind differed (Sections 4 and 7); every one of those renames landed. The 3
duplicate candidates were an artefact of the brace damage in Section 4 and went with Task
7's repair. The 3 that remain unmapped -- `+[PortServerKernelServerInstance
kernelServerInstance]` (15728), `+[PortServerVersion driverKitVersionForPortServer]` (15740)
and `__divdi3` (15752) -- are absent from our source by design: build-generated Kernel
Server glue and libgcc.

## 2. Stated limitations

- **Two analyzers, not three.** Ghidra is disabled in `tools/binrecon/profiles/portserver.json`
  because it cannot analyze this binary: its raw-i386 fallback fails validation with
  `external relocation symbol association is missing`, deterministically, and this image has
  59 undefined externals. There is no `analysis-reference-ghidra.json`, and every
  analyzer-agreement statement here compares **IDA against angr only**. angr's `CFGFast` is
  the weaker of the two, so `boundary_disputed` is materially **less sensitive** than it
  would be in a three-analyzer run: a boundary both analyzers get wrong the same way would
  pass unnoticed. No such case is known, but the check is weaker and that is recorded rather
  than glossed.
- **`pdservd.tproj` is out of scope** (spec section 1.2). `pdservd` is `MH_EXECUTE`, which
  `binrecon/macho.py` rejects. It is deliberately not under `--source-dir`, and its absence
  from `source-map.json` is **not** a gap.
- **No compile gate.** No Rhapsody guest is available, so nothing here has been compiled.
  Every claim rests on reading the reference disassembly.

## 3. Analyzer agreement

IDA reports 113 functions; angr reports 316. **Every one of IDA's 113 start addresses is
also an angr start address, and all 113 sizes are identical.** angr's extra 203 entries are
interior addresses that `CFGFast` promotes to function starts because it splits basic blocks
more finely. That is recorded, not corrected, and it is not 203 boundary disputes -- it is
203 interior labels inside extents the two analyzers already agree on. `boundary_disputed`
is therefore correctly empty.

IDA's extents run 1-2 bytes under a naive symbol-gap calculation for some functions, because
the gap includes the linker's padding to the next 4-byte boundary. **IDA's `size` is
authoritative** and is what `ledger.json` and `source-map.json` carry.

## 4. Compile blockers -- five of the six source files

**Five of the six `.m` files in `PortServer.lksproj` cannot compile as committed.** All of
this predates the reconstruction. It is repaired in Task 7, in its own commits, ahead of any
divergence fix.

| File | Defect | Signal |
|---|---|---|
| `AppleIOPSSafeCondLock.m` | missing closing brace on `-setCondition:` (~line 361); orphaned comment tail at 487-489 with no opening comment marker | brace delta `+1` |
| `PDPseudo.m` | one extra closing brace (~line 209) | brace delta `-1` |
| `ttyiops.m` | missing closing brace after line 959 (`ttyiops_start`) and after line 1793 (the duplicate `ttyiops_waitForDCD` stub at 1780-1794) | brace delta `+2` |
| `IOPortSessionKern.m` | raw newline inside a string literal, lines 472-473 | odd quote count |
| `PortServer.m` | two literal NUL bytes at lines 192 and 224 where an escaped NUL was intended, **and** a raw newline inside a string literal at lines 101-102 | `file(1)` reports the source as `data` |

Only `IOPortSession.m` is structurally clean.

Two consequences worth stating explicitly:

- The `AppleIOPSSafeCondLock.m` brace damage is **what produced the three
  `duplicate_candidates`** in the source map. The scanner saw two apparent definitions of
  `setCondition:` and `unlockWith:` because the first was never closed. They are not real
  duplicates.
- A separate call-arity defect was found in the same family: `ttyiops_close` is declared
  with 2 parameters but called with 4 at `ttyiops.m:2031`.

## 5. Reference data absent from our source

### From pass 1

Recorded here once so the findings can refer to them.

**`AppleIOPSSafeCondLock` instance layout** — `__OBJC,__instance_vars` at 30412, read
directly; `__class[0]` gives `super_class` `Object`, `instance_size` **20** (0x14),
`ivars` → 30412:

| ivar | `@encode` | offset |
|---|---|---|
| `cond_interlock` | `{?="locked"I}` | 4 |
| `conditionVar` | `i` | 8 |
| `sleep_interlock` | `{?="locked"I}` | 12 |
| `interuptable` | `C` | 16 |
| `want_lock` | `C` | 17 |
| `waiting` | `C` | 18 |

`{?="locked"I}` is a 4-byte anonymous struct with one `unsigned int` member named
`locked` — the NeXT `simple_lock` shape, consistent with the `xchg`-based test-and-set
sequences at 604-621, 724-741, 840-857, 1000-1017 and 1120-1137.

**`IOPortSession` instance layout** — `__instance_vars` at 30488; `__class[1]` gives
`super_class` `Object`, `instance_size` **8**, `ivars` → 30488:

| ivar | `@encode` | offset |
|---|---|---|
| `_priv` | `^v` | 4 |

**The `_priv` block** (0x34 bytes, `IOMalloc`ed at 1412, `IOFree`d at 1792, `memset` to
zero at 1426) — recovered from the stores in `initForDevice:result:` and the loads
everywhere else:

```
+0x00 id     device       (the IOGetObjectForDeviceName result)
+0x04 void * entry        (port-list entry, 0x20 bytes, NULL when not acquired)
+0x08 int    err          (initialised to 0xFFFFFD33 = -717)
+0x0c IMP    setState:mask:
+0x10 IMP    getState
+0x14 IMP    watchState:mask:
+0x18 IMP    nextEvent
+0x1c IMP    executeEvent:data:
+0x20 IMP    requestEvent:data:
+0x24 IMP    enqueueEvent:data:sleep:
+0x28 IMP    dequeueEvent:data:sleep:
+0x2c IMP    enqueueData:bufferSize:transferCount:sleep:
+0x30 IMP    dequeueData:bufferSize:transferCount:minCount:
```

**The port-list entry** (0x20 bytes, `IOMalloc`ed at 3014, `IOFree`d at 3530):

```
+0x00 next
+0x04 prev
+0x08 AppleIOPSSafeCondLock *
+0x0c NXConditionLock *      (initWith:1)
+0x10 id  device
+0x14 IOPortSession * owner
+0x18 int type               (0 none, 1 callout, 2 dialin)
+0x1c char callout waiters
+0x1d char dialin waiters
+0x1e char refcount
+0x1f (pad)
```

---

### From pass 2

### 5.1 `__cstring` (16160, 444 bytes, 20 entries)

```
16160 'PDPseudo'                16308 'ttyd%c'
16169 'Server Device'           16315 'PortServerPLGandS'
16183 "Port Server: Can't find space in devsw\n"
16223 'Port Server'             16333 'Maximum Sessions'
16235 'pdservd'                 16350 'IOPortSessionKern: Invalid Config Table\n'
16243 "ttyiops: Couldn't create any more tty instances\n"
16292 'Port Device tty'         16391 '/dev/rpski%02d'
16406 'ttytxd'  16413 'ttyrxd'  16420 'ttyas'
16426 'PStty%04x: ACTIVE failed (%d)\n'
16457 'PStty%04x: mctl PD_E_FLOW_CONTROL failed %d\n'
16502 'PStty%04x: dequeueData ret %d\n'
16533 'Soft'    16538 'Hard'
16543 'PStty%04x: %sware Overflow\n'
16571 'PStty%04x: enqueueData rtn (%d)\n'
```

The last nine belong to `ttyiops.m` and are out of scope. Every string my three files
use is in this list, and **our sources introduce one string that is not**
(`"PortServer: Maximum number of devices exceeded"`, Finding 39).

### 5.2 Class metadata

```
CLASS PDPseudo   super_class=IODevice  instance_size=264  ivars=0
                 protocols -> {next 0, count 1, [PortDevices]}
                 15 methods: 2 class (+deviceStyle 4324, +probe: 4336),
                             13 instance (4400 … 4680)

CLASS PortServer super_class=IODevice  instance_size=616
                 ivar  state  {ttyiops_state=…}  offset=264 (0x108)
                 9 methods: 4 class (+serverMajor: 4692, +deviceStyle 4928,
                            +requiredProtocols 4940, +probe: 4952),
                            5 instance (5128 … 6096)

CATEGORY IOPortSessionKern (IOPortSession)
                 10 CLASS methods  (6576 … 8432)
                 4 instance methods (8512 … 8704)
```

`PortServer`'s single ivar decodes the three magic offsets our source hard-codes:

| our literal | ivar-relative | field of `ttyiops_state` |
|---|---|---|
| `self + 0x108` | `&self->state` | the whole struct |
| `self + 0x1f0` | `state + 0xE8` | `iops` (`@"IOPortSession"`) |
| `self + 0x264` | `state + 0x15C` | the `b1` bitfield byte (`is_post_loaded` …) |

### 5.3 `+[IOPortSession iopsKernMsgIoctl:data:]` jump table

`jpt_1D46` sits at 7504, immediately after the `jmp ds:jpt_1D46[eax*4]` at 7494 and
immediately before the first case body at 7560. All fourteen entries were read as
little-endian `uint32` and every target verified to be both a real instruction and a
basic-block start. `7504 + 14*4 = 7560`, which is exactly the first case block, so the
table is complete and there is no fifteenth case hidden in padding:

| op | target | op | target | op | target |
|---|---|---|---|---|---|
| 2 | 7560 | 7 | 7652 | 12 | 7764 |
| 3 | 7584 | 8 | 7676 | 13 | 7788 |
| 4 | 7600 | 9 | 7692 | 14 | 7820 |
| 5 | 7628 | 10 | 7716 | 15 | 7864 |
| 6 | 7636 | 11 | 7732 | | |

The dispatch is `eax = *(int *)data - 2; if (eax > 0x0D) goto default` — so the covered
range is exactly 2…15 and the default returns 0x16. **Our `switch` covers exactly
2…15 with the same default.** That part matches.

### 5.4 `_ttyiops_devsw` (32768-relative, at 33072)

Read with its relocations, this is a full `cdevsw`:

```
+0x00 d_open   _ttyiops_open      +0x1C  0
+0x04 d_close  _ttyiops_close     +0x20 d_select    _ttyiops_select
+0x08 d_read   _ttyiops_read      +0x24 d_mmap      _enodev
+0x0C d_write  _ttyiops_write     +0x28 d_strategy  _enodev_strat
+0x10 d_ioctl  _ttyiops_ioctl     +0x2C d_getc      _enodev
+0x14 d_stop   _ttyiops_stop      +0x30 d_putc      _enodev
+0x18 d_reset  _nulldev           +0x34 d_type      3
```

`+[PortServer serverMajor:]` pushes **fields of this struct** for eight of the eleven
function-pointer arguments and skips `+0x28` (`d_strategy`), which
`addToCdevswFromDescription:…` does not take. That is what settles Finding 36.

### 5.5 `__bss` / `__data` layout for the globals in scope

```
__data 32768 local _PseudoDeviceLoaded   (1 byte, 0)
__data 32772 local _portServerMajor      (4 bytes, 0)
__data 32776 local _ttyiopsMap           (104 bytes = 26 * 4)
__data 32880 local _protocols.102        ({ @protocol(PortDevices), 0 })
__data 33072 local _ttyiops_devsw
__bss  33172 local _pseudoUnit
__bss  33176 local _ttyiopsMapLock
__bss  33180 local _mapLock
__bss  33184 local _numSessions
__bss  33188 local _nsPortKernIdMap      (512 bytes, runs to end of __bss at 33700)
```

Every one of these is `local` (i.e. `static`). The binary does carry `global` data
symbols elsewhere (`_ttyiops_speeds`, `_PortServer_instance`), so `local` here is a real
source-level `static`, not a `kl_ld` artifact. See Finding 45.

---

### From pass 3

### 5.6 `_dtrDownDelay` — `__TEXT,__const`, 16604, 8 bytes

File image (offset 19000): `02 00 00 00 00 00 00 00`.

```c
static const struct timeval dtrDownDelay = { 2, 0 };   /* 2 s, 0 µs */
```

It is a `struct timeval`, not a scalar. There is exactly one reference, in
`_ttyiops_init`, and it is used as a two-word timeval addend:

```
 12662: 8B934C010000    mov  edx, [ebx+14Ch]          ; target.tv_sec  = tp->dtrDownTime.tv_sec
 12668: 8955F8          mov  [ebp+var_8], edx
 12671: 8B9350010000    mov  edx, [ebx+150h]          ; target.tv_usec = tp->dtrDownTime.tv_usec
 12677: 8955FC          mov  [ebp+var_4], edx
 12680: 8B0DDC400000    mov  ecx, ds:_dtrDownDelay    ; += dtrDownDelay.tv_sec
 12686: 014DF8          add  [ebp+var_8], ecx
 12689: 8B1DE0400000    mov  ebx, ds:dword_40E0       ; += dtrDownDelay.tv_usec
 12695: 015DFC          add  [ebp+var_4], ebx
 12698: 817DFC3F420F00  cmp  [ebp+var_4], 0F423Fh     ; if (usec > 999999) { sec++; usec -= 1000000; }
```

`dword_40E0` is 16608, i.e. `_dtrDownDelay + 4` — the `tv_usec` half. Both halves
are added, then the microsecond field is normalised. Our source hardcodes only
the seconds half (`target_time.tv_sec += 2;` at `ttyiops.m:847`) and does not
carry the constant at all. See F59.

### 5.7 `_ttyiops_devsw` — `__DATA,__data`, 33072, 56 bytes

56 bytes is exactly `sizeof(struct cdevsw)` for this kernel
(`src/kernel-7/bsd/sys/conf.h`, 14 fields × 4). Image bytes and the relocations
against them:

```
33072: b8220000  ->  8888   RELOC _ttyiops_open
33076: 0c250000  ->  9484   RELOC _ttyiops_close
33080: f4260000  ->  9972   RELOC _ttyiops_read
33084: a0270000  -> 10144   RELOC _ttyiops_write
33088: b4290000  -> 10676   RELOC _ttyiops_ioctl
33092: 9c2c0000  -> 11420   RELOC _ttyiops_stop
33096: 00000000  ->         RELOC _nulldev        (UNDEF 41292)
33100: 00000000  ->         (no relocation — literal NULL)
33104: 0c280000  -> 10252   RELOC _ttyiops_select
33108: 00000000  ->         RELOC _enodev         (UNDEF 41272)
33112: 00000000  ->         RELOC _enodev_strat   (UNDEF 41276)
33116: 00000000  ->         RELOC _enodev         (UNDEF 41272)
33120: 00000000  ->         RELOC _enodev         (UNDEF 41272)
33124: 03000000  ->     3   (no relocation — literal)
```

Slot by slot, against `struct cdevsw`:

| # | Offset | Field | Value |
|---|---|---|---|
| 0 | 33072 | `d_open` | `ttyiops_open` |
| 1 | 33076 | `d_close` | `ttyiops_close` |
| 2 | 33080 | `d_read` | `ttyiops_read` |
| 3 | 33084 | `d_write` | `ttyiops_write` |
| 4 | 33088 | `d_ioctl` | `ttyiops_ioctl` |
| 5 | 33092 | `d_stop` | `ttyiops_stop` |
| 6 | 33096 | `d_reset` | `nulldev` |
| 7 | 33100 | `d_ttys` | `0` |
| 8 | 33104 | `d_select` | `ttyiops_select` |
| 9 | 33108 | `d_mmap` | `enodev` |
| 10 | 33112 | `d_strategy` | `enodev_strat` |
| 11 | 33116 | `d_getc` | `enodev` |
| 12 | 33120 | `d_putc` | `enodev` |
| 13 | 33124 | `d_type` | `3` = `D_TTY` (`conf.h:119`) |

Written out, the definition our source is missing entirely:

```c
static struct cdevsw ttyiops_devsw = {
    ttyiops_open,   ttyiops_close,  ttyiops_read,   ttyiops_write,
    ttyiops_ioctl,  ttyiops_stop,   nulldev,        0,
    ttyiops_select, enodev,         enodev_strat,   enodev,
    enodev,         D_TTY
};
```

Its single consumer is `_portServeropen` (reference address 6149) — that lives in
`PortServer.m`, part 2's scope, so only the definition belongs here. It must be
file-scope in `ttyiops.m` and non-`static` enough to be visible there, or moved,
whichever part 2 recorded.

`_ttyiops_devsw` is `local` in the symbol table, so it was `static` in Apple's
source, and `_portServeropen` therefore also lived in `ttyiops.m` in Apple's tree
— consistent with our `portServeropen`/`portServerclose`/`portServerioctl`
wrappers already sitting at `ttyiops.m:2185–2206`.

---

### `_ttyiops_waitForDCD` behaviour

The `TODO: Implement DCD waiting logic` marker at `ttyiops.m:1786` is on a
**second, redundant** definition. There are two definitions of
`ttyiops_waitForDCD` in the file — `ttyiops.m:1099` (a complete body) and
`ttyiops.m:1784` (the stub). This is the third entry in `source-map.json`'s
`duplicate_candidates` (`{"address": 12880, "reasons": ["symbol name resolves to
multiple definitions"]}`); the other two are `-[AppleIOPSSafeCondLock
setCondition:]` and `-[... unlockWith:]`, both part 1's scope.

**The body at `ttyiops.m:1099` is the real one and it is already correct.** The
stub at `:1784` is the duplicate and is also where one of the two unclosed braces
lives (§5). Complete removal of lines 1780–1794 is the whole fix; nothing needs
to be written from scratch.

The reference, read instruction by instruction:

```
 12888: 8B5D08          mov  ebx, [ebp+arg_0]              ; tp
 12893: F6450C04        test [ebp+arg_4], 4                ; flag & 0x04
 12897: 756D            jnz  13008                         ;   -> acquire and return 0
 12899: F6436808        test byte ptr [ebx+68h], 8         ; t_state & 0x08 (carrier on)
 12903: 7567            jnz  13008
 12905: 6683BB94000000 00  cmp word ptr [ebx+94h], 0       ; (short)t_cflag  (bit 15 = CLOCAL)
 12913: 7C5D            jl   13008                         ;   CLOCAL set -> don't wait
 12915: C745FC40000000  mov  [ebp+var_4], 40h              ; watch value = 0x40
 12922: 6A40            push 40h                           ; mask         = 0x40
 12924: 8D45FC          lea  eax, [ebp+var_4]
 12927: 50              push eax
 12928: 8B0DDC620000    mov  ecx, ds:paWatchstateMask      ; @selector(watchState:mask:)
 12934: 51              push ecx
 12935: 8B8BE8000000    mov  ecx, [ebx+0E8h]               ; tp->portSession
 12941: 51              push ecx
 12942: E86DCDFFFF      call _objc_msgSend
 12950: 3D33FDFFFF      cmp  eax, 0FFFFFD33h               ; -0x2CD
 12955: 7407            jz   12964
 12957: 3D41FDFFFF      cmp  eax, 0FFFFFD41h               ; -0x2BF
 12962: 7518            jnz  12988                         ; success -> l_modem
 12964: BA10000000      mov  edx, 10h                      ; EBUSY
 12969: 3D41FDFFFF      cmp  eax, 0FFFFFD41h
 12974: 7505            jnz  12981
 12976: BA04000000      mov  edx, 4                        ; EINTR
 12981: 89D0            mov  eax, edx
 12983: EB2E            jmp  13031                         ; return without acquiring
 12988: 8B4660          mov  eax, [esi+60h]                ; t_line
 12991: C1E005          shl  eax, 5                        ; * sizeof(struct linesw)
 12994: 6A01            push 1
 12996: 56              push esi                           ; tp
 12997: 8B801C000000    mov  eax, ds:_linesw[eax]          ; +0x1C == l_modem
 13003: FFD0            call eax                           ; (*l_modem)(tp, 1)
 13008: 6A00            push 0
 13010: 8B0D10630000    mov  ecx, ds:paAcquire             ; @selector(acquire:)
 13016: 51              push ecx
 13017: 8B9BE8000000    mov  ebx, [ebx+0E8h]
 13023: 53              push ebx
 13024: E81BCDFFFF      call _objc_msgSend                 ; [session acquire:0]
 13029: 31C0            xor  eax, eax                      ; return 0
```

In C:

```c
int ttyiops_waitForDCD(struct tty *tp, int flag)
{
    int r;
    unsigned int watch;

    if ((flag & 0x04) == 0 &&
        (((unsigned char *)tp)[0x68] & 0x08) == 0 &&
        ((short *)tp)[0x94/2] >= 0) {              /* CLOCAL clear */
        watch = 0x40;                              /* PD_RS232_S_CAR */
        r = (int)objc_msgSend(((id *)tp)[0xE8/4],
                              @selector(watchState:mask:), &watch, 0x40);
        if (r == -0x2CD) return 0x10;              /* EBUSY, no acquire  */
        if (r == -0x2BF) return 4;                 /* EINTR, no acquire  */
        (*linesw[tp->t_line].l_modem)(tp, 1);
    }
    objc_msgSend(((id *)tp)[0xE8/4], @selector(acquire:), 0);
    return 0;
}
```

Points a later fix pass must not lose:

- All three early-out conditions (`flag & 4`, `t_state & 8`, CLOCAL) skip straight
  to the `[session acquire:0]` at 13008 and return 0. They do **not** skip the
  acquire.
- Both error returns skip the acquire entirely.
- `l_modem` is called unconditionally on success, with no NULL guard, and only on
  the path that actually waited.
- `((short *)tp)[0x94/2]`, not `[0x94/4]` — the `jl` at 12913 is a signed 16-bit
  test of the halfword at byte offset 0x94, i.e. `CLOCAL` = bit 15 of `t_cflag`.
- `-0x2CD` maps to `EBUSY` (0x10) and `-0x2BF` to `EINTR` (4). Note the compiler
  emitted a redundant re-test of `-0x2BF` at 12969; the mapping is unambiguous.

Our `ttyiops.m:1099` body matches all of this instruction for instruction. The
only correction it needs is deletion of its duplicate.

---

## 6. The two NUL sites in `-[PortServer initFromDeviceDescription:]`

`file(1)` reports `PortServer.m` as `data`, and a byte scan finds **exactly two** `0x00`
bytes in the file, at offsets **5972** and **6685**, on lines **192** and **224**. Both
are inside `-[PortServer initFromDeviceDescription:]`. Both are single NUL bytes sitting
between two single-quotes where the two-character escape `\0` was intended. No other
file in `PortServer.lksproj` contains a NUL byte.

**Both are genuinely NUL handling.** Here is the evidence for each, from the reference
function at 5128 read in full.

### Site 1 — offset 5972, line 192: `*device_name == '\0'`

Our source, with the raw byte shown as `\0`:

```c
    direct_device = objc_msgSend(deviceDescription, @selector(directDevice));
    device_name = (const char *)objc_msgSend(direct_device, @selector(name));

    /* Check if device name exists and is not empty */
    if (device_name == NULL || *device_name == '\0') {   /* line 192, byte 5972 */
        goto init_failed;
    }
```

Reference, the two tests immediately after the `name` send:

```
5169: 8945A0      mov  [ebp+__s2], eax          ; device_name = [directDevice name]
5175: 85C0        test eax, eax
5177: 0F8479010000 jz  loc_15B8                 ; -> [self free]
5183: 803800      cmp  byte ptr [eax], 0        ; *device_name == '\0'
5186: 0F8470010000 jz  loc_15B8                 ; -> [self free]
```

`cmp byte ptr [eax], 0` is an unambiguous "first character is NUL" test, it is a *byte*
compare (not `cmp dword`), and it is the second half of a short-circuited `||` whose
first half is the null-pointer test at 5175. There is no other reading. **This is
`*device_name == '\0'` and nothing else** — it is not a space test, not a `< ' '` test,
and not a compare against any character constant other than zero.

### Site 2 — offset 6685, line 224: `name_buffer[7] = '\0'`

Our source:

```c
        name_buffer[0] = 'p';   name_buffer[4] = 'r';
        name_buffer[1] = 'd';   name_buffer[5] = 'v';
        name_buffer[2] = 's';   name_buffer[6] = 'd';
        name_buffer[3] = 'e';   name_buffer[7] = '\0';   /* line 224, byte 6685 */
```

Reference, in the `PDPseudo` branch:

```
5233: BBC0000000   mov  ebx, 0C0h                     ; unit = 0xC0
5238: 8B156B3F0000 mov  edx, dword ptr ds:aPdservd    ; "pdservd" at 16235
5244: 8955B0       mov  [ebp+var_50], edx             ; name_buffer[0..3]
5247: 8B156F3F0000 mov  edx, dword ptr ds:aPdservd+4
5253: 8955B4       mov  [ebp+var_4C], edx             ; name_buffer[4..7]
```

`__cstring` at 16235 holds `pdservd` — seven characters, so the eighth byte of the
literal, at 16242, is its terminating NUL. The reference copies **eight** bytes as two
32-bit moves, and the eighth byte it copies is that NUL. `var_50` is the same 8-byte
stack slot the later `sprintf(name_buffer, "ttyd%c", …)` at 5378 writes and that
`[self setName:name_buffer]` at 5476 passes, so it is our `char name_buffer[8]`.

**So site 2 is a NUL terminator, byte 7 of an 8-byte name buffer.** It is not a space
and not padding. It is written by the string literal rather than by an explicit
assignment — the reference source says `strcpy(name_buffer, "pdservd")` (gcc expands the
constant 8-byte copy inline; `_strcpy` is imported but the only two call sites in the
whole binary are 6466 in `_portServerioctl` and 7410 in `+iopsKernInitIoctl:data:`) —
but the byte it stores at index 7 is exactly the `'\0'` our line 224 writes.

**Confirmation for Task 7: both sites are NUL handling.** Replacing each raw `0x00`
byte with the two characters `\` `0` restores valid ASCII source and changes no
semantics. Two further defects live in the same file and should be fixed in the same
pass because they are the same class of corruption — see Finding 46 (`PortServer.m:101`)
and Finding 54 (`IOPortSessionKern.m:472`), both of which are raw newlines inside string
literals and are hard compile errors.

---

## 7. The ten method-kind mismatches

**Confirmed exactly as the brief describes, with no exceptions in either direction.**

The reference does not put these methods on the `IOPortSession` class at all — it puts
them in a **category**. `__OBJC,__category` holds two entries, and the second is:

```
CATEGORY IOPortSessionKern (IOPortSession)
  class_methods    -> __cat_cls_meth,  10 entries
  instance_methods -> __cat_inst_meth,  4 entries
```

Our `@implementation IOPortSession (IOPortSessionKern)` at `IOPortSessionKern.m:29` is
therefore **correct** — the category name and the class it extends both match. Only the
`+`/`-` marker on ten of the fourteen methods is wrong.

### 7.1 The split, method by method

Read straight out of `__cat_cls_meth` / `__cat_inst_meth`:

| addr | kind in reference | `__meth_var_types` | our declaration |
|---|---|---|---|
| 6576 | **`+`** `iopsKernInit:` | `v12@8:12@16` | `-` `IOPortSessionKern.m:460` |
| 6792 | **`+`** `iopsKernFree` | `@8@8:12` | `-` `:422` |
| 6900 | **`+`** `iopsKernNumSess` | `i8@8:12` | `-` `:752` |
| 6912 | **`+`** `iopsServerIoctlCommand:data:` | `i16@8:12i16*20` | `-` `:776` |
| 7232 | **`+`** `iopsKernOpen:` | `i12@8:12i16` | `-` `:757` |
| 7312 | **`+`** `iopsKernInitIoctl:data:` | `i16@8:12i16*20` | `-` `:529` |
| 7440 | **`+`** `iopsKernMsgIoctl:data:` | `i16@8:12i16*20` | `-` `:583` |
| 7948 | **`+`** `iopsKernEnqueue:msg:` | `i16@8:12@16^{?=ii*III}20` | `-` `:317` |
| 8180 | **`+`** `iopsKernDequeue:msg:` | `i16@8:12@16^{?=ii*III}20` | `-` `:207` |
| 8432 | **`+`** `iopsKernClose:` | `i12@8:12i16` | `-` `:159` |
| 8512 | `-` `getIntValues:forParameter:count:` | `i20@8:12^I16*20^I24` | `-` `:68` ✓ kind |
| 8576 | `-` `getCharValues:forParameter:count:` | `i20@8:12*16*20^I24` | `-` `:40` ✓ kind |
| 8640 | `-` `setIntValues:forParameter:count:` | `i20@8:12^I16*20I24` | `-` `:125` ✓ kind |
| 8704 | `-` `setCharValues:forParameter:count:` | `i20@8:12*16*20I24` | `-` `:96` ✓ kind |

Ten `+`, four `-`. The four accessors are `-` in both. Nothing else in this category is
`+` in one and `-` in the other.

### 7.2 What each of the ten does with `self`, and why that is observable

A class method receives the **metaclass** in `self`, so any of these ten that
dereferenced `self` as an object with ivars would crash. **None of them does.** That is
the disassembly-level confirmation the brief asks for:

| addr | what it does with `self` (`[ebp+arg_0]`) | evidence |
|---|---|---|
| 6576 `iopsKernInit:` | **never loads it** | `[ebp+arg_0]` is not referenced anywhere in 6576–6788; every operand is `[ebp+arg_8]` (the argument) or a file-static |
| 6792 `iopsKernFree` | loads it at 6797 and **passes it straight back as a receiver** to `objc_msgSend` at 6821 for `iopsKernClose:` — i.e. `[self iopsKernClose:i]` where `self` is the class. Never dereferenced. |
| 6900 `iopsKernNumSess` | **never loads it**; the body is `mov eax, ds:_numSessions` |
| 6912 `iopsServerIoctlCommand:data:` | **never loads it**; works entirely off `_mapLock`, `_numSessions`, `_nsPortKernIdMap` and the two arguments |
| 7232 `iopsKernOpen:` | **never loads it**; `alloc` goes to the `IOPortSession` **class ref** at 7283, not to `self` |
| 7312 `iopsKernInitIoctl:data:` | **never loads it** |
| 7440 `iopsKernMsgIoctl:data:` | **never loads it**; the two recursive sends at 7828/7872 use the `IOPortSession` class ref at 7879, not `self` |
| 7948 `iopsKernEnqueue:msg:` | **never loads it** |
| 8180 `iopsKernDequeue:msg:` | **never loads it** |
| 8432 `iopsKernClose:` | **never loads it** |

Contrast the four that really are instance methods: all four open with
`mov eax,[ebp+self]` / `cmp dword ptr [eax+4],0` — a load of `IOPortSession`'s single
ivar `_priv` at offset 4 (part 1, Finding 15). That is the layout dependency the brief
asked me to watch for, and it is the *only* one in my scope: 8512, 8576, 8640 and 8704
each do `self->_priv`, then `*(id *)_priv`, then forward. Nothing in `PDPseudo.m`,
`PortServer.m` or the ten class methods touches `_priv`.

So the split is not a naming accident. Nine of the ten never touch the receiver at all,
and the tenth uses it only as a message target. They are static, file-scope operations
over three file-static globals, and Apple wrote them as class methods for exactly that
reason.

### 7.3 Every call site that must change

**Declarations (20 sites).** Ten in the header, ten in the implementation:

```
IOPortSessionKern.h:66   - (int)iopsKernClose:(int)sessionId;
IOPortSessionKern.h:81   - (int)iopsKernDequeue:(id)session msg:(void *)msg;
IOPortSessionKern.h:96   - (int)iopsKernEnqueue:(id)session msg:(void *)msg;
IOPortSessionKern.h:104  - (id)iopsKernFree;
IOPortSessionKern.h:112  - (void)iopsKernInit:(id)deviceDescription;
IOPortSessionKern.h:124  - (int)iopsKernInitIoctl:(int)sessionId data:(char *)data;
IOPortSessionKern.h:133  - (int)iopsKernMsgIoctl:(int)sessionId data:(char *)data;
IOPortSessionKern.h:138  - (int)iopsKernNumSess;
IOPortSessionKern.h:144  - (int)iopsKernOpen:(int)sessionId;
IOPortSessionKern.h:155  - (int)iopsServerIoctlCommand:(int)command data:(char *)data;

IOPortSessionKern.m:159  - (int)iopsKernClose:(int)sessionId
IOPortSessionKern.m:207  - (int)iopsKernDequeue:(id)session msg:(void *)msg
IOPortSessionKern.m:317  - (int)iopsKernEnqueue:(id)session msg:(void *)msg
IOPortSessionKern.m:422  - (id)iopsKernFree
IOPortSessionKern.m:460  - (void)iopsKernInit:(id)deviceDescription
IOPortSessionKern.m:529  - (int)iopsKernInitIoctl:(int)sessionId data:(char *)data
IOPortSessionKern.m:583  - (int)iopsKernMsgIoctl:(int)sessionId data:(char *)data
IOPortSessionKern.m:752  - (int)iopsKernNumSess
IOPortSessionKern.m:757  - (int)iopsKernOpen:(int)sessionId
IOPortSessionKern.m:776  - (int)iopsServerIoctlCommand:(int)command data:(char *)data
```

**Existing send sites (5).** I grepped every `.h` and `.m` in `PortServer.lksproj` and
`pdservd.tproj` for all ten selectors. These are all of them:

| site | current text | after the fix |
|---|---|---|
| `PortServer.m:134-136` | `objc_msgSend(objc_getClass("IOPortSession"), @selector(iopsKernInit:), deviceDescription)` | `[IOPortSession iopsKernInit:deviceDescription]` |
| `PortServer.m:448-449` | `objc_msgSend(objc_getClass("IOPortSession"), @selector(iopsKernNumSess))` | `[IOPortSession iopsKernNumSess]` |
| `IOPortSessionKern.m:431` | `objc_msgSend(self, @selector(iopsKernClose:), sessionIndex)` | `[self iopsKernClose:sessionIndex]` — correct **only once `iopsKernFree` is itself `+`**, since `self` must be the class |
| `IOPortSessionKern.m:707-710` | `objc_msgSend(objc_getClass("IOPortSession"), @selector(iopsKernEnqueue:msg:), sessionObject, data)` | `[IOPortSession iopsKernEnqueue:sessionObject msg:data]` |
| `IOPortSessionKern.m:727-730` | `objc_msgSend(objc_getClass("IOPortSession"), @selector(iopsKernDequeue:msg:), sessionObject, data)` | `[IOPortSession iopsKernDequeue:sessionObject msg:data]` |

Note the first two and the last two are **already class-directed sends**. They are
broken *today*: `objc_getClass("IOPortSession")` returns the class object, and a class
object does not respond to an instance-method selector, so all four raise
`does not recognize selector` at runtime. That is the observable consequence of the
mismatch, and it is why this finding is the largest in the file.

**Sites that do not yet exist but will (5).** The reference calls five of the ten from
the three C entry points, which our tree does not implement (Finding 42). Task 8 will
create these:

| reference site | send |
|---|---|
| `_portServeropen` 6179-6186 | `[IOPortSession iopsKernOpen:(dev & 0x3F)]` |
| `_portServerclose` 6279-6286 | `[IOPortSession iopsKernClose:(dev & 0x3F)]` |
| `_portServerioctl` 6486/6532-6540 | `[IOPortSession iopsServerIoctlCommand:cmd data:data]` |
| `_portServerioctl` 6506/6532-6540 | `[IOPortSession iopsKernInitIoctl:(dev & 0x3F) data:data]` |
| `_portServerioctl` 6526/6532-6540 | `[IOPortSession iopsKernMsgIoctl:(dev & 0x3F) data:data]` |

`+iopsKernFree` has **no** call site anywhere in the reference binary; it is exported for
the unload path and nothing in this driver invokes it.

---

## 8. Config table and localizable strings

Compared against the shipped `PortServer.config`:

| File | Reference | Ours | Disposition |
|---|---|---|---|
| `Default.table` | `"Version" = "5.00";` | absent | fix |
| `Default.table` | `"Support Dialin"` | `"Support DialIn"` | fix |
| `Default.table` | `"Help File" = "PortServer_Main.rtfd";` | `"...rtf"` | fix |
| `Default.table` | three trailing comments read `ttyd*` / `cu*`, aligned | `ttyof..` / `cuA`, misaligned | fix |
| `Default.table` | `"Driver Version" = "PROGRAM:PortServer  PROJECT:drvPortServer-14 ..."` | absent | **accept** -- build-generated, records Apple's 1998 build host |
| `Localizable.strings` line 1 | `"PortServer" = "Port Server";` | `"Port Server" = "Port Server";` | fix |

The `Localizable.strings` key is the lookup key, so ours resolves nothing.

`English.lproj/DriverHelp/` contains only `TableOfContents.rtf`. The `PortServer_Main.rtfd`
bundle that the `Help File` key names is **absent from our tree**. The `DriverHelp` to
`Help` directory rename between source and built bundle is a `pb_makefiles` convention, not
a divergence.

**`Support Dialin` -- do not overclaim.** The table divergence is real and worth correcting
for parity with what Apple shipped. But the string `Support Dialin` occurs in **no file
under `src/`** and in **none of the three shipped binaries** (`PortServer_reloc`,
`PortServer`, `pdservd`). Whatever consumes the key does so from outside this driver,
presumably the DriverKit configuration layer. **No behavioural consequence is demonstrated,
and none is claimed here.**

## 9. Corrections to the task brief

Recorded because the brief's assumptions were checked against the binary rather than trusted:

- The twelve `PDPseudo` methods from 4548 are **not** forwarding stubs -- they contain no call
  and no selector. Two of them are 9 bytes returning 0, not 12 bytes returning -702.
- `_tiotors232` (14216) and `_rs232totio` (14232) are **not** table lookups. They are a plain
  mask operation, and our source is already correct.
- `_ttyiops_speeds` is at **32888**, not 33144, and it **precedes** `_ttyiops_devsw`. It is a
  `struct speedtab[23]` of speed pairs, not the flat `int[24]` our source has.

## 10. README status

`src/drivers-i386/README` does not list this driver at all, and `drvPortServer` does not live
under `src/drivers-i386/`. It should gain an entry stating: reconstructed against the
reference binary, five pre-existing compile blockers repaired, divergence fixes applied, not
yet compiled or tested. It cannot claim more than that -- no guest build was in scope.

## 11. Findings

Findings 1-26 come from pass 1, 27-57 from pass 2, and 58-82 from pass 3. Numbering is
continuous and non-overlapping.

### `AppleIOPSSafeCondLock.m`

**Finding 1 — `AppleIOPSSafeCondLock.m` does not compile; two method bodies are
duplicated and the file is textually corrupt.**

This is both `duplicate_candidates` entries in `source-map.json` (addresses 484 and 712),
and it is not a subtle one: the file has an unbalanced brace count of +1 and two hard
syntax errors.

**Our source** — `-setCondition:` opened at `:361` has no closing brace. Line 372 is its
last statement and line 373 immediately opens a comment for the next method:

```c
372     thread_wakeup_prim((char *)self + 8, 1, 0);
373 /*
374  * unlock - Release lock
...
378  */
379 - (void)unlock
```

and after `-unlockWith:` closes at `:486` two orphaned comment-body lines sit outside any
comment:

```c
486 }
487  * This is the typical way to change condition values
488  */
489 - (void)unlockWith:(int)condition
```

So `-setCondition:` is defined at both `:361` and `:506`, and `-unlockWith:` at both
`:434` and `:489`. **The real sites are `:361` and `:434`** — both match the reference
body instruction for instruction (see F7 and F8); the `:489` and `:506` copies are
`TODO`-marked stubs that only store `conditionVar`.

**The concrete difference:** the reference emits one `-setCondition:` (484, 35 bytes) and
one `-unlockWith:` (712, 84 bytes). `__OBJC,__inst_meth` for the class has exactly 12
entries, one per selector, no duplicates.

**Disposition:** fix.

**Rationale:** the file cannot build in its current state, so every other finding in it
is unreachable until this is repaired. Delete `:487-499` and `:501-516` and close
`-setCondition:` at `:372`. This is the same class of tree damage as the NUL bytes in
`PortServer.m` that Task 7 handles.

**Outcome (Task 8):** Repaired ahead of the fix pass. Task 7 (`f230c8ad`) closed `-setCondition:` at
`:372` and deleted the two `TODO` stubs, so the file arrived at Task 8 with brace delta
`+0` and one definition each of `-setCondition:` and `-unlockWith:`. The three
`duplicate_candidates` this finding predicted are gone from the regenerated source map
(3 -> 0). Ledger: 484 and 712 are carried by Findings 7 and 8, both **assembly-matched**.

---

**Finding 2 — the eight IMP cache globals are declared twice; the wrappers read the
uninitialised copy.**

**Our source** — `AppleIOPSSafeCondLock.m:18-25` declares `_IMP_interuptable` …
`_IMP_lockWhen` and `+initialize` (`:41-78`) writes those eight. `:529-536` declares a
second, alphabetised set `IMP_condition` … `IMP_unlockWith`, and all eight
`AIOPSSCL_*` wrappers (`:548`, `:561`, `:573`, `:586`, `:598`, `:609`, `:620`, `:631`)
read *that* set. Nothing assigns it. Every wrapper call is therefore a call through a
NULL function pointer.

**Reference behaviour** — see Section 5: eight globals in `__DATA,__bss` at 33128–33156,
written by `+initialize` and read by the wrappers. Only eight symbols exist in that
address range; there is no second set.

**Disposition:** fix.

**Rationale:** this is the fix-pass decision the brief asked to be settled, and the
answer is unambiguous. Keep one set: the names of `:529-536` (`IMP_*`, since the binary's
`_IMP_*` is the assembler mangling of a C `IMP_*`) in the declaration order of `:18-25`
(interuptable, condition, setCondition, unlock, unlockWith, lock, lockTry, lockWhen,
which is the reference's `__bss` address order), declared once before
`@implementation`. Delete `:529-536` and rewrite `+initialize` and the eight wrappers
against the survivor.

**Outcome (Task 8):** Fixed. The second, uninitialised `IMP_condition` … `IMP_unlockWith` set was deleted
and one set of eight kept, named `IMP_*` in the reference's `__bss` address order, written
by `+initialize` and read by all eight wrappers. This removed a live NULL-function-pointer
call on every wrapper invocation. Ledger: 368, 412, 456, 796, 960 and 1048
**control-flow-confirmed**; 564 and 680 are held at **signature-confirmed** by Finding 9's
weaker evidence. The eight `__bss` slots and their single writer were read from the symbol
table and the wrapper bodies, not printed instruction by instruction.

---

**Finding 3 — `+initialize` caches `@selector(setCondition:)`; the reference caches
`@selector(setCondition)`, without the colon.**

**Reference disassembly** — `+[AppleIOPSSafeCondLock initialize]` at 57, and
`_AIOPSSCL_setCondition` at 459, load the *same* `__message_refs` slot:

```
 57: 8B15A4620000  mov edx, ds:paSetcondition_0   ; __message_refs+12 = 25252
...
459: 8B15A4620000  mov edx, ds:paSetcondition_0   ; __message_refs+12 = 25252
```

and `__message_refs[3]` (25252) points at the `__meth_var_names` string **`"setCondition"`**
— no trailing colon. The binary's only `"setCondition:"` string is the method-name entry
in `__inst_meth`; no `__message_refs` slot refers to it.

**Our source** — `AppleIOPSSafeCondLock.m:51-53`:

```c
_IMP_setCondition = objc_msgSend(self,
                                 @selector(instanceMethodFor:),
                                 @selector(setCondition:));
```

**The concrete difference:** the reference asks the class for the implementation of a
selector the class does not implement, so `instanceMethodFor:` returns the forwarding
IMP rather than the 484 body. Our `AIOPSSCL_setCondition` at `:609` already uses the
colon-less form, so our two sites disagree with each other as well as with the reference.

**Disposition:** fix.

**Rationale:** reconstruct what shipped. This is a real latent bug in Apple's original —
`AIOPSSCL_setCondition` can never reach `-setCondition:` — but nothing in the driver
calls `AIOPSSCL_setCondition` (no relocation targets 456 outside its own definition), so
reproducing it is inert. Leave a comment saying so rather than silently "improving" it.

**Outcome (Task 8):** Fixed: `+initialize` now caches `@selector(setCondition)` without the colon, with a
comment recording that this is Apple's latent bug (the wrapper can never reach
`-setCondition:`) and that it is inert because nothing calls `AIOPSSCL_setCondition`.
Ledger: 0 **control-flow-confirmed**.

---

**Finding 4 — `+initialize` returns `id`, not `void`.**

**Reference** — `__OBJC,__cls_meth` for the metaclass at 25760 lists one method,
`initialize`, `@encode` `@8@8:12`, `imp` 0. The body confirms it:

```
213: 89D8  mov eax, ebx      ; ebx = the class argument
215: 8B5DFC mov ebx, [ebp+var_4]
218: 89EC  mov esp, ebp
220: 5D    pop ebp
221: C3    retn
```

**Our source** — `AppleIOPSSafeCondLock.h:31` and `.m:38` both say `+ (void)initialize`,
and the body falls off the end.

**Disposition:** fix. `+ (id)initialize` … `return self;`. (`IOPortSession`'s
`+initialize` is already `+ (id)` in our header and already returns `self`, and matches.)

**Outcome (Task 8):** Fixed in both `.h` and `.m`; `return self;` added. Ledger: 0
**control-flow-confirmed**.

---

**Finding 5 — the `@interface` declares two ivars where the reference has six, at the
wrong offsets and under the wrong names.**

**Reference** — `__OBJC,__instance_vars` at 30412 and `__class[0]`, read directly out of
the binary; the full table is in §5. `instance_size` is **20**; ivars run
`cond_interlock` (4), `conditionVar` (8), `sleep_interlock` (12), `interuptable` (16),
`want_lock` (17), `waiting` (18).

**Our source** — `AppleIOPSSafeCondLock.h:20-21`:

```c
    int _condition;         /* Current condition value */
    BOOL _interruptible;    /* Whether lock can be interrupted */
```

which puts `_condition` at offset **4** (the reference's `cond_interlock`) and
`_interruptible` at offset **8** (the reference's `conditionVar`), and gives
`instance_size` 12 rather than 20.

**The concrete difference:** every method in the `.m` reaches its state through raw
`*(int *)((char *)self + N)` casts, so the *emitted code* is right by accident, but the
object is 8 bytes shorter than the code writes — `[self+0x10]`, `[self+0x11]` and
`[self+0x12]` all land past the end of the allocation — and the `__instance_vars`
section our build produces bears no resemblance to the reference's.

**Disposition:** fix.

**Rationale:** silent heap corruption on every `AppleIOPSSafeCondLock` allocated, and one
is allocated per port entry (`-[IOPortSession acquirePort:sleep:]` at 3052-3066).
Declare the six real ivars with the reference's names and types and replace the raw
casts; `cond_interlock`/`sleep_interlock` need a `typedef struct { unsigned int locked; }`
to reproduce the `{?="locked"I}` encoding.

**Outcome (Task 8):** Fixed. `cond_interlock` (+4), `conditionVar` (+8), `sleep_interlock` (+12),
`interuptable` (+16), `want_lock` (+17) and `waiting` (+18) are declared, `instance_size`
becomes 20, and every raw `*(int *)((char *)self + N)` cast in the file is replaced by the
named ivar — ending the out-of-bounds writes at `self+0x10/0x11/0x12`. The two interlocks
use a `typedef struct { unsigned int locked; } AIOPSSCLInterlock;` to reproduce the
`{?="locked"I}` encoding; **the typedef name is invented**, since the reference struct is
anonymous. This is `__OBJC` metadata and lies inside no function extent, so it sets no
ledger status of its own.

---

**Finding 6 — the `TODO` at `AppleIOPSSafeCondLock.m:140` describes cleanup the
reference does not do; the body is already correct.**

**Reference disassembly** — `-[AppleIOPSSafeCondLock free]` (520, 41 bytes) in full:

```
520: 55            push ebp
521: 89E5          mov  ebp, esp
523: 83EC08        sub  esp, 8
526: 8B15C4620000  mov  edx, ds:paFree              ; @selector(free)
532: 52            push edx
533: 8B5508        mov  edx, [ebp+self]
536: 8955F8        mov  [ebp+var_8.receiver], edx
539: 8B15B4630000  mov  edx, ds:stru_63B0.super_class
545: 8955FC        mov  [ebp+var_8.super_class], edx
548: 8D45F8        lea  eax, [ebp+var_8]
551: 50            push eax
552: E8D3FDFFFF    call _objc_msgSendSuper
557: 89EC          mov  esp, ebp
559: 5D            pop  ebp
560: C3            retn
```

That is the whole method: `return [super free];`. There is no lock release, no wakeup,
no free of any lock structure. `_thread_wakeup_prim` is not called; the only calls in the
function are the one `objc_msgSendSuper`.

**Our source** — `AppleIOPSSafeCondLock.m:138-147` already does exactly this, but carries
a `TODO` claiming otherwise:

```c
138 - free
139 {
140     /* TODO: Cleanup synchronization primitives:
141      * - Ensure lock is not held
142      * - Wake any waiting threads
143      * - Free lock structures
144      */
145
146     return [super free];
147 }
```

**Disposition:** fix (comment only).

**Rationale:** the body is byte-for-byte right; the comment is the divergence and it will
mislead the next reader into "completing" a method that is already complete. Delete
`:140-144`. This is a comment-accuracy fix, not a code change, and the function should be
recorded as matching.

**Outcome (Task 8):** Fixed (comment-only): the four `TODO` lines are gone and the body is
`return [super free];`. Ledger: 520 was already **assembly-matched** and stays there.

---

**Finding 7 — `-setCondition:` returns `self` and wakes one waiter; the `:506` stub does
neither.**

**Reference disassembly** — `-[AppleIOPSSafeCondLock setCondition:]` (484, 35) in full:

```
484: 55            push ebp
485: 89E5          mov  ebp, esp
487: 53            push ebx
488: 8B5D08        mov  ebx, [ebp+self]
491: 8B4510        mov  eax, [ebp+arg_8]      ; condition
494: 894308        mov  [ebx+8], eax          ; conditionVar = condition
497: 6A00          push 0                     ; result   = 0
499: 6A01          push 1                     ; one_thread = 1
501: 8D4308        lea  eax, [ebx+8]          ; event    = &conditionVar
504: 50            push eax
505: E802FEFFFF    call _thread_wakeup_prim
510: 89D8          mov  eax, ebx              ; return self
512: 8B5DFC        mov  ebx, [ebp+var_4]
515: 89EC          mov  esp, ebp
517: 5D            pop  ebp
518: C3            retn
```

`@encode` `@12@8:12i16` — returns `id`, takes one `int`.

**Our source** — `:361-372` (the real site) has the identical body but is declared
`- (void)setCondition:(int)condition` and drops the return; `:506-516` is a stub whose
`TODO` at `:508` lists broadcast/wake behaviour that is in fact `thread_wakeup_prim(…, 1,
0)`, i.e. wake *one* thread.

**Disposition:** fix.

**Rationale:** delete the `:501-516` copy, declare the survivor `- setCondition:(int)condition`
returning `id`, and `return self;`. The behaviour the brief asked me to record precisely
enough to write from these notes alone is: *store the argument into `conditionVar` (offset
8), then `thread_wakeup_prim(&self->conditionVar, 1, 0)`, then return `self`.* Note it
takes no interlock — the caller is expected to hold the lock.

**Outcome (Task 8):** Fixed: `- setCondition:(int)` stores `conditionVar`, calls
`thread_wakeup_prim(&conditionVar, 1, 0)` and returns `self`; no interlock is taken.
Ledger: 484 **assembly-matched** — all 35 bytes of the reference body are printed above and
the repaired source reproduces them statement for statement.

---

**Finding 8 — `-unlockWith:` takes both interlocks, stores, releases both, then calls
`AIOPSSCL_unlock` directly; the `:489` stub does only the store.**

**Reference disassembly** — `-[AppleIOPSSafeCondLock unlockWith:]` (712, 84) in full:

```
712: 55            push ebp
713: 89E5          mov  ebp, esp
715: 53            push ebx
716: 8B4D08        mov  ecx, [ebp+self]
719: 8D510C        lea  edx, [ecx+0Ch]        ; &sleep_interlock
722: 90 90         nop nop
724: 833A00        cmp  dword ptr [edx], 0     ; spin while held
727: 75FB          jnz  724
729: B801000000    mov  eax, 1
734: 8702          xchg eax, [edx]             ; test-and-set
736: 83F001        xor  eax, 1
739: 85C0          test eax, eax
741: 74ED          jz   724
743: 8D5104        lea  edx, [ecx+4]          ; &cond_interlock — same sequence
746: 90 90 / 748: 833A00 / 751: 75FB / 753: B801000000 / 758: 8702 / 760: 83F001
763: 85C0 / 765: 74ED
767: 8B5D10        mov  ebx, [ebp+arg_8]
770: 895908        mov  [ecx+8], ebx           ; conditionVar = condition
773: 31C0          xor  eax, eax
775: 874104        xchg eax, [ecx+4]           ; release cond_interlock
778: 31C0          xor  eax, eax
780: 87410C        xchg eax, [ecx+0Ch]         ; release sleep_interlock
783: 51            push ecx
784: E81FFFFFFF    call _AIOPSSCL_unlock        ; direct C call to 564, NOT a msgSend
789: 8B5DFC        mov  ebx, [ebp+var_4]
792: 89EC          mov  esp, ebp
794: 5D            pop  ebp
795: C3            retn                         ; returns AIOPSSCL_unlock's eax = self
```

`@encode` `@12@8:12i16` — returns `id`.

**Our source** — `:434-486` (the real site) matches this exactly, including the direct
`AIOPSSCL_unlock(self)` call at `:483`; it is declared `- (void)`. `:489-499` is a stub
whose `TODO` at `:491` lists behaviour ("broadcast to all waiting threads") that the
reference does not perform here — the wakeup happens inside `-unlock`, on
`&conditionVar` with `one_thread = 1` and on `self` with `one_thread = 0`.

**Disposition:** fix.

**Rationale:** delete the `:487-499` copy; declare the survivor returning `id` and
`return (id)AIOPSSCL_unlock(self);` (which requires F9's prototype change). Behaviour to
write from these notes: *acquire `sleep_interlock` (offset 12) by test-and-set spin,
acquire `cond_interlock` (offset 4) the same way, store the argument into `conditionVar`
(offset 8), release `cond_interlock`, release `sleep_interlock`, tail-call
`AIOPSSCL_unlock(self)` and return its result.*

**Outcome (Task 8):** Fixed: `- unlockWith:(int)` ends `return AIOPSSCL_unlock(self);`. Ledger: 712
**assembly-matched** — all 84 bytes are printed above, including both test-and-set spins,
the `conditionVar` store, both releases and the direct `call _AIOPSSCL_unlock`.

---

**Finding 9 — `-unlock` returns `id`, and so do `AIOPSSCL_unlock` and
`AIOPSSCL_unlockWith`.**

Detailed evidence in Section 5. The body otherwise matches ours instruction for instruction:
acquire `sleep_interlock`, `thread_wakeup_prim(&conditionVar, 1, 0)`, clear `want_lock`
(offset 17), and if `waiting` (offset 18) is set, clear it and `thread_wakeup_prim(self,
0, 0)`, then release `sleep_interlock`.

**Our source** — `.h:69` / `.m:379` `- (void)unlock`; `.h:126` / `.m:617`
`void AIOPSSCL_unlock(id lock)`; `.h:132` / `.m:628` `void AIOPSSCL_unlockWith(id, int)`.

**Disposition:** fix. `- unlock` returning `id`, `id AIOPSSCL_unlock(id)`,
`id AIOPSSCL_unlockWith(id, int)`.

**Outcome (Task 8):** Fixed in source — `-unlock`, `AIOPSSCL_unlock` and `AIOPSSCL_unlockWith` all
return `id` — but **the evidence for it is a dangling cross-reference**. This finding defers
to "Section 5", and Section 5 carries no `-unlock` disassembly; the change rests on the
`@encode` string `@8@8:12` and on Finding 8's printed `retn` comment at 795, not on any
instruction stream quoted in this document. The ledger records that honestly: 564, 592 and
680 are **signature-confirmed**, not `control-flow-confirmed`, because a type string is
signature evidence and nothing more. 592–678 should be re-read with the binary open.

---

**Finding 10 — `-lock` returns `int`, and `AIOPSSCL_lock` returns it; our own source
already depends on this and cannot compile without it.**

**Reference** — `@encode` `lock i8@8:12`. The `int` accumulator lives in `ecx` and is the
return value:

```
832: 31C9          xor  ecx, ecx              ; result = 0
...
915: E868FCFFFF    call _thread_wait_result
920: 89C1          mov  ecx, eax              ; result = thread_wait_result()
922: 8A4611        mov  al, [esi+11h]         ; want_lock
925: 84C0          test al, al
927: 7404          jz   933
929: 85C9          test ecx, ecx
931: 74C7          jz   876                   ; loop while want_lock && !result
933: 85C9          test ecx, ecx
935: 7504          jnz  941
937: C6461101      mov  byte ptr [esi+11h], 1 ; want_lock = 1 only if result == 0
941: 31C0          xor  eax, eax
943: 87460C        xchg eax, [esi+0Ch]        ; release sleep_interlock
946: 89C8          mov  eax, ecx              ; <-- return result
```

`-[IOPortSession requestType:sleep:]` consumes it, at 4189-4203:
`result = [entry->safeCondLock lock]; if (result != 0) return 0xFFFFFD41;`.

**Our source** — `.h:58` / `.m:180` `- (void)lock`, `.h:102` / `.m:570`
`void AIOPSSCL_lock(id lock)`. But `.m:305` writes

```c
result = AIOPSSCL_lock(self);
```

against that `void` prototype — a hard compile error independent of F1.

**Disposition:** fix. `- (int)lock`, `int AIOPSSCL_lock(id)`. The body needs no change:
`.m:180-244` already computes `result` and already carries the note at `:242`.

**Outcome (Task 8):** Fixed: `- (int)lock` / `int AIOPSSCL_lock(id)` with `return result;`. This also
repaired a hard compile error — `-lockWhen:` already assigned `AIOPSSCL_lock`'s result
against a `void` prototype. Ledger: 796 and 824 **control-flow-confirmed**.

---

**Finding 11 — `-lockWhen:` returns `int`, and `AIOPSSCL_lockWhen` returns it.**

**Reference** — `@encode` `lockWhen: i12@8:12i16`. `-[AppleIOPSSafeCondLock lockWhen:]`
(1080, 108) keeps the result in `edx` and returns it at 1177 (`mov eax, edx`); it returns
0 by falling into the same epilogue when the condition matches (1112 `jz loc_499`, with
`edx` known zero). `-[IOPortSession getType:sleep:]` consumes it at 3676-3680:
`if ([entry->safeCondLock lockWhen:type] != 0) result = 0xFFFFFD41;`.

Body confirmation, which also matches ours: `result = AIOPSSCL_lock(self)` (a direct
`call` to 796 at 1093, not a msgSend); if non-zero return it; if `condition ==
conditionVar` return 0; else spin-acquire `cond_interlock` (offset 4), call
`AIOPSSCL_unlock(self)` (direct call to 564 at 1140), `thread_sleep(&conditionVar,
&cond_interlock, interuptable)`, `result = thread_wait_result()`, loop back to 1092 if
zero, else return it.

**Our source** — `.h:64` / `.m:297` `- (void)lockWhen:`, `.h:114` / `.m:595`
`void AIOPSSCL_lockWhen(id, int)`.

**Disposition:** fix. `- (int)lockWhen:(int)condition`, `int AIOPSSCL_lockWhen(id, int)`.

**Outcome (Task 8):** Fixed: `- (int)lockWhen:(int)` / `int AIOPSSCL_lockWhen(id, int)`; the two
interrupt paths return `result` and the success path returns 0. Ledger: 1048 and 1080
**control-flow-confirmed**.

---

**Finding 14 — `-initWith:intr:` writes `interuptable` last, after `want_lock` and
`waiting`.**

**Reference disassembly** — the store sequence at 326-357:

```
326: C7460400000000  mov dword ptr [esi+4],  0     ; cond_interlock.locked = 0
333: 8B5510          mov edx, [ebp+arg_8]
336: 895608          mov [esi+8], edx              ; conditionVar = condition
339: C7460C00000000  mov dword ptr [esi+0Ch], 0    ; sleep_interlock.locked = 0
346: C6461100        mov byte ptr [esi+11h], 0     ; want_lock = 0
350: C6461200        mov byte ptr [esi+12h], 0     ; waiting = 0
354: 885E10          mov [esi+10h], bl             ; interuptable = intr   <-- last
```

`[super init]`'s result is discarded (the `objc_msgSendSuper` at 321 is not used); the
method returns `esi` = `self`. `@encode` `@13@8:12i16c20`, so `intr` is a `char`.

**Our source** — `.m:119-124` writes offset 0x10 *before* 0x11 and 0x12.

**Disposition:** fix.

**Rationale:** with named ivars (F5) gcc emits assignments in source order, so this two-
line reordering is what makes the 84 bytes line up. Trivial, but it is a real byte
difference, not compiler scheduling — the three stores are to distinct non-aliasing
addresses and gcc 2.x does not reorder them.

**Outcome (Task 8):** Fixed: the store sequence in `-initWith:intr:` is now `cond_interlock.locked,
conditionVar, sleep_interlock.locked, want_lock, waiting, interuptable`. Ledger: 284
**control-flow-confirmed** — 31 of the function's 84 bytes are printed above; the prologue
and the discarded `[super init]` are described rather than printed.

---

### `IOPortSession.m`

**Finding 12 — the four `IOPortSession(Private)` methods have no leading underscore.**

**Reference** — `__OBJC,__category[0]` at 30372: `category_name` `Private`,
`class_name` `IOPortSession`, `instance_methods` → 24728. That list holds exactly four
entries, and the confirming `__message_refs` slots carry the same names:

| selector | `@encode` | imp | our declaration | our definition |
|---|---|---|---|---|
| `acquirePort:sleep:` | `i13@8:12i16c20` | 2772 | `IOPortSession.h:176` | `IOPortSession.m:697` |
| `releasePort` | `v8@8:12` | 3332 | `IOPortSession.h:186` | `IOPortSession.m:921` |
| `getType:sleep:` | `i13@8:12i16c20` | 3588 | `IOPortSession.h:183` | `IOPortSession.m:845` |
| `requestType:sleep:` | `i13@8:12i16c20` | 3824 | `IOPortSession.h:193` | `IOPortSession.m:1002` |

`__message_refs` 25348 `"acquirePort:sleep:"`, 25352 `"requestType:sleep:"`, 25356
`"releasePort"`, 25368 `"getType:sleep:"` — no underscore on any of the four, and no
underscored variant appears anywhere in `__meth_var_names`.

**Our source** — all four are `_`-prefixed in the header (`:176`, `:183`, `:186`, `:193`),
in the `@implementation` (`:697`, `:845`, `:921`, `:1002`), and at all nine call sites:
`:209`, `:231`, `:255`, `:258`, `:811`, `:827`, `:1024`, `:1071`, `:1087`.

**The concrete difference:** the selector strings in `__meth_var_names`,
`__message_refs` and `__cat_inst_meth` would all differ by one byte per name, and the
category method list would not match.

**Disposition:** fix.

**Rationale:** confirms the full set of four is exactly as the brief presumed, including
`requestType:sleep:`. Mechanical rename across 4 declarations, 4 definitions and 9 call
sites; no behaviour change.

**Outcome (Task 8):** Fixed: the four selectors were renamed across 4 header declarations, 4 definitions
and all 9 call sites, and a whole-`PortServer.lksproj` grep for the old names now returns
nothing. **No file outside the finding's own scope needed editing** — the underscored
selectors appeared nowhere in `PDPseudo.m`, `PortServer.m`, `IOPortSessionKern.m`,
`ttyiops.m` or `pdservd.tproj/`. Ledger: 1984, 2036, 2772, 3332, 3588 and 3824
**control-flow-confirmed** (read from `__category[0]` / `__cat_inst_meth` /
`__message_refs`).

---

**Finding 15 — `IOPortSession` declares no ivars; the reference has `_priv`, `void *`, at
offset 4.**

**Reference** — `__OBJC,__instance_vars` at 30488 holds one entry, `_priv`, `@encode`
`^v`, offset **4**; `__class[1]` gives `super_class` `Object`, `instance_size` **8**,
`ivars` → 30488.

**Our source** — `IOPortSession.h:30-32`:

```c
@interface IOPortSession : Object
{
    /* Instance variables - TODO: determine actual layout from decompiled code */
}
```

so `instance_size` is 4, while the `.m` writes and reads `*(void **)((char *)self + 4)`
in **every single method** (`:154`, `:182-184`, `:207`, `:229`, `:248`, `:273`, `:292`,
`:316`, `:343`, `:374`, `:413`, `:443`, `:473`, `:511`, `:556`, `:605`, `:654`, `:708`,
`:727`, and throughout the four private methods).

**Disposition:** fix.

**Rationale:** this was flagged in the brief as the highest-value check in scope, and the
answer is that the layout question is settled by the metadata rather than by the
disassembly: one `void *` ivar named `_priv`. Declare it and replace the raw casts.
Every `self+4` access is currently one word past the end of the object.

**Related, and this is the good news:** the 13 offsets `-[IOPortSession
initForDevice:result:]` writes into the `_priv` block were checked one by one against our
`method_cache[]` indices at `:102-154`, and **all 13 are correct** — `[ebx]`=device,
`[ebx+8]`=0xFFFFFD33, `[ebx+4]`=0, then IMPs at +0x0c setState:mask:, +0x10 getState,
+0x14 watchState:mask:, +0x18 nextEvent, +0x1c executeEvent:data:, +0x20
requestEvent:data:, +0x24 enqueueEvent:data:sleep:, +0x28 dequeueEvent:data:sleep:,
+0x2c enqueueData:…, +0x30 dequeueData:…, then `[edi+4]`=block. The store *order* matches
ours too (device, err, entry, then the ten IMPs in that sequence). No ivar-order
corruption exists in the body; the defect is purely that `_priv` is undeclared.

**Outcome (Task 8):** Fixed: `void *_priv;` is declared in the `@interface` (`instance_size` 8, offset
4) and every `*(void **)((char *)self + 4)` / `*(int *)((char *)self + 4)` /
`**(id **)((char *)self + 4)` replaced by `_priv`. This was the highest-impact repair in
pass 1's range: previously every access ran one word past the end of a 4-byte object.
`__OBJC` metadata; it sets no ledger status of its own. Note that
`IOPortSessionKern.m`'s four accessors still reach the same field by raw cast — correct now
that `_priv` sits at offset 4, but not spelled as the named ivar.

---

**Finding 16 — `_portList` is a single 8-byte queue head; `DAT_00008190` is its second
word, not a separate global.**

**Reference** — the `__DATA,__bss` symbol table around the list:

```
33160 _portListLock
33164 _portList          <-- 8 bytes, 33164..33171
33172 _pseudoUnit
```

and `+[IOPortSession initialize]` initialises both words of it:

```
1191: C705908100008C810000  mov ds:dword_8190, offset _portList   ; _portList+4 = &_portList
1201: C7058C8100008C810000  mov ds:_portList,  offset _portList   ; _portList+0 = &_portList
```

`dword_8190` is 0x8190 = 33168 = `_portList + 4`. IDA names it separately only because no
symbol covers the interior of `_portList`. This is a `queue_init` on a `{next, prev}`
head, and the rest of the code treats it that way: the insert at 3160-3180 sets
`new->prev = _portList.prev; new->next = &_portList; _portList.prev = new;
old_tail->next = new`, and the unlink in `releasePort` at 3421-3453 substitutes
`&_portList` for either neighbour when it is the head.

**Our source** — `IOPortSession.m:11-13`:

```c
static void *_portList = NULL;      /* Head of port list (circular linked list) */
static void *DAT_00008190 = NULL;   /* Tail of port list */
static id _portListLock = NULL;     /* Lock protecting the port list */
```

**The concrete difference:** three globals where the reference has two, and the emitted
`__bss` layout and relocation targets differ. The declaration *order* is right
(`_portListLock` then `_portList`).

**Disposition:** fix.

**Rationale:** declare one `static struct { void *next; void *prev; } _portList;` (or the
DriverKit `queue_head_t` if a matching declaration exists in this tree) and drop
`DAT_00008190`, replacing its uses with `_portList.prev`. Zero-initialisation is
equivalent — the symbol is in `__bss`.

**Outcome (Task 8):** Partially fixed. `DAT_00008190` is deleted and `_portList` is now one
`static struct { void *next; void *prev; }` head, with `+initialize` writing `prev` then
`next`, the empty test against `&_portList`, both insert cases and the `releasePort` unlink
all rewritten. **Not done: the declaration order.** This finding asserts the order is
already right (`_portListLock` then `_portList`) while our source declares `_portList`
first, so the finding is self-contradictory and part 1 left the order alone. If the
reference `__bss` order (33160 `_portListLock`, 33164 `_portList`) is meant to be reproduced
by declaration order, a one-line swap is still owed. Ledger: 1188 and 3332
**control-flow-confirmed**.

---

**Finding 17 — `objc_getClass("…")` should be ordinary class references.**

**Reference** — `__OBJC,__cls_refs` holds six entries: 25496 `NXLock`, 25500
`AppleIOPSSafeCondLock`, 25504 `NXConditionLock`, 25508 `PDPseudo`, 25512
`IOPortSession`, 25516 `IODevice`; and the binary imports
`.objc_class_name_NXLock`, `.objc_class_name_NXConditionLock`,
`.objc_class_name_Object`, `.objc_class_name_IODevice`, `.objc_class_name_Protocol`.
The three sites in scope load `__cls_refs` slots directly:

```
1225: 8B159 8630000  mov edx, ds:paNxlock            ; +[IOPortSession initialize]
3045: 8B0D9C630000    mov ecx, ds:paAppleiopssafec    ; -[… acquirePort:sleep:]
3085: 8B0DA0630000    mov ecx, ds:paNxconditionloc    ; -[… acquirePort:sleep:]
```

**`_objc_getClass` is not among the binary's 51 imports.**

**Our source** — `IOPortSession.m:45` `objc_getClass("NXLock")`, `:739`
`objc_getClass("AppleIOPSSafeCondLock")`, `:745` `objc_getClass("NXConditionLock")`
(and `IOPortSession.m:189` `objc_getClass("Object")`, covered by F19).

**Disposition:** fix.

**Rationale:** using `objc_getClass` adds an undefined symbol the reference does not
have, and creates `__cstring` entries for the class names that the reference does not
have either. Write `[[NXLock alloc] init]`, `[[AppleIOPSSafeCondLock alloc] init]`,
`[[NXConditionLock alloc] initWith:1]` and let the compiler emit the class references.

**Outcome (Task 8):** Fixed: `objc_getClass("NXLock")`, `objc_getClass("AppleIOPSSafeCondLock")` and
`objc_getClass("NXConditionLock")` became `[[NXLock alloc] init]`,
`[[AppleIOPSSafeCondLock alloc] init]` and `[[NXConditionLock alloc] initWith:1]`;
`#import <machkit/NXLock.h>` added. Ledger: 1188, 1304 and 2772
**control-flow-confirmed**.

---

**Finding 18 — `-[IOPortSession init]` really does call `[super free]`.**

**Reference disassembly** — the whole of 1260 (41 bytes):

```
1260: 55            push ebp
1261: 89E5          mov  ebp, esp
1263: 83EC08        sub  esp, 8
1266: 8B15C4620000  mov  edx, ds:paFree           ; __message_refs+44 -> "free"
1272: 52            push edx
1273: 8B5508        mov  edx, [ebp+self]
1276: 8955F8        mov  [ebp+var_8.receiver], edx
1279: 8B15DC630000  mov  edx, ds:stru_63B0.ext    ; 25564 = IOPortSession's super_class field
1285: 8955FC        mov  [ebp+var_8.super_class], edx
1288: 8D45F8        lea  eax, [ebp+var_8]
1291: 50            push eax
1292: E8EFFAFFFF    call _objc_msgSendSuper
1297: 89EC          mov  esp, ebp
1299: 5D            pop  ebp
1300: C3            retn                          ; returns msgSendSuper's result
```

The selector is loaded from `__message_refs[11]`, whose `__meth_var_names` string is
`"free"`. `-[AppleIOPSSafeCondLock initWith:intr:]` at 298 loads `paInit` from
`__message_refs[10]` = `"init"` in the identical idiom, so the two are distinguishable
and this is not a mislabelling.

**Our source** — `IOPortSession.m:56-64` substitutes `[super init]; return self;` and
explains at `:58-61` that "decompiled code shows this calls `[super free]`, but that
makes no sense … likely an error in the original binary or a quirk of the decompiler."

**The concrete difference:** it is not a decompiler quirk. The selector reference is
unambiguous, and `-init` returns `Object`'s `-free` result (nil) rather than `self`.

**Disposition:** fix.

**Rationale:** the point of this pass is to reconstruct what shipped, and nothing in the
driver sends bare `-init` to an `IOPortSession` (`ttyiops.m` uses
`initForDevice:result:`, `__message_refs` 25416), so reproducing the oddity is inert.
Write `return [super free];` with a prominent comment recording that this is Apple's
apparent copy-paste bug and not ours. **This is the one finding in my scope where
fidelity and sanity disagree; `accept` with a comment is defensible if the project would
rather not ship a knowingly broken `-init`.** I recommend fix + comment.

**Outcome (Task 8):** Fixed: the body is `return [super free];` with a comment recording that this is
Apple's apparent copy-paste bug, not ours, and that it is inert because nothing sends bare
`-init` to an `IOPortSession`. Ledger: 1260 **assembly-matched** — all 41 bytes are printed
above and the `__message_refs[11]` -> `"free"` load is unambiguous.

---

**Finding 19 — `-[IOPortSession free]` returns `[super free]`, and builds the super
struct from the class, not from `objc_getClass("Object")`.**

**Reference disassembly** — 1760 (88 bytes), the parts that matter:

```
1770: 8B15FC620000  mov  edx, ds:paRelease
1776: 52 / 1777: 53 / 1778: E809F9FFFF  call _objc_msgSend    ; [self release]
1786: 837B0400      cmp  dword ptr [ebx+4], 0                 ; if (_priv)
1790: 7415          jz   1813
1792: 6A34          push 34h
1794: 8B5304        mov  edx, [ebx+4]
1797: 52 / 1798: E8F5F8FFFF  call _IOFree                      ; IOFree(_priv, 0x34)
1803: C7430400000000 mov dword ptr [ebx+4], 0                  ; _priv = 0
1813: 8B15C4620000  mov  edx, ds:paFree
1820: 895DF8        mov  [ebp+var_8.receiver], ebx
1823: 8B15DC630000  mov  edx, ds:stru_63B0.ext                 ; class's super_class field
1832: 8D45F8 / 1835: 50 / 1836: E8CFF8FFFF  call _objc_msgSendSuper
1841: 8B5DF4        mov  ebx, [ebp+var_C]
1844: 89EC / 1846: 5D / 1847: C3                               ; returns msgSendSuper's result
```

**Our source** — `IOPortSession.m:174-193` hand-rolls the `objc_super` struct:

```c
    super_struct.receiver = self;
    super_struct.class = objc_getClass("Object");
    objc_msgSendSuper(&super_struct, @selector(free));

    return self;
```

**The concrete difference:** two — the `objc_getClass` import (F17) and the return value.
The reference returns nil (Object's `-free`), ours returns `self`.

**Disposition:** fix. `return [super free];`.

**Outcome (Task 8):** Fixed: the hand-rolled `objc_super` struct and its `objc_getClass("Object")` are
gone; the body is `[self release]`, the conditional `IOFree(_priv, 0x34)`, then
`return [super free];`. Ledger: 1760 **control-flow-confirmed** — this finding prints the
parts of 1760 that matter, not the whole 88 bytes.

---

**Finding 20 — `-[IOPortSession initForDevice:result:]`: the first argument is `char *`,
and the failure path is `return [self free];`.**

**Reference** — `@encode` `@16@8:12*16^i20`: returns `id`, first argument `char *`,
second `int *`. Failure path in full:

```
1374: 0F8562010000  jnz 1734          ; IOGetObjectForDeviceName failed — *result already set
1406: 0F843C010000  jz  1728          ; conformsTo: returned NO
1728: C7063EFDFFFF  mov dword ptr [esi], 0FFFFFD3Eh   ; *result = -706
1734: 8B15C4620000  mov edx, ds:paFree
1740: 52
1741: 57            push edi          ; self
1742: E82DF9FFFF    call _objc_msgSend                ; [self free]
1747: 8D65E8        lea esp, [ebp-18h]
1750: 5B / 5E / 5F / 89EC / 5D / C3                   ; returns [self free]'s result
```

Note the two entry points: the `IOGetObjectForDeviceName` failure jumps *past* the
`*result` store at 1728, because `*result` was already assigned the error at 1367
(`mov [esi], eax`). Success returns `edi` = `self` at 1722-1724.

**Our source** — `IOPortSession.h:49` says `- initForDevice:(const char *)device`,
`IOPortSession.m:75` says `- initForDevice:(int)device` and casts at `:89`. The two
disagree with each other as well as with the reference. `:164-165` is
`[self free]; return nil;`.

**Disposition:** fix. `- initForDevice:(char *)device result:(int *)result` in both
header and implementation, drop the cast at `:89`, and `return [self free];`.

**Rationale:** the header/implementation disagreement is a latent bug independent of
parity; on i386 it happens to compile because both are 4 bytes. The `return [self free]`
form is not cosmetic — the reference genuinely returns whatever `Object`'s `-free`
returns rather than a literal `nil`, and there is no `xor eax, eax` anywhere in the tail.

**Outcome (Task 8):** Fixed: the signature is `- initForDevice:(char *)device result:(int *)result` in
both header and implementation (they previously disagreed with each other), the `(char *)`
cast at `IOGetObjectForDeviceName` is dropped, and `[self free]; return nil;` became
`return [self free];`. Ledger: 1304 **control-flow-confirmed**.

---

**Finding 21 — `conformsTo:` is passed `@protocol(PortDevices)`, not
`@protocol(IOSerialDeviceProtocol)`.**

**Reference disassembly** — 1380-1406:

```
1380: 6898680000    push offset stru_6898        ; 26776
1385: 8B15CC620000  mov  edx, ds:paConformsto
1391: 52 / 1392: 8B55F4 / 1395: 52
1396: E887FAFFFF    call _objc_msgSend
1404: 84C0          test al, al
1406: 0F843C010000  jz   1728
```

26776 is the first record in `__OBJC,__protocol`, read directly:
`isa=2, protocol_name="PortDevices", protocol_list=0, instance_methods=24784,
class_methods=0`. Four byte-identical `PortDevices` records exist (26776, 26796, 26816,
26836) — one per compilation unit that mentions the protocol, which is normal for this
runtime; `IOPortSession.m`'s is the one at 26776. No protocol named
`IOSerialDeviceProtocol` exists anywhere in `__class_names` or `__protocol`.

**Our source** — `IOPortSession.m:94` passes `@protocol(IOSerialDeviceProtocol)`, even
though `IOPortSession.h:18-20` already declares `@protocol PortDevices` correctly.

**Disposition:** fix. Pass `@protocol(PortDevices)`. Leave the unused
`#define IOPortDevice PortDevices` alias at `:23` alone — it is not referenced from
anything in my scope, and removing it is out of scope for a parity fix.

**Outcome (Task 8):** Fixed: `conformsTo:@protocol(PortDevices)`. The `IOSerialDeviceProtocol` it
replaced names a protocol that exists nowhere in the binary. The
`#define IOPortDevice PortDevices` alias was left alone as this finding directs. Ledger:
1304 **control-flow-confirmed**.

---

**Finding 22 — `-[IOPortSession acquirePort:sleep:]` matches, with three inherited
defects and one confirmed subtlety.**

The 560-byte body was traced block by block and **agrees with `IOPortSession.m:697-831`
throughout**: the fast path when `_priv->entry` is already set (2793-2831, including the
`type == 1 && entry[0x1d]` case that sets `already_in_list`), the list lock, the
empty-list check against `&_portList`, the linear search comparing `entry[0x10]` against
`_priv->device` with the refcount bump at 2836, the `[device acquire:0]` /
`IOMalloc(0x20)` / `memset` / lock-object construction path, the `entry[0x1d] =
entry[0x1c]` copy at 3117-3120, the zeroing of `+0x18` then `+0x14`, `entry[0x1e] = 1`,
both list-insert cases, the unlock, the `_priv->entry = entry` store *after* the unlock,
the `requestType:sleep:` call, and the release/re-acquire of `entry[0x10]` when
`already_in_list`. Return is `_priv->err`.

Its divergences are all inherited: F12 (three underscored selectors — `_requestType:sleep:`
at `:811`, `_releasePort` at `:827`, and its own name), F16 (`DAT_00008190` at `:767`,
`:772`, `:774`, `:775`), F17 (`objc_getClass` at `:739`, `:745`), and F25 (`sleep` is a
`char`, sign-extended at 3210 `movsx eax, [ebp+var_4]`, before being passed on).

**One subtlety worth recording** so the fix pass does not "correct" it: at 3117 the
reference copies `entry[0x1c]` into `entry[0x1d]` on a **freshly `memset`-zeroed** block,
so both are zero and the copy is a no-op. Our `:754` reproduces it. Keep it.

**Disposition:** no finding of its own; fix via F12/F16/F17/F25.

**Outcome (Task 8):** No change of its own; repaired through Findings 12, 16, 17 and 25. The
`entry[0x1d] = entry[0x1c]` copy on the freshly `memset`-zeroed block was **kept**, as this
finding instructs. Ledger: 2772 **control-flow-confirmed** — the 560-byte body was traced
block by block and agrees throughout, but was not transcribed instruction by
instruction.

---

**Finding 23 — `-[IOPortSession acquireAudit:]` takes the `sleep` flag.**

**Reference disassembly** — the whole of 1932 (49 bytes):

```
1932: 55 / 1933: 89E5
1935: 8B5508        mov   edx, [ebp+self]
1938: 8A4510        mov   al,  [ebp+arg_8]        ; the argument, one byte
1941: 837A0400      cmp   dword ptr [edx+4], 0    ; if (_priv == NULL)
1945: 7419          jz    1972
1947: 0FBEC0        movsx eax, al                 ; sign-extend char -> int
1950: 50            push  eax                     ; sleep:
1951: 6A01          push  1                       ; acquirePort: 1  (callout)
1953: 8B0D04630000  mov   ecx, ds:paAcquireportSle
1959: 51 / 1960: 52
1961: E852F8FFFF    call  _objc_msgSend           ; return [self acquirePort:1 sleep:sleep]
1966: 89EC / 5D / C3
1972: B83EFDFFFF    mov   eax, 0FFFFFD3Eh         ; -706
1977: 89EC / 5D / C3
```

`@encode` `acquireAudit: i9@8:12c16` — one `char` argument. `-[IOPortSession acquire:]`
(1984) is the same 49 bytes with `push 2` instead of `push 1`.

**Our source** — `IOPortSession.h:65` / `.m:224` `- (int)acquireAudit` taking nothing,
and `:231` hardcodes `sleep:1`.

**The concrete difference:** the argument is the caller's sleep flag, sign-extended from
`char` and forwarded verbatim as `acquirePort:`'s second argument. Hardcoding 1 changes
behaviour for any caller that passes 0 — and `__message_refs` 25476 shows
`acquireAudit:` is sent from elsewhere in the driver (`ttyiops.m`, out of my scope).

**Disposition:** fix. `- (int)acquireAudit:(BOOL)sleep`, forwarding it. Same finding
covers `- (int)acquire:(BOOL)sleep` at `.h:60` / `.m:202`, currently `(int)sleep`.

**Outcome (Task 8):** Fixed: `- (int)acquireAudit:(BOOL)sleep` forwards to `acquirePort:1 sleep:sleep`
and `- (int)acquire:(BOOL)sleep` likewise; the hardcoded `sleep:1` is gone. Both existing
senders (`ttyiops.m`, `IOPortSessionKern.m`) already passed an argument, so no foreign call
site changed. Ledger: 1932 **assembly-matched** — all 49 bytes are printed above. 1984
`-acquire:` is held at **control-flow-confirmed** instead: Findings 12 and 25 also touch it
and both rest on weaker evidence.

---

**Finding 24 — five methods declared `void` in our source return `int` in the
reference.**

**Reference** — `__OBJC,__inst_meth` `@encode`s, and in every case the disassembly
returns something:

| selector | `@encode` | our decl | what the reference returns |
|---|---|---|---|
| `release` | `i8@8:12` | `.h:68` `- (void)` | `-706` if `_priv == NULL` (2049), else `0` (2095 `xor eax, eax`) |
| `setState:mask:` | `i16@8:12L16L20` | `.h:93` `- (void)` | the forwarded IMP's result (2140), else `_priv->err` (2148-2151) |
| `watchState:mask:` | `i16@8:12^L16L20` | `.h:99` `- (void)` | IMP result if `_priv->err` still 0 (2230-2241), else `_priv->err` (2248-2251) |
| `executeEvent:data:` | `i16@8:12L16L20` | `.h:107` `- (void)` | IMP result (2344), else `_priv->err` (2352-2355) |
| `requestEvent:data:` | `i16@8:12L16^L20` | `.h:113` `- (void)` | IMP result (2400), else `_priv->err` (2408-2411) |

**Our source** — all five bodies compute the value and drop it. `-release` at `:245-260`
has no `return` at all on either path; `-watchState:mask:` at `:365-395` even has a
comment at `:394` saying "Error case - return without modifying state".

**Disposition:** fix. All five become `- (int)`, returning what the disassembly returns.

**Rationale:** `release`'s `-706` is the only signal a caller gets that the session was
never initialised, and `setState:mask:`/`executeEvent:data:` are how the tty layer learns
that the port went away mid-call. Dropping them is a behaviour change, not just a
signature change.

**Outcome (Task 8):** Fixed: `release` (-706 when `_priv` is NULL, else 0), `setState:mask:`,
`watchState:mask:`, `executeEvent:data:` and `requestEvent:data:` now return the forwarded
IMP's result or the session error code; `watchState:mask:` uses the same
re-read-`_priv`-on-error shape confirmed for `dequeueData:…`. Ledger: 2036, 2104, 2188, 2308
and 2364 **control-flow-confirmed** — per-method addresses were cited, not full streams.

---

**Finding 25 — thirteen `@encode` signatures differ: `unsigned long` vs `unsigned int`,
`char *` vs `void *`, and `char` vs `int` for every `sleep:` argument.**

**Reference** — from `__OBJC,__meth_var_types`, verbatim:

```
getState                                        L8@8:12
nextEvent                                       L8@8:12
setState:mask:                                  i16@8:12L16L20
watchState:mask:                                i16@8:12^L16L20
executeEvent:data:                              i16@8:12L16L20
requestEvent:data:                              i16@8:12L16^L20
enqueueEvent:data:sleep:                        i17@8:12L16L20c24
dequeueEvent:data:sleep:                        i17@8:12^L16^L20c24
enqueueData:bufferSize:transferCount:sleep:     i21@8:12*16I20^I24c28
dequeueData:bufferSize:transferCount:minCount:  i24@8:12*16I20^I24I28
acquire:                                        i9@8:12c16
acquireAudit:                                   i9@8:12c16
acquirePort:sleep:                              i13@8:12i16c20
getType:sleep:                                  i13@8:12i16c20
requestType:sleep:                              i13@8:12i16c20
```

`L` is `unsigned long`, `I` is `unsigned int`, `*` is `char *`, `c` is `char`, `^` is
pointer-to.

**Our source** — `IOPortSession.h` uses `unsigned int` throughout for the state and event
methods (`:87`, `:93`, `:99`, `:107`, `:113`, `:118`, `:126`, `:134`), `void *` for the
two data buffers (`:145`, `:157`), and `int sleep` everywhere (`:60`, `:126`, `:134`,
`:148`, `:176`, `:183`, `:193`).

**The concrete difference:** `unsigned long` and `unsigned int` are the same width on
i386 so the emitted code is unaffected for the state/event methods, but
`__meth_var_types` is a literal byte array in the binary, so these are real parity
differences and not cosmetics. The `sleep:` arguments are *not* width-neutral: the
reference reads them as one byte and sign-extends (`mov al, [ebp+arg_10]` / `movsx eax,
al` at 2427/2447, 2515/2535, 2603/2623, 1938/1947, 1990/1999, 2787/3210, 3599, 3838).

**Disposition:** fix.

**Rationale:** cheap, mechanical, and the `sleep:` half genuinely changes codegen. Note
that `dequeueData:…` uses `I` (unsigned int) while `enqueueEvent:…` uses `L` (unsigned
long) — the original's own types were inconsistent, so copy the table above literally
rather than picking one.

**Outcome (Task 8):** Fixed: the header's state/event methods moved to `unsigned long` /
`unsigned long *`, the two data buffers to `char *`, the two transfer counts left
`unsigned int` / `unsigned int *`, and **every** `sleep:` argument to `BOOL` (`c`). The
`__meth_var_types` table above was copied literally, including its own `L` vs `I`
inconsistency. Ledger: 2104, 2160, 2188, 2264, 2308, 2364, 2420, 2508, 2596, 2688, 2772,
3588 and 3824 **control-flow-confirmed**, and it is this finding that holds 1984 and several
of the others below `assembly-matched`.

---

**Finding 26 — `getType:` takes an `int` by value; our source takes `int *` and
dereferences it.**

**Reference** — `@encode` `getType:sleep: i13@8:12i16c20`: first argument `i`, a plain
`int`. The disassembly never loads through it — the three uses are all value uses:

```
3616: 837D1001      cmp [ebp+arg_8], 1        ; if (type == 1) use entry+0x1c else entry+0x1d
3647: 8B5510        mov edx, [ebp+arg_8]
3650: 52            push edx                  ; [safeCondLock lockWhen:type]
...
3796: 8B5510        mov edx, [ebp+arg_8]
3799: 895018        mov [eax+18h], edx        ; entry->type = type
```

and the caller passes a value, not an address — `-[IOPortSession requestType:sleep:]` at
4292-4306:

```
4292: 0FBE45FC      movsx eax, [ebp+var_4]    ; sleep
4296: 50            push  eax
4297: 53            push  ebx                 ; type, by value
4298: 8B0D18630000  mov   ecx, ds:paGettypeSleep
4304: 51 / 4305: 56 / 4306: E829EFFFFF  call _objc_msgSend
```

with a second entry point at 4113-4120 that pushes the literal `1` for the
`type == 1 && entry[0x1d]` recursion case.

**Our source** — `IOPortSession.h:183` and `.m:845` declare `- (int)_getType:(int *)type
sleep:(int)sleep` and dereference at `:859`, `:874` and `:905`; `.m:1087` passes
`&type`.

**Disposition:** fix. `- (int)getType:(int)type sleep:(BOOL)sleep`, drop the three
dereferences, and pass `type` by value at `:1087`.

**Rationale:** taking the address of the `type` parameter forces it to the stack and
changes the whole frame; it also makes `getType:` look like it can write back to its
caller, which it cannot. The rest of `getType:sleep:` matches: `sleep == 0` returns
`0xFFFFFD34` (-716); the flag pointer is `entry + 0x1c` when `type == 1` else
`entry + 0x1d`; increment, `lockWhen:type` (non-zero result → `0xFFFFFD41`, -703),
`[nxCondLock lock]`, `[nxCondLock condition]`, `unlockWith:1` when zero else `unlock`,
decrement the flag, and on success store `entry->type = type` and `entry->owner = self`.
`-[IOPortSession requestType:sleep:]`'s 34-block state machine was traced in full and
matches `:1002-1130` including all four `-706` exits, the `-703` lock-failure exit, the
`unlock_value` computation (2 if `entry[0x1d]`, else `entry[0x1c] != 0`), and the
`lockWhen:1`/`unlock` epilogue.

**Outcome (Task 8):** Fixed: `- (int)getType:(int)type sleep:(BOOL)sleep`; the three `*type`
dereferences became `type`, and `requestType:sleep:` passes `type` rather than `&type`.
Ledger: 3588 and 3824 **control-flow-confirmed**.

---

**Finding 13 — the methods are in the wrong order in both files.**

**Reference** — the runtime emits each method list in reverse source order, so reading
`__inst_meth` backwards recovers the original file order, and it agrees exactly with
ascending IMP address.

`AppleIOPSSafeCondLock.m`, with the C wrappers interposed at their text addresses:

```
+initialize (0), -init (224), -initWith: (252), -initWith:intr: (284),
AIOPSSCL_interuptable (368), -interuptable (396),
AIOPSSCL_condition (412),    -condition (440),
AIOPSSCL_setCondition (456), -setCondition: (484),
-free (520),
AIOPSSCL_unlock (564),       -unlock (592),
AIOPSSCL_unlockWith (680),   -unlockWith: (712),
AIOPSSCL_lock (796),         -lock (824),
AIOPSSCL_lockTry (960),      -lockTry (988),
AIOPSSCL_lockWhen (1048),    -lockWhen: (1080)
```

Each wrapper sits immediately *before* the method it forwards to. That interleaving is
only reachable if the C functions are written **inside** the `@implementation` block,
which gcc permits. Our file puts all eight wrappers after `@end` (`:521-632`), and orders
the methods `initialize, init, initWith:, initWith:intr:, free, condition, interuptable,
lock, lockTry, lockWhen:, setCondition:, unlock, unlockWith:`.

`IOPortSession.m` source order from the reference:

```
init, initForDevice:result:, free, name, locked, acquireAudit:, acquire:, release,
setState:mask:, getState, watchState:mask:, nextEvent, executeEvent:data:,
requestEvent:data:, enqueueEvent:data:sleep:, dequeueEvent:data:sleep:,
enqueueData:…, dequeueData:…
```

Ours has `acquire:` before `acquireAudit:`, `name`/`locked` after `release`, and
`getState` before `setState:mask:`. The `Private` category order is
`acquirePort:sleep:`, `releasePort`, `getType:sleep:`, `requestType:sleep:`; ours is
`_acquirePort:sleep:`, `_getType:sleep:`, `_releasePort`, `_requestType:sleep:`.

**Disposition:** fix.

**Rationale:** purely mechanical and behaviour-free, but nothing else in the ledger can
line up on address until it is done — text order *is* the function layout.

**Outcome (Task 8):** Fixed in both files: the eight C wrappers moved inside `@implementation`, each
immediately ahead of the method it forwards to, and both classes' methods reordered to the
reference's ascending IMP order (`PDPseudo`'s equivalent is Finding 33). **This sets no
ledger status.** Method text order is a link-order property observable only in a built image,
and there is no compiler in this tree; no function extent carries this finding.

---

### `PDPseudo.m`

**Finding 27 — `PDPseudo.m` does not compile: a stray closing brace at line 209.**

```c
203  - (void)requestEvent:(unsigned int)event data:(unsigned int *)data
204  {
205      /* Operation not supported - no-op */
206      /* Note: Decompiled shows return 0xfffffd42 but signature is void */
207  }
208
209  }                                <-- extra
210
211  /*
212   * enqueueEvent:data:sleep: …
```

The method body at 203–207 is already closed at 207. The brace at 209 closes the
`@implementation`'s brace balance early and every subsequent method is parsed outside a
method context.

**Disposition:** fix. **Rationale:** hard syntax error; the file cannot build.
This is the `PDPseudo.m` counterpart of part 1's Finding 1 (`AppleIOPSSafeCondLock.m`)
and of Finding 54 below (`IOPortSessionKern.m`). Three of the six files in this
`lksproj` currently fail to compile.

**Outcome (Task 8):** Repaired ahead of the fix pass by Task 7 (`9d005a26`). Brace delta is `+0`
today.

---

**Finding 28 — `PDPseudo`'s superclass is `Object`; the reference has
`IODevice <PortDevices>`.** `PDPseudo.h:17`, and the `#import <objc/Object.h>` at
`PDPseudo.h:9`.

Reference `__OBJC,__class[2]`, read directly from the binary:

```
name          -> PDPseudo
super_class   -> IODevice          (26991 in __class_names)
instance_size -> 264
ivars         -> 0
protocols     -> {next 0, count 1, [ PortDevices ] }   (list at 24588, protocol at 26796)
```

`.objc_class_name_IODevice` is imported (41200). `instance_size` 264 with no ivars of its
own is exactly `IODevice`'s own size, corroborated independently by `PortServer`, whose
first and only ivar `state` sits at **264**. The `objc_msgSendSuper` at 4490 loads
`PDPseudo.super_class` (`stru_6400.super_class`, 25604 = `__class` entry 2 + 4), which is
the third piece of evidence.

**Disposition:** fix — `@interface PDPseudo : IODevice <PortDevices>` and import
`<driverkit/IODevice.h>`.
**Rationale:** structural, and the same shape as drvBPF's Finding 1. `PDPseudo` is
declared in `Default.table`'s `"Class Names"` and cannot be instantiated by DriverKit
unless it descends from `IODevice`. The protocol adoption is what makes
`+[IOPortSession iopsServerIoctlCommand:data:]`'s `conformsTo:` scan (6162) find it.

**Outcome (Task 8):** Fixed: `@interface PDPseudo : IODevice <PortDevices>` with
`#import <driverkit/IODevice.h>` replacing `<objc/Object.h>`. Ledger: 4400
**assembly-matched** — 4400 was re-read in full after the edit and 4477 loads
`PDPseudo.super_class`, which is what a plain `[super …]` against an `IODevice` superclass
emits.

---

**Finding 29 — `+[PDPseudo probe:]` issues three message sends where the reference
issues two, and reaches the class through `objc_getClass`.** `PDPseudo.m:33-53`.

**Reference** (all 61 bytes):

```
4336: 55 89E5              push ebp / mov ebp,esp
4339: 8B5510 52            push [ebp+arg_8]              ; deviceDescription
4343: 8B151C630000 52      push ds:paInitfromdevice      ; @selector(initFromDeviceDescription:)
4350: 8B15C8620000 52      push ds:paAlloc               ; @selector(alloc)
4357: 8B15A4630000 52      push ds:paPdpseudo_0          ; __cls_refs[3] -> "PDPseudo"
4364: E8EFEEFFFF           call _objc_msgSend            ; [PDPseudo alloc]
4369: 83C408               add  esp, 8
4372: 50                   push eax
4373: E8E6EEFFFF           call _objc_msgSend            ; [obj initFromDeviceDescription:dd]
4378: 85C0 7506            test eax,eax / jnz 4388
4382: 31C0 …               return 0
4388: B801000000 …         return 1
```

Two sends. The class comes from `__cls_refs` (25508, one of six entries, contents
`NXLock`, `AppleIOPSSafeCondLock`, `NXConditionLock`, **`PDPseudo`**, `IOPortSession`,
`IODevice`) — that is what plain `[PDPseudo alloc]` compiles to. Note also the
argument-sharing: gcc pushes both selector/argument groups once and `add esp,8` between
the calls.

**Our source**

```c
    pseudoDevice = objc_msgSend(objc_getClass("PDPseudo"), @selector(alloc));
    pseudoDevice = objc_msgSend(pseudoDevice,
                                @selector(initFromDeviceDescription:),
                                deviceDescription);
    initResult = objc_msgSend(pseudoDevice);        /* no selector at all */
    if (initResult == 0) return 0;
    return 1;
```

**Difference:** (a) an `objc_getClass("PDPseudo")` runtime lookup where the reference has
a compile-time class reference; (b) a **third** `objc_msgSend(pseudoDevice)` with no
selector argument, which has no counterpart in the reference and is not valid C — it
sends whatever garbage is in the second stack slot; (c) `objc_msgSend` written out by
hand where the source plainly said `[[PDPseudo alloc] initFromDeviceDescription:…]`.

**Disposition:** fix. **Rationale:** the third send is a live defect, not a stylistic
one. This is the same shape as part 1's Finding 17, which covers the `objc_getClass`
half.

**Outcome (Task 8):** Fixed: `[[PDPseudo alloc] initFromDeviceDescription:deviceDescription]`, the
selectorless third send deleted, `objc_getClass("PDPseudo")` replaced by the class name.
Ledger: 4336 **assembly-matched** — 4336 was re-read in full (61 bytes, two `_objc_msgSend`,
class from `__cls_refs`, `test eax,eax` then 0/1).

---

**Finding 30 — six of the constant-return methods are declared `(void)` but the
reference returns −702 from all of them.** `PDPseudo.h:39,41,42,45,46` and
`PDPseudo.m:117,145,160,188,203`.

The reference's twelve constant-return methods are two groups:

```
returning 0FFFFFD42h (-702), 12 bytes, ten of them:
  4548 acquire:      4620 executeEvent:data:      4656 dequeueEvent:data:sleep:
  4560 release       4632 requestEvent:data:      4668 enqueueData:…:sleep:
  4572 setState:mask: 4644 enqueueEvent:data:sleep: 4680 dequeueData:…:minCount:
  4596 watchState:mask:

  4548: 55 89E5 B842FDFFFF 89EC 5D C3     ; the exact byte string, ten times

returning 0, 9 bytes, two of them:
  4584 getState      4608 nextEvent
  4584: 55 89E5 31C0 89EC 5D C3
```

`__meth_var_types` gives the return type for each: `i8@8:12` for `release`,
`i16@8:12L16L20` for `setState:mask:`, `i16@8:12^L16L20` for `watchState:mask:`,
`i16@8:12L16L20` for `executeEvent:data:`, `i16@8:12L16^L20` for `requestEvent:data:` —
all `i`, `int`. Ours declares five of those `(void)` (`release`, `setState:mask:`,
`watchState:mask:`, `executeEvent:data:`, `requestEvent:data:`) with an empty body and a
comment saying "Decompiled shows return 0xfffffd42 but signature is void".

**Difference:** the comment is wrong and the signature is wrong. Every one of the five
returns −702 in the reference. −702 is `IO_R_UNSUPPORTED` in DriverKit's
`return.h` numbering (the same value `IOPortSession`'s stubs use); the whole point of
`PDPseudo` is to be a `PortDevices` conformer that rejects every operation, and a caller
that gets no return value cannot tell.

**Disposition:** fix. Declare all five `- (int)` (`IOReturn`) returning `0xfffffd42`.
`getState` and `nextEvent` keep their zero returns.
**Rationale:** highest-severity finding in `PDPseudo.m` after the syntax error — five
methods currently return an indeterminate register to callers that test it.

**Outcome (Task 8):** Fixed for **five** methods — `release`, `setState:mask:`, `watchState:mask:`,
`executeEvent:data:` and `requestEvent:data:` are now `- (int)` returning `0xfffffd42`;
`getState` and `nextEvent` keep their `return 0`. **This finding's title says "six"; there
are five, and its own body agrees** (see Section 13). The numeric literal was kept rather
than a symbolic name, because -702 is `IO_R_RESOURCE`, not `IO_R_UNSUPPORTED` (Section 13).
Ledger: 4548 and 4560 **assembly-matched** — both were re-read in full and are the exact
12-byte `55 89E5 B842FDFFFF 89EC 5D C3`. 4572, 4596, 4620 and 4632 are held at
**control-flow-confirmed**: they were not re-read individually and rest on §5.1's statement
that they share that byte string.

---

**Finding 31 — nine `@encode` signatures in `PDPseudo` differ.** `PDPseudo.h:37-59`.

Reference `__meth_var_types` versus what our declarations encode:

| selector | reference | ours encodes | difference |
|---|---|---|---|
| `initFromDeviceDescription:` | `@12@8:12@16` | `@12@8:12^v16` | arg is `id`, not `void *` |
| `acquire:` | `i9@8:12c16` | `i12@8:12i16` | arg is `char` |
| `getState` | `L8@8:12` | `I8@8:12` | `unsigned long`, not `unsigned int` |
| `nextEvent` | `L8@8:12` | `I8@8:12` | same |
| `setState:mask:` | `i16@8:12L16L20` | `v16@8:12I16I20` | return + both args |
| `watchState:mask:` | `i16@8:12^L16L20` | `v16@8:12^I16I20` | return + both args |
| `executeEvent:data:` | `i16@8:12L16L20` | `v16@8:12I16I20` | return + both args |
| `requestEvent:data:` | `i16@8:12L16^L20` | `v16@8:12I16^I20` | return + both args |
| `enqueueEvent:data:sleep:` | `i17@8:12L16L20c24` | `i20@8:12I16I20i24` | `L`×2, `sleep` is `char` |
| `dequeueEvent:data:sleep:` | `i17@8:12^L16^L20c24` | `i20@8:12^I16^I20i24` | same |
| `enqueueData:…:sleep:` | `i21@8:12*16I20^I24c28` | `i24@8:12^v16I20^I24i28` | buffer is `char *`, `sleep` is `char` |
| `dequeueData:…:minCount:` | `i24@8:12*16I20^I24I28` | `i24@8:12^v16I20^I24I28` | buffer is `char *` |

The `unsigned long` / `unsigned int` split is the same one part 1 recorded as Finding 25
for `IOPortSession`, and it is unsurprising — `PDPseudo` and `IOPortSession` implement
the *same* `PortDevices` protocol, and their two method lists have byte-identical type
strings for all twelve shared selectors. That cross-check is itself confirmation: every
`PDPseudo` signature above is byte-identical to `IOPortSession`'s for the same selector.

**Disposition:** fix. **Rationale:** these are protocol conformance signatures. On i386
the emitted stores are the same width, so nothing changes at runtime, but the encodings
are what `conformsTo:` and the DriverKit parameter machinery read, and they should match
`IOPortSession`'s byte for byte because the reference's do.

**Outcome (Task 8):** Applied — all twelve `PortDevices` selectors in `PDPseudo.h` and `.m` now use the
same spellings `IOPortSession.h` uses — but **not re-verified**: the declarations were
compared against the `__meth_var_types` table quoted in this finding, not against a fresh
read of the section. Ledger: 4584, 4608, 4644, 4656, 4668 and 4680 therefore stay
**unexamined**. 4400 and 4548 carry stronger, independent evidence from Findings 32 and 30
and are `assembly-matched`.

---

**Finding 32 — `-[PDPseudo initFromDeviceDescription:]` builds its `objc_super` with
`objc_getClass("IODevice")`.** `PDPseudo.m:80-84`.

Reference at 4474-4490:

```
4474: 8975F8       mov [ebp+var_8.receiver], esi
4477: 8B1504640000 mov edx, ds:stru_6400.super_class   ; PDPseudo's own super_class field
4483: 8955FC       mov [ebp+var_8.super_class], edx
4486: 8D45F8 50    lea eax,[ebp+var_8] / push eax
4490: E871EEFFFF   call _objc_msgSendSuper
```

`stru_6400 + 4` = 25604 = `__class` entry 2 (`PDPseudo`) field 1 (`super_class`). That is
what a plain `[super initFromDeviceDescription:…]` compiles to. Everything else in the
method matches instruction for instruction: the `_PseudoDeviceLoaded` guard at
4411/4420, `[self setName:"PDPseudo"]`, `[self setDeviceKind:"Server Device"]`, the
super send, the null test, `[self registerDevice]`, and the shared `[self free]` /
epilogue tail at 4524/4537.

**Our source** uses `super_struct.class = objc_getClass("IODevice");`.

**Difference:** a runtime name lookup where the compiler emits a static field load, and
it names the superclass explicitly instead of letting `super` do it.

**Disposition:** fix — write `[super initFromDeviceDescription:deviceDescription]` and
drop `struct objc_super` from the file.
**Rationale:** same defect part 1 recorded as Finding 17; listed here because the fix
touches `PDPseudo.m` and `PortServer.m` (three more sites: 5513, 5825, 6035) as well.

**Outcome (Task 8):** Fixed: `[super initFromDeviceDescription:deviceDescription]`; `struct objc_super`
and `<objc/objc-runtime.h>` are gone from the file. Ledger: 4400 **assembly-matched**, with
Finding 28.

---

**Finding 33 — `getState` and `setState:mask:` are declared in the wrong order.**
`PDPseudo.m:130` and `:145`; `PDPseudo.h:40` and `:41`.

Reference `imp` addresses are monotonically increasing in source order:
`acquire:` 4548, `release` 4560, **`setState:mask:` 4572, `getState` 4584**,
`watchState:mask:` 4596, `nextEvent` 4608, `executeEvent:data:` 4620,
`requestEvent:data:` 4632, `enqueueEvent:data:sleep:` 4644,
`dequeueEvent:data:sleep:` 4656, `enqueueData:…` 4668, `dequeueData:…` 4680.

Our file has `getState` (130) before `setState:mask:` (145); every other pair is in the
reference's order.

**Disposition:** fix. **Rationale:** cosmetic on its own, but it is the only remaining
ordering difference in the file and swapping two adjacent methods is free. Same class as
part 1's Finding 13.

**Outcome (Task 8):** Fixed: swapped in `.h` and `.m`, in its own commit (`1e23f5f1`, 14 insertions /
14 deletions). **This sets no ledger status** — declaration order is a link-order property,
not observable in either function's instruction stream.

---

### `PortServer.m`

**Finding 34 — `PortServer.m` contains two literal NUL bytes where `'\0'` was
intended.** `PortServer.m:192` (byte 5972) and `PortServer.m:224` (byte 6685).

Full evidence in §6 above. `file(1)` reports the source as `data`; a byte scan of all
six `.m` and six `.h` files in `PortServer.lksproj` finds NUL bytes in `PortServer.m`
and nowhere else, two of them, at exactly the two offsets the brief names. Both sit
between single quotes in a character constant inside
`-[PortServer initFromDeviceDescription:]`; site 1 is the `*device_name == '\0'` test
that the reference implements as `cmp byte ptr [eax], 0` at 5183, site 2 is the
`name_buffer[7]` terminator that the reference gets from the eighth byte of the
`"pdservd"` literal it copies at 5238-5253.

**Disposition:** fix — replace each raw `0x00` with the two ASCII characters `\` `0`.
**Rationale:** Task 7's whole purpose. The change is byte-for-byte reversible, restores
the file to ASCII, and alters no semantics.

**Outcome (Task 8):** Repaired ahead of the fix pass by Task 7 (`a48a9ba4`). `file(1)` now reports
`PortServer.m` as ASCII text and the byte scan finds zero NULs.

---

**Finding 35 — `PortServer`'s superclass is `Object` and it declares no ivars; the
reference is `IODevice` with one ivar `state` of type `ttyiops_state` at offset 264.**
`PortServer.h:15-18`.

Reference `__OBJC,__class[3]`:

```
name          -> PortServer
super_class   -> IODevice
instance_size -> 616
ivars         -> 1 entry:  state   {ttyiops_state=…}   offset 264
protocols     -> 0
```

The ivar's `@encode` string is 900+ characters and decodes to a struct beginning with an
embedded `struct tty` and continuing
`… "iops" @"IOPortSession" "rxThread" ^v "txThread" ^v "it_out" {termios…} "it_in"
{termios…} "dtr_down_time" {timeval…} "in_opens_pending" i "dcd_delay_ticks" i
"is_post_loaded" b1 "preempt" b1 "is_releasing" b1 "rx_blocked" b1
"has_audit_sleeper" b1 "kill_threads" b1 "is_timers_set" b1 "is_tx_enabled" b1
"is_rx_enabled" b1 "is_dcd_timer" b1 "is_dtr_delay" b1`.

That single declaration explains all three magic offsets our source hard-codes
(table in §5.2): `self + 0x108` is `&self->state`, `self + 0x1f0` is `self->state.iops`,
and `self + 0x264` is the byte holding the eleven `b1` bitfields — `is_post_loaded`
being bit 0, which is exactly the bit `getIntValues:`/`setIntValues:` read and write for
`"PortServerPLGandS"`.

**Disposition:** fix — `@interface PortServer : IODevice` with
`ttyiops_state state;` as its one ivar, and replace the three literal offsets with
`&state`, `state.iops` and `state.is_post_loaded`.
**Rationale:** largest structural finding in the file. `instance_size` 616 = 264
(`IODevice`) + 352 (`ttyiops_state`), and `ttyiops.h` in our tree already declares a
`ttyiops_state`, so the type exists. The hard-coded offsets are also what makes
Finding 40 (`ttyiops_attachDevice`) hard to see.

**Outcome (Task 8):** Applied in two halves. Part 2 applied the superclass (`@interface PortServer :
IODevice`) but **could not** apply the `ttyiops_state state;` ivar, because
`ttyiops_state` did not exist anywhere in this tree — this finding's rationale asserts that
`ttyiops.h` already declares it, and that is wrong (Section 13). Part 3 then decoded the
reference's ivar type string at address 27458, which names every field, cross-checked every
derived offset against the disassembly (`[edi+0E8h]`, `[ebx+154h]`, `[ebx+158h]`,
`[ebx+15Ch]`), declared `ttyiops_state` in `ttyiops.h` and gave `PortServer` its one ivar.
**`instance_size` is now 616, not 264, so the out-of-bounds writes at `self+0x1f0` and
`self+0x264` are gone**, and all three literal offsets in `PortServer.m` are replaced by
`state.iops`, `state.is_post_loaded` and `&state`. Not re-read from `__OBJC` after editing;
metadata, so it sets no ledger status. **Left undone:** `ttyiops.m` still addresses the same
fields through roughly 120 literal byte offsets (`((unsigned char *)tp)[0x15c]`,
`((id *)tp)[0xe8/4]`, …). No finding asks for that rewrite and it would swamp the pass's
substantive repairs, so it was deliberately not done; those offsets are now *documented* by
the type rather than unexplained.

---

**Finding 36 — the `addToCdevswFromDescription:…` argument list passes the *values* of
`extern int` objects where the reference passes function addresses and `cdevsw`
fields.** `PortServer.m:26-35` and `:79-92`.

**Reference** at 4712-4802, arguments in push order (reverse of declaration order):

```
4778: 68E0170000   push offset _portServeropen      ; immediate: address of a local function
4773: 6844180000   push offset _portServerclose     ; immediate
4754: 68A8180000   push offset _portServerioctl     ; immediate
4766: 8B1538810000 push ds:off_8138                 ; ttyiops_devsw.d_read   -> _ttyiops_read
4759: 8B153C810000 push ds:off_813C                 ; ttyiops_devsw.d_write  -> _ttyiops_write
4747: 8B1544810000 push ds:off_8144                 ; ttyiops_devsw.d_stop   -> _ttyiops_stop
4740: 8B1548810000 push ds:off_8148                 ; ttyiops_devsw.d_reset  -> _nulldev
4733: 8B1550810000 push ds:off_8150                 ; ttyiops_devsw.d_select -> _ttyiops_select
4726: 8B1554810000 push ds:off_8154                 ; ttyiops_devsw.d_mmap   -> _enodev
4719: 8B155C810000 push ds:off_815C                 ; ttyiops_devsw.d_getc   -> _enodev
4712: 8B1560810000 push ds:off_8160                 ; ttyiops_devsw.d_putc   -> _enodev
```

The three `push offset` forms are addresses of functions defined in this binary; the
eight `mov ds:off_81xx` forms are **loads of the fields of `_ttyiops_devsw`** (33072,
§5.4). The gap at `+0x28` (`d_strategy`, `_enodev_strat`) is skipped, which is exactly
what a member-by-member spelling of the eleven-argument selector produces.

**Our source**

```c
extern int portServeropen;   extern int ttyiops_read;   extern int nulldev;
extern int portServerclose;  extern int ttyiops_write;  extern int ttyiops_select;
extern int portServerioctl;  extern int ttyiops_stop;   extern int enodev;
…
        cdevswResult = objc_msgSend(cdevswResult,
                                    @selector(addToCdevswFromDescription:open:),
                                    deviceDescription,
                                    portServeropen, portServerclose,
                                    ttyiops_read,   ttyiops_write,
                                    portServerioctl, ttyiops_stop,
                                    &nulldev, ttyiops_select,
                                    &enodev, &enodev, &enodev);
```

**Difference, three separate defects:**

1. `portServeropen`, `portServerclose`, `portServerioctl`, `ttyiops_read`,
   `ttyiops_write`, `ttyiops_stop` and `ttyiops_select` are declared `extern int` and
   passed **by value**. Those symbols are functions. The expression `portServeropen`
   therefore reads the first four bytes of the function's machine code and passes that
   as the entry point. Every one of the seven is a garbage pointer.
2. `&nulldev` and `&enodev` pass the *address* of an `extern int`, where the reference
   passes the value of a `cdevsw` field which the linker has relocated to `_nulldev` /
   `_enodev`. Accidentally right in effect and wrong in form.
3. The selector is written `@selector(addToCdevswFromDescription:open:)` — a two-part
   selector with eleven extra arguments. `__meth_var_names` has no such selector; the
   real one is the full twelve-part
   `addToCdevswFromDescription:open:close:read:write:ioctl:stop:reset:select:mmap:getc:putc:`.
   The argument count (12 pushes: description plus eleven pointers) matches exactly.

Two further sends in this method have no counterpart in the reference:
`objc_msgSend(cdevswResult);` at `:93` and
`_portServerMajor = objc_msgSend(majorResult);` at `:98`, both with no selector. The
reference issues exactly four sends in `serverMajor:` — `[self class]`,
`addToCdevsw…`, `[self class]`, `characterMajor` (4802, 4811, 4834, 4843) — plus two for
the lock (4895, 4904). Ours issues six plus two.

**Disposition:** fix. **Rationale:** the driver cannot work. Its `cdevsw` entry is
installed with seven wild function pointers, so the first `open` of `/dev/ttyd*` jumps
into the middle of a function body. Largest behavioural finding in the file.

**Outcome (Task 8):** Applied: the seven `extern int` function declarations are gone, the selector is
the full twelve-part `addToCdevswFromDescription:open:close:read:write:ioctl:stop:reset:
select:mmap:getc:putc:`, each argument is cast to `IOSwitchFunc`, and both selectorless
sends are deleted. **Residual, still open:** the reference loads eight of the eleven
pointers out of `ttyiops_devsw`'s fields (`mov ds:off_81xx`) where we pass the same eight
functions by name. The values are identical; the spelling is not. Part 3 noted that
`ttyiops_devsw` now exists in the same file so the spelling *could* be changed, but declined
to overturn part 2's considered choice on part 2's own finding. **This is the one piece of
Finding 36 that is not closed.** Ledger: 4692 **control-flow-confirmed** — 4692 was re-read
in full after the edit and every send, push, store and branch is present and in order, but
it is held below `assembly-matched` for exactly this spelling.

---

**Finding 37 — `+[PortServer probe:]` issues five sends where the reference issues
three.** `PortServer.m:144-150`.

**Reference** at 5034-5075:

```
5034: 53                   push ebx                    ; deviceDescription
5035: 8B151C630000 52      push ds:paInitfromdevice
5042: 8B15C8620000 52      push ds:paAlloc
5049: 8B152C630000 52      push ds:paClass
5056: 56                   push esi                    ; self
5057: E83AECFFFF           call _objc_msgSend           ; [self class]
5062: 83C408 50            add esp,8 / push eax
5066: E831ECFFFF           call _objc_msgSend           ; [cls alloc]
5071: 83C408 50            add esp,8 / push eax
5075: E828ECFFFF           call _objc_msgSend           ; [obj initFromDeviceDescription:dd]
5080: 89C3                 mov ebx, eax
```

Three sends, result kept in `ebx`, then unlock, then `test ebx,ebx`.

**Our source** has the same first three plus
`portServerInit = objc_msgSend(portServerInit);` at `:149` and
`initResult = objc_msgSend(portServerInit);` at `:150`, both selectorless.

Everything else in the method matches: the `[self serverMajor:dd]` guard against −1
(4963-4983), `[IOPortSession iopsKernInit:dd]` (4985-5000), the
`do { } while ([_ttyiopsMapLock lock] != 0)` spin (5008-5032), the unlock (5082-5096),
and the 1/0 return (5105/5112).

**Disposition:** fix — delete the two extra sends.
**Rationale:** same defect as Finding 29; the two selectorless sends are live undefined
behaviour on the probe path.

**Outcome (Task 8):** Fixed: the two selectorless sends are deleted, the guard is
`portServerInit != nil`, and `objc_getClass` is replaced. **Not re-read after editing.**
Ledger: 4952 **unexamined**.

---

**Finding 38 — the TTY branch sets `deviceKind` to `"Port Device tty"`, not
`"Port Server"`.** `PortServer.m:254`.

**Reference**, the two `setDeviceKind:` sites:

```
PDPseudo branch, 5212:  68 5F3F0000  push offset aPortServer      ; 16223 "Port Server"
TTY branch,      5348:  68 A43F0000  push offset aPortDeviceTty   ; 16292 "Port Device tty"
```

**Our source** passes `"Port Server"` in both branches (`:214` and `:254`).

`"Port Device tty"` is also the parameter name `-getIntValues:forParameter:count:` matches
at 5742, so the string is load-bearing twice over: a caller does
`[dev getIntValues:… forParameter:"Port Device tty" …]` to fetch the `struct tty *`, and
the device advertises the same string as its kind so it can be found.

**Disposition:** fix. **Rationale:** the value is user-visible in `IODeviceMaster`
enumeration and it is a one-word change. Ours also introduces no new string, so
`__cstring` will match.

**Outcome (Task 8):** Fixed: the TTY branch's `deviceKind` is now `"Port Device tty"`. **Not re-read
after editing.** Ledger: 5128 **unexamined**.

---

**Finding 39 — the "no free slot" log message is
`"ttyiops: Couldn't create any more tty instances\n"`.** `PortServer.m:249`.

```
5333: 68 733F0000  push offset aTtyiopsCouldnT   ; 16243
5338: E821EBFFFF   call _IOLog
5343: E9D4000000   jmp  loc_15B8                 ; -> [self free]
```

Our source logs `"PortServer: Maximum number of devices exceeded"` — a string that does
not exist in the reference's `__cstring` at all (§5.1), and which lacks the trailing
`\n` every other `IOLog` in this binary carries.

**Disposition:** fix. **Rationale:** an invented string in a reconstruction is worse
than a missing one; it will show up as a spurious `__cstring` entry in any future
byte-comparison of the built driver.

**Outcome (Task 8):** Fixed: the message is now
`IOLog("ttyiops: Couldn't create any more tty instances\n")`, so `__cstring` no longer gains
an entry the reference does not have. **Not re-read after editing.** Ledger: 5128
**unexamined**.

---

**Finding 40 — `ttyiops_attachDevice` is called with one argument, `&self->state`; our
call site passes two, `(self, unit_index)`.** `PortServer.m:270`, and the prototype at
`ttyiops.h:36`.

**Reference** at 5442-5456, the whole call:

```
5442: 8B4508        mov  eax, [ebp+self]
5445: 0508010000    add  eax, 108h            ; &self->state
5450: 50            push eax                  ; ONE argument
5451: E8F00C0000    call _ttyiops_attachDevice
5456: 83C404        add  esp, 4               ; one 4-byte argument popped
```

`add esp,4` after the call settles the count: one argument, not two. And the callee
confirms the type — `_ttyiops_attachDevice` (8768) opens
`mov ebx,[ebp+arg_0]` then `mov dword ptr [ebx+120h],0` … `mov dword ptr [ebx+148h],2580h`
(9600, a baud rate), i.e. it writes `termios` fields at `state + 0x18` upward. It never
sends a message to its argument, so the argument is not an `id`.

**Our source**

```c
void ttyiops_attachDevice(id portServerObj, unsigned int unit);   /* ttyiops.h:36 */
…
        ttyiops_attachDevice(self, unit_index);                   /* PortServer.m:270 */
```

**Difference:** two arguments where there is one, and the first is typed `id` where the
reference passes a `ttyiops_state *`. The unit number the reference does not pass here;
it goes in via `[self setUnit:ebx]` at 5459 immediately afterwards, which our source also
does at `:274`.

**Disposition:** fix — `void ttyiops_attachDevice(ttyiops_state *state);` and
`ttyiops_attachDevice(&state);` at the call site.
**Rationale:** stack-corrupting mismatch between caller and callee. The prototype lives
in `ttyiops.h` and the definition in `ttyiops.m:206`, both outside my scope; I record the
call site, which is inside it, and flag the other two for whoever owns `ttyiops.m`.

**Outcome (Task 8):** Fixed, in two steps. Part 2 made the call site one-argument but cast it
`(struct tty *)`, which was **wrong** — `+0x108` is `&self->state`, and the offsets the
callee writes (0x120, 0xF4, 0x14C) are all past the end of `struct tty`'s 232 bytes. Part 3
corrected the cast to `ttyiops_state *` on the evidence of the reference's ivar `@encode` at
27458 (Section 13), and the call site is now simply `ttyiops_attachDevice(&state);`.
Declaration, definition and call site all agree. **Not re-read after editing.** Ledger: 5128
**unexamined**.

---

**Finding 41 — five hand-rolled byte-compare loops where the reference emits a
fixed-length `repe cmpsb`.** `PortServer.m:197-210`, `:367-380`, `:405-418`,
`:431-444`, `:492-505`.

Reference, all five sites, same shape:

```
5192: BE203F0000  mov  esi, offset aPdpseudo         ; 5128, "PDPseudo"
5197: 8B7DA0      mov  edi, [ebp+__s2]
5200: B909000000  mov  ecx, 9                        ; strlen + NUL
5205: FC          cld
5206: A800        test al, 0
5208: F3A6        repe cmpsb
5210: 7534        jnz  loc_1490

5634  mov edi, offset aPortserverplga  / mov ecx, 12h  ; 5620, "PortServerPLGandS", 17+1
5742  mov edi, offset aPortDeviceTty   / mov ecx, 10h  ; 5620, "Port Device tty",   15+1
5786  mov edi, offset aMaximumSession  / mov ecx, 11h  ; 5620, "Maximum Sessions",  16+1
5914  mov edi, offset aPortserverplga  / mov ecx, 12h  ; 5896
```

This is gcc's inline expansion of a constant-length compare against a string literal,
equivalent to `strcmp(x, "…") == 0` because the count includes the NUL.

**Our source** writes each one out:

```c
    cmp_len = 9;  match = 1;  p1 = device_name;  p2 = "PDPseudo";
    while (cmp_len > 0) {
        cmp_len--;
        if (*p1 != *p2) { match = 0; break; }
        p1++;  p2++;
    }
    if (match) { … }
```

**Difference:** behaviourally equivalent, structurally unrelated, and it emits a second
copy of each literal through the `p2` initialiser. The reference genuinely does call
`_strcmp` elsewhere in this same function — at 5306, on `iopsName` versus `device_name` —
so the source mixes an explicit `strcmp` with four literal comparisons the compiler
chose to expand; our `:239` already matches that one.

**Disposition:** fix — write all five as `strcmp(x, "…") == 0`. `PortServer.m:9` already
imports `<string.h>`.
**Rationale:** identical in kind to drvBPF's Finding 3, which was fixed the same way.
Note for the ledger: as in drvBPF, a `strcmp` call cannot be *proved* to compile back to
`repe cmpsb` without a compiler, so these three functions should be held at
`control-flow-confirmed` rather than advanced to `assembly-matched`.

**Outcome (Task 8):** Fixed, five sites: all five are now `strcmp(x, "…") == 0` and the
`cmp_len`/`match`/`p1`/`p2` locals are gone from three methods. Ledger: 5620 and 5896
**control-flow-confirmed** — exactly as this finding instructs, a `strcmp` call cannot be
shown to compile back to `repe cmpsb` without a compiler. 5128 is **unexamined** for
Findings 38/39/40's sake.

---

**Finding 42 — `_portServeropen`, `_portServerclose` and `_portServerioctl` live in the
wrong translation unit and their bodies are one-line pass-throughs; the reference bodies
implement the pseudo-device split.** `ttyiops.m:2185`, `:2194`, `:2203`;
`ttyiops.h:70-72`.

**Translation unit.** `__module_info` lists the seven modules in link order (§1);
`PortServer.m`'s functions occupy 4692–6575 and `IOPortSessionKern.m`'s start at 6576.
The three C functions sit at 6112, 6212 and 6312 — inside `PortServer.m`'s range, after
`-[PortServer state]` (6096) and before `+[IOPortSession iopsKernInit:]` (6576). They are
compiled from `PortServer.m`. In our tree they are in `ttyiops.m`.

**Bodies.** Ours:

```c
int portServeropen(unsigned int dev, int flag, int mode, struct proc *p)
{ return ttyiops_open(dev, flag, mode, p); }
```

The reference's, in full (6112–6210):

```
6116: 8B5508          mov  edx, [ebp+arg_0]          ; dev
6119: 31DB            xor  ebx, ebx                  ; rtn = 0
6123: 25C0000000      and  eax, 0C0h
6128: 3DC0000000      cmp  eax, 0C0h                 ; (dev & 0xC0) == 0xC0 ?
6133: 741D            jz   loc_1814                  ; pseudo device
6135-6147:            push arg_C, arg_8, arg_4, dev
6148: A130810000      mov  eax, ds:_ttyiops_devsw    ; d_open
6153: FFD0            call eax                       ; (*ttyiops_devsw.d_open)(dev,flag,mode,p)
6155: 89C3            mov  ebx, eax
6160: EB22            jmp  loc_1834
6164: 89D0 83E03F     mov eax,edx / and eax, 3Fh     ; minor = dev & 0x3F
6169: 7419            jz   loc_1834                  ; minor 0 -> rtn stays 0
6171: 50              push eax
6172-6185:            push @selector(iopsKernOpen:), IOPortSession class ref
6186: E8D1E7FFFF      call _objc_msgSend             ; [IOPortSession iopsKernOpen:minor]
6191: 89C3            mov  ebx, eax
6196: 53              push ebx
6197: E8C6E7FFFF      call _IOSetUNIXError           ; IOSetUNIXError(rtn)
6202: 89D8            mov  eax, ebx                  ; return rtn
```

`_portServerclose` (6212) is the same function with `d_close` (`off_8134`) and
`iopsKernClose:`. `_portServerioctl` (6312) is larger and does the same split, then for
the pseudo device dispatches on three ioctl commands:

```
6377: 81FE047054C0   cmp esi, 0C0547004h   -> copy [IOPortSession] name of _ttyiopsMap[minor]
                                              into data via strcpy (6445-6466), else ENXIO(6)
6484:                                      -> [IOPortSession iopsServerIoctlCommand:cmd data:data]
6496: 81FE037058C0   cmp esi, 0C0587003h   -> [IOPortSession iopsKernInitIoctl:minor data:data]
6516: 81FE027018C0   cmp esi, 0C0187002h   -> [IOPortSession iopsKernMsgIoctl:minor data:data]
default                                    -> 0x16 (EINVAL)
```

with a `_portServerMajor` check at 6394 (`movzx eax, byte ptr [ecx+51h]`; `cmp
ds:_portServerMajor, eax`) guarding the name lookup, and `_IOSetUNIXError` on every exit.

**Difference:** the whole body. Ours is `return ttyiops_open(...)`. The reference's
routes minor numbers with bits 6 and 7 set (`0xC0`, the value
`-[PortServer initFromDeviceDescription:]` assigns to the pseudo unit at 5233) to the
`IOPortSession` kernel-session layer and everything else to `ttyiops`, calls through the
`cdevsw` struct rather than naming `ttyiops_open` directly, and reports errors through
`IOSetUNIXError`. Our version has no pseudo-device path at all, which means
`/dev/rpski*` — the session device `iopsServerIoctlCommand:` hands out at 7048 — does
nothing.

**Disposition:** fix. **Rationale:** the second-largest behavioural finding in the
driver after Finding 36, and the reason five of the ten class methods in §7.3 currently
have no caller. Moving the three functions into `PortServer.m` also restores the
`__module_info` layout.

**Outcome (Task 8):** Deferred by part 2 — writing the bodies in `PortServer.m` alone would have
produced duplicate external definitions and deleting them from `ttyiops.m` was outside part
2's file scope — and then **applied in full by part 3**, which owns both files.
`portServeropen`, `portServerclose` and `portServerioctl` are deleted from `ttyiops.m` and
rewritten in `PortServer.m` with the reference bodies, all three `static`, matching the
reference's `local` binding. `portServerclose`'s signature widened to the four-argument
`open_close_fcn_t` shape. **`/dev/rpski*` now reaches the kernel session layer**, and the
five class methods part 2 reported as callerless (`iopsKernOpen:`, `iopsKernClose:`,
`iopsServerIoctlCommand:data:`, `iopsKernInitIoctl:data:`, `iopsKernMsgIoctl:data:`) all
have call sites. Ledger: 6112, 6212 and 6312 **control-flow-confirmed** — all three streams
were read in full, but *before* the bodies were written rather than after, and the
`strcpy`/`IOSetUNIXError` argument marshalling is compiler-dependent.

---

**Finding 43 — `forParameter:` and `count:` are typed `int` in both parameter
accessors.** `PortServer.m:352-354`, `:478-480`, `PortServer.h:49-55`.

Reference `__meth_var_types`:

```
getIntValues:forParameter:count:   i20@8:12^I16*20^I24
setIntValues:forParameter:count:   i20@8:12^I16*20I24
```

So: `parameterArray` is `unsigned int *` (`^I`), `parameterName` is `char *` (`*`,
`IOParameterName` decaying), `count` is `unsigned int *` for the getter and
`unsigned int` **by value** for the setter. The disassembly agrees: `getIntValues:`
writes `mov dword ptr [edx],1` through `arg_10` at 5681, while `setIntValues:` compares
`arg_10` directly with `cmp eax,1` at 5931.

**Our source** declares `forParameter:(int)parameter` in both and `count:(int)count` in
both, then casts inside the body (`param_str = (char *)parameter;`,
`*(unsigned int *)count = 1;`). The setter's `if (count == 1)` happens to be right
because it is by value there; the getter's casts are what hide the pointer/value split.

**Disposition:** fix — `(unsigned int *)values`, `(IOParameterName)parameterName`,
`(unsigned int *)count` for the getter and `(unsigned int)count` for the setter; delete
the casts.
**Rationale:** the casts currently make a real type error invisible; the encodings should
match anyway. Same shape as drvBPF's Finding 4.

**Outcome (Task 8):** Fixed: both accessors take `forParameter:(IOParameterName)parameterName`, the
getter `count:(unsigned int *)count` and the setter `count:(unsigned int)count`; the
internal casts are deleted. Ledger: 5620 and 5896 **control-flow-confirmed**. Part 2 read
5620 in full and would have called its non-`strcmp` half `assembly-matched`, and read 5896
to 5962 (`cmp eax,1` at 5931 confirms the setter's `count` is by value), but both are held
lower by the Finding 41 rewrite inside them.

---

**Finding 44 — `-[PortServer state]` returns `int`; the reference returns a
`ttyiops_state *`.** `PortServer.m:333-337`, `PortServer.h:47`.

Reference type string: `^{ttyiops_state={tty=…}@^v^v{termios=…}{termios=…}{timeval=ii}iib1b1b1b1b1b1b1b1b1b1b1}8@8:12`
— a pointer to the struct. Body (all 15 bytes) is `mov eax,[ebp+self]; add eax,108h`,
which is `return &self->state`.

Ours returns `(int)((char *)self + 0x108)`.

**Disposition:** fix, together with Finding 35 — `- (ttyiops_state *)state { return &state; }`.
**Rationale:** encoding-only at the instruction level, but the `int` return is what
forces the pointer cast, and the same cast is what obscured Finding 40.

**Outcome (Task 8):** Deferred by part 2 with Finding 35's ivar — declaring it `void *` would have
traded one wrong encoding for another — and applied by part 3 once `ttyiops_state` existed:
`- (ttyiops_state *)state { return &state; }`, replacing
`- (int)state { return (int)((char *)self + 0x108); }`. **Not re-read after editing.**
Ledger: 6096 **unexamined**.

---

**Finding 45 — six file-scope globals are not `static`; the reference has all six
`local`.** `PortServer.m:11-13`, `IOPortSessionKern.m:10-15`.

Reference nlist bindings (§5.5): `_ttyiopsMap`, `_ttyiopsMapLock`, `_pseudoUnit`,
`_mapLock`, `_numSessions`, `_nsPortKernIdMap` are all **`local`**. The binary does carry
`global` data symbols (`_ttyiops_speeds` in `__data`, `_PortServer_instance` in
`__common`), so `local` here reflects a real `static` in the source rather than
wholesale localisation by `kl_ld`.

Our `PortServer.m:11-13` and `IOPortSessionKern.m:10-15` declare all six without
`static`. `_PseudoDeviceLoaded` (`PDPseudo.m:10`) and `_portServerMajor`
(`PortServer.m:16`) are already `static` and already match.

**Disposition:** fix. **Rationale:** one keyword each; it also removes the cross-file
visibility that currently lets `ttyiops.m` reach `_ttyiopsMap` implicitly.

**Caveat, stated rather than glossed:** `_ttyiopsMap` and `_pseudoUnit` are read from
`_portServerioctl`, which belongs in `PortServer.m` (Finding 42) — so `static` is
consistent only once that move happens. `_ttyiopsMap` may also be needed by `ttyiops.m`;
I did not audit `ttyiops.m` and cannot confirm from the reference which file the
`_ttyiopsMap` references outside 4692–6576 come from.

**Outcome (Task 8):** Five of six applied: `static` was added to `_ttyiopsMapLock`, `_pseudoUnit`,
`_nsPortKernIdMap`, `_numSessions` and `_mapLock`, each confirmed by grep to have no
reference outside its defining file. **`_ttyiopsMap` is deliberately left non-`static`** —
`ttyiops.m` reads it in ten places through `ttyiops.h`'s `extern`, so `static` is a link
error today, exactly as this finding's own caveat says. Part 3 hit the same wall on
`_portServerMajor` (Section 14) and made the same call. **Both acceptances are on data
symbols, which have no ledger entry**, so they are recorded here and nowhere else.

---

**Finding 46 — `PortServer.m:101` has a raw newline inside a string literal.**

```c
101            IOLog("Port Server: Can't find space in devsw
102  ");
```

Byte 0x0A appears between the quotes. That is a hard C error ("missing terminating `"`
character"). The reference's string is `__cstring` 16183,
`"Port Server: Can't find space in devsw\n"`, pushed at 4861.

**Disposition:** fix — `"Port Server: Can't find space in devsw\n"`.
**Rationale:** compile blocker. Task 7 should take this with the two NUL bytes; it is
the same corruption (an escape sequence written as the byte it denotes) applied to `\n`
instead of `\0`.

**Outcome (Task 8):** Repaired ahead of the fix pass by Task 7 (`a48a9ba4`).

---

**Finding 47 — `_protocols_102` is built from the address of a `Protocol *` variable;
the reference stores `@protocol(PortDevices)` itself.** `PortServer.m:19-23`.

Reference `_protocols.102` at 32880 is two words: `{ 26816, 0 }`. 26816 is one of the
four 20-byte structs in `__OBJC,__protocol`, and its `protocol_name` field points at
`"PortDevices"`. `+[PortServer requiredProtocols]` (4940, 12 bytes) is
`mov eax, offset _protocols_102` and nothing else, and its type `^@8@8:12` matches our
`+ (id *)requiredProtocols` exactly.

**Our source**

```c
extern Protocol *objc_protocol_PortDevices;
Protocol *_protocols_102[] = { &objc_protocol_PortDevices, NULL };
```

**Difference:** an extra level of indirection — the array holds `&(a Protocol *)`, not a
`Protocol *`. Every reader of `requiredProtocols` will dereference garbage.

**Disposition:** fix — `Protocol *_protocols_102[] = { @protocol(PortDevices), 0 };`
and drop the `extern`.
**Rationale:** part 1's Finding 21 records the same substitution at
`conformsTo:`'s call site; this is the data-definition half of it. The
`@protocol(PortDevices)` form requires the `PortDevices` protocol declaration to be in
scope, which `IOPortSession.h` should provide once Finding 21 lands.

**Outcome (Task 8):** Fixed: `_protocols_102` is now `{ @protocol(PortDevices), 0 }`; the
`extern Protocol *objc_protocol_PortDevices;` and the extra `&` are gone. **Not re-read
after editing** — the change is to the data definition rather than to the 12-byte function.
Ledger: 4940 **unexamined**.

---

### `IOPortSessionKern.m`

**Finding 48 — ten class methods are declared as instance methods.**
`IOPortSessionKern.h:66,81,96,104,112,124,133,138,144,155` and
`IOPortSessionKern.m:159,207,317,422,460,529,583,752,757,776`.

Full treatment in §7 — the split table, the per-method evidence that nine of the ten
never load the receiver at all and the tenth uses it only as a message target, and the
complete list of call sites.

**Disposition:** fix — change all twenty `-` markers to `+`.
**Rationale:** the largest finding in this file and one of the two largest in the pass.
Four existing call sites already send these selectors to the class object
(`objc_getClass("IOPortSession")` twice in `PortServer.m`, twice in this file), so with
the current `-` declarations they raise "does not recognize selector" the first time the
driver probes. Five more sites appear when Finding 42 is fixed.

The category declaration itself, `@implementation IOPortSession (IOPortSessionKern)`
at `:29`, is **correct** and needs no change — `__OBJC,__category[1]` names exactly this
category on exactly this class, and the file name in `__module_info` is
`IOPortSessionKern.m`.

**Outcome (Task 8):** Applied in full — the largest repair in pass 2's range. All ten declarations in
`IOPortSessionKern.h` and all ten in `IOPortSessionKern.m` are now `+`; the four accessors
from 8512 stay `-`; all five existing send sites are class-directed. Ledger: 6576, 6792,
6900, 6912, 7232, 7948, 8180 and 8432 **assembly-matched** — each was re-read in full after
editing and §7.2's claim independently re-confirmed (6900, 6912, 7232, 8432, 7948, 8180 and
6576 never reference `[ebp+arg_0]`; 6792 loads it at 6797 only to push it as the receiver at
6820). 7312 and 7440 are **unexamined**: they were not re-read.

---

**Finding 49 — the four value accessors carry a leading underscore the reference does
not have.** `IOPortSessionKern.h:25,35,45,55` and `IOPortSessionKern.m:40,68,96,125`.

Reference `__cat_inst_meth`, read directly:

```
- getIntValues:forParameter:count:    i20@8:12^I16*20^I24   imp 8512
- getCharValues:forParameter:count:   i20@8:12*16*20^I24    imp 8576
- setIntValues:forParameter:count:    i20@8:12^I16*20I24    imp 8640
- setCharValues:forParameter:count:   i20@8:12*16*20I24     imp 8704
```

No underscore on any of the four. Our selectors are `_getIntValues:forParameter:count:`
and so on.

The bodies otherwise match instruction for instruction. All four are the same 61-byte
shape:

```
8515: 8B4508      mov  eax, [ebp+self]
8518: 83780400    cmp  dword ptr [eax+4], 0     ; self->_priv
8522: 7409        jz   -> return -706
8524: 8B4004      mov  eax, [eax+4]
8527: 8B00        mov  eax, [eax]               ; *(id *)_priv
8529: 85C0 750B   test eax,eax / jnz -> forward
8533: B83EFDFFFF  mov  eax, 0FFFFFD3Eh          ; -706
…
8544-8564:        push count, parameterName, values, @selector(…), receiver; call objc_msgSend
```

which is exactly our `(*(int *)((char *)self + 4) != 0) && (**(int **)((char *)self + 4) != 0)`
guard and forward, and −706 for both failures. Offset 4 is `IOPortSession`'s `_priv`
ivar (part 1, Finding 15); the first word of whatever `_priv` points at is the device
object.

**Disposition:** fix — drop the four underscores.
**Rationale:** these are the DriverKit parameter-protocol selectors. With the underscore
they are never called: `IODevice`'s parameter machinery looks up
`getIntValues:forParameter:count:` by name. Same defect as part 1's Finding 12, which
records the identical underscore prefix on the four `IOPortSession(Private)` methods —
the two findings should be fixed together so the naming convention across the driver
comes out consistent.

**Outcome (Task 8):** Fixed: the four leading underscores are dropped, and the parameter types were
also brought to the encodings this finding itself quotes (`char *` for the char pair,
`IOParameterName` for the name, `unsigned int *` / `unsigned int` for get/set `count`) —
slightly beyond the finding's literal disposition, recorded as such, and behaviour-neutral
because the bodies only forward. Ledger: 8512 **assembly-matched** — re-read in full after
editing: the `[self+4]` guard, the `*_priv` load, `-706` on either failure and a five-push
forward. 8576, 8640 and 8704 are **unexamined**: this finding states they are the same
61-byte shape but they were not re-read.

---

**Finding 50 — `_nsPortKernStateMap` does not exist; the reference has one 512-byte
array of 8-byte `{ id session; int inUse; }` slots.** `IOPortSessionKern.m:10-11`, and
every index expression in the file.

**Reference.** `_nsPortKernIdMap` is at 33188 and `__bss` ends at 33700, so the array is
exactly **512 bytes**. `+iopsKernInit:` and `+iopsKernFree` both `bzero` it with a length
of `0x200` (6714/6872). IDA names the address four bytes past its start `dword_81A8`,
and every access in the file is one of two forms:

```
+iopsKernOpen: 7239   cmp ds:dword_81A8[ebx*8], 0            ; slot[i].inUse
+iopsKernOpen: 7256   cmp ds:_nsPortKernIdMap[ebx*8], 0      ; slot[i].session
+iopsKernOpen: 7295   mov ds:_nsPortKernIdMap[ebx*8], eax

+iopsKernInit: 6729   mov ds:dword_81A8, 1                   ; slot[0].inUse = 1

+iopsServerIoctlCommand: 6998  mov eax, offset _nsPortKernIdMap
                        7004  cmp dword ptr [eax+ebx*8+4], 0 ; slot[i].inUse
                        7036  mov ds:dword_81A8[ebx*8], 1

+iopsKernClose: 8440  lea ebx, ds:0[edx*8]
                8447  lea esi, _nsPortKernIdMap[ebx]
                8453  cmp dword ptr [esi+4], 0               ; slot[i].inUse
                8459  cmp ds:_nsPortKernIdMap[ebx], 0        ; slot[i].session
                8493  mov dword ptr [esi+4], 0

+iopsKernInitIoctl: 7321  mov edx, ds:_nsPortKernIdMap[edi*8]
+iopsKernMsgIoctl:  7455  mov edx, ds:_nsPortKernIdMap[eax]  (eax = i*8)
```

`dword_81A8` is `_nsPortKernIdMap + 4`, indexed with the same `*8` stride. There is one
array, 64 slots of 8 bytes, each `{ id session; int inUse; }`. `iopsKernInit:` reserving
`slot[0].inUse = 1` is what keeps minor 0 out of the pool.

**Our source**

```c
id   _nsPortKernIdMap[64]    = { NULL };   /* 256 bytes */
char _nsPortKernStateMap[128] = { 0 };     /* 128 bytes */
…
    portObject = *(id *)((char *)_nsPortKernIdMap + sessionId * 8);
    if (_nsPortKernStateMap[sessionId * 2] != 0) …
    bzero(&_nsPortKernIdMap, 0x200);
```

**Difference, and it is a memory-safety bug, not a cosmetic one.** Our
`_nsPortKernIdMap` is 64 `id`s = **256 bytes**, but every access uses an 8-byte stride,
so `sessionId` 32 and above reads and writes past the end of the array — and the
`bzero(&_nsPortKernIdMap, 0x200)` at `:444` and `:500` zeroes 512 bytes over a 256-byte
object, clobbering `_nsPortKernStateMap` and whatever follows it. `"Maximum Sessions"` in
`Default.table` is `16`, so the overrun is not reached with the shipped configuration,
but the code caps at 64 (`+iopsKernInit:` 6681) and a larger table triggers it
immediately.

**Disposition:** fix — one array of 64 elements of a two-member struct, and delete
`_nsPortKernStateMap` entirely. Every `_nsPortKernStateMap[i * 2]` becomes
`map[i].inUse`, every `*(id *)((char *)_nsPortKernIdMap + i * 8)` becomes
`map[i].session`, and both `bzero` lengths become `sizeof map`.
**Rationale:** the second-largest finding in this file. It also removes a global that has
no counterpart in the reference at all, which a byte-level comparison of `__bss` would
otherwise flag forever.

**Outcome (Task 8):** Applied in full: one `static nsPortKernSlot _nsPortKernIdMap[64]` of
`{ id session; int inUse; }` = 512 bytes, `_nsPortKernStateMap` deleted, every
`_nsPortKernStateMap[i * 2]` became `map[i].inUse`, every
`*(id *)((char *)_nsPortKernIdMap + i * 8)` became `map[i].session`, and both `bzero`
lengths became `sizeof _nsPortKernIdMap`. **This removes the 256-byte-array /
512-byte-`bzero` overrun.** Ledger: 6576, 6792, 6912, 7232 and 8432 **assembly-matched** —
all five re-read after editing, with the `*8` stride and the `+0`/`+4` field split
unambiguous in each. 7312 and 7440 stay **unexamined** for Finding 48's reason.

---

**Finding 51 — `_numSessions` is initialised to −1; the reference leaves it
uninitialised.** `IOPortSessionKern.m:14`.

`_numSessions` is at 33184 in **`__bss`** (§5.5). A C object with an explicit non-zero
initialiser goes in `__data`; `__bss` means the reference wrote `static int _numSessions;`
with no initialiser, so it starts at **0**, not −1. −1 is only ever written by
`+iopsKernInit:`'s error path (6617, `mov ds:_numSessions, 0FFFFFFFFh`).

Our `int _numSessions = -1;` would be emitted into `__data`, and it changes behaviour
before `iopsKernInit:` runs: `+iopsKernFree` (6802, `cmp ds:_numSessions, ebx; jl`) and
`+iopsServerIoctlCommand:` (6990, same test) both branch on `_numSessions >= 0`, and with
−1 they skip their loops where the reference runs one iteration over slot 0.

**Disposition:** fix — `static int _numSessions;` (see also Finding 45 for the `static`).
**Rationale:** small, but it is a section-placement difference the binary states
directly, and it changes two branch outcomes. The `/* -1 if not initialized */` comment
should go with it.

**Outcome (Task 8):** Fixed: `static int _numSessions;` with no initialiser, so it lands in `__bss` at
0 as the reference does. Ledger: 6792 and 6912 **assembly-matched** — both branch on
`cmp ds:_numSessions, ebx` with `ebx = 0`, so the code now runs one iteration over slot 0
before `iopsKernInit:`, as the reference does.

---

**Finding 52 — the enqueue and dequeue retry loops test the wrong condition.**
`IOPortSessionKern.m:231` and `:346`.

**Reference**, `+iopsKernDequeue:msg:` (8180). `[ebp+var_804]` is the `transferCount`
out-parameter, `esi` is the `bufferSize` passed to `dequeueData:`:

```
8221: 837B0C00      cmp dword ptr [ebx+0Ch], 0   ; msg->remaining
8225: jz  -> return 0
8231: 837B0400      cmp dword ptr [ebx+4], 0     ; msg->result
8235: jnz -> return 0
8241: 8DBD00F8FFFF  lea edi, [ebp+var_800]       ; kernel buffer, set ONCE, outside the loop
8248: 39B5FCF7FFFF  cmp [ebp+var_804], esi       ; <-- loop head: transferCount vs bufferSize
8254: jnz -> return 0
8260: 8B730C        mov esi, [ebx+0Ch]           ; chunk = msg->remaining
8263-8271:          if (chunk > 0x800) chunk = 0x800
8276-8283:          min = msg->minCount; if (min > chunk) min = chunk
…
8407: 837B0400      cmp dword ptr [ebx+4], 0
8411: jz  -> 8248   (back edge)
```

So the loop continues while `transferCount == bufferSize` — i.e. while the session
handed back everything it was asked for — **and** `msg->remaining != 0` **and**
`msg->result == 0`. On the first pass both `transferCount` and `bufferSize` are 0, so the
test admits entry. `+iopsKernEnqueue:msg:` (7948) has the identical head at 8012
(`cmp [ebp+var_804], ebx`, `ebx` being the `bufferSize` it passed).

**Our source**, both methods:

```c
        /* Loop while no data was transferred (retry until we get something) */
        while (transferCount == 0) {
```

**Difference:** ours continues only while **nothing** was transferred; the reference
continues only while **everything** was transferred. Those are opposite conditions. With
ours, a session that returns a partial transfer exits the loop immediately and the
remaining bytes are silently dropped; a session that returns nothing spins forever.

**Disposition:** fix.
**Rationale:** behavioural, on the bulk read/write path, in both directions.

**Honest limit on this one.** I am confident about the *machine* condition
(`transferCount == bufferSize`, read straight off 8012 and 8248 with the register
provenance traced) but not about the exact C the reference source spelled. gcc rotated
both loops, and `+iopsKernEnqueue:` additionally expresses its "refill the kernel buffer"
test as a **pointer** comparison — `edi` is initialised to `ebp` (7989), one past the end
of the 2048-byte buffer at `[ebp-0x800]`, and 8024 does `cmp edi, ebp; jnb` to decide
whether to `copyin` again — where our `:348` uses a `remainingInBuffer == 0` counter. The
two agree for every reachable input I traced, and the `sub ebx, [ebp+var_804]` fallback
at 8028 is provably unreachable (it is only entered when `transferCount == bufferSize`,
which forces `ebx` to 0). I record the machine behaviour and leave the exact source form
to Task 8.

Everything else in both methods matches: the `0x800` chunk cap, `copyin`/`copyout`
argument order, the `0x16` return on a copy fault (7-instruction tail at 8076 and 8365),
the `msg->total += n` / `msg->ubuf += n` / `msg->remaining -= n` triple, and dequeue's
`if (n < msg->minCount) msg->minCount -= n; else msg->minCount = 0;` at 8372-8398.
Dequeue reuses the buffer from its start on every pass (`edi` set once at 8241) and
enqueue advances `edi` by the transfer count (8120) — our source has both.

**Outcome (Task 8):** Fixed, and one step further on the enqueue side. Both loops now continue while the
session handed back everything it was asked for (`while (transferCount == chunkSize)`, with
`chunkSize` initialised to 0 so the first pass still runs). **This finding's claim that our
counter-based refill test and the reference's pointer test agree on every reachable input is
false once the loop condition is corrected** (Section 13): above 2048 bytes a full 0x800
pass would take the `else` branch and call `enqueueData:` with `bufferSize:0` where the
reference refills. The reference's pointer test was therefore transcribed literally —
`kernelBufPtr` starts one past the end of the buffer and the refill test is
`kernelBufPtr >= kernelBuffer + sizeof kernelBuffer` — with `chunkSize -= transferCount` as
the `sub ebx, [var_804]` fallback. Ledger: 7948 and 8180 **assembly-matched**, both re-read
in full after editing.

---

**Finding 53 — `+iopsServerIoctlCommand:data:` writes `*(int *)data` only when a
conforming device was found.** `IOPortSessionKern.m:817`.

Reference, command `0xC0047000`:

```
7181: 84C0          test al, al            ; conformsTo: result
7183: 759F          jnz  loc_1BB0          ; -> 7088
…
7088: 8B5514 891A   mov edx,[ebp+arg_C] / mov [edx], ebx    ; *(int *)data = objectNumber
7093: EB63          jmp loc_1C1A                            ; -> return edi (0)
…
7202: BF06000000    mov edi, 6                              ; ENXIO, data untouched
```

The store at 7091 is reached only from the `conformsTo:` success branch.

**Our source** stores unconditionally after the loop and then decides the return value:

```c
        /* Update object number in data */
        *(int *)data = objectNumber;

        if (lookupResult != -0x2c0) return 0;
        return 6;
```

**Difference:** on the not-found path ours overwrites the caller's `objectNumber` with
the exhausted cursor. The caller is `_portServerioctl` at 6484 and the value goes back to
user space, so the caller's enumeration cursor is corrupted on the terminating call.

Everything else matches: the `if (n < -1) n = -1` clamp (7105-7110), the `-704`
(`0xFFFFFD40`) sentinel from `lookupByObjectNumber:instance:`, `@protocol(PortDevices)`
as the `conformsTo:` argument (7157, `offset stru_68D4` = 26836 — see part 1's Finding
21), and the command `0x40547001` path in full: `[_mapLock lock]` returning non-zero →
`4`, the free-slot scan, `slot[i].inUse = 1`, `sprintf(data, "/dev/rpski%02d", i)`,
`6` when the pool is exhausted, and `[_mapLock unlock]` on every exit.

**Disposition:** fix — move the store inside the success branch.
**Rationale:** small, concrete, and it is on the path `pdservd` uses to enumerate port
devices.

**Outcome (Task 8):** Fixed: the store happens only on the `conformsTo:` success path and the not-found
path returns 6 with `data` untouched. Ledger: 6912 **assembly-matched** — re-read in full;
`mov [edx], ebx` at 7091 is reachable only from the success branch, and the `< -1 -> -1`
clamp, the -704 sentinel, the `0x40547001` free-slot path and the `[_mapLock unlock]` on
every exit are all present.

---

**Finding 54 — `IOPortSessionKern.m:472` has a raw newline inside a string literal; the
file does not compile.**

```c
472            IOLog("IOPortSessionKern: Invalid Config Table
473  ");
```

Byte 0x0A between the quotes, confirmed with `od -c`. The reference's string is
`__cstring` 16350, `"IOPortSessionKern: Invalid Config Table\n"`, pushed at 6607.

**Disposition:** fix — `"IOPortSessionKern: Invalid Config Table\n"`.
**Rationale:** compile blocker, and the same corruption as Finding 46. With Findings 27,
46 and 54 outstanding, three of the six `.m` files in `PortServer.lksproj` fail to build
(`AppleIOPSSafeCondLock.m` is the fourth, part 1's Finding 1). **Nothing in this driver
compiles today**, which is worth stating plainly because it bounds what any later
verification step can claim.

**Outcome (Task 8):** Repaired ahead of the fix pass by Task 7 (`7c7f4c19`).

---

**Finding 55 — `objc_getClass("…")` where the reference has ordinary class
references.** `IOPortSessionKern.m:506`, `:707`, `:727`, `:765`, `:797`;
`PortServer.m:106`, `:134`, `:260`, `:448`; `PDPseudo.m:39` (see Finding 29).

The reference's `__OBJC,__cls_refs` is 24 bytes — six entries — holding `NXLock`,
`AppleIOPSSafeCondLock`, `NXConditionLock`, `PDPseudo`, `IOPortSession` and `IODevice`.
Every class-directed send in this scope loads one of them:

```
6753  ds:paAppleiopssafec   +iopsKernInit:            [AppleIOPSSafeCondLock alloc]
7283  ds:paIoportsession    +iopsKernOpen:            [IOPortSession alloc]
7136  ds:paIodevice         +iopsServerIoctlCommand:  [IODevice lookupByObjectNumber:instance:]
7879  ds:paIoportsession    +iopsKernMsgIoctl:        [IOPortSession iopsKernEnqueue:/Dequeue:]
4993  ds:paIoportsession    +[PortServer probe:]      [IOPortSession iopsKernInit:]
5409  ds:paIoportsession    -[PortServer initFrom…]   [IOPortSession alloc]
5855  ds:paIoportsession    -[PortServer getIntValues…] [IOPortSession iopsKernNumSess]
4888  ds:paAppleiopssafec   +[PortServer serverMajor:] [AppleIOPSSafeCondLock alloc]
4357  ds:paPdpseudo_0       +[PDPseudo probe:]        [PDPseudo alloc]
```

There is **no** `_objc_getClass` in the import list (§ imports, 41200-41400) — the
reference never calls it. Every one of our `objc_getClass("…")` sites therefore has no
counterpart at all.

**Disposition:** fix — plain bracket syntax with the class named directly.
**Rationale:** part 1 recorded this as Finding 17 for `IOPortSession.m`; recorded again
here because it is ten more sites across all three of my files, and because the
`objc_getClass` route is what currently masks Finding 48 (a name lookup succeeds where a
compile-time class reference plus an instance-method selector would at least be visible
to the reader).

**Outcome (Task 8):** Fixed: all ten sites in `PDPseudo.m`, `PortServer.m` and `IOPortSessionKern.m`
are gone, and a grep for `objc_msgSend|objc_getClass|objc_super` over those three files now
returns nothing. Ledger: as the individual functions above.

---

### Cross-file

**Finding 56 — none of the three files declares its `@interface` against the right
runtime headers.** `PDPseudo.h:9`, `PortServer.h:9`, `IOPortSessionKern.h:11`.

All three import `<objc/Object.h>` (directly or through `IOPortSession.h`) and
`<objc/objc-runtime.h>`, and use `objc_msgSend`/`objc_msgSendSuper`/`objc_getClass`
explicitly throughout. The reference imports `.objc_class_name_IODevice`,
`.objc_class_name_NXConditionLock`, `.objc_class_name_NXLock`,
`.objc_class_name_Object` and `.objc_class_name_Protocol`, and calls `_objc_msgSend` /
`_objc_msgSendSuper` only as the compiler's own expansion of bracket syntax.

**Disposition:** fix, as the natural consequence of Findings 28, 32, 35, 47 and 55 rather
than as a change in its own right.
**Rationale:** grouped here so Task 8 does not treat the header edits as five unrelated
changes. Once bracket syntax replaces the hand-written sends, `<objc/objc-runtime.h>`
can come out of all three files.

**Outcome (Task 8):** Fixed: `<objc/objc-runtime.h>` removed from all three `.m` files;
`<objc/Object.h>` replaced by `<driverkit/IODevice.h>` in `PDPseudo.h` and `PortServer.h`
and added to `IOPortSessionKern.h`; `<driverkit/IODeviceParams.h>` added to
`IOPortSessionKern.m` and `ttyiops.h` / `AppleIOPSSafeCondLock.h` / `IOPortSessionKern.h` to
`PortServer.m`. Build-time only; it sets no ledger status.

---

**Finding 57 — `Default.table` differs from Apple's in five places.**
`src/drvPortServer/PortServer.drvproj/Default.table`.

Apple's table (616 bytes, read from the reference `.config` bundle) against ours:

| line | ours | reference |
|---|---|---|
| — | *(absent)* | `"Version" = "5.00";` |
| 10 | `"Support DialIn"` | `"Support Dialin"` |
| 10 | comment `/* … (ttyof..) */` | `/* … (ttyd*) */` |
| 11 | comment `/* … (cuA) */` | `/* … (cu*) */` |
| 12 | `"PortServer_Main.rtf"` | `"PortServer_Main.rtfd"` |
| — | *(absent)* | `"Driver Version" = "PROGRAM:PortServer  PROJECT:drvPortServer-14  DEVELOPER:root  BUILT:Sat Mar 28 22:30:53 PST 1998";` |

Every other key matches exactly, including `"Maximum Sessions" = "16"`, which is the one
key this binary actually reads.

**Disposition:** fix the `Dialin` capitalisation and the `.rtfd` extension; **accept**
the two absent keys. **Rationale:** `"Version"` and `"Driver Version"` are build-stamp
metadata generated by Apple's build (`"Driver Version"` embeds a 1998 build date and a
project number), and reproducing them verbatim would be a lie about provenance —
drvBPF made the same call for `_BPF_VERS_STRING`. The `Dialin` key and the help-file
extension are content, not stamps, and should match.

**Honest limit:** see Section 8. I could not find any consumer of `"Support Dialin"` in this
driver or anywhere in `src/`, so I cannot demonstrate that the capitalisation causes a
behavioural difference. The case for fixing it is fidelity to the shipped table.

**Outcome (Task 8):** Applied as specified: `"Version" = "5.00";` added, `Support DialIn` ->
`Support Dialin`, the three trailing comments corrected to `ttyd*` / `cu*`, `.rtf` ->
`.rtfd`, and `Localizable.strings` line 1 rekeyed to `"PortServer"`. The transposed
dialin/dialout comments are preserved as Apple wrote them. **`"Driver Version"` is
deliberately not added** — it embeds Apple's 1998 build host, date and project number, and
reproducing it verbatim would misstate provenance; drvBPF made the same call for
`_BPF_VERS_STRING`. A diff against the reference bundle now shows that one line as the only
difference in `Default.table`, and `Localizable.strings` as byte-identical. **No behavioural
consequence is claimed for the `Support Dialin` capitalisation** — the string occurs in no
file under `src/` and in none of the three shipped binaries. **This acceptance has no ledger
entry** (config data, not a function) and is recorded only here.

---

### Finding 58 — `ttyiops_speeds` is a `struct speedtab[]`, not a flat `int[]`

**Reference** (`__DATA,__data` 32888–33071, 184 bytes, 23 pairs, read from the
file image at offset 35284, and the sole consumer at `_ttyiops_param`+61):

```
 13100: 6878800000  push offset _ttyiops_speeds
 13105: 8B4E28      mov  ecx, [esi+28h]           ; t->c_ospeed
 13109: E8C6CCFFFF  call _ttspeedtab              ; ttspeedtab(c_ospeed, ttyiops_speeds)
```

```
 { 0, 0 },             { 50, 100 },           { 75, 150 },         { 110, 220 },
 { 134, 269 },         { 150, 300 },          { 200, 400 },        { 300, 600 },
 { 600, 1200 },        { 1200, 2400 },        { 1800, 3600 },      { 2400, 4800 },
 { 4800, 9600 },       { 9600, 19200 },       { 19200, 38400 },    { 38400, 76800 },
 { 57600, 115200 },    { 115200, 230400 },    { 230400, 460800 },  { 460800, 921600 },
 { 921600, 1843200 },  { 1843200, 3686400 },  { -1, -1 }
```

**Our source** (`ttyiops.m:37–62`):

```c
int ttyiops_speeds[] = {
    0, 50, 75, 110, 134, 150, 200, 300, 600, 1200, 1800, 2400, 4800,
    9600, 19200, 38400, 7200, 14400, 28800, 57600, 76800, 115200, 230400, -1
};
```

**Difference.** Wrong element type (scalar vs. `{sp_speed, sp_code}` pair), wrong
length (24 vs. 46 words), and wrong contents. The reference's `sp_code` is always
exactly `2 * sp_speed` (including B134 → 269, i.e. 134.5 baud doubled), which is
the half-bit-time unit the `PD_E_DATA_RATE` event (0x33) takes. Our table also
invents four rates the reference does not carry (7200, 14400, 28800, 76800 as
*speeds*) and omits 460800, 921600 and 1843200. Passed to `ttspeedtab()` as it
stands, our table is read as pairs anyway and yields garbage codes for every rate.

**Disposition: fix.** Replace with a `struct speedtab ttyiops_speeds[]` carrying
the 23 pairs above verbatim. `struct speedtab` is declared in `<sys/tty.h>`.

**Outcome (Task 8):** Fixed: the flat `int[24]` is replaced by the 23 `{ sp_speed, sp_code }` pairs;
the invented rates (7200, 14400, 28800, and 76800-as-a-speed) are gone and 460800, 921600
and 1843200 are restored. Ledger: the table's sole consumer lies inside 13040, which is
**assembly-matched** on Findings 62 and 63's evidence; the 184 data bytes themselves were
taken from this finding's decode rather than re-read from the file image, so this finding's
own evidence is no stronger than `control-flow-confirmed`.

---

### Finding 59 — `_dtrDownDelay` is absent; the 2-second DTR-down delay is inlined

**Reference:** see Section 5.6 (12659–12716). Both halves of a file-scope
`struct timeval` at 16604 are added to `tp->[0x14c]`/`[0x150]` before the
microsecond carry.

**Our source** (`ttyiops.m:843–853`):

```c
target_time.tv_sec  = ((long *)tp)[0x14c/sizeof(long)];
target_time.tv_usec = ((long *)tp)[0x150/sizeof(long)];
target_time.tv_sec += 2;                 /* <- inlined constant */
if (target_time.tv_usec > 999999) { ... }
```

**Difference.** The constant is not carried as data, and the `tv_usec` addend
(which is 0, so runtime behaviour is identical) is dropped. Byte-level fidelity
requires the object, because `ttyiops_init` loads from two absolute addresses
16604 and 16608.

**Disposition: fix.** Add at file scope:

```c
static const struct timeval dtrDownDelay = { 2, 0 };
```

and use `target_time.tv_sec += dtrDownDelay.tv_sec; target_time.tv_usec +=
dtrDownDelay.tv_usec;`. Runtime behaviour is unchanged; this is a fidelity fix.

**Outcome (Task 8):** Fixed: `static const struct timeval dtrDownDelay = { 2, 0 };` at file scope, and
`ttyiops_init` adds both halves. Runtime behaviour unchanged. Evidence:
`control-flow-confirmed` — 12659–12698 was re-read. Ledger: 12260 is
**intentional-mismatch**, on Finding 80's account rather than this one.

---

### Finding 60 — `ttyiops_devsw` is absent from our source entirely

**Reference:** `__DATA,__data` 33072, 56 bytes, decoded slot by slot in Section 5.7.

**Our source:** no `cdevsw` initialiser anywhere in `ttyiops.m`. Our
`portServeropen`/`portServerclose`/`portServerioctl` wrappers
(`ttyiops.m:2185–2206`) exist and correspond to reference `_portServeropen`
(6112), `_portServerclose` (6212), `_portServerioctl` (6312), but the table those
wrappers are installed alongside is missing.

**Difference.** A 56-byte static `struct cdevsw`, `static`-linkage, referenced
once from `_portServeropen`+37 (reference address 6149). Without it the driver
cannot register a character device.

**Disposition: fix.** Add the definition exactly as written in Section 5.7, at file
scope in `ttyiops.m`, before `portServeropen`. Coordinate with part 2's finding
on `_portServeropen`, which is what consumes it.

**Outcome (Task 8):** Applied. The 14 slots are §5.7's decode, spelled with `conf.h`'s own
`eno_*` macros, `(reset_fcn_t *)nulldev` for `d_reset`, literal `0` for `d_ttys` and
`D_TTY` for `d_type`. Data transcribed from the relocation table, not re-read from the
file image; it sets no ledger status.

The Task 8 pass first put the definition in `PortServer.m`, `static`, arguing that the
symbol was `local` and so a definition in `ttyiops.m` would be unreachable from the
wrappers Finding 42 moved into `PortServer.m`. **That rationale was backwards and the
placement has been corrected: the definition is now in `ttyiops.m`, non-`static`, declared
`extern struct cdevsw ttyiops_devsw;` in `ttyiops.h`, and `PortServer.m` only references
it.** See Section 13's `N_PEXT` bullet for the symbol-table evidence. In short:
`_ttyiops_devsw` is one of the reference's five `N_PEXT` symbols — non-`static` in Apple's
source — while all seven `ttyiops_*` entry points whose addresses it takes are `0x0e`,
i.e. genuinely `static`. A static function's address can only be taken inside its own
translation unit, so the table had to be defined in `ttyiops.m`, and non-`static`
precisely so `PortServer.m` could name it. The 14 slot values are unchanged by the move.

---

### Finding 61 — `ttyiops_attachDevice` has the wrong signature and does work the reference does not

**Reference** (8768, IDA size 119; the brief's 120 includes one padding byte):

```
 8774: 8B5D08              mov  ebx, [ebp+arg_0]                  ; only one argument
 8777: C7832001000000000000 mov dword ptr [ebx+120h], 0
 8787: C7832401000000000000 mov dword ptr [ebx+124h], 0
 8797: C78328010000004B0000 mov dword ptr [ebx+128h], 4B00h
 8807: C7832C01000000000000 mov dword ptr [ebx+12Ch], 0
 8817: C7834801000080250000 mov dword ptr [ebx+148h], 2580h
 8827: C7834401000080250000 mov dword ptr [ebx+144h], 2580h
 8837: 8DB320010000        lea  esi, [ebx+120h]
 8843: 56                  push esi
 8844: E86FDDFFFF          call _termioschars                     ; termioschars(tp + 0x120)
 8849: 8DBBF4000000        lea  edi, [ebx+0F4h]
 8855: FC / B90B000000 / F3A5   cld; mov ecx,0Bh; rep movsd       ; 44 bytes, +0x120 -> +0xF4
 8863: 6A08 / 81C34C010000 / 53 / E853DDFFFF  bzero(tp + 0x14C, 8)
```

and its only call site, in `-[PortServer initFromDeviceDescription:]`:

```
 5442: 8B4508              mov  eax, [ebp+self]
 5445: 0508010000          add  eax, 108h
 5450: 50                  push eax
 5451: E8F00C0000          call _ttyiops_attachDevice              ; one argument
 5456: 83C404              add  esp, 4
```

**Our source** (`ttyiops.m:206–245`):

```c
void ttyiops_attachDevice(id portServerObj, unsigned int unit)
{
    if (portServerObj == NULL || unit > 25) return;
    _ttyiopsMap[unit] = portServerObj;
    tp = (struct tty *)((char *)portServerObj + 0x108);
    ...
    termioschars(&tp->t_termios);
```

**Difference.** Four separate problems.
1. The reference takes **one** parameter, the already-offset `struct tty *`. The
   caller does the `+ 0x108`.
2. The `_ttyiopsMap[unit] = portServerObj` store is not in this function. The
   relocation survey shows `_ttyiopsMap` written only from
   `-[PortServer initFromDeviceDescription:]` (reference 5271, 5292, 5586).
3. The `portServerObj == NULL || unit > 25` guard has no counterpart in the
   reference; there is no test of `arg_0` at all.
4. `termioschars(&tp->t_termios)` targets `tp + 0x8C`, but the reference passes
   `tp + 0x120` — the *default* termios that lines 224–229 just filled in, not
   the live one. As written our code initialises one structure and defaults a
   different one.

**Disposition: fix.** Reduce to `void ttyiops_attachDevice(struct tty *tp)`, drop
the guard and the map store, and pass `(struct termios *)((char *)tp + 0x120)` to
`termioschars`. The map store belongs in `PortServer.m` — flag it to whoever owns
part 2's `initFromDeviceDescription:` finding rather than silently deleting it.

**Outcome (Task 8):** Fixed, with part 2's cast corrected. `ttyiops.h`, `ttyiops.m` and `PortServer.m`
now all agree on `void ttyiops_attachDevice(ttyiops_state *state)` called as
`ttyiops_attachDevice(&state)`. **This finding's own spelling, `struct tty *`, is wrong**
(Section 13): the offsets the callee writes — 0x120 `it_in`, 0xF4 `it_out`, 0x14C
`dtr_down_time` — are all past the end of `struct tty`'s 232 bytes. The body drops the
`portServerObj == NULL || unit > 25` guard and the `_ttyiopsMap[unit] = portServerObj` store
(which stays in `PortServer.m`, where the reference puts it) and passes `&state->it_in` to
`termioschars`, which the reference's `lea esi,[ebx+120h]` settles. Ledger: 8768
**assembly-matched** — re-read in full after editing.

---

### Finding 62 — `c_cc[VSTART]`/`c_cc[VSTOP]` are indexed as `c_cc[7]`/`c_cc[8]`

**Reference** (`_ttyiops_param`, and again in `_ttyiops_control_ioctl` and
`_ttyiops_ioctl`):

```
 13062: F6460106     test byte ptr [esi+1], 6          ; c_iflag & (IXON|IXOFF)
 13068: 807E1CFF     cmp  byte ptr [esi+1Ch], 0FFh     ; c_cc[12] == VSTART
 13078: 807E1DFF     cmp  byte ptr [esi+1Dh], 0FFh     ; c_cc[13] == VSTOP
...
 13502: 0FB6461C     movzx eax, byte ptr [esi+1Ch]     ; VSTART -> event 0xED
 13533: 0FB6461D     movzx eax, byte ptr [esi+1Dh]     ; VSTOP  -> event 0xE9
```

`struct termios` puts `c_cc` at offset 0x10, so 0x1C is `c_cc[12]` = `VSTART`
and 0x1D is `c_cc[13]` = `VSTOP`.

**Our source** (`ttyiops.m:1354`, `:1358`, `:1488`, `:1492`):

```c
if (t->c_cc[7] == (unsigned char)-1)  return 0x16;   /* comment says VSTART */
if (t->c_cc[8] == (unsigned char)-1)  return 0x16;   /* comment says VSTOP  */
...
objc_msgSend(portSession, @selector(executeEvent:data:), 0xed, t->c_cc[7]);
objc_msgSend(portSession, @selector(executeEvent:data:), 0xe9, t->c_cc[8]);
```

**Difference.** `c_cc[7]` is offset 0x17 (an unused spare slot) and `c_cc[8]` is
0x18 (`VINTR`). Four sites. The driver would validate the wrong characters and
program `^C` as the XOFF character.

**Disposition: fix.** Use `t->c_cc[VSTART]` and `t->c_cc[VSTOP]` at all four
sites (`<sys/termios.h>` defines them as 12 and 13).

**Outcome (Task 8):** Fixed, four sites: `t->c_cc[7]`/`[8]` -> `t->c_cc[VSTART]`/`[VSTOP]`. Ledger:
13040 **assembly-matched** — the full stream was read and compared statement by statement
against the finished function.

---

### Finding 63 — every `ttyiops_param` failure path returns `EINVAL`, not the message result

**Reference.** `var_8` is set to `0x16` on entry (13055) and to `0` only on the
success path (13654). Every one of the six failure branches jumps to the single
epilogue at 13661, which returns `var_8`:

```
 13055: C745F816000000  mov  [ebp+var_8], 16h        ; the only other write is 0 at 13654
 13164: 0F85EB010000    jnz  13661                   ; data-rate  (0x33) failed
 13270: 0F8581010000    jnz  13661                   ; char size  (0x3B) failed
 13333: 0F8542010000    jnz  13661                   ; parity     (0x43) failed
 13389: 0F850A010000    jnz  13661                   ; stop bits  (0xF3) failed
 13496: 0F859F000000    jnz  13661                   ; flow ctrl  (0x53) failed
 13569: 755A            jnz  13661                   ; XON|XOFF   (0xED/0xE9) failed
 13661: 8B45F8          mov  eax, [ebp+var_8]
```

**Our source** (`ttyiops.m:1413`, `:1430`, `:1443`, `:1482`, `:1496`):

```c
result = (int)objc_msgSend(portSession, @selector(executeEvent:data:), 0x3b, char_size);
if (result != 0) {
    return result;                 /* <- returns the IOPortSession status */
}
```

and worst of all at line 1495:

```c
if ((xon_char_result | xoff_char_result) != 0) {
    return result;                 /* <- `result` is 0 here: returns SUCCESS on failure */
}
```

**Difference.** Five sites return an IOPortSession status (a large negative
`kern_return_t`-style value) where the reference returns `EINVAL`; the sixth
returns 0 — reporting success — when programming the XON/XOFF characters fails.
`ttyiops_param` is `t_param`, so its return value goes straight into `ttioctl`
and out to userland as an `errno`.

**Disposition: fix.** Replace all six with `return 0x16;`. Only the data-rate
branch at line 1381 is already correct.

**Outcome (Task 8):** Fixed, five sites: the char-size, parity, stop-bit, flow-control and XON/XOFF
branches all `return 0x16;`. **The last of the five was returning `result`, which is 0 at
that point — it reported success on failure.** Ledger: 13040 **assembly-matched**.

---

### Finding 64 — `ttyiops_param` is called only when `ttioctl` returns > 0

**Reference:**

```
 10852: 8945FC          mov  [ebp+var_4], eax        ; error = l_ioctl(...)
 10858: 85C0            test eax, eax
 10860: 0F8DC1000000    jge  11059                   ; >= 0 -> straight to optimiseInput
...
 11031: 8945FC          mov  [ebp+var_4], eax        ; error = ttioctl(...)
 11037: 85C0            test eax, eax
 11039: 7C27            jl   11080                   ; < 0 -> modem-ioctl switch
 11041: 7E10            jle  11059                   ; == 0 -> skip ttyiops_param
 11043: 8D878C000000    lea  eax, [edi+8Ch]
 11049: 50 / 57         push eax; push edi
 11051: E8C0070000      call _ttyiops_param          ; only reached when ttioctl > 0
 11059: 8D878C000000    lea  eax, [edi+8Ch]          ; ttyiops_optimiseInput(tp, &tp->t_termios)
```

**Our source** (`ttyiops.m:1559`, `:1668–1675`):

```c
if (error >= 0) {
    goto update_and_return;
}
...
update_and_return:
    if (error > 0) {
        ttyiops_param(tp, (struct termios *)&((unsigned char *)tp)[0x8c]);
    }
    ttyiops_optimiseInput(tp, (struct termios *)&((unsigned char *)tp)[0x8c]);
```

**Difference.** The reference's `jge 11059` from the *line discipline* result
lands past `ttyiops_param`. Ours funnels both paths through `update_and_return`,
so a line discipline `l_ioctl` that returns a positive value re-programs the
hardware — the reference never does that.

**Disposition: fix.** Split the two joins: the `l_ioctl >= 0` path must jump to
the `ttyiops_optimiseInput` call, and only the `ttioctl > 0` path may call
`ttyiops_param` first.

**Outcome (Task 8):** Fixed: the `l_ioctl >= 0` path jumps past the `ttyiops_param` call and only the
`ttioctl > 0` path calls it. Ledger: 10676 is **intentional-mismatch**, on Finding 67's
account; this finding's own evidence is `assembly-matched` — the full 636-byte stream was
read and every branch target in the epilogue region checked against the finished labels.

---

### Finding 65 — `l_ioctl` is called through a NULL guard the reference does not have

**Reference** (10824–10852): the `linesw` slot is loaded and called with no test.

```
 10824: 8B4760       mov  eax, [edi+60h]
 10827: C1E005       shl  eax, 5
 10844: 8B8010000000 mov  eax, ds:_linesw[eax]      ; +0x10 == l_ioctl
 10850: FFD0         call eax
```

**Our source** (`ttyiops.m:1552–1556`):

```c
if (linesw[((int *)tp)[0x60/4]].l_ioctl) {
    error = linesw[...].l_ioctl(tp, cmd, data, flag, p);
} else {
    error = -1; // ENOTTY
}
```

**Difference.** The guard and the `-1` fallback are invented. Functionally the
fallback happens to reach the same `< 0` branch, so this is fidelity only — but
it is the same pattern as F79 and should be fixed with it.

**Disposition: fix.** Call unconditionally.

**Outcome (Task 8):** Fixed: `l_ioctl` is now called unconditionally, matching 10824–10850. Ledger:
10676 **intentional-mismatch**, per Finding 67; this finding's own evidence is
`assembly-matched`.

---

### Finding 66 — the control-device path returns early, skipping the shared cleanup

**Reference:**

```
 10784: F645F8C0     test byte ptr [ebp+var_8], 0C0h
 10788: 7422         jz   10824
 10808: E89BFEFFFF   call _ttyiops_control_ioctl
 10813: 8945FC       mov  [ebp+var_4], eax
 10816: E9CA010000   jmp  11279                     ; -> shared cleanup, not a return
...
 11279: 81A78C000000FFF1FFFF  and dword ptr [edi+8Ch], 0FFFFF1FFh   ; t_iflag &= ~0xE00
 11289: 81A794000000FFFFFCFF  and dword ptr [edi+94h], 0FFFCFFFFh   ; t_cflag &= ~0x30000
 11299: 8B45FC                mov eax, [ebp+var_4]
```

**Our source** (`ttyiops.m:1547–1549`):

```c
if ((dev & 0xc0) != 0) {
    return ttyiops_control_ioctl(tp, dev, cmd, data, flag, p);
}
```

**Difference.** The reference clears the software-flow-control bits from
`t_iflag` and the hardware-flow bits from `t_cflag` on *every* exit from
`ttyiops_ioctl`, including the control-device one. Ours skips them, leaving
whatever `ttyiops_convertFlowCtrl` set visible to the next `TIOCGETA`.

**Disposition: fix.** Store into `error` and `goto cleanup_and_return`.

**Outcome (Task 8):** Fixed: `ttyiops_control_ioctl`'s result is stored into `error` and jumps to the
shared cleanup, so the `t_iflag &= ~0xE00` and `t_cflag &= ~0x30000` run on that exit too.
Ledger: 10676 **intentional-mismatch**, per Finding 67; this finding's own evidence is
`assembly-matched`.

---

### Finding 67 — the `tp == NULL` path also falls through the cleanup, and dereferences NULL

**Reference:**

```
 8966/10765: 85FF           test edi, edi
 10767:      750F           jnz  10784
 10769:      C745FC06000000 mov  [ebp+var_4], 6           ; ENXIO
 10776:      E9F2010000     jmp  11279                    ; -> cleanup, with edi == 0
 11279:      81A78C000000FFF1FFFF  and dword ptr [edi+8Ch], 0FFFFF1FFh
```

**Our source** (`ttyiops.m:1542–1544`):

```c
if (tp == NULL) {
    return 6; // ENXIO
}
```

**Difference.** The reference jumps into the shared epilogue with `edi == 0` and
faults on `[edi+0x8C]`. This is a genuine, reachable Apple bug: any ioctl on a
minor whose `_ttyiopsMap` slot is empty panics the kernel. Our source's early
return is strictly safer.

**Disposition: accept.** Keep our early `return 6;` and do not reproduce the
NULL dereference. Recorded here so the divergence is deliberate and documented
rather than an oversight; the ledger entry for `_ttyiops_ioctl` should carry it
as an intentional mismatch.

**Outcome (Task 8):** **Accepted, not fixed.** Our early `return 6;` on `tp == NULL` stays. Reproducing
the reference here would import a reachable kernel NULL dereference: it jumps from 10776
into the epilogue at 11279 with `edi == 0` and faults on `[edi+8Ch]` on any ioctl against an
empty `_ttyiopsMap` slot. Ledger: 10676 **intentional-mismatch**, reviewer Pat Raynor, with
that reason recorded on the entry. The rest of 10676 (Findings 64, 65, 66 and 68)
transcribes the reference, which is why the entry was walked up through `assembly-matched`
before being accepted.

---

### Finding 68 — `TIOCSETA*` validation reads `data[7]` instead of `data[0x1c]`

**Reference** (10988–10998, inside the `0x802C7414/15/16` case):

```
 10988: 80791CFF   cmp byte ptr [ecx+1Ch], 0FFh     ; ((struct termios *)data)->c_cc[VSTART]
 10992: 7406       jz  11000                        ;   -> EINVAL
 10994: 80791DFF   cmp byte ptr [ecx+1Dh], 0FFh     ; ->c_cc[VSTOP]
 10998: 750C       jnz 11012
 11000: C745FC16000000  mov [ebp+var_4], 16h
```

**Our source** (`ttyiops.m:1588`):

```c
if (((char *)data)[7] == -1 || ((char *)data)[0x1d] == -1) {
```

**Difference.** The first offset is 7, not 0x1C. Byte 7 is the top byte of
`c_oflag`; the second offset is already right, which makes the first look like a
transcription slip rather than a deliberate choice.

**Disposition: fix.** `((char *)data)[0x1c]`.

**Outcome (Task 8):** Fixed: `((char *)data)[7]` -> `((char *)data)[0x1c]`, matching
`cmp byte ptr [ecx+1Ch], 0FFh` at 10988. Ledger: 10676 **intentional-mismatch**, per
Finding 67; this finding's own evidence is `assembly-matched`.

---

### Finding 69 — the same `data[7]` slip in `ttyiops_control_ioctl`

**Reference** (10591–10601):

```
 10591: 807E1CFF   cmp byte ptr [esi+1Ch], 0FFh
 10595: 7406       jz  10603
 10597: 807E1DFF   cmp byte ptr [esi+1Dh], 0FFh
 10601: 7509       jnz 10612
 10603: B816000000 mov eax, 16h
```

**Our source** (`ttyiops.m:658`):

```c
if (((char *)data)[7] == -1 || ((char *)data)[0x1d] == -1) {
    return 0x16; // EINVAL
}
```

**Difference and disposition.** Identical to F68: `[7]` must be `[0x1c]`.
**fix.**

**Outcome (Task 8):** Fixed: the same edit in `ttyiops_control_ioctl`, matching
`cmp byte ptr [esi+1Ch], 0FFh` at 10591. **10456's stream was not read** — the four
instructions quoted here are unambiguous, but nothing more than that is claimed. Ledger:
10456 **unexamined**.

---

### Finding 70 — `ttyiops_open` never calls `l_modem`

**Reference** (9164–9218):

```
 9164: F7C720000000  test edi, 20h                  ; dev & 0x20
 9170: 751A          jnz  9198                      ;   -> call l_modem
 9172: 8B15D8620000  mov  edx, ds:paGetstate
 9186: E819DCFFFF    call _objc_msgSend             ; [session getState]
 9194: A840          test al, 40h                   ; carrier?
 9196: 7417          jz   9221                      ;   no  -> skip l_modem
 9198: 8B55FC        mov  edx, [ebp+var_4]          ; tp
 9201: 8B4260        mov  eax, [edx+60h]            ; t_line
 9204: C1E005        shl  eax, 5
 9207: 6A01          push 1
 9209: 52            push edx
 9210: 8B801C000000  mov  eax, ds:_linesw[eax]      ; +0x1C == l_modem
 9216: FFD0          call eax                       ; (*l_modem)(tp, 1)
 9221: F7C720000000  test edi, 20h                  ; continue to the DCD wait
```

**Our source** (`ttyiops.m:1987–1998`):

```c
if ((dev & 0x20) != 0) {
    goto line_discipline_open;          /* <- skips l_modem entirely */
}
state = (unsigned int)objc_msgSend(((id *)tp)[0xe8/4], @selector(getState));
if ((state & 0x40) != 0) {
    goto line_discipline_open;          /* <- and again */
}
```

**Difference.** The reference calls `(*linesw[tp->t_line].l_modem)(tp, 1)` when
the open is non-blocking *or* carrier is already asserted, and only then falls
into the DCD-wait check. Ours branches past it to the thread-creation block. The
line discipline is therefore never told that carrier is up on a fast open, so
`TS_CARR_ON` is never set and the first `read()` blocks forever.

**Disposition: fix.** Restore the call, with the reference's exact control flow:
both conditions fall *into* the `l_modem` call, and only the
`carrier-absent && blocking` case skips it.

**Outcome (Task 8):** Fixed: both the `dev & 0x20` and the `getState & 0x40` tests now fall *into*
`(*linesw[tp->t_line].l_modem)(tp, 1)`, and only the carrier-absent blocking case skips it.
**This is the fix that makes `TS_CARR_ON` get set on a fast open.** Ledger: 8888
**assembly-matched** — the full 594-byte stream was read, including the 9164–9246 region
this edit rewrites.

---

### Finding 71 — `ttyiops_open`'s CLOCAL test indexes the wrong halfword

**Reference** (9233–9244):

```
 9233: 8B55FC              mov edx, [ebp+var_4]
 9236: 6683BA9400000000    cmp word ptr [edx+94h], 0
 9244: 7C7A                jl  9368                   ; CLOCAL set -> skip the wait
```

**Our source** (`ttyiops.m:2004`):

```c
if ((((short *)tp)[0x94/4] & 0x8000) == 0) {
```

**Difference.** `0x94/4` is 37, so `((short *)tp)[37]` is the halfword at byte
offset **74**, not 0x94 (148). The correct index is `0x94/2`. The same expression
is written correctly elsewhere in the file (`ttyiops.m:270`, `:289`, `:324`,
`:1123`), which makes this a local slip. The reference's `jl` is also a plain
signed test, not an explicit `& 0x8000`.

**Disposition: fix.** `if (((short *)tp)[0x94/2] >= 0) { /* wait for DCD */ }`.

**Outcome (Task 8):** Fixed: `((short *)tp)[0x94/4] & 0x8000` -> `((short *)tp)[0x94/2] >= 0`. The old
expression read byte offset 74, not 148. Ledger: 8888 **assembly-matched**.

---

### Finding 72 — `ttyiops_read`'s RTS-flow flag is at 0x15C, not 0x57

**Reference** (10083–10102):

```
 10083: F6835C01000008  test byte ptr [ebx+15Ch], 8
 10090: 7429            jz   10133
 10092: 8B03            mov  eax, [ebx]                ; t_rawq.c_cc
 10094: 034320          add  eax, [ebx+20h]            ; + t_canq.c_cc
 10097: 3D7B030000      cmp  eax, 37Bh
 10102: 7F1D            jg   10133
```

**Our source** (`ttyiops.m:1835`):

```c
if ((((unsigned char *)tp)[0x57] & 8) != 0) {
```

**Difference.** Byte offset 0x57 instead of 0x15C. 0x15C is the driver's private
flag byte used consistently everywhere else in this file (`ttyiops.m:316`, `:442`,
`:483`, `:510`, `:814`, `:945`, `:995`, …); 0x57 lands inside `t_canq`. As
written, the RTS re-assert after a read is driven by a byte of queue state.

**Disposition: fix.** `((unsigned char *)tp)[0x15c] & 8`.

**Outcome (Task 8):** Fixed: `[0x57]` -> `[0x15c]`, matching `test byte ptr [ebx+15Ch], 8` at 10083.
Ledger: 9972 **control-flow-confirmed** — only the tail (10061–10143) was read, not the
whole 172-byte function.

---

### Finding 73 — `ttyiops_getData`'s three flag tests are all at 0x15C, not 0x57

**Reference** (14265, 14307, 14320, 14329):

```
 14265: F6865C01000020  test byte ptr [esi+15Ch], 20h     ; RX suspended -> return
 14307: 80895C01000008  or   byte ptr [ecx+15Ch], 8       ; no space -> set flow-off
 14320: F6815C01000008  test byte ptr [ecx+15Ch], 8
 14329: 80A15C010000F7  and  byte ptr [ecx+15Ch], 0F7h    ; clear flow-off
```

**Our source** (`ttyiops.m:111`, `:125`, `:130`, `:131`):

```c
if (((unsigned char *)tp)[0x57] & TTY_STATE_RXFULL)  { return; }
...
((unsigned char *)tp)[0x57] |= TTY_STATE_RXFLOWOFF;
if (((unsigned char *)tp)[0x57] & TTY_STATE_RXFLOWOFF) {
    ((unsigned char *)tp)[0x57] &= ~TTY_STATE_RXFLOWOFF;
}
```

**Difference.** Same as F72, three more sites, plus the `#define` comments at
`ttyiops.m:83–84` that document 0x57. Bit values (0x20, 0x08) are right; only the
byte offset is wrong.

**Disposition: fix.** All three to 0x15C, and correct the two `#define` comments.

**Outcome (Task 8):** Fixed, four sites plus two `#define` comments: `[0x57]` -> `[0x15c]` at the
RX-suspended test, the flow-off set, the flow-off test and the flow-off clear. Ledger: 14248
**assembly-matched** — the full 309-byte stream was read.

---

### Finding 74 — `ttyiops_txload`'s transfer size collapses to the queue count

**Reference** (15076–15114):

```
 15076: B8A0010000     mov  eax, 1A0h
 15081: 81FA9F010000   cmp  edx, 19Fh                  ; edx = space reported by event 0x23
 15087: 7702           ja   15091                      ;   space > 0x19F -> keep 0x1A0
 15089: 89D0           mov  eax, edx                   ;   else eax = space
 15091: 89C2           mov  edx, eax                   ; edx = min(space, 0x1A0)
 15104: 8B8558FEFFFF   mov  eax, [ebp+var_1A8]         ; outq count
 15110: 39D0           cmp  eax, edx
 15112: 7E02           jle  15116                      ;   outq <= edx -> keep outq
 15114: 89D0           mov  eax, edx                   ;   else eax = edx
 15116: 50             push eax                        ; q_to_b(..., min(outq, space, 0x1A0))
```

**Our source** (`ttyiops.m:1057–1066`):

```c
transfer_size = 0x1a0;
if (buffer_space < 0x1a0) transfer_size = buffer_space;
if ((int)transfer_size < (int)outq_size) transfer_size = outq_size;
else                                     transfer_size = outq_size;
```

**Difference.** The final `if`/`else` assigns `outq_size` in both branches, so
the whole clamp is dead and `transfer_size` is always `outq_size`. With
`buffer[416]` on the stack and a queue that can hold far more, `q_to_b` overruns
the local buffer. This is a stack smash, not a cosmetic issue.

**Disposition: fix.**

```c
transfer_size = 0x1a0;
if (buffer_space < 0x1a0)          transfer_size = buffer_space;
if (outq_size   < transfer_size)   transfer_size = outq_size;
```

**Outcome (Task 8):** Fixed: the dead `if/else` that assigned `outq_size` in both arms is now
`if ((int)outq_size < (int)transfer_size) transfer_size = outq_size;`, so the transfer is
`min(outq, space, 0x1A0)`. **This closes the 416-byte stack smash.** Ledger: 14952
**assembly-matched** — re-read in full after editing.

---

### Finding 75 — `ttyiops_txFunc` passes a code address as the `timeout` delay

**Reference** (15532–15557):

```
 15532: 808B5D01000002  or   byte ptr [ebx+15Dh], 2
 15539: 8B9358010000    mov  edx, [ebx+158h]            ; the tick count ttyiops_init computed
 15545: 52              push edx
 15546: 53              push ebx
 15547: 68843B0000      push offset _ttyiops_dcddelay   ; 0x3B84 == 15236
 15552: E83BC3FFFF      call _timeout
```

**Our source** (`ttyiops.m:1264`):

```c
timeout((timeout_func_t)ttyiops_dcddelay, tp, 0x3b84);
```

**Difference.** `0x3B84` is the *address* of `_ttyiops_dcddelay` (15236), which
the decompiler emitted twice — once correctly as the function argument and once
as the delay. The real delay is `((int *)tp)[0x158/4]`, i.e. the
`(hz + 50) / 100` value `ttyiops_init` stores at `ttyiops.m:818`. At `hz == 100`
that is 2 ticks (~20 ms); `0x3B84` is 15236 ticks, over two minutes.

**Disposition: fix.** `timeout((timeout_func_t)ttyiops_dcddelay, tp, ((int *)tp)[0x158/4]);`

**Outcome (Task 8):** Fixed: `0x3b84` (the address of `_ttyiops_dcddelay`) replaced by
`((int *)tp)[0x158/4]`. Ledger: 15316 **control-flow-confirmed** — 15490–15600 was read, not
the whole 411-byte function.

---

### Finding 76 — `ttyiops_mctl`'s break-control block is absent from our source (and dead in the reference)

**Reference** (13685–13837):

```
 13688: 8B4D0C          mov  ecx, [ebp+arg_4]
 13691: 83E106          and  ecx, 6                       ; bits &= 6
 13694: 894DF8          mov  [ebp+var_8], ecx
 13714: E869CAFFFF      call _objc_msgSend                ; var_4 = [session getState]
 13722: 8B55F8          mov  edx, [ebp+var_8]
 13725: 81E200080000    and  edx, 800h                    ; (bits & 6) & 0x800  -- always 0
 13734: 85D2            test edx, edx
 13736: 746A            jz   13844                        ; always taken
 13738: 8D56FF          lea  edx, [esi-1]                 ; how - 1
 13741: 83FA01          cmp  edx, 1
 13744: 7762            ja   13844                        ; only how == 1 or 2
 13746: 83FE01          cmp  esi, 1
 13749: 0F94C2          setz dl                           ; on = (how == 1)
 13761: 6A01 ... 68F9000000  push 1; push on; push 0F9h
 13789: E81ECAFFFF      call _objc_msgSend                ; [session enqueueEvent:0xF9 data:on sleep:1]
 13797: 837DFC00        cmp  [ebp+var_4], 0
 13801: 741F            jz   13834
 13803: 6A01 / 6890D00300 / 6A4B  push 1; push 3D090h; push 4Bh
 13829: E8F6C9FFFF      call _objc_msgSend                ; [session enqueueEvent:0x4B data:250000 sleep:1]
 13834: 8B45FC          mov  eax, [ebp+var_4]
 13837: E994000000      jmp  13990                        ; return on
```

**Our source** (`ttyiops.m:524–586`): the block does not exist; the function goes
straight from `bits &= 6` and `getState` into the `switch (how)`.

**Difference.** 100 bytes of the reference are missing. They implement break
control: `ttyiops_ioctl` maps `TIOCSBRK` (0x2000747B) to `ttyiops_mctl(tp, 0x800,
1)` and `TIOCCBRK` (0x2000747A) to `ttyiops_mctl(tp, 0x800, 2)`, and this block is
what would service them — event 0xF9 to set/clear break, plus event 0x4B with
0x3D090 = 250000 (µs, i.e. a 0.25 s minimum break) when asserting.

It is **unreachable**: `var_8 = arg_4 & 6`, so `var_8 & 0x800` is identically
zero and the `jz` at 13736 always fires. Apple's `bits &= 6` on entry strips the
0x800 break bit before it is tested, so `TIOCSBRK`/`TIOCCBRK` silently do nothing
on shipped Rhapsody. That is a real Apple bug, faithfully preserved in the
binary.

**Disposition: fix.** Reproduce the block, including the `bits &= 6` that kills
it, with a comment recording that it is dead and why. Runtime behaviour is
unchanged; this restores 100 bytes of the translation unit and documents the
upstream defect rather than silently "improving" on it. Do **not** move or widen
the mask — that would change behaviour.

**Outcome (Task 8):** Fixed: the ~100 bytes at 13722–13837 are restored, with a comment recording that
`bits &= 6` on the line above makes the test identically false, so `TIOCSBRK`/`TIOCCBRK` are
dead on shipped Rhapsody. The mask was not moved or widened. Ledger: 13676
**assembly-matched** — the full 324-byte stream was read and both `enqueueEvent` argument
lists reproduced.

---

### Finding 77 — `ttyiops_procEvent` discards event 0x53 rather than forwarding it

**Reference** (14602–14624):

```
 14602: 8B45FC       mov  eax, [ebp+var_4]
 14605: 83F85C       cmp  eax, 5Ch
 14608: 7435         jz   14663                    ; 0x5C -> data |= 0x1000000, forward
 14610: 7710         ja   14628
 14612: 83F853       cmp  eax, 53h
 14615: 746F         jz   14728                    ; 0x53 -> var_4 = 0  (DROPPED)
 14617: 766D         jbe  14728                    ; < 0x53 -> var_4 = 0
 14619: 83F859       cmp  eax, 59h
 14622: 746F         jz   14735                    ; 0x59 -> forward unchanged
 14624: EB66         jmp  14728                    ; else  -> var_4 = 0
 14728: C745FC00000000  mov [ebp+var_4], 0
 14735: 837DFC00        cmp [ebp+var_4], 0
 14739: 7413            jz  14760                  ; 0 -> no l_rint call
```

**Our source** (`ttyiops.m:2112–2115`):

```c
if (event_type == 0x53) {
    /* Event 0x53 - Flow control event, pass through */
    goto send_to_line_discipline;
}
```

**Difference.** The reference sends 0x53 to the `var_4 = 0` sink, which suppresses
the `l_rint` call. Ours forwards it, so a flow-control event is injected into the
line discipline as an input character. Every other arm (0x5C, 0x59, 0x60, 0x68,
0x6C, 0xF9, default) matches.

**Disposition: fix.** Make 0x53 fall into the `event_type = 0` path along with
everything below 0x53.

**Outcome (Task 8):** Fixed: the `event_type == 0x53` arm now falls into the `event_type = 0` sink with
everything below 0x53. Ledger: 14560 **assembly-matched** — the full 207-byte stream was
read.

---

### Finding 78 — `ttyiops_waitForDCD` is defined twice; delete the stub

**Reference.** One `_ttyiops_waitForDCD` at 12880, 160 bytes, fully decoded in Section 5.

**Our source.** Two definitions:
- `ttyiops.m:1099–1153` — a complete body that matches the reference instruction
  for instruction.
- `ttyiops.m:1784–1793` — a stub carrying the `TODO: Implement DCD waiting logic`
  marker, returning 0 unconditionally, and missing its closing brace (§5).

`source-map.json` records this as the third `duplicate_candidates` entry.

**Difference.** A duplicate external definition; the file cannot compile with
both, and if it could, the stub at 1784 would be the one the linker sees last.
The stub never waits and never acquires the session, so `ttyiops_open` would
proceed on a port it has not acquired.

**Disposition: fix.** Delete `ttyiops.m:1780–1794` (the stub, its comment block,
and its trailing blank line). Keep the body at 1099 unchanged; the only edit it
might want is a comment noting the `-0x2CD`/`-0x2BF` mapping. Deleting the stub
also removes one of the two unclosed braces.

**Outcome (Task 8):** Repaired ahead of the fix pass by Task 7; there is exactly one definition today
and it is the complete body. **Nothing in the fix pass re-verified 12880 against the
reference**, so the ledger leaves it **unexamined** rather than claiming credit for Task 7's
deletion.

---

### Finding 79 — defensive NULL guards the reference does not have

The reference contains no argument NULL checks and no `linesw` slot NULL checks
anywhere in this translation unit. Our source adds eleven, in eight functions:

| Our source | Guard | Reference at the same point |
|---|---|---|
| `ttyiops.m:104` | `if (tp == NULL) return;` (`getData`) | 14260: `mov esi, [ebp+arg_0]`, no test |
| `ttyiops.m:136` | `if (portSession == nil) return;` | no test |
| `ttyiops.m:158` | `if (linesw[t_line].l_rint)` | 14524: loaded and called |
| `ttyiops.m:212` | `if (portServerObj == NULL \|\| unit > 25)` | 8774: no test (see F61) |
| `ttyiops.m:262` | `if (tp == NULL) return 0x16;` (`acquireSession`) | 11601: no test |
| `ttyiops.m:435` | `if (tp == NULL) return 0;` (`close`) | 9558: no test |
| `ttyiops.m:460` | `if (linesw[t_line].l_close)` | 9676: loaded and called |
| `ttyiops.m:530` | `if (tp == NULL) return 0;` (`mctl`) | 13704: no test |
| `ttyiops.m:602` | `if (tp == NULL \|\| data == NULL)` (`control_ioctl`) | 10462: no test |
| `ttyiops.m:687` | `if (portSession == nil \|\| flags == NULL)` | 10359: no test |
| `ttyiops.m:749` | `if (linesw[t_line].l_modem)` (`dcddelay`) | 15291: loaded and called |

**Difference.** Extra code in each prologue, and in `ttyiops_close`'s case an
outright behavioural change: the reference dereferences a NULL `tp` (the same
class of bug as F67).

**Disposition: fix**, except `ttyiops.m:435`. Remove the ten guards that only add
instructions the reference does not have; **accept** the `ttyiops_close` NULL
check on the same grounds as F67, and record it as an intentional mismatch. Doing
this as one sweep keeps the diff coherent.

**Outcome (Task 8):** Ten of the eleven guards removed: `getData`'s `tp` and `portSession` guards and
its `l_rint` slot test, `acquireSession`'s `tp` guard, `close`'s `l_close` slot test,
`mctl`'s `tp` guard, `control_ioctl`'s `tp`/`data` guard, `convertFlowCtrl`'s
`portSession`/`flags` guard, and `dcddelay`'s `l_modem` slot test; `attachDevice`'s went
with Finding 61 and `ttyiops_ioctl`'s `l_ioctl` test with Finding 65. **One kept
deliberately: `ttyiops_close`'s `if (tp == NULL) return 0;`**, exactly as this finding
directs — the reference at 9558 falls through with `ebx == 0` into
`or byte ptr [ebx+15Ch], 4`, a reachable kernel NULL dereference on close of an empty map
slot. Ledger: 14248 and 13676 **assembly-matched**; 10352, 11592 and 15236 **unexamined**,
their prologues never read; 9484 **intentional-mismatch**, reviewer Pat Raynor, with that
reason recorded on the entry. **A twelfth guard the report pass missed is still in place:**
`ttyiops_init`'s `if (tp == NULL) return;`. It is not in this finding's table, so part 3
left it; 12260–12420 was never read, so whether the reference's prologue also lacks a test
is unknown. It deserves a finding of its own.

---

### Finding 80 — the `(hz + 50) / 100` tick value is computed in 64 bits

**Reference** (12428–12486):

```
 12428: 8B1500000000  mov  edx, ds:_hz
 12434: 89D1          mov  ecx, edx
 12436: 89CB          mov  ebx, ecx
 12438: C1FB1F        sar  ebx, 1Fh              ; sign-extend hz to 64 bits
 12453: 83C132        add  ecx, 32h              ; += 50
 12456: 83D300        adc  ebx, 0
 12465: 6A00 / 6A64   push 0; push 64h           ; divisor 100 as a 64-bit value
 12475: E8C80C0000    call __divdi3
 12486: 898358010000  mov  [ebx+158h], eax
```

**Our source** (`ttyiops.m:818`):

```c
((int *)tp)[0x158/4] = (int)((hz + 50) / 100);
```

**Difference.** Ours is a 32-bit `idiv`; the reference widens to `long long` and
calls `__divdi3` (which is why `__divdi3` is linked into the binary at 15752).
The results are identical for every plausible `hz`, so this is codegen fidelity
only. It is worth recording because `__divdi3` appears in `source-map.json`'s
`unmapped` list and this is its only caller — so its presence is explained, not a
gap.

**Disposition: accept.** Note it in the ledger; changing the source to force
`__divdi3` (e.g. `(long long)hz + 50`) would be guessing at Apple's exact
declaration of `hz` and buys nothing.

**Outcome (Task 8):** **Accepted, not fixed.** Our 32-bit division gives an identical result for every
value of `hz`, and forcing the 64-bit widening would mean guessing Apple's declaration of
`hz`. Ledger: 12260 **intentional-mismatch**, reviewer Pat Raynor, with that reason recorded
on the entry; 15752 `__divdi3` stays **intentional-mismatch** as build-linked libgcc, and
its presence in `source-map.json`'s `unmapped` bucket is explained by this one call site.

---

### Finding 81 — `ttyiops_close`'s prototype disagrees with its call site

**Reference.** `_ttyiops_close` is called from `_ttyiops_open` with four
arguments:

```
 9333: 8B5514  mov edx, [ebp+arg_C]; push edx      ; p
 9337: 8B5510  mov edx, [ebp+arg_8]; push edx      ; mode
 9341: 8B550C  mov edx, [ebp+arg_4]; push edx      ; flag
 9345: 57      push edi                            ; dev
 9346: E885000000  call _ttyiops_close
```

`_ttyiops_close` itself only ever reads `arg_0` (dev) and `arg_4` (flag);
`_portServerclose` calls it with two. Apple's declaration was therefore the
K&R-style variadic-tolerant `int ttyiops_close(dev, flag)` with a loose
four-argument call site — legal in the original tree, not legal against our
prototype.

**Our source.** `int ttyiops_close(unsigned int dev, int flag)` at
`ttyiops.m:418`, called as `ttyiops_close(dev, flag, mode, (int)p)` at
`ttyiops.m:2031`.

**Difference.** A hard compile error, independent of the brace damage.

**Disposition: fix.** Trim the call site at `ttyiops.m:2031` to
`ttyiops_close(dev, flag)`. The reference's extra two arguments are never read,
so this is behaviour-preserving. Hand this one to Task 7 along with the braces —
it is a compile blocker, not a semantic divergence.

**Outcome (Task 8):** Fixed: `ttyiops.m` now calls `ttyiops_close(dev, flag)`. The reference does push
four arguments, but `_ttyiops_close` reads only `arg_0` at 9490 and `arg_4` at 9671 —
Apple's K&R declaration tolerated the extra two, so trimming is behaviour-preserving and is
the only spelling our prototype accepts. Evidence: `control-flow-confirmed`, the full stream
read. Ledger: 9484 **intentional-mismatch**, on Finding 79's kept guard rather than on this
finding.

---

### Finding 82 — two decompiler artefacts that read as bugs

Grouped because neither changes behaviour and both are one-line edits.

**(a) `ttyiops.m:329` and `:375` — a phantom argument to `-name`.**

```
 11883: 8D45FC        lea  eax, [ebp+var_4]      ; &result, pushed for the *outer* call
 11886: 50            push eax
 11887: 8B1500630000  mov  edx, ds:paName
 11894: 52            push edx
 11901: E87ED1FFFF    call _objc_msgSend         ; [session name]
 11906: 83C408        add  esp, 8                ; pops self+sel only; &result stays
 11909: 50            push eax                   ; the name
 11910: 8B1548630000  mov  edx, ds:paInitfordeviceR
 11931/11940: ...     call _objc_msgSend         ; [[IOPortSession alloc] initForDevice:name result:&result]
```

Our source writes `objc_msgSend(((id *)tp)[0xe8/4], @selector(name), &acquire_result)`.
`&acquire_result` is gcc's pre-staged last argument of `initForDevice:result:`,
not an argument to `name`. Harmless under `objc_msgSend`'s variadic prototype, but
misleading. **Disposition: fix** (drop the third argument).

**(b) `ttyiops.m:177` — `tp->t_dev` where the reference uses `tp + 0x64`.**

```
 14387: 8B7664  mov esi, [esi+64h]
 14390: 56      push esi
 14391: 6876400000  push offset aPstty04xDequeu   ; "PStty%04x: dequeueData ret %d\n"
```

Every other `IOLog` in this file writes the same field as
`((unsigned int *)tp)[100/4]` (= `tp + 0x64`); only this one uses `tp->t_dev`.
Whether `t_dev` resolves to 0x64 depends on the `struct tty` layout our headers
produce, and the surrounding code does not rely on it. **Disposition: fix** for
consistency with the other five sites.

**Outcome (Task 8):** Both fixed. (a) the phantom `&acquire_result` third argument to `-name` is dropped
at both `ttyiops_acquireSession` sites; (b) `tp->t_dev` in `getData`'s `IOLog` is now
`((unsigned int *)tp)[100/4]`, matching the other five `IOLog` sites in the file. Ledger:
14248 **assembly-matched** for (b); 11592 **unexamined** for (a) — only the instructions
quoted here were read, not the surrounding 667-byte stream.

---

## 12. What could not be determined

### From pass 1

Stated plainly, without hedging elsewhere in this document.

1. **The struct tag behind `{?="locked"I}`.** The `@encode` names an *anonymous* struct
   (`?`) with one `unsigned int` member called `locked`. I did not find a matching
   declaration in this tree — I searched only the two files in scope and their headers,
   not `src/kernel-7` or `src/driverkit-3` exhaustively. Any
   `typedef struct { unsigned int locked; } X;` reproduces the encoding, but I cannot say
   what Apple called it. Whoever does the fix pass should grep the kernel headers before
   inventing a name.

2. **Whether `-initWith:intr:` writes `interuptable` last in the *source*.** I recorded
   the emitted order (F14) and argued gcc 2.x would not reorder three non-aliasing
   stores, but I did not prove it. If the fix pass writes them in our current order and
   the byte comparison then fails, F14 is the reason.

3. **`AIOPSSCL_setCondition`'s original prototype.** The call site pushes exactly two
   words (receiver and selector), so it takes one `id` and no condition — but I cannot
   tell from the binary whether the original header declared a second parameter that the
   body ignored.

4. **Whether `-[IOPortSession release]`'s `-706` return is consumed.** The callers are in
   `ttyiops.m` and `IOPortSessionKern.m`, both out of my scope. F24 argues from the
   presence of the return value, not from a demonstrated caller.

5. **Which of the four `PortDevices` protocol records belongs to which module.** I
   attributed 26776 to `IOPortSession.m` because that is the record `initForDevice:result:`
   pushes; the other three (26796, 26816, 26836) are byte-identical and I did not
   attribute them. 26816 is pointed at by `_protocols.102` in `__data`, which belongs to
   another module.

6. **The `IOPortSessionKern` category** (`__category[1]`, instance methods 25084, class
   methods 24600) adds more methods to `IOPortSession` from `IOPortSessionKern.m`. It is
   out of scope and I did not read it; if it references `_priv` at other offsets, F15's
   ivar declaration will need to be visible to it too.

### From pass 2

1. **Who reads `"Support Dialin"`.** Covered at length in Section 8. The string is absent from
   `PortServer_reloc`, from `PortServer`, from `pdservd` and from every source file in
   this repository. I can show our table differs from Apple's by one character; I cannot
   show what breaks.

2. **The exact C of the two bulk-transfer loops** (Finding 52). I have the machine
   condition with full register provenance, and I have shown the alternative branch at
   8028 is unreachable, but gcc rotated both loops and `+iopsKernEnqueue:` expresses its
   refill test as a pointer comparison against the end of the stack buffer rather than as
   a counter. Several C spellings produce this code; I did not pick one.

3. **Whether the reference's `serverMajor:` names `ttyiops_devsw`'s members or takes a
   `struct cdevsw *`** (Finding 36). The eight `mov ds:off_81xx` loads are unambiguous
   *loads of those eight fields*, and the skipped `d_strategy` slot argues strongly for
   member-by-member spelling, but a helper that copied fields out of a passed-in pointer
   would compile to the same thing if it inlined. The fix is the same either way.

4. **Which translation unit the `_ttyiopsMap` references outside 4692–6576 come from**
   (Finding 45's caveat). `ttyiops.m` is not in my scope and I did not read its 1200+
   bytes of text looking for them, so I cannot state with certainty that `static` on
   `_ttyiopsMap` is safe until Finding 42's move happens.

5. **The `PortServer` `state` ivar's exact `@encode`-to-`ttyiops.h` correspondence**
   (Finding 35). I decoded the type string and matched the named fields
   (`iops`, `rxThread`, `txThread`, `it_out`, `it_in`, `dtr_down_time`,
   `in_opens_pending`, `dcd_delay_ticks`, and eleven `b1` bitfields), and I confirmed the
   three offsets our source uses, but I did not verify field-by-field that our
   `ttyiops.h`'s `ttyiops_state` lays out to 352 bytes with `iops` at +0xE8 and the
   bitfield byte at +0x15C. That check belongs with whoever audits `ttyiops.m`.

6. **`PortServerVersion` and `PortServerKernelServerInstance`** (15740 and 15728) are
   build-generated glue in `PortServer_instance.m`, outside all three parts of this pass.
   I read their metadata only to confirm they are not ours.

### From pass 3

- **`suser`'s exact argument shape.** `_ttyiops_open`+141 and
  `_ttyiops_control_ioctl`+104 both emit `push p + 0xD2` then
  `push [[p + 8] + 0x24]`. Our source writes `suser(p->p_ucred->cr_uid,
  &p->p_acflag)`. `p + 8` is plainly `p_ucred` and `p + 0xD2` is plainly
  `p_acflag`, but `ucred + 0x24` is not `cr_uid` in the 4.4BSD layout
  (`cr_ref`, `cr_uid`, `cr_ngroups`, `cr_groups[]`), so either this kernel's
  `struct ucred` differs or the first argument is something else in the group
  array. I did not resolve which, and did not raise a finding on it — the
  offsets are consistent between the two call sites, so whatever our headers
  make `p->p_ucred->cr_uid` compile to should be checked against 0x24 during the
  fix pass rather than guessed at here.
- **Whether `ttyiops_devsw` should be `static`.** The symbol is `local`, so it was
  `static` in Apple's tree, and `_portServeropen` (its only user, at reference
  6149) must therefore have been in the same file. Our `portServeropen` already
  is. But part 2 owns `_portServeropen`, and if that part concluded otherwise the
  linkage needs reconciling between the two reports.
- **The `hz` declaration behind F80.** I established that the division is 64-bit
  and that `__divdi3` has exactly one caller; I did not establish what
  declaration in Apple's headers produced it.
- **Whether `_ttyiops_devsw` slot 7 (`d_ttys`) is a literal `0` or a relocation
  the linker resolved to zero.** The relocation table has no entry at 33100 and
  the bytes are zero, so I recorded it as a literal `0`, matching `NO_CDEVICE` in
  `conf.h`. That is an inference from an absence, not a positive observation.

## 13. Corrections to the report pass, found during the Task 8 fix pass

These are errors in *this document* that only surfaced when the repairs were actually
applied. They are recorded here rather than silently edited into the findings above, so the
report pass's original claim and its correction both stay on the record.

- **Finding 30's title says "six" `(void)` methods; there are five.** Its own body lists
  exactly five (`release`, `setState:mask:`, `watchState:mask:`, `executeEvent:data:`,
  `requestEvent:data:`) and our source has five. The title is a typo, not a missed site.

- **−702 is `IO_R_RESOURCE`, not `IO_R_UNSUPPORTED`.** Finding 30 names it
  `IO_R_UNSUPPORTED`; in `src/driverkit-3/driverkit/return.h`, −702 is `IO_R_RESOURCE` and
  −711 is `IO_R_UNSUPPORTED`. The fix kept the numeric literal `0xfffffd42` rather than
  introduce a wrong symbolic name. The value in the binary is not in dispute; only the name
  this document gave it.

- **Finding 35's rationale claims `ttyiops.h` already declares `ttyiops_state`. It did
  not.** `grep -rn ttyiops_state src/drvPortServer` matched only this document. Part 2 could
  therefore apply only the superclass half of Finding 35, and Findings 35's ivar and 44 had
  to wait for part 3, which declared the type from the reference's ivar `@encode` at 27458.
  Section 12's "remaining uncertainty" 5 already admitted the layout was never checked; the
  rationale contradicted it.

- **Finding 52's claim that the two enqueue refill tests agree on every reachable input is
  false above 2048 bytes.** Once the loop condition is corrected as the finding directs, a
  full 0x800 pass takes the `else` branch under our counter-based `remainingInBuffer == 0`
  test, sets the size to 0 and calls `enqueueData:` with `bufferSize:0`, whereas the
  reference (`cmp edi, ebp; jnb` at 8024, `edi` advanced by `transferCount` at 8120 and
  initialised to `ebp` at 7989) refills. The fix transcribes the reference's pointer test
  literally instead.

- **Finding 61's cast for `ttyiops_attachDevice` is wrong; Finding 40's is right.** Finding
  61 spells the parameter `struct tty *`. Part 2 followed it and part 3 corrected it to
  `ttyiops_state *`, on the evidence of the reference's ivar `@encode` at 27458: `+0x108` is
  `&self->state`, and the offsets the callee writes — 0x120 `it_in`, 0xF4 `it_out`, 0x14C
  `dtr_down_time` — are all past the end of `struct tty`, which lays out to 232 (0xE8)
  bytes. `struct tty *` would have made every one of those writes out of bounds of the
  pointed-to type.

- **`local` in this document does not mean `static`; three of the data symbols §5.5 calls
  `static` are `N_PEXT`.** §5.5's "Every one of these is `local` (i.e. `static`)" and
  §5.7's closing paragraph are both wrong, and Section 12's open question "Whether
  `ttyiops_devsw` should be `static`" is answered by reading `n_type` rather than the
  analyzer's coarse `local`/`external` binding. The reference's symbol table has exactly
  **five** `N_PEXT` (`0x1e`) symbols — private-external, i.e. non-`static` in Apple's
  source and made file-local only by the static link:

  ```
  _portServerMajor       0x1e  __data  32772
  _ttyiopsMap            0x1e  __data  32776
  _ttyiops_attachDevice  0x1e  __text   8768
  _ttyiops_devsw         0x1e  __data  33072
  __divdi3               0x1e  __text  15752
  ```

  By contrast `_ttyiops_open`, `_ttyiops_close`, `_ttyiops_read`, `_ttyiops_write`,
  `_ttyiops_ioctl`, `_ttyiops_stop` and `_ttyiops_select` are all `0x0e` — `N_SECT` with
  neither `N_EXT` nor `N_PEXT` — and so were genuinely `static`. Since `ttyiops_devsw`
  takes the address of all seven, and a `static` function's address can only be taken
  inside its own translation unit, **Apple defined `ttyiops_devsw` in `ttyiops.m`,
  non-`static`.** Corroborating: `_ttyiops_speeds` is at 32888 and is 23 × 8 = 184 bytes,
  ending at exactly 33072 where `_ttyiops_devsw` begins — adjacent in `__data`, hence the
  same translation unit, in that order. This supersedes Finding 60's first outcome and
  Section 14's `_ttyiopsMap` / `_portServerMajor` acceptance bullet.

- **A twelfth defensive NULL guard the Finding 79 table missed.** `ttyiops_init`'s
  `if (tp == NULL) return;` is not in the table and was therefore left in place. 12260–12420
  was never read, so whether the reference's prologue also lacks a test is unknown.

## 14. Work the Task 8 fix pass left undone

Recorded plainly rather than folded into the outcomes above, because each is a real gap the
next pass inherits.

- **`+serverMajor:`'s argument spelling — the last piece of Finding 36.** The reference
  loads eight of its eleven arguments out of `ttyiops_devsw`'s fields (`mov ds:off_81xx`);
  ours passes the same eight functions by name. Part 2 recorded the by-name spelling as a
  considered choice while `ttyiops_devsw` did not exist; part 3 created `ttyiops_devsw`,
  which makes the field spelling possible, but declined to overturn part 2's decision on
  part 2's own finding. The table now lives in `ttyiops.m` and is declared in `ttyiops.h`,
  so it is still in scope in `PortServer.m` and the field spelling remains available. 4692
  is held at `control-flow-confirmed` for exactly this reason.

- **`ttyiops.m`'s literal byte offsets — 183, not the "roughly 120" first written here.**
  `ttyiops.m` still reaches `ttyiops_state`'s fields as `((unsigned char *)tp)[0x15c]`,
  `((id *)tp)[0xe8/4]` and so on. The earlier figure was an estimate and was low; counted
  over the current file, the offsets applied to `tp` are **183**: 158 hex subscripts on a
  cast of `tp`, 23 decimal ones (`[100/4]`, `[100]`, `[8]`, `[7]`, `[200/4]`), and 2
  pointer-arithmetic forms (`(char *)tp + 0x40`, `+ 0x8c`). Counting the same idiom on the
  other bases in the file brings it to **194** — 5 on `data`, 6 on
  `_ttyiopsMap[...] + 0x108`. (Excluded from both totals: the 4 `((unsigned char *)&iflag)[1]`
  accesses, which index a local, and the `char padding[0xe8 - sizeof(struct tty)]` member
  declaration.) No finding asks for the rewrite, the type now documents every one of them,
  and doing it would have produced a mechanical diff swamping the pass's substantive
  repairs. It was deliberately not done.

- **`suser`'s argument shape, and the disagreement between its two call sites — now
  resolved from the disassembly.** Section 12 asked for `ucred + 0x24` to be checked during
  the fix pass. It was not, and in the process a worse problem surfaced: `ttyiops.m:1953`
  (in `ttyiops_open`) writes `suser(((struct proc *)p)->p_ucred->cr_uid, &p->p_acflag)`
  while `ttyiops.m:661` writes `suser(p->p_ucred, &p->p_acflag)`. The two disagree, so at
  most one can be right. **The reference settles it: `:1953` is the wrong one.** Both
  `_suser` call sites in the binary compile to the identical three-instruction argument
  setup, and each performs exactly **two** loads off the `struct proc *`:

  ```
  _ttyiops_open (22B8):            _ttyiops_control_ioctl (28D8):
  2345: mov eax, [ebp+arg_C]       2940: lea eax, [edi+0D2h]      ; &p->p_acflag
  2348: add eax, 0D2h              2946: push eax
  234D: push eax                   ; &p->p_acflag
  234E: mov edx, [ebp+arg_C]
  2351: mov eax, [edx+8]           2947: mov eax, [edi+8]         ; p->p_cred
  2354: mov eax, [eax+24h]         294A: mov eax, [eax+24h]       ; ->pc_ucred
  2357: push eax                   294D: push eax
  2358: call _suser                294E: call _suser
  ```

  `src/kernel-7/bsd/sys/proc.h:116` defines `p_ucred` as the macro `p_cred->pc_ucred`, so
  the expansion is inherently two loads. The offsets corroborate it: `p_cred` is
  `proc.h:110`, the first member after the 8-byte `LIST_ENTRY(proc) p_list`, hence `+8`; and
  `pc_ucred` is `proc.h:291`, sitting behind `struct lock__bsd__ pc_lock`, whose ten members
  (`lock.h:75-87`) occupy 4+4+4+4+2+2+4+4+4+4 = 36 = **0x24** bytes on i386. `p_acflag`
  (`proc.h:185`) is the `+0xD2`. A third load for `->cr_uid` appears at neither site.
  `src/kernel-7/bsd/sys/ucred.h:90` also declares
  `int suser(struct ucred *cred, u_short *acflag)`, which `:1953` violates by passing a
  `uid_t`. **Conclusion: `ttyiops.m:661` matches the reference and is correct; `:1953`'s
  `->cr_uid` is wrong and should be dropped.** Not repaired here — this section is
  disclosure only.

- **Finding 16's `_portList` / `_portListLock` declaration order.** Left alone because the
  finding is self-contradictory about it. If the reference `__bss` order (33160
  `_portListLock`, 33164 `_portList`) is meant to be reproduced by declaration order, a
  one-line swap is still owed.

- ~~**Two accepted divergences that no ledger entry can carry.**~~ **Withdrawn — there was
  never anything to accept.** The Task 8 pass booked `_ttyiopsMap` (Finding 45) and
  `_portServerMajor` (part 3's out-of-list repair) as accepted divergences on the grounds
  that they are "`local` in the reference but must stay non-`static` in our tree". Both are
  `N_PEXT`, i.e. **non-`static` in Apple's source** (see Section 13); our non-`static`
  spelling therefore *matches* the reference and no divergence exists. Nothing was booked in
  `ledger.json` — it has entries only for the 113 functions — so no ledger entry needed
  correcting either.

  What remains true, and is a repair rather than an acceptance: `_portServerMajor` fixed a
  pre-existing link break that no finding raised. `ttyiops.h` declared
  `extern int portServerMajor;` while `PortServer.m` defined `static int _portServerMajor`
  — two different C identifiers, the second not externally visible, so `ttyiops.m`'s six
  references resolved to nothing.

- **No compile gate anywhere in Tasks 7 or 8.** Nothing in this driver has been built. Every
  claim in this document and in `ledger.json` rests on reading the reference disassembly.

- **Two compile blockers this branch walked past without disclosing them.** Both are
  **pre-existing**, both are in `ttyiops.m`, and **neither was repaired** — they are outside
  this branch's remit and belong to a follow-up. They are recorded here because §14 had
  previously said only that there was no compile gate, without naming anything that would
  actually fail one.

  1. **`timeout_func_t` is not defined anywhere under `src/`.** `ttyiops.m:1273`, `:1279` and
     `:1319` cast through it:

     ```c
     timeout((timeout_func_t)ttyiops_dcddelay, tp, ...);
     untimeout((timeout_func_t)ttyiops_dcddelay, tp);
     ```

     A tree-wide search finds the identifier only at those three lines and in this document
     — there is no `typedef` for it. `src/kernel-7/bsd/sys/systm.h:177` declares
     `void timeout __P((void (*)(void *), void *arg, int ticks));`, so the correct cast type
     is `void (*)(void *)`; the nearby `timeout_fcn_t` at `systm.h:176` is the typedef Apple
     actually spells, and differs from ours by one letter. **This branch touched line 1273**
     (commit `46236c13`, Finding 46's DCD-delay repair) and left the undefined type in place.

  2. **`sys/proc.h` is never included, so `struct proc` is incomplete where it is
     dereferenced.** `ttyiops.m` names `struct proc *` in four prototypes (`:614`, `:904`,
     `:1535`, `:1915`) and dereferences it at `:661` (`p->p_ucred`, `p->p_acflag`) and
     `:1953` (same). With no `#import <sys/proc.h>` the type is only an incomplete forward
     declaration and every one of those member accesses is an error. Note that `p_ucred` is
     a macro rather than a member (`proc.h:116`), so the header is required for the
     expansion as well as for the layout.
