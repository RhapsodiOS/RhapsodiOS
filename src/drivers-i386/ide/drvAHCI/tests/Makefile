CC = cc
CFLAGS = -ansi -pedantic -Wall -Werror
INCLUDES = -I../AHCI.drvproj/AHCI.lksproj \
	-I../../../../kernel-7/bsd/dev \
	-I../../../../kernel-7/machdep/i386

.PHONY: all check test clean

all: ahci_command_test ahci_state_test ata_hd_registry_test ata_hd_root_test eide_registry_migration_test

ahci_command_test: ahci_command_test.c ../AHCI.drvproj/AHCI.lksproj/AHCICommand.c ../AHCI.drvproj/AHCI.lksproj/AHCICommand.h ../AHCI.drvproj/AHCI.lksproj/AHCIRegs.h
	$(CC) $(CFLAGS) $(INCLUDES) -o $@ ahci_command_test.c ../AHCI.drvproj/AHCI.lksproj/AHCICommand.c

ahci_state_test: ahci_state_test.c ../AHCI.drvproj/AHCI.lksproj/AHCIState.c ../AHCI.drvproj/AHCI.lksproj/AHCIState.h
	$(CC) $(CFLAGS) $(INCLUDES) -o $@ ahci_state_test.c ../AHCI.drvproj/AHCI.lksproj/AHCIState.c

ata_hd_registry_test: ata_hd_registry_test.c ../../../../kernel-7/bsd/dev/ata_hd_registry_core.c ../../../../kernel-7/bsd/dev/ata_hd_registry_core.h
	$(CC) $(CFLAGS) $(INCLUDES) -o $@ ata_hd_registry_test.c ../../../../kernel-7/bsd/dev/ata_hd_registry_core.c

ata_hd_root_test: ata_hd_root_test.c ../../../../kernel-7/machdep/i386/ata_hd_root.c ../../../../kernel-7/machdep/i386/ata_hd_root.h ../../../../kernel-7/bsd/dev/ata_hd_registry_core.h
	$(CC) $(CFLAGS) $(INCLUDES) -o $@ ata_hd_root_test.c ../../../../kernel-7/machdep/i386/ata_hd_root.c

eide_registry_migration_test: eide_registry_migration_test.c
	$(CC) $(CFLAGS) -o $@ eide_registry_migration_test.c

check: test

test: all
	./ahci_command_test
	./ahci_state_test
	./ata_hd_registry_test
	./ata_hd_root_test
	./eide_registry_migration_test

clean:
	rm -f ahci_command_test ahci_state_test ata_hd_registry_test ata_hd_root_test eide_registry_migration_test
