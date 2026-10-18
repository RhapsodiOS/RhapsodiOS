# OpenGL Framework Reconstruction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reconstruct the supplied OpenGL implementation as a PPC/i386 RhapsodiOS framework with native Objective-C views, validate its software renderer, and then recommend a hardware-acceleration path.

**Architecture:** Recover the supplied GL/GLU, engine, memory, software renderer, and dispatch contracts from PowerPC PEF evidence. Add a native context boundary and Objective-C view adapter inside OpenGL.framework, presenting through Interceptor without an AppKit-to-OpenGL link. Hardware investigation starts after software acceptance.

**Tech Stack:** C89, historical Objective-C and manual memory management, Foundation threads/locks, AppKit, Interceptor, DriverKit-facing presentation, Project Builder/pb_makefiles, Python host evidence checks, IDA, isolated PPC/i386 guests.

**Spec:** [Approved three-phase design](../specs/2026-10-18-opengl-framework-reconstruction-design.md).

## Global Constraints

- Target 32-bit PowerPC and i386, the historical Objective-C runtime, manual memory management, and the repository's Project Builder/pb_makefiles build conventions.
- Create the project under `src/Kits/OpenGL`.
- Produce `/System/Library/Frameworks/OpenGL.framework/Versions/A/OpenGL` and the usual framework links.
- AppKit must not link back to OpenGL.
- Place the new Objective-C classes in OpenGL.framework and expose them through `<OpenGL/NSOpenGL.h>` and `<OpenGL/NSOpenGLView.h>`.
- A public QuickDraw/AGL compatibility layer and a complete later-macOS CGL API are outside phases 1 and 2.
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
| `gl.h`, `glu.h`, `glext.h`, `OpenGL.h` | Measured GL/GLU/extension public declarations |
| `NSOpenGL.h`, `NSOpenGLView.h` | Native Objective-C source API |
| `Private/RGLNative.h`, `Private/RGLRenderer.h`, `Private/RGLState.h` | New native boundary, recovered renderer ABI, recovered internal state |
| `Platform/RGLMemory.c`, `Platform/RGLThread.m`, `Platform/RGLBuffers.c`, `Platform/RGLContext.c` | Native allocation, thread ownership, drawable buffers, context lifecycle |
| `Library/GLDispatch.c`, `Library/GLState.c`, `Library/GLObjects.c`, `Library/GLLists.c` | GL exports, state/errors, shareable objects, display lists |
| `Engine/GLTransform.c`, `Engine/GLClip.c`, `Engine/GLLight.c`, `Engine/GLEvaluate.c` | Recovered transformation, clipping, lighting, evaluation pipeline |
| `Renderer/GLPrimitive.c`, `Renderer/GLFragment.c`, `Renderer/GLTexture.c`, `Renderer/GLPixel.c` | Software primitives, depth/stencil/blend, sampling, pixel operations |
| `Utility/GLUProject.c`, `Utility/GLUMipmap.c`, `Utility/GLUQuadric.c`, `Utility/GLUTess.c`, `Utility/GLUNurbs.c` | GLU families present in the reference |
| `NSOpenGLPixelFormat.m`, `NSOpenGLContext.m`, `NSOpenGLView.m` | Public Objective-C adapters |
| `Private/NSOpenGLDrawable.h`, `NSOpenGLDrawable.m` | Interceptor attachment, clipping, conversion, presentation |
| `reconstruction/reference.json`, `abi.md`, `native-api.md`, `ledger.json`, `batches.md`, `build-environment.md`, `validation.md` | Reviewed identities, contracts, source mapping, build and acceptance evidence |
| `reconstruction/export_ida.py`, `check_evidence.py`, `tests/test_evidence.py` | PEF-aware evidence export/checking, with no bundled proprietary bytes |
| `tests/Makefile`, `test_support.h`, `test_support.m`, named tests below | Native behavioral and rendering tests |
| `examples/OpenGLDemo.m`, `examples/Makefile` | Two-window demonstration without nib dependencies |
| `vm/build-opengl.sh`, `vm/test-opengl.sh` (repository root) | Explicit staged dependency/build and test entry points |

