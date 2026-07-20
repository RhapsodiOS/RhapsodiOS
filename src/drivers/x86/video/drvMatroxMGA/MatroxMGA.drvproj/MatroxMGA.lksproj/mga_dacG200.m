/* $XFree86: xc/programs/Xserver/hw/xfree86/vga256/drivers/mga/mga_dacG200.c,v 1.1.2.11 1998/11/01 07:51:18 dawes Exp $ */
/*
 * Millennium G200 RAMDAC driver
 *
 * Mirko Viviani, mirko.viviani@gmail.com
 * Ported to NEXTSTEP 3.3 and up
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
#include "mgax.h"
#include "xf86_Config.h"

#import "MGA.h"

@implementation MatroxMGA (G200)

/*
 * implementation
 */
 
#define DACREGSIZE 0x50
    
/*
 * Only change bits shown in this mask.  Ideally reserved bits should be
 * zeroed here.  Also, don't change the vgaioen bit here since it is
 * controlled elsewhere.
 *
 * XXX These settings need to be checked.
 */
#define OPTION1_MASK	0xFFFFFEFF
#define OPTION2_MASK	0xFFFFFFFF
#define OPTION3_MASK	0xFFFFFFFF

#define OPTION1_MASK_PRIMARY	0xFFFC0FF

/*
 * This is a convenience macro, so that entries in the driver structure
 * can simply be dereferenced with 'newVS->xxx'.
 * change ajv - new conflicts with the C++ reserved word.
 */
#define newVS ((vgaMGAPtr)vgaNewVideoState)

typedef struct {
	vgaHWRec std;                           /* good old IBM VGA */
	unsigned long Option;
	unsigned long Option2;
	unsigned long Option3;
	unsigned char DacRegs[DACREGSIZE];
	unsigned char ExtVga[6];
} vgaMGARec, *vgaMGAPtr;
    
/*
 * Read/write to the DAC via MMIO 
 */

/*
 * direct registers
 */
static unsigned char inMGAdreg(MGAMMIOBase, reg)
unsigned char *MGAMMIOBase;
unsigned char reg;
{
	return INREG8(RAMDAC_OFFSET + reg);
}

static void outMGAdreg(MGAMMIOBase, reg, val)
unsigned char *MGAMMIOBase;
unsigned char reg, val;
{
	OUTREG8(RAMDAC_OFFSET + reg, val);
}

/*
 * indirect registers
 */
void outMGAdac(MGAMMIOBase, reg, val)
unsigned char *MGAMMIOBase;
unsigned char reg, val;
{
	outMGAdreg(MGAMMIOBase, MGA1064_INDEX, reg);
	outMGAdreg(MGAMMIOBase, MGA1064_DATA, val);
}

unsigned char inMGAdac(MGAMMIOBase, reg)
unsigned char *MGAMMIOBase;
unsigned char reg;
{
	outMGAdreg(MGAMMIOBase, MGA1064_INDEX, reg);
	return inMGAdreg(MGAMMIOBase, MGA1064_DATA);
}

/*
 * MGACalcClock - Calculate the PLL settings (m, n, p, s).
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
 *   August 18, 1998 - Radoslaw Kapitan
 *   Adapted for G200 DAC
 *
 *   February 28, 1997 - Guy DESBIEF 
 *   Adapted for MGA1064SG DAC.
 *   based on MGACalcClock  written by [aem] Andrew E. Mileski
 */

/* The following values are in kHz */
/* they came from guess, need to be checked with doc !!!!!!!! */
#define MGA_MIN_VCO_FREQ     50000 // 120000
#define MGA_MAX_VCO_FREQ    310000 // 250000


