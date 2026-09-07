# drvPCFloppy Invented Symbol Removal — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `drvPCFloppy` export the same symbol set as Apple's `Floppy_reloc`, and fix the live memory-corruption bug in `IOFloppyDrive`.

**Architecture:** Five independent corrections to an existing driver. The largest gives the untyped 40-byte operation record a real struct type so Mach's inlining queue macros can replace three hand-written helper functions. The rest invert the storage class on eight data objects, delete a duplicate method override, and add one ivar.

**Tech Stack:** Objective-C for the NeXT/Rhapsody DriverKit, GCC 2.x, `<kernserv/queue.h>`. Reference binary at `C:/Users/raynorpat/Downloads/test/Drivers/i386/Floppy.config/Floppy_reloc`. Build artifact at `out/i386/drvPCFloppy/Floppy.config/Floppy_reloc`.

**Spec:** [2026-09-07-floppy-invented-symbol-removal-design.md](../specs/2026-09-07-floppy-invented-symbol-removal-design.md)

## Global Constraints

- **Working directory:** `src/drivers-i386/ide/drvPCFloppy/Floppy.drvproj/Floppy.lksproj/` unless stated otherwise. Referred to below as *the driver directory*.
- **You cannot build.** The build runs on a Rhapsody guest and is performed by the user. Never claim a change is verified by compilation. Task 9 is the only build gate and requires the user to build first.
- **All source files use CRLF line endings.** Multi-line string matching in Python must open files with `newline=''` and match `\r\n`, or match single lines only. `git commit` will warn about CRLF conversion; that warning is expected and not an error.
- **Another agent commits to this repository.** Stage only your own files by explicit path. Never `git add -A`, never `git commit -a`.
- **Commit messages:** short, subsystem-prefixed (`drvPCFloppy: `), one to two lines, no metadata, no trailers, no `Co-Authored-By`.
- **There is no unit-test framework in this driver.** Each task's verification is a static check — a `grep` whose output is stated exactly — except Task 9, which compares binary symbol tables.
- **Do not touch** `FloppyController` or `IOFloppyDrive`'s existing ivars beyond the single addition in Task 8. Those classes are reconstructed in later pieces.

---

### Task 1: Document the operation record's field map

The 40-byte record allocated by `IOMalloc(0x28)` is accessed as `operation[0]`…`operation[9]` in 76 places. Before it can be typed, its fields must be identified from use. This task produces the field map that Task 2 turns into a struct.

**Files:**
- Create: `src/drivers-i386/ide/drvPCFloppy/reconstruction/operation-record.md`

**Interfaces:**
- Produces: the field map consumed by Task 2's struct definition. Field names fixed here are used verbatim in Tasks 2–5.

- [ ] **Step 1: Confirm the link words, because the source comments are wrong**

Run, from the driver directory:

```bash
grep -n "nextOp\|prevOp" Thread.m | head -6
```

Expected output includes:

```
	nextOp = (unsigned int *)operation[8];
	prevOp = (unsigned int *)operation[9];
```

`dequeueOperation` therefore treats **[8] as next and [9] as prev**. Several comments in `IOFloppyDisk.m` and `Request.m` label `operation[8]` as "prev" and `operation[9]` as "next". Those comments are wrong. `queue_chain_t` is `struct queue_entry { next; prev; }`, so [8],[9] map onto it directly with no reordering.

- [ ] **Step 2: Record the field map**

Create `src/drivers-i386/ide/drvPCFloppy/reconstruction/operation-record.md` with exactly this content:

```markdown
# The floppy operation record

`IOMalloc(0x28)` — 40 bytes, queued on `IOFloppyDisk`'s `_queueHead`/`_queueTail`
and consumed by the operation thread. Allocated at `IOFloppyDisk.m:99`,
`Request.m:242` and `Request.m:921`; also `Bsd.m:330` and `Bsd.m:476`, which
cast it to `id`.

| Word | Byte | Field | Evidence |
| --- | --- | --- | --- |
| [0] | 0  | `type`           | `= 1` write cylinder (`Request.m:924`), `= 4` abort and exit thread (`IOFloppyDisk.m:100`); read as `operationType` |
| [1] | 4  | `cylinder`       | `= cylinderNumber` (`Request.m:927`); used as the queue sort key |
| [2] | 8  | `flag2`          | assigned only the constants 0 and 1; purpose not yet determined |
| [3] | 12 | `lock3`          | receives `unlockWith:0`; an object |
| [4] | 16 | `completionLock` | `= (unsigned)completionLock`, an `NXConditionLock` (`IOFloppyDisk.m:105`); receives `unlockWith:0` |
| [5] | 20 | `capacity`       | passed to `+[IOFloppyDisk geometryOfCapacity:]`; stored into `_capacity` |
| [6] | 24 | `result`         | `= success`; read as `formatPending` |
| [7] | 28 | `lock7`          | receives `unlockWith:0`; an object |
| [8] | 32 | `link.next`      | `nextOp = operation[8]` in `dequeueOperation` |
| [9] | 36 | `link.prev`      | `prevOp = operation[9]` in `dequeueOperation` |

**The comments in the source are wrong about [8] and [9].** `IOFloppyDisk.m`
and `Request.m` annotate `operation[8]` as "prev" and `operation[9]` as "next".
`dequeueOperation` is authoritative and reads them the other way. Words 8 and 9
therefore correspond, in order, to `queue_chain_t`'s `next` and `prev`.

`flag2`, `lock3` and `lock7` are named for their observed use rather than a
recovered meaning. Three separate lock-like fields is unexpected; if a later
pass determines what they are, rename them here first.
```

- [ ] **Step 3: Verify the file exists and is complete**

Run, from the repository root:

```bash
grep -c "^| \[" src/drivers-i386/ide/drvPCFloppy/reconstruction/operation-record.md
```

Expected output: `10`

- [ ] **Step 4: Commit**

```bash
git add src/drivers-i386/ide/drvPCFloppy/reconstruction/operation-record.md
git commit -m "drvPCFloppy: document the operation record's field map"
```

---

### Task 2: Define the operation struct and convert IOFloppyDisk.m

**Files:**
- Create: `src/drivers-i386/ide/drvPCFloppy/Floppy.drvproj/Floppy.lksproj/FloppyOperation.h`
- Modify: `src/drivers-i386/ide/drvPCFloppy/Floppy.drvproj/Floppy.lksproj/IOFloppyDisk.m` (6 indexed accesses)

**Interfaces:**
- Consumes: the field map from Task 1.
- Produces: `floppyOperation_t` with members `type`, `cylinder`, `flag2`, `lock3`, `completionLock`, `capacity`, `result`, `lock7`, `link`. Tasks 3, 4 and 5 use these names verbatim.

- [ ] **Step 1: Create the header**

Create `FloppyOperation.h` in the driver directory:

```objc
/*
 * The operation record queued on IOFloppyDisk's operation thread.
 *
 * Forty bytes, allocated with IOMalloc(0x28).  The layout is fixed by the
 * existing code, which indexed it as operation[0] through operation[9];
 * see reconstruction/operation-record.md for the evidence behind each name.
 *
 * link occupies words 8 and 9, in that order, which is exactly
 * queue_chain_t's { next, prev } -- so the Mach queue macros operate on
 * this record directly.
 */

#ifndef _FLOPPYOPERATION_H_
#define _FLOPPYOPERATION_H_

#import <kernserv/queue.h>
#import <objc/objc.h>

typedef struct floppyOperation {
	unsigned int	type;			/* 1 = write cylinder, 4 = abort */
	unsigned int	cylinder;		/* queue sort key */
	unsigned int	flag2;			/* 0 or 1 */
	id		lock3;
	id		completionLock;		/* NXConditionLock */
	unsigned int	capacity;
	unsigned int	result;
	id		lock7;
	queue_chain_t	link;			/* words 8 and 9: next, prev */
} floppyOperation_t;

#endif /* _FLOPPYOPERATION_H_ */
```

- [ ] **Step 2: Verify the struct is 40 bytes by inspection**

Nine members: four `unsigned int` (16 bytes), three `id` (12), one
`queue_chain_t` (8) = 36, plus `capacity` and `result` already counted — count
them explicitly: `type` 4, `cylinder` 4, `flag2` 4, `lock3` 4,
`completionLock` 4, `capacity` 4, `result` 4, `lock7` 4, `link` 8 = **40**.

Run, from the driver directory:

```bash
grep -c "^	\(unsigned int\|id\|queue_chain_t\)" FloppyOperation.h
```

Expected output: `9`

- [ ] **Step 3: Import the header in IOFloppyDisk.m**

In `IOFloppyDisk.m`, immediately after the existing `#import "IOFloppyDisk.h"` line, add:

