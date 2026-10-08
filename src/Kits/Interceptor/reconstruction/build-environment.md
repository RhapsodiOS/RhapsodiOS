# Interceptor build and analysis environment

Host tools found during Task 2:

- IDA Professional 9.4: `C:\Program Files\IDA Professional 9.4\idat.exe`. Its reference exports contain 392 PowerPC and 419 i386 function records.
- Ghidra 12.1.2 at `D:\ghidra\support\analyzeHeadless.bat`, with Java 21. A synthetic i386 dylib fixture succeeds. A real DR2 run succeeds when its scratch directory is outside the hidden `.codex` path.
- angr 9.3.0 in `D:\RhapsodiOS\.venv-binrecon`. A synthetic i386 dylib fixture succeeds.
- Binrecon now accepts 32-bit MH_DYLIB images in either byte order.

The historical Rhapsody SDK, Project Builder make, and MIG are not yet verified in the isolated worktree. The primary checkout contains an i386 Rhapsody image at `D:\RhapsodiOS\vm\work\rhap-i386-bootstrapped.img`; snapshot-mode QEMU boots it to a root single-user shell. A second image, `devzero-i386-build2.qcow2`, also reaches that shell. Both report Rhapsody Kernel Release 5.3 i386. The checked compiler and SDK paths (`/usr/bin/cc`, `/usr/bin/gcc`, `/usr/bin/make`, `/NextDeveloper/Tools`, `/NextDeveloper/Executables`, and `/Developer/Tools`) are absent from both images. The configured SSH route returned `Connection refused`; no PowerPC guest has been identified. The guest can run shell probes, but it cannot currently build the reconstructed framework or execute its compiled tests.

## Native Task 3 probe

The current Windows host exposes GNU make and QEMU, but `cc`, `gcc`, `clang`,
`otool`, and `llvm-objdump` are not on `PATH`; the managed checkout has no
`vm/vm.conf`. Native i386 single-user execution is available through the
existing primary-checkout disk images, but neither image has a compiler or
developer SDK at the checked paths. The historical linker, MIG, and framework
import libraries also remain unavailable. Do not treat source-level checks or
the native shell probes as a successful framework build.

The target commands are:

```sh
make RC_ARCHS=ppc OBJROOT=<external-ppc-obj> SYMROOT=<external-ppc-sym> DSTROOT=<external-ppc-dstroot>
make RC_ARCHS=i386 OBJROOT=<external-i386-obj> SYMROOT=<external-i386-sym> DSTROOT=<external-i386-dstroot>
make -C tests abi RC_ARCHS=ppc FRAMEWORK_ROOT=<selected-framework-bundle>
make -C tests abi RC_ARCHS=i386 FRAMEWORK_ROOT=<selected-framework-bundle>
```

They are documented but not runnable on this host until the compatible guest
and SDK are configured. The test runner accepts either a framework bundle root
(loading `Versions/A/Interceptor`) or an explicitly selected thin dylib path.
It must run in a separate process for each selected architecture/framework.

The current Windows GNU make invocation uses `cmd.exe`, so the POSIX test
recipe fails at `mkdir -p` before compiler discovery. `bash.exe` on `PATH` is
the WSL launcher and there is no configured Linux distribution. Direct
`rect` and `palette` test attempts therefore do not reach compilation or
execute their fixtures.

The palette test Makefile parses in dry-run mode. The framework Makefile dry
run cannot resolve `$(MAKEFILEPATH)/pb_makefiles/platform.make` on this host,
so it also stops before compiling any Objective-C source.

## Analyzer agreement limit

All three i386 exporters individually accepted the DR2 image. They produced 419 IDA, 416 Ghidra, and 1085 angr function records. IDA and Ghidra relocation encodings also differ. Running all three through the current consensus publisher fails with `relocation 0 has missing or conflicting width`. The committed i386 profile therefore uses IDA for its stable address inventory. Ghidra and angr outputs remain independent review evidence under `C:\Users\raynorpat\Downloads\test\Interceptor-evidence\adapters-i386` and are not committed.

A Ghidra run whose project directory was under the managed checkout failed because `.codex` is not permitted in a Ghidra project path. Moving analyzer output to the external evidence directory resolved that path constraint; it was not a binary loader failure.
