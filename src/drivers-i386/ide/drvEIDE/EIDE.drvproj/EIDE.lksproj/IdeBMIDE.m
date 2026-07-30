/*
 * Copyright (c) 1999 Apple Computer, Inc. All rights reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 *
 * "Portions Copyright (c) 1999 Apple Computer, Inc.  All Rights
 * Reserved.  This file contains Original Code and/or Modifications of
 * Original Code as defined in and that are subject to the Apple Public
 * Source License Version 1.0 (the 'License').  You may not use this file
 * except in compliance with the License.  Please obtain a copy of the
 * License at http://www.apple.com/publicsource and read it before using
 * this file.
 *
 * The Original Code and all software distributed under the License are
 * distributed on an 'AS IS' basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE OR NON-INFRINGEMENT.  Please see the
 * License for the specific language governing rights and limitations
 * under the License."
 *
 * @APPLE_LICENSE_HEADER_END@
 */
/*
 * IdeBMIDE.m - Generic SFF-8038i bus-master IDE core. Chipset-independent
 * DMA engine and PRD handling, shared by all chipset back-ends.
 * Moved out of IdePIIX.m; no logic changes.
 */
#import "IdeCnt.h"
#import "IdeBMIDE.h"
#import "IdeCntCmds.h"
#import "AtapiCntCmds.h"
#import <driverkit/i386/IOPCIDeviceDescription.h>
#import <driverkit/i386/IOPCIDirectDevice.h>
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <mach/mach_interface.h>
#import <machdep/i386/io_inline.h>
#import "IdeDDM.h"
#if (IO_DRIVERKIT_VERSION != 330)
#import <machdep/machine/pmap.h>
#endif

extern vm_offset_t pmap_resident_extract(pmap_t pmap, vm_offset_t va);

#ifndef MIN
#define MIN(a,b)    ((a) < (b) ? (a) : (b))
#endif

/*
 * Function: IOMallocPage
 *
 * Purpose:
 *   Returns a pointer to a page-aligned memory block of size >= PAGE_SIZE.
 *   Note that on Intel, the hardware page size of 4K. However, MACH's
 *   notion of a page is 8K, which is comprised of two contiguous
 *   (physical/virtual) hardware pages.
 *
 * Return:
 *   Actual pointer and size of block returned in actual_ptr and actual_size.
 *   Use these as arguments to IOFree: IOFree(*actual_ptr, *actual_size);
 */
static void *
IOMallocPage(int request_size, void ** actual_ptr,
				 int * actual_size)
{
    void * mem_ptr;

	/*
	 * Minimize memory use by first trying to allocate the requested size
	 * without any padding.
	 */
	*actual_size = round_page(request_size);
	mem_ptr = IOMalloc(*actual_size);
	if (mem_ptr == NULL)
		return NULL;

	/*
	 * Check alignment of this page.
	 */
	if ((vm_offset_t)mem_ptr & (PAGE_SIZE - 1)) {	// NOT page aligned.
		IOFree(mem_ptr, *actual_size);
		*actual_size = round_page(request_size) + PAGE_SIZE;
		mem_ptr = IOMalloc(*actual_size);
		if (mem_ptr == NULL)
			return NULL;
	}

	*actual_ptr = mem_ptr;
	return ((void *)round_page(mem_ptr));
}

/*
 * Function: bmVirtualToPhysical
 *
 * Similar to IOPhysicalFromVirtual but with no SPLVM/SPLX and locking.
 */
static __inline__ vm_offset_t
bmVirtualToPhysical(struct vm_map *map, vm_offset_t vaddr)
{
	return (vm_offset_t)pmap_resident_extract(
			(pmap_t)vm_map_pmap_EXTERNAL(map),
			vaddr);
}

/*
 * Function: bmStartDMA
 *
 * Purpose:
 * Start the bus master by writing a 1 to the SSBM bit in BMICX register.
 *
 * Argument:
 * piix_base - base address of the I/O space mapped bus master registers
 */
