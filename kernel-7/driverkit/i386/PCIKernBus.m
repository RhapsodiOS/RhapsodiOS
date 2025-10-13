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

/*
 * Copyright (c) 1994 NeXT Computer, Inc.
 *
 * Kernel PCI Bus Resource Object(s).
 *
 * HISTORY
 *
 * 11 Oct 2025 raynorpat
 *	Created proper PCI bus support for i386.
 */

#import <mach/mach_types.h>

#import <driverkit/KernLock.h>
#import <driverkit/i386/PCIKernBus.h>
#import <driverkit/i386/PCIKernBusPrivate.h>
#import <driverkit/i386/PCI.h>
#import <driverkit/KernDevice.h>
#import <kernserv/i386/spl.h>
#import <machdep/i386/intr_exported.h>
#import <machdep/i386/io_inline.h>

#define IO_NUM_PCI_INTERRUPTS	16

/* PCI Configuration Mechanism #1 */
#define PCI_CONFIG_ADDRESS	0x0CF8
#define PCI_CONFIG_DATA		0x0CFC

/* PCI Configuration Address Format */
#define PCI_CONFIG_ENABLE	0x80000000
#define PCI_CONFIG_BUS(b)	(((b) & 0xFF) << 16)
#define PCI_CONFIG_DEV(d)	(((d) & 0x1F) << 11)
#define PCI_CONFIG_FUNC(f)	(((f) & 0x07) << 8)
#define PCI_CONFIG_REG(r)	((r) & 0xFC)

/* Maximum PCI bus/device/function numbers */
#define PCI_MAX_BUSES		256
#define PCI_MAX_DEVICES		32
#define PCI_MAX_FUNCTIONS	8

/*
 * Read a 32-bit value from PCI configuration space
 */
static inline unsigned long
pci_config_read32(unsigned char bus, unsigned char dev, unsigned char func, unsigned char reg)
{
    unsigned long address;
    unsigned long data;

    address = PCI_CONFIG_ENABLE |
              PCI_CONFIG_BUS(bus) |
              PCI_CONFIG_DEV(dev) |
              PCI_CONFIG_FUNC(func) |
              PCI_CONFIG_REG(reg);

    outl(PCI_CONFIG_ADDRESS, address);
    data = inl(PCI_CONFIG_DATA);

    return data;
}

/*
 * Read a 16-bit value from PCI configuration space
 */
static inline unsigned short
pci_config_read16(unsigned char bus, unsigned char dev, unsigned char func, unsigned char reg)
{
    unsigned long address;
    unsigned short data;

    address = PCI_CONFIG_ENABLE |
              PCI_CONFIG_BUS(bus) |
              PCI_CONFIG_DEV(dev) |
              PCI_CONFIG_FUNC(func) |
              PCI_CONFIG_REG(reg);

    outl(PCI_CONFIG_ADDRESS, address);
    data = inw(PCI_CONFIG_DATA + (reg & 2));

    return data;
}

/*
 * Read an 8-bit value from PCI configuration space
 */
static inline unsigned char
pci_config_read8(unsigned char bus, unsigned char dev, unsigned char func, unsigned char reg)
{
    unsigned long address;
    unsigned char data;

    address = PCI_CONFIG_ENABLE |
              PCI_CONFIG_BUS(bus) |
              PCI_CONFIG_DEV(dev) |
              PCI_CONFIG_FUNC(func) |
              PCI_CONFIG_REG(reg);

    outl(PCI_CONFIG_ADDRESS, address);
    data = inb(PCI_CONFIG_DATA + (reg & 3));

    return data;
}

/* PCI Header Types */
#define PCI_HEADER_TYPE_NORMAL		0x00
#define PCI_HEADER_TYPE_BRIDGE		0x01
#define PCI_HEADER_TYPE_CARDBUS		0x02
#define PCI_HEADER_TYPE_MASK		0x7F
#define PCI_HEADER_MULTIFUNCTION	0x80

/* PCI Class Codes */
#define PCI_CLASS_BRIDGE_DEVICE		0x06
#define PCI_SUBCLASS_PCI_BRIDGE		0x04

