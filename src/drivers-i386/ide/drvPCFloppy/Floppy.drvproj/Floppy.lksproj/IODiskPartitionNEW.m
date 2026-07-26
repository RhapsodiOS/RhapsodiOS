/*
 * IODiskPartitionNEW.m - Implementation for NeXT-style LogicalDisk (NEW implementation)
 *
 * Based on IODiskPartition.m
 */

#import "IODiskPartitionNEW.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>

extern unsigned int page_size;
extern unsigned int page_mask;

@implementation IODiskPartitionNEW

/*
 * Class method: deviceStyle
 * From decompiled code: returns device style constant.
 */
+ (int)deviceStyle
{
	return IO_DirectDevice;  // 1
}

/*
 * Class method: requiredProtocols
 * From decompiled code: returns array of required protocol names.
 */
+ (const char **)requiredProtocols
{
	static const char *protocols[] = {
		"IOPhysicalDiskMethods",
		NULL
	};
	return protocols;
}

/*
 * Class method: probe
 * From decompiled code: probes for partitions on physical disk.
 */
+ (BOOL)probe : deviceDescription
{
	id directDevice;
	id drive;
	id logicalDisk;
	BOOL isPhysical;
	BOOL isFormatted;
	BOOL hasReadyState;
	IOReturn result;
	const char *deviceName;
	unsigned blockSize;
	unsigned diskSize;
	disk_label_t *label = NULL;
	BOOL hasValidDisk = NO;
	BOOL hasValidLabel = NO;
	char partitionName[32];
	unsigned capacityKB;
	const char *capacityUnit;
	
	// Get direct device from device description
	directDevice = [deviceDescription directDevice];
	deviceName = (const char *)[directDevice name];
	
	// Check if this is a physical disk
	isPhysical = [directDevice isPhysical];
	if (!isPhysical) {
		return NO;
	}
	
	// Get or create logical disk for partition 'a'
	logicalDisk = [directDevice nextLogicalDisk];
	if (logicalDisk == nil) {
		// Create new partition 'a'
		logicalDisk = [IODiskPartitionNEW new];
		
		// Set partition name (e.g., "fd0a")
		sprintf(partitionName, "%sa", deviceName);
		[logicalDisk setName:partitionName];
		[logicalDisk setDeviceKind:"IODiskPartition"];
		[logicalDisk setLocation:nil];
		[logicalDisk init];
		[logicalDisk registerDevice];
		
		// Connect to physical disk
		[logicalDisk connectToPhysicalDisk:directDevice];
		[directDevice setLogicalDisk:logicalDisk];
		
		// Clear flags (offsets 0x154, 0x155, 0x156)
		((IODiskPartitionNEW *)logicalDisk)->_labelValid = NO;
		((IODiskPartitionNEW *)logicalDisk)->_blockDeviceOpen = NO;
		((IODiskPartitionNEW *)logicalDisk)->_rawDeviceOpen = NO;
		
		// Register Unix disk
		[directDevice registerUnixDisk:0];
		[logicalDisk registerUnixDisk:0];
	} else {
		// Reuse existing logical disk
		[logicalDisk connectToPhysicalDisk:directDevice];
		
		// Clear flags
		((IODiskPartitionNEW *)logicalDisk)->_labelValid = NO;
		((IODiskPartitionNEW *)logicalDisk)->_blockDeviceOpen = NO;
		((IODiskPartitionNEW *)logicalDisk)->_rawDeviceOpen = NO;
	}
	
	// Check if drive is ready
	drive = [directDevice drive];
	hasReadyState = [drive lastReadyState];
	
	if (hasReadyState == IO_Ready) {
		// Check if disk is formatted
		isFormatted = [directDevice isFormatted];
		
		if (isFormatted) {
			// Get disk parameters
			blockSize = [directDevice blockSize];
			diskSize = [directDevice diskSize];
			hasValidDisk = YES;
			
			// Allocate buffer for disk label (0x1c5c bytes)
			label = (disk_label_t *)IOMalloc(0x1c5c);
			
			// Try to read disk label
			result = [logicalDisk readLabel:label];
			if (result == IO_R_SUCCESS) {
				hasValidLabel = YES;
				// Probe label and create partitions
				[logicalDisk _probeLabel:(BOOL)label];
			} else {
				IOLog("%s: No Valid Disk Label\n", deviceName);
				// Set default parameters for partition 'a'
				[logicalDisk setBlockSize:blockSize];
				[logicalDisk setDiskSize:[directDevice diskSize]];
			}
		} else {
			IOLog("%s: Disk Unformatted\n", deviceName);
		}
	} else {
		IOLog("%s: Disk Not Ready\n", deviceName);
	}
	
	// Log disk information
	if (hasValidDisk) {
		IOLog("%s: Device Block Size: %u bytes\n", deviceName, blockSize);
		
		// Calculate capacity
		capacityKB = (diskSize >> 10) * blockSize;
		if (capacityKB < 0x2801) {  // Less than ~10 MB
			capacityKB = diskSize * blockSize;
			capacityUnit = "%s: Device Capacity:   %u KB\n";
		} else {
			capacityUnit = "%s: Device Capacity:   %u MB\n";
		}
		IOLog(capacityUnit, deviceName, capacityKB >> 10);
	}
	
	if (hasValidLabel) {
		// Log disk label name (at offset 0xc in disk_label_t)
		IOLog("%s: Disk Label:        %s\n", deviceName, (char *)label + 0xc);
	}
	
	// Free label buffer if allocated
	if (label != NULL) {
		IOFree(label, 0x1c5c);
	}
	
	return YES;
}


