# Foundation NSDistantObject overrides

Reference: Foundation i386 IDA database instance `d12fe2f23883`.

Reconstructed the confirmed `NSDistantObject` overrides for
`isAClassOfObject:`, `awakeAfterUsingCoder:`, `classForArchiver`, `class`,
`copyWithZone:`, `copy`, `mutableCopyWithZone:`, `mutableCopy`, `description`,
`hash`, `isEqual:`, `zone`, `conformsToProtocol:`, and `initWithCoder:`. The
forwarding overrides build an invocation using the same target classes and
selectors shown by IDA, forward it through `forwardInvocation:`, and retain
returned copy results. IDA passes a null zone to both zone-taking copy methods.
`classForArchiver` raises `NSInvalidArgumentException` with the recovered
`NSDistantObject asked to archive` reason. The decoder follows all three wire
kinds, logging gates, import/retain behavior, and the target's exception
messages for invalid ports and wire values. `conformsToProtocol:` checks the
remote wire state and forwards the protocol name through
`_conformsToProtocolNamed:` as the target does.

`appendFormat:` and `stringByAppendingFormat:` now format their variadic input
locally, build the corresponding `appendString:` or `stringByAppendingString:`
invocation for the target string class, forward it, and release the temporary
formatted string. `retain` and `release` also record internal reference count
events 6 and 7 when `NSKeepAllocationStatistics` is enabled, matching IDA.
The source selector audit finds no remaining missing `NSDistantObject` methods.

The source selector audit now reports 722 missing selectors, down from 738,
with zero renames and duplicates and 135 extra selectors remaining.
`git diff --check` passed; no tests or builds were run.
