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
 * afpuser.h
 * - definitions for afp machine "user" API
 */
#define nil pascal_nil
#import <oamshim/MacTypes.h>
#import <oamshim/OAMTypes.h>
#import <oamshim/OAM.h>
#undef nil

#import "afp.h"

OAMStatus openOAMSession(OAMSessionID * session_p);
OAMStatus closeOAMSession(OAMSessionID sessionID);

OAMStatus createOAMUser(OAMSessionID session, u_char * name, u_char * inet_p,
			u_char * passwd_p);
OAMStatus deleteOAMUser(OAMSessionID session, u_char * name);
OAMStatus isOAMUser(OAMSessionID session, u_char * name);
OAMStatus setOAMUserPassword(OAMSessionID session, u_char * name, 
			     u_char * passwd);

OAMStatus createOAMGroup(OAMSessionID session, unsigned char * name);
OAMStatus addOAMGroupMember(OAMSessionID session, StringPtr group, 
			    StringPtr user);
OAMStatus removeOAMGroupMember(OAMSessionID session, StringPtr group, 
			       StringPtr user);