/* Global bus count tracking */
static int total_buses_found = 0;
static int total_devices_found = 0;

/*
 * Check if PCI bridge exists and is accessible
 */
static int
pci_check_bridge(unsigned char bus, unsigned char dev, unsigned char func,
                 unsigned char *secondary_bus)
{
    unsigned char header_type;
    unsigned char class_code, subclass;

    header_type = pci_config_read8(bus, dev, func, 0x0E);
    class_code = pci_config_read8(bus, dev, func, 0x0B);
    subclass = pci_config_read8(bus, dev, func, 0x0A);

    /* Check if this is a PCI-to-PCI bridge */
    if ((header_type & PCI_HEADER_TYPE_MASK) == PCI_HEADER_TYPE_BRIDGE &&
        class_code == PCI_CLASS_BRIDGE_DEVICE &&
        subclass == PCI_SUBCLASS_PCI_BRIDGE) {

        /* Read secondary bus number (offset 0x19) */
        *secondary_bus = pci_config_read8(bus, dev, func, 0x19);
        return 1;
    }

    return 0;
}

/*
 * Scan a single PCI bus
 */
static void
pci_scan_single_bus(unsigned char bus, int depth)
{
    unsigned char dev, func;
    unsigned short vendor_id, device_id;
    unsigned char header_type;
    unsigned char class_code, subclass, prog_if, revision;
    unsigned char secondary_bus;
    int multifunction;

    for (dev = 0; dev < PCI_MAX_DEVICES; dev++) {
        multifunction = 0;

        for (func = 0; func < PCI_MAX_FUNCTIONS; func++) {
            /* Read vendor ID */
            vendor_id = pci_config_read16(bus, dev, func, 0x00);

            /* Check if device exists */
            if (vendor_id == PCI_INVALID_VENDOR_ID || vendor_id == 0x0000) {
                if (func == 0)
                    break;  /* No device at this slot */
                else
                    continue;  /* Try next function */
            }

            /* Read device ID */
            device_id = pci_config_read16(bus, dev, func, 0x02);

            /* Read class code information */
            revision = pci_config_read8(bus, dev, func, 0x08);
            prog_if = pci_config_read8(bus, dev, func, 0x09);
            subclass = pci_config_read8(bus, dev, func, 0x0A);
            class_code = pci_config_read8(bus, dev, func, 0x0B);

            /* Read header type */
            header_type = pci_config_read8(bus, dev, func, 0x0E);

            /* Print device information */
            printf("Found PCI %d.%d device: ID=%x:%x at Dev=%d Func=%d Bus=%d\n",
                   (class_code >> 4) & 0x0F, class_code & 0x0F,
                   vendor_id, device_id,
                   dev, func, bus);

            total_devices_found++;

            /* Check if this is a PCI-to-PCI bridge */
            if (pci_check_bridge(bus, dev, func, &secondary_bus)) {
                printf("  PCI Bridge found: Primary=%d Secondary=%d\n",
                       bus, secondary_bus);

                /* Prevent infinite recursion and scan secondary bus */
                if (secondary_bus > 0 && secondary_bus < PCI_MAX_BUSES &&
                    depth < 8) {
                    total_buses_found++;
                    pci_scan_single_bus(secondary_bus, depth + 1);
                }
            }

            /* Check if multifunction device */
            if (func == 0) {
                multifunction = (header_type & PCI_HEADER_MULTIFUNCTION) != 0;
                if (!multifunction)
                    break;
            }
        }
    }
}

/*
 * Scan all PCI buses and enumerate devices
 */
static void
pci_scan_bus(void)
{
    printf("Scanning PCI bus(es)...\n");

    total_buses_found = 1;  /* Start with bus 0 */
    total_devices_found = 0;

    /* Start scanning from bus 0 */
    pci_scan_single_bus(0, 0);

    printf("PCI scan complete: %d bus%s, %d device%s\n",
           total_buses_found,
           total_buses_found == 1 ? "" : "es",
           total_devices_found,
           total_devices_found == 1 ? "" : "s");
}


