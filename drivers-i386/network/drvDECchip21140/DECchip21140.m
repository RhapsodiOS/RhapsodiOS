/*
 * DECchip21140.m
 * Private implementation for DECchip 21140
 */

#import "DECchip21140.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/i386/ioPorts.h>

/* CSR Register definitions */
#define CSR0_SWR    0x00000001  /* Software Reset */
#define CSR6_SR     0x00000002  /* Start Receive */
#define CSR6_ST     0x00002000  /* Start Transmit */
#define CSR6_PR     0x00000040  /* Promiscuous mode */

/* EEPROM definitions */
#define EEPROM_SIZE 128

@implementation DECchip21140NetworkDriver(Private)

- (BOOL)_allocMemory
{
    return [self allocateMemory];
}

- (void)_freeMemory
{
    [self freeMemory];
}

- (BOOL)_initFromDeviceDescription:(IODeviceDescription *)deviceDescription
{
    return YES;
}

- (void)_resetChip
{
    [self writeCSR:0 value:CSR0_SWR];
    IOSleep(10);
}

- (BOOL)_initChip
{
    [self _resetChip];
    [self _initDescriptors];
    [self _mediaInit];
    [self _initMII];
    return YES;
}

- (void)_selectInterface:(int)interface
{
    _mediaType = interface;
}

- (void)_setInterface
{
    [self _setMediaType:_mediaType];
}

- (void)_startTransmit
{
    [self startTransmit];
}

- (void)_startReceive
{
    [self startReceive];
}

- (void)_transmitInterruptOccurred
{
    Descriptor *desc;
    unsigned int status;

    while (_txTail != _txHead) {
        desc = (Descriptor *)_txDescriptors + _txTail;
        status = desc->status;

        /* Check if still owned by chip */
        if (status & TDES0_OWN) {
            break;
        }

        /* Update statistics */
        if (status & TDES0_ES) {
            _txErrors++;
        } else {
            _txPackets++;
        }

        /* Get collision count */
        _collisions += (status & TDES0_CC_MASK) >> 3;

        /* Move to next descriptor */
        _txTail = (_txTail + 1) % _txRingSize;
    }
}

- (void)_receiveInterruptOccurred
{
    Descriptor *desc;
    unsigned int status, length;
    void *buffer;

    while (1) {
        desc = (Descriptor *)_rxDescriptors + _rxHead;
        status = desc->status;

        /* Check if still owned by chip */
        if (status & RDES0_OWN) {
            break;
        }

        /* Check for errors */
        if (status & RDES0_ES) {
            _rxErrors++;
        } else {
            /* Get frame length */
            length = (status & RDES0_FL_MASK) >> 16;
            length -= 4; /* Remove CRC */

            /* Get buffer pointer */
            buffer = (void *)((unsigned int)_receiveBuffers + (_rxHead * RX_BUFFER_SIZE));

            /* Pass packet up to network stack */
            [self _receivePacket:buffer];

            _rxPackets++;
        }

        /* Reset descriptor for reuse */
        desc->status = RDES0_OWN;

        /* Move to next descriptor */
        _rxHead = (_rxHead + 1) % _rxRingSize;
    }

    /* Kick receive poll demand */
    [self writeCSR:CSR2_RX_POLL value:1];
}

- (void)_sendPacket:(void *)packet length:(unsigned int)len
{
    Descriptor *desc;
    void *buffer;

    if (!packet || len == 0 || len > TX_BUFFER_SIZE) {
        return;
    }

    desc = (Descriptor *)_txDescriptors + _txHead;

    /* Wait if descriptor still owned by chip */
    if (desc->status & TDES0_OWN) {
        return;
    }

    /* Copy packet to transmit buffer */
    buffer = (void *)((unsigned int)_transmitBuffers + (_txHead * TX_BUFFER_SIZE));
    bcopy(packet, buffer, len);

    /* Setup descriptor */
    desc->buffer1 = (unsigned int)buffer;
    desc->control = TDES1_LS | TDES1_FS | TDES1_IC | (len & TDES1_TBS1_MASK);
    desc->status = TDES0_OWN;

    /* Move to next descriptor */
    _txHead = (_txHead + 1) % _txRingSize;

    /* Kick transmit poll demand */
    [self writeCSR:CSR1_TX_POLL value:1];
}

- (void)_receivePacket:(void *)packet
{
    /* This would pass the packet up to the network stack */
    /* Implementation depends on IOEthernetDriver interface */
}

