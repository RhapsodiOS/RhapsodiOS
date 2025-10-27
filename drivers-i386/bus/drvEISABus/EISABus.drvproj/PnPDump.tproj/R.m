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
 * R.m
 * PnP Resource Stubs and Utility Functions
 *
 * This file contains:
 * - PnP resource class implementations (PnPDependentResources, PnPDeviceResources,
 *   PnPLogicalDevice, PnPResource, PnPResources, pnpDMA, pnpIOPort, pnpIRQ, pnpMemory)
 * - I/O utility functions (IOMalloc, IOFree, IOLog, IOGetTimestamp, IOScheduleFunc, etc.)
 * - PnP dump utility program (main function)
 */

#import <objc/Object.h>
#import <objc/objc-runtime.h>
#import <stdio.h>
#import <string.h>
#import <stdarg.h>

/* Static variables */
static unsigned short readPort = 0;
static char verbose = 0;
static char noValue[64];  /* Buffer for undefined value names */

/* Global variables for utility program */
static char *progname;
static char cmdBuffer[512];    /* Command buffer */
static char valueBuffer[512];  /* Value buffer */

/* Standard I/O */
typedef struct __sFILE FILE;
extern FILE *__stderrp;
#define stderr __stderrp

/* Standard C library functions */
extern void *malloc(unsigned int size);
extern void free(void *ptr);
extern int vsprintf(char *str, const char *format, va_list args);
extern int sprintf(char *str, const char *format, ...);
extern int printf(const char *format, ...);
extern int fprintf(FILE *stream, const char *format, ...);
extern int strcmp(const char *s1, const char *s2);
extern char *strcpy(char *dest, const char *src);
extern unsigned int strlen(const char *s);
extern void syslog(int priority, const char *format, ...);
extern void exit(int status);

/* Mach/kernel functions */
extern int thread_suspend(int thread);
extern int thread_resume(int thread);
extern int msg_receive(void *msg, int option, int timeout);
extern int port_allocate(int task, int *port);
extern void kern_timestamp(unsigned long long *timestamp);

/* C thread functions */
extern int cthread_fork(void (*func)(void *), void *arg);
extern void cthread_exit(int result);

/* Objective-C runtime functions (types defined in objc headers) */
/* Note: id, Class, SEL are defined in <objc/objc-runtime.h> */

/* DriverKit functions */
extern void calloutThread(void *arg);
extern void __IOCopyMemory(void *dest, const void *src, unsigned int count, unsigned int flags);

/* External ports */
extern int sleepPort;
extern int *task_self_ptr;

/* Callout chain structure for IOScheduleFunc/IOUnscheduleFunc */
typedef struct CalloutEntry {
    void (*func)(void *);              /* offset 0 - function pointer */
    void *arg;                         /* offset 4 - argument */
    unsigned int timestamp_low;        /* offset 8 - timestamp low 32 bits */
    unsigned int timestamp_high;       /* offset 12 - timestamp high 32 bits */
    struct CalloutEntry *prev;         /* offset 16 - previous entry */
    struct CalloutEntry *next;         /* offset 20 - next entry */
} CalloutEntry;

/* External callout chain variables */
extern CalloutEntry *calloutChain;
extern id calloutLock;

/* PnPDependentResources stubs */

@interface PnPDependentResources : Object
{
    char pad[20];        /* padding to offset 0x14 */
    char goodConfigFlag; /* offset 0x14 (20) */
}
@end

@implementation PnPDependentResources

- (int)goodConfig
{
    return (int)goodConfigFlag;
}

- setGoodConfig:(char)flag
{
    goodConfigFlag = flag;
    return self;
}

@end

/* PnPDeviceResources stubs */

@interface PnPDeviceResources : Object
{
    id deviceListObj;           /* offset 4 */
    char deviceNameBuf[80];     /* offset 8 (0x08) to 87 (0x57) */
    size_t deviceNameLen;       /* offset 0x58 (88) */
    const char *deviceID;       /* offset 0x5c (92) */
    unsigned int serialNum;     /* offset 0x60 (96) */
    int csnValue;               /* offset 0x64 (100) */
}
@end

@implementation PnPDeviceResources

+ (void)setReadPort:(unsigned int)port
{
    readPort = (unsigned short)port;
}

+ (void)setVerbose:(int)flag
{
    verbose = (char)flag;
}

- init
{
    [super init];
    deviceNameLen = 0;
    deviceNameBuf[0] = '\0';
    return self;
}

- (int)csn
{
    return csnValue;
}

- (int)deviceCount
{
    return [deviceListObj count];
}

- deviceList
{
    return deviceListObj;
}

- (const char *)deviceName
{
    return deviceNameBuf;
}

- deviceWithID:(const char *)identifier
{
    int i;
    id device;
    const char *devID;

    i = 0;
    while (1) {
        device = [deviceListObj objectAt:i];
        if (device == nil) {
            return nil;
        }

        devID = [device ID];
        if (identifier == devID) {
            return device;
        }

        i++;
    }
    return nil;
}

- free
{
    if (deviceListObj != nil) {
        [[deviceListObj freeObjects:@selector(free)] free];
    }
    return [super free];
}

- (const char *)ID
{
    return deviceID;
}

- initForBuf:(const unsigned char *)buffer Length:(int)length CSN:(int)csn
{
    unsigned int vendorID;
    unsigned int serial;
    char vendorStr[8];
    id listClass;
    extern char verbose;

    [super init];

    /* Check minimum length */
    if (length < 9) {
        printf("PnPDeviceResources: len %d is < START_OFFSET %d\n", length, 9);
        return nil;
    }

    /* Copy vendor ID from first 4 bytes */
    vendorID = *(unsigned int *)buffer;

    /* Set CSN */
    csnValue = csn;

    /* Set ID and serial number */
    [self setID:(const char *)(unsigned long)vendorID];
    serial = *(unsigned int *)(buffer + 4);
    [self setSerialNumber:serial];

    /* Print verbose info if enabled */
    if (verbose == 1) {
        unsigned int id;
        char c1, c2, c3;

        id = (unsigned int)[self ID];
        serial = [self serialNumber];

        /* Decode vendor ID: 3 letters encoded in upper bits */
        c1 = ((id >> 26) & 0x1f) + 0x40;
        c2 = ((id >> 21) & 0x1f) + 0x40;
        c3 = ((id >> 16) & 0x1f) + 0x40;
        sprintf(vendorStr, "%04x", id & 0xffff);
        vendorStr[4] = c1;
        vendorStr[5] = c2;
        vendorStr[6] = c3;
        vendorStr[7] = '\0';

        printf("Vendor Id %s (0x%lx) Serial Number 0x%lx CheckSum 0x%x\n",
               &vendorStr[4], (unsigned long)id, (unsigned long)serial, buffer[8]);
    }

    /* Allocate device list */
    listClass = objc_getClass("List");
    deviceListObj = [[listClass alloc] init];
    if (deviceListObj == nil) {
        printf("PnPDeviceResources: failed to allocate device_list\n");
        [self free];
        return nil;
    }

    /* Parse configuration starting at offset 9 */
    if ([self parseConfig:(buffer + 9) Length:(length - 9)] != 0) {
        return self;
    }

    /* Parse failed, cleanup */
    [self free];
    return nil;
}

- initForBufNoHeader:(const unsigned char *)buffer Length:(int)length CSN:(int)csn
{
    id listClass;

    [super init];

    /* Set CSN */
    csnValue = csn;

    /* Allocate device list */
    listClass = objc_getClass("List");
    deviceListObj = [[listClass alloc] init];
    if (deviceListObj == nil) {
        printf("PnPDeviceResources: failed to allocate device_list\n");
        [self free];
        return nil;
    }

    /* Parse configuration from beginning */
    if ([self parseConfig:buffer Length:length] != 0) {
        return self;
    }

    /* Parse failed, cleanup */
    [self free];
    return nil;
}

