# Validation record

## Baseline

- PowerPC reference: 70,852 bytes, SHA-256
  `4a08718bd848e733a7e4ef8ef8f7b9a282a2fe56c8d38b14f23622c9983b7179`.
- Resource SHA-256 inventory: `resources.sha256` (13 files).
- Local Downloads search: found the supplied PowerPC ProcessViewer binary and
  a Rhapsody DR2 PPC installation image containing the matching-era SDK;
  no i386 oracle currently available.
- Binrecon validates both artifacts. The current rebuilt PPC executable is
  69,480 bytes, SHA-256
  `3d6f27b63b8b7b1081b0dfe8e31671ea880fba42164f42a1d1ae6f7e7e022e5a`.
  IDA 9.4 comparison completed with `normalized-functions=FAIL`: 1 of 131
  function records is assembly-matched, 125 differ, 3 are missing from the
  reference-side pairing, and 2 are missing from the rebuilt-side pairing.
  Keep this acceptance failure visible; this comparison is not evidence of
  complete binary parity. Output is under ignored
  `tools/binrecon/out/processviewer-ppc`.
- Hex-Rays run: 83 application functions (78 Objective-C methods and five C
  functions), zero decompilation failures. Pseudocode and IDA database remain
  ignored under the same output directory and are indexed in `pseudocode.md`.
- Binrecon parser, source-map, and ledger tests: `pytest tests/test_macho.py
  tests/test_objc_index.py tests/test_source_map.py tests/test_ledger.py -q`
  from `tools/binrecon` — 117 passed. The metadata index's
  46 directly decoded names reconcile to all 78 method symbols using class and
  category IMP addresses; no parser change was made.
- The normalized binrecon exporter records instructions, basic blocks,
  references, and import stubs, not pseudocode. A separate Hex-Rays IDAPython
  pass generated the pseudocode. Individual methods still require behavioral
  checks during their implementation tasks.
- PPC selector audit: `selector_check.py` reports 78 reference selectors and 78
  source definitions, with zero missing, extra, renamed, or duplicate selectors.
  The source map validates with 83 mapped application functions, 45 runtime or
  import entries, and no disputed boundaries. The auxiliary C/data name audit
  finds source definitions for all 19 application data symbols; its remaining
  six text names and eight data names belong to startup, dyld, and runtime code.
  The i386 linked executable's `nm` output contains the reconstructed app-owned
  globals, including the sort/status keys, process key and protected-name lists,
  defaults keys, type registry, and inspector preferences.

## Per-architecture completion matrix

| Evidence | PowerPC | i386 |
|---|---|---|
| Reference identity | verified | no reference found |
| Static function inventory | 83 app-owned functions mapped and control-flow-confirmed; the 45 unreviewed entries are startup/runtime/import code outside the application | shared PPC contract only; no i386 oracle |
| ABI / selector inventory | extracted to `abi.md` | target runtime ABI probe passes; no reference selector oracle |
| Application build | all six sources compile and link against the recovered DR2 PPC SDK; Mach-O PPC executable and 13-resource app bundle staged | direct guest link passes; Mach-O i386 confirmed |
| Deterministic behavior tests | not run on PPC | all six primary i386 targets (abi, process, process-types, table, controller, inspector) and live argv/sysctl/status probes pass |
| GUI integration | not run | staged app and minimal NSApplicationMain bundle both SIGBUS in headless guest |
| Instruction-level parity | binrecon normalized comparison fails (1 matched, 125 differing, 5 unpaired records); all 83 app functions are control-flow-confirmed, including Inspector visibility geometry | unavailable without oracle |

## Rebuilt PPC comparison and audits

- The executable was built with the DR2 PPC headers, frameworks, startup object,
  and compiler support archive extracted read-only from the local DR2 PPC image
  into a temporary sysroot. It is a PowerPC Mach-O executable and links to the
  expected AppKit, Foundation, and System framework install paths. The staged
  bundle contains all 13 reference resources. PPC execution and GUI startup
  remain unverified because the local PPC image does not provide a usable guest
  shell and the QEMU boot attempts did not reach SSH.
