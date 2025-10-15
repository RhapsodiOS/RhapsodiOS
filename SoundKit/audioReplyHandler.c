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
#ifdef SHLIB
#define SHLIB_MIG	/* needed because we import audioReplyHandler.h */
#include "shlib.h"
#endif SHLIB

/*
 * audioReplyHandler.c
 *
 * Copyright (c) 1991, NeXT Computer, Inc.  All rights reserved.
 *
 *
 * HISTORY
 *	07/09/91/mtm	Original coding.
 */

#import <bsd/dev/audioTypes.h>
#import "audioReplyHandler.h"
#import <audioReplyServer.c>
#import <bsd/sys/types.h>

/*
 * The port argument in each of the following is actually a pointer
 * to a structure containing pointers to functions to call for each of
 * the following messages.
 */

kern_return_t _NXAudioReplyStreamStatus(port_t port, port_t streamPort,
					port_t replyPort, int id,
					int tag, int status)
{
    _NXAudioReply *audioReply = (_NXAudioReply *)port;

    if (audioReply->streamStatus == 0)
	return MIG_BAD_ID;
    return (*audioReply->streamStatus)(audioReply->arg, streamPort,
				       replyPort, id, tag, status);
}

kern_return_t _NXAudioReplyRecordedData(port_t port, port_t streamPort,
					port_t replyPort, int id,
					int tag, pointer_t data,
					u_int count)
{
    _NXAudioReply *audioReply = (_NXAudioReply *)port;

    if (audioReply->recordedData == 0)
	return MIG_BAD_ID;
    return (*audioReply->recordedData)(audioReply->arg, streamPort,
				       replyPort, id,
				       tag, (void *)data, count);
}

kern_return_t _NXAudioReplyHandler(msg_header_t *msg,
				   _NXAudioReply *audioReply)
{
    char out_msg_buf[_NXAUDIO_REPLY_OUTMSG_SIZE];
    typedef struct {
	msg_header_t Head;
	msg_type_t RetCodeType;
	kern_return_t RetCode;
    } Reply;
    Reply *out_msg = (Reply *)out_msg_buf;
    kern_return_t ret_code;

    msg->msg_local_port = (port_t)audioReply;

    /* FIXME: mig generates this routine with subsystem name!
    _NXAudioReplyServer(msg, (msg_header_t *)out_msg); */

    audioReply_server(msg, (msg_header_t *)out_msg);
    ret_code = out_msg->RetCode;

    if (out_msg->RetCode == MIG_NO_REPLY)
	ret_code = KERN_SUCCESS;

    return ret_code;
}
