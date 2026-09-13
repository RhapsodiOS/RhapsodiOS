# Universal rbuild repository bootstrap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the live `/build/repo` so every `BootstrapManifest` package is a real i386+ppc universal APK, then prove ordinary universal `buildpackage` and `rbuild kernel --arch i386` against that repo.

**Architecture:** Keep thin `rbuild bootstrap` and `target_arch=ppc`. Add `rbuild bootstrap-universal` as the primary documented method: require an already-thin sysroot, rebuild `Csu` through `Libsystem` fat, then rebuild the full manifest fat in the same repo. Compile-probe every CPU; link-probe a CPU only when sysroot `crt1.o` and `System` already contain that slice. No `golden.img` seeds.

**Tech Stack:** C89 rbuild, existing test macros, POSIX guest make/cc/lipo, APK tar/gzip, 32-bit Mach-O, PowerShell `build-src.ps1`.

**Approved design:** `docs/superpowers/specs/2026-09-13-rbuild-universal-bootstrap-design.md`.

---

## Working rules and sequence

Implement tasks in order. Do not parallelize builder/runner/CLI changes.

Use an isolated checkout for implementation. The current tree has unrelated driver work; do not mix those files into this branch. Create `.worktrees/rbuild-universal-bootstrap` from the spec commit (verify `.worktrees` is gitignored first).

Run C tests from `src/rbuild-1` on the Rhapsody guest (`make test`, `make trace-test`). PowerShell is not the native test shell. Host script tests run on Windows: `powershell -NoProfile -File vm\tests\test-build-src.ps1`.

Do not wipe `/build/repo` until Task 9. Earlier tasks use private `/tmp` fixtures only.

For each task: add the specified regression first, observe the relevant failure, implement, rerun the focused checks, commit only the task files. A missing compiler is not a successful regression failure.

## File responsibilities

| Files | Responsibility |
| --- | --- |
| `src/rbuild-1/architecture.c`, `tests/test_architecture.c` | Universal operation mask in `architecture_resolve` |
| `src/rbuild-1/builder.c`, `builder.h`, `tests/test_builder.c` | Keep thin bootstrap; honor universal bootstrap operation; per-CPU link readiness |
| `src/rbuild-1/main.c`, `runner.c` | `bootstrap-universal` CLI, sysroot prerequisite, two native walks |
| `src/rbuild-1/tests/bootstrap-resume.sh`, `tests/bootstrap-runtime-manifest.sh`, `Makefile` | Resume/quarantine and runtime-manifest subsequence |
| `src/BootstrapManifest`, `src/BootstrapRuntimeManifest` | Runtime block order and the subsequence file |
| `src/Csu-1/*` | Per-arch dyld stubs and fat installed `/usr/lib/dyld` |
| `src/Libsystem-2/Makefile`, `Makefile.postamble` | Per-arch `System.order.*` and object-dir links |
| `vm/build-src-lib.ps1`, `vm/tests/test-build-src.ps1` | `-Bootstrap` runs thin then `bootstrap-universal` |
| `src/rbuild-1/README.md`, `README.md`, `vm/README.md`, `docs/build/rbuild-universal.md` | Primary method and guest evidence |

Do not change APK filenames, kernel `--arch` parsing, or ordinary universal defaults.

## Task 1: Allow universal as an architecture operation

**Files:** Modify `src/rbuild-1/architecture.c`, `src/rbuild-1/tests/test_architecture.c`.

- [ ] **Step 1: Update `test_resolve` so operation 3 is legal for universal source**

In `src/rbuild-1/tests/test_architecture.c`, replace the validity condition inside `test_resolve` with:

```c
int valid = operation == 0 || (source & operation) == operation;
```

Add this assertion at the end of `test_resolve`, after the nested loops:

```c
{
    unsigned effective = 99;
    CHECK_INT(architecture_resolve(RB_ARCH_UNIVERSAL, RB_ARCH_UNIVERSAL,
                                   &effective), 0);
    CHECK_INT(effective, RB_ARCH_UNIVERSAL);
    effective = 99;
    CHECK(architecture_resolve(RB_ARCH_I386, RB_ARCH_UNIVERSAL,
                               &effective) != 0);
    CHECK_INT(effective, 99);
    effective = 99;
    CHECK(architecture_resolve(RB_ARCH_PPC, RB_ARCH_UNIVERSAL,
                               &effective) != 0);
    CHECK_INT(effective, 99);
}
```

- [ ] **Step 2: Run the architecture test and confirm it fails**

Run: `cd src/rbuild-1 && make tests/test_architecture && ./tests/test_architecture`

Expected: FAIL on `architecture_resolve(3, 3, …)` (operation 3 currently rejected).

- [ ] **Step 3: Accept universal in `architecture_resolve`**

Replace the function in `src/rbuild-1/architecture.c` with:

```c
int architecture_resolve(unsigned source, unsigned operation, unsigned *effective) {
    if (source < RB_ARCH_I386 || source > RB_ARCH_UNIVERSAL)
        return 1;
    if (operation != 0 && operation != RB_ARCH_I386 &&
        operation != RB_ARCH_PPC && operation != RB_ARCH_UNIVERSAL)
        return 1;
    if (operation != 0 && (source & operation) != operation)
        return 1;
    *effective = operation ? operation : source;
    return 0;
}
```

- [ ] **Step 4: Re-run the architecture test**

Run: `cd src/rbuild-1 && ./tests/test_architecture`

Expected: `tests/test_architecture.c: … checks, 0 failures`

- [ ] **Step 5: Commit**

