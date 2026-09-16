#Requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:Checks = 0

function Assert-Equal($Actual, $Expected, [string]$Name) {
    $script:Checks++
    if ($Actual -ne $Expected) {
        throw "$Name`: expected [$Expected], got [$Actual]"
    }
}

function Assert-Match([string]$Actual, [string]$Pattern, [string]$Name) {
    $script:Checks++
    if ($Actual -notmatch $Pattern) {
        throw "$Name`: pattern [$Pattern] was not found"
    }
}

function Assert-NotMatch([string]$Actual, [string]$Pattern, [string]$Name) {
    $script:Checks++
    if ($Actual -match $Pattern) {
        throw "$Name`: forbidden pattern [$Pattern] was found"
    }
}

function Assert-Throws([scriptblock]$Action, [string]$Name) {
    $script:Checks++
    try {
        & $Action
    } catch {
        return
    }
    throw "$Name`: expected an exception"
}

function Assert-RemotePayloadBytes([string]$Path, [string]$ScriptBody, [string]$Name) {
    $actual = [System.IO.File]::ReadAllBytes($Path)
    $normalized = $ScriptBody.Replace("`r`n", "`n").Replace("`r", "`n").TrimEnd("`n") + "`n"
    $strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
    $expected = $strictUtf8.GetBytes($normalized)
    $hasBom = $actual.Length -ge 3 -and $actual[0] -eq 0xEF -and $actual[1] -eq 0xBB -and $actual[2] -eq 0xBF
    Assert-Equal $hasBom $false "$Name has no UTF-8 BOM"
    Assert-Equal ([Convert]::ToBase64String($actual)) ([Convert]::ToBase64String($expected)) "$Name exact strict UTF-8 bytes"
}

function Get-EncodingSignature([System.Text.Encoding]$Encoding) {
    return [pscustomobject]@{
        CodePage = $Encoding.CodePage
        WebName = $Encoding.WebName
        EncoderFallback = $Encoding.EncoderFallback.GetType().FullName
        DecoderFallback = $Encoding.DecoderFallback.GetType().FullName
        Preamble = [Convert]::ToBase64String($Encoding.GetPreamble())
    }
}

function Assert-EncodingSignature($Actual, $Expected, [string]$Name) {
    Assert-Equal $Actual.CodePage $Expected.CodePage "$Name code page"
    Assert-Equal $Actual.WebName $Expected.WebName "$Name web name"
    Assert-Equal $Actual.EncoderFallback $Expected.EncoderFallback "$Name encoder fallback"
    Assert-Equal $Actual.DecoderFallback $Expected.DecoderFallback "$Name decoder fallback"
    Assert-Equal $Actual.Preamble $Expected.Preamble "$Name preamble"
}

$VmDir = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$repoRoot = (Resolve-Path (Join-Path $VmDir '..')).Path
. (Join-Path $VmDir 'build-src-lib.ps1')
$realProfile = Get-Content -Raw (Join-Path $repoRoot 'src\rbuild-1\toolchains\gcc-darwin.conf')
$texi2htmlIndex = (& git -C $repoRoot ls-files -s -- src/CoreOSMakefiles-1/ReleaseControl/texi2html) -join "`n"
Assert-Match $texi2htmlIndex '^100755 ' 'CoreOS texi2html is tracked executable'
$ccBuildGccText = Get-Content -Raw (Join-Path $repoRoot 'src\cc-1\build_gcc')
Assert-Match $ccBuildGccText '-print-prog-name=cc1' 'cc bootstrap discovers the configured GCC backend instead of assuming a host layout'
Assert-Match $ccBuildGccText '-arch \$host -c' 'cc bootstrap compile-probes when -print-prog-name returns a basename'
Assert-Match $ccBuildGccText 'LDFLAGS="\$\{OTHER_LDFLAGS\} -undefined suppress"' 'cc fat xgcc links before System is universal'
Assert-NotMatch $ccBuildGccText 'if \[ -d /`if \[ "\$RHAPSODY" \]; then echo usr/libexec; else echo lib; fi`/\$host \]' 'cc bootstrap does not require the historical fixed compiler directory'
$ccMakefileText = Get-Content -Raw (Join-Path $repoRoot 'src\cc-1\cc\Makefile.in')
Assert-Equal ([regex]::Matches($ccMakefileText, '\$\(MAKE\).*BISON="\$\(BISON\)"').Count) 6 'cc self-bootstrap propagates configured bison through every compiler-stage submake'
$ccTopMakefileText = Get-Content -Raw (Join-Path $repoRoot 'src\cc-1\Makefile')
Assert-Match $ccTopMakefileText 'CFLAGS="-O \$\(RC_CFLAGS\) \$\(OTHER_CFLAGS\) \$\(LOCAL_CFLAGS\)"' 'cc bundled bison compiles with bootstrap LOCAL_CFLAGS'
Assert-Match $ccTopMakefileText 'LDFLAGS="\$\(RC_CFLAGS\) \$\(OTHER_LDFLAGS\) -undefined suppress' 'cc bundled bison fat-links before System is universal'
Assert-Match $ccTopMakefileText '\$\(RC_CFLAGS\) \$\(OTHER_CFLAGS\) \$\(LOCAL_CFLAGS\)"' 'cc fat bootstrap compiles with bootstrap LOCAL_CFLAGS'
$gnumakeMakefileText = Get-Content -Raw (Join-Path $repoRoot 'src\gnumake-1\Makefile')
Assert-Match $gnumakeMakefileText 'source_root="\$\(SRCROOT\)"' 'gnumake preserves its configured source root across the object-directory chdir'
Assert-Match $gnumakeMakefileText '\$\$source_root/\$\(MAKE_SRC_DIR\)/configure' 'gnumake configures from the preserved source tree'
Assert-NotMatch $gnumakeMakefileText 'PWD=`pwd`' 'gnumake does not repurpose the shell-maintained PWD variable for its source root'
$csuMakefileText = Get-Content -Raw (Join-Path $repoRoot 'src\Csu-1\Makefile')
Assert-Match $csuMakefileText '(?m)^crt1\.o:.*\$\(OBJROOT\)/dyld\.stub' 'Csu builds the dylinker stub before merging crt1'
Assert-Match $csuMakefileText '(?m)^gcrt1\.o:.*\$\(OBJROOT\)/dyld\.stub' 'Csu builds the dylinker stub before merging gcrt1'
Assert-Match $csuMakefileText '(?m)^pscrt1\.o:.*\$\(OBJROOT\)/dyld\.stub' 'Csu builds the dylinker stub before merging pscrt1'
Assert-NotMatch $csuMakefileText 'as \$\(RC_CFLAGS\)' 'Csu does not pass compiler defines to as for the dylinker stub'
Assert-Match $csuMakefileText '\$\(CC\).*\$\(SRCROOT\)/dyld_stub\.s' 'Csu assembles the dylinker stub with the C compiler driver'
Assert-Match $csuMakefileText '\$\(DSTROOT\)/usr/lib/dyld' 'Csu packages a runnable /usr/lib/dyld for chroot build roots'
Assert-Match $csuMakefileText 'findstring i386,\$\(RC_ARCHS\)' 'Csu lipos host ppc dyld with an i386 stub only when RC_ARCHS includes i386'
Assert-Match $csuMakefileText '(?s)ifneq.*findstring i386.*LIPO.*else.*usr/lib/dyld' 'thin Csu install copies host ppc dyld instead of creating a fat product'
$csuStubText = Get-Content -Raw (Join-Path $repoRoot 'src\Csu-1\dyld_stub.s')
Assert-NotMatch $csuStubText "`r" 'Csu dylinker stub uses Unix line endings'
$bootstrapManifestText = Get-Content -Raw (Join-Path $repoRoot 'src\BootstrapManifest')
Assert-Match $bootstrapManifestText '(?s)dir\s+pb_makefiles-1\s+headers.*dir\s+kernel-7\s+headers' 'pb_makefiles fragments are published before kernel header generation'
Assert-Match $bootstrapManifestText '(?s)dir\s+architecture-1\s+headers.*dir\s+Libc-1\s+headers.*dir\s+pb_makefiles-1\s+all' 'pb_makefiles tools compile after architecture and libc headers'
Assert-Match $bootstrapManifestText '(?s)dir\s+pb_makefiles-1\s+all.*dir\s+objc4-1\s+headers' 'pb_makefiles tools are built before objc4 headers need dotdotify'
Assert-Equal ([regex]::Matches($bootstrapManifestText, '(?m)^dir\s+pb_makefiles-1\s+headers\s*$').Count) 1 'pb_makefiles headers stay an early makefile-fragment pass'
Assert-Equal ([regex]::Matches($bootstrapManifestText, '(?m)^dir\s+pb_makefiles-1\s+all\s*$').Count) 1 'pb_makefiles all is scheduled once'
Assert-Match $bootstrapManifestText '(?s)dir\s+Libc-1\s+headers.*dir\s+cc-1\s+headers.*dir\s+bison-1\s+all.*dir\s+cc-1\s+all' 'libc and cc headers are replayed before bison and the full cc bootstrap'
Assert-Match $bootstrapManifestText '(?s)dir\s+machkit-1\s+headers.*dir\s+machkit-1\s+all.*dir\s+driverkit-3\s+all' 'machkit library is packaged after its headers and before driverkit'
Assert-Match $bootstrapManifestText '(?s)dir\s+architecture-1\s+headers.*dir\s+architecture-1\s+all' 'architecture headers are published before the architecture package'
Assert-Match $bootstrapManifestText '(?s)dir\s+Libstreams-1\s+all.*dir\s+objc-1\s+all' 'in-kernel objc is packaged after libstreams'
Assert-Match $bootstrapManifestText '(?s)dir\s+Csu-1\s+all.*dir\s+Libc-1\s+all.*dir\s+objc4-1\s+all.*dir\s+Libsystem-2\s+all' 'Csu and Libc are packaged before objc4 all and Libsystem'
Assert-Match $bootstrapManifestText '(?s)dir\s+Libcurses-1\s+all.*dir\s+Commands/adv_cmds\s+all.*dir\s+files-5\s+all' 'adv-cmds is packaged after libcurses and before files and later chroot consumers'
Assert-Match $bootstrapManifestText '(?s)dir\s+driverkit-3\s+all.*dir\s+kernload-1\s+all' 'kernload is packaged after driverkit'
Assert-Match $bootstrapManifestText '(?s)dir\s+Libsystem-2\s+all.*dir\s+kernload-1\s+all' 'kernload is packaged after Libsystem so fat System exists for i386 links'
$bootstrapRuntimeManifestText = Get-Content -Raw (Join-Path $repoRoot 'src\BootstrapRuntimeManifest')
Assert-NotMatch $bootstrapRuntimeManifestText '(?m)^dir\s+kernload-1\s' 'runtime walk does not link kernload before fat System'
Assert-Match $bootstrapRuntimeManifestText '(?s)dir\s+cctools-2\s+all.*dir\s+cc-1\s+all.*dir\s+Libsystem-2\s+all' 'runtime walk rebuilds fat cctools and cc before Libsystem harvests them'
Assert-Match $bootstrapManifestText '(?s)dir\s+driverkit-3\s+all.*dir\s+cctools-2\s+all.*dir\s+cc-1\s+all.*dir\s+Libsystem-2\s+all' 'full manifest rebuilds fat cctools and cc immediately before Libsystem'
Assert-Match $bootstrapManifestText '(?m)^dir\s+gnudiff-1\s+all\s*$' 'gnudiff is packaged for later kernel chroot builds'
Assert-Match $bootstrapManifestText '(?s)dir\s+Librpcsvc-1\s+headers.*dir\s+Libinfo-1\s+headers.*dir\s+Libinfo-1\s+all' 'librpcsvc and libinfo headers are published before libinfo compiles dns against netinfo/ni.h'
$driverkitLibMakefileText = Get-Content -Raw (Join-Path $repoRoot 'src\driverkit-3\libDriver\Makefile')
Assert-Match $driverkitLibMakefileText '(?m)^HEADER_ROOT=\$\(HDRROOT\)$' 'driverkit libDriver prefers HDRROOT for System.framework includes'
Assert-Match $driverkitLibMakefileText '-I\$\(HEADER_ROOT\)\$\(SYSTEM_LIBRARY_DIR\)/Frameworks/System.framework/Versions/B/Headers' 'driverkit libDriver compiles against versioned sysroot System.framework headers'
Assert-Match $driverkitLibMakefileText '-undefined suppress' 'driverkit user dylib allows unresolved System symbols until fat Libsystem exists'
Assert-Match $driverkitLibMakefileText 'OTHER_LDFLAGS' 'driverkit user dylib link uses bootstrap OTHER_LDFLAGS'
$projectCommonMakeText = Get-Content -Raw (Join-Path $repoRoot 'src\project_makefiles-1\common.make')
Assert-Match $projectCommonMakeText 'ALL_CFLAGS = .*\$\(LOCAL_CFLAGS\)' 'project_makefiles compile with bootstrap LOCAL_CFLAGS after the local -I.'
$coreosCommonMakeText = Get-Content -Raw (Join-Path $repoRoot 'src\CoreOSMakefiles-1\ReleaseControl\Common.make')
Assert-Match $coreosCommonMakeText 'Extra_CC_Flags \+= \$\(RC_CFLAGS\) \$\(LOCAL_CFLAGS\)' 'GNUSource projects compile with bootstrap LOCAL_CFLAGS'
Assert-Match $coreosCommonMakeText 'Extra_LD_Flags \+= \$\(OTHER_LDFLAGS\)' 'GNUSource projects link with bootstrap OTHER_LDFLAGS'
$projectMakefilesMakefileText = Get-Content -Raw (Join-Path $repoRoot 'src\project_makefiles-1\Makefile')
Assert-Match $projectMakefilesMakefileText '(?m)^CFLAGS = .*\$\(LOCAL_CFLAGS\)' 'project_makefiles tools compile with bootstrap LOCAL_CFLAGS'
$libcDriversPostambleText = Get-Content -Raw (Join-Path $repoRoot 'src\Libc-1\drivers.subproj\Makefile.postamble')
Assert-Match $libcDriversPostambleText '(?m)^MIG_DIR=\$\(HDRROOT\)/System/Library/Frameworks/System.framework/Versions/B/PrivateHeaders/driverkit$' 'libc Event MIG reads driverkit defs from the bootstrap sysroot'
Assert-NotMatch $libcDriversPostambleText 'MIG_DIR=/System/Library' 'libc Event MIG does not hardcode live host PrivateHeaders'
Assert-Match $libcDriversPostambleText '\$\(OFILE_DIR\)/EventUser\.o' 'libc EventUser.o target lives under OFILE_DIR'
Assert-Match $libcDriversPostambleText '-o \$\(OFILE_DIR\)/EventUser\.o' 'libc EventUser.o compile does not prefix OFILE_DIR onto \$@'
Assert-NotMatch $libcDriversPostambleText '-o \$\(OFILE_DIR\)/\$@' 'libc EventUser.o compile does not double OFILE_DIR'
$zprintPostambleText = Get-Content -Raw (Join-Path $repoRoot 'src\Commands\system_cmds\zprint.tproj\Makefile.postamble')
Assert-Match $zprintPostambleText '(?m)^MACH_DEBUG_DEFS = \$\(HDRROOT\)/System/Library/Frameworks/System.framework/Versions/B/PrivateHeaders/mach_debug/mach_debug\.defs$' 'zprint MIG reads mach_debug.defs from the bootstrap sysroot'
Assert-NotMatch $zprintPostambleText 'MACH_DEBUG_DEFS = \$\(SYSTEM_LIBRARY_DIR\)' 'zprint MIG does not hardcode live host PrivateHeaders'
$cctoolsAsMakefileText = Get-Content -Raw (Join-Path $repoRoot 'src\cctools-2\as\Makefile')
$cctoolsLdMakefileText = Get-Content -Raw (Join-Path $repoRoot 'src\cctools-2\ld\Makefile')
$cctoolsGprofMakefileText = Get-Content -Raw (Join-Path $repoRoot 'src\cctools-2\gprof\Makefile')
Assert-Match $cctoolsAsMakefileText '-I\$\(HDRROOT\)/System/Library/Frameworks/System.framework/Versions/B/PrivateHeaders' 'cctools as reads streams.h from the bootstrap sysroot'
Assert-Match $cctoolsLdMakefileText '-I\$\(HDRROOT\)/System/Library/Frameworks/System.framework/Versions/B/PrivateHeaders' 'cctools ld reads PrivateHeaders from the bootstrap sysroot'
Assert-Match $cctoolsGprofMakefileText '-I\$\(HDRROOT\)/System/Library/Frameworks/System.framework/Versions/B/PrivateHeaders' 'cctools gprof reads PrivateHeaders from the bootstrap sysroot'
Assert-NotMatch $cctoolsAsMakefileText '-I\$\(NEXT_ROOT\)/System/Library/Frameworks/System.framework/PrivateHeaders' 'cctools as does not wait for NEXT_ROOT/System.framework'
Assert-Match $cctoolsAsMakefileText '\$\(LOCAL_CFLAGS\)' 'cctools as compiles with bootstrap LOCAL_CFLAGS'
Assert-Equal ([regex]::Matches($cctoolsAsMakefileText, 'CFLAGS="-g -O[^"]*\$\(LOCAL_CFLAGS\)"').Count) 2 'cctools as driver_build recursive CFLAGS keep LOCAL_CFLAGS'
Assert-Match $cctoolsLdMakefileText '\$\(LOCAL_CFLAGS\)' 'cctools ld compiles with bootstrap LOCAL_CFLAGS'
Assert-Match $cctoolsGprofMakefileText '\$\(LOCAL_CFLAGS\)' 'cctools gprof compiles with bootstrap LOCAL_CFLAGS'
foreach ($cctoolsDir in @('ar', 'file', 'otool', 'misc', 'mkshlib', 'profileServer', 'dyld', 'libstuff', 'libmacho', 'libdyld')) {
    $cctoolsMakefileText = Get-Content -Raw (Join-Path $repoRoot ("src\cctools-2\{0}\Makefile" -f $cctoolsDir))
    Assert-Match $cctoolsMakefileText '\$\(LOCAL_CFLAGS\)' ("cctools {0} compiles with bootstrap LOCAL_CFLAGS" -f $cctoolsDir)
}
$cctoolsArMakefileText = Get-Content -Raw (Join-Path $repoRoot 'src\cctools-2\ar\Makefile')
$cctoolsFileMakefileText = Get-Content -Raw (Join-Path $repoRoot 'src\cctools-2\file\Makefile')
$cctoolsMiscMakefileText = Get-Content -Raw (Join-Path $repoRoot 'src\cctools-2\misc\Makefile')
$cctoolsMkshlibMakefileText = Get-Content -Raw (Join-Path $repoRoot 'src\cctools-2\mkshlib\Makefile')
$cctoolsProfileServerMakefileText = Get-Content -Raw (Join-Path $repoRoot 'src\cctools-2\profileServer\Makefile')
$cctoolsFatToolLink = '\$\(RC_CFLAGS\) \$\(OTHER_LDFLAGS\) -undefined suppress -o'
Assert-Match $cctoolsArMakefileText $cctoolsFatToolLink 'cctools ar fat-links before System is universal'
Assert-Match $cctoolsFileMakefileText $cctoolsFatToolLink 'cctools file fat-links before System is universal'
Assert-Match $cctoolsAsMakefileText $cctoolsFatToolLink 'cctools as fat-links before System is universal'
Assert-Match $cctoolsLdMakefileText $cctoolsFatToolLink 'cctools ld fat-links before System is universal'
Assert-Match $cctoolsGprofMakefileText $cctoolsFatToolLink 'cctools gprof fat-links before System is universal'
Assert-Match $cctoolsMiscMakefileText $cctoolsFatToolLink 'cctools misc fat-links before System is universal'
Assert-Match $cctoolsMkshlibMakefileText $cctoolsFatToolLink 'cctools mkshlib fat-links before System is universal'
Assert-Match $cctoolsProfileServerMakefileText $cctoolsFatToolLink 'cctools profileServer fat-links before System is universal'
Assert-Equal ([regex]::Matches($cctoolsArMakefileText, '-undefined suppress').Count) 1 'cctools ar only suppresses on the executable link'
Assert-Equal ([regex]::Matches($cctoolsAsMakefileText, '-undefined suppress').Count) 2 'cctools as suppresses driver and as, not relocatable -r'
$kernloadKernservMakefileText = Get-Content -Raw (Join-Path $repoRoot 'src\kernload-1\include\kernserv\Makefile')
$kernloadLibMakefileText = Get-Content -Raw (Join-Path $repoRoot 'src\kernload-1\libkernload\Makefile')
Assert-Equal ([regex]::Matches($kernloadKernservMakefileText, '(?m)^install:').Count) 1 'kernserv headers have one install target'
Assert-Match $kernloadKernservMakefileText 'MIG_GENERATED_INSTALL' 'kernserv install publishes MIG-generated headers'
Assert-Match $kernloadLibMakefileText '-I\$\{SYMROOT\}/include' 'libkernload compiles against SYMROOT-generated kernserv headers'
Assert-Match $kernloadLibMakefileText '\$\{LOCAL_CFLAGS\}' 'libkernload compiles with bootstrap LOCAL_CFLAGS'
$kernloadLoaderMakefileText = Get-Content -Raw (Join-Path $repoRoot 'src\kernload-1\kern_loader\Makefile')
$kernloadLoadedServerMakefileText = Get-Content -Raw (Join-Path $repoRoot 'src\kernload-1\loaded_server\Makefile')
$kernloadKlLogMakefileText = Get-Content -Raw (Join-Path $repoRoot 'src\kernload-1\cmds\kl_log\Makefile')
$kernloadKlUtilMakefileText = Get-Content -Raw (Join-Path $repoRoot 'src\kernload-1\cmds\kl_util\Makefile')
Assert-Match $kernloadLoaderMakefileText '\$\{LOCAL_CFLAGS\}' 'kern_loader compiles with bootstrap LOCAL_CFLAGS'
Assert-Match $kernloadLoadedServerMakefileText '\$\{LOCAL_CFLAGS\}' 'loaded_server compiles with bootstrap LOCAL_CFLAGS'
Assert-Match $kernloadLoadedServerMakefileText "CFLAGS=-static.*LOCAL_CFLAGS" 'loaded_server generated MIG compile uses bootstrap LOCAL_CFLAGS'
Assert-Match $kernloadLoadedServerMakefileText '(?m)^Makefile\.gen:.*Makefile' 'loaded_server regenerates Makefile.gen when the parent Makefile changes'
Assert-Match $kernloadKlLogMakefileText '\$\{LOCAL_CFLAGS\}' 'kl_log compiles with bootstrap LOCAL_CFLAGS'
Assert-Match $kernloadKlUtilMakefileText '\$\{LOCAL_CFLAGS\}' 'kl_util compiles with bootstrap LOCAL_CFLAGS'
$iondrvHeaderText = Get-Content -Raw (Join-Path $repoRoot 'src\driverkit-3\libDriver\ppc\IONDRVFramebuffer.h')
$iondrvImplText = Get-Content -Raw (Join-Path $repoRoot 'src\driverkit-3\libDriver\ppc\IONDRVFramebuffer.m')
Assert-Match $iondrvHeaderText '(?s)@interface IOATIMACH64NDRV:IOATINDRV\s*\{[^}]*engineInitialized' 'Mach64 NDRV declares engineInitialized in the class interface'
Assert-NotMatch $iondrvImplText '@implementation IOATIMACH64NDRV\s*\{' 'Mach64 NDRV does not redeclare ivars in @implementation'
Assert-NotMatch $iondrvImplText 'config\.mode' 'NDRV acceleration uses IOFBConfiguration.displayMode'
Assert-Match $iondrvHeaderText '(?s)@interface IOIX3DNDRV:IONDRVFramebuffer\s*\{[^}]*@public[^}]*registerBase' 'TwinTurbo interrupt handler can see NDRV registerBase'
Assert-Match $iondrvImplText 'getPixelInformationForDisplayMode:modeID andDepthIndex:depthIndex' 'NDRV acceleration uses the IOFramebuffer pixel-info selector'
$pexpertGestaltText = Get-Content -Raw (Join-Path $repoRoot 'src\drivers-ppc\bus\drvPExpert\powermac\powermac_gestalt.h')
Assert-Match $pexpertGestaltText 'gestaltSawtooth\s*=\s*1000' 'PExpert gestalt table includes NewWorld Sawtooth machines'
$libcMachPreambleText = Get-Content -Raw (Join-Path $repoRoot 'src\Libc-1\mach.subproj\Makefile.preamble')
$libsystemMakeText = Get-Content -Raw (Join-Path $repoRoot 'src\Libsystem-2\Makefile')
$libsystemPostambleText = Get-Content -Raw (Join-Path $repoRoot 'src\Libsystem-2\Makefile.postamble')
Assert-NotMatch $libsystemMakeText 'System\.order\.\$\(TARGET_ARCH\)' 'Libsystem does not bind a single TARGET_ARCH order file at parse time'
Assert-Match $libsystemPostambleText 'TARGET_ARCHS' 'Libsystem harvest links iterate TARGET_ARCHS'
Assert-Match $libsystemPostambleText 'LINK_ARCHS = \$\(TARGET_ARCH\)' 'empty TARGET_ARCHS falls back to project_makefiles TARGET_ARCH'
Assert-Match $libsystemPostambleText 'for arch in \$\(LINK_ARCHS\)' 'make_links iterates LINK_ARCHS so a per-arch recurse still harvests'
Assert-Match $libsystemPostambleText 'foreach A,\$\(LINK_ARCHS\)' 'sectorder uses LINK_ARCHS instead of empty TARGET_ARCHS'
Assert-NotMatch $libsystemPostambleText 'for arch in \$\(TARGET_ARCHS\); do' 'make_links does not iterate possibly-empty TARGET_ARCHS'
Assert-Match $libsystemPostambleText 'after_install::' 'Libsystem installs compatibility dylibs after System.framework'
Assert-Match $libsystemPostambleText 'usr/lib/\$\$lib\.dylib' 'Libsystem compatibility dylibs live in /usr/lib'
Assert-Match $libsystemPostambleText 'libkvm' 'Libsystem publishes libkvm.dylib as a System.framework compatibility link'
Assert-NotMatch $libsystemPostambleText 'libcompat' 'Libsystem does not alias unharvested libcompat onto System.framework'
$nvramPostambleText = Get-Content -Raw (Join-Path $repoRoot 'src\Commands\system_cmds\nvram.tproj\Makefile.postamble')
$fbalertSourceText = Get-Content -Raw (Join-Path $repoRoot 'src\Commands\system_cmds\fbalert.tproj\fbalert.c')
Assert-Match $nvramPostambleText '\$\(LN\) -f PowerSurge' 'nvram machine aliases force-replace so bootstrap resume does not fail with File exists'
Assert-NotMatch $nvramPostambleText '\$\(LN\) -s ' 'nvram does not pass extra -s; bootstrap LN is already /bin/ln -s'
Assert-Match $fbalertSourceText '#include <bsd/dev/kmreg_com.h>' 'fbalert includes kmreg_com.h from System PrivateHeaders/bsd'
Assert-NotMatch $fbalertSourceText '#include <dev/kmreg_com.h>' 'fbalert does not use the kernel-relative kmreg_com.h path'
Assert-NotMatch $libsystemPostambleText '\$\(LN\) \$\$name/\$\$\{obj_dir\}_obj/\$\$name\.ofileList' 'Libsystem ofileList symlink is not cwd-relative (dangling with ln -s)'
Assert-Match $libcMachPreambleText 'override\s+MIG\s*=\s*\$\(CONFIG_DIR\)/mig' 'libc Mach headers override inherited host MIG with the configured private tool'
Assert-Match $libcMachPreambleText 'MIGFLAGS\s*=\s*\$\(RC_CFLAGS\)\s+\$\(LOCAL_CFLAGS\)' 'libc Mach MIG preprocessing uses isolated RC flags and bootstrap LOCAL_CFLAGS includes'
$libcPostambleText = Get-Content -Raw (Join-Path $repoRoot 'src\Libc-1\Makefile.postamble')
Assert-Match $libcPostambleText '\$\(LIPO\) -create' 'Libc lipos per-arch static archives before installing libc_static.a'
Assert-Match $libcPostambleText '\$\(RM\) -f \$\(SYMROOT\)/libc_static\.a' 'Libc breaks the last-arch hardlink before lipo of libc_static.a'
Assert-Match $libcPostambleText 'libc\.\$\$\{arch\}_static\.a' 'Libc finds per-arch static archives as libc.<arch>_static.a'
Assert-Match $libcPostambleText 'count -gt 1' 'Libc only lipos libc_static.a when more than one architecture archive exists'

