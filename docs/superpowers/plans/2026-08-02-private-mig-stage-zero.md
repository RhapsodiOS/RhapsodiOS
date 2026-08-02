# Private MIG Stage-Zero Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and bind a complete private MIG toolchain before bootstrap so kernel header generation never uses the live host or incomplete sysroot MIG.

**Architecture:** Extend the existing rbuild stage-zero command with three isolated yacc/lex/C builds and install the repository wrapper privately.  The wrapper keeps historical defaults for target packaging but accepts explicit compiler and libexec overrides; bootstrap always supplies those overrides while the profile PATH selects the private wrapper.

**Tech Stack:** PowerShell 5.1 command generation, POSIX Bourne shell, C89/GCC, yacc, lex, Rhapsody MIG sources.

---

### Task 1: Specify the generated private MIG contract

**Files:**
- Modify: `vm/test-build-src.ps1`
- Test: `vm/test-build-src.ps1`

- [ ] **Step 1: Add failing command-generation assertions**

Add assertions beside the existing private config assertions that require:

```powershell
Assert-Match $rbuildCommand ([regex]::Escape('rm -rf /build/tools/mig-build')) 'MIG private build root is recreated exactly'
Assert-Match $rbuildCommand ([regex]::Escape('/usr/bin/install -d /build/tools/bin /build/tools/libexec')) 'MIG private product directories are created'
Assert-Match $rbuildCommand ([regex]::Escape('/usr/bin/install -c -m 755 /build/src/Commands/bootstrap_cmds/migcom.tproj/mig.sh /build/tools/bin/mig')) 'repository MIG wrapper is installed privately'
Assert-Match $rbuildCommand ([regex]::Escape('/build/tools/libexec/migcom')) 'classic MIG compiler is private'
Assert-Match $rbuildCommand ([regex]::Escape('/build/tools/libexec/migcom_typd')) 'typed MIG compiler is private'
Assert-Match $rbuildCommand ([regex]::Escape('/build/tools/libexec/migcom_untypd')) 'untyped MIG compiler is private'
Assert-Match $alternateRbuild ([regex]::Escape('/opt/gcc/bin/gcc-4.2 -O')) 'configured compiler builds MIG tools'
Assert-Match $bootstrapCommand ([regex]::Escape('MIGCC=/usr/bin/cc MIGCOM_DIR=/build/tools/libexec')) 'bootstrap binds private MIG compiler tools'
Assert-NotMatch $rbuildCommand '/usr/bin/mig|/usr/libexec/migcom|NEXT_ROOT|DSTROOT=/|cp .*mig' 'stage zero never uses or copies live MIG'
```

Add space-containing path assertions for `mig-build`, project include paths,
private libexec outputs, and bootstrap `MIGCOM_DIR`.

- [ ] **Step 2: Add failing preflight assertions**

Require `mig.sh`, every project's `parser.y` and `lexxer.l`, each exact C source
declared by its Makefile, and the untyped version stub to appear in the
preflight command.  Retain the existing `/usr/bin/yacc` and `/usr/bin/lex`
checks.

- [ ] **Step 3: Run the tests and observe RED**

Run:

```powershell
powershell -NoProfile -File vm\test-build-src.ps1
```

Expected: failure at the first missing private MIG build assertion.

### Task 2: Make the repository wrapper explicitly bindable

**Files:**
- Modify: `src/Commands/bootstrap_cmds/migcom.tproj/mig.sh`
- Test: `vm/test-build-src.ps1`

- [ ] **Step 1: Add wrapper source assertions before implementation**

Load `mig.sh` in `vm/test-build-src.ps1` and require these contracts:

```powershell
Assert-Match $migWrapper 'MIGCC' 'MIG wrapper supports compiler override'
Assert-Match $migWrapper 'MIGCOM_DIR' 'MIG wrapper supports private libexec override'
Assert-Match $migWrapper '-i[ `t]+\)' 'MIG wrapper forwards -i with its argument'
Assert-Match $migWrapper 'migcom_typd' 'MIG wrapper supports typed compiler selection'
```

- [ ] **Step 2: Run the wrapper tests and observe RED**

Run the PowerShell suite and confirm it fails because `MIGCOM_DIR` and `-i`
forwarding do not exist.

- [ ] **Step 3: Implement override-compatible wrapper selection**

Preserve the historical defaults, but introduce override selection equivalent
to:

```sh
C=${MIGCC-}
MIGCOM_ROOT=${MIGCOM_DIR-/usr/libexec}
migcom=$MIGCOM_ROOT/migcom
```

When `MIGCC` is nonempty, preprocess with `$C -E`; otherwise preserve the
existing architecture-specific cpp path.  Change typed/untyped selection to
`$MIGCOM_ROOT/migcom_typd` and `$MIGCOM_ROOT/migcom_untypd`.  Add:

```sh
-i ) migflags="$migflags $1 $2"; shift; shift;;
```

The wrapper must not derive private paths from `NEXT_ROOT`.

- [ ] **Step 4: Run the wrapper contract tests**

Run the PowerShell suite.  Expected: wrapper assertions pass; generated phase
assertions remain RED until Task 3.

### Task 3: Build and bind the private MIG products

**Files:**
- Modify: `vm/build-src-lib.ps1`
- Modify: `vm/test-build-src.ps1`
- Test: `vm/test-build-src.ps1`

- [ ] **Step 1: Extend preflight with exact source ownership**

Add explicit project checks driven by fixed source-name lists.  The lists are:

```text
migcom: error.c global.c handler.c header.c mig.c routine.c server.c statement.c string.c type.c user.c utils.c parser.y lexxer.l mig.sh
migcom_typd: error.c global.c header.c migcom.c routine.c server.c statement.c string.c type.c user.c utils.c parser.y lexxer.l
migcom_untypd: error.c global.c header.c mig.c routine.c server.c statement.c string.c test.c type.c user.c utils.c parser.y lexxer.l migcom_untypd_vers_stub.c
```

Use quoted `$SOURCE_ROOT` checks and fail with the project and missing source.

- [ ] **Step 2: Generate each isolated MIG build**

In the rbuild phase, recreate only `ToolsDir/mig-build`, create `bin`,
`libexec`, and three project build directories, then for each project run:

```sh
cd "$project_build"
/usr/bin/yacc -d "$project_source/parser.y"
/bin/mv y.tab.h parser.h
/usr/bin/lex "$project_source/lexxer.l"
"$BUILD_CC" -O -I"$project_source" -I"$project_build" \
  -o "$ToolsDir/libexec/$product" \
  <exact declared C source list> y.tab.c lex.yy.c
```

Include `migcom_untypd_vers_stub.c` only in the untyped compile.  Install
`mig.sh` to `ToolsDir/bin/mig` with `/usr/bin/install -c -m 755`.  Do not invoke
the aggregate ProjectBuilder makefiles, glob sources, use `/tmp`, copy a live
binary, or use a destination root.

- [ ] **Step 3: Bind bootstrap explicitly**

Keep the existing inline `CONFIG_DIR` and add:

```sh
MIGCC=<quoted configured BuildCc>
MIGCOM_DIR=<quoted ToolsDir>/libexec
```

immediately before the bootstrap rbuild executable.  Do not add the variables
to rbuild, world, or kernel-driver phase environments.

- [ ] **Step 4: Run the full local contract suite**

Run:

```powershell
powershell -NoProfile -File vm\test-build-src.ps1
```

Expected: all checks pass.

- [ ] **Step 5: Verify syntax, import, forbidden paths, and diff hygiene**

Run PowerShell parser checks for both modified `.ps1` files, dot-source
`vm/build-src-lib.ps1`, inspect generated rbuild/bootstrap commands with target
`/bin/sh -n`, and run:

```powershell
git diff --check
git diff -- src/Commands/bootstrap_cmds/migcom.tproj/mig.sh vm/build-src-lib.ps1 vm/test-build-src.ps1
```

Expected: zero parser, shell syntax, forbidden-path, or whitespace errors.
Do not run the full bootstrap.

- [ ] **Step 6: Commit the focused implementation**

```powershell
git add -- src/Commands/bootstrap_cmds/migcom.tproj/mig.sh vm/build-src-lib.ps1 vm/test-build-src.ps1
git commit -m "build: source private MIG toolchain"
```
