#Requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:Checks = 0

function Assert-Equal($Actual, $Expected, [string]$Name) {
    $script:Checks++
    if ($Actual -ne $Expected) {
        throw "$Name`: expected [$Expected], got [$Actual]"
    }
}

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

function Assert-Throws([scriptblock]$Action, [string]$Name) {
    $script:Checks++
    try {
        & $Action
    } catch {
        return
    }
    throw "$Name`: expected an exception"
}

function Assert-RemotePayloadBytes([string]$Path, [string]$ScriptBody, [string]$Name) {
    $actual = [System.IO.File]::ReadAllBytes($Path)
    $normalized = $ScriptBody.Replace("`r`n", "`n").Replace("`r", "`n").TrimEnd("`n") + "`n"
    $strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
    $expected = $strictUtf8.GetBytes($normalized)
    $hasBom = $actual.Length -ge 3 -and $actual[0] -eq 0xEF -and $actual[1] -eq 0xBB -and $actual[2] -eq 0xBF
    Assert-Equal $hasBom $false "$Name has no UTF-8 BOM"
    Assert-Equal ([Convert]::ToBase64String($actual)) ([Convert]::ToBase64String($expected)) "$Name exact strict UTF-8 bytes"
}

function Get-EncodingSignature([System.Text.Encoding]$Encoding) {
    return [pscustomobject]@{
        CodePage = $Encoding.CodePage
        WebName = $Encoding.WebName
        EncoderFallback = $Encoding.EncoderFallback.GetType().FullName
        DecoderFallback = $Encoding.DecoderFallback.GetType().FullName
        Preamble = [Convert]::ToBase64String($Encoding.GetPreamble())
    }
}

function Assert-EncodingSignature($Actual, $Expected, [string]$Name) {
    Assert-Equal $Actual.CodePage $Expected.CodePage "$Name code page"
    Assert-Equal $Actual.WebName $Expected.WebName "$Name web name"
    Assert-Equal $Actual.EncoderFallback $Expected.EncoderFallback "$Name encoder fallback"
    Assert-Equal $Actual.DecoderFallback $Expected.DecoderFallback "$Name decoder fallback"
    Assert-Equal $Actual.Preamble $Expected.Preamble "$Name preamble"
}

. (Join-Path $PSScriptRoot 'build-src-lib.ps1')
$realProfile = Get-Content -Raw (Join-Path $PSScriptRoot '..\src\rbuild-1\toolchains\gcc-darwin.conf')

$buildScriptText = Get-Content -Raw (Join-Path $PSScriptRoot 'build-src.ps1')
$remoteScriptText = Get-Content -Raw (Join-Path $PSScriptRoot 'rhap-remote.ps1')
$migWrapperText = Get-Content -Raw (Join-Path $PSScriptRoot '..\src\Commands\bootstrap_cmds\migcom.tproj\mig.sh')
$classicErrorText = Get-Content -Raw (Join-Path $PSScriptRoot '..\src\Commands\bootstrap_cmds\migcom.tproj\error.c')
$classicErrorHeaderText = Get-Content -Raw (Join-Path $PSScriptRoot '..\src\Commands\bootstrap_cmds\migcom.tproj\error.h')
$classicUtilsText = Get-Content -Raw (Join-Path $PSScriptRoot '..\src\Commands\bootstrap_cmds\migcom.tproj\utils.c')
$typedErrorText = Get-Content -Raw (Join-Path $PSScriptRoot '..\src\Commands\bootstrap_cmds\migcom_typd.tproj\error.c')
$typedErrorHeaderText = Get-Content -Raw (Join-Path $PSScriptRoot '..\src\Commands\bootstrap_cmds\migcom_typd.tproj\error.h')
$kernelMakeTemplateText = Get-Content -Raw (Join-Path $PSScriptRoot '..\src\kernel-7\conf\Makefile.template')
$pkginfoSourceText = Get-Content -Raw (Join-Path $PSScriptRoot '..\src\rbuild-1\pkginfo.c')
$decommentSourcePath = Join-Path $PSScriptRoot '..\src\Commands\bootstrap_cmds\decomment.tproj\decomment.c'
$decommentSourceText = Get-Content -Raw $decommentSourcePath
Assert-Match $migWrapperText 'MIGCC' 'MIG wrapper supports configured compiler override'
Assert-Match $migWrapperText 'MIGARCH' 'MIG wrapper supports configured architecture override'
Assert-Match $migWrapperText 'append_cppflag "-D\$mig_arch"' 'configured GCC receives one preserved architecture definition'
Assert-Match $migWrapperText 'mig_arch=\$\{MIGARCH-\}' 'configured architecture begins only from MIGARCH'
Assert-Match $migWrapperText 'arch=\$2; mig_arch=\$2' 'explicit -arch overrides both configured and historical architecture state'
Assert-Match $migWrapperText 'MIGCOM_DIR' 'MIG wrapper supports private libexec override'
Assert-Match $migWrapperText '-i[ `t]+\)' 'MIG wrapper forwards -i and its argument'
Assert-Match $migWrapperText '\$\{1#-\}.*=.*\$1' 'MIG wrapper preserves a following option after optional -i prefix'
Assert-Match $migWrapperText 'MIGCOM_ROOT/migcom_typd' 'MIG wrapper selects typed compiler below configured libexec'
Assert-Match $migWrapperText 'MIGCOM_DIR-/usr/libexec' 'MIG wrapper preserves packaged target libexec default'
Assert-Match $migWrapperText '"\$MIGCC" -E -x c -traditional-cpp' 'configured GCC forces C preprocessing for defs inputs while preserving historical semantics'
Assert-Match $migWrapperText '"\$MIGCC" -E -x c -traditional-cpp[^\r\n]*"\$file"' 'configured GCC wrapper exercise accepts a defs filename as its single input'
Assert-Match $migWrapperText '"\$CPP" \$cppflags "\$file" -' 'default compiler branch preserves historical cpp invocation'
Assert-Match $migWrapperText 'IFS=\$newline' 'MIG wrapper splits only its newline-delimited argument lists'
Assert-Match $migWrapperText '(?m)^set -f$' 'MIG wrapper disables pathname expansion for controlled argument expansion'
Assert-Match $migWrapperText 'argument contains a newline' 'MIG wrapper rejects unrepresentable newline arguments'
Assert-NotMatch $migWrapperText '(?m)^\s*"?\$MIGCC"?[^\r\n]*"\$file"\s+-' 'configured GCC receives one input and writes preprocessed output to stdout'
Assert-Match $migWrapperText '"\$migcom" \$migflags < "\$mig_tmp"' 'MIG wrapper preserves spaces in private libexec path and consumes staged preprocessing'
Assert-Match $migWrapperText 'MIGCPP-' 'MIG wrapper supports an optional compatibility cpp override'
Assert-Match $migWrapperText '/usr/libexec/\$\{arch-' 'MIG wrapper preserves architecture-specific historical cpp default'
Assert-Match $migWrapperText 'trap finish 0' 'MIG wrapper cleans staged preprocessing on every exit'
Assert-Match $migWrapperText '(?s)mig_tmp_candidate=.*?if mkdir "\$mig_tmp_candidate".*?mig_tmp_dir=\$mig_tmp_candidate' 'MIG wrapper claims staging ownership only after atomic directory creation'
Assert-Match $migWrapperText 'rm -f "\$mig_tmp_dir/input"[\r\n]+\s*rmdir "\$mig_tmp_dir"' 'MIG wrapper cleans only its fixed file and owned directory non-recursively'
Assert-NotMatch $migWrapperText 'rm -rf[^\r\n]*mig_tmp|test -e "\$mig_tmp_candidate"' 'MIG wrapper never recursively removes or prechecks an unowned staging candidate'
Assert-Match $migWrapperText '(?s)trap ''{2} 1 2 3 15.*?mkdir "\$mig_tmp_candidate".*?mig_tmp_dir=\$mig_tmp_candidate.*?trap ''exit 1'' 1 2 3 15' 'MIG wrapper ignores cleanup signals only through atomic ownership assignment'
Assert-Match $migWrapperText '(?s)else[\r\n\s]+trap ''exit 1'' 1 2 3 15[\r\n\s]+echo "mig: could not create private preprocessor staging directory' 'MIG wrapper restores signal handlers when staging mkdir fails'
Assert-Match $migWrapperText '(?s)finish\(\).*?trap - 0 1 2 3 15.*?cleanup' 'MIG wrapper disables every trap before exit cleanup'
Assert-Match $migWrapperText '-sheader[ `t]+\)[^\r\n]*append_migflag "\$1"; append_migflag "\$2"' 'MIG wrapper forwards server-header output to backend'
Assert-Match $migWrapperText '-handler[ `t]+\)[^\r\n]*append_migflag "\$1"; append_migflag "\$2"' 'MIG wrapper forwards handler output to backend'
Assert-NotMatch $migWrapperText 'NEXT_ROOT' 'MIG wrapper never derives compiler location from a sysroot'
Assert-Match $classicErrorText '#include <stdarg\.h>' 'classic MIG errors use GCC-compatible standard varargs'
Assert-Match $classicUtilsText '#include <stdarg\.h>' 'classic MIG writers use GCC-compatible standard varargs'
Assert-Equal ([regex]::Matches($classicUtilsText, '#include <stdarg\.h>').Count) 1 'classic MIG writers include standard varargs once'
Assert-NotMatch ($classicErrorText + $classicUtilsText) '<varargs\.h>|\bva_dcl\b|va_start\([^,\r\n]+\)' 'classic MIG has no obsolete varargs interface'
Assert-Match $classicErrorText 'strerror\(error_num\)' 'classic MIG uses the host-supported error string interface'
Assert-NotMatch $classicErrorHeaderText '<mach/mach_error\.h>' 'classic MIG does not import an unused live-only Mach error header'
Assert-Match $typedErrorText 'strerror\(error_num\)' 'typed MIG uses the host-supported error string interface'
Assert-NotMatch ($classicErrorText + $typedErrorText + $typedErrorHeaderText) '(?m)^\s*extern[^\r\n]*\b(sys_nerr|sys_errlist)\b|\b(sys_nerr|sys_errlist)\s*\[' 'private MIG sources do not depend on obsolete libc error tables'
Assert-Match $kernelMakeTemplateText '(?m)^DECOMMENT \?= /usr/local/bin/decomment$' 'kernel preserves an overrideable historical decomment default'
Assert-NotMatch $kernelMakeTemplateText '(?m)^\s*@-for i in (?:\$\{EXPORT\}|`echo \$\{MACHINE_EXPORT\}`)' 'kernel header export recipes do not ignore loop failure'
Assert-Equal ([regex]::Matches($kernelMakeTemplateText, 'unifdef_status=\$\$\?;').Count) 2 'both kernel export loops capture unifdef status immediately'
Assert-Equal ([regex]::Matches($kernelMakeTemplateText, '\[ \$\$unifdef_status -eq 1 \]').Count) 2 'both kernel export loops reserve decomment fallback for unifdef status one'
Assert-Equal ([regex]::Matches($kernelMakeTemplateText, '\[ \$\$unifdef_status -ne 0 \]').Count) 2 'both kernel export loops reject unexpected unifdef failure'
Assert-Equal ([regex]::Matches($kernelMakeTemplateText, 'object_dir=`pwd` \|\| exit 1;').Count) 2 'both kernel export loops reject failed object directory capture'
Assert-Equal ([regex]::Matches($kernelMakeTemplateText, 'EXPDIR="\$\$object_dir/exports";').Count) 2 'both kernel export loops preserve the guarded object directory'
Assert-Equal ([regex]::Matches($kernelMakeTemplateText, '\(cd "\$\(SOURCE_DIR\)/\$\$i" \|\| exit 1;').Count) 2 'both kernel export loops quote and guard source directory changes'
Assert-Equal ([regex]::Matches($kernelMakeTemplateText, 'DSTDIR="\$\(DSTROOT\)\$\(INCDIR\)/\$\$i";').Count) 2 'both kernel export loops preserve space-containing destination paths'
Assert-Equal ([regex]::Matches($kernelMakeTemplateText, '"\$\(DECOMMENT\)" "\$\$EXPDIR/\$\$j"  r >\s*(?:\\\r?\n\s*)?"\$\$EXPDIR/\$\$j\.strip" \|\| exit 1;').Count) 2 'both kernel export loops quote and hard-fail the decomment fallback'
Assert-Equal ([regex]::Matches($kernelMakeTemplateText, '\[ -d "\$\$EXPDIR" \] \|\| \$\(MKDIRS\) "\$\$EXPDIR" \|\| exit 1;').Count) 2 'both kernel export loops reject export directory creation failure'
Assert-Equal ([regex]::Matches($kernelMakeTemplateText, '\[ -d "\$\$DSTDIR" \] \|\| \$\(MKDIRS\) "\$\$DSTDIR" \|\| exit 1;').Count) 2 'both kernel export loops reject destination directory creation failure'
Assert-Equal ([regex]::Matches($kernelMakeTemplateText, 'rm -f "\$\$EXPDIR"/\* \|\| exit 1;').Count) 2 'both kernel export loops reject export cleanup failure'
Assert-Equal ([regex]::Matches($kernelMakeTemplateText, 'echo garbage > "\$\$EXPDIR/\$\$j\.strip" \|\| exit 1;').Count) 2 'both kernel export loops reject sentinel write failure'
Assert-Equal ([regex]::Matches($kernelMakeTemplateText, '"\$\$j" > "\$\$EXPDIR/\$\$j";').Count) 2 'both kernel export loops quote unifdef header paths and output'
Assert-Equal ([regex]::Matches($kernelMakeTemplateText, '\[ -s "\$\$EXPDIR/\$\$j\.strip" \]').Count) 2 'both kernel export loops quote exported-header probes'
Assert-Equal ([regex]::Matches($kernelMakeTemplateText, 'cd "\$\$EXPDIR" \|\| exit 1;').Count) 2 'both kernel export loops quote and guard export directory changes'
Assert-Equal ([regex]::Matches($kernelMakeTemplateText, 'install \$\(INSTALL_FLAGS\) "\$\$j" "\$\$DSTDIR";').Count) 2 'both kernel export loops quote install source and destination paths'
Assert-Equal ([regex]::Matches($kernelMakeTemplateText, 'rm -f "\$\$EXPDIR/\$\$j\.strip" \|\| exit 1;').Count) 2 'both kernel export loops reject normal probe cleanup failure'
Assert-Equal ([regex]::Matches($kernelMakeTemplateText, 'install_status=\$\$\?;').Count) 2 'both kernel export loops capture install status immediately'
Assert-Equal ([regex]::Matches($kernelMakeTemplateText, 'if \[ \$\$install_status -ne 0 \]; then[\s\S]*?rm -f "\$\$EXPDIR/\$\$j\.strip";[\s\S]*?exit 1;').Count) 2 'both kernel export loops clean probes without masking install failure'
Assert-Equal ([regex]::Matches($kernelMakeTemplateText, '\) \|\| exit 1;\s*\\\r?\n\s*done').Count) 2 'both kernel export loops propagate header-directory subshell failure'
Assert-Match $pkginfoSourceText 'tc->archive_create' 'configured APK creation selects the generic archive creator'
Assert-Match $pkginfoSourceText 'tc->archive_create_flags' 'configured APK creation expands generic creator flags'
Assert-Match $pkginfoSourceText 'archive_cwd != 0 && chdir\(archive_cwd\) != 0' 'configured archive child enters the package root'
Assert-NotMatch $pkginfoSourceText 'tc->tar_create_flags' 'APK creation has no tar-specific configured flags'
foreach ($header in @('stdio.h', 'ctype.h', 'fcntl.h', 'stdlib.h', 'unistd.h')) {
    Assert-Match $decommentSourceText ("#include <{0}>" -f [regex]::Escape($header)) "decomment declares precise $header dependency"
}
Assert-NotMatch $decommentSourceText '#import|bsd/libc\.h' 'decomment has no obsolete umbrella or import directive'
Assert-Match $decommentSourceText 'if\(fd < 0\)' 'decomment accepts descriptor zero from open'
Assert-NotMatch $decommentSourceText 'if\(fd <= 0\)' 'decomment does not reject descriptor zero'
Assert-Equal ([regex]::Matches($decommentSourceText, 'isspace\(\(unsigned char\)bufchar\)').Count) 2 'decomment passes unsigned bytes to ctype'

