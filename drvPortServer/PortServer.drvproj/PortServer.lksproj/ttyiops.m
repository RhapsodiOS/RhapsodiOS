/*
 * Copyright (c) 1999 Apple Computer, Inc. All rights reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 *
 * Portions Copyright (c) 1999 Apple Computer, Inc.  All Rights
 * Reserved.  This file contains Original Code and/or Modifications of
 * Original Code as defined in and that are subject to the Apple Public
 * Source License Version 1.1 (the "License").  You may not use this file
 * except in compliance with the License.  Please obtain a copy of the
 * License at http://www.apple.com/publicsource and read it before using
 * this file.
 *
 * The Original Code and all software distributed under the License are
 * distributed on an "AS IS" basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE OR NON- INFRINGEMENT.  Please see the
 * License for the specific language governing rights and limitations
 * under the License.
 *
 * @APPLE_LICENSE_HEADER_END@
 */

#import <objc/objc.h>
#import <objc/objc-runtime.h>
#import <sys/types.h>
#import <sys/tty.h>
#import <sys/conf.h>
#import <sys/dkstat.h>
#import <kern/assert.h>
#import <driverkit/generalFuncs.h>

#import "ttyiops.h"

/* Speed table for baud rate conversion */
int ttyiops_speeds[] = {
    0,      // B0
    50,     // B50
    75,     // B75
    110,    // B110
    134,    // B134
    150,    // B150
    200,    // B200
    300,    // B300
    600,    // B600
    1200,   // B1200
    1800,   // B1800
    2400,   // B2400
    4800,   // B4800
    9600,   // B9600
    19200,  // B19200
    38400,  // B38400
    7200,   // B7200
    14400,  // B14400
    28800,  // B28800
    57600,  // B57600
    76800,  // B76800
    115200, // B115200
    230400, // B230400
    -1      // End marker
};

/* Extended tty structure used by PortServer */
typedef struct {
    struct tty base_tty;        // Base tty structure at offset 0
    // Additional fields follow...
    // Based on decompiled offsets:
    // offset 0x00: base_tty.t_rawq (first field)
    // offset 0x1c: base_tty.t_outq (7 * 4 bytes in)
    // offset 0x60: base_tty.t_line (24 * 4 bytes in)
    // offset 0x64: base_tty.t_dev (25 * 4 bytes in)
    // offset 0x6a: flags at byte offset 106
    // offset 0x9b: flags at byte offset 155
    // offset 0xe8: IOPortSession object pointer (58 * 4 bytes in)
    char padding[0xe8 - sizeof(struct tty)];
    id portSession;             // IOPortSession object at offset 0xe8 (0x3a * 4)
} extended_tty_t;

#define EXT_TTY(tp) ((extended_tty_t *)(tp))

/* State flags */
#define TTY_STATE_RXFULL    0x20    // RX buffer full flag at offset 0x57 (byte)
#define TTY_STATE_RXFLOWOFF 0x08    // RX flow control off flag

/* Termios flags */
#define TTY_IFLAG_RAW       0x01    // Raw mode flag at offset 0x6a (byte)
#define TTY_LFLAG_CANON     0x20    // Canonical mode flag at offset 0x9b (byte)

/* Error codes */
#define KERN_IOPS_NODATA    0x2ca   // No data available error code

void ttyiops_getData(struct tty *tp)
{
    extended_tty_t *ext_tp;
    id portSession;
    unsigned int availableSpace;
    unsigned int transferCount;
    unsigned char buffer[1024];
    int result;
    unsigned int i;
    SEL dequeueDataSel;

    if (tp == NULL) {
        return;
    }

    ext_tp = EXT_TTY(tp);

    /* Check if RX buffer is full (bit 0x20 at byte offset 0x57) */
    if (((unsigned char *)tp)[0x57] & TTY_STATE_RXFULL) {
        return;
    }

    /* Calculate available space in buffer */
    /* Buffer size is 0x3fc, subtract current count and reserved */
    availableSpace = 0x3fc - (tp->t_rawq.c_cc + ((int *)tp)[8]);

    if (availableSpace > 0x400) {
        availableSpace = 0x400;
    }

    if (availableSpace == 0) {
        /* Set RX flow control off flag */
        ((unsigned char *)tp)[0x57] |= TTY_STATE_RXFLOWOFF;
        return;
    }

    /* Clear RX flow control off flag if it was set */
    if (((unsigned char *)tp)[0x57] & TTY_STATE_RXFLOWOFF) {
        ((unsigned char *)tp)[0x57] &= ~TTY_STATE_RXFLOWOFF;
    }

    /* Get the port session object */
    portSession = ext_tp->portSession;
    if (portSession == nil) {
        return;
    }

    /* Dequeue data from the port session */
    dequeueDataSel = @selector(dequeueData:bufferSize:transferCount:minCount:);
    transferCount = 0;

    result = (int)objc_msgSend(portSession, dequeueDataSel,
                                buffer, availableSpace, &transferCount, 1);

    /* Check result - allow success (0) or no data available (0x2ca) */
    if (result == 0 || result == -KERN_IOPS_NODATA) {
        if (transferCount != 0) {
            /* Check if we should use line discipline or direct queuing */
            if ((((unsigned char *)tp)[0x6a] & TTY_IFLAG_RAW) == 0 ||
                (((unsigned char *)tp)[0x9b] & TTY_LFLAG_CANON) != 0) {
                /* Process through line discipline - one character at a time */
                for (i = 0; i < transferCount; i++) {
                    /* Call line discipline l_rint function */
                    /* linesw is an array, indexed by t_line, each entry is 0x20 bytes */
                    /* l_rint is the first function pointer in the structure */
                    if (linesw[tp->t_line].l_rint) {
                        linesw[tp->t_line].l_rint(buffer[i], tp);
                    }
                }
            } else {
                /* Direct queuing - update statistics */
                tk_nin += transferCount;
                tk_rawcc += transferCount;
                ((int *)tp)[7] += transferCount;

                /* Queue data directly */
                b_to_q(buffer, transferCount, &tp->t_rawq);

                /* Wake up readers */
                ttwakeup(tp);
            }
        }
    } else {
        /* Log error */
        IOLog("PStty%04x: dequeueData ret %d\n", tp->t_dev, result);
    }
}

/*
 * rs232totio - Convert RS232 flags to termios flags
 * Masks the RS232 flags to extract only the relevant bits
 */
unsigned int rs232totio(unsigned int rs232_flags)
{
    return rs232_flags & 0x8e6;
}

/*
 * tiotors232 - Convert termios flags to RS232 flags
 * Masks the termios flags to extract only the relevant bits
 */
unsigned int tiotors232(unsigned int tio_flags)
{
    return tio_flags & 0x866;
}

/*
 * ttyiops_attachDevice - Initialize tty device settings and attach to map
 * portServerObj: PortServer object instance
 * unit: Unit index (0-25 for ttyd a-z)
 *
 * Sets up the default termios structure and stores the PortServer object in _ttyiopsMap
 */
void ttyiops_attachDevice(id portServerObj, unsigned int unit)
{
    struct tty *tp;
    int i;
    unsigned int *src, *dst;

    if (portServerObj == NULL || unit > 25) {
        return;
    }

    /* Store PortServer object in map */
    _ttyiopsMap[unit] = portServerObj;

    /* Get tty structure at offset +0x108 */
    tp = (struct tty *)((char *)portServerObj + 0x108);

    /* Initialize termios structure at offset 0x120 */
    /* These offsets correspond to the t_termios structure fields */
    ((unsigned int *)tp)[0x120/4] = 0;          // c_iflag
    ((unsigned int *)tp)[0x124/4] = 0;          // c_oflag
    ((unsigned int *)tp)[0x128/4] = 0x4b00;     // c_cflag (19200 baud, CS8, etc)
    ((unsigned int *)tp)[300/4] = 0;            // c_lflag
    ((unsigned int *)tp)[0x148/4] = 0x2580;     // c_ospeed (9600 baud)
    ((unsigned int *)tp)[0x144/4] = 0x2580;     // c_ispeed (9600 baud)

    /* Set default termios control characters */
    termioschars(&tp->t_termios);

    /* Copy termios structure from offset 0x120 to offset 0xf4 */
    /* This copies 11 dwords (44 bytes) */
    src = &((unsigned int *)tp)[0x120/4];
    dst = &((unsigned int *)tp)[0xf4/4];

    for (i = 0; i < 11; i++) {
        *dst++ = *src++;
    }

    /* Clear 8 bytes at offset 0x14c (struct winsize) */
    bzero(&((unsigned char *)tp)[0x14c], 8);
}

/*
 * ttyiops_acquireSession - Acquire a session for the tty device
 * Handles session locking and device acquisition with proper synchronization
 * Returns 0 on success, error code on failure
 */