- (int)parseConfig:(const unsigned char *)buffer Length:(int)length
{
    const unsigned char *ptr;
    int bytesLeft;
    unsigned char tag;
    unsigned int tagType;
    unsigned int itemLen;
    unsigned short largeLen;
    id logicalDevice;
    int depLevel;
    id depResources;
    unsigned int vendorID;
    char vendorStr[8];
    unsigned char byte;
    int i;
    extern char verbose;
    id memClass, irqClass, dmaClass, portClass, logDevClass, depClass;
    id resourceObj;

    logicalDevice = nil;
    depLevel = 0;
    depResources = nil;
    bytesLeft = length;
    ptr = buffer;

    /* Get class objects */
    memClass = objc_getClass("pnpMemory");
    irqClass = objc_getClass("pnpIRQ");
    dmaClass = objc_getClass("pnpDMA");
    portClass = objc_getClass("pnpIOPort");
    logDevClass = objc_getClass("PnPLogicalDevice");
    depClass = objc_getClass("PnPDependentResources");

    while (bytesLeft > 0) {
        tag = *ptr++;
        bytesLeft--;

        /* Large resource item (bit 7 set) */
        if (tag & 0x80) {
            /* Need at least 2 more bytes for length */
            if (bytesLeft < 2) {
                printf("PnPDeviceResources: bytes left is < 2\n");
                return 0;
            }

            largeLen = *(unsigned short *)ptr;
            ptr += 2;
            bytesLeft -= 2;

            if (bytesLeft < largeLen) {
                printf("PnPDeviceResources: LIN ilen %d > bytes left %d\n", largeLen, bytesLeft);
                return 0;
            }

            tagType = tag & 0x7F;
            switch (tagType) {
            case 1:  /* Memory range 24-bit */
            case 5:  /* Memory range 32-bit */
            case 6:  /* Fixed memory range 32-bit */
                resourceObj = [[memClass alloc] initFrom:ptr Length:largeLen Type:tagType];
                if (resourceObj == nil) {
                    printf("failed to init memory\n");
                    return 0;
                }
                if (depLevel == 0) {
                    [[logicalDevice resources] addMemory:resourceObj];
                } else {
                    [depResources addMemory:resourceObj];
                }
                break;

            case 2:  /* ANSI identifier string */
                if ([self deviceName][0] == '\0') {
                    [self setDeviceName:(const char *)ptr Length:largeLen];
                } else {
                    [logicalDevice setDeviceName:(const char *)ptr Length:largeLen];
                }
                if (verbose == 1) {
                    printf("id string(%d) '", largeLen);
                    for (i = 0; i < largeLen; i++) {
                        printf("%c", ptr[i]);
                    }
                    printf("'\n");
                }
                break;

            case 3:  /* Unicode identifier string */
                if ([self deviceName][0] == '\0') {
                    [self setDeviceName:(const char *)(ptr + 2) Length:(largeLen - 2)];
                } else {
                    [logicalDevice setDeviceName:(const char *)(ptr + 2) Length:(largeLen - 2)];
                }
                if (verbose == 1) {
                    printf("UNICODE id string(%d) '", largeLen);
                    for (i = 0; i < (largeLen - 2); i++) {
                        printf("%c", ptr[2 + i]);
                    }
                    printf("'\n");
                }
                break;

            case 4:  /* Vendor defined */
                if (verbose == 1) {
                    printf("vendor defined(%d bytes)", largeLen);
                    for (i = 0; i < largeLen; i++) {
                        byte = ptr[i];
                        printf(" '%c'[%xh]", (byte >= 0x20 && byte < 0x80) ? byte : '.', byte);
                    }
                    printf(" ]\n");
                }
                break;
            }

            ptr += largeLen;
            bytesLeft -= largeLen;
        }
        /* Small resource item (bit 7 clear) */
        else {
            itemLen = tag & 0x07;
            tagType = (tag >> 3) & 0x0F;

            /* End tag */
            if ((tag & 0x78) == 0x78) {
                return 1;
            }

            if (bytesLeft < itemLen) {
                printf("PnPDeviceResources: bytes left %d, needed %d\n", bytesLeft, itemLen);
                return 0;
            }

            switch (tagType) {
            case 1:  /* PnP version */
                if (verbose == 1) {
                    printf("Plug and Play Version %d.%d (Vendor %d.%d)\n",
                           ptr[0] >> 4, ptr[0] & 0xF, ptr[1] >> 4, ptr[1] & 0xF);
                }
                break;

            case 2:  /* Logical device ID */
                logicalDevice = [[logDevClass alloc] init];
                if (logicalDevice == nil) {
                    printf("PnPDeviceResources: allocate PnPLogicalDevice failed\n");
                    return 0;
                }

                [logicalDevice setLogicalDeviceNumber:[deviceListObj count]];
                [deviceListObj addObject:logicalDevice];

                /* Extract vendor ID from first 4 bytes */
                vendorID = *(unsigned int *)ptr;
                [logicalDevice setID:(const char *)(unsigned long)vendorID];

                if (verbose == 1) {
                    unsigned int id = (unsigned int)[logicalDevice ID];
                    vendorStr[0] = ((id >> 26) & 0x1F) + 0x40;
                    vendorStr[1] = ((id >> 21) & 0x1F) + 0x40;
                    vendorStr[2] = ((id >> 16) & 0x1F) + 0x40;
                    sprintf(&vendorStr[3], "%04x", id & 0xFFFF);
                    vendorStr[7] = '\0';
                    printf("\nLogical Device %d: Id %s (0x%lx)\n",
                           [logicalDevice logicalDeviceNumber], vendorStr, (unsigned long)id);
                }

                /* Check flags */
                if (itemLen > 4) {
                    byte = ptr[4];
                    if ((byte & 1) && verbose == 1) {
                        printf("boot process participation capable\n");
                    }
                    if (byte & 0xFE) {
                        if (verbose == 1) printf("register support:");
                        for (i = 1; i < 8; i++) {
                            if ((byte >> i) & 1) {
                                if (verbose == 1) printf(" 0x%x", 0x30 + i);
                            }
                        }
                        if (verbose == 1) printf("\n");
                    }
                }

                if (itemLen > 5) {
                    byte = ptr[5];
                    if (byte != 0) {
                        if (verbose == 1) printf("register support:");
                        for (i = 0; i < 8; i++) {
                            if ((byte >> i) & 1) {
                                if (verbose == 1) printf(" 0x%x", 0x38 + i);
                            }
                        }
                        if (verbose == 1) printf("\n");
                    }
                }
                break;

            case 3:  /* Compatible device ID */
                vendorID = *(unsigned int *)ptr;
                if (verbose == 1) {
                    vendorStr[0] = ((vendorID >> 26) & 0x1F) + 0x40;
                    vendorStr[1] = ((vendorID >> 21) & 0x1F) + 0x40;
                    vendorStr[2] = ((vendorID >> 16) & 0x1F) + 0x40;
                    sprintf(&vendorStr[3], "%04x", vendorID & 0xFFFF);
                    vendorStr[7] = '\0';
                    printf("Compatible Device Id: %s (0x%lx)\n", vendorStr, (unsigned long)vendorID);
                }
                [logicalDevice addCompatID:(const char *)(unsigned long)vendorID];
                break;

            case 4:  /* IRQ format */
                resourceObj = [[irqClass alloc] initFrom:ptr Length:itemLen];
                if (resourceObj == nil) {
                    printf("PnPDeviceResources: failed to parse IRQ\n");
                    return 0;
                }
                if (depLevel == 0) {
                    [[logicalDevice resources] addIRQ:resourceObj];
                } else {
                    [depResources addIRQ:resourceObj];
                }
                break;

            case 5:  /* DMA format */
                resourceObj = [[dmaClass alloc] initFrom:ptr Length:itemLen];
                if (resourceObj == nil) {
                    printf("PnPDeviceResources: failed to parse DMA\n");
                    return 0;
                }
                if (depLevel == 0) {
                    [[logicalDevice resources] addDMA:resourceObj];
                } else {
                    [depResources addDMA:resourceObj];
                }
                break;

            case 6:  /* Start dependent functions */
                if (verbose == 1) {
                    printf("Start dependent function %d ", depLevel);
                }
                depLevel++;

                depResources = [[depClass alloc] init];
                if (depResources == nil) {
                    printf("PnPDeviceResources: failed to alloc depResources\n");
                    return 0;
                }

                [[logicalDevice resources] markStartDependentResources];
                [[logicalDevice depResources] addObject:depResources];
                [depResources setGoodConfig:1];

                if (itemLen != 0) {
                    byte = ptr[0];
                    if (byte == 0) {
                        if (verbose == 1) printf("[good configuration]");
                    } else if (byte == 1) {
                        if (verbose == 1) printf("[acceptable configuration]");
                    } else if (byte == 2) {
                        [depResources setGoodConfig:0];
                        if (verbose == 1) printf("[suboptimal configuration]");
                    }
                }
                if (verbose == 1) printf("\n");
                break;

            case 7:  /* End dependent functions */
                if (verbose == 1) {
                    printf("End of dependent functions\n");
                }
                depLevel = 0;
                depResources = nil;
                break;

            case 8:  /* I/O port descriptor */
            case 9:  /* Fixed I/O port descriptor */
                resourceObj = [[portClass alloc] initFrom:ptr Length:itemLen Type:tagType];
                if (resourceObj == nil) {
                    printf("PnPDeviceResources: failed to parse ioPort\n");
                    return 0;
                }
                if (depLevel == 0) {
                    [[logicalDevice resources] addIOPort:resourceObj];
                } else {
                    [depResources addIOPort:resourceObj];
                }
                break;

            case 0xE:  /* Vendor defined */
                if (verbose == 1) {
                    printf("vendor defined(%d bytes)[", itemLen);
                    for (i = 0; i < itemLen; i++) {
                        byte = ptr[i];
                        printf(" '%c'[%xh]", (byte >= 0x20 && byte < 0x80) ? byte : '.', byte);
                    }
                    printf(" ]\n");
                }
                break;
            }

            ptr += itemLen;
            bytesLeft -= itemLen;
        }
    }

    return 1;
}

