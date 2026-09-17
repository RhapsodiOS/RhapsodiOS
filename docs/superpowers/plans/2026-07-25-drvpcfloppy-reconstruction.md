# drvPCFloppy Reconstruction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring drvPCFloppy's selector names, linkage, config table and resources into agreement with Apple's shipped `Floppy_reloc`, then produce the committed source map, ledger and divergence report that the fix phases will work from.

**Architecture:** Two phases. A mechanical pre-pass repairs what the reference symbol table proves directly — 27 duplicate method definitions deleted, 134 selectors renamed, four selector shapes corrected, four lock classes linked instead of reimplemented, the config table and localized resources restored. A report pass then runs IDA and angr over the reference, maps all 225 reference functions onto our sources, and records every remaining divergence. No behavioural repair happens in this plan; that is the follow-on fix-phase plan written in Task 13.

**Tech Stack:** Objective-C for DriverKit 3 (NeXT `cc`, C89), built by `gnumake` inside a Rhapsody QEMU guest. Analysis by `tools/binrecon` on the Windows host: Python 3.12 in `.venv-binrecon`, IDA Professional 9.2, angr 9.3.0.

**Spec:** [2026-07-25-drvpcfloppy-binary-reconstruction-design.md](../specs/2026-07-25-drvpcfloppy-binary-reconstruction-design.md)

## Global Constraints

- **Reference binary:** `C:\Users\raynorpat\Downloads\test\Drivers\i386\Floppy.config\Floppy_reloc`. Never modified.
- **Rebuilt binary:** `out/i386/drvPCFloppy/Floppy.config/Floppy_reloc`, produced in the guest and copied back by the user.
- **Source directory:** `src/drivers-i386/ide/drvPCFloppy/Floppy.drvproj/Floppy.lksproj` — referred to below as `$LKS`.
- **Scratchpad:** the session's temporary directory, referred to below as `$SCRATCHPAD`. Nothing written there is committed.
- **Python invocation:** always `PYTHONPATH=tools/binrecon .venv-binrecon/Scripts/python.exe`, run from the repository root.
- **Guest builds are a user handoff.** `vm/build-i386-floppy.sh` is outside `SyncPaths` and the user runs it manually. Where this plan says *Build checkpoint*, stop, ask the user to run the build and return `/tmp/Floppy.log` plus the staged `Floppy_reloc`, and do not proceed until they do.
- **Drop exactly one underscore, never strip all.** These four reference selectors legitimately begin with `_`: `_freePartitions`, `_initPartition:disktab:`, `_probeLabel:`, `_diskParamCommon:length:deviceOffset:bytesToMove:`.
- **Commit messages** start with the subsystem (`drvPCFloppy: `, `binrecon: `, `docs: `), are one to two lines, describe behaviour rather than files, and carry no metadata or co-author trailers (CLAUDE.md §5).
- **Surgical changes only.** Every changed line traces to this plan. Do not tidy adjacent code, reformat, or fix unrelated dead code — note it instead.
- **The pre-pass is the only licensed sweep.** After Task 12, changes touch only what the ledger flags.

## Scope

This plan covers spec §4.1 (mechanical pre-pass) and §4.2 (report pass). It does **not** cover the five fix phases of §4.3: their content is determined by `divergences.md`, which does not exist until Task 12. Task 13 writes that plan. Attempting to specify fix-phase steps now would mean inventing the divergences they resolve.

## File Structure

**Modified — driver sources** (all under `$LKS`):

| File | Change |
|---|---|
| `IODiskNew.m`, `IODiskNew.h` | 25 duplicate definitions and declarations deleted |
| `IODiskPartitionNEW.m`, `IODiskPartitionNEW.h` | 2 duplicate definitions and declarations deleted |
| all 19 `.m` and 20 `.h` | 134 selectors renamed |
| `IOFloppyDisk.m/.h`, `IOFloppyDrive.m/.h`, `Geometry.m/.h`, `IOLogicalDiskNEW.m/.h` | selector shapes and one category name corrected |
| `FloppyCnt.m`, `IODiskNew.m`, `Makefile` | link `machkit/NXLock.h` instead of the local copy |
| `NXLock.m`, `NXLock.h` | deleted |

**Modified — driver bundle:**

| File | Change |
|---|---|
| `Floppy.drvproj/Default.table` | `"Version"` added, `"Boot Driver"` made a bare key |
| `Floppy.drvproj/PB.project` | `English.lproj` registered |
| `Floppy.drvproj/English.lproj/…` | created from the reference bundle |

**Created — reconstruction artifacts:**

| File | Responsibility |
|---|---|
| `tools/binrecon/profiles/floppy.json` | analyzer configuration, reference and rebuilt paths |
| `src/drivers-i386/ide/drvPCFloppy/reconstruction/source-map.json` | the complete 225-function partition |
| `src/drivers-i386/ide/drvPCFloppy/reconstruction/ledger.json` | per-function parity confidence |
| `src/drivers-i386/ide/drvPCFloppy/reconstruction/divergences.md` | every finding, with reference decompilation beside our source |

**Already committed and used as-is:** `tools/binrecon/selector_check.py`, `tools/binrecon/import_check.py`, `tools/binrecon/parity_check.py`, `vm/build-i386-floppy.sh`.

**Scratch, not committed:** `fix_selectors.py`, written in Task 3 under the session scratchpad.

---

### Task 1: Untrack the staged rebuild and correct the README

`6713ce0c` added `out/` to `.gitignore` and untracked drvSerialPointingDevice's staged artifacts but missed drvPCFloppy's, so a 791 KB binary is still in the repository. The README's status line for drvPCFloppy is also stale — it has built since `7f1c93a6`.

**Files:**
- Modify: `src/drivers-i386/README` (drvPCFloppy line)
- Untrack: `out/i386/drvPCFloppy/Floppy.config/Floppy_reloc`, `out/i386/drvPCFloppy/Floppy.config/Default.table`

**Interfaces:**
- Consumes: nothing.
- Produces: nothing later tasks import. The staged binary stays on disk for `parity_check.py` and `import_check.py`.

- [ ] **Step 1: Confirm the files are tracked and ignored at the same time**

```bash
git ls-files out/i386/drvPCFloppy/
```

Expected: two paths listed — `Floppy.config/Default.table` and `Floppy.config/Floppy_reloc`.

- [ ] **Step 2: Untrack them, keeping the working copies**

```bash
git rm --cached -r out/i386/drvPCFloppy/
```

Expected: `rm 'out/i386/drvPCFloppy/Floppy.config/Default.table'` and the same for `Floppy_reloc`. Note `--cached`: the files must remain on disk, because Tasks 5 and 9 read them.

- [ ] **Step 3: Verify they survived on disk and are now ignored**

```bash
ls -la out/i386/drvPCFloppy/Floppy.config/ && git check-ignore -v out/i386/drvPCFloppy/Floppy.config/Floppy_reloc
```

Expected: both files present, and `check-ignore` prints `.gitignore:19:out/`.

- [ ] **Step 4: Correct the README status line**

In `src/drivers-i386/README`, change:

```
 * drvPCFloppy - needs compiled and then tested
```

to:

```
 * drvPCFloppy - builds; reconstruction against Apple's Floppy_reloc in progress
```

- [ ] **Step 5: Commit**

