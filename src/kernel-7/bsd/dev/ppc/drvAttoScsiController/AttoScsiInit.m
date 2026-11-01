/*
 * Copyright (c) 1999 Apple Computer, Inc. All rights reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 * 
 * Portions Copyright (c) 1999 Apple Computer, Inc.  All Rights
 * Reserved.  This file contains Original Code and/or Modifications of
 * Original Code as defined in and that are subject to the Apple Public
 * Source License Version 1.1 (the "License").  You may not use this file
 * except in compliance with the License.  Please obtain a copy of the
 * License at http://www.apple.com/publicsource and read it before using
 * this file.
 * 
 * The Original Code and all software distributed under the License are
 * distributed on an "AS IS" basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE OR NON- INFRINGEMENT.  Please see the
 * License for the specific language governing rights and limitations
 * under the License.
 * 
 * @APPLE_LICENSE_HEADER_END@
 */

/* AttoScsiInit.m created by russb2 on Sat 30-May-1998 */

/*-----------------------------------------------------------------------------*
 * This module contains initialization routines for the driver.
 *
 * Driver initialization consists of:
 * 
 * - Doing PCI bus initialization for the script engine PCI device.
 * - Setting up shared communication areas in system memory between the script
 *   and the driver.
 * - Copying the script program into the script engine on-board ram, applying 
 *   script relocation fixups as required.
 * - Setting the initial register values for the script engine.
 * - Setting up driver related storage and interfacing with driverKit.
 *
 *-----------------------------------------------------------------------------*/

/*
 * This define causes AttoScsiScript.h to include the script instructions and
 * relocation tables. Normally without this define we only will get #define
 * values for interfacing with the script.
 */
#define INCL_SCRIPT_TEXT

#import "AttoScsiController.h"
#import <kern/thread_call.h>
#import <machdep/ppc/interrupts.h>

/*-----------------------------------------------------------------------------*
 * This structure contains most of the inital register settings for
 * the script engine. See AttoScsiRegs.h for the actual initialization
 * values.
 *
 *-----------------------------------------------------------------------------*/
typedef struct ChipInitRegs
{
    u_int32_t		regNum;
    u_int32_t		regSize;
    u_int32_t		regValue;

} ChipInitRegs;

static ChipInitRegs 	AttoScsiInitRegs[] =
{
	{ SCNTL0,	SCNTL0_SIZE,	SCNTL0_INIT 	},
	{ SCNTL1,	SCNTL1_SIZE,    SCNTL1_INIT	},
        { SCNTL2,	SCNTL2_SIZE,	SCNTL2_INIT	},
        { SCNTL3,     	SCNTL3_SIZE,	SCNTL3_INIT_875	},
        { SXFER,	SXFER_SIZE, 	SXFER_INIT	},
        { SDID,		SDID_SIZE,	SDID_INIT	},
        { GPREG,	GPREG_SIZE,	GPREG_INIT	},
        { SFBR,		SFBR_SIZE,	SFBR_INIT	},
        { SOCL, 	SOCL_SIZE,	SOCL_INIT	},
        { DSA,		DSA_SIZE,	DSA_INIT	},
        { ISTAT,	ISTAT_SIZE,	ISTAT_INIT	},
        { TEMP,		TEMP_SIZE,	TEMP_INIT	},
        { CTEST0,	CTEST0_SIZE,	CTEST0_INIT	},
        { CTEST3,	CTEST3_SIZE,	CTEST3_INIT_A	},
        { CTEST4,	CTEST4_SIZE,	CTEST4_INIT_ATTO },
        { CTEST5,	CTEST5_SIZE,	CTEST5_INIT_ATTO },
        { DBC,		DBC_SIZE,	DBC_INIT	},
        { DCMD,		DCMD_SIZE,	DCMD_INIT	},
        { DNAD,		DNAD_SIZE,	DNAD_INIT	},
	{ DSPS,		DSPS_SIZE,	DSPS_INIT	},
	{ SCRATCHA,	SCRATCHA_SIZE,	SCRATCHA_INIT	},
        { DMODE,	DMODE_SIZE,	DMODE_INIT_A	},
        { DIEN,		DIEN_SIZE,	0		},
        { DWT,		DWT_SIZE,	DWT_INIT	},
        { DCNTL,	DCNTL_SIZE,	DCNTL_INIT_A 	},
        { SIEN0,	SIEN0_SIZE,	0		},
        { SIEN1,	SIEN1_SIZE,	0		},
        { SLPAR,	SLPAR_SIZE,	SLPAR_INIT	},
        { MACNTL,	MACNTL_SIZE,	MACNTL_INIT	},
        { GPCNTL,	GPCNTL_SIZE,	GPCNTL_INIT	},
        { STIME0,	STIME0_SIZE,	STIME0_INIT	},
        { STIME1,	STIME1_SIZE,	STIME1_INIT	},
        { RESPID0,	RESPID0_SIZE,   RESPID0_INIT	},
        { RESPID1,    	RESPID1_SIZE,   RESPID1_INIT	},
        { STEST2,	STEST2_SIZE,	STEST2_INIT	},
        { STEST3,	STEST3_SIZE,	STEST3_INIT	},
        { SODL,		SODL_SIZE,	SODL_INIT	},
        { SCRATCHB,	SCRATCHB_SIZE,	SCRATCHB_INIT	}
};


