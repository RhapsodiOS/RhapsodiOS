CFLAGS = -g -O
SRCS =  atc_dsp.c sd_error.c sd_error.h \
	atc_dsp.asm atc_dma_support.asm ioequ.asm
ATC_FILES = \
	atc_macros.asm \
	atc_h.asm \
	atc_mem.asm \
	atc_util.asm \
	atc_spec.asm

debug all: atc_dsp atc_dsp.lod

synch_test: atc_dsp
	asm56000 -a -b -l -OS,SO,MEX synched_buffers_example.asm
	cp synched_buffers_example.lod atc_dsp.lod
	atc_dsp

atc_dsp: atc_dsp.o sd_error.o
	$(CC) $(CFLAGS) -o atc_dsp atc_dsp.o sd_error.o -lsys_s

lod atc_dsp.lod: atc_dsp.asm atc_dma_support.asm $(ATC_FILES)
	asm56000 -a -b -l -OS,SO,MEX,NOMD atc_dsp.asm

clean:
	-/bin/rm -f atc_dsp *.lnk *.lod *.map *.lst *.snd *.dat *.o *~

installsrc:
	mkdirs -m 755 $(SRCROOT)
	cp $(SRCS) Makefile $(SRCROOT)
	chmod 444 $(SRCROOT)/*

installme: /me/bin
	install -q -c -s -m 755 atc_dsp /me/bin

output: atc_dsp atc_dsp.lod
	atc_dsp scl.snd scc.snd


tags: $(SRCS)
	etags -t $(SRCS)

asmbag: $(ATC_FILES)
	bag $(ATC_FILES) > atc_dsp.bag
