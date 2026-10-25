set -eu
export PATH=/private/tmp/adaptecu2scsi-task2/stage/usr/bin:/build/tools/bin:/usr/bin:/bin:/usr/sbin:/sbin
export CONFIG_DIR=/build/tools/bin
export AU2_SHA256=/private/tmp/adaptecu2scsi-task2/sha256sum
export AU2_SOURCE_REVISION=92691668a38e846d1ba853f7b969eff25bb28dde
cd /private/tmp/adaptecu2scsi-task13
mkdir b10-inputs
cd b10-inputs
tar xf ../b10-inputs.tar
for source in AdaptecU2CHIMTransport.c AdaptecU2CHIMTypes.h AdaptecU2CHIM.h AdaptecU2CHIMPrivate.h OSMFunctions.h AdaptecU2SCSI.h AdaptecU2SCSIPrivate.h; do cp "$source" /private/tmp/adaptecu2scsi-task2/src/kernel-7/bsd/dev/ppc/drvAdaptecU2SCSI/"$source"; done
cd /private/tmp/adaptecu2scsi-task2/src/kernel-7
/bin/sh bsd/dev/ppc/drvAdaptecU2SCSI/tests/build-objects.sh /private/tmp/adaptecu2scsi-task13/b10-native bsd/dev/ppc/drvAdaptecU2SCSI/AdaptecU2CHIMTransport.c
for source in AdaptecU2CHIMTransport.c AdaptecU2CHIMTypes.h AdaptecU2CHIM.h AdaptecU2CHIMPrivate.h OSMFunctions.h AdaptecU2SCSI.h AdaptecU2SCSIPrivate.h; do "$AU2_SHA256" bsd/dev/ppc/drvAdaptecU2SCSI/"$source"; done > /private/tmp/adaptecu2scsi-task13/b10-native/source-inputs.sha256
for source in AdaptecU2CHIMTypes.h AdaptecU2CHIM.h AdaptecU2CHIMPrivate.h OSMFunctions.h AdaptecU2SCSI.h AdaptecU2SCSIPrivate.h; do "$AU2_SHA256" bsd/dev/ppc/drvAdaptecU2SCSI/"$source"; done > /private/tmp/adaptecu2scsi-task13/b10-native/header-inputs.sha256
cd /private/tmp/adaptecu2scsi-task13
tar cf b10-products.tar b10-native