/*
 * Controllers sharing an interrupt line, indexed by the line's interrupt
 * number. The first controller registered on a line installs the handler.
 */
typedef struct IntQEntry
{
    AttoScsiController		*controller;
    queue_chain_t		link;
} IntQEntry;

static queue_head_t		interruptQ[64];

/*
 * Runs at thread level: poll every controller on the interrupting line
 * until none has an interrupt pending.
 */
static void AttoScsiServiceInterrupts( AttoScsiController *controller )
{
    queue_head_t		*q = &interruptQ[controller->interrupt];
    IntQEntry			*entry;
    int				serviced;

    do
    {
        serviced = 0;
        queue_iterate( q, entry, IntQEntry *, link )
        {
            if ( [entry->controller checkForPendingInterrupt] )
            {
                serviced++;
                [entry->controller interruptOccurred];
            }
        }
    }
    while ( serviced );
}

static void AttoScsiInterruptHandler( int irq, void *ssp, void *arg )
{
    thread_call_func( (thread_call_func_t) AttoScsiServiceInterrupts, (thread_call_spec_t) arg, TRUE );
}

@implementation AttoScsiController(Init)

+ initialize
{
    int		i;

    for ( i = 0; i < 64; i++ )
    {
        queue_init( &interruptQ[i] );
    }
    return self;
}

- (void) registerHandlerForIRQ:(int)irq
{
    IntQEntry			*entry;

    interrupt = irq;

    if ( queue_empty( &interruptQ[interrupt] ) )
    {
        pmac_register_int( pmac_int_to_number( interrupt ), SPLBIO, AttoScsiInterruptHandler, self );
    }

    queue_iterate( &interruptQ[interrupt], entry, IntQEntry *, link )
    {
        if ( entry->controller == self )
        {
            return;
        }
    }

    entry = (IntQEntry *) IOMalloc( sizeof(IntQEntry) );
    entry->controller = self;
    queue_enter( &interruptQ[interrupt], entry, IntQEntry *, link );
}

/*-----------------------------------------------------------------------------*
 *  Probe, configure board and init new instance.
 *
 *-----------------------------------------------------------------------------*/
+ (BOOL)probe:(IOPCIDevice *)deviceDescription
{
    AttoScsiController	*sym8xx = [self alloc];

//  call_kdp();	
    return ([sym8xx initFromDeviceDescription: deviceDescription] ? YES : NO);		
}

/*-----------------------------------------------------------------------------*
 *
 *
 *-----------------------------------------------------------------------------*/
