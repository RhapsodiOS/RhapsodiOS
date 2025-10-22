/*
 * Geometry.m - Geometry support methods for IOFloppyDisk
 *
 * Category methods for disk geometry calculations and cache management
 */

#import "IOFloppyDisk.h"
#import "Geometry.h"
#import <driverkit/generalFuncs.h>
#import <driverkit/kernelDriver.h>

/*
 * Apple variable-rate band layouts for GCR-encoded floppy disks.
 *
 * These arrays define the cylinder-to-sector mapping for Apple's proprietary
 * variable-rate floppy formats. Apple used "banded" or "zoned" recording where
 * outer tracks have more sectors than inner tracks, similar to modern hard drives.
 *
 * Format: Array of triplets [startBlock, startCylinder, sectorsPerCylinder]
 * - startBlock: First logical block number in this band
 * - startCylinder: First cylinder in this band
 * - sectorsPerCylinder: Number of sectors per cylinder in this band
 *
 * Bands are ordered from outermost (highest cylinder) to innermost (cylinder 0).
 * The final entry has startBlock=0, startCylinder=0, marking the innermost band.
 *
 * Single-sided formats (400KB):
 *   - Outermost tracks: 8 sectors/track
 *   - Innermost tracks: 12 sectors/track
 *
 * Double-sided formats (800KB, 1600KB):
 *   - Each cylinder has 2 heads (sides)
 *   - sectorsPerCylinder = sectors/track on both heads
 */

// Apple 400KB single-sided variable-rate format
// Total: ~400KB on 80 cylinders, 1 head, variable sectors (8-12)
unsigned int appleBandLayout400[] = {
    0x000002a0, 0x00000040, 0x00000008,  // Band 0: Cyl 64-79,  8 sect/cyl
    0x00000210, 0x00000030, 0x00000009,  // Band 1: Cyl 48-63,  9 sect/cyl
    0x00000170, 0x00000020, 0x0000000a,  // Band 2: Cyl 32-47, 10 sect/cyl
    0x000000c0, 0x00000010, 0x0000000b,  // Band 3: Cyl 16-31, 11 sect/cyl
    0x00000000, 0x00000000, 0x0000000c,  // Band 4: Cyl  0-15, 12 sect/cyl
};

// Apple 800KB double-sided variable-rate format (standard Mac format)
// Total: ~800KB on 80 cylinders, 2 heads, variable sectors (8-12 per track)
unsigned int appleBandLayout800[] = {
    0x00000540, 0x00000040, 0x00000008,  // Band 0: Cyl 64-79,  8 sect/cyl (4/track/side)
    0x00000420, 0x00000030, 0x00000009,  // Band 1: Cyl 48-63,  9 sect/cyl
    0x000002e0, 0x00000020, 0x0000000a,  // Band 2: Cyl 32-47, 10 sect/cyl
    0x00000180, 0x00000010, 0x0000000b,  // Band 3: Cyl 16-31, 11 sect/cyl
    0x00000000, 0x00000000, 0x0000000c,  // Band 4: Cyl  0-15, 12 sect/cyl (6/track/side)
};

// Apple 1600KB double-sided high-density variable-rate format
// Total: ~1600KB on 80 cylinders, 2 heads, variable sectors (16-24 per track)
unsigned int appleBandLayout1600[] = {
    0x00000a80, 0x00000040, 0x00000010,  // Band 0: Cyl 64-79, 16 sect/cyl (8/track/side)
    0x00000840, 0x00000030, 0x00000012,  // Band 1: Cyl 48-63, 18 sect/cyl (9/track/side)
    0x000005c0, 0x00000020, 0x00000014,  // Band 2: Cyl 32-47, 20 sect/cyl (10/track/side)
    0x00000300, 0x00000010, 0x00000016,  // Band 3: Cyl 16-31, 22 sect/cyl (11/track/side)
    0x00000000, 0x00000000, 0x00000018,  // Band 4: Cyl  0-15, 24 sect/cyl (12/track/side)
};

/*
 * FDC density and MID (Media IDentifier) lookup tables.
 *
 * These tables map density codes to FDC configuration values. Each table
 * contains pairs of values terminated by a {0, 0} entry.
 *
 * Structure: Array of pairs [value, densityCode]
 * - value: Configuration value or pointer (usage TBD)
 * - densityCode: Density identifier (0=terminator, 1=DD, 2=HD, 3=ED)
 *
 * Note: The first value in each pair appears to be in the 0x99xx range,
 * suggesting it may be a pointer or encoded parameter value.
 */

