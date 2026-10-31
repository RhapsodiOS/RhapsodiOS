# Terminal build and analysis environment

## Repository support observed

- `src/rbuild-1/toolchains/gcc-darwin-ppc.conf` and
  `gcc-darwin-i386.conf` exist; a universal profile also exists.
- `vm/README.md` documents remote Rhapsody guest builds through
  `vm/sync-src.ps1` and `vm/build-src.ps1`. The documented default guest is the
  PowerPC build box; the architecture profile mechanism also has i386 support.
- The guest procedure relies on local `vm.conf` credentials. Do not read or
  disclose that file. No guest connection/build was attempted during inventory.
- The Terminal reference requires AppKit, Foundation, and System framework
  versions present on the original system (see `reference.md`).

## Analysis tools

- Binrecon source and profiles are under `tools/binrecon`.
- IDA Professional 9.4 is installed at
  `C:/Program Files/IDA Professional 9.4/idat.exe`; 9.2 is not installed at the
  path used by existing profiles. The Terminal profile records 9.4 and verifies
  the version reported by the analyzer. The repository README documents 9.2, so
  check adapter compatibility and retain the actual run evidence before relying
  on the newer version.
- `D:/ghidra/support/analyzeHeadless.bat` exists, but current binrecon only
  supports Ghidra on i386. Java version and successful invocation remain to be
  checked when an i386 artifact is available.
- The repository's ignored `.venv-binrecon` is present in this worktree and
  provides the pinned Python 3.12 binrecon environment used for validation.

## Pending environment discovery

No full Terminal build command has been established. The framework headers
below support target syntax checks, while linking and guest runtime remain
unverified. Recover the historical Project Builder application rules and
verify isolated guest images before claiming either architecture builds or
runs. PPC decompilation and source-map analysis are available through IDA 9.4.

## Native build status

The Terminal reference resources are preserved under `Resources/`. Project
Builder metadata uses the repository's historical `app.make` rules and the
observed AppKit/Foundation dependencies. The host exposes a Windows `make` shim,
LLVM Clang 22, and Rhapsody PPC/i386 cross-toolchain profile files, but no
verified Terminal application build command or usable guest build has been
established. The app source manifest contains the recovered implementation
units; project metadata validation is not a linked artifact. The Services
protocol header is copied from the separate Developer header and hash-verified;
the in-bundle header is only a 66-byte stub.

LLVM Clang 22 parses the changed Objective-C/C translation units for both
`powerpc-apple-rhapsody` and `i386-apple-rhapsody` using the recovered SDK at
`C:\Users\raynorpat\Downloads\test\Frameworks\System.framework\Versions\B\Headers`
and AppKit/Foundation headers from the DR2 framework directory. Framework
qualified junctions under `%TEMP%\rhapsodios-terminal-sdk-shim` expose the
versioned flat AppKit/Foundation headers as `AppKit/...` and `Foundation/...`;
the System header root, `bsd`, and `objc` directories expose runtime/BSD
declarations. The compiler needs `-fno-builtin`, `-DAPPKIT_EXTERN=extern`, and
the target macro (`-Dppc=1` or `-Di386=1`) for these legacy headers. The current
TerminalDO, ServiceProvider, ServiceCache, TerminalApp, Terminal, TerminalAgent,
and TerminalDefaults Objective-C units all pass syntax checks for both target
triples. `ServiceCache.m` also emits an i386 object. The host LLVM Clang 22
installation has no PowerPC code-generation backend, so it cannot emit the PPC
object even though PPC syntax checks pass. These checks do not link the
application or prove guest runtime behavior. `ShellExec.c` also passes strict
C89 `-Wall -Wextra -Werror` checks
for both target triples. `Shell.m` parses for both and retains the pre-existing
`findslot:` local-`slot` shadow warnings. The shell helper host test stubs
`execvp` and passes tokenization, quoting, escaping, and ordinary/login argv
construction cases.