/*
 * Free method.
 * From decompiled code: unregisters Unix disk then calls super.
 */
- free
{
	// Unregister the Unix disk with partition number (offset 0x150)
	[self unregisterUnixDisk:_partition];

	// Call super's free
	return [super free];
}

/*
 * Eject method.
 * From decompiled code: checks safety, frees partitions, ejects media.
 */
- (IOReturn)eject
{
	id physicalDisk;
	id drive;
	IOReturn result;

	physicalDisk = [self physicalDisk];

	// Check if it's safe to eject
	result = [self checkSafeConfig:"eject"];
	if (result != IO_R_SUCCESS) {
		return result;
	}

	// Free all partitions
	[self _freePartitions];

	// Clear label valid flag (offset 0x154)
	_labelValid = NO;

	// Call super's setFormattedInternal with NO
	[super setFormattedInternal:NO];

	// Get drive and eject the media
	drive = [physicalDisk drive];
	[drive ejectMedia];

	return IO_R_SUCCESS;
}

/*
 * Read disk label.
 * From decompiled code: reads and validates disk label from partition.
 */
- (IOReturn)readLabel : (disk_label_t *)label_p
{
	id physicalDisk;
	unsigned blockSize;
	BOOL formatted;
	int partitionOffset;
	unsigned blocksNeeded;
	unsigned bytesToRead;
	unsigned bufferSize;
	unsigned char *buffer;
	unsigned actualLength;
	IOReturn result;
	int i;
	BOOL foundLabel = NO;
	unsigned readOffset;
	int checkResult;

	// Get physical disk
	physicalDisk = [self physicalDisk];

	// Get block size and formatted status
	blockSize = [physicalDisk blockSize];
	formatted = [physicalDisk isFormatted];

	// Validate block size and formatted status
	if (blockSize == 0 || !formatted) {
		return (IOReturn)0xfffffbb3;  // IO_R_INVALID_ARG
	}

	// Get NeXT partition offset
	partitionOffset = [self NeXTpartitionOffset];
	if (partitionOffset < 0) {
		return partitionOffset;
	}

	// Calculate buffer size needed for disk label
	// 0x1c47 = 7239 bytes (size of disk_label_t structure)
	blocksNeeded = (blockSize + 0x1c47) / blockSize;
	bytesToRead = blockSize * blocksNeeded;

	// Allocate page-aligned buffer
	bufferSize = (bytesToRead + page_mask) & ~page_mask;
	buffer = (unsigned char *)IOMalloc(bufferSize);

	// Try to read label from up to 4 locations
	for (i = 0; i < 4; i++) {
		readOffset = partitionOffset + (blocksNeeded * i);

		result = [physicalDisk readAt:readOffset
		                       length:bytesToRead
		                       buffer:buffer
		                 actualLength:&actualLength
		                       client:IOVmTaskSelf()];

		// Check if read succeeded and got full data
		if (result == IO_R_SUCCESS && actualLength == bytesToRead) {
			// Check if this is a valid label
			checkResult = check_label(buffer, readOffset);
			if (checkResult == 0) {
				foundLabel = YES;
				break;
			}
		}

		// If device disappeared, stop trying
		if (result == (IOReturn)0xfffffbb2) {  // IO_R_NO_DEVICE
			break;
		}
	}

	// Process results
	if (foundLabel) {
		// Set label valid flag (offset 0x154)
		_labelValid = YES;

		// Extract disk label data
		get_disk_label(buffer, label_p);

		result = IO_R_SUCCESS;
	} else {
		// Return appropriate error
		if (result != (IOReturn)0xfffffbb2) {
			result = (IOReturn)0xfffffbb4;
		}
	}

	// Free buffer
	IOFree(buffer, bufferSize);

	return result;
}

