/* $XFree86: xc/programs/Xserver/hw/xfree86/vga256/drivers/mga/mga_dac1064.c,v 1.1.2.15 1998/10/31 14:40:59 hohndel Exp $ */


/*
 * Mystique RAMDAC driver v1.3
 *
 * Author:	Andrew van der Stock
 * 		ajv@greebo.svhm.org.au
 *
 * Contributors:
 *
 * 		Radoslaw Kapitan,
 * 		dude.
 * 
 *		Dirk Hohndel
 *			hohndel@XFree86.Org
 *		integrated into XFree86-3.1.2Gg
 *		fixed some problems with PCI probing and mapping
 *
 *		David Dawes
 *			dawes@XFree86.Org
 *		some cleanups, and fixed some problems
 *
 *		Andrew E. Mileski
 *			aem@ott.hookup.net
 *		RAMDAC timing, and BIOS stuff
 *
 *		Leonard N. Zubkoff
 *			lnz@dandelion.com
 *		Support for 8MB boards, RGB Sync-on-Green, and DPMS.
 
 *		Guy DESBIEF
 *			g.desbief@aix.pacwan.net
 *		RAMDAC timing, for MGA 1064SG integrated RAMDAC
 *
 *		Andrew van der Stock, andrew.van.der.Stock@member.sage-au.org.au
 * 		MGA BIOS stuff
 *
 *      Mirko Viviani, mirko.viviani@gmail.com
 *      Ported to NEXTSTEP 3.3 and up
 *
*/
 
#include "driverkit/i386/ioPorts.h"
#include "xf86.h"
#include "xf86Priv.h"
#include "xf86_OSlib.h"
#include "xf86_HWlib.h"
#include "xf86cursor.h"
#include "vga.h"
#include "vgaPCI.h"

#include "mga_reg.h"
#include "mga_bios.h"
#include "mga.h"
#include "xf86_Config.h"

/*
 * exported functions
 */
void MGA1064RamdacInit();
Bool MGA1064Init();
void MGA1064Restore();
void *MGA1064Save();

#import "MGA.h"


void outMGA1064(unsigned char * MGAMMIOBase, unsigned char reg, unsigned char val);
unsigned char inMGA1064(unsigned char * MGAMMIOBase, unsigned char reg);
//static unsigned char inMGA1064dreg(unsigned char * MGAMMIOBase, unsigned char reg);
//static void outMGA1064dreg(unsigned char * MGAMMIOBase, unsigned char reg, unsigned char val);


@implementation MatroxMGA (M1064)

/*
 * implementation
 */
 
/*
 * indexes to mga1064sg registers (the order is important)
 */
static unsigned char MGADACregs[] = {
        0x04, 0x05, 0x08, 0x09, 0x0A, 0x0C, 0x0D, 0x0E,
	0x10, 0x11, 0x12, 0x18, 0x19, 0x1A, 0x1D, 0x1E, 
	0x2A, 0x2B, 0x2F, 0x38, 0x3A,
	0x3C, 0x3D, 0x3E, 0x40, 0x41, 0x42, 0x43
};

/*
 * initial values of the registers
 */
static unsigned char MGADACbpp8[] = {
        0xFF, 0x0F, 0xFF, 0xFF, 0xFF, 0x00, 0x00, 0x00,
	0x4B, 0xE4, 0xF9, 0x80, 0x00, 0x09, 0x20, 0x1F, 
	0x00, 0x1A, 0x40, 0x00, 0x07,
	0x00, 0x00, 0x0D, 0xCA, 0x33, 0x58, 0xC2
};

static unsigned char MGADACbpp16[] = {
        0xFF, 0x0F, 0xFF, 0xFF, 0xFF, 0x00, 0x00, 0x00,
	0x4B, 0xE4, 0xF9, 0x80, 0x02, 0x09, 0x20, 0x1F, 
	0x00, 0x1A, 0x40, 0x00, 0x07,
	0x00, 0x00, 0x0D, 0xCA, 0x33, 0x58, 0xC2
};

static unsigned char MGADACbpp24[] = {
        0xFF, 0x0F, 0xFF, 0xFF, 0xFF, 0x00, 0x00, 0x00,
	0x4B, 0xE4, 0xF9, 0x80, 0x03, 0x09, 0x20, 0x1F, 
	0x00, 0x1A, 0x40, 0x00, 0x07,
	0x00, 0x00, 0x0D, 0xCA, 0x33, 0x58, 0xC2
};

static unsigned char MGADACbpp32[] = {
        0xFF, 0x0F, 0xFF, 0xFF, 0xFF, 0x00, 0x00, 0x00,
	0x4B, 0xE4, 0xF9, 0x80, 0x07, 0xC9, 0x20, 0x1F, 
	0x00, 0x1A, 0x40, 0x00, 0x07,
	0x00, 0x00, 0x0D, 0xCA, 0x33, 0x58, 0xC2
};