$decommentRuntimeDir = Join-Path $env:TEMP ("rhap-decomment-runtime-{0}" -f [guid]::NewGuid().ToString('n'))
New-Item -ItemType Directory -Path $decommentRuntimeDir | Out-Null
try {
    $clangCommand = Get-Command clang.exe -ErrorAction SilentlyContinue
    $clang = if ($null -eq $clangCommand) { $null } else { $clangCommand.Source }
    if ([string]::IsNullOrWhiteSpace($clang)) {
        $clang = Join-Path $env:ProgramFiles 'LLVM\bin\clang.exe'
    }
    Assert-Equal (Test-Path -LiteralPath $clang -PathType Leaf) $true 'LLVM compiler is available for decomment runtime contract'
    $unistd = Join-Path $decommentRuntimeDir 'unistd.h'
    $runnerSource = Join-Path $decommentRuntimeDir 'fd0-runner.c'
    $decommentExe = Join-Path $decommentRuntimeDir 'decomment.exe'
    $runnerExe = Join-Path $decommentRuntimeDir 'fd0-runner.exe'
    $input = Join-Path $decommentRuntimeDir 'input.h'
    Set-Content -LiteralPath $unistd -Encoding ASCII -Value @(
        '#include <io.h>',
        '#define read _read'
    )
    Set-Content -LiteralPath $runnerSource -Encoding ASCII -Value @(
        '#include <io.h>',
        '#include <process.h>',
        'int main(int argc, char **argv) {',
        '    if (argc != 3 || _close(0) != 0) return 125;',
        '    return _spawnl(_P_WAIT, argv[1], argv[1], argv[2], "r", (char *)0);',
        '}'
    )
    Set-Content -LiteralPath $input -Encoding ASCII -Value @(
        'alpha /* block */ beta // line',
        ' gamma'
    )
    & $clang -std=c89 -Wall -Wextra -Werror -Wno-deprecated-declarations `
        -I $decommentRuntimeDir -Dopen=_open -o $decommentExe $decommentSourcePath
    Assert-Equal $LASTEXITCODE 0 'LLVM compiles decomment with precise headers'
    & $clang -std=c89 -Wall -Wextra -Werror -Wno-deprecated-declarations `
        -o $runnerExe $runnerSource
    Assert-Equal $LASTEXITCODE 0 'LLVM compiles descriptor-zero decomment runner'
    $normalOutput = (& $decommentExe $input r) -join "`n"
    Assert-Equal $LASTEXITCODE 0 'decomment runtime fixture succeeds normally'
    Assert-Equal $normalOutput 'alphabetagamma' 'decomment strips block, line, and whitespace comments'
    $fdZeroOutput = (& $runnerExe $decommentExe $input) -join "`n"
    Assert-Equal $LASTEXITCODE 0 'decomment accepts its input file as descriptor zero'
    Assert-Equal $fdZeroOutput 'alphabetagamma' 'descriptor-zero decomment preserves scanner behavior'
} finally {
    Remove-Item -LiteralPath $decommentRuntimeDir -Recurse -Force -ErrorAction SilentlyContinue
}
Assert-Match $buildScriptText '(?s)param\(\s*\[switch\]\$All,\s*\[switch\]\$Rbuild,\s*\[switch\]\$Bootstrap,\s*\[switch\]\$KernelDrivers,\s*\[switch\]\$World,\s*\[switch\]\$Fresh\s*\)' 'canonical build-src parameters'
Assert-Match $remoteScriptText ([regex]::Escape('$stdinWriter.WriteAsync($payload)')) 'stream stdin writer is asynchronous'
Assert-Match $remoteScriptText 'Task\]::WaitAny' 'stream writer and readers share a blocking task loop'
Assert-Match $remoteScriptText '\[void\]\$writeTask\.GetAwaiter\(\)\.GetResult\(\)' 'stream writer task result cannot pollute exit status'
Assert-Equal ([regex]::Matches($remoteScriptText, 'ReadLineAsync\(\)').Count -ge 4) $true 'stream readers are continuously renewed'
Assert-Equal ($remoteScriptText.IndexOf('ReadLineAsync()') -lt $remoteScriptText.IndexOf('$stdinWriter.WriteAsync($payload)')) $true 'stream readers are armed with async stdin writer'
Assert-Match $remoteScriptText '(?s)\$stdoutTask = \$process\.StandardOutput\.ReadLineAsync\(\).*?\$sinkError.*?& \$emitStdout' 'stdout renews before deferred sink handling'
Assert-Match $remoteScriptText '(?s)\$stderrTask = \$process\.StandardError\.ReadLineAsync\(\).*?\$sinkError.*?& \$emitStderr' 'stderr renews before deferred sink handling'
Assert-Match $remoteScriptText '\$process\.Kill\(\)' 'exceptional streaming cleanup terminates exact child'
Assert-Match $remoteScriptText '(?s)finally \{.*?WaitForExit\(\).*?Dispose\(\)' 'exceptional cleanup reaps before dispose'
Assert-Equal ($buildScriptText.IndexOf('New-RhapFreshCommand') -lt $buildScriptText.IndexOf('New-RhapPreflightCommand')) $true 'fresh topology validates before preflight'
Assert-Match $buildScriptText 'New-RhapFreshCommand[^\r\n]+-Profile \$cfg\.ToolchainProfile' 'fresh validates resolved configured profile'
Assert-Match $buildScriptText ([regex]::Escape('-TargetArch $profileValues.target_arch')) 'phase generation consumes the selected profile architecture'

$phaseArgs = @{
    SourceRoot = '/build/src'
    ToolsDir = '/build/tools'
    BootstrapRoot = '/build/bootstrap-root'
    StateDir = '/build/state'
    Profile = '/build/src/rbuild-1/toolchains/gcc-darwin.conf'
    RepoDir = '/build/repo'
    BuiltDir = '/build/built'
    BuildCc = '/usr/bin/cc'
    TargetArch = 'ppc'
    Make = '/usr/bin/make'
    ToolPath = '/build/tools/bin:/usr/bin:/bin'
}
$rbuildCommand = New-RhapBuildPhaseCommand -Phase 'rbuild' @phaseArgs
Assert-Match $rbuildCommand ([regex]::Escape('cd /build/src/rbuild-1 && /usr/bin/make CC=/usr/bin/cc clean test all')) 'rbuild cleans tests and builds with profile compiler'
Assert-Match $rbuildCommand ([regex]::Escape('/usr/bin/install -d /build/tools/bin')) 'rbuild creates private tool directory'
Assert-Match $rbuildCommand ([regex]::Escape('/usr/bin/install -c -m 755 rbuild /build/tools/bin/rbuild')) 'rbuild installs privately'
Assert-Match $rbuildCommand ([regex]::Escape('/usr/bin/cc -O -o /build/tools/bin/relpath /build/src/Commands/bootstrap_cmds/relpath.tproj/relpath.c')) 'relpath is source-built with profile compiler'
Assert-Match $rbuildCommand ([regex]::Escape('/usr/bin/cc -O -o /build/tools/bin/decomment /build/src/Commands/bootstrap_cmds/decomment.tproj/decomment.c')) 'decomment is source-built privately with profile compiler'
Assert-Match $rbuildCommand ([regex]::Escape("printf '%s\n' 'alpha /* block */ beta // line' ' gamma' > /build/tools/decomment-build/input.h")) 'decomment smoke covers block, line, and whitespace removal'
Assert-Match $rbuildCommand ([regex]::Escape('/build/tools/bin/decomment /build/tools/decomment-build/input.h r > /build/tools/decomment-build/output.h')) 'decomment smoke executes the private product'
Assert-Match $rbuildCommand ([regex]::Escape('test "$(/bin/cat /build/tools/decomment-build/output.h)" = alphabetagamma')) 'decomment smoke validates meaningful exact output'
Assert-NotMatch $rbuildCommand '/usr/local/bin/decomment|bootstrap-root/(usr/)?(?:local/)?bin/decomment|cp .*decomment' 'stage zero never copies or selects live or sysroot decomment'
Assert-Match $rbuildCommand ([regex]::Escape('rm -rf /build/tools/config-build')) 'config private build directory is recreated exactly'
Assert-Match $rbuildCommand ([regex]::Escape('/usr/bin/install -d /build/tools/config-build')) 'config uses private build directory'
Assert-Match $rbuildCommand ([regex]::Escape('/usr/bin/yacc -d /build/src/Commands/bootstrap_cmds/config.tproj/parser.y')) 'config parser is source-generated'
Assert-Match $rbuildCommand ([regex]::Escape('/usr/bin/lex /build/src/Commands/bootstrap_cmds/config.tproj/lexer.l')) 'config lexer is source-generated'
Assert-Match $rbuildCommand ([regex]::Escape('/usr/bin/cc -O -bsd -DCMU -DLOCALARCHITECTURE -DNeXT=1 -I/build/src/Commands/bootstrap_cmds/config.tproj -I/build/tools/config-build -o /build/tools/bin/config')) 'config preserves project compiler flags and builds privately with profile compiler'
Assert-NotMatch $rbuildCommand '/usr/local/bin/config|cp .*config|DSTROOT=/' 'config never copies or installs to live host'
Assert-Match $rbuildCommand ([regex]::Escape('rm -rf /build/tools/mig-build')) 'MIG private build root is recreated exactly'
Assert-Match $rbuildCommand ([regex]::Escape('/usr/bin/install -d /build/tools/bin /build/tools/libexec /build/tools/mig-build/include/mach/machine /build/tools/mig-build/include/mach/ppc /build/tools/mig-build/migcom /build/tools/mig-build/migcom_typd /build/tools/mig-build/migcom_untypd')) 'MIG private product, overlay, and build directories are created'
Assert-Match $rbuildCommand ([regex]::Escape('/usr/bin/install -c -m 755 /build/src/Commands/bootstrap_cmds/migcom.tproj/mig.sh /build/tools/bin/mig')) 'repository MIG wrapper is installed privately'
Assert-Match $rbuildCommand ([regex]::Escape('/build/tools/mig-build/include/mach/message.h')) 'MIG build creates a private source-owned Mach header overlay'
Assert-Match $rbuildCommand ([regex]::Escape('/bin/ln -s /build/src/kernel-7/mach/ndr.h /build/tools/mig-build/include/mach/ndr.h')) 'MIG overlay includes the untyped backend NDR dependency'
Assert-Match $rbuildCommand ([regex]::Escape('/bin/ln -s /build/src/kernel-7/mach/ppc/simple_lock.h /build/tools/mig-build/include/mach/ppc/simple_lock.h')) 'MIG overlay declares its complete verified PPC header closure'
Assert-Match $rbuildCommand ([regex]::Escape('-I/build/tools/mig-build/include')) 'MIG compilers search the private header overlay first'
Assert-Match $rbuildCommand ([regex]::Escape('-M -O -bsd -DNeXT=1 -I/build/tools/mig-build/include')) 'MIG dependency audit uses the real private compile flags'
Assert-Match $rbuildCommand ([regex]::Escape('/usr/include/mach/')) 'MIG dependency audit rejects live host Mach headers'
Assert-Match $rbuildCommand ([regex]::Escape('/build/bootstrap-root/')) 'MIG dependency audit rejects bootstrap sysroot headers'
Assert-Match $rbuildCommand ([regex]::Escape('/usr/bin/yacc -d /build/src/Commands/bootstrap_cmds/migcom.tproj/parser.y && /bin/mv y.tab.h parser.h && /usr/bin/lex /build/src/Commands/bootstrap_cmds/migcom.tproj/lexxer.l')) 'classic MIG parser and lexer are generated privately'
Assert-Match $rbuildCommand ([regex]::Escape('-o /build/tools/libexec/migcom ')) 'classic MIG compiler is private'
Assert-Match $rbuildCommand ([regex]::Escape('-o /build/tools/libexec/migcom_typd ')) 'typed MIG compiler is private'
Assert-Match $rbuildCommand ([regex]::Escape('-o /build/tools/libexec/migcom_untypd ')) 'untyped MIG compiler is private'
Assert-Match $rbuildCommand ([regex]::Escape('/usr/bin/cc -O -bsd -DNeXT=1 -I/build/tools/mig-build/include -I/build/src/Commands/bootstrap_cmds/migcom.tproj -I/build/tools/mig-build/migcom -o /build/tools/libexec/migcom')) 'classic MIG enables Rhapsody handler and padding support'
Assert-Match $rbuildCommand ([regex]::Escape('/usr/bin/cc -O -bsd -DNeXT=1 -I/build/tools/mig-build/include -I/build/src/Commands/bootstrap_cmds/migcom_typd.tproj -I/build/tools/mig-build/migcom_typd -o /build/tools/libexec/migcom_typd')) 'typed MIG preserves historical platform flags'
Assert-Match $rbuildCommand ([regex]::Escape('/usr/bin/cc -O -bsd -DNeXT=1 -I/build/tools/mig-build/include -I/build/src/Commands/bootstrap_cmds/migcom_untypd.tproj -I/build/tools/mig-build/migcom_untypd -o /build/tools/libexec/migcom_untypd')) 'untyped MIG preserves historical platform flags'
Assert-Match $rbuildCommand ([regex]::Escape('/migcom.tproj/handler.c')) 'classic MIG links the NeXT handler backend'
Assert-Match $rbuildCommand ([regex]::Escape('/build/src/Commands/bootstrap_cmds/migcom_untypd.tproj/migcom_untypd_vers_stub.c')) 'untyped MIG compiler links its checked-in version stub'
Assert-Match $rbuildCommand ([regex]::Escape('CONFIG_DIR=/build/tools/bin MIGCC=/usr/bin/cc MIGARCH=ppc MIGCOM_DIR=/build/tools/libexec /build/tools/bin/mig -typed -I/build/src/kernel-7 -DKERNEL -DKERNEL_SERVER -header /dev/null -user /dev/null -server mach_server.c /build/src/kernel-7/mach/mach.defs')) 'private typed MIG wrapper contract preprocesses a real defs filename with configured GCC and profile architecture'
Assert-NotMatch $rbuildCommand '/usr/bin/mig|/usr/libexec/migcom|NEXT_ROOT|bootstrap-root/usr/libexec|DSTROOT=/|cp .*mig' 'stage zero never uses or copies live or sysroot MIG'
$alternatePhaseArgs = $phaseArgs.Clone()
$alternatePhaseArgs.BuildCc = '/opt/gcc/bin/gcc-4.2'
$alternatePhaseArgs.TargetArch = 'mips_safe'
$alternatePhaseArgs.Make = '/opt/make/bin/gmake'
$alternateRbuild = New-RhapBuildPhaseCommand -Phase 'rbuild' @alternatePhaseArgs
Assert-Match $alternateRbuild ([regex]::Escape('/opt/make/bin/gmake CC=/opt/gcc/bin/gcc-4.2 clean test all')) 'alternate profile compiler builds rbuild'
Assert-Match $alternateRbuild ([regex]::Escape('/opt/gcc/bin/gcc-4.2 -O -bsd -DCMU -DLOCALARCHITECTURE -DNeXT=1')) 'alternate profile compiler builds config with project flags'
Assert-Match $alternateRbuild ([regex]::Escape('/opt/gcc/bin/gcc-4.2 -O -bsd -DNeXT=1 -I/build/tools/mig-build/include -I/build/src/Commands/bootstrap_cmds/migcom.tproj -I/build/tools/mig-build/migcom -o /build/tools/libexec/migcom')) 'alternate profile compiler builds MIG with historical platform flags'
Assert-Match $alternateRbuild ([regex]::Escape('/opt/gcc/bin/gcc-4.2 -O -o /build/tools/bin/decomment /build/src/Commands/bootstrap_cmds/decomment.tproj/decomment.c')) 'alternate profile compiler builds private decomment'
Assert-Match $alternateRbuild ([regex]::Escape('MIGCC=/opt/gcc/bin/gcc-4.2 MIGARCH=mips_safe MIGCOM_DIR=/build/tools/libexec')) 'alternate GCC profile selects its own safe MIG architecture'
Assert-NotMatch $alternateRbuild ([regex]::Escape('/usr/bin/make CC=/usr/bin/cc')) 'alternate profile does not use default build tools'
$spacedCompilerArgs = $phaseArgs.Clone()
$spacedCompilerArgs.BuildCc = '/opt/gcc tools/bin/gcc'
$spacedCompilerRbuild = New-RhapBuildPhaseCommand -Phase 'rbuild' @spacedCompilerArgs
Assert-Match $spacedCompilerRbuild ([regex]::Escape("'/opt/gcc tools/bin/gcc' -O -bsd -DNeXT=1 -I/build/tools/mig-build/include -I/build/src/Commands/bootstrap_cmds/migcom.tproj")) 'space-containing configured GCC builds private MIG as one executable path'
Assert-Match $spacedCompilerRbuild ([regex]::Escape("'/opt/gcc tools/bin/gcc' -O -o /build/tools/bin/decomment /build/src/Commands/bootstrap_cmds/decomment.tproj/decomment.c")) 'space-containing configured GCC builds private decomment as one executable path'
$metacharRootArgs = $phaseArgs.Clone()
$metacharRootArgs.BootstrapRoot = '/build/root[1].*'
$metacharRootRbuild = New-RhapBuildPhaseCommand -Phase 'rbuild' @metacharRootArgs
Assert-Match $metacharRootRbuild ([regex]::Escape("/usr/bin/grep -F -e '/usr/include/mach/' -e '/build/root[1].*'/")) 'MIG dependency audit treats metacharacter sysroot as a literal path'
Assert-Match $metacharRootRbuild ([regex]::Escape("else mig_dependency_status=`$?; test `$mig_dependency_status -eq 1 || { echo 'build-src: private MIG dependency audit failed: migcom'")) 'MIG dependency audit distinguishes grep errors from no matches'