/*
 * Write disk label.
 * From decompiled code: validates label, writes to multiple locations with checksums.
 */
- (IOReturn)writeLabel : (disk_label_t *)label_p
{
	id physicalDisk;
	unsigned blockSize;
	BOOL formatted;
	IOReturn result;
	unsigned char *buffer = NULL;
	unsigned bufferSize = 0;
	unsigned blocksNeeded;
	unsigned bytesToWrite;
	unsigned checksumSize;
	unsigned checksumOffset;
	unsigned short *checksumPtr;
	unsigned short checksum;
	unsigned writeCount = 0;
	int partitionOffset;
	int i;
	unsigned writeOffset;
	unsigned actualLength;
	char *checkResult;
	ns_time_t timestamp;
	const char *name;

	// Get physical disk
	physicalDisk = [self physicalDisk];
	blockSize = [physicalDisk blockSize];

	// Check if it's safe to write label
	result = [self checkSafeConfig:"writeLabel"];
	if (result != IO_R_SUCCESS) {
		return result;
	}

	// Lock logical disks
	[physicalDisk lockLogicalDisks];

	// Check if disk is formatted
	formatted = [physicalDisk isFormatted];
	if (!formatted) {
		result = (IOReturn)0xfffffd36;  // IO_R_NOT_FORMATTED
		goto cleanup;
	}

	// Free partitions and clear label valid flag
	[self _freePartitions];
	_labelValid = NO;  // offset 0x154

	// Determine label type and set appropriate sizes
	if (label_p->dl_version == DL_V1 || label_p->dl_version == DL_V2) {
		// NeXT or dlV2 label (0x4e655854 or 0x646c5632)
		checksumSize = 0x1c48;
		checksumOffset = 0x1c46;
		checksumPtr = &label_p->dl_checksum;
	} else if (label_p->dl_version == DL_V3) {
		// dlV3 label (0x646c5633)
		checksumSize = 0x230;
		checksumOffset = 0x22e;
		checksumPtr = &label_p->dl_v3_checksum;
	} else {
		// Bad label version
		name = (const char *)[self name];
		IOLog("%s writeLabel: BAD LABEL", name);
		result = (IOReturn)0xfffffd3e;
		goto cleanup;
	}

	// Tag label with current time
	IOGetTimestamp(&timestamp);
	label_p->dl_tag = (unsigned)timestamp;

	// Clear checksum and block offset
	label_p->dl_label_blkno = 0;
	*checksumPtr = 0;

	// Calculate buffer size needed
	blocksNeeded = (blockSize + 0x1c47) / blockSize;
	bytesToWrite = blockSize * blocksNeeded;

	// Allocate page-aligned buffer
	bufferSize = (bytesToWrite + page_mask) & ~page_mask;
	buffer = (unsigned char *)IOMalloc(bufferSize);

	// Serialize label to buffer
	put_disk_label(label_p, buffer);

	// Calculate checksum (divide by 2 for 16-bit words)
	checksum = checksum16(buffer, checksumSize >> 1);

	// Store checksum in big-endian format (byte swap)
	*(unsigned short *)(buffer + checksumOffset) = (checksum >> 8) | (checksum << 8);

	// Verify the label is valid
	checkResult = check_label(buffer, 0);
	if (checkResult != 0) {
		name = (const char *)[self name];
		IOLog("%s writeLabel: BAD LABEL : %s", name, checkResult);
		result = (IOReturn)0xfffffd3e;
		goto cleanup;
	}

	// Get NeXT partition offset
	partitionOffset = [self NeXTpartitionOffset];
	if (partitionOffset < 0) {
		result = partitionOffset;
		goto cleanup;
	}

	// Write label to up to 4 locations
	for (i = 1; i < 4; i++) {
		writeOffset = partitionOffset + (blocksNeeded * i);

		// Update block offset in label (stored at offset 4 in big-endian)
		*(unsigned *)(buffer + 4) =
			(writeOffset >> 24) |
			((writeOffset & 0xff0000) >> 8) |
			((writeOffset & 0xff00) << 8) |
			(writeOffset << 24);

		result = [physicalDisk writeAt:writeOffset
		                        length:bytesToWrite
		                        buffer:buffer
		                  actualLength:&actualLength
		                        client:IOVmTaskSelf()];

		// Count successful writes
		if (result == IO_R_SUCCESS && actualLength == bytesToWrite) {
			writeCount++;
		}

		// If device disappeared, stop trying
		if (result == (IOReturn)0xfffffbb2) {  // IO_R_NO_DEVICE
			break;
		}
	}

	// Check if at least one write succeeded
	if (writeCount != 0) {
		// Set label valid flag (offset 0x154)
		_labelValid = YES;

		// Probe label to recreate partitions
		[self _probeLabel:(BOOL)label_p];

		result = IO_R_SUCCESS;
	} else {
		// All writes failed
		if (result != (IOReturn)0xfffffbb2) {
			result = (IOReturn)0xfffffd36;  // IO_R_NOT_FORMATTED
		}
	}

cleanup:
	// Unlock logical disks
	[physicalDisk unlockLogicalDisks];

	// Free buffer if allocated
	if (buffer != NULL) {
		IOFree(buffer, bufferSize);
	}

	return result;
}


