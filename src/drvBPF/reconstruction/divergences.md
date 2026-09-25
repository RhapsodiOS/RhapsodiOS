# drvBPF reconstruction divergences

Report pass over Apple's shipped `BPF_reloc`
(`reference_sha256` `56DF84EDC7D77C0799A036C21BE43D833A926BCAA6DA48512DF99CEE7A1B86DB`,
32020 bytes, `MH_PRELOAD` i386). This document records where our reimplementation in
`src/drvBPF/BPF.drvproj/BPF.lksproj/` diverges from that binary.
**It changes no driver source.** Task 4 does the fixing.

Line numbers are against the current committed tree (`BPF.m` 132 lines,
`bpf.c` 1291, `bpf_filter.c` 565, `BPF.h` 47), verified with `git status`
before the pass began.

**Task 4 has since applied Findings 1-8.** The line numbers quoted in each finding are
the pre-fix ones and are left as written; the post-fix locations are in the
`**Outcome:**` lines and in the regenerated `source-map.json`. The depth table in
Section 1 likewise describes the report pass; the post-fix counts are 27
`assembly-matched`, 1 `control-flow-confirmed`, 0 `unexamined` and 2
`intentional-mismatch`.

**Findings 9 and 10 were added later**, by the whole-branch review, against two functions
this pass had wrongly recorded as matched. They are also fixed. The post-fix ledger counts
are unchanged by them.

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

**Two of the entries in the `assembly-matched` row above were wrong.** The whole-branch
review found real divergences in `+[BPF probe:]` (0) and `_bpf_tap` (3124), both of which
this pass had recorded as matched with no divergence. They are Findings 9 and 10, and
both are now fixed. So the honest reading of the report pass is 21 matched and 7
divergent, not 23 and 5.

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

**Outcome:** fixed. `BPF.h:35` now imports `<driverkit/IODirectDevice.h>` and `BPF.h:37`
declares `@interface BPF : IODirectDevice`. No ivars were added, so `instance_size` stays
`IODirectDevice`'s own 296. This is class metadata rather than a function, so it carries
no ledger entry of its own; it is corroborated by the `stru_2024.super_class` loads in the
two `objc_msgSendSuper` sites at 219 and 383, both of which were re-read.

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

**Outcome:** fixed. `BPF.m:95-97` now opens the method body with
`bpfops.bpf_tap = bpf_tap;` and `bpfops.bpf_mtap = bpf_mtap;`, ahead of the `setName:`
send, matching the reference's order. To declare `bpfops` the file gained
`#define _KERNEL`, a `struct mbuf;` forward declaration and `#import <net/bpf.h>`
(`BPF.m:40-42`), plus `extern` prototypes for `bpf_tap` and `bpf_mtap` in the existing
external-function block (`BPF.m:52-53`). All 105 bytes at 156-260 were re-read after the
edit and every instruction now has a counterpart in our source. Ledger 156 advanced
`unexamined` → `assembly-matched`.

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

**Outcome:** fixed. The `expected`/`p1`/`p2` loop is gone; `BPF.m:111` now reads
`if (strcmp(parameterName, "BpfMajorMinor") == 0 && *count == 2) {`, and `BPF.m:38` adds
`#import <string.h>` for the declaration, matching the convention other `.m` files in
this tree use. All 147 bytes at 264-410 were re-read after the edit. **The status was
held at `control-flow-confirmed`, not advanced to `assembly-matched`**: the reference
expands the compare inline as `repe cmpsb` at 281-301, and with no compiler available
there is no way to confirm our `strcmp` call compiles to that expansion rather than a
`call _strcmp`. Everything else in the function was matched instruction for instruction.
Ledger 264 advanced `unexamined` → `control-flow-confirmed`.

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

**Outcome:** fixed. `parameterArray` is now `unsigned int *` in both the `@interface`
(`BPF.h:41`) and the `@implementation` (`BPF.m:106`), so `__meth_var_types` encodes `^I`
at offset 16. Both `parameterArray` stores remain 32-bit writes, so no instruction
changed. This finding shares ledger entry 264 with Finding 3 and is covered by that
entry's `control-flow-confirmed` status; the type-encoding change itself is fully
confirmed, and only Finding 3's `repe cmpsb` question holds the entry short of
`assembly-matched`.

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

