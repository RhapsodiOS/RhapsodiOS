/* Copyright (c) 1993 NeXT Computer, Inc.  All rights reserved.
 *
 * stblocksize.h   XXX this should be added to scsireg.h
 *
 * HISTORY
 * 18-Oct-93	Phillip Dibner at NeXT
 *	Created.
 */

#import <sys/types.h>

#define C6OP_RDBLKLIMS	0x05	/* read block limits */

struct read_blk_sz_reply {

#if	__BIG_ENDIAN__
	u_int	rbsr_rsvd:8,		/* byte 4 - reserved */
		rsbr_max_bll:24;	/* maximum block length limit */
	u_short	rsbr_min_bll;		/* minimum block length limit */
#elif	__LITTLE_ENDIAN__
	u_char	rbsr_rsvd;
	u_char	rbsr_max_bll2;
	u_char	rbsr_max_bll1;
	u_char	rbsr_max_bll0;
	u_char	rbsr_min_bll1;
	u_char	rbsr_min_bll0;
#else
#error	SCSI command / data structures are compiler sensitive
#endif
} read_blk_sz_reply_t;
