/* $XConsortium: mga_driver.c /main/12 1996/10/28 05:13:26 kaleb $ */
/*
 * MGA Millennium (MGA2064W) with Ti3026 RAMDAC driver v.1.1
 *
 * The driver is written without any chip documentation. All extended ports
 * and registers come from tracing the VESA-ROM functions.
 * The BitBlt Engine comes from tracing the windows BitBlt function.
 *
 * Author:	Radoslaw Kapitan, Tarnow, Poland
 *			kapitan@student.uci.agh.edu.pl
 *		original source
 *
 * Now that MATROX has released documentation to the public, enhancing
 * this driver has become much easier. Nevertheless, this work continues
 * to be based on Radoslaw's original source
 *
 * Contributors:
 *		Andrew Vanderstock, Melbourne, Australia
 *			vanderaj@mail2.svhm.org.au
 *		additions, corrections, cleanups, Mill II and BIOS stuff
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
 *		Doug Merritt
 *			doug@netcom.com
 *		Fixed 32bpp hires 8MB horizontal line glitch at middle right
 *
 *      Mirko Viviani, mirko.viviani@gmail.com
 *      Ported to NEXTSTEP 3.3 and up
 */
 
/* $XFree86: xc/programs/Xserver/hw/xfree86/vga256/drivers/mga/mga_driver.c,v 1.1.2.35 1998/10/31 14:41:00 hohndel Exp $ */

#include "X.h"
#include "input.h"
#include "screenint.h"

#import "driverkit/i386/ioPorts.h"
#import "driverkit/kernelDriver.h"
#include "xf86.h"
#include "xf86Priv.h"
#include "xf86_OSlib.h"
#include "xf86_HWlib.h"
#include "xf86_PCI.h"
#include "vga.h"
#include "vgaPCI.h"

#ifdef XFreeXDGA
#include "X.h"
#include "Xproto.h"
#include "scrnintstr.h"
#include "servermd.h"
#define _XF86DGA_SERVER_
#include "extensions/xf86dgastr.h"
#endif

#define XCONFIG_FLAGS_ONLY
#include "xf86_Config.h"

#include "mga_macros.h"
#include "mga_bios.h"
#include "mga_reg.h"
#include "mgax.h"

#import "MGA.h"

@implementation MatroxMGA (driver)


extern vgaPCIInformation *vgaPCIInfo;

/* #define DEFAULT_SW_CURSOR */

/*
 * Driver data structures.
 */

#ifndef __NeXT
MGABiosInfo MGABios;
MGABios2Info MGABios2;

pciTagRec MGAPciTag;
int Chipset;
int ChipRev;
int MGAinterleave;
int MGABppShft;
int MGAusefbitblt;
int MGAydstorg;
unsigned char* MGAMMIOBase = NULL;
#ifdef __alpha__
unsigned char* MGAMMIOBaseDENSE = NULL;
#endif
#endif

/*
 * Forward definitions for the functions that make up the driver.
 */

static char *		MGAIdent();

/*
 * This data structure defines the driver itself.
 */
vgaVideoChipRec MGAs = {
	/* 
	 * Function pointers
	 */
	NULL,
	NULL,
	NULL,
	NULL,
	NULL,
	NULL,
	NULL,
	NULL,
	NULL,
	(void (*)())NULL,	/* GetMode, */
	NULL,
	(void (*)())NULL,	/* SetRead, */
	(void (*)())NULL,	/* SetWrite, */
	(void (*)())NULL,	/* SetReadWrite, */
	/*
	 * This is the size of the mapped memory window, usually 64k.
	 */
	0x10000,		
	/*
	 * This is the size of a video memory bank for this chipset.
	 */
	0x10000,
	/*
	 * This is the number of bits by which an address is shifted
	 * right to determine the bank number for that address.
	 */
	16,
	/*
	 * This is the bitmask used to determine the address within a
	 * specific bank.
	 */
	0xFFFF,
	/*
	 * These are the bottom and top addresses for reads inside a
	 * given bank.
	 */
	0x00000, 0x10000,
	/*
	 * And corresponding limits for writes.
	 */
	0x00000, 0x10000,
	/*
	 * Whether this chipset supports a single bank register or
	 * seperate read and write bank registers.	Almost all chipsets
	 * support two banks, and two banks are almost always faster
	 */
	FALSE,
	/*
	 * The chipset requires vertical timing numbers to be divided
	 * by two for interlaced modes
	 */
	VGA_DIVIDE_VERT,
	/*
	 * This is a dummy initialization for the set of option flags
	 * that this driver supports.	It gets filled in properly in the
	 * probe function, if the probe succeeds (assuming the driver
	 * supports any such flags).
	 */
	{0,},
	/*
	 * This determines the multiple to which the virtual width of
	 * the display must be rounded for the 256-color server. 
	 */
	0,
	/*
	 * If the driver includes support for a linear-mapped frame buffer
	 * for the detected configuratio this should be set to TRUE in the
	 * Probe or FbInit function. 
	 */
	TRUE,
	/*
	 * This is the physical base address of the linear-mapped frame
	 * buffer (when used).	Set it to 0 when not in use.
	 */
	0,
	/*
	 * This is the size of the linear-mapped frame buffer (when used).
	 * Set it to 0 when not in use.
	 */
	0,
	/*
	 * This is TRUE if the driver has support for the given depth for 
	 * the detected configuration. It must be set in the Probe function.
	 * It most cases it should be FALSE.
	 */
	TRUE,	/* 16bpp */
	TRUE,	/* 24bpp */
	TRUE,	/* 32bpp */
	/*
	 * This is a pointer to a list of builtin driver modes.
	 * This is rarely used, and in must cases, set it to NULL
	 */
	NULL,
	/*
	 * This is a factor that can be used to scale the raw clocks
	 * to pixel clocks.	 This is rarely used, and in most cases, set
	 * it to 1.
	 */
	1,     /* ClockMulFactor */
	1     /* ClockDivFactor */
};