// Density values table
// Maps density codes to configuration parameters
unsigned int densityValues[] = {
    0x00000000, 0x00000000,  // Entry 0: padding/reserved
    0x000099ab, 0x00000001,  // Entry 1: DD (Double Density) - 250 Kbps
    0x000099a1, 0x00000002,  // Entry 2: HD (High Density) - 500 Kbps
    0x00009997, 0x00000003,  // Entry 3: ED (Extra Density) - 1 Mbps
    0x0000998d, 0x00000000,  // Entry 4: terminator
};

// MID (Media IDentifier) values table
// Similar to densityValues but in different order (ED, HD, DD)
// Used for media detection or format identification
unsigned int midValues[] = {
    0x00000000, 0x00000000,  // Entry 0: padding/reserved
    0x000099d9, 0x00000003,  // Entry 1: ED (Extra Density) - 1 Mbps
    0x000099ce, 0x00000002,  // Entry 2: HD (High Density) - 500 Kbps
    0x000099c3, 0x00000001,  // Entry 3: DD (Double Density) - 250 Kbps
    0x000099b8, 0x00000000,  // Entry 4: terminator
};

// FDC disk physical parameter table
// Maps density codes to physical disk geometry parameters
// Structure: Array of 4-word entries [densityCode, numHeads, numCylinders, ?]
// Used for configuring physical parameters based on media density
unsigned int fdDiskInfo[] = {
    // Entry 0: Density 3 (ED - Extra Density) - 2.88MB
    0x00000003, 0x00000002, 0x00000050, 0x00000001,  // Density 3, 2 heads, 80 cylinders (0x50)

    // Entry 1: Density 2 (HD - High Density) - 1.44MB
    0x00000002, 0x00000002, 0x00000050, 0x00000002,  // Density 2, 2 heads, 80 cylinders (0x50)

    // Entry 2: Density 1 (DD - Double Density) - 720KB
    0x00000001, 0x00000002, 0x00000050, 0x00000003,  // Density 1, 2 heads, 80 cylinders (0x50)

    // Terminator
    0x00000000, 0x00000000, 0x00000000, 0x00000000,
};

// Sector size information structures for different densities
// These structures define sector size and timing parameters for each density
//
// Structure appears to be:
// [0] sectorSize - bytes per sector (typically 512 = 0x200)
// [1] n - sector size code for FDC (2 = 512 bytes: 128 * 2^n)
// [2] sectorsPerTrack - number of sectors per track
// [3] gapLength - gap length for read/write operations
// [4] formatGapLength - gap length for format operations
// [5] ??? - unknown parameter
// [6] ??? - unknown parameter
// [7] ??? - unknown parameter or terminator

// Sector size info for 1MB formats (720KB DD)
unsigned int _ssi_1mb[] = {
    0x00000200,  // [0] Sector size: 512 bytes
    0x00000002,  // [1] N value: 2 (512 = 128 * 2^2)
    0x00000009,  // [2] Sectors per track: 9 (for 720KB DD)
    0x0000541b,  // [3] Gap length: 0x541B
    0x00000400,  // [4] Format gap length: 0x400
    0x00000003,  // [5] Unknown: 3
    0x00000005,  // [6] Unknown: 5
    0x00007435,  // [7] Unknown: 0x7435
};

// Sector size info for 2MB formats (1.44MB HD)
unsigned int _ssi_2mb[] = {
    0x00000200,  // [0] Sector size: 512 bytes
    0x00000002,  // [1] N value: 2 (512 = 128 * 2^2)
    0x00000012,  // [2] Sectors per track: 18 (for 1.44MB HD)
    0x0000651b,  // [3] Gap length: 0x651B
    0x00000000,  // [4] Format gap length: 0 (or continues to next field)
    0x00000000,  // [5] Unknown: 0
    0x00000000,  // [6] Unknown: 0
    0x00000000,  // [7] Unknown/terminator: 0
};

