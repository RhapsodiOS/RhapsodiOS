# Intel824X0PCI divergences

Reference: `Intel824X0_reloc`, SHA-256 `2056748F5588CD447F79989689BD6C8B1232A8D7CF2037FD6D4B5E7CDE4998A0`
Analyses: IDA 9.2, Ghidra 12.1, angr 9.3.0

## Baseline build

**No build was performed as part of this pass.** The Rhapsody build guest was
unreachable at report time, so this report does not carry a fresh build verdict.
That step is deferred.

What *is* on disk, and is reported here only as an observation rather than as a
baseline this pass produced: an untracked staged artifact exists at
`out/i386/Intel824X0PCI/Intel824X0.config/Intel824X0_reloc`, 82516 bytes, mtime
2026-07-25 13:19, alongside an `out/i386/Intel824X0PCI/README.txt` recording
`make exit status was: 0`. Two things suggest it was produced from the current
source tree rather than from some other checkout: the staged
`Intel824X0.config/Default.table` is byte-identical to our
`src/drivers-i386/bus/Intel824X0PCI/Intel824X0.drvproj/Default.table` (including
the `"Auto Detect_IDs"` misspelling recorded as Finding 9 below), and the
artifact's symbol table contains a stabs entry naming the build path
`/build/source/src/drivers-i386/bus/Intel824X0PCI/Intel824X0.build/derived_src/Intel824X0.drvproj/Intel824X0.lksproj/Intel824X0_instance.m`.
Neither of those establishes *when* it was built or against which revision of
`Intel824X0.m`, so its provenance is not proven and it is not treated as this
pass's baseline. Confirming it — by rebuilding on the guest and re-comparing — is
deferred together with the build itself.

The artifact is larger than the reference's 28376 bytes because our builds are
unstripped; that size difference would not be a finding.

## Baseline parity

**The Task 3 Step 5 baseline parity run was not performed either**, for the same
reason: no build of record exists for this pass.

`tools/binrecon/parity_check.py` *was* run during this pass against the
unverified staged artifact described above, purely as an independent cross-check
on the disassembly findings. It is recorded here labelled as such — it is not the
deferred baseline parity output, and the findings below do not depend on it. The
output was:

```
missing_strings (8):
    '%s: Detected '
    '%s: Disabling PCI-to-Memory write posting.\n'
    '%s: PCI-to-Memory write posting disabled by BIOS.\n'
    'Host-Bridge\n'
    'Intel '
    'Intel 82424ZX Host-Bridge\n'
    'Intel 82434%cX Host-Bridge (step A-%d)\n'
    'Other'
missing_symbols (0):
extra_strings (8):
    'Intel 824X0 PCI Host Bridge'
    'Intel824X0: %s\n'
    'Intel824X0: %s: Write-posting already disabled\n'
    'Intel824X0: %s: Write-posting enabled, disabling...\n'
    'Intel824X0: Intel 82440FX (Natoma) PCI and Memory Controller detected\n'
    'Intel824X0: Intel 82443FX (Orion) C-%d stepping detected\n'
    'Intel824X0: Intel chipset detected (device ID 0x%04x)\n'
    'Intel824X0: Unknown or unsupported chipset\n'
extra_symbols (7):
    ''
    '+[Intel824X0 probe:]:f2'
    '+[Intel824X0KernelServerInstance kernelServerInstance]:f268=*256'
    '+[Intel824X0Version driverKitVersionForIntel824X0]:f1'
    '-[Intel824X0 initFromDeviceDescription:]:f23'
    '/build/source/src/drivers-i386/bus/Intel824X0PCI/Intel824X0.build/derived_src/Intel824X0.drvproj/Intel824X0.lksproj/Intel824X0_instance.m'
    'Intel824X0.m'
```

Read plainly: every one of the reference's four `__text` symbols is present
(`missing_symbols (0)`), so the class, method set and build-generated glue line up
exactly — but **every single one of the reference's nine `__cstring` entries other
than the class name `Intel824X0` is absent**, replaced one-for-one by eight
strings of our own invention. The `extra_symbols` entries are stabs debug symbols
and the empty string, i.e. the expected consequence of comparing an unstripped
object against a stripped one, and are not findings.

## Post-fix parity

**Not run.** The fix pass had no transport to a Rhapsody build host either, so no
rebuild was performed and there is no post-fix artifact to compare. Running
`parity_check.py` again would only have re-measured the same unchanged staged
binary described above and reported the pre-fix result, which would be worse than
no number at all. No parity output is recorded here, and none is estimated.

What this leaves unverified is worth naming plainly: the source changes recorded
in the `**Outcome:**` lines below **have not been compiled**. Nothing here
establishes that the file still builds, that the nine reference `__cstring`
entries now appear verbatim, or that `-[Intel824X0 initFromDeviceDescription:]`
still fits inside the reference's 459 bytes of code. The replacement strings were
written to match the enumerated `__cstring` table character for character,
including the absent trailing newline on `%s: Detected `, but matching intent is
not the same evidence as a parity run. Steps 4 to 6 of the Task 6 brief should be
run before this driver is called done.

## Summary

| Bucket | Count |
| --- | --- |
| mapped | 2 |
| unmapped | 2 |
| duplicate_candidates | 0 |
| boundary_disputed | 0 |

