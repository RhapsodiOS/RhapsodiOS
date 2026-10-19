# Foundation NSUndoManager reconnaissance

This note records an IDA analysis pass for the DR2 i386 `NSUndoManager`
implementation. The reference is IDA database `6c2a913dc37a`; its ABI record is
`src/Kits/Foundation/reconstruction/abi/NSUndoManager.json`.

`NSUndoManager.m` currently contains TODO bodies for all of the public
selectors listed in that ABI record, and no source implementation exists yet
for the target's private undo object classes. IDA confirms those classes and
their selector layouts in the same module: `_NSUndoStack`, `_NSUndoObject`,
`_NSUndoBeginMark`, `_NSUndoEndMark`, `_NSUndoLightInvocation`, and
`_NSUndoInvocation`.

Traced manager methods include `init` (`0x425457c4`), `dealloc`
(`0x4256c8f0`), grouping and event grouping (`0x42552558`, `0x4255246c`,
`0x42547cfc`, `0x42552440`), registration (`0x425464b4`, `0x425465a0`,
`0x4256ca18`), undo/redo (`0x4256d28c`, `0x4256d114`, `0x4256cd4c`), and the
public stack accessors and menu-title methods. The captured pseudocode shows
that initialization allocates two stacks, enables groups-by-event by default,
and initializes run-loop modes. Registration prepares event grouping, clears
redo history for ordinary registration, then pushes onto the active stack.
Undo and redo switch the active direction flag, transfer the group identifier,
invoke a complete marked group, and post the corresponding change
notifications.

The private stack is a doubly linked list headed at the newest object. Begin
and end marker objects track nesting; `_count` tracks complete top-level
groups, and `_max` trims oldest complete groups. `popAndInvoke` consumes
markers and invokes action objects until the outer group closes. The object
variants either retain an `NSInvocation` and its arguments or retain the
single argument for a selector-based invocation. Target class layouts and
selector encodings are recorded in the ABI JSON.

Other confirmed behavior includes nested enable/disable counting with an
exception on unmatched enable, group-by-event default-on, checkpoint
notification reentrancy protection, and localization of menu titles through
the Foundation bundle. Exact branches should follow the decompiled method
bodies; no source edits or tests were made during this analysis pass.

## Follow-up control-flow detail

A follow-up read-only pass confirmed the exact manager and stack transitions.
Initialization creates both stacks, clears the undoing/redoing flags, enables
groups-by-event, and initializes run-loop modes. `beginUndoGrouping` chooses
the redo stack only while undoing; otherwise it chooses the undo stack. It
posts a checkpoint notification when automatic event grouping does not already
have a top-level group open, adds a begin marker, and posts the open-group
notification outside undo/redo. `endUndoGrouping` posts a checkpoint, raises
on an empty active stack, posts the will-close notification outside undo/redo,
and adds an end marker.

`_registerUndoObject:` releases a registration when registration is disabled.
Otherwise, it clears redo history outside undo/redo, prepares event grouping,
requires an open group, and pushes the action to the active stack. `undo` first
posts a checkpoint, closes a pending top-level event group when required, and
raises if a group is still open before calling `undoNestedGroup`. `redo` and
`undoNestedGroup` require the active stack's newest object to be an end marker;
they begin a corresponding group on the opposite stack, copy the group
identifier, invoke the complete marked group, then close the opposite group
with notifications around the operation.

The stack stores its newest object at `_head`; every push links the new
object ahead of the previous head and maintains both `next` and `previous`.
Top-level begin markers increment `_count`; consuming the matching outer begin
marker decrements it. Closing a top-level group trims the oldest complete
group only when a nonzero `_max` is below `_count`. `popAndInvoke` consumes
markers while tracking nesting depth and invokes action objects until the
matching outer begin marker is reached.

This follow-up only updates the analysis note. `NSUndoManager.m` remains
untouched pending approval of the reconstruction design; no tests or builds
were run.

## Invocation and event-grouping detail

The two action objects intentionally have different ownership paths. The
lightweight selector action stores its target without retaining it, retains
its single argument, invokes the selector with that argument, and releases the
argument on deallocation. The full invocation action stores the target without
retaining it, retains its `NSInvocation`, calls `retainArguments`, and later
invokes it with the saved target; deallocation releases the invocation. The
base undo object stores its target and raises if its abstract `invoke` method
is called.

