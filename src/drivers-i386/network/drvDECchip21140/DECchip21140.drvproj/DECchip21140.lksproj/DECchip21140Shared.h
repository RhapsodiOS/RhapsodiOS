#ifndef _DECCHIP21140_SHARED_H_
#define _DECCHIP21140_SHARED_H_

#define DECCHIP21140_RX_RING_SIZE 64
#define DECCHIP21140_TX_RING_SIZE 32

#define DESC_CTRL_SIZE1_MASK 0x000007ff
#define DESC_CTRL_SIZE2_MASK 0x003ff800
#define DESC_CTRL_SIZE2_SHIFT 11
#define DESC_END_OF_RING 0x02000000

typedef struct {
    unsigned int status;
    unsigned int control;
    unsigned int buffer1;
    unsigned int buffer2;
} DECchipDescriptor;

#endif
