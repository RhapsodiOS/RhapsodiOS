param([Parameter(Mandatory=$true)][string]$BodyPath)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'rhap-remote.ps1')
$cfg = Get-RhapVmConfig -DiePrefix 'guest-current'
$cfg.Host = '127.0.0.1'
$options = [System.Collections.Generic.List[string]]::new()
for ($i = 0; $i -lt $script:RhapLegacySshOptions.Count; $i++) {
    if ($script:RhapLegacySshOptions[$i] -eq '-o' -and $i + 1 -lt $script:RhapLegacySshOptions.Count -and $script:RhapLegacySshOptions[$i + 1] -match '^Port=') { $i++; continue }
    $options.Add($script:RhapLegacySshOptions[$i])
}
$options.Add('-o'); $options.Add('Port=4921')
$options.Add('-o'); $options.Add('ConnectTimeout=6')
$script:RhapLegacySshOptions = @($options)
$ssh = Resolve-RhapTool -NameOrPath $cfg.Ssh -DiePrefix 'guest-current'
Invoke-RhapSshCapture -Cfg $cfg -Ssh $ssh -ScriptBody (Get-Content -LiteralPath $BodyPath -Raw) | Out-Null
$r = $script:RhapLastSshCapture
Write-Host $r.Stdout
if ($r.Stderr) { Write-Host '--- stderr ---'; Write-Host $r.Stderr }
exit $r.ExitCode