#ifdef	PC98_MGA
static unsigned char PC98_MGADACbpp8[] = {
	0xFE, 0x03, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF,
	0x3F, 0x43, 0x50, 0x00, 0x05, 0x09, 0x20, 0x19, 
	0x10, 0x3f, 0x40, 0x00, 0x07,
	0x00, 0x00, 0x1C, 0xEE, 0x9A, 0x82, 0x5B
};

static unsigned char PC98_MGADACbpp16[] = {
	0xFE, 0x07, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF,
	0x3F, 0x43, 0x50, 0x00, 0x02, 0x09, 0x20, 0x19, 
	0x10, 0x3f, 0x40, 0x00, 0x07,
	0x00, 0x00, 0x1C, 0xEE, 0x9A, 0x82, 0x5B
};

static unsigned char PC98_MGADACbpp32[] = {
	0xFE, 0x07, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF,
	0x2A, 0x02, 0x10, 0x00, 0x07, 0xC9, 0x20, 0x19, 
	0x10, 0x3f, 0x40, 0x00, 0x07,
	0x00, 0x00, 0x00, 0x0E, 0x9A, 0x80, 0x5A
};
#endif	/* PC98_MGA */

/*
 * This is a convenience macro, so that entries in the driver structure
 * can simply be dereferenced with 'newVS->xxx'.
 * change ajv - new conflicts with the C++ reserved word.
 */
#define newVS ((vgaMGAPtr)vgaNewVideoState)

typedef struct {
	vgaHWRec std;                           /* good old IBM VGA */
	unsigned long DAClong;
	unsigned char DACclk[6];
	unsigned char DACreg[sizeof(MGADACregs)];
	unsigned char ExtVga[6];
} vgaMGARec, *vgaMGAPtr;
    
/*
 * Read/write to the DAC via MMIO 
 */

void outMGA1064(MGAMMIOBase, reg, val)
unsigned char *MGAMMIOBase;
unsigned char reg, val;
{
		OUTREG8(RAMDAC_OFFSET + MGA1064_INDEX, reg);
		OUTREG8(RAMDAC_OFFSET + MGA1064_DATA, val);
}

unsigned char inMGA1064(MGAMMIOBase, reg)
unsigned char *MGAMMIOBase;
unsigned char reg;
{
	unsigned char val;
	
		OUTREG8(RAMDAC_OFFSET + MGA1064_INDEX, reg);
		val = INREG8(RAMDAC_OFFSET + MGA1064_DATA);

	return val;
}

/*
 * direct registers
 */
/*static unsigned char inMGA1064dreg(MGAMMIOBase, reg)
unsigned char *MGAMMIOBase;
unsigned char reg;
{
	unsigned char val;
	
	val = INREG8(RAMDAC_OFFSET + reg);

	return val;
}

static void outMGA1064dreg(MGAMMIOBase, reg, val)
unsigned char *MGAMMIOBase;
unsigned char reg, val;
{
	OUTREG8(RAMDAC_OFFSET + reg, val);
}*/

/*
 * MGA1064SGCalcClock - Calculate the PLL settings (m, n, p, s).
 *
 * DESCRIPTION
 *   For more information, refer to the Matrox
 *   "MGA1064SG Developer Specification (document 10524-MS-0100).
 *     chapter 5.7.8. "PLLs Clocks Generators"
 *
 * PARAMETERS
 *   f_out		IN	Desired clock frequency.
 *   f_max		IN	Maximum allowed clock frequency.
 *   m			OUT	Value of PLL 'm' register.
 *   n			OUT	Value of PLL 'n' register.
 *   p			OUT	Value of PLL 'p' register.
 *   s			OUT	Value of PLL 's' filter register 
 *                              (pix pll clock only).
 *
 * HISTORY
 *   February 28, 1997 - Guy DESBIEF 
 *   Adapted for MGA1064SG DAC.
  *  based on MGACalcClock  written by [aem] Andrew E. Mileski
 */

/* The following values are in kHz */
/* #define MGA1064_MIN_VCO_FREQ  110000 */
#define MGA1064_MIN_VCO_FREQ  120000
#define MGA1064_MAX_VCO_FREQ    170000
#define MGA1064_MAX_PCLK_FREQ    170000
#define MGA1064_MAX_MCLK_FREQ 100000
#define MGA1064_REF_FREQ      1431818 /* gia' moltiplicata *100 */
#define MGA1064_FEED_DIV_MIN      100
#define MGA1064_FEED_DIV_MAX      127
#define MGA1064_IN_DIV_MIN      1
#define MGA1064_IN_DIV_MAX      31
#define MGA1064_POST_DIV_MIN      0
#define MGA1064_POST_DIV_MAX      3


