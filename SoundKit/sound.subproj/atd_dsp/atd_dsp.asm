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
; Audio Transform Decompression (ATD)
;
; Copright 1991, NeXT Computer, Inc.
; All rights reserved.
;
; Algorithms by Julius O. Smith at NeXT.
; Initial DSP programming by DSP consultant Sandeep Pombra.
; Final features, debugging, and ongoing maintenance by J.O.Smith.
;
; PROGRAMMING CONVENTIONS
;
;	r3,r6,r7 are reserved for i/o.  r3 is used at interrupt level.
;	m registers are -1 always unless dedicated to I/O (m3,m6,m7).
;	n registers are always scratch.
;	caller saves any additional registers it wants saved.
;
	page 255,255,0,1,1	   	; Width, height, topmar, botmar, lmar
	nolist
	include 'ioequ.asm'
	list

;--- Program configuration ---

BUG56_VERSION	set 0	 	; Set 0 for real thing, 1 for standalone Bug56
DEBUG_VERSION	set 1		; Set to 0 after DSP code is debugged
DEBUG_DMA	set 1		; Set to 0 after DSP code is debugged
TEST_DROP_ADD	set 0		; Set to 0 after drop/add code is debugged
SHORT_CIRCUIT	set 0		; 1 = loopback test

	if SHORT_CIRCUIT
	  warn 'SHORT CIRCUIT MODE'
	endif

	if !@def(TRAILPAD)
TRAILPAD  set 4	;number of buffers after sound ends
	endif
	if TRAILPAD!=0
	  msg 'Sending extra buffers to flush sound-out'
	endif

	if !@def(WRITE_SNDOUT)
WRITE_SNDOUT set 0		; 1 to get mono converted to stereo
	endif
	if WRITE_SNDOUT
	  msg 'converting mono ATC to stereo'
	endif

; The start address is made large to leave room for Bug56
; By moving some things off chip in Bug56 mode, you can have both.
; (See the JPEG DSP code for an example).

START		equ 	$40	; Leaves room for special DEGMON (e.g. 1.0)
;;START		equ 	$7C	; Leaves room for standard 2.0-3.0 DEGMON

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
reset	
	bset    #0,x:m_pbc		; Enable host port
	bset	#3,x:m_pcddr		;    pc3 asserts 0 to enable external
	bclr	#3,x:m_pcd		;    DSP ram on very early machines
	movep   #0,x:m_bcr		; No wait states for the external sram
	jmp	reset_offchip		; off chip to conserve onchip memory

;
;
; Include ATC decompression
;
        include 'atd_macros.asm'
        include 'atd_h.asm'
	include	'atd_mem.asm'
	include	'atd_util.asm'
	include	'atd_spec.asm'

	if *>$200
	  fail 'Internal P memory overflow' ; fatal for 8K SRAM
	endif
;
; ==================== Switch to off-chip program memory ===================
;
;;	org p:($ADA0+NUM_INTMEM-$8000)	; old formula

	org p:free1
;
; input/output routines, DMA and non-DMA i/o
;
	include 'atd_dma_support.asm'

reset_offchip
	movec   #6,omr			; Data rom enabled, mode 2 = "normal"
	if DEBUG_VERSION
	  move	#2,sp			; leave room for Bug56 stack use
	else
	  move	#0,sp			; clear stack
	endif
        movep   #>$00B400,x:m_ipr  	; Intr levels: SSI=2, SCI=1, HOST=0
	move	#0,sr			; go to lowest int. priority level
	move 	#$FFFF,m0
	move	m0,m1
	move	m0,m2
	move	m0,m4
	move	m0,m5	; m3,m6,m7 devoted to I/O

;;------------------------------ PARTITION 2 ---------------------------------

	jmp partition_2		; needed only if org is used below

	if *>$3000		; free1 section tops out at $2FFF
	  fail 'External P memory partition 1 overflow'
	else
free1_unused	equ	$3000-*
	endif

	org p:free2_after_y	; sorry for all the jumping around

partition_2

;;------------------------------ MAIN ENTRY --------------------------------
main

	if BUG56_VERSION
	  move #>$400,A			; ATC buffer size
        else
	  readWordHost A		; read ATC buffer size
	  if DEBUG_VERSION
	    move #>$400,X0
	    cmp X0,A
	    jsne abort
	  endif
	endif
	move A,x:<bufsize

	if BUG56_VERSION
	  move #>$100,A			; ATC header size
        else
	  readWordHost A		; read ATC header size
	endif
	move A,x:<header_size

	if BUG56_VERSION
	  move #>1,A			; ATC channel count
        else
	  readWordHost A		; read ATC channel count
	endif
	move A,x:<channels

	if !BUG56_VERSION
	  move #cbgain,R0
	  DO #NCB,get_gain_loop
	    readWordHost A		; read ATC band gains
	    move A,x:(R0)+