$buildScriptText = Get-Content -Raw (Join-Path $VmDir 'build-src.ps1')
$remoteScriptText = Get-Content -Raw (Join-Path $VmDir 'rhap-remote.ps1')
$migWrapperText = Get-Content -Raw (Join-Path $repoRoot 'src\Commands\bootstrap_cmds\migcom.tproj\mig.sh')
$classicErrorText = Get-Content -Raw (Join-Path $repoRoot 'src\Commands\bootstrap_cmds\migcom.tproj\error.c')
$classicErrorHeaderText = Get-Content -Raw (Join-Path $repoRoot 'src\Commands\bootstrap_cmds\migcom.tproj\error.h')
$classicUtilsText = Get-Content -Raw (Join-Path $repoRoot 'src\Commands\bootstrap_cmds\migcom.tproj\utils.c')
$typedErrorText = Get-Content -Raw (Join-Path $repoRoot 'src\Commands\bootstrap_cmds\migcom_typd.tproj\error.c')
$typedErrorHeaderText = Get-Content -Raw (Join-Path $repoRoot 'src\Commands\bootstrap_cmds\migcom_typd.tproj\error.h')
$kernelMakeTemplateText = Get-Content -Raw (Join-Path $repoRoot 'src\kernel-7\conf\Makefile.template')
$pkginfoSourceText = Get-Content -Raw (Join-Path $repoRoot 'src\rbuild-1\pkginfo.c')
$apkSourceText = Get-Content -Raw (Join-Path $repoRoot 'src\rbuild-1\apk.c')
$apkTestSourceText = Get-Content -Raw (Join-Path $repoRoot 'src\rbuild-1\tests\test_apk.c')
$builderSourceText = Get-Content -Raw (Join-Path $repoRoot 'src\rbuild-1\builder.c')
$productsSourceText = Get-Content -Raw (Join-Path $repoRoot 'src\rbuild-1\products.c')
$rbuildMainText = Get-Content -Raw (Join-Path $repoRoot 'src\rbuild-1\main.c')
$rbuildKernelText = Get-Content -Raw (Join-Path $repoRoot 'src\rbuild-1\kernel.c')
$rbuildRunnerText = Get-Content -Raw (Join-Path $repoRoot 'src\rbuild-1\runner.c')
$rbuildMakefileText = Get-Content -Raw (Join-Path $repoRoot 'src\rbuild-1\Makefile')
$rbuildBlacklistPath = Join-Path $repoRoot 'src\rbuild-1\kernel-drivers-blacklist.json'
$rbuildBlacklistText = Get-Content -Raw $rbuildBlacklistPath
$paxGnutarText = Get-Content -Raw (Join-Path $repoRoot 'src\rbuild-1\pax-gnutar.sh')
$bootstrapResumeText = Get-Content -Raw (Join-Path $repoRoot 'src\rbuild-1\tests\bootstrap-resume.sh')
$decommentSourcePath = Join-Path $repoRoot 'src\Commands\bootstrap_cmds\decomment.tproj\decomment.c'
$decommentSourceText = Get-Content -Raw $decommentSourcePath
Assert-Match $migWrapperText 'MIGCC' 'MIG wrapper supports configured compiler override'
Assert-Match $migWrapperText 'MIGARCH' 'MIG wrapper supports configured architecture override'
Assert-Match $migWrapperText 'append_cppflag "-D\$mig_arch"' 'configured GCC receives one preserved architecture definition'
Assert-Match $migWrapperText 'mig_arch=\$\{MIGARCH-\}' 'configured architecture begins only from MIGARCH'
Assert-Match $migWrapperText 'arch=\$2; mig_arch=\$2' 'explicit -arch overrides both configured and historical architecture state'
Assert-Match $migWrapperText 'MIGCOM_DIR' 'MIG wrapper supports private libexec override'
Assert-Match $migWrapperText '-i[ `t]+\)' 'MIG wrapper forwards -i and its argument'
Assert-Match $migWrapperText '(?s)-i[ `t]+\)[^\r\n]*shift;.*?case \$1 in' 'MIG wrapper classifies optional -i operand with a portable case test'
Assert-Match $migWrapperText '(?s)-i[ `t]+\)[^\r\n]*.*?case \$1 in[\r\n\t ]*-\* \)' 'MIG wrapper does not consume a following option as the -i prefix'
Assert-NotMatch $migWrapperText '\$\{1#-\}' 'MIG wrapper avoids quoted prefix stripping that Rhapsody ash ignores'
Assert-Match $migWrapperText 'MIGCOM_ROOT/migcom_typd' 'MIG wrapper selects typed compiler below configured libexec'
Assert-Match $migWrapperText 'MIGCOM_DIR-/usr/libexec' 'MIG wrapper preserves packaged target libexec default'
Assert-Match $migWrapperText '"\$MIGCC" -E -x c -traditional-cpp' 'configured GCC forces C preprocessing for defs inputs while preserving historical semantics'
Assert-Match $migWrapperText '"\$MIGCC" -E -x c -traditional-cpp[^\r\n]*"\$file"' 'configured GCC wrapper exercise accepts a defs filename as its single input'
Assert-Match $migWrapperText '"\$CPP" \$cppflags "\$file" -' 'default compiler branch preserves historical cpp invocation'
Assert-Match $migWrapperText 'IFS=\$newline' 'MIG wrapper splits only its newline-delimited argument lists'
Assert-Match $migWrapperText '(?m)^set -f$' 'MIG wrapper disables pathname expansion for controlled argument expansion'
Assert-Match $migWrapperText 'argument contains a newline' 'MIG wrapper rejects unrepresentable newline arguments'
Assert-NotMatch $migWrapperText '(?m)^\s*"?\$MIGCC"?[^\r\n]*"\$file"\s+-' 'configured GCC receives one input and writes preprocessed output to stdout'
Assert-Match $migWrapperText '"\$migcom" \$migflags < "\$mig_tmp"' 'MIG wrapper preserves spaces in private libexec path and consumes staged preprocessing'
Assert-Match $migWrapperText 'MIGCPP-' 'MIG wrapper supports an optional compatibility cpp override'
Assert-Match $migWrapperText '/usr/libexec/\$\{arch-' 'MIG wrapper preserves architecture-specific historical cpp default'
Assert-Match $migWrapperText 'trap finish 0' 'MIG wrapper cleans staged preprocessing on every exit'
Assert-Match $migWrapperText '(?s)mig_tmp_candidate=.*?if mkdir "\$mig_tmp_candidate".*?mig_tmp_dir=\$mig_tmp_candidate' 'MIG wrapper claims staging ownership only after atomic directory creation'
Assert-Match $migWrapperText 'rm -f "\$mig_tmp_dir/input"[\r\n]+\s*rmdir "\$mig_tmp_dir"' 'MIG wrapper cleans only its fixed file and owned directory non-recursively'
Assert-NotMatch $migWrapperText 'rm -rf[^\r\n]*mig_tmp|test -e "\$mig_tmp_candidate"' 'MIG wrapper never recursively removes or prechecks an unowned staging candidate'
Assert-Match $migWrapperText '(?s)trap ''{2} 1 2 3 15.*?mkdir "\$mig_tmp_candidate".*?mig_tmp_dir=\$mig_tmp_candidate.*?trap ''exit 1'' 1 2 3 15' 'MIG wrapper ignores cleanup signals only through atomic ownership assignment'
Assert-Match $migWrapperText '(?s)else[\r\n\s]+trap ''exit 1'' 1 2 3 15[\r\n\s]+echo "mig: could not create private preprocessor staging directory' 'MIG wrapper restores signal handlers when staging mkdir fails'
Assert-Match $migWrapperText '(?s)finish\(\).*?trap - 0 1 2 3 15.*?cleanup' 'MIG wrapper disables every trap before exit cleanup'
Assert-Match $migWrapperText '-sheader[ `t]+\)[^\r\n]*append_migflag "\$1"; append_migflag "\$2"' 'MIG wrapper forwards server-header output to backend'
Assert-Match $migWrapperText '-handler[ `t]+\)[^\r\n]*append_migflag "\$1"; append_migflag "\$2"' 'MIG wrapper forwards handler output to backend'
Assert-NotMatch $migWrapperText 'NEXT_ROOT' 'MIG wrapper never derives compiler location from a sysroot'
Assert-Match $classicErrorText '#include <stdarg\.h>' 'classic MIG errors use GCC-compatible standard varargs'
Assert-Match $classicUtilsText '#include <stdarg\.h>' 'classic MIG writers use GCC-compatible standard varargs'
Assert-Equal ([regex]::Matches($classicUtilsText, '#include <stdarg\.h>').Count) 1 'classic MIG writers include standard varargs once'
Assert-NotMatch ($classicErrorText + $classicUtilsText) '<varargs\.h>|\bva_dcl\b|va_start\([^,\r\n]+\)' 'classic MIG has no obsolete varargs interface'
Assert-Match $classicErrorText 'strerror\(error_num\)' 'classic MIG uses the host-supported error string interface'
Assert-NotMatch $classicErrorHeaderText '<mach/mach_error\.h>' 'classic MIG does not import an unused live-only Mach error header'
Assert-Match $typedErrorText 'strerror\(error_num\)' 'typed MIG uses the host-supported error string interface'
Assert-NotMatch ($classicErrorText + $typedErrorText + $typedErrorHeaderText) '(?m)^\s*extern[^\r\n]*\b(sys_nerr|sys_errlist)\b|\b(sys_nerr|sys_errlist)\s*\[' 'private MIG sources do not depend on obsolete libc error tables'
Assert-Match $kernelMakeTemplateText '(?ms)^ifndef DECOMMENT\s*\nDECOMMENT = /usr/local/bin/decomment\s*\nendif' 'kernel decomment default is GNU make 3.74-legal and env-overrideable'
Assert-NotMatch $kernelMakeTemplateText 'DECOMMENT \?=' 'kernel decomment default does not use GNU make 3.77 \?='
Assert-NotMatch $kernelMakeTemplateText '(?m)^\s*@-for i in (?:\$\{EXPORT\}|`echo \$\{MACHINE_EXPORT\}`)' 'kernel header export recipes do not ignore loop failure'
Assert-Equal ([regex]::Matches($kernelMakeTemplateText, 'unifdef_status=0;').Count) 2 'both kernel export loops start unifdef status at zero under sh -ce'
Assert-Equal ([regex]::Matches($kernelMakeTemplateText, '\|\| unifdef_status=\$\$\?;').Count) 2 'both kernel export loops survive GNU make sh -ce when unifdef reports changes'
Assert-NotMatch $kernelMakeTemplateText '\$\(UNIFDEF\)[^\r\n]*>(?:\\\r?\n\s*)?"\$\$EXPDIR/\$\$j";' 'unifdef is not a bare set -e command before status capture'
Assert-Equal ([regex]::Matches($kernelMakeTemplateText, '\[ \$\$unifdef_status -eq 1 \]').Count) 2 'both kernel export loops reserve decomment fallback for unifdef status one'
Assert-Equal ([regex]::Matches($kernelMakeTemplateText, '\[ \$\$unifdef_status -ne 0 \]').Count) 2 'both kernel export loops reject unexpected unifdef failure'
Assert-Equal ([regex]::Matches($kernelMakeTemplateText, 'object_dir=`pwd` \|\| exit 1;').Count) 2 'both kernel export loops reject failed object directory capture'
Assert-Equal ([regex]::Matches($kernelMakeTemplateText, 'EXPDIR="\$\$object_dir/exports";').Count) 2 'both kernel export loops preserve the guarded object directory'
Assert-Equal ([regex]::Matches($kernelMakeTemplateText, '\(cd "\$\(SOURCE_DIR\)/\$\$i" \|\| exit 1;').Count) 2 'both kernel export loops quote and guard source directory changes'
Assert-Equal ([regex]::Matches($kernelMakeTemplateText, 'DSTDIR="\$\(DSTROOT\)\$\(INCDIR\)/\$\$i";').Count) 2 'both kernel export loops preserve space-containing destination paths'
Assert-Equal ([regex]::Matches($kernelMakeTemplateText, '"\$\(DECOMMENT\)" "\$\$EXPDIR/\$\$j"  r >\s*(?:\\\r?\n\s*)?"\$\$EXPDIR/\$\$j\.strip" \|\| exit 1;').Count) 2 'both kernel export loops quote and hard-fail the decomment fallback'
Assert-Equal ([regex]::Matches($kernelMakeTemplateText, '\[ -d "\$\$EXPDIR" \] \|\| \$\(MKDIRS\) "\$\$EXPDIR" \|\| exit 1;').Count) 2 'both kernel export loops reject export directory creation failure'
Assert-Equal ([regex]::Matches($kernelMakeTemplateText, '\[ -d "\$\$DSTDIR" \] \|\| \$\(MKDIRS\) "\$\$DSTDIR" \|\| exit 1;').Count) 2 'both kernel export loops reject destination directory creation failure'
Assert-Equal ([regex]::Matches($kernelMakeTemplateText, 'rm -f "\$\$EXPDIR"/\* \|\| exit 1;').Count) 2 'both kernel export loops reject export cleanup failure'
Assert-Equal ([regex]::Matches($kernelMakeTemplateText, 'echo garbage > "\$\$EXPDIR/\$\$j\.strip" \|\| exit 1;').Count) 2 'both kernel export loops reject sentinel write failure'
Assert-Equal ([regex]::Matches($kernelMakeTemplateText, '"\$\$j" > "\$\$EXPDIR/\$\$j"').Count) 2 'both kernel export loops quote unifdef header paths and output'
Assert-Equal ([regex]::Matches($kernelMakeTemplateText, '\[ -s "\$\$EXPDIR/\$\$j\.strip" \]').Count) 2 'both kernel export loops quote exported-header probes'
Assert-Equal ([regex]::Matches($kernelMakeTemplateText, 'cd "\$\$EXPDIR" \|\| exit 1;').Count) 2 'both kernel export loops quote and guard export directory changes'
Assert-Equal ([regex]::Matches($kernelMakeTemplateText, 'install \$\(INSTALL_FLAGS\) "\$\$j" "\$\$DSTDIR";').Count) 2 'both kernel export loops quote install source and destination paths'
Assert-Equal ([regex]::Matches($kernelMakeTemplateText, 'rm -f "\$\$EXPDIR/\$\$j\.strip" \|\| exit 1;').Count) 2 'both kernel export loops reject normal probe cleanup failure'
Assert-Equal ([regex]::Matches($kernelMakeTemplateText, 'install_status=\$\$\?;').Count) 2 'both kernel export loops capture install status immediately'
Assert-Equal ([regex]::Matches($kernelMakeTemplateText, 'if \[ \$\$install_status -ne 0 \]; then[\s\S]*?rm -f "\$\$EXPDIR/\$\$j\.strip";[\s\S]*?exit 1;').Count) 2 'both kernel export loops clean probes without masking install failure'
Assert-Equal ([regex]::Matches($kernelMakeTemplateText, '\) \|\| exit 1;\s*\\\r?\n\s*done').Count) 2 'both kernel export loops propagate header-directory subshell failure'
Assert-Match $pkginfoSourceText 'tc->archive_create' 'configured APK creation selects the generic archive creator'
Assert-Match $pkginfoSourceText 'tc->archive_create_flags' 'configured APK creation expands generic creator flags'
Assert-Match $pkginfoSourceText 'archive_cwd != 0 && chdir\(archive_cwd\) != 0' 'configured archive child enters the package root'
Assert-NotMatch $pkginfoSourceText 'tc->tar_create_flags' 'APK creation has no tar-specific configured flags'
foreach ($apkCase in @(
    [pscustomobject]@{ Name = 'apk.c'; Text = $apkSourceText },
    [pscustomobject]@{ Name = 'test_apk.c'; Text = $apkTestSourceText }
)) {
    $typesIdx = $apkCase.Text.IndexOf('#include <sys/types.h>')
    $direntIdx = $apkCase.Text.IndexOf('#include <dirent.h>')
    Assert-Equal ($typesIdx -ge 0) $true "$($apkCase.Name) includes sys/types.h"
    Assert-Equal ($direntIdx -ge 0) $true "$($apkCase.Name) includes dirent.h"
    Assert-Equal ($typesIdx -lt $direntIdx) $true "$($apkCase.Name) includes sys/types.h before dirent.h"
}
Assert-Match $builderSourceText 'ReleaseControl/Common.make' 'bootstrap waits for CoreOS Common.make before CoreOSMakefiles='
Assert-Match $builderSourceText 'rmtree_dir\(params->SYMROOT\)' 'must_build wipes leftover SYMROOT before rsync and probes'
Assert-Match $builderSourceText 'rmtree_dir\(params->OBJROOT\)' 'must_build wipes leftover OBJROOT before rsync and probes'
Assert-Match $rbuildMainText 'rbuild kernel \[--state DIR\] --arch ARCH' 'rbuild usage includes kernel'
Assert-Match $rbuildMainText 'rbuild kerneldrivers \[--state DIR\] --arch ARCH' 'rbuild usage includes kerneldrivers'
Assert-Match $rbuildMainText 'strcmp\(sub, "kernel"\)' 'rbuild dispatches kernel'
Assert-Match $rbuildMainText 'strcmp\(sub, "kerneldrivers"\)' 'rbuild dispatches kerneldrivers'
Assert-Match $rbuildKernelText 'driverkit-3' 'kernel core starts at driverkit'
Assert-Match $rbuildKernelText 'drivers-"' 'kernel core interpolates the selected architecture into PExpert'
Assert-Match $rbuildKernelText 'kernel-7' 'kernel core ends at kernel-7'
Assert-Match $rbuildKernelText 'drvBPF' 'kerneldrivers includes extra BPF project'
Assert-Match $rbuildKernelText 'drvPortServer' 'kerneldrivers includes extra PortServer project'
Assert-Match $rbuildKernelText 'drvSCSIServer' 'kerneldrivers includes extra SCSIServer project'
Assert-Match $rbuildKernelText 'drvSCSITape' 'kerneldrivers includes extra SCSITape project'
Assert-Match $rbuildKernelText 'drvPExpert' 'kerneldrivers skips the platform expert already built by kernel'
Assert-Match $rbuildRunnerText 'runner_kernel\(' 'runner exposes kernel'
Assert-Match $rbuildRunnerText 'runner_kerneldrivers\(' 'runner exposes kerneldrivers'
Assert-Match $rbuildRunnerText 'KERNEL_DRIVERS_BLACKLIST_REL' 'kerneldrivers loads the checked-in driver blacklist'
Assert-Match $rbuildRunnerText 'kernel_load_blacklist' 'kerneldrivers applies the JSON blacklist'
Assert-Match $rbuildRunnerText 'rbuild: skip ' 'kerneldrivers reports each skipped WIP driver'
Assert-Match $rbuildBlacklistText '"skip"' 'kernel driver blacklist is a JSON skip list'
Assert-Match $rbuildBlacklistText 'drivers-ppc/ide/drvPPCSwimFloppy' 'blacklist includes unfinished ppc floppy reconstruction'
Assert-Match $rbuildBlacklistText 'drivers-ppc/input/drvIOADBDevice' 'blacklist includes unfinished ppc ADB reconstruction'
Assert-Match $rbuildBlacklistText 'drivers-i386/ide/drvEIDE' 'blacklist includes unfinished i386 EIDE work'
Assert-Match $rbuildBlacklistText 'drivers-i386/sound/drvIntelAC97Sound' 'blacklist includes unfinished AC97 reconstruction'
Assert-Match $rbuildBlacklistText 'drivers-i386/scsi/drvAdaptec6X60' 'blacklist includes unfinished i386 SCSI reconstruction'
Assert-Match $rbuildBlacklistText '"drvBPF"' 'blacklist includes unfinished BPF reconstruction'
Assert-Match $rbuildBlacklistText '"drvSCSIServer"' 'blacklist includes unfinished SCSIServer reconstruction'
Assert-NotMatch $rbuildBlacklistText 'drvPPCOHare' 'working ppc OHare is not blacklisted'
Assert-NotMatch $rbuildBlacklistText 'drvPPCBMac' 'working ppc BMac is not blacklisted'
Assert-NotMatch $rbuildBlacklistText 'drvPPCDec21040' 'working ppc Dec21040 is not blacklisted'
Assert-NotMatch $rbuildBlacklistText 'drvPExpert' 'platform expert is a kernel-core package, not a blacklist entry'
Assert-Match $rbuildRunnerText '(?s)int runner_buildpackage.*?opt\.clean = 1' 'standalone buildpackage removes package chroots'
Assert-Match $rbuildMakefileText 'kernel\.o' 'rbuild links the kernel module'
Assert-Match $rbuildMakefileText 'tests/test_kernel' 'rbuild runs kernel unit tests'
Assert-Match $builderSourceText 'access\(coreos_common, F_OK\)' 'bootstrap probes CoreOS Common.make in the sysroot'
Assert-Match $builderSourceText 'cpp_flags_ready' 'bootstrap waits for compiler headers before isolated -nostdinc'
Assert-Match $builderSourceText 'push_kv\(out, "HDRROOT", opt->sysroot\)' 'bootstrap make uses the target sysroot as HDRROOT'
Assert-Match $builderSourceText 'str_cats\(\s*opt->sysroot, "/usr/local/lib/objs"' 'bootstrap SUBLIBROOTS points at harvested objects in the sysroot'
Assert-Match $builderSourceText 'architecture_cflags\(effective\)' 'universal bootstrap RC_CFLAGS uses both -arch flags, not the profile arch_flags'
Assert-Match $builderSourceText 'apk_use_arch\(path, 0, tc, name, version, required, objects, 1\)' 'bootstrap cache reuse accepts a covering architecture'
Assert-Match $builderSourceText 'products_validate\(root, required, objects, objects\)' 'object harvest allows extra CPU coverage in directory buckets'
Assert-Match $rbuildRunnerText 'architecture_covers' 'thin bootstrap reuses state whose architecture covers the requested CPU'
Assert-Match $productsSourceText 'i386\.subproj' 'object harvest treats Project Builder i386.subproj as an i386 CPU bucket'
Assert-Match $productsSourceText 'allow_superset \|\| v\.objects' 'object collections accept extra CPU coverage'
Assert-Match $productsSourceText '\(mask & bucket\) != bucket' 'directory buckets accept fat objects that still cover the bucket CPU'
$libsystemPostambleText = Get-Content -Raw (Join-Path $repoRoot 'src\Libsystem-2\Makefile.postamble')
Assert-Match $libsystemPostambleText '\$\(SYMROOT\)/libsystem-links/\$\(BUILD_TARGET\)/\$\(TARGET_ARCH\)' 'Libsystem make_links staging is per-arch so ppc does not reuse i386 object links'
Assert-NotMatch $libsystemPostambleText '\$\(OFILE_DIR\)/links' 'Libsystem make_links does not harvest foreign-arch objects under OFILE_DIR'
Assert-NotMatch $libsystemPostambleText '\$\(OBJROOT\)/libsystem-links' 'Libsystem make_links is not under OBJROOT harvest'
Assert-Match $builderSourceText 'builder_relativize_symlinks\(dstroot\)' 'APK packaging rewrites DSTROOT absolute aliases to relative symlinks'
Assert-Match $builderSourceText '-Wl,-syslibroot,' 'bootstrap rewrites syslibroot linker flags for Rhapsody ld'
Assert-Match $builderSourceText 'str_cats\("-L", root, "/usr/local/lib"' 'bootstrap linker search includes sysroot /usr/local/lib for libcompat.a'
Assert-Match $builderSourceText '/usr/local/bin/indr' 'bootstrap selects sysroot indr for Csu after cctools'
Assert-NotMatch $bootstrapResumeText 'mktemp' 'bootstrap-resume creates temps without mktemp'
Assert-Match $bootstrapResumeText 'umask 077 && mkdir' 'bootstrap-resume claims a private temp directory atomically'
Assert-Match $bootstrapResumeText '(?m)^make=/bin/make$' 'bootstrap-resume fixture make exists on Rhapsody'
foreach ($header in @('stdio.h', 'ctype.h', 'fcntl.h', 'stdlib.h', 'unistd.h')) {
    Assert-Match $decommentSourceText ("#include <{0}>" -f [regex]::Escape($header)) "decomment declares precise $header dependency"
}
Assert-NotMatch $decommentSourceText '#import|bsd/libc\.h' 'decomment has no obsolete umbrella or import directive'
Assert-Match $decommentSourceText 'if\(fd < 0\)' 'decomment accepts descriptor zero from open'
Assert-NotMatch $decommentSourceText 'if\(fd <= 0\)' 'decomment does not reject descriptor zero'
Assert-Equal ([regex]::Matches($decommentSourceText, 'isspace\(\(unsigned char\)bufchar\)').Count) 2 'decomment passes unsigned bytes to ctype'

