# Foundation `NSCoderExtensions1` category analysis

Reference: Foundation i386 IDA database `d12fe2f23883`,
`src/Kits/Foundation/reconstruction/abi/NSCompatibility.json`, and the
Objective-C runtime class layouts in `src/objc-1`.

## Scope

The Foundation ABI has 26 missing methods across four categories on runtime
classes: seven on `HashTable`, eight on `List`, six on `Storage`, and five on
`StreamTable`. The category methods all log the compatibility warning once
per method. The runtime classes and their layouts already exist in
`src/objc-1`; the missing owner bodies belong to Foundation's
`NSCoderExtensions1` categories.

## HashTable

IDA addresses: `0x4256aa98` (`autorelease`), `0x4256aae4`
(`encodeWithCoder:`), `0x4256abe4` (`freeObjects`), `0x4256ac68`
(`initWithCoder:`), `0x4256adf8` (`release`), `0x4256ae58` (`retainCount`),
`0x4256aea4` (`retain`).

`encodeWithCoder:` writes the count and key/value type descriptors using
`"i%%"`, then enumerates entries and encodes each key and value with the
stored type descriptors. `initWithCoder:` selects old `"i**"` or current
`"i%%"` decoding based on the archived class version, rejects missing key or
value descriptors, derives and zeroes the bucket array in the receiver's zone,
then decodes and inserts each pair. `freeObjects` chooses the release callback
for keys and values according to whether their type descriptor begins with
`@`, then delegates to `freeKeys:values:`. The three ownership methods use the
Foundation extra-reference-count helpers; `autorelease` calls
`NSAutoreleaseObject`.

## List

IDA addresses: `0x4256aef0` (`autorelease`), `0x4256af3c`
(`encodeWithCoder:`), `0x4256afc4` (`freeObjects`), `0x4256b038`
(`initWithCoder:`), `0x4256b15c` (`makeObjectsPerform:withObject:`),
`0x4256b1cc` (`release`), `0x4256b22c` (`retainCount`), `0x4256b278`
(`retain`).

`encodeWithCoder:` writes the element count, then the elements as an `@` array.
`initWithCoder:` handles versioned and older count encodings, sets capacity to
the decoded count, allocates the element buffer from the receiver's zone, and
decodes the object array. `freeObjects` removes elements from the end and
sends `release` to each. `makeObjectsPerform:withObject:` walks the stored
array in reverse and sends `perform:withObject:` to each element. Ownership
methods use the same Foundation helpers as the `HashTable` category.

## Storage

IDA addresses: `0x4256dbe8` (`autorelease`), `0x4256dc34`
(`encodeWithCoder:`), `0x4256dcc4` (`initWithCoder:`), `0x4256ddfc`
(`release`), `0x4256de5c` (`retainCount`), `0x4256dea8` (`retain`).

Encoding stores the element descriptor, element size, and element count, then
encodes the raw element buffer using that descriptor. Decoding supports the
older `"*iii"` record and the current descriptor-plus-integers record; it sets
capacity to the decoded count, allocates and zeroes `count * elementSize`
bytes in the receiver's zone when needed, and decodes the array. Ownership
methods use the Foundation extra-reference-count helpers.

## StreamTable

IDA addresses: `0x4256def4` (`encodeWithCoder:`), `0x4256e018`
(`freeObjects`), `0x4256e08c` (`initWithCoder:`), `0x4256e1d0`
(`nextStreamState:key:value:`), `0x4256e25c` (`valueForStreamKey:`).

Encoding first invokes `HashTable`'s coder implementation, then encodes each
stream value's typed key, byte length, and serialized bytes. Decoding invokes
the `HashTable` decoder, reconstructs each serialized stream value, and inserts
it. `nextStreamState:key:value:` delegates iteration to the hash table and
converts the stored value through `getObject_new`; `valueForStreamKey:` looks
up the stored value and applies the same conversion. `freeObjects` selects the
key-release callback from the key descriptor and uses
`freePickleAndReleaseObject` for stream values.

These notes identify the reconstruction surface.

## Implementation status (2026-10-04)

Implemented all 26 missing category methods in `NSCompatibility.m`. Decoding
preserves the legacy and current type encodings, archived counts, receiver
zones, and the stream pickle ownership and lazy-unarchive behavior. Hash-table
descriptor rejection uses the observed `NSInternalInconsistencyException` and
format string. Every method has its own compatibility-warning slot.

The exact-owner comparison reports 26 expected category methods and 26 source
definitions, with no missing, extra, or duplicate selectors. The global
selector audit dropped from 64 missing selectors to 38, with zero renames and
zero duplicates. `git diff --check` is clean. No tests or builds were run.
