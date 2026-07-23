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
 * audioReplyHandler.h
 *
 * Copyright (c) 1991, NeXT Computer, Inc.  All rights reserved.
 *
 */

#ifndef _NXAUDIO_REPLY_HANDLER_
#define _NXAUDIO_REPLY_HANDLER_

#import <mach/kern_return.h>
#import <mach/port.h>
#import <mach/message.h>
#import <bsd/sys/types.h>
#import <bsd/dev/audioTypes.h>

/*
 * Functions to call for handling messages returned.
 */
typedef struct __NXAudioReply {
    kern_return_t (*streamStatus)(
			void *arg,
			port_t streamPort,
			port_t replyPort,
			int id,
			int tag,
			int status);
    kern_return_t (*recordedData)(
			void *arg,
			port_t streamPort,
			port_t replyPort,
			int id,
			int tag,
			void *data,
			u_int count);
    void		*arg;		/* argument to pass to function */
    int			timeout;	/* timeout for RPC return msg_send */
} _NXAudioReply;

/*
 * Sizes of messages structures for send and receive.
 */
union _NXAudioReplyRequest {
	struct {
		msg_header_t Head;
		msg_type_t streamPortType;
		port_t streamPort;
		msg_type_t streamReplyType;
		port_t streamReply;
		msg_type_t streamIdType;
		int streamId;
		msg_type_t tagType;
		int tag;
		msg_type_t statusType;
		int status;
	} _NXAudioStreamStatus;
	struct {
		msg_header_t Head;
		msg_type_t streamPortType;
		port_t streamPort;
		msg_type_t streamReplyType;
		port_t streamReply;
		msg_type_t streamIdType;
		int streamId;
		msg_type_t tagType;
		int tag;
		msg_type_long_t dataType;
		dealloc_ptr data;
	} _NXAudioRecordedData;
};
#define _NXAUDIO_REPLY_INMSG_SIZE sizeof(union _NXAudioReplyRequest)

union _NXAudioReplyReply {
	struct {
		msg_header_t Head;
		msg_type_t RetCodeType;
		kern_return_t RetCode;
	} _NXAudioStreamStatus;
	struct {
		msg_header_t Head;
		msg_type_t RetCodeType;
		kern_return_t RetCode;
	} _NXAudioRecordedData;
};
#define _NXAUDIO_REPLY_OUTMSG_SIZE sizeof(union _NXAudioReplyReply)

/*
 * Handler routine to call when receiving messages from audio driver.
 */
extern kern_return_t _NXAudioReplyHandler(msg_header_t *msg,
					  _NXAudioReply *_NXAudioReply);

#endif	_NXAUDIO_REPLY_HANDLER_
