#
# Makefile for the /private/dev directory.
#

# Comment out this line if you want make output
.SILENT:

# The makefile above hands us THISDIR for informational purposes
THISDIR=.

#	The directory we are building
DIR = /private/dev

#	The directory that must be created
DSTDIR = ${DSTROOT}${DIR}
DSTOWNER = root
DSTGROUP = wheel
DSTMODE = 775

#	Files that are ok to edit
RWFILES	= MAKEDEV.local
RWMODE = 644

all:

clean:
	echo "    Removing" *~ .[a-zA-Z]*~ \#* *.BAK
	rm -f *~ .[a-zA-Z]*~ \#* *.BAK

install: ${DSTDIR}
	echo "    Read/Write files:"
	for i in `echo ${RWFILES}` ; \
	  do \
		echo -n " $$i" ; \
		install -c -o root -g wheel -m ${RWMODE} $$i ${DSTDIR}/$$i ; \
	  done
	echo "."
	echo "    Creating devices"
	cd ${DSTDIR}; /dev/MAKEDEV rhapsody
#	The host's MAKEDEV may predate the kernel's CSPRNG (Rhapsody DR2's
#	does), so add its nodes as kernel-7's MAKEDEV std makes them.
	cd ${DSTDIR}; test -c random || { mknod random c 17 0; chmod 644 random; }
	cd ${DSTDIR}; test -c urandom || { mknod urandom c 17 1; chmod 644 urandom; }

${DSTDIR}: DSTROOT ${DSTROOT}
	echo "    Making ${DSTDIR}"
	mkdir -p -m ${DSTMODE} ${DSTDIR}
	chown ${DSTOWNER}:${DSTGROUP} ${DSTDIR}

$(DSTROOT):
	echo 'Please make a directory for $@ and try again'; exit 1

DSTROOT:
	@if [ -n "${$@}" ]; then exit 0; else echo Must define $@; exit 1; fi
