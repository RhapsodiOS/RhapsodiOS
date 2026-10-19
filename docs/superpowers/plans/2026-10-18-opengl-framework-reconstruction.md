# OpenGL Framework Reconstruction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reconstruct the supplied OpenGL implementation as a PPC/i386 RhapsodiOS framework with native Objective-C views, validate its software renderer, and then recommend a hardware-acceleration path.

**Architecture:** Recover the supplied GL/GLU, AGL context API, GLI engine, and GLD renderer contracts from PowerPC PEF evidence. NSOpenGL wraps Apple's recovered handles; private platform adaptations present through Interceptor without introducing another context ABI or an AppKit-to-OpenGL link. Hardware investigation starts after software acceptance.

**Tech Stack:** C89, historical Objective-C and manual memory management, Foundation threads/locks, AppKit, Interceptor, DriverKit-facing presentation, Project Builder/pb_makefiles, Python host evidence checks, IDA, isolated PPC/i386 guests.

**Spec:** [Approved three-phase design](../specs/2026-10-18-opengl-framework-reconstruction-design.md).

## Global Constraints

- Target 32-bit PowerPC and i386, the historical Objective-C runtime, manual memory management, and the repository's Project Builder/pb_makefiles build conventions.
- Create the project under `src/Kits/OpenGL`.
- Produce `/System/Library/Frameworks/OpenGL.framework/Versions/A/OpenGL` and the usual framework links.
- AppKit must not link back to OpenGL.
- Place the new Objective-C classes in OpenGL.framework and expose them through `<OpenGL/NSOpenGL.h>` and `<OpenGL/NSOpenGLView.h>`.
- Preserve the portable AGL pixel-format/context/offscreen interface and measured GLI/GLD contracts; a complete QuickDraw compatibility runtime and complete later-macOS CGL API are outside phases 1 and 2.
- Preserve measured Apple names, signatures, constants, errors, handle semantics, shared layouts, and dispatch slots. Record necessary native ABI adaptations; do not promise unchanged PEF binary loading.
- Put native thread/ownership state in private side tables or Objective-C objects, not additional fields in Apple ABI structures.
- Unknown routines and no-op stubs are incomplete.
- Phase 1 includes the software renderer implementation needed by phase 2.
- Phase 2 provides rendering acceptance; a phase 1 build does not establish that rendering is correct.
- Phase 3 selects an approach; hardware-driver implementation requires its own design and plan after that investigation.
- Use the exact archive and six component hashes in the spec; preserve their mixed versions. Keep binaries, resource forks, databases, and raw analysis outside Git.
- Follow AGENTS.md snapshot, guest ownership, unique-port, SSH-readiness, and shutdown rules. Never modify the shared VM base or another session's guest/configuration.
- Stage only task-owned files; use short subsystem-prefixed commits without metadata. Preserve unrelated working-tree changes.

## Review Focus

- A rendering thread exits while its context is current: release ownership and permit later transfer without stale dispatch (Task 5).
- A resize allocation fails: preserve the last valid buffers, shared textures, and context state (Tasks 4 and 9).
- A clipped, flipped child view has padded rows: present only visible pixels with correct orientation and intact row guards (Tasks 8 and 13).
- Window Server disappears during presentation: release locks, invalidate mappings, and reject further writes through stale addresses (Tasks 8 and 13).
- dyld resolves an installed framework instead of the build under test: fail the identity check before reporting any result (Tasks 2, 11, and 13).

## Execution conventions and evidence boundary

Read the spec and applicable AGENTS.md files first. At execution time use the
worktree skill to reuse or create an isolated `codex/opengl-framework` checkout.
Do not create a second checkout merely to write this plan. Recheck the branch and
working tree because other work may have advanced since planning.

Commands below run from the checkout root unless labeled guest. New files and
test targets below are deliverables, not claims that those commands work today.
Use the existing `.venv-binrecon/Scripts/python.exe` on the host where available;
set `PYTHONPATH=tools/binrecon` for existing binrecon tests. Native tests run in the
compatible target environment, not Windows Python or a modern host Objective-C
runtime. A missing target/tool is a recorded blocker, never a passing test.

The current IDA adapter calls `read_macho` before exporting analysis. Do not feed
PEF inputs to that pipeline as if they were Mach-O. Use the working IDA PEF loader
and a project-local evidence export; reuse existing Mach-O tooling for rebuilt
artifacts. Introduce a general PEF parser only if a measured requirement cannot
be satisfied by IDA and a narrowly scoped loader-table check.

The binaries have not yet yielded every private prototype or routine boundary.
Task 1 therefore produces the exact recovered ABI and per-routine worklist. Before
implementing each reconstruction batch in Tasks 3, 4, or 6, append its exact
symbols, signatures, source ownership, inputs, and expected observations to
`reconstruction/batches.md`. Review this against the evidence before coding.
This is an evidence dependency, not permission to guess signatures or invent a
replacement renderer ABI. A group with unresolved signatures remains incomplete;
independent, understood groups can proceed. Do not report the worklist itself as
implementation or ask for repeated scope approval for routine evidence updates.

## Files and responsibilities

Paths in this table are relative to `src/Kits/OpenGL/` unless stated otherwise.
The source grouping is proposed organization, not recovered original filenames.

