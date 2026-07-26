# drvVGA baseline build

Records the result of building `src/drivers-i386/video/drvVGA` for the first
time in this tree, immediately after Task 4 restructured it into the
Aggregate -> Driver -> Kernel Server project shape. No source under
`drvVGA` has been edited since that restructuring. This is a measurement,
not a repair: the sources inside are unmodified inventions (Task 4's
restructuring changed layout only), and the point of this baseline is to
record whether they compile *before* the reconstruction phase starts
rewriting them, so a later failure cannot be misattributed to that work.

## Result: build FAILED (pre-existing)

`gnumake` fails while compiling `VGAConfigTable.m`. Neither `VGA_reloc`
nor `VGA_psdrvr` was produced, so there is nothing to stage, copy back, or
run `parity_check.py` against. Steps 4 and 5 of the task brief (copy
staged artifacts back to the host, record parity numbers) do not apply to
this run for that reason.

Per the effort's instructions for this task, this is recorded as the
baseline as-is; no `.m`/`.c`/`.h` file was edited to make the build pass.
A repair, if warranted, belongs in its own separate commit per the task
brief's Step 7, not folded into this one.

## Step 2: sync to the guest

```bash
cd /d/RhapsodiOS
PW=$(grep -i '^Password=' vm/vm.conf | cut -d= -f2)
HOST=$(grep -i '^Host=' vm/vm.conf | cut -d= -f2)
"/c/Program Files/PuTTY/pscp.exe" -batch -r -pw "$PW" src/drivers-i386/video/drvVGA root@$HOST:/build/source/src/drivers-i386/video/
"/c/Program Files/PuTTY/pscp.exe" -batch -pw "$PW" vm/build-i386-vga.sh root@$HOST:/build/source/vm/
```

Both transfers completed (exit 0), copying `Makefile`, `Makefile.pre/postamble`,
`Default.table`, `DriverInfo`, `English.lproj/{Info.rtf,Localizable.strings}`,
`SVGABIOS.table`, `Load_Commands.sect`, `VGA.h`, `VGA.m`, `VGAConfigTable.m`,
`VGAModes.{c,h}`, `VGASetMode.m`, `VGAPSDriver.{c,h}`, and their Makefiles.

## Step 3: build

```bash
cd /d/RhapsodiOS
PW=$(grep -i '^Password=' vm/vm.conf | cut -d= -f2)
HOST=$(grep -i '^Host=' vm/vm.conf | cut -d= -f2)
"/c/Program Files/PuTTY/plink.exe" -batch -pw "$PW" root@$HOST 'tr -d "\r" < /build/source/vm/build-i386-vga.sh > /tmp/br && mv /tmp/br /build/source/vm/build-i386-vga.sh; sh /build/source/vm/build-i386-vga.sh' > /tmp/vga-build.log 2>&1
echo "EXIT=$?"
```

`EXIT=1`

Full log:

```
======== build VGA (drvVGA) ========
Makefile.postamble:2: /NextDeveloper/Makefiles/driverkit/Makefile.bundle_postamble: No such file or directory
== Making all for i386 in VGA.drvproj ==
== Making VGA for i386 ==
Pre-build setup...
/bin/rm -f /build/source/src/drivers-i386/video/drvVGA/VGA.build/derived_src/TrustedPrecomps.txt
......in VGA
......in VGA_psdrvr
Building...
......in VGA
Creating VGA_instance.m
/usr/bin/cc -arch i386 -O  -Wmost -precomp-trustfile /build/source/src/drivers-i386/video/drvVGA/VGA.build/derived_src/TrustedPrecomps.txt -g  -fno-common -I/build/source/src/drivers-i386/video/drvVGA/VGA.build/ProjectHeaders -I/build/source/src/drivers-i386/video/drvVGA/VGA.build/PrivateHeaders/ -I/build/source/src/drivers-i386/video/drvVGA/VGA.build/Headers/ -I/build/source/src/drivers-i386/video/drvVGA/VGA.build/derived_src/VGA.drvproj/VGA.lksproj -I. -pipe   -static -DKERNEL -D_KERNEL -DMACH_USER_API -DKERNEL_SERVER_INSTANCE=VGA_instance       -I/build/source/src/drivers-i386/video/drvVGA/VGA.build/Headers -I/build/source/src/drivers-i386/video/drvVGA/VGA.build/PrivateHeaders -F/build/source/src/drivers-i386/video/drvVGA  -F/System/Library/PrivateFrameworks -F/System/Library/PrivateFrameworks        -ObjC        -c -o /build/source/src/drivers-i386/video/drvVGA/VGA.build/objects-optimized/VGA.drvproj/VGA.lksproj/VGA.i386.o VGA.m
/usr/bin/cc -arch i386 -O  -Wmost -precomp-trustfile /build/source/src/drivers-i386/video/drvVGA/VGA.build/derived_src/TrustedPrecomps.txt -g  -fno-common -I/build/source/src/drivers-i386/video/drvVGA/VGA.build/ProjectHeaders -I/build/source/src/drivers-i386/video/drvVGA/VGA.build/PrivateHeaders/ -I/build/source/src/drivers-i386/video/drvVGA/VGA.build/Headers/ -I/build/source/src/drivers-i386/video/drvVGA/VGA.build/derived_src/VGA.drvproj/VGA.lksproj -I. -pipe   -static -DKERNEL -D_KERNEL -DMACH_USER_API -DKERNEL_SERVER_INSTANCE=VGA_instance       -I/build/source/src/drivers-i386/video/drvVGA/VGA.build/Headers -I/build/source/src/drivers-i386/video/drvVGA/VGA.build/PrivateHeaders -F/build/source/src/drivers-i386/video/drvVGA  -F/System/Library/PrivateFrameworks -F/System/Library/PrivateFrameworks        -ObjC        -c -o /build/source/src/drivers-i386/video/drvVGA/VGA.build/objects-optimized/VGA.drvproj/VGA.lksproj/VGAConfigTable.i386.o VGAConfigTable.m
VGAConfigTable.m: In function `-[VGA(ConfigTable) valueForStringKey:]':
VGAConfigTable.m:19: warning: `VGA' does not respond to `configTable'
VGAConfigTable.m:20: warning: `VGA' does not respond to `configTable'
VGAConfigTable.m:20: warning: static access to object of type `id'
VGAConfigTable.m:20: structure has no member named `valueForStringKey'
VGAConfigTable.m:17: warning: `value' might be used uninitialized in this function
VGAConfigTable.m: In function `-[VGA(ConfigTable) parametersForMode:forStringKey:parameters:count:]':
VGAConfigTable.m:34: warning: `VGA' does not respond to `configTable'
VGAConfigTable.m:37: warning: `VGA' does not respond to `configTable'
VGAConfigTable.m:37: warning: static access to object of type `id'
VGAConfigTable.m:37: structure has no member named `valueForStringKey'
VGAConfigTable.m:42: warning: implicit declaration of function `strncpy'
VGAConfigTable.m:32: warning: `value' might be used uninitialized in this function
VGAConfigTable.m: In function `-[VGA(ConfigTable) booleanForStringKey:withDefault:]':
VGAConfigTable.m:56: warning: `VGA' does not respond to `configTable'
VGAConfigTable.m:59: warning: `VGA' does not respond to `configTable'
VGAConfigTable.m:59: warning: static access to object of type `id'
VGAConfigTable.m:59: structure has no member named `valueForStringKey'
VGAConfigTable.m:54: warning: `value' might be used uninitialized in this function
gnumake[2]: *** [/build/source/src/drivers-i386/video/drvVGA/VGA.build/objects-optimized/VGA.drvproj/VGA.lksproj/VGAConfigTable.i386.o] Error 1
gnumake[1]: *** [build@VGA.lksproj] Error 2
gnumake: *** [all@VGA.drvproj] Error 2
make exit=2 for VGA
=== vga done fail=1 ===
FAILED: no VGA_reloc
FAILED: no VGA_psdrvr
/build/source/src/drivers-i386/video/drvVGA/VGA.drvproj/VGA_psdrvr.tproj
/build/source/src/drivers-i386/video/drvVGA/VGA.build/objects-optimized/VGA.drvproj/VGA_psdrvr.tproj
/build/source/src/drivers-i386/video/drvVGA/VGA.build/derived_src/VGA.drvproj/VGA_psdrvr.tproj
/build/source/src/drivers-i386/video/drvVGA/VGA.config
```

`make exit=2 for VGA`. Harness exit: `=== vga done fail=1 ===` (script `exit 1`).

### Root cause

`VGA.drvproj/VGA.lksproj/VGAConfigTable.m` (the `VGA (ConfigTable)`
category) calls `[self configTable]`, a method the `VGA` class does not
declare or inherit (see `VGA.h` / `VGA.m`). The compiler falls back to
treating the message send as returning `id` (hence "static access to
object of type `id`") and then fails outright on
`->valueForStringKey(key)` because the resulting expression has "no
member named `valueForStringKey`" — that member-access form assumes a
C++ style vtable-object pointer, not an Objective-C message send. This is
a pre-existing defect in the invented source carried over unmodified from
before Task 4; Task 4 only moved files into the new project layout and
did not touch `VGAConfigTable.m`.

The `VGA_psdrvr.tproj` subproject never reached its own compile step:
`gnumake`'s aggregate build for `VGA.drvproj` stopped at the first
subproject failure (`VGA.lksproj`), so `VGA_psdrvr` was not attempted in
this run. Confirmed on the guest — only `VGA.i386.o` (from `VGA.m`) and
`derived_src/VGA.drvproj/VGA.lksproj/VGA_instance.m` exist under
`VGA.build`; no objects exist under `VGA.build/objects-optimized/VGA.drvproj/VGA_psdrvr.tproj`.

There is also an unrelated benign warning from `Makefile.postamble`
(`/NextDeveloper/Makefiles/driverkit/Makefile.bundle_postamble: No such
file or directory`) that does not stop the build — it fires before the
compile phase and the aggregate build proceeds past it.

## Steps 4-5: staged binaries / parity numbers

Not applicable. No `VGA_reloc` or `VGA_psdrvr` was produced by this
build, so there was nothing to copy back to `out/i386/drvVGA/VGA.config/`
and nothing to hand to `tools/binrecon/parity_check.py`. Confirmed no
staging directory was populated on the guest
(`/build/out/i386/drvVGA/VGA.config` does not exist because the harness's
own success path, which creates it, was never reached — the script exits
1 before staging).

## Step 7: repair

Not attempted in this task per the effort's instructions for Task 5: this
is a measurement task, and a build failure is a legitimate, expected
baseline result. A repair, if warranted, is scoped to its own later
commit per the task brief's Step 7.
