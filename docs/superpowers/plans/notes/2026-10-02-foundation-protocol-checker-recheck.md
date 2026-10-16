# NSProtocolChecker Reference Recheck

Reference: Foundation i386 IDA database `6c2a913dc37a`.

The proxy implementation in `src/Kits/Foundation/NSProtocolChecker.m` matches
the target paths checked in this pass:

- `+[NSProtocolChecker allocWithZone:]` substitutes
  `NSConcreteProtocolChecker` only for the abstract base and calls
  `_NSAllocateObject` with zero extra bytes.
- `protocolCheckerWithTarget:protocol:` allocates, initializes, then
  autoreleases the checker.
- `methodDescriptionForSelector:` checks the forwarding-method protocol first,
  then the wrapped protocol. `methodSignatureForSelector:` builds a signature
  from the returned type string. `forwardInvocation:` validates only against
  the wrapped protocol before invoking the target.
- `respondsToSelector:` and `_conformsToProtocolNamed:` query the wrapped
  protocol. Unknown selectors go through
  `_NSProtocolCheckerRaiseUnknownSelectorException`.
- The concrete checker retains the target, stores the protocol pointer, and
  releases the target before calling `NSProxy` deallocation. Port-coder
  replacement and `awakeAfterUsingCoder:` also match the target.
- Abstract `target` and `protocol` call
  `NSRequestConcreteImplementation` for `NSProtocolChecker`.

One wording difference was found in abstract
`initWithTarget:protocol:`. The target's exception format begins
`*** initialization method -%s ...`; the source omitted `initialization
method`. The source string now matches the target. The target helper's unknown
selector message matches the source exactly.

This comparison used pseudocode, data strings, and the checked-in ABI record.
No IDA database changes, tests, or builds were made.