All four reference functions were examined at instruction level — this driver is
548 bytes of `__TEXT,__text` in total, so a complete read was affordable and no
function was deferred. Both mapped functions (`+[Intel824X0 probe:]`, 24
instructions; `-[Intel824X0 initFromDeviceDescription:]`, 149 instructions) were
read line by line against `Intel824X0.m`. Both unmapped functions (6 instructions
each) were read as well and are the trivial build-generated stubs described below.
No function was examined at control-flow level only, and none was left unexamined
for time or size reasons.

Both mapped functions carry confirmed divergences and therefore remain
`unexamined` in the ledger, per the convention established by the drvPCIBus and
drvPCMCIABus passes: a function known to diverge is written up here rather than
given a positive status it has not earned. Ten findings follow; seven concern
`-[Intel824X0 initFromDeviceDescription:]` (one of which is accepted), one concerns
`+[Intel824X0 probe:]`, and two concern `Default.table`.

*Updated by the fix pass:* the nine `fix` findings have been applied and both
mapped functions now sit at `control-flow-confirmed`. See the `**Outcome:**` line
on each finding, and `## Post-fix parity` for what that status does and does not
rest on.

The headline is that our `-[Intel824X0 initFromDeviceDescription:]` has the right
*shape* — the same message sends in the same order, the same PCI registers, the
same branch structure — but identifies the wrong two chipsets, and every string it
prints is invented. The reference detects the **Intel 82424ZX** and the **Intel
82434LX/NX**; our source calls them the 82440FX (Natoma) and the 82443FX (Orion).

## Reference `__cstring`, enumerated

Sliced directly out of the reference at section offset 2876, length 213
(`__TEXT,__cstring`, address 548):

| Address | String |
| --- | --- |
| 548 | `Intel824X0` |
| 559 | `Other` |
| 565 | `%s: Detected ` |
| 579 | `Intel 82424ZX Host-Bridge\n` |
| 606 | `Intel 82434%cX Host-Bridge (step A-%d)\n` |
| 646 | `Intel ` |
| 653 | `Host-Bridge\n` |
| 666 | `%s: Disabling PCI-to-Memory write posting.\n` |
| 710 | `%s: PCI-to-Memory write posting disabled by BIOS.\n` |

The absence of a trailing `\n` on `%s: Detected ` is load-bearing: the reference
builds one console line out of two or three separate `IOLog` calls, with `[self
name]` as the `%s` prefix. `Intel ` and `Host-Bridge\n` are the two halves of the
fall-through name for an unrecognised Intel part. This is the anchor that makes
the rest of the disassembly legible.

## Unmapped: build-generated

`+[Intel824X0KernelServerInstance kernelServerInstance]` (address 524) and
`+[Intel824X0Version driverKitVersionForIntel824X0]` (address 536) — emitted by
the Kernel Server project type and `Load_Commands.sect`, not written by hand.
Accepted, same as the equivalent pairs in drvPCIBus and drvPCMCIABus. Both are
six-instruction constant returns:

```
; 524  +[Intel824X0KernelServerInstance kernelServerInstance]
push ebp / mov ebp, esp / mov eax, offset _Intel824X0_instance / mov esp, ebp / pop ebp / retn

; 536  +[Intel824X0Version driverKitVersionForIntel824X0]
push ebp / mov ebp, esp / mov eax, 1F4h / mov esp, ebp / pop ebp / retn
```

`1F4h` is 500, the DriverKit version the build stamps in; it is unrelated to the
`"Version" = "5.01"` line missing from our `Default.table` (Finding 10), which is
a config-table string, not this value.

## Analyzer disagreement: Ghidra misses `kernelServerInstance` entirely

IDA reports four functions at `(0, 61)`, `(64, 459)`, `(524, 12)`, `(536, 12)`.
Ghidra reports only three — it has no function at 524 at all, though it agrees
exactly with IDA on the other three, including the 459-byte body and its 21 basic
blocks. This is a Ghidra detection gap for one function, not evidence the function
is absent: the reference's Mach-O symbol table lists
`+[Intel824X0KernelServerInstance kernelServerInstance]` at address 524 in
`__text`, and IDA disassembles a normal 12-byte body there. It is the same pattern
documented for `-[_PCMCIAPool init]` and `+[PCMCIABusKernelServerInstance
kernelServerInstance]` in the drvPCMCIABus pass — Ghidra appears to systematically
lose the tiny `kernelServerInstance` stub across these drivers. IDA is
authoritative for the partition; recorded here, and it does not affect the source
map or the ledger.

angr reports nine entries. Four are the real functions. Three — at 61 (3 bytes),
269 (3 bytes) and 470 (2 bytes) — are inter-function alignment padding and
fall-through fragments inside the two real bodies, not functions. The remaining
two, at 761 (159 bytes) and 921 (10 bytes), lie **beyond** the 548-byte
`__TEXT,__text` section entirely: 761 and 921 are inside `__TEXT,__const`, and the
symbol table names them `_Intel824X0_VERS_STRING` and `_Intel824X0_VERS_NUM`.
Reading those file offsets confirms it — 761 holds the ASCII string
`@(#)PROGRAM:Intel824X0  PROJECT:drvIntel824X0PCI-12  DEVELOPER:root  BUILT:Sat
Mar 28 22:09:31 PST 1998\n` and 921 holds `12`. These are `what(1)` version data
that `CFGFast` mistook for code because the two sections share `rx` permissions.
Recorded as analyzer noise; no action taken.

