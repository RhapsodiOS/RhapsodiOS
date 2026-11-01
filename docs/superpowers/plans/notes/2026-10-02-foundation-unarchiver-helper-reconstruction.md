# Foundation NSUnarchiver helper reconstruction

Reference: Foundation i386 IDA database instance `d12fe2f23883`.

The target's `-[NSUnarchiver decodeObject]` (`0x4250e4fc`) calls a C helper
named `_decodeObject`. Its `-[NSUnarchiver decodeValueOfObjCType:at:]`
(`0x425122d0`) calls the C helper `_decodeValueOfObjCType`. The class decoder
is likewise an internal C helper named `_decodeClass`. None of those three
helpers is an Objective-C selector in the target.

`NSArchiver.m` now implements the helpers as static C functions. An explicit
decoder context passes the unarchiver's private state from Objective-C methods
to the C helpers, avoiding extra runtime selectors while retaining recursive
object, class, and type decoding. Array element decoding uses the same type
helper.

The selector audit previously reported valid underscore-prefixed target
methods as duplicates whenever a same-class public method existed. Its
duplicate check now first verifies whether the underscore-prefixed selector
itself exists in the target. After the change, the Foundation source audit
reports no renames or duplicates; it still reports 752 missing and 135 extra
selectors overall, which remain separate reconstruction work.

Source-only checks confirmed the NSUnarchiver helper selectors are absent from
the source method inventory, the Objective-C implementation blocks are
balanced, and there is no trailing whitespace. No tests or builds were run.
