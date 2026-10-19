# Foundation `NSArray` path extensions analysis

Reference: Foundation i386 IDA database `d12fe2f23883` and
`src/Kits/Foundation/reconstruction/abi/NSPathUtilities.json`.

## Current source and ABI state

The ABI manifest defines the `NSArrayPathExtensions` category with two
instance methods: `stringsByAppendingPathComponent:` and
`pathsMatchingExtensions:`. `NSPathUtilities.m` implements the latter but has
no definition for the former. A class-plus-selector static audit confirms that
`stringsByAppendingPathComponent:` is the only missing selector from this
category; the general category audit had false positives because source
definitions are grouped under unqualified `@implementation NSArray` and
`@implementation NSString` blocks.

## IDA behavior

`-[NSArray stringsByAppendingPathComponent:]` is at `0x4253e67c`. Its body:

1. Reads the receiver's count.
2. Creates an `NSMutableArray` with that capacity.
3. Iterates indices from zero to count minus one.
4. Gets each path and sends `stringByAppendingPathComponent:` with the method's
   original argument.
5. Adds each result to the mutable array and returns that array.

Instruction-level review confirms the argument is loaded from the method's
stack argument and left in place across the nested `objc_msgSend`, so the
decompiler's call does forward the supplied component even though its
pseudocode omits that argument in the rendered expression. The function has no
direct call xrefs; it remains exposed through the Objective-C selector.

The adjacent `-[NSArray pathsMatchingExtensions:]` at `0x4253ee98` is already
implemented in the source and confirms the same mutable-array construction and
iteration pattern. It selects only paths whose extension is non-empty and is
contained in the supplied filter array.

## Implementation status (2026-10-03)

Implemented `-stringsByAppendingPathComponent:` in the existing NSArray path
utilities implementation. It uses the target's capacity allocation, index
order, per-element `NSString` dispatch, and mutable-array return value. Static
category-owner and whitespace checks pass. Tests and builds were not run.