$bootstrapCommand = New-RhapBuildPhaseCommand -Phase 'bootstrap' @phaseArgs
$alternateToolBootstrap = New-RhapBuildPhaseCommand -Phase 'bootstrap' @alternatePhaseArgs
$spacedCompilerBootstrap = New-RhapBuildPhaseCommand -Phase 'bootstrap' @spacedCompilerArgs
Assert-Match $bootstrapCommand ([regex]::Escape('/usr/bin/install -d /build/bootstrap-root /build/repo /build/state')) 'bootstrap creates owned output directories'
Assert-Match $bootstrapCommand ([regex]::Escape('CONFIG_DIR=/build/tools/bin DECOMMENT=/build/tools/bin/decomment MIGCC=/usr/bin/cc')) 'bootstrap scopes private config and decomment tools'
Assert-Match $bootstrapCommand ([regex]::Escape('CONFIG_DIR=/build/tools/bin DECOMMENT=/build/tools/bin/decomment MIGCC=/usr/bin/cc MIGARCH=ppc MIGCOM_DIR=/build/tools/libexec /build/tools/bin/rbuild bootstrap')) 'bootstrap explicitly binds private decomment, MIG compiler, architecture, and libexec tools'
Assert-Match $alternateToolBootstrap ([regex]::Escape('MIGCC=/opt/gcc/bin/gcc-4.2 MIGARCH=mips_safe MIGCOM_DIR=/build/tools/libexec')) 'bootstrap binds alternate configured GCC and architecture to private MIG'
Assert-Match $spacedCompilerBootstrap ([regex]::Escape("MIGCC='/opt/gcc tools/bin/gcc' MIGARCH=ppc MIGCOM_DIR=/build/tools/libexec")) 'bootstrap quotes space-containing configured GCC for MIG wrapper'
Assert-NotMatch $bootstrapCommand '/usr/bin/mig|/usr/libexec/migcom|NEXT_ROOT|bootstrap-root/usr/libexec' 'bootstrap never selects live or sysroot MIG'
Assert-Equal ($bootstrapCommand.IndexOf('/usr/bin/install -d') -lt $bootstrapCommand.IndexOf('/build/tools/bin/rbuild bootstrap')) $true 'bootstrap creates outputs before rbuild'
Assert-Match $bootstrapCommand ([regex]::Escape('&& cd /build/src && CONFIG_DIR=/build/tools/bin')) 'bootstrap starts from synced source root'
Assert-Match $bootstrapCommand ([regex]::Escape('/build/tools/bin/rbuild bootstrap --sysroot /build/bootstrap-root --toolchain /build/src/rbuild-1/toolchains/gcc-darwin.conf --state /build/state /build/src/BootstrapManifest /build/repo /build/repo')) 'bootstrap uses resumable CLI'
$alternateSourceArgs = $phaseArgs.Clone()
$alternateSourceArgs.SourceRoot = '/srv/synced source'
$alternateBootstrap = New-RhapBuildPhaseCommand -Phase 'bootstrap' @alternateSourceArgs
Assert-Match $alternateBootstrap ([regex]::Escape("cd '/srv/synced source' && CONFIG_DIR=/build/tools/bin")) 'bootstrap quotes and uses alternate source cwd'
Assert-Match $alternateBootstrap ([regex]::Escape("'/srv/synced source'/BootstrapManifest")) 'bootstrap manifest follows alternate source root'
Assert-NotMatch $alternateBootstrap '/var/root|cd +~' 'bootstrap never inherits login cwd'
$spacedPhaseArgs = $phaseArgs.Clone()
$spacedPhaseArgs.SourceRoot = '/srv/build tree/src'
$spacedPhaseArgs.ToolsDir = '/srv/build tree/tools'
$spacedPhaseArgs.BootstrapRoot = '/srv/build tree/bootstrap root'
$spacedPhaseArgs.RepoDir = '/srv/build tree/repo'
$spacedPhaseArgs.BuiltDir = '/srv/build tree/built output'
$spacedPhaseArgs.StateDir = '/srv/build tree/state'
$spacedPhaseArgs.Profile = '/srv/build tree/profile.conf'
$spacedRbuild = New-RhapBuildPhaseCommand -Phase 'rbuild' @spacedPhaseArgs
Assert-Match $spacedRbuild ([regex]::Escape("rm -rf '/srv/build tree/tools'/config-build")) 'config safely quotes alternate private build directory'
Assert-Match $spacedRbuild ([regex]::Escape("'/srv/build tree/tools'/bin/decomment '/srv/build tree/tools'/decomment-build/input.h r > '/srv/build tree/tools'/decomment-build/output.h")) 'decomment smoke safely quotes alternate private tool paths'
Assert-Match $spacedRbuild ([regex]::Escape("-I'/srv/build tree/src'/Commands/bootstrap_cmds/config.tproj -I'/srv/build tree/tools'/config-build -o '/srv/build tree/tools'/bin/config")) 'config safely quotes alternate source and tools paths'
Assert-Match $spacedRbuild ([regex]::Escape("rm -rf '/srv/build tree/tools'/mig-build")) 'MIG safely quotes alternate private build root'
Assert-Match $spacedRbuild ([regex]::Escape("-O -bsd -DNeXT=1 -I'/srv/build tree/tools'/mig-build/include -I'/srv/build tree/src'/Commands/bootstrap_cmds/migcom_typd.tproj -I'/srv/build tree/tools'/mig-build/migcom_typd -o '/srv/build tree/tools'/libexec/migcom_typd")) 'MIG preserves platform flags and safely quotes alternate paths'
Assert-Match $spacedRbuild ([regex]::Escape("CONFIG_DIR='/srv/build tree/tools'/bin MIGCC=/usr/bin/cc MIGARCH=ppc MIGCOM_DIR='/srv/build tree/tools'/libexec '/srv/build tree/tools'/bin/mig -typed -I'/srv/build tree/src'/kernel-7 -DKERNEL -DKERNEL_SERVER -header /dev/null -user /dev/null -server mach_server.c '/srv/build tree/src'/kernel-7/mach/mach.defs")) 'typed MIG smoke generation safely quotes alternate source and private tool paths'
$spacedBootstrap = New-RhapBuildPhaseCommand -Phase 'bootstrap' @spacedPhaseArgs
Assert-Match $spacedBootstrap ([regex]::Escape("/usr/bin/install -d '/srv/build tree/bootstrap root' '/srv/build tree/repo' '/srv/build tree/state'")) 'bootstrap safely quotes owned outputs'
Assert-Match $spacedBootstrap ([regex]::Escape("CONFIG_DIR='/srv/build tree/tools'/bin DECOMMENT='/srv/build tree/tools'/bin/decomment MIGCC=/usr/bin/cc")) 'bootstrap safely quotes private config and decomment tools'
Assert-Match $spacedBootstrap ([regex]::Escape("MIGCC=/usr/bin/cc MIGARCH=ppc MIGCOM_DIR='/srv/build tree/tools'/libexec '/srv/build tree/tools'/bin/rbuild bootstrap")) 'bootstrap safely quotes private MIG bindings and profile architecture'
Assert-Match $spacedBootstrap ([regex]::Escape("DECOMMENT='/srv/build tree/tools'/bin/decomment MIGCC=/usr/bin/cc")) 'bootstrap safely quotes private decomment binding'
$kernelCommand = New-RhapBuildPhaseCommand -Phase 'kernel-drivers' @phaseArgs -DriverProjects @('drivers-ppc/storage/drvExample') -MakeDriverProjects @('drvBPF')
Assert-Match $kernelCommand ([regex]::Escape('test -d /build/repo')) 'kernel requires existing repository input'
Assert-Match $kernelCommand ([regex]::Escape('/usr/bin/install -d /build/built /build/state')) 'kernel creates owned output directories'
Assert-Equal ($kernelCommand.IndexOf('/usr/bin/install -d /build/built') -lt $kernelCommand.IndexOf('--dir driverkit-3')) $true 'kernel creates outputs before core packages'
Assert-Match $kernelCommand ([regex]::Escape('cd /build/src')) 'kernel package paths resolve beneath source root'
Assert-Match $kernelCommand ([regex]::Escape('/build/tools/bin/rbuild buildpackage --state /build/state --dir kernel-7 /build/repo /build/built')) 'kernel uses persistent state'
Assert-Match $kernelCommand ([regex]::Escape('--dir drivers-ppc/storage/drvExample /build/repo /build/built')) 'packaged driver uses rbuild'
Assert-Match $kernelCommand ([regex]::Escape('cd /build/src/drvBPF && PATH=/build/tools/bin:/usr/bin:/bin /usr/bin/make')) 'make-only driver uses configured make and path'
Assert-Match $kernelCommand ([regex]::Escape('CC=/usr/bin/cc')) 'make-only driver uses configured compiler'
Assert-Match $kernelCommand 'profile_cksum=.*cksum' 'make-only marker binds remote profile fingerprint'
Assert-Match $kernelCommand '/build/state/logs/drvBPF-all\.log' 'make-only driver has persistent log'
Assert-Match $kernelCommand '/build/state/drivers/drvBPF-all\.done' 'make-only driver has resume marker'
Assert-Match $kernelCommand 'mv .*\.done\.tmp\.\$\$ .*\.done' 'make-only marker is atomic'
Assert-Match $kernelCommand 'profile mismatch.*-Fresh' 'make-only stale profile is a hard error'
Assert-Equal ($kernelCommand.IndexOf('mkdir -p /build/state/logs') -lt $kernelCommand.IndexOf('set +e')) $true 'driver state directories are required setup'
Assert-Match $kernelCommand 'driver state write failed' 'make-only marker write failure is reported'
Assert-Match $kernelCommand 'core: driverkit-3, driverTools-1, kernel-7 \(required, all ok\)' 'kernel summary reports required core packages'
Assert-Match $kernelCommand 'drivers ok: \$rbuild_driver_passes' 'kernel summary reports optional successes'
Assert-Match $kernelCommand 'drivers fail: \$rbuild_driver_failures' 'kernel summary reports optional failures'
$worldCommand = New-RhapBuildPhaseCommand -Phase 'world' @phaseArgs
Assert-Match $worldCommand ([regex]::Escape('test -d /build/repo')) 'world requires existing repository input'
Assert-Match $worldCommand ([regex]::Escape('/usr/bin/install -d /build/built /build/state')) 'world creates owned output directories'
Assert-Equal ($worldCommand.IndexOf('/usr/bin/install -d /build/built') -lt $worldCommand.IndexOf('rbuild buildall')) $true 'world creates outputs before buildall'
Assert-Match $worldCommand ([regex]::Escape('cd /build/src && /build/tools/bin/rbuild buildall --state /build/state Manifest /build/repo /build/built')) 'world uses manifest and state'

foreach ($generated in @($rbuildCommand, $bootstrapCommand, $kernelCommand, $worldCommand)) {
    Assert-NotMatch $generated '/tmp/_|_seed-bootstrap-hdrs\.sh|DSTROOT=/|/usr/bin/rbuild|date-setting|header upload' 'generated command excludes obsolete workaround'
    Assert-NotMatch $generated '(?m)^\s*rm\s+-rf' 'phase command never deletes build output trees'
}

$freshCommand = New-RhapFreshCommand -RemoteRoot '/build' -SourceRoot '/build/src' -Profile '/build/src/rbuild-1/toolchains/gcc-darwin.conf' -ToolsDir '/build/tools' -BootstrapRoot '/build/bootstrap-root' -RepoDir '/build/repo' -BuiltDir '/build/built' -StateDir '/build/state'
Assert-Match $freshCommand ([regex]::Escape("rm -rf '/build/tools' '/build/bootstrap-root' '/build/repo' '/build/built' '/build/state'")) 'fresh removes exact configured outputs once'
Assert-Match $freshCommand ([regex]::Escape("mkdir -p '/build'")) 'fresh recreates only default output parent'
Assert-NotMatch $freshCommand ([regex]::Escape("mkdir -p '/build/tools")) 'fresh does not recreate output directories'
$freshRmLine = @($freshCommand -split "`n" | Where-Object { $_ -match '^rm -rf ' })[0]
Assert-NotMatch $freshRmLine '\*|\$[A-Za-z_]' 'fresh has no wildcard or variable deletion operands'
Assert-Equal ([regex]::Matches($freshCommand, '(?m)\brm\s').Count) 1 'fresh uses one removal command'
Assert-Match $freshCommand 'pwd -P' 'fresh validates physical boundaries'
Assert-Match $freshCommand 'test -L' 'fresh rejects symlink path components'
Assert-Match $freshCommand 'SOURCE_PHYS' 'fresh protects physical source root'
Assert-Match $freshCommand 'physical RemoteRoot may not be /' 'fresh rejects physical filesystem root'
Assert-Match $freshCommand 'SourceRoot escapes RemoteRoot' 'fresh requires physical source containment'
Assert-Match $freshCommand 'test -f "\$PROFILE"' 'fresh requires existing regular profile'
Assert-Match $freshCommand 'test ! -L "\$PROFILE"' 'fresh rejects final profile symlink'
Assert-Match $freshCommand 'PROFILE_PARENT_PHYS=.*pwd -P' 'fresh resolves profile parent physically'
Assert-Match $freshCommand 'profile.*overlaps Fresh output' 'fresh compares physical profile and outputs'
Assert-Equal ($freshCommand.IndexOf('check_target') -lt $freshCommand.IndexOf("rm -rf '/build/tools'")) $true 'fresh validates before deletion'
Assert-Equal ($freshCommand.IndexOf('PROFILE_PARENT_PHYS') -lt $freshCommand.IndexOf("rm -rf '/build/tools'")) $true 'fresh resolves physical profile before deletion'
$freshBase = @{ RemoteRoot='/build'; SourceRoot='/build/src'; Profile='/build/src/profile.conf'; ToolsDir='/build/tools'; BootstrapRoot='/build/root'; RepoDir='/build/repo'; BuiltDir='/build/built'; StateDir='/build/state' }
Assert-Throws { $p=$freshBase.Clone(); $p.ToolsDir='/build'; New-RhapFreshCommand @p } 'fresh rejects output equal to root'
Assert-Throws { $p=$freshBase.Clone(); $p.ToolsDir='/usr/tools'; New-RhapFreshCommand @p } 'fresh rejects output outside root'
Assert-Throws { $p=$freshBase.Clone(); $p.SourceRoot='/srv/src'; New-RhapFreshCommand @p } 'fresh rejects source outside root'
Assert-Throws { $p=$freshBase.Clone(); $p.ToolsDir='/build/src/tools'; New-RhapFreshCommand @p } 'fresh rejects output inside source'
Assert-Throws { $p=$freshBase.Clone(); $p.ToolsDir='/build/SRC'; New-RhapFreshCommand @p } 'fresh rejects case alias of source'
Assert-Throws { $p=$freshBase.Clone(); $p.ToolsDir='/build/output'; $p.BootstrapRoot='/build/OUTPUT'; New-RhapFreshCommand @p } 'fresh rejects case-insensitive duplicate roles'
Assert-Throws { $p=$freshBase.Clone(); $p.ToolsDir='/build/output'; $p.BootstrapRoot='/build/output/root'; New-RhapFreshCommand @p } 'fresh rejects nested roles'
Assert-Throws { $p=$freshBase.Clone(); $p.Profile='/build/tools/gcc.conf'; New-RhapFreshCommand @p } 'fresh rejects profile nested beneath output'
Assert-Throws { $p=$freshBase.Clone(); $p.Profile='/build/TOOLS'; New-RhapFreshCommand @p } 'fresh rejects profile case alias of output'
$outsideProfileFresh = New-RhapFreshCommand -RemoteRoot '/build' -SourceRoot '/build/src' -Profile '/opt/profiles/gcc.conf' -ToolsDir '/build/tools' -BootstrapRoot '/build/root' -RepoDir '/build/repo' -BuiltDir '/build/built' -StateDir '/build/state'
Assert-Match $outsideProfileFresh ([regex]::Escape("rm -rf '/build/tools'")) 'fresh accepts absolute profile outside outputs'
$caseFresh = New-RhapFreshCommand -RemoteRoot '/build' -SourceRoot '/build/src' -Profile '/build/src/profile.conf' -ToolsDir '/build/A/tools' -BootstrapRoot '/build/a/root' -RepoDir '/build/output/repo' -BuiltDir '/build/other/built' -StateDir '/build/state/run'
Assert-Match $caseFresh ([regex]::Escape("mkdir -p '/build/A' '/build/a' '/build/output' '/build/other' '/build/state'")) 'fresh deduplicates nested case-distinct parents ordinally'
Assert-NotMatch $caseFresh ([regex]::Escape("mkdir -p '/build/A/tools'")) 'fresh leaves nested outputs for their phases'

Assert-Equal (Assert-RhapFreshMode -All -Fresh) $true 'fresh accepts all mode'
Assert-Throws { Assert-RhapFreshMode -Rbuild -Fresh } 'fresh rejects granular rbuild mode'
Assert-Throws { Assert-RhapFreshMode -Bootstrap -Fresh } 'fresh rejects granular bootstrap mode'

$profileRead = New-RhapReadProfileCommand -Profile '/opt/profiles/gcc.conf'
Assert-Equal $profileRead "set -e; /bin/cat '/opt/profiles/gcc.conf'" 'absolute remote profile read command'
Assert-Throws { New-RhapReadProfileCommand -Profile "/opt/profile's.conf" } 'profile read rejects unsafe quote'

$orchestrationEvents = New-Object System.Collections.Generic.List[string]
$sequenceResult = Invoke-RhapBuildOrchestration -Phases @('rbuild', 'bootstrap', 'kernel-drivers', 'world') -PreflightBody 'preflight-body' -ProfileBody 'profile-body' -FreshBody 'fresh-body' -ParseProfile { param($text) "parsed:$text" } -PhaseFactory { param($phase, $profile) "$phase/$profile" } -ScriptInvoker { param($name, $body, $stream) $orchestrationEvents.Add("$name`:$stream"); return 0 } -CaptureInvoker { param($body) $orchestrationEvents.Add('profile'); return [pscustomobject]@{ ExitCode = 0; Stdout = 'remote'; Stderr = '' } }
Assert-Equal $sequenceResult $true 'orchestrator success'
Assert-Equal ($orchestrationEvents -join ',') 'preflight:False,profile,fresh output reset:False,rbuild:True,bootstrap:True,kernel-drivers:True,world:True' 'orchestrator preflight fresh and canonical order'
Assert-Equal @($orchestrationEvents | Where-Object { $_ -eq 'preflight:False' }).Count 1 'orchestrator runs preflight once'
$failureEvents = New-Object System.Collections.Generic.List[string]
Assert-Throws { Invoke-RhapBuildOrchestration -Phases @('rbuild', 'bootstrap', 'kernel-drivers', 'world') -PreflightBody 'p' -ProfileBody 'q' -ParseProfile { param($text) $text } -PhaseFactory { param($phase, $profile) $phase } -ScriptInvoker { param($name, $body, $stream) $failureEvents.Add($name); if ($name -eq 'bootstrap') { return 9 }; return 0 } -CaptureInvoker { param($body) return [pscustomobject]@{ ExitCode = 0; Stdout = 'remote'; Stderr = '' } } } 'orchestrator propagates required phase failure'
Assert-Equal ($failureEvents -join ',') 'preflight,rbuild,bootstrap' 'orchestrator stops at first required failure'

