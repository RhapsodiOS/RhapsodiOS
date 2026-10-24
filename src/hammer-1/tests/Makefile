# Developer build and checks for the HAMMER tools, run natively on a
# Rhapsody build guest from a tree holding src/kernel-7 and src/hammer-1.
# The packaged build uses the pb_makefiles projects instead.
K = ../../kernel-7/bsd/hammer
CC = cc
CFLAGS = -O -I../common -I$(K)
COMMON = ../common/ondisk.c ../common/cache.c ../common/blockmap.c \
	 ../common/misc.c ../common/uuid.c ../common/compat.c \
	 ../common/crc32.c ../common/icrc32.c ../common/hammer_admit.c
HAMMER = ../hammer/hammer.c ../hammer/cmd_show.c ../hammer/cmd_blockmap.c
IMG = /var/tmp/hammer-newfs-show.img

all: newfs_hammer mount_hammer hammer hammer_walk hammer_io ns_ops

# Syscall checks run on a guest booted with a HAMMER kernel.
hammer_io: hammer_io.c $(K)/hammer_mount.h
	$(CC) -O -I$(K) hammer_io.c -o $@

# Portable tree manifest; the same source is compiled on DragonFly.
hammer_walk: hammer_walk.c
	$(CC) -O hammer_walk.c -o $@

# Namespace workload; the same source is compiled on DragonFly.
ns_ops: ns_ops.c
	$(CC) -O ns_ops.c -o $@

newfs_hammer: ../newfs_hammer/newfs_hammer.c $(COMMON)
	$(CC) $(CFLAGS) ../newfs_hammer/newfs_hammer.c $(COMMON) -o $@

mount_hammer: ../mount_hammer/mount_hammer.c $(K)/hammer_mount.h
	$(CC) -O -I$(K) ../mount_hammer/mount_hammer.c -o $@

hammer: $(HAMMER) $(COMMON)
	$(CC) $(CFLAGS) $(HAMMER) $(COMMON) -o $@

# The tools carry copies of kernel sources (CRC, admission); they must not drift.
mirrors:
	cmp ../common/crc32.c $(K)/crc32.c
	cmp ../common/icrc32.c $(K)/icrc32.c
	cmp ../common/hammer_admit.c $(K)/hammer_admit.c

check: mirrors all
	sh newfs-show.sh $(IMG)

# Cross-compile every tool source for ppc.  A plain guest has no ppc
# libSystem to link against; the rbuild universal package build links.
ppc:
	rm -rf ppc && mkdir ppc
	cd ppc && $(CC) -arch ppc $(CFLAGS:-I%=-I../%) -c \
	    ../../newfs_hammer/newfs_hammer.c ../../mount_hammer/mount_hammer.c \
	    $(HAMMER:../%=../../%) \
	    $(COMMON:../%=../../%)

clean:
	rm -rf newfs_hammer mount_hammer hammer hammer_walk hammer_io ns_ops ppc *.out

.PHONY: all mirrors check ppc clean