`git rm --cached` in Step 2 already staged the two deletions, and `out/` is
ignored, so do **not** name that path to `git add` — git refuses ignored paths
and the command fails. Stage only the README:

```bash
git add src/drivers-i386/README
git commit -m "drvPCFloppy: untrack the staged rebuild and refresh the status line

The out/ tree is guest build output per 6713ce0c; the driver has built since 7f1c93a6."
```

Then confirm the commit carries all three changes:

```bash
git show --stat HEAD
```

Expected: `src/drivers-i386/README` modified, and both `out/i386/drvPCFloppy/Floppy.config/` files deleted.

---

### Task 2: Link the machkit lock classes instead of reimplementing them

Spec §2.6 and §4.1 step 0c. The reference imports `.objc_class_name_NXLock`, `NXConditionLock` and `NXSpinLock` as undefined symbols, so Apple linked them from the kernel. `NXLock.m` reimplements all four locally. This is spec §4.1's gating step and goes first: if `machkit/NXLock.h` turns out to be unreachable from a loadable kernel driver, everything after it is affected. drvEIDE — marked complete — already does this correctly at `AtapiCnt.m:52`, so the risk is low.

**Files:**
- Delete: `$LKS/NXLock.m`, `$LKS/NXLock.h`
- Modify: `$LKS/FloppyCnt.m:9`, `$LKS/IODiskNew.m:10`, `$LKS/Makefile`

**Interfaces:**
- Consumes: nothing.
- Produces: `NXLock`, `NXConditionLock`, `NXSpinLock` and `NXRecursiveLock` now resolve from `<machkit/NXLock.h>` for every later task. No local declaration of them survives.

- [ ] **Step 1: Confirm the local copy is the only thing providing them, and that nothing else imports it**

```bash
grep -rn "NXLock.h" src/drivers-i386/ide/drvPCFloppy/
```

Expected: exactly four hits — `FloppyCnt.m:9` and `IODiskNew.m:10` importing `"NXLock.h"`, plus `NXLock.m:4` and the header's own banner comment. If any other file imports it, add that file to Step 3.

- [ ] **Step 2: Confirm machkit declares all four classes**

```bash
grep -n "@interface" src/machkit-1/NXLock.h
```

Expected: `NXSpinLock`, `NXConditionLock`, `NXLock` and `NXRecursiveLock`. Our local header is a verbatim copy of this file, so nothing is lost by deleting it.

- [ ] **Step 3: Switch the two imports to the framework header**

In `$LKS/FloppyCnt.m` line 9 and `$LKS/IODiskNew.m` line 10, change:

```objc
#import "NXLock.h"
```

to:

```objc
#import <machkit/NXLock.h>
```

- [ ] **Step 4: Delete the local implementation and header**

```bash
git rm src/drivers-i386/ide/drvPCFloppy/Floppy.drvproj/Floppy.lksproj/NXLock.m src/drivers-i386/ide/drvPCFloppy/Floppy.drvproj/Floppy.lksproj/NXLock.h
```

- [ ] **Step 5: Remove them from the Makefile**

In `$LKS/Makefile`, the `CLASSES` list currently reads:

```make
          kernelDiskMethodsNEW.m NXLock.m Request.m Support.m Thread.m\
```

change it to:

```make
          kernelDiskMethodsNEW.m Request.m Support.m Thread.m\
```

and the `HFILES` list currently reads:

```make
         kernelDiskMethodsNEW.h NXLock.h Request.h Support.h Thread.h\
```

change it to:

```make
         kernelDiskMethodsNEW.h Request.h Support.h Thread.h\
```

`PB.project` never listed either file, so it needs no change — that disagreement between the two build descriptions is what this step resolves.

- [ ] **Step 6: Verify no reference to the deleted files remains**

```bash
grep -rn "NXLock.m\|\"NXLock.h\"" src/drivers-i386/ide/drvPCFloppy/
```

Expected: no output.

- [ ] **Step 7: Commit**

```bash
git add -A src/drivers-i386/ide/drvPCFloppy
git commit -m "drvPCFloppy: link the machkit lock classes instead of reimplementing them

The reference imports NXLock, NXConditionLock and NXSpinLock from the kernel; our local NXLock.m defined its own."
```

---

### Task 3: Delete the 27 duplicate method definitions

Spec §2.1 and §4.1 step 0a. Twenty-seven underscored methods shadow a correctly-named sibling in the same `@implementation` block. `IODiskNEW` defines a substantive `registerDevice` at `IODiskNew.m:188` and then a `_registerDevice` at 344 whose entire body is `// TODO: Implement registration`. The reference's `IODiskNEW` carries the non-underscored names, so the underscored ones are residue. Renaming rather than deleting them would produce duplicate definitions that do not compile.

**Files:**
- Create: `<scratchpad>/fix_selectors.py`
- Modify: `$LKS/IODiskNew.m`, `$LKS/IODiskNew.h`, `$LKS/IODiskPartitionNEW.m`, `$LKS/IODiskPartitionNEW.h`

**Interfaces:**
- Consumes: `selector_check.reference_selectors(path)`, `selector_check.source_methods(source_dir)` and `selector_check.classify(reference, methods) -> (renames, duplicates, missing, extra)`, all from the committed `tools/binrecon/selector_check.py`. `renames` and `duplicates` are lists of `(full_name, filename, line)`; `missing` and `extra` are sorted lists of names.
- Produces: `fix_selectors.py` with a `--rename` mode that Task 4 runs.

- [ ] **Step 1: Run the check and watch it fail**

```bash
PYTHONPATH=tools/binrecon .venv-binrecon/Scripts/python.exe tools/binrecon/selector_check.py "C:/Users/raynorpat/Downloads/test/Drivers/i386/Floppy.config/Floppy_reloc" src/drivers-i386/ide/drvPCFloppy/Floppy.drvproj/Floppy.lksproj
```

Expected: exit status 1, `renames (134)`, `duplicates (27)`, `missing (6)`, `extra (17)`. The 27 duplicates are 25 in `IODiskNew.m` and 2 in `IODiskPartitionNEW.m`.

- [ ] **Step 2: Write the migration script**

Create `fix_selectors.py` in the session scratchpad directory. It is a one-shot repair, not committed.

