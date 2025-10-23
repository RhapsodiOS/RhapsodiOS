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

/* 	Copyright (c) 1997 Apple Computer, Inc.  All rights reserved. 
 *
 * PowerSurgeMB.c
 *
 * 20-May-97   Simon Douglas
 *      Created.
 */

#include <mach/mach_types.h>
#include <machdep/ppc/proc_reg.h>
#include <machdep/ppc/powermac.h>
#import <driverkit/IODevice.h>
#include "busses.h"
#import <bsd/dev/ppc/drvPMU/pmu.h>
#import <bsd/dev/ppc/drvPMU/pmupriv.h>
#import <bsd/dev/ppc/drvPMU/pmumisc.h>


// seconds between 1904 (Mac) & 1970 (UNIX) - many.
#define JAN11970	0x7c25b080
// MacOS xpram var for local secs from GMT
#define MACTIMEZONE	0xec

#define printf kprintf

void MBCallback(id unused, UInt32 refnum, UInt32 length, UInt8* buffer);
void wait_for_callback(void);

thread_t  our_thread;
id ApplePMUId;		// loaded driver


IOReturn
cuda_time_of_day( unsigned int * secs, int set )
{
    unsigned int  newTime;

kprintf("cuda_time_of_day: ApplePMUId = %08x, secs = %08x, *secs = %08x, set = %08x\n",
	ApplePMUId, secs, *secs, set);

    if ( set == 0 ) {
      if ( ApplePMUId == NULL ) {
		*secs = JAN11970;
      } else {
		[ApplePMUId getRealTimeClock:(UInt8 *)&newTime :0 :0 :MBCallback];
		wait_for_callback();
	
		*secs = newTime;
kprintf("newTime =%x\n", newTime);
      }
    } else {
      if ( ApplePMUId != NULL ) {
		newTime = *secs;

		[ApplePMUId setRealTimeClock:(UInt8 *)&newTime :0 :0 :MBCallback];
		wait_for_callback();
      }
    }
    
    return 0;
}


void
cuda_restart(int powerOff)
{
    unsigned char commandBuffer[4] = {'M', 'A', 'T', 'T'};
    unsigned char inputBuffer[1];

    kprintf("cuda_restart\n");

    /* Sync NVRAM on Sawtooth before shutdown/restart */
    if (IsSawtooth()) {
      SyncCore99NVRAM();
    }

    if ( ApplePMUId == NULL ) {
      kprintf("cuda_restart, no PMU driver\n");
    } else {
      if( powerOff ) {
	[ApplePMUId sendMiscCommand:kPMUPmgrPWRoff :4 :commandBuffer :inputBuffer :0 :0 :MBCallback];
      } else {
	[ApplePMUId sendMiscCommand:kPMUresetCPU :0 :NULL :NULL :0 :0 :MBCallback];
      }
      wait_for_callback();
    }
}

void PowerSurgeSendIIC( unsigned char iicAddr, unsigned char iicReg, unsigned char iicData)
{
#if 0 //No adb_send() in adb.c any more
    adb_request_t   cmd;

    adb_init_request(&cmd);
    cmd.a_cmd.a_header[0] = ADB_PACKET_PSEUDO;
    cmd.a_cmd.a_header[1] = ADB_PSEUDOCMD_GET_SET_IIC;
    cmd.a_cmd.a_header[2] = iicAddr;
    cmd.a_cmd.a_header[3] = iicReg;
    cmd.a_cmd.a_header[4] = iicData;
    cmd.a_cmd.a_hcount = 5;
    adb_send(&cmd, TRUE);
#endif
    UInt8       buffer[5] = {   1,
                    0x22, 	//ADB_PSEUDOCMD_GET_SET_IIC in adb.h 
                    iicAddr, 
                    iicReg,
                    iicData};

    if ( ApplePMUId != NULL ) {       //A.W. combined from Titan C
        // old, Simon says is buggy [ApplePMUId CudaMisc:buffer:5:NULL:0:NULL];
        [ApplePMUId CudaMisc:buffer:5:(UInt32)current_thread() : 0: MBCallback];

		wait_for_callback();
	}

}

// Can't be used anymore...
#if 0
enum {
    kXPRAMNVPartition		= 0x1300,
    kNameRegistryNVPartition	= 0x1400,
    kOpenFirmwareNVPartition	= 0x1800,
};
#endif


static long Core99NVRAMInited;
static char Core99NVRAM[0x2000];
static char Core99NVRAMBackup[0x2000];  /* For tracking changes */
static void *Core99NVRAMPhysAddr;       /* Physical NVRAM base address */
static void *Core99PrimaryBank;         /* Current primary bank pointer */
static void *Core99BackupBank;          /* Backup bank pointer */
static unsigned long Core99GenCount;    /* Current generation counter */

/* Calculate header checksum (first 16 bytes, skip byte 1) */
static unsigned char CalcHeaderChecksum(unsigned char *data)
{
  unsigned char sum = 0, oldsum;
  int i;

  for (i = 0; i < 0x10; i++) {
    if (i != 1) {
      oldsum = sum;
      sum += data[i];
      if (sum < oldsum) sum++;  /* Handle carry */
    }
  }
  return sum;
}

