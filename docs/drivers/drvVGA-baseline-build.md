# drvVGA baseline build

Records the result of building `src/drivers-i386/video/drvVGA` for the first
time in this tree, immediately after Task 4 restructured it into the
Aggregate -> Driver -> Kernel Server project shape. This is a measurement,
not a repair in spirit: the sources inside are unmodified inventions (Task
4's restructuring changed layout only), and the point of this baseline is to
record whether they compile *before* the reconstruction phase starts
rewriting them, so a later failure cannot be misattributed to that work.

The very first run of this harness (commit `29a68ac2`) failed to compile.
Task 5's own Step 7 requires that pre-existing failure to be repaired in its
own commit and the baseline re-run; this document records the result of
that repair.

## Result: build PASSES (after Step 7 repair)

Two repairs were required, each in its own commit, before both `VGA_reloc`
and `VGA_psdrvr` could be produced:

1. `64bab51e` — `VGAConfigTable.m` called `[self configTable]` (a method
   `VGA` does not declare) and then used C struct-arrow syntax
   (`->valueForStringKey(key)`) on the result. Fixed to reach the table via
   `[[self deviceDescription] configTable]` and call it as an ordinary
   Objective-C message (`[configTable valueForStringKey:key]`), matching the
   idiom used elsewhere in DriverKit (`IOFrameBufferDisplay.m`,
   `IOSVGADisplay.m`).
2. `11637fc1` — `VGA.drvproj`, `VGA.drvproj/VGA.lksproj`, and
   `VGA.drvproj/VGA_psdrvr.tproj` had no `PB.project` file at any of the
   three levels (every other driver under `src/drivers-i386` has one at
   each level). `bundle.make` needs `VGA_psdrvr.tproj/PB.project` to
   generate `Info-nextstep.plist`; without it the aggregate build failed in
   the second subproject with "No rule to make target `PB.project`". Added
   the three missing files, modeled on `drvPCIBus`'s `PB.project`s and
   `drvEISABus`'s `PnPDump.tproj/PB.project`.

With both repairs in place, `gnumake` still exits nonzero (`make exit=2`)
because of a later, expected packaging step failure — `English.copy-local-
resources` fails because `VGA.drvproj/English.lproj/SVGABIOS.strings` does
not exist yet (a later task creates it; the harness's own header comment
anticipates accepting the run once both binaries exist even if a later
packaging rule exits nonzero). Both `VGA_reloc` and `VGA_psdrvr` are
produced before that point, so the harness itself reports success
(`=== vga done fail=0 ===`).

## Step 2: sync to the guest

```bash
cd /d/RhapsodiOS
PW=$(grep -i '^Password=' vm/vm.conf | cut -d= -f2)
HOST=$(grep -i '^Host=' vm/vm.conf | cut -d= -f2)
"/c/Program Files/PuTTY/pscp.exe" -batch -r -pw "$PW" src/drivers-i386/video/drvVGA root@$HOST:/build/source/src/drivers-i386/video/
"/c/Program Files/PuTTY/pscp.exe" -batch -pw "$PW" vm/build-i386-vga.sh root@$HOST:/build/source/vm/
```

Both transfers completed (exit 0), copying `Makefile`, `Makefile.pre/postamble`,
`PB.project` (at all three levels), `Default.table`, `DriverInfo`,
`English.lproj/{Info.rtf,Localizable.strings}`, `SVGABIOS.table`,
`Load_Commands.sect`, `VGA.h`, `VGA.m`, `VGAConfigTable.m`, `VGAModes.{c,h}`,
`VGASetMode.m`, `VGAPSDriver.{c,h}`, and their Makefiles.

## Step 3: build

```bash
cd /d/RhapsodiOS
PW=$(grep -i '^Password=' vm/vm.conf | cut -d= -f2)
HOST=$(grep -i '^Host=' vm/vm.conf | cut -d= -f2)
"/c/Program Files/PuTTY/plink.exe" -batch -pw "$PW" root@$HOST 'tr -d "\r" < /build/source/vm/build-i386-vga.sh > /tmp/br && mv /tmp/br /build/source/vm/build-i386-vga.sh; sh /build/source/vm/build-i386-vga.sh' > /tmp/vga-build.log 2>&1
echo "EXIT=$?"
```

`EXIT=0`

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
/usr/bin/cc -arch i386 -O  -Wmost -precomp-trustfile /build/source/src/drivers-i386/video/drvVGA/VGA.build/derived_src/TrustedPrecomps.txt -g  -fno-common -I/build/source/src/drivers-i386/video/drvVGA/VGA.build/ProjectHeaders -I/build/source/src/drivers-i386/video/drvVGA/VGA.build/PrivateHeaders/ -I/build/source/src/drivers-i386/video/drvVGA/VGA.build/Headers/ -I/build/source/src/drivers-i386/video/drvVGA/VGA.build/derived_src/VGA.drvproj/VGA.lksproj -I. -pipe   -static -DKERNEL -D_KERNEL -DMACH_USER_API -DKERNEL_SERVER_INSTANCE=VGA_instance       -I/build/source/src/drivers-i386/video/drvVGA/VGA.build/Headers -I/build/source/src/drivers-i386/video/drvVGA/VGA.build/PrivateHeaders -F/build/source/src/drivers-i386/video/drvVGA  -F/System/Library/PrivateFrameworks -F/System/Library/PrivateFrameworks        -ObjC        -c -o /build/source/src/drivers-i386/video/drvVGA/VGA.build/objects-optimized/VGA.drvproj/VGA.lksproj/VGA.i386.o VGA.m
/usr/bin/cc -arch i386 -O  -Wmost -precomp-trustfile /build/source/src/drivers-i386/video/drvVGA/VGA.build/derived_src/TrustedPrecomps.txt -g  -fno-common -I/build/source/src/drivers-i386/video/drvVGA/VGA.build/ProjectHeaders -I/build/source/src/drivers-i386/video/drvVGA/VGA.build/PrivateHeaders/ -I/build/source/src/drivers-i386/video/drvVGA/VGA.build/Headers/ -I/build/source/src/drivers-i386/video/drvVGA/VGA.build/derived_src/VGA.drvproj/VGA.lksproj -I. -pipe   -static -DKERNEL -D_KERNEL -DMACH_USER_API -DKERNEL_SERVER_INSTANCE=VGA_instance       -I/build/source/src/drivers-i386/video/drvVGA/VGA.build/Headers -I/build/source/src/drivers-i386/video/drvVGA/VGA.build/PrivateHeaders -F/build/source/src/drivers-i386/video/drvVGA  -F/System/Library/PrivateFrameworks -F/System/Library/PrivateFrameworks        -ObjC        -c -o /build/source/src/drivers-i386/video/drvVGA/VGA.build/objects-optimized/VGA.drvproj/VGA.lksproj/VGAConfigTable.i386.o VGAConfigTable.m
VGAConfigTable.m: In function `-[VGA(ConfigTable) parametersForMode:forStringKey:parameters:count:]':
VGAConfigTable.m:46: warning: implicit declaration of function `strncpy'
/usr/bin/cc -arch i386 -O  -Wmost -precomp-trustfile /build/source/src/drivers-i386/video/drvVGA/VGA.build/derived_src/TrustedPrecomps.txt -g  -fno-common -I/build/source/src/drivers-i386/video/drvVGA/VGA.build/ProjectHeaders -I/build/source/src/drivers-i386/video/drvVGA/VGA.build/PrivateHeaders/ -I/build/source/src/drivers-i386/video/drvVGA/VGA.build/Headers/ -I/build/source/src/drivers-i386/video/drvVGA/VGA.build/derived_src/VGA.drvproj/VGA.lksproj -I. -pipe   -static -DKERNEL -D_KERNEL -DMACH_USER_API -DKERNEL_SERVER_INSTANCE=VGA_instance       -I/build/source/src/drivers-i386/video/drvVGA/VGA.build/Headers -I/build/source/src/drivers-i386/video/drvVGA/VGA.build/PrivateHeaders -F/build/source/src/drivers-i386/video/drvVGA  -F/System/Library/PrivateFrameworks -F/System/Library/PrivateFrameworks        -ObjC        -c -o /build/source/src/drivers-i386/video/drvVGA/VGA.build/objects-optimized/VGA.drvproj/VGA.lksproj/VGASetMode.i386.o VGASetMode.m
VGASetMode.m: In function `-[VGA(SetMode) selectMode]':
VGASetMode.m:33: warning: unused variable `i'
/usr/bin/cc -arch i386 -O  -Wmost -precomp-trustfile /build/source/src/drivers-i386/video/drvVGA/VGA.build/derived_src/TrustedPrecomps.txt -g  -fno-common -I/build/source/src/drivers-i386/video/drvVGA/VGA.build/ProjectHeaders -I/build/source/src/drivers-i386/video/drvVGA/VGA.build/PrivateHeaders/ -I/build/source/src/drivers-i386/video/drvVGA/VGA.build/Headers/ -I/build/source/src/drivers-i386/video/drvVGA/VGA.build/derived_src/VGA.drvproj/VGA.lksproj -I. -pipe   -static -DKERNEL -D_KERNEL -DMACH_USER_API -DKERNEL_SERVER_INSTANCE=VGA_instance       -I/build/source/src/drivers-i386/video/drvVGA/VGA.build/Headers -I/build/source/src/drivers-i386/video/drvVGA/VGA.build/PrivateHeaders -F/build/source/src/drivers-i386/video/drvVGA  -F/System/Library/PrivateFrameworks -F/System/Library/PrivateFrameworks        -c -o /build/source/src/drivers-i386/video/drvVGA/VGA.build/objects-optimized/VGA.drvproj/VGA.lksproj/VGAModes.i386.o VGAModes.c
VGAModes.c:24: warning: missing braces around initializer for `vgaModes[0].displayInfo.pixelEncoding'
/usr/bin/kl_ld -o /build/source/src/drivers-i386/video/drvVGA/VGA.config/VGA_reloc -n VGA  -i VGA_instance -l Load_Commands.sect   -arch i386  /build/source/src/drivers-i386/video/drvVGA/VGA.build/objects-optimized/VGA.drvproj/VGA.lksproj/VGA.o /build/source/src/drivers-i386/video/drvVGA/VGA.build/objects-optimized/VGA.drvproj/VGA.lksproj/VGAConfigTable.o /build/source/src/drivers-i386/video/drvVGA/VGA.build/objects-optimized/VGA.drvproj/VGA.lksproj/VGASetMode.o  /build/source/src/drivers-i386/video/drvVGA/VGA.build/objects-optimized/VGA.drvproj/VGA.lksproj/VGAModes.o           /build/source/src/drivers-i386/video/drvVGA/VGA.build/objects-optimized/VGA.drvproj/VGA.lksproj/VGA_instance.o         
ld: warning /usr/lib/libcc.a archive's cputype (18, architecture ppc) does not match cputype (7) for specified -arch flag: i386 (can't load from it)
......in VGA_psdrvr
/usr/lib/mergeInfo PB.project /build/source/src/drivers-i386/video/drvVGA/VGA.build/derived_src/VGA.drvproj/VGA_psdrvr.tproj/Java.plist -o /build/source/src/drivers-i386/video/drvVGA/VGA.config/VGA_psdrvr.bundle/Resources/Info-nextstep.plist
/usr/bin/cc -arch i386 -O  -Wmost -precomp-trustfile /build/source/src/drivers-i386/video/drvVGA/VGA.build/derived_src/TrustedPrecomps.txt -g  -fno-common -I/build/source/src/drivers-i386/video/drvVGA/VGA.build/ProjectHeaders -I/build/source/src/drivers-i386/video/drvVGA/VGA.config/VGA_psdrvr.bundle/PrivateHeaders -I/build/source/src/drivers-i386/video/drvVGA/VGA.config/VGA_psdrvr.bundle/Headers -I/build/source/src/drivers-i386/video/drvVGA/VGA.build/derived_src/VGA.drvproj/VGA_psdrvr.tproj -I. -pipe        -I/build/source/src/drivers-i386/video/drvVGA/VGA.build/Headers -I/build/source/src/drivers-i386/video/drvVGA/VGA.build/PrivateHeaders -F/build/source/src/drivers-i386/video/drvVGA  -F/System/Library/PrivateFrameworks -F/System/Library/PrivateFrameworks        -c -o /build/source/src/drivers-i386/video/drvVGA/VGA.build/objects-optimized/VGA.drvproj/VGA_psdrvr.tproj/VGAPSDriver.i386.o VGAPSDriver.c
/usr/bin/cc   -L/build/source/src/drivers-i386/video/drvVGA/VGA.build/objects-optimized/VGA.drvproj/VGA_psdrvr.tproj        -F/build/source/src/drivers-i386/video/drvVGA -L/build/source/src/drivers-i386/video/drvVGA -F/System/Library/PrivateFrameworks -F/System/Library/PrivateFrameworks      -arch i386 -o /build/source/src/drivers-i386/video/drvVGA/VGA.config/VGA_psdrvr.bundle/VGA_psdrvr    /build/source/src/drivers-i386/video/drvVGA/VGA.build/objects-optimized/VGA.drvproj/VGA_psdrvr.tproj/VGAPSDriver.o                    
/usr/bin/ld: warning /lib/crt1.o cputype (18, architecture ppc) does not match cputype (7) for specified -arch flag: i386 (file not loaded)
/usr/bin/ld: warning /usr/lib/libcc_dynamic.a archive's cputype (18, architecture ppc) does not match cputype (7) for specified -arch flag: i386 (can't load from it)
/usr/bin/ld: warning /System/Library/Frameworks/System.framework/System cputype (18, architecture ppc) does not match cputype (7) for specified -arch flag: i386 (file not loaded)
Copying English resources...
fastcp: '/build/source/src/drivers-i386/video/drvVGA/VGA.drvproj/English.lproj/SVGABIOS.strings' does not exist.
gnumake[1]: *** [English.copy-local-resources] Error 255
gnumake: *** [all@VGA.drvproj] Error 2
make exit=2 for VGA
/build/source/src/drivers-i386/video/drvVGA/VGA.config/VGA_reloc: Mach-O preload executable i386
/build/source/src/drivers-i386/video/drvVGA/VGA.config/VGA_psdrvr.bundle/VGA_psdrvr: Mach-O executable i386
staged /build/out/i386/drvVGA/VGA.config
total 350
drwxr-xr-x  3 root  wheel    1024 Nov 28 05:22 .
drwxr-xr-x  3 root  wheel    1024 Nov 28 05:22 ..
-rw-r--r--  1 root  wheel     540 Nov 28 05:22 Default.table
-rw-r--r--  1 root  wheel     137 Nov 28 05:22 DriverInfo
drwxr-xr-x  2 root  wheel    1024 Nov 28 04:59 English.lproj
-rw-r--r--  1 root  wheel     541 Nov 28 05:22 SVGABIOS.table
-rwxr-xr-x  1 root  wheel   20908 Nov 28 05:22 VGA_psdrvr
-rw-r--r--  1 root  wheel  146724 Nov 28 05:22 VGA_reloc
=== vga done fail=0 ===
```

`make exit=2 for VGA` (the `English.copy-local-resources` packaging step,
which runs after both binaries are built — see below). Harness's own exit
line: `=== vga done fail=0 ===` (script `exit 0`), because the harness only
checks for the *existence* of `VGA_reloc` and `VGA_psdrvr`, per its header
comment: "Accept the run when both VGA_reloc and VGA_psdrvr exist, even if a
packaging rule later in the makefile exits nonzero."

### The one remaining (expected) error after both repairs

```
fastcp: '/build/source/src/drivers-i386/video/drvVGA/VGA.drvproj/English.lproj/SVGABIOS.strings' does not exist.
gnumake[1]: *** [English.copy-local-resources] Error 255
```

`VGA.drvproj/Makefile`'s `LOCAL_RESOURCES` lists `SVGABIOS.strings`
alongside `Localizable.strings`, but only `Localizable.strings` exists in
`English.lproj/`. `SVGABIOS.strings` is not created by this task — it
belongs to a later task — so this failure is expected and was left
untouched (the `PB.project` files added in this task's repair also do not
reference `SVGABIOS.strings`, for the same reason).

Compiler warnings present (none block the build): `VGAConfigTable.m:46`
implicit declaration of `strncpy`; `VGASetMode.m:33` unused variable `i`;
`VGAModes.c:24` missing braces around a struct initializer. All three are
pre-existing, in files this task's repair did not touch beyond
`VGAConfigTable.m`'s two named defects (and the `strncpy` warning in that
same file predates this repair too, on an untouched line).

