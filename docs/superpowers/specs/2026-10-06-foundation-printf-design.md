# PPC Foundation `NSPrintf` Reconstruction Design

## Goal

Reconstruct the PPC Foundation formatted-output path from the live MOSXS
Foundation image. Implement its internal `_NSvfprintf` engine and exported
`_NSvsnprintf` entry, route the existing `_NSsnprintf` wrapper through
Foundation's PPC formatter, and preserve the existing i386
libc-forwarding behavior.

The PPC formatter's floating conversions depend on Foundation's `___dtoa` and
`_quorem` routines. Reconstruct that dependency using the existing shared
`NSBigint` implementation rather than calling host libc formatting helpers.

## Evidence and current state

IDA instances used for this design:

| Target | IDA instance | Finding |
| --- | --- | --- |
| MOSXS PPC Foundation | `75ffa72daeee` | `_NSvfprintf` at `0x425121b8`; exported `_NSvsnprintf` at `0x425138d0`; exported `_NSsnprintf` at `0x42535b8c` |
| MOSXS i386 Foundation | `2387801ca778` | Exported `_NSsnprintf` at `0x4252e994`; no Foundation `_NSvfprintf` or `_NSvsnprintf` |

IDA's PPC entry table includes `_NSvsnprintf` and `_NSsnprintf`, but not
`_NSvfprintf`; the formatter engine remains an internal function. The i386
entry table includes `_NSsnprintf` only from this family.

The PPC `_NSvfprintf` is a 951-line formatter. It recognizes `%%`, character,
string, signed and unsigned integer, octal, pointer, and hexadecimal
conversions; floating `e`, `E`, `f`, `g`, and `G`; `%n`; dynamic width and
precision; and the target's legacy `h`, `l`, `q`, `L`, `D`, `O`, and `U`
length/conversion spellings. Flags include space, alternate form, `*`, plus,
left alignment, zero padding, and precision. It emits through a vector buffer
and flushes with `__sprint`, which delegates to Foundation's local
`__sfvwrite` implementation.

PPC helper entries in the live image:

| Helper | PPC entry | Role |
| --- | --- | --- |
| `__sprint` | `0x42511f28` | Flush the formatter's vector buffer through `__sfvwrite` |
| `__sfvwrite` | `0x42511f7c` | Consume the vector buffer using Foundation's FILE buffering state |
| `__ultoa` | `0x4252733c` | Convert 32-bit unsigned integers |
| `__uqtoa` | `0x425ac214` | Convert 64-bit unsigned integers |
| `cvt` | `0x4254f2e0` | Prepare floating conversion through `___dtoa` |
| `exponent` | `0x42560cc0` | Render decimal exponents |
| `___dtoa` | `0x4254e138` | Produce decimal digits using shared `Bigint` helpers |
| `_quorem` | `0x4255b5e0` | Quotient/remainder helper used by `___dtoa` |

The existing `NSBigint.h/.m` reconstruction provides the allocator, freelist,
shared tables, and arithmetic helpers used by both `__NSstrtod` and the target
`___dtoa`. `NSDtoa.m` now contains the PPC `___dtoa` converter and its
`_quorem` dependency. `NSPrintf.m` now contains the PPC vector writer, the
`_NSvfprintf` engine and conversion helpers, and the exported `_NSvsnprintf`
entry. `NSObjCRuntime.m` routes the PPC `_NSsnprintf` wrapper through that
entry while retaining the i386 libc path.

The PPC IDA call graph confirms the conversion closure: `___dtoa` calls
`_Bfree`, `_d2b`, `_Balloc`, `_i2b`, `_pow5mult`, `_mult`, `_hi0bits`,
`_lshift`, `_cmp`, `_multadd`, `_memmove`, `_quorem`, and `_diff`. `_quorem`
calls only `_cmp`. Formatter floating conversions reach `___dtoa` through
`_cvt`; `_exponent` has no callees. This is the observed closure to implement
for decimal conversion, without treating Bigint helper exports as part of the
public Foundation ABI.

The call at `0x42511f48` from `__sprint` resolves to Foundation's local
`__sfvwrite` function at `0x42511f7c`; it is neither an import nor an external
libc dependency. Its 98-line body handles unbuffered, fully buffered, and
string streams, updates FILE cursors and remaining vector bytes, and marks the
stream error flag on write failure. When the line-buffered flag is set, the
body returns success without consuming the vector. Its unbuffered path caps
each write callback request at 1024 bytes. The Berkeley
`src/Libc-1/stdio.subproj/fvwrite.c` is comparison material, but differs in
line-buffer handling and must not be copied in place of the PPC body.

