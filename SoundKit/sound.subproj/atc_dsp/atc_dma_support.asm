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
; fast_dma_support.asm - Time-efficient DSP DMA read and write support.
;
; Author: J. O. Smith (jos@next.com)
; NeXT Computer Inc.
; January 1991
; Last updated 7/24/91.
;
	if !@def(BUG56_VERSION)
BUG56_VERSION set 0		; 1 to get version to load into Bug56
	endif

	if BUG56_VERSION
	  msg 'BUG56 version'
;*FIXME*sndconvert bug prohibits internal comments*  cobj 'BUG56 version'
	endif

	if !@def(DEBUG_DMA)
DEBUG_DMA	  set 0			; 1 to get extra error checking
	endif

	if DEBUG_DMA
	  msg 'DEBUG_DMA version'
;*FIXME*sndconvert bug prohibits internal comments* cobj 'DEBUG version'
	endif

dma_s_saved_lc	set *

;------------------------- Y memory locations used ----------------------

;;	org y:$ADA0	; Old org

	org y:(free2+3)&$FFFC ; first free mod-4 location in bank 2

Y_DMAQ_A0	dc 0	; Enqueued DMA request
Y_DMAQ_A1	dc 0	; Enqueued DMA request
Y_DMAQ_A2	dc 0	; Enqueued DMA request
Y_DMAQ_A3	dc 0	; Enqueued DMA request

Y_DMA_STATUS	dc 0	; On-chip Y memory word used for status bits
Y_DMAQ_FREE	dc Y_DMAQ_A0	; Pointer to first empty slot in DMA Q
Y_DMAQ_NEXT	dc Y_DMAQ_A0	; Pointer to first nonempty slot in DMA Q or 0
Y_DMA_ARG	dc 0	; DMA descriptor argument
Y_SYSCALL	dc 0	; On-chip Y memory word used for syscall arg

; DMA state variables

Y_READ_TRIGGER		dc 0	; ptr value at which dma request goes out
Y_WRITE_TRIGGER		dc 0	; ptr value at which dma request goes out
Y_LAST_READ_ADDRESS	dc 0	; ptr to last ready element of read buffers
Y_WRITE_BLOCK_ADDRESS 	dc 0	; ptr to last empty element of write buffers

	if DMA_LOG_VERSION
Y_DMAQ_LOG_PTR		dc *+1
Y_DMAQ_LOG		dc 0
;	...
	endif

Y_DMA_TOP_REAL		equ *	; Pointer to top of Y memory used.
	if @def(Y_DMA_TOP)
	  if Y_DMA_TOP_REAL>Y_DMA_TOP
	    fail 'Too many on-chip Y variables used by fast_dma_support.asm'
	  endif
	else
	if DMA_LOG_VERSION
Y_DMA_TOP equ Y_DMA_TOP_REAL+32	; Allocate DMA request and DQ log
	else
Y_DMA_TOP equ Y_DMA_TOP_REAL	; Allocate DMA request
	endif
	endif

free2_after_y	equ	*	; first free location in bank 2 now

;------------------------- Bit fields in the status word ----------------------
;
B_DMA_ACTIVE 	equ 0	  	;  $1 - set when DMA is active
B_SYS_CALL	equ 1 		;  $2 - indicates sys call has been received
B_ABORTING	equ 2		;  $4 - indicates abort host command received
B_LAST_W_BUF	equ 3		;  $8 - set after abort during last input buf
B_IDLE   	equ 4		; $10 - abort complete (looked at using Bug56)
	if DEBUG_DMA
B_REGS_SAVED 	equ 5 		; $20 - set when regs saved (DEBUG_DMA)
B_READ_BLOCK 	equ 6 		; $40 - set when blocking until READ complete
B_WRITE_BLOCK 	equ 7 		; $80 - set when blocking until WRITE complete
B_READ_FLOWING	equ 8		;$100 - set when READ is actively flowing
B_WRITE_FLOWING	equ 9		;$200 - set when WRITE is actively flowing
B_AWAIT_NOT_HF1	equ 10		;$400 - set when waiting for hf1 to go low
B_AWAIT_HF1	equ 11		;$800 - set when waiting for hf1 to go high
	endif
