# drvISASerialPort Binary Reconstruction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reconstruct `drvISASerialPort` against Apple's shipped `ISASerialPort_reloc`, splitting our single 5349-line file into the reference's four translation units and inverting its state model, with a committed source map, parity ledger and divergence document.

**Architecture:** A report pass maps all 45 reference functions to our one file and records the divergences; the fix pass then works translation unit by translation unit, smallest first, extracting each into its own file. Every phase leaves the driver linking and relines the source map.

**Tech Stack:** Python 3.12 in `.venv-binrecon`, `tools/binrecon` (angr 9.3.0, jsonschema 4.26.0), IDA Professional 9.2 (`idat.exe`), Objective-C and C for Rhapsody DriverKit, `gnumake` with NeXT `pb_makefiles` inside a Rhapsody DR2 guest.

**Spec:** [2026-07-26-isaserialport-binary-reconstruction-design.md](../specs/2026-07-26-isaserialport-binary-reconstruction-design.md)

## Global Constraints

Every task's requirements implicitly include this section.

- **Never commit reference binaries, rebuilt artifacts, or analyzer output.** `tools/binrecon/out/` and `out/` are both gitignored. Rebuilt `_reloc` files stage to `out/i386/` and stay untracked.
- **Run all `binrecon` commands from the repository root `D:\RhapsodiOS`** with `PYTHONPATH=tools/binrecon`. Analyzer executable paths in profiles are resolved by the host process, so a different cwd breaks them.
- **Python is `./.venv-binrecon/Scripts/python.exe`.** Not `python`, not `py`.
- **`BINRECON_REFERENCE` must be exported** in any shell running `binrecon validate`, `analyze`, `source-map` or `ledger`:
  `C:\Users\raynorpat\Downloads\test\Drivers\i386\ISASerialPort.config\ISASerialPort_reloc`
- **The reference binary is read-only.** Never modify it.
- **Reference identity:** 67328 bytes, SHA-256 `4CAA1BB9E8CE3309560F14E352F3D68902EA1C59937DC84DBB5EBCDA330EA932`. Every committed `source-map.json` and `ledger.json` must carry that SHA-256; `load_source_map` enforces it.
- **`"Driver Version"` is out of every comparison.** It is emitted by Apple's build.
- **Evidence is IDA + angr only.** Ghidra aborts on this binary with `Ghidra relocation operand metadata is ambiguous` (`normalize.py:432`), leaving `complete: false`. Its profile sets `analyzers.ghidra.enabled: false`. **Do not re-enable it**, and expect no `analysis-reference-ghidra.json`.
- **`binrecon analyze` exits 1 here, and that is success.** Reference-only profiles can never satisfy `normalized-functions` acceptance, which compares a reference against a *rebuilt* artifact. The gate is `complete: true` plus a reference consensus, never the exit code. Piping the command through `tail` makes `$?` report the pipe's last stage — redirect to a file if you need the exit code.
- **Resolve every constant to its definition, never to the comment beside it.** Our source's inline comments have been wrong four times in the sibling effort: an `IODelay(30)` whose comment claimed 30 ms while the code delayed 30 µs, and a set of `IO_R_*` names whose comments disagreed with `src/driverkit-3/driverkit/return.h`. This driver's `__udivdi3` comments are another instance.
- **`parity_check.py` compares symbol NAMES only.** A `static`-versus-`external` change is invisible to it. Verify linkage by reading the rebuilt nlist with `binrecon.macho.read_macho`, checking each symbol's `binding` and `section`.
- **Never claim a ledger status stronger than the work performed.** `assembly-matched` means the rebuilt instruction stream was read against the reference. `control-flow-confirmed` means block shape and call targets were checked but not every instruction. A diverging function stays `unexamined` with a `divergences.md` entry. Reviewers spot-check this against the binary, and three passes in the sibling effort were caught overstating it.
- **Commit messages** start with `drvISASerialPort: ` or `drivers-i386: `, run one to two lines, and describe what the change does rather than listing files. **No metadata, no `Co-Authored-By`, no "Generated with" trailer.**
- **Do not touch** `src/kernel-7/**`, any other driver, any binrecon tooling, or `vm/build-i386-input-drivers.sh` (which belongs to a different effort — this one uses `vm/build-i386-input-recon.sh`).
- **Other sessions commit to this branch concurrently** and have several times swept staged changes into their own commits. Stage and commit promptly; if unrelated changes appear mid-work, leave them alone.

### The reference function partition

45 functions. Sizes are gaps between consecutive symbol addresses, with the last bounded by `__text` size 24412. **IDA's function extents run 1-3 bytes shorter** because the linker pads with `nop`; that is normal and is not an analyzer disagreement. `load_source_map` checks against the IDA analysis, so use this table to *identify* functions, not to assert sizes.

| Addr | Size | Symbol | Linkage | TU |
| --- | --- | --- | --- | --- |
| 0 | 200 | `_RX_enqueueLongEvent` | local | 1 |
| 200 | 64 | `+[ISASerialPort probe:]` | local | 1 |
| 264 | 2276 | `-[ISASerialPort initFromDeviceDescription:]` | local | 1 |
| 2540 | 236 | `-[ISASerialPort free]` | local | 1 |
| 2776 | 64 | `-[ISASerialPort getHandler:level:argument:forInterrupt:]` | local | 1 |
| 2840 | 172 | `-[ISASerialPort getCharValues:forParameter:count:]` | local | 1 |
| 3012 | 1144 | `_activatePort` | local | 1 |
| 4156 | 348 | `_deactivatePort` | local | 1 |
| 4504 | 944 | `-[ISASerialPort acquire:]` | local | 1 |
| 5448 | 564 | `-[ISASerialPort release]` | local | 1 |
| 6012 | 268 | `-[ISASerialPort setState:mask:]` | local | 1 |
| 6280 | 20 | `-[ISASerialPort getState]` | local | 1 |
| 6300 | 100 | `-[ISASerialPort watchState:mask:]` | local | 1 |
| 6400 | 72 | `-[ISASerialPort nextEvent]` | local | 1 |
| 6472 | 868 | `-[ISASerialPort executeEvent:data:]` | local | 1 |
| 7340 | 748 | `-[ISASerialPort requestEvent:data:]` | local | 1 |
| 8088 | 120 | `-[ISASerialPort enqueueEvent:data:sleep:]` | local | 1 |
| 8208 | 120 | `-[ISASerialPort dequeueEvent:data:sleep:]` | local | 1 |
| 8328 | 696 | `-[ISASerialPort enqueueData:bufferSize:transferCount:sleep:]` | local | 1 |
| 9024 | 384 | `-[ISASerialPort dequeueData:bufferSize:transferCount:minCount:]` | local | 1 |
| 9408 | 680 | `_dataLatTOHandler` | local | 1 |
| 10088 | 60 | `_frameTOHandler` | local | 1 |
| 10148 | 60 | `_delayTOHandler` | local | 1 |
| 10208 | 124 | `_heartBeatTOHandler` | local | 1 |
| 10332 | 24 | `_PCMCIA_yanked` | local | 1 |
| 10356 | 2704 | `_executeEvent` | local | 1 |
| 13060 | 3172 | `_FIFOIntHandler` | local | 1 |
| 16232 | 2472 | `_NonFIFOIntHandler` | local | 1 |
| 18704 | 684 | `_identifyChip` | **external** | 2 |
| 19388 | 148 | `_initChip` | **external** | 2 |
| 19536 | 1148 | `_programChip` | **external** | 2 |
| 20684 | 200 | `_RX_enqueueLongEvent` | local | 3 |
| 20884 | 516 | `_TX_enqueueEvent` | **external** | 3 |
| 21400 | 852 | `_RX_dequeueEvent` | **external** | 3 |
| 22252 | 680 | `_RX_dequeueData` | **external** | 3 |
| 22932 | 44 | `_validateRingBufferSize` | **external** | 3 |
| 22976 | 92 | `_freeRingBuffer` | **external** | 3 |
| 23068 | 132 | `_allocateRingBuffer` | **external** | 3 |
| 23200 | 200 | `_RX_enqueueLongEvent` | local | 4 |
| 23400 | 184 | `_flowMachine` | **external** | 4 |
| 23584 | 192 | `_watchState` | **external** | 4 |
| 23776 | 12 | `+[ISASerialPortKernelServerInstance kernelServerInstance]` | local | glue |
| 23788 | 12 | `+[ISASerialPortVersion driverKitVersionForISASerialPort]` | local | glue |
| 23800 | 264 | `__udivdi3` | local | libgcc |
| 24064 | 348 | `__umoddi3` | local | libgcc |

