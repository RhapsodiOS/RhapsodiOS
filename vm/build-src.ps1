#Requires -Version 5.0
<#
.SYNOPSIS
  Kick off rbuild / bootstrap / kernel+drivers / world builds on the PPC guest.
.EXAMPLE
  powershell -File vm\build-src.ps1 -Rbuild
  powershell -File vm\build-src.ps1 -Bootstrap
  powershell -File vm\build-src.ps1 -KernelDrivers
  powershell -File vm\build-src.ps1 -World
#>
param(
    [switch]$Rbuild,
    [switch]$Bootstrap,
    [switch]$KernelDrivers,
    [switch]$World
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$VmDir = $PSScriptRoot
. (Join-Path $VmDir 'rhap-remote.ps1')

function Write-Die([string]$Message) {
    Write-RhapDie 'build-src' $Message
}

function Show-Usage {
    Write-Host @"
Usage: powershell -File vm\build-src.ps1 <-Rbuild|-Bootstrap|-KernelDrivers|-World>

  -Rbuild          Build and install rbuild (gnumake + install to /usr/bin)
  -Bootstrap       rbuild bootstrap BootstrapManifest -> RepoDir
  -KernelDrivers   Build driverkit/driverTools/kernel, then all i386+ppc drivers
                   (and drvBPF / drvPortServer). Driver failures are summarized.
  -World           rbuild buildall Manifest RepoDir BuiltDir

Config: vm\vm.conf (Host, User, Password, RemoteRoot, RepoDir, BuiltDir, Make, Ssh)
Exactly one mode switch is required. Sync sources first with sync-src.ps1.
"@
}

$modeCount = @($Rbuild, $Bootstrap, $KernelDrivers, $World) | Where-Object { $_ } | Measure-Object | Select-Object -ExpandProperty Count
if ($modeCount -eq 0) {
    Show-Usage
    exit 1
}
if ($modeCount -gt 1) {
    Show-Usage
    Write-Die 'specify exactly one of -Rbuild, -Bootstrap, -KernelDrivers, -World'
}

$cfg = Get-RhapVmConfig -DiePrefix 'build-src'
$ssh = Resolve-RhapTool -NameOrPath $cfg.Ssh -DiePrefix 'build-src'
$srcRemote = "$($cfg.RemoteRoot)/src"
$make = $cfg.Make
$repo = $cfg.RepoDir
$built = $cfg.BuiltDir
$localSrc = Join-Path $cfg.LocalRoot 'src'
if (-not (Test-Path -LiteralPath $localSrc)) {
    Write-Die "local src missing: $localSrc"
}

function Invoke-BuildRemote([string]$RemoteCommand) {
    Write-Host "build-src: $RemoteCommand"
    $ec = Invoke-RhapRemote -Cfg $cfg -Ssh $ssh -RemoteCommand $RemoteCommand
    return $ec
}

function Get-DriverProjectRels {
    $rels = New-Object System.Collections.Generic.List[string]
    foreach ($arch in @('drivers-i386', 'drivers-ppc')) {
        $archRoot = Join-Path $localSrc $arch
        if (-not (Test-Path -LiteralPath $archRoot)) { continue }
        Get-ChildItem -LiteralPath $archRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $cat = $_
            Get-ChildItem -LiteralPath $cat.FullName -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                $proj = $_
                if ($proj.Name -notmatch '^(drv|Intel)') { return }
                $hasCtl = Test-Path -LiteralPath (Join-Path $proj.FullName 'dpkg\control')
                $hasMk = Test-Path -LiteralPath (Join-Path $proj.FullName 'Makefile')
                if (-not $hasCtl -and -not $hasMk) { return }
                $rels.Add(("$arch/$($cat.Name)/$($proj.Name)" -replace '\\', '/'))
            }
        }
    }
    foreach ($extra in @('drvBPF', 'drvPortServer')) {
        $p = Join-Path $localSrc $extra
        if (-not (Test-Path -LiteralPath $p)) { continue }
        $hasCtl = Test-Path -LiteralPath (Join-Path $p 'dpkg\control')
        $hasMk = Test-Path -LiteralPath (Join-Path $p 'Makefile')
        if ($hasCtl -or $hasMk) { $rels.Add($extra) }
    }
    return @($rels | Sort-Object -Unique)
}

if ($Rbuild) {
    $cmd = "cd $srcRemote/rbuild-1 && $make && $make install DSTROOT=/"
    $ec = Invoke-BuildRemote $cmd
    if ($ec -ne 0) { Write-Die "rbuild build/install failed (exit $ec)" }
    Write-Host 'build-src: rbuild installed'
    exit 0
}

