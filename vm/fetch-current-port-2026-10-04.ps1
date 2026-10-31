param([Parameter(Mandatory=$true)][string]$RemotePath,[Parameter(Mandatory=$true)][string]$Destination)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'rhap-remote.ps1')
$cfg = Get-RhapVmConfig -DiePrefix 'guest-fetch-current'
$cfg.Host = '127.0.0.1'
$options = [System.Collections.Generic.List[string]]::new()
for ($i = 0; $i -lt $script:RhapLegacySshOptions.Count; $i++) {
    if ($script:RhapLegacySshOptions[$i] -eq '-o' -and $i + 1 -lt $script:RhapLegacySshOptions.Count -and $script:RhapLegacySshOptions[$i + 1] -match '^Port=') { $i++; continue }
    $options.Add($script:RhapLegacySshOptions[$i])
}
$options.Add('-o'); $options.Add('Port=4921'); $options.Add('-o'); $options.Add('ConnectTimeout=8')
$script:RhapLegacySshOptions = @($options)
$body = "wc -c < '$RemotePath' || exit 1`nhexdump -v -e '32/1 `"%02x`" `"\n`"' '$RemotePath' || exit 1`n"
$ssh = Resolve-RhapTool -NameOrPath $cfg.Ssh -DiePrefix 'guest-fetch-current'
Invoke-RhapSshCapture -Cfg $cfg -Ssh $ssh -ScriptBody $body | Out-Null
$r = $script:RhapLastSshCapture
if ($r.ExitCode -ne 0) { throw "reading $RemotePath failed: $($r.Stderr)" }
$lines = @($r.Stdout -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
$size = [int64]$lines[0]
$hex = -join ($lines | Select-Object -Skip 1)
if (($hex.Length % 2) -ne 0) { throw 'odd-length hex stream' }
$bytes = New-Object byte[] ($hex.Length / 2)
for ($i = 0; $i -lt $bytes.Length; $i++) { $bytes[$i] = [Convert]::ToByte($hex.Substring($i * 2, 2), 16) }
if ($bytes.Length -ne $size) { throw "received $($bytes.Length) bytes, expected $size" }
$dest = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Destination)
[IO.File]::WriteAllBytes($dest, $bytes)
Write-Host "fetched $size bytes to $dest"
Get-FileHash -Algorithm SHA256 -LiteralPath $dest
