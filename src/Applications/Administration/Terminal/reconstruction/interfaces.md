# Recovered Terminal interface baseline

This document records declarations supported by reference metadata. The
Objective-C encodings use the historical 32-bit ABI. Encodings confirm types
and calling shape, but source signatures also depend on original typedefs and
class inheritance. Behavior remains unverified until task tests compare
reference observations.

## Distributed-object protocol

The app header is a 66-byte import stub. The full support header is
`C:\Users\raynorpat\Downloads\test\Applications_ppc\Developer\Headers\Apps\TerminalDOProtocol.h`.
The `TerminalDO` method table has all public DO selectors and implementations.
The header signatures and PPC method encodings agree:

| Selector | Objective-C encoding | Recovered public shape |
| --- | --- | --- |
| `protocolVersion` | `i4@4:8` | returns `int` |
| `runCommand:windowTitle:` | `v12@4:8@12@16` | `NSString *command`, `NSString *title` |
| `runCommand:windowType:windowHandle:shellType:windowTitle:returnCode:` | `v28@4:8@12i16N^i20i24@28o^i32` | command; `TSWindowType`; in/out `int *`; `TSShellType`; title; out `int *` |
| `runCommand:inputData:outputData:waitForReturn:directory:returnCode:` | `v28@4:8@12@16^@20c24@28o^i32` | command; `NSData *`; `NSData **`; `BOOL`; directory; out `int *` |
| `runCommand:inputData:outputData:errorData:waitForReturn:windowType:windowHandle:exitAction:shellType:windowTitle:directory:environment:returnCode:` | `v60@4:8@12@16^@20^@24c28i32N^i40i44i48@52@56@60o^i64` | command/data/error, wait, window, handle, exit/shell, title, directory, environment, and out return code |

The header defines `TSWindowType`: `TSWindowNone=0`, `TSWindowIdle=2`,
`TSWindowNew=4`, `TSWindowDedicated=8`; `TSShellType`: `TSShellNone=1`,
`TSShellBourne=2`, `TSShellDefault=4`, `TSShellFastC=8`; and `TSExitAction`:
`TSCloseOnExit=0`, `TSCloseUnlessError=1`, `TSDontCloseOnExit=2`. Confirm
these values against constant references and observed behavior before adopting
the header in the source.

IDA pseudocode for the full DO method shows window reuse/creation, optional
stdin data, child startup, and separate stdout/stderr capture. Its stack-variable
and structure interpretations remain unresolved; use it to guide focused
disassembly and reference cases.

## Recovered storage contracts

`Chunk.c` implements the C chunk and screen-line primitives. The PPC chunk has
a 12-byte header: 16-bit growth quantum at offset 0, 16-bit element width at 2,
32-bit allocated element count at 4, 32-bit used count at 8, then packed data.
The five-argument `ChunkMalloc` entry accepts element width, growth quantum,
initial count, requested capacity, and `NSZone *`; it rounds the capacity up to
the growth quantum and allocates in that zone. `ChunkGrow` adds whole quanta
and sets count to the requested value; `ChunkRealloc` adds one quantum;
`ChunkCompress` rounds used count to a quantum.
`ChunkAdd` appends one fixed-width element and increments count. Copy/dup preserve
raw bytes and used count. These rules follow PPC pseudocode at `0x21870` through
`0x21C54`; call sites include `Filer`, `TString`, `vt100`, and `FieldView`.
Resize and release recover the owning zone from the object pointer. The storage
tests pass a null zone for host allocation, while Terminal call sites pass their
owning object zone. `FieldView` now creates screen-line nodes and drawing chunks
in its own zone.

The standalone `_char_offset` helper at `0x5FE0` is reproduced in
`WordBoundary.c`. IDA shows it normalizes any nonzero low two bits in its first
argument to bit 1, then interprets mask values 2 through 14 as ordered
attributes with offsets 0, 1, 2, and 4. The second argument selects one or more
of those bits and the helper returns the accumulated offset. The current
reference has no direct callers, so its original call-site contract and runtime
use remain unverified.

A screen line stores a 32-bit next pointer, 8-bit absolute starting column,
8-bit attributes, 16-bit text length, and NUL-terminated bytes at offset 8. Its
PPC node header is 12 bytes. `lineCreate`, `lineFree`, `lineInsert`,
`lineTruncate`, `lineSplit`, and `lineToString` are portable C forms of
`_newNode`, `_freeLine`, `_insertNode`, `_truncateLine`, `_splitLine`, and
`_lineToString` at `0x21C58`, `0x22010`, `0x21E44`, `0x22060`, `0x22D34`, and
`0x22BA8`. `_overNode` at `0x21D34` removes fully covered following spans,
merges touching/overlapping equal-attribute spans, and trims a different-
attribute span to the first uncovered suffix. Direct tests cover gaps, full
coverage, and equal-attribute concatenation; the insertion tests cover
differing-attribute overlap. `reallocNode` matches PPC's unchecked
`NSZoneRealloc` result write and NUL terminator. `lineSplit` follows the
original four-argument contract: input list,
8-bit split column, out-left list, and out-right list. It partitions across gaps
and rebases right-side span offsets. `lineToString` returns the destination
pointer for the final copied span, matching `_lineToString`. `lineInsert` accepts
`(newSpan, existingList)` like `_insertNode`. Its gap
walk now follows the PPC comparison of incoming start against the existing span
end; overlap paths avoid unsigned prefix underflow and preserve the displaced
suffix on differing attributes. Host-side list links use native pointers;
`TerminalLine32` records the target layout explicitly. Host-side branch tests
cover the overlap normalization paths; target-zone ownership and i386 layout
still need guest validation. Allocation-failure behavior outside `reallocNode`
also remains to be compared against the PPC binary.

## Shell object layout and recovered routines

IDA's PPC `Shell` instance uses a 56-byte, 4-byte-aligned layout: the `Filer`
superclass occupies bytes 0–23 (with its `NSObject` superclass at 0–3);
`pid` is at 24, `exitAction` at 28, the
11-byte PTY name at 32–42, padding at 43, `command` at 44, `slot` at 48,
`invalidated` at 52, and tail padding at 53–55. `Shell.h` declares the recovered
fields and retains explicit padding so the host-side layout test checks the PPC
ABI.

The direct accessors at `0xB96C`–`0xB9B8` and `findslot:` at `0xB21C` are
implemented in `Shell.m`. The latter scans the system `ttyent` database in
order, compares the supplied prefix to each terminal name, and returns the
one-based entry index or `-1`. `findslot:` is marked control-flow-confirmed in
the binrecon ledger; host tests confirm the declared layout, while target
Objective-C ABI and tty database behavior still need Rhapsody-side verification.

### Shell process and lifecycle call graph

IDA names and method encodings confirm the PPC methods at `0xAD54` through
`0xB9BC`.
IDA's PPC type graph gives the exact hierarchy `Shell : Filer : NSObject`.
The `Shell` UDT names `Filer` as its 24-byte super object; the six subclass
ivars occupy offsets 24–52 as listed above. `Filer` stores its
`NSFileHandle *fileHandle` at offset 4 and callback `target` at offset 16.
`Terminal` implements `childExit:status:` at `0xCA8C`. The PPC call site sets
selector from `exitAction` and dispatches exactly two explicit object
arguments—the Shell and wait-status pointer—through
`performSelector:withObject:withObject:`. This agrees with the two-argument
method encoding. The method saves the sender from `r5`, emits its exit message,
then checks whether its window is key. In that case it locks focus, clears the
cursor, unlocks focus, and flushes the window before disabling cursor drawing
and removing dirt timers. The method-entry TOC base is anchored by its tail
`performClose:` send: `0xCA8C + 0x30000 - 0x49C8 = 0x380C4`. The first two
sender cells then resolve to `kill` (`0x3800C`) and `close` (`0x37F54`), matching
the source. This method is control-flow-confirmed after restoring the missing
key-window branch and correcting the second sender call.
`slaveMinorDevice` gets the descriptor from the inherited NSFileHandle and
returns the low byte of `st_rdev`; on `fstat` failure it invokes
`NSAssertionHandler` with `Shell.m:688` and the binary's embedded message.

`login` now builds the binary-confirmed 36-byte BSD utmp record, writes the
record at the tty's indexed slot in `/var/run/utmp`, appends it to
`/var/log/wtmp`, and brackets those privileged writes with the saved real and
effective UID transition. `logout` appends and clears the utmp entry, resets
the slot, changes the PTY device back to root and `wheel` (or `tty`) with mode
0666, and restores the saved credentials. The record layout and paths come
from the target's typed UDT and `__cstring`; verify privileged file behavior
on the target OS.

`system:login:folder:env:` now opens a PTY pair, changes slave ownership/mode,
marks the master close-on-exec, and installs it in the inherited file object.
After creating a close-on-exec error pipe, it `vfork`s. The child starts a
session, establishes the controlling terminal, drops to the configured uid/gid,
sets the recovered termios masks, applies the PTY window size, duplicates the
slave onto descriptors 0–2, validates its credentials, then sends
`broadcastSize` to the target before changing to the requested/home/root
directory and installing the optional environment. `execs0` handles login mode
and `execs` handles ordinary mode. The parent closes the slave and error-pipe
write end, records the PTY login, copies the command into the shell's zone, and
reports success only when the error pipe reaches EOF. Failed exec writes the
12-byte `Exec failed` record before the child exits with status 221. The host
stub-exec tests cover argv parsing for both helpers; PPC and i386 target syntax
checks pass. Target runtime behavior and the fallback window-size value remain
unverified.

`-[Terminal broadcastSize]` sends a four-short `TIOCSWINSZ` record to the shell
when its file descriptor is positive. The record uses `cursorx` for rows,
`height` for columns, and truncates the view bounds' pixel width and height to
16-bit values, matching the 196-byte PPC body.

`_isCommandClean` (`0x4FC8`, 324 bytes) compares the command basename, after
first accepting any leading `-`. With `allowShellCommands` false it returns
true only for an exact member of the configured null-terminated clean-command
list. When true it also accepts `su`, `su.wheel`, and `su.nowheel`, rejects
`rsh`, and accepts any basename of at most five bytes ending in `sh`. This
unusual suffix rule is retained as observed. The implementation is
`isCommandClean` in `ShellPolicy.c`; native tests cover paths, allowlist
matching, login-option acceptance, special `su`/`rsh` handling, and both sides
of the suffix-length boundary.

The PPC `FlagMap` at `0x20B5C`–`0x20EC0` uses an 8-byte wrapper containing a
bitmap pointer and a 16-bit byte capacity at offset 4. Creation allocates a
16-byte zeroed bitmap in the supplied zone; `FlagIsSet` treats each index as a
little-bit-order position and returns false outside `capacity * 8`. `SetFlag`
grows by 16 bytes while the index is within 10,000, zeroes each appended block,
then sets or clears the selected bit. The target returns the bitmap pointer for
in-range indices, but for indices above 10,000 returns the original wrapper
pointer without changing the map; that observed edge is retained. `FreeFlagMap`
frees the bitmap and wrapper with `free`. `FlagMap.c` and `tests/flagmap.c`
cover initial state, byte boundaries, growth, clearing, and the threshold. In
Objective-C compilation mode, allocation failures call
`NSAssertionHandler.handleFailureInFunction:...` with the PPC-observed function,
file, line, and messages (`Malloc flagmap` at lines 21 and 22;
`Realloc flagmap` at line 64). The native C test exercises successful
allocation paths; assertion exception behavior is not runtime-tested here.

`cmdtok`, `execs`, and `execs0` are implemented in `ShellExec.c` with their
reference-observed helper signatures. Token parsing and failed-exec argv
construction are covered by a host test that replaces `execvp`; actual process
replacement remains target-runtime verification work.

The source now reconstructs the class initializer's mutable shell array,
SIGCHLD wakeup pipe, user record, and asynchronous NSFileHandle notification.

`_main` (`0x20F50`, 720 bytes) saves the process's real/effective UIDs and
real GID before calling `become_user`, which swaps the UIDs with `setreuid`.
The main-bundle path is checked for readability; when unavailable, the
executable's containing directory becomes the working directory. If `chdir`
fails, startup displays the `No Wrapper` alert and exits successfully before
querying the process-name path; after a successful directory change, that path
is checked. Failure displays the `No Wrapper` alert and exits successfully.
Startup then creates `TerminalApp`, loads `WindowTop.tiff` with the
application as `NSOwner` in its zone only when that resource exists, sends
`finishLaunching`, and enters the AppKit event loop. `TerminalMain.m` and
`ProcessIdentity.c` implement this path.
`Shell` resolves its passwd record from the saved real UID, preserving the
identity chosen before the startup UID swap.

`TerminalApp.m` also reconstructs four PPC state accessors. `hasPrefManager`
checks the NIB outlet at instance offset `0x74`; `prefWindowVisible` and its
setter read/write the final byte at `0x7F` of the state word at `0x7C`; and
`doingForcedQuit` tests mask `0x00FFFF00` in that word. The header models the
flag word explicitly: `isPartOfASet` at `0x7C`, two reserved bytes, then
`prefVisible` at `0x7F`. The middle-byte mask selects the same bytes on both
32-bit targets. No i386 reference was available to confirm the full class
layout.
The same layout includes the `serviceProvider` outlet at `0x70` and printing
state byte at `0x79`; the getter and setter map directly to those IDA loads and
stores. The `prefManager` getter lazily creates a page-sized zone, names it
`Preferences`, and allocates the manager there, beeping and returning nil if
zone creation fails.
`setWindowStatus:withScroller:debug:setMember:` stores four byte arguments to
the observed offsets `0x78`, `0x7B`, `0x7A`, and `0x7C`; `killZone:` passes its
argument directly to `NSRecycleZone`.
`init` sets `invalidated=0`, `pid=-1`, assigns the default `exitAction`, clears
the PTY name and command, and registers the instance. `freeAll` empties that
array. `handleFileActivity:` drains signal work, unmasks signals, and rearms
the pipe notification. `invalidate` is idempotent: it calls `kill`, removes
the instance from the active array, and frees `command`; `dealloc` calls
`invalidate` before super deallocation.

`handleSignal` now drains `wait3(WNOHANG)`, searches active shells in reverse
for each reaped PID, marks the matching Shell exited, and dispatches its
`exitAction` with the Shell and status pointer. The PPC call site passes the
Shell and wait-status pointer through `performSelector:withObject:withObject:`,
matching the callback's two-object method encoding. Runtime callback delivery
still needs the original OS. `kill` and `dealloc` preserve their observed call
order. `slaveMinorDevice` and the PTY process-launch path are reconstructed;
the launch's guest runtime behavior remains unverified.

## Emulation base object

IDA's `Emulation` UDT has a 32-bit Objective-C superclass pointer followed by
`term` at offset 4 and `meta` at 8. Although the UDT places `eflags` at 10,
the PPC instructions for `setDefaults:` and `autowrapIsOn` access a flags word at
offset 12. `Emulation.h` reserves bytes 10–11 and models the flags word at 12;
PPC and i386 layout assertions confirm a 16-byte object. The defaults record
prefix aligns the two shorts at 8 and 10 and places `var9` at 12; its complete
declared layout is 88 bytes. `Emulation.m` implements `setTerminal:` and
`terminal` (`0x58C8`, `0x58D8`), `initDefaults:` and `setDefaults:` (`0x58E8`,
`0x5BF4`), the empty base `translateChars:len:` (`0x5C4C`), `autowrapIsOn`
(`0x5FBC`), and `metaCharacter` (`0x5FD0`).
`termDidResize:` (`0x5BD0`) resets `bot` and `drawCursOK` on the terminal view.
`wrapoutput` (`0x5DA0`) applies the recovered autowrap cursor transition.
`deAlternatize:` (`0x5B14`) clears the alternate modifier flag and normalizes
the event character values using `characters`, `charactersIgnoringModifiers`,
and `setChars:`.

`ctrloutput:` (`0x5C58`) dispatches control bytes through a PPC relative jump
table. The base method handles BEL, BS, HT, LF, and CR. Values 0–6 and 11–12
jump directly to the common epilogue; the source's default branch preserves
those no-op targets. VT52 and VT100 override the dispatch with their own
control semantics and sequence forwarding. `-[vt100 ctrloutput:]` (`0x185B8`)
also handles tab stops, linefeed/newline mode, keypad mode, and escape entry.

`output:len:` (`0x5E30`) is represented from IDA's recovered block flow: it
routes controls through `ctrloutput:`, batches printable runs up to the right
edge, invokes character translation before forwarding to the Terminal, wraps
when already at the edge, and delegates the remaining stream to the active
emulator when required. IDA's selector references resolve to `ctrloutput:`,
`output:len:`, `wrapoutput`, `translateChars:len:`, and `_mark:len:`. The first
four dispatch paths are represented in the current sources; screen marking is
still outside this implementation slice. The PPC entry has no terminal or input
pointer preflight before its length-controlled loop, and the source now matches. Binrecon maps the method IMP, but
source-location matching is not runtime parity.

