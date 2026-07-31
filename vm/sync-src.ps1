#Requires -Version 5.0
<#
.SYNOPSIS
  Sync local src/ to the Rhapsody guest build tree (RemoteRoot/src) via tar|ssh.
.EXAMPLE
  powershell -File vm\sync-src.ps1 -All
  powershell -File vm\sync-src.ps1 -Path drivers-i386/bus/drvPCMCIABus
.NOTES
  The PPC Rhapsody sshd only speaks ancient crypto. This script passes the same
  OpenSSH -o options documented in "SSH CONNECTION.md".

  Modern OpenSSH scp loses the connection against this guest even with -O, so
  transfers use Windows tar piped into ssh (via cmd.exe for a binary-safe pipe).
#>
param(
    [switch]$All,

    [Parameter()]
    [string]$Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$VmDir = $PSScriptRoot
$ConfPath = Join-Path $VmDir 'vm.conf'

# Rhapsody DR2 / Mac OS X Server 1.x sshd algorithm set (see vm/SSH CONNECTION.md).
# Host-key checking is disabled for this lab guest: Windows OpenSSH often fails
# to update ~/.ssh/known_hosts for ssh-dss keys ("Failed to add the host..."),
# which aborts the session under accept-new / yes.
$script:KnownHostsFile = Join-Path $env:TEMP 'rhap-sync-src-known_hosts'
if (-not (Test-Path -LiteralPath $script:KnownHostsFile)) {
    New-Item -ItemType File -Path $script:KnownHostsFile -Force | Out-Null
}
# OpenSSH on Windows accepts forward slashes in -o path values more reliably.
$knownHostsOpt = ($script:KnownHostsFile -replace '\\', '/')
$script:LegacySshOptions = @(
    '-o', 'KexAlgorithms=diffie-hellman-group1-sha1',
    '-o', 'HostKeyAlgorithms=ssh-dss',
    '-o', 'Ciphers=3des-cbc',
    '-o', 'MACs=hmac-sha1',
    '-o', 'PubkeyAuthentication=no',
    '-o', 'StrictHostKeyChecking=no',
    '-o', "UserKnownHostsFile=$knownHostsOpt"
)

function Write-Die([string]$Message) {
    Write-Error "sync-src: $Message"
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
        Ssh        = 'ssh.exe'
        Tar        = 'tar.exe'
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
    Write-Die "tool not found: $NameOrPath (install OpenSSH Client / tar, or set Ssh/Tar in vm.conf)"
}

function Invoke-WithSshAskPass {
    param(
        [hashtable]$Cfg,
        [scriptblock]$Action
    )
    # OpenSSH has no -pw; force SSH_ASKPASS so non-interactive runs work on Windows.
    $ask = Join-Path $env:TEMP ("sync-src-askpass-{0}.cmd" -f [guid]::NewGuid().ToString('n'))
    $prev = @{
        SSH_ASKPASS         = $env:SSH_ASKPASS
        SSH_ASKPASS_REQUIRE = $env:SSH_ASKPASS_REQUIRE
        DISPLAY             = $env:DISPLAY
        RHAP_SSH_PASS       = $env:RHAP_SSH_PASS
    }
    try {
        Set-Content -LiteralPath $ask -Value "@echo off`r`necho %RHAP_SSH_PASS%" -Encoding ASCII
        $env:RHAP_SSH_PASS = $Cfg.Password
        $env:SSH_ASKPASS = $ask
        $env:SSH_ASKPASS_REQUIRE = 'force'
        if ([string]::IsNullOrWhiteSpace($env:DISPLAY)) { $env:DISPLAY = 'unused' }
        return & $Action
    } finally {
        Remove-Item -LiteralPath $ask -Force -ErrorAction SilentlyContinue
        foreach ($k in $prev.Keys) {
            if ($null -eq $prev[$k]) {
                Remove-Item -LiteralPath "Env:$k" -ErrorAction SilentlyContinue
            } else {
                Set-Item -Path "Env:$k" -Value $prev[$k]
            }
        }
    }
}

function Invoke-Remote {
    param(
        [hashtable]$Cfg,
        [string]$Ssh,
        [string]$RemoteCommand
    )
    $sshArgs = @($script:LegacySshOptions) + @("$($Cfg.User)@$($Cfg.Host)", $RemoteCommand)
    Invoke-WithSshAskPass -Cfg $Cfg -Action {
        & $Ssh @sshArgs
        $script:LastSshExitCode = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
    }
    return $script:LastSshExitCode
}

function Invoke-TarUpload {
    param(
        [hashtable]$Cfg,
        [string]$Ssh,
        [string]$Tar,
        [string]$LocalParent,
        [string]$LeafName,
        [string]$RemoteParent,
        [string]$Label
    )

    if (-not (Test-Path -LiteralPath (Join-Path $LocalParent $LeafName))) {
        Write-Die "path missing locally: $(Join-Path $LocalParent $LeafName)"
    }

    $mkdirCmd = "mkdir -p $RemoteParent"
    $ec = Invoke-Remote -Cfg $Cfg -Ssh $Ssh -RemoteCommand $mkdirCmd
    if ($ec -ne 0) { Write-Die "remote mkdir failed (exit $ec): $mkdirCmd" }

    # cmd.exe pipe keeps the tar stream binary-safe (PowerShell 5.x pipes are not).
    $remote = "$($Cfg.User)@$($Cfg.Host)"
    $remoteCmd = "cd $RemoteParent && tar xf -"
    $opts = ($script:LegacySshOptions -join ' ')
    $cmdLine = " `"$Tar`" --format ustar -cf - -C `"$LocalParent`" `"$LeafName`" | `"$Ssh`" $opts $remote `"$remoteCmd`" "

    Write-Host "sync-src: tar|ssh $Label -> ${remote}:$RemoteParent/"
    Invoke-WithSshAskPass -Cfg $Cfg -Action {
        cmd.exe /c $cmdLine
        if ($LASTEXITCODE -ne 0) {
            Write-Die "tar|ssh failed (exit $LASTEXITCODE) for $Label"
        }
    }
}

function Show-Usage {
    Write-Host @"
Usage:
  powershell -File vm\sync-src.ps1 -All
  powershell -File vm\sync-src.ps1 -Path <path-under-src>

  -All     Upload the entire local src/ tree to RemoteRoot/src
  -Path    Upload one folder or file under src/ (path relative to src/)

Config: vm\vm.conf (Host, User, Password, RemoteRoot, LocalRoot, Ssh, Tar)
Uses OpenSSH with legacy KEX/hostkey/cipher/MAC options (see vm\SSH CONNECTION.md).
Transfers via tar|ssh (not scp — modern scp drops this guest).
Exactly one of -All or -Path is required.
"@
}

if ($All -and -not [string]::IsNullOrWhiteSpace($Path)) {
    Show-Usage
    Write-Die 'specify either -All or -Path, not both'
}
if (-not $All -and [string]::IsNullOrWhiteSpace($Path)) {
    Show-Usage
    exit 1
}

$cfg = Get-VmConfig
$ssh = Resolve-Tool $cfg.Ssh
$tar = Resolve-Tool $cfg.Tar
$localSrc = Join-Path $cfg.LocalRoot 'src'
if (-not (Test-Path -LiteralPath $localSrc)) {
    Write-Die "local src missing: $localSrc"
}

if ($All) {
    Invoke-TarUpload -Cfg $cfg -Ssh $ssh -Tar $tar `
        -LocalParent $cfg.LocalRoot -LeafName 'src' `
        -RemoteParent $cfg.RemoteRoot -Label 'src'
} else {
    $rel = $Path.Trim().TrimStart('/', '\').Replace('\', '/')
    $local = Join-Path $localSrc ($rel -replace '/', [IO.Path]::DirectorySeparatorChar)
    if (-not (Test-Path -LiteralPath $local)) {
        Write-Die "path missing locally: $local"
    }

    $leaf = Split-Path -Leaf $rel
    $parentRel = Split-Path -Parent $rel
    if ([string]::IsNullOrWhiteSpace($parentRel)) {
        $localParent = $localSrc
        $remoteParent = "$($cfg.RemoteRoot)/src"
    } else {
        $localParent = Join-Path $localSrc ($parentRel -replace '/', [IO.Path]::DirectorySeparatorChar)
        $remoteParent = "$($cfg.RemoteRoot)/src/$($parentRel.Replace('\', '/'))"
    }

    Invoke-TarUpload -Cfg $cfg -Ssh $ssh -Tar $tar `
        -LocalParent $localParent -LeafName $leaf `
        -RemoteParent $remoteParent -Label "src/$rel"
}

Write-Host 'sync-src: complete'
