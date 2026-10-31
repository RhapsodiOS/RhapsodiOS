# NSRunLoop Timer Vector Ordering

## Goal

Make `NSRunLoop` timer insertion expose the same vector pointer and count at each reentrant or throwing timer-retain callback as both i386 and PPC Foundation targets.

## Evidence

The paired IDA bodies are `-[NSRunLoop addTimer:forMode:]` (i386 `0x4252504c`, PPC `0x4254267c`) and `insertTimer` (i386 `0x4251ee8c`, PPC `0x42545a7c`). Both targets publish a newly allocated vector to `_timers` before insertion. In insertion, both publish a reallocated vector after retaining the timer and increment the vector count before sending `retain` to the timer. The source currently keeps a new vector local until the helper returns, increments the count after retaining timer and modes, and publishes the pointer at the end.

## Design

Change only `NSRunLoop.m` and its paired source-map anchors. In `addTimer:forMode:`, store a newly allocated vector in `_timers` before insertion and pass the ivar-backed pointer through the existing helper argument. For a new timer entry, `NSRunLoopInsertTimer` must insert the timer pointer and mode pointer as separate vector elements, matching target count/capacity updates before each retain callback. After shifting for the timer slot, increment the vector count, retain and store the timer, and publish the possibly reallocated vector through `timerVector`. If `combineModes` is true, combine the mode after the timer slot is stored and published. Then increment count for the mode slot, retain and store the mode, and publish the current vector. Preserve duplicate detection and its mode-combination path, insertion-point selection, firing order, and the existing retained ownership of timer and modes. Apply the helper's ordering consistently at both existing call sites: normal addition and reinsertion after firing.

## Scope and verification

Do not change timer comparisons, duplicate handling, insertion-point selection, or callback scheduling. Match the two target slot-insertion phases including the `combineModes` call between them. Update only source-line anchors made stale by the `NSRunLoop.m` edit and record the paired correction in `reconstruction/divergences.md`. Verify the two target maps still point to the same four IDA functions and resolve their source anchors to the edited methods. Static paired IDA/source-map review only; no tests or builds.
