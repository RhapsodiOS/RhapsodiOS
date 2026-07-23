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
; Mono to stereo, 8 to 16 bit (for performing format SND_FORMAT_LINEAR_8)
;
	include	"dspsound.asm"
main
	jsr	start
loop
	jsr	getHost	; 8-bit sample right-justified to A
;
; NOTE A *would* contain two 8-bit samples right-justified to A
; if 16-bit DMA were used as it should be.  (This was first
; written before DMA to the DSP worked.)
;
	move    #>@pow(2,-8),x0
	move	a,y0
	mpy	x0,y0,a
	move	a0,y0
	move    #>@pow(2,-8),x1
	mpy	x1,y0,a	; want 16-bits right justified in A
	jsr	putHost
	jsr	putHost
	jcs	stop
	jmp	loop