```python
"""One-shot repair of drvPCFloppy's selector names against the reference binary.

Two modes, run in order:

  --delete-duplicates   remove the underscored method definitions that shadow a
                        correctly-named sibling, plus their header declarations
  --rename              drop one leading underscore from the remaining
                        underscored selectors, in declarations, definitions and
                        message sends

A token that is also an instance-variable name is renamed only in method
signature position, so `return _isPhysical;` keeps its ivar reference while
`- (BOOL)_isPhysical` becomes `- (BOOL)isPhysical`.
"""

import argparse
import re
import sys
from pathlib import Path

sys.path.insert(0, 'tools/binrecon')
from selector_check import reference_selectors, source_methods, classify


def ivar_names(source_dir):
    names = set()
    for path in Path(source_dir).glob('*.h'):
        text = path.read_text(errors='replace')
        for block in re.findall(r'@interface[^{]*\{(.*?)^\}', text, re.S | re.M):
            for name in re.findall(r'(\b_\w+)\s*(?:\[[^\]]*\])?\s*;', block):
                names.add(name)
    return names


def first_keyword(full_name):
    selector = full_name.split(' ', 1)[1].rstrip(']')
    return selector.split(':')[0]


def method_span(lines, start):
    """Return (first, last) 0-based line indices of the definition at `start`,
    extended upward over an immediately preceding comment block."""
    depth, index, seen_brace = 0, start, False
    while index < len(lines):
        depth += lines[index].count('{') - lines[index].count('}')
        if '{' in lines[index]:
            seen_brace = True
        if seen_brace and depth <= 0:
            break
        index += 1
    last = index
    first = start
    probe = start - 1
    while probe >= 0 and lines[probe].strip() == '':
        probe -= 1
    if probe >= 0 and lines[probe].strip().endswith('*/'):
        while probe >= 0 and '/*' not in lines[probe]:
            probe -= 1
        if probe >= 0:
            first = probe
    return first, last


def delete_duplicates(source_dir, duplicates):
    by_file = {}
    for full, filename, line in duplicates:
        by_file.setdefault(filename, []).append((line, full))

    removed = 0
    for filename, entries in by_file.items():
        path = Path(source_dir) / filename
        lines = path.read_text(errors='replace').splitlines(keepends=True)
        drop = set()
        for line, _ in entries:
            first, last = method_span(lines, line - 1)
            drop.update(range(first, last + 1))
        kept = [text for index, text in enumerate(lines) if index not in drop]
        path.write_text(''.join(kept))
        removed += len(entries)
        print('  %s: removed %d definitions (%d lines)'
              % (filename, len(entries), len(drop)))

    # Header declarations for the same selectors, scoped to the owning class:
    # _free is a duplicate on IODiskNEW but a true rename on IODiskPartitionNEW.
    tokens_by_class = {}
    for full, _, _ in duplicates:
        owner = re.match(r'^[-+]\[(\w+)', full).group(1)
        tokens_by_class.setdefault(owner, set()).add(first_keyword(full))

    for path in sorted(Path(source_dir).glob('*.h')):
        lines = path.read_text(errors='replace').splitlines(keepends=True)
        out, index, dropped, active = [], 0, 0, set()
        while index < len(lines):
            interface = re.match(r'^@interface\s+(\w+)', lines[index])
            if interface:
                active = tokens_by_class.get(interface.group(1), set())
            elif lines[index].startswith('@end'):
                active = set()
            match = re.match(r'^[-+]\s*(?:\([^)]*\)\s*)?(_\w+)', lines[index].lstrip())
            if match and match.group(1) in active:
                while index < len(lines) and ';' not in lines[index]:
                    index += 1
                index += 1
                dropped += 1
                continue
            out.append(lines[index])
            index += 1
        if dropped:
            path.write_text(''.join(out))
            print('  %s: removed %d declarations' % (path.name, dropped))
    return removed


def rename(source_dir, renames, ivars):
    tokens = sorted({first_keyword(full) for full, _, _ in renames},
                    key=len, reverse=True)
    signature_only = [t for t in tokens if t in ivars]
    everywhere = [t for t in tokens if t not in ivars]
    print('  %d tokens renamed everywhere, %d in signature position only'
          % (len(everywhere), len(signature_only)))

    for path in sorted(list(Path(source_dir).glob('*.m'))
                       + list(Path(source_dir).glob('*.h'))):
        text = path.read_text(errors='replace')
        original = text
        for token in everywhere:
            text = re.sub(r'\b%s\b' % re.escape(token), token[1:], text)
        for token in signature_only:
            text = re.sub(r'(?m)^([-+]\s*(?:\([^)]*\)\s*)?)%s\b' % re.escape(token),
                          lambda m: m.group(1) + token[1:], text)
        if text != original:
            path.write_text(text)
            print('  %s: rewritten' % path.name)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('reference')
    parser.add_argument('source_dir')
    parser.add_argument('--delete-duplicates', action='store_true')
    parser.add_argument('--rename', action='store_true')
    args = parser.parse_args()

    reference = reference_selectors(Path(args.reference))
    methods = list(source_methods(args.source_dir))
    renames, duplicates, _, _ = classify(reference, methods)

    if args.delete_duplicates:
        print('deleting %d duplicate definitions' % len(duplicates))
        delete_duplicates(args.source_dir, duplicates)
    if args.rename:
        print('renaming %d selectors' % len(renames))
        rename(args.source_dir, renames, ivar_names(args.source_dir))
    return 0


if __name__ == '__main__':
    sys.exit(main())
```

- [ ] **Step 3: Delete the duplicates**

```bash
PYTHONPATH=tools/binrecon .venv-binrecon/Scripts/python.exe "$SCRATCHPAD/fix_selectors.py" "C:/Users/raynorpat/Downloads/test/Drivers/i386/Floppy.config/Floppy_reloc" src/drivers-i386/ide/drvPCFloppy/Floppy.drvproj/Floppy.lksproj --delete-duplicates
```

Expected, exactly:

```
deleting 27 duplicate definitions
  IODiskNew.m: removed 25 definitions (189 lines)
  IODiskPartitionNEW.m: removed 2 definitions (14 lines)
  IODiskNew.h: removed 25 declarations
  IODiskPartitionNEW.h: removed 2 declarations
```

If any other header appears in that output, the class scoping has regressed — stop and fix the script rather than committing.

- [ ] **Step 4: Verify the duplicates are gone and the renames are untouched**

```bash
PYTHONPATH=tools/binrecon .venv-binrecon/Scripts/python.exe tools/binrecon/selector_check.py "C:/Users/raynorpat/Downloads/test/Drivers/i386/Floppy.config/Floppy_reloc" src/drivers-i386/ide/drvPCFloppy/Floppy.drvproj/Floppy.lksproj | grep -E "^(our|renames|duplicates)"
```

Expected: `our definitions: 207`, `renames (134)`, `duplicates (0)`.

- [ ] **Step 5: Confirm each deleted selector still has its sibling**

```bash
grep -n "^- registerDevice\|^- free\|^- (IOReturn)eject" src/drivers-i386/ide/drvPCFloppy/Floppy.drvproj/Floppy.lksproj/IODiskNew.m
```

Expected: three hits. These are the substantive implementations the duplicates were shadowing.

- [ ] **Step 6: Commit**

```bash
git add src/drivers-i386/ide/drvPCFloppy
git commit -m "drvPCFloppy: delete the duplicate underscored methods

Twenty-seven underscored definitions shadowed implemented siblings; eight were TODO stubs that the reference has no counterpart for."
```

---

### Task 4: Rename the 134 remaining selectors

Spec §2.1 and §4.1 step 0a′. These are the true renames: the underscored method is the class's only definition of that selector, so `-[IODiskNEW free]` and every other DriverKit-called selector currently overrides nothing.

Six of the tokens — `_devAndIdInfo`, `_driveName`, `_isPhysical`, `_lastReadyState`, `_nextLogicalDisk`, `_physicalDisk` — are also instance-variable names. In every case the method is a getter returning the ivar of the same name, and none appears in message-send position, so the script renames those six only in signature position. The other 123 are replaced everywhere.

**Files:**
- Modify: all 19 `.m` and 19 remaining `.h` files under `$LKS`