### Root cause of the pre-repair failures

`VGA.drvproj/VGA.lksproj/VGAConfigTable.m` called `[self configTable]`, a
method the `VGA` class does not declare or inherit, then used C
struct-arrow syntax (`->valueForStringKey(key)`) on the (`id`-typed) result.
Fixed in commit `64bab51e` by reaching the table through
`[[self deviceDescription] configTable]` and using an ordinary Objective-C
message send, matching the idiom in `IOFrameBufferDisplay.m` and
`IOSVGADisplay.m`.

Once that was fixed, `VGA.lksproj` compiled and linked (`VGA_reloc`
produced), but the aggregate build then failed in the *second* subproject,
`VGA_psdrvr.tproj`, because none of `VGA.drvproj`, `VGA.drvproj/VGA.lksproj`,
or `VGA.drvproj/VGA_psdrvr.tproj` had a `PB.project` file — every other
driver under `src/drivers-i386` has one at each of these levels.
`bundle.make` needs `VGA_psdrvr.tproj/PB.project` to generate
`Info-nextstep.plist`. Fixed in commit `11637fc1` by adding the three
missing `PB.project` files, modeled on `drvPCIBus`'s (`.drvproj`/`.lksproj`)
and `drvEISABus`'s `PnPDump.tproj` (bundle-subproject shape).

