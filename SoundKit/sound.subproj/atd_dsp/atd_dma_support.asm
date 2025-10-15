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
	define SR_SPACE 'x'

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

	if !@def(DMA_LOG_VERSION)
DMA_LOG_VERSION	  set 0
	endif

dma_s_saved_lc	set *

;------------------------- Y memory locations used ----------------------

	org y:(free2+3)&$FFFC ; first free mod-4 location in bank 2

Y_DMAQ_A0	dc 0	; Enqueued DMA request  - Must be "modulo aligned"
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
	if DEBUG_DMA
Y_READ_PAREN	 	dc 0	; +1 for each request, -1 for each read rcvd
	endif

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
Y_DMA_TOP equ Y_DMA_TOP_REAL+32	; Allocate DMA request and DMAQ log
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
B_CMD_RCVD	equ 12		;$1000 - set when command rcvd from host
B_NEW_ADD_DROP	equ 13		;$2000 - set on receipt of add/drop spec
B_ADDING	equ 14		;$4000 - set when inserting samples
B_ARG_INDEX	equ 15		;$8000 - 0 for host_arg1, 1 for host_arg2
B_PHASE_ERROR	equ 16		;$10000 - set when opcode unrecognized
B_MEM_SMASH	equ 17		;$20000 - set when memory-smasher detected
B_BAD_WID	equ 18		;$40000 - set when bad cbwidth value detected
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

jclr_status macro bit,subr
	if Y_DMAQ_A0==0
	  jclr #bit,y:Y_DMA_STATUS,subr
	else
	  btst #bit,y:Y_DMA_STATUS
	  jcc subr
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

bset_status macro bit
	bset #bit,y:Y_DMA_STATUS
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
VEC_HR_DMA	equ	$002A	  ;not used directly. Holds DMA HOST_RCV
VEC_SYS_CALL	equ	$002C	  ;host command indicating sys-call int coming
VEC_ABORT 	equ 	$002E	  ;host command indicating external abort
VEC_HR_PW	equ	$0030	  ;not used directly. Holds PIO HOST_RCV

	org	p:VEC_STK_ERR
iv_se	jsr	>dma_error

	org	p:VEC_HOST_RCV
iv_hr	jsr	>pio_word_received

	org	p:VEC_HR_PW
iv_pw	jsr	>pio_word_received

	org	p:VEC_HR_DMA
iv_dmaw	movep 	x:<<m_hrx,y:(R_DMA)+	; DMA write (from host)
	nop

	org	p:VEC_HOST_XMT
iv_hx	movep 	y:(R_DMA)+,x:<<m_htx	; DMA read from x data memory
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
	;; !!! CAREFUL !!! ONLY X0 SAVED !!!
	move X0,SR_SPACE:saved_x0
	jclr #m_hrdf,x:m_hsr,sys_call		;buzz until int received
	movep x:m_hrx,y:Y_SYSCALL		;int specifying operation
	if DEBUG_DMA
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
	  set_io_bit hrie,hcr 			; enable dma output flow
	endif
	move p:iv_dmaw,X0			; new host_rcv handler
	move X0,p:iv_hr
	move p:(iv_dmaw+1),X0			; second word of handler
	move X0,p:(iv_hr+1)
	if DEBUG_DMA
	  set_status B_READ_FLOWING
	endif
	move SR_SPACE:saved_x0,X0
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
;* needed?    jsclr_status B_DMA_ACTIVE,next_dma ; let any Q'd dma requests out
	      if DEBUG_DMA
		set_status B_READ_BLOCK
	      endif
	      jmp await_read_buf
arb_cont	  
	  if DEBUG_DMA
	    clear_status B_READ_BLOCK
	  endif
	  nop
	  nop
arb_loop
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
	set_io_bit hcie,hcr 			; enable host commands
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
	; Start first DMA read.
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
	;
	; Enable host receive interrupts for args from host
	;
	if !BUG56_VERSION
	  set_io_bit hrie,hcr 		; Enable PIO and DMA receipt
	endif
	rts