// Sector size info for 4MB formats (2.88MB ED)
unsigned int _ssi_4mb[] = {
    0x00000200,  // [0] Sector size: 512 bytes
    0x00000002,  // [1] N value: 2 (512 = 128 * 2^2)
    0x00000024,  // [2] Sectors per track: 36 (for 2.88MB ED)
    0x0000531b,  // [3] Gap length: 0x531B
    0x00000000,  // [4] Format gap length: 0 (or continues to next field)
    0x00000000,  // [5] Unknown: 0
    0x00000000,  // [6] Unknown: 0
    0x00000000,  // [7] Unknown/terminator: 0
};

// FDC density to sector size mapping table
// Maps density codes to sector size information structures
// Structure: Array of pairs [densityCode, pointerToSectorSizeInfo]
// Used for looking up sector size configuration for a given density
unsigned int fdDensitySectsize[] = {
    0x00000001, (unsigned int)_ssi_1mb,   // Entry 0: Density 1 (DD) -> 1MB sector size info (720KB, 9 sect/trk)
    0x00000002, (unsigned int)_ssi_2mb,   // Entry 1: Density 2 (HD) -> 2MB sector size info (1.44MB, 18 sect/trk)
    0x00000003, (unsigned int)_ssi_4mb,   // Entry 2: Density 3 (ED) -> 4MB sector size info (2.88MB, 36 sect/trk)
    0x00000000, (unsigned int)_ssi_1mb,   // Terminator/default -> 1MB sector size info
    0x00000000, 0x00000000,                // End marker
};

// FDC density information table
// Maps density codes to FDC configuration parameters
// Structure: Array of triplets [densityCode, dataRate, mfmFlag]
// Used for configuring the FDC for different media densities
//
// densityCode: 1=DD (Double Density), 2=HD (High Density), 3=ED (Extra Density)
// dataRate: Data transfer rate in Hz (736000=250Kbps, 1474560=500Kbps, 1842176=1Mbps)
// mfmFlag: MFM encoding flag (1=MFM, 0=FM)
unsigned int fdDensityInfo[] = {
    // Entry 0: HD (High Density) - 500 Kbps, MFM
    0x00000001, 0x000b4000, 0x00000001,  // Density 1, 736000 Hz (0xB4000), MFM

    // Entry 1: HD (High Density) - 500 Kbps, MFM
    0x00000002, 0x00168000, 0x00000001,  // Density 2, 1474560 Hz (0x168000), MFM

    // Entry 2: ED (Extra Density) - 1 Mbps, MFM
    0x00000003, 0x001c2d00, 0x00000001,  // Density 3, 1842432 Hz (0x1C2D00), MFM

    // Terminator
    0x00000000, 0x000b4000, 0x00000001,
};

// FDC ioctl handler mapping table
// Maps ioctl command codes to handler function pointers
// Structure: Array of pairs [ioctlCode, handlerAddress]
// Used for dispatching ioctl requests to appropriate handlers
unsigned int fdIoctlValues[] = {
    0x80046417, 0x00009a70,  // Entry 0:  DKIOCGLASTREADYSTATUS (0x80046417) -> handler at 0x9a70
    0x40046417, 0x00009a63,  // Entry 1:  DKIOCGLASTREADYSTATUS (0x40046417) -> handler at 0x9a63
    0x5c5c6400, 0x00009a57,  // Entry 2:  DKIOCGPART (read label) (0x5c5c6400) -> handler at 0x9a57
    0x9c5c6401, 0x00009a4b,  // Entry 3:  DKIOCSPART (write label) (0x9c5c6401) -> handler at 0x9a4b
    0x20006415, 0x00009a40,  // Entry 4:  DKIOCCHECKINSERT (0x20006415) -> handler at 0x9a40
    0x40306405, 0x00009a36,  // Entry 5:  DKIOCINFO (drive info) (0x40306405) -> handler at 0x9a36
    0x40046418, 0x00009a2a,  // Entry 6:  DKIOCISWRITABLE (0x40046418) -> handler at 0x9a2a
    0x40046419, 0x00009a1d,  // Entry 7:  Unknown ioctl (0x40046419) -> handler at 0x9a1d
    0xc0606600, 0x00009a14,  // Entry 8:  DKIOCFORMAT (format disk) (0xc0606600) -> handler at 0x9a14
    0x80046602, 0x00009a09,  // Entry 9:  Unknown ioctl (0x80046602) -> handler at 0x9a09
    0x80046603, 0x000099fe,  // Entry 10: DKIOCGLASTREADYSTATUS (0x80046603) -> handler at 0x99fe
    0x40346601, 0x000099f3,  // Entry 11: Unknown ioctl (0x40346601) -> handler at 0x99f3
    0x4020660a, 0x000099e5,  // Entry 12: DKIOCGETFORMATCAPACITIES (0x4020660a) -> handler at 0x99e5
    0x00000000, 0x00000000,  // Terminator
};