$profileValues = ConvertFrom-RhapToolchainProfileText -Text $realProfile
Assert-Equal $profileValues.build_cc '/usr/bin/cc' 'profile build compiler value'
Assert-Equal $profileValues.target_arch 'ppc' 'profile target architecture value'
Assert-Equal $profileValues.make '/usr/bin/make' 'profile make value'
Assert-Equal $profileValues.make_flags 'MAKEFILEDIR=@SYSROOT@/System/Developer/Makefiles/project MAKEFILEPATH=@SYSROOT@/System/Developer/Makefiles' 'profile bootstrap make flags'
Assert-Equal $profileValues.make_flags_ready '@SYSROOT@/System/Developer/Makefiles/project/platform.make' 'profile bootstrap make flags readiness path'
Assert-Equal $profileValues.ld_flags_ready '@SYSROOT@/System/Library/Frameworks/System.framework/Versions/B/System' 'profile bootstrap linker flags readiness path'
Assert-Equal $profileValues.archive_create '/bin/pax' 'profile archive creator value'
Assert-Equal $profileValues.archive_create_flags '-w -x ustar' 'profile archive creator flags'

Assert-Equal (Test-RhapToolchainProfileText -Text $realProfile) $true 'real toolchain profile contract'
Assert-Throws { Test-RhapToolchainProfileText -Text ($realProfile + "unknown_key=value`n") } 'reject unknown profile key'
Assert-Throws { Test-RhapToolchainProfileText -Text ($realProfile + "build_cc=/bin/false`n") } 'reject duplicate profile key'
Assert-Throws { Test-RhapToolchainProfileText -Text ($realProfile + "target_arch=i386`n") } 'reject duplicate target_arch profile key'
Assert-Throws { Test-RhapToolchainProfileText -Text ($realProfile -replace '(?m)^ld_flags=.*\r?\n?', '') } 'reject missing profile key'
Assert-Throws { Test-RhapToolchainProfileText -Text ($realProfile -replace '(?m)^target_arch=.*\r?\n?', '') } 'reject missing target_arch profile key'
Assert-Throws { Test-RhapToolchainProfileText -Text ($realProfile -replace '(?m)^archive_create=.*\r?\n?', '') } 'reject missing archive creator profile key'
Assert-Throws { Test-RhapToolchainProfileText -Text ($realProfile -replace '(?m)^archive_create_flags=.*\r?\n?', '') } 'reject missing archive creator flags profile key'
Assert-Equal (Test-RhapToolchainProfileText -Text ($realProfile -replace '(?m)^make_flags(?:_ready)?=.*\r?\n?', '')) $true 'accept profile without bootstrap make flags'
Assert-Throws { Test-RhapToolchainProfileText -Text ($realProfile -replace '(?m)^make_flags=.*$', 'make_flags=') } 'reject empty bootstrap make flags'
Assert-Throws { Test-RhapToolchainProfileText -Text ($realProfile -replace '(?m)^make_flags=.*$', 'make_flags=   ') } 'reject whitespace bootstrap make flags'
Assert-Equal (Test-RhapToolchainProfileText -Text ($realProfile -replace '(?m)^make_flags_ready=.*\r?\n?', '')) $true 'accept bootstrap make flags without readiness gate'
Assert-Equal (Test-RhapToolchainProfileText -Text ($realProfile -replace '(?m)^ld_flags_ready=.*\r?\n?', '')) $true 'accept bootstrap linker flags without readiness gate'
Assert-Equal (Test-RhapToolchainProfileText -Text ($realProfile -replace '(?m)^make_flags(?:_ready)?=.*\r?\n?', '')) $true 'accept profile omitting bootstrap make flags and gate'
Assert-Throws { Test-RhapToolchainProfileText -Text ($realProfile -replace '(?m)^make_flags=.*\r?\n?', '') } 'reject readiness gate without bootstrap make flags'
Assert-Throws { Test-RhapToolchainProfileText -Text ($realProfile -replace '(?m)^make_flags_ready=.*$', 'make_flags_ready=') } 'reject empty bootstrap make flags readiness gate'
Assert-Throws { Test-RhapToolchainProfileText -Text ($realProfile -replace '(?m)^make_flags_ready=.*$', 'make_flags_ready=   ') } 'reject whitespace bootstrap make flags readiness gate'
Assert-Throws { Test-RhapToolchainProfileText -Text ($realProfile -replace '(?m)^ld_flags_ready=.*$', 'ld_flags_ready=') } 'reject empty bootstrap linker flags readiness gate'
Assert-Throws { Test-RhapToolchainProfileText -Text ($realProfile -replace '(?m)^ld_flags_ready=.*$', 'ld_flags_ready=   ') } 'reject whitespace bootstrap linker flags readiness gate'
Assert-Throws { Test-RhapToolchainProfileText -Text ($realProfile + "tar_create_flags=--posix`n") } 'reject legacy tar-specific creation flags key'
Assert-Throws { Test-RhapToolchainProfileText -Text ($realProfile -replace '(?m)^target_arch=.*$', 'target_arch=ppc;touch_bad') } 'reject unsafe target_arch profile value'
Assert-Throws { Test-RhapToolchainProfileText -Text ($realProfile -replace '(?m)^profile=', 'profile ') } 'reject malformed profile line'
Assert-Equal (Assert-RhapSafeIdentifier -Value 'mips_safe' -Name 'target_arch') 'mips_safe' 'accept alternate safe architecture identifier'
Assert-Throws { Assert-RhapSafeIdentifier -Value '9ppc' -Name 'target_arch' } 'reject digit-leading architecture identifier'
Assert-Throws { Assert-RhapSafeIdentifier -Value 'ppc;touch_bad' -Name 'target_arch' } 'reject architecture injection'
Assert-Throws { $p=$phaseArgs.Clone(); $p.TargetArch='ppc other'; New-RhapBuildPhaseCommand -Phase 'rbuild' @p } 'phase rejects unsafe target architecture'
Assert-Equal (Assert-RhapSafeArchFlags -Value '-arch ppc -mcpu=G4') '-arch ppc -mcpu=G4' 'accept gcc-style flag operands'
Assert-Throws { Assert-RhapSafeArchFlags -Value '-arch *' } 'reject glob star in arch flags'
Assert-Throws { Assert-RhapSafeArchFlags -Value '-arch ppc?' } 'reject glob question in arch flags'
Assert-Throws { Assert-RhapSafeArchFlags -Value '-I[abc]' } 'reject glob bracket in arch flags'
Assert-Equal (Test-RhapMachOFileOutput -Text '/tmp/probe.o: Mach-O object ppc' -TargetArch ppc) $true 'accept profile Mach-O object description'
Assert-Equal (Test-RhapMachOFileOutput -Text '/tmp/probe.o: Mach-O object mips_safe' -TargetArch mips_safe) $true 'accept alternate profile Mach-O object description'
Assert-Throws { Test-RhapMachOFileOutput -Text '/tmp/probe.o: Mach-O object i386' -TargetArch ppc } 'reject wrong object architecture'
Assert-Throws { Test-RhapMachOFileOutput -Text '/tmp/probe.o: Mach-O object ppc64' -TargetArch ppc } 'reject PPC architecture prefix collision'
Assert-Throws { Test-RhapMachOFileOutput -Text '/tmp/probe.o: Mach-O object i386foo' -TargetArch i386 } 'reject i386 architecture prefix collision'
Assert-Throws { Test-RhapMachOFileOutput -Text '/tmp/probe.o: ELF 32-bit MSB relocatable, PowerPC' -TargetArch ppc } 'reject non-Mach-O object'

Assert-Equal (Assert-RhapSafeRemoteOutputPath -RemoteRoot '/build' -Path '/build/repo') '/build/repo' 'accept descendant'
Assert-Equal (Assert-RhapSafeRemoteOutputPath -RemoteRoot '//build//' -Path '//build///state//') '/build/state' 'normalize slashes'

foreach ($case in @(
    @('', '/build/repo', 'empty root'),
    @('/build', '', 'empty path'),
    @('build', '/build/repo', 'relative root'),
    @('/build', 'build/repo', 'relative path'),
    @('/build', '/build', 'equal root'),
    @('/build', '/', 'filesystem root'),
    @('/build', '/usr', 'outside root'),
    @('/build', '/buildish/repo', 'prefix lookalike'),
    @('/build', '/build/./repo', 'dot component'),
    @('/build', '/build/repo/../state', 'dotdot component'),
    @('/build/.', '/build/repo', 'dot root component'),
    @('/build', "/build/repo`nrm", 'newline'),
    @('/build', '/build/repo\state', 'backslash'),
    @('/build', '/build/repo;rm', 'shell metacharacter'),
    @('/', '/build/repo', 'unsafe broad root')
)) {
    $root = $case[0]
    $path = $case[1]
    $name = $case[2]
    Assert-Throws { Assert-RhapSafeRemoteOutputPath -RemoteRoot $root -Path $path } "reject $name"
}

Assert-Equal ((Get-RhapBuildPhases -All) -join ',') 'rbuild,bootstrap,kernel-drivers,world' 'all phase order'
Assert-Equal ((Get-RhapBuildPhases -Rbuild) -join ',') 'rbuild' 'rbuild phase'
Assert-Equal ((Get-RhapBuildPhases -Bootstrap) -join ',') 'bootstrap' 'bootstrap phase'
Assert-Equal ((Get-RhapBuildPhases -KernelDrivers) -join ',') 'kernel-drivers' 'kernel phase'
Assert-Equal ((Get-RhapBuildPhases -World) -join ',') 'world' 'world phase'
Assert-Throws { Get-RhapBuildPhases } 'reject no phase'
Assert-Throws { Get-RhapBuildPhases -All -World } 'reject all plus phase'
Assert-Throws { Get-RhapBuildPhases -Rbuild -Bootstrap } 'reject two phases'