static long /*double*/
MGA1064SGCalcClock ( f_out, f_max, m, n, p, s )
	long f_out;
	long f_max;
	int *m;
	int *n;
	int *p;
	int *s;
{
	int best_m=0, best_n=0;
	long /*double*/ f_pll, f_vco;
	long /*double*/ m_err, /*inc_m,*/ calc_f, /*f_out_f,*/ base_freq;

	/* Make sure that f_min <= f_out <= f_max */

	if ( f_out < ( MGA1064_MIN_VCO_FREQ / 8))
		f_out = MGA1064_MIN_VCO_FREQ / 8;

	if ( f_out > f_max ) {
		f_out = f_max;
#ifdef DEBUG
	ErrorF( "f_out adjusted to f_max =%ld\n",
		f_out );
#endif
	}

	/*
	 * f_pll = f_vco /  (2^p)
	 * Choose p so that MGA1064_MIN_VCO_FREQ   <= f_vco <= MGA1064_MAX_VCO_FREQ  
	 * we don't have to bother checking for this maximum limit.
	 */
	f_vco = /*( double )*/ f_out*100;
	for ( *p = 0; *p < MGA1064_POST_DIV_MAX && f_vco < (MGA1064_MIN_VCO_FREQ*100); ( *p )++ )
		f_vco *= 2.0;

	/* Initial value of calc_f for the loop */
	calc_f = 0;

	base_freq = MGA1064_REF_FREQ / ( 1 << *p );

	/* Initial amount of error for frequency maximum */
	m_err = f_out*100;

	/* Search for the different values of ( *m ) */
	for ( *m = 1 ; *m < 31 ; ( *m )++ ) {
		/* see values of ( *n ) which we can't use */
		for ( *n = 100; *n <= 127; ( *n )++ ) { 

			calc_f = (base_freq * (*n)) / *m ;

		/*
		 * Pick the closest frequency.
		 */
			if (abs( calc_f - (f_out*100) ) < m_err ) {
				m_err = abs(calc_f - (f_out*100));
				best_m = *m;
				best_n = *n;
#ifdef DEBUG1
/*	ErrorF( "best_m=%x, best_n=%x,  m_err %f, calc_f=%f\n",
		best_m, best_n, m_err, calc_f );*/
	ErrorF( "best_m=%x, best_n=%x,  m_err %ld, calc_f=%ld\n",
		best_m, best_n, m_err, calc_f );
#endif
			}
		}
	}
	
	/*  */

	/* Now all the calculations can be completed */
	f_vco = MGA1064_REF_FREQ * best_n / best_m;
/* Adjustments for filtering pll feed back */
	if ( (5000000/*.0*/ <= f_vco)
	&& (f_vco < 10000000/*.0*/) )
		*s = 0;	
	if ( (10000000/*.0*/ <= f_vco)
	&& (f_vco < 14000000/*.0*/) )
		*s = 1;	
	if ( (14000000/*.0*/ <= f_vco)
	&& (f_vco < 18000000/*.0*/) )
		*s = 2;	
	if ( (18000000/*.0*/ <= f_vco)
	&& (f_vco < 22000000/*.0*/) )
		*s = 3;	

	f_pll = f_vco / ( 1 << *p );

	*m = best_m - 1;
	*n = best_n - 1;
	*p = ( 1 << *p ) - 1 ; 
#ifdef DEBUG
/*	ErrorF( "f_out_requ =%ld f_pll_real=%.1f f_vco=%.1f n=0x%x m=0x%x p=0x%x s=0x%x\n",*/
	ErrorF( "f_out_requ =%ld f_pll_real=%ld f_vco=%ld n=0x%x m=0x%x p=0x%x s=0x%x\n",
		f_out, f_pll, f_vco, *n, *m, *p, *s );
#endif

	return f_pll;
}
/*
 * MGA1064SetPCLK - Set the pixel (PCLK) and loop (LCLK) clocks.
 *
 * PARAMETERS
 *   f_pll			IN	Pixel clock PLL frequencly in kHz.
 *   bpp			IN	Bytes per pixel.
 *
 * EXTERNAL REFERENCES
 *   vga256InfoRec.maxClock	IN	Max allowed pixel clock in kHz.
 *   vgaBitsPerPixel		IN	Bits per pixel.
 *
 * HISTORY
 *   March 26, 1997 - [aem] Guy DESBIEF
 *   modified for Mystique DAC not tested.
 *   January 11, 1997 - [aem] Andrew E. Mileski
 *   Split to simplify code for MCLK (=GCLK) setting.
 *
 *   December 14, 1996 - [aem] Andrew E. Mileski
 *   Fixed loop clock to be based on the calculated, not requested,
 *   pixel clock. Added f_max = maximum f_vco frequency.
 *
 *   October 19, 1996 - [aem] Andrew E. Mileski
 *   Commented the loop clock code (wow, I understand everything now),
 *   and simplified it a bit. This should really be two separate functions.
 *
 *   October 1, 1996 - [aem] Andrew E. Mileski
 *   Optimized the m & n picking algorithm. Added maxClock detection.
 *   Low speed pixel clock fix (per the docs). Documented what I understand.
 *
 *   ?????, ??, ???? - [???] ????????????
 */