`-[vt52 translateChars:len:]` (`0x18ED0`) is represented in the `vt52`
subclass declaration and implementation. IDA shows that its VT52 line-drawing
flag gates an in-place mapping for bytes `0x5C` through `0x66`; the eleven
replacement bytes are taken directly from the corresponding PPC stores. The
other bytes, including `0x67` through `0x7E`, are unchanged, and the method is a
no-op when the flag is clear. `setDefaults:` (`0x18FD4`) inserts defaults byte
5 bit 0 into `vt52flags` bit 6 before calling the base implementation.
`wrapoutput` (`0x19178`) decrements the terminal's row without checking the
base autowrap flag. `ctrloutput:` now handles the recovered beep, backspace,
tab, linefeed, carriage return, and escape cases and dispatches active
multi-byte sequences through their stored handler. `vt52getline:` selects
`vt52getcol:` for the second cursor-address byte, which stores the addressed
row and column and exits escape mode. `Emulation key:` (`0x5924`) follows the recovered modifier, repeat, meta, and
newline paths; its non-alternate function-key branch returns 2 when `eflags`
bit `0x40000000` is set, matching PPC instruction `0x5A20`. `vt52 key:`
(`0x188B4`) uses its recovered application/strict keypad mappings and special
key bytes. The escape dispatcher (`0x18CA8`) implements the recovered clamped
cursor moves, graphics-mode toggle, cursor home, reverse linefeed,
insert-line/line-clear calls, cursor-address prefix, and line-up handler.
`reset` (`0x19194`) clears the recovered cursor, scroll, screen, and
emulator-mode state. The `vt52Escape:` relative table sends `0x59` to the
`vt52getline:` selector at `0x384AC`, preserving escape state while awaiting the
column byte. Entry `0x5A` sends the literal `\033/Z` at `0x31EDC` through
`output:` at selector cell `0x380C8`, then takes the common escape-state cleanup
path. The provided application bundle contains only the PPC executable, so i386 ABI and
behavior parity remain unverified. `vt52`'s UDT places its private flag at
object offset 24; the header reserves the inherited bytes through offset 19,
then the writer pointer at 20 and the flag byte at 24. The target layout record
is asserted as 32 bytes on 32-bit PPC and i386.

`vt100`'s PPC UDT is 48 bytes: the 16-byte `Emulation` base, `vt52Emulator`,
`vflags`, `sx`/`sy`, `args`, `narg`, `tabs`, `text`, and `writer`. The matching
header layout is recorded and asserted. `-[vt100 key:]` (`0x16A18`) now
implements the base key dispositions, cursor/function-key sequences, keypad
application sequences, shifted keypad digits, and Enter handling from the PPC
switches and constants. `-[vt100 setDefaults:]` (`0x18524`) applies the two
recovered `var5` flag mappings, forwards defaults to the attached VT52 emulator,
then calls the base implementation. `linefeed` (`0x16674`) and `revlinefeed`
(`0x166F0`) use the recovered screen-scroll selectors and cursor bounds.
`reset` (`0x16764`) refreshes the view, restores eight-column tab stops, resets
emulator and terminal flags/cursors, and clears the recovered line range.
`vt100CSI:` (`0x17EC0`) initializes argument collection and private-mode state;
`vt100CollectArgs:` (`0x17C38`) accumulates decimal arguments and dispatches the
completed command; `vt100Private:` (`0x17A38`) applies the recovered private
set/reset modes (mode 5 is a no-op; mode 6 toggles the origin flag), including
the 80/132-column resize path; `vt100string:`
(`0x17E4C`) enters string collection; and
`vt100CollectString:` (`0x17D40`) accumulates and truncates terminated strings
as recovered. Application-keypad plus emits `ESC l`; normal plus emits `+` or
`,` based on its recovered flag. `translateChars:len:` (`0x183A4`) applies the
PPC line-drawing substitutions only under the recovered `vflags` combinations;
the case table maps the observed characters directly to their stored bytes.
`ctrloutput:` (`0x185B8`) now models the PPC C0 dispatch including tab-stop
scanning, linefeed/newline mode, keypad modes, and escape/sequence forwarding.
`vt100Escape:` (`0x18158`) handles index/next-line, setting a tab stop, reverse
index, CSI and string entry, reset, keypad modes, the device-attributes reply,
and saved cursor/style state. Its `#8` alignment test fills each screen row
with `E`; the G0/G1 selector methods implement the supported mode-bit changes
from their relative jump tables. Other `#` values are no-ops. `Emulation`'s
base `ctrloutput:` (`0x5C58`) includes BEL, BS, HT, LF, and CR; C0 values 0–6
and 11–12 jump directly to its common epilogue.
The normal CSI command handler currently reconstructs cursor movement commands
A-D, cursor positioning (`H`/`f`), scroll-region selection (`r`), tab-stop
clearing (`g`, parameters 0 and 3), line insertion/deletion (`L`/`M`), and
character deletion (`P`) from their PPC jump-table targets. `H`/`f` use
one-based arguments with a default of one, clamp the row to the screen or
origin-mode margins, and clamp the column to screen width. In `FieldView`,
`_cursory` is the row, `cursory` is the column, `cursorx` is the row capacity,
and `height` is the column capacity; CSI reads/writes these recovered fields
directly. `r` refreshes the
screen, applies the recovered default-region handling and clamps the exclusive
bottom margin to the screen height; it resets the cursor to the top margin in
origin mode and otherwise to row zero, with column zero. `L` and
`M` normalize and clamp their counts to the active scroll region. The recovered
accesses map A/B to the terminal row (`_cursory`) and C/D to the column
(`cursory`); A observes `top`, B observes `bot` and row capacity (`cursorx`),
and C observes column capacity (`height`). The `g` branch clears the current
column's tab byte for parameter 0 and zeroes the column-capacity-sized table
for parameter 3. The PPC dispatch table has no-op exits for the remaining
letters; each non-no-op command target has a corresponding source case.
`initDefaults:` (`0x16864`) constructs the companion VT52 emulator and allocates
the argument, tab, and string chunks with the recovered growth and capacity
values. `dealloc` (`0x169A0`) frees those chunks, releases the companion, and
calls superclass deallocation. `termDidResize:` (`0x16D20`) grows or resizes
the tab chunk, copies the reference's all-enabled default-tab bytes, and then
forwards resize to the base class. `wrapoutput` (`0x187C4`) follows the
autowrap flag to scroll or advance the row and reset the column; with autowrap
disabled it decrements the column. `setTerminal:` (`0x184C0`) forwards the
terminal pointer to both the base emulator and companion VT52 object. A
matching i386 reference and native compiler/runtime are still needed for
dual-architecture verification.

`-[Terminal cancelDelayedPerforms]` (`0xC2F0`) cancels pending requests on the
Terminal object for `_delayedCursor:`, `displayWindowStatus:`, and
`redisplayTitle:` through `NSRunLoop`'s cancellation API. `-[Terminal setTitle:]`
(`0xD76C`) empties the saved `TString` and sets the title option byte to `8`
only for a non-nil title other than the `Custom Title` example. The separate
`-[Terminal setCustomTitle:]` (`0xD808`) accepts a C string, converts it to an
`NSString` for the `TString`, and sets or clears option bit `0x08` according to
whether that C string is nonempty. `TerminalApp` and `TerminalDO` now call this
binary-compatible C-string interface.
`-[Terminal redisplayTitle:]` (`0xD8B0`) forwards the current column and row
capacities to `windowHook::` (`0xD9C8`), where the actual title reconstruction
and forwarding to the window are handled. `windowHook::` obtains the shell's
command and PTY, the selected custom-title display string, terminal dimensions,
file name, and the option byte at defaults offset 36. `_winTitle` (`0xF840`)
has eight arguments and combines those components in mask order: custom title
(`0x08`), compressed command (`0x01`), PTY basename (`0x02`), dimensions
(`0x04`), and compressed file name (`0x10`). It uses the original two-space,
D0, space separator. With a zero option byte it obtains the process name from
`NSProcessInfo`; when the debug flag is set it asks `NSBundle` to localize the
key `" \xD0 (Key Stealer)"` with an empty fallback and appends the resulting
string. `_pathCompress` (`0xFB9C`) takes three arguments and obtains the home
directory through `NSHomeDirectory`. The C formatter and Objective-C Foundation
bridge are in `WindowTitle.c` and `WindowTitleRuntime.m`. Host tests cover the
option composition and path compression; both target architectures pass syntax
checks for the bridge. `-[Terminal redisplayTitle:]` (`0xD8B0`) forwards the
stored terminal row and column capacities to `windowHook::`; that hook
(`0xD9C8`) updates the window title with localized `Dead Terminal` text for
failed shells, using `"\n\r[Process exited - exit code %u]"` as the fallback.
For live shells it obtains command, PTY, custom title, option bits, debugging
state, and file name before calling `winTitle`.

`-[Terminal invalidate]` (`0xC388`) runs only while inherited PostScript output
is disabled. It invalidates the FieldView, clears the window's edited marker,
stops cursor blinking and delayed performs, removes dirt timers, unregisters a
valid shell device, detaches and closes/releases the shell, releases the
emulator, and marks the terminal dead. The PPC body and inherited
`FieldView invalidate` guard establish this call order. `Terminal.m` passes
PPC and i386 target-triple syntax checks; guest runtime behavior remains open.

`-[Terminal dealloc]` (`0xC4C8`) cancels delayed performs, requests the shared
font manager's font panel, sets its panel font to the terminal's current font
with `isMultiple:NO`, and then calls superclass `dealloc`. The PPC call cells
resolve to `cancelDelayedPerforms`, `sharedFontManager`, `fontPanel:`,
`setPanelFont:isMultiple:`, and `dealloc`; the float constant is 10.0. The
font manager/panel declarations are present in the bundled AppKit headers.

`-[Terminal setDefaults:]` (`0xBF9C`) asserts that the supplied defaults
structure is the same live allocation already stored in `def`; the binary's
assertion text is `Tried to change defaults struct on the fly.` It updates the
two high event-flag bits from defaults offsets 6 and 0, saves `var17`, and sets
the window's edited marker from the process dirt monitor unless monitoring is
disabled or the shell is dead. It forwards the structure to the emulator,
releases and replaces all four text colors, three background colors, and the
cursor color using each source color's own color space, then updates FieldView
flag bits 19 and 18 and the low cursor-shape bits while preserving cursor-shape
bit 4. Finally it calls `FieldView setDefaults:` and the title hook with the
stored height and cursor column. The saved defaults fields and method order are
confirmed by the PPC decompilation; AppKit/Foundation selector behavior relies
on the bundled historical headers. Target compilation and runtime behavior
remain to be verified.

## FieldView line-slot scrolling

`TerminalScreen.c` reconstructs the line-array edits in
`-[FieldView _lscrollup:to:lines:]` (`0x1ADAC`) and
`-[FieldView _lscrolldown:to:lines:]` (`0x1B024`). Each PPC slot is eight bytes: a
32-bit line pointer and a 32-bit companion field. Up-scroll frees the first
`count` rows in `[from,to)`, shifts the remaining slots toward `from`, and
zeroes the exposed bottom slots. Down-scroll frees the last rows, shifts the
remaining slots down, and zeroes the exposed top slots. The portable host slot
uses a native pointer while `TerminalLineSlot32` records the PPC width.

Tests cover both directions, preservation of companion values during moves,
zeroing, outside-region stability, zero-count calls, and invalid ranges. The
scrollback-enabled up-scroll branch grows storage by the configured quantum,
shifts the viewport down, retains displaced rows, and moves `topline` only when
it was following the bottom. `FieldView.m` joins this storage operation to the
recovered screen-scroll and scrollback redraw selectors. The host storage test
verifies the eight-byte chunk move and exposed-row clearing; PPC runtime parity
remains unverified.

`-[FieldView _lclear:to:]` (`0x1B144`) uses a matching chunk operation to retain
the cleared visible rows in the history prefix and zero their former slots. It
dispatches the recovered scrollback screen-scroll and exposed-row redraw calls.

`-[FieldView _lscrollup:]` (`0x1C300`) applies the recovered display-mode
transition and shifts the active visible row interval, preserving displaced
rows when scrollback is enabled.

`-[FieldView _sclear:to:]` (`0x1A1D8`) clips clear notifications to the visible
scrollback range. `-[FieldView _srclear:to:]` (`0x1A9A4`) clears the clipped
display rows, redraws their stored text spans, and flushes the refresh.

## Scrollback pruning

`terminalLineBufferPruneTo` reconstructs the row-storage work in
`-[Terminal pruneNumLinesTo:]` (`0x0EB14`). Its argument is the retained line
count: it frees the removed prefix, moves the retained suffix to row zero,
clears vacated slots, sets the count to the retained value, and subtracts the
removed count from `topLine`. Slot assignment carries both the line pointer and
its 32-bit companion value. The native method now performs this compaction and
the recovered selection endpoint rule: subtract the removed count when both
endpoints are at or after the prefix; otherwise clear the selection. It disables
window flushing around the mutation, marks the content view for display, and
reflects the scroller position. PPC `__sel_backref` resolves the tail sequence
to `contentView` (cell `0x37DDC`), `setNeedsDisplay:`, `display`,
`reflectPosition`, a fresh `window`, and `enableFlushWindow`; source preserves
that order. The focused selector test checks the full tail and all calls in the
method.

Host tests cover full-prefix removal and overlapping in-place compaction, row
metadata, top-line adjustment including unsigned wrap behavior, and invalid
requests.

## VT100 reset state

`VT100State.c` reconstructs the state mutations in `-[vt100 reset]` at
`0x16764`. The binary first requests `refresh`, initializes every tab stop at
columns divisible by eight, applies the recovered masks to emulator/video/terminal
flags, resets the scroll and draw limits and both cursor rows, then clears the
terminal from row zero through the screen width. Callbacks preserve those
Objective-C message boundaries for later integration. The tab chunk must already
have capacity for the screen width, matching the binary's direct indexed writes.

The host test checks all masks, cursor/region fields, tab-stop positions, and
capacity rejection. It verifies this state helper only; the terminal callbacks
and guest ABI still need runtime comparison.

The same state module implements `-[vt100 linefeed]` (`0x16674`) and
`-[vt100 revlinefeed]` (`0x166F0`). Forward line feed scrolls one line at
`drawCursOK - 1`, otherwise increments and clamps to `height - 1`; reverse
line feed scrolls from the current row to `drawCursOK` by one line when at the
bottom margin, otherwise decrements without moving below zero. Scroll callbacks
retain the recovered Objective-C call arguments.

## Character-delete path observed in the reference

`-[vt100 _deletechar:]` (`0x16ED8`) normalizes a zero count to one, then
forwards the active row, column, and count to FieldView's `_bdelete::bytes:`
selector. That method calls `_deleteChars` (`0x221F8`), whose full 12-byte PPC
body is only a stack-frame adjustment followed by `blr`; it leaves `r3`
unchanged. `lineDeleteChars` preserves that exact no-op helper behavior, and
`FieldView _bdelete::bytes:` looks up the active visible row, applies the helper,
and writes its returned pointer back. The emulator wrapper preserves count
normalization and argument forwarding.
This documents the behavior of this binary, not a general terminal expectation.

Host tests verify the forwarded arguments and unchanged line contents.

## VT100 CSI argument collector

`VT100Args.c` is a host-testable model of the integer collector in
`-[vt100 vt100CollectArgs:]` at `0x17C38`; the production Objective-C method
remains in `vt100.m`. The argument chunk has 16-bit elements, and
`-[vt100 vt100CSI:]` resets its used count to one, clears argument zero, and
resets the dispatch index. The collector folds ASCII digits into the current
value with 16-bit wraparound. A semicolon increments used count, grows the
chunk by one allocation quantum when needed, and initializes the next value to
zero. Any other byte selects normal CSI or private dispatch according to the
private-mode flag; `vt100.m` retains the actual dispatch handlers.

The host test covers numeric accumulation, empty arguments, chunk growth,
16-bit overflow, and both dispatch outcomes. This helper is not called by the
Objective-C runtime path. The PPC IDA comparison confirms that path's state
transitions and dispatch in `vt100.m`; guest runtime behavior remains
unverified.

## VT100 CSI state bridge

`VT100Parser.c` is a host-testable model of the recovered `vt100CSI:` entry
behavior at `0x17EC0`, separate from the production method in `vt100.m`. Entry
resets the argument chunk to one zeroed 16-bit value. A leading `?` selects
private dispatch and is consumed as a mode marker; every other first byte is
fed to the normal argument collector, matching the Objective-C writer
transition. Subsequent bytes remain in the argument state until a
non-digit/non-semicolon byte is returned as a command with normal/private
dispatch selected. The model emits a dispatch event; the Objective-C path
continues into its recovered command handlers.

The host test exercises both paths across multiple input bytes, validates
argument values, and checks that dispatch closes the collection state.

## VT100 string collector

