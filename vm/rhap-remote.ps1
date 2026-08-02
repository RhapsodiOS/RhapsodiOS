# Shared OpenSSH helpers for Rhapsody PPC guest scripts (sync-src, build-src).
# Dot-source from the same directory:  . "$PSScriptRoot\rhap-remote.ps1"

Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'build-src-lib.ps1')

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
        RemoteRoot = '/build'
        LocalRoot  = ''
        Ssh        = 'ssh.exe'
        Tar        = 'tar.exe'
        Make       = 'gnumake'
        RepoDir    = '/build/repo'
        BuiltDir   = '/build/built'
        ToolsDir   = '/build/tools'
        BootstrapRoot = '/build/bootstrap-root'
        StateDir   = '/build/state'
        ToolchainProfile = 'rbuild-1/toolchains/gcc-darwin.conf'
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
    $cfg.RemoteRoot = ConvertTo-RhapNormalizedRemotePath -Path $cfg.RemoteRoot -Name 'RemoteRoot'
    if ($cfg.RemoteRoot -eq '/') { throw 'RemoteRoot may not be the filesystem root' }
    foreach ($key in @('RepoDir', 'BuiltDir', 'ToolsDir', 'BootstrapRoot', 'StateDir')) {
        $cfg[$key] = ConvertTo-RhapNormalizedRemotePath -Path $cfg[$key] -Name $key
        if ($cfg[$key] -eq '/') { Write-RhapDie $DiePrefix "$key may not be the filesystem root" }
    }
    if (-not $cfg.ToolchainProfile.StartsWith('/')) {
        $cfg.ToolchainProfile = "$($cfg.RemoteRoot)/src/$($cfg.ToolchainProfile)"
    }
    $cfg.ToolchainProfile = ConvertTo-RhapNormalizedRemotePath -Path $cfg.ToolchainProfile -Name 'ToolchainProfile'
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

function New-RhapSshStandardInputEncoding {
    return New-Object System.Text.UTF8Encoding($false, $true)
}

function ConvertTo-RhapSshPayload {
    param([string]$ScriptBody)

    $payload = $ScriptBody.Replace("`r`n", "`n").Replace("`r", "`n").TrimEnd("`n") + "`n"
    [void](New-RhapSshStandardInputEncoding).GetByteCount($payload)
    return $payload
}

function Start-RhapSshProcess {
    param(
        [System.Diagnostics.Process]$Process,
        [string]$Ssh
    )

    $started = $false
    [System.Threading.Monitor]::Enter([Console])
    try {
        $previousEncoding = [Console]::InputEncoding
        try {
            [Console]::InputEncoding = New-RhapSshStandardInputEncoding
            if (-not $Process.Start()) { throw "could not start SSH: $Ssh" }
            $started = $true
            return $Process.StandardInput
        } catch {
            if ($started) {
                try { if (-not $Process.HasExited) { $Process.Kill() } } catch { }
                try { $Process.WaitForExit() } catch { }
            }
            throw
        } finally {
            [Console]::InputEncoding = $previousEncoding
        }
    } finally {
        [System.Threading.Monitor]::Exit([Console])
    }
}