```objc
#import "FloppyOperation.h"
```

- [ ] **Step 4: Convert IOFloppyDisk.m's six accesses**

In `IOFloppyDisk.m`, change the declaration of `operation` in the method
containing the abort path from `unsigned *operation;` to
`floppyOperation_t *operation;`, then replace the indexed accesses:

| Was | Becomes |
| --- | --- |
| `operation = (unsigned *)IOMalloc(0x28);` | `operation = (floppyOperation_t *)IOMalloc(sizeof(floppyOperation_t));` |
| `operation[0] = 4;` | `operation->type = 4;` |
| `operation[4] = (unsigned)completionLock;` | `operation->completionLock = completionLock;` |
| `operation[8] = (unsigned)queueHead;` | `operation->link.next = (queue_entry_t)queueHead;` |
| `operation[9] = (unsigned)queueHead;` | `operation->link.prev = (queue_entry_t)queueHead;` |

Delete the two misleading `// prev` and `// next` comments on the link
assignments; the field names now say which is which.

- [ ] **Step 5: Verify no indexed accesses remain in this file**

Run, from the driver directory:

```bash
grep -c "operation\[[0-9]\]" IOFloppyDisk.m
```

Expected output: `0`

- [ ] **Step 6: Commit**

```bash
git add src/drivers-i386/ide/drvPCFloppy/Floppy.drvproj/Floppy.lksproj/FloppyOperation.h src/drivers-i386/ide/drvPCFloppy/Floppy.drvproj/Floppy.lksproj/IOFloppyDisk.m
git commit -m "drvPCFloppy: give the operation record a struct type"
```

---

### Task 3: Convert Request.m's twelve accesses

**Files:**
- Modify: `src/drivers-i386/ide/drvPCFloppy/Floppy.drvproj/Floppy.lksproj/Request.m` (12 indexed accesses)

**Interfaces:**
- Consumes: `floppyOperation_t` from Task 2.

- [ ] **Step 1: Import the header**

In `Request.m`, after the existing imports, add:

```objc
#import "FloppyOperation.h"
```

- [ ] **Step 2: List the accesses to convert**

Run, from the driver directory:

```bash
grep -n "operation\[[0-9]\]\|readOperation\[[0-9]\]" Request.m
```

Expected: 12 lines. Convert each using the Task 1 field map — `[0]`→`type`,
`[1]`→`cylinder`, `[2]`→`flag2`, `[3]`→`lock3`, `[4]`→`completionLock`,
`[5]`→`capacity`, `[6]`→`result`, `[7]`→`lock7`, `[8]`→`link.next`,
`[9]`→`link.prev`.

- [ ] **Step 3: Convert them**

Change each declaration of `operation` and `readOperation` from `unsigned *` to
`floppyOperation_t *`, change both `IOMalloc(0x28)` calls to
`IOMalloc(sizeof(floppyOperation_t))` with a `(floppyOperation_t *)` cast, and
rewrite each indexed access as the corresponding member. Casts of the form
`(unsigned)someObject` assigned into `lock3`, `completionLock` or `lock7` lose
the cast, since those members are now `id`.

Worked example — `Request.m:921-945` becomes:

```objc
		// Allocate write operation structure
		operation = (floppyOperation_t *)IOMalloc(sizeof(floppyOperation_t));

		// Set operation type to 1 (write cylinder)
		operation->type = 1;

		// Set cylinder number
		operation->cylinder = cylinderNumber;

		// Get queue lock
		queueLock = *(id *)((char *)self + 0x158);

		// Lock the queue
		[queueLock lock];

		mainQueue = (id)((char *)self + 0x150);
		queueHead = (int *)((char *)self + 0x150);

		if (*(void **)((char *)self + 0x150) == mainQueue) {
			*(unsigned **)((char *)self + 0x150) = (unsigned *)operation;
			*(unsigned **)((char *)self + 0x154) = (unsigned *)operation;
			operation->link.next = (queue_entry_t)queueHead;
			operation->link.prev = (queue_entry_t)queueHead;
		} else {
			int lastEntry = *(int *)((char *)self + 0x154);
			operation->link.prev = (queue_entry_t)lastEntry;
			operation->link.next = (queue_entry_t)queueHead;
```

The surrounding raw `self + 0x150` access is left exactly as it is; Task 5
replaces that whole block with `queue_enter`. Delete any `// prev` / `// next`
comments on the link assignments — the field names now carry that.