int ttyiops_acquireSession(struct tty *tp, unsigned int session_flags)
{
    int result;
    int error_code = 0;
    int acquire_result;
    id newSession;
    id deviceName;
    id ioPortSessionClass;
    unsigned int current_session;

    if (tp == NULL) {
        return 0x16; // EINVAL
    }

    /* Session acquisition loop with sleep/retry logic */
    while (1) {
        /* Check if we can proceed without waiting */
        if (((session_flags & 0x20) != 0) ||                    // Non-blocking flag set
            (((short *)tp)[0x94/2] < 0) ||                      // Some condition at offset 0x94
            ((((unsigned char *)tp)[0x15c] & 0x10) == 0)) {     // Flag check at 0x15c
            
            /* Check if session is not in use */
            if (((int *)tp)[100/4] == 0) {
                goto acquire_session;
            }

            /* Check if same session */
            if (((unsigned int *)tp)[100/4] == session_flags) {
                /* Check additional conditions */
                if ((((unsigned char *)tp)[0x68] & 0x20) != 0 && 
                    (((unsigned char *)tp)[0x15c] & 4) == 0) {
                    goto acquire_session;
                }
            } else {
                /* Different session - check if can override */
                if ((((unsigned char *)tp)[100] & 0x20) != 0) {
                    if (((session_flags & 0x20) == 0) && 
                        (((short *)tp)[0x94/2] >= 0)) {
                        goto sleep_and_retry;
                    }
                    if ((((unsigned char *)tp)[100] & 0x20) != 0) {
                        return 0x10; // EBUSY
                    }
                }

                if ((((short *)tp)[0x94/2] < 0) || 
                    ((session_flags & 0x20) == 0) ||
                    (((unsigned char *)tp)[0x68] & 0x20) != 0) {
                    return 0x10; // EBUSY
                }

                /* Check if waiting flag is set */
                if ((((unsigned char *)tp)[0x15c] & 2) == 0) {
                    break;
                }
            }
        }

sleep_and_retry:
        /* Sleep and retry */
        tsleep(tp, 0x19, "ttyas", 0);
    }

    /* Set waiting flag */
    ((unsigned char *)tp)[0x15c] |= 2;

acquire_session:
    /* If no current session, create new one */
    if (((int *)tp)[100/4] == 0) {
        ((unsigned int *)tp)[100/4] = session_flags;

        /* Check if need to create audited session */
        if (((session_flags & 0x20) == 0) && (((short *)tp)[0x94/2] >= 0)) {
            /* Set busy flag */
            ((unsigned char *)tp)[0x15c] |= 0x10;

            /* Get device name */
            deviceName = objc_msgSend(((id *)tp)[0xe8/4], @selector(name), &acquire_result);

            /* Get IOPortSession class */
            ioPortSessionClass = objc_getClass("IOPortSession");

            /* Allocate and initialize new session */
            newSession = objc_msgSend(ioPortSessionClass, @selector(alloc));
            newSession = objc_msgSend(newSession, @selector(initForDevice:result:), 
                                     deviceName, &acquire_result);

            /* Acquire with audit */
            acquire_result = (int)objc_msgSend(newSession, @selector(acquireAudit:), 1);

            /* Clear busy flag */
            ((unsigned char *)tp)[0x15c] &= ~0x10;

            if (acquire_result == 0) {
                /* Success - free old session and assign new one */
                ((unsigned int *)tp)[100/4] = session_flags;
                objc_msgSend(((id *)tp)[0xe8/4], @selector(free));
                ((id *)tp)[0xe8/4] = newSession;
            } else {
                /* Failed - free new session and return error */
                objc_msgSend(newSession, @selector(free));
                error_code = 6; // EIO

                if (acquire_result == -0x2bf) {
                    error_code = 4; // EINTR
                    goto cleanup_and_return;
                }
            }
        } else {
            /* Non-audited acquire */
            result = (int)objc_msgSend(((id *)tp)[0xe8/4], @selector(acquire:), 0);
            error_code = 0;

            if (result != 0) {
                error_code = 0x10; // EBUSY
                goto cleanup_and_return;
            }
        }
    } else if ((((unsigned char *)tp)[0x15c] & 2) != 0) {
        /* Switching sessions */
        ((unsigned int *)tp)[100/4] = session_flags;

        /* Get device name */
        deviceName = objc_msgSend(((id *)tp)[0xe8/4], @selector(name), &acquire_result);

        /* Get IOPortSession class */
        ioPortSessionClass = objc_getClass("IOPortSession");

        /* Allocate and initialize new session */
        newSession = objc_msgSend(ioPortSessionClass, @selector(alloc));
        newSession = objc_msgSend(newSession, @selector(initForDevice:result:), 
                                 deviceName, &acquire_result);

        /* Acquire without audit */
        acquire_result = (int)objc_msgSend(newSession, @selector(acquire:), 0);

        /* Clear waiting flag */
        ((unsigned char *)tp)[0x15c] &= ~2;

        if (acquire_result == 0) {
            /* Success - assign new session */
            ((id *)tp)[0xe8/4] = newSession;
        } else {
            /* Failed - free new session */
            objc_msgSend(newSession, @selector(free));
            error_code = 0x10; // EBUSY
        }
    }

    /* Return success if no error */
    if (error_code == 0) {
        return 0;
    }

cleanup_and_return:
    /* Clear session and wake up waiters */
    ((int *)tp)[100/4] = 0;
    wakeup(tp);
    return error_code;
}

/*
 * ttyiops_close - Close the TTY device
 * Handles cleanup of the device session and releases resources
 * Returns 0 on success
 */
int ttyiops_close(unsigned int dev, int flag)
{
    struct tty *tp = NULL;
    unsigned int state;
    unsigned int minor;

    /* Validate device and find corresponding tty structure */
    /* Check if major number matches portServerMajor */
    if ((portServerMajor == ((dev >> 8) & 0xff)) && 
        ((dev & 0xc0) != 0xc0)) {
        minor = dev & 0x1f;
        if (_ttyiopsMap[minor] != NULL) {
            /* TTY structure is at offset 0x108 from map entry */
            tp = (struct tty *)((char *)_ttyiopsMap[minor] + 0x108);
        }
    }

    if (tp == NULL) {
        return 0;
    }

    /* Check if this is a callout device (bits 0xc0) */
    if ((dev & 0xc0) == 0) {
        /* Set closing flag at offset 0x15c */
        ((unsigned char *)tp)[0x15c] |= 4;

        /* Clear bit 0x100 in flags at offset 0x68 */
        ((unsigned int *)tp)[0x68/4] &= ~0x100;

        /* Execute close event (0x53) */
        objc_msgSend(((id *)tp)[0xe8/4], @selector(executeEvent:data:), 0x53, 0);

        /* Set state: clear 0x20400000, set 0xffffffff */
        objc_msgSend(((id *)tp)[0xe8/4], @selector(setState:mask:), 
                     0xffffffff, 0x20400000);

        /* Enqueue drain event (0xf9) with sleep */
        objc_msgSend(((id *)tp)[0xe8/4], @selector(enqueueEvent:data:sleep:), 
                     0xf9, 0, 1);

        /* Call line discipline close function */
        /* linesw is indexed by t_line at offset 0x60, each entry is 0x20 bytes */
        if (linesw[((int *)tp)[0x60/4]].l_close) {
            linesw[((int *)tp)[0x60/4]].l_close(tp, flag);
        }

        /* Check if should drop modem control lines */
        /* Check flags at offsets 0x95, 0x68, and device flags */
        if ((((unsigned char *)tp)[0x95] & 0x40) != 0 ||      // HUPCL flag
            (((unsigned char *)tp)[0x68] & 0x20) == 0 ||       // Not exclusive
            ((dev & 0x20) == 0 &&                              // Not dialout
             (((short *)tp)[0x128/2] >= 0 &&                   // c_cflag check
              (state = (unsigned int)objc_msgSend(((id *)tp)[0xe8/4], 
                                                   @selector(getState)), 
               (state & 0x40) == 0)))) {                       // Carrier not detected
            /* Drop modem control lines */
            ttyiops_mctl(tp, 0, 0);
        }

        /* Close the tty */
        ttyclose(tp);

        /* Wait for pending TX/RX data to drain */
        if (((int *)tp)[0xf0/4] != 0 || ((int *)tp)[0xec/4] != 0) {
            /* Set drain flag */
            ((unsigned char *)tp)[0x15c] |= 0x20;

            /* Execute drain event (5) */
            objc_msgSend(((id *)tp)[0xe8/4], @selector(executeEvent:data:), 5, 0);

            /* Wait for TX data to drain (offset 0xf0) */
            if (((int *)tp)[0xf0/4] != 0) {
                do {
                    tsleep(&((int *)tp)[0xf0/4], 0x119, "ttytxd", 0);
                } while (((int *)tp)[0xf0/4] != 0);
            }

            /* Wait for RX data to drain (offset 0xec) */
            if (((int *)tp)[0xec/4] != 0) {
                do {
                    tsleep(&((int *)tp)[0xec/4], 0x119, "ttyrxd", 0);
                } while (((int *)tp)[0xec/4] != 0);
            }
        }

        /* Release the port session */
        objc_msgSend(((id *)tp)[0xe8/4], @selector(release));

        /* Clear session owner at offset 100 */
        ((int *)tp)[100/4] = 0;

        /* Clear closing flag (bit 4 at offset 0x15c) */
        ((unsigned char *)tp)[0x15c] &= ~4;

        /* Wake up any waiting processes */
        wakeup(tp);
    }

    return 0;
}

/*
 * ttyiops_mctl - Modem control function
 * Controls modem signal lines (DTR, RTS, etc.)
 * Returns current modem status or error code
 */
int ttyiops_mctl(struct tty *tp, int bits, int how)
{
    unsigned int current_state;
    unsigned int new_state;
    int result;

    if (tp == NULL) {
        return 0;
    }

    /* Mask bits to only DTR and RTS (bits 1 and 2 = 6) */
    bits &= 6;

    /* Get current hardware state */
    current_state = (unsigned int)objc_msgSend(((id *)tp)[0xe8/4], @selector(getState));

    /* Determine new state based on operation */
    switch (how) {
        case 0:  /* DMSET - Set to exact value (preserve other bits) */
            /* Set DTR/RTS to specified value, preserve bits 0x60 */
            new_state = bits | (current_state & 0x60);
            break;

        case 1:  /* DMBIS - Bit set (OR) */
            /* Set specified bits */
            new_state = current_state | bits;
            break;

        case 2:  /* DMBIC - Bit clear */
            /* Clear specified bits */
            new_state = current_state & ~bits;
            break;

        case 3:  /* DMGET - Get current state */
            /* Just return current state without changes */
            return current_state;

        default:
            /* Unknown operation */
            new_state = current_state;
            break;
    }

    /* Check if DTR is being dropped (bit 2 cleared when it was set) */
    if ((~new_state & current_state & 2) != 0) {
        /* Store timestamp when DTR was dropped */
        /* This is used for DTR drop timing requirements */
        ((long *)tp)[0x14c/sizeof(long)] = time.tv_sec;
        ((long *)tp)[0x150/sizeof(long)] = time.tv_usec;
    }

    /* Apply new state to hardware */
    /* Mask 6 means only DTR and RTS bits can be changed */
    result = (int)objc_msgSend(((id *)tp)[0xe8/4], @selector(setState:mask:),
                                new_state, 6);

    if (result != 0) {
        IOLog("PStty%04x: mctl PD_E_FLOW_CONTROL failed %d\n",
              ((int *)tp)[100/4], result);
    }

    return new_state;
}

