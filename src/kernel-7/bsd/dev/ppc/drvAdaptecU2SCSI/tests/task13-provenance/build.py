from pathlib import Path
import tarfile,io,json,hashlib,subprocess,sys
root=Path.cwd();task=root/'tools/binrecon/out/adaptecu2scsi-ppc/task13';prefix='src/kernel-7/bsd/dev/ppc/drvAdaptecU2SCSI/'
rev=subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip();batch=sys.argv[1]
sources=[n for n in ('AdaptecU2CHIMTransport.c','AdaptecU2CHIMAPI.c') if (root/prefix/n).exists()]
names=sources+['AdaptecU2CHIMTypes.h','AdaptecU2CHIM.h','AdaptecU2CHIMPrivate.h','OSMFunctions.h','AdaptecU2SCSI.h','AdaptecU2SCSIPrivate.h'];inputs={}
with tarfile.open(task/(batch+'-inputs.tar'),'w',format=tarfile.USTAR_FORMAT) as stream:
 for name in names:
  raw=(root/prefix/name).read_bytes();data=raw.replace(b'\r\n',b'\n');digest=lambda b:hashlib.sha256(b).hexdigest().upper()
  inputs[name]={'working_sha256':digest(raw),'staged_sha256':digest(data),'normalized_working_sha256':digest(data)}
  member=tarfile.TarInfo(name);member.size=len(data);stream.addfile(member,io.BytesIO(data))
(task/(batch+'-inputs.json')).write_text(json.dumps({'source_revision':rev,'work_in_progress':True,'inputs':inputs},indent=2)+'\n')
guest='/private/tmp/adaptecu2scsi-task13';kernel='/private/tmp/adaptecu2scsi-task2/src/kernel-7';dest=guest+'/'+batch+'-native'
script=f'''set -eu
export PATH=/private/tmp/adaptecu2scsi-task2/stage/usr/bin:/build/tools/bin:/usr/bin:/bin:/usr/sbin:/sbin
export CONFIG_DIR=/build/tools/bin
export AU2_SHA256=/private/tmp/adaptecu2scsi-task2/sha256sum
export AU2_SOURCE_REVISION={rev}
cd {guest}
mkdir {batch}-inputs
cd {batch}-inputs
tar xf ../{batch}-inputs.tar
for source in {' '.join(names)}; do cp "$source" {kernel}/bsd/dev/ppc/drvAdaptecU2SCSI/"$source"; done
cd {kernel}
/bin/sh bsd/dev/ppc/drvAdaptecU2SCSI/tests/build-objects.sh {dest} {' '.join('bsd/dev/ppc/drvAdaptecU2SCSI/'+n for n in sources)}
for source in {' '.join(names)}; do "$AU2_SHA256" bsd/dev/ppc/drvAdaptecU2SCSI/"$source"; done > {dest}/source-inputs.sha256
for source in {' '.join(names[len(sources):])}; do "$AU2_SHA256" bsd/dev/ppc/drvAdaptecU2SCSI/"$source"; done > {dest}/header-inputs.sha256
cd {guest}
tar cf {batch}-products.tar {batch}-native
'''
(task/('build-'+batch+'.sh')).write_text(script)