// FDC command configuration values table
// Maps command IDs to FDC parameters and flags
// Structure: Array of triplets [padding, paramValue, commandId]
// Used for FDC command execution with timing/control parameters
unsigned int fdCommandValues[] = {
    0x00000000, 0x0000988b, 0x00000001,  // Entry 0: Cmd 1, param 0x988b
    0x00000000, 0x0000987d, 0x00000002,  // Entry 1: Cmd 2, param 0x987d
    0x00000000, 0x00009871, 0x00000003,  // Entry 2: Cmd 3, param 0x9871
    0x00000000, 0x00009862, 0x00000004,  // Entry 3: Cmd 4, param 0x9862
    0x00000000, 0x00009852, 0x00000005,  // Entry 4: Cmd 5, param 0x9852
    0x00000000, 0x00009841, 0x00000006,  // Entry 5: Cmd 6, param 0x9841
    0x00000000, 0x00000000, 0x00000000,  // Terminator
};

// FDC opcode/command configuration values table
// Maps opcode/command codes to FDC parameters
// Structure: Array of pairs [value, commandCode]
// Used for configuring FDC commands with appropriate timing or parameters
unsigned int fcOpcodeValues[] = {
    0x00009982, 0x00000c06,  // Entry 0: Cmd 0x06, param 0x9982
    0x00009970, 0x0000050c,  // Entry 1: Cmd 0x0c, param 0x9970
    0x00009966, 0x00000905,  // Entry 2: Cmd 0x05, param 0x9966
    0x00009953, 0x00000209,  // Entry 3: Cmd 0x09, param 0x9953
    0x00009942, 0x00001602,  // Entry 4: Cmd 0x02, param 0x9942
    0x00009935, 0x00001016,  // Entry 5: Cmd 0x16, param 0x9935
    0x0000991a, 0x00000d10,  // Entry 6: Cmd 0x10, param 0x991a
    0x0000990e, 0x0000070d,  // Entry 7: Cmd 0x0d, param 0x990e
    0x00009900, 0x00000308,  // Entry 8: Cmd 0x08, param 0x9900
    0x000098f2, 0x00000403,  // Entry 9: Cmd 0x03, param 0x98f2
    0x000098df, 0x00000f04,  // Entry 10: Cmd 0x04, param 0x98df
    0x000098d4, 0x0000130f,  // Entry 11: Cmd 0x0f, param 0x98d4
    0x000098c4, 0x00000e13,  // Entry 12: Cmd 0x13, param 0x98c4
    0x000098b6, 0x00000a0e,  // Entry 13: Cmd 0x0e, param 0x98b6
    0x000098a9, 0x0000120a,  // Entry 14: Cmd 0x0a, param 0x98a9
    0x00009895, 0x00000012,  // Entry 15: Cmd 0x12, param 0x9895
    0x00000000, 0x00000000,  // Terminator
};

/*
 * FloppyGeometry - Master geometry table for all supported floppy formats.
 *
 * This table defines the physical geometry for all floppy disk formats supported
 * by the driver. Each entry contains 7 words (28 bytes) defining a format:
 *
 * Structure: [capacity, diskSize, numHeads, numCylinders, sectorsPerTrack, sectorSize, bandLayout]
 * - capacity: Capacity identifier (bit flags: 0x20=720K, 0x100=1.44M, 0x200=Apple, 0x400=Apple HD, 0x800=2.88M)
 * - diskSize: Total disk size in KB
 * - numHeads: Number of heads/sides (1 or 2)
 * - numCylinders: Number of cylinders (typically 80)
 * - sectorsPerTrack: Sectors per track (for fixed geometry, 0 for variable)
 * - sectorSize: Sector size in bytes (typically 512)
 * - bandLayout: Pointer to variable-rate band layout array, or 0 for fixed geometry
 *
 * The table is terminated by an entry with capacity = 0.
 */