/*
 * Check if block device is open (public version).
 * From decompiled code: returns *(char *)(self + 0x155)
 */
- (BOOL)isBlockDeviceOpen
{
	return _blockDeviceOpen;  // offset 0x155
}

/*
 * Set block device open flag.
 * From decompiled code: sets flag and updates instance open status.
 */
- (void)setBlockDeviceOpen : (BOOL)openFlag
{
	// Set block device open flag (offset 0x155)
	_blockDeviceOpen = (openFlag != 0);

	// Update instance open status based on whether either device is open
	[self setInstanceOpen:(_blockDeviceOpen || _rawDeviceOpen)];
}



/*
 * Set raw device open flag.
 * From decompiled code: sets flag and updates instance open status.
 */
- (void)setRawDeviceOpen : (BOOL)openFlag
{
	// Set raw device open flag (offset 0x156)
	_rawDeviceOpen = (openFlag != 0);

	// Update instance open status based on whether either device is open
	[self setInstanceOpen:(_blockDeviceOpen || _rawDeviceOpen)];
}

/*
 * Check if raw device is open (public version).
 * From decompiled code: returns *(char *)(self + 0x156)
 */
- (BOOL)isRawDeviceOpen
{
	return _rawDeviceOpen;  // offset 0x156
}

/*
 * Get NeXT partition offset.
 * From decompiled code: reads MBR and finds NeXT partition (type 0xA7).
 */