MGARamdacRec MGAdac = {
        FALSE, 0, 0, 0, NULL, NULL, NULL, NULL, NULL,
        90000, /* maxPixelClock */
        0
}; 



/*
 * MGAReadBios - Read the video BIOS info block.
 *
 * DESCRIPTION
 *   Warning! This code currently does not detect a video BIOS.
 *   In the future, support for motherboards with the mga2064w
 *   will be added (no video BIOS) - this is not a huge concern
 *   for me today though.
 *
 * EXTERNAL REFERENCES
 *   vga256InfoRec.BIOSbase	IN	Physical address of video BIOS.
 *   MGABios			OUT	The video BIOS info block.
 *
 * HISTORY
 *   August  31, 1997 - [ajv] Andrew van der Stock
 *   Fixed to understand Mystique and Millennium II
 * 
 *   January 11, 1997 - [aem] Andrew E. Mileski
 *   Set default values for GCLK (= MCLK / pre-scale ).
 *
 *   October 7, 1996 - [aem] Andrew E. Mileski
 *   Written and tested.
 */ 

int xf86ReadBIOS(Base, Offset, Buf, Len)
unsigned long Base;
unsigned long Offset;
unsigned char *Buf;
int Len;
{
	unsigned char *base;

	if(IOMapPhysicalIntoIOTask(Base+Offset, Len, &base) != IO_R_SUCCESS) return 0;

//	IOCopyMemory(Base+Offset, Buf, Len, 1);
	bcopy(base, Buf, Len);

	IOUnmapPhysicalFromIOTask(base, Len);

	return Len;
}


- (void)MGAReadBios
{
	CARD8 	tmp[ 64 ];
	CARD16 	offset;
	CARD8	chksum;
	CARD8	*pPINSInfo; 
	int i;

	/* Make sure the BIOS is present */
	xf86ReadBIOS( vga256InfoRec.BIOSbase, 0, tmp, sizeof( tmp ));

	if ( tmp[ 0 ] != 0x55 || tmp[ 1 ] != 0xaa
	     || strncmp(( char * )( tmp + 45 ), "MATROX", 6 ) )
        {
		ErrorF( "%s %s: Video BIOS info block not detected!\n",
			XCONFIG_PROBED, vga256InfoRec.name);
		return;
	}

	/* Get the info block offset */
	xf86ReadBIOS( vga256InfoRec.BIOSbase, 0x7ffc,
		( CARD8 * ) & offset, sizeof( offset ));

	/* Let the world know what we are up to */
#ifdef DEBUG
	ErrorF( "%s %s: Video BIOS info block at 0x%08lx\n",
		XCONFIG_PROBED, vga256InfoRec.name,
		vga256InfoRec.BIOSbase + offset );	
#endif

	/* Copy the info block */
	switch (Chipset)
	{
		case PCI_CHIP_MGA2064:
			xf86ReadBIOS( vga256InfoRec.BIOSbase, offset,
				( CARD8 * ) & MGABios.StructLen, sizeof( MGABios ));
		break;

		default:
			xf86ReadBIOS( vga256InfoRec.BIOSbase, offset,
				( CARD8 * ) & MGABios2.PinID, sizeof( MGABios2 ));
	}
	
	/* matrox millennium-2 and mystique pins info */
	if ( MGABios2.PinID == 0x412e )
	{
		/* check that the pins info is correct */
		if ( MGABios2.StructLen != 0x40 )
		{
			ErrorF( "%s %s: Video BIOS info block not detected!\n",
		                XCONFIG_PROBED, vga256InfoRec.name);
			return;
		}
		/* check that the chksum is correct */
		chksum = 0;
		pPINSInfo = (CARD8 *) &MGABios2.PinID;

		for (i=0; i < MGABios2.StructLen; i++)
		{
			chksum += *pPINSInfo;
			pPINSInfo++;
		}

		if ( chksum )
		{
			ErrorF("%s %s: Video BIOS info block did not checksum!\n",
		                XCONFIG_PROBED, vga256InfoRec.name);
			MGABios2.PinID = 0;
			return;
		}

		/* last check */
		if ( MGABios2.StructRev == 0 ) 
		{
			ErrorF( "%s %s: Video BIOS info block does not have a valid revision!\n",
		                XCONFIG_PROBED, vga256InfoRec.name);
			MGABios2.PinID = 0;
			return;
		}
		ErrorF( "%s %s: Found and verified enhanced Video BIOS info block\n",
			XCONFIG_PROBED, vga256InfoRec.name);

#if DEBUG
		ErrorF( "%s %s: MClk %d Clk4MB %d Clk8MB %d\n",
			XCONFIG_PROBED, vga256InfoRec.name,
			MGABios2.ClkMem,MGABios2.Clk4MB,MGABios2.Clk8MB);
#endif
	  	/* Set default MCLK values (scaled by 100 kHz) */
		if ( MGABios2.ClkMem == 0 )
		    MGABios2.ClkMem = 50;
	  	if ( MGABios2.Clk4MB == 0 )
		    MGABios2.Clk4MB = MGABios.ClkBase;
		if ( MGABios2.Clk8MB == 0 )
		    MGABios2.Clk8MB = MGABios.Clk4MB;
		MGABios.StructLen = 0; /* not in use */
		return;
	}
	else
	{
	  /* Set default MCLK values (scaled by 10 kHz) */
	  if ( MGABios.ClkBase == 0 )
		MGABios.ClkBase = 4500;
  	  if ( MGABios.Clk4MB == 0 )
		MGABios.Clk4MB = MGABios.ClkBase;
	  if ( MGABios.Clk8MB == 0 )
		MGABios.Clk8MB = MGABios.Clk4MB;
	  MGABios2.PinID = 0; /* not in use */
	  return;
	}
}

