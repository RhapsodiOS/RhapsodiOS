# Interceptor ABI inventory

The supplied headers are the declaration authority. Task 3 will copy them byte-for-byte into the framework project and add architecture-specific checks against Objective-C metadata.

| Public header | Bytes | SHA-256 |
|---|---:|---|
| Interceptor.h | 399 | `141DD0D5AB96A7E7E229E371E081DA4DE7384F86CA750A194A1808E90E69C35F` |
| Interceptor_types.h | 6181 | `6E840655D87D92D8DCC78B0F0054D56564C98ECDD93E8DF87FD2BC9F7C503361` |
| InterceptorGlobals.h | 903 | `10D2393997C22DFC41B8CED53A3D08B32F7B455004D2F44E09943DABDA318322` |
| NSBitmap.h | 1976 | `727FEA357CD9F3B53BC22F5CD9C40EF2BDA366F8794138221F60660CC4C679F4` |
| NSDirectBitmap.h | 1654 | `C76353D8597A382D3ED38B29416667711AE983141907F0329BFD9F0CC45C559E` |
| NSDirectPalette.h | 1194 | `31AB1D4C47F685B0FB773EF1CC3C0FA37F6950A35986675014D9BA5DADBB8D49` |
| NSDirectScreen.h | 3145 | `C6B6B668B30EDEA34B10D5D080B881B5671AD528CE53CAB4888A27572F89CFF0` |
| NSFramebuffer.h | 2136 | `17D3F1000ABE5BA76030FDDA5375A9D7F805B58729DA588FE5D5F2BB4076003B` |
| NSShape.h | 773 | `0B87EAE0EAD79E704A8839488F19E1428F08D73CD10496C661185FA5E16C40D9` |

Public interfaces include the pixel encoding types and `InterceptorReturn`; `NSDirectBitmapProtocol`; NSSimpleBitmap; NSDirectBitmap; NSDirectPalette; NSDirectScreen; NSFramebuffer; and NSShape. `NSInterceptorClient`, `NSInterceptedRect`, and `_NSShapeEnumerator` are present in the binary and need private declarations recovered from metadata and disassembly.

## Recovered class and ivar layout

All three available slices agree on these class instance sizes, ivar type encodings, and byte offsets. This establishes stable DR2-to-newer layouts for the classes present in all references. Offsets are from the start of the Objective-C instance.

