/*
 * Copyright (c) 2007 The DragonFly Project.  All rights reserved.
 *
 * This code is derived from software contributed to The DragonFly Project
 * by Matthew Dillon <dillon@backplane.com>
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in
 *    the documentation and/or other materials provided with the
 *    distribution.
 * 3. Neither the name of The DragonFly Project nor the names of its
 *    contributors may be used to endorse or promote products derived
 *    from this software without specific, prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
 * FOR A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE
 * COPYRIGHT HOLDERS OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
 * INCIDENTAL, SPECIAL, EXEMPLARY OR CONSEQUENTIAL DAMAGES (INCLUDING,
 * BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED
 * AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
 * OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT
 * OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 */

#include "hammer_util.h"

static int64_t getsize(const char *str, int pw);
static void format_volume(volume_info_t volume, int nvols,const char *label);
static hammer_off_t format_root_directory(const char *label);
static uint64_t nowtime(void);
static void print_volume(const volume_info_t volume);
static void usage(int exit_code);
static void test_header_junk_size(int64_t size);
static void test_boot_area_size(int64_t size);
static void test_memory_log_size(int64_t size);
static void test_undo_buffer_size(int64_t size);

static int ForceOpt;
static int64_t HeaderJunkSize = -1;
static int64_t BootAreaSize = -1;
static int64_t MemoryLogSize = -1;
static int64_t UndoBufferSize;

#define GIG	(1024LL*1024*1024)

int
main(int ac, char **av)
{
	off_t total;
	off_t avg_vol_size;
	int ch;
	int i;
	int nvols;
	const char *label = NULL;
	volume_info_t volume;

	/*
	 * Sanity check basic filesystem structures.  No cookies for us
	 * if it gets broken!
	 */
	assert(sizeof(struct hammer_volume_ondisk) <= HAMMER_BUFSIZE);
	assert(sizeof(struct hammer_volume_ondisk) <= HAMMER_MIN_VOL_JUNK);
	assert(sizeof(struct hammer_blockmap_layer1) == 32);
	assert(sizeof(struct hammer_blockmap_layer2) == 16);

	/*
	 * Parse arguments
	 */
	while ((ch = getopt(ac, av, "dfEL:j:b:m:u:hC:V:")) != -1) {
		switch(ch) {
		case 'd':
			++DebugOpt;
			break;
		case 'f':
			ForceOpt = 1;
			break;
		case 'E':
			errx(1, "TRIM (-E) is not supported on Rhapsody");
			/* not reached */
			break;
		case 'L':
			label = optarg;
			break;
		case 'j': /* Not mentioned in newfs_hammer(8) */
			HeaderJunkSize = getsize(optarg, 2);
			test_header_junk_size(HeaderJunkSize);
			break;
		case 'b':
			BootAreaSize = getsize(optarg, 2);
			test_boot_area_size(BootAreaSize);
			break;
		case 'm':
			MemoryLogSize = getsize(optarg, 2);
			test_memory_log_size(MemoryLogSize);
			break;
		case 'u':
			UndoBufferSize = getsize(optarg, 2);
			test_undo_buffer_size(UndoBufferSize);
			break;
		case 'h':
			usage(0);
			/* not reached */
			break;
		case 'C':
			if (hammer_parse_cache_size(optarg) == -1) {
				usage(1);
				/* not reached */
			}
			break;
		case 'V':
			HammerVersion = strtol(optarg, NULL, 0);
			if (HammerVersion != HAMMER_VOL_VERSION_SEVEN) {
				errx(1, "Only HAMMER version %d is supported",
				     HAMMER_VOL_VERSION_SEVEN);
				/* not reached */
			}
			break;
		default:
			usage(1);
			/* not reached */
			break;
		}
	}
	ac -= optind;
	av += optind;
	nvols = ac;

	if (HammerVersion == (uint32_t)-1)
		HammerVersion = HAMMER_VOL_VERSION_DEFAULT;

	if (nvols == 0) {
		errx(1, "You must specify a special file (volume)");
		/* not reached */
	}
	if (nvols > 1) {
		errx(1, "Rhapsody HAMMER is single volume only");
		/* not reached */
	}

	if (label == NULL) {
		hwarnx("A filesystem label must be specified");
		usage(1);
		/* not reached */
	}

	/*
	 * Generate a filesystem id and lookup the filesystem type
	 */
	hammer_uuid_create(&Hammer_FSId);
	if (hammer_uuid_name_lookup(&Hammer_FSType, HAMMER_FSTYPE_STRING)) {
		errx(1, "uuids file does not have the DragonFly "
			"HAMMER filesystem type");
		/* not reached */
	}

	total = 0;
	for (i = 0; i < nvols; ++i) {
		volume = init_volume(av[i], O_RDWR, i);
		printf("Volume %d %s %-15s size %s\n",
			volume->vol_no, volume->type, volume->name,
			sizetostr(volume->size));
		total += volume->size;
	}

	/*
	 * Reserve space for (future) header junk, setup our poor-man's
	 * big-block allocator.  Note that the header junk space includes
	 * volume header which is 1928 bytes.
	 */
	if (HeaderJunkSize == -1)
		HeaderJunkSize = HAMMER_VOL_JUNK_SIZE;
	else if (HeaderJunkSize < (int64_t)sizeof(struct hammer_volume_ondisk))
		HeaderJunkSize = sizeof(struct hammer_volume_ondisk);
	HeaderJunkSize = HAMMER_BUFSIZE_DOALIGN(HeaderJunkSize);

	/*
	 * Calculate defaults for the boot area and memory log sizes,
	 * only if not specified by -b or -m option.
	 */
	avg_vol_size = total / nvols;
	if (BootAreaSize == -1)
		BootAreaSize = init_boot_area_size(BootAreaSize, avg_vol_size);
	if (MemoryLogSize == -1)
		MemoryLogSize = init_memory_log_size(MemoryLogSize, avg_vol_size);

	/*
	 * Format the volumes.  Format the root volume first so we can
	 * bootstrap the freemap.
	 */
	format_volume(get_root_volume(), nvols, label);
	for (i = 0; i < nvols; ++i) {
		if (i != HAMMER_ROOT_VOLNO)
			format_volume(get_volume(i), nvols, label);
	}

	print_volume(get_root_volume());

	flush_all_volumes();
	return(0);
}

