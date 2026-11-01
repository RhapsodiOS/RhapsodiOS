param([string]$Batch)
$ErrorActionPreference='Stop'
$taskRoot=(Get-Location).Path+'/tools/binrecon/out/adaptecu2scsi-ppc/task13'
& tools/binrecon/out/adaptecu2scsi-ppc/venv/Scripts/python.exe tools/binrecon/out/adaptecu2scsi-ppc/task13/build.py $Batch
& tools/binrecon/out/adaptecu2scsi-ppc/guest/remote.ps1 -Upload ($taskRoot+'/'+$Batch+'-inputs.tar') -Remote ('mkdir -p /private/tmp/adaptecu2scsi-task13; cat > /private/tmp/adaptecu2scsi-task13/'+$Batch+'-inputs.tar')
& tools/binrecon/out/adaptecu2scsi-ppc/guest/remote.ps1 -Script ($taskRoot+'/build-'+$Batch+'.sh') *> ($taskRoot+'/'+$Batch+'-native.log')
Get-Content ($taskRoot+'/'+$Batch+'-native.log')
& D:/RhapsodiOS/vm/work/kernel-samurai-followup-20261015/fetch-binary.ps1 -Port 2293 -RemotePath ('/private/tmp/adaptecu2scsi-task13/'+$Batch+'-products.tar') -Destination ($taskRoot+'/'+$Batch+'-products.tar')
tar -xf ($taskRoot+'/'+$Batch+'-products.tar') -C $taskRoot