**Interfaces:**
- Consumes: `fix_selectors.py` from Task 3.
- Produces: every reference selector except the six of spec §2.5 and §1.3 now appears under its reference name. Task 6 corrects four of those six.

- [ ] **Step 1: Confirm the check still fails on renames only**

```bash
PYTHONPATH=tools/binrecon .venv-binrecon/Scripts/python.exe tools/binrecon/selector_check.py "C:/Users/raynorpat/Downloads/test/Drivers/i386/Floppy.config/Floppy_reloc" src/drivers-i386/ide/drvPCFloppy/Floppy.drvproj/Floppy.lksproj | grep -E "^(renames|duplicates)"
```

Expected: `renames (134)`, `duplicates (0)`.

- [ ] **Step 2: Run the rename**

```bash
PYTHONPATH=tools/binrecon .venv-binrecon/Scripts/python.exe "$SCRATCHPAD/fix_selectors.py" "C:/Users/raynorpat/Downloads/test/Drivers/i386/Floppy.config/Floppy_reloc" src/drivers-i386/ide/drvPCFloppy/Floppy.drvproj/Floppy.lksproj --rename
```

Expected first two lines, exactly:

```
renaming 134 selectors
  123 tokens renamed everywhere, 6 in signature position only
```

followed by one `rewritten` line per modified file.

- [ ] **Step 3: Verify the check now passes**

```bash
PYTHONPATH=tools/binrecon .venv-binrecon/Scripts/python.exe tools/binrecon/selector_check.py "C:/Users/raynorpat/Downloads/test/Drivers/i386/Floppy.config/Floppy_reloc" src/drivers-i386/ide/drvPCFloppy/Floppy.drvproj/Floppy.lksproj > /dev/null; echo "exit=$?"
```

Expected: `exit=0`.

- [ ] **Step 4: Confirm the six ivar-colliding tokens kept their ivar references**

```bash
sed -n '/^- (const char \*)driveName/,/^}/p' src/drivers-i386/ide/drvPCFloppy/Floppy.drvproj/Floppy.lksproj/IODriveNEW.m
```

Expected: the signature is `- (const char *)driveName` and the body still reads `return _driveName;`. A body reading `return driveName;` means the signature-only rule failed — revert and fix before continuing.

- [ ] **Step 5: Confirm the four legitimately-underscored selectors kept one underscore**

```bash
grep -rn "^- (IOReturn)_freePartitions\|^- (IOReturn)_probeLabel\|^- (IOReturn)_initPartition\|^- (IOReturn)_diskParamCommon" src/drivers-i386/ide/drvPCFloppy/Floppy.drvproj/Floppy.lksproj/
```

Expected: four hits, each with exactly one leading underscore. Zero hits means they were over-stripped.

- [ ] **Step 6: Commit**

```bash
git add src/drivers-i386/ide/drvPCFloppy
git commit -m "drvPCFloppy: restore Apple's selector names

134 methods carried a leading underscore, so free, registerDevice and the read/write family overrode nothing."
```

---

### Task 4b: Rename the 21 misnamed C functions

Added after Task 5's build revealed that spec §2.3 was wrong. Twenty-one reference C functions are not absent from our sources — they are present under a name carrying one spurious leading underscore. `Bsd.m:44` declares `static int _HandleBsdIoctl(...)`, which compiles to the symbol `__HandleBsdIoctl`, while the reference has `_HandleBsdIoctl`. Same defect as Task 4, in C rather than Objective-C, on the same evidence.

**Files:**
- Modify: `$LKS/Bsd.m`, `$LKS/FloppyCnt.m`, `$LKS/FloppyCnt.h`, `$LKS/FloppyDriveInt.m`, `$LKS/FloppyDriveInt2.m`, `$LKS/IOFloppyDisk.m`, `$LKS/IOFloppyDisk.h`, `$LKS/Thread.m`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: 21 more reference symbols resolvable by name. Task 11's source map can then classify them `mapped` rather than `absent-from-sources`.

The 21 names, each to lose exactly one leading underscore:

```
_FloppyControllerThread   _HandleBsdClose      _HandleBsdIoctl
_HandleBsdOpen            _HandleBsdRead       _HandleBsdSize
_HandleBsdStrategy        _HandleBsdWrite      _OperationThreadStartup
_fakeStrategySuccess      _fdTimer             _floppyDriveType
_identifyBsdDev           _identifyDetachedDiskIdFromBsdDev
_numFloppyDrives          _physContBlocks      _queueOperationAscending
_strlower                 _sweepQueueInsert    _sweepQueueReorder
_vFloppyCopy
```

- [ ] **Step 1: Confirm the current symbol names**

```bash
PYTHONPATH=tools/binrecon .venv-binrecon/Scripts/python.exe -c "
from pathlib import Path
from binrecon.macho import read_macho
d = read_macho(Path('out/i386/drvPCFloppy/Floppy.config/Floppy_reloc'))
t = [s['name'] for s in d['symbols'] if s['section'] == '__TEXT,__text']
print([n for n in t if n.startswith('__Handle')][:4])
"
```

Expected: names beginning with two underscores, e.g. `__HandleBsdOpen`.

- [ ] **Step 2: Rename each name and all its references**

For each of the 21 names, replace the whole-word token `_NAME` with `NAME` across the eight files listed above — prototypes, definitions and call sites alike. These are file-scope C identifiers, and none of them collides with an instance-variable name, so unlike Task 4 a straight whole-word token replacement is safe.

Two things to expect and leave alone:
- `Bsd.m:1192-1197` is a comment block listing `HandleBsdOpen (0x448)` and friends without underscores. It is already correct and needs no change.
- `Thread.m` defines `_strlower` but calls `strlower` at lines 639 and 698. Those call sites are already in the target form. Renaming the definition makes them agree, repairing a pre-existing mismatch — do not "fix" the call sites in the other direction.

- [ ] **Step 3: Verify no double-underscore C names remain**

```bash
grep -rnE "(^|[^_[:alnum:]])_(FloppyControllerThread|HandleBsd(Close|Ioctl|Open|Read|Size|Strategy|Write)|OperationThreadStartup|fakeStrategySuccess|fdTimer|floppyDriveType|identifyBsdDev|identifyDetachedDiskIdFromBsdDev|numFloppyDrives|physContBlocks|queueOperationAscending|strlower|sweepQueueInsert|sweepQueueReorder|vFloppyCopy)\b" src/drivers-i386/ide/drvPCFloppy/Floppy.drvproj/Floppy.lksproj/
```

Expected: no output.

- [ ] **Step 4: Verify the Objective-C gate is untouched**

```bash
PYTHONPATH=tools/binrecon .venv-binrecon/Scripts/python.exe tools/binrecon/selector_check.py "C:/Users/raynorpat/Downloads/test/Drivers/i386/Floppy.config/Floppy_reloc" src/drivers-i386/ide/drvPCFloppy/Floppy.drvproj/Floppy.lksproj | grep -E "^(our|renames|duplicates)"
```

Expected, unchanged: `our definitions: 195`, `renames (0)`, `duplicates (0)`.

- [ ] **Step 5: Commit**

```bash
git add src/drivers-i386/ide/drvPCFloppy
git commit -m "drvPCFloppy: restore Apple's C function names

Twenty-one file-scope functions carried a leading underscore; strlower was also defined under a name its own call sites never used."
```

---

