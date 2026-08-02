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

. (Join-Path $PSScriptRoot 'build-src-lib.ps1')
$realProfile = Get-Content -Raw (Join-Path $PSScriptRoot '..\src\rbuild-1\toolchains\gcc-darwin.conf')

$buildScriptText = Get-Content -Raw (Join-Path $PSScriptRoot 'build-src.ps1')
$remoteScriptText = Get-Content -Raw (Join-Path $PSScriptRoot 'rhap-remote.ps1')
$migWrapperText = Get-Content -Raw (Join-Path $PSScriptRoot '..\src\Commands\bootstrap_cmds\migcom.tproj\mig.sh')
$classicErrorText = Get-Content -Raw (Join-Path $PSScriptRoot '..\src\Commands\bootstrap_cmds\migcom.tproj\error.c')
$classicErrorHeaderText = Get-Content -Raw (Join-Path $PSScriptRoot '..\src\Commands\bootstrap_cmds\migcom.tproj\error.h')
$classicUtilsText = Get-Content -Raw (Join-Path $PSScriptRoot '..\src\Commands\bootstrap_cmds\migcom.tproj\utils.c')
$typedErrorText = Get-Content -Raw (Join-Path $PSScriptRoot '..\src\Commands\bootstrap_cmds\migcom_typd.tproj\error.c')
$typedErrorHeaderText = Get-Content -Raw (Join-Path $PSScriptRoot '..\src\Commands\bootstrap_cmds\migcom_typd.tproj\error.h')
Assert-Match $migWrapperText 'MIGCC' 'MIG wrapper supports configured compiler override'
Assert-Match $migWrapperText 'MIGCOM_DIR' 'MIG wrapper supports private libexec override'
Assert-Match $migWrapperText '-i[ `t]+\)' 'MIG wrapper forwards -i and its argument'
Assert-Match $migWrapperText '\$\{1#-\}.*=.*\$1' 'MIG wrapper preserves a following option after optional -i prefix'
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
Assert-Match $buildScriptText '(?s)param\(\s*\[switch\]\$All,\s*\[switch\]\$Rbuild,\s*\[switch\]\$Bootstrap,\s*\[switch\]\$KernelDrivers,\s*\[switch\]\$World,\s*\[switch\]\$Fresh\s*\)' 'canonical build-src parameters'
Assert-Match $remoteScriptText ([regex]::Escape('StandardInput.WriteAsync($payload)')) 'stream stdin writer is asynchronous'
Assert-Match $remoteScriptText 'Task\]::WaitAny' 'stream writer and readers share a blocking task loop'
Assert-Match $remoteScriptText '\[void\]\$writeTask\.GetAwaiter\(\)\.GetResult\(\)' 'stream writer task result cannot pollute exit status'
Assert-Equal ([regex]::Matches($remoteScriptText, 'ReadLineAsync\(\)').Count -ge 4) $true 'stream readers are continuously renewed'
Assert-Equal ($remoteScriptText.IndexOf('ReadLineAsync()') -lt $remoteScriptText.IndexOf('StandardInput.WriteAsync($payload)')) $true 'stream readers are armed with async stdin writer'
Assert-Match $remoteScriptText '(?s)\$stdoutTask = \$process\.StandardOutput\.ReadLineAsync\(\).*?\$sinkError.*?& \$emitStdout' 'stdout renews before deferred sink handling'
Assert-Match $remoteScriptText '(?s)\$stderrTask = \$process\.StandardError\.ReadLineAsync\(\).*?\$sinkError.*?& \$emitStderr' 'stderr renews before deferred sink handling'
Assert-Match $remoteScriptText '\$process\.Kill\(\)' 'exceptional streaming cleanup terminates exact child'
Assert-Match $remoteScriptText '(?s)finally \{.*?WaitForExit\(\).*?Dispose\(\)' 'exceptional cleanup reaps before dispose'
Assert-Equal ($buildScriptText.IndexOf('New-RhapFreshCommand') -lt $buildScriptText.IndexOf('New-RhapPreflightCommand')) $true 'fresh topology validates before preflight'
Assert-Match $buildScriptText 'New-RhapFreshCommand[^\r\n]+-Profile \$cfg\.ToolchainProfile' 'fresh validates resolved configured profile'

