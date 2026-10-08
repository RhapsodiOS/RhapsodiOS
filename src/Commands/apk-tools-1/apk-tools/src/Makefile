progs-y			+= apk
apk-objs		:= state.o database.o package.o archive.o \
			   version.o io.o url.o gunzip.o blob.o \
			   hash.o md5.o apk.o \
			   add.o del.o update.o info.o search.o \
			   ver.o index.o fetch.o audit.o
CFLAGS_apk.o		:= -DAPK_VERSION=\"$(FULL_VERSION)\"

progs-$(STATIC)		+= apk.static
apk.static-objs		:= $(apk-objs)
LDFLAGS_apk.static	:= -static

# -nopie is not portable to old ld / Darwin ld; drop it. zlib is linked via
# -lz by default and overridable (make LIBS=...) so the target can point at
# its own libz.
LIBS			?= -lz

install::
	$(INSTALLDIR) $(DESTDIR)$(SBINDIR)
	$(INSTALL) $(obj)/apk $(DESTDIR)$(SBINDIR)