- (void)MGA1064SGSetPCLK:(long)f_out bpp:(int)bpp
{
	/* Pixel clock values */
	int m, n, p, s;

//	unsigned char pclk_ctrl;
//	unsigned char misc_ctrl,misc_reg;

	/* The actual frequency output by the clock */
	long /*double*/ f_pll;
	long f_max;

	/* Get the maximum pixel clock frequency from the BIOS, 
         * or from a reasonable default
         */
	if ( MGABios2.PinID && MGABios2.PclkMax != 0xff )
		f_max = (MGABios2.PclkMax+100) * 1000; /* [ajv - scale it] */
	else
		f_max = MGA1064_MAX_PCLK_FREQ;

	if ( vga256InfoRec.maxClock < f_max )
		f_max = vga256InfoRec.maxClock;

	/* Do the calculations for m, n, and p */
	f_pll = MGA1064SGCalcClock( f_out, f_max, & m, & n, & p ,& s);

	/* Values for the pixel clock PLL registers */
	newVS->DACclk[ 0 ] = ( m & 0x1f );
	newVS->DACclk[ 1 ] = ( n & 0x7f );
	newVS->DACclk[ 2 ] = ( p & 0x07 | ((s & 0x3) << 3) );

#ifdef DEBUG
	ErrorF( "MGA1064SGSetPCLK: MISC Reg %x\n",inb(MGAREG_MISC_READ));
#endif
	/* Select PLL C values p 4-151 */
#ifdef JAMAIS
	misc_reg= inb(MGAREG_MISC_READ);
	misc_reg &= ~MGAREG_MISC_CLK_SEL_MGA_MSK;
	misc_reg |= MGAREG_MISC_CLK_SEL_MGA_PIX;
	outb(MGAREG_MISC_WRITE, misc_reg);
/* #endif */
#endif
#ifdef DEBUG
	ErrorF( "MGA1064SGSetPCLK: MISC Reg %x (apres ecriture)\n",inb(MGAREG_MISC_READ));
#endif

#ifdef DEBUG
	ErrorF( "MGA1064SGSetPCLK: pixpll_m=%x pixpll_n=%x pixpll_p=%x, misc_ctrl=%x\n"
		,inMGA1064( MGAMMIOBase, MGA1064_PIX_PLLC_M )
		,inMGA1064( MGAMMIOBase, MGA1064_PIX_PLLC_N )
		,inMGA1064( MGAMMIOBase, MGA1064_PIX_PLLC_P )
		,inMGA1064( MGAMMIOBase, MGA1064_MISC_CTL ) 
		);
	ErrorF( "bpp=%d \n", bpp);
#endif
}

#if 0
/*
 * MGA1064SGSetMCLK - Set the memory clock (MCLK) PLL.
 *
 * HISTORY
 *   March 26, 1997 - [aem] Guy DESBIEF
 *   modified not tested.
 */

