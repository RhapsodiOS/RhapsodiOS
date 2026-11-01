# Foundation project registration audit (2026-10-04)

Compared the source lists in `src/Kits/Foundation/Makefile` and
`Makefile.preamble` with `PB.project`.

- All 77 compiled `.m` sources are distinct and occur exactly once in
  `PB.project`'s `CLASSES` list.
- All 66 headers declared by the generated `Makefile` occur exactly once in
  `PB.project`'s `H_FILES` list.
- The reconstruction modules previously absent from `PB.project` are now
  registered. `NSFault.m` already appears in the generated `Makefile`; it is
  registered in `PB.project` without a redundant preamble entry.
- The exact-profile selector audit against the Foundation i386 reference
  reports 3,253 reference selectors and 3,300 source definitions, with zero
  missing selectors, renames, or duplicates. Its 47 extra source definitions
  include APIs outside this reference profile.
- The exact-profile C-symbol audit reports seven unclaimed exports:
  `_NSRecordAllocationEvent`, `__NSParseAndAutorelease`, `__NSParseAndRelease`,
  `__NSParseAndRetain`, `__NSStandardizePath`, `__NSToDoAtLastThreadExit`, and
  `__NSWalkData`.

These were source and manifest audits only. No tests or builds were run.