## Finding 1: `+[Intel824X0 probe:]` allocates through `self`, not through a class reference

**Source:** `src/drivers-i386/bus/Intel824X0PCI/Intel824X0.drvproj/Intel824X0.lksproj/Intel824X0.m:50`

**Reference behaviour**

```
0   push ebp
1   mov ebp, esp
3   mov edx, [ebp+arg_8]           ; deviceDescription
6   push edx
7   mov edx, ds:paInitfromdevice   ; reloc -> __message_refs+4, sel initFromDeviceDescription:
13  push edx
14  mov edx, ds:paAlloc            ; reloc -> __message_refs+0, sel alloc
20  push edx
21  mov edx, ds:paIntel824x0_0     ; reloc -> __OBJC,__cls_refs (8232), class Intel824X0
27  push edx
28  call _objc_msgSend             ; [Intel824X0 alloc]
33  add esp, 8
36  push eax
37  call _objc_msgSend             ; [<new> initFromDeviceDescription:deviceDescription]
42  test eax, eax
44  jnz loc_34
46  xor eax, eax                   ; return NO
...
52  mov eax, 1                     ; return YES
```

**Our source**

```objc
instance = [[self alloc] initFromDeviceDescription:deviceDescription];
if (instance == nil) {
    return NO;
}
return YES;
```

**Difference:** the receiver of `alloc`. The reference loads it from
`__OBJC,__cls_refs`, which is what the compiler emits for a *named* class
(`[Intel824X0 alloc]`); ours loads `[ebp+arg_0]`, which is what it emits for
`[self alloc]` in a class method. This was verified against our own build rather
than inferred: `+[Intel824X0 probe:]` in
`out/i386/Intel824X0PCI/Intel824X0.config/Intel824X0_reloc` reads
`8b 55 08  mov edx, [ebp+8]` at the corresponding point where the reference reads
`8b 15 28 20 00 00  mov edx, ds:paIntel824x0_0`. That 3-byte-versus-6-byte
encoding accounts exactly for the whole size difference between the two functions:
our body is 58 bytes, the reference's is 61.

Everything else in this function matches: the same two `objc_msgSend` calls with
the same argument order, the same `add esp, 8` between them, the same `test eax,
eax`. The two also differ in which return value the compiler laid down first —
the reference emits the `xor eax, eax` (NO) block before the `mov eax, 1` (YES)
block, ours the reverse — but the branch condition is inverted to match (`jnz` vs
`jz`) and the semantics are identical. That ordering is a code-generation
artifact, not a source difference, and is not part of this finding.

**Disposition:** fix

**Rationale:** behaviour-neutral for this class, which is never subclassed, so
nothing observable changes. Worth doing anyway because it is the *only* remaining
difference in an otherwise instruction-for-instruction match, and the one-token
change buys byte-level parity for the whole function.

**Outcome:** fixed. `[self alloc]` became `[Intel824X0 alloc]` at
`Intel824X0.m:50`, which is what makes the compiler emit an `__OBJC,__cls_refs`
load instead of an `[ebp+self]` load. `+[Intel824X0 probe:]` (ledger address 0)
advanced `unexamined` → `signature-confirmed` → `control-flow-confirmed`. It is
not `assembly-matched`: that claim needs a rebuilt binary, and no build was run
this pass.

## Finding 2: both PCI device IDs are attributed to the wrong chipsets

**Source:** `.../Intel824X0.m:36-38`, `:97-120`

**Reference behaviour**

```
250 mov eax, [ebp+var_C]           ; the dword read from PCI config register 0
253 cmp eax, 4838086h
258 jz  loc_110                    ; -> 272, "Intel 82424ZX Host-Bridge\n"
260 cmp eax, 4A38086h
265 jz  loc_120                    ; -> 288, "Intel 82434%cX Host-Bridge (step A-%d)\n"
267 jmp loc_160                    ; -> 352, the generic fall-through
```

`0x04838086` reaches the `IOLog` at 277 whose only argument is the string at 579,
`Intel 82424ZX Host-Bridge\n`. `0x04A38086` reaches the `IOLog` at 336 whose format
string is the one at 606, `Intel 82434%cX Host-Bridge (step A-%d)\n`. There is no
ambiguity about which string belongs to which branch — each is a direct `push
offset` immediately before its call, with a relocation naming the `__cstring`
address.

**Our source**

```c
#define INTEL_82440FX_DEVID    0x0483  /* 82440FX (Natoma) */
#define INTEL_82443FX_DEVID    0x04A3  /* 82443FX (Orion) */
```

with matching log text `Intel 82440FX (Natoma) PCI and Memory Controller
detected` and `Intel 82443FX (Orion) C-%d stepping detected`.

**Difference:** the two IDs our source tests are numerically correct — the
comparisons `0x04838086` and `0x04A38086` match the reference exactly, and so does
`Default.table`'s `"0x04838086 0x04A38086"` — but the parts they are said to
identify are wrong. Apple's binary names them the **82424ZX** (the Saturn-family
host bridge) and the **82434LX/NX** (Mercury/Neptune). Our source names them the
82440FX (Natoma) and the 82443FX (Orion), which are different silicon; 0x1237 is
the 82441FX/82440FX host bridge PCI device ID, not 0x0483. The reference is right
and our reconstruction guessed.

**Disposition:** fix

