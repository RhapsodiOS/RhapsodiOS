CC = "C:\\Program Files\\LLVM\\bin\\clang.exe"
CFLAGS = -std=c89 -pedantic -Wall -Wextra -Wconversion -Wsign-conversion -Werror
INCLUDES = -I../AHCI.drvproj/AHCI.lksproj

ahci_command_test.exe: ahci_command_test.c ../AHCI.drvproj/AHCI.lksproj/AHCICommand.c ../AHCI.drvproj/AHCI.lksproj/AHCICommand.h ../AHCI.drvproj/AHCI.lksproj/AHCIRegs.h
	$(CC) $(CFLAGS) $(INCLUDES) -o $@ ahci_command_test.c ../AHCI.drvproj/AHCI.lksproj/AHCICommand.c

ahci_state_test.exe: ahci_state_test.c ../AHCI.drvproj/AHCI.lksproj/AHCIState.c ../AHCI.drvproj/AHCI.lksproj/AHCIState.h
	$(CC) $(CFLAGS) $(INCLUDES) -o $@ ahci_state_test.c ../AHCI.drvproj/AHCI.lksproj/AHCIState.c

test: ahci_command_test.exe ahci_state_test.exe
	./ahci_command_test.exe
	./ahci_state_test.exe

clean:
	rm -f ahci_command_test.exe ahci_state_test.exe