`VT100String.c` is a host-testable model of the buffer behavior in
`-[vt100 vt100CollectString:]` at `0x17D40`; the production method and its
`pasteText:` dispatch remain in `vt100.m`. PPC appends each byte, grows the
chunk when its count reaches capacity, and completes on a control byte or once
the count exceeds `0x400`. Completion overwrites the just-appended byte with
NUL, so a control terminator is excluded and the byte that crosses the limit
is discarded. For counts above `0x51`, the displayed window includes that NUL:
the returned view starts at `count - 0x51`, replaces its first three payload
bytes with periods, and has a maximum payload length of 80 bytes. The helper's
view length excludes the NUL.

Host tests cover control-byte exclusion, the display-window tail, and the
1024-byte collection boundary. They exercise the helper model; the Objective-C
state and paste dispatch are independently recovered in `vt100.m`.

## Objective-C method inventory

There are 558 unique IMP/type entries and 558 IDA method symbols. Binrecon's
static selector helper resolves 441 IMP addresses, all of which match IDA. For
117 method-list entries, the selector pointer refers outside the file-backed
sections. Their type strings and implementation addresses still match method
symbols, providing evidence for the method entry while the pointer relocation or
runtime resolution remains an open question.

| IMP | IDA method symbol | PPC type encoding | Selector state |
| --- | --- | --- | --- |
| `0x00002664` | `-[CommandPanel showPanel]` | `v4@4:8` | resolved |
| `0x000027B4` | `-[CommandPanel commandEntered:]` | `v8@4:8@12` | resolved |
| `0x000029D8` | `-[CommandPanel control:textView:doCommandBySelector:]` | `c16@4:8@12@16:20` | selector pointer outside file-backed sections |
| `0x00003A4C` | `-[DirtMonitor init]` | `@4@4:8` | selector pointer outside file-backed sections |
| `0x000040B4` | `-[DirtMonitor registerDevice:withFD:]` | `v12@4:8i12i16` | resolved |
| `0x0000429C` | `-[DirtMonitor setShellsClean:runningBackgroundClean:fastAudits:cleanCommands:]` | `v20@4:8c12c16c20^*24` | resolved |
| `0x000043B4` | `-[DirtMonitor unregisterDevice:]` | `v8@4:8i12` | resolved |
| `0x00004500` | `-[DirtMonitor releaseKnownTask:taskDied:]` | `v9@4:8^{?=IiC{?=b1b1b1}c[2I]^{_KT}^{_KT}}12c16` | resolved |
| `0x00004728` | `-[DirtMonitor uncacheThreads:]` | `v8@4:8^{?=IiC{?=b1b1b1}c[2I]^{_KT}^{_KT}}12` | resolved |
| `0x00004848` | `-[DirtMonitor isDeviceDirty:]` | `c8@4:8i12` | resolved |
| `0x0000510C` | `-[DirtMonitor getProcNames:onDevice:howMany:]` | `@16@4:8^[17c]12i16^i20` | resolved |
| `0x000054D4` | `-[DirtMonitor compactFreePortStack]` | `v4@4:8` | resolved |
| `0x00005544` | `-[DirtMonitor extendFreePortStack]` | `v4@4:8` | resolved |
| `0x00005720` | `-[DirtMonitor handleMachMessage:]` | `v8@4:8^v12` | selector pointer outside file-backed sections |
| `0x000058C8` | `-[Emulation setTerminal:]` | `v8@4:8@12` | resolved |
| `0x000058D8` | `-[Emulation terminal]` | `@4@4:8` | resolved |
| `0x000058E8` | `-[Emulation initDefaults:]` | `@8@4:8^{?=cccccccSSc*@fIIC@ii[8@]i}12` | resolved |
| `0x00005924` | `-[Emulation key:]` | `i8@4:8@12` | resolved |
| `0x00005B14` | `-[Emulation deAlternatize:]` | `v8@4:8@12` | resolved |
| `0x00005BD0` | `-[Emulation termDidResize:]` | `v8@4:8@12` | resolved |
| `0x00005BF4` | `-[Emulation setDefaults:]` | `v8@4:8^{?=cccccccSSc*@fIIC@ii[8@]i}12` | resolved |
| `0x00005C4C` | `-[Emulation translateChars:len:]` | `v12@4:8*12I16` | resolved |
| `0x00005C58` | `-[Emulation ctrloutput:]` | `v5@4:8C12` | resolved |
| `0x00005DA0` | `-[Emulation wrapoutput]` | `v4@4:8` | resolved |
| `0x00005E30` | `-[Emulation output:len:]` | `v12@4:8r*12I16` | resolved |
| `0x00005FBC` | `-[Emulation autowrapIsOn]` | `c4@4:8` | resolved |
| `0x00005FD0` | `-[Emulation metaCharacter]` | `s4@4:8` | resolved |
| `0x00006118` | `+[FieldPrint fieldPrint:]` | `v8@4:8@12` | resolved |
| `0x00006538` | `-[FieldPrint isFlipped]` | `c4@4:8` | selector pointer outside file-backed sections |
| `0x00006548` | `-[FieldPrint print:]` | `v8@4:8@12` | selector pointer outside file-backed sections |
| `0x000065E8` | `-[FieldPrint adjustPageHeightNew:top:bottom:limit:]` | `v24@4:8^f12f12f20f28` | selector pointer outside file-backed sections |
| `0x0000669C` | `-[FieldPrint drawRect:]` | `v20@4:8{?={?=ff}{?=ff}}12` | selector pointer outside file-backed sections |
| `0x00006C90` | `-[FieldPrint rangePicked:]` | `v8@4:8@12` | resolved |
| `0x00006E94` | `-[FieldPrint attributesPicked:]` | `v8@4:8@12` | resolved |
| `0x00007610` | `-[FieldView initWithFrame:]` | `@20@4:8{?={?=ff}{?=ff}}12` | selector pointer outside file-backed sections |
| `0x000078B8` | `-[FieldView isFlipped]` | `c4@4:8` | selector pointer outside file-backed sections |
| `0x000078C8` | `-[FieldView setDrawCursOK:]` | `v5@4:8c12` | resolved |
| `0x000078D8` | `-[FieldView drawCursOK]` | `c4@4:8` | resolved |
| `0x000078EC` | `-[FieldView setDrawsLineAtRightEdge:]` | `v5@4:8c12` | resolved |
| `0x000078FC` | `-[FieldView drawsLineAtRightEdge]` | `c4@4:8` | resolved |
| `0x00007910` | `-[FieldView setUpWithDefaults:]` | `v8@4:8^{?=cccccccSSc*@fIIC@ii[8@]i}12` | resolved |
| `0x00007B44` | `-[FieldView invalidate]` | `v4@4:8` | selector pointer outside file-backed sections |
| `0x00007BA4` | `-[FieldView dealloc]` | `v4@4:8` | selector pointer outside file-backed sections |
| `0x00007C00` | `-[FieldView setUpGState]` | `v4@4:8` | selector pointer outside file-backed sections |
| `0x00007C74` | `-[FieldView resetCursorRects]` | `v4@4:8` | selector pointer outside file-backed sections |
| `0x00007CE0` | `-[FieldView windowHook::]` | `v12@4:8I12I16` | resolved |
| `0x00007CEC` | `-[FieldView setFrameSize:]` | `v12@4:8{?=ff}12` | selector pointer outside file-backed sections |
| `0x000083E8` | `-[FieldView sizeEmulationTo::]` | `v12@4:8I12I16` | resolved |
| `0x000085C8` | `-[FieldView width]` | `I4@4:8` | selector pointer outside file-backed sections |
| `0x000085D8` | `-[FieldView height]` | `I4@4:8` | selector pointer outside file-backed sections |
| `0x000085E8` | `-[FieldView windowWillResize:toSize:]` | `{?=ff}20@8:12@16{?=ff}20` | selector pointer outside file-backed sections |
| `0x0000898C` | `-[FieldView setupFont:]` | `v8@4:8@12` | resolved |
| `0x00008BB0` | `-[FieldView copyFont:]` | `v8@4:8@12` | selector pointer outside file-backed sections |
| `0x00008D20` | `-[FieldView pasteFont:]` | `v8@4:8@12` | selector pointer outside file-backed sections |
| `0x00009014` | `-[FieldView changeFont:]` | `v8@4:8@12` | selector pointer outside file-backed sections |
| `0x000091D4` | `-[FieldView windowDidBecomeMain:]` | `v8@4:8@12` | resolved |
| `0x00009228` | `-[FieldView setDelegate:]` | `v8@4:8@12` | method IMP/type match IDA; PPC `__sel_backref` confirms guarded `autorelease`, ivar store, and `retain` sends |
| `0x00009284` | `-[FieldView delegate]` | `@4@4:8` | selector pointer outside file-backed sections |
| `0x00009294` | `-[FieldView setDefaults:]` | `v8@4:8^{?=cccccccSSc*@fIIC@ii[8@]i}12` | resolved |
| `0x00009578` | `-[FieldView removeScroller]` | `v4@4:8` | resolved |
| `0x000097B4` | `-[FieldView reinstateScroller]` | `v4@4:8` | resolved |
| `0x000099BC` | `-[FieldView print:]` | `v8@4:8@12` | selector pointer outside file-backed sections |
| `0x000099FC` | `-[FieldView emulator]` | `@4@4:8` | resolved |
| `0x00009A60` | `-[FieldView recordDefaultsChanges]` | `v4@4:8` | resolved |
| `0x00009BF0` | `-[FieldView defaults]` | `^{?=cccccccSSc*@fIIC@ii[8@]i}4@4:8` | resolved |
| `0x00009C50` | `-[FieldView disablePSOutput]` | `v4@4:8` | resolved |
| `0x00009C64` | `-[FieldView enablePSOutput]` | `v4@4:8` | resolved |
| `0x00009C78` | `-[Filer handleFileActivity:]` | `v8@4:8@12` | resolved |
| `0x00009D38` | `-[Filer init]` | `@4@4:8` | selector pointer outside file-backed sections |
| `0x00009DC8` | `-[Filer close]` | `v4@4:8` | selector pointer outside file-backed sections |
| `0x00009E8C` | `-[Filer dealloc]` | `v4@4:8` | selector pointer outside file-backed sections |
| `0x00009EF0` | `-[Filer setTarget:]` | `v8@4:8@12` | selector pointer outside file-backed sections |
| `0x00009F00` | `-[Filer target]` | `@4@4:8` | selector pointer outside file-backed sections |
| `0x00009F10` | `-[Filer setFd:]` | `v8@4:8i12` | resolved |
| `0x0000A020` | `-[Filer fd]` | `i4@4:8` | resolved |
| `0x0000A0F0` | `-[Filer handleOutput:]` | `v8@4:8@12` | resolved |
| `0x0000A2C8` | `-[Filer output:len:]` | `v12@4:8r*12I16` | resolved |
| `0x0000A360` | `-[Filer output:]` | `v8@4:8r*12` | resolved |
| `0x0000A3B0` | `-[Filer outputChar:]` | `v5@4:8C12` | resolved |
| `0x0000A3F0` | `+[FindPanel alloc]` | `@4@4:8` | selector pointer outside file-backed sections |
| `0x0000A480` | `-[FindPanel findPanel]` | `@4@4:8` | resolved |
| `0x0000A558` | `-[FindPanel findPanel:]` | `v8@4:8@12` | resolved |
| `0x0000A624` | `-[FindPanel enterSelection:]` | `v8@4:8@12` | resolved |
| `0x0000A794` | `-[FindPanel doFind:findBackwards:]` | `v9@4:8@12c16` | resolved |
| `0x0000AAB8` | `-[FindPanel findNext:]` | `v8@4:8@12` | selector pointer outside file-backed sections |
| `0x0000AAF0` | `-[FindPanel findPrevious:]` | `v8@4:8@12` | resolved |
| `0x0000AB28` | `-[FindPanel importFindText:]` | `c8@4:8@12` | resolved |
| `0x0000AC50` | `-[FindPanel exportFindText:]` | `c8@4:8@12` | resolved |
| `0x0000AD54` | `+[Shell handleSignal]` | `v4@4:8` | resolved |
| `0x0000AE5C` | `+[Shell handleFileActivity:]` | `v8@4:8@12` | resolved |
| `0x0000AEE8` | `+[Shell initialize]` | `v4@4:8` | selector pointer outside file-backed sections |
| `0x0000B00C` | `+[Shell freeAll]` | `v4@4:8` | resolved |
| `0x0000B048` | `-[Shell init]` | `@4@4:8` | selector pointer outside file-backed sections |
| `0x0000B0DC` | `-[Shell kill]` | `v4@4:8` | resolved |
| `0x0000B154` | `-[Shell invalidate]` | `v4@4:8` | selector pointer outside file-backed sections |
| `0x0000B1C0` | `-[Shell dealloc]` | `v4@4:8` | selector pointer outside file-backed sections |
| `0x0000B21C` | `-[Shell findslot:]` | `i8@4:8*12` | resolved |
| `0x0000B298` | `-[Shell login]` | `v4@4:8` | resolved |
| `0x0000B3D8` | `-[Shell logout]` | `v4@4:8` | resolved |
| `0x0000B558` | `-[Shell system:login:folder:env:]` | `c20@4:8r*12c16r*20^*24` | resolved |
| `0x0000B96C` | `-[Shell setExitAction:]` | `v8@4:8:12` | resolved |
| `0x0000B97C` | `-[Shell exitAction]` | `:4@4:8` | resolved |
| `0x0000B98C` | `-[Shell pid]` | `i4@4:8` | resolved |
| `0x0000B99C` | `-[Shell pty]` | `r*4@4:8` | resolved |
| `0x0000B9AC` | `-[Shell command]` | `r*4@4:8` | resolved |
| `0x0000B9BC` | `-[Shell slaveMinorDevice]` | `i4@4:8` | resolved |
| `0x0000BA84` | `-[Terminal setUpWithDefaults:inFolder:env:]` | `c16@4:8^{?=cccccccSSc*@fIIC@ii[8@]i}12r*16^*20` | resolved |
| `0x0000BE38` | `-[Terminal fileName]` | `r*4@4:8` | selector pointer outside file-backed sections |
| `0x0000BE48` | `-[Terminal sharesFile]` | `c4@4:8` | resolved |
| `0x0000BE5C` | `-[Terminal setFileName:sharesFile:]` | `v9@4:8r*12c16` | resolved |
| `0x0000BF9C` | `-[Terminal setDefaults:]` | `v8@4:8^{?=cccccccSSc*@fIIC@ii[8@]i}12` | resolved |
| `0x0000C2E0` | `-[Terminal shell]` | `@4@4:8` | resolved |
| `0x0000C2F0` | `-[Terminal cancelDelayedPerforms]` | `v4@4:8` | resolved |
| `0x0000C388` | `-[Terminal invalidate]` | `v4@4:8` | selector pointer outside file-backed sections |
| `0x0000C4C8` | `-[Terminal dealloc]` | `v4@4:8` | selector pointer outside file-backed sections |
| `0x0000C570` | `-[Terminal setEmulator:]` | `v8@4:8@12` | resolved |
| `0x0000C580` | `-[Terminal outputdata:len:]` | `@12@4:8*12I16` | resolved |
| `0x0000C888` | `-[Terminal scheduleUpdate]` | `@4@4:8` | resolved |
| `0x0000CA30` | `-[Terminal shellDevice]` | `i4@4:8` | resolved |
| `0x0000CA40` | `-[Terminal endOfFileOn:]` | `v8@4:8@12` | resolved |
| `0x0000CA8C` | `-[Terminal childExit:status:]` | `v12@4:8@12@16` | resolved |
| `0x0000CE34` | `-[Terminal removeDirtTimers]` | `v4@4:8` | resolved |
| `0x0000CEC0` | `-[Terminal output:]` | `v8@4:8r*12` | resolved |
| `0x0000CEF8` | `-[Terminal output:len:]` | `v12@4:8r*12I16` | resolved |
| `0x0000CF30` | `-[Terminal outputChar:]` | `v5@4:8C12` | resolved |
| `0x0000CF68` | `-[Terminal broadcastSize]` | `v4@4:8` | resolved |
| `0x0000D02C` | `-[Terminal setFrameSize:]` | `v12@4:8{?=ff}12` | selector pointer outside file-backed sections |
| `0x0000D12C` | `-[Terminal keyDown:]` | `v8@4:8@12` | selector pointer outside file-backed sections |
| `0x0000D424` | `-[Terminal acceptsFirstResponder]` | `c4@4:8` | selector pointer outside file-backed sections |
| `0x0000D434` | `-[Terminal paste:]` | `v8@4:8@12` | selector pointer outside file-backed sections |
| `0x0000D69C` | `-[Terminal pasteText:]` | `v8@4:8*12` | resolved |
| `0x0000D72C` | `-[Terminal serviceOwner]` | `I4@4:8` | resolved |
| `0x0000D73C` | `-[Terminal setServiceOwner:]` | `v8@4:8I12` | resolved |
| `0x0000D74C` | `-[Terminal DOwinHandle]` | `i4@4:8` | resolved |
| `0x0000D75C` | `-[Terminal setDOwinHandle:]` | `v8@4:8i12` | resolved |
| `0x0000D76C` | `-[Terminal setTitle:]` | `v8@4:8@12` | selector pointer outside file-backed sections |
| `0x0000D808` | `-[Terminal setCustomTitle:]` | `v8@4:8*12` | resolved |
| `0x0000D8B0` | `-[Terminal redisplayTitle:]` | `v8@4:8@12` | resolved |
| `0x0000D8F0` | `-[Terminal windowWillResize:toSize:]` | `{?=ff}20@8:12@16{?=ff}20` | selector pointer outside file-backed sections |
| `0x0000D9C8` | `-[Terminal windowHook::]` | `v12@4:8I12I16` | resolved |
| `0x0000DB0C` | `-[Terminal handleCursorBlinkTimer:]` | `v8@4:8@12` | resolved |
| `0x0000DC30` | `-[Terminal cursorBlink:]` | `v5@4:8c12` | resolved |
| `0x0000DD18` | `-[Terminal windowDidResignKey:]` | `v8@4:8@12` | selector pointer outside file-backed sections |
| `0x0000DE20` | `-[Terminal windowDidBecomeKey:]` | `v8@4:8@12` | selector pointer outside file-backed sections |
| `0x0000DF50` | `-[Terminal windowDidBecomeMain:]` | `v8@4:8@12` | resolved |
| `0x0000DFF4` | `-[Terminal windowDidResignMain:]` | `v8@4:8@12` | resolved |
| `0x0000E06C` | `-[Terminal debugToggle:]` | `v8@4:8@12` | resolved |
| `0x0000E1E8` | `-[Terminal mouseEntered:]` | `v8@4:8@12` | selector pointer outside file-backed sections |
| `0x0000E280` | `-[Terminal mouseExited:]` | `v8@4:8@12` | selector pointer outside file-backed sections |
| `0x0000E2DC` | `-[Terminal emulator]` | `@4@4:8` | resolved |
| `0x0000E2EC` | `-[Terminal windowWillMiniaturize:]` | `v8@4:8@12` | resolved |
| `0x0000E348` | `-[Terminal windowDidDeminiaturize:]` | `v8@4:8@12` | resolved |
| `0x0000E3E8` | `-[Terminal windowShouldClose:]` | `c8@4:8@12` | selector pointer outside file-backed sections |
| `0x0000E918` | `-[Terminal updateDirtIfNeeded]` | `v4@4:8` | resolved |
| `0x0000EA10` | `-[Terminal defaults]` | `^{?=cccccccSSc*@fIIC@ii[8@]i}4@4:8` | resolved |
| `0x0000EA20` | `-[Terminal window]` | `@4@4:8` | selector pointer outside file-backed sections |
| `0x0000EA30` | `-[Terminal getExtraWinInfo:]` | `v8@4:8^{?=ffc}12` | resolved |
| `0x0000EB14` | `-[Terminal pruneNumLinesTo:]` | `v8@4:8i12` | resolved |
| `0x0000ED08` | `-[Terminal draggingEntered:]` | `I8@4:8@12` | selector pointer outside file-backed sections |
| `0x0000ED44` | `-[Terminal draggingUpdated:]` | `I8@4:8@12` | selector pointer outside file-backed sections |
| `0x0000ED78` | `-[Terminal prepareForDragOperation:]` | `c8@4:8@12` | selector pointer outside file-backed sections |
| `0x0000EECC` | `-[Terminal performDragOperation:]` | `c8@4:8@12` | selector pointer outside file-backed sections |
| `0x0000F174` | `-[Terminal isDead]` | `c4@4:8` | resolved |
| `0x0000F188` | `-[Terminal setSpringLoadedPaste:]` | `v8@4:8r*12` | resolved |
| `0x0000F240` | `-[Terminal _acceptColor:atPoint:]` | `v12@4:8@12^{?=ff}16` | resolved |
| `0x0000F458` | `-[Terminal displayWindowStatus:]` | `v8@4:8@12` | resolved |
| `0x0000F5E8` | `-[Terminal updateWindowStatus]` | `v4@4:8` | resolved |
| `0x0000F67C` | `-[Terminal handleDirtTimer:]` | `v8@4:8@12` | resolved |
| `0x0000FCD8` | `-[TerminalAgent initDefaults:inFolder:env:]` | `@16@4:8^{?=cccccccSSc*@fIIC@ii[8@]i}12r*16^*20` | resolved |
| `0x00010100` | `-[TerminalAgent setTerminal:]` | `v8@4:8@12` | resolved |
| `0x00010110` | `-[TerminalAgent terminal]` | `@4@4:8` | resolved |
| `0x0001014C` | `+[TerminalApp initialize]` | `v4@4:8` | selector pointer outside file-backed sections |
| `0x00010250` | `-[TerminalApp _newInstance]` | `@4@4:8` | resolved |
| `0x0001029C` | `+[TerminalApp sharedApplication]` | `@4@4:8` | selector pointer outside file-backed sections |
| `0x000102FC` | `-[TerminalApp new:]` | `v8@4:8@12` | resolved |
| `0x00010334` | `-[TerminalApp newShell:]` | `@8@4:8r*12` | resolved |
| `0x00010370` | `-[TerminalApp newShell:env:]` | `@12@4:8r*12@16` | resolved |
| `0x000103AC` | `-[TerminalApp newShell:inFolder:env:]` | `@16@4:8r*12r*16@20` | resolved |
| `0x00010620` | `-[TerminalApp runCommand:usingShell:inFolder:windowTitle:closeOnExit:]` | `i24@4:8*12*16*20*24i28` | resolved |
| `0x00010724` | `-[TerminalApp msgPaste:]` | `i8@4:8^i12` | selector pointer outside file-backed sections |
| `0x000107B4` | `-[TerminalApp setupDefaults]` | `c4@4:8` | resolved |
| `0x00010A60` | `-[TerminalApp applicationWillFinishLaunching:]` | `v8@4:8@12` | resolved |
| `0x00010DE0` | `-[TerminalApp DOServicesOK]` | `c4@4:8` | resolved |
| `0x00010E60` | `-[TerminalApp applicationDidFinishLaunching:]` | `v8@4:8@12` | resolved |
| `0x00011400` | `-[TerminalApp doStartupAction]` | `v4@4:8` | resolved |
| `0x000114F8` | `-[TerminalApp applicationDidUnhide:]` | `v8@4:8@12` | resolved |
| `0x00011634` | `-[TerminalApp preferences:]` | `v8@4:8@12` | resolved |
| `0x0001176C` | `-[TerminalApp prefWindowVisible]` | `c4@4:8` | resolved |
| `0x00011780` | `-[TerminalApp setPrefWindowVisible:]` | `v5@4:8c12` | resolved |
| `0x00011790` | `-[TerminalApp prefManager]` | `@4@4:8` | resolved |
| `0x00011830` | `-[TerminalApp hasPrefManager]` | `c4@4:8` | resolved |
| `0x00011848` | `-[TerminalApp info:]` | `v8@4:8@12` | resolved |
| `0x0001199C` | `-[TerminalApp applicationShouldTerminate:]` | `c8@4:8@12` | selector pointer outside file-backed sections |
| `0x000120E4` | `-[TerminalApp recalculateDirtyWindows]` | `v4@4:8` | resolved |
| `0x0001225C` | `-[TerminalApp doingForcedQuit]` | `c4@4:8` | resolved |
| `0x00012278` | `-[TerminalApp validateMenuItem:]` | `c8@4:8@12` | selector pointer outside file-backed sections |
| `0x00012544` | `-[TerminalApp setWindowStatus:withScroller:debug:setMember:]` | `v17@4:8c12c16c20c24` | resolved |
| `0x00012560` | `-[TerminalApp print:]` | `v8@4:8@12` | selector pointer outside file-backed sections |
| `0x00012610` | `-[TerminalApp showServiceManager:]` | `v8@4:8@12` | resolved |
| `0x000126BC` | `-[TerminalApp serviceCache]` | `@4@4:8` | resolved |
| `0x00012740` | `-[TerminalApp lazyDestroyZone:wait:]` | `@8@4:8^{?=}12f12` | resolved |
| `0x0001281C` | `-[TerminalApp killZone:]` | `v8@4:8^{?=}12` | resolved |
| `0x00012840` | `-[TerminalApp dirtMonitor]` | `@4@4:8` | resolved |
| `0x00012930` | `-[TerminalApp cleanCommands]` | `r^*4@4:8` | resolved |
| `0x00012AB4` | `-[TerminalApp save:]` | `v8@4:8@12` | resolved |
| `0x00012AF4` | `-[TerminalApp saveAs:]` | `v8@4:8@12` | resolved |
| `0x00012B34` | `-[TerminalApp save:mustPrompt:howMany:inFile:]` | `c20@4:8@12c16i20r*24` | resolved |
| `0x000133F4` | `-[TerminalApp makePanelGoToLibrary:]` | `v8@4:8@12` | resolved |
| `0x000134F0` | `-[TerminalApp open:]` | `v8@4:8@12` | selector pointer outside file-backed sections |
| `0x0001360C` | `-[TerminalApp openFile:]` | `c8@4:8@12` | selector pointer outside file-backed sections |
| `0x00013BD4` | `-[TerminalApp monStart:]` | `v8@4:8@12` | resolved |
| `0x00013BE0` | `-[TerminalApp monStop:]` | `v8@4:8@12` | resolved |
| `0x00013BEC` | `-[TerminalApp application:openTempFile:]` | `c12@4:8@12@16` | selector pointer outside file-backed sections |
| `0x00013C24` | `-[TerminalApp application:openFile:]` | `c12@4:8@12@16` | selector pointer outside file-backed sections |
| `0x00013E0C` | `-[TerminalApp openServicesFile:]` | `c8@4:8@12` | resolved |
| `0x00014470` | `-[TerminalApp updateLibraryMenu]` | `v4@4:8` | resolved; body source-mapped |
| `0x000146C4` | `-[TerminalApp openLibraryTerm:]` | `c8@4:8@12` | resolved |
| `0x00014740` | `-[TerminalApp maybeUpdateLibraryMenu]` | `v4@4:8` | resolved |
| `0x000147EC` | `-[TerminalApp quickTitle:]` | `v8@4:8@12` | resolved |
| `0x00014A28` | `-[TerminalApp quickTitleOK:]` | `v8@4:8@12` | resolved |
| `0x00014A80` | `-[TerminalApp quickTitleCancel:]` | `v8@4:8@12` | resolved |
| `0x00014AD8` | `-[TerminalApp newCommand:]` | `v8@4:8@12` | resolved |
| `0x00014B48` | `-[TerminalApp serviceProvider]` | `@4@4:8` | resolved |
| `0x00014B58` | `-[TerminalApp fontManager:willIncludeFont:]` | `c12@4:8@12@16` | selector pointer outside file-backed sections |
| `0x00014BF0` | `-[TerminalApp shell]` | `r*4@4:8` | resolved |
| `0x00014C9C` | `-[TerminalApp setPerformingPrint:]` | `v5@4:8c12` | resolved |
| `0x00014CAC` | `-[TerminalApp applicationDidBecomeActive:]` | `v8@4:8@12` | selector pointer outside file-backed sections |
| `0x00014D04` | `-[TerminalApp displayAppStatus:]` | `v8@4:8@12` | resolved |
| `0x00014D74` | `-[TerminalApp resetAppStatus]` | `v4@4:8` | resolved |
| `0x00014DBC` | `-[TerminalApp updateAppStatus]` | `v4@4:8` | resolved |
| `0x00015040` | `-[TerminalApp activateNext:forward:includeMini:]` | `v13@4:8@12c16c20` | resolved |
| `0x00015238` | `-[TerminalDO init]` | `@4@4:8` | selector pointer outside file-backed sections |
| `0x00015650` | `-[TerminalDO protocolVersion]` | `i4@4:8` | resolved |
| `0x00015664` | `-[TerminalDO runCommand:windowTitle:]` | `v12@4:8@12@16` | resolved |
| `0x000156D8` | `-[TerminalDO runCommand:windowType:windowHandle:shellType:windowTitle:returnCode:]` | `v28@4:8@12i16N^i20i24@28o^i32` | resolved |
| `0x00015748` | `-[TerminalDO runCommand:inputData:outputData:waitForReturn:directory:returnCode:]` | `v28@4:8@12@16^@20c24@28o^i32` | resolved |
| `0x000157B8` | `-[TerminalDO runCommand:inputData:outputData:errorData:waitForReturn:windowType:windowHandle:exitAction:shellType:windowTitle:directory:environment:returnCode:]` | `v60@4:8@12@16^@20^@24c28i32N^i40i44i48@52@56@60o^i64` | resolved |
| `0x00016470` | `-[TString _createIfNecessary]` | `@4@4:8` | resolved |
| `0x000164E8` | `-[TString stringValue]` | `@4@4:8` | selector pointer outside file-backed sections |
| `0x00016544` | `-[TString setStringValue:]` | `v8@4:8@12` | selector pointer outside file-backed sections |
| `0x000165E0` | `-[TString empty]` | `v4@4:8` | selector pointer outside file-backed sections |
| `0x00016618` | `-[TString dealloc]` | `v4@4:8` | selector pointer outside file-backed sections |
| `0x00016674` | `-[vt100 linefeed]` | `v4@4:8` | resolved |
| `0x000166F0` | `-[vt100 revlinefeed]` | `v4@4:8` | resolved |
| `0x00016764` | `-[vt100 reset]` | `v4@4:8` | selector pointer outside file-backed sections |
| `0x00016864` | `-[vt100 initDefaults:]` | `@8@4:8^{?=cccccccSSc*@fIIC@ii[8@]i}12` | resolved |
| `0x000169A0` | `-[vt100 dealloc]` | `v4@4:8` | selector pointer outside file-backed sections |
| `0x00016A18` | `-[vt100 key:]` | `i8@4:8@12` | resolved |
| `0x00016D20` | `-[vt100 termDidResize:]` | `v8@4:8@12` | resolved |
| `0x00016DC8` | `-[vt100 _insertline:]` | `v8@4:8I12` | resolved |
| `0x00016E50` | `-[vt100 _deleteline:]` | `v8@4:8I12` | resolved |
| `0x00016ED8` | `-[vt100 _deletechar:]` | `v8@4:8I12` | resolved |
| `0x00016F2C` | `-[vt100 vt100DoCSI:]` | `v5@4:8C12` | resolved |
| `0x00017A38` | `-[vt100 vt100Private:]` | `v5@4:8C12` | resolved |
| `0x00017C38` | `-[vt100 vt100CollectArgs:]` | `v5@4:8C12` | resolved |
| `0x00017D40` | `-[vt100 vt100CollectString:]` | `@5@4:8C12` | resolved |
| `0x00017E4C` | `-[vt100 vt100string:]` | `@5@4:8C12` | resolved |
| `0x00017EC0` | `-[vt100 vt100CSI:]` | `v5@4:8C12` | resolved |
| `0x00017F48` | `-[vt100 vt100CharsetG0:]` | `v5@4:8C12` | resolved |
| `0x00017FC8` | `-[vt100 vt100CharsetG1:]` | `v5@4:8C12` | resolved |
| `0x00018048` | `-[vt100 vt100Hash:]` | `v5@4:8C12` | resolved |
| `0x00018158` | `-[vt100 vt100Escape:]` | `v5@4:8C12` | resolved |
| `0x000183A4` | `-[vt100 translateChars:len:]` | `v12@4:8*12I16` | resolved |
| `0x000184C0` | `-[vt100 setTerminal:]` | `v8@4:8@12` | resolved |
| `0x00018524` | `-[vt100 setDefaults:]` | `v8@4:8^{?=cccccccSSc*@fIIC@ii[8@]i}12` | resolved |
| `0x000185B8` | `-[vt100 ctrloutput:]` | `v5@4:8C12` | resolved |
| `0x000187C4` | `-[vt100 wrapoutput]` | `v4@4:8` | resolved |
| `0x00018878` | `-[vt52 initDefaults:]` | `@8@4:8^{?=cccccccSSc*@fIIC@ii[8@]i}12` | resolved |
| `0x000188B4` | `-[vt52 key:]` | `i8@4:8@12` | resolved |
| `0x00018C34` | `-[vt52 vt52getcol:]` | `@5@4:8c12` | resolved |
| `0x00018C68` | `-[vt52 vt52getline:]` | `@5@4:8c12` | resolved |
| `0x00018CA8` | `-[vt52 vt52Escape:]` | `@5@4:8C12` | resolved |
| `0x00018EC0` | `-[vt52 vt100Emulator:]` | `v8@4:8@12` | resolved |
| `0x00018ED0` | `-[vt52 translateChars:len:]` | `v12@4:8*12I16` | resolved |
| `0x00018FD4` | `-[vt52 setDefaults:]` | `v8@4:8^{?=cccccccSSc*@fIIC@ii[8@]i}12` | resolved |
| `0x00019034` | `-[vt52 ctrloutput:]` | `v5@4:8C12` | resolved |
| `0x00019178` | `-[vt52 wrapoutput]` | `v4@4:8` | resolved |
| `0x00019194` | `-[vt52 reset]` | `v4@4:8` | selector pointer outside file-backed sections |
| `0x00019230` | `+[MutableEvent mutableEventWithEvent:]` | `@8@4:8@12` | resolved |
| `0x00019378` | `-[MutableEvent setChar:]` | `v5@4:8c12` | resolved |
| `0x000193F0` | `-[MutableEvent setChars:]` | `v8@4:8@12` | resolved |
| `0x0001944C` | `-[MutableEvent setKeyCode:]` | `v8@4:8I12` | resolved |
| `0x0001945C` | `-[MutableEvent setModifierFlags:]` | `v8@4:8I12` | resolved |
| `0x0001946C` | `-[MutableEvent charValue]` | `c4@4:8` | resolved |

