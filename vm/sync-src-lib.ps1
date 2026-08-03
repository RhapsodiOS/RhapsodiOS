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
    if ($Token -notmatch '^[0-9a-f]{32}$') { throw 'Token must be 32 lowercase hexadecimal characters' }

    $remoteRootLiteral = ConvertTo-RhapShellLiteral $root
    $parent = ConvertTo-RhapShellLiteral $normalizedParent
    $leaf = ConvertTo-RhapShellLiteral $LeafName
    $cpioCommand = ConvertTo-RhapShellLiteral $Cpio
    $suffix = ConvertTo-RhapShellLiteral $Token
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
lock="`$lock_root/`$leaf"
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
            rmdir "`$lock_root" 2>/dev/null || :
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
    mkdir "`$lock_root" 2>/dev/null || test -d "`$lock_root" || exit 76
fi
test ! -L "`$lock_root" || exit 74
LOCK_ROOT_PHYS=`$(cd -P "`$lock_root" 2>/dev/null && pwd -P) || exit 74
test "`$LOCK_ROOT_PHYS" = "`$PARENT_ACTUAL_PHYS/.rhap-sync-lock" || exit 74
if ! mkdir "`$lock" 2>/dev/null; then
    exit 75
fi
lock_owned=1
if ! printf '%s\n' "`$suffix" > "`$lock/owner"; then
    rm -f "`$lock/owner" 2>/dev/null || :
    rmdir "`$lock" 2>/dev/null || :
    rmdir "`$lock_root" 2>/dev/null || :
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
