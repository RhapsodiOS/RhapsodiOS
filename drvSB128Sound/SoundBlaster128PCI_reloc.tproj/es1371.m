/*---------------------------------------------------------------------------*\
*	                                                                      *
*	Copyright (c) 2001 by Jens Heise      	                              *
*	                                                                      *
*	created: 19.05.2001	              	  modified: 27.05.2001        *
*									      *
*			Version: 1.0					      *
*	                                                                      *
*-----------------------------------------------------------------------------*
*									      *
*									      *
*	This driver is based on the es1371 module for linux. Most changes     *
*	done are in locking, buffer management, sleeping and scheduling       *
*	(none on NeXT).                                                       *
*									      *
*	Copyright of original linux sources.                                  *
*	Copyright (C) 1998-2000  Thomas Sailer (sailer@ife.ee.ethz.ch)        *
*	                                                                      *
*	This program is free software; you can redistribute it and/or         *
*	modify it under the terms of the GNU General Public License as        *
*	published by the Free Software Foundation; either version 2 of        *
*	the License, or (at your option) any later version.                   *
*	                                                                      *
*	This program is distributed in the hope that it will be useful,       *
*	but WITHOUT ANY WARRANTY; without even the implied warranty of        *
*	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU     *
*	General Public License for more details.                              *
*	                                                                      *
*	You should have received a copy of the GNU General Public License     *
*	along with this program; if not, write to the Free Software           *
*	Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.             *
*	                                                                      *
\*---------------------------------------------------------------------------*/
#import <driverkit/generalFuncs.h>
#import <driverkit/i386/IOPCIDeviceDescription.h>
#import <driverkit/i386/IOPCIDirectDevice.h>
#import <driverkit/i386/PCI.h>
#import <driverkit/i386/directDevice.h>
#import <driverkit/i386/ioPorts.h>
#import <driverkit/kernelDriver.h>
#import <kernserv/i386/spl.h>
#import <kernserv/prototypes.h>
#import <kernserv/sched_prim.h>
#import <mach/vm_param.h>

#import "ac97.h"
#import "es1371.h"
#import "SoundBlaster128PCIDriver.h"	/* For DRV_TITLE 		     */

static const char *stereo_enhancement[] =
{
        "no 3D stereo enhancement",
        "Analog Devices Phat Stereo",
        "Creative Stereo Enhancement",
        "National Semiconductor 3D Stereo Enhancement",
        "YAMAHA Ymersion",
        "BBE 3D Stereo Enhancement",
        "Crystal Semiconductor 3D Stereo Enhancement",
        "Qsound QXpander",
        "Spatializer 3D Stereo Enhancement",
        "SRS 3D Stereo Enhancement",
        "Platform Technologies 3D Stereo Enhancement",
        "AKM 3D Audio",
        "Aureal Stereo Enhancement",
        "AZTECH  3D Enhancement",
        "Binaura 3D Audio Enhancement",
        "ESS Technology Stereo Enhancement",
        "Harman International VMAx",
        "NVidea 3D Stereo Enhancement",
        "Philips Incredible Sound",
        "Texas Instruments 3D Stereo Enhancement",
        "VLSI Technology 3D Stereo Enhancement",
        NULL,
        NULL,
        NULL,
        NULL,
        NULL,
        "SigmaTel SS3D"
};

static const unsigned sample_shift[] = { 0, 1, 1, 2 };

				/* NeXT out-function has the arguments in
				   another order than linux so switch them.  */
#define outb(a,b)	outb((b),(a))
#define outw(a,b)	outw((b),(a))
#define outl(a,b)	outl((b),(a))

				/* Redefine linux locking function in NeXT
				   usable way.                               */
#define spin_lock_irqsave(lock, pri)	{pri = spl6(); simple_lock(*lock);}
#define spin_unlock_irqrestore(lock, pri)	{splx(pri);		\
						 simple_unlock(*lock);}

/*-------------------------------- Misc stuff -------------------------------*/
/*---------------------------------- ld2() ----------------------------------*\
*									      *
*	???
*									      *
\*---------------------------------------------------------------------------*/

static unsigned ld2(unsigned int x)
{
    unsigned r = 0;

    if (x >= 0x10000)
    {
	x >>= 16;
	r += 16;
    } /* if */
    if (x >= 0x100)
    {
	x >>= 8;
	r += 8;
    } /* if */
    if (x >= 0x10)
    {
	x >>= 4;
	r += 4;
    } /* if */
    if (x >= 4)
    {
	x >>= 2;
	r += 2;
    } /* if */
    if (x >= 2)
	r++;
    return r;
} /* ld2() */



/*-------------------------- Sample rate converter --------------------------*/
/*----------------------------- wait_src_ready() ----------------------------*\
*									      *
*	Wait for the sample rate converter to become ready.                   *
*									      *
\*---------------------------------------------------------------------------*/

static unsigned wait_src_ready(struct es1371_state *s)
{
    unsigned int t, r;

    for (t = 0; t < POLL_COUNT; t++)
    {
	if (!((r = inl(s->io + ES1371_REG_SRCONV)) & SRC_BUSY))
	    return r;
	IODelay(1);
    } /* for */
    IOLog("%s: sample rate converter timeout r = 0x%08x\n", DRV_TITLE, r);
    return r;
} /* wait_src_ready() */



/*-------------------------------- src_read() -------------------------------*\
*									      *
*	Read register from SRC.                                               *
*									      *
\*---------------------------------------------------------------------------*/