unsigned int FloppyGeometry[] = {
    // Entry 0: 2.88MB ED (Extra Density) - 80 cyl, 2 heads, 36 sect/track
    0x00000800, 0x00001680, 0x00000002, 0x00000050, 0x00000024, 0x00000200, 0x00000000,

    // Entry 1: Apple 1.6MB FDHD variable-rate - 80 cyl, 2 heads, variable sectors
    0x00000400, 0x00000d20, 0x00000002, 0x00000050, 0x00000015, 0x00000200, 0x00000000,

    // Entry 2: Apple 1.6MB FDHD with band layout - 80 cyl, 2 heads, variable (16-24 sect)
    0x00000200, 0x00000c80, 0x00000002, 0x00000050, 0x00000000, 0x00000200, (unsigned int)appleBandLayout1600,

    // Entry 3: 1.44MB HD (High Density) - 80 cyl, 2 heads, 18 sect/track
    0x00000100, 0x00000b40, 0x00000002, 0x00000050, 0x00000012, 0x00000200, 0x00000000,

    // Entry 4: Unknown/Reserved - 128 bytes?, 2 heads, 0 sect/track
    0x00000080, 0x00000960, 0x00000002, 0x00000050, 0x0000000f, 0x00000200, 0x00000000,

    // Entry 5: Unknown/Reserved - 64 bytes?, 2 heads, 0 sect/track
    0x00000040, 0x00000640, 0x00000002, 0x00000050, 0x00000000, 0x00000200, (unsigned int)appleBandLayout800,

    // Entry 6: Apple 800KB with band layout - 80 cyl, 2 heads, variable (8-12 sect)
    0x00000020, 0x000005a0, 0x00000002, 0x00000050, 0x00000009, 0x00000200, 0x00000000,

    // Entry 7: Apple 400KB (single-sided) - 80 cyl, 1 head, variable sectors
    0x00000010, 0x00000320, 0x00000001, 0x00000050, 0x00000000, 0x00000200, (unsigned int)appleBandLayout400,

    // Entry 8: Apple 720KB (double-sided DD) - 40 cyl, 2 heads, 9 sect/track
    0x00000008, 0x000002d0, 0x00000002, 0x00000028, 0x00000009, 0x00000200, 0x00000000,

    // Entry 9: Apple 360KB (single-sided) - 40 cyl, 1 head, 9 sect/track
    0x00000004, 0x00000168, 0x00000001, 0x00000028, 0x00000009, 0x00000200, 0x00000000,

    // Entry 10: Apple 544KB? - 34 cyl?, 1 head, 16 sect/track
    0x00000002, 0x00000220, 0x00000001, 0x00000022, 0x00000010, 0x00000100, 0x00000000,

    // Entry 11: Apple 256KB? - 256 bytes?, 1 head, 0 sect/track
    0x00000001, 0x00000100, 0x00000001, 0x00000000, 0x00000100, 0x00000000, 0x00000000,

    // Terminator entry
    0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
};

@implementation IOFloppyDisk(Geometry)

/*
 * Class method: Get capacity from disk size.
 * From decompiled code: converts disk size to capacity identifier.
 *
 * This method searches through the FloppyGeometry table to find an entry
 * that matches the given disk size (in KB). The table contains geometry
 * information for various floppy disk formats.
 *
 * Parameters:
 *   diskSize - Size of the disk in KB (e.g., 1440 for 1.44MB)
 *
 * Returns:
 *   Capacity identifier from the matching geometry entry
 *
 * FloppyGeometry table structure (7 int entries per format):
 *   [0] - Capacity identifier
 *   [1] - ? (offset 0x04)
 *   [2] - ? (offset 0x08)
 *   [3] - ? (offset 0x0c)
 *   [4] - Blocks/sectors (offset 0x10)
 *   [5] - ? (offset 0x14)
 *   [6] - Sectors per track (offset 0x18)
 *
 * The table is NULL-terminated (capacity = 0 marks end).
 */
