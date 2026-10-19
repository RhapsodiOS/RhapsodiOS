# Foundation `NSNonsavingDefaultsManager` selector audit

Reference: `src/Kits/Foundation/reconstruction/abi/NSUserDefaults.json` from
the Foundation i386 target.

The ABI manifest contains the `NSNonsavingDefaultsManager` class, its
`_domains` ivar at offset 4, and ten instance selectors. The list includes
`initWithPath:` and the dictionary accessors, but not `dealloc`. The source
previously added `-dealloc` to release `_domains`, creating a selector absent
from the target. That method was removed so the class inherits the target's
`NSObject` deallocation behavior. The `_domains` storage is therefore not
released by a class override, matching the target's selector surface.

The full selector audit reports 3,253 reference selectors, zero missing,
renamed, or duplicate selectors, and 57 source extras. `git diff --check` is
clean for the source change. No tests or builds were run.
