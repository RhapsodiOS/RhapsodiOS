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

#if BYTE_ORDER == LITTLE_ENDIAN

/*
 * The first record of a node always starts right after the 14-byte node
 * descriptor, so the last UInt16 of a valid node (its first offset) reads
 * 0x000e in host order and 0x0e00 while still in disk order.
 */
#define kNodeInHostOrder	0x000e
#define kNodeInDiskOrder	0x0e00

/* Swap a field in place, but only on the second (swapping) pass. */
#define SW16(x)	do { if (swap) (x) = SWAP_BE16(x); } while (0)
#define SW32(x)	do { if (swap) (x) = SWAP_BE32(x); } while (0)

static void
swap_hfs_extents(HFSExtentDescriptor *e, int n)
{
	int i;

	for (i = 0; i < n; i++) {
		e[i].startBlock = SWAP_BE16(e[i].startBlock);
		e[i].blockCount = SWAP_BE16(e[i].blockCount);
	}
}

static void
swap_plus_extents(HFSPlusExtentDescriptor *e, int n)
{
	int i;

	for (i = 0; i < n; i++) {
		e[i].startBlock = SWAP_BE32(e[i].startBlock);
		e[i].blockCount = SWAP_BE32(e[i].blockCount);
	}
}

/* UInt64 is a {hi, lo} struct here, stored big-endian as hi then lo. */
static void
swap_uint64(UInt64 *v)
{
	v->hi = SWAP_BE32(v->hi);
	v->lo = SWAP_BE32(v->lo);
}

static void
swap_fork(HFSPlusForkData *f)
{
	swap_uint64(&f->logicalSize);
	f->clumpSize = SWAP_BE32(f->clumpSize);
	f->totalBlocks = SWAP_BE32(f->totalBlocks);
	swap_plus_extents(f->extents, kHFSPlusExtentDensity);
}

/*
 * drVN is a Pascal string, and drFndrInfo, like all Finder information,
 * stays big-endian in memory.
 */
void
hfs_swap_MDB(HFSMasterDirectoryBlock *mdb)
{
	mdb->drSigWord = SWAP_BE16(mdb->drSigWord);
	mdb->drCrDate = SWAP_BE32(mdb->drCrDate);
	mdb->drLsMod = SWAP_BE32(mdb->drLsMod);
	mdb->drAtrb = SWAP_BE16(mdb->drAtrb);
	mdb->drNmFls = SWAP_BE16(mdb->drNmFls);
	mdb->drVBMSt = SWAP_BE16(mdb->drVBMSt);
	mdb->drAllocPtr = SWAP_BE16(mdb->drAllocPtr);
	mdb->drNmAlBlks = SWAP_BE16(mdb->drNmAlBlks);
	mdb->drAlBlkSiz = SWAP_BE32(mdb->drAlBlkSiz);
	mdb->drClpSiz = SWAP_BE32(mdb->drClpSiz);
	mdb->drAlBlSt = SWAP_BE16(mdb->drAlBlSt);
	mdb->drNxtCNID = SWAP_BE32(mdb->drNxtCNID);
	mdb->drFreeBks = SWAP_BE16(mdb->drFreeBks);
	mdb->drVolBkUp = SWAP_BE32(mdb->drVolBkUp);
	mdb->drVSeqNum = SWAP_BE16(mdb->drVSeqNum);
	mdb->drWrCnt = SWAP_BE32(mdb->drWrCnt);
	mdb->drXTClpSiz = SWAP_BE32(mdb->drXTClpSiz);
	mdb->drCTClpSiz = SWAP_BE32(mdb->drCTClpSiz);
	mdb->drNmRtDirs = SWAP_BE16(mdb->drNmRtDirs);
	mdb->drFilCnt = SWAP_BE32(mdb->drFilCnt);
	mdb->drDirCnt = SWAP_BE32(mdb->drDirCnt);
	mdb->drEmbedSigWord = SWAP_BE16(mdb->drEmbedSigWord);
	swap_hfs_extents(&mdb->drEmbedExtent, 1);
	mdb->drXTFlSize = SWAP_BE32(mdb->drXTFlSize);
	swap_hfs_extents(mdb->drXTExtRec, kHFSExtentDensity);
	mdb->drCTFlSize = SWAP_BE32(mdb->drCTFlSize);
	swap_hfs_extents(mdb->drCTExtRec, kHFSExtentDensity);
}

