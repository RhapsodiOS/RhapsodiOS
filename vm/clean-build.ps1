#Requires -Version 5.1
<#
.SYNOPSIS
  Remove configured /build outputs on the PPC guest, leaving /build/src in place.
.EXAMPLE
  powershell -File vm\clean-build.ps1
.NOTES
  Reuses the same Fresh topology checks as build-src.ps1 -Fresh: tools,
  bootstrap-root, repo, built, and state are deleted. SourceRoot is kept.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$VmDir = $PSScriptRoot
. (Join-Path $VmDir 'build-src-lib.ps1')
. (Join-Path $VmDir 'rhap-remote.ps1')

function Write-Die([string]$Message) {
    Write-RhapDie 'clean-build' $Message
}

$cfg = Get-RhapVmConfig -DiePrefix 'clean-build'
$ssh = Resolve-RhapTool -NameOrPath $cfg.Ssh -DiePrefix 'clean-build'
$sourceRoot = ConvertTo-RhapNormalizedRemotePath -Path "$($cfg.RemoteRoot)/src" -Name 'SourceRoot'

$freshCommand = New-RhapFreshCommand -RemoteRoot $cfg.RemoteRoot -SourceRoot $sourceRoot -Profile $cfg.ToolchainProfile -ToolsDir $cfg.ToolsDir -BootstrapRoot $cfg.BootstrapRoot -RepoDir $cfg.RepoDir -BuiltDir $cfg.BuiltDir -StateDir $cfg.StateDir

Write-Host 'clean-build: resetting configured outputs'
$ec = Invoke-RhapSshScript -Cfg $cfg -Ssh $ssh -ScriptBody $freshCommand -Stream
if ($ec -ne 0) {
    Write-Die "guest reset failed (exit $ec)"
}
Write-Host 'clean-build: complete'