/* Calculate Adler-32 style data checksum */
static unsigned long CalcDataChecksum(unsigned char *data, int length)
{
  unsigned long a = 1, b = 0;
  int i;

  for (i = 0; i < length; i++) {
    a = a + data[i];
    b = b + a;
  }
  return ((b % 0xFFF1) << 16) | (a % 0xFFF1);
}

/* Read generation counter from NVRAM bank header with validation */
static unsigned long ReadGenCount(void *bankAddr)
{
  unsigned char *bank = (unsigned char *)bankAddr;
  unsigned char headerChecksum, expectedHeader;
  unsigned long dataChecksum, expectedData;

  /* Check signature byte */
  if (bank[0] != 'Z') {
    return 0;  /* Invalid bank */
  }

  /* Verify header checksum */
  expectedHeader = CalcHeaderChecksum(bank);
  headerChecksum = bank[1];
  if (headerChecksum != expectedHeader) {
    kprintf("ReadGenCount: header checksum mismatch\n");
    return 0;  /* Corrupted header */
  }

  /* Verify data checksum */
  expectedData = CalcDataChecksum(bank + 0x18, 0x1FEC);
  dataChecksum = *(unsigned long *)(bank + 0x10);
  if (dataChecksum != expectedData) {
    kprintf("ReadGenCount: data checksum mismatch\n");
    return 0;  /* Corrupted data */
  }

  /* Return generation counter at offset 0x14 */
  return *(unsigned long *)(bank + 0x14);
}

IOReturn InitCore99NVRAM(void)
{
  volatile unsigned char *nvAddrReg =
    (volatile unsigned char *) (POWERMAC_IO(PCI_NVRAM_ADDR_PHYS));
  unsigned long gen0, gen1;
  void *bank0, *bank1;

  kprintf("InitCore99NVRAM: nvAddrReg = %x\n", nvAddrReg);

  /* Core99 NVRAM uses double-buffering with generation counters:
   * - Physical NVRAM has TWO 8KB banks
   * - Each bank has a generation counter in its header
   * - Read both counters and use the bank with higher generation (newer data)
   */
  Core99NVRAMPhysAddr = (void *)nvAddrReg;
  bank0 = Core99NVRAMPhysAddr;
  bank1 = (void *)((char *)Core99NVRAMPhysAddr + 0x2000);

  gen0 = ReadGenCount(bank0);
  gen1 = ReadGenCount(bank1);

  kprintf("InitCore99NVRAM: bank0 gen=%d, bank1 gen=%d\n", gen0, gen1);

  /* Select the newer bank (higher generation count) */
  if (gen1 < gen0) {
    /* Bank 0 is newer */
    Core99PrimaryBank = bank0;
    Core99BackupBank = bank1;
    Core99GenCount = gen0;
  } else {
    /* Bank 1 is newer (or equal) */
    Core99PrimaryBank = bank1;
    Core99BackupBank = bank0;
    Core99GenCount = gen1;
  }

  /* Copy the newer bank into RAM buffer */
  bcopy(Core99PrimaryBank, Core99NVRAM, 0x2000);
  bcopy(Core99NVRAM, Core99NVRAMBackup, 0x2000);

  Core99NVRAMInited = 1;

  return 0;
}

/* Sync Core99 NVRAM buffer back to hardware if modified */
void SyncCore99NVRAM(void)
{
  unsigned char *nvramBuf = (unsigned char *)Core99NVRAM;
  unsigned long dataChecksum;
  unsigned char headerChecksum;

  if (!Core99NVRAMInited) {
    return;  /* NVRAM not initialized */
  }

  /* Check if NVRAM was modified since last sync */
  if (bcmp(Core99NVRAM, Core99NVRAMBackup, 0x2000) != 0) {
    kprintf("SyncCore99NVRAM: flushing modified NVRAM to hardware (gen %d -> %d)\n",
            Core99GenCount, Core99GenCount + 1);

    /* Increment generation counter at offset 0x14 */
    Core99GenCount++;
    *(unsigned long *)(nvramBuf + 0x14) = Core99GenCount;

    /* Calculate and write data checksum at offset 0x10 */
    dataChecksum = CalcDataChecksum(nvramBuf + 0x18, 0x1FEC);
    *(unsigned long *)(nvramBuf + 0x10) = dataChecksum;

    /* Set signature byte */
    nvramBuf[0] = 'Z';

    /* Calculate and write header checksum at offset 0x01 */
    headerChecksum = CalcHeaderChecksum(nvramBuf);
    nvramBuf[1] = headerChecksum;

    eieio();

    /* Write to BACKUP bank (atomic update - if power fails, primary is still valid) */
    bcopy(Core99NVRAM, Core99BackupBank, 0x2000);
    eieio();

    /* Swap bank pointers - backup bank is now primary */
    void *temp = Core99PrimaryBank;
    Core99PrimaryBank = Core99BackupBank;
    Core99BackupBank = temp;

    /* Update tracking backup */
    bcopy(Core99NVRAM, Core99NVRAMBackup, 0x2000);

    kprintf("SyncCore99NVRAM: sync complete\n");
  }
}

