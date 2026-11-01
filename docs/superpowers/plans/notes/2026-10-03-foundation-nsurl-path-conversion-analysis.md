# Foundation NSString URL/path conversion analysis

Reference: Foundation i386 IDA database `d12fe2f23883` and
`src/Kits/Foundation/reconstruction/abi/NSPathUtilities.json`.

## Current source and ABI state

The `NSString(NSPathUtilities)` ABI category contains
`stringByConvertingPathToURL` and `stringByConvertingURLToPath`. Neither
selector is implemented in the Foundation source. Both have named method
symbols in IDA. Their bodies are at `0x42582864` and `0x425828a0` respectively;
IDA reports no direct call xrefs for either method.

## `stringByConvertingPathToURL`

At `0x42582864`, the method sends `stringByStandardizingPath` to the receiver,
then appends the constant `file://localhost` (16 bytes) as the receiver of
`stringByAppendingString:`. The result is therefore the prefix followed by
the standardized path; the body performs no percent escaping.

## `stringByConvertingURLToPath`

At `0x425828a0`, the method checks for the prefix `file:`. The instruction
sequence confirms the following receiver and branch flow:

- It takes a substring from index 5 of the original string.
- If that suffix begins with `//`, it takes a substring from index 2 of the
  **original string**, not from the suffix.
- It then checks that substring's first character. If it is not `/`, the
  method requires the substring to begin with `localhost`; on success it takes
  a substring from index 9 of the original string.
- If the suffix does not begin with `//`, the temporary path is nil.
- For strings without the `file:` prefix, it returns nil if the string
  contains `:`; otherwise it standardizes and returns the receiver.

Because substring index 2 of a `file:` URL starts with `le:`, the
`localhost` check fails. The target consequently returns nil for the
`file:`-prefixed branch as written. The instruction sequence confirms this
receiver choice; it is not just a decompiler label. Preserve this quirk only if
the reconstruction goal is strict binary behavior; changing it to conventional
file-URL parsing would diverge from this target.

## Reconstruction boundary

These two methods were added to `NSPathUtilities.m` under
`NSString(NSPathUtilities)` without changing the underlying URL parser or
other path methods. The reconstruction follows the target binary, so
`stringByConvertingURLToPath` preserves the verified `file:`-branch quirk.

The selector audit now reports 3,036 source definitions and 337 missing
reference selectors, with zero renames or duplicates. Both selectors resolve
under the reference category owner, and `git diff --check` passed. No tests or
builds were run.