/*
 * ttyiops_control_ioctl - Handle control device ioctl commands
 * Processes ioctls for the control device (non-data device)
 * Returns 0 on success, error code on failure
 */
int ttyiops_control_ioctl(struct tty *tp, unsigned int dev, unsigned int cmd,
                          void *data, int flag, struct proc *p)
{
    int result;
    unsigned int *src, *dst;
    struct termios *termios_src, *termios_dst;
    unsigned char *data_bytes;
    int i;

    if (tp == NULL || data == NULL) {
        return 0x16; // EINVAL
    }

    /* Check if this is a control device (bits 0xc0 should be 0x40) */
    if ((dev & 0xc0) != 0x40) {
        return 0x13; // EACCES
    }

    /* Determine which termios structure to use based on device type */
    /* If bit 0x20 is clear, use offset 0x120, otherwise use 0xf4 */
    if ((dev & 0x20) == 0) {
        termios_src = (struct termios *)&((unsigned char *)tp)[0x120];
    } else {
        termios_src = (struct termios *)&((unsigned char *)tp)[0xf4];
    }

    /* Handle specific ioctl commands */
    switch (cmd) {
        case 0x40087468:  /* TIOCGWINSZ - Get window size */
            /* Clear 8 bytes (struct winsize) */
            bzero(data, 8);
            return 0;

        case 0x4004741a:  /* TIOCOUTQ - Get output queue count */
            /* Return 0 for output queue count */
            *((int *)data) = 0;
            return 0;

        case 0x402c7413:  /* TIOCGETA - Get termios attributes */
            /* Copy termios structure from device to user data */
            termios_dst = (struct termios *)data;
            src = (unsigned int *)termios_src;
            dst = (unsigned int *)termios_dst;

            /* Copy 11 dwords (44 bytes) */
            for (i = 0; i < 11; i++) {
                *dst++ = *src++;
            }
            return 0;

        case 0x802c7414:  /* TIOCSETA - Set termios attributes */
            /* Check if user has permission */
            result = suser(p->p_ucred, &p->p_acflag);
            if (result != 0) {
                return result;
            }

            termios_dst = termios_src;
            termios_src = (struct termios *)data;
            data_bytes = (unsigned char *)data;

            /* Validate termios settings */
            /* Check if PARENB or PARODD is set (bits 6 or 2 at byte offset 1) */
            if ((data_bytes[1] & 0x6) != 0) {
                /* Check for invalid speed values at offsets 7 and 0x1d */
                if (((char *)data)[7] == -1 || ((char *)data)[0x1d] == -1) {
                    return 0x16; // EINVAL
                }
            }

            /* Copy termios structure from user data to device */
            src = (unsigned int *)termios_src;
            dst = (unsigned int *)termios_dst;

            /* Copy 11 dwords (44 bytes) */
            for (i = 0; i < 11; i++) {
                *dst++ = *src++;
            }
            return 0;

        default:
            /* Unknown ioctl command */
            return 0x19; // ENOTTY
    }
}

/*
 * ttyiops_convertFlowCtrl - Convert flow control settings from device to flags
 * Queries the port session for flow control status and updates the flags accordingly
 */
void ttyiops_convertFlowCtrl(id portSession, unsigned int *flags)
{
    unsigned char response[2];  /* local_8 and local_7 */

    if (portSession == nil || flags == NULL) {
        return;
    }

    /* Request flow control event (0x53) from port session */
    /* Response contains flow control status in two bytes */
    objc_msgSend(portSession, @selector(requestEvent:data:), 0x53, response);

    /* Check bit 0x8 (bit 3) in first byte - RX XON/XOFF flow control */
    if ((response[0] & 0x8) != 0) {
        flags[0] |= 0x200;  /* Set IXON flag */
    }

    /* Check bit 0x4 (bit 2) in second byte - output flow control */
    if ((response[1] & 0x4) != 0) {
        flags[0] |= 0x800;  /* Set additional output flow control flag */
    }

    /* Check bit 0x10 (bit 4) in first byte - TX XON/XOFF flow control */
    if ((response[0] & 0x10) != 0) {
        flags[0] |= 0x400;  /* Set IXOFF flag */
    }

    /* Check bit 0x4 (bit 2) in first byte - RTS flow control */
    if ((response[0] & 0x4) != 0) {
        flags[2] |= 0x20000;  /* Set CRTS_IFLOW flag */
    }

    /* Check bit 0x20 (bit 5) in first byte - CTS flow control */
    if ((response[0] & 0x20) != 0) {
        flags[2] |= 0x10000;  /* Set CCTS_OFLOW flag */
    }
}

/*
 * ttyiops_dcddelay - Handle delayed DCD (Data Carrier Detect) processing
 * Called after a delay to process DCD state changes through the line discipline
 */
void ttyiops_dcddelay(struct tty *tp)
{
    unsigned int state;
    unsigned int dcd_bit;

    if (tp == NULL) {
        return;
    }

    /* Check if DCD delay is pending and exclusive mode is set */
    /* Bit 2 at offset 0x15d: DCD delay pending flag */
    /* Bit 0x20 at offset 0x68: Exclusive mode flag */
    if ((((unsigned char *)tp)[0x15d] & 2) != 0 &&
        (((unsigned char *)tp)[0x68] & 0x20) != 0) {
        
        /* Get current state from IOPortSession */
        state = (unsigned int)objc_msgSend(((id *)tp)[0xe8/4], @selector(getState));

        /* Extract DCD bit (bit 6) and shift to bit 0 */
        dcd_bit = (state >> 6) & 1;

        /* Call line discipline modem function with DCD state */
        /* linesw[t_line].l_modem function is at offset 0x1c in linesw entry */
        /* Each linesw entry is 0x20 bytes, l_modem is the 8th function pointer */
        if (linesw[((int *)tp)[0x60/4]].l_modem) {
            linesw[((int *)tp)[0x60/4]].l_modem(tp, dcd_bit);
        }
    }

    /* Clear DCD delay pending flag (bit 2 at offset 0x15d) */
    ((unsigned char *)tp)[0x15d] &= ~2;
}

/*
 * ttyiops_init - Initialize TTY device for operation
 * Sets up function pointers, copies termios settings, and activates the device
 */
void ttyiops_init(struct tty *tp)
{
    struct termios *termios_src;
    unsigned int *src, *dst;
    int result;
    unsigned int state;
    struct timeval target_time, current_time, time_diff;
    int sleep_ms;
    int i;

    if (tp == NULL) {
        return;
    }

    /* Set up function pointers in tty structure */
    /* Offset 0xc0: t_oproc (output start function) */
    tp->t_oproc = ttyiops_start;
    
    /* Offset 200 (0xc8): t_param (parameter set function) */
    ((void **)tp)[200/4] = (void *)ttyiops_param;

    /* Determine which termios structure to use based on device flags */
    /* Check bit 0x20 at byte offset 100 */
    if ((((unsigned char *)tp)[100] & 0x20) == 0) {
        termios_src = (struct termios *)&((unsigned char *)tp)[0x120];
    } else {
        termios_src = (struct termios *)&((unsigned char *)tp)[0xf4];
    }

    /* Copy termios structure to t_termios at offset 0x8c */
    src = (unsigned int *)termios_src;
    dst = &((unsigned int *)tp)[0x8c/4];

    /* Copy 11 dwords (44 bytes) */
    for (i = 0; i < 11; i++) {
        *dst++ = *src++;
    }

    /* Set water marks for flow control */
    ttsetwater(tp);

    /* Execute initialization events */
    /* Event 0x28: Initialization event */
    objc_msgSend(((id *)tp)[0xe8/4], @selector(executeEvent:data:), 0x28, 0);

    /* Event 0x2f: Configuration event */
    objc_msgSend(((id *)tp)[0xe8/4], @selector(executeEvent:data:), 0x2f, 0);

    /* Clear bits 0xc (bits 2 and 3) at offset 0x68 */
    ((unsigned int *)tp)[0x68/4] &= ~0xc;

    /* Clear bit 0x20 (bit 5) at offset 0x15c */
    ((unsigned char *)tp)[0x15c] &= ~0x20;

    /* Calculate timeout value based on hz (system clock ticks per second) */
    /* Formula: (hz + 50) / 100 to get ticks for 10ms, with rounding */
    ((int *)tp)[0x158/4] = (int)((hz + 50) / 100);
    
    if (((int *)tp)[0x158/4] < 1) {
        ((int *)tp)[0x158/4] = 1;
    }

    /* Execute flow control event (0x53) */
    objc_msgSend(((id *)tp)[0xe8/4], @selector(executeEvent:data:), 0x53, 0);

    /* Set state: clear mask 0x20400000 */
    objc_msgSend(((id *)tp)[0xe8/4], @selector(setState:mask:), 0, 0x20400000);

    /* Execute ACTIVE event (5) and check result */
    result = (int)objc_msgSend(((id *)tp)[0xe8/4], @selector(executeEvent:data:), 5, 1);
    
    if (result != 0) {
        IOLog("PStty%04x: ACTIVE failed (%d)\n", ((int *)tp)[100/4], result);
    }

    /* Get current hardware state */
    state = (unsigned int)objc_msgSend(((id *)tp)[0xe8/4], @selector(getState));

    /* Check if bit 2 (DSR) is clear - need to wait for modem ready */
    if ((state & 2) == 0) {
        /* Get target time from offsets 0x14c and 0x150 (struct timeval) */
        target_time.tv_sec = ((long *)tp)[0x14c/sizeof(long)];
        target_time.tv_usec = ((long *)tp)[0x150/sizeof(long)];

        /* Add 2 seconds to target time */
        target_time.tv_sec += 2;

        /* Handle microsecond overflow */
        if (target_time.tv_usec > 999999) {
            target_time.tv_sec += 1;
            target_time.tv_usec -= 1000000;
        }

        /* Calculate time difference from current time */
        current_time = time;
        time_diff.tv_sec = target_time.tv_sec - current_time.tv_sec;
        time_diff.tv_usec = target_time.tv_usec - current_time.tv_usec;

        /* Handle underflow in microseconds */
        if (time_diff.tv_usec < 0) {
            time_diff.tv_sec -= 1;
            time_diff.tv_usec += 1000000;
        }

        /* Only sleep if time is in the future and non-zero */
        if (time_diff.tv_sec >= 0 && 
            (time_diff.tv_sec != 0 || time_diff.tv_usec != 0)) {
            
            /* Convert to milliseconds with rounding */
            sleep_ms = time_diff.tv_sec * 1000 + 
                      ((time_diff.tv_usec + 5000) / 10000) * 10;
            
            if (sleep_ms != 0) {
                IOSleep(sleep_ms);
            }
        }

        /* Assert DTR and RTS (bits 2 and 4 = 6) */
        ttyiops_mctl(tp, 6, 0);
    }

    /* Set state: set bit 4, mask bit 4 */
    objc_msgSend(((id *)tp)[0xe8/4], @selector(setState:mask:), 4, 4);
}