IOReturn
ReadNVRAM( unsigned int offset, unsigned int length, unsigned char * buffer )
{
  volatile unsigned char *nvAddrReg =
    (volatile unsigned char *) (POWERMAC_IO(PCI_NVRAM_ADDR_PHYS));
  volatile unsigned char *nvDataReg =
    (volatile unsigned char *) (POWERMAC_IO(PCI_NVRAM_DATA_PHYS));
int	i;

    if( offset + length > 0x2000 )
	return( IO_R_UNSUPPORTED);

    if (IsSawtooth()) {
      if (!Core99NVRAMInited) {
        if (InitCore99NVRAM() != 0) return -1;
      }
      for (i = 0; i < length; i++) {
	buffer[i] = Core99NVRAM[offset + i];
      }
    } else if (HasPMU()) {
      // This is a powerbook
      if (ApplePMUId == NULL) {
	for ( i = 0; i < length; i++ ) {
	  buffer[i] = 0;
	}
      } else {
	[ApplePMUId readNVRAM: offset: length: buffer: 0: 0: MBCallback];
	wait_for_callback();
      }
    } else {
      // This is a desktop mac
      if (IsPowerSurge()) {
        for( i = 0; i < length; i++) {
	  *nvAddrReg = (0xff & ((offset + i) >> 5));
	  eieio();
	  buffer[i] = *(nvDataReg + 16 * ((offset + i) & 0x1f));
	  eieio();
        }
      } else {
        for (i = 0; i < length; i++) {
	  buffer[i] = nvAddrReg[(offset + i) * 16];
        }
      }
    }

    return 0;
}

IOReturn
WriteNVRAM( unsigned int offset, unsigned int length, unsigned char * buffer )
{
  volatile unsigned char *nvAddrReg =
    (volatile unsigned char *) (POWERMAC_IO(PCI_NVRAM_ADDR_PHYS));
  volatile unsigned char *nvDataReg =
    (volatile unsigned char *) (POWERMAC_IO(PCI_NVRAM_DATA_PHYS));
int	i;

    if( offset + length > 0x2000 )
	return( IO_R_UNSUPPORTED);

    if (IsSawtooth()) {
      if (!Core99NVRAMInited) {
        if (InitCore99NVRAM() != 0) return -1;
      }
      for (i = 0; i < length; i++) {
	Core99NVRAM[offset + i] = buffer[i];
      }
    } else if (HasPMU()) { 
      // This is a powerbook
      if (ApplePMUId == NULL) {
      } else {
	[ApplePMUId writeNVRAM: offset: length: buffer: 0: 0: MBCallback];
	wait_for_callback();
      }
    } else {
      // This is a desktop mac
      if (IsPowerSurge()) {
        for( i = 0; i < length; i++) {
	  *nvAddrReg = (0xff & ((offset + i) >> 5));
	  eieio();
	  *(nvDataReg + 16 * ((offset + i) & 0x1f)) = buffer[i];
	  eieio();
        }
      } else {
        for( i = 0; i < length; i++) {
	  nvAddrReg[(offset + i) * 16] = buffer[i];
        }
      }
    }

    return 0;
}


int
GetMacOSTimeZone( void )
{
    int			macZone;
    IOReturn		err;

    err = ReadNVRAM( NVRAM_XPRAM_Offset + MACTIMEZONE, 4,
		     (unsigned char *)&macZone);

    printf( " macZone: %x",macZone );

    if( err == 0) {
	if( macZone & 0x00800000)
	    macZone |= 0xff000000;	// sign ext 24->32
	else
	    macZone &= 0x00ffffff;	// sign ext 24->32
    } else
	macZone = 0;
    return macZone;
}

unsigned int
get_unix_time_of_day( void )
{
    int			secs, macZone;
    int			err;

    err = cuda_time_of_day( &secs, FALSE );
/*	printf( "TOD secs: %x,",secs ); */
    secs -= (JAN11970 + GetMacOSTimeZone());
/*	printf( " = Mac OS X Server: %x\n",secs ); */
    return( secs );
}

void
set_unix_time_of_day( unsigned int unixSecs )
{
    int			secs, macZone;
    int			err;

/*	printf( "Mac OS X Server: %x,", unixSecs ); */
    secs = unixSecs + JAN11970 + GetMacOSTimeZone();
/*	printf( " = TOD secs: %x\n",secs ); */
   err = cuda_time_of_day( &secs, TRUE );
   return;
}

void MBCallback(id unused, UInt32 refnum, UInt32 length, UInt8* buffer)
{
    clear_wait(our_thread,0,FALSE);
}


// We have sent a command to the PMU driver.  Sleep until it has sent the
// command to the PMU.
void wait_for_callback(void)
{
    our_thread = current_thread();
    assert_wait(our_thread, FALSE);
    thread_block();
}
