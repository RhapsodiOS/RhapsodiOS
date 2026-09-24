# Run a shell script on the build box and exit with its exit status.
# vm.conf is gitignored, so a worktree has none: set RHAP_VM_DIR to a vm
# directory that has one (such as the main checkout's) to use it instead.
param([Parameter(Mandatory = $true)][string]$ScriptFile)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($env:RHAP_VM_DIR) { $script:RhapVmDir = $env:RHAP_VM_DIR }
. (Join-Path $PSScriptRoot '..\..\vm\rhap-remote.ps1')
$cfg = Get-RhapVmConfig -DiePrefix 'hfs-name-test'
$ssh = Resolve-RhapTool -Name $cfg.Ssh -Kind 'ssh'
Invoke-RhapSshCapture -Cfg $cfg -Ssh $ssh -ScriptBody (Get-Content -LiteralPath $ScriptFile -Raw)
$r = $script:RhapLastSshCapture
[Console]::Out.Write($r.Stdout)
if ($r.Stderr) { [Console]::Error.Write($r.Stderr) }
exit $r.ExitCode
