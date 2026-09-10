#Requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:Checks = 0

function Assert-Match([string]$Actual, [string]$Pattern, [string]$Name) {
    $script:Checks++
    if ($Actual -notmatch $Pattern) {
        throw "$Name`: pattern [$Pattern] was not found"
    }
}

function Assert-NotMatch([string]$Actual, [string]$Pattern, [string]$Name) {
    $script:Checks++
    if ($Actual -match $Pattern) {
        throw "$Name`: forbidden pattern [$Pattern] was found"
    }
}

function Assert-Equal($Actual, $Expected, [string]$Name) {
    $script:Checks++
    if ($Actual -ne $Expected) {
        throw "$Name`: expected [$Expected], got [$Actual]"
    }
}

function Assert-Throws([scriptblock]$Action, [string]$Name) {
    $script:Checks++
    try { & $Action } catch { return }
    throw "$Name`: expected an exception"
}

function ConvertTo-TestPosixPath([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path).Replace('\', '/')
    if ($full -match '^([A-Za-z]):/(.*)$') { return '/' + $matches[1].ToLowerInvariant() + '/' + $matches[2] }
    return $full
}

function Start-TestRemoteCommand {
    param(
        [string]$Bash,
        [string]$Command,
        [string]$Archive,
        [string]$Directory,
        [scriptblock]$Observer
    )
    $scriptPath = Join-Path $Directory ("remote-{0}.sh" -f [guid]::NewGuid().ToString('n'))
    [IO.File]::WriteAllText($scriptPath, $Command.Replace("`r`n", "`n"), (New-Object Text.UTF8Encoding($false)))
    $startInfo = New-Object Diagnostics.ProcessStartInfo
    $startInfo.FileName = $Bash
    $startInfo.Arguments = '"' + (ConvertTo-TestPosixPath $scriptPath) + '"'
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $startInfo
    $started = $false
    $stdinClosed = $false
    try {
        if (-not $process.Start()) { throw 'could not start test shell' }
        $started = $true
        if ($Observer) { & $Observer $process }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $input = [IO.File]::OpenRead($Archive)
        try {
            $input.CopyTo($process.StandardInput.BaseStream)
        } finally {
            $input.Dispose()
            $process.StandardInput.Close()
            $stdinClosed = $true
        }
        return [pscustomobject]@{
            Process = $process
            Stdout = $stdout
            Stderr = $stderr
            ScriptPath = $scriptPath
        }
    } catch {
        if ($started -and -not $stdinClosed) { try { $process.StandardInput.Close() } catch { } }
        if ($started) {
            try { if (-not $process.HasExited) { $process.Kill() } } catch { }
            try { $process.WaitForExit() } catch { }
        }
        $process.Dispose()
        Remove-Item -LiteralPath $scriptPath -Force -ErrorAction SilentlyContinue
        throw
    }
}

function Complete-TestRemoteCommand($Context) {
    try {
        $Context.Process.WaitForExit()
        [void]$Context.Stdout.Result
        [void]$Context.Stderr.Result
        return [int]$Context.Process.ExitCode
    } finally {
        try { if (-not $Context.Process.HasExited) { $Context.Process.Kill() } } catch { }
        try { $Context.Process.WaitForExit() } catch { }
        $Context.Process.Dispose()
        Remove-Item -LiteralPath $Context.ScriptPath -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-TestRemoteCommand([string]$Bash, [string]$Command, [string]$Archive, [string]$Directory) {
    $context = Start-TestRemoteCommand -Bash $Bash -Command $Command -Archive $Archive -Directory $Directory
    return Complete-TestRemoteCommand $context
}

$syncScriptText = Get-Content -Raw (Join-Path $PSScriptRoot 'sync-src.ps1')
$targetCshHeaderText = Get-Content -Raw (Join-Path $PSScriptRoot '..\src\Commands\basic_cmds\csh.tproj\csh.h')
$targetCshManualText = Get-Content -Raw (Join-Path $PSScriptRoot '..\src\Commands\basic_cmds\csh.tproj\csh.1')
$targetCshLexText = Get-Content -Raw (Join-Path $PSScriptRoot '..\src\Commands\basic_cmds\csh.tproj\lex.c')

Assert-Match $syncScriptText '--format cpio' 'sync archive uses portable cpio format'
Assert-Match $syncScriptText ([regex]::Escape('--format cpio -cf $ArchivePath -C $ArchiveParent -- $ArchiveLeaf')) 'producer terminates options before archive leaf'
Assert-NotMatch $syncScriptText '--format ustar' 'sync archive no longer uses ustar'
Assert-NotMatch $syncScriptText '\|\s*`?"?\$Ssh' 'producer and SSH are not joined by a masking pipeline'
Assert-Match $syncScriptText 'New-RhapSyncRemoteCommand' 'sync uses the stage-and-replace command builder'
Assert-Match $syncScriptText 'New-RhapArchiveSshCommand' 'production sync explicitly wraps transaction with sh'
Assert-Match $syncScriptText 'Invoke-RhapCpioTransfer' 'production sync uses the tested producer-consumer transaction'
Assert-Match $syncScriptText 'Invoke-RhapArchiveConsumerProcess' 'production sync uses diagnostic-preserving consumer process'
Assert-Match $targetCshHeaderText '#define\s+BUFSIZ\s+1024' 'target csh limits words to 1024-byte buffer'
Assert-Match $targetCshManualText 'limits argument lists to 10240 characters' 'target csh documents 10240-character argument list'
Assert-Match $targetCshLexText 'dolflg = c == ''"'' \? DOALL : DOEXCL' 'target csh single quotes retain history processing'

. (Join-Path $PSScriptRoot 'build-src-lib.ps1')
. (Join-Path $PSScriptRoot 'sync-src-lib.ps1')
Assert-Equal ($null -ne (Get-Command Start-TestRemoteCommand -ErrorAction SilentlyContinue)) $true 'test harness exposes an asynchronous remote command starter'
Assert-Equal ($null -ne (Get-Command Invoke-RhapCpioTransfer -ErrorAction SilentlyContinue)) $true 'sync exposes a testable producer-consumer transaction'
Assert-Equal ($null -ne (Get-Command ConvertTo-RhapSyncRelativePath -ErrorAction SilentlyContinue)) $true 'sync exposes relative path validation'
Assert-Equal ($null -ne (Get-Command New-RhapFixExecBitsCommand -ErrorAction SilentlyContinue)) $true 'sync exposes quoted chmod command construction'
Assert-Equal ($null -ne (Get-Command New-RhapArchiveSshCommand -ErrorAction SilentlyContinue)) $true 'sync exposes explicit sh command wrapping'
Assert-Equal ($null -ne (Get-Command Invoke-RhapArchiveConsumerProcess -ErrorAction SilentlyContinue)) $true 'sync exposes testable archive consumer process'

$safeToken = '0123456789abcdef0123456789abcdef'
$lockNamespaceVersion = 'rhapsodios-sync-lock-v1'
Assert-Throws { New-RhapSyncRemoteCommand -RemoteRoot '/build' -RemoteParent '/outside' -LeafName 'src' -Token $safeToken } 'remote command rejects a parent outside RemoteRoot'
Assert-Throws { New-RhapSyncRemoteCommand -RemoteRoot '/build' -RemoteParent '/build/src' -LeafName '..' -Token $safeToken } 'remote command rejects traversal leaf'
Assert-Throws { New-RhapSyncRemoteCommand -RemoteRoot '/build' -RemoteParent '/build/src' -LeafName '.rhap-sync-lock' -Token $safeToken } 'remote command rejects reserved lock namespace leaf'
Assert-Throws { New-RhapSyncRemoteCommand -RemoteRoot '/build' -RemoteParent '/build/src' -LeafName 'project' -Token 'unsafe' } 'remote command rejects unsafe token'
Assert-Throws { New-RhapSyncRemoteCommand -RemoteRoot '/build' -RemoteParent '/build/src' -LeafName 'bang!leaf' -Token $safeToken } 'remote command rejects leaf history expansion'
Assert-Throws { New-RhapSyncRemoteCommand -RemoteRoot '/build' -RemoteParent '/build/src' -LeafName 'quote"leaf' -Token $safeToken } 'remote command rejects quoted leaf'
Assert-Throws { New-RhapSyncRemoteCommand -RemoteRoot '/build' -RemoteParent '/build/src' -LeafName "single'leaf" -Token $safeToken } 'remote command rejects single-quoted leaf'
Assert-Throws { New-RhapSyncRemoteCommand -RemoteRoot '/build' -RemoteParent '/build/src' -LeafName "line`nleaf" -Token $safeToken } 'remote command rejects control characters in leaf'
Assert-Throws { New-RhapSyncRemoteCommand -RemoteRoot '/build!' -RemoteParent '/build!/src' -LeafName 'leaf' -Token $safeToken } 'remote command rejects path history expansion'
$quotedFixExec = New-RhapFixExecBitsCommand -RemoteTree '/build/src/project;touch_pwn'
Assert-Match $quotedFixExec ([regex]::Escape("find '/build/src/project;touch_pwn' -type f")) 'chmod pass shell-quotes metacharacter path'
Assert-NotMatch $quotedFixExec 'find /build/src/project;touch_pwn' 'chmod pass never interpolates raw metacharacter path'
Assert-Match $quotedFixExec '-name texi2html' 'chmod pass restores extensionless texi2html script'
$physicalCommand = New-RhapSyncRemoteCommand -RemoteRoot '/build' -RemoteParent '/build/src/project' -LeafName 'leaf' -Token $safeToken
$spacedCommand = New-RhapSyncRemoteCommand -RemoteRoot '/build' -RemoteParent '/build/src' -LeafName 'DLL Files.fgl' -Token $safeToken
Assert-NotMatch $spacedCommand "'" 'transaction body is outer-single-quote-safe for spaced leaf'
Assert-Match $physicalCommand 'ROOT_PHYS=\$\(cd "\$root" && pwd\)' 'remote sync resolves RemoteRoot without POSIX cd -P'
Assert-Match $physicalCommand 'PARENT_BASE_PHYS=\$\(cd "\$probe" && pwd\)' 'remote sync resolves RemoteParent ancestor without POSIX cd -P'
Assert-NotMatch $physicalCommand 'cd -P|pwd -P' 'remote sync never uses POSIX cd -P or pwd -P'
Assert-Match $physicalCommand 'die\(\) \{' 'remote sync records exit status before EXIT trap'
Assert-NotMatch $physicalCommand 'printf "%s\\n"' 'remote sync does not use printf backslash escapes'
Assert-Match $physicalCommand 'lock_root=.*\.rhap-sync-lock' 'remote sync defines a deterministic lock namespace'
Assert-Match $physicalCommand 'lock="\$lock_targets/\$leaf"' 'remote sync keys its lock beneath target namespace'
Assert-Match $physicalCommand 'if mkdir "\$lock"' 'remote sync atomically acquires its target lock'
Assert-Equal ($physicalCommand.IndexOf('if mkdir "$lock"') -lt $physicalCommand.IndexOf('if test -e "$old"')) $true 'target lock precedes old-path inspection'
Assert-Equal ($physicalCommand.IndexOf('if mkdir "$lock"') -lt $physicalCommand.IndexOf('mkdir "$stage"')) $true 'target lock precedes stage creation'
Assert-NotMatch $physicalCommand '/bin/ls -d' 'remote sync never uses Jaguar ls as an existence probe'
Assert-Match $physicalCommand 'test -e "\$old" \|\| test -L "\$old"' 'old collision probe includes broken symlinks'
Assert-Match $physicalCommand 'test -e "\$target" \|\| test -L "\$target"' 'target existence probe includes broken symlinks'
Assert-Equal (ConvertTo-RhapSyncRelativePath 'drivers/project') 'drivers/project' 'relative sync path is preserved'
foreach ($unsafePath in @('/absolute', 'C:\absolute', '../escape', 'drivers/../escape', 'drivers//project', './project')) {
    Assert-Throws { ConvertTo-RhapSyncRelativePath $unsafePath } "reject unsafe sync path $unsafePath"
}

$transactionRoot = Join-Path $env:TEMP ("rhap-sync-test-{0}" -f [guid]::NewGuid().ToString('n'))
New-Item -ItemType Directory -Path $transactionRoot | Out-Null
try {
    $consumerCalled = $false
    Assert-Throws {
        Invoke-RhapCpioTransfer -LocalParent $transactionRoot -LeafName 'tree' -TempDirectory $transactionRoot `
            -Producer { param($archive) [IO.File]::WriteAllText($archive, 'partial'); return 17 } `
            -Consumer { $script:consumerCalled = $true; return 0 }
    } 'producer failure propagates'
    Assert-Equal $consumerCalled $false 'producer failure prevents SSH consumer'
    Assert-Equal (@(Get-ChildItem $transactionRoot -Filter 'rhap-sync-*.cpio').Count) 0 'producer failure removes temporary archive'

    Assert-Throws {
        Invoke-RhapCpioTransfer -LocalParent $transactionRoot -LeafName 'tree' -TempDirectory $transactionRoot `
            -Producer { param($archive) [IO.File]::WriteAllText($archive, 'complete'); return 0 } `
            -Consumer { return 23 }
    } 'consumer failure propagates'
    Assert-Equal (@(Get-ChildItem $transactionRoot -Filter 'rhap-sync-*.cpio').Count) 0 'consumer failure removes temporary archive'

    $fixtureParent = Join-Path $transactionRoot 'fixture'
    $fixtureTree = Join-Path $fixtureParent 'tree'
    New-Item -ItemType Directory -Path $fixtureTree -Force | Out-Null
    $boundaryName = ('n' * 95)
    $boundaryRelative = "tree/$boundaryName"
    Assert-Equal ([Text.Encoding]::ASCII.GetByteCount($boundaryRelative)) 100 'boundary fixture is exactly 100 archive-name bytes'
    [IO.File]::WriteAllText((Join-Path $fixtureTree $boundaryName), 'boundary-content')
    $archivePath = Join-Path $transactionRoot 'fixture.cpio'
    $hostTar = (Get-Command tar.exe).Source
    & $hostTar --format cpio -cf $archivePath -C $fixtureParent tree
    Assert-Equal $LASTEXITCODE 0 'host cpio producer succeeds'
    $archiveEntries = @(& $hostTar -tf $archivePath)
    Assert-Equal ($archiveEntries -contains $boundaryRelative) $true 'cpio preserves exact 100-byte boundary name'

    $hyphenLeaf = '-leading-project'
    $hyphenTree = Join-Path $fixtureParent $hyphenLeaf
    New-Item -ItemType Directory -Path $hyphenTree | Out-Null
    [IO.File]::WriteAllText((Join-Path $hyphenTree 'member'), 'hyphen-content')
    $hyphenArchive = Join-Path $transactionRoot 'hyphen.cpio'
    & $hostTar --format cpio -cf $hyphenArchive -C $fixtureParent -- $hyphenLeaf
    Assert-Equal $LASTEXITCODE 0 'leading-hyphen cpio producer succeeds'
    $hyphenEntries = @(& $hostTar -tf $hyphenArchive)
    Assert-Equal ($hyphenEntries -contains "$hyphenLeaf/member") $true 'leading-hyphen archive has exact member path'
    Assert-Equal (@($hyphenEntries | Where-Object { $_ -like "$hyphenLeaf*" }).Count) 2 'leading-hyphen archive has only exact tree and member'

    $gitRoot = Split-Path (Split-Path (Get-Command git.exe).Source)
    $bash = Join-Path $gitRoot 'bin\bash.exe'
    $existenceRoot = Join-Path $transactionRoot 'existence-fixture'
    $regularPath = Join-Path $existenceRoot 'regular'
    $missingPath = Join-Path $existenceRoot 'missing'
    $brokenTarget = Join-Path $existenceRoot 'removed-target'
    $brokenLink = Join-Path $existenceRoot 'broken-link'
    New-Item -ItemType Directory -Path $regularPath -Force | Out-Null
    New-Item -ItemType Directory -Path $brokenTarget | Out-Null
    New-Item -ItemType Junction -Path $brokenLink -Target $brokenTarget | Out-Null
    [IO.Directory]::Delete($brokenTarget)
    try {
        $existenceCommand = "test -e '$(ConvertTo-TestPosixPath $regularPath)' || exit 81; test -L '$(ConvertTo-TestPosixPath $regularPath)' && exit 82; test -e '$(ConvertTo-TestPosixPath $missingPath)' && exit 83; test -L '$(ConvertTo-TestPosixPath $missingPath)' && exit 84; test -e '$(ConvertTo-TestPosixPath $brokenLink)' && exit 85; test -L '$(ConvertTo-TestPosixPath $brokenLink)' || exit 86"
        & $bash -c $existenceCommand
        Assert-Equal $LASTEXITCODE 0 'shell tests distinguish regular, missing, and broken-symlink paths'
    } finally {
        try { [IO.Directory]::Delete($brokenLink) } catch { }
        Remove-Item -LiteralPath $existenceRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    $wrappedSpacedCommand = New-RhapArchiveSshCommand -ScriptBody $spacedCommand
    Assert-Match $wrappedSpacedCommand '^/bin/sh -c ''[^'']+'' sh ''C' 'transaction explicitly invokes short sh bootstrap with chunks'
    Assert-Equal $wrappedSpacedCommand.EndsWith("'") $true 'sh-wrapped transaction closes outer quote'
    Assert-Match $wrappedSpacedCommand ([regex]::Escape('leaf="DLL Files.fgl"')) 'sh-wrapped transaction preserves spaced leaf assignment'
    $cshQuotedWords = @([regex]::Matches($wrappedSpacedCommand, "'([^']*)'") | ForEach-Object { $_.Groups[1].Value })
    $cshWordBytes = @($cshQuotedWords | ForEach-Object { [Text.Encoding]::UTF8.GetByteCount($_) })
    Assert-Equal (($cshWordBytes | Measure-Object -Maximum).Maximum -le 800) $true 'every csh quoted word stays comfortably below BUFSIZ'
    Assert-Equal (@($cshQuotedWords | Where-Object { $_ -match "[`r`n]" }).Count) 0 'csh quoted words contain no literal newline'
    Assert-Equal ([Text.Encoding]::UTF8.GetByteCount($wrappedSpacedCommand) -lt 10240) $true 'remote command stays below target csh argument limit'
    Assert-Throws { New-RhapArchiveSshCommand -ScriptBody ('x' * 11000) } 'csh wrapper rejects transaction above total argument limit'

    $reconstructedOutput = Join-Path $transactionRoot 'reconstructed-body.txt'
    $reconstructionBody = "write_probe() {`n    printf `"%s\n`" `"line one`"`n    printf `"%s\n`" `"line two`"`n}`nwrite_probe > `"$(ConvertTo-TestPosixPath $reconstructedOutput)`"`n"
    $reconstructionCommand = New-RhapArchiveSshCommand -ScriptBody $reconstructionBody
    $emptyArchive = Join-Path $transactionRoot 'empty-archive'
    [IO.File]::WriteAllBytes($emptyArchive, (New-Object byte[] 0))
    Assert-Equal (Invoke-RhapArchiveConsumerProcess -Executable $bash -Arguments @('-c', $reconstructionCommand) -ArchivePath $emptyArchive) 0 'chunk bootstrap reconstructs multiline function through sh'
    Assert-Equal ([IO.File]::ReadAllText($reconstructedOutput).Replace("`r`n", "`n")) "line one`nline two`n" 'chunk bootstrap preserves newlines and arguments'

    # Rhapsody /bin/sh is 1996 Almquist: `sh -c SCRIPT sh C...` leaves $0 as argv[0]
    # and puts the POSIX $0 placeholder in $1. Simulate that argv layout with bash.
    $ashQuotedWords = @([regex]::Matches($reconstructionCommand, "'([^']*)'") | ForEach-Object { $_.Groups[1].Value })
    Assert-Equal ($ashQuotedWords.Count -ge 2) $true 'wrapped reconstruction has bootstrap plus chunks'
    $ashBootstrap = $ashQuotedWords[0]
    $ashChunks = @($ashQuotedWords | Select-Object -Skip 1)
    Remove-Item -LiteralPath $reconstructedOutput -Force
    $ashExit = Invoke-RhapArchiveConsumerProcess -Executable $bash `
        -Arguments (@('-c', $ashBootstrap, '/bin/sh', 'sh') + $ashChunks) `
        -ArchivePath $emptyArchive
    Assert-Equal $ashExit 0 'chunk bootstrap reconstructs through Rhapsody ash -c argv'
    Assert-Equal ([IO.File]::ReadAllText($reconstructedOutput).Replace("`r`n", "`n")) "line one`nline two`n" 'ash-compatible bootstrap preserves reconstructed body'
    Assert-Match $ashBootstrap 'n=\$\(echo; echo X\); n=\$\{n%X\}' 'bootstrap captures a newline without printf backslash escapes'

    $argumentCapture = Join-Path $transactionRoot 'argument-capture.sh'
    $argumentBase = Join-Path $transactionRoot 'ssh-argument'
    $argumentScript = @'
#!/bin/sh
capture=$1
shift
printf "%s\n" "$#" > "$capture.count"
index=0
for argument do
    printf "%s" "$argument" > "$capture.$index"
    index=$((index + 1))
done
/bin/cat >/dev/null
exit 0
'@
    [IO.File]::WriteAllText($argumentCapture, $argumentScript.Replace("`r`n", "`n"), (New-Object Text.UTF8Encoding($false)))
    $argumentExit = Invoke-RhapArchiveConsumerProcess -Executable $bash `
        -Arguments @((ConvertTo-TestPosixPath $argumentCapture), (ConvertTo-TestPosixPath $argumentBase), 'legacy-option', 'root@guest', $wrappedSpacedCommand) `
        -ArchivePath $archivePath
    Assert-Equal $argumentExit 0 'archive consumer argument fixture succeeds'
    Assert-Equal ([IO.File]::ReadAllText("$argumentBase.count").Trim()) '3' 'SSH receives wrapper as one argument'
    Assert-Equal ([IO.File]::ReadAllText("$argumentBase.2")) $wrappedSpacedCommand 'multiline function body survives process argument transport exactly'

    $crtArgumentBase = Join-Path $transactionRoot 'crt-argument'
    $trailingBackslash = 'trail\'
    $quotedArgument = 'quote"inside'
    $backslashQuoteArgument = 'slashes\\\"tail'
    $crtExit = Invoke-RhapArchiveConsumerProcess -Executable $bash `
        -Arguments @((ConvertTo-TestPosixPath $argumentCapture), (ConvertTo-TestPosixPath $crtArgumentBase), $trailingBackslash, $quotedArgument, $backslashQuoteArgument) `
        -ArchivePath $archivePath
    Assert-Equal $crtExit 0 'CRT argument quoting fixture succeeds'
    Assert-Equal ([IO.File]::ReadAllText("$crtArgumentBase.count").Trim()) '3' 'CRT quoting preserves argument count'
    Assert-Equal ([IO.File]::ReadAllText("$crtArgumentBase.0")) $trailingBackslash 'CRT quoting preserves trailing backslash'
    Assert-Equal ([IO.File]::ReadAllText("$crtArgumentBase.1")) $quotedArgument 'CRT quoting preserves embedded quote'
    Assert-Equal ([IO.File]::ReadAllText("$crtArgumentBase.2")) $backslashQuoteArgument 'CRT quoting preserves backslash run before quote'

    $largeArchive = Join-Path $transactionRoot 'large-archive.cpio'
    $largeStream = [IO.File]::Open($largeArchive, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $largeStream.SetLength(16MB) } finally { $largeStream.Dispose() }
    $brokenPipeChild = Join-Path $transactionRoot 'broken-pipe-child.cmd'
    [IO.File]::WriteAllText($brokenPipeChild, "@echo off`r`necho known child stdout`r`necho known child stderr 1>&2`r`n%SystemRoot%\System32\ping.exe -n 2 127.0.0.1 >nul`r`nexit /b 37`r`n", [Text.Encoding]::ASCII)
    $diagnostics = @{ stdout = ''; stderr = '' }
    $brokenPipeExit = Invoke-RhapArchiveConsumerProcess -Executable (Join-Path $env:SystemRoot 'System32\cmd.exe') `
        -Arguments @('/d', '/c', $brokenPipeChild) -ArchivePath $largeArchive `
        -Observer { param($stream, $content) $diagnostics[$stream] += $content }
    Assert-Equal $brokenPipeExit 37 'nonzero child exit wins over broken-pipe write error'
    Assert-Match $diagnostics.stdout 'known child stdout' 'broken-pipe path preserves child stdout'
    Assert-Match $diagnostics.stderr 'known child stderr' 'broken-pipe path preserves child stderr'

    $zeroExitChild = Join-Path $transactionRoot 'zero-exit-child.cmd'
    [IO.File]::WriteAllText($zeroExitChild, "@echo off`r`n%SystemRoot%\System32\ping.exe -n 2 127.0.0.1 >nul`r`nexit /b 0`r`n", [Text.Encoding]::ASCII)
    $zeroExitWriteError = $null
    try {
        Invoke-RhapArchiveConsumerProcess -Executable (Join-Path $env:SystemRoot 'System32\cmd.exe') `
            -Arguments @('/d', '/c', $zeroExitChild) -ArchivePath $largeArchive
    } catch { $zeroExitWriteError = $_.Exception }
    Assert-Equal ($null -ne $zeroExitWriteError) $true 'zero child exit propagates write error'
    Assert-Match $zeroExitWriteError.Message 'pipe' 'zero child exit preserves broken-pipe diagnostic'

    $exceptionProcess = [pscustomobject]@{ Id = 0 }
    Assert-Throws {
        Start-TestRemoteCommand -Bash $bash -Command 'while :; do :; done' `
            -Archive (Join-Path $transactionRoot 'missing-archive') -Directory $transactionRoot `
            -Observer { param($process) $exceptionProcess.Id = $process.Id }
    } 'test harness surfaces an archive-open failure'
    Assert-Equal ($exceptionProcess.Id -gt 0) $true 'exception cleanup fixture starts Bash'
    Assert-Equal ($null -eq (Get-Process -Id $exceptionProcess.Id -ErrorAction SilentlyContinue)) $true 'exception cleanup kills and waits for Bash'
    $extractor = Join-Path $transactionRoot 'fake-cpio.sh'
    [IO.File]::WriteAllText($extractor, "#!/bin/sh`nexec /c/Windows/System32/tar.exe -xf -`n", (New-Object Text.UTF8Encoding($false)))
    $remoteBase = Join-Path $transactionRoot 'remote'
    New-Item -ItemType Directory -Path $remoteBase | Out-Null
    $remoteRoot = ConvertTo-TestPosixPath $remoteBase
    $cpioPath = ConvertTo-TestPosixPath $extractor

    $outsideBase = Join-Path $transactionRoot 'outside'
    New-Item -ItemType Directory -Path $outsideBase | Out-Null
    [IO.File]::WriteAllText((Join-Path $outsideBase 'sentinel'), 'outside-prior')
    $escapeLink = Join-Path $remoteBase 'escape-link'
    New-Item -ItemType Junction -Path $escapeLink -Target $outsideBase | Out-Null
    try {
        $escapedParent = "$remoteRoot/escape-link/missing-parent"
        $escapeCommand = New-RhapSyncRemoteCommand -RemoteRoot $remoteRoot -RemoteParent $escapedParent -LeafName 'tree' -Token $safeToken -Cpio $cpioPath
        Assert-Equal (Invoke-TestRemoteCommand $bash $escapeCommand $archivePath $transactionRoot) 74 'physical parent symlink escape is rejected'
        Assert-Equal ([IO.File]::ReadAllText((Join-Path $outsideBase 'sentinel'))) 'outside-prior' 'symlink escape preserves outside content'
        Assert-Equal (@(Get-ChildItem $outsideBase -Filter '.rhap-sync-*').Count) 0 'symlink escape creates no outside stage'
        Assert-Equal (Test-Path (Join-Path $outsideBase 'missing-parent')) $false 'symlink escape creates no outside target parent'
    } finally {
        if (Test-Path -LiteralPath $escapeLink) { [IO.Directory]::Delete($escapeLink) }
    }

    $markerFailureParent = Join-Path $remoteBase 'marker-failure-parent'
    New-Item -ItemType Directory -Path $markerFailureParent | Out-Null
    $markerFailureCommand = "echo() { return 1; }`n" +
        (New-RhapSyncRemoteCommand -RemoteRoot $remoteRoot -RemoteParent (ConvertTo-TestPosixPath $markerFailureParent) -LeafName 'tree' -Token $safeToken -Cpio $cpioPath)
    Assert-Equal (Invoke-TestRemoteCommand $bash $markerFailureCommand $archivePath $transactionRoot) 76 'namespace marker publication failure propagates'
    Assert-Equal (Test-Path (Join-Path $markerFailureParent '.rhap-sync-lock')) $false 'failed creator removes only its unmarked namespace'
    Assert-Equal (@(Get-ChildItem -LiteralPath $markerFailureParent).Count) 0 'namespace marker failure leaves parent unmodified'
    Remove-Item -LiteralPath $markerFailureParent -Force

    $unownedNamespace = Join-Path $remoteBase '.rhap-sync-lock'
    New-Item -ItemType Directory -Path $unownedNamespace | Out-Null
    [IO.File]::WriteAllText((Join-Path $unownedNamespace 'foreign'), 'foreign-content')
    $nonemptyUnownedCommand = New-RhapSyncRemoteCommand -RemoteRoot $remoteRoot -RemoteParent $remoteRoot -LeafName 'tree' -Token '22222222222222222222222222222222' -Cpio $cpioPath
    Assert-Equal (Invoke-TestRemoteCommand $bash $nonemptyUnownedCommand $archivePath $transactionRoot) 77 'pre-existing nonempty unowned lock namespace is rejected'
    Assert-Equal ([IO.File]::ReadAllText((Join-Path $unownedNamespace 'foreign'))) 'foreign-content' 'nonempty unowned lock namespace content is preserved'
    Assert-Equal (@(Get-ChildItem -LiteralPath $unownedNamespace).Count) 1 'nonempty unowned lock namespace remains unmodified'
    Remove-Item -LiteralPath $unownedNamespace -Recurse -Force

    New-Item -ItemType Directory -Path $unownedNamespace | Out-Null
    $unownedCommand = New-RhapSyncRemoteCommand -RemoteRoot $remoteRoot -RemoteParent $remoteRoot -LeafName 'tree' -Token $safeToken -Cpio $cpioPath
    Assert-Equal (Invoke-TestRemoteCommand $bash $unownedCommand $archivePath $transactionRoot) 77 'pre-existing empty unowned lock namespace is rejected'
    Assert-Equal (Test-Path $unownedNamespace -PathType Container) $true 'empty unowned lock namespace is preserved'
    Assert-Equal (@(Get-ChildItem -LiteralPath $unownedNamespace).Count) 0 'empty unowned lock namespace remains unmodified'
    Remove-Item -LiteralPath $unownedNamespace -Force

    foreach ($leaf in @('src', 'project', 'version')) {
        $leafFixture = Join-Path $transactionRoot "fixture-$leaf"
        $leafTree = Join-Path $leafFixture $leaf
        New-Item -ItemType Directory -Path $leafTree -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $leafTree 'wanted'), "new-$leaf")
        $leafArchive = Join-Path $transactionRoot "$leaf.cpio"
        & $hostTar --format cpio -cf $leafArchive -C $leafFixture $leaf
        Assert-Equal $LASTEXITCODE 0 "$leaf fixture producer succeeds"
        $prior = Join-Path $remoteBase $leaf
        New-Item -ItemType Directory -Path $prior -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $prior 'stale-extra'), 'stale')
        $command = New-RhapSyncRemoteCommand -RemoteRoot $remoteRoot -RemoteParent $remoteRoot -LeafName $leaf -Token $safeToken -Cpio $cpioPath
        Assert-Equal (Invoke-TestRemoteCommand $bash $command $leafArchive $transactionRoot) 0 "$leaf stage promotion succeeds"
        Assert-Equal (Test-Path (Join-Path $prior 'wanted')) $true "$leaf installs expected content"
        Assert-Equal (Test-Path (Join-Path $prior 'stale-extra')) $false "$leaf removes stale extras"
        Assert-Equal (@(Get-ChildItem $remoteBase -Filter '.rhap-sync-[0-9a-f]*').Count) 0 "$leaf cleans stage path"
        Assert-Equal (@(Get-ChildItem $remoteBase -Filter '.rhap-old-*').Count) 0 "$leaf cleans old path"
        Remove-Item -LiteralPath $prior -Recurse -Force
    }

    $concurrentTarget = Join-Path $remoteBase 'tree'
    New-Item -ItemType Directory -Path $concurrentTarget | Out-Null
    [IO.File]::WriteAllText((Join-Path $concurrentTarget 'prior'), 'prior-content')
    $secondFixture = Join-Path $transactionRoot 'second-fixture'
    New-Item -ItemType Directory -Path (Join-Path $secondFixture 'tree') -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $secondFixture 'tree\second-only'), 'second-content')
    $secondArchive = Join-Path $transactionRoot 'second.cpio'
    & $hostTar --format cpio -cf $secondArchive -C $secondFixture -- tree
    Assert-Equal $LASTEXITCODE 0 'concurrent loser fixture producer succeeds'
    $otherFixture = Join-Path $transactionRoot 'other-fixture'
    New-Item -ItemType Directory -Path (Join-Path $otherFixture 'other') -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $otherFixture 'other\wanted'), 'other-content')
    $otherArchive = Join-Path $transactionRoot 'other.cpio'
    & $hostTar --format cpio -cf $otherArchive -C $otherFixture -- other
    Assert-Equal $LASTEXITCODE 0 'different-target fixture producer succeeds'
    $blockEntered = Join-Path $transactionRoot 'block-entered'
    $blockRelease = Join-Path $transactionRoot 'block-release'
    $blockingCpio = Join-Path $transactionRoot 'blocking-cpio.sh'
    $blockScript = "#!/bin/sh`n: > '$(ConvertTo-TestPosixPath $blockEntered)'`nwhile test ! -f '$(ConvertTo-TestPosixPath $blockRelease)'; do /bin/sleep 1; done`nexec /c/Windows/System32/tar.exe -xf -`n"
    [IO.File]::WriteAllText($blockingCpio, $blockScript, (New-Object Text.UTF8Encoding($false)))
    $secondToken = 'fedcba9876543210fedcba9876543210'
    $otherToken = '11111111111111111111111111111111'
    $firstCommand = New-RhapSyncRemoteCommand -RemoteRoot $remoteRoot -RemoteParent $remoteRoot -LeafName 'tree' -Token $safeToken -Cpio (ConvertTo-TestPosixPath $blockingCpio)
    $firstContext = Start-TestRemoteCommand -Bash $bash -Command $firstCommand -Archive $archivePath -Directory $transactionRoot
    $firstCompleted = $false
    try {
        for ($attempt = 0; $attempt -lt 100 -and -not (Test-Path $blockEntered); $attempt++) { Start-Sleep -Milliseconds 25 }
        Assert-Equal (Test-Path $blockEntered) $true 'first transaction reaches blocked extractor'
        $lockOwner = Join-Path $remoteBase ".rhap-sync-lock\targets\tree\owner"
        Assert-Equal ([IO.File]::ReadAllText($lockOwner).Trim()) $safeToken 'first transaction owns deterministic target lock'

        $otherCommand = New-RhapSyncRemoteCommand -RemoteRoot $remoteRoot -RemoteParent $remoteRoot -LeafName 'other' -Token $otherToken -Cpio $cpioPath
        Assert-Equal (Invoke-TestRemoteCommand $bash $otherCommand $otherArchive $transactionRoot) 0 'different target proceeds while first target is locked'
        Assert-Equal ([IO.File]::ReadAllText((Join-Path $remoteBase 'other\wanted'))) 'other-content' 'different-target result is intact'
        Assert-Equal ([IO.File]::ReadAllText($lockOwner).Trim()) $safeToken 'different target does not replace first lock owner'

        $loserCommand = New-RhapSyncRemoteCommand -RemoteRoot $remoteRoot -RemoteParent $remoteRoot -LeafName 'tree' -Token $secondToken -Cpio $cpioPath
        Assert-Equal (Invoke-TestRemoteCommand $bash $loserCommand $secondArchive $transactionRoot) 75 'same-target concurrent loser reports busy'
        Assert-Equal ([IO.File]::ReadAllText((Join-Path $concurrentTarget 'prior'))) 'prior-content' 'concurrent loser preserves prior target'
        Assert-Equal ([IO.File]::ReadAllText($lockOwner).Trim()) $safeToken 'concurrent loser does not delete or replace owner lock'
        Assert-Equal (Test-Path (Join-Path $remoteBase ".rhap-sync-$secondToken")) $false 'concurrent loser creates no stage'

        [IO.File]::WriteAllText($blockRelease, 'release')
        Assert-Equal (Complete-TestRemoteCommand $firstContext) 0 'first transaction completes after release'
        $firstCompleted = $true
    } finally {
        if (-not (Test-Path $blockRelease)) { [IO.File]::WriteAllText($blockRelease, 'release') }
        if (-not $firstCompleted) { try { [void](Complete-TestRemoteCommand $firstContext) } catch { } }
    }
    Assert-Equal (Test-Path (Join-Path $concurrentTarget $boundaryName)) $true 'lock owner promotes its exact archive'
    Assert-Equal (Test-Path (Join-Path $concurrentTarget 'second-only')) $false 'concurrent loser content is never installed'
    Assert-Equal (Test-Path (Join-Path $concurrentTarget 'tree')) $false 'concurrent sync never nests target inside target'
    Assert-Equal ([IO.File]::ReadAllText((Join-Path $remoteBase '.rhap-sync-lock\version')).Trim()) $lockNamespaceVersion 'owner retains authenticated lock namespace'
    Assert-Equal (@(Get-ChildItem (Join-Path $remoteBase '.rhap-sync-lock')).Count) 2 'completed transactions retain marker and empty target namespace'
    Assert-Equal (@(Get-ChildItem (Join-Path $remoteBase '.rhap-sync-lock\targets')).Count) 0 'completed transactions leave no target locks'
    Assert-Equal (@(Get-ChildItem $remoteBase -Filter '.rhap-sync-[0-9a-f]*').Count) 0 'concurrent transactions leave no stage paths'
    Remove-Item -LiteralPath (Join-Path $remoteBase 'other') -Recurse -Force
    Remove-Item -LiteralPath $concurrentTarget -Recurse -Force

    $failureTarget = Join-Path $remoteBase 'tree'
    New-Item -ItemType Directory -Path $failureTarget -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $failureTarget 'prior'), 'prior-content')
    $ownerWriteFailureCommand = ('echo() { if test "$1" = "' + $lockNamespaceVersion + '"; then command echo "$1"; else return 1; fi; }' + "`n") +
        (New-RhapSyncRemoteCommand -RemoteRoot $remoteRoot -RemoteParent $remoteRoot -LeafName 'tree' -Token $safeToken -Cpio $cpioPath)
    Assert-Equal (Invoke-TestRemoteCommand $bash $ownerWriteFailureCommand $archivePath $transactionRoot) 76 'owner-marker write failure propagates'
    Assert-Equal ([IO.File]::ReadAllText((Join-Path $remoteBase '.rhap-sync-lock\version')).Trim()) $lockNamespaceVersion 'owner-marker write failure preserves authenticated namespace'
    Assert-Equal (Test-Path (Join-Path $remoteBase '.rhap-sync-lock\targets\tree')) $false 'owner-marker write failure removes exclusively acquired target lock'
    Assert-Equal ([IO.File]::ReadAllText((Join-Path $failureTarget 'prior'))) 'prior-content' 'owner-marker write failure preserves prior target'
    $failingCpio = Join-Path $transactionRoot 'failing-cpio.sh'
    [IO.File]::WriteAllText($failingCpio, "#!/bin/sh`nexit 42`n", (New-Object Text.UTF8Encoding($false)))
    $failureCommand = New-RhapSyncRemoteCommand -RemoteRoot $remoteRoot -RemoteParent $remoteRoot -LeafName 'tree' -Token $safeToken -Cpio (ConvertTo-TestPosixPath $failingCpio)
    Assert-Equal (Invoke-TestRemoteCommand $bash $failureCommand $archivePath $transactionRoot) 42 'cpio extraction failure propagates'
    Assert-Equal ([IO.File]::ReadAllText((Join-Path $failureTarget 'prior'))) 'prior-content' 'cpio extraction failure preserves prior target'
    Assert-Equal (@(Get-ChildItem $remoteBase -Filter '.rhap-sync-[0-9a-f]*').Count) 0 'cpio failure cleans stage path'
    Assert-Equal (@(Get-ChildItem $remoteBase -Filter '.rhap-old-*').Count) 0 'cpio failure creates no old path'

    $collisionStage = Join-Path $remoteBase ".rhap-sync-$safeToken"
    New-Item -ItemType Directory -Path $collisionStage | Out-Null
    [IO.File]::WriteAllText((Join-Path $collisionStage 'owned'), 'do-not-delete')
    $collisionCommand = New-RhapSyncRemoteCommand -RemoteRoot $remoteRoot -RemoteParent $remoteRoot -LeafName 'tree' -Token $safeToken -Cpio $cpioPath
    Assert-Equal ((Invoke-TestRemoteCommand $bash $collisionCommand $archivePath $transactionRoot) -ne 0) $true 'stage collision fails'
    Assert-Equal ([IO.File]::ReadAllText((Join-Path $collisionStage 'owned'))) 'do-not-delete' 'stage collision preserves pre-existing path'
    Remove-Item -LiteralPath $collisionStage -Recurse -Force

    $collisionOld = Join-Path $remoteBase ".rhap-old-$safeToken"
    New-Item -ItemType Directory -Path $collisionOld | Out-Null
    [IO.File]::WriteAllText((Join-Path $collisionOld 'owned'), 'do-not-delete')
    Assert-Equal ((Invoke-TestRemoteCommand $bash $collisionCommand $archivePath $transactionRoot) -ne 0) $true 'old-path collision fails'
    Assert-Equal ([IO.File]::ReadAllText((Join-Path $collisionOld 'owned'))) 'do-not-delete' 'old-path collision preserves pre-existing path'
    Assert-Equal ([IO.File]::ReadAllText((Join-Path $failureTarget 'prior'))) 'prior-content' 'old-path collision preserves prior target'
    Remove-Item -LiteralPath $collisionOld -Recurse -Force

    $rollbackTarget = $failureTarget
    New-Item -ItemType Directory -Path $rollbackTarget -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $rollbackTarget 'prior'), 'prior-content')
    $fakeBin = Join-Path $transactionRoot 'fake-bin'
    New-Item -ItemType Directory -Path $fakeBin | Out-Null
    $fakeMv = Join-Path $fakeBin 'mv'
    [IO.File]::WriteAllText($fakeMv, "#!/bin/sh`ncase `"`$1`" in */.rhap-sync-*/*) exit 71 ;; esac`nexec /usr/bin/mv `"`$@`"`n", (New-Object Text.UTF8Encoding($false)))
    $rollbackCommand = "PATH='$(ConvertTo-TestPosixPath $fakeBin)':`$PATH; export PATH`n" +
        (New-RhapSyncRemoteCommand -RemoteRoot $remoteRoot -RemoteParent $remoteRoot -LeafName 'tree' -Token $safeToken -Cpio $cpioPath)
    Assert-Equal (Invoke-TestRemoteCommand $bash $rollbackCommand $archivePath $transactionRoot) 71 'promotion failure propagates'
    Assert-Equal ([IO.File]::ReadAllText((Join-Path $rollbackTarget 'prior'))) 'prior-content' 'promotion failure restores prior target'
    Assert-Equal (@(Get-ChildItem $remoteBase -Filter '.rhap-sync-[0-9a-f]*').Count) 0 'rollback cleans stage path'
    Assert-Equal (@(Get-ChildItem $remoteBase -Filter '.rhap-old-*').Count) 0 'rollback cleans old path'
} finally {
    Remove-Item -LiteralPath $transactionRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "sync-src tests: PASS ($script:Checks checks)"