static unsigned src_read(struct es1371_state *s, unsigned reg)
{
    unsigned int temp,i,orig;

				/* wait for ready                            */
    temp = wait_src_ready (s);

				/* we can only access the SRC at certain
				   times, make sure we're allowed to before
				   we read                                   */
    orig = temp;
				/* expose the SRC state bits                 */
    outl ( (temp & SRC_CTLMASK) | (reg << SRC_RAMADDR_SHIFT) | 0x10000UL,
	s->io + ES1371_REG_SRCONV);

				/* now, wait for busy and the correct time to
				   read                                      */
    temp = wait_src_ready (s);

    if ( (temp & 0x00870000UL ) != ( SRC_OKSTATE << 16 ))
    {
				/* wait for the right state                  */
	for (i=0; i<POLL_COUNT; i++)
	{
	    temp = inl (s->io + ES1371_REG_SRCONV);
	    if ( (temp & 0x00870000UL ) == ( SRC_OKSTATE << 16 ))
		break;
	} /* for */
    } /* if */

				/* hide the state bits                       */
    outl ((orig & SRC_CTLMASK) | (reg << SRC_RAMADDR_SHIFT),
    			s->io + ES1371_REG_SRCONV);
    return temp;
} /* src_read() */



/*------------------------------- src_write() -------------------------------*\
*									      *
*	Write data to SRC register.                                           *
*									      *
\*---------------------------------------------------------------------------*/

static void src_write(struct es1371_state *s, unsigned reg, unsigned data)
{
    unsigned int r;

    r = wait_src_ready(s) & (SRC_DIS | SRC_DDAC1 | SRC_DDAC2 | SRC_DADC);
    r |= (reg << SRC_RAMADDR_SHIFT) & SRC_RAMADDR_MASK;
    r |= (data << SRC_RAMDATA_SHIFT) & SRC_RAMDATA_MASK;
    outl(r | SRC_WE, s->io + ES1371_REG_SRCONV);

    return;
} /* src_write() */



/*------------------------------ set_adc_rate() -----------------------------*\
*									      *
*	Set the rate of the adc.                                              *
*									      *
\*---------------------------------------------------------------------------*/

void set_adc_rate(struct es1371_state *s, unsigned rate)
{
    unsigned int	n;
    unsigned int	truncm;
    unsigned int	freq;
    unsigned long	flags;

    spin_lock_irqsave(&s->lock, flags);

    if (rate > 48000)
	rate = 48000;
    if (rate < 4000)
	rate = 4000;
    n = rate / 3000;
    if ((1 << n) & ((1 << 15) | (1 << 13) | (1 << 11) | (1 << 9)))
	n--;
    truncm = (21 * n - 1) | 1;
    freq = ((48000UL << 15) / rate) * n;
    s->adcrate = (48000UL << 15) / (freq / n);

    if (rate >= 24000)
    {
	if (truncm > 239)
	    truncm = 239;
	src_write(s, SRCREG_ADC+SRCREG_TRUNC_N,
			(((239 - truncm) >> 1) << 9) | (n << 4));
    } /* if */
    else
    {
	if (truncm > 119)
	    truncm = 119;
	src_write(s, SRCREG_ADC+SRCREG_TRUNC_N,
		    0x8000 | (((119 - truncm) >> 1) << 9) | (n << 4));
    } /* if..else */
    src_write(s, SRCREG_ADC+SRCREG_INT_REGS,
		(src_read(s, SRCREG_ADC+SRCREG_INT_REGS) & 0x00ff) |
		((freq >> 5) & 0xfc00));
    src_write(s, SRCREG_ADC+SRCREG_VFREQ_FRAC, freq & 0x7fff);
    src_write(s, SRCREG_VOL_ADC, n << 8);
    src_write(s, SRCREG_VOL_ADC+1, n << 8);

    spin_unlock_irqrestore(&s->lock, flags);

    return;
} /* set_adc_rate() */



/*----------------------------- set_dac1_rate() -----------------------------*\
*									      *
*	Set rate of dac1.                                                     *
*									      *
\*---------------------------------------------------------------------------*/

void set_dac1_rate(struct es1371_state *s, unsigned rate)
{
    unsigned int freq, r;
    unsigned long flags;

    spin_lock_irqsave(&s->lock, flags);

    if (rate > 48000)
	rate = 48000;
    if (rate < 4000)
	rate = 4000;
    freq = ((rate << 15) + 1500) / 3000;
    s->dac1rate = (freq * 3000 + 16384) >> 15;
    r = (wait_src_ready(s) & (SRC_DIS | SRC_DDAC2 | SRC_DADC)) | SRC_DDAC1;
    outl(r, s->io + ES1371_REG_SRCONV);
    src_write(s, SRCREG_DAC1+SRCREG_INT_REGS,
		(src_read(s, SRCREG_DAC1+SRCREG_INT_REGS) & 0x00ff) |
		((freq >> 5) & 0xfc00));
    src_write(s, SRCREG_DAC1+SRCREG_VFREQ_FRAC, freq & 0x7fff);
    r = (wait_src_ready(s) & (SRC_DIS | SRC_DDAC2 | SRC_DADC));
    outl(r, s->io + ES1371_REG_SRCONV);

    spin_unlock_irqrestore(&s->lock, flags);

    return;
} /* set_dac1_rate() */



/*----------------------------- set_dac2_rate() -----------------------------*\
*									      *
*	Set rate of dac2.                                                     *
*									      *
\*---------------------------------------------------------------------------*/

