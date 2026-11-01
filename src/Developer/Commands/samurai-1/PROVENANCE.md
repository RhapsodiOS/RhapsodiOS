# Samurai for RhapsodiOS

Source: https://github.com/raynorpat/samurai

Imported commit: `a520a9654c6ff97616b094be3262e523a9357799`.
The complete source license is retained in `samurai/LICENSE`.
The package version is the import date for this untagged snapshot; samu's
`--version` reports the supported Ninja language version, 1.9.0.

The common sources use C89 syntax. Rhapsody builds use its existing BSD
64-bit integer types and `strtoq`/`strtouq`, rather than C99 headers and
conversion functions. String storage uses an allocated character buffer
instead of a flexible array member. Hash constants are assembled from
32-bit halves for the native compiler; hash and log formats are preserved.
The native GCC 2.7.2.1 optimizer produces incorrect hashes, so only htab.c
is compiled with `-O0` on Rhapsody. Upstream hash vectors guard this workaround.

The POSIX backend uses fork/exec. Rhapsody uses select for job-output and
signal-pipe readiness, gettimeofday for progress timing, and its stat
nanosecond fields for dependency timestamps. A formatting adapter permits
zero-length snprintf/vsnprintf queries against the older libc. No librt
or newer POSIX runtime is required. The Windows backend is retained from
the fork but is not part of the Rhapsody build.

Build and test with `gnumake test`. Install through rbuild or with
`gnumake install DSTROOT=/staging/root`. The wrapper preserves RC_CFLAGS
for native i386 and ppc builds, and installs samu, its manual and license.
