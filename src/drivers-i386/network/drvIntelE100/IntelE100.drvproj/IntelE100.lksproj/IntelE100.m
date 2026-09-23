/*
 * IntelE100.m - Intel 8255x (e100) 10/100 ethernet driver for RhapsodiOS
 * i386.
 *
 * Copyright (c) 2026, Pat Raynor. BSD-2-Clause; see LICENSE.
 *
 * IDENTIFICATION-ONLY BUILD: this finds the part, reads its EEPROM and
 * PHY, logs them, and declines to attach. The full driver replaces this
 * file.
 */

#import <driverkit/IODevice.h>
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>
#import <driverkit/i386/directDevice.h>
#import <driverkit/i386/IOPCIDirectDevice.h>
#import <driverkit/IODeviceDescription.h>
#import <driverkit/IOEthernet.h>

#import "E100Regs.h"
#import "E100Logic.h"
#import "E100Hw.h"
#import "E100Port.h"

#define E100_VENDOR     0x8086

@interface IntelE100 : IOEthernet
{
    unsigned short      ioBase;
    const E100Chip     *chip;
    int                 revision;
    unsigned int        quirks;
    int                 irqCount;
    int                 phyAddr;
    unsigned short      phyId1, phyId2;
}
+ (BOOL)probe:(IODeviceDescription *)devDesc;
- initFromDeviceDescription:(IODeviceDescription *)devDesc;
- (void)_findPhy:(unsigned short)phyWord;
@end

@implementation IntelE100

+ (BOOL)probe:(IODeviceDescription *)devDesc
{
    IntelE100 *dev = [self alloc];

    if (dev == nil)
        return NO;
    return [dev initFromDeviceDescription:devDesc] != nil;
}

