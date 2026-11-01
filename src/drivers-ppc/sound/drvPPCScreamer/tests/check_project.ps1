$ErrorActionPreference='Stop'
$driver=Split-Path $PSScriptRoot
$kernel=Join-Path $driver 'PPCScreamer.drvproj/PPCScreamer.lksproj'
$shared=Join-Path $driver '../drvPPCTASAudio/PPCTASAudio.drvproj/PPCTASAudio.lksproj'
foreach($level in @($driver,(Join-Path $driver 'PPCScreamer.drvproj'),$kernel)) {
    foreach($name in @('Makefile','Makefile.preamble','Makefile.postamble','PB.project')) {
        if(!(Test-Path (Join-Path $level $name))) {throw "Missing $level/$name"}
    }
    if((Get-Content (Join-Path $level 'Makefile.preamble') -Raw) -notmatch 'INCLUDED_ARCHS = ppc') {throw "Non-PPC project: $level"}
}
$make=(Get-Content (Join-Path $kernel 'Makefile') -Raw) -replace '\\\r?\n',' '
foreach($line in ([regex]::Matches($make,'(?m)^(?:CFILES|CLASSES|HFILES) = [^\r\n]*'))) {
    $files=($line.Value -replace '^[^=]+=','' -replace '\\','') -split '\s+'
    foreach($file in $files) {
        if($file -and !(Test-Path (Join-Path $kernel $file))) {
            if($file -notin @('PPCDBDMAAudio.c','TASTime.c') -or !(Test-Path (Join-Path $shared $file))) {throw "Missing source: $file"}
        }
    }
}
foreach($name in @('PPCDBDMAAudio.c','TASTime.c')) {
    if(Test-Path (Join-Path $kernel $name)) {throw "Copied canonical helper: $name"}
    if($make -notmatch [regex]::Escape($name)) {throw "Missing canonical source: $name"}
}
if((Get-Content (Join-Path $kernel 'Makefile.preamble') -Raw) -notmatch 'vpath %.c.*drvPPCTASAudio') {throw 'Missing canonical source search path'}
$metadata=Get-ChildItem $driver -Recurse -File | Where-Object {$_.Name -in @('Makefile','PB.project','Makefile.preamble')}
foreach($file in $metadata) {
    if((Get-Content $file.FullName -Raw) -match 'dpkg/control|INCLUDED_ARCHS[^\r\n]*i386') {throw "Incorrect metadata: $file"}
}
$table=Get-Content (Join-Path $driver 'PPCScreamer.drvproj/Default.table') -Raw
if($table -notmatch '"Matching" = "awacs davbus"' -or $table -match '"Server Name"') {throw 'Incorrect driver table'}
if((Get-Content (Join-Path $driver 'apk/pkginfo') -Raw) -notmatch 'arch = ppc-apple-rhapsody') {throw 'Incorrect package architecture'}
Write-Output 'Screamer project: source paths and PPC metadata passed'
