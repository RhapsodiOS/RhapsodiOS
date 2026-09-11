# Private Stage-Zero Decomment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and bind a private source-owned decomment tool and make kernel header export reject missing or failed fallback processing.

**Architecture:** Extend the existing PowerShell stage-zero generator phase with one direct configured-compiler build and smoke. Bind the resulting absolute path only in bootstrap, while making the kernel's historical absolute default environment-overrideable and its two export loops failure-preserving.

**Tech Stack:** PowerShell 5.1 command generation/tests, POSIX shell, GNU make syntax, C89-era source tooling.

---

### Task 1: Define the stage-zero and bootstrap contract

**Files:**
- Modify: `vm/test-build-src.ps1`

- [ ] **Step 1: Write failing command-generation tests**

Assert that preflight requires `decomment.c`; rbuild compiles `$ToolsDir/bin/decomment` with `BuildCc`, runs a fixed comment/whitespace smoke, and alternate/spaced paths remain single shell words; bootstrap sets `DECOMMENT=$ToolsDir/bin/decomment`; generated commands never select `/usr/local/bin/decomment` or a sysroot copy.

- [ ] **Step 2: Run the PowerShell suite and verify RED**

Run `powershell -NoProfile -ExecutionPolicy Bypass -File vm/test-build-src.ps1`. Expect failure because no private decomment build or binding exists.

### Task 2: Define kernel failure semantics

**Files:**
- Modify: `vm/test-build-src.ps1`

- [ ] **Step 1: Write failing source-contract tests**

Read `kernel-7/conf/Makefile.template` and assert `DECOMMENT ?= /usr/local/bin/decomment`, no ignored `@-for` export recipes, explicit fallback failure exits, and explicit subshell failure propagation in both machine-independent and machine-dependent loops.

- [ ] **Step 2: Add a real shell fallback fixture**

Execute a small extracted loop contract with fake `unifdef` and decomment programs. Verify successful fallback exports a nonempty header, while missing or exit-nonzero decomment returns nonzero and cannot be accepted.

- [ ] **Step 3: Run the PowerShell suite and verify RED**

Expect failure on the current hardcoded default and swallowed fallback status.

### Task 3: Implement the private generator and binding

**Files:**
- Modify: `vm/build-src-lib.ps1`

- [ ] **Step 1: Require the source in preflight**

Add `Commands/bootstrap_cmds/decomment.tproj/decomment.c` to the immutable source checks.

- [ ] **Step 2: Build and smoke the private product**

After creating `ToolsDir/bin`, compile with the shell-quoted configured `BuildCc`, write a fixed smoke input below the private build area, run `decomment ... r`, compare its exact output, and fail the phase on mismatch.

- [ ] **Step 3: Bind bootstrap inline**

Add shell-quoted `DECOMMENT=$ToolsDir/bin/decomment` only to the bootstrap command environment.

- [ ] **Step 4: Run the PowerShell suite and verify remaining failures are kernel-only**

### Task 4: Make kernel export failure-preserving

**Files:**
- Modify: `src/kernel-7/conf/Makefile.template`

- [ ] **Step 1: Preserve the historical default with override support**

Change `DECOMMENT = /usr/local/bin/decomment` to `DECOMMENT ?= /usr/local/bin/decomment`.

- [ ] **Step 2: Repair both export loops**

Remove make's recipe-error ignore, change fallback calls to `$(DECOMMENT) ... || exit 1`, and append `|| exit 1` to each per-directory subshell so the outer loop and make receive failure.

- [ ] **Step 3: Run the PowerShell suite and verify GREEN**

Run `powershell -NoProfile -ExecutionPolicy Bypass -File vm/test-build-src.ps1`; expect all checks to pass.

### Task 5: Verify and commit

**Files:**
- Verify all files above plus the design and plan documents.

- [ ] **Step 1: Run syntax and focused native gates**

Run PowerShell parser checks for `vm/build-src-lib.ps1` and `vm/test-build-src.ps1`, `sh -n` for relevant shell fixtures/wrappers, the focused LLVM-built rbuild toolchain unit test, and `git diff --check`.

- [ ] **Step 2: Review scope and safety**

Confirm generated commands contain no live install, copy, `/usr/local/bin/decomment` selection, sysroot fallback, or full bootstrap invocation. Confirm unrelated untracked files are untouched.

- [ ] **Step 3: Commit the focused change**

Stage only the design, plan, PowerShell generator/tests, and kernel template, then commit with a short build-subsystem message.