| Files | Responsibility |
| --- | --- |
| `Makefile`, `Makefile.preamble`, `Makefile.postamble`, `PB.project`, `Resources/Info-nextstep.plist` | Framework build, headers, dependencies, version-A installation |
| `gl.h`, `glu.h`, `glext.h`, `agl.h`, `OpenGL.h` | Measured GL/GLU/extension and portable AGL public declarations |
| `NSOpenGL.h`, `NSOpenGLView.h` | Native Objective-C source API |
| `Private/GLI.h`, `Private/GLD.h`, `Private/GLState.h` | Recovered engine/renderer ABI and internal state; no new context API |
| `Platform/GLMemory.c`, `Platform/GLThread.m`, `Platform/GLBuffers.c`, `Library/AGLContext.c` | Private native allocation/thread/drawable adaptations and Apple context entry points |
| `Library/GLDispatch.c`, `Library/GLState.c`, `Library/GLObjects.c`, `Library/GLLists.c` | GL exports, state/errors, shareable objects, display lists |
| `Engine/GLTransform.c`, `Engine/GLClip.c`, `Engine/GLLight.c`, `Engine/GLEvaluate.c` | Recovered transformation, clipping, lighting, evaluation pipeline |
| `Renderer/GLPrimitive.c`, `Renderer/GLFragment.c`, `Renderer/GLTexture.c`, `Renderer/GLPixel.c` | Software primitives, depth/stencil/blend, sampling, pixel operations |
| `Utility/GLUProject.c`, `Utility/GLUMipmap.c`, `Utility/GLUQuadric.c`, `Utility/GLUTess.c`, `Utility/GLUNurbs.c` | GLU families present in the reference |
| `NSOpenGLPixelFormat.m`, `NSOpenGLContext.m`, `NSOpenGLView.m` | Public Objective-C adapters |
| `Private/NSOpenGLDrawable.h`, `NSOpenGLDrawable.m` | Interceptor attachment, clipping, conversion, presentation |
| `reconstruction/reference.json`, `abi.json`, `abi.md`, `native-api.md`, `ledger.json`, `batches.md`, `build-environment.md`, `validation.md` | Reviewed identities, machine-checkable Apple ABI, native deviations, source mapping, build and acceptance evidence |
| `reconstruction/export_ida.py`, `check_evidence.py`, `tests/test_evidence.py` | PEF-aware evidence export/checking, with no bundled proprietary bytes |
| `tests/Makefile`, `test_support.h`, `test_support.m`, named tests below | Native behavioral and rendering tests |
| `examples/OpenGLDemo.m`, `examples/Makefile` | Two-window demonstration without nib dependencies |
| `vm/build-opengl.sh`, `vm/test-opengl.sh` (repository root) | Explicit staged dependency/build and test entry points |

Modify existing AppKit methods only in their owning files and only when Task 7
demonstrates a missing prerequisite. If the recovered call graph requires extra
source units, record their exact paths in `batches.md` before adding them; split
along recovered responsibilities rather than growing a single renderer file.

## Apple ABI and native adaptation boundaries

Use Apple's existing entry-point families as the interfaces, not a renamed
replacement API. The following names are confirmed exports in the supplied files;
Task 1 must recover and freeze their exact types, argument order, return/error
conventions, ownership, and layouts before declaring or implementing them.
Decompiler-generated prototypes alone are insufficient.

| Boundary | Confirmed entry points to recover and use |
| --- | --- |
| Public AGL pixel formats | `aglChoosePixelFormat`, `aglDescribePixelFormat`, `aglNextPixelFormat`, `aglDestroyPixelFormat` |
| Public AGL contexts | `aglCreateContext`, `aglDestroyContext`, `aglSetCurrentContext`, `aglGetCurrentContext`, `aglCopyContext` |
| Public AGL drawable/state | `aglSetOffScreen`, `aglUpdateContext`, `aglSwapBuffers`, `aglGetInteger`, `aglSetInteger`, `aglGetError`, `aglErrorString` |
| GLI engine | `gliChoosePixelFormat`, `gliDestroyPixelFormat`, `gliCreateContext`, `gliDestroyContext`, `gliAttachDrawable`, `gliSwapBuffers`, `gliGetFunctionDispatch`, `gliGetExtensionDispatch`, `gliGetSystemDispatch` |
| GLD renderer | `gldChoosePixelFormat`, `gldCreateContext`, `gldDestroyContext`, `gldAttachDrawable`, `gldGetRenderDispatch`, `gldGetSystemDispatch`, texture and vertex-buffer operations |

This table is the initial dependency map, not the complete export inventory. Match
all in-scope entries identified in Task 1, including query and error functions.
Do not flatten GLI/GLD into one table, reorder slots, replace callback prototypes,
or treat the AGL, GLI, and GLD context handles as interchangeable without evidence.
Record their actual call relationships and handle conversions.

`agl.h` exposes the measured AGL opaque types, including AGLContext and
AGLPixelFormat, and supported public entry points. Preserve Apple's create/destroy
and error-return conventions rather than adding public retain/release calls or
a native status enum. Keep native lifetime/thread bookkeeping separate; test
destruction through AGL as well as through an Objective-C owner so one cannot
leave the other's context binding stale.

