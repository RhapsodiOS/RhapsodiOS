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

Assert-Match $syncScriptText '--format cpio' 'sync archive uses portable cpio format'
Assert-Match $syncScriptText ([regex]::Escape('--format cpio -cf $ArchivePath -C $ArchiveParent -- $ArchiveLeaf')) 'producer terminates options before archive leaf'
Assert-NotMatch $syncScriptText '--format ustar' 'sync archive no longer uses ustar'
Assert-NotMatch $syncScriptText '\|\s*`?"?\$Ssh' 'producer and SSH are not joined by a masking pipeline'
Assert-Match $syncScriptText 'New-RhapSyncRemoteCommand' 'sync uses the stage-and-replace command builder'
Assert-Match $syncScriptText 'Invoke-RhapCpioTransfer' 'production sync uses the tested producer-consumer transaction'

. (Join-Path $PSScriptRoot 'build-src-lib.ps1')
. (Join-Path $PSScriptRoot 'sync-src-lib.ps1')
Assert-Equal ($null -ne (Get-Command Start-TestRemoteCommand -ErrorAction SilentlyContinue)) $true 'test harness exposes an asynchronous remote command starter'
Assert-Equal ($null -ne (Get-Command Invoke-RhapCpioTransfer -ErrorAction SilentlyContinue)) $true 'sync exposes a testable producer-consumer transaction'
Assert-Equal ($null -ne (Get-Command ConvertTo-RhapSyncRelativePath -ErrorAction SilentlyContinue)) $true 'sync exposes relative path validation'
Assert-Equal ($null -ne (Get-Command New-RhapFixExecBitsCommand -ErrorAction SilentlyContinue)) $true 'sync exposes quoted chmod command construction'

$safeToken = '0123456789abcdef0123456789abcdef'
Assert-Throws { New-RhapSyncRemoteCommand -RemoteRoot '/build' -RemoteParent '/outside' -LeafName 'src' -Token $safeToken } 'remote command rejects a parent outside RemoteRoot'
Assert-Throws { New-RhapSyncRemoteCommand -RemoteRoot '/build' -RemoteParent '/build/src' -LeafName '..' -Token $safeToken } 'remote command rejects traversal leaf'
Assert-Throws { New-RhapSyncRemoteCommand -RemoteRoot '/build' -RemoteParent '/build/src' -LeafName 'project' -Token 'unsafe' } 'remote command rejects unsafe token'
$quotedFixExec = New-RhapFixExecBitsCommand -RemoteTree '/build/src/project;touch_pwn'
Assert-Match $quotedFixExec ([regex]::Escape("find '/build/src/project;touch_pwn' -type f")) 'chmod pass shell-quotes metacharacter path'
Assert-NotMatch $quotedFixExec 'find /build/src/project;touch_pwn' 'chmod pass never interpolates raw metacharacter path'
$physicalCommand = New-RhapSyncRemoteCommand -RemoteRoot '/build' -RemoteParent '/build/src/project' -LeafName 'leaf' -Token $safeToken
Assert-Match $physicalCommand 'ROOT_PHYS=.*pwd -P' 'remote sync resolves physical RemoteRoot'
Assert-Match $physicalCommand 'PARENT_BASE_PHYS=.*pwd -P' 'remote sync resolves nearest existing RemoteParent ancestor'
Assert-Match $physicalCommand 'lock_root=.*\.rhap-sync-lock' 'remote sync defines a deterministic lock namespace'
Assert-Match $physicalCommand 'lock="\$lock_root/\$leaf"' 'remote sync keys its lock by target leaf'
Assert-Match $physicalCommand 'if ! mkdir "\$lock"' 'remote sync atomically acquires its target lock'
Assert-Equal ($physicalCommand.IndexOf('if ! mkdir "$lock"') -lt $physicalCommand.IndexOf('/bin/ls -d "$old"')) $true 'target lock precedes old-path inspection'
Assert-Equal ($physicalCommand.IndexOf('if ! mkdir "$lock"') -lt $physicalCommand.IndexOf('mkdir "$stage"')) $true 'target lock precedes stage creation'
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

    foreach ($leaf in @('src', 'project')) {
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
        Assert-Equal (@(Get-ChildItem $remoteBase -Filter '.rhap-sync-*').Count) 0 "$leaf cleans stage path"
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
        $lockOwner = Join-Path $remoteBase ".rhap-sync-lock\tree\owner"
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
    Assert-Equal (Test-Path (Join-Path $remoteBase '.rhap-sync-lock')) $false 'owner cleans lock namespace after completion'
    Assert-Equal (@(Get-ChildItem $remoteBase -Filter '.rhap-sync-*').Count) 0 'concurrent transactions leave no stage paths'
    Remove-Item -LiteralPath (Join-Path $remoteBase 'other') -Recurse -Force
    Remove-Item -LiteralPath $concurrentTarget -Recurse -Force

    $failureTarget = Join-Path $remoteBase 'tree'
    New-Item -ItemType Directory -Path $failureTarget -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $failureTarget 'prior'), 'prior-content')
    $ownerWriteFailureCommand = "printf() { return 1; }`n" +
        (New-RhapSyncRemoteCommand -RemoteRoot $remoteRoot -RemoteParent $remoteRoot -LeafName 'tree' -Token $safeToken -Cpio $cpioPath)
    Assert-Equal (Invoke-TestRemoteCommand $bash $ownerWriteFailureCommand $archivePath $transactionRoot) 76 'owner-marker write failure propagates'
    Assert-Equal (Test-Path (Join-Path $remoteBase '.rhap-sync-lock')) $false 'owner-marker write failure removes exclusively acquired empty lock'
    Assert-Equal ([IO.File]::ReadAllText((Join-Path $failureTarget 'prior'))) 'prior-content' 'owner-marker write failure preserves prior target'
    $failingCpio = Join-Path $transactionRoot 'failing-cpio.sh'
    [IO.File]::WriteAllText($failingCpio, "#!/bin/sh`nexit 42`n", (New-Object Text.UTF8Encoding($false)))
    $failureCommand = New-RhapSyncRemoteCommand -RemoteRoot $remoteRoot -RemoteParent $remoteRoot -LeafName 'tree' -Token $safeToken -Cpio (ConvertTo-TestPosixPath $failingCpio)
    Assert-Equal (Invoke-TestRemoteCommand $bash $failureCommand $archivePath $transactionRoot) 42 'cpio extraction failure propagates'
    Assert-Equal ([IO.File]::ReadAllText((Join-Path $failureTarget 'prior'))) 'prior-content' 'cpio extraction failure preserves prior target'
    Assert-Equal (@(Get-ChildItem $remoteBase -Filter '.rhap-sync-*').Count) 0 'cpio failure cleans stage path'
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
    Assert-Equal (@(Get-ChildItem $remoteBase -Filter '.rhap-sync-*').Count) 0 'rollback cleans stage path'
    Assert-Equal (@(Get-ChildItem $remoteBase -Filter '.rhap-old-*').Count) 0 'rollback cleans old path'
} finally {
    Remove-Item -LiteralPath $transactionRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "sync-src tests: PASS ($script:Checks checks)"