- (unsigned int)serialNumber
{
    return serialNum;
}

- setDeviceName:(const char *)name Length:(int)length
{
    size_t copyLen;

    /* Only set if not already set */
    if (deviceNameLen == 0) {
        /* Limit to 79 bytes (leave room for null terminator) */
        copyLen = (length < 79) ? length : 79;
        deviceNameLen = copyLen;

        /* Copy name to buffer */
        strncpy(deviceNameBuf, name, copyLen);

        /* Null terminate */
        deviceNameBuf[deviceNameLen] = '\0';

        return (id)1;
    }

    return (id)0;
}

- setID:(const char *)identifier
{
    deviceID = identifier;
    return self;
}

- setSerialNumber:(unsigned int)serial
{
    serialNum = serial;
    return self;
}

@end

/* PnPLogicalDevice stubs */

@interface PnPLogicalDevice : Object
{
    char deviceNameBuf[80];     /* offset 4 (0x04) to 83 (0x53) */
    size_t deviceNameLen;       /* offset 0x54 (84) */
    const char *deviceID;       /* offset 0x58 (88) */
    id compatIDsList;           /* offset 0x5c (92) - List of compatible IDs */
    id resourcesObj;            /* offset 0x60 (96) - PnPResources */
    id depResourcesList;        /* offset 0x64 (100) - List of dependent resources */
    int logicalDevNum;          /* offset 0x68 (104) */
}
@end

@implementation PnPLogicalDevice

- init
{
    id listClass, resClass;

    [super init];

    /* Allocate PnPResources */
    resClass = objc_getClass("PnPResources");
    resourcesObj = [[resClass alloc] init];

    /* Allocate depResources list */
    listClass = objc_getClass("List");
    depResourcesList = [[listClass alloc] init];

    /* Allocate compatIDs list */
    compatIDsList = [[listClass alloc] init];

    deviceNameLen = 0;
    deviceNameBuf[0] = '\0';
    logicalDevNum = 0;

    return self;
}

- free
{
    /* Free resources */
    [resourcesObj free];

    /* Free depResources list and its objects */
    [[depResourcesList freeObjects:@selector(free)] free];

    /* Free compatIDs list */
    [compatIDsList free];

    return [super free];
}

- (const char *)deviceName
{
    return deviceNameBuf;
}

- setDeviceName:(const char *)name Length:(int)length
{
    size_t copyLen;

    /* Only set if not already set */
    if (deviceNameLen == 0) {
        /* Limit to 79 bytes (leave room for null terminator) */
        copyLen = (length < 79) ? length : 79;
        deviceNameLen = copyLen;

        /* Copy name to buffer */
        strncpy(deviceNameBuf, name, copyLen);

        /* Null terminate */
        deviceNameBuf[deviceNameLen] = '\0';

        return (id)1;
    }

    return (id)0;
}

- (const char *)ID
{
    return deviceID;
}

- setID:(const char *)identifier
{
    deviceID = identifier;
    return self;
}

- (int)logicalDeviceNumber
{
    return logicalDevNum;
}

- setLogicalDeviceNumber:(int)devNum
{
    logicalDevNum = devNum;
    return self;
}

- addCompatID:(const char *)identifier
{
    [compatIDsList addObject:(id)identifier];
    return self;
}

- compatIDs
{
    return compatIDsList;
}

- resources
{
    return resourcesObj;
}

- depResources
{
    return depResourcesList;
}

@end

/* PnPResource stubs */

@interface PnPResource : Object
{
    id listObj;         /* offset 4 */
    int depStart;       /* offset 8 */
}
@end

@implementation PnPResource

- init
{
    id listClass;

    [super init];

    /* Allocate list */
    listClass = objc_getClass("List");
    listObj = [[listClass alloc] init];

    /* Initialize depStart */
    depStart = 0;

    /* If list allocation failed, free and return nil */
    if (listObj == nil) {
        return [self free];
    }

    return self;
}

- free
{
    /* Free all objects in list, then free the list itself */
    [[listObj freeObjects:@selector(free)] free];

    return [super free];
}

- list
{
    return listObj;
}

- (int)matches:(id)config Using:(id)dep
{
    id configList;
    int count;
    int i;
    id ourObject;
    id configObject;
    int match;

    /* Get config resource list */
    configList = [config list];
    count = [configList count];

    /* If no resources to match, return true */
    if (count == 0) {
        return 1;
    }

    /* Check each resource */
    i = 0;
    while (1) {
        /* Get our resource (using dependent fallback) */
        ourObject = [self objectAt:i Using:dep];
        if (ourObject == nil) {
            break;
        }

        /* Get config resource to match against */
        configObject = [configList objectAt:i];

        /* Check if they match */
        match = [ourObject matches:configObject];
        if (match == 0) {
            return 0;
        }

        i++;
    }

    /* Return true if we processed at least one item */
    return (i > 0) ? 1 : 0;
}

- objectAt:(int)index Using:(id)other
{
    id otherList;
    int otherCount;

    /* Get count from the "other" resource */
    otherList = [other list];
    otherCount = [otherList count];

    /* If index is in dependent range */
    if (index >= depStart) {
        /* If index falls within the dependent resource range */
        if (index < (otherCount + depStart)) {
            /* Return object from "other" resource at adjusted index */
            return [otherList objectAt:(index - depStart)];
        }

        /* Index is past dependent resources - adjust for the inserted dependent items */
        return [listObj objectAt:(otherCount + depStart + index)];
    }

    /* Index is before dependent start - return from our list */
    return [listObj objectAt:index];
}

- (void)setDepStart:(int)start
{
    depStart = start;
}

@end

/* PnPResources stubs */

@interface PnPResources : Object
{
    id _irq;        /* offset 4 - PnPResource for IRQs */
    id _dma;        /* offset 8 - PnPResource for DMAs */
    id _port;       /* offset 12 (0xc) - PnPResource for I/O ports */
    id _memory;     /* offset 16 (0x10) - PnPResource for memory */
}
@end

@implementation PnPResources

- init
{
    id resClass;

    [super init];

    /* Allocate resource containers */
    resClass = objc_getClass("PnPResource");
    _irq = [[resClass alloc] init];
    _dma = [[resClass alloc] init];
    _port = [[resClass alloc] init];
    _memory = [[resClass alloc] init];

    /* If any allocation failed, free and return nil */
    if ((_irq == nil) || (_dma == nil) || (_port == nil) || (_memory == nil)) {
        return [self free];
    }

    return self;
}

- free
{
    [_irq free];
    [_dma free];
    [_port free];
    [_memory free];

    return [super free];
}

- addDMA:(id)dma
{
    id list = [_dma list];
    [list addObject:dma];
    return self;
}

- addIOPort:(id)port
{
    id list = [_port list];
    [list addObject:port];
    return self;
}

- addIRQ:(id)irq
{
    id list = [_irq list];
    [list addObject:irq];
    return self;
}