**Rationale:** this is the root error the rest of the divergences in this function
grow out of. Every log string, the stepping decode in Finding 4, and the comment
block at the top of `Intel824X0.m` are all downstream of the wrong chipset
identity. It is not merely cosmetic even though it only affects console output:
anyone reading the boot log to work out which host bridge the machine has would be
told the wrong answer, and the driver's own name (`Intel824X0` — a 824*X*0 family
part, i.e. 82424/82434, not 8244x) contradicts our labelling.

**Outcome:** fixed. `INTEL_82440FX_DEVID` and `INTEL_82443FX_DEVID` were deleted
and replaced by `INTEL_82424ZX_ID 0x04838086` and `INTEL_82434LX_ID 0x04A38086`,
whole 32-bit config-register-0 dwords rather than device-ID halves, so the two
comparisons now read as the single `cmp` each that the reference emits instead of
being reassembled from a shift and an or. Ledger address 64 →
`control-flow-confirmed`.

## Finding 3: the detection banner is one composed line in the reference and three independent lines in ours

**Source:** `.../Intel824X0.m:93-127`

**Reference behaviour**

```
204 push 0                          ; register 0
206 lea eax, [ebp+var_C]
209 push eax
210 mov edx, ds:paGetpciconfigda
216 push edx
217 push ebx                        ; self
218 call _objc_msgSend              ; [self getPCIConfigData:&configData atRegister:0]
223 mov edx, ds:paName
229 push edx
230 push ebx
231 call _objc_msgSend              ; [self name]
236 push eax
237 push offset aSDetected          ; "%s: Detected "        <- no newline
242 call _IOLog
```

and then, on each of the three branches, a *second* `IOLog` that supplies only the
tail of the same line:

- 82424ZX branch (272): `IOLog("Intel 82424ZX Host-Bridge\n")`
- 82434 branch (336): `IOLog("Intel 82434%cX Host-Bridge (step A-%d)\n", c, step)`
- fall-through (352): `if (low 16 bits of configData == 0x8086) IOLog("Intel ");`
  then, unconditionally, `IOLog("Host-Bridge\n")`

So the reference produces exactly one console line per boot, e.g.
`Intel824X0: Detected Intel 82424ZX Host-Bridge`.

**Our source**

```c
deviceName = [self name];
IOLog("Intel824X0: %s\n", deviceName);
...
IOLog("Intel824X0: Intel 82440FX (Natoma) PCI and Memory Controller detected\n");
```

**Difference:** three things at once. (a) Our first log terminates with `\n`, so
the name and the chipset land on separate lines instead of composing. (b) Our
format is `"Intel824X0: %s\n"` — the driver name is hardcoded into the literal and
`%s` receives `[self name]`, which *is* the driver name, so the line reads
`Intel824X0: Intel824X0`; the reference's `"%s: Detected "` uses `[self name]` as
the prefix and the literal contributes the word `Detected`. (c) Our per-chipset
messages re-prefix `Intel824X0: ` themselves, which the reference's tails never do.

**Disposition:** fix

**Rationale:** the message-send sequence is already correct — `[self
getPCIConfigData:&configData atRegister:0]`, then `[self name]`, then `IOLog` —
so this is a string-and-newline change, not a restructuring. Fixing it is a
prerequisite for Findings 4 and 6, which describe the tails of the line this
finding establishes.

**Outcome:** fixed. The banner is now `IOLog("%s: Detected ", [self name]);` with
no trailing newline, and the three tails supply the rest of the line. The
`deviceName` local was dropped and `[self name]` is called inline at all three
sites, matching the reference, which pushes the `objc_msgSend` result straight
into the `IOLog` argument list and keeps no such local: its frame is exactly
`objc_super` + `configData` + the flag (`lea esp, [ebp-1Ch]` at 513 over three
saved registers). The `vendorID`, `deviceID` and `revisionID` locals were dropped
for the same reason. Ledger address 64 → `control-flow-confirmed`.

## Finding 4: the 82434 stepping letter uses `0x0C`/`0x0E` and `%d` where the reference uses `'L'`/`'N'` and `%c`

**Source:** `.../Intel824X0.m:102-119`

**Reference behaviour**

```
288 push 8                          ; PCI_REVISION_ID
290 lea eax, [ebp+var_C]
293 push eax
294 mov edx, ds:paGetpciconfigda
300 push edx
301 push ebx
302 call _objc_msgSend              ; [self getPCIConfigData:&configData atRegister:8]
307 mov eax, [ebp+var_C]
310 and eax, 0Fh                    ; step = revision & 0x0F     -> the %d
313 push eax
314 mov eax, 4Ch                    ; 'L'
319 test byte ptr [ebp+var_C], 10h
323 jz  loc_14A                     ; bit 4 clear -> keep 'L'
325 mov eax, 4Eh                    ; 'N'
330 push eax                        ;                            -> the %c
331 push offset aIntel82434CxHo     ; "Intel 82434%cX Host-Bridge (step A-%d)\n"
336 call _IOLog
341 add esp, 1Ch
344 cmp byte ptr [ebp+var_C], 10h
348 jnz loc_182                     ; -> 386, skip the write-posting fix
350 jmp loc_188                     ; -> 392, do the write-posting fix
```

