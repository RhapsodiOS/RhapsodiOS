/*
 * Copyright (c) 1992-1996 NeXT Software, Inc.
 *
 * Adaptec AHA-1542 SCSI controller inline functions.
 *
 * HISTORY
 *
 * 12 July 1992 David E. Bohman at NeXT
 *	Created.
 */

#import <driverkit/i386/ioPorts.h>

/*
 * Primitives to access the
 * board registers.
 */

static inline
void
aha_put_ctrl(
    unsigned short	base,
    aha_ctrl_reg_t	reg
)
{
    union {
	aha_ctrl_reg_t		reg;
	unsigned char		data;
    } tconv;
    
    tconv.reg = reg;

    outb(base + AHA_CTRL_REG_OFF, tconv.data);
}

static inline
aha_stat_reg_t
aha_get_stat(
    unsigned short	base
)
{
    union {
	aha_stat_reg_t		reg;
	unsigned char		data;
    } tconv;

    tconv.data = inb(base + AHA_STAT_REG_OFF);

    return (tconv.reg);
}

static inline
aha_intr_reg_t
aha_get_intr(
    unsigned short	base
)
{
    union {
	aha_intr_reg_t		reg;
	unsigned char		data;
    } tconv;

    tconv.data = inb(base + AHA_INTR_REG_OFF);

    return (tconv.reg);
}

static inline
void
aha_put_cmd(
    unsigned short	base,
    aha_cmd_reg_t	reg
)
{
    outb(base + AHA_CMD_REG_OFF, reg);
}

static inline
aha_cmd_reg_t
aha_get_cmd(
    unsigned short	base
)
{
    return (inb(base + AHA_CMD_REG_OFF));
}

/*
 * Functions built on top
 * of the primatives above.
 */

static inline
void
aha_clr_intr(
    unsigned short	base
)
{
    aha_ctrl_reg_t	ctrl = { 0 };

    ctrl.intr_clr = 1;

    aha_put_ctrl(base, ctrl);
}


static inline
boolean_t
aha_await_datain(
    IOEISAPortAddress	base,
    unsigned int	how_long
)
{
    aha_stat_reg_t	stat;
 
    do {
    	stat = aha_get_stat(base);
    } while (!stat.datain_full && how_long--);
    return how_long;
}


static inline
boolean_t
aha_get_bytes(
    IOEISAPortAddress	base,
    unsigned char	*addr,
    unsigned int	length
)
{
    while (length--) {
    	if (!aha_await_datain(base, 1000))
		return FALSE;
    	*addr++ = inb(base);
    }
    return TRUE;
}


/*
 *  24-bit accessor functions (with byte swapping)
 */
static inline void
aha_put_24(unsigned int source, volatile unsigned char *dest)
{
	dest[2] = source & 0xff;
	dest[1] = (source >> 8) & 0xff;
	dest[0] = (source >> 16) & 0xff;
}


static inline unsigned int
aha_get_24(volatile unsigned char *source)
{
	return (source[0] << 16) | (source[1] << 8) | source[2];
}


