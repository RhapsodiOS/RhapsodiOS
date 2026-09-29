"""Put newfs_hfs's on-disk structures in big-endian order (HFS is big-endian).

Usage: python patch_newfs.py PATH/TO/HFSVolumeInit.c [--dry-run]

Each substitution keeps the file's own whitespace (it is captured, never
retyped) and must match exactly the number of times given, or nothing is
written.  The file is read and written as latin-1: it holds Mac-Roman bytes.
"""
import re
import sys

SWAP_CODE = r"""

/*
 * HFS is big-endian on disk.  The MDB and the volume header are built and
 * used in host order and swapped as a whole around the writes that put them
 * on disk; everything else is built big-endian directly.  After the kernel's
 * hfs_swap_MDB and hfs_swap_VolumeHeader (bsd/hfs/hfs_endian.c).
 */
#if BYTE_ORDER == LITTLE_ENDIAN

static void
SwapHFSExtents (HFSExtentDescriptor *e, int n)
{
	int i;

	for (i = 0; i < n; i++) {
		e[i].startBlock = SWAP_BE16 (e[i].startBlock);
		e[i].blockCount = SWAP_BE16 (e[i].blockCount);
	}
}

static void
SwapPlusFork (HFSPlusForkData *f)
{
	int i;

	f->logicalSize.hi = SWAP_BE32 (f->logicalSize.hi);
	f->logicalSize.lo = SWAP_BE32 (f->logicalSize.lo);
	f->clumpSize = SWAP_BE32 (f->clumpSize);
	f->totalBlocks = SWAP_BE32 (f->totalBlocks);
	for (i = 0; i < kHFSPlusExtentDensity; i++) {
		f->extents[i].startBlock = SWAP_BE32 (f->extents[i].startBlock);
		f->extents[i].blockCount = SWAP_BE32 (f->extents[i].blockCount);
	}
}

/* drVN is a Pascal string and drFndrInfo stays big-endian. */
static void
SwapMDB (HFSMasterDirectoryBlock *mdb)
{
	mdb->drSigWord = SWAP_BE16 (mdb->drSigWord);
	mdb->drCrDate = SWAP_BE32 (mdb->drCrDate);
	mdb->drLsMod = SWAP_BE32 (mdb->drLsMod);
	mdb->drAtrb = SWAP_BE16 (mdb->drAtrb);
	mdb->drNmFls = SWAP_BE16 (mdb->drNmFls);
	mdb->drVBMSt = SWAP_BE16 (mdb->drVBMSt);
	mdb->drAllocPtr = SWAP_BE16 (mdb->drAllocPtr);
	mdb->drNmAlBlks = SWAP_BE16 (mdb->drNmAlBlks);
	mdb->drAlBlkSiz = SWAP_BE32 (mdb->drAlBlkSiz);
	mdb->drClpSiz = SWAP_BE32 (mdb->drClpSiz);
	mdb->drAlBlSt = SWAP_BE16 (mdb->drAlBlSt);
	mdb->drNxtCNID = SWAP_BE32 (mdb->drNxtCNID);
	mdb->drFreeBks = SWAP_BE16 (mdb->drFreeBks);
	mdb->drVolBkUp = SWAP_BE32 (mdb->drVolBkUp);
	mdb->drVSeqNum = SWAP_BE16 (mdb->drVSeqNum);
	mdb->drWrCnt = SWAP_BE32 (mdb->drWrCnt);
	mdb->drXTClpSiz = SWAP_BE32 (mdb->drXTClpSiz);
	mdb->drCTClpSiz = SWAP_BE32 (mdb->drCTClpSiz);
	mdb->drNmRtDirs = SWAP_BE16 (mdb->drNmRtDirs);
	mdb->drFilCnt = SWAP_BE32 (mdb->drFilCnt);
	mdb->drDirCnt = SWAP_BE32 (mdb->drDirCnt);
	mdb->drEmbedSigWord = SWAP_BE16 (mdb->drEmbedSigWord);
	SwapHFSExtents (&mdb->drEmbedExtent, 1);
	mdb->drXTFlSize = SWAP_BE32 (mdb->drXTFlSize);
	SwapHFSExtents (mdb->drXTExtRec, kHFSExtentDensity);
	mdb->drCTFlSize = SWAP_BE32 (mdb->drCTFlSize);
	SwapHFSExtents (mdb->drCTExtRec, kHFSExtentDensity);
}

/* finderInfo stays big-endian. */
static void
SwapVH (HFSPlusVolumeHeader *vh)
{
	vh->signature = SWAP_BE16 (vh->signature);
	vh->version = SWAP_BE16 (vh->version);
	vh->attributes = SWAP_BE32 (vh->attributes);
	vh->lastMountedVersion = SWAP_BE32 (vh->lastMountedVersion);
	vh->reserved = SWAP_BE32 (vh->reserved);
	vh->createDate = SWAP_BE32 (vh->createDate);
	vh->modifyDate = SWAP_BE32 (vh->modifyDate);
	vh->backupDate = SWAP_BE32 (vh->backupDate);
	vh->checkedDate = SWAP_BE32 (vh->checkedDate);
	vh->fileCount = SWAP_BE32 (vh->fileCount);
	vh->folderCount = SWAP_BE32 (vh->folderCount);
	vh->blockSize = SWAP_BE32 (vh->blockSize);
	vh->totalBlocks = SWAP_BE32 (vh->totalBlocks);
	vh->freeBlocks = SWAP_BE32 (vh->freeBlocks);
	vh->nextAllocation = SWAP_BE32 (vh->nextAllocation);
	vh->rsrcClumpSize = SWAP_BE32 (vh->rsrcClumpSize);
	vh->dataClumpSize = SWAP_BE32 (vh->dataClumpSize);
	vh->nextCatalogID = SWAP_BE32 (vh->nextCatalogID);
	vh->writeCount = SWAP_BE32 (vh->writeCount);
	vh->encodingsBitmap.hi = SWAP_BE32 (vh->encodingsBitmap.hi);
	vh->encodingsBitmap.lo = SWAP_BE32 (vh->encodingsBitmap.lo);
	SwapPlusFork (&vh->allocationFile);
	SwapPlusFork (&vh->extentsFile);
	SwapPlusFork (&vh->catalogFile);
	SwapPlusFork (&vh->attributesFile);
	SwapPlusFork (&vh->startupFile);
}

/* A Unicode name copied from a host-order HFSUniStr255 into a node. */
static void
SwapUniStr (HFSUniStr255 *s)
{
	int i;

	for (i = 0; i < s->length; i++)
		s->unicode[i] = SWAP_BE16 (s->unicode[i]);
	s->length = SWAP_BE16 (s->length);
}

#define SWAP_MDB(mdb)		SwapMDB (mdb)
#define SWAP_VH(vh)			SwapVH (vh)
#define SWAP_UNISTR(s)		SwapUniStr (s)

#else

#define SWAP_MDB(mdb)
#define SWAP_VH(vh)
#define SWAP_UNISTR(s)

#endif
"""