`-[TerminalApp recalculateDirtyWindows]` (`0x120E4`, encoding `v4@4:8`) walks
`[NSApp windows]` in order and processes only windows whose delegate passes
`isKindOfClass:[Terminal class]`. For each such window it queries
`_theDefaultsObject` with `boolForKey:@"MonitorProcs"`; disabled monitoring or
`-[Terminal isDead]` clears the window's edited flag. Otherwise it obtains the
application delegate's DirtMonitor, asks `isDeviceDirty:` for the Terminal's
`shellDevice`, and stores that result with `setDocumentEdited:`. The PPC
selector cells that are external to the executable are resolved by the call
shapes and corroborating Terminal/DirtMonitor interfaces. This method is now
implemented in `TerminalApp.m` and source-mapped at line 419; guest behavior
remains unverified.

`-[TerminalApp print:]` (`0x12560`, encoding `v8@4:8@12`) obtains the main
window from `NSApp`, reads its delegate, and checks that the delegate is a
`Terminal` before forwarding the original sender through `print:`; otherwise it
beeps. The PPC call sequence, `NSApplication`/`NSWindow` declarations, and
`Terminal : FieldView` implementation establish the receiver and selector
chain. `FieldView print:` then calls `FieldPrint fieldPrint:`. The method is
implemented in `TerminalApp.m`; no guest printing observation has been run.