- addMemory:(id)memory
{
    id list = [_memory list];
    [list addObject:memory];
    return self;
}

- dma
{
    return _dma;
}

- irq
{
    return _irq;
}

- memory
{
    return _memory;
}

- port
{
    return _port;
}

- initFromRegisters:(void *)registers
{
    unsigned char *regs = (unsigned char *)registers;
    int i;
    unsigned short portBase;
    unsigned char irqNum, irqFlags;
    unsigned char dmaChannel;
    unsigned int memBase24, memControl24, memLimit24;
    unsigned int memBase32, memControl32, memLimit32;
    unsigned int length;
    id portObj, irqObj, dmaObj, memObj;
    id memList;
    int memCount;
    id portClass, irqClass, dmaClass, memClass;
    extern char verbose;

    /* Initialize */
    if ([self init] == nil) {
        return nil;
    }

    /* Get class objects */
    portClass = objc_getClass("pnpIOPort");
    irqClass = objc_getClass("pnpIRQ");
    dmaClass = objc_getClass("pnpDMA");
    memClass = objc_getClass("pnpMemory");

    /* Parse I/O ports (8 slots at offset 0x38) */
    for (i = 0; i < 8; i++) {
        portBase = (regs[0x38 + i*2] << 8) | regs[0x39 + i*2];

        if (portBase != 0) {
            portObj = [[portClass alloc] initWithBase:portBase Length:0];
            if (portObj == nil) {
                return [self free];
            }

            [self addIOPort:portObj];

            if (verbose != 0) {
                [portObj print];
            }
        }
    }

    /* Parse IRQs (2 slots at offset 0x48) */
    for (i = 0; i < 2; i++) {
        irqNum = regs[0x48 + i*2];

        /* IRQ 2 redirects to IRQ 9 */
        if (irqNum == 2) {
            irqNum = 9;
        }

        irqFlags = regs[0x49 + i*2];

        if (irqNum != 0) {
            irqObj = [[irqClass alloc] init];
            if (irqObj == nil) {
                return [self free];
            }

            [irqObj addToIRQList:(id)(unsigned long)irqNum];
            [irqObj setHigh:(irqFlags & 2) Level:(irqFlags & 1)];
            [self addIRQ:irqObj];

            if (verbose != 0) {
                [irqObj print];
            }
        }
    }

    /* Parse DMA channels (2 slots at offset 0x4c) */
    for (i = 0; i < 2; i++) {
        dmaChannel = regs[0x4c + i];

        if (dmaChannel != 4) {
            dmaObj = [[dmaClass alloc] init];
            if (dmaObj == nil) {
                return [self free];
            }

            [dmaObj addDMAToList:(id)(unsigned long)dmaChannel];
            [self addDMA:dmaObj];

            if (verbose != 0) {
                [dmaObj print];
            }
        }
    }

    /* Parse 24-bit memory (4 slots at offset 0x0) */
    for (i = 0; i < 4; i++) {
        memBase24 = (regs[i*5 + 0] << 16) | (regs[i*5 + 1] << 8);

        if (memBase24 != 0) {
            memControl24 = regs[i*5 + 2];
            memLimit24 = (regs[i*5 + 3] << 16) | (regs[i*5 + 4] << 8);

            /* Calculate length */
            length = 0;
            if (memLimit24 != 0) {
                if ((memControl24 & 1) == 0) {
                    /* Range length mode - invert and add 1 */
                    length = ((memLimit24 ^ 0xFFFFFF) + 1);
                } else {
                    /* High address decode mode - subtract base from limit */
                    length = memLimit24 - memBase24;
                }
            }

            memObj = [[memClass alloc] initWithBase:memBase24
                                            Length:length
                                             Bit16:(memControl24 & 2)
                                             Bit32:0
                                          HighAddr:(memControl24 & 1)
                                              Is32:0];
            if (memObj == nil) {
                return [self free];
            }

            [self addMemory:memObj];

            if (verbose != 0) {
                [memObj print];
            }
        }
    }

    /* Check if we already have 32-bit memory */
    memList = [_memory list];
    memCount = [memList count];

    if (memCount == 0) {
        /* Parse 32-bit memory (4 slots at offset 0x14) */
        for (i = 0; i < 4; i++) {
            memBase32 = (regs[0x14 + i*9] << 24) | (regs[0x15 + i*9] << 16) |
                        (regs[0x16 + i*9] << 8) | regs[0x17 + i*9];

            if (memBase32 != 0) {
                memControl32 = regs[0x18 + i*9];
                memLimit32 = (regs[0x19 + i*9] << 24) | (regs[0x1a + i*9] << 16) |
                             (regs[0x1b + i*9] << 8) | regs[0x1c + i*9];

                /* Calculate length */
                length = 0;
                if (memLimit32 != 0) {
                    if ((memControl32 & 1) == 0) {
                        /* Range length mode - negate */
                        length = (~memLimit32 + 1);
                    } else {
                        /* High address decode mode - subtract base from limit */
                        length = memLimit32 - memBase32;
                    }
                }

                memObj = [[memClass alloc] initWithBase:memBase32
                                                Length:length
                                                 Bit16:(memControl32 & 2)
                                                 Bit32:(memControl32 & 4)
                                              HighAddr:(memControl32 & 1)
                                                  Is32:1];

                [self addMemory:memObj];

                if (verbose != 0) {
                    [memObj print];
                }
            }
        }
    }

    return self;
}

- (void)markStartDependentResources
{
    int count;
    id list;

    /* Set IRQ dependent start */
    list = [_irq list];
    count = [list count];
    [_irq setDepStart:count];

    /* Set DMA dependent start */
    list = [_dma list];
    count = [list count];
    [_dma setDepStart:count];

    /* Set port dependent start */
    list = [_port list];
    count = [list count];
    [_port setDepStart:count];

    /* Set memory dependent start */
    list = [_memory list];
    count = [list count];
    [_memory setDepStart:count];
}

- (void)print
{
    id resourceContainers[4];
    id list;
    int i, j;
    id resource;

    /* Setup array for iteration (port, IRQ, memory, DMA) */
    resourceContainers[0] = _port;
    resourceContainers[1] = _irq;
    resourceContainers[2] = _memory;
    resourceContainers[3] = _dma;

    /* Print each resource type */
    for (i = 0; i < 4; i++) {
        list = [resourceContainers[i] list];

        /* Print each resource in this type */
        j = 0;
        while (1) {
            resource = [list objectAt:j];
            if (resource == nil) {
                break;
            }

            [resource print];
            j++;
        }
    }
}

@end

/* pnpDMA stubs */

@interface pnpDMA : Object
{
    unsigned int dmaChannelList[8];  /* offset 4-35: array of DMA channels */
    int channelCount;                /* offset 0x24 (36): number of channels */
    unsigned char width8bit;         /* offset 0x28 (40): 8-bit transfer */
    unsigned char width16bit;        /* offset 0x29 (41): 16-bit transfer */
    unsigned char busMaster;         /* offset 0x2a (42): bus master */
    unsigned char byteMode;          /* offset 0x2b (43): byte mode */
    unsigned char wordCount;         /* offset 0x2c (44): word count */
    unsigned char speed;             /* offset 0x2d (45): speed */
}
@end

@implementation pnpDMA

- init
{
    [super init];
    channelCount = 0;
    return self;
}

- initFrom:(const unsigned char *)data Length:(int)length
{
    unsigned char channelMask;
    unsigned char flags;
    int i;
    extern char verbose;

    [super init];

    /* Read channel bitmask */
    channelMask = data[0];

    /* Add each channel that has its bit set */
    for (i = 0; i < 8; i++) {
        if ((channelMask >> i) & 1) {
            dmaChannelList[channelCount] = i;
            channelCount++;
        }
    }

    /* Read flags byte if present */
    if (length > 1) {
        flags = data[1];

        /* Bits 0-1: Transfer width */
        switch (flags & 0x03) {
        case 0:  /* 8-bit only */
            width8bit = 1;
            width16bit = 0;
            break;
        case 1:  /* 8 and 16-bit */
            width8bit = 1;
            width16bit = 1;
            break;
        case 2:  /* 16-bit only */
            width8bit = 0;
            width16bit = 1;
            break;
        }

        /* Bit 2: Bus master */
        busMaster = (flags >> 2) & 1;

        /* Bit 3: Byte mode */
        byteMode = (flags >> 3) & 1;

        /* Bit 4: Word count */
        wordCount = (flags >> 4) & 1;

        /* Bits 5-6: Speed */
        speed = (flags >> 5) & 3;
    }

    if (verbose != 0) {
        [self print];
    }

    return self;
}