### Task 5: Build checkpoint — the pre-pass so far

Tasks 2, 3 and 4 each passed a static gate. This is their integration gate: the first build since the tree changed shape. An over-eager rename shows up here as an undeclared identifier, and a missed call site as a "may not respond to" warning.

**Files:** none modified.

**Interfaces:**
- Consumes: the working tree from Tasks 2–4.
- Produces: a refreshed `out/i386/drvPCFloppy/Floppy.config/Floppy_reloc` for Tasks 9 and 12.

- [ ] **Step 1: Hand off to the user**

Ask the user to sync and run `vm/build-i386-floppy.sh` in the guest, then return `/tmp/Floppy.log` and copy the staged `Floppy_reloc` to `out/i386/drvPCFloppy/Floppy.config/`. Wait for them. Do not continue on assumption.

- [ ] **Step 2: Confirm the build succeeded**

In the returned log, expect `make exit=0` and a `Floppy_reloc` staged. If the build failed, the failure belongs to Tasks 2–4 and is fixed there before proceeding — do not start Task 6 on a broken tree.

- [ ] **Step 3: Review the warnings the rename could have caused**

```bash
grep -n "may not respond\|undeclared\|conflicting types" /tmp/Floppy.log
```

Expected: no `undeclared` and no `conflicting types`. Any `may not respond to` naming a renamed selector is a missed call site — fix it in `$LKS`, then repeat this checkpoint.

- [ ] **Step 4: Measure the three parity axes**

```bash
PYTHONPATH=tools/binrecon .venv-binrecon/Scripts/python.exe tools/binrecon/parity_check.py "C:/Users/raynorpat/Downloads/test/Drivers/i386/Floppy.config/Floppy_reloc" out/i386/drvPCFloppy/Floppy.config/Floppy_reloc | grep -E "^[a-z_]+ \("
```

Expected: `missing_symbols` far below its 163 baseline — roughly 24, being the 17 absent C functions of spec §2.3, the 3 build-generated entries of §1.3 and the 4 names Task 6 corrects. `missing_strings` stays near 94; the pre-pass does not restore strings.

```bash
PYTHONPATH=tools/binrecon .venv-binrecon/Scripts/python.exe tools/binrecon/import_check.py "C:/Users/raynorpat/Downloads/test/Drivers/i386/Floppy.config/Floppy_reloc" out/i386/drvPCFloppy/Floppy.config/Floppy_reloc | grep -E "^(reference|rebuilt|missing_imports)"
```

Expected: `missing_imports (7)` or fewer. Record all four numbers — Task 12 writes them into `divergences.md` as the post-pre-pass baseline.

- [ ] **Step 5: Verify every remaining missing symbol is accounted for**

Read the full `missing_symbols` list. Each entry must be one of: a C function from spec §2.3, a build-generated name from §1.3, or one of the four names Task 6 corrects. A name outside those three groups means the pre-pass silently dropped something — investigate before continuing.

- [ ] **Step 6: Commit nothing**

This task changes no files. Record the four numbers in the task notes for Task 12.

---

### Task 6: Correct three selector shapes and one category name

Spec §2.5 and §4.1 step 0b. Apple declared three initialisers and one geometry method with empty keywords; named keywords produce a different selector, so these still override nothing after Task 4. One category is also miscased.

**Files:**
- Modify: `$LKS/IOFloppyDisk.m`, `$LKS/IOFloppyDisk.h`, `$LKS/IOFloppyDrive.m`, `$LKS/IOFloppyDrive.h`, `$LKS/Geometry.m`, `$LKS/Geometry.h`, `$LKS/Request.m`, `$LKS/FloppyCnt.m`, `$LKS/FloppyDriveInt.m`, `$LKS/IOLogicalDiskNEW.m`, `$LKS/IOLogicalDiskNEW.h`

**Interfaces:**
- Consumes: the renamed tree from Task 4. `cylinderFromBlockNumber:head:sector:` exists under that name only after Task 4 ran.
- Produces: `selector_check` reports `missing (2)` — only the two build-generated names of spec §1.3 remain.

- [ ] **Step 1: Confirm the four names are still missing**

```bash
PYTHONPATH=tools/binrecon .venv-binrecon/Scripts/python.exe tools/binrecon/selector_check.py "C:/Users/raynorpat/Downloads/test/Drivers/i386/Floppy.config/Floppy_reloc" src/drivers-i386/ide/drvPCFloppy/Floppy.drvproj/Floppy.lksproj | sed -n '/^missing/,/^extra/p'
```

Expected: six names — `+[FloppyKernelServerInstance kernelServerInstance]`, `+[FloppyVersion driverKitVersionForFloppy]`, `-[IOFloppyDisk initFromDeviceDescription::::]`, `-[IOFloppyDisk(Geometry) cylinderFromBlockNumber:::]`, `-[IOFloppyDrive initFromDeviceDescription:::]`, `-[IOLogicalDiskNEW(private) _diskParamCommon:length:deviceOffset:bytesToMove:]`.

- [ ] **Step 2: Reshape `IOFloppyDisk`'s initialiser**

In `$LKS/IOFloppyDisk.m` at line 161, change:

```objc
- initFromDeviceDescription:(id)deviceDescription
                      drive:(id)drive
                   capacity:(unsigned)capacity
             writeProtected:(BOOL)writeProtected
```

to:

```objc
- initFromDeviceDescription:(id)deviceDescription
                           :(id)drive
                           :(unsigned)capacity
                           :(BOOL)writeProtected
```

Apply the identical change to the declaration at `$LKS/IOFloppyDisk.h:87`. Leave `[super initFromDeviceDescription:deviceDescription]` at `IOFloppyDisk.m:174` alone — that is `IODirectDevice`'s one-keyword method, a different selector.

- [ ] **Step 3: Update its caller**

At `$LKS/FloppyDriveInt.m:270-274`, change:

```objc
	// Call: [[IOFloppyDisk alloc] initFromDeviceDescription:drive:type:isEjectable:]
	diskObject = [[IOFloppyDisk alloc] initFromDeviceDescription:_deviceDescription
	                                                        drive:self
	                                                         type:diskType
	                                                  isEjectable:isEjectable];
```

to:

```objc
	// Call: [[IOFloppyDisk alloc] initFromDeviceDescription::::]
	diskObject = [[IOFloppyDisk alloc] initFromDeviceDescription:_deviceDescription
	                                                            :self
	                                                            :diskType
	                                                            :isEjectable];
```

Note the pre-existing inconsistency this resolves: the call site sent `initFromDeviceDescription:drive:type:isEjectable:` while the definition declared `drive:capacity:writeProtected:`, so **no method in the tree implemented the selector being sent**. Reshaping both ends makes them agree. The argument names still disagree about meaning — the definition calls the third parameter `capacity` and the caller passes `diskType` — which is a report-pass finding for Task 12, not something to resolve here. Record it; do not rename the parameters.

- [ ] **Step 4: Reshape `IOFloppyDrive`'s initialiser**

In `$LKS/IOFloppyDrive.m` at line 172, change:

```objc
- initFromDeviceDescription:(IODeviceDescription *)deviceDescription
                 controller:(id)controller
                       unit:(unsigned)unit
```

to:

```objc
- initFromDeviceDescription:(IODeviceDescription *)deviceDescription
                           :(id)controller
                           :(unsigned)unit
```

