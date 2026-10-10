ifeq ($(origin CC),default)
CC = clang
endif
EXE ?=
CFLAGS ?= -std=gnu89 -Wall -Werror -Wno-gnu-folding-constant -m32 -I.. -I../../..

check: memmap_test$(EXE)
	./memmap_test$(EXE)

memmap_test$(EXE): memmap_test.c ../memmap.c ../memmap.h
	$(CC) $(CFLAGS) memmap_test.c ../memmap.c -o $@

clean:
	rm -f memmap_test memmap_test.exe

.PHONY: check clean