static long /*double*/
MGACalcClock ( MGABios2Info *MGABios2, int Chipset, long f_out,
               int *best_m, int *best_n, int *p, int *s )
{
	int m=0, n=0;
	long /*double*/ f_pll, f_vco;
	long /*double*/ m_err, calc_f;
	long /*double*/ ref_freq;
	int feed_div_min, feed_div_max;
	int in_div_min, in_div_max;
	int post_div_max;

	switch( Chipset )
	{
	case PCI_CHIP_MGA1064:
		ref_freq     = 1431818;
		feed_div_min = 100;
		feed_div_max = 127;
		in_div_min   = 1;
		in_div_max   = 31;
		post_div_max = 7;
		break;
	case PCI_CHIP_MGAG400:
		ref_freq     = 2705050;
		feed_div_min = 7;
		feed_div_max = 127;
		in_div_min   = 1;
		in_div_max   = 31;
		post_div_max = 7;
		break;
	case PCI_CHIP_MGAG100:
	case PCI_CHIP_MGAG100_PCI:
	case PCI_CHIP_MGAG200:
	case PCI_CHIP_MGAG200_PCI:
	default:
		if (MGABios2->PinID && (MGABios2->VidCtrl & 0x20))
			ref_freq = 1431818;
		else
			ref_freq = 2705050;
		feed_div_min = 7;
		feed_div_max = 127;
		in_div_min   = 1;
		in_div_max   = 6;
		post_div_max = 7;
		break;
	}

	/* Make sure that f_min <= f_out <= f_max */
	if ( f_out < ( MGA_MIN_VCO_FREQ / 8))
		f_out = MGA_MIN_VCO_FREQ / 8;

	/*
	 * f_pll = f_vco / (p+1)
	 * Choose p so that MGA_MIN_VCO_FREQ   <= f_vco <= MGA_MAX_VCO_FREQ  
	 * we don't have to bother checking for this maximum limit.
	 */
	f_vco = /*( double )*/ f_out*100;
	for ( *p = 0; *p < post_div_max && f_vco < (MGA_MIN_VCO_FREQ * 100);
		*p = *p * 2 + 1, f_vco *= 2);

	/* Initial amount of error for frequency maximum */
	m_err = f_out * 100;

	/* Search for the different values of ( m ) */
	for ( m = in_div_min ; m <= in_div_max ; m++ )
	{
		/* see values of ( n ) which we can't use */
		for ( n = feed_div_min; n <= feed_div_max; n++ )
		{ 
			calc_f = ref_freq * (n + 1) / (m + 1) ;

		/*
		 * Pick the closest frequency.
		 */
			if (abs( calc_f - (f_out*100) ) < m_err ) {
				m_err = abs(calc_f - (f_out*100));
				*best_m = m;
				*best_n = n;
			}
		}
	}
	
	/* Now all the calculations can be completed */
	f_vco = ref_freq * (*best_n + 1) / (*best_m + 1);

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
	if ( (18000000/*.0*/ <= f_vco) )
		*s = 3;

	f_pll = f_vco / ( *p + 1 );

#ifdef DEBUG
//	ErrorF( "f_out_requ =%ld f_pll_real=%.1f f_vco=%.1f n=0x%x m=0x%x p=0x%x s=0x%x\n",
	ErrorF( "f_out_requ =%ld f_pll_real=%ld f_vco=%ld n=0x%x m=0x%x p=0x%x s=0x%x\n",
		f_out, f_pll, f_vco, *n, *m, *p, *s );
#endif

	return f_pll;
}


/*
 * MGASetPCLK - Set the pixel (PCLK) and loop (LCLK) clocks.
 *
 * PARAMETERS
 *   f_pll			IN	Pixel clock PLL frequencly in kHz.
 */
- (void)MGASetPCLK:(long)f_out
{
	/* Pixel clock values */
	int m, n, p, s;

	/* The actual frequency output by the clock */
	long /*double*/ f_pll;

	if(MGAISG450)
	{
		[self G450SetPLLFreq: f_out];
		return;
	}

	/* Do the calculations for m, n, and p */
	f_pll = MGACalcClock( &MGABios2, Chipset, f_out, &m, &n, &p , &s);

	/* Values for the pixel clock PLL registers */
	newVS->DacRegs[ MGA1064_PIX_PLLC_M ] = m & 0x1f;
	newVS->DacRegs[ MGA1064_PIX_PLLC_N ] = n & 0x7f;
	newVS->DacRegs[ MGA1064_PIX_PLLC_P ] = (p & 0x07) | ((s & 0x3) << 3);
}

