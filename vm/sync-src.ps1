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

  After extract, restores +x on configure/scripts (Windows tar drops Unix mode bits).
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
Transfers via cpio over SSH (not scp). Post-sync restores +x on configure/scripts.
Exactly one of -All or -Path is required.
"@
}

function Invoke-FixExecBits {
    param(
        [hashtable]$Cfg,
        [string]$Ssh,
        [string]$RemoteTree
    )
    # Windows ustar extract typically yields 0644. Named helpers only — a
    # full-tree shebang walk over Darwin sources is too slow on the guest.
    Write-Host "sync-src: restoring +x under $RemoteTree"
    $named = New-RhapFixExecBitsCommand -RemoteTree $RemoteTree
    $ec = Invoke-RhapRemote -Cfg $Cfg -Ssh $Ssh -RemoteCommand $named
    if ($ec -ne 0) {
        Write-Host "sync-src: warning: chmod pass exited $ec (continuing)"
    }
}

function ConvertTo-ProcessArgument([string]$Value) {
    return '"' + $Value.Replace('"', '\"') + '"'
}

function Invoke-CpioUpload {
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

    $remote = "$($Cfg.User)@$($Cfg.Host)"
    $token = [guid]::NewGuid().ToString('n')
    $remoteCmd = New-RhapSyncRemoteCommand -RemoteRoot $Cfg.RemoteRoot -RemoteParent $RemoteParent -LeafName $LeafName -Token $token
    $producer = {
        param($ArchivePath, $ArchiveParent, $ArchiveLeaf)
        Write-Host "sync-src: creating cpio archive for $Label"
        & $Tar --format cpio -cf $ArchivePath -C $ArchiveParent -- $ArchiveLeaf
        return [int]$LASTEXITCODE
    }
    $consumer = {
        param($ArchivePath)
        $sshArgs = @('-T') + $script:RhapLegacySshOptions + @($remote, $remoteCmd)
        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName = $Ssh
        $startInfo.Arguments = (($sshArgs | ForEach-Object { ConvertTo-ProcessArgument $_ }) -join ' ')
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardInput = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $startInfo
        $result = [pscustomobject]@{ ExitCode = -1; Started = $false }
        try {
            Write-Host "sync-src: cpio over SSH $Label -> ${remote}:$RemoteParent/"
            Invoke-RhapSshAskPass -Cfg $Cfg -Action {
                if (-not $process.Start()) { throw "could not start SSH: $Ssh" }
                $result.Started = $true
                $stdoutTask = $process.StandardOutput.ReadToEndAsync()
                $stderrTask = $process.StandardError.ReadToEndAsync()
                $input = [System.IO.File]::OpenRead($ArchivePath)
                try {
                    $input.CopyTo($process.StandardInput.BaseStream)
                } finally {
                    $input.Dispose()
                    $process.StandardInput.Close()
                }
                $process.WaitForExit()
                $stdout = [string]$stdoutTask.Result
                $stderr = [string]$stderrTask.Result
                if (-not [string]::IsNullOrWhiteSpace($stdout)) { Write-Host $stdout.TrimEnd("`r", "`n") }
                if (-not [string]::IsNullOrWhiteSpace($stderr)) { Write-Host $stderr.TrimEnd("`r", "`n") }
                $result.ExitCode = [int]$process.ExitCode
            }
            return [int]$result.ExitCode
        } finally {
            if ($result.Started) {
                try { if (-not $process.HasExited) { $process.Kill() } } catch { }
                try { $process.WaitForExit() } catch { }
            }
            $process.Dispose()
        }
    }
    try {
        Invoke-RhapCpioTransfer -LocalParent $LocalParent -LeafName $LeafName -Producer $producer -Consumer $consumer
    } catch {
        Write-Die "$($_.Exception.Message) for $Label"
    }

    $remoteTree = "$RemoteParent/$LeafName"
    Invoke-FixExecBits -Cfg $Cfg -Ssh $Ssh -RemoteTree $remoteTree
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
$localSrc = Join-Path $cfg.LocalRoot 'src'
if (-not (Test-Path -LiteralPath $localSrc)) {
    Write-Die "local src missing: $localSrc"
}

if ($All) {
    Invoke-CpioUpload -Cfg $cfg -Ssh $ssh -Tar $tar `
        -LocalParent $cfg.LocalRoot -LeafName 'src' `
        -RemoteParent $cfg.RemoteRoot -Label 'src'
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

    Invoke-CpioUpload -Cfg $cfg -Ssh $ssh -Tar $tar `
        -LocalParent $localParent -LeafName $leaf `
        -RemoteParent $remoteParent -Label "src/$rel"
}

Write-Host 'sync-src: complete'
