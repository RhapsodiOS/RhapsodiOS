/*
 * Copyright (c) 2000 Apple Computer, Inc. All rights reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 *
 * Portions Copyright (c) 2000 Apple Computer, Inc.  All Rights
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
 * hfs_endian.h -- HFS and HFS Plus are big-endian on disk.  hfs.util reads
 * the volume header, B-tree headers and catalog keys straight off the device;
 * these convert them to host order.
 * After diskdev_cmds-143 mount_hfs.tproj/hfs_endian.h.
 */
#ifndef __MOUNT_HFS_ENDIAN_H__
#define __MOUNT_HFS_ENDIAN_H__

#include <architecture/byte_order.h>

#define SWAP_BE16(x)	NXSwapBigShortToHost(x)
#define SWAP_BE32(x)	NXSwapBigLongToHost(x)

#endif /* __MOUNT_HFS_ENDIAN_H__ */