- (BOOL)_initDescriptors
{
    return [self initDescriptors];
}

- (void)_setupRxDescriptor:(int)index
{
    [self setupRxDescriptor:index];
}

- (void)_setupTxDescriptor:(int)index
{
    [self setupTxDescriptor:index];
}

- (void)_loadSetupFilter
{
    unsigned short *setup;
    Descriptor *desc;
    int i;

    if (!_setupFrame) {
        return;
    }

    setup = (unsigned short *)_setupFrame;
    bzero(setup, SETUP_FRAME_SIZE);

    /* Create perfect filter for our station address */
    for (i = 0; i < 6; i++) {
        setup[i] = _stationAddress[i] | (_stationAddress[i] << 8);
    }

    /* Broadcast address */
    for (i = 6; i < 12; i++) {
        setup[i] = 0xFFFF;
    }

    /* Use first TX descriptor for setup frame */
    desc = (Descriptor *)_txDescriptors;
    desc->buffer1 = (unsigned int)_setupFrame;
    desc->control = TDES1_SET | TDES1_FS | TDES1_LS | TDES1_IC |
                    (SETUP_FRAME_SIZE & TDES1_TBS1_MASK);
    desc->status = TDES0_OWN;

    /* Kick transmit poll */
    [self writeCSR:CSR1_TX_POLL value:1];

    /* Wait for completion */
    for (i = 0; i < 1000; i++) {
        if (!(desc->status & TDES0_OWN)) {
            break;
        }
        IODelay(10);
    }
}

- (void)_updateDescriptorFromNetbuf:(void *)descriptor
{
    /* Update descriptor from network buffer */
}

- (void)_allocateNetbuf
{
    /* Allocate network buffer */
}

- (void)_getStatistics
{
    [self updateStats];
}

- (void)_resetStats
{
    [self resetStats];
}

- (IOReturn)_getPowerState
{
    return [self getPowerState];
}

- (IOReturn)_setPowerState:(unsigned int)state
{
    return [self setPowerState:state];
}

- (void)_setPowerManagement
{
    /* Setup power management */
}

- (void)_mediaInit
{
    /* Initialize media detection */
    _mediaType = 0;  /* 10BASE-T */
    _linkUp = NO;
    _fullDuplex = NO;
}

- (void)_mediaDetect
{
    /* Detect media type */
}

- (void)_mediaAutoSense
{
    /* Auto-sense media */
}

- (void)_setMediaType:(unsigned int)mediaType
{
    _mediaType = mediaType;
}

- (void)_getDriverName:(char *)name
{
    if (name) {
        strcpy(name, "DECchip21140NetworkDriver");
    }
}

- (void)_verifyChecksum
{
    /* Verify EEPROM checksum */
}

- (void)_writeHi:(unsigned int)value
{
    /* Write high value to register */
}

- (unsigned short)_readEEPROM:(int)offset
{
    /* Read from EEPROM */
    if (offset < 0 || offset >= EEPROM_SIZE) {
        return 0;
    }

    unsigned int value = 0;
    int i;

    /* Read EEPROM using CSR9 */
    [self writeCSR:9 value:0x4800 | (offset & 0xFF)];

    /* Wait for read to complete */
    for (i = 0; i < 1000; i++) {
        value = [self readCSR:9];
        if (value & 0x80000000) {
            break;
        }
        IODelay(10);
    }

    return (unsigned short)((value >> 16) & 0xFFFF);
}

- (void)_writeEEPROM:(int)offset value:(unsigned short)value
{
    /* Write to EEPROM */
    if (offset < 0 || offset >= EEPROM_SIZE) {
        return;
    }

    /* Write EEPROM using CSR9 */
    [self writeCSR:9 value:0x5000 | (offset & 0xFF) | ((value & 0xFFFF) << 16)];
    IODelay(1000);
}

- (unsigned int)_readCSR:(int)csr
{
    return [self readCSR:csr];
}

- (void)_writeCSR:(int)csr value:(unsigned int)value
{
    [self writeCSR:csr value:value];
}

- (void)_handleTransmit
{
    unsigned int txIndex = _txTail;
    unsigned int *desc;

    while (txIndex != _txHead) {
        desc = (unsigned int *)((char *)_txDescriptors + (txIndex * 16));

        /* Check if descriptor processed */
        if (desc[0] & 0x80000000) {
            break;  /* Still owned by chip */
        }

        /* Check for errors */
        if (desc[0] & 0x00008000) {
            _txErrors++;
        }

        /* Update tail */
        _txTail = (txIndex + 1) % _txRingSize;
        txIndex = _txTail;
    }
}