- initFromDeviceDescription:(IOPCIDevice *) deviceDescription
{

    if ( [super initFromDeviceDescription:deviceDescription] == nil)
    {
      goto abort;
    }

    if ( [self AttoScsiInit: deviceDescription] == NO )
    {
      goto abort;
    }

    /*
     *  
     */
    interruptPortKern = IOConvertPort(	[self interruptPort],
                                        IO_KernelIOTask,
                                        IO_Kernel);

    AttoScsiTimerReq( self );

    [self resetSCSIBus];

    /*
     *  Now that everything has succeeded, enable interrupts, and go,
     */
    [self registerDevice];	
    return self;

abort:
    [self free];
    return NULL;
}

/*-----------------------------------------------------------------------------*
 * Script Initialization
 *
 *-----------------------------------------------------------------------------*/
- (BOOL) AttoScsiInit:(IOPCIDevice *)deviceDescription
{
    /*
     * Perform PCI related initialization
     */
    if ( [self AttoScsiInitPCI: (IOPCIDevice *)deviceDescription] == NO )
    { 
        return NO;
    }

    /*
     * Allocate/initialize driver resources
     */
    if ( [self AttoScsiInitVars] == NO )
    {
        return NO;
    }

    /*
     * Initialize the script engine registers
     */
    if ( [self AttoScsiInitChip] == NO )
    {
        return NO;
    }

    /* 
     * Apply fixups to script and copy script to script engine's on-board ram
     */
    if ( [self AttoScsiInitScript] == NO )
    {
        return NO;
    }

    [self registerHandlerForIRQ: [deviceDescription interrupt]];

    /*
     * Start script execution
     */
    AttoScsiWriteRegs( chipBaseAddr, DSP, DSP_SIZE, (u_int32_t) &chipRamAddrPhys[Ent_select_phase] );

    return YES;
}

/*-----------------------------------------------------------------------------*
 * Script engine PCI initialization
 *
 * This routine determines the chip version/revision, enables the chip address
 * ranges and allocates a virtual mapping to the script engine's registers and
 * on-board ram.
 *-----------------------------------------------------------------------------*/