get_gain_loop
	endif

	if 0
	warn 'halting'
halt0	jmp halt0
resume0
	endif

	jsr dma_start		; Reset DMA state machine

	move x:<outstep,B	; advance output pointer so 1st OLA
	if WRITE_SNDOUT		;   does not reach back into time.
	  lsl B			; mono to stereo => doubled output
	else
	  jmp_mono single_out
	    lsl b		; stereo case => back up double also
	endif
single_out
	move B1,N_DMA_OUT

	move x:<header_size,A
	tst A
	jeq skiphloop		; a DO count of 0 means 65536 iterations
	do A,skiphloop
	  jsr getWordDMA	; skip soundfile hdr (awaits buf1, req's buf2)
skiphloop

	if 0
	warn 'Halting'
halt	jmp halt
resume
	endif

	lua (R_DMA_OUT)+N_DMA_OUT,R_DMA_OUT	; OLA advance for back-up
;
; ------------------- Read compression subheader -------------------------
;
;    typedef struct {
;	int originalSize;
;	int method;
;	int numDropped;
;	int encodeLength;
;	int reserved;
;    } compressionSubHeader;
;

	; Read total number of bytes and divide it by 2 to get shorts.
	; Divide total number of shorts by FRAME_STEP to get steps.
	; If stereo, divide again by 2 since bytecount was aggregate.
	if FRAME_STEP!=256
		fail 'this code assumes a frame step size of 256 words'
	endif
	readWordDMA Y1
	move #>@pow(2,-16),X1
	mpy Y1,X1,A #>@pow(2,-8),X1	
	move A0,X0		; A0 contains top short
	readWordDMA Y1
	mpy Y1,X1,A 		; A1 contains low-order byte
	add X0,A x:<int_1,X0	; assemble 24-bit word
	lsr A			; bytes to shorts
;;??? Why does this fix stereo ???
;;	jmp_mono ds_done
;;	  lsr A			; divide stereo case by 2 to get frames
;;ds_done
	add X0,A		; add 1 to accommodate final partial frame
	if BUG56_VERSION
	  move #>1024,A		; random large number
	endif
	move A,x:<data_steps

	do #8,skip_subheader
	  jsr getWordDMA	; skip rest of compression subheader
skip_subheader

	if 0
	warn 'halting before main loop'
halt	jmp >halt
resume
	endif

;;------------------------------ MAIN LOOP ---------------------------------

; If either WRITE_SNDOUT or doing stereo, only one call to process_frame
; can occur before await_write_buf.  This is because process_frame writes
; 256 samples ahead of "where it is".  For true mono to disk, process_frame 
; can be called three times before await_write_buf.  We forego the latter case
; for simplicity below.

loop	
	check_mem
	jsr process_frame		; out_ptr is init'd at asm time
	check_mem
	jsr await_write_buf		; process_frame overwrites next 256
	check_mem

	if 1
	warn 'testing termination on zero frame size'
	jmp loop
	endif

	if (TRAILPAD==0)
	  jmp loop
	else
	  move 	x:<int_1,x0
	  move	x:<played_steps,a
	  add	x0,a		; update total number of frames played out
	  move	a,x:<played_steps
 	  move 	x:<data_steps,b
	  sub 	a,b
	  jgt 	loop
;
; All data has been sent.  Zero pad and flush last partial buffer
;
	  check_mem

break1	  do #DMA_WRITE_SIZE,loop2
	    clr A 	y:Y_WRITE_TRIGGER,X0
	    move	A,y:(R_DMA_OUT)+
	    move 	R_DMA_OUT,B
	    cmp X0,B
	    jseq 	enqueue_dma_write
	    nop
	    nop
loop2
	  check_mem
	  jsr await_write_buf	; let last buffer out, if any
	  check_mem
;
; Copy input to output until the host gives up the DSP port.
;
loop3	  
	  do #DMA_WRITE_SIZE,floop
	    jsr getWordDMA
	    clr A	; guard against trailing garbage
	    move A,y:(R_DMA_OUT)+
floop
	  jsr enqueue_dma_write
	  jsr await_write_buf
	  jmp loop3

	endif				; TRAILPAD!=0
	
;;------------------------------ MAIN LOOP END -----------------------------

	if DEBUG_VERSION
abort	  bset #m_hf2,x:m_hcr	; abort code = HF2 and HF3
	  bset #m_hf3,x:m_hcr	; abort code = HF2 and HF3
	  jmp *
	endif

free2_after_p	equ *

SND_BOOTER equ 6  ; number of words in SNDBootDSP() bootstrap monitor
		  ; see <soundlibrary>/booter.asm
	if *>$4000-SND_BOOTER	; free2 section tops out at $3FFF
		fail 'External P memory partition 2 overflow'
	else
free2_unused	equ	$4000-SND_BOOTER-free2_after_p
	endif

	end reset