NSOpenGL uses AGL lifecycle/pixel-format/current-context operations where they
apply, with private native drawable association implemented behind those operations
using the measured engine contracts. An NSView is never cast to AGLDrawable or a
QuickDraw port. Classic-only AGL functions requiring missing QuickDraw services
must be explicitly listed as unavailable or return a reference-supported failure;
never publish success stubs or guess a new error code. Do not expose a CGL name
with an AGL signature; later CGL compatibility would need separate evidence.

Task 1's `abi.json` records symbol spelling, calling convention, type widths and
signedness, parameter/return types, enum values, shared structure size/alignment/
offsets, and dispatch slots, each linked to a header or binary observation. Record
PPC reference, PPC Mach-O, and i386 target expectations separately. PEF transition
vectors, TOC handling, and symbol decoration need loader/calling-convention analysis;
a Mach-O port is not automatically binary-compatible with the original PEF modules.
Keep a deviation table with reasons and affected callers, rather than claiming
unmeasured ABI parity.

Match NSOpenGL attribute values and type widths to an identified Apple header or
other authoritative Apple evidence; the classic bundle does not itself establish
NSOpenGL's later Cocoa declarations. Translate NSOpenGL attributes to AGL values
explicitly when needed. The initial native feature set remains window/offscreen,
single/double buffering, color/alpha/depth/stencil sizes, and rejection of required
acceleration without an accelerated backend. Recover AGL defaults, list grammar,
virtual-screen reporting, errors, and unsupported combinations instead of imposing
project-chosen numeric tokens or a guessed universal pixel format.

Zero-size/detached native views remain nonpresentable. Native resize allocation
failure preserves old buffers. Presentation conversion stays private and observes
recovered pixel formats, row stride, channel order, and buffer-selection semantics;
it does not require a new exported RGBA-copy routine or replace the renderer's
internal format. GL errors and AGL errors retain their separate recovered semantics.

```objc
/* NSOpenGLPixelFormat */
- (id)initWithAttributes:(const NSOpenGLPixelFormatAttribute *)attributes;
- (void)getValues:(int *)values forAttribute:(NSOpenGLPixelFormatAttribute)attribute
    forVirtualScreen:(int)screen;
- (int)numberOfVirtualScreens;
/* NSOpenGLContext */
- (id)initWithFormat:(NSOpenGLPixelFormat *)format
    shareContext:(NSOpenGLContext *)share;
+ (NSOpenGLContext *)currentContext;
+ (void)clearCurrentContext;
- (void)makeCurrentContext;
- (void)setView:(NSView *)view;
- (NSView *)view;
- (void)clearDrawable;
- (void)update;
- (void)flushBuffer;
/* NSOpenGLView : NSView */
- (id)initWithFrame:(NSRect)frame pixelFormat:(NSOpenGLPixelFormat *)format;
- (NSOpenGLPixelFormat *)pixelFormat;
- (NSOpenGLContext *)openGLContext;
- (void)setOpenGLContext:(NSOpenGLContext *)context;
- (void)clearGLContext;
- (void)prepareOpenGL;
- (void)reshape;
- (void)drawRect:(NSRect)rect;
```

Invalid format/share initialization returns nil. Native wrapper misuse may raise
`NSInvalidArgumentException`; concurrent native ownership may raise
`NSInternalInconsistencyException` without changing either binding. These are
documented NSOpenGL adaptation behaviors, not replacements for AGL's C return/error
contracts. Any propagated presentation exception is raised after releasing locks.
Flush of a zero-size/detached native view is a no-op; loss of a previously valid
mapping is an error. Preserve C GL/AGL error state independently.

Use NSThread's thread dictionary and `NSThreadWillExitNotification`, which are
implemented in this tree. Private side bookkeeping protects current-context
lifetime and guards cross-thread ownership; it must not change the shared Apple
context layouts. Do not overwrite `cthread_data`, which Foundation already uses.
AGL and NSOpenGL current-context queries must resolve the same binding. Keep wrapper
ownership separate from borrowed AGL handles; raw AGL destruction must invalidate
native associations according to the measured destroy contract. A C-created context
may acquire a nonowning wrapper for currentContext; never create a second GL state.
Break bindings on clear/exit, and synchronize initialization for C-first as well as
Objective-C-first clients. Record native thread-local behavior as a deviation if
the reference uses a different current-context model.

## Test and build commands

Task 2 creates a test makefile whose targets compile and execute their named test,
return nonzero on failure, and emit `PASS <target>` only after all assertions pass.
`FRAMEWORK_ROOT` selects the absolute `OpenGL.framework` directory; dependency
roots and loaded Mach-O image paths are checked before execution. Separate processes
are required when swapping Foundation/AppKit/Interceptor implementations.

Guest commands, with `OPENGL_CPU` set to `ppc` or `i386` by the caller:

```sh
export OPENGL_SOURCE=/build/source
export OPENGL_OUTPUT=/build/opengl-validation
sh "$OPENGL_SOURCE/vm/build-opengl.sh" "$OPENGL_CPU" "$OPENGL_SOURCE" "$OPENGL_OUTPUT"
gnumake -C "$OPENGL_SOURCE/src/Kits/OpenGL/tests" memory RC_ARCHS="$OPENGL_CPU" \
  FRAMEWORK_ROOT="$OPENGL_OUTPUT/$OPENGL_CPU/sym/OpenGL.framework"
```

Replace `memory` with the target named by each task. `build-opengl.sh` accepts
exactly `CPU SOURCE OUTPUT`, validates CPU, creates per-CPU obj/sym/dst roots,
uses staged headers/libraries, and calls pb_makefiles with explicit `RC_ARCHS`,
`OBJROOT`, `SYMROOT`, `DSTROOT`. It never installs to the live system root.
Record the actual compiler, SDK, dependency hashes, and full commands in
`build-environment.md`. Do not use global `vm.conf` to redirect another session;
pass a private endpoint through the existing remote helper functions.

## Phase 1 — framework and native views

### Task 1: Recover reference ABI and an auditable reconstruction worklist

**Files:** Create the reconstruction evidence documents, `abi.json`, and three evidence
scripts/tests in the file map. Consume existing IDA APIs and Mach-O export tooling.
**Interfaces:** `check_evidence.py reference.json ledger.json` exits 0 for consistent
identity/accounting, 1 for missing/inconsistent evidence. `--complete` additionally
rejects unresolved owned routines. Ledger rows contain component/hash, address,
aliases, source path, prototype evidence, dependency edges, disposition, and tests.

- [ ] Write `test_changed_reference_rejected`, `test_alias_not_double_counted`, and `test_unresolved_blocks_completion` with synthetic JSON assertions: wrong hash fails; two labels at the same proven entry count once; unresolved owned entry fails `--complete`.
- [ ] Run `python -m pytest src/Kits/OpenGL/reconstruction/tests/test_evidence.py -q`; expect missing-checker failures before implementation.
- [ ] Implement the checker and IDA export; hash original data/resource forks, inventory all six components, and cross-check PEF exports/imports against loader metadata. Inventory code regions without symbols as well as named entries. Keep ATI evidence reference-only.
- [ ] Recover the five-component software call graph, GL/GLU/AGL types, GLI/GLD prototypes and dispatch slots, shared layouts, memory ownership, actual formats/defaults, sharing rules, current-context/destruction rules, flush behavior, and extension list in `abi.md` and `abi.json`. Check caller argument setup and result use against each prototype. Identify an Apple NSOpenGL header separately and record its version/provenance before declaring wrapper constants. Create one evidence batch per independently testable family; give every owned routine an explicit disposition.
- [ ] Rerun tests and checker; expect evidence consistency PASS, while `--complete` correctly fails until reconstruction finishes. Commit `OpenGL: record reference contracts and reconstruction worklist`.

### Task 2: Establish native build and selected-framework test loading

**Files:** Create framework build/resource files, test Makefile/support files,
`tests/abi.m`, `tests/agl_client.c`, `tests/test_framework_identity.py`, and `vm/build-opengl.sh`.
**Interfaces:** Test support provides `int GLTestCheck(int,const char *)`,
`int GLTestFinish(const char *)`, and `int GLTestVerifyImages(void)`; use historical
dyld image enumeration to validate the selected image and dependency paths.

- [ ] Add `test_wrong_framework_root_fails` and `test_missing_cpu_slice_fails`; assertion: exit is nonzero before rendering. Add header-width/signedness/constant/layout checks against the independently recovered `abi.json`, plus link checks for Apple exports and version-A install name. Compile an AGL C client in a separate translation unit; do not derive expected ABI values from the headers being tested.
- [ ] Run the tests against absent and deliberately mismatched temporary fixtures; expect rejection, not silent system fallback.
- [ ] Model framework makefiles on Interceptor, but link OpenGL to Interceptor/AppKit/Foundation. Create the staged build runner and image identity checks. Empty build products are diagnostic only and cannot satisfy Task 11.
- [ ] Compile header probes for both CPUs and verify the installation tree under the external DSTROOT; run `abi` once implementation supplies the exports. Establish baseline availability of staged dependency slices; record blockers explicitly.
- [ ] Commit `OpenGL: add native framework build and test loading`.

### Task 3: Reconstruct memory services and GL object ownership

**Files:** Create `Platform/GLMemory.c`, `Library/GLObjects.c`, corresponding
state declarations, and `tests/memory.c`, `tests/sharing.c`.
**Interfaces:** Consume Task 1's exact allocation/object and create/destroy
contracts. Keep any native extra lifetime bookkeeping private; add no exported
retain/release API or shared-structure fields. Use a test-only allocation-failure seam.

- [ ] Add `allocation_failure_preserves_owner` and `share_group_survives_creator`: fail each allocation site in a creation sequence, assert no leaked ownership; destroy a creating context while another owner still resolves its texture/list namespace.
- [ ] Run targets `memory` and `sharing`; expect missing implementation or failed ownership assertions.
- [ ] Recover allocation/alignment rules, object names, reference counts, deletion, and share-group lifetime in separate evidence batches. Adapt Mac allocation services to native allocation without copying fixed PowerPC pointer arithmetic.
- [ ] Rerun `memory` and `sharing` on each target; verify malformed sizes/overflow rejection, repeated create/free, and failure cleanup with live-allocation counts returning to baseline.
- [ ] Commit each independently tested batch, using messages such as `OpenGL: reconstruct shared object lifetime`.