$cmd = New-RhapPreflightCommand -SourceRoot '/build/src' -ToolsDir '/build/tools' -BootstrapRoot '/build/bootstrap-root' -StateDir '/build/state' -Profile '/build/src/rbuild-1/toolchains/gcc-darwin.conf'
$profileValidatorStart = $cmd.IndexOf("awk 'BEGIN {")
$profileValidatorEndMarker = ' || fail "invalid toolchain profile"'
$profileValidatorEnd = $cmd.IndexOf($profileValidatorEndMarker, $profileValidatorStart)
Assert-Equal ($profileValidatorStart -ge 0) $true 'generated preflight contains profile validator'
Assert-Equal ($profileValidatorEnd -gt $profileValidatorStart) $true 'generated preflight profile validator has a failure boundary'
$profileValidator = $cmd.Substring($profileValidatorStart, $profileValidatorEnd - $profileValidatorStart)
function Test-GeneratedProfileValidatorContract([string]$Validator, [string]$ProfileText) {
    $allowed = @{}
    $required = @{}
    foreach ($match in [regex]::Matches($Validator, 'allowed\["([A-Za-z0-9_]+)"\] = 1')) {
        $allowed[$match.Groups[1].Value] = $true
    }
    foreach ($match in [regex]::Matches($Validator, 'required\["([A-Za-z0-9_]+)"\] = 1')) {
        $required[$match.Groups[1].Value] = $true
    }
    $paired = @{}
    foreach ($match in [regex]::Matches($Validator, 'paired\["([A-Za-z0-9_]+)"\] = "([A-Za-z0-9_]+)"')) {
        $paired[$match.Groups[1].Value] = $match.Groups[2].Value
    }
    $seen = @{}
    foreach ($rawLine in ($ProfileText -split "`r?`n")) {
        $line = $rawLine.Trim()
        if ($line -eq '' -or $line.StartsWith('#')) { continue }
        $equals = $line.IndexOf('=')
        if ($equals -lt 1) { return $false }
        $key = $line.Substring(0, $equals).Trim()
        $value = $line.Substring($equals + 1).Trim()
        if (-not $allowed.ContainsKey($key) -or $seen.ContainsKey($key) -or $value -eq '') { return $false }
        $seen[$key] = $true
    }
    foreach ($key in $required.Keys) {
        if (-not $seen.ContainsKey($key)) { return $false }
    }
    foreach ($key in $paired.Keys) {
        if ($seen.ContainsKey($key) -and -not $seen.ContainsKey($paired[$key])) { return $false }
    }
    return $true
}
Assert-Equal (Test-GeneratedProfileValidatorContract -Validator $profileValidator -ProfileText $realProfile) $true 'generated preflight accepts canonical profile with optional make flags'
Assert-Equal (Test-GeneratedProfileValidatorContract -Validator $profileValidator -ProfileText ($realProfile -replace '(?m)^make_flags(?:_ready)?=.*\r?\n?', '')) $true 'generated preflight accepts profile omitting optional make flags'
Assert-Equal (Test-GeneratedProfileValidatorContract -Validator $profileValidator -ProfileText ($realProfile -replace '(?m)^make_flags=.*$', 'make_flags=')) $false 'generated preflight rejects empty optional make flags'
Assert-Equal (Test-GeneratedProfileValidatorContract -Validator $profileValidator -ProfileText ($realProfile -replace '(?m)^make_flags=.*$', 'make_flags=   ')) $false 'generated preflight rejects whitespace optional make flags'
Assert-Equal (Test-GeneratedProfileValidatorContract -Validator $profileValidator -ProfileText ($realProfile -replace '(?m)^make_flags_ready=.*\r?\n?', '')) $true 'generated preflight accepts bootstrap make flags without readiness gate'
Assert-Equal (Test-GeneratedProfileValidatorContract -Validator $profileValidator -ProfileText ($realProfile -replace '(?m)^ld_flags_ready=.*\r?\n?', '')) $true 'generated preflight accepts bootstrap linker flags without readiness gate'
Assert-Equal (Test-GeneratedProfileValidatorContract -Validator $profileValidator -ProfileText ($realProfile -replace '(?m)^make_flags(?:_ready)?=.*\r?\n?', '')) $true 'generated preflight accepts omitted bootstrap make flags pair'
Assert-Equal (Test-GeneratedProfileValidatorContract -Validator $profileValidator -ProfileText ($realProfile -replace '(?m)^make_flags=.*\r?\n?', '')) $false 'generated preflight rejects readiness gate without bootstrap make flags'
Assert-Equal (Test-GeneratedProfileValidatorContract -Validator $profileValidator -ProfileText ($realProfile -replace '(?m)^make_flags_ready=.*$', 'make_flags_ready=')) $false 'generated preflight rejects empty readiness gate'
Assert-Equal (Test-GeneratedProfileValidatorContract -Validator $profileValidator -ProfileText ($realProfile -replace '(?m)^make_flags_ready=.*$', 'make_flags_ready=   ')) $false 'generated preflight rejects whitespace readiness gate'
Assert-Equal (Test-GeneratedProfileValidatorContract -Validator $profileValidator -ProfileText ($realProfile -replace '(?m)^ld_flags_ready=.*$', 'ld_flags_ready=')) $false 'generated preflight rejects empty linker readiness gate'
Assert-Equal (Test-GeneratedProfileValidatorContract -Validator $profileValidator -ProfileText ($realProfile -replace '(?m)^ld_flags_ready=.*$', 'ld_flags_ready=   ')) $false 'generated preflight rejects whitespace linker readiness gate'
Assert-Equal (Test-GeneratedProfileValidatorContract -Validator $profileValidator -ProfileText ($realProfile + "unknown_key=value`n")) $false 'generated preflight rejects unknown profile key'
Assert-Match $cmd '^set -e' 'literal POSIX script body'
Assert-Match $cmd 'test -f ' 'profile existence check'
Assert-Match $cmd 'test -d "\$SOURCE_ROOT"' 'source root directory check'
Assert-Match $cmd '"\$SOURCE_ROOT/BootstrapManifest"' 'bootstrap manifest source check'
Assert-Match $cmd '"\$SOURCE_ROOT/rbuild-1/Makefile"' 'rbuild source check'
Assert-Match $cmd '"\$SOURCE_ROOT/rbuild-1/toolchain\.c"' 'rbuild toolchain source check'
Assert-Match $cmd 'gcc-darwin\.conf' 'configured profile path'
Assert-Match $cmd 'test -x /usr/bin/cc' 'developer compiler check'
Assert-Match $cmd '/usr/bin/cc -arch ppc -c' 'target compiler evidence'
Assert-Match $cmd 'case-sensitive filesystem required' 'case sensitivity error'
Assert-Match $cmd 'BUILD_CC' 'build compiler parsed'
Assert-Match $cmd 'TARGET_CC' 'target compiler parsed'
Assert-Match $cmd 'TARGET_ARCH' 'target architecture parsed'
Assert-Match $cmd 'ARCH_FLAGS' 'architecture flags parsed'
Assert-NotMatch $cmd ([regex]::Escape('case "$rbuild_flag" in -*')) 'arch flag operands such as ppc are accepted'
Assert-Match $cmd 'set -f' 'disable pathname expansion before flags split'
Assert-Match $cmd 'unsafe arch_flags' 'reject unsafe raw architecture flags'
Assert-Match $cmd 'gzip' 'gzip requirement'
Assert-Match $cmd 'tar' 'tar requirement'
Assert-Match $cmd 'ARCHIVE_CREATE_TOOL=\$\(profile_value archive_create\)' 'archive creator parsed for preflight'
Assert-Match $cmd '"\$ARCHIVE_CREATE_TOOL"' 'archive creator included in executable preflight'
Assert-Match $cmd 'rsync' 'rsync requirement'
Assert-Match $cmd 'make' 'make requirement'
Assert-Match $cmd 'ln' 'ln requirement'
Assert-Match $cmd 'test -x /usr/bin/yacc' 'kernel config yacc requirement'
Assert-Match $cmd 'test -x /usr/bin/lex' 'kernel config lex requirement'
Assert-Match $cmd 'config\.tproj/parser\.y' 'kernel config parser source requirement'
Assert-Match $cmd 'config\.tproj/lexer\.l' 'kernel config lexer source requirement'
Assert-Match $cmd 'config\.tproj/config\.h' 'kernel config header source requirement'
Assert-Match $cmd 'migcom\.tproj' 'classic MIG source project requirement'
Assert-Match $cmd 'migcom_typd\.tproj' 'typed MIG source project requirement'
Assert-Match $cmd 'migcom_untypd\.tproj' 'untyped MIG source project requirement'
Assert-Match $cmd 'mig\.sh' 'MIG wrapper source requirement'
Assert-Match $cmd 'handler\.c' 'classic MIG unique source requirement'
Assert-Match $cmd 'migcom\.c' 'typed MIG unique source requirement'
Assert-Match $cmd 'test\.c' 'untyped MIG unique source requirement'
Assert-Match $cmd 'migcom_untypd_vers_stub\.c' 'untyped MIG version source requirement'
Assert-Match $cmd ([regex]::Escape('test -f "$SOURCE_ROOT/Commands/bootstrap_cmds/decomment.tproj/decomment.c" || fail "decomment source missing"')) 'preflight requires source-owned decomment implementation'
Assert-Match $cmd ([regex]::Escape('test -f "$SOURCE_ROOT/kernel-7/mach/mach.defs" || fail "MIG wrapper smoke definition missing"')) 'MIG smoke definition source requirement'
Assert-Match $cmd 'kernel-7/\$mig_header' 'MIG overlay preflight checks source-owned headers'
Assert-Match $cmd 'mach/message\.h.*mach/ppc/simple_lock\.h' 'MIG overlay preflight declares the verified header closure'
Assert-Match $cmd 'test -x /bin/mv' 'MIG generated header rename tool requirement'
Assert-Match $cmd 'TOOLS_DIR=' 'preflight binds configured private tools directory'
Assert-Match $cmd 'TOOL_PATH=\$\(profile_value path\)' 'preflight reads configured build PATH'
Assert-Match $cmd 'profile PATH must select private MIG wrapper first' 'preflight requires private MIG wrapper PATH priority'
Assert-Match $cmd '/usr/bin/tee' 'driver log streaming requirement'
Assert-Match $cmd '/usr/bin/cksum' 'driver state fingerprint requirement'
Assert-Match $cmd '/usr/bin/sed' 'driver state parser requirement'
Assert-Match $cmd 'test -f "\$tool".*test -x "\$tool"' 'configured executables must be files'
Assert-Match $cmd 'df -k' 'free space check'
Assert-Match $cmd ([regex]::Escape("awk '{ fields=NF; available=`$4 } END")) 'free space awk consumes vintage df records'
Assert-Match $cmd ([regex]::Escape("awk -v wanted=`"`$1`" 'BEGIN")) 'profile awk is protected from shell expansion'
Assert-Match $cmd 'trap' 'probe cleanup trap'
Assert-Match $cmd 'PROBE_PARENT=\$\(nearest_parent "\$BOOTSTRAP_ROOT"\)' 'case probe uses planned filesystem'
Assert-Match $cmd '/usr/bin/file "\$PROBE/target\.o"' 'target object architecture inspection'
Assert-Match $cmd 'Mach-O object \$TARGET_ARCH' 'target object profile architecture Mach-O requirement'
Assert-Match $cmd ([regex]::Escape('*"Mach-O object $TARGET_ARCH"|*"Mach-O object $TARGET_ARCH "*|*"Mach-O object $TARGET_ARCH,"*')) 'generated target object check requires an exact architecture token boundary'
Assert-NotMatch $cmd ([regex]::Escape('*"Mach-O object $TARGET_ARCH"*')) 'generated target object check rejects arbitrary architecture suffixes'
$machOBoundaryCommand = New-RhapMachOValidationCommand
$boundarySh = (Get-Command sh.exe -ErrorAction Stop).Source
$boundaryScript = Join-Path $env:TEMP ("rhap-macho-boundary-{0}.sh" -f [guid]::NewGuid().ToString('n'))
$boundaryScriptSh = ([System.IO.Path]::GetFullPath($boundaryScript) -replace '\\', '/')
if ($boundaryScriptSh -match '^([A-Za-z]):') { $boundaryScriptSh = '/' + $Matches[1].ToLowerInvariant() + $boundaryScriptSh.Substring(2) }
Set-Content -LiteralPath $boundaryScript -Encoding ASCII -NoNewline -Value ((@"
#!/bin/sh
fail() { exit 1; }
TARGET_FILE=`$1
TARGET_ARCH=`$2
$machOBoundaryCommand
"@) -replace "`r`n", "`n")
function Test-GeneratedMachOBoundary([string]$Text, [string]$Arch) {
    & $boundarySh $boundaryScriptSh $Text $Arch 2>$null
    return $LASTEXITCODE
}
try {
    Assert-Equal (Test-GeneratedMachOBoundary -Text '/tmp/probe.o: Mach-O object ppc' -Arch ppc) 0 'generated object check accepts exact PPC token at end'
    Assert-Equal (Test-GeneratedMachOBoundary -Text '/tmp/probe.o: Mach-O object ppc, flags' -Arch ppc) 0 'generated object check accepts comma-delimited PPC token'
    Assert-Equal (Test-GeneratedMachOBoundary -Text '/tmp/probe.o: Mach-O object i386 flags' -Arch i386) 0 'generated object check accepts space-delimited i386 token'
    Assert-Equal (Test-GeneratedMachOBoundary -Text '/tmp/probe.o: Mach-O object ppc64' -Arch ppc) 1 'generated object check rejects PPC prefix collision'
    Assert-Equal (Test-GeneratedMachOBoundary -Text '/tmp/probe.o: Mach-O object i386foo' -Arch i386) 1 'generated object check rejects i386 prefix collision'
} finally {
    Remove-Item -LiteralPath $boundaryScript -Force -ErrorAction SilentlyContinue
}

$decommentContractDir = Join-Path $env:TEMP ("rhap-decomment-contract-{0}" -f [guid]::NewGuid().ToString('n'))
New-Item -ItemType Directory -Path $decommentContractDir | Out-Null
try {
    $fallbackScript = Join-Path $decommentContractDir 'fallback.sh'
    $fakeUnifdef = Join-Path $decommentContractDir 'unifdef'
    $failingUnifdef = Join-Path $decommentContractDir 'unifdef-fail'
    $fakeDecomment = Join-Path $decommentContractDir 'decomment'
    $failingDecomment = Join-Path $decommentContractDir 'decomment-fail'
    $inputHeader = Join-Path $decommentContractDir 'input.h'
    $installMarker = Join-Path $decommentContractDir 'installed'
    $fallbackBody = @'
#!/bin/sh
UNIFDEF=$1
DECOMMENT=$2
INPUT=$3
OUT=$4
INSTALL=$5
(
    RAW="$OUT.raw"
    "$UNIFDEF" -UKERNEL_PRIVATE -UDRIVER_PRIVATE "$INPUT" > "$RAW"
    unifdef_status=$?
    if test "$unifdef_status" -eq 1; then
        "$DECOMMENT" "$RAW" r > "$OUT" || exit 1
    elif test "$unifdef_status" -ne 0; then
        exit 1
    fi
    test -s "$OUT" || exit 1
    : > "$INSTALL"
) || exit 1
'@
    $unifdefBody = @'
#!/bin/sh
input=
for arg do input=$arg; done
/bin/cat "$input"
exit 1
'@
    $failingUnifdefBody = @'
#!/bin/sh
input=
for arg do input=$arg; done
/bin/cat "$input"
exit 2
'@
    $decommentBody = @'
#!/bin/sh
if test -s "$1"; then /bin/cat "$1"; else printf '%s\n' 'int synthesized_header;'; fi
'@
    $failingBody = @'
#!/bin/sh
exit 7
'@
    Set-Content -LiteralPath $fallbackScript -Encoding ASCII -NoNewline -Value ($fallbackBody -replace "`r`n", "`n")
    Set-Content -LiteralPath $fakeUnifdef -Encoding ASCII -NoNewline -Value ($unifdefBody -replace "`r`n", "`n")
    Set-Content -LiteralPath $failingUnifdef -Encoding ASCII -NoNewline -Value ($failingUnifdefBody -replace "`r`n", "`n")
    Set-Content -LiteralPath $fakeDecomment -Encoding ASCII -NoNewline -Value ($decommentBody -replace "`r`n", "`n")
    Set-Content -LiteralPath $failingDecomment -Encoding ASCII -NoNewline -Value ($failingBody -replace "`r`n", "`n")
    Set-Content -LiteralPath $inputHeader -Encoding ASCII -Value 'int exported_header;'
    function ConvertTo-DecommentTestShPath([string]$Path) {
        $converted = ([System.IO.Path]::GetFullPath($Path) -replace '\\', '/')
        if ($converted -match '^([A-Za-z]):') { return '/' + $Matches[1].ToLowerInvariant() + $converted.Substring(2) }
        return $converted
    }
    $contractSh = ConvertTo-DecommentTestShPath $fallbackScript
    $unifdefSh = ConvertTo-DecommentTestShPath $fakeUnifdef
    $failingUnifdefSh = ConvertTo-DecommentTestShPath $failingUnifdef
    $decommentSh = ConvertTo-DecommentTestShPath $fakeDecomment
    $failingSh = ConvertTo-DecommentTestShPath $failingDecomment
    $inputSh = ConvertTo-DecommentTestShPath $inputHeader
    $outputSh = ConvertTo-DecommentTestShPath (Join-Path $decommentContractDir 'output.h')
    $installMarkerSh = ConvertTo-DecommentTestShPath $installMarker
    & $boundarySh $contractSh $unifdefSh $decommentSh $inputSh $outputSh $installMarkerSh
    Assert-Equal $LASTEXITCODE 0 'kernel export fallback accepts successful decomment output'
    Assert-Equal (Test-Path -LiteralPath $installMarker) $true 'kernel export fallback installs successful output'
    $savedErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'SilentlyContinue'
        Remove-Item -LiteralPath $installMarker -Force -ErrorAction SilentlyContinue
        & $boundarySh $contractSh $unifdefSh '/no/such/private/decomment' $inputSh $outputSh $installMarkerSh 2>$null
        $missingDecommentExit = $LASTEXITCODE
        & $boundarySh $contractSh $unifdefSh $failingSh $inputSh $outputSh $installMarkerSh 2>$null
        $failingDecommentExit = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $savedErrorActionPreference
    }
    Assert-Equal ($missingDecommentExit -ne 0) $true 'kernel export fallback rejects missing decomment tool'
    Assert-Equal ($failingDecommentExit -ne 0) $true 'kernel export fallback propagates decomment failure'
    Assert-Equal (Test-Path -LiteralPath $installMarker) $false 'failed decomment fallback cannot install a header'
    $savedErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'SilentlyContinue'
        & $boundarySh $contractSh $failingUnifdefSh $decommentSh $inputSh $outputSh $installMarkerSh 2>$null
        $unexpectedUnifdefExit = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $savedErrorActionPreference
    }
    Assert-Equal ($unexpectedUnifdefExit -ne 0) $true 'kernel export rejects unifdef status two even with partial output'
    Assert-Equal (Test-Path -LiteralPath $installMarker) $false 'unifdef status two cannot install a partial header'
    $savedErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'SilentlyContinue'
        & $boundarySh $contractSh '/no/such/private/unifdef' $decommentSh $inputSh $outputSh $installMarkerSh 2>$null
        $missingUnifdefExit = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $savedErrorActionPreference
    }
    Assert-Equal ($missingUnifdefExit -ne 0) $true 'kernel export rejects missing unifdef status 127'
    Assert-Equal (Test-Path -LiteralPath $installMarker) $false 'missing unifdef cannot install a synthesized header'

    $recipeScript = Join-Path $decommentContractDir 'export-recipe.sh'
    $mkdirOk = Join-Path $decommentContractDir 'mkdir-ok'
    $mkdirFail = Join-Path $decommentContractDir 'mkdir-fail'
    $installOk = Join-Path $decommentContractDir 'install-ok'
    $installFail = Join-Path $decommentContractDir 'install-fail'
    $pwdOk = Join-Path $decommentContractDir 'pwd-ok'
    $pwdFail = Join-Path $decommentContractDir 'pwd-fail'
    $spacedToolDir = Join-Path $decommentContractDir 'private tools'
    New-Item -ItemType Directory -Path $spacedToolDir | Out-Null
    $spacedDecomment = Join-Path $spacedToolDir 'decomment'
    $recipeBody = @'