+ (unsigned int)_capacityFromSize:(unsigned int)diskSize
{
	extern unsigned int FloppyGeometry[];  // External geometry table
	int index;
	int matchIndex;
	unsigned int *geometryEntry;
	unsigned int blocks;
	unsigned int sectorsPerTrack;
	unsigned int sizeInKB;

	index = 0;
	matchIndex = 0;

	// Search through FloppyGeometry table
	// Each entry is 7 ints (28 bytes = 0x1c)
	do {
		matchIndex = index;

		// Get pointer to current geometry entry
		geometryEntry = &FloppyGeometry[index * 7];

		// Calculate size in KB from blocks and sectors per track
		// blocks at offset 0x10 (index 4), sectors per track at offset 0x18 (index 6)
		blocks = geometryEntry[4];           // Offset 0x10 from entry start
		sectorsPerTrack = geometryEntry[6];  // Offset 0x18 from entry start

		// Calculate size in KB: (blocks * sectorsPerTrack) / 1024
		sizeInKB = (unsigned int)(blocks * sectorsPerTrack) >> 10;

		// Check if this entry matches the requested size
		if (sizeInKB == diskSize) {
			break;
		}

		// Move to next entry
		matchIndex = index + 1;
		index = matchIndex;

		// Check if we've reached the end of the table
		// The table is terminated when capacity (offset 0) is 0
	} while (FloppyGeometry[matchIndex * 7] != 0);

	// Return the capacity identifier from the matching entry
	return FloppyGeometry[matchIndex * 7];
}

/*
 * Class method: Get geometry from capacity.
 * From decompiled code: returns geometry structure for given capacity.
 *
 * This method searches through the FloppyGeometry table to find an entry
 * with the matching capacity identifier and returns a pointer to that entry.
 *
 * Parameters:
 *   capacity - Capacity identifier to search for
 *
 * Returns:
 *   Pointer to the geometry entry (7 ints) in FloppyGeometry table,
 *   or NULL if not found
 *
 * FloppyGeometry table structure (7 int entries per format):
 *   [0] - Capacity identifier
 *   [1] - ? (offset 0x04)
 *   [2] - ? (offset 0x08)
 *   [3] - ? (offset 0x0c)
 *   [4] - Blocks/sectors (offset 0x10)
 *   [5] - ? (offset 0x14)
 *   [6] - Sectors per track (offset 0x18)
 */
+ (void *)_geometryOfCapacity:(unsigned int)capacity
{
	extern unsigned int FloppyGeometry[];  // External geometry table
	int index;
	int nextIndex;

	index = 0;

	// Search through FloppyGeometry table
	// Each entry is 7 ints (28 bytes = 0x1c)
	do {
		// Check if current entry's capacity matches
		if (FloppyGeometry[index * 7] == capacity) {
			// Found matching entry, return pointer to it
			return (void *)&FloppyGeometry[index * 7];
		}

		// Move to next entry
		nextIndex = index + 1;
		index = nextIndex;

		// Check if we've reached the end of the table
		// The table is terminated when capacity (offset 0) is 0
	} while (FloppyGeometry[nextIndex * 7] != 0);

	// No matching entry found
	return NULL;
}

/*
 * Class method: Create size list from capacities.
 * From decompiled code: converts capacity bitmask to array of sizes.
 *
 * This method iterates through the FloppyGeometry table and for each entry
 * whose capacity matches the bitmask, calculates the size in KB and adds it
 * to the output array.
 *
 * Parameters:
 *   capacities - Bitmask of capacity identifiers (not an array - it's a bitmask!)
 *   sizeList   - Output array to store size values (NULL-terminated)
 *
 * Returns:
 *   IO_R_SUCCESS (method has void return in decompiled code)
 *
 * Example:
 *   If capacities = 0x03 (bits 0 and 1 set), this will add sizes for
 *   all geometry entries with capacity IDs 0 or 1.
 */
