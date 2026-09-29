# Interceptor function worklist

Each address is from the selected thin image symbol table or IDA output. Status stays unexamined until body, signature, and callers are checked against disassembly.

## PowerPC primary

IDA function records: 392; symbol records: 540.

| Address | Size | IDA names | Review status |
|---:|---:|---|---|
| `0x47A02464` | 48 | `dyld_stub_binding_helper` | unexamined |
| `0x47A02494` | 32 | `__dyld_func_lookup` | unexamined |
| `0x47A024B4` | 640 | `_CopyLong` | static-reviewed; runtime pending; `NSDirectBitmap.m` |
| `0x47A02734` | 176 | `_CopyShort` | static-reviewed; runtime pending; `NSDirectBitmap.m` |
| `0x47A027E4` | 188 | `_CopyByte` | static-reviewed; runtime pending; `NSDirectBitmap.m` |
| `0x47A028A0` | 64 | `+[NSDirectBitmap minDepthForGray:andColor:]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A028E0` | 16 | `-[NSDirectBitmap bitsPerPixel]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A028F0` | 16 | `-[NSDirectBitmap bitsPerSample]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A02900` | 136 | `-[NSDirectBitmap bytesPerPlane]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A02988` | 108 | `-[NSDirectBitmap bytesPerRow]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A029F4` | 16 | `-[NSDirectBitmap colorSpaceName]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A02A04` | 56 | `-[NSDirectBitmap conversionTable]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A02A3C` | 56 | `-[NSDirectBitmap inverseConversionTable]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A02A74` | 140 | `-[NSDirectBitmap _dataBuffer]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A02B00` | 160 | `-[NSDirectBitmap bitmapData]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A02BA0` | 460 | `-[NSDirectBitmap _flushInShape:]` | static-reviewed; source authored; runtime pending |
| `0x47A02D6C` | 168 | `-[NSDirectBitmap flush]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A02E14` | 856 | `-[NSDirectBitmap flushIn:]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A0316C` | 200 | `-[NSDirectBitmap dealloc]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A03234` | 272 | `-[NSDirectBitmap getBitmapDataPlanes:]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A03344` | 132 | `-[NSDirectBitmap pixelEncodings]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A033C8` | 20 | `-[NSDirectBitmap hasAlpha]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A033DC` | 120 | `-[NSDirectBitmap init]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A03454` | 344 | `-[NSDirectBitmap initForRect:inWindow:]` | static-reviewed; source authored; runtime pending |
| `0x47A035AC` | 20 | `-[NSDirectBitmap isPlanar]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A035C0` | 232 | `-[NSDirectBitmap _mapFramebufferForScreen:]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A036A8` | 956 | `-[NSDirectBitmap _initForRect:inWinNum:onScreen:]` | static-reviewed; source authored; runtime pending |
| `0x47A03A64` | 20 | `-[NSDirectBitmap isBuffered]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A03A78` | 20 | `-[NSDirectBitmap isDirectMapped]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A03A8C` | 268 | `-[NSDirectBitmap lockBitmap]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A03B98` | 36 | `-[NSDirectBitmap numberOfPlanes]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A03BBC` | 272 | `-[NSDirectBitmap pixelEncoding]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A03CCC` | 16 | `-[NSDirectBitmap pixelsWide]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A03CDC` | 16 | `-[NSDirectBitmap pixelsHigh]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A03CEC` | 260 | `-[NSDirectBitmap _updateBuffer]` | static-reviewed; source authored; runtime pending |
| `0x47A03DF0` | 16 | `-[NSDirectBitmap samplesPerPixel]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A03E00` | 280 | `-[NSDirectBitmap setBuffered:]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A03F18` | 208 | `-[NSDirectBitmap _canUseDirectMapping]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A03FE8` | 252 | `-[NSDirectBitmap setDirectMapped:]` | static-reviewed; source authored; runtime pending |
| `0x47A040E4` | 84 | `-[NSDirectBitmap tryLockBitmap]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A04138` | 84 | `-[NSDirectBitmap unlockBitmap]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A0418C` | 388 | `-[NSDirectBitmap _updateBackingStoreForRect:]` | static-reviewed; source authored; runtime pending |
| `0x47A04310` | 976 | `-[NSDirectBitmap _updateForRect:inWinNum:onScreen:]` | static-reviewed; source authored; runtime pending |
| `0x47A046E0` | 248 | `-[NSDirectBitmap updateForRect:inWindow:]` | static-reviewed; source authored; runtime pending |
| `0x47A047D8` | 172 | `-[NSDirectBitmap updateState]` | static-reviewed; source authored; runtime pending |
| `0x47A04884` | 60 | `-[NSDirectBitmap hideCursor]` | static-reviewed; source authored; runtime pending |
| `0x47A048C0` | 60 | `-[NSDirectBitmap showCursor]` | static-reviewed; source authored; runtime pending |
| `0x47A048FC` | 60 | `-[NSDirectBitmap currentPalette]` | static-reviewed; source authored; runtime pending |
| `0x47A04938` | 84 | `-[NSDirectBitmap _setDelegate:]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A0498C` | 16 | `-[NSDirectBitmap _framebuffer]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A0499C` | 20 | `-[NSDirectBitmap _setFlushOnExposure:]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A049B0` | 120 | `-[NSDirectBitmap _screenBoundsOrigin]` | static-reviewed; source authored; runtime pending |
| `0x47A04A28` | 132 | `-[NSDirectBitmap _isUnobscured]` | static-reviewed; source authored; runtime pending |
| `0x47A04AAC` | 100 | `-[NSDirectBitmap _isTotallyObscured]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A04B10` | 164 | `-[NSDirectBitmap _setViewClip:]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A04BB4` | 16 | `-[NSDirectBitmap _viewClipShape:]` | static-reviewed; source authored; runtime pending; `ppc/direct-bitmap.md` |
| `0x47A04BC4` | 136 | `-[NSDirectBitmap _setViewClipShape:]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A04C4C` | 148 | `-[NSDirectBitmap areaWillMove:by:]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A04CE0` | 232 | `-[NSDirectBitmap areaDidMove:by:]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A04DC8` | 356 | `-[NSDirectBitmap areaWillObscure:inRect:]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A04F2C` | 476 | `-[NSDirectBitmap areaDidReveal:inRect:]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A05108` | 76 | `-[NSDirectBitmap areaWasOrderedIn:]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A05154` | 76 | `-[NSDirectBitmap areaWasOrderedOut:]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A051A0` | 44 | `-[NSDirectBitmap areaIsInvalid:]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A051CC` | 68 | `-[NSDirectBitmap areaChangedScreen:from:to:]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A05210` | 44 | `-[NSDirectBitmap areaWindowFreed:]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A0523C` | 24 | `-[NSDirectBitmap areaDidChangeBuffering:toType:]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A05254` | 52 | `-[NSDirectBitmap(Obsolete) colorSpace]` | static-reviewed; source authored; runtime pending |
| `0x47A05288` | 52 | `-[NSDirectBitmap(Obsolete) data]` | static-reviewed; source authored; runtime pending |
| `0x47A052BC` | 76 | `+[NSDirectPalette defaultPalette]` | static-reviewed; source authored; runtime pending |
| `0x47A05308` | 76 | `+[NSDirectPalette defaultColorPalette]` | static-reviewed; source authored; runtime pending |
| `0x47A05354` | 404 | `+[NSDirectPalette defaultGrayPalette]` | static-reviewed; source authored; runtime pending |
| `0x47A054E8` | 324 | `+[NSDirectPalette currentPalette]` | static-reviewed; source authored; runtime pending |
| `0x47A0562C` | 204 | `-[NSDirectPalette initWithArrayOfColors:]` | static-reviewed; source authored; runtime pending |
| `0x47A056F8` | 488 | `-[NSDirectPalette init]` | static-reviewed; source authored; runtime pending |
| `0x47A058E0` | 60 | `-[NSDirectPalette colorAtIndex:]` | static-reviewed; source authored; runtime pending |
| `0x47A0591C` | 592 | `-[NSDirectPalette indexForColor:]` | static-reviewed; source authored; runtime pending |
| `0x47A05B6C` | 60 | `-[NSDirectPalette count]` | static-reviewed; source authored; runtime pending |
| `0x47A05BA8` | 144 | `-[NSDirectPalette dealloc]` | static-reviewed; source authored; runtime pending |
| `0x47A05C38` | 60 | `-[NSDirectPalette objectEnumerator]` | static-reviewed; source authored; runtime pending |
| `0x47A05C74` | 584 | `-[NSDirectPalette rawMachinePalette]` | static-reviewed; source authored; runtime pending |
| `0x47A05EBC` | 204 | `-[NSDirectPalette setColor:atIndex:]` | static-reviewed; source authored; runtime pending |
| `0x47A05F88` | 148 | `-[NSDirectPalette setRed:green:blue:atIndex:]` | static-reviewed; source authored; runtime pending |
| `0x47A0601C` | 96 | `-[NSDirectPalette getRed:green:blue:atIndex:]` | static-reviewed; source authored; runtime pending |
| `0x47A0607C` | 240 | `-[NSDirectPalette setColors:atIndices:]` | static-reviewed; source authored; runtime pending |
| `0x47A0616C` | 76 | `-[NSDirectPalette copy]` | static-reviewed; source authored; runtime pending |
| `0x47A061B8` | 76 | `-[NSDirectPalette mutableCopy]` | static-reviewed; source authored; runtime pending |
| `0x47A06204` | 52 | `-[NSDirectPalette copyWithZone:]` | static-reviewed; source authored; runtime pending |
| `0x47A06238` | 96 | `-[NSDirectPalette mutableCopyWithZone:]` | static-reviewed; source authored; runtime pending |
| `0x47A06298` | 64 | `-[NSDirectPalette encodeWithCoder:]` | static-reviewed; source authored; runtime pending |
| `0x47A062D8` | 160 | `-[NSDirectPalette initWithCoder:]` | static-reviewed; source authored; runtime pending |
| `0x47A06378` | 248 | `-[NSDirectPalette isEqual:]` | static-reviewed; source authored; runtime pending |
| `0x47A06470` | 656 | `-[NSDirectPalette blendedPaletteWithFraction:ofColor:]` | static-reviewed; source authored; runtime pending |
| `0x47A06700` | 136 | `-[NSDirectScreen _clearModeInfo]` | static-reviewed; source authored; runtime pending |
| `0x47A06788` | 492 | `-[NSDirectScreen initWithScreen:]` | static-reviewed; source authored; runtime pending |
| `0x47A06974` | 368 | `-[NSDirectScreen dealloc]` | static-reviewed; source authored; runtime pending |
| `0x47A06AE4` | 204 | `-[NSDirectScreen screenSize]` | static-reviewed; source authored; runtime pending |
| `0x47A06BB0` | 92 | `-[NSDirectScreen pixelsWide]` | static-reviewed; source authored; runtime pending |
| `0x47A06C0C` | 92 | `-[NSDirectScreen pixelsHigh]` | static-reviewed; source authored; runtime pending |
| `0x47A06C68` | 444 | `-[NSDirectScreen addressForPoint:]` | static-reviewed; source authored; runtime pending |
| `0x47A06E24` | 2544 | `-[NSDirectScreen availableDisplayModes]` | static-reviewed; source authored; runtime pending |
| `0x47A07814` | 376 | `-[NSDirectScreen availableDisplayModesForOptions:]` | static-reviewed; source authored; runtime pending |
| `0x47A0798C` | 1164 | `-[NSDirectScreen bestModeForFormat:width:height:]` | static-reviewed; source authored; runtime pending |
| `0x47A07E18` | 124 | `-[NSDirectScreen bestModeForOptions:]` | static-reviewed; source authored; runtime pending |
| `0x47A07E94` | 296 | `-[NSDirectScreen currentMode]` | static-reviewed; source authored; runtime pending |
| `0x47A07FBC` | 120 | `-[NSDirectScreen bitsPerPixel]` | static-reviewed; source authored; runtime pending |
| `0x47A08034` | 120 | `-[NSDirectScreen bitsPerSample]` | static-reviewed; source authored; runtime pending |
| `0x47A080AC` | 176 | `-[NSDirectScreen bytesPerRow]` | static-reviewed; source authored; runtime pending |
| `0x47A0815C` | 92 | `-[NSDirectScreen bytesPerPlane]` | static-reviewed; source authored; runtime pending |
| `0x47A081B8` | 16 | `-[NSDirectScreen numberOfPlanes]` | static-reviewed; source authored; runtime pending |
| `0x47A081C8` | 64 | `-[NSDirectScreen _canLockWithMode:]` | static-reviewed; source authored; runtime pending |
| `0x47A08208` | 72 | `-[NSDirectScreen colorSpaceName]` | static-reviewed; source authored; runtime pending |
| `0x47A08250` | 116 | `-[NSDirectScreen bitmapData]` | static-reviewed; source authored; runtime pending |
| `0x47A082C4` | 80 | `-[NSDirectScreen getBitmapDataPlanes:]` | static-reviewed; source authored; runtime pending |
| `0x47A08314` | 16 | `-[NSDirectScreen isPlanar]` | static-reviewed; source authored; runtime pending |
| `0x47A08324` | 16 | `-[NSDirectScreen hasAlpha]` | static-reviewed; source authored; runtime pending |
| `0x47A08334` | 60 | `-[NSDirectScreen deviceSlot]` | static-reviewed; source authored; runtime pending |
| `0x47A08370` | 60 | `-[NSDirectScreen deviceUnit]` | static-reviewed; source authored; runtime pending |
| `0x47A083AC` | 24 | `-[NSDirectScreen displayIsShielded]` | static-reviewed; source authored; runtime pending |
| `0x47A083C4` | 60 | `-[NSDirectScreen driver]` | static-reviewed; source authored; runtime pending |
| `0x47A08400` | 280 | `-[NSDirectScreen fadeDisplay:toColor:]` | static-reviewed; source authored; runtime pending |
| `0x47A08518` | 360 | `-[NSDirectScreen _fadeIn:]` | static-reviewed; source authored; runtime pending |
| `0x47A08680` | 776 | `-[NSDirectScreen fadeDisplayInFromColor:]` | static-reviewed; source authored; runtime pending |
| `0x47A08988` | 380 | `-[NSDirectScreen _fadeOut:]` | static-reviewed; source authored; runtime pending |
| `0x47A08B04` | 776 | `-[NSDirectScreen fadeDisplayOutToColor:]` | static-reviewed; source authored; runtime pending |
| `0x47A08E0C` | 20 | `-[NSDirectScreen fadeDuration]` | static-reviewed; source authored; runtime pending |
| `0x47A08E20` | 24 | `-[NSDirectScreen fadeInProgress]` | static-reviewed; source authored; runtime pending |
| `0x47A08E38` | 24 | `-[NSDirectScreen fadeApplied]` | static-reviewed; source authored; runtime pending |
| `0x47A08E50` | 136 | `-[NSDirectScreen _lockWithMode:]` | static-reviewed; source authored; runtime pending |
| `0x47A08ED8` | 72 | `-[NSDirectScreen pixelEncoding]` | static-reviewed; source authored; runtime pending |
| `0x47A08F20` | 120 | `-[NSDirectScreen samplesPerPixel]` | static-reviewed; source authored; runtime pending |
| `0x47A08F98` | 60 | `-[NSDirectScreen screenNumber]` | static-reviewed; source authored; runtime pending |
| `0x47A08FD4` | 136 | `-[NSDirectScreen canSetPalette]` | static-reviewed; source authored; runtime pending |
| `0x47A0905C` | 256 | `-[NSDirectScreen setPalette:]` | static-reviewed; source authored; runtime pending |
| `0x47A0915C` | 20 | `-[NSDirectScreen currentPalette]` | static-reviewed; source authored; runtime pending |
| `0x47A09170` | 256 | `-[NSDirectScreen setPaletteAtNextBlankingInterval:]` | static-reviewed; source authored; runtime pending |
| `0x47A09270` | 80 | `-[NSDirectScreen setFadeDuration:]` | static-reviewed; source authored; runtime pending |
| `0x47A092C0` | 652 | `-[NSDirectScreen shieldDisplay]` | static-reviewed; source authored; runtime pending |
| `0x47A0954C` | 20 | `-[NSDirectScreen shieldingWindow]` | static-reviewed; source authored; runtime pending |
| `0x47A09560` | 600 | `-[NSDirectScreen switchToDisplayMode:]` | static-reviewed; source authored; runtime pending |
| `0x47A097B8` | 128 | `-[NSDirectScreen _unlock]` | static-reviewed; source authored; runtime pending |
| `0x47A09838` | 344 | `-[NSDirectScreen unshieldDisplay]` | static-reviewed; source authored; runtime pending |
| `0x47A09990` | 40 | `-[NSDirectScreen hideCursor]` | static-reviewed; source authored; runtime pending |
| `0x47A099B8` | 40 | `-[NSDirectScreen showCursor]` | static-reviewed; source authored; runtime pending |
| `0x47A099E0` | 100 | `-[NSDirectScreen setGamma:]` | static-reviewed; source authored; runtime pending |
| `0x47A09A44` | 376 | `-[NSDirectScreen setGammaRed:green:blue:]` | static-reviewed; source authored; runtime pending |
| `0x47A09BBC` | 984 | `-[NSDirectScreen setGammaTableOfSize:red:green:blue:]` | static-reviewed; source authored; runtime pending |
| `0x47A09F94` | 312 | `-[NSDirectScreen _loadPalette:]` | static-reviewed; source authored; runtime pending |
| `0x47A0A0CC` | 380 | `-[NSDirectScreen _createBackingStore]` | static-reviewed; source authored; runtime pending |
| `0x47A0A248` | 100 | `-[NSDirectScreen _destroyBackingStore]` | static-reviewed; source authored; runtime pending |
| `0x47A0A2AC` | 504 | `_CopySrcToDst` | static-reviewed; runtime pending; `NSFramebuffer.m` |
| `0x47A0A4A4` | 52 | `-[NSDirectScreen(Obsolete) colorSpace]` | static-reviewed; source authored; runtime pending |
| `0x47A0A4D8` | 52 | `-[NSDirectScreen(Obsolete) data]` | static-reviewed; source authored; runtime pending |
| `0x47A0A50C` | 176 | `_setInstanceForScreen` | static-reviewed; source authored; runtime pending; `NSFramebuffer.m` |
| `0x47A0A5BC` | 108 | `_instanceForScreen` | static-reviewed; source authored; runtime pending; `NSFramebuffer.m` |
| `0x47A0A628` | 56 | `-[NSFramebuffer initWithScreen:]` | static-reviewed; runtime pending; `NSFramebuffer.m` |
| `0x47A0A660` | 204 | `-[NSFramebuffer initWithScreen:andMapIfPossible:]` | static-reviewed; runtime pending; `NSFramebuffer.m` |
| `0x47A0A72C` | 692 | `-[NSFramebuffer initFromScreen:andMapIfPossible:]` | static-reviewed; source authored; runtime pending; `NSFramebuffer.m` |
| `0x47A0A9E0` | 92 | `-[NSFramebuffer unmapScreen]` | static-reviewed; source authored; runtime pending; `NSFramebuffer.m` |
| `0x47A0AA3C` | 544 | `-[NSFramebuffer remapScreen]` | static-reviewed; source authored; runtime pending; `NSFramebuffer.m` |
| `0x47A0AC5C` | 20 | `-[NSFramebuffer isMappable]` | static-reviewed; runtime pending; `NSFramebuffer.m` |
| `0x47A0AC70` | 216 | `-[NSFramebuffer screenBounds]` | static-reviewed; runtime pending; architecture difference recorded |
| `0x47A0AD48` | 16 | `-[NSFramebuffer screenNumber]` | static-reviewed; runtime pending; `NSFramebuffer.m` |
| `0x47A0AD58` | 184 | `-[NSFramebuffer conversionTable]` | static-reviewed; source authored; runtime pending; `NSFramebuffer.m` |
| `0x47A0AE10` | 184 | `-[NSFramebuffer inverseConversionTable]` | static-reviewed; source authored; runtime pending; `NSFramebuffer.m` |
| `0x47A0AEC8` | 144 | `-[NSFramebuffer addressForPoint:]` | static-reviewed; runtime pending; `NSFramebuffer.m` |
| `0x47A0AF58` | 100 | `-[NSFramebuffer pixelEncoding]` | static-reviewed; runtime pending; `NSFramebuffer.m` |
| `0x47A0AFBC` | 100 | `-[NSFramebuffer driver]` | static-reviewed; runtime pending; `NSFramebuffer.m` |
| `0x47A0B020` | 16 | `-[NSFramebuffer deviceUnit]` | static-reviewed; runtime pending; `NSFramebuffer.m` |
| `0x47A0B030` | 16 | `-[NSFramebuffer deviceSlot]` | static-reviewed; runtime pending; `NSFramebuffer.m` |
| `0x47A0B040` | 12 | `-[NSFramebuffer retain]` | static-reviewed; runtime pending; `NSFramebuffer.m` |
| `0x47A0B04C` | 12 | `-[NSFramebuffer release]` | static-reviewed; runtime pending; `NSFramebuffer.m` |
| `0x47A0B058` | 16 | `-[NSFramebuffer retainCount]` | static-reviewed; runtime pending; `NSFramebuffer.m` |
| `0x47A0B068` | 12 | `-[NSFramebuffer dealloc]` | static-reviewed; runtime pending; `NSFramebuffer.m` |
| `0x47A0B074` | 16 | `-[NSFramebuffer canLockWithMode:]` | static-reviewed; runtime pending; `NSFramebuffer.m` |
| `0x47A0B084` | 12 | `-[NSFramebuffer lockWithMode:]` | static-reviewed; runtime pending; `NSFramebuffer.m` |
| `0x47A0B090` | 12 | `-[NSFramebuffer unlock]` | static-reviewed; runtime pending; `NSFramebuffer.m` |
| `0x47A0B09C` | 16 | `-[NSFramebuffer _interceptorClient]` | static-reviewed; runtime pending; `NSFramebuffer.m` |
| `0x47A0B0AC` | 12 | `_NSRemapMegaPixelDisplayForCurrentThread` | static-reviewed; source authored; runtime pending |
| `0x47A0B0B8` | 412 | `-[NSInterceptedRect initForRect:inWindow:onFramebuffer:forClient:]` | static-reviewed; source authored; runtime pending; `ppc/client-state.md` |
| `0x47A0B254` | 16 | `-[NSInterceptedRect setTarget:]` | static-reviewed; source authored; runtime pending; `ppc/client-state.md` |
| `0x47A0B264` | 16 | `-[NSInterceptedRect target]` | static-reviewed; source authored; runtime pending; `ppc/client-state.md` |
| `0x47A0B274` | 72 | `-[NSInterceptedRect lockRect]` | static-reviewed; source authored; runtime pending; `ppc/client-state.md` |
| `0x47A0B2BC` | 68 | `-[NSInterceptedRect unlockRect]` | static-reviewed; source authored; runtime pending; `ppc/client-state.md` |
| `0x47A0B300` | 48 | `-[NSInterceptedRect isLocked]` | static-reviewed; source authored; runtime pending; `ppc/client-state.md` |
| `0x47A0B330` | 44 | `-[NSInterceptedRect currentScreenRect]` | static-reviewed; source authored; runtime pending; `ppc/client-state.md` |
| `0x47A0B35C` | 16 | `-[NSInterceptedRect currentScreenRectShape]` | static-reviewed; source authored; runtime pending; `ppc/client-state.md` |
| `0x47A0B36C` | 96 | `-[NSInterceptedRect currentClipList:count:]` | static-reviewed; source authored; runtime pending |
| `0x47A0B3CC` | 96 | `-[NSInterceptedRect compositeBits:withOp:]` | static-reviewed; source authored; runtime pending |
| `0x47A0B42C` | 60 | `-[NSInterceptedRect removeFromWindowServer]` | static-reviewed; source authored; runtime pending; `ppc/client-state.md` |
| `0x47A0B468` | 148 | `-[NSInterceptedRect dealloc]` | static-reviewed; source authored; runtime pending; `ppc/client-state.md` |
| `0x47A0B4FC` | 16 | `-[NSInterceptedRect uniqueID]` | static-reviewed; source authored; runtime pending |
| `0x47A0B50C` | 16 | `-[NSInterceptedRect windowNumber]` | static-reviewed; source authored; runtime pending; `ppc/client-state.md` |
| `0x47A0B51C` | 44 | `-[NSInterceptedRect rectangle]` | static-reviewed; source authored; runtime pending; `ppc/client-state.md` |
| `0x47A0B548` | 20 | `-[NSInterceptedRect isTotallyVisible]` | static-reviewed; source authored; runtime pending; `ppc/client-state.md` |
| `0x47A0B55C` | 20 | `-[NSInterceptedRect isTotallyObscured]` | static-reviewed; source authored; runtime pending; `ppc/client-state.md` |
| `0x47A0B570` | 16 | `-[NSInterceptedRect _flags]` | static-reviewed; source authored; runtime pending; `ppc/client-state.md` |
| `0x47A0B580` | 16 | `-[NSInterceptedRect framebuffer]` | static-reviewed; source authored; runtime pending; `ppc/client-state.md` |
| `0x47A0B590` | 1908 | `-[NSInterceptedRect _handleMsg:withReply:]` | static-reviewed; source authored; runtime pending; `ppc/client-state.md` |
| `0x47A0BD04` | 188 | `+[NSInterceptorClient initialize]` | static-reviewed; source authored; runtime pending; `ppc/client-state.md` |
| `0x47A0BDC0` | 284 | `-[NSInterceptorClient init]` | static-reviewed; source authored; runtime pending; `ppc/client-state.md` |
| `0x47A0BEDC` | 388 | `-[NSInterceptorClient dealloc]` | static-reviewed; source authored; runtime pending; `ppc/client-state.md` |
| `0x47A0C060` | 108 | `-[NSInterceptorClient setHandlingThread:]` | static-reviewed; source authored; runtime pending; `ppc/client-state.md` |
| `0x47A0C0CC` | 60 | `-[NSInterceptorClient handlingThread]` | static-reviewed; source authored; runtime pending; `ppc/client-state.md` |
| `0x47A0C108` | 308 | `-[NSInterceptorClient interceptorPort]` | static-reviewed; source authored; runtime pending; `ppc/client-state.md` |
| `0x47A0C23C` | 268 | `-[NSInterceptorClient handleInterceptorMessage:withReply:]` | static-reviewed; source authored; runtime pending; `ppc/client-state.md` |
| `0x47A0C348` | 560 | `-[NSInterceptorClient _addInterceptedRect:returnedScreenRect:returnedFlags:]` | static-reviewed; source authored; runtime pending; `ppc/client-state.md` |
| `0x47A0C578` | 160 | `-[NSInterceptorClient _removeInterceptedRect:]` | static-reviewed; source authored; runtime pending; `ppc/client-state.md` |
| `0x47A0C618` | 16 | `-[NSInterceptorClient _context]` | static-reviewed; source authored; runtime pending; `ppc/client-state.md` |
| `0x47A0C628` | 88 | `-[NSInterceptorClient windowServerPortDeath:]` | static-reviewed; source authored; runtime pending; `ppc/client-state.md` |
| `0x47A0C680` | 632 | `-[NSInterceptorClient _notifyHandler]` | static-reviewed; source authored; runtime pending; `ppc/client-state.md` |
| `0x47A0C8F8` | 364 | `-[NSInterceptorClient startHandlingThread]` | static-reviewed; source authored; runtime pending; `ppc/client-state.md` |
| `0x47A0CA64` | 60 | `_empty_shape` | static-reviewed; runtime pending |
| `0x47A0CAA0` | 348 | `_rect_shape` | static-reviewed; runtime pending |
| `0x47A0CBFC` | 108 | `_is_equal_shape` | static-reviewed; runtime pending |
| `0x47A0CC68` | 68 | `_is_empty_shape` | static-reviewed; runtime pending |
| `0x47A0CCAC` | 96 | `_offset_shape` | static-reviewed; runtime pending |
| `0x47A0CD0C` | 820 | `_union_shape` | static-reviewed; runtime pending |
| `0x47A0D040` | 764 | `_intersect_shape` | static-reviewed; runtime pending |
| `0x47A0D33C` | 780 | `_difference_shape` | static-reviewed; runtime pending |
| `0x47A0D648` | 108 | `-[NSShape init]` | static-reviewed; runtime pending |
| `0x47A0D6B4` | 128 | `-[NSShape initFromRect:]` | static-reviewed; runtime pending |
| `0x47A0D734` | 72 | `-[NSShape intersectWithShape:]` | static-reviewed; runtime pending |
| `0x47A0D77C` | 72 | `-[NSShape unionWithShape:]` | static-reviewed; runtime pending |
| `0x47A0D7C4` | 72 | `-[NSShape differenceWithShape:]` | static-reviewed; runtime pending |
| `0x47A0D80C` | 40 | `-[NSShape isEmpty]` | static-reviewed; runtime pending |
| `0x47A0D834` | 76 | `-[NSShape isEqual:]` | static-reviewed; runtime pending |
| `0x47A0D880` | 164 | `-[NSShape copyWithZone:]` | static-reviewed; runtime pending |
| `0x47A0D924` | 84 | `-[NSShape offsetShape:]` | static-reviewed; runtime pending |
| `0x47A0D978` | 96 | `-[NSShape rectEnumerator]` | static-reviewed; runtime pending |
| `0x47A0D9D8` | 88 | `-[NSShape dealloc]` | static-reviewed; runtime pending |
| `0x47A0DA30` | 348 | `-[NSShape description]` | PPC static-reviewed; source authored; runtime pending |
| `0x47A0DB8C` | 92 | `-[_NSShapeEnumerator initForShapeImpl:]` | static-reviewed; runtime pending |
| `0x47A0DBE8` | 364 | `-[_NSShapeEnumerator nextRect]` | static-reviewed; runtime pending |
| `0x47A0DD54` | 316 | `-[NSSimpleBitmap initWithBitmapDataPlanes:pixelsWide:pixelsHigh:bitsPerSample:samplesPerPixel:hasAlpha:isPlanar:colorSpaceName:bytesPerRow:bitsPerPixel:]` | static-reviewed; runtime pending |
| `0x47A0DE90` | 16 | `-[NSSimpleBitmap bitmapData]` | static-reviewed; runtime pending |
| `0x47A0DEA0` | 132 | `-[NSSimpleBitmap getBitmapDataPlanes:]` | static-reviewed; runtime pending |
| `0x47A0DF24` | 20 | `-[NSSimpleBitmap isPlanar]` | static-reviewed; runtime pending |
| `0x47A0DF38` | 20 | `-[NSSimpleBitmap hasAlpha]` | static-reviewed; runtime pending |
| `0x47A0DF4C` | 16 | `-[NSSimpleBitmap samplesPerPixel]` | static-reviewed; runtime pending |
| `0x47A0DF5C` | 16 | `-[NSSimpleBitmap bitsPerPixel]` | static-reviewed; runtime pending |
| `0x47A0DF6C` | 16 | `-[NSSimpleBitmap bitsPerSample]` | static-reviewed; runtime pending |
| `0x47A0DF7C` | 16 | `-[NSSimpleBitmap bytesPerRow]` | static-reviewed; runtime pending |
| `0x47A0DF8C` | 36 | `-[NSSimpleBitmap bytesPerPlane]` | static-reviewed; runtime pending |
| `0x47A0DFB0` | 36 | `-[NSSimpleBitmap numberOfPlanes]` | static-reviewed; runtime pending |
| `0x47A0DFD4` | 16 | `-[NSSimpleBitmap colorSpaceName]` | static-reviewed; runtime pending |
| `0x47A0DFE4` | 16 | `-[NSSimpleBitmap pixelsWide]` | static-reviewed; runtime pending |
| `0x47A0DFF4` | 16 | `-[NSSimpleBitmap pixelsHigh]` | static-reviewed; runtime pending |
| `0x47A0E004` | 96 | `-[NSSimpleBitmap dealloc]` | static-reviewed; runtime pending |
| `0x47A0E064` | 52 | `-[NSSimpleBitmap(Obsolete) colorSpace]` | static-reviewed; source authored; runtime pending |
| `0x47A0E098` | 52 | `-[NSSimpleBitmap(Obsolete) data]` | static-reviewed; source authored; runtime pending |
| `0x47A0E0CC` | 204 | `_rendezVous` | static-reviewed; source authored; runtime pending; `ppc/ipc.md` |
| `0x47A0E198` | 52 | `__rendezvousPort` | static-reviewed; source authored; runtime pending; `ppc/ipc.md` |
| `0x47A0E1CC` | 296 | `_getPSPort` | static-reviewed; source authored; runtime pending; `ppc/ipc.md` |
| `0x47A0E2F4` | 164 | `_InterceptorCreateRemoteContext` | static-reviewed; runtime pending; `InterceptorContext.c` |
| `0x47A0E398` | 40 | `_InterceptorCreateContext` | static-reviewed; runtime pending; `InterceptorContext.c` |
| `0x47A0E3C0` | 136 | `_InterceptorDestroyContext` | static-reviewed; runtime pending; `InterceptorContext.c` |
| `0x47A0E448` | 92 | `_Interceptor_mig_error` | static-reviewed; source authored; runtime pending; `InterceptorIPC.c` |
| `0x47A0E4A4` | 84 | `_InterceptorMapFrameBuffer` | static-reviewed; source authored; runtime pending; `InterceptorIPC.c` |
| `0x47A0E4F8` | 84 | `_InterceptorUnmapFrameBuffer` | static-reviewed; source authored; runtime pending; `InterceptorIPC.c` |
| `0x47A0E54C` | 16 | `_InterceptorGetBM34ToBM35Table` | static-reviewed; source authored; runtime pending; `InterceptorIPC.c` |
| `0x47A0E55C` | 16 | `_InterceptorGetBM35ToBM34Table` | static-reviewed; source authored; runtime pending; `InterceptorIPC.c` |
| `0x47A0E56C` | 48 | `_InterceptorGetBM256ToBM38Table` | static-reviewed; source authored; runtime pending; `InterceptorIPC.c` |
| `0x47A0E59C` | 48 | `_InterceptorGetBM38ToBM256Table` | static-reviewed; source authored; runtime pending; `InterceptorIPC.c` |
| `0x47A0E5CC` | 44 | `_InterceptorScreenCount` | PPC static-reviewed; source authored; runtime pending |
| `0x47A0E5F8` | 140 | `InterceptorCompositeBits` | static-reviewed; source authored; runtime pending; `InterceptorIPC.c` |
| `0x47A0E684` | 140 | `_InterceptorFrameBufferInfo` | static-reviewed; source authored; runtime pending; `InterceptorIPC.c` |
| `0x47A0E710` | 44 | `_InterceptorHideCursor` | PPC static-reviewed; source authored; runtime pending |
| `0x47A0E73C` | 40 | `_InterceptorShowCursor` | PPC static-reviewed; source authored; runtime pending |
| `0x47A0E764` | 52 | `_InterceptorFlushRect` | static-reviewed; source authored; runtime pending; `InterceptorIPC.c` |
| `0x47A0E798` | 52 | `_InterceptorAddDirtyRect` | static-reviewed; source authored; runtime pending; `InterceptorIPC.c` |
| `0x47A0E7CC` | 36 | `_InterceptorFlushDirtyRects` | static-reviewed; source authored; runtime pending; `InterceptorIPC.c` |
| `0x47A0E7F0` | 36 | `_InterceptorRepairPalette` | static-reviewed; source authored; runtime pending; `InterceptorIPC.c` |
| `0x47A0E814` | 36 | `_InterceptorDamagedPalette` | static-reviewed; source authored; runtime pending; `InterceptorIPC.c` |
| `0x47A0E838` | 72 | `_InterceptorGetDeviceAccessTokens` | PPC static-reviewed; source authored; runtime pending; `InterceptorIPC.c` |
| `0x47A0E880` | 332 | `__InterceptorEnableFrameBufferMapping` | static-reviewed; source authored; runtime pending; `InterceptorIPC.c`; `ppc/ipc.md` |
| `0x47A0E9CC` | 332 | `__InterceptorDisableFrameBufferMapping` | static-reviewed; source authored; runtime pending; `InterceptorIPC.c`; `ppc/ipc.md` |
| `0x47A0EB18` | 336 | `__InterceptorMapFrameBuffer` | static-reviewed; source authored; runtime pending; `InterceptorIPC.c` |
| `0x47A0EC68` | 384 | `__InterceptorGetBM34ToBM35Table` | static-reviewed; source authored; runtime pending; `InterceptorIPC.c` |
| `0x47A0EDE8` | 472 | `__InterceptorCompositeBits` | static-reviewed; source authored; runtime pending; `InterceptorIPC.c` |
| `0x47A0EFC0` | 704 | `__InterceptorFrameBufferInfo` | static-reviewed; source authored; runtime pending; `InterceptorIPC.c` |
| `0x47A0F280` | 284 | `__OldInterceptorSetNotifyPort` | static-reviewed; source authored; runtime pending; `InterceptorIPC.c`; `ppc/ipc.md` |
| `0x47A0F39C` | 436 | `__InterceptorAddRect` | static-reviewed; `InterceptorIPC.c`; runtime pending |
| `0x47A0F550` | 284 | `__InterceptorRemoveRect` | static-reviewed; `InterceptorIPC.c`; runtime pending |
| `0x47A0F66C` | 300 | `__InterceptorSetNotifyPort` | static-reviewed; `InterceptorIPC.c`; runtime pending |
| `0x47A0F798` | 392 | `__InterceptorGetBM35ToBM34Table` | static-reviewed; source authored; runtime pending; `InterceptorIPC.c` |
| `0x47A0F920` | 268 | `__InterceptorScreenCount` | PPC static-reviewed; source authored; runtime pending |
| `0x47A0FA2C` | 268 | `__InterceptorHideCursor` | PPC static-reviewed; source authored; runtime pending |
| `0x47A0FB38` | 268 | `__InterceptorShowCursor` | PPC static-reviewed; source authored; runtime pending |
| `0x47A0FC44` | 304 | `__InterceptorGetBM256ToBM38Table` | static-reviewed; source authored; runtime pending; `InterceptorIPC.c` |
| `0x47A0FD74` | 304 | `__InterceptorGetBM38ToBM256Table` | static-reviewed; source authored; runtime pending; `InterceptorIPC.c` |
| `0x47A0FEA4` | 172 | `__InterceptorFlushRect` | static-reviewed; source authored; runtime pending; `InterceptorIPC.c` |
| `0x47A0FF50` | 172 | `__InterceptorAddDirtyRect` | static-reviewed; source authored; runtime pending; `InterceptorIPC.c` |
| `0x47A0FFFC` | 128 | `__InterceptorFlushDirtyRects` | static-reviewed; source authored; runtime pending; `InterceptorIPC.c` |
| `0x47A1007C` | 96 | `__InterceptorRepairPalette` | static-reviewed; source authored; runtime pending; `InterceptorIPC.c` |
| `0x47A100DC` | 96 | `__InterceptorDamagedPalette` | static-reviewed; source authored; runtime pending; `InterceptorIPC.c` |
| `0x47A1013C` | 384 | `__InterceptorGetDeviceAccessTokens` | static-reviewed; source authored; runtime pending; `InterceptorIPC.c` |
| `0x47A102BC` | 96 | `__InterceptorShowCursorAsync` | PPC/i386 static-reviewed; source authored; runtime pending |
| `0x47A1031C` | 316 | `__InterceptorUnmapFrameBuffer` | static-reviewed; source authored; runtime pending; `InterceptorIPC.c` |
| `0x47A112EC` | 36 | `_NSEqualSizes` | linker-generated PIC import stub; no framework source body |
| `0x47A11310` | 36 | `_NSEqualRects` | linker-generated PIC import stub; no framework source body |
| `0x47A11334` | 36 | `j__InterceptorScreenCount` | linker-generated PIC import stub; no framework source body |
| `0x47A11358` | 36 | `j__InterceptorShowCursor` | linker-generated PIC import stub; no framework source body |
| `0x47A1137C` | 36 | `j__InterceptorHideCursor` | linker-generated PIC import stub; no framework source body |
| `0x47A113A0` | 36 | `_NSIsEmptyRect` | linker-generated PIC import stub; no framework source body |
| `0x47A113C4` | 36 | `_NSConvertWindowNumberToGlobal` | linker-generated PIC import stub; no framework source body |
| `0x47A113E8` | 36 | `_sel_getName` | linker-generated PIC import stub; no framework source body |
| `0x47A1140C` | 36 | `_objc_msgSendSuper` | linker-generated PIC import stub; no framework source body |
| `0x47A11430` | 36 | `_NSZoneFree` | linker-generated PIC import stub; no framework source body |
| `0x47A11454` | 36 | `_printf` | linker-generated PIC import stub; no framework source body |
| `0x47A11478` | 36 | `j__InterceptorCompositeBits` | linker-generated PIC import stub; no framework source body |
| `0x47A1149C` | 36 | `_NSIntersectionRect` | linker-generated PIC import stub; no framework source body |
| `0x47A114C0` | 36 | `_NSOffsetRect` | linker-generated PIC import stub; no framework source body |
| `0x47A114E4` | 36 | `_objc_msgSend_stret` | linker-generated PIC import stub; no framework source body |
| `0x47A11508` | 36 | `_bzero` | linker-generated PIC import stub; no framework source body |
| `0x47A1152C` | 36 | `_NSZoneMalloc` | linker-generated PIC import stub; no framework source body |
| `0x47A11550` | 36 | `_objc_msgSend` | linker-generated PIC import stub; no framework source body |
| `0x47A11574` | 36 | `_memset` | linker-generated PIC import stub; no framework source body |
| `0x47A11598` | 36 | `_NSLog` | linker-generated PIC import stub; no framework source body |
| `0x47A115BC` | 36 | `_pow` | linker-generated PIC import stub; no framework source body |
| `0x47A115E0` | 36 | `_malloc` | linker-generated PIC import stub; no framework source body |
| `0x47A11604` | 36 | `_free` | linker-generated PIC import stub; no framework source body |
| `0x47A11628` | 36 | `__IOSetCharValues` | linker-generated PIC import stub; no framework source body |
| `0x47A1164C` | 36 | `__IOSetIntValues` | linker-generated PIC import stub; no framework source body |
| `0x47A11670` | 36 | `_NXCloseEventStatus` | linker-generated PIC import stub; no framework source body |
| `0x47A11694` | 36 | `_NXSetAutoDimBrightness` | linker-generated PIC import stub; no framework source body |
| `0x47A116B8` | 36 | `_NXScreenBrightness` | linker-generated PIC import stub; no framework source body |
| `0x47A116DC` | 36 | `_NXAutoDimBrightness` | linker-generated PIC import stub; no framework source body |
| `0x47A11700` | 36 | `_NXOpenEventStatus` | linker-generated PIC import stub; no framework source body |
| `0x47A11724` | 36 | `_PSWait` | linker-generated PIC import stub; no framework source body |
| `0x47A11748` | 36 | `_PSgrestore` | linker-generated PIC import stub; no framework source body |
| `0x47A1176C` | 36 | `_PSsetexposurecolor` | linker-generated PIC import stub; no framework source body |
| `0x47A11790` | 36 | `_PSsetrgbcolor` | linker-generated PIC import stub; no framework source body |
| `0x47A117B4` | 36 | `_PSwindowdeviceround` | linker-generated PIC import stub; no framework source body |
| `0x47A117D8` | 36 | `_PSgsave` | linker-generated PIC import stub; no framework source body |
| `0x47A117FC` | 36 | `_PSsetautofill` | linker-generated PIC import stub; no framework source body |
| `0x47A11820` | 36 | `j__InterceptorDamagedPalette` | linker-generated PIC import stub; no framework source body |
| `0x47A11844` | 36 | `_sprintf` | linker-generated PIC import stub; no framework source body |
| `0x47A11868` | 36 | `_NSStringFromSelector` | linker-generated PIC import stub; no framework source body |
| `0x47A1188C` | 36 | `j__InterceptorDestroyContext` | linker-generated PIC import stub; no framework source body |
| `0x47A118B0` | 36 | `__IOGetIntValues` | linker-generated PIC import stub; no framework source body |
| `0x47A118D4` | 36 | `j__InterceptorGetDeviceAccessTokens` | linker-generated PIC import stub; no framework source body |
| `0x47A118F8` | 36 | `j__InterceptorCreateContext` | linker-generated PIC import stub; no framework source body |
| `0x47A1191C` | 36 | `j__InterceptorGetBM256ToBM38Table` | linker-generated PIC import stub; no framework source body |
| `0x47A11940` | 36 | `j__InterceptorGetBM35ToBM34Table` | linker-generated PIC import stub; no framework source body |
| `0x47A11964` | 36 | `j__InterceptorGetBM38ToBM256Table` | linker-generated PIC import stub; no framework source body |
| `0x47A11988` | 36 | `j__InterceptorGetBM34ToBM35Table` | linker-generated PIC import stub; no framework source body |
| `0x47A119AC` | 36 | `j__InterceptorUnmapFrameBuffer` | linker-generated PIC import stub; no framework source body |
| `0x47A119D0` | 36 | `j__InterceptorMapFrameBuffer` | linker-generated PIC import stub; no framework source body |
| `0x47A119F4` | 36 | `j__InterceptorFrameBufferInfo` | linker-generated PIC import stub; no framework source body |
| `0x47A11A18` | 36 | `_objc_setMultithreaded` | linker-generated PIC import stub; no framework source body |
| `0x47A11A3C` | 36 | `_port_set_add` | linker-generated PIC import stub; no framework source body |
| `0x47A11A60` | 36 | `_msg_send` | linker-generated PIC import stub; no framework source body |
| `0x47A11A84` | 36 | `_mach_error_string` | linker-generated PIC import stub; no framework source body |
| `0x47A11AA8` | 36 | `_msg_receive` | linker-generated PIC import stub; no framework source body |
| `0x47A11ACC` | 36 | `j___rendezvousPort` | linker-generated PIC import stub; no framework source body |
| `0x47A11AF0` | 36 | `_cthread_set_name` | linker-generated PIC import stub; no framework source body |
| `0x47A11B14` | 36 | `_ur_cthread_self` | linker-generated PIC import stub; no framework source body |
| `0x47A11B38` | 36 | `j__NSRemapMegaPixelDisplayForCurrentThread` | linker-generated PIC import stub; no framework source body |
| `0x47A11B5C` | 36 | `j___InterceptorRemoveRect` | linker-generated PIC import stub; no framework source body |
| `0x47A11B80` | 36 | `j___InterceptorAddRect` | linker-generated PIC import stub; no framework source body |
| `0x47A11BA4` | 36 | `j___InterceptorSetNotifyPort` | linker-generated PIC import stub; no framework source body |
| `0x47A11BC8` | 36 | `_task_get_special_port` | linker-generated PIC import stub; no framework source body |
| `0x47A11BEC` | 36 | `_thread_get_special_port` | linker-generated PIC import stub; no framework source body |
| `0x47A11C10` | 36 | `_thread_self` | linker-generated PIC import stub; no framework source body |
| `0x47A11C34` | 36 | `_port_allocate` | linker-generated PIC import stub; no framework source body |
| `0x47A11C58` | 36 | `_port_deallocate` | linker-generated PIC import stub; no framework source body |
| `0x47A11C7C` | 36 | `_port_set_remove` | linker-generated PIC import stub; no framework source body |
| `0x47A11CA0` | 36 | `_mach_error` | linker-generated PIC import stub; no framework source body |
| `0x47A11CC4` | 36 | `_port_set_allocate` | linker-generated PIC import stub; no framework source body |
| `0x47A11CE8` | 36 | `_memcpy` | linker-generated PIC import stub; no framework source body |
| `0x47A11D0C` | 36 | `_NSZoneRealloc` | linker-generated PIC import stub; no framework source body |
| `0x47A11D30` | 36 | `_netname_look_up` | linker-generated PIC import stub; no framework source body |
| `0x47A11D54` | 36 | `_bootstrap_look_up` | linker-generated PIC import stub; no framework source body |
| `0x47A11D78` | 36 | `_msg_rpc` | linker-generated PIC import stub; no framework source body |
| `0x47A11D9C` | 36 | `j___InterceptorGetDeviceAccessTokens` | linker-generated PIC import stub; no framework source body |
| `0x47A11DC0` | 36 | `j___InterceptorDamagedPalette` | linker-generated PIC import stub; no framework source body |
| `0x47A11DE4` | 36 | `j___InterceptorRepairPalette` | linker-generated PIC import stub; no framework source body |
| `0x47A11E08` | 36 | `j___InterceptorFlushDirtyRects` | linker-generated PIC import stub; no framework source body |
| `0x47A11E2C` | 36 | `j___InterceptorAddDirtyRect` | linker-generated PIC import stub; no framework source body |
| `0x47A11E50` | 36 | `j___InterceptorFlushRect` | linker-generated PIC import stub; no framework source body |
| `0x47A11E74` | 36 | `j___InterceptorShowCursorAsync` | linker-generated PIC import stub; no framework source body |
| `0x47A11E98` | 36 | `j___InterceptorHideCursor` | linker-generated PIC import stub; no framework source body |
| `0x47A11EBC` | 36 | `j___InterceptorFrameBufferInfo` | linker-generated PIC import stub; no framework source body |
| `0x47A11EE0` | 36 | `j___InterceptorCompositeBits` | linker-generated PIC import stub; no framework source body |
| `0x47A11F04` | 36 | `j___InterceptorScreenCount` | linker-generated PIC import stub; no framework source body |
| `0x47A11F28` | 36 | `j___InterceptorGetBM38ToBM256Table` | linker-generated PIC import stub; no framework source body |
| `0x47A11F4C` | 36 | `j___InterceptorGetBM256ToBM38Table` | linker-generated PIC import stub; no framework source body |
| `0x47A11F70` | 36 | `j___InterceptorUnmapFrameBuffer` | linker-generated PIC import stub; no framework source body |
| `0x47A11F94` | 36 | `j___InterceptorMapFrameBuffer` | linker-generated PIC import stub; no framework source body |
| `0x47A11FB8` | 36 | `j__Interceptor_mig_error` | linker-generated PIC import stub; no framework source body |
| `0x47A11FDC` | 36 | `_strncpy` | linker-generated PIC import stub; no framework source body |

