# Foundation `NSMutableArray` selector analysis

Reference: Foundation i386 IDA database `d12fe2f23883`,
`src/Kits/Foundation/reconstruction/abi/NSArray.json`, and current Foundation
sources.

## Reconstructed selectors

- `-[NSMutableArray initWithContentsOfFile:]` (`0x4255f3b0`) loads NSData,
  captures the receiver's zone, deallocates the receiver, parses the data,
  requires an NSArray result, and returns a mutable copy in that zone.
- `-[NSMutableArray classForCoder]` (`0x425447dc`) returns the
  `__NSMutableArrayClass` class object; source expresses this as
  `[NSMutableArray class]`.
- `-[NSMutableArray exchangeObjectAtIndex:withObjectAtIndex:]`
  (`0x4255f26c`) obtains the count, raises the array bounds exception for
  either invalid index, swaps concrete storage entries directly, and uses a
  retain plus two replacements for non-concrete mutable arrays.
- `-[NSMutableArray removeObject:range:identical:]` (`0x42516a10`) validates
  the requested range, scans only while the target object's retain count is
  nonzero, removes identical objects and—unless `identical` is set—objects
  equal to it. Concrete arrays compact the backing storage in place. Other
  mutable arrays process at most 128 entries per `getObjects:range:` batch and
  remove matched indices after examining each batch.

The four selectors are now implemented under the exact `NSMutableArray` owner.
Static exact-owner and whitespace checks only; no tests or builds were run.