**Outcome:** fixed, deliberately and with the tradeoff above understood. `bpf.c:232`
is now `MGET(m, M_WAIT, MT_DATA)`, `bpf.c:235` tests `len > MLEN`, and both
`m->m_pkthdr.len` statements (the `= len` after the cluster path and the `-= hlen` inside
the link-header block) are deleted. Nothing else in the function was touched. All 534
bytes at 420-953 were re-read after the edit: `m_flags = 0` at 678, the `_m_retry` call
at 692, `cmp [ebp+var_4], 6Ch` at 716, the single `m_len` store at 856 and the lone
`m_len -= hlen` at 871 now all follow from our source, and the function writes
`m_pkthdr` nowhere. The known consequence stands: `bpfwrite` hands the result to
`(*ifp->if_output)` without `M_PKTHDR`, exactly as the shipped binary does. Ledger 420
advanced `unexamined` → `assembly-matched`.

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

**Outcome:** fixed. `bpf.c:289` is now the live statement `*bp->bif_driverp = bp;`; the
comment markers are gone and the surrounding comment block is untouched. All 29 bytes at
956-984 were re-read after the edit and every store maps to a statement in order, ending
with the `[edx+8]` load and `[eax]` store at 976-979. Ledger 956 advanced `unexamined` →
`assembly-matched`.

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

**Outcome (Finding 7):** fixed. `bpf.c:329` is now the live statement
`*d->bd_bif->bif_driverp = 0;` guarded by the existing `if (bp->bif_dlist == 0)`, so the
`if` no longer guards an empty statement; the explanatory comment between them is
unchanged. Note the reference reloads `d->bd_bif` from `[esi+1Ch]` at 1088 rather than
using the `bp` already in `edi`, which is why the statement is written through `d` and
not through `bp`. All 129 bytes at 988-1116 were re-read after the edit. Ledger 988
advanced `unexamined` → `assembly-matched`.

Findings 6 and 7 were applied together, as the report pass required.

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

**Outcome:** fixed. `Default.table:5` is now `"Version" = "1.0";`, between
`"Driver Name"` and `"Post-Load"`. `"Driver Version"` was deliberately not added, as it
is build-generated and would bake in Apple's 1998 build host. The table now differs from
the reference's by that one build-generated line only. `Default.table` carries no ledger
entry.

`English.lproj/Localizable.strings` is **identical** to the reference. The reference's
`.config` has `English.lproj/Help/` where our source has `English.lproj/DriverHelp/`;
that rename is a `pb_makefiles` convention, not a divergence, and `BPF.rtfd`,
`TableOfContents.rtf` and both `PixelRule.tiff` files are present in ours.

### Found later, by the whole-branch review

Findings 9 and 10 were **not** produced by the report pass. Both functions had been
recorded as `assembly-matched` — "every instruction read, and no divergence found" — and
both claims were wrong. They are written up here in the same form as the rest.

**Finding 9 — `+[BPF probe:]` sends a selector that does not exist.**
`BPF.m:69-81` (pre-fix).

**Reference behaviour** — the eleven `IOSwitchFunc` arguments, pushed right-to-left at
11-61, then the descriptor, the selector and `self`:

```
11: push offset _enodev        21: push offset _enodev      41: push offset _bpfioctl
16: push offset _enodev        26: push offset _bpf_select  46: push offset _bpfwrite
                              31: push offset _nulldev     51: push offset _bpfread
                              36: push offset _nulldev     56: push offset _bpfclose
                                                           61: push offset _bpfopen
66: push esi                  ; deviceDescription
80: add esp, 38h              ; 14 * 4 = 12 method arguments + self + _cmd
```

`__meth_var_names` at 8782 holds the selector string verbatim:

```
addToCdevswFromDescription:open:close:read:write:ioctl:stop:reset:select:mmap:getc:putc:
```

Twelve keywords, matching the `add esp, 38h` arity, and matching the declaration at
`src/driverkit-3/driverkit/IODevice.h:112-123`.

**Our source** named the last two keywords `strategy:` and `getstat:`.

**Difference:** the *values* were right — all three of `mmap`, `getc` and `putc` are
`enodev` in the reference, and our source passed `enodev` three times — but the selector
we composed, `...select:mmap:strategy:getstat:`, is not a method of `IODevice`. The
earlier read checked the pushed function pointers and never checked the keyword names
against `IODevice.h` or against `__meth_var_names`.

**Disposition:** fix.

**Rationale:** load-bearing. An unrecognised selector makes `+probe:` fail, so the cdevsw
entry is never installed and `/dev/bpf*` never opens — which would have defeated the
`bpfops` repair of Finding 2 that this branch exists to make.

