# Foundation `NSConnection` Released-Proxy Reconstruction Design

## Goal

Implement the four IDA-confirmed released-proxy methods missing from
`src/Kits/Foundation/NSConnection.m`, and keep the sender path in
`releaseName:count:` wire-compatible with the decoder. Preserve authentication,
release-count, and invocation-ownership behavior.

## Design

Add the methods to the existing `NSConnection` implementation, without public
header changes. A file-local fast-integer decoder handles released-proxy
records; `releaseName:count:` uses the existing typed data serializer for its
two unsigned fields.

- `getReleasedProxies:length:` forwards to the coder's
  `decodeBytesWithReturnedLength:` and returns that byte pointer.
- `handleReleasedProxies:length:` ignores a null pointer or zero length.
  Otherwise decode pairs of compact fast integers until the supplied byte end,
  use the first as the local proxy name, and pass the second to that proxy's
  `_releaseWireCount:`. Each value uses the signed one-byte payload-length
  prefix and up to four native-order value bytes used by `_decodeFastInt`.
  Keep the target's per-pair decode and optional logging behavior; do not add a
  separate alignment or length-divisibility check. Raise the observed
  `NSRangeException` for encoded widths beyond four; also reject oversized
  positive prefixes before they can overwrite the four-byte result buffer.
- `decodeReleasedProxies:` calls the two helpers in sequence using the length
  returned by `getReleasedProxies:length:`.
- `releaseName:count:` serializes both values with
  `serializeDataAt:ofObjCType:"I" context:nil`, matching the binary's call
  path. The typed serializer writes the compact fast-integer wire format;
  fixed-width `serializeInt:` writes are not compatible.
- `_cleanupAndAuthenticate:sequence:conversation:invocation:raise:` first
  decodes one object value and the piggybacked releases. If the connection's
  authentication flag is clear, or coder verification with the connection
  delegate succeeds, process the releases, release the supplied invocation,
  and return `YES`. On failed verification, send an exception result only when
  `raise` is true, using `NSFailedAuthenticationException` and reason
  `*** Received message without authentication`; release the invocation and
  return `NO`.

Use the exact IDA encodings in
`src/Kits/Foundation/reconstruction/abi/NSConnection.json`. Keep
`-[NSConnection description]` outside this change because its active path still
has unresolved out-of-slice selector references.

## Constraints and verification

- Modify `NSConnection.m` only for runtime behavior.
- Follow the current project instruction not to add or run tests or builds.
- Verify the four definitions and signatures against the ABI, inspect the
  final diff, and run static whitespace checks only.

## Evidence

The behavior is recorded in
`docs/superpowers/plans/notes/2026-10-03-foundation-nsconnection-release-analysis.md`
from IDA database `d12fe2f23883`, including method addresses, byte-pair
handling, authentication result flow, exception strings, and release logging.

The original fixed-width interpretation has been superseded by a direct IDA
recheck: `releaseName:count:` calls `serializeDataAt:ofObjCType:"I"`, which
uses `_encodeFastInt`; `handleReleasedProxies:length:` decodes through
`_decodeFastInt`. The sender and receiver therefore use a signed one-byte
payload-length prefix followed by the nonredundant bytes of each 32-bit value.
