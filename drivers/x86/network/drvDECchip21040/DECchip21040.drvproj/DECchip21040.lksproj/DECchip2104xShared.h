/*
 * DECchip2104xShared.h
 * Shared definitions for DEC 21040/21041 driver
 */

#ifndef _DECCHIP2104XSHARED_H
#define _DECCHIP2104XSHARED_H

#include <driverkit/IONetworkDeviceDescription.h>

/* Descriptor structure for DMA */
typedef struct _DECchipDescriptor {
    unsigned int status;        /* Status and control bits */
    unsigned int control;       /* Control and buffer sizes */
    unsigned int buffer1;       /* Physical address of buffer 1 */
    unsigned int buffer2;       /* Physical address of buffer 2 */
} DECchipDescriptor;

/* Descriptor control bits */
#define DESC_CTRL_SIZE1_MASK    0x000007FF  /* Buffer 1 size mask */
#define DESC_CTRL_SIZE2_MASK    0x003FF800  /* Buffer 2 size mask */
#define DESC_CTRL_SIZE2_SHIFT   11

/* Constants */
#define DECCHIP_SETUP_FRAME_SIZE    0x5F0   /* Setup frame size */
#define DECCHIP_MAX_PACKET_SIZE     1518    /* Maximum Ethernet packet */

/* Ring sizes */
#define DECCHIP_TX_RING_SIZE        16      /* Number of TX descriptors */
#define DECCHIP_RX_RING_SIZE        32      /* Number of RX descriptors */

#endif /* _DECCHIP2104XSHARED_H */
