/*
 * Copyright (c) 1999 Apple Computer, Inc. All rights reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 * 
 * "Portions Copyright (c) 1999 Apple Computer, Inc.  All Rights
 * Reserved.  This file contains Original Code and/or Modifications of
 * Original Code as defined in and that are subject to the Apple Public
 * Source License Version 1.0 (the 'License').  You may not use this file
 * except in compliance with the License.  Please obtain a copy of the
 * License at http://www.apple.com/publicsource and read it before using
 * this file.
 * 
 * The Original Code and all software distributed under the License are
 * distributed on an 'AS IS' basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE OR NON-INFRINGEMENT.  Please see the
 * License for the specific language governing rights and limitations
 * under the License."
 * 
 * @APPLE_LICENSE_HEADER_END@
 */
/*
 * bootpdfile.h
 * - routines and variables to parse
 */
extern char	boot_home_dir[128];/* bootfile directory */
extern char	boot_tftp_dir[128];/* bootfile directory given to tftpd */
extern char	boot_default_file[64];/* default file to boot */

void 		bootp_readtab();
boolean_t 	bootp_getbyhw_file(u_char hwtype, void * hwaddr, int hwlen,
				   struct in_addr * iaddr_p, 
				   u_char * * hostname,
				   u_char * * bootfile);
boolean_t       bootp_getbyip_file(struct in_addr ciaddr, u_char * * hostname, 
				   u_char * * bootfile);

