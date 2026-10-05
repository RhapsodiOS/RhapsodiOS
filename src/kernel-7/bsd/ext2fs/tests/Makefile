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
	rm -f disk_test disk_test.exe swap_test swap_test.exe

.PHONY: all check clean
