# Foundation `NSString(NSURLPathUtilities)` owner correction

The four URL/path helpers already had IDA-derived bodies in
`NSPathUtilities.m`, documented in the Foundation strings analysis note. A
current exact-owner comparison against
`src/Kits/Foundation/reconstruction/abi/NSURLPathUtilities.json` showed they
were still inside the flat `NSString` implementation. The ABI assigns them to
the `NSURLPathUtilities` category.

Moved `stringByAddingPercentEscapes`, `stringByRemovingPercentEscapes`,
`standardizedNativePath`, and `standardizedURLPath` into
`NSString(NSURLPathUtilities)` without changing their bodies. Static exact-owner
and whitespace checks only; no tests or builds were run.