## Step 4: copy staged artifacts back to the host

```bash
cd /d/RhapsodiOS
PW=$(grep -i '^Password=' vm/vm.conf | cut -d= -f2)
HOST=$(grep -i '^Host=' vm/vm.conf | cut -d= -f2)
mkdir -p out/i386/drvVGA
"/c/Program Files/PuTTY/pscp.exe" -batch -r -pw "$PW" root@$HOST:/build/out/i386/drvVGA/VGA.config out/i386/drvVGA/
ls -la out/i386/drvVGA/VGA.config
```

```
total 171
-rw-r--r-- 1 raynorpat 1049089    540 Jul 25 20:48 Default.table
-rw-r--r-- 1 raynorpat 1049089    137 Jul 25 20:48 DriverInfo
drwxr-xr-x 1 raynorpat 1049089      0 Jul 25 20:48 English.lproj
-rw-r--r-- 1 raynorpat 1049089    541 Jul 25 20:48 SVGABIOS.table
-rw-r--r-- 1 raynorpat 1049089  20908 Jul 25 20:48 VGA_psdrvr
-rw-r--r-- 1 raynorpat 1049089 146724 Jul 25 20:48 VGA_reloc
```

**Binary sizes:**

| Binary | Ours (unstripped) | Apple reference |
| --- | --- | --- |
| `VGA_reloc` | 146,724 bytes | 71,112 bytes |
| `VGA_psdrvr` | 20,908 bytes | 26,584 bytes |

