/*
 * Copyright (c) 1992-1998 NeXT Software, Inc.
 *
 * Adaptec AIC-6X60 SCSI controller inline functions.
 *
 * HISTORY
 *
 * 28 Mar 1998 Adapted from AHA-1542 driver
 *	Created.
 */

#import <driverkit/i386/ioPorts.h>

/*
 * Primitives to access the
 * board registers.
 */

static inline
void
aic_put_ctrl(
    unsigned short	base,
    aic_ctrl_reg_t	reg
)
{
    union {
	aic_ctrl_reg_t		reg;
	unsigned char		data;
    } tconv;

    tconv.reg = reg;

    outb(base + AIC_CTRL_REG_OFF, tconv.data);
}

static inline
aic_stat_reg_t
aic_get_stat(
    unsigned short	base
)
{
    union {
	aic_stat_reg_t		reg;
	unsigned char		data;
    } tconv;

    tconv.data = inb(base + AIC_STAT_REG_OFF);

    return (tconv.reg);
}

static inline
aic_intr_reg_t
aic_get_intr(
    unsigned short	base
)
{
    union {
	aic_intr_reg_t		reg;
	unsigned char		data;
    } tconv;

    tconv.data = inb(base + AIC_INTR_REG_OFF);

    return (tconv.reg);
}

static inline
void
aic_put_cmd(
    unsigned short	base,
    aic_cmd_reg_t	reg
)
{
    outb(base + AIC_CMD_REG_OFF, reg);
}

static inline
aic_cmd_reg_t
aic_get_cmd(
    unsigned short	base
)
{
    return (inb(base + AIC_CMD_REG_OFF));
}

/*
 * Functions built on top
 * of the primatives above.
 */

static inline
void
aic_clr_intr(
    unsigned short	base
)
{
    aic_ctrl_reg_t	ctrl = { 0 };

    ctrl.intr_clr = 1;

    aic_put_ctrl(base, ctrl);
}


static inline
boolean_t
aic_await_datain(
    IOEISAPortAddress	base,
    unsigned int	how_long
)
{
    aic_stat_reg_t	stat;

    do {
    	stat = aic_get_stat(base);
    } while (!stat.datain_full && how_long--);
    return how_long;
}


static inline
boolean_t
aic_get_bytes(
    IOEISAPortAddress	base,
    unsigned char	*addr,
    unsigned int	length
)
{
    while (length--) {
    	if (!aic_await_datain(base, 1000))
		return FALSE;
    	*addr++ = inb(base);
    }
    return TRUE;
}


/*
 *  24-bit accessor functions (with byte swapping)
 */
static inline void
aic_put_24(unsigned int source, volatile unsigned char *dest)
{
	dest[2] = source & 0xff;
	dest[1] = (source >> 8) & 0xff;
	dest[0] = (source >> 16) & 0xff;
}


static inline unsigned int
aic_get_24(volatile unsigned char *source)
{
	return (source[0] << 16) | (source[1] << 8) | source[2];
}