- initFromDeviceDescription:(IODeviceDescription *)devDesc
{
    IOPCIConfigSpace    config;
    unsigned long       command;
    unsigned short      ee[E100_EEPROM_WORDS_KEPT];
    unsigned short      sum, word;
    unsigned char       mac[6];
    int                 eeBits, words, i;

    if ([super initFromDeviceDescription:devDesc] == nil)
        return nil;

    if ([IODirectDevice getPCIConfigSpace:&config
                    withDeviceDescription:devDesc] != IO_R_SUCCESS) {
        IOLog("IntelE100: cannot read PCI configuration space\n");
        [self free];
        return nil;
    }
    if (config.VendorID != E100_VENDOR) {
        IOLog("IntelE100: vendor %04x is not Intel\n",
              (unsigned int)config.VendorID);
        [self free];
        return nil;
    }
    chip = e100ChipLookup(config.DeviceID, (unsigned char)config.RevisionID);
    if (chip == 0) {
        IOLog("IntelE100: device %04x is not an 8255x this driver knows\n",
              (unsigned int)config.DeviceID);
        [self free];
        return nil;
    }

    /*
     * The CSRs are decoded through the I/O BAR as well as the memory BAR,
     * and port I/O needs no mapping. Scan for it rather than assume BAR1.
     */
    ioBase = 0;
    for (i = 0; i < 6; i++) {
        unsigned long bar = config.BaseAddress[i];

        if ((bar & 1UL) && (bar & 0xFFFFFFFCUL) != 0UL
            && (bar & 0xFFFFFFFCUL) <= 0xFFFFUL) {
            ioBase = (unsigned short)(bar & 0xFFFCUL);
            break;
        }
    }
    if (ioBase == 0) {
        IOLog("IntelE100: %s has no I/O BAR assigned\n", chip->name);
        [self free];
        return nil;
    }

    /* I/O decoding and bus mastering. The status half of the dword goes
     * back as zero, which leaves its write-one-to-clear bits alone. */
    if ([IODirectDevice getPCIConfigData:&command atRegister:0x04
                   withDeviceDescription:devDesc] == IO_R_SUCCESS
        && (command & 0x0005UL) != 0x0005UL) {
        [IODirectDevice setPCIConfigData:((command & 0xFFFFUL) | 0x0005UL)
                              atRegister:0x04 withDeviceDescription:devDesc];
        IOLog("IntelE100: turned on I/O decoding and bus mastering"
              " (command was %04x)\n", (unsigned int)(command & 0xFFFFUL));
    }

    /* A warm boot leaves the chip as the last driver left it (SDM 8.1.1).
     * Both PORT commands clear the SCB M bit, so mask again at once. */
    e100PortCommand(ioBase, E100_PORT_SELECTIVE_RESET);
    e100PortCommand(ioBase, E100_PORT_SOFTWARE_RESET);
    E100_OUTB(ioBase + E100_SCB_INTR, E100_INTR_MASK_ALL);

    eeBits = e100EepromAddressBits(ioBase);
    if (eeBits < 6 || eeBits > 8) {
        IOLog("IntelE100: EEPROM did not answer (address width %d)\n", eeBits);
        [self free];
        return nil;
    }
    words = 1 << eeBits;
    sum = 0;
    for (i = 0; i < words; i++) {
        word = e100EepromRead(ioBase, eeBits, i);
        sum = (unsigned short)(sum + word);
        if (i < E100_EEPROM_WORDS_KEPT)
            ee[i] = word;
    }
    e100MacFromEeprom(ee, mac);
    if (!e100MacValid(mac)) {
        IOLog("IntelE100: EEPROM holds %02x:%02x:%02x:%02x:%02x:%02x,"
              " which is not a station address\n",
              mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
        [self free];
        return nil;
    }

    revision = e100EffectiveRevision(chip, (unsigned char)config.RevisionID, ee);
    quirks = e100Quirks(chip, revision, ee);
    irqCount = [devDesc numInterrupts];

    /* "0 irq" is the signature of a missing "IRQ Levels" key in the
     * instance table (drvIntel1000's README-Instance0.md). */
    IOLog("IntelE100: %s [8086:%04x rev %02x] %s generation, I/O 0x%04x,"
          " config IRQ %d, %d irq\n",
          chip->name, (unsigned int)config.DeviceID,
          (unsigned int)config.RevisionID, e100GenerationName(revision),
          (unsigned int)ioBase, (int)config.InterruptLine, irqCount);
    IOLog("IntelE100: MAC %02x:%02x:%02x:%02x:%02x:%02x, EEPROM %d words,"
          " checksum %s\n",
          mac[0], mac[1], mac[2], mac[3], mac[4], mac[5], words,
          (sum == E100_EEPROM_SUM) ? "OK" : "BAD - continuing");
    if (quirks & E100_Q_RXBUG)
        IOLog("IntelE100: EEPROM word 3 does not mark the receive lockup"
              " fixed - watching for it\n");
    if (quirks & E100_Q_CU_RESUME)
        IOLog("IntelE100: EEPROM enables Dynamic Standby (82801BA erratum 30)"
              " - a CU NOP precedes every resume; the EEPROM is left alone\n");
    if (revision >= E100_REV_82550)
        IOLog("IntelE100: %s runs in simplified mode here, which no reference"
              " driver exercises on this part\n", chip->name);

    [self _findPhy:ee[E100_EEPROM_PHY]];

    IOLog("IntelE100: identification-only build - not attaching\n");
    [self free];
    return nil;
}

/*
 * The MII address from EEPROM word 6 first (SDM 7.1), then every other
 * address, taking the first whose PHYID1 is neither 0 nor all ones.
 */
- (void)_findPhy:(unsigned short)phyWord
{
    int want = phyWord & E100_PHY_ADDR_MASK;
    int i, addr, id1;

    phyAddr = -1;
    if (quirks & E100_Q_SERIAL) {
        IOLog("IntelE100: 82503 serial interface - no MII PHY\n");
        return;
    }
    for (i = -1; i < 32; i++) {
        addr = (i < 0) ? want : i;
        if (i == want)
            continue;
        id1 = e100MdiRead(ioBase, addr, MII_PHYID1);
        if (id1 > 0 && id1 != 0xFFFF) {
            phyAddr = addr;
            phyId1 = (unsigned short)id1;
            phyId2 = (unsigned short)(e100MdiRead(ioBase, addr, MII_PHYID2)
                                      & 0xFFFF);
            IOLog("IntelE100: PHY at MII address %d%s, ID %04x:%04x\n",
                  addr, (i < 0) ? "" : " (found by scanning; the EEPROM"
                  " names another)", (unsigned int)phyId1,
                  (unsigned int)phyId2);
            /* Autonegotiate once, here. Restarting it on every
             * -resetAndEnable: would drop the link at each filter change. */
            (void)e100MdiWrite(ioBase, addr, MII_BMCR,
                               BMCR_AUTONEG | BMCR_RESTART_AUTONEG);
            return;
        }
    }
    IOLog("IntelE100: no MII PHY answered - link will be reported as up\n");
}

@end