/*
 * MGACountRAM --
 *
 * Counts amount of installed RAM 
 * 
 * now counts in 2 MB increments, all the way to 16 MB.
 * also preserves fb contents, - ajv 970830
 * 
 * blocks = # of 2 MB blocks to check. = 4 on 8 MB addr, =8 on 16 MB addr 
 */

- (int)MGACountRam:(int)blocks
{
	int 	videoMem;

	videoMem = 2048;

	if(MGAs.ChipLinearBase)
	{
		volatile unsigned char* base=NULL;
		int			i, basePtr;
		unsigned char 		tmp, seed, oldMem, cacheMem, newMem[8];

/*		base = xf86MapVidMem(vga256InfoRec.scrnIndex, LINEAR_REGION,
			      (pointer)((unsigned long)MGAs.ChipLinearBase),
			      blocks * 2097152 );*/

#ifdef DEBUG
		IOLog("blocks=%ld Linear=%ld len=%ld\n", blocks, MGAs.ChipLinearBase, blocks * 2097152);
#endif

		if(IOMapPhysicalIntoIOTask(MGAs.ChipLinearBase, blocks * 2097152, &base) != IO_R_SUCCESS) return 0;

#ifdef DEBUG
		IOLog("base=%ld\n", (long)base);
#endif

		/* turn MGA mode on - enable linear frame buffer (CRTCEXT3) */
		OUTREG8(0x1FDE, 3);
		tmp = INREG8(0x1FDF);
		OUTREG8(0x1FDF, tmp | 0x80);
	
		/* write, read and compare method */

		seed = 0x11;

		/* clear out newMem */		
		newMem[0] = newMem[1] = newMem[2] = newMem[3] = 0;
		newMem[4] = newMem[5] = newMem[6] = newMem[7] = 0;

		basePtr = 0x100000;		/* 1 MB */
		cacheMem = base[0x5000];	/* cache flush spot */
		for (i = 0; i < blocks; i++)
		{	
			oldMem = base[basePtr];		/* remember previous contents */
			base[basePtr] = 0;		/* clear it */
			base[basePtr] = seed;
			OUTREG8(MGAREG_CRTC_INDEX, 0);  /* flush the cache */

			newMem[i] = base[basePtr];
			base[basePtr] = oldMem;		/* restore it to old val */
			seed += 0x11;	
			basePtr += 0x200000;		/* go forward another 2 MB */
		}
		base[0x5000] = cacheMem;	/* restore the state */

		/* restore CRTCEXT3 state */
		OUTREG8(0x1FDE, 3);
		OUTREG8(0x1FDF, tmp);

#ifdef DEBUG
		IOLog("pre unmap base\n");
#endif

		IOUnmapPhysicalFromIOTask(base, blocks * 2097152);

/*		xf86UnMapVidMem(vga256InfoRec.scrnIndex, LINEAR_REGION, 
				(pointer)base, blocks * 2097152 );*/
		seed = 0x11;
		videoMem = 0;
		
		for ( i=0; i < blocks; i++ )
		{
			if ( newMem[i] == seed )
			{
				seed += 0x11;
				videoMem += 2048;
			}
		}
	}
	return videoMem;
}

/*
 * MGAIdent --
 *
 * Returns the string name for supported chipset 'n'. 
 */
static char *
MGAIdent(n)
int n;
{
	static char *chipsets[] = {"mga2064w", "mga1064sg", "mga2164w",
	                           "mga2164w AGP", "mgag200", "mgag100",
				   "mgag400" };

	if (n + 1 > sizeof(chipsets) / sizeof(char *))
		return(NULL);
	else
		return(chipsets[n]);
}

/*
 * MGAProbe --
 *
 * This is the function that makes a yes/no decision about whether or not
 * a chipset supported by this driver is present or not. 
 */
