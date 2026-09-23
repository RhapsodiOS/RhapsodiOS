# Unit tests for drvIntelE100's plain C, built and run on the build guest:
#   cd tests && gnumake check
# Same flags as drvAHCI's tests. -traditional-cpp makes cc-783.1 use GNU
# cpp instead of cpp-precomp. Under -ansi, cpp-precomp rewrites the system
# headers' __inline to inline, which gcc 2.7.2.1 then rejects (bsd/stdio.h
# __sputc, bsd/ctype.h __istype). -U__GNUC__ is not enough once ctype.h is
# included: it then wants an extern __istype that libc does not export.
CC = cc
CFLAGS = -ansi -pedantic -Wall -Werror -traditional-cpp
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