On 2026-10-05, the full 54-file Terminal `MFILES` manifest passed Clang syntax
checks for both `powerpc-apple-rhapsody` and `i386-apple-rhapsody` with the
recovered DR2 headers and the System `bsd` headers. This pass corrected the `task_threads`
array type to the SDK's `thread_array_t`, imported the `PSsetgray` declaration,
and aligned the process-name buffer call and zero-valued arguments with their
declared types. A fresh manifest-wide syntax pass confirms all 54 translation
units pass for both target triples with the BSD headers ordered ahead of the
temporary host shims. `make -C src/Applications/Administration/Terminal/tests
CC="C:/Program Files/LLVM/bin/clang.exe"` passes all host-side test targets,
including the new scrollback-boundary regression test. The focused binrecon
source-map/ledger suite passes (49 tests); a fresh host-suite run on
2026-10-05 also exited successfully. The PPC reference identity and
793-entry ledger validated at that point; the ledger then recorded 638
control-flow-confirmed and 155 signature-confirmed entries, with zero
unexamined functions. Syntax and host tests do not link the application or
verify guest runtime behavior.

On 2026-10-05, a fresh run in this checkout passed all 14 host C regression
targets, including the scrollback-boundary regression. Binrecon's focused
source-map, ledger, and profile tests passed (145 passed, 1 skipped); profile
validation rechecked the 333,472-byte PPC input hash, and ledger validation
reported 793 entries (638 control-flow-confirmed, 155 signature-confirmed at
that time).
The full cross-target Clang manifest command could not be reproduced in this
PowerShell session because Clang did not resolve the existing temporary SDK
shim junctions through its include search paths; no source change was made from
that failed invocation.

On 2026-10-05, the documented Python environment ran the full binrecon suite:
978 passed and 4 skipped. This exposed a stale PPC profile inventory assertion;
`tools/binrecon/tests/test_profile.py` now includes `terminal-ppc.json`. The
Terminal host tests also pass after rebuilding and running each Windows test
as an explicit `.exe`; this avoids accidentally executing a stale `.exe` when
make's previous extensionless output was built on Windows.

All 54 manifest files emit i386 Mach-O object files when compiled with LLVM's
`i386-apple-darwin` triple and fragile 10.4 Objective-C runtime, with the
recovered DR2 headers, BSD headers before host shims, and the Rhapsody `i386`
preprocessor define. On 2026-10-05, a fresh pass produced 33 Objective-C and
21 C objects with source-extension-qualified filenames in a temporary
directory, avoiding the `Filer.m`/`Filer.c` basename collision. This
compatibility-target object pass does not establish a Rhapsody executable:
`ld64.lld` rejects `-arch i386` as unsupported, and the host has no compatible
Rhapsody linker or startup objects. The direct `i386-apple-rhapsody` triple
passes syntax checks but LLVM emits ELF objects for it. PPC object generation
is unavailable in this LLVM installation.

The configured PPC guest was checked read-only on 2026-10-05, but its SSH
connection was refused at `127.0.0.1:2222`. No source was synced and no remote
build was attempted; retry guest builds once the SSH service is available.

On 2026-10-05, native binrecon reanalysis of the pinned PPC executable
completed with IDA 9.4 and reproduced the published analysis and consensus
hashes. The refreshed analysis validates against the complete 793-entry PPC
source map. The current ledger validates at 638 control-flow-confirmed and
155 signature-confirmed entries, with none unexamined. The full binrecon suite
passes 978 tests with 4 skips, and the Terminal host suite passes all 14
targets. Normalized-function acceptance remains false because no rebuilt
Terminal executable is configured. No i386 Terminal reference binary or
reachable Rhapsody guest is available, so i386 binary comparison and native
guest application build/runtime verification remain open.

