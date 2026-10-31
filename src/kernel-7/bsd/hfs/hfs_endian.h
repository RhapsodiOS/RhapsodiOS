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
 * hfs_endian.h
 *
 * HFS and HFS Plus are big-endian on disk.  On a big-endian host every
 * macro here is an identity or empty, so the ppc kernel compiles exactly as
 * it did before these macros existed.  Adapted from xnu-124.7
 * bsd/hfs/hfs_endian.h.
 */
#ifndef __HFS_ENDIAN_H__
#define __HFS_ENDIAN_H__

#include <machine/endian.h>

#if BYTE_ORDER == BIG_ENDIAN

#define SWAP_BE16(x)	(x)
#define SWAP_BE32(x)	(x)
#define SWAP_MDB(mdb)
#define SWAP_VH(vh)

#elif BYTE_ORDER == LITTLE_ENDIAN

#include <machine/byte_order.h>
#include "hfscommon/headers/BTreesInternal.h"
#include "hfscommon/headers/HFSVolumes.h"

#define SWAP_BE16(x)	NXSwapBigShortToHost(x)
#define SWAP_BE32(x)	NXSwapBigLongToHost(x)
#define SWAP_MDB(mdb)	hfs_swap_MDB(mdb)
#define SWAP_VH(vh)	hfs_swap_VolumeHeader(vh)

struct buf;

/* Whole-struct swaps; each is its own inverse. */
void	hfs_swap_MDB(HFSMasterDirectoryBlock *mdb);
void	hfs_swap_VolumeHeader(HFSPlusVolumeHeader *vh);

/*
 * B-tree nodes.  Each validates the whole node before changing a byte and
 * returns non-zero, leaving the node untouched, if it is not a valid node.
 */
int	hfs_swap_BTNode(BlockDescriptor *block, int isHFSPlus, UInt32 fileID, int toHost);
int	hfs_btnode_to_host(BlockDescriptor *block, int isHFSPlus, UInt32 fileID);
int	hfs_btnode_to_disk(struct buf *bp, FCB *fcb, int isHFSPlus, UInt32 fileID);

#else
#error Unknown byte order
#endif

#endif /* __HFS_ENDIAN_H__ */