| Class | Instance size | Ivar name : type @ byte offset |
|---|---:|---|
| `NSDirectBitmap` | 200 | `isBuffered` : `c` @ 104; `isDirectMapped` : `c` @ 105; `isUnobscured` : `c` @ 106; `isLocked` : `c` @ 107; `depthMismatch` : `c` @ 108; `drawToBuffer` : `c` @ 109; `updateNeeded` : `c` @ 110; `framebuffer` : `@` @ 112; `currentScreen` : `i` @ 116; `newScreen` : `i` @ 120; `interceptRect` : `@` @ 124; `interceptClient` : `@` @ 128; `copyFunc` : `^?` @ 132; `window` : `@` @ 136; `gWinNum` : `i` @ 140; `rect` : `{?="origin"{?="x"f"y"f}"size"{?="width"f"height"f}}` @ 144; `_flushOnExposure` : `i` @ 160; `_delegate` : `@` @ 164; `_viewClip` : `@` @ 168; `processingDelegate` : `i` @ 172; `fbMode` : `i` @ 176; `_naughtyFlags` : `i` @ 180; `_screenIsDirty` : `c` @ 184; `_dbm_pad2` : `c` @ 185; `_dbm_pad3` : `c` @ 186; `_dbm_pad4` : `c` @ 187; `_dbm_padding` : `[2I]` @ 188; `_dbm_private` : `^v` @ 196 |
| `NSDirectPalette` | 8 | `_private` : `^v` @ 4 |
| `NSDirectScreen` | 8 | `_private` : `^v` @ 4 |
| `NSFramebuffer` | 336 | `interceptorClient` : `@` @ 104; `screenNumber` : `i` @ 108; `bounds` : `{?="origin"{?="x"f"y"f}"size"{?="width"f"height"f}}` @ 112; `pixelEncoding` : `[64c]` @ 128; `publicPixelEncoding` : `@"NSString"` @ 192; `driver` : `[80c]` @ 196; `publicDriver` : `@"NSString"` @ 276; `deviceSlot` : `i` @ 280; `deviceUnit` : `i` @ 284; `conversionTable` : `^v` @ 288; `inverseConversionTable` : `^v` @ 292; `isMapped` : `c` @ 296; `_fb_padding1` : `I` @ 300; `_palette` : `^{?}` @ 304; `_paletteSize` : `i` @ 308; `_fb_padding` : `[5I]` @ 312; `_fb_private` : `^v` @ 332 |
| `NSInterceptedRect` | 108 | `rect` : `{?="origin"{?="x"f"y"f}"size"{?="width"f"height"f}}` @ 4; `screenRect` : `{?="origin"{?="x"f"y"f}"size"{?="width"f"height"f}}` @ 20; `windowNumber` : `i` @ 36; `screen` : `@` @ 40; `uniqueID` : `I` @ 44; `target` : `@` @ 48; `flags` : `I` @ 52; `rectLock` : `@"NSConditionLock"` @ 56; `isTotallyVisible` : `c` @ 60; `isTotallyObscured` : `c` @ 61; `moveInProgress` : `c` @ 62; `isLocked` : `c` @ 63; `tmpBitmap` : `@"NSSimpleBitmap"` @ 64; `interceptorClient` : `@"NSInterceptorClient"` @ 68; `screenRectShape` : `@"NSShape"` @ 72; `_ir_padding` : `[7I]` @ 76; `_ir_private` : `^v` @ 104 |
| `NSInterceptorClient` | 68 | `context` : `^{?}` @ 4; `interceptedRects` : `@"NSMutableArray"` @ 8; `listLock` : `@"NSConditionLock"` @ 12; `portLock` : `@"NSLock"` @ 16; `handlingThread` : `@"NSThread"` @ 20; `_reserved0` : `c` @ 24; `_notifyPort` : `@"NSPort"` @ 28; `_padding` : `[8I]` @ 32; `_private` : `^v` @ 64 |
| `_NSShapeEnumerator` | 28 | `xloc` : `^s` @ 4; `yloc` : `^s` @ 8; `r` : `{?="origin"{?="x"f"y"f}"size"{?="width"f"height"f}}` @ 12 |
| `NSShape` | 12 | `zone` : `^{?}` @ 4; `_impl` : `^v` @ 8 |
| `NSSimpleBitmap` | 104 | `isPlanar` : `c` @ 4; `hasAlpha` : `c` @ 5; `bitsPerSample` : `i` @ 8; `samplesPerPixel` : `i` @ 12; `bitsPerPixel` : `i` @ 16; `bytesPerRow` : `i` @ 20; `bytesPerPlane` : `i` @ 24; `numPlanes` : `i` @ 28; `pixelsWide` : `i` @ 32; `pixelsHigh` : `i` @ 36; `colorSpace` : `@"NSString"` @ 40; `colorSpaceCode` : `i` @ 44; `data` : `[5^v]` @ 48; `_bm_padding` : `[8I]` @ 68; `_bm_private` : `^v` @ 100 |
| `NSFramework_Interceptor` | 0 | none |

## Runtime selector type encodings

The ABI test checks these encodings from the primary PowerPC reference and the
DR2 i386 reference. The architecture-specific offsets differ because the
32-bit ABIs place `self`, `_cmd`, and arguments differently. The reconstructed
framework is expected to keep the primary API on both CPUs, including the newer
`defaultColorPalette` class method.

| Selector | PowerPC | i386 |
|---|---|---|
| `-[NSShape intersectWithShape:]` | `v8@4:8@12` | `v12@8:12@16` |
| `-[NSShape initFromRect:]` | `@20@4:8{?={?=ff}{?=ff}}12` | `@24@8:12{?={?=ff}{?=ff}}16` |
| `-[NSFramebuffer addressForPoint:]` | `^v12@4:8{?=ff}12` | `^v16@8:12{?=ff}16` |
| `-[NSDirectPalette setColor:atIndex:]` | `v12@4:8@12i16` | `v16@8:12@16i20` |
| `-[NSSimpleBitmap initWithBitmapDataPlanes:...]` | `@48@4:8^*12i16i20i24i28c32c43@44i48i52` | `@48@8:12^*16i20i24i28i32c36c40@44i48i52` |
| `+[NSDirectPalette defaultColorPalette]` | `@4@4:8` | `@4@8:12` |

The ABI test covers all inventoried class sizes and ivar names, types, and
offsets, plus the selected public layouts, enum endpoints, and selectors above.
Its test helper is self-checked against deliberately altered class-size and
selector-encoding fixtures. The build/runtime harness still requires a
compatible historical toolchain and guest before its result can be claimed.
