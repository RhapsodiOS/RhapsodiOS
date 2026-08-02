# Pure helpers shared by build-src.ps1 and its dependency-free tests.

Set-StrictMode -Version Latest

$script:RhapToolchainKeys = @(
    'profile', 'build_cc', 'target_cc', 'target_ar', 'target_ranlib',
    'make', 'shell', 'tar', 'tar_create_flags', 'gzip', 'rsync', 'path',
    'arch_flags', 'cpp_flags', 'ld_flags', 'ln'
)

function Test-RhapToolchainProfileText {
    param([Parameter(Mandatory = $true)][string]$Text)

    $seen = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([System.StringComparer]::Ordinal)
    foreach ($rawLine in ($Text -split "`r?`n")) {
        $line = $rawLine.Trim()
        if ($line -eq '' -or $line.StartsWith('#')) { continue }
        $equals = $line.IndexOf('=')
        if ($equals -lt 1) { throw 'malformed toolchain profile line' }
        $key = $line.Substring(0, $equals).Trim()
        $value = $line.Substring($equals + 1).Trim()
        if (-not ($script:RhapToolchainKeys -ccontains $key)) { throw "unknown toolchain profile key $key" }
        if ($seen.ContainsKey($key)) { throw "duplicate toolchain profile key $key" }
        $seen.Add($key, $value)
    }
    foreach ($key in $script:RhapToolchainKeys) {
        if (-not $seen.ContainsKey($key) -or $seen[$key] -eq '') {
            throw "toolchain profile missing $key"
        }
    }
    return $true
}

function Assert-RhapSafeArchFlags {
    param([Parameter(Mandatory = $true)][string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value) -or $Value -notmatch '^[A-Za-z0-9_./,+=\s-]+$') {
        throw 'unsafe arch_flags'
    }
    return $Value
}

function Test-RhapPpcMachOFileOutput {
    param([Parameter(Mandatory = $true)][string]$Text)
    if ($Text -notmatch '(^|:\s*)Mach-O object ppc($|[ ,])') {
        throw 'TARGET_CC did not produce a PPC Mach-O object'
    }
    return $true
}

function ConvertTo-RhapNormalizedRemotePath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$Name = 'path'
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or -not $Path.StartsWith('/')) {
        throw "$Name must be an absolute POSIX path"
    }
    if ($Path -match '[\x00-\x1f\x7f\\;&|<>`$()''"]') {
        throw "$Name contains unsafe characters"
    }
    foreach ($component in ($Path -split '/')) {
        if ($component -eq '.' -or $component -eq '..') {
            throw "$Name contains an unsafe path component"
        }
    }
    $normalized = [regex]::Replace($Path, '/+', '/').TrimEnd('/')
    if ($normalized -eq '') { return '/' }
    return $normalized
}

function Assert-RhapSafeRemoteOutputPath {
    param(
        [Parameter(Mandatory = $true)][string]$RemoteRoot,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $root = ConvertTo-RhapNormalizedRemotePath -Path $RemoteRoot -Name 'RemoteRoot'
    $output = ConvertTo-RhapNormalizedRemotePath -Path $Path -Name 'Path'
    if ($root -eq '/') {
        throw 'RemoteRoot may not be the filesystem root'
    }
    if ($output -eq $root -or -not $output.StartsWith($root + '/', [System.StringComparison]::Ordinal)) {
        throw "Path must be a strict descendant of RemoteRoot"
    }
    return $output
}

function Get-RhapBuildPhases {
    param(
        [switch]$All,
        [switch]$Rbuild,
        [switch]$Bootstrap,
        [switch]$KernelDrivers,
        [switch]$World
    )

    $selected = @($All, $Rbuild, $Bootstrap, $KernelDrivers, $World) |
        Where-Object { $_ } |
        Measure-Object |
        Select-Object -ExpandProperty Count
    if ($selected -ne 1) {
        throw 'specify exactly one of -All, -Rbuild, -Bootstrap, -KernelDrivers, or -World'
    }
    if ($All) { return @('rbuild', 'bootstrap', 'kernel-drivers', 'world') }
    if ($Rbuild) { return @('rbuild') }
    if ($Bootstrap) { return @('bootstrap') }
    if ($KernelDrivers) { return @('kernel-drivers') }
    return @('world')
}

function ConvertTo-RhapShellDoubleQuoted {
    param([Parameter(Mandatory = $true)][string]$Value)
    return '"' + $Value + '"'
}

function Assert-RhapSafeCommandPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$Name
    )
    [void](ConvertTo-RhapNormalizedRemotePath -Path $Path -Name $Name)
}

