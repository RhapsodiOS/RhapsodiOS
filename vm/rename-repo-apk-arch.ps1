#Requires -Version 5.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'rhap-remote.ps1')
$cfg = Get-RhapVmConfig -DiePrefix 'rename-repo-apk-arch'
$ssh = Resolve-RhapTool -NameOrPath $cfg.Ssh -DiePrefix 'rename-repo-apk-arch'

$body = Get-Content -Raw (Join-Path $PSScriptRoot 'rename-repo-apk-arch.sh')
$ec = Invoke-RhapSshScript -Cfg $cfg -Ssh $ssh -ScriptBody $body -Stream
exit $ec