#!/bin/sh
MKDIRS=$1
INSTALL=$2
DECOMMENT=$3
UNIFDEF=$4
INPUT=$5
ROOT=$6
ACCEPTED=$7
SENTINEL_MODE=$8
PWD_TOOL=$9
(
    object_dir=`"$PWD_TOOL" "$ROOT"` || exit 1
    EXPDIR="$object_dir/exports"
    DSTDIR="$object_dir/include"
    [ -d "$EXPDIR" ] || "$MKDIRS" "$EXPDIR" || exit 1
    rm -f "$EXPDIR"/* || exit 1
    [ -d "$DSTDIR" ] || "$MKDIRS" "$DSTDIR" || exit 1
    RAW="$EXPDIR/input.h"
    STRIP="$RAW.strip"
    if test "$SENTINEL_MODE" = fail; then /usr/bin/mkdir "$STRIP" || exit 1; fi
    echo garbage > "$STRIP" || exit 1
    "$UNIFDEF" "$INPUT" > "$RAW"
    unifdef_status=$?
    if test "$unifdef_status" -eq 1; then
        "$DECOMMENT" "$RAW" r > "$STRIP" || exit 1
    elif test "$unifdef_status" -ne 0; then
        exit 1
    fi
    if test -s "$STRIP"; then
        if ! "$INSTALL" "$RAW" "$DSTDIR/output.h"; then
            rm -f "$STRIP"
            exit 1
        fi
    fi
    rm -f "$STRIP" || exit 1
    : > "$ACCEPTED"
) || exit 1
'@
    $mkdirOkBody = @'
#!/bin/sh
/usr/bin/mkdir -p "$1"
'@
    $mkdirFailBody = @'
#!/bin/sh
exit 8
'@
    $installOkBody = @'
#!/bin/sh
/bin/cp "$1" "$2"
'@
    $installFailBody = @'
#!/bin/sh
exit 9
'@
    $pwdOkBody = @'
#!/bin/sh
printf '%s\n' "$1"
'@
    $pwdFailBody = @'
#!/bin/sh
exit 10
'@
    Set-Content -LiteralPath $recipeScript -Encoding ASCII -NoNewline -Value ($recipeBody -replace "`r`n", "`n")
    Set-Content -LiteralPath $mkdirOk -Encoding ASCII -NoNewline -Value ($mkdirOkBody -replace "`r`n", "`n")
    Set-Content -LiteralPath $mkdirFail -Encoding ASCII -NoNewline -Value ($mkdirFailBody -replace "`r`n", "`n")
    Set-Content -LiteralPath $installOk -Encoding ASCII -NoNewline -Value ($installOkBody -replace "`r`n", "`n")
    Set-Content -LiteralPath $installFail -Encoding ASCII -NoNewline -Value ($installFailBody -replace "`r`n", "`n")
    Set-Content -LiteralPath $pwdOk -Encoding ASCII -NoNewline -Value ($pwdOkBody -replace "`r`n", "`n")
    Set-Content -LiteralPath $pwdFail -Encoding ASCII -NoNewline -Value ($pwdFailBody -replace "`r`n", "`n")
    Copy-Item -LiteralPath $fakeDecomment -Destination $spacedDecomment
    $recipeSh = ConvertTo-DecommentTestShPath $recipeScript
    $mkdirOkSh = ConvertTo-DecommentTestShPath $mkdirOk
    $mkdirFailSh = ConvertTo-DecommentTestShPath $mkdirFail
    $installOkSh = ConvertTo-DecommentTestShPath $installOk
    $installFailSh = ConvertTo-DecommentTestShPath $installFail
    $pwdOkSh = ConvertTo-DecommentTestShPath $pwdOk
    $pwdFailSh = ConvertTo-DecommentTestShPath $pwdFail
    $spacedDecommentSh = ConvertTo-DecommentTestShPath $spacedDecomment
    $spacedSourceDir = Join-Path $decommentContractDir 'source root with spaces'
    New-Item -ItemType Directory -Path $spacedSourceDir | Out-Null
    $spacedInput = Join-Path $spacedSourceDir 'input header.h'
    Copy-Item -LiteralPath $inputHeader -Destination $spacedInput
    $spacedInputSh = ConvertTo-DecommentTestShPath $spacedInput
    $successRoot = Join-Path $decommentContractDir 'object root with spaces'
    $successRootSh = ConvertTo-DecommentTestShPath $successRoot
    $successAccepted = Join-Path $decommentContractDir 'success accepted'
    $successAcceptedSh = ConvertTo-DecommentTestShPath $successAccepted
    & $boundarySh $recipeSh $mkdirOkSh $installOkSh $spacedDecommentSh $unifdefSh $spacedInputSh $successRootSh $successAcceptedSh ok $pwdOkSh
    Assert-Equal $LASTEXITCODE 0 'kernel export recipe preserves spaced source, object, export, destination, and tool paths'
    Assert-Equal (Test-Path -LiteralPath $successAccepted) $true 'successful export recipe reaches acceptance marker'
    Assert-Equal (Test-Path -LiteralPath (Join-Path $successRoot 'include\output.h')) $true 'successful export recipe installs output'

    $mkdirFailRoot = Join-Path $decommentContractDir 'mkdir fail root'
    $mkdirFailAccepted = Join-Path $decommentContractDir 'mkdir fail accepted'
    & $boundarySh $recipeSh $mkdirFailSh $installOkSh $spacedDecommentSh $unifdefSh $spacedInputSh (ConvertTo-DecommentTestShPath $mkdirFailRoot) (ConvertTo-DecommentTestShPath $mkdirFailAccepted) ok $pwdOkSh 2>$null
    $mkdirFailExit = $LASTEXITCODE
    Assert-Equal ($mkdirFailExit -ne 0) $true 'kernel export recipe propagates MKDIRS failure'
    Assert-Equal (Test-Path -LiteralPath $mkdirFailAccepted) $false 'MKDIRS failure cannot reach acceptance marker'
    Assert-Equal (Test-Path -LiteralPath (Join-Path $mkdirFailRoot 'include\output.h')) $false 'MKDIRS failure cannot install output'

    $installFailRoot = Join-Path $decommentContractDir 'install fail root'
    $installFailAccepted = Join-Path $decommentContractDir 'install fail accepted'
    & $boundarySh $recipeSh $mkdirOkSh $installFailSh $spacedDecommentSh $unifdefSh $spacedInputSh (ConvertTo-DecommentTestShPath $installFailRoot) (ConvertTo-DecommentTestShPath $installFailAccepted) ok $pwdOkSh 2>$null
    $installFailExit = $LASTEXITCODE
    Assert-Equal ($installFailExit -ne 0) $true 'kernel export recipe propagates install failure'
    Assert-Equal (Test-Path -LiteralPath $installFailAccepted) $false 'install failure cannot reach acceptance marker'
    Assert-Equal (Test-Path -LiteralPath (Join-Path $installFailRoot 'include\output.h')) $false 'install failure cannot leave accepted output'

    $sentinelFailRoot = Join-Path $decommentContractDir 'sentinel fail root'
    $sentinelFailAccepted = Join-Path $decommentContractDir 'sentinel fail accepted'
    $savedErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'SilentlyContinue'
        & $boundarySh $recipeSh $mkdirOkSh $installOkSh $spacedDecommentSh $unifdefSh $spacedInputSh (ConvertTo-DecommentTestShPath $sentinelFailRoot) (ConvertTo-DecommentTestShPath $sentinelFailAccepted) fail $pwdOkSh 2>$null
        $sentinelFailExit = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $savedErrorActionPreference
    }
    Assert-Equal ($sentinelFailExit -ne 0) $true 'kernel export recipe propagates sentinel write failure'
    Assert-Equal (Test-Path -LiteralPath $sentinelFailAccepted) $false 'sentinel write failure cannot reach acceptance marker'
    Assert-Equal (Test-Path -LiteralPath (Join-Path $sentinelFailRoot 'include\output.h')) $false 'sentinel write failure cannot install output'

    $pwdFailRoot = Join-Path $decommentContractDir 'pwd fail root'
    $pwdFailAccepted = Join-Path $decommentContractDir 'pwd fail accepted'
    & $boundarySh $recipeSh $mkdirOkSh $installOkSh $spacedDecommentSh $unifdefSh $spacedInputSh (ConvertTo-DecommentTestShPath $pwdFailRoot) (ConvertTo-DecommentTestShPath $pwdFailAccepted) ok $pwdFailSh 2>$null
    $pwdFailExit = $LASTEXITCODE
    Assert-Equal ($pwdFailExit -ne 0) $true 'kernel export recipe propagates failed pwd capture'
    Assert-Equal (Test-Path -LiteralPath $pwdFailAccepted) $false 'failed pwd capture cannot reach acceptance marker'
    Assert-Equal (Test-Path -LiteralPath (Join-Path $pwdFailRoot 'exports')) $false 'failed pwd capture cannot create an export directory'
} finally {
    Remove-Item -LiteralPath $decommentContractDir -Recurse -Force -ErrorAction SilentlyContinue
}
Assert-NotMatch $cmd '(?m)(^|[;&|] *)mkdir +-p +/build/(tools|bootstrap-root|state)' 'does not create output roots'
Assert-NotMatch $cmd '(?m)(^|[;&|]\s*)(eval|source)\s' 'does not execute profile as code'
Assert-NotMatch $cmd '^sh -c ' 'does not nest through the login shell'

$quoted = New-RhapPreflightCommand -SourceRoot '/build/source tree' -ToolsDir '/build/source tree/tools' -BootstrapRoot '/build/source tree/root' -StateDir '/build/source tree/state' -Profile '/build/source tree/profile.conf'
Assert-Match $quoted ([regex]::Escape('source tree/profile.conf')) 'space-containing path is quoted'
Assert-Throws { New-RhapPreflightCommand -SourceRoot '/build/src;touch /tmp/x' -ToolsDir '/build/tools' -BootstrapRoot '/build/root' -StateDir '/build/state' -Profile '/build/profile' } 'reject control shell input'
Assert-Throws { New-RhapPreflightCommand -SourceRoot '/build/src' -ToolsDir '/build/tools' -BootstrapRoot '/build/root' -StateDir '/build/state' -Profile "/build/profile's.conf" } 'reject unsupported quote input'

$configDir = Join-Path $env:TEMP ("rhap-config-test-{0}" -f [guid]::NewGuid().ToString('n'))
New-Item -ItemType Directory -Path $configDir | Out-Null
try {
    Set-Content -LiteralPath (Join-Path $configDir 'vm.conf') -Encoding ASCII -Value @(
        'Host=example.invalid',
        'User=root',
        'Password=test',
        'RemoteRoot=/build'
    )
    $script:RhapVmDir = $configDir
    . (Join-Path $PSScriptRoot 'rhap-remote.ps1')
    $cfg = Get-RhapVmConfig -DiePrefix 'test-build-src'
    Assert-Equal $cfg.ToolsDir '/build/tools' 'default tools directory'
    Assert-Equal $cfg.BootstrapRoot '/build/bootstrap-root' 'default bootstrap root'
    Assert-Equal $cfg.StateDir '/build/state' 'default state directory'
    Assert-Equal $cfg.ToolchainProfile '/build/src/rbuild-1/toolchains/gcc-darwin.conf' 'relative profile resolution'

    Set-Content -LiteralPath (Join-Path $configDir 'vm.conf') -Encoding ASCII -Value @(
        'Host=example.invalid',
        'User=root',
        'Password=test',
        'RemoteRoot=////'
    )
    Assert-Throws { Get-RhapVmConfig -DiePrefix 'test-build-src' } 'reject filesystem root config'

    Set-Content -LiteralPath (Join-Path $configDir 'vm.conf') -Encoding ASCII -Value @(
        'Host=example.invalid',
        'User=root',
        'Password=test',
        'RemoteRoot=/build'
    )

    $transportDir = Join-Path $env:TEMP ("rhap-transport-test-{0}" -f [guid]::NewGuid().ToString('n'))
    $originalConsoleInputEncoding = Get-EncodingSignature ([Console]::InputEncoding)
    New-Item -ItemType Directory -Path $transportDir | Out-Null
    try {
        $captureSource = Join-Path $transportDir 'capture-stdin.c'
        $captureExe = Join-Path $transportDir 'capture-stdin.exe'
        Set-Content -LiteralPath $captureSource -Encoding ASCII -Value @(
            '#include <fcntl.h>',
            '#include <io.h>',
            '#include <stdio.h>',
            '#include <stdlib.h>',
            'int main(void) {',
            '    const char *path = getenv("RHAP_STDIN_CAPTURE");',
            '    const char *stdout_path = getenv("RHAP_STDIN_STDOUT_FILE");',
            '    const char *stdout_marker = getenv("RHAP_STDIN_STDOUT_MARKER");',
            '    unsigned char buffer[4096];',
            '    size_t count;',
            '    size_t i;',
            '    size_t position = 0;',
            '    int is_profile = 1;',
            '    const char profile_prefix[] = "set -e; /bin/cat ";',
            '    FILE *out;',
            '    FILE *in;',
            '    FILE *marker;',
            '    if (path == NULL || _setmode(_fileno(stdin), _O_BINARY) == -1) return 125;',
            '    out = fopen(path, "wb");',
            '    if (out == NULL) return 125;',
            '    while ((count = fread(buffer, 1, sizeof(buffer), stdin)) != 0) {',
            '        for (i = 0; i < count && position < sizeof(profile_prefix) - 1; ++i, ++position) {',
            '            if (buffer[i] != (unsigned char)profile_prefix[position]) is_profile = 0;',
            '        }',
            '        if (fwrite(buffer, 1, count, out) != count) return 125;',
            '    }',
            '    if (fclose(out) != 0) return 125;',
            '    if (is_profile && position == sizeof(profile_prefix) - 1 && stdout_path != NULL && stdout_marker != NULL) {',
            '        marker = fopen(stdout_marker, "rb");',
            '        if (marker == NULL) {',
            '            marker = fopen(stdout_marker, "wb");',
            '            if (marker == NULL || fclose(marker) != 0) return 125;',
            '            in = fopen(stdout_path, "rb");',
            '            if (in == NULL) return 125;',
            '            while ((count = fread(buffer, 1, sizeof(buffer), in)) != 0) {',
            '                if (fwrite(buffer, 1, count, stdout) != count) return 125;',
            '            }',
            '            if (fclose(in) != 0) return 125;',
            '        } else if (fclose(marker) != 0) return 125;',
            '    }',
            '    return 0;',
            '}'
        )
        & $clang -std=c89 -Wall -Wextra -Werror -D_CRT_SECURE_NO_WARNINGS -o $captureExe $captureSource
        Assert-Equal $LASTEXITCODE 0 'LLVM compiles remote stdin byte-capture fixture'

        foreach ($transportCase in @(
            [pscustomobject]@{ Name='preflight buffered transport'; Body=$cmd; Stream=$false },
            [pscustomobject]@{ Name='fresh streaming transport'; Body=$freshCommand; Stream=$true },
            [pscustomobject]@{ Name='phase streaming transport'; Body=$rbuildCommand; Stream=$true }
        )) {
            $capturePath = Join-Path $transportDir (($transportCase.Name -replace ' ', '-') + '.bin')
            $env:RHAP_STDIN_CAPTURE = $capturePath
            $transportExit = Invoke-RhapSshScript -Cfg $cfg -Ssh $captureExe -ScriptBody $transportCase.Body -Stream:$transportCase.Stream
            Assert-Equal $transportExit 0 "$($transportCase.Name) exit"
            Assert-RemotePayloadBytes -Path $capturePath -ScriptBody $transportCase.Body -Name $transportCase.Name
            $bytes = [System.IO.File]::ReadAllBytes($capturePath)
            Assert-Equal ([System.Text.Encoding]::ASCII.GetString($bytes, 0, 3)) 'set' "$($transportCase.Name) begins with set"
        }

        $profileTransportBody = New-RhapReadProfileCommand -Profile '/build/src/rbuild-1/toolchains/gcc-darwin.conf'
        $profileCapturePath = Join-Path $transportDir 'profile-capture.bin'
        $env:RHAP_STDIN_CAPTURE = $profileCapturePath
        $profileTransport = Invoke-RhapSshCapture -Cfg $cfg -Ssh $captureExe -ScriptBody $profileTransportBody
        Assert-Equal $profileTransport.ExitCode 0 'profile capture byte transport exit'
        Assert-RemotePayloadBytes -Path $profileCapturePath -ScriptBody $profileTransportBody -Name 'profile capture transport'

        $childCapturePath = Join-Path $transportDir 'child-file.bin'
        $childHarness = Join-Path $transportDir 'invoke-transport.ps1'
        $escapedRemote = (Join-Path $PSScriptRoot 'rhap-remote.ps1').Replace("'", "''")
        $escapedCaptureExe = $captureExe.Replace("'", "''")
        Set-Content -LiteralPath $childHarness -Encoding ASCII -Value @(
            "`$ErrorActionPreference = 'Stop'",
            ". '$escapedRemote'",
            "`$cfg = @{ User='root'; Host='example.invalid'; Password='test' }",
            ('$exitCode = Invoke-RhapSshScript -Cfg $cfg -Ssh ''{0}'' -ScriptBody "set -e`nprintf ''child''" -Stream' -f $escapedCaptureExe),
            "if (`$exitCode -ne 0) { exit `$exitCode }"
        )
        $env:RHAP_STDIN_CAPTURE = $childCapturePath
        & powershell -NoProfile -File $childHarness
        Assert-Equal $LASTEXITCODE 0 'no-profile file transport child exit'
        Assert-RemotePayloadBytes -Path $childCapturePath -ScriptBody "set -e`nprintf 'child'" -Name 'no-profile file transport'

        $canonicalVmDir = Join-Path $transportDir 'canonical-vm'
        New-Item -ItemType Directory -Path $canonicalVmDir | Out-Null
        foreach ($canonicalFile in @('build-src.ps1', 'build-src-lib.ps1', 'rhap-remote.ps1')) {
            Copy-Item -LiteralPath (Join-Path $PSScriptRoot $canonicalFile) -Destination $canonicalVmDir
        }
        Set-Content -LiteralPath (Join-Path $canonicalVmDir 'vm.conf') -Encoding ASCII -Value @(
            'Host=example.invalid',
            'User=root',
            'Password=test',
            'RemoteRoot=/build',
            "LocalRoot=$((Split-Path -Parent $PSScriptRoot))",
            "Ssh=$captureExe"
        )
        $canonicalCapturePath = Join-Path $transportDir 'canonical-rbuild.bin'
        $env:RHAP_STDIN_CAPTURE = $canonicalCapturePath
        $env:RHAP_STDIN_STDOUT_FILE = Join-Path $PSScriptRoot '..\src\rbuild-1\toolchains\gcc-darwin.conf'
        $env:RHAP_STDIN_STDOUT_MARKER = Join-Path $transportDir 'canonical-profile-emitted'
        $canonicalOutput = & powershell -NoProfile -File (Join-Path $canonicalVmDir 'build-src.ps1') -Rbuild 2>&1
        Assert-Equal $LASTEXITCODE 0 "canonical build-src -Rbuild transport exit: $($canonicalOutput -join ' | ')"
        Assert-RemotePayloadBytes -Path $canonicalCapturePath -ScriptBody $rbuildCommand -Name 'canonical build-src rbuild phase transport'
        Assert-EncodingSignature (Get-EncodingSignature ([Console]::InputEncoding)) $originalConsoleInputEncoding 'normal remote transport restores host console input encoding'

        $startFailureProcess = New-Object System.Diagnostics.Process
        $startFailureInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startFailureInfo.FileName = Join-Path $transportDir 'missing-ssh.exe'
        $startFailureInfo.UseShellExecute = $false
        $startFailureInfo.RedirectStandardInput = $true
        $startFailureProcess.StartInfo = $startFailureInfo
        try {
            Assert-Throws { Start-RhapSshProcess -Process $startFailureProcess -Ssh $startFailureInfo.FileName } 'SSH start failure is reported'
        } finally {
            $startFailureProcess.Dispose()
        }
        Assert-EncodingSignature (Get-EncodingSignature ([Console]::InputEncoding)) $originalConsoleInputEncoding 'SSH start failure restores host console input encoding'

        $acquisitionFailureProcess = New-Object System.Diagnostics.Process
        $acquisitionFailureInfo = New-Object System.Diagnostics.ProcessStartInfo
        $acquisitionFailureInfo.FileName = $captureExe
        $acquisitionFailureInfo.UseShellExecute = $false
        $acquisitionFailureInfo.RedirectStandardInput = $false
        $acquisitionFailureProcess.StartInfo = $acquisitionFailureInfo
        $acquisitionFailureMessage = $null
        $acquisitionFailureExited = $false
        try {
            try {
                [void](Start-RhapSshProcess -Process $acquisitionFailureProcess -Ssh $captureExe)
            } catch {
                $acquisitionFailureMessage = $_.Exception.Message
            }
            $acquisitionFailureExited = $acquisitionFailureProcess.HasExited
        } finally {
            $acquisitionFailureProcess.Dispose()
        }
        Assert-Match $acquisitionFailureMessage '^could not acquire SSH standard input:' 'stdin writer acquisition failure is reported clearly'
        Assert-Equal $acquisitionFailureExited $true 'stdin writer acquisition failure reaps the started child'
        Assert-EncodingSignature (Get-EncodingSignature ([Console]::InputEncoding)) $originalConsoleInputEncoding 'stdin writer acquisition failure restores host console input encoding'

        $badPayload = 'set -e' + "`n# " + [char]0xD800
        $env:RHAP_STDIN_CAPTURE = Join-Path $transportDir 'malformed.bin'
        Assert-Throws { Invoke-RhapSshScript -Cfg $cfg -Ssh $captureExe -ScriptBody $badPayload } 'remote transport rejects malformed UTF-16'
    } finally {
        Remove-Item Env:RHAP_STDIN_CAPTURE -ErrorAction SilentlyContinue
        Remove-Item Env:RHAP_STDIN_STDOUT_FILE -ErrorAction SilentlyContinue
        Remove-Item Env:RHAP_STDIN_STDOUT_MARKER -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $transportDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    $capture = @{}
    $fakeSsh = {
        param($Executable, $Arguments, $StdinBody)
        $capture.Executable = $Executable
        $capture.Arguments = @($Arguments)
        $capture.StdinBody = $StdinBody
        return 23
    }
    $fakeBody = "printf 'one'`r`nprintf 'two'"
    $fakeExit = Invoke-RhapSshScript -Cfg $cfg -Ssh 'fake-ssh.exe' -ScriptBody $fakeBody -Invoker $fakeSsh
    Assert-Equal $fakeExit 23 'script helper preserves exit status'
    Assert-Equal $capture.Executable 'fake-ssh.exe' 'script helper executable'
    Assert-Equal $capture.Arguments[-1] '/bin/sh -s' 'minimal remote shell argv'
    Assert-Equal (@($capture.Arguments | Where-Object { $_ -eq '/bin/sh -s' }).Count) 1 'one remote shell command'
    Assert-Equal $capture.StdinBody "printf 'one'`nprintf 'two'`n" 'exact LF-normalized stdin body'

    $streamEvents = New-Object System.Collections.Generic.List[string]
    $streamInvoker = {
        param($Executable, $Arguments, $StdinBody, $Streaming, $EmitStdout, $EmitStderr)
        Assert-Equal $Streaming $true 'stream invoker mode'
        & $EmitStdout 'early stdout'
        & $EmitStderr 'early stderr'
        $streamEvents.Add('exit')
        return 29
    }
    $streamObserver = { param($Kind, $Line) $streamEvents.Add("$Kind`:$Line") }
    $streamExit = Invoke-RhapSshScript -Cfg $cfg -Ssh 'fake-ssh.exe' -ScriptBody 'build' -Invoker $streamInvoker -Stream -Observer $streamObserver
    Assert-Equal $streamExit 29 'stream helper preserves failure exit'
    Assert-Equal ($streamEvents -join ',') 'stdout:early stdout,stderr:early stderr,exit' 'stream output observed before process exit'

    $remoteProfile = $realProfile -replace '(?m)^build_cc=.*$', 'build_cc=/remote/bin/gcc'
    $captureInvoker = {
        param($Executable, $Arguments, $StdinBody)
        $capture.ProfileBody = $StdinBody
        return [pscustomobject]@{ ExitCode = 0; Stdout = $remoteProfile; Stderr = '' }
    }
    $profileResult = Invoke-RhapSshCapture -Cfg $cfg -Ssh 'fake-ssh.exe' -ScriptBody (New-RhapReadProfileCommand -Profile '/opt/profiles/gcc.conf') -Invoker $captureInvoker
    Assert-Equal $profileResult.ExitCode 0 'profile capture exit'
    Assert-Match $capture.ProfileBody ([regex]::Escape("/bin/cat '/opt/profiles/gcc.conf'")) 'profile capture reads absolute remote path'
    $remoteValues = ConvertFrom-RhapToolchainProfileText -Text $profileResult.Stdout
    Assert-Equal $remoteValues.build_cc '/remote/bin/gcc' 'remote profile contents are authoritative'

    Set-Content -LiteralPath (Join-Path $configDir 'vm.conf') -Encoding ASCII -Value @(
        'Host=example.invalid',
        'User=root',
        'Password=test',
        'RemoteRoot=/srv/rhapsodios',
        'ToolsDir=/srv/rhapsodios/custom-tools',
        'BootstrapRoot=/srv/rhapsodios/custom-root',
        'StateDir=/srv/rhapsodios/custom-state',
        'ToolchainProfile=/opt/profiles/gcc.conf'
    )
    $cfg = Get-RhapVmConfig -DiePrefix 'test-build-src'
    Assert-Equal $cfg.ToolsDir '/srv/rhapsodios/custom-tools' 'tools override'
    Assert-Equal $cfg.BootstrapRoot '/srv/rhapsodios/custom-root' 'bootstrap override'
    Assert-Equal $cfg.StateDir '/srv/rhapsodios/custom-state' 'state override'
    Assert-Equal $cfg.ToolchainProfile '/opt/profiles/gcc.conf' 'absolute profile preserved'
} finally {
    Remove-Item -LiteralPath $configDir -Recurse -Force -ErrorAction SilentlyContinue
}

$wrapperTestDir = Join-Path $env:TEMP ("mig wrapper test {0}" -f [guid]::NewGuid().ToString('n'))
New-Item -ItemType Directory -Path $wrapperTestDir | Out-Null
$previousMigArch = $env:MIGARCH
$env:MIGARCH = 'ppc'
try {
    function ConvertTo-TestShPath([string]$Path) {
        $resolved = [System.IO.Path]::GetFullPath($Path) -replace '\\', '/'
        if ($resolved -match '^([A-Za-z]):') {
            return '/' + $Matches[1].ToLowerInvariant() + $resolved.Substring(2)
        }
        return $resolved
    }

    $fakeBin = Join-Path $wrapperTestDir 'gcc tools'
    $fakeLibexec = Join-Path $wrapperTestDir 'mig libexec'
    $captureDir = Join-Path $wrapperTestDir 'argument capture'
    $definitionDir = Join-Path $wrapperTestDir 'source definitions'
    $outputDir = Join-Path $wrapperTestDir 'generated output'
    $runDir = Join-Path $wrapperTestDir 'current build directory'
    foreach ($dir in @($fakeBin, $fakeLibexec, $captureDir, $definitionDir, $outputDir, $runDir)) {
        New-Item -ItemType Directory -Path $dir | Out-Null
    }
    $fakeCompiler = Join-Path $fakeBin 'gcc'
    $fakeBackend = Join-Path $fakeLibexec 'migcom'
    $fakeCompilerBody = @'
#!/bin/sh
for arg do printf '%s\n' "$arg" >> "$MIG_TEST_CAPTURE/compiler.args"; done
printf '%s\n' '--invocation--' >> "$MIG_TEST_CAPTURE/compiler.args"
language=
input=
target_arch=
typed=
while test $# -gt 0; do
    case $1 in
        -x) shift; language=$1 ;;
        -Dppc|-Dalternate_safe) target_arch=$1 ;;
        -DMACH_IPC_FLAVOR=TYPED) typed=yes ;;
        *.defs) input=$1 ;;
    esac
    shift
done
if test -n "${MIGCC-}"; then test "$language" = c || exit 91; fi
test -f "$input" || exit 92
case $input in
    */kernel-7/mach/mach.defs)
        test "$target_arch" = -Dppc || exit 95
        test "$typed" = yes || exit 96
        ;;