`MutableEvent` is a Terminal-owned subclass of `NSEvent`. The DR2 AppKit
`NSEvent.h` layout declares `_data.key.keyCode` as an unsigned short and
`_modifierFlags` as an unsigned int. Its PPC setters at `0x1944C` and `0x1945C`
are direct stores to those inherited ivars; the implementation preserves the
16-bit key-code truncation and 32-bit modifier flags. `MutableEvent.m` and
`MutableEvent.h` are included in both Terminal project source manifests.

`+[MutableEvent mutableEventWithEvent:]` (`0x19230`) reads the source event's
type, location, modifier flags, timestamp, window number, context, characters,
characters ignoring modifiers, repeat flag, and key code, then forwards them
in that order to the inherited `keyEventWithType:location:modifierFlags:timestamp:windowNumber:context:characters:charactersIgnoringModifiers:isARepeat:keyCode:` class factory. The PPC string table and `NSEvent.h` confirm these selectors and types; the `NSPoint` location and double timestamp are passed using the target ABI's aggregate and floating-point argument paths.

`setChar:` (`0x19378`) releases the old key string, creates a new string from
the one-byte argument with `allocWithZone:NULL` and `initWithCString:length:`,
then stores the input byte in the first byte of the reserved event word used as
the `charValue` cache. `setChars:` (`0x193F0`) releases the old string through
selector cell `0x37CC8` (`__sel_backref` row `0x441E8` → `release`), retains
the supplied string through cell `0x37CF0` (row `0x44390` → `retain`), stores
it, and clears that cache byte. `MutableEvent.m` now matches the recovered PPC
ownership sequence.

