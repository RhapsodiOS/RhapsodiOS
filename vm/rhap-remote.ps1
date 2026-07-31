# Shared OpenSSH helpers for Rhapsody PPC guest scripts (sync-src, build-src).
# Dot-source from the same directory:  . "$PSScriptRoot\rhap-remote.ps1"

Set-StrictMode -Version Latest

if (-not (Get-Variable -Name RhapVmDir -Scope Script -ErrorAction SilentlyContinue) -or
    [string]::IsNullOrWhiteSpace($script:RhapVmDir)) {
    $script:RhapVmDir = $PSScriptRoot
}
$script:RhapConfPath = Join-Path $script:RhapVmDir 'vm.conf'

$script:RhapKnownHostsFile = Join-Path $env:TEMP 'rhap-known_hosts'
if (-not (Test-Path -LiteralPath $script:RhapKnownHostsFile)) {
    New-Item -ItemType File -Path $script:RhapKnownHostsFile -Force | Out-Null
}
$rhapKnownHostsOpt = ($script:RhapKnownHostsFile -replace '\\', '/')
$script:RhapLegacySshOptions = @(
    '-o', 'KexAlgorithms=diffie-hellman-group1-sha1',
    '-o', 'HostKeyAlgorithms=ssh-dss',
    '-o', 'Ciphers=3des-cbc',
    '-o', 'MACs=hmac-sha1',
    '-o', 'PubkeyAuthentication=no',
    '-o', 'StrictHostKeyChecking=no',
    '-o', "UserKnownHostsFile=$rhapKnownHostsOpt"
)

function Write-RhapDie {
    param(
        [string]$Prefix,
        [string]$Message
    )
    Write-Error "${Prefix}: $Message"
    exit 1
}

function Get-RhapVmConfig {
    param(
        [string]$DiePrefix = 'rhap',
        [hashtable]$ExtraDefaults = @{}
    )
    if (-not (Test-Path -LiteralPath $script:RhapConfPath)) {
        Write-RhapDie $DiePrefix "missing $($script:RhapConfPath) - copy vm.conf.example to vm.conf and edit"
    }
    $cfg = @{
        Host       = ''
        User       = ''
        Password   = ''
        RemoteRoot = '/build/source'
        LocalRoot  = ''
        Ssh        = 'ssh.exe'
        Tar        = 'tar.exe'
        Make       = 'gnumake'
        RepoDir    = '/build/repo'
        BuiltDir   = '/build/built'
    }
    foreach ($k in $ExtraDefaults.Keys) { $cfg[$k] = $ExtraDefaults[$k] }

    Get-Content -LiteralPath $script:RhapConfPath | ForEach-Object {
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
            Write-RhapDie $DiePrefix "vm.conf missing required key: $req"
        }
    }
    if ([string]::IsNullOrWhiteSpace($cfg.LocalRoot)) {
        $cfg.LocalRoot = Split-Path -Parent $script:RhapVmDir
    }
    $cfg.RemoteRoot = $cfg.RemoteRoot.TrimEnd('/')
    $cfg.RepoDir = $cfg.RepoDir.TrimEnd('/')
    $cfg.BuiltDir = $cfg.BuiltDir.TrimEnd('/')
    if ([string]::IsNullOrWhiteSpace($cfg.Make)) { $cfg.Make = 'gnumake' }
    return $cfg
}

function Resolve-RhapTool {
    param(
        [string]$NameOrPath,
        [string]$DiePrefix = 'rhap'
    )
    if (Test-Path -LiteralPath $NameOrPath) {
        return (Resolve-Path -LiteralPath $NameOrPath).Path
    }
    $cmd = Get-Command $NameOrPath -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    Write-RhapDie $DiePrefix "tool not found: $NameOrPath"
}

function Invoke-RhapSshAskPass {
    param(
        [hashtable]$Cfg,
        [scriptblock]$Action
    )
    $ask = Join-Path $env:TEMP ("rhap-askpass-{0}.cmd" -f [guid]::NewGuid().ToString('n'))
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
        # Do not return Action output — callers that assign the result would
        # capture ssh/make stdout as if it were an exit code.
        & $Action
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

function Invoke-RhapRemote {
    param(
        [hashtable]$Cfg,
        [string]$Ssh,
        [string]$RemoteCommand
    )
    # -tt: force a tty so ancient sshd still forwards remote stdout/stderr.
    $sshArgs = @('-tt') + $script:RhapLegacySshOptions + @("$($Cfg.User)@$($Cfg.Host)", $RemoteCommand)
    Invoke-RhapSshAskPass -Cfg $Cfg -Action {
        # Out-Host keeps make/rbuild logs visible without putting them on the
        # success stream (which would pollute `$ec = Invoke-RhapRemote ...`).
        # Continue EAP: OpenSSH prints "Connection ... closed." on stderr; with
        # Stop that becomes a terminating ErrorRecord when merged via 2>&1.
        $prevEap = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            & $Ssh @sshArgs 2>&1 | ForEach-Object { Write-Host ("$_") }
            $script:RhapLastSshExitCode = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
        } finally {
            $ErrorActionPreference = $prevEap
        }
    }
    return ,[int]$script:RhapLastSshExitCode
}
