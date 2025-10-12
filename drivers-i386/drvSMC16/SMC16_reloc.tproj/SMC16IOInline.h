/*
 * Copyright (c) 1993-1996 NeXT Software, Inc.
 *
 * Low level IO inline expansions for
 * SMC EtherCard Plus Elite16 Adapter.
 *
 * HISTORY
 *
 * 26 Jan 1993 
 *	Created.
 */

#import <driverkit/i386/ioPorts.h>

#import "SMC16Hdw.h"

#import "wd83C584.h"
#import "wd83C690.h"

/*
 * We use a union of all relevant registers so that we can declare
 * variables of a single type, yet access and return variables of
 * these multiple types easily.  Typically, we use the last 2 elements
 * in our inb() calls.
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
    SMC16_off_t		offset;
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
    
    _conv.data = inb(base + SMC16_BIC_OFF + BIC_MSR_OFF);
    
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

    outb(base + SMC16_BIC_OFF + BIC_MSR_OFF, _conv.data);
}

static __inline__
bic_icr_t
get_icr(
    IOEISAPortAddress	base
)
{
    _reg_conv_t		_conv;
    
    _conv.data = inb(base + SMC16_BIC_OFF + BIC_ICR_OFF);
    
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

    outb(base + SMC16_BIC_OFF + BIC_ICR_OFF, _conv.data);
}

static __inline__
bic_irr_t
get_irr(
    IOEISAPortAddress	base
)
{
    _reg_conv_t		_conv;
    
    _conv.data = inb(base + SMC16_BIC_OFF + BIC_IRR_OFF);
    
    return (_conv.irr);
}

static __inline__
void
put_irr(
    bic_irr_t		reg,
    IOEISAPortAddress	base
)
{
    _reg_conv_t		_conv;
    
    _conv.irr = reg;

    outb(base + SMC16_BIC_OFF + BIC_IRR_OFF, _conv.data);
}

static __inline__
bic_laar_t
get_laar(
    IOEISAPortAddress	base
)
{
    _reg_conv_t		_conv;
    
    _conv.data = inb(base + SMC16_BIC_OFF + BIC_LAAR_OFF);
    
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

    outb(base + SMC16_BIC_OFF + BIC_LAAR_OFF, _conv.data);
}

static __inline__
bic_bio_t
get_bio(
    IOEISAPortAddress	base
)
{
    _reg_conv_t		_conv;
    bic_icr_t    	icr = get_icr(base);
    
    icr.ora = BIC_ACCESS_BIO;
    put_icr(icr,base);
    _conv.data = inb(base + SMC16_BIC_OFF + BIC_BIO_OFF);
    
    return (_conv.bio);
}

static __inline__
void
put_bio(
    bic_bio_t		reg,
    IOEISAPortAddress	base
)
{
    _reg_conv_t		_conv;
    bic_icr_t    	icr = get_icr(base);
    
    icr.ora = BIC_ACCESS_BIO;
    put_icr(icr,base);
    _conv.bio = reg;

    outb(base + SMC16_BIC_OFF + BIC_BIO_OFF, _conv.data);
}

static __inline__
bic_ear_t
get_ear(
    IOEISAPortAddress	base
)
{
    _reg_conv_t		_conv;
    bic_icr_t    	icr = get_icr(base);
    
    icr.ora = BIC_ACCESS_EAR;
    put_icr(icr,base);
    
    _conv.data = inb(base + SMC16_BIC_OFF + BIC_EAR_OFF);
    
    return (_conv.ear);
}

static __inline__
unsigned char
get_bid(
    IOEISAPortAddress	base
)
{
    return (inb(base + SMC16_BIC_OFF + BIC_ID_OFF));
}

/*
 * Access to 83C690 registers.
 */

/*
 * Select a different register
 * page, and return the old one.
 */

#define REG_PAGE0	0
#define REG_PAGE1	1
#define REG_PAGE2	2
#define REG_PAGE3	3

static __inline__
int
sel_reg_page(
    int			page,
    IOEISAPortAddress	base
)
{
    _reg_conv_t		_conv;
    int			oldpage;
    
    _conv.data = inb(base + SMC16_NIC_OFF + NIC_CMD_REG_OFF);
    oldpage = _conv.cmd_reg.psel;
    
    _conv.cmd_reg.psel = page;
    outb(base + SMC16_NIC_OFF + NIC_CMD_REG_OFF, _conv.data);
    
    return (oldpage);
}

/*
 * Get/Put 83C690 register values,
 * assuming that the correct register
 * page has already been selected.
 */

static __inline__
nic_cmd_reg_t
get_cmd_reg(
    IOEISAPortAddress	base
)
{
    _reg_conv_t		_conv;
    
    _conv.data = inb(base + SMC16_NIC_OFF + NIC_CMD_REG_OFF);
    
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
    
    outb(base + SMC16_NIC_OFF + NIC_CMD_REG_OFF, _conv.data);
}

static __inline__
nic_istat_reg_t
get_istat_reg(
    IOEISAPortAddress	base
)
{
    _reg_conv_t		_conv;
    
    _conv.data = inb(base + SMC16_NIC_OFF + NIC_ISTAT_REG_OFF);
    
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
    
    outb(base + SMC16_NIC_OFF + NIC_ISTAT_REG_OFF, _conv.data);
}

static __inline__
nic_imask_reg_t
get_imask_reg(
    IOEISAPortAddress	base
)
{
    _reg_conv_t		_conv;
    
    _conv.data = inb(base + SMC16_NIC_OFF + NIC_IMASK_REG_OFF);
    
    return (_conv.imask_reg);
}