`_RX_enqueueLongEvent` appears three times: it is a `static` defined in a shared header and emitted in TUs 1, 3 and 4. It is **not** in TU 2. The 11 `external` symbols are exactly TUs 2-4's functions and are what `ISASerialPortInternal.h` must declare.

### Where our source stands

`src/drivers-i386/input/drvISASerialPort/ISASerialPort.drvproj/ISASerialPort.lksproj/`:

- `ISASerialPort.m` — 5349 lines, holds everything
- `ISASerialPort.h` — 321 lines
- `Makefile` — `CLASSES = ISASerialPort.m` (line 16), `HFILES = ISASerialPort.h` (18), `OTHERSRCS = Load_Commands.sect Makefile Makefile.preamble` (20)
- `Load_Commands.sect` — **163 bytes; must be 164**

All 22 of our C functions are `static` with a leading underscore, and all take an explicit `ISASerialPort *self` first parameter — a decompiler artifact of methods rendered as functions. Definition lines in the current file:

| Line | Definition |
| --- | --- |
| 147 | `static unsigned int _validateRingBufferSize(unsigned int requestedSize, ISASerialPort *self)` |
| 176 | `static void _freeRingBuffer(void *queueBase)` |
| 215 | `static void _frameTOHandler(thread_call_spec_t spec, thread_call_t call)` |
| 245 | `static void _delayTOHandler(thread_call_spec_t spec, thread_call_t call)` |
| 274 | `static void _dataLatTOHandler(ISASerialPort *self)` |
| 455 | `static unsigned int _flowMachine(ISASerialPort *self)` |
| 525 | `static IOReturn _watchState(ISASerialPort *self, unsigned int *state, unsigned int mask)` |
| 601 | `static unsigned int _identifyChip(ISASerialPort *self)` |
| 733 | `static IOReturn _initChip(ISASerialPort *self)` |
| 769 | `static IOReturn _programChip(ISASerialPort *self)` |
| 959 | `static void _PCMCIA_yanked(ISASerialPort *self)` |
| 976 | `static IOReturn _activatePort(ISASerialPort *self)` |
| 1258 | `static IOReturn _deactivatePort(ISASerialPort *self)` |
| 1379 | `static IOReturn _allocateRingBuffer(void *queueBase, ISASerialPort *self)` |
| 1452 | `static IOReturn _RX_dequeueEvent(ISASerialPort *self, unsigned char *eventType, unsigned int *eventData, BOOL sleep)` |
| 1658 | `static IOReturn _RX_enqueueLongEvent(ISASerialPort *self, unsigned int event, unsigned int data)` |
| 1715 | `static IOReturn _TX_enqueueEvent(ISASerialPort *self, unsigned int event, unsigned int data, BOOL sleep)` |
| 1859 | `static IOReturn _RX_dequeueData(ISASerialPort *self, unsigned char *byteOut, BOOL sleep)` |
| 2040 | `static void _heartBeatTOHandler(thread_call_spec_t spec, thread_call_t call)` |
| 2083 | `static void _NonFIFOIntHandler(void *identity, void *state, ISASerialPort *self)` |
| 2582 | `static void _FIFOIntHandler(void *identity, void *state, ISASerialPort *self)` |
| 3201 | `static void _executeEvent(ISASerialPort *self, unsigned char eventType, ...)` |

Line numbers shift as soon as any task edits the file. Use them to *find* definitions, then re-derive.

### Current parity, measured before any work

| Section | Reference | Ours |
| --- | --- | --- |
| `__TEXT,__text` | 24412 | 24980 |
| `__TEXT,__cstring` | 742 | 649 |
| `__TEXT,__const` | 682 | 196 |
| `__DATA,__data` | 196 | 36 |
| `__OBJC,__class` | 120 | 120 |
| `__OBJC,__instance_vars` | **28** | **820** |
| `Loaded Server,Load Commands` | 164 | 163 |

Sections matching by size: **16 of 30**. `parity_check.py` reports 29 missing strings and 24 missing symbols.

### Standard fix-pass verification

Tasks 3, 4, 5 and 6 all end with these five checks. Run them in order.

**1. Build.** Sync only this driver's directory — never all of `src/`, and never `vm/rhap-vm.ps1 sync`, which would upload other sessions' uncommitted work to the shared guest:

```bash
cd /d/RhapsodiOS
PW=$(grep -i '^Password=' vm/vm.conf | cut -d= -f2)
HOST=$(grep -i '^Host=' vm/vm.conf | cut -d= -f2)
"/c/Program Files/PuTTY/pscp.exe" -batch -r -pw "$PW" \
  src/drivers-i386/input/drvISASerialPort root@$HOST:/build/source/src/drivers-i386/input/
"/c/Program Files/PuTTY/pscp.exe" -batch -pw "$PW" \
  vm/build-i386-input-recon.sh root@$HOST:/build/source/vm/
"/c/Program Files/PuTTY/plink.exe" -batch -pw "$PW" root@$HOST \
  'tr -d "\r" < /build/source/vm/build-i386-input-recon.sh > /tmp/br && mv /tmp/br /build/source/vm/build-i386-input-recon.sh; sh /build/source/vm/build-i386-input-recon.sh drvISASerialPort' > /tmp/isa.log 2>&1
echo "EXIT=$?"
tail -3 /tmp/isa.log
```

If the guest is unreachable, Tasks 3-6 cannot be verified. Do **not** proceed as though they were: report which of the five checks went unrun and stop. Task 1's scaffolding and Task 2's report pass do not need the guest and deliver regardless.

The guest's root shell is `tcsh` and `/bin/sh` is a 1999 Bourne shell: **no `2>&1` and no nested double quotes inside the remote command string** — redirect on the local side as shown.

Expected: `EXIT=0` and a final line `=== input-recon done fail=0 built: drvISASerialPort ===`.

**2. Retrieve and check parity.**

```bash
mkdir -p out/i386/drvISASerialPort/ISASerialPort.config
"/c/Program Files/PuTTY/pscp.exe" -batch -pw "$PW" \
  root@$HOST:/build/out/i386/drvISASerialPort/ISASerialPort.config/ISASerialPort_reloc \
  out/i386/drvISASerialPort/ISASerialPort.config/
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe tools/binrecon/parity_check.py \
  "$BINRECON_REFERENCE" out/i386/drvISASerialPort/ISASerialPort.config/ISASerialPort_reloc
```

It exits 1 when either `missing_` list is non-empty — information, not a crash. Our build is unstripped, so `extra_symbols` and a `_reloc` larger than 67328 bytes are expected and are **not** findings. `missing_strings` and `missing_symbols` must fall relative to the previous phase.

**3. Linkage.** `parity_check.py` cannot see linkage, so read the nlist:

```bash
./.venv-binrecon/Scripts/python.exe -c "
import sys; from pathlib import Path
sys.path.insert(0,'tools/binrecon')
from binrecon.macho import read_macho
ref  = read_macho(Path(r'C:\Users\raynorpat\Downloads\test\Drivers\i386\ISASerialPort.config\ISASerialPort_reloc'))
ours = read_macho(Path('out/i386/drvISASerialPort/ISASerialPort.config/ISASerialPort_reloc'))
def ext(d): return {s['name'] for s in d['symbols'] if s['binding']=='external' and s['section']=='__TEXT,__text'}
r, o = ext(ref), ext(ours)
print('reference externals:', len(r))
print('ours externals     :', len(o))
print('reference-only     :', sorted(r-o))
print('ours-only          :', sorted(o-r))
"
```

The reference has 11 externally defined `__text` symbols. As each TU is extracted, `reference-only` shrinks toward empty.

**4. Sections.**

```bash
./.venv-binrecon/Scripts/python.exe -c "
import sys; from pathlib import Path
sys.path.insert(0,'tools/binrecon')
from binrecon.macho import read_macho
ref  = read_macho(Path(r'C:\Users\raynorpat\Downloads\test\Drivers\i386\ISASerialPort.config\ISASerialPort_reloc'))
ours = read_macho(Path('out/i386/drvISASerialPort/ISASerialPort.config/ISASerialPort_reloc'))
r={s['name']:s['size'] for s in ref['sections']}; o={s['name']:s['size'] for s in ours['sections']}
for n in sorted(r):
    mark = '' if o.get(n)==r[n] else '   <-- differs'
    print(f'{n:34} ref={r[n]:<7} ours={o.get(n)}{mark}')
print('match by size:', sum(1 for n in r if n in o and r[n]==o[n]), '/', len(r))
"
```

Record the match count. It starts at 16/30 and must not regress.

**Watch `__OBJC,__module_info` specifically.** It is 32 bytes in both the reference and our build today, and it must stay 32. If it grows, an Objective-C source file was added where a `.c` file belongs — see Task 3 Step 2.

**5. Reline the source map. MANDATORY, and the step most easily forgotten.**

Any edit that adds or removes lines invalidates every `source_line` in `source-map.json` and `ledger.json`. In the sibling effort one fix pass left its map pointing past the end of the file and another left it pinned to an uncommitted tree. Regenerate to scratch, then merge:

```bash
export SCRATCH="C:/Users/RAYNOR~2/AppData/Local/Temp/claude/D--RhapsodiOS/cf8c5065-de19-4760-b109-038e7f5e4bfd/scratchpad"
./.venv-binrecon/Scripts/python.exe -m binrecon source-map \
  --reference-analysis tools/binrecon/out/isaserialport/published/analysis-reference-ida.json \
  --binary "$BINRECON_REFERENCE" \
  --source-dir src/drivers-i386/input/drvISASerialPort/ISASerialPort.drvproj/ISASerialPort.lksproj \
  --repo-root . --output "$SCRATCH/isa-fresh.json"
```

Write it to scratch, **not** over the committed map — the fresh one has no hand-resolved bucket assignments. Then copy `source_line` and `source_path` across by `address` into both `source-map.json` and `ledger.json`, keeping the committed bucket assignments. **If the fresh run's bucket counts differ from the committed map's, stop and report** — the edit changed the function partition and that needs a human look, not an automatic merge.

Confirm:

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -c "
from pathlib import Path
from binrecon.schema import load_json, load_source_map
a = load_json(Path('tools/binrecon/out/isaserialport/published/analysis-reference-ida.json'))
load_source_map(Path('src/drivers-i386/input/drvISASerialPort/reconstruction/source-map.json'),
                reference_analysis=a, repo_root=Path.cwd())
print('source map OK')
"
```

---

### Task 1: Profile and scaffolding

Lands the tooling plus the three fixes that need no disassembly. The packaging fix matters more than it looks: `gnumake` currently exits 2 on a rule unrelated to code, so until it is fixed every later task's "build exits 0" gate is vacuous.

**Files:**
- Create: `tools/binrecon/profiles/isaserialport.json`
- Modify: `vm/build-i386-input-recon.sh` — add a `drvISASerialPort` case
- Modify: `src/drivers-i386/input/drvISASerialPort/ISASerialPort.drvproj/Default.table:1-2`
- Modify: `src/drivers-i386/input/drvISASerialPort/ISASerialPort.drvproj/Makefile:18`
- Modify: `src/drivers-i386/input/drvISASerialPort/ISASerialPort.drvproj/ISASerialPort.lksproj/Load_Commands.sect`

**Interfaces:**
- Consumes: nothing.
- Produces: `tools/binrecon/profiles/isaserialport.json` with `output_dir` `../out/isaserialport`, so analyzer output lands in `tools/binrecon/out/isaserialport`. Also produces a build harness invocable as `sh vm/build-i386-input-recon.sh drvISASerialPort` that exits 0.

- [ ] **Step 1: Write the profile**

`tools/binrecon/profiles/isaserialport.json`. Note `ghidra.enabled` is **false** — see Global Constraints.

```json
{
  "schema_version": "profile-v1",
  "name": "drvISASerialPort reconstruction",
  "architecture": "i386",
  "endianness": "little",
  "reference": {
    "path": "${BINRECON_REFERENCE}"
  },
  "analyzers": {
    "ida": {
      "enabled": true,
      "executable": "C:/Program Files/IDA Professional 9.2/idat.exe",
      "timeout_seconds": 900,
      "version": "9.2"
    },
    "ghidra": {
      "enabled": false,
      "executable": "D:/ghidra/support/analyzeHeadless.bat",
      "timeout_seconds": 900,
      "version": "12.1"
    },
    "angr": {
      "enabled": true,
      "executable": ".venv-binrecon/Scripts/python.exe",
      "timeout_seconds": 900,
      "version": "9.3.0"
    }
  },
  "comparison": {
    "acceptance": "normalized-functions",
    "ignore_metadata": [],
    "entry_points": []
  },
  "output_dir": "../out/isaserialport"
}
```

- [ ] **Step 2: Validate the profile**

```bash
cd /d/RhapsodiOS
export PYTHONPATH=tools/binrecon
export BINRECON_REFERENCE='C:\Users\raynorpat\Downloads\test\Drivers\i386\ISASerialPort.config\ISASerialPort_reloc'
./.venv-binrecon/Scripts/python.exe -m binrecon validate --profile tools/binrecon/profiles/isaserialport.json
```

Expected: the resolved absolute path, size **67328**, and SHA-256 `4CAA1BB9E8CE3309560F14E352F3D68902EA1C59937DC84DBB5EBCDA330EA932`, with no rebuilt artifact. If the SHA-256 differs, **stop** — the reference on disk is not the one this plan was written against.

- [ ] **Step 3: Add the build-script case**

`vm/build-i386-input-recon.sh` dispatches through `case` (a `want()`-style predicate cannot be used: Rhapsody's 1999 Bourne `/bin/sh` applies `set -e` to any function returning nonzero, even from an `if` condition, which killed an earlier version of this script). Add `drvISASerialPort` to the `TARGETS` default list and a new `case` arm:

```sh
	drvISASerialPort)
		build_one ISASerialPort drvISASerialPort ISASerialPort.drvproj || fail=1
		;;
```

The three `build_one` arguments are the reference binary basename, the `drv` directory name, and the `.drvproj` directory name — in that order. For this driver all three stems differ from each other, so transcribe exactly.

- [ ] **Step 4: Check the script still parses**

```bash
sh -n vm/build-i386-input-recon.sh && echo "syntax OK"
```

Expected: `syntax OK`.

- [ ] **Step 5: Add the missing `"Version"` line**

The reference `Default.table` has it on line 2, immediately after `"Title"`. Ours goes from:

```
"Title" = "System Serial";
"Class Names" = "ISASerialPort";
```

to:

```
"Title" = "System Serial";
"Version" = "5.00";
"Class Names" = "ISASerialPort";
```

- [ ] **Step 6: Fix `Load_Commands.sect` from 163 to 164 bytes**

Its first line is `#\n`; the reference has `# \n` with a trailing space. The canonical 164-byte file already exists — copy it rather than retyping, since a trailing space is easy to lose:

```bash
cd /d/RhapsodiOS
cp src/drivers-i386/input/drvPS2Mouse/PS2Mouse.drvproj/PS2Mouse.lksproj/Load_Commands.sect \
   src/drivers-i386/input/drvISASerialPort/ISASerialPort.drvproj/ISASerialPort.lksproj/Load_Commands.sect
wc -c src/drivers-i386/input/drvISASerialPort/ISASerialPort.drvproj/ISASerialPort.lksproj/Load_Commands.sect
```

Expected: `164`.

**Do not create an `Unload_Commands.sect`.** The reference has no `Loaded Server,Unload Commands` section for this driver, unlike four of its five siblings.

- [ ] **Step 7: Fix the packaging rule**

`ISASerialPort.drvproj/Makefile:18` reads `GLOBAL_RESOURCES =`. Set it to `Default.table`, matching `drvBusMouse/BusMouse.drvproj/Makefile:16` and `drvPCParallel/PCParallelPort.drvproj/Makefile:18`:

```make
GLOBAL_RESOURCES = Default.table
```

This is what stops `post_copy_tables` from running `chmod` on a `$(NAME).config/*.table` that does not exist.

- [ ] **Step 8: Build and confirm `gnumake` now exits 0**

Run Standard fix-pass verification check 1. Expected: `EXIT=0` and `=== input-recon done fail=0 built: drvISASerialPort ===`.

Before this task the build linked successfully but `gnumake` exited 2 on the packaging rule. If it still exits non-zero, read `/tmp/isa.log` and report rather than working around it.

- [ ] **Step 9: Confirm the table now matches the reference**

```bash
cd /d/RhapsodiOS
REF='C:/Users/raynorpat/Downloads/test/Drivers/i386/ISASerialPort.config/Default.table'
OURS='src/drivers-i386/input/drvISASerialPort/ISASerialPort.drvproj/Default.table'
diff <(grep -v 'Driver Version' "$REF"  | sed 's/[[:space:]]*$//' | grep -v '^$' | sort) \
     <(grep -v 'Driver Version' "$OURS" | sed 's/[[:space:]]*$//' | grep -v '^$' | sort) \
  && echo "tables identical apart from Driver Version"
```

Expected: `tables identical apart from Driver Version`.

- [ ] **Step 10: Commit**

Two commits — the tooling and the driver scaffolding are independently reviewable.

```bash
git add tools/binrecon/profiles/isaserialport.json vm/build-i386-input-recon.sh
git commit -m "binrecon: add the drvISASerialPort profile and build case

Ghidra is disabled for this driver; its normalization aborts on ambiguous
relocation operand metadata."

git add src/drivers-i386/input/drvISASerialPort/ISASerialPort.drvproj/Default.table \
        src/drivers-i386/input/drvISASerialPort/ISASerialPort.drvproj/Makefile \
        src/drivers-i386/input/drvISASerialPort/ISASerialPort.drvproj/ISASerialPort.lksproj/Load_Commands.sect
git commit -m "drvISASerialPort: fix the table version, load section and packaging rule

Load_Commands.sect was a byte short of the reference's 164, and an empty
GLOBAL_RESOURCES made post_copy_tables fail after a successful link."
```

---

### Task 2: Report pass

Maps all 45 reference functions against our single `ISASerialPort.m`, per the approved approach: the file split is recorded as a finding here and enacted in Tasks 3-6.

**Files:**
- Create: `src/drivers-i386/input/drvISASerialPort/reconstruction/source-map.json`
- Create: `src/drivers-i386/input/drvISASerialPort/reconstruction/ledger.json`
- Create: `src/drivers-i386/input/drvISASerialPort/reconstruction/divergences.md`
- Read: `ISASerialPort.m` (5349 lines), `ISASerialPort.h` (321 lines)

**Interfaces:**
- Consumes: `tools/binrecon/profiles/isaserialport.json` from Task 1.
- Produces: a validated `source-map-v1` with a complete 45-function partition, a `ledger-v1` with 45 entries and `reference_sha256` `4CAA1BB9…`, `rebuilt_sha256` `null`, and a `divergences.md` that Tasks 3-6 work from. Also produces the two decodes those tasks depend on: the `_Chip` table layout and the confirmed TU boundary for every function.

- [ ] **Step 1: Run the analyzers**

```bash
cd /d/RhapsodiOS
export PYTHONPATH=tools/binrecon
export BINRECON_REFERENCE='C:\Users\raynorpat\Downloads\test\Drivers\i386\ISASerialPort.config\ISASerialPort_reloc'
./.venv-binrecon/Scripts/python.exe -m binrecon analyze \
  --profile tools/binrecon/profiles/isaserialport.json \
  --output tools/binrecon/out/isaserialport/run-summary.json > /tmp/isa-an.log 2>&1
echo "EXIT=$?"
tail -2 /tmp/isa-an.log
```

**Expected: `EXIT=1`, and that is success** — see Global Constraints. The last line reads `analysis complete; analyzers=2 comparisons=0 normalized-functions=FAIL`.

- [ ] **Step 2: Verify the real gate**

```bash
./.venv-binrecon/Scripts/python.exe -c "
import json
d = json.load(open('tools/binrecon/out/isaserialport/run-summary.json'))
print(d['complete'], d['reference_sha256'],
      [(a['name'], a['version']) for a in d['analyzers']],
      d['consensus']['reference'] is not None)
"
ls tools/binrecon/out/isaserialport/published/
```

Expected exactly:

```
True 4CAA1BB9E8CE3309560F14E352F3D68902EA1C59937DC84DBB5EBCDA330EA932 [('IDA', '9.2'), ('angr', '9.3.0')] True
```

and three files: `analysis-reference-ida.json`, `analysis-reference-angr.json`, `consensus-reference.json`. There is **no** `analysis-reference-ghidra.json` and the `analyzers` list has **two** entries — both expected. Each entry's keys are `name`, `version`, `reference`, `rebuilt`; there is no `analyzer` key.

- [ ] **Step 3: Generate the source map**

```bash
./.venv-binrecon/Scripts/python.exe -m binrecon source-map \
  --reference-analysis tools/binrecon/out/isaserialport/published/analysis-reference-ida.json \
  --binary "$BINRECON_REFERENCE" \
  --source-dir src/drivers-i386/input/drvISASerialPort/ISASerialPort.drvproj/ISASerialPort.lksproj \
  --repo-root . \
  --output src/drivers-i386/input/drvISASerialPort/reconstruction/source-map.json
```

Create the `reconstruction/` directory first; it does not exist yet. `source_sites` globs `*.m` and `*.c` in `--source-dir` non-recursively, which currently finds only `ISASerialPort.m`.

- [ ] **Step 4: Run the validator to see what it rejects**

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -c "
from pathlib import Path
from binrecon.schema import load_json, load_source_map
a = load_json(Path('tools/binrecon/out/isaserialport/published/analysis-reference-ida.json'))
load_source_map(Path('src/drivers-i386/input/drvISASerialPort/reconstruction/source-map.json'),
                reference_analysis=a, repo_root=Path.cwd())