- (BOOL)MGAProbe
{
	unsigned long MGAMMIOAddr = 0;
	pciConfigPtr pcr = &MGApcr;
//	pciConfigPtr mgapcr = pciConfig;
	int i;
	CARD32 save;

	Chipset = 0;
	i = 0;

	{
		int id = pcr->_device;

		Chipset = id;
		switch(id)
		{
			case PCI_CHIP_MGA2064:
				vga256InfoRec.chipset = MGAIdent(0);
				break;
			case PCI_CHIP_MGA1064:
				vga256InfoRec.chipset = MGAIdent(1);
				break;
			case PCI_CHIP_MGA2164:
				vga256InfoRec.chipset = MGAIdent(2);
				break;
			case PCI_CHIP_MGA2164_AGP:
				vga256InfoRec.chipset = MGAIdent(3);
				break;
			case PCI_CHIP_MGAG200:
			case PCI_CHIP_MGAG200_PCI:
				vga256InfoRec.chipset = MGAIdent(4);
				break;
			case PCI_CHIP_MGAG100:
			case PCI_CHIP_MGAG100_PCI:
				vga256InfoRec.chipset = MGAIdent(5);
				break;
			case PCI_CHIP_MGAG400:
				vga256InfoRec.chipset = MGAIdent(6);
				break;
			default:
				Chipset = 0;
		}
		if(!Chipset) return(FALSE);
	}

	ChipRev = pcr->_rev_id;

	/*
	 *	OK. It's MGA
	 */
	 
	MGAPciTag = pcibusTag(pcr->_bus, pcr->_cardnum, pcr->_func);

	/* ajv changes to reflect actual values. see sdk pp 3-2. */
	/* these masks just get rid of the crap in the lower bits */
	/* XXX - ajv I'm assuming that pcr->_base0 is pci config space + 0x10 */
	/*				and _base1 is another four bytes on */
	/* XXX - these values are Intel byte order I believe. */
	/* rev 3 (at least Mystique 220) has these swapped */
	/* so does the Mill II */
	
	/* details: mgabase1 sdk pp 4-11 */
	/* details: mgabase2 sdk pp 4-12 */
	
	if ( Chipset == PCI_CHIP_MGA2064 ||
		Chipset == PCI_CHIP_MGA1064 && ChipRev < 3 )
	{
		MGAs.ChipLinearBase = pcr->_base1 & 0xff800000;
		MGAMMIOAddr = pcr->_base0 & 0xffffc000;
	} else {
		MGAs.ChipLinearBase = pcr->_base0 & 0xff800000;
		MGAMMIOAddr = pcr->_base1 & 0xffffc000;
	}

#ifdef DEBUG
	ErrorF("%08x\n", pcr->_baserom);
#endif

	/* Allow this to be overriden in the XF86Config file */
//	if (vga256InfoRec.BIOSbase == 0) {
//		if ( pcr->_baserom )	/* details: rombase sdk pp 4-15 */
//			vga256InfoRec.BIOSbase = pcr->_baserom & 0xffff0000;
//		else
			vga256InfoRec.BIOSbase = 0xc0000;
//	}
	if (vga256InfoRec.MemBase)
		MGAs.ChipLinearBase = vga256InfoRec.MemBase;
	if (vga256InfoRec.IObase)
		MGAMMIOAddr = vga256InfoRec.IObase;

	videoRamAddress = MGAs.ChipLinearBase;

	if (!MGAs.ChipLinearBase)
		FatalError("MGA: Can't detect linear framebuffer address\n");
	if (!MGAMMIOAddr)
		FatalError("MGA: Can't detect IO registers address\n");
	
/*	if (xf86Verbose)
	{
		ErrorF("%s %s: Linear framebuffer at 0x%lX\n", 
			vga256InfoRec.MemBase? XCONFIG_GIVEN : XCONFIG_PROBED,
			vga256InfoRec.name, MGAs.ChipLinearBase);
		ErrorF("%s %s: MMIO registers at 0x%lX\n", 
			vga256InfoRec.IObase? XCONFIG_GIVEN : XCONFIG_PROBED,
			vga256InfoRec.name, MGAMMIOAddr);
	}*/
	
#ifdef DEBUG
		ErrorF("Linear framebuffer at 0x%lX\n", 
			MGAs.ChipLinearBase);
		ErrorF("MMIO registers at 0x%lX\n", 
			MGAMMIOAddr);
		ErrorF("Video BIOS info block at 0x%lX\n", 
			vga256InfoRec.BIOSbase);
#endif

//	if(MGAMMIOAddr != 0xE2000000) MGAMMIOAddr = 0xE2000000;

	/* enable IO ports, etc. */
	[self MGAEnterLeave:ENTER];

	/*
	 * Disable memory and I/O before mapping the MMIO area.
	 * This avoids the MMIO area being read during the mapping
	 * (which happens on some SVR4 versions), which will cause
	 * a lockup.
	 */

	save = pciReadLong(MGAPciTag, PCI_CMD_STAT_REG);
	pciWriteLong(MGAPciTag, PCI_CMD_STAT_REG,
		     save & ~(PCI_CMD_IO_ENABLE | PCI_CMD_MEM_ENABLE));

	/*
	 * Map IO registers to virtual address space
	 */ 
	if(IOMapPhysicalIntoIOTask(MGAMMIOAddr, 0x4000, &MGAMMIOBase) != IO_R_SUCCESS)
	{
		ErrorF("Failed to map MMIO register !!\n");
		return FALSE;
	}

	/* Re-enable I/O and memory */
	pciWriteLong(MGAPciTag, PCI_CMD_STAT_REG,
		     save | (PCI_CMD_IO_ENABLE | PCI_CMD_MEM_ENABLE));

	if (!MGAMMIOBase)
		FatalError("MGA: Can't map IO registers\n");
	

	/*
	 * Read the BIOS data struct
	 */
	[self MGAReadBios];
#ifdef DEBUG
	ErrorF("MGABios.RamdacType = 0x%x\n",MGABios.RamdacType);
#endif
	
	/*
	 * If the user has specified the amount of memory in the XF86Config
	 * file, we respect that setting.
	 */

	if (!vga256InfoRec.videoRam) {
	   if ( MGA_IS_2164(Chipset) || MGA_IS_G100(Chipset) ) {
		vga256InfoRec.videoRam = 4096;
#ifdef EDEBUG
		ErrorF("(!!) %s: Unable to probe for video memory size.  "
			"Assuming 8 Meg.\tPlease specify the correct amount "
			"in the XF86Config file.\tSee the file README.MGA "
			"for details.\n", vga256InfoRec.name);
#endif
	   } else if (MGA_IS_G200(Chipset) || MGA_IS_G400(Chipset)) {
		vga256InfoRec.videoRam = 8192;
#ifdef EDEBUG
		ErrorF("(!!) %s: Unable to probe for video memory size.  "
			"Assuming 8 Meg.\tPlease specify the correct amount "
			"in the XF86Config file.\tSee the file README.MGA "
			"for details.\n", vga256InfoRec.name);
#endif
	   } else
		vga256InfoRec.videoRam = [self MGACountRam:4]; /* count to 8 mb */
	}

	MGAs.ChipLinearSize = vga256InfoRec.videoRam;

	/* sanity check ChipLinearSize */

	if ( MGA_IS_2164(Chipset) || MGA_IS_G100(Chipset) )
	{
		if ( MGAs.ChipLinearSize < 2048 || MGAs.ChipLinearSize > 16384 )
		{
			MGAs.ChipLinearSize = 2048; /* nice safe size */
			ErrorF("(!!) %s: reset VideoRAM to 2 MB for safety!\n",
				vga256InfoRec.name);
		}
	}
	else if( MGA_IS_G200(Chipset) )
	{
		if ( MGAs.ChipLinearSize < 4096 || MGAs.ChipLinearSize > 16384 )
		{
			MGAs.ChipLinearSize = 8192; /* nice safe size */
			ErrorF("(!!) %s: reset VideoRAM to 4 MB for safety!\n",
				vga256InfoRec.name);
		}
	}
	else if( MGA_IS_GCLASS(Chipset) )
	{
		if ( MGAs.ChipLinearSize < 4096 || MGAs.ChipLinearSize > 32768 )
		{
			MGAs.ChipLinearSize = 8192; /* nice safe size */
			ErrorF("(!!) %s: reset VideoRAM to 8 MB for safety!\n",
				vga256InfoRec.name);
		}
	}
	else
	{
		if ( MGAs.ChipLinearSize < 2048 || MGAs.ChipLinearSize > 8192 )
		{
			MGAs.ChipLinearSize = 2048; /* nice safe size */
			ErrorF("(!!) %s: reset VideoRAM to 2 MB for safety!\n",
				vga256InfoRec.name);
		}
	}

	vga256InfoRec.videoRam =  MGAs.ChipLinearSize;
	MGAs.ChipLinearSize *= 1024;

	/*
	 * fill MGAdac struct
	 * Warning: currently, it should be after RAM counting
	 */
	switch (Chipset)
	{
	case PCI_CHIP_MGA2064:
	case PCI_CHIP_MGA2164:
	case PCI_CHIP_MGA2164_AGP:
		[self MGA3026RamdacInit];
		break;
	case PCI_CHIP_MGA1064:
	case PCI_CHIP_MGAG100:
	case PCI_CHIP_MGAG200:
	case PCI_CHIP_MGAG400:
	case PCI_CHIP_MGAG100_PCI:
	case PCI_CHIP_MGAG200_PCI:
		[self MGAG200RamdacInit];
		break;
	}

	/*
	 * If the user has specified ramdac speed in the XF86Config
	 * file, we respect that setting.
	 */
	if( vga256InfoRec.dacSpeeds[0] )
		vga256InfoRec.maxClock = vga256InfoRec.dacSpeeds[0];
	else
		vga256InfoRec.maxClock = MGAdac.maxPixelClock;

	/*
	 * Last we fill in the remaining data structures. 
	 */
	vga256InfoRec.bankedMono = FALSE;
	
#ifdef XFreeXDGA
    	vga256InfoRec.directMode = XF86DGADirectPresent;
#endif
 
	OFLG_SET(OPTION_NOACCEL, &MGAs.ChipOptionFlags);
	OFLG_SET(OPTION_SYNC_ON_GREEN, &MGAs.ChipOptionFlags);
	OFLG_SET(OPTION_DAC_8_BIT, &MGAs.ChipOptionFlags);
	OFLG_SET(OPTION_SW_CURSOR, &MGAs.ChipOptionFlags);
	OFLG_SET(OPTION_HW_CURSOR, &MGAs.ChipOptionFlags);
	OFLG_SET(OPTION_PCI_RETRY, &MGAs.ChipOptionFlags);
	OFLG_SET(OPTION_MGA_24BPP_FIX, &MGAs.ChipOptionFlags);
	OFLG_SET(OPTION_MGA_SDRAM, &MGAs.ChipOptionFlags);

	OFLG_SET(CLOCK_OPTION_PROGRAMABLE, &vga256InfoRec.clockOptions);
	OFLG_SET(OPTION_DAC_8_BIT, &vga256InfoRec.options);

	if([self booleanForStringKey:MGA_sync_on_green withDefault:NO]
		== YES)
		OFLG_SET(OPTION_SYNC_ON_GREEN, &vga256InfoRec.options);

	/* Moved width checking because virtualX isn't set until after
	   the probing.  Instead, make use of the newly added
	   PitchAdjust hook. */

//	vgaSetPitchAdjustHook(MGAPitchAdjust);

//	vgaSetLinearOffsetHook(MGALinearOffset);

//	[self TestAndSetRounding:0];

	/* Set the bpp shift value */
	MGABppShifts[0] = 0;
	MGABppShifts[1] = 1;
	MGABppShifts[2] = 0;
	MGABppShifts[3] = 2;

	save = pciReadLong(MGAPciTag, PCI_OPTION_REG);

	if (MGA_IS_GCLASS(Chipset)) {
	    /* for the Gx00 chipsets we want to know whether the card uses
	       SDRAM or SGRAM */
	    if ( (save & (0x01 << 14)) == 0 ) {
#ifdef DEBUG
		ErrorF("%s %s: detected an SDRAM card\n",
		    XCONFIG_PROBED, vga256InfoRec.name);
#endif
		MGAHasSDRAM = TRUE;
	    }
	    else {
#ifdef DEBUG
		ErrorF("%s %s: detected an SGRAM card\n",
		    XCONFIG_PROBED, vga256InfoRec.name);
#endif
		MGAHasSDRAM = FALSE;
	    }
	}

#ifdef DPMSExtension
	vga256InfoRec.DPMSSet = MGADisplayPowerManagementSet;
#endif

	return(TRUE);
}

