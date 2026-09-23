# Unit tests for drvIntelE100's plain C, built and run on the build guest:
#   cd tests && gnumake check
# Same flags as drvAHCI's tests. -U__GNUC__ works around a cc-783.1/gcc
# 2.7.2.1 bug: with -ansi it still takes bsd/stdio.h's "defined(__GNUC__)"
# branch (a static __inline __sputc) but then rejects __inline as a
# non-keyword identifier; undefining __GNUC__ picks stdio.h's portable
# macro-only __sputc fallback instead, so no driver code is affected.
CC = cc
CFLAGS = -ansi -pedantic -Wall -Werror -U__GNUC__
LKS = ../IntelE100.drvproj/IntelE100.lksproj
INCLUDES = -I. -I$(LKS)

.PHONY: all check test clean

all: e100_logic_test e100_hw_test

e100_logic_test: e100_logic_test.c $(LKS)/E100Logic.c $(LKS)/E100Logic.h $(LKS)/E100Regs.h
	$(CC) $(CFLAGS) $(INCLUDES) -o $@ e100_logic_test.c $(LKS)/E100Logic.c

e100_hw_test: e100_hw_test.c e100_test_ports.h $(LKS)/E100Hw.c $(LKS)/E100Hw.h $(LKS)/E100Port.h $(LKS)/E100Regs.h
	$(CC) $(CFLAGS) -DE100_HOST_TEST $(INCLUDES) -o $@ e100_hw_test.c $(LKS)/E100Hw.c

check: test

test: all
	./e100_logic_test
	./e100_hw_test

clean:
	rm -f e100_logic_test e100_hw_test
