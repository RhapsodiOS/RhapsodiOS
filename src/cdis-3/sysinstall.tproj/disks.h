/* disks.h -- sysinstall's candidate disks.  disks_list is Rhapsody only;
 * dev_disk_name has a host test. */

#ifndef DISKS_H
#define DISKS_H

/* Fills names ("hd0", "sd3") and sizes (in 512-byte sectors) with the
 * disks whose /dev/rhd0-3h or /dev/rsd0-7h opens, less the disk holding
 * the live root.  At most max; returns how many, or -1 if the live root
 * can't be stat()ed. */
int disks_list(char names[][8], unsigned long sizes[], int max);

/* The disk a block device's numbers name: major 3 is hd, 6 is sd, and the
 * unit is minor >> 3 (8 partitions a unit), so (3, 8), hd1a, gives "hd1".
 * 0, or -1 for any other major. */
int dev_disk_name(unsigned major, unsigned minor, char out[8]);

#endif