- addDMAToList:(id)channel
{
    if (channelCount < 8) {
        dmaChannelList[channelCount] = (unsigned int)(unsigned long)channel;
        channelCount++;
    }
    return self;
}

- (unsigned int *)dmaChannels
{
    return dmaChannelList;
}

- (int)channelCount
{
    return channelCount;
}

- (int)number
{
    return channelCount;
}

- (int)matches:(id)other
{
    int otherCount;
    int i;
    unsigned int *otherChannels;

    /* Get number of channels in other */
    otherCount = [other number];

    if (otherCount == 0) {
        return 0;
    }

    /* Can only match if other has exactly 1 channel */
    if (otherCount != 1) {
        printf("pnpDMA: can only match one DMA\n");
        return 0;
    }

    /* Check if any of our channels matches the other's single channel */
    otherChannels = [other dmaChannels];
    for (i = 0; i < channelCount; i++) {
        if (dmaChannelList[i] == otherChannels[0]) {
            return 1;
        }
    }

    return 0;
}

- (void)print
{
    int i;
    int first = 1;
    const char *speedStr;

    printf("dma channel: ");

    /* Print channel list */
    for (i = 0; i < channelCount; i++) {
        if (first) {
            printf("%d", dmaChannelList[i]);
            first = 0;
        } else {
            printf(", %d", dmaChannelList[i]);
        }
    }

    printf(" ");

    /* Print capabilities */
    if (width8bit) {
        printf("[8 bit]");
    }
    if (width16bit) {
        printf("[16 bit]");
    }

    /* These are always printed in the decompiled code */
    printf("[bus master]");
    printf("[byte]");
    printf("[word]");

    /* Print speed */
    switch (speed) {
    case 0:
        speedStr = "[compat]";
        break;
    case 1:
        speedStr = "[type A]";
        break;
    case 2:
        speedStr = "[type B]";
        break;
    case 3:
        speedStr = "[type F]";
        break;
    default:
        speedStr = NULL;
        break;
    }

    if (speedStr != NULL) {
        printf("%s", speedStr);
    }

    printf("\n");
}

@end

/* pnpIOPort stubs */

@interface pnpIOPort : Object
{
    unsigned short minBase;        /* offset 4 - minimum base address */
    unsigned short maxBase;        /* offset 6 - maximum base address */
    unsigned short alignment;      /* offset 8 - alignment */
    unsigned short length;         /* offset 10 - length */
    unsigned char linesDecoded;    /* offset 0xc - lines decoded (10 or 16 bit) */
}
@end

@implementation pnpIOPort

- init
{
    [super init];
    return self;
}

- initWithBase:(unsigned short)base Length:(unsigned short)len
{
    [super init];
    minBase = base;
    maxBase = base;
    length = len;
    return self;
}

- initFrom:(const unsigned char *)data Length:(int)dataLen Type:(int)type
{
    unsigned char infoByte;
    unsigned short baseAddr;
    unsigned char alignByte;
    extern char verbose;

    [super init];

    if (type == 8) {
        /* I/O port descriptor - 7 bytes */
        if (dataLen != 7) {
            printf("PnPDeviceResources: ioport length is %d, should be 7\n", dataLen);
            return [self free];
        }

        infoByte = data[0];
        minBase = (data[1] | (data[2] << 8));
        maxBase = (data[3] | (data[4] << 8));
        length = data[6];
        alignByte = data[5];
        alignment = alignByte;

        /* If alignment is 0, use length as alignment */
        if (alignByte == 0) {
            alignment = length;
        }

        /* Decode type: bit 0 = 0 means 10-bit, 1 means 16-bit */
        if ((infoByte & 1) == 0) {
            linesDecoded = 10;
        } else {
            linesDecoded = 16;
        }

        if (verbose != 0) {
            [self print];
        }
    }
    else if (type == 9) {
        /* Fixed I/O port descriptor - 3 bytes */
        if (dataLen != 3) {
            printf("PnPDeviceResources: ioport length is %d, should be 3\n", dataLen);
            return [self free];
        }

        baseAddr = (data[0] | (data[1] << 8));
        minBase = baseAddr & 0x3FF;  /* 10-bit address */
        maxBase = baseAddr & 0x3FF;
        length = data[2];
        alignment = data[2];
        linesDecoded = 10;

        if (verbose != 0) {
            printf("fixed ");
            [self print];
        }
    }

    return self;
}

- (unsigned short)min_base
{
    return minBase;
}

- (unsigned short)max_base
{
    return maxBase;
}

- (unsigned short)alignment
{
    return alignment;
}

- (unsigned short)length
{
    return length;
}

- (unsigned char)lines_decoded
{
    return linesDecoded;
}

- (int)matches:(id)other
{
    unsigned short otherMinBase;
    unsigned short alignedBase;

    /* Get other's min base */
    otherMinBase = [other min_base];

    /* Calculate aligned base address */
    if (alignment != 0) {
        alignedBase = alignment * (((alignment - 1) + otherMinBase) / alignment);
    } else {
        alignedBase = otherMinBase;
    }

    /* Check if other's base equals aligned base and is in our range */
    if ((otherMinBase == alignedBase) &&
        (minBase <= otherMinBase) &&
        (otherMinBase <= maxBase)) {
        return 1;
    }

    return 0;
}

- (void)print
{
    printf("i/o port: 0x%x..0x%x align 0x%x length 0x%x [%d lines]\n",
           minBase, maxBase, alignment, length, linesDecoded);
}

@end

/* pnpIRQ stubs */

@interface pnpIRQ : Object
{
    unsigned int irqList[16];      /* offset 4-67: array of IRQ numbers */
    int irqCount;                  /* offset 0x44 (68): number of IRQs */
    unsigned char highEdge;        /* offset 0x48 (72): high, edge triggered */
    unsigned char lowEdge;         /* offset 0x49 (73): low, edge triggered */
    unsigned char highLevel;       /* offset 0x4a (74): high, level triggered */
    unsigned char lowLevel;        /* offset 0x4b (75): low, level triggered */
}
@end

@implementation pnpIRQ

- init
{
    [super init];
    irqCount = 0;
    return self;
}

- initFrom:(const unsigned char *)data Length:(int)length
{
    unsigned short irqMask;
    unsigned char flags;
    int i;
    extern char verbose;

    [super init];

    irqCount = 0;

    /* Read IRQ bitmask (2 bytes, little endian) */
    irqMask = data[0] | (data[1] << 8);

    /* Add each IRQ that has its bit set */
    for (i = 0; i < 16; i++) {
        if ((irqMask >> i) & 1) {
            irqList[irqCount] = i;
            irqCount++;
        }
    }

    /* Default to level triggered */
    highLevel = 1;

    /* Read flags byte if present (length > 2) */
    if (length > 2) {
        flags = data[2];

        /* Clear default */
        highLevel = 0;

        /* Bit 0: Level (1) vs Edge (0) */
        /* Bit 1: High (1) vs Low (0) */
        if (flags & 1) {
            /* Level triggered */
            if ((flags >> 1) & 1) {
                highLevel = 1;
            } else {
                lowLevel = 1;
            }
        } else {
            /* Edge triggered */
            if ((flags >> 1) & 1) {
                highEdge = 1;
            } else {
                lowEdge = 1;
            }
        }
    }

    if (verbose != 0) {
        [self print];
    }

    return self;
}

- addToIRQList:(id)irq
{
    if (irqCount < 16) {
        irqList[irqCount] = (unsigned int)(unsigned long)irq;
        irqCount++;
    }
    return self;
}

- setHigh:(unsigned char)highFlag Level:(unsigned char)levelFlag
{
    /* Clear all flags */
    highEdge = 0;
    lowEdge = 0;
    highLevel = 0;
    lowLevel = 0;

    /* Set the appropriate flag based on combination */
    if (highFlag) {
        if (levelFlag) {
            highLevel = 1;  /* High, level */
        } else {
            highEdge = 1;   /* High, edge */
        }
    } else {
        if (levelFlag) {
            lowLevel = 1;   /* Low, level */
        } else {
            lowEdge = 1;    /* Low, edge */
        }
    }

    return self;
}