+ (IOReturn)_sizeListFromCapacities:(unsigned int)capacities
                           sizeList:(unsigned int *)sizeList
{
	extern unsigned int FloppyGeometry[];  // External geometry table
	int index;
	int nextIndex;
	unsigned int *geometryEntry;
	unsigned int blocks;
	unsigned int sectorsPerTrack;
	unsigned int sizeInKB;
	unsigned int capacityId;

	index = 0;

	// Iterate through FloppyGeometry table
	// Each entry is 7 ints (28 bytes = 0x1c)
	do {
		// Get pointer to current geometry entry
		geometryEntry = &FloppyGeometry[index * 7];

		// Get capacity identifier from entry
		capacityId = geometryEntry[0];  // Offset 0x00

		// Check if this capacity is in the bitmask
		if ((capacityId & capacities) != 0) {
			// Calculate size in KB from blocks and sectors per track
			blocks = geometryEntry[4];           // Offset 0x10
			sectorsPerTrack = geometryEntry[6];  // Offset 0x18

			// Calculate size in KB: (blocks * sectorsPerTrack) / 1024
			sizeInKB = (unsigned int)(blocks * sectorsPerTrack) >> 10;

			// Store size in output array and advance pointer
			*sizeList = sizeInKB;
			sizeList++;
		}

		// Move to next entry
		nextIndex = index + 1;
		index = nextIndex;

		// Check if we've reached the end of the table
		// The table is terminated when capacity (offset 0) is 0
	} while (FloppyGeometry[nextIndex * 7] != 0);

	// NULL-terminate the output array
	*sizeList = 0;

	return IO_R_SUCCESS;
}

/*
 * Calculate blocks remaining to end of cylinder from given block number.
 * From decompiled code: calculates how many blocks until end of current cylinder.
 */
- (unsigned)_blocksToEndOfCylinderFromBlockNumber:(unsigned)blockNumber
{
	id driveObject;
	unsigned *geometryArray;
	unsigned blocksPerCylinder;
	unsigned adjustedBlockNumber;
	
	// Get drive object from offset 0x14c
	driveObject = *(id *)((char *)self + 0x14c);
	
	// Get geometry array pointer from offset 0x18 relative to drive object
	geometryArray = *(unsigned **)((char *)driveObject + 0x18);
	
	adjustedBlockNumber = blockNumber;
	
	if (geometryArray == NULL) {
		// Fixed geometry: blocks per cylinder = numCyls * sectorsPerTrack
		// offset 0x10 and offset 0x8 from drive object
		blocksPerCylinder = *(int *)((char *)driveObject + 0x10) * 
		                    *(int *)((char *)driveObject + 0x8);
	} else {
		// Variable geometry: search array for matching range
		// Array format: [startBlock, ?, sectorsPerCyl, ...]
		while (blockNumber >= *geometryArray) {
			geometryArray += 3;  // Move to next entry (3 uints per entry)
		}
		
		// Get sectors per cylinder from array entry at index 2
		// Multiply by sectors per track from drive object
		blocksPerCylinder = geometryArray[2] * 
		                    *(int *)((char *)driveObject + 0x8);
		
		// Adjust block number relative to this geometry range
		adjustedBlockNumber = blockNumber - *geometryArray;
	}
	
	// Calculate blocks remaining to end of current cylinder
	// Formula: blocksPerCyl - (blockNum % blocksPerCyl)
	return blocksPerCylinder - (adjustedBlockNumber % blocksPerCylinder);
}

/*
 * Get cache pointer from block number.
 * From decompiled code: returns pointer to cached cylinder for given block.
 */
- (void *)_cachePointerFromBlockNumber:(unsigned)blockNumber
{
	id driveObject;
	int sectorSize;
	void *cacheBase;
	
	// Get drive object from offset 0x14c
	driveObject = *(id *)((char *)self + 0x14c);
	
	// Get sector size from offset 0x14 relative to drive object
	sectorSize = *(int *)((char *)driveObject + 0x14);
	
	// Get cache base pointer from offset 0x134
	cacheBase = *(void **)((char *)self + 0x134);
	
	// Calculate cache pointer: blockNumber * sectorSize + cacheBase
	return (void *)((char *)cacheBase + (blockNumber * sectorSize));
}

/*
 * Get cache pointer from cylinder number.
 * From decompiled code: returns pointer to cached cylinder data.
 */