**Outcome:** fixed. `BPF.m:78-80` now reads `mmap:` / `getc:` / `putc:`, each still
`(IOSwitchFunc)enodev`. All 51 instructions at 0-155 were re-read after the edit and
every one has a counterpart in our source. Ledger 0 keeps `assembly-matched`; a third
`analyzer_agreement` reason records the false claim, the correction and the post-repair
re-read. Note that the ledger's transition rule is forward-only, so `assembly-matched`
could not have been walked back even had the post-repair evidence been weaker — that is
recorded in §8.

**Finding 10 — `bpf_tap`'s K&R parameter names do not agree; the file cannot compile.**
`bpf.c:1019-1022` (pre-fix).

**Reference behaviour** — the function prologue and the first use of the argument:

```
3130: 8B4508    mov eax, [ebp+arg_0]
3139: 8B5804    mov ebx, [eax+4]      ; bp->bif_dlist
```

`arg_0` is read once and dereferenced at +4 with no intervening indirection, so it *is*
the `struct bpf_if *` — not an `ifnet` from which one is reached. `_bpf_mtap` (3296) does
the identical thing at 3305/3325 (`mov edx, [ebp+arg_0]`, `mov ebx, [edx+4]`), and its
source already declares `caddr_t arg;`. `src/kernel-7/bsd/net/bpf.h:286-288` types the
`bpfops_t` slot as `void (*bpf_tap)(caddr_t, u_char *, u_int)`, and `BPF.m:52` externs it
the same way.

**Our source**

```c
bpf_tap(arg, pkt, pktlen)
	struct ifnet *ifp;
	register u_char *pkt;
	register u_int pktlen;
{
	...
	bp = (struct bpf_if *)arg;
```

**Difference:** the parameter list names `arg`, the declarations name `ifp`. `arg` is
then undeclared where the body casts it, and `ifp` is declared but is not a parameter —
a hard `gcc` error, in live code (`bpf.c:58` defines `BPFDRV`). The body itself was
correct and matched; only the declaration was wrong, which is what the earlier read
missed by reading the body and not the signature.

**Disposition:** fix.

**Rationale:** compile blocker on the packet-capture path, and inconsistent with
`bpf_mtap` two functions below it.

**Outcome:** fixed. `bpf.c:1020` now declares `caddr_t arg;`, matching `bpf_mtap`, the
`bpfops_t` slot and the `extern` in `BPF.m`. All 40 instructions at 3124-3202 were re-read
after the edit and every one has a counterpart in our source. Ledger 3124 keeps
`assembly-matched`, with a third reason recording the false claim and the correction.
**Stated limit:** the assembly settles *how* the argument is used — as a `bpf_if *`, with
no `ifnet` deref — but not the C spelling of its declared type; `caddr_t` comes from
`bpf_mtap` and from `bpf.h`, not from the disassembly.

---

## 7. Tooling change made during this pass

**No driver source was changed.** One binrecon change was required to produce
`source-map.json` at all, and it is recorded here because it is not a driver change and
Task 4 should not be surprised by it.

`binrecon.source_map.source_sites` could not see any C function in `bpf.c` or
`bpf_filter.c`. The underlying bug is not K&R-specific — it is that the scanner could
not handle a definition whose **return type sits on its own line**, which is broader
than K&R and also affects plain ANSI definitions. Two things defeated the scanner:

1. `_C_DEFINITION` could not match a bare header such as
   `bpf_movein(uio, linktype, mp, sockp, datlen)` (K&R) or a wrapped ANSI definition,
   because the return type sits on the preceding line and the regex required a prefix
   before the function name on the same line.
2. K&R parameter declarations (`register struct uio *uio;`) each end in `;`, which the
   forward scan read as a prototype terminator and rejected the definition.

The fix makes the return-type prefix optional, and stops an **indented** `;`-terminated
line from terminating the scan when the matched line already closed its parameter list
with `)`. Both conditions are needed; neither alone is sufficient.

Verification, not assertion:

- `tools/binrecon/tests`: **665 passed, 4 skipped** — the 662 baseline plus the three
  regression tests that pin the scanner fix described in §7. No existing test changed.