- [ ] **Step 4: Verify**

Run, from the driver directory:

```bash
grep -c "operation\[[0-9]\]\|readOperation\[[0-9]\]" Request.m
```

Expected output: `0`

- [ ] **Step 5: Commit**

```bash
git add src/drivers-i386/ide/drvPCFloppy/Floppy.drvproj/Floppy.lksproj/Request.m
git commit -m "drvPCFloppy: type Request.m's operation accesses"
```

---

### Task 4: Convert Thread.m's fifty-seven accesses

The largest single conversion, and the one that touches the operation thread's
scheduling logic. Convert mechanically; do not restructure any logic.

**Files:**
- Modify: `src/drivers-i386/ide/drvPCFloppy/Floppy.drvproj/Floppy.lksproj/Thread.m` (57 indexed accesses)

**Interfaces:**
- Consumes: `floppyOperation_t` from Task 2.

- [ ] **Step 1: Import the header**

In `Thread.m`, after the existing imports, add:

```objc
#import "FloppyOperation.h"
```

- [ ] **Step 2: Convert every indexed access**

Run, from the driver directory, to enumerate them:

```bash
grep -n "operation\[[0-9]\]\|current\[[0-9]\]\|op\[[0-9]\]" Thread.m
```

Convert each using the Task 1 field map. Note that `Thread.m` also indexes
variables named `current` and `op`, which are the same record type reached
through different locals — those convert identically. Change each such local's
declaration to `floppyOperation_t *`.

Worked examples covering the four shapes that appear in this file:

```objc
	/* plain read */
	operationType = operation[0];              /* was */
	operationType = operation->type;           /* becomes */

	/* sort-key comparison against another record */
	if (current[1] < operation[1])             /* was */
	if (current->cylinder < operation->cylinder)   /* becomes */

	/* object field sent a message */
	[(id)operation[4] unlockWith:0];           /* was */
	[operation->completionLock unlockWith:0];  /* becomes */

	/* link traversal */
	nextOp = (unsigned int *)operation[8];     /* was */
	nextOp = (floppyOperation_t *)operation->link.next;   /* becomes */
```

The `(id)` casts on words 3, 4 and 7 disappear because those members are now
`id`. The link casts change target type because `link.next` is a
`queue_entry_t`.

The three helper functions `queueEmpty`, `dequeueOperation` and
`appendOperationToQueue` still take `id *queueHead` and cast internally. Leave
them alone in this task; Task 5 deletes them.

- [ ] **Step 3: Verify**

Run, from the driver directory:

```bash
grep -c "operation\[[0-9]\]\|current\[[0-9]\]\|op\[[0-9]\]" Thread.m
```

Expected output: `0`

- [ ] **Step 4: Verify the whole driver has no indexed operation access left**

Run, from the driver directory:

```bash
grep -rn "operation\[[0-9]\]\|readOperation\[[0-9]\]\|current\[[0-9]\]\|op\[[0-9]\]" *.m
```

Expected output: no lines.

- [ ] **Step 5: Commit**

```bash
git add src/drivers-i386/ide/drvPCFloppy/Floppy.drvproj/Floppy.lksproj/Thread.m
git commit -m "drvPCFloppy: type Thread.m's operation accesses"
```

---

### Task 5: Replace the three queue helpers with Mach macros

**Files:**
- Modify: `src/drivers-i386/ide/drvPCFloppy/Floppy.drvproj/Floppy.lksproj/Thread.m` (delete 3 functions, rewrite 24 call sites)
- Modify: `src/drivers-i386/ide/drvPCFloppy/Floppy.drvproj/Floppy.lksproj/IOFloppyDisk.m` (queue init and the open-coded append)
- Modify: `src/drivers-i386/ide/drvPCFloppy/Floppy.drvproj/Floppy.lksproj/Request.m` (two open-coded appends)

**Interfaces:**
- Consumes: `floppyOperation_t` from Task 2.

- [ ] **Step 1: Confirm the macro semantics match the helpers**

This is the one change that can break the operation thread, so confirm rather
than assume. Run, from the repository root:

```bash
sed -n '/#define	queue_init/,+2p;/#define	queue_first/,+2p;/#define	queue_end/,+2p;/#define queue_empty/,+2p' src/kernel-7/kernserv/queue.h
```

Expected output includes:

```
#define	queue_init(q)	((q)->next = (q)->prev = q)
#define	queue_first(q)	((q)->next)
#define	queue_end(q, qe)	((q) == (qe))
#define queue_empty(q)		queue_end((q), queue_first(q))
```