So: the `%c` is `'N'` (0x4E) when bit 4 of the revision byte is set and `'L'`
(0x4C) when it is clear — that is, it selects 82434**N**X from 82434**L**X, which
is exactly what the brief predicted. The `%d` is the low nibble of the revision
register, printed after the fixed text `step A-`. And the write-posting fix is
armed on this branch only when the revision byte is *exactly* `0x10` — the
82434NX A-0 stepping.

Note the reference does not set the `needsWritePostingFix` flag (`var_10`) on this
branch at all; instead it branches straight into the write-posting block at 392,
bypassing the `cmp [ebp+var_10], 0` test at 386. That is a code-generation detail;
the effect is identical to setting the flag.

**Our source**

```c
if (configData & 0x10) {
    IOLog("Intel824X0: Intel 82443FX (Orion) C-%d stepping detected\n",
          0x0E, revisionID & 0x0F);
} else {
    IOLog("Intel824X0: Intel 82443FX (Orion) C-%d stepping detected\n",
          0x0C, revisionID & 0x0F);
}
if ((revisionID & 0xFF) == 0x10) {
    needsWritePostingFix = YES;
}
```

**Difference:** the branch condition (`configData & 0x10`) and the low-nibble
extraction (`revisionID & 0x0F`) are both correct and match the reference exactly.
The constants and the conversion specifier are not:

- The reference's `0x4C`/`0x4E` are the ASCII characters `'L'` and `'N'`. Our
  `0x0C`/`0x0E` are the same values with the high nibble dropped — control
  characters, not letters. This looks like a transcription slip in the original
  reconstruction: someone read `4Ch`/`4Eh` and wrote `0x0C`/`0x0E`.
- The reference prints them with `%c`. Our format string uses `%d`, so even the
  intended letter would come out as a number.
- Our format string has **one** `%d` but is passed **two** arguments. The one that
  actually gets consumed is the first — `0x0E` or `0x0C` — so the line as built
  prints `C-14` or `C-12`, and the real stepping value (`revisionID & 0x0F`) is
  silently discarded. This is a live bug in our source today, not just a
  cosmetic mismatch.
- The reference's text is `(step A-%d)`; ours says `C-%d stepping`, so even the
  letter of the stepping family is wrong.
- The reference computes the stepping nibble from `configData` directly after
  re-reading register 8 into the same variable; ours introduces a separate
  `revisionID` local. Behaviourally the same, since our `revisionID = configData &
  0xFF` immediately follows the same read.

The write-posting arming condition matches: reference `revision byte == 0x10`,
ours `(revisionID & 0xFF) == 0x10`.

**Disposition:** fix

**Rationale:** the argument-count mismatch alone makes this a correctness bug —
a varargs call whose format string under-consumes its arguments. Combined with
Finding 2 the whole branch currently reports a chipset that is not present and a
stepping value that was never read.

**Outcome:** fixed. The branch is now a single `IOLog("Intel 82434%cX
Host-Bridge (step A-%d)\n", (configData & 0x10) ? 'N' : 'L', configData & 0x0F);`
— two conversions, two arguments, so the arity bug is gone. The ternary replaces
the if/else pair, which is what the reference's `mov eax, 4Ch` / conditional `mov
eax, 4Eh` at 314–325 is: one value selected, one call site. The separate
`revisionID` local was dropped and the arming test rewritten as `(configData &
0xFF) == 0x10`, the byte compare the reference performs at 344. Ledger address 64
→ `control-flow-confirmed`.

## Finding 5: `setDeviceKind:` passes a descriptive string where the reference passes `"Other"`

**Source:** `.../Intel824X0.m:71`

**Reference behaviour**

```
101 push offset aOther              ; "Other"   (__cstring 559)
106 mov edx, ds:paSetdevicekind
112 push edx
113 push ebx                        ; self
114 call _objc_msgSend              ; [self setDeviceKind:"Other"]
```

**Our source**

```objc
[self setDeviceKind:"Intel 824X0 PCI Host Bridge"];
```

**Difference:** the string. `"Other"` is not arbitrary — it is the same value as
`"Family" = "Other";` in both our `Default.table` and the reference's, so Apple
kept the device kind and the config-table family in agreement. `[self
setName:"Intel824X0"]` on the preceding line matches exactly (reference pushes
`aIntel824x0`, `__cstring` 548), as does the ordering: both `setName:` and
`setDeviceKind:` are sent *before* `[super initFromDeviceDescription:]`, which our
source also does.

**Disposition:** fix

**Rationale:** `deviceKind` is surfaced by DriverKit device inspection and by
`IODeviceDescription`; a driver reporting a different kind than the reference is a
real, externally visible behaviour difference, however small. It is also a
one-string change.

**Outcome:** fixed. `[self setDeviceKind:"Intel 824X0 PCI Host Bridge"]` became
`[self setDeviceKind:"Other"]`, agreeing with `"Family" = "Other";` in
`Default.table` as the reference does. Ledger address 64 →
`control-flow-confirmed`.

## Finding 6: the unrecognised-device path composes `"Intel "` + `"Host-Bridge\n"` instead of logging two unrelated lines

**Source:** `.../Intel824X0.m:121-127`

**Reference behaviour**

```
352 cmp word ptr [ebp+var_C], 8086h   ; low 16 bits = vendor ID
358 jnz loc_175                       ; -> 373
360 push offset aIntel                ; "Intel "
365 call _IOLog
370 add esp, 4
373 push offset aHostBridge           ; "Host-Bridge\n"
378 call _IOLog
383 add esp, 4
386 cmp [ebp+var_10], 0               ; needsWritePostingFix
390 jz  loc_1F0                       ; -> 496, return
```

Combined with the `"%s: Detected "` prefix from Finding 3, an Intel part with an
unrecognised device ID prints `Intel824X0: Detected Intel Host-Bridge`, and a
non-Intel part prints `Intel824X0: Detected Host-Bridge`. Note the vendor test
uses a 16-bit compare against the *low* half of the config dword, so it is testing
the vendor ID field, and note that `Host-Bridge\n` is emitted unconditionally on
this path — the `jnz` skips only the `"Intel "` fragment. The write-posting flag is
never set on this path, so an unrecognised device gets no register write.

**Our source**

```c
if (vendorID == INTEL_VENDOR_ID) {
    IOLog("Intel824X0: Intel chipset detected (device ID 0x%04x)\n", deviceID);
}
IOLog("Intel824X0: Unknown or unsupported chipset\n");
```

**Difference:** the branch structure is right — a vendor-ID test guarding one log,
followed by an unconditional log — but both strings are invented, both are
self-prefixed and newline-terminated so they do not compose with the `Detected `
prefix, and ours prints a `deviceID` value the reference never formats. The
reference has no `%04x` anywhere in `__cstring`; the value is simply not reported.

**Disposition:** fix

**Rationale:** same category as Finding 3 — the control flow is already correct
and only the strings need replacing, but "Unknown or unsupported chipset" actively
misinforms: the reference treats an unrecognised Intel host bridge as a perfectly
normal outcome and says so neutrally.

**Outcome:** fixed. The branch now reads `if ((configData & 0xFFFF) ==
INTEL_VENDOR_ID) IOLog("Intel ");` followed by an unconditional
`IOLog("Host-Bridge\n");`. The `deviceID` value we used to format is no longer
computed or printed, matching the reference, which has no `%04x` anywhere in
`__cstring`. Ledger address 64 → `control-flow-confirmed`.

## Finding 7: the write-posting log strings differ (the register, bit and polarity do not)

**Source:** `.../Intel824X0.m:130-145`

**Reference behaviour**

```
392 push 54h                          ; PCI_DRAMC
394 lea eax, [ebp+var_C]
397 push eax
398 mov edx, ds:paGetpciconfigda
404 push edx
405 push ebx
406 call _objc_msgSend                ; [self getPCIConfigData:&configData atRegister:0x54]
411 add esp, 10h
414 test byte ptr [ebp+var_C], 1      ; bit 0
418 jz  loc_1D8                       ; -> 472, already disabled