- (BOOL) AttoScsiInitPCI: (IOPCIDevice *)deviceDescription
{
    IORange		*ioRange;
    unsigned long	pciReg0, pciReg8;
    u_int32_t		pciRamSlot=-1, pciRegSlot=-1;
    u_int32_t		n;

    /*
     * Determine the number of memory ranges for the PCI device.
     * 
     * The hardware implementation may or may not have a ROM present
     * accounting for the difference in the number of ranges.
     */
    n = [deviceDescription numMemoryRanges];
    if ( !( n == 3  ||  n == 4 )  )
    {
      return NO;
    }

    ioRange = [deviceDescription memoryRangeList];

    [deviceDescription configReadLong:0x00 value:&pciReg0];
    [deviceDescription configReadLong:0x08 value:&pciReg8];

    DeviceID = pciReg0 >> 16;

    switch ( DeviceID )
    {
      case 0x0f:
        chipType      = 0x875;
        MaxSyncOffset = 16;
        MinSyncPeriod = 12;
        Scntl3Reset   = SCNTL3_INIT_875_SLOW;
        break;

      case 0x0c:
        chipType      = 0x895;
        MaxSyncOffset = 31;
        MinSyncPeriod = 10;
        Scntl3Reset   = SCNTL3_INIT_895_SLOW;
        Flags        |= kAttoFlagQuadClock;
        break;

      case 0x0b:
        chipType      = 0x896;
        MaxSyncOffset = 31;
        MinSyncPeriod = 10;
        Scntl3Reset   = SCNTL3_INIT_895_SLOW;
        Flags        |= kAttoFlagQuadClock | kAttoFlag896;
        break;

      default:
        chipType = 0x825;
        return NO;
    }

    /*
     * Divergence from 5.6: it never sets MinSEPeriod, so on a single-ended
     * bus AttoScsiInitChip offered an SDTR period of 0 and GetPeriodEntry
     * picked Ultra2 timing. Single-ended buses top out at Ultra (12).
     */
    MinSEPeriod = 12;

    chipClockRate = CLK_40MHz;

    /*
     * BUS MASTER, MEM I/O Space, MEM WR & INV
     */
    [deviceDescription configWriteLong:0x04 value:0x16];

    /*
     *  set Latency to Max , cache 32
     */
    [deviceDescription configWriteLong:0x0C value:0x2008];

    switch ( n )
    {
      case 3:
        pciRegSlot = 2;
        pciRamSlot = 1;
        break;
      case 4:
        pciRegSlot = 3;
        pciRamSlot = 2;
    }

    /*
     * get chip register block mapped into pci memory
     */
    ioRange[pciRegSlot].size = round_page(ioRange[pciRegSlot].size);
    [deviceDescription setMemoryRangeList: ioRange num: n];
    ioRange = [deviceDescription memoryRangeList];

    chipBaseAddrPhys 	= (u_int8_t *)ioRange[pciRegSlot].start;
    [self mapMemoryRange: pciRegSlot to:(vm_address_t *)&chipBaseAddr findSpace:YES cache:IO_CacheOff];

    chipRamAddrPhys 	= (u_int8_t *)ioRange[pciRamSlot].start;
    [self mapMemoryRange: pciRamSlot to:(vm_address_t *)&chipRamAddr findSpace:YES cache:IO_CacheOff];

    /*
     * Setup pointers to the script engine's registers and on-board ram for
     * inspection by the kernel mini-mon utility.
     */
#if 0
    if ( !gRegs875 )
    {
        gRegs875 	= (u_int32_t)chipBaseAddr; 
        gRegs875Phys	= (u_int32_t)chipBaseAddrPhys;
        gRam875  	= (u_int32_t)chipRamAddr;
        gRam875Phys 	= (u_int32_t)chipRamAddrPhys;
    }
#endif

    return YES;
}


/*-----------------------------------------------------------------------------*
 * This routine allocates/initializes shared memory for communication between 
 * the script and the driver. In addition other driver resources semaphores, 
 * queues are initialized here.
 *
 *-----------------------------------------------------------------------------*/
- (BOOL) AttoScsiInitVars
{
    kern_return_t		kr;
    u_int32_t			i;

    kr = kmem_alloc_wired(IOVmTaskSelf(), (vm_offset_t *) &adapter, page_size );
    if ( kr != KERN_SUCCESS )
    {
        return NO;
    }
    bzero( adapter, page_size );

    /*
     * We keep two copies of the Nexus pointer array. One contains physical addresses and
     * is located in the script/driver shared storage. The other copy holds the corresponding
     * virtual addresses to the active Nexus structures and is located in the drivers instance
     * data.
     * Both tables can be accessed through indirect pointers in the script/driver communication
     * area. This is the preferred method to access these arrays.
     */ 
    adapter->nexusPtrsVirt = (Nexus **)nexusArrayVirt;
    adapter->nexusPtrsPhys = (Nexus **)adapter->nexusArrayPhys;

    for (i=0; i < MAX_SCSI_TAG; i ++ )
    {
        adapter->nexusPtrsVirt[i] = (Nexus *) -1;
        adapter->nexusPtrsPhys[i] = (Nexus *) -1;
    }

    IOPhysicalFromVirtual((vm_task_t)IOVmTaskSelf(), (vm_offset_t)adapter, (vm_offset_t *)&adapterPhys );
 
    /*
     * The script/driver communication area also contains a 16-entry table clock
     * settings for each target.
     */ 
    for (i=0; i < MAX_SCSI_TARGETS; i++ )
    {
        targets[i].targetTagSem = [[NXLock alloc] init];
        targets[i].flags        = kTFXferSyncAllowed | kTFXferWide16Allowed | kTFCmdQueueAllowed;

        adapter->targetClocks[i].scntl3Reg = (Flags & kAttoFlagQuadClock) ? SCNTL3_INIT_895_SLOW : SCNTL3_INIT_875_SLOW;
    }

    /*
     * Allocate/init various driver semaphores
     */
    cmdQTagSem      = [[NXLock alloc] init];
    abortBdrSem     = [[NXLock alloc] init];
    resetQuiesceSem = [[NXLock alloc] init];

    
    /*
     *  Initialize the IOThread command queue.
     */
    queue_init(&srbPendingQ);
    srbPendingQLock = [[NXLock alloc] init];

    /*
     * Initialize the SRB Pool   
     */
    queue_init(&srbPool);
    srbPoolLock = [[NXLock alloc] init];

    /*
     * Reserve our host-adapter ID so the driverKit SCSI classes do not probe it.  
     */
    for ( i = 0; i < MAX_SCSI_LUNS; i++ )
    {
        [ self reserveTarget: kHostAdapterSCSIId lun: i forOwner: self ];
    }

    /*
     * Start up the SRB Pool grow thread.
     */
    srbPoolGrowLock = [[NXConditionLock alloc] initWith: kSRBGrowPoolIdle];
    IOForkThread( (IOThreadFunc) AttoScsiGrowSRBPool, (void *)self );

    return YES;
}


