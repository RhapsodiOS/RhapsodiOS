# OpenGL framework reconstruction and native views

## Intent and agreed scope

Reconstruct Apple's supplied classic Mac OS OpenGL implementation as a native
RhapsodiOS framework, with Objective-C pixel formats, contexts, and views that
present through the existing Interceptor framework. Target 32-bit PowerPC and
i386, the historical Objective-C runtime, manual memory management, and the
repository's Project Builder/pb_makefiles build conventions.

The user approved the supplied mixed-version bundle as the reference and the
proposed framework/Interceptor architecture. Following plan review, the user
requested matching Apple's ABI rather than introducing a separate native context
ABI. Preserve the measured Apple interfaces and isolate necessary OS adaptations
behind them. The user requested three phases:

1. Framework reconstruction and native views.
2. Software-rendering testing and correction.
3. Investigation and selection of the hardware-acceleration path.

Phase 1 includes the software renderer implementation needed by phase 2.
Phase 2 provides rendering acceptance; a phase 1 build does not establish that
rendering is correct. Phase 3 selects an approach; hardware-driver implementation
requires its own design and plan after that investigation.

This document specifies phases 1 and 2 and the investigation boundary for phase 3.
It does not claim any implementation is complete.

## Measured reference

Archive: `C:\Users\raynorpat\Downloads\OpenGL_1_2_4.sit__0.hqx`.
Size: 1847920 bytes. SHA-256:
`fb9b9c273b50182b917ea1df360d9b9997f51c93b9879841a2ae7cf188412f4a`.

The archive is StuffIt 5 inside BinHex. It was extracted with unar, preserving
resource forks, into
`D:\RhapsodiOS\tmp\opengl-124-reference\extracted\OpenGL 1.2.4`.
Extracted reference binaries, resource forks, analyzer databases, and downloaded
analysis tools remain outside committed source.

All six data forks have PowerPC PEF headers. Versions below come from embedded
`vers` resources, not the archive filename.

| Component | Version | Data bytes | Data SHA-256 |
| --- | --- | ---: | --- |
| OpenGLEngine | 1.2.4 | 716021 | `df4dbb7d3dcfa1fafd53308af4632a9096d0b1b2e02ed07fce75df43466bad7f` |
| OpenGLLibrary | 1.2.5 | 233966 | `ec9a99787306f3ffa6735434ac66399773b10a7a9b623bc1590ef8ac64ecc948` |
| OpenGLMemory | 1.2.4 | 10370 | `9650ce61caf1e99e0d7071437ae8ce6dadbaa815bedc260a1a4a55c9073bbfb6` |
| OpenGLRenderer | 1.2.4 | 2869768 | `679d3cd4e01f45dfb777e1158c05910be80de3f98400c061ebefc4ac1fcc70d6` |
| OpenGLRendererATI | 1.3.2 | 412010 | `76377eada9be154974edbd533b936200192529df48ceabb024a73c542c077481` |
| OpenGLUtility | 1.2.4 | 214786 | `d92c1f944bba93adbe944b5d2c2e9dcf0f58ccf7ee95b50fd1d985695889a3a8` |

IDA loaded OpenGLLibrary and OpenGLRendererATI as PowerPC PEF. Library entries
include GL commands and AGL context/pixel-format operations. ATI entries include
`gldCreateContext`, `gldAttachDrawable`, `gldGetRenderDispatch`,
`gldGetSystemDispatch`, and texture/vertex-buffer operations.
OpenGLEngine additionally exposes `gliChoosePixelFormat`, `gliCreateContext`,
`gliAttachDrawable`, `gliGetFunctionDispatch`, `gliGetExtensionDispatch`,
`gliGetSystemDispatch`, and related destruction/query functions. Preserve these
distinct AGL, GLI, and GLD boundaries; recover their exact call relationships,
prototypes, layouts, and dispatch slots before implementation.

ATI also references external `QA*` operations, including
`QADrawContextNew`, `QADeviceGetFirstEngine`, `QAEngineGestalt`, and
`QATextureNew`. These dependencies must be traced before choosing a hardware
port. Renderer strings name several Rage and Radeon families; names alone do
not establish working hardware support or the presence of their lower drivers.
IDA's generic import iterator returned an empty list for these PEF files despite
external names being present. Do not interpret that result as absence of imports;
cross-check PEF loader metadata during the reference inventory.