### Task 4: Recover pixel formats, contexts, and drawable buffers

**Files:** Create `Library/AGLContext.c`, `Platform/GLBuffers.c`, `agl.h`,
`Private/GLI.h`, `Private/GLD.h`, recovered state declarations,
`tests/pixel_format.c`, and `tests/buffers.c`.
**Interfaces:** Implement the measured AGL format/context/offscreen functions and
their actual GLI/GLD calls from Task 1. Keep resize/presentation bookkeeping private.

- [ ] Test `unknown_attribute_rejected`, `accelerated_format_rejected`, `incompatible_share_rejected`, `failed_resize_preserves_pixels`, and `offscreen_row_bounds_checked` through real AGL entry points. Assert the reference-recorded NULL/boolean return and exact AGL error for each failed creation/query; query output/error consumption follows reference behavior. Assert native failed resize preserves old dimensions/content/objects and guarded offscreen rows remain intact. Freeze concrete assertions from Task 1 before implementation; do not substitute new status values.
- [ ] Run `pixel-format` and `buffers`; expect contract failures before implementation.
- [ ] Reconstruct format enumeration, context setup/destruction, default state, front/back/depth/stencil allocation, and render/flush dispatch. Add offscreen buffers through the same context path used by views; do not make a separate test renderer.
- [ ] Run tests for zero/negative/extreme dimensions, explicit stride, mismatched share formats, single/double buffering, and allocator failure at each step. Verify exact byte order with RGBA bytes `0x12,0x34,0x56,0x78` on both CPUs.
- [ ] Commit `OpenGL: reconstruct software contexts and drawables`.

### Task 5: Enforce current-context thread ownership

**Files:** Create `Platform/GLThread.m`, `tests/current_context.m`.
**Interfaces:** Implement `aglSetCurrentContext`/`aglGetCurrentContext` with their
measured signatures and error conventions. Private bookkeeping coordinates native
thread ownership, wrapper lifetime, raw AGL destruction, and clear/exit cleanup.

- [ ] Add `two_threads_cannot_own_one_context`, `failed_switch_preserves_old_context`, and `thread_exit_releases_owner`. Use condition locks/barriers, not sleeps; assert the failed AGL return and evidence-supported error mapping, correct prior binding, and success after owner exit. If the reference has no concurrency failure, document the native adaptation and its existing-error mapping before coding, without adding an error constant.
- [ ] Run `current-context`; expect ownership failures before implementation.
- [ ] Implement thread-dictionary bindings, guarded acquisition/release, and exit cleanup through existing Foundation interfaces. Keep ABI objects unchanged. Use the same current state for C GL/AGL and Objective-C currentContext, including a client that calls AGL before any NSOpenGL class is initialized.
- [ ] Test release reentrancy: clear a binding holding the last wrapper/context references and assert teardown completes without reacquiring an already-held ownership lock. Remove ownership under the lock, then perform destruction/releases after unlocking.
- [ ] Rerun with two independent contexts, repeated clear, nested autorelease pools, Objective-C owner release while current, raw `aglDestroyContext` for wrapped/current contexts, and thread exit without explicit clear. Apply measured AGL destroy semantics and invalidate associations without a double free. Record native thread-local deviations; confirm no Foundation thread-data overwrite.
- [ ] Commit `OpenGL: isolate current contexts by thread`.

### Task 6: Reconstruct GL dispatch, engine, software rasterizer, and GLU

**Files:** Create the Library/Engine/Renderer/Utility units in the file map,
public GL headers, and `tests/{dispatch,state,transform,primitive,fragment,texture,pixel,lists,glu}.c`.
**Interfaces:** Every public and private signature comes from Task 1's frozen
batch entry; GL dispatch obtains the same Apple context state used by Task 5.
Preserve distinct GLI/GLD table layouts and GL/AGL error state; invent no private
Apple prototype or substitute dispatch ABI.

Execute the following rows as separate reviewed, committed reconstruction batches,
splitting any row further by its measured call graph. A batch lists every symbol
it implements and has its own failing test, minimal implementation, and rerun.

| Order / target | Owned behavior | Required assertions |
| --- | --- | --- |
| `dispatch` | GL entry-point forwarding and dispatch tables | Every measured slot maps to its intended routine; A/B context switches select A/B state; no-context behavior matches the documented native adaptation |
| `state` | State defaults, setters/getters, errors, attribute stacks | Invalid enum does not mutate state; error retrieval/reset matches reference; push/change/pop restores exact recorded values |
| `transform` | Matrices, clipping, lighting, evaluators | Identity preserves a fixed vertex; known translate/scale produces expected coordinates; outside-plane vertices reject; light/evaluator fixtures match recovered equations |
| `primitive` | Points, lines, triangles, polygon assembly, viewport | Zero-area input writes no unrelated pixels; a nonedge interior pixel has expected coverage; scissor excludes an outside sentinel |
| `fragment` | Depth, stencil, blend, alpha, masks, accumulation if present | Near sample wins under LESS; stencil mismatch suppresses color; disabled color channels retain their prior bytes |
| `texture` | Texture storage/sampling, mipmaps, supported multitexture | A 2x2 nearest-sampled texture returns the selected texel; shared updates are visible; deletion obeys reference lifetime |
| `pixel` | Clear, draw/copy/read pixels, packing/unpacking | Odd-width padded rows preserve guards; readback channel order is correct; pack/unpack state changes do not leak between contexts |
| `lists` | Display-list compilation/replay and reference-owned object commands | Compile-only does not draw; replay does; deleting one shared context preserves remaining lists; recorded arguments retain required values |
| `glu` | Projection, mipmaps, quadrics, tessellation, NURBS families present in inventory | Identity project/unproject round trip; mip dimensions; primitive/callback order fixtures and invalid input behavior from reference |