static void
MGA1064SGSetMCLK( f_out )
	long f_out;
{
	double f_pll;
	int mclk_m, mclk_n, mclk_p,mclk_s;
	int pclk_m, pclk_n, pclk_p,pclk_s;
	int mclk_ctl, rfhcnt;
	long	option_reg;
	long	f_max;

	/* ajv - get it from the bios, if it exists */

	if (MGABios2.PinID)
		f_max = MGABios2.ClkMem * 1000;
	else
		f_max = MGA1064_MAX_MCLK_FREQ;

	f_pll = MGA1064SGCalcClock(
		f_out, f_max,
		& mclk_m, & mclk_n, & mclk_p ,& mclk_s
	);

	/* Save MCLK settings */
	/* modified Guy DESBIEF March 20 97 */

	pclk_n = inMGA1064( MGA1064_SYS_PLL_N );
	pclk_m = inMGA1064( MGA1064_SYS_PLL_M );
	pclk_p = (inMGA1064( MGA1064_SYS_PLL_P ) & 0x7);
	pclk_s = ((inMGA1064( MGA1064_SYS_PLL_P ) & 0x18) >>3) ;
	option_reg = pciReadLong(MGAPciTag, PCI_OPTION_REG);
#ifdef JAMAIS
	/* Sequence required according page 5.77 */
	/* Stop MCLK (sysclkdis = 1) according doc p 4.14 and 5.77 */
	/* Disable system clock */
	option_reg |= MGA1064_OPT_SYS_CLK_DIS;
	pciWriteLong( MGAPciTag, PCI_OPTION_REG, option_reg );

	/* select PCI bus clock */
	option_reg &= ~MGA1064_OPT_SYS_CLK_MSK;
	pciWriteLong( MGAPciTag, PCI_OPTION_REG, option_reg );

	/* Enable system clock */
	option_reg &= ~MGA1064_OPT_SYS_CLK_DIS;
	pciWriteLong( MGAPciTag, PCI_OPTION_REG, option_reg );


/* Set the new MCLK frequency  */
	/* Guy DESBIEF March 26 97 */	
	/* see page 4.189 */	
	outMGA1064( MGA1064_SYS_PLL_M, ( mclk_m & 0x1f ));
	/* see page 4.190 */	
	outMGA1064( MGA1064_SYS_PLL_N, mclk_n & 0x7f );
	/* see page 4.191 */	
	/* adjust filter also */	
	outMGA1064( MGA1064_SYS_PLL_P, ( (mclk_p & 0x07) | ((mclk_s & 0x03) << 3 )) );

	/* Wait for SYS PLL to lock on frequency */
	while (( inMGA1064( MGA1064_SYS_PLL_STAT ) & 0x40 ) == 0 ) {
		;
	}
	option_reg = pciReadLong(MGAPciTag, PCI_OPTION_REG);
	/* Disable system clock */
	option_reg |= MGA1064_OPT_SYS_CLK_DIS;
	pciWriteLong( MGAPciTag, PCI_OPTION_REG, option_reg );

	/* Select PLL clock */
	option_reg &= ~MGA1064_OPT_SYS_CLK_MSK;
	option_reg |= MGA1064_OPT_SYS_CLK_PLL;
	pciWriteLong( MGAPciTag, PCI_OPTION_REG, option_reg );

	/* Enable system clock */
	option_reg &= ~MGA1064_OPT_SYS_CLK_DIS;
	pciWriteLong( MGAPciTag, PCI_OPTION_REG, option_reg );

#endif	
	/* Set the WRAM refresh divider */
	rfhcnt = ( 332.0 * f_pll / 1280000.0 );
	if ( rfhcnt > 15 )
		rfhcnt = 0;

	rfhcnt <<= 16;

    	if(!OFLG_ISSET(OPTION_PCI_RETRY, &vga256InfoRec.options))
	   rfhcnt |= (1 << 29);

 	pciWriteLong( MGAPciTag, PCI_OPTION_REG, rfhcnt |
		( pciReadLong( MGAPciTag, PCI_OPTION_REG ) & ~0x200f0000 ));

#ifdef DEBUG
	ErrorF( "MGA1064SGSetMCLK: syspll_m=%x syspll_n=%x syspll_p=%x, option_reg=%x\n"
		,inMGA1064( MGA1064_SYS_PLL_M )
		,inMGA1064( MGA1064_SYS_PLL_N )
		,inMGA1064( MGA1064_SYS_PLL_P )
		,pciReadLong( MGAPciTag, PCI_OPTION_REG ) 
		);
	ErrorF( "rfhcnt=%d\n", rfhcnt );
#endif

}
#endif


/*
 * MGA1064Init
 *
 * The 'mode' parameter describes the video mode.	The 'mode' structure 
 * as well as the 'vga256InfoRec' structure can be dereferenced for
 * information that is needed to initialize the mode.	The 'new' macro
 * (see definition above) is used to simply fill in the structure.
 */