420 mov edx, ds:paName
426 push edx
427 push ebx
428 call _objc_msgSend                ; [self name]
433 push eax
434 push offset aSDisablingPciT       ; "%s: Disabling PCI-to-Memory write posting.\n"
439 call _IOLog
444 mov eax, [ebp+var_C]
447 and al, 0FEh                      ; clear bit 0
449 mov [ebp+var_C], eax
452 push 54h
454 push eax
455 mov edx, ds:paSetpciconfigda
461 push edx
462 push ebx
463 call _objc_msgSend                ; [self setPCIConfigData:configData atRegister:0x54]
468 jmp loc_1F0

472 mov edx, ds:paName                ; loc_1D8
478 push edx
479 push ebx
480 call _objc_msgSend                ; [self name]
485 push eax
486 push offset aSPciToMemoryWr       ; "%s: PCI-to-Memory write posting disabled by BIOS.\n"
491 call _IOLog
```

**Our source**

```c
[self getPCIConfigData:&configData atRegister:PCI_DRAMC];
if ((configData & DRAMC_WP_ENABLE) == 0) {
    deviceName = [self name];
    IOLog("Intel824X0: %s: Write-posting already disabled\n", deviceName);
} else {
    deviceName = [self name];
    IOLog("Intel824X0: %s: Write-posting enabled, disabling...\n", deviceName);
    configData &= ~DRAMC_WP_ENABLE;
    [self setPCIConfigData:configData atRegister:PCI_DRAMC];
}
```

**Difference:** strings only. Everything structural is correct and confirmed
against the disassembly: the register is `0x54` on both sides (our `PCI_DRAMC`),
the bit is bit 0 on both sides (our `DRAMC_WP_ENABLE`), the polarity matches
(bit set means posting is enabled, so it gets cleared; bit clear means the BIOS
already disabled it, so only a message is printed), the clear is `and al, 0FEh`
which is exactly `configData &= ~1`, and both sides call `[self name]` freshly
inside each branch rather than reusing a value cached earlier — three `[self
name]` sites in the reference (231, 428, 480) against three in ours (lines 93, 134,
138), of which at most two execute per call on either side.

The two message texts differ: ours prepends `Intel824X0: ` to a format that
already begins with `%s` (so the built driver prints `Intel824X0: Intel824X0: ...`),
and the wording is different — `Write-posting already disabled` versus `PCI-to-Memory
write posting disabled by BIOS.`, and `Write-posting enabled, disabling...` versus
`Disabling PCI-to-Memory write posting.`

**Disposition:** fix

**Rationale:** the doubled prefix is a visible defect in the built driver
regardless of reconstruction fidelity, and since the surrounding logic is already
correct the fix is confined to two string literals.

**Outcome:** fixed. The two literals became `"%s: Disabling PCI-to-Memory write
posting.\n"` and `"%s: PCI-to-Memory write posting disabled by BIOS.\n"`, losing
the doubled `Intel824X0: ` prefix. The `deviceName` local was dropped here too and
`[self name]` moved inline into each `IOLog`, which is what the reference does at
420–439 and 472–491. Deliberately *not* changed: the `if ((configData &
DRAMC_WP_ENABLE) == 0) { … } else { … }` sense, which this finding records as
already correct — the reference's `jz` reaches the BIOS-already-disabled message
and falls through to the disabling path, so the two source branches sit in the
opposite textual order from the reference's blocks while testing the same bit with
the same polarity. Inverting the source to match block order would be a
code-generation guess this finding does not support. A second, independent
signal was found during review: the reference binary's `__TEXT,__cstring`
section enumerates its nine string literals in a specific order, seven of
which appear in exactly the same order as the literals in our source text.
The only two that do not match are precisely this pair — the reference lists
`%s: Disabling PCI-to-Memory write posting.\n` before `%s: PCI-to-Memory write
posting disabled by BIOS.\n`, while our source has them reversed. This ordering
consistency suggests that the compiler emits `__cstring` entries in source-text
order, which would mean Apple wrote `if (configData & 1) { Disabling... } else
{ ...disabled by BIOS }`. Behaviour is identical either way; `parity_check.py`
compares strings as a set and will not flag this difference. The change was
correctly not made in this pass because the finding's disposition confined the
fix to the two string literals themselves, not their sequencing. Ledger address 64 →
`control-flow-confirmed`.