`_prepareEventGrouping` selects the active direction's stack and, when
groups-by-event is enabled, no automatic group is already pending, and the
active stack has no open group, sets the pending-event flag, begins a group,
and schedules `_processEndOfEventNotification:` on the current run loop.
That callback clears the pending flag and ends the group only while
groups-by-event remains enabled. `_postCheckpointNotification` guards its
notification with a separate in-flight flag so observers cannot recursively
post another checkpoint during the same callback.

## Registration, queries, and titles

`registerUndoWithTarget:selector:object:` constructs the lightweight action
and hands it to `_registerUndoObject:`. `prepareWithInvocationTarget:` stores
the temporary target and returns the manager as a forwarding proxy;
`methodSignatureForSelector:` first asks `NSObject`, then the temporary target.
`forwardInvocation:` raises if no target is active, clears the invocation's
target, wraps it in `_NSUndoInvocation`, registers it, and clears the temporary
target.

`canUndo` checks whether the undo stack has any objects. `canRedo` first posts
a checkpoint notification, then checks the redo stack. `removeAllActions`
clears both stacks, the forwarding target, undo/redo direction flags, and the
registration-disable counter; if an automatic event group is pending it
recreates the undo stack's begin marker. `removeAllActionsWithTarget:` removes
matching objects from both stacks. `setActionName:` assigns the active stack's
group identifier, while the action-name getters return the stack identifier
or the shared empty string.

Undo and redo menu titles use the action-specific localization hook only when
the corresponding stack is actionable and its group identifier is nonempty.
Otherwise, each title comes from `_NSFoundationBundle` using its own key, an
empty-string fallback, and the undo strings table.

## Group names and manager settings

`_setGroupIdentifier:` ignores nil names and all names while registration is
disabled. Otherwise it prepares event grouping, requires an open group on the
active stack, and sets the identifier on that stack's current begin marker.
The stack reads and writes the identifier through its newest begin marker.
The undo-level getter and setter proxy to the undo stack's `max` and `setMax:`;
run-loop modes are returned directly and replaced by copying the supplied
array in the manager's zone before releasing the old array.

Registration disabling is a nesting counter. Disabling increments it;
enabling raises if it is already zero and otherwise decrements it. The
enabled query is exactly `_disabled == 0`. Group-by-event setting replaces
only its flag bit, leaving the pending-event bit separate.

The title-format hooks load separate localized format strings for Undo and
Redo from the Foundation bundle and substitute the supplied action name.

## Marker and removal mechanics

The stack initializer sets count, maximum, and head to zero/nil. `markBegin`
and `markEnd` allocate their marker objects in the stack's zone and push them
through the same linked-list path as actions. `_beginMark` walks from the
newest object toward older objects, balancing end markers against begin
markers until it finds the begin marker for the active outer group.

The list's `next` links run from newest toward older objects. Removing a node
repairs its neighboring links and the head/tail reference, then releases that
node. `removeAllObjectsWithTarget:` walks the list and removes each node whose
base target matches the requested target. `removeAllObjects` releases the
entire list and resets count and nesting depth.

The disassembly of `push:` (`0x42547b44`) confirms the initial list invariant:
the first object's `next` points to nil and its `previous` points to itself;
later pushes set the new object's `next` to the former head and its `previous`
to the former head's `previous` (the tail), then update the former head's
`previous` to the new object. Pushing a begin marker increments the complete
group count only when nesting was zero, then increments nesting. Pushing an
end marker with zero nesting raises; otherwise it decrements nesting and trims
the oldest group only when that closes the outermost group and a nonzero
maximum is below the complete group count.

`popUndoObject` (`0x4256ea4c`) replaces the head with its `next` and copies the
old head's `previous` (the tail pointer) to the new head's `previous`. Popping
a begin marker decrements nesting and decrements the complete-group count when
it closes the outermost group; popping an end marker increments nesting. The
removed node is autoreleased. `removeObject:` (`0x4256ebe4`) splices an
interior or head node through its `next` and `previous` links; when removing
the tail, it clears the newer node's `next` and updates `head.previous` to the
new tail. This confirms that `head.previous` carries the tail pointer while
`next` walks toward older nodes.

`_removeBottom` (`0x4256e720`) begins at `head.previous`, requires the oldest
node to be a begin marker, then walks toward newer nodes using `previous` while
balancing begin and end markers. It releases each traversed node's older
neighbor, then sets the surviving tail's `next` to nil and decrements the
complete-group count.

Begin-mark group identifiers are copied in the mark's zone, and replacing or
deallocating a mark releases the prior identifier.

## Manager transitions

