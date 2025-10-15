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
; Audio Transform Decompression (ATC)
;
; Copright 1991 by NeXT Computer, Inc.
; All rights reserved.
;
; Algorithm developed by Julius O. Smith at NeXT.
; Initial DSP programming by DSP consultant Sandeep Pombra.
; Final features/debugging and ongoing maintenance by J.O. Smith.
;
; PROGRAMMING CONVENTIONS
;
;	r3,r6,r7 are reserved for i/o.  r3 is used at interrupt level.
;	low x memory swapped out by fft => don't use it for interrupt saves.
;	m registers are -1 always unless dedicated to I/O (m3,m6,m7).
;	n registers are always scratch.
;	caller saves any additional registers it wants saved.
;
	page 255,255,0,1,1	   	; Width, height, topmar, botmar, lmar
	nolist
	include 'ioequ.asm'
	list

;--- Program configuration ---
NUM_INTMEM		equ	$20	;number of internal L mem

BUG56_VERSION	set 0	 	; Set 0 for real thing, 1 for standalone Bug56
DEBUG_VERSION	set 1		; Set to 0 after DSP code is debugged
DEBUG_DMA	set 1		; Set to 0 after DSP code is debugged
WRITE_SNDOUT	set 0		; Set to 0 for the encoder
DMA_LOG_VERSION	set 0		; See atc_dma_support.asm

	if DEBUG_VERSION
	    	warn 'start address hacked for Bug56'
START		equ 	$7C	; Leaves room for interrupt vectors
	else
START		equ 	$40	; Leaves room for interrupt vectors
	endif


;--- DMA configuration ---

		define	R_DMA 'R3'	; Dedicated to DMA in
		define	N_DMA 'N3'	; Unused
		define	M_DMA 'M3'	; -1

		define	R_DMA_IN 'R6'	; Dedicated to DMA in
		define	N_DMA_IN 'N6'	; Unused
		define	M_DMA_IN 'M6'	; DMA_READ_SIZE-1 (modulo addr)

		define	R_DMA_OUT 'R7'	; Dedicated to DMA out
		define	N_DMA_OUT 'N7'	; Unused
		define	M_DMA_OUT 'M7'	; DMA_WRITE_SIZE-1 (modulo addr)

; equates for DMA  config						
DMA_READ_SIZE		equ	$400	; size of each DMA transfer in
DMA_WRITE_SIZE		equ	$400	; size of each DMA transfer out
READ_BUF1		equ	$2000	; first input buffer
READ_BUF2		equ	$2400	; second input buffer
WRITE_BUF1		equ	$3000	; first output buffer
WRITE_BUF2		equ	$3400	; second output buffer
						
;;-----------------------------------------------------------------------

	if BUG56_VERSION
; 	  Do NOT assemble the reset vector for Bug56 version.
	else 
	  org p:0
	  jmp reset
	endif

	org p:START
;
; reset --- first thing executed when DSP boots up - must be on-chip
;
reset	movec   #6,omr			; Data rom enabled, mode 2 = "normal"
	if 0	;; STACK IS OVERFLOWING!
	  move	#2,sp			; leave room for Bug56 stack use
	else
	  move	#0,sp			; clear stack
	endif
	bset    #0,x:m_pbc		; Enable host port
	bset	#3,x:m_pcddr		;    pc3 asserts 0 to enable external
	bclr	#3,x:m_pcd		;    DSP ram on very early machines
	movep   #>$000000,x:m_bcr	; No wait states for the external sram
        movep   #>$00B400,x:m_ipr  	; Intr levels: SSI=2, SCI=1, HOST=0
	move	#0,sr			; go to lowest int. priority level
	move 	#$FFFF,m0
	move	m0,m1
	move	m0,m2
	move	m0,m4
	move	m0,m5	; m3,m6,m7 devoted to I/O
	jmp 	main
;
;
; Include ATC encoder
;
        include 'atc_macros.asm'
        include 'atc_h.asm'
	include	'atc_mem.asm'
	include	'atc_util.asm'
	include	'atc_spec.asm'

	if *>$200
	  fail 'Internal P memory overflow!' ; fatal for 8K SRAM
	endif
;;	org p:($ADB0+NUM_INTMEM-$8000)	; old formula

	org p:free1

;
; input/output routines, DMA and non-DMA i/o
;
	include 'atc_dma_support.asm'