$decommentRuntimeDir = Join-Path $env:TEMP ("rhap-decomment-runtime-{0}" -f [guid]::NewGuid().ToString('n'))
New-Item -ItemType Directory -Path $decommentRuntimeDir | Out-Null
try {
    $clangCommand = Get-Command clang.exe -ErrorAction SilentlyContinue
    $clang = if ($null -eq $clangCommand) { $null } else { $clangCommand.Source }
    if ([string]::IsNullOrWhiteSpace($clang)) {
        $clang = Join-Path $env:ProgramFiles 'LLVM\bin\clang.exe'
    }
    Assert-Equal (Test-Path -LiteralPath $clang -PathType Leaf) $true 'LLVM compiler is available for decomment runtime contract'
    $unistd = Join-Path $decommentRuntimeDir 'unistd.h'
    $runnerSource = Join-Path $decommentRuntimeDir 'fd0-runner.c'
    $decommentExe = Join-Path $decommentRuntimeDir 'decomment.exe'
    $runnerExe = Join-Path $decommentRuntimeDir 'fd0-runner.exe'
    $input = Join-Path $decommentRuntimeDir 'input.h'
    Set-Content -LiteralPath $unistd -Encoding ASCII -Value @(
        '#include <io.h>',
        '#define read _read'
    )
    Set-Content -LiteralPath $runnerSource -Encoding ASCII -Value @(
        '#include <io.h>',
        '#include <process.h>',
        'int main(int argc, char **argv) {',
        '    if (argc != 3 || _close(0) != 0) return 125;',
        '    return _spawnl(_P_WAIT, argv[1], argv[1], argv[2], "r", (char *)0);',
        '}'
    )
    Set-Content -LiteralPath $input -Encoding ASCII -Value @(
        'alpha /* block */ beta // line',
        ' gamma'
    )
    & $clang -std=c89 -Wall -Wextra -Werror -Wno-deprecated-declarations `
        -I $decommentRuntimeDir -Dopen=_open -o $decommentExe $decommentSourcePath
    Assert-Equal $LASTEXITCODE 0 'LLVM compiles decomment with precise headers'
    & $clang -std=c89 -Wall -Wextra -Werror -Wno-deprecated-declarations `
        -o $runnerExe $runnerSource
    Assert-Equal $LASTEXITCODE 0 'LLVM compiles descriptor-zero decomment runner'
    $normalOutput = (& $decommentExe $input r) -join "`n"
    Assert-Equal $LASTEXITCODE 0 'decomment runtime fixture succeeds normally'
    Assert-Equal $normalOutput 'alphabetagamma' 'decomment strips block, line, and whitespace comments'
    $fdZeroOutput = (& $runnerExe $decommentExe $input) -join "`n"
    Assert-Equal $LASTEXITCODE 0 'decomment accepts its input file as descriptor zero'
    Assert-Equal $fdZeroOutput 'alphabetagamma' 'descriptor-zero decomment preserves scanner behavior'
} finally {
    Remove-Item -LiteralPath $decommentRuntimeDir -Recurse -Force -ErrorAction SilentlyContinue
}
Assert-Match $buildScriptText '(?s)param\(\s*\[switch\]\$All,\s*\[switch\]\$Rbuild,\s*\[switch\]\$Bootstrap,\s*\[switch\]\$Kernel,\s*\[switch\]\$KernelDrivers,\s*\[switch\]\$World,\s*\[switch\]\$Fresh\s*\)' 'canonical build-src parameters'
Assert-Match $remoteScriptText ([regex]::Escape('$stdinWriter.WriteAsync($payload)')) 'stream stdin writer is asynchronous'
Assert-Match $remoteScriptText 'Task\]::WaitAny' 'stream writer and readers share a blocking task loop'
Assert-Match $remoteScriptText '\[void\]\$writeTask\.GetAwaiter\(\)\.GetResult\(\)' 'stream writer task result cannot pollute exit status'
Assert-Equal ([regex]::Matches($remoteScriptText, 'ReadLineAsync\(\)').Count -ge 4) $true 'stream readers are continuously renewed'
Assert-Equal ($remoteScriptText.IndexOf('ReadLineAsync()') -lt $remoteScriptText.IndexOf('$stdinWriter.WriteAsync($payload)')) $true 'stream readers are armed with async stdin writer'
Assert-Match $remoteScriptText '(?s)\$stdoutTask = \$process\.StandardOutput\.ReadLineAsync\(\).*?\$sinkError.*?& \$emitStdout' 'stdout renews before deferred sink handling'
Assert-Match $remoteScriptText '(?s)\$stderrTask = \$process\.StandardError\.ReadLineAsync\(\).*?\$sinkError.*?& \$emitStderr' 'stderr renews before deferred sink handling'
Assert-Match $remoteScriptText '\$process\.Kill\(\)' 'exceptional streaming cleanup terminates exact child'
Assert-Match $remoteScriptText '(?s)finally \{.*?WaitForExit\(\).*?Dispose\(\)' 'exceptional cleanup reaps before dispose'
Assert-Equal ($buildScriptText.IndexOf('New-RhapFreshCommand') -lt $buildScriptText.IndexOf('New-RhapPreflightCommand')) $true 'fresh topology validates before preflight'
Assert-Match $buildScriptText 'New-RhapFreshCommand[^\r\n]+-Profile \$cfg\.ToolchainProfile' 'fresh validates resolved configured profile'
Assert-Match $buildScriptText ([regex]::Escape('-TargetArch $profileValues.target_arch')) 'phase generation consumes the selected profile architecture'
Assert-Equal ((Get-RhapKernelCorePackages -TargetArch 'ppc') -join ',') 'driverkit-3,driverTools-1,kernload-1,drivers-ppc/bus/drvPExpert,kernel-7' 'ppc kernel core package order'
Assert-Equal ((Get-RhapKernelCorePackages -TargetArch 'i386') -join ',') 'driverkit-3,driverTools-1,kernload-1,drivers-i386/bus/drvPExpert,kernel-7' 'i386 kernel core package order'
Assert-Match $buildScriptText 'Get-RhapKernelCorePackages -TargetArch \$profileValues\.target_arch' 'kernel phase validates core sources for the selected architecture'
Assert-Match $buildScriptText "\`$phase -eq 'kernel'" 'kernel phase preflights core package sources'
Assert-NotMatch $buildScriptText 'function Get-DriverProjectRels' 'optional driver scan lives in rbuild, not the host orchestrator'
Assert-NotMatch $buildScriptText "@\('drivers-i386', 'drivers-ppc'\)" 'optional driver scan does not mix i386 and ppc trees'

$phaseArgs = @{
    SourceRoot = '/build/src'
    ToolsDir = '/build/tools'
    BootstrapRoot = '/build/bootstrap-root'
    StateDir = '/build/state'
    Profile = '/build/src/rbuild-1/toolchains/gcc-darwin.conf'
    RepoDir = '/build/repo'
    BuiltDir = '/build/built'
    BuildCc = '/usr/bin/cc'
    TargetArch = 'ppc'
    Make = '/bin/make'
    ToolPath = '/build/tools/bin:/usr/bin:/bin'
}
$rbuildCommand = New-RhapBuildPhaseCommand -Phase 'rbuild' @phaseArgs
Assert-Match $rbuildCommand ([regex]::Escape('cd /build/src/rbuild-1 && /bin/make CC=/usr/bin/cc clean test all')) 'rbuild cleans tests and builds with profile compiler'
Assert-Match $rbuildCommand ([regex]::Escape('/usr/bin/install -d /build/tools/bin')) 'rbuild creates private tool directory'
Assert-Match $rbuildCommand ([regex]::Escape('/usr/bin/install -c -m 755 rbuild /build/tools/bin/rbuild')) 'rbuild installs privately'
Assert-Match $rbuildCommand ([regex]::Escape('/usr/bin/cc -O -o /build/tools/bin/relpath /build/src/Commands/bootstrap_cmds/relpath.tproj/relpath.c')) 'relpath is source-built with profile compiler'
Assert-Match $rbuildCommand ([regex]::Escape('/usr/bin/cc -O -o /build/tools/bin/decomment /build/src/Commands/bootstrap_cmds/decomment.tproj/decomment.c')) 'decomment is source-built privately with profile compiler'
Assert-Match $rbuildCommand ([regex]::Escape("printf '%s\n' 'alpha /* block */ beta // line' ' gamma' > /build/tools/decomment-build/input.h")) 'decomment smoke covers block, line, and whitespace removal'
Assert-Match $rbuildCommand ([regex]::Escape('/build/tools/bin/decomment /build/tools/decomment-build/input.h r > /build/tools/decomment-build/output.h')) 'decomment smoke executes the private product'
Assert-Match $rbuildCommand ([regex]::Escape('test "$(/bin/cat /build/tools/decomment-build/output.h)" = alphabetagamma')) 'decomment smoke validates meaningful exact output'
Assert-NotMatch $rbuildCommand '/usr/local/bin/decomment|bootstrap-root/(usr/)?(?:local/)?bin/decomment|cp .*decomment' 'stage zero never copies or selects live or sysroot decomment'
Assert-Match $rbuildCommand ([regex]::Escape('rm -rf /build/tools/config-build')) 'config private build directory is recreated exactly'
Assert-Match $rbuildCommand ([regex]::Escape('/usr/bin/install -d /build/tools/config-build')) 'config uses private build directory'
Assert-Match $rbuildCommand ([regex]::Escape('/usr/bin/yacc -d /build/src/Commands/bootstrap_cmds/config.tproj/parser.y')) 'config parser is source-generated'
Assert-Match $rbuildCommand ([regex]::Escape('/usr/bin/lex /build/src/Commands/bootstrap_cmds/config.tproj/lexer.l')) 'config lexer is source-generated'
Assert-Match $rbuildCommand ([regex]::Escape('/usr/bin/cc -O -bsd -DCMU -DLOCALARCHITECTURE -DNeXT=1 -I/build/src/Commands/bootstrap_cmds/config.tproj -I/build/tools/config-build -o /build/tools/bin/config')) 'config preserves project compiler flags and builds privately with profile compiler'
Assert-NotMatch $rbuildCommand '/usr/local/bin/config|cp .*config|DSTROOT=/' 'config never copies or installs to live host'
Assert-Match $rbuildCommand ([regex]::Escape('rm -rf /build/tools/mig-build')) 'MIG private build root is recreated exactly'
Assert-Match $rbuildCommand ([regex]::Escape('/usr/bin/install -d /build/tools/bin /build/tools/libexec /build/tools/mig-build/include/mach/machine /build/tools/mig-build/include/mach/ppc /build/tools/mig-build/migcom /build/tools/mig-build/migcom_typd /build/tools/mig-build/migcom_untypd')) 'MIG private product, overlay, and build directories are created'
Assert-Match $rbuildCommand ([regex]::Escape('/usr/bin/install -c -m 755 /build/src/Commands/bootstrap_cmds/migcom.tproj/mig.sh /build/tools/bin/mig')) 'repository MIG wrapper is installed privately'
Assert-Match $rbuildCommand ([regex]::Escape('/build/tools/mig-build/include/mach/message.h')) 'MIG build creates a private source-owned Mach header overlay'
Assert-Match $rbuildCommand ([regex]::Escape('/bin/ln -s /build/src/kernel-7/mach/ndr.h /build/tools/mig-build/include/mach/ndr.h')) 'MIG overlay includes the untyped backend NDR dependency'
Assert-Match $rbuildCommand ([regex]::Escape('/bin/ln -s /build/src/kernel-7/mach/ppc/simple_lock.h /build/tools/mig-build/include/mach/ppc/simple_lock.h')) 'MIG overlay declares its complete verified PPC header closure'
Assert-Match $rbuildCommand ([regex]::Escape('-I/build/tools/mig-build/include')) 'MIG compilers search the private header overlay first'
Assert-Match $rbuildCommand ([regex]::Escape('-M -O -bsd -DNeXT=1 -I/build/tools/mig-build/include')) 'MIG dependency audit uses the real private compile flags'
Assert-Match $rbuildCommand ([regex]::Escape('/usr/include/mach/')) 'MIG dependency audit rejects live host Mach headers'
Assert-Match $rbuildCommand ([regex]::Escape('/build/bootstrap-root/')) 'MIG dependency audit rejects bootstrap sysroot headers'
Assert-Match $rbuildCommand ([regex]::Escape('/usr/bin/yacc -d /build/src/Commands/bootstrap_cmds/migcom.tproj/parser.y && /bin/mv y.tab.h parser.h && /usr/bin/lex /build/src/Commands/bootstrap_cmds/migcom.tproj/lexxer.l')) 'classic MIG parser and lexer are generated privately'
Assert-Match $rbuildCommand ([regex]::Escape('-o /build/tools/libexec/migcom ')) 'classic MIG compiler is private'
Assert-Match $rbuildCommand ([regex]::Escape('-o /build/tools/libexec/migcom_typd ')) 'typed MIG compiler is private'
Assert-Match $rbuildCommand ([regex]::Escape('-o /build/tools/libexec/migcom_untypd ')) 'untyped MIG compiler is private'
Assert-Match $rbuildCommand ([regex]::Escape('/usr/bin/cc -O -bsd -DNeXT=1 -I/build/tools/mig-build/include -I/build/src/Commands/bootstrap_cmds/migcom.tproj -I/build/tools/mig-build/migcom -o /build/tools/libexec/migcom')) 'classic MIG enables Rhapsody handler and padding support'
Assert-Match $rbuildCommand ([regex]::Escape('/usr/bin/cc -O -bsd -DNeXT=1 -I/build/tools/mig-build/include -I/build/src/Commands/bootstrap_cmds/migcom_typd.tproj -I/build/tools/mig-build/migcom_typd -o /build/tools/libexec/migcom_typd')) 'typed MIG preserves historical platform flags'
Assert-Match $rbuildCommand ([regex]::Escape('/usr/bin/cc -O -bsd -DNeXT=1 -I/build/tools/mig-build/include -I/build/src/Commands/bootstrap_cmds/migcom_untypd.tproj -I/build/tools/mig-build/migcom_untypd -o /build/tools/libexec/migcom_untypd')) 'untyped MIG preserves historical platform flags'
Assert-Match $rbuildCommand ([regex]::Escape('/migcom.tproj/handler.c')) 'classic MIG links the NeXT handler backend'
Assert-Match $rbuildCommand ([regex]::Escape('/build/src/Commands/bootstrap_cmds/migcom_untypd.tproj/migcom_untypd_vers_stub.c')) 'untyped MIG compiler links its checked-in version stub'
Assert-Match $rbuildCommand ([regex]::Escape('CONFIG_DIR=/build/tools/bin MIGCC=/usr/bin/cc MIGARCH=ppc MIGCOM_DIR=/build/tools/libexec /build/tools/bin/mig -typed -I/build/src/kernel-7 -DKERNEL -DKERNEL_SERVER -header /dev/null -user /dev/null -server mach_server.c /build/src/kernel-7/mach/mach.defs')) 'private typed MIG wrapper contract preprocesses a real defs filename with configured GCC and profile architecture'
Assert-NotMatch $rbuildCommand '/usr/bin/mig|/usr/libexec/migcom|NEXT_ROOT|bootstrap-root/usr/libexec|DSTROOT=/|cp .*mig' 'stage zero never uses or copies live or sysroot MIG'
$alternatePhaseArgs = $phaseArgs.Clone()
$alternatePhaseArgs.BuildCc = '/opt/gcc/bin/gcc-4.2'
$alternatePhaseArgs.TargetArch = 'mips_safe'
$alternatePhaseArgs.Make = '/opt/make/bin/gmake'
$alternateRbuild = New-RhapBuildPhaseCommand -Phase 'rbuild' @alternatePhaseArgs
Assert-Match $alternateRbuild ([regex]::Escape('/opt/make/bin/gmake CC=/opt/gcc/bin/gcc-4.2 clean test all')) 'alternate profile compiler builds rbuild'
Assert-Match $alternateRbuild ([regex]::Escape('/opt/gcc/bin/gcc-4.2 -O -bsd -DCMU -DLOCALARCHITECTURE -DNeXT=1')) 'alternate profile compiler builds config with project flags'
Assert-Match $alternateRbuild ([regex]::Escape('/opt/gcc/bin/gcc-4.2 -O -bsd -DNeXT=1 -I/build/tools/mig-build/include -I/build/src/Commands/bootstrap_cmds/migcom.tproj -I/build/tools/mig-build/migcom -o /build/tools/libexec/migcom')) 'alternate profile compiler builds MIG with historical platform flags'
Assert-Match $alternateRbuild ([regex]::Escape('/opt/gcc/bin/gcc-4.2 -O -o /build/tools/bin/decomment /build/src/Commands/bootstrap_cmds/decomment.tproj/decomment.c')) 'alternate profile compiler builds private decomment'
Assert-Match $alternateRbuild ([regex]::Escape('MIGCC=/opt/gcc/bin/gcc-4.2 MIGARCH=mips_safe MIGCOM_DIR=/build/tools/libexec')) 'alternate GCC profile selects its own safe MIG architecture'
Assert-NotMatch $alternateRbuild ([regex]::Escape('/bin/make CC=/usr/bin/cc')) 'alternate profile does not use default build tools'
$spacedCompilerArgs = $phaseArgs.Clone()
$spacedCompilerArgs.BuildCc = '/opt/gcc tools/bin/gcc'
$spacedCompilerRbuild = New-RhapBuildPhaseCommand -Phase 'rbuild' @spacedCompilerArgs
Assert-Match $spacedCompilerRbuild ([regex]::Escape("'/opt/gcc tools/bin/gcc' -O -bsd -DNeXT=1 -I/build/tools/mig-build/include -I/build/src/Commands/bootstrap_cmds/migcom.tproj")) 'space-containing configured GCC builds private MIG as one executable path'
Assert-Match $spacedCompilerRbuild ([regex]::Escape("'/opt/gcc tools/bin/gcc' -O -o /build/tools/bin/decomment /build/src/Commands/bootstrap_cmds/decomment.tproj/decomment.c")) 'space-containing configured GCC builds private decomment as one executable path'
$metacharRootArgs = $phaseArgs.Clone()
$metacharRootArgs.BootstrapRoot = '/build/root[1].*'
$metacharRootRbuild = New-RhapBuildPhaseCommand -Phase 'rbuild' @metacharRootArgs
Assert-Match $metacharRootRbuild ([regex]::Escape("/usr/bin/grep -F -e '/usr/include/mach/' -e '/build/root[1].*'/")) 'MIG dependency audit treats metacharacter sysroot as a literal path'
Assert-Match $metacharRootRbuild ([regex]::Escape("else mig_dependency_status=`$?; test `$mig_dependency_status -eq 1 || { echo 'build-src: private MIG dependency audit failed: migcom'")) 'MIG dependency audit distinguishes grep errors from no matches'