# (pattern, replacement, exact match count)
SUBS = [
    # the byte-order header, after the file's own last include
    (r'(#include "newfs_hfs\.h"\n)', r'\1#include "hfs_endian.h"\n', 1),
    # record offsets, and the swap routines right after that macro
    (r'(#define SetOffset\(buffer,nodesize,offset,record\)[^\n]*= )\(offset\)\)\n',
     lambda m: m.group(1) + 'SWAP_BE16 (offset))\n' + SWAP_CODE, 1),
    # MDB: swap around its two writes
    (r'\n(\t+)(err = WriteToDisk\(driveInfo, kMDBStart, kOneSector, mdb\);)',
     r'\n\1SWAP_MDB(mdb);\t\t\t\t\t\t\t\t// to disk order for its two writes\n\1\2', 1),
    (r'(err = WriteToDisk\(driveInfo, driveInfo->totalSectors - 2, kOneSector, mdb\);[^\n]*\n(\t+)M_ExitOnError\(err\);\n)',
     r'\1\2SWAP_MDB(mdb);\t\t\t\t\t\t\t\t// back to host order\n', 1),
    # volume header: the same
    (r'\n(\t+)(err = WriteToDisk\(driveInfo, 2, kOneSector, header\);)',
     r'\n\1SWAP_VH(header);\t\t\t\t\t\t\t\t// to disk order for its two writes\n\1\2', 1),
    (r'(err = WriteToDisk\(driveInfo, \(header->totalBlocks \* \(header->blockSize/kBytesPerSector\)\) - 2, kOneSector, header\);[^\n]*\n(\t+)M_ExitOnError\(err\);\n)',
     r'\1\2SWAP_VH(header);\t\t\t\t\t\t\t\t// back to host order\n', 1),
    # B-tree header node (InitBTreeHeader)
    (r'(bth->node\.numRecords\s*=\s*)3;', r'\1SWAP_BE16 (3);', 1),
    (r'(bth->node\.fLink\s*=\s*)2;', r'\1SWAP_BE32 (2);', 1),
    (r'(bth->node\.fLink\s*=\s*)1;', r'\1SWAP_BE32 (1);', 1),
    (r'(bth->treeDepth\s*=\s*)1;', r'\1SWAP_BE16 (1);', 1),
    (r'(bth->rootNode\s*=\s*)1;', r'\1SWAP_BE32 (1);', 1),
    (r'(bth->firstLeafNode\s*=\s*)1;', r'\1SWAP_BE32 (1);', 1),
    (r'(bth->lastLeafNode\s*=\s*)1;', r'\1SWAP_BE32 (1);', 1),
    (r'(bth->attributes\s*=\s*)attributes;', r'\1SWAP_BE32 (attributes);', 1),
    (r'(bth->leafRecords\s*=\s*)recordCount;', r'\1SWAP_BE32 (recordCount);', 1),
    (r'(bth->nodeSize\s*=\s*)nodeSize;', r'\1SWAP_BE16 (nodeSize);', 1),
    (r'(bth->maxKeyLength\s*=\s*)keySize;', r'\1SWAP_BE16 (keySize);', 1),
    (r'(bth->totalNodes\s*=\s*)nodeCount;', r'\1SWAP_BE32 (nodeCount);', 1),
    (r'(bth->freeNodes\s*=\s*)nodeCount - usedNodes;', r'\1SWAP_BE32 (nodeCount - usedNodes);', 1),
    (r'(bth->clumpSize\s*=\s*)clumpSize;', r'\1SWAP_BE32 (clumpSize);', 1),
    (r'(\*bitMapPtr = )~\(\(UInt32\) 0xFFFFFFFF >> usedNodes\);',
     r'\1SWAP_BE32 (~((UInt32) 0xFFFFFFFF >> usedNodes));', 1),
    (r'(\*offsetPtr(?:\+\+)?\s*=\s*)([^;\n]+);', r'\1SWAP_BE16 (\2);', 4),
    # leaf and map node descriptors
    (r'(nd->numRecords\s*=\s*)2;', r'\1SWAP_BE16 (2);', 2),
    (r'(nd->numRecords\s*=\s*)1;', r'\1SWAP_BE16 (1);', 1),
    (r'(nd->fLink\s*=\s*)\+\+firstMapNode;', r'\1SWAP_BE32 (++firstMapNode);', 1),
    # HFS root folder and thread (SetupCatalogRecords)
    (r'(cdk->parentID\s*=\s*)(kHFSRootParentID|kHFSRootFolderID);', r'\1SWAP_BE32 (\2);', 2),
    (r'(cdr->recordType\s*=\s*)kHFSFolderRecord;', r'\1SWAP_BE16 (kHFSFolderRecord);', 1),
    (r'(cdr->folderID\s*=\s*)kHFSRootFolderID;', r'\1SWAP_BE32 (kHFSRootFolderID);', 1),
    (r'(cdr->(?:createDate|modifyDate)\s*=\s*)timeStamp;', r'\1SWAP_BE32 (timeStamp);', 2),
    (r'(ctr->recordType\s*=\s*)kHFSFolderThreadRecord;', r'\1SWAP_BE16 (kHFSFolderThreadRecord);', 1),
    (r'(ctr->parentID\s*=\s*)kHFSRootParentID;', r'\1SWAP_BE32 (kHFSRootParentID);', 1),
    # HFS Plus root folder and thread (InitRootFolder)
    (r'(key->keyLength\s*=\s*)(kHFSPlusCatalogKeyMinimumLength \+ sizeof\(UniChar\) \* \(volName->length\));',
     r'\1SWAP_BE16 (\2);', 1),
    (r'(key->keyLength\s*=\s*)kHFSPlusCatalogKeyMinimumLength;', r'\1SWAP_BE16 (kHFSPlusCatalogKeyMinimumLength);', 1),
    (r'(key->parentID\s*=\s*)(kHFSRootParentID|kHFSRootFolderID);', r'\1SWAP_BE32 (\2);', 2),
    (r'(BlockMoveData\(volName, &key->nodeName, )key->keyLength - kHFSPlusCatalogKeyMinimumLength \+ sizeof\(UInt16\)\);',
     r'\1sizeof(UniChar) * (volName->length + 1));\n\tSWAP_UNISTR(&key->nodeName);', 1),
    (r'(offset \+= )key->keyLength( \+ 2;)', r'\1SWAP_BE16 (key->keyLength)\2', 2),
    (r'(folder->recordType\s*=\s*)kHFSPlusFolderRecord;', r'\1SWAP_BE16 (kHFSPlusFolderRecord);', 1),
    (r'(folder->folderID\s*=\s*)kHFSRootFolderID;', r'\1SWAP_BE32 (kHFSRootFolderID);', 1),
    (r'(folder->(?:createDate|contentModDate)\s*=\s*)timeStamp;', r'\1SWAP_BE32 (timeStamp);', 2),
    (r'(folder->textEncoding\s*=\s*)GetDefaultTextEncoding\(\);', r'\1SWAP_BE32 (GetDefaultTextEncoding());', 1),
    (r'(thread->recordType\s*=\s*)kHFSPlusFolderThreadRecord;', r'\1SWAP_BE16 (kHFSPlusFolderThreadRecord);', 1),
    (r'(thread->parentID\s*=\s*)kHFSRootParentID;', r'\1SWAP_BE32 (kHFSRootParentID);', 1),
    (r'(BlockMoveData\(volName, &thread->nodeName, sizeof\(UniChar\) \* \(volName->length \+ 1\)\);)',
     r'\1\n\tSWAP_UNISTR(&thread->nodeName);', 1),
]


def main(argv):
    path = argv[1]
    with open(path, encoding="latin-1", newline="") as f:
        text = f.read()
    for pat, rep, want in SUBS:
        got = len(re.findall(pat, text))
        if got != want:
            raise SystemExit("%s: %r matched %d times, expected %d" % (path, pat, got, want))
        text = re.sub(pat, rep, text)
    if "--dry-run" in argv:
        print("all %d substitutions match" % len(SUBS))
        return 0
    with open(path, "w", encoding="latin-1", newline="") as f:
        f.write(text)
    print("patched %s" % path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
