# BOM-Free Remote Script Transport Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Guarantee that every process-backed remote shell payload starts with script bytes rather than a UTF-8 BOM.

**Architecture:** Construct each process-owned SSH stdin writer under a narrowly scoped strict BOM-free UTF-8 `Console.InputEncoding`, restoring the host encoding immediately after writer acquisition and leaving the current string normalization and process I/O orchestration intact. Exercise the real process boundary with a hermetic byte-capture executable, including a fresh PowerShell 5.1 `-NoProfile -File` child.

**Tech Stack:** Windows PowerShell 5.1, .NET `ProcessStartInfo`, strict `UTF8Encoding`, C stdin-capture fixture compiled by the existing LLVM test dependency.

---

### Task 1: Raw-byte regression coverage

**Files:**
- Modify: `vm/test-build-src.ps1`

- [ ] **Step 1: Add the failing byte-capture tests**

Compile a small native fixture that copies stdin bytes to a file selected by an environment variable. Invoke the real `Invoke-RhapSshScript` process path for generated preflight, fresh, and rbuild phase bodies in both streaming and buffered modes; invoke `Invoke-RhapSshCapture` for the profile-read body. Assert each file begins with ASCII `set` where applicable, never begins `EF BB BF`, and equals strict BOM-free UTF-8 for the normalized source string. Add a child script that dot-sources `rhap-remote.ps1`, calls the real helper, and is launched using `powershell -NoProfile -File`. Add a malformed-surrogate case and assert that it throws.

- [ ] **Step 2: Run the focused suite and verify RED**

Run: `powershell -NoProfile -File vm\test-build-src.ps1`

Expected: FAIL because captured process stdin begins `EF BB BF` (and the malformed surrogate is not rejected by a strict encoder).

### Task 2: Strict BOM-free process stdin

**Files:**
- Modify: `vm/rhap-remote.ps1`

- [ ] **Step 1: Add the minimal shared encoding helper**

Create a private helper returning `New-Object System.Text.UTF8Encoding($false, $true)`. Because Windows PowerShell 5.1 has no `ProcessStartInfo.StandardInputEncoding`, start the process and acquire its stdin writer while `Console.InputEncoding` is narrowly scoped to that encoding, then restore the previous encoding immediately. Validate the normalized payload with the strict encoder before process start. Do not change invoker payload strings or the streaming task loop.

- [ ] **Step 2: Run the focused suite and verify GREEN**

Run: `powershell -NoProfile -File vm\test-build-src.ps1`

Expected: PASS with zero failed checks.

- [ ] **Step 3: Review the transport diff**

Run: `git diff --check` and `git diff -- vm/rhap-remote.ps1 vm/test-build-src.ps1 docs/superpowers/specs/2026-08-02-bom-free-remote-script-transport-design.md docs/superpowers/plans/2026-08-02-bom-free-remote-script-transport.md`

Expected: no whitespace errors; only the approved transport, tests, design, and plan are changed.

- [ ] **Step 4: Run the full local gate**

Run: `powershell -NoProfile -File vm\test-build-src.ps1`

Expected: PASS with all checks and no warnings or errors.

- [ ] **Step 5: Commit the focused change**

Run: `git add docs/superpowers/specs/2026-08-02-bom-free-remote-script-transport-design.md docs/superpowers/plans/2026-08-02-bom-free-remote-script-transport.md vm/rhap-remote.ps1 vm/test-build-src.ps1; git commit -m "build: send remote scripts without bom"`

Expected: one focused commit; no unrelated files staged.