B_SKIPPING_HDR	equ 22		;$400000 - set while skipping soundfile header
B_ERROR		equ 23		;$800000 - set on internal abort due to err

set_status macro bit
	bset #bit,y:Y_DMA_STATUS
	endm

clear_status macro bit
	bclr #bit,y:Y_DMA_STATUS
	endm

test_status macro bit
	btst #bit,y:Y_DMA_STATUS
	endm

jset_status macro bit,subr
	if Y_DMAQ_A0==0
	  jset #bit,y:Y_DMA_STATUS,subr
	else
	  btst #bit,y:Y_DMA_STATUS
	  jcs subr
	endif
	endm

jsset_status macro bit,subr
	if Y_DMAQ_A0==0
	  jsset #bit,y:Y_DMA_STATUS,subr
	else
	  btst #bit,y:Y_DMA_STATUS
	  jscs subr
	endif
	endm

jsclr_status macro bit,subr
	if Y_DMAQ_A0==0
	  jsclr #bit,y:Y_DMA_STATUS,subr
	else
	  btst #bit,y:Y_DMA_STATUS
	  jscc subr
	endif
	endm

set_bit macro bit,reg
	bset #m_\bit,x:m_\reg
	endm

clear_bit macro bit,reg
	bclr #m_\bit,x:m_\reg
	endm

; asm_goto - assemble short absolute jump address in common-denominator case.
; usage: asm_goto <JMP,Jxx,JSR,JSxx>,label
;  6-bit Absolute Short addresses: jclr,jsclr,jset,jsset
; 12-bit Absolute Short addresses: jxx,jmp,jsxx,jsr
; The DSP assembler should figure this out!
asm_goto macro op,addr
	if addr<64
	  op <addr ; must be in first 64 words for JScc, 4K for JMP, Jcc etc.
	else
	  op addr
	endif
	endm

; asm_plain_goto - assemble as if no macro
asm_plain_goto macro op,addr
	op addr
	endm
;
;------------------------------- Message codes ----------------------------
;
SC_W_REQ	equ	$020002	  ;"Sys call" requesting DMA write on chan 2
DM_R_REQ	equ	$050001	  ;"DSP message" requesting DMA read on chan 1
DM_W_REQ	equ	$040002	  ;message requesting DMA write on channel 2 
;
;------------------------------- Interrupt vectors ----------------------------
;
VEC_STK_ERR	equ	$0002	  ;stack error interrupt vector
VEC_HOST_RCV	equ	$0020	  ;host receive interrupt vector
VEC_HOST_XMT	equ	$0022	  ;host transmit interrupt vector
VEC_W_DONE	equ	$0024	  ;host command saying dma from dsp complete
VEC_R_DONE	equ	$0028	  ;host command saying dma to dsp complete
VEC_SYS_CALL	equ	$002C	  ;host command indicating sys-call int coming
VEC_ABORT 	equ 	$002E	  ;host command indicating external abort

	org	p:VEC_STK_ERR
iv_se	jsr	>dma_error

	org	p:VEC_HOST_RCV
iv_hr	movep 	x:m_hrx,y:(R_DMA)+	; DMA write to external memory
	nop

	org	p:VEC_HOST_XMT
iv_hx	movep 	y:(R_DMA)+,x:m_htx	; DMA read from x data memory
	nop

	org	p:VEC_R_DONE
iv_rc	jsr	>dma_read_complete

	org	p:VEC_W_DONE
iv_wc	jsr	>dma_write_complete

	org	p:VEC_SYS_CALL
	jsr	>sys_call

	org	p:VEC_ABORT
	jsr	>dma_error		; Not supported in this example

	org	p:dma_s_saved_lc