/*
 * MGAG200Init
 *
 * The 'mode' parameter describes the video mode.	The 'mode' structure 
 * as well as the 'vga256InfoRec' structure can be dereferenced for
 * information that is needed to initialize the mode.	The 'new' macro
 * (see definition above) is used to simply fill in the structure.
 */
- (BOOL)MGAG200Init:(DisplayModePtr)mode
{
	/*
	 * initial values of the DAC registers
	 */
	static unsigned char initDAC[] = {
	/* 0x00: */	   0,    0,    0,    0,    0,    0, 0x00,    0,
	/* 0x08: */	   0,    0,    0,    0,    0,    0,    0,    0,
	/* 0x08: */	   0,    0,    0,    0,    0,    0,    0,    0,
	/* 0x18: */	0x00,    0, 0xC9, 0xFF, 0xBF, 0x20, 0x1F, 0x20,
	/* 0x20: */	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	/* 0x28: */	0x00, 0x00, 0x00, 0x00,    0,    0,    0, 0x40,
	/* 0x30: */	0x00, 0xB0, 0x00, 0xC2, 0x34, 0x14, 0x02, 0x83,
	/* 0x38: */	0x00, 0x93, 0x00, 0x77, 0x00, 0x00, 0x00, 0x3A,
	/* 0x40: */	   0,    0,    0,    0,    0,    0,    0,    0,
	/* 0x48: */	   0,    0,    0,    0,    0,    0,    0,    0
	};

	int hd, hs, he, ht, vd, vs, ve, vt, wd;
	int i, BppShift;
	int weight555 = FALSE;
	vgaMGAPtr pReg;
	vgaHWRec *pVga;

	BppShift = MGABppShifts[(vgaBitsPerPixel >> 3) - 1];

	/*
	 * This will allocate the datastructure and initialize all of the
	 * generic VGA registers.
	 */
	if (![self vgaHWInit:mode size:sizeof(vgaMGARec)])
		return(FALSE);

	pReg = vgaNewVideoState;
	pVga = &((vgaMGAPtr)vgaNewVideoState)->std;

	for (i = 0; i < DACREGSIZE; i++)
	{
	    pReg->DacRegs[i] = initDAC[i]; 
	}

	switch(Chipset)
	{
	case PCI_CHIP_MGA1064:
		pReg->DacRegs[ MGA1064_SYS_PLL_M ] = 0x04;
		pReg->DacRegs[ MGA1064_SYS_PLL_N ] = 0x44;
		pReg->DacRegs[ MGA1064_SYS_PLL_P ] = 0x18;
		pReg->Option  = 0x5F094F21;
		pReg->Option2 = 0x00000000;
		break;
	case PCI_CHIP_MGAG100:
	case PCI_CHIP_MGAG100_PCI:
		pReg->DacRegs[ MGAGDAC_XVREFCTRL ] = 0x03;
		if(MGAHasSDRAM) {
		    if(OverclockMem) {
                        /* 220 Mhz */
			pReg->DacRegs[ MGA1064_SYS_PLL_M ] = 0x06;
			pReg->DacRegs[ MGA1064_SYS_PLL_N ] = 0x38;
			pReg->DacRegs[ MGA1064_SYS_PLL_P ] = 0x18;
		    } else {
                        /* 203 Mhz */
			pReg->DacRegs[ MGA1064_SYS_PLL_M ] = 0x01;
			pReg->DacRegs[ MGA1064_SYS_PLL_N ] = 0x0E;
			pReg->DacRegs[ MGA1064_SYS_PLL_P ] = 0x18;
		    }
		    pReg->Option = 0x404991a9;
		} else {
		    if(OverclockMem) {
                        /* 143 Mhz */
			pReg->DacRegs[ MGA1064_SYS_PLL_M ] = 0x06;
			pReg->DacRegs[ MGA1064_SYS_PLL_N ] = 0x24;
			pReg->DacRegs[ MGA1064_SYS_PLL_P ] = 0x10;
		    } else {
		        /* 124 Mhz */
			pReg->DacRegs[ MGA1064_SYS_PLL_M ] = 0x04;
			pReg->DacRegs[ MGA1064_SYS_PLL_N ] = 0x16;
			pReg->DacRegs[ MGA1064_SYS_PLL_P ] = 0x08;
		    }
		    pReg->Option = 0x4049d121;
		}
		pReg->Option2 = 0x0000007;
		break;
	case PCI_CHIP_MGAG400:
	       if (MGAISG450)
		       break;

	       if(MGAdac.maxPixelClock == 360000) {  /* G400 MAX */
	           if(OverclockMem) {
			/* 150/200  */
			pReg->DacRegs[ MGA1064_SYS_PLL_M ] = 0x05;
			pReg->DacRegs[ MGA1064_SYS_PLL_N ] = 0x42;
			pReg->DacRegs[ MGA1064_SYS_PLL_P ] = 0x18;
			pReg->Option3 = 0x019B8419;
			pReg->Option = 0x50574120;
		   } else {
			/* 125/166  */
			pReg->DacRegs[ MGA1064_SYS_PLL_M ] = 0x02;
			pReg->DacRegs[ MGA1064_SYS_PLL_N ] = 0x1B;
			pReg->DacRegs[ MGA1064_SYS_PLL_P ] = 0x18;
			pReg->Option3 = 0x019B8419;
			pReg->Option = 0x5053C120;
		   } 
		} else {
	           if(OverclockMem) {
			/* 125/166  */
			pReg->DacRegs[ MGA1064_SYS_PLL_M ] = 0x02;
			pReg->DacRegs[ MGA1064_SYS_PLL_N ] = 0x1B;
			pReg->DacRegs[ MGA1064_SYS_PLL_P ] = 0x18;
			pReg->Option3 = 0x019B8419;
			pReg->Option = 0x5053C120;
		   } else {
			/* 110/166  */
			pReg->DacRegs[ MGA1064_SYS_PLL_M ] = 0x13;
			pReg->DacRegs[ MGA1064_SYS_PLL_N ] = 0x7A;
			pReg->DacRegs[ MGA1064_SYS_PLL_P ] = 0x08;
			pReg->Option3 = 0x0190a421;
			pReg->Option = 0x50044120;
		   } 
		}
		if(MGAHasSDRAM)
		   pReg->Option &= ~(1 << 14);
		pReg->Option2 = 0x01003000;
		break;
	case PCI_CHIP_MGAG200:
	case PCI_CHIP_MGAG200_PCI:
	default:
#ifdef USEMGAHAL
	       MGA_HAL(break;);
#endif
		if(OverclockMem) {
                     /* 143 Mhz */
		    pReg->DacRegs[ MGA1064_SYS_PLL_M ] = 0x06;
		    pReg->DacRegs[ MGA1064_SYS_PLL_N ] = 0x24;
		    pReg->DacRegs[ MGA1064_SYS_PLL_P ] = 0x10;
		} else {
		    /* 124 Mhz */
		    pReg->DacRegs[ MGA1064_SYS_PLL_M ] = 0x04;
		    pReg->DacRegs[ MGA1064_SYS_PLL_N ] = 0x2D;
		    pReg->DacRegs[ MGA1064_SYS_PLL_P ] = 0x19;
		}
	        pReg->Option2 = 0x00008000;
		if(MGAHasSDRAM)
		    pReg->Option = 0x40499121;
		else
		    pReg->Option = 0x4049cd21;
		break;
	}

	/* must always have the pci retries on but rely on 
	   polling to keep them from occuring */
	pReg->Option &= ~0x20000000;

	switch(vgaBitsPerPixel)
	{
	case 8:
		pReg->DacRegs[ MGA1064_MUL_CTL ] = MGA1064_MUL_CTL_8bits;
		break;
	case 16:
		pReg->DacRegs[ MGA1064_MUL_CTL ] = MGA1064_MUL_CTL_16bits;
		if ( (xf86weight.red == 5) && (xf86weight.green == 5)
					&& (xf86weight.blue == 5) ) {
			weight555 = TRUE;
			pReg->DacRegs[ MGA1064_MUL_CTL ] = MGA1064_MUL_CTL_15bits;
		}
		break;
	case 24:
		pReg->DacRegs[ MGA1064_MUL_CTL ] = MGA1064_MUL_CTL_24bits;
		break;
	case 32:
/*		if(Overlay8Plus24) {
		   pReg->DacRegs[ MGA1064_MUL_CTL ] = MGA1064_MUL_CTL_32bits;
		   pReg->DacRegs[ MGA1064_COL_KEY_MSK_LSB ] = 0xFF;
		   pReg->DacRegs[ MGA1064_COL_KEY_LSB ] = pMga->colorKey;
		} else*/
			pReg->DacRegs[ MGA1064_MUL_CTL ] = MGA1064_MUL_CTL_32_24bits;
		break;
	default:
		FatalError("MGA: unsupported depth\n");
	}
		
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
	
	/* HTOTAL & 0x7 equal to 0x6 in 8bpp or 0x4 in 24bpp causes strange
	 * vertical stripes
	 */  
	if((ht & 0x07) == 0x06 || (ht & 0x07) == 0x04)
		ht++;
		
	if (vgaBitsPerPixel == 24)
		wd = (vga256InfoRec.displayWidth * 3) >> (4 - BppShift);
	else
		wd = vga256InfoRec.displayWidth >> (4 - BppShift);

	pReg->ExtVga[0] = 0;
	pReg->ExtVga[5] = 0;
	
	if (mode->Flags & V_INTERLACE)
	{
		pReg->ExtVga[0] = 0x80;
		pReg->ExtVga[5] = (hs + he - ht) >> 1;
		wd <<= 1;
		vt &= 0xFFFE;
	}

	pReg->ExtVga[0]	|= (wd & 0x300) >> 4;
	pReg->ExtVga[1]	= (((ht - 4) & 0x100) >> 8) |
				((hd & 0x100) >> 7) |
				((hs & 0x100) >> 6) |
				(ht & 0x40);
	pReg->ExtVga[2]	= ((vt & 0xc00) >> 10) |
				((vd & 0x400) >> 8) |
				((vd & 0xc00) >> 7) |
				((vs & 0xc00) >> 5);
	if (vgaBitsPerPixel == 24)
		pReg->ExtVga[3]	= (((1 << BppShift) * 3) - 1) | 0x80;
	else
		pReg->ExtVga[3]	= ((1 << BppShift) - 1) | 0x80;

//	pReg->ExtVga[3] &= 0xE7;	/* ajv - bits 4-5 MUST be 0 or bad karma happens */

	pReg->ExtVga[4]	= 0;
		
	pReg->std.CRTC[0]	= ht - 4;
	pReg->std.CRTC[1]	= hd;
	pReg->std.CRTC[2]	= hd;
	pReg->std.CRTC[3]	= (ht & 0x1F) | 0x80;
	pReg->std.CRTC[4]	= hs;
	pReg->std.CRTC[5]	= ((ht & 0x20) << 2) | (he & 0x1F);
	pReg->std.CRTC[6]	= vt & 0xFF;
	pReg->std.CRTC[7]	= ((vt & 0x100) >> 8 ) |
				((vd & 0x100) >> 7 ) |
				((vs & 0x100) >> 6 ) |
				((vd & 0x100) >> 5 ) |
				0x10 |
				((vt & 0x200) >> 4 ) |
				((vd & 0x200) >> 3 ) |
				((vs & 0x200) >> 2 );
	pReg->std.CRTC[9]	= ((vd & 0x200) >> 4) | 0x40; 
	pReg->std.CRTC[16] = vs & 0xFF;
	pReg->std.CRTC[17] = (ve & 0x0F) | 0x20;
	pReg->std.CRTC[18] = vd & 0xFF;
	pReg->std.CRTC[19] = wd & 0xFF;
	pReg->std.CRTC[21] = vd & 0xFF;
	pReg->std.CRTC[22] = (vt + 1) & 0xFF;

#if 0
	orig = pciReadLong(MGAPciTag, PCI_OPTION_REG) & (0x17 << 10);
	if (MGA_IS_G200(Chipset) || MGA_IS_G400(Chipset)) {
	    /* we want to leave the hardpwmsk 
	       and memconfig bits alone, in case this is an SDRAM card */
	    pReg->DAClong = 0x40078121 | orig; 
	}
	else if (MGA_IS_G100(Chipset)) {
	    pReg->DAClong = 0x400781A9 | orig;
	}
#endif

	if (OFLG_ISSET(OPTION_SYNC_ON_GREEN, &vga256InfoRec.options))
	{
		pReg->DacRegs[MGA1064_GEN_CTL] &= ~0x20;
		pReg->ExtVga[3] |= 0x40;
	}
#if 0
        if(OFLG_ISSET(OPTION_PCI_RETRY, &vga256InfoRec.options))
	    pReg->Option &= ~(1 << 29);
	else
	    pReg->Option |= (1 << 29);
#endif

	/* select external clock */
	pVga->MiscOutReg |= 0x0C; 

	if (mode->Flags & V_DBLSCAN)
		pVga->CRTC[9] |= 0x80;

	if(MGAISG450)
	{
		OUTREG(MGAREG_ZORG, 0);
	}

//	[self MGASetPCLK:vga256InfoRec.clock[newVS->std.NoClock]];
	[self MGASetPCLK:mode->Clock];

#ifdef DEBUG		
	ErrorF("MGAInit: Inforec pixclk=");
	ErrorF("%6ld pixclk: m=%02X n=%02X p=%02X\n",
//		vga256InfoRec.clock[pReg->std.NoClock]);
		mode->Clock);
	ErrorF("DAClong: %08lX\n", pReg->DAClong);

	ErrorF("pReg ->DacRegs:\n");

	for(i=0; i<sizeof(pReg->DacRegs); i++) {
		ErrorF("%02X->%02X ",i, pReg->DacRegs[i]);
		if ((i % 8) == 7 )
			ErrorF("\n");
	}
	ErrorF("\n");
	ErrorF("Physical DacRegs\n");
	for(i=0; i<sizeof(pReg->DacRegs); i++) {
		ErrorF("%02X->%02X ",i,inMGAdac(MGAMMIOBase, i));
		if ((i % 8) == 7 )
			ErrorF("\n");
	}
	ErrorF("\nExtVgaRegs:");
	for (i=0; i<6; i++) ErrorF(" %02X", pReg->ExtVga[i]);
	ErrorF("\n");
#endif

	/* Set adress of cursor image */
	pReg->DacRegs[4] = (vga256InfoRec.videoRam-1) & 0xFF;
	pReg->DacRegs[5] = (vga256InfoRec.videoRam-1) >> 8;

	/* This disables the VGA memory aperture */
	pVga->MiscOutReg &= ~0x02;

	return(TRUE);
}