```bash
git add src/rbuild-1/architecture.c src/rbuild-1/tests/test_architecture.c
git commit -m "rbuild: allow universal as an architecture operation"
```

## Task 2: Honor universal operation during bootstrap resolve

**Files:** Modify `src/rbuild-1/builder.c`, `src/rbuild-1/tests/test_builder.c`.

Thin bootstrap must still force the profile CPU when `operation_arch` is 0. Universal bootstrap keeps `operation_arch == RB_ARCH_UNIVERSAL` and still requires a thin profile `target_arch`.

- [ ] **Step 1: Add `test_bootstrap_universal_resolve` to `tests/test_builder.c`**

Place it immediately after `test_resolved_thin_flags`. Reuse the existing `toolchain_fixture` helper already in that file:

```c
TEST(test_bootstrap_universal_resolve) {
    Package pkg;
    BuildOptions opt;
    Toolchain tc;
    package_init(&pkg);
    build_options_init(&opt);
    toolchain_fixture(&tc);
    opt.bootstrap = 1;
    opt.toolchain = &tc;
    opt.operation_arch = RB_ARCH_UNIVERSAL;
    CHECK_INT(builder_resolve_architecture(&pkg, &opt), 0);
    CHECK_STR(pkg.architecture, "universal-apple-rhapsody");
    CHECK_INT(opt.effective_arch, RB_ARCH_UNIVERSAL);
    CHECK_INT(opt.operation_arch, RB_ARCH_UNIVERSAL);
    package_set(&pkg.architecture, "i386");
    opt.operation_arch = RB_ARCH_UNIVERSAL;
    CHECK(builder_resolve_architecture(&pkg, &opt) != 0);
    package_set(&pkg.architecture, "ppc");
    opt.operation_arch = RB_ARCH_UNIVERSAL;
    CHECK(builder_resolve_architecture(&pkg, &opt) != 0);
    package_set(&pkg.architecture, 0);
    opt.operation_arch = 0;
    CHECK_INT(builder_resolve_architecture(&pkg, &opt), 0);
    CHECK_STR(pkg.architecture, "ppc-apple-rhapsody");
    CHECK_INT(opt.effective_arch, RB_ARCH_PPC);
    package_free(&pkg);
}
```

Add `RUN(test_bootstrap_universal_resolve);` next to the other `RUN` lines in `run_all`.

- [ ] **Step 2: Run the focused builder test**

Run: `cd src/rbuild-1 && make tests/test_builder && ./tests/test_builder`

Expected: FAIL in `test_bootstrap_universal_resolve` because bootstrap currently overwrites operation with profile ppc (`got ppc-apple-rhapsody want universal-apple-rhapsody`).

- [ ] **Step 3: Keep universal operation in `builder_resolve_architecture`**

In `src/rbuild-1/builder.c`, replace the bootstrap block inside `builder_resolve_architecture` with:

```c
    if (opt->bootstrap) {
        unsigned profile_arch;
        if (!opt->toolchain ||
            architecture_parse(opt->toolchain->target_arch, &profile_arch) != 0 ||
            (profile_arch != RB_ARCH_I386 && profile_arch != RB_ARCH_PPC) ||
            (operation && operation != profile_arch &&
             operation != RB_ARCH_UNIVERSAL)) {
            fprintf(stderr, "rbuild: %s: invalid or conflicting bootstrap architecture '%s' for operation '%s'\n",
                    pkg->source ? pkg->source :
                    (pkg->package ? pkg->package : "(unknown)"),
                    opt->toolchain && opt->toolchain->target_arch ?
                    opt->toolchain->target_arch : "(missing)",
                    operation ? (architecture_label(operation) ?
                    architecture_label(operation) : "(invalid)") : "bootstrap");
            return 1;
        }
        if (operation != RB_ARCH_UNIVERSAL)
            operation = profile_arch;
    }
```

- [ ] **Step 4: Re-run `./tests/test_builder`**

Expected: `tests/test_builder.c: … checks, 0 failures`. Existing `test_resolved_thin_flags` and `test_build_rejects_unsupported_bootstrap_architecture` must still pass.

- [ ] **Step 5: Commit**

```bash
git add src/rbuild-1/builder.c src/rbuild-1/tests/test_builder.c
git commit -m "rbuild: keep universal operation during bootstrap resolve"
```

## Task 3: Per-CPU bootstrap link readiness

**Files:** Modify `src/rbuild-1/builder.c`, `src/rbuild-1/builder.h`, `src/rbuild-1/tests/test_builder.c`.

After a thin pass, `ld_flags_ready` exists but is ppc-only. Link-probe a CPU only when **both** sysroot `/lib/crt1.o` and the expanded `ld_flags_ready` System binary contain that slice. File existence is not enough. Ordinary (non-bootstrap) probes still always link.

Update the existing `test_toolchain_probes` empty-marker case: an empty `ready` file is not valid Mach-O, so it must stay compile-only. Add ppc-only crt/System fixtures when the test wants a ppc link.

- [ ] **Step 1: Extend `test_toolchain_probes`**

`probe_fixture`'s `cc` shim logs `$arch-$stage` to `/tmp/rb-probe-tools/calls` (`i386-compile`, `ppc-link`, …). Keep the current compile-only check when `ld_flags_ready` is missing. An empty `ready` file is not Mach-O, so it must also stay compile-only.

Insert this helper above `test_toolchain_probes` (cputype 18 = ppc, 7 = i386):