`queue_empty(q)` expands to `(q) == (q)->next`, which is exactly what
`queueEmpty` returns. `queue_init` sets both links to the head, which is what
`IOFloppyDisk.m`'s initialisation does. If either differs from this, stop and
report it rather than proceeding.

- [ ] **Step 2: Declare the queue head as a queue_head_t**

In `IOFloppyDisk.h`, replace the two separate pointers:

```objc
	void *_queueHead;                // offset 0x150: operation queue head
	void *_queueTail;                // offset 0x154: operation queue tail
```

with a single chain occupying the same eight bytes:

```objc
	queue_head_t _operationQueue;    // offset 0x150: next, prev
```

and add `#import <kernserv/queue.h>` to `IOFloppyDisk.h`'s imports. This
matches the reference, whose ivar at +336 is
`{?="next"^{queue_entry}"prev"^{queue_entry}} _operationQueue`.

- [ ] **Step 3: Replace the initialisation**

In `IOFloppyDisk.m`, replace:

```objc
	// Initialize operation queue (circular list pointing to itself)
	_queueHead = (void *)((char *)&_queueHead);
	_queueTail = (void *)((char *)&_queueHead);
```

with:

```objc
	queue_init(&_operationQueue);
```

- [ ] **Step 4: Replace the open-coded appends**

In `IOFloppyDisk.m` and in `Request.m` (two sites), each open-coded
empty-or-append block of the form shown in Task 2's step 4 becomes one call:

```objc
	queue_enter(&_operationQueue, operation, floppyOperation_t *, link);
```

In `Request.m` the queue is reached through `self`; use `&self->_operationQueue`
if the expression is not already implicit.

- [ ] **Step 5: Replace the helper call sites in Thread.m**

Rewrite the 24 call sites:

| Was | Becomes |
| --- | --- |
| `queueEmpty(q)` | `queue_empty(q)` |
| `dequeueOperation(q)` | `queue_remove_first(q, operation, floppyOperation_t *, link)` — note this assigns rather than returns; declare `operation` before the call and use it after |
| `appendOperationToQueue(q, operation)` | `queue_enter(q, operation, floppyOperation_t *, link)` |

The queue arguments change type from `id *` to `queue_head_t *`; update the
locals that hold them (`ctlQueue`, `wbAscQueue`, `wbDescQueue`, `rwAscQueue`,
`rwDescQueue` and the like) accordingly.

- [ ] **Step 6: Delete the three helper functions**

Remove the definitions of `queueEmpty`, `dequeueOperation` and
`appendOperationToQueue` from `Thread.m`, together with their comment blocks.

- [ ] **Step 7: Verify**

Run, from the driver directory:

```bash
grep -c "queueEmpty\|dequeueOperation\|appendOperationToQueue" Thread.m
```

Expected output: `0`

```bash
grep -c "_queueHead\|_queueTail" *.m *.h
```

Expected output: `0` for every file.

- [ ] **Step 8: Commit**

```bash
git add src/drivers-i386/ide/drvPCFloppy/Floppy.drvproj/Floppy.lksproj/Thread.m src/drivers-i386/ide/drvPCFloppy/Floppy.drvproj/Floppy.lksproj/IOFloppyDisk.m src/drivers-i386/ide/drvPCFloppy/Floppy.drvproj/Floppy.lksproj/IOFloppyDisk.h src/drivers-i386/ide/drvPCFloppy/Floppy.drvproj/Floppy.lksproj/Request.m
git commit -m "drvPCFloppy: use the Mach queue macros for the operation queue"
```

---

### Task 6: Invert the linkage on the eight data objects

**Files:**
- Modify: `IODiskPartitionNEW.m` (`protocols[]` to file scope; `diskLabelValues` to function-local)
- Modify: `IODiskNew.m` (`diskIoReturnValues[]` to file scope)
- Modify: `Geometry.m` (`fdCommandValues`, `densityValues`, `midValues`, `fdrValues`, `fcOpcodeValues`)
- Modify: `FloppyCmds.m` (`fcOpcodeValues`)
- Modify: `Bsd.m` (`fdIoctlNameValues`)
- Modify: `FloppyDriveInt2.m` (the `extern fdrValues` declaration)

All paths are in the driver directory.

- [ ] **Step 1: Move `protocols[]` to file scope**