$phaseArgs = @{
    SourceRoot = '/build/src'
    ToolsDir = '/build/tools'
    BootstrapRoot = '/build/bootstrap-root'
    StateDir = '/build/state'
    Profile = '/build/src/rbuild-1/toolchains/gcc-darwin.conf'
    RepoDir = '/build/repo'
    BuiltDir = '/build/built'
    BuildCc = '/usr/bin/cc'
    Make = '/usr/bin/make'
    ToolPath = '/build/tools/bin:/usr/bin:/bin'
}
$rbuildCommand = New-RhapBuildPhaseCommand -Phase 'rbuild' @phaseArgs
Assert-Match $rbuildCommand ([regex]::Escape('cd /build/src/rbuild-1 && /usr/bin/make CC=/usr/bin/cc clean test all')) 'rbuild cleans tests and builds with profile compiler'
Assert-Match $rbuildCommand ([regex]::Escape('/usr/bin/install -d /build/tools/bin')) 'rbuild creates private tool directory'
Assert-Match $rbuildCommand ([regex]::Escape('/usr/bin/install -c -m 755 rbuild /build/tools/bin/rbuild')) 'rbuild installs privately'
Assert-Match $rbuildCommand ([regex]::Escape('/usr/bin/cc -O -o /build/tools/bin/relpath /build/src/Commands/bootstrap_cmds/relpath.tproj/relpath.c')) 'relpath is source-built with profile compiler'
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
Assert-Match $rbuildCommand ([regex]::Escape('CONFIG_DIR=/build/tools/bin MIGCC=/usr/bin/cc MIGCOM_DIR=/build/tools/libexec /build/tools/bin/mig -I/build/src/kernel-7 -header mach_interface.h -i -server /dev/null /build/src/kernel-7/mach/mach.defs')) 'private MIG wrapper contract preprocesses a real defs filename with configured GCC'
Assert-NotMatch $rbuildCommand '/usr/bin/mig|/usr/libexec/migcom|NEXT_ROOT|bootstrap-root/usr/libexec|DSTROOT=/|cp .*mig' 'stage zero never uses or copies live or sysroot MIG'
$alternatePhaseArgs = $phaseArgs.Clone()
$alternatePhaseArgs.BuildCc = '/opt/gcc/bin/gcc-4.2'
$alternatePhaseArgs.Make = '/opt/make/bin/gmake'
$alternateRbuild = New-RhapBuildPhaseCommand -Phase 'rbuild' @alternatePhaseArgs
Assert-Match $alternateRbuild ([regex]::Escape('/opt/make/bin/gmake CC=/opt/gcc/bin/gcc-4.2 clean test all')) 'alternate profile compiler builds rbuild'
Assert-Match $alternateRbuild ([regex]::Escape('/opt/gcc/bin/gcc-4.2 -O -bsd -DCMU -DLOCALARCHITECTURE -DNeXT=1')) 'alternate profile compiler builds config with project flags'
Assert-Match $alternateRbuild ([regex]::Escape('/opt/gcc/bin/gcc-4.2 -O -bsd -DNeXT=1 -I/build/tools/mig-build/include -I/build/src/Commands/bootstrap_cmds/migcom.tproj -I/build/tools/mig-build/migcom -o /build/tools/libexec/migcom')) 'alternate profile compiler builds MIG with historical platform flags'
Assert-NotMatch $alternateRbuild ([regex]::Escape('/usr/bin/make CC=/usr/bin/cc')) 'alternate profile does not use default build tools'
$spacedCompilerArgs = $phaseArgs.Clone()
$spacedCompilerArgs.BuildCc = '/opt/gcc tools/bin/gcc'
$spacedCompilerRbuild = New-RhapBuildPhaseCommand -Phase 'rbuild' @spacedCompilerArgs
Assert-Match $spacedCompilerRbuild ([regex]::Escape("'/opt/gcc tools/bin/gcc' -O -bsd -DNeXT=1 -I/build/tools/mig-build/include -I/build/src/Commands/bootstrap_cmds/migcom.tproj")) 'space-containing configured GCC builds private MIG as one executable path'
$metacharRootArgs = $phaseArgs.Clone()
$metacharRootArgs.BootstrapRoot = '/build/root[1].*'
$metacharRootRbuild = New-RhapBuildPhaseCommand -Phase 'rbuild' @metacharRootArgs
Assert-Match $metacharRootRbuild ([regex]::Escape("/usr/bin/grep -F -e '/usr/include/mach/' -e '/build/root[1].*'/")) 'MIG dependency audit treats metacharacter sysroot as a literal path'
Assert-Match $metacharRootRbuild ([regex]::Escape("else mig_dependency_status=`$?; test `$mig_dependency_status -eq 1 || { echo 'build-src: private MIG dependency audit failed: migcom'")) 'MIG dependency audit distinguishes grep errors from no matches'