/*
 * MGAG200Restore
 *
 * This function restores a video mode.	 It basically writes out all of
 * the registers that have previously been saved in the vgaMGARec data 
 * structure.
 */
- (void)MGAG200Restore:(vgaMGAPtr)restore
{
	int i;
	CARD32 optionMask;

	/*
	 * Code is needed to get things back to bank zero.
	 */

	/* restore DAC regs */
	for (i = 0; i < DACREGSIZE; i++) {
	    if( (i <= 0x03) ||
	    	(i == 0x07) ||
	    	(i == 0x0b) ||
	    	(i == 0x0f) ||
	       ((i >= 0x13) && (i <= 0x17)) ||
	    	(i == 0x1b) ||
	    	(i == 0x1c) ||
	       ((i >= 0x1f) && (i <= 0x29)) ||
	       ((i >= 0x30) && (i <= 0x37)) ||
		  (MGAISG450 &&
		   ((i == 0x2c) || (i == 0x2d) || (i == 0x2e) ||
		    (i == 0x4c) || (i == 0x4d) || (i == 0x4e))))
	       		continue; 
	    outMGAdac(MGAMMIOBase, i, restore->DacRegs[i]);
	}

	/* Do not set the memory config for primary cards as it
	   should be correct already */
	optionMask = (primaryHead) ? OPTION1_MASK_PRIMARY : OPTION1_MASK; 

	if (!MGAISG450)
	{
		/* restore pci_option register */
		pciSetBitsLong(MGAPciTag.tag, PCI_OPTION_REG, optionMask,
			       restore->Option);
		if (Chipset != PCI_CHIP_MGA1064)
			pciSetBitsLong(MGAPciTag.tag, PCI_MGA_OPTION2,
					OPTION2_MASK, restore->Option2);
		if (Chipset == PCI_CHIP_MGAG400)
			pciSetBitsLong(MGAPciTag.tag, PCI_MGA_OPTION3,
				OPTION3_MASK, restore->Option3);
	}

	/* restore CRTCEXT regs */
	for (i = 0; i < 6; i++)
		OUTREG16(0x1FDE, (restore->ExtVga[i] << 8) | i);

	/*
	 * This function handles restoring the generic VGA registers.
	 */
	[self vgaHWRestore:(vgaHWPtr)restore];

	/*
	 * this is needed to properly restore start address (???)
	 */
	OUTREG16(0x1FDE, (restore->ExtVga[0] << 8) | 0);
}

