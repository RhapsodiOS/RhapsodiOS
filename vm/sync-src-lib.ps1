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

# Git has no mode for untracked files; these names get +x when untracked.
$script:RhapUntrackedExecutableNames = @(
    'configure', 'Configure', 'config.guess', 'config.sub', 'config.rpath', 'install-sh',
    'mkinstalldirs', 'missing', 'ltmain.sh', 'compile', 'depcomp', 'autogen.sh', 'build_gcc',
    'move-if-change', 'ylwrap', 'genmultilib', 'texi2html', '*.sh', '*.pl'
)

function ConvertFrom-RhapGitLsFiles {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Staged,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Untracked
    )

    # $Staged is `git ls-files -s -z` output, $Untracked is `git ls-files -o -z`.
    $paths = New-Object 'System.Collections.Generic.SortedSet[string]' ([System.StringComparer]::Ordinal)
    foreach ($entry in $Staged.Split([char]0)) {
        if ($entry -eq '') { continue }
        if ($entry -notmatch '(?s)^([0-7]{6}) [0-9a-f]+ [0-3]\t(.+)$') { throw "malformed git ls-files entry: $entry" }
        if ($matches[1] -eq '100755') { [void]$paths.Add($matches[2]) }
    }
    foreach ($path in $Untracked.Split([char]0)) {
        if ($path -eq '') { continue }
        $name = $path.Substring($path.LastIndexOf('/') + 1)
        if (@($script:RhapUntrackedExecutableNames | Where-Object { $name -clike $_ }).Count -gt 0) {
            [void]$paths.Add($path)
        }
    }
    return @($paths)
}

function Invoke-RhapGitListing {
    param(
        [Parameter(Mandatory = $true)][string]$Git,
        [Parameter(Mandatory = $true)][string]$Directory,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $Git
    $startInfo.Arguments = ((@('--literal-pathspecs', '-C', $Directory) + $Arguments | ForEach-Object { ConvertTo-RhapProcessArgument $_ }) -join ' ')
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardOutputEncoding = New-Object System.Text.UTF8Encoding($false)
    $process = [System.Diagnostics.Process]::Start($startInfo)
    try {
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $stdout = $process.StandardOutput.ReadToEnd()
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) {
            throw "git $($Arguments -join ' ') failed (exit $($process.ExitCode)): $($stderrTask.Result.Trim())"
        }
        return $stdout
    } finally {
        $process.Dispose()
    }
}

function Get-RhapSyncExecutablePaths {
    param(
        [Parameter(Mandatory = $true)][string]$Git,
        [Parameter(Mandatory = $true)][string]$LocalSrc,
        [Parameter(Mandatory = $true)][string]$Pathspec
    )

    # Paths come back relative to $LocalSrc, matching RemoteRoot/src on the guest.
    $staged = Invoke-RhapGitListing -Git $Git -Directory $LocalSrc -Arguments @('ls-files', '-s', '-z', '--', $Pathspec)
    $untracked = Invoke-RhapGitListing -Git $Git -Directory $LocalSrc -Arguments @('ls-files', '-o', '-z', '--', $Pathspec)
    $paths = @(ConvertFrom-RhapGitLsFiles -Staged $staged -Untracked $untracked)
    # Index entries deleted from the working tree never reach the archive.
    return @($paths | Where-Object { Test-Path -LiteralPath (Join-Path $LocalSrc $_) -PathType Leaf })
}

function ConvertTo-RhapShQuoted {
    param([Parameter(Mandatory = $true)][string]$Value)

    if ($Value -match '[\x00-\x1f\x7f]') { throw 'shell value contains control characters' }
    return "'" + $Value.Replace("'", "'\''") + "'"
}