;---------------------------------------------------------------------------
; sys_call - field a request from the kernel
;
; A "system call" is a host command followed by one int written to the DSP.
; In the future, the int may specify more ints to follow.
; All currently possible syscall bits are listed in 
; /usr/include/nextdev/snd_dsp.h (search for SYSCALL).
;
; arg = 24bits = (8,,16) = (op,datum)
; 	where op = 1 for read and 2 for write
;	and datum is currently not used.
;
sys_call
	;; *** NOTE *** No regs saved, typically.
	jclr #m_hrdf,x:m_hsr,sys_call		;buzz until int received
	movep x:m_hrx,y:Y_SYSCALL		;int specifying operation
	if DMA_LOG_VERSION
	  set_status B_SYS_CALL			;set flag to say we got this
	  jsr 	save_regs
	  move #>SC_W_REQ,X0
	  move	y:Y_SYSCALL,A 			;int specifying operation
	  cmp	X0,A
	  jsne	dma_error
	  test_status B_READ_FLOWING
	  jscs	dma_error
	  jsr restore_regs
	endif
	if !BUG56_VERSION
	  set_bit hrie,hcr 			; enable dma output flow
	endif
	if DEBUG_DMA
	  set_status B_READ_FLOWING
	endif
	rti

;---------------------------------------------------------------------------
; Simple host-interface i/o
;
; "writeWordHost source" writes word in source to the host interface.
; "readWordHost dest" reads word in host interface to dest.
; These can only be used at the BEGINNING of the DSP program.
; After DMA transfers start, they cannot be used again.
;
writeWordHost macro source
	if !BUG56_VERSION
	  jclr #m_htde,x:m_hsr,*	; can't force short
	endif
        movep source,x:m_hrx
	endm	

;-------------------------------
readWordHost macro dest
	if !BUG56_VERSION
	  jclr #m_hrdf,x:m_hsr,*	; can't force short
	endif
        movep x:m_hrx,dest
	endm	

; DMA end-pointers
;
READ_END1	equ	READ_BUF2  ; End of first input buffer + 1
READ_END2	equ	READ_BUF1  ; End of second input buffer + 1 (modulo)
WRITE_END1	equ	WRITE_BUF2 ; End of first ouput buffer + 1
WRITE_END2	equ	WRITE_BUF1 ; End of 2nd out buf + 1 (modulo indexing)

;-------------------------------
;
; await_write_buf - block until all pending write requests are satisfied
;
await_write_buf
	move #Y_DMAQ_A0,R0
	do #4,awb_loop
	  move y:(R0)+,A
	  tst A #>$10000,X0
	  jeq awb_cont	  		; no request
	    and X0,A
	    jne awb_cont	  	; read request
	      enddo
	      jsclr_status B_DMA_ACTIVE,next_dma ; let any Q'd dma requests out
	      if DEBUG_DMA
		set_status B_WRITE_BLOCK
	      endif
	      jmp await_write_buf
awb_cont	  
	  if DEBUG_DMA
	    clear_status B_WRITE_BLOCK
	  endif
	  nop
	  nop
awb_loop
	rts

;-------------------------------
;
; await_read_buf - block until all pending read requests are satisfied
;
await_read_buf
	move #Y_DMAQ_A0,R0
	do #4,arb_loop
	  move y:(R0)+,A
	  tst A #>$10000,X0
	  jeq arb_cont	  		; no request
	    and X0,A
	    jeq arb_cont	  	; write request
	      enddo
              jsclr_status B_DMA_ACTIVE,next_dma ; let any Q'd dma requests out
	      if DEBUG_DMA
		set_status B_READ_BLOCK
	      endif
	      jmp await_read_buf
arb_cont  nop
	  nop
arb_loop
	  if DEBUG_DMA
	    clear_status B_READ_BLOCK
	  endif
	rts

