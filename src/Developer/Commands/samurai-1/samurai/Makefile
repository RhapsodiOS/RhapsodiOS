# RhapsodiOS: build with the native C89 compiler and libc.
CC=cc
CFLAGS=-O -Wall
CPPFLAGS=-DNO_POSIX_SPAWN -DHAVE_GETLOADAVG
LDFLAGS=
LDLIBS=
ifeq ($(shell uname -s),Rhapsody)
CPPFLAGS+=-DSAMU_RHAPSODY -no-precomp
endif

OBJ=build.o deps.o env.o graph.o htab.o log.o parse.o samu.o scan.o \
    tool.o tree.o util.o os-posix.o compat.o
HDR=arg.h build.h compat.h deps.h env.h graph.h htab.h log.h os.h \
    parse.h scan.h tool.h tree.h util.h

all: samu

samu: $(OBJ)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $(OBJ) $(LDLIBS)

.c.o:
	$(CC) $(CPPFLAGS) $(CFLAGS) -c -o $@ $<

$(OBJ): $(HDR)

ifeq ($(shell uname -s),Rhapsody)
# GCC 2.7.2.1 miscompiles the 64-bit hash arithmetic with optimization.
htab.o: htab.c $(HDR)
	$(CC) $(CPPFLAGS) $(CFLAGS) -O0 -c -o $@ htab.c
endif

port-types: ../tests/types.c util.o htab.o compat.o $(HDR)
	$(CC) $(CPPFLAGS) $(CFLAGS) $(LDFLAGS) -I. -o $@ ../tests/types.c util.o htab.o compat.o $(LDLIBS)

test: samu port-types
	./port-types

clean:
	rm -f samu port-types $(OBJ)

.PHONY: all clean test
