# Foundation NSTask Reconstruction Design

## Goal

Reconstruct the DR2 i386 `NSTask` implementation in
`src/Kits/Foundation/NSTask.m`, including the abstract public class, private
`NSConcreteTask`, task dictionary support, process launch and termination,
run-loop notification delivery, and the detached `taskWithPath:arguments:`
convenience path. Preserve the selectors and private object layout recorded in
the reference binary.

## Reference and evidence

The reference is the DR2 i386 Foundation binary used by this worktree:
`C:/Users/raynorpat/Downloads/test/Foundation-i386`, SHA-256
`1165B9063ADD5672514455CA2C9830625BEA2BCE5E46126FB5E8652114C909D6`.
IDA database `6c2a913dc37a` contains the `NSTask` and `NSConcreteTask`
implementations. The extracted ABI document is
`src/Kits/Foundation/reconstruction/abi/NSTask.json`.

The public `NSTask` is abstract. `+[NSTask allocWithZone:]` substitutes
`NSConcreteTask` for allocations of `NSTask` itself; `-init` delegates to
`NSObject`, and the public task operations request concrete implementation.
`NSConcreteTask` has instance size 28 and these i386 ivars:

| Ivar | Offset | Type |
| --- | ---: | --- |
| `_dictionary` | +4 | `NSMutableDictionary *` |
| `_hasExeced` | +8 | `char` |
| `_isRunning` | +9 | `char` |
| `_pid` | +12 | `int` |
| `_terminationStatus` | +16 | `int` |
| `hiddenTaskData` | +20 | private pointer |
| `port` | +24 | `NSPort *` |

The private dictionary keys confirmed from the constant-string objects are
`_NSTaskEnvironmentDictionary`, `_NSTaskArgumentArray`,
`_NSTaskDirectoryPath`, `_NSTaskExecutablePath`, `_NSTaskInputFileHandle`,
`_NSTaskOutputFileHandle`, `_NSTaskDiagnosticFileHandle`,
`_NSTaskTerminationStatus`, and `_NSTaskHasBeenLaunched`. The reference uses
`NSInvalidArgumentException` for launch argument and state errors and
`NSInternalInconsistencyException` for `fork` failure.

## Design

Keep `NSTask` as the abstract public class. Implement allocation substitution,
`currentTaskDictionary`, the dictionary and path launch factories, and the
public abstract forwarding behavior in `NSTask.m`. Implement the concrete
class in the same module with ivars and selectors matching `NSTask.json`.
Concrete property setters lazily copy the default task dictionary, copy path,
argument, environment, and directory values, retain standard stream objects
through the dictionary, and reject changes after launch. Getters return values
from the dictionary.

`launchWithDictionary:` rejects repeat launches and a missing dictionary,
makes a mutable copy when needed, removes previous launch state, standardizes
the executable path, checks its executable access, and prepares `argv` and
`envp`. When the environment entry is absent it uses `_NSEnviron()`; when
present it formats each entry as `key=value`. Standard streams accept
`NSFileHandle` or `NSPipe`; a pipe contributes the child-side endpoint. The
child uses `vfork`, creates a session, maps descriptors 0 through 2 (using
`/dev/null` for unspecified streams), closes descriptors from 3 onward,
changes directory when requested, and calls `execve`. The parent marks the
task launched and running, closes its copies of the child-side pipe endpoints,
and requests termination notification.

The termination worker waits with `wait4`, retries interrupted waits, stores
the reference status value (wait status shifted right by eight, or -1 on
failure), and sends a Mach-port notification. Its shared 24-byte record uses
a lock and reference count so the worker and task can release it safely.
`handleMachMessage:` transfers the status, clears the running state, removes
the run-loop port, clears its delegate, releases the port, and posts
`NSTaskDidTerminateNotification`. `waitUntilExit` runs the current loop in
default mode until the running flag clears. `interrupt` and `terminate` signal
the process group with `SIGINT` and `SIGTERM`, respectively, after checking
launch state. `terminationStatus` raises until a launched task has stopped.

Keep `taskWithPath:arguments:` as the distinct reference behavior: check
executable access, fork twice, detach the final child, close inherited file
descriptors, redirect standard streams to the reference devices, and call
`execv`. The `launchedTaskWithPath:arguments:` alias forwards to
`launchedTaskWithLaunchPath:arguments:`.

## Scope and constraints

- Modify `src/Kits/Foundation/NSTask.m` for implementation behavior and
  update the ABI JSON only if direct comparison finds a mismatch.
- Preserve `NSTask.json`'s class layouts, method encodings, categories, and
  symbols against the reference extraction.
- Follow the reference's ownership and state transitions; do not replace its
  run-loop notification path with polling or a different process API.
- Do not add or run tests or builds. Review against IDA and use source-level
  static checks only.

## Review focus

- Ensure allocations of `NSTask` create `NSConcreteTask`, while subclass
  allocations preserve the requested subclass.
- Check launch preconditions, dictionary copy ownership, executable path
  conversion, environment construction, and pipe endpoint selection against
  IDA.
- Preserve descriptor duplication before remapping standard descriptors and
  close only the parent copies identified by the reference.
- Keep termination status delivery, shared-record releases, run-loop cleanup,
  and the notification post in the reference order.
- Match every class size, ivar offset and type, selector encoding, and exported
  symbol in `NSTask.json`.