static __inline__ void
bmStartDMA(u_short piix_base)
{
	bmide_bmicx_u piix_cmd;

	/*
	 * Engage the bus master by writing 1 to the start bit in the
	 * Command Register.
	 */
	piix_cmd.byte = inb(piix_base + BMIDE_BMICX);
	piix_cmd.bits.ssbm = 1;
	outb(piix_base + BMIDE_BMICX, piix_cmd.byte);
}

/*
 * Function: bmStopDMA
 *
 * Purpose:
 * Stop the bus master by clearing the SSBM bit in BMICX register.
 *
 * Argument:
 * piix_base - base address of the I/O space mapped bus master registers
 *
 * Note:
 * Not declared static: called directly (as a plain C function) from
 * IdePIIX.m's PIIXInit, so it needs external linkage. See IdeBMIDE.h.
 */
void
bmStopDMA(u_short piix_base)
{
	bmide_bmicx_u piix_cmd;

	/*
	 * Stop the bus master by writing 0 to the start bit in the
	 * Command Register.
	 */
	piix_cmd.byte = inb(piix_base + BMIDE_BMICX);
	piix_cmd.bits.ssbm = 0;
	outb(piix_base + BMIDE_BMICX, piix_cmd.byte);
}

/*
 * Function: bmGetStatus
 *
 * Purpose:
 * Return the PIIX BMISX (bus master IDE status register).
 *
 * Argument:
 * piix_base - base address of the I/O space mapped bus master registers
 */
static __inline__ u_char
bmGetStatus(u_short piix_base)
{
	return (inb(piix_base + BMIDE_BMISX));
}

/*
 * Function: bmSetupPRDTable
 *
 * Purpose:
 * Setup the PRD (descriptor) table for the current IDE transfer.
 * This table must be aligned on a DWord (4 byte) boundary.
 *
 * Arguments:
 * table    - points to the start of the PRD table
 * size     - max number of PRD entries that the table can hold
 * vaddr	- virtual address of the start of memory buffer
 * size		- size of memory buffer in bytes
 * map		- vm_map for the memory buffer
 *
 * Return:
 *	YES: table is setup and ready for use
 *	NO : table full or alignment error
 *
 */
static __inline__ BOOL
bmSetupPRDTable(bmide_prd_t *table, u_int table_size, vm_offset_t vaddr,
	u_int size, struct vm_map *map)
{
	vm_offset_t vaddr_next;
	vm_offset_t paddr;
	vm_offset_t paddr_next;
	vm_offset_t paddr_start;
	const char *name = "PIIXSetupPRDTable";
	u_int len_prd;
	u_int index;

#ifdef DEBUG
	bmide_prd_t *table_saved = table;
#endif DEBUG

	ddm_ide_dma("  PIIXSetupPRDTable: vaddr:%08x size:%d\n",
		(u_int)vaddr, (u_int)size, 3, 4, 5);

	if (vaddr & (BMIDE_BUF_ALIGN - 1)) {
		IOLog("%s: buffer is not %d byte aligned\n", name, BMIDE_BUF_ALIGN);
		return NO;
	}

	if (size == 0) {
		IOLog("%s: zero length DMA buffer\n", name);
		return NO;
	}

	index = len_prd = 0;
	paddr = bmVirtualToPhysical(map, vaddr);
	paddr_start = paddr;
	do {
		u_int len;

		vaddr_next = trunc_page(vaddr) + PAGE_SIZE;		// next virtual page
		paddr_next = trunc_page(paddr) + PAGE_SIZE;		// next phys page
		vaddr      = vaddr_next;

		len = paddr_next - paddr;		// length to transfer in this page
		if (len > size) len = size;		// take the minimum
		size  -= len;					// decrement total remaining bytes
		len_prd += len;					// increment current PRD counter

		/*
		 * If there are more bytes remaining, try to append the next
		 * page into the same PRD. We must check that the next page
		 * is physically contiguous with the current one.
		 *
		 * Each PRD cannot cross 64K boundary, and is limited to 64K per PRD.
		 */
		if (size &&
		(paddr_next == (paddr = bmVirtualToPhysical(map, vaddr))) &&
		((paddr_start & ~(BMIDE_BUF_BOUND-1))==(paddr & ~(BMIDE_BUF_BOUND-1))) &&
		(len_prd <= (BMIDE_BUF_LIMIT - PAGE_SIZE))) {
		continue;
		}

		/*
		 * Setup PRD entry
		 *
		 * For the length field in PRD, 0 is used to denote the max
		 * transfer size of 64K.
		 */
		table->base = paddr_start;
		table->count = (len_prd == BMIDE_BUF_LIMIT) ? 0 : len_prd;
		table->eot = 0;
		table++;

		len_prd = 0;
		paddr_start = paddr;

	} while (size && (++index < table_size));

	if (size) {
		IOLog("%s: PRD table exhausted\n", name);
		return NO;
	}

	/*
	 * Set the 'end-of-table' bit on the last PRD entry.
	 */
	--table;
	table->eot = 1;

#ifdef DEBUG
	{
	int i = 0;
	u_int *ip = (u_int *)&table_saved[0];
	do {
		ddm_ide_dma("    table[%d]  %08x:%08x\n", i, *ip, *(ip+1), 4, 5);
		ip += 2;
	} while (i++ < index);
	}
#endif DEBUG

	return YES;
}

