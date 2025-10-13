/*
 * Copyright (c) 1998 NeXT Software, Inc.
 *
 * SMC EtherCard Plus Elite16 Ultra adapters.
 *
 * HISTORY
 *
 * Mar 1998
 *	Created from SMC16 driver.
 */

typedef unsigned char	SMCUltra_off_t;
typedef unsigned int	SMCUltra_len_t;

/*
 * Hardware Board ID
 */
#define SMCULTRA_REV(bid)		(((bid) & 0x1E) >> 1)
#define SMCULTRA_LARGE_RAM(bid)		(((bid) & 0x40) != 0)

/*
 * IO offset to Bus Interface Chip
 */
#define SMCULTRA_BIC_OFF	0x00

/*
 * IO offset to Network Interface Chip
 */
#define SMCULTRA_NIC_OFF	0x10

