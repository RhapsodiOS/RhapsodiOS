##
# Makefile for Parallel Port Pre-Load Tool
##

NAME = InstallPPDev
OBJC_FILES = InstallPPDev.m IODeviceMaster.m
HFILES = IODeviceMaster.h

INSTALLDIR = /usr/local/bin

CFLAGS = -Wall -O2
LDFLAGS = -framework System -lobjc

OBJECTS = $(OBJC_FILES:.m=.o)

all: $(NAME)

$(NAME): $(OBJECTS)
	$(CC) $(CFLAGS) -o $(NAME) $(OBJECTS) $(LDFLAGS)

.m.o:
	$(CC) $(CFLAGS) -c $< -o $@

install: $(NAME)
	install -d $(DSTROOT)$(INSTALLDIR)
	install -c -m 755 $(NAME) $(DSTROOT)$(INSTALLDIR)/$(NAME)

clean:
	rm -f $(NAME) $(OBJECTS) *.o

.PHONY: all install clean
