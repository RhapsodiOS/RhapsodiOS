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
 * _sounddriver.h
 */

#import <mach/mach.h>
#import <bsd/sys/types.h>

/*
 * Stream setup codes marked as RESERVED in sounddriver.h.
 */
#define SNDDRIVER_STREAM_TO_SNDOUT_GENERIC		(16)
#define SNDDRIVER_STREAM_FROM_SNDIN_GENERIC		(17)

#define	SOUNDDRIVER_STREAM_FORMAT_RATE_CONTINUOUS	(1<<0)
#define	SOUNDDRIVER_STREAM_FORMAT_RATE_8000		(1<<1)
#define	SOUNDDRIVER_STREAM_FORMAT_RATE_11025		(1<<2)
#define	SOUNDDRIVER_STREAM_FORMAT_RATE_16000		(1<<3)
#define	SOUNDDRIVER_STREAM_FORMAT_RATE_22050		(1<<4)
#define	SOUNDDRIVER_STREAM_FORMAT_RATE_32000		(1<<5)
#define	SOUNDDRIVER_STREAM_FORMAT_RATE_44100		(1<<6)
#define	SOUNDDRIVER_STREAM_FORMAT_RATE_48000		(1<<7)

#define	SOUNDDRIVER_STREAM_FORMAT_ENCODING_MULAW_8	(1<<0)
#define	SOUNDDRIVER_STREAM_FORMAT_ENCODING_LINEAR_8	(1<<1)
#define	SOUNDDRIVER_STREAM_FORMAT_ENCODING_LINEAR_16	(1<<2)

kern_return_t snddriver_get_sndout_formats (
	port_t		device_port,		// valid device port
	u_int		*sample_rates,		// returned rates
	u_int		*low_rate,		// returned low rate
	u_int		*high_rate,		// returned high rate
	u_int		*data_encodings,	// returned encodings
	u_int		*chan_limit);		// returned chan limit

kern_return_t snddriver_get_sndin_formats (
	port_t		device_port,		// valid device port
	u_int		*sample_rates,		// returned rates
	u_int		*low_rate,		// returned low rate
	u_int		*high_rate,		// returned high rate
	u_int		*data_encodings,	// returned encodings
	u_int		*chan_limit);		// returned chan limit

kern_return_t snddriver_set_sndout_format (
	port_t		device_port,		// valid device port
	port_t		owner_port,		// valid owner port
	u_int		sample_rate,		// sampling rate
	u_int		data_encoding,		// encoding
	u_int		chan_count);		// channel count

kern_return_t snddriver_set_sndin_format (
	port_t		device_port,		// valid device port
	port_t		owner_port,		// valid owner port
	u_int		sample_rate,		// sampling rate
	u_int		data_encoding,		// encoding
	u_int		chan_count);		// channel count