/* finderInfo stays big-endian in memory. */
void
hfs_swap_VolumeHeader(HFSPlusVolumeHeader *vh)
{
	vh->signature = SWAP_BE16(vh->signature);
	vh->version = SWAP_BE16(vh->version);
	vh->attributes = SWAP_BE32(vh->attributes);
	vh->lastMountedVersion = SWAP_BE32(vh->lastMountedVersion);
	vh->reserved = SWAP_BE32(vh->reserved);
	vh->createDate = SWAP_BE32(vh->createDate);
	vh->modifyDate = SWAP_BE32(vh->modifyDate);
	vh->backupDate = SWAP_BE32(vh->backupDate);
	vh->checkedDate = SWAP_BE32(vh->checkedDate);
	vh->fileCount = SWAP_BE32(vh->fileCount);
	vh->folderCount = SWAP_BE32(vh->folderCount);
	vh->blockSize = SWAP_BE32(vh->blockSize);
	vh->totalBlocks = SWAP_BE32(vh->totalBlocks);
	vh->freeBlocks = SWAP_BE32(vh->freeBlocks);
	vh->nextAllocation = SWAP_BE32(vh->nextAllocation);
	vh->rsrcClumpSize = SWAP_BE32(vh->rsrcClumpSize);
	vh->dataClumpSize = SWAP_BE32(vh->dataClumpSize);
	vh->nextCatalogID = SWAP_BE32(vh->nextCatalogID);
	vh->writeCount = SWAP_BE32(vh->writeCount);
	swap_uint64(&vh->encodingsBitmap);
	swap_fork(&vh->allocationFile);
	swap_fork(&vh->extentsFile);
	swap_fork(&vh->catalogFile);
	swap_fork(&vh->attributesFile);
	swap_fork(&vh->startupFile);
}

/*
 * The header record only; the node's user record and map record are left
 * alone (map words are swapped where BTreeAllocate.c uses them).
 */
static void
swap_header(HeaderRec *h)
{
	h->treeDepth = SWAP_BE16(h->treeDepth);
	h->rootNode = SWAP_BE32(h->rootNode);
	h->leafRecords = SWAP_BE32(h->leafRecords);
	h->firstLeafNode = SWAP_BE32(h->firstLeafNode);
	h->lastLeafNode = SWAP_BE32(h->lastLeafNode);
	h->nodeSize = SWAP_BE16(h->nodeSize);
	h->maxKeyLength = SWAP_BE16(h->maxKeyLength);
	h->totalNodes = SWAP_BE32(h->totalNodes);
	h->freeNodes = SWAP_BE32(h->freeNodes);
	h->clumpSize = SWAP_BE32(h->clumpSize);
	h->attributes = SWAP_BE32(h->attributes);
}

/*
 * One HFS Plus record in [rec, end).  With swap == 0 this only checks that
 * the record fits its slot; with swap == 1 it swaps it.  Lengths and types
 * are read in host order whichever way the bytes are going (toHost).
 * Finder information (userInfo, finderInfo) is never swapped.
 */
