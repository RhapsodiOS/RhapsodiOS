/*
 * EtherLinkXLKDB.m
 * 3Com EtherLink XL Network Driver - KDB/Debugger Support
 */

#import "EtherLinkXL.h"
#import <driverkit/generalFuncs.h>
#import <kernserv/prototypes.h>

/* Command Register Commands */
#define CMD_ACK_INTERRUPT       0x3000
#define CMD_ACK_INTERRUPT_LATCH 0x3001

/* Descriptor Status Bits */
#define DESC_STATUS_ERROR       0x40
#define DESC_STATUS_COMPLETE    0x80
#define DESC_LENGTH_MASK        0x1FFF

/* Register Offsets */
#define REG_COMMAND             0x0E
#define REG_TX_STATUS           0x24

@implementation EtherLinkXL(EtherLinkXLKDB)

/*
 * Receive a packet (polling mode for debugger)
 */
- (BOOL)receivePacket:(void *)data length:(unsigned int *)length timeout:(unsigned int)timeout
{
    unsigned int timeoutUsec;
    unsigned int localIndex;
    EtherLinkXLDescriptor *descriptor;
    unsigned short descStatus;
    unsigned int packetLength;
    void *bufferAddr;

    /* Initialize output length */
    *length = 0;

    /* Convert timeout from milliseconds to microseconds */
    timeoutUsec = timeout * 1000;

    /* Only receive if adapter is running */
    if (!isRunning) {
        return NO;
    }

    /* Get current RX descriptor index (masked to ring size) */
    localIndex = rxIndex & 0x3F;

    /* Poll for received packets */
    while (timeoutUsec > 0) {
        descriptor = &rxDescriptors[localIndex];

        /* Check if descriptor is owned by software (bit 7 set in status byte) */
        if ((((unsigned char *)descriptor)[5] & DESC_STATUS_COMPLETE) != 0) {
            /* Get status word at offset +4 */
            descStatus = ((unsigned short *)descriptor)[2];

            /* Check for errors (bit 6) and minimum packet size (> 59 bytes) */
            if (((((unsigned char *)descriptor)[5] & DESC_STATUS_ERROR) == 0) &&
                ((descStatus & DESC_LENGTH_MASK) > 59)) {

                /* Get packet length */
                packetLength = descStatus & DESC_LENGTH_MASK;
                *length = packetLength;

                /* Map the netbuf and copy data */
                bufferAddr = (void *)nb_map(rxNetbufArray[localIndex]);
                bcopy(bufferAddr, data, packetLength);

                /* Clear descriptor status words */
                ((unsigned int *)descriptor)[1] = 0;  /* Clear status at +4 */
                ((unsigned int *)descriptor)[2] = 0;  /* Clear next field at +8 */

                /* Advance RX index */
                rxIndex++;

                /* Acknowledge interrupt */
                outw(ioBase + REG_COMMAND, CMD_ACK_INTERRUPT_LATCH);

                return YES;
            }

            /* Bad packet - clear descriptor and move to next */
            ((unsigned int *)descriptor)[1] = 0;
            ((unsigned int *)descriptor)[2] = 0;
            rxIndex++;
            localIndex = rxIndex & 0x3F;

            /* Acknowledge interrupt */
            outw(ioBase + REG_COMMAND, CMD_ACK_INTERRUPT_LATCH);
        }

        /* Delay 50 microseconds between polls */
        IODelay(50);
        timeoutUsec -= 50;

        /* Acknowledge any pending interrupts */
        outw(ioBase + REG_COMMAND, CMD_ACK_INTERRUPT_LATCH);
    }

    /* Timeout - no packet received */
    return NO;
}

/*
 * Send a packet (polling mode for debugger)
 */
- (void)sendPacket:(void *)data length:(unsigned int)length
{
    int pollCount;
    int txStatus;
    int i;
    EtherLinkXLDescriptor *descriptor;
    EtherLinkXLDescriptor *prevDescriptor;
    void *bufferAddr;
    int originalSize;
    const char *driverName;

    /* Only transmit if adapter is running and TX queue not full */
    if (!isRunning || txHead >= TX_RING_SIZE) {
        return;
    }

    /* If there's a pending transmission, wait for completion */
    if (txPending) {
        /* Poll for TX completion (register ioBase + 0x24) */
        pollCount = 0;
        while (pollCount < 10000) {
            txStatus = inw(ioBase + REG_TX_STATUS);
            if (txStatus == 0) {
                break;
            }
            IODelay(500);
            pollCount++;
        }

        if (pollCount >= 10000) {
            driverName = [[self name] cString];
            IOLog("%s: sendPacket: polling timed out\n", driverName);
            return;
        }

        /* Free any completed TX buffers */
        for (i = 0; i < TX_RING_SIZE; i++) {
            if (txNetbufArray[i] != NULL) {
                nb_free(txNetbufArray[i]);
                txNetbufArray[i] = NULL;
            }
        }

        /* Clear timeout */
        [self clearTimeout];
    }

    /* Get current TX descriptor */
    descriptor = &txDescriptors[txHead];

    /* Free any existing netbuf in this TX slot */
    if (txNetbufArray[txHead] != NULL) {
        nb_free(txNetbufArray[txHead]);
        txNetbufArray[txHead] = NULL;
    }

    /* Copy data to temporary netbuf */
    bufferAddr = (void *)nb_map(txTempNetbuf);
    bcopy(data, bufferAddr, length);

    /* Shrink netbuf to exact packet size */
    originalSize = nb_size(txTempNetbuf);
    nb_shrink_bot(txTempNetbuf, originalSize - length);

    /* Update descriptor from netbuf */
    if (![self __updateDescriptor:descriptor fromNetBuf:txTempNetbuf receive:NO]) {
        driverName = [[self name] cString];
        IOLog("%s: sendPacket: IOUpdateDescriptorFromNetBuf failed\n", driverName);
    } else {
        /* Clear descriptor status */
        descriptor->nextDescriptor = 0;

        /* Clear ownership bit (bit 7 of byte 7) */
        ((unsigned char *)descriptor)[7] &= 0x7F;

        /* If not first descriptor, update previous descriptor's next pointer */
        if (txHead != 0) {
            prevDescriptor = &txDescriptors[txHead - 1];
            prevDescriptor->nextDescriptor = prevDescriptor->reserved[2];  /* Saved physical addr */
            ((unsigned char *)prevDescriptor)[7] &= 0x7F;
        }

        /* Increment TX count */
        txHead++;

        /* Initiate transmission */
        [self __switchQueuesAndTransmitWithTimeout:0];

        /* Poll for completion */
        pollCount = 0;
        while (pollCount < 10000) {
            txStatus = inw(ioBase + REG_TX_STATUS);
            if (txStatus == 0) {
                break;
            }
            IODelay(500);
            pollCount++;
        }

        if (pollCount >= 10000) {
            driverName = [[self name] cString];
            IOLog("%s: sendPacket: polling timed out\n", driverName);
        }

        /* Restore netbuf size */
        nb_grow_bot(txTempNetbuf, originalSize - length);

        /* Clear pending flag */
        txPending = NO;
    }
}

@end
