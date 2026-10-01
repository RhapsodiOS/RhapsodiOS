# Recovered Objective-C ABI

Reference: `C:\Users\raynorpat\Downloads\test\Applications_ppc\Administration\ProcessViewer.app\ProcessViewer`; SHA-256 `4a08718bd848e733a7e4ef8ef8f7b9a282a2fe56c8d38b14f23622c9983b7179`. All offsets and encodings below are from the supplied big-endian PowerPC image. Objective-C method IMP addresses were matched to the named `__TEXT,__text` symbols; the runtime metadata index alone omits selector strings for part of this table. Raw encodings preserve the 32-bit runtime offsets.

Class metadata yielded 7 classes and 78 method records, including the private category. Each listed IMP matched an executable text symbol: 78/78.

## `Inspector` : `NSObject`

Instance size: 92 bytes. Objective-C module: `Inspector.m`.

| Ivar | Type encoding | Offset |
|---|---|---:|
| `_process` | `@"Process"` | `0x4` |
| `splitView` | `@"NSSplitView"` | `0x8` |
| `tabContainer` | `@"NSView"` | `0xc` |
| `invalidSelectionView` | `@"NSView"` | `0x10` |
| `tabView` | `@"NSTabView"` | `0x14` |
| `pidView` | `@"NSView"` | `0x18` |
| `statsView` | `@"NSView"` | `0x1c` |
| `argsView` | `@"NSView"` | `0x20` |
| `invalidSelectionText` | `@"NSTextField"` | `0x24` |
| `pathField` | `@"NSTextField"` | `0x28` |
| `argumentsTable` | `@"NSTableView"` | `0x2c` |
| `pidField` | `@"NSTextField"` | `0x30` |
| `parentField` | `@"NSTextField"` | `0x34` |
| `processGroupField` | `@"NSTextField"` | `0x38` |
| `savedUidField` | `@"NSTextField"` | `0x3c` |
| `terminalField` | `@"NSTextField"` | `0x40` |
| `realMemoryField` | `@"NSTextField"` | `0x44` |
| `virtualMemoryField` | `@"NSTextField"` | `0x48` |
| `timeField` | `@"NSTextField"` | `0x4c` |
| `_isVisible` | `c` | `0x50` |
| `_minTabContainerHeight` | `f` | `0x54` |
| `_minMainContainerHeight` | `f` | `0x58` |

| Method symbol | Raw type encoding | IMP |
|---|---|---:|
| `-[Inspector _loadInspectorNib]` | `v4@4:8` | `0x21c4` |
| `-[Inspector _processTanked:]` | `v8@4:8@12` | `0x2a34` |
| `-[Inspector _setCurrentView:]` | `v5@4:8c12` | `0x251c` |
| `-[Inspector _setProcess:]` | `v8@4:8@12` | `0x2954` |
| `-[Inspector awakeFromNib]` | `v4@4:8` | `0x2078` |
| `-[Inspector dealloc]` | `v4@4:8` | `0x248c` |
| `-[Inspector isVisible]` | `c4@4:8` | `0x28c4` |
| `-[Inspector numberOfRowsInTableView:]` | `i8@4:8@12` | `0x2e0c` |
| `-[Inspector setSplitView:]` | `v8@4:8@12` | `0x20ec` |
| `-[Inspector setVisible:]` | `v5@4:8c12` | `0x259c` |
| `-[Inspector showInfoForMultipleSelection]` | `v4@4:8` | `0x2d88` |
| `-[Inspector showInfoForNoSelection]` | `v4@4:8` | `0x2d04` |
| `-[Inspector showInfoForProcess:]` | `v8@4:8@12` | `0x2a6c` |
| `-[Inspector splitView:constrainMinCoordinate:maxCoordinate:ofSubviewAt:]` | `v20@4:8@12^f16^f20i24` | `0x2840` |
| `-[Inspector splitView:resizeSubviewsWithOldSize:]` | `v16@4:8@12{?=ff}16` | `0x2eac` |
| `-[Inspector tabView:didSelectTabViewItem:]` | `v12@4:8@12@16` | `0x28d8` |
| `-[Inspector tableView:objectValueForTableColumn:row:]` | `@16@4:8@12@16i20` | `0x2e60` |

## `Process` : `NSObject`

Instance size: 32 bytes. Objective-C module: `Process.m`.

| Ivar | Type encoding | Offset |
|---|---|---:|
| `_pid` | `i` | `0x4` |
| `_ppid` | `i` | `0x8` |
| `_pgid` | `i` | `0xc` |
| `_saved_euid` | `I` | `0x10` |
| `_real_uid` | `I` | `0x14` |
| `_args` | `@"NSArray"` | `0x18` |
| `_values` | `@"NSMutableDictionary"` | `0x1c` |