;-------------------------------
getWordDMA
	if BUG56_VERSION
	  ; Assume first two buffers assembled in
	  move y:(R_DMA_IN)+,A	; requested read (last wd of NQ'd read buffer)
	  rts
	endif
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

; **************************** DMA QUEUE CODE *********************************

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
	  move y:Y_DMAQ_NEXT,R0 ; restore R0
	  move #3,M0		; DMA Q is modulo
	  clr A
	endif	
	move A,y:(R0)+		; clear y:(y:Y_DMAQ_NEXT) to mark cell as done
	move R0,y:Y_DMAQ_NEXT	; advance "next" pointer
	clear_status B_DMA_ACTIVE ; next_dma insists on this condition
	asm_plain_goto jsr,next_dma ; start next dma, if any
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
	  move y:Y_DMAQ_NEXT,R0 ; address of next DMA descriptor
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
	    set_io_bit htie,hcr 		; Go
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
	;* set_io_bit hrie,hcr 			; done when sys_call comes in
	if DEBUG_DMA
	  move y:Y_READ_PAREN,A
	  move #>1,X0
	  add X0,A
	  move A,y:Y_READ_PAREN
	endif
nd_run	set_status B_DMA_ACTIVE			; DMA is "active"
	rts

nd_stop	clear_status B_DMA_ACTIVE ; Empty DMA Q => DMA stops

	rts

; *************************** INTERRUPT HANDLERS ******************************

	org SR_SPACE:*

saved_a2 	dc 	0
saved_a1 	dc 	0
saved_a0 	dc 	0
saved_x0 	dc 	0
saved_r0 	dc 	0
saved_m0 	dc 	0

host_arg1	dc	0
host_arg2	dc	0

	if TEST_DROP_ADD
	warn 'Hacked here to test drop/add'
add_drop_count	dc	102400
add_drop_time	dc	0
	else
add_drop_count	dc	0
add_drop_time	dc	0
	endif

	org p:*

save_regs
	if DEBUG_DMA
	  jsset_status B_REGS_SAVED,dma_error
	endif
	move A2,SR_SPACE:saved_a2
	move A1,SR_SPACE:saved_a1
	move A0,SR_SPACE:saved_a0
	move X0,SR_SPACE:saved_x0
	move R0,SR_SPACE:saved_r0
	move M0,SR_SPACE:saved_m0
	if DEBUG_DMA
	  set_status B_REGS_SAVED
	endif
	rts

restore_regs
	if DEBUG_DMA
	  jsclr_status B_REGS_SAVED,dma_error
	endif
	move SR_SPACE:saved_a2,A2
	move SR_SPACE:saved_a1,A1
	move SR_SPACE:saved_a0,A0
	move SR_SPACE:saved_x0,X0
	move SR_SPACE:saved_r0,R0
	move SR_SPACE:saved_m0,M0
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
	clear_io_bit htie,hcr   	; shouldn't matter
	if DEBUG_DMA
	    clear_status B_WRITE_FLOWING
	endif
	asm_plain_goto jsr,dequeue_dma	; remove dma ptr from Q
	asm_plain_goto jsr,restore_regs
	rti

dma_read_complete			; DMA from host is complete
	asm_plain_goto jsr,save_regs
	if DEBUG_DMA
	    jsset_status B_WRITE_FLOWING,dma_error
	    move y:Y_READ_PAREN,A
	    move #>1,X0
	    sub X0,A
	    move A,y:Y_READ_PAREN
	endif
	update_last_read_address 	; read buffer filled
;;	clear_io_bit hrie,hcr   	; leave hrie on for host args
	if DEBUG_DMA
	  clear_status B_READ_FLOWING
	endif
	move p:iv_pw,X0			; new host_rcv handler for PIO
	move X0,p:iv_hr
	move p:(iv_pw+1),X0		; second word of handler
	move X0,p:(iv_hr+1)
	asm_plain_goto jsr,dequeue_dma	; remove dma ptr from Q
	asm_plain_goto jsr,restore_regs
	rti

cmd_error
dma_error
	set_status B_ERROR
	if BUG56_VERSION
		SWI
	else
		ori #2,mr ; raise level to 2 (lock out host interrupts)
		set_io_bit	hf3,hcr	; abort code = HF2 and HF3
		set_io_bit hf2,hcr
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

;
; ----------------------------- pio_word_received ----------------------------

pio_word_received
	asm_plain_goto jsr,save_regs	; save A, X0, R0, M0
	if DEBUG_DMA
	    jsset_status B_READ_FLOWING,dma_error
	    jsclr #m_hrdf,x:<<m_hsr,cmd_error
	endif
;get arg
	jset_status B_ARG_INDEX,pwr_arg2
;
; Receive arg 1
;
;*unused* jset_status B_CMD_RCVD,pwr_done	; previous arg not used yet
pwr_ra1	move x:m_hrx,A				; fetch arg1
	move A,SR_SPACE:host_arg1
	set_status B_ARG_INDEX
	jset #m_hrdf,x:<<m_hsr,pwr_ra1		; hope '040 has written arg 2
	jmp pwr_done
pwr_arg2
	move x:m_hrx,A				; fetch arg2
	move A,SR_SPACE:host_arg2
	clear_status B_ARG_INDEX
;
; strip opcode bit so that all command handlers below can assume arg1 in A1
;
	move #>$FF,X0	; strip off uppermost byte = opcode
	move SR_SPACE:host_arg1,A 
	and X0,A
;
; Equalizer Gains
;
;*	jclr #EQGAIN_CMD_BIT,SR_SPACE:host_arg1,pwr_not_eqgain
	btst #EQGAIN_CMD_BIT,SR_SPACE:host_arg1
	jcc pwr_not_eqgain
	if DEBUG_DMA
		move #>(NCB-1),X0	; maximum offset possible
		cmp X0,A   ; A contains offset into eq gain table	
		jsgt cmd_error
		tst A
		jslt cmd_error
	endif
 	move #cbgain,X0	; A contains offset into eq gain table	
	add X0,A	; address of gain to poke
	move A1,R0
	move #$ffff,M0	; linear addressing (required since fft uses M0==0)
	move SR_SPACE:host_arg2,A
	move A,x:(R0)
	jmp pwr_done
pwr_not_eqgain
;*	jclr #SYNCH_CMD_BIT,SR_SPACE:host_arg1,pwr_not_synch
	btst #SYNCH_CMD_BIT,SR_SPACE:host_arg1
	jcc pwr_not_synch
	move SR_SPACE:add_drop_time,X0
	add X0,A
	move A,SR_SPACE:add_drop_time	; time limit in samples to accomplish drop/add
	move SR_SPACE:host_arg2,X0 ; plus (add) or minus (drop) #samples to fudge
	move SR_SPACE:add_drop_count,A
	add X0,A
	move A,SR_SPACE:add_drop_count
	bset_status B_NEW_ADD_DROP
	jmp pwr_done
pwr_not_synch
	;; any other commands go here (up to 8 before encode, then up to 256)
	; if here, opcode was unrecognized.  Assume phase error:
	set_status B_PHASE_ERROR	; want to know about this
	move SR_SPACE:host_arg2,X0
	move X0,SR_SPACE:host_arg1
	set_status B_ARG_INDEX
	jset #m_hrdf,x:<<m_hsr,pwr_ra1	; maybe arg 2 is already waiting
pwr_done asm_plain_goto jsr,restore_regs
	rti

; ----------------------- Insert or delete  samples -----------------------
; add_drop_samples - called by atd_util.asm:process_frame before FFT.
;   if add_drop_count is nonzero,  
;	subtract delta_outstep from it
;	Compute new delta_outstep if host has updated drop/add specification.
; 	Add delta_outstep to add_drop_count
; Note that add_drop_count and add_drop_time are updated by HC interrupt.
;
;**	warn 'synchronization hacked out here'
	if 1	; hack
add_drop_samples
	move	SR_SPACE:add_drop_count,a ; number of samples to drop/add
	tst	a
	jne	ads_working
	  rts
ads_working	; assumes nonzero SR_SPACE:add_drop_count in A
	clear_status B_ADDING		; save sign bit
	jlt	ads_neg
	  set_status B_ADDING		;   for later convenience
ads_neg	abs a	x:<delta_outstep,b	; current warpage per frame
	abs	b
	sub	b,a
	jle	ads_stop_add_drop ; finished drop/add
	jset_status B_ADDING,ads_adg
	  neg a a,y0
ads_adg	move    a,SR_SPACE:add_drop_count	; updated drop/add count

	jclr_status B_NEW_ADD_DROP,ads_continue_add_drop
;
; Host has updated the add/drop count => need to recompute new_outstep
; On entry, y0 = drop_count
;
	clear_status B_NEW_ADD_DROP
	move	#>1,b	; proposed delta
	move    SR_SPACE:add_drop_time,a
	tst 	a	a,y1
	jeq 	ads_have_delta	; drop_time 0 means take your time
	move	#>FRAME_STEP,x0
;
; In loop below, x0=FRAME_STEP/delta, y0=abs(drop_count), b=delta, y1=drop_time
;
ads_lp	mpy	x0,y0,a 	; a = how long we'd take at current delta
	cmp	y1,a		; do we make it?
	jlt	ads_have_delta
	  asl	b	x0,a	; no, try doubling delta
	  asr	a 		; update FRAME_STEP/delta
	  move	a,x0
	jmp	ads_lp

ads_have_delta			; delta in b
	move #>FRAME_STEP,a
	asr a	; FRAME_STEP/2
	cmp b,a
	tlt a,b	; limit delta to FRAME_STEP/2
	move SR_SPACE:add_drop_count,a
	tst a
	jgt ads_pls
	  neg b
ads_pls	move b,x:<delta_outstep
	move #>FRAME_STEP,a
	add  b,a
	move a,x:<newoutstep	; takes effect NEXT frame
	rts

ads_continue_add_drop
	move    x:<newoutstep,b ; one frame of delay
	move	b,x:<outstep
	rts

ads_stop_add_drop
	move	#>FRAME_STEP,y1
	clr a	y1,x:<outstep	; restore outstep
	move a,SR_SPACE:add_drop_count
	move a,SR_SPACE:add_drop_time
	move a,x:<delta_outstep
	clear_status B_ADDING
	rts

	endif	; hack

; ----------------------------- FFT save/restore ----------------------------

save_io_pointers ; called by atd_util.asm:process_frame prior to FFT
	move 	r6,x:<saved_r6 ; assumed left alone by overlap_add
	move 	m6,x:<saved_m6
	move 	r7,x:<saved_r7 ; assumed left alone by overlap_add
	move 	m7,x:<saved_m7
	rts
		
restore_io_pointers ; called by atd_util.asm:process_frame after FFT
	move 	x:<saved_r6,r6	; overlap_add is where these are needed
	move 	x:<saved_m6,m6
	move 	x:<saved_r7,r7
	move 	x:<saved_m7,m7
	rts


;============================= OFF-CHIP SEGMENTS ============================

; !!! NOTE !!! THESE ARE NOT SUBROUTINES OR MACROS !!!
; You jump to them and they jump back.  They exist purely
; because we cannot fit everything on chip

; ola_check_write_trigger - jumped to from overlap_add in atd_util.asm.
;
; y:Y_WRITE_TRIGGER is one of the two buffer addresses.  If we crossed it
; above, we need to call enqueue_dma_write to have the buffer picked up
; by the host.  We wrote either 256 (mono) or 512 (stereo) samples, and
; the buffers are each length 1024.  If we crossed a trigger, R_DMA_OUT
; will be at most 255 (mono) or 512 (stereo) larger than the trigger address.
; If we triggered last time with equality (mono) or 1 past (stereo), 
; then R_DMA_OUT will be 256 (mono) 513 (stereo) greater this time.
; Let N be 256 or 512 for mono or stereo out respectively.  Then we trigger if
;
; 		0 <= (R_DMA_OUT-y:Y_WRITE_TRIGGER) < N	(mono)
; 		0 < (R_DMA_OUT-y:Y_WRITE_TRIGGER) <= N	(stereo)
;
; The mono and stereo cases have different fence-posts because
; indexing by two leaves R_DMA_OUT one past the next write address for 
; channel 0 after channel 1 is written out.
;
; Can arbitrary changes in x:newoutstep screw anything up here?
;
ola_check_write_trigger
	move R_DMA_OUT,B		; address of next word to write
	move y:Y_WRITE_TRIGGER,X0
	sub X0,B			; this is done on each word to enable
	jlt ola_copy_go			; negative => trigger impossible
	jmp_mono ola_mono_trigger_check
ola_stereo_trigger_check
	  ; stereo case, address difference known to be >= 0, need >0 && <=N
	  jmp_chan0 ola_copy_go		; all triggers after channel 1 written
	  tst B				; "jmp" macros destroy this
	  jeq ola_copy_go
	  move x:outstep,A		; N = "512"
	  asl	A
	  cmp A,B			; (R_DMA_OUT-y:Y_WRITE_TRIGGER) -N
	  jsle enqueue_dma_write	; write trigger occurred
	  jmp ola_copy_go
ola_mono_trigger_check
	  ; mono case, address difference known to be >= 0, need <N
	  move x:outstep,X0		; N = "256"
	  cmp X0,B			; (R_DMA_OUT-y:Y_WRITE_TRIGGER) -N
	  jslt enqueue_dma_write	; write trigger occurred
	  jmp ola_copy_go

; -------------------------------------------------------------------------


