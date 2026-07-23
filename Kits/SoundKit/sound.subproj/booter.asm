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
	include	"portdefs.asm"

X_P_SIZE	equ 6			;size of bootstrapper
X_P_LOAD	equ XRAMHI-X_P_SIZE	;reserved space for bootstrapper

	org	p:VEC_RESET
	jmp	reset
	
	org	p:VEC_END
reset
        movec   #6,OMR			;data rom enabled, mode 2
	bset    #0,x:PBC		;host port
	movep   #>$0001F7,x:PCC		;both serial ports (SC0 not available)
	bset	#3,x:PCDDR		;   pc3 is an output with value
	bclr	#3,x:PCD		;   zero to enable the external ram
	movep   #>$000000,x:BCR		;no wait states on the external sram
        movep   #>$00B400,x:IPR  	;intr levels: SSI=2, SCI=1, HOST=0
next_segment			;Load a segment
	jsr	get_host	; get memory space
	move	a,b
	jsr	get_host	; load address to r0
	move	a1,r0
	jsr	get_host	; word count to x0
	move	a1,x0
	move	#>1,a
	cmp	a,b	#>2,a
	jeq	x_load		; 1 means x memory
	cmp	a,b	#>3,a
	jeq	y_load		; 2 means y memory
	cmp	a,b	#>4,a
	jeq	l_load		; 3 means l memory
	cmp	a,b
	jne	skip_seg	; 4 means p memory
	clr	a
	move	r0,a
	tst	a
	jeq	final_p
	jmp	p_load
skip_seg			; anything is skipped
	do	x0,skip_loop
	jsr	get_host
skip_loop
	jmp	next_segment
p_load
	do	x0,pl_loop
	jsr	get_host
	move	a1,p:(r0)+
pl_loop
	jmp	next_segment
x_load
	do	x0,xl_loop
	jsr	get_host
	move	a1,x:(r0)+
xl_loop
	jmp	next_segment
y_load
	do	x0,yl_loop
	jsr	get_host
	move	a1,y:(r0)+
yl_loop
	jmp 	next_segment
l_load
	move	x0,a
	asr	a
	move	a,x0
	do	x0,ll_loop
	jsr	get_host
	move	a1,x:(R0)
	jsr	get_host
	move	a1,y:(r0)+
ll_loop
	jmp	next_segment
get_host
	jclr	 #HRDF,x:HSR,get_host
	move	x:HRX,a
	rts
final_p
	move	#p_mem_loop,r2
	move	#X_P_LOAD,r1
	do	#6,load_p_mem_loop
	movem	p:(r2)+,y0
	movem	y0,p:(r1)+
load_p_mem_loop
	jmp	X_P_LOAD

;
;The following gets loaded into external memory before running.
;Assumes r0 is set to zero and x0 has the count on entry
;
p_mem_loop
	dc	$06c400
	dc	$003ffe
	dc	$0aa980
	dc	$003ffc
	dc	$08586b
	dc	$0c0000
;
;Which really is:
;
;	org	p:XRAMHI-6
;p_mem_loop
;	do	x0,_done
;_get
;	jclr	#HRDF,x:HSR,_get
;	movep	x:HRX,p:(r0)+
;_done
;	jmp	reset


