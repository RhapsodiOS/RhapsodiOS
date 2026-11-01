# `NSFormatter` base methods (2026-10-07)

Compared the base formatter methods in both IDA targets against
`NSFormatter.m`:

| Method | i386 | PPC | Target behavior |
| --- | --- | --- | --- |
| `attributedStringForObjectValue:withDefaultAttributes:` | `0x4258a308` | `0x425a231c` | Returns nil. |
| `editingStringForObjectValue:` | `0x4258a334` | `0x4255f0b0` | Forwards to `stringForObjectValue:`. |
| `isPartialStringValid:newEditingString:errorDescription:` | `0x4258a39c` | `0x425a23d0` | Returns YES. |
| `stringForObjectValue:` | `0x4258a3a8` | `0x425a23e0` | Requests a concrete implementation, then returns nil. |
| `getObjectValue:forString:errorDescription:` | `0x4258a360` | `0x425a236c` | Requests a concrete implementation, then returns NO. |

The source already matches these base-class bodies; the nil and constant-return
methods are intentional target behavior, not missing implementations.

No source or ABI changes were needed. Static paired IDA/source review only; no
tests or builds were run.
