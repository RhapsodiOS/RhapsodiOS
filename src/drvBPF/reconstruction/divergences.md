# drvBPF reconstruction divergences

Report pass over Apple's shipped `BPF_reloc`
(`reference_sha256` `56DF84EDC7D77C0799A036C21BE43D833A926BCAA6DA48512DF99CEE7A1B86DB`,
32020 bytes, `MH_PRELOAD` i386). This document records where our reimplementation in
`src/drvBPF/BPF.drvproj/BPF.lksproj/` diverges from that binary.
**It changes no driver source.** Task 4 does the fixing.

Line numbers are against the current committed tree (`BPF.m` 132 lines,
`bpf.c` 1291, `bpf_filter.c` 565, `BPF.h` 47), verified with `git status`
before the pass began.

---

## 1. Coverage and examination depth

The reference partitions into **30 functions**: 28 hand-written plus 2 pieces of
build-generated Kernel Server glue. All 28 are mapped; the 2 glue functions are
`unmapped` by design.

| Depth | Count | What was done |
|---|---|---|
| `assembly-matched` | 23 | Every instruction read, and no divergence found |
| `control-flow-confirmed` | 0 | — |
| `unexamined` | 5 | Every instruction read, **and a divergence found** — these carry a finding below |
| `intentional-mismatch` | 2 | Build-generated glue, not present in source |

**Every one of the 28 mapped functions had its full instruction stream read.** No
function in this driver was examined at block-and-call-target level only, and none was
skipped. `unexamined` is used, per the ledger convention, only for a function that
diverges.

Two functions needed data decoded out of the binary rather than read off the
disassembly, and both were done directly:

- `_bpf_filter` (4276): all **178** entries of the jump table at 4336 were read from
  `__TEXT,__text` as little-endian `uint32`, and every target cross-checked against an
  address that is both a real instruction and a basic-block start. 46 distinct targets;
  133 of the 178 selectors reach the default at 6104; the table ends at
  `4336 + 178*4 = 5048`, which is exactly the first case block.
- `_bpf_movein` (420): the eleven-entry jump table at 448 covering `linktype` 0-10.

`_bpfioctl` (1736) needed neither: see Section 4.

The ObjC metadata was read directly out of the binary (`__OBJC,__class`,
`__meta_class`, `__cls_meth`, `__inst_meth`, `__class_names`, `__meth_var_types`,
`__meth_var_names`, `__message_refs`, `__module_info`, `__cstring`), not inferred from
disassembly.

## 2. Stated limitations

- **Two analyzers, not three.** Ghidra is disabled in `tools/binrecon/profiles/bpf.json`
  because it cannot analyze this binary. There is no `analysis-reference-ghidra.json`,
  and every analyzer-disagreement statement in this document and in `ledger.json`
  compares **IDA against angr only**. angr's `CFGFast` is the weaker of the two on this
  image, so `boundary_disputed` is materially **less sensitive** here than it would be
  in a three-analyzer run: a boundary both IDA and angr get wrong the same way would
  pass unnoticed. No such case is known, but the check is weaker and that is recorded
  rather than glossed.
- **`PostLoad.tproj` is out of scope** (spec §1.2). It is named in `Default.table` as
  `"Post-Load" = "PostLoad"` and builds a separate user-space tool. It is deliberately
  not under `--source-dir`, and its absence from `source-map.json` is **not** a gap.
- **`bpf_filter.c` and `bpf.c` are BSD sources with K&R function definitions**, which
  `binrecon.source_map` could not parse before this pass. See Section 7.

## 3. Analyzer agreement

IDA reports 30 functions. angr reports 129. **Every one of IDA's 30 start addresses is
also an angr start address, and all 30 sizes are identical.** angr's extra 99 entries
are interior addresses that `CFGFast` promotes to function starts because it splits
basic blocks more finely. That is recorded, not corrected, and it is not 99 boundary
disputes — it is 99 interior labels inside extents the two analyzers already agree on.
`boundary_disputed` is therefore correctly empty.

IDA's function extents run 1-3 bytes under the task brief's symbol-gap sizes for 22 of
the 30 functions, because the brief's table is gap-derived and includes the linker's
padding to the next 4-byte boundary. **IDA's `size` is authoritative** and is what
`ledger.json` and `source-map.json` carry. A 1-3 byte gap-versus-IDA difference is
padding, not a boundary dispute.

## 4. Two corrections to the task brief

Both were checked against the binary rather than assumed.