function Invoke-RhapSshScript {
    param(
        [hashtable]$Cfg,
        [string]$Ssh,
        [string]$ScriptBody,
        [scriptblock]$Invoker,
        [switch]$Stream,
        [scriptblock]$Observer
    )

    $payload = ConvertTo-RhapSshPayload -ScriptBody $ScriptBody
    $sshArgs = @('-T') + $script:RhapLegacySshOptions + @(
        "$($Cfg.User)@$($Cfg.Host)",
        '/bin/sh -s'
    )

    Invoke-RhapSshAskPass -Cfg $Cfg -Action {
        $emitStdout = {
            param([string]$Line)
            if ($Observer) { & $Observer 'stdout' $Line }
            Write-Host $Line
        }
        $emitStderr = {
            param([string]$Line)
            if ($Observer) { & $Observer 'stderr' $Line }
            Write-Host $Line
        }
        if ($Invoker) {
            $script:RhapLastSshExitCode = [int](& $Invoker $Ssh $sshArgs $payload ([bool]$Stream) $emitStdout $emitStderr)
            return
        }

        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName = $Ssh
        $startInfo.Arguments = (($sshArgs | ForEach-Object {
            '"' + $_.Replace('"', '\"') + '"'
        }) -join ' ')
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardInput = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true

        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $startInfo
        $processStarted = $false
        $stdinClosed = $false
        $stdinWriter = $null
        try {
            $stdinWriter = Start-RhapSshProcess -Process $process -Ssh $Ssh
            $processStarted = $true
            if ($Stream) {
                $stdoutDone = $false
                $stderrDone = $false
                $stdoutTask = $process.StandardOutput.ReadLineAsync()
                $stderrTask = $process.StandardError.ReadLineAsync()
                $writeDone = $false
                $writeError = $null
                $readError = $null
                $sinkError = $null
                $sinkSuppressed = $false
                try {
                    $writeTask = $stdinWriter.WriteAsync($payload)
                } catch {
                    $writeError = $_.Exception
                    $writeDone = $true
                    try { $stdinWriter.Close() } catch { }
                    $stdinClosed = $true
                }
                while (-not $writeDone -or -not $stdoutDone -or -not $stderrDone) {
                    $waitTasks = New-Object 'System.Collections.Generic.List[System.Threading.Tasks.Task]'
                    if (-not $writeDone) { $waitTasks.Add($writeTask) }
                    if (-not $stdoutDone) { $waitTasks.Add($stdoutTask) }
                    if (-not $stderrDone) { $waitTasks.Add($stderrTask) }
                    [void][System.Threading.Tasks.Task]::WaitAny($waitTasks.ToArray())
                    if (-not $writeDone -and $writeTask.IsCompleted) {
                        try { [void]$writeTask.GetAwaiter().GetResult() } catch { $writeError = $_.Exception }
                        $writeDone = $true
                        try { $stdinWriter.Close() } catch { if (-not $writeError) { $writeError = $_.Exception } }
                        $stdinClosed = $true
                    }
                    if (-not $stdoutDone -and $stdoutTask.IsCompleted) {
                        $line = $null
                        $readFailed = $false
                        try {
                            $line = $stdoutTask.GetAwaiter().GetResult()
                        } catch {
                            if (-not $readError) { $readError = $_.Exception }
                            $stdoutDone = $true
                            $readFailed = $true
                        }
                        if (-not $readFailed) {
                            if ($null -eq $line) {
                                $stdoutDone = $true
                            } else {
                                $stdoutTask = $process.StandardOutput.ReadLineAsync()
                                if (-not $sinkSuppressed) {
                                    try { & $emitStdout $line } catch { if (-not $sinkError) { $sinkError = $_.Exception }; $sinkSuppressed = $true }
                                }
                            }
                        }
                    }
                    if (-not $stderrDone -and $stderrTask.IsCompleted) {
                        $line = $null
                        $readFailed = $false
                        try {
                            $line = $stderrTask.GetAwaiter().GetResult()
                        } catch {
                            if (-not $readError) { $readError = $_.Exception }
                            $stderrDone = $true
                            $readFailed = $true
                        }
                        if (-not $readFailed) {
                            if ($null -eq $line) {
                                $stderrDone = $true
                            } else {
                                $stderrTask = $process.StandardError.ReadLineAsync()
                                if (-not $sinkSuppressed) {
                                    try { & $emitStderr $line } catch { if (-not $sinkError) { $sinkError = $_.Exception }; $sinkSuppressed = $true }
                                }
                            }
                        }
                    }
                    if ($readError) {
                        if (-not $stdinClosed) { try { $stdinWriter.Close() } catch { }; $stdinClosed = $true }
                        try { if (-not $process.HasExited) { $process.Kill() } } catch { }
                        try { $process.WaitForExit() } catch { }
                        if (-not $writeDone) { try { [void]$writeTask.GetAwaiter().GetResult() } catch { }; $writeDone = $true }
                        if (-not $stdoutDone) { try { [void]$stdoutTask.GetAwaiter().GetResult() } catch { }; $stdoutDone = $true }
                        if (-not $stderrDone) { try { [void]$stderrTask.GetAwaiter().GetResult() } catch { }; $stderrDone = $true }
                        throw $readError
                    }
                }
                if (-not $stdinClosed) { $stdinWriter.Close(); $stdinClosed = $true }
                $process.WaitForExit()
                $script:RhapLastSshExitCode = [int]$process.ExitCode
                if ($writeError) { throw $writeError }
                if ($sinkError) { throw $sinkError }
            } else {
                $stdoutTask = $process.StandardOutput.ReadToEndAsync()
                $stderrTask = $process.StandardError.ReadToEndAsync()
                $stdinWriter.Write($payload)
                $stdinWriter.Close()
                $stdinClosed = $true
                $process.WaitForExit()
                $stdout = $stdoutTask.Result
                $stderr = $stderrTask.Result
                if (-not [string]::IsNullOrEmpty($stdout)) { & $emitStdout ($stdout.TrimEnd("`r", "`n")) }
                if (-not [string]::IsNullOrEmpty($stderr)) { & $emitStderr ($stderr.TrimEnd("`r", "`n")) }
                $script:RhapLastSshExitCode = [int]$process.ExitCode
            }
        } finally {
            if ($processStarted -and $stdinWriter -and -not $stdinClosed) {
                try { $stdinWriter.Close() } catch { }
            }
            if ($Stream -and $processStarted) {
                try { if (-not $process.HasExited) { $process.Kill() } } catch { }
                try { $process.WaitForExit() } catch { }
            }
            $process.Dispose()
        }
    }
    return ,[int]$script:RhapLastSshExitCode
}

function Invoke-RhapSshCapture {
    param(
        [hashtable]$Cfg,
        [string]$Ssh,
        [string]$ScriptBody,
        [scriptblock]$Invoker
    )
    $payload = ConvertTo-RhapSshPayload -ScriptBody $ScriptBody
    $sshArgs = @('-T') + $script:RhapLegacySshOptions + @("$($Cfg.User)@$($Cfg.Host)", '/bin/sh -s')
    Invoke-RhapSshAskPass -Cfg $Cfg -Action {
        if ($Invoker) {
            $script:RhapLastSshCapture = & $Invoker $Ssh $sshArgs $payload
            return
        }
        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName = $Ssh
        $startInfo.Arguments = (($sshArgs | ForEach-Object { '"' + $_.Replace('"', '\"') + '"' }) -join ' ')
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardInput = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $startInfo
        $stdinWriter = $null
        $stdinClosed = $false
        try {
            $stdinWriter = Start-RhapSshProcess -Process $process -Ssh $Ssh
            $stdoutTask = $process.StandardOutput.ReadToEndAsync()
            $stderrTask = $process.StandardError.ReadToEndAsync()
            $stdinWriter.Write($payload)
            $stdinWriter.Close()
            $stdinClosed = $true
            $process.WaitForExit()
            $script:RhapLastSshCapture = [pscustomobject]@{
                ExitCode = [int]$process.ExitCode
                Stdout = [string]$stdoutTask.Result
                Stderr = [string]$stderrTask.Result
            }
        } finally {
            if ($stdinWriter -and -not $stdinClosed) {
                try { $stdinWriter.Close() } catch { }
            }
            $process.Dispose()
        }
    }
    return $script:RhapLastSshCapture
}