## Approach and alternatives

Use evidence-driven source reconstruction with explicit RhapsodiOS platform
adaptations. Recover the supplied implementation's GL/GLU behavior and renderer
contracts; replace classic Mac OS allocation, loading, threading, and drawable
dependencies with native equivalents where required. Record each replacement
and the behavior it preserves. Do not transliterate PowerPC instructions into
architecture-specific C when portable source expresses the recovered behavior.

A Mesa-backed compatibility implementation would change the requested reference.
The existing `mesa-recon` branch contains planning material, not an implemented
renderer in the current checkout. It is background material only. Executing the
original PEF libraries through a classic-Mac compatibility layer would introduce
a separate runtime and is outside this design.

## Framework structure and dependency direction

Create the project under `src/Kits/OpenGL`, with `PB.project`, makefiles, public
headers, resources, focused tests, and reconstruction evidence. Produce
`/System/Library/Frameworks/OpenGL.framework/Versions/A/OpenGL` and the usual
framework links. Integrate with the repository's actual framework build ordering
after inspecting it; do not assume an entry in a manifest alone builds a kit.

The framework contains these logical units, without introducing extra public
frameworks or a general-purpose plugin system:

- GL/GLU entry points, Apple AGL context operations, and recovered GLI/GLD dispatch.
- Engine, software rendering, memory support, and GLU routines.
- Private native platform services and drawable binding behind the Apple interfaces.
- Objective-C pixel-format, context, and view adapters.
- An internal Interceptor presentation adapter.

Preserve recognizable reference component boundaries in source and the evidence
ledger. Derive internal renderer tables and signatures from the binaries rather
than inventing a substitute ABI. Public GL/GLU declarations must agree with the
implemented exports. Record the supported API and extension inventory before
publishing version or capability strings.

OpenGL links to AppKit, Foundation, and Interceptor. Interceptor already links to
AppKit and Foundation. AppKit must not link back to OpenGL. Place the new
Objective-C classes in OpenGL.framework and expose them through
`<OpenGL/NSOpenGL.h>` and `<OpenGL/NSOpenGLView.h>`. Applications explicitly link
OpenGL.framework. This is a RhapsodiOS source API, not a claim of later macOS
AppKit binary compatibility.

Preserve GL/GLU and the portable AGL pixel-format/context/offscreen API, including
names, parameter and return types, constants, error conventions, and opaque handle
semantics. Preserve measured GLI engine and GLD renderer contracts, especially
dispatch-table order, shared structures, ownership, and callback signatures.
Objective-C objects wrap those handles; do not interpose a second public or
cross-module context ABI with new status codes or retain/release entry points.

Recover compatibility declarations in `gl.h`, `glu.h`, `agl.h`, and private
GLI/GLD headers from matching headers and binary evidence. Record unsupported
classic-platform entry points separately. A complete QuickDraw compatibility
runtime and a complete later-macOS CGL API remain outside phases 1 and 2. Never
pass an NSView pointer as an AGLDrawable/QuickDraw port or rename an AGL function
to CGL while retaining an incompatible signature. Native drawable binding remains
private and uses the measured engine/renderer contracts with explicit adaptations.

This targets Apple-compatible interfaces in rebuilt source and native Mach-O
libraries. It does not load the original PEF components unchanged. Record PPC
PEF-to-Mach-O calling convention/loader adaptations and the i386 port separately;
source compatibility, measured data-layout compatibility, and executable binary
compatibility are different claims. Preserve matching layouts where feasible,
and record every necessary deviation with a caller-based justification. Keep
native ownership/thread bookkeeping in private side tables or Objective-C objects
rather than appending fields to a shared Apple ABI structure.

## Native Objective-C contract

Provide the following initial API surface using types compatible with the
repository's headers and compiler:

- `NSOpenGLPixelFormat`: attribute-based initialization, attribute queries, and
  virtual-screen count. Support window and offscreen software drawables,
  single/double buffering, color, depth, and stencil requirements where the
  recovered renderer supports them. Reject unsatisfied requirements and unknown
  attributes; never silently promise acceleration or unavailable buffers.