`init` creates independent undo and redo stacks in the manager's zone, clears
the disable counter and undo/redo flags, enables the initial-event-group flag,
sets the temporary forwarding target to nil, and creates an empty run-loop
modes array. `beginUndoGrouping` is a no-op while registration is disabled.
Otherwise, outside undo/redo it prepares event grouping, selects the active
stack, posts a checkpoint when automatic initial grouping is no longer in
effect or the selected stack is already nested, and pushes a begin marker.
Explicit grouping also posts the group-opened notification.

`endUndoGrouping` selects the active stack and posts a checkpoint before it
checks nesting. Ending at level zero raises. Explicit grouping posts the
group-closed notification before pushing the end marker. `_registerUndoObject:`
releases its argument if registration is disabled; otherwise it clears redo
history outside undo/redo, prepares event grouping, requires an active group,
and pushes the undo object onto the selected stack.

`undo` posts a checkpoint, closes a pending automatic outer group when the
pending-event bit is set and the undo stack is at level one, then rejects any
remaining open group before invoking `undoNestedGroup`. `undoNestedGroup`
switches into undo mode, requires the undo stack's newest object to be an end
marker, opens a corresponding group on the redo stack, copies the group
identifier, invokes and transfers the group from undo to redo, closes the redo
group, posts notifications around the operation, then clears undo mode. `redo`
returns immediately unless `canRedo` succeeds; it similarly requires an end
marker on the redo stack, opens a group on undo, copies the identifier, invokes
the redo group, closes the undo group, and clears redo mode. Both paths clear
their direction flag before raising on malformed stack shape.

IDA addresses: `init` `0x425457c4`; `beginUndoGrouping` `0x42552558`;
`endUndoGrouping` `0x4255246c`; `_registerUndoObject:` `0x425464b4`;
`undo` `0x4256d28c`; `undoNestedGroup` `0x4256d114`; `redo` `0x4256cd4c`.

## Exported notifications and diagnostic literals

The target exports all seven notification constants declared in
`NSUndoManager.h`: checkpoint, will/did undo, will/did redo, did-open-group,
and will-close-group. Their data symbols are contiguous at
`0x42603244`–`0x4260325c`; the referenced strings at `0x425faed5`–`0x425fafc1`
match the constant names. The current `NSUndoManager.m` TODO skeleton contains
no definitions for these exports yet.

The target's diagnostic strings also confirm distinct failure cases for
registration outside a group, ending an unopened group, unmatched enabling of
registration, undoing with too many nested groups, ending the group before
calling a restricted method, invoking a restricted method while undoing, and
removing the bottom stack group. These literals are stored at
`0x425fafed`, `0x425fb03a`, `0x425fb08a`, `0x425fb105`, `0x425fb157`,
`0x425fb1a9`, and `0x425fb32d` respectively. An additional guard at
`0x425fb472` requires closing the undo-manager group before that operation.

Direct pseudocode confirms the `endUndoGrouping`, `enableUndoRegistration`,
`undo`, `undoNestedGroup`, and `redo` exceptions use the corresponding strings
at `0x425fb03a`, `0x425fb08a`, `0x425fb105`, `0x425fb157`, and `0x425fb1a9`.

## ABI storage map for implementation

The checked-in ABI JSON gives the manager a 40-byte i386 instance. Its fields
are `_undoStack` at offset 4, `_redoStack` at 8, `_runLoopModes` at 12,
`_disabled` at 16, the packed flags at 20, `_target` at 24, and three reserved
pointers at 28, 32, and 36. The packed flag bits are `undoing`, `redoing`,
`registeredForCallback`, `postingCheckpointNotification`, and `groupsByEvent`;
the target reserves the remaining 27 bits.

The six support-class layouts are:

| Class | Instance size | Instance fields after `NSObject` |
| --- | ---: | --- |
| `_NSUndoStack` | 20 | `_max` 4, `_count` 8, `_nestingLevel` 12, `_head` 16 |
| `_NSUndoObject` | 16 | `next` 4, `previous` 8, `_target` 12 |
| `_NSUndoBeginMark` | 20 | `_groupIdentifier` 16 |
| `_NSUndoEndMark` | 16 | none |
| `_NSUndoLightInvocation` | 24 | `_selector` 16, `_arg` 20 |
| `_NSUndoInvocation` | 20 | `_invocation` 16 |

This is a direct expansion of `src/Kits/Foundation/reconstruction/abi/NSUndoManager.json`;
it records the storage contract needed to avoid changing target layout during
the pending implementation. No source code was changed in this follow-up.