An additional native check on 2026-10-05 validates the current 793-entry PPC
ledger at 640 control-flow-confirmed and 153 signature-confirmed, along with
the saved IDA analysis and source map at 640 mapped and 153 unmapped entries.
The focused Terminal selector suite passes 16 tests, and the Terminal host
test suite exits successfully. Existing compiler logs show all 55 production
translation units pass PPC and i386 syntax checks, although the same-turn
manifest command could not resolve the temporary framework include junctions
from the current shell. A read-only port check found the configured PPC guest
SSH service at `127.0.0.1:2222` unavailable. The host still cannot link either
architecture into a Rhapsody app, and no guest app runtime was verified.

On 2026-10-05, the full binrecon test suite passed again (1,008 passed, 4
skipped) using the documented `PYTHONPATH=tools/binrecon` invocation. The
Terminal Windows host test makefile rebuilt and ran all 14 regression targets
successfully. A direct `make -C src/Applications/Administration/Terminal`
attempt stopped before compilation because this host does not define
`MAKEFILEPATH`, so the historical `/pb_makefiles/platform.make` include could
not be resolved. The Project Builder target still needs its Rhapsody makefile
tree and a compatible PPC/i386 linker; this host's LLVM linker rejects both
architectures, and no guest configuration is present in `vm.conf`. No app
binary was linked or run.
On 2026-10-05, PPC IDA review of `ServiceProvider provideService:userData:error:` found that the implementation sent `checkSettings` to the menu item's `NSUserData`. `ServiceCache updateServicesFile` serializes that field as a decimal `NSString`, so the provider now sends `intValue` before matching the service record's sequence. `ServiceProvider.m` passes Clang syntax checks for both `powerpc-apple-rhapsody` and `i386-apple-rhapsody` using `-fobjc-runtime=macosx-fragile-10.4`, the recovered DR2 SDK shim, and System BSD headers. The complete Terminal host test suite passes. These checks do not establish linked app or guest-runtime behavior.

The 2026-10-05 native save-scan correction passes PPC/i386 `TerminalApp.m`
syntax checks, the complete Terminal host test suite, PPC ledger validation,
and semantic source-map validation (640 mapped, 153 classified runtime/import
entries). A fresh `make -C src/Applications/Administration/Terminal -n`
attempt stops before compilation because `/pb_makefiles/platform.make` is not
available on this host. Linking and guest runtime therefore remain unverified.

On 2026-10-05, project manifest auditing found `TerminalLaunch.c` present in
`Makefile` but missing from `PB.project`, which would leave the Project Builder
application target without its launch implementation. The two manifests also
differed on `ShellController.h`, `TerminalLaunch.h`, and `TerminalServices.h`.
Both source and header lists now match exactly (56 translation units and 55
headers), and a regression test guards that parity and verifies every listed
file exists. `TerminalLaunch.c` passes PPC and i386 target syntax checks, and
its native launch-helper regression passes. This closes manifest consistency;
the app still cannot be linked or run here without the historical Rhapsody
build tree and compatible linker/runtime.

On 2026-10-05, native execution validation was repeated against the current
Terminal source. All 56 `MFILES` translation units pass Clang syntax checks
for both `powerpc-apple-rhapsody` and `i386-apple-rhapsody`. The complete
Terminal host regression suite passes all 14 targets, and the full binrecon
test suite passes (1,057 passed, 4 skipped). Binrecon IDA 9.4 completed a new
analysis of the pinned 333,472-byte PPC executable (SHA-256
`B83EDEF820DF31A406FBFBBFB86DD5B80DB6818BD6D8BD14211680F2BD8E57D7`),
exporting 793 functions. The PPC source map validates against that analysis:
640 functions map to source, 153 are classified runtime/import entries, and
there are no boundary disputes. The ledger validates with 640
control-flow-confirmed and 153 signature-confirmed entries. The profile has no
rebuilt artifact, so normalized-function comparison remains unavailable; no
application executable was linked or run. PPC code generation and the
Rhapsody guest build/runtime remain unavailable in this host environment.