- Both architecture builds pass: PPC cross-compiles and links against the
  recovered DR2 SDK, and i386 links in the disposable guest. The current PPC
  comparison remains a failure and is not evidence of binary parity.
- `selector_check.py` reports an exact 78/78 selector match. The auxiliary
  C-symbol audit finds all 11 hand-written symbols; its six unmatched names are
  startup/dyld symbols, with no extra symbols. These audits establish name
  coverage only, not instruction parity.
- The latest import audit reports 76 reference imports and 74 rebuilt imports.
  The three reference-only names are `NSException`, `NSGenericException`, and
  `NSInvalidArgumentException`; `_getpid` is rebuilt-only.
  The app-string audit still reports seven reference-only and three
  rebuilt-only strings. These differences remain open for source/resource and
  link-map review. `Inspector -setVisible:` now matches the recovered window
  expansion/collapse flow, minimum-size adjustment, 10-point screen inset,
  `NSPointInRect` clamp, frame update, and visibility persistence. Its i386
  regression passes the screen-edge, minimum-height, idempotence, and visibility
  lifecycle cases.

The static ABI header/resource checks pass four tests. The live enumeration probe
creates a controlled child, verifies parsed `ps` fields against its sysctl
record, terminates and reaps it, confirms a cache-only read still returns the
retained object, then confirms a forced refresh removes the stale process while
preserving the same `Process` object for PID 1. A separate
run with `NSZombieEnabled=YES` also completes without zombie-release reports.
`git diff --check` reports no whitespace errors. The
i386 test binaries were rebuilt from the synchronized
source tree in the private disposable Rhapsody guest; the bundle-backed
`process-types` probe confirms discovery and localization of a second bundled
`*.processType` file. Expected Foundation logs
about its missing distributed notification server appear in process-type and
table tests. Inspector tests cover the recovered frame constraints and visibility lifecycle,
including preference persistence and restoration from the saved bool setting. The observer test verifies that unrelated and replaced-process notifications leave the pane open, while the current process invalidation closes it. Tab tests cover all three valid content mappings, invalid indices, missing selection, and missing fallback views. Detail-display tests verify process fields, path/arguments, empty-argument and nil fallback, and no/multiple-selection text. A separate real-NIB probe remains unverified: it hit
missing pasteboard/RulebookServer services and an uncaught nil insertion during
bundle loading. Controller tests interpose username, alert, signal, and save-panel calls. They
verify owner gates, protected-name warnings, cancellation, preference-dependent
confirmation text, and signal selection without showing real panels or
signaling a real process. Export tests verify filtered property-list contents, cancellation, dictionary
build ordering, and one beep after a failed atomic write. The test build also defines
`PROCESSVIEWER_TEST` so the app's `main` in `ProcessControl.m` does not collide
with the test runner's entry point. Inspector geometry tests cover the recovered
initial tab frame width and minimum height, plus split-view growth, shrinkage,
undersized existing child frames, and minimum-height boundaries. The two-child
resize path now uses the recovered frame-height minus child-heights-and-divider
calculation, applies minima in child order, and follows the non-two-child
`adjustSubviews` fallback; the i386 inspector test, app build, and focused suite pass. The
real-NIB probe remains unverified because the headless guest lacks pasteboard
and RulebookServer services and then throws during bundle loading.


- Inspector parity follow-up: PPC `dealloc` releases four view ivars and calls `super`; it has no notification-center removal call. The table data source directly indexes `arguments[row + 1]`; regressions verify row `-1` maps to the executable path and invalid accesses raise.
- Process ownership audit: PPC `ProcessType -dealloc` releases `_name` only; source-only releases of `_key` and `_values` were removed. Process field accessors match PPC.
- Inspector split-view setter audit: PPC removes the previous split view, retains its replacement, and derives the minimum main-pane height from the replacement and first-subview frames. A regression failed against the earlier tab-container calculation and passes after correction.
- Process arguments audit: PPC creates and caches the result array after a successful `table()` call even if its terminator scan finds no final four-NUL boundary; source now matches. Live argument parsing passes.
- Map enumerator, dictionary export, string-value helper, suffix-number conversion, ProcessType initialization, table-header behavior, and small ProcessControl callbacks match PPC pseudocode and existing relevant tests.
- Current ledger: all 83 app-owned functions are control-flow-confirmed; the 45 remaining entries are startup/runtime/import code. PPC runtime remains unavailable; the i386 full target suite and app link pass.