static int
swap_plus_record(UInt8 *rec, UInt8 *end, int isIndex, UInt32 fileID, int toHost, int swap)
{
	UInt16 keyLength, n, j;
	SInt16 type;
	UInt8 *data;

	if (rec + sizeof(UInt16) > end)
		return EINVAL;
	keyLength = *(UInt16 *)rec;
	if (toHost)
		keyLength = SWAP_BE16(keyLength);
	data = rec + sizeof(UInt16) + keyLength;
	if (data > end)
		return EINVAL;

	if (fileID == kHFSExtentsFileID) {
		HFSPlusExtentKey *key = (HFSPlusExtentKey *)rec;

		if (keyLength != kHFSPlusExtentKeyMaximumLength)
			return EINVAL;
		SW16(key->keyLength);
		SW32(key->fileID);
		SW32(key->startBlock);
		if (isIndex)
			goto pointer;
		if (data + sizeof(HFSPlusExtentRecord) > end)
			return EINVAL;
		if (swap)
			swap_plus_extents((HFSPlusExtentDescriptor *)data, kHFSPlusExtentDensity);
		return 0;
	}
	if (fileID != kHFSCatalogFileID)
		return EINVAL;

	{
		HFSPlusCatalogKey *key = (HFSPlusCatalogKey *)rec;

		if (keyLength < 6)
			return EINVAL;
		n = key->nodeName.length;
		if (toHost)
			n = SWAP_BE16(n);
		if (n > kHFSPlusMaxFileNameChars || 6 + 2 * n > keyLength)
			return EINVAL;
		SW16(key->keyLength);
		SW32(key->parentID);
		SW16(key->nodeName.length);
		for (j = 0; j < n; j++)
			SW16(key->nodeName.unicode[j]);
	}
	if (isIndex)
		goto pointer;

	if (data + sizeof(SInt16) > end)
		return EINVAL;
	type = *(SInt16 *)data;
	if (toHost)
		type = SWAP_BE16(type);
	switch (type) {
	case kHFSPlusFolderRecord: {
		HFSPlusCatalogFolder *r = (HFSPlusCatalogFolder *)data;

		if (data + sizeof(*r) > end)
			return EINVAL;
		SW16(r->flags);
		SW32(r->valence);
		SW32(r->folderID);
		SW32(r->createDate);
		SW32(r->contentModDate);
		SW32(r->attributeModDate);
		SW32(r->accessDate);
		SW32(r->backupDate);
		SW32(r->permissions.ownerID);
		SW32(r->permissions.groupID);
		SW32(r->permissions.permissions);
		SW32(r->permissions.specialDevice);
		SW32(r->textEncoding);
		break;
	}
	case kHFSPlusFileRecord: {
		HFSPlusCatalogFile *r = (HFSPlusCatalogFile *)data;

		if (data + sizeof(*r) > end)
			return EINVAL;
		SW16(r->flags);
		SW32(r->fileID);
		SW32(r->createDate);
		SW32(r->contentModDate);
		SW32(r->attributeModDate);
		SW32(r->accessDate);
		SW32(r->backupDate);
		SW32(r->permissions.ownerID);
		SW32(r->permissions.groupID);
		SW32(r->permissions.permissions);
		SW32(r->permissions.specialDevice);
		SW32(r->textEncoding);
		if (swap) {
			swap_fork(&r->dataFork);
			swap_fork(&r->resourceFork);
		}
		break;
	}
	case kHFSPlusFolderThreadRecord:
	case kHFSPlusFileThreadRecord: {
		HFSPlusCatalogThread *r = (HFSPlusCatalogThread *)data;

		if (data + 10 > end)
			return EINVAL;
		n = r->nodeName.length;
		if (toHost)
			n = SWAP_BE16(n);
		if (n > kHFSPlusMaxFileNameChars || data + 10 + 2 * n > end)
			return EINVAL;
		SW32(r->parentID);
		SW16(r->nodeName.length);
		for (j = 0; j < n; j++)
			SW16(r->nodeName.unicode[j]);
		break;
	}
	default:
		return EINVAL;
	}
	SW16(*(SInt16 *)data);
	return 0;

pointer:
	if (data + sizeof(UInt32) > end)
		return EINVAL;
	SW32(*(UInt32 *)data);
	return 0;
}