```c
static void write_macho(const char *path, unsigned char cputype) {
    unsigned char code[28];
    FILE *f;
    memset(code, 0, sizeof(code));
    code[0] = 0xfe; code[1] = 0xed; code[2] = 0xfa; code[3] = 0xce;
    code[7] = cputype;
    code[15] = 1;
    f = fopen(path, "wb");
    CHECK(f != 0);
    if (!f) return;
    CHECK_INT(fwrite(code, 1, sizeof(code), f), sizeof(code));
    fclose(f);
}
```

Replace the block that currently creates empty `ready` and expects `builder_probe_toolchain` to fail under `RB_PROBE_MODE=link`, through the following `RB_PROBE_MODE=ok` success, with:

```c
    f=fopen("/tmp/rb-probe-tools/ready","w");CHECK(f!=0);if(f)fclose(f);
    unlink("/tmp/rb-probe-tools/calls");
    CHECK_INT(builder_probe_toolchain(&p,&p,&opt),0);
    CHECK(!probe_text_has("/tmp/rb-probe-tools/calls","link"));
    mkdir("/tmp/rb-probe-tools/lib", 0755);
    write_macho("/tmp/rb-probe-tools/ready", 18);
    write_macho("/tmp/rb-probe-tools/lib/crt1.o", 18);
    setenv("RB_PROBE_MODE","ok",1);
    unlink("/tmp/rb-probe-tools/calls");
    opt.effective_arch=3;
    CHECK_INT(builder_probe_toolchain(&p,&p,&opt),0);
    CHECK(probe_text_has("/tmp/rb-probe-tools/calls","i386-compile"));
    CHECK(!probe_text_has("/tmp/rb-probe-tools/calls","i386-link"));
    CHECK(probe_text_has("/tmp/rb-probe-tools/calls","ppc-link"));
    write_macho("/tmp/rb-probe-tools/ready", 7);
    write_macho("/tmp/rb-probe-tools/lib/crt1.o", 7);
    unlink("/tmp/rb-probe-tools/calls");
    CHECK_INT(builder_probe_toolchain(&p,&p,&opt),0);
    CHECK(probe_text_has("/tmp/rb-probe-tools/calls","i386-link"));
    CHECK(probe_text_has("/tmp/rb-probe-tools/calls","ppc-compile"));
    CHECK(!probe_text_has("/tmp/rb-probe-tools/calls","ppc-link"));
    opt.effective_arch=1;
```

Keep the later `tc.ld_flags_ready=0` / `arch_flags` checks. They still run with `effective_arch=1`.

- [ ] **Step 2: Run `./tests/test_builder`**

Expected: FAIL. Empty `ready` currently forces a link attempt (`got 1 want 0` or unexpected `i386-link`).

- [ ] **Step 3: Implement per-slice link readiness**

In `src/rbuild-1/builder.c`, next to `toolchain_ready`, add:

```c
static int file_has_slice(const char *path, unsigned slice) {
    unsigned mask;
    int code;
    if (!path || macho_file_arches(path, &mask, &code) != 0 || !code)
        return 0;
    return (mask & slice) == slice;
}

static int slice_link_ready(const BuildOptions *opt, unsigned slice) {
    char *system_path;
    char *crt_path;
    int ready;
    if (!opt || !opt->bootstrap || !opt->toolchain) return 1;
    if (!toolchain_ready(opt->toolchain->ld_flags_ready, opt->sysroot))
        return 0;
    system_path = expand_toolchain_value(opt->toolchain->ld_flags_ready,
                                         opt->sysroot);
    crt_path = str_cats(opt->sysroot ? opt->sysroot : "", "/lib/crt1.o",
                        (char *)0);
    ready = file_has_slice(system_path, slice) && file_has_slice(crt_path, slice);
    free(system_path);
    free(crt_path);
    return ready;
}
```

In `builder_probe_toolchain`, delete the single `link_ready` computed once from `toolchain_ready`. Inside the per-slice loop, compute:

```c
        int link_ready = slice_link_ready(opt, slice);
```

and keep `for (pass = 0; !rc && pass < (link_ready ? 2 : 1); pass++)`.

Update the comment in `src/rbuild-1/builder.h` above `builder_probe_toolchain` to:

```c
/* Probe resolved slices in private OBJROOT directories. Bootstrap links a
 * CPU only when sysroot crt1.o and ld_flags_ready System contain that slice. */
```

- [ ] **Step 4: Re-run `./tests/test_builder` and `make tests/test_architecture`**

Expected: 0 failures.

- [ ] **Step 5: Commit**

```bash
git add src/rbuild-1/builder.c src/rbuild-1/builder.h src/rbuild-1/tests/test_builder.c
git commit -m "rbuild: link-probe a CPU only when sysroot already has that slice"
```

## Task 4: Runtime manifest and Csu-before-Libc order

**Files:** Create `src/BootstrapRuntimeManifest`, `src/rbuild-1/tests/bootstrap-runtime-manifest.sh`; modify `src/BootstrapManifest`, `src/rbuild-1/Makefile`, `vm/tests/test-build-src.ps1`.

`objc4`/`Libstreams` must stay **before** `Libsystem` (Libsystem harvests those objects). They must stay **after** `Csu` and `Libc` so i386 object compiles have crt and libc. Move the Libsystem component libs to immediately follow `Csu-1 all`, then language/runtime `all` targets, then `Libsystem-2 all`. Keep early `headers` rows where they are.

- [ ] **Step 1: Write `tests/bootstrap-runtime-manifest.sh`**

Create `src/rbuild-1/tests/bootstrap-runtime-manifest.sh`:

```sh
#!/bin/sh
set -e
root=`dirname "$0"`/../../..
full="$root/src/BootstrapManifest"
runtime="$root/src/BootstrapRuntimeManifest"
if test ! -f "$full" || test ! -f "$runtime"; then
    echo "bootstrap-runtime-manifest: missing manifest" >&2
    exit 1
fi
# Strip comments/blank lines to a three-column stream.
flat() { awk '$1=="dir" { print $1, $2, $3 }' "$1"; }
start=`flat "$runtime" | awk 'NR==1 { print $2, $3; exit }'`
test "$start" = "Csu-1 all" || {
    echo "bootstrap-runtime-manifest: must start at Csu-1 all" >&2
    exit 1
}
end=`flat "$runtime" | awk 'END { print $2, $3 }'`
test "$end" = "Libsystem-2 all" || {
    echo "bootstrap-runtime-manifest: must end at Libsystem-2 all" >&2
    exit 1
}
awk -v runtime="$runtime" '
    BEGIN {
        while ((getline line < runtime) > 0) {
            n = split(line, f, /[ \t]+/)
            if (f[1] != "dir") continue
            r[++rc] = f[1] " " f[2] " " f[3]
        }
        close(runtime)
        if (rc < 2) { print "bootstrap-runtime-manifest: runtime too short" > "/dev/stderr"; exit 1 }
    }
    $1=="dir" { f[++fc] = $1 " " $2 " " $3 }
    END {
        for (i = 1; i <= fc; i++) if (f[i] == r[1]) { s = i; break }
        if (!s) { print "bootstrap-runtime-manifest: Csu-1 all missing from BootstrapManifest" > "/dev/stderr"; exit 1 }
        for (j = 1; j <= rc; j++) {
            if (f[s + j - 1] != r[j]) {
                print "bootstrap-runtime-manifest: not a contiguous subsequence at " r[j] > "/dev/stderr"
                exit 1
            }
        }
        print "bootstrap-runtime-manifest: PASS"
    }
' "$full"
```

- [ ] **Step 2: Run the script**

Run: `sh src/rbuild-1/tests/bootstrap-runtime-manifest.sh`

Expected: FAIL (`missing manifest` or subsequence error). Do not create the runtime file yet.

- [ ] **Step 3: Reorder `BootstrapManifest` and add `BootstrapRuntimeManifest`**

In `src/BootstrapManifest`, replace the block from `# CRT and language/runtime support.` through `dir     Libsystem-2             all` with:

```
# CRT, libc components, language/runtime objects, then System.
# Csu and Libc must precede i386 compiles of later runtime libraries.
# objc4/Libstreams objects must exist before Libsystem harvests them.
dir     Csu-1                   all
dir     Libc-1                  all
dir     Libcompat-1             all
dir     Libcurses-1             all
dir     Libedit-1               all
dir     Librpcsvc-1             headers
dir     Libinfo-1               all
dir     Libkvm-1                all
dir     Libm-1                  all
dir     objc4-1                 all
dir     Libstreams-1            all
dir     objc-1                  all
dir     machkit-1               headers
dir     machkit-1               all
dir     driverkit-3             all
dir     kernload-1              all
dir     Libsystem-2             all
```

Leave every earlier headers/tools row unchanged, including `objc4-1 headers` and `Libc-1 headers`.

Create `src/BootstrapRuntimeManifest` with the same comment header style as `BootstrapManifest` and exactly those `dir` rows (Csu-1 all through Libsystem-2 all).

Wire the script into `src/rbuild-1/Makefile` `test:` after `bootstrap-closure.sh`:

```
	MAKE=$(MAKE) sh tests/bootstrap-runtime-manifest.sh
```

In `vm/tests/test-build-src.ps1`, keep `Libstreams-1 all` before `objc-1 all`. Add:

```powershell
Assert-Match $bootstrapManifestText '(?s)dir\s+Csu-1\s+all.*dir\s+Libc-1\s+all.*dir\s+objc4-1\s+all.*dir\s+Libsystem-2\s+all' 'Csu and Libc are packaged before objc4 all and Libsystem'
```

- [ ] **Step 4: Re-run the subsequence script and host assertion file**

Run: `sh src/rbuild-1/tests/bootstrap-runtime-manifest.sh`

Expected: `bootstrap-runtime-manifest: PASS`

Run: `powershell -NoProfile -File vm\tests\test-build-src.ps1`

Expected: existing tests plus the new order assertion pass. If an old assertion encoded Libc-after-objc4-all, update that assertion to the new order rather than reverting the manifest.

- [ ] **Step 5: Commit**

```bash
git add src/BootstrapManifest src/BootstrapRuntimeManifest src/rbuild-1/tests/bootstrap-runtime-manifest.sh src/rbuild-1/Makefile vm/tests/test-build-src.ps1
git commit -m "rbuild: add BootstrapRuntimeManifest after Csu and Libc"
```

## Task 5: `rbuild bootstrap-universal` command

**Files:** Modify `src/rbuild-1/main.c`, `src/rbuild-1/runner.h` (only if a helper is declared), `src/rbuild-1/tests/bootstrap-resume.sh`; any small helper can live as `static` in `main.c`.

Behavior:

- Same flags as `bootstrap`.
- `RunnerOptions.bootstrap = 1` and `operation_arch = RB_ARCH_UNIVERSAL`.
- Refuse to start unless expanded `ld_flags_ready` exists and `$sysroot/usr/local/bin/indr` is executable. Print the missing path. Do not invoke thin bootstrap.
- Load `BootstrapRuntimeManifest` from the same directory as the caller-supplied srclist. Missing file is an error.
- Walk runtime manifest, then the caller-supplied full manifest, both via `runner_manifest`.
- Dry-run still performs both walks' planning.

