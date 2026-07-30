CC = cc
CFLAGS = -ansi -pedantic -Wall -Werror
INCLUDES = -I../AHCI.drvproj/AHCI.lksproj

ahci_command_test: ahci_command_test.c ../AHCI.drvproj/AHCI.lksproj/AHCICommand.c ../AHCI.drvproj/AHCI.lksproj/AHCICommand.h ../AHCI.drvproj/AHCI.lksproj/AHCIRegs.h
	$(CC) $(CFLAGS) $(INCLUDES) -o $@ ahci_command_test.c ../AHCI.drvproj/AHCI.lksproj/AHCICommand.c

test: ahci_command_test
	./ahci_command_test

clean:
	rm -f ahci_command_test
