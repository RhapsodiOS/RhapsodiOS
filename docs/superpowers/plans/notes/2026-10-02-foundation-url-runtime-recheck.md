# Foundation NSURL runtime recheck

This note records a source-to-reference comparison of the URL construction
path in DR2 i386 Foundation, IDA database `6c2a913dc37a`.

`-[NSURL initWithString:relativeToURL:]` at `0x425946f4` raises when the URL
string is nil, parses generic URL component ranges, and replaces the receiver
with an `NSAbsoluteURL` instance when the parsed scheme length is nonzero. For
relative URLs, it initializes `NSURL`, copies the relative string, and retains
the supplied base URL. The generic parser at `0x4259596c` returns success for
an empty string and does not validate percent escapes or reject control
characters; the initializer's only explicit input error is nil.

The target scheme scan accepts ASCII letters, `+`, `-`, and `.` until a colon,
without requiring the first character to be a letter. Digits terminate the
scan. `NSURLStringHasScheme` now uses those rules, and the constructor no
longer applies a separate percent-escape or control-character validation
pass. Empty strings therefore follow the target's ordinary relative-URL path.

IDA's `NSAbsoluteURL` ABI record describes a subclass of `NSURL` with one
`NSString *_scheme` ivar at offset 20. Its initializer (`0x42594428`) requires
a nil base URL and a nonempty scheme, removes `scheme:` from the stored
relative string, and saves the original scheme. `baseURL` returns nil;
`scheme` removes percent escapes from `_scheme`; `relativeString` reattaches
`_scheme:` to the superclass string; and `resourceSpecifier` returns the
superclass relative string. `NSURL.m` now implements this private subclass and
routes scheme-bearing strings through it. Its initializer strips the scheme
before calling the superclass initializer, then retains the original escaped
scheme; this prevents the superclass from selecting the subclass again.

`-[NSURL initWithScheme:host:path:]` at `0x42594828` requires an absolute
path, standardizes that path, percent-escapes the host and scheme, forms the
URL string, and calls `initWithString:`. The source already follows those
steps for this initializer.

The constructor and private-class gap is now addressed in `NSURL.m`; the
existing `NSAbsoluteURL` ABI record remains the layout/selector reference.
`git diff --check` and a JSON parse of that ABI record passed. No tests or
builds were run.

`-[NSURL absoluteString]` at `0x42594bc0` begins by calling
`-[NSURL relativeString]` and returns that result directly when `baseURL` is
nil. Since `NSAbsoluteURL` overrides `relativeString` to restore the escaped
scheme, inherited `absoluteString` preserves the scheme. No override or
correction is needed for this path.

## File URL initializer comparison (2026-10-04)

The exact project IDA database confirms `-[NSURL initWithScheme:host:path:]`
at `0x42594828` standardizes the path, escapes host and scheme, formats all
three values into the URL string, then calls `initWithString:`. The existing
source follows this path; its additional `scheme == nil` check is not present
in the reference.

`-[NSURL initFileURLWithPath:]` at `0x425948fc` requires a nonnil, nonempty
path, standardizes relative paths, then checks whether the final character is
the directory delimiter. If not, it asks `NSFileManager` whether the path is a
directory and appends the delimiter when needed. Absolute paths are passed to
`initWithScheme:host:path:` with the file scheme and localhost. Relative paths
are standardized as URL paths before being passed to `initWithString:`.
`+[NSURL fileURLWithPath:]` at `0x42594a7c` allocates, initializes, and
autoreleases as the current source does.

The current `initFileURLWithPath:` differs in three observable branches: it
does not append a delimiter for an existing directory, it substitutes `.` if
standardizing a relative path produces an empty string, and it passes a
relative path directly to `initWithString:` without URL-path standardization.
These differences are confirmed by the function's call order and value flow;
no source change was made during this analysis.

## Relative path accessor comparison (2026-10-04)

IDA confirms `-[NSURL _absoluteURLPath]` (`0x425952fc`) resolves a non-absolute
relative path by splitting the base URL path, removing its last component,
then appending the relative path components and reducing `.` and `..`. The
current source splits the base path and appends the relative path without
removing the base's last component first. For a base path such as
`/dir/file` and relative path `next`, this produces `/dir/file/next` in source,
while the target resolves `/dir/next`.

The target's `_relativeURLPath` (`0x42595224`) returns nil for a missing or
empty path, and `path` (`0x42595700`) standardizes the resolved path through
`standardizedNativePath`. Current `relativePath` follows the nil result for an
empty component, but current `path` explicitly returns an empty string for an
empty path component. No source change was made during this analysis.

## File URL and relative path corrections (2026-10-04)

`NSURL.m` now follows the IDA call order in `-[NSURL initFileURLWithPath:]`:
standardize relative paths, ask the default file
manager whether the result is a directory, append `/` for directories, and
standardize a remaining relative path as a URL path before `initWithString:`.
The target initializer tests its `isDirectory` output regardless of the
lookup result. `NSFileManager fileExistsAtPath:isDirectory:` leaves that
output untouched on failure, so the source's earlier initialization to `NO`
was removed to preserve the target's stack-residue behavior.

`-[NSURL _absoluteURLPath]` now removes the base URL's final path component
before appending a relative reference and reducing `.` / `..` components, as
the target does. This fixes references such as base `/dir/file` plus relative
`next`, which resolve to `/dir/next`.

Static selector, source-list, and whitespace checks passed. No tests or builds
were run.

## `path` forwarding correction (2026-10-04)

IDA confirms `-[NSURL path]` at `0x42595700` sends `_absoluteURLPath` and then
`standardizedNativePath`. The source now uses that same sequence. This also
preserves nil for a URL with no path component and resolves relative URLs
through the corrected `_absoluteURLPath`; the previous implementation parsed
`absoluteString` itself and returned an empty string for an empty path.

`-[NSURL relativePath]` at `0x42595288` independently extracts the relative
URL's path component and standardizes it as a native path, returning nil when
the component is absent or empty; the existing source matches that behavior.

The `-[NSURL initWithScheme:host:path:]` recheck at `0x42594828` confirms its
only explicit rejection is a non-absolute path. The source no longer rejects a
nil scheme before escaping and formatting it, matching the target's branch.

## Generic URL delegation corrections (2026-10-04)

IDA shows `-[NSURL scheme]` (`0x42594f58`) returns the base URL's scheme,
`-[NSURL resourceSpecifier]` (`0x42594f88`) returns `relativeString`, and
`-[NSURL absoluteURL]` (`0x42594ee8`) returns self only when there is no base
URL. The source now follows those generic-class paths. `NSAbsoluteURL` already
overrides `scheme` and `resourceSpecifier`, so absolute URLs retain their
subclass behavior.

## `absoluteString` component merge correction (2026-10-04)

IDA at `0x42594bc0` confirms that `-[NSURL absoluteString]` parses the
receiver's relative string and its base URL's relative string, then merges by
component. For an ordinary relative path it preserves the base prefix before
the base path, resolves the receiver path through `_absoluteURLPath`, and
appends any suffix after the path. Network-path references inherit the base
scheme when one exists; parameter and query references use separate prefix
and suffix branches. The target does not early-return the base URL when its
scheme is nil.

`NSURL.m` now follows those branches and reads the base URL's `relativeString`
instead of recursively expanding it with `absoluteString`. It uses raw parser
ranges here because the method relies on zero offsets for absent components.
The reference parser at `0x4259596c` confirms parameter, query, and fragment
ranges begin after their delimiters. The prior local scheme detector and RFC
dot-path merger were removed because the target delegates path resolution to
`_absoluteURLPath`. No tests or builds were run.