/*-----------------------------------------------------------------------------*
 * This routine makes a temporary copy of the script program, applies script fixups,
 * initializes the script local data table at the top of the script image, and
 * copies the modified script image to the script engine's on-board ram.
 *
 *-----------------------------------------------------------------------------*/
- (BOOL) AttoScsiInitScript
{
    u_int32_t	 	i;
    u_int32_t		scriptPgm[sizeof(ABSC_SCRIPT)/sizeof(u_int32_t)];

    /*
     * Make a copy of the script
     */
    bcopy( ABSC_SCRIPT, scriptPgm, sizeof(scriptPgm) );
    bzero( scriptPgm, R_ld_size );

    /*
     * Apply fixups to the script copy
     */
    for ( i=0; i < sizeof(ARel_Patches)/sizeof(u_int32_t); i++ )
    {
        scriptPgm[ARel_Patches[i]] += (u_int32_t)chipRamAddrPhys;
    }
    for ( i=0; i < sizeof(ALABELPATCHES)/sizeof(u_int32_t); i++ )
    {
        scriptPgm[ALABELPATCHES[i]] += (u_int32_t)chipRamAddrPhys;
    }
 
    /*
     * Initialize the script working variables with pointers to the script/driver
     * communications area.
     */
    scriptPgm[R_ld_sched_mlbx_base_adr >> 2] 	= (u_int32_t)&adapterPhys->schedMailBox;
    scriptPgm[R_ld_nexus_array_base >> 2]    	= (u_int32_t)&adapterPhys->nexusArrayPhys;
    scriptPgm[R_ld_device_table_base_adr >> 2] 	= (u_int32_t)&adapterPhys->targetClocks;

    /*
     * Load the script image into the script engine's on-board ram.
     */
    [self AttoScsiLoadScript: scriptPgm count:sizeof(scriptPgm)/sizeof(u_int32_t)];

    return YES;
}


/*-----------------------------------------------------------------------------*
 * This routine transfers the script program image into the script engine's
 * on-board ram
 *
 *-----------------------------------------------------------------------------*/
- (void) AttoScsiLoadScript:(u_int32_t *)scriptPgm count:(u_int32_t)scriptWords
{
    u_int32_t			i;
    volatile u_int32_t		*ramPtr = (volatile u_int32_t *)chipRamAddr;

    for ( i = 0; i < scriptWords; i++ )
    {
        ramPtr[i] = EndianSwap32(scriptPgm[i]);
    }
}

