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
Transfers via tar|ssh (not scp). Post-sync restores +x on configure/scripts.
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
    $named = "find $RemoteTree -type f \( -name configure -o -name config.guess -o -name config.sub -o -name config.rpath -o -name install-sh -o -name mkinstalldirs -o -name missing -o -name ltmain.sh -o -name compile -o -name depcomp -o -name autogen.sh -o -name build_gcc -o -name move-if-change -o -name ylwrap -o -name genmultilib -o -name '*.sh' -o -name '*.pl' \) -exec chmod a+x {} \;"
    $ec = Invoke-RhapRemote -Cfg $Cfg -Ssh $Ssh -RemoteCommand $named
    if ($ec -ne 0) {
        Write-Host "sync-src: warning: chmod pass exited $ec (continuing)"
    }
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
    $ec = Invoke-RhapRemote -Cfg $Cfg -Ssh $Ssh -RemoteCommand $mkdirCmd
    if ($ec -ne 0) { Write-Die "remote mkdir failed (exit $ec): $mkdirCmd" }

    # cmd.exe pipe keeps the tar stream binary-safe (PowerShell 5.x pipes are not).
    $remote = "$($Cfg.User)@$($Cfg.Host)"
    $remoteCmd = "cd $RemoteParent && tar xf -"
    $opts = ($script:RhapLegacySshOptions -join ' ')
    $cmdLine = " `"$Tar`" --format ustar -cf - -C `"$LocalParent`" `"$LeafName`" | `"$Ssh`" $opts $remote `"$remoteCmd`" "

    Write-Host "sync-src: tar|ssh $Label -> ${remote}:$RemoteParent/"
    Invoke-RhapSshAskPass -Cfg $Cfg -Action {
        cmd.exe /c $cmdLine
        if ($LASTEXITCODE -ne 0) {
            Write-Die "tar|ssh failed (exit $LASTEXITCODE) for $Label"
        }
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