In `IODiskPartitionNEW.m`, the array is currently local to
`+[IODiskPartitionNEW requiredProtocols]` at line 48. Move the declaration
above the `@implementation`, leaving the method returning it:

```objc
static const char *protocols[] = {
	"IOPhysicalDiskMethods",
	NULL
};
```

and the method body becomes:

```objc
+ (const char **)requiredProtocols
{
	return protocols;
}
```

- [ ] **Step 2: Move `diskIoReturnValues[]` to file scope**

In `IODiskNew.m`, the table is declared inside a method at line 308. Move the
declaration above the `@implementation` unchanged, keeping its initialiser
exactly as written, and leave the method referring to it.

- [ ] **Step 3: Move the seven name tables to function-local**

For each of `fdCommandValues` (`Geometry.m:228`), `densityValues`
(`Geometry.m:244`), `midValues` (`Geometry.m:258`), `diskLabelValues`
(`IODiskPartitionNEW.m:23`) and `fdIoctlNameValues` (`Bsd.m:106`): move the
declaration inside the single function that reads it, keeping `static const`.

Before moving each one, confirm it has exactly one reader. Run, from the driver
directory, substituting the table name:

```bash
grep -n "fdCommandValues" Geometry.m
```

If a table has more than one reading function in its file, leave it file-static
and record that in the divergence note in Task 9; the symbol only disappears
when the move is genuinely available.

- [ ] **Step 4: Resolve the `fcOpcodeValues` collision**

There are two objects under this name:

```bash
grep -n "fcOpcodeValues" FloppyCmds.m Geometry.m
```

Expected: `FloppyCmds.m:32` declares `static const IONamedValue fcOpcodeValues[]`;
`Geometry.m:291` declares a non-static `unsigned int fcOpcodeValues[]`. Two
different types under one name, and the exported symbol comes from Geometry.m's.

Rename `Geometry.m`'s to `fcOpcodeCodes` — it is an `unsigned int` table, not a
name table — and make it `static`. Update its readers in `Geometry.m`. Leave
`FloppyCmds.m`'s alone in this step; it becomes function-local under Step 3's
rule if it has one reader.

**If the two are read interchangeably anywhere, stop and report it.** That
would mean a consumer is reading data of the wrong shape today, which is a
finding for the divergence record and not something to absorb silently.

- [ ] **Step 5: Give each `fdrValues` consumer its own copy**

`Geometry.m:192` defines `const IONamedValue fdrValues[]` non-static;
`FloppyDriveInt2.m:17` declares it `extern` and reads it at line 546. The
reference exports no such symbol, so it was not shared across translation
units.

Make `Geometry.m`'s copy `static const` and function-local under Step 3's rule.
In `FloppyDriveInt2.m`, delete the `extern` declaration and add a local
`static const IONamedValue fdrValues[]` inside `logRwErr:block:status:readFlag:`
with the same entries as `Geometry.m`'s.

- [ ] **Step 6: Verify no file-scope name tables remain**

Run, from the driver directory:

```bash
grep -n "^static const IONamedValue\|^const IONamedValue" *.m
```

Expected output: no lines.

```bash
grep -n "^static const char \*protocols\|^static.*diskIoReturnValues" *.m
```

Expected: two lines, one in `IODiskPartitionNEW.m` and one in `IODiskNew.m`.

- [ ] **Step 7: Commit**

```bash
git add src/drivers-i386/ide/drvPCFloppy/Floppy.drvproj/Floppy.lksproj/IODiskPartitionNEW.m src/drivers-i386/ide/drvPCFloppy/Floppy.drvproj/Floppy.lksproj/IODiskNew.m src/drivers-i386/ide/drvPCFloppy/Floppy.drvproj/Floppy.lksproj/Geometry.m src/drivers-i386/ide/drvPCFloppy/Floppy.drvproj/Floppy.lksproj/FloppyCmds.m src/drivers-i386/ide/drvPCFloppy/Floppy.drvproj/Floppy.lksproj/Bsd.m src/drivers-i386/ide/drvPCFloppy/Floppy.drvproj/Floppy.lksproj/FloppyDriveInt2.m
git commit -m "drvPCFloppy: give the name tables and protocol lists the reference's linkage"
```

---

### Task 7: Delete the duplicate isAnyOtherOpen