Named Objective-C symbols (candidate module by class name; verify in module metadata):

| Address | Symbol | Candidate source module | Review status |
|---:|---|---|---|
| `0x47A028A0` | `+[NSDirectBitmap minDepthForGray:andColor:]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A028E0` | `-[NSDirectBitmap bitsPerPixel]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A028F0` | `-[NSDirectBitmap bitsPerSample]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A02900` | `-[NSDirectBitmap bytesPerPlane]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A02988` | `-[NSDirectBitmap bytesPerRow]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A029F4` | `-[NSDirectBitmap colorSpaceName]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A02A04` | `-[NSDirectBitmap conversionTable]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A02A3C` | `-[NSDirectBitmap inverseConversionTable]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A02A74` | `-[NSDirectBitmap _dataBuffer]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A02B00` | `-[NSDirectBitmap bitmapData]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A02BA0` | `-[NSDirectBitmap _flushInShape:]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A02D6C` | `-[NSDirectBitmap flush]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A02E14` | `-[NSDirectBitmap flushIn:]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A0316C` | `-[NSDirectBitmap dealloc]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A03234` | `-[NSDirectBitmap getBitmapDataPlanes:]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A03344` | `-[NSDirectBitmap pixelEncodings]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A033C8` | `-[NSDirectBitmap hasAlpha]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A033DC` | `-[NSDirectBitmap init]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A03454` | `-[NSDirectBitmap initForRect:inWindow:]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A035AC` | `-[NSDirectBitmap isPlanar]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A035C0` | `-[NSDirectBitmap _mapFramebufferForScreen:]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A036A8` | `-[NSDirectBitmap _initForRect:inWinNum:onScreen:]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A03A64` | `-[NSDirectBitmap isBuffered]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A03A78` | `-[NSDirectBitmap isDirectMapped]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A03A8C` | `-[NSDirectBitmap lockBitmap]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A03B98` | `-[NSDirectBitmap numberOfPlanes]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A03BBC` | `-[NSDirectBitmap pixelEncoding]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A03CCC` | `-[NSDirectBitmap pixelsWide]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A03CDC` | `-[NSDirectBitmap pixelsHigh]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A03CEC` | `-[NSDirectBitmap _updateBuffer]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A03DF0` | `-[NSDirectBitmap samplesPerPixel]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A03E00` | `-[NSDirectBitmap setBuffered:]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A03F18` | `-[NSDirectBitmap _canUseDirectMapping]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A03FE8` | `-[NSDirectBitmap setDirectMapped:]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A040E4` | `-[NSDirectBitmap tryLockBitmap]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A04138` | `-[NSDirectBitmap unlockBitmap]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A0418C` | `-[NSDirectBitmap _updateBackingStoreForRect:]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A04310` | `-[NSDirectBitmap _updateForRect:inWinNum:onScreen:]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A046E0` | `-[NSDirectBitmap updateForRect:inWindow:]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A047D8` | `-[NSDirectBitmap updateState]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A04884` | `-[NSDirectBitmap hideCursor]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A048C0` | `-[NSDirectBitmap showCursor]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A048FC` | `-[NSDirectBitmap currentPalette]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A04938` | `-[NSDirectBitmap _setDelegate:]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A0498C` | `-[NSDirectBitmap _framebuffer]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A0499C` | `-[NSDirectBitmap _setFlushOnExposure:]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A049B0` | `-[NSDirectBitmap _screenBoundsOrigin]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A04A28` | `-[NSDirectBitmap _isUnobscured]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A04AAC` | `-[NSDirectBitmap _isTotallyObscured]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A04B10` | `-[NSDirectBitmap _setViewClip:]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A04BB4` | `-[NSDirectBitmap _viewClipShape:]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A04BC4` | `-[NSDirectBitmap _setViewClipShape:]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A04C4C` | `-[NSDirectBitmap areaWillMove:by:]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A04CE0` | `-[NSDirectBitmap areaDidMove:by:]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A04DC8` | `-[NSDirectBitmap areaWillObscure:inRect:]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A04F2C` | `-[NSDirectBitmap areaDidReveal:inRect:]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A05108` | `-[NSDirectBitmap areaWasOrderedIn:]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A05154` | `-[NSDirectBitmap areaWasOrderedOut:]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A051A0` | `-[NSDirectBitmap areaIsInvalid:]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A051CC` | `-[NSDirectBitmap areaChangedScreen:from:to:]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A05210` | `-[NSDirectBitmap areaWindowFreed:]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A0523C` | `-[NSDirectBitmap areaDidChangeBuffering:toType:]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A05254` | `-[NSDirectBitmap(Obsolete) colorSpace]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A05288` | `-[NSDirectBitmap(Obsolete) data]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A052BC` | `+[NSDirectPalette defaultPalette]` | `NSDirectPalette.m` | static-reviewed; source authored; runtime pending |
| `0x47A05308` | `+[NSDirectPalette defaultColorPalette]` | `NSDirectPalette.m` | static-reviewed; source authored; runtime pending |
| `0x47A05354` | `+[NSDirectPalette defaultGrayPalette]` | `NSDirectPalette.m` | static-reviewed; source authored; runtime pending |
| `0x47A054E8` | `+[NSDirectPalette currentPalette]` | `NSDirectPalette.m` | static-reviewed; source authored; runtime pending |
| `0x47A0562C` | `-[NSDirectPalette initWithArrayOfColors:]` | `NSDirectPalette.m` | static-reviewed; source authored; runtime pending |
| `0x47A056F8` | `-[NSDirectPalette init]` | `NSDirectPalette.m` | static-reviewed; source authored; runtime pending |
| `0x47A058E0` | `-[NSDirectPalette colorAtIndex:]` | `NSDirectPalette.m` | static-reviewed; source authored; runtime pending |
| `0x47A0591C` | `-[NSDirectPalette indexForColor:]` | `NSDirectPalette.m` | static-reviewed; source authored; runtime pending |
| `0x47A05B6C` | `-[NSDirectPalette count]` | `NSDirectPalette.m` | static-reviewed; source authored; runtime pending |
| `0x47A05BA8` | `-[NSDirectPalette dealloc]` | `NSDirectPalette.m` | static-reviewed; source authored; runtime pending |
| `0x47A05C38` | `-[NSDirectPalette objectEnumerator]` | `NSDirectPalette.m` | static-reviewed; source authored; runtime pending |
| `0x47A05C74` | `-[NSDirectPalette rawMachinePalette]` | `NSDirectPalette.m` | static-reviewed; source authored; runtime pending |
| `0x47A05EBC` | `-[NSDirectPalette setColor:atIndex:]` | `NSDirectPalette.m` | static-reviewed; source authored; runtime pending |
| `0x47A05F88` | `-[NSDirectPalette setRed:green:blue:atIndex:]` | `NSDirectPalette.m` | static-reviewed; source authored; runtime pending |
| `0x47A0601C` | `-[NSDirectPalette getRed:green:blue:atIndex:]` | `NSDirectPalette.m` | static-reviewed; source authored; runtime pending |
| `0x47A0607C` | `-[NSDirectPalette setColors:atIndices:]` | `NSDirectPalette.m` | static-reviewed; source authored; runtime pending |
| `0x47A0616C` | `-[NSDirectPalette copy]` | `NSDirectPalette.m` | static-reviewed; source authored; runtime pending |
| `0x47A061B8` | `-[NSDirectPalette mutableCopy]` | `NSDirectPalette.m` | static-reviewed; source authored; runtime pending |
| `0x47A06204` | `-[NSDirectPalette copyWithZone:]` | `NSDirectPalette.m` | static-reviewed; source authored; runtime pending |
| `0x47A06238` | `-[NSDirectPalette mutableCopyWithZone:]` | `NSDirectPalette.m` | static-reviewed; source authored; runtime pending |
| `0x47A06298` | `-[NSDirectPalette encodeWithCoder:]` | `NSDirectPalette.m` | static-reviewed; source authored; runtime pending |
| `0x47A062D8` | `-[NSDirectPalette initWithCoder:]` | `NSDirectPalette.m` | static-reviewed; source authored; runtime pending |
| `0x47A06378` | `-[NSDirectPalette isEqual:]` | `NSDirectPalette.m` | static-reviewed; source authored; runtime pending |
| `0x47A06470` | `-[NSDirectPalette blendedPaletteWithFraction:ofColor:]` | `NSDirectPalette.m` | static-reviewed; source authored; runtime pending |
| `0x47A06700` | `-[NSDirectScreen _clearModeInfo]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A06788` | `-[NSDirectScreen initWithScreen:]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A06974` | `-[NSDirectScreen dealloc]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A06AE4` | `-[NSDirectScreen screenSize]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A06BB0` | `-[NSDirectScreen pixelsWide]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A06C0C` | `-[NSDirectScreen pixelsHigh]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A06C68` | `-[NSDirectScreen addressForPoint:]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A06E24` | `-[NSDirectScreen availableDisplayModes]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A07814` | `-[NSDirectScreen availableDisplayModesForOptions:]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A0798C` | `-[NSDirectScreen bestModeForFormat:width:height:]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A07E18` | `-[NSDirectScreen bestModeForOptions:]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A07E94` | `-[NSDirectScreen currentMode]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A07FBC` | `-[NSDirectScreen bitsPerPixel]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A08034` | `-[NSDirectScreen bitsPerSample]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A080AC` | `-[NSDirectScreen bytesPerRow]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A0815C` | `-[NSDirectScreen bytesPerPlane]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A081B8` | `-[NSDirectScreen numberOfPlanes]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A081C8` | `-[NSDirectScreen _canLockWithMode:]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A08208` | `-[NSDirectScreen colorSpaceName]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A08250` | `-[NSDirectScreen bitmapData]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A082C4` | `-[NSDirectScreen getBitmapDataPlanes:]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A08314` | `-[NSDirectScreen isPlanar]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A08324` | `-[NSDirectScreen hasAlpha]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A08334` | `-[NSDirectScreen deviceSlot]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A08370` | `-[NSDirectScreen deviceUnit]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A083AC` | `-[NSDirectScreen displayIsShielded]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A083C4` | `-[NSDirectScreen driver]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A08400` | `-[NSDirectScreen fadeDisplay:toColor:]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A08518` | `-[NSDirectScreen _fadeIn:]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A08680` | `-[NSDirectScreen fadeDisplayInFromColor:]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A08988` | `-[NSDirectScreen _fadeOut:]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A08B04` | `-[NSDirectScreen fadeDisplayOutToColor:]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A08E0C` | `-[NSDirectScreen fadeDuration]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A08E20` | `-[NSDirectScreen fadeInProgress]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A08E38` | `-[NSDirectScreen fadeApplied]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A08E50` | `-[NSDirectScreen _lockWithMode:]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A08ED8` | `-[NSDirectScreen pixelEncoding]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A08F20` | `-[NSDirectScreen samplesPerPixel]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A08F98` | `-[NSDirectScreen screenNumber]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A08FD4` | `-[NSDirectScreen canSetPalette]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A0905C` | `-[NSDirectScreen setPalette:]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A0915C` | `-[NSDirectScreen currentPalette]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A09170` | `-[NSDirectScreen setPaletteAtNextBlankingInterval:]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A09270` | `-[NSDirectScreen setFadeDuration:]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A092C0` | `-[NSDirectScreen shieldDisplay]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A0954C` | `-[NSDirectScreen shieldingWindow]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A09560` | `-[NSDirectScreen switchToDisplayMode:]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A097B8` | `-[NSDirectScreen _unlock]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A09838` | `-[NSDirectScreen unshieldDisplay]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A09990` | `-[NSDirectScreen hideCursor]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A099B8` | `-[NSDirectScreen showCursor]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A099E0` | `-[NSDirectScreen(NSPrivate) setGamma:]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A09A44` | `-[NSDirectScreen(NSPrivate) setGammaRed:green:blue:]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A09BBC` | `-[NSDirectScreen(NSPrivate) setGammaTableOfSize:red:green:blue:]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A09F94` | `-[NSDirectScreen(NSPrivate) _loadPalette:]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A0A0CC` | `-[NSDirectScreen(NSPrivate) _createBackingStore]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A0A248` | `-[NSDirectScreen(NSPrivate) _destroyBackingStore]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A0A4A4` | `-[NSDirectScreen(Obsolete) colorSpace]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A0A4D8` | `-[NSDirectScreen(Obsolete) data]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A0A628` | `-[NSFramebuffer initWithScreen:]` | `NSFramebuffer.m` | static-reviewed; runtime pending |
| `0x47A0A660` | `-[NSFramebuffer initWithScreen:andMapIfPossible:]` | `NSFramebuffer.m` | static-reviewed; runtime pending |
| `0x47A0A72C` | `-[NSFramebuffer initFromScreen:andMapIfPossible:]` | `NSFramebuffer.m` | static-reviewed; source authored; runtime pending |
| `0x47A0A9E0` | `-[NSFramebuffer unmapScreen]` | `NSFramebuffer.m` | static-reviewed; source authored; runtime pending |
| `0x47A0AA3C` | `-[NSFramebuffer remapScreen]` | `NSFramebuffer.m` | static-reviewed; source authored; runtime pending |
| `0x47A0AC5C` | `-[NSFramebuffer isMappable]` | `NSFramebuffer.m` | static-reviewed; runtime pending |
| `0x47A0AC70` | `-[NSFramebuffer screenBounds]` | `NSFramebuffer.m` | static-reviewed; runtime pending; architecture difference recorded |
| `0x47A0AD48` | `-[NSFramebuffer screenNumber]` | `NSFramebuffer.m` | static-reviewed; runtime pending |
| `0x47A0AD58` | `-[NSFramebuffer conversionTable]` | `NSFramebuffer.m` | static-reviewed; source authored; runtime pending |
| `0x47A0AE10` | `-[NSFramebuffer inverseConversionTable]` | `NSFramebuffer.m` | static-reviewed; source authored; runtime pending |
| `0x47A0AEC8` | `-[NSFramebuffer addressForPoint:]` | `NSFramebuffer.m` | static-reviewed; runtime pending |
| `0x47A0AF58` | `-[NSFramebuffer pixelEncoding]` | `NSFramebuffer.m` | static-reviewed; runtime pending |
| `0x47A0AFBC` | `-[NSFramebuffer driver]` | `NSFramebuffer.m` | static-reviewed; runtime pending |
| `0x47A0B020` | `-[NSFramebuffer deviceUnit]` | `NSFramebuffer.m` | static-reviewed; runtime pending |
| `0x47A0B030` | `-[NSFramebuffer deviceSlot]` | `NSFramebuffer.m` | static-reviewed; runtime pending |
| `0x47A0B040` | `-[NSFramebuffer retain]` | `NSFramebuffer.m` | static-reviewed; runtime pending |
| `0x47A0B04C` | `-[NSFramebuffer release]` | `NSFramebuffer.m` | static-reviewed; runtime pending |
| `0x47A0B058` | `-[NSFramebuffer retainCount]` | `NSFramebuffer.m` | static-reviewed; runtime pending |
| `0x47A0B068` | `-[NSFramebuffer dealloc]` | `NSFramebuffer.m` | static-reviewed; runtime pending |
| `0x47A0B074` | `-[NSFramebuffer canLockWithMode:]` | `NSFramebuffer.m` | static-reviewed; runtime pending |
| `0x47A0B084` | `-[NSFramebuffer lockWithMode:]` | `NSFramebuffer.m` | static-reviewed; runtime pending |
| `0x47A0B090` | `-[NSFramebuffer unlock]` | `NSFramebuffer.m` | static-reviewed; runtime pending |
| `0x47A0B09C` | `-[NSFramebuffer(NSPrivate) _interceptorClient]` | `NSFramebuffer.m` | static-reviewed; runtime pending |
| `0x47A0B0B8` | `-[NSInterceptedRect initForRect:inWindow:onFramebuffer:forClient:]` | `NSInterceptedRect.m` | static-reviewed; source authored; runtime pending; `ppc/client-state.md` |
| `0x47A0B254` | `-[NSInterceptedRect setTarget:]` | `NSInterceptedRect.m` | static-reviewed; source authored; runtime pending; `ppc/client-state.md` |
| `0x47A0B264` | `-[NSInterceptedRect target]` | `NSInterceptedRect.m` | static-reviewed; source authored; runtime pending; `ppc/client-state.md` |
| `0x47A0B274` | `-[NSInterceptedRect lockRect]` | `NSInterceptedRect.m` | static-reviewed; source authored; runtime pending; `ppc/client-state.md` |
| `0x47A0B2BC` | `-[NSInterceptedRect unlockRect]` | `NSInterceptedRect.m` | static-reviewed; source authored; runtime pending; `ppc/client-state.md` |
| `0x47A0B300` | `-[NSInterceptedRect isLocked]` | `NSInterceptedRect.m` | static-reviewed; source authored; runtime pending; `ppc/client-state.md` |
| `0x47A0B330` | `-[NSInterceptedRect currentScreenRect]` | `NSInterceptedRect.m` | static-reviewed; source authored; runtime pending; `ppc/client-state.md` |
| `0x47A0B35C` | `-[NSInterceptedRect currentScreenRectShape]` | `NSInterceptedRect.m` | static-reviewed; source authored; runtime pending; `ppc/client-state.md` |
| `0x47A0B36C` | `-[NSInterceptedRect currentClipList:count:]` | `NSInterceptedRect.m` | static-reviewed; source authored; runtime pending |
| `0x47A0B3CC` | `-[NSInterceptedRect compositeBits:withOp:]` | `NSInterceptedRect.m` | static-reviewed; source authored; runtime pending |
| `0x47A0B42C` | `-[NSInterceptedRect removeFromWindowServer]` | `NSInterceptedRect.m` | static-reviewed; source authored; runtime pending; `ppc/client-state.md` |
| `0x47A0B468` | `-[NSInterceptedRect dealloc]` | `NSInterceptedRect.m` | static-reviewed; source authored; runtime pending; `ppc/client-state.md` |
| `0x47A0B4FC` | `-[NSInterceptedRect uniqueID]` | `NSInterceptedRect.m` | static-reviewed; source authored; runtime pending |
| `0x47A0B50C` | `-[NSInterceptedRect windowNumber]` | `NSInterceptedRect.m` | static-reviewed; source authored; runtime pending; `ppc/client-state.md` |
| `0x47A0B51C` | `-[NSInterceptedRect rectangle]` | `NSInterceptedRect.m` | static-reviewed; source authored; runtime pending; `ppc/client-state.md` |
| `0x47A0B548` | `-[NSInterceptedRect isTotallyVisible]` | `NSInterceptedRect.m` | static-reviewed; source authored; runtime pending; `ppc/client-state.md` |
| `0x47A0B55C` | `-[NSInterceptedRect isTotallyObscured]` | `NSInterceptedRect.m` | static-reviewed; source authored; runtime pending; `ppc/client-state.md` |
| `0x47A0B570` | `-[NSInterceptedRect _flags]` | `NSInterceptedRect.m` | static-reviewed; source authored; runtime pending; `ppc/client-state.md` |
| `0x47A0B580` | `-[NSInterceptedRect framebuffer]` | `NSInterceptedRect.m` | static-reviewed; source authored; runtime pending; `ppc/client-state.md` |
| `0x47A0B590` | `-[NSInterceptedRect _handleMsg:withReply:]` | `NSInterceptedRect.m` | static-reviewed; runtime pending |
| `0x47A0BD04` | `+[NSInterceptorClient initialize]` | `NSInterceptorClient.m` | static-reviewed; source authored; runtime pending; `ppc/client-state.md` |
| `0x47A0BDC0` | `-[NSInterceptorClient init]` | `NSInterceptorClient.m` | static-reviewed; runtime pending |
| `0x47A0BEDC` | `-[NSInterceptorClient dealloc]` | `NSInterceptorClient.m` | static-reviewed; runtime pending |
| `0x47A0C060` | `-[NSInterceptorClient setHandlingThread:]` | `NSInterceptorClient.m` | static-reviewed; runtime pending |
| `0x47A0C0CC` | `-[NSInterceptorClient handlingThread]` | `NSInterceptorClient.m` | static-reviewed; runtime pending |
| `0x47A0C108` | `-[NSInterceptorClient interceptorPort]` | `NSInterceptorClient.m` | static-reviewed; runtime pending |
| `0x47A0C23C` | `-[NSInterceptorClient handleInterceptorMessage:withReply:]` | `NSInterceptorClient.m` | static-reviewed; runtime pending |
| `0x47A0C348` | `-[NSInterceptorClient _addInterceptedRect:returnedScreenRect:returnedFlags:]` | `NSInterceptorClient.m` | static-reviewed; runtime pending |
| `0x47A0C578` | `-[NSInterceptorClient _removeInterceptedRect:]` | `NSInterceptorClient.m` | static-reviewed; runtime pending |
| `0x47A0C618` | `-[NSInterceptorClient _context]` | `NSInterceptorClient.m` | static-reviewed; runtime pending |
| `0x47A0C628` | `-[NSInterceptorClient windowServerPortDeath:]` | `NSInterceptorClient.m` | static-reviewed; runtime pending |
| `0x47A0C680` | `-[NSInterceptorClient _notifyHandler]` | `NSInterceptorClient.m` | static-reviewed; runtime pending |
| `0x47A0C8F8` | `-[NSInterceptorClient startHandlingThread]` | `NSInterceptorClient.m` | static-reviewed; runtime pending |
| `0x47A0D648` | `-[NSShape init]` | `NSShape.m` | static-reviewed; runtime pending |
| `0x47A0D6B4` | `-[NSShape initFromRect:]` | `NSShape.m` | static-reviewed; runtime pending |
| `0x47A0D734` | `-[NSShape intersectWithShape:]` | `NSShape.m` | static-reviewed; runtime pending |
| `0x47A0D77C` | `-[NSShape unionWithShape:]` | `NSShape.m` | static-reviewed; runtime pending |
| `0x47A0D7C4` | `-[NSShape differenceWithShape:]` | `NSShape.m` | static-reviewed; runtime pending |
| `0x47A0D80C` | `-[NSShape isEmpty]` | `NSShape.m` | static-reviewed; runtime pending |
| `0x47A0D834` | `-[NSShape isEqual:]` | `NSShape.m` | static-reviewed; runtime pending |
| `0x47A0D880` | `-[NSShape copyWithZone:]` | `NSShape.m` | static-reviewed; runtime pending |
| `0x47A0D924` | `-[NSShape offsetShape:]` | `NSShape.m` | static-reviewed; runtime pending |
| `0x47A0D978` | `-[NSShape rectEnumerator]` | `NSShape.m` | static-reviewed; runtime pending |
| `0x47A0D9D8` | `-[NSShape dealloc]` | `NSShape.m` | static-reviewed; runtime pending |
| `0x47A0DA30` | `-[NSShape description]` | `NSShape.m` | static-reviewed; source authored; runtime pending |
| `0x47A0DB8C` | `-[_NSShapeEnumerator initForShapeImpl:]` | `NSShape.m` | static-reviewed; runtime pending |
| `0x47A0DBE8` | `-[_NSShapeEnumerator nextRect]` | `NSShape.m` | static-reviewed; runtime pending |
| `0x47A0DD54` | `-[NSSimpleBitmap initWithBitmapDataPlanes:pixelsWide:pixelsHigh:bitsPerSample:samplesPerPixel:hasAlpha:isPlanar:colorSpaceName:bytesPerRow:bitsPerPixel:]` | `NSSimpleBitmap.m` | static-reviewed; runtime pending |
| `0x47A0DE90` | `-[NSSimpleBitmap bitmapData]` | `NSSimpleBitmap.m` | static-reviewed; runtime pending |
| `0x47A0DEA0` | `-[NSSimpleBitmap getBitmapDataPlanes:]` | `NSSimpleBitmap.m` | static-reviewed; runtime pending |
| `0x47A0DF24` | `-[NSSimpleBitmap isPlanar]` | `NSSimpleBitmap.m` | static-reviewed; runtime pending |
| `0x47A0DF38` | `-[NSSimpleBitmap hasAlpha]` | `NSSimpleBitmap.m` | static-reviewed; runtime pending |
| `0x47A0DF4C` | `-[NSSimpleBitmap samplesPerPixel]` | `NSSimpleBitmap.m` | static-reviewed; runtime pending |
| `0x47A0DF5C` | `-[NSSimpleBitmap bitsPerPixel]` | `NSSimpleBitmap.m` | static-reviewed; runtime pending |
| `0x47A0DF6C` | `-[NSSimpleBitmap bitsPerSample]` | `NSSimpleBitmap.m` | static-reviewed; runtime pending |
| `0x47A0DF7C` | `-[NSSimpleBitmap bytesPerRow]` | `NSSimpleBitmap.m` | static-reviewed; runtime pending |
| `0x47A0DF8C` | `-[NSSimpleBitmap bytesPerPlane]` | `NSSimpleBitmap.m` | static-reviewed; runtime pending |
| `0x47A0DFB0` | `-[NSSimpleBitmap numberOfPlanes]` | `NSSimpleBitmap.m` | static-reviewed; runtime pending |
| `0x47A0DFD4` | `-[NSSimpleBitmap colorSpaceName]` | `NSSimpleBitmap.m` | static-reviewed; runtime pending |
| `0x47A0DFE4` | `-[NSSimpleBitmap pixelsWide]` | `NSSimpleBitmap.m` | static-reviewed; runtime pending |
| `0x47A0DFF4` | `-[NSSimpleBitmap pixelsHigh]` | `NSSimpleBitmap.m` | static-reviewed; runtime pending |
| `0x47A0E004` | `-[NSSimpleBitmap dealloc]` | `NSSimpleBitmap.m` | static-reviewed; runtime pending |
| `0x47A0E064` | `-[NSSimpleBitmap(Obsolete) colorSpace]` | `NSSimpleBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A0E098` | `-[NSSimpleBitmap(Obsolete) data]` | `NSSimpleBitmap.m` | static-reviewed; source authored; runtime pending |