;;------------------------------ MAIN ENTRY --------------------------------
main

	if BUG56_VERSION
	  move #>$400,X0		; ATC buffer size
        else
	  readWordHost X0		; read ATC buffer size
	  if 0
	    move #>$400,A 	
	    cmp X0,A
	    jsne abort
	  endif
	  move X0,x:atc_bufsize
	endif

	if BUG56_VERSION
	  move #>$100,X0		; ATC header size
        else
	  readWordHost X0		; read ATC header size
	endif
	move X0,x:atc_header_size

	if BUG56_VERSION
	  move #>1,X0			; ATC channel count
        else
	  readWordHost X0		; read ATC channel count
	endif
	move X0,x:atc_channels

	if BUG56_VERSION
	  move #>2,X0
        else
	  readWordHost X0		; read ATC compression method
	  if 0
	    move #>2,A 	
	    cmp X0,A
	    jsne abort
	  endif
	endif
	move X0,x:atc_method

	if BUG56_VERSION
	  move #>0,X0
        else
	  readWordHost X0		; read ATC bits dropped
	  if 0
	    clr A
	    cmp X0,A
	    jsne abort
	  endif
	endif
	move X0,x:atc_dropped

	if BUG56_VERSION
	  move #>FRAME_STEP,X0
        else
	  readWordHost X0		; read ATC "encode length"
	endif
	move X0,x:atc_encode_len

	if !BUG56_VERSION
	  readWordHost X0		; read ATC sampleSkip
	  if 0
	    move x:atc_channels,A 	
	    cmp X0,A
	    jsne abort
	  endif
	endif

	if BUG56_VERSION
	  move #>$100,X0		; ATC buffer count
        else
	  readWordHost X0		; read ATC buffer count (# DMA bufs)
	  move X0,x:atc_bufcount
	endif

	if !BUG56_VERSION
	  move #cbth,R0
	  DO #NCB,get_th_loop
	    readWordHost A		; read ATC band thresholds
	    move A,x:(R0)+
get_th_loop
	endif

;;------------------------------ READ FIRST BUFFER ----------------------------

	jsr dma_start		; Reset DMA and request first buffer

	set_status B_SKIPPING_HDR

	if 0
	warn 'halting before first await_read_buf'
halt	jmp	halt
resume  
	endif

	jsr await_read_buf	; wait until 1st read is finished
	jsr se_read_buf		; sign extend 1st buffer
	jsr enqueue_dma_read	; request 2nd read (must call after sign ext.)

;;------------------------------ MAIN Loop ---------------------------------

	do x:atc_bufcount,main_loop

	do #2,pf_loop1
	  jsr process_frame		; in_ptr is init'd at asm time	
	  nop
pf_loop1

	jsr await_read_buf		; wait until pending read finishes
	jsr se_read_buf			; sign extend latest buffer

	do #2,pf_loop2
	  jsr process_frame
	  nop
pf_loop2

	jsr enqueue_dma_read	; request next buffer

	if DEBUG_VERSION
	move x:atc_bufs_done,A
	move x:int_1,X0
	add  X0,A
	move A,x:atc_bufs_done
	endif

	nop

main_loop

;;------------------------------ MAIN LOOP END -----------------------------

	; make sure last partial buffer goes out (zero filled)
	do #DMA_WRITE_SIZE,flush
	  clr A
	  jsr putWordDMA
flush	
	jsr await_write_buf

	warn 'need to set hf3 after last dma COMPLETE containing valid data'
	set_hf3				; tell host we're done

done	move x:atc_outsize,A
	move A,x:m_htx
	jmp done
	

	if DEBUG_VERSION
abort	  bset #m_hf2,x:m_hcr	; abort code = HF2 and HF3
	  bset #m_hf3,x:m_hcr	; abort code = HF2 and HF3
	  set_status B_ERROR
	  jmp *
	endif

;;------------------------------ PARTITION 2 ---------------------------------

	jmp partition_2		; needed only if org is used below

	if *>$3000
	  fail 'External P memory overflow!' ; fatal for 8K SRAM
	else
free1_unused	equ	$3000-*
	endif

	org p:free2_after_y	; sorry for all the jumping around

partition_2

;;---------------------------- NEW CODE GOES HERE ----------------------------


;    +--------------------------------------------------------------------+
;    +  Function Name : packexp
; 	pack exponents
;    +--------------------------------------------------------------------+
;

packexp

	move	#exponent,r4	;  exponent pointer
	move	#4,n0		; 4 bits per exponent
		
	do	#(NCBW),_endexp

	move	#(lshft-12),r0  ; left shift by 12

	move			y:(r4)+,y0	;e1
	move	x:(r0)+n0,x0			;l12  
	mpy	x0,y0,a		x:(r0)+n0,x0	y:(r4)+,y0 ; l8 e2	
	move	a0,b		; e1<<12

	mpy	x0,y0,a		x:(r0),x0	; l4
	move	a0,x1		; e2<<8
	or	x1,b	y:(r4)+,y0  ; (e1<<12) | (e2<<8)  e3  

	mpy	x0,y0,a		y:(r4)+,y0	;e4		
	move	a0,x1		; e3<<4
	or	x1,b		; (e1<<12) | (e2<<8)  | (e3<<4)  

	or	y0,b		; (e1<<12) | (e2<<8)  | (e3<<4)  | e4

	move	b1,x:(r7)+

_endexp	
atcend

	rts

; -------------------------------------------------------------------------

free2_after_p	equ *

SND_BOOTER equ 6  ; number of words in SNDBootDSP() bootstrap monitor
		  ; see <soundlibrary>/booter.asm
	if *>$4000-SND_BOOTER	; free2 section tops out at $3FFF
		fail 'External P memory partition 2 overflow'
	else
free2_unused	equ	$4000-SND_BOOTER-free2_after_p
	endif

	end reset