- (BOOL)MGA1064Init:(DisplayModePtr)mode
{
	int hd, hs, he, ht, vd, vs, ve, vt, wd;
	int i, index_1d=0;
	unsigned char* initDAC=NULL;
	int weight555 = FALSE;
	
#ifdef DEBUG
	ErrorF("MGA1064Init: depth %x bits\n",vgaBitsPerPixel);
#endif
	switch(vgaBitsPerPixel)
	{
	case 8:
		initDAC = MGADACbpp8;
		break;
	case 16:
		initDAC = MGADACbpp16;
		if ( (xf86weight.red == 5) && (xf86weight.green == 5)
					&& (xf86weight.blue == 5) ) {
			weight555 = TRUE;
			initDAC[12] = 0x01 ;
		}
		break;
	case 24:
		initDAC = MGADACbpp24;
		break;
	case 32:
		initDAC = MGADACbpp32;
		break;
	default:
		FatalError("MGA: unsupported depth\n");
	}
		
	/*
	 * This will allocate the datastructure and initialize all of the
	 * generic VGA registers.
	 */
	if (![self vgaHWInit:mode size:sizeof(vgaMGARec)])
		return(FALSE);

	/*
	 * Here all of the other fields of 'newVS' get filled in.
	 */
	hd = (mode->CrtcHDisplay	>> 3)	- 1;
	hs = (mode->CrtcHSyncStart	>> 3)	- 1;
	he = (mode->CrtcHSyncEnd	>> 3)	- 1;
	ht = (mode->CrtcHTotal		>> 3)	- 1;
	vd = mode->CrtcVDisplay			- 1;
	vs = mode->CrtcVSyncStart		- 1;
	ve = mode->CrtcVSyncEnd			- 1;
	vt = mode->CrtcVTotal			- 2;
	
	/* HTOTAL & 0xF equal to 0xE in 8bpp or 0x4 in 24bpp causes strange
	 * vertical stripes
	 */  
	if((ht & 0x0F) == 0x0E || (ht & 0x0F) == 0x04)
		ht++;
		
	if (vgaBitsPerPixel == 24)
		wd = (vga256InfoRec.displayWidth * 3) >> (4 - MGABppShft);
	else
		wd = vga256InfoRec.displayWidth >> (4 - MGABppShft);

	newVS->ExtVga[0] = 0;
	newVS->ExtVga[5] = 0;
	
	if (mode->Flags & V_INTERLACE)
	{
		newVS->ExtVga[0] = 0x80;
		newVS->ExtVga[5] = (hs + he - ht) >> 1;
		wd <<= 1;
		vt &= 0xFFFE;
	}

	newVS->ExtVga[0]	|= (wd & 0x300) >> 4;
	newVS->ExtVga[1]	= (((ht - 4) & 0x100) >> 8) |
				((hd & 0x100) >> 7) |
				((hs & 0x100) >> 6) |
				(ht & 0x40);
	newVS->ExtVga[2]	= ((vt & 0x400) >> 10) |
				((vt & 0x800) >> 10) |
				((vd & 0x400) >> 8) |
				((vd & 0x400) >> 7) |
				((vd & 0x800) >> 7) |
				((vs & 0x400) >> 5) |
				((vs & 0x800) >> 5);
	if (vgaBitsPerPixel == 24)
		newVS->ExtVga[3]	= (((1 << MGABppShft) * 3) - 1) | 0x80;
	else
		newVS->ExtVga[3]	= ((1 << MGABppShft) - 1) | 0x80;

	newVS->ExtVga[3] &= 0xE7;	/* ajv - bits 4-5 MUST be 0 or bad karma happens */

	newVS->ExtVga[4]	= 0;
		
	newVS->std.CRTC[0]	= ht - 4;
	newVS->std.CRTC[1]	= hd;
	newVS->std.CRTC[2]	= hd;
	newVS->std.CRTC[3]	= (ht & 0x1F) | 0x80;
	newVS->std.CRTC[4]	= hs;
	newVS->std.CRTC[5]	= ((ht & 0x20) << 2) | (he & 0x1F);
	newVS->std.CRTC[6]	= vt & 0xFF;
	newVS->std.CRTC[7]	= ((vt & 0x100) >> 8 ) |
				((vd & 0x100) >> 7 ) |
				((vs & 0x100) >> 6 ) |
				((vd & 0x100) >> 5 ) |
				0x10 |
				((vt & 0x200) >> 4 ) |
				((vd & 0x200) >> 3 ) |
				((vs & 0x200) >> 2 );
	newVS->std.CRTC[9]	= ((vd & 0x200) >> 4) | 0x40; 
	newVS->std.CRTC[16] = vs & 0xFF;
	newVS->std.CRTC[17] = (ve & 0x0F) | 0x20;
	newVS->std.CRTC[18] = vd & 0xFF;
	newVS->std.CRTC[19] = wd & 0xFF;
	newVS->std.CRTC[21] = vd & 0xFF;
	newVS->std.CRTC[22] = (vt + 1) & 0xFF;

	if (mode->Flags & V_DBLSCAN)
		newVS->std.CRTC[9] |= 0x80;
    
	for (i = 0; i < sizeof(MGADACregs); i++)
	{
	    newVS->DACreg[i] = initDAC[i]; 
	    if (MGADACregs[i] == 0x1D)
		index_1d = i;
	}

	/* Per DDK vid.c line 75, sync polarity should be controlled
	 * via the TVP3026 RAMDAC register 1D and so MISC Output Register
	 * should always have bits 6 and 7 set. */

#ifndef JAMAIS
	newVS->std.MiscOutReg |= 0x2B;
/*
	newVS->std.MiscOutReg &= ~0x1;
	newVS->std.MiscOutReg &= ~0xc;
	newVS->std.MiscOutReg |= 0x8;
*/
#else
	newVS->std.MiscOutReg |=  0xC0;
	if ((mode->Flags & (V_PHSYNC | V_NHSYNC)) &&
	    (mode->Flags & (V_PVSYNC | V_NVSYNC)))
	{
	    if (mode->Flags & V_PHSYNC)
		newVS->std.MiscOutReg &= ~0x40;
	    if (mode->Flags & V_PVSYNC)
		newVS->std.MiscOutReg &= ~0x80;
	}
	else
	{
	  int VDisplay = mode->VDisplay;
	  if (mode->Flags & V_DBLSCAN)
	    VDisplay *= 2;
	  if      (VDisplay < 400)
  		  newVS->std.MiscOutReg &= ~0x40; /* +hsync -vsync */
	  else if (VDisplay < 480)
  		  newVS->std.MiscOutReg &= ~0x80; /* -hsync +vsync */
	  else if (VDisplay < 768)
  		  newVS->std.MiscOutReg &= ~0x00; /* -hsync -vsync */
	  else
  		  newVS->std.MiscOutReg &= ~0xC0; /* +hsync +vsync */
	}
#endif
	if (OFLG_ISSET(OPTION_SYNC_ON_GREEN, &vga256InfoRec.options)) {
//		ErrorF("%s %s: sync on green\n",
//		    XCONFIG_GIVEN, vga256InfoRec.name);
		newVS->DACreg[index_1d] &= ~0x20;
		newVS->ExtVga[3] |= 0x40;
	}
	newVS->DAClong = 0x5F094F21;
        if(!OFLG_ISSET(OPTION_PCI_RETRY, &vga256InfoRec.options))
	    newVS->DAClong |= (1 << 29);

	[self MGA1064SGSetPCLK:mode->Clock bpp:(1 << MGABppShft)];

	/*
	 * init palette for palettized depths
	 */
	for(i = 0; i < 256; i++) {
		switch(vgaBitsPerPixel) 
		{
		case 16:
			newVS->std.DAC[i * 3 + 0] = i << 3;
			newVS->std.DAC[i * 3 + 1] = i << (weight555 ? 3 : 2);
			newVS->std.DAC[i * 3 + 2] = i << 3;
			break;
		case 24:
		case 32:
			newVS->std.DAC[i * 3 + 0] = i;
			newVS->std.DAC[i * 3 + 1] = i;
			newVS->std.DAC[i * 3 + 2] = i;
			break;
		}
	}
		
#ifdef DEBUG		
	ErrorF("MGA1064Init: Inforec pixclk=\n");
	ErrorF("%6ld pixclk: m=%02X n=%02X p=%02X\n"
	,vga256InfoRec.clock[newVS->std.NoClock],
	newVS->DACclk[0], newVS->DACclk[1], newVS->DACclk[2]
	);
	ErrorF("sysclk: m=%02X n=%02X p=%02X	DAClong: %08lX\n",
	newVS->DACclk[3], newVS->DACclk[4], newVS->DACclk[5], newVS->DAClong);

	ErrorF("NewVS ->DACregs:\n");

	for(i=0; i<sizeof(MGADACregs); i++) {
	    ErrorF("(ad=%02X) %02X ",MGADACregs[i],newVS->DACreg[i]);
	if ((i % 5) == 4 )
	ErrorF("\n");
	}
	ErrorF("\n");
	ErrorF("Physical DACregs\n");
	for(i=0; i<sizeof(MGADACregs); i++) {
	    ErrorF("(ad=%02X) %02X ",MGADACregs[i],inMGA1064(MGAMMIOBase, MGADACregs[i]));
	if ((i % 5) == 4 )
	ErrorF("\n");
	}
	ErrorF("ExtVgaRegs:");
	for (i=0; i<6; i++) ErrorF(" %02X", newVS->ExtVga[i]);
	ErrorF("\n");
#endif

	/* Set adress of cursor image */
	newVS->DACreg[0] = (vga256InfoRec.videoRam-1) & 0xFF;
	newVS->DACreg[1] = (vga256InfoRec.videoRam-1) >> 8;

	return(TRUE);
}

