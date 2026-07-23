# CLAUDE.md

This file provides guidance to Claude Code and other AI agents when working with code in this repository.

## What This Is

RhapsodiOS is an open-source reimplementation of Apple's Rhapsody (which became Mac OS X Server 1.0–1.2v3), forked from Apple's Darwin 0.3 release (summer 1999). It targets **ppc** and **i386** and builds best on a case-sensitive filesystem, historically on a Rhapsody DR2 / Mac OS X Server 1.x guest.

All OS project sources live under `src/` — each is a self-contained Apple/NeXT project (kernel, libc, commands, drivers, etc.) with its own `Makefile.preamble` / `pb_makefiles` framework.

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

## 5. Committing Changes

**Keep commit messages short, human-readable, and descriptive.**

- Always keep the commit messages short, human-readable, and descriptive.
- Start the commit line with whatever subsystem you are working on, e.g. "kernel: ", "boot: ", "AppKit: ", etc.
- Describe what the changes actually do instead of listing the changed files. Keep commit messages as one to two lines.
- Do not add any metadata to commits.

## 6. Debugging

- Make sure to use temporary disk images if testing a boot to isolate testing if another agent is working a different debugging session
