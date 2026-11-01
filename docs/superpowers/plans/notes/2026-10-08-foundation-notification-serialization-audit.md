# Foundation notification removal serialization audit (2026-10-08)

Compared the PPC notification center source with the MOSXS Foundation IDA
database.

- `_postNotification` at `0x425270b0` registers its stack-local post record
  while `__NSNotificationCenterSerializeRemoves` is enabled, unlocks around
  observer delivery, then reacquires the lock, unlinks the post record,
  broadcasts, and unlocks. The source's `NSNotificationCenterBeginPost`,
  `NSNotificationCenterEndPost`, and `NSNotificationCenterDeliver` follow
  that lock and post-record lifecycle.
- `removeObserver:name:object:` at `0x4251cb34` locks the center, calls
  `wait_while_posting` when serialization is enabled, removes matching
  records, updates the observer tables, and unlocks. The source waits under
  the same lock before mutating the registry.
- `wait_while_posting` at `0x42581508` loops on `is_in_posting` and waits on
  the center condition. `is_in_posting` at `0x425811f8` ignores same-thread
  posts after nulling matching entries in their snapshots, and returns true
  for a matching observer in another thread. The source helpers mirror this
  behavior.
- The target's callers at `0x4250afe4` and `0x4253bbec` use a 16-entry stack
  buffer and allocate a heap snapshot only after that fills. They call
  `_postNotification` and free the snapshot only after it returns. Since
  `_postNotification` re-raises the first saved callback exception, the
  caller's free is skipped on that path. Source callers likewise free
  `matches.entries` only after `NSNotificationCenterDeliver` returns, and
  delivery re-raises the saved exception. The expanded-snapshot leak therefore
  matches the target and must be preserved for behavioral fidelity.

No source behavior was changed in this audit. Static paired IDA/source review
only; no tests or builds were run.