- `source_sites` output was dumped across every source directory referenced by every
  committed `source-map.json` in the repo, before and after the change, and diffed. The
  diff is **additive only, everywhere**: **172 sites added across 16 driver source
  directories, 0 removed and 0 changed anywhere.** Only 30 of the 172 additions are
  drvBPF's; the return-type-on-its-own-line pattern is common across the tree,
  including plain ANSI definitions such as `IOMallocPage`, `ide_block_char_majors` and
  `inb`, not just K&R. The largest gainers besides drvBPF were MatroxMGA (+37),
  IntelAC97 (+22), drvEIDE (+20), drvSCSITape (+14) and SMC16 (+12). None of the other
  15 directories has a committed `source-map.json` in this repo, so no committed
  artifact besides drvBPF's is invalidated by this change; the 10 that do exist belong
  to drvEISABus, drvPCIBus, drvPCMCIABus, Intel82365PCMCIA, Intel824X0PCI, drvBusMouse,
  drvPCParallel, drvPS2Keyboard, drvPS2Mouse and drvSerialPointingDevice — none of which
  is among the 16.

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
- The ledger's `transition` is forward-only along
  `unexamined → signature-confirmed → control-flow-confirmed → assembly-matched`, so a
  status recorded in error cannot be walked back; the only exit from `assembly-matched` is
  the terminal `intentional-mismatch`. Entries 0 and 3124 therefore keep
  `assembly-matched`, which their post-repair full-stream re-reads do support, but the
  ledger has no way to express "this was once claimed wrongly" other than the corrective
  `analyzer_agreement` reason now attached to each.

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

## Forced divergence: the driver allocates the descriptor table

2026-09-25. For kernel-7, at the user's request.

Loaded on the i386 QEMU guest, which runs this tree's kernel-7
(kernel-154.5.1-7), the driver answered every open with `ENXIO`. Nothing
allocates the descriptors.

The reference was built for a kernel that owned them. Apple's DR2 i386
`mach_kernel` has `_bpf_dtab` as a 60-byte `__common` block (0x22829c, with the
next symbol at 0x2282d8; `sizeof(struct bpf_d)` is 0x3c), so
`struct bpf_d bpf_dtab[1]`, and `_nbpfilter` as an initialised 1 in `__data`.
Its `_bpfattach` ends with the 4.4BSD loop that marks the descriptors free. The
reference indexes that array directly. All six of its index sites are a `lea`
with `_bpf_dtab` as the displacement, which is what `extern struct bpf_d
bpf_dtab[]` compiles to: `_bpfopen` 1160 and 1166, `_bpfclose` 1223, `_bpfread`
1292, `_bpfwrite` 1538, `_bpfioctl` 1761, `_bpf_select` 3045.

kernel-7 is Darwin 0.3's source, unchanged here. `bsd/net/bpf.c:123-124`
declares `struct bpf_d *bpf_dtab;` and
`int nbpfilter = -1; /* Mark as uninitialized; BPF will init */`, and its
`bpfattach` no longer marks anything free. Between DR2 and Darwin 0.3 Apple
handed the table to the driver. The reference cannot work on kernel-7: it sees
`nbpfilter` as -1, and it would index the 4-byte pointer variable as though it
were the table. On the guest, Apple's binary got no working nodes either.

Fix, in the driver and not the kernel, because kernel-7's own comment gives the
job to the driver: `bpfilterattach(n)`, empty in the reference, now allocates n
descriptors with `MALLOC`, zeroes them, marks each free and sets `nbpfilter`
last. `-initFromDeviceDescription:` calls it with 4 before it installs
`bpfops`. Four is xnu's `NBPFILTER`; PostLoad's `path[10]` holds names up to
`/dev/bpf9`. This costs parity in `_bpfilterattach` (412) and
`-[BPF initFromDeviceDescription:]` (156).

**Correction to §5 and the ledger.** §5 called our
`extern struct bpf_d *bpf_dtab;` "correct as written", and the ledger records
the six functions above as `assembly-matched`. Neither is right. A pointer
declaration compiles each index site to a load of the pointer and then the
index, an instruction the reference does not have. The pointer is now the right
declaration for kernel-7, so this belongs to this divergence rather than being a
parity bug to fix, but those six ledger claims missed it. The ledger's
transitions are forward-only (§8), so it is recorded here instead.

## Forced divergence: written frames carry a packet header

2026-09-25. From a reference defect, fixed at the user's request. This reverses
Finding 5.

Finding 5 matched the reference's `MGET` in `bpf_movein` and noted that
`bpfwrite` would then hand `if_output` a frame without `M_PKTHDR`. On the guest
that is fatal. The tree's IOEthernet output
(`src/driverkit-3/libDriver/Kernel/IOEthernet.m:625`) logs
`IOEthernet: M_PKTHDR flag not set (0001)` and frees every frame a BPF client
writes, so dhcpcd's DISCOVER never left the machine.