static void
PCIKernBusInterruptDispatch(int deviceIntr, void * ssp, int old_ipl, void *_interrupt)
{
    BOOL			leave_enabled;
    PCIKernBusInterrupt_ *	interrupt = (PCIKernBusInterrupt_ *)_interrupt;

    leave_enabled = KernBusInterruptDispatch(_interrupt, ssp);
    if (!leave_enabled) {
        KernLockAcquire(interrupt->_PCILock);
        intr_disable_irq(interrupt->_irq);
        interrupt->_irqEnabled = NO;
        KernLockRelease(interrupt->_PCILock);
    }
}

@implementation PCIKernBusInterrupt

- initForResource:	resource
	item:		(unsigned int)item
	shareable:	(BOOL)shareable
{
    [super initForResource:resource item:item shareable:shareable];

    _irq = item;
    _irqEnabled = NO;
    _PCILock = [[KernLock alloc] initWithLevel:IPLHIGH];
    _priorityLevel = IPLDEVICE;

    return self;
}

- dealloc
{
    [_PCILock free];
    return [super dealloc];
}

- attachDeviceInterrupt:	interrupt
{
    if (!interrupt)
    	return nil;

    [_PCILock acquire];

    if( NO == _irqAttached) {
        intr_register_irq(_irq,
                        (intr_handler_t)PCIKernBusInterruptDispatch,
                        (unsigned int)self,
                        _priorityLevel);
	_irqAttached = YES;
    }
    /*
     * -attachDeviceInterrupt will return nil
     * if the interrupt is suspended.
     */
    if ([super attachDeviceInterrupt:interrupt]) {
        _irqEnabled = YES;
        intr_enable_irq(_irq);
    } else {
        intr_disable_irq(_irq);
        _irqEnabled = NO;
    }

    [_PCILock release];

    return self;
}

- attachDeviceInterrupt:	interrupt
		atLevel: 	(int)level
{
    if (!interrupt)
	return nil;

    [_PCILock acquire];

    if (level < _priorityLevel || level >  IPLSCHED) {
	[_PCILock release];
    	return nil;
    }

    if (level > _priorityLevel)
    	intr_change_ipl(_irq, level);

    _priorityLevel = level;

    if( NO == _irqAttached) {
        intr_register_irq(_irq,
                        (intr_handler_t)PCIKernBusInterruptDispatch,
                        (unsigned int)self,
                        _priorityLevel);
	_irqAttached = YES;
    }
    /*
     * -attachDeviceInterrupt will return nil
     * if the interrupt is suspended.
     */
    if ([super attachDeviceInterrupt:interrupt]) {
        _irqEnabled = YES;
        intr_enable_irq(_irq);
    } else {
        intr_disable_irq(_irq);
        _irqEnabled = NO;
    }

    [_PCILock release];
    return self;
}

- detachDeviceInterrupt:	interrupt
{
    int			irq = [self item];

    [_PCILock acquire];

    if ( ![super detachDeviceInterrupt:interrupt]) {
      intr_disable_irq(_irq);
      _irqEnabled = NO;
    }

    [_PCILock release];
    return self;
}

- suspend
{
    [_PCILock acquire];

    [super suspend];

    if (_irqEnabled) {
      intr_disable_irq(_irq);
      _irqEnabled = NO;
    }

    [_PCILock release];

    return self;
}

- resume
{
    [_PCILock acquire];

    if ([super resume] && !_irqEnabled) {
        _irqEnabled = YES;
        intr_enable_irq(_irq);
    }

    [_PCILock release];

    return self;
}

@end



@implementation PCIKernBus

static const char *resourceNameStrings[] = {
    IRQ_LEVELS_KEY,
    DMA_CHANNELS_KEY,
    MEM_MAPS_KEY,
    IO_PORTS_KEY,
    NULL
};

+ initialize
{
    [self registerBusClass:self name:"PCI"];
    return self;
}