$bootstrapCommand = New-RhapBuildPhaseCommand -Phase 'bootstrap' @phaseArgs
$alternateToolBootstrap = New-RhapBuildPhaseCommand -Phase 'bootstrap' @alternatePhaseArgs
$spacedCompilerBootstrap = New-RhapBuildPhaseCommand -Phase 'bootstrap' @spacedCompilerArgs
Assert-Match $bootstrapCommand ([regex]::Escape('/usr/bin/install -d /build/bootstrap-root /build/repo /build/state')) 'bootstrap creates owned output directories'
Assert-Match $bootstrapCommand ([regex]::Escape('CONFIG_DIR=/build/tools/bin DECOMMENT=/build/tools/bin/decomment MIGCC=/usr/bin/cc')) 'bootstrap scopes private config and decomment tools'
Assert-Match $bootstrapCommand ([regex]::Escape('BISON=/build/bootstrap-root/usr/bin/bison BISON_SIMPLE=/build/bootstrap-root/usr/share/bison.simple')) 'bootstrap scopes the replayed bison executable and parser skeleton'
Assert-Match $bootstrapCommand ([regex]::Escape('CONFIG_DIR=/build/tools/bin DECOMMENT=/build/tools/bin/decomment MIGCC=/usr/bin/cc MIGARCH=ppc MIGCOM_DIR=/build/tools/libexec BISON=/build/bootstrap-root/usr/bin/bison BISON_SIMPLE=/build/bootstrap-root/usr/share/bison.simple /build/tools/bin/rbuild bootstrap')) 'bootstrap explicitly binds private decomment, MIG, and staged parser-generator tools'
Assert-Match $alternateToolBootstrap ([regex]::Escape('MIGCC=/opt/gcc/bin/gcc-4.2 MIGARCH=mips_safe MIGCOM_DIR=/build/tools/libexec')) 'bootstrap binds alternate configured GCC and architecture to private MIG'
Assert-Match $spacedCompilerBootstrap ([regex]::Escape("MIGCC='/opt/gcc tools/bin/gcc' MIGARCH=ppc MIGCOM_DIR=/build/tools/libexec")) 'bootstrap quotes space-containing configured GCC for MIG wrapper'
Assert-NotMatch $bootstrapCommand '/usr/bin/mig|/usr/libexec/migcom|NEXT_ROOT|bootstrap-root/usr/libexec' 'bootstrap never selects live or sysroot MIG'
Assert-Equal ($bootstrapCommand.IndexOf('/usr/bin/install -d') -lt $bootstrapCommand.IndexOf('/build/tools/bin/rbuild bootstrap')) $true 'bootstrap creates outputs before rbuild'
Assert-Match $bootstrapCommand ([regex]::Escape('&& cd /build/src && CONFIG_DIR=/build/tools/bin')) 'bootstrap starts from synced source root'
Assert-Match $bootstrapCommand ([regex]::Escape('/build/tools/bin/rbuild bootstrap --sysroot /build/bootstrap-root --toolchain /build/src/rbuild-1/toolchains/gcc-darwin.conf --state /build/state /build/src/BootstrapManifest /build/repo /build/repo')) 'bootstrap uses resumable CLI'
Assert-Match $bootstrapCommand ([regex]::Escape('/build/tools/bin/rbuild bootstrap-universal --sysroot /build/bootstrap-root --toolchain /build/src/rbuild-1/toolchains/gcc-darwin.conf --state /build/state /build/src/BootstrapManifest /build/repo /build/repo')) 'bootstrap-universal is the primary second walk'
Assert-Equal ($bootstrapCommand.IndexOf('/build/tools/bin/rbuild bootstrap --sysroot') -lt $bootstrapCommand.IndexOf('/build/tools/bin/rbuild bootstrap-universal --sysroot')) $true 'thin bootstrap runs before bootstrap-universal'
$alternateSourceArgs = $phaseArgs.Clone()
$alternateSourceArgs.SourceRoot = '/srv/synced source'
$alternateBootstrap = New-RhapBuildPhaseCommand -Phase 'bootstrap' @alternateSourceArgs
Assert-Match $alternateBootstrap ([regex]::Escape("cd '/srv/synced source' && CONFIG_DIR=/build/tools/bin")) 'bootstrap quotes and uses alternate source cwd'
Assert-Match $alternateBootstrap ([regex]::Escape("'/srv/synced source'/BootstrapManifest")) 'bootstrap manifest follows alternate source root'
Assert-NotMatch $alternateBootstrap '/var/root|cd +~' 'bootstrap never inherits login cwd'
$spacedPhaseArgs = $phaseArgs.Clone()
$spacedPhaseArgs.SourceRoot = '/srv/build tree/src'
$spacedPhaseArgs.ToolsDir = '/srv/build tree/tools'
$spacedPhaseArgs.BootstrapRoot = '/srv/build tree/bootstrap root'
$spacedPhaseArgs.RepoDir = '/srv/build tree/repo'
$spacedPhaseArgs.BuiltDir = '/srv/build tree/built output'
$spacedPhaseArgs.StateDir = '/srv/build tree/state'
$spacedPhaseArgs.Profile = '/srv/build tree/profile.conf'
$spacedRbuild = New-RhapBuildPhaseCommand -Phase 'rbuild' @spacedPhaseArgs
Assert-Match $spacedRbuild ([regex]::Escape("rm -rf '/srv/build tree/tools'/config-build")) 'config safely quotes alternate private build directory'
Assert-Match $spacedRbuild ([regex]::Escape("'/srv/build tree/tools'/bin/decomment '/srv/build tree/tools'/decomment-build/input.h r > '/srv/build tree/tools'/decomment-build/output.h")) 'decomment smoke safely quotes alternate private tool paths'
Assert-Match $spacedRbuild ([regex]::Escape("-I'/srv/build tree/src'/Commands/bootstrap_cmds/config.tproj -I'/srv/build tree/tools'/config-build -o '/srv/build tree/tools'/bin/config")) 'config safely quotes alternate source and tools paths'
Assert-Match $spacedRbuild ([regex]::Escape("rm -rf '/srv/build tree/tools'/mig-build")) 'MIG safely quotes alternate private build root'
Assert-Match $spacedRbuild ([regex]::Escape("-O -bsd -DNeXT=1 -I'/srv/build tree/tools'/mig-build/include -I'/srv/build tree/src'/Commands/bootstrap_cmds/migcom_typd.tproj -I'/srv/build tree/tools'/mig-build/migcom_typd -o '/srv/build tree/tools'/libexec/migcom_typd")) 'MIG preserves platform flags and safely quotes alternate paths'
Assert-Match $spacedRbuild ([regex]::Escape("CONFIG_DIR='/srv/build tree/tools'/bin MIGCC=/usr/bin/cc MIGARCH=ppc MIGCOM_DIR='/srv/build tree/tools'/libexec '/srv/build tree/tools'/bin/mig -typed -I'/srv/build tree/src'/kernel-7 -DKERNEL -DKERNEL_SERVER -header /dev/null -user /dev/null -server mach_server.c '/srv/build tree/src'/kernel-7/mach/mach.defs")) 'typed MIG smoke generation safely quotes alternate source and private tool paths'
$spacedBootstrap = New-RhapBuildPhaseCommand -Phase 'bootstrap' @spacedPhaseArgs
Assert-Match $spacedBootstrap ([regex]::Escape("/usr/bin/install -d '/srv/build tree/bootstrap root' '/srv/build tree/repo' '/srv/build tree/state'")) 'bootstrap safely quotes owned outputs'
Assert-Match $spacedBootstrap ([regex]::Escape("CONFIG_DIR='/srv/build tree/tools'/bin DECOMMENT='/srv/build tree/tools'/bin/decomment MIGCC=/usr/bin/cc")) 'bootstrap safely quotes private config and decomment tools'
Assert-Match $spacedBootstrap ([regex]::Escape("MIGCC=/usr/bin/cc MIGARCH=ppc MIGCOM_DIR='/srv/build tree/tools'/libexec BISON='/srv/build tree/bootstrap root'/usr/bin/bison BISON_SIMPLE='/srv/build tree/bootstrap root'/usr/share/bison.simple '/srv/build tree/tools'/bin/rbuild bootstrap")) 'bootstrap safely quotes private MIG, parser-generator, and profile architecture bindings'
Assert-Match $spacedBootstrap ([regex]::Escape("DECOMMENT='/srv/build tree/tools'/bin/decomment MIGCC=/usr/bin/cc")) 'bootstrap safely quotes private decomment binding'
$kernelCommand = New-RhapBuildPhaseCommand -Phase 'kernel' @phaseArgs
Assert-Match $kernelCommand ([regex]::Escape('test -d /build/repo')) 'kernel requires existing repository input'
Assert-Match $kernelCommand ([regex]::Escape('/usr/bin/install -d /build/built /build/state')) 'kernel creates owned output directories'
Assert-Equal ($kernelCommand.IndexOf('/usr/bin/install -d /build/built') -lt $kernelCommand.IndexOf('rbuild kernel')) $true 'kernel creates outputs before rbuild kernel'
Assert-Match $kernelCommand ([regex]::Escape('cd /build/src && /build/tools/bin/rbuild kernel --state /build/state --arch ppc /build/src /build/repo /build/built')) 'kernel uses dedicated rbuild command'
Assert-NotMatch $kernelCommand 'buildpackage|--dir driverkit-3|kerneldrivers' 'kernel phase does not inline package loops or optional drivers'
$kernelDriversCommand = New-RhapBuildPhaseCommand -Phase 'kernel-drivers' @phaseArgs
Assert-Match $kernelDriversCommand ([regex]::Escape('test -d /build/repo')) 'kernel-drivers requires existing repository input'
Assert-Match $kernelDriversCommand ([regex]::Escape('/usr/bin/install -d /build/built /build/state')) 'kernel-drivers creates owned output directories'
Assert-Equal ($kernelDriversCommand.IndexOf('/usr/bin/install -d /build/built') -lt $kernelDriversCommand.IndexOf('rbuild kerneldrivers')) $true 'kernel-drivers creates outputs before rbuild kerneldrivers'
Assert-Match $kernelDriversCommand ([regex]::Escape('cd /build/src && /build/tools/bin/rbuild kerneldrivers --state /build/state --arch ppc /build/src /build/repo /build/built')) 'kernel-drivers uses dedicated rbuild command'
Assert-NotMatch $kernelDriversCommand 'buildpackage|--dir driverkit-3| rbuild kernel ' 'kernel-drivers phase does not inline the kernel core list'
$i386KernelArgs = $phaseArgs.Clone()
$i386KernelArgs.TargetArch = 'i386'
$i386KernelCommand = New-RhapBuildPhaseCommand -Phase 'kernel' @i386KernelArgs
Assert-Match $i386KernelCommand ([regex]::Escape('rbuild kernel --state /build/state --arch i386 /build/src /build/repo /build/built')) 'i386 kernel selects the profile architecture'
Assert-NotMatch $i386KernelCommand 'drivers-ppc' 'i386 kernel command does not mention the ppc driver tree'
$i386KernelDriversCommand = New-RhapBuildPhaseCommand -Phase 'kernel-drivers' @i386KernelArgs
Assert-Match $i386KernelDriversCommand ([regex]::Escape('rbuild kerneldrivers --state /build/state --arch i386 /build/src /build/repo /build/built')) 'i386 kernel-drivers selects the profile architecture'
$spacedKernel = New-RhapBuildPhaseCommand -Phase 'kernel' @spacedPhaseArgs
Assert-Match $spacedKernel ([regex]::Escape("'/srv/build tree/tools'/bin/rbuild kernel --state '/srv/build tree/state' --arch ppc '/srv/build tree/src' '/srv/build tree/repo' '/srv/build tree/built output'")) 'kernel safely quotes alternate source and output paths'
$worldCommand = New-RhapBuildPhaseCommand -Phase 'world' @phaseArgs
Assert-Match $worldCommand ([regex]::Escape('test -d /build/repo')) 'world requires existing repository input'
Assert-Match $worldCommand ([regex]::Escape('/usr/bin/install -d /build/built /build/state')) 'world creates owned output directories'
Assert-Equal ($worldCommand.IndexOf('/usr/bin/install -d /build/built') -lt $worldCommand.IndexOf('rbuild buildall')) $true 'world creates outputs before buildall'
Assert-Match $worldCommand ([regex]::Escape('cd /build/src && /build/tools/bin/rbuild buildall --state /build/state Manifest /build/repo /build/built')) 'world uses manifest and state'

foreach ($generated in @($rbuildCommand, $bootstrapCommand, $kernelCommand, $kernelDriversCommand, $worldCommand)) {
    Assert-NotMatch $generated '/tmp/_|_seed-bootstrap-hdrs\.sh|DSTROOT=/|/usr/bin/rbuild|date-setting|header upload' 'generated command excludes obsolete workaround'
    Assert-NotMatch $generated '(?m)^\s*rm\s+-rf(?! /private/tmp/roots)' 'phase command never deletes build output trees'
}

$freshCommand = New-RhapFreshCommand -RemoteRoot '/build' -SourceRoot '/build/src' -Profile '/build/src/rbuild-1/toolchains/gcc-darwin.conf' -ToolsDir '/build/tools' -BootstrapRoot '/build/bootstrap-root' -RepoDir '/build/repo' -BuiltDir '/build/built' -StateDir '/build/state'
Assert-Match $freshCommand ([regex]::Escape("rm -rf '/build/tools' '/build/bootstrap-root' '/build/repo' '/build/built' '/build/state'")) 'fresh removes exact configured outputs once'
Assert-Match $freshCommand ([regex]::Escape("mkdir -p '/build'")) 'fresh recreates only default output parent'
Assert-NotMatch $freshCommand ([regex]::Escape("mkdir -p '/build/tools")) 'fresh does not recreate output directories'
$freshRmLine = @($freshCommand -split "`n" | Where-Object { $_ -match '^rm -rf ' })[0]
Assert-NotMatch $freshRmLine '\*|\$[A-Za-z_]' 'fresh has no wildcard or variable deletion operands'
Assert-Equal ([regex]::Matches($freshCommand, '(?m)\brm\s').Count) 1 'fresh uses one removal command'
Assert-Match $freshCommand 'pwd' 'fresh validates physical boundaries'
Assert-Match $freshCommand 'test -L' 'fresh rejects symlink path components'
Assert-Match $freshCommand 'SOURCE_PHYS' 'fresh protects physical source root'
Assert-Match $freshCommand 'physical RemoteRoot may not be /' 'fresh rejects physical filesystem root'
Assert-Match $freshCommand 'SourceRoot escapes RemoteRoot' 'fresh requires physical source containment'
Assert-Match $freshCommand 'test -f "\$PROFILE"' 'fresh requires existing regular profile'
Assert-Match $freshCommand 'test ! -L "\$PROFILE"' 'fresh rejects final profile symlink'
Assert-Match $freshCommand 'PROFILE_PARENT_PHYS=.*pwd' 'fresh resolves profile parent physically'
Assert-NotMatch $freshCommand 'cd -P' 'fresh uses Rhapsody-legal cd (no -P)'
Assert-Match $freshCommand 'ROOT_PHYS=\$\(cd "\$ROOT" && pwd\)' 'fresh resolves RemoteRoot without POSIX cd -P'
Assert-Match $freshCommand 'profile.*overlaps Fresh output' 'fresh compares physical profile and outputs'
Assert-Equal ($freshCommand.IndexOf('check_target') -lt $freshCommand.IndexOf("rm -rf '/build/tools'")) $true 'fresh validates before deletion'
Assert-Equal ($freshCommand.IndexOf('PROFILE_PARENT_PHYS') -lt $freshCommand.IndexOf("rm -rf '/build/tools'")) $true 'fresh resolves physical profile before deletion'
$freshBase = @{ RemoteRoot='/build'; SourceRoot='/build/src'; Profile='/build/src/profile.conf'; ToolsDir='/build/tools'; BootstrapRoot='/build/root'; RepoDir='/build/repo'; BuiltDir='/build/built'; StateDir='/build/state' }
Assert-Throws { $p=$freshBase.Clone(); $p.ToolsDir='/build'; New-RhapFreshCommand @p } 'fresh rejects output equal to root'
Assert-Throws { $p=$freshBase.Clone(); $p.ToolsDir='/usr/tools'; New-RhapFreshCommand @p } 'fresh rejects output outside root'
Assert-Throws { $p=$freshBase.Clone(); $p.SourceRoot='/srv/src'; New-RhapFreshCommand @p } 'fresh rejects source outside root'
Assert-Throws { $p=$freshBase.Clone(); $p.ToolsDir='/build/src/tools'; New-RhapFreshCommand @p } 'fresh rejects output inside source'
Assert-Throws { $p=$freshBase.Clone(); $p.ToolsDir='/build/SRC'; New-RhapFreshCommand @p } 'fresh rejects case alias of source'
Assert-Throws { $p=$freshBase.Clone(); $p.ToolsDir='/build/output'; $p.BootstrapRoot='/build/OUTPUT'; New-RhapFreshCommand @p } 'fresh rejects case-insensitive duplicate roles'
Assert-Throws { $p=$freshBase.Clone(); $p.ToolsDir='/build/output'; $p.BootstrapRoot='/build/output/root'; New-RhapFreshCommand @p } 'fresh rejects nested roles'
Assert-Throws { $p=$freshBase.Clone(); $p.Profile='/build/tools/gcc.conf'; New-RhapFreshCommand @p } 'fresh rejects profile nested beneath output'
Assert-Throws { $p=$freshBase.Clone(); $p.Profile='/build/TOOLS'; New-RhapFreshCommand @p } 'fresh rejects profile case alias of output'
$outsideProfileFresh = New-RhapFreshCommand -RemoteRoot '/build' -SourceRoot '/build/src' -Profile '/opt/profiles/gcc.conf' -ToolsDir '/build/tools' -BootstrapRoot '/build/root' -RepoDir '/build/repo' -BuiltDir '/build/built' -StateDir '/build/state'
Assert-Match $outsideProfileFresh ([regex]::Escape("rm -rf '/build/tools'")) 'fresh accepts absolute profile outside outputs'
$caseFresh = New-RhapFreshCommand -RemoteRoot '/build' -SourceRoot '/build/src' -Profile '/build/src/profile.conf' -ToolsDir '/build/A/tools' -BootstrapRoot '/build/a/root' -RepoDir '/build/output/repo' -BuiltDir '/build/other/built' -StateDir '/build/state/run'
Assert-Match $caseFresh ([regex]::Escape("mkdir -p '/build/A' '/build/a' '/build/output' '/build/other' '/build/state'")) 'fresh deduplicates nested case-distinct parents ordinally'
Assert-NotMatch $caseFresh ([regex]::Escape("mkdir -p '/build/A/tools'")) 'fresh leaves nested outputs for their phases'

Assert-Equal (Assert-RhapFreshMode -All -Fresh) $true 'fresh accepts all mode'
Assert-Throws { Assert-RhapFreshMode -Rbuild -Fresh } 'fresh rejects granular rbuild mode'
Assert-Throws { Assert-RhapFreshMode -Bootstrap -Fresh } 'fresh rejects granular bootstrap mode'
$cleanScriptPath = Join-Path $VmDir 'clean-build.ps1'
Assert-Equal (Test-Path -LiteralPath $cleanScriptPath -PathType Leaf) $true 'clean-build script exists'
$cleanScriptText = Get-Content -Raw $cleanScriptPath
Assert-Match $cleanScriptText 'New-RhapFreshCommand' 'clean-build reuses the Fresh output-reset topology'
Assert-Match $cleanScriptText 'Invoke-RhapSshScript' 'clean-build runs the reset on the guest'
Assert-Match $cleanScriptText 'clean-build: complete' 'clean-build reports completion'
Assert-NotMatch $cleanScriptText '(?m)rm\s+-rf\s+.*/src' 'clean-build does not delete SourceRoot'
Assert-NotMatch $cleanScriptText '-All' 'clean-build does not start an -All rebuild'

$profileRead = New-RhapReadProfileCommand -Profile '/opt/profiles/gcc.conf'
Assert-Equal $profileRead "set -e; /bin/cat '/opt/profiles/gcc.conf'" 'absolute remote profile read command'
Assert-Throws { New-RhapReadProfileCommand -Profile "/opt/profile's.conf" } 'profile read rejects unsafe quote'