- [ ] For each row, record exact numeric fixtures and reference addresses in its batch, write the named assertions using the real engine or the smallest recovered pure routine, and run its target to observe a meaningful failure.
- [ ] Implement only that batch, preserving error behavior, endian handling, and ownership. Recover tables/constants from evidence, not visually approximate output. Correct decompiler mistakes by checking disassembly and callers.
- [ ] Rerun the row's target and affected predecessor tests; commit the working batch with an `OpenGL:` message describing its behavior.
- [ ] Audit the complete five-component function inventory for features not named in this table, including feedback/selection and private helpers. Add exact source/tests/batches for every in-scope omission before claiming Task 6 complete; do not silently narrow the supplied implementation to a triangle demo.
- [ ] Run all nine targets and the ledger checker. Unknown or stubbed owned functions remain failures. Capability/version strings must describe implemented and tested functions; archive component version is not the GL API version.

### Task 7: Recover the AppKit prerequisites exercised by native views

**Files:** Modify only demonstrated owners among `src/Kits/AppKit/NSView.m`,
`NSWindow.m`, and `NSApplication.m`; create `src/Kits/OpenGL/tests/view_prerequisites.m`
and `reconstruction/appkit-prerequisites.md`.
**Interfaces:** Consume existing declarations for setFrame/setFrameSize,
convertRect:toView:/fromView:, visibleRect, hierarchy attach/remove, contentView,
display invalidation/focus, and window lifecycle. Preserve historical AppKit ABI.

- [ ] Audit all build units/categories and record which required selectors actually lack bodies. Add tests for nested frame conversion, flipped-child clipping, window propagation on reparent, resize notifications, and ordinary drawRect delivery; assert the same behavior with a non-GL NSView.
- [ ] Run `view-prerequisites` against the explicitly selected rebuilt AppKit; record missing selectors/behavior before editing. Compare with the available historical AppKit reference in a separate process.
- [ ] Recover only the missing required routines from AppKit evidence. Keep geometry, hierarchy, and display delivery as separate fix/test/commit batches; do not add GL-specific shortcuts to NSView.
- [ ] Rerun `view-prerequisites` and affected existing AppKit checks. If missing dependencies expand into general AppKit reconstruction, document the blocker and retain a separate original-AppKit integration lane; do not claim rebuilt integration passed.
- [ ] Commit each prerequisite with an `AppKit:` description and record its reference evidence.

### Task 8: Present through Interceptor without stale mappings

**Files:** Create `Private/NSOpenGLDrawable.h`, `NSOpenGLDrawable.m`,
`tests/presentation.m`; modify Interceptor private declarations only if an existing
implemented selector must be declared for this adapter.
**Interfaces:** Private drawable methods: `-initWithView:(NSView *)view`,
`-(BOOL)updateForContext:(AGLContext)context`,
`-(BOOL)presentContext:(AGLContext)context`, and `-(void)detach`.
Consume NSDirectBitmap's lock/update/flush APIs and the recovered software buffer
and GLI/GLD drawable contracts. These private Objective-C helpers are not exported
Apple functions. They must not reinterpret NSView as a QuickDraw AGLDrawable.

- [ ] Write `clipped_flipped_padded_present` with a bitmap test double and guards; assert only the intersection changes and the visible rows are oriented correctly. Add `server_loss_releases_lock` and `move_reacquires_bitmap_pointer` with addresses changed between locks.
- [ ] Run `presentation`; expect missing-adapter failures, then retain these tests for mapping/lock regressions.
- [ ] Implement frame conversion, effective visible clipping, buffered bitmap presentation, and format conversion. Inspect the private view-clip selectors and retain/delegate behavior before using them. Use existing Interceptor copy operations only with their documented padding semantics; RGBA-to-display conversion must be explicit where layouts differ.
- [ ] Rerun tests for full occlusion, partial exposure, zero size, detach, map failure, and exceptions during copy. Check latest-presented content survives exposure and no retained delegate cycle or framebuffer pointer survives detach/unlock. Do not hold the framebuffer lock while rendering.
- [ ] Commit `OpenGL: present native drawables through Interceptor`.

### Task 9: Implement native pixel-format and context objects