| Method symbol | Raw type encoding | IMP |
|---|---|---:|
| `+[Process enumerateProcessesAndFetch:]` | `@5@4:8c12` | `0x331c` |
| `+[Process getSortContext:forKey:ascending:]` | `c13@4:8^{?=@cc}12@16c20` | `0x3924` |
| `+[Process initialize]` | `v4@4:8` | `0x31a4` |
| `-[Process arguments]` | `@4@4:8` | `0x3c54` |
| `-[Process compare:context:]` | `i12@4:8@12^{?=@cc}16` | `0x3e84` |
| `-[Process dealloc]` | `v4@4:8` | `0x3b2c` |
| `-[Process description]` | `@4@4:8` | `0x3a9c` |
| `-[Process dictionaryRepresentation]` | `@4@4:8` | `0x404c` |
| `-[Process initWithPid:]` | `@8@4:8i12` | `0x39fc` |
| `-[Process invalidate]` | `v4@4:8` | `0x3b9c` |
| `-[Process objectForKey:]` | `@8@4:8@12` | `0x3af4` |
| `-[Process parentProcessId]` | `I4@4:8` | `0x3e64` |
| `-[Process processGroupId]` | `I4@4:8` | `0x3e74` |
| `-[Process processId]` | `I4@4:8` | `0x3e44` |
| `-[Process savedUserId]` | `I4@4:8` | `0x3e54` |
| `-[Process tty]` | `@4@4:8` | `0x3c14` |

## `MapTableEnumerator` : `NSEnumerator`

Instance size: 16 bytes. Objective-C module: `Process.m`.

| Ivar | Type encoding | Offset |
|---|---|---:|
| `_mapEnum` | `{?="_pi"I"_nk"^v"_bs"^v}` | `0x4` |

| Method symbol | Raw type encoding | IMP |
|---|---|---:|
| `+[MapTableEnumerator _newWithMapTable:]` | `@8@4:8^{?=}12` | `0x30e0` |
| `-[MapTableEnumerator nextObject]` | `@4@4:8` | `0x3160` |

## `ProcessControl` : `NSResponder`

Instance size: 68 bytes. Objective-C module: `ProcessControl.m`.

| Ivar | Type encoding | Offset |
|---|---|---:|
| `processTable` | `@"ProcessTableView"` | `0x8` |
| `sortOrderButton` | `@"NSButton"` | `0xc` |
| `filterText` | `@"NSTextField"` | `0x10` |
| `typePopup` | `@"NSPopUpButton"` | `0x14` |
| `rateField` | `@"NSTextField"` | `0x18` |
| `countField` | `@"NSTextField"` | `0x1c` |
| `timer` | `@"NSTimer"` | `0x20` |
| `allColumns` | `@"NSArray"` | `0x24` |
| `fieldNames` | `@"NSMutableArray"` | `0x28` |
| `filteredProcesses` | `@"NSMutableArray"` | `0x2c` |
| `allProcesses` | `@"NSMutableArray"` | `0x30` |
| `optionsDictionary` | `@"NSDictionary"` | `0x34` |
| `moreInfoSwitch` | `@"NSButton"` | `0x38` |
| `inspector` | `@"Inspector"` | `0x3c` |
| `processTypes` | `@"NSArray"` | `0x40` |

| Method symbol | Raw type encoding | IMP |
|---|---|---:|
| `-[ProcessControl applicationDidFinishLaunching:]` | `v8@4:8@12` | `0x477c` |
| `-[ProcessControl assignActions]` | `v4@4:8` | `0x4b94` |
| `-[ProcessControl bumpRate:]` | `v8@4:8@12` | `0x55d8` |
| `-[ProcessControl changeSortOrder:]` | `v8@4:8@12` | `0x647c` |
| `-[ProcessControl controlTextDidChange:]` | `v8@4:8@12` | `0x63c8` |
| `-[ProcessControl dealloc]` | `v4@4:8` | `0x46ec` |
| `-[ProcessControl exportProcessList:]` | `v8@4:8@12` | `0x58ec` |
| `-[ProcessControl getProcesses:]` | `v8@4:8@12` | `0x4df4` |
| `-[ProcessControl hideColumn:]` | `v8@4:8@12` | `0x5a8c` |
| `-[ProcessControl init]` | `@4@4:8` | `0x4558` |
| `-[ProcessControl killProcessWithConfirmation:]` | `v8@4:8@12` | `0x5d3c` |
| `-[ProcessControl killProcesses:]` | `v8@4:8@12` | `0x5c94` |
| `-[ProcessControl numberOfRowsInTableView:]` | `i8@4:8@12` | `0x6380` |
| `-[ProcessControl print:]` | `v8@4:8@12` | `0x5a24` |
| `-[ProcessControl refilter:]` | `v8@4:8@12` | `0x550c` |
| `-[ProcessControl resetRate:]` | `v8@4:8@12` | `0x5548` |
| `-[ProcessControl resort:]` | `v8@4:8@12` | `0x5424` |
| `-[ProcessControl setShowType:]` | `v8@4:8@12` | `0x4d50` |
| `-[ProcessControl shouldShowProcess:]` | `c8@4:8@12` | `0x4c48` |
| `-[ProcessControl showAboutPanel:]` | `v8@4:8@12` | `0x5824` |
| `-[ProcessControl showAllColumns:]` | `v8@4:8@12` | `0x5b40` |
| `-[ProcessControl showMoreInfoAboutSelection:]` | `v8@4:8@12` | `0x571c` |
| `-[ProcessControl tableView:objectValueForTableColumn:row:]` | `@16@4:8@12@16i20` | `0x6278` |
| `-[ProcessControl tableViewSelectionDidChange:]` | `v8@4:8@12` | `0x5728` |
| `-[ProcessControl toggleMoreInfo:]` | `v8@4:8@12` | `0x5c08` |
| `-[ProcessControl updateForSortChange:filterChange:]` | `v9@4:8c12c16` | `0x4fb8` |
| `-[ProcessControl updateRate]` | `v4@4:8` | `0x4ea4` |
| `-[ProcessControl validateMenuItem:]` | `c8@4:8@12` | `0x6508` |
| `-[ProcessControl windowDidResize:]` | `v8@4:8@12` | `0x6400` |
| `-[ProcessControl windowShouldClose:]` | `c8@4:8@12` | `0x6438` |

