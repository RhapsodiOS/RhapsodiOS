/* disks.h -- sysinstall's candidate disks.  Rhapsody only; no host test. */

#ifndef DISKS_H
#define DISKS_H

/* Fills names ("hd0", "sd3") and sizes (in 512-byte sectors) with the
 * disks whose /dev/rhd0-3h or /dev/rsd0-7h opens, less the disk holding
 * the live root.  At most max; returns how many, or -1 if mount doesn't
 * say which disk holds the live root. */
int disks_list(char names[][8], unsigned long sizes[], int max);

#endif
