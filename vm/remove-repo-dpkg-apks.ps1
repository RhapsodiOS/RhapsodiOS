#Requires -Version 5.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'rhap-remote.ps1')
$cfg = Get-RhapVmConfig -DiePrefix 'remove-repo-dpkg-apks'
$ssh = Resolve-RhapTool -NameOrPath $cfg.Ssh -DiePrefix 'remove-repo-dpkg-apks'

$body = Get-Content -Raw (Join-Path $PSScriptRoot 'remove-repo-dpkg-apks.sh')
$ec = Invoke-RhapSshScript -Cfg $cfg -Ssh $ssh -ScriptBody $body -Stream
exit $ec
