/*
 * Copyright (c) 1994-1996 NeXT Software, Inc.  All rights reserved.
 * Copyright (c) 2025 RhapsodiOS Project. All rights reserved.
 *
 * HISTORY
 * 10-Nov-25   Created for ESS ES1x88 AudioDrive support
 *             Based on SoundBlaster16 driver
 */

/*
 * Base address - determined at runtime
 */
static unsigned int sbBaseRegisterAddress = 0;

/*
 * DSP Register addresses - determined at runtime
 */
static unsigned int sbResetReg = 0;
static unsigned int sbReadDataReg = 0;
static unsigned int sbWriteDataOrCommandReg = 0;
static unsigned int sbWriteBufferStatusReg = 0;
static unsigned int sbDataAvailableStatusReg = 0;
static unsigned int sbAck8bitInterrupt = 0;
static unsigned int sbAck16bitInterrupt = 0;

static __inline__
void
assignDSPRegAddresses(void)
{
    sbResetReg =
        (sbBaseRegisterAddress + SB16_DSP_RESET_OFFSET);
    sbReadDataReg =
        (sbBaseRegisterAddress + SB16_DSP_READ_DATA_OFFSET);
    sbWriteDataOrCommandReg =
        (sbBaseRegisterAddress + SB16_DSP_WRITE_DATA_OR_COMMAND_OFFSET);
    sbWriteBufferStatusReg =
        (sbBaseRegisterAddress + SB16_DSP_WRITE_BUFFER_STATUS_OFFSET);
    sbDataAvailableStatusReg =
        (sbBaseRegisterAddress + SB16_DSP_DATA_AVAILABLE_STATUS_OFFSET);
    sbAck8bitInterrupt =
        (sbBaseRegisterAddress + SB16_DSP_DATA_AVAILABLE_STATUS_OFFSET);
    sbAck16bitInterrupt =
        (sbBaseRegisterAddress + SB16_DSP_16BIT_ACK_OFFSET);
}

/*
 * Mixer register addresses
 */
static unsigned int sbMixerAddressReg = 0;
static unsigned int sbMixerDataReg = 0;

static __inline__
void
assignMixerRegAddresses(void)
{
    sbMixerAddressReg =
        (sbBaseRegisterAddress + SB16_MIXER_ADDRESS_OFFSET);
    sbMixerDataReg =
        (sbBaseRegisterAddress + SB16_MIXER_DATA_OFFSET);
}

/*
 * Shadow registers for mixer settings
 */
static sb16MonoMixerRegister_t volMaster =      {0};
static sb16MonoMixerRegister_t volFM =          {0};
static sb16MonoMixerRegister_t volCD =          {0};
static sb16MonoMixerRegister_t volLine =        {0};
static unsigned char volMic =                   0;

/*
 * Last stage (output) gain controls (0-3)
 */
static unsigned char lastStageGainInputLeft =   0;
static unsigned char lastStageGainInputRight =  0;
static unsigned char lastStageGainOutputLeft =  0;
static unsigned char lastStageGainOutputRight = 0;

/*
 * ES1x88 hardware detection
 */
static unsigned int essHardware =               0;
static unsigned char essChipRevision =          0;

/*
 * ES1x88 record source
 */
static unsigned char sbRecordSource =           0;

/*
 * ES1x88 voice volume alias
 */
static unsigned char volVoc =                   0;

/*
 * Buffer counter and DMA command variables
 */
static unsigned int sbBufferCounter =           0;
static unsigned char sbStartDMACommand =        0;
static unsigned char sbStartDMAMode =           0;

/*
 * Write to mixer register
 */
static  __inline__
void
outbIXMixer(unsigned int address, unsigned int val)
{
    outb(sbMixerAddressReg, address);
    IODelay(SB16_ADDRESS_WRITE_DELAY);
    outb(sbMixerDataReg, val);
    IODelay(SB16_DATA_WRITE_DELAY);
}

/*
 * Wait for DSP data available (with timeout)
 * Returns 1 if data available, 0 on timeout
 */
static __inline__
int
waitForDSPDataAvailable(void)
{
    int timeout = 0;
    char status;

    while (timeout < 2000) {
        IODelay(10);
        status = inb(sbDataAvailableStatusReg);
        if (status < 0) {  /* Bit 7 set means data available */
            return 1;
        }
        timeout++;
    }

    /* Timeout - try reset */
    outb(sbResetReg, 1);
    IODelay(10);
    outb(sbResetReg, 0);
    IODelay(100);
    outb(sbWriteDataOrCommandReg, ES_CMD_EXTENDED_ID);
    return 0;
}

/*
 * Wait for DSP write buffer ready (with timeout)
 * Returns 1 if ready, 0 on timeout
 */
static __inline__
int
waitForDSPWriteReady(void)
{
    int timeout = 0;
    char status;

    while (timeout < 2000) {
        IODelay(10);
        status = inb(sbWriteBufferStatusReg);
        if (status >= 0) {  /* Bit 7 clear means buffer ready */
            return 1;
        }
        timeout++;
    }

    /* Timeout - try reset */
    outb(sbResetReg, 1);
    IODelay(10);
    outb(sbResetReg, 0);
    IODelay(100);
    outb(sbWriteDataOrCommandReg, ES_CMD_EXTENDED_ID);
    return 0;
}

/*
 * Clear and acknowledge interrupts
 * For ES1x88, reading the data available status register clears the interrupt
 */
static __inline__
unsigned char
clearInterrupts(void)
{
    unsigned char status;

    status = inb(sbDataAvailableStatusReg);
    return status;
}

/*
 * Program the DMA Select register (0x81) with the active DMA channels
 */
static __inline__
void
programDMASelect(unsigned int dma8Channel, unsigned int dma16Channel)
{
    unsigned char dmaSelectBits = 0;

    /* Set 8-bit DMA channel bit */
    if (dma8Channel == 0) {
        dmaSelectBits = 0x01;
    } else if (dma8Channel == 1) {
        dmaSelectBits = 0x02;
    } else if (dma8Channel == 3) {
        dmaSelectBits = 0x08;
    }

    /* Set 16-bit DMA channel bit */
    if (dma16Channel == 5) {
        dmaSelectBits |= 0x20;
    } else if (dma16Channel == 6) {
        dmaSelectBits |= 0x40;
    } else if (dma16Channel == 7) {
        dmaSelectBits |= 0x80;
    }

    /* Write to mixer DMA select register */
    outbIXMixer(MC16_DMA_SELECT, dmaSelectBits);
}