- (unsigned int *)irqs
{
    return irqList;
}

- (int)number
{
    return irqCount;
}

- (int)matches:(id)other
{
    int otherCount;
    int i;
    unsigned int *otherIRQs;

    /* Get number of IRQs in other */
    otherCount = [other number];

    if (otherCount == 0) {
        return 0;
    }

    /* Can only match if other has exactly 1 IRQ */
    if (otherCount != 1) {
        printf("pnpIRQ: can only match one IRQ\n");
        return 0;
    }

    /* Check if any of our IRQs matches the other's single IRQ */
    otherIRQs = [other irqs];
    for (i = 0; i < irqCount; i++) {
        if (irqList[i] == otherIRQs[0]) {
            return 1;
        }
    }

    return 0;
}

- (void)print
{
    int i;
    int first = 1;

    printf("irq: ");

    /* Print IRQ list */
    for (i = 0; i < irqCount; i++) {
        if (first) {
            printf("%d", irqList[i]);
            first = 0;
        } else {
            printf(", %d", irqList[i]);
        }
    }

    /* Print trigger/polarity combinations */
    if (highEdge) {
        printf(" [high, edge]");
    }
    if (lowEdge) {
        printf(" [low, edge]");
    }
    if (highLevel) {
        printf(" [high, level]");
    }
    if (lowLevel) {
        printf(" [low, level]");
    }

    printf("\n");
}

@end

/* pnpMemory stubs */

@interface pnpMemory : Object
{
    unsigned int minBase;          /* offset 4 - minimum base address */
    unsigned int maxBase;          /* offset 8 - maximum base address */
    unsigned int alignment;        /* offset 0xc (12) - alignment */
    unsigned int length;           /* offset 0x10 (16) - length */
    unsigned char writeable;       /* offset 0x14 (20) - writeable */
    unsigned char cacheable;       /* offset 0x15 (21) - cacheable */
    unsigned char highAddr;        /* offset 0x16 (22) - high address decode */
    unsigned char rangeLength;     /* offset 0x17 (23) - range length */
    unsigned char shadowable;      /* offset 0x18 (24) - shadowable */
    unsigned char bit8;            /* offset 0x19 (25) - 8-bit access */
    unsigned char bit16;           /* offset 0x1a (26) - 16-bit access */
    unsigned char bit32;           /* offset 0x1b (27) - 32-bit access */
    unsigned char is32;            /* offset 0x1c (28) - 32-bit memory */
}
@end

@implementation pnpMemory

- init
{
    [super init];
    return self;
}

- initWithBase:(unsigned int)base Length:(unsigned int)len Bit16:(unsigned char)b16 Bit32:(unsigned char)b32 HighAddr:(unsigned char)ha Is32:(unsigned char)i32
{
    [super init];
    minBase = base;
    maxBase = base;
    length = len;
    bit8 = (b16 == 0);  /* Set to opposite of bit16 */
    bit16 = b16;
    bit32 = b32;
    highAddr = ha;
    is32 = i32;
    return self;
}

- initFrom:(const unsigned char *)data Length:(int)dataLen Type:(int)type
{
    unsigned short value16;
    unsigned int value32;
    extern char verbose;

    [super init];

    /* Initialize all bit flags to 0 */
    bit8 = 0;
    bit16 = 0;
    bit32 = 0;
    is32 = 0;

    if (type == 5) {
        /* 32-bit memory range descriptor */
        is32 = 1;

        if (dataLen != 17) {
            printf("PnPDeviceResources: 32BIT_MEMORY_RANGE ilen is %d, should be 17\n", dataLen);
            return [self free];
        }

        [self setControl:data[0]];
        minBase = data[1] | (data[2] << 8) | (data[3] << 16) | (data[4] << 24);
        maxBase = data[5] | (data[6] << 8) | (data[7] << 16) | (data[8] << 24);
        length = data[13] | (data[14] << 8) | (data[15] << 16) | (data[16] << 24);
        alignment = data[9] | (data[10] << 8) | (data[11] << 16) | (data[12] << 24);

        if (alignment == 0) {
            alignment = length;
        }
    }
    else if (type == 6) {
        /* 32-bit fixed memory descriptor */
        is32 = 1;

        if (dataLen != 9) {
            printf("PnPDeviceResources: 32BIT_FIXED_MEMORY ilen is %d, should be 9\n", dataLen);
            return [self free];
        }

        [self setControl:data[0]];
        value32 = data[1] | (data[2] << 8) | (data[3] << 16) | (data[4] << 24);
        minBase = value32;
        maxBase = value32;
        value32 = data[5] | (data[6] << 8) | (data[7] << 16) | (data[8] << 24);
        length = value32;
        alignment = value32;

        if (verbose != 0) {
            printf("fixed ");
            [self print];
        }
    }
    else if (type == 1) {
        /* 24-bit memory range descriptor */
        if (dataLen != 9) {
            printf("PnPDeviceResources: MEMORY_RANGE ilen is %d, should be 3\n", dataLen);
            return [self free];
        }

        [self setControl:data[0]];
        minBase = ((data[1] | (data[2] << 8)) << 8);
        maxBase = ((data[3] | (data[4] << 8)) << 8);
        value16 = data[5] | (data[6] << 8);
        alignment = value16;

        if (value16 == 0) {
            alignment = 0x10000;
        }

        length = ((data[7] | (data[8] << 8)) << 8);
    }

    if (verbose != 0) {
        [self print];
    }

    return self;
}

- setControl:(unsigned char)control
{
    unsigned char widthBits;

    /* Decode control byte for memory characteristics */

    /* Bits 3-4: Memory width */
    widthBits = (control >> 3) & 3;
    switch (widthBits) {
    case 1:
        /* 16-bit only */
        bit16 = 1;
        break;
    case 2:
        /* 8 and 16-bit */
        bit16 = 1;
        /* Fall through to set bit8 */
    case 0:
        bit8 = 1;
        break;
    case 3:
        /* 32-bit */
        bit32 = 1;
        break;
    }

    /* Decode other control bits */
    writeable = (control >> 6) & 1;    /* Bit 6: Expansion ROM capable */
    cacheable = (control >> 5) & 1;    /* Bit 5: Shadowable */
    highAddr = (control >> 2) & 1;     /* Bit 2: High address decode */
    rangeLength = (control >> 1) & 1;  /* Bit 1: Range length */
    shadowable = control & 1;          /* Bit 0: Writeable (RAM vs ROM) */

    return self;
}

- (unsigned int)alignment
{
    return alignment;
}

- (int)bit8
{
    return (int)bit8;
}

- (int)bit16
{
    return (int)bit16;
}

- (int)bit32
{
    return (int)bit32;
}

- (int)highAddressDecode
{
    return (int)highAddr;
}

- (int)is32
{
    return (int)is32;
}

- (unsigned int)length
{
    return length;
}

- (int)matches:(id)other
{
    pnpMemory *otherMem;
    unsigned int otherMin, otherMax, otherAlign, otherLen;
    unsigned int alignMask;
    unsigned int testBase;

    if (other == nil) {
        return 0;
    }

    otherMem = (pnpMemory *)other;
    otherMin = [otherMem min_base];
    otherMax = [otherMem max_base];
    otherAlign = [otherMem alignment];
    otherLen = [otherMem length];

    /* Check if length requirement can be satisfied */
    if (otherLen > length) {
        return 0;
    }

    /* Check alignment constraints */
    if (otherAlign != 0) {
        alignMask = otherAlign - 1;

        /* Test if minBase satisfies alignment */
        if ((minBase & alignMask) == 0) {
            /* minBase is aligned, check if it's within acceptable range */
            if (minBase >= otherMin && minBase <= otherMax) {
                return 1;
            }
        }

        /* Find next aligned address >= otherMin */
        testBase = (otherMin + alignMask) & ~alignMask;

        /* Check if aligned address is within range */
        if (testBase >= minBase && testBase <= maxBase && testBase <= otherMax) {
            return 1;
        }
    }

    return 0;
}

- (unsigned int)max_base
{
    return maxBase;
}

- (unsigned int)min_base
{
    return minBase;
}