## `ProcessType` : `NSObject`

Instance size: 16 bytes. Objective-C module: `ProcessType.m`.

| Ivar | Type encoding | Offset |
|---|---|---:|
| `_name` | `@"NSString"` | `0x4` |
| `_key` | `@"NSString"` | `0x8` |
| `_values` | `@"NSSet"` | `0xc` |

| Method symbol | Raw type encoding | IMP |
|---|---|---:|
| `+[ProcessType allProcessTypes]` | `@4@4:8` | `0x6928` |
| `-[ProcessType dealloc]` | `v4@4:8` | `0x6af8` |
| `-[ProcessType initWithDictionary:strings:]` | `@12@4:8@12@16` | `0x6b58` |
| `-[ProcessType localizedName]` | `@4@4:8` | `0x6dec` |
| `-[ProcessType matchesProcess:]` | `c8@4:8@12` | `0x6d74` |
| `-[ProcessType name]` | `@4@4:8` | `0x6dfc` |

## `ProcessTableHeaderView` : `NSTableHeaderView`

Instance size: 116 bytes. Objective-C module: `ProcessTableView.m`.

| Ivar | Type encoding | Offset |
|---|---|---:|

| Method symbol | Raw type encoding | IMP |
|---|---|---:|
| `-[ProcessTableHeaderView _modifySelectionWithEvent:onColumn:]` | `v12@4:8@12i16` | `0x7034` |
| `-[ProcessTableHeaderView drawRect:]` | `v20@4:8{?={?=ff}{?=ff}}12` | `0x6f10` |

## `ProcessTableView` : `NSTableView`

Instance size: 232 bytes. Objective-C module: `ProcessTableView.m`.

| Ivar | Type encoding | Offset |
|---|---|---:|
| `_highlightedColumnIdentifier` | `@` | `0xe4` |

| Method symbol | Raw type encoding | IMP |
|---|---|---:|
| `-[ProcessTableView highlightedColumnIdentifier]` | `@4@4:8` | `0x6e94` |
| `-[ProcessTableView initWithCoder:]` | `@8@4:8@12` | `0x6e0c` |
| `-[ProcessTableView setHighlightedColumn:]` | `v8@4:8i12` | `0x6ea4` |

## Category `Process(Private)`

| Method symbol | Raw type encoding | IMP |
|---|---|---:|
| `-[Process(Private) _setCString:forKey:]` | `v12@4:8r*12@16` | `0x4350` |

## Category `Process(Private)`

| Method symbol | Raw type encoding | IMP |
|---|---|---:|
| `-[Process(Private) _update]` | `v4@4:8` | `0x4178` |

## Application C functions

IDA 9.4 Hex-Rays output for the five non-Objective-C application functions is
retained externally as analysis evidence. The signatures below transcribe its
PowerPC decompilation; pointer aliases and source-level prototype spellings
remain to be verified against caller instructions before writing headers.

| Function | Decompiler signature | Address |
|---|---|---:|
| `_floatFromNumberWithSuffix` | `double (id)` | `0x4414` |
| `_sortFunction` | `id (void *, int, int)` | `0x4514` |
| `__readTypesFromFile` | `void (void *, int, void *)` | `0x6594` |
| `_main` | `int (int argc, const char **argv, const char **envp)` | `0x71e4` |
| `_NameForUID` | `void * (uid_t)` | `0x7204` |

`Process`'s sort context encoding is `^{?=@cc}`. The recovered record contains
an Objective-C sort key, a one-byte comparison kind, and a one-byte ascending
flag on PowerPC. Confirm natural C structure declaration and i386 alignment in
the target compiler before using it across architectures.
