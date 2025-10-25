/*
 * Copyright (c) 1999, 2000-2001 Apple Computer, Inc. All rights reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 *
 * The contents of this file constitute Original Code as defined in and
 * are subject to the Apple Public Source License Version 1.1 (the
 * "License").  You may not use this file except in compliance with the
 * License.  Please obtain a copy of the License at
 * http://www.apple.com/publicsource and read it before using this file.
 *
 * This Original Code and all software distributed under the License are
 * distributed on an "AS IS" basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE OR NON-INFRINGEMENT.  Please see the
 * License for the specific language governing rights and limitations
 * under the License.
 *
 * @APPLE_LICENSE_HEADER_END@
 */

/*
	File:		comp.c

	Contains:	NULL compression. Kernel version of Yarrow assumes
				incoming seed data is truly random.
*/
#include "dev/random/YarrowCoreLib/include/WindowsTypesForMac.h"
#include "comp.h"

/* null compression */
comp_error_status comp_init(COMP_CTX* ctx)
{
	return COMP_SUCCESS;
}


comp_error_status comp_add_data(COMP_CTX* ctx,Bytef* inp,uInt inplen)
{
	return COMP_SUCCESS;
}

comp_error_status comp_get_ratio(COMP_CTX* ctx,float* out)
{
	*out = 1.0;
	return COMP_SUCCESS;
}

comp_error_status comp_end(COMP_CTX* ctx)
{
	return COMP_SUCCESS;
}
