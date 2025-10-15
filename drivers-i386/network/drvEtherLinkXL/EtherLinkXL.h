/*
 * Copyright (c) 1998 3Com Corporation. All rights reserved.
 *
 * EtherLink XL 3C90X Ethernet Driver
 */

#import <driverkit/IOEthernetController.h>
#import <driverkit/i386/IOPCIDevice.h>
#import <driverkit/i386/IOPCIDeviceDescription.h>

@class EtherLinkXLMII;

@interface EtherLinkXL : IOEthernetController
{
    IOPCIDevice *pciDevice;
    EtherLinkXLMII *miiDevice;

    /* Hardware registers */
    void *ioBase;
    unsigned int ioBasePhys;

    /* Device state */
    BOOL isFullDuplex;
    BOOL isRunning;
    BOOL transmitEnabled;
    BOOL receiveEnabled;

    /* Statistics */
    unsigned int txPackets;
    unsigned int rxPackets;
    unsigned int txErrors;
    unsigned int rxErrors;

    /* Buffer management */
    void *transmitBuffer;
    void *receiveBuffer;
    unsigned int transmitBufferSize;
    unsigned int receiveBufferSize;

    /* Interrupt handling */
    unsigned int interruptLevel;
    unsigned int interruptOccurred;

    /* Network configuration */
    unsigned char ethernetAddress[6];
    unsigned int mediaType;
    unsigned int linkStatus;

    /* Power management */
    unsigned int powerState;
}

/* Initialization */
+ (BOOL)probe:(IOPCIDevice *)device;
- initFromDeviceDescription:(IOPCIDeviceDescription *)deviceDescription;
- free;

/* Device control */
- (BOOL)resetAndEnable:(BOOL)enable;
- (void)enableAdapter;
- (void)disableAdapter;
- (void)setRunning:(BOOL)running;

/* Hardware access */
- (unsigned int)readRegister:(unsigned int)offset;
- (void)writeRegister:(unsigned int)offset value:(unsigned int)value;
- (void)selectWindow:(int)window;

/* Network interface */
- (void)transmitPacket:(netbuf_t)packet;
- (void)receivePacket;
- (void)handleInterrupt;

/* Configuration */
- (void)setEthernetAddress:(unsigned char *)addr;
- (void)getEthernetAddress:(unsigned char *)addr;
- (void)setFullDuplex:(BOOL)fullDuplex;
- (void)setMediaType:(unsigned int)media;

/* Statistics */
- (void)updateStatistics;
- (unsigned int)getTxPackets;
- (unsigned int)getRxPackets;

/* MII interface */
- (unsigned int)miiReadBit;
- (void)miiWriteBit:(unsigned int)bit;
- (void)miiInit;

/* Power management */
- (void)setPowerState:(unsigned int)state;
- (unsigned int)getPowerState;

@end

/* Register definitions */
#define ELINK_COMMAND           0x0E
#define ELINK_STATUS            0x0E
#define ELINK_WINDOW            0x0F
#define ELINK_TX_STATUS         0x1B
#define ELINK_INT_STATUS        0x18

/* Command codes */
#define CMD_GLOBAL_RESET        0x00
#define CMD_SELECT_WINDOW       0x01
#define CMD_START_TX            0x02
#define CMD_RX_ENABLE           0x04
#define CMD_RX_DISABLE          0x05
#define CMD_TX_ENABLE           0x09
#define CMD_TX_DISABLE          0x0A
#define CMD_REQ_INTR            0x0B
#define CMD_ACK_INTR            0x0D
#define CMD_SET_INTR_ENABLE     0x0E
#define CMD_SET_RX_FILTER       0x0F

/* Interrupt bits */
#define INT_LATCH               0x0001
#define INT_HOST_ERROR          0x0002
#define INT_TX_COMPLETE         0x0004
#define INT_RX_COMPLETE         0x0010
#define INT_RX_EARLY            0x0020
#define INT_UPDATE_STATS        0x0080
#define INT_LINK_EVENT          0x0100
#define INT_DN_COMPLETE         0x0200
#define INT_UP_COMPLETE         0x0400

/* Window definitions */
#define WINDOW_0                0
#define WINDOW_1                1
#define WINDOW_2                2
#define WINDOW_3                3
#define WINDOW_4                4
#define WINDOW_5                5
#define WINDOW_6                6
#define WINDOW_7                7