**The `__TEXT,__const` jump table for `_bpfioctl` does not exist.** The brief directed
that a 170-byte jump table at 6382 be decoded out of `__TEXT,__const` and its `BIOC*`
values checked. `__TEXT,__const` is 170 bytes at 6382, but it holds exactly two
symbols — `_BPF_VERS_STRING` (6382, 160 bytes,
`@(#)PROGRAM:BPF  PROJECT:drvBPF-3  DEVELOPER:root  BUILT:Sun Mar 29 03:25:29 PST 1998`)
and `_BPF_VERS_NUM` (6542, `3`) — both build-generated version glue. `_bpfioctl`
contains no indirect jump at all; its switch is a gcc-generated **balanced binary-search
compare chain** over 15 constants. The only jump tables in the binary are `jpt_1B8`
(448, inside `_bpf_movein`) and `jpt_10E6` (4336, inside `_bpf_filter`). The `BIOC*`
values were verified anyway, from the compare chain — see Finding-free Section 6.

**The reference does not call `strcmp` from `getIntValues:forParameter:count:`.** The
brief asked whether it does. It imports `_strcmp`, but there is exactly **one** call
site in the whole binary, at 2842 inside `_bpf_setif`, comparing `ifp->if_name` against
`ifr->ifr_name`. See Finding 3.

## 5. Functions absent from the binary that are not findings

`bpf_timeout` (`bpf.c:393`), `bpf_sleep` (`bpf.c:404`), `bpfselect` (`bpf.c:956`) and
`bpf_alloc` (`bpf.c:1268`) are each inside a `#if BSD < 199103` block — opened at
`bpf.c:391`, `:391`, `:954` and `:1261` respectively. `bpf.c:66` includes
`<sys/param.h>`, and `src/kernel-7/bsd/sys/param.h:69` defines `BSD` as **199506**, so
all four blocks are dead and never compile. `bpf_wakeup` (`bpf.c:527`) is
`static __inline void` and is inlined into `catchpacket` — visibly so, as two separate
`wakeup` / `selwakeup` / `bd_sel.si_thread = 0` expansions at 3504-3519 and 3542-3557.

Our 26 `bpf.c` definitions therefore compile to the reference's **21** `bpf.c`
functions: 26 − 4 dead − 1 inlined = 21. `bpf_filter.c` contributes 4 more
(`m_xword`, `m_xhalf`, `bpf_filter`, `bpf_validate`), `BPF.m` 3, and the glue 2, for 30.
**Not findings.** The brief's line-number estimates were checked against the file rather
than trusted; the values above are the verified ones.

Two further non-findings in the same family:

- `bpf_bufsize`, `bpf_iflist`, `bpf_dtab` and `nbpfilter` are **undefined imports** in
  the reference — the kernel owns them, the driver does not. `bpf.c:121` and
  `bpf.c:135-137` *define* them, but `bpf.c:58` has `#define BPFDRV`, which puts those
  lines in the false arm of `#ifndef BPFDRV` / `#else`; the live declarations are the
  `extern`s at `bpf.c:123` and `:131-133`. Correct as written.
- `bpf.c:155-165` declares `bpf_allocbufs`, `bpf_freed`, `bpf_ifname` and `bpf_setif`
  twice each. Duplicate prototypes are legal C and emit nothing. Cosmetic only.

## 6. Linkage, and what already matches

Reading the reference's nlist with `binrecon.macho.read_macho`: 117 symbols, all with a
section or `UNDEF`. **Every `static`-versus-external decision in our source already
matches the reference**, which is unusual for this project and worth stating explicitly
so Task 4 does not "fix" it:

| Reference `local` (i.e. `static`) | Reference `global` |
|---|---|
| `_bpf_movein`, `_bpf_attachd`, `_bpf_detachd`, `_reset_d`, `_bpf_setif`, `_bpf_ifname`, `_bpf_mcopy`, `_catchpacket`, `_bpf_allocbufs`, `_bpf_freed`, `_m_xword`, `_m_xhalf` | `_bpfilterattach`, `_bpfopen`, `_bpfclose`, `_bpfread`, `_bpfwrite`, `_bpfioctl`, `_bpf_setf`, `_bpf_select`, `_bpf_tap`, `_bpf_mtap`, `_ifpromisc`, `_bpf_filter`, `_bpf_validate` |

All twelve on the left are `static` in our sources; all thirteen on the right are not.
Note the deliberate asymmetry the reference preserves and we already match: `bpf_setf`
is external while `bpf_setif` is static.

