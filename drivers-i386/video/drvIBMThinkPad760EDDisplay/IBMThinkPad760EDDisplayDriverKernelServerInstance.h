/*
 * Copyright (c) 1998 Apple Computer, Inc. All rights reserved.
 *
 * IBM ThinkPad 760ED Display Driver - Kernel Server Instance
 */

#import <objc/Object.h>
#import <kernserv/prototypes.h>

@interface IBMThinkPad760EDDisplayDriverKernelServerInstance : Object
{
    id driver;
    kern_server_t kernelServer;
}

+ (BOOL)loadDriver;
+ (BOOL)unloadDriver;

- init;
- (void)free;
- (kern_return_t)startDriver;
- (kern_return_t)stopDriver;

@end
