/*
 * Copyright (c) 1993-1996 NeXT Software, Inc.
 *
 * SMC EtherCard Plus Elite16 adapters.
 *
 * HISTORY
 *
 * 26 Jan 1993 
 *	Created.
 */
 
typedef unsigned char	SMC16_off_t;
typedef unsigned int	SMC16_len_t;

/*
 * Hardware Board ID
 */
#define SMC16_REV(bid)		(((bid) & 0x1E) >> 1)
#define SMC16_LARGE_RAM(bid)	(((bid) & 0x40) != 0)

/*
 * IO offset to Bus Interface Chip
 */
#define SMC16_BIC_OFF	0x00

/*
 * IO offset to Network Interface Chip
 */
#define SMC16_NIC_OFF	0x10

