/*
 * Copyright (c) 1998 Apple Computer, Inc. All rights reserved.
 *
 * EtherExpress16KernelServerInstance.h - Kernel Server Instance
 */

#import <objc/Object.h>

@class EtherExpress16;

@interface EtherExpress16KernelServerInstance : Object
{
    EtherExpress16 *driver;
}

- init:(EtherExpress16 *)drv;
- free;

@end
