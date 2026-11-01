# Foundation `NSUndoManagerPrivate` category owner correction

`NSUndoManager.m` already contains IDA-derived implementations for the five
private selectors in `reconstruction/abi/NSUndoManager.json`, but they were
defined inside the flat `NSUndoManager` implementation. The ABI assigns them
to `NSUndoManager(NSUndoManagerPrivate)`.

Moved `_setGroupIdentifier:`, `_registerUndoObject:`,
`_postCheckpointNotification`, `_processEndOfEventNotification:`, and
`_prepareEventGrouping` into that exact category without changing their
bodies. Static exact-owner and whitespace checks only; no tests or builds were
run.