`+[BPF probe:]` is `global` while the other two methods are `local`. Objective-C methods
carry no `static` keyword, so this is a `kl_ld` artifact and not something our source
controls. Not a finding.

`_dst.112` (`__bss`, 16 bytes) is the `static struct sockaddr dst` inside `bpfwrite`;
ours declares it `static` too (`bpf.c:544`). `_BPF_instance` (`__common`),
`_BPF_VERS_STRING` and `_BPF_VERS_NUM` (`__const`) are glue.

`__module_info` names exactly two modules, `BPF.m` and `BPF_instance.m` — the first
ours, the second generated. `bpf.c` and `bpf_filter.c` are plain C and contribute none.

`_bpfioctl`'s fifteen commands were checked by expanding the macros from our own headers
and comparing against the compare-chain constants. All fifteen agree, none is missing
and none is extra: `BIOCGBLEN` `0x40044266`, `BIOCSBLEN` `0xC0044266`, `BIOCSETF`
`0x80084267`, `BIOCFLUSH` `0x20004268`, `BIOCPROMISC` `0x20004269`, `BIOCGDLT`
`0x4004426A`, `BIOCGETIF` `0x4020426B`, `BIOCSETIF` `0x8020426C`, `BIOCSRTIMEOUT`
`0x8008426D`, `BIOCGRTIMEOUT` `0x4008426E`, `BIOCGSTATS` `0x4008426F`, `BIOCIMMEDIATE`
`0x80044270`, `BIOCVERSION` `0x40044271`, `FIONREAD` `0x4004667F`, `SIOCGIFADDR`
`0xC0206921`. The chain is a 15-node perfect binary search tree (first compare at
sorted index 7, then 3 and 11, then 1/5/9/13, then the eight leaves), which proves the
set is complete — there is no sixteenth case hidden in the alignment padding.

The reference's `__cstring` is 86 bytes and holds exactly five entries: `bpf` (6296),
`BpfMajorMinor` (6300), `bpf: ifpromisc failed` (6314),
`bpf_detachd: descriptor not in list` (6336), `bpf_mcopy` (6372). Our sources produce
the same five and no others.

---

## Findings

### Class and layout

**Finding 1 — superclass is `IODevice` where the reference has `IODirectDevice`.**
`BPF.h:37`, and the `#import <driverkit/IODevice.h>` at `BPF.h:35`. Reference
`__OBJC,__class[0]`, read directly from the binary: `name` → `BPF`, `super_class` →
**`IODirectDevice`**, `instance_size` **296**, `ivars` **0**. Both
`.objc_class_name_IODevice` and `.objc_class_name_IODirectDevice` are imported — the
former is `BPFVersion`'s superclass, the latter is `BPF`'s. `instance_size` 296 with no
ivars of its own is exactly `IODirectDevice`'s own size, which independently
corroborates the reading (`drvPCParallel`'s `IOParallelPort`, also `IODirectDevice`, has
its first ivar at 296). Our class likewise declares no ivars, so the fix is the
superclass and the import, nothing more. `src/driverkit-3/driverkit/IODirectDevice.h`
exists in this tree.

**Disposition:** fix.

**Rationale:** largest structural finding in the driver, and the same pattern already
confirmed in `drvPCParallel`.

### `-[BPF initFromDeviceDescription:]` (156)

**Finding 2 — the driver never installs its `bpfops` hooks.**
`src/drvBPF/BPF.drvproj/BPF.lksproj/BPF.m:86-93`.

**Reference behaviour** — the first two instructions of the method body, before the
`setName:` send:

```
170: C70500000000340C0000  mov ds:_bpfops,   offset _bpf_tap    ; reloc _bpfops+0, _bpf_tap  (3124)
180: C70504000000E00C0000  mov ds:_bpfops+4, offset _bpf_mtap   ; reloc _bpfops+4, _bpf_mtap (3296)
```

`_bpfops` is an **undefined import** (nlist `UNDEF`, stub 24820), so the object being
written lives in the kernel, not the driver. `src/kernel-7/bsd/net/bpf.h:286-288`
declares it:

```c
typedef struct {
	void (*bpf_tap) (caddr_t, u_char *, u_int);
	void (*bpf_mtap)(caddr_t, struct mbuf *);
} bpfops_t;

extern bpfops_t bpfops;
```

Field order matches the offsets: `bpf_tap` at +0, `bpf_mtap` at +4.

**Our source**

```objc
- initFromDeviceDescription:(IODeviceDescription *)deviceDescription
{
    [self setName:"bpf"];
    [super initFromDeviceDescription:deviceDescription];
    [self registerDevice];

    return self;
}
```