- (unsigned)NeXTpartitionOffset
{
	id physicalDisk;
	unsigned char *buffer;
	unsigned actualLength;
	unsigned blockSize;
	IOReturn result;
	int partitionOffset = 0;
	int i;
	BOOL foundOtherPartition = NO;
	unsigned char *partEntry;

	physicalDisk = [self physicalDisk];

	// Allocate page-sized buffer
	buffer = (unsigned char *)IOMalloc(page_size);

	// Check if block size is 512 bytes
	blockSize = [physicalDisk blockSize];
	if (blockSize != 0x200) {
		goto cleanup;
	}

	// Read sector 0 (MBR)
	result = [physicalDisk readAt:0
	                        length:0x200
	                        buffer:buffer
	                  actualLength:&actualLength
	                        client:IOVmTaskSelf()];

	if (result != IO_R_SUCCESS) {
		partitionOffset = 0xfffffbb1;  // Read error
		goto cleanup;
	}

	// Check for boot signature 0xAA55 at offset 0x1FE
	if (*(unsigned short *)(buffer + 0x1FE) != 0xAA55) {
		goto cleanup;
	}

	// Scan partition table (4 entries at 0x1BE, each 0x10 bytes)
	partEntry = buffer + 0x1BE;
	for (i = 0; i < 4; i++) {
		// Check partition type at offset 4 in entry
		if (partEntry[4] != 0) {
			if (partEntry[4] == 0xA7) {  // NeXT partition type
				// Get partition offset from offset 8 (4 bytes, little-endian)
				partitionOffset = *(int *)(partEntry + 8);
				goto cleanup;
			}
			foundOtherPartition = YES;
		}
		partEntry += 0x10;
	}

	// If we found other partitions but no NeXT partition
	if (foundOtherPartition) {
		partitionOffset = 0xfffffbb0;  // No NeXT partition
	}

cleanup:
	IOFree(buffer, page_size);
	return partitionOffset;
}

/*
 * Set formatted flag (override).
 * From decompiled code: checks safety then sets formatted on physical disk and self.
 */
- (IOReturn)setFormatted : (BOOL)formattedFlag
{
	IOReturn result;
	id physicalDisk;

	// Check if it's safe to change formatted status
	result = [self checkSafeConfig:"setFormatted"];
	if (result != IO_R_SUCCESS) {
		return result;
	}

	// Set formatted on physical disk
	physicalDisk = [self physicalDisk];
	[physicalDisk setFormattedInternal:formattedFlag];

	// Set formatted on self
	[self setFormattedInternal:formattedFlag];

	return IO_R_SUCCESS;
}

/*
 * Set formatted flag internal (override).
 * From decompiled code: frees partitions, clears label, then calls super.
 */
- (void)setFormattedInternal : (BOOL)formattedFlag
{
	// Free all partitions
	[self _freePartitions];

	// Clear label valid flag (offset 0x154)
	_labelValid = NO;

	// Call superclass to set formatted flag
	[super setFormattedInternal:formattedFlag];
}

#ifdef KERNEL

/*
 * Read at offset.
 * From decompiled code: checks label validity then delegates to super.
 */
- (IOReturn)readAt : (unsigned)offset
	     length : (unsigned)length
	     buffer : (unsigned char *)buffer
       actualLength : (unsigned *)actualLength
	     client : (vm_task_t)client
{
	const char *name;

	// Check if label is valid (offset 0x154)
	if (_labelValid) {
		// Delegate to superclass
		return [super readAt:offset
		               length:length
		               buffer:buffer
		         actualLength:actualLength
		               client:client];
	}

	// No valid label
	name = (const char *)[self name];
	IOLog("%s: Read attempt with no valid label", name);
	return (IOReturn)0xfffffd3e;
}

/*
 * Read asynchronously at offset.
 * From decompiled code: checks label validity then delegates to super.
 */