## Initial source reconstruction

`src/Kits/Foundation/NSUndoManager.m` now contains implementations for the
manager, both invocation action classes, begin/end markers, the undo object
base class, and the linked undo stack. The manager implementation defines the
seven exported notification strings and follows the recorded grouping,
run-loop callback, checkpoint, registration, undo/redo, action-name, and
localized menu-title paths. The six private class ivar layouts match the ABI
table above. Manager stack selection uses the existing direction flags and
does not add a new Objective-C selector.

The manager's public methods and private manager callbacks were checked
against their IDA function bodies, including the action-name and menu
localization branches. The stack's initialization, push/pop, group-name,
removal, level-limit, bottom-trimming, target-filter, and `description` paths
were also checked. Source layout and diagnostic strings received a manual
review. A final description pass confirmed the begin/end marker string values
and both invocation action formats, and removed an extra `_NSUndoObject`
`description` implementation that had no body in the target binary. The
initializer/deallocator retain paths match the decompiled ownership operations.
The final constructor pass also aligned initialization with the target's
super-init calls and default-zero assumptions. It found and corrected a
`_beginMark` mismatch: the search starts at the current nesting level and
returns the matching outer group marker (`0x425521f4`). Constructors and
ownership bodies were checked at `_NSUndoObject initWithTarget:` (`0x42543540`),
`_NSUndoLightInvocation initWithTarget:selector:object:` (`0x425462b8`),
`_NSUndoInvocation initWithTarget:invocation:` (`0x4256e5b8`), and the related
deallocators. No build or tests were run, so runtime ownership behavior remains
unverified.

## PPC state-transition parity recheck

A cross-target read-only pass compared the current source with the attached
PPC Foundation database `738acbc1219d`. `-[NSUndoManager endUndoGrouping]`
(`0x4254da8c`) returns immediately when `_disabled` is nonzero; the i386 body
at `0x4255246c` does not have that guard. The source now preserves this
PPC-only behavior with a compile-time target guard.

The PPC `undoNestedGroup` (`0x42579f30`) and `redo` (`0x42579c54`) bodies
also copy the action-group identifier to the opposite stack only when
registration is still enabled after `beginUndoGrouping`. The corresponding
i386 paths (`0x4256d114` and `0x4256cd4c`) copy it unconditionally. The source
now makes those two copies conditional only for PPC, while retaining the
shared notification, invocation, and stack-transfer order.

The PPC stack `push:` (`0x4254c56c`), `popUndoObject` (`0x4257b3dc`),
`removeObject:` (`0x4257b5ec`), and `_removeBottom` (`0x4257b0f0`) were checked.
Their list and count transitions match the existing source. A follow-up check
of guarded diagnostics and teardown found the additional differences
recorded below.

The same pass found one more target-specific transition in
`removeAllActions` (PPC `0x4254bab4`, i386 `0x42555d74`). With an automatic
event callback pending, PPC clears `registeredForCallback` and cancels the
scheduled `_processEndOfEventNotification:` perform on the current run loop.
i386 instead leaves the callback pending and recreates the empty undo-group
begin marker. The implementation now preserves these separate target paths.
No tests or builds were run.

The stack also has a private, zero-initialized one-byte `DebugUndo` flag in
both images (i386 `0x426023fc`, PPC `0x42626318`). When set, `push:` and
`popUndoObject` log the stack and object classes and addresses, and stack
`dealloc` logs its address. The implementation now includes those guarded
messages using the target strings `%@ 0x%x pushing %@ object %@`,
`%@ 0x%x popping %@ object %@`, and `Deallocing undo stack: 0x%x`.

Both i386 `-[_NSUndoStack dealloc]` (`0x4256e7ec`) and PPC
(`0x4254aaec`) drain the list by repeatedly calling `popUndoObject` before
calling super. This autoreleases each remaining item through the pop method;
the previous source path called `removeAllObjects` and released each one
directly. The source now matches the target's pop-based teardown. The
`DebugUndo` byte is internal and non-public in both IDA databases, so it was
kept private and was not added to exported-symbol metadata. No tests or builds
were run.

## Current-tree source status recheck (2026-10-09)

The opening status above is historical and no longer describes the worktree:
`NSUndoManager.m` now contains the manager and private undo-stack classes,
including the target-specific transitions recorded in
`2026-10-08-foundation-current-gap-audit.md`. The earlier statement that the
source remained a TODO skeleton pending design approval is superseded. This
status correction made no source or ABI changes; static source/audit review
only, with no tests or builds.
