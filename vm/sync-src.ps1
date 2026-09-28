#Requires -Version 5.0
<#
.SYNOPSIS
  Sync local src/ to the Rhapsody guest build tree (RemoteRoot/src) via cpio over SSH.
.EXAMPLE
  powershell -File vm\sync-src.ps1 -All
  powershell -File vm\sync-src.ps1 -Path drivers-i386/bus/drvPCMCIABus
.NOTES
  The PPC Rhapsody sshd only speaks ancient crypto. This script passes the same
  OpenSSH -o options documented in "SSH CONNECTION.md".

  Modern OpenSSH scp loses the connection against this guest even with -O, so
  transfers use a temporary cpio archive sent to ssh as a binary stream.

  After extract, sets exactly the execute bits git records (Windows tar drops
  Unix mode bits); untracked configure/scripts get +x by name.
#>
param(
    [switch]$All,

    [Parameter()]
    [string]$Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$VmDir = $PSScriptRoot
. (Join-Path $VmDir 'rhap-remote.ps1')
. (Join-Path $VmDir 'sync-src-lib.ps1')

function Write-Die([string]$Message) {
    Write-RhapDie 'sync-src' $Message
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
Transfers via cpio over SSH (not scp). Post-sync sets the execute bits git records.
Exactly one of -All or -Path is required.
"@
}

function Invoke-FixExecBits {
    param(
        [hashtable]$Cfg,
        [string]$Ssh,
        [string]$RemoteTree,
        [string[]]$ExecutablePaths
    )
    # Windows tar drops Unix mode bits; set the ones git records. The path
    # list outgrows the guest csh's 10240-byte limit, so it goes over stdin.
    Write-Host "sync-src: setting git execute bits under $RemoteTree ($($ExecutablePaths.Count) executable)"
    $fixExec = New-RhapFixExecBitsCommand -RemoteSrc "$($Cfg.RemoteRoot)/src" -RemoteTree $RemoteTree -ExecutablePaths $ExecutablePaths
    $ec = Invoke-RhapSshScript -Cfg $Cfg -Ssh $Ssh -ScriptBody $fixExec
    if ($ec -ne 0) {
        Write-Die "chmod pass exited $ec"
    }
}

function Invoke-CpioUpload {
    param(
        [hashtable]$Cfg,
        [string]$Ssh,
        [string]$Tar,
        [string]$Git,
        [string]$LocalParent,
        [string]$LeafName,
        [string]$RemoteParent,
        [string]$Label,
        [string]$Pathspec
    )

    if (-not (Test-Path -LiteralPath (Join-Path $LocalParent $LeafName))) {
        Write-Die "path missing locally: $(Join-Path $LocalParent $LeafName)"
    }

    try {
        $executables = @(Get-RhapSyncExecutablePaths -Git $Git -LocalSrc (Join-Path $Cfg.LocalRoot 'src') -Pathspec $Pathspec)
    } catch {
        Write-Die "$($_.Exception.Message) for $Label"
    }

    $remote = "$($Cfg.User)@$($Cfg.Host)"
    $token = [guid]::NewGuid().ToString('n')
    $transactionBody = New-RhapSyncRemoteCommand -RemoteRoot $Cfg.RemoteRoot -RemoteParent $RemoteParent -LeafName $LeafName -Token $token
    $remoteCmd = New-RhapArchiveSshCommand -ScriptBody $transactionBody
    $producer = {
        param($ArchivePath, $ArchiveParent, $ArchiveLeaf)
        Write-Host "sync-src: creating cpio archive for $Label"
        & $Tar --format cpio -cf $ArchivePath -C $ArchiveParent -- $ArchiveLeaf
        return [int]$LASTEXITCODE
    }
    $consumer = {
        param($ArchivePath)
        $sshArgs = @('-T') + $script:RhapLegacySshOptions + @($remote, $remoteCmd)
        $result = [pscustomobject]@{ ExitCode = -1 }
        Write-Host "sync-src: cpio over SSH $Label -> ${remote}:$RemoteParent/"
        Invoke-RhapSshAskPass -Cfg $Cfg -Action {
            $result.ExitCode = Invoke-RhapArchiveConsumerProcess -Executable $Ssh -Arguments $sshArgs -ArchivePath $ArchivePath
        }
        return [int]$result.ExitCode
    }
    try {
        Invoke-RhapCpioTransfer -LocalParent $LocalParent -LeafName $LeafName -Producer $producer -Consumer $consumer
    } catch {
        Write-Die "$($_.Exception.Message) for $Label"
    }

    $remoteTree = "$RemoteParent/$LeafName"
    Invoke-FixExecBits -Cfg $Cfg -Ssh $Ssh -RemoteTree $remoteTree -ExecutablePaths $executables
}

if ($All -and -not [string]::IsNullOrWhiteSpace($Path)) {
    Show-Usage
    Write-Die 'specify either -All or -Path, not both'
}
if (-not $All -and [string]::IsNullOrWhiteSpace($Path)) {
    Show-Usage
    exit 1
}

$cfg = Get-RhapVmConfig -DiePrefix 'sync-src'
$ssh = Resolve-RhapTool -NameOrPath $cfg.Ssh -DiePrefix 'sync-src'
$tar = Resolve-RhapTool -NameOrPath $cfg.Tar -DiePrefix 'sync-src'
$git = Resolve-RhapTool -NameOrPath 'git.exe' -DiePrefix 'sync-src'
$localSrc = Join-Path $cfg.LocalRoot 'src'
if (-not (Test-Path -LiteralPath $localSrc)) {
    Write-Die "local src missing: $localSrc"
}

if ($All) {
    Invoke-CpioUpload -Cfg $cfg -Ssh $ssh -Tar $tar -Git $git `
        -LocalParent $cfg.LocalRoot -LeafName 'src' `
        -RemoteParent $cfg.RemoteRoot -Label 'src' -Pathspec '.'
} else {
    $rel = ConvertTo-RhapSyncRelativePath -Path $Path
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

    Invoke-CpioUpload -Cfg $cfg -Ssh $ssh -Tar $tar -Git $git `
        -LocalParent $localParent -LeafName $leaf `
        -RemoteParent $remoteParent -Label "src/$rel" -Pathspec $rel
}

Write-Host 'sync-src: complete'