- (void)print
{
    char *memType;

    /* Print memory type based on is32 flag */
    if (is32 == 0) {
        memType = "24";
    } else {
        memType = "32";
    }

    printf("mem%s: 0x%lx..0x%lx align 0x%lx len 0x%lx ", memType, minBase, maxBase, alignment, length);

    /* Print bit width flags */
    if (bit8 != 0) {
        printf("[8-bit]");
    }

    if (bit16 != 0) {
        printf("[16-bit]");
    }

    if (bit32 != 0) {
        printf("[32-bit]");
    }

    /* Print memory characteristics */
    if (writeable != 0) {
        printf("[expROM]");
    }

    if (cacheable != 0) {
        printf("[shadow]");
    }

    if (highAddr == 0) {
        printf("[range]");
    } else {
        printf("[hi addr]");
    }

    if (shadowable == 0) {
        printf("[ROM]");
    }

    printf("\n");
}

@end

/* C function implementations */

/*
 * IOMalloc
 * Allocate memory
 */
void *IOMalloc(unsigned int size)
{
    return malloc(size);
}

/*
 * IOFree
 * Free memory
 */
void IOFree(void *ptr, unsigned int size)
{
    free(ptr);
}

/*
 * IOLog
 * Log a message using syslog
 */
void IOLog(const char *format, ...)
{
    char buffer[300];
    va_list args;

    /* Get variadic arguments */
    va_start(args, format);

    /* Format the message */
    vsprintf(buffer, format, args);

    /* Clean up va_list */
    va_end(args);

    /* Log to syslog with priority 3 (LOG_ERR) */
    syslog(3, "%s", buffer);
}

/*
 * IOGetTimestamp
 * Get current timestamp in nanoseconds
 */
void IOGetTimestamp(unsigned int *timestamp)
{
    unsigned long long kern_ts;
    unsigned int ts_low;
    int ts_high;
    int temp;

    /* Get kernel timestamp as 64-bit value */
    kern_timestamp(&kern_ts);
    ts_low = (unsigned int)kern_ts;
    ts_high = (int)(kern_ts >> 32);

    /* Complex calculation to convert to nanoseconds */
    /* This is essentially: timestamp = ts * 1000 (to get nanoseconds) */
    /* The decompiled code shows multiplication by 1000 split into smaller operations */
    temp = (ts_high * 4 | ts_low >> 30) + ts_high + ((ts_low * 4 < ts_low) ? 1 : 0);
    temp = temp + (temp * 4 | (ts_low * 5) >> 30) + ((ts_low * 5 < ts_low * 20) ? 1 : 0);

    timestamp[0] = ts_low * 1000;
    timestamp[1] = ((temp * 4 | (ts_low * 25) >> 30) + temp +
                   ((ts_low * 100 < ts_low * 25) ? 1 : 0)) * 8 | (ts_low * 125) >> 29;
}

/*
 * IOInitGeneralFuncs
 * Initialize general I/O functions and callout chain
 */
void IOInitGeneralFuncs(void)
{
    Class nxLockClass;
    int result;
    CalloutEntry **chainTail;

    /* Initialize callout chain as empty circular list */
    chainTail = (CalloutEntry **)((char *)&calloutChain + 4);
    *chainTail = (CalloutEntry *)&calloutChain;
    calloutChain = (CalloutEntry *)&calloutChain;

    /* Create NXLock object for callout synchronization */
    nxLockClass = objc_getClass("NXLock");
    calloutLock = objc_msgSend(nxLockClass, sel_getUid("new"));

    /* Allocate sleep port */
    result = port_allocate(*task_self_ptr, &sleepPort);
    if (result != 0) {
        IOLog("IOInitGeneralFunc: port_allocate error\n");
    }

    /* Fork callout thread */
    IOForkThread(calloutThread, NULL);
}

/*
 * IOUnscheduleFunc
 * Remove a function from the callout chain
 */
void IOUnscheduleFunc(void (*func)(void *), void *arg)
{
    CalloutEntry *entry;
    CalloutEntry *prev;
    CalloutEntry *next;
    CalloutEntry *prevLink;
    CalloutEntry *nextLink;

    /* Lock the callout chain */
    [calloutLock lock];

    /* Walk the callout chain looking for matching entry */
    entry = calloutChain;
    if (entry != (CalloutEntry *)&calloutChain) {
        do {
            if ((entry->func == func) && (entry->arg == arg)) {
                /* Found matching entry, unlink it */
                prev = entry->prev;
                next = entry->next;

                /* Update prev's next pointer */
                prevLink = prev;
                if (prev != (CalloutEntry *)&calloutChain) {
                    prevLink = (CalloutEntry *)&prev->prev;
                }
                prevLink->next = next;

                /* Update next's prev pointer */
                nextLink = next;
                if (next != (CalloutEntry *)&calloutChain) {
                    nextLink = (CalloutEntry *)&next->prev;
                }
                nextLink->prev = prev;

                /* Free the entry */
                IOFree(entry, 0x18);
                break;
            }

            /* Move to next entry */
            entry = *(CalloutEntry **)&entry->prev;
        } while (entry != (CalloutEntry *)&calloutChain);
    }

    /* Unlock the callout chain */
    [calloutLock unlock];
}

/*
 * IOSuspendThread
 * Suspend a thread
 */
void IOSuspendThread(int *threadPtr)
{
    thread_suspend(threadPtr[1]);
}

/*
 * IOSleep
 * Sleep for specified timeout
 */
void IOSleep(unsigned int timeout)
{
    char msgBuf[4];
    int msgSize;
    int port;

    port = sleepPort;
    msgSize = 0x18;
    msg_receive(msgBuf, 0x500, timeout);
}

/*
 * IOScheduleFunc
 * Schedule a function to be called after a delay
 */
void IOScheduleFunc(void (*func)(void *), void *arg, unsigned int delayMS)
{
    CalloutEntry *entry;
    unsigned int timestamp[2];
    unsigned int origLow;
    unsigned long long delayNS;
    unsigned int delayNS_low;
    unsigned int delayNS_high;
    CalloutEntry **chainPtr;

    /* If no delay, call function immediately */
    if (delayMS == 0) {
        (*func)(arg);
        return;
    }

    /* Allocate callout entry */
    entry = (CalloutEntry *)IOMalloc(0x18);
    entry->func = func;
    entry->arg = arg;

    /* Get current timestamp */
    IOGetTimestamp(timestamp);

    /* Convert milliseconds to nanoseconds: delayMS * 1,000,000,000 */
    /* The decompiled code shows this as delayMS * 1000000000 with complex carry handling */
    delayNS = (unsigned long long)delayMS * 1000000000ULL;
    delayNS_low = (unsigned int)delayNS;
    delayNS_high = (unsigned int)(delayNS >> 32);

    /* Add delay to timestamp with carry handling */
    origLow = timestamp[0];
    timestamp[0] = timestamp[0] + delayNS_low;
    timestamp[1] = timestamp[1] + delayNS_high + ((timestamp[0] < origLow) ? 1 : 0);

    /* Store timestamp in entry */
    entry->timestamp_low = timestamp[0];
    entry->timestamp_high = timestamp[1];

    /* Lock the callout chain */
    [calloutLock lock];

    /* Insert at end of chain */
    if (calloutChain == (CalloutEntry *)&calloutChain) {
        /* Chain is empty */
        calloutChain = entry;
        chainPtr = (CalloutEntry **)((char *)&calloutChain + 4);
        *chainPtr = entry;
        entry->prev = (CalloutEntry *)&calloutChain;
        entry->next = (CalloutEntry *)&calloutChain;
    } else {
        /* Insert at tail */
        chainPtr = (CalloutEntry **)((char *)&calloutChain + 4);
        entry->next = (CalloutEntry *)*chainPtr;
        entry->prev = (CalloutEntry *)&calloutChain;
        (*chainPtr)->prev = entry;
        *chainPtr = entry;
    }

    /* Unlock the callout chain */
    [calloutLock unlock];
}

/*
 * IOResumeThread
 * Resume a suspended thread
 */
void IOResumeThread(int *threadPtr)
{
    thread_resume(threadPtr[1]);
}

/*
 * IOPanic
 * Print panic message and enter infinite loop
 */
void IOPanic(const char *message)
{
    IOLog(message);
    IOLog("waiting for debugger connection...");

    /* Infinite loop waiting for debugger */
    while (1) {
        /* Do nothing */
    }
}

/*
 * IOForkThread
 * Create a new thread
 */
