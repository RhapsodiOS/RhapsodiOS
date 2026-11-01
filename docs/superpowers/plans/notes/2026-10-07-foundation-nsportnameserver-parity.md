# `NSMachNMServer` paired IDA parity (2026-10-07)

Compared the concrete `NSPortNameServer` implementation in DR2 i386 and
MOSXS PPC IDA with `NSPortNameServer.m`.

`+[NSMachNMServer default]` lazily allocates and initializes a singleton.
`-init` passes the exported `__NSMachNMServerPort` to `-initWithPort:`, whose
body only retains the supplied port and returns `self`. The source follows
this path and does not add a superclass initializer call.

`-portForName:onHost:` obtains the host and service C strings, substitutes the
empty string for either nil result, calls `netname_look_up`, and returns nil on
failure or `+[NSPort portWithMachPort:]` on success. `-portForName:` forwards
with a nil host. `-registerPort:forName:signature:` checks for `machPort`,
raises `NSInvalidArgumentException` when absent, substitutes the empty string
for a nil name, and passes the name-server, signature, and registered port
Mach port values to `netname_check_in`. The convenience registration method
lazily creates one signature port and forwards to that body. The two removal
methods share the same lazy signature and nil-name substitution before
calling `netname_check_out`.

Both `count` bodies return zero. `copyWithZone:` and `mutableCopyWithZone:`
allocate the receiver's class in the requested zone and initialize it. The
source deallocator releases `_nameServerPort` before calling `super`, matching
both targets. No source correction was indicated.

Relevant i386 addresses: `default` `0x425445f8`, `init` `0x42552fe4`,
`initWithPort:` `0x4255300c`, `portForName:onHost:` `0x4254328c`,
`registerPort:forName:` `0x42549a0c`,
`registerPort:forName:signature:` `0x4254812c`, `removePortForName:`
`0x42569758`, `removePortForName:signature:` `0x42569784`, `count`
`0x425696a4`, `copyWithZone:` `0x4256966c`, `mutableCopyWithZone:`
`0x425696fc`, and `dealloc` `0x425696b0`.

Relevant PPC addresses: `default` `0x425483e0`, `init` `0x42555f70`,
`initWithPort:` `0x42555fb0`, `portForName:onHost:` `0x425480dc`,
`registerPort:forName:` `0x42575e38`,
`registerPort:forName:signature:` `0x42575ed0`, `removePortForName:`
`0x42575fd4`, `removePortForName:signature:` `0x42576010`, `count`
`0x42575d4c`, `copyWithZone:` `0x42575d08`, `mutableCopyWithZone:`
`0x42575dbc`, and `dealloc` `0x42575d5c`. Static paired IDA/source review
only; no tests or builds were run.

## Process-start hook

Also compared `__NSToDoAtProcessStart` in i386 (`0x4254a77c`) and PPC
(`0x42580288`) with the hook at the start of `NSPortNameServer.m`. Both targets
populate the same class-cache globals, set the same six class versions
(`NSString` 1, `NSMutableString` 1, `NSCountedSet` 1, `NSTimeZone` 1,
`NSNumberFormatter` 4, and `NSDateFormatter` 41), lazily allocate the same four
empty collection/string-array globals, initialize the shared distant-date
globals only when nil, reset Mach ports, and create/store/return the name-server
port.

The i386 pseudocode renders the double arguments as two 32-bit integers. The
future pair (`0x22000000`, `0x422d63c6`) and past pair (`0xdc000000`,
`0xc22d63c0`) are the low/high words, respectively, of the exact IEEE-754
values `63113990400.0` and `-63113817600.0` used by `NSDate`'s lazy accessors.
The PPC string reference for the fourth version setter resolves to
`NSTimeZone`; its misleading IDA label is an interior string reference, not a
different class. The source's calls to `[NSDate distantFuture]` and
`[NSDate distantPast]` initialize the same globals through the same
`NSDistantDate` allocation and initializer path. No source correction was
indicated. Static paired IDA/source review only; no tests or builds were run.