$orchestrationEvents = New-Object System.Collections.Generic.List[string]
$sequenceResult = Invoke-RhapBuildOrchestration -Phases @('rbuild', 'bootstrap', 'kernel', 'kernel-drivers', 'world') -PreflightBody 'preflight-body' -ProfileBody 'profile-body' -FreshBody 'fresh-body' -ParseProfile { param($text) "parsed:$text" } -PhaseFactory { param($phase, $profile) "$phase/$profile" } -ScriptInvoker { param($name, $body, $stream) $orchestrationEvents.Add("$name`:$stream"); return 0 } -CaptureInvoker { param($body) $orchestrationEvents.Add('profile'); return [pscustomobject]@{ ExitCode = 0; Stdout = 'remote'; Stderr = '' } }
Assert-Equal $sequenceResult $true 'orchestrator success'
Assert-Equal ($orchestrationEvents -join ',') 'preflight:False,profile,fresh output reset:False,rbuild:True,bootstrap:True,kernel:True,kernel-drivers:True,world:True' 'orchestrator preflight fresh and canonical order'
Assert-Equal @($orchestrationEvents | Where-Object { $_ -eq 'preflight:False' }).Count 1 'orchestrator runs preflight once'
$failureEvents = New-Object System.Collections.Generic.List[string]
Assert-Throws { Invoke-RhapBuildOrchestration -Phases @('rbuild', 'bootstrap', 'kernel', 'kernel-drivers', 'world') -PreflightBody 'p' -ProfileBody 'q' -ParseProfile { param($text) $text } -PhaseFactory { param($phase, $profile) $phase } -ScriptInvoker { param($name, $body, $stream) $failureEvents.Add($name); if ($name -eq 'bootstrap') { return 9 }; return 0 } -CaptureInvoker { param($body) return [pscustomobject]@{ ExitCode = 0; Stdout = 'remote'; Stderr = '' } } } 'orchestrator propagates required phase failure'
Assert-Equal ($failureEvents -join ',') 'preflight,rbuild,bootstrap' 'orchestrator stops at first required failure'

$profileValues = ConvertFrom-RhapToolchainProfileText -Text $realProfile
Assert-Equal $profileValues.build_cc '/usr/bin/cc' 'profile build compiler value'
Assert-Equal $profileValues.target_arch 'ppc' 'profile target architecture value'
Assert-Equal $profileValues.make '/bin/make' 'profile make value'
Assert-Equal $profileValues.make_flags 'MAKEFILEDIR=@SYSROOT@/System/Developer/Makefiles/project MAKEFILEPATH=@SYSROOT@/System/Developer/Makefiles' 'profile bootstrap make flags'
Assert-Equal $profileValues.make_flags_ready '@SYSROOT@/System/Developer/Makefiles/project/platform.make' 'profile bootstrap make flags readiness path'
Assert-Equal $profileValues.cpp_flags '-nostdinc -F@SYSROOT@/System/Library/Frameworks -I@SYSROOT@/System/Library/Frameworks/System.framework/Versions/B/Headers -I@SYSROOT@/System/Library/Frameworks/System.framework/Versions/B/Headers/bsd -I@SYSROOT@/System/Library/Frameworks/System.framework/Versions/B/PrivateHeaders' 'profile bootstrap isolated versioned BSD headers'
Assert-Equal $profileValues.cpp_flags_ready '@SYSROOT@/Developer/Libraries/gcc-lib/ppc/ginclude/stdarg.h' 'profile bootstrap cpp flags wait for compiler stdarg.h'
Assert-Equal $profileValues.ld_flags_ready '@SYSROOT@/System/Library/Frameworks/System.framework/Versions/B/System' 'profile bootstrap linker flags readiness path'
Assert-Equal $profileValues.archive_create '/bin/pax' 'profile archive creator value'
Assert-Equal $profileValues.archive_create_flags '-w -x ustar' 'profile archive creator flags'
Assert-Equal $profileValues.tar '/build/src/rbuild-1/pax-gnutar.sh' 'profile tar reconstructs POSIX ustar prefix names'
Assert-Match $paxGnutarText '(?m)^#!/bin/sh$' 'pax-gnutar is a POSIX shell wrapper'
Assert-Match $paxGnutarText '-xf' 'pax-gnutar accepts GNU tar extract flags'
Assert-Match $paxGnutarText '-cf' 'pax-gnutar accepts GNU tar create flags'
Assert-Match $paxGnutarText '/bin/pax -r' 'pax-gnutar extracts with pax so ustar prefix names survive'
Assert-Match $paxGnutarText '/bin/pax -w -x ustar' 'pax-gnutar creates POSIX ustar archives with pax'

Assert-Equal (Test-RhapToolchainProfileText -Text $realProfile) $true 'real toolchain profile contract'
Assert-Throws { Test-RhapToolchainProfileText -Text ($realProfile + "unknown_key=value`n") } 'reject unknown profile key'
Assert-Throws { Test-RhapToolchainProfileText -Text ($realProfile + "build_cc=/bin/false`n") } 'reject duplicate profile key'
Assert-Throws { Test-RhapToolchainProfileText -Text ($realProfile + "target_arch=i386`n") } 'reject duplicate target_arch profile key'
Assert-Throws { Test-RhapToolchainProfileText -Text ($realProfile -replace '(?m)^ld_flags=.*\r?\n?', '') } 'reject missing profile key'
Assert-Throws { Test-RhapToolchainProfileText -Text ($realProfile -replace '(?m)^target_arch=.*\r?\n?', '') } 'reject missing target_arch profile key'
Assert-Throws { Test-RhapToolchainProfileText -Text ($realProfile -replace '(?m)^archive_create=.*\r?\n?', '') } 'reject missing archive creator profile key'
Assert-Throws { Test-RhapToolchainProfileText -Text ($realProfile -replace '(?m)^archive_create_flags=.*\r?\n?', '') } 'reject missing archive creator flags profile key'
Assert-Equal (Test-RhapToolchainProfileText -Text ($realProfile -replace '(?m)^make_flags(?:_ready)?=.*\r?\n?', '')) $true 'accept profile without bootstrap make flags'
Assert-Throws { Test-RhapToolchainProfileText -Text ($realProfile -replace '(?m)^make_flags=.*$', 'make_flags=') } 'reject empty bootstrap make flags'
Assert-Throws { Test-RhapToolchainProfileText -Text ($realProfile -replace '(?m)^make_flags=.*$', 'make_flags=   ') } 'reject whitespace bootstrap make flags'
Assert-Equal (Test-RhapToolchainProfileText -Text ($realProfile -replace '(?m)^make_flags_ready=.*\r?\n?', '')) $true 'accept bootstrap make flags without readiness gate'
Assert-Equal (Test-RhapToolchainProfileText -Text ($realProfile -replace '(?m)^ld_flags_ready=.*\r?\n?', '')) $true 'accept bootstrap linker flags without readiness gate'
Assert-Equal (Test-RhapToolchainProfileText -Text ($realProfile -replace '(?m)^cpp_flags_ready=.*\r?\n?', '')) $true 'accept bootstrap cpp flags without readiness gate'
Assert-Equal (Test-RhapToolchainProfileText -Text ($realProfile -replace '(?m)^make_flags(?:_ready)?=.*\r?\n?', '')) $true 'accept profile omitting bootstrap make flags and gate'
Assert-Throws { Test-RhapToolchainProfileText -Text ($realProfile -replace '(?m)^make_flags=.*\r?\n?', '') } 'reject readiness gate without bootstrap make flags'
Assert-Throws { Test-RhapToolchainProfileText -Text ($realProfile -replace '(?m)^make_flags_ready=.*$', 'make_flags_ready=') } 'reject empty bootstrap make flags readiness gate'
Assert-Throws { Test-RhapToolchainProfileText -Text ($realProfile -replace '(?m)^make_flags_ready=.*$', 'make_flags_ready=   ') } 'reject whitespace bootstrap make flags readiness gate'
Assert-Throws { Test-RhapToolchainProfileText -Text ($realProfile -replace '(?m)^ld_flags_ready=.*$', 'ld_flags_ready=') } 'reject empty bootstrap linker flags readiness gate'
Assert-Throws { Test-RhapToolchainProfileText -Text ($realProfile -replace '(?m)^ld_flags_ready=.*$', 'ld_flags_ready=   ') } 'reject whitespace bootstrap linker flags readiness gate'
Assert-Throws { Test-RhapToolchainProfileText -Text ($realProfile -replace '(?m)^cpp_flags_ready=.*$', 'cpp_flags_ready=') } 'reject empty bootstrap cpp flags readiness gate'
Assert-Throws { Test-RhapToolchainProfileText -Text ($realProfile -replace '(?m)^cpp_flags_ready=.*$', 'cpp_flags_ready=   ') } 'reject whitespace bootstrap cpp flags readiness gate'
Assert-Throws { Test-RhapToolchainProfileText -Text ($realProfile + "tar_create_flags=--posix`n") } 'reject legacy tar-specific creation flags key'
Assert-Throws { Test-RhapToolchainProfileText -Text ($realProfile -replace '(?m)^target_arch=.*$', 'target_arch=ppc;touch_bad') } 'reject unsafe target_arch profile value'
Assert-Throws { Test-RhapToolchainProfileText -Text ($realProfile -replace '(?m)^profile=', 'profile ') } 'reject malformed profile line'
Assert-Equal (Assert-RhapSafeIdentifier -Value 'mips_safe' -Name 'target_arch') 'mips_safe' 'accept alternate safe architecture identifier'
Assert-Throws { Assert-RhapSafeIdentifier -Value '9ppc' -Name 'target_arch' } 'reject digit-leading architecture identifier'
Assert-Throws { Assert-RhapSafeIdentifier -Value 'ppc;touch_bad' -Name 'target_arch' } 'reject architecture injection'
Assert-Throws { $p=$phaseArgs.Clone(); $p.TargetArch='ppc other'; New-RhapBuildPhaseCommand -Phase 'rbuild' @p } 'phase rejects unsafe target architecture'
Assert-Equal (Assert-RhapSafeArchFlags -Value '-arch ppc -mcpu=G4') '-arch ppc -mcpu=G4' 'accept gcc-style flag operands'
Assert-Throws { Assert-RhapSafeArchFlags -Value '-arch *' } 'reject glob star in arch flags'
Assert-Throws { Assert-RhapSafeArchFlags -Value '-arch ppc?' } 'reject glob question in arch flags'
Assert-Throws { Assert-RhapSafeArchFlags -Value '-I[abc]' } 'reject glob bracket in arch flags'
Assert-Equal (Test-RhapMachOFileOutput -Text '/tmp/probe.o: Mach-O object ppc' -TargetArch ppc) $true 'accept profile Mach-O object description'
Assert-Equal (Test-RhapMachOFileOutput -Text '/tmp/probe.o: Mach-O object mips_safe' -TargetArch mips_safe) $true 'accept alternate profile Mach-O object description'
Assert-Throws { Test-RhapMachOFileOutput -Text '/tmp/probe.o: Mach-O object i386' -TargetArch ppc } 'reject wrong object architecture'
Assert-Throws { Test-RhapMachOFileOutput -Text '/tmp/probe.o: Mach-O object ppc64' -TargetArch ppc } 'reject PPC architecture prefix collision'
Assert-Throws { Test-RhapMachOFileOutput -Text '/tmp/probe.o: Mach-O object i386foo' -TargetArch i386 } 'reject i386 architecture prefix collision'
Assert-Throws { Test-RhapMachOFileOutput -Text '/tmp/probe.o: ELF 32-bit MSB relocatable, PowerPC' -TargetArch ppc } 'reject non-Mach-O object'

Assert-Equal (Assert-RhapSafeRemoteOutputPath -RemoteRoot '/build' -Path '/build/repo') '/build/repo' 'accept descendant'
Assert-Equal (Assert-RhapSafeRemoteOutputPath -RemoteRoot '//build//' -Path '//build///state//') '/build/state' 'normalize slashes'

foreach ($case in @(
    @('', '/build/repo', 'empty root'),
    @('/build', '', 'empty path'),
    @('build', '/build/repo', 'relative root'),
    @('/build', 'build/repo', 'relative path'),
    @('/build', '/build', 'equal root'),
    @('/build', '/', 'filesystem root'),
    @('/build', '/usr', 'outside root'),
    @('/build', '/buildish/repo', 'prefix lookalike'),
    @('/build', '/build/./repo', 'dot component'),
    @('/build', '/build/repo/../state', 'dotdot component'),
    @('/build/.', '/build/repo', 'dot root component'),
    @('/build', "/build/repo`nrm", 'newline'),
    @('/build', '/build/repo\state', 'backslash'),
    @('/build', '/build/repo;rm', 'shell metacharacter'),
    @('/', '/build/repo', 'unsafe broad root')
)) {
    $root = $case[0]
    $path = $case[1]
    $name = $case[2]
    Assert-Throws { Assert-RhapSafeRemoteOutputPath -RemoteRoot $root -Path $path } "reject $name"
}

Assert-Equal ((Get-RhapBuildPhases -All) -join ',') 'rbuild,bootstrap,kernel,kernel-drivers,world' 'all phase order'
Assert-Equal ((Get-RhapBuildPhases -Rbuild) -join ',') 'rbuild' 'rbuild phase'
Assert-Equal ((Get-RhapBuildPhases -Bootstrap) -join ',') 'bootstrap' 'bootstrap phase'
Assert-Equal ((Get-RhapBuildPhases -Kernel) -join ',') 'kernel' 'kernel phase'
Assert-Equal ((Get-RhapBuildPhases -KernelDrivers) -join ',') 'kernel-drivers' 'kernel-drivers phase'
Assert-Equal ((Get-RhapBuildPhases -World) -join ',') 'world' 'world phase'
Assert-Throws { Get-RhapBuildPhases } 'reject no phase'
Assert-Throws { Get-RhapBuildPhases -All -World } 'reject all plus phase'
Assert-Throws { Get-RhapBuildPhases -Rbuild -Bootstrap } 'reject two phases'
Assert-Throws { Get-RhapBuildPhases -Kernel -KernelDrivers } 'reject kernel plus kernel-drivers'

