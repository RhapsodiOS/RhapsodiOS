NAME = Floppy_reloc

CFILES = FloppyController.m IOFloppyDrive.m IOFloppyDisk.m

HFILES = FloppyController.h IOFloppyDrive.h IOFloppyDisk.h

MAKEFILEDIR = /NextDeveloper/Makefiles/app
MAKEFILE = tool.make

LIBS = -lDriver

OTHER_CFLAGS = -DDRIVER_PRIVATE

-include Makefile.preamble

include $(MAKEFILEDIR)/$(MAKEFILE)

-include Makefile.postamble

-include Makefile.dependencies