## i386 DR2

IDA function records: 419; symbol records: 629.

| Address | Size | IDA names | Review status |
|---:|---:|---|---|
| `0x47A00CBC` | 20 | `dyld_stub_binding_helper` | unexamined |
| `0x47A00CD0` | 14 | `__dyld_func_lookup` | unexamined |
| `0x47A00CE0` | 543 | `_CopyLong` | static-reviewed; runtime pending; `NSDirectBitmap.m` |
| `0x47A00F00` | 602 | `_CopyShort` | static-reviewed; runtime pending; `NSDirectBitmap.m` |
| `0x47A0115C` | 132 | `_CopyByte` | static-reviewed; runtime pending; `NSDirectBitmap.m` |
| `0x47A011E0` | 34 | `+[NSDirectBitmap minDepthForGray:andColor:]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A01204` | 13 | `-[NSDirectBitmap bitsPerPixel]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A01214` | 13 | `-[NSDirectBitmap bitsPerSample]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A01224` | 71 | `-[NSDirectBitmap bytesPerPlane]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A0126C` | 64 | `-[NSDirectBitmap bytesPerRow]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A012AC` | 13 | `-[NSDirectBitmap colorSpaceName]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A012BC` | 32 | `-[NSDirectBitmap conversionTable]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A012DC` | 32 | `-[NSDirectBitmap inverseConversionTable]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A012FC` | 84 | `-[NSDirectBitmap _dataBuffer]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A01350` | 118 | `-[NSDirectBitmap bitmapData]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A013C8` | 560 | `-[NSDirectBitmap _flushInShape:]` | static-reviewed; source authored; runtime pending |
| `0x47A015F8` | 80 | `-[NSDirectBitmap flush]` | static-reviewed; source authored; runtime pending; `i386/direct-bitmap.md` |
| `0x47A01648` | 873 | `-[NSDirectBitmap flushIn:]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A019B4` | 197 | `-[NSDirectBitmap dealloc]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A01A7C` | 214 | `-[NSDirectBitmap getBitmapDataPlanes:]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A01B54` | 112 | `-[NSDirectBitmap pixelEncodings]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A01BC4` | 14 | `-[NSDirectBitmap hasAlpha]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A01BD4` | 91 | `-[NSDirectBitmap init]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A01C30` | 326 | `-[NSDirectBitmap initForRect:inWindow:]` | static-reviewed; source authored; runtime pending |
| `0x47A01D78` | 14 | `-[NSDirectBitmap isPlanar]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A01D88` | 214 | `-[NSDirectBitmap _mapFramebufferForScreen:]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A01E60` | 857 | `-[NSDirectBitmap _initForRect:inWinNum:onScreen:]` | static-reviewed; source authored; runtime pending |
| `0x47A021BC` | 14 | `-[NSDirectBitmap isBuffered]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A021CC` | 14 | `-[NSDirectBitmap isDirectMapped]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A021DC` | 213 | `-[NSDirectBitmap lockBitmap]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A022B4` | 24 | `-[NSDirectBitmap numberOfPlanes]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A022CC` | 215 | `-[NSDirectBitmap pixelEncoding]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A023A4` | 13 | `-[NSDirectBitmap pixelsWide]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A023B4` | 13 | `-[NSDirectBitmap pixelsHigh]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A023C4` | 246 | `-[NSDirectBitmap _updateBuffer]` | static-reviewed; source authored; runtime pending |
| `0x47A024BC` | 13 | `-[NSDirectBitmap samplesPerPixel]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A024CC` | 239 | `-[NSDirectBitmap setBuffered:]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A025BC` | 167 | `-[NSDirectBitmap _canUseDirectMapping]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A02664` | 206 | `-[NSDirectBitmap setDirectMapped:]` | static-reviewed; source authored; runtime pending |
| `0x47A02734` | 49 | `-[NSDirectBitmap tryLockBitmap]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A02768` | 48 | `-[NSDirectBitmap unlockBitmap]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A02798` | 304 | `-[NSDirectBitmap _updateBackingStoreForRect:]` | static-reviewed; source authored; runtime pending |
| `0x47A028C8` | 948 | `-[NSDirectBitmap _updateForRect:inWinNum:onScreen:]` | static-reviewed; source authored; runtime pending |
| `0x47A02C7C` | 239 | `-[NSDirectBitmap updateForRect:inWindow:]` | static-reviewed; source authored; runtime pending |
| `0x47A02D6C` | 181 | `-[NSDirectBitmap updateState]` | static-reviewed; source authored; runtime pending |
| `0x47A02E24` | 41 | `-[NSDirectBitmap hideCursor]` | static-reviewed; source authored; runtime pending |
| `0x47A02E50` | 41 | `-[NSDirectBitmap showCursor]` | static-reviewed; source authored; runtime pending |
| `0x47A02E7C` | 34 | `-[NSDirectBitmap currentPalette]` | static-reviewed; source authored; runtime pending |
| `0x47A02EA0` | 68 | `-[NSDirectBitmap _setDelegate:]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A02EE4` | 13 | `-[NSDirectBitmap _framebuffer]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A02EF4` | 20 | `-[NSDirectBitmap _setFlushOnExposure:]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A02F08` | 81 | `-[NSDirectBitmap _screenBoundsOrigin]` | static-reviewed; source authored; runtime pending |
| `0x47A02F5C` | 120 | `-[NSDirectBitmap _isUnobscured]` | static-reviewed; source authored; runtime pending |
| `0x47A02FD4` | 78 | `-[NSDirectBitmap _isTotallyObscured]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A03024` | 123 | `-[NSDirectBitmap _setViewClip:]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A030A0` | 16 | `-[NSDirectBitmap _viewClipShape:]` | static-reviewed; source authored; runtime pending; `i386/direct-bitmap.md` |
| `0x47A030B0` | 105 | `-[NSDirectBitmap _setViewClipShape:]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A0311C` | 123 | `-[NSDirectBitmap areaWillMove:by:]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A03198` | 217 | `-[NSDirectBitmap areaDidMove:by:]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A03274` | 308 | `-[NSDirectBitmap areaWillObscure:inRect:]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A033A8` | 434 | `-[NSDirectBitmap areaDidReveal:inRect:]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A0355C` | 46 | `-[NSDirectBitmap areaWasOrderedIn:]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A0358C` | 46 | `-[NSDirectBitmap areaWasOrderedOut:]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A035BC` | 34 | `-[NSDirectBitmap areaIsInvalid:]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A035E0` | 51 | `-[NSDirectBitmap areaChangedScreen:from:to:]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A03614` | 34 | `-[NSDirectBitmap areaWindowFreed:]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A03638` | 16 | `-[NSDirectBitmap areaDidChangeBuffering:toType:]` | static-reviewed; source authored; runtime pending; `NSDirectBitmap.m` |
| `0x47A03648` | 29 | `-[NSDirectBitmap(Obsolete) colorSpace]` | static-reviewed; source authored; runtime pending |
| `0x47A03668` | 29 | `-[NSDirectBitmap(Obsolete) data]` | static-reviewed; source authored; runtime pending |
| `0x47A03688` | 65 | `+[NSDirectPalette defaultPalette]` | static-reviewed; source authored; runtime pending |
| `0x47A036CC` | 230 | `+[NSDirectPalette currentPalette]` | static-reviewed; source authored; runtime pending |
| `0x47A037B4` | 180 | `-[NSDirectPalette initWithArrayOfColors:]` | static-reviewed; source authored; runtime pending |
| `0x47A03868` | 391 | `-[NSDirectPalette init]` | static-reviewed; source authored; runtime pending |
| `0x47A039F0` | 38 | `-[NSDirectPalette colorAtIndex:]` | static-reviewed; source authored; runtime pending |
| `0x47A03A18` | 572 | `-[NSDirectPalette indexForColor:]` | static-reviewed; source authored; runtime pending |
| `0x47A03C54` | 34 | `-[NSDirectPalette count]` | static-reviewed; source authored; runtime pending |
| `0x47A03C78` | 120 | `-[NSDirectPalette dealloc]` | static-reviewed; source authored; runtime pending |
| `0x47A03CF0` | 34 | `-[NSDirectPalette objectEnumerator]` | static-reviewed; source authored; runtime pending |
| `0x47A03D14` | 557 | `-[NSDirectPalette rawMachinePalette]` | static-reviewed; source authored; runtime pending |
| `0x47A03F44` | 169 | `-[NSDirectPalette setColor:atIndex:]` | static-reviewed; source authored; runtime pending |
| `0x47A03FF0` | 82 | `-[NSDirectPalette setRed:green:blue:atIndex:]` | static-reviewed; source authored; runtime pending |
| `0x47A04044` | 70 | `-[NSDirectPalette getRed:green:blue:atIndex:]` | static-reviewed; source authored; runtime pending |
| `0x47A0408C` | 220 | `-[NSDirectPalette setColors:atIndices:]` | static-reviewed; source authored; runtime pending |
| `0x47A04168` | 52 | `-[NSDirectPalette copy]` | static-reviewed; source authored; runtime pending |
| `0x47A0419C` | 52 | `-[NSDirectPalette mutableCopy]` | static-reviewed; source authored; runtime pending |
| `0x47A041D0` | 33 | `-[NSDirectPalette copyWithZone:]` | static-reviewed; source authored; runtime pending |
| `0x47A041F4` | 79 | `-[NSDirectPalette mutableCopyWithZone:]` | static-reviewed; source authored; runtime pending |
| `0x47A04244` | 38 | `-[NSDirectPalette encodeWithCoder:]` | static-reviewed; source authored; runtime pending |
| `0x47A0426C` | 136 | `-[NSDirectPalette initWithCoder:]` | static-reviewed; source authored; runtime pending |
| `0x47A042F4` | 200 | `-[NSDirectPalette isEqual:]` | static-reviewed; source authored; runtime pending |
| `0x47A043BC` | 645 | `-[NSDirectPalette blendedPaletteWithFraction:ofColor:]` | static-reviewed; source authored; runtime pending |
| `0x47A04644` | 103 | `-[NSDirectScreen _clearModeInfo]` | static-reviewed; source authored; runtime pending |
| `0x47A046AC` | 460 | `-[NSDirectScreen initWithScreen:]` | static-reviewed; source authored; runtime pending |
| `0x47A04878` | 367 | `-[NSDirectScreen dealloc]` | static-reviewed; source authored; runtime pending |
| `0x47A049E8` | 189 | `-[NSDirectScreen screenSize]` | static-reviewed; source authored; runtime pending |
| `0x47A04AA8` | 62 | `-[NSDirectScreen pixelsWide]` | static-reviewed; source authored; runtime pending |
| `0x47A04AE8` | 62 | `-[NSDirectScreen pixelsHigh]` | static-reviewed; source authored; runtime pending |
| `0x47A04B28` | 257 | `-[NSDirectScreen addressForPoint:]` | static-reviewed; source authored; runtime pending |
| `0x47A04C2C` | 2861 | `-[NSDirectScreen availableDisplayModes]` | static-reviewed; source authored; runtime pending |
| `0x47A0575C` | 447 | `-[NSDirectScreen availableDisplayModesForOptions:]` | static-reviewed; source authored; runtime pending |
| `0x47A0591C` | 1289 | `-[NSDirectScreen bestModeForFormat:width:height:]` | static-reviewed; source authored; runtime pending |
| `0x47A05E28` | 113 | `-[NSDirectScreen bestModeForOptions:]` | static-reviewed; source authored; runtime pending |
| `0x47A05E9C` | 258 | `-[NSDirectScreen currentMode]` | static-reviewed; source authored; runtime pending |
| `0x47A05FA0` | 101 | `-[NSDirectScreen bitsPerPixel]` | static-reviewed; source authored; runtime pending |
| `0x47A06008` | 101 | `-[NSDirectScreen bitsPerSample]` | static-reviewed; source authored; runtime pending |
| `0x47A06070` | 140 | `-[NSDirectScreen bytesPerRow]` | static-reviewed; source authored; runtime pending |
| `0x47A060FC` | 58 | `-[NSDirectScreen bytesPerPlane]` | static-reviewed; source authored; runtime pending |
| `0x47A06138` | 12 | `-[NSDirectScreen numberOfPlanes]` | static-reviewed; source authored; runtime pending |
| `0x47A06144` | 42 | `-[NSDirectScreen _canLockWithMode:]` | static-reviewed; source authored; runtime pending |
| `0x47A06170` | 56 | `-[NSDirectScreen colorSpaceName]` | static-reviewed; source authored; runtime pending |
| `0x47A061A8` | 78 | `-[NSDirectScreen bitmapData]` | static-reviewed; source authored; runtime pending |
| `0x47A061F8` | 66 | `-[NSDirectScreen getBitmapDataPlanes:]` | static-reviewed; source authored; runtime pending |
| `0x47A0623C` | 9 | `-[NSDirectScreen isPlanar]` | static-reviewed; source authored; runtime pending |
| `0x47A06248` | 9 | `-[NSDirectScreen hasAlpha]` | static-reviewed; source authored; runtime pending |
| `0x47A06254` | 35 | `-[NSDirectScreen deviceSlot]` | static-reviewed; source authored; runtime pending |
| `0x47A06278` | 35 | `-[NSDirectScreen deviceUnit]` | static-reviewed; source authored; runtime pending |
| `0x47A0629C` | 17 | `-[NSDirectScreen displayIsShielded]` | static-reviewed; source authored; runtime pending |
| `0x47A062B0` | 35 | `-[NSDirectScreen driver]` | static-reviewed; source authored; runtime pending |
| `0x47A062D4` | 234 | `-[NSDirectScreen fadeDisplay:toColor:]` | static-reviewed; source authored; runtime pending |
| `0x47A063C0` | 314 | `-[NSDirectScreen _fadeIn:]` | static-reviewed; source authored; runtime pending |
| `0x47A064FC` | 707 | `-[NSDirectScreen fadeDisplayInFromColor:]` | static-reviewed; source authored; runtime pending |
| `0x47A067C0` | 314 | `-[NSDirectScreen _fadeOut:]` | static-reviewed; source authored; runtime pending |
| `0x47A068FC` | 711 | `-[NSDirectScreen fadeDisplayOutToColor:]` | static-reviewed; source authored; runtime pending |
| `0x47A06BC4` | 16 | `-[NSDirectScreen fadeDuration]` | static-reviewed; source authored; runtime pending |
| `0x47A06BD4` | 17 | `-[NSDirectScreen fadeInProgress]` | static-reviewed; source authored; runtime pending |
| `0x47A06BE8` | 17 | `-[NSDirectScreen fadeApplied]` | static-reviewed; source authored; runtime pending |
| `0x47A06BFC` | 109 | `-[NSDirectScreen _lockWithMode:]` | static-reviewed; source authored; runtime pending |
| `0x47A06C6C` | 56 | `-[NSDirectScreen pixelEncoding]` | static-reviewed; source authored; runtime pending |
| `0x47A06CA4` | 101 | `-[NSDirectScreen samplesPerPixel]` | static-reviewed; source authored; runtime pending |
| `0x47A06D0C` | 35 | `-[NSDirectScreen screenNumber]` | static-reviewed; source authored; runtime pending |
| `0x47A06D30` | 89 | `-[NSDirectScreen canSetPalette]` | static-reviewed; source authored; runtime pending |
| `0x47A06D8C` | 225 | `-[NSDirectScreen setPalette:]` | static-reviewed; source authored; runtime pending |
| `0x47A06E70` | 16 | `-[NSDirectScreen currentPalette]` | static-reviewed; source authored; runtime pending |
| `0x47A06E80` | 225 | `-[NSDirectScreen setPaletteAtNextBlankingInterval:]` | static-reviewed; source authored; runtime pending |
| `0x47A06F64` | 41 | `-[NSDirectScreen setFadeDuration:]` | static-reviewed; source authored; runtime pending |
| `0x47A06F90` | 576 | `-[NSDirectScreen shieldDisplay]` | static-reviewed; source authored; runtime pending |
| `0x47A071D0` | 16 | `-[NSDirectScreen shieldingWindow]` | static-reviewed; source authored; runtime pending |
| `0x47A071E0` | 575 | `-[NSDirectScreen switchToDisplayMode:]` | static-reviewed; source authored; runtime pending |
| `0x47A07420` | 105 | `-[NSDirectScreen _unlock]` | static-reviewed; source authored; runtime pending |
| `0x47A0748C` | 236 | `-[NSDirectScreen unshieldDisplay]` | static-reviewed; source authored; runtime pending |
| `0x47A07578` | 21 | `-[NSDirectScreen hideCursor]` | static-reviewed; source authored; runtime pending |
| `0x47A07590` | 21 | `-[NSDirectScreen showCursor]` | static-reviewed; source authored; runtime pending |
| `0x47A075A8` | 48 | `-[NSDirectScreen setGamma:]` | static-reviewed; source authored; runtime pending |
| `0x47A075D8` | 475 | `-[NSDirectScreen setGammaRed:green:blue:]` | static-reviewed; source authored; runtime pending |
| `0x47A077B4` | 1145 | `-[NSDirectScreen setGammaTableOfSize:red:green:blue:]` | static-reviewed; source authored; runtime pending |
| `0x47A07C30` | 264 | `-[NSDirectScreen _loadPalette:]` | static-reviewed; source authored; runtime pending |
| `0x47A07D38` | 266 | `-[NSDirectScreen _createBackingStore]` | static-reviewed; source authored; runtime pending |
| `0x47A07E44` | 52 | `-[NSDirectScreen _destroyBackingStore]` | static-reviewed; source authored; runtime pending |
| `0x47A07E78` | 261 | `_CopySrcToDst` | static-reviewed; runtime pending; `NSFramebuffer.m` |
| `0x47A07F80` | 29 | `-[NSDirectScreen(Obsolete) colorSpace]` | static-reviewed; source authored; runtime pending |
| `0x47A07FA0` | 29 | `-[NSDirectScreen(Obsolete) data]` | static-reviewed; source authored; runtime pending |
| `0x47A07FC0` | 125 | `_setInstanceForScreen` | static-reviewed; source authored; runtime pending; `NSFramebuffer.m` |
| `0x47A08040` | 53 | `_instanceForScreen` | static-reviewed; source authored; runtime pending; `NSFramebuffer.m` |
| `0x47A08078` | 35 | `-[NSFramebuffer initWithScreen:]` | static-reviewed; runtime pending; `NSFramebuffer.m` |
| `0x47A0809C` | 185 | `-[NSFramebuffer initWithScreen:andMapIfPossible:]` | static-reviewed; runtime pending; `NSFramebuffer.m` |
| `0x47A08158` | 784 | `-[NSFramebuffer initFromScreen:andMapIfPossible:]` | static-reviewed; source authored; runtime pending; `NSFramebuffer.m` |
| `0x47A08468` | 66 | `-[NSFramebuffer unmapScreen]` | static-reviewed; source authored; runtime pending; `NSFramebuffer.m` |
| `0x47A084AC` | 656 | `-[NSFramebuffer remapScreen]` | static-reviewed; source authored; runtime pending; `NSFramebuffer.m` |
| `0x47A0873C` | 17 | `-[NSFramebuffer isMappable]` | static-reviewed; runtime pending; `NSFramebuffer.m` |
| `0x47A08750` | 119 | `-[NSFramebuffer screenBounds]` | static-reviewed; runtime pending; architecture difference recorded |
| `0x47A087C8` | 13 | `-[NSFramebuffer screenNumber]` | static-reviewed; runtime pending; `NSFramebuffer.m` |
| `0x47A087D8` | 164 | `-[NSFramebuffer conversionTable]` | static-reviewed; source authored; runtime pending; `NSFramebuffer.m` |
| `0x47A0887C` | 164 | `-[NSFramebuffer inverseConversionTable]` | static-reviewed; source authored; runtime pending; `NSFramebuffer.m` |
| `0x47A08920` | 116 | `-[NSFramebuffer addressForPoint:]` | static-reviewed; runtime pending; `NSFramebuffer.m` |
| `0x47A08994` | 87 | `-[NSFramebuffer pixelEncoding]` | static-reviewed; runtime pending; `NSFramebuffer.m` |
| `0x47A089EC` | 87 | `-[NSFramebuffer driver]` | static-reviewed; runtime pending; `NSFramebuffer.m` |
| `0x47A08A44` | 16 | `-[NSFramebuffer deviceUnit]` | static-reviewed; runtime pending; `NSFramebuffer.m` |
| `0x47A08A54` | 16 | `-[NSFramebuffer deviceSlot]` | static-reviewed; runtime pending; `NSFramebuffer.m` |
| `0x47A08A64` | 10 | `-[NSFramebuffer retain]` | static-reviewed; runtime pending; `NSFramebuffer.m` |
| `0x47A08A70` | 7 | `-[NSFramebuffer release]` | static-reviewed; runtime pending; `NSFramebuffer.m` |
| `0x47A08A78` | 12 | `-[NSFramebuffer retainCount]` | static-reviewed; runtime pending; `NSFramebuffer.m` |
| `0x47A08A84` | 7 | `-[NSFramebuffer dealloc]` | static-reviewed; runtime pending; `NSFramebuffer.m` |
| `0x47A08A8C` | 12 | `-[NSFramebuffer canLockWithMode:]` | static-reviewed; runtime pending; `NSFramebuffer.m` |
| `0x47A08A98` | 7 | `-[NSFramebuffer lockWithMode:]` | static-reviewed; runtime pending; `NSFramebuffer.m` |
| `0x47A08AA0` | 7 | `-[NSFramebuffer unlock]` | static-reviewed; runtime pending; `NSFramebuffer.m` |
| `0x47A08AA8` | 13 | `-[NSFramebuffer _interceptorClient]` | static-reviewed; runtime pending; `NSFramebuffer.m` |
| `0x47A08AB8` | 7 | `_NSRemapMegaPixelDisplayForCurrentThread` | static-reviewed; source authored; runtime pending |
| `0x47A08AC0` | 357 | `-[NSInterceptedRect initForRect:inWindow:onFramebuffer:forClient:]` | static-reviewed; source authored; runtime pending; `i386/rect-state.md` |
| `0x47A08C28` | 16 | `-[NSInterceptedRect setTarget:]` | static-reviewed; source authored; runtime pending; `i386/rect-state.md` |
| `0x47A08C38` | 13 | `-[NSInterceptedRect target]` | static-reviewed; source authored; runtime pending; `i386/rect-state.md` |
| `0x47A08C48` | 42 | `-[NSInterceptedRect lockRect]` | static-reviewed; source authored; runtime pending; `i386/rect-state.md` |
| `0x47A08C74` | 38 | `-[NSInterceptedRect unlockRect]` | static-reviewed; source authored; runtime pending; `i386/rect-state.md` |
| `0x47A08C9C` | 29 | `-[NSInterceptedRect isLocked]` | static-reviewed; source authored; runtime pending; `i386/rect-state.md` |
| `0x47A08CBC` | 39 | `-[NSInterceptedRect currentScreenRect]` | static-reviewed; source authored; runtime pending; `i386/rect-state.md` |
| `0x47A08CE4` | 13 | `-[NSInterceptedRect currentScreenRectShape]` | static-reviewed; source authored; runtime pending; `i386/rect-state.md` |
| `0x47A08CF4` | 66 | `-[NSInterceptedRect currentClipList:count:]` | static-reviewed; source authored; runtime pending |
| `0x47A08D38` | 66 | `-[NSInterceptedRect compositeBits:withOp:]` | static-reviewed; source authored; runtime pending |
| `0x47A08D7C` | 33 | `-[NSInterceptedRect removeFromWindowServer]` | static-reviewed; source authored; runtime pending; `i386/rect-state.md` |
| `0x47A08DA0` | 132 | `-[NSInterceptedRect dealloc]` | static-reviewed; source authored; runtime pending; `i386/rect-state.md` |
| `0x47A08E24` | 13 | `-[NSInterceptedRect uniqueID]` | static-reviewed; source authored; runtime pending |
| `0x47A08E34` | 13 | `-[NSInterceptedRect windowNumber]` | static-reviewed; source authored; runtime pending; `i386/rect-state.md` |
| `0x47A08E44` | 39 | `-[NSInterceptedRect rectangle]` | static-reviewed; source authored; runtime pending; `i386/rect-state.md` |
| `0x47A08E6C` | 14 | `-[NSInterceptedRect isTotallyVisible]` | static-reviewed; source authored; runtime pending; `i386/rect-state.md` |
| `0x47A08E7C` | 14 | `-[NSInterceptedRect isTotallyObscured]` | static-reviewed; source authored; runtime pending; `i386/rect-state.md` |
| `0x47A08E8C` | 13 | `-[NSInterceptedRect _flags]` | static-reviewed; source authored; runtime pending; `i386/rect-state.md` |
| `0x47A08E9C` | 13 | `-[NSInterceptedRect framebuffer]` | static-reviewed; source authored; runtime pending; `i386/rect-state.md` |
| `0x47A08EAC` | 1433 | `-[NSInterceptedRect _handleMsg:withReply:]` | static-reviewed; source authored; runtime pending; `i386/rect-state.md` |
| `0x47A09448` | 165 | `+[NSInterceptorClient initialize]` | static-reviewed; source authored; runtime pending; `i386/client-state.md` |
| `0x47A094F0` | 273 | `-[NSInterceptorClient init]` | static-reviewed; source authored; runtime pending; `i386/client-state.md` |
| `0x47A09604` | 418 | `-[NSInterceptorClient dealloc]` | static-reviewed; source authored; runtime pending; `i386/client-state.md` |
| `0x47A097A8` | 86 | `-[NSInterceptorClient setHandlingThread:]` | static-reviewed; source authored; runtime pending; `i386/client-state.md` |
| `0x47A09800` | 38 | `-[NSInterceptorClient handlingThread]` | static-reviewed; source authored; runtime pending; `i386/client-state.md` |
| `0x47A09828` | 291 | `-[NSInterceptorClient interceptorPort]` | static-reviewed; source authored; runtime pending; `i386/client-state.md` |
| `0x47A0994C` | 251 | `-[NSInterceptorClient handleInterceptorMessage:withReply:]` | static-reviewed; source authored; runtime pending; `i386/client-state.md` |
| `0x47A09A48` | 449 | `-[NSInterceptorClient _addInterceptedRect:returnedScreenRect:returnedFlags:]` | static-reviewed; source authored; runtime pending; `i386/client-state.md` |
| `0x47A09C0C` | 135 | `-[NSInterceptorClient _removeInterceptedRect:]` | static-reviewed; source authored; runtime pending; `i386/client-state.md` |
| `0x47A09C94` | 13 | `-[NSInterceptorClient _context]` | static-reviewed; source authored; runtime pending; `i386/client-state.md` |
| `0x47A09CA4` | 65 | `-[NSInterceptorClient windowServerPortDeath:]` | static-reviewed; source authored; runtime pending; `i386/client-state.md` |
| `0x47A09CE8` | 642 | `-[NSInterceptorClient _notifyHandler]` | static-reviewed; source authored; runtime pending; `i386/client-state.md` |
| `0x47A09F6C` | 366 | `-[NSInterceptorClient startHandlingThread]` | static-reviewed; source authored; runtime pending; `i386/client-state.md` |
| `0x47A0A0DC` | 35 | `_empty_shape` | static-reviewed; runtime pending |
| `0x47A0A100` | 340 | `_rect_shape` | static-reviewed; runtime pending |
| `0x47A0A254` | 58 | `_is_equal_shape` | static-reviewed; runtime pending |
| `0x47A0A290` | 55 | `_is_empty_shape` | static-reviewed; runtime pending |
| `0x47A0A2C8` | 65 | `_offset_shape` | static-reviewed; runtime pending |
| `0x47A0A30C` | 659 | `_union_shape` | static-reviewed; runtime pending |
| `0x47A0A5A0` | 620 | `_intersect_shape` | static-reviewed; runtime pending |
| `0x47A0A80C` | 625 | `_difference_shape` | static-reviewed; runtime pending |
| `0x47A0AA80` | 87 | `-[NSShape init]` | static-reviewed; runtime pending |
| `0x47A0AAD8` | 93 | `-[NSShape initFromRect:]` | static-reviewed; runtime pending |
| `0x47A0AB38` | 51 | `-[NSShape intersectWithShape:]` | static-reviewed; runtime pending |
| `0x47A0AB6C` | 51 | `-[NSShape unionWithShape:]` | static-reviewed; runtime pending |
| `0x47A0ABA0` | 51 | `-[NSShape differenceWithShape:]` | static-reviewed; runtime pending |
| `0x47A0ABD4` | 22 | `-[NSShape isEmpty]` | static-reviewed; runtime pending |
| `0x47A0ABEC` | 48 | `-[NSShape isEqual:]` | static-reviewed; runtime pending |
| `0x47A0AC1C` | 128 | `-[NSShape copyWithZone:]` | static-reviewed; runtime pending |
| `0x47A0AC9C` | 78 | `-[NSShape offsetShape:]` | static-reviewed; runtime pending |
| `0x47A0ACEC` | 81 | `-[NSShape rectEnumerator]` | static-reviewed; runtime pending |
| `0x47A0AD40` | 65 | `-[NSShape dealloc]` | static-reviewed; source authored; runtime pending; `i386/shape.md` |
| `0x47A0AD84` | 304 | `-[NSShape description]` | static-reviewed; source authored; runtime pending |
| `0x47A0AEB4` | 66 | `-[_NSShapeEnumerator initForShapeImpl:]` | static-reviewed; runtime pending |
| `0x47A0AEF8` | 191 | `-[_NSShapeEnumerator nextRect]` | static-reviewed; runtime pending |
| `0x47A0AFB8` | 259 | `-[NSSimpleBitmap initWithBitmapDataPlanes:pixelsWide:pixelsHigh:bitsPerSample:samplesPerPixel:hasAlpha:isPlanar:colorSpaceName:bytesPerRow:bitsPerPixel:]` | static-reviewed; runtime pending |
| `0x47A0B0BC` | 13 | `-[NSSimpleBitmap bitmapData]` | static-reviewed; runtime pending |
| `0x47A0B0CC` | 87 | `-[NSSimpleBitmap getBitmapDataPlanes:]` | static-reviewed; runtime pending |
| `0x47A0B124` | 14 | `-[NSSimpleBitmap isPlanar]` | static-reviewed; runtime pending |
| `0x47A0B134` | 14 | `-[NSSimpleBitmap hasAlpha]` | static-reviewed; runtime pending |
| `0x47A0B144` | 13 | `-[NSSimpleBitmap samplesPerPixel]` | static-reviewed; runtime pending |
| `0x47A0B154` | 13 | `-[NSSimpleBitmap bitsPerPixel]` | static-reviewed; runtime pending |
| `0x47A0B164` | 13 | `-[NSSimpleBitmap bitsPerSample]` | static-reviewed; runtime pending |
| `0x47A0B174` | 13 | `-[NSSimpleBitmap bytesPerRow]` | static-reviewed; runtime pending |
| `0x47A0B184` | 19 | `-[NSSimpleBitmap bytesPerPlane]` | static-reviewed; runtime pending |
| `0x47A0B198` | 24 | `-[NSSimpleBitmap numberOfPlanes]` | static-reviewed; runtime pending |
| `0x47A0B1B0` | 13 | `-[NSSimpleBitmap colorSpaceName]` | static-reviewed; runtime pending |
| `0x47A0B1C0` | 13 | `-[NSSimpleBitmap pixelsWide]` | static-reviewed; runtime pending |
| `0x47A0B1D0` | 13 | `-[NSSimpleBitmap pixelsHigh]` | static-reviewed; runtime pending |
| `0x47A0B1E0` | 74 | `-[NSSimpleBitmap dealloc]` | static-reviewed; runtime pending |
| `0x47A0B22C` | 29 | `-[NSSimpleBitmap(Obsolete) colorSpace]` | static-reviewed; source authored; runtime pending |
| `0x47A0B24C` | 29 | `-[NSSimpleBitmap(Obsolete) data]` | static-reviewed; source authored; runtime pending |
| `0x47A0B26C` | 112 | `_rendezVous` | static-reviewed; source authored; runtime pending; `i386/ipc.md` |
| `0x47A0B2DC` | 19 | `__rendezvousPort` | static-reviewed; source authored; runtime pending; `i386/ipc.md` |
| `0x47A0B2F0` | 234 | `_getPSPort` | static-reviewed; source authored; runtime pending; `i386/ipc.md` |
| `0x47A0B3DC` | 117 | `_InterceptorCreateRemoteContext` | static-reviewed; runtime pending; `InterceptorContext.c` |
| `0x47A0B454` | 16 | `_InterceptorCreateContext` | static-reviewed; runtime pending; `InterceptorIPC.c` |
| `0x47A0B464` | 90 | `_InterceptorDestroyContext` | static-reviewed; runtime pending; `InterceptorIPC.c` |
| `0x47A0B4C0` | 60 | `_Interceptor_mig_error` | static-reviewed; source authored; runtime pending; `InterceptorIPC.c` |
| `0x47A0B4FC` | 45 | `_InterceptorMapFrameBuffer` | static-reviewed; source authored; runtime pending; `InterceptorIPC.c` |
| `0x47A0B52C` | 45 | `_InterceptorUnmapFrameBuffer` | static-reviewed; source authored; runtime pending; `InterceptorIPC.c` |
| `0x47A0B55C` | 26 | `_InterceptorGetBM34ToBM35Table` | static-reviewed; source authored; runtime pending; `InterceptorIPC.c` |
| `0x47A0B578` | 26 | `_InterceptorGetBM35ToBM34Table` | static-reviewed; source authored; runtime pending; `InterceptorIPC.c` |
| `0x47A0B594` | 26 | `_InterceptorGetBM256ToBM38Table` | static-reviewed; source authored; runtime pending; `InterceptorIPC.c` |
| `0x47A0B5B0` | 26 | `_InterceptorGetBM38ToBM256Table` | static-reviewed; source authored; runtime pending; `InterceptorIPC.c` |
| `0x47A0B5CC` | 22 | `_InterceptorScreenCount` | static-reviewed; source authored; runtime pending; `InterceptorIPC.c` |
| `0x47A0B5E4` | 70 | `_InterceptorCompositeBits` | static-reviewed; source authored; runtime pending; `InterceptorIPC.c` |
| `0x47A0B62C` | 66 | `_InterceptorFrameBufferInfo` | static-reviewed; source authored; runtime pending; `InterceptorIPC.c` |
| `0x47A0B670` | 22 | `_InterceptorHideCursor` | static-reviewed; source authored; runtime pending; `InterceptorIPC.c` |
| `0x47A0B688` | 20 | `_InterceptorShowCursor` | static-reviewed; source authored; runtime pending; `InterceptorIPC.c` |
| `0x47A0B69C` | 62 | `_InterceptorFlushRect` | static-reviewed; source authored; runtime pending; `InterceptorIPC.c` |
| `0x47A0B6DC` | 62 | `_InterceptorAddDirtyRect` | static-reviewed; source authored; runtime pending; `InterceptorIPC.c` |
| `0x47A0B71C` | 22 | `_InterceptorFlushDirtyRects` | static-reviewed; source authored; runtime pending; `InterceptorIPC.c` |
| `0x47A0B734` | 18 | `_InterceptorRepairPalette` | static-reviewed; source authored; runtime pending; `InterceptorIPC.c` |
| `0x47A0B748` | 18 | `_InterceptorDamagedPalette` | static-reviewed; source authored; runtime pending; `InterceptorIPC.c` |
| `0x47A0B75C` | 38 | `_InterceptorGetDeviceAccessTokens` | i386 static-reviewed; source authored; runtime pending; `InterceptorIPC.c` |
| `0x47A0B784` | 11 | `_ev_lock` | unexamined |
| `0x47A0B78F` | 15 | `_spin` | unexamined |
| `0x47A0B7A0` | 14 | `_ev_unlock` | unexamined |
| `0x47A0B7B0` | 21 | `_ev_try_lock` | unexamined |
| `0x47A0B7C8` | 246 | `__InterceptorEnableFrameBufferMapping` | static-reviewed; source authored; runtime pending; `InterceptorIPC.c`; `ppc/ipc.md` |
| `0x47A0B8C0` | 246 | `__InterceptorDisableFrameBufferMapping` | static-reviewed; source authored; runtime pending; `InterceptorIPC.c`; `ppc/ipc.md` |
| `0x47A0B9B8` | 255 | `__InterceptorMapFrameBuffer` | static-reviewed; source authored; runtime pending; `InterceptorIPC.c` |
| `0x47A0BAB8` | 298 | `__InterceptorGetBM34ToBM35Table` | static-reviewed; source authored; runtime pending; `InterceptorIPC.c` |
| `0x47A0BBE4` | 389 | `__InterceptorCompositeBits` | static-reviewed; source authored; runtime pending; `InterceptorIPC.c` |
| `0x47A0BD6C` | 662 | `__InterceptorFrameBufferInfo` | static-reviewed; source authored; runtime pending; `InterceptorIPC.c` |
| `0x47A0C004` | 213 | `__OldInterceptorSetNotifyPort` | static-reviewed; source authored; runtime pending; `InterceptorIPC.c`; `ppc/ipc.md` |
| `0x47A0C0DC` | 267 | `__InterceptorAddRect` | static-reviewed; `InterceptorIPC.c`; runtime pending |
| `0x47A0C1E8` | 213 | `__InterceptorRemoveRect` | static-reviewed; `InterceptorIPC.c`; runtime pending |
| `0x47A0C2C0` | 229 | `__InterceptorSetNotifyPort` | static-reviewed; `InterceptorIPC.c`; runtime pending |
| `0x47A0C3A8` | 298 | `__InterceptorGetBM35ToBM34Table` | static-reviewed; source authored; runtime pending; `InterceptorIPC.c` |
| `0x47A0C4D4` | 197 | `__InterceptorScreenCount` | static-reviewed; source authored; runtime pending; `InterceptorIPC.c` |
| `0x47A0C59C` | 197 | `__InterceptorHideCursor` | static-reviewed; source authored; runtime pending; `InterceptorIPC.c` |
| `0x47A0C664` | 197 | `__InterceptorShowCursor` | static-reviewed; source authored; runtime pending; `InterceptorIPC.c` |
| `0x47A0C72C` | 219 | `__InterceptorGetBM256ToBM38Table` | static-reviewed; source authored; runtime pending; `InterceptorIPC.c` |
| `0x47A0C808` | 219 | `__InterceptorGetBM38ToBM256Table` | static-reviewed; source authored; runtime pending; `InterceptorIPC.c` |
| `0x47A0C8E4` | 130 | `__InterceptorFlushRect` | static-reviewed; source authored; runtime pending; `InterceptorIPC.c` |
| `0x47A0C968` | 130 | `__InterceptorAddDirtyRect` | static-reviewed; source authored; runtime pending; `InterceptorIPC.c` |
| `0x47A0C9EC` | 95 | `__InterceptorFlushDirtyRects` | static-reviewed; source authored; runtime pending; `InterceptorIPC.c` |
| `0x47A0CA4C` | 74 | `__InterceptorRepairPalette` | static-reviewed; source authored; runtime pending; `InterceptorIPC.c` |
| `0x47A0CA98` | 74 | `__InterceptorDamagedPalette` | static-reviewed; source authored; runtime pending; `InterceptorIPC.c` |
| `0x47A0CAE4` | 275 | `__InterceptorGetDeviceAccessTokens` | static-reviewed; source authored; runtime pending; `InterceptorIPC.c` |
| `0x47A0CBF8` | 74 | `__InterceptorShowCursorAsync` | static-reviewed; source authored; runtime pending; `InterceptorIPC.c` |
| `0x47A0CC44` | 249 | `__InterceptorUnmapFrameBuffer` | static-reviewed; source authored; runtime pending; `InterceptorIPC.c` |
| `0x47A0CD40` | 362 | `__IOLookupByObjectNumber` | unexamined |
| `0x47A0CEAC` | 298 | `__IOLookupByDeviceName` | unexamined |
| `0x47A0CFD8` | 546 | `__IOGetIntValues` | unexamined |
| `0x47A0D1FC` | 543 | `__IOGetCharValues` | unexamined |
| `0x47A0D41C` | 413 | `__IOSetIntValues` | unexamined |
| `0x47A0D5BC` | 405 | `__IOSetCharValues` | unexamined |
| `0x47A0D754` | 851 | `__IOGetEISADeviceConfig` | unexamined |
| `0x47A0DAA8` | 186 | `__IOMapEISADevicePorts` | unexamined |
| `0x47A0DB64` | 186 | `__IOUnMapEISADevicePorts` | unexamined |
| `0x47A0DC20` | 311 | `__IOMapEISADeviceMemory` | unexamined |
| `0x47A0DD58` | 301 | `__IOProbeDriver` | unexamined |
| `0x47A0DE88` | 384 | `__IOGetSystemConfig` | unexamined |
| `0x47A0E008` | 301 | `__IOUnloadDriver` | unexamined |
| `0x47A0E138` | 384 | `__IOGetDriverConfig` | unexamined |
| `0x47A0E2B8` | 202 | `__PMSetPowerState` | unexamined |
| `0x47A0E384` | 207 | `__PMGetPowerEvent` | unexamined |
| `0x47A0E454` | 227 | `__PMGetPowerStatus` | unexamined |
| `0x47A0E538` | 202 | `__PMSetPowerManagement` | unexamined |
| `0x47A0E604` | 166 | `__PMRestoreDefaults` | unexamined |
| `0x47A0E6AC` | 691 | `__IOCallDeviceMethod` | unexamined |
| `0x47A0E960` | 223 | `__IOCreateMachPort` | unexamined |
| `0x47A0F338` | 14 | `_NSEqualSizes` | linker-generated PIC import stub; no framework source body |
| `0x47A0F352` | 14 | `_NSEqualRects` | linker-generated PIC import stub; no framework source body |
| `0x47A0F36C` | 14 | `j__InterceptorScreenCount` | linker-generated PIC import stub; no framework source body |
| `0x47A0F386` | 14 | `j__InterceptorShowCursor` | linker-generated PIC import stub; no framework source body |
| `0x47A0F3A0` | 14 | `j__InterceptorHideCursor` | linker-generated PIC import stub; no framework source body |
| `0x47A0F3BA` | 14 | `_NSIsEmptyRect` | linker-generated PIC import stub; no framework source body |
| `0x47A0F3D4` | 14 | `_memset` | linker-generated PIC import stub; no framework source body |
| `0x47A0F3EE` | 14 | `_NSConvertWindowNumberToGlobal` | linker-generated PIC import stub; no framework source body |
| `0x47A0F408` | 14 | `_sel_getName` | linker-generated PIC import stub; no framework source body |
| `0x47A0F422` | 14 | `_objc_msgSendSuper` | linker-generated PIC import stub; no framework source body |
| `0x47A0F43C` | 14 | `_NSZoneFree` | linker-generated PIC import stub; no framework source body |
| `0x47A0F456` | 14 | `_printf` | linker-generated PIC import stub; no framework source body |
| `0x47A0F470` | 14 | `j__InterceptorCompositeBits` | linker-generated PIC import stub; no framework source body |
| `0x47A0F48A` | 14 | `_NSIntersectionRect` | linker-generated PIC import stub; no framework source body |
| `0x47A0F4A4` | 14 | `_NSOffsetRect` | linker-generated PIC import stub; no framework source body |
| `0x47A0F4BE` | 14 | `_bzero` | linker-generated PIC import stub; no framework source body |
| `0x47A0F4D8` | 14 | `_NSZoneMalloc` | linker-generated PIC import stub; no framework source body |
| `0x47A0F4F2` | 14 | `_objc_msgSend` | linker-generated PIC import stub; no framework source body |
| `0x47A0F50C` | 14 | `_NSLog` | linker-generated PIC import stub; no framework source body |
| `0x47A0F526` | 14 | `_pow` | linker-generated PIC import stub; no framework source body |
| `0x47A0F540` | 14 | `_malloc` | linker-generated PIC import stub; no framework source body |
| `0x47A0F55A` | 14 | `_free` | linker-generated PIC import stub; no framework source body |
| `0x47A0F574` | 14 | `j___IOSetCharValues` | linker-generated PIC import stub; no framework source body |
| `0x47A0F58E` | 14 | `j___IOSetIntValues` | linker-generated PIC import stub; no framework source body |
| `0x47A0F5A8` | 14 | `_NXCloseEventStatus` | linker-generated PIC import stub; no framework source body |
| `0x47A0F5C2` | 14 | `_NXSetAutoDimBrightness` | linker-generated PIC import stub; no framework source body |
| `0x47A0F5DC` | 14 | `_NXScreenBrightness` | linker-generated PIC import stub; no framework source body |
| `0x47A0F5F6` | 14 | `_NXAutoDimBrightness` | linker-generated PIC import stub; no framework source body |
| `0x47A0F610` | 14 | `_NXOpenEventStatus` | linker-generated PIC import stub; no framework source body |
| `0x47A0F62A` | 14 | `_PSWait` | linker-generated PIC import stub; no framework source body |
| `0x47A0F644` | 14 | `_PSgrestore` | linker-generated PIC import stub; no framework source body |
| `0x47A0F65E` | 14 | `_PSsetexposurecolor` | linker-generated PIC import stub; no framework source body |
| `0x47A0F678` | 14 | `_PSsetrgbcolor` | linker-generated PIC import stub; no framework source body |
| `0x47A0F692` | 14 | `_PSwindowdeviceround` | linker-generated PIC import stub; no framework source body |
| `0x47A0F6AC` | 14 | `_PSgsave` | linker-generated PIC import stub; no framework source body |
| `0x47A0F6C6` | 14 | `_PSsetautofill` | linker-generated PIC import stub; no framework source body |
| `0x47A0F6E0` | 14 | `j__InterceptorDamagedPalette` | linker-generated PIC import stub; no framework source body |
| `0x47A0F6FA` | 14 | `_sprintf` | linker-generated PIC import stub; no framework source body |
| `0x47A0F714` | 14 | `_NSStringFromSelector` | linker-generated PIC import stub; no framework source body |
| `0x47A0F72E` | 14 | `j__InterceptorDestroyContext` | linker-generated PIC import stub; no framework source body |
| `0x47A0F748` | 14 | `j___IOGetIntValues` | linker-generated PIC import stub; no framework source body |
| `0x47A0F762` | 14 | `j__InterceptorGetDeviceAccessTokens` | linker-generated PIC import stub; no framework source body |
| `0x47A0F77C` | 14 | `j__InterceptorCreateContext` | linker-generated PIC import stub; no framework source body |
| `0x47A0F796` | 14 | `j__InterceptorGetBM256ToBM38Table` | linker-generated PIC import stub; no framework source body |
| `0x47A0F7B0` | 14 | `j__InterceptorGetBM35ToBM34Table` | linker-generated PIC import stub; no framework source body |
| `0x47A0F7CA` | 14 | `j__InterceptorGetBM38ToBM256Table` | linker-generated PIC import stub; no framework source body |
| `0x47A0F7E4` | 14 | `j__InterceptorGetBM34ToBM35Table` | linker-generated PIC import stub; no framework source body |
| `0x47A0F7FE` | 14 | `j__InterceptorUnmapFrameBuffer` | linker-generated PIC import stub; no framework source body |
| `0x47A0F818` | 14 | `j__InterceptorMapFrameBuffer` | linker-generated PIC import stub; no framework source body |
| `0x47A0F832` | 14 | `j__InterceptorFrameBufferInfo` | linker-generated PIC import stub; no framework source body |
| `0x47A0F84C` | 14 | `_objc_setMultithreaded` | linker-generated PIC import stub; no framework source body |
| `0x47A0F866` | 14 | `_port_set_add` | linker-generated PIC import stub; no framework source body |
| `0x47A0F880` | 14 | `_msg_send` | linker-generated PIC import stub; no framework source body |
| `0x47A0F89A` | 14 | `_mach_error_string` | linker-generated PIC import stub; no framework source body |
| `0x47A0F8B4` | 14 | `_msg_receive` | linker-generated PIC import stub; no framework source body |
| `0x47A0F8CE` | 14 | `j___rendezvousPort` | linker-generated PIC import stub; no framework source body |
| `0x47A0F8E8` | 14 | `_cthread_set_name` | linker-generated PIC import stub; no framework source body |
| `0x47A0F902` | 14 | `_ur_cthread_self` | linker-generated PIC import stub; no framework source body |
| `0x47A0F91C` | 14 | `j__NSRemapMegaPixelDisplayForCurrentThread` | linker-generated PIC import stub; no framework source body |
| `0x47A0F936` | 14 | `j___InterceptorRemoveRect` | linker-generated PIC import stub; no framework source body |
| `0x47A0F950` | 14 | `j___InterceptorAddRect` | linker-generated PIC import stub; no framework source body |
| `0x47A0F96A` | 14 | `j___InterceptorSetNotifyPort` | linker-generated PIC import stub; no framework source body |
| `0x47A0F984` | 14 | `_task_get_special_port` | linker-generated PIC import stub; no framework source body |
| `0x47A0F99E` | 14 | `_thread_get_special_port` | linker-generated PIC import stub; no framework source body |
| `0x47A0F9B8` | 14 | `_thread_self` | linker-generated PIC import stub; no framework source body |
| `0x47A0F9D2` | 14 | `_port_allocate` | linker-generated PIC import stub; no framework source body |
| `0x47A0F9EC` | 14 | `_port_deallocate` | linker-generated PIC import stub; no framework source body |
| `0x47A0FA06` | 14 | `_port_set_remove` | linker-generated PIC import stub; no framework source body |
| `0x47A0FA20` | 14 | `_mach_error` | linker-generated PIC import stub; no framework source body |
| `0x47A0FA3A` | 14 | `_port_set_allocate` | linker-generated PIC import stub; no framework source body |
| `0x47A0FA54` | 14 | `_memcpy` | linker-generated PIC import stub; no framework source body |
| `0x47A0FA6E` | 14 | `_NSZoneRealloc` | linker-generated PIC import stub; no framework source body |
| `0x47A0FA88` | 14 | `_netname_look_up` | linker-generated PIC import stub; no framework source body |
| `0x47A0FAA2` | 14 | `_bootstrap_look_up` | linker-generated PIC import stub; no framework source body |
| `0x47A0FABC` | 14 | `_msg_rpc` | linker-generated PIC import stub; no framework source body |
| `0x47A0FAD6` | 14 | `j___InterceptorGetDeviceAccessTokens` | linker-generated PIC import stub; no framework source body |
| `0x47A0FAF0` | 14 | `j___InterceptorDamagedPalette` | linker-generated PIC import stub; no framework source body |
| `0x47A0FB0A` | 14 | `j___InterceptorRepairPalette` | linker-generated PIC import stub; no framework source body |
| `0x47A0FB24` | 14 | `j___InterceptorFlushDirtyRects` | linker-generated PIC import stub; no framework source body |
| `0x47A0FB3E` | 14 | `j___InterceptorAddDirtyRect` | linker-generated PIC import stub; no framework source body |
| `0x47A0FB58` | 14 | `j___InterceptorFlushRect` | linker-generated PIC import stub; no framework source body |
| `0x47A0FB72` | 14 | `j___InterceptorShowCursorAsync` | linker-generated PIC import stub; no framework source body |
| `0x47A0FB8C` | 14 | `j___InterceptorHideCursor` | linker-generated PIC import stub; no framework source body |
| `0x47A0FBA6` | 14 | `j___InterceptorFrameBufferInfo` | linker-generated PIC import stub; no framework source body |
| `0x47A0FBC0` | 14 | `j___InterceptorCompositeBits` | linker-generated PIC import stub; no framework source body |
| `0x47A0FBDA` | 14 | `j___InterceptorScreenCount` | linker-generated PIC import stub; no framework source body |
| `0x47A0FBF4` | 14 | `j___InterceptorGetBM38ToBM256Table` | linker-generated PIC import stub; no framework source body |
| `0x47A0FC0E` | 14 | `j___InterceptorGetBM256ToBM38Table` | linker-generated PIC import stub; no framework source body |
| `0x47A0FC28` | 14 | `j___InterceptorGetBM35ToBM34Table` | linker-generated PIC import stub; no framework source body |
| `0x47A0FC42` | 14 | `j___InterceptorGetBM34ToBM35Table` | linker-generated PIC import stub; no framework source body |
| `0x47A0FC5C` | 14 | `j___InterceptorUnmapFrameBuffer` | linker-generated PIC import stub; no framework source body |
| `0x47A0FC76` | 14 | `j___InterceptorMapFrameBuffer` | linker-generated PIC import stub; no framework source body |
| `0x47A0FC90` | 14 | `j__Interceptor_mig_error` | linker-generated PIC import stub; no framework source body |
| `0x47A0FCAA` | 14 | `_strncpy` | linker-generated PIC import stub; no framework source body |
| `0x47A0FCC4` | 14 | `_bcopy` | linker-generated PIC import stub; no framework source body |
| `0x47A0FCDE` | 14 | `_mig_dealloc_reply_port` | linker-generated PIC import stub; no framework source body |
| `0x47A0FCF8` | 14 | `_mig_get_reply_port` | linker-generated PIC import stub; no framework source body |

