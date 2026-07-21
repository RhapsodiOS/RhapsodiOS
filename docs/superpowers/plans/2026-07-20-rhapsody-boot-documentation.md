# Rhapsody Boot Documentation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish source-grounded Markdown and Mermaid documentation explaining the i386 and PPC boot paths through the start of `rc` scripts.

**Architecture:** Two independent architecture narratives are supported by a shared subsystem reference and a source map. Treat the repository as authoritative: each important claim has a source anchor and a Verified, Inferred, or Research gap label.

**Tech Stack:** Markdown, Mermaid flowcharts, PowerShell, ripgrep, Git.

---

## File structure

- Create `docs/boot-i386.md`: i386 narrative and three Mermaid diagrams.
- Create `docs/boot-ppc.md`: PPC narrative and three Mermaid diagrams.
- Create `docs/boot-common.md`: shared Mach, BSD, VM, I/O, and DriverKit reference.
- Create `docs/boot-source-map.md`: stage-to-path/symbol/evidence index.
- Create `docs/boot-documentation-checklist.md`: maintenance and validation checklist.
- Modify `README.md` only if it has a documentation-index section.

### Task 1: Create the evidence ledger

**Files:** Create `docs/boot-source-map.md`; inspect `src/kernel-7/`, `src/driverkit-3/`, and `src/drivers/`.

- [ ] Run `rg --files src/kernel-7 src/driverkit-3 src/drivers | rg '(machdep|bsd|driverkit|kernserv|i386|ppc|boot|loader|startup|init)'` to inventory candidates.
- [ ] Run `rg -n --glob '*.{c,h,s,S,m}' 'unix_startup|bsd_init|start_kernel|kernel_main|launch_init|init_exec|execve' src/kernel-7`; trace direct calls with `rg -n -C 8`.
- [ ] Write the ledger, defining **Verified**, **Inferred**, and **Research gap**. Its table columns are Stage; i386 path and symbol; PPC path and symbol; Shared path and symbol; Evidence; Notes / next trace.
- [ ] Add rows for loader handoff, architecture entry, VM, Mach, BSD, drivers, root filesystem, first user process, and `rc`.
- [ ] Validate citations: extract `src/` paths with ripgrep and fail if any does not exist. Commit only `docs/boot-source-map.md` as `docs: map Rhapsody boot source evidence`.

### Task 2: Write the i386 narrative

**Files:** Create `docs/boot-i386.md`; inspect i386 paths found in Task 1.

- [ ] Trace the i386 entry through shared Mach, VM, BSD, driver, root, first-process, and `rc` boundaries. Add all unresolved transitions to the ledger rather than guessing.
- [ ] Write sections: Scope and reading guide; Firmware and loader handoff; Architecture entry and early machine setup; Mach kernel and virtual-memory initialization; BSD initialization and root filesystem; DriverKit, drivers, and service activation; First user-space process and the `rc` boundary; Evidence and research gaps.
- [ ] End each material paragraph with a current-tree source anchor (path and symbol); label all non-verified statements.
- [ ] Add exactly three Mermaid diagrams: a left-to-right timeline ending at `rc`; a top-down i386/Mach/VM/BSD/DriverKit composition graph; and a top-down configuration/driver/root/first-process/`rc` handoff graph. Explain each edge below its diagram.
- [ ] Validate exactly three Mermaid fences, no unresolved placeholder markers, and no missing cited path. Commit `docs/boot-i386.md` as `docs: describe i386 Rhapsody boot path`.

### Task 3: Write the PPC narrative

**Files:** Create `docs/boot-ppc.md`; inspect `src/kernel-7/machdep/ppc/`, `src/drivers/ppc/`, and the ledger.

- [ ] Begin with `src/kernel-7/machdep/ppc/start.s` and `src/kernel-7/machdep/ppc/unix_startup.c`; trace direct calls into common subsystems.
- [ ] Treat Open Firmware/loader handoff as a research gap whenever the current source does not substantiate it.
- [ ] Write the same sections as the i386 narrative, explicitly marking PPC-specific divergence and common-code convergence.
- [ ] Add exactly three Mermaid diagrams: PPC timeline; PPC/common-kernel composition; driver/root/first-process/`rc` handoff. Mark unresolved transitions in prose and diagram notes.
- [ ] Validate the same rules as i386; update the ledger and commit both as `docs: describe PPC Rhapsody boot path`.

### Task 4: Write shared architecture documentation

**Files:** Create `docs/boot-common.md`; modify both architecture pages.

- [ ] Extract a concept only when the narratives cite the same common source or demonstrate verified convergence; leave architecture-specific discussion local.
- [ ] Write sections: How to use this reference; Architecture-specific code and common kernel code; Mach, VM, and BSD responsibilities; DriverKit, kernel servers, and hardware drivers; Storage, VFS, and the root filesystem; Evidence boundaries.
- [ ] Link each architecture page to the precise shared heading needed, using relative Markdown fragments that match actual headings.
- [ ] Verify all fragments resolve, all cited paths exist, and commit as `docs: explain shared Rhapsody kernel architecture`.

### Task 5: Maintain and validate the documentation set

**Files:** Create `docs/boot-documentation-checklist.md`; possibly modify `README.md`.

- [ ] Write a checklist requiring existing paths, accurate symbols and evidence labels, independently readable narratives, three diagrams per architecture page, prose/diagram agreement, and a strict `rc` stopping point.
- [ ] Inspect `README.md`; add a compact link to the narratives and source map only if it has a natural documentation section.
- [ ] Run final structural checks: five output files exist; each architecture page has three Mermaid blocks; all extracted `src/` citations exist; no placeholder terms; and `git diff --check` passes.
- [ ] Inspect the staged diff for unrelated workspace changes. Commit only the documentation files, plus `README.md` only when it was changed, as `docs: add Rhapsody boot documentation guide`.