$bootstrapCommand = New-RhapBuildPhaseCommand -Phase 'bootstrap' @phaseArgs
$alternateToolBootstrap = New-RhapBuildPhaseCommand -Phase 'bootstrap' @alternatePhaseArgs
$spacedCompilerBootstrap = New-RhapBuildPhaseCommand -Phase 'bootstrap' @spacedCompilerArgs
Assert-Match $bootstrapCommand ([regex]::Escape('/usr/bin/install -d /build/bootstrap-root /build/repo /build/state')) 'bootstrap creates owned output directories'
Assert-Match $bootstrapCommand ([regex]::Escape('CONFIG_DIR=/build/tools/bin MIGCC=/usr/bin/cc')) 'bootstrap scopes private config tool directory'
Assert-Match $bootstrapCommand ([regex]::Escape('CONFIG_DIR=/build/tools/bin MIGCC=/usr/bin/cc MIGCOM_DIR=/build/tools/libexec /build/tools/bin/rbuild bootstrap')) 'bootstrap explicitly binds private MIG compiler and libexec tools'
Assert-Match $alternateToolBootstrap ([regex]::Escape('MIGCC=/opt/gcc/bin/gcc-4.2 MIGCOM_DIR=/build/tools/libexec')) 'bootstrap binds alternate configured GCC to private MIG'
Assert-Match $spacedCompilerBootstrap ([regex]::Escape("MIGCC='/opt/gcc tools/bin/gcc' MIGCOM_DIR=/build/tools/libexec")) 'bootstrap quotes space-containing configured GCC for MIG wrapper'
Assert-NotMatch $bootstrapCommand '/usr/bin/mig|/usr/libexec/migcom|NEXT_ROOT|bootstrap-root/usr/libexec' 'bootstrap never selects live or sysroot MIG'
Assert-Equal ($bootstrapCommand.IndexOf('/usr/bin/install -d') -lt $bootstrapCommand.IndexOf('/build/tools/bin/rbuild bootstrap')) $true 'bootstrap creates outputs before rbuild'
Assert-Match $bootstrapCommand ([regex]::Escape('&& cd /build/src && CONFIG_DIR=/build/tools/bin')) 'bootstrap starts from synced source root'
Assert-Match $bootstrapCommand ([regex]::Escape('/build/tools/bin/rbuild bootstrap --sysroot /build/bootstrap-root --toolchain /build/src/rbuild-1/toolchains/gcc-darwin.conf --state /build/state /build/src/BootstrapManifest /build/repo /build/repo')) 'bootstrap uses resumable CLI'
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
Assert-Match $spacedRbuild ([regex]::Escape("-I'/srv/build tree/src'/Commands/bootstrap_cmds/config.tproj -I'/srv/build tree/tools'/config-build -o '/srv/build tree/tools'/bin/config")) 'config safely quotes alternate source and tools paths'
Assert-Match $spacedRbuild ([regex]::Escape("rm -rf '/srv/build tree/tools'/mig-build")) 'MIG safely quotes alternate private build root'
Assert-Match $spacedRbuild ([regex]::Escape("-O -bsd -DNeXT=1 -I'/srv/build tree/tools'/mig-build/include -I'/srv/build tree/src'/Commands/bootstrap_cmds/migcom_typd.tproj -I'/srv/build tree/tools'/mig-build/migcom_typd -o '/srv/build tree/tools'/libexec/migcom_typd")) 'MIG preserves platform flags and safely quotes alternate paths'
Assert-Match $spacedRbuild ([regex]::Escape("CONFIG_DIR='/srv/build tree/tools'/bin MIGCC=/usr/bin/cc MIGCOM_DIR='/srv/build tree/tools'/libexec '/srv/build tree/tools'/bin/mig -I'/srv/build tree/src'/kernel-7 -header mach_interface.h -i -server /dev/null '/srv/build tree/src'/kernel-7/mach/mach.defs")) 'MIG smoke generation safely quotes alternate source and private tool paths'
$spacedBootstrap = New-RhapBuildPhaseCommand -Phase 'bootstrap' @spacedPhaseArgs
Assert-Match $spacedBootstrap ([regex]::Escape("/usr/bin/install -d '/srv/build tree/bootstrap root' '/srv/build tree/repo' '/srv/build tree/state'")) 'bootstrap safely quotes owned outputs'
Assert-Match $spacedBootstrap ([regex]::Escape("CONFIG_DIR='/srv/build tree/tools'/bin MIGCC=/usr/bin/cc")) 'bootstrap safely quotes private config directory'
Assert-Match $spacedBootstrap ([regex]::Escape("MIGCC=/usr/bin/cc MIGCOM_DIR='/srv/build tree/tools'/libexec '/srv/build tree/tools'/bin/rbuild bootstrap")) 'bootstrap safely quotes private MIG bindings'
$kernelCommand = New-RhapBuildPhaseCommand -Phase 'kernel-drivers' @phaseArgs -DriverProjects @('drivers-ppc/storage/drvExample') -MakeDriverProjects @('drvBPF')
Assert-Match $kernelCommand ([regex]::Escape('test -d /build/repo')) 'kernel requires existing repository input'
Assert-Match $kernelCommand ([regex]::Escape('/usr/bin/install -d /build/built /build/state')) 'kernel creates owned output directories'
Assert-Equal ($kernelCommand.IndexOf('/usr/bin/install -d /build/built') -lt $kernelCommand.IndexOf('--dir driverkit-3')) $true 'kernel creates outputs before core packages'
Assert-Match $kernelCommand ([regex]::Escape('cd /build/src')) 'kernel package paths resolve beneath source root'
Assert-Match $kernelCommand ([regex]::Escape('/build/tools/bin/rbuild buildpackage --state /build/state --dir kernel-7 /build/repo /build/built')) 'kernel uses persistent state'
Assert-Match $kernelCommand ([regex]::Escape('--dir drivers-ppc/storage/drvExample /build/repo /build/built')) 'packaged driver uses rbuild'
Assert-Match $kernelCommand ([regex]::Escape('cd /build/src/drvBPF && PATH=/build/tools/bin:/usr/bin:/bin /usr/bin/make')) 'make-only driver uses configured make and path'
Assert-Match $kernelCommand ([regex]::Escape('CC=/usr/bin/cc')) 'make-only driver uses configured compiler'
Assert-Match $kernelCommand 'profile_cksum=.*cksum' 'make-only marker binds remote profile fingerprint'
Assert-Match $kernelCommand '/build/state/logs/drvBPF-all\.log' 'make-only driver has persistent log'
Assert-Match $kernelCommand '/build/state/drivers/drvBPF-all\.done' 'make-only driver has resume marker'
Assert-Match $kernelCommand 'mv .*\.done\.tmp\.\$\$ .*\.done' 'make-only marker is atomic'
Assert-Match $kernelCommand 'profile mismatch.*-Fresh' 'make-only stale profile is a hard error'
Assert-Equal ($kernelCommand.IndexOf('mkdir -p /build/state/logs') -lt $kernelCommand.IndexOf('set +e')) $true 'driver state directories are required setup'
Assert-Match $kernelCommand 'driver state write failed' 'make-only marker write failure is reported'
Assert-Match $kernelCommand 'core: driverkit-3, driverTools-1, kernel-7 \(required, all ok\)' 'kernel summary reports required core packages'
Assert-Match $kernelCommand 'drivers ok: \$rbuild_driver_passes' 'kernel summary reports optional successes'
Assert-Match $kernelCommand 'drivers fail: \$rbuild_driver_failures' 'kernel summary reports optional failures'
$worldCommand = New-RhapBuildPhaseCommand -Phase 'world' @phaseArgs
Assert-Match $worldCommand ([regex]::Escape('test -d /build/repo')) 'world requires existing repository input'
Assert-Match $worldCommand ([regex]::Escape('/usr/bin/install -d /build/built /build/state')) 'world creates owned output directories'
Assert-Equal ($worldCommand.IndexOf('/usr/bin/install -d /build/built') -lt $worldCommand.IndexOf('rbuild buildall')) $true 'world creates outputs before buildall'
Assert-Match $worldCommand ([regex]::Escape('cd /build/src && /build/tools/bin/rbuild buildall --state /build/state Manifest /build/repo /build/built')) 'world uses manifest and state'