- [ ] **Step 1: Add resume coverage for universal rebuild of thin state**

In `src/rbuild-1/tests/bootstrap-resume.sh`, after the existing `wrong-architecture` rebuild case succeeds, add a real `./rbuild bootstrap-universal` invocation against a private fixture that already has:

- a toolchain profile with `target_arch=ppc` and `ld_flags_ready=@SYSROOT@/System`
- `$root/System` present (empty file is enough for the **prerequisite** existence check in this task; link probes use Task 3 rules)
- `$root/usr/local/bin/indr` executable (`#!/bin/sh` / `exit 0`)
- `BootstrapRuntimeManifest` beside a tiny full manifest
- an existing ppc state record and thin APK for the first full-manifest package

Assert:

- missing `indr` prints `rbuild:` and the `indr` path and exits nonzero
- successful dry-run (`-n bootstrap-universal`) lists the runtime source before the later full-manifest source
- live `bootstrap-universal` prints `must build` for the ppc-state package (stale `effective_architecture`)

Match the fixture style already used in that script (same temp dir, same profile writer). Do not call `/usr/rbuild-root`.

- [ ] **Step 2: Run `MAKE=$(MAKE) sh tests/bootstrap-resume.sh` from `src/rbuild-1`**

Expected: FAIL (`unknown subcommand "bootstrap-universal"`).

- [ ] **Step 3: Implement the command**

Add to `USAGE` in `src/rbuild-1/main.c`:

```
    "  rbuild bootstrap-universal --sysroot ROOT --toolchain FILE --state DIR"
    " <srclist> <repository> <dstdir>\n"
```

Add these static helpers in `main.c` (need `<unistd.h>` if not already included):

```c
static char *sibling_path(const char *srclist, const char *name) {
    const char *slash = strrchr(srclist, '/');
    if (!slash) return xstrdup(name);
    {
        size_t n = (size_t)(slash - srclist);
        char *dir = xmalloc(n + 1);
        memcpy(dir, srclist, n);
        dir[n] = '\0';
        {
            char *out = path_join(dir, name);
            free(dir);
            return out;
        }
    }
}

static int bootstrap_sysroot_ready(const Toolchain *tc, const char *sysroot) {
    char *marker;
    char *indr;
    int rc = 0;
    marker = 0;
    if (tc->ld_flags_ready) {
        const char *p = tc->ld_flags_ready;
        const char *m = "@SYSROOT@";
        sbuf expanded;
        const char *hit;
        sbuf_init(&expanded);
        while ((hit = strstr(p, m)) != 0) {
            sbuf_putn(&expanded, p, (size_t)(hit - p));
            sbuf_puts(&expanded, sysroot ? sysroot : "");
            p = hit + sizeof("@SYSROOT@") - 1;
        }
        sbuf_puts(&expanded, p);
        marker = sbuf_steal(&expanded);
        sbuf_free(&expanded);
    }
    if (!marker || access(marker, F_OK) != 0) {
        fprintf(stderr, "rbuild: bootstrap-universal requires thin sysroot marker %s\n",
                marker ? marker : "(missing ld_flags_ready)");
        rc = 1;
    }
    indr = str_cats(sysroot, "/usr/local/bin/indr", (char *)0);
    if (!rc && access(indr, X_OK) != 0) {
        fprintf(stderr, "rbuild: bootstrap-universal requires %s\n", indr);
        rc = 1;
    }
    free(marker);
    free(indr);
    return rc;
}
```

Do **not** duplicate `@SYSROOT@` expansion long-term if a later cleanup can call a shared helper; for this task, duplicating the small expander in `main.c` is acceptable so `expand_toolchain_value` can stay `static` in `builder.c`.

Refactor `cmd_bootstrap` flag parsing into `cmd_bootstrap_args` shared by both commands, then:

```c
static int cmd_bootstrap_universal(int argc, char **argv) {
    /* parse the same --sysroot/--toolchain/--state + three paths */
    /* toolchain_load/validate as cmd_bootstrap */
    if (bootstrap_sysroot_ready(&tc, sysroot) != 0) { toolchain_free(&tc); return 1; }
    runtime = sibling_path(argv[i], "BootstrapRuntimeManifest");
    if (access(runtime, R_OK) != 0) {
        fprintf(stderr, "rbuild: missing BootstrapRuntimeManifest beside %s\n",
                argv[i]);
        free(runtime); toolchain_free(&tc); return 1;
    }
    memset(&opt, 0, sizeof(opt));
    opt.bootstrap = 1;
    opt.sysroot = sysroot;
    opt.state_dir = state;
    opt.toolchain = &tc;
    opt.toolchain_file = profile;
    opt.operation_arch = RB_ARCH_UNIVERSAL;
    rc = runner_manifest(runtime, argv[i + 1], argv[i + 2], &opt);
    if (rc == 0)
        rc = runner_manifest(argv[i], argv[i + 1], argv[i + 2], &opt);
    free(runtime);
    toolchain_free(&tc);
    return rc;
}
```

Dispatch `bootstrap-universal` next to `bootstrap` in `main`.

- [ ] **Step 4: Re-run `sh tests/bootstrap-resume.sh` and `./tests/test_builder`**

Expected: `bootstrap-resume: PASS` and builder tests 0 failures.

- [ ] **Step 5: Commit**

```bash
git add src/rbuild-1/main.c src/rbuild-1/tests/bootstrap-resume.sh
git commit -m "rbuild: add bootstrap-universal two-walk command"
```