`bundle.make` produced `VGA_psdrvr` inside a `VGA_psdrvr.bundle/` wrapper
directory on the guest (`VGA.config/VGA_psdrvr.bundle/VGA_psdrvr`), rather
than as a bare file directly under `VGA.config/` — `VGA_psdrvr.tproj`'s
`Makefile` sets `BUNDLE_EXTENSION =` (empty), so no extension is appended,
but a wrapper directory is still created. The harness's own
`find "$SRC" -name VGA_psdrvr -type f` locates the file inside that wrapper
and stages it as a bare file under `$OUT/drvVGA/VGA.config/`, which is what
was copied back to the host above. Per this task's instructions, the
Makefile was not changed to chase this.

## Step 5: parity numbers

```bash
cd /d/RhapsodiOS
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe tools/binrecon/parity_check.py \
  "C:/Users/raynorpat/Downloads/test/Drivers/i386/VGA.config/VGA_reloc" \
  out/i386/drvVGA/VGA.config/VGA_reloc
```

Exit 1. Counts:

- `missing_strings`: 29
- `missing_symbols`: 28
- `extra_strings`: 19
- `extra_symbols`: 34

```bash
PYTHONPATH=tools/binrecon ./.venv-binrecon/Scripts/python.exe tools/binrecon/parity_check.py \
  "C:/Users/raynorpat/Downloads/test/Drivers/i386/VGA.config/VGA_psdrvr" \
  out/i386/drvVGA/VGA.config/VGA_psdrvr
```