`charValue` (`0x1946C`) returns the cached signed byte when nonzero. Otherwise,
if the key string is nonempty, it extracts the first-character substring,
queries `+[NSString defaultCStringEncoding]`, and asks whether the substring
can be converted. If so, it writes the C string into the reserved cache byte
using `getCString:maxLength:` with the binary's length argument of one. The
selectors are present in the PPC string table, and the code returns the
sign-extended cache byte whether or not conversion succeeds.
| `0x00019544` | `-[NSPopUpButton(WhyIsntThisInTheAppKit) itemWithTag:]` | `@8@4:8i12` | selector pointer outside file-backed sections |
| `0x000196AC` | `-[FieldView _rawscrollup:to:lines:]` | `v16@4:8I12I16I20` | resolved |
| `0x00019AD8` | `-[FieldView _rawscrolldown:to:lines:]` | `v16@4:8I12I16I20` | resolved |
| `0x00019F10` | `-[FieldView _rawclear:to:]` | `v12@4:8I12I16` | resolved |
| `0x0001A04C` | `-[FieldView _sscrollup:to:lines:]` | `v16@4:8I12I16I20` | resolved |
| `0x0001A110` | `-[FieldView _sscrolldown:to:lines:]` | `v16@4:8I12I16I20` | resolved |
| `0x0001A1D8` | `-[FieldView _sclear:to:]` | `v12@4:8I12I16` | resolved |
| `0x0001A3C0` | `-[FieldView _smark:len:attr:at::back:]` | `v28@4:8r*12I16C20I24I28i32` | resolved |
| `0x0001A6C8` | `-[FieldView refreshscreen]` | `v4@4:8` | resolved |
| `0x0001A9A4` | `-[FieldView _srclear:to:]` | `v12@4:8I12I16` | resolved |
| `0x0001AAA0` | `-[FieldView _srscrollup:to:lines:]` | `v16@4:8I12I16I20` | resolved |
| `0x0001AB64` | `-[FieldView _srscrolldown:to:lines:]` | `v16@4:8I12I16I20` | resolved |
| `0x0001AC34` | `-[FieldView _refresh]` | `v4@4:8` | resolved |
| `0x0001ADAC` | `-[FieldView _lscrollup:to:lines:]` | `v16@4:8I12I16I20` | resolved |
| `0x0001B024` | `-[FieldView _lscrolldown:to:lines:]` | `v16@4:8I12I16I20` | resolved |
| `0x0001B144` | `-[FieldView _lclear:to:]` | `v12@4:8I12I16` | resolved |
| `0x0001B374` | `-[FieldView _bclear:to:]` | `v12@4:8I12I16` | resolved |
| `0x0001B664` | `-[FieldView _bclear:from:]` | `v12@4:8I12I16` | resolved |
| `0x0001B9AC` | `-[FieldView _sshighlight::::isLit:]` | `@21@4:8I12I16I20I24c28` | resolved |
| `0x0001BE44` | `-[FieldView _highlight::to::in::isLit:]` | `v36@4:8I12C16I20C24I28I32c43` | resolved |
| `0x0001BFF8` | `-[FieldView _highlight::to::isLit:]` | `v21@4:8I12C16I20C24c28` | resolved |
| `0x0001C044` | `-[FieldView _highlightsel:to:isLit:]` | `v13@4:8I12I16c20` | resolved |
| `0x0001C098` | `-[FieldView _srhclear:to:]` | `v12@4:8I12I16` | resolved |
| `0x0001C16C` | `-[FieldView _srhscrollup:to:lines:]` | `v16@4:8I12I16I20` | resolved |
| `0x0001C230` | `-[FieldView _srhscrolldown:to:lines:]` | `v16@4:8I12I16I20` | resolved |
| `0x0001C300` | `-[FieldView _lscrollup:]` | `v8@4:8I12` | resolved |
| `0x0001C59C` | `-[FieldView _mark:len:]` | `v12@4:8r*12I16` | resolved |
| `0x0001C744` | `-[FieldView isSelected::]` | `c12@4:8i12i16` | resolved |
| `0x0001C7A8` | `-[FieldView _delayedCursor:]` | `v8@4:8@12` | resolved |
| `0x0001C828` | `-[FieldView _cursor]` | `v4@4:8` | resolved |
| `0x0001CE5C` | `-[FieldView _clearcursor]` | `v4@4:8` | resolved |
| `0x0001CFC4` | `-[FieldView(FieldDraw) drawRect:]` | `v20@4:8{?={?=ff}{?=ff}}12` | selector pointer outside file-backed sections |
| `0x0001D12C` | `-[FieldView setWrap]` | `v4@4:8` | sets current row slot metadata byte to one |
| `0x0001D160` | `-[FieldView _binsert::bytes:]` | `v16@4:8I12I16I20` | three unsigned integer arguments; updates the scrollback-relative line slot with `_insertChars`'s unchanged line pointer |
| `0x0001D1D8` | `-[FieldView _bdelete::bytes:]` | `v16@4:8I12I16I20` | resolved |
| `0x0001D250` | `-[FieldView(FieldMouseScroll) _scrollTo:]` | `v8@4:8I12` | selector pointer outside file-backed sections |
| `0x0001D464` | `-[FieldView scrollTo:]` | `v8@4:8I12` | resolved |
| `0x0001D4D4` | `-[FieldView pageUp]` | `v4@4:8` | resolved |
| `0x0001D534` | `-[FieldView pageDown]` | `v4@4:8` | resolved |
| `0x0001D5B0` | `-[FieldView lineUp]` | `v4@4:8` | resolved |
| `0x0001D5F4` | `-[FieldView lineDown]` | `v4@4:8` | resolved |
| `0x0001D648` | `-[FieldView positionFrom:]` | `v8@4:8@12` | resolved |
| `0x0001D7F8` | `-[FieldView setScroller:]` | `v8@4:8@12` | external selector operands; reconstructed as release/store/retain |
| `0x0001D854` | `-[FieldView reflectPosition]` | `v4@4:8` | resolved |
| `0x0001D994` | `-[FieldView _autoScrollTo:]` | `v8@4:8I12` | resolved |
| `0x0001DA30` | `-[FieldView _smartAutoScrollTo:]` | `@8@4:8I12` | resolved |
| `0x0001DAD8` | `-[FieldView _dragEnd::]` | `v9@4:8I12C16` | resolved |
| `0x0001DD10` | `-[FieldView _singleClick::]` | `v9@4:8I12C16` | resolved |
| `0x0001DD94` | `-[FieldView findPrevWord:::]` | `v16@4:8i12i16^{?=IC}20` | resolved |
| `0x0001DE70` | `-[FieldView findNextWord:::]` | `v16@4:8i12i16^{?=IC}20` | resolved |
| `0x0001DF94` | `-[FieldView findMatchingDelimiter:::delimChars:backwards:]` | `c21@4:8i12i16^{?=IC}20r*24c28` | resolved |
| `0x0001E0DC` | `-[FieldView _doubleClick::]` | `v9@4:8I12C16` | resolved |
| `0x0001E2E4` | `-[FieldView _tripleClick::]` | `v9@4:8I12C16` | resolved |
| `0x0001E3AC` | `-[FieldView _drag::]` | `v9@4:8I12C16` | resolved |
| `0x0001E7BC` | `-[FieldView _shiftClick::]` | `v9@4:8I12C16` | resolved |
| `0x0001E8C0` | `-[FieldView _clearSelection]` | `v4@4:8` | resolved |
| `0x0001E940` | `-[FieldView _point:toPosition::]` | `v20@4:8{?=ff}12^I20^I24` | resolved |
| `0x0001EDB4` | `-[FieldView hackRoutine:]` | `v8@4:8@12` | resolved |
| `0x0001EE9C` | `-[FieldView(FieldMouseScroll) mouseDown:]` | `v8@4:8@12` | selector pointer outside file-backed sections |
| `0x0001F3B4` | `-[FieldView selStream]` | `@4@4:8` | resolved |
| `0x0001F734` | `-[FieldView(FieldMouseScroll) copy:]` | `v8@4:8@12` | selector pointer outside file-backed sections |
| `0x0001F838` | `-[FieldView clearScrollback:]` | `v8@4:8@12` | resolved |
| `0x0001FB14` | `-[FieldView(FieldMouseScroll) selectAll:]` | `v8@4:8@12` | selector pointer outside file-backed sections |
| `0x0001FEA4` | `-[FieldView(FieldMouseScroll) find:]` | `c8@4:8r*12` | selector pointer outside file-backed sections |
| `0x00020364` | `-[FieldView bfind:]` | `c8@4:8r*12` | resolved |
| `0x0002081C` | `-[FieldView selStr]` | `r*4@4:8` | resolved |
| `0x0002088C` | `-[FieldView jumpToSelection:]` | `v8@4:8@12` | resolved |
| `0x0002097C` | `-[FieldView(FieldMouseScroll) validRequestorForSendType:returnType:]` | `@12@4:8@12@16` | selector pointer outside file-backed sections |
| `0x00020A0C` | `-[FieldView(FieldMouseScroll) writeSelectionToPasteboard:types:]` | `c12@4:8@12@16` | selector pointer outside file-backed sections |
| `0x00023558` | `-[Preferences init]` | `@4@4:8` | selector pointer outside file-backed sections |
| `0x000237C0` | `-[Preferences showPrefWindow:]` | `v8@4:8@12` | resolved |
| `0x0002381C` | `-[Preferences changePane:]` | `v8@4:8@12` | resolved |
| `0x0002386C` | `-[Preferences reflectChoiceOfPane:]` | `v8@4:8i12` | resolved |
| `0x00023B48` | `-[Preferences terminalDidBecomeMain:]` | `v8@4:8@12` | resolved |
| `0x00023C44` | `-[Preferences terminalDidResignMain:]` | `v8@4:8@12` | resolved |
| `0x00023D88` | `-[Preferences doFlush]` | `v4@4:8` | resolved |
| `0x00023DE4` | `-[Preferences setUpButtons:]` | `v8@4:8i12` | resolved |
| `0x00023F2C` | `-[Preferences revert:]` | `v8@4:8@12` | resolved |
| `0x00024028` | `-[Preferences setDefaultX:]` | `v8@4:8@12` | resolved |
| `0x000240FC` | `-[Preferences ok:]` | `v8@4:8@12` | selector pointer outside file-backed sections |
| `0x00024260` | `-[Preferences suggest:]` | `v8@4:8@12` | resolved |
| `0x0002435C` | `-[Preferences showDefaultX:]` | `v8@4:8@12` | resolved |
| `0x00024394` | `-[Preferences showDefault:]` | `v5@4:8c12` | resolved |
| `0x00024498` | `-[Preferences okButton]` | `@4@4:8` | resolved |
| `0x000244A8` | `-[Preferences windowShouldClose:]` | `c8@4:8@12` | selector pointer outside file-backed sections |
| `0x00024510` | `-[Preferences handleReturnByProxy:]` | `v8@4:8@12` | resolved |
| `0x00024570` | `-[Preferences windowDidBecomeKey:]` | `v8@4:8@12` | selector pointer outside file-backed sections |
| `0x000245E0` | `-[Preferences windowWillClose:]` | `v8@4:8@12` | selector pointer outside file-backed sections |
| `0x00024618` | `-[Preferences windowDidResignKey:]` | `v8@4:8@12` | selector pointer outside file-backed sections |
| `0x00024688` | `-[Preferences notifyController:withArg:]` | `@12@4:8:12@16` | resolved |
| `0x00024700` | `-[Preferences setCurrentTerminal:]` | `v8@4:8@12` | resolved |
| `0x000247F4` | `-[Preferences currentTerminal]` | `@4@4:8` | resolved |
| `0x00024804` | `-[EmulationController setFromStruct:]` | `v8@4:8r^{?=cccccccSSc*@fIIC@ii[8@]i}12` | resolved |
| `0x00024854` | `-[EmulationController showDefault:]` | `v5@4:8c12` | resolved |
| `0x0002494C` | `-[EmulationController suggest:]` | `v8@4:8@12` | resolved |
| `0x00024994` | `-[EmulationController setMeta:opts:::lock:]` | `v21@4:8i12c16c20c24c28` | resolved |
| `0x000249F0` | `-[EmulationController displayValues::::]` | `v17@4:8i12c16c20c24` | resolved |
| `0x00024B18` | `-[EmulationController revert:]` | `v8@4:8@12` | resolved |
| `0x00024B60` | `-[EmulationController setDefault]` | `@4@4:8` | resolved |
| `0x00024C8C` | `-[EmulationController setStruct:]` | `v8@4:8^{?=cccccccSSc*@fIIC@ii[8@]i}12` | resolved |
| `0x00024D38` | `-[EmulationController firstVisible:]` | `v8@4:8@12` | resolved |
| `0x00024D74` | `-[EmulationController lastVisible:]` | `v8@4:8@12` | resolved |
| `0x00024D80` | `-[MiscController setFromStruct:]` | `v8@4:8r^{?=cccccccSSc*@fIIC@ii[8@]i}12` | resolved |
| `0x00024DCC` | `-[MiscController showDefault:]` | `v5@4:8c12` | resolved |
| `0x00024EC0` | `-[MiscController suggest]` | `v4@4:8` | resolved |
| `0x00024F08` | `-[MiscController setScrollback:lines:wrap:autoFocus:lock:]` | `v21@4:8c12i16c20c24c28` | resolved |
| `0x00024F64` | `-[MiscController displayScrollback:lines:wrap:autoFocus:]` | `v17@4:8c12i16c20c24` | resolved |
| `0x000250F4` | `-[MiscController revert]` | `v4@4:8` | resolved |
| `0x0002513C` | `-[MiscController setDefault]` | `@4@4:8` | resolved |
| `0x0002529C` | `-[MiscController setStruct:]` | `v8@4:8^{?=cccccccSSc*@fIIC@ii[8@]i}12` | resolved |
| `0x0002536C` | `-[MiscController checkSettings]` | `c4@4:8` | resolved |
| `0x0002552C` | `-[MiscController firstVisible:]` | `v8@4:8@12` | resolved |
| `0x00025568` | `-[MiscController lastVisible:]` | `v8@4:8@12` | resolved |
| `0x00025574` | `-[MiscController handleReturn:]` | `v8@4:8@12` | resolved |
| `0x00025638` | `-[MiscController limitLines:]` | `v8@4:8@12` | resolved |
| `0x000256CC` | `-[MiscController unlimitLines:]` | `v8@4:8@12` | resolved |
| `0x00025760` | `-[ProcessMonitorController setFromStruct:]` | `v8@4:8r^{?=cccccccSSc*@fIIC@ii[8@]i}12` | resolved |
| `0x0002576C` | `-[ProcessMonitorController showDefault:]` | `v5@4:8c12` | resolved |
| `0x00025864` | `-[ProcessMonitorController displayMonitor:shellsClean:runningBkgndClean:fastAudits:cleanCommands:]` | `v24@4:8c12c16c20c24r^*28` | resolved |
| `0x000259D0` | `-[ProcessMonitorController revert]` | `v4@4:8` | resolved |
| `0x00025A2C` | `-[ProcessMonitorController setDefault]` | `@4@4:8` | resolved |
| `0x00025A90` | `-[ProcessMonitorController enablementChanged:]` | `v8@4:8@12` | resolved |
| `0x00025B00` | `-[ProcessMonitorController runningBackgroundChanged:]` | `v8@4:8@12` | resolved |
| `0x00025B70` | `-[ProcessMonitorController writeCommands]` | `v4@4:8` | resolved |
| `0x00025BE8` | `-[ProcessMonitorController suggest]` | `v4@4:8` | resolved |
| `0x00025C44` | `-[ProcessMonitorController setStruct:]` | `v8@4:8^{?=cccccccSSc*@fIIC@ii[8@]i}12` | resolved |
| `0x00025CA0` | `-[ProcessMonitorController firstVisible:]` | `v8@4:8@12` | resolved |
| `0x00025CF4` | `-[ProcessMonitorController lastVisible:]` | `v8@4:8@12` | resolved |
| `0x00025D00` | `-[ProcessMonitorController add:]` | `v8@4:8@12` | resolved |
| `0x00026064` | `-[ProcessMonitorController remove:]` | `v8@4:8@12` | selector pointer outside file-backed sections |
| `0x00026124` | `-[ProcessMonitorController tableViewSelectionDidChange:]` | `v8@4:8@12` | selector pointer outside file-backed sections |
| `0x00026198` | `-[ProcessMonitorController controlTextDidChange:]` | `v8@4:8@12` | selector pointer outside file-backed sections |
| `0x00026260` | `-[ProcessMonitorController promulgateSettings]` | `v4@4:8` | resolved |
| `0x00026360` | `-[ProcessMonitorController numberOfRowsInTableView:]` | `i8@4:8@12` | selector pointer outside file-backed sections |
| `0x000263AC` | `-[ProcessMonitorController tableView:objectValueForTableColumn:row:]` | `@16@4:8@12@16i20` | selector pointer outside file-backed sections |
| `0x00026428` | `-[ProcessMonitorController tableView:setObjectValue:forTableColumn:row:]` | `v20@4:8@12@16@20i24` | selector pointer outside file-backed sections |
| `0x000264A0` | `-[ShellController setFromStruct:]` | `v8@4:8r^{?=cccccccSSc*@fIIC@ii[8@]i}12` | resolved |
| `0x000264AC` | `-[ShellController showDefault:]` | `v5@4:8c12` | resolved |
| `0x00026544` | `-[ShellController setShell:source:]` | `v9@4:8r*12c16` | resolved |
| `0x000265D0` | `-[ShellController revert]` | `v4@4:8` | resolved |
| `0x0002662C` | `-[ShellController setDefault]` | `@4@4:8` | resolved |
| `0x00026690` | `-[ShellController suggest]` | `v4@4:8` | resolved |
| `0x000266EC` | `-[ShellController setStruct:]` | `v8@4:8^{?=cccccccSSc*@fIIC@ii[8@]i}12` | resolved |
| `0x00026748` | `-[ShellController checkSettings]` | `c4@4:8` | resolved |
| `0x00026A2C` | `-[ShellController firstVisible:]` | `v8@4:8@12` | resolved |
| `0x00026A80` | `-[ShellController lastVisible:]` | `v8@4:8@12` | resolved |
| `0x00026A8C` | `-[ShellController shellChanged:]` | `v8@4:8@12` | resolved |
| `0x00026B14` | `-[ShellController sourceDotLoginChanged:]` | `v8@4:8@12` | resolved |
| `0x00026B70` | `-[StartupController setFromStruct:]` | `v8@4:8r^{?=cccccccSSc*@fIIC@ii[8@]i}12` | resolved |
| `0x00026B7C` | `-[StartupController showDefault:]` | `v5@4:8c12` | resolved |
| `0x00026CC0` | `-[StartupController setAction:file:fastLaunch:lockRevert:]` | `v17@4:8i12r*16c20c24` | resolved |
| `0x00026E60` | `-[StartupController suggest]` | `v4@4:8` | resolved |
| `0x00026EBC` | `-[StartupController revert]` | `v4@4:8` | resolved |
| `0x00026F78` | `-[StartupController setStruct:]` | `v8@4:8^{?=cccccccSSc*@fIIC@ii[8@]i}12` | resolved |
| `0x00026FA0` | `-[StartupController checkSettings]` | `c4@4:8` | resolved |
| `0x00027250` | `-[StartupController firstVisible:]` | `v8@4:8@12` | resolved |
| `0x000272A4` | `-[StartupController lastVisible:]` | `v8@4:8@12` | resolved |
| `0x000272B0` | `-[StartupController startupFilesChanged:]` | `@8@4:8@12` | resolved |
| `0x0002735C` | `-[StartupController setPathRequest:]` | `v8@4:8@12` | resolved |
| `0x00027448` | `-[StartupController pathWasSet:]` | `v8@4:8@12` | resolved |
| `0x0002758C` | `-[StartupController fastStartupChanged:]` | `v8@4:8@12` | resolved |
| `0x000275E8` | `-[StartupController startupActionChanged:]` | `v8@4:8@12` | resolved |
| `0x00027674` | `-[StartupController setDefault]` | `@4@4:8` | resolved |
| `0x0002769C` | `-[StartupController forceSetDefault]` | `v4@4:8` | resolved |
| `0x00027780` | `-[StartupController savePanelDidChangeStartupDefaults:]` | `v8@4:8@12` | resolved |
| `0x000277B8` | `-[TextAttributeController revert]` | `v4@4:8` | resolved |
| `0x000277C4` | `-[TextAttributeController setFromStruct:]` | `v8@4:8r^{?=cccccccSSc*@fIIC@ii[8@]i}12` | resolved |
| `0x00027878` | `-[TextAttributeController setDefault]` | `@4@4:8` | resolved |
| `0x00027A14` | `-[TextAttributeController showDefault:]` | `v5@4:8c12` | resolved |
| `0x00027AFC` | `-[TextAttributeController suggest]` | `v4@4:8` | resolved |
| `0x00027B08` | `-[TextAttributeController setStruct:]` | `v8@4:8^{?=cccccccSSc*@fIIC@ii[8@]i}12` | resolved |
| `0x00027BFC` | `-[TextAttributeController firstVisible:]` | `v8@4:8@12` | resolved |
| `0x00027CC4` | `-[TextAttributeController lastVisible:]` | `v8@4:8@12` | resolved |
| `0x00027CD0` | `-[TextAttributeController windowDidBecomeKey:]` | `v8@4:8@12` | selector pointer outside file-backed sections |
| `0x00027D34` | `-[TitleBarController init]` | `@4@4:8` | selector pointer outside file-backed sections |
| `0x00027D88` | `-[TitleBarController awakeFromNib]` | `v4@4:8` | selector pointer outside file-backed sections |
| `0x00027DE8` | `-[TitleBarController setFromStruct:]` | `v8@4:8r^{?=cccccccSSc*@fIIC@ii[8@]i}12` | resolved |
| `0x00027E50` | `-[TitleBarController showDefault:]` | `v5@4:8c12` | resolved |
| `0x00027F04` | `-[TitleBarController suggest]` | `v4@4:8` | resolved |
| `0x00027F48` | `-[TitleBarController setBits:custom:lock:]` | `v13@4:8i12r*16c20` | resolved |
| `0x00028004` | `-[TitleBarController displayBits:custom:]` | `v12@4:8i12r*16` | resolved |
| `0x000282FC` | `-[TitleBarController revert]` | `v4@4:8` | resolved |
| `0x0002833C` | `-[TitleBarController setDefault]` | `@4@4:8` | resolved |
| `0x0002843C` | `-[TitleBarController titleBits]` | `i4@4:8` | resolved |
| `0x000284B4` | `-[TitleBarController checkSettings]` | `c4@4:8` | resolved |
| `0x000285D8` | `-[TitleBarController setStruct:]` | `v8@4:8^{?=cccccccSSc*@fIIC@ii[8@]i}12` | resolved |
| `0x000286A0` | `-[TitleBarController firstVisible:]` | `v8@4:8@12` | resolved |
| `0x000286E8` | `-[TitleBarController lastVisible:]` | `v8@4:8@12` | resolved |
| `0x000286F4` | `-[TitleBarController titleBitsChanged:]` | `v8@4:8@12` | resolved |
| `0x000287C8` | `-[TitleBarController textDidEndEditing:]` | `v8@4:8@12` | selector pointer outside file-backed sections |
| `0x000288A8` | `-[WindowController setFromStruct:]` | `v8@4:8r^{?=cccccccSSc*@fIIC@ii[8@]i}12` | resolved |
| `0x00028914` | `-[WindowController showDefault:]` | `v5@4:8c12` | resolved |
| `0x00028A6C` | `-[WindowController suggest]` | `v4@4:8` | resolved |
| `0x00028C48` | `-[WindowController setRows:cols:exitAction:font:size:lock:]` | `v25@4:8i12i16i20r*24f12c32` | resolved |
| `0x00028DB0` | `-[WindowController displayRows:cols:exitAction:font:size:]` | `v20@4:8i12i16i20r*24f12` | resolved |
| `0x00028EB4` | `-[WindowController displayFont:inSize:]` | `v8@4:8r*12f12` | resolved |
| `0x0002916C` | `-[WindowController revert]` | `v4@4:8` | resolved |
| `0x000291BC` | `-[WindowController setDefault]` | `@4@4:8` | resolved |
| `0x00029354` | `-[WindowController setStruct:]` | `v8@4:8^{?=cccccccSSc*@fIIC@ii[8@]i}12` | resolved |
| `0x00029514` | `-[WindowController checkSettings]` | `c4@4:8` | resolved |
| `0x00029B50` | `-[WindowController setFontRequest:]` | `v8@4:8@12` | resolved |
| `0x00029C60` | `-[WindowController receiveFontFromTrap:]` | `@8@4:8@12` | resolved |
| `0x00029CE0` | `-[WindowController firstVisible:]` | `v8@4:8@12` | resolved |
| `0x00029D34` | `-[WindowController lastVisible:]` | `v8@4:8@12` | resolved |
| `0x00029D7C` | `-[WindowController fontTrapDidResignFirstResponder]` | `@4@4:8` | resolved |
| `0x00029DE4` | `-[WindowController windowDidResignKey:]` | `v8@4:8@12` | selector pointer outside file-backed sections |
| `0x00029E50` | `-[FontTrap acceptsFirstResponder]` | `c4@4:8` | selector pointer outside file-backed sections |
| `0x00029E60` | `-[FontTrap changeFont:]` | `v8@4:8@12` | selector pointer outside file-backed sections |
| `0x0002A2EC` | `-[FontTrap resignFirstResponder]` | `c4@4:8` | selector pointer outside file-backed sections |
| `0x0002A328` | `-[FontTrap initWithFrame:]` | `@20@4:8{?={?=ff}{?=ff}}12` | selector pointer outside file-backed sections |
| `0x0002A384` | `-[ServiceCache init]` | `@4@4:8` | selector pointer outside file-backed sections |
| `0x0002A4FC` | `-[ServiceCache setOKToSave:]` | `v5@4:8c12` | resolved |
| `0x0002A55C` | `-[ServiceCache serviceSetChanged]` | `c4@4:8` | resolved |
| `0x0002A5C8` | `-[ServiceCache loadServiceSet]` | `c4@4:8` | resolved |
| `0x0002ABA4` | `-[ServiceCache disableOfferExamples]` | `v4@4:8` | resolved |
| `0x0002ABB8` | `-[ServiceCache readService:fromFile:zone:]` | `c16@4:8^{?=@c*CCCCCCCCCI}12^{?=*iiss{__sbuf=*i}i^v^?^?^?^?{__sbuf=*i}*i[3C][1C]{__sbuf=*i}iq}16^{?=}20` | resolved |
| `0x0002AD9C` | `-[ServiceCache discardServices]` | `v4@4:8` | resolved |
| `0x0002AE6C` | `-[ServiceCache serviceSet]` | `^{?=i^{?}}4@4:8` | resolved |
| `0x0002AE7C` | `-[ServiceCache updateServicesFile]` | `c4@4:8` | resolved |
| `0x0002B818` | `-[ServiceCache saveService:inSlot:]` | `v12@4:8^{?=@c*CCCCCCCCCI}12i16` | resolved |
| `0x0002B8C8` | `-[ServiceCache importService:from:]` | `v12@4:8^{?=@c*CCCCCCCCCI}12^{?=@c*CCCCCCCCCI}16` | resolved |
| `0x0002BA0C` | `-[ServiceCache addNewTermService:]` | `i8@4:8^{?=@c*CCCCCCCCCI}12` | resolved |
| `0x0002BB78` | `-[ServiceCache removeServiceAt:]` | `v8@4:8i12` | resolved |
| `0x0002BCE0` | `-[ServiceCache writeServices]` | `v4@4:8` | resolved |
| `0x0002BEBC` | `-[ServiceCache writeService:toFile:]` | `v12@4:8^{?=@c*CCCCCCCCCI}12^{?=*iiss{__sbuf=*i}i^v^?^?^?^?{__sbuf=*i}*i[3C][1C]{__sbuf=*i}iq}16` | resolved |
| `0x0002BF70` | `-[ServiceCache checkFile:forNaughtyModes:]` | `c12@4:8r*12I16` | resolved |
| `0x0002C070` | `-[ServiceCache convertString:toPrintable:]` | `v12@4:8*12*16` | resolved |
| `0x0002C134` | `-[ServiceCache convertPrintable:toString:]` | `v12@4:8*12*16` | resolved |
| `0x0002C1E4` | `-[ServiceCache loadCommandsMenu]` | `v4@4:8` | resolved |
| `0x0002C1F0` | `-[ServiceManager cellCountFor:]` | `i8@4:8@12` | resolved |
| `0x0002C248` | `-[ServiceManager init]` | `@4@4:8` | selector pointer outside file-backed sections |
| `0x0002C3F4` | `-[ServiceManager go:]` | `v5@4:8c12` | resolved |
| `0x0002C748` | `-[ServiceManager renewForServiceSet:]` | `v8@4:8^{?=i^{?}}12` | resolved |
| `0x0002C85C` | `-[ServiceManager isDirty]` | `c4@4:8` | selector pointer outside file-backed sections |
| `0x0002C870` | `-[ServiceManager setDirty:]` | `v5@4:8c12` | resolved |
| `0x0002C8E0` | `-[ServiceManager updateForCurrentDirtiness]` | `v4@4:8` | resolved |
| `0x0002C9F4` | `-[ServiceManager editSelectedServiceName:]` | `v8@4:8@12` | resolved |
| `0x0002CB2C` | `-[ServiceManager serviceSelected:]` | `v8@4:8@12` | resolved |
| `0x0002CD18` | `-[ServiceManager setControlsFromService:]` | `v8@4:8^{?=@c*CCCCCCCCCI}12` | resolved |
| `0x0002CEA8` | `-[ServiceManager setupExecBoxForWindowType:routingFlags:andSetPopUp:]` | `v13@4:8C12C16c20` | resolved |
| `0x0002D22C` | `-[ServiceManager setControlsIn:fromFlags:]` | `@9@4:8@12C16` | resolved |
| `0x0002D328` | `-[ServiceManager polymorphicOptsChanged:]` | `v8@4:8@12` | resolved |
| `0x0002D48C` | `-[ServiceManager execTypeChanged:]` | `v8@4:8@12` | resolved |
| `0x0002D528` | `-[ServiceManager makeDirty:]` | `v8@4:8@12` | resolved |
| `0x0002D560` | `-[ServiceManager add:]` | `v8@4:8@12` | resolved |
| `0x0002D8D8` | `-[ServiceManager freeService:]` | `v8@4:8^{?=@c*CCCCCCCCCI}12` | resolved |
| `0x0002D924` | `-[ServiceManager whyAreSettingsNotAcceptable]` | `i4@4:8` | resolved |
| `0x0002D9B8` | `-[ServiceManager nameUnique:]` | `c8@4:8@12` | resolved |
| `0x0002DA94` | `-[ServiceManager fillServiceFromWindow:]` | `v8@4:8^{?=@c*CCCCCCCCCI}12` | resolved |
| `0x0002DCA0` | `-[ServiceManager setFlags:fromControlsIn:]` | `v12@4:8*12@16` | resolved |
| `0x0002DD5C` | `-[ServiceManager setFlagsFromCell:]` | `c8@4:8@12` | resolved |
| `0x0002DDC4` | `-[ServiceManager change:]` | `v8@4:8@12` | resolved |
| `0x0002DFC4` | `-[ServiceManager warnAboutStrangeness:]` | `v8@4:8^{?=@c*CCCCCCCCCI}12` | resolved |
| `0x0002E088` | `-[ServiceManager checkSettings]` | `c4@4:8` | resolved |
| `0x0002E168` | `-[ServiceManager windowShouldClose:]` | `c8@4:8@12` | selector pointer outside file-backed sections |
| `0x0002E454` | `-[ServiceManager remove:]` | `v8@4:8@12` | selector pointer outside file-backed sections |
| `0x0002E5A8` | `-[ServiceManager windowDidResize:]` | `v8@4:8@12` | selector pointer outside file-backed sections |
| `0x0002E624` | `-[ServiceManager windowWillResize:toSize:]` | `{?=ff}20@8:12@16{?=ff}20` | selector pointer outside file-backed sections |
| `0x0002E678` | `-[ServiceManager controlTextDidChange:]` | `v8@4:8@12` | selector pointer outside file-backed sections |
| `0x0002E6B0` | `-[ServiceManager control:textShouldEndEditing:]` | `c12@4:8@12@16` | selector pointer outside file-backed sections |
| `0x0002E7D8` | `-[ServiceManager controlTextDidEndEditing:]` | `v8@4:8@12` | selector pointer outside file-backed sections |
| `0x0002EA20` | `-[ServiceManager save:]` | `v8@4:8@12` | resolved |
| `0x0002ED98` | `-[ServiceManager saveService:]` | `v8@4:8@12` | resolved |
| `0x0002EE14` | `-[ServiceProvider provideService:userData:error:]` | `v16@4:8@12@16r^@20` | resolved |
| `0x0002EFF0` | `-[ServiceProvider doService:pasteboard:isDrag:dragTerm:errBuff:]` | `c24@4:8^{?=@c*CCCCCCCCCI}12@16c20@24r^@28` | resolved |
| `0x00030858` | `-[ServiceProvider newCommand:shell:env:]` | `@16@4:8r*12C16@20` | resolved |
| `0x00030894` | `-[ServiceProvider newCommand:shell:path:env:]` | `@20@4:8r*12C16r*20@24` | resolved |
| `0x000309D4` | `-[ServiceProvider ok:]` | `@8@4:8@12` | selector pointer outside file-backed sections |
| `0x00030A24` | `-[ServiceProvider cancel:]` | `@8@4:8@12` | selector pointer outside file-backed sections |
| `0x00030A74` | `-[ServiceProvider pasteboard:containsType:]` | `c12@4:8@12@16` | resolved |
| `0x00030B00` | `-[ServiceProvider copyString:]` | `*8@4:8r*12` | resolved |
| `0x00030BE0` | `-[ServiceProvider ensureNibLoaded]` | `v4@4:8` | resolved |
| `0x00030D1C` | `-[ServiceProvider replace:with:in:]` | `*16@4:8r*12r*16*20` | resolved |
| `0x00030E9C` | `-[ServiceProvider windowWillResize:toSize:]` | `{?=ff}20@8:12@16{?=ff}20` | resolved |