## Task 6: Fat Csu dyld stub and installed dyld

**Files:** Create `src/Csu-1/dyld_stub_i386.s`; modify `src/Csu-1/Makefile`, `src/Csu-1/PB.project` only if that file lists sources (keep PB.project in sync if it enumerates `SFILES`).

Do not assemble ppc `blr` with `-arch i386`. Do not copy i386 dyld from `golden.img`.

- [ ] **Step 1: Add `src/Csu-1/dyld_stub_i386.s`**

```
/*
 * i386 MH_DYLINKER stub. Paired with dyld_stub.s (ppc) so fat crt1.o
 * and /usr/lib/dyld contain an i386 slice. ld only needs LC_ID_DYLINKER.
 */
	.text
	.align 2,0x90
	.globl _start
_start:
	ret
```

- [ ] **Step 2: Change Csu to compile stubs per arch and lipo installed dyld**

In `src/Csu-1/Makefile`:

- Add `LIPO = /usr/bin/lipo` next to `INDR`.
- Add `dyld_stub_i386.s` to `INSTALL_FILES`.
- Replace the `$(OBJROOT)/dyld.stub` recipe so it does **not** pass `$(RC_CFLAGS)` to the ppc-only `dyld_stub.s`. Explicit single-arch compiles:

```
$(OBJROOT)/dyld_stub.ppc.o: $(SRCROOT)/dyld_stub.s
	$(CC) -arch ppc -c -o $(OBJROOT)/dyld_stub.ppc.o $(SRCROOT)/dyld_stub.s

$(OBJROOT)/dyld_stub.i386.o: $(SRCROOT)/dyld_stub_i386.s
	$(CC) -arch i386 -c -o $(OBJROOT)/dyld_stub.i386.o $(SRCROOT)/dyld_stub_i386.s

$(OBJROOT)/dyld.stub: $(OBJROOT)/dyld_stub.ppc.o $(OBJROOT)/dyld_stub.i386.o
	$(CC) -arch ppc -dylinker -dylinker_install_name /usr/lib/dyld \
		-nostdlib -o $(OBJROOT)/dyld.stub.ppc $(OBJROOT)/dyld_stub.ppc.o
	$(CC) -arch i386 -dylinker -dylinker_install_name /usr/lib/dyld \
		-nostdlib -o $(OBJROOT)/dyld.stub.i386 $(OBJROOT)/dyld_stub.i386.o
	$(LIPO) -create -o $(OBJROOT)/dyld.stub \
		$(OBJROOT)/dyld.stub.ppc $(OBJROOT)/dyld.stub.i386
```

Keep using `$(DYLD)` in the `crt1.o` `-r` link as today.

Replace the install line that copies host `/usr/lib/dyld` with:

```
	$(MKDIR) $(DSTROOT)/usr/lib
	$(CC) -arch i386 -dylinker -dylinker_install_name /usr/lib/dyld \
		-nostdlib -o $(OBJROOT)/dyld.i386 $(OBJROOT)/dyld_stub.i386.o
	$(LIPO) -create -o $(DSTROOT)/usr/lib/dyld /usr/lib/dyld $(OBJROOT)/dyld.i386
	$(CHMOD) 555 $(DSTROOT)/usr/lib/dyld
```

Add the new `.o` / stub products to `clean`.

If `PB.project` lists `dyld_stub.s`, add `dyld_stub_i386.s` there too.

- [ ] **Step 3: Native compile check in a private directory (not `/build`)**

On the guest, from a copy of Csu or `SRCROOT` pointing at `src/Csu-1`:

```sh
cd /tmp && rm -rf csu-fat && mkdir csu-fat
# use the project sources in-place with private OBJ/SYM/DST
gnumake -C /build/src/Csu-1 OBJROOT=/tmp/csu-fat SYMROOT=/tmp/csu-fat \
    DSTROOT=/tmp/csu-fat-dst RC_CFLAGS='-arch i386 -arch ppc' \
    RC_ARCHS='i386 ppc' install
lipo -info /tmp/csu-fat/dyld.stub /tmp/csu-fat-dst/usr/lib/dyld \
    /tmp/csu-fat-dst/lib/crt1.o
```

Expected: each named file reports i386 (or i486) **and** ppc. If `indr -arch all` fails, fix that recipe before committing. Do not install into `/`. This task is not complete until that private `lipo -info` output shows both slices.

- [ ] **Step 4: Commit**

```bash
git add src/Csu-1/dyld_stub_i386.s src/Csu-1/Makefile src/Csu-1/PB.project
git commit -m "Csu: lipo i386 dyld stub with host ppc dyld"
```

## Task 7: Libsystem per-architecture harvest links

**Files:** Modify `src/Libsystem-2/Makefile`, `src/Libsystem-2/Makefile.postamble`, `vm/tests/test-build-src.ps1`.

`NEXTSTEP_PB_LDFLAGS` currently uses `System.order.$(TARGET_ARCH)` and `make_links` looks up a single `${TARGET_ARCH}` object directory. A fat `RC_ARCHS="i386 ppc"` build must iterate `$(TARGET_ARCHS)` (same as `RC_ARCHS` in `pb_makefiles-1/common.make`).

- [ ] **Step 1: Add host assertions**

In `vm/tests/test-build-src.ps1`:

```powershell
$libsystemMakeText = Get-Content -Raw (Join-Path $repoRoot 'src\Libsystem-2\Makefile')
$libsystemPostambleText = Get-Content -Raw (Join-Path $repoRoot 'src\Libsystem-2\Makefile.postamble')
Assert-NotMatch $libsystemMakeText 'System\.order\.\$\(TARGET_ARCH\)' 'Libsystem does not bind a single TARGET_ARCH order file at parse time'
Assert-Match $libsystemPostambleText 'TARGET_ARCHS' 'Libsystem harvest links iterate TARGET_ARCHS'
```

