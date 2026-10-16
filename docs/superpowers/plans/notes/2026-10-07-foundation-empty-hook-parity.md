# Foundation empty-hook parity

Compared several minimal source bodies against both Foundation IDA targets.
The source matches the target behavior in each case:

| Source implementation | i386 | PPC | Target behavior |
| --- | ---: | ---: | --- |
| `GarbageCollectUniquedStrings` | `0x4256eca0` | `0x4257b6e8` | Empty body |
| `NSDebugRecordObjectAndStack` | `0x4256edb4` | `0x4257b85c` | Empty body |
| `-[NSRunLoop configureAsServer]` | `0x425819e8` | `0x425972d4` | Empty body |
| `-[NSPerformTimer userInfo]` | `0x425811fc` | `0x42596838` | Returns nil |

No source behavior or ABI metadata changed. Static paired decompile/source
review only; no tests or builds were run.