## Finding 8: the return values are computed differently (accepted)

**Source:** `.../Intel824X0.m:74-83`, `:147`

**Reference behaviour**

```
127 mov [ebp+var_8.receiver], ebx      ; objc_super.receiver = self
130 mov edx, ds:stru_202C.attributes   ; objc_super.class = superclass
136 mov [ebp+var_8.super_class], edx
139 lea eax, [ebp+var_8]
142 push eax
143 call _objc_msgSendSuper            ; [super initFromDeviceDescription:deviceDescription]
148 mov edi, eax                       ; edi holds the super result for the whole function
150 add esp, 24h
153 test edi, edi
155 jz  loc_1F4                        ; -> 500

161 push 0 / push 0 / push 0
167 mov edx, ds:paGetpcideviceFu
173 push edx
174 push esi                           ; deviceDescription, not self
175 call _objc_msgSend                 ; [deviceDescription getPCIdevice:0 function:0 bus:0]
180 add esp, 14h
183 test eax, eax
185 jnz loc_1F4                        ; -> 500

...
496 mov eax, edi                       ; loc_1F0: return the super result
498 jmp loc_201

500 mov edx, ds:paFree                 ; loc_1F4
506 push edx
507 push ebx
508 call _objc_msgSend                 ; [self free]  -- and fall straight into the epilogue,
513 lea esp, [ebp-1Ch]                 ;   so eax is free's return value, i.e. nil
```

**Our source**

```objc
if ([super initFromDeviceDescription:deviceDescription] == nil) {
    [self free];
    return nil;
}
if ([deviceDescription getPCIdevice:0 function:0 bus:0] != 0) {
    [self free];
    return nil;
}
...
return self;
```

**Difference:** two, both structural. On the success path the reference returns
the value `[super initFromDeviceDescription:]` gave back (kept in `edi` across the
entire function), where ours returns `self`. On the failure paths the reference
falls out of `[self free]` straight into the epilogue, so its return value *is*
`free`'s return value — effectively `return [self free];` — where ours discards it
and writes `return nil;` explicitly. Both failure paths in the reference share one
`[self free]` block at 500, as do ours after the compiler's tail merging.

**Disposition:** accept

**Rationale:** `-[Object free]` returns `nil` by contract, and
`-[IODirectDevice initFromDeviceDescription:]` returns `self` on success, so both
constructions produce identical values on every path. The difference is in how
Apple's source happened to be spelled, not in what the function does. Recorded
because it is real and confirmed, not because it needs changing.

**Outcome:** accepted, no change. `return self;` and the two `[self free]; return
nil;` failure paths are as they were.

Everything else in this prologue matches exactly, and is worth stating positively:
`objc_msgSendSuper` with a stack-built `objc_super`, the nil test on its result,
the `getPCIdevice:function:bus:` probe sent to **`deviceDescription`** (not to
`self`) with all three arguments zero, the `!= 0` failure test, and the
`[self registerDevice]` that follows.

## Finding 9: `Default.table` auto-detect key is misspelled

**Source:** `src/drivers-i386/bus/Intel824X0PCI/Intel824X0.drvproj/Default.table:8`

**Reference:** `"Auto Detect IDs" = "0x04838086 0x04A38086";`

**Ours:** `"Auto Detect_IDs" = "0x04838086 0x04A38086";`

**Difference:** an underscore where the reference has a space. The ID list itself
is identical.

**Disposition:** fix

**Rationale:** this is not cosmetic. `Auto Detect IDs` is the key the driver
loader looks up to match a PCI device against this driver; a key spelled
`Auto Detect_IDs` will simply not be found, so the driver would never be
auto-matched to the host bridge no matter how correct the code is. Confirmed
present in the staged build's copy of the table as well, so it is not a
transcription error in the report.

**Outcome:** fixed. `Default.table:8` now reads `"Auto Detect IDs"`. No ledger
entry covers `Default.table`, so no status moved for this.

