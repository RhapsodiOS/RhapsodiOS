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
#include "shlib.h"
#endif SHLIB

/*
 * audioLookup.c
 *
 * Copyright (c) 1991, NeXT Computer, Inc.  All rights reserved.
 *
 *      Port lookup function for audio driver kernel server.
 *
 * HISTORY
 *	07/09/91/mtm	Original coding.
 */

#import <bsd/dev/audioTypes.h>
#import <servers/netname.h>
#import <servers/bootstrap.h>
#import <mach/mach.h>
#import <stdlib.h>
#import <string.h>

/*
 * Get the audio device ports.  Try the bootstrap server first if
 * hostname is "" (local machine).  This gives you a secure port that
 * can't be yanked away from a different machine.
 */
static kern_return_t get_device_ports(char *hostname, port_t *sndin_port,
				      port_t *sndout_port)
{
    port_t in_port, out_port, bs_port;
    kern_return_t err;

    if (strlen(hostname) == 0) {
	/*
	 * Try our bootstrap port first.
	 */
	err = task_get_bootstrap_port(task_self(), &bs_port);
	if (!err) {
	    err = bootstrap_look_up(bs_port, _NXAUDIO_SOUNDIN_SERVER_NAME,
				    &in_port);
	    if (!err)
		err = bootstrap_look_up(bs_port, _NXAUDIO_SOUNDOUT_SERVER_NAME,
					&out_port);
	}
	/*
	 * Device ports not found, try the net name server.
	 */
	if (err) {
	    err = netname_look_up(name_server_port, hostname,
				  _NXAUDIO_SOUNDIN_SERVER_NAME, &in_port);
	    if (!err)
		err = netname_look_up(name_server_port, hostname,
				      _NXAUDIO_SOUNDOUT_SERVER_NAME,
				      &out_port);
	}
    } else {
	/*
	 * Look up the device ports on a remote machine.
	 */
	err = netname_look_up(name_server_port, hostname,
			      _NXAUDIO_SOUNDIN_SERVER_NAME, &in_port);
	if (!err)
	    err = netname_look_up(name_server_port, hostname,
				  _NXAUDIO_SOUNDOUT_SERVER_NAME, &out_port);
    }
    if (err)
	*sndin_port = *sndout_port = PORT_NULL;
    else {
	*sndin_port = in_port;
	*sndout_port = out_port;
    }
    return err;
}

/*
 * Look up the the soundin server port.
 */
kern_return_t _NXAudioSoundinLookup(const char *host, port_t *serverPort)
{
    char *hostname;
    port_t outPort;

    if (!(hostname = (char *)host))
	hostname = "";
    return get_device_ports(hostname, serverPort, &outPort);
}

/*
 * Look up the the soundout server port.
 */
kern_return_t _NXAudioSoundoutLookup(const char *host, port_t *serverPort)
{
    char *hostname;
    port_t inPort;

    if (!(hostname = (char *)host))
	hostname = "";
    return get_device_ports(hostname, &inPort, serverPort);
}










