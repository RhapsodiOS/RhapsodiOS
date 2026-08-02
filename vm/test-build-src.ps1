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
$alternatePhaseArgs = $phaseArgs.Clone()
$alternatePhaseArgs.BuildCc = '/opt/gcc/bin/gcc-4.2'
$alternatePhaseArgs.Make = '/opt/make/bin/gmake'
$alternateRbuild = New-RhapBuildPhaseCommand -Phase 'rbuild' @alternatePhaseArgs
Assert-Match $alternateRbuild ([regex]::Escape('/opt/make/bin/gmake CC=/opt/gcc/bin/gcc-4.2 clean test all')) 'alternate profile compiler builds rbuild'
Assert-NotMatch $alternateRbuild ([regex]::Escape('/usr/bin/make CC=/usr/bin/cc')) 'alternate profile does not use default build tools'

$bootstrapCommand = New-RhapBuildPhaseCommand -Phase 'bootstrap' @phaseArgs
Assert-Match $bootstrapCommand ([regex]::Escape('set -e; cd /build/src && /build/tools/bin/rbuild bootstrap')) 'bootstrap starts from synced source root'
Assert-Match $bootstrapCommand ([regex]::Escape('/build/tools/bin/rbuild bootstrap --sysroot /build/bootstrap-root --toolchain /build/src/rbuild-1/toolchains/gcc-darwin.conf --state /build/state /build/src/BootstrapManifest /build/repo /build/repo')) 'bootstrap uses resumable CLI'
$alternateSourceArgs = $phaseArgs.Clone()
$alternateSourceArgs.SourceRoot = '/srv/synced source'
$alternateBootstrap = New-RhapBuildPhaseCommand -Phase 'bootstrap' @alternateSourceArgs
Assert-Match $alternateBootstrap ([regex]::Escape("set -e; cd '/srv/synced source' && /build/tools/bin/rbuild bootstrap")) 'bootstrap quotes and uses alternate source cwd'
Assert-Match $alternateBootstrap ([regex]::Escape("'/srv/synced source'/BootstrapManifest")) 'bootstrap manifest follows alternate source root'
Assert-NotMatch $alternateBootstrap '/var/root|cd +~' 'bootstrap never inherits login cwd'
$kernelCommand = New-RhapBuildPhaseCommand -Phase 'kernel-drivers' @phaseArgs -DriverProjects @('drivers-ppc/storage/drvExample') -MakeDriverProjects @('drvBPF')
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

Write-Host "build-src tests: PASS ($script:Checks checks)"