void set_dac2_rate(struct es1371_state *s, unsigned rate)
{
    unsigned int freq, r;
    unsigned long flags;

    spin_lock_irqsave(&s->lock, flags);

    if (rate > 48000)
	rate = 48000;
    if (rate < 4000)
	rate = 4000;
    freq = ((rate << 15) + 1500) / 3000;
    s->dac1rate = (freq * 3000 + 16384) >> 15;
    r = (wait_src_ready(s) & (SRC_DIS | SRC_DDAC1 | SRC_DADC)) | SRC_DDAC2;
    outl(r, s->io + ES1371_REG_SRCONV);
    src_write(s, SRCREG_DAC2+SRCREG_INT_REGS,
		(src_read(s, SRCREG_DAC2+SRCREG_INT_REGS) & 0x00ff) |
		((freq >> 5) & 0xfc00));
    src_write(s, SRCREG_DAC2+SRCREG_VFREQ_FRAC, freq & 0x7fff);
    r = (wait_src_ready(s) & (SRC_DIS | SRC_DDAC1 | SRC_DADC));
    outl(r, s->io + ES1371_REG_SRCONV);

    spin_unlock_irqrestore(&s->lock, flags);

    return;
} /* set_dac2_rate() */



/*-------------------------------- src_init() -------------------------------*\
*									      *
*	Initialize the SRC.                                                   *
*									      *
\*---------------------------------------------------------------------------*/

static void src_init(struct es1371_state *s)
{
    unsigned int i;
				/* before we enable or disable the SRC we
				   need to wait for it to become ready       */
    wait_src_ready(s);

    outl(SRC_DIS, s->io + ES1371_REG_SRCONV);

    for (i = 0; i < 0x80; i++)
	src_write(s, i, 0);

    src_write(s, SRCREG_DAC1+SRCREG_TRUNC_N, 16 << 4);
    src_write(s, SRCREG_DAC1+SRCREG_INT_REGS, 16 << 10);
    src_write(s, SRCREG_DAC2+SRCREG_TRUNC_N, 16 << 4);
    src_write(s, SRCREG_DAC2+SRCREG_INT_REGS, 16 << 10);
    src_write(s, SRCREG_VOL_ADC, 1 << 12);
    src_write(s, SRCREG_VOL_ADC+1, 1 << 12);
    src_write(s, SRCREG_VOL_DAC1, 1 << 12);
    src_write(s, SRCREG_VOL_DAC1+1, 1 << 12);
    src_write(s, SRCREG_VOL_DAC2, 1 << 12);
    src_write(s, SRCREG_VOL_DAC2+1, 1 << 12);
    set_adc_rate(s, 22050);
    set_dac1_rate(s, 22050);
    set_dac2_rate(s, 22050);

				/* WARNING:
				   enabling the sample rate converter without
				   properly programming its parameters causes
				   the chip to lock up (the SRC busy bit will
				   be stuck high, and I've found no way to
				   rectify this other than power cycle)      */
    wait_src_ready(s);
    outl(0, s->io+ES1371_REG_SRCONV);

    return;
} /* src_init() */



/*---------------------------------- DAC's ----------------------------------*/
/*------------------------------- start_adc() -------------------------------*\
*									      *
*	Start the ADC (not testet).                                           *
*									      *
\*---------------------------------------------------------------------------*/

void start_adc(struct es1371_state *s)
{
    unsigned int	fshift;
    unsigned int	fragremain;
    unsigned long 	flags;

    spin_lock_irqsave(&s->lock, flags);

    if (!(s->ctrl & CTRL_ADC_EN) && (s->dma_adc.count <
    		(signed)(s->dma_adc.dmasize - 2*s->dma_adc.fragsize)))
    {
	s->ctrl |= CTRL_ADC_EN;
	s->sctrl = (s->sctrl & ~SCTRL_R1LOOPSEL) | SCTRL_R1INTEN;
	outl(s->sctrl, s->io+ES1371_REG_SERIAL_CONTROL);
	fragremain = ((- s->dma_adc.hwptr) & (s->dma_adc.fragsize-1));
	fshift = sample_shift[(s->sctrl & SCTRL_R1FMT) >> SCTRL_SH_R1FMT];
	if (fragremain < 2*fshift)
	    fragremain = s->dma_adc.fragsize;
	outl((fragremain >> fshift) - 1, s->io+ES1371_REG_ADC_SCOUNT);
	outl(s->ctrl, s->io+ES1371_REG_CONTROL);
	outl((s->dma_adc.fragsize >> fshift) - 1, s->io+ES1371_REG_ADC_SCOUNT);
    } /* if */

    spin_unlock_irqrestore(&s->lock, flags);

    return;
} /* start_adc() */



/*------------------------------- start_dac1() ------------------------------*\
*									      *
*	Start dac1 (should work since it's the same as in dac2 which is       *
*	used.                                                                 *
*									      *
\*---------------------------------------------------------------------------*/

void start_dac1(struct es1371_state *s)
{
    unsigned int	fshift;
    unsigned int	fragremain;
    unsigned long 	flags;

    spin_lock_irqsave(&s->lock, flags);

    if (!(s->ctrl & CTRL_DAC1_EN))
    {
	s->ctrl |= CTRL_DAC1_EN;
	s->sctrl = (s->sctrl & ~(SCTRL_P1LOOPSEL | SCTRL_P1PAUSE |
				SCTRL_P1SCTRLD)) | SCTRL_P1INTEN;
	outl(s->sctrl, s->io+ES1371_REG_SERIAL_CONTROL);
	fragremain = ((- s->dma_dac1.hwptr) & (s->dma_dac1.fragsize-1));
	fshift = sample_shift[(s->sctrl & SCTRL_P1FMT) >> SCTRL_SH_P1FMT];
	if (fragremain < 2*fshift)
	    fragremain = s->dma_dac1.fragsize;
	outl((fragremain >> fshift) - 1, s->io+ES1371_REG_DAC1_SCOUNT);
	outl(s->ctrl, s->io+ES1371_REG_CONTROL);
	outl((s->dma_dac1.fragsize >> fshift) - 1,
				s->io+ES1371_REG_DAC1_SCOUNT);
    } /* if */

    spin_unlock_irqrestore(&s->lock, flags);

    return;
} /* start_dac1() */