function New-RhapPreflightCommand {
    param(
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [Parameter(Mandatory = $true)][string]$ToolsDir,
        [Parameter(Mandatory = $true)][string]$BootstrapRoot,
        [Parameter(Mandatory = $true)][string]$StateDir,
        [Parameter(Mandatory = $true)][string]$Profile
    )

    Assert-RhapSafeCommandPath -Path $SourceRoot -Name 'SourceRoot'
    Assert-RhapSafeCommandPath -Path $ToolsDir -Name 'ToolsDir'
    Assert-RhapSafeCommandPath -Path $BootstrapRoot -Name 'BootstrapRoot'
    Assert-RhapSafeCommandPath -Path $StateDir -Name 'StateDir'
    Assert-RhapSafeCommandPath -Path $Profile -Name 'Profile'

    $qProfile = ConvertTo-RhapShellDoubleQuoted $Profile
    $qTools = ConvertTo-RhapShellDoubleQuoted $ToolsDir
    $qBootstrap = ConvertTo-RhapShellDoubleQuoted $BootstrapRoot
    $qState = ConvertTo-RhapShellDoubleQuoted $StateDir
    $qSource = ConvertTo-RhapShellDoubleQuoted $SourceRoot
    $requiredKeys = ($script:RhapToolchainKeys | ForEach-Object { "required[`"$_`"] = 1" }) -join '; '

    $parts = @(
        'set -e',
        "SOURCE_ROOT=$qSource",
        "PROFILE=$qProfile",
        "BOOTSTRAP_ROOT=$qBootstrap",
        'fail() { echo "build-src preflight: $*" >&2; exit 1; }',
        'test -d "$SOURCE_ROOT" || fail "source root missing: $SOURCE_ROOT"',
        'test -f "$SOURCE_ROOT/BootstrapManifest" || fail "source BootstrapManifest missing"',
        'test -d "$SOURCE_ROOT/rbuild-1" || fail "rbuild source directory missing"',
        'test -f "$SOURCE_ROOT/rbuild-1/Makefile" || fail "rbuild Makefile missing"',
        'test -f "$SOURCE_ROOT/rbuild-1/toolchain.c" || fail "rbuild toolchain source missing"',
        'test -f "$PROFILE" || fail "toolchain profile missing: $PROFILE"',
        "awk 'BEGIN { $requiredKeys } function trim(value) { sub(/^[ `t]*/, `"`", value); sub(/[ `t]*`$/, `"`", value); return value } { text=trim(`$0); if (text == `"`" || substr(text, 1, 1) == `"#`") next; equals=index(text, `"=`"); if (equals < 2) exit 1; key=trim(substr(text, 1, equals-1)); value=trim(substr(text, equals+1)); if (!(key in required) || (key in seen) || value == `"`") exit 1; seen[key]=1 } END { for (key in required) if (!(key in seen)) exit 1 }' `"`$PROFILE`" || fail `"invalid toolchain profile`"",
        "profile_value() { awk -v wanted=`"`$1`" 'BEGIN { found=0 } /^[ `t]*#/ { next } { line=`$0; sub(/^[ `t]*/, `"`", line); eq=index(line, `"=`"); if (eq < 2) next; key=substr(line, 1, eq-1); value=substr(line, eq+1); sub(/[ `t]*`$/, `"`", key); sub(/^[ `t]*/, `"`", value); sub(/[ `t]*`$/, `"`", value); if (key == wanted) { print value; found=1; exit } } END { if (found == 0) exit 1 }' `"`$PROFILE`"; }",
        'BUILD_CC=$(profile_value build_cc) || fail "profile missing build_cc"',
        'TARGET_CC=$(profile_value target_cc) || fail "profile missing target_cc"',
        'TARGET_AR=$(profile_value target_ar) || fail "profile missing target_ar"',
        'TARGET_RANLIB=$(profile_value target_ranlib) || fail "profile missing target_ranlib"',
        'MAKE_TOOL=$(profile_value make) || fail "profile missing make"',
        'SHELL_TOOL=$(profile_value shell) || fail "profile missing shell"',
        'TAR_TOOL=$(profile_value tar) || fail "profile missing tar"',
        'GZIP_TOOL=$(profile_value gzip) || fail "profile missing gzip"',
        'RSYNC_TOOL=$(profile_value rsync) || fail "profile missing rsync"',
        'LN_TOOL=$(profile_value ln) || fail "profile missing ln"',
        'ARCH_FLAGS=$(profile_value arch_flags) || fail "profile missing arch_flags"',
        'for tool in "$BUILD_CC" "$TARGET_CC" "$TARGET_AR" "$TARGET_RANLIB" "$MAKE_TOOL" "$SHELL_TOOL" "$TAR_TOOL" "$GZIP_TOOL" "$RSYNC_TOOL" "$LN_TOOL"; do case "$tool" in /*) ;; *) fail "configured executable is not absolute: $tool" ;; esac; expr "$tool" : "/[-A-Za-z0-9_./+]*\$" >/dev/null || fail "configured executable contains unsafe characters: $tool"; test -f "$tool" && test -x "$tool" || fail "configured executable is not an executable file: $tool"; done',
        'test -x /usr/bin/cc || fail "Developer Tools compiler missing: /usr/bin/cc"',
        'test -x /usr/bin/install || fail "Developer Tools install missing: /usr/bin/install"',
        'test -f /usr/bin/file && test -x /usr/bin/file || fail "object inspection tool missing: /usr/bin/file"',
        'nearest_parent() { rbuild_parent=$1; while :; do test -e "$rbuild_parent" && break; rbuild_next=${rbuild_parent%/*}; test -n "$rbuild_next" || rbuild_next=/; if test "$rbuild_next" = "$rbuild_parent"; then break; fi; rbuild_parent=$rbuild_next; done; printf "%s\n" "$rbuild_parent"; }',
        'check_space() { rbuild_parent=$(nearest_parent "$1"); df -k "$rbuild_parent" | awk ''{ fields=NF; available=$4 } END { if (fields < 4 || (available + 0) < 1) exit 1 }'' || fail "no usable free space below $1"; }',
        "check_space $qTools",
        'check_space "$BOOTSTRAP_ROOT"',
        "check_space $qState",
        'PROBE_PARENT=$(nearest_parent "$BOOTSTRAP_ROOT")',
        'PROBE="$PROBE_PARENT/.rbuild-preflight.$$"',
        '(umask 077 && mkdir "$PROBE") || fail "cannot create preflight probe directory"',
        'cleanup() { rm -f "$PROBE/RbuildCaseProbe" "$PROBE/rbuildcaseprobe" "$PROBE/probe.c" "$PROBE/dev.o" "$PROBE/build.o" "$PROBE/target.o"; rmdir "$PROBE" 2>/dev/null || :; }',
        'trap cleanup 0 1 2 3 15',
        ': > "$PROBE/RbuildCaseProbe"',
        'if test -e "$PROBE/rbuildcaseprobe"; then fail "case-sensitive filesystem required"; fi',
        ': > "$PROBE/rbuildcaseprobe"',
        'test -f "$PROBE/RbuildCaseProbe" && test -f "$PROBE/rbuildcaseprobe" || fail "case-sensitive filesystem required"',
        'printf "%s\n" "int rbuild_probe;" > "$PROBE/probe.c"',
        '/usr/bin/cc -arch ppc -c "$PROBE/probe.c" -o "$PROBE/dev.o" || fail "Developer Tools PPC compile failed"',
        'test -s "$PROBE/dev.o" || fail "Developer Tools PPC compiler produced an empty object"',
        '"$BUILD_CC" -c "$PROBE/probe.c" -o "$PROBE/build.o" || fail "BUILD_CC compile failed"',
        'test -s "$PROBE/build.o" || fail "BUILD_CC produced an empty object"',
        'set --',
        'case "$ARCH_FLAGS" in *[!A-Za-z0-9_./,+=\ -]*) fail "unsafe arch_flags" ;; esac',
        'set -f',
        'for rbuild_flag in $ARCH_FLAGS; do expr "$rbuild_flag" : "[-A-Za-z0-9_./,+=][-A-Za-z0-9_./,+=]*\$" >/dev/null || fail "unsafe arch_flags word: $rbuild_flag"; set -- "$@" "$rbuild_flag"; done',
        '"$TARGET_CC" "$@" -c "$PROBE/probe.c" -o "$PROBE/target.o" || fail "TARGET_CC compile failed"',
        'test -s "$PROBE/target.o" || fail "TARGET_CC produced an empty object"',
        'TARGET_FILE=$(/usr/bin/file "$PROBE/target.o") || fail "could not inspect TARGET_CC object"',
        'case "$TARGET_FILE" in *"Mach-O object ppc"*) ;; *) fail "TARGET_CC did not produce a PPC Mach-O object: $TARGET_FILE" ;; esac',
        'echo "build-src preflight: ok"'
    )
    $body = $parts -join '; '
    return $body
}