foreach ($generated in @($rbuildCommand, $bootstrapCommand, $kernelCommand, $worldCommand)) {
    Assert-NotMatch $generated '/tmp/_|_seed-bootstrap-hdrs\.sh|DSTROOT=/|/usr/bin/rbuild|date-setting|header upload' 'generated command excludes obsolete workaround'
    Assert-NotMatch $generated '(?m)^\s*rm\s+-rf' 'phase command never deletes build output trees'
}

$freshCommand = New-RhapFreshCommand -RemoteRoot '/build' -SourceRoot '/build/src' -Profile '/build/src/rbuild-1/toolchains/gcc-darwin.conf' -ToolsDir '/build/tools' -BootstrapRoot '/build/bootstrap-root' -RepoDir '/build/repo' -BuiltDir '/build/built' -StateDir '/build/state'
Assert-Match $freshCommand ([regex]::Escape("rm -rf '/build/tools' '/build/bootstrap-root' '/build/repo' '/build/built' '/build/state'")) 'fresh removes exact configured outputs once'
Assert-Match $freshCommand ([regex]::Escape("mkdir -p '/build'")) 'fresh recreates only default output parent'
Assert-NotMatch $freshCommand ([regex]::Escape("mkdir -p '/build/tools")) 'fresh does not recreate output directories'
$freshRmLine = @($freshCommand -split "`n" | Where-Object { $_ -match '^rm -rf ' })[0]
Assert-NotMatch $freshRmLine '\*|\$[A-Za-z_]' 'fresh has no wildcard or variable deletion operands'
Assert-Equal ([regex]::Matches($freshCommand, '(?m)\brm\s').Count) 1 'fresh uses one removal command'
Assert-Match $freshCommand 'pwd -P' 'fresh validates physical boundaries'
Assert-Match $freshCommand 'test -L' 'fresh rejects symlink path components'
Assert-Match $freshCommand 'SOURCE_PHYS' 'fresh protects physical source root'
Assert-Match $freshCommand 'physical RemoteRoot may not be /' 'fresh rejects physical filesystem root'
Assert-Match $freshCommand 'SourceRoot escapes RemoteRoot' 'fresh requires physical source containment'
Assert-Match $freshCommand 'test -f "\$PROFILE"' 'fresh requires existing regular profile'
Assert-Match $freshCommand 'test ! -L "\$PROFILE"' 'fresh rejects final profile symlink'
Assert-Match $freshCommand 'PROFILE_PARENT_PHYS=.*pwd -P' 'fresh resolves profile parent physically'
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

