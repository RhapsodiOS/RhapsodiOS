# Native: the Rhapsody cc on the build guest.  Portable (e.g. WSL gcc):
#   make check CPPFLAGS=-DHAMMER_PORTABLE_TEST
# Swap path on a little-endian host:
#   make check CPPFLAGS=-DHAMMER_TEST_SWAP
CC ?= cc
CPPFLAGS ?=
CFLAGS ?= -O2
CRC = ../crc32.c ../icrc32.c
HEADERS = ../hammer_port.h ../hammer_disk.h ../hammer_btree.h ../hammer_crc.h ../hammer_admit.h

all: swap_test admit_test

swap_test: swap_test.c $(CRC) $(HEADERS)
	$(CC) $(CPPFLAGS) $(CFLAGS) -I.. swap_test.c $(CRC) -o $@

admit_test: admit_test.c ../hammer_admit.c $(CRC) $(HEADERS)
	$(CC) $(CPPFLAGS) $(CFLAGS) -I.. admit_test.c ../hammer_admit.c $(CRC) -o $@

check: all
	./swap_test
	./admit_test

clean:
	rm -f swap_test admit_test

.PHONY: all check clean
