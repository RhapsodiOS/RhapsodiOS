NAME = ProcessViewer

PROJECTVERSION = 2.8
PROJECT_TYPE = Application

MFILES = Process.m UserIdCache.m ProcessType.m ProcessTableView.m ProcessControl.m Inspector.m

HFILES = Process.h ProcessType.h ProcessTableView.h ProcessControl.h Inspector.h InspectorLayout.h

OTHERSRCS = Makefile.preamble Makefile Makefile.postamble PB.project

MAKEFILEDIR = $(MAKEFILEPATH)/pb_makefiles
CODE_GEN_STYLE = DYNAMIC
MAKEFILE = app.make
NEXTSTEP_INSTALLDIR = /System/Administration
PDO_UNIX_INSTALLDIR = /System/Administration
LIBS =
DEBUG_LIBS = $(LIBS)
PROF_LIBS = $(LIBS)
FRAMEWORKS = AppKit Foundation

NEXTSTEP_OBJCPLUS_COMPILER = /usr/bin/cc
WINDOWS_OBJCPLUS_COMPILER = $(DEVDIR)/gcc
PDO_UNIX_OBJCPLUS_COMPILER = $(NEXTDEV_BIN)/gcc
NEXTSTEP_JAVA_COMPILER = /usr/bin/javac
WINDOWS_JAVA_COMPILER = $(JDKBINDIR)/javac.exe
PDO_UNIX_JAVA_COMPILER = $(NEXTDEV_BIN)/javac

include $(MAKEFILEDIR)/platform.make

-include Makefile.preamble

include $(MAKEFILEDIR)/$(MAKEFILE)

-include Makefile.postamble

-include Makefile.dependencies