## Remaining interface recovery

### Services ABI shared by ServiceCache and ServiceProvider

`TerminalServices.h` now carries the shared PPC service-record ABI recovered
from the `ServiceCache` and `ServiceProvider` methods. `TerminalServiceRecord`
is 28 bytes: the service name at offset 0, reserved byte at 4, command pointer
at 8, nine option bytes at 12–20, and flags word at 24. `TerminalServiceSet` is an
8-byte count/pointer pair. The `ServiceCache` ivars match the IDA UDT: `theSet`
at 4, `lastMod` at 8, `initialized` at 12, `dirPath`/`mapFile`/`cacheFile` at
16/20/24, `serviceDirectory` at 28, and the three save/example flags at
32–34, yielding a 36-byte instance. `tests/serviceabi.m` checks both shared
record sizes and the complete cache object size when parsed for either 32-bit
target. This ABI is confirmed against the PPC image; the same 32-bit layouts
are used for i386 pending a matching i386 Terminal reference. The header now guards every ServiceCache ivar offset with _Static_assert; ServiceCache.m and tests/serviceabi.m pass PPC and i386 target syntax checks with those assertions enabled.

### DirtMonitor PPC object layout

IDA's `DirtMonitor` UDT is 84 bytes. `DirtMonitor.h` preserves its 32-bit
field offsets: `numPtys` at 4, `knownDevices`/`fds` at 8/12, `numPorts` at 16,
`goodTasks`/`freePortNames` at 20/24, stack counters at 28–34, free-task and
flag-map pointers at 36–44, policy bytes at 48–50, `cleanCommands` at 52,
processor-set data at 56/60, `selfTaskName` at 64, and `monitorOK` at 81.
The constructor, PTY registration, and clean-policy update are reconstructed
in `DirtMonitor.m`. The PPC constructor's complete Objective-C send list is
resolved through its method-entry TOC base. Its notification setup creates an
`NSPort`, retains it, sets the monitor as delegate, obtains the current run
loop, and adds the port in that order. `DirtMonitor.m` now matches this
ownership and call sequence. The UDT and runtime behavior remain PPC-only until
an i386 oracle is found.

### `-[Terminal updateDirtIfNeeded]` (`0x0000E918`)

The PPC body checks the app-global `_theDefaultsObject` with
`boolForKey:@"MonitorProcs"`. If monitoring is disabled or the Terminal is
dead, it clears the window's document-edited state. Otherwise, only when the
window is not miniaturized and `needsDirtUpdate` is set, it asks the app
delegate's `dirtMonitor` whether `shellDevice` is dirty, applies that result to
the window, and clears `needsDirtUpdate`. If monitoring is enabled and either
guard prevents the query, the body leaves the window state and pending flag
unchanged.

Evidence: PPC function `0xE918`; defaults receiver `_theDefaultsObject` at
`0x35030`; key object `0x36DA8` -> `MonitorProcs` string `0x315D8`; window
selector cell `0x37C94`; `setDocumentEdited:` selector cell `0x38074`; app
delegate global `_NSApp` at `0x356B4`; `dirtMonitor` selector cell `0x38054`;
`isDeviceDirty:` selector cell `0x38070` -> selector string `0x3C900`. The
PPC object offsets are `deadMeat +0xF0`, `isMiniaturized +0xEE`,
`needsDirtUpdate +0xEF`, and `shellDevice +0xF8`. Selector cells resolve through
the PPC `__sel_backref` table: `boolForKey:` at `0x37D00` (row `0x42B98`),
`window` at `0x37C94` (`0x45360`), `setDocumentEdited:` at `0x38074`
(`0x448C0`), `dirtMonitor` at `0x38054` (`0x43088`), and `isDeviceDirty:` at
`0x38070` (`0x43838`). The exact sends match the source. The matching i386
implementation and runtime behavior remain unverified.

### `-[Terminal endOfFileOn:]` (`0x0000CA40`)

IDA's PPC body sends `close` and then `release` to its `sender` argument and
returns. In the reconstructed `Filer` path, `handleOutput:` calls
`[target endOfFileOn:self]` when `tryOutput` reports a nonzero result. `Filer`
implements `close` by closing the file handle, unregistering notifications,
releasing the handle, clearing buffered data, and stopping its timer; the
subsequent `release` tears down the object. Its selector encoding is
`v8@4:8`; sender is an Objective-C object.

### `-[Terminal childExit:status:]` (`0x0000CA8C`)

The reconstructed callback reads the wait status from its second object slot,
applies `ShellExitAction`, prints the exact localized signal/exit/completion
messages, unregisters the shell device when the terminal remains open, and
closes the window for the auto-close cases. IDA confirms the strings and the
PPC branch structure. After printing an exit message, the PPC body checks
`[[self window] isKeyWindow]`; on the key-window path it locks focus, clears
the cursor, unlocks focus, and flushes the window before disabling cursor
drawing. `Terminal.m` now preserves that sequence. The method-entry TOC base is
anchored by its tail `performClose:` send (`0xCA8C + 0x30000 - 0x49C8 =
0x380C4`). That base resolves the initial sender calls to `kill` (`0x3800C`)
and `close` (`0x37F54`), which source now matches. Encoding:
`v12@4:8@12@16`.

### `-[Terminal windowShouldClose:]` (`0x0000E3E8`)

The callback suppresses prompts during forced application quit, otherwise
updates the window's edited state from `MonitorProcs` and DirtMonitor. A dirty
window stops dirt timers, obtains up to ten 17-byte process-name records, and
shows localized Close Anyway/Cancel prompts. A cancelled alert returns NO;
accepting it advances the active window when this is the key or main window,
kills the shell, and asks `TerminalApp` to lazily recycle the terminal zone.
The source map covers the complete 1,328-byte PPC function. The monitor's
`getProcNames:onDevice:howMany:` selector returns an object; the caller uses
the count output and does not test a status byte. Its PPC implementation at
`0x510C` walks privileged processor sets, resolves task PIDs and process
records, and collects unique runnable command names for the requested terminal
device when the shell policy considers them unclean. It initializes the count
to zero and stops after ten names. Encoding: `c8@4:8@12`.

The shared record filter is implemented in `ProcessNames.c` and checks runnable
state, positive PID, the PTY device major (`4`) and requested minor, the shell
clean-command policy, duplicate command names, and the ten-entry bound. `DirtMonitor.m`
enumerates tasks from each privileged processor set with Mach
`processor_set_tasks`, resolves process records, and applies that filter. The
initializer retains the Mach notification port, sets its delegate, then registers
it on the current run loop in recovered PPC order.

For multiple process names, the PPC callback appends each 17-byte record
directly to the localized message and separates records with a newline. The
native implementation follows that flow; a formatted 17-byte temporary would
truncate or overflow the longest process name.

### `-[Terminal windowWillResize:toSize:]` (`0x0000D8F0`)

IDA confirms that the method temporarily writes byte value 4 at offset `0x24`
from `self->def`, calls the superclass resize constraint, restores the byte,
then sends `displayWindowStatus:` to `self` with `self` as the argument before
scheduling `windowHook::` after 0.5 seconds. The status selector is recovered
from the method-entry-relative TOC cell at `0x00038080`; the later selector
resolves to `performSelector:withObject:afterDelay:`.
`defaultsFromDB` allocates a `0x58`-byte record and
stores the fixed-pitch font-size float at `0x18`, confirming that `var12` is at
that offset and the separate byte at `0x24` is `var15` (`TitleBits`). The
loader assigns the record fields directly, without clearing the allocation or
creating a local autorelease pool, and copies the shell path after allocating
its zone buffer. The reconstruction preserves that PPC flow.
reconstructed `windowWillResize:toSize:` now temporarily sets `var15` to 4,
delegates grid constraints to `FieldView`, restores the preference bits, updates
the miniaturized-window status, and schedules the delayed reflow. Encoding:
`{?=ff}20@8:12@16{?=ff}20`.

### `-[Terminal setFileName:sharesFile:]` (`0x0000BE5C`)

IDA confirms that the method always stores the shares byte. If the incoming
filename pointer differs from the current pointer, it frees the old buffer,
copies a nonempty path into a buffer allocated from the view's zone (or clears
the field for null/empty input), then refreshes the window title with
`windowHook:height:cursorx`. The null-allocation branch invokes
`NSAssertionHandler.handleFailureInMethod:object:file:lineNumber:description:`
with `_cmd`, `self`, `Terminal.m`, line 133, and the embedded message
`Couldn't malloc space for file name.` The failure branch continues to the
binary's `strcpy` instruction if the handler returns. Its selector encoding is
`v9@4:8r*12c16`.

### `-[FieldView delegate]` (`0x00009284`)

The complete 16-byte PPC body returns the `delegate` instance variable without
retaining or transforming it. The source declaration is `- (id)delegate;` and
the implementation directly returns the stored pointer. The class layout
places `delegate` after `scroller`; the selector encoding is `@4@4:8`.

### `-[FieldView resetCursorRects]` (`0x00007C74`)

The PPC body obtains `[self bounds]` as an `NSRect` and registers it with
`addCursorRect:cursor:` using the AppKit I-beam cursor. The source preserves
that order and full rectangle. Selector strings are present in the reference at
`0x3CEAC` (`bounds`) and `0x3D210` (`addCursorRect:cursor:`); the cursor class
method `+[NSCursor IBeamCursor]` is declared in the bundled historical AppKit
header. Encoding: `v4@4:8`.

### `-[FieldView windowHook::]` (`0x00007CE0`)

The PPC body is a three-instruction no-op (`stwu`, stack restore, `blr`). Its
two `unsigned int` arguments have no effect. The base view implementation stays
empty; `Terminal` overrides the same selector to update the window title.
Encoding: `v12@4:8I12I16`.

### `-[FieldView setUpGState]` (`0x00007C00`)

The PPC body selects `screenfont` when non-nil, otherwise `font`, sends that
font `set`, then invokes the superclass `setUpGState`. The source keeps the
fallback and call order. The bundled historical headers declare `NSFont -set`
and `NSView -setUpGState`. Encoding: `v4@4:8`.

### `-[FieldView initWithFrame:]` (`0x00007610`) color defaults

The PPC initializer requests four colors from the `NSColor` class and copies
them into `backColor[0..2]`, `textColor[0..3]`, and `cursorColor`. The source
uses the selector order `whiteColor`, `blackColor`, `darkGrayColor`,
`lightGrayColor`, yielding white/black/dark-gray backgrounds, black/white/black/
dark-gray text, and a light-gray cursor. The four selector references are
adjacent in the PPC initializer and the matching selector strings occur in
that order in the reference. The same image's external bindings include
`_NSBlack`, `_NSDarkGray`, and `_NSLightGray`, which corroborates the palette
family but does not directly bind each selector cell to its string. The
selector-to-name association therefore remains an ordering-based inference.
Encoding:
`@20@4:8{?={?=ff}{?=ff}}12`.

### `-[FieldView setUpWithDefaults:]` (`0x00007910`)

IDA confirms that this 564-byte method clears `enablePSOutput` and the high
field-flag nibble, starts from the default window origin at offsets `0x1C` and
`0x20`, and checks the current main-window frame against the main screen size.
When the window is left of the recovered 160-point clearance and its top is above
the 160-point threshold, the next window origin is cascaded by 25 points. The
method applies that origin with `setFrameOrigin:`, sets flag `0x08000000`,
forwards defaults to `setDefaults:`, sets the window background to white,
displays it, and calls `makeKeyAndOrderFront:` with the view. It is implemented
in `FieldView.m`; PPC and i386 syntax checks pass. Its signature is
`v8@4:8^{?=cccccccSSc*@fIIC@ii[8@]i}12`.

### FieldView scroll navigation

### FieldView frame resizing

IDA pseudocode and PPC disassembly show that `-[FieldView setFrameSize:]`
(`0x7CEC`) saves the old row/column capacities and cursor offset, records
whether the viewport followed the bottom of scrollback, updates the scroller
around the superclass frame call, and computes new grid capacities from cell
size plus a shared frame inset. When column capacity changes, autowrap mode
controls whether wrapped rows are joined/split or all overlong rows are
truncated. The method then trims scrollback when disabled, adjusts the cursor
row and column, repairs viewport flags and selection columns, resizes text
buffers to `height + 1`, clears drawing caches, asks the Terminal to resize its
emulator, and refreshes.

The source now reads and writes row pointers through `terminalLineAt` and
`terminalLineSet`, and edits the wrap marker through `terminalLineSetWrapped`.
These helpers preserve the reference's 8-byte chunk entry on both 32-bit
targets. `TerminalChunkLineEntry32` names the recovered 4-byte pointer, marker
byte at offset 4, and three padding bytes; the host fixture verifies this
layout and that scroll operations preserve complete row entries.

