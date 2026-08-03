Set-StrictMode -Version Latest

function ConvertTo-RhapSyncRelativePath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $relative = $Path.Trim().Replace('\', '/')
    if ([string]::IsNullOrWhiteSpace($relative) -or $relative.StartsWith('/') -or $relative -match '^[A-Za-z]:/') {
        throw 'sync path must be relative to src'
    }
    foreach ($component in ($relative -split '/')) {
        if ([string]::IsNullOrEmpty($component) -or $component -eq '.' -or $component -eq '..') {
            throw 'sync path contains an unsafe component'
        }
    }
    if ($relative -match '[\x00-\x1f\x7f]') { throw 'sync path contains control characters' }
    return $relative
}

function Invoke-RhapCpioTransfer {
    param(
        [Parameter(Mandatory = $true)][string]$LocalParent,
        [Parameter(Mandatory = $true)][string]$LeafName,
        [Parameter(Mandatory = $true)][scriptblock]$Producer,
        [Parameter(Mandatory = $true)][scriptblock]$Consumer,
        [string]$TempDirectory = $env:TEMP
    )

    $archive = Join-Path $TempDirectory ("rhap-sync-{0}.cpio" -f [guid]::NewGuid().ToString('n'))
    try {
        $producerExit = [int](& $Producer $archive $LocalParent $LeafName)
        if ($producerExit -ne 0) { throw "cpio archive creation failed (exit $producerExit)" }
        if (-not (Test-Path -LiteralPath $archive -PathType Leaf)) { throw 'cpio archive creation produced no archive' }
        $consumerExit = [int](& $Consumer $archive)
        if ($consumerExit -ne 0) { throw "cpio over SSH failed (exit $consumerExit)" }
    } finally {
        Remove-Item -LiteralPath $archive -Force -ErrorAction SilentlyContinue
    }
}

function New-RhapFixExecBitsCommand {
    param([Parameter(Mandatory = $true)][string]$RemoteTree)

    $tree = ConvertTo-RhapShellLiteral $RemoteTree
    return "find $tree -type f \( -name configure -o -name Configure -o -name config.guess -o -name config.sub -o -name config.rpath -o -name install-sh -o -name mkinstalldirs -o -name missing -o -name ltmain.sh -o -name compile -o -name depcomp -o -name autogen.sh -o -name build_gcc -o -name move-if-change -o -name ylwrap -o -name genmultilib -o -name '*.sh' -o -name '*.pl' \) -exec chmod a+x {} \;"
}

