/*
 * Copyright (c) 1998 Apple Computer, Inc. All rights reserved.
 *
 * ATIMach64DisplayDriverKernelServerInstance.h
 * Kernel Server Instance for ATI Mach64 Display Driver
 *
 * HISTORY
 * 28 Mar 98    Created.
 */

#ifndef _ATIMACH64_DISPLAY_DRIVER_KERNEL_SERVER_INSTANCE_H
#define _ATIMACH64_DISPLAY_DRIVER_KERNEL_SERVER_INSTANCE_H

#import <objc/Object.h>
#import <mach/mach_types.h>

@interface ATIMach64DisplayDriverKernelServerInstance : Object
{
@private
    void *_kernelInstance;
    void *_deviceInstance;
}

+ (id)allocKernelInstance;
- (id)initFromMachine:(void *)machine fromSource:(void *)source;
- (void)free;

@end

#endif /* _ATIMACH64_DISPLAY_DRIVER_KERNEL_SERVER_INSTANCE_H */