**Files:** Create `NSOpenGL.h`, `NSOpenGLPixelFormat.m`, `NSOpenGLContext.m`,
`tests/native_context.m`; update build class/header lists.
**Interfaces:** Implement the public selectors above using Apple NSOpenGL constants
frozen in Task 1 and explicit AGL translation where needed. Wrap AGLPixelFormat and
AGLContext from Tasks 4/5; context view associations from Task 8 are nonowning.

- [ ] Add tests asserting nil for impossible initialization, the evidence-derived software virtual-screen count, rejection of an index outside that count, setView:nil clears attachment, currentContext matches C AGL dispatch, and incompatible concurrent acquisition preserves prior state. Pin the count/query behavior from Task 1 rather than assuming one virtual screen.

  Include the no-context baseline before creating a test wrapper:
  ```objc
  [NSOpenGLContext clearCurrentContext];
  assert([NSOpenGLContext currentContext] == nil);
  assert(aglGetCurrentContext() == NULL);
  ```
- [ ] Run `native-context`; expect missing classes/selectors or failed contracts.
- [ ] Implement thin wrappers around Apple handles and lifecycle operations, private view update/presentation, and share-context initialization. Ensure autorelease activity cannot destroy the currently bound wrapper. Existing share objects survive drawable changes. C and Objective-C clients must share one GL state, not synchronized copies.
- [ ] Rerun with allocation failure during resize, context replacement, detach/rebind, view destruction, and thread exit. Count live wrappers/bindings/drawables returning to baseline. Verify all failure paths release locks before raising.
- [ ] Commit `OpenGL: add native pixel format and context objects`.

### Task 10: Implement NSOpenGLView and the native demo

**Files:** Create `NSOpenGLView.h`, `NSOpenGLView.m`, `tests/native_view.m`,
`examples/OpenGLDemo.m`, `examples/Makefile`; update build lists.
**Interfaces:** Implement the public view selectors above. A retained format/context
pair backs each view; clearing releases it after detach. initWithFrame: uses the
default format. Creation failure returns nil. The demo creates windows in code.

- [ ] Add an instrumented subclass asserting prepare count 1 for each installed context, reshape after dimension changes, current context during drawing, and previous thread context restored after drawing. Assert normal mouse/event delivery and teardown without a retain cycle.
- [ ] Run `native-view`; expect missing-view failures.
- [ ] Implement native view lifecycle using the measured NSView hooks. Keep prepare/reshape defaults minimal; the subclass chooses viewport/projection. ClearGLContext detaches/releases; the next openGLContext access lazily recreates from the retained pixel format. Reject replacement with an incompatible format.
- [ ] Build a two-window demo with a rotating textured object and distinct clear colors, sharing one texture between contexts. Run lifecycle tests including explicit context replacement, removal/reparent, zero size, repeated clear/recreate, and failed lazy creation. Actual visual acceptance is Task 13.
- [ ] Commit `OpenGL: add native view lifecycle and demonstration`.

### Task 11: Close phase 1 with dual-architecture framework acceptance

**Files:** Finish `tests/abi.m`, build/header lists, `reconstruction/validation.md`,
and `vm/build-opengl.sh`; add `vm/test-opengl.sh` with `CPU SOURCE OUTPUT SUITE`.
**Interfaces:** `SUITE=phase1` runs all phase 1 targets and records individual exit
codes and loaded-image identities. Invalid CPU/suite/roots fail before execution.

- [ ] Add ABI assertions for every in-scope GL/GLU/AGL export and Objective-C selector, type widths/signedness, enum values, shared field offsets/alignment, and GLI/GLD dispatch slots against `abi.json`. Check dependency direction, actual install name, and linker symbol decoration. Run separately compiled C AGL and NSOpenGL clients switching/querying the same context. Confirm no second native context API is exported.
- [ ] Build/stage PPC and i386 separately with the runner, then a combined pb_makefiles build using `RC_ARCHS='ppc i386'` into its own output roots. Verify both Mach-O slices and complete version-A framework links/headers with the existing Mach-O reader.
- [ ] Run `phase1` on each available target and `check_evidence.py reference.json ledger.json --complete`. Check the complete source/ABI inventory manually as well; a nonempty function body alone is not reconstruction evidence.
- [ ] Record each CPU's build, unit, reference-evidence, and dependency status separately. Do not create OS-wide packaging or modify global manifests merely to claim integration; the explicit staged dependency build is the integration deliverable. Do not mark phase 1 complete with unresolved required code or target builds.
- [ ] Commit `OpenGL: verify framework and native view integration` only with the actual evidence represented accurately.

## Phase 2 — software-rendering validation

### Task 12: Establish offscreen software-rendering acceptance

**Files:** Create `tests/software_rendering.c`, `tests/render_cases.json`,
`tests/compare_pixels.py`, `tests/test_compare_pixels.py`, and
`reconstruction/software-validation.md`; add the `software-rendering` target.
**Interfaces:** The native harness emits dimensions, RGBA bytes, scene ID, CPU,
GL state/error observations, and loaded-image identity beneath
`OUTPUT/CPU/results/offscreen`. The host comparator accepts `--cases FILE --results DIR`,
reads per-case expected pixels/tolerances from the case metadata, and returns
nonzero for any mismatch. Missing or duplicate scene IDs also fail. Copy retrieved
results into host `tmp/opengl-validation/CPU/results/offscreen`.