Fix, as in 4.4BSD and Darwin's later `bpf.c`: `MGETHDR`, the cluster threshold
back to `MHLEN`, and after `m->m_len = len`, `m->m_pkthdr.len = len - hlen` and
`m->m_pkthdr.rcvif = 0` (`MGETHDR` leaves `rcvif` unset). This costs parity in
`_bpf_movein` (420), and the binary now imports `_m_retryhdr`.

## PostLoad: the device-count loop is signed again

2026-09-25. Not a divergence: a reconstruction error, put back to parity.
`PostLoad.tproj` is outside the ledger (§2).

`PostLoad.m` declared its loop counter `unsigned int`, so `i < bpfValues[1]`
compared against the -1 of an unset `nbpfilter` as 0xFFFFFFFF. On the guest it
made 7938 `/dev/bpf*` nodes before it was killed, overrunning `path[10]` from
`/dev/bpf10` on. With BPF in Active Drivers it would hang boot in
`0300_Devices`. The reference's `_main` compares signed, with `jle` at 0x3ceb
before the loop and `jg` at 0x3dbf after the `inc esi`. `i` is an `int` again.

## Default.table: "Server Name" came out twice

2026-09-25. Not a divergence: Finding 8's outcome missed it.

The driver build's `post_copy_tables` rule
(`src/driverTools-1/DriverProjectType/driver.make:154-159`) appends
`"Server Name" = "$(NAME)";` to every table. That is why the reference's
shipped table has the line once, just before the build-stamped
`"Driver Version"`. Our source table carried it as well, so the built table had
it twice; Finding 8 compared the source table with the shipped one and did not
allow for the append. The line is gone from the source, and the built table now
matches the reference's except for the build stamp. Most other driver tables
in the tree carry the same line and get the same duplicate; they are not
changed here.

## Build warnings

2026-09-25. Neither change alters generated code.

- `splimp`, `splnet` and `splx` were implicitly declared (first at the `MGET`
  expansion in `bpf_movein` and in `bpfwrite`). The `#include <machine/spl.h>`
  for `BPFDRV` builds had sat inside `#if 0` since the file was added. It is
  live again; kernel-7 exports `bsd/machine/spl.h`, which pulls in
  `kernserv/<arch>/spl.h`.
- `catchpacket(d, pkt, pktlen, slen, bcopy)` passed `bcopy`, whose length is a
  `size_t` (`unsigned long`), where the copy-function parameter said `u_int`.
  That parameter and `bpf_mcopy`'s length are now `size_t`, as in later BSDs and
  xnu. Both types are 32 bits on both targets.

## Guest test

2026-09-25, on a private `-snapshot` QEMU guest booted from
`vm/work/rhap-i386-bootstrapped.img`, running kernel-7 (kernel-154.5.1-7
RELEASE_I386). Built there with `rbuild buildpackage --toolchain
/build/src/rbuild-1/toolchains/gcc-darwin-i386.conf --arch i386` into
`bpf-3-i386.apk`. The spl and `catchpacket` warnings are gone. The warnings
left are `_KERNEL` redefinitions, `struct ifnet`/`struct mbuf` scope notes from
installed headers, `A`/`X` in `bpf_filter`, and PostLoad's `IODeviceMaster`
stubs; this change touched none of those lines. The built `Default.table` has
one `"Server Name"`, where the reference has it.

- `driverLoader D=BPF` loaded it (`Registering: bpf`), and PostLoad made
  `/dev/bpf0` to `/dev/bpf3` and no more.
- A 60-byte ARP request for 10.10.0.1, written to `/dev/bpf0` bound to `en0`,
  returned 60. It appears in a QEMU `filter-dump` capture of the NIC, and
  slirp's reply was read back through the same descriptor. The console printed
  no `M_PKTHDR` message.
- With `/dev/bpf0` to `/dev/bpf2` held open, the same test got `EBUSY` on each
  and ran on `/dev/bpf3`, so all four descriptors start free.
- Control: Apple's `BPF_reloc` with the rebuilt PostLoad. PostLoad finished at
  once and made no nodes.
- With `BPF` added to `Instance0.table`'s Active Drivers, boot's
  `driverLoader a` loaded it, boot reached the login window, `/dev/bpf0` to
  `/dev/bpf3` were there, and the write test passed again.

dhcpcd was not rerun against this build; the dhcpcd-1 session's lease tests
used a guest-only driver carrying equivalent fixes.
