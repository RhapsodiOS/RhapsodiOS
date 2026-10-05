CC ?= cc
CFLAGS ?= -O2 -Wall
all: ext2_io partition_info
ext2_io: ext2_io.c
	$(CC) $(CFLAGS) -I../../kernel-7/bsd ext2_io.c -o $@
partition_info: partition_info.c ../../kernel-7/bsd/dev/disk.h
	$(CC) $(CFLAGS) -I../../kernel-7/bsd partition_info.c -o $@
clean:
	rm -f ext2_io partition_info