function New-RhapFixExecBitsCommand {
    param(
        [Parameter(Mandatory = $true)][string]$RemoteSrc,
        [Parameter(Mandatory = $true)][string]$RemoteTree,
        [AllowEmptyCollection()][string[]]$ExecutablePaths = @()
    )

    # Windows tar gives every file a mode of its own (.bat/.cmd/.exe come out
    # 0755), so clear all execute bits, then set exactly git's. The script
    # goes to /bin/sh on stdin; batches stay far below the guest's 64K ARG_MAX.
    $lines = New-Object 'System.Collections.Generic.List[string]'
    $lines.Add('status=0')
    $lines.Add("find $(ConvertTo-RhapShQuoted $RemoteTree) -type f \( -perm -100 -o -perm -010 -o -perm -001 \) -exec chmod a-x {} \; || status=1")
    $lines.Add("cd $(ConvertTo-RhapShQuoted $RemoteSrc) || exit 1")
    $batch = New-Object System.Text.StringBuilder
    foreach ($path in $ExecutablePaths) {
        $word = ConvertTo-RhapShQuoted "./$path"
        if ($batch.Length -gt 0 -and [Text.Encoding]::UTF8.GetByteCount($batch.ToString() + $word) -gt 8000) {
            $lines.Add("chmod a+x$batch || status=1")
            [void]$batch.Clear()
        }
        [void]$batch.Append(" $word")
    }
    if ($batch.Length -gt 0) { $lines.Add("chmod a+x$batch || status=1") }
    $lines.Add('exit $status')
    return ($lines -join "`n") + "`n"
}

