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