## Finding 10: `Default.table` is missing the `Version` line

**Source:** `src/drivers-i386/bus/Intel824X0PCI/Intel824X0.drvproj/Default.table`

**Reference:** carries `"Version" = "5.01";` between `"Instance" = "0";` and
`"Server Name" = "Intel824X0";`.

**Ours:** the line is absent.

**Difference:** one missing key/value pair, in a specific position in the table.

**Disposition:** fix

**Rationale:** trivially restorable, and config-table version strings are read
back by driver-management tooling. No evidence was found either way about whether
its absence breaks loading, so it is recorded as a straightforward gap rather than
a severity claim.

**Outcome:** fixed. `"Version" = "5.01";` was inserted between `"Instance" = "0";`
and the first `"Server Name" = "Intel824X0";`, the position the reference uses.
`"Driver Version"` was deliberately not added; see the section below.

## Accepted: `Default.table` `"Driver Version"`

The reference table ends with

```
"Driver Version" = "PROGRAM:Intel824X0  PROJECT:drvIntel824X0PCI-12  DEVELOPER:root  BUILT:Sat Mar 28 22:09:34 PST 1998";
```

which our table does not have, and correctly so — it is stamped in by the build,
carries Apple's build host, developer and timestamp, and is the table-side twin of
the `_Intel824X0_VERS_STRING` blob in `__TEXT,__const` (same text, timestamp three
seconds earlier). Accepted; nothing to do.

## Functions examined with no divergence found

None. Both hand-written functions carry at least one confirmed divergence and stay
`unexamined` in the ledger. The two build-generated functions are recorded as
`intentional-mismatch`.

*Updated by the fix pass:* both hand-written functions were moved to
`control-flow-confirmed` once their divergences were applied, transiting
`signature-confirmed` on the way because the ledger tool refuses to skip states.
The two build-generated entries were left at `intentional-mismatch`.

## README status

`src/drivers-i386/README:8` currently reads:

```
 * Intel824X0PCI - complete
```

**The evidence does not support "complete."** Concretely: the driver identifies
both of the two PCI device IDs it supports as the wrong chipsets (Finding 2); one
of its two log sites passes two arguments to a format string with one conversion
and prints a constant where the stepping value should be (Finding 4); every one of
the reference's nine `__cstring` entries except the class name is absent from our
build and replaced with invented text (baseline parity cross-check above); and its
`Default.table` uses an auto-detect key the loader will not match (Finding 9).
Against that, the function partition, class layout, PCI register numbers, bit
positions, branch structure and message-send order are all correct, and no
function is missing.

Suggested wording, matching the phrasing used for the other reconstructed bus
drivers in the same file:

```
 * Intel824X0PCI - builds; reconstructed against the reference binary, divergences found, fixes not yet applied
```

The README was **not** edited as part of this pass — this is a report, and Task 6
applies the changes.

*Updated by the fix pass:* the fix pass did not edit `src/drivers-i386/README`
either. Ownership of that file moved to the later README task so that all the
reconstructed drivers get one consistent rewording, and because the wording
suggested above ("fixes not yet applied") is now out of date without being
replaceable by "complete" — the fixes are applied but uncompiled and unverified.

## Uncertainty and limits of this pass

- No build was run and no baseline parity of record exists; see the two sections
  at the top. The parity output quoted there is a cross-check against an artifact
  of unproven provenance, and none of the ten findings rests on it.
- `+[Intel824X0 probe:]` carries symbol binding `global` in the reference while
  `-[Intel824X0 initFromDeviceDescription:]` carries `local`. Why the two differ
  was not investigated; it does not affect any finding.

  *Resolved by the fix pass: there is no divergence, and the `global` label is an
  IDA artifact.* Reading the reference's Mach-O symbol table directly, all four
  `__text` symbols — including `+[Intel824X0 probe:]` — have `n_type = 0x0e`,
  that is `N_SECT` with the `N_EXT` bit clear, i.e. local. The reference has 16
  symbols of which exactly 12 are `N_EXT`, and the list is entirely
  `.objc_class_name_*`, `_Intel824X0_VERS_STRING`, `_Intel824X0_VERS_NUM`,
  `_Intel824X0_instance` and the six undefined symbols: `_IOLog`,
  `_objc_msgSend`, `_objc_msgSendSuper`, and the three inherited class-name
  references. No Objective-C method symbol is among them. The same read of our
  staged artifact gives `n_type = 0x0e` for both methods as well, so the two
  binaries **agree**. The `binding: global` on entry 0 comes from
  `analysis-reference-ida.json`, where IDA reports its own name flags for the
  function at address 0 rather than the Mach-O `N_EXT` bit; `binrecon.macho`
  reads the symbol table itself and calls it `local` in both binaries. Nothing
  was changed. Even had the binaries genuinely differed, the binding of an
  Objective-C method label is chosen by the compiler's ObjC emitter, not
  expressible in the method's source text, so it would not have been actionable
  here.
- The reference's `-[Intel824X0 initFromDeviceDescription:]` was read as 149
  instructions across 21 basic blocks, which IDA and Ghidra agree on exactly. No
  instruction in it was left unaccounted for by the findings above, but the
  reconstruction of Apple's original *source text* from that disassembly is an
  inference in places — particularly Finding 8's claim about which value the
  success path returns, which is certain at the machine level and only probable at
  the source level.
