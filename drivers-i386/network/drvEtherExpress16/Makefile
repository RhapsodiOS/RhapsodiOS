NAME = EtherExpress16
DRIVERTYPE = reloc

OFILES = EtherExpress16_reloc.o EtherExpress16KernelServerInstance.o

CFILES = EtherExpress16.m EtherExpress16KernelServerInstance.m

INSTALL_BIN_DIR = /usr/Devices/System.config

LDFLAGS = -noseglinkedit
LIBS = -lDriver

include ../CoreOSMakefiles-1/ReleaseControl/Common.make
include ../CoreOSMakefiles-1/ReleaseControl/Driver.make
