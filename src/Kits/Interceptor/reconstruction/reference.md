# Interceptor reference inventory

Behavioral authority: the normal PowerPC framework under `C:\Users\raynorpat\Downloads\test\Frameworks\Interceptor.framework\Versions\A`. DR2 provides the i386 slice and same-release architecture comparison. Binaries and analyzer databases remain outside Git.

| Image | CPU/format | Bytes | SHA-256 | `__text` bytes | symbols | named ObjC methods |
|---|---|---:|---|---:|---:|---:|
| Primary normal | ppc MH_DYLIB | 145364 | `8b98846ae99cc7b8120a5dcf8b9a21855700895d0df5fe0da403c9f183d63a96` | 57332 | 540 | 234 |
| Primary profile | ppc MH_DYLIB | 170032 | `de209f58f70c69a346460e95bfb3ffed2d3400e49602a1b8178e1b42521084de` | 74244 | 541 | 234 |
| DR2 i386 slice | i386 MH_DYLIB | 140216 | `56eb8f81b06cfbdbe898d39c4766720f71b1c1effd54869f78cd3340dc9a9dd1` | inventory in IDA output | 629 | 232 |
| DR2 ppc slice | ppc MH_DYLIB | 156188 | `9f83fda9410d56530b9d98d695ebbb84d767f58f0fb3f93fe1e45d1793755fcc` | inventory in IDA output | 619 | 232 |

The DR2 fat container is 311836 bytes, SHA-256 `e7af0995aa6bcc744ce00137d29cdd8ce2daf3f93cd0efa436f4e90d3ab46041`; its i386 slice begins at offset 8192 and its PowerPC slice at 155648.

The binary's Objective-C module metadata identifies these nine source files:

- NSDirectBitmap.m
- NSDirectPalette.m
- NSDirectScreen.m
- NSFramebuffer.m
- NSInterceptedRect.m
- NSInterceptorClient.m
- NSShape.m
- NSSimpleBitmap.m
- NSFramework_Interceptor.m

The primary load commands link `/usr/lib/libDriver.A.dylib`, AppKit Versions/C, Foundation Versions/C, and System Versions/B. The framework install name is `/System/Library/Frameworks/Interceptor.framework/Versions/A/Interceptor`.

The DR2 i386 slice links AppKit, Foundation, and System but has no
`libDriver.A.dylib` load command. Its embedded `__IO*`/`__PM*` RPC clients
correspond to DriverKit's MIG client definitions and are treated as linked
support code; see `i386/linkage.md` for ownership evidence and the event-lock
assembly classification.

The analyzer worklists are in `function-worklist.md`. The current Objective-C metadata helper returns 151 method names from the primary image, while its symbol table names 234 methods. Resolve this 83-method coverage gap before relying on the helper as a complete source map.
