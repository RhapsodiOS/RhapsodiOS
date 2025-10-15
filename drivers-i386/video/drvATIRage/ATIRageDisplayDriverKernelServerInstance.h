/*
 * Copyright (c) 1998 Apple Computer, Inc. All rights reserved.
 *
 * ATIRageDisplayDriverKernelServerInstance.h
 * Kernel Server Instance for ATI Rage Display Driver
 *
 * HISTORY
 * 28 Mar 98    Created.
 */

#ifndef _ATIRAGE_DISPLAY_DRIVER_KERNEL_SERVER_INSTANCE_H
#define _ATIRAGE_DISPLAY_DRIVER_KERNEL_SERVER_INSTANCE_H

#import <objc/Object.h>
#import <mach/mach_types.h>

@interface ATIRageDisplayDriverKernelServerInstance : Object
{
@private
    void *_kernelInstance;
    void *_deviceInstance;
}

+ (id)allocKernelInstance;
- (id)initFromMachine:(void *)machine fromSource:(void *)source;
- (void)free;

@end

#endif /* _ATIRAGE_DISPLAY_DRIVER_KERNEL_SERVER_INSTANCE_H */
