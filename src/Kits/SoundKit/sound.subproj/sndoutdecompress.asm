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
; sndoutdecompress.asm
;	See comments in decompress.asm
;	This is the version that sends samples to soundout.

	opt	mex
	page	132

WRITE_SNDOUT	equ	1
	
	; The sound driver requires lead pad because it starts soundout
	; DMA right away - while the DSP is still producing the first
	; real buffer.  ** Actually this may now be fixed, but it is nice
	; to have leading and trailing zeros anyway. **
	; BUG #7912 - Setting lead pad to zero fixes the problem of sndout
	; aborting with a large file header.
LEADPAD		equ	0	;number of buffers before sound begins
TRAILPAD	equ	4	;number of buffers after sound ends

	include "dspsounddi.asm"
	include "decompress.asm"

