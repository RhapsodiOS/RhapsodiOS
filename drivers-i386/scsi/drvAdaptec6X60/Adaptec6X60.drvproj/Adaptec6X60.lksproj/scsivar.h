/*
 * Copyright (c) 1992-1998 NeXT Software, Inc.
 *
 * Generic SCSI data structures.
 *
 * HISTORY
 *
 * 28 Mar 1998 Adapted from AHA-1542 driver
 *	Created.
 *  6 July 1992 David E. Bohman at NeXT
 *	Created from m68k version.
 */

/*
 * SCSI bus constants used only by driver (not exported)
 */

/*
 * message codes
 */
#define	MSG_CMDCMPLT		0x00	/* to host: command complete */
#define	MSG_SAVEPTRS		0x02	/* to host: save data pointers */
#define	MSG_RESTOREPTRS		0x03	/* to host: restore pointers */
#define	MSG_DISCONNECT		0x04	/* to host: disconnect */
#define	MSG_IDETERR		0x05	/* to disk: initiator detected error */
#define	MSG_ABORT		0x06	/* to disk: abort op, go to bus free */
#define	MSG_MSGREJECT		0x07	/* both ways: last msg unimplemented */
#define	MSG_NOP			0x08	/* to disk: no-op message */
#define	MSG_MSGPARERR		0x09	/* to disk: parity error last message */
#define	MSG_LNKCMDCMPLT		0x0a	/* to host: linked command complete */
#define	MSG_LNKCMDCMPLTFLAG	0x0b	/* to host: flagged linked cmd cmplt */
#define	MSG_DEVICERESET		0x0c	/* to disk: reset and go to bus free */

#define	MSG_IDENTIFYMASK	0x80	/* both ways: thread identification */
#define	MSG_ID_DISCONN		0x40	/*	can disconnect/reconnect */
#define	MSG_ID_LUNMASK		0x07	/*	target LUN */

/*
 * opcode groups
 */
#define	SCSI_OPGROUP(opcode)	((opcode) & 0xe0)

#define	OPGROUP_0		0x00	/* six byte commands */
#define	OPGROUP_1		0x20	/* ten byte commands */
#define	OPGROUP_2		0x40	/* ten byte commands */
#define	OPGROUP_5		0xa0	/* twelve byte commands */
#define	OPGROUP_6		0xc0	/* six byte, vendor unique commands */
#define	OPGROUP_7		0xe0	/* ten byte, vendor unique commands */

/*
 * scsi bus phases
 */
#define	PHASE_DATAOUT		0x0
#define	PHASE_DATAIN		0x1
#define	PHASE_COMMAND		0x2
#define	PHASE_STATUS		0x3
#define	PHASE_MSGOUT		0x6
#define	PHASE_MSGIN		0x7


