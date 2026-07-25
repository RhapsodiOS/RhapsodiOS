# Intel82365PCMCIA divergences

Reference: `PCIC_reloc`, SHA-256 `80360707448AF7E4E100CE24993E0728F5DDC688D1D31DA5161478B0BCC3A208`
Analyses: IDA 9.2, Ghidra 12.1, angr 9.3.0

## Baseline build

**No build was performed as part of this pass.** There is no transport from this
machine to a Rhapsody build guest, so this report carries no build verdict of its
own and none is estimated.

What is on disk, and is reported here as labelled supplementary evidence only:
an untracked staged artifact at
`out/i386/Intel82365PCMCIA/PCIC.config/PCIC_reloc`, 243784 bytes, SHA-256
`24B7276D1A339C6B05D2C6FD43EE12756672230A799084E72E23A5E3BF01CE15`, mtime
2026-07-25 13:19, alongside an `out/i386/Intel82365PCMCIA/README.txt` recording
`make exit status was: 0`. **Its provenance is inferred, not observed** — it was
not produced by our build script during this effort, and nothing establishes when
it was built or against which revision of the six `.m` files.

Two things are consistent with it having come from the current tree, and are
recorded as circumstantial only:

- The staged `PCIC.config/PCI.table` and `PCIC.config/Default.table` are
  byte-identical to `src/drivers-i386/bus/Intel82365PCMCIA/PCIC.drvproj/PCI.table`
  and `.../Default.table`, including the `"Server Name"` defect recorded as
  Finding 17.
- Its symbol table carries a stabs entry naming the build path
  `/build/source/src/drivers-i386/bus/Intel82365PCMCIA/PCIC.build/derived_src/PCIC.drvproj/PCIC.lksproj/PCIC_instance.m`
  and file stabs for `PCIC.m`, `PCICDebug.m`, `PCICInternal.m`, `PCICSocket.m`,
  `PCICWindow.m` and `PCICWindowAttributes.m` — the same six files our tree has.

The artifact is larger than the reference's 38700 bytes because our builds are
unstripped; that size difference would not be a finding.

Findings 1, 8, 9, 11 and 17 quote measurements taken from this artifact. Each such
quotation is labelled at the point of use. Every one of them is corroborated by
the source text itself, so no finding depends on the artifact alone.

## Baseline parity

The Task 3 Step 5 baseline parity run of record was not performed, for the same
reason. `tools/binrecon/parity_check.py` **was** run during this pass against the
staged artifact described above, as an independent cross-check on the disassembly
work. It is recorded here labelled as such. Abbreviated output (the 101
`extra_symbols` are almost all stabs debug entries, the expected consequence of
comparing an unstripped object against a stripped one; the load-bearing ones are
quoted in the findings):

```
missing_strings (2):
    'PCIC: No device at base address 0x%04x\n'
    'PCIC: PCMCIA->PCI Bus Bridge Detected (Dev=%d, Bus=%d)\n'
missing_symbols (13):
    '-[PCIC(Debug) readAttributeMemory:forSocket:]'
    '-[PCIC(Debug) spoofInterrupt]'
    '-[PCIC(Internal) readRegister:socket:]'
    '-[PCIC(Internal) writeRegister:socket:value:]'
    '-[PCIC_PCI initFromDeviceDescription:]'
    '_FindEmptyMemoryRange'
    '_MapAttributeMemory'
    '_checkForCirrusChip'
    '_setIoWindow'
    '_setMemoryWindow'
    '_setStatusChangeInterrupt'
    '_setWindow'
    '_socketIsValid'
extra_strings (8):
    ' (Cirrus)'
    'I/O Ports'
    'PCIC: Failed to create any sockets\n'
    'PCIC: Failed to create socket list\n'
    'PCIC: Failed to create window list\n'
    'PCIC: Hardware validation failed at port 0x%x\n'
    'PCIC: Initialized at port 0x%x, IRQ %d, %d sockets%s\n'
    'PCIC: No I/O port range specified\n'
```

Read plainly: twelve of the thirteen `missing_symbols` are naming divergence,
not missing code (§ Naming divergence) — the underlying functions exist and, in
ten of the twelve cases, match the reference instruction for instruction. The
thirteenth, `-[PCIC_PCI initFromDeviceDescription:]`, is genuinely absent. Eight
of the reference's ten `__cstring` entries are present in our build; the two that
are missing belong to code we do not have (`PCIC_PCI`) or to a log site we
reconstructed with different text.

## Post-fix parity

**Not run, and post-fix parity is unverified.** The fix pass had no transport to a
Rhapsody build host, so **no build was performed and no post-fix artifact exists**.
`parity_check.py` was not re-run: it would only have re-measured the same unchanged
staged binary described under § Baseline build and reported the pre-fix numbers,
which would be worse than no number at all. No parity output is recorded here, and
none is estimated or guessed.

What this leaves unverified is worth naming plainly: **every source change recorded
in the `**Outcome:**` lines below is uncompiled.** Nothing here establishes that
the six `.m` files still build, that the thirteen `missing_symbols` are now
present, that the two `missing_strings` now appear verbatim, that the eight
`extra_strings` are gone, or that the rewritten `-[PCIC
initFromDeviceDescription:]` and the newly written `_setWindow` and
`-[PCIC_PCI initFromDeviceDescription:]` are anywhere near the reference's 639,
436 and 221 bytes. That is also why no ledger entry is `assembly-matched`: that
status requires instruction-level evidence from a rebuilt binary, and the ceiling
for a source-only change is `control-flow-confirmed`.

### Unresolved build-time risk: the return convention of `-[PCICSocket status]`

**Whoever gets a build first must check this before anything else.**

`-[PCICSocket status]` now returns `PCMCIAStatus`, a 4-byte bitfield struct, which
is what the reference's type encoding declares (Finding 11(f)). `drvPCMCIABus`
separately declares the *same selector* as `- (unsigned int)status` in its
`Object(PCMCIASocketWindowMethods)` category at
`src/drivers-i386/bus/drvPCMCIABus/PCMCIABus.drvproj/PCMCIABus.lksproj/PCMCIAKernBusPrivate.h:32-37`
(the declaration itself is line 36), and calls it at `PCMCIAKernBus.m:724`,
`PCMCIAKernBusPrivate.m:64` and `PCMCIAKernBusPrivate.m:1242`.

Apple's binary returns the value in `eax` with no hidden struct-return pointer —
verified by reading the reference at address 3836: its first argument slot
`[ebp+8]` holds `self` (`8B 55 08` then `8B 52 08`, reading `socketNumber` from
ivar +8), so nothing is displaced by a hidden buffer pointer; it loads the result
with `89 F0` (`mov eax, esi`); and it ends `8D 65 F4 5B 5E 89 EC 5D C3`, a plain
`ret` rather than the `ret $4` a callee-popped struct pointer would need. That is the
`-freg-struct-return` convention, under which the two declarations agree at the
ABI level and the call across the driver boundary is safe.

Under `-fpcc-struct-return` it is not. The callee would use the stret convention —
a caller-allocated buffer passed as a hidden first argument, popped by the callee
— while `drvPCMCIABus`, which sees a scalar return type, emits a plain
`objc_msgSend` and reads `eax`. Nothing diagnoses this: the two translation units
are compiled from different headers in different projects and the linker sees only
`objc_msgSend`. The result would be a silently corrupted status value and a
misaligned stack at every one of the three call sites.

**Check to perform on the first build:** disassemble the emitted
`-[PCICSocket status]` and confirm it takes no hidden struct pointer (two
arguments, `self` and `_cmd`, and a plain `ret`). If it does take one, either the
compiler must be given `-freg-struct-return` for this project or `drvPCMCIABus`'s
declaration must be brought into agreement. This was not resolvable without a
compiler and is recorded here rather than guessed at.

## Summary

| Bucket | Count |
| --- | --- |
| mapped | 79 |
| unmapped | 3 |
| duplicate_candidates | 0 |
| boundary_disputed | 0 |

**All 82 reference functions were read at instruction level; not all 82 carry a
per-function write-up.** The whole `__TEXT,__text` section is 7548 bytes, small
enough that a complete read was affordable, and none was deferred. Concretely:

- **82 read at instruction level** — full IDA disassembly read side by side
  with the corresponding source text, every register offset, bit mask, branch
  condition and message send checked.
- **0 examined at control-flow level only.**
- **0 left unexamined** beyond confirming existence.
- Per-function findings are recorded for every one of the 82 that diverges on
  its own. Four do not get one: `-[PCIC sockets]` (932), `-[PCIC windows]`
  (948), `-[PCIC setStatusChangeHandler:]` (964) and `-[PCICSocket windows]`
  (3820) diverge only through the ivar offsets they read or write (reference
  +300/+304/+308/+16, ours +312/+316/+320/+12), which is already fully
  recorded in Finding 4.

Two honesty qualifications on that claim. First, for ten of the `PCICSocket`
accessors (addresses 4368, 4420, 4556, 4608, 4736, 4784, 4908, 4956, 5080, 5132)
the disassembly was read with the uniform `io_inline.h` `outb`/`inb` expansion
filtered out, after verifying that expansion byte for byte in three unfiltered
siblings at 4180, 4236 and 5288; every semantically load-bearing instruction in
those ten was read. Second, "instruction level" here means the reference was read
completely and compared against our *source text*; it does **not** mean our
compiled output was diffed against the reference, because no build was run.

**18 hand-written functions carry no divergence** and are listed in § Functions
examined with no divergence found. **62 carry at least one confirmed divergence**
and remain `unexamined` in the ledger, per the convention established by the
drvPCIBus, drvPCMCIABus and Intel824X0PCI passes: a function known to diverge is
written up here rather than given a positive status it has not earned. **2** are
build-generated glue recorded as `intentional-mismatch`.

Twenty findings follow, ordered by severity. Three are accepted; the other
seventeen are marked `fix`.

*Updated by the fix pass:* **sixteen of the seventeen `fix` findings were applied
in full; the seventeenth, Finding 13, was applied in part.** See the `**Outcome:**`
line on each finding for what changed, which commit changed it, and the ledger
status that resulted. The ledger now stands at 76 `control-flow-confirmed` and 6
`intentional-mismatch`, with nothing left `unexamined`. Nothing is
`assembly-matched` and nothing can be until a build exists; see § Post-fix parity,
which also records an unresolved build-time risk in `-[PCICSocket status]` that
must be checked on the first build.

The headline is that the *register-level* reconstruction of this driver is
remarkably good — PCIC index/data port protocol, socket stride of 0x40, every
register number, every bit position and every mask in `PCICSocket` and
`PCICWindow` match Apple's binary exactly — but the driver as it stands **cannot
load**: `PCICSocket.m` references a symbol that does not exist at link time
(Finding 1), the class `PCI.table` names as the driver class does not exist at
all (Finding 3), one of the two window-programming helpers is an empty stub
(Finding 2), and all three classes have the wrong instance-variable layout
(Finding 4).

## Reference `__TEXT,__cstring`, enumerated

Sliced directly out of the reference at file offset 9944, length 291 (section
address 7548):

| Address | String |
| --- | --- |
| 7548 | `PCIC: PCMCIA->PCI Bus Bridge Detected (Dev=%d, Bus=%d)\n` |
| 7604 | `PCIC: No device at base address 0x%04x\n` |
| 7644 | `PCIC` |
| 7649 | `PCMCIA Adapter` |
| 7664 | `PCIC: couldn't enable interrupts\n` |
| 7698 | `PCIC: couldn't start IO thread\n` |
| 7730 | `BIOS at %x, length %x\n` |
| 7753 | `No BIOS at %x\n` |
| 7768 | `buffer: logical %x, physical %x\n` |
| 7801 | `PCIC: readAttributeMemory: not ready\n` |

Ten strings, not the four the earlier spec recorded for `PCICDebug.m` alone. The
`__cstring` order is source-emission order, which is why the two `PCIC_PCI`/`PCIC`
strings lead: `PCIC.m` compiles `PCIC_PCI` first (see § PCIC_PCI: go/no-go).

`__TEXT,__const` at 7839 holds `@(#)PROGRAM:PCIC  PROJECT:drvIntel82365PCMCIA-13
DEVELOPER:root  BUILT:Sat Mar 28 22:08:54 PST 1998\n` (`_PCIC_VERS_STRING`) and,
at 7999, `13` (`_PCIC_VERS_NUM`). Both are `what(1)` version data stamped in by
the build; neither is a finding.

## How the object-file partition was established

This is worth recording because it is what made the rest of the pass tractable
and because it decides Step 4.

The reference is a `ld -r` relocatable link of seven object files. Two independent
signals recover the partition exactly:

1. **`__OBJC,__module_info`.** Seven 16-byte module records, each naming its
   source file and pointing at a symtab that lists the classes and categories
   that file defines. Decoded:

   | Source file | Defines |
   | --- | --- |
   | `PCIC.m` | classes `PCIC` (17312) and **`PCIC_PCI`** (17352) |
   | `PCICDebug.m` | category `PCIC(Debug)` (20756) |
   | `PCICInternal.m` | category `PCIC(Internal)` (20776) |
   | `PCICSocket.m` | class `PCICSocket` (17392) |
   | `PCICWindow.m` | class `PCICWindow` (17432) |
   | `PCICWindowAttributes.m` | category `PCICWindow(Attributes)` (20808) |
   | `PCIC_instance.m` | classes `PCICVersion` (17472), `PCICKernelServerInstance` (17512) |

   The method lists hanging off those class and category structures give each
   method's `IMP`, so every one of the 73 Objective-C methods is attributed to a
   file by the binary's own metadata rather than by inference from link order.

