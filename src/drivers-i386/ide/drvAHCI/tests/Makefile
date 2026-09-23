# -traditional-cpp makes cc-783.1 use GNU cpp instead of cpp-precomp. Under
# -ansi, cpp-precomp rewrites the system headers' __inline to inline, which
# gcc 2.7.2.1 then rejects (bsd/stdio.h __sputc, bsd/ctype.h __istype).
# -U__GNUC__ is not enough: ctype.h then wants an extern __istype that libc
# does not export.
CC = cc
CFLAGS = -ansi -pedantic -Wall -Werror -traditional-cpp
INCLUDES = -I../AHCI.drvproj/AHCI.lksproj \
	-I../../../../kernel-7/bsd/dev \
	-I../../../../kernel-7/machdep/i386

.PHONY: all check test clean

all: ahci_command_test ahci_atapi_test ahci_state_test ahci_hba_test ahci_pci_test ahci_port_test ahci_scaffold_contract_test ahci_task10_contract_test ahci_disk_test ahci_task11_contract_test ahci_task12_contract_test ata_hd_registry_test ata_hd_root_test eide_registry_migration_test eide_ioctl_validation_test

ahci_command_test: ahci_command_test.c ../AHCI.drvproj/AHCI.lksproj/AHCICommand.c ../AHCI.drvproj/AHCI.lksproj/AHCICommand.h ../AHCI.drvproj/AHCI.lksproj/AHCIRegs.h
	$(CC) $(CFLAGS) $(INCLUDES) -o $@ ahci_command_test.c ../AHCI.drvproj/AHCI.lksproj/AHCICommand.c

ahci_atapi_test: ahci_atapi_test.c ../AHCI.drvproj/AHCI.lksproj/AHCIATAPILogic.c ../AHCI.drvproj/AHCI.lksproj/AHCIATAPILogic.h ../AHCI.drvproj/AHCI.lksproj/AHCICommand.c
	$(CC) $(CFLAGS) $(INCLUDES) -o $@ ahci_atapi_test.c ../AHCI.drvproj/AHCI.lksproj/AHCIATAPILogic.c ../AHCI.drvproj/AHCI.lksproj/AHCICommand.c

ahci_state_test: ahci_state_test.c ../AHCI.drvproj/AHCI.lksproj/AHCIState.c ../AHCI.drvproj/AHCI.lksproj/AHCIState.h
	$(CC) $(CFLAGS) $(INCLUDES) -o $@ ahci_state_test.c ../AHCI.drvproj/AHCI.lksproj/AHCIState.c

ahci_hba_test: ahci_hba_test.c ../AHCI.drvproj/AHCI.lksproj/AHCIHBA.c ../AHCI.drvproj/AHCI.lksproj/AHCIHBA.h ../AHCI.drvproj/AHCI.lksproj/AHCIRegs.h
	$(CC) $(CFLAGS) $(INCLUDES) -o $@ ahci_hba_test.c ../AHCI.drvproj/AHCI.lksproj/AHCIHBA.c

ahci_pci_test: ahci_pci_test.c ../AHCI.drvproj/AHCI.lksproj/AHCIPCI.c ../AHCI.drvproj/AHCI.lksproj/AHCIPCI.h ../AHCI.drvproj/AHCI.lksproj/AHCIRegs.h
	$(CC) $(CFLAGS) $(INCLUDES) -o $@ ahci_pci_test.c ../AHCI.drvproj/AHCI.lksproj/AHCIPCI.c

ahci_port_test: ahci_port_test.c ../AHCI.drvproj/AHCI.lksproj/AHCIPortLogic.c ../AHCI.drvproj/AHCI.lksproj/AHCIPortLogic.h ../AHCI.drvproj/AHCI.lksproj/AHCIRegs.h ../AHCI.drvproj/AHCI.lksproj/AHCIState.h ../AHCI.drvproj/AHCI.lksproj/AHCICommand.c
	$(CC) $(CFLAGS) $(INCLUDES) -o $@ ahci_port_test.c ../AHCI.drvproj/AHCI.lksproj/AHCIPortLogic.c ../AHCI.drvproj/AHCI.lksproj/AHCIState.c ../AHCI.drvproj/AHCI.lksproj/AHCICommand.c

ahci_scaffold_contract_test: ahci_scaffold_contract_test.c
	$(CC) $(CFLAGS) -o $@ ahci_scaffold_contract_test.c

ahci_task10_contract_test: ahci_task10_contract_test.c
	$(CC) $(CFLAGS) -o $@ ahci_task10_contract_test.c

ahci_disk_test: ahci_disk_test.c ../AHCI.drvproj/AHCI.lksproj/AHCIDiskLogic.c ../AHCI.drvproj/AHCI.lksproj/AHCIDiskLogic.h
	$(CC) $(CFLAGS) $(INCLUDES) -o $@ ahci_disk_test.c ../AHCI.drvproj/AHCI.lksproj/AHCIDiskLogic.c

ahci_task11_contract_test: ahci_task11_contract_test.c
	$(CC) $(CFLAGS) -o $@ ahci_task11_contract_test.c

ahci_task12_contract_test: ahci_task12_contract_test.c
	$(CC) $(CFLAGS) -o $@ ahci_task12_contract_test.c

ata_hd_registry_test: ata_hd_registry_test.c ../../../../kernel-7/bsd/dev/ata_hd_registry_core.c ../../../../kernel-7/bsd/dev/ata_hd_registry_core.h
	$(CC) $(CFLAGS) $(INCLUDES) -o $@ ata_hd_registry_test.c ../../../../kernel-7/bsd/dev/ata_hd_registry_core.c

ata_hd_root_test: ata_hd_root_test.c ../../../../kernel-7/machdep/i386/ata_hd_root.c ../../../../kernel-7/machdep/i386/ata_hd_root.h ../../../../kernel-7/bsd/dev/ata_hd_registry_core.h
	$(CC) $(CFLAGS) $(INCLUDES) -o $@ ata_hd_root_test.c ../../../../kernel-7/machdep/i386/ata_hd_root.c

eide_registry_migration_test: eide_registry_migration_test.c
	$(CC) $(CFLAGS) -o $@ eide_registry_migration_test.c

eide_ioctl_validation_test: eide_ioctl_validation_test.c ../../drvEIDE/EIDE.drvproj/EIDE.lksproj/EIDEIoctlValidation.c ../../drvEIDE/EIDE.drvproj/EIDE.lksproj/EIDEIoctlValidation.h
	$(CC) $(CFLAGS) -I../../drvEIDE/EIDE.drvproj/EIDE.lksproj -o $@ eide_ioctl_validation_test.c ../../drvEIDE/EIDE.drvproj/EIDE.lksproj/EIDEIoctlValidation.c

check: test

test: all
	./ahci_command_test
	./ahci_atapi_test
	./ahci_state_test
	./ahci_hba_test
	./ahci_pci_test
	./ahci_port_test
	./ahci_scaffold_contract_test
	./ahci_task10_contract_test
	./ahci_disk_test
	./ahci_task11_contract_test
	./ahci_task12_contract_test
	./ata_hd_registry_test
	./ata_hd_root_test
	./eide_registry_migration_test
	./eide_ioctl_validation_test

clean:
	rm -f ahci_command_test ahci_atapi_test ahci_state_test ahci_hba_test ahci_pci_test ahci_port_test ahci_scaffold_contract_test ahci_task10_contract_test ahci_disk_test ahci_task11_contract_test ahci_task12_contract_test ata_hd_registry_test ata_hd_root_test eide_registry_migration_test eide_ioctl_validation_test