- [ ] **Step 2: Run `powershell -NoProfile -File vm\tests\test-build-src.ps1`**

Expected: FAIL on `System.order.$(TARGET_ARCH)`.

- [ ] **Step 3: Per-arch flags and links**

In `src/Libsystem-2/Makefile`, change `NEXTSTEP_PB_LDFLAGS` to drop the single `System.order.$(TARGET_ARCH)` reference:

```
NEXTSTEP_PB_LDFLAGS = -seg1addr 0x41300000 -sectorder_detail -read_only_relocs warning
```

In `Makefile.postamble`, wrap `make_links` so the existing directory-discovery `for i in $$dirs` body runs once per arch:

```
for arch in $(TARGET_ARCHS); do \
    echo ========== Creating $$obj_dir links for $$arch ==========; \
    ... use $$arch anywhere ${TARGET_ARCH} was used ... \
done
```

Set extra libtool flags to include both order files when both archs are selected:

```
DYNAMIC_SECTORDER_FLAGS = $(foreach A,$(TARGET_ARCHS),-sectorder __TEXT __text $(SRCROOT)/System.order.$(A))
```

If `DYNAMIC_SECTORDER_FLAGS` is already consumed by `set_extra_libtool_flags`, assign it in the postamble before `make_links`. Do not pass a ppc order file when linking only i386.

Keep the `after_install` `/usr/lib/lib*.dylib` aliases. Those aliases point at fat `System` once Libsystem is universal.

- [ ] **Step 4: Re-run `vm\tests\test-build-src.ps1`**

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/Libsystem-2/Makefile src/Libsystem-2/Makefile.postamble vm/tests/test-build-src.ps1
git commit -m "Libsystem: iterate TARGET_ARCHS for order files and object links"
```

## Task 8: Primary host bootstrap path and docs

**Files:** Modify `vm/build-src-lib.ps1`, `vm/tests/test-build-src.ps1`, `README.md`, `vm/README.md`, `src/rbuild-1/README.md`, `docs/build/rbuild-universal.md`.

- [ ] **Step 1: Fail the host script test for missing `bootstrap-universal`**

Change the bootstrap phase command assertion in `vm/tests/test-build-src.ps1` so the generated command must contain thin bootstrap **then** `bootstrap-universal` with the same sysroot/toolchain/state/manifest/repo. Keep the existing thin-bootstrap substring checks; add:

```powershell
Assert-Match $bootstrapCommand ([regex]::Escape('/build/tools/bin/rbuild bootstrap-universal --sysroot /build/bootstrap-root --toolchain /build/src/rbuild-1/toolchains/gcc-darwin.conf --state /build/state /build/src/BootstrapManifest /build/repo /build/repo')) 'bootstrap-universal is the primary second walk'
Assert-Equal ($bootstrapCommand.IndexOf('/build/tools/bin/rbuild bootstrap --sysroot') -lt $bootstrapCommand.IndexOf('/build/tools/bin/rbuild bootstrap-universal --sysroot')) $true 'thin bootstrap runs before bootstrap-universal'
```

Also update the `MIGARCH=ppc ... rbuild bootstrap` assertion: the thin command may be followed by `&&` and the universal command. Match a prefix, not “bootstrap is the last rbuild invocation”.

- [ ] **Step 2: Run `powershell -NoProfile -File vm\tests\test-build-src.ps1`**

Expected: FAIL (`bootstrap-universal` missing from `New-RhapBuildPhaseCommand`).

- [ ] **Step 3: Emit both commands from `-Bootstrap`**

In `vm/build-src-lib.ps1`, in the `'bootstrap'` phase string (the `return "set -e; /usr/bin/install -d …"` line), after the existing `rbuild bootstrap … BootstrapManifest $repo $repo` command, append:

```
 && CONFIG_DIR=$tools/bin DECOMMENT=$tools/bin/decomment MIGCC=$cc MIGARCH=$targetArch MIGCOM_DIR=$tools/libexec BISON=$bootstrap/usr/bin/bison BISON_SIMPLE=$bootstrap/usr/share/bison.simple $rbuild bootstrap-universal --sysroot $bootstrap --toolchain $profilePath --state $state $source/BootstrapManifest $repo $repo
```

Reuse the same quoting helpers already used for `$rbuild` / `$source`. Do not add a second `install -d`.

Update docs:

- Root `README.md` Bootstrap section: `-Bootstrap` runs thin `rbuild bootstrap` then `rbuild bootstrap-universal`. Thin-only is not enough for ordinary universal builds.
- `vm/README.md` flag table: same pair.
- `src/rbuild-1/README.md`: document `bootstrap-universal` next to `bootstrap`; say it is the primary method for a dual-arch repo; thin `bootstrap` remains for tests and the first walk.
- `docs/build/rbuild-universal.md`: add a “Repository bootstrap” section describing the three walks, per-CPU link readiness, no `golden.img` seeds, and that kernel/world are out of scope. Leave the 2026-09-12 fixture acceptance table as fixture evidence, not live-repo evidence.

- [ ] **Step 4: Re-run `vm\tests\test-build-src.ps1`**

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add vm/build-src-lib.ps1 vm/tests/test-build-src.ps1 README.md vm/README.md src/rbuild-1/README.md docs/build/rbuild-universal.md
git commit -m "rbuild: make bootstrap-universal the primary host bootstrap path"
```