esac
if test "${MIG_TEST_CPP_MODE-}" = fail; then
    printf '%s\n' 'partial preprocessor output'
    exit 42
fi
if test "${MIG_TEST_CPP_MODE-}" = signal; then
    kill -TERM "$PPID"
    printf '%s\n' 'partial signaled output'
    exit 0
fi
while IFS= read -r line || test -n "$line"; do printf '%s\n' "$line"; done < "$input"
'@
    $fakeBackendBody = @'
#!/bin/sh
for arg do printf '%s\n' "$arg" >> "$MIG_TEST_CAPTURE/backend.args"; done
printf '%s\n' '--invocation--' >> "$MIG_TEST_CAPTURE/backend.args"
header=
user=
while test $# -gt 0; do
    case $1 in
        -header) shift; header=$1 ;;
        -user) shift; user=$1 ;;
    esac
    shift
done
test -n "$header" || exit 93
if test "${MIG_TEST_BACKEND_MODE-}" = fail; then exit 94; fi
while IFS= read -r line || test -n "$line"; do printf '%s\n' "$line"; done > "$header"
test -z "$user" || printf '%s\n' 'generated user' > "$user"
'@
    Set-Content -LiteralPath $fakeCompiler -Encoding ASCII -NoNewline -Value ($fakeCompilerBody -replace "`r`n", "`n")
    Set-Content -LiteralPath $fakeBackend -Encoding ASCII -NoNewline -Value ($fakeBackendBody -replace "`r`n", "`n")
    Copy-Item -LiteralPath $fakeBackend -Destination (Join-Path $fakeLibexec 'migcom_typd')
    Copy-Item -LiteralPath $fakeBackend -Destination (Join-Path $fakeLibexec 'migcom_untypd')
    $fakeMkdir = Join-Path $fakeBin 'mkdir'
    $fakeMkdirBody = @'
#!/bin/sh
/usr/bin/mkdir "$@" || exit $?
printf '%s\n' signaled > "$MIG_TEST_CAPTURE/mkdir.signal"
kill -TERM "$PPID"
exit 0
'@
    Set-Content -LiteralPath $fakeMkdir -Encoding ASCII -NoNewline -Value ($fakeMkdirBody -replace "`r`n", "`n")
    $defsOne = Join-Path $definitionDir 'first interface.defs'
    $defsTwo = Join-Path $definitionDir 'second interface.defs'
    Set-Content -LiteralPath $defsOne -Encoding ASCII -Value 'subsystem first_contract 4100;'
    Set-Content -LiteralPath $defsTwo -Encoding ASCII -Value 'subsystem second_contract 4101;'
    $headerOutput = Join-Path $outputDir 'public header.h'
    $userOutput = Join-Path $outputDir 'user source.c'
    $serverHeader = Join-Path $outputDir 'server header.h'
    $handlerOutput = Join-Path $outputDir 'handler source.c'
    $prefix = Join-Path $outputDir 'routine prefix'
    $sh = (Get-Command sh.exe -ErrorAction Stop).Source
    $wrapperArgs = @(
        '-header', (ConvertTo-TestShPath $headerOutput),
        '-user', (ConvertTo-TestShPath $userOutput),
        '-sheader', (ConvertTo-TestShPath $serverHeader),
        '-handler', (ConvertTo-TestShPath $handlerOutput),
        '-i', (ConvertTo-TestShPath $prefix),
        '-DVALUE=two words',
        (ConvertTo-TestShPath $defsOne),
        (ConvertTo-TestShPath $defsTwo)
    )
    $quotedWrapperArgs = ($wrapperArgs | ForEach-Object { ConvertTo-RhapShellLiteral $_ }) -join ' '
    $invoke = 'cd {0} && MIGCC={1} MIGCOM_DIR={2} MIG_TEST_CAPTURE={3} sh {4} {5}' -f @(
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $runDir)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $fakeCompiler)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $fakeLibexec)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $captureDir)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath (Join-Path $PSScriptRoot '..\src\Commands\bootstrap_cmds\migcom.tproj\mig.sh'))),
        $quotedWrapperArgs
    )
    & $sh -c $invoke
    Assert-Equal $LASTEXITCODE 0 'MIG wrapper executes configured GCC and backend with spaced paths'
    Assert-Equal (Test-Path -LiteralPath $headerOutput) $true 'MIG wrapper generates requested spaced header output'
    Assert-Equal (Test-Path -LiteralPath $userOutput) $true 'MIG wrapper generates requested spaced user output'
    $compilerArgs = Get-Content -LiteralPath (Join-Path $captureDir 'compiler.args')
    $backendArgs = Get-Content -LiteralPath (Join-Path $captureDir 'backend.args')
    Assert-Equal (@($compilerArgs | Where-Object { $_ -eq '-DVALUE=two words' }).Count) 2 'MIG wrapper preserves spaced cpp flag for multiple definitions'
    Assert-Equal (@($compilerArgs | Where-Object { $_ -eq '-Dppc' }).Count) 2 'MIG wrapper adds one configured architecture definition per compiler invocation'
    Assert-Equal (@($compilerArgs | Where-Object { $_ -eq '--invocation--' }).Count) 2 'MIG wrapper preprocesses multiple definitions'
    Assert-Equal (@($backendArgs | Where-Object { $_ -eq (ConvertTo-TestShPath $headerOutput) }).Count) 2 'MIG wrapper preserves spaced backend header value'
    Assert-Equal (@($backendArgs | Where-Object { $_ -eq (ConvertTo-TestShPath $prefix) }).Count) 2 'MIG wrapper preserves spaced optional -i prefix'
    Assert-Equal (@($backendArgs | Where-Object { $_ -eq '--invocation--' }).Count) 2 'MIG wrapper invokes backend for multiple definitions'
    $newlineFlag = "-DBAD=line one`nline two"
    $newlineInvoke = 'MIGCC={0} MIGCOM_DIR={1} MIG_TEST_CAPTURE={2} sh {3} {4} {5} 2>/dev/null' -f @(
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $fakeCompiler)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $fakeLibexec)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $captureDir)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath (Join-Path $PSScriptRoot '..\src\Commands\bootstrap_cmds\migcom.tproj\mig.sh'))),
        (ConvertTo-RhapShellLiteral $newlineFlag),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $defsOne))
    )
    & $sh -c $newlineInvoke
    Assert-Equal $LASTEXITCODE 1 'MIG wrapper rejects embedded newlines before execution'
    Assert-Equal (@((Get-Content -LiteralPath (Join-Path $captureDir 'compiler.args')) | Where-Object { $_ -eq '--invocation--' }).Count) 2 'newline rejection does not invoke configured compiler'

    $wrapperShPath = ConvertTo-TestShPath (Join-Path $PSScriptRoot '..\src\Commands\bootstrap_cmds\migcom.tproj\mig.sh')
    $operandResults = Join-Path $captureDir 'operand.results'
    $operandContractBody = @'
status=0
empty=
: > "$MIG_OPERAND_RESULTS"
for required_option in -user -server -header -sheader -handler -arch; do
    if (set -- "$required_option"; . "$MIG_WRAPPER") 2>/dev/null; then result=FAIL; status=1; else result=PASS; fi
    printf "%s missing %s\n" "$required_option" "$result" >> "$MIG_OPERAND_RESULTS"
    if (set -- "$required_option" "$empty"; . "$MIG_WRAPPER") 2>/dev/null; then result=FAIL; status=1; else result=PASS; fi
    printf "%s empty %s\n" "$required_option" "$result" >> "$MIG_OPERAND_RESULTS"
    if (set -- "$required_option" -q "$MIG_DEFS"; . "$MIG_WRAPPER") 2>/dev/null; then result=FAIL; status=1; else result=PASS; fi
    printf "%s option %s\n" "$required_option" "$result" >> "$MIG_OPERAND_RESULTS"
done
exit $status
'@
    $operandScript = Join-Path $wrapperTestDir 'operand contract.sh'
    Set-Content -LiteralPath $operandScript -Encoding ASCII -NoNewline -Value ($operandContractBody -replace "`r`n", "`n")
    $operandInvoke = 'cd {0} && MIGCC={1} MIGCOM_DIR={2} MIG_TEST_CAPTURE={3} MIG_WRAPPER={4} MIG_DEFS={5} MIG_OPERAND_RESULTS={6} sh {7}' -f @(
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $runDir)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $fakeCompiler)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $fakeLibexec)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $captureDir)),
        (ConvertTo-RhapShellLiteral $wrapperShPath),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $defsOne)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $operandResults)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $operandScript))
    )
    & $sh -c $operandInvoke
    Assert-Equal $LASTEXITCODE 0 'MIG wrapper rejects every invalid required operand form'
    $operandResultLines = Get-Content -LiteralPath $operandResults
    Assert-Equal $operandResultLines.Count 18 'MIG wrapper exercises missing, empty, and option operands for every required option'
    Assert-Equal (@($operandResultLines | Where-Object { $_ -notmatch ' PASS$' }).Count) 0 'MIG wrapper invalid operand cases all return nonzero'
    Assert-Equal (@((Get-Content -LiteralPath (Join-Path $captureDir 'compiler.args')) | Where-Object { $_ -eq '--invocation--' }).Count) 2 'invalid required operands do not invoke configured compiler'

    $failedConfiguredOutput = Join-Path $outputDir 'configured failure header.h'
    $configuredFailureInvoke = 'cd {0} && MIGCC={1} MIGCOM_DIR={2} MIG_TEST_CAPTURE={3} MIG_TEST_CPP_MODE=fail sh {4} -header {5} {6} 2>/dev/null' -f @(
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $runDir)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $fakeCompiler)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $fakeLibexec)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $captureDir)),
        (ConvertTo-RhapShellLiteral $wrapperShPath),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $failedConfiguredOutput)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $defsOne))
    )
    & $sh -c $configuredFailureInvoke
    Assert-Equal ($LASTEXITCODE -ne 0) $true 'MIG wrapper propagates configured compiler failure'
    Assert-Equal (Test-Path -LiteralPath $failedConfiguredOutput) $false 'configured compiler partial output never reaches backend output'
    Assert-Equal (@((Get-Content -LiteralPath (Join-Path $captureDir 'backend.args')) | Where-Object { $_ -eq '--invocation--' }).Count) 2 'configured compiler failure does not invoke backend'
    Assert-Equal (@(Get-ChildItem -LiteralPath $runDir -Force | Where-Object { $_.Name -like '*.migcpp.*' }).Count) 0 'configured compiler failure removes staged preprocessing output'

    $failedBackendOutput = Join-Path $outputDir 'backend failure header.h'
    $backendFailureInvoke = 'cd {0} && MIGCC={1} MIGCOM_DIR={2} MIG_TEST_CAPTURE={3} MIG_TEST_BACKEND_MODE=fail sh {4} -header {5} {6} 2>/dev/null' -f @(
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $runDir)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $fakeCompiler)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $fakeLibexec)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $captureDir)),
        (ConvertTo-RhapShellLiteral $wrapperShPath),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $failedBackendOutput)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $defsOne))
    )
    & $sh -c $backendFailureInvoke
    Assert-Equal ($LASTEXITCODE -ne 0) $true 'MIG wrapper propagates backend failure'
    Assert-Equal (Test-Path -LiteralPath $failedBackendOutput) $false 'backend failure does not report a generated output'
    Assert-Equal (@(Get-ChildItem -LiteralPath $runDir -Force | Where-Object { $_.Name -like '*.migcpp.*' }).Count) 0 'backend failure removes staged preprocessing output'

    $collisionResults = Join-Path $captureDir 'collision.results'
    $collisionFileOutput = Join-Path $outputDir 'collision file header.h'
    $collisionDirOutput = Join-Path $outputDir 'collision dir header.h'
    $collisionDanglingOutput = Join-Path $outputDir 'collision dangling header.h'
    $collisionLiveOutput = Join-Path $outputDir 'collision live header.h'
    $backendCountBeforeCollision = @((Get-Content -LiteralPath (Join-Path $captureDir 'backend.args')) | Where-Object { $_ -eq '--invocation--' }).Count
    $collisionContractBody = @'
