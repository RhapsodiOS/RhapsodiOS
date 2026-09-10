#Requires -Version 5.1
<#
.SYNOPSIS
  Run resumable rbuild, bootstrap, kernel/driver, and world builds on the PPC host.
.EXAMPLE
  powershell -File vm\build-src.ps1 -All
  powershell -File vm\build-src.ps1 -All -Fresh
#>
param(
    [switch]$All,
    [switch]$Rbuild,
    [switch]$Bootstrap,
    [switch]$KernelDrivers,
    [switch]$World,
    [switch]$Fresh
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$VmDir = $PSScriptRoot
. (Join-Path $VmDir 'build-src-lib.ps1')
. (Join-Path $VmDir 'rhap-remote.ps1')

function Write-Die([string]$Message) {
    Write-RhapDie 'build-src' $Message
}

function Show-Usage {
    Write-Host @"
Usage: powershell -File vm\build-src.ps1 <-All|-Rbuild|-Bootstrap|-KernelDrivers|-World> [-Fresh]

  -All             Run rbuild, bootstrap, kernel/drivers, then world
  -Rbuild          Build, test, and install private rbuild and relpath tools
  -Bootstrap       Resume BootstrapManifest into the target sysroot and repository
  -KernelDrivers   Build required kernel packages and optional drivers
  -World           Resume the world Manifest build
  -Fresh           Safely remove configured build outputs after preflight

Config: vm\vm.conf. Sync sources first with sync-src.ps1.
"@
}

try {
    $phases = @(Get-RhapBuildPhases -All:$All -Rbuild:$Rbuild -Bootstrap:$Bootstrap -KernelDrivers:$KernelDrivers -World:$World)
} catch {
    Show-Usage
    Write-Die $_.Exception.Message
}
[void](Assert-RhapFreshMode -All:$All -Rbuild:$Rbuild -Bootstrap:$Bootstrap -KernelDrivers:$KernelDrivers -World:$World -Fresh:$Fresh)

$cfg = Get-RhapVmConfig -DiePrefix 'build-src'
$ssh = Resolve-RhapTool -NameOrPath $cfg.Ssh -DiePrefix 'build-src'
$sourceRoot = ConvertTo-RhapNormalizedRemotePath -Path "$($cfg.RemoteRoot)/src" -Name 'SourceRoot'

foreach ($path in @($cfg.ToolsDir, $cfg.BootstrapRoot, $cfg.RepoDir, $cfg.BuiltDir, $cfg.StateDir)) {
    [void](Assert-RhapSafeRemoteOutputPath -RemoteRoot $cfg.RemoteRoot -Path $path)
}

$localSrc = Join-Path $cfg.LocalRoot 'src'
if (-not (Test-Path -LiteralPath $localSrc -PathType Container)) {
    Write-Die "local src missing: $localSrc"
}
function Get-DriverProjectRels {
    param(
        [Parameter(Mandatory = $true)][string]$TargetArch
    )
    $arch = Assert-RhapSafeIdentifier -Value $TargetArch -Name 'TargetArch'
    $packaged = New-Object System.Collections.Generic.List[string]
    $makeOnly = New-Object System.Collections.Generic.List[string]
    $archRoot = Join-Path $localSrc "drivers-$arch"
    if (Test-Path -LiteralPath $archRoot -PathType Container) {
        Get-ChildItem -LiteralPath $archRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $category = $_
            Get-ChildItem -LiteralPath $category.FullName -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                $project = $_
                if ($project.Name -notmatch '^(drv|Intel)') { return }
                $rel = "drivers-$arch/$($category.Name)/$($project.Name)"
                if (Test-Path -LiteralPath (Join-Path $project.FullName 'dpkg\control') -PathType Leaf) {
                    $packaged.Add($rel)
                } elseif (Test-Path -LiteralPath (Join-Path $project.FullName 'Makefile') -PathType Leaf) {
                    $makeOnly.Add($rel)
                }
            }
        }
    }
    foreach ($extra in @('drvBPF', 'drvPortServer')) {
        $project = Join-Path $localSrc $extra
        if (Test-Path -LiteralPath (Join-Path $project 'dpkg\control') -PathType Leaf) {
            $packaged.Add($extra)
        } elseif (Test-Path -LiteralPath (Join-Path $project 'Makefile') -PathType Leaf) {
            $makeOnly.Add($extra)
        }
    }
    return @{
        Packaged = @($packaged | Sort-Object -Unique)
        MakeOnly = @($makeOnly | Sort-Object -Unique)
    }
}

