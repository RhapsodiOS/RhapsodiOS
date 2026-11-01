# Universal Samurai kernel validation

Validated on 2026-10-15. This extends the existing
`kernel-samurai-validation.md` and `kernel-samurai-ppc-validation.md` records.

## Build interface

From `src/kernel-7`:

```sh
samu -f build-universal.ninja
samu -f build-universal-debug.ninja
```

These produce `BUILD.ninja/{RELEASE,DEBUG}_UNIVERSAL/mach_kernel` and
`mach_kernel.sys`. Each entry invokes the existing matching i386/PPC entry
manifests with separate architecture logs and output directories. The child
builds check their dependencies on every invocation; `restat` prevents
unchanged outputs from triggering packaging. Each child uses one job.

Historical `lipo -create` combines PPC first, then i386. Packaging writes a
temporary file, refreshes its timestamp, and publishes it after success.
Ordinary universal clean preserves child-owned thin products. Architecture
manifests, existing Makefiles, and non-kernel source projects are unchanged.
No build generator was introduced.

## Native tests

Tests used the owned `kernel-samurai-universal` QEMU snapshot of the Rhapsody
i386 build guest, Samurai 1.9.0 built from the in-tree project, Apple cc-771.4
(GCC 2.7.2.1), and the installed historical `/usr/bin/lipo`. After the initial
run, the guest booted the previously verified DEBUG_I386 kernel from the
i386 milestone. Persistent test files lived under `/build`; startup clears
`/tmp`.

The Samurai project test/install checks passed. The final native
`ninja/tests/universal.sh` suite passed using small native Mach-O executable
fixtures built with `cc -g`, `ld`, and `strip` for both architectures and
configurations. Its child graphs copy controlled inputs to test the real
coordinator and real `lipo` without recompiling the full kernel. It checked:

- Both fat outputs extract to their exact thin inputs.
- Changing only a stripped i386 input repackages only the stripped output.
- An unchanged build performs no slice generation or packaging.
- Child exit status 17 stops packaging; a retry succeeds.
- Invalid Mach-O input fails `lipo`, preserves published files, and recovers.
- Missing fat and thin files regenerate correctly.
- RELEASE clean removes both universal files while preserving all thin
  files and the DEBUG universal kernel.

The in-tree cctools `lipo` preserves input timestamps. A regression wrapper
delegating to the real native tool and restoring the older input timestamp
reproduced repeated packaging on idle. Refreshing the temporary output's
timestamp fixed this; the final suite includes the passing regression.

Native shell probes also exposed test-harness portability issues:
`set -e` exits a failing function even when invoked inside `if`, and
`command -v` is unsupported. Expected failures now call Samurai directly,
and tool discovery uses `which`. Copy-if-changed fixture edges use `restat`
to preserve idle behavior for unchanged members of a multi-output action.

All six entry manifests passed host parsing; the new shell test passed
syntax checks. Independent review found no remaining actionable issues.

## Full kernel products

The full-size packaging run reused the previously verified i386 kernels
from `boot-final5` and PPC Samurai kernels from the PPC milestone. It used
the final universal manifests and copy-only child fixtures with those
immutable inputs. Full kernel compilation was not repeated for this
extension; the unchanged architecture builds and Make comparisons are
covered by the earlier records.

Both configurations packaged successfully and returned to idle. Independent
host inspection of all four saved fat files verified exactly two Mach-O
executable slices, PPC first, correct alignment, and byte-for-byte equality
of all eight slices against the original thin kernels.

| Configuration | File | Bytes | POSIX cksum |
| --- | --- | ---: | ---: |
| RELEASE_UNIVERSAL | `mach_kernel` | 4,694,840 | 1791626389 |
| RELEASE_UNIVERSAL | `mach_kernel.sys` | 58,434,708 | 3958563644 |
| DEBUG_UNIVERSAL | `mach_kernel` | 5,163,684 | 348513699 |
| DEBUG_UNIVERSAL | `mach_kernel.sys` | 58,893,804 | 2036386597 |

One earlier full-size run on the initial Oct 10 guest kernel produced a fat
RELEASE `.sys` file with 16 zeroed bytes in PPC debug data; all thin inputs
retained their original checksums. Standalone serial/parallel creation and
four repeated extractions produced the independently calculated expected
checksum. The cause of that first mismatch was not established, and no
kernel/tool fix is claimed. The final archived products passed independent
host comparison of every slice; none contain that mismatch.

## Boot checks

The initial i386-first DEBUG fat file stalled before kernel startup with
the guest's DR2 booter 5.0.2. A PPC-first DEBUG file containing the same thin
slices subsequently booted to SSH. The manifests retain this tested layout;
actual full-size fat headers were checked because `lipo` sorts by alignment.

Both final universal kernels booted through their i386 slices to SSH. Each
product matched its booted `/mach_kernel` byte for byte. Running versions
identified `BUILD.ninja/RELEASE_I386` and `BUILD.ninja/DEBUG_I386`,
respectively. Fat-file inspection and i386 extraction matched the original
thin kernels. Filesystem copy/compare and process-list smoke checks passed
for both configurations.

PPC CPU execution remains unverified because no usable PPC boot environment
was available. The i386 results do not establish PPC boot qualification.

## Retained evidence

Host artifacts are under
`D:/RhapsodiOS/vm/work/kernel-samurai-universal-20261015/`:

| Archive | Bytes | POSIX cksum | SHA-256 |
| --- | ---: | ---: | --- |
| `universal-products.tgz` | 44,537,618 | 1673454159 | `17668381a3924eb3ac24e0d568c1f94176848c88e031247800560468f16b781a` |
| `universal-tests.tgz` | 2,086 | 3333416213 | `150716db4823278385d7ea2fcc11219d18ba224cb2e220720d7195ce8f228ca7` |

Guest and host archive checksums match. The 44 archived text logs contain
no NUL bytes. `products-report.json` records every fat/slice SHA-256 and
size; extracted fat kernels are under `products/`. Boot and diagnostic logs
are saved beside the archives. Earlier failed attempts are retained.

The read-only base image SHA-256 matched
`6e55911ca3439d6cc24e687c17437c033c717df36520fce37407b0a97eed40f5`.