function ConvertTo-RhapShellDoubleQuotedAssignmentValue {
    param([Parameter(Mandatory = $true)][string]$Value)

    if ($Value -match '[!''"\x00-\x1f\x7f]') { throw 'shell value is unsafe for target csh' }
    $escaped = $Value.Replace('\', '\\').Replace('"', '\"').Replace('$', '\$').Replace('`', '\`')
    return '"' + $escaped + '"'
}

function New-RhapArchiveSshCommand {
    param([Parameter(Mandatory = $true)][string]$ScriptBody)

    if ($ScriptBody.Contains("'") -or $ScriptBody.Contains('!') -or $ScriptBody.Contains("`r")) {
        throw 'archive transaction body is unsafe for target csh'
    }

    $chunkBytes = 699
    # Target ash (Rhapsody /bin/sh) puts the POSIX $0 placeholder in $1; skip it.
    # Target /usr/bin/printf drops backslash escapes, so printf "\nX" yields "nX".
    $bootstrap = 'n=$(echo; echo X); n=${n%X}; s=; for p do case "$p" in sh) ;; N) s="$s$n";; C*) s="$s${p#C}";; *) exit 78;; esac; done; eval "$s"'
    $transportWords = New-Object 'System.Collections.Generic.List[string]'
    $lines = $ScriptBody.Split([char]"`n")
    for ($lineIndex = 0; $lineIndex -lt $lines.Length; $lineIndex++) {
        $line = $lines[$lineIndex]
        if ($line.Length -gt 0) {
            $builder = New-Object System.Text.StringBuilder
            $bytes = 0
            $elements = [System.Globalization.StringInfo]::GetTextElementEnumerator($line)
            while ($elements.MoveNext()) {
                $element = [string]$elements.Current
                $elementBytes = [Text.Encoding]::UTF8.GetByteCount($element)
                if ($bytes -gt 0 -and $bytes + $elementBytes -gt $chunkBytes) {
                    $transportWords.Add('C' + $builder.ToString())
                    [void]$builder.Clear()
                    $bytes = 0
                }
                [void]$builder.Append($element)
                $bytes += $elementBytes
            }
            if ($builder.Length -gt 0) { $transportWords.Add('C' + $builder.ToString()) }
        }
        if ($lineIndex -lt $lines.Length - 1) { $transportWords.Add('N') }
    }

    $command = New-Object System.Text.StringBuilder
    [void]$command.Append("/bin/sh -c '$bootstrap' sh")
    foreach ($word in $transportWords) {
        if ([Text.Encoding]::UTF8.GetByteCount($word) -gt 700) { throw 'archive transaction chunk exceeds target csh word limit' }
        [void]$command.Append(" '$word'")
    }
    $result = $command.ToString()
    if ([Text.Encoding]::UTF8.GetByteCount($result) -ge 10240) { throw 'archive transaction exceeds target csh argument limit' }
    return $result
}

function ConvertTo-RhapProcessArgument {
    param([Parameter(Mandatory = $true)][string]$Value)

    $quoted = New-Object System.Text.StringBuilder
    [void]$quoted.Append('"')
    $backslashes = 0
    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq [char]'\') {
            $backslashes++
            continue
        }
        if ($character -eq [char]'"') {
            [void]$quoted.Append(('\' * (2 * $backslashes + 1)))
            [void]$quoted.Append('"')
            $backslashes = 0
            continue
        }
        if ($backslashes -gt 0) {
            [void]$quoted.Append(('\' * $backslashes))
            $backslashes = 0
        }
        [void]$quoted.Append($character)
    }
    if ($backslashes -gt 0) { [void]$quoted.Append(('\' * (2 * $backslashes))) }
    [void]$quoted.Append('"')
    return $quoted.ToString()
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
exit_code=0
die() {
    exit_code=`$1
    exit `$1
}
cleanup() {
    status=`$exit_code
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
if test -L "`$root"; then die 74; fi
ROOT_PHYS=`$(cd "`$root" && pwd) || die 74
if test "`$ROOT_PHYS" = /; then die 74; fi
probe=`$parent
suffix_path=
while :; do
    if test "`$probe" = "`$root"; then break; fi
    if test -L "`$probe"; then die 74; fi
    if test -e "`$probe"; then break; fi
    component=`${probe##*/}
    suffix_path=/`$component`$suffix_path
    next=`${probe%/*}
    test -n "`$next" || next=/
    if test "`$next" = "`$probe"; then die 74; fi
    probe=`$next
done
test -d "`$probe" || die 74
PARENT_BASE_PHYS=`$(cd "`$probe" && pwd) || die 74
PARENT_PHYS=`$PARENT_BASE_PHYS`$suffix_path
case "`$PARENT_PHYS" in
    "`$ROOT_PHYS"|"`$ROOT_PHYS"/*) ;;
    *) die 74 ;;
esac
mkdir -p "`$parent" || die `$?
PARENT_ACTUAL_PHYS=`$(cd "`$parent" && pwd) || die 74
case "`$PARENT_ACTUAL_PHYS" in
    "`$ROOT_PHYS"|"`$ROOT_PHYS"/*) ;;
    *) die 74 ;;
esac
if test -L "`$lock_root"; then die 74; fi
if test -d "`$lock_root"; then
    namespace_created=0
else
    if mkdir "`$lock_root" 2>/dev/null; then
        namespace_created=1
    else
        test -d "`$lock_root" || die 76
        namespace_created=0
    fi
fi
if test -L "`$lock_root"; then die 74; fi
LOCK_ROOT_PHYS=`$(cd "`$lock_root" && pwd) || die 74
test "`$LOCK_ROOT_PHYS" = "`$PARENT_ACTUAL_PHYS/.rhap-sync-lock" || die 74
if test "`$namespace_created" -eq 1; then
    if echo "`$lock_version" > "`$lock_version_file"; then
        :
    else
        rm -f "`$lock_version_file" 2>/dev/null || :
        rmdir "`$lock_root" 2>/dev/null || :
        die 76
    fi
fi
if test -L "`$lock_version_file"; then die 77; fi
test -f "`$lock_version_file" || die 77
published_version=`$(/bin/cat "`$lock_version_file" 2>/dev/null || :)
test "`$published_version" = "`$lock_version" || die 77
if test -L "`$lock_targets"; then die 74; fi
if test -d "`$lock_targets"; then
    :
else
    mkdir "`$lock_targets" 2>/dev/null || test -d "`$lock_targets" || die 76
fi
if test -L "`$lock_targets"; then die 74; fi
LOCK_TARGETS_PHYS=`$(cd "`$lock_targets" && pwd) || die 74
test "`$LOCK_TARGETS_PHYS" = "`$LOCK_ROOT_PHYS/targets" || die 74
if mkdir "`$lock" 2>/dev/null; then
    :
else
    die 75
fi
lock_owned=1
if echo "`$suffix" > "`$lock/owner"; then
    :
else
    rm -f "`$lock/owner" 2>/dev/null || :
    rmdir "`$lock" 2>/dev/null || :
    lock_owned=0
    die 76
fi
if test -e "`$old" || test -L "`$old"; then
    die 73
fi
mkdir "`$stage" || die `$?
stage_created=1
cd "`$stage" || die `$?
$cpioCommand -idum || die `$?
if test -f "`$stage/`$leaf" || test -d "`$stage/`$leaf"; then
    :
else
    die 66
fi
if test -e "`$target" || test -L "`$target"; then
    mv "`$target" "`$old" || die `$?
    saved=1
fi
mv "`$stage/`$leaf" "`$target" || die `$?
promoted=1
rm -rf "`$stage" "`$old"
stage_created=0
saved=0
die 0
"@
}
