# Pure helpers shared by build-src.ps1 and its dependency-free tests.

Set-StrictMode -Version Latest

$script:RhapRequiredToolchainKeys = @(
    'profile', 'build_cc', 'target_cc', 'target_arch', 'target_ar', 'target_ranlib',
    'make', 'shell', 'tar', 'archive_create', 'archive_create_flags', 'gzip', 'rsync', 'path',
    'arch_flags', 'cpp_flags', 'ld_flags', 'ln'
)
$script:RhapToolchainKeys = @($script:RhapRequiredToolchainKeys) + @('make_flags', 'make_flags_ready', 'cpp_flags_ready', 'ld_flags_ready')

$script:RhapMigMachHeaders = @(
    'mach/message.h',
    'mach/ndr.h',
    'mach/kern_return.h',
    'mach/machine/kern_return.h',
    'mach/ppc/kern_return.h',
    'mach/port.h',
    'mach/boolean.h',
    'mach/machine/boolean.h',
    'mach/ppc/boolean.h',
    'mach/machine/vm_types.h',
    'mach/ppc/vm_types.h',
    'mach/machine/simple_lock.h',
    'mach/ppc/simple_lock.h'
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
    foreach ($key in $script:RhapRequiredToolchainKeys) {
        if (-not $seen.ContainsKey($key) -or $seen[$key] -eq '') {
            throw "toolchain profile missing $key"
        }
    }
    foreach ($key in $script:RhapToolchainKeys) {
        if ($seen.ContainsKey($key) -and $seen[$key] -eq '') {
            throw "toolchain profile missing $key"
        }
    }
    if ($seen.ContainsKey('make_flags_ready') -and -not $seen.ContainsKey('make_flags')) {
        throw 'toolchain make_flags_ready requires make_flags'
    }
    if ($seen.ContainsKey('target_arch') -and $seen['target_arch'] -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
        throw 'invalid toolchain target_arch'
    }
    return $true
}

function Assert-RhapSafeIdentifier {
    param([Parameter(Mandatory = $true)][string]$Value, [string]$Name = 'identifier')
    if ($Value -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') { throw "invalid $Name" }
    return $Value
}

function ConvertFrom-RhapToolchainProfileText {
    param([Parameter(Mandatory = $true)][string]$Text)

    [void](Test-RhapToolchainProfileText -Text $Text)
    $values = @{}
    foreach ($rawLine in ($Text -split "`r?`n")) {
        $line = $rawLine.Trim()
        if ($line -eq '' -or $line.StartsWith('#')) { continue }
        $equals = $line.IndexOf('=')
        $values[$line.Substring(0, $equals).Trim()] = $line.Substring($equals + 1).Trim()
    }
    return $values
}

function Assert-RhapSafeArchFlags {
    param([Parameter(Mandatory = $true)][string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value) -or $Value -notmatch '^[A-Za-z0-9_./,+=\s-]+$') {
        throw 'unsafe arch_flags'
    }
    return $Value
}

function Test-RhapMachOFileOutput {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$TargetArch
    )
    $arch = [regex]::Escape((Assert-RhapSafeIdentifier -Value $TargetArch -Name 'TargetArch'))
    if ($Text -notmatch "(^|:\s*)Mach-O object $arch($|[ ,])") {
        throw "TARGET_CC did not produce a $TargetArch Mach-O object"
    }
    return $true
}

function New-RhapMachOValidationCommand {
    param([string]$ArchVariable = 'TARGET_ARCH')
    $arch = '$' + (Assert-RhapSafeIdentifier -Value $ArchVariable -Name 'ArchVariable')
    return "case `"`$TARGET_FILE`" in *`"Mach-O object $arch`"|*`"Mach-O object $arch `"*|*`"Mach-O object $arch,`"*) ;; *) fail `"TARGET_CC did not produce a $arch Mach-O object: `$TARGET_FILE`" ;; esac"
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
        [switch]$Kernel,
        [switch]$KernelDrivers,
        [switch]$World
    )

    $selected = @($All, $Rbuild, $Bootstrap, $Kernel, $KernelDrivers, $World) |
        Where-Object { $_ } |
        Measure-Object |
        Select-Object -ExpandProperty Count
    if ($selected -ne 1) {
        throw 'specify exactly one of -All, -Rbuild, -Bootstrap, -Kernel, -KernelDrivers, or -World'
    }
    if ($All) { return @('rbuild', 'bootstrap', 'kernel', 'kernel-drivers', 'world') }
    if ($Rbuild) { return @('rbuild') }
    if ($Bootstrap) { return @('bootstrap') }
    if ($Kernel) { return @('kernel') }
    if ($KernelDrivers) { return @('kernel-drivers') }
    return @('world')
}

function Get-RhapKernelCorePackages {
    param(
        [Parameter(Mandatory = $true)][string]$TargetArch
    )

    $arch = Assert-RhapSafeIdentifier -Value $TargetArch -Name 'TargetArch'
    $archs = if ($arch -eq 'universal') { @('i386', 'ppc') } else { @($arch) }
    return @(
        'driverkit-3',
        'driverTools-1',
        'kernload-1'
    ) + @($archs | ForEach-Object { "drivers-$_/bus/drvPExpert" }) + @(
        'kernel-7'
    )
}