The current `NSObjCRuntime.m` `_NSsnprintf` body calls libc `vsnprintf`. Its
behavior matches the i386 IDA body exactly: `va_start`, then forward the buffer,
size, format, and `va_list` to libc `vsnprintf`. The PPC IDA wrapper also
accepts the same C signature but calls Foundation's own formatting path.

The checked-in Berkeley `src/Libc-1/stdio.subproj/vfprintf.c`,
`vsnprintf.c`, and `stdlib.subproj/strtod.c` provide source comparison material
for the parser, wrappers, decimal conversion, and Bigint code. They are not the
behavioral authority; PPC IDA control flow, constants, and layouts are.

## Design

### Module boundary

Add `NSPrintf.m` for the target's internal `_NSvfprintf`, `__sfvwrite`,
`__sprint`, integer converters, floating-format helpers, and exported
`_NSvsnprintf`. Implement their behavior from the PPC IDA entries, comparing
each section to the checked-in Berkeley `vfprintf.c`, `vsnprintf.c`, and
`fvwrite.c` sources where they apply. Use the project's stdio declarations
where their layout matches the target; otherwise define only the private
memory-stream, FILE, and vector records needed by confirmed IDA field offsets.

Add `NSDtoa.m` for the PPC `___dtoa` body and `_quorem` dependency. Declare
their narrow internal interface for `NSPrintf.m` without adding them to the
Foundation public export or source-symbol assignment manifests. Use
`NSBigint.h/.m` for shared arithmetic, freelist, and cached tables; do not
duplicate the shared implementation or alter the completed `__NSstrtod`
behavior.

In `NSObjCRuntime.m`, preserve the current i386 `_NSsnprintf` implementation
and route only the PPC branch through Foundation's `_NSvsnprintf`. Register
`NSPrintf.m` and `NSDtoa.m` in `PB.project` and `Makefile.preamble`.

### Formatting behavior

Match PPC IDA for:

1. Flag, width, precision, and legacy length parsing, including `*` argument
   consumption and negative dynamic width handling.
2. Integer, string, character, pointer, `%n`, escaped-percent, and unknown
   conversion handling, including signedness and target-specific zero/space
   padding rules.
3. Floating `e`, `E`, `f`, `g`, and `G` selection, `Inf`/`NaN` handling,
   decimal-point placement, trailing zero policy, and exponent rendering.
4. Vector buffering, flush/error propagation, count calculation, and target
   return behavior, including `__sprint` calling the local `__sfvwrite`
   implementation, the 1024-byte unbuffered write limit, and the observed
   successful no-consumption return for line-buffered streams.
5. `_NSvsnprintf` memory-stream initialization, the size-zero `-1` result,
   termination behavior, and forwarding to `_NSvfprintf`.
6. `_NSsnprintf` PPC `va_list` forwarding while retaining the current i386
   libc `vsnprintf` call unchanged.
7. `___dtoa` digit generation, rounding and trimming, Bigint cleanup, and
   `_quorem` arithmetic based on their live PPC bodies.

### ABI and platform records

Add a PPC-only ABI record and source-symbol assignment for `_NSvsnprintf`,
which is absent from the i386 Foundation image. Keep `_NSvfprintf`,
`__sprint`, `__sfvwrite`, and all other helpers internal and out of public
export assignments. Keep the existing common
`_NSsnprintf` export assigned to `NSObjCRuntime.m`, since that module continues
to own its platform-specific wrapper. Keep formatter helpers, `___dtoa`, and
`_quorem` out of public export assignments.
Record the i386 divergence and the PPC-only formatter path in
`reconstruction/divergences.md`; record new helper ownership only where the
existing ownership manifest tracks those symbols.

## Verification

- Compare each formatter, wrapper, converter, and `_quorem` body against its
  live PPC IDA function and inspect the exact called helper set.
- Confirm PPC exports `_NSvsnprintf` and retains internal `_NSvfprintf`, while
  i386 still uses the unchanged libc-forwarding `_NSsnprintf` and has no
  Foundation `_NSvfprintf` or `_NSvsnprintf` implementation.
- Validate the PPC ABI overlay, symbol and ownership assignments, source
  registration, and unique export definitions.
- Run `git diff --check` on the implementation slice.
- Do not add or run tests or builds for this reconstruction slice; runtime
  verification is outside its current scope.

## Out of scope

- Replacing or wrapping i386 libc `vsnprintf`.
- Adding newer printf extensions not present in the PPC IDA parser.
- Changing `NSLog`, `NSLogv`, or other Foundation logging APIs except where
  they already call `_NSsnprintf`.
- Modifying `NSBigint` or the completed `NSStrtod` conversion path except to
  resolve a directly demonstrated shared-helper mismatch.
