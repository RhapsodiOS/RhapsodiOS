/* host_includes shim: verbatim copy of src/kernel-7/bsd/dev/i386/disk.h
 * with struct fdisk_part's relsect/numsect narrowed back to their original
 * fixed 32-bit on-disk widths (see BOOTEFI_HOST_NARROWED below).  A raw
 * MBR partition entry is a fixed 16 bytes (8 status/CHS bytes + two
 * 4-byte fields); on the original 32-bit host `unsigned long` matched
 * that.  On this LP64 host it's 8 bytes, so sizeof(struct fdisk_part)
 * silently grows from 16 to 24 -- disk.c's `fd++` scan over
 * blk0->parts[FDISK_NPART] then reads each subsequent MBR entry 8 bytes
 * short, and any partition past the first is read from the wrong offset
 * entirely (observed: the second, 0xA7 Rhapsody, entry in a hybrid
 * MBR+ESP image was missed, part_offset stayed 0, and the label read
 * failed). */
/*
 * Copyright (c) 1999 Apple Computer, Inc. All rights reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 * 
 * Portions Copyright (c) 1999 Apple Computer, Inc.  All Rights
 * Reserved.  This file contains Original Code and/or Modifications of
 * Original Code as defined in and that are subject to the Apple Public
 * Source License Version 1.1 (the "License").  You may not use this file
 * except in compliance with the License.  Please obtain a copy of the
 * License at http://www.apple.com/publicsource and read it before using
 * this file.
 * 
 * The Original Code and all software distributed under the License are
 * distributed on an "AS IS" basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE OR NON- INFRINGEMENT.  Please see the
 * License for the specific language governing rights and limitations
 * under the License.
 * 
 * @APPLE_LICENSE_HEADER_END@
 */

/*
 * Copyright (c) 1992 NeXT Computer, Inc.
 *
 * IBM PC disk partitioning data structures.
 *
 * HISTORY
 *
 * 8 July 1992 ? at NeXT
 *	Created.
 */
 
#ifdef	DRIVER_PRIVATE

#define DISK_BLK0	0		/* blkno of boot block */
#define DISK_BLK0SZ	512		/* size of boot block */
#define DISK_BOOTSZ	446		/* size of boot code in boot block */
#define	DISK_SIGNATURE	0xAA55		/* signature of the boot record */
#define FDISK_NPART	4		/* number of entries in fdisk table */
#define FDISK_ACTIVE	0x80		/* indicator of active partition */
#define FDISK_NEXTNAME	0xA7		/* indicator of NeXT partition */
#define FDISK_DOS12	0x01            /* 12-bit fat < 10MB dos partition */
#define FDISK_DOS16S	0x04            /* 16-bit fat < 32MB dos partition */
#define FDISK_DOSEXT	0x05            /* extended dos partition */
#define FDISK_DOS16B	0x06            /* 16-bit fat >= 32MB dos partition */

/*
 * Format of fdisk partion entry (if present).
 */
struct fdisk_part {
    unsigned char	bootid;		/* bootable or not */
    unsigned char	beghead;	/* begining head, sector, cylinder */
    unsigned char	begsect;	/* begcyl is a 10-bit number */
    unsigned char	begcyl;		/* High 2 bits are in begsect */
    unsigned char	systid;		/* OS type */
    unsigned char	endhead;	/* ending head, sector, cylinder */
    unsigned char	endsect;	/* endcyl is a 10-bit number */
    unsigned char	endcyl;		/* High 2 bits are in endsect */
    unsigned int	relsect;	/* partion physical offset on disk */ /* BOOTEFI_HOST_NARROWED: was unsigned long (8 bytes on LP64); on-disk field is 32-bit */
    unsigned int	numsect;	/* number of sectors in partition */ /* BOOTEFI_HOST_NARROWED: was unsigned long (8 bytes on LP64); on-disk field is 32-bit */
};

/*
 * Format of boot block.
 */
struct disk_blk0 {
    unsigned char	bootcode[DISK_BOOTSZ];
    unsigned char	parts[FDISK_NPART][sizeof (struct fdisk_part)];
    unsigned short	signature;
};

#endif	/* DRIVER_PRIVATE */
