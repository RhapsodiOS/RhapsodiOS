# Objective-C runtime string conversion reconstruction

IDA recheck confirmed the i386 and PPC conversion paths:

- `NSStringFromSelector` raises `NSInvalidArgumentException` for a null
  selector with reason `*** NSStringFromSelector(): 0 selector`; otherwise it
  returns `stringWithCString:length:` using the selector name and byte length.
- `NSStringFromClass` returns the class name through
  `stringWithCString:length:`. The reference does not check for `Nil` first.
- `NSSelectorFromString` calls `-[NSString cString]` and `sel_getUid`.
- `NSClassFromString` calls `-[NSString cString]`, then `objc_getClass`, and
  calls `_NSAltClassNameFromString` only when lookup fails and the callback is
  installed.

`NSObjCRuntime.m` now follows those paths and no longer creates or reads raw
`NXConstantString`-shaped records. The same update reconstructed
`-[Protocol detailedDescription]` and `+[NSObject detailedDescriptionForClass:]`
from the i386/PPC IDA bodies, including protocol lists, method descriptions,
class flags, method lists, and superclass output. The method addresses and
remaining verification limits are recorded in `reconstruction/divergences.md`.
No ABI declarations or instance layouts changed. Static source checks only;
no build or tests were run.
