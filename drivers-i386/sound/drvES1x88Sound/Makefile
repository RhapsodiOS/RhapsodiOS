#
# Makefile for ES1x88 Audio Driver
#

NAME = ES1x88AudioDriver

PROJECTVERSION = 1.0
LANGUAGE = English

LOCAL_RESOURCES =

GLOBAL_RESOURCES = Default.table

TOOLS = ES1x88AudioDriver_reloc.tproj

OTHERSRCS = Makefile.preamble Makefile Makefile.postamble README

MAKEFILEDIR = $(MAKEFILEPATH)/pb_makefiles
CODE_GEN_STYLE = DYNAMIC
MAKEFILE = aggregate.make
SOURCEMODE = 444

BUNDLE_EXTENSION = config

include $(MAKEFILEDIR)/platform.make

-include Makefile.preamble

include $(MAKEFILEDIR)/$(MAKEFILE)

-include Makefile.postamble

-include Makefile.dependencies