/*
 * TestAndSetRounding
 *
 * used in MGAPitchAdjust (see there) - ansi
 */

- (int)TestAndSetRounding:(int)pitch
{
	switch (vgaBitsPerPixel)
	{
	case 8:
		if (MGAinterleave) {
			MGAs.ChipRounding = 128;
		} else {
			MGAs.ChipRounding = 64;
		}
		break;
	case 16:
		if (MGAinterleave) {
			MGAs.ChipRounding = 64;
		} else {
			MGAs.ChipRounding = 32;
		}
		break;
	case 32:
		if (MGAinterleave) {
			MGAs.ChipRounding = 32;
		} else {
			MGAs.ChipRounding = 16;
		}
		break;
	case 24:
		if (MGAinterleave) {
			MGAs.ChipRounding = 128;
		} else {
			MGAs.ChipRounding = 64;
		}
		break;
	}

/*	if (pitch % MGAs.ChipRounding)
		pitch = pitch + MGAs.ChipRounding - (pitch % MGAs.ChipRounding);
*/
#ifdef DEBUG
	ErrorF("pitch= %x MGAs.ChipRounding= %x MGAinterleave= %x MGABppShft= %x\n",pitch ,MGAs.ChipRounding,MGAinterleave,MGABppShft);
#endif
	return pitch;
}