- (void)_handleReceive
{
    [self receivePacket];
}

- (void)_handleLinkChange
{
    /* Handle link status change */
}

- (void)_setAddressFiltering
{
    [self _loadSetupFilter];
}

- (void)_getStationAddress:(unsigned char *)addr
{
    if (addr) {
        bcopy(_stationAddress, addr, 6);
    }
}

- (unsigned int)_readMII:(int)phyAddr reg:(int)regAddr
{
    unsigned int value;
    int i;

    /* MII management frame */
    unsigned int frame = 0x60020000 | ((phyAddr & 0x1F) << 23) | ((regAddr & 0x1F) << 18);

    [self writeCSR:9 value:frame];

    /* Wait for read to complete */
    for (i = 0; i < 1000; i++) {
        value = [self readCSR:9];
        if (!(value & 0x80000000)) {
            break;
        }
        IODelay(10);
    }

    return (value >> 16) & 0xFFFF;
}

- (void)_writeMII:(int)phyAddr reg:(int)regAddr value:(unsigned int)value
{
    /* MII management frame */
    unsigned int frame = 0x50020000 | ((phyAddr & 0x1F) << 23) |
                        ((regAddr & 0x1F) << 18) | (value & 0xFFFF);

    [self writeCSR:9 value:frame];
    IODelay(10);
}

- (void)_initMII
{
    /* Initialize MII interface */
    _phyInit;
}

- (void)_phyInit
{
    /* Initialize PHY */
    [self _phyAutoNegotiate];
}

- (void)_phyAutoNegotiate
{
    /* Start PHY auto-negotiation */
    [self _writeMII:1 reg:0 value:0x1200];  /* Enable auto-negotiation */
}

- (void)_phyControl
{
    /* PHY control */
}

- (void)_phyReadRegister:(int)reg value:(unsigned int *)value
{
    if (value) {
        *value = [self _readMII:1 reg:reg];
    }
}

- (void)_phyWriteRegister:(int)reg value:(unsigned int)value
{
    [self _writeMII:1 reg:reg value:value];
}

- (void)_getPhyCapabilities
{
    /* Get PHY capabilities from register 1 */
    unsigned int status = [self _readMII:1 reg:1];

    if (status & 0x0004) {
        _linkUp = YES;
    } else {
        _linkUp = NO;
    }
}

- (void)_setConnectionType:(unsigned int)type
{
    _mediaType = type;
}

- (unsigned int)_getConnectionType
{
    return _mediaType;
}

- (void)_initPortRegisterForToken:(unsigned int)token
{
    /* Initialize port register */
}

- (unsigned int)_readPortRegisterForFunction:(unsigned int)function
{
    /* Read port register */
    return 0;
}

- (void)_getNextValueFromString:(const char *)string value:(unsigned int *)value
{
    if (!string || !value) {
        return;
    }

    *value = 0;
}

- (void)_delay_IODelay:(unsigned int)delay
{
    IODelay(delay);
}

- (void)_threeStateControl
{
    /* Three-state control */
}

- (void)_adminControl
{
    /* Admin control */
}

- (void)_adminStatus
{
    /* Admin status */
}

- (void)_phyGetCapabilities
{
    [self _getPhyCapabilities];
}

- (void)_phyWaySetLocalAbility
{
    /* Set local PHY ability */
}

- (void)_connectToControl
{
    /* Connect to control */
}

- (void)_connectValidateCheckConnection
{
    /* Validate connection */
}

- (void)_mediaSense
{
    [self _mediaDetect];
}

- (void)_timeoutOccurred
{
    [self timeoutOccurred];
}

- (void)_scheduleFunc_sendPacket
{
    /* Schedule send packet function */
}

- (void)_freeResources
{
    [self _freeMemory];
}

- (void)_domainControl
{
    /* Domain control */
}

- (void)_adminGenSetConnection
{
    /* Admin gen set connection */
}

- (void)_adminThreeState
{
    /* Admin three state */
}

- (void)_verifyChecksum_writeChecksum
{
    /* Verify and write checksum */
}

- (void)_getDriverName_mediaSupported
{
    /* Get driver name and media supported */
}

@end
