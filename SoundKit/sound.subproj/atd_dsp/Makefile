CFLAGS = -g -O
ATD_FILES = \
	atd_dsp.asm \
	ioequ.asm \
	atd_dma_support.asm \
	atd_macros.asm \
	atd_h.asm \
	atd_mem.asm \
	atd_util.asm \
	atd_spec.asm

SRCS =  atd_dsp.c sd_error.c sd_error.h $(ATD_FILES)

debug all: atd_dsp atd_dsp.lod

synch_test: atd_dsp
	/bin/time asm56000 -a -b -l -OS,SO,MEX synched_buffers_example.asm
	cp synched_buffers_example.lod atd_dsp.lod
	atd_dsp

atd_dsp: atd_dsp.o sd_error.o
	$(CC) $(CFLAGS) -o atd_dsp atd_dsp.o sd_error.o -lsys_s

lod atd_dsp.lod: atd_dsp.asm atd_dma_support.asm $(ATD_FILES)
	/bin/time asm56000 -a -b -l -OS,SO,MEX,NOMD atd_dsp.asm

clean:
	-/bin/rm -f atd_dsp *.lnk *.lod *.map *.lst *.snd *.dat *.o *~

installsrc:
	mkdirs -m 755 $(SRCROOT)
	cp $(SRCS) Makefile $(SRCROOT)
	chmod 444 $(SRCROOT)/*

installme: /me/bin
	install -q -c -s -m 755 atd_dsp /me/bin

output: atd_dsp atd_dsp.lod
	atd_dsp sc.snd scd.snd
	sndplay scd.snd

tags: $(SRCS)
	etags -t $(SRCS)

bag:
	bag $(SRCS) > atd_dsp.bag

asmbag:
	bag $(ATD_FILES) > atd_asm.bag