status=0
: > "$MIG_COLLISION_RESULTS"
candidate="./.first interface.migcpp.$$.$MIG_SEQUENCE.d"
check_failure()
{
    if (set -- -header "$1" "$MIG_DEFS"; . "$MIG_WRAPPER") 2>/dev/null
    then
        printf "%s FAIL\n" "$2" >> "$MIG_COLLISION_RESULTS"
        status=1
    else
        printf "%s PASS\n" "$2" >> "$MIG_COLLISION_RESULTS"
    fi
}

printf "%s\n" original > "$candidate"
check_failure "$MIG_FILE_OUTPUT" file
test "$(/bin/cat "$candidate")" = original || status=1
rm -f "$candidate"

mkdir "$candidate"
printf "%s\n" sentinel > "$candidate/sentinel"
check_failure "$MIG_DIR_OUTPUT" dir
test "$(/bin/cat "$candidate/sentinel")" = sentinel || status=1
rm -f "$candidate/sentinel"
rmdir "$candidate"

mkdir dangling-target
/c/Windows/System32/cmd.exe //d //c mklink //J "$candidate" dangling-target >/dev/null || exit 1
rmdir dangling-target
check_failure "$MIG_DANGLING_OUTPUT" dangling
if mkdir "$candidate" 2>/dev/null; then status=1; rmdir "$candidate"; fi
/c/Windows/System32/cmd.exe //d //c rmdir "$candidate" >/dev/null || status=1

mkdir live-target
printf "%s\n" live > live-target/sentinel
/c/Windows/System32/cmd.exe //d //c mklink //J "$candidate" live-target >/dev/null || exit 1
check_failure "$MIG_LIVE_OUTPUT" live
test "$(/bin/cat live-target/sentinel)" = live || status=1
if mkdir "$candidate" 2>/dev/null; then status=1; rmdir "$candidate"; fi
/c/Windows/System32/cmd.exe //d //c rmdir "$candidate" >/dev/null || status=1
rm -f live-target/sentinel
rmdir live-target
exit $status
'@
    $collisionScript = Join-Path $wrapperTestDir 'collision contract.sh'
    Set-Content -LiteralPath $collisionScript -Encoding ASCII -NoNewline -Value ($collisionContractBody -replace "`r`n", "`n")
    $collisionInvoke = 'cd {0} && MIGCC={1} MIGCOM_DIR={2} MIG_TEST_CAPTURE={3} MIG_WRAPPER={4} MIG_DEFS={5} MIG_SEQUENCE=x MIG_COLLISION_RESULTS={6} MIG_FILE_OUTPUT={7} MIG_DIR_OUTPUT={8} MIG_DANGLING_OUTPUT={9} MIG_LIVE_OUTPUT={10} sh {11}' -f @(
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $runDir)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $fakeCompiler)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $fakeLibexec)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $captureDir)),
        (ConvertTo-RhapShellLiteral $wrapperShPath),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $defsOne)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $collisionResults)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $collisionFileOutput)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $collisionDirOutput)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $collisionDanglingOutput)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $collisionLiveOutput)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $collisionScript))
    )
    & $sh -c $collisionInvoke
    Assert-Equal $LASTEXITCODE 0 'MIG wrapper preserves every unowned staging collision'
    $collisionResultLines = Get-Content -LiteralPath $collisionResults
    Assert-Equal $collisionResultLines.Count 4 'MIG wrapper exercises file, directory, dangling, and live link collisions'
    Assert-Equal (@($collisionResultLines | Where-Object { $_ -notmatch ' PASS$' }).Count) 0 'MIG wrapper rejects every staging collision'
    Assert-Equal (@((Get-Content -LiteralPath (Join-Path $captureDir 'backend.args')) | Where-Object { $_ -eq '--invocation--' }).Count) $backendCountBeforeCollision 'MIG staging collisions never invoke backend'
    foreach ($collisionOutput in @($collisionFileOutput, $collisionDirOutput, $collisionDanglingOutput, $collisionLiveOutput)) {
        Assert-Equal (Test-Path -LiteralPath $collisionOutput) $false "MIG staging collision leaves output absent: $collisionOutput"
    }

    $transitionOutput = Join-Path $outputDir 'ownership transition header.h'
    $transitionInvoke = 'cd {0} && PATH={1}:/usr/bin:/bin MIGCC={2} MIGCOM_DIR={3} MIG_TEST_CAPTURE={4} sh {5} -header {6} {7} 2>/dev/null' -f @(
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $runDir)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $fakeBin)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $fakeCompiler)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $fakeLibexec)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $captureDir)),
        (ConvertTo-RhapShellLiteral $wrapperShPath),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $transitionOutput)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $defsOne))
    )
    & $sh -c $transitionInvoke
    Assert-Equal $LASTEXITCODE 0 'MIG wrapper survives a signal during mkdir ownership transition'
    Assert-Equal (Test-Path -LiteralPath (Join-Path $captureDir 'mkdir.signal')) $true 'MIG ownership transition test delivers its signal'
    Assert-Equal (Test-Path -LiteralPath $transitionOutput) $true 'MIG wrapper generates output after protected ownership transition'
    Assert-Equal (@(Get-ChildItem -LiteralPath $runDir -Force | Where-Object { $_.Name -like '*.migcpp.*' }).Count) 0 'ownership transition signal leaves no staged directory'

    $signalOutput = Join-Path $outputDir 'owned signal header.h'
    $signalInvoke = 'cd {0} && MIGCC={1} MIGCOM_DIR={2} MIG_TEST_CAPTURE={3} MIG_TEST_CPP_MODE=signal sh {4} -header {5} {6} 2>/dev/null' -f @(
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $runDir)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $fakeCompiler)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $fakeLibexec)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $captureDir)),
        (ConvertTo-RhapShellLiteral $wrapperShPath),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $signalOutput)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $defsOne))
    )
    & $sh -c $signalInvoke
    Assert-Equal ($LASTEXITCODE -ne 0) $true 'MIG wrapper propagates signal after staging ownership'
    Assert-Equal (Test-Path -LiteralPath $signalOutput) $false 'owned-stage signal never reaches backend output'
    Assert-Equal (@(Get-ChildItem -LiteralPath $runDir -Force | Where-Object { $_.Name -like '*.migcpp.*' }).Count) 0 'owned-stage signal cleanup leaves no staged directory'

    $archCountBeforeDefault = @((Get-Content -LiteralPath (Join-Path $captureDir 'compiler.args')) | Where-Object { $_ -eq '-Dppc' }).Count
    $defaultOutput = Join-Path $outputDir 'default cpp header.h'
    $defaultInvoke = 'unset MIGCC; cd {0} && MIGCPP={1} MIGCOM_DIR={2} MIG_TEST_CAPTURE={3} sh {4} -header {5} {6}' -f @(
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $runDir)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $fakeCompiler)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $fakeLibexec)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $captureDir)),
        (ConvertTo-RhapShellLiteral $wrapperShPath),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $defaultOutput)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $defsOne))
    )
    & $sh -c $defaultInvoke
    Assert-Equal $LASTEXITCODE 0 'MIG wrapper default cpp branch executes successfully'
    Assert-Equal (Test-Path -LiteralPath $defaultOutput) $true 'MIG wrapper default cpp branch generates requested output'
    $failedDefaultOutput = Join-Path $outputDir 'default failure header.h'
    $defaultFailureInvoke = 'unset MIGCC; cd {0} && MIGCPP={1} MIGCOM_DIR={2} MIG_TEST_CAPTURE={3} MIG_TEST_CPP_MODE=fail sh {4} -header {5} {6} 2>/dev/null' -f @(
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $runDir)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $fakeCompiler)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $fakeLibexec)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $captureDir)),
        (ConvertTo-RhapShellLiteral $wrapperShPath),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $failedDefaultOutput)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $defsOne))
    )
    & $sh -c $defaultFailureInvoke
    Assert-Equal ($LASTEXITCODE -ne 0) $true 'MIG wrapper propagates default cpp failure'
    Assert-Equal (Test-Path -LiteralPath $failedDefaultOutput) $false 'default cpp partial output never reaches backend output'
    Assert-Equal (@(Get-ChildItem -LiteralPath $runDir -Force | Where-Object { $_.Name -like '*.migcpp.*' }).Count) 0 'default cpp failure removes staged preprocessing output'
    $archCountAfterDefault = @((Get-Content -LiteralPath (Join-Path $captureDir 'compiler.args')) | Where-Object { $_ -eq '-Dppc' }).Count
    Assert-Equal $archCountAfterDefault $archCountBeforeDefault 'historical no-MIGCC cpp branch ignores configured MIGARCH'

    $compilerCountBeforeInvalidArch = @((Get-Content -LiteralPath (Join-Path $captureDir 'compiler.args')) | Where-Object { $_ -eq '--invocation--' }).Count
    foreach ($badArch in @('ppc;touch_bad', '9ppc', 'ppc other')) {
        $invalidArchInvoke = 'cd {0} && MIGCC={1} MIGARCH={2} MIGCOM_DIR={3} MIG_TEST_CAPTURE={4} sh {5} -header {6} {7} 2>/dev/null' -f @(
            (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $runDir)),
            (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $fakeCompiler)),
            (ConvertTo-RhapShellLiteral $badArch),
            (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $fakeLibexec)),
            (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $captureDir)),
            (ConvertTo-RhapShellLiteral $wrapperShPath),
            (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath (Join-Path $outputDir 'invalid arch.h'))),
            (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $defsOne))
        )
        & $sh -c $invalidArchInvoke
        Assert-Equal ($LASTEXITCODE -ne 0) $true "MIG wrapper rejects invalid configured architecture: $badArch"
    }
    $missingArchInvoke = 'cd {0} && unset MIGARCH && MIGCC={1} MIGCOM_DIR={2} MIG_TEST_CAPTURE={3} sh {4} -header {5} {6} 2>/dev/null' -f @(
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $runDir)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $fakeCompiler)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $fakeLibexec)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $captureDir)),
        (ConvertTo-RhapShellLiteral $wrapperShPath),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath (Join-Path $outputDir 'missing arch.h'))),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $defsOne))
    )
    & $sh -c $missingArchInvoke
    Assert-Equal ($LASTEXITCODE -ne 0) $true 'configured MIG compiler requires an architecture contract'
    $invalidExplicitArchInvoke = 'cd {0} && MIGCC={1} MIGARCH=ppc MIGCOM_DIR={2} MIG_TEST_CAPTURE={3} sh {4} -arch {5} -header {6} {7} 2>/dev/null' -f @(
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $runDir)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $fakeCompiler)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $fakeLibexec)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $captureDir)),
        (ConvertTo-RhapShellLiteral $wrapperShPath),
        (ConvertTo-RhapShellLiteral 'ppc;touch_bad'),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath (Join-Path $outputDir 'invalid explicit arch.h'))),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $defsOne))
    )
    & $sh -c $invalidExplicitArchInvoke
    Assert-Equal ($LASTEXITCODE -ne 0) $true 'MIG wrapper validates and rejects unsafe explicit -arch'
    Assert-Equal (@((Get-Content -LiteralPath (Join-Path $captureDir 'compiler.args')) | Where-Object { $_ -eq '--invocation--' }).Count) $compilerCountBeforeInvalidArch 'invalid or missing architectures never invoke configured compiler'

    $ambientPpcBefore = @((Get-Content -LiteralPath (Join-Path $captureDir 'compiler.args')) | Where-Object { $_ -eq '-Dppc' }).Count
    $ambientI386Before = @((Get-Content -LiteralPath (Join-Path $captureDir 'compiler.args')) | Where-Object { $_ -eq '-Di386' }).Count
    $ambientConflictOutput = Join-Path $outputDir 'ambient architecture conflict header.h'
    $ambientConflictInvoke = 'cd {0} && arch=i386 MIGCC={1} MIGARCH=ppc MIGCOM_DIR={2} MIG_TEST_CAPTURE={3} sh {4} -header {5} {6}' -f @(
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $runDir)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $fakeCompiler)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $fakeLibexec)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $captureDir)),
        (ConvertTo-RhapShellLiteral $wrapperShPath),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $ambientConflictOutput)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $defsOne))
    )
    & $sh -c $ambientConflictInvoke
    Assert-Equal $LASTEXITCODE 0 'ambient lowercase arch does not override configured MIGARCH'
    $compilerArgsAfterAmbient = Get-Content -LiteralPath (Join-Path $captureDir 'compiler.args')
    Assert-Equal (@($compilerArgsAfterAmbient | Where-Object { $_ -eq '-Dppc' }).Count) ($ambientPpcBefore + 1) 'configured branch emits profile MIGARCH despite ambient lowercase arch'
    Assert-Equal (@($compilerArgsAfterAmbient | Where-Object { $_ -eq '-Di386' }).Count) $ambientI386Before 'configured branch never emits ambient lowercase arch'

    $overrideOutput = Join-Path $outputDir 'explicit architecture header.h'
    $overrideInvoke = 'cd {0} && arch=ambient_bad MIGCC={1} MIGARCH=ppc MIGCOM_DIR={2} MIG_TEST_CAPTURE={3} sh {4} -arch i386 -header {5} {6}' -f @(
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $runDir)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $fakeCompiler)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $fakeLibexec)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $captureDir)),
        (ConvertTo-RhapShellLiteral $wrapperShPath),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $overrideOutput)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $defsOne))
    )
    & $sh -c $overrideInvoke
    Assert-Equal $LASTEXITCODE 0 'explicit safe -arch overrides configured MIGARCH'
    $compilerArgsAfterOverride = Get-Content -LiteralPath (Join-Path $captureDir 'compiler.args')
    Assert-Equal (@($compilerArgsAfterOverride | Where-Object { $_ -eq '-Di386' }).Count) ($ambientI386Before + 1) 'explicit i386 architecture is preserved as one cpp argument'

    $typedOutput = Join-Path $outputDir 'typed mach server.h'
    $actualMachDefs = Join-Path $PSScriptRoot '..\src\kernel-7\mach\mach.defs'
    $typedInvoke = 'cd {0} && MIGCC={1} MIGARCH=ppc MIGCOM_DIR={2} MIG_TEST_CAPTURE={3} sh {4} -typed -I{5} -DKERNEL -DKERNEL_SERVER -header {6} -user /dev/null -server /dev/null {7}' -f @(
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $runDir)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $fakeCompiler)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $fakeLibexec)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $captureDir)),
        (ConvertTo-RhapShellLiteral $wrapperShPath),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath (Join-Path $PSScriptRoot '..\src\kernel-7'))),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $typedOutput)),
        (ConvertTo-RhapShellLiteral (ConvertTo-TestShPath $actualMachDefs))
    )
    & $sh -c $typedInvoke
    Assert-Equal $LASTEXITCODE 0 'typed wrapper contract accepts the actual kernel mach.defs with configured architecture'
    Assert-Equal (Test-Path -LiteralPath $typedOutput) $true 'typed actual mach.defs reaches private typed backend'
    $typedCompilerArgs = Get-Content -LiteralPath (Join-Path $captureDir 'compiler.args')
    Assert-Equal (@($typedCompilerArgs | Where-Object { $_ -eq '-DMACH_IPC_FLAVOR=TYPED' }).Count -ge 1) $true 'typed actual mach.defs selects typed preprocessing'
    Assert-Equal (@($typedCompilerArgs | Where-Object { $_ -eq (ConvertTo-TestShPath $actualMachDefs) }).Count) 1 'typed wrapper passes the actual mach.defs as one input'
} finally {
    $env:MIGARCH = $previousMigArch
    Remove-Item -LiteralPath $wrapperTestDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "build-src tests: PASS ($script:Checks checks)"