#if 0
/*
 * MGAPitchAdjust --
 *
 * This function adjusts the display width (pitch) once the virtual
 * width is known.  It returns the display width.
 */
static int
MGAPitchAdjust()
{
	int *pWidth, pitch = 0;
	int accel;
	
	/* ajv - See MGA2064 p4-59 for millennium supported pitches
         * See MGA1064 p4-68 for mystique pitch 
	 * XXX see if MGA2164 has same width types as MGA1064
         */

	int width[] = { 640, 768, 800, 960, 1024, 1152, 1280,
			1600, 1920, 2048, 0 };
	int width2[] = { 512, 640, 768, 800, 832, 960, 1024, 1152, 1280,
			1600, 1664, 1920, 2048, 0 };

	switch (Chipset)
	{
		case PCI_CHIP_MGA1064:
		case PCI_CHIP_MGAG100:
		case PCI_CHIP_MGAG200:
		case PCI_CHIP_MGAG400:
		case PCI_CHIP_MGAG100_PCI:
		case PCI_CHIP_MGAG200_PCI:
			pWidth = &width2[0];
			break;

		case PCI_CHIP_MGA2064:
		case PCI_CHIP_MGA2164:	/* XXX - may need to be with 1064 */
	        case PCI_CHIP_MGA2164_AGP:
		default:
			pWidth = &width[0];
			break;
	}

	if (!OFLG_ISSET(OPTION_NOACCEL, &vga256InfoRec.options))
	{
		accel = TRUE;
		
		while ( *pWidth )
		{
			if (*pWidth >= vga256InfoRec.virtualX && 
			    TestAndSetRounding(*pWidth) == *pWidth)
			{
				pitch = *pWidth;
				break;
			}
			pWidth++;
		}
	}
	else
	{
		accel = FALSE;
		pitch = TestAndSetRounding(vga256InfoRec.virtualX);
	}


	if (!pitch)
	{
		if(accel) 
		{
			FatalError("MGA: Can't find pitch, try using option"
				   "\"no_accel\"\n");
		}
		else
		{
			FatalError("MGA: Can't find pitch (Oups, should not"
				   "happen!)\n");
		}
	}

	if (pitch != vga256InfoRec.virtualX)
	{
		if (accel)
		{
			ErrorF("%s %s: Display pitch set to %d (a multiple "
			       "of %d & possible for acceleration)\n",
			       XCONFIG_PROBED, vga256InfoRec.name,
			       pitch, MGAs.ChipRounding);
		}
		else
		{
			ErrorF("%s %s: Display pitch set to %d (a multiple "
			       "of %d)\n",
			       XCONFIG_PROBED, vga256InfoRec.name,
			       pitch, MGAs.ChipRounding);
		}
	}
#ifdef DEBUG
	else
	{
		ErrorF("%s %s: pitch is %d, virtual x is %d, display width is %d\n", XCONFIG_PROBED, vga256InfoRec.name,
		       pitch, vga256InfoRec.virtualX, vga256InfoRec.displayWidth);
	}
#endif

	return pitch;
}
#endif


/*
 * MGALinearOffset --
 *
 * This function computes the byte offset into the linear frame buffer where
 * the frame buffer data should actually begin.  According to DDK misc.c line
 * 1023, if more than 4MB is to be displayed, YDSTORG must be set appropriately
 * to align memory bank switching, and this requires a corresponding offset
 * on linear frame buffer access.
 */