# Every core source must exist locally except a platform expert, which rbuild
# skips when missing (drivers-i386/bus/drvPExpert has no source yet). Returns
# the platform experts that will be skipped.
function Assert-RhapKernelCoreSources {
    param(
        [Parameter(Mandatory = $true)][string]$LocalSource,
        [Parameter(Mandatory = $true)][string]$TargetArch
    )

    $skipped = @()
    foreach ($package in @(Get-RhapKernelCorePackages -TargetArch $TargetArch)) {
        if (Test-Path -LiteralPath (Join-Path $LocalSource $package) -PathType Container) { continue }
        if ($package -like 'drivers-*/bus/drvPExpert') {
            $skipped += $package
            continue
        }
        throw "core package source missing locally: $package"
    }
    return $skipped
}

function Assert-RhapFreshMode {
    param(
        [switch]$All,
        [switch]$Rbuild,
        [switch]$Bootstrap,
        [switch]$Kernel,
        [switch]$KernelDrivers,
        [switch]$World,
        [switch]$Fresh
    )
    if ($Fresh -and -not $All) {
        throw '-Fresh is only valid with -All'
    }
    return $true
}

function Invoke-RhapBuildOrchestration {
    param(
        [Parameter(Mandatory = $true)][string[]]$Phases,
        [Parameter(Mandatory = $true)][string]$PreflightBody,
        [Parameter(Mandatory = $true)][string]$ProfileBody,
        [string]$FreshBody,
        [Parameter(Mandatory = $true)][scriptblock]$ParseProfile,
        [Parameter(Mandatory = $true)][scriptblock]$PhaseFactory,
        [Parameter(Mandatory = $true)][scriptblock]$ScriptInvoker,
        [Parameter(Mandatory = $true)][scriptblock]$CaptureInvoker
    )
    $exitCode = [int](& $ScriptInvoker 'preflight' $PreflightBody $false)
    if ($exitCode -ne 0) { throw "preflight failed (exit $exitCode)" }
    $capture = & $CaptureInvoker $ProfileBody
    if ($capture.ExitCode -ne 0) { throw "remote toolchain profile read failed (exit $($capture.ExitCode))" }
    $profile = & $ParseProfile $capture.Stdout
    if (-not [string]::IsNullOrEmpty($FreshBody)) {
        $exitCode = [int](& $ScriptInvoker 'fresh output reset' $FreshBody $false)
        if ($exitCode -ne 0) { throw "fresh output reset failed (exit $exitCode)" }
    }
    foreach ($phase in $Phases) {
        $body = & $PhaseFactory $phase $profile
        $exitCode = [int](& $ScriptInvoker $phase $body $true)
        if ($exitCode -ne 0) { throw "$phase failed (exit $exitCode)" }
    }
    return $true
}

function ConvertTo-RhapShellDoubleQuoted {
    param([Parameter(Mandatory = $true)][string]$Value)
    return '"' + $Value + '"'
}

function ConvertTo-RhapShellLiteral {
    param([Parameter(Mandatory = $true)][string]$Value)
    if ($Value -match '^[A-Za-z0-9_./,+:=@-]+$') { return $Value }
    if ($Value.Contains("'")) { throw 'shell value contains an unsupported quote' }
    return "'$Value'"
}

function Assert-RhapSafeCommandPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$Name
    )
    [void](ConvertTo-RhapNormalizedRemotePath -Path $Path -Name $Name)
}

function New-RhapReadProfileCommand {
    param([Parameter(Mandatory = $true)][string]$Profile)
    Assert-RhapSafeCommandPath -Path $Profile -Name 'ToolchainProfile'
    return "set -e; /bin/cat '$(ConvertTo-RhapNormalizedRemotePath -Path $Profile)'"
}

function Test-RhapPathOverlapIgnoreCase {
    param([string]$Left, [string]$Right)
    return [string]::Equals($Left, $Right, [System.StringComparison]::OrdinalIgnoreCase) -or
        $Left.StartsWith($Right + '/', [System.StringComparison]::OrdinalIgnoreCase) -or
        $Right.StartsWith($Left + '/', [System.StringComparison]::OrdinalIgnoreCase)
}

function Assert-RhapSafeBuildTopology {
    param(
        [Parameter(Mandatory = $true)][string]$RemoteRoot,
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [Parameter(Mandatory = $true)][string[]]$Outputs
    )
    $root = ConvertTo-RhapNormalizedRemotePath -Path $RemoteRoot -Name 'RemoteRoot'
    $source = ConvertTo-RhapNormalizedRemotePath -Path $SourceRoot -Name 'SourceRoot'
    [void](Assert-RhapSafeRemoteOutputPath -RemoteRoot $root -Path $source)
    if ($Outputs.Count -ne 5) { throw 'exactly five build output roles are required' }
    $safe = New-Object System.Collections.Generic.List[string]
    foreach ($path in $Outputs) {
        $output = Assert-RhapSafeRemoteOutputPath -RemoteRoot $root -Path $path
        if (Test-RhapPathOverlapIgnoreCase -Left $output -Right $source) {
            throw 'build output overlaps SourceRoot'
        }
        foreach ($other in $safe) {
            if (Test-RhapPathOverlapIgnoreCase -Left $output -Right $other) {
                throw 'build output roles must be disjoint'
            }
        }
        $safe.Add($output)
    }
    return @($safe)
}