static
void
print_volume(const volume_info_t volume)
{
	hammer_volume_ondisk_t ondisk;
	hammer_blockmap_t blockmap;
	hammer_off_t total = 0;
	int i, nvols;
	const char *name = NULL;
	char *fsidstr;

	ondisk = volume->ondisk;
	blockmap = &ondisk->vol0_blockmap[HAMMER_ZONE_UNDO_INDEX];

	nvols = (int32_t)hget32(ondisk->vol_count);
	for (i = 0; i < nvols; ++i) {
		volume_info_t p = get_volume(i);
		total += p->size;
		if (p->vol_no == HAMMER_ROOT_VOLNO) {
			assert(name == NULL);
			name = p->name;
		}
	}

	hammer_uuid_to_string(&Hammer_FSId, &fsidstr);

	printf("---------------------------------------------\n");
	printf("HAMMER version %d\n", HammerVersion);
	printf("%d volume%s total size %s\n",
		nvols, (nvols == 1 ? "" : "s"), sizetostr(total));
	printf("root-volume:         %s\n", name);
	if (DebugOpt) {
		printf("header-junk-size:    %s\n",
			sizetostr(hget64(ondisk->vol_bot_beg)));
	}
	printf("boot-area-size:      %s\n",
		sizetostr(hget64(ondisk->vol_mem_beg) -
			  hget64(ondisk->vol_bot_beg)));
	printf("memory-log-size:     %s\n",
		sizetostr(hget64(ondisk->vol_buf_beg) -
			  hget64(ondisk->vol_mem_beg)));
	printf("undo-buffer-size:    %s\n",
		sizetostr(HAMMER_OFF_LONG_ENCODE(hget64(blockmap->alloc_offset))));
	printf("total-pre-allocated: %s\n",
		sizetostr(HAMMER_OFF_SHORT_ENCODE(volume->vol_free_off)));
	printf("fsid:                %s\n", fsidstr);
	printf("\n");
	printf("NOTE: Please remember that you may have to manually set up a\n"
		"cron(8) job to prune and reblock the filesystem regularly.\n"
		"By default, the system automatically runs 'hammer cleanup'\n"
		"on a nightly basis.  The periodic.conf(5) variable\n"
		"'daily_clean_hammer_enable' can be unset to disable this.\n"
		"Also see 'man hammer' and 'man HAMMER' for more information.\n");
	if (total < 10*GIG) {
		printf("\nWARNING: The minimum UNDO/REDO FIFO is %s, "
			"you really should not\n"
			"try to format a HAMMER filesystem this small.\n",
			sizetostr(HAMMER_BIGBLOCK_SIZE *
			       HAMMER_MIN_UNDO_BIGBLOCKS));
	}
	if (total < 50*GIG) {
		printf("\nWARNING: HAMMER filesystems less than 50GB are "
			"not recommended!\n"
			"You may have to run 'hammer prune-everything' and "
			"'hammer reblock'\n"
			"quite often, even if using a nohistory mount.\n");
	}
}