/*
 * Function: bmPrepareDMA
 *
 * Purpose:
 * Prepare the PIIX bus master for a DMA transfer.
 *
 * Arguments:
 *  piix_base - base address of the I/O space mapped bus master registers
 *  table     - points to the start of the PRD table
 *  tableAddr - physical address of the table
 *  isRead    - YES for read transfers (from device to host)
 */
static __inline__ BOOL
bmPrepareDMA(u_short piix_base, u_int tableAddr, BOOL isRead)
{
	bmide_bmicx_u piix_cmd;
	bmide_bmisx_u piix_status;

	/*
	 * Provide the starting address of the PRD table by loading the
	 * PRD Table Pointer Register.
	 *
	 * For some reason, outl(piix_base + BMIDE_BMIDTPX, tableAddr)
	 * will only write the lower 16-bit WORD. That's why we use
	 * two outw instructions.
	 */
	outw(piix_base + BMIDE_BMIDTPX, tableAddr & 0xffff);
	outw(piix_base + BMIDE_BMIDTPX + 2, (tableAddr >> 16) & 0xffff);

	/*
	 * Set the R/W bit depending on the direction of the transfer.
	 * The controller is also STOP'ed.
	 *
	 * Arghh!!! Why does the Intel PIIX3 and PIIX4 doc have this backwards?
	 */
	piix_cmd.byte = 0;
	piix_cmd.bits.rwcon = isRead ? 1 : 0;
	outb(piix_base + BMIDE_BMICX, piix_cmd.byte);

	/*
	 * Clear interrupt and error bits in the Status Register.
	 */
	piix_status.byte = inb(piix_base + BMIDE_BMISX);
	piix_status.bits.err = piix_status.bits.ideints = 1;
//	piix_status.bits.dma0cap = piix_status.bits.dma1cap = 1;
	outb(piix_base + BMIDE_BMISX, piix_status.byte);

	return YES;
}

@implementation IdeController(BMIDE)

/*
 * Method: bmRegisterRange:
 *
 * Purpose:
 * Add the 8-byte Bus-Master control registers to the portRangeList in
 * the deviceDescription. The base address for the registers resides in
 * PCI config space location 0x20. The first 8 bytes are for the primary
 * IDE channel, the next eight bytes are for the secondary IDE channel.
 *
 * Note:
 * This must be called before [super init...] because that's when the
 * resources are registered.
 */