- `NSOpenGLContext`: initialization with pixel format and optional share context,
  current-context access/set/clear, view attachment/detachment, drawable update,
  and `flushBuffer`. Sharing covers the reference-supported shareable objects;
  identify and test texture and display-list ownership explicitly.
- `NSOpenGLView`: frame/pixel-format initialization, pixel-format and context
  access, context replacement/clearing, `prepareOpenGL`, `reshape`, and
  `drawRect:` integration. Call preparation once per newly installed context and
  reshape after drawable-size changes. Preserve normal NSView event handling.

Document selectors, constants, widths, and error behavior in the implementation
plan and recovered ABI manifest before adding public headers. Match Apple
NSOpenGL attribute values and translate explicitly to AGL attributes where needed;
do not choose new numeric values or assume the two APIs have identical lists.
The selector list above is the scope boundary;
it does not authorize modern Cocoa features, nib compatibility, or additional
OpenGL extensions.

A context is current on at most one thread at a time. Track the current context
per thread and require clearing before transfer. Detect concurrent ownership
instead of allowing two threads to corrupt dispatch state. Native adapters use
the repository's available thread facilities and must not retain a stale context
after destruction or thread exit. Measure the supplied AGL current-context model;
record any thread-local behavior added for native NSOpenGL as a platform adaptation,
not historical parity. C GL/AGL callers and NSOpenGL must observe the same binding.
Shared resources outlive any one context while
other contexts in the share group still own them.

The view retains its context and pixel format. The context's drawable association
does not retain the view; view teardown clears that association before releasing
the context. Any Interceptor delegate ownership must also avoid a retain cycle.
Replacing or detaching a drawable preserves unrelated GL state and shared objects.

## Drawable and presentation flow

The application makes its context current and issues GL calls. The reconstructed
software renderer writes into context-owned buffers. Presentation converts/copies
the completed color buffer into an Interceptor-managed bitmap and flushes only
the visible portion of the view.

Reuse `NSDirectBitmap` rectangle updates, clipping, buffering, locking, and flush
operations. Its bitmap address and stride are meaningful while locked; never
cache mapped framebuffer addresses across unlocks, window moves, or mode changes.
Reuse existing pixel-conversion routines where their formats match. Keep rendering
outside the framebuffer lock, taking that lock only for presentation work.

Compute the drawable rectangle in window coordinates and intersect with the
view's visible region. Handle flipped views, row stride, pixel packing, and CPU
byte order explicitly. On resize, replace size-dependent buffers and update the
viewport contract through `reshape`; do not silently rewrite application GL state.
Zero-size and detached views have no presentable drawable. Occluded regions must
not overwrite other windows; exposure must restore the latest presented content.

For double buffering, `flushBuffer` presents the completed back buffer; for single
buffering, preserve the reconstructed renderer's flush behavior through the native
drawable adapter. Buffer swaps must not imply hardware page flipping or vertical
synchronization. Unsupported acceleration requests fail honestly.

Allocation failure must leave existing valid objects intact or fail initialization
cleanly. Invalid pixel formats and incompatible sharing fail creation. Lost window
server mappings invalidate presentation resources; never continue writing through
an old pointer. Preserve reference GL and AGL error semantics, including their
separate error state and return conventions. Do not introduce a parallel numeric
error ABI. Native-only presentation failures remain private diagnostics and
documented Objective-C behavior.

## AppKit prerequisites

The inspected `src/Kits/AppKit/NSView.m` implements basic state queries, but lacks
several operations declared by its header, including frame setters, coordinate
conversion, hierarchy mutation, and focus operations. Audit the full build and
runtime before treating any missing method as available through another unit.

Recover only prerequisites required for this OpenGL view, using the existing
AppKit reconstruction evidence and conventions. Do not expand this effort into
general AppKit reconstruction or replace normal view behavior with OpenGL-only
shortcuts. Document unrelated runtime blockers. A working demo against the guest's
original AppKit is useful evidence, but does not prove rebuilt AppKit integration.

## Phase 1: framework and native views