- (int)MGALinearOffset
{
	int BytesPerPixel = vgaBitsPerPixel / 8;
	int offset, offset_modulo, ydstorg_modulo;

	MGAydstorg = 0;
	if (vga256InfoRec.virtualX * vga256InfoRec.virtualY * BytesPerPixel
		<= 4*1024*1024)
	    return 0;

	if (MGA_IS_G400(Chipset))
		return 0;

	offset = (4*1024*1024) % (vga256InfoRec.displayWidth * BytesPerPixel);
	offset_modulo = 4;
	ydstorg_modulo = 64;
	if (vgaBitsPerPixel == 24)
	    offset_modulo *= 3;
	if (MGAinterleave)
	{
	    offset_modulo <<= 1;
	    ydstorg_modulo <<= 1;
	}
	MGAydstorg = offset / BytesPerPixel;

	/*
	 * When this was unconditional, it caused a line of horizontal garbage
	 * at the middle right of the screen at the 4Meg boundary in 32bpp
	 * (and presumably any other modes that use more than 4M). But it's
	 * essential for 24bpp (it may not matter either way for 8bpp & 16bpp,
	 * I'm not sure; I didn't notice problems when I checked with and
	 * without.)
	 * DRM Doug Merritt 12/97, submitted to XFree86 6/98 (oops)
	 */
	if (BytesPerPixel < 4) {
	    while ((offset % offset_modulo) != 0 ||
		   (MGAydstorg % ydstorg_modulo) != 0) {
		offset++;
		MGAydstorg = offset / BytesPerPixel;
	    }
	}

	return MGAydstorg * BytesPerPixel;
}


/*
 * MGARestore --
 *
 * This function restores a video mode.	 It basically writes out all of
 * the registers that have previously been saved in the vgaMGARec data 
 * structure.
 */
- (void)MGARestore:(vgaHWPtr)restore
{
	[self vgaProtect:TRUE];
	
	switch (Chipset)
	{
		case PCI_CHIP_MGA2085:
		case PCI_CHIP_MGA2064:
		case PCI_CHIP_MGA2164:
		case PCI_CHIP_MGA2164_AGP:
			[self MGA3026Restore:restore];
			break;
		case PCI_CHIP_MGA1064:
		case PCI_CHIP_MGAG400:
		case PCI_CHIP_MGAG200:
		case PCI_CHIP_MGAG200_PCI:
		case PCI_CHIP_MGAG100:
		case PCI_CHIP_MGAG100_PCI:
			[self MGAG200Restore:restore];
			break;
	}

	[self MGAStormSync];
	[self MGAStormEngineInit];

	[self vgaProtect:FALSE];
}


/*
 * MGASave --
 *
 * This function saves the video state.	 It reads all of the SVGA registers
 * into the vgaMGARec data structure.
 */
- (void)MGASave:(vgaHWPtr)save
{
	switch (Chipset)
	{
		case PCI_CHIP_MGA2085:
		case PCI_CHIP_MGA2064:
		case PCI_CHIP_MGA2164:
		case PCI_CHIP_MGA2164_AGP:
			[self MGA3026Save:save];
			break;
		case PCI_CHIP_MGA1064:
		case PCI_CHIP_MGAG400:
		case PCI_CHIP_MGAG200:
		case PCI_CHIP_MGAG200_PCI:
		case PCI_CHIP_MGAG100:
		case PCI_CHIP_MGAG100_PCI:
			[self MGAG200Save:save];
			break;
	}
}


- (void)MGAStormSync
{
//    if(MGAIsClipped) { 
	/* we don't need to sync after a cpu->screen color expand.
		we merely need to reset the clipping box */
/*	WAITFIFO(1);
    	OUTREG(MGAREG_CXBNDRY, 0xFFFF0000);
	MGAIsClipped = FALSE;
    } else while(MGAISBUSY());*/

    /* flush cache before a read (mga-1064g 5.1.6) */
    OUTREG8(MGAREG_CRTC_INDEX, 0); 
}


- (void)MGAStormEngineInit
{
    CARD32 maccess = 0;
    BOOL MGAUsePCIRetry = FALSE;

    if(MGA_IS_G100(Chipset))
    	maccess = 1 << 14;	/* enable JEDEC */
    
    switch( vgaBitsPerPixel )
    {
    case 8:
        break;
    case 16:
	/* set 16 bpp, turn off dithering, turn on 5:5:5 pixels */
        maccess |= 1 + (1 << 30) + (1 << 31);
        break;
    case 24:
        maccess |= 3;
        break;
    case 32:
        maccess |= 2;
        break;
    }

    WAITFIFO(8);
    OUTREG(MGAREG_PITCH, vga256InfoRec.displayWidth);
    OUTREG(MGAREG_YDSTORG, MGAydstorg);
    OUTREG(MGAREG_MACCESS, maccess);
    if( !(MGA_IS_G100(Chipset) && MGAHasSDRAM) )
	    OUTREG(MGAREG_PLNWT, ~0);
    OUTREG(MGAREG_OPMODE, MGAOPM_DMA_BLIT);

    /* put clipping in a know state */
    OUTREG(MGAREG_CXBNDRY, 0xFFFF0000);	/* (maxX << 16) | minX */ 
    OUTREG(MGAREG_YTOP, 0x00000000);	/* minPixelPointer */ 
    OUTREG(MGAREG_YBOT, 0x007FFFFF);	/* maxPixelPointer */ 
}


/*
 * MGAEnterLeave --
 *
 * This function is called when the virtual terminal on which the server
 * is running is entered or left, as well as when the server starts up
 * and is shut down.	Its function is to obtain and relinquish I/O 
 * permissions for the SVGA device.	 This includes unlocking access to
 * any registers that may be protected on the chipset, and locking those
 * registers again on exit.
 */