/*
/*
 * ttyiops_select - Select/poll on TTY device
 * Main select entry point for PortServer devices
 * Delegates to standard tty select handler
 */
int ttyiops_select(unsigned int dev, int which, struct proc *p)
{
    struct tty *tp;
    int result;
    
    /* Validate device and get tty structure */
    /* Check major number matches portServerMajor */
    if (portServerMajor != ((dev >> 8) & 0xff)) {
        tp = NULL;
    }
    /* Check that device is not 0xc0 (invalid combination) */
    else if ((dev & 0xc0) == 0xc0) {
        tp = NULL;
    }
    /* Get tty from map using minor number & 0x1f */
    else if (_ttyiopsMap[dev & 0x1f] == NULL) {
        tp = NULL;
    }
    else {
        /* tp points to offset 0x108 within the ttyiopsMap entry */
        tp = (struct tty *)((char *)_ttyiopsMap[dev & 0x1f] + 0x108);
    }
    
    result = 6;  /* ENXIO - No such device or address */
    
    if (tp != NULL) {
        /* Call standard tty select handler */
        result = ttyselect(tp, which, p);
    }
    
    return result;
}

/*
 * ttyiops_start - Start output on the TTY device
 * Called by line discipline when output data is available
 * Triggers hardware transmission by setting state bits
 */