/*
 * MGA1064Restore
 *
 * This function restores a video mode.	 It basically writes out all of
 * the registers that have previously been saved in the vgaMGARec data 
 * structure.
 */
- (void)MGA1064Restore:(vgaMGAPtr)restore
{
	int i,j;
	long option_reg;

	/*
	 * Code is needed to get things back to bank zero.
	 */
	for (i = 0; i < 6; i++)
		outw(0x3DE, (restore->ExtVga[i] << 8) | i);

	/* restore DAC regs */
	for (i = 0; i < sizeof(MGADACregs); i++)
		outMGA1064(MGAMMIOBase, MGADACregs[i], restore->DACreg[i]);

	option_reg = pciReadLong(MGAPciTag, PCI_OPTION_REG) ;
#ifdef DEBUG
	ErrorF("MGA1064Restore(1): DAClong %x option_reg %x\n",
		restore->DAClong,option_reg);
#endif
	pciWriteLong(MGAPciTag, PCI_OPTION_REG, restore->DAClong );

	/*
	 * This function handles restoring the generic VGA registers.
	 */
	[self vgaHWRestore:(vgaHWPtr)restore];

	outb(0x3C2, restore -> std.MiscOutReg);

	/*
	 * Code to restore SVGA registers that have been saved/modified
	 * goes here. 
	 */
	outw(0x3DE, (restore->ExtVga[0] << 8) | 0);
	
	j = 0;
	/* restore Pix pll C regs */
	for (i = 0; i < 3; i++)
		outMGA1064(MGAMMIOBase, (MGA1064_PIX_PLLC_M + i), restore->DACclk[j++]);

	/* Wait for PIX PLL to lock on frequency */
	while (( inMGA1064( MGAMMIOBase, MGA1064_PIX_PLL_STAT ) & 0x40 ) == 0 ) {
		;
	}
#ifdef JAMAIS
	j = 3;
	/* restore Sys pll regs */
	for (i = 0; i < 3; i++)
		outMGA1064(MGAMMIOBase, (MGA1064_SYS_PLL_M + i), restore->DACclk[j++]);
#endif
	
#ifdef DEBUG
	ErrorF("PCI retry (0-enabled / 1-disabled): %d\n",
		!!(restore->DAClong & 0x20000000));
	ErrorF("MGA1064Restore: DAClong %x\n",
		restore->DAClong);
	ErrorF( "MGA1064Restore: MiscOutReg= %x\n",inb(0x3CC));
#endif		 
}