$profileRead = New-RhapReadProfileCommand -Profile '/opt/profiles/gcc.conf'
Assert-Equal $profileRead "set -e; /bin/cat '/opt/profiles/gcc.conf'" 'absolute remote profile read command'
Assert-Throws { New-RhapReadProfileCommand -Profile "/opt/profile's.conf" } 'profile read rejects unsafe quote'

$orchestrationEvents = New-Object System.Collections.Generic.List[string]
$sequenceResult = Invoke-RhapBuildOrchestration -Phases @('rbuild', 'bootstrap', 'kernel-drivers', 'world') -PreflightBody 'preflight-body' -ProfileBody 'profile-body' -FreshBody 'fresh-body' -ParseProfile { param($text) "parsed:$text" } -PhaseFactory { param($phase, $profile) "$phase/$profile" } -ScriptInvoker { param($name, $body, $stream) $orchestrationEvents.Add("$name`:$stream"); return 0 } -CaptureInvoker { param($body) $orchestrationEvents.Add('profile'); return [pscustomobject]@{ ExitCode = 0; Stdout = 'remote'; Stderr = '' } }
Assert-Equal $sequenceResult $true 'orchestrator success'
Assert-Equal ($orchestrationEvents -join ',') 'preflight:False,profile,fresh output reset:False,rbuild:True,bootstrap:True,kernel-drivers:True,world:True' 'orchestrator preflight fresh and canonical order'
Assert-Equal @($orchestrationEvents | Where-Object { $_ -eq 'preflight:False' }).Count 1 'orchestrator runs preflight once'
$failureEvents = New-Object System.Collections.Generic.List[string]
Assert-Throws { Invoke-RhapBuildOrchestration -Phases @('rbuild', 'bootstrap', 'kernel-drivers', 'world') -PreflightBody 'p' -ProfileBody 'q' -ParseProfile { param($text) $text } -PhaseFactory { param($phase, $profile) $phase } -ScriptInvoker { param($name, $body, $stream) $failureEvents.Add($name); if ($name -eq 'bootstrap') { return 9 }; return 0 } -CaptureInvoker { param($body) return [pscustomobject]@{ ExitCode = 0; Stdout = 'remote'; Stderr = '' } } } 'orchestrator propagates required phase failure'
Assert-Equal ($failureEvents -join ',') 'preflight,rbuild,bootstrap' 'orchestrator stops at first required failure'