## Task 9: Live guest wipe, universal repo, and proof builds

**Files:** Modify `docs/build/rbuild-universal.md` with recorded evidence only after the commands below succeed. No `/build` overwrite until this task.

Temporary disk image if another agent is booting a guest. This guest is the configured `vm/vm.conf` PPC box.

- [ ] **Step 1: Sync rbuild + manifests + Csu + Libsystem**

```powershell
powershell -NoProfile -File vm\sync-src.ps1 -Path rbuild-1
powershell -NoProfile -File vm\sync-src.ps1 -Path Csu-1
powershell -NoProfile -File vm\sync-src.ps1 -Path Libsystem-2
powershell -NoProfile -File vm\sync-src.ps1 -Path BootstrapManifest
```

`BootstrapRuntimeManifest` is a file under `src/`; if `-Path BootstrapManifest` only uploads that one file, also upload `BootstrapRuntimeManifest` the same way (`-Path BootstrapRuntimeManifest`). If `sync-src.ps1 -Path` requires a directory, upload from the repo `src/` tree using whatever path form the script already documents.

- [ ] **Step 2: Rebuild private rbuild on the guest**

```powershell
powershell -NoProfile -File vm\build-src.ps1 -Rbuild
```

Expected: guest `make test` / `make trace-test` PASS, including `bootstrap-runtime-manifest: PASS` and `bootstrap-resume: PASS`. Success line `build-src: complete (rbuild)`.

- [ ] **Step 3: Wipe live outputs and run primary bootstrap**

```powershell
powershell -NoProfile -File vm\clean-build.ps1
powershell -NoProfile -File vm\build-src.ps1 -Rbuild
powershell -NoProfile -File vm\build-src.ps1 -Bootstrap
```

Expected: thin walk completes, then `bootstrap-universal` completes, `build-src: complete (bootstrap)`, exit 0. If Csu/Libsystem/Libc fail fat, fix that project in a new task commit; do not quarantine into a thin package and call it success.

- [ ] **Step 4: Inspect the live repo**

On the guest, for every `BootstrapManifest` `all`/`headers` APK in `/build/repo`, check `.PKGINFO` `arch = universal-apple-rhapsody`. Sample `lipo -info` (or rbuild’s Mach-O reader) on:

- `/build/bootstrap-root/lib/crt1.o`
- `/build/bootstrap-root/usr/lib/dyld`
- `/build/bootstrap-root/System/Library/Frameworks/System.framework/Versions/B/System`
- one tool from a rebuilt package (for example sysroot `usr/bin/bison` or `usr/bin/cc`)

Expected: i386 (or i486) **and** ppc on each sampled Mach-O. Record the exact commands and outputs in `docs/build/rbuild-universal.md`.

- [ ] **Step 5: Ordinary universal `buildpackage` proof**

Use a small unlabeled/universal project that is **not** a kernel. A private copy of an existing headerless tool is acceptable if its `Build-Depends` are satisfied by the new repo. Run `rbuild buildpackage --dir --target all <source> <private-repo> <private-apks>` with a chroot populated from `/build/repo` (ordinary path, not bootstrap). Repeat the same command.

Expected: first run publishes `arch universal-apple-rhapsody` fat executable; second run reuses cache (`already exists` / `already have`) with no probe commands. Do not execute the produced binary.

- [ ] **Step 6: `rbuild kernel --arch i386` proof**

```sh
rbuild kernel --state /build/state --arch i386 /build/src /build/repo /tmp/rbuild-i386-kernel-proof
```

Use a dest other than `/build/built` if a ppc kernel tree must stay untouched. Expected: i386 metadata on kernel packages; objects/executables are i386 (not ppc-only). Do not boot. A dest-path safety error from rbuild must be resolved by choosing an allowed dest under the configured remote root, not by disabling checks.

- [ ] **Step 7: Commit evidence only**

Update `docs/build/rbuild-universal.md` with the live-tree commands, commit hash of the rbuild used, and pass/fail of steps 4–6. Commit:

```bash
git add docs/build/rbuild-universal.md
git commit -m "rbuild: record live universal bootstrap acceptance"
```

If step 3–6 cannot run (guest down), do not claim success. Leave the evidence section stating the blocker; do not mark Task 9 complete.

## Self-review (spec coverage)

| Spec requirement | Task |
| --- | --- |
| Wipe live `/build/repo` and `/build/bootstrap-root` | 9 |
| From-source i386, no `golden.img` | 6, 9 |
| Profile stays `target_arch=ppc` | 2, 5, 8 |
| `bootstrap` unchanged thin | 2, 5 |
| `bootstrap-universal` primary, two walks, sibling runtime manifest | 4, 5, 8 |
| Hard error if thin sysroot/`indr` missing | 5 |
| Universal operation; thin source conflicts | 1, 2 |
| Per-CPU compile; link only if crt+System have the slice | 3 |
| Runtime subsequence Csu through Libsystem | 4 |
| Csu fat stub + lipo host ppc dyld | 6 |
| Libsystem per-arch order/object dirs | 7 |
| Quarantine thin same-name APKs / stale ppc state rebuilds | existing runner + 5 resume test |
| Ordinary universal `buildpackage` + i386 kernel proof | 9 |
| Docs / `-Bootstrap` pair | 8 |
| No full world rebuild, no i386 execution claims | 9 dest + docs |

No TBD placeholders. `architecture_resolve`, `slice_link_ready`, `bootstrap-universal`, and `BootstrapRuntimeManifest` names are used consistently across tasks.
