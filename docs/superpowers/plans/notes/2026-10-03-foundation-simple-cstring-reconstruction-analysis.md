# Foundation simple C string reconstruction

Reference: Foundation i386 IDA database `d12fe2f23883` and
`src/Kits/Foundation/reconstruction/abi/NSSimpleCString.json`.

## Reconstructed selectors

`NSSimpleCString.m` now implements the nine missing `NSSimpleCString`
selectors recorded in the ABI manifest:

| Selector | IDA address |
| --- | --- |
| `_newSubstringWithRange:zone:` | `0x4252d18c` |
| `canBeConvertedToEncoding:` | `0x4258ee00` |
| `compare:options:range:` | `0x42535b00` |
| `copyWithZone:` | `0x42513274` |
| `hasPrefix:` | `0x4252d030` |
| `hasSuffix:` | `0x425466d0` |
| `isEqual:` | `0x42505680` |
| `isEqualToString:` | `0x4250678c` |
| `stringByAppendingString:` | `0x425325e8` |

The substring method checks the lower and upper range bounds, returns the
empty singleton for a zero-length range, retains the receiver for a full
range, and uses the existing 24-byte inline-string threshold. Longer ranges
use `NSCSubstring` with the receiver as its referenced string.

Comparison uses the existing `NSCompareCStringBytes` helper when the other
string exposes fast C bytes and delegates to `NSString` otherwise. Equality
uses direct byte comparison for simple C-string storage, a fast-byte path for
other C strings, and the existing chunked character comparison when no fast
C representation is available. Prefix and suffix checks preserve IDA's
zero-length behavior.

## Append disassembly

Hex-Rays did not decompile `0x425325e8`; its instruction flow shows the
receiver-empty and argument-empty copy paths, then dispatches according to
the argument's fastest encoding. The C path allocates in the receiver's zone,
copies receiver bytes, and obtains the argument bytes with the C-string
encoding. The Unicode path allocates a UTF-16 buffer, copies characters from
both strings, and initializes an owning string. The implementation follows
those branches and their allocation lengths.

## Verification

The static selector audit moved from 2,956 definitions / 419 missing
selectors to 2,965 definitions / 410 missing selectors. It reports zero
renames and duplicates, and no remaining `NSSimpleCString` or
`NSCSubstring` selector gaps. Whitespace checks passed. No build or runtime
tests were run.
