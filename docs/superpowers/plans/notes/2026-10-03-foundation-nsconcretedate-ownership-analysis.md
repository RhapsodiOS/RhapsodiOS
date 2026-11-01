# Foundation NSConcreteDate ownership reconstruction

Reference: Foundation i386 IDA database d12fe2f23883 and
src/Kits/Foundation/reconstruction/abi/NSDate.json.

## Reconstructed selectors

NSDate.m now implements the five missing NSConcreteDate ownership and
copying methods:

| Selector | IDA address |
| --- | --- |
| release | 0x4250d040 |
| dealloc | 0x4250f0e0 |
| retain | 0x425199fc |
| copyWithZone: | 0x42543498 |
| retainCount | 0x4259ac40 |

retain, release, and retainCount use the existing
_NSIncrementInternalRefCount, _NSDecrementInternalRefCountWasZero, and
_NSInternalRefCount helpers with mask -1 and _NSGlobalRetainLock.
copyWithZone: ignores its zone and returns [self retain]. dealloc forwards
to the superclass.

## Verification

The static selector audit moved from 2,976 definitions / 399 missing
selectors to 2,981 definitions / 394 missing selectors. It reports zero
renames and duplicates. Whitespace checks passed. No build or runtime tests
were run.