- (BOOL) bmRegisterRange:(IOPCIDeviceDescription *)devDesc
{
    IOReturn 		rtn;
	unsigned long	bmiba;
	IORange 		io_range[2];

    rtn = [[self class] getPCIConfigData:&bmiba atRegister:BMIDE_BMIBA
		withDeviceDescription:devDesc];
    if (rtn != IO_R_SUCCESS) {
    	IOLog("%s: PCI config space access error %d\n", [self name], rtn);
		return NO;
    }

	/*
	 * Sanity check. Make sure this is an I/O range.
	 */
	if ((bmiba & 0x01) == 0) {
		IOLog("%s: PCI memory range 0x%02x (0x%08lx) is not an I/O range\n",
			[self name], BMIDE_BMIBA, bmiba);
		return NO;
	}

	_bmRegs = bmiba & BMIDE_BM_MASK;

	if (_bmRegs == 0)	// uninitialized range
		return NO;

	if (_ideChannel == PCI_CHANNEL_SECONDARY)
		_bmRegs += BMIDE_BM_OFFSET;

	/*
	 * Add this range to our device description's port range list.
	 */
	io_range[0] = [devDesc portRangeList][0];
	io_range[1].start = _bmRegs;
	io_range[1].size  = BMIDE_BM_SIZE;
	if ([devDesc setPortRangeList:io_range num:2] != IO_R_SUCCESS) {
		IOLog("%s: setPortRangeList failed\n", [self name]);
		return NO;
	}

	return YES;
}

/*
 * Method: bmInitPRDTable
 *
 * Purpose:
 * Initialize a "page-aligned" page of memory for the PRD descriptors
 * used by the bus master IDE controller.
 *
 * FIXME: Need to free the _prdTable memory.
 */
- (BOOL) bmInitPRDTable
{
	_prdTable.size = PAGE_SIZE;
	_prdTable.ptr = (void *)IOMallocPage(
						_prdTable.size,
						&_prdTable.ptrReal,
						&_prdTable.sizeReal
						);

	/*
	 * _prdTable->ptr should now points to a physically contiguous block
	 * of PAGE_SIZE bytes.
	 */
    if (_prdTable.ptr == NULL)
		return NO;

	/*
	 * cache the physical address of the descriptor table to _tablePhyAddr.
	 */
	if (IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_address_t)_prdTable.ptr,
		&_tablePhyAddr) != IO_R_SUCCESS) {
		IOFree(_prdTable.ptrReal, _prdTable.sizeReal);
		_prdTable.ptr = NULL;		/* prevent double-free in -free */
		return NO;
	}

	bzero(_prdTable.ptr, _prdTable.size);
	return YES;
}

/*
 * Even if an interrupt is missed, consider the transfer operation
 * successful if the PIIX status flags says so.
 */
#define TRUST_PIIX	1

/*
 * Method: PIIXPerformDMA
 *
 * Purpose:
 * Program the PIIX controller to perform DMA READ/WRITE transfers
 * based on the transfer request ideIoReq. The entire transfer is
 * translated into one or more PRD entries in the PRD table. We will
 * get a single interrupt when the entire transfer is complete.
 *
 * Note:
 * The PIIX status register should have bit 2 and bit 0 set at the
 * conclusion of the transfer. This corresponds to the case when the
 * IDE device generated an interrupt and the size of the PRD is equal
 * to the IDE device transfer size.
 *
 * If bit 1 is set, meaning that the controller encountered a target
 * or master abort, it is very likely that we told it to DMA to/from
 * an invalid piece of memory. Perhaps due to an incorrect virtual
 * to physical map conversion.
 */