**Files:**
- Modify: `src/drivers-i386/ide/drvPCFloppy/Floppy.drvproj/Floppy.lksproj/IODiskPartitionNEW.m` (delete method at line 978)
- Modify: `src/drivers-i386/ide/drvPCFloppy/Floppy.drvproj/Floppy.lksproj/IODiskPartitionNEW.h` (delete declaration)

- [ ] **Step 1: Confirm the inherited implementation exists and is equivalent**

Run, from the driver directory:

```bash
sed -n '/- (BOOL)isAnyOtherOpen/,/^}/p' IOLogicalDiskNEW.m
```

Expected: a method walking the logical-disk chain via `nextLogicalDisk` and
returning `YES` on the first partition whose `isRawDeviceOpen` is true — the
same algorithm as `IODiskPartitionNEW.m:978`. If the two differ in behaviour,
stop and report it; deleting the override would then be a behaviour change.

- [ ] **Step 2: Delete the override**

Remove the whole `- (BOOL)isAnyOtherOpen` method from `IODiskPartitionNEW.m`,
including its comment block, and remove its declaration from
`IODiskPartitionNEW.h`'s `(Private)` category.

The one caller, `IODiskPartitionNEW.m:941`, is unchanged — `[self
isAnyOtherOpen]` now reaches the inherited implementation.

- [ ] **Step 3: Verify**

Run, from the driver directory:

```bash
grep -n "isAnyOtherOpen" IODiskPartitionNEW.m IODiskPartitionNEW.h IOLogicalDiskNEW.m
```

Expected: exactly two lines — the call at `IODiskPartitionNEW.m:941` and the
definition in `IOLogicalDiskNEW.m`.

- [ ] **Step 4: Commit**

```bash
git add src/drivers-i386/ide/drvPCFloppy/Floppy.drvproj/Floppy.lksproj/IODiskPartitionNEW.m src/drivers-i386/ide/drvPCFloppy/Floppy.drvproj/Floppy.lksproj/IODiskPartitionNEW.h
git commit -m "drvPCFloppy: drop IODiskPartitionNEW's duplicate isAnyOtherOpen"
```

---

### Task 8: Add lastAccess to IOFloppyDrive and fix the corruption

`IOGetTimestamp` writes eight bytes at `self + 0x170`, which in our layout is
`_numHeads` at +368 and `_flags` at +372. Every timestamp write destroys both.

**Files:**
- Modify: `src/drivers-i386/ide/drvPCFloppy/Floppy.drvproj/Floppy.lksproj/IOFloppyDrive.h` (add ivar)
- Modify: `src/drivers-i386/ide/drvPCFloppy/Floppy.drvproj/Floppy.lksproj/FloppyDriveInt.m:669`
- Modify: `src/drivers-i386/ide/drvPCFloppy/Floppy.drvproj/Floppy.lksproj/FloppyDriveInt2.m:588-589`

- [ ] **Step 1: Add the ivar**

In `IOFloppyDrive.h`, add as the **last** member of the ivar block, so no
existing offset moves:

```objc
	unsigned long long lastAccess;   /* reference: +368; placed at the end
					  * until Piece C rebuilds this class */
```

- [ ] **Step 2: Fix the write site**

In `FloppyDriveInt.m` line 669, replace:

```objc
	IOGetTimestamp((unsigned long long *)((char *)self + 0x170));
```

with:

```objc
	IOGetTimestamp(&lastAccess);
```

- [ ] **Step 3: Fix the read sites**

In `FloppyDriveInt2.m` lines 588-589, replace:

```objc
	lastTimeLow = *(unsigned *)((char *)self + 0x170);
	lastTimeHigh = *(unsigned *)((char *)self + 0x174);
```

with:

```objc
	lastTimeLow = (unsigned)lastAccess;
	lastTimeHigh = (unsigned)(lastAccess >> 32);
```

- [ ] **Step 4: Verify no raw access to 0x170 or 0x174 remains**

Run, from the driver directory:

```bash
grep -rn "0x170\|0x174" *.m
```

Expected output: no lines.

- [ ] **Step 5: Commit**

```bash
git add src/drivers-i386/ide/drvPCFloppy/Floppy.drvproj/Floppy.lksproj/IOFloppyDrive.h src/drivers-i386/ide/drvPCFloppy/Floppy.drvproj/Floppy.lksproj/FloppyDriveInt.m src/drivers-i386/ide/drvPCFloppy/Floppy.drvproj/Floppy.lksproj/FloppyDriveInt2.m
git commit -m "drvPCFloppy: give IOFloppyDrive a real lastAccess field

The timestamp was written through a raw offset that lands on _numHeads
and _flags in our layout, destroying both on every access."
```