/*
 * MGA1064Save --
 *
 * This function saves the video state.	 It reads all of the SVGA registers
 * into the vgaMGARec data structure.
 *   March 3, 1997 - [aem] Guy DESBIEF
 *   modified and tested.
 */
- (void)MGA1064Save:(vgaMGAPtr)save
{
	int i,index_sav;
	unsigned char index_reg;
	
	/*
	 * Code is needed to get back to bank zero.
	 */
	outw(0x3DE, 0x0004);
	
	/*
	 * This function will handle creating the data structure and filling
	 * in the generic VGA portion.
	 */
	save = (vgaMGAPtr)[self vgaHWSave:save withSize:sizeof(vgaMGARec)];

	/*
	 * The port I/O code necessary to read in the extended registers 
	 * into the fields of the vgaMGARec structure.
	 */
	for (i = 0; i < 6; i++)
	{
		outb(0x3DE, i);
		save->ExtVga[i] = inb(0x3DF);
	}
	
	for (i = 0; i < sizeof(MGADACregs); i++)
		save->DACreg[i]	 = inMGA1064(MGAMMIOBase, MGADACregs[i]);
/* Reading Sys PLL register */
	index_reg = MGA1064_SYS_PLL_M;
	index_sav = 0;
	for (i = 0; i < 3; i++) {
		save->DACclk[index_sav++] = inMGA1064(MGAMMIOBase, index_reg++);
	}

/* Reading Pix PLL register */
	index_reg = MGA1064_PIX_PLLC_M;
/* C pix pll registers bank only */	
	for (i = 0; i < 3; i++) {
		save->DACclk[i] = inMGA1064(MGAMMIOBase, index_reg++);
	}
/*	save ->std.MiscOutReg = inb(0x3CC); */	
	save->DAClong = pciReadLong(MGAPciTag, PCI_OPTION_REG);
#ifdef DEBUG	
	ErrorF( "MGA1064Save: save->DAClong= %x\n",save->DAClong );
	ErrorF( "MGA1064Save: MiscOutReg= %x\n",inb(0x3CC));
#endif

	vgaSaved = save;
}

- (void)MGA1064RamdacInit
{
    MGAdac.isHwCursor        = TRUE;
	MGAdac.CursorMaxWidth    = 64;
	MGAdac.CursorMaxHeight   = 64;
	MGAdac.SetCursorColors   = NULL;
	MGAdac.SetCursorPosition = NULL;
	MGAdac.LoadCursorImage   = NULL;
	MGAdac.HideCursor        = NULL;
	MGAdac.ShowCursor        = NULL;
	MGAdac.CursorFlags       = USE_HARDWARE_CURSOR |
	                           HARDWARE_CURSOR_BIT_ORDER_MSBFIRST |
	                           HARDWARE_CURSOR_TRUECOLOR_AT_8BPP |
	                           HARDWARE_CURSOR_PROGRAMMED_ORIGIN |
	                           HARDWARE_CURSOR_CHAR_BIT_FORMAT |
	                           HARDWARE_CURSOR_SWAP_SOURCE_AND_MASK |
	                           HARDWARE_CURSOR_PROGRAMMED_BITS;

    if ( MGABios2.PinID )
    {
		MGAdac.maxPixelClock = (MGABios2.RamdacSpeed+100) * 1000;
#ifdef DEBUG
		ErrorF("Using BIOS value for maxPixelClock: %d kHz\n", MGAdac.maxPixelClock);
#endif
    }
    else
    {
		if ( ChipRev < 3 )
		   MGAdac.maxPixelClock = 170000;
		else
		   MGAdac.maxPixelClock = 220000;
	    }
}

@end