$cmd = New-RhapPreflightCommand -SourceRoot '/build/src' -ToolsDir '/build/tools' -BootstrapRoot '/build/bootstrap-root' -StateDir '/build/state' -Profile '/build/src/rbuild-1/toolchains/gcc-darwin.conf'
$profileValidatorStart = $cmd.IndexOf("awk 'BEGIN {")
$profileValidatorEndMarker = ' || fail "invalid toolchain profile"'
$profileValidatorEnd = $cmd.IndexOf($profileValidatorEndMarker, $profileValidatorStart)
Assert-Equal ($profileValidatorStart -ge 0) $true 'generated preflight contains profile validator'
Assert-Equal ($profileValidatorEnd -gt $profileValidatorStart) $true 'generated preflight profile validator has a failure boundary'
$profileValidator = $cmd.Substring($profileValidatorStart, $profileValidatorEnd - $profileValidatorStart)
function Test-GeneratedProfileValidatorContract([string]$Validator, [string]$ProfileText) {
    $allowed = @{}
    $required = @{}
    foreach ($match in [regex]::Matches($Validator, 'allowed\["([A-Za-z0-9_]+)"\] = 1')) {
        $allowed[$match.Groups[1].Value] = $true
    }
    foreach ($match in [regex]::Matches($Validator, 'required\["([A-Za-z0-9_]+)"\] = 1')) {
        $required[$match.Groups[1].Value] = $true
    }
    $paired = @{}
    foreach ($match in [regex]::Matches($Validator, 'paired\["([A-Za-z0-9_]+)"\] = "([A-Za-z0-9_]+)"')) {
        $paired[$match.Groups[1].Value] = $match.Groups[2].Value
    }
    $seen = @{}
    foreach ($rawLine in ($ProfileText -split "`r?`n")) {
        $line = $rawLine.Trim()
        if ($line -eq '' -or $line.StartsWith('#')) { continue }
        $equals = $line.IndexOf('=')
        if ($equals -lt 1) { return $false }
        $key = $line.Substring(0, $equals).Trim()
        $value = $line.Substring($equals + 1).Trim()
        if (-not $allowed.ContainsKey($key) -or $seen.ContainsKey($key) -or $value -eq '') { return $false }
        $seen[$key] = $true
    }
    foreach ($key in $required.Keys) {
        if (-not $seen.ContainsKey($key)) { return $false }
    }
    foreach ($key in $paired.Keys) {
        if ($seen.ContainsKey($key) -and -not $seen.ContainsKey($paired[$key])) { return $false }
    }
    return $true
}
Assert-Equal (Test-GeneratedProfileValidatorContract -Validator $profileValidator -ProfileText $realProfile) $true 'generated preflight accepts canonical profile with optional make flags'
Assert-Equal (Test-GeneratedProfileValidatorContract -Validator $profileValidator -ProfileText ($realProfile -replace '(?m)^make_flags(?:_ready)?=.*\r?\n?', '')) $true 'generated preflight accepts profile omitting optional make flags'
Assert-Equal (Test-GeneratedProfileValidatorContract -Validator $profileValidator -ProfileText ($realProfile -replace '(?m)^make_flags=.*$', 'make_flags=')) $false 'generated preflight rejects empty optional make flags'
Assert-Equal (Test-GeneratedProfileValidatorContract -Validator $profileValidator -ProfileText ($realProfile -replace '(?m)^make_flags=.*$', 'make_flags=   ')) $false 'generated preflight rejects whitespace optional make flags'
Assert-Equal (Test-GeneratedProfileValidatorContract -Validator $profileValidator -ProfileText ($realProfile -replace '(?m)^make_flags_ready=.*\r?\n?', '')) $true 'generated preflight accepts bootstrap make flags without readiness gate'
Assert-Equal (Test-GeneratedProfileValidatorContract -Validator $profileValidator -ProfileText ($realProfile -replace '(?m)^ld_flags_ready=.*\r?\n?', '')) $true 'generated preflight accepts bootstrap linker flags without readiness gate'
Assert-Equal (Test-GeneratedProfileValidatorContract -Validator $profileValidator -ProfileText ($realProfile -replace '(?m)^cpp_flags_ready=.*\r?\n?', '')) $true 'generated preflight accepts bootstrap cpp flags without readiness gate'
Assert-Equal (Test-GeneratedProfileValidatorContract -Validator $profileValidator -ProfileText ($realProfile -replace '(?m)^make_flags(?:_ready)?=.*\r?\n?', '')) $true 'generated preflight accepts omitted bootstrap make flags pair'
Assert-Equal (Test-GeneratedProfileValidatorContract -Validator $profileValidator -ProfileText ($realProfile -replace '(?m)^make_flags=.*\r?\n?', '')) $false 'generated preflight rejects readiness gate without bootstrap make flags'
Assert-Equal (Test-GeneratedProfileValidatorContract -Validator $profileValidator -ProfileText ($realProfile -replace '(?m)^make_flags_ready=.*$', 'make_flags_ready=')) $false 'generated preflight rejects empty readiness gate'
Assert-Equal (Test-GeneratedProfileValidatorContract -Validator $profileValidator -ProfileText ($realProfile -replace '(?m)^make_flags_ready=.*$', 'make_flags_ready=   ')) $false 'generated preflight rejects whitespace readiness gate'
Assert-Equal (Test-GeneratedProfileValidatorContract -Validator $profileValidator -ProfileText ($realProfile -replace '(?m)^ld_flags_ready=.*$', 'ld_flags_ready=')) $false 'generated preflight rejects empty linker readiness gate'
Assert-Equal (Test-GeneratedProfileValidatorContract -Validator $profileValidator -ProfileText ($realProfile -replace '(?m)^ld_flags_ready=.*$', 'ld_flags_ready=   ')) $false 'generated preflight rejects whitespace linker readiness gate'
Assert-Equal (Test-GeneratedProfileValidatorContract -Validator $profileValidator -ProfileText ($realProfile -replace '(?m)^cpp_flags_ready=.*$', 'cpp_flags_ready=')) $false 'generated preflight rejects empty cpp readiness gate'
Assert-Equal (Test-GeneratedProfileValidatorContract -Validator $profileValidator -ProfileText ($realProfile -replace '(?m)^cpp_flags_ready=.*$', 'cpp_flags_ready=   ')) $false 'generated preflight rejects whitespace cpp readiness gate'
Assert-Equal (Test-GeneratedProfileValidatorContract -Validator $profileValidator -ProfileText ($realProfile + "unknown_key=value`n")) $false 'generated preflight rejects unknown profile key'
Assert-Match $cmd '^set -e' 'literal POSIX script body'
Assert-Match $cmd 'test -f ' 'profile existence check'
Assert-Match $cmd 'test -d "\$SOURCE_ROOT"' 'source root directory check'
Assert-Match $cmd '"\$SOURCE_ROOT/BootstrapManifest"' 'bootstrap manifest source check'
Assert-Match $cmd '"\$SOURCE_ROOT/rbuild-1/Makefile"' 'rbuild source check'
Assert-Match $cmd '"\$SOURCE_ROOT/rbuild-1/toolchain\.c"' 'rbuild toolchain source check'
Assert-Match $cmd 'gcc-darwin\.conf' 'configured profile path'
Assert-Match $cmd 'test -x /usr/bin/cc' 'developer compiler check'
Assert-Match $cmd '/usr/bin/cc -arch ppc -c' 'target compiler evidence'
Assert-Match $cmd 'case-sensitive filesystem required' 'case sensitivity error'
Assert-Match $cmd 'BUILD_CC' 'build compiler parsed'
Assert-Match $cmd 'TARGET_CC' 'target compiler parsed'
Assert-Match $cmd 'TARGET_ARCH' 'target architecture parsed'
Assert-Match $cmd 'ARCH_FLAGS' 'architecture flags parsed'
Assert-NotMatch $cmd ([regex]::Escape('case "$rbuild_flag" in -*')) 'arch flag operands such as ppc are accepted'
Assert-Match $cmd 'set -f' 'disable pathname expansion before flags split'
Assert-Match $cmd 'unsafe arch_flags' 'reject unsafe raw architecture flags'
Assert-Match $cmd 'gzip' 'gzip requirement'
Assert-Match $cmd 'tar' 'tar requirement'
Assert-Match $cmd 'ARCHIVE_CREATE_TOOL=\$\(profile_value archive_create\)' 'archive creator parsed for preflight'
Assert-Match $cmd '"\$ARCHIVE_CREATE_TOOL"' 'archive creator included in executable preflight'
Assert-Match $cmd 'rsync' 'rsync requirement'
Assert-Match $cmd 'make' 'make requirement'
Assert-Match $cmd 'ln' 'ln requirement'
Assert-Match $cmd 'test -x /usr/bin/yacc' 'kernel config yacc requirement'
Assert-Match $cmd 'test -x /usr/bin/lex' 'kernel config lex requirement'
Assert-Match $cmd 'config\.tproj/parser\.y' 'kernel config parser source requirement'
Assert-Match $cmd 'config\.tproj/lexer\.l' 'kernel config lexer source requirement'
Assert-Match $cmd 'config\.tproj/config\.h' 'kernel config header source requirement'
Assert-Match $cmd 'migcom\.tproj' 'classic MIG source project requirement'
Assert-Match $cmd 'migcom_typd\.tproj' 'typed MIG source project requirement'
Assert-Match $cmd 'migcom_untypd\.tproj' 'untyped MIG source project requirement'
Assert-Match $cmd 'mig\.sh' 'MIG wrapper source requirement'
Assert-Match $cmd 'handler\.c' 'classic MIG unique source requirement'
Assert-Match $cmd 'migcom\.c' 'typed MIG unique source requirement'
Assert-Match $cmd 'test\.c' 'untyped MIG unique source requirement'
Assert-Match $cmd 'migcom_untypd_vers_stub\.c' 'untyped MIG version source requirement'
Assert-Match $cmd ([regex]::Escape('test -f "$SOURCE_ROOT/Commands/bootstrap_cmds/decomment.tproj/decomment.c" || fail "decomment source missing"')) 'preflight requires source-owned decomment implementation'
Assert-Match $cmd ([regex]::Escape('test -f "$SOURCE_ROOT/kernel-7/mach/mach.defs" || fail "MIG wrapper smoke definition missing"')) 'MIG smoke definition source requirement'
Assert-Match $cmd 'kernel-7/\$mig_header' 'MIG overlay preflight checks source-owned headers'
Assert-Match $cmd 'mach/message\.h.*mach/ppc/simple_lock\.h' 'MIG overlay preflight declares the verified header closure'
Assert-Match $cmd 'test -x /bin/mv' 'MIG generated header rename tool requirement'
Assert-Match $cmd 'TOOLS_DIR=' 'preflight binds configured private tools directory'
Assert-Match $cmd 'TOOL_PATH=\$\(profile_value path\)' 'preflight reads configured build PATH'
Assert-Match $cmd 'profile PATH must select private MIG wrapper first' 'preflight requires private MIG wrapper PATH priority'
Assert-Match $cmd '/usr/bin/tee' 'driver log streaming requirement'
Assert-Match $cmd '/usr/bin/cksum' 'driver state fingerprint requirement'
Assert-Match $cmd '/usr/bin/sed' 'driver state parser requirement'
Assert-Match $cmd 'test -f "\$tool".*test -x "\$tool"' 'configured executables must be files'
Assert-Match $cmd 'df -k' 'free space check'
Assert-Match $cmd ([regex]::Escape("awk '{ fields=NF; available=`$4 } END")) 'free space awk consumes vintage df records'
Assert-Match $cmd ([regex]::Escape("awk -v wanted=`"`$1`" 'BEGIN")) 'profile awk is protected from shell expansion'
Assert-Match $cmd 'trap' 'probe cleanup trap'
Assert-Match $cmd 'PROBE_PARENT=\$\(nearest_parent "\$BOOTSTRAP_ROOT"\)' 'case probe uses planned filesystem'
Assert-Match $cmd '/usr/bin/file "\$PROBE/target\.o"' 'target object architecture inspection'
Assert-Match $cmd 'Mach-O object \$TARGET_ARCH' 'target object profile architecture Mach-O requirement'
Assert-Match $cmd ([regex]::Escape('*"Mach-O object $TARGET_ARCH"|*"Mach-O object $TARGET_ARCH "*|*"Mach-O object $TARGET_ARCH,"*')) 'generated target object check requires an exact architecture token boundary'
Assert-NotMatch $cmd ([regex]::Escape('*"Mach-O object $TARGET_ARCH"*')) 'generated target object check rejects arbitrary architecture suffixes'
$machOBoundaryCommand = New-RhapMachOValidationCommand
$boundarySh = (Get-Command sh.exe -ErrorAction Stop).Source
$boundaryScript = Join-Path $env:TEMP ("rhap-macho-boundary-{0}.sh" -f [guid]::NewGuid().ToString('n'))
$boundaryScriptSh = ([System.IO.Path]::GetFullPath($boundaryScript) -replace '\\', '/')
if ($boundaryScriptSh -match '^([A-Za-z]):') { $boundaryScriptSh = '/' + $Matches[1].ToLowerInvariant() + $boundaryScriptSh.Substring(2) }
Set-Content -LiteralPath $boundaryScript -Encoding ASCII -NoNewline -Value ((@"
#!/bin/sh
fail() { exit 1; }
TARGET_FILE=`$1
TARGET_ARCH=`$2
$machOBoundaryCommand
"@) -replace "`r`n", "`n")
function Test-GeneratedMachOBoundary([string]$Text, [string]$Arch) {
    & $boundarySh $boundaryScriptSh $Text $Arch 2>$null
    return $LASTEXITCODE
}
try {
    Assert-Equal (Test-GeneratedMachOBoundary -Text '/tmp/probe.o: Mach-O object ppc' -Arch ppc) 0 'generated object check accepts exact PPC token at end'
    Assert-Equal (Test-GeneratedMachOBoundary -Text '/tmp/probe.o: Mach-O object ppc, flags' -Arch ppc) 0 'generated object check accepts comma-delimited PPC token'
    Assert-Equal (Test-GeneratedMachOBoundary -Text '/tmp/probe.o: Mach-O object i386 flags' -Arch i386) 0 'generated object check accepts space-delimited i386 token'
    Assert-Equal (Test-GeneratedMachOBoundary -Text '/tmp/probe.o: Mach-O object ppc64' -Arch ppc) 1 'generated object check rejects PPC prefix collision'
    Assert-Equal (Test-GeneratedMachOBoundary -Text '/tmp/probe.o: Mach-O object i386foo' -Arch i386) 1 'generated object check rejects i386 prefix collision'
} finally {
    Remove-Item -LiteralPath $boundaryScript -Force -ErrorAction SilentlyContinue
}

$decommentContractDir = Join-Path $env:TEMP ("rhap-decomment-contract-{0}" -f [guid]::NewGuid().ToString('n'))
New-Item -ItemType Directory -Path $decommentContractDir | Out-Null
try {
    $fallbackScript = Join-Path $decommentContractDir 'fallback.sh'
    $fakeUnifdef = Join-Path $decommentContractDir 'unifdef'
    $failingUnifdef = Join-Path $decommentContractDir 'unifdef-fail'
    $fakeDecomment = Join-Path $decommentContractDir 'decomment'
    $failingDecomment = Join-Path $decommentContractDir 'decomment-fail'
    $inputHeader = Join-Path $decommentContractDir 'input.h'
    $installMarker = Join-Path $decommentContractDir 'installed'
    $fallbackBody = @'
#!/bin/sh
UNIFDEF=$1
DECOMMENT=$2
INPUT=$3
OUT=$4
INSTALL=$5
(
    RAW="$OUT.raw"
    "$UNIFDEF" -UKERNEL_PRIVATE -UDRIVER_PRIVATE "$INPUT" > "$RAW"
    unifdef_status=$?
    if test "$unifdef_status" -eq 1; then
        "$DECOMMENT" "$RAW" r > "$OUT" || exit 1
    elif test "$unifdef_status" -ne 0; then
        exit 1
    fi
    test -s "$OUT" || exit 1
    : > "$INSTALL"
) || exit 1
'@
    $unifdefBody = @'
#!/bin/sh
input=
for arg do input=$arg; done
/bin/cat "$input"
exit 1
'@
    $failingUnifdefBody = @'
#!/bin/sh
input=
for arg do input=$arg; done
/bin/cat "$input"
exit 2
'@
    $decommentBody = @'
#!/bin/sh
if test -s "$1"; then /bin/cat "$1"; else printf '%s\n' 'int synthesized_header;'; fi
'@
    $failingBody = @'
#!/bin/sh
exit 7
'@
    Set-Content -LiteralPath $fallbackScript -Encoding ASCII -NoNewline -Value ($fallbackBody -replace "`r`n", "`n")
    Set-Content -LiteralPath $fakeUnifdef -Encoding ASCII -NoNewline -Value ($unifdefBody -replace "`r`n", "`n")
    Set-Content -LiteralPath $failingUnifdef -Encoding ASCII -NoNewline -Value ($failingUnifdefBody -replace "`r`n", "`n")
    Set-Content -LiteralPath $fakeDecomment -Encoding ASCII -NoNewline -Value ($decommentBody -replace "`r`n", "`n")
    Set-Content -LiteralPath $failingDecomment -Encoding ASCII -NoNewline -Value ($failingBody -replace "`r`n", "`n")
    Set-Content -LiteralPath $inputHeader -Encoding ASCII -Value 'int exported_header;'
    function ConvertTo-DecommentTestShPath([string]$Path) {
        $converted = ([System.IO.Path]::GetFullPath($Path) -replace '\\', '/')
        if ($converted -match '^([A-Za-z]):') { return '/' + $Matches[1].ToLowerInvariant() + $converted.Substring(2) }
        return $converted
    }
    $contractSh = ConvertTo-DecommentTestShPath $fallbackScript
    $unifdefSh = ConvertTo-DecommentTestShPath $fakeUnifdef
    $failingUnifdefSh = ConvertTo-DecommentTestShPath $failingUnifdef
    $decommentSh = ConvertTo-DecommentTestShPath $fakeDecomment
    $failingSh = ConvertTo-DecommentTestShPath $failingDecomment
    $inputSh = ConvertTo-DecommentTestShPath $inputHeader
    $outputSh = ConvertTo-DecommentTestShPath (Join-Path $decommentContractDir 'output.h')
    $installMarkerSh = ConvertTo-DecommentTestShPath $installMarker
    & $boundarySh $contractSh $unifdefSh $decommentSh $inputSh $outputSh $installMarkerSh
    Assert-Equal $LASTEXITCODE 0 'kernel export fallback accepts successful decomment output'
    Assert-Equal (Test-Path -LiteralPath $installMarker) $true 'kernel export fallback installs successful output'
    $savedErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'SilentlyContinue'
        Remove-Item -LiteralPath $installMarker -Force -ErrorAction SilentlyContinue
        & $boundarySh $contractSh $unifdefSh '/no/such/private/decomment' $inputSh $outputSh $installMarkerSh 2>$null
        $missingDecommentExit = $LASTEXITCODE
        & $boundarySh $contractSh $unifdefSh $failingSh $inputSh $outputSh $installMarkerSh 2>$null
        $failingDecommentExit = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $savedErrorActionPreference
    }
    Assert-Equal ($missingDecommentExit -ne 0) $true 'kernel export fallback rejects missing decomment tool'
    Assert-Equal ($failingDecommentExit -ne 0) $true 'kernel export fallback propagates decomment failure'
    Assert-Equal (Test-Path -LiteralPath $installMarker) $false 'failed decomment fallback cannot install a header'
    $savedErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'SilentlyContinue'
        & $boundarySh $contractSh $failingUnifdefSh $decommentSh $inputSh $outputSh $installMarkerSh 2>$null
        $unexpectedUnifdefExit = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $savedErrorActionPreference
    }
    Assert-Equal ($unexpectedUnifdefExit -ne 0) $true 'kernel export rejects unifdef status two even with partial output'
    Assert-Equal (Test-Path -LiteralPath $installMarker) $false 'unifdef status two cannot install a partial header'
    $savedErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'SilentlyContinue'
        & $boundarySh $contractSh '/no/such/private/unifdef' $decommentSh $inputSh $outputSh $installMarkerSh 2>$null
        $missingUnifdefExit = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $savedErrorActionPreference
    }
    Assert-Equal ($missingUnifdefExit -ne 0) $true 'kernel export rejects missing unifdef status 127'
    Assert-Equal (Test-Path -LiteralPath $installMarker) $false 'missing unifdef cannot install a synthesized header'

    $recipeScript = Join-Path $decommentContractDir 'export-recipe.sh'
    $mkdirOk = Join-Path $decommentContractDir 'mkdir-ok'
    $mkdirFail = Join-Path $decommentContractDir 'mkdir-fail'
    $installOk = Join-Path $decommentContractDir 'install-ok'
    $installFail = Join-Path $decommentContractDir 'install-fail'
    $pwdOk = Join-Path $decommentContractDir 'pwd-ok'
    $pwdFail = Join-Path $decommentContractDir 'pwd-fail'
    $spacedToolDir = Join-Path $decommentContractDir 'private tools'
    New-Item -ItemType Directory -Path $spacedToolDir | Out-Null
    $spacedDecomment = Join-Path $spacedToolDir 'decomment'
    $recipeBody = @'