Inventory the five non-ATI components' owned functions, exports, external
dependencies, data tables, and calling conventions. Establish PEF analysis support
using IDA and narrowly extend existing evidence tooling only when needed. Map every
owned routine to recovered source, a documented platform replacement, or an explicit
out-of-scope classic-platform API. Unknown routines and no-op stubs are incomplete.

Reconstruct the software path and native adapters, add necessary AppKit
prerequisites, build both architectures, and prepare an Objective-C demo and
offscreen test harness for phase 2. Hardware-only dependencies must not prevent
loading or selecting the software renderer.

Phase 1 acceptance requires successful PPC/i386 framework builds, header/link
checks, Apple ABI checks for types/constants/layouts/dispatch slots, an accounted-for
export and routine inventory, and focused tests of
allocation, pixel-format rejection, context ownership/sharing, drawable lifetime,
and presentation bounds. These checks are part of implementation, not postponed
until phase 2. Track byte order and target ABI independently for both CPUs.
Compile a separate C GL/AGL caller and an NSOpenGL caller against the compatibility
headers and exercise their shared context state. Export spelling alone is not ABI
validation; use evidence-derived expectations independent of implementation headers.

Phase 1 completion is structural and behavioral-unit acceptance. It must not be
reported as software-rendering acceptance or full hardware parity.

## Phase 2: software-rendering validation

Run the real renderer first against offscreen buffers, then through the native
view and Interceptor in disposable RhapsodiOS guests. The minimum rendering matrix
includes clear/color/depth/stencil behavior, immediate-mode geometry, transforms,
clipping, textures, blending, depth ordering, display lists, GLU operations, and
the extensions advertised by the completed framework. Expand coverage from the
actual recovered API inventory; the demo alone is insufficient.

Use exact expected pixels for deterministic operations. Establish tolerances for
rasterization and floating-point comparisons before assessing results. Distinguish
specification-based tests from differential comparisons with the supplied renderer.
Only claim differential parity when the original implementation has actually run
under a compatible classic-Mac environment with a recorded test configuration.

Exercise multiple windows/contexts, resource sharing, context transfer between
threads, resize, move, overlap/uncover, flipped views, detachment, destruction,
invalid formats, and allocation/presentation failures. Verify clipping visually
and with captured pixels; check guards around offscreen buffers for bad strides
and bounds. Correct failures before claiming this phase complete.

Record the framework build, CPU, display depth, AppKit/Foundation/Interceptor
versions, guest image, scene inputs, expected results, actual results, and relevant
screenshots. Report separately for PPC and i386. Cross-compilation or a host mock
does not replace guest execution. If a target guest or dependency is unavailable,
leave that acceptance item explicitly blocked.

Follow AGENTS.md guest isolation rules: use snapshots or throwaway copies, unique
guest names and SSH/QMP/monitor ports, verify ownership with QMP `query-name`, and
never boot the shared base image writable. Use the prescribed sync/reboot/quit
sequence for writable guests and resync a snapshot guest after restarting it.

## Phase 3: choose the hardware-acceleration path

After software validation, trace the ATI renderer's `QA*` dependencies and identify
the actual lower driver components, hardware command interface, memory management,
and synchronization requirements. Compare these with the available RhapsodiOS
DriverKit drivers and hardware or emulator capabilities.

Evaluate a narrow port of the ATI dependency path against a native backend that
implements the recovered renderer contract for one supported GPU. Consider other
backends only when concrete available hardware makes them relevant. Existing
framebuffer support and renderer-name strings do not prove 3D acceleration.

Deliver an evidence-backed recommendation identifying the first GPU/CPU target,
required reference artifacts, kernel/user-space boundary, test environment, and
remaining gaps. Retain software fallback. Do not preselect a GPU, add speculative
kernel interfaces, or claim acceleration in phases 1 or 2. Hardware implementation
receives a separate approved design and plan.

## Review and implementation boundary

Review this written spec before creating the implementation plan. After approval,
write an executable phase 1 plan and concrete phase 2 acceptance tasks, respecting
the three-phase sequence. Phase 3 remains an investigation rather than a promised
driver implementation. No product source has been changed for this design.
