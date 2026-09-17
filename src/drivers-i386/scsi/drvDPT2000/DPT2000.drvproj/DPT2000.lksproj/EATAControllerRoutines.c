/*
 * Copyright (c) 1999 Apple Computer, Inc.
 *
 * EATAControllerRoutines.c - standalone C symbols from DPTSCSIDriver_reloc.
 *
 * HISTORY
 *
 * Reconstructed from DPTSCSIDriver_reloc. _parseConfigSpace lives in
 * EATAController.m because it sends IODirectDevice messages.
 */

#include <string.h>
#include <driverkit/generalFuncs.h>
#include <driverkit/kernelDriver.h>
#include <driverkit/interruptMsg.h>
#include <kernserv/prototypes.h>
#include <mach/message.h>
#include "EATAControllerTypes.h"

static msg_header_t timeoutMsgTemplate = {
	0,
	1,
	sizeof(msg_header_t),
	MSG_TYPE_NORMAL,
	PORT_NULL,
	PORT_NULL,
	IO_TIMEOUT_MSG
};

int
eata_busy(unsigned short ioBase, int count)
{
	unsigned short	port;
	unsigned char	aux;

	port = ioBase + EATA_AUX_STATUS_OFF;
	do {
		aux = inb(port);
		if ((aux & EATA_AUX_BUSY) == 0)
			break;
		count--;
	} while (count);
	return (aux & EATA_AUX_BUSY);
}

int
eata_busy_0(unsigned short ioBase, int count)
{
	unsigned short	port;
	unsigned char	aux;

	port = ioBase + EATA_AUX_STATUS_OFF;
	do {
		aux = inb(port);
		if ((aux & EATA_AUX_BUSY) == 0)
			break;
		count--;
	} while (count);
	return (aux & EATA_AUX_BUSY);
}

void
eataTimeout(void *arg)
{
	struct ccb	*ccb = arg;
	msg_header_t	msg = timeoutMsgTemplate;

	msg.msg_remote_port = ccb->timeoutPort;
	IOLog("EATA timeout\n");
	msg_send_from_kernel(&msg, MSG_OPTION_NONE, 0);
}