void ttyiops_start(struct tty *tp)
{
    id portSession;
    
    /* Check if transmit can start:
     * - Bit 0x80 at offset 0x15c must be clear (not already transmitting)
     * - Bit 0x01 at offset 0x69 must be clear (not stopped by user)
     */
    
    /* Check byte at 0x15c - if bit 0x80 is clear (>= 0 when signed) */
    if ((((signed char *)tp)[0x15c] >= 0) && 
        ((((unsigned char *)tp)[0x69] & 1) == 0)) {
        
        /* Set bit 0x80 at offset 0x15c - mark as transmitting */
        ((unsigned char *)tp)[0x15c] = ((unsigned char *)tp)[0x15c] | 0x80;
        
        /* Set state bit 0x20000000 - trigger hardware transmission */
        portSession = ((id *)tp)[0xe8/4];
        objc_msgSend(portSession, @selector(setState:mask:), 
                     0xffffffff, 0x20000000);
    }
    
    /* Check if t_outq has data (offset 0x40 is t_outq.c_cc) */
    if (((int *)tp)[0x40/4] != 0) {
        /* Set state bit 0x8000000 - notify hardware data is ready */
        portSession = ((id *)tp)[0xe8/4];
        objc_msgSend(portSession, @selector(setState:mask:),
                     0x8000000, 0x8000000);
    }

/*
 * ttyiops_stop - Stop output on the TTY device
 * Called by line discipline to stop/restart output or flush queues
 * Returns 0 (always succeeds)
 */
int ttyiops_stop(struct tty *tp, int flags)
{
    id portSession;
    
    portSession = ((id *)tp)[0xe8/4];
    
    /* Check if output is currently stopped (bit 0x01 at offset 0x69 - TS_TTSTOP) */
    if ((((unsigned char *)tp)[0x69] & 1) != 0) {
        /* Output is stopped - clear transmission active flag */
        /* Clear bit 0x80 at offset 0x15c */
        ((unsigned char *)tp)[0x15c] = ((unsigned char *)tp)[0x15c] & 0x7f;
        
        /* Clear state bit 0x20000000 - stop hardware transmission */
        objc_msgSend(portSession, @selector(setState:mask:), 0, 0x20000000);
    }
    
    /* Check FWRITE flag (0x02) - flush write queue */
    if ((flags & 2) != 0) {
        /* Execute event 0x28 - flush/discard output data */
        objc_msgSend(portSession, @selector(executeEvent:data:), 0x28, 0);
    }
    
    /* Check FREAD flag (0x01) - flush read queue */
    if ((flags & 1) != 0) {
        /* Execute event 0x2f - flush/discard input data */
        objc_msgSend(portSession, @selector(executeEvent:data:), 0x2f, 0);
        
        /* If RTS flow control is active, re-assert RTS */
        /* Check bit 0x08 at offset 0x15c */
        if ((((unsigned char *)tp)[0x15c] & 8) != 0) {
            /* Set state bit 0x400000 - re-enable RTS */
            objc_msgSend(portSession, @selector(setState:mask:), 0x400000, 0x400000);
        }
    }
    
    return 0;
}

/*
 * ttyiops_txload - Load data into transmit queue
 * Dequeues data from t_outq and loads it into IOPortSession transmit buffer
 * Updates state mask based on transmission status
 */
void ttyiops_txload(struct tty *tp, unsigned int *mask)
{
    unsigned int buffer_space;
    unsigned int outq_size;
    unsigned int transfer_size;
    unsigned int bytes_transferred;
    int result;
    id portSession;
    unsigned char buffer[416];  /* 0x1a0 bytes */
    
    /* Check if output queue has data */
    if (((int *)tp)[0x40/4] == 0) {
        /* No data to send */
        return;
    }
    
    portSession = ((id *)tp)[0xe8/4];
    
    /* Set TS_BUSY flag if not already set */
    if ((((unsigned char *)tp)[0x68] & 4) == 0) {
        /* Set TS_BUSY flag (bit 0x04 at offset 0x68) */
        ((unsigned char *)tp)[0x68] = ((unsigned char *)tp)[0x68] | 4;
        
        /* Set state mask bits for TX monitoring */
        *mask = *mask | 0x4000000;   /* Watch for TX error */
        *mask = *mask & 0xefffffff;  /* Clear bit 0x10000000 (drain complete) */
    }
    
    /* Get initial output queue size */
    outq_size = ((unsigned int *)tp)[0x40/4];
    
    /* Main transmission loop - continue while data in queue */
    while (outq_size != 0) {
        /* Request available buffer space from hardware (event 0x23) */
        objc_msgSend(portSession, @selector(requestEvent:data:), 0x23, &buffer_space);
        
        /* Check if hardware has buffer space */
        if ((int)buffer_space < 1) {
            /* No buffer space - set bit 0x2000000 to watch for space */
            *mask = *mask | 0x2000000;
            return;
        }
        
        /* Calculate transfer size - minimum of:
         * - Available hardware buffer space
         * - Our local buffer size (0x1a0 = 416 bytes)
         * - Data in output queue
         */
        transfer_size = 0x1a0;
        if (buffer_space < 0x1a0) {
            transfer_size = buffer_space;
        }
        if ((int)transfer_size < (int)outq_size) {
            transfer_size = outq_size;
        }
        else {
            transfer_size = outq_size;
        }
        
        /* Dequeue data from t_outq to local buffer */
        bytes_transferred = q_to_b((struct clist *)((char *)tp + 0x40), 
                                   buffer, transfer_size);
        
        /* Enqueue data to IOPortSession transmit buffer */
        result = (int)objc_msgSend(portSession, 
                                   @selector(enqueueData:bufferSize:transferCount:minCount:),
                                   buffer, bytes_transferred, &outq_size, 0);
        
        if (result == 0) {
            /* Successfully enqueued - wake up processes waiting for output drain */
            ttwwakeup(tp);
        }
        else {
            /* Enqueue failed - log error */
            IOLog("PStty%04x: enqueueData rtn (%d)\n", 
                  ((unsigned int *)tp)[100/4], result);
        }
        
        /* Get updated output queue size for next iteration */
        outq_size = ((unsigned int *)tp)[0x40/4];
    }
    
    /* All data sent - return to caller */
}

/*
 * ttyiops_waitForDCD - Wait for DCD (carrier detect) signal
 * Blocks until carrier is detected or open is aborted
 * Returns 0 on success, 0x10 (EBUSY) if interrupted, 4 (EINTR) on signal
 */
int ttyiops_waitForDCD(struct tty *tp, int flag)
{
    int result;
    unsigned int watch_state;
    id portSession;
    
    /* Check conditions where we don't need to wait for DCD:
     * - FNONBLOCK flag set (bit 0x04 in flag)
     * - TS_CARR_ON already set (bit 0x08 at offset 0x68)
     * - CLOCAL flag set (bit 0x8000 in c_cflag at offset 0x94)
     */
    
    if ((flag & 4) != 0) {
        /* Non-blocking mode - don't wait */
        goto acquire_and_return;
    }
    
    if ((((unsigned char *)tp)[0x68] & 8) != 0) {
        /* Carrier already on */
        goto acquire_and_return;
    }
    
    /* Check CLOCAL flag (bit 15 of c_cflag) */
    /* When cast to short and checked < 0, tests if bit 15 (0x8000) is set */
    if (((short *)tp)[0x94/2] >= 0) {
        /* CLOCAL not set - must wait for carrier */
        
        portSession = ((id *)tp)[0xe8/4];
        
        /* Watch for DCD state bit (0x40) to become set */
        watch_state = 0x40;
        result = (int)objc_msgSend(portSession, @selector(watchState:mask:),
                                   &watch_state, 0x40);
        
        /* Check result codes */
        if (result == -0x2cd) {
            /* -0x2cd: Aborted/busy */
            return 0x10;  /* EBUSY */
        }
        else if (result == -0x2bf) {
            /* -0x2bf: Interrupted by signal */
            return 4;  /* EINTR */
        }
        /* result == 0: DCD detected, fall through */
        
        /* Call line discipline modem handler to notify of carrier */
        (*linesw[tp->t_line].l_modem)(tp, 1);
    }
    
acquire_and_return:
    /* Acquire session with audit flag = 0 (no audit) */
    objc_msgSend(((id *)tp)[0xe8/4], @selector(acquire:), 0);
    
    return 0;  /* Success */
}

/*
 * ttyiops_write - Write to TTY device
 * Main write entry point for PortServer devices
 * Delegates to line discipline write handler
 */
int ttyiops_write(unsigned int dev, struct uio *uio, int flag)
{
    struct tty *tp;
    int error;
    
    /* Validate device and get tty structure */
    /* Check major number matches portServerMajor */
    if (portServerMajor != ((dev >> 8) & 0xff)) {
        tp = NULL;
    }
    /* Check that device is not 0xc0 (invalid combination) */
    else if ((dev & 0xc0) == 0xc0) {
        tp = NULL;
    }
    /* Get tty from map using minor number & 0x1f */
    else if (_ttyiopsMap[dev & 0x1f] == NULL) {
        tp = NULL;
    }
    else {
        /* tp points to offset 0x108 within the ttyiopsMap entry */
        tp = (struct tty *)((char *)_ttyiopsMap[dev & 0x1f] + 0x108);
    }
    
    error = 6;  /* ENXIO - No such device or address */
    
    if (tp != NULL) {
        /* Call line discipline write handler */
        /* linesw[tp->t_line].l_write(tp, uio, flag) */
        error = (*linesw[tp->t_line].l_write)(tp, uio, flag);
    }
    
    return error;
}


/*
 * ttyiops_txFunc - Transmit thread function
 * Runs in a separate thread to continuously transmit data to hardware
 * Manages output queue, flow control, and carrier detect changes
 */
void ttyiops_txFunc(struct tty *tp)
{
    int result;
    unsigned int watch_state;
    unsigned int state_mask;
    unsigned int state_changes;
    unsigned int initial_dcd;
    unsigned int watch_mask;
    id portSession;
    
    portSession = ((id *)tp)[0xe8/4];
    
    /* Set up watch mask for state changes */
    state_mask = 0x18000040;  /* Watch bits: 0x40 (DCD), 0x8000000, 0x10000000 */
    
    /* Get initial DCD state */
    initial_dcd = (unsigned int)objc_msgSend(portSession, @selector(getState));
    
    /* Calculate initial watch state:
     * - Toggle DCD bit (0x40) from current state
     * - Set bits 0xe000000 (watch for TX events)
     */
    watch_mask = ((initial_dcd & 0x40) ^ 0x40) | 0xe000000;
    
    /* Main TX loop */
    while (1) {
        /* Set up state to watch for */
        watch_state = watch_mask;
        
        /* Wait for state changes */
        result = (int)objc_msgSend(portSession, @selector(watchState:mask:),
                                   &watch_state, state_mask);
        
        /* Check for interrupted and shutdown flag */
        if ((result == -0x2ca) && ((((unsigned char *)tp)[0x15c] & 0x20) != 0)) {
            /* Shutdown requested - exit loop */
            break;
        }
        
        /* Calculate which bits changed: mask & (~old_state ^ new_state) */
        /* This gives us bits that changed AND are in our watch mask */
        state_changes = state_mask & (~watch_mask ^ watch_state);
        
        /* Check if bit 0x8000000 changed (data ready for transmission) */
        if ((state_changes & 0x8000000) != 0) {
            /* Clear the data ready bit */
            objc_msgSend(portSession, @selector(setState:mask:), 0, 0x8000000);
            
            /* Load data into transmit queue */
            ttyiops_txload(tp, &state_mask);
        }
        
        /* Check if bit 0x40 changed (DCD - carrier detect) */
        if ((state_changes & 0x40) != 0) {
            /* Toggle DCD watch state - watch for opposite state next time */
            watch_mask = watch_mask ^ 0x40;
            
            /* Check if DCD delay is NOT already pending (bit 0x02 at offset 0x15d) */
            if ((((unsigned char *)tp)[0x15d] & 2) == 0) {
                /* Set DCD delay pending flag */
                ((unsigned char *)tp)[0x15d] = ((unsigned char *)tp)[0x15d] | 2;
                
                /* Schedule timeout to process DCD change */
                /* Call ttyiops_dcddelay after delay (0x3b84 ticks) */
                timeout((timeout_func_t)ttyiops_dcddelay, tp, 0x3b84);
            }
            else {
                /* DCD delay already pending - cancel it */
                ((unsigned char *)tp)[0x15d] = ((unsigned char *)tp)[0x15d] & 0xfd;
                untimeout((timeout_func_t)ttyiops_dcddelay, tp);
            }
        }
        
        /* Check if bit 0x2000000 changed (TX complete/buffer empty) */
        if ((state_changes & 0x2000000) != 0) {
            /* Clear bit 0x2000000 from state_mask - no longer watching it */
            state_mask = state_mask & 0xfdffffff;
            
            /* Load more data (may re-enable bit in mask) */
            ttyiops_txload(tp, &state_mask);
        }
        
        /* Check if bit 0x4000000 changed (TX error or special condition) */
        if ((state_changes & 0x4000000) != 0) {
            /* Clear bit 0x4000000, set bit 0x10000000 in state_mask */
            state_mask = (state_mask & 0xfbffffff) | 0x10000000;
        }
        
        /* Check if bit 0x10000000 is set in mask but NOT in current state */
        /* This means we want to signal TX drain complete */
        if ((state_mask & ~watch_state & 0x10000000) != 0) {
            /* Clear bit 0x10000000 from state_mask */
            state_mask = state_mask & 0xefffffff;
            
            /* Clear TS_BUSY flag (bit 0x04 at offset 0x68) */
            ((unsigned int *)tp)[0x68/4] = ((unsigned int *)tp)[0x68/4] & 0xfffffffb;
            
            /* Wake up processes waiting for output drain */
            ttwwakeup(tp);
        }
    }
    
    /* Thread shutdown sequence */
    /* Check if DCD delay is pending */
    if ((((unsigned char *)tp)[0x15d] & 2) != 0) {
        /* Clear pending flag */
        ((unsigned char *)tp)[0x15d] = ((unsigned char *)tp)[0x15d] & 0xfd;
        
        /* Cancel timeout */
        untimeout((timeout_func_t)ttyiops_dcddelay, tp);
    }
    
    /* Clear TX thread handle at offset 0xf0 */
    ((void **)tp)[0xf0/4] = NULL;
    
    /* Wake up any threads waiting on the TX thread handle */
    wakeup(&((void **)tp)[0xf0/4]);
    
    /* Exit this kernel thread */
    IOExitThread();
}


/*
/*
 * ttyiops_param - Set TTY parameters
 * Configures hardware serial port parameters based on termios settings
 * Handles baud rate, character size, parity, stop bits, and flow control
 * Returns 0 on success, 0x16 (EINVAL) on failure
 */
int ttyiops_param(struct tty *tp, struct termios *t)
{
    int result;
    int speed_index;
    unsigned int cflag;
    unsigned int iflag;
    unsigned int char_size;
    unsigned int parity;
    unsigned int stop_bits;
    unsigned int flow_control;
    unsigned int xon_char_result, xoff_char_result;
    id portSession;
    
    result = 0x16;  /* EINVAL - Invalid argument */
    
    /* Validate XON/XOFF characters if IXON or IXOFF is set */
    /* Check c_iflag bits 1 and 2 (IXON=0x200/bit 9, IXOFF=0x400/bit 10) 
     * The decompiled code checks byte at offset 1 with mask 6
     * c_iflag is at offset 0, so byte 1 would be bits 8-15
     * Bits 1-2 of byte 1 = bits 9-10 of c_iflag = IXON|IXOFF
     */
    iflag = t->c_iflag;
    if ((((unsigned char *)&iflag)[1] & 6) != 0) {
        /* If VSTART (c_cc[7]) is -1, invalid */
        if (t->c_cc[7] == (unsigned char)-1) {
            return 0x16;
        }
        /* If VSTOP (c_cc[8], offset 0x1d from base) is -1, invalid */
        if (t->c_cc[8] == (unsigned char)-1) {
            return 0x16;
        }
    }
    
    /* Handle input/output speed settings */
    /* If c_ispeed is 0, set it equal to c_ospeed */
    if (t->c_ispeed == 0) {
        t->c_ispeed = t->c_ospeed;
    }
    
    /* Look up speed in ttyiops_speeds table */
    speed_index = ttspeedtab(t->c_ospeed, ttyiops_speeds);
    
    /* If speed not found (returned 0) and speeds differ, return error */
    if ((speed_index != 0) && (t->c_ospeed != t->c_ispeed)) {
        return 0x16;
    }
    
    /* Set baud rate - event 0x33 */
    portSession = ((id *)tp)[0xe8/4];
    result = (int)objc_msgSend(portSession, @selector(executeEvent:data:), 0x33, speed_index);
    if (result != 0) {
        return 0x16;
    }
    
    /* Configure character size based on CSIZE bits (0x300 in c_cflag) */
    cflag = t->c_cflag;
    char_size = cflag & 0x300;  /* CSIZE mask */
    
    if (char_size == 0x100) {
        /* CS6 - 6 bits */
        char_size = 0xc;  /* 12 decimal */
    }
    else if (char_size < 0x101) {
        if (char_size == 0) {
            /* CS5 - 5 bits */
            char_size = 10;
            goto set_char_size;
        }
        /* Not 0 or 0x100, so must be 0x200 or 0x300 below */
        char_size = 0x10;  /* Default to 16 (8 bits) */
    }
    else if (char_size == 0x200) {
        /* CS7 - 7 bits */
        char_size = 0xe;  /* 14 decimal */
    }
    else {
        /* CS8 - 8 bits (0x300) or invalid */
        char_size = 0x10;  /* 16 decimal */
    }
    
set_char_size:
    /* Set character size - event 0x3b */
    result = (int)objc_msgSend(portSession, @selector(executeEvent:data:), 0x3b, char_size);
    if (result != 0) {
        return result;
    }
    
    /* Configure parity based on PARENB (0x1000) and PARODD (0x2000) */
    parity = 1;  /* No parity */
    if ((cflag & 0x1000) != 0) {
        /* PARENB set - parity enabled */
        parity = 3;  /* Even parity */
        if ((cflag & 0x2000) != 0) {
            /* PARODD set - odd parity */
            parity = 2;
        }
    }
    
    /* Set parity - event 0x43 */
    result = (int)objc_msgSend(portSession, @selector(executeEvent:data:), 0x43, parity);
    if (result != 0) {
        return result;
    }
    
    /* Configure stop bits based on CSTOPB (0x400) */
    stop_bits = 2;  /* 1 stop bit */
    if ((cflag & 0x400) != 0) {
        /* CSTOPB set - 2 stop bits */
        stop_bits = 4;
    }
    
    /* Set stop bits - event 0xf3 */
    result = (int)objc_msgSend(portSession, @selector(executeEvent:data:), 0xf3, stop_bits);
    if (result != 0) {
        return result;
    }
    
    /* Build flow control flags from termios settings */
    flow_control = 0;
    
    /* Check IXOFF (bit 10 = 0x400, byte 1 bit 2 = 0x2 in byte 1) */
    if ((((unsigned char *)&iflag)[1] & 2) != 0) {
        flow_control = 8;  /* Software input flow control */
    }
    
    /* Check IXON (bit 9 = 0x200, byte 1 bit 1 = 0x8 in big-endian byte 1) 
     * Actually checking byte at offset 1, bit 3 (0x8) */
    if ((((unsigned char *)&iflag)[1] & 8) != 0) {
        flow_control = flow_control | 0x400;  /* Software output flow control */
    }
    
    /* Check INPCK (bit 4 = 0x10, byte 0 bit 4) */
    if ((((unsigned char *)&iflag)[1] & 4) != 0) {
        flow_control = flow_control | 0x10;  /* Parity checking */
    }
    
    /* Check CRTS_IFLOW (0x20000 in c_cflag) - hardware input flow (RTS) */
    if ((cflag & 0x20000) != 0) {
        flow_control = flow_control | 4;
    }
    
    /* Check CCTS_OFLOW (0x10000 in c_cflag) - hardware output flow (CTS) */
    if ((cflag & 0x10000) != 0) {
        flow_control = flow_control | 0x20;
    }
    
    /* Clear software flow control flags in termios (will be managed by hardware) */
    t->c_iflag = t->c_iflag & 0xfffff1ff;  /* Clear bits 9-11 (IXON, IXOFF, IXANY) */
    t->c_cflag = t->c_cflag & 0xfffcffff;  /* Clear bits 16-17 (CCTS_OFLOW, CRTS_IFLOW) */
    
    /* Set flow control - event 0x53 */
    result = (int)objc_msgSend(portSession, @selector(executeEvent:data:), 0x53, flow_control);
    if (result != 0) {
        return result;
    }
    
    /* Set XON character - event 0xed */
    xon_char_result = (unsigned int)objc_msgSend(portSession, @selector(executeEvent:data:), 
                                                  0xed, t->c_cc[7]);  /* VSTART */
    
    /* Set XOFF character - event 0xe9 */
    xoff_char_result = (unsigned int)objc_msgSend(portSession, @selector(executeEvent:data:),
                                                   0xe9, t->c_cc[8]);  /* VSTOP */
    
    /* Check if either XON or XOFF setting failed */
    if ((xon_char_result | xoff_char_result) != 0) {
        return result;
    }
    
    /* Set flag at offset 0x15c, bit 0x80 */
    ((unsigned char *)tp)[0x15c] = ((unsigned char *)tp)[0x15c] | 0x80;
    
    /* Set state bit 0x20000000 - indicate parameters are set */
    objc_msgSend(portSession, @selector(setState:mask:), 0x20000000, 0x20000000);
    
    /* Handle MDMBUF flag (0x800 in c_cflag) - modem flow control */
    if ((cflag & 0x800) != 0) {
        /* Enable carrier flow control */
        objc_msgSend(portSession, @selector(setState:mask:), 0xffffffff, 0x400000);
    }
    else {
        /* Disable carrier flow control */
        objc_msgSend(portSession, @selector(setState:mask:), 0, 0x400000);
    }
    
    result = 0;  /* Success */
    return result;
}


/*
 * ttyiops_ioctl - Main ioctl handler for TTY devices
 * Routes ioctl commands to appropriate handlers
 * Returns 0 on success, error code on failure
 */
int ttyiops_ioctl(unsigned int dev, unsigned int cmd, void *data, int flag, struct proc *p)
{
    struct tty *tp = NULL;
    unsigned int minor;
    int error = 0;
    unsigned int modem_bits;
    unsigned int how;

    /* Validate device and find corresponding tty structure */
    if ((portServerMajor == ((dev >> 8) & 0xff)) && 
        ((dev & 0xc0) != 0xc0)) {
        minor = dev & 0x1f;
        if (_ttyiopsMap[minor] != NULL) {
            tp = (struct tty *)((char *)_ttyiopsMap[minor] + 0x108);
        }
    }

    if (tp == NULL) {
        return 6; // ENXIO
    }

    /* Check if this is a control device */
    if ((dev & 0xc0) != 0) {
        return ttyiops_control_ioctl(tp, dev, cmd, data, flag, p);
    }

    /* Try line discipline ioctl first */
    if (linesw[((int *)tp)[0x60/4]].l_ioctl) {
        error = linesw[((int *)tp)[0x60/4]].l_ioctl(tp, cmd, data, flag, p);
    } else {
        error = -1; // ENOTTY
    }

    /* If line discipline handled it, we're done (unless positive error) */
    if (error >= 0) {
        goto update_and_return;
    }

    /* Handle termios ioctls */
    switch (cmd) {
        case 0x402c7413:  /* TIOCGETA - Get termios */
            /* Copy termios from offset 0x8c */
            bcopy(&((unsigned char *)tp)[0x8c], data, 0x2c);
            
            /* Update flow control flags */
            ttyiops_convertFlowCtrl(((id *)tp)[0xe8/4], (unsigned int *)data);
            
            error = 0;
            goto cleanup_and_return;

        case 0x802c7414:  /* TIOCSETA - Set termios immediately */
        case 0x802c7415:  /* TIOCSETAW - Set termios after drain */
        case 0x802c7416:  /* TIOCSETAF - Set termios after drain and flush */
            /* Get current flow control settings */
            ttyiops_convertFlowCtrl(((id *)tp)[0xe8/4], 
                                   &((unsigned int *)tp)[0x8c/4]);

            /* Validate parity settings */
            /* Check if PARENB is set (bit 0 at byte offset param_3+2) */
            /* and if parity is enabled in current settings (bits 6 in byte at 0x8d) */
            if ((((unsigned char *)data)[8] & 1) != 0 &&  // c_cflag & PARENB
                (((unsigned char *)tp)[0x8d] & 6) != 0) { // Current parity flags
                /* Check for invalid speed values */
                if (((char *)data)[7] == -1 || ((char *)data)[0x1d] == -1) {
                    error = 0x16; // EINVAL
                    goto cleanup_and_return;
                }
            }
            break;

        default:
            break;
    }

    /* Try standard tty ioctl */
    error = ttioctl(tp, cmd, data, flag, p);

    if (error < 0) {
        /* Handle custom modem control ioctls */
        error = 0;

        switch (cmd) {
            case 0x20007478:  /* TIOCSDTR - Set DTR */
                modem_bits = 2;
                how = 2;  /* Set */
                goto do_modem_control;

            case 0x20007479:  /* TIOCCDTR - Clear DTR */
                modem_bits = 2;
                how = 1;  /* Clear */
                goto do_modem_control;

            case 0x2000747a:  /* TIOCMSET - Set modem bits (masked) */
                modem_bits = 0x800;
                how = 2;  /* Set */
                goto do_modem_control;

            case 0x2000747b:  /* TIOCMBIS - Bit set */
                modem_bits = 0x800;
                how = 1;  /* Set specified bits */
                goto do_modem_control;

            case 0x4004746a:  /* TIOCMGET - Get modem bits */
                /* Get modem control status */
                modem_bits = ttyiops_mctl(tp, 0, 3);
                
                /* Convert RS232 to termios format */
                modem_bits = rs232totio(modem_bits);
                
                /* Return to user */
                *((unsigned int *)data) = modem_bits;
                goto cleanup_and_return;

            case 0x8004746b:  /* TIOCMSET - Set all modem bits */
                modem_bits = *((unsigned int *)data);
                how = 2;  /* Set */
                goto convert_and_set;

            case 0x8004746c:  /* TIOCMBIS - Set specified bits */
                modem_bits = *((unsigned int *)data);
                how = 1;  /* Set bits */
                goto convert_and_set;

            case 0x8004746d:  /* TIOCMBIC - Clear specified bits */
                modem_bits = *((unsigned int *)data);
                how = 0;  /* Clear bits */
                goto convert_and_set;

            default:
                error = 0x19; // ENOTTY
                goto cleanup_and_return;

convert_and_set:
            /* Convert termios format to RS232 */
            modem_bits = tiotors232(modem_bits);

do_modem_control:
            /* Execute modem control */
            ttyiops_mctl(tp, modem_bits, how);
            goto cleanup_and_return;
        }
    }

update_and_return:
    /* If ioctl succeeded and changed parameters, apply them */
    if (error > 0) {
        ttyiops_param(tp, (struct termios *)&((unsigned char *)tp)[0x8c]);
    }

    /* Optimize input processing based on current settings */
    ttyiops_optimiseInput(tp, (struct termios *)&((unsigned char *)tp)[0x8c]);

cleanup_and_return:
    /* Clear flow control flags that shouldn't be user-visible */
    /* Clear bits 0x200, 0x400, 0x800 at offset 0x8c (c_iflag) */
    ((unsigned int *)tp)[0x8c/4] &= ~0xe00;
    
    /* Clear bits 0x10000, 0x20000, 0x30000 at offset 0x94 (c_cflag) */
    ((unsigned int *)tp)[0x94/4] &= ~0x30000;

    return error;
}

/*
 * ttyiops_optimiseInput - Optimize input processing based on termios settings
 * Determines if input can be processed in "raw" mode for better performance
 * Sets TS_CAN_BYPASS_L_RINT flag if line discipline input processing can be bypassed
 */
void ttyiops_optimiseInput(struct tty *tp, struct termios *t)
{
    int need_processing;
    unsigned int event1, event2;
    id portSession;

    need_processing = 0;

    /* Check various termios flags that require character-by-character processing:
     *
     * t_iflag (input flags) - mask 0x23e0:
     *   ISTRIP   0x0020 - Strip 8th bit
     *   INLCR    0x0040 - Map NL to CR
     *   IGNCR    0x0080 - Ignore CR
     *   ICRNL    0x0100 - Map CR to NL
     *   IXON     0x0200 - Enable XON/XOFF output control
     *   IXANY    0x0800 - Allow any char to restart output
     *   IMAXBEL  0x2000 - Ring bell on full input queue
     *
     * t_lflag (local flags) - mask 0x588:
     *   ECHO     0x0008 - Echo input
     *   ECHONL   0x0080 - Echo NL even if ECHO off
     *   ICANON   0x0100 - Canonical input (erase/kill processing)
     *   ISIG     0x0080 - Enable signals (different bit position)
     *   IEXTEN   0x0400 - Enable extended processing
     */

    /* Check if any input flags requiring processing are set (mask 0x23e0) */
    if ((t->c_iflag & 0x23e0) != 0) {
        need_processing = 1;
    }
    /* Check if IGNBRK (0x1) not set but BRKINT (0x2) is set (special break handling) */
    else if ((t->c_iflag & 3) == 2) {
        need_processing = 1;
    }
    /* Check if IGNPAR (0x4) not set and PARMRK (0x8) is set, but not both IGNPAR and INPCK */
    else if (((t->c_iflag & 8) != 0) && ((t->c_iflag & 5) != 5)) {
        need_processing = 1;
    }
    /* Check if any local flags requiring processing are set (mask 0x588) */
    else if ((t->c_lflag & 0x588) != 0) {
        need_processing = 1;
    }
    /* Check if line discipline input routine is not the standard ttyinput */
    else if (linesw[tp->t_line].l_rint != ttyinput) {
        need_processing = 1;
    }

    /* Update t_state flag based on whether processing is needed */
    if (need_processing) {
        /* Clear TS_CAN_BYPASS_L_RINT flag (bit 0x10000) - cannot bypass */
        ((unsigned int *)tp)[0x68/4] = ((unsigned int *)tp)[0x68/4] & 0xfffeffff;
    }
    else {
        /* Set TS_CAN_BYPASS_L_RINT flag (bit 0x10000) - can bypass for speed */
        ((unsigned int *)tp)[0x68/4] = ((unsigned int *)tp)[0x68/4] | 0x10000;
    }

    /* Execute hardware events based on line discipline */
    portSession = ((id *)tp)[0xe8/4];

    if (tp->t_line == 4) {
        /* Line discipline 4 - SLIPDISC (Serial Line IP) */
        /* Execute event 0x59 with data 0xc0 */
        objc_msgSend(portSession, @selector(executeEvent:data:), 0x59, 0xc0);
        event2 = 0x7e;  /* Second event will be 0x55 with data 0x7e */
    }
    else if (tp->t_line == 5) {
        /* Line discipline 5 - PPPDISC (Point-to-Point Protocol) */
        event1 = 0x59;
        event2 = 0x7e;
        /* Execute event 0x59 with data 0x7e */
        objc_msgSend(portSession, @selector(executeEvent:data:), event1, 0x7e);
        event2 = 0xc0;  /* Second event will be 0x55 with data 0xc0 */
    }
    else {
        /* Standard line disciplines (0=TTYDISC, 1=NTTYDISC, 2=TABLDISC, etc.) */
        event1 = 0x55;
        /* Execute event 0x55 with data 0x7e */
        objc_msgSend(portSession, @selector(executeEvent:data:), event1, 0x7e);
        event2 = 0xc0;
    }

    /* Execute second event: 0x55 with the determined event2 data */
    objc_msgSend(portSession, @selector(executeEvent:data:), 0x55, event2);
}

/*
 * ttyiops_waitForDCD - Wait for DCD (carrier detect) signal
 * Stub function - implementation needed
 */
int ttyiops_waitForDCD(struct tty *tp, int flag)
{
    /* TODO: Implement DCD waiting logic */
    /* This function should:
     * - Check current DCD state
     * - Sleep waiting for carrier if needed
     * - Handle CLOCAL flag (local mode, ignore carrier)
     * - Return appropriate error codes
     */
    return 0;

/*
 * ttyiops_read - Read from TTY device
 * Main read entry point for PortServer devices
 * Delegates to line discipline read handler and manages flow control
 */
int ttyiops_read(unsigned int dev, struct uio *uio, int flag)
{
    struct tty *tp;
    int error;
    int rawq_cc;
    int canq_size;
    
    /* Validate device and get tty structure */
    /* Check major number matches portServerMajor */
    if (portServerMajor != ((dev >> 8) & 0xff)) {
        tp = NULL;
    }
    /* Check that device is not 0xc0 (invalid combination) */
    else if ((dev & 0xc0) == 0xc0) {
        tp = NULL;
    }
    /* Get tty from map using minor number & 0x1f */
    else if (_ttyiopsMap[dev & 0x1f] == NULL) {
        tp = NULL;
    }
    else {
        /* tp points to offset 0x108 within the ttyiopsMap entry */
        tp = (struct tty *)((char *)_ttyiopsMap[dev & 0x1f] + 0x108);
    }
    
    error = 6;  /* ENXIO - No such device or address */
    
    if (tp != NULL) {
        /* Call line discipline read handler */
        /* linesw[tp->t_line].l_read(tp, uio, flag) */
        error = (*linesw[tp->t_line].l_read)(tp, uio, flag);
        
        /* Check if RTS flow control is enabled and queue has space */
        /* Check bit 0x08 at offset 0x57 (t_state flags) */
        /* This is the "RTS flow control active" flag */
        if ((((unsigned char *)tp)[0x57] & 8) != 0) {
            /* Calculate total queue usage: t_rawq.c_cc + canq */
            rawq_cc = tp->t_rawq.c_cc;
            canq_size = ((int *)tp)[8];  /* canq at offset 0x20 (8*4) */
            
            /* If total queue usage < 0x37c (892 bytes), re-enable RTS */
            /* Queue has space, allow more data to flow in */
            if (rawq_cc + canq_size < 0x37c) {
                /* Set state bit 0x400000 to re-assert RTS */
                objc_msgSend(((id *)tp)[0xe8/4], @selector(setState:mask:),
                             0x400000, 0x400000);
            }
        }
    }
    
    return error;
}

/*
 * ttyiops_rxFunc - Receive thread function
 * Runs in a separate thread to continuously receive data from hardware
 * Processes both data and events from the IOPortSession
 */
void ttyiops_rxFunc(struct tty *tp)
{
    int result;
    unsigned int next_event;
    unsigned int state_watch;
    id portSession;
    unsigned char flags;
    
    /* Clear RX thread active flag (bit 0x08 at offset 0x15c) */
    ((unsigned char *)tp)[0x15c] = ((unsigned char *)tp)[0x15c] & 0xf7;
    
    flags = ((unsigned char *)tp)[0x15c];
    portSession = ((id *)tp)[0xe8/4];
    
    /* Main RX loop - continue until shutdown flag (bit 0x20) is set */
    while ((flags & 0x20) == 0) {
        /* Check if we should watch for state changes (bit 0x08) */
        if ((((unsigned char *)tp)[0x15c] & 8) != 0) {
            /* Watch for state bit 0x100000 to change */
            state_watch = 0x100000;
            result = (int)objc_msgSend(portSession, @selector(watchState:mask:),
                                       &state_watch, 0x100000);
            
            /* If watchState returned -0x2ca (interrupted) and shutdown flag set, exit */
            if ((result == -0x2ca) && ((((unsigned char *)tp)[0x15c] & 0x20) != 0)) {
                break;
            }
        }
        
        /* Get next event type from IOPortSession */
        next_event = (unsigned int)objc_msgSend(portSession, @selector(nextEvent));
        
        /* Check if this is a data event (type 0, 1, 2, 3 or 0x54, 0x55, 0x56, 0x57) */
        /* Mask off bottom 2 bits - if result is 0 or 0x54, it's a data event */
        if (((next_event & 0xfffffffc) == 0) || ((next_event & 0xfffffffc) == 0x54)) {
            /* Data available - process it */
            ttyiops_getData(tp);
        }
        else {
            /* Non-data event - process it */
            ttyiops_procEvent(tp);
        }
        
        /* Re-check flags for next iteration */
        flags = ((unsigned char *)tp)[0x15c];
    }
    
    /* Thread shutdown sequence */
    /* Clear RX thread handle at offset 0xec */
    ((void **)tp)[0xec/4] = NULL;
    
    /* Wake up any threads waiting on the RX thread handle */
    wakeup(&((void **)tp)[0xec/4]);
    
    /* Exit this kernel thread */
    IOExitThread();
}


/*
 * ttyiops_open - Open a tty device
 * Main open routine for PortServer tty devices
 * Handles device validation, session acquisition, initialization, and thread creation
 * Returns 0 on success, error code on failure
 */
int ttyiops_open(unsigned int dev, int flag, int mode, struct proc *p)
{
    struct tty *tp;
    unsigned int state;
    int error;
    int *open_count_ptr;
    id portSession;
    void *thread_id;
    
    /* Validate device and get tty structure */
    /* Check major number matches portServerMajor */
    if (portServerMajor != ((dev >> 8) & 0xff)) {
        tp = NULL;
    }
    /* Check that device is not 0xc0 (invalid combination) */
    else if ((dev & 0xc0) == 0xc0) {
        tp = NULL;
    }
    /* Get tty from map using minor number & 0x1f */
    else if (_ttyiopsMap[dev & 0x1f] == NULL) {
        tp = NULL;
    }
    else {
        /* tp points to offset 0x108 within the ttyiopsMap entry */
        tp = (struct tty *)((char *)_ttyiopsMap[dev & 0x1f] + 0x108);
    }
    
    error = 0;
    
    /* If no valid tty found, return ENXIO (6) */
    if (tp == NULL) {
        error = 6;  /* ENXIO - No such device or address */
    }
    /* Handle data device opens (bits 0xc0 == 0) */
    else if ((dev & 0xc0) == 0) {
        /* Check if exclusive use flag is set and verify permission */
        if ((((unsigned char *)tp)[0x69] & 4) != 0) {
            /* suser() checks if user has superuser privileges */
            error = suser(((struct proc *)p)->p_ucred->cr_uid, &p->p_acflag);
            if (error == 0) {
                return 0x10;  /* EBUSY */
            }
        }
        
        /* Increment open count if not O_NONBLOCK (0x20) */
        if ((dev & 0x20) == 0) {
            ((int *)tp)[0x154/4] = ((int *)tp)[0x154/4] + 1;
        }
        
        /* Main open loop - keep trying until successful */
        while (1) {
            /* Try to acquire session */
            error = ttyiops_acquireSession(tp, dev);
            if (error != 0) {
                break;  /* Failed to acquire session */
            }
            
            /* If device not already open (t_state & TS_ISOPEN == 0) */
            if ((((unsigned char *)tp)[0x68] & 0x20) == 0) {
                /* Initialize device and parameters */
                ttyiops_init(tp);
                ttyiops_param(tp, (struct termios *)((char *)tp + 0x8c));
            }
            
            /* Check if O_NONBLOCK set OR DCD is present */
            if ((dev & 0x20) != 0) {
                /* Non-blocking open, proceed to line discipline */
                goto line_discipline_open;
            }
            
            /* Get hardware state to check DCD (bit 0x40) */
            state = (unsigned int)objc_msgSend(((id *)tp)[0xe8/4], @selector(getState));
            if ((state & 0x40) != 0) {
                /* DCD present, can proceed */
                goto line_discipline_open;
            }
            
            /* Need to wait for DCD if:
             * - Not O_NONBLOCK (checked above)
             * - CLOCAL not set (checked here via t_cflag bit 0x8000)
             */
            if ((((short *)tp)[0x94/4] & 0x8000) == 0) {
                /* CLOCAL not set, must wait for carrier */
                portSession = ((id *)tp)[0xe8/4];
                error = ttyiops_waitForDCD(tp, flag);
                
                /* Handle wait results */
                if (error == 0x10) {
                    /* EBUSY - Check if this process owns the device */
                    if (((unsigned int *)tp)[100/4] == dev) {
                        /* Clear device ownership */
                        ((unsigned int *)tp)[100/4] = 0;
                    }
                    else {
                        /* Free the session (different process) */
                        objc_msgSend(portSession, @selector(free));
                    }
                    /* Continue loop to retry */
                    continue;
                }
                else if (error == 4) {
                    /* EINTR - Interrupted by signal */
                    open_count_ptr = &((int *)tp)[0x154/4];
                    *open_count_ptr = *open_count_ptr - 1;
                    error = 4;
                    
                    /* If last close, clean up */
                    if (*open_count_ptr == 0) {
                        ttyiops_close(dev, flag, mode, (int)p);
                        return 4;
                    }
                    
                    /* Clear device ownership and wake up waiters */
                    ((unsigned int *)tp)[100/4] = 0;
                    goto wakeup_and_return;
                }
                /* error == 0 means DCD arrived, fall through */
            }
            
line_discipline_open:
            /* Create RX thread if not already created */
            if (((void **)tp)[0xec/4] == NULL) {
                thread_id = (void *)IOForkThread((IOThreadFunc)ttyiops_rxFunc, tp);
                ((void **)tp)[0xec/4] = thread_id;
            }
            
            /* Create TX thread if not already created */
            if (((void **)tp)[0xf0/4] == NULL) {
                thread_id = (void *)IOForkThread((IOThreadFunc)ttyiops_txFunc, tp);
                ((void **)tp)[0xf0/4] = thread_id;
            }
            
            /* Call line discipline open */
            error = (*linesw[tp->t_line].l_open)(dev, tp);
            
            /* Decrement open count if not O_NONBLOCK */
            if ((dev & 0x20) == 0) {
                ((int *)tp)[0x154/4] = ((int *)tp)[0x154/4] - 1;
            }
            
wakeup_and_return:
            /* Wake up any processes waiting on this tty */
            wakeup(tp);
            return error;
        }
        
        /* If we get here, session acquisition failed */
        /* Decrement open count if not O_NONBLOCK */
        if ((dev & 0x20) == 0) {
            ((int *)tp)[0x154/4] = ((int *)tp)[0x154/4] - 1;
        }
    }
    /* Handle control device opens (bit 0x40 set) */
    else if ((dev & 0x40) == 0) {
        /* If bit 0x40 not set but bit 0xc0 != 0, invalid */
        error = 0x13;  /* EACCES */
    }
    /* else: control device (0x40 set), error remains 0 */
    
    return error;
}

/*
 * ttyiops_procEvent - Process hardware events from IOPortSession
 * Dequeues events from the port session and handles them appropriately
 * Certain events are passed to the line discipline for processing
 */
void ttyiops_procEvent(struct tty *tp)
{
    unsigned int event_type;
    unsigned int event_data;
    id portSession;
    char *overflow_type;
    
    /* Dequeue event from IOPortSession (non-blocking) */
    portSession = ((id *)tp)[0xe8/4];
    objc_msgSend(portSession, @selector(dequeueEvent:data:sleep:),
                 &event_type, &event_data, 0);
    
    /* Process event based on type */
    
    /* Event 0x5c - Special event requiring bit 0x1000000 to be set */
    if (event_type == 0x5c) {
        event_data = event_data | 0x1000000;
        goto send_to_line_discipline;
    }
    
    if (event_type < 0x5d) {
        /* Events less than 0x5d */
        if (event_type == 0x53) {
            /* Event 0x53 - Flow control event, pass through */
            goto send_to_line_discipline;
        }
        if (event_type > 0x53) {
            /* Event 0x59 - Protocol event (SLIP/PPP), pass through */
            if (event_type == 0x59) {
                goto send_to_line_discipline;
            }
        }
        /* Other events < 0x5d: ignore */
        event_type = 0;
        goto send_to_line_discipline;
    }
    
    /* Events >= 0x5d */
    if (event_type == 0x68) {
        /* Event 0x68 - Hardware overflow error */
        overflow_type = "Hard";
        goto log_overflow;
    }
    
    if (event_type < 0x69) {
        /* Event 0x60 - Special event requiring bit 0x2000000 to be set */
        if (event_type == 0x60) {
            event_data = event_data | 0x2000000;
            goto send_to_line_discipline;
        }
    }
    else {
        /* Events >= 0x69 */
        if (event_type == 0x6c) {
            /* Event 0x6c - Software overflow error */
            overflow_type = "Soft";
            goto log_overflow;
        }
        
        if (event_type == 0xf9) {
            /* Event 0xf9 - Special event with bit 0x1000000 */
            event_data = 0;
            event_data = event_data | 0x1000000;
            goto send_to_line_discipline;
        }
    }
    
    /* Unknown event type - ignore */
    event_type = 0;
    goto send_to_line_discipline;

log_overflow:
    /* Log overflow error (hardware or software) */
    IOLog("PStty%04x: %sware Overflow\n", 
          ((unsigned int *)tp)[100/4], overflow_type);
    event_type = 0;  /* Don't pass overflow events to line discipline */

send_to_line_discipline:
    /* If event_type is non-zero, call line discipline input routine */
    if (event_type != 0) {
        /* Call l_rint function of current line discipline */
        /* linesw[tp->t_line].l_rint(event_data, tp) */
        (*linesw[tp->t_line].l_rint)(event_data, tp);
    }
}


/* ========================================================================
 * Character Device Switch Wrappers
 * ======================================================================== */

/*
 * portServeropen - Character device open wrapper
 * Simply calls ttyiops_open
 */
int portServeropen(unsigned int dev, int flag, int mode, struct proc *p)
{
    return ttyiops_open(dev, flag, mode, p);
}

/*
 * portServerclose - Character device close wrapper
 * Simply calls ttyiops_close
 */
int portServerclose(unsigned int dev, int flag)
{
    return ttyiops_close(dev, flag);
}

/*
 * portServerioctl - Character device ioctl wrapper
 * Simply calls ttyiops_ioctl
 */
int portServerioctl(unsigned int dev, unsigned int cmd, void *data, int flag, struct proc *p)
{
    return ttyiops_ioctl(dev, cmd, data, flag, p);
}