static __inline__
void
put_imask_reg(
    nic_imask_reg_t	reg,
    IOEISAPortAddress	base
)
{
    _reg_conv_t		_conv;
    
    _conv.imask_reg = reg;
    
    outb(base + SMC16_NIC_OFF + NIC_IMASK_REG_OFF, _conv.data);
}

static __inline__
nic_dcon_reg_t
get_dcon_reg(
    IOEISAPortAddress	base
)
{
    _reg_conv_t		_conv;
    
    _conv.data = inb(base + SMC16_NIC_OFF + NIC_DCON_REG_OFF);
    
    return (_conv.dcon_reg);
}

static __inline__
void
put_dcon_reg(
    nic_dcon_reg_t	reg,
    IOEISAPortAddress	base
)
{
    _reg_conv_t		_conv;
    
    _conv.dcon_reg = reg;
    
    outb(base + SMC16_NIC_OFF + NIC_DCON_REG_OFF, _conv.data);
}

static __inline__
void
put_enh_reg(
    nic_enh_reg_t	reg,
    IOEISAPortAddress	base
)
{
    _reg_conv_t		_conv;
    
    _conv.enh_reg = reg;
    
    outb(base + SMC16_NIC_OFF + NIC_ENH_REG_OFF, _conv.data);
}

static __inline__
nic_rcon_reg_t
get_rcon_reg(
    IOEISAPortAddress	base
)
{
    _reg_conv_t		_conv;
    
    _conv.data = inb(base + SMC16_NIC_OFF + NIC_RCON_REG_OFF);
    
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
    
    outb(base + SMC16_NIC_OFF + NIC_RCON_REG_OFF, _conv.data);
}

static __inline__
nic_tcon_reg_t
get_tcon_reg(
    IOEISAPortAddress	base
)
{
    _reg_conv_t		_conv;
    
    _conv.data = inb(base + SMC16_NIC_OFF + NIC_TCON_REG_OFF);
    
    return (_conv.tcon_reg);
}

static __inline__
void
put_tcon_reg(
    nic_tcon_reg_t	reg,
    IOEISAPortAddress	base
)
{
    _reg_conv_t		_conv;
    
    _conv.tcon_reg = reg;
    
    outb(base + SMC16_NIC_OFF + NIC_TCON_REG_OFF, _conv.data);
}

static __inline__
void
put_tstart_reg(
    SMC16_off_t		reg,
    IOEISAPortAddress	base
)
{
    outb(base + SMC16_NIC_OFF + NIC_TSTART_REG_OFF, reg);
}

static __inline__
void
put_tcnt_reg(
    unsigned short	reg,
    IOEISAPortAddress	base
)
{
    union {
	struct {
	    unsigned char	tcntl	:8;
	    unsigned char	tcnth	:8;
	} l_h;
	unsigned short		tcnt;
    } _conv;
    
    _conv.tcnt = reg;
    
    outb(base + SMC16_NIC_OFF + NIC_TCNTL_REG_OFF, _conv.l_h.tcntl);
    outb(base + SMC16_NIC_OFF + NIC_TCNTH_REG_OFF, _conv.l_h.tcnth);
}

static __inline__
nic_tstat_reg_t
get_tstat_reg(
    IOEISAPortAddress	base
)
{
    _reg_conv_t		_conv;

    _conv.data = inb(base + SMC16_NIC_OFF + NIC_TSTAT_REG_OFF);
    
    return (_conv.tstat_reg);
}

static __inline__
void
put_rstart_reg(
    SMC16_off_t		reg,
    IOEISAPortAddress	base
)
{
    outb(base + SMC16_NIC_OFF + NIC_RSTART_REG_OFF, reg);
}

static __inline__
void
put_rstop_reg(
    SMC16_off_t		reg,
    IOEISAPortAddress	base
)
{
    outb(base + SMC16_NIC_OFF + NIC_RSTOP_REG_OFF, reg);
}

static __inline__
SMC16_off_t
get_block_reg(
    IOEISAPortAddress	base
)
{
    _reg_conv_t	_conv;
    int		oldPage = sel_reg_page(NIC_BLOCK_REG_R_PG,base);
    
    _conv.offset = (inb(base + SMC16_NIC_OFF + NIC_BLOCK_REG_OFF));
    sel_reg_page(oldPage,base);
    return _conv.offset;  
}

static __inline__
void
put_block_reg(
    SMC16_off_t		reg,
    IOEISAPortAddress	base
)
{
    int	oldPage = sel_reg_page(NIC_BLOCK_REG_W_PG,base);
    outb(base + SMC16_NIC_OFF + NIC_BLOCK_REG_OFF, reg);
    sel_reg_page(oldPage,base);
}

static __inline__
SMC16_off_t
get_bound_reg(
    IOEISAPortAddress	base
)
{
    return (inb(base + SMC16_NIC_OFF + NIC_BOUND_REG_OFF));
}

static __inline__
void
put_bound_reg(
    SMC16_off_t		reg,
    IOEISAPortAddress	base
)
{
    outb(base + SMC16_NIC_OFF + NIC_BOUND_REG_OFF, reg);
}

static __inline__
SMC16_off_t
get_curr_reg(
    IOEISAPortAddress	base
)
{
    return (inb(base + SMC16_NIC_OFF + NIC_CURR_REG_OFF));
}

static __inline__
void
put_curr_reg(
    SMC16_off_t		reg,
    IOEISAPortAddress	base
)
{
    outb(base + SMC16_NIC_OFF + NIC_CURR_REG_OFF, reg);
}