**Difference:** the two hook installations are absent. Nothing else in the method
differs — `setName:"bpf"`, the `objc_msgSendSuper` to `initFromDeviceDescription:`,
`registerDevice` and `return self` all match instruction for instruction, in that order.

**Disposition:** fix.

**Rationale:** this is the single load-bearing omission in the driver. `bpf.h:291` and
`:296` define `BPF_TAP` and `BPF_MTAP` as `{if (bpfops.bpf_tap != NULL) ...}`, so with
`bpfops` left null **every network driver's tap call is a no-op and the BPF driver
captures nothing at all**. The driver would load, register, and silently never work.

### `-[BPF getIntValues:forParameter:count:]` (264)

**Finding 3 — the parameter-name comparison is hand-rolled where the reference inlines
a fixed-length compare.** `BPF.m:99-114`.

**Reference behaviour**

```
281: BF9C180000        mov  edi, offset aBpfmajorminor   ; "BpfMajorMinor" (6300)
286: C745F40E000000    mov  [ebp+var_C], 0Eh             ; 14 = strlen + NUL
293: 8B4DF4            mov  ecx, [ebp+var_C]
296: FC                cld
297: A800              test al, 0
299: F3A6              repe cmpsb
301: 753D              jnz  loc_16C                      ; -> super
303: 833B02            cmp  dword ptr [ebx], 2           ; *count == 2
306: 7538              jnz  loc_16C
```

`esi` was loaded with `parameterName` at 273/279. This is gcc's inline expansion of a
constant-length compare against the 13-character literal plus its NUL; `repe cmpsb`
stops at the first difference, so it is exactly equivalent to `strcmp(...) == 0`. There
is no call. The binary's only `_strcmp` call site is at 2842 in `_bpf_setif`.

**Our source**

```c
const char *expected = "BpfMajorMinor";
const char *p1, *p2;

p1 = parameterName;
p2 = expected;

while (*p1 && *p2) {
    if (*p1 != *p2)
        break;
    p1++;
    p2++;
}

if (*p1 == '\0' && *p2 == '\0' && *count == 2) {
```

**Difference:** an explicit byte loop and a two-terminator test in place of a single
comparison. The two are behaviourally equivalent — our loop exits with both pointers on
their NULs exactly when the strings are equal — but they compile to entirely different
instruction streams, and ours emits a second copy of the literal via `expected`.

Everything after the test matches: `[[self class] characterMajor]` into
`parameterArray[0]`, `nbpfilter` into `parameterArray[1]`, `*count = 2`, `return 0`, and
the `objc_msgSendSuper` fallback passing `parameterArray`, `parameterName` and `count`
in that order.

**Disposition:** fix.

**Rationale:** write it as `strcmp(parameterName, "BpfMajorMinor") == 0`, which is what
the reference's source plainly said. Whether our compiler chooses `repe cmpsb` or a
call is its business; the point is to stop hand-rolling it.

**Finding 4 — `parameterArray` is typed `int *`; the reference types it
`unsigned int *`.** `BPF.m:95`. Reference `__OBJC,__meth_var_types` entry at 8663 is
`i20@8:12^I16*20^I24`: return `i` (`IOReturn`, which
`src/driverkit-3/driverkit/return.h:36` typedefs to `int`), `self`, `_cmd`, then
**`^I`** at 16, `*` at 20 and `^I` at 24. Ours declares `(int *)parameterArray`, which
encodes as `^i`. The other two arguments already agree: `IOParameterName` is
`char[...]` (`driverTypes.h:171`) and decays to `*`, and `count` is `unsigned int *` =
`^I`.

**Disposition:** fix.

**Rationale:** type-encoding only — the emitted stores are identical 32-bit writes — but
it is a one-character change and it makes `__meth_var_types` match byte for byte.
The other two method signatures (`c12@8:12@16` for `+probe:`, `@12@8:12@16` for
`-initFromDeviceDescription:`) already match ours exactly.

### `_bpf_movein` (420)

**Finding 5 — the reference allocates a plain mbuf; ours allocates a packet-header
mbuf.** `bpf.c:232-255`.

**Reference behaviour** — three independent pieces of evidence, all pointing the same
way:

```
678: 66C743120000  mov  word ptr [ebx+12h], 0     ; m->m_flags = 0
688: 6A01 6A01     push 1 / push 1
692: E847FDFFFF    call _m_retry                  ; not m_retryhdr
716: 837DFC6C      cmp  [ebp+var_4], 6Ch          ; if (len > 108)
```

