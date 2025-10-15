/*
 * Copyright (c) 1998 Apple Computer, Inc. All rights reserved.
 *
 * EtherExpress16KernelServerInstance.m - Kernel Server Instance Implementation
 */

#import "EtherExpress16KernelServerInstance.h"
#import "EtherExpress16.h"

@implementation EtherExpress16KernelServerInstance

- init:(EtherExpress16 *)drv
{
    [super init];
    driver = drv;
    return self;
}

- free
{
    driver = nil;
    return [super free];
}

@end