/*------------------------------- start_dac2() ------------------------------*\
*									      *
*	Start dac2 (this dac is used by the driver since dac2 supports        *
*	loop increment and dac2 is used on linux for normal playback).        *
*									      *
\*---------------------------------------------------------------------------*/

void start_dac2(struct es1371_state *s, BOOL noLock)
{
    unsigned int	fshift;
    unsigned int	fragremain;
    unsigned long 	flags;

    if (!noLock) spin_lock_irqsave(&s->lock, flags);

    if (!(s->ctrl & CTRL_DAC2_EN))
    {
	s->ctrl |= CTRL_DAC2_EN;
	s->sctrl = (s->sctrl & ~(SCTRL_P2LOOPSEL | SCTRL_P2PAUSE |
		SCTRL_P2DACSEN | SCTRL_P2ENDINC | SCTRL_P2STINC)) |
		SCTRL_P2INTEN |
		(((s->sctrl & SCTRL_P2FMT) ? 2 : 1) << SCTRL_SH_P2ENDINC) |
		(0 << SCTRL_SH_P2STINC);
	outl(s->sctrl, s->io+ES1371_REG_SERIAL_CONTROL);
	fragremain = ((- s->dma_dac2.hwptr) & (s->dma_dac2.fragsize-1));
	fshift = sample_shift[(s->sctrl & SCTRL_P2FMT) >> SCTRL_SH_P2FMT];
	if (fragremain < 2*fshift)
	    fragremain = s->dma_dac2.fragsize;
	outl((fragremain >> fshift) - 1, s->io+ES1371_REG_DAC2_SCOUNT);
	outl(s->ctrl, s->io+ES1371_REG_CONTROL);
	outl((s->dma_dac2.fragsize >> fshift) - 1,
				s->io+ES1371_REG_DAC2_SCOUNT);
    } /* if */

    if (!noLock) spin_unlock_irqrestore(&s->lock, flags);

    return;
} /* start_dac2() */



/*------------------------------- get_hwptr() -------------------------------*\
*									      *
*	Reading the hardware pointers and calculate the difference.           *
*									      *
\*---------------------------------------------------------------------------*/

static unsigned get_hwptr(struct es1371_state *s, struct dmabuf *db, unsigned reg)
{
    unsigned hwptr, diff;

    outl((reg >> 8) & 15, s->io+ES1371_REG_MEMPAGE);
    hwptr = (inl(s->io+(reg & 0xff)) >> 14) & 0x3fffc;
    diff = (db->dmasize + hwptr - db->hwptr) % db->dmasize;
    db->hwptr = hwptr;

    return diff;
} /* get_hwptr() */



/*------------------------------- update_ptr() ------------------------------*\
*									      *
*	Update the pointers for the dma buffer. (Completely stripped          *
*	handling of unmapped buffer since it is always mapped on NeXT).       *
*									      *
\*---------------------------------------------------------------------------*/

static void update_ptr(struct es1371_state *s)
{
    int		diff;

				/* update ADC pointer                        */
    if (s->ctrl & CTRL_ADC_EN)
    {
	diff = get_hwptr(s, &s->dma_adc, ES1371_REG_ADC_FRAMECNT);
	s->dma_adc.total_bytes += diff;
	s->dma_adc.count += diff;
	if (s->dma_adc.count >= (signed)s->dma_adc.fragsize)
	    s->dma_adc.wait = NO;
    } /* if */
				/* update DAC1 pointer                       */
    if (s->ctrl & CTRL_DAC1_EN)
    {
	diff = get_hwptr(s, &s->dma_dac1, ES1371_REG_DAC1_FRAMECNT);
	s->dma_dac1.total_bytes += diff;

	s->dma_dac1.count += diff;
	if (s->dma_dac1.count >= (signed)s->dma_dac1.fragsize)
	    s->dma_dac1.wait = NO;
    } /* if */
				/* update DAC2 pointer                       */
    if (s->ctrl & CTRL_DAC2_EN)
    {
	diff = get_hwptr(s, &s->dma_dac2, ES1371_REG_DAC2_FRAMECNT);
	s->dma_dac2.total_bytes += diff;

	s->dma_dac2.count += diff;
	if (s->dma_dac2.count >= (signed)s->dma_dac2.fragsize)
	    s->dma_dac2.wait = NO;
    } /* if */

    return;
} /* update_ptr() */



/*---------------------------- clear_interrupt() ----------------------------*\
*									      *
*	Clear the cards interrupt flags and update pointers.                  *
*									      *
\*---------------------------------------------------------------------------*/