static
void
usage(int exit_code)
{
	fprintf(stderr,
		"usage: newfs_hammer -L label [-Efh] [-b bootsize] [-m savesize] [-u undosize]\n"
		"                    [-C cachesize[:readahead]] [-V version] special ...\n"
	);
	exit(exit_code);
}

static
void
test_header_junk_size(int64_t size)
{
	if (size < HAMMER_MIN_VOL_JUNK) {
		if (ForceOpt == 0) {
			errx(1, "The minimum header junk size is %s",
				sizetostr(HAMMER_MIN_VOL_JUNK));
			/* not reached */
		} else {
			hwarnx("You have specified header junk size less than %s",
				sizetostr(HAMMER_MIN_VOL_JUNK));
		}
	} else if (size > HAMMER_MAX_VOL_JUNK) {
		errx(1, "The maximum header junk size is %s",
			sizetostr(HAMMER_MAX_VOL_JUNK));
		/* not reached */
	}
}

static
void
test_boot_area_size(int64_t size)
{
	if (size < HAMMER_BOOT_MINBYTES) {
		if (ForceOpt == 0) {
			errx(1, "The minimum boot area size is %s",
				sizetostr(HAMMER_BOOT_MINBYTES));
			/* not reached */
		} else {
			hwarnx("You have specified boot area size less than %s",
				sizetostr(HAMMER_BOOT_MINBYTES));
		}
	} else if (size > HAMMER_BOOT_MAXBYTES) {
		errx(1, "The maximum boot area size is %s",
			sizetostr(HAMMER_BOOT_MAXBYTES));
		/* not reached */
	}
}

static
void
test_memory_log_size(int64_t size)
{
	if (size < HAMMER_MEM_MINBYTES) {
		if (ForceOpt == 0) {
			errx(1, "The minimum memory log size is %s",
				sizetostr(HAMMER_MEM_MINBYTES));
			/* not reached */
		} else {
			hwarnx("You have specified memory log size less than %s",
				sizetostr(HAMMER_MEM_MINBYTES));
		}
	} else if (size > HAMMER_MEM_MAXBYTES) {
		errx(1, "The maximum memory log size is %s",
			sizetostr(HAMMER_MEM_MAXBYTES));
		/* not reached */
	}
}

static
void
test_undo_buffer_size(int64_t size)
{
	int64_t minbuf, maxbuf;

	minbuf = HAMMER_BIGBLOCK_SIZE * HAMMER_MIN_UNDO_BIGBLOCKS;
	maxbuf = HAMMER_BIGBLOCK_SIZE * HAMMER_MAX_UNDO_BIGBLOCKS;

	if (size < minbuf) {
		if (ForceOpt == 0) {
			errx(1, "The minimum UNDO/REDO FIFO size is %s",
				sizetostr(minbuf));
			/* not reached */
		} else {
			hwarnx("You have specified an UNDO/REDO FIFO size less "
				"than %s, which may lead to VFS panics",
				sizetostr(minbuf));
		}
	} else if (size > maxbuf) {
		errx(1, "The maximum UNDO/REDO FIFO size is %s",
			sizetostr(maxbuf));
		/* not reached */
	}
}