---

### Task 9: Build and verify against the reference symbol table

**This task requires the user to build the driver.** Ask, and wait. Do not
claim any part of this plan is verified before the build completes.

**Files:**
- Modify: `src/drivers-i386/ide/drvPCFloppy/reconstruction/divergences.md` (record the outcome)

- [ ] **Step 1: Ask the user to build**

Tell the user that Tasks 1–8 are committed and the driver needs building on the
Rhapsody guest before verification can run. Note that six earlier changes across
four drivers are also unbuilt, three of which alter class inheritance, so a
build failure may originate outside this plan.

- [ ] **Step 2: Compare the symbol tables**

Run, from the repository root:

```bash
PYTHONPATH=tools/binrecon PYTHONIOENCODING=ascii:replace ./.venv-binrecon/Scripts/python.exe -c "
from binrecon.macho import read_macho
import re
def syms(p, want):
    m=read_macho(p); out=set()
    for s in m.get('symbols',[]):
        n=s.get('name') or ''; sec=s.get('section') or ''
        if not n or not sec: continue
        if ':' in n or n.startswith('/') or n.endswith('.c') or n.endswith('.m'): continue
        if not re.match(r'^[_+\-\[A-Za-z]', n): continue
        if want in sec.lower(): out.add(n)
    return out
R='C:/Users/raynorpat/Downloads/test/Drivers/i386/Floppy.config/Floppy_reloc'
N='out/i386/drvPCFloppy/Floppy.config/Floppy_reloc'
for sect in ('text','data'):
    r,n=syms(R,sect),syms(N,sect)
    print(f'--- __{sect} ---')
    print(f'  reference-only: {sorted(r-n)}')
    print(f'  ours-only:      {sorted(n-r)}')
"
```

Expected `__text`: `ours-only` is empty. `reference-only` contains
`_Floppy_VERS_NUM`, `_Floppy_VERS_STRING`, and possibly `___clz_tab` and
`__udivdi3`.

Expected `__data`: `_protocols` and `_diskIoReturnValues` present on both sides;
`_protocols.82` and `_diskIoReturnValues.126` gone from ours. `reference-only`
still contains `_fcUnitNum`, `_ssi_1mb`, `_ssi_2mb`, `_ssi_4mb`, which are out
of scope and belong to Pieces B and C.

- [ ] **Step 3: Confirm IOFloppyDrive grew by exactly eight bytes**

Run, from the repository root:

```bash
PYTHONPATH=tools/binrecon PYTHONIOENCODING=ascii:replace ./.venv-binrecon/Scripts/python.exe -c "
import struct
from binrecon.macho import read_macho
m=read_macho('out/i386/drvPCFloppy/Floppy.config/Floppy_reloc')
data=open('out/i386/drvPCFloppy/Floppy.config/Floppy_reloc','rb').read()
secs=[(s['name'],s['address'],s['size'],s['offset']) for s in m['sections']]
S={s['name']:s for s in m['sections']}
def a2o(a):
    for n,ad,sz,off in secs:
        if ad<=a<ad+sz: return off+(a-ad)
def cstr(a):
    o=a2o(a); return data[o:data.index(b'\0',o)].decode('ascii','replace')
cs=S['__OBJC,__class']; base=a2o(cs['address'])
for i in range(cs['size']//40):
    r=struct.unpack_from('<10I',data,base+i*40)
    if cstr(r[2])=='IOFloppyDrive': print('IOFloppyDrive instance_size =', r[5])
"
```

Expected output: `IOFloppyDrive instance_size = 424` — 416 plus the eight-byte
`lastAccess`. Still short of the reference's 444, which Piece C addresses.

- [ ] **Step 4: Record the outcome**

Append a section to
`src/drivers-i386/ide/drvPCFloppy/reconstruction/divergences.md` stating: which
symbols converged; any table that had to stay file-static because it had more
than one reader; whether the `fcOpcodeValues` collision exposed a consumer
reading the wrong shape; and whether `___clz_tab`/`__udivdi3` appeared once
`lastAccess` became a real 64-bit field.

- [ ] **Step 5: Commit**

```bash
git add src/drivers-i386/ide/drvPCFloppy/reconstruction/divergences.md
git commit -m "drvPCFloppy: record the invented-symbol removal verification"
```