int clear_interrupt(struct es1371_state *s)
{
    unsigned int 	intsrc;
    unsigned int	sctl;
    unsigned long	flags;

				/* fastpath out, to ease interrupt sharing   */
    intsrc = inl(s->io+ES1371_REG_STATUS);
    if (!(intsrc & 0x80000000))
	return 0;

    //spin_lock_irqsave(&s->lock, flags);
				/* clear audio interrupts first              */
    sctl = s->sctrl;
    if (intsrc & STAT_ADC)
    {
	sctl &= ~SCTRL_R1INTEN;
	s->dma_adc.intr = YES;
    } /* if */
    if (intsrc & STAT_DAC1)
    {
	sctl &= ~SCTRL_P1INTEN;
	s->dma_dac1.intr = YES;
    } /* if */
    if (intsrc & STAT_DAC2)
    {
	sctl &= ~SCTRL_P2INTEN;
	s->dma_dac2.intr = YES;
    } /* if */
    outl(sctl, s->io+ES1371_REG_SERIAL_CONTROL);
    outl(s->sctrl, s->io+ES1371_REG_SERIAL_CONTROL);
    update_ptr(s);

    //spin_unlock_irqrestore(&s->lock, flags);

    return 1;
} /* clear_interrupt() */



/*-------------------------------- stop_adc() -------------------------------*\
*									      *
*	Stop the adc.                                                         *
*									      *
\*---------------------------------------------------------------------------*/

void stop_adc(struct es1371_state *s)
{
    unsigned long	flags;

    spin_lock_irqsave(&s->lock, flags);

    s->ctrl &= ~CTRL_ADC_EN;
    outl(s->ctrl, s->io+ES1371_REG_CONTROL);

    spin_unlock_irqrestore(&s->lock, flags);

} /* stop_adc() */



/*------------------------------- stop_dac1() -------------------------------*\
*									      *
*	Stop the dac1.                                                        *
*									      *
\*---------------------------------------------------------------------------*/

void stop_dac1(struct es1371_state *s)
{
    unsigned long	flags;

    spin_lock_irqsave(&s->lock, flags);

    s->ctrl &= ~CTRL_DAC1_EN;
    outl(s->ctrl, s->io+ES1371_REG_CONTROL);

    spin_unlock_irqrestore(&s->lock, flags);

} /* stop_dac1() */



/*------------------------------- stop_dac2() -------------------------------*\
*									      *
*	Stop the dac2.                                                        *
*									      *
\*---------------------------------------------------------------------------*/

void stop_dac2(struct es1371_state *s)
{
    unsigned long	flags;

    spin_lock_irqsave(&s->lock, flags);

    s->ctrl &= ~CTRL_DAC2_EN;
    outl(s->ctrl, s->io+ES1371_REG_CONTROL);

    spin_unlock_irqrestore(&s->lock, flags);

} /* stop_dac2() */



/*----------------------------- prepare_dmabuf() ----------------------------*\
*									      *
*	Called by NeXT's createDMABuf. Sets the buffer address and            *
*	calculates the buforder which is needed by prog_dmabuf.               *
*									      *
\*---------------------------------------------------------------------------*/

static void prepare_dmabuf(struct es1371_state *s, struct dmabuf *db, unsigned int addr, unsigned int dmasize, unsigned reg)
{
    unsigned int	order=dmasize;

				/* Set address in structure and calculate
				   buforder for use in prog_dmabuf.          */
    db->rawbuf = (void*)addr;
    for(db->buforder = 0; order > PAGE_SIZE; db->buforder++)
	order = order >> 1;

    return;
} /* prepare_dmabuf() */



/*--------------------------- prepare_dmabuf_adc() --------------------------*\
*									      *
*	Prepare buffer for adc.                                               *
*									      *
\*---------------------------------------------------------------------------*/

void prepare_dmabuf_adc(struct es1371_state *s, unsigned int addr, unsigned int dmasize)
{
    return prepare_dmabuf(s, &s->dma_adc, addr, dmasize,
    			ES1371_REG_ADC_FRAMEADR);
} /* prepare_dmabuf_adc() */



/*-------------------------- prepare_dmabuf_dac1() --------------------------*\
*									      *
*	Prepare buffer for dac1.                                              *
*									      *
\*---------------------------------------------------------------------------*/

void prepare_dmabuf_dac1(struct es1371_state *s, unsigned int addr, unsigned int dmasize)
{
    return prepare_dmabuf(s, &s->dma_dac1, addr, dmasize,
    			ES1371_REG_DAC1_FRAMEADR);
} /* prepare_dmabuf_dac1() */



/*-------------------------- prepare_dmabuf_dac2() --------------------------*\
*									      *
*	Prepare buffer for dac2.                                              *
*									      *
\*---------------------------------------------------------------------------*/

void prepare_dmabuf_dac2(struct es1371_state *s, unsigned int addr, unsigned int dmasize)
{
    return prepare_dmabuf(s, &s->dma_dac2, addr, dmasize,
    			ES1371_REG_DAC2_FRAMEADR);
} /* prepare_dmabuf_dac2() */



/*------------------------------ prog_dmabuf() ------------------------------*\
*									      *
*	Initialize the dma buffer and set it to the card. This method is      *
*	called each time before output is started.                            *
*									      *
\*---------------------------------------------------------------------------*/