- (ide_return_t)performDMA:(ideIoReq_t *)ideIoReq
    taskfile:(const ideTaskfile_t *)taskfile command:(unsigned int)command
{
	ideRegsVal_t	*ideRegs = &(ideIoReq->regValues);
	ideRegsAddrs_t	*rp = &_ideRegsAddrs;
    unsigned char	status;
	bmide_bmisx_u	piix_status;
	ide_return_t	rtn = IDER_SUCCESS;
	BOOL			read;

	if (command != IDE_READ_DMA && command != IDE_WRITE_DMA &&
	    command != IDE_READ_DMA_EXT && command != IDE_WRITE_DMA_EXT)
		return IDER_REJECT;

	read = (command == IDE_READ_DMA || command == IDE_READ_DMA_EXT);

	ddm_ide_dma("DMA command:%x block:%d count:%d read:%d map:%d\n",
		command,
		ideIoReq->block,
		ideIoReq->blkcnt,
		read,
		ideIoReq->map);

	/*
	 * wait for BSY = 0 and DRDY = 1
	 */
    rtn = [self waitForDeviceReady];
    if (rtn != IDER_SUCCESS) {
		IOLog("%s: drive not ready\n", [self name]);
		return (rtn);
    }

	/*
	 * Set up PRD descriptor table
	 */
	if (bmSetupPRDTable(_prdTable.ptr,
		BMIDE_DT_BOUND/sizeof(bmide_prd_t),
		(vm_offset_t)ideIoReq->addr,
		ideIoReq->blkcnt * IDE_SECTOR_SIZE,
		(struct vm_map *)ideIoReq->map) == NO) {
		return NO;
	}

	/*
	 * Prepare the PIIX controller for the current transfer.
	 */
	if (bmPrepareDMA(_bmRegs, _tablePhyAddr, read) == NO) {
		IOLog("%s: PIIXPrepareDMA error\n", [self name]);
		return IDER_CMD_ERROR;
	}

	/*
	 * Program the drive (task file).
	 */
	[self writeTaskfile:taskfile errorRegisters:ideRegs];

	ddm_ide_dma(
		"DMA drHead:%02x sectNum:%02x sectCnt:%02x cylLow:%02x cylHigh:%02x\n",
		ideRegs->drHead,
		ideRegs->sectNum,
		ideRegs->sectCnt,
		ideRegs->cylLow,
		ideRegs->cylHigh);

	/*
	 * Issue DMA READ/WRITE command to drive.
	 */
	[self enableInterrupts];
    outb(rp->command, command);

	/*
	 * Start the PIIX bus master.
	 */
	bmStartDMA(_bmRegs);

	/* Wait for interrupt to signal the completion of the transfer.
	 */
	rtn = [self ideWaitForInterrupt:command ideStatus:&status];
	piix_status.byte = bmGetStatus(_bmRegs);
	bmStopDMA(_bmRegs);

/* Trust bus-master status even if the completion interrupt was missed. */
#ifdef TRUST_PIIX
	if ((piix_status.byte & BMIDE_STATUS_MASK) == BMIDE_STATUS_OK) {

			if (rtn != IDER_SUCCESS) {
				/* Interrupt timed-out, but PIIX claims that transaction
				 * was completed without errors.
				 * This may require more testing. Always trust PIIX?
				 * First, read status from the drive.
				 */
				if ((rtn = [self waitForNotBusy]) != IDER_SUCCESS)
					return IDER_CMD_ERROR;
				status = inb(rp->status);
			}
#else
	if ((rtn == IDER_SUCCESS) && ((piix_status.byte & BMIDE_STATUS_MASK) ==
		BMIDE_STATUS_OK)) {
#endif TRUST_PIIX

		    if (status & (ERROR | WRITE_FAULT)) {
				[self getIdeRegisters:ideRegs Print:"DMA error"];
				return IDER_CMD_ERROR;
	    	}

	    	if (status & ERROR_CORRECTED) {
				IOLog("%s: Error during data transfer (corrected).\n",
			    	[self name]);
		    }
	}
	else {
		[self getIdeRegisters:ideRegs Print:NULL];
		IOLog("%s: PIIX status:0x%02x error code:%d\n",
			[self name], piix_status.byte, rtn);
		rtn = IDER_CMD_ERROR;
	}

	ddm_ide_dma(
		"END drHead:%02x sectNum:%02x sectCnt:%02x cylLow:%02x cylHigh:%02x\n",
    	inb(rp->drHead),
    	inb(rp->sectNum),
    	inb(rp->sectCnt),
    	inb(rp->cylLow),
    	inb(rp->cylHigh));

	return (rtn);
}

#define MAX_BUSY_WAIT 				(1000*100)

/*
 * Perform DMA transfers for ATAPI devices.
 */
- (sc_status_t) performATAPIDMA:(atapiIoReq_t *)atapiIoReq
	buffer:(void *)buffer
	client:(struct vm_map *)client
{
	bmide_bmisx_u piix_status;
	unsigned char cmd = atapiIoReq->atapiCmd[0];
	ide_return_t	rtn;
    unsigned char	status;
	ideRegsAddrs_t	*rp = &_ideRegsAddrs;
	int	i;

	//IOLog("DMA transfer\n");

	atapiIoReq->bytesTransferred = 0;

	/*
	 * Set up PRD descriptor table
	 */
	if (bmSetupPRDTable(_prdTable.ptr,
		BMIDE_DT_BOUND/sizeof(bmide_prd_t),
		(vm_offset_t)buffer,
		atapiIoReq->maxTransfer,
		client) == NO)
		{
		atapiIoReq->scsiStatus = STAT_CHECK;
		return SR_IOST_CMDREJ;
	}

	if (bmPrepareDMA(_bmRegs, _tablePhyAddr, atapiIoReq->read) == NO) {
		IOLog("%s: PIIXPrepareDMA error\n", [self name]);
		atapiIoReq->scsiStatus = STAT_CHECK;
		return SR_IOST_CMDREJ;
	}

	/*
	 * Start the PIIX bus master.
	 */
	bmStartDMA(_bmRegs);

	if (atapiIoReq->timeout > IDE_INTR_TIMEOUT) {
		u_int current_timeout = [self interruptTimeOut];

		//IOLog("using SCSI timeout:%d\n", atapiIoReq->timeout);
		[self setInterruptTimeOut:atapiIoReq->timeout];
		rtn = [self ideWaitForInterrupt:cmd ideStatus:&status];
		[self setInterruptTimeOut:current_timeout];
	}
	else {
		rtn = [self ideWaitForInterrupt:cmd ideStatus:&status];
	}

	piix_status.byte = bmGetStatus(_bmRegs);
	bmStopDMA(_bmRegs);

	/*
	 * This is stupid but the Chinon drive fires off an interrupt first
	 * and then updates the status register. It appears that any drive
	 * based on Western Digital chipset will do this. At any rate, this
	 * code is harmless and should be left here.
	 */
	for (i = 0; i < MAX_BUSY_WAIT; i++)	{
		if (status & BUSY)
			IODelay(10);
		else
			break;
		status = inb(_ideRegsAddrs.status);
	}

/* Trust bus-master status even if the completion interrupt was missed. */
#ifdef TRUST_PIIX
	if ((piix_status.byte & BMIDE_STATUS_MASK) == BMIDE_STATUS_OK) {
		if (rtn != IDER_SUCCESS) {
			/* Interrupt timed-out, but PIIX claims that transaction
			 * was completed without errors.
			 * This may require more testing. Always trust PIIX?
			 * First, read status from the drive.
			 */
			if ((rtn = [self waitForNotBusy]) != IDER_SUCCESS) {
				IOLog("%s: FATAL: ATAPI Drive: %d Command %x failed.\n",
					[self name], _driveNum, atapiIoReq->atapiCmd[0]);
				[self getIdeRegisters:NULL Print:"ATAPI DMA"];
				IOLog("%s: transfer size: %d\n",
					[self name], atapiIoReq->maxTransfer);
				[self atapiSoftReset:_driveNum];
				atapiIoReq->scsiStatus = STAT_CHECK;
				return SR_IOST_CHKSNV;
			}
			status = inb(rp->status);
		}
#else
	if ((rtn == IDER_SUCCESS) && ((piix_status.byte & BMIDE_STATUS_MASK) ==
		BMIDE_STATUS_OK)) {
#endif TRUST_PIIX

		if (status & ERROR) {
			atapiIoReq->scsiStatus = STAT_CHECK;
			return SR_IOST_CHKSNV;
		}
	}
	else {
		[self getIdeRegisters:NULL Print:"ATAPI DMA"];
		IOLog("%s: PIIX status:0x%02x error code:%d\n",
			[self name], piix_status.byte, rtn);
		IOLog("%s: transfer size: %d\n", [self name], atapiIoReq->maxTransfer);
		[self atapiSoftReset:_driveNum];
		atapiIoReq->scsiStatus = STAT_CHECK;
		return SR_IOST_CHKSNV;
	}

	atapiIoReq->bytesTransferred = atapiIoReq->maxTransfer;
	atapiIoReq->scsiStatus = STAT_GOOD;
	return SR_IOST_GOOD;
}

@end
