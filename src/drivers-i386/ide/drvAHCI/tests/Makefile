CC = cc
CFLAGS = -ansi -pedantic -Wall -Werror
INCLUDES = -I../AHCI.drvproj/AHCI.lksproj

.PHONY: all check test clean

all: ahci_command_test ahci_state_test

ahci_command_test: ahci_command_test.c ../AHCI.drvproj/AHCI.lksproj/AHCICommand.c ../AHCI.drvproj/AHCI.lksproj/AHCICommand.h ../AHCI.drvproj/AHCI.lksproj/AHCIRegs.h
	$(CC) $(CFLAGS) $(INCLUDES) -o $@ ahci_command_test.c ../AHCI.drvproj/AHCI.lksproj/AHCICommand.c

ahci_state_test: ahci_state_test.c ../AHCI.drvproj/AHCI.lksproj/AHCIState.c ../AHCI.drvproj/AHCI.lksproj/AHCIState.h
	$(CC) $(CFLAGS) $(INCLUDES) -o $@ ahci_state_test.c ../AHCI.drvproj/AHCI.lksproj/AHCIState.c

check: test

test: all
	./ahci_command_test
	./ahci_state_test

clean:
	rm -f ahci_command_test ahci_state_test