$profileValues = ConvertFrom-RhapToolchainProfileText -Text $realProfile
Assert-Equal $profileValues.build_cc '/usr/bin/cc' 'profile build compiler value'
Assert-Equal $profileValues.make '/usr/bin/make' 'profile make value'

Assert-Equal (Test-RhapToolchainProfileText -Text $realProfile) $true 'real toolchain profile contract'
Assert-Throws { Test-RhapToolchainProfileText -Text ($realProfile + "unknown_key=value`n") } 'reject unknown profile key'
Assert-Throws { Test-RhapToolchainProfileText -Text ($realProfile + "build_cc=/bin/false`n") } 'reject duplicate profile key'
Assert-Throws { Test-RhapToolchainProfileText -Text ($realProfile -replace '(?m)^ld_flags=.*\r?\n?', '') } 'reject missing profile key'
Assert-Throws { Test-RhapToolchainProfileText -Text ($realProfile -replace '(?m)^profile=', 'profile ') } 'reject malformed profile line'
Assert-Equal (Assert-RhapSafeArchFlags -Value '-arch ppc -mcpu=G4') '-arch ppc -mcpu=G4' 'accept gcc-style flag operands'
Assert-Throws { Assert-RhapSafeArchFlags -Value '-arch *' } 'reject glob star in arch flags'
Assert-Throws { Assert-RhapSafeArchFlags -Value '-arch ppc?' } 'reject glob question in arch flags'
Assert-Throws { Assert-RhapSafeArchFlags -Value '-I[abc]' } 'reject glob bracket in arch flags'
Assert-Equal (Test-RhapPpcMachOFileOutput -Text '/tmp/probe.o: Mach-O object ppc') $true 'accept PPC Mach-O object description'
Assert-Throws { Test-RhapPpcMachOFileOutput -Text '/tmp/probe.o: Mach-O object i386' } 'reject wrong object architecture'
Assert-Throws { Test-RhapPpcMachOFileOutput -Text '/tmp/probe.o: ELF 32-bit MSB relocatable, PowerPC' } 'reject non-Mach-O object'

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

Assert-Equal ((Get-RhapBuildPhases -All) -join ',') 'rbuild,bootstrap,kernel-drivers,world' 'all phase order'
Assert-Equal ((Get-RhapBuildPhases -Rbuild) -join ',') 'rbuild' 'rbuild phase'
Assert-Equal ((Get-RhapBuildPhases -Bootstrap) -join ',') 'bootstrap' 'bootstrap phase'
Assert-Equal ((Get-RhapBuildPhases -KernelDrivers) -join ',') 'kernel-drivers' 'kernel phase'
Assert-Equal ((Get-RhapBuildPhases -World) -join ',') 'world' 'world phase'
Assert-Throws { Get-RhapBuildPhases } 'reject no phase'
Assert-Throws { Get-RhapBuildPhases -All -World } 'reject all plus phase'
Assert-Throws { Get-RhapBuildPhases -Rbuild -Bootstrap } 'reject two phases'