/* One HFS record in [rec, end); see swap_plus_record. */
static int
swap_hfs_record(UInt8 *rec, UInt8 *end, int isIndex, UInt32 fileID, int toHost, int swap)
{
	UInt8 keyLength;
	SInt16 type;
	UInt8 *data;

	if (rec + 1 > end)
		return EINVAL;
	keyLength = rec[0];
	data = rec + ((keyLength + 2) & ~1);
	if (data > end)
		return EINVAL;

	if (fileID == kHFSExtentsFileID) {
		HFSExtentKey *key = (HFSExtentKey *)rec;

		if (keyLength != kHFSExtentKeyMaximumLength)
			return EINVAL;
		SW32(key->fileID);
		SW16(key->startBlock);
		if (isIndex)
			goto pointer;
		if (data + sizeof(HFSExtentRecord) > end)
			return EINVAL;
		if (swap)
			swap_hfs_extents((HFSExtentDescriptor *)data, kHFSExtentDensity);
		return 0;
	}
	if (fileID != kHFSCatalogFileID)
		return EINVAL;

	{
		HFSCatalogKey *key = (HFSCatalogKey *)rec;

		if (keyLength < 6 || key->nodeName[0] > kHFSMaxFileNameChars ||
		    6 + key->nodeName[0] > keyLength)
			return EINVAL;
		SW32(key->parentID);
	}
	if (isIndex)
		goto pointer;

	if (data + sizeof(SInt16) > end)
		return EINVAL;
	type = *(SInt16 *)data;
	if (toHost)
		type = SWAP_BE16(type);
	switch (type) {
	case kHFSFolderRecord: {
		HFSCatalogFolder *r = (HFSCatalogFolder *)data;

		if (data + sizeof(*r) > end)
			return EINVAL;
		SW16(r->flags);
		SW16(r->valence);
		SW32(r->folderID);
		SW32(r->createDate);
		SW32(r->modifyDate);
		SW32(r->backupDate);
		break;
	}
	case kHFSFileRecord: {
		HFSCatalogFile *r = (HFSCatalogFile *)data;

		if (data + sizeof(*r) > end)
			return EINVAL;
		SW32(r->fileID);
		SW16(r->dataStartBlock);
		SW32(r->dataLogicalSize);
		SW32(r->dataPhysicalSize);
		SW16(r->rsrcStartBlock);
		SW32(r->rsrcLogicalSize);
		SW32(r->rsrcPhysicalSize);
		SW32(r->createDate);
		SW32(r->modifyDate);
		SW32(r->backupDate);
		SW16(r->clumpSize);
		if (swap) {
			swap_hfs_extents(r->dataExtents, kHFSExtentDensity);
			swap_hfs_extents(r->rsrcExtents, kHFSExtentDensity);
		}
		break;
	}
	case kHFSFolderThreadRecord:
	case kHFSFileThreadRecord: {
		HFSCatalogThread *r = (HFSCatalogThread *)data;

		if (data + sizeof(*r) > end)
			return EINVAL;
		SW32(r->parentID);
		break;
	}
	default:
		return EINVAL;
	}
	SW16(*(SInt16 *)data);
	return 0;

pointer:
	if (data + sizeof(UInt32) > end)
		return EINVAL;
	SW32(*(UInt32 *)data);
	return 0;
}

/*
 * Offset of record i (i == numRecords gives the start of free space), read
 * from the offset table at the end of the node in host order.
 */
static UInt16
record_offset(UInt8 *base, UInt32 size, UInt16 i, int toHost)
{
	UInt16 off = ((UInt16 *)(base + size))[-1 - (int)i];

	return toHost ? SWAP_BE16(off) : off;
}