Modify existing AppKit methods only in their owning files and only when Task 7
demonstrates a missing prerequisite. If the recovered call graph requires extra
source units, record their exact paths in `batches.md` before adding them; split
along recovered responsibilities rather than growing a single renderer file.

## New native interfaces

These are RhapsodiOS adapter contracts, not assertions about Apple's private ABI.
Task 1 separately records every recovered `gl*`, `glu*`, and internal `gld*`
signature with its reference address and evidence.

In `Private/RGLNative.h`, use opaque `RGLPixelFormat` and `RGLContext` structs,
`unsigned int` attributes, and this status enum: `RGLOk=0`, `RGLInvalid=1`,
`RGLNoMemory=2`, `RGLBusy=3`, `RGLNoDrawable=4`, `RGLUnsupported=5`,
`RGLDrawableLost=6`. Status values describe adapter failures, not GL errors.

```c
RGLStatus RGLChoosePixelFormat(const unsigned int *attrs, RGLPixelFormat **out);
void RGLRetainPixelFormat(RGLPixelFormat *format);
void RGLReleasePixelFormat(RGLPixelFormat *format);
RGLStatus RGLGetPixelFormatValue(const RGLPixelFormat *format,
                               unsigned int attribute, int *out);
RGLStatus RGLCreateContext(RGLPixelFormat *format, RGLContext *share,
                          RGLContext **out);
void RGLRetainContext(RGLContext *context);
void RGLReleaseContext(RGLContext *context);
RGLStatus RGLMakeCurrent(RGLContext *context); /* NULL clears this thread */
RGLContext *RGLGetCurrentContext(void);       /* borrowed, thread-local */
RGLStatus RGLResizeDrawable(RGLContext *context, int width, int height);
void RGLClearDrawable(RGLContext *context);
RGLStatus RGLCopyPresentableRGBA(RGLContext *context, unsigned char *dst,
                               unsigned long capacity, int stride);
RGLStatus RGLFlushDrawable(RGLContext *context);
```

Creation/query functions set output pointers only on success; creation failures
set `*out=NULL`. Retains/releases accept NULL. Resize accepts zero dimensions as
nonpresentable, rejects negative/overflowing dimensions, and preserves old buffers
on allocation failure. RGBA copies use byte-ordered R,G,B,A, bottom row first,
8 bits per channel, with caller-supplied capacity/stride; reject insufficient
capacity without writing. This is a presentation conversion, not a requirement
to replace recovered internal pixel formats. Flush completes pending software
work before the adapter copies the buffer selected for presentation. The recovered
single/double-buffer semantics are fixed in Task 1 and wired in Task 4.

`NSOpenGL.h` declares `typedef unsigned int NSOpenGLPixelFormatAttribute` and
project-chosen tokens: DoubleBuffer=5, ColorSize=8, AlphaSize=11, DepthSize=12,
StencilSize=13, OffScreen=53, Accelerated=73, Window=80, each prefixed
`NSOpenGLPFA`. The attribute list ends in 0; size tokens consume an integer value,
boolean tokens do not. No other token is accepted initially. These are deliberate
adapter API values, not values extracted from the PEF reference. Require exactly
one drawable kind; default to Window when neither is supplied. Nil attributes
request that default. Actual size defaults and supported combinations are the
measured software renderer defaults, recorded in Task 1, not invented bit depths.
Accelerated is rejected until a backend exists. One software virtual screen is
reported, numbered 0; it is not a physical-display count.

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

Invalid format/share initialization returns nil. Bad attribute queries and wrong
drawable-kind attachments raise `NSInvalidArgumentException`. Concurrent current
ownership raises `NSInternalInconsistencyException` and leaves both threads'
bindings intact. Unrecoverable resize/presentation failures raise
`NSGenericException` with the adapter status after releasing acquired locks.
Flush of a zero-size/detached window view is a no-op; loss of a previously valid
mapping is an error. Keep GL command errors in the recovered GL error state.