- (void *)_cachePointerFromCylinderNumber:(unsigned)cylinderNumber
{
	id driveObject;
	int *geometryArray;
	int blockNumber;
	int sectorsPerTrack;
	int numHeads;
	int sectorSize;
	void *cacheBase;
	
	// Get drive object from offset 0x14c
	driveObject = *(id *)((char *)self + 0x14c);
	
	// Get geometry array pointer from offset 0x18 relative to drive object
	geometryArray = *(int **)((char *)driveObject + 0x18);
	
	// Get sectors per track from offset 0x8 relative to drive object
	sectorsPerTrack = *(int *)((char *)driveObject + 0x8);
	
	if (geometryArray == NULL) {
		// Fixed geometry: calculate block number from cylinder
		// blockNumber = cylinder * numHeads * sectorsPerTrack
		numHeads = *(int *)((char *)driveObject + 0x10);
		blockNumber = cylinderNumber * numHeads * sectorsPerTrack;
	} else {
		// Variable geometry: search for cylinder range
		// Array format: [startBlock, startCylinder, sectorsPerCyl, ...]
		while ((unsigned)geometryArray[1] <= cylinderNumber) {
			geometryArray += 3;  // Move to next entry
		}
		
		// Calculate block number within this geometry range
		// blockNumber = startBlock + (cyl - startCyl) * sectorsPerCyl * sectorsPerTrack
		blockNumber = geometryArray[0] + 
		             (cylinderNumber - geometryArray[1]) * 
		             geometryArray[2] * sectorsPerTrack;
	}
	
	// Get sector size from offset 0x14 relative to drive object
	sectorSize = *(int *)((char *)driveObject + 0x14);
	
	// Get cache base pointer from offset 0x134
	cacheBase = *(void **)((char *)self + 0x134);
	
	// Calculate cache pointer: blockNumber * sectorSize + cacheBase
	return (void *)((char *)cacheBase + (blockNumber * sectorSize));
}

/*
 * Calculate cylinder number from block number and get head/sector.
 * From decompiled code: converts LBA to CHS addressing.
 */
- (unsigned)_cylinderFromBlockNumber:(unsigned)blockNumber
                                head:(unsigned *)head
                              sector:(unsigned *)sector
{
	id driveObject;
	unsigned *geometryArray;
	unsigned sectorsPerTrack;
	unsigned numHeads;
	unsigned sectorsPerCylinder;
	unsigned long long temp;
	unsigned cylinderNumber;
	unsigned adjustedBlock;
	
	// Get drive object from offset 0x14c
	driveObject = *(id *)((char *)self + 0x14c);
	
	// Get geometry array pointer from offset 0x18 relative to drive object
	geometryArray = *(unsigned **)((char *)driveObject + 0x18);
	
	// Get sectors per track from offset 0x8 relative to drive object
	sectorsPerTrack = *(unsigned *)((char *)driveObject + 0x8);
	
	if (geometryArray == NULL) {
		// Fixed geometry conversion
		// Get number of heads from offset 0x10 relative to drive object
		numHeads = *(unsigned *)((char *)driveObject + 0x10);
		
		// Divide block number by sectors per track
		temp = (unsigned long long)blockNumber / (unsigned long long)numHeads;
		
		// Calculate head number if pointer provided
		if (head != NULL) {
			*head = (unsigned)(temp % (unsigned long long)sectorsPerTrack);
		}
		
		// Calculate sector number if pointer provided
		if (sector != NULL) {
			*sector = blockNumber % numHeads;
		}
		
		// Calculate cylinder number
		cylinderNumber = (unsigned)(temp / sectorsPerTrack);
		
	} else {
		// Variable geometry conversion
		// Search for the geometry range containing this block
		while (blockNumber < *geometryArray) {
			geometryArray += 3;  // Move to next entry
		}
		
		// Get sectors per cylinder from array entry at index 2
		sectorsPerCylinder = geometryArray[2];
		
		// Calculate adjusted block number relative to this range
		adjustedBlock = blockNumber - *geometryArray;
		
		// Divide adjusted block by sectors per cylinder
		temp = (unsigned long long)adjustedBlock / (unsigned long long)sectorsPerCylinder;
		
		// Calculate head number if pointer provided
		if (head != NULL) {
			*head = (unsigned)(temp % (unsigned long long)sectorsPerTrack);
		}
		
		// Calculate sector number if pointer provided
		if (sector != NULL) {
			*sector = adjustedBlock % sectorsPerCylinder;
		}
		
		// Calculate cylinder number (add starting cylinder from array[1])
		cylinderNumber = (unsigned)(temp / sectorsPerTrack) + geometryArray[1];
	}
	
	return cylinderNumber;
}

@end

/* End of Geometry.m */