`src/kernel-7/bsd/sys/mbuf.h` distinguishes the two macros exactly here: `MGET` sets
`m_flags = 0` and falls back to `m_retry`, while `MGETHDR` sets `m_flags = M_PKTHDR`
(`= 2`, `mbuf.h:152`) and falls back to `m_retryhdr`. The reference sets 0 and calls
`m_retry`; **`_m_retryhdr` does not appear in the import list at all**, which settles
it. And 0x6C = 108 = `MLEN` (`MSIZE` 128 − `sizeof(struct m_hdr)` 20, `mbuf.h:72`), not
`MHLEN` = 100 (`mbuf.h:73`).

Consistently with that, the reference **never writes `m_pkthdr`**. At 856 it sets only
`m->m_len = len`, and at 871-874 only `m->m_len -= hlen` and `m->m_data += hlen`.

**Our source**

```c
MGETHDR(m, M_WAIT, MT_DATA);
if (m == 0)
	return (ENOBUFS);
if (len > MHLEN) {
...
	m->m_len = len;
	m->m_pkthdr.len = len;
	*mp = m;
...
		m->m_len -= hlen;
		m->m_pkthdr.len -= hlen;
		m->m_data += hlen; /* XXX */
```

**Difference:** three linked changes — `MGETHDR` → `MGET`, `MHLEN` → `MLEN`, and the two
`m->m_pkthdr.len` statements deleted.

Everything else in the 534-byte function matches: the eleven-entry jump table at 448,
all five `sa_family`/`hlen` arms (`DLT_SLIP` → `AF_INET`/0, `DLT_PPP` and `DLT_NULL` →
`AF_UNSPEC`/0, `DLT_EN10MB` → `AF_UNSPEC`/14, `DLT_FDDI` → `AF_UNSPEC`/24, default →
`EIO`), the `MCLBYTES` = 0x800 bound, the whole `MCLGET` expansion with its
`(m_flags & M_EXT) == 0` test and `ENOBUFS` = 55, both three-argument `uiomove` calls
(the live `BSD >= 199103` `UIOMOVE`), and the `m_freem` tail.

**Disposition:** fix.

**Rationale:** match the reference. Note this is a case where the reference is arguably
*worse* — `bpfwrite` hands the result to `(*ifp->if_output)`, which normally wants
`M_PKTHDR` — but reproducing the shipped binary is the goal, and the missing
`m_retryhdr` import makes the reading unambiguous. Task 4 should make this change
deliberately and with the tradeoff recorded, not silently.

### `_bpf_attachd` (956) and `_bpf_detachd` (988)

**Finding 6 — `*bp->bif_driverp = bp` is commented out.** `bpf.c:291`.

**Reference behaviour**

```
976: 8B4208  mov eax, [edx+8]   ; bp->bif_driverp
979: 8910    mov [eax], edx     ; *bp->bif_driverp = bp
```

`src/kernel-7/bsd/net/bpfdesc.h` puts `bif_driverp` at offset 8 in `struct bpf_if`
(`bif_next` 0, `bif_dlist` 4, `bif_driverp` 8), so the reading is exact.

**Our source**

```c
	d->bd_bif = bp;
	d->bd_next = bp->bif_dlist;
	bp->bif_dlist = d;

/*	*bp->bif_driverp = bp; */
```

**Difference:** the reference executes the statement; ours has it commented out. The
three preceding stores match exactly (0x1C, 0, +4).

**Disposition:** fix.

**Finding 7 — `*d->bd_bif->bif_driverp = 0` is commented out.** `bpf.c:331`.

**Reference behaviour**

```
1082: 837F0400      cmp dword ptr [edi+4], 0    ; if (bp->bif_dlist == 0)
1086: 750C          jnz loc_44C
1088: 8B461C        mov eax, [esi+1Ch]          ; d->bd_bif
1091: 8B4008        mov eax, [eax+8]            ; ->bif_driverp
1094: C70000000000  mov dword ptr [eax], 0      ; *... = 0
1100: C7461C00000000 mov dword ptr [esi+1Ch], 0 ; d->bd_bif = 0
```

**Our source**

```c
	if (bp->bif_dlist == 0)
		/*
		 * Let the driver know that there are no more listeners.
		 */
	    /* *d->bd_bif->bif_driverp = 0 */;
	d->bd_bif = 0;
```

which leaves an `if` guarding an empty statement.

