<#
Run a shell script on the build guest, or copy one file back from it.

  powershell -NoProfile -File vm\guest-remote.ps1 -Run vm\build-i386-e100.sh
  powershell -NoProfile -File vm\guest-remote.ps1 -Fetch /build/out/x.apk -To vm\work\x.apk

-Fetch sends the file as a hex dump on stdout. This guest's sshd only
speaks the legacy algorithms rhap-remote.ps1 sets up, and modern scp cannot
talk to it at all (vm/README.md), so there is no binary channel to use.
#>
param(
    [string]$Run,
    [string]$Fetch,
    [string]$To
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'rhap-remote.ps1')

if ([string]::IsNullOrEmpty($Run) -eq [string]::IsNullOrEmpty($Fetch)) {
    Write-RhapDie 'guest-remote' 'give exactly one of -Run or -Fetch'
}
$cfg = Get-RhapVmConfig -DiePrefix 'guest-remote'
$ssh = Resolve-RhapTool -NameOrPath $cfg.Ssh -DiePrefix 'guest-remote'

if ($Run) {
    $body = Get-Content -LiteralPath $Run -Raw
    Invoke-RhapSshCapture -Cfg $cfg -Ssh $ssh -ScriptBody $body | Out-Null
    $r = $script:RhapLastSshCapture
    Write-Host $r.Stdout
    if ($r.Stderr) { Write-Host '--- stderr ---'; Write-Host $r.Stderr }
    exit $r.ExitCode
}

if ([string]::IsNullOrEmpty($To)) { Write-RhapDie 'guest-remote' '-Fetch needs -To' }
$body = @'
f='__FILE__'
wc -c < "$f" || exit 1
hexdump -v -e '32/1 "%02x" "\n"' "$f" || exit 1
'@
$body = $body.Replace('__FILE__', $Fetch)
Invoke-RhapSshCapture -Cfg $cfg -Ssh $ssh -ScriptBody $body | Out-Null
$r = $script:RhapLastSshCapture
if ($r.ExitCode -ne 0) { Write-RhapDie 'guest-remote' "reading $Fetch failed: $($r.Stderr)" }

$lines = @($r.Stdout -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
$size = [int64]$lines[0]
$hex = -join ($lines | Select-Object -Skip 1)
$bytes = New-Object byte[] ($hex.Length / 2)
for ($i = 0; $i -lt $bytes.Length; $i++) {
    $bytes[$i] = [Convert]::ToByte($hex.Substring(2 * $i, 2), 16)
}
if ($bytes.Length -ne $size) {
    Write-RhapDie 'guest-remote' "got $($bytes.Length) bytes but the guest says $size"
}
$dest = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($To)
[IO.File]::WriteAllBytes($dest, $bytes)
Write-Host "fetched $size bytes to $dest"
