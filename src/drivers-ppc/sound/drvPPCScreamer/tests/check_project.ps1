$ErrorActionPreference='Stop'
$driver=Split-Path $PSScriptRoot
$kernel=Join-Path $driver 'PPCScreamer.drvproj/PPCScreamer.lksproj'
foreach($level in @($driver,(Join-Path $driver 'PPCScreamer.drvproj'),$kernel)) {
    foreach($name in @('Makefile','Makefile.preamble','Makefile.postamble','PB.project')) {
        if(!(Test-Path (Join-Path $level $name))) {throw "Missing $level/$name"}
    }
    if((Get-Content (Join-Path $level 'Makefile.preamble') -Raw) -notmatch 'INCLUDED_ARCHS = ppc') {throw "Non-PPC project: $level"}
}
$make=Get-Content (Join-Path $kernel 'Makefile') -Raw
foreach($line in ([regex]::Matches($make,'(?m)^(?:CFILES|CLASSES|HFILES) = (?:[^\r\n]*(?:\\\r?\n))?[^\r\n]*'))) {
    $files=($line.Value -replace '^[^=]+=','' -replace '\\','') -split '\s+'
    foreach($file in $files) {if($file -and !(Test-Path (Join-Path $kernel $file))) {throw "Missing source: $file"}}
}
$table=Get-Content (Join-Path $driver 'PPCScreamer.drvproj/Default.table') -Raw
if($table -notmatch '"Matching" = "awacs davbus"' -or $table -match '"Server Name"') {throw 'Incorrect driver table'}
if((Get-Content (Join-Path $driver 'apk/pkginfo') -Raw) -notmatch 'arch = ppc-apple-rhapsody') {throw 'Incorrect package architecture'}
Write-Output 'Screamer project: source paths and PPC metadata passed'