- (IOReturn)readAsyncAt : (unsigned)offset
		  length : (unsigned)length
		  buffer : (unsigned char *)buffer
		 pending : (void *)pending
		  client : (vm_task_t)client
{
	const char *name;

	// Check if label is valid (offset 0x154)
	if (_labelValid) {
		// Delegate to superclass
		return [super readAsyncAt:offset
		                    length:length
		                    buffer:buffer
		                   pending:pending
		                    client:client];
	}

	// No valid label
	name = (const char *)[self name];
	IOLog("%s: Read attempt with no valid label", name);
	return (IOReturn)0xfffffd3e;
}

/*
 * Write at offset.
 * From decompiled code: checks label validity then delegates to super.
 */
- (IOReturn)writeAt : (unsigned)offset
	      length : (unsigned)length
	      buffer : (unsigned char *)buffer
        actualLength : (unsigned *)actualLength
	      client : (vm_task_t)client
{
	const char *name;

	// Check if label is valid (offset 0x154)
	if (_labelValid) {
		// Delegate to superclass
		return [super writeAt:offset
		                length:length
		                buffer:buffer
		          actualLength:actualLength
		                client:client];
	}

	// No valid label
	name = (const char *)[self name];
	IOLog("%s: Write attempt with no valid label", name);
	return (IOReturn)0xfffffd3e;
}

/*
 * Write asynchronously at offset.
 * From decompiled code: checks label validity then delegates to super.
 */
- (IOReturn)writeAsyncAt : (unsigned)offset
		   length : (unsigned)length
		   buffer : (unsigned char *)buffer
		  pending : (void *)pending
		   client : (vm_task_t)client
{
	const char *name;

	// Check if label is valid (offset 0x154)
	if (_labelValid) {
		// Delegate to superclass
		return [super writeAsyncAt:offset
		                     length:length
		                     buffer:buffer
		                    pending:pending
		                     client:client];
	}

	// No valid label
	name = (const char *)[self name];
	IOLog("%s: Write attempt with no valid label", name);
	return (IOReturn)0xfffffd3e;
}

#endif KERNEL

@end

/*
 * Category: Private
 */
@implementation IODiskPartitionNEW(Private)

/*
 * Free all partitions.
 * From decompiled code: frees next logical disk if not open.
 */
- (IOReturn)_freePartitions
{
	id nextDisk;
	const char *name;

	// Get the next logical disk
	nextDisk = [self nextLogicalDisk];

	// Must be partition 0 to free partitions (offset 0x150)
	if (_partition != 0) {
		name = (const char *)[self name];
		IOLog("%s: _freePartitions on partition != 0", name);
		return (IOReturn)0xfffffd2b;  // IO_R_BUSY
	}

	// If no next disk, nothing to free
	if (nextDisk == nil) {
		return IO_R_SUCCESS;
	}

	// Check if the next disk is open
	if ([nextDisk isOpen]) {
		name = (const char *)[self name];
		IOLog("%s: _freePartitions with open partitions", name);
		return (IOReturn)0xfffffd2b;  // IO_R_BUSY
	}

	// Free the next disk (will recursively free the chain)
	[nextDisk free];

	// Clear the reference
	[self setLogicalDisk:nil];

	return IO_R_SUCCESS;
}

/*
 * Initialize a partition.
 * From decompiled code: sets up partition with data from disktab.
 */
- (IOReturn)_initPartition : (int)partition
		    disktab : (struct disktab *)dt
{
	id physicalDisk;
	id diskName;
	char partitionName[32];
	partition_t *partEntry;
	unsigned physBlockSize;
	unsigned partitionBase;

	// Get pointer to the partition entry in the disktab
	partEntry = &dt->d_partitions[partition];

	// Get the physical disk object
	physicalDisk = [self physicalDisk];

	// Create partition name (e.g., "sd0a", "sd0b")
	diskName = [physicalDisk name];
	sprintf(partitionName, "%s%c", (const char *)diskName, partition + 'a');

	// Set partition properties
	[self setName:partitionName];
	[self setLocation:nil];
	[self setDiskSize:partEntry->p_size];
	[self setBlockSize:dt->d_secsize];
	[self setUnit:[physicalDisk unit]];
	[self setWriteProtected:[physicalDisk isWriteProtected]];

	// Calculate partition base in physical blocks
	physBlockSize = [physicalDisk blockSize];
	partitionBase = (dt->d_front + partEntry->p_base) *
	                (dt->d_secsize / physBlockSize);
	[self setPartitionBase:partitionBase];

	// Store partition number (offset 0x150)
	_partition = partition;

	// Call super setFormattedInternal
	[super setFormattedInternal:YES];

	// Set label valid flag (offset 0x154)
	_labelValid = YES;

	// Register as Unix disk
	[self registerUnixDisk:partition];

	return IO_R_SUCCESS;
}

