/*
 * IdeVIA.m - VIA VT82C5xx/686A chipset back-end.
 */
#import "IdeCnt.h"
#import "IdeVIA.h"
#import "IdeBMIDE.h"
#import <driverkit/KernBus.h>
#import <driverkit/i386/IOPCIDeviceDescription.h>
#import <driverkit/i386/IOPCIDirectDevice.h>
#import <driverkit/generalFuncs.h>
#import <string.h>

@interface Object(VIAPCIRegisterAccess)
- (IOReturn)getRegister:(unsigned char)address
	device:(unsigned char)device
	function:(unsigned char)function
	bus:(unsigned char)bus
	data:(unsigned long *)data;
@end

static BOOL viaMatch(id deviceDescription, unsigned long pciID,
	unsigned char progIf, ideChipCaps_t *out)
{
	unsigned char dev;
	unsigned char fun;
	unsigned char bus;
	unsigned long bridge;
	unsigned long classRev;
	const viaChipInfo_t *chip;
	id pci;
	IOReturn rtn;

	rtn = [deviceDescription getPCIdevice:&dev function:&fun bus:&bus];
	if (rtn != IO_R_SUCCESS || fun != 1)
		return NO;
	pci = [KernBus lookupBusInstanceWithName:"PCI" busId:0];
	if (pci == nil)
		return NO;
	rtn = [pci getRegister:0x00 device:dev function:0 bus:bus data:&bridge];
	if (rtn != IO_R_SUCCESS)
		return NO;
	rtn = [pci getRegister:0x08 device:dev function:0 bus:bus data:&classRev];
	if (rtn != IO_R_SUCCESS)
		return NO;
	chip = VIAFindChip(pciID, bridge, (unsigned char)(classRev & 0xff));
	if (chip == NULL)
		return NO;
	out->maxPIO = chip->maxPIO;
	out->maxMWDMA = chip->maxMWDMA;
	out->maxUDMA = chip->maxUDMA;
	out->flags = (progIf & PCI_IDE_BUSMASTER) ? CHIP_FLAG_BUSMASTER : 0;
	out->privateData = (unsigned int)chip->chip;
	return YES;
}

static void viaSetTiming(id self, void *drives)
{
	[self VIASetTiming:drives];
}

static void viaResetTiming(id self)
{
	[self VIAResetTiming];
}

static BOOL viaDetectCable(id self)
{
	return [self VIADetectCable];
}

const ideChipsetOps_t ideVIAOps = {
	"VIA VT82C5xx/686A",
	viaMatch,
	viaSetTiming,
	viaResetTiming,
	viaDetectCable
};

@implementation IdeController(VIA)

- (BOOL) VIAChannel:(unsigned char *)channel
{
	switch (_ideChannel) {
		case PCI_CHANNEL_PRIMARY:
			*channel = VIA_CHANNEL_PRIMARY;
			return YES;
		case PCI_CHANNEL_SECONDARY:
			*channel = VIA_CHANNEL_SECONDARY;
			return YES;
		default:
			return NO;
	}
}

- (BOOL) VIAReadConfig:(viaConfig_t *)config
{
	unsigned int index;
	unsigned int offset;
	unsigned long data;
	IOReturn rtn;

	for (offset = VIA_CONFIG_BASE; offset < VIA_CONFIG_BASE + VIA_CONFIG_SIZE;
	     offset += 4) {
		rtn = [[self class] getPCIConfigData:&data
			atRegister:(unsigned char)offset
			withDeviceDescription:[self deviceDescription]];
		if (rtn != IO_R_SUCCESS)
			return NO;
		index = offset - VIA_CONFIG_BASE;
		config->bytes[index] = (unsigned char)(data & 0xff);
		config->bytes[index + 1] = (unsigned char)((data >> 8) & 0xff);
		config->bytes[index + 2] = (unsigned char)((data >> 16) & 0xff);
		config->bytes[index + 3] = (unsigned char)((data >> 24) & 0xff);
	}
	return YES;
}

- (BOOL) VIAWriteConfigFrom:(const viaConfig_t *)before
	to:(const viaConfig_t *)after
{
	unsigned int index;
	unsigned int offset;
	unsigned long beforeData;
	unsigned long afterData;
	IOReturn rtn;
	BOOL success;

	success = YES;
	for (offset = VIA_CONFIG_BASE; offset < VIA_CONFIG_BASE + VIA_CONFIG_SIZE;
	     offset += 4) {
		index = offset - VIA_CONFIG_BASE;
		beforeData = (unsigned long)before->bytes[index] |
			((unsigned long)before->bytes[index + 1] << 8) |
			((unsigned long)before->bytes[index + 2] << 16) |
			((unsigned long)before->bytes[index + 3] << 24);
		afterData = (unsigned long)after->bytes[index] |
			((unsigned long)after->bytes[index + 1] << 8) |
			((unsigned long)after->bytes[index + 2] << 16) |
			((unsigned long)after->bytes[index + 3] << 24);
		if (beforeData == afterData)
			continue;
		rtn = [[self class] setPCIConfigData:afterData
			atRegister:(unsigned char)offset
			withDeviceDescription:[self deviceDescription]];
		if (rtn != IO_R_SUCCESS) {
			IOLog("%s: VIA PCI config write failed at 0x%02x\n",
				[self name], offset);
			success = NO;
		}
	}
	return success;
}

- (BOOL) VIASetTiming:(void *)drives
{
	driveInfo_t *drv;
	viaConfig_t before;
	viaConfig_t after;
	viaDriveTiming_t timings[2];
	unsigned char channel;
	unsigned char pioMode;
	unsigned int unit;

	if (![self VIAChannel:&channel])
		return NO;
	if (![self VIAReadConfig:&before]) {
		IOLog("%s: VIA PCI config read failed\n", [self name]);
		return NO;
	}
	drv = (driveInfo_t *)drives;
	for (unit = 0; unit < 2; unit++) {
		pioMode = ata_mode_to_num(
			ata_mask_to_mode(drv[unit].driveModes.mode.pio));
		if (pioMode > 4)
			pioMode = 4;
		timings[unit].present = (drv[unit].ideInfo.type != 0);
		timings[unit].pioMode = pioMode;
		timings[unit].transferType = (unsigned char)drv[unit].transferType;
		timings[unit].transferMode =
			ata_mode_to_num(drv[unit].transferMode);
	}
	after = before;
	VIAComputeConfig(&after, (viaChip_t)_chipCaps.privateData, channel,
		timings);
	return [self VIAWriteConfigFrom:&before to:&after];
}

- (BOOL) VIAResetTiming
{
	viaConfig_t before;
	viaConfig_t after;
	unsigned char channel;

	bmStopDMA(_bmRegs);
	if (![self VIAChannel:&channel])
		return NO;
	if (![self VIAReadConfig:&before]) {
		IOLog("%s: VIA PCI config read failed\n", [self name]);
		return NO;
	}
	after = before;
	VIAResetConfig(&after, (viaChip_t)_chipCaps.privateData, channel);
	return [self VIAWriteConfigFrom:&before to:&after];
}

- (BOOL) VIADetectCable
{
	viaConfig_t config;
	unsigned char channel;

	if (![self VIAChannel:&channel])
		return NO;
	if (![self VIAReadConfig:&config]) {
		IOLog("%s: VIA PCI config read failed\n", [self name]);
		return NO;
	}
	return VIADetect80WireCable(&config,
		(viaChip_t)_chipCaps.privateData, channel) ? YES : NO;
}

@end