print('source map OK')
"
```

Expected on the raw generated map: a `SemanticValidationError`, or unplaced entries. The generated map is a starting point, not an answer. Two things need hand resolution: the two glue methods have no source site and belong in `unmapped`, and `_RX_enqueueLongEvent` appears at **three** addresses (0, 20684, 23200) while our source defines it once — decide whether those go in `mapped` (all three to our single definition) or `duplicate_candidates`, and say why in `divergences.md`.

- [ ] **Step 5: Hand-resolve until the validator passes**

Every one of the 45 addresses must land in exactly one bucket — `mapped`, `unmapped`, `boundary_disputed`, `duplicate_candidates` — and entries within a bucket must be sorted by `(address, reference_names)`; `validate_source_map_semantics` rejects any other order. Re-run Step 4 until it prints `source map OK`.

- [ ] **Step 6: Diff every mapped function**

Read the disassembly of each against our source: control-flow shape, literal constants, I/O port addresses **and access directions**, struct field offsets, call targets. Disassembly comes from `tools/binrecon/out/isaserialport/published/analysis-reference-ida.json`, or the `kawaiidra` MCP server (`mcp__kawaiidra__*`, loadable via ToolSearch).

Budget by size, not count. The five largest are `_FIFOIntHandler` (3172), `_executeEvent` (2704), `_NonFIFOIntHandler` (2472), `-[ISASerialPort initFromDeviceDescription:]` (2276) and `_programChip` (1148) — together 11.8 KB of the 24.4 KB total.

- [ ] **Step 7: Decode the `_Chip` table field by field**

All 180 bytes at `__DATA,__data`. Task 5 writes `identifyChip` from this decode, so a gap here becomes an invention there. Record the entry stride, what each field holds, and which of the twelve part names each entry selects:

```
82510, ST16C650, 16650, 16C1550, 16550AF/C/CF, 16550,
16550 with defective FIFO, 16C1450, 8250A or 16450, 16450, 8250, Unknown
```

Also decode `_msr_state_lut` (16 bytes at `__DATA,__data`).

- [ ] **Step 8: Decode the 11 exported functions' parameter types from the disassembly**

**Our source's signatures for these are decompiler artifacts and cannot be trusted.** Every one takes an explicit `ISASerialPort *self` first parameter, which is how a decompiler renders a method — but these are C functions in the reference and their real parameter lists are only visible in what the callers push and what each callee reads off its stack frame.

For each of the 11, record: the number of arguments, each one's width and how the callee uses it, and the return type. In particular establish **whether any of them takes an `ISASerialPort *` at all.** After Step 9's ivar inversion they will be reading file-scope statics rather than instance variables, so a `self` parameter may be pure decompiler residue.

This matters beyond correctness — see the `.c`-versus-`.m` constraint in Task 3 Step 2. A function that genuinely needs the `@interface` cannot live in a `.c` file, and a `.m` file would break a section that currently matches.

- [ ] **Step 9: Confirm every TU boundary from the disassembly**

The Global Constraints table assigns each function to a TU from symbol addresses plus the repeated-static evidence. That is a strong prior, not proof. Confirm each of the four boundaries — 18704, 20684, 23200, 23776 — and record any function the disassembly places on the other side. A misplaced function shifts every later address.

- [ ] **Step 10: Decode the reference's 28 bytes of ivars**

`__OBJC,__instance_vars` is 28 bytes against our 820. Record each field the reference keeps as an instance variable, with its name, type encoding and offset. Task 3 inverts everything else to file-scope statics, and it must be driven by this decode rather than by which fields our C functions happen to touch — the interrupt handlers run at raised IPL and a misclassified field is a fault no static check catches.

- [ ] **Step 11: Compare the table**

Diff `Default.table` against the reference, ignoring `"Driver Version"`. After Task 1 this must be clean; a residual difference is a Task 1 defect and must be said so.

- [ ] **Step 12: Write `divergences.md`**

Follow `src/drivers-i386/input/drvPCParallel/reconstruction/divergences.md`, the most recent approved example at comparable scale. Header naming the reference and SHA-256 and the analyzer versions; a baseline-build note; a bucket-count summary; a statement of how many functions were examined at which depth; an unmapped/build-generated section; an analyzer-disagreement section comparing **IDA against angr only**; then numbered findings, each with source path and line, reference disassembly, and our source side by side.

Five things this document must state explicitly:

1. **The reduced analyzer set** is a stated limitation of this driver's evidence.
2. **Task 3-6 must verify linkage by reading the rebuilt nlist**, not by `parity_check.py` counts, which are name-only.
3. **The four-TU split**, with address ranges, and that `ISASerialPort.m` is the only filename recorded in the binary. `__OBJC,__module_info` names exactly two modules — `ISASerialPort.m` and the build-generated `ISASerialPort_instance.m`. `ISASerialPortChip.c`, `ISASerialPortQueue.c` and `ISASerialPortFlow.c` are **our names, not Apple's**; say so, or a later reader will take them for recovered facts.
4. **The class conforms to a `PortDevices` protocol**, per `__OBJC,__class_names`.
5. **The `__udivdi3`/`__umoddi3` call sites are a decompiler artifact.** Our source declares them as four-argument functions and calls them explicitly; gcc emits those calls implicitly from ordinary `unsigned long long` division. The helpers themselves stay, because `/usr/lib/libcc.a` on the guest is a PPC archive that cannot load for `-arch i386`, so `___clz_tab` stays absent and `__TEXT,__const` remains near 196 against 682 — a recorded environment limitation.

- [ ] **Step 13: Write `ledger.json`**

`schema_version` `ledger-v1`, `reference_sha256` `4CAA1BB9E8CE3309560F14E352F3D68902EA1C59937DC84DBB5EBCDA330EA932`, `rebuilt_sha256` `null`. One entry per reference function — 45 — each with `address`, `names`, `size`, `source_path`, `source_line`, `status`, `reason`, `reviewer`, `artifacts` and `analyzer_agreement` (`{analyzers, reasons, status}`), where `analyzers` is `["IDA","angr"]`. The two glue methods get `intentional-mismatch` with a reason naming the Kernel Server project type and a reviewer.

Verify it loads:

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe -m binrecon ledger \
  --profile tools/binrecon/profiles/isaserialport.json \
  --ledger src/drivers-i386/input/drvISASerialPort/reconstruction/ledger.json
```

Expected: 45 entries and `reference_sha256` matching. `binrecon ledger` resolves the profile's reference artifact, so `BINRECON_REFERENCE` must still be exported.

- [ ] **Step 14: Re-run the validator as a final gate**

Step 4's command. Expected: `source map OK`.

- [ ] **Step 15: Commit**

```bash
git add src/drivers-i386/input/drvISASerialPort/reconstruction/source-map.json
git commit -m "drvISASerialPort: map the driver against the reference binary"

git add src/drivers-i386/input/drvISASerialPort/reconstruction/ledger.json \
        src/drivers-i386/input/drvISASerialPort/reconstruction/divergences.md
git commit -m "drvISASerialPort: record the parity ledger and divergences"
```

---

### Task 3: TU 4 and the structural foundation

The smallest translation unit — 576 bytes, two functions — but it carries the change everything else depends on. An exported C function in another translation unit cannot dereference an Objective-C instance variable, so the ivar-to-static inversion is what makes any extraction possible, and it lands here.

**Files:**
- Create: `.../ISASerialPort.lksproj/ISASerialPortInternal.h`
- Create: `.../ISASerialPort.lksproj/ISASerialPortFlow.c`
- Modify: `.../ISASerialPort.lksproj/ISASerialPort.m`, `ISASerialPort.h`
- Modify: `.../ISASerialPort.lksproj/Makefile:16-20`
- Modify: `src/drivers-i386/input/drvISASerialPort/reconstruction/{ledger.json,divergences.md,source-map.json}`