/*-----------------------------------------------------------------------------*
 * This routine initializes the script engine's register block.
 *
 *-----------------------------------------------------------------------------*/
- (BOOL) AttoScsiInitChip
{
    u_int32_t			i;
    int				burstLen;
    u_int8_t			burstCode;
    u_int32_t			busMode;
    short			n;

    /*
     * Reset the script engine
     */
    AttoScsiWriteRegs( chipBaseAddr, ISTAT, ISTAT_SIZE, RST );
    IODelay( 25 );
    AttoScsiWriteRegs( chipBaseAddr, ISTAT, ISTAT_SIZE, ISTAT_INIT );
  
    /*
     * Load our canned register values into the script engine
     */
    for ( i = 0; i < sizeof(AttoScsiInitRegs)/sizeof(ChipInitRegs); i++ )
    {
        AttoScsiWriteRegs( chipBaseAddr, AttoScsiInitRegs[i].regNum, AttoScsiInitRegs[i].regSize, AttoScsiInitRegs[i].regValue );
        IODelay( 10 );
    }

    /*
     * GPIO3 reads low on a differential card.
     */
    AttoScsiWriteRegs( chipBaseAddr, GPCNTL, GPCNTL_SIZE, GPIO3 );
    if ( !(AttoScsiReadRegs( chipBaseAddr, GPREG, GPREG_SIZE ) & GPIO3) )
    {
        AttoScsiWriteRegs( chipBaseAddr, STEST2, STEST2_SIZE, DIF );
    }

    /*
     * Bring the 40Mhz SCLK up with the clock doubler (875) or quadrupler (895/896).
     */
    if ( chipClockRate == CLK_40MHz )
    {
        /* set clock doubler enabler bit */
        AttoScsiWriteRegs( chipBaseAddr, STEST1, STEST1_SIZE, STEST1_INIT | DBLEN);
        if ( Flags & kAttoFlagQuadClock )
        {
            /* wait for the quadrupler to lock */
            while ( !(AttoScsiReadRegs( chipBaseAddr, STEST4, STEST4_SIZE ) & LOCK) )
                ;
        }
        else
        {
            IODelay(30);  
        }
        /* halt scsi clock */
        AttoScsiWriteRegs( chipBaseAddr, STEST3, STEST3_SIZE, STEST3_INIT | HSC );
        IODelay(10);
        AttoScsiWriteRegs( chipBaseAddr, SCNTL3, SCNTL3_SIZE, Scntl3Reset);
        IODelay(10);
        /* set clock doubler select bit */
        AttoScsiWriteRegs( chipBaseAddr, STEST1, STEST1_SIZE, STEST1_INIT | DBLEN | DBLSEL);
        IODelay(10);
        /* clear hold on scsi clock */
        AttoScsiWriteRegs( chipBaseAddr, STEST3, STEST3_SIZE, STEST3_INIT);
    }

    AttoScsiWriteRegs( chipBaseAddr, DIEN,  DIEN_SIZE,  DIEN_INIT_ATTO );
    AttoScsiWriteRegs( chipBaseAddr, SIEN0, SIEN0_SIZE, SIEN0_ATTO );
    AttoScsiWriteRegs( chipBaseAddr, SIEN1, SIEN1_SIZE, SIEN1_ATTO );

    if ( !(AttoScsiReadRegs( chipBaseAddr, STEST2, STEST2_SIZE ) & DIF) )
    {
        AttoScsiClearRegBits( chipBaseAddr, GPCNTL, GPCNTL_SIZE, 0x1c );
    }
    AttoScsiWriteRegs( chipBaseAddr, GPREG, GPREG_SIZE, (AttoScsiReadRegs( chipBaseAddr, GPREG, GPREG_SIZE ) & 0xfc) | GPIO3 );

    /*
     * PCI burst length. This only ever sets BL2 and leaves BL1-0 clear,
     * so both chips burst 32 transfers.
     */
    burstLen = (Flags & kAttoFlag896) ? 32 : 64;
    if ( burstLen )
    {
        for ( burstCode = 0, burstLen /= 2; burstLen; burstLen /= 2 )
        {
            burstCode++;
        }
        if ( burstCode & 4 )
        {
            AttoScsiModRegBits( chipBaseAddr, CTEST5, CTEST5_SIZE, ~BL2, BL2 );
        }
        AttoScsiModRegBits( chipBaseAddr, DMODE, DMODE_SIZE, ~BL1_0, ERMP );
    }
    else
    {
        AttoScsiModRegBits( chipBaseAddr, CTEST4, CTEST4_SIZE, ~BDIS, BDIS );
    }

    /*
     * 895/896: find out whether the bus is LVD or single-ended. The bus
     * mode is sensed with the SCSI drivers in high impedance mode.
     */
    if ( Flags & kAttoFlagQuadClock )
    {
        AttoScsiModRegBits( chipBaseAddr, STEST2, STEST2_SIZE, 0xff, SZM );
        AttoScsiModRegBits( chipBaseAddr, SIEN1,  SIEN1_SIZE,  0xff, 0x10 );
        IODelay( 1000 );
        for ( n = 0; n < 100; n++ )
        {
            istatReg = AttoScsiReadRegs( chipBaseAddr, ISTAT, ISTAT_SIZE );
            if ( istatReg & (SIP | DIP) )
            {
                dstatReg = AttoScsiReadRegs( chipBaseAddr, DSTAT, DSTAT_SIZE );
                IODelay( 5 );
                sistReg  = AttoScsiReadRegs( chipBaseAddr, SIST, SIST_SIZE );
            }
        }

        busMode = AttoScsiReadRegs( chipBaseAddr, STEST4, STEST4_SIZE ) & SMODE;
        AttoScsiWriteRegs( chipBaseAddr, STEST0, STEST0_SIZE, busMode >> 2 );
        AttoScsiModRegBits( chipBaseAddr, STEST2, STEST2_SIZE, ~SZM, 0 );
        IODelay( 1000 );
        for ( n = 0; n < 100; n++ )
        {
            istatReg = AttoScsiReadRegs( chipBaseAddr, ISTAT, ISTAT_SIZE );
            if ( istatReg & (SIP | DIP) )
            {
                dstatReg = AttoScsiReadRegs( chipBaseAddr, DSTAT, DSTAT_SIZE );
                IODelay( 5 );
                sistReg  = AttoScsiReadRegs( chipBaseAddr, SIST, SIST_SIZE );
            }
        }

        if ( busMode == SMODE )
        {
            MinSyncPeriod = 10;
            /* Divergence from 5.6: it did Flags &= kAttoFlagLVD, dropping the quadrupler flag */
            Flags |= kAttoFlagLVD;
        }
        else
        {
            Flags &= ~kAttoFlagLVD;
            MinSyncPeriod = MinSEPeriod;
        }

        if ( Flags & kAttoFlag896 )
        {
            /* early 896 revisions */
            if ( (AttoScsiReadRegs( chipBaseAddr, CTEST3, CTEST3_SIZE ) & VERS) < 0x40 )
            {
                AttoScsiModRegBits( chipBaseAddr, CCNTL0, CCNTL0_SIZE, 0xff, 1 );
            }
        }
    }

    /*  
     * Set our host-adapter ID in the script engine's registers
     */
    initiatorID = kHostAdapterSCSIId;

    if ( initiatorID > 7 )
    {
        AttoScsiWriteRegs( chipBaseAddr, RESPID1, RESPID1_SIZE, 1 << (initiatorID-8));
    }
    else
    {
        AttoScsiWriteRegs( chipBaseAddr, RESPID0, RESPID0_SIZE, 1 << initiatorID);
    }

    AttoScsiWriteRegs( chipBaseAddr, SCID, SCID_SIZE, SCID_INIT | initiatorID );

    return YES;
}


@end