static int prog_dmabuf(struct es1371_state *s, struct dmabuf *db, unsigned rate, unsigned fmt, unsigned reg, unsigned transferCount)
{
    unsigned 	bytepersec;
    unsigned 	bufs;

				/* NeXT always begin playback at begin of
				   buffer, so reset all pointers and count.  */
    db->hwptr = 0;
    db->swptr = 0;
    db->total_bytes = 0;
    db->count = 0;
    db->error = 0;
				/* NeXT specific count which specify how many
				   bytes may be transferred before an
				   interrupt is placed and buffer is
				   refilled.                                 */
    db->transferCount = transferCount;

				/* The code for allocating buffers is
				   completely stripped since buffer is
				   already allocated by NeXT.                */
    fmt &= ES1371_FMT_MASK;
    bytepersec = rate << sample_shift[fmt];
    bufs = PAGE_SIZE << db->buforder;
    db->fragshift = ld2(bytepersec/100);

				/* Correct the fragshift to speed up the
				   system. Now there are 4 interrupts for
				   transferring one complete buffer page.
				   (Originaly an interrupt were placed every
				   16 samples which places horrible load on
				   the system).                              */
    for(db->fragshift = 0; (2 << db->fragshift) < transferCount;)
    	db->fragshift++;

    if (db->fragshift < 3)
	db->fragshift = 3;

    db->numfrag = bufs >> db->fragshift;
    while (db->numfrag < 4 && db->fragshift > 3)
    {
	db->fragshift--;
	db->numfrag = bufs >> db->fragshift;
    } /* while */
    db->fragsize = 1 << db->fragshift;
    db->fragsamples = db->fragsize >> sample_shift[fmt];
    db->dmasize = db->numfrag << db->fragshift;

    outl((reg >> 8) & 15, s->io+ES1371_REG_MEMPAGE);
    outl((unsigned long)db->rawbuf, s->io+(reg & 0xff));
    outl((db->dmasize >> 2)-1, s->io+((reg + 4) & 0xff));

    return 0;
} /* prog_dmabuf() */



/*---------------------------- prog_dmabuf_adc() ----------------------------*\
*									      *
*	Program dma buffer for adc.                                           *
*									      *
\*---------------------------------------------------------------------------*/

int prog_dmabuf_adc(struct es1371_state *s, unsigned int transferCount)
{
    stop_adc(s);
    return prog_dmabuf(s, &s->dma_adc, s->adcrate,
		(s->sctrl >> SCTRL_SH_R1FMT) & ES1371_FMT_MASK,
		ES1371_REG_ADC_FRAMEADR, transferCount);
} /* prog_dmabuf_adc() */



/*---------------------------- prog_dmabuf_dac1() ---------------------------*\
*									      *
*	Program dma buffer for dac1.                                          *
*									      *
\*---------------------------------------------------------------------------*/

int prog_dmabuf_dac1(struct es1371_state *s, unsigned int transferCount)
{
    stop_dac1(s);
    return prog_dmabuf(s, &s->dma_dac1, s->dac1rate,
		(s->sctrl >> SCTRL_SH_P1FMT) & ES1371_FMT_MASK,
		ES1371_REG_DAC1_FRAMEADR, transferCount);
} /* prog_dmabuf_dac1() */



/*---------------------------- prog_dmabuf_dac2() ---------------------------*\
*									      *
*	Program dma buffer for dac2.                                          *
*									      *
\*---------------------------------------------------------------------------*/

int prog_dmabuf_dac2(struct es1371_state *s, unsigned int transferCount)
{
    stop_dac2(s);
    return prog_dmabuf(s, &s->dma_dac2, s->dac2rate,
    		(s->sctrl >> SCTRL_SH_P2FMT) & ES1371_FMT_MASK,
		ES1371_REG_DAC2_FRAMEADR, transferCount);
} /* prog_dmabuf_dac2() */



/*---------------------------------- codecs ---------------------------------*/
/*-------------------------------- wrcodec() --------------------------------*\
*									      *
*	Write data to the codec interface.                                    *
*									      *
\*---------------------------------------------------------------------------*/

static void wrcodec(struct es1371_state *s, unsigned addr, unsigned data)
{
    unsigned		t, x;
    unsigned long	flags;

    spin_lock_irqsave(&s->lock, flags);

    for (t = 0; t < POLL_COUNT; t++)
	if (!(inl(s->io+ES1371_REG_CODEC) & CODEC_WIP))
	    break;

				/* save the current state for later          */
    x = wait_src_ready(s);

				/* enable SRC state data in SRC mux          */
    outl(( x & (SRC_DIS | SRC_DDAC1 | SRC_DDAC2 | SRC_DADC)) | 0x00010000,
			s->io+ES1371_REG_SRCONV);

				/* wait for not busy (state 0) first to avoid
				   transition states                         */
    for (t=0; t<POLL_COUNT; t++)
    {
	if((inl(s->io+ES1371_REG_SRCONV) & 0x00870000) == 0 )
	    break;
	IODelay(1);
    } /* for */

				/* wait for a SAFE time to write addr/data
				   and then do it, dammit                    */
    for (t=0; t<POLL_COUNT; t++)
    {
	if((inl(s->io+ES1371_REG_SRCONV) & 0x00870000) == 0x00010000)
	    break;
	IODelay(1);
    } /* for */

    outl(((addr << CODEC_POADD_SHIFT) & CODEC_POADD_MASK) |
	    ((data << CODEC_PODAT_SHIFT) & CODEC_PODAT_MASK),
	    s->io+ES1371_REG_CODEC);

				/* restore SRC reg                           */
    wait_src_ready(s);
    outl(x, s->io+ES1371_REG_SRCONV);

    spin_unlock_irqrestore(&s->lock, flags);

    return;
} /* wrcodec() */



/*-------------------------------- rdcodec() --------------------------------*\
*									      *
*	Read data from codec interface.                                       *
*									      *
\*---------------------------------------------------------------------------*/