- [ ] Add comparator tests proving a changed clear pixel fails, changed row guard fails, and a comparison never accepts a channel difference beyond the case's predeclared tolerance. Run host pytest and observe missing-comparator failures.
- [ ] Implement deterministic cases for clear/scissor/masks, depth/stencil, nearest texture lookup, transform/clip, blending, lists, sharing, and GLU; add cases for every advertised extension. Encode exact deterministic expected pixels; assert `glGetError()==GL_NO_ERROR` after valid scenes and the recovered error after invalid commands.
- [ ] Define any nonexact rasterization tolerance before collecting candidate output, recording the numerical justification and reference. Do not generate golden images from the new renderer or loosen tolerances after seeing a failure. Keep a separate exact/differential lane when the original renderer can actually run.
- [ ] Run `software-rendering` on both target CPUs and transfer outputs without lossy image conversion. Run `python src/Kits/OpenGL/tests/compare_pixels.py --cases src/Kits/OpenGL/tests/render_cases.json --results tmp/opengl-validation/i386/results/offscreen`, then the same command with `ppc` replacing `i386`. Expect every required scene to pass with the measured CPU identity. Test odd widths, padded strides, byte order, extreme clipping, and repeated object creation/destruction.
- [ ] Correct each rendering failure in its owning source with a reproducing regression, rerun affected cases, then the suite. Commit behavior fixes separately and commit the final evidence as `OpenGL: validate offscreen software rendering`.

### Task 13: Validate native window rendering in isolated guests

**Files:** Create `tests/window_rendering.m`, extend `vm/test-opengl.sh` with
`SUITE=phase2`, and update `reconstruction/software-validation.md`.
**Interfaces:** Native test writes scenario observations and captures named scene
states; host screenshot comparison checks pixels inside and outside the drawable.
Record guest identity, unique endpoint ports, CPU, mode, framework paths/hashes.

- [ ] Before booting, audit the current QEMU helpers for snapshot mode, unique names/ports, and query-name-before-quit behavior. Use helpers only when they meet AGENTS.md; otherwise use a private invocation with equivalent checks. Never reuse the shared vm.conf or terminate by process name.
- [ ] Run the demo/test against the built OpenGL and explicitly identified AppKit/Foundation/Interceptor. Exercise resize, move, overlap/uncover, flipped/clipped child views, zero size, close/reopen, detach/reparent, shared textures/lists, and context transfer. Assert neighbor-window sentinels do not change and uncovered contents match the last presentation.
- [ ] Exercise controlled mapping loss/failure without terminating another session's Window Server. Confirm the adapter releases locks and stops writing through invalid mappings. Test real presentation and dependency integration as well as Task 8's isolated fault-injection assertions.
- [ ] Capture scene state, screenshots, and pixel checks; compare with Task 12's expected scene data. Run original-AppKit and rebuilt-AppKit lanes in separate processes/guests as needed and label both. A passing original-AppKit lane does not satisfy rebuilt integration.
- [ ] Fix failures with targeted regressions and rerun; mark any unavailable PPC/i386 runtime or required dependency blocked. Shut down only this guest using the prescribed sequence. Commit `OpenGL: record native software rendering acceptance` with accurate outcomes.

## Phase 3 — select the hardware path

### Task 14: Trace ATI dependencies and recommend the first hardware target

**Files:** Create `reconstruction/hardware-dependencies.md` and
`docs/superpowers/specs/2026-10-18-opengl-hardware-investigation.md` as an investigation
report, not an implementation-approved driver spec.
**Interfaces:** Consume accepted phase 2 evidence, the recovered renderer ABI,
and the supplied OpenGLRendererATI binary. Produce a recommendation with evidence
for device support, external components, command submission, memory, and synchronization.

- [ ] Confirm phase 2 acceptance before hardware implementation work. If software validation is blocked, preserve that status; do not relabel framebuffer presentation as acceleration.
- [ ] Trace each external QA entry to its owning library/interface using PEF metadata and callers. Locate any available lower ATI components, record hashes and export contracts, and distinguish supported hardware from mere name strings.
- [ ] Compare a narrow ATI dependency port with a native backend for the recovered renderer contract, using available GPU/emulator capabilities. Identify required kernel interfaces and test hardware; do not fabricate an acceleration API from existing framebuffer methods.
- [ ] Record feasibility, missing artifacts, CPU/GPU target, measurable accelerated test scenes, fallback behavior, and the recommended route. Review every conclusion against a binary, source, hardware document, or executed probe; label unresolved evidence.
- [ ] Commit `OpenGL: recommend a hardware acceleration path` and present the report for a separate hardware design/plan decision. No driver implementation is authorized by this task.

## Completion and handoff

Track phase 1 build/API/unit acceptance, phase 2 rendering acceptance, and phase 3
recommendation separately. Never collapse a blocked target into an overall PASS.
The plan introduces no automatic publication, installation into shared guests,
or promise that all three phases can finish without additional hardware evidence.

After plan review, choose native execution or task-by-task subagent execution.
For this tightly coupled reconstruction, native execution is recommended: the same
worker retains the evolving ABI/call-graph context across batches, with an independent
review at the end. Any execution method must preserve the evidence gates above.