function ConvertTo-RhapShellDoubleQuotedAssignmentValue {
    param([Parameter(Mandatory = $true)][string]$Value)

    if ($Value.Contains("'")) { throw 'shell value contains an unsupported quote' }
    $escaped = $Value.Replace('\', '\\').Replace('"', '\"').Replace('$', '\$').Replace('`', '\`')
    return '"' + $escaped + '"'
}

function New-RhapArchiveSshCommand {
    param([Parameter(Mandatory = $true)][string]$ScriptBody)

    if ($ScriptBody.Contains("'")) { throw 'archive transaction body contains an unsupported quote' }
    return "/bin/sh -c '$ScriptBody'"
}

function ConvertTo-RhapProcessArgument {
    param([Parameter(Mandatory = $true)][string]$Value)
    return '"' + $Value.Replace('"', '\"') + '"'
}

function Invoke-RhapArchiveConsumerProcess {
    param(
        [Parameter(Mandatory = $true)][string]$Executable,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$ArchivePath,
        [scriptblock]$Observer
    )

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $Executable
    $startInfo.Arguments = (($Arguments | ForEach-Object { ConvertTo-RhapProcessArgument $_ }) -join ' ')
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    $started = $false
    $reaped = $false
    $stdinClosed = $false
    $transportError = $null
    try {
        if (-not $process.Start()) { throw "could not start archive consumer: $Executable" }
        $started = $true
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $input = [System.IO.File]::OpenRead($ArchivePath)
        try {
            try { $input.CopyTo($process.StandardInput.BaseStream) } catch { $transportError = $_.Exception }
        } finally {
            $input.Dispose()
            try { $process.StandardInput.Close() } catch { if (-not $transportError) { $transportError = $_.Exception } }
            $stdinClosed = $true
        }

        $waitError = $null
        try {
            $process.WaitForExit()
            $reaped = $true
        } catch {
            $waitError = $_.Exception
        }
        $stdout = [string]$stdoutTask.Result
        $stderr = [string]$stderrTask.Result
        if (-not [string]::IsNullOrWhiteSpace($stdout)) {
            if ($Observer) { & $Observer 'stdout' $stdout }
            Write-Host $stdout.TrimEnd("`r", "`n")
        }
        if (-not [string]::IsNullOrWhiteSpace($stderr)) {
            if ($Observer) { & $Observer 'stderr' $stderr }
            Write-Host $stderr.TrimEnd("`r", "`n")
        }
        if (-not $waitError -and $process.ExitCode -ne 0) { return [int]$process.ExitCode }
        if ($transportError) { throw $transportError }
        if ($waitError) { throw $waitError }
        return 0
    } finally {
        if ($started -and -not $stdinClosed) { try { $process.StandardInput.Close() } catch { } }
        if ($started -and -not $reaped) {
            try { if (-not $process.HasExited) { $process.Kill() } } catch { }
            try { $process.WaitForExit(); $reaped = $true } catch { }
        }
        $process.Dispose()
    }
}

function New-RhapSyncRemoteCommand {
    param(
        [Parameter(Mandatory = $true)][string]$RemoteRoot,
        [Parameter(Mandatory = $true)][string]$RemoteParent,
        [Parameter(Mandatory = $true)][string]$LeafName,
        [Parameter(Mandatory = $true)][string]$Token,
        [string]$Cpio = '/usr/bin/cpio'
    )

    $root = ConvertTo-RhapNormalizedRemotePath -Path $RemoteRoot -Name 'RemoteRoot'
    if ($root -eq '/') { throw 'RemoteRoot may not be the filesystem root' }
    $normalizedParent = ConvertTo-RhapNormalizedRemotePath -Path $RemoteParent -Name 'RemoteParent'
    if ($normalizedParent -ne $root -and
        -not $normalizedParent.StartsWith($root + '/', [System.StringComparison]::Ordinal)) {
        throw 'RemoteParent must be RemoteRoot or its descendant'
    }
    if ([string]::IsNullOrWhiteSpace($LeafName) -or $LeafName -eq '.' -or $LeafName -eq '..' -or
        $LeafName -match '[/\\\x00-\x1f\x7f]') {
        throw 'LeafName must be one safe path component'
    }
    if ([string]::Equals($LeafName, '.rhap-sync-lock', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'LeafName is reserved for sync locking'
    }
    if ($Token -notmatch '^[0-9a-f]{32}$') { throw 'Token must be 32 lowercase hexadecimal characters' }

    $remoteRootLiteral = ConvertTo-RhapShellDoubleQuotedAssignmentValue $root
    $parent = ConvertTo-RhapShellDoubleQuotedAssignmentValue $normalizedParent
    $leaf = ConvertTo-RhapShellDoubleQuotedAssignmentValue $LeafName
    $cpioCommand = ConvertTo-RhapShellDoubleQuotedAssignmentValue $Cpio
    $suffix = ConvertTo-RhapShellDoubleQuotedAssignmentValue $Token
    return @"
set -e
root=$remoteRootLiteral
parent=$parent
leaf=$leaf
suffix=$suffix
stage="`$parent/.rhap-sync-`$suffix"
old="`$parent/.rhap-old-`$suffix"
target="`$parent/`$leaf"
lock_root="`$parent/.rhap-sync-lock"
lock_version_file="`$lock_root/version"
lock_version=rhapsodios-sync-lock-v1
lock_targets="`$lock_root/targets"
lock="`$lock_targets/`$leaf"
saved=0
promoted=0
stage_created=0
lock_owned=0
cleanup() {
    status=`$?
    trap 0 1 2 15
    if test "`$promoted" -ne 1 && test "`$saved" -eq 1; then
        rm -rf "`$target"
        if mv "`$old" "`$target"; then saved=0; fi
    fi
    if test "`$stage_created" -eq 1; then rm -rf "`$stage"; fi
    if test "`$promoted" -eq 1; then rm -rf "`$old"; fi
    if test "`$lock_owned" -eq 1; then
        owner=`$(/bin/cat "`$lock/owner" 2>/dev/null || :)
        if test "`$owner" = "`$suffix"; then
            rm -f "`$lock/owner"
            rmdir "`$lock" 2>/dev/null || :
        fi
        lock_owned=0
    fi
    exit "`$status"
}
trap cleanup 0 1 2 15
test ! -L "`$root" || exit 74
ROOT_PHYS=`$(cd -P "`$root" 2>/dev/null && pwd -P) || exit 74
test "`$ROOT_PHYS" != / || exit 74
probe=`$parent
suffix_path=
while test "`$probe" != "`$root"; do
    test ! -L "`$probe" || exit 74
    if test -e "`$probe"; then break; fi
    component=`${probe##*/}
    suffix_path=/`$component`$suffix_path
    next=`${probe%/*}
    test -n "`$next" || next=/
    test "`$next" != "`$probe" || exit 74
    probe=`$next
done
test -d "`$probe" || exit 74
PARENT_BASE_PHYS=`$(cd -P "`$probe" 2>/dev/null && pwd -P) || exit 74
PARENT_PHYS=`$PARENT_BASE_PHYS`$suffix_path
case "`$PARENT_PHYS" in
    "`$ROOT_PHYS"|"`$ROOT_PHYS"/*) ;;
    *) exit 74 ;;
esac
mkdir -p "`$parent"
PARENT_ACTUAL_PHYS=`$(cd -P "`$parent" 2>/dev/null && pwd -P) || exit 74
case "`$PARENT_ACTUAL_PHYS" in
    "`$ROOT_PHYS"|"`$ROOT_PHYS"/*) ;;
    *) exit 74 ;;
esac
test ! -L "`$lock_root" || exit 74
if test ! -d "`$lock_root"; then
    if mkdir "`$lock_root" 2>/dev/null; then
        namespace_created=1
    else
        test -d "`$lock_root" || exit 76
        namespace_created=0
    fi
else
    namespace_created=0
fi
test ! -L "`$lock_root" || exit 74
LOCK_ROOT_PHYS=`$(cd -P "`$lock_root" 2>/dev/null && pwd -P) || exit 74
test "`$LOCK_ROOT_PHYS" = "`$PARENT_ACTUAL_PHYS/.rhap-sync-lock" || exit 74
if test "`$namespace_created" -eq 1; then
    if ! printf "%s\n" "`$lock_version" > "`$lock_version_file"; then
        rm -f "`$lock_version_file" 2>/dev/null || :
        rmdir "`$lock_root" 2>/dev/null || :
        exit 76
    fi
fi
test ! -L "`$lock_version_file" || exit 77
test -f "`$lock_version_file" || exit 77
published_version=`$(/bin/cat "`$lock_version_file" 2>/dev/null || :)
test "`$published_version" = "`$lock_version" || exit 77
test ! -L "`$lock_targets" || exit 74
if test ! -d "`$lock_targets"; then
    mkdir "`$lock_targets" 2>/dev/null || test -d "`$lock_targets" || exit 76
fi
test ! -L "`$lock_targets" || exit 74
LOCK_TARGETS_PHYS=`$(cd -P "`$lock_targets" 2>/dev/null && pwd -P) || exit 74
test "`$LOCK_TARGETS_PHYS" = "`$LOCK_ROOT_PHYS/targets" || exit 74
if ! mkdir "`$lock" 2>/dev/null; then
    exit 75
fi
lock_owned=1
if ! printf "%s\n" "`$suffix" > "`$lock/owner"; then
    rm -f "`$lock/owner" 2>/dev/null || :
    rmdir "`$lock" 2>/dev/null || :
    lock_owned=0
    exit 76
fi
if /bin/ls -d "`$old" >/dev/null 2>&1; then
    exit 73
fi
mkdir "`$stage"
stage_created=1
cd "`$stage"
$cpioCommand -idum
if ! test -f "`$stage/`$leaf" && ! test -d "`$stage/`$leaf"; then
    exit 66
fi
if /bin/ls -d "`$target" >/dev/null 2>&1; then
    mv "`$target" "`$old"
    saved=1
fi
mv "`$stage/`$leaf" "`$target"
promoted=1
rm -rf "`$stage" "`$old"
stage_created=0
saved=0
exit 0
"@
}