2. **The `io_inline.h` per-translation-unit statics.** `__DATA,__bss` holds five
   consecutive `_xxx.86`/`_xxx.89`/`_xxx.92` triples — the counters
   `<machdep/i386/io_inline.h>` declares `static` and every `outb`/`inb`
   increments. Because they are `static`, each translation unit that performs I/O
   gets its own copy, and the address a function increments names its object
   file:

   | `_xxx.86` address | Translation unit |
   | --- | --- |
   | 8192 | `PCIC.m` |
   | 8204 | `PCICDebug.m` (its file statics `_init.117` at 8216 and `_memory` at 8220 follow) |
   | 8224 | `PCICInternal.m` |
   | 8236 | `PCICSocket.m` |
   | 8248 | `PCICWindow.m` |

The two signals agree everywhere they overlap, and together they place all 82
functions. The resulting file map, which supersedes the link-order estimate the
task brief carried:

| Address range | Source file |
| --- | --- |
| 0–223 | `PCIC.m` (`PCIC_PCI`) |
| 224–1759 | `PCIC.m` (`PCIC`, then the three file statics) |
| 1760–2699 | `PCICDebug.m` |
| 2700–2815 | `PCICInternal.m` |
| 2816–5367 | `PCICSocket.m` |
| 5368–7315 | `PCICWindow.m` |
| 7316–7523 | `PCICWindowAttributes.m` |
| 7524–7547 | `PCIC_instance.m` (build-generated) |

Two corrections to the brief's estimate fall out of this: address 0 is in
`PCIC.m`, not in a file absent from our tree; and `-[PCIC(Debug) spoofInterrupt]`
at 2688 belongs to `PCICDebug.m`, putting the `PCICInternal.m` boundary at 2700
rather than 2700 being the second of two `(Internal)` methods.

## Step 4 resolved: the second `_socketIsValid` at 2816 is in `PCICSocket.m`

The evidence decides, and decides cleanly.

The two bodies are byte-identical over all 74 bytes **except for one byte, at
body offset 25** (`00` versus `2C`; the two relocation targets share their
three high bytes):

```
; 1488  _socketIsValid                     ; 2816  _socketIsValid (second copy)
1488 55           push ebp                 2816 55           push ebp
1489 89E5         mov ebp, esp             2817 89E5         mov ebp, esp
1491 83EC04       sub esp, 4               2819 83EC04       sub esp, 4
1494 8A4D08       mov cl, [ebp+arg_0]      2822 8A4D08       mov cl, [ebp+arg_0]
1497 C0E106       shl cl, 6                2825 C0E106       shl cl, 6
1500 668B15...    mov dx, ds:_reg_base     2828 668B15...    mov dx, ds:_reg_base
1507 88C8         mov al, cl               2835 88C8         mov al, cl
1509 EE           out dx, al               2837 EE           out dx, al
1510 F0FF05 00200000  inc ds:8192  <---    2838 F0FF05 2C200000  inc ds:8236  <---
...                                        ...
```

`8192` is `PCIC.m`'s `_xxx.86`; `8236` is `PCICSocket.m`'s. The copy at 2816
increments `PCICSocket.m`'s counter, so it was compiled in `PCICSocket.m`. Every
other function in the 2816–5367 run increments the same 8236, and every function
in the 224–1759 run increments 8192.

The call graph agrees independently: `-[PCICSocket initWithAdapter:socketNumber:]`
at 2892 reaches it with a direct near call, `2917 E896FFFFFF call 2816` — a
PC-relative displacement of -106, i.e. a same-object-file call — while
`-[PCIC initFromDeviceDescription:]` at 292 calls the copy at 1488 the same way
(`329 E882040000 call 1488`). No call crosses from one run to the other.

Both symbols are `n_type=0x0e` (`N_SECT`, `N_EXT` clear), i.e. both are `static`.
Apple's source therefore declares `static socketIsValid(...)` separately in
`PCIC.m` and in `PCICSocket.m` — two file-local copies of the same function, not
one shared definition. That is the shape Finding 1 is about.

The entry has been moved out of `duplicate_candidates` accordingly. In the source
map both 1488 and 2816 point at `PCIC.m:359`, our tree's single definition,
because that is the source text our build compiles for both behaviours; the
structural difference is Finding 1.

## Naming divergence

Twelve of the thirteen `missing_symbols` above are naming, not absence. Two
distinct patterns, both confirmed from our staged build's own symbol table (read
with a direct `nlist` walk, so this does not rest on the IDA adapter's unreliable
`binding` field):

**Eight C functions carry an extra leading underscore.** Apple's identifiers have
no leading underscore, so the compiler renders them `_socketIsValid`,
`_checkForCirrusChip` and so on. Ours are written `_socketIsValid` *in the C
source*, which the compiler renders one underscore deeper:

| Apple's C identifier | Reference symbol | Our C identifier | Our symbol |
| --- | --- | --- | --- |
| `socketIsValid` | `_socketIsValid` | `_socketIsValid` | `__socketIsValid` |
| `checkForCirrusChip` | `_checkForCirrusChip` | `_checkForCirrusChip` | `__checkForCirrusChip` |
| `setStatusChangeInterrupt` | `_setStatusChangeInterrupt` | `_setStatusChangeInterrupt` | `__setStatusChangeInterrupt` |
| `FindEmptyMemoryRange` | `_FindEmptyMemoryRange` | `_FindEmptyMemoryRange` | `__FindEmptyMemoryRange` |
| `setWindow` | `_setWindow` | `_setWindow` | `__setWindow` |
| `MapAttributeMemory` | `_MapAttributeMemory` | `_MapAttributeMemory` | `__MapAttributeMemory` |
| `setMemoryWindow` | `_setMemoryWindow` | `_setMemoryWindow` | `__setMemoryWindow` |
| `setIoWindow` | `_setIoWindow` | `_setIoWindow` | `__setIoWindow` |

All eight `__`-prefixed forms are present in the staged artifact's symbol table,
which is what establishes this is a spelling difference and not missing code.
Same pattern as the nine C functions in `drvPCMCIABus`.

**Four category selectors carry a leading underscore.** `PCIC(Debug)` and
`PCIC(Internal)` in our tree declare `_readAttributeMemory:forSocket:`,
`_spoofInterrupt`, `_readRegister:socket:` and `_writeRegister:socket:value:`.
The reference's `__OBJC,__meth_var_names` has `readAttributeMemory:forSocket:`
(offset 19903), `spoofInterrupt` (19888), `readRegister:socket:` (19962) and
`writeRegister:socket:value:` (19934) with no underscore, and the category method
lists point at them. This is the same shape as `drvPCMCIABus`'s two
`(Parsing)`-category selectors.

Of the twelve, **ten match the reference instruction for instruction once the
name is set aside**: `socketIsValid` (both copies), `checkForCirrusChip`,
`setStatusChangeInterrupt`, `FindEmptyMemoryRange`, `MapAttributeMemory`,
`setIoWindow`, `readAttributeMemory:forSocket:`, `readRegister:socket:`,
`writeRegister:socket:value:`. Two do not, for reasons unrelated to naming:
`setWindow` is a stub (Finding 2) and `spoofInterrupt` does something else
entirely (Finding 6). So the naming divergence is itself cosmetic, but — as in
`drvPCMCIABus` — it is not evidence that the bodies underneath are equivalent.

**Disposition:** fix. Rename all twelve to match Apple's spelling. Note that for
`socketIsValid` the rename is *not* sufficient on its own; see Finding 1.

**Outcome:** fixed, all twelve. The eight C functions lost their leading
underscore in commit `3b7f8935`, so the compiler now renders them with exactly one
(`socketIsValid` -> `_socketIsValid`, and so on down the table). The four category
selectors lost theirs in `c22d05b4`: `PCIC(Debug)` now declares
`readAttributeMemory:forSocket:` and `spoofInterrupt`, and `PCIC(Internal)`
declares `readRegister:socket:` and `writeRegister:socket:value:`, matching the
`__meth_var_names` entries at 19903, 19888, 19962 and 19934. Both commits changed
declarations and call sites together. The rename is source-level only; that the
emitted symbol table now matches has not been measured, because no build was run.

## File placement

`_setMemoryWindow` (address 6620) and `_setIoWindow` (address 7084) sit inside
`PCICWindow.m`'s address run and increment `PCICWindow.m`'s `io_inline.h` static
at 8248. Our tree defines both at the bottom of `PCIC.m`
(`PCIC.m:496` and `PCIC.m:452`) and reaches them from `PCICWindow.m` through
`extern` declarations at `PCICWindow.m:38-39`.

Apple's source has them as file-local statics in `PCICWindow.m`, immediately
after `-[PCICWindow set16Bit:]` and before the `(Attributes)` category's object
file. Both reference symbols are `n_type=0x0e`, i.e. `static`.

**Disposition:** fix — approved in the spec, applied in Task 9 Step 4. Moving
them also resolves half of Finding 9, because a `static` in `PCICWindow.m` needs
no `extern` declaration and no external linkage.

**Outcome:** fixed in commit `cc01a6a4`. Both functions were cut from the bottom of
`PCIC.m` and pasted into `PCICWindow.m` after `-[PCICWindow set16Bit:]`, where the
reference has them, and both were made `static`. They now sit at
`PCICWindow.m:364` (`setMemoryWindow`) and `PCICWindow.m:430` (`setIoWindow`). The
two `extern` declarations at the top of `PCICWindow.m` went away with the move, as
predicted. Ledger addresses 6620 and 7084 -> `control-flow-confirmed`, and both
source-map entries were repointed from `PCIC.m` to `PCICWindow.m`.

## Fidelity principle

Stated once here because two findings below apply it in what would otherwise
read as opposite directions: **reproduce Apple's form, not Apple's defects.**
Where the reference is demonstrably buggy, keep our correct behaviour and record
the divergence as an intentional mismatch, with its evidence, rather than
reintroducing the bug. Match Apple exactly on everything non-behavioural —
symbol names, string literals, file placement, comments, including cosmetic
typos.

Finding 14 (`-[PCICWindow enabled]`) keeps our correct `and` rather than Apple's
`or`, because the reference is buggy there. Finding 18's comment-typo item
restores Apple's grammatical slip, because a comment is non-behavioural. Both
dispositions follow from this one rule.

## Finding 1: `PCICSocket.m` references `socketIsValid` through an `extern` that does not link

**Source:** `src/drivers-i386/bus/Intel82365PCMCIA/PCIC.drvproj/PCIC.lksproj/PCIC.m:43`,
`:359`; `.../PCICSocket.m:40`, `:62`

**Reference behaviour**

Two separate `static` definitions, one per translation unit, as § Step 4 shows.
`PCICSocket.m`'s copy at 2816 is called by `-[PCICSocket
initWithAdapter:socketNumber:]`; `PCIC.m`'s copy at 1488 is called by `-[PCIC
initFromDeviceDescription:]`. Neither file has an `extern` declaration, because
neither needs one.

**Our source**

`PCIC.m:43` declares and `PCIC.m:359` defines

```c
static char _socketIsValid(unsigned int socket);
```

while `PCICSocket.m:40` declares

```c
/* External reference to _socketIsValid function from PCIC.m */
extern char _socketIsValid(unsigned int socket);
```

and `PCICSocket.m:62` calls it.

**Difference:** a `static` function in `PCIC.m` has internal linkage and cannot
satisfy an external reference from `PCICSocket.m`. The reference is left
unresolved. This is not a theoretical objection — it is visible in the staged
artifact's symbol table, which contains *both*

```
    1396 n_type=0x0e sect= 1 desc=    0 __socketIsValid        <- the static definition
       0 n_type=0x01 sect= 0 desc=    0 __socketIsValid        <- N_UNDF|N_EXT, unresolved
