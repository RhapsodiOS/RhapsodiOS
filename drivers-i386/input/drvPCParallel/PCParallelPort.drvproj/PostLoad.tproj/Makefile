##
# Makefile for Parallel Port Post-Load Tool
##

NAME = RemovePPDev
CFILES = RemovePPDev.c

INSTALLDIR = /usr/local/bin

CFLAGS = -Wall -O2
LDFLAGS =

all: $(NAME)

$(NAME): $(CFILES)
	$(CC) $(CFLAGS) -o $(NAME) $(CFILES) $(LDFLAGS)

install: $(NAME)
	install -d $(DSTROOT)$(INSTALLDIR)
	install -c -m 755 $(NAME) $(DSTROOT)$(INSTALLDIR)/$(NAME)

clean:
	rm -f $(NAME) *.o

.PHONY: all install clean
