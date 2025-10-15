/*
 * DECchip21140.h
 * Private implementation class for DECchip 21140
 */

#import "DECchip21140NetworkDriver.h"

/* Private category - internal implementation */
@interface DECchip21140NetworkDriver(Private)

/* Private initialization */
- (BOOL)_allocMemory;
- (void)_freeMemory;
- (BOOL)_initFromDeviceDescription:(IODeviceDescription *)deviceDescription;

/* Private chip operations */
- (void)_resetChip;
- (BOOL)_initChip;
- (void)_selectInterface:(int)interface;
- (void)_setInterface;

/* Private transmit/receive */
- (void)_startTransmit;
- (void)_startReceive;
- (void)_transmitInterruptOccurred;
- (void)_receiveInterruptOccurred;
- (void)_sendPacket:(void *)packet length:(unsigned int)len;
- (void)_receivePacket:(void *)packet;

/* Private descriptor operations */
- (BOOL)_initDescriptors;
- (void)_setupRxDescriptor:(int)index;
- (void)_setupTxDescriptor:(int)index;

/* Private setup frame */
- (void)_loadSetupFilter;
- (void)_updateDescriptorFromNetbuf:(void *)descriptor;
- (void)_allocateNetbuf;

/* Private statistics */
- (void)_getStatistics;
- (void)_resetStats;

/* Private power management */
- (IOReturn)_getPowerState;
- (IOReturn)_setPowerState:(unsigned int)state;
- (void)_setPowerManagement;

/* Private media handling */
- (void)_mediaInit;
- (void)_mediaDetect;
- (void)_mediaAutoSense;
- (void)_setMediaType:(unsigned int)mediaType;
- (void)_getDriverName:(char *)name;
- (void)_verifyChecksum;
- (void)_writeHi:(unsigned int)value;

/* Private EEPROM access */
- (unsigned short)_readEEPROM:(int)offset;
- (void)_writeEEPROM:(int)offset value:(unsigned short)value;

/* Private register operations */
- (unsigned int)_readCSR:(int)csr;
- (void)_writeCSR:(int)csr value:(unsigned int)value;

/* Private interrupt handling */
- (void)_handleTransmit;
- (void)_handleReceive;
- (void)_handleLinkChange;

/* Private filtering */
- (void)_setAddressFiltering;
- (void)_getStationAddress:(unsigned char *)addr;
- (void)_loadSetupFilter;

/* Private MII operations */
- (unsigned int)_readMII:(int)phyAddr reg:(int)regAddr;
- (void)_writeMII:(int)phyAddr reg:(int)regAddr value:(unsigned int)value;
- (void)_initMII;

/* Private phy operations */
- (void)_phyInit;
- (void)_phyAutoNegotiate;
- (void)_phyControl;
- (void)_phyReadRegister:(int)reg value:(unsigned int *)value;
- (void)_phyWriteRegister:(int)reg value:(unsigned int)value;
- (void)_getPhyCapabilities;

/* Private connection type handling */
- (void)_setConnectionType:(unsigned int)type;
- (unsigned int)_getConnectionType;

/* Private port register operations */
- (void)_initPortRegisterForToken:(unsigned int)token;
- (unsigned int)_readPortRegisterForFunction:(unsigned int)function;

/* Private vendor specific operations */
- (void)_getNextValueFromString:(const char *)string value:(unsigned int *)value;

/* Private delay operations */
- (void)_delay_IODelay:(unsigned int)delay;

/* Private three-state control */
- (void)_threeStateControl;

/* Private admin control */
- (void)_adminControl;
- (void)_adminStatus;

/* Private phy capabilities */
- (void)_phyGetCapabilities;
- (void)_phyWaySetLocalAbility;

/* Private connection handling */
- (void)_connectToControl;
- (void)_connectValidateCheckConnection;

/* Private media sense */
- (void)_mediaSense;

/* Private timeout handling */
- (void)_timeoutOccurred;

/* Private allocation */
- (void)_allocateNetbuf;

/* Private schedule functions */
- (void)_scheduleFunc_sendPacket;

/* Private free resources */
- (void)_freeResources;

/* Private domain control */
- (void)_domainControl;

/* Private admin operations */
- (void)_adminGenSetConnection;
- (void)_adminThreeState;

/* Private phy way set */
- (void)_phyWaySetLocalAbility;

/* Private read register */
- (void)_phyReadRegister:(int)reg;

/* Private write checksum */
- (void)_verifyChecksum_writeChecksum;

/* Private get driver name */
- (void)_getDriverName_mediaSupported;

@end