```

`ld -r` does not diagnose undefined symbols, so the build reports success and the
staged `README.txt` records `make exit status was: 0`. The failure surfaces later,
when the kernel loader tries to resolve `__socketIsValid` against the kernel's
symbol table and does not find it. Enumerating every undefined symbol in the
staged artifact, `__socketIsValid` is the **only** one beyond the expected
kernel and runtime externals (`_IOLog`, `_IODelay`, `_IOVmTaskSelf`,
`_IOPhysicalFromVirtual`, `_objc_msgSend`, `_objc_msgSendSuper` and four
`.objc_class_name_*` references). The reference has no undefined
`_socketIsValid`.

**Disposition:** fix

**Rationale:** this is the single most severe item in the report. Every other
finding concerns behaviour once the driver is running; this one prevents it from
loading. It is also the reason the "builds clean" signal from the staged
artifact must not be read as "works": `ld -r` will happily emit an object with
dangling externals.

Two ways to fix it, and they are not equivalent for fidelity:

- **Match Apple:** delete the `extern` from `PCICSocket.m` and add a second
  `static` definition there. Reproduces the reference exactly, including the two
  distinct `_xxx.86` statics, at the cost of a duplicated ten-line function.
- **Minimal:** drop `static` from `PCIC.m`'s definition. Links, but leaves one
  copy where the reference has two, and gives the symbol external linkage the
  reference does not.

This report recommends the first, because reproducing Apple's source layout is
the point of the exercise and the duplication is Apple's own. Task 9 should
record which it chose.

**Outcome:** fixed in commit `3b7f8935`, and **the first option was chosen** — the
one that matches Apple. The `extern` declaration and its comment were deleted from
`PCICSocket.m` and a second file-local `static char socketIsValid(unsigned int)`
was defined there at `PCICSocket.m:44`, ahead of `@implementation PCICSocket`,
mirroring the reference's two independent definitions. `PCIC.m` keeps its own at
`PCIC.m:360`. Both lost the leading underscore in the same commit (§ Naming
divergence). The undefined `__socketIsValid` this finding is about therefore has no
source left to come from, though that has not been re-measured: no build was run,
so the claim rests on the C language rules rather than on a fresh symbol table.
Ledger addresses 1488 and 2816 -> `control-flow-confirmed`, and the source map now
maps them to `PCIC.m:360` and `PCICSocket.m:44` respectively instead of both to
`PCIC.m`.

## Finding 2: `_setWindow` is an empty placeholder; the reference is 436 bytes of register programming

**Source:** `.../PCICDebug.m:136-144`

**Our source**

```c
static IOReturn _setWindow(int socket, int window, unsigned int baseAddr,
                           unsigned int size, unsigned int physicalAddr,
                           unsigned int offset, unsigned int flags,
                           int windowType, int enable)
{
    /* Placeholder implementation */
    /* This would configure PCIC window registers for the specified parameters */
    return IO_R_SUCCESS;
}
```

**Reference behaviour** (address 1872, 436 bytes). Nine arguments; naming them
from how `_MapAttributeMemory` calls it and from what each is used for:

```
setWindow(socket, window, cardAddress, size, systemAddress,
          is16Bit, extraWaitState, attributeMemory, writeProtect)
```

```
1899  edx = cardAddress + 0x400000 - systemAddress      ; cardOffset
1916  ecx = systemAddress >> 12
1921  var_14 = window << 3                              ; window * 8
1930  esi    = socket << 6                              ; socket * 64
                                                        ; base = esi + var_14 + 0x10
1936  reg[base+0]  <- (systemAddress >> 12) & 0xFF      ; system start, low
1984  reg[base+1]  <- ((systemAddress >> 20) & 0x0F) | (is16Bit << 7)
2049  stop = systemAddress + size - 1
2067  reg[base+2]  <- (stop >> 12) & 0xFF               ; system stop, low
2109  reg[base+3]  <- ((stop >> 20) & 0x0F) | (extraWaitState << 6)
2174  reg[base+4]  <- (cardOffset >> 12) & 0xFF         ; card offset, low
2226  reg[base+5]  <- ((cardOffset >> 20) & 0x3F)
                      | ((attributeMemory & 1) << 6)
2251                 & 0x7Fh                            ; and bl, 7Fh, clears bit 7
                      | (writeProtect << 7)