Apply the same change to `$LKS/IOFloppyDrive.h:99`. Then at `$LKS/FloppyCnt.m:476-478`, change:

```objc
			drive = [[IOFloppyDrive alloc] initFromDeviceDescription:devDesc
			                                              controller:controller
			                                                    unit:driveIndex];
```

to:

```objc
			drive = [[IOFloppyDrive alloc] initFromDeviceDescription:devDesc
			                                                        :controller
			                                                        :driveIndex];
```

- [ ] **Step 5: Reshape the geometry method**

This method still carries its leading underscore: Task 4 renamed only selectors whose de-underscored form matches a reference name, and `cylinderFromBlockNumber:head:sector:` does not — the reference selector has empty keywords. So this step drops the underscore *and* reshapes, in one edit.

In `$LKS/Geometry.m` at line 673 and `$LKS/Geometry.h:78`, change:

```objc
- (unsigned)_cylinderFromBlockNumber:(unsigned)blockNumber
                                head:(unsigned *)head
                              sector:(unsigned *)sector
```

to:

```objc
- (unsigned)cylinderFromBlockNumber:(unsigned)blockNumber
                                   :(unsigned *)head
                                   :(unsigned *)sector
```

Then update both sends at `$LKS/Request.m:349` and `:350` from `[self _cylinderFromBlockNumber:blockStart head:NULL sector:NULL]` to `[self cylinderFromBlockNumber:blockStart :NULL :NULL]`.

- [ ] **Step 6: Correct the category name and `_diskParamCommon`**

Two changes to the same method, which Task 4 could not touch for the same reason as Step 5: its de-underscored form did not match the reference, because the *category* differs too.

First, the reference category is `IOLogicalDiskNEW(private)`, lower case. Change `@interface IOLogicalDiskNEW(Private)` at `$LKS/IOLogicalDiskNEW.h:98` and `@implementation IOLogicalDiskNEW(Private)` at `$LKS/IOLogicalDiskNEW.m:322` to `(private)`.

Second, the reference selector is `_diskParamCommon:length:deviceOffset:bytesToMove:` — one leading underscore. Ours has two. The keyword arity is already correct, so this is a one-underscore drop, not a reshape. Change the declaration at `$LKS/IOLogicalDiskNEW.h:103` and the definition at `$LKS/IOLogicalDiskNEW.m:328` from `__diskParamCommon` to `_diskParamCommon`, and update the four sends at `$LKS/IOLogicalDiskNEW.m:183`, `:217`, `:258` and `:299`, each of which reads `result = [self __diskParamCommon:offset`.

Leave every other keyword alone — only the first component loses an underscore.

- [ ] **Step 7: Verify only the build-generated names remain missing**

```bash
PYTHONPATH=tools/binrecon .venv-binrecon/Scripts/python.exe tools/binrecon/selector_check.py "C:/Users/raynorpat/Downloads/test/Drivers/i386/Floppy.config/Floppy_reloc" src/drivers-i386/ide/drvPCFloppy/Floppy.drvproj/Floppy.lksproj | grep -E "^(renames|duplicates|missing)"
```

Expected: `renames (0)`, `duplicates (0)`, `missing (2)` — the two `kl_ld`-generated class methods, which are never written by hand.

- [ ] **Step 8: Commit**

```bash
git add src/drivers-i386/ide/drvPCFloppy
git commit -m "drvPCFloppy: match Apple's empty-keyword selectors

Three initialisers and cylinderFromBlockNumber used named keywords, so they overrode nothing; the private category was also miscased."
```

---

### Task 7: Restore the two `Default.table` divergences

Spec §2.7 and §4.1 step 0d.

**Files:**
- Modify: `src/drivers-i386/ide/drvPCFloppy/Floppy.drvproj/Default.table`

**Interfaces:**
- Consumes: nothing.
- Produces: a table differing from the reference only in `"Driver Version"`, which is build-stamped.

- [ ] **Step 1: Diff against the reference**

```bash
diff "C:/Users/raynorpat/Downloads/test/Drivers/i386/Floppy.config/Default.table" src/drivers-i386/ide/drvPCFloppy/Floppy.drvproj/Default.table
```

Expected: three differences — the reference has `"Version" = "5.10";` that we lack, the reference has bare `"Boot Driver";` where we have `"Boot Driver" = "";`, and the reference has a `"Driver Version"` line that we lack.

- [ ] **Step 2: Add the `"Version"` line**

After `"Family" = "Disk";`, insert:

```
"Version" = "5.10";
```

- [ ] **Step 3: Make `"Boot Driver"` a bare key**

Change:

```
"Boot Driver" = "";
```

to:

```
"Boot Driver";
```

- [ ] **Step 4: Verify only `"Driver Version"` differs**

```bash
diff "C:/Users/raynorpat/Downloads/test/Drivers/i386/Floppy.config/Default.table" src/drivers-i386/ide/drvPCFloppy/Floppy.drvproj/Default.table
```

Expected: one hunk, the reference's `"Driver Version" = "PROGRAM:Floppy …";` line only. Do not add that line — the build stamps it.

- [ ] **Step 5: Commit**

```bash
git add src/drivers-i386/ide/drvPCFloppy/Floppy.drvproj/Default.table
git commit -m "drvPCFloppy: restore the Version key and the bare Boot Driver key

Matches Apple's Default.table except for the build-stamped Driver Version."
```

---

### Task 8: Add the localized resources

Spec §2.8 and §4.1 step 0e. The reference bundle ships `English.lproj`; our tree has none, while drvEIDE and drvVGA both carry theirs under `<name>.drvproj/English.lproj/`.

**Files:**
- Create: `src/drivers-i386/ide/drvPCFloppy/Floppy.drvproj/English.lproj/Localizable.strings`
- Create: `src/drivers-i386/ide/drvPCFloppy/Floppy.drvproj/English.lproj/Help/Floppy.rtfd/` (`TXT.rtf`, `251243_PixelRule.tiff`, `494393_PixelRule.tiff`, `other.tiff`)
- Create: `src/drivers-i386/ide/drvPCFloppy/Floppy.drvproj/English.lproj/Help/TableOfContents.rtf`
- Modify: `src/drivers-i386/ide/drvPCFloppy/Floppy.drvproj/PB.project`

**Interfaces:**
- Consumes: nothing.
- Produces: resources that `vm/build-i386-floppy.sh` already copies — its `if [ -d "$SRC/$proj/English.lproj" ]` branch has been dormant until now.

- [ ] **Step 1: Copy the reference bundle's localized tree**

```bash
cp -r "C:/Users/raynorpat/Downloads/test/Drivers/i386/Floppy.config/English.lproj" src/drivers-i386/ide/drvPCFloppy/Floppy.drvproj/
```

- [ ] **Step 2: Verify the contents landed**

```bash
find src/drivers-i386/ide/drvPCFloppy/Floppy.drvproj/English.lproj -type f | sort
```

Expected six files: `Localizable.strings`, `Help/TableOfContents.rtf`, and `Help/Floppy.rtfd/` containing `TXT.rtf`, `251243_PixelRule.tiff`, `494393_PixelRule.tiff` and `other.tiff`.

- [ ] **Step 3: Confirm the strings file matches the reference**

