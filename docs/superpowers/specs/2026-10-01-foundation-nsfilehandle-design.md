# Foundation NSFileHandle Reconstruction Design

## Goal

Reconstruct the DR2 i386 `NSFileHandle` implementation in
`src/Kits/Foundation/NSFileHandle.m`, including its private concrete file
handles, null-device behavior, `NSPipe`, and background notifications. Preserve
the public API and the private Objective-C layouts recorded in the reference
binary.

## Reference and evidence

The reference is the DR2 i386 Foundation slice already used by this worktree:
`C:/Users/raynorpat/Downloads/test/Foundation-i386`, SHA-256
`1165B9063ADD5672514455CA2C9830625BEA2BCE5E46126FB5E8652114C909D6`.
IDA database `6c2a913dc37a` identifies `NSFileHandle`'s public methods as
abstract methods that call `NSRequestConcreteImplementation`. The real behavior
is implemented by `NSConcreteFileHandle` and `NSNullFileHandle`; `NSPipe` uses
`NSConcretePipe`.

The extracted Objective-C ABI records these relevant layouts:

| Class | Instance size | Ivars |
| --- | ---: | --- |
| `NSFileHandle` | 4 | none |
| `NSConcreteFileHandle` | 36 | `_fd` +4, `_nativeHandle` +8, `_avars` +12, `_flags` +16, `_port` +20, `_modes` +24, `hiddenData` +28, `_activity` +32 |
| `NSNullFileHandle` | 4 | none |
| `NSPipe` | 4 | none |
| `NSConcretePipe` | 12 | `_readHandle` +4, `_writeHandle` +8 |

The private ABI document will be recorded as
`src/Kits/Foundation/reconstruction/abi/NSFileHandle.json` from the existing
reference extractor. The file is already listed by the Foundation build.

## Design

Keep `NSFileHandle` as the abstract base. Its `+allocWithZone:` substitutes
`NSConcreteFileHandle` when allocating the base class; base I/O selectors keep
the reference's concrete-implementation exception. Implement the private
concrete class in the existing `.m` file, with ivars and selectors matching the
ABI document.

Concrete descriptor operations will follow the reference's POSIX behavior:
open file paths with `O_RDONLY`, `O_WRONLY`, or `O_RDWR` and the reference's
zero create mode; reject directory descriptors; read regular files up to the
requested size or EOF; read non-regular descriptors in 4096-byte chunks; write
the full data buffer; implement seek, truncate, sync, and close; and raise
`NSFileHandleOperationException` with the reference error context on system-call
failures. Standard input/output/error handles remain cached, non-owning handles
with their distinct protected flags, and fall back to the cached null handle if
descriptor initialization fails. The null handle returns descriptor `-1`, zero
offsets, and empty data; writes, seeks, synchronization, truncation, and close
are no-ops.

`NSPipe` will allocate `NSConcretePipe`, create a POSIX pipe, wrap the read and
write descriptors in concrete file handles, and return those same endpoints
from its accessors. Ownership and deallocation will follow the reference's
retain/release paths.

Background operations will use the reference's worker routines and hidden-data
handoff: a per-handle `NSPort` delegate delivers completion to the current
`NSRunLoop`, registered for the requested modes (or the reference default
modes). The delegate will post the matching read, read-to-EOF, accepted
connection, or data-available notification with the reference user-info keys.
The four asynchronous entry points will share the reference's activity setup
and reject conflicting in-flight activities as the binary does.

## Scope and constraints

- Modify `src/Kits/Foundation/NSFileHandle.m` only for runtime behavior; do not
  change public headers or unrelated Foundation modules.
- Add the extracted reference ABI document for this module.
- Use IDA-confirmed selectors, layouts, control flow, ownership, and constants;
  do not infer private layouts from the source stubs.
- Do not add or run tests or builds. Review the source against IDA, verify the
  committed ABI document against the reference metadata, and run static
  whitespace/source checks only.

## Review focus

- Keep abstract methods on `NSFileHandle` and concrete behavior on the private
  subclasses, matching the target class hierarchy.
- Preserve the exact descriptor ownership and standard-handle flag behavior.
- Check partial reads, EOF, zero-length data, closed descriptors, and syscall
  errors against IDA pseudocode.
- Ensure every background worker releases its hidden-data state exactly once
  and that the run loop removes the port for each previously registered mode.
- Match class instance sizes, ivar offsets/types, selector encodings, and
  exported symbols in `NSFileHandle.json`.
