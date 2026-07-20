;;;;
;; Copyright (c) 1999 Apple Computer, Inc. All rights reserved.
;;
;; @APPLE_LICENSE_HEADER_START@
;; 
;; "Portions Copyright (c) 1999 Apple Computer, Inc.  All Rights
;; Reserved.  This file contains Original Code and/or Modifications of
;; Original Code as defined in and that are subject to the Apple Public
;; Source License Version 1.0 (the 'License').  You may not use this file
;; except in compliance with the License.  Please obtain a copy of the
;; License at http://www.apple.com/publicsource and read it before using
;; this file.
;; 
;; The Original Code and all software distributed under the License are
;; distributed on an 'AS IS' basis, WITHOUT WARRANTY OF ANY KIND, EITHER
;; EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
;; INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
;; FITNESS FOR A PARTICULAR PURPOSE OR NON-INFRINGEMENT.  Please see the
;; License for the specific language governing rights and limitations
;; under the License."
;; 
;; @APPLE_LICENSE_HEADER_END@
;;;;
; ************************************************************************
; *									 *
; *    AUDIO TRANSFORM CODER MEMORY MAP					 *
; *    INTERNAL PARAMETERS RESIDED IN X Y AND L MEMORY SPACES            *
; *                                                                      *
; ************************************************************************

;
; ***************************************************************************
; ************************************************************************
; *                                                                      *
; *    MISC INTERAL X MEMORY VARIABLES                                   *
; *                                                                      *
; ************************************************************************
;
;
	org	li:0
fftbuf		dsm	FRAME_STEP	; for FFT manipulation

	org	xi:0
int_1		dc	1		;set at init to 1
allpv		dc	ALL_PV		;all present vector
pbcount		dc	@pow(2,(WORD_SIZE-23)) ; word size bits from the right
mant_size	dc	MANTISSA_SIZE	;set at init to MANTISSA_SIZE
word_size	dc	WORD_SIZE	;set at init to WORD_SIZE
tmpp		dc	0
out_ptr		dc	WRITE_BUF1	; output buffer pointer

save_r6		dc	0
save_m6		dc	0
save_r7		dc	0
save_m7		dc	0

atc_bufcount	dc	0

last_x_intmem	equ	*


;	Y rom sinetable
;*	org	y:FFTCOEFF
;*	nolist
;*        sinewave	FFTTABLE	;;(already in ROM)


;********* PREASSEMBLED INPUT BUFFER FOR TESTING **************
	org x:READ_BUF1
;*	include 'ey.asm'


; ************************************************************************
; *                                                                      *
; *    EXTERAL L MEMORY VARIABLES                                        *
; *                                                                      *
; ************************************************************************
;
	org	le:EXT_L_MEM	; start from EXT_L_MEM
	nolist
g_buf		dsm	FRAME_STEP	; framesize/2 circuler buffers
h_buf		dsm	FRAME_STEP
window_buf	dsm	FRAME_STEP	; window function
					; even terms in x   odd in y
w2nbuf		dsm	FRAME_STEP	; twiddle factor sine/cosine tables
nzbuf		dsm	FRAME_STEP	; dct/dst sine/cosine tables
intmem_save	ds	NUM_INTMEM

ymem_ext	equ	*

	list
	org	xe:ymem_ext   
cbth	bsc	NCB,@pow(2,-(MAX_FRAME_EXPONENT))	;** must be same address as cblo

rshft	; right shift table  rsht x = rshft+x  0<x<23
            DC      $800000	    
            DC      $400000         ;>>1    <<23
            DC      $200000         ;>>2    <<22
            DC      $100000         ;>>3    <<21
            DC      $080000         ;>>4    <<20
            DC      $040000         ;>>5    <<19
            DC      $020000         ;>>6    <<18
            DC      $010000         ;>>7    <<17
            DC      $008000         ;>>8    <<16
            DC      $004000         ;>>9    <<15
            DC      $002000         ;>>10   <<14
            DC      $001000         ;>>11   <<13
            DC      $000800         ;>>12   <<12
            DC      $000400         ;>>13   <<11
            DC      $000200         ;>>14   <<10
            DC      $000100         ;>>15   <<9
            DC      $000080         ;>>16   <<8
            DC      $000040         ;>>17   <<7
            DC      $000020         ;>>18   <<6
            DC      $000010         ;>>19   <<5
            DC      $000008         ;>>20   <<4
            DC      $000004         ;>>21   <<3
            DC      $000002         ;>>22   <<2
            DC      $000001         ;>>23   <<1
lshft	    ; lshft x = lshft-x  0<x<23
	    DUP		8
	    DC	    $000000	    ; right shifts greater than 23 up to 32
	    ENDM

; other X memory variables
in_ptr		dc	READ_BUF1	; input buffer pointer
frame_number	dc	1	; set at init to 1
atc_channels	dc	0	; number of channels sent down from the host on 
				; start-up:
channel_index	dc	0

; words sent down from the host on start-up:
atc_bufs_done	dc	0
atc_bufs_reqd	dc	0
atc_bufsize	dc	0
atc_outsize	dc	0
atc_header_size	dc	0
atc_method	dc	0
atc_dropped	dc	0
atc_encode_len	dc	0
saved_sp	dc	0

datap		bsc	MAX_CODED_SIZE,0
		; coded data

mantp		equ	(datap+1+NCBW+FRAME_STEP/WORD_SIZE) 
		; starting address of packed mantissa	

xe_end

	org	ye:ymem_ext
cblo	dc	$0 ; low bin number of each critical band
	dc	$1
	dc	$2
	dc	$3
	dc	$4
	dc	$5
	dc	$6
	dc	$7
	dc	$8
	dc	$9
	dc	$a
	dc	$b
	dc	$c
	dc	$e
	dc	$10
	dc	$12
	dc	$14
	dc	$16
	dc	$19
	dc	$1c
	dc	$1f
	dc	$23
	dc	$27
	dc	$2c
	dc	$31
	dc	$37
	dc	$3e
	dc	$46
	dc	$4f
	dc	$59
	dc	$64
	dc	$70
	dc	$7d
	dc	$8b
	dc	$9a
	dc	$aa
	dc	$bb
	dc	$cd
	dc	$e0
	dc	$f4

exponent ds	NCB   	; exponents

cbwid	dc	$1
	dc	$1
	dc	$1
	dc	$1
	dc	$1
	dc	$1
	dc	$1
	dc	$1
	dc	$1
	dc	$1
	dc	$1
	dc	$1
	dc	$2
	dc	$2
	dc	$2
	dc	$2
	dc	$2
	dc	$3
	dc	$3
	dc	$3
	dc	$4
	dc	$4
	dc	$5
	dc	$5
	dc	$6
	dc	$7
	dc	$8
	dc	$9
	dc	$a
	dc	$b
	dc	$c
	dc	$d
	dc	$e
	dc	$f
	dc	$10
	dc	$11
	dc	$12
	dc	$13
	dc	$14
	dc	$c	; skip fs/2

ye_end

;	create and store tables
	nolist
        create_window	FRAME_SIZE,window_buf
        sincosgen	FRAME_SIZE,w2nbuf,FRAME_STEP
        create_phasors	FRAME_SIZE,nzbuf,FRAME_STEP
	list
end_phasors

free1	equ ye_end-$8000	; convert to $2000-$3000 range
free2	equ xe_end-$7000	; convert to $3000-$4000 range