**Interfaces:**
- Consumes: Task 2's `divergences.md` — specifically its Step 9 ivar decode and Step 8 boundary confirmation — and its `ledger.json`.
- Produces: `ISASerialPortInternal.h`, declaring all **11** functions the reference exports plus the file-scope state they share, and `ISASerialPortFlow.c` defining `flowMachine` and `watchState` with `external` linkage. Tasks 4, 5 and 6 add their definitions to that header's declarations without changing it.

- [ ] **Step 1: Baseline build and parity**

Standard fix-pass verification checks 1 through 4, before any edit. Record all four results — the parity counts, the externals comparison and the section match count are the numbers later steps are measured against. Expect `missing_strings` 29, `missing_symbols` 24, sections 16/30, and **0** of the reference's 11 externals present.

- [ ] **Step 2: Create `ISASerialPortInternal.h`**

It declares the cross-TU interface. Drop the leading underscore from each name, because the reference's symbols are `_flowMachine` and so on, which is what a C function named `flowMachine` compiles to.

**Take the parameter lists from Task 2's Step 8 decode, not from our current definitions.** Our source gives every one of these an `ISASerialPort *self` first parameter, which is a decompiler artifact of a method rendered as a function. The real signatures come from what the reference's callers push.

**Why `.c` and not `.m`, and why that forces an order.** Our build's `__OBJC,__module_info` is **32 bytes / 2 modules — already exactly matching the reference**, because `ISASerialPort.m` plus the generated `ISASerialPort_instance.m` are the only Objective-C modules. Adding `.m` files would make it 3, 4 and 5 modules and **break a section that currently matches**. So TUs 2-4 must be `.c`.

But a `.c` file compiled without Objective-C cannot parse `@interface`, so it cannot dereference `self->currentState` the way our `_flowMachine` does today. That is precisely why Step 3's ivar inversion comes **before** Step 4's extraction rather than after: once driver state lives in file-scope storage, these functions need no `@interface` and `.c` becomes possible.

If Step 8's decode shows a function genuinely requires an `ISASerialPort *` — for a message send, not an ivar read — then it cannot be a `.c` file. Stop and report rather than forcing it: the choice is then between breaking `__module_info` parity and misplacing the function, and that is a judgement call for a human.

The header below assumes the decode confirms no `@interface` dependency survives the inversion. Adjust its signatures to match the decode; the names and the count of 11 are fixed by the reference.

The header declares all 11 exported functions up front even though Tasks 4-6 supply eight of them, so it is written once and never revised:

The skeleton below carries our current parameter lists as a starting point. **Replace each with what Step 8's decode establishes** before writing the file:

```c
/*
 * ISASerialPortInternal.h - state and entry points shared between the
 * driver's four translation units.
 *
 * The reference binary exports exactly these 11 symbols from __TEXT,__text.
 * Everything else in the driver is local to its translation unit.
 *
 * These are plain C, compiled without Objective-C, so nothing here may
 * depend on the @interface. Shared driver state is declared extern below
 * and defined once, without static, in ISASerialPort.m.
 */

#ifndef _ISASERIALPORTINTERNAL_H_
#define _ISASERIALPORTINTERNAL_H_

#import "ISASerialPort.h"

/* ISASerialPortChip.c */
extern unsigned int identifyChip(ISASerialPort *self);
extern IOReturn initChip(ISASerialPort *self);
extern IOReturn programChip(ISASerialPort *self);

/* ISASerialPortQueue.c */
extern IOReturn TX_enqueueEvent(ISASerialPort *self, unsigned int event,
                                unsigned int data, BOOL sleep);
extern IOReturn RX_dequeueEvent(ISASerialPort *self, unsigned char *eventType,
                                unsigned int *eventData, BOOL sleep);
extern IOReturn RX_dequeueData(ISASerialPort *self, unsigned char *byteOut,
                               BOOL sleep);
extern unsigned int validateRingBufferSize(unsigned int requestedSize,
                                           ISASerialPort *self);
extern void freeRingBuffer(void *queueBase);
extern IOReturn allocateRingBuffer(void *queueBase, ISASerialPort *self);

/* ISASerialPortFlow.c */
extern unsigned int flowMachine(ISASerialPort *self);
extern IOReturn watchState(ISASerialPort *self, unsigned int *state,
                           unsigned int mask);

#endif /* _ISASERIALPORTINTERNAL_H_ */
```

Then add the file-scope state declarations the Step 9 decode says are shared. Declare them `extern` here and define them once, without `static`, in `ISASerialPort.m` — a non-static tentative definition, the pattern `_keyboardQueueElements` uses in drvPS2Keyboard. Writing `static` in the header would give each TU its own private copy and silently break the driver.

- [ ] **Step 3: Invert the state model**

Move every field Task 2's Step 9 decode does **not** list among the reference's 28 bytes out of `@interface ISASerialPort` and into file-scope storage. The reference keeps `_Chip` (180 bytes) and `_msr_state_lut` (16) in `__DATA,__data` plus four `_xxx.NN` sets in `__DATA,__bss`.

Two rules:
- **Follow the decode, not convenience.** The interrupt handlers `_FIFOIntHandler` and `_NonFIFOIntHandler` run at raised IPL and read this state.
- **State the exported C functions must reach goes in the header as `extern`**, defined once without `static` in `ISASerialPort.m`. State only `ISASerialPort.m` uses becomes `static` there.

Target: `__OBJC,__instance_vars` at **28 bytes**. Check it after the build with verification check 4.

- [ ] **Step 4: Extract `flowMachine` and `watchState`**

Create `ISASerialPortFlow.c` holding both, moved verbatim from `ISASerialPort.m` apart from three changes: drop `static`, drop the leading underscore from the name, and `#import "ISASerialPortInternal.h"`. Delete both definitions from `ISASerialPort.m` and update its call sites to the un-underscored names.

Our current definitions are at `ISASerialPort.m:455` (`_flowMachine`) and `:525` (`_watchState`) — re-derive those line numbers, since Step 3 will already have moved them.

`.c` not `.m`: these hold no Objective-C.

Note the reference also emits a `static _RX_enqueueLongEvent` copy in this TU (address 23200). That comes from the shared header, so if Task 2 established it belongs there, declare it `static` in `ISASerialPortInternal.h` and let each TU that references it emit its own copy.

- [ ] **Step 5: Wire the Makefile**

`ISASerialPort.lksproj/Makefile` currently has `CLASSES = ISASerialPort.m` (line 16), `HFILES = ISASerialPort.h` (18) and `OTHERSRCS = Load_Commands.sect Makefile Makefile.preamble` (20). C sources go in `CFILES`, not `CLASSES`:

```make
CLASSES = ISASerialPort.m

CFILES = ISASerialPortFlow.c

HFILES = ISASerialPort.h ISASerialPortInternal.h
```

Leave `OTHERSRCS`, `PUBLIC_HEADERS` and `NEXTSTEP_PB_CFLAGS` alone.

- [ ] **Step 6: Build and verify**

Standard fix-pass verification checks 1 through 4. Expected: `EXIT=0`; `flowMachine` and `watchState` now present in the externals comparison, so `reference-only` drops from 11 to 9; `__OBJC,__instance_vars` at or near 28; section match count above 16/30.

If `EXIT` is non-zero, the most likely cause is state a moved function can no longer reach. Read `/tmp/isa.log`.

- [ ] **Step 7: Reline the source map**

Standard fix-pass verification check 5. Expected: `source map OK`. The bucket counts must match the committed map; the extraction moved code between files, so `source_path` changes for two functions — that is expected and is exactly what the merge handles.

- [ ] **Step 8: Resolve the ledger entries and update `divergences.md`**

Advance the entries for `flowMachine` (23400) and `watchState` (23584), plus every entry the ivar inversion touched, to the status the new evidence supports. Add a resolution line per finding. Any accepted divergence becomes `intentional-mismatch` with both a reason and `--reviewer 'Pat Raynor'` — the CLI rejects one without the other, and an entry already in that state must have its reason corrected by direct JSON edit, then revalidated.