function New-RhapTargetProbeCommand {
    return @(
        'set --',
        'case "$ARCH_FLAGS" in *[!A-Za-z0-9_./,+=\ -]*) fail "unsafe arch_flags" ;; esac',
        'set -f',
        'for rbuild_flag in $ARCH_FLAGS; do expr "$rbuild_flag" : "[-A-Za-z0-9_./,+=][-A-Za-z0-9_./,+=]*\$" >/dev/null || fail "unsafe arch_flags word: $rbuild_flag"; set -- "$@" "$rbuild_flag"; done',
        # A universal profile's arch_flags build a fat object; probe each CPU thin.
        'if test "$TARGET_ARCH" = universal; then PROBE_ARCHS="i386 ppc"; else PROBE_ARCHS=$TARGET_ARCH; fi',
        ('for PROBE_ARCH in $PROBE_ARCHS; do if test "$TARGET_ARCH" = universal; then set -- -arch "$PROBE_ARCH"; fi; ' +
            '"$TARGET_CC" "$@" -c "$PROBE/probe.c" -o "$PROBE/target.o" || fail "TARGET_CC compile failed for $PROBE_ARCH"; ' +
            'test -s "$PROBE/target.o" || fail "TARGET_CC produced an empty object"; ' +
            'TARGET_FILE=$(/usr/bin/file "$PROBE/target.o") || fail "could not inspect TARGET_CC object"; ' +
            (New-RhapMachOValidationCommand -ArchVariable 'PROBE_ARCH') + '; done')
    ) -join '; '
}

# -Rbuild and -Bootstrap run tools on the guest. A universal profile needs the
# thin profile for the guest's CPU beside it. A thin profile for another CPU is
# accepted only when every Mach-O tool in BOOTSTRAP_ROOT/usr/bin has a slice the
# guest can run; lipo names subtypes (i486, ppc750), so slices map to families.
function New-RhapHostPhaseCheckCommand {
    return (@'
GUEST_ARCH=$(/usr/bin/arch) || fail "cannot determine the guest CPU with /usr/bin/arch"
case "$GUEST_ARCH" in i386|ppc) ;; *) fail "unsupported guest CPU: $GUEST_ARCH" ;; esac
arch_family() { case "$1" in i386|i486|i486SX|pentium|i586|pentpro|pentIIm3|pentIIm5) echo i386 ;; ppc|ppc601|ppc603|ppc603e|ppc603ev|ppc604|ppc604e|ppc750) echo ppc ;; *) echo unknown ;; esac; }
if test "$TARGET_ARCH" = universal; then
    case "$PROFILE" in *-universal.conf) HOST_PROFILE="${PROFILE%-universal.conf}-$GUEST_ARCH.conf" ;; *) fail "universal profile must be named *-universal.conf so its host profile can be found: $PROFILE" ;; esac
    test -f "$HOST_PROFILE" || fail "no host toolchain profile for this $GUEST_ARCH guest: $HOST_PROFILE"
    HOST_TARGET_ARCH=$(PROFILE=$HOST_PROFILE; profile_value target_arch) || fail "host toolchain profile has no target_arch: $HOST_PROFILE"
    test "$HOST_TARGET_ARCH" = "$GUEST_ARCH" || fail "host toolchain profile $HOST_PROFILE targets $HOST_TARGET_ARCH, not this $GUEST_ARCH guest"
