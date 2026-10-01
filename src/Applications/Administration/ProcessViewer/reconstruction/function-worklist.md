# PowerPC function worklist

Reference SHA-256: `4a08718bd848e733a7e4ef8ef8f7b9a282a2fe56c8d38b14f23622c9983b7179`. IDA 9.4, 128 function records, complete PowerPC text-section inventory. Application symbols are mapped by class/helper name to the embedded original module filenames; non-application startup/import stubs remain explicit. Direct `bl` references are recovered from IDA-exported instruction operands.

| Address | Size | Symbol | Proposed owner / disposition | Direct callers |
|---:|---:|---|---|---|
| `0x1e54` | 48 | `start` | `runtime/linker` | — |
| `0x1e88` | 320 | `__start` | `runtime/linker` | start |
| `0x1fc8` | 76 | `__call_mod_init_funcs` | `runtime/linker` | __start |
| `0x2014` | 60 | `__dyld_init_check` | `runtime/linker` | __start |
| `0x2050` | 24 | `dyld_stub_binding_helper` | `runtime/linker` | — |
| `0x2068` | 16 | `__dyld_func_lookup` | `runtime/linker` | __call_mod_init_funcs |
| `0x2078` | 116 | `-[Inspector awakeFromNib]` | `Inspector.m` | — |
| `0x20ec` | 216 | `-[Inspector setSplitView:]` | `Inspector.m` | — |
| `0x21c4` | 712 | `-[Inspector _loadInspectorNib]` | `Inspector.m` | — |
| `0x248c` | 144 | `-[Inspector dealloc]` | `Inspector.m` | — |
| `0x251c` | 128 | `-[Inspector _setCurrentView:]` | `Inspector.m` | — |
| `0x259c` | 676 | `-[Inspector setVisible:]` | `Inspector.m` | — |
| `0x2840` | 132 | `-[Inspector splitView:constrainMinCoordinate:maxCoordinate:ofSubviewAt:]` | `Inspector.m` | — |
| `0x28c4` | 20 | `-[Inspector isVisible]` | `Inspector.m` | — |
| `0x28d8` | 124 | `-[Inspector tabView:didSelectTabViewItem:]` | `Inspector.m` | — |
| `0x2954` | 224 | `-[Inspector _setProcess:]` | `Inspector.m` | — |
| `0x2a34` | 56 | `-[Inspector _processTanked:]` | `Inspector.m` | — |
| `0x2a6c` | 664 | `-[Inspector showInfoForProcess:]` | `Inspector.m` | — |
| `0x2d04` | 132 | `-[Inspector showInfoForNoSelection]` | `Inspector.m` | — |
| `0x2d88` | 132 | `-[Inspector showInfoForMultipleSelection]` | `Inspector.m` | — |
| `0x2e0c` | 84 | `-[Inspector numberOfRowsInTableView:]` | `Inspector.m` | — |
| `0x2e60` | 76 | `-[Inspector tableView:objectValueForTableColumn:row:]` | `Inspector.m` | — |
| `0x2eac` | 564 | `-[Inspector splitView:resizeSubviewsWithOldSize:]` | `Inspector.m` | — |
| `0x30e0` | 128 | `+[MapTableEnumerator _newWithMapTable:]` | `Process.m` | — |
| `0x3160` | 68 | `-[MapTableEnumerator nextObject]` | `Process.m` | — |
| `0x31a4` | 376 | `+[Process initialize]` | `Process.m` | — |
| `0x331c` | 1544 | `+[Process enumerateProcessesAndFetch:]` | `Process.m` | — |
| `0x3924` | 216 | `+[Process getSortContext:forKey:ascending:]` | `Process.m` | — |
| `0x39fc` | 160 | `-[Process initWithPid:]` | `Process.m` | — |
| `0x3a9c` | 88 | `-[Process description]` | `Process.m` | — |
| `0x3af4` | 56 | `-[Process objectForKey:]` | `Process.m` | — |
| `0x3b2c` | 112 | `-[Process dealloc]` | `Process.m` | — |
| `0x3b9c` | 120 | `-[Process invalidate]` | `Process.m` | — |
| `0x3c14` | 64 | `-[Process tty]` | `Process.m` | — |
| `0x3c54` | 496 | `-[Process arguments]` | `Process.m` | — |
| `0x3e44` | 16 | `-[Process processId]` | `Process.m` | — |
| `0x3e54` | 16 | `-[Process savedUserId]` | `Process.m` | — |
| `0x3e64` | 16 | `-[Process parentProcessId]` | `Process.m` | — |
| `0x3e74` | 16 | `-[Process processGroupId]` | `Process.m` | — |
| `0x3e84` | 456 | `-[Process compare:context:]` | `Process.m` | — |
| `0x404c` | 300 | `-[Process dictionaryRepresentation]` | `Process.m` | — |
| `0x4178` | 472 | `-[Process(Private) _update]` | `Process.m` | — |
| `0x4350` | 196 | `-[Process _setCString:forKey:]` | `Process.m` | — |
| `0x4414` | 256 | `_floatFromNumberWithSuffix` | `Process.m` | — |
| `0x4514` | 68 | `_sortFunction` | `Process.m` | — |
| `0x4558` | 404 | `-[ProcessControl init]` | `ProcessControl.m` | — |
| `0x46ec` | 144 | `-[ProcessControl dealloc]` | `ProcessControl.m` | — |
| `0x477c` | 1048 | `-[ProcessControl applicationDidFinishLaunching:]` | `ProcessControl.m` | — |
| `0x4b94` | 180 | `-[ProcessControl assignActions]` | `ProcessControl.m` | — |
| `0x4c48` | 264 | `-[ProcessControl shouldShowProcess:]` | `ProcessControl.m` | — |
| `0x4d50` | 164 | `-[ProcessControl setShowType:]` | `ProcessControl.m` | — |
| `0x4df4` | 176 | `-[ProcessControl getProcesses:]` | `ProcessControl.m` | — |
| `0x4ea4` | 276 | `-[ProcessControl updateRate]` | `ProcessControl.m` | — |
| `0x4fb8` | 1132 | `-[ProcessControl updateForSortChange:filterChange:]` | `ProcessControl.m` | — |
| `0x5424` | 232 | `-[ProcessControl resort:]` | `ProcessControl.m` | — |
| `0x550c` | 60 | `-[ProcessControl refilter:]` | `ProcessControl.m` | — |
| `0x5548` | 144 | `-[ProcessControl resetRate:]` | `ProcessControl.m` | — |
| `0x55d8` | 324 | `-[ProcessControl bumpRate:]` | `ProcessControl.m` | — |
| `0x571c` | 12 | `-[ProcessControl showMoreInfoAboutSelection:]` | `ProcessControl.m` | — |
| `0x5728` | 252 | `-[ProcessControl tableViewSelectionDidChange:]` | `ProcessControl.m` | — |
| `0x5824` | 200 | `-[ProcessControl showAboutPanel:]` | `ProcessControl.m` | — |
| `0x58ec` | 312 | `-[ProcessControl exportProcessList:]` | `ProcessControl.m` | — |
| `0x5a24` | 104 | `-[ProcessControl print:]` | `ProcessControl.m` | — |
| `0x5a8c` | 180 | `-[ProcessControl hideColumn:]` | `ProcessControl.m` | — |
| `0x5b40` | 200 | `-[ProcessControl showAllColumns:]` | `ProcessControl.m` | — |
| `0x5c08` | 140 | `-[ProcessControl toggleMoreInfo:]` | `ProcessControl.m` | — |
| `0x5c94` | 168 | `-[ProcessControl killProcesses:]` | `ProcessControl.m` | — |
| `0x5d3c` | 1340 | `-[ProcessControl killProcessWithConfirmation:]` | `ProcessControl.m` | — |
| `0x6278` | 264 | `-[ProcessControl tableView:objectValueForTableColumn:row:]` | `ProcessControl.m` | — |
| `0x6380` | 72 | `-[ProcessControl numberOfRowsInTableView:]` | `ProcessControl.m` | — |
| `0x63c8` | 56 | `-[ProcessControl controlTextDidChange:]` | `ProcessControl.m` | — |
| `0x6400` | 56 | `-[ProcessControl windowDidResize:]` | `ProcessControl.m` | — |
| `0x6438` | 68 | `-[ProcessControl windowShouldClose:]` | `ProcessControl.m` | — |
| `0x647c` | 140 | `-[ProcessControl changeSortOrder:]` | `ProcessControl.m` | — |
| `0x6508` | 140 | `-[ProcessControl validateMenuItem:]` | `ProcessControl.m` | — |
| `0x6594` | 916 | `__readTypesFromFile` | `ProcessType.m` | +[ProcessType allProcessTypes] |
| `0x6928` | 464 | `+[ProcessType allProcessTypes]` | `ProcessType.m` | — |
| `0x6af8` | 96 | `-[ProcessType dealloc]` | `ProcessType.m` | — |
| `0x6b58` | 540 | `-[ProcessType initWithDictionary:strings:]` | `ProcessType.m` | — |
| `0x6d74` | 120 | `-[ProcessType matchesProcess:]` | `ProcessType.m` | — |
| `0x6dec` | 16 | `-[ProcessType localizedName]` | `ProcessType.m` | — |
| `0x6dfc` | 16 | `-[ProcessType name]` | `ProcessType.m` | — |
| `0x6e0c` | 136 | `-[ProcessTableView initWithCoder:]` | `ProcessTableView.m` | — |
| `0x6e94` | 16 | `-[ProcessTableView highlightedColumnIdentifier]` | `ProcessTableView.m` | — |
| `0x6ea4` | 108 | `-[ProcessTableView setHighlightedColumn:]` | `ProcessTableView.m` | — |
| `0x6f10` | 292 | `-[ProcessTableHeaderView drawRect:]` | `ProcessTableView.m` | — |
| `0x7034` | 432 | `-[ProcessTableHeaderView _modifySelectionWithEvent:onColumn:]` | `ProcessTableView.m` | — |
| `0x71e4` | 32 | `_main` | `ProcessControl.m` | __start |
| `0x7204` | 312 | `_NameForUID` | `UserIdCache.m` | -[Process(Private) _update] |
| `0x7a0c` | 36 | `_exit` | `dyld/import stub` | __start |
| `0x7a30` | 36 | `__objcInit` | `runtime/linker` | __start |
| `0x7a54` | 36 | `_NSPointInRect` | `dyld/import stub` | -[Inspector setVisible:] |
| `0x7a78` | 36 | `_objc_msgSendSuper` | `dyld/import stub` | -[Inspector dealloc], -[Process dealloc], -[Process initWithPid:], -[ProcessControl dealloc], -[ProcessControl init], -[ProcessTableHeaderView drawRect:], -[ProcessTableView initWithCoder:], -[ProcessType dealloc], -[ProcessType initWithDictionary:strings:] |
| `0x7a9c` | 36 | `_objc_msgSend_stret` | `dyld/import stub` | -[Inspector _loadInspectorNib], -[Inspector setSplitView:], -[Inspector setVisible:], -[Inspector splitView:constrainMinCoordinate:maxCoordinate:ofSubviewAt:], -[Inspector splitView:resizeSubviewsWithOldSize:], -[ProcessControl shouldShowProcess:], -[ProcessTableHeaderView _modifySelectionWithEvent:onColumn:], -[ProcessTableHeaderView drawRect:] |
| `0x7ac0` | 36 | `_objc_msgSend` | `dyld/import stub` | +[MapTableEnumerator _newWithMapTable:], +[Process enumerateProcessesAndFetch:], +[Process getSortContext:forKey:ascending:], +[Process initialize], +[ProcessType allProcessTypes], -[Inspector _loadInspectorNib], -[Inspector _processTanked:], -[Inspector _setCurrentView:], -[Inspector _setProcess:], -[Inspector awakeFromNib], -[Inspector dealloc], -[Inspector numberOfRowsInTableView:], -[Inspector setSplitView:], -[Inspector setVisible:], -[Inspector showInfoForMultipleSelection], -[Inspector showInfoForNoSelection], -[Inspector showInfoForProcess:], -[Inspector splitView:constrainMinCoordinate:maxCoordinate:ofSubviewAt:], -[Inspector splitView:resizeSubviewsWithOldSize:], -[Inspector tabView:didSelectTabViewItem:], -[Inspector tableView:objectValueForTableColumn:row:], -[Process _setCString:forKey:], -[Process arguments], -[Process compare:context:], -[Process dealloc], -[Process description], -[Process dictionaryRepresentation], -[Process initWithPid:], -[Process invalidate], -[Process objectForKey:], -[Process tty], -[Process(Private) _update], -[ProcessControl applicationDidFinishLaunching:], -[ProcessControl assignActions], -[ProcessControl bumpRate:], -[ProcessControl changeSortOrder:], -[ProcessControl controlTextDidChange:], -[ProcessControl dealloc], -[ProcessControl exportProcessList:], -[ProcessControl getProcesses:], -[ProcessControl hideColumn:], -[ProcessControl init], -[ProcessControl killProcessWithConfirmation:], -[ProcessControl killProcesses:], -[ProcessControl numberOfRowsInTableView:], -[ProcessControl print:], -[ProcessControl refilter:], -[ProcessControl resetRate:], -[ProcessControl resort:], -[ProcessControl setShowType:], -[ProcessControl shouldShowProcess:], -[ProcessControl showAboutPanel:], -[ProcessControl showAllColumns:], -[ProcessControl tableView:objectValueForTableColumn:row:], -[ProcessControl tableViewSelectionDidChange:], -[ProcessControl toggleMoreInfo:], -[ProcessControl updateForSortChange:filterChange:], -[ProcessControl updateRate], -[ProcessControl validateMenuItem:], -[ProcessControl windowDidResize:], -[ProcessControl windowShouldClose:], -[ProcessTableHeaderView _modifySelectionWithEvent:onColumn:], -[ProcessTableHeaderView drawRect:], -[ProcessTableView initWithCoder:], -[ProcessTableView setHighlightedColumn:], -[ProcessType dealloc], -[ProcessType initWithDictionary:strings:], -[ProcessType matchesProcess:], _NameForUID, __readTypesFromFile, _floatFromNumberWithSuffix, _sortFunction |
| `0x7ae4` | 36 | `_strcmp` | `dyld/import stub` | -[Process _setCString:forKey:] |
| `0x7b08` | 36 | `_NSLog` | `dyld/import stub` | -[Process(Private) _update], -[ProcessType initWithDictionary:strings:], __readTypesFromFile |
| `0x7b2c` | 36 | `_strerror` | `dyld/import stub` | -[Process(Private) _update] |
| `0x7b50` | 36 | `_sysctl` | `dyld/import stub` | -[Process(Private) _update] |
| `0x7b74` | 36 | `_strlen` | `dyld/import stub` | -[Process arguments], -[Process(Private) _update], _NameForUID |
| `0x7b98` | 36 | `_index` | `dyld/import stub` | -[Process arguments] |
| `0x7bbc` | 36 | `_table` | `dyld/import stub` | -[Process arguments] |
| `0x7be0` | 36 | `_NSZoneMalloc` | `dyld/import stub` | -[Process arguments] |
| `0x7c04` | 36 | `_NSMapInsert` | `dyld/import stub` | -[Process initWithPid:], _NameForUID |
| `0x7c28` | 36 | `_NSFreeMapTable` | `dyld/import stub` | +[Process enumerateProcessesAndFetch:] |
| `0x7c4c` | 36 | `_NSAllMapTableValues` | `dyld/import stub` | +[Process enumerateProcessesAndFetch:] |
| `0x7c70` | 36 | `_NSCountMapTable` | `dyld/import stub` | +[Process enumerateProcessesAndFetch:] |
| `0x7c94` | 36 | `_NSMapRemove` | `dyld/import stub` | +[Process enumerateProcessesAndFetch:], -[Process invalidate] |
| `0x7cb8` | 36 | `_NSMapGet` | `dyld/import stub` | +[Process enumerateProcessesAndFetch:], _NameForUID |
| `0x7cdc` | 36 | `_strchr` | `dyld/import stub` | +[Process enumerateProcessesAndFetch:] |
| `0x7d00` | 36 | `_NSCreateMapTableWithZone` | `dyld/import stub` | +[Process enumerateProcessesAndFetch:], _NameForUID |
| `0x7d24` | 36 | `_NSCopyMapTableWithZone` | `dyld/import stub` | +[Process enumerateProcessesAndFetch:] |
| `0x7d48` | 36 | `_NSDefaultMallocZone` | `dyld/import stub` | +[Process enumerateProcessesAndFetch:], -[Process arguments], -[Process dictionaryRepresentation], -[Process initWithPid:] |
| `0x7d6c` | 36 | `_NSNextMapEnumeratorPair` | `dyld/import stub` | -[MapTableEnumerator nextObject] |
| `0x7d90` | 36 | `_NSEnumerateMapTable` | `dyld/import stub` | +[MapTableEnumerator _newWithMapTable:] |
| `0x7db4` | 36 | `_kill` | `dyld/import stub` | -[ProcessControl killProcessWithConfirmation:] |
| `0x7dd8` | 36 | `_NSRunAlertPanel` | `dyld/import stub` | -[ProcessControl killProcessWithConfirmation:] |
| `0x7dfc` | 36 | `_NSUserName` | `dyld/import stub` | -[ProcessControl killProcessWithConfirmation:], -[ProcessType initWithDictionary:strings:] |
| `0x7e20` | 36 | `_NSHomeDirectory` | `dyld/import stub` | -[ProcessControl exportProcessList:] |
| `0x7e44` | 36 | `_NSShowSystemInfoPanel` | `dyld/import stub` | -[ProcessControl showAboutPanel:] |
| `0x7e68` | 36 | `_NSBeep` | `dyld/import stub` | -[ProcessControl bumpRate:], -[ProcessControl exportProcessList:] |
| `0x7e8c` | 36 | `_NSSearchPathForDirectoriesInDomains` | `dyld/import stub` | +[ProcessType allProcessTypes] |
| `0x7eb0` | 36 | `__NSExceptionObjectFromHandler2` | `runtime/linker` | __readTypesFromFile |
| `0x7ed4` | 36 | `__NSRemoveHandler2` | `runtime/linker` | __readTypesFromFile |
| `0x7ef8` | 36 | `__setjmp` | `runtime/linker` | __readTypesFromFile |
| `0x7f1c` | 36 | `__NSAddHandler2` | `runtime/linker` | __readTypesFromFile |
| `0x7f40` | 36 | `_NSApplicationMain` | `dyld/import stub` | _main |
| `0x7f64` | 36 | `_getpwuid` | `dyld/import stub` | _NameForUID |