/*
 * Convert a string to a 64 bit signed integer with various requirements.
 */
static
int64_t
getsize(const char *str, int powerof2)
{
	int64_t val;
	char *ptr;

	val = strtoll(str, &ptr, 0);
	switch(*ptr) {
	case 't':
	case 'T':
		val *= 1024;
		/* fall through */
	case 'g':
	case 'G':
		val *= 1024;
		/* fall through */
	case 'm':
	case 'M':
		val *= 1024;
		/* fall through */
	case 'k':
	case 'K':
		val *= 1024;
		break;
	default:
		errx(1, "Unknown suffix in number '%s'", str);
		/* not reached */
	}

	if (ptr[1]) {
		errx(1, "Unknown suffix in number '%s'", str);
		/* not reached */
	}
	if ((powerof2 & 1) && (val ^ (val - 1)) != ((val << 1) - 1)) {
		errx(1, "Value not power of 2: %s", str);
		/* not reached */
	}
	if ((powerof2 & 2) && (val & HAMMER_BUFMASK)) {
		errx(1, "Value not an integral multiple of %dK: %s",
		     HAMMER_BUFSIZE / 1024, str);
		/* not reached */
	}
	return(val);
}

/*
 * Generate a transaction id.  Transaction ids are no longer time-based.
 * Put the nail in the coffin by not making the first one time-based.
 *
 * We could start at 1 here but start at 2^32 to reserve a small domain for
 * possible future use.
 */
static
hammer_tid_t
createtid(void)
{
	static hammer_tid_t lasttid;

	if (lasttid == 0)
		lasttid = 0x0000000100000000ULL;
	return(lasttid++);
}

static
uint64_t
nowtime(void)
{
	struct timeval tv;
	uint64_t xtime;

	gettimeofday(&tv, NULL);
	xtime = tv.tv_sec * 1000000LL + tv.tv_usec;
	return(xtime);
}


/*
 * Format a HAMMER volume.
 */