**Difference:** same as Finding 6, in the teardown direction. Everything else in the
129-byte function matches: the `bd_promisc` / `ifpromisc(bp->bif_ifp, 0)` arm with its
`panic("bpf: ifpromisc failed")`, the descriptor-list walk with
`panic("bpf_detachd: descriptor not in list")`, the unlink, and the `bd_bif` clear.

**Disposition:** fix.

**Rationale (Findings 6 and 7 together):** these two are the same omission and must be
fixed together, because they are the two halves of one protocol. `bif_driverp` points
into the network driver's softc; the attach stores the `bpf_if` there and the detach
clears it, which is how a driver learns whether any listener is attached. With both
commented out the field is never touched. Combined with Finding 2 this is why the
driver, as committed, cannot capture a packet.

### Configuration table

**Finding 8 — `Default.table` lacks the `Version` key.**
`src/drvBPF/BPF.drvproj/Default.table`. `diff` against the reference's table reports
exactly two differences and no third:

```
5d4
< "Version" = "1.0";
9d7
< "Driver Version" = "PROGRAM:BPF  PROJECT:drvBPF-3  DEVELOPER:root  BUILT:Sun Mar 29 03:25:39 PST 1998";
```

The second is build-generated — the build injects it, and the matching
`_BPF_VERS_STRING` in `__const` carries the same stamp ten seconds earlier
(`03:25:29` versus the table's `03:25:39`). **Accepted, not a finding.**

The first is ours to add.

**Disposition:** fix — add `"Version" = "1.0";` after the `"Driver Name"` line, matching
the reference's key order.

`English.lproj/Localizable.strings` is **identical** to the reference. The reference's
`.config` has `English.lproj/Help/` where our source has `English.lproj/DriverHelp/`;
that rename is a `pb_makefiles` convention, not a divergence, and `BPF.rtfd`,
`TableOfContents.rtf` and both `PixelRule.tiff` files are present in ours.

---

## 7. Tooling change made during this pass

**No driver source was changed.** One binrecon change was required to produce
`source-map.json` at all, and it is recorded here because it is not a driver change and
Task 4 should not be surprised by it.

`binrecon.source_map.source_sites` could not see any C function in `bpf.c` or
`bpf_filter.c`. These are BSD sources in K&R style, and two things defeated the scanner:

1. `_C_DEFINITION` could not match a bare K&R header such as
   `bpf_movein(uio, linktype, mp, sockp, datlen)`, because the return type sits on the
   preceding line and the regex required a prefix before the function name.
2. K&R parameter declarations (`register struct uio *uio;`) each end in `;`, which the
   forward scan read as a prototype terminator and rejected the definition.

The fix makes the return-type prefix optional, and stops an **indented** `;`-terminated
line from terminating the scan when the matched line already closed its parameter list
with `)`. Both conditions are needed; neither alone is sufficient.

Verification, not assertion:

- `tools/binrecon/tests`: **662 passed, 4 skipped** — unchanged.
- `source_sites` output was dumped across every source directory referenced by every
  committed `source-map.json` in the repo, before and after the change, and diffed. The
  diff is **purely additive and entirely within drvBPF**: 30 new keys, zero changed, zero
  removed. No other driver's mapping moves.

Before the change `source-map.json` had `mapped` 3 / `unmapped` 27. After it has
`mapped` 28, `unmapped` 2, `duplicate_candidates` 0, `boundary_disputed` 0 — exactly
what the brief predicted.

## 8. Unresolved

- Whether Apple's `bpf.c` really carried the `*bp->bif_driverp` statements as live code
  or whether the shipped binary was built from a source where our comment markers were
  absent for a different reason. The binary is unambiguous about what executes; the
  comment in our tree is a reconstruction artifact and its provenance is not
  recoverable.
- Why the reference uses `MGET` rather than `MGETHDR` in `bpf_movein` (Finding 5). The
  4.4BSD original this file derives from uses `MGETHDR`. Whether Apple changed it
  deliberately or inherited an older revision is not recoverable from the binary.

## README status

`src/drivers-i386/README` does not list this driver at all — and would not naturally,
since `drvBPF` lives at `src/drvBPF/`, not under `src/drivers-i386/`. Task 9 should add
a section for it. After the report pass, and **before** Task 4 lands, the accurate line
is:

```
network
 * drvBPF - reconstructed against the reference binary, fixes not yet applied
```

Once Task 4 applies Findings 1-8, it should read `reconstructed against the reference
binary, fixes applied, not yet compiled or tested` — and no stronger claim than that,
because this driver has never been built.