- ProcessControl destructor audit: PPC releases only the four collection ivars before `super dealloc`. Removed the source-only timer invalidation/release and `optionsDictionary` release; the focused suite and i386 app link pass. Current ledger: 72 confirmed / 56 unreviewed.

- Inspector NIB setup audit: PPC sizes the pane from `splitView.bounds`, wires the arguments table before tab setup, and detaches the container and four pane views before installing tab items. Source now follows this sequence; the headless guest cannot instantiate the production NIB, so this method is confirmed statically rather than through an end-to-end GUI run.
- UID cache and app entry point: `_NameForUID` matches PPC's uid+1 map key, passwd lookup, UTF-8 conversion, cache insertion, and returned cached object; `_main` forwards directly to `NSApplicationMain`. Current ledger: 82 confirmed / 46 unreviewed. The kill selection path now mirrors PPC direct row indexing; `applicationDidFinishLaunching:` remains unconfirmed because PPC restores additional window, table, and sort state.
- Kill-path follow-up: removed the source-only selected-row bounds check in `killProcesses:` to match PPC direct indexing. The focused i386 suite passes and the app relinks as Mach-O i386. PPC compilation and GUI/runtime validation remain unavailable in the current environment.

- Action wiring follow-up: `assignActions` now enables table-column autosaving before assigning header targets/actions, matching PPC. The regression first failed against reconstructed source and passes after the fix; the full focused i386 suite and i386 app link pass.

- About-panel parity: IDA data confirms version `15.0`, `CopyrightStartYear`=`1998`, and `Version`; the reconstructed options dictionary and `_cmd`/sender forwarding now match PPC. A controller regression verifies the options, forwarding, and cache reuse; focused i386 tests and app linking pass.

- ProcessControl initialization: PPC registers DefaultTypeTag=-1, RefreshInterval="20.0", and DeleteProtectedProcesses="NO" before allocating its three mutable arrays. Source follows that order; a test-only defaults capture verifies the exact values without mutating the guest preference store. The focused i386 suite and app link pass.

- Header-view class installation: PPC initWithCoder: writes the ProcessTableHeaderView class pointer into a decoded non-nil header view. Source uses a shared class-install helper; the i386 table regression verifies the swap and restores the test object. The focused suite and i386 app link pass. Current PPC ledger: 83 control-flow-confirmed and 45 unexamined; launch and printing are control-flow-confirmed.

- Launch review: PPC sets the shared print orientation to landscape and its left margin to 36 points before menu population. Source now applies those settings and restores the saved process-window frame before enabling autosave; the i386 focused suite and application link pass. The saved type selection, sort-button styling, frame restoration, and window activation now match the PPC selector and branch flow. Static launch reconstruction is confirmed; end-to-end GUI startup remains unavailable in the headless guest.

- Print behavior: PPC resolves to `[[processTable superview] superview]` as the view passed to `NSPrintOperation`; the i386 regression failed against the prior table-view argument and passes with the recovered ancestor. Focused tests and app link pass. Current PPC ledger: 83 control-flow-confirmed and 45 unexamined.

- Launch completion: `__sel_backref` resolves every launch selector, and PPC constant strings provide the preference keys, autosave names, sort behavior, and print settings. Source now follows that sequence. All 83 app-owned functions are control-flow-confirmed, including the recovered `Inspector -setVisible:` window geometry branch; the remaining 45 ledger entries belong to startup/runtime/import code. PPC compilation and linking now pass against the recovered DR2 SDK; PPC execution and GUI startup remain unavailable. The i386 focused suite and application link pass.