```

(Abridged for readability — implement from the disassembly in the analyses,
not from this listing.)

**Difference:** all of it. Our stub touches no hardware. `_MapAttributeMemory`
calls it as `setWindow(socket, 0, 0, 0x2000, physicalAddress, 0, 0, 1, 0)` — the
one live call site, mapping 8 KB of attribute memory with the attribute-memory
bit set — so `-[PCIC(Debug) readAttributeMemory:forSocket:]` currently sets up
nothing and then reads whatever happens to be at the physical page it found.
Everything else in `_MapAttributeMemory` and `readAttributeMemory:forSocket:` is
correct (see § Functions examined with no divergence found for the surrounding
context); this one function is the hole.

Note also that our parameter names are wrong even where positions are right:
`baseAddr` is the card address, `physicalAddr` is the system address, `offset` is
the 16-bit data-path flag, `flags` is the extra-wait-state flag, `windowType` is
the attribute-memory flag and `enable` is the write-protect flag.

**Disposition:** fix

**Rationale:** the reference disassembly is completely legible — six register
writes, every shift and mask visible — so this is directly implementable. Leaving
it stubbed means the driver's attribute-memory path silently does nothing, which
is worse than an error.

**Outcome:** fixed in commit `6604e364`. The placeholder body was replaced with the
six register writes the reference performs, in the reference's order and with its
arithmetic: `cardOffset = cardAddress + 0x400000 - systemAddress`, window base
`(socket << 6) + (window << 3) + 0x10`, then the system start low byte, the system
start high nibble ORed with `is16Bit << 7`, the stop page from `systemAddress +
size - 1`, its high nibble ORed with `extraWaitState << 6`, the card offset low
byte, and the card offset high six bits ORed with the attribute-memory bit and the
write-protect bit. The nine parameters were also renamed from the invented
`baseAddr`/`physicalAddr`/`offset`/`flags`/`windowType`/`enable` to what each one
actually is, so the one live call from `MapAttributeMemory` now reads correctly.
Ledger address 1872 -> `control-flow-confirmed`; it is not `assembly-matched`
because the 436 bytes have not been rebuilt and compared.

## Finding 3: the `PCIC_PCI` class is absent

**Source:** absent from `src/drivers-i386/bus/Intel82365PCMCIA/PCIC.drvproj/PCIC.lksproj/`

`PCI.table` already names `"Driver Name" = "PCIC_PCI";` with
`"Auto Detect IDs" = "0x11001013"` (Cirrus Logic PD6832 PCI-to-PCMCIA bridge), so
our config table advertises a class our code does not define. See § PCIC_PCI:
go/no-go for the full reference reconstruction and the verdict.

**Disposition:** fix

**Outcome:** fixed in commit `3e7f1b25`. `@implementation PCIC_PCI` was written into
`PCIC.m` at line 49, **ahead of** `@implementation PCIC`, which is where
`__OBJC,__module_info` and the address-0 `IMP` put it, and `@interface PCIC_PCI :
PCIC` was added to `PCIC.h`. The body follows the reconstruction in § PCIC_PCI:
go/no-go exactly: the `getPCIdevice:function:bus:` probe with a null `function:`,
the `PCIC: PCMCIA->PCI Bus Bridge Detected (Dev=%d, Bus=%d)\n` log, the class-side
`getPCIConfigData:atRegister:withDeviceDescription:` on `IODirectDevice` reading
BAR0 into `reg_base`, the `& 0xFFFC` mask, the four-byte `IORange` handed to
`setPortRangeList:num:`, and both failure paths sending `free` to `super`. The
class declares no ivars of its own, so its instance size follows `PCIC`'s 312.
Ledger address 0 -> `control-flow-confirmed`, and the source map moved it out of
`unmapped` into `mapped` at `PCIC.m:56`. One of the report's two `missing_strings`
now exists in our source; that it lands in `__cstring` byte for byte has not been
measured, because no build was run.

## Finding 4: all three classes have the wrong instance-variable layout

**Source:** `.../PCIC.h:52-60`, `.../PCICSocket.h:38-49`, `.../PCICWindow.h:35-47`

Read from `__OBJC,__instance_vars` and `__OBJC,__class` in both binaries.

**`PCIC`** — reference `instance_size` 312, ours 324:

| Offset | Reference | Ours |
| --- | --- | --- |
| 296 | `CirrusCompatible` (`c`) | `basePort` (`I`) |
| 300 | `sockets` (`@"List"`) | `numSockets` (`I`) |
| 304 | `windows` (`@"List"`) | `irqLevel` (`I`) |
| 308 | `statusHandler` (`@`) | `isCirrusChip` (`c`) |
| 312 | — | `socketList` (`@`) |
| 316 | — | `windowList` (`@`) |
| 320 | — | `statusChangeHandler` (`@`) |

Three ivars our reconstruction invented — `basePort`, `numSockets`, `irqLevel` —
displace all four real ones by 12 bytes. The comments in `PCIC.m:258`, `:267` and
`:277` already state the correct offsets (0x12C, 0x130, 0x134); the declaration
order in `PCIC.h` contradicts them. The reference does not need any of the three:
it keeps the port base only in the global `reg_base`, never stores a socket
count, and re-reads `[deviceDescription interrupt]` at each use.

**`PCICSocket`** — reference `instance_size` 20, ours 44:

| Offset | Reference | Ours |
| --- | --- | --- |
| 4 | `adapter` (`@`) | `adapter` (`@`) |
| 8 | `socketNumber` (`i`) | `socketNumber` (`I`) |
| 12 | `statusMask` (bitfield struct) | `windowList` (`@`) |
| 16 | `windows` (`@"List"`) | `cardEnabled` (`I`) |
| 20–40 | — | `cardVccPower`, `cardVppPower`, `cardIRQ`, `cardAutoPower`, `memoryInterface`, `statusChangeMask` |

Our `PCICSocket` has no `statusMask` ivar at all: our `windowList` sits at +12,
where the reference has `statusMask`, and our separate `statusChangeMask` sits at
+40. Six further ivars exist that shadow accessor names but are never read or
written by any method — every `PCICSocket` accessor in both binaries goes to the
hardware, not to an ivar. The reference's `statusMask` type is worth quoting in full because it names the status
bits:

```
{?="present"b1"locked"b1"ejectRequest"b1"insertRequest"b1"batteryStatus"b2"writeProtect"b1"ready"b1}
```

That is bit 0 `present`, bit 1 `locked`, bit 2 `ejectRequest`, bit 3
`insertRequest`, bits 4–5 `batteryStatus`, bit 6 `writeProtect`, bit 7 `ready` —
and it confirms that our `-[PCICSocket status]` bit reformatting (Finding 11's
list of matching bodies) is correct even though our comments label bit 6 wrongly.

**`PCICWindow`** — reference `instance_size` 36, ours 48:

| Offset | Reference | Ours |
| --- | --- | --- |
| 4 | `socket` (`@`) | `socket` (`@`) |
| 8 | `validSockets` (`@"List"`) | `validSocketsList` (`@`) |
| 12 | `socketNumber` (`i`) | `socketNumber` (`I`) |
| 16 | `windowNumber` (`i`) | `windowNumber` (`I`) |
| 20 | `memoryWindow` (`c`) | `memoryWindow` (`C`) |
| 24 | `systemAddress` (`I`) | `systemAddress` (`I`) |
| 28 | `cardAddress` (`I`) | `cardAddress` (`I`) |
| 32 | `mapSize` (`I`) | `mapSize` (`I`) |
| 36–44 | — | `enabled`, `attrMemFlag`, `is16Bit` |

The offsets are right here; the divergences are the ivar's name
(`validSocketsList` versus `validSockets`), `memoryWindow` being `unsigned char`
where the reference is `char`, the two `int` ivars being `unsigned`, and three
unused trailing ivars.

**Disposition:** fix

**Rationale:** instance-variable layout is ABI. `PCIC` in particular is a
subclass of `IODirectDevice` and a superclass of `PCIC_PCI` (Finding 3), so
getting the size wrong propagates. The invented ivars are also the visible
symptom of Finding 5 — they exist to hold values Apple's driver never keeps.

**Outcome:** fixed in commit `2a99753a`, all three layouts rewritten to the
reference's exact names, types and order, giving instance sizes 312, 20 and 36:

- **`PCIC`** now declares exactly `CirrusCompatible`, `sockets`, `windows`,
  `statusHandler` at +296/+300/+304/+308. `basePort`, `numSockets` and `irqLevel`
  were deleted; `basePort` in particular had no replacement, so every read of it
  was repointed at the global `reg_base`, including the one in
  `-[PCIC interruptOccurred]`. The declaration order now agrees with the
  `0x12C`/`0x130`/`0x134` comments that previously contradicted it.
- **`PCICSocket`** now declares `adapter`, `socketNumber` (`int`, not `unsigned`),
  the `PCMCIAStatus` bitfield `statusMask` at +12, and `windows` at +16. The six
  never-read shadow ivars (`cardEnabled`, `cardVccPower`, `cardVppPower`,
  `cardIRQ`, `cardAutoPower`, `memoryInterface`) and the separate
  `statusChangeMask` were deleted. `PCMCIAStatus` is declared in `PCICSocket.h`
  with the reference's eight fields in the reference's order and widths.
- **`PCICWindow`** renamed `validSocketsList` to `validSockets`, made
  `socketNumber` and `windowNumber` `int`, made `memoryWindow` `char`, and dropped
  the three unused trailing ivars `enabled`, `attrMemFlag`, `is16Bit`.

This finding touched every method that reads or writes an ivar, which is why the
four functions § Summary lists as having no write-up of their own — `-[PCIC
sockets]` (932), `-[PCIC windows]` (948), `-[PCIC setStatusChangeHandler:]` (964)
and `-[PCICSocket windows]` (3820) — advance on this outcome alone, to
`control-flow-confirmed`. The sizes 312/20/36 are what the source now describes;
they have not been read back out of a rebuilt `__OBJC,__class`, because no build
was run.

## Finding 5: `-[PCIC initFromDeviceDescription:]` was reconstructed from the wrong premises

**Source:** `.../PCIC.m:79-194`

**Reference behaviour** (address 292, 639 bytes). Reconstructed in full:

```objc
- initFromDeviceDescription:deviceDescription
{
    int i;
    id socket;

    reg_base = *(unsigned int *)[deviceDescription portRangeList];   /* 304-322 */
    if (!socketIsValid(0)) {                                          /* 327-339 */
        IOLog("PCIC: No device at base address 0x%04x\n", reg_base);  /* 341-353 */
        return [self free];                                           /* 358-371 */
    }
    if (![super initFromDeviceDescription:deviceDescription])         /* 376-413 */
        return [super free];                                          /* 415-440 */

    [self setName:"PCIC"];                                            /* 448-461 */
    [self setDeviceKind:"PCMCIA Adapter"];                            /* 466-479 */
    [self setUnit:0];                                                 /* 484-494 */

    sockets = [[List alloc] init];                                    /* 502-537 */
    windows = [[List alloc] init];                                    /* 543-578 */

    for (i = 0; i <= 3; i++) {                                        /* 584-698 */
        socket = [[PCICSocket alloc] initWithAdapter:self socketNumber:i];
        if (!socket) break;
        [sockets addObject:socket];
        [windows appendList:[socket windows]];
    }
    if ([sockets count] == 0) {                                       /* 700-745 */
        [sockets free];
        [self free];
        return nil;
    }
    CirrusCompatible = checkForCirrusChip();                          /* 752-757 */
    for (i = 0; i < [sockets count]; i++)                             /* 763-821 */
        setStatusChangeInterrupt(i, [deviceDescription interrupt]);
    if ([self enableAllInterrupts])                                   /* 824-854 */
        IOLog("PCIC: couldn't enable interrupts\n");                  /* falls through */
    if ([self startIOThread]) {                                       /* 857-875 */
        IOLog("PCIC: couldn't start IO thread\n");                    /* 896-901 */
        [self free];
        return nil;
    }
    [self registerDevice];                                            /* 877-885 */
    return self;                                                      /* 890 */
}
```

**Differences,** in the order they occur:

1. **How the port base is obtained.** The reference sends `portRangeList` to the
   device description and dereferences the first `IORange`'s `start` field
   (`315 call objc_msgSend; 320 mov eax,[eax]; 322 mov ds:_reg_base, eax`). Ours
   sends `resourcesForKey:"I/O Ports"` — hence the `I/O Ports` string in our
   `__cstring` that the reference does not have — and checks the result for NULL,
   logging `PCIC: No I/O port range specified\n`. The reference has no such check
   and no such string.
2. **`basePort` is not an ivar in the reference.** Ours stores `basePort =
   range->start` and then `reg_base = basePort`; the reference writes `reg_base`
   directly. See Finding 4.
3. **The hardware-failure message.** Reference: `PCIC: No device at base address
   0x%04x\n` with `reg_base` as the argument. Ours: `PCIC: Hardware validation
   failed at port 0x%x\n` with `basePort`. Both `%04x` and the wording differ,
   and the reference's string is one of the two in `missing_strings` above.
4. **The failure return.** The reference falls out of `[self free]` straight into
   the epilogue, so it returns `free`'s value; ours writes `return nil;`
   explicitly. Both produce `nil`, so this part is behaviourally identical and is
   not itself actionable — recorded for completeness. On the super-init failure
   path both sides send `[super free]`, which matches exactly.
5. **No IRQ ivar and no default of 5.** Ours reads `irqLevel = [deviceDescription
   interrupt]` once, substitutes 5 if it is zero, and passes the cached value to
   `setStatusChangeInterrupt`. The reference sends `interrupt` to the device
   description **inside** the loop on every iteration and has no default.
6. **No list-allocation failure messages.** Ours logs `PCIC: Failed to create
   socket list\n` and `PCIC: Failed to create window list\n` and frees on either;
   the reference does not test either allocation.
7. **No nil check before `appendList:`.** Ours guards `[socket windows]` with
   `if (socketWindows)`; the reference appends unconditionally.
8. **The no-sockets path.** The reference does `[sockets free]` — freeing the
   *list*, not self — then falls into the shared `[self free]; return nil;` tail.
   Ours logs `PCIC: Failed to create any sockets\n` (a string the reference does
   not have) and frees only self.
9. **`numSockets` is not an ivar in the reference.** Ours stores
   `numSockets = [socketList count]`. See Finding 4.
10. **`enableAllInterrupts` failure is not fatal in the reference.** At 842 the
    reference tests the result and jumps *past* the `IOLog` to `startIOThread`
    on success; on failure it logs and **falls through** to `startIOThread`
    anyway. Ours frees and returns `nil`. This is a real behaviour difference:
    Apple's driver still starts its I/O thread and registers itself on a machine
    where interrupt enabling failed.
11. **The final banner does not exist.** Ours ends with `IOLog("PCIC:
    Initialized at port 0x%x, IRQ %d, %d sockets%s\n", ...)` using the ` (Cirrus)`
    suffix string. Neither string is in the reference; Apple's driver prints
    nothing on success.

Everything else matches and is worth stating positively: the order
`setName:` / `setDeviceKind:` / `setUnit:` and their exact arguments `"PCIC"`,
`"PCMCIA Adapter"`, `0`; both `[[List alloc] init]` pairs; the four-socket loop
with a `break` on nil; `addObject:` then `appendList:[socket windows]`; the
`count == 0` test; `checkForCirrusChip()` stored as a byte; the
`setStatusChangeInterrupt(i, irq)` argument order; `startIOThread` before
`registerDevice`; `return self`.

**Disposition:** fix

**Rationale:** this is the method the whole driver hangs off. Points 1, 5 and 10
are behaviour differences on real hardware, not cosmetics, and points 2, 9 and
the `isCirrusChip` naming are what force the `PCIC` ivar layout in Finding 4.

**Outcome:** fixed in commit `314591cd`; the method was rewritten against the
reconstruction above and all eleven numbered differences are gone. Point by point:
the port base now comes from `[deviceDescription portRangeList]` and the first
`IORange`'s `start` is assigned straight into the global `reg_base`, with no
`resourcesForKey:"I/O Ports"` and no NULL check (1, 2); the failure message is
`PCIC: No device at base address 0x%04x\n` with `reg_base` (3), which is the second
of the report's two `missing_strings`; the failure return is `return [self free];`
rather than an explicit `nil` (4); `[deviceDescription interrupt]` is re-sent
inside the loop with no cached `irqLevel` and no default of 5 (5); the two
`[[List alloc] init]` results are stored without being tested (6); `appendList:`
is sent unguarded (7); the no-sockets path does `[sockets free]; [self free];
return nil;` (8); `numSockets` is gone (9); `enableAllInterrupts` failure logs and
**falls through to `startIOThread`** instead of being fatal (10); and the invented
success banner and its ` (Cirrus)` suffix were deleted (11). With them went all
six invented log strings and both remaining `extra_strings` that belonged to this
method. Ledger address 292 -> `control-flow-confirmed`. Whether the rewritten body
comes out near the reference's 639 bytes is unmeasured: no build was run.

## Finding 6: `spoofInterrupt` is a software interrupt, not a message send

**Source:** `.../PCICDebug.m:200-204`

**Reference behaviour**

```
2688 55     push ebp
2689 89E5   mov ebp, esp
2691 CD45   int 45h
2693 89EC   mov esp, ebp
2695 5D     pop ebp
2696 C3     retn
```

**Our source**

```objc
- (void)_spoofInterrupt
{
    [self interruptOccurred];
}
```

**Difference:** the reference raises interrupt vector 0x45 with an `int`
instruction. On i386 Mach the hardware IRQ vectors start at 0x40, so 0x45 is
IRQ 5 — the IRQ this driver's `PCI.table` and `Default.table` both request
(`"IRQ Levels" = "5"`). The reference therefore exercises the *whole* interrupt
delivery path: IDT entry, kernel dispatch, DriverKit interrupt message, I/O
thread, and only then `interruptOccurred`. Ours short-circuits all of that and
calls the handler directly on the caller's thread.

The size difference is the whole body: 9 bytes against the 19 or so a message
send needs.

**Disposition:** fix

**Rationale:** the two are not interchangeable for the purpose the method exists
for. A debug hook that skips the interrupt plumbing cannot test the interrupt
plumbing. It is also a two-line change: `asm volatile("int $0x45");` reproduces
the reference exactly.

Note the type encodings already agree (`v8@8:12` on both sides), so only the
body and the selector's leading underscore need to change.

**Outcome:** fixed in commit `2fa7466b`. The body is now a single
`asm volatile("int $0x45");`, which is the reference's `CD 45` and nothing else,
and the whole interrupt delivery path is exercised again. The selector lost its
underscore in `c22d05b4` (§ Naming divergence). Ledger address 2688 ->
`control-flow-confirmed`.

## Finding 7: `_setMemoryWindow` omits three read-modify-write cycles and computes the card offset differently

**Source:** `.../PCIC.m:496-542`

**Reference behaviour** (address 6620, 461 bytes; argument order
`socket, window, cardAddress, size, systemAddress`):

```
6629  var_4 = cardAddress + 0x400000 - systemAddress    ; cardOffset
6645  var_8 = (systemAddress >> 12) & 0xFF
6651  var_C = window << 3
6660  var_10 = socket << 6                              ; base = var_10 + var_C + 0x10

6669  reg[base+0]  <-  var_8                                        ; plain write
6724  reg[base+1]  <-  (read & 0xF0) | ((systemAddress >> 20) & 0x0F)   ; READ-MODIFY-WRITE
6805  stop = systemAddress + size - 1
6824  reg[base+2]  <-  (stop >> 12) & 0xFF                          ; plain write
6863  reg[base+3]  <-  (read & 0xF0) | ((stop >> 20) & 0x0F)        ; READ-MODIFY-WRITE
6946  reg[base+4]  <-  (cardOffset >> 12) & 0xFF                    ; plain write
6996  reg[base+5]  <-  (read & 0xC0) | ((cardOffset >> 20) & 0x3F)  ; READ-MODIFY-WRITE
```

The three read-modify-writes are unmistakable in the disassembly: at 6755, 6894
and 7026 the function does `in al, dx` on the data port *before* writing, and
masks the value it read (`and bl, 0F0h` twice, `and bl, 0C0h` once).

**Our source**

```c
cardOffset = cardAddr >> 12;
...
outb(reg_base, socketOffset + windowOffset + 1);
outb(reg_base + 1, (unsigned char)((startAddr >> 8) & 0x0F));
...
outb(reg_base, socketOffset + windowOffset + 3);
outb(reg_base + 1, (unsigned char)((stopAddr >> 8) & 0x0F));
...
outb(reg_base, socketOffset + windowOffset + 5);
outb(reg_base + 1, (unsigned char)((cardOffset >> 8) & 0x3F));
```

**Difference:** two, both real.

- **The three high-order registers are written blind.** Register `base+1` bits
  4–7 are the memory window's timing-set select and the 16-bit data path bit;
  `base+3` bits 4–7 are the wait-state and timing-set bits; `base+5` bits 6–7 are
  the write-protect and register-select bits. Our writes zero all of them. The
  reference deliberately preserves them, which is why it pays for three extra
  port reads.
- **The card offset formula.** The reference computes `cardAddress + 0x400000 -
  systemAddress` before shifting; ours computes `cardAddress` alone. The PCIC
  card-offset register holds a *signed* offset added to the system address to
  produce the card address, so the reference's expression is the correct one
  (`0x400000` is the 4 MB wrap constant that keeps the 6-bit field positive);
  ours programs an absolute card address into an offset field. `_setWindow`
  computes the same `cardAddr + 0x400000 - sysAddr` at 1899, independently
  confirming the formula.

Everything else matches: `windowOffset = 0x10 + window * 8`, `socketOffset =
socket << 6`, the `>> 12` page shift, `stop = sysAddr + size - 1`, and the three
low-byte writes.

**Disposition:** fix

**Rationale:** both halves are silent hardware faults of exactly the kind this
pass exists to catch. Zeroing the timing bits mis-times every memory window;
programming an absolute address into an offset register maps the wrong card page.

**Outcome:** fixed in commit `cce22ccc`. Registers `base+1`, `base+3` and `base+5`
are now read-modify-writes: each does an `inb` on the data port and ORs the new
value into the bits the reference preserves — `& 0xF0` for the two high address
nibbles and `& 0xC0` for the card-offset high bits — so the timing-set, 16-bit
data path, wait-state, write-protect and register-select bits survive. The card
offset is now `(cardAddr + 0x400000 - sysAddr) >> 12`, the same expression
`setWindow` computes at 1899, instead of the absolute `cardAddr >> 12`. The
function moved to `PCICWindow.m` in the same pass (§ File placement), so ledger
address 6620 -> `control-flow-confirmed` with its source path repointed to
`PCICWindow.m:364`.

## Finding 8: the naming divergence group

See § Naming divergence for the full table and evidence. Twelve identifiers, eight
C functions and four category selectors, all confirmed present-under-a-different-name
in the staged artifact's symbol table.

**Disposition:** fix

**Rationale:** cosmetic in isolation, but the whole point of this effort is that
the symbol table should match, and for `socketIsValid` the rename is entangled
with Finding 1's linkage failure.

**Outcome:** fixed; see the `**Outcome:**` line under § Naming divergence for the
detail. Eight C functions renamed in commit `3b7f8935`, four category selectors in
`c22d05b4`, all twelve declarations and call sites together. The
`socketIsValid` half is completed by Finding 1's second `static` definition in
`PCICSocket.m`, without which the rename alone would still have left an
unresolved external. Ledger addresses 1488, 1564, 1684, 1760, 1872, 2308, 2540,
2688, 2700, 2748, 2816, 6620 and 7084 all -> `control-flow-confirmed` (several of
them on other findings' outcomes as well).

## Finding 9: three linkage divergences

**Source:** `.../PCICDebug.m:87`, `.../PCIC.m:452`, `.../PCIC.m:496`

Read from raw `nlist` in both binaries — deliberately not from the IDA analysis,
whose `binding` field reports IDA's own name flags rather than the Mach-O `N_EXT`
bit and produced a false `global` on Intel824X0PCI.

| Symbol | Reference `n_type` | Reference linkage | Our linkage |
| --- | --- | --- | --- |
| `_MapAttributeMemory` | `0x0f` | **non-static** (`N_EXT` set) | `static` (`PCICDebug.m:87`) |
| `_setMemoryWindow` | `0x0e` | **static** | non-static (`PCIC.m:496`) |
| `_setIoWindow` | `0x0e` | **static** | non-static (`PCIC.m:452`) |

Every other function symbol in the reference's `__text` is `0x0e`.
`_MapAttributeMemory` is the single exception, and it is exported despite having
exactly one caller inside the same file — presumably a debugging convenience, the
same instinct that put the whole file behind a `(Debug)` category. Our stabs
confirm the mirror image on our side: the staged artifact carries
`_setIoWindow:F19` and `_setMemoryWindow:F19` with a capital `F` (global
function) where it carries `_setWindow:f1` and `_socketIsValid:f2` with a
lowercase `f` (static).

A fourth, smaller signature divergence belongs with these because it concerns the
same function. Our `_MapAttributeMemory` is declared

```c
static unsigned long long _MapAttributeMemory(int socket)
```

and ends `return ((regValue & 0xE0) | 1);`. The reference returns nothing usable —
it falls out of its last `mov al, [ebp+var_C]` into the epilogue with the upper 24
bits of `eax` and all of `edx` undefined, and its one caller discards the result.
The 64-bit return type is a decompiler artifact that was carried into the
reconstruction; it costs an extra register-pair setup at every return. The
function should be `void`, or at most `unsigned char`.

**Disposition:** fix

**Rationale:** trivially restorable and it costs nothing. The
`_setMemoryWindow`/`_setIoWindow` half falls out of the file move in § File
placement — once they live in `PCICWindow.m` next to their only caller they can
and should be `static`, which also lets the two `extern` declarations at
`PCICWindow.m:38-39` go away.

**Outcome:** fixed, in three commits. `MapAttributeMemory` lost its `static` in
`3b7f8935`, matching the reference's lone `n_type=0x0f` export, and its bogus
`unsigned long long` return became `void` in `1b37b611`, which also deleted the
`return ((regValue & 0xE0) | 1);` — the function now ends on the `outb` that writes
that value, as the reference does, and its one caller never wanted a result.
`setMemoryWindow` and `setIoWindow` became `static` when they moved into
`PCICWindow.m` in `cc01a6a4`, and the two `extern` declarations went away with
them exactly as predicted. Ledger addresses 2308, 6620 and 7084 ->
`control-flow-confirmed`. The `n_type` values that would confirm this are
unmeasured; no build was run.

## Finding 10: `_setMemoryWindow` and `_setIoWindow` are defined in the wrong file

See § File placement. Both belong in `PCICWindow.m`; our tree has them at the
bottom of `PCIC.m`.

**Disposition:** fix — approved in the spec, applied in Task 9 Step 4.

**Outcome:** fixed in commit `cc01a6a4`; see the `**Outcome:**` line under § File
placement. Both now sit in `PCICWindow.m` after `-[PCICWindow set16Bit:]` and both
are `static`. Ledger addresses 6620 and 7084 -> `control-flow-confirmed`, source
paths repointed from `PCIC.m` to `PCICWindow.m`.

## Finding 11: 42 of the 73 Objective-C methods have divergent type encodings

**Source:** `.../PCICSocket.h`, `.../PCICWindow.h`, `.../PCIC.h`,
`.../PCICWindowAttributes.m`, `.../PCICDebug.m`

Measured objectively by decoding `__OBJC,__meth_var_types` in both binaries and
comparing per selector, out of 73: **28 agree, 42 differ, 1 is absent from our
build** (`-[PCIC_PCI initFromDeviceDescription:]`, previously miscounted here as
a type divergence — see Finding 3), **and 2 are build-generated methods skipped**
(`+[PCICKernelServerInstance kernelServerInstance]`,
`+[PCICVersion driverKitVersionForPCIC]`; see § Unmapped: build-generated). The
complete list of differences, grouped:

**(a) Setters that return `BOOL` in the reference and `void` in ours (13).** Each
of these ends `mov eax, 1` in the reference — an instruction our source has no
way to emit:

`-[PCICSocket setStatusChangeMask:]` (3980), `setCardEnabled:` (4236),
`setCardAutoPower:` (4420), `setCardVccPower:` (4608), `setCardVppPower:` (4784),
`setCardIRQ:` (4956), `setMemoryInterface:` (5132);
`-[PCICWindow setSocket:]` (5512, returns 1 or 0),
`setMapWithSize:systemAddress:cardAddress:` (5592), `setAttributeMemory:` (5740),
`setEnabled:` (5988), `setMemoryInterface:` (6168, returns 1 or 0),
`set16Bit:` (6324).

**(b) Getters that return `char` in the reference and `unsigned int` in ours (13).**

`-[PCICSocket cardEnabled]` (4180), `cardAutoPower` (4368), `memoryInterface`
(5080); `-[PCICWindow attributeMemory]` (5676), `enabled` (5904),
`memoryInterface` (6152), `is16Bit` (6200);
`-[PCICWindow(Attributes) canUse8Bit]` (7316), `canUse16Bit` (7328),
`mustBePowerOfTwo` (7340), `writeProtectable` (7352), `supportsIO` (7484),
`supportsMemory` (7508).

Three of these change the emitted code as well as the metadata: at 4180, 6152 and
7508 the reference ends with a sign-extending `movsx eax, al` that a
`unsigned int` return would not produce.

**(c) Getters that return `int` in the reference and `unsigned int` in ours (9).**

`-[PCICSocket socketNumber]` (3804);
`-[PCICWindow(Attributes) minimumSize]` (7388), `maximumSize` (7400),
`sizeAlignment` (7412), `baseAlignment` (7424), `offsetAlignment` (7436),
`slowestSpeed` (7448), `fastestSpeed` (7460), `addressLinesDecoded` (7472).

**(d) Arguments declared `unsigned int` where the reference takes `char` (9).**

`setCardEnabled:` (4236), `setCardAutoPower:` (4420),
`-[PCICSocket setMemoryInterface:]` (5132), `setCardReset:` (5288),
`setAttributeMemory:` (5740), `setEnabled:` (5988),
`-[PCICWindow setMemoryInterface:]` (6168), `set16Bit:` (6324) — and
`-[PCICWindow initWithSocket:memoryWindow:number:]` (5368), whose `memoryWindow`
argument the reference declares `char`. At 5288 this changes the emitted compare
from a byte compare (`80 7D 10 01`) to a dword compare.

**(e) Arguments declared `unsigned int` where the reference takes `int` (2).**

`-[PCIC(Debug) readAttributeMemory:forSocket:]` (2540, both arguments),
`-[PCICSocket initWithAdapter:socketNumber:]` (2892, the socket number).

**(f) The status bitfield struct (3).** `-[PCICSocket status]` (3836) and
`statusChangeMask` (4164) return, and `setStatusChangeMask:` (3980) takes, the
eight-bit struct quoted in Finding 4; ours use `unsigned int`.

**(g) `-[PCICSocket powerStates]` (5276) returns `id` in the reference** (`@8@8:12`)
and `unsigned int` in ours. Both bodies are `xor eax, eax`, so this is metadata
only; it reads as Apple declaring it to return an object (presumably a list of
supported power states) and stubbing it out with `nil`.

**Disposition:** fix

**Rationale:** the type string is emitted into `__OBJC,__meth_var_types` and is
part of the binary, so none of these is invisible. More importantly the driver
declares conformance to DriverKit's PCMCIA protocols (Finding 13), and a protocol
method whose signature does not match the protocol's is a real interface defect —
a caller that goes through the protocol will read the wrong-width return value.
Sixteen of the 43 also change the emitted instructions (the thirteen missing
`return YES`s, plus the three `movsx` sites, plus the byte compare at 5288).

**Outcome:** fixed in commit `091c8f3a`, all 42. Group by group: the thirteen
setters in (a) now return `char` and end `return YES;` (the two at 5512 and 6168
return the reference's 1-or-0); the thirteen getters in (b) return `char`; the
nine in (c) return `int`; the nine arguments in (d) are declared `char`, including
`-[PCICWindow initWithSocket:memoryWindow:number:]`'s `memoryWindow`; the two in
(e) take `int`; the three in (f) use the `PCMCIAStatus` bitfield struct that
Finding 4 added to `PCICSocket.h`; and `-[PCICSocket powerStates]` (g) returns
`id` with a `nil` body. Every declaration in the four headers and
`PCICWindowAttributes.m` was changed together with its implementation, so
`__meth_var_types` should now agree on all 71 hand-written methods — "should",
because the type strings have not been decoded out of a rebuilt binary. The
`assembly-matched` claim that would need is unavailable this pass. Ledger: all 42
addresses -> `control-flow-confirmed`, except 5368 and 5904, which are terminal
`intentional-mismatch` on Findings 20 and 14 respectively.

**One consequence of group (f) is an unresolved build-time risk**, discovered in
review and recorded in full under § Post-fix parity: `-[PCICSocket status]` now
returns a 4-byte struct while `drvPCMCIABus` declares the same selector as
`- (unsigned int)status` and calls it at three sites. The reference returns in
`eax` with no hidden struct pointer, which is correct under
`-freg-struct-return`; under `-fpcc-struct-return` the two would silently
disagree across the driver boundary. Whoever gets a build first must check the
emitted function for a hidden argument.

## Finding 12: `-[PCICSocket initWithAdapter:socketNumber:]` sends two extra `init` messages

**Source:** `.../PCICSocket.m:102-103`, `:107-108`

**Reference behaviour**

```
3204 push 7 / paInitcount / paAlloc / paList
3225 call objc_msgSend             ; [List alloc]
3236 call objc_msgSend             ; [<allocated> initCount:7]
3243 mov [edi+10h], ecx            ; windows = result
...
3276 call objc_msgSend             ; [PCICWindow alloc]
3287 call objc_msgSend             ; [<allocated> initWithSocket:self memoryWindow:0 number:i]
3305 call objc_msgSend             ; [windows addObject:<window>]
```

Two sends for the list, two for each window. No `init`.

**Our source**

```objc
windowList = [[List alloc] initCount:7];
windowList = [windowList init];
...
window = [[PCICWindow alloc] initWithSocket:self memoryWindow:0 number:i];
window = [window init];
```

**Difference:** one extra `init` send per object constructed — one for the window
list and one for each of the six windows, so seven per socket, and up to
twenty-eight across the four sockets `-[PCIC initFromDeviceDescription:]`
creates. Sending `-init` to an already-initialised `List` re-runs `Object`'s
designated initialiser over a live object; sending it to a `PCICWindow` invokes
the inherited `-[Object init]` after `initWithSocket:memoryWindow:number:` has
already run.

**Disposition:** fix

**Rationale:** it is dead work at best and re-initialisation at worst, and
removing it is a two-line deletion. Everything else in this 896-byte method
matches exactly, and that is worth recording positively: the socket validity
check and `[self free]; return nil` on failure; registers 2, 3, 4, 5 cleared;
register 6 set to `0x20`; register 7 cleared; one window with `memoryWindow:0`
programming registers `0x08`–`0x0B` to `0xFF, 7, 0xFF, 7`; five windows with
`memoryWindow:1` programming `0x10`–`0x13` to the same values; `return self`.

**Outcome:** fixed in commit `575ea479`. Both `[... init]` re-sends were deleted:
the window list is now built as `[[List alloc] initCount:7]` and each window as
`[[PCICWindow alloc] initWithSocket:self memoryWindow:… number:i]`, two sends
each, as the reference does. Nothing else in the method changed under this
finding; its socket-number argument became `int` under Finding 11(e), its ivar
accesses moved under Finding 4, and the `socketIsValid` it calls is now the
file-local copy Finding 1 added to the same file. Ledger address 2892 ->
`control-flow-confirmed`.

## Finding 13: protocol adoption is absent, and `PCMCIAStatusChange` is invented

**Source:** `.../PCIC.h:45-49`, `:51`; `.../PCICSocket.h:37`; `.../PCICWindow.h:34`

**Reference behaviour.** `__OBJC,__protocol` holds five protocol records, and the
class and category structures reference them:

| Class or category | Adopts |
| --- | --- |
| `PCIC` | `PCMCIAAdapter`, `IOPower` |
| `PCICSocket` | `PCMCIASocket` |
| `PCICWindow` | `PCMCIAWindow` |
| `PCICWindow(Attributes)` | `PCMCIAWindowAttributes` |

**Our source** declares none of them. It does declare a protocol the reference
does not have:

```objc
@protocol PCMCIAStatusChange
- statusChangedForSocket:socket changedStatus:(unsigned int)status;
@end
```

**Difference:** the four real protocols are absent from our binary's
`__OBJC,__protocol` section entirely, and `.objc_class_name_Protocol` — which the
reference imports because it emits protocol records — is not among our undefined
symbols. Our `PCMCIAStatusChange` is not a protocol Apple's driver declares; the
selector it wraps, `statusChangedForSocket:changedStatus:`, *is* real (it is in
the reference's `__meth_var_names` at 19787 and `-[PCIC interruptOccurred]` sends
it), but it is sent to an untyped `id` there, not through a locally declared
protocol.

The four real protocols almost certainly live in the `drvPCMCIABus` project's
headers, which is where `PCMCIAKernBus` and its friends are; adopting them will
require finding or writing those declarations.

**Disposition:** fix

**Rationale:** protocol conformance is how DriverKit's PCMCIA layer discovers what
an adapter, socket and window can do. Without it the four `PCMCIA*` protocol
records are missing from the loadable server and the bus driver has no
type-level contract to check against. It is also the reason Finding 11's
signatures matter: the signatures Apple used are the protocols' signatures.

This finding is the one most likely to expand Task 9's scope, because it depends
on headers outside this driver.

**Outcome: partially applied — this is the one incomplete item in the fix pass.**

**Done,** in commit `8e1633ea`: `PCIC` now declares `<IOPower>`, which is the
second of the two protocols the reference's class structure names for it, and the
invented `@protocol PCMCIAStatusChange` was deleted along with the typed use of
it. `-[PCIC interruptOccurred]` sends `statusChangedForSocket:changedStatus:` to
an untyped `id` again, which is what the reference does.

**Not done:** the four `PCMCIA*` protocol adoptions —
`PCMCIAAdapter` on `PCIC`, `PCMCIASocket` on `PCICSocket`, `PCMCIAWindow` on
`PCICWindow`, `PCMCIAWindowAttributes` on `PCICWindow(Attributes)`.

**Why.** Three of the four do not exist anywhere in `src/`. Searching the whole
tree, there is no declaration of `PCMCIASocket`, `PCMCIAWindow` or
`PCMCIAWindowAttributes` at all. The fourth, `PCMCIAAdapter`, does exist — at
`src/drivers-i386/bus/drvPCMCIABus/PCMCIABus.drvproj/PCMCIABus.lksproj/PCMCIAKernBus.h:66`
— but it sits inside that header's `#ifdef DRIVER_PRIVATE` block and that project
is not on this driver's include path, so adopting it here would have meant either
exporting a private header across two driver projects or copying the declaration.
Adopting the other three would have meant **inventing Apple's protocol
declarations** — guessing which selectors each protocol contains and what their
signatures are — and writing that guess into `drvPCMCIABus` as though it were
recovered. That was refused: this effort's whole value is that what it writes down
came off Apple's binary.

**The follow-up,** for whoever picks this up: the selector lists are recoverable.
The reference's `__OBJC,__protocol` section holds five protocol records, and each
one carries an instance-method description list naming every selector and its type
encoding. Decoding those five records gives the three missing protocols exactly,
with no guessing, and they should then be declared in `drvPCMCIABus` alongside
`PCMCIAAdapter` and adopted from there. Finding 11's signatures are the other half
of the same job — the signatures Apple used *are* these protocols' signatures — and
they are already applied, so the adoptions can be added without disturbing the
method declarations again.

**Ledger effect: none, in either direction.** Protocol adoption is recorded in
`__OBJC,__protocol` and in the class and category structures' protocol-list
pointers. It emits no code into `__TEXT,__text` and changes no method's type
encoding, so no ledger entry advances on it and none is blocked by it. This is
worth stating explicitly because it means the ledger reaching 76
`control-flow-confirmed` and 6 `intentional-mismatch` **does not** mean the driver
matches the reference: the four protocol records are still missing from what our
build would emit, and that gap is invisible to a per-function ledger.

## Finding 14: `-[PCICWindow enabled]` uses OR in the reference and always reports enabled (accepted)

**Source:** `.../PCICWindow.m:80-98`

**Reference behaviour**

```
5904 ...   read register (socketNumber << 6) + 6
5943 31D2  xor edx, edx
5945 8079 1400  cmp byte ptr [ecx+14h], 0     ; memoryWindow
5949 7505       jnz loc_1744
5951 BA06000000 mov edx, 6                    ; memory windows start at bit 6
5956 25FF000000 and eax, 0FFh
5961 035110     add edx, [ecx+10h]            ; + windowNumber
5964 89D1       mov ecx, edx
5966 BA01000000 mov edx, 1
5971 D3E2       shl edx, cl                   ; 1 << bit
5973 09D0       or  eax, edx                  ; <-- OR, not AND
5975 0F95C0     setnz al
5978 25FF000000 and eax, 0FFh
```

(Abridged for readability — implement from the disassembly in the analyses,
not from this listing.)

`or eax, edx` where `edx` is `1 << bit` can never be zero, so `setnz al` always
sets 1. **Apple's `-[PCICWindow enabled]` unconditionally returns YES.**

The encoding leaves no room for doubt: `09 D0` is `or eax, edx`; the AND form
would be `21 D0`.

**Our source**

```c
return ((unsigned int)regValue & (1 << ((bitOffset + (char)windowNumber) & 0x1F))) != 0;
```

**Difference:** ours performs the AND the method's name implies and returns the
window's actual enable bit. Everything else — the register number (6), the
bit-6 base for memory windows, the `+ windowNumber` — matches exactly, and the
companion `-[PCICWindow setEnabled:]` at 5988 sets and clears the same bit
correctly on both sides, which is what makes this look like a typo in Apple's
source rather than an intent.

**Disposition:** accept

**Rationale:** this is a defect in the reference, not in ours. Reproducing it
would make the accessor useless and would silently break any caller that asks
whether a window is enabled. Fidelity to a shipped binary does not extend to
copying its bugs, and nothing else in the driver reads this accessor, so keeping
our version costs no compatibility. Per § Fidelity principle: the reference is
demonstrably buggy here, so we keep our correct behaviour and record the
divergence instead of reproducing it.

Recorded rather than fixed, and flagged for Task 9 in case the reviewer takes the
opposite view: if byte-level parity is ever wanted for this function it will have
to reintroduce the OR.

**Outcome: accepted, nothing changed.** The reviewer did not take the opposite
view. `-[PCICWindow enabled]` still performs the AND and still returns the
window's actual enable bit, and the reference's `09 D0` was not reintroduced. The
only thing that changed about this method in the fix pass is its return type,
which became `char` under Finding 11(b). Ledger address 5904 ->
`intentional-mismatch`, reviewer Pat Raynor, with the reason recording that the
reference is buggy here and that per § Fidelity principle we reproduce Apple's
form but not Apple's defects. That status is terminal, so this function will not
be revisited by a later parity pass unless the decision itself is reopened.

## Finding 15: `PCICInternal.h` is dead

**Source:** `.../PCICInternal.h`

No `.m` file in the project imports it — `PCICInternal.m` imports `PCIC.h`,
`<driverkit/generalFuncs.h>` and `<machdep/i386/io_inline.h>`, and nothing else
mentions the header. It declares three functions `static`
(`_socketIsValid`, `_checkForCirrusChip`, `_setStatusChangeInterrupt`) at
`PCICInternal.h:35-37`, which no translation unit defines; had any file included
it, the compiler would warn about static declarations that are never defined.
Its two non-static declarations at `:40-41` duplicate the ones
`PCICWindow.m:38-39` makes for itself.

**Disposition:** fix

**Rationale:** the user has explicitly instructed that Task 9 delete it. It is
also actively misleading, since a `static` declaration in a header is a bug
waiting for someone to include it. **Not deleted by this pass** — this is a
report.

**Outcome:** fixed. `PCICInternal.h` was deleted in commit `cc01a6a4`, together
with its entry in `PB.project`, and its stale `HFILES` reference was removed from
the project `Makefile` in `2cdbb926`. Nothing imported it, so nothing else had to
change. No ledger entry covers a header, so no status moved for this.

## Finding 16: `PCI.table` is missing the `Version` line

**Source:** `src/drivers-i386/bus/Intel82365PCMCIA/PCIC.drvproj/PCI.table`

**Reference:** carries `"Version" = "5.00";` as the last line.

**Ours:** the line is absent. Our table is otherwise byte-identical to the
reference's first fifteen lines, including `"Auto Detect IDs" = "0x11001013"` and
`"Driver Name" = "PCIC_PCI"`.

**Disposition:** fix

**Rationale:** trivially restorable, and config-table version strings are read
back by driver-management tooling. Same finding as Intel824X0PCI's Finding 10.

The reference's other extra line,
`"Driver Version" = "PROGRAM:PCIC  PROJECT:drvIntel82365PCMCIA-13  DEVELOPER:root
BUILT:Sat Mar 28 22:08:58 PST 1998";`, is stamped in by the build and carries
Apple's build host and timestamp. **Accepted**; it should not be added by hand —
see Finding 17 for why that matters here.

**Outcome:** fixed in commit `d458ea6c`. `PCI.table` now ends `"Version" = "5.00";`
and is otherwise unchanged, so it matches the reference on all sixteen lines it
should carry. `"Driver Version"` was deliberately not added, per the paragraph
above. No ledger entry covers a config table, so no status moved for this.

## Finding 17: `Default.table` is malformed and misuses `Server Name`

**Source:** `src/drivers-i386/bus/Intel82365PCMCIA/PCIC.drvproj/Default.table`

**Reference**

```
"Title" = "PCIC";
...
"Server Name" = "PCIC";
"Driver Version" = "PROGRAM:PCIC  PROJECT:drvIntel82365PCMCIA-13  DEVELOPER:root  BUILT:Sat Mar 28 22:08:58 PST 1998";
"Version" = "5.00";
```

**Ours**

```
{
    "Title" = "PCIC";
    ...
    "Server Name" = "PROGRAM:PCIC  PROJECT:drvIntel82365PCMCIA-13  DEVELOPER:root  BUILT:Sat Mar 28 22:08:58 PST 1998";
    "Driver Version" = "PROGRAM:PCIC  PROJECT:drvIntel82365PCMCIA-13  DEVELOPER:root  BUILT:Sat Mar 28 22:08:58 PST 1998";
    "Version" = "5.00";
}
```

**Differences:** three.

1. **`"Server Name"` holds the driver-version string** instead of `"PCIC"`. This
   looks like a transcription slip when the table was copied from Apple's — the
   `"Driver Version"` value was pasted into both keys. `Server Name` is the key
   the kernel server loader uses to name the loadable server; the reference
   binary's `Loaded Server,Server Name` section holds the four bytes `PCIC`, so
   the value is load-bearing.
2. **The whole table is wrapped in braces.** The reference's is a bare sequence
   of key/value lines, matching every other `.table` in `drivers-i386`. Whether
   the parser tolerates the braces was not tested.
3. **Apple's `"Driver Version"` is hardcoded**, complete with `DEVELOPER:root`
   and Apple's March 1998 build timestamp. That value is supposed to be stamped in
   by our own build; hardcoding Apple's makes every build claim to be Apple's.

The other twelve lines match the reference exactly, including
`"I/O Ports" = "0x3E0-0x3E1"` and `"Driver Name" = "PCIC"` (note this table names
`PCIC`, not `PCIC_PCI` — the ISA-probed instance rather than the PCI-bridge one).

Confirmed present in the staged artifact's copy of the table as well, so it is
not a transcription error in this report.

**Disposition:** fix

**Rationale:** point 1 is a functional defect in the driver's own configuration.
Points 2 and 3 are cleanup that should go with it.

**Outcome:** fixed in commit `87748390`, all three points. `"Server Name"` now
holds `"PCIC"`, matching the four bytes in the reference's `Loaded Server,Server
Name` section; the enclosing braces are gone, so the file is a bare sequence of
key/value lines like every other `.table` in `drivers-i386`; and the hardcoded
`"Driver Version"` line carrying Apple's `DEVELOPER:root` and March 1998 timestamp
was deleted, leaving that value for our own build to stamp in. `"Version" =
"5.00";` stays. The other twelve lines were already correct and were not touched.
No ledger entry covers a config table, so no status moved for this.

## Finding 18: `DriverInfo` diverges in every value

**Source:** `src/drivers-i386/bus/Intel82365PCMCIA/PCIC.drvproj/DriverInfo`

**Reference**

```
#
# used by geninfo: DRIVER_NAME is the names which appears on the
# installer window
#
DRIVER_NAME="Intel 82365 PCMCIA Adapter"
DEFAULT_DRIVER_VERSION="5.00";
```

**Ours**

```
#
# used by geninfo: DRIVER_NAME is the name which appears on the
# installer window
#
DRIVER_NAME="PCIC"
DRIVER_VERSION_330="3.3";
DRIVER_VERSION_400="4.0";
DRIVER_VERSION_410="4.0";
DRIVER_VERSION_420="4.0";
DEFAULT_DRIVER_VERSION="5.01";
```

**Differences:** four.

1. `DRIVER_NAME` is `"PCIC"` where the reference has the human-readable
   `"Intel 82365 PCMCIA Adapter"`. This string is what the installer window shows,
   so ours displays a four-letter internal code to the user.
2. `DEFAULT_DRIVER_VERSION` is `"5.01"` where the reference has `"5.00"`, which
   also disagrees with the `"Version" = "5.00"` that Findings 16 and 17 concern.
3. Four `DRIVER_VERSION_*` lines exist that the reference does not have. They look
   copied from another driver's `DriverInfo`.
4. The comment reads `is the name which appears` where the reference reads
   `is the names which appears` — our version fixes Apple's grammar. Recorded
   because a byte-level comparison will flag it; whether to reintroduce the typo
   is a judgement call for Task 9. This report's view is that the comment should
   match, since the goal is fidelity and the file is otherwise verbatim. Per
   § Fidelity principle: a comment is non-behavioural, so the cosmetic typo
   should be reproduced exactly, not corrected.

**Disposition:** fix

**Rationale:** point 1 is user-visible, point 2 is a version number that
contradicts the config tables, point 3 is dead configuration.

**Outcome:** fixed in commit `87748390`, and **`DriverInfo` is now byte-identical
to the reference.** `DRIVER_NAME` is `"Intel 82365 PCMCIA Adapter"`,
`DEFAULT_DRIVER_VERSION` is `"5.00"` in agreement with both config tables, the four
dead `DRIVER_VERSION_*` lines are gone, and — per § Fidelity principle, since a
comment is non-behavioural — Apple's grammatical slip `is the names which appears`
was restored. This is the only file in the driver that a byte-level comparison
would now pass, and it is the one place in this pass where a difference was
resolved by making our file *worse* English on purpose. No ledger entry covers
`DriverInfo`, so no status moved for this.

## Finding 19: `-[PCIC interruptOccurred]` and `-[PCIC setPowerState:]` cache counts the reference re-sends each iteration (accepted)

**Source:** `.../PCIC.m:209`, `:237-239`, `:298`

**Reference behaviour.** The loop re-sends `count` to the socket list at the top
of every iteration (996–1024), and sends
`statusChangedForSocket:changedStatus:` to `[self+0x134]` unconditionally
(1165–1183).

**Our source** reads `count = [socketList count];` once before the loop and wraps
the handler send in `if (statusChangeHandler)`.

**Difference:** two code-shape differences with no behavioural consequence. The
socket list does not change during the loop; and `objc_msgSend` to `nil` is a
no-op in this runtime, so the reference's unguarded send does exactly what our
guarded one does.

Everything else in this 226-byte method matches exactly, and the bit
reformatting is worth stating because it is the driver's translation from PCIC
hardware bits to PCMCIA status bits: register `(i << 6) + 4`, then bit 2 of the
value to bit 7, bit 3 to bit 0, and `(bit 1 | bit 0)` to bit 4. Our source
reproduces all four mappings.

**`-[PCIC setPowerState:]`** (address 1264, 200 bytes) has the same shape in
both of its loops. The reference re-sends `count` at the top of each:

```
blocks: (1288,30,[1318,1452]) ... (1444,6,[1288])   ; back-edge re-sends [sockets count]
        (1376,26,[1402,1444]) ... (1402,41,[1376])  ; back-edge re-sends [windows count]
```

Our `PCIC.m` (around line 298) caches `count` and `windowCount` in locals before
each loop instead of re-sending `[socketList count]`/`[windowList count]` on
every iteration. Neither list changes during the loop, so this is the same
no-behavioural-consequence divergence as `interruptOccurred`'s.

**Disposition:** accept

**Rationale:** neither difference changes behaviour, and the ivar-offset problem
this method also has is already Finding 4's. Recorded because it is real and
confirmed, not because it needs changing. If Task 9 pursues byte-level parity it
will have to revisit both.

**Outcome: accepted, nothing changed under this finding.** Both methods still
cache their counts in locals before the loop, and `-[PCIC interruptOccurred]`
still guards the handler send with `if (statusHandler)`. What did change in both,
under Finding 4, is which ivars they touch: `interruptOccurred` no longer reads
the deleted `basePort` and takes the port base from the global `reg_base` instead,
and both now go through `sockets`, `windows` and `statusHandler` at the
reference's offsets. Ledger addresses 984 and 1264 -> `intentional-mismatch`,
reviewer Pat Raynor, each with a reason recording that the list does not change
during the loop and that `objc_msgSend` to `nil` is a no-op, so behaviour is
identical. Both statuses are terminal; a later byte-level parity pass that wants
these two functions to match instruction for instruction would have to reopen the
decision, not merely re-examine them.

## Finding 20: `-[PCICWindow initWithSocket:memoryWindow:number:]` builds its list in two statements (accepted)

**Source:** `.../PCICWindow.m:61-62`

**Reference behaviour**

```
5414 paAddobject / paInit / paAlloc / paList pushed
5442 call objc_msgSend   ; [List alloc]
5451 call objc_msgSend   ; [<allocated> init]
5460 call objc_msgSend   ; [<list> addObject:socket]
5465 894608  mov [esi+8], eax    ; validSockets = the result of addObject:
```

That is `validSockets = [[[List alloc] init] addObject:socket];` — the ivar
receives `addObject:`'s return value, which for `List` is the receiver.

**Our source**

```objc
validSocketsList = [[List alloc] init];
[validSocketsList addObject:socket];
```

**Difference:** statement shape only. `-[List addObject:]` returns `self`, so both
leave the same object in the ivar.

**Disposition:** accept

**Rationale:** the values are identical and our form is clearer. The rest of this
method matches exactly: `socket` stored at +4, `[theSocket socketNumber]` cached
at +12, `number` at +16, `memoryWindow` as a byte at +20, `return self`. The
`memoryWindow` argument type divergence is Finding 11's, and the ivar name is
Finding 4's.

**Outcome: accepted, nothing changed under this finding.** The list is still built
in two statements. The method did change under the other two findings it appears
in: the ivar it assigns is now called `validSockets` rather than
`validSocketsList` (Finding 4, commit `2a99753a`) and the `memoryWindow` argument
is now declared `char` (Finding 11(d), commit `091c8f3a`). Ledger address 5368 ->
`intentional-mismatch`, reviewer Pat Raynor, with a reason recording that
`-[List addObject:]` returns `self` so both forms leave the same object in the
ivar. Terminal, as above.

## Functions examined with no divergence found

Eighteen hand-written functions match at every level examined — same symbol name,
same type encoding, same ivar offsets, same instruction semantics. They are the
only ones this pass advanced past `unexamined`:

| Address | Function | What it does |
| --- | --- | --- |
| 224 | `+[PCIC probe:]` | `[[self alloc] initFromDeviceDescription:]`, `setnz` BOOL conversion |
| 280 | `+[PCIC deviceStyle]` | returns 0 |
| 1212 | `-[PCIC interrupt]` | `[[self deviceDescription] interrupt]` |
| 1252 | `-[PCIC getPowerState:]` | returns -711 (`IO_R_UNSUPPORTED`) |
| 1464 | `-[PCIC getPowerManagement:]` | returns -711 |
| 1476 | `-[PCIC setPowerManagement:]` | returns -711 |
| 3788 | `-[PCICSocket adapter]` | reads ivar +4 |
| 4556 | `-[PCICSocket cardVccPower]` | register 2, bit 4 |
| 4736 | `-[PCICSocket cardVppPower]` | register 2, bits 0–1 |
| 4908 | `-[PCICSocket cardIRQ]` | register 3, bits 0–3 |
| 5268 | `-[PCICSocket reset]` | empty body |
| 5480 | `-[PCICWindow validSockets]` | reads ivar +8 |
| 5496 | `-[PCICWindow socket]` | reads ivar +4 |
| 5544 | `-[PCICWindow systemAddress]` | reads ivar +24 |
| 5560 | `-[PCICWindow cardAddress]` | reads ivar +28 |
| 5576 | `-[PCICWindow mapSize]` | reads ivar +32 |
| 7364 | `-[PCICWindow(Attributes) firstSystemAddress]` | returns 0x10000 |
| 7376 | `-[PCICWindow(Attributes) lastSystemAddress]` | returns 0xFFFFFF |

These sit at `control-flow-confirmed` in the ledger, not `assembly-matched`: that
claim needs a rebuilt binary diffed against the reference, and no build was run.

*Updated by the fix pass:* the other 62 entries were advanced too, once their
findings were applied — 58 to `control-flow-confirmed` and 4 to
`intentional-mismatch` (984, 1264, 5368, 5904, the three accepted findings). Each
transited `signature-confirmed` on the way, because the ledger tool refuses to
skip states. The two build-generated entries were left at `intentional-mismatch`.
**Nothing was raised to `assembly-matched` and nothing can be** until a build
exists; the eighteen functions above have exactly the same evidence behind them
now as they did at report time, and the 58 newly advanced ones have less, since
their source was rewritten and never compiled. Nothing is left `unexamined`.

Separately, and worth recording positively even though the enclosing functions
diverge for other reasons: **every register number, bit position and mask in
`PCICSocket` and `PCICWindow` matches Apple's binary.** All ten remaining
`PCICSocket` register accessors, all fourteen `PCICWindow` register accessors,
`_setIoWindow`, `_FindEmptyMemoryRange`, `_MapAttributeMemory`,
`readAttributeMemory:forSocket:`, `readRegister:socket:` and
`writeRegister:socket:value:` are semantically exact. **All sixteen
`PCICWindow(Attributes)` constants match** (0x10, 0x1000, 1, 1, 0, 0x10000,
0xFFFFFF, 0x1000000, 0x1000, 0, 0x1000, 0x1000, 0, `memoryWindow == 0`,
`memoryWindow`, 1). The hardware-level reconstruction of this driver is sound;
its problems are structural.

## Unmapped: build-generated

`+[PCICKernelServerInstance kernelServerInstance]` (7524) and
`+[PCICVersion driverKitVersionForPCIC]` (7536) are emitted by the Kernel Server
project type and `Load_Commands.sect`, not written by hand. Accepted, same as the
equivalent pairs in drvPCIBus, drvPCMCIABus and Intel824X0PCI. Both are
six-instruction constant returns:

```
; 7524  +[PCICKernelServerInstance kernelServerInstance]
push ebp / mov ebp, esp / mov eax, offset _PCIC_instance / mov esp, ebp / pop ebp / retn

; 7536  +[PCICVersion driverKitVersionForPCIC]
push ebp / mov ebp, esp / mov eax, 1F4h / mov esp, ebp / pop ebp / retn
```

`1F4h` is 500, the DriverKit version the build stamps in; it is unrelated to the
`"Version" = "5.00"` strings in Findings 16 to 18, which are config-table values.

The third unmapped entry, `-[PCIC_PCI initFromDeviceDescription:]` at 0, is
Finding 3.

## PCIC_PCI: go/no-go

**Verdict: GO.** The reference's 221-byte
`-[PCIC_PCI initFromDeviceDescription:]` is completely legible and directly
implementable, and it belongs in a file we already have.

Three pieces of evidence make this a low-risk implementation rather than a guess:

1. **The class's home is known.** `__OBJC,__module_info` puts `PCIC_PCI` in
   `PCIC.m`, and its `IMP` at address 0 sits ahead of `+[PCIC probe:]` at 224, so
   Apple's `@implementation PCIC_PCI` precedes `@implementation PCIC` in that
   file. No new file, no new project entry.
2. **Its shape is fully specified by the class structure.** `PCIC_PCI` at 17352:
   superclass `PCIC`, `instance_size` 312 (i.e. no ivars of its own), no protocol
   list, one instance method and no class methods. `[super ...]` in the body
   resolves through `PCIC_PCI`'s `super_class` field at 17356, confirming the
   inheritance.
3. **The body has no unresolved operations.** Six calls, all named by
   relocations: one `getPCIdevice:function:bus:`, one `IOLog`, one
   `getPCIConfigData:atRegister:withDeviceDescription:` sent to the
   `IODirectDevice` class reference, one `setPortRangeList:num:`, and two
   `objc_msgSendSuper`. Every constant is visible. There is no data table to
   recover and no arithmetic whose meaning is in doubt.

The reconstruction, at source level:

```objc
@implementation PCIC_PCI

- initFromDeviceDescription:deviceDescription
{
    unsigned char device, bus;      /* var_1 at ebp-1, var_2 at ebp-2 */
    IORange range;                  /* var_14/var_10 at ebp-20 */

    if ([deviceDescription getPCIdevice:&device function:0 bus:&bus])   /* 14-42 */
        return [super free];                                           /* 184-207 */

    IOLog("PCIC: PCMCIA->PCI Bus Bridge Detected (Dev=%d, Bus=%d)\n",   /* 48-63 */
          device, bus);

    [IODirectDevice getPCIConfigData:&reg_base                         /* 68-90 */
                          atRegister:0x10
               withDeviceDescription:deviceDescription];
    reg_base &= 0xFFFC;                                                /* 95-105 */

    range.start = reg_base;                                            /* 110 */
    range.size  = 4;                                                   /* 113 */
    [deviceDescription setPortRangeList:&range num:1];                 /* 123-137 */

    if (![super initFromDeviceDescription:deviceDescription])          /* 142-176 */
        return [super free];                                           /* 184-207 */
    return self;                                                       /* 178 */
}

@end
```

Points worth calling out for whoever writes it:

- The receiver of `getPCIConfigData:atRegister:withDeviceDescription:` is the
  **`IODirectDevice` class**, loaded from `__OBJC,__cls_refs` at 17296 — it is a
  class method, sent before `[super init...]` has run.
- Register `0x10` is PCI BAR0. `and eax, 0FFFCh` masks to 16 bits **and** clears
  the two low BAR type bits, yielding the I/O base. That base is written back
  into the global `reg_base`, which is how the rest of the driver finds the chip.
- The port range is exactly 4 bytes wide (`mov [ebp+var_10], 4`), not the 2 bytes
  `Default.table` requests for the ISA path — the PD6832 exposes an extra index
  pair.
- Both `device` and `bus` are single bytes (`movzx eax, byte ptr`), and
  `function:` is passed `0`, i.e. a null pointer: the function number is not
  wanted.
- Both failure paths send `free` to **`super`**, not to `self`, and fall straight
  into the epilogue so the return value is `free`'s.
- The `IOLog` format string is already at `__cstring` 7548 and is one of the two
  `missing_strings`; adding it will close that half of the parity gap.

**Consequence for Task 9:** the class stays in scope. This is *not* the
`drvEISABus` `PnPArgStack` situation, where the reference code was too opaque to
reimplement responsibly; here the disassembly is a near-transcription. Task 9
Step 3 should write it into `PCIC.m` ahead of `@implementation PCIC`.

One caveat that is not a reason for no-go but should be recorded: the
implementation depends on `-[IODeviceDescription getPCIdevice:function:bus:]`,
`+[IODirectDevice getPCIConfigData:atRegister:withDeviceDescription:]` and
`-[IODeviceDescription setPortRangeList:num:]` existing in our DriverKit headers
with those exact signatures. The first two are used identically by
`Intel824X0PCI` and `drvPCIBus`, so they are present; `setPortRangeList:num:` was
not separately verified during this pass.

*Updated by the fix pass:* the class was written, in commit `3e7f1b25`, into
`PCIC.m` at line 49 ahead of `@implementation PCIC` as recommended. See Finding 3's
`**Outcome:**` line. The caveat above stands unresolved in one respect: whether the
three DriverKit signatures the body depends on are present *as used* has still not
been checked by a compiler, because no build was run.

## Apple's source ordering, per file

Function addresses give Apple's source order directly. Ours differs in five of
the six files. This is not a finding — behaviour is unaffected — but it is
recorded because it is the remaining obstacle to byte-level parity once the
findings above are applied, and because it costs nothing to capture now.

| File | Apple's order | Ours |
| --- | --- | --- |
| `PCIC.m` | `PCIC_PCI initFromDeviceDescription:`, then `PCIC`: `probe:`, `deviceStyle`, `initFromDeviceDescription:`, `sockets`, `windows`, `setStatusChangeHandler:`, `interruptOccurred`, `interrupt`, `getPowerState:`, `setPowerState:`, `getPowerManagement:`, `setPowerManagement:`, then the statics `socketIsValid`, `checkForCirrusChip`, `setStatusChangeInterrupt` | `deviceStyle`, `probe:`, `initFromDeviceDescription:`, `interruptOccurred`, `interrupt`, `sockets`, `windows`, `setStatusChangeHandler:`, `setPowerManagement:`, `setPowerState:`, `getPowerManagement:`, `getPowerState:`, then `_socketIsValid`, `_checkForCirrusChip`, `_setStatusChangeInterrupt`, `_setIoWindow`, `_setMemoryWindow` |
| `PCICDebug.m` | `FindEmptyMemoryRange`, `setWindow`, `MapAttributeMemory`, `readAttributeMemory:forSocket:`, `spoofInterrupt` | `_FindEmptyMemoryRange`, `_MapAttributeMemory`, `_setWindow`, `_readAttributeMemory:forSocket:`, `_spoofInterrupt` |
| `PCICInternal.m` | `readRegister:socket:`, `writeRegister:socket:value:` | same order |
| `PCICSocket.m` | `socketIsValid`, `initWithAdapter:socketNumber:`, `adapter`, `socketNumber`, `windows`, `status`, `setStatusChangeMask:`, `statusChangeMask`, `cardEnabled`, `setCardEnabled:`, `cardAutoPower`, `setCardAutoPower:`, `cardVccPower`, `setCardVccPower:`, `cardVppPower`, `setCardVppPower:`, `cardIRQ`, `setCardIRQ:`, `memoryInterface`, `setMemoryInterface:`, `reset`, `powerStates`, `setCardReset:` | getters grouped first, then setters, then `reset` |
| `PCICWindow.m` | `initWithSocket:memoryWindow:number:`, `validSockets`, `socket`, `setSocket:`, `systemAddress`, `cardAddress`, `mapSize`, `setMapWithSize:…`, `attributeMemory`, `setAttributeMemory:`, `enabled`, `setEnabled:`, `memoryInterface`, `setMemoryInterface:`, `is16Bit`, `set16Bit:`, then the statics `setMemoryWindow`, `setIoWindow` | getters grouped first, then setters; the two statics are in `PCIC.m` |
| `PCICWindowAttributes.m` | `canUse8Bit`, `canUse16Bit`, `mustBePowerOfTwo`, `writeProtectable`, `firstSystemAddress`, `lastSystemAddress`, `minimumSize`, `maximumSize`, `sizeAlignment`, `baseAlignment`, `offsetAlignment`, `slowestSpeed`, `fastestSpeed`, `addressLinesDecoded`, `supportsIO`, `supportsMemory` | alphabetical |

Apple's `PCICSocket.m` and `PCICWindow.m` interleave each getter with its setter;
ours group all getters then all setters. Apple's `PCICWindowAttributes.m` order is
the protocol's declaration order, not alphabetical.

## Analyzer disagreement

**IDA is authoritative** for the partition: its 82 functions match the reference's
Mach-O symbol table exactly, symbol for symbol and address for address.

**Ghidra reports 79.** It misses three functions entirely and agrees with IDA on
size for all 79 it does find:

- 2700 `-[PCIC(Internal) readRegister:socket:]` (46 bytes)
- 7316 `-[PCICWindow(Attributes) canUse8Bit]` (12 bytes)
- 7524 `+[PCICKernelServerInstance kernelServerInstance]` (12 bytes)

The third is the same systematic gap documented for drvPCMCIABus and
Intel824X0PCI — Ghidra loses the tiny `kernelServerInstance` stub across every
driver in this effort. The other two are new instances of the same shape (small
functions immediately after a larger one), not evidence of anything absent: all
three are in the symbol table and IDA disassembles normal bodies at each.

**angr reports 153**, all 82 real functions plus 71 spurious entries:

- **70 are 1-to-4-byte fragments inside real function bodies** — inter-function
  alignment padding and fall-through blocks that `CFGFast` promoted to functions.
  Addresses 182, 221, 277, 289, 445, 750, 823, 894, 931, 983, 1197, 1210, 1251,
  1443, 1450, 1553, 1562, 1669, 1683, 1821, 1871, 2539, 2658, 2685, 2693, 2746,
  2881, 2890, 2950, 3801, 3817, 3833, 3979, 4177, 4234, 4367, 4417, 4553, 4605,
  4735, 4782, 4954, 5131, 5267, 5275, 5285, 5479, 5493, 5509, 5541, 5557, 5573,
  5589, 5642, 5674, 5737, 5901, 5987, 6070, 6151, 6166, 6197, 6271, 6526, 6619,
  7081, 7349, 7457, 7469, 7506.
- **One lies beyond the end of `__TEXT,__text`**: address 7999, 10 bytes, inside
  `__TEXT,__const`. The symbol table names it `_PCIC_VERS_NUM`; reading that file
  offset confirms it holds the two ASCII characters `13`. `what(1)` version data
  that `CFGFast` mistook for code because the two sections share `rx`
  permissions. The same phenomenon was recorded for Intel824X0PCI.

angr also disagrees with IDA and Ghidra on exactly one size: at 2688
(`spoofInterrupt`) it reports 5 bytes rather than 9, because it treats the
`int 45h` at 2691 as a block terminator and splits off a 4-byte fragment at 2693.
That disagreement is itself corroborating evidence for Finding 6.

None of this affects the source map or the ledger; it is recorded as analyzer
noise.

## README status

`src/drivers-i386/README:9` currently reads:

```
 * Intel82365PCMCIA - needs compiled and then tested
```

**That understates the problem.** The driver in its current form would not survive
loading even if it were compiled and tested:

- `PCICSocket.m` references `__socketIsValid`, which the link leaves undefined
  (Finding 1). The kernel loader resolves symbols at load time; this one has
  nothing to resolve against.
- The class `PCI.table` names as the driver class, `PCIC_PCI`, does not exist
  (Finding 3), so the PCI auto-detect path has no entry point.
- All three classes have the wrong instance size and layout (Finding 4).

Against that, the README's phrasing is not wrong about the build: **the driver
does appear to compile**. The staged artifact at
`out/i386/Intel82365PCMCIA/PCIC.config/PCIC_reloc` exists with an accompanying
`make exit status was: 0`. But its provenance is inferred rather than observed
(§ Baseline build), and `ld -r` reporting success is precisely what masks
Finding 1 — so "compiles" is a weaker statement here than it looks.

Suggested wording, matching the phrasing used for the other reconstructed bus
drivers in the same file:

```
 * Intel82365PCMCIA - reconstructed against the reference binary; links with an unresolved symbol and is missing the PCIC_PCI class, fixes not yet applied
```

The README was **not** edited as part of this pass — this is a report, and the
later README task owns that file so all the reconstructed drivers get one
consistent rewording.

*Updated by the fix pass:* the wording suggested above is now out of date — the
fixes *are* applied, the unresolved symbol and the missing `PCIC_PCI` class are
both gone from the source — but it cannot be replaced by "complete" either, since
nothing was compiled and nothing was booted. The README task rewrote the line as

```
 * Intel82365PCMCIA - reconstructed against the reference binary, fixes applied except the four PCMCIA protocol adoptions, not yet compiled or tested
```

which is what the evidence in this document supports and no more.

## Uncertainty and limits of this pass

- **No build was run and no baseline parity of record exists.** The parity output
  in § Baseline parity is a cross-check against an artifact whose provenance is
  unproven. Findings 1, 8, 9, 11 and 17 quote measurements from it; each is
  independently corroborated by the source text, so no finding rests on the
  artifact alone. In particular Finding 1's `N_UNDF|N_EXT` symbol is what the C
  language rules predict from `static` in one file and `extern` in another, so
  the artifact confirms rather than establishes it.
- **"Instruction level" means the reference was read completely and compared to
  our source text.** It does not mean our compiled output was diffed against the
  reference. Where this report says a body "matches instruction for instruction"
  it is asserting that our source, compiled by an equivalent compiler, would
  produce the same instructions — an inference, not a measurement. The 18
  functions in § Functions examined with no divergence found sit at
  `control-flow-confirmed` for exactly that reason.
- **Ten `PCICSocket` accessors were read with the `io_inline.h` expansion
  filtered.** Named in § Summary. The filtered instructions are the uniform
  `out dx, al` / `inc ds:_xxx.86` / `in al, dx` sequence, verified byte for byte
  in three unfiltered siblings, but they were not re-read individually in those
  ten.
- **Finding 13 is the least well bounded.** The four `PCMCIA*` protocols are
  declared somewhere outside this driver, most likely in `drvPCMCIABus`; this
  pass did not go looking for them, so it cannot say how much work adopting them
  is. Task 9 should scope that before committing to it.

  *Scoped by the fix pass, and left undone.* Only one of the four,
  `PCMCIAAdapter`, exists in the tree at all, and it is behind `DRIVER_PRIVATE`
  in `drvPCMCIABus`. The other three would have had to be invented. See Finding
  13's `**Outcome:**` line for the recovery route: decode the reference's five
  `__OBJC,__protocol` records and land the results in `drvPCMCIABus`.

- **A build-time hazard was found in review and could not be settled without a
  compiler.** `-[PCICSocket status]` now returns a 4-byte struct while
  `drvPCMCIABus` declares the same selector as returning `unsigned int`. Under
  `-freg-struct-return` — which is what Apple's binary uses — the two agree;
  under `-fpcc-struct-return` they would silently disagree across a driver
  boundary. Recorded in full under § Post-fix parity, with the check to perform.
- **Apple's original *source text* is inferred in places.** The reconstructions
  in Findings 2, 5, 7 and § PCIC_PCI: go/no-go are certain at the machine level
  and only probable at the source level — particularly the argument names and
  the choice between `if`/`else` and early return, which the compiler erases.
- **`-[PCICSocket status]` reads an uninitialised register.** At 3844 the
  reference does `mov eax, esi; xor al, al; mov esi, eax` before `esi` has been
  written, so bits 8–31 of its return value are whatever the caller left in
  `esi`. That is consistent with the declared return type being an eight-bit
  bitfield struct — only the low byte is defined — but it means a caller that
  widens the result to `int` sees garbage. Our version returns a clean value.
  Not raised as a finding because the type Apple declares makes the upper bits
  meaningless; noted because a byte-level comparison will show it.
- **`-[PCIC(Debug) readAttributeMemory:forSocket:]` carries a redundant test on
  both sides.** The reference reaches address 2639 (`test ebx, ebx`) from two
  places: the `jnz` at 2624 when the ready bit appears, and the fall-through at
  2637 when the retry count reaches zero. On the first path `ebx` is always at
  least 1, because the decrement happens after the test, so the `jz` there can
  only be taken on the timeout path. Our `if (retries == 0)` reproduces the same
  shape exactly. Recorded as a shared quirk, not a divergence.
