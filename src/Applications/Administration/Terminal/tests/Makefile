CC ?= cc
CFLAGS ?= -O0 -g
ARCH_FLAGS ?=
ifeq ($(OS),Windows_NT)
EXEEXT = .exe
endif
STORAGE_SOURCES = storage.c ../Chunk.c ../FindCharacters.c ../PrintLine.c \
	../VT100Args.c ../VT100String.c ../VT100Parser.c ../VT100State.c \
	../TerminalScreen.c ../PathCompress.c ../WordBoundary.c ../WordSelection.c \
	../PasteText.c

.PHONY: all storage filer fstream debugdps integerstring shellexec shellpolicy flagmap processinfo processnames identity windowtitle printline servicemanagerstate scrollback savepanelmode launch clean
all: storage filer fstream debugdps integerstring shellexec shellpolicy flagmap processinfo processnames identity windowtitle printline servicemanagerstate scrollback savepanelmode launch
filer: filer.c ../Filer.c ../Chunk.c ../Filer.h ../Chunk.h
	$(CC) $(ARCH_FLAGS) $(CFLAGS) -o filer$(EXEEXT) filer.c ../Filer.c ../Chunk.c
	./filer$(EXEEXT)
storage: $(STORAGE_SOURCES) ../Chunk.h ../FindCharacters.h ../PrintLine.h \
	../VT100Args.h ../VT100String.h ../VT100Parser.h ../VT100State.h \
	../TerminalScreen.h ../PathCompress.h ../WordBoundary.h ../WordSelection.h \
	../PasteText.h
	$(CC) $(ARCH_FLAGS) $(CFLAGS) -o storage$(EXEEXT) $(STORAGE_SOURCES)
	./storage$(EXEEXT)
fstream: fstream.c ../FindCharacters.c ../FindCharacters.h ../Chunk.c ../Chunk.h
	$(CC) $(ARCH_FLAGS) $(CFLAGS) -o fstream$(EXEEXT) fstream.c ../FindCharacters.c ../Chunk.c
	./fstream$(EXEEXT)
debugdps: debugdps.c ../DebugDPS.m ../DebugDPS.h
	$(CC) $(ARCH_FLAGS) $(CFLAGS) -D__MACH__ -x objective-c -I../../../../Kits -o debugdps$(EXEEXT) debugdps.c ../DebugDPS.m
	./debugdps$(EXEEXT)
integerstring: integerstring.c ../IntegerString.c ../IntegerString.h
	$(CC) $(ARCH_FLAGS) $(CFLAGS) -o integerstring$(EXEEXT) integerstring.c ../IntegerString.c
	./integerstring$(EXEEXT)
shellexec: shellexec.c ../ShellExec.c ../ShellExec.h
	$(CC) $(ARCH_FLAGS) $(CFLAGS) -Dexecvp=terminalTestExecvp -o shellexec$(EXEEXT) shellexec.c ../ShellExec.c
	./shellexec$(EXEEXT)
shellpolicy: shellpolicy.c ../ShellPolicy.c ../ShellPolicy.h
	$(CC) $(ARCH_FLAGS) $(CFLAGS) -o shellpolicy$(EXEEXT) shellpolicy.c ../ShellPolicy.c
	./shellpolicy$(EXEEXT)
flagmap: flagmap.c ../FlagMap.c ../FlagMap.h
	$(CC) $(ARCH_FLAGS) $(CFLAGS) -o flagmap$(EXEEXT) flagmap.c ../FlagMap.c
	./flagmap$(EXEEXT)
processinfo: processinfo.c ../ProcessInfo.c ../ProcessInfo.h
	$(CC) $(ARCH_FLAGS) $(CFLAGS) -o processinfo$(EXEEXT) processinfo.c
	./processinfo$(EXEEXT)
	$(CC) $(ARCH_FLAGS) $(CFLAGS) -DTERMINAL_PROCESSINFO_PPC_TEST -o processinfo-ppc$(EXEEXT) processinfo.c
	./processinfo-ppc$(EXEEXT)
processnames: processnames.c ../ProcessNames.c ../ProcessNames.h ../ShellPolicy.c
	$(CC) $(ARCH_FLAGS) $(CFLAGS) -o processnames$(EXEEXT) processnames.c ../ProcessNames.c ../ShellPolicy.c
	./processnames$(EXEEXT)
identity: identity.c ../ProcessIdentity.c ../ProcessIdentity.h
	$(CC) $(ARCH_FLAGS) $(CFLAGS) -DTERMINAL_PROCESSIDENTITY_TEST -o identity$(EXEEXT) identity.c ../ProcessIdentity.c
	./identity$(EXEEXT)
windowtitle: windowtitle.c ../WindowTitle.c ../PathCompress.c ../WindowTitle.h ../PathCompress.h
	$(CC) $(ARCH_FLAGS) $(CFLAGS) -o windowtitle$(EXEEXT) windowtitle.c ../WindowTitle.c ../PathCompress.c
	./windowtitle$(EXEEXT)
printline: printline.c ../PrintLine.c ../Chunk.c ../PrintLine.h ../Chunk.h
	$(CC) $(ARCH_FLAGS) $(CFLAGS) -o printline$(EXEEXT) printline.c ../PrintLine.c ../Chunk.c
	./printline$(EXEEXT)
servicemanagerstate: servicemanagerstate.c ../ServiceManagerState.h
	$(CC) $(ARCH_FLAGS) $(CFLAGS) -o servicemanagerstate$(EXEEXT) servicemanagerstate.c
	./servicemanagerstate$(EXEEXT)
scrollback: scrollback.c ../Chunk.c ../FindCharacters.c ../PrintLine.c \
		../VT100Args.c ../VT100String.c ../VT100Parser.c ../VT100State.c \
		../TerminalScreen.c ../PathCompress.c ../WordBoundary.c \
		../WordSelection.c ../PasteText.c ../TerminalScreen.h ../Chunk.h
	$(CC) $(ARCH_FLAGS) $(CFLAGS) -D_CRT_SECURE_NO_WARNINGS -o scrollback$(EXEEXT) scrollback.c ../Chunk.c ../FindCharacters.c ../PrintLine.c ../VT100Args.c ../VT100String.c ../VT100Parser.c ../VT100State.c ../TerminalScreen.c ../PathCompress.c ../WordBoundary.c ../WordSelection.c ../PasteText.c
	./scrollback$(EXEEXT)
savepanelmode: savepanelmode.c ../SavePanelMode.c ../SavePanelMode.h
	$(CC) $(ARCH_FLAGS) $(CFLAGS) -o savepanelmode$(EXEEXT) savepanelmode.c ../SavePanelMode.c
	./savepanelmode$(EXEEXT)
launch: launch.c ../TerminalLaunch.c ../TerminalLaunch.h
	$(CC) $(ARCH_FLAGS) $(CFLAGS) -o launch$(EXEEXT) launch.c ../TerminalLaunch.c
	./launch$(EXEEXT)
clean:
	rm -f storage storage.exe filer filer.exe fstream fstream.exe debugdps debugdps.exe integerstring integerstring.exe shellexec shellexec.exe shellpolicy shellpolicy.exe flagmap flagmap.exe processinfo processinfo.exe processinfo-ppc processinfo-ppc.exe processnames processnames.exe identity identity.exe windowtitle windowtitle.exe printline printline.exe servicemanagerstate servicemanagerstate.exe scrollback scrollback.exe savepanelmode savepanelmode.exe launch launch.exe
