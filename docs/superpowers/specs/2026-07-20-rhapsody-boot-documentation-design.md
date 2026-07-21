# Rhapsody Boot Documentation Design

## Purpose

Create a source-grounded explanation of how the repository's current Rhapsody
kernel and BSD environment boot on i386 and PowerPC. The documentation must
serve three audiences: contributors modifying the code, developers seeking an
architecture orientation, and historical or technical readers.

The scope ends when the system begins executing its `rc` scripts. The graphical
environment and later user-space startup are explicitly out of scope.

## Deliverables

Place a small cross-linked Markdown documentation set in `docs/`:

- `docs/boot-i386.md`: a linear i386 narrative from BIOS and bootloader
  handoff through architecture setup, Mach and BSD initialization, driver
  activation, first user process, and the `rc` boundary.
- `docs/boot-ppc.md`: the equivalent PowerPC narrative, beginning at Open
  Firmware and bootloader handoff and identifying platform-specific divergence.
- `docs/boot-common.md`: a concise shared reference for the Mach/BSD boundary,
  VM and I/O responsibilities, DriverKit and driver-loading concepts, and
  shared terminology. It must not duplicate the two boot narratives.
- `docs/boot-source-map.md`: a contributor index mapping each boot stage to
  repository paths, entry symbols, and its evidence status.

The i386 and PPC documents are intentionally complete, stand-alone narratives.
They will cross-link to shared material where readers need deeper context.

## Diagram Design

Each architecture narrative includes Mermaid diagrams for:

1. the high-level timeline from firmware through `rc`;
2. kernel composition, showing architecture-specific code, Mach, BSD, VM, and
   DriverKit/I/O responsibilities; and
3. driver and root-filesystem handoff, including boot configuration, probing,
   services or driver classes, storage/root mounting, and the user-space
   transition.

Diagrams will be small enough to render clearly in standard Markdown viewers.
The prose is authoritative; diagrams must be checked against it whenever either
changes.

## Evidence Policy

Every important claim identifies a repository path and, when available, the
relevant entry symbol or function. The documents mark claims as one of:

- **Verified**: directly established by current repository source.
- **Inferred**: supported by relationships in the source but not confirmed by
  a direct trace.
- **Research gap**: an unresolved, concrete question with likely files or
  symbols to inspect next.

This policy keeps the first pass useful while accurately representing an old,
possibly incomplete or non-buildable source snapshot.

## Research and Authoring Sequence

1. Inventory loader, kernel, architecture, DriverKit, and startup trees;
   record canonical entry points and build or configuration artifacts.
2. Trace the i386 route end-to-end, writing source anchors and research gaps as
   they are discovered.
3. Trace the PPC route using the same milestones and record each substantive
   divergence from i386.
4. Write the shared reference and source map from facts established in the two
   traces.
5. Add Mermaid diagrams and validate that every node and edge agrees with the
   documented trace.
6. Check source paths and symbols against the working tree and add a short
   maintenance checklist for future updates.

## Acceptance Criteria

- Both architecture pages reach `rc` execution without covering the graphical
  environment.
- Each page can be read independently and distinguishes shared from
  architecture-specific behavior.
- Every material claim has a source anchor or an explicit inference/research-gap
  label.
- Mermaid diagrams render and do not contradict the surrounding narrative.
- The source map contains paths, symbols where practical, and evidence status
  for every major stage.
- No unlabelled speculation or dangling repository reference remains.

## Out of Scope

- Implementing or modifying boot, kernel, driver, or user-space behavior.
- Reconstructing absent source solely from external historical material.
- Detailed desktop, WindowServer, or post-`rc` startup documentation.