$cmd = New-RhapPreflightCommand -SourceRoot '/build/src' -ToolsDir '/build/tools' -BootstrapRoot '/build/bootstrap-root' -StateDir '/build/state' -Profile '/build/src/rbuild-1/toolchains/gcc-darwin.conf'
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
Assert-Match $cmd 'ARCH_FLAGS' 'architecture flags parsed'
Assert-NotMatch $cmd ([regex]::Escape('case "$rbuild_flag" in -*')) 'arch flag operands such as ppc are accepted'
Assert-Match $cmd 'set -f' 'disable pathname expansion before flags split'
Assert-Match $cmd 'unsafe arch_flags' 'reject unsafe raw architecture flags'
Assert-Match $cmd 'gzip' 'gzip requirement'
Assert-Match $cmd 'tar' 'tar requirement'
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
Assert-Match $cmd 'Mach-O object ppc' 'target object PPC Mach-O requirement'
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
    . (Join-Path $PSScriptRoot 'rhap-remote.ps1')
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
while test $# -gt 0; do
    case $1 in
        -x) shift; language=$1 ;;
        *.defs) input=$1 ;;
    esac
    shift
done
if test -n "${MIGCC-}"; then test "$language" = c || exit 91; fi
test -f "$input" || exit 92
if test "${MIG_TEST_CPP_MODE-}" = fail; then
    printf '%s\n' 'partial preprocessor output'
    exit 42
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
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath (Join-Path $PSScriptRoot '..\src\Commands\bootstrap_cmds\migcom.tproj\mig.sh'))),
        $quotedWrapperArgs
    )
    & $sh -c $invoke
    Assert-Equal $LASTEXITCODE 0 'MIG wrapper executes configured GCC and backend with spaced paths'
    Assert-Equal (Test-Path -LiteralPath $headerOutput) $true 'MIG wrapper generates requested spaced header output'
    Assert-Equal (Test-Path -LiteralPath $userOutput) $true 'MIG wrapper generates requested spaced user output'
    $compilerArgs = Get-Content -LiteralPath (Join-Path $captureDir 'compiler.args')
    $backendArgs = Get-Content -LiteralPath (Join-Path $captureDir 'backend.args')
    Assert-Equal (@($compilerArgs | Where-Object { $_ -eq '-DVALUE=two words' }).Count) 2 'MIG wrapper preserves spaced cpp flag for multiple definitions'
    Assert-Equal (@($compilerArgs | Where-Object { $_ -eq '--invocation--' }).Count) 2 'MIG wrapper preprocesses multiple definitions'
    Assert-Equal (@($backendArgs | Where-Object { $_ -eq (ConvertTo-TestShPath $headerOutput) }).Count) 2 'MIG wrapper preserves spaced backend header value'
    Assert-Equal (@($backendArgs | Where-Object { $_ -eq (ConvertTo-TestShPath $prefix) }).Count) 2 'MIG wrapper preserves spaced optional -i prefix'
    Assert-Equal (@($backendArgs | Where-Object { $_ -eq '--invocation--' }).Count) 2 'MIG wrapper invokes backend for multiple definitions'
    $newlineFlag = "-DBAD=line one`nline two"
    $newlineInvoke = 'MIGCC={0} MIGCOM_DIR={1} MIG_TEST_CAPTURE={2} sh {3} {4} {5} 2>/dev/null' -f @(
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $fakeCompiler)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $fakeLibexec)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $captureDir)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath (Join-Path $PSScriptRoot '..\src\Commands\bootstrap_cmds\migcom.tproj\mig.sh'))),
        (ConvertTo-RhapShellLiteral $newlineFlag),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $defsOne))
    )
    & $sh -c $newlineInvoke
    Assert-Equal $LASTEXITCODE 1 'MIG wrapper rejects embedded newlines before execution'
    Assert-Equal (@((Get-Content -LiteralPath (Join-Path $captureDir 'compiler.args')) | Where-Object { $_ -eq '--invocation--' }).Count) 2 'newline rejection does not invoke configured compiler'

    $wrapperShPath = ConvertTo-TestShPath (Join-Path $PSScriptRoot '..\src\Commands\bootstrap_cmds\migcom.tproj\mig.sh')
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
} finally {
    Remove-Item -LiteralPath $wrapperTestDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "build-src tests: PASS ($script:Checks checks)"