static
void
format_volume(volume_info_t volume, int nvols, const char *label)
{
	volume_info_t root_vol;
	hammer_volume_ondisk_t ondisk;
	int64_t freeblks;
	int64_t freebytes;
	int64_t vol_buf_size;
	hammer_off_t vol_alloc;
	int i;

	/*
	 * Initialize basic information in the on-disk volume structure.
	 */
	ondisk = volume->ondisk;

	ondisk->vol_fsid = Hammer_FSId;
	ondisk->vol_fstype = Hammer_FSType;
	snprintf(ondisk->vol_label, sizeof(ondisk->vol_label), "%s", label);
	ondisk->vol_no = hmk32(volume->vol_no);
	ondisk->vol_count = hmk32(nvols);
	ondisk->vol_version = hmk32(HammerVersion);

	vol_alloc = HeaderJunkSize;
	ondisk->vol_bot_beg = hmk64(vol_alloc);
	vol_alloc += BootAreaSize;
	ondisk->vol_mem_beg = hmk64(vol_alloc);
	vol_alloc += MemoryLogSize;

	/*
	 * The remaining area is the zone 2 buffer allocation area.
	 */
	ondisk->vol_buf_beg = hmk64(vol_alloc);
	ondisk->vol_buf_end = hmk64(volume->size & ~(int64_t)HAMMER_BUFMASK);
	vol_buf_size = HAMMER_VOL_BUF_SIZE(ondisk);

	if (vol_buf_size < (int64_t)sizeof(*ondisk)) {
		errx(1, "volume %d %s is too small to hold the volume header",
		     volume->vol_no, volume->name);
		/* not reached */
	}
	if ((vol_buf_size & ~HAMMER_OFF_SHORT_MASK) != 0) {
		errx(1, "volume %d %s is too large", volume->vol_no, volume->name);
		/* not reached */
	}

	ondisk->vol_rootvol = hmk32(HAMMER_ROOT_VOLNO);
	ondisk->vol_signature = hmk64(HAMMER_FSBUF_VOLUME);

	volume->vol_free_off = HAMMER_ENCODE_RAW_BUFFER(volume->vol_no, 0);
	volume->vol_free_end = HAMMER_ENCODE_RAW_BUFFER(volume->vol_no,
				vol_buf_size & ~HAMMER_BIGBLOCK_MASK64);

	/*
	 * Format the root volume.
	 */
	if (volume->vol_no == HAMMER_ROOT_VOLNO) {
		/*
		 * Check freemap counts before formatting
		 */
		freeblks = count_freemap(volume);
		freebytes = freeblks * HAMMER_BIGBLOCK_SIZE64;
		if (freebytes < 10*GIG && ForceOpt == 0) {
			errx(1, "Cannot create a HAMMER filesystem less than 10GB "
				"unless you use -f\n(for the size of Volume %d).  "
				"HAMMER filesystems less than 50GB are not "
				"recommended.", HAMMER_ROOT_VOLNO);
			/* not reached */
		}

		/*
		 * Starting TID
		 */
		ondisk->vol0_next_tid = hmk64(createtid());

		/*
		 * Format freemap.  vol0_stat_freebigblocks is
		 * the number of big-blocks available for anything
		 * other than freemap zone at this point.
		 */
		format_freemap(volume);
		assert(hget64(ondisk->vol0_stat_freebigblocks) == 0);
		ondisk->vol0_stat_freebigblocks = hmk64(initialize_freemap(volume));

		/*
		 * Format zones that are mapped to zone-2.
		 */
		for (i = 0; i < HAMMER_MAX_ZONES; ++i) {
			if (hammer_is_index_record(i))
				format_blockmap(volume, i, 0);
		}

		/*
		 * Format undo zone.  Formatting decrements
		 * vol0_stat_freebigblocks whenever a new big-block
		 * is allocated for undo zone.
		 */
		format_undomap(volume, &UndoBufferSize);
		assert(hget64(ondisk->vol0_stat_bigblocks) == 0);
		ondisk->vol0_stat_bigblocks = ondisk->vol0_stat_freebigblocks;

		/*
		 * Format the root directory.  Formatting decrements
		 * vol0_stat_freebigblocks whenever a new big-block
		 * is allocated for required zones.
		 */
		ondisk->vol0_btree_root = hmk64(format_root_directory(label));
		/* root inode */
		ondisk->vol0_stat_inodes =
			hmk64(hget64(ondisk->vol0_stat_inodes) + 1);
	} else {
		/* Single volume only: main() refuses more than one. */
		root_vol = get_root_volume();
		freeblks = 0;
		assert(root_vol == volume);
	}
}

/*
 * Format the root directory.
 */