void IOForkThread(void (*func)(void *), void *arg)
{
    cthread_fork(func, arg);
}

/*
 * IOFindValueForName
 * Look up a value by name in a name/value table
 * Table format: alternating int values and char* names, terminated by NULL name
 * Returns 0 on success, 0xfffffd3e (-706) on not found
 */
int IOFindValueForName(const char *name, int *table, int *outValue)
{
    char **namePtr;
    int *valuePtr;
    int result;

    /* Check if table has entries (second element is first name pointer) */
    if (table[1] != 0) {
        namePtr = (char **)(table + 1);
        valuePtr = table;

        /* Walk through table */
        do {
            result = strcmp(*namePtr, name);
            if (result == 0) {
                /* Found match */
                *outValue = *valuePtr;
                return 0;
            }

            /* Advance to next entry (skip value and name pointers) */
            namePtr += 2;
            valuePtr += 2;
        } while (*namePtr != NULL);
    }

    /* Not found */
    return 0xfffffd3e;
}

/*
 * IOFindNameForValue
 * Look up a name by value in a name/value table
 * Table format: alternating int values and char* names, terminated by NULL name
 * Returns pointer to name string, or formatted "N(d) (UNDEFINED)" if not found
 */
char *IOFindNameForValue(int value, int *table)
{
    int *valuePtr;
    char **namePtr;

    /* Check if table has entries */
    if (table[1] != 0) {
        valuePtr = table;
        namePtr = (char **)(table + 1);

        /* Walk through table */
        do {
            if (*valuePtr == value) {
                /* Found match */
                return *namePtr;
            }

            /* Advance to next entry */
            namePtr += 2;
            valuePtr += 2;
        } while (*namePtr != NULL);
    }

    /* Not found - format undefined value string */
    sprintf(noValue, "%d(d) (UNDEFINED)", value);
    return noValue;
}

/*
 * IOExitThread
 * Exit current thread with -1 result
 */
void IOExitThread(void)
{
    cthread_exit(0xffffffff);
}

/*
 * IODelay
 * Busy-wait delay for specified microseconds
 */
void IODelay(unsigned int microseconds)
{
    unsigned int currentTime[2];
    unsigned long long targetTime;
    unsigned int targetTime_low;
    unsigned long long delayNS;

    /* Get current timestamp */
    IOGetTimestamp(currentTime);

    /* Convert microseconds to nanoseconds and add to current time */
    delayNS = (unsigned long long)microseconds * 1000;
    targetTime = ((unsigned long long)currentTime[1] << 32) | currentTime[0];
    targetTime += delayNS;
    targetTime_low = (unsigned int)targetTime;

    /* Busy-wait until target time reached */
    do {
        IOGetTimestamp(currentTime);
    } while ((int)(targetTime_low - currentTime[0]) >= 0);
}

/*
 * IOCopyMemory
 * Copy memory with flags
 */
void IOCopyMemory(void *dest, const void *src, unsigned int count, unsigned int flags)
{
    __IOCopyMemory(dest, src, count, flags);
}

/*
 * =============================================================================
 * PnP Dump Utility Program
 * =============================================================================
 * This section contains a standalone utility program for dumping ISA PnP
 * device information. It queries the EISA driver for PnP card and device
 * configuration information.
 *
 * Usage: pnpdump [-c] [-d]
 *   -c  Dump card resource descriptions
 *   -d  Dump device configurations
 *   (no flags: dump both)
 * =============================================================================
 */

/*
 * bail
 * Print error message and exit
 */
void bail(const char *msg, int code)
{
    fprintf(stderr, "%s: %s %d\n", progname, msg, code);
    exit(1);
}

/*
 * main
 * PnP device information dump utility
 */
int main(int argc, char **argv)
{
    int dumpConfig;      /* -d flag: dump device configurations */
    int dumpCards;       /* -c flag: dump card info */
    id deviceMaster;
    int result;
    unsigned int objNum;
    const char *kind;
    Class pnpDevResClass;
    Class pnpResClass;
    unsigned int csn;
    char *argPtr;
    unsigned int valueSize;
    id deviceResources;
    int deviceCount;
    id deviceList;
    int deviceIndex;
    id currentConfig;

    progname = argv[0];

    /* Parse command-line arguments */
    if (argc == 1) {
        /* No arguments - dump both cards and configs */
        dumpConfig = 1;
        dumpCards = 1;
    } else {
        dumpConfig = 0;
        dumpCards = 0;

        /* Process all arguments */
        while (argc = argc - 1, argc != 0) {
            argv = argv + 1;
            if (**argv == '-') {
                argPtr = *argv;
                /* Process all flags in this argument */
                while (argPtr = argPtr + 1, *argPtr != '\0') {
                    if (*argPtr == 'c') {
                        dumpCards = 1;
                    } else if (*argPtr == 'd') {
                        dumpConfig = 1;
                    } else {
                        bail("invalid option\n", 0);
                    }
                }
            }
        }
    }

    /* Get device master and look up EISA0 */
    deviceMaster = objc_msgSend(objc_getClass("IODeviceMaster"), sel_getUid("new"));
    result = (int)objc_msgSend(deviceMaster, sel_getUid("lookUpByDeviceName:objectNumber:deviceKind:"),
                         "EISA0", &objNum, &kind);
    if (result != 0) {
        bail("lookup EISA0 failed", result);
    }

    /* Get PnP classes */
    pnpDevResClass = objc_getClass("PnPDeviceResources");
    pnpResClass = objc_getClass("PnPResources");

    /* Enable verbose output */
    objc_msgSend(pnpDevResClass, sel_getUid("setVerbose:"), 1);

    /* Iterate through all possible CSNs (1-254) */
    for (csn = 1; csn <= 254; csn++) {
        valueSize = 0x200;

        if (dumpCards) {
            /* Get PnP info for this card */
            sprintf(cmdBuffer, "%s( %d", "GetPnPInfo", csn);
            result = (int)objc_msgSend(deviceMaster,
                                sel_getUid("getCharValues:forParameter:objectNumber:count:"),
                                valueBuffer, cmdBuffer, objNum, &valueSize);

            if (result == 0) {
                /* Card found - parse and display info */
                printf("\n");
                printf("=========================================================\n");
                printf("csn %d:\n", csn);
                printf("=====================\n");
                printf("Resource Description:\n");
                printf("=====================\n");

                deviceResources = objc_msgSend(pnpDevResClass, sel_getUid("alloc"));
                deviceResources = objc_msgSend(deviceResources,
                                              sel_getUid("initForBuf:Length:CSN:"),
                                              valueBuffer, valueSize, csn);

                result = (int)objc_msgSend(deviceResources, sel_getUid("parseConfig"));
                if (result == 0) {
                    exit(1);
                }

                deviceList = objc_msgSend((id)result, sel_getUid("deviceList"));
                deviceCount = (int)objc_msgSend(deviceList, sel_getUid("count"));
                objc_msgSend((id)result, sel_getUid("free"));
            } else {
                /* No more cards */
                continue;
            }
        } else {
            /* Assume up to 10 logical devices */
            deviceCount = 10;
        }

        /* Dump current device configurations if requested */
        if (dumpConfig && deviceCount > 0) {
            for (deviceIndex = 0; deviceIndex < deviceCount; deviceIndex++) {
                sprintf(cmdBuffer, "%s( %d %d", "GetPnPDeviceCfg", csn, deviceIndex);
                valueSize = 0x200;

                result = (int)objc_msgSend(deviceMaster,
                                    sel_getUid("getCharValues:forParameter:objectNumber:count:"),
                                    valueBuffer, cmdBuffer, objNum, &valueSize);

                if (result == 0) {
                    printf("\n");
                    printf("============================================\n");
                    printf("Current configuration for Logical Device %d:\n", deviceIndex);
                    printf("============================================\n");

                    currentConfig = objc_msgSend(pnpResClass, sel_getUid("alloc"));
                    currentConfig = objc_msgSend(currentConfig,
                                                sel_getUid("initFromRegisters:"),
                                                valueBuffer);

                    result = (int)objc_msgSend(currentConfig, sel_getUid("parseConfig"));
                    if (result == 0) {
                        printf("config is nil - continuing\n");
                    } else {
                        objc_msgSend((id)result, sel_getUid("free"));
                    }
                }
            }
        }
    }

    exit(0);
    return 0;
}