#!/bin/sh
MKDIRS=$1
INSTALL=$2
DECOMMENT=$3
UNIFDEF=$4
INPUT=$5
ROOT=$6
ACCEPTED=$7
SENTINEL_MODE=$8
PWD_TOOL=$9
(
    object_dir=`"$PWD_TOOL" "$ROOT"` || exit 1
    EXPDIR="$object_dir/exports"
    DSTDIR="$object_dir/include"
    [ -d "$EXPDIR" ] || "$MKDIRS" "$EXPDIR" || exit 1
    rm -f "$EXPDIR"/* || exit 1
    [ -d "$DSTDIR" ] || "$MKDIRS" "$DSTDIR" || exit 1
    RAW="$EXPDIR/input.h"
    STRIP="$RAW.strip"
    if test "$SENTINEL_MODE" = fail; then /usr/bin/mkdir "$STRIP" || exit 1; fi
    echo garbage > "$STRIP" || exit 1
    "$UNIFDEF" "$INPUT" > "$RAW"
    unifdef_status=$?
    if test "$unifdef_status" -eq 1; then
        "$DECOMMENT" "$RAW" r > "$STRIP" || exit 1
    elif test "$unifdef_status" -ne 0; then
        exit 1
    fi
    if test -s "$STRIP"; then
        if ! "$INSTALL" "$RAW" "$DSTDIR/output.h"; then
            rm -f "$STRIP"
            exit 1
        fi
    fi
    rm -f "$STRIP" || exit 1
    : > "$ACCEPTED"
) || exit 1
'@
    $mkdirOkBody = @'
#!/bin/sh
/usr/bin/mkdir -p "$1"
'@
    $mkdirFailBody = @'
#!/bin/sh
exit 8
'@
    $installOkBody = @'
#!/bin/sh
/bin/cp "$1" "$2"
'@
    $installFailBody = @'
#!/bin/sh
exit 9
'@
    $pwdOkBody = @'
#!/bin/sh
printf '%s\n' "$1"
'@
    $pwdFailBody = @'
#!/bin/sh
exit 10
'@
    Set-Content -LiteralPath $recipeScript -Encoding ASCII -NoNewline -Value ($recipeBody -replace "`r`n", "`n")
    Set-Content -LiteralPath $mkdirOk -Encoding ASCII -NoNewline -Value ($mkdirOkBody -replace "`r`n", "`n")
    Set-Content -LiteralPath $mkdirFail -Encoding ASCII -NoNewline -Value ($mkdirFailBody -replace "`r`n", "`n")
    Set-Content -LiteralPath $installOk -Encoding ASCII -NoNewline -Value ($installOkBody -replace "`r`n", "`n")
    Set-Content -LiteralPath $installFail -Encoding ASCII -NoNewline -Value ($installFailBody -replace "`r`n", "`n")
    Set-Content -LiteralPath $pwdOk -Encoding ASCII -NoNewline -Value ($pwdOkBody -replace "`r`n", "`n")
    Set-Content -LiteralPath $pwdFail -Encoding ASCII -NoNewline -Value ($pwdFailBody -replace "`r`n", "`n")
    Copy-Item -LiteralPath $fakeDecomment -Destination $spacedDecomment
    $recipeSh = ConvertTo-DecommentTestShPath $recipeScript
    $mkdirOkSh = ConvertTo-DecommentTestShPath $mkdirOk
    $mkdirFailSh = ConvertTo-DecommentTestShPath $mkdirFail
    $installOkSh = ConvertTo-DecommentTestShPath $installOk
    $installFailSh = ConvertTo-DecommentTestShPath $installFail
    $pwdOkSh = ConvertTo-DecommentTestShPath $pwdOk
    $pwdFailSh = ConvertTo-DecommentTestShPath $pwdFail
    $spacedDecommentSh = ConvertTo-DecommentTestShPath $spacedDecomment
    $spacedSourceDir = Join-Path $decommentContractDir 'source root with spaces'
    New-Item -ItemType Directory -Path $spacedSourceDir | Out-Null
    $spacedInput = Join-Path $spacedSourceDir 'input header.h'
    Copy-Item -LiteralPath $inputHeader -Destination $spacedInput
    $spacedInputSh = ConvertTo-DecommentTestShPath $spacedInput
    $successRoot = Join-Path $decommentContractDir 'object root with spaces'
    $successRootSh = ConvertTo-DecommentTestShPath $successRoot
    $successAccepted = Join-Path $decommentContractDir 'success accepted'
    $successAcceptedSh = ConvertTo-DecommentTestShPath $successAccepted
    & $boundarySh $recipeSh $mkdirOkSh $installOkSh $spacedDecommentSh $unifdefSh $spacedInputSh $successRootSh $successAcceptedSh ok $pwdOkSh
    Assert-Equal $LASTEXITCODE 0 'kernel export recipe preserves spaced source, object, export, destination, and tool paths'
    Assert-Equal (Test-Path -LiteralPath $successAccepted) $true 'successful export recipe reaches acceptance marker'
    Assert-Equal (Test-Path -LiteralPath (Join-Path $successRoot 'include\output.h')) $true 'successful export recipe installs output'

    $mkdirFailRoot = Join-Path $decommentContractDir 'mkdir fail root'
    $mkdirFailAccepted = Join-Path $decommentContractDir 'mkdir fail accepted'
    & $boundarySh $recipeSh $mkdirFailSh $installOkSh $spacedDecommentSh $unifdefSh $spacedInputSh (ConvertTo-DecommentTestShPath $mkdirFailRoot) (ConvertTo-DecommentTestShPath $mkdirFailAccepted) ok $pwdOkSh 2>$null
    $mkdirFailExit = $LASTEXITCODE
    Assert-Equal ($mkdirFailExit -ne 0) $true 'kernel export recipe propagates MKDIRS failure'
    Assert-Equal (Test-Path -LiteralPath $mkdirFailAccepted) $false 'MKDIRS failure cannot reach acceptance marker'
    Assert-Equal (Test-Path -LiteralPath (Join-Path $mkdirFailRoot 'include\output.h')) $false 'MKDIRS failure cannot install output'

    $installFailRoot = Join-Path $decommentContractDir 'install fail root'
    $installFailAccepted = Join-Path $decommentContractDir 'install fail accepted'
    & $boundarySh $recipeSh $mkdirOkSh $installFailSh $spacedDecommentSh $unifdefSh $spacedInputSh (ConvertTo-DecommentTestShPath $installFailRoot) (ConvertTo-DecommentTestShPath $installFailAccepted) ok $pwdOkSh 2>$null
    $installFailExit = $LASTEXITCODE
    Assert-Equal ($installFailExit -ne 0) $true 'kernel export recipe propagates install failure'
    Assert-Equal (Test-Path -LiteralPath $installFailAccepted) $false 'install failure cannot reach acceptance marker'
    Assert-Equal (Test-Path -LiteralPath (Join-Path $installFailRoot 'include\output.h')) $false 'install failure cannot leave accepted output'

    $sentinelFailRoot = Join-Path $decommentContractDir 'sentinel fail root'
    $sentinelFailAccepted = Join-Path $decommentContractDir 'sentinel fail accepted'
    $savedErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'SilentlyContinue'
        & $boundarySh $recipeSh $mkdirOkSh $installOkSh $spacedDecommentSh $unifdefSh $spacedInputSh (ConvertTo-DecommentTestShPath $sentinelFailRoot) (ConvertTo-DecommentTestShPath $sentinelFailAccepted) fail $pwdOkSh 2>$null
        $sentinelFailExit = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $savedErrorActionPreference
    }
    Assert-Equal ($sentinelFailExit -ne 0) $true 'kernel export recipe propagates sentinel write failure'
    Assert-Equal (Test-Path -LiteralPath $sentinelFailAccepted) $false 'sentinel write failure cannot reach acceptance marker'
    Assert-Equal (Test-Path -LiteralPath (Join-Path $sentinelFailRoot 'include\output.h')) $false 'sentinel write failure cannot install output'

    $pwdFailRoot = Join-Path $decommentContractDir 'pwd fail root'
    $pwdFailAccepted = Join-Path $decommentContractDir 'pwd fail accepted'
    & $boundarySh $recipeSh $mkdirOkSh $installOkSh $spacedDecommentSh $unifdefSh $spacedInputSh (ConvertTo-DecommentTestShPath $pwdFailRoot) (ConvertTo-DecommentTestShPath $pwdFailAccepted) ok $pwdFailSh 2>$null
    $pwdFailExit = $LASTEXITCODE
    Assert-Equal ($pwdFailExit -ne 0) $true 'kernel export recipe propagates failed pwd capture'
    Assert-Equal (Test-Path -LiteralPath $pwdFailAccepted) $false 'failed pwd capture cannot reach acceptance marker'
    Assert-Equal (Test-Path -LiteralPath (Join-Path $pwdFailRoot 'exports')) $false 'failed pwd capture cannot create an export directory'
} finally {
    Remove-Item -LiteralPath $decommentContractDir -Recurse -Force -ErrorAction SilentlyContinue
}
Assert-NotMatch $cmd '(?m)(^|[;&|] *)mkdir +-p +/build/(tools|bootstrap-root|state)' 'does not create output roots'
Assert-NotMatch $cmd '(?m)(^|[;&|]\s*)(eval|source)\s' 'does not execute profile as code'
Assert-NotMatch $cmd '^sh -c ' 'does not nest through the login shell'

$quoted = New-RhapPreflightCommand -SourceRoot '/build/source tree' -ToolsDir '/build/source tree/tools' -BootstrapRoot '/build/source tree/root' -StateDir '/build/source tree/state' -Profile '/build/source tree/profile.conf'
Assert-Match $quoted ([regex]::Escape('source tree/profile.conf')) 'space-containing path is quoted'
Assert-Throws { New-RhapPreflightCommand -SourceRoot '/build/src;touch /tmp/x' -ToolsDir '/build/tools' -BootstrapRoot '/build/root' -StateDir '/build/state' -Profile '/build/profile' } 'reject control shell input'
Assert-Throws { New-RhapPreflightCommand -SourceRoot '/build/src' -ToolsDir '/build/tools' -BootstrapRoot '/build/root' -StateDir '/build/state' -Profile "/build/profile's.conf" } 'reject unsupported quote input'

$configDir = Join-Path $env:TEMP ("rhap-config-test-{0}" -f [guid]::NewGuid().ToString('n'))
New-Item -ItemType Directory -Path $configDir | Out-Null
try {
    Set-Content -LiteralPath (Join-Path $configDir 'vm.conf') -Encoding ASCII -Value @(
        'Host=example.invalid',
        'User=root',
        'Password=test',
        'RemoteRoot=/build'
    )
    $script:RhapVmDir = $configDir
    . (Join-Path $VmDir 'rhap-remote.ps1')
    $cfg = Get-RhapVmConfig -DiePrefix 'test-build-src'
    Assert-Equal $cfg.ToolsDir '/build/tools' 'default tools directory'
    Assert-Equal $cfg.BootstrapRoot '/build/bootstrap-root' 'default bootstrap root'
    Assert-Equal $cfg.StateDir '/build/state' 'default state directory'
    Assert-Equal $cfg.ToolchainProfile '/build/src/rbuild-1/toolchains/gcc-darwin.conf' 'relative profile resolution'

    Set-Content -LiteralPath (Join-Path $configDir 'vm.conf') -Encoding ASCII -Value @(
        'Host=example.invalid',
        'User=root',
        'Password=test',
        'RemoteRoot=////'
    )
    Assert-Throws { Get-RhapVmConfig -DiePrefix 'test-build-src' } 'reject filesystem root config'

    Set-Content -LiteralPath (Join-Path $configDir 'vm.conf') -Encoding ASCII -Value @(
        'Host=example.invalid',
        'User=root',
        'Password=test',
        'RemoteRoot=/build'
    )

    $transportDir = Join-Path $env:TEMP ("rhap-transport-test-{0}" -f [guid]::NewGuid().ToString('n'))
    $originalConsoleInputEncoding = Get-EncodingSignature ([Console]::InputEncoding)
    New-Item -ItemType Directory -Path $transportDir | Out-Null
    try {
        $captureSource = Join-Path $transportDir 'capture-stdin.c'
        $captureExe = Join-Path $transportDir 'capture-stdin.exe'
        Set-Content -LiteralPath $captureSource -Encoding ASCII -Value @(
            '#include <fcntl.h>',
            '#include <io.h>',
            '#include <stdio.h>',
            '#include <stdlib.h>',
            'int main(void) {',
            '    const char *path = getenv("RHAP_STDIN_CAPTURE");',
            '    const char *stdout_path = getenv("RHAP_STDIN_STDOUT_FILE");',
            '    const char *stdout_marker = getenv("RHAP_STDIN_STDOUT_MARKER");',
            '    unsigned char buffer[4096];',
            '    size_t count;',
            '    size_t i;',
            '    size_t position = 0;',
            '    int is_profile = 1;',
            '    const char profile_prefix[] = "set -e; /bin/cat ";',
            '    FILE *out;',
            '    FILE *in;',
            '    FILE *marker;',
            '    if (path == NULL || _setmode(_fileno(stdin), _O_BINARY) == -1) return 125;',
            '    out = fopen(path, "wb");',
            '    if (out == NULL) return 125;',
            '    while ((count = fread(buffer, 1, sizeof(buffer), stdin)) != 0) {',
            '        for (i = 0; i < count && position < sizeof(profile_prefix) - 1; ++i, ++position) {',
            '            if (buffer[i] != (unsigned char)profile_prefix[position]) is_profile = 0;',
            '        }',
            '        if (fwrite(buffer, 1, count, out) != count) return 125;',
            '    }',
            '    if (fclose(out) != 0) return 125;',
            '    if (is_profile && position == sizeof(profile_prefix) - 1 && stdout_path != NULL && stdout_marker != NULL) {',
            '        marker = fopen(stdout_marker, "rb");',
            '        if (marker == NULL) {',
            '            marker = fopen(stdout_marker, "wb");',
            '            if (marker == NULL || fclose(marker) != 0) return 125;',
            '            in = fopen(stdout_path, "rb");',
            '            if (in == NULL) return 125;',
            '            while ((count = fread(buffer, 1, sizeof(buffer), in)) != 0) {',
            '                if (fwrite(buffer, 1, count, stdout) != count) return 125;',
            '            }',
            '            if (fclose(in) != 0) return 125;',
            '        } else if (fclose(marker) != 0) return 125;',
            '    }',
            '    return 0;',
            '}'
        )
        & $clang -std=c89 -Wall -Wextra -Werror -D_CRT_SECURE_NO_WARNINGS -o $captureExe $captureSource
        Assert-Equal $LASTEXITCODE 0 'LLVM compiles remote stdin byte-capture fixture'

        foreach ($transportCase in @(
            [pscustomobject]@{ Name='preflight buffered transport'; Body=$cmd; Stream=$false },
            [pscustomobject]@{ Name='fresh streaming transport'; Body=$freshCommand; Stream=$true },
            [pscustomobject]@{ Name='phase streaming transport'; Body=$rbuildCommand; Stream=$true }
        )) {
            $capturePath = Join-Path $transportDir (($transportCase.Name -replace ' ', '-') + '.bin')
            $env:RHAP_STDIN_CAPTURE = $capturePath
            $transportExit = Invoke-RhapSshScript -Cfg $cfg -Ssh $captureExe -ScriptBody $transportCase.Body -Stream:$transportCase.Stream
            Assert-Equal $transportExit 0 "$($transportCase.Name) exit"
            Assert-RemotePayloadBytes -Path $capturePath -ScriptBody $transportCase.Body -Name $transportCase.Name
            $bytes = [System.IO.File]::ReadAllBytes($capturePath)
            Assert-Equal ([System.Text.Encoding]::ASCII.GetString($bytes, 0, 3)) 'set' "$($transportCase.Name) begins with set"
        }

        $profileTransportBody = New-RhapReadProfileCommand -Profile '/build/src/rbuild-1/toolchains/gcc-darwin.conf'
        $profileCapturePath = Join-Path $transportDir 'profile-capture.bin'
        $env:RHAP_STDIN_CAPTURE = $profileCapturePath
        $profileTransport = Invoke-RhapSshCapture -Cfg $cfg -Ssh $captureExe -ScriptBody $profileTransportBody
        Assert-Equal $profileTransport.ExitCode 0 'profile capture byte transport exit'
        Assert-RemotePayloadBytes -Path $profileCapturePath -ScriptBody $profileTransportBody -Name 'profile capture transport'

        $childCapturePath = Join-Path $transportDir 'child-file.bin'
        $childHarness = Join-Path $transportDir 'invoke-transport.ps1'
        $escapedRemote = (Join-Path $VmDir 'rhap-remote.ps1').Replace("'", "''")
        $escapedCaptureExe = $captureExe.Replace("'", "''")
        Set-Content -LiteralPath $childHarness -Encoding ASCII -Value @(
            "`$ErrorActionPreference = 'Stop'",
            ". '$escapedRemote'",
            "`$cfg = @{ User='root'; Host='example.invalid'; Password='test' }",
            ('$exitCode = Invoke-RhapSshScript -Cfg $cfg -Ssh ''{0}'' -ScriptBody "set -e`nprintf ''child''" -Stream' -f $escapedCaptureExe),
            "if (`$exitCode -ne 0) { exit `$exitCode }"
        )
        $env:RHAP_STDIN_CAPTURE = $childCapturePath
        & powershell -NoProfile -File $childHarness
        Assert-Equal $LASTEXITCODE 0 'no-profile file transport child exit'
        Assert-RemotePayloadBytes -Path $childCapturePath -ScriptBody "set -e`nprintf 'child'" -Name 'no-profile file transport'

        $canonicalVmDir = Join-Path $transportDir 'canonical-vm'
        New-Item -ItemType Directory -Path $canonicalVmDir | Out-Null
        foreach ($canonicalFile in @('build-src.ps1', 'build-src-lib.ps1', 'rhap-remote.ps1')) {
            Copy-Item -LiteralPath (Join-Path $VmDir $canonicalFile) -Destination $canonicalVmDir
        }
        Set-Content -LiteralPath (Join-Path $canonicalVmDir 'vm.conf') -Encoding ASCII -Value @(
            'Host=example.invalid',
            'User=root',
            'Password=test',
            'RemoteRoot=/build',
            "LocalRoot=$repoRoot",
            "Ssh=$captureExe"
        )
        $canonicalCapturePath = Join-Path $transportDir 'canonical-rbuild.bin'
        $env:RHAP_STDIN_CAPTURE = $canonicalCapturePath
        $env:RHAP_STDIN_STDOUT_FILE = Join-Path $repoRoot 'src\rbuild-1\toolchains\gcc-darwin.conf'
        $env:RHAP_STDIN_STDOUT_MARKER = Join-Path $transportDir 'canonical-profile-emitted'
        $canonicalOutput = & powershell -NoProfile -File (Join-Path $canonicalVmDir 'build-src.ps1') -Rbuild 2>&1
        Assert-Equal $LASTEXITCODE 0 "canonical build-src -Rbuild transport exit: $($canonicalOutput -join ' | ')"
        Assert-RemotePayloadBytes -Path $canonicalCapturePath -ScriptBody $rbuildCommand -Name 'canonical build-src rbuild phase transport'
        Assert-EncodingSignature (Get-EncodingSignature ([Console]::InputEncoding)) $originalConsoleInputEncoding 'normal remote transport restores host console input encoding'

        $startFailureProcess = New-Object System.Diagnostics.Process
        $startFailureInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startFailureInfo.FileName = Join-Path $transportDir 'missing-ssh.exe'
        $startFailureInfo.UseShellExecute = $false
        $startFailureInfo.RedirectStandardInput = $true
        $startFailureProcess.StartInfo = $startFailureInfo
        try {
            Assert-Throws { Start-RhapSshProcess -Process $startFailureProcess -Ssh $startFailureInfo.FileName } 'SSH start failure is reported'
        } finally {
            $startFailureProcess.Dispose()
        }
        Assert-EncodingSignature (Get-EncodingSignature ([Console]::InputEncoding)) $originalConsoleInputEncoding 'SSH start failure restores host console input encoding'

        $acquisitionFailureProcess = New-Object System.Diagnostics.Process
        $acquisitionFailureInfo = New-Object System.Diagnostics.ProcessStartInfo
        $acquisitionFailureInfo.FileName = $captureExe
        $acquisitionFailureInfo.UseShellExecute = $false
        $acquisitionFailureInfo.RedirectStandardInput = $false
        $acquisitionFailureProcess.StartInfo = $acquisitionFailureInfo
        $acquisitionFailureMessage = $null
        $acquisitionFailureExited = $false
        try {
            try {
                [void](Start-RhapSshProcess -Process $acquisitionFailureProcess -Ssh $captureExe)
            } catch {
                $acquisitionFailureMessage = $_.Exception.Message
            }
            $acquisitionFailureExited = $acquisitionFailureProcess.HasExited
        } finally {
            $acquisitionFailureProcess.Dispose()
        }
        Assert-Match $acquisitionFailureMessage '^could not acquire SSH standard input:' 'stdin writer acquisition failure is reported clearly'
        Assert-Equal $acquisitionFailureExited $true 'stdin writer acquisition failure reaps the started child'
        Assert-EncodingSignature (Get-EncodingSignature ([Console]::InputEncoding)) $originalConsoleInputEncoding 'stdin writer acquisition failure restores host console input encoding'

        $badPayload = 'set -e' + "`n# " + [char]0xD800
        $env:RHAP_STDIN_CAPTURE = Join-Path $transportDir 'malformed.bin'
        Assert-Throws { Invoke-RhapSshScript -Cfg $cfg -Ssh $captureExe -ScriptBody $badPayload } 'remote transport rejects malformed UTF-16'
    } finally {
        Remove-Item Env:RHAP_STDIN_CAPTURE -ErrorAction SilentlyContinue
        Remove-Item Env:RHAP_STDIN_STDOUT_FILE -ErrorAction SilentlyContinue
        Remove-Item Env:RHAP_STDIN_STDOUT_MARKER -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $transportDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    $capture = @{}
    $fakeSsh = {
        param($Executable, $Arguments, $StdinBody)
        $capture.Executable = $Executable
        $capture.Arguments = @($Arguments)
        $capture.StdinBody = $StdinBody
        return 23
    }
    $fakeBody = "printf 'one'`r`nprintf 'two'"
    $fakeExit = Invoke-RhapSshScript -Cfg $cfg -Ssh 'fake-ssh.exe' -ScriptBody $fakeBody -Invoker $fakeSsh
    Assert-Equal $fakeExit 23 'script helper preserves exit status'
    Assert-Equal $capture.Executable 'fake-ssh.exe' 'script helper executable'
    Assert-Equal $capture.Arguments[-1] '/bin/sh -s' 'minimal remote shell argv'
    Assert-Equal (@($capture.Arguments | Where-Object { $_ -eq '/bin/sh -s' }).Count) 1 'one remote shell command'
    Assert-Equal $capture.StdinBody "printf 'one'`nprintf 'two'`n" 'exact LF-normalized stdin body'

    $streamEvents = New-Object System.Collections.Generic.List[string]
    $streamInvoker = {
        param($Executable, $Arguments, $StdinBody, $Streaming, $EmitStdout, $EmitStderr)
        Assert-Equal $Streaming $true 'stream invoker mode'
        & $EmitStdout 'early stdout'
        & $EmitStderr 'early stderr'
        $streamEvents.Add('exit')
        return 29
    }
    $streamObserver = { param($Kind, $Line) $streamEvents.Add("$Kind`:$Line") }
    $streamExit = Invoke-RhapSshScript -Cfg $cfg -Ssh 'fake-ssh.exe' -ScriptBody 'build' -Invoker $streamInvoker -Stream -Observer $streamObserver
    Assert-Equal $streamExit 29 'stream helper preserves failure exit'
    Assert-Equal ($streamEvents -join ',') 'stdout:early stdout,stderr:early stderr,exit' 'stream output observed before process exit'

    $remoteProfile = $realProfile -replace '(?m)^build_cc=.*$', 'build_cc=/remote/bin/gcc'
    $captureInvoker = {
        param($Executable, $Arguments, $StdinBody)
        $capture.ProfileBody = $StdinBody
        return [pscustomobject]@{ ExitCode = 0; Stdout = $remoteProfile; Stderr = '' }
    }
    $profileResult = Invoke-RhapSshCapture -Cfg $cfg -Ssh 'fake-ssh.exe' -ScriptBody (New-RhapReadProfileCommand -Profile '/opt/profiles/gcc.conf') -Invoker $captureInvoker
    Assert-Equal $profileResult.ExitCode 0 'profile capture exit'
    Assert-Match $capture.ProfileBody ([regex]::Escape("/bin/cat '/opt/profiles/gcc.conf'")) 'profile capture reads absolute remote path'
    $remoteValues = ConvertFrom-RhapToolchainProfileText -Text $profileResult.Stdout
    Assert-Equal $remoteValues.build_cc '/remote/bin/gcc' 'remote profile contents are authoritative'

    Set-Content -LiteralPath (Join-Path $configDir 'vm.conf') -Encoding ASCII -Value @(
        'Host=example.invalid',
        'User=root',
        'Password=test',
        'RemoteRoot=/srv/rhapsodios',
        'ToolsDir=/srv/rhapsodios/custom-tools',
        'BootstrapRoot=/srv/rhapsodios/custom-root',
        'StateDir=/srv/rhapsodios/custom-state',
        'ToolchainProfile=/opt/profiles/gcc.conf'
    )
    $cfg = Get-RhapVmConfig -DiePrefix 'test-build-src'
    Assert-Equal $cfg.ToolsDir '/srv/rhapsodios/custom-tools' 'tools override'
    Assert-Equal $cfg.BootstrapRoot '/srv/rhapsodios/custom-root' 'bootstrap override'
    Assert-Equal $cfg.StateDir '/srv/rhapsodios/custom-state' 'state override'
    Assert-Equal $cfg.ToolchainProfile '/opt/profiles/gcc.conf' 'absolute profile preserved'
} finally {
    Remove-Item -LiteralPath $configDir -Recurse -Force -ErrorAction SilentlyContinue
}

$wrapperTestDir = Join-Path $env:TEMP ("mig wrapper test {0}" -f [guid]::NewGuid().ToString('n'))
New-Item -ItemType Directory -Path $wrapperTestDir | Out-Null
$previousMigArch = $env:MIGARCH
$env:MIGARCH = 'ppc'
try {
    function ConvertTo-TestShPath([string]$Path) {
        $resolved = [System.IO.Path]::GetFullPath($Path) -replace '\\', '/'
        if ($resolved -match '^([A-Za-z]):') {
            return '/' + $Matches[1].ToLowerInvariant() + $resolved.Substring(2)
        }
        return $resolved
    }

    $fakeBin = Join-Path $wrapperTestDir 'gcc tools'
    $fakeLibexec = Join-Path $wrapperTestDir 'mig libexec'
    $captureDir = Join-Path $wrapperTestDir 'argument capture'
    $definitionDir = Join-Path $wrapperTestDir 'source definitions'
    $outputDir = Join-Path $wrapperTestDir 'generated output'
    $runDir = Join-Path $wrapperTestDir 'current build directory'
    foreach ($dir in @($fakeBin, $fakeLibexec, $captureDir, $definitionDir, $outputDir, $runDir)) {
        New-Item -ItemType Directory -Path $dir | Out-Null
    }
    $fakeCompiler = Join-Path $fakeBin 'gcc'
    $fakeBackend = Join-Path $fakeLibexec 'migcom'
    $fakeCompilerBody = @'
#!/bin/sh
for arg do printf '%s\n' "$arg" >> "$MIG_TEST_CAPTURE/compiler.args"; done
printf '%s\n' '--invocation--' >> "$MIG_TEST_CAPTURE/compiler.args"
language=
input=
target_arch=
typed=
while test $# -gt 0; do
    case $1 in
        -x) shift; language=$1 ;;
        -Dppc|-Dalternate_safe) target_arch=$1 ;;
        -DMACH_IPC_FLAVOR=TYPED) typed=yes ;;
        *.defs) input=$1 ;;
    esac
    shift
done
if test -n "${MIGCC-}"; then test "$language" = c || exit 91; fi
test -f "$input" || exit 92
case $input in
    */kernel-7/mach/mach.defs)
        test "$target_arch" = -Dppc || exit 95
        test "$typed" = yes || exit 96
        ;;
esac
if test "${MIG_TEST_CPP_MODE-}" = fail; then
    printf '%s\n' 'partial preprocessor output'
    exit 42
fi
if test "${MIG_TEST_CPP_MODE-}" = signal; then
    kill -TERM "$PPID"
    printf '%s\n' 'partial signaled output'
    exit 0
fi
while IFS= read -r line || test -n "$line"; do printf '%s\n' "$line"; done < "$input"
'@
    $fakeBackendBody = @'
#!/bin/sh
for arg do printf '%s\n' "$arg" >> "$MIG_TEST_CAPTURE/backend.args"; done
printf '%s\n' '--invocation--' >> "$MIG_TEST_CAPTURE/backend.args"
header=
user=
while test $# -gt 0; do
    case $1 in
        -header) shift; header=$1 ;;
        -user) shift; user=$1 ;;
    esac
    shift
done
test -n "$header" || exit 93
if test "${MIG_TEST_BACKEND_MODE-}" = fail; then exit 94; fi
while IFS= read -r line || test -n "$line"; do printf '%s\n' "$line"; done > "$header"
test -z "$user" || printf '%s\n' 'generated user' > "$user"
'@
    Set-Content -LiteralPath $fakeCompiler -Encoding ASCII -NoNewline -Value ($fakeCompilerBody -replace "`r`n", "`n")
    Set-Content -LiteralPath $fakeBackend -Encoding ASCII -NoNewline -Value ($fakeBackendBody -replace "`r`n", "`n")
    Copy-Item -LiteralPath $fakeBackend -Destination (Join-Path $fakeLibexec 'migcom_typd')
    Copy-Item -LiteralPath $fakeBackend -Destination (Join-Path $fakeLibexec 'migcom_untypd')
    $fakeMkdir = Join-Path $fakeBin 'mkdir'
    $fakeMkdirBody = @'
#!/bin/sh
/usr/bin/mkdir "$@" || exit $?
printf '%s\n' signaled > "$MIG_TEST_CAPTURE/mkdir.signal"
kill -TERM "$PPID"
exit 0
'@
    Set-Content -LiteralPath $fakeMkdir -Encoding ASCII -NoNewline -Value ($fakeMkdirBody -replace "`r`n", "`n")
    $defsOne = Join-Path $definitionDir 'first interface.defs'
    $defsTwo = Join-Path $definitionDir 'second interface.defs'
    Set-Content -LiteralPath $defsOne -Encoding ASCII -Value 'subsystem first_contract 4100;'
    Set-Content -LiteralPath $defsTwo -Encoding ASCII -Value 'subsystem second_contract 4101;'
    $headerOutput = Join-Path $outputDir 'public header.h'
    $userOutput = Join-Path $outputDir 'user source.c'
    $serverHeader = Join-Path $outputDir 'server header.h'
    $handlerOutput = Join-Path $outputDir 'handler source.c'
    $prefix = Join-Path $outputDir 'routine prefix'
    $sh = (Get-Command sh.exe -ErrorAction Stop).Source
    $wrapperArgs = @(
        '-header', (ConvertTo-TestShPath $headerOutput),
        '-user', (ConvertTo-TestShPath $userOutput),
        '-sheader', (ConvertTo-TestShPath $serverHeader),
        '-handler', (ConvertTo-TestShPath $handlerOutput),
        '-i', (ConvertTo-TestShPath $prefix),
        '-DVALUE=two words',
        (ConvertTo-TestShPath $defsOne),
        (ConvertTo-TestShPath $defsTwo)
    )
    $quotedWrapperArgs = ($wrapperArgs | ForEach-Object { ConvertTo-RhapShellLiteral $_ }) -join ' '
    $invoke = 'cd {0} && MIGCC={1} MIGCOM_DIR={2} MIG_TEST_CAPTURE={3} sh {4} {5}' -f @(
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $runDir)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $fakeCompiler)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $fakeLibexec)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $captureDir)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath (Join-Path $repoRoot 'src\Commands\bootstrap_cmds\migcom.tproj\mig.sh'))),
        $quotedWrapperArgs
    )
    & $sh -c $invoke
    Assert-Equal $LASTEXITCODE 0 'MIG wrapper executes configured GCC and backend with spaced paths'
    Assert-Equal (Test-Path -LiteralPath $headerOutput) $true 'MIG wrapper generates requested spaced header output'
    Assert-Equal (Test-Path -LiteralPath $userOutput) $true 'MIG wrapper generates requested spaced user output'
    $compilerArgs = Get-Content -LiteralPath (Join-Path $captureDir 'compiler.args')
    $backendArgs = Get-Content -LiteralPath (Join-Path $captureDir 'backend.args')
    Assert-Equal (@($compilerArgs | Where-Object { $_ -eq '-DVALUE=two words' }).Count) 2 'MIG wrapper preserves spaced cpp flag for multiple definitions'
    Assert-Equal (@($compilerArgs | Where-Object { $_ -eq '-Dppc' }).Count) 2 'MIG wrapper adds one configured architecture definition per compiler invocation'
    Assert-Equal (@($compilerArgs | Where-Object { $_ -eq '--invocation--' }).Count) 2 'MIG wrapper preprocesses multiple definitions'
    Assert-Equal (@($backendArgs | Where-Object { $_ -eq (ConvertTo-TestShPath $headerOutput) }).Count) 2 'MIG wrapper preserves spaced backend header value'
    Assert-Equal (@($backendArgs | Where-Object { $_ -eq (ConvertTo-TestShPath $prefix) }).Count) 2 'MIG wrapper preserves spaced optional -i prefix'
    Assert-Equal (@($backendArgs | Where-Object { $_ -eq '--invocation--' }).Count) 2 'MIG wrapper invokes backend for multiple definitions'
    $iflagCaptureDir = Join-Path $wrapperTestDir 'iflag argument capture'
    New-Item -ItemType Directory -Path $iflagCaptureDir | Out-Null
    $iflagHeader = Join-Path $outputDir 'kernloader header.h'
    $iflagInvoke = 'cd {0} && MIGCC={1} MIGARCH=ppc MIGCOM_DIR={2} MIG_TEST_CAPTURE={3} sh {4} -header {5} -i -server /dev/null {6}' -f @(
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $runDir)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $fakeCompiler)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $fakeLibexec)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $iflagCaptureDir)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath (Join-Path $repoRoot 'src\Commands\bootstrap_cmds\migcom.tproj\mig.sh'))),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $iflagHeader)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $defsOne))
    )
    & $sh -c $iflagInvoke
    Assert-Equal $LASTEXITCODE 0 'MIG wrapper keeps -server after bare -i'
    $iflagCompilerArgs = Get-Content -LiteralPath (Join-Path $iflagCaptureDir 'compiler.args')
    $iflagBackendArgs = Get-Content -LiteralPath (Join-Path $iflagCaptureDir 'backend.args')
    Assert-Equal (@($iflagCompilerArgs | Where-Object { $_ -eq (ConvertTo-TestShPath $defsOne) }).Count) 1 'bare -i still preprocesses the defs file once'
    Assert-Equal (@($iflagCompilerArgs | Where-Object { $_ -eq '/dev/null' }).Count) 0 'bare -i does not preprocess /dev/null as a defs file'
    Assert-Equal (@($iflagBackendArgs | Where-Object { $_ -eq '-server' }).Count) 1 'bare -i forwards -server to the backend'
    Assert-Equal (@($iflagBackendArgs | Where-Object { $_ -eq '/dev/null' }).Count) 1 'bare -i forwards /dev/null as the -server operand'
    Assert-Equal (@($iflagBackendArgs | Where-Object { $_ -eq '--invocation--' }).Count) 1 'bare -i invokes the backend once'
    $newlineFlag = "-DBAD=line one`nline two"
    $newlineInvoke = 'MIGCC={0} MIGCOM_DIR={1} MIG_TEST_CAPTURE={2} sh {3} {4} {5} 2>/dev/null' -f @(
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $fakeCompiler)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $fakeLibexec)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $captureDir)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath (Join-Path $repoRoot 'src\Commands\bootstrap_cmds\migcom.tproj\mig.sh'))),
        (ConvertTo-RhapShellLiteral $newlineFlag),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $defsOne))
    )
    & $sh -c $newlineInvoke
    Assert-Equal $LASTEXITCODE 1 'MIG wrapper rejects embedded newlines before execution'
    Assert-Equal (@((Get-Content -LiteralPath (Join-Path $captureDir 'compiler.args')) | Where-Object { $_ -eq '--invocation--' }).Count) 2 'newline rejection does not invoke configured compiler'

    $wrapperShPath = ConvertTo-TestShPath (Join-Path $repoRoot 'src\Commands\bootstrap_cmds\migcom.tproj\mig.sh')
    $operandResults = Join-Path $captureDir 'operand.results'
    $operandContractBody = @'