elif test "$TARGET_ARCH" != "$GUEST_ARCH"; then
    test -x /usr/bin/lipo || fail "architecture inspection tool missing: /usr/bin/lipo"
    test -d "$BOOTSTRAP_ROOT/usr/bin" || fail "the $TARGET_ARCH profile on this $GUEST_ARCH guest needs universal bootstrap tools, but $BOOTSTRAP_ROOT/usr/bin does not exist"
    HOST_TOOLS=0
    for HOST_TOOL in "$BOOTSTRAP_ROOT"/usr/bin/*; do
        test -f "$HOST_TOOL" || continue
        HOST_TOOL_INFO=$(/usr/bin/lipo -info "$HOST_TOOL" 2>/dev/null) || continue
        HOST_TOOLS=1
        HOST_TOOL_OK=0
        case "$HOST_TOOL_INFO" in
            "Architectures in the fat file: "*) for HOST_SLICE in $(echo "$HOST_TOOL_INFO" | /usr/bin/sed 's/.* are: //'); do if test "$(arch_family "$HOST_SLICE")" = "$GUEST_ARCH"; then HOST_TOOL_OK=1; fi; done ;;
            "Non-fat file: "*) if test "$GUEST_ARCH" = i386 && test "$(arch_family "$(echo "$HOST_TOOL_INFO" | /usr/bin/sed 's/.* is architecture: //')")" = i386; then HOST_TOOL_OK=1; fi ;;
            *) fail "unrecognized lipo output for $HOST_TOOL: $HOST_TOOL_INFO" ;;
        esac
        test "$HOST_TOOL_OK" = 1 || fail "$HOST_TOOL cannot run on this $GUEST_ARCH guest ($HOST_TOOL_INFO); the $TARGET_ARCH profile here needs universal bootstrap tools, so run -Rbuild and -Bootstrap with gcc-darwin-$GUEST_ARCH.conf or gcc-darwin-universal.conf"
    done
    test "$HOST_TOOLS" = 1 || fail "the $TARGET_ARCH profile on this $GUEST_ARCH guest needs universal bootstrap tools, but $BOOTSTRAP_ROOT/usr/bin has no Mach-O tools"
fi
'@).Replace("`r", '').TrimEnd("`n")
}

function New-RhapPreflightCommand {
    param(
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [Parameter(Mandatory = $true)][string]$ToolsDir,
        [Parameter(Mandatory = $true)][string]$BootstrapRoot,
        [Parameter(Mandatory = $true)][string]$StateDir,
        [Parameter(Mandatory = $true)][string]$Profile,
        [switch]$HostPhases
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
    $allowedKeys = ($script:RhapToolchainKeys | ForEach-Object { "allowed[`"$_`"] = 1" }) -join '; '
    $requiredKeys = ($script:RhapRequiredToolchainKeys | ForEach-Object { "required[`"$_`"] = 1" }) -join '; '
    $pairedKeys = 'paired["make_flags_ready"] = "make_flags"'
    $migMachHeaders = $script:RhapMigMachHeaders -join ' '
    $hostPhaseParts = if ($HostPhases) { @(New-RhapHostPhaseCheckCommand) } else { @() }

    $parts = @(
        'set -e',
        "SOURCE_ROOT=$qSource",
        "PROFILE=$qProfile",
        "TOOLS_DIR=$qTools",
        "BOOTSTRAP_ROOT=$qBootstrap",
        'fail() { echo "build-src preflight: $*" >&2; exit 1; }',
        'test -d "$SOURCE_ROOT" || fail "source root missing: $SOURCE_ROOT"',
        'test -f "$SOURCE_ROOT/BootstrapManifest" || fail "source BootstrapManifest missing"',
        'test -d "$SOURCE_ROOT/rbuild-1" || fail "rbuild source directory missing"',
        'test -f "$SOURCE_ROOT/rbuild-1/Makefile" || fail "rbuild Makefile missing"',
        'test -f "$SOURCE_ROOT/rbuild-1/toolchain.c" || fail "rbuild toolchain source missing"',
        'test -f "$SOURCE_ROOT/Commands/bootstrap_cmds/decomment.tproj/decomment.c" || fail "decomment source missing"',
        'test -f "$SOURCE_ROOT/Commands/bootstrap_cmds/config.tproj/parser.y" || fail "kernel config parser source missing"',
        'test -f "$SOURCE_ROOT/Commands/bootstrap_cmds/config.tproj/lexer.l" || fail "kernel config lexer source missing"',
        'test -f "$SOURCE_ROOT/Commands/bootstrap_cmds/config.tproj/config.h" || fail "kernel config header source missing"',
        'for config_source in externs.c main.c mkglue.c mkheaders.c mkioconf.c mkmakefile.c mkswapconf.c openp.c searchp.c; do test -f "$SOURCE_ROOT/Commands/bootstrap_cmds/config.tproj/$config_source" || fail "kernel config source missing: $config_source"; done',
        'for mig_source in error.c global.c handler.c header.c mig.c routine.c server.c statement.c string.c type.c user.c utils.c parser.y lexxer.l mig.sh routine.h type.h utils.h lexxer.h global.h statement.h write.h error.h string.h alloc.h mig_errors.h; do test -f "$SOURCE_ROOT/Commands/bootstrap_cmds/migcom.tproj/$mig_source" || fail "classic MIG source missing: $mig_source"; done',
        'for mig_source in error.c global.c header.c migcom.c routine.c server.c statement.c string.c type.c user.c utils.c parser.y lexxer.l alloc.h cross64.h error.h global.h lexxer.h statement.h string.h type.h utils.h write.h routine.h; do test -f "$SOURCE_ROOT/Commands/bootstrap_cmds/migcom_typd.tproj/$mig_source" || fail "typed MIG source missing: $mig_source"; done',
        'for mig_source in error.c global.c header.c mig.c routine.c server.c statement.c string.c test.c type.c user.c utils.c parser.y lexxer.l migcom_untypd_vers_stub.c alloc.h error.h global.h lexxer.h routine.h statement.h strdefs.h type.h utils.h write.h; do test -f "$SOURCE_ROOT/Commands/bootstrap_cmds/migcom_untypd.tproj/$mig_source" || fail "untyped MIG source missing: $mig_source"; done',
        'test -f "$SOURCE_ROOT/kernel-7/mach/mach.defs" || fail "MIG wrapper smoke definition missing"',
        "for mig_header in $migMachHeaders; do test -f `"`$SOURCE_ROOT/kernel-7/`$mig_header`" || fail `"MIG compatibility header missing: `$mig_header`"; done",
        'test -f "$PROFILE" || fail "toolchain profile missing: $PROFILE"',
        "awk 'BEGIN { $allowedKeys; $requiredKeys; $pairedKeys } function trim(value) { sub(/^[ `t]*/, `"`", value); sub(/[ `t]*`$/, `"`", value); return value } { text=trim(`$0); if (text == `"`" || substr(text, 1, 1) == `"#`") next; equals=index(text, `"=`"); if (equals < 2) exit 1; key=trim(substr(text, 1, equals-1)); value=trim(substr(text, equals+1)); if (!(key in allowed) || (key in seen) || value == `"`") exit 1; seen[key]=1 } END { for (key in required) if (!(key in seen)) exit 1; for (key in paired) if ((key in seen) && !(paired[key] in seen)) exit 1 }' `"`$PROFILE`" || fail `"invalid toolchain profile`"",
        "profile_value() { awk -v wanted=`"`$1`" 'BEGIN { found=0 } /^[ `t]*#/ { next } { line=`$0; sub(/^[ `t]*/, `"`", line); eq=index(line, `"=`"); if (eq < 2) next; key=substr(line, 1, eq-1); value=substr(line, eq+1); sub(/[ `t]*`$/, `"`", key); sub(/^[ `t]*/, `"`", value); sub(/[ `t]*`$/, `"`", value); if (key == wanted) { print value; found=1; exit } } END { if (found == 0) exit 1 }' `"`$PROFILE`"; }",
        'BUILD_CC=$(profile_value build_cc) || fail "profile missing build_cc"',
        'TARGET_CC=$(profile_value target_cc) || fail "profile missing target_cc"',
        'TARGET_ARCH=$(profile_value target_arch) || fail "profile missing target_arch"',
        'TARGET_AR=$(profile_value target_ar) || fail "profile missing target_ar"',
        'TARGET_RANLIB=$(profile_value target_ranlib) || fail "profile missing target_ranlib"',
        'MAKE_TOOL=$(profile_value make) || fail "profile missing make"',
        'SHELL_TOOL=$(profile_value shell) || fail "profile missing shell"',
        'TAR_TOOL=$(profile_value tar) || fail "profile missing tar"',
        'ARCHIVE_CREATE_TOOL=$(profile_value archive_create) || fail "profile missing archive_create"',
        'GZIP_TOOL=$(profile_value gzip) || fail "profile missing gzip"',
        'RSYNC_TOOL=$(profile_value rsync) || fail "profile missing rsync"',
        'LN_TOOL=$(profile_value ln) || fail "profile missing ln"',
        'TOOL_PATH=$(profile_value path) || fail "profile missing path"',
        'ARCH_FLAGS=$(profile_value arch_flags) || fail "profile missing arch_flags"',
        'expr "$TARGET_ARCH" : "[A-Za-z_][A-Za-z0-9_]*\$" >/dev/null || fail "invalid target_arch: $TARGET_ARCH"',
        'case "$TOOL_PATH" in "$TOOLS_DIR/bin"|"$TOOLS_DIR/bin":*) ;; *) fail "profile PATH must select private MIG wrapper first: $TOOLS_DIR/bin" ;; esac',
        'for tool in "$BUILD_CC" "$TARGET_CC" "$TARGET_AR" "$TARGET_RANLIB" "$MAKE_TOOL" "$SHELL_TOOL" "$TAR_TOOL" "$ARCHIVE_CREATE_TOOL" "$GZIP_TOOL" "$RSYNC_TOOL" "$LN_TOOL"; do case "$tool" in /*) ;; *) fail "configured executable is not absolute: $tool" ;; esac; expr "$tool" : "/[-A-Za-z0-9_./+]*\$" >/dev/null || fail "configured executable contains unsafe characters: $tool"; test -f "$tool" && test -x "$tool" || fail "configured executable is not an executable file: $tool"; done',
        'test -x /usr/bin/cc || fail "Developer Tools compiler missing: /usr/bin/cc"',
        'test -x /usr/bin/install || fail "Developer Tools install missing: /usr/bin/install"',
        'test -f /usr/bin/yacc && test -x /usr/bin/yacc || fail "Developer Tools yacc missing: /usr/bin/yacc"',
        'test -f /usr/bin/lex && test -x /usr/bin/lex || fail "Developer Tools lex missing: /usr/bin/lex"',
        'test -f /bin/mv && test -x /bin/mv || fail "generated source rename tool missing: /bin/mv"',
        'test -f /usr/bin/file && test -x /usr/bin/file || fail "object inspection tool missing: /usr/bin/file"',
        'for helper in /usr/bin/tee /usr/bin/cksum /usr/bin/sed /usr/bin/grep /bin/cat /bin/ln; do test -f "$helper" && test -x "$helper" || fail "build helper missing: $helper"; done'
    ) + $hostPhaseParts + @(
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
        (New-RhapTargetProbeCommand),
        'echo "build-src preflight: ok"'
    )
    $body = $parts -join '; '
    return $body
}