The PPC constant pool resolves the shared frame inset to `6.0f` at `0x34648`
(also referenced by `sizeEmulationTo::` at `0x34654`). At `0x3464C` it stores
the double `2^52 + 2^31`, used when converting byte cell metrics by XORing the
byte with `0x80000000`; at `0x34658` it stores `2^52`, used for unsigned
integer-to-double conversion. `setFrameSize:` divides each frame dimension
minus the six-point inset by the converted cell dimension, then truncates to
an unsigned byte. `sizeEmulationTo::` clamps requested columns and rows to 255
and converts their products with the byte cell metrics using the `2^52` bias.
It obtains the window frame and view
bounds, adjusts the window width and height, keeps the top edge anchored, then
calls `setFrame:display:NO` and `display`. That geometry is implemented in
`FieldView.m`. The stateful `setFrameSize:` body is implemented from the PPC
row, cursor, scrollback, selection, and drawing-cache operations; its initial
selectors resolve to `removeScroller` and `reinstateScroller`. Those methods
now disable window flushing, adjust the window content width around the
scroller's 1-point gutter, update FieldView bounds without recursively
dispatching `setFrameSize:`, detach or restore the scroller, and restore
autoresizing/display. The `removeScroller` path also clears selection, scrolls
to the live bottom, and conditionally calls `pruneNumLinesTo:` when supported.
The accessor evidence also
confirms there is no separate `width` ivar:
`width` returns the column-count ivar at object offset `0xD8`, and `height`
returns the row-count ivar at `0xD9`. `FieldView.h` now omits the extra byte so
subsequent ivars retain their recovered PPC offsets.

`-[FieldView windowDidBecomeMain:]` (`0x91D4`) sends `new` to `NSFontPanel`,
then `setSelectedFont:isMultiple:` to the returned panel with the view's `font`
ivar and zero. PPC `__sel_backref` rows `0x43C88` and `0x44B70` bind callsite
cells `0x37EDC` and `0x37EE0` to those selector strings. The sender argument is
unused; `FieldView.m` now matches the binary.

`lineUp` and `lineDown` (`0x1D5B0`, `0x1D5F4`) move `topline` by one only when
the destination remains within scrollback, then call `scrollTo:`. `pageUp` and
`pageDown` (`0x1D4D4`, `0x1D534`) move by `cursorx - 2`, clamping at zero or
`lines->count - cursorx` respectively. The original unsigned arithmetic and
branch conditions are retained. The shared selector resolves to `scrollTo:`
at `0x37EF4`, and the argument arithmetic matches the method pseudocode.

`scrollTo:` (`0x1D464`) locks focus, invokes `_scrollTo:`, unlocks focus, and
then reflects the position. The PPC `__sel_backref` rows resolve `lockFocus`
at cell `0x37E74` (`0x43B58`), `_scrollTo:` at `0x38528` (`0x428E8`),
`unlockFocus` at `0x37E90` (`0x45198`), and `reflectPosition` at `0x3816C`
(`0x44158`). `FieldView.m` now follows that binary sequence.
`_scrollTo:` (`0x1D250`) clamps to `lines->count - cursorx`, changes `topline`,
and updates the two viewport-state flag bits. For overlapping viewports it
dispatches `_srhscrollup:to:lines:` or `_srhscrolldown:to:lines:` with the
movement delta; for a non-overlapping jump it dispatches `_srhclear:to:`.
Those three helpers now preserve the PPC clipping, selection highlight, and
cursor-restoration decisions. Their incremental repaint path reaches the
implemented `_rawscrollup:to:lines:` and `_rawscrolldown:to:lines:` methods;
full viewport repaint queues rectangles and text for `refreshscreen`. IDA
confirms the raw scroll flag/count gates, DPS blit geometry, six-strip remainder
distribution, background fills, window flushes, and conditional PostScript
wait. The source methods match the PPC control flow; rendered guest behavior
remains runtime-unverified.

`_rawclear:to:` (`0x19F10`) sets `backColor[0]` and fills an `NSRect` at x=0,
y=`first * bheight`, with width=`height * bwidth` and height=`(last - first) *
bheight`. This geometry is directly represented by the PPC integer-to-float
conversions and `NSRectFill` call. The source map matches the implementation to
the complete 316-byte PPC function.

IDA disassembly shows both raw scroll routines branch on `aflags & 0x8000` and
the requested line count. The active branch either invokes `__PSsplat` when
`drawsLineAtRightEdge` is set or paints six pixel-height strips using the
background color. The per-strip path sends `[self window]` followed by
`[window flushWindow]`; selector-table references and receiver types support
those sends. The optional `PSWait` follows the edge-drawing condition. The
source methods at `FieldView.m:1695` and `:1771` match this PPC control flow.
The reconstructed `__PSsplat` helper (`0x22F20`) copies the 88-byte DPS object
template, writes six big-endian float operands at the observed offsets, and
dispatches it through the current context's `BinObjSeqWrite` procedure. Guest
rendering and i386 parity remain unverified.

`-[FieldView refreshscreen]` (`0x1A6C8`) flushes up to three background-rectangle
chunks, then four text styles. For each nonempty text chunk it sets the text
color, fills and clears queued underline rectangles, emits text entries in
reverse order, and clears the chunk count. Style index 2 uses a second `FVshow`
pass when flag `0x00080000` is set. This control flow is implemented in
`FieldView.m`; AppKit rendering remains unverified at runtime.

`_sscrollup:to:lines:` (`0x1A04C`) and `_sscrolldown:to:lines:` (`0x1A110`)
clip absolute row intervals to `[topline, topline + cursorx)`, convert the
clipped rows to viewport-relative coordinates, and compare the visible span
with the requested count. When the span is large enough, they call the matching
raw scroll method and clear the newly exposed rows with `_rawclear:to:`; when
it is smaller, they clear the clipped interval directly. The three- and
two-argument message signatures match the PPC selector strings for the raw
scroll and clear methods.

The per-function owner and address are in `function-worklist.md`. Recover each
method's complete declarations, class/ivar layouts, ownership, error behavior,
and build-module owner from encoding strings, class metadata, callers, NIBs, and
disassembly before implementation. The selector/type inventory is a PPC ABI
baseline; i386 encodings and layouts must be recovered from a matching reference
or validated against the compiler ABI. The worklist marks the few helper routes
that still need caller confirmation.

`_get_process_info_from_pid` (`0x21220`) issues the four-item MIB
`{CTL_KERN, KERN_PROC, KERN_PROC_PID, pid}`. On first use, it queries the
required buffer size, allocates a cached process-record buffer, then performs
the PID query. Either failed `sysctl` call prints `Failure calling sysctl` and
leaves the output unchanged. Success copies the process ID, process group, terminal process group,
terminal device, runnable flag (`p_stat == 2`, `SRUN`), and 16 command bytes. The IDA
pseudocode confirms PPC record offsets `+24`, `+392`, `+396`, `+404`, `+20`, and
`+163` respectively. Caller analysis confirms the word copied from `+404` is
the terminal device: the `DirtMonitor` callers inspect its major byte (`4`) and
PTY minor byte, while the name begins at output offset `+20`. The `+396` output
slot is preserved as the terminal-process-group value; callers inspected do
not consume it. The recovered SDK's current `kinfo_proc` order differs, so PPC
uses the observed record offsets directly. The i386 path uses the recovered
SDK's typed `p_pid`, `e_pgid`, `e_tpgid`, `e_tdev`, `p_stat`, and `p_comm`
fields; there is no matching i386 Terminal binary to confirm those offsets.

`Preferences` now declares the IDA UDT's 32-bit ivar sequence, including the
eight-entry controller and pane arrays, `currentTerminal` at `0xAC`, and the
trailing `shouldEnableOKIfPossible` byte at `0xB4`. Compiler static assertions
against `@defs(Preferences)` confirm `okButton` at `0x48`, `currentTerminal` at
`0xAC`, `installedPane` at `0xB0`, and the flag at `0xB4`. `okButton` and
`currentTerminal` are direct-return accessors matching their complete 16-byte
PPC bodies.

`-[TerminalApp quickTitleOK:]` (`0x14A28`) and `quickTitleCancel:` (`0x14A80`)
send the sender to `quickTitlePanel` with `orderOut:`, then stop the app's modal
session with result 0 for OK or 1 for Cancel. The external selector values
resolve exactly to `orderOut:` and `stopModalWithCode:` in the supplied AppKit
database; AppKit selector-reference xrefs point to both names. Their complete
source bodies are implemented in `TerminalApp.m` and control-flow-confirmed in
the PPC ledger.

`-[Preferences showPrefWindow:]` (`0x237C0`) sends `makeKeyAndOrderFront:self`
to its window, then sends `firstVisible:self` to `installedController` when that
outlet is non-nil. The local `firstVisible:` selector string and the PPC branch
guard match the implemented body in `Preferences.m`.

`-[Preferences changePane:]` (`0x2381C`) reads `selectedTag` from its sender and
passes the integer to `reflectChoiceOfPane:`. `selectedTag` comes from the
`NSControl` API. The method updates the pane selector title from the menu item
carrying that tag.

`-[Preferences reflectChoiceOfPane:]` (`0x2386C`) checks the indexed pane
against `installedPane`, updates the pane selector title from its tagged menu
item, runs `lastVisible:` on the outgoing controller, retains and removes the old
view, and installs the new pane and controller. It centers the new view from the
container and pane bounds differences, invokes
`firstVisible:`, and loads either current Terminal defaults or saved defaults.
AppKit and Foundation selector references point outside the Terminal image;
their names resolve in the supplied framework databases after applying the
0x1000 image slide.

`-[Preferences ok:]` (`0x240FC`) checks its controller and terminal, obtains
Terminal defaults, passes them to the active controller with `setStruct:`, and
persists them with `setDefaults:`. `-[Preferences windowShouldClose:]`
(`0x244A8`) clears the Preferences-visible flag and calls `lastVisible:` when
a controller is installed. `-[Preferences notifyController:withArg:]`
(`0x24688`) uses `respondsToSelector:` before forwarding with
`performSelector:withObject:`.

`-[Preferences doFlush]` (`0x23D88`) sends `enableFlushWindow` to the
preferences window, obtains its content view, and sends `setNeedsDisplay:YES`.
All three external selector references resolve exactly in the supplied AppKit
image after applying the 0x1000 slide.

The Preferences window key callbacks forward their notifications to the
installed controller only when it responds to the matching callback selector.
`windowWillClose:` clears `currentTerminal` by calling
`setCurrentTerminal:nil`.

`-[Preferences showDefaultX:]` (`0x2435C`) forwards to `showDefault:NO` using
the local `showDefault:` selector reference.

`-[Preferences handleReturnByProxy:]` (`0x24510`) checks `okButton.isEnabled`
and forwards the sender to `okButton.performClick:` only when enabled. Both
AppKit selectors resolve exactly after applying the validated 0x1000 image
slide.

`-[WindowController lastVisible:]` (`0x29D34`) obtains the window from
`fontField` and sends `makeFirstResponder:nil`, ending field editing when the
window-controller pane is hidden.

`ShellController` has two IDA-confirmed outlets, `sourceCheck` at offset `0x4`
and `shellForm` at `0x8`, matching its Preferences nib declaration. Its
`lastVisible:` override (`0x26A80`) is an empty method.

`EmulationController` has IDA-confirmed outlets for the translation, alternate
character, keypad, strict-mode, alternate-message, and check controls at offsets
`0x4` through `0x1C`. Its three revert-state bytes occupy `0x20` through `0x22`, followed by one byte of alignment padding in its 40-byte layout.
`firstVisible:` (`0x24D38`) sends `selectCellWithTag:31` to its sender, restoring
the Emulation row when the preferences pane becomes visible. `lastVisible:`
(`0x24D74`) is an empty method. `suggest:` calls `setMeta:opts:::lock:` with
`(-1, 1, 0, 0, 0)`. That setter saves the previous metadata and three option
bytes when its lock argument is true, then forwards the four displayed values
to `displayValues::::`. `revert:` forwards the saved values with locking off.
`setStruct:` writes the translation, keypad, and strict checkbox states to the
defaults record. It uses `revertMeta` for the meta byte while `altMsg` exists;
otherwise it reads the selected cell's tag from `altMatrix`.
`showDefault:` synchronizes `_theDefaultsObject`, reads `Meta`, `Translate`,
`Keypad`, and `StrictEmulation`, then calls `setMeta:opts:::lock:` with its
`show` argument as the lock flag.
`displayValues::::` updates the option controls and clears `checkMatrix`. Meta
values `-1`, `0`, and `27` select their `altMatrix` tags; if the custom `altMsg`
field is enabled, it aborts editing and resigns first responder first. Other
meta values leave an existing custom field untouched, or set the title of
`altBox` to `altMsg` when that field is absent. The box is then redrawn.
`setDefault` writes the three checkbox states to their user-default keys and
writes Meta from `revertMeta` when `altMsg` exists, or from the selected
`altMatrix` cell tag otherwise.
`setFromStruct:` forwards the defaults record's Meta, Translate, Keypad, and
StrictEmulation values to `setMeta:opts:::lock:` with locking enabled, capturing
the prior controller state before applying the record.


`-[Preferences init]` now initializes the Preferences nib and populates the
controller and pane arrays in the index order recovered from the PPC IDA
pseudocode, then sets up buttons and selects pane 0. IDA's selector strings at
`0x3D6A8`, `0x3D6B8`, `0x3D6D0`, and `0x3D6F0` confirm the source's
`bundleForClass:`, `pathForResource:ofType:`,
`dictionaryWithObjectsAndKeys:`, and `loadNibFile:externalNameTable:withZone:`
calls. The initializer passes the `Preferences` nib path, an `NSOwner` table,
and `[self zone]` to the bundle loader; `Preferences.m` matches this PPC call
sequence.

`-[Preferences setUpButtons:]` stores the OK policy bit, sets each preference
button's enabled state from the corresponding flag, and attaches or removes the
button matrix according to the binary's recovered flag mask.

The Preferences Revert, Set Default, Suggest, and Show Default actions forward
to the installed pane controller. The three redraw actions suppress window
flushing during the controller update and then mark the content view dirty.

Preferences now tracks the current Terminal window through a close-notification
observer. On terminal activation it sends that terminal's defaults to the
installed preference controller and restores the configured OK-button state.

When the active terminal resigns main status, Preferences disables OK and
clears its current terminal. If its window remains visible, it defers the flush
re-enable and redraw by 0.1 seconds.

## MiscController instance layout

The PPC IDA type `MiscController` is 44 bytes under the 32-bit ABI. After the 4-byte superclass pointer, its eight outlets are `autoFocusCheck` at 0x04, `wrapCheck` at 0x08, `lineLimitField` at 0x0C, `linesUnlimited` at 0x10, `linesLimited` at 0x14, `scrollbackEnableCheck` at 0x18, `okButton` at 0x1C, and `otherOptionsMatrix` at 0x20. Revert state occupies `revertScrollback` at 0x24, `revertAutoFocus` at 0x25, `revertAutowrap` at 0x26, one padding byte, and `revertSaveLines` at 0x28.

The defaults record uses `var3` for Scrollback, `var1` for Autowrap, `var0` for AutoFocus, and `var17` for SaveLines. These offsets and selector argument encodings are confirmed from PPC IDA metadata; no i386 Terminal executable was supplied for an independent comparison.


## Shell preference controller behavior

`ShellController` has `sourceCheck` and `shellForm` outlets at offsets `0x4` and `0x8`. `showDefault:` synchronizes defaults, reads the application's selected shell and the `SourceDotLogin` Boolean, and applies them to the form and checkbox. `firstVisible:` configures 24 preference buttons and displays those values. `checkSettings` removes the command suffix at the first space, tab, newline, or carriage return before checking the path. It accepts only an existing executable regular file; missing, inaccessible, stat-failing, and non-regular paths each show the original localized alert. `shellChanged:` persists the form value only after validation; `sourceDotLoginChanged:` persists the checkbox state.

The original PPC `ShellController` and `ProcessMonitorController` `revert`, `setDefault`, `suggest`, and `setStruct:` implementations all raise `NSInvalidArgumentException` with the format `*** Method not implemented: %s` and the current selector name. The exception name is the `_NSInvalidArgumentException` import; the format string is the constant at `0x32170`. These are intentional reference behaviors, so reconstructed source preserves the exception. Both classes' `setFromStruct:` and `lastVisible:` are empty overrides.

## Startup preference controller

`StartupController` has NIB outlets `actionMatrix`, `fastAutolaunchCheck`, and `pathForm` at PPC offsets `0x4`, `0x8`, and `0xC`. Its 32-byte object stores the revert action at `0x10`, zone-owned revert filename at `0x14`, and revert fast-launch byte at `0x18`, followed by three padding bytes. `showDefault:` reads integer `StartupAction` (clamped and persisted to 0–2), string `StartupFile`, and Boolean `FastLaunch`; `setAction:file:fastLaunch:lockRevert:` updates controls and replaces the revert snapshot only when locked. `checkSettings` checks read access only for action tag 2, showing the exact localized missing-path, nonexistent-path, and unreadable-path alerts. `pathWasSet:` selects tag 2 for a nonempty path and persists action/file only after accepted validation. `fastStartupChanged:` and `startupActionChanged:` persist their controls. `forceSetDefault` writes all three startup values; `setDefault` returns self without effect. `setFromStruct:` and `setStruct:` are empty. The PPC body inventory confirms these selectors and the 32-bit field offsets; source syntax passes for both targets.