;-------------------------------
;
; se_read_buf - sign-extend read buffer, and zero any remaining header
;
se_read_buf
	test_status B_SKIPPING_HDR
	jcc se_rb_noskip
	  move x:atc_header_size,A
	  move #>DMA_READ_SIZE,X0
	  cmp X0,A
	  tgt X0,A ; If header size exceeds buffer size, do one buffer
	  tst A    ; zero must be checked as a special case
	  jeq header_zeroed
	  move y:Y_READ_TRIGGER,R0
	  clr A A,X0
	  rep X0
	    move A,x:(R0)+	; zero up to one buffer of soundfile header
	  move x:atc_header_size,A
	  sub X0,A		; remaining header size, if any
	  move A,x:atc_header_size
	  jgt se_rb_noskip 	; continue skipping header
header_zeroed
	clear_status B_SKIPPING_HDR
se_rb_noskip
	move y:Y_READ_TRIGGER,R0 ; FIXME: Header needlessly sign extended
; do sign extension
	move #>$FFFF,x1
	move #>$8000,y1
	do #(DMA_READ_SIZE),se_loop
	  move x:(R0),A1
	  se24		; sign extend  to 24 bits i/o in A1
	  move A1,x:(R0)+
se_loop
	nop
	rts

;-------------------------------
check_reg macro r
	  if "r"=='R0'||"r"=='r0'
	    fail 'fast_dma_support.asm: Cannot use R0 for DMA reg'
	  endif
	endm

	check_reg R_DMA
	check_reg R_DMA_IN
	check_reg R_DMA_OUT
;
; dma_start - executed when DSP boots up. Resets DMA and starts first read.
;
;-------------------------------
dma_start 
	if BUG56_VERSION
	  move #(2*DMA_READ_SIZE-1),M_DMA_IN	; Modulo addressing for input
	  move #(2*DMA_WRITE_SIZE-1),M_DMA_OUT	; Modulo addressing for output
	  move #READ_BUF1,R_DMA_IN    	; init input pointer for first read
	  move #WRITE_BUF1,R_DMA_OUT    ; init output pointer for first write
	  rts
	endif
	set_bit hcie,hcr 			; enable host commands
	if DMA_READ_SIZE==DMA_WRITE_SIZE
	  move #DMA_READ_SIZE-1,M_DMA		; Modulo addressing by default
	else
	  move #$FFFF,M_DMA			; Linear addressing by default
	endif
	move #(2*DMA_READ_SIZE-1),M_DMA_IN	; Modulo addressing for input
	move #(2*DMA_WRITE_SIZE-1),M_DMA_OUT	; Modulo addressing for output
	move #0,X0
	move #Y_DMAQ_A0,R0
	rep #(Y_DMA_TOP-Y_DMAQ_A0)
	  move X0,y:(R0)+		; Clear DMA request Q, status, etc.
	move #Y_DMAQ_A0,X0
	move X0,y:Y_DMAQ_FREE
	move X0,y:Y_DMAQ_NEXT
	;
	; Clear DMA buffers
	;
	move #0,X0
	move #READ_BUF1,R0
	move #2*DMA_READ_SIZE,N0
	rep N0
	  move X0,y:(R0)+		; Clear DMA buffers

	move #WRITE_BUF1,R0
	move #2*DMA_WRITE_SIZE,N0
	rep N0
	  move X0,y:(R0)+		; Clear DMA buffers
	;
	if DMA_LOG_VERSION
	  move #Y_DMAQ_LOG,R0
	  move R0,y:Y_DMAQ_LOG_PTR	; Initialize DMA request and DQ log
	endif
	;
	; Initialize DMA state variables.
	; Request first DMA read.
	;
	move #READ_BUF2,R0		; trigger is always one buffer ahead
	move R0,y:Y_READ_TRIGGER	; init for enqueue_dma_read's sake
	move #READ_END2,X0		; actually beginning of read buffers
	move X0,y:Y_LAST_READ_ADDRESS	; init for dma_read_complete's sake
	asm_plain_goto jsr,enqueue_dma_read 	; prime input pipe
	;
	; Set up pointers for user i/o code
	;
	move #READ_BUF1,R_DMA_IN    	; init input pointer for first read
	move #WRITE_BUF1,R_DMA_OUT    ; init output pointer for first write
	move #WRITE_BUF2,X0		; ptr value when wbuf1 full
	move X0,y:Y_WRITE_TRIGGER	;  installed as trigger
	move #WRITE_END2,X0	  	; first buffer element we can't write
	move X0,y:Y_WRITE_BLOCK_ADDRESS ;  installed for proper blocking
	if BUG56_VERSION
	  jsr do_dma_read ; Simulate host getting around to one DMA write
	endif
	rts