function New-RhapBuildPhaseCommand {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('rbuild', 'bootstrap', 'kernel', 'kernel-drivers', 'world')][string]$Phase,
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [Parameter(Mandatory = $true)][string]$ToolsDir,
        [Parameter(Mandatory = $true)][string]$BootstrapRoot,
        [Parameter(Mandatory = $true)][string]$StateDir,
        [Parameter(Mandatory = $true)][string]$Profile,
        [Parameter(Mandatory = $true)][string]$RepoDir,
        [Parameter(Mandatory = $true)][string]$BuiltDir,
        [Parameter(Mandatory = $true)][string]$BuildCc,
        [Parameter(Mandatory = $true)][string]$TargetArch,
        [Parameter(Mandatory = $true)][string]$Make,
        [Parameter(Mandatory = $true)][string]$ToolPath
    )

    foreach ($item in @(
        @($SourceRoot, 'SourceRoot'), @($ToolsDir, 'ToolsDir'),
        @($BootstrapRoot, 'BootstrapRoot'), @($StateDir, 'StateDir'),
        @($Profile, 'Profile'), @($RepoDir, 'RepoDir'), @($BuiltDir, 'BuiltDir'),
        @($BuildCc, 'BuildCc'), @($Make, 'Make')
    )) {
        Assert-RhapSafeCommandPath -Path $item[0] -Name $item[1]
    }

    $source = ConvertTo-RhapShellLiteral $SourceRoot
    $tools = ConvertTo-RhapShellLiteral $ToolsDir
    $bootstrap = ConvertTo-RhapShellLiteral $BootstrapRoot
    $state = ConvertTo-RhapShellLiteral $StateDir
    $profilePath = ConvertTo-RhapShellLiteral $Profile
    $repo = ConvertTo-RhapShellLiteral $RepoDir
    $built = ConvertTo-RhapShellLiteral $BuiltDir
    $cc = ConvertTo-RhapShellLiteral $BuildCc
    $targetArchValue = Assert-RhapSafeIdentifier -Value $TargetArch -Name 'TargetArch'
    $targetArch = ConvertTo-RhapShellLiteral $targetArchValue
    # A universal profile names no single CPU. -Rbuild and -Bootstrap run on
    # the guest, so they use the guest's CPU and the thin profile beside the
    # universal one: rbuild fingerprints bootstrap state by that file's bytes.
    $universal = $targetArchValue -eq 'universal'
    $guestArchSetup = 'GUEST_ARCH=$(/usr/bin/arch); case "$GUEST_ARCH" in i386|ppc) ;; *) echo "build-src: unsupported guest CPU: $GUEST_ARCH" >&2; exit 1 ;; esac'
    $migArch = if ($universal) { '$GUEST_ARCH' } else { $targetArch }
    $makeTool = ConvertTo-RhapShellLiteral $Make
    if ($ToolPath -notmatch '^[A-Za-z0-9_./:+@=-]+$') { throw 'unsafe toolchain path' }
    $toolPath = ConvertTo-RhapShellLiteral $ToolPath
    $rbuild = "$tools/bin/rbuild"
    $decommentBuild = "$tools/decomment-build"
    $configSource = "$source/Commands/bootstrap_cmds/config.tproj"
    $configBuild = "$tools/config-build"
    $migBuild = "$tools/mig-build"
    $migInclude = "$migBuild/include"
    $migSmoke = "$migBuild/smoke"

    if ($Phase -eq 'rbuild') {
        $commands = New-Object System.Collections.Generic.List[string]
        $commands.Add('set -e')
        if ($universal) { $commands.Add($guestArchSetup) }
        $commands.Add("cd $source/rbuild-1")
        $commands.Add("$makeTool CC=$cc clean test all")
        $commands.Add("/usr/bin/install -d $tools/bin")
        $commands.Add("/usr/bin/install -c -m 755 rbuild $rbuild")
        $commands.Add("$cc -O -o $tools/bin/relpath $source/Commands/bootstrap_cmds/relpath.tproj/relpath.c")
        $commands.Add("rm -rf $decommentBuild")
        $commands.Add("/usr/bin/install -d $decommentBuild")
        $commands.Add("$cc -O -o $tools/bin/decomment $source/Commands/bootstrap_cmds/decomment.tproj/decomment.c")
        $commands.Add("printf '%s\n' 'alpha /* block */ beta // line' ' gamma' > $decommentBuild/input.h")
        $commands.Add("$tools/bin/decomment $decommentBuild/input.h r > $decommentBuild/output.h")
        $commands.Add("test `"`$(/bin/cat $decommentBuild/output.h)`" = alphabetagamma || { echo 'build-src: private decomment smoke failed' >&2; exit 1; }")
        $commands.Add("rm -rf $configBuild")
        $commands.Add("/usr/bin/install -d $configBuild")
        $commands.Add("cd $configBuild")
        $commands.Add("/usr/bin/yacc -d $configSource/parser.y")
        $commands.Add("/usr/bin/lex $configSource/lexer.l")
        $commands.Add("$cc -O -bsd -DCMU -DLOCALARCHITECTURE -DNeXT=1 -I$configSource -I$configBuild -o $tools/bin/config $configSource/externs.c $configSource/main.c $configSource/mkglue.c $configSource/mkheaders.c $configSource/mkioconf.c $configSource/mkmakefile.c $configSource/mkswapconf.c $configSource/openp.c $configSource/searchp.c $configBuild/y.tab.c $configBuild/lex.yy.c")
        $commands.Add("rm -rf $migBuild")
        $commands.Add("/usr/bin/install -d $tools/bin $tools/libexec $migInclude/mach/machine $migInclude/mach/ppc $migBuild/migcom $migBuild/migcom_typd $migBuild/migcom_untypd")
        foreach ($header in $script:RhapMigMachHeaders) {
            $commands.Add("/bin/ln -s $source/kernel-7/$header $migInclude/$header")
        }
        $commands.Add("/usr/bin/install -c -m 755 $source/Commands/bootstrap_cmds/migcom.tproj/mig.sh $tools/bin/mig")
        foreach ($project in @(
            @('migcom', 'error.c global.c handler.c header.c mig.c routine.c server.c statement.c string.c type.c user.c utils.c'),
            @('migcom_typd', 'error.c global.c header.c migcom.c routine.c server.c statement.c string.c type.c user.c utils.c'),
            @('migcom_untypd', 'error.c global.c header.c mig.c routine.c server.c statement.c string.c test.c type.c user.c utils.c migcom_untypd_vers_stub.c')
        )) {
            $name = $project[0]
            $migSource = "$source/Commands/bootstrap_cmds/$name.tproj"
            $projectBuild = "$migBuild/$name"
            $compileSources = (($project[1] -split ' ') | ForEach-Object { "$migSource/$_" }) -join ' '
            $commands.Add("cd $projectBuild")
            $commands.Add("/usr/bin/yacc -d $migSource/parser.y")
            $commands.Add('/bin/mv y.tab.h parser.h')
            $commands.Add("/usr/bin/lex $migSource/lexxer.l")
            $compileInputs = "$compileSources $projectBuild/y.tab.c $projectBuild/lex.yy.c"
            $commands.Add("$cc -M -O -bsd -DNeXT=1 -I$migInclude -I$migSource -I$projectBuild $compileInputs > $projectBuild/dependencies")
            $commands.Add("if /usr/bin/grep -F -e '/usr/include/mach/' -e $bootstrap/ $projectBuild/dependencies >/dev/null; then echo 'build-src: private MIG dependency escaped source-owned overlay: $name' >&2; exit 1; else mig_dependency_status=`$?; test `$mig_dependency_status -eq 1 || { echo 'build-src: private MIG dependency audit failed: $name' >&2; exit 1; }; fi")
            $commands.Add("$cc -O -bsd -DNeXT=1 -I$migInclude -I$migSource -I$projectBuild -o $tools/libexec/$name $compileInputs")
        }
        $commands.Add("rm -rf $migSmoke")
        $commands.Add("/usr/bin/install -d $migSmoke")
        $commands.Add("cd $migSmoke")
        $commands.Add("CONFIG_DIR=$tools/bin MIGCC=$cc MIGARCH=$migArch MIGCOM_DIR=$tools/libexec $tools/bin/mig -typed -I$source/kernel-7 -DKERNEL -DKERNEL_SERVER -header /dev/null -user /dev/null -server mach_server.c $source/kernel-7/mach/mach.defs")
        return ($commands -join ' && ')
    }
    if ($Phase -eq 'bootstrap') {
        $bootstrapSetup = 'set -e'
        $bootstrapProfile = $profilePath
        if ($universal) {
            $suffix = '-universal.conf'
            if (-not $Profile.EndsWith($suffix)) {
                throw "universal profile must be named *$suffix so its host profile can be found: $Profile"
            }
            $bootstrapSetup = "set -e; $guestArchSetup"
            $bootstrapProfile = (ConvertTo-RhapShellLiteral $Profile.Substring(0, $Profile.Length - $suffix.Length)) + '-$GUEST_ARCH.conf'
        }
        return "$bootstrapSetup; /usr/bin/install -d $bootstrap $repo $state && cd $source && CONFIG_DIR=$tools/bin DECOMMENT=$tools/bin/decomment MIGCC=$cc MIGARCH=$migArch MIGCOM_DIR=$tools/libexec BISON=$bootstrap/usr/bin/bison BISON_SIMPLE=$bootstrap/usr/share/bison.simple $rbuild bootstrap --sysroot $bootstrap --toolchain $bootstrapProfile --state $state $source/BootstrapManifest $repo $repo && CONFIG_DIR=$tools/bin DECOMMENT=$tools/bin/decomment MIGCC=$cc MIGARCH=$migArch MIGCOM_DIR=$tools/libexec BISON=$bootstrap/usr/bin/bison BISON_SIMPLE=$bootstrap/usr/share/bison.simple $rbuild bootstrap-universal --sysroot $bootstrap --toolchain $bootstrapProfile --state $state $source/BootstrapManifest $repo $repo"
    }
    if ($Phase -eq 'world') {
        return "set -e; test -d $repo || { echo 'build-src: repository missing: $RepoDir' >&2; exit 1; }; /usr/bin/install -d $built $state && cd $source && $rbuild buildall --state $state Manifest $repo $built"
    }
    # rbuild builds one kernel CPU per run; a universal profile means both.
    $kernelArchs = if ($targetArchValue -eq 'universal') { @('i386', 'ppc') } else { @($targetArch) }
    $kernelCommand = if ($Phase -eq 'kernel') { 'kernel' } else { 'kerneldrivers' }
    $kernelBuilds = ($kernelArchs | ForEach-Object {
        "$rbuild $kernelCommand --state $state --toolchain $profilePath --arch $_ $source $repo $built"
    }) -join ' && '
    return "set -e; test -d $repo || { echo 'build-src: repository missing: $RepoDir' >&2; exit 1; }; /usr/bin/install -d $built $state && cd $source && $kernelBuilds"
}

