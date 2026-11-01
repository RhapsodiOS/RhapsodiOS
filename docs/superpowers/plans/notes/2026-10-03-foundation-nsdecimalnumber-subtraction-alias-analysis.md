# Foundation `NSDecimalNumber` subtraction selector analysis

Reference: Foundation i386 IDA database `d12fe2f23883`,
`src/Kits/Foundation/reconstruction/abi/NSDecimalNumber.json`, and current
`src/Kits/Foundation/NSDecimalNumber.m`.

The ABI contains two misspelled compatibility selectors not defined in source:
`decimalNumberBySubstracting:` and
`decimalNumberBySubstracting:withBehavior:`.

- `-[NSDecimalNumber decimalNumberBySubstracting:]` at `0x4259bd68` obtains
  `+[NSDecimalNumber defaultBehavior]`, then sends the correctly spelled
  `decimalNumberBySubtracting:withBehavior:` to `self` with the operand and
  behavior.
- `-[NSDecimalNumber decimalNumberBySubstracting:withBehavior:]` at
  `0x4259bdac` forwards both arguments to the correctly spelled
  `decimalNumberBySubtracting:withBehavior:` method.

The correctly spelled subtraction methods already exist in
`NSDecimalNumber.m:255` and `:260`. The two misspelled selectors are now
implemented as forwarding aliases. Static ABI-owner and whitespace checks
pass; tests and builds were not run.