static unsigned rdcodec(struct es1371_state *s, unsigned addr)
{
    unsigned 		t, x;
    unsigned long 	flags;

    spin_lock_irqsave(&s->lock, flags);

				/* wait for WIP to go away                   */
    for (t = 0; t < 0x1000; t++)
	if (!(inl(s->io+ES1371_REG_CODEC) & CODEC_WIP))
	    break;

				/* save the current state for later          */
    x = (wait_src_ready(s) & (SRC_DIS | SRC_DDAC1 | SRC_DDAC2 | SRC_DADC));

				/* enable SRC state data in SRC mux          */
    outl( x | 0x00010000, s->io+ES1371_REG_SRCONV);

				/* wait for not busy (state 0) first to avoid
				   transition states                         */
    for (t=0; t<POLL_COUNT; t++)
    {
	if((inl(s->io+ES1371_REG_SRCONV) & 0x00870000) ==0 )
	    break;
	IODelay(1);
    } /* for */

				/* wait for a SAFE time to write addr/data
				   and then do it, dammit                    */
    for (t=0; t<POLL_COUNT; t++)
    {
	if((inl(s->io+ES1371_REG_SRCONV) & 0x00870000) ==0x00010000)
	    break;
	IODelay(1);
    } /* for */

    outl(((addr << CODEC_POADD_SHIFT) & CODEC_POADD_MASK) | CODEC_PORD,
    			s->io+ES1371_REG_CODEC);

				/* restore SRC reg                           */
    wait_src_ready(s);
    outl(x, s->io+ES1371_REG_SRCONV);

    spin_unlock_irqrestore(&s->lock, flags);

				/* wait for WIP again                        */
    for (t = 0; t < 0x1000; t++)
	if (!(inl(s->io+ES1371_REG_CODEC) & CODEC_WIP))
	    break;

				/* now wait for the stinkin' data (RDY)      */
    for (t = 0; t < POLL_COUNT; t++)
	if ((x = inl(s->io+ES1371_REG_CODEC)) & CODEC_RDY)
	    break;

    return ((x & CODEC_PIDAT_MASK) >> CODEC_PIDAT_SHIFT);
} /* rdcodec() */



/*----------------------------- NeXT Interface  -----------------------------*/
/*------------------------------ set_adc_mode() -----------------------------*\
*									      *
*	Set recordmode of adc.                                                *
*									      *
\*---------------------------------------------------------------------------*/

void set_adc_mode(struct es1371_state *s, BOOL bit16, BOOL stereo)
{
    unsigned long	flags;

    stop_adc(s);

    spin_lock_irqsave(&s->lock, flags);

    s->sctrl = inl(s->io+ES1371_REG_SERIAL_CONTROL);
    s->sctrl &= ~SCTRL_R1FMT;

				/* Using 8- or 16-bit samples.               */
    if (bit16)
	s->sctrl |= SCTRL_R1SEB;

				/* Is stereo sound enabled.                  */
    if (stereo)
	s->sctrl |= SCTRL_R1SMB;
    outl(s->sctrl, s->io+ES1371_REG_SERIAL_CONTROL);

    spin_unlock_irqrestore(&s->lock, flags);

    return;
} /* set_adc_mode() */



/*----------------------------- set_dac1_mode() -----------------------------*\
*									      *
*	Set playbackmode for dac1.                                            *
*									      *
\*---------------------------------------------------------------------------*/

void set_dac1_mode(struct es1371_state *s, BOOL bit16, BOOL stereo)
{
    unsigned long	flags;

    stop_dac1(s);

    spin_lock_irqsave(&s->lock, flags);

    s->sctrl = inl(s->io+ES1371_REG_SERIAL_CONTROL);
    s->sctrl &= ~SCTRL_P1FMT;

				/* Using 8- or 16-bit samples.               */
    if (bit16)
	s->sctrl |= SCTRL_P1SEB;
				/* Is stereo sound enabled.                  */
    if (stereo)
	s->sctrl |= SCTRL_P1SMB;
    outl(s->sctrl, s->io+ES1371_REG_SERIAL_CONTROL);

    spin_unlock_irqrestore(&s->lock, flags);

    return;
} /* set_dac1_mode() */



/*----------------------------- set_dac2_mode() -----------------------------*\
*									      *
*	Set playbackmode for dac2.                                            *
*									      *
\*---------------------------------------------------------------------------*/

void set_dac2_mode(struct es1371_state *s, BOOL sb16, BOOL stereo)
{
    unsigned long	flags;

    stop_dac2(s);

    spin_lock_irqsave(&s->lock, flags);

    s->sctrl = inl(s->io+ES1371_REG_SERIAL_CONTROL);
    s->sctrl &= ~SCTRL_P2FMT;

				/* Using 8- or 16-bit samples.               */
    if (sb16)
	s->sctrl |= SCTRL_P2SEB;
				/* Is stereo sound enabled.                  */
    if (stereo)
	s->sctrl |= SCTRL_P2SMB;
    outl(s->sctrl, s->io+ES1371_REG_SERIAL_CONTROL);

    spin_unlock_irqrestore(&s->lock, flags);

    return;
} /* set_dac2_mode() */



/*---------------------------- set_attenuation() ----------------------------*\
*									      *
*	Set attenuation for register reg. Attenuation for left and right      *
*	is specified as integer between 0 (no attenuation) and 31 or 63       *
*	(inaudible) depending on reg like documented in the ac97 spec.        *
*									      *
\*---------------------------------------------------------------------------*/

void set_attenuation(struct es1371_state *s, unsigned int reg, int left, int right, int mute)
{
    unsigned int	data=0;

    data = (left << 8) & AC97_LEFTVOL;
    data |= (right & AC97_RIGHTVOL);

    if (mute)
	data |= AC97_MUTE;

    wrcodec(s, reg, data);

    return;
} /* set_attenuation() */



