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
 * hfs_endian.c
 *
 * Byte order for the HFS and HFS Plus volume formats, adapted from
 * xnu-124.7 bsd/hfs/hfs_endian.c.  The layout checks compile on every
 * architecture and emit no code; the swapping code exists only on
 * little-endian hosts.
 */

#include <sys/param.h>
#include <sys/systm.h>
#include <sys/buf.h>
#include <sys/errno.h>

#include "hfs.h"
#include "hfs_endian.h"
#include "hfscommon/headers/BTreesPrivate.h"

/*
 * On-disk layout checks.  Apple's cc packs these structs with
 * #pragma options align=mac68k.  Each line fails to compile (a negative
 * array size) if a struct does not have the size or field offset that the
 * format defines (Inside Macintosh: Files; Technical Note TN1150).
 */
#define HFS_CHECK(name, cond)	typedef char hfs_check_##name[(cond) ? 1 : -1]
#define HFS_OFF(type, field)	((unsigned long)&((type *)0)->field)

HFS_CHECK(uint64, sizeof(UInt64) == 8);
HFS_CHECK(hfs_extent, sizeof(HFSExtentDescriptor) == 4);
HFS_CHECK(plus_extent, sizeof(HFSPlusExtentDescriptor) == 8);
HFS_CHECK(plus_fork, sizeof(HFSPlusForkData) == 80);

HFS_CHECK(mdb, sizeof(HFSMasterDirectoryBlock) == 162);
HFS_CHECK(mdb_alblksiz, HFS_OFF(HFSMasterDirectoryBlock, drAlBlkSiz) == 20);
HFS_CHECK(mdb_nxtcnid, HFS_OFF(HFSMasterDirectoryBlock, drNxtCNID) == 30);
HFS_CHECK(mdb_vn, HFS_OFF(HFSMasterDirectoryBlock, drVN) == 36);
HFS_CHECK(mdb_volbkup, HFS_OFF(HFSMasterDirectoryBlock, drVolBkUp) == 64);
HFS_CHECK(mdb_wrcnt, HFS_OFF(HFSMasterDirectoryBlock, drWrCnt) == 70);
HFS_CHECK(mdb_filcnt, HFS_OFF(HFSMasterDirectoryBlock, drFilCnt) == 84);
HFS_CHECK(mdb_fndrinfo, HFS_OFF(HFSMasterDirectoryBlock, drFndrInfo) == 92);
HFS_CHECK(mdb_embedsig, HFS_OFF(HFSMasterDirectoryBlock, drEmbedSigWord) == 124);
HFS_CHECK(mdb_xtflsize, HFS_OFF(HFSMasterDirectoryBlock, drXTFlSize) == 130);
HFS_CHECK(mdb_ctextrec, HFS_OFF(HFSMasterDirectoryBlock, drCTExtRec) == 150);

HFS_CHECK(vh, sizeof(HFSPlusVolumeHeader) == 512);
HFS_CHECK(vh_blocksize, HFS_OFF(HFSPlusVolumeHeader, blockSize) == 40);
HFS_CHECK(vh_encodings, HFS_OFF(HFSPlusVolumeHeader, encodingsBitmap) == 72);
HFS_CHECK(vh_finderinfo, HFS_OFF(HFSPlusVolumeHeader, finderInfo) == 80);
HFS_CHECK(vh_allocation, HFS_OFF(HFSPlusVolumeHeader, allocationFile) == 112);
HFS_CHECK(vh_extents, HFS_OFF(HFSPlusVolumeHeader, extentsFile) == 192);
HFS_CHECK(vh_catalog, HFS_OFF(HFSPlusVolumeHeader, catalogFile) == 272);
HFS_CHECK(vh_startup, HFS_OFF(HFSPlusVolumeHeader, startupFile) == 432);

HFS_CHECK(node, sizeof(BTNodeDescriptor) == 14);
HFS_CHECK(header, sizeof(HeaderRec) == 120);
HFS_CHECK(header_nodesize, HFS_OFF(HeaderRec, nodeSize) == 32);
HFS_CHECK(header_clumpsize, HFS_OFF(HeaderRec, clumpSize) == 46);
HFS_CHECK(header_attributes, HFS_OFF(HeaderRec, attributes) == 52);

HFS_CHECK(hfs_extent_key, sizeof(HFSExtentKey) == 8);
HFS_CHECK(hfs_extent_key_start, HFS_OFF(HFSExtentKey, startBlock) == 6);
HFS_CHECK(plus_extent_key, sizeof(HFSPlusExtentKey) == 12);
HFS_CHECK(hfs_catalog_key, sizeof(HFSCatalogKey) == 38);
HFS_CHECK(hfs_catalog_key_name, HFS_OFF(HFSCatalogKey, nodeName) == 6);
HFS_CHECK(plus_catalog_key, sizeof(HFSPlusCatalogKey) == 518);
HFS_CHECK(plus_catalog_key_name, HFS_OFF(HFSPlusCatalogKey, nodeName) == 6);

HFS_CHECK(hfs_folder, sizeof(HFSCatalogFolder) == 70);
HFS_CHECK(hfs_folder_id, HFS_OFF(HFSCatalogFolder, folderID) == 6);
HFS_CHECK(hfs_file, sizeof(HFSCatalogFile) == 102);
HFS_CHECK(hfs_file_id, HFS_OFF(HFSCatalogFile, fileID) == 20);
HFS_CHECK(hfs_file_datalen, HFS_OFF(HFSCatalogFile, dataLogicalSize) == 26);
HFS_CHECK(hfs_file_dataext, HFS_OFF(HFSCatalogFile, dataExtents) == 74);
HFS_CHECK(hfs_thread, sizeof(HFSCatalogThread) == 46);
HFS_CHECK(hfs_thread_parent, HFS_OFF(HFSCatalogThread, parentID) == 10);

HFS_CHECK(plus_folder, sizeof(HFSPlusCatalogFolder) == 88);
HFS_CHECK(plus_folder_perm, HFS_OFF(HFSPlusCatalogFolder, permissions) == 32);
HFS_CHECK(plus_file, sizeof(HFSPlusCatalogFile) == 248);
HFS_CHECK(plus_file_datafork, HFS_OFF(HFSPlusCatalogFile, dataFork) == 88);
HFS_CHECK(plus_thread, sizeof(HFSPlusCatalogThread) == 520);
HFS_CHECK(plus_thread_parent, HFS_OFF(HFSPlusCatalogThread, parentID) == 4);