static int
swap_node(BlockDescriptor *block, int isHFSPlus, UInt32 fileID, int toHost, int swap)
{
	BTNodeDescriptor *desc = (BTNodeDescriptor *)block->buffer;
	UInt8 *base = (UInt8 *)block->buffer;
	UInt32 size = block->blockSize;
	UInt16 count, i, off, prev;
	int err;

	count = desc->numRecords;
	if (toHost)
		count = SWAP_BE16(count);
	if (sizeof(BTNodeDescriptor) + (count + 1) * sizeof(UInt16) > size)
		return EINVAL;
	prev = 0;
	for (i = 0; i <= count; i++) {
		off = record_offset(base, size, i, toHost);
		if (i == 0 ? off != sizeof(BTNodeDescriptor) : off <= prev)
			return EINVAL;
		prev = off;
	}
	if (prev > size - (count + 1) * sizeof(UInt16))
		return EINVAL;

	switch (desc->type) {
	case kLeafNode:
	case kIndexNode:
		for (i = 0; i < count; i++) {
			UInt8 *rec = base + record_offset(base, size, i, toHost);
			UInt8 *end = base + record_offset(base, size, i + 1, toHost);

			err = isHFSPlus
			    ? swap_plus_record(rec, end, desc->type == kIndexNode, fileID, toHost, swap)
			    : swap_hfs_record(rec, end, desc->type == kIndexNode, fileID, toHost, swap);
			if (err)
				return err;
		}
		break;
	case kHeaderNode:
		if (count < 1 || record_offset(base, size, 1, toHost) < sizeof(HeaderRec))
			return EINVAL;
		if (swap)
			swap_header((HeaderRec *)base);
		break;
	case kMapNode:
		break;
	default:
		return EINVAL;
	}

	/* The descriptor and offset table go last: the records above used them. */
	if (swap) {
		desc->fLink = SWAP_BE32(desc->fLink);
		desc->bLink = SWAP_BE32(desc->bLink);
		desc->numRecords = SWAP_BE16(desc->numRecords);
		for (i = 0; i <= count; i++) {
			UInt16 *p = &((UInt16 *)(base + size))[-1 - (int)i];

			*p = SWAP_BE16(*p);
		}
	}
	return 0;
}

/*
 * Swap a whole node.  The first pass only validates; nothing changes unless
 * the whole node is valid.
 */
int
hfs_swap_BTNode(BlockDescriptor *block, int isHFSPlus, UInt32 fileID, int toHost)
{
	int err;

	err = swap_node(block, isHFSPlus, fileID, toHost, 0);
	if (err == 0)
		(void) swap_node(block, isHFSPlus, fileID, toHost, 1);
	return err;
}

/*
 * A node just obtained through GetBTreeBlock: put it in host order unless it
 * already is.  BTOpenPath first reads the header node at kMinNodeSize, before
 * it knows the real node size, uses only the header record and then trashes
 * the buffer; that short read has no offset table to go by, so only its
 * header record is swapped.
 */
int
hfs_btnode_to_host(BlockDescriptor *block, int isHFSPlus, UInt32 fileID)
{
	BTNodeDescriptor *desc = (BTNodeDescriptor *)block->buffer;
	HeaderRec *header = (HeaderRec *)block->buffer;
	UInt16 last = *(UInt16 *)((UInt8 *)block->buffer + block->blockSize - sizeof(UInt16));

	if (desc->type == kHeaderNode && block->blockSize >= sizeof(HeaderRec) &&
	    header->nodeSize != block->blockSize &&
	    SWAP_BE16(header->nodeSize) != block->blockSize) {
		swap_header(header);
		return 0;
	}
	if (last == kNodeInDiskOrder)
		return hfs_swap_BTNode(block, isHFSPlus, fileID, 1);
	return 0;	/* already host order, or not a node: CheckNode decides */
}

/*
 * A B-tree buffer about to be written: put it in disk order if it is in host
 * order.  A buffer that is not exactly one node of this tree is refused.
 */
int
hfs_btnode_to_disk(struct buf *bp, FCB *fcb, int isHFSPlus, UInt32 fileID)
{
	BlockDescriptor block;
	BTreeControlBlockPtr btcb = (BTreeControlBlockPtr)fcb->fcbBTCBPtr;
	UInt16 last = *(UInt16 *)((UInt8 *)bp->b_data + bp->b_bcount - sizeof(UInt16));

	if (last != kNodeInHostOrder)
		return 0;	/* already disk order, or not a node (ClearBTNodes writes zeros) */
	if (btcb == NULL || bp->b_bcount != btcb->nodeSize)
		return EIO;
	block.buffer = bp->b_data;
	block.blockHeader = bp;
	block.blockSize = bp->b_bcount;
	block.blockReadFromDisk = 0;
	return hfs_swap_BTNode(&block, isHFSPlus, fileID, 0);
}

#endif /* BYTE_ORDER == LITTLE_ENDIAN */