$freshCommand = $null
if ($Fresh) {
    $freshCommand = New-RhapFreshCommand -RemoteRoot $cfg.RemoteRoot -SourceRoot $sourceRoot -Profile $cfg.ToolchainProfile -ToolsDir $cfg.ToolsDir -BootstrapRoot $cfg.BootstrapRoot -RepoDir $cfg.RepoDir -BuiltDir $cfg.BuiltDir -StateDir $cfg.StateDir
}

$preflight = New-RhapPreflightCommand -SourceRoot $sourceRoot -ToolsDir $cfg.ToolsDir -BootstrapRoot $cfg.BootstrapRoot -StateDir $cfg.StateDir -Profile $cfg.ToolchainProfile
$profileBody = New-RhapReadProfileCommand -Profile $cfg.ToolchainProfile
$scriptInvoker = {
    param($name, $body, $stream)
    Write-Host "build-src: $name"
    return Invoke-RhapSshScript -Cfg $cfg -Ssh $ssh -ScriptBody $body -Stream:$stream
}
$captureInvoker = {
    param($body)
    $result = Invoke-RhapSshCapture -Cfg $cfg -Ssh $ssh -ScriptBody $body
    if ($result.ExitCode -ne 0 -and -not [string]::IsNullOrWhiteSpace($result.Stderr)) {
        Write-Host $result.Stderr.TrimEnd()
    }
    return $result
}
$parseProfile = {
    param($text)
    $values = ConvertFrom-RhapToolchainProfileText -Text $text
    [void](Assert-RhapSafeCommandPath -Path $values.build_cc -Name 'build_cc')
    [void](Assert-RhapSafeIdentifier -Value $values.target_arch -Name 'target_arch')
    [void](Assert-RhapSafeCommandPath -Path $values.make -Name 'make')
    return $values
}
$phaseFactory = {
    param($phase, $profileValues)
    $extra = @{}
    if ($phase -eq 'kernel-drivers') {
        $corePackages = @(Get-RhapKernelCorePackages -TargetArch $profileValues.target_arch)
        foreach ($package in $corePackages) {
            if (-not (Test-Path -LiteralPath (Join-Path $localSrc $package) -PathType Container)) {
                throw "core package source missing locally: $package"
            }
        }
        $drivers = Get-DriverProjectRels -TargetArch $profileValues.target_arch
        $extra.DriverProjects = @($drivers.Packaged | Where-Object { $corePackages -notcontains $_ })
        $extra.MakeDriverProjects = @($drivers.MakeOnly | Where-Object { $corePackages -notcontains $_ })
        Write-Host "build-src: $($extra.DriverProjects.Count + $extra.MakeDriverProjects.Count) optional driver projects"
    }
    return New-RhapBuildPhaseCommand -Phase $phase -SourceRoot $sourceRoot -ToolsDir $cfg.ToolsDir -BootstrapRoot $cfg.BootstrapRoot -StateDir $cfg.StateDir -Profile $cfg.ToolchainProfile -RepoDir $cfg.RepoDir -BuiltDir $cfg.BuiltDir -BuildCc $profileValues.build_cc -TargetArch $profileValues.target_arch -Make $profileValues.make -ToolPath $profileValues.path @extra
}
try {
    [void](Invoke-RhapBuildOrchestration -Phases $phases -PreflightBody $preflight -ProfileBody $profileBody -FreshBody $freshCommand -ParseProfile $parseProfile -PhaseFactory $phaseFactory -ScriptInvoker $scriptInvoker -CaptureInvoker $captureInvoker)
} catch {
    Write-Die $_.Exception.Message
}

Write-Host "build-src: complete ($($phases -join ', '))"
