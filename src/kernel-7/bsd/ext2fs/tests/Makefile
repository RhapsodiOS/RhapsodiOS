# Native: use the target compiler and installed/exported BSD headers.
# Portable: CPPFLAGS may inject host_compat.h; disk structs stay production.
CC ?= cc
CPPFLAGS ?=
CFLAGS ?= -O2 -Wall
EXE ?=
HEADERS = ../ext2_disk.h ../ext2_fs.h ../ext2fs_dinode.h ../ext2fs_dir.h ../ext2_bitmap.h

all: disk_test$(EXE) swap_test$(EXE)

disk_test$(EXE): disk_test.c ../ext2_disk.c ../ext2fs_bswap.c $(HEADERS)
	$(CC) $(CPPFLAGS) $(CFLAGS) -I.. disk_test.c ../ext2_disk.c ../ext2fs_bswap.c -o $@

# Compile the real swap functions on little-endian hosts too. This does not
# simulate a target ABI or replace the required native PPC disk test.
swap_test$(EXE): swap_test.c ../ext2fs_bswap.c $(HEADERS)
	$(CC) $(CPPFLAGS) $(CFLAGS) -DEXT2_TEST_SWAP -I.. swap_test.c ../ext2fs_bswap.c -o $@

check: all
	./disk_test$(EXE)
	./swap_test$(EXE)

clean:
	rm -f disk_test disk_test.exe swap_test swap_test.exe adapter_test bmap_test

.PHONY: all check clean

# Native adapter test deliberately uses the actual shared kernel structures.
adapter_test: adapter_test.c ../ext2fs_rhapsody.c ../ext2fs_rhapsody.h $(HEADERS)
	$(CC) $(CFLAGS) -Wno-precomp -I../.. adapter_test.c ../ext2fs_rhapsody.c ../ext2_disk.c ../ext2fs_bswap.c -o $@
check-adapter: adapter_test
	./adapter_test

# The native buffer test compiles actual ext2 and UFS traversal with local ABI
# headers. Only process accounting and device I/O are test boundaries.
KERNEL_TEST_BUILD = ../../../BUILD/RELEASE_I386
KERNEL_TEST_CPPFLAGS = -D_KERNEL -DKERNEL -I$(KERNEL_TEST_BUILD) -I../../.. -I../.. -I../../../machdep -I$(NEXT_ROOT)/System/Library/Frameworks/System.framework/PrivateHeaders
bmap_test: bmap_test.c bmap_ext2.c bmap_ufs.c bmap_test_env.h ../ext2fs_bmap.c ../../ufs/ufs/ufs_bmap.c ../ext2fs_rhapsody.c ../ext2fs_extern.h ../ext2fs_rhapsody.h $(HEADERS)
	$(CC) $(CFLAGS) -Wno-precomp $(KERNEL_TEST_CPPFLAGS) bmap_test.c bmap_ext2.c bmap_ufs.c ../ext2fs_rhapsody.c ../ext2_disk.c ../ext2fs_bswap.c -o $@
check-bmap: bmap_test
	./bmap_test