/*---------------------------- get_attenuation() ----------------------------*\
*									      *
*	Read attenuations for source specified by reg.                        *
*									      *
\*---------------------------------------------------------------------------*/

void get_attenuation(struct es1371_state *s, unsigned int reg, int *left, int *right, int *mute)
{
    unsigned int	data=rdcodec(s, reg);

    *left = (data & AC97_LEFTVOL) >> 8;
    *right = (data & AC97_RIGHTVOL);
    *mute = data & AC97_MUTE;

    return;
} /* get_attenuation() */



/*----------------------------- resetHardware()  ----------------------------*\
*									      *
*	Initializes and test the hardware on startup (probe_chip in linux     *
*	driver).                                                              *
*									      *
\*---------------------------------------------------------------------------*/

void resetHardware(struct es1371_state *s)
{
    unsigned int	cssr;
    int			val;
    int			val2;
    unsigned char	id[4];

    s->ctrl = 0;
    s->sctrl = 0;
    cssr = 0;

				/* initialize the chips                      */
    outl(s->ctrl, s->io+ES1371_REG_CONTROL);
    outl(s->sctrl, s->io+ES1371_REG_SERIAL_CONTROL);
    outl(0, s->io+ES1371_REG_LEGACY);

				/* if we are a 5880 turn on the AC97         */
    if (s->vendor == PCI_VENDOR_ID_ENSONIQ &&
	((s->device == PCI_DEVICE_ID_ENSONIQ_CT5880 &&
		s->rev == CT5880REV_CT5880_C) ||
	(s->device == PCI_DEVICE_ID_ENSONIQ_ES1371 &&
		s->rev == ES1371REV_CT5880_A) ||
	(s->device == PCI_DEVICE_ID_ENSONIQ_ES1371 &&
		s->rev == ES1371REV_ES1373_8)))
    {
	cssr |= CSTAT_5880_AC97_RST;
	outl(cssr, s->io+ES1371_REG_STATUS);
				/* need to delay around 20ms(bleech) to give
				   some CODECs enough time to wakeup         */
	IODelay(20000);
    } /* if */

				/* AC97 warm reset to start the bitclk       */
    outl(s->ctrl | CTRL_SYNCRES, s->io+ES1371_REG_CONTROL);
    IODelay(2);
    outl(s->ctrl, s->io+ES1371_REG_CONTROL);

    src_init(s);
				/* codec init                                */
				/* reset codec                               */
    wrcodec(s, AC97_RESET, 0);
				/* get codec ID                              */
    s->mix.codec_id = rdcodec(s, AC97_RESET);
    val = rdcodec(s, AC97_VENDOR_ID1);
    val2 = rdcodec(s, AC97_VENDOR_ID2);
    id[0] = val >> 8;
    id[1] = val;
    id[2] = val2 >> 8;
    id[3] = 0;
    if (id[0] <= ' ' || id[0] > 0x7f)
	id[0] = ' ';
    if (id[1] <= ' ' || id[1] > 0x7f)
	id[1] = ' ';
    if (id[2] <= ' ' || id[2] > 0x7f)
	id[2] = ' ';
    IOLog("%s: codec vendor %s (0x%04x%02x) revision %d (0x%02x)\n", DRV_TITLE,
	    id, val & 0xffff, (val2 >> 8) & 0xff, val2 & 0xff, val2 & 0xff);
    IOLog("%s: codec features", DRV_TITLE);

    if (s->mix.codec_id & CODEC_ID_DEDICATEDMIC)
	IOLog(" dedicated MIC PCM in");
    if (s->mix.codec_id & CODEC_ID_MODEMCODEC)
	IOLog(" Modem Line Codec");
    if (s->mix.codec_id & CODEC_ID_BASSTREBLE)
	IOLog(" Bass & Treble");
    if (s->mix.codec_id & CODEC_ID_SIMULATEDSTEREO)
	IOLog(" Simulated Stereo");
    if (s->mix.codec_id & CODEC_ID_HEADPHONEOUT)
	IOLog(" Headphone out");
    if (s->mix.codec_id & CODEC_ID_LOUDNESS)
	IOLog(" Loudness");
    if (s->mix.codec_id & CODEC_ID_18BITDAC)
	IOLog(" 18bit DAC");
    if (s->mix.codec_id & CODEC_ID_20BITDAC)
	IOLog(" 20bit DAC");
    if (s->mix.codec_id & CODEC_ID_18BITADC)
	IOLog(" 18bit ADC");
    if (s->mix.codec_id & CODEC_ID_20BITADC)
	IOLog(" 20bit ADC");
    IOLog("%s\n", (s->mix.codec_id & 0x3ff) ? "" : " none");
    val = (s->mix.codec_id >> CODEC_ID_SESHIFT) & CODEC_ID_SEMASK;
    IOLog("%s: stereo enhancement: %s\n", DRV_TITLE,
		(val <= 26 && stereo_enhancement[val]) ?
			stereo_enhancement[val] : "unknown");
				/* Mixereinstellungen vornehmen.             */
    wrcodec(s, AC97_CD_VOL, 0x4040);
    wrcodec(s, AC97_PCMOUT_VOL, 0x4040 | AC97_MUTE);
    wrcodec(s, AC97_LINEIN_VOL, 0x4040);
    wrcodec(s, AC97_MIC_VOL, 0x4040);

    return;
} /* resetHardware */


#undef outb
#undef outw
#undef outl