Raises `MachOFormatError`, exit 1:

```
binrecon.macho.MachOFormatError: unsupported Mach-O file type 2; expected MH_OBJECT, MH_PRELOAD or MH_BUNDLE
```

This is the exact case the task brief pre-flagged: "If the psdrvr
invocation raises `MachOFormatError`, Task 1 is incomplete — `parity_check.py`
calls `read_macho` twice per binary." Isolated which side triggers it: the
**reference** `VGA_psdrvr` reads successfully; the **rebuilt** one is Mach-O
file type 2 (`MH_EXECUTE`), which `read_macho` does not support (only
`MH_OBJECT`, `MH_PRELOAD`, `MH_BUNDLE`). `VGA_psdrvr.tproj`'s link step
(`/usr/bin/cc ... -o .../VGA_psdrvr.bundle/VGA_psdrvr ...`) does not pass a
`-bundle` flag, so the linker produced a plain executable rather than a
loadable bundle. No `.m`/`.c`/`.h`/Makefile file was changed to chase this,
per this task's scope (Step 7 repairs the *build*, not this downstream
verification-tool gap, which the brief explicitly assigns elsewhere).
Parity counts for `VGA_psdrvr` could not be recorded for this reason.

## Step 6: this baseline record

This document. `docs/drivers/drvVGA-baseline-build.md` was rewritten in its
own commit, separate from the two repair commits (`64bab51e`, `11637fc1`).
