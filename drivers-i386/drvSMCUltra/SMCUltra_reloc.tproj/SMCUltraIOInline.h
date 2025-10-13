/*
 * Copyright (c) 1998 NeXT Software, Inc.
 *
 * Low level IO inline expansions for
 * SMC EtherCard Plus Elite16 Ultra Adapter.
 *
 * HISTORY
 *
 * Mar 1998
 *	Created from SMC16 driver.
 */

#import <driverkit/i386/ioPorts.h>

#import "SMCUltraHdw.h"

#import "wd83C584.h"
#import "wd83C690.h"

/*
 * We use a union of all relevant registers so that we can declare
 * variables of a single type, yet access and return variables of
 * these multiple types easily.
 */
typedef union {
    bic_msr_t		msr;
    bic_icr_t		icr;
    bic_iar_t		iar;
    bic_bio_t		bio;
    bic_ear_t		ear;
    bic_irr_t		irr;
    bic_laar_t		laar;
    nic_cmd_reg_t	cmd_reg;
    nic_enh_reg_t	enh_reg;
    nic_istat_reg_t	istat_reg;
    nic_imask_reg_t	imask_reg;
    nic_tstat_reg_t	tstat_reg;
    nic_rcon_reg_t	rcon_reg;
    nic_tcon_reg_t	tcon_reg;
    nic_dcon_reg_t	dcon_reg;
    unsigned char	data;
    SMCUltra_off_t	offset;
}_reg_conv_t;

/*
 * Access to 83C584 registers.
 */

static __inline__
bic_msr_t
get_msr(
    IOEISAPortAddress	base
)
{
    _reg_conv_t		_conv;

    _conv.data = inb(base + SMCULTRA_BIC_OFF + BIC_MSR_OFF);

    return (_conv.msr);
}

static __inline__
void
put_msr(
    bic_msr_t		reg,
    IOEISAPortAddress	base
)
{
    _reg_conv_t		_conv;

    _conv.msr = reg;

    outb(base + SMCULTRA_BIC_OFF + BIC_MSR_OFF, _conv.data);
}

static __inline__
bic_icr_t
get_icr(
    IOEISAPortAddress	base
)
{
    _reg_conv_t		_conv;

    _conv.data = inb(base + SMCULTRA_BIC_OFF + BIC_ICR_OFF);

    return (_conv.icr);
}

static __inline__
void
put_icr(
    bic_icr_t		reg,
    IOEISAPortAddress	base
)
{
    _reg_conv_t		_conv;

    _conv.icr = reg;

    outb(base + SMCULTRA_BIC_OFF + BIC_ICR_OFF, _conv.data);
}

static __inline__
bic_laar_t
get_laar(
    IOEISAPortAddress	base
)
{
    _reg_conv_t		_conv;

    _conv.data = inb(base + SMCULTRA_BIC_OFF + BIC_LAAR_OFF);

    return (_conv.laar);
}

static __inline__
void
put_laar(
    bic_laar_t		reg,
    IOEISAPortAddress	base
)
{
    _reg_conv_t		_conv;

    _conv.laar = reg;

    outb(base + SMCULTRA_BIC_OFF + BIC_LAAR_OFF, _conv.data);
}

/*
 * NIC Register page selection
 */
#define REG_PAGE0	0
#define REG_PAGE1	1
#define REG_PAGE2	2

static __inline__
int
sel_reg_page(
    int			page,
    IOEISAPortAddress	base
)
{
    _reg_conv_t	_conv;

    _conv.data = inb(base + SMCULTRA_NIC_OFF + NIC_CMD_REG_OFF);
    _conv.cmd_reg.psel = page;
    outb(base + SMCULTRA_NIC_OFF + NIC_CMD_REG_OFF, _conv.data);

    return page;
}

/*
 * Command register access
 */
static __inline__
nic_cmd_reg_t
get_cmd_reg(
    IOEISAPortAddress	base
)
{
    _reg_conv_t		_conv;

    _conv.data = inb(base + SMCULTRA_NIC_OFF + NIC_CMD_REG_OFF);

    return (_conv.cmd_reg);
}

static __inline__
void
put_cmd_reg(
    nic_cmd_reg_t	reg,
    IOEISAPortAddress	base
)
{
    _reg_conv_t		_conv;

    _conv.cmd_reg = reg;

    outb(base + SMCULTRA_NIC_OFF + NIC_CMD_REG_OFF, _conv.data);
}

/*
 * Interrupt status register access
 */
static __inline__
nic_istat_reg_t
get_istat_reg(
    IOEISAPortAddress	base
)
{
    _reg_conv_t		_conv;

    _conv.data = inb(base + SMCULTRA_NIC_OFF + NIC_ISTAT_REG_OFF);

    return (_conv.istat_reg);
}

static __inline__
void
put_istat_reg(
    nic_istat_reg_t	reg,
    IOEISAPortAddress	base
)
{
    _reg_conv_t		_conv;

    _conv.istat_reg = reg;

    outb(base + SMCULTRA_NIC_OFF + NIC_ISTAT_REG_OFF, _conv.data);
}

/*
 * Receive configuration register access
 */
static __inline__
nic_rcon_reg_t
get_rcon_reg(
    IOEISAPortAddress	base
)
{
    _reg_conv_t		_conv;

    (void)sel_reg_page(REG_PAGE2, base);
    _conv.data = inb(base + SMCULTRA_NIC_OFF + NIC_RCON_REG_OFF);
    (void)sel_reg_page(REG_PAGE0, base);

    return (_conv.rcon_reg);
}

static __inline__
void
put_rcon_reg(
    nic_rcon_reg_t	reg,
    IOEISAPortAddress	base
)
{
    _reg_conv_t		_conv;

    _conv.rcon_reg = reg;

    (void)sel_reg_page(REG_PAGE2, base);
    outb(base + SMCULTRA_NIC_OFF + NIC_RCON_REG_OFF, _conv.data);
    (void)sel_reg_page(REG_PAGE0, base);
}

/*
 * Simple register access macros
 */
#define put_bound_reg(val, base) \
    outb((base) + SMCULTRA_NIC_OFF + NIC_BOUND_REG_OFF, (val))

#define put_rstart_reg(val, base) \
    outb((base) + SMCULTRA_NIC_OFF + NIC_RSTART_REG_OFF, (val))

#define put_rstop_reg(val, base) \
    outb((base) + SMCULTRA_NIC_OFF + NIC_RSTOP_REG_OFF, (val))

#define put_curr_reg(val, base) \
    outb((base) + SMCULTRA_NIC_OFF + NIC_CURR_REG_OFF, (val))

#define put_tstart_reg(val, base) \
    outb((base) + SMCULTRA_NIC_OFF + NIC_TSTART_REG_OFF, (val))