- (void)MGAEnterLeave:(BOOL)enter
{
//	unsigned char misc_ctrl;
	unsigned char temp;

	if (enter)
	{
//		xf86EnableIOPorts(vga256InfoRec.scrnIndex);
		if (MGAMMIOBase)
		{
//			xf86MapDisplay(vga256InfoRec.scrnIndex,
//					MMIO_REGION);
			[self MGAStormSync];
		}

//		IOLog("MiscOutReg = %02X\n", inb(0x3CC));
		vgaIOBase = (inb(0x3CC) & 0x01) ? 0x3D0 : 0x3B0;

		/* Unprotect CRTC[0-7] */
		outb(vgaIOBase + 4, 0x11); temp = inb(vgaIOBase + 5);
		outb(vgaIOBase + 5, temp & 0x7F);
	}
	else
	{
		/* Protect CRTC[0-7] */
		outb(vgaIOBase + 4, 0x11); temp = inb(vgaIOBase + 5);
		outb(vgaIOBase + 5, (temp & 0x7F) | 0x80);
		
		if (MGAMMIOBase)
		{
			[self MGAStormSync];
/*			xf86UnMapDisplay(vga256InfoRec.scrnIndex,
					MMIO_REGION);
			if (xf86Exiting && xf86Info.caughtSignal)
			{
				/*
				 * Without this a core dump can cause a
				 * lockup on some platforms.
				 *//*
				xf86UnMapVidMem(vga256InfoRec.scrnIndex,
						MMIO_REGION, MGAMMIOBase,
						0x4000);
				MGAMMIOBase = 0;
			}*/
		}
		
//		xf86DisableIOPorts(vga256InfoRec.scrnIndex);
	}
}


/*
 * MGAAdjust --
 *
 * This function is used to initialize the SVGA Start Address - the first
 * displayed location in the video memory.
 */
- (void)MGAAdjust:(int)x y:(int)y
{
	int Base;
	int tmp;
	CARD32 count;

	Base = (y * vga256InfoRec.displayWidth + x + MGAydstorg) >>
		(3 - MGABppShifts[(vgaBitsPerPixel >> 3) - 1]);

	if (vgaBitsPerPixel == 24) {
	    if (MGA_IS_G400(Chipset))
		Base &= ~1;
	    Base *= 3;
	}

	/* find start of retrace */
	while (INREG8(0x1FDA) & 0x08);
	while (!(INREG8(0x1FDA) & 0x08)); 
	/* wait until we're past the start (fixseg.c in the DDK) */
	count = INREG(MGAREG_VCOUNT) + 2;
	while(INREG(MGAREG_VCOUNT) < count);


	OUTREG16(MGAREG_CRTC_INDEX, (Base & 0x00FF00) | 0x0C);
	OUTREG16(MGAREG_CRTC_INDEX, ((Base & 0x0000FF) << 8) | 0x0D);
	OUTREG8(MGAREG_CRTCEXT_INDEX, 0x00);
	tmp = INREG8(MGAREG_CRTCEXT_DATA);
	OUTREG8(MGAREG_CRTCEXT_DATA, (tmp & 0xF0) | ((Base & 0x0F0000) >> 16));
}


#if 0
/*
 * MGAValidMode -- 
 *
 * Checks if a mode is suitable for the selected chipset.
 */
static Bool
MGAValidMode(mode,verbose,flag)
DisplayModePtr mode;
Bool verbose;
int flag;
{
	int lace = 1 + ((mode->Flags & V_INTERLACE) != 0);
	
	if ((mode->CrtcHDisplay <= 2048) &&
	    (mode->CrtcHSyncStart <= 4096) && 
	    (mode->CrtcHSyncEnd <= 4096) && 
	    (mode->CrtcHTotal <= 4096) &&
	    (mode->CrtcVDisplay <= 2048 * lace) &&
	    (mode->CrtcVSyncStart <= 4096 * lace) &&
	    (mode->CrtcVSyncEnd <= 4096 * lace) &&
	    (mode->CrtcVTotal <= 4096 * lace))
	{
		return(MODE_OK);
	}
	else
	{
		return(MODE_BAD);
	}
}
#endif

/*
 * MGADisplayPowerManagementSet --
 *
 * Sets VESA Display Power Management Signaling (DPMS) Mode.
 */
#ifdef DPMSExtension
static void MGADisplayPowerManagementSet(PowerManagementMode)
int PowerManagementMode;
{
	unsigned char seq1, crtcext1;
	if (!xf86VTSema) return;
	switch (PowerManagementMode)
	{
	case DPMSModeOn:
	    /* Screen: On; HSync: On, VSync: On */
	    seq1 = 0x00;
	    crtcext1 = 0x00;
	    break;
	case DPMSModeStandby:
	    /* Screen: Off; HSync: Off, VSync: On */
	    seq1 = 0x20;
	    crtcext1 = 0x10;
	    break;
	case DPMSModeSuspend:
	    /* Screen: Off; HSync: On, VSync: Off */
	    seq1 = 0x20;
	    crtcext1 = 0x20;
	    break;
	case DPMSModeOff:
	    /* Screen: Off; HSync: Off, VSync: Off */
	    seq1 = 0x20;
	    crtcext1 = 0x30;
	    break;
	}
	BREGO (0x3C4, 0x01);	/* Select SEQ1 */
	seq1 |= BREG (0x3C5) & ~0x20;
	BREGO (0x3C5, seq1);
	BREGO (0x3DE, 0x01);	/* Select CRTCEXT1 */
	crtcext1 |= BREG (0x3DF) & ~0x30;
	BREGO (0x3DF, crtcext1);
}
#endif

@end
