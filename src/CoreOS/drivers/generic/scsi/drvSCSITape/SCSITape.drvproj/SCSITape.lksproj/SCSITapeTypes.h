/*	Copyright (c) 1993 NeXT Computer, Inc.  All rights reserved.
 *
 * SCSITapeTypes.h - Data types for SCSITape Class
 *
 * HISTORY
 * 5-Apr-95    Phillip Dibner at NeXT
 *      Created.
 */

#import <driverkit/IODevice.h>
#import <driverkit/scsiTypes.h>

#define NST 4		// Number of SCSI Tape units

/*
 * dev_t to tape unit, other minor device bits
 */
#define	ST_UNIT(dev)		(minor(dev) >> 3)
#define ST_RETURN(dev)		(minor(dev) & 1) 	/* bit 0 true - no */
							/* rewind on close */
#define ST_EXABYTE(dev)		(minor(dev) & 2)	/* bit 1 true - */
							/* Exabyte drive */

/*
 * I/O timouts in seconds
 */

#define ST_IOTO_NORM	120		/* default */
#define ST_IOTO_RWD	(5 * 60)	/* rewind command */
#define ST_IOTO_SENSE	1		/* request sense */
#define ST_IOTO_SPR	60		/* space records */
#define ST_IOTO_SPFM	(10 * 60)	/* space file marks. 10 minutes */
					/* PER FILE MARK TO SPACE. */
/*
 *   str_status values   XXX not used yet in current implementation.
 */
#define STRST_GOOD 	0		/* OK */
#define STRST_BADST	1		/* bad SCSI status */
#define STRST_IOTO	2		/* I/O timeout */
#define STRST_VIOL	3		/* SCSI bus violation */
#define STRST_SELTO	4		/* selection timeout */
#define STRST_CMDREJ	5		/* driver command reject */
#define STRST_OTHER	6		/* other error */



/*
 * Vendor Unique mode select data for Exabyte drive
 */
struct exabyte_vudata {
	u_int		ct:1,		/* cartridge type */
			rsvd1:1,
			nd:1,		/* no disconnect during data xfer */
			rsvd2:1,
			nbe:1,		/* No Busy Enable */
			ebd:1,		/* Even Byte Disconnect */
			pe:1,		/* Parity Enable */
			nal:1,		/* No Auto Load */
			rsvd3:7,
			p5:1,		/* P5 cartridge */
			motion_thresh:8,	/* motion threshold */
			recon_thresh:8;	/* reconnect threshold */
	u_char		gap_thresh;	/* gap threshold */
};

#define MSP_VU_EXABYTE	0x05		/* # vendor unique bytes for mode  */
					/*     select/sense */


/*
 * Return codes from initSCSITape:
 */
typedef enum {
	STR_GOOD,			// init succeeded
	STR_NOTATAPE,			// not a SCSI tape
	STR_SELECTTO,			// selection timeout
	STR_ERROR			// other error
} stInitReturn_t;