status=0
empty=
: > "$MIG_OPERAND_RESULTS"
for required_option in -user -server -header -sheader -handler -arch; do
    if (set -- "$required_option"; . "$MIG_WRAPPER") 2>/dev/null; then result=FAIL; status=1; else result=PASS; fi
    printf "%s missing %s\n" "$required_option" "$result" >> "$MIG_OPERAND_RESULTS"
    if (set -- "$required_option" "$empty"; . "$MIG_WRAPPER") 2>/dev/null; then result=FAIL; status=1; else result=PASS; fi
    printf "%s empty %s\n" "$required_option" "$result" >> "$MIG_OPERAND_RESULTS"
    if (set -- "$required_option" -q "$MIG_DEFS"; . "$MIG_WRAPPER") 2>/dev/null; then result=FAIL; status=1; else result=PASS; fi
    printf "%s option %s\n" "$required_option" "$result" >> "$MIG_OPERAND_RESULTS"
done
exit $status
'@
    $operandScript = Join-Path $wrapperTestDir 'operand contract.sh'
    Set-Content -LiteralPath $operandScript -Encoding ASCII -NoNewline -Value ($operandContractBody -replace "`r`n", "`n")
    $operandInvoke = 'cd {0} && MIGCC={1} MIGCOM_DIR={2} MIG_TEST_CAPTURE={3} MIG_WRAPPER={4} MIG_DEFS={5} MIG_OPERAND_RESULTS={6} sh {7}' -f @(
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $runDir)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $fakeCompiler)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $fakeLibexec)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $captureDir)),
        (ConvertTo-RhapShellLiteral $wrapperShPath),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $defsOne)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $operandResults)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $operandScript))
    )
    & $sh -c $operandInvoke
    Assert-Equal $LASTEXITCODE 0 'MIG wrapper rejects every invalid required operand form'
    $operandResultLines = Get-Content -LiteralPath $operandResults
    Assert-Equal $operandResultLines.Count 18 'MIG wrapper exercises missing, empty, and option operands for every required option'
    Assert-Equal (@($operandResultLines | Where-Object { $_ -notmatch ' PASS$' }).Count) 0 'MIG wrapper invalid operand cases all return nonzero'
    Assert-Equal (@((Get-Content -LiteralPath (Join-Path $captureDir 'compiler.args')) | Where-Object { $_ -eq '--invocation--' }).Count) 2 'invalid required operands do not invoke configured compiler'

    $failedConfiguredOutput = Join-Path $outputDir 'configured failure header.h'
    $configuredFailureInvoke = 'cd {0} && MIGCC={1} MIGCOM_DIR={2} MIG_TEST_CAPTURE={3} MIG_TEST_CPP_MODE=fail sh {4} -header {5} {6} 2>/dev/null' -f @(
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $runDir)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $fakeCompiler)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $fakeLibexec)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $captureDir)),
        (ConvertTo-RhapShellLiteral $wrapperShPath),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $failedConfiguredOutput)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $defsOne))
    )
    & $sh -c $configuredFailureInvoke
    Assert-Equal ($LASTEXITCODE -ne 0) $true 'MIG wrapper propagates configured compiler failure'
    Assert-Equal (Test-Path -LiteralPath $failedConfiguredOutput) $false 'configured compiler partial output never reaches backend output'
    Assert-Equal (@((Get-Content -LiteralPath (Join-Path $captureDir 'backend.args')) | Where-Object { $_ -eq '--invocation--' }).Count) 2 'configured compiler failure does not invoke backend'
    Assert-Equal (@(Get-ChildItem -LiteralPath $runDir -Force | Where-Object { $_.Name -like '*.migcpp.*' }).Count) 0 'configured compiler failure removes staged preprocessing output'

    $failedBackendOutput = Join-Path $outputDir 'backend failure header.h'
    $backendFailureInvoke = 'cd {0} && MIGCC={1} MIGCOM_DIR={2} MIG_TEST_CAPTURE={3} MIG_TEST_BACKEND_MODE=fail sh {4} -header {5} {6} 2>/dev/null' -f @(
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $runDir)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $fakeCompiler)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $fakeLibexec)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $captureDir)),
        (ConvertTo-RhapShellLiteral $wrapperShPath),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $failedBackendOutput)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $defsOne))
    )
    & $sh -c $backendFailureInvoke
    Assert-Equal ($LASTEXITCODE -ne 0) $true 'MIG wrapper propagates backend failure'
    Assert-Equal (Test-Path -LiteralPath $failedBackendOutput) $false 'backend failure does not report a generated output'
    Assert-Equal (@(Get-ChildItem -LiteralPath $runDir -Force | Where-Object { $_.Name -like '*.migcpp.*' }).Count) 0 'backend failure removes staged preprocessing output'

    $collisionResults = Join-Path $captureDir 'collision.results'
    $collisionFileOutput = Join-Path $outputDir 'collision file header.h'
    $collisionDirOutput = Join-Path $outputDir 'collision dir header.h'
    $collisionDanglingOutput = Join-Path $outputDir 'collision dangling header.h'
    $collisionLiveOutput = Join-Path $outputDir 'collision live header.h'
    $backendCountBeforeCollision = @((Get-Content -LiteralPath (Join-Path $captureDir 'backend.args')) | Where-Object { $_ -eq '--invocation--' }).Count
    $collisionContractBody = @'
status=0
: > "$MIG_COLLISION_RESULTS"
candidate="./.first interface.migcpp.$$.$MIG_SEQUENCE.d"
check_failure()
{
    if (set -- -header "$1" "$MIG_DEFS"; . "$MIG_WRAPPER") 2>/dev/null
    then
        printf "%s FAIL\n" "$2" >> "$MIG_COLLISION_RESULTS"
        status=1
    else
        printf "%s PASS\n" "$2" >> "$MIG_COLLISION_RESULTS"
    fi
}

printf "%s\n" original > "$candidate"
check_failure "$MIG_FILE_OUTPUT" file
test "$(/bin/cat "$candidate")" = original || status=1
rm -f "$candidate"

mkdir "$candidate"
printf "%s\n" sentinel > "$candidate/sentinel"
check_failure "$MIG_DIR_OUTPUT" dir
test "$(/bin/cat "$candidate/sentinel")" = sentinel || status=1
rm -f "$candidate/sentinel"
rmdir "$candidate"

mkdir dangling-target
/c/Windows/System32/cmd.exe //d //c mklink //J "$candidate" dangling-target >/dev/null || exit 1
rmdir dangling-target
check_failure "$MIG_DANGLING_OUTPUT" dangling
if mkdir "$candidate" 2>/dev/null; then status=1; rmdir "$candidate"; fi
/c/Windows/System32/cmd.exe //d //c rmdir "$candidate" >/dev/null || status=1

mkdir live-target
printf "%s\n" live > live-target/sentinel
/c/Windows/System32/cmd.exe //d //c mklink //J "$candidate" live-target >/dev/null || exit 1
check_failure "$MIG_LIVE_OUTPUT" live
test "$(/bin/cat live-target/sentinel)" = live || status=1
if mkdir "$candidate" 2>/dev/null; then status=1; rmdir "$candidate"; fi
/c/Windows/System32/cmd.exe //d //c rmdir "$candidate" >/dev/null || status=1
rm -f live-target/sentinel
rmdir live-target
exit $status
'@
    $collisionScript = Join-Path $wrapperTestDir 'collision contract.sh'
    Set-Content -LiteralPath $collisionScript -Encoding ASCII -NoNewline -Value ($collisionContractBody -replace "`r`n", "`n")
    $collisionInvoke = 'cd {0} && MIGCC={1} MIGCOM_DIR={2} MIG_TEST_CAPTURE={3} MIG_WRAPPER={4} MIG_DEFS={5} MIG_SEQUENCE=x MIG_COLLISION_RESULTS={6} MIG_FILE_OUTPUT={7} MIG_DIR_OUTPUT={8} MIG_DANGLING_OUTPUT={9} MIG_LIVE_OUTPUT={10} sh {11}' -f @(
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $runDir)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $fakeCompiler)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $fakeLibexec)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $captureDir)),
        (ConvertTo-RhapShellLiteral $wrapperShPath),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $defsOne)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $collisionResults)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $collisionFileOutput)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $collisionDirOutput)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $collisionDanglingOutput)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $collisionLiveOutput)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $collisionScript))
    )
    & $sh -c $collisionInvoke
    Assert-Equal $LASTEXITCODE 0 'MIG wrapper preserves every unowned staging collision'
    $collisionResultLines = Get-Content -LiteralPath $collisionResults
    Assert-Equal $collisionResultLines.Count 4 'MIG wrapper exercises file, directory, dangling, and live link collisions'
    Assert-Equal (@($collisionResultLines | Where-Object { $_ -notmatch ' PASS$' }).Count) 0 'MIG wrapper rejects every staging collision'
    Assert-Equal (@((Get-Content -LiteralPath (Join-Path $captureDir 'backend.args')) | Where-Object { $_ -eq '--invocation--' }).Count) $backendCountBeforeCollision 'MIG staging collisions never invoke backend'
    foreach ($collisionOutput in @($collisionFileOutput, $collisionDirOutput, $collisionDanglingOutput, $collisionLiveOutput)) {
        Assert-Equal (Test-Path -LiteralPath $collisionOutput) $false "MIG staging collision leaves output absent: $collisionOutput"
    }

    $transitionOutput = Join-Path $outputDir 'ownership transition header.h'
    $transitionInvoke = 'cd {0} && PATH={1}:/usr/bin:/bin MIGCC={2} MIGCOM_DIR={3} MIG_TEST_CAPTURE={4} sh {5} -header {6} {7} 2>/dev/null' -f @(
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $runDir)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $fakeBin)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $fakeCompiler)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $fakeLibexec)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $captureDir)),
        (ConvertTo-RhapShellLiteral $wrapperShPath),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $transitionOutput)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $defsOne))
    )
    & $sh -c $transitionInvoke
    Assert-Equal $LASTEXITCODE 0 'MIG wrapper survives a signal during mkdir ownership transition'
    Assert-Equal (Test-Path -LiteralPath (Join-Path $captureDir 'mkdir.signal')) $true 'MIG ownership transition test delivers its signal'
    Assert-Equal (Test-Path -LiteralPath $transitionOutput) $true 'MIG wrapper generates output after protected ownership transition'
    Assert-Equal (@(Get-ChildItem -LiteralPath $runDir -Force | Where-Object { $_.Name -like '*.migcpp.*' }).Count) 0 'ownership transition signal leaves no staged directory'

    $signalOutput = Join-Path $outputDir 'owned signal header.h'
    $signalInvoke = 'cd {0} && MIGCC={1} MIGCOM_DIR={2} MIG_TEST_CAPTURE={3} MIG_TEST_CPP_MODE=signal sh {4} -header {5} {6} 2>/dev/null' -f @(
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $runDir)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $fakeCompiler)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $fakeLibexec)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $captureDir)),
        (ConvertTo-RhapShellLiteral $wrapperShPath),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $signalOutput)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $defsOne))
    )
    & $sh -c $signalInvoke
    Assert-Equal ($LASTEXITCODE -ne 0) $true 'MIG wrapper propagates signal after staging ownership'
    Assert-Equal (Test-Path -LiteralPath $signalOutput) $false 'owned-stage signal never reaches backend output'
    Assert-Equal (@(Get-ChildItem -LiteralPath $runDir -Force | Where-Object { $_.Name -like '*.migcpp.*' }).Count) 0 'owned-stage signal cleanup leaves no staged directory'

    $archCountBeforeDefault = @((Get-Content -LiteralPath (Join-Path $captureDir 'compiler.args')) | Where-Object { $_ -eq '-Dppc' }).Count
    $defaultOutput = Join-Path $outputDir 'default cpp header.h'
    $defaultInvoke = 'unset MIGCC; cd {0} && MIGCPP={1} MIGCOM_DIR={2} MIG_TEST_CAPTURE={3} sh {4} -header {5} {6}' -f @(
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $runDir)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $fakeCompiler)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $fakeLibexec)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $captureDir)),
        (ConvertTo-RhapShellLiteral $wrapperShPath),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $defaultOutput)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $defsOne))
    )
    & $sh -c $defaultInvoke
    Assert-Equal $LASTEXITCODE 0 'MIG wrapper default cpp branch executes successfully'
    Assert-Equal (Test-Path -LiteralPath $defaultOutput) $true 'MIG wrapper default cpp branch generates requested output'
    $failedDefaultOutput = Join-Path $outputDir 'default failure header.h'
    $defaultFailureInvoke = 'unset MIGCC; cd {0} && MIGCPP={1} MIGCOM_DIR={2} MIG_TEST_CAPTURE={3} MIG_TEST_CPP_MODE=fail sh {4} -header {5} {6} 2>/dev/null' -f @(
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $runDir)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $fakeCompiler)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $fakeLibexec)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $captureDir)),
        (ConvertTo-RhapShellLiteral $wrapperShPath),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $failedDefaultOutput)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $defsOne))
    )
    & $sh -c $defaultFailureInvoke
    Assert-Equal ($LASTEXITCODE -ne 0) $true 'MIG wrapper propagates default cpp failure'
    Assert-Equal (Test-Path -LiteralPath $failedDefaultOutput) $false 'default cpp partial output never reaches backend output'
    Assert-Equal (@(Get-ChildItem -LiteralPath $runDir -Force | Where-Object { $_.Name -like '*.migcpp.*' }).Count) 0 'default cpp failure removes staged preprocessing output'
    $archCountAfterDefault = @((Get-Content -LiteralPath (Join-Path $captureDir 'compiler.args')) | Where-Object { $_ -eq '-Dppc' }).Count
    Assert-Equal $archCountAfterDefault $archCountBeforeDefault 'historical no-MIGCC cpp branch ignores configured MIGARCH'

    $compilerCountBeforeInvalidArch = @((Get-Content -LiteralPath (Join-Path $captureDir 'compiler.args')) | Where-Object { $_ -eq '--invocation--' }).Count
    foreach ($badArch in @('ppc;touch_bad', '9ppc', 'ppc other')) {
        $invalidArchInvoke = 'cd {0} && MIGCC={1} MIGARCH={2} MIGCOM_DIR={3} MIG_TEST_CAPTURE={4} sh {5} -header {6} {7} 2>/dev/null' -f @(
            (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $runDir)),
            (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $fakeCompiler)),
            (ConvertTo-RhapShellLiteral $badArch),
            (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $fakeLibexec)),
            (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $captureDir)),
            (ConvertTo-RhapShellLiteral $wrapperShPath),
            (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath (Join-Path $outputDir 'invalid arch.h'))),
            (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $defsOne))
        )
        & $sh -c $invalidArchInvoke
        Assert-Equal ($LASTEXITCODE -ne 0) $true "MIG wrapper rejects invalid configured architecture: $badArch"
    }
    $missingArchInvoke = 'cd {0} && unset MIGARCH && MIGCC={1} MIGCOM_DIR={2} MIG_TEST_CAPTURE={3} sh {4} -header {5} {6} 2>/dev/null' -f @(
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $runDir)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $fakeCompiler)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $fakeLibexec)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $captureDir)),
        (ConvertTo-RhapShellLiteral $wrapperShPath),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath (Join-Path $outputDir 'missing arch.h'))),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $defsOne))
    )
    & $sh -c $missingArchInvoke
    Assert-Equal ($LASTEXITCODE -ne 0) $true 'configured MIG compiler requires an architecture contract'
    $invalidExplicitArchInvoke = 'cd {0} && MIGCC={1} MIGARCH=ppc MIGCOM_DIR={2} MIG_TEST_CAPTURE={3} sh {4} -arch {5} -header {6} {7} 2>/dev/null' -f @(
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $runDir)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $fakeCompiler)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $fakeLibexec)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $captureDir)),
        (ConvertTo-RhapShellLiteral $wrapperShPath),
        (ConvertTo-RhapShellLiteral 'ppc;touch_bad'),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath (Join-Path $outputDir 'invalid explicit arch.h'))),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $defsOne))
    )
    & $sh -c $invalidExplicitArchInvoke
    Assert-Equal ($LASTEXITCODE -ne 0) $true 'MIG wrapper validates and rejects unsafe explicit -arch'
    Assert-Equal (@((Get-Content -LiteralPath (Join-Path $captureDir 'compiler.args')) | Where-Object { $_ -eq '--invocation--' }).Count) $compilerCountBeforeInvalidArch 'invalid or missing architectures never invoke configured compiler'

    $ambientPpcBefore = @((Get-Content -LiteralPath (Join-Path $captureDir 'compiler.args')) | Where-Object { $_ -eq '-Dppc' }).Count
    $ambientI386Before = @((Get-Content -LiteralPath (Join-Path $captureDir 'compiler.args')) | Where-Object { $_ -eq '-Di386' }).Count
    $ambientConflictOutput = Join-Path $outputDir 'ambient architecture conflict header.h'
    $ambientConflictInvoke = 'cd {0} && arch=i386 MIGCC={1} MIGARCH=ppc MIGCOM_DIR={2} MIG_TEST_CAPTURE={3} sh {4} -header {5} {6}' -f @(
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $runDir)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $fakeCompiler)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $fakeLibexec)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $captureDir)),
        (ConvertTo-RhapShellLiteral $wrapperShPath),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $ambientConflictOutput)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $defsOne))
    )
    & $sh -c $ambientConflictInvoke
    Assert-Equal $LASTEXITCODE 0 'ambient lowercase arch does not override configured MIGARCH'
    $compilerArgsAfterAmbient = Get-Content -LiteralPath (Join-Path $captureDir 'compiler.args')
    Assert-Equal (@($compilerArgsAfterAmbient | Where-Object { $_ -eq '-Dppc' }).Count) ($ambientPpcBefore + 1) 'configured branch emits profile MIGARCH despite ambient lowercase arch'
    Assert-Equal (@($compilerArgsAfterAmbient | Where-Object { $_ -eq '-Di386' }).Count) $ambientI386Before 'configured branch never emits ambient lowercase arch'

    $overrideOutput = Join-Path $outputDir 'explicit architecture header.h'
    $overrideInvoke = 'cd {0} && arch=ambient_bad MIGCC={1} MIGARCH=ppc MIGCOM_DIR={2} MIG_TEST_CAPTURE={3} sh {4} -arch i386 -header {5} {6}' -f @(
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $runDir)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $fakeCompiler)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $fakeLibexec)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $captureDir)),
        (ConvertTo-RhapShellLiteral $wrapperShPath),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $overrideOutput)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $defsOne))
    )
    & $sh -c $overrideInvoke
    Assert-Equal $LASTEXITCODE 0 'explicit safe -arch overrides configured MIGARCH'
    $compilerArgsAfterOverride = Get-Content -LiteralPath (Join-Path $captureDir 'compiler.args')
    Assert-Equal (@($compilerArgsAfterOverride | Where-Object { $_ -eq '-Di386' }).Count) ($ambientI386Before + 1) 'explicit i386 architecture is preserved as one cpp argument'

    $typedOutput = Join-Path $outputDir 'typed mach server.h'
    $actualMachDefs = Join-Path $repoRoot 'src\kernel-7\mach\mach.defs'
    $typedInvoke = 'cd {0} && MIGCC={1} MIGARCH=ppc MIGCOM_DIR={2} MIG_TEST_CAPTURE={3} sh {4} -typed -I{5} -DKERNEL -DKERNEL_SERVER -header {6} -user /dev/null -server /dev/null {7}' -f @(
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $runDir)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $fakeCompiler)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $fakeLibexec)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $captureDir)),
        (ConvertTo-RhapShellLiteral $wrapperShPath),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath (Join-Path $repoRoot 'src\kernel-7'))),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $typedOutput)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $actualMachDefs))
    )
    & $sh -c $typedInvoke
    Assert-Equal $LASTEXITCODE 0 'typed wrapper contract accepts the actual kernel mach.defs with configured architecture'
    Assert-Equal (Test-Path -LiteralPath $typedOutput) $true 'typed actual mach.defs reaches private typed backend'
    $typedCompilerArgs = Get-Content -LiteralPath (Join-Path $captureDir 'compiler.args')
    Assert-Equal (@($typedCompilerArgs | Where-Object { $_ -eq '-DMACH_IPC_FLAVOR=TYPED' }).Count -ge 1) $true 'typed actual mach.defs selects typed preprocessing'
    Assert-Equal (@($typedCompilerArgs | Where-Object { $_ -eq (ConvertTo-TestShPath $actualMachDefs) }).Count) 1 'typed wrapper passes the actual mach.defs as one input'
} finally {
    $env:MIGARCH = $previousMigArch
    Remove-Item -LiteralPath $wrapperTestDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "build-src tests: PASS ($script:Checks checks)"
