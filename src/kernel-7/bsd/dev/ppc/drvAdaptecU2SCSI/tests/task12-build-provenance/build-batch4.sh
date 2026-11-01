set -eu
export PATH=/private/tmp/adaptecu2scsi-task2/stage/usr/bin:/build/tools/bin:/usr/bin:/bin:/usr/sbin:/sbin
export CONFIG_DIR=/build/tools/bin
export AU2_SHA256=/private/tmp/adaptecu2scsi-task2/sha256sum
export AU2_SOURCE_REVISION=608e9f524deeaaa79910e484ee9c5008be3f863c
cd /private/tmp/adaptecu2scsi-task12
mkdir batch4-inputs
cd batch4-inputs
tar xf ../batch4-inputs.tar
for source in AdaptecU2CHIMHIM.c AdaptecU2CHIMTypes.h AdaptecU2CHIM.h AdaptecU2CHIMPrivate.h OSMFunctions.h AdaptecU2SCSI.h AdaptecU2SCSIPrivate.h; do cp "$source" /private/tmp/adaptecu2scsi-task2/src/kernel-7/bsd/dev/ppc/drvAdaptecU2SCSI/"$source"; done
cd /private/tmp/adaptecu2scsi-task2/src/kernel-7
/bin/sh bsd/dev/ppc/drvAdaptecU2SCSI/tests/build-objects.sh /private/tmp/adaptecu2scsi-task12/batch4-native bsd/dev/ppc/drvAdaptecU2SCSI/AdaptecU2CHIMHIM.c
for source in AdaptecU2CHIMHIM.c AdaptecU2CHIMTypes.h AdaptecU2CHIM.h AdaptecU2CHIMPrivate.h OSMFunctions.h AdaptecU2SCSI.h AdaptecU2SCSIPrivate.h; do "$AU2_SHA256" bsd/dev/ppc/drvAdaptecU2SCSI/"$source"; done > /private/tmp/adaptecu2scsi-task12/batch4-native/source-inputs.sha256
for source in AdaptecU2CHIMTypes.h AdaptecU2CHIM.h AdaptecU2CHIMPrivate.h OSMFunctions.h AdaptecU2SCSI.h AdaptecU2SCSIPrivate.h; do "$AU2_SHA256" bsd/dev/ppc/drvAdaptecU2SCSI/"$source"; done > /private/tmp/adaptecu2scsi-task12/batch4-native/header-inputs.sha256
cd /private/tmp/adaptecu2scsi-task12
tar cf batch4-products.tar batch4-native
