/*
 * IdeAMD.m - AMD-756/766 chipset back-end.
 */
#import "IdeCnt.h"
#import "IdeAMD.h"
#import "IdeBMIDE.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/i386/IOPCIDirectDevice.h>
#import <machkit/NXLock.h>

/*
 * Primary and secondary objects share PCI dwords, so serialize each full
 * read/compute/write transaction across both channels.
 */
static id amdConfigLock = nil;

static BOOL amdMatch(id deviceDescription, unsigned long pciID,
	unsigned char revision, unsigned char progIf, ideChipCaps_t *out)
{
	const amdChipInfo_t *chip;

	(void)deviceDescription;
	chip = AMDFindChip(pciID, revision);
	if (chip == NULL)
		return NO;
	if (amdConfigLock == nil) {
		amdConfigLock = [NXLock new];
		if (amdConfigLock == nil) {
			IOLog("IdeAMD: AMD PCI config lock allocation failed\n");
			return NO;
		}
	}
	out->maxPIO = chip->maxPIO;
	out->maxMWDMA = chip->maxMWDMA;
	out->maxUDMA = chip->maxUDMA;
	out->flags = (progIf & PCI_IDE_BUSMASTER) ? CHIP_FLAG_BUSMASTER : 0;
	out->privateData = (unsigned int)chip->chip;
	return YES;
}

static void amdSetTiming(id self, void *drives) { [self AMDSetTiming:drives]; }
static void amdResetTiming(id self) { [self AMDResetTiming]; }
static BOOL amdDetectCable(id self) { return [self AMDDetectCable]; }

const ideChipsetOps_t ideAMDOperations = {
	"AMD-756/766", amdMatch, amdSetTiming, amdResetTiming, amdDetectCable
};

@implementation IdeController(AMD)

- (BOOL) AMDChannel:(unsigned char *)channel
{
	switch (_ideChannel) {
		case PCI_CHANNEL_PRIMARY:
			*channel = AMD_CHANNEL_PRIMARY;
			return YES;
		case PCI_CHANNEL_SECONDARY:
			*channel = AMD_CHANNEL_SECONDARY;
			return YES;
		default:
			return NO;
	}
}

- (BOOL) AMDReadConfig:(amdConfig_t *)config
{
	unsigned int index;
	unsigned int offset;
	unsigned long data;
	IOReturn rtn;

	for (offset = AMD_CONFIG_BASE;
	     offset < AMD_CONFIG_BASE + AMD_CONFIG_SIZE; offset += 4) {
		rtn = [[self class] getPCIConfigData:&data
			atRegister:(unsigned char)offset
			withDeviceDescription:[self deviceDescription]];
		if (rtn != IO_R_SUCCESS)
			return NO;
		index = offset - AMD_CONFIG_BASE;
		config->bytes[index] = (unsigned char)(data & 0xff);
		config->bytes[index + 1] = (unsigned char)((data >> 8) & 0xff);
		config->bytes[index + 2] = (unsigned char)((data >> 16) & 0xff);
		config->bytes[index + 3] = (unsigned char)((data >> 24) & 0xff);
	}
	return YES;
}

- (BOOL) AMDWriteChangesFrom:(const amdConfig_t *)before
	to:(const amdConfig_t *)after
{
	unsigned int index;
	unsigned int offset;
	unsigned long beforeData;
	unsigned long afterData;
	IOReturn rtn;
	BOOL success;

	success = YES;
	for (offset = AMD_CONFIG_BASE;
	     offset < AMD_CONFIG_BASE + AMD_CONFIG_SIZE; offset += 4) {
		index = offset - AMD_CONFIG_BASE;
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
			IOLog("%s: AMD PCI config write failed at 0x%02x\n",
				[self name], offset);
			success = NO;
		}
	}
	return success;
}

- (BOOL) AMDSetTiming:(void *)drives
{
	driveInfo_t *drv;
	amdConfig_t before;
	amdConfig_t after;
	amdDriveTiming_t timings[2];
	unsigned char channel;
	unsigned char pioMode;
	unsigned int unit;
	BOOL success;

	if (![self AMDChannel:&channel])
		return NO;
	drv = (driveInfo_t *)drives;
	for (unit = 0; unit < 2; ++unit) {
		pioMode = ata_mode_to_num(
			ata_mask_to_mode(drv[unit].driveModes.mode.pio));
		if (pioMode > 4)
			pioMode = 4;
		timings[unit].present = (drv[unit].ideInfo.type != 0);
		timings[unit].pioMode = pioMode;
		timings[unit].transferType =
			(unsigned char)drv[unit].transferType;
		timings[unit].transferMode =
			ata_mode_to_num(drv[unit].transferMode);
	}
	[amdConfigLock lock];
	if (![self AMDReadConfig:&before]) {
		IOLog("%s: AMD PCI config read failed\n", [self name]);
		[amdConfigLock unlock];
		return NO;
	}
	after = before;
	AMDComputeConfig(&after, (amdChip_t)_chipCaps.privateData, channel,
		timings);
	success = [self AMDWriteChangesFrom:&before to:&after];
	[amdConfigLock unlock];
	return success;
}

- (BOOL) AMDResetTiming
{
	amdConfig_t before;
	amdConfig_t after;
	unsigned char channel;
	BOOL success;

	if ((_chipCaps.flags & CHIP_FLAG_BUSMASTER) && _bmRegs != 0)
		bmStopDMA(_bmRegs);
	if (![self AMDChannel:&channel])
		return NO;
	[amdConfigLock lock];
	if (![self AMDReadConfig:&before]) {
		IOLog("%s: AMD PCI config read failed\n", [self name]);
		[amdConfigLock unlock];
		return NO;
	}
	after = before;
	AMDResetConfig(&after, (amdChip_t)_chipCaps.privateData, channel);
	success = [self AMDWriteChangesFrom:&before to:&after];
	[amdConfigLock unlock];
	return success;
}

- (BOOL) AMDDetectCable
{
	amdConfig_t config;
	amdChip_t chip;
	unsigned char channel;
	BOOL success;

	chip = (amdChip_t)_chipCaps.privateData;
	if (chip == AMD_CHIP_756)
		return YES;
	if (![self AMDChannel:&channel])
		return NO;
	[amdConfigLock lock];
	if (![self AMDReadConfig:&config]) {
		IOLog("%s: AMD PCI config read failed\n", [self name]);
		[amdConfigLock unlock];
		return NO;
	}
	success = AMDDetect80WireCable(&config, chip, channel) ? YES : NO;
	[amdConfigLock unlock];
	return success;
}

@end