```bash
cat src/drivers-i386/ide/drvPCFloppy/Floppy.drvproj/English.lproj/Localizable.strings
```

Expected exactly:

```
"Floppy" = "Floppy Disk";
"Long Name" = "Floppy Disk Drive";
```

- [ ] **Step 4: Register the resources in `PB.project`**

In `src/drivers-i386/ide/drvPCFloppy/Floppy.drvproj/PB.project`, change:

```
        OTHER_RESOURCES = (Default.table);
```

to:

```
        OTHER_RESOURCES = (Default.table, "English.lproj");
```

and change:

```
    LOCALIZABLE_FILES = {};
```

to:

```
    LOCALIZABLE_FILES = {"Localizable.strings" = "Localizable.strings"; };
```

- [ ] **Step 5: Commit**

```bash
git add src/drivers-i386/ide/drvPCFloppy/Floppy.drvproj
git commit -m "drvPCFloppy: add the English.lproj resources from Apple's bundle

Localizable.strings and the Floppy.rtfd help tree were missing entirely."
```

---

### Task 9: Build checkpoint — the pre-pass complete

Integration gate for Tasks 6, 7 and 8, and the last build before the report pass. The rebuilt binary this produces is the one the report pass compares against.

**Files:** none modified.

**Interfaces:**
- Consumes: the working tree from Tasks 6–8.
- Produces: the `Floppy_reloc` that Task 11's profile resolves as `${BINRECON_REBUILT}`.

- [ ] **Step 1: Hand off to the user**

Ask the user to run `vm/build-i386-floppy.sh` and return `/tmp/Floppy.log` plus the staged `Floppy_reloc` and `Floppy.config` contents. Wait.

- [ ] **Step 2: Confirm the build succeeded and staged the resources**

Expect `make exit=0` in the log, and the `ls -la` at the end of the script listing `English.lproj` alongside `Default.table` and `Floppy_reloc`. A missing `English.lproj` means Task 8 step 4 did not take effect.

- [ ] **Step 3: Re-measure the three axes**

```bash
PYTHONPATH=tools/binrecon .venv-binrecon/Scripts/python.exe tools/binrecon/parity_check.py "C:/Users/raynorpat/Downloads/test/Drivers/i386/Floppy.config/Floppy_reloc" out/i386/drvPCFloppy/Floppy.config/Floppy_reloc | grep -E "^[a-z_]+ \("
PYTHONPATH=tools/binrecon .venv-binrecon/Scripts/python.exe tools/binrecon/import_check.py "C:/Users/raynorpat/Downloads/test/Drivers/i386/Floppy.config/Floppy_reloc" out/i386/drvPCFloppy/Floppy.config/Floppy_reloc | grep -E "^missing_imports"
```

Expected: `missing_symbols` about 20 — the 17 C functions of spec §2.3 plus the 3 build-generated names — and `missing_imports (6)`, the category name having been resolved by Task 6. Both must be at or below the Task 5 numbers; a rise is a regression in Tasks 6–8.

- [ ] **Step 4: Record the numbers**

Carry all four forward to Task 12, which writes them into `divergences.md` as the state the fix phases start from.

---

### Task 10: Add the binrecon profile

Spec §3.1. Unlike every other committed i386 profile this one carries a `rebuilt` block, because we have a staged rebuild and can therefore run a real comparison rather than a reference-only analysis.

**Files:**
- Create: `tools/binrecon/profiles/floppy.json`

**Interfaces:**
- Consumes: `${BINRECON_REFERENCE}` and `${BINRECON_REBUILT}` from the environment.
- Produces: the profile path that Tasks 11 and 12 pass to `--profile`.

- [ ] **Step 1: Write the profile**

Create `tools/binrecon/profiles/floppy.json`:

```json
{
  "schema_version": "profile-v1",
  "name": "drvPCFloppy reconstruction",
  "architecture": "i386",
  "endianness": "little",
  "reference": {
    "path": "${BINRECON_REFERENCE}"
  },
  "rebuilt": {
    "path": "${BINRECON_REBUILT}"
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
  "output_dir": "../out/floppy"
}
```

- [ ] **Step 2: Set both artifact paths for this shell session**

```bash
export BINRECON_REFERENCE='C:\Users\raynorpat\Downloads\test\Drivers\i386\Floppy.config\Floppy_reloc'
export BINRECON_REBUILT="$PWD/out/i386/drvPCFloppy/Floppy.config/Floppy_reloc"
```

- [ ] **Step 3: Validate the profile resolves both artifacts**

```bash
PYTHONPATH=tools/binrecon .venv-binrecon/Scripts/python.exe -m binrecon validate --profile tools/binrecon/profiles/floppy.json
```

Expected: both absolute paths, sizes and SHA-256 identities printed, exit 0. The reference is 124,956 bytes. An "unset variable" error means Step 2 was skipped.

- [ ] **Step 4: Commit**

```bash
git add tools/binrecon/profiles/floppy.json
git commit -m "binrecon: add the drvPCFloppy profile

Carries a rebuilt block as well as a reference, since drvPCFloppy already stages a guest build."
```

---

### Task 11: Analyze the reference and build the source map

Spec §4.2 steps 1 and 2.

**Files:**
- Create: `src/drivers-i386/ide/drvPCFloppy/reconstruction/source-map.json`
- Generated, not committed: everything under `tools/binrecon/out/floppy/`

**Interfaces:**
- Consumes: `tools/binrecon/profiles/floppy.json` from Task 10.
- Produces: `source-map.json` conforming to `source-map-v1`, with all 225 reference functions partitioned across `mapped`, `unmapped`, `boundary_disputed` and `duplicate_candidates`. Task 12 reads it.

- [ ] **Step 1: Run the analyzers**

```bash
PYTHONPATH=tools/binrecon .venv-binrecon/Scripts/python.exe -m binrecon analyze --profile tools/binrecon/profiles/floppy.json --output tools/binrecon/out/floppy/run-summary.json
```

Expected: IDA 9.2 and angr 9.3.0 analyses plus `consensus-reference.json` under `tools/binrecon/out/floppy/`, and **exit status 1**. That is correct, not a failure: `normalized-functions` acceptance cannot pass while our unstripped 791 KB build is compared against a 125 KB reference. Confirm `run-summary.json` exists and names both analyzers before continuing. An exit status of 1 with no summary written *is* a failure — investigate that.

- [ ] **Step 2: Build the source map**

```bash
PYTHONPATH=tools/binrecon .venv-binrecon/Scripts/python.exe -m binrecon source-map \
  --reference-analysis tools/binrecon/out/floppy/consensus-reference.json \
  --binary "C:/Users/raynorpat/Downloads/test/Drivers/i386/Floppy.config/Floppy_reloc" \
  --source-dir src/drivers-i386/ide/drvPCFloppy/Floppy.drvproj/Floppy.lksproj \
  --repo-root . \
  --objc-methods \
  --output src/drivers-i386/ide/drvPCFloppy/reconstruction/source-map.json
```

`--objc-methods` resolves names from the Objective-C metadata as well as the symbol table, which matters here because 196 of the 225 functions are methods.

- [ ] **Step 3: Hand-resolve the residue**

Every reference function must land in exactly one bucket. Assign reason classes to the `unmapped` entries:

- `absent-from-sources` — the 17 C functions of spec §2.3: `FloppyControllerThread`, `OperationThreadStartup`, `HandleBsdWrite`, `docopy`, `dowire`, `fakeStrategySuccess`, `fdTimer`, `floppyDriveType`, `identifyBsdDev`, `identifyDetachedDiskIdFromBsdDev`, `numFloppyDrives`, `physContBlocks`, `queueOperationAscending`, `queueOperationDecending`, `sweepQueueInsert`, `sweepQueueReorder`, `vFloppyCopy`.
- `build-generated` — `__udivdi3`, `+[FloppyKernelServerInstance kernelServerInstance]`, `+[FloppyVersion driverKitVersionForFloppy]`.

Anything else unmapped is a mapping gap to resolve by hand, not to reclassify.

- [ ] **Step 4: Verify the map loads under the semantic loader**

```bash
PYTHONPATH=tools/binrecon .venv-binrecon/Scripts/python.exe -c "
from binrecon.source_map import load_source_map
m = load_source_map(
    'src/drivers-i386/ide/drvPCFloppy/reconstruction/source-map.json',
    reference_analysis='tools/binrecon/out/floppy/consensus-reference.json',
    repo_root='.')
print('functions:', sum(len(m[k]) for k in ('mapped','unmapped','boundary_disputed','duplicate_candidates') if k in m))
"
```

Expected: no exception, and a total of 225. The loader enforces the complete partition, names, full function sizes and source-line bounds, so a clean load is the gate. If the import path differs, find it with `grep -rn "def load_source_map" tools/binrecon/`.

- [ ] **Step 5: Commit**

```bash
git add src/drivers-i386/ide/drvPCFloppy/reconstruction/source-map.json
git commit -m "drvPCFloppy: map every reference function to our sources

All 225 functions partitioned; the 17 absent C functions and 3 build-generated entries are recorded as unmapped with reasons."
```

---

### Task 12: Write the divergence report and the parity ledger

Spec §4.2 steps 3 to 5. This is the deliverable the fix phases work from.

**Files:**
- Create: `src/drivers-i386/ide/drvPCFloppy/reconstruction/divergences.md`
- Create: `src/drivers-i386/ide/drvPCFloppy/reconstruction/ledger.json`

**Interfaces:**
- Consumes: `source-map.json` from Task 11; the parity numbers from Tasks 5 and 9.
- Produces: `divergences.md` and a `ledger-v1` ledger with an entry for all 225 functions. The fix-phase plan written in Task 13 is derived entirely from these two files.

- [ ] **Step 1: Decompile and diff every mapped function**

Work file by file, in the phase order spec §4.3 sets: `FloppyCnt.m`, `FloppyCntIo.m`, `FloppyCmds.m`, `FloppyArch.m`, then the generic disk family, then drive, then disk and geometry, then `Bsd.m`. For each function compare control-flow shape, literal constants, I/O port addresses, struct field offsets and call targets against our source.

- [ ] **Step 2: Confirm the tables are clean**

```bash
diff "C:/Users/raynorpat/Downloads/test/Drivers/i386/Floppy.config/Default.table" src/drivers-i386/ide/drvPCFloppy/Floppy.drvproj/Default.table
diff "C:/Users/raynorpat/Downloads/test/Drivers/i386/Floppy.config/English.lproj/Localizable.strings" src/drivers-i386/ide/drvPCFloppy/Floppy.drvproj/English.lproj/Localizable.strings
```

Expected: only the `"Driver Version"` hunk, and no difference at all for the strings. A residual difference is a Task 7 or Task 8 defect, not a new finding.

- [ ] **Step 3: Write `divergences.md`**

Structure it as: the post-pre-pass baseline numbers from Task 9 (`missing_symbols`, `missing_strings`, `missing_imports`, and the extras for context); then one section per fix phase from spec §4.3; then within each, one entry per finding giving the reference decompilation beside our source and the reason it diverges. Record the reason class for every `unmapped` entry from Task 11 here too — spec §4.2's "done when" requires it.

- [ ] **Step 4: Create the ledger with an entry per function**

Assign each of the 225 functions a status. A function whose evidence supports it gets the strongest of `signature-confirmed`, `control-flow-confirmed` or `assembly-matched`. A function that diverges stays `unexamined` and gets a `divergences.md` entry — that is the drvPCIBus convention, and the ledger records parity confidence rather than a repair queue. Use `--source-path` and `--source-line` together; they are required as a pair.

```bash
PYTHONPATH=tools/binrecon .venv-binrecon/Scripts/python.exe -m binrecon ledger \
  --profile tools/binrecon/profiles/floppy.json \
  --ledger src/drivers-i386/ide/drvPCFloppy/reconstruction/ledger.json \
  --address 0x0 --status signature-confirmed \
  --source-path src/drivers-i386/ide/drvPCFloppy/Floppy.drvproj/Floppy.lksproj/Bsd.m --source-line 1134
```

That example is `+[IOFloppyDisk(Bsd) driveNumberOfDrive:]`, the function at address 0. Repeat per function, taking addresses from `source-map.json`.

- [ ] **Step 5: Verify the ledger is complete**

```bash
PYTHONPATH=tools/binrecon .venv-binrecon/Scripts/python.exe -m binrecon ledger \
  --profile tools/binrecon/profiles/floppy.json \
  --ledger src/drivers-i386/ide/drvPCFloppy/reconstruction/ledger.json
```

Expected: 225 entries, none missing. Unlike the earlier drivers `rebuilt_sha256` is a real hash here, not `null`, because the profile carries a rebuilt artifact.

- [ ] **Step 6: Commit**

```bash
git add src/drivers-i386/ide/drvPCFloppy/reconstruction
git commit -m "drvPCFloppy: record the parity ledger and divergences

Every reference function carries a status; the report pass is the baseline the fix phases work from."
```

---

### Task 13: Write the fix-phase plan

The five fix phases of spec §4.3 could not be specified before `divergences.md` existed. Now it does.

**Files:**
- Create: `docs/superpowers/plans/2026-07-25-drvpcfloppy-fix-phases.md`

**Interfaces:**
- Consumes: `divergences.md` and `ledger.json` from Task 12.
- Produces: the plan that carries the work to the spec §5 done bar.

- [ ] **Step 1: Re-read the spec's fix-phase section**

Spec §4.3 fixes the phase order and membership: controller (28 functions), generic disk family (83), drive (50), disk and geometry (50), BSD (11). The controller leads as the smallest independent phase; the generic family precedes drive and disk because they inherit from it.

- [ ] **Step 2: Derive one task per finding group**

Each phase becomes a task series ending in a build checkpoint, a `parity_check.py` and `import_check.py` run, and a ledger advance. Per spec §4.3 a phase that raises any of the three counts is a regression and does not commit.

- [ ] **Step 3: Carry the done bar forward verbatim**

Spec §5: build green; `missing_symbols` 0 but for the three build-generated entries; `missing_strings` 0 or each remainder dispositioned `intentional-mismatch` with a reason and reviewer; the import gap dispositioned the same way; `load_source_map` passes; all 225 functions at `signature-confirmed` or better, or `intentional-mismatch`.

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/plans/2026-07-25-drvpcfloppy-fix-phases.md
git commit -m "docs: implementation plan for the drvPCFloppy fix phases"
```
