#Requires -Version 5.0
<#
.SYNOPSIS
  Sync source to Rhapsody QEMU guest and run remote builds (PuTTY plink/pscp).
.EXAMPLE
  powershell -File vm\rhap-vm.ps1 sync
  powershell -File vm\rhap-vm.ps1 build world
  powershell -File vm\rhap-vm.ps1 ssh hostname
#>
param(
    [Parameter(Position = 0)]
    [ValidateSet('sync', 'build', 'ssh', 'help')]
    [string]$Command = 'help',

    [Parameter(Position = 1, ValueFromRemainingArguments = $true)]
    [string[]]$Rest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$VmDir = $PSScriptRoot
$ConfPath = Join-Path $VmDir 'vm.conf'

function Write-Die([string]$Message) {
    Write-Error "rhap-vm: $Message"
    exit 1
}

function Get-VmConfig {
    if (-not (Test-Path -LiteralPath $ConfPath)) {
        Write-Die "missing $ConfPath - copy vm.conf.example to vm.conf and edit"
    }
    $cfg = @{
        Host       = ''
        User       = ''
        Password   = ''
        RemoteRoot = '/build/source'
        LocalRoot  = ''
        Plink      = 'plink.exe'
        Pscp       = 'pscp.exe'
        SyncPaths  = 'src;ninja'
    }
    Get-Content -LiteralPath $ConfPath | ForEach-Object {
        $line = $_.Trim()
        if ($line -eq '' -or $line.StartsWith('#')) { return }
        $eq = $line.IndexOf('=')
        if ($eq -lt 1) { return }
        $key = $line.Substring(0, $eq).Trim()
        $val = $line.Substring($eq + 1).Trim()
        if ($cfg.ContainsKey($key)) { $cfg[$key] = $val }
    }
    foreach ($req in @('Host', 'User', 'Password')) {
        if ([string]::IsNullOrWhiteSpace($cfg[$req])) {
            Write-Die "vm.conf missing required key: $req"
        }
    }
    if ([string]::IsNullOrWhiteSpace($cfg.LocalRoot)) {
        $cfg.LocalRoot = Split-Path -Parent $VmDir
    }
    $cfg.RemoteRoot = $cfg.RemoteRoot.TrimEnd('/')
    return $cfg
}

function Resolve-Tool([string]$NameOrPath) {
    if (Test-Path -LiteralPath $NameOrPath) { return (Resolve-Path -LiteralPath $NameOrPath).Path }
    $cmd = Get-Command $NameOrPath -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    Write-Die "tool not found: $NameOrPath (install PuTTY or set Plink/Pscp in vm.conf)"
}

function Invoke-Plink {
    param(
        [hashtable]$Cfg,
        [string]$RemoteCommand,
        [switch]$Batch,
        [switch]$AllocateTty
    )
    $plink = Resolve-Tool $Cfg.Plink
    # Do not use $args — it is PowerShell's automatic variable.
    $plinkArgs = @('-ssh')
    if ($Batch) { $plinkArgs += '-batch' }
    if ($AllocateTty) { $plinkArgs += '-t' }
    $plinkArgs += @('-pw', $Cfg.Password, "$($Cfg.User)@$($Cfg.Host)")
    if (-not [string]::IsNullOrWhiteSpace($RemoteCommand)) {
        # One remote argv so plink options like -C are never parsed from the command.
        $plinkArgs += $RemoteCommand
    }
    if ($env:RHAP_VM_DEBUG -eq '1') {
        $shown = foreach ($a in $plinkArgs) {
            if ($a -eq $Cfg.Password) { '<redacted>' } else { $a }
        }
        Write-Host "rhap-vm: debug plink $($shown -join ' ')"
    }
    # Important: do not `return $LASTEXITCODE` — callers that assign the result
    # would also capture plink stdout into that variable (hiding "OK", make logs, etc.).
    & $plink @plinkArgs
    if ($null -eq $LASTEXITCODE) { return }
    # Set a script-scoped copy for callers that need it without pipeline capture.
    $script:LastPlinkExitCode = $LASTEXITCODE
}

function Get-LastPlinkExitCode {
    if ($null -ne $script:LastPlinkExitCode) { return $script:LastPlinkExitCode }
    if ($null -ne $LASTEXITCODE) { return $LASTEXITCODE }
    return 0
}

function Invoke-Sync([hashtable]$Cfg) {
    $pscp = Resolve-Tool $Cfg.Pscp
    $paths = @($Cfg.SyncPaths -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($paths.Count -eq 0) { Write-Die 'SyncPaths is empty' }

    foreach ($rel in $paths) {
        $local = Join-Path $Cfg.LocalRoot $rel
        if (-not (Test-Path -LiteralPath $local)) {
            Write-Die "sync path missing locally: $local"
        }
    }

    $mkdirCmd = "mkdir -p $($Cfg.RemoteRoot)"
    Invoke-Plink -Cfg $Cfg -Batch -AllocateTty -RemoteCommand $mkdirCmd
    $ec = Get-LastPlinkExitCode
    if ($ec -ne 0) { Write-Die "remote mkdir failed (exit $ec): $mkdirCmd" }

    foreach ($rel in $paths) {
        $local = Join-Path $Cfg.LocalRoot $rel
        $remoteSpec = "$($Cfg.User)@$($Cfg.Host):$($Cfg.RemoteRoot)/$($rel.Replace('\','/'))"
        Write-Host "rhap-vm: pscp $rel -> $remoteSpec"
        $pscpArgs = @('-batch', '-r', '-pw', $Cfg.Password, $local, $remoteSpec)
        & $pscp @pscpArgs
        if ($LASTEXITCODE -ne 0) {
            Write-Die "pscp failed (exit $LASTEXITCODE) for $rel"
        }
    }
    Write-Host 'rhap-vm: sync complete'
}

function Invoke-Build([hashtable]$Cfg, [string[]]$Targets) {
    if (-not $Targets -or $Targets.Count -eq 0) { $Targets = @('world') }
    $targetStr = ($Targets -join ' ')
    # Avoid make -C (plink and old BSD make both treat -C specially). Use sh -c + cd.
    $remote = "sh -c 'cd $($Cfg.RemoteRoot)/ninja && make $targetStr'"
    Write-Host "rhap-vm: $remote"
    Invoke-Plink -Cfg $Cfg -Batch -AllocateTty -RemoteCommand $remote
    exit (Get-LastPlinkExitCode)
}

function Invoke-Ssh([hashtable]$Cfg, [string[]]$RemoteCmd) {
    if (-not $RemoteCmd -or $RemoteCmd.Count -eq 0) {
        Invoke-Plink -Cfg $Cfg
        exit (Get-LastPlinkExitCode)
    }
    $joined = ($RemoteCmd -join ' ')
    Invoke-Plink -Cfg $Cfg -Batch -AllocateTty -RemoteCommand $joined
    exit (Get-LastPlinkExitCode)
}

$cfg = $null
switch ($Command) {
    'help' {
        Write-Host @"
Usage: powershell -File vm\rhap-vm.ps1 <sync|build|ssh|help> [args...]

  sync              Upload SyncPaths to RemoteRoot via pscp
  build [targets]   Remote: cd RemoteRoot/ninja && make (default: world)
  ssh [command]     Interactive plink, or one-shot remote command

Config: vm\vm.conf (copy from vm.conf.example)
First connection: accept host key interactively once, then sync/build use -batch.
Debug: set RHAP_VM_DEBUG=1 to print the plink argv (password redacted).
"@
        exit 0
    }
    'sync' {
        $cfg = Get-VmConfig
        Invoke-Sync $cfg
    }
    'build' {
        $cfg = Get-VmConfig
        Invoke-Build $cfg $Rest
    }
    'ssh' {
        $cfg = Get-VmConfig
        Invoke-Ssh $cfg $Rest
    }
}