Use NSThread's thread dictionary and `NSThreadWillExitNotification`, which are
implemented in this tree. A private binding object retains the C context while
current; an ownership lock guards cross-thread acquisition. Do not overwrite
`cthread_data`, which Foundation already uses. Public current-context lookup maps
the current C context to its live Objective-C wrapper; retain that wrapper in the
binding as well, and break the binding explicitly on clear/exit. Initialize shared
locking through the Objective-C class initialization path, not a racy lazy C flag.

## Test and build commands

Task 2 creates a test makefile whose targets compile and execute their named test,
return nonzero on failure, and emit `PASS <target>` only after all assertions pass.
`FRAMEWORK_ROOT` selects the absolute `OpenGL.framework` directory; dependency
roots and loaded Mach-O image paths are checked before execution. Separate processes
are required when swapping Foundation/AppKit/Interceptor implementations.

Guest commands, with `RGL_CPU` set to `ppc` or `i386` by the caller:

```sh
export RGL_SOURCE=/build/source
export RGL_OUTPUT=/build/opengl-validation
sh "$RGL_SOURCE/vm/build-opengl.sh" "$RGL_CPU" "$RGL_SOURCE" "$RGL_OUTPUT"
gnumake -C "$RGL_SOURCE/src/Kits/OpenGL/tests" memory RC_ARCHS="$RGL_CPU" \
  FRAMEWORK_ROOT="$RGL_OUTPUT/$RGL_CPU/sym/OpenGL.framework"
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

**Files:** Create the seven reconstruction evidence documents and three evidence
scripts/tests in the file map. Consume existing IDA APIs and Mach-O export tooling.
**Interfaces:** `check_evidence.py reference.json ledger.json` exits 0 for consistent
identity/accounting, 1 for missing/inconsistent evidence. `--complete` additionally
rejects unresolved owned routines. Ledger rows contain component/hash, address,
aliases, source path, prototype evidence, dependency edges, disposition, and tests.

- [ ] Write `test_changed_reference_rejected`, `test_alias_not_double_counted`, and `test_unresolved_blocks_completion` with synthetic JSON assertions: wrong hash fails; two labels at the same proven entry count once; unresolved owned entry fails `--complete`.
- [ ] Run `python -m pytest src/Kits/OpenGL/reconstruction/tests/test_evidence.py -q`; expect missing-checker failures before implementation.
- [ ] Implement the checker and IDA export; hash original data/resource forks, inventory all six components, and cross-check PEF exports/imports against loader metadata. Inventory code regions without symbols as well as named entries. Keep ATI evidence reference-only.
- [ ] Recover five-component software call graph, GL/GLU types, dispatch slots, memory ownership, actual formats/defaults, sharing rules, flush behavior, and extension list in `abi.md`. Create one evidence batch per independently testable family below; give every owned routine an explicit disposition. Do not discard code merely because it has no public export.
- [ ] Rerun tests and checker; expect evidence consistency PASS, while `--complete` correctly fails until reconstruction finishes. Commit `OpenGL: record reference contracts and reconstruction worklist`.

### Task 2: Establish native build and selected-framework test loading

**Files:** Create framework build/resource files, test Makefile/support files,
`tests/abi.m`, `tests/test_framework_identity.py`, and `vm/build-opengl.sh`.
**Interfaces:** Test support provides `int RGLTestCheck(int,const char *)`,
`int RGLTestFinish(const char *)`, and `int RGLTestVerifyImages(void)`; use historical
dyld image enumeration to validate the selected image and dependency paths.

- [ ] Add `test_wrong_framework_root_fails` and `test_missing_cpu_slice_fails`; assertion: exit is nonzero before rendering. Add header-width/link checks for the 32-bit ABI and version-A install name.
- [ ] Run the tests against absent and deliberately mismatched temporary fixtures; expect rejection, not silent system fallback.
- [ ] Model framework makefiles on Interceptor, but link OpenGL to Interceptor/AppKit/Foundation. Create the staged build runner and image identity checks. Empty build products are diagnostic only and cannot satisfy Task 11.
- [ ] Compile header probes for both CPUs and verify the installation tree under the external DSTROOT; run `abi` once implementation supplies the exports. Establish baseline availability of staged dependency slices; record blockers explicitly.
- [ ] Commit `OpenGL: add native framework build and test loading`.

### Task 3: Reconstruct memory services and GL object ownership

**Files:** Create `Platform/RGLMemory.c`, `Library/GLObjects.c`, corresponding
state declarations, and `tests/memory.c`, `tests/sharing.c`.
**Interfaces:** Consume Task 1's exact allocation/object signatures; expose the
pixel-format/context retain/release operations in the native interface as their
owning structures become available. Use a test-only allocation-failure seam.

- [ ] Add `allocation_failure_preserves_owner` and `share_group_survives_creator`: fail each allocation site in a creation sequence, assert no leaked ownership; destroy a creating context while another owner still resolves its texture/list namespace.
- [ ] Run targets `memory` and `sharing`; expect missing implementation or failed ownership assertions.
- [ ] Recover allocation/alignment rules, object names, reference counts, deletion, and share-group lifetime in separate evidence batches. Adapt Mac allocation services to native allocation without copying fixed PowerPC pointer arithmetic.
- [ ] Rerun `memory` and `sharing` on each target; verify malformed sizes/overflow rejection, repeated create/free, and failure cleanup with live-allocation counts returning to baseline.
- [ ] Commit each independently tested batch, using messages such as `OpenGL: reconstruct shared object lifetime`.

### Task 4: Recover pixel formats, contexts, and drawable buffers

**Files:** Create `Platform/RGLContext.c`, `Platform/RGLBuffers.c`,
`Private/RGLNative.h`, recovered ABI headers, `tests/pixel_format.c`, and `tests/buffers.c`.
**Interfaces:** Implement native choose/query/create/resize/clear/copy/flush
signatures above; consume the exact renderer tables recovered by Task 1.

- [ ] Test `unknown_attribute_rejected`, `accelerated_format_rejected`, `incompatible_share_rejected`, `failed_resize_preserves_pixels`, and `copy_capacity_checked`. Assert unsupported creation has a NULL output; invalid queries do not change output values; failed resize leaves old dimensions/content/objects intact; short destination gets no writes.

  Pin rejection without depending on a supported color/depth combination:
  ```c
  unsigned int accelerated[] = { 73, 0 };
  unsigned int unknown[] = { 0xffffffffU, 0 };
  RGLPixelFormat *format = NULL;
  assert(RGLChoosePixelFormat(accelerated, &format) == RGLUnsupported);
  assert(format == NULL);
  assert(RGLChoosePixelFormat(unknown, &format) == RGLInvalid);
  assert(format == NULL);
  ```
- [ ] Run `pixel-format` and `buffers`; expect contract failures before implementation.
- [ ] Reconstruct format enumeration, context setup/destruction, default state, front/back/depth/stencil allocation, and render/flush dispatch. Add offscreen buffers through the same context path used by views; do not make a separate test renderer.
- [ ] Run tests for zero/negative/extreme dimensions, explicit stride, mismatched share formats, single/double buffering, and allocator failure at each step. Verify exact byte order with RGBA bytes `0x12,0x34,0x56,0x78` on both CPUs.
- [ ] Commit `OpenGL: reconstruct software contexts and drawables`.

### Task 5: Enforce current-context thread ownership

**Files:** Create `Platform/RGLThread.m`, `tests/current_context.m`.
**Interfaces:** Produce `RGLMakeCurrent`/`RGLGetCurrentContext`; the private binding
retains current state and wrapper, releases on clear/exit, and leaves prior binding
unchanged when acquiring a context owned by another thread fails.

- [ ] Add `two_threads_cannot_own_one_context`, `failed_switch_preserves_old_context`, and `thread_exit_releases_owner`. Use condition locks/barriers, not sleeps; assert RGLBusy for competing acquisition, correct old current context after failure, and success after owner exit.
- [ ] Run `current-context`; expect ownership failures before implementation.
- [ ] Implement thread-dictionary bindings, guarded acquisition/release, and exit cleanup through the existing Foundation interfaces. Use the same current state for C GL dispatch and Objective-C currentContext.
- [ ] Test release reentrancy: clear a binding holding the last wrapper/context references and assert teardown completes without reacquiring an already-held ownership lock. Remove ownership under the lock, then perform destruction/releases after unlocking.
- [ ] Rerun with two independent contexts, repeated clear, nested autorelease pools, caller releasing its last reference while current, and thread exit without explicit clear. Confirm no global current-context pointer or Foundation thread-data overwrite.
- [ ] Commit `OpenGL: isolate current contexts by thread`.

### Task 6: Reconstruct GL dispatch, engine, software rasterizer, and GLU

**Files:** Create the Library/Engine/Renderer/Utility units in the file map,
public GL headers, and `tests/{dispatch,state,transform,primitive,fragment,texture,pixel,lists,glu}.c`.
**Interfaces:** Every public and private signature comes from Task 1's frozen
batch entry; GL dispatch obtains current native state from Task 5. Never expose
the private native status enum as a GL error or invent a `gld*` prototype.

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
`-(RGLStatus)updateForContext:(RGLContext *)context`,
`-(RGLStatus)presentContext:(RGLContext *)context`, and `-(void)detach`.
Consume NSDirectBitmap's lock/update/flush APIs and Task 4's RGBA copy interface.

- [ ] Write `clipped_flipped_padded_present` with a bitmap test double and guards; assert only the intersection changes and the visible rows are oriented correctly. Add `server_loss_releases_lock` and `move_reacquires_bitmap_pointer` with addresses changed between locks.
- [ ] Run `presentation`; expect missing-adapter failures, then retain these tests for mapping/lock regressions.
- [ ] Implement frame conversion, effective visible clipping, buffered bitmap presentation, and format conversion. Inspect the private view-clip selectors and retain/delegate behavior before using them. Use existing Interceptor copy operations only with their documented padding semantics; RGBA-to-display conversion must be explicit where layouts differ.
- [ ] Rerun tests for full occlusion, partial exposure, zero size, detach, map failure, and exceptions during copy. Check latest-presented content survives exposure and no retained delegate cycle or framebuffer pointer survives detach/unlock. Do not hold the framebuffer lock while rendering.
- [ ] Commit `OpenGL: present native drawables through Interceptor`.

### Task 9: Implement native pixel-format and context objects

**Files:** Create `NSOpenGL.h`, `NSOpenGLPixelFormat.m`, `NSOpenGLContext.m`,
`tests/native_context.m`; update build class/header lists.
**Interfaces:** Implement the exact public selectors, token values, and adapter
error translation above using Tasks 4, 5, and 8. Context view associations are nonowning.

- [ ] Add tests asserting nil for impossible initialization, one software virtual screen, exception for screen 1/unknown queries, setView:nil clears attachment, currentContext matches C dispatch, and incompatible concurrent acquisition preserves prior state.

  Include the no-context baseline before creating a test wrapper:
  ```objc
  [NSOpenGLContext clearCurrentContext];
  assert([NSOpenGLContext currentContext] == nil);
  assert(RGLGetCurrentContext() == NULL);
  ```
- [ ] Run `native-context`; expect missing classes/selectors or failed contracts.
- [ ] Implement the thin wrappers, ownership, error translation, view update/flush, and share-context initialization. Ensure autorelease activity cannot destroy the currently bound wrapper. Existing share objects survive drawable changes.
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

- [ ] Add ABI assertions for every public GL/GLU export and Objective-C selector in the frozen inventory, 32-bit type widths, absence of unsupported declared exports, dependency direction, and actual install name.
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
