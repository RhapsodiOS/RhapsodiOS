# Foundation i386 reconstruction, stage 1

Plan: docs/superpowers/plans/2026-07-26-foundation-i386-reconstruction.md
Worktree: D:/RhapsodiOS/.claude/worktrees/foundation-recon (branch foundation-recon)
Base: c259aba3

Reference of record: C:/Users/raynorpat/Downloads/test/Foundation-i386
  size 1630488  sha256 1165B9063ADD5672514455CA2C9830625BEA2BCE5E46126FB5E8652114C909D6

## Tasks

1. Confirm the guest can compile a Foundation module   [GATE - stop if blocked]
2. Accept MH_DYLIB in the Mach-O reader
3. Read fat containers and extract a slice
4. Extract classes and ivars from __OBJC
5. Extract modules, categories and exported symbols
6. Emit per-module ABI documents with `binrecon abi`
7. Verify a build against committed ABI with `binrecon abi-check`
8. Generate a module's analysis scope
9. Report source mapping per module
10. Analyse the reference
11. Commit the ABI baseline
12. Reconstruct NSDecimal.m
13. Reconstruct NSGeometry.m
14. Reconstruct NSRange.m
15. Verify the stage and record divergences

## Pre-flight decisions

- Fat handling: materialize the i386 slice to a file (user chose). runner.py:312
  cross-checks analyzer input identity against profile.reference_identity, so a
  slice-aware reader would have broken `analyze`. No profile-v1/analysis-v1
  schema changes.
- abi-check rewritten: `--built MODULE=PATH`, real external-symbol comparison,
  tolerates objects with no __OBJC. Earlier draft copied expected symbols onto
  actual (checked nothing) and crashed on NSRange.o/NSDecimal.o.

## Minor findings (for final review triage)

(none yet)

## Progress

