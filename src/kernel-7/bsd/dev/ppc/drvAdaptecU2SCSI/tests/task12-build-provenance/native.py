from pathlib import Path
import tarfile,io,json,hashlib,subprocess,sys
r=Path.cwd();t=r/'tools/binrecon/out/adaptecu2scsi-ppc/task12';prefix='src/kernel-7/bsd/dev/ppc/drvAdaptecU2SCSI/';rev=sys.argv[2] if len(sys.argv)>2 else subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip();batch=sys.argv[1];rev=subprocess.check_output(["git","rev-parse",rev],text=True).strip()
names=['AdaptecU2CHIMHIM.c','AdaptecU2CHIMTypes.h','AdaptecU2CHIM.h','AdaptecU2CHIMPrivate.h','OSMFunctions.h','AdaptecU2SCSI.h','AdaptecU2SCSIPrivate.h'];inputs={}
with tarfile.open(t/(batch+'-inputs.tar'),'w',format=tarfile.USTAR_FORMAT) as a:
 for name in names:
  raw=(r/prefix/name).read_bytes();b=raw.replace(b'\r\n',b'\n')
  inputs[name]={'working_sha256':hashlib.sha256(raw).hexdigest().upper(),'staged_sha256':hashlib.sha256(b).hexdigest().upper(),'normalized_working_sha256':hashlib.sha256(b).hexdigest().upper()};i=tarfile.TarInfo(name);i.size=len(b);a.addfile(i,io.BytesIO(b))
(t/(batch+'-inputs.json')).write_text(json.dumps({'source_revision':rev,'work_in_progress':True,'inputs':inputs},indent=2)+'\n')
g='/private/tmp/adaptecu2scsi-task12';k='/private/tmp/adaptecu2scsi-task2/src/kernel-7';out=g+'/'+batch+'-native'
s=f'''set -eu
export PATH=/private/tmp/adaptecu2scsi-task2/stage/usr/bin:/build/tools/bin:/usr/bin:/bin:/usr/sbin:/sbin
export CONFIG_DIR=/build/tools/bin
export AU2_SHA256=/private/tmp/adaptecu2scsi-task2/sha256sum
export AU2_SOURCE_REVISION={rev}
cd {g}
mkdir {batch}-inputs
cd {batch}-inputs
tar xf ../{batch}-inputs.tar
for source in {' '.join(names)}; do cp "$source" {k}/bsd/dev/ppc/drvAdaptecU2SCSI/"$source"; done
cd {k}
/bin/sh bsd/dev/ppc/drvAdaptecU2SCSI/tests/build-objects.sh {out} bsd/dev/ppc/drvAdaptecU2SCSI/AdaptecU2CHIMHIM.c
for source in {' '.join(names)}; do "$AU2_SHA256" bsd/dev/ppc/drvAdaptecU2SCSI/"$source"; done > {out}/source-inputs.sha256
for source in {' '.join(names[1:])}; do "$AU2_SHA256" bsd/dev/ppc/drvAdaptecU2SCSI/"$source"; done > {out}/header-inputs.sha256
cd {g}
tar cf {batch}-products.tar {batch}-native
'''
(t/('build-'+batch+'.sh')).write_text(s)