/*
 * MGAG200Save --
 *
 * This function saves the video state.	 It reads all of the SVGA registers
 * into the vgaMGARec data structure.
 */
- (void)MGAG200Save:(vgaMGAPtr)save
{
	int i;
	
	/*
	 * Code is needed to get back to bank zero.
	 */
	OUTREG16(0x1FDE, 0x0004);
	
	/*
	 * This function will handle creating the data structure and filling
	 * in the generic VGA portion.
	 */
	save = (vgaMGAPtr)[self vgaHWSave:save withSize:sizeof(vgaMGARec)];
//	MGAGSavePalette(pScrn, vgaReg->DAC);

	/*
	 * The port I/O code necessary to read in the extended registers 
	 * into the fields of the vgaMGARec structure.
	 */
	for (i = 0; i < DACREGSIZE; i++)
		save->DacRegs[i] = inMGAdac(MGAMMIOBase, i);

	save->Option = pciReadLong(MGAPciTag, PCI_OPTION_REG);

	save->Option2 = pciReadLong(MGAPciTag, PCI_MGA_OPTION2);
	if (Chipset == PCI_CHIP_MGAG400)
	    save->Option3 = pciReadLong(MGAPciTag, PCI_MGA_OPTION3);

	for (i = 0; i < 6; i++) {
		OUTREG8(0x1FDE, i);
		save->ExtVga[i] = INREG8(0x1FDF);
	}

	vgaSaved = save;
}