if ($Bootstrap) {
    $bm = Join-Path $localSrc 'BootstrapManifest'
    if (-not (Test-Path -LiteralPath $bm)) {
        Write-Die "local BootstrapManifest missing: $bm (restore/sync before -Bootstrap)"
    }
    $ec = Invoke-BuildRemote "test -f $srcRemote/BootstrapManifest"
    if ($ec -ne 0) {
        Write-Die "remote BootstrapManifest missing at $srcRemote/BootstrapManifest - sync with: sync-src.ps1 -Path BootstrapManifest"
    }
    # Guest clock drifts; autoconf aborts when source mtimes (from Windows sync)
    # are newer than "now". Rhapsody date(1) wants yyyymmddHHMM.SS.
    $timeArg = (Get-Date).ToString('yyyyMMddHHmm') + '.00'
    $ec = Invoke-BuildRemote "date $timeArg"
    if ($ec -ne 0) {
        Write-Host "build-src: warning: could not set guest date to $timeArg (continuing)"
    }
    # Native builds read live System.framework headers; seed ones this image lacks.
    $seedLocal = Join-Path $VmDir '_seed-bootstrap-hdrs.sh'
    if (-not (Test-Path -LiteralPath $seedLocal)) {
        Write-Die "missing $seedLocal"
    }
    $tar = Resolve-RhapTool -NameOrPath $cfg.Tar -DiePrefix 'build-src'
    Write-Host 'build-src: uploading seed-bootstrap-hdrs.sh'
    $remote = "$($cfg.User)@$($cfg.Host)"
    $opts = ($script:RhapLegacySshOptions -join ' ')
    $cmdLine = " `"$tar`" --format ustar -cf - -C `"$VmDir`" `"_seed-bootstrap-hdrs.sh`" | `"$ssh`" $opts $remote `"cd /tmp && tar xf - && chmod a+x /tmp/_seed-bootstrap-hdrs.sh`" "
    Invoke-RhapSshAskPass -Cfg $cfg -Action {
        cmd.exe /c $cmdLine
        if ($LASTEXITCODE -ne 0) {
            Write-Die "seed script upload failed (exit $LASTEXITCODE)"
        }
    }
    $ec = Invoke-BuildRemote "/tmp/_seed-bootstrap-hdrs.sh $srcRemote"
    if ($ec -ne 0) { Write-Die "seed-bootstrap-hdrs failed (exit $ec)" }
    $prep = "mkdir -p $repo && cd $srcRemote && rbuild bootstrap BootstrapManifest $repo $repo"
    $ec = Invoke-BuildRemote $prep
    if ($ec -ne 0) { Write-Die "bootstrap failed (exit $ec)" }
    Write-Host 'build-src: bootstrap complete'
    exit 0
}

if ($World) {
    $mf = Join-Path $localSrc 'Manifest'
    if (-not (Test-Path -LiteralPath $mf)) {
        Write-Die "local Manifest missing: $mf"
    }
    $prep = "mkdir -p $repo $built && cd $srcRemote && rbuild buildall Manifest $repo $built"
    $ec = Invoke-BuildRemote $prep
    if ($ec -ne 0) { Write-Die "world buildall failed (exit $ec)" }
    Write-Host 'build-src: world build complete'
    exit 0
}

# -KernelDrivers
$corePkgs = @('driverkit-3', 'driverTools-1', 'kernel-7')
$ec = Invoke-BuildRemote "mkdir -p $repo $built"
if ($ec -ne 0) { Write-Die "mkdir repo/built failed (exit $ec)" }

foreach ($pkg in $corePkgs) {
    $localPkg = Join-Path $localSrc $pkg
    if (-not (Test-Path -LiteralPath $localPkg)) {
        Write-Die "core package source missing locally: $localPkg"
    }
    $cmd = "cd $srcRemote && rbuild buildpackage --dir $pkg $repo $built"
    $ec = Invoke-BuildRemote $cmd
    if ($ec -ne 0) {
        Write-Die "core package build failed (exit $ec): $pkg"
    }
    Write-Host "build-src: ok $pkg"
}

$drivers = Get-DriverProjectRels
Write-Host "build-src: $($drivers.Count) driver projects to build"
$passed = New-Object System.Collections.Generic.List[string]
$failed = New-Object System.Collections.Generic.List[string]

foreach ($rel in $drivers) {
    $localProj = Join-Path $localSrc ($rel -replace '/', [IO.Path]::DirectorySeparatorChar)
    $hasCtl = Test-Path -LiteralPath (Join-Path $localProj 'dpkg\control')
    if ($hasCtl) {
        $cmd = "cd $srcRemote && rbuild buildpackage --dir $rel $repo $built"
    } else {
        $cmd = "cd $srcRemote/$rel && $make"
    }
    $ec = Invoke-BuildRemote $cmd
    if ($ec -eq 0) {
        $passed.Add($rel)
        Write-Host "build-src: ok $rel"
    } else {
        $failed.Add($rel)
        Write-Host "build-src: FAIL $rel (exit $ec)"
    }
}

Write-Host '======== kernel/drivers summary ========'
Write-Host "core: $($corePkgs -join ', ') (required, all ok)"
Write-Host "drivers ok: $($passed.Count)"
Write-Host "drivers fail: $($failed.Count)"
if ($failed.Count -gt 0) {
    $failed | ForEach-Object { Write-Host "  FAIL $_" }
    Write-Die "kernel/drivers finished with $($failed.Count) driver failure(s)"
}
Write-Host 'build-src: kernel/drivers complete'
