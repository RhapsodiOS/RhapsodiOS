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