- (void)MGAG200RamdacInit
{
	MGAdac.isHwCursor        = TRUE;
	MGAdac.CursorMaxWidth    = 64;
	MGAdac.CursorMaxHeight   = 64;
//	MGAdac.SetCursorColors   = MGA1064SetCursorColors;
//	MGAdac.SetCursorPosition = MGA1064SetCursorPosition;
//	MGAdac.LoadCursorImage   = MGA1064LoadCursorImage;
//	MGAdac.HideCursor        = MGA1064HideCursor;
//	MGAdac.ShowCursor        = MGA1064ShowCursor;
	MGAdac.CursorFlags       = USE_HARDWARE_CURSOR |
	                           HARDWARE_CURSOR_BIT_ORDER_MSBFIRST |
	                           HARDWARE_CURSOR_TRUECOLOR_AT_8BPP |
	                           HARDWARE_CURSOR_PROGRAMMED_ORIGIN |
	                           HARDWARE_CURSOR_CHAR_BIT_FORMAT |
				   HARDWARE_CURSOR_SWAP_SOURCE_AND_MASK |
	                           HARDWARE_CURSOR_PROGRAMMED_BITS;

	if (MGABios2.PinID && (MGABios2.PclkMax != 0xFF))
	{
		MGAdac.maxPixelClock = (MGABios2.PclkMax + 100) * 1000;
    	}
    	else
    	{
    		switch( Chipset )
    		{
    		case PCI_CHIP_MGA1064:
		    if ( ChipRev < 3 )
		    	MGAdac.maxPixelClock = 170000;
		    else
		        MGAdac.maxPixelClock = 220000;
		    break;
    		case PCI_CHIP_MGAG400:
		    /* We don't know the new pins format but we know that
		       the maxclock / 4 is where the RamdacType was in the
		       old pins format */
		    MGAdac.maxPixelClock = MGABios2.RamdacType * 4000;
		    if(MGAdac.maxPixelClock < 300000)
			MGAdac.maxPixelClock = 300000;
		    break;
		default:
		    MGAdac.maxPixelClock = 250000;
		}
	}

	MGAinterleave = FALSE;
}

@end