function New-RhapFreshCommand {
    param(
        [Parameter(Mandatory = $true)][string]$RemoteRoot,
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [Parameter(Mandatory = $true)][string]$Profile,
        [Parameter(Mandatory = $true)][string]$ToolsDir,
        [Parameter(Mandatory = $true)][string]$BootstrapRoot,
        [Parameter(Mandatory = $true)][string]$RepoDir,
        [Parameter(Mandatory = $true)][string]$BuiltDir,
        [Parameter(Mandatory = $true)][string]$StateDir
    )

    $root = ConvertTo-RhapNormalizedRemotePath -Path $RemoteRoot -Name 'RemoteRoot'
    $source = ConvertTo-RhapNormalizedRemotePath -Path $SourceRoot -Name 'SourceRoot'
    $profilePath = ConvertTo-RhapNormalizedRemotePath -Path $Profile -Name 'ToolchainProfile'
    $targets = @(Assert-RhapSafeBuildTopology -RemoteRoot $root -SourceRoot $source -Outputs @($ToolsDir, $BootstrapRoot, $RepoDir, $BuiltDir, $StateDir))
    foreach ($target in $targets) {
        if (Test-RhapPathOverlapIgnoreCase -Left $profilePath -Right $target) {
            throw 'ToolchainProfile overlaps a Fresh output role'
        }
    }
    $quoted = @($targets | ForEach-Object { "'$_'" })
    $parents = New-Object System.Collections.Generic.List[string]
    foreach ($target in $targets) {
        $lastSlash = $target.LastIndexOf('/')
        $parent = if ($lastSlash -eq 0) { '/' } else { $target.Substring(0, $lastSlash) }
        if (-not [string]::Equals($parent, $root, [System.StringComparison]::Ordinal)) {
            [void](Assert-RhapSafeRemoteOutputPath -RemoteRoot $root -Path $parent)
        }
        $seen = $false
        foreach ($existing in $parents) {
            if ([string]::Equals($parent, $existing, [System.StringComparison]::Ordinal)) {
                $seen = $true
                break
            }
        }
        if (-not $seen) { $parents.Add($parent) }
    }
    $quotedParents = @($parents | ForEach-Object { "'$_'" })
    $checks = @(
        'set -e',
        "ROOT='$root'",
        "SOURCE='$source'",
        "PROFILE='$profilePath'",
        'fail() { echo "build-src fresh: $*" >&2; exit 1; }',
        'ROOT_PHYS=$(cd "$ROOT" && pwd) || fail "cannot resolve RemoteRoot"',
        'SOURCE_PHYS=$(cd "$SOURCE" && pwd) || fail "cannot resolve SourceRoot"',
        'test "$ROOT_PHYS" != / || fail "physical RemoteRoot may not be /"',
        'case "$SOURCE_PHYS" in "$ROOT_PHYS"/*) ;; *) fail "SourceRoot escapes RemoteRoot" ;; esac',
        'test -f "$PROFILE" || fail "ToolchainProfile is not a regular file"',
        'test ! -L "$PROFILE" || fail "ToolchainProfile may not be a symlink for Fresh"',
        'PROFILE_PARENT=${PROFILE%/*}; test -n "$PROFILE_PARENT" || PROFILE_PARENT=/',
        'PROFILE_PARENT_PHYS=$(cd "$PROFILE_PARENT" 2>/dev/null && pwd) || fail "cannot resolve ToolchainProfile parent"',
        'PROFILE_PHYS="$PROFILE_PARENT_PHYS/${PROFILE##*/}"',
        'check_target() { target=$1; probe=$target; while test "$probe" != "$ROOT"; do if test -L "$probe"; then fail "symlink in output path: $probe"; fi; next=${probe%/*}; test -n "$next" || next=/; test "$next" != "$probe" || fail "invalid output path"; probe=$next; done; probe=$target; suffix=; while test ! -e "$probe"; do leaf=${probe##*/}; suffix=/$leaf$suffix; probe=${probe%/*}; test -n "$probe" || probe=/; done; if test -d "$probe"; then physical=$(cd "$probe" 2>/dev/null && pwd) || fail "cannot resolve $probe"; target_physical=$physical$suffix; else parent=${probe%/*}; test -n "$parent" || parent=/; physical=$(cd "$parent" 2>/dev/null && pwd) || fail "cannot resolve $parent"; target_physical=$physical/${probe##*/}$suffix; fi; case "$target_physical" in "$ROOT_PHYS"|"$ROOT_PHYS"/*) ;; *) fail "output escapes RemoteRoot: $target" ;; esac; case "$target_physical" in "$SOURCE_PHYS"|"$SOURCE_PHYS"/*) fail "output reaches SourceRoot: $target" ;; esac; case "$PROFILE_PHYS" in "$target_physical"|"$target_physical"/*) fail "ToolchainProfile physically overlaps Fresh output: $target" ;; esac; case "$target_physical" in "$PROFILE_PHYS"|"$PROFILE_PHYS"/*) fail "Fresh output physically overlaps ToolchainProfile: $target" ;; esac; }'
    )
    foreach ($target in $targets) { $checks += "check_target '$target'" }
    $checks += "rm -rf $($quoted -join ' ')"
    $checks += "mkdir -p $($quotedParents -join ' ')"
    return $checks -join "`n"
}