;-------------------------------
getWordDMA
	if BUG56_VERSION
	  ; Assume first two buffers assembled in
	  move y:(R_DMA_IN)+,A	; requested read (last wd of NQ'd read buffer)
	  rts
	endif
;;	warn 'Reintroducing rwd_block bug'
rwd_block
	move R_DMA_IN,A			; address of next word to read
	move y:Y_LAST_READ_ADDRESS,X0	; first unavailable word
	cmp X0,A
	jne rwd_unblock
	jsclr_status B_DMA_ACTIVE,next_dma ; let any Q'd dma requests out
	if DEBUG_DMA
	  set_status B_READ_BLOCK
	endif
	asm_plain_goto jmp,rwd_block ; block until dma_read_complete is called
rwd_unblock
	if DEBUG_DMA
	  clear_status B_READ_BLOCK
	endif
	move y:Y_READ_TRIGGER,X0
	move R_DMA_IN,A
	cmp X0,A
	jseq enqueue_dma_read	; we depend on delay before host starts write:
	move y:(R_DMA_IN)+,A	; requested read (last wd of NQ'd read buffer)
	rts

;-------------------------------
; addWordDMA and friends.
; A whole buffer is accumulated before requesting DMA. 
;
; Registers A, B, X0, and Y0 are modified.
; Assumes R_DMA_OUT points to output buffer.
;
; NO BLOCKING IS DONE --- CALLER MUST AWAIT DMA TO HOST WHEN NEEDED
;
addWordDMA
	move y:(R_DMA_OUT),X0		; current output


	add X0,A			; add new value to output

; shift by 8 for output
	move A,X1 			; y1 contains 2^(-8)
	mpy X1,Y1,A

putWordDMA
	move A,y:(R_DMA_OUT)+		; requested write
	if WRITE_SNDOUT
	  move A,y:(R_DMA_OUT)+		; duplicate word for stereo output
	endif
	move R_DMA_OUT,B		; address of next word to read
	move y:Y_WRITE_TRIGGER,X0
	cmp X0,B
	jseq enqueue_dma_write
	rts

putWordNoTriggerDMA
	move A,y:(R_DMA_OUT)+		; requested write
	if WRITE_SNDOUT
	  move A,y:(R_DMA_OUT)+		; duplicate word for stereo output
	endif
	rts

; **************************** DMA QUEUE CODE *********************************

mask_host macro
	  ori #2,mr ; raise level to 2 (lock out host at level 1)
	  do #1,_loop
	   nop ; wait for pipeline to clear (need 8 cycles delay)
_loop
	  endm

unmask_host macro
	  andi #$FC,mr ; i1:i0 = 0
	  endm


update_write_trigger macro
	move y:Y_WRITE_TRIGGER,A
	move #WRITE_BUF1,X0
	cmp X0,A
	jne udwta_t
	move #WRITE_BUF2,X0
udwta_t move X0,y:Y_WRITE_TRIGGER
	endm

update_read_trigger macro	; returns read-trigger in X0 as side effect
	move y:Y_READ_TRIGGER,A
	move #READ_BUF1,X0
	cmp X0,A
	jne udrta_t
	move #READ_BUF2,X0
udrta_t move X0,y:Y_READ_TRIGGER
	endm

enqueue_dma_read			; CLOBBERS R0,A,X0
	update_read_trigger 		; toggle trigger address
	move X0,y:Y_DMA_ARG 		; argument to enqueue_dma
	bset #16,y:Y_DMA_ARG		; r/w~ bit
	asm_plain_goto jsr,enqueue_dma

	msg 'delete this debugging code at some point'
	move x:atc_bufs_reqd,A
	move x:int_1,X0
	add  X0,A
	move A,x:atc_bufs_reqd
	
	rts

enqueue_dma_write			; CLOBBERS R0,A,X0
	update_write_trigger 		; toggle trigger address
	move y:Y_WRITE_TRIGGER,R0
	move R0,y:Y_DMA_ARG 		; argument to enqueue_dma
	bclr #16,y:Y_DMA_ARG		; r/w~ bit
	asm_plain_goto jsr,enqueue_dma
	rts

; enqueue_dma - Place DMA descriptor into next free element of DMA Q.
;		DMA descriptor (direction,,address) passed in y:Y_DMA_ARG. 
;		Since interrupts are turned off, interrupt-level regs used.
;
enqueue_dma
	mask_host		; Act like an interrupt handler
	asm_plain_goto jsr,save_regs	; We need R0.
	move #3,M0		; Q is length 4, modulo
	move y:Y_DMAQ_FREE,R0	; ptr to next free place in DMA Q
	move y:Y_DMA_ARG,X0	; direction,,address
	if DEBUG_DMA
	  move y:(R0),A		; descriptor should be zero unless DMA Q full
	  tst A			; Blocking should prevent DMA Q from filling
	  jsne dma_error
	endif
	move X0,y:(R0)+		; enqueue dma descriptor
	move R0,y:Y_DMAQ_FREE	; advance free pointer
	jsclr_status B_DMA_ACTIVE,next_dma ; DMA restart (can't force short)
	asm_plain_goto jsr,restore_regs
	unmask_host
	rts

	if DMA_LOG_VERSION
wrap_log_ptr	
; on entry, R0 points to word in log just written
; X0 and B clobbered
	  move #>Y_DMA_TOP,B
	  move R0,X0
	  cmp X0,B		; B-X0 = TOP-current
	  jge dd_cont
	    move #Y_DMAQ_LOG,R0
dd_cont	  move R0,y:Y_DMAQ_LOG_PTR ; update pointer
	  move M0,y:(R0)	; Flag where we are in log
 	  rts
	endif

dequeue_dma			; CALLED AT INTERRUPT LEVEL WITH REGS SAVED
	clr A y:Y_DMAQ_NEXT,R0	; active-DMA pointer
	move #3,M0		; DMA Q is modulo
	nop
	if DMA_LOG_VERSION
	  move y:(R0),A		; old DMA descriptor
	  move #-1,M0
	  move y:Y_DMAQ_LOG_PTR,R0
	  nop
	  move R_DMA,y:(R0)+	; check up on final DMA transfer address
	  jsr wrap_log_ptr	; possibly flip R0 back to log start
	  move A,y:(R0)		; write dma descr for last xfer to log
	  bset #23,y:(R0)+	; flag this entry as a "dequeue"
	  jsr wrap_log_ptr	; possibly flip R0 back to log start
	  move y:Y_DMAQ_NEXT,R0	; restore R0
	  move #3,M0		; DMA Q is modulo
	  clr A
	endif	
	move A,y:(R0)+		; clear y:(y:Y_DMAQ_NEXT) to mark cell as done
	move R0,y:Y_DMAQ_NEXT	; advance "next" pointer
	clear_status B_DMA_ACTIVE ; next_dma insists on this condition
	asm_plain_goto jsr,next_dma	 ; start next dma, if any
dd_nodq rts

next_dma			; CALLED AT INTERRUPT LEVEL WITH REGS SAVED
	; called only when DMA not active to start up a DMA
	; called by enqueue_dma, in which case Q will never be empty
	; called by dequeue_dma, in which case Q may be empty
	if DEBUG_DMA
	  jsset_status B_DMA_ACTIVE,dma_error
	endif
	move y:Y_DMAQ_NEXT,R0	; address of next DMA descriptor
	move #$ffff,M0		; linear mode
	move y:(R0),A		; DMA descriptor
	tst A			; zero means
	jeq nd_stop		;   nothing to do
	if DMA_LOG_VERSION
	  move y:Y_DMAQ_LOG_PTR,R0
	  nop
	  move A,y:(R0)+	; ASSUMES M0 == -1 !
	  jsr wrap_log_ptr	; possibly flip R0 back to log start
	  move y:Y_DMAQ_NEXT,R0	; address of next DMA descriptor
	endif	
	move A1,R_DMA		; DMA start address, stripping r/w~ bit
	jset #16,y:(R0),nd_read ; test r/w~ bit (can't force short)
nd_write
	  if DEBUG_DMA
	    set_status B_AWAIT_NOT_HF1
	  endif
	  jset	#m_hf1,x:m_hsr,nd_write		; make sure HF1 is low
	  if DEBUG_DMA
	    clear_status B_AWAIT_NOT_HF1
	  endif
	  jclr #m_htde,x:m_hsr,nd_write 	; wait until we can write host
	  movep	#DM_R_REQ,x:m_htx		; send "read request" DSP msg
	  if DEBUG_DMA
	    set_status B_AWAIT_HF1
	  endif
	  if !BUG56_VERSION
nd_ahf1     jclr #m_hf1,x:m_hsr,nd_ahf1		; HF1 means DMA is set up to go
	  endif
	  if DEBUG_DMA
	    clear_status B_AWAIT_HF1
	  endif
	  if !BUG56_VERSION
	    set_bit htie,hcr 			; Go
	  endif
	if DEBUG_DMA
	  set_status B_WRITE_FLOWING
	endif
	asm_plain_goto jmp,nd_run

nd_read	
	jclr #m_htde,x:m_hsr,nd_read	 	; wait until we can write host
	jset #m_dma,x:m_hsr,nd_read 		; wait until prev dma done
	jset #m_hf1,x:m_hsr,nd_read 		; wait until prev dma done
	movep	#DM_W_REQ,x:m_htx		; send "write request" DSP msg
	;* set_bit hrie,hcr 			; done when sys_call comes in

nd_run	set_status B_DMA_ACTIVE			; DMA is "active"
	rts

nd_stop	clear_status B_DMA_ACTIVE ; Empty DMA Q => DMA stops

	rts

; *************************** INTERRUPT HANDLERS ******************************

saved_a2 dc 0
saved_a1 dc 0
saved_a0 dc 0
saved_x0 dc 0
saved_r0 dc 0
saved_m0 dc 0

save_regs
	if DEBUG_DMA
	  jsset_status B_REGS_SAVED,dma_error
	endif
	move A2,p:saved_a2
	move A1,p:saved_a1
	move A0,p:saved_a0
	move X0,p:saved_x0
	move R0,p:saved_r0
	move M0,p:saved_m0
	if DEBUG_DMA
	  set_status B_REGS_SAVED
	endif
	rts

restore_regs
	if DEBUG_DMA
	  jsclr_status B_REGS_SAVED,dma_error
	endif
	move p:saved_a2,A2
	move p:saved_a1,A1
	move p:saved_a0,A0
	move p:saved_x0,X0
	move p:saved_r0,R0
	move p:saved_m0,M0
	if DEBUG_DMA
	  clear_status B_REGS_SAVED
	endif
	rts

update_write_block_address macro ; CALLED AT INTERRUPT LEVEL WITH REGS SAVED
	move y:Y_WRITE_BLOCK_ADDRESS,A
	move #WRITE_END1,X0
	cmp X0,A
	jne ulwa_t		; addresses toggle
	move #WRITE_END2,X0
ulwa_t  move X0,y:Y_WRITE_BLOCK_ADDRESS
	endm

update_last_read_address macro	; CALLED AT INTERRUPT LEVEL WITH REGS SAVED
	move y:Y_LAST_READ_ADDRESS,A
	move #READ_END1,X0
	cmp X0,A
	jne ulra_t		; addresses toggle
	move #READ_END2,X0
ulra_t  move X0,y:Y_LAST_READ_ADDRESS
	endm

dma_write_complete
	asm_plain_goto jsr,save_regs
	if DEBUG_DMA
	    jsset_status B_READ_FLOWING,dma_error
	endif
	update_write_block_address 	; write buffer freed
	clear_bit htie,hcr   		; shouldn't matter
	if DEBUG_DMA
	    clear_status B_WRITE_FLOWING
	endif
	asm_plain_goto jsr,dequeue_dma	; remove dma ptr from Q
	asm_plain_goto jsr,restore_regs
	rti

dma_read_complete
	asm_plain_goto jsr,save_regs
	if DEBUG_DMA
	    jsset_status B_WRITE_FLOWING,dma_error
	endif
	update_last_read_address 	; read buffer filled
	clear_bit hrie,hcr   		; shouldn't matter
	if DEBUG_DMA
	  clear_status B_READ_FLOWING
	endif
	asm_plain_goto jsr,dequeue_dma	; remove dma ptr from Q
	asm_plain_goto jsr,restore_regs
	rti

dma_error
	set_status B_ERROR
	if BUG56_VERSION
		SWI
	else
		ori #2,mr ; raise level to 2 (lock out host interrupts)
		set_bit	hf3,hcr	; abort code = HF2 and HF3
		set_bit hf2,hcr
		movec sp,x:saved_sp
dma_abort	asm_plain_goto jmp,dma_abort
	endif

	if BUG56_VERSION

do_dma_write ; CALL AT USER LEVEL
 	  do #DMA_WRITE_SIZE,ddw_wloop
ddw_wblock  jclr #m_htde,x:m_hsr,ddw_wblock	; Manually read words in Bug56
	     movep 	y:(R_DMA)+,x:m_htx	; DMA read from x data memory
ddw_wloop
	  jsr dma_write_complete		; Don't issue host command
	rts

do_dma_read ; CALL AT USER LEVEL
	if 0
	  do #DMA_READ_SIZE,ddr_rloop
ddr_rblock  jclr #m_hrdf,x:m_hsr,ddr_rblock	; Manually feed words in Bug56
	    movep x:m_hrx,y:(R_DMA)+		; DMA write to external memory
ddr_rloop
	endif
	  jsr dma_read_complete			; Don't issue host command
	  rts

	endif					; BUG56_VERSION



; save i/o pointers
save_atc_io_pointers
	move 	r6,x:<save_r6
	move 	m6,x:<save_m6
	move 	r7,x:<save_r7
	move 	m7,x:<save_m7
	move 	#$FFFF,m6
	move 	m6,m7
	rts


; Increment frame number  if mono or stereo (channel 1)
; toggle channel index between 0 and 1
update_frame_number
	jmp_mono new_frame ; more generally, compare #channels to zero
	bchg	#0,x:channel_index	; more generally, incr until = atc_channels
	jcc	same_frame
new_frame
	move	x:<int_1,x1
	if DEBUG_DMA
	  move #>1,A
	  cmp X1,A
	  jsne dma_error
	endif
	move	x:frame_number,a
	add	x1,a
	move	a1,x:frame_number

same_frame
	rts