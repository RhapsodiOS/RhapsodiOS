/*
 * Copyright (c) 1993-1996 NeXT Software, Inc.
 *
 * Driver class for SMC EtherCard Plus Elite16 Ethernet adapters.
 *
 * HISTORY
 *
 * 26 Jan 1993 
 *	Created.
 */

#import <driverkit/IOEthernet.h>
#import <driverkit/i386/directDevice.h>
#import "SMC16Hdw.h"
#import "wd83C690.h"

@interface SMC16:IOEthernet
{
    IOEISAPortAddress	base;		/* port base 			     */
    int			irq;		/* interrupt			     */
    enet_addr_t		myAddress;	/* local copy of ethernet address    */
    IONetwork		*network;	/* handle to kernel network object   */
    
    id			transmitQueue;	/* queue for outgoing packets 	     */
    BOOL		transmitActive;	/* trasmit in progress 		     */
    
    vm_offset_t		membase;	/* base address of onboard memory    */
    vm_size_t		memsize;	/* configured size of onboard memory */

    SMC16_len_t		memtotal;	/* actualy size of onboard memory    */
    SMC16_len_t		memused;	/* amount of onboard memory in use   */
    
    SMC16_off_t		rstart;		/* ptr to 1st buffer in ring	     */
    SMC16_off_t		rstop;		/* ptr to last bufferin in ring      */
    SMC16_off_t		rnext;		/* ptr to next avaliable buffer      */
    
    SMC16_off_t		tstart;		/* ptr to transmit buffer     	     */

    nic_rcon_reg_t	rconsave;	/* recv ctrl register value	     */
}

+ (BOOL)probe:(IODeviceDescription *)devDesc;

- initFromDeviceDescription:(IODeviceDescription *)devDesc;
- free;

- (IOReturn)enableAllInterrupts;
- (void)disableAllInterrupts;
- (BOOL)resetAndEnable:(BOOL)enable;
- (void)timeoutOccurred;
- (void)interruptOccurred;

- (BOOL)enablePromiscuousMode;
- (void)disablePromiscuousMode;
- (BOOL)enableMulticastMode;
- (void)disableMulticastMode;

- (void)transmit:(netbuf_t)pkt;

@end