static
hammer_off_t
format_root_directory(const char *label)
{
	hammer_off_t btree_off;
	hammer_off_t idata_off;
	hammer_off_t pfsd_off;
	hammer_tid_t create_tid;
	hammer_node_ondisk_t bnode;
	hammer_inode_data_t idata;
	hammer_pseudofs_data_t pfsd;
	buffer_info_t data_buffer0 = NULL;
	buffer_info_t data_buffer1 = NULL;
	buffer_info_t data_buffer2 = NULL;
	hammer_btree_elm_t elm;
	uint64_t xtime;

	/*
	 * Allocate zero-filled root btree node, inode and pfs
	 */
	bnode = alloc_btree_node(&btree_off, &data_buffer0);
	idata = alloc_meta_element(&idata_off, sizeof(*idata), &data_buffer1);
	pfsd = alloc_meta_element(&pfsd_off, sizeof(*pfsd), &data_buffer2);
	create_tid = createtid();
	xtime = nowtime();

	/*
	 * Populate the inode data and inode record for the root directory.
	 */
	idata->version = hmk16(HAMMER_INODE_DATA_VERSION);
	idata->mode = hmk16(0755);
	idata->ctime = hmk64(xtime);
	idata->mtime = hmk64(xtime);
	idata->atime = hmk64(xtime);
	idata->obj_type = HAMMER_OBJTYPE_DIRECTORY;
	idata->size = hmk64(0);
	idata->nlinks = hmk64(1);
	if (HammerVersion >= HAMMER_VOL_VERSION_TWO)
		idata->cap_flags |= HAMMER_INODE_CAP_DIR_LOCAL_INO;
	if (HammerVersion >= HAMMER_VOL_VERSION_SIX)
		idata->cap_flags |= HAMMER_INODE_CAP_DIRHASH_ALG1;

	/*
	 * Populate the PFS data for the root PFS.
	 */
	pfsd->sync_low_tid = hmk64(1);
	pfsd->sync_beg_tid = hmk64(0);
	pfsd->sync_end_tid = hmk64(0); /* overridden by vol0_next_tid on root PFS */
	pfsd->shared_uuid = Hammer_FSId;
	pfsd->unique_uuid = Hammer_FSId;
	pfsd->mirror_flags = hmk32(0);
	snprintf(pfsd->label, sizeof(pfsd->label), "%s", label);

	/*
	 * Create the root of the B-Tree.  The root is a leaf node so we
	 * do not have to worry about boundary elements.
	 */
	bnode->parent = hmk64(0);  /* no parent */
	bnode->count = hmk32(2);
	bnode->type = HAMMER_BTREE_TYPE_LEAF;
	bnode->mirror_tid = hmk64(0);

	/*
	 * Create the first node element for the inode.
	 */
	elm = &bnode->elms[0];
	elm->leaf.base.btype = HAMMER_BTREE_TYPE_RECORD;
	elm->leaf.base.localization = hmk32(HAMMER_DEF_LOCALIZATION |
					    HAMMER_LOCALIZE_INODE);
	elm->leaf.base.obj_id = hmk64(HAMMER_OBJID_ROOT);
	elm->leaf.base.key = hmk64(0);
	elm->leaf.base.create_tid = hmk64(create_tid);
	elm->leaf.base.delete_tid = hmk64(0);
	elm->leaf.base.rec_type = hmk16(HAMMER_RECTYPE_INODE);
	elm->leaf.base.obj_type = HAMMER_OBJTYPE_DIRECTORY;
	elm->leaf.create_ts = hmk32((uint32_t)time(NULL));

	elm->leaf.data_offset = hmk64(idata_off);
	elm->leaf.data_len = hmk32(sizeof(*idata));
	hammer_crc_set_leaf(HammerVersion, idata, &elm->leaf);

	/*
	 * Create the second node element for the PFS data.
	 * This is supposed to be a record part of the root ip (inode),
	 * so it should have the same obj_type value as above.
	 */
	elm = &bnode->elms[1];
	elm->leaf.base.btype = HAMMER_BTREE_TYPE_RECORD;
	elm->leaf.base.localization = hmk32(HAMMER_DEF_LOCALIZATION |
					    HAMMER_LOCALIZE_MISC);
	elm->leaf.base.obj_id = hmk64(HAMMER_OBJID_ROOT);
	elm->leaf.base.key = hmk64(0);
	elm->leaf.base.create_tid = hmk64(create_tid);
	elm->leaf.base.delete_tid = hmk64(0);
	elm->leaf.base.rec_type = hmk16(HAMMER_RECTYPE_PFS);
	elm->leaf.base.obj_type = HAMMER_OBJTYPE_DIRECTORY;
	elm->leaf.create_ts = hmk32((uint32_t)time(NULL));

	elm->leaf.data_offset = hmk64(pfsd_off);
	elm->leaf.data_len = hmk32(sizeof(*pfsd));

	hammer_crc_set_leaf(HammerVersion, pfsd, &elm->leaf);

	hammer_crc_set_btree(HammerVersion, bnode);

	rel_buffer(data_buffer0);
	rel_buffer(data_buffer1);
	rel_buffer(data_buffer2);

	return(btree_off);
}