- init
{
    [super init];

    [self _insertResource:[[KernBusItemResource alloc]
				initWithItemCount:IO_NUM_PCI_INTERRUPTS
				itemKind:[PCIKernBusInterrupt class]
				owner:self]
		    withKey:IRQ_LEVELS_KEY];

    [self _insertResource:[[KernBusRangeResource alloc]
    					initWithExtent:RangeMAX
					kind:[KernBusMemoryRange class]
					owner:self]
		    withKey:MEM_MAPS_KEY];

    [[self class] registerBusInstance:self name:"PCI" busId:[self busId]];

    /* Scan and enumerate PCI devices */
    pci_scan_bus();

    printf("PCI bus support enabled\n");
    return self;
}

- (const char **)resourceNames
{
    return resourceNameStrings;
}

- free
{

    if ([self areResourcesActive])
    	return self;

    [[self _deleteResourceWithKey:IRQ_LEVELS_KEY] free];
    [[self _deleteResourceWithKey:MEM_MAPS_KEY] free];

    return [super free];
}

/*
 * Detect PCI bus presence
 */
- (BOOL)isPCIPresent
{
    unsigned long vendorID;

    /* Try to read vendor ID from device 0:0:0 */
    /* If PCI is present, this should return a valid vendor ID */
    vendorID = pci_config_read32(0, 0, 0, 0x00);

    /* Valid vendor IDs are 0x0001-0xFFFE (0xFFFF means no device) */
    if ((vendorID & 0xFFFF) == 0xFFFF || (vendorID & 0xFFFF) == 0x0000) {
        return NO;
    }

    return YES;
}

/*
 * Extract PCI address from device description
 */
- (IOReturn)configAddress:deviceDescription
                   device:(unsigned char *)devNum
                 function:(unsigned char *)funNum
                      bus:(unsigned char *)busNum
{
    const char *devStr, *funcStr, *busStr;

    if (!deviceDescription) {
        return IO_R_INVALID_ARG;
    }

    /* Get device, function, and bus from device description */
    devStr = [deviceDescription stringForKey:"Device"];
    funcStr = [deviceDescription stringForKey:"Function"];
    busStr = [deviceDescription stringForKey:"Bus"];

    if (!devStr || !funcStr || !busStr) {
        return IO_R_NO_DEVICE;
    }

    /* Parse the values */
    if (devNum) *devNum = (unsigned char)strtoul(devStr, NULL, 0);
    if (funNum) *funNum = (unsigned char)strtoul(funcStr, NULL, 0);
    if (busNum) *busNum = (unsigned char)strtoul(busStr, NULL, 0);

    return IO_R_SUCCESS;
}

/*
 * Read from PCI configuration space
 */
- (IOReturn)getRegister:(unsigned char)address
                 device:(unsigned char)devNum
               function:(unsigned char)funNum
                    bus:(unsigned char)busNum
                   data:(unsigned long *)data
{
    if (!data) {
        return IO_R_INVALID_ARG;
    }

    /* Verify address is 32-bit aligned */
    if (address & 0x03) {
        return IO_R_INVALID_ARG;
    }

    *data = pci_config_read32(busNum, devNum, funNum, address);

    return IO_R_SUCCESS;
}

/*
 * Write to PCI configuration space
 */
- (IOReturn)setRegister:(unsigned char)address
                 device:(unsigned char)devNum
               function:(unsigned char)funNum
                    bus:(unsigned char)busNum
                   data:(unsigned long)data
{
    unsigned long configAddress;

    /* Verify address is 32-bit aligned */
    if (address & 0x03) {
        return IO_R_INVALID_ARG;
    }

    configAddress = PCI_CONFIG_ENABLE |
                    PCI_CONFIG_BUS(busNum) |
                    PCI_CONFIG_DEV(devNum) |
                    PCI_CONFIG_FUNC(funNum) |
                    PCI_CONFIG_REG(address);

    outl(PCI_CONFIG_ADDRESS, configAddress);
    outl(PCI_CONFIG_DATA, data);

    return IO_R_SUCCESS;
}

@end