Named Objective-C symbols (candidate module by class name; verify in module metadata):

| Address | Symbol | Candidate source module | Review status |
|---:|---|---|---|
| `0x47A011E0` | `+[NSDirectBitmap minDepthForGray:andColor:]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A01204` | `-[NSDirectBitmap bitsPerPixel]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A01214` | `-[NSDirectBitmap bitsPerSample]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A01224` | `-[NSDirectBitmap bytesPerPlane]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A0126C` | `-[NSDirectBitmap bytesPerRow]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A012AC` | `-[NSDirectBitmap colorSpaceName]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A012BC` | `-[NSDirectBitmap conversionTable]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A012DC` | `-[NSDirectBitmap inverseConversionTable]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A012FC` | `-[NSDirectBitmap _dataBuffer]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A01350` | `-[NSDirectBitmap bitmapData]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A013C8` | `-[NSDirectBitmap _flushInShape:]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A015F8` | `-[NSDirectBitmap flush]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A01648` | `-[NSDirectBitmap flushIn:]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A019B4` | `-[NSDirectBitmap dealloc]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A01A7C` | `-[NSDirectBitmap getBitmapDataPlanes:]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A01B54` | `-[NSDirectBitmap pixelEncodings]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A01BC4` | `-[NSDirectBitmap hasAlpha]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A01BD4` | `-[NSDirectBitmap init]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A01C30` | `-[NSDirectBitmap initForRect:inWindow:]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A01D78` | `-[NSDirectBitmap isPlanar]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A01D88` | `-[NSDirectBitmap _mapFramebufferForScreen:]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A01E60` | `-[NSDirectBitmap _initForRect:inWinNum:onScreen:]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A021BC` | `-[NSDirectBitmap isBuffered]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A021CC` | `-[NSDirectBitmap isDirectMapped]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A021DC` | `-[NSDirectBitmap lockBitmap]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A022B4` | `-[NSDirectBitmap numberOfPlanes]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A022CC` | `-[NSDirectBitmap pixelEncoding]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A023A4` | `-[NSDirectBitmap pixelsWide]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A023B4` | `-[NSDirectBitmap pixelsHigh]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A023C4` | `-[NSDirectBitmap _updateBuffer]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A024BC` | `-[NSDirectBitmap samplesPerPixel]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A024CC` | `-[NSDirectBitmap setBuffered:]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A025BC` | `-[NSDirectBitmap _canUseDirectMapping]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A02664` | `-[NSDirectBitmap setDirectMapped:]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A02734` | `-[NSDirectBitmap tryLockBitmap]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A02768` | `-[NSDirectBitmap unlockBitmap]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A02798` | `-[NSDirectBitmap _updateBackingStoreForRect:]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A028C8` | `-[NSDirectBitmap _updateForRect:inWinNum:onScreen:]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A02C7C` | `-[NSDirectBitmap updateForRect:inWindow:]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A02D6C` | `-[NSDirectBitmap updateState]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A02E24` | `-[NSDirectBitmap hideCursor]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A02E50` | `-[NSDirectBitmap showCursor]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A02E7C` | `-[NSDirectBitmap currentPalette]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A02EA0` | `-[NSDirectBitmap _setDelegate:]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A02EE4` | `-[NSDirectBitmap _framebuffer]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A02EF4` | `-[NSDirectBitmap _setFlushOnExposure:]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A02F08` | `-[NSDirectBitmap _screenBoundsOrigin]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A02F5C` | `-[NSDirectBitmap _isUnobscured]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A02FD4` | `-[NSDirectBitmap _isTotallyObscured]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A03024` | `-[NSDirectBitmap _setViewClip:]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A030A0` | `-[NSDirectBitmap _viewClipShape:]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A030B0` | `-[NSDirectBitmap _setViewClipShape:]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A0311C` | `-[NSDirectBitmap areaWillMove:by:]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A03198` | `-[NSDirectBitmap areaDidMove:by:]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A03274` | `-[NSDirectBitmap areaWillObscure:inRect:]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A033A8` | `-[NSDirectBitmap areaDidReveal:inRect:]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A0355C` | `-[NSDirectBitmap areaWasOrderedIn:]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A0358C` | `-[NSDirectBitmap areaWasOrderedOut:]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A035BC` | `-[NSDirectBitmap areaIsInvalid:]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A035E0` | `-[NSDirectBitmap areaChangedScreen:from:to:]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A03614` | `-[NSDirectBitmap areaWindowFreed:]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A03638` | `-[NSDirectBitmap areaDidChangeBuffering:toType:]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A03648` | `-[NSDirectBitmap(Obsolete) colorSpace]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A03668` | `-[NSDirectBitmap(Obsolete) data]` | `NSDirectBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A03688` | `+[NSDirectPalette defaultPalette]` | `NSDirectPalette.m` | static-reviewed; source authored; runtime pending |
| `0x47A036CC` | `+[NSDirectPalette currentPalette]` | `NSDirectPalette.m` | static-reviewed; source authored; runtime pending |
| `0x47A037B4` | `-[NSDirectPalette initWithArrayOfColors:]` | `NSDirectPalette.m` | static-reviewed; source authored; runtime pending |
| `0x47A03868` | `-[NSDirectPalette init]` | `NSDirectPalette.m` | static-reviewed; source authored; runtime pending |
| `0x47A039F0` | `-[NSDirectPalette colorAtIndex:]` | `NSDirectPalette.m` | static-reviewed; source authored; runtime pending |
| `0x47A03A18` | `-[NSDirectPalette indexForColor:]` | `NSDirectPalette.m` | static-reviewed; source authored; runtime pending |
| `0x47A03C54` | `-[NSDirectPalette count]` | `NSDirectPalette.m` | static-reviewed; source authored; runtime pending |
| `0x47A03C78` | `-[NSDirectPalette dealloc]` | `NSDirectPalette.m` | static-reviewed; source authored; runtime pending |
| `0x47A03CF0` | `-[NSDirectPalette objectEnumerator]` | `NSDirectPalette.m` | static-reviewed; source authored; runtime pending |
| `0x47A03D14` | `-[NSDirectPalette rawMachinePalette]` | `NSDirectPalette.m` | static-reviewed; source authored; runtime pending |
| `0x47A03F44` | `-[NSDirectPalette setColor:atIndex:]` | `NSDirectPalette.m` | static-reviewed; source authored; runtime pending |
| `0x47A03FF0` | `-[NSDirectPalette setRed:green:blue:atIndex:]` | `NSDirectPalette.m` | static-reviewed; source authored; runtime pending |
| `0x47A04044` | `-[NSDirectPalette getRed:green:blue:atIndex:]` | `NSDirectPalette.m` | static-reviewed; source authored; runtime pending |
| `0x47A0408C` | `-[NSDirectPalette setColors:atIndices:]` | `NSDirectPalette.m` | static-reviewed; source authored; runtime pending |
| `0x47A04168` | `-[NSDirectPalette copy]` | `NSDirectPalette.m` | static-reviewed; source authored; runtime pending |
| `0x47A0419C` | `-[NSDirectPalette mutableCopy]` | `NSDirectPalette.m` | static-reviewed; source authored; runtime pending |
| `0x47A041D0` | `-[NSDirectPalette copyWithZone:]` | `NSDirectPalette.m` | static-reviewed; source authored; runtime pending |
| `0x47A041F4` | `-[NSDirectPalette mutableCopyWithZone:]` | `NSDirectPalette.m` | static-reviewed; source authored; runtime pending |
| `0x47A04244` | `-[NSDirectPalette encodeWithCoder:]` | `NSDirectPalette.m` | static-reviewed; source authored; runtime pending |
| `0x47A0426C` | `-[NSDirectPalette initWithCoder:]` | `NSDirectPalette.m` | static-reviewed; source authored; runtime pending |
| `0x47A042F4` | `-[NSDirectPalette isEqual:]` | `NSDirectPalette.m` | static-reviewed; source authored; runtime pending |
| `0x47A043BC` | `-[NSDirectPalette blendedPaletteWithFraction:ofColor:]` | `NSDirectPalette.m` | static-reviewed; source authored; runtime pending |
| `0x47A04644` | `-[NSDirectScreen _clearModeInfo]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A046AC` | `-[NSDirectScreen initWithScreen:]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A04878` | `-[NSDirectScreen dealloc]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A049E8` | `-[NSDirectScreen screenSize]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A04AA8` | `-[NSDirectScreen pixelsWide]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A04AE8` | `-[NSDirectScreen pixelsHigh]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A04B28` | `-[NSDirectScreen addressForPoint:]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A04C2C` | `-[NSDirectScreen availableDisplayModes]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A0575C` | `-[NSDirectScreen availableDisplayModesForOptions:]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A0591C` | `-[NSDirectScreen bestModeForFormat:width:height:]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A05E28` | `-[NSDirectScreen bestModeForOptions:]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A05E9C` | `-[NSDirectScreen currentMode]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A05FA0` | `-[NSDirectScreen bitsPerPixel]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A06008` | `-[NSDirectScreen bitsPerSample]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A06070` | `-[NSDirectScreen bytesPerRow]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A060FC` | `-[NSDirectScreen bytesPerPlane]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A06138` | `-[NSDirectScreen numberOfPlanes]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A06144` | `-[NSDirectScreen _canLockWithMode:]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A06170` | `-[NSDirectScreen colorSpaceName]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A061A8` | `-[NSDirectScreen bitmapData]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A061F8` | `-[NSDirectScreen getBitmapDataPlanes:]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A0623C` | `-[NSDirectScreen isPlanar]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A06248` | `-[NSDirectScreen hasAlpha]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A06254` | `-[NSDirectScreen deviceSlot]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A06278` | `-[NSDirectScreen deviceUnit]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A0629C` | `-[NSDirectScreen displayIsShielded]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A062B0` | `-[NSDirectScreen driver]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A062D4` | `-[NSDirectScreen fadeDisplay:toColor:]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A063C0` | `-[NSDirectScreen _fadeIn:]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A064FC` | `-[NSDirectScreen fadeDisplayInFromColor:]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A067C0` | `-[NSDirectScreen _fadeOut:]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A068FC` | `-[NSDirectScreen fadeDisplayOutToColor:]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A06BC4` | `-[NSDirectScreen fadeDuration]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A06BD4` | `-[NSDirectScreen fadeInProgress]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A06BE8` | `-[NSDirectScreen fadeApplied]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A06BFC` | `-[NSDirectScreen _lockWithMode:]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A06C6C` | `-[NSDirectScreen pixelEncoding]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A06CA4` | `-[NSDirectScreen samplesPerPixel]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A06D0C` | `-[NSDirectScreen screenNumber]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A06D30` | `-[NSDirectScreen canSetPalette]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A06D8C` | `-[NSDirectScreen setPalette:]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A06E70` | `-[NSDirectScreen currentPalette]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A06E80` | `-[NSDirectScreen setPaletteAtNextBlankingInterval:]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A06F64` | `-[NSDirectScreen setFadeDuration:]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A06F90` | `-[NSDirectScreen shieldDisplay]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A071D0` | `-[NSDirectScreen shieldingWindow]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A071E0` | `-[NSDirectScreen switchToDisplayMode:]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A07420` | `-[NSDirectScreen _unlock]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A0748C` | `-[NSDirectScreen unshieldDisplay]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A07578` | `-[NSDirectScreen hideCursor]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A07590` | `-[NSDirectScreen showCursor]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A075A8` | `-[NSDirectScreen(NSPrivate) setGamma:]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A075D8` | `-[NSDirectScreen(NSPrivate) setGammaRed:green:blue:]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A077B4` | `-[NSDirectScreen(NSPrivate) setGammaTableOfSize:red:green:blue:]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A07C30` | `-[NSDirectScreen(NSPrivate) _loadPalette:]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A07D38` | `-[NSDirectScreen(NSPrivate) _createBackingStore]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A07E44` | `-[NSDirectScreen(NSPrivate) _destroyBackingStore]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A07F80` | `-[NSDirectScreen(Obsolete) colorSpace]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A07FA0` | `-[NSDirectScreen(Obsolete) data]` | `NSDirectScreen.m` | static-reviewed; source authored; runtime pending |
| `0x47A08078` | `-[NSFramebuffer initWithScreen:]` | `NSFramebuffer.m` | static-reviewed; runtime pending |
| `0x47A0809C` | `-[NSFramebuffer initWithScreen:andMapIfPossible:]` | `NSFramebuffer.m` | static-reviewed; runtime pending |
| `0x47A08158` | `-[NSFramebuffer initFromScreen:andMapIfPossible:]` | `NSFramebuffer.m` | static-reviewed; source authored; runtime pending |
| `0x47A08468` | `-[NSFramebuffer unmapScreen]` | `NSFramebuffer.m` | static-reviewed; source authored; runtime pending |
| `0x47A084AC` | `-[NSFramebuffer remapScreen]` | `NSFramebuffer.m` | static-reviewed; source authored; runtime pending |
| `0x47A0873C` | `-[NSFramebuffer isMappable]` | `NSFramebuffer.m` | static-reviewed; runtime pending |
| `0x47A08750` | `-[NSFramebuffer screenBounds]` | `NSFramebuffer.m` | static-reviewed; runtime pending; architecture difference recorded |
| `0x47A087C8` | `-[NSFramebuffer screenNumber]` | `NSFramebuffer.m` | static-reviewed; runtime pending |
| `0x47A087D8` | `-[NSFramebuffer conversionTable]` | `NSFramebuffer.m` | static-reviewed; source authored; runtime pending |
| `0x47A0887C` | `-[NSFramebuffer inverseConversionTable]` | `NSFramebuffer.m` | static-reviewed; source authored; runtime pending |
| `0x47A08920` | `-[NSFramebuffer addressForPoint:]` | `NSFramebuffer.m` | static-reviewed; runtime pending |
| `0x47A08994` | `-[NSFramebuffer pixelEncoding]` | `NSFramebuffer.m` | static-reviewed; runtime pending |
| `0x47A089EC` | `-[NSFramebuffer driver]` | `NSFramebuffer.m` | static-reviewed; runtime pending |
| `0x47A08A44` | `-[NSFramebuffer deviceUnit]` | `NSFramebuffer.m` | static-reviewed; runtime pending |
| `0x47A08A54` | `-[NSFramebuffer deviceSlot]` | `NSFramebuffer.m` | static-reviewed; runtime pending |
| `0x47A08A64` | `-[NSFramebuffer retain]` | `NSFramebuffer.m` | static-reviewed; runtime pending |
| `0x47A08A70` | `-[NSFramebuffer release]` | `NSFramebuffer.m` | static-reviewed; runtime pending |
| `0x47A08A78` | `-[NSFramebuffer retainCount]` | `NSFramebuffer.m` | static-reviewed; runtime pending |
| `0x47A08A84` | `-[NSFramebuffer dealloc]` | `NSFramebuffer.m` | static-reviewed; runtime pending |
| `0x47A08A8C` | `-[NSFramebuffer canLockWithMode:]` | `NSFramebuffer.m` | static-reviewed; runtime pending |
| `0x47A08A98` | `-[NSFramebuffer lockWithMode:]` | `NSFramebuffer.m` | static-reviewed; runtime pending |
| `0x47A08AA0` | `-[NSFramebuffer unlock]` | `NSFramebuffer.m` | static-reviewed; runtime pending |
| `0x47A08AA8` | `-[NSFramebuffer(NSPrivate) _interceptorClient]` | `NSFramebuffer.m` | static-reviewed; runtime pending |
| `0x47A08AC0` | `-[NSInterceptedRect initForRect:inWindow:onFramebuffer:forClient:]` | `NSInterceptedRect.m` | static-reviewed; source authored; runtime pending; `i386/rect-state.md` |
| `0x47A08C28` | `-[NSInterceptedRect setTarget:]` | `NSInterceptedRect.m` | static-reviewed; source authored; runtime pending; `i386/rect-state.md` |
| `0x47A08C38` | `-[NSInterceptedRect target]` | `NSInterceptedRect.m` | static-reviewed; source authored; runtime pending; `i386/rect-state.md` |
| `0x47A08C48` | `-[NSInterceptedRect lockRect]` | `NSInterceptedRect.m` | static-reviewed; source authored; runtime pending; `i386/rect-state.md` |
| `0x47A08C74` | `-[NSInterceptedRect unlockRect]` | `NSInterceptedRect.m` | static-reviewed; source authored; runtime pending; `i386/rect-state.md` |
| `0x47A08C9C` | `-[NSInterceptedRect isLocked]` | `NSInterceptedRect.m` | static-reviewed; source authored; runtime pending; `i386/rect-state.md` |
| `0x47A08CBC` | `-[NSInterceptedRect currentScreenRect]` | `NSInterceptedRect.m` | static-reviewed; source authored; runtime pending; `i386/rect-state.md` |
| `0x47A08CE4` | `-[NSInterceptedRect currentScreenRectShape]` | `NSInterceptedRect.m` | static-reviewed; source authored; runtime pending; `i386/rect-state.md` |
| `0x47A08CF4` | `-[NSInterceptedRect currentClipList:count:]` | `NSInterceptedRect.m` | static-reviewed; source authored; runtime pending |
| `0x47A08D38` | `-[NSInterceptedRect compositeBits:withOp:]` | `NSInterceptedRect.m` | static-reviewed; source authored; runtime pending |
| `0x47A08D7C` | `-[NSInterceptedRect removeFromWindowServer]` | `NSInterceptedRect.m` | static-reviewed; source authored; runtime pending; `i386/rect-state.md` |
| `0x47A08DA0` | `-[NSInterceptedRect dealloc]` | `NSInterceptedRect.m` | static-reviewed; source authored; runtime pending; `i386/rect-state.md` |
| `0x47A08E24` | `-[NSInterceptedRect uniqueID]` | `NSInterceptedRect.m` | static-reviewed; source authored; runtime pending |
| `0x47A08E34` | `-[NSInterceptedRect windowNumber]` | `NSInterceptedRect.m` | static-reviewed; source authored; runtime pending; `i386/rect-state.md` |
| `0x47A08E44` | `-[NSInterceptedRect rectangle]` | `NSInterceptedRect.m` | static-reviewed; source authored; runtime pending; `i386/rect-state.md` |
| `0x47A08E6C` | `-[NSInterceptedRect isTotallyVisible]` | `NSInterceptedRect.m` | static-reviewed; source authored; runtime pending; `i386/rect-state.md` |
| `0x47A08E7C` | `-[NSInterceptedRect isTotallyObscured]` | `NSInterceptedRect.m` | static-reviewed; source authored; runtime pending; `i386/rect-state.md` |
| `0x47A08E8C` | `-[NSInterceptedRect _flags]` | `NSInterceptedRect.m` | static-reviewed; source authored; runtime pending; `i386/rect-state.md` |
| `0x47A08E9C` | `-[NSInterceptedRect framebuffer]` | `NSInterceptedRect.m` | static-reviewed; source authored; runtime pending; `i386/rect-state.md` |
| `0x47A08EAC` | `-[NSInterceptedRect _handleMsg:withReply:]` | `NSInterceptedRect.m` | static-reviewed; source authored; runtime pending |
| `0x47A09448` | `+[NSInterceptorClient initialize]` | `NSInterceptorClient.m` | static-reviewed; source authored; runtime pending; `i386/client-state.md` |
| `0x47A094F0` | `-[NSInterceptorClient init]` | `NSInterceptorClient.m` | static-reviewed; source authored; runtime pending; `i386/client-state.md` |
| `0x47A09604` | `-[NSInterceptorClient dealloc]` | `NSInterceptorClient.m` | static-reviewed; source authored; runtime pending; `i386/client-state.md` |
| `0x47A097A8` | `-[NSInterceptorClient setHandlingThread:]` | `NSInterceptorClient.m` | static-reviewed; source authored; runtime pending; `i386/client-state.md` |
| `0x47A09800` | `-[NSInterceptorClient handlingThread]` | `NSInterceptorClient.m` | static-reviewed; source authored; runtime pending; `i386/client-state.md` |
| `0x47A09828` | `-[NSInterceptorClient interceptorPort]` | `NSInterceptorClient.m` | static-reviewed; source authored; runtime pending; `i386/client-state.md` |
| `0x47A0994C` | `-[NSInterceptorClient handleInterceptorMessage:withReply:]` | `NSInterceptorClient.m` | static-reviewed; source authored; runtime pending; `i386/client-state.md` |
| `0x47A09A48` | `-[NSInterceptorClient _addInterceptedRect:returnedScreenRect:returnedFlags:]` | `NSInterceptorClient.m` | static-reviewed; source authored; runtime pending; `i386/client-state.md` |
| `0x47A09C0C` | `-[NSInterceptorClient _removeInterceptedRect:]` | `NSInterceptorClient.m` | static-reviewed; source authored; runtime pending; `i386/client-state.md` |
| `0x47A09C94` | `-[NSInterceptorClient _context]` | `NSInterceptorClient.m` | static-reviewed; source authored; runtime pending; `i386/client-state.md` |
| `0x47A09CA4` | `-[NSInterceptorClient windowServerPortDeath:]` | `NSInterceptorClient.m` | static-reviewed; source authored; runtime pending; `i386/client-state.md` |
| `0x47A09CE8` | `-[NSInterceptorClient _notifyHandler]` | `NSInterceptorClient.m` | static-reviewed; source authored; runtime pending; `i386/client-state.md` |
| `0x47A09F6C` | `-[NSInterceptorClient startHandlingThread]` | `NSInterceptorClient.m` | static-reviewed; source authored; runtime pending; `i386/client-state.md` |
| `0x47A0AA80` | `-[NSShape init]` | `NSShape.m` | static-reviewed; runtime pending |
| `0x47A0AAD8` | `-[NSShape initFromRect:]` | `NSShape.m` | static-reviewed; runtime pending |
| `0x47A0AB38` | `-[NSShape intersectWithShape:]` | `NSShape.m` | static-reviewed; runtime pending |
| `0x47A0AB6C` | `-[NSShape unionWithShape:]` | `NSShape.m` | static-reviewed; runtime pending |
| `0x47A0ABA0` | `-[NSShape differenceWithShape:]` | `NSShape.m` | static-reviewed; runtime pending |
| `0x47A0ABD4` | `-[NSShape isEmpty]` | `NSShape.m` | static-reviewed; runtime pending |
| `0x47A0ABEC` | `-[NSShape isEqual:]` | `NSShape.m` | static-reviewed; runtime pending |
| `0x47A0AC1C` | `-[NSShape copyWithZone:]` | `NSShape.m` | static-reviewed; runtime pending |
| `0x47A0AC9C` | `-[NSShape offsetShape:]` | `NSShape.m` | static-reviewed; runtime pending |
| `0x47A0ACEC` | `-[NSShape rectEnumerator]` | `NSShape.m` | static-reviewed; runtime pending |
| `0x47A0AD40` | `-[NSShape dealloc]` | `NSShape.m` | static-reviewed; source authored; runtime pending; `i386/shape.md` |
| `0x47A0AD84` | `-[NSShape description]` | `NSShape.m` | static-reviewed; source authored; runtime pending |
| `0x47A0AEB4` | `-[_NSShapeEnumerator initForShapeImpl:]` | `NSShape.m` | static-reviewed; runtime pending |
| `0x47A0AEF8` | `-[_NSShapeEnumerator nextRect]` | `NSShape.m` | static-reviewed; runtime pending |
| `0x47A0AFB8` | `-[NSSimpleBitmap initWithBitmapDataPlanes:pixelsWide:pixelsHigh:bitsPerSample:samplesPerPixel:hasAlpha:isPlanar:colorSpaceName:bytesPerRow:bitsPerPixel:]` | `NSSimpleBitmap.m` | static-reviewed; runtime pending |
| `0x47A0B0BC` | `-[NSSimpleBitmap bitmapData]` | `NSSimpleBitmap.m` | static-reviewed; runtime pending |
| `0x47A0B0CC` | `-[NSSimpleBitmap getBitmapDataPlanes:]` | `NSSimpleBitmap.m` | static-reviewed; runtime pending |
| `0x47A0B124` | `-[NSSimpleBitmap isPlanar]` | `NSSimpleBitmap.m` | static-reviewed; runtime pending |
| `0x47A0B134` | `-[NSSimpleBitmap hasAlpha]` | `NSSimpleBitmap.m` | static-reviewed; runtime pending |
| `0x47A0B144` | `-[NSSimpleBitmap samplesPerPixel]` | `NSSimpleBitmap.m` | static-reviewed; runtime pending |
| `0x47A0B154` | `-[NSSimpleBitmap bitsPerPixel]` | `NSSimpleBitmap.m` | static-reviewed; runtime pending |
| `0x47A0B164` | `-[NSSimpleBitmap bitsPerSample]` | `NSSimpleBitmap.m` | static-reviewed; runtime pending |
| `0x47A0B174` | `-[NSSimpleBitmap bytesPerRow]` | `NSSimpleBitmap.m` | static-reviewed; runtime pending |
| `0x47A0B184` | `-[NSSimpleBitmap bytesPerPlane]` | `NSSimpleBitmap.m` | static-reviewed; runtime pending |
| `0x47A0B198` | `-[NSSimpleBitmap numberOfPlanes]` | `NSSimpleBitmap.m` | static-reviewed; runtime pending |
| `0x47A0B1B0` | `-[NSSimpleBitmap colorSpaceName]` | `NSSimpleBitmap.m` | static-reviewed; runtime pending |
| `0x47A0B1C0` | `-[NSSimpleBitmap pixelsWide]` | `NSSimpleBitmap.m` | static-reviewed; runtime pending |
| `0x47A0B1D0` | `-[NSSimpleBitmap pixelsHigh]` | `NSSimpleBitmap.m` | static-reviewed; runtime pending |
| `0x47A0B1E0` | `-[NSSimpleBitmap dealloc]` | `NSSimpleBitmap.m` | static-reviewed; runtime pending |
| `0x47A0B22C` | `-[NSSimpleBitmap(Obsolete) colorSpace]` | `NSSimpleBitmap.m` | static-reviewed; source authored; runtime pending |
| `0x47A0B24C` | `-[NSSimpleBitmap(Obsolete) data]` | `NSSimpleBitmap.m` | static-reviewed; source authored; runtime pending |