/*
 * Probe for disk label.
 * From decompiled code: creates partition objects for valid partitions.
 */
- (IOReturn)_probeLabel : (BOOL)needsLabel
{
	id physicalDisk;
	id partition;
	id previousPartition;
	int i;
	struct disktab *dt;
	partition_t *partEntry;

	physicalDisk = [self physicalDisk];

	// Only partition 0 creates other partitions
	if (_partition == 0) {
		// Get disktab from structure at offset 0x2c
		dt = (struct disktab *)((char *)needsLabel + 0x2c);
		[self _initPartition:0 disktab:dt];

		// Create partitions 1-6 if valid
		previousPartition = self;
		for (i = 1; i < NPART - 1; i++) {
			partEntry = &dt->d_partitions[i];

			if (partEntry->p_size > 0) {
				partition = [IODiskPartitionNEW new];
				[partition connectToPhysicalDisk:physicalDisk];
				[partition _initPartition:i disktab:dt];
				[partition init];
				[partition registerDevice];
				[previousPartition setLogicalDisk:partition];
				[[self physicalDisk] setLogicalDisk:partition];
				previousPartition = partition;
			}
		}
	} else {
		IOLog("%s: _probeLabel on partition != 0",
		      (const char *)[self name]);
	}

	return IO_R_SUCCESS;
}

/*
 * Check if configuration is safe for destructive operations.
 * From decompiled code: checks partition, block devices, and other opens.
 */
- (IOReturn)checkSafeConfig : (const char *)operation
{
	const char *name;

	// Must be partition 0 for destructive operations (offset 0x150)
	if (_partition != 0) {
		name = (const char *)[self name];
		IOLog("%s: %s on partition != 0", name, operation);
		return (IOReturn)0xfffffd2b;  // IO_R_BUSY
	}

	// Check if any block devices are open
	if ([self isAnyBlockDevOpen]) {
		name = (const char *)[self name];
		IOLog("%s: %s with open block devices", name, operation);
		return (IOReturn)0xfffffd2b;  // IO_R_BUSY
	}

	// Check if any other partitions are open
	if ([self isAnyOtherOpen]) {
		name = (const char *)[self name];
		IOLog("%s: %s with other partitions open", name, operation);
		return (IOReturn)0xfffffd2b;  // IO_R_BUSY
	}

	return IO_R_SUCCESS;
}

/*
 * Check if any block device is open.
 * From decompiled code: iterates through all partitions.
 */
- (BOOL)isAnyBlockDevOpen
{
	id physicalDisk;
	id partition;

	// Get physical disk and iterate through all partitions
	physicalDisk = [self physicalDisk];
	partition = physicalDisk;

	while (1) {
		partition = [partition nextLogicalDisk];
		if (partition == nil) {
			return NO;
		}
		if ([partition isBlockDeviceOpen]) {
			return YES;
		}
	}
}

/*
 * Check if any other partition has devices open.
 * Similar to isAnyBlockDevOpen but checks raw devices.
 */
- (BOOL)isAnyOtherOpen
{
	id physicalDisk;
	id partition;

	// Get physical disk and iterate through all partitions
	physicalDisk = [self physicalDisk];
	partition = physicalDisk;

	while (1) {
		partition = [partition nextLogicalDisk];
		if (partition == nil) {
			return NO;
		}
		if ([partition isRawDeviceOpen]) {
			return YES;
		}
	}
}

@end