- [ ] **Step 9: Commit**

```bash
git add src/drivers-i386/input/drvISASerialPort/ISASerialPort.drvproj/ISASerialPort.lksproj/
git commit -m "drvISASerialPort: move driver state to file scope and split out flow control

The reference exports 11 C functions that cannot reach instance variables, so
the state model inverts before any translation unit can be extracted."

git add src/drivers-i386/input/drvISASerialPort/reconstruction/
git commit -m "drvISASerialPort: advance the ledger after the flow-control split"
```

---

### Task 4: TU 3, the ring buffer

Six functions, 2516 bytes, all exported. The largest of the three small units and self-contained: it owns the RX and TX ring buffers.

**Files:**
- Create: `.../ISASerialPort.lksproj/ISASerialPortQueue.c`
- Modify: `.../ISASerialPort.lksproj/ISASerialPort.m`, `Makefile`
- Modify: `src/drivers-i386/input/drvISASerialPort/reconstruction/{ledger.json,divergences.md,source-map.json}`

**Interfaces:**
- Consumes: `ISASerialPortInternal.h` from Task 3, which already declares all six of these functions — do **not** modify the header's declarations. Also consumes Task 2's `divergences.md`.
- Produces: `ISASerialPortQueue.c` defining `TX_enqueueEvent`, `RX_dequeueEvent`, `RX_dequeueData`, `validateRingBufferSize`, `freeRingBuffer` and `allocateRingBuffer` with `external` linkage, so `reference-only` externals drop from 9 to 3.

- [ ] **Step 1: Baseline**

Standard fix-pass verification checks 1 through 4. Record the four results — this is Task 3's end state and Task 4 is measured against it.

- [ ] **Step 2: Extract the six functions**

Create `ISASerialPortQueue.c` holding all six, moved verbatim apart from: drop `static`, drop the leading underscore, and `#import "ISASerialPortInternal.h"`. Our definitions are currently at `ISASerialPort.m` lines 147 (`_validateRingBufferSize`), 176 (`_freeRingBuffer`), 1379 (`_allocateRingBuffer`), 1452 (`_RX_dequeueEvent`), 1715 (`_TX_enqueueEvent`) and 1859 (`_RX_dequeueData`) — re-derive, since Task 3 shifted them.

Order them as the reference does, so link order matches: `TX_enqueueEvent` (20884), `RX_dequeueEvent` (21400), `RX_dequeueData` (22252), `validateRingBufferSize` (22932), `freeRingBuffer` (22976), `allocateRingBuffer` (23068). The reference also emits its `static _RX_enqueueLongEvent` copy at 20684, ahead of all six.

Delete the six definitions from `ISASerialPort.m` and update its call sites to the un-underscored names. Their signatures are already in `ISASerialPortInternal.h`; if a signature disagrees with what the moved code needs, the header is right and the call site is wrong — the header was derived from the reference.

- [ ] **Step 3: Wire the Makefile**

```make
CFILES = ISASerialPortFlow.c ISASerialPortQueue.c
```

- [ ] **Step 4: Build and verify**

Standard fix-pass verification checks 1 through 4. Expected: `EXIT=0`; `reference-only` externals down to 3 (`identifyChip`, `initChip`, `programChip`); section match count not regressed.

- [ ] **Step 5: Reline the source map**

Standard fix-pass verification check 5. Expected: `source map OK`.

- [ ] **Step 6: Resolve the ledger entries and update `divergences.md`**

Advance the six entries at 20884, 21400, 22252, 22932, 22976 and 23068, plus 20684 if Task 2 mapped that `_RX_enqueueLongEvent` copy here. A resolution line per finding.

- [ ] **Step 7: Commit**

```bash
git add src/drivers-i386/input/drvISASerialPort/ISASerialPort.drvproj/ISASerialPort.lksproj/
git commit -m "drvISASerialPort: split the ring buffer into its own translation unit

Six exported functions matching the reference's third object, in its link order."

git add src/drivers-i386/input/drvISASerialPort/reconstruction/
git commit -m "drvISASerialPort: advance the ledger after the ring buffer split"
```

---

### Task 5: TU 2, chip identification

Three functions, 1980 bytes — and the chip table, which is the one piece of this driver that has to be written rather than moved.

**Files:**
- Create: `.../ISASerialPort.lksproj/ISASerialPortChip.c`
- Modify: `.../ISASerialPort.lksproj/ISASerialPort.m`, `Makefile`
- Modify: `src/drivers-i386/input/drvISASerialPort/reconstruction/{ledger.json,divergences.md,source-map.json}`

**Interfaces:**
- Consumes: `ISASerialPortInternal.h` from Task 3, which already declares `identifyChip`, `initChip` and `programChip` — do **not** modify its declarations. Also consumes Task 2's Step 7 `_Chip` table decode.
- Produces: `ISASerialPortChip.c` defining all three with `external` linkage, and the `_Chip` table in `__DATA,__data`, so `reference-only` externals reach **0** and `__DATA,__data` moves toward the reference's 196 bytes.

- [ ] **Step 1: Baseline**

Standard fix-pass verification checks 1 through 4. Record the four results.

- [ ] **Step 2: Write the `_Chip` table**

From Task 2's Step 7 decode. It is 180 bytes in `__DATA,__data` and selects among the reference's twelve part names:

```
82510, ST16C650, 16650, 16C1550, 16550AF/C/CF, 16550,
16550 with defective FIFO, 16C1450, 8250A or 16450, 16450, 8250, Unknown
```

Our source currently names four invented parts — `16550A`, `16750`, `16950`, `16550?` — which have no counterpart in the reference. They go.

Define it without `static` if the decode shows the reference exports `_Chip`; the symbol table is the authority. Also write `_msr_state_lut` (16 bytes) from the same decode.

If the Step 7 decode is incomplete — if it does not pin down the stride or a field's meaning — **stop and say so** rather than inventing a layout. That is the single highest-risk guess available in this task.

- [ ] **Step 3: Extract and rewrite the three functions**

Create `ISASerialPortChip.c` with `identifyChip` (currently `ISASerialPort.m:601`), `initChip` (`:733`) and `programChip` (`:769`), in the reference's order: `identifyChip` (18704), `initChip` (19388), `programChip` (19536). Re-derive the line numbers.

`initChip` and `programChip` move, with `static` and the leading underscore dropped. **`identifyChip` is rewritten** against the reference disassembly and the `_Chip` table — it is 684 bytes in the reference, and our version detects a different set of parts.

Note this TU is the one that does **not** get a `_RX_enqueueLongEvent` copy; the reference has none between 18704 and 20684.

- [ ] **Step 4: Wire the Makefile**

```make
CFILES = ISASerialPortFlow.c ISASerialPortQueue.c ISASerialPortChip.c
```

- [ ] **Step 5: Build and verify**

Standard fix-pass verification checks 1 through 4. Expected: `EXIT=0`; `reference-only` externals **0** and `ours-only` empty or explained; `__DATA,__data` at or near 196; `missing_strings` down by the eight chip names plus `Auto`.

- [ ] **Step 6: Check `identifyChip` against the reference size**

The overfit guard. `identifyChip` is 684 bytes in the reference; materially larger means structure was invented rather than reconstructed:

```bash
cd /d/RhapsodiOS
./.venv-binrecon/Scripts/python.exe -c "
import sys; from pathlib import Path
sys.path.insert(0,'tools/binrecon')
from binrecon.macho import read_macho
d = read_macho(Path('out/i386/drvISASerialPort/ISASerialPort.config/ISASerialPort_reloc'))
t = next(s for s in d['sections'] if s['name']=='__TEXT,__text')
end = t['address'] + t['size']
sy = sorted({(s['address'], s['name']) for s in d['symbols']
             if s['section']=='__TEXT,__text' and s['name'].startswith('_')})
for i,(a,n) in enumerate(sy):
    if n in ('_identifyChip','_initChip','_programChip'):
        nxt = sy[i+1][0] if i+1 < len(sy) else end
        print(f'{n:20} ours={nxt-a}')
print('reference: _identifyChip=684  _initChip=148  _programChip=1148')
"
```

Our build is unstripped and carries debug stabs sharing addresses, so treat this as indicative. Record the comparison in `divergences.md` whatever it shows.

- [ ] **Step 7: Reline the source map**

Standard fix-pass verification check 5. Expected: `source map OK`.

- [ ] **Step 8: Resolve the ledger entries and update `divergences.md`**

Advance 18704, 19388 and 19536. `identifyChip` was rewritten rather than moved, so unless its rebuilt instruction stream was read against the reference, `control-flow-confirmed` is the honest ceiling. Record the Step 6 size comparison.

- [ ] **Step 9: Commit**

```bash
git add src/drivers-i386/input/drvISASerialPort/ISASerialPort.drvproj/ISASerialPort.lksproj/
git commit -m "drvISASerialPort: reconstruct chip identification from the reference table

Our source detected four parts it invented; the reference's Chip table selects
among twelve and identifyChip is written against it."

git add src/drivers-i386/input/drvISASerialPort/reconstruction/
git commit -m "drvISASerialPort: advance the ledger after the chip split"
```

---

### Task 6: TU 1, the class

18704 bytes, 28 functions — three quarters of the driver. It goes last, with three settled modules beneath it.

**Files:**
- Modify: `.../ISASerialPort.lksproj/ISASerialPort.m`, `ISASerialPort.h`
- Modify: `src/drivers-i386/input/drvISASerialPort/reconstruction/{ledger.json,divergences.md,source-map.json}`

**Interfaces:**
- Consumes: `ISASerialPortInternal.h` and all three extracted C files from Tasks 3-5, plus Task 2's `divergences.md`.
- Produces: the finished driver. Nothing later depends on it except Task 7's README line.

- [ ] **Step 1: Baseline**

Standard fix-pass verification checks 1 through 4. Record the four results.

- [ ] **Step 2: Fix the nine config keys**

Every key our code reads is one the shipped `Default.table` never supplies, so every one parses as absent. `initFromDeviceDescription:` (reference address 264) reads them:

| Reference key | Ours |
| --- | --- |
| `Chip Type` | `ChipType` |
| `Bus Type` | `PortType` |
| `Chip Clock` | `ClockRate` |
| `Heart Beat Interval` | `HeartBeat` |
| `TX Buffer Size` | `TXBufSize` |
| `RX Buffer Size` | `RXBufSize` |
| `Instance` | `PortNum` |
| `Enable MSR Interrupts` | *(our source does not read it)* |
| `Serial` | *(our source does not read it)* |

Seven are renames. `Enable MSR Interrupts` and `Serial` are additions — our source reads neither, so the reference's handling has to be reconstructed from `initFromDeviceDescription:`, along with the log strings `%s: MSR Interrupts enabled.` and `ISASerialPort: Invalid Config Table`.

Do not merely rename: check what each value feeds. Renaming a key while leaving a wrongly-inverted consumer is how the sibling effort nearly shipped a bug, which is why one driver's key rename was deliberately split from its semantics.

- [ ] **Step 3: Fix the 64-bit division**

`ISASerialPort.m` calls `__udivdi3` and `__umoddi3` **explicitly with four arguments** at what were lines 3308-3309 and 3934-3935. gcc emits those calls implicitly from ordinary `unsigned long long` arithmetic; the four-argument form is a decompiler rendering of `call ___udivdi3` with the operands already pushed.

Rewrite both sites as plain 64-bit division and modulo. For the pair at 3308-3309, that is a single division and modulo of `tempValue * 1000000000` by `eventData`.

**Keep the hand-written `__udivdi3`/`__umoddi3` definitions.** `/usr/lib/libcc.a` on the guest is a PPC archive and cannot load for `-arch i386`, so they are the only implementation available. Because our source names them `__udivdi3`/`__umoddi3` in C, the compiler emits `___udivdi3`/`___umoddi3` — exactly what gcc's implicit calls resolve to — so removing the explicit calls does not break the link. Add a comment saying they stand in for an unavailable i386 libgcc, and remove the misleading comments Task 2 flagged.

`___clz_tab` stays absent; `__TEXT,__const` remains near 196 against 682. Recorded, not chased.

- [ ] **Step 4: Add the `PortDevices` protocol conformance**

`__OBJC,__class_names` shows the reference class conforms to `PortDevices` alongside `IODirectDevice`, `IODevice` and `Object`. Add it to the `@interface` declaration.

- [ ] **Step 5: Work the remaining findings**

Everything else `divergences.md` records for the 28 TU 1 functions. Budget by size: `_FIFOIntHandler` (3172), `_executeEvent` (2704), `_NonFIFOIntHandler` (2472) and `initFromDeviceDescription:` (2276) are 10.6 KB of the 18.7 KB.

Resolve constants to their definitions, never to the comment beside them.

- [ ] **Step 6: Build and verify**

Standard fix-pass verification checks 1 through 4. Expected: `EXIT=0`; `missing_strings` **0**; `reference-only` externals still 0; section match count at its best.

- [ ] **Step 7: Reline the source map**

Standard fix-pass verification check 5. Expected: `source map OK`.

- [ ] **Step 8: Resolve every remaining ledger entry**

No entry may end `unexamined`. Verify:

```bash
cd /d/RhapsodiOS
./.venv-binrecon/Scripts/python.exe -c "
import json
d = json.load(open('src/drivers-i386/input/drvISASerialPort/reconstruction/ledger.json'))
left = [e['names'][0] for e in d['entries'] if e['status']=='unexamined']
print('entries:', len(d['entries']), 'unexamined:', len(left))
[print('  ', n) for n in left]
"
```

Expected: `entries: 45 unexamined: 0`.

- [ ] **Step 9: Commit**

```bash
git add src/drivers-i386/input/drvISASerialPort/ISASerialPort.drvproj/ISASerialPort.lksproj/
git commit -m "drvISASerialPort: align the driver class with the reference binary

Reads the config keys the shipped table actually supplies, conforms to
PortDevices, and lets gcc emit the 64-bit division helpers."

git add src/drivers-i386/input/drvISASerialPort/reconstruction/
git commit -m "drvISASerialPort: advance the ledger after the class fix pass"
```

---

### Task 7: README status line

**Files:**
- Modify: `src/drivers-i386/README:17`

**Interfaces:**
- Consumes: the outcome of Task 6 — whether the driver built and whether its fix pass completed.
- Produces: nothing. This is the last task.

- [ ] **Step 1: Update the line**

`src/drivers-i386/README` currently has, in its `input` block:

```
 * drvISASerialPort - needs compiled and then tested
```

Its five siblings now read `compiles; reconstructed against the reference binary, fixes applied, not yet tested`. Match that wording if the driver built and its fix pass completed.

**Do not write `complete`.** That word is reserved in this file for drivers actually exercised, and this one has not been booted — verification was static only.

- [ ] **Step 2: Verify only that line changed**

```bash
cd /d/RhapsodiOS
git diff --stat src/drivers-i386/README
git diff src/drivers-i386/README
```

Expected: one changed line, inside the `input` block, with no other block touched. If the diff shows anything else, undo it.

- [ ] **Step 3: Commit**

```bash
git add src/drivers-i386/README
git commit -m "drivers-i386: record the drvISASerialPort reconstruction status"
```
