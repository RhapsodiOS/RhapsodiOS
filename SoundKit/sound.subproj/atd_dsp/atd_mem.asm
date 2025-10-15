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
; *    atd_mem.asm - AUDIO TRANSFORM MEMORY MAP 			 *
; *    INTERNAL PARAMETERS RESIDE IN X Y AND L MEMORY SPACES             *
; *                                                                      *
; ************************************************************************

;
; ***************************************************************************

NUM_INTMEM		equ	$40	;number of internal L mem

; ************************************************************************
; *                                                                      *
; *    MISC INTERAL X MEMORY VARIABLES                                   *
; *                                                                      *
; ************************************************************************
;
; equates for memory locations
INT_X_MEM		equ	$0	;starting address of atd x int mem
EXT_L_MEM		equ	$A800	;starting address of atd l ext mem
					; multiple of framestep = 2^k

	org	li:INT_X_MEM
fftbuf		dsm	FRAME_STEP	; for FFT manipulation

	org	xi:INT_X_MEM
outstep		dc	FRAME_STEP	
newoutstep	dc	FRAME_STEP	
overlap		dc	FRAME_SIZE-FRAME_STEP	
int_1		dc	1		;set at init to 1
mant_size	dc	MANTISSA_SIZE	;set at init to MANTISSA_SIZE
word_size	dc	WORD_SIZE	;set at init to WORD_SIZE
frameExponent	ds	1
tmpp		ds	1
; words sent down from the host on start-up:
bufsize		dc	0
header_size	dc	0
channels	dc	0
chan		dc	0
	
data_steps	dc	0
played_steps	dc	0

	if TEST_DROP_ADD
	warn 'Hacked here to test drop/add'
delta_outstep	dc	1
	else
delta_outstep	dc	0
	endif

saved_r6	dc	0
saved_m6	dc	0
saved_r7	dc	0
saved_m7	dc	0
last_x_intmem	equ	*

;	Y rom sinetable
	org	y:FFTCOEFF
	nolist
;*      sinewave	FFTTABLE	;; (already in ROM)

;********* PREASSEMBLED INPUT BUFFER FOR TESTING **************

	org x:READ_BUF1
;*	include 'compressed_impulse.asm'

	list

; ************************************************************************
; *                                                                      *
; *    EXTERAL L MEMORY VARIABLES                                        *
; *                                                                      *
; ************************************************************************
;
; Note that external l memory can only be used in "image 2" of the DSP
; memory, i.e., where x and y memories are physically separate at the
; same address.
;
; Actual locations as of 3/2/92
;
; read_buffer_1 x:A000	(halve?)	write_buffer_1 y:A000
; read_buffer_2 x:A400	(halve?)	write_buffer_2 y:A400
;
; g_buf		l:A800	(A000 to A800 is read buffers in x, write bufs in y)
; h_buf		l:A900
; window_buf	l:AA00
;
; w2nbuf	l:AB00
; nzbuf		l:AC00
;
; framebuf	l:A800
; intmem_save	l:AD00	($40 words, to AD40-1)
; cb_base	l:AD40

; cbgain	x:AD40#$28
; frame_number	x:AD68#1
; rshft		x:AD69#$20
; presp		x:AD89#$10
; exponent	x:AD99#$28
; xe_end	x:ADC1		(locations x|y|p:3DC1-3FFF available)
; ext y vars	x:ADC1#D
; Y_DMA_TOP_REAL x:ADCE
; free2_unused 	   232

; cblo		y:AD40#$28
; cbwid		y:AD68#$28 (to $ad90)
; ye_end	y:AD90		(locations x|y|p:2D90-2FFF available)
; ext p code	x:AD90
; free1_unused 	    39

	org	le:EXT_L_MEM	; start from EXT_L_MEM
	nolist
g_buf		dsm	FRAME_STEP	; framesize/2 circuler buffers
h_buf		dsm	FRAME_STEP	; for FFT manipulation
window_buf	dsm	FRAME_STEP	; window function
					; even terms in x   odd in y
w2nbuf		dsm	FRAME_STEP	; twiddle factor sine/cosine tables
nzbuf		dsm	FRAME_STEP	; dct/dst sine/cosine tables

framebuf	equ	g_buf		; output buffer
intmem_save	ds	NUM_INTMEM	; save internal memory
cb_base		equ	*

;
; Create tables of critical band information
;
	org	xe:cb_base
cbgain	bsc	NCB,@pow(2,-4)	; cbgain and cblow same address
frame_number	dc	1	; set at init to 1
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
;
; 32 words above, NPW=16, NCB=40 => 56 below => 88 total = 
;
	list
presp	ds	NPW	; presence bits 16*NPW
exponent ds	NCB   	; exponents
xe_end	equ 	*

	org	ye:cb_base
; cbgain and cblow same address
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
ye_end	equ 	*


;	create and store tables
	nolist
        create_window	FRAME_SIZE,window_buf
        sincosgen	FRAME_SIZE,w2nbuf,FRAME_STEP
        create_phasors	FRAME_SIZE,nzbuf,FRAME_STEP
	list
end_phasors

free1	equ ye_end-$8000	; convert to $2000-$3000 range
free2	equ xe_end-$7000	; convert to $3000-$4000 range
